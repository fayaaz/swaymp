/* swaymp-touch: inject pointer motion + a left click through /dev/uinput.
 * Run as root (sudo). Used by overlay_demo.sh to show a touch on the waybar
 * cheatsheet button. Commands are executed in order:
 *   home            clamp the cursor to (0,0) with a large negative warp
 *   move X Y        relative pointer move
 *   click           BTN_LEFT press + release
 *   pause MS        sleep
 * example: sudo swaymp-touch home pause 300 move 82 20 pause 400 click
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <linux/uinput.h>
#include <linux/input.h>

static int fd = -1;

static void emit(int type, int code, int value)
{
    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = type;
    ev.code = code;
    ev.value = value;
    if (write(fd, &ev, sizeof(ev)) < 0) {
        perror("write event");
        exit(1);
    }
}

static void emit_sync(void) { emit(EV_SYN, 0, 0); }

static void move(int dx, int dy)
{
    emit(EV_REL, REL_X, dx);
    emit(EV_REL, REL_Y, dy);
    emit_sync();
}

static void click(void)
{
    emit(EV_KEY, BTN_LEFT, 1);
    emit_sync();
    usleep(120000);
    emit(EV_KEY, BTN_LEFT, 0);
    emit_sync();
}

static int open_dev(void)
{
    struct uinput_setup us;
    fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) { perror("open /dev/uinput"); return 1; }
    if (ioctl(fd, UI_SET_EVBIT, EV_REL) < 0 ||
        ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0 ||
        ioctl(fd, UI_SET_RELBIT, REL_X) < 0 ||
        ioctl(fd, UI_SET_RELBIT, REL_Y) < 0 ||
        ioctl(fd, UI_SET_KEYBIT, BTN_LEFT) < 0) {
        perror("UI_SET_*BIT");
        return 1;
    }
    memset(&us, 0, sizeof(us));
    us.id.bustype = BUS_VIRTUAL;
    us.id.vendor = 0x2131;
    us.id.product = 0x0001;
    strcpy(us.name, "swaymp-touch");
    if (ioctl(fd, UI_DEV_SETUP, &us) < 0) { perror("UI_DEV_SETUP"); return 1; }
    if (ioctl(fd, UI_DEV_CREATE) < 0) { perror("UI_DEV_CREATE"); return 1; }
    usleep(600000);
    return 0;
}

int main(int argc, char **argv)
{
    int i;
    if (argc < 2) {
        fprintf(stderr, "usage: swaymp-touch home|move X Y|click|pause MS [...]\n");
        return 2;
    }
    if (open_dev() != 0) return 1;
    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "home")) {
            move(-4000, -4000);
        } else if (!strcmp(argv[i], "move") && i + 2 < argc) {
            int dx = atoi(argv[i + 1]);
            int dy = atoi(argv[i + 2]);
            i += 2;
            move(dx, dy);
        } else if (!strcmp(argv[i], "click")) {
            click();
        } else if (!strcmp(argv[i], "pause") && i + 1 < argc) {
            long ms = atol(argv[++i]);
            struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };
            nanosleep(&ts, NULL);
        } else {
            fprintf(stderr, "unknown argument: %s\n", argv[i]);
            ioctl(fd, UI_DEV_DESTROY);
            return 2;
        }
    }
    usleep(200000);
    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return 0;
}
