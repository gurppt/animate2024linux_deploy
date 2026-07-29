#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

static const char *families[] =
{
    "Segoe UI",
    "Segoe UI Semibold",
    "Tahoma",
    "Microsoft Sans Serif",
    "Arial",
    "Times New Roman",
    "Adobe Clean",
    NULL
};

static const char *samples[] =
{
    "8", "10", "99", "100", "Brush Size", "Properties", "Color", "Swatches", NULL
};

int main(void)
{
    HDC dc = CreateCompatibleDC(NULL);
    int dpi = GetDeviceCaps(dc, LOGPIXELSY);
    unsigned int i, j;
    printf("FONT-PROBE: dpi_y=%d\n", dpi);
    for (i = 0; families[i]; i++)
    {
        HFONT font = CreateFontA(-MulDiv(9, dpi, 72), 0, 0, 0, FW_NORMAL,
                                 FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                 OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                 DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
                                 families[i]);
        HGDIOBJ previous = SelectObject(dc, font);
        TEXTMETRICA metrics;
        char resolved[LF_FACESIZE] = {0};
        GetTextFaceA(dc, sizeof(resolved), resolved);
        GetTextMetricsA(dc, &metrics);
        printf("FONT family=\"%s\" resolved=\"%s\" height=%ld ascent=%ld descent=%ld ave=%ld max=%ld weight=%ld\n",
               families[i], resolved, metrics.tmHeight, metrics.tmAscent,
               metrics.tmDescent, metrics.tmAveCharWidth, metrics.tmMaxCharWidth,
               metrics.tmWeight);
        for (j = 0; samples[j]; j++)
        {
            SIZE size;
            GetTextExtentPoint32A(dc, samples[j], (int)lstrlenA(samples[j]), &size);
            printf("TEXT family=\"%s\" sample=\"%s\" width=%ld height=%ld\n",
                   families[i], samples[j], size.cx, size.cy);
        }
        SelectObject(dc, previous);
        DeleteObject(font);
    }
    DeleteDC(dc);
    return 0;
}
