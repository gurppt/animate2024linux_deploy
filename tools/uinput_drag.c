#include <errno.h>
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static int fd;

static void emit(int type, int code, int value)
{
    struct input_event ev = {0};
    ev.type = type;
    ev.code = code;
    ev.value = value;
    if (write(fd, &ev, sizeof(ev)) != sizeof(ev))
        fprintf(stderr, "uinput write: %s\n", strerror(errno));
}

static void sync_events(void)
{
    emit(EV_SYN, SYN_REPORT, 0);
}

static void pause_ms(long ms)
{
    struct timespec ts = {ms / 1000, (ms % 1000) * 1000000};
    nanosleep(&ts, NULL);
}

int main(int argc, char **argv)
{
    struct uinput_setup setup = {0};
    int steps = 100, dx = 2, dy = 1, delay = 12;
    int zigzag = 0;

    if (argc > 1) steps = atoi(argv[1]);
    if (argc > 2) dx = atoi(argv[2]);
    if (argc > 3) dy = atoi(argv[3]);
    if (argc > 4) delay = atoi(argv[4]);
    if (argc > 5 && !strcmp(argv[5], "zigzag")) zigzag = 1;

    if ((fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK)) < 0)
    {
        fprintf(stderr, "open /dev/uinput: %s\n", strerror(errno));
        return 1;
    }

    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_KEYBIT, BTN_LEFT);
    ioctl(fd, UI_SET_EVBIT, EV_REL);
    ioctl(fd, UI_SET_RELBIT, REL_X);
    ioctl(fd, UI_SET_RELBIT, REL_Y);

    snprintf(setup.name, UINPUT_MAX_NAME_SIZE, "Codex physical drag mouse");
    setup.id.bustype = BUS_USB;
    setup.id.vendor = 0x1209;
    setup.id.product = 0xc0de;
    setup.id.version = 1;
    if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0)
    {
        fprintf(stderr, "uinput setup: %s\n", strerror(errno));
        close(fd);
        return 1;
    }

    pause_ms(1200);
    emit(EV_KEY, BTN_LEFT, 1);
    sync_events();
    pause_ms(150);
    for (int i = 0; i < steps; i++)
    {
        emit(EV_REL, REL_X, dx);
        emit(EV_REL, REL_Y, zigzag && ((i / 5) & 1) ? -dy : dy);
        sync_events();
        pause_ms(delay);
    }
    pause_ms(100);
    emit(EV_KEY, BTN_LEFT, 0);
    sync_events();
    pause_ms(200);
    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return 0;
}
