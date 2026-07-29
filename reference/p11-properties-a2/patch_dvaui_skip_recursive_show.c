#include <errno.h>
#include <stdio.h>
#include <string.h>

struct site {
    long file_offset;
    unsigned char expected[5];
};

int main(int argc, char **argv)
{
    /*
     * Both UI_Show implementations finish their own visibility/invalidation
     * work and then call UI_DispatchNodeChange(NodeChange::Show = 3).
     * That dispatcher recursively visits the complete freshly rebuilt
     * Properties subtree.  Suppress only those two Show notifications; all
     * SetParent, ChildAdded/Removed, rect, scale and generic dispatches remain
     * byte-identical.
     *
     * PE mapping for .text: raw = RVA - 0x1000 + 0x400.
     */
    static const struct site sites[] = {
        { 0x49432c, { 0xe8, 0x7f, 0xf6, 0xf9, 0xff } }, /* RVA 0x494f2c */
        { 0x481eff, { 0xe8, 0xac, 0x1a, 0xfb, 0xff } }  /* RVA 0x482aff */
    };
    static const unsigned char patch[5] = {
        0x90, 0x90, 0x90, 0x90, 0x90
    };
    unsigned char current[sizeof(patch)];
    FILE *file;
    size_t i;

    if (argc != 2) {
        fprintf(stderr, "usage: %s dvaui.dll\n", argv[0]);
        return 2;
    }
    if (!(file = fopen(argv[1], "r+b"))) {
        fprintf(stderr, "%s: %s\n", argv[1], strerror(errno));
        return 1;
    }
    for (i = 0; i < sizeof(sites) / sizeof(sites[0]); ++i) {
        if (fseek(file, sites[i].file_offset, SEEK_SET) ||
            fread(current, 1, sizeof(current), file) != sizeof(current) ||
            memcmp(current, sites[i].expected, sizeof(current))) {
            fprintf(stderr, "refus: octets inattendus au site %zu\n", i);
            fclose(file);
            return 1;
        }
        if (fseek(file, sites[i].file_offset, SEEK_SET) ||
            fwrite(patch, 1, sizeof(patch), file) != sizeof(patch)) {
            fputs("echec d'ecriture\n", stderr);
            fclose(file);
            return 1;
        }
    }
    fclose(file);
    return 0;
}
