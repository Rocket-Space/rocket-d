#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <signal.h>
#include <time.h>
#include <linux/input.h>

#define MAX_DEVICES 32
#define COOLDOWN_MS 150

static volatile int running = 1;

static void handle_signal(int sig) {
    (void)sig;
    running = 0;
}

static long long time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int is_media_key(int code) {
    switch (code) {
        case KEY_VOLUMEUP: case KEY_VOLUMEDOWN: case KEY_MUTE:
        case KEY_BRIGHTNESSUP: case KEY_BRIGHTNESSDOWN:
        case KEY_PLAYPAUSE: case KEY_NEXTSONG: case KEY_PREVIOUSSONG:
        case KEY_STOPCD: case KEY_MICMUTE: case KEY_MEDIA:
            return 1;
    }
    return 0;
}

static int is_meta_key(int code) {
    return code == KEY_LEFTMETA || code == KEY_RIGHTMETA;
}

static int is_shift_key(int code) {
    return code == KEY_LEFTSHIFT || code == KEY_RIGHTSHIFT;
}

static int is_number_key(int code, int *num) {
    if (code >= KEY_1 && code <= KEY_9) { *num = code - KEY_1 + 1; return 1; }
    if (code == KEY_0) { *num = 10; return 1; }
    return 0;
}

typedef struct {
    int fd;
} DeviceEntry;

static int open_keyboards(DeviceEntry *devs, int max) {
    char path[256], name[256];
    int count = 0;
    DIR *dir = opendir("/dev/input");
    if (!dir) return 0;

    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL && count < max) {
        if (strncmp(ent->d_name, "event", 5) != 0)
            continue;
        snprintf(path, sizeof(path), "/dev/input/%s", ent->d_name);
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;

        name[0] = '\0';
        ioctl(fd, EVIOCGNAME(sizeof(name)), name);

        unsigned long bits = 0;
        if (ioctl(fd, EVIOCGBIT(0, sizeof(bits)), &bits) < 0) {
            close(fd); continue;
        }
        if (!(bits & (1 << EV_KEY))) {
            close(fd); continue;
        }

        unsigned long keybits[KEY_MAX / (sizeof(unsigned long) * 8) + 1] = {0};
        if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybits)), keybits) < 0) {
            close(fd); continue;
        }

        int has_letters = 0;
        for (int k = KEY_A; k <= KEY_Z; k++) {
            if (keybits[k / (sizeof(unsigned long) * 8)] & (1UL << (k % (sizeof(unsigned long) * 8)))) {
                has_letters = 1; break;
            }
        }

        if (!has_letters) {
            close(fd); continue;
        }

        devs[count].fd = fd;
        fprintf(stderr, "rocket-media-keys: monitoring keyboard: %s [%s]\n", path, name);
        count++;
    }
    closedir(dir);
    return count;
}

static void run_cmd(const char *cmd) {
    if (fork() == 0) {
        setsid();
        execl("/bin/sh", "sh", "-c", cmd, NULL);
        _exit(1);
    }
}

static void handle_media_key(int code) {
    switch (code) {
        case KEY_BRIGHTNESSUP:    run_cmd("brightnessctl s 5%+"); break;
        case KEY_BRIGHTNESSDOWN:  run_cmd("brightnessctl s 5%-"); break;
        case KEY_VOLUMEUP:        run_cmd("pamixer -i 5"); break;
        case KEY_VOLUMEDOWN:      run_cmd("pamixer -d 5"); break;
        case KEY_MUTE: case KEY_MEDIA: run_cmd("pamixer -t"); break;
        case KEY_MICMUTE:         run_cmd("pamixer --source @DEFAULT_SOURCE@ -t"); break;
        case KEY_PLAYPAUSE: case KEY_STOPCD: run_cmd("playerctl play-pause"); break;
        case KEY_NEXTSONG:        run_cmd("playerctl next"); break;
        case KEY_PREVIOUSSONG:    run_cmd("playerctl previous"); break;
    }
}

int main(void) {
    signal(SIGTERM, handle_signal);
    signal(SIGINT, handle_signal);

    DeviceEntry devs[MAX_DEVICES];
    int nfds = open_keyboards(devs, MAX_DEVICES);

    if (nfds == 0) {
        fprintf(stderr, "rocket-media-keys: no keyboards found\n");
        return 1;
    }

    fprintf(stderr, "rocket-media-keys: monitoring %d keyboard(s)\n", nfds);

    long long last_time[KEY_MAX + 1] = {0};
    int meta_down = 0;
    int alt_down = 0;
    int shift_down = 0;

    while (running) {
        fd_set rfds;
        FD_ZERO(&rfds);
        int maxfd = 0;

        for (int i = 0; i < nfds; i++) {
            FD_SET(devs[i].fd, &rfds);
            if (devs[i].fd > maxfd) maxfd = devs[i].fd;
        }

        struct timeval tv = {0, 100000};
        int ret = select(maxfd + 1, &rfds, NULL, NULL, &tv);
        if (ret < 0) break;

        for (int i = 0; i < nfds; i++) {
            if (!FD_ISSET(devs[i].fd, &rfds)) continue;

            struct input_event ev;
            ssize_t n = read(devs[i].fd, &ev, sizeof(ev));
            if (n != sizeof(ev)) continue;

            if (ev.type != EV_KEY || ev.code > KEY_MAX) continue;

            if (!is_media_key(ev.code) && !is_meta_key(ev.code)
                && ev.code != KEY_LEFTALT && ev.code != KEY_RIGHTALT
                && ev.code != KEY_LEFTSHIFT && ev.code != KEY_RIGHTSHIFT
                && !meta_down)
                continue;

            int code = ev.code;
            int value = ev.value;

            if (is_meta_key(code)) {
                if (value == 1) { meta_down = 1; }
                else if (value == 0) { meta_down = 0; }
                continue;
            }

            if (is_shift_key(code)) {
                shift_down = (value > 0) ? 1 : 0;
            }

            if (code == KEY_LEFTALT || code == KEY_RIGHTALT) {
                alt_down = (value > 0) ? 1 : 0;
            }

            if (meta_down && value == 1) {
                int num;

                switch (code) {
                    case KEY_SPACE:
                        if (alt_down)
                            run_cmd("rocket-d-menu");
                        else
                            run_cmd("wofi --show drun -config $HOME/.config/wofi/config -style $HOME/.config/wofi/style.css");
                        break;
                    case KEY_ENTER:
                        run_cmd("kitty");
                        break;
                    default:
                        if (shift_down && is_number_key(code, &num)) {
                            char cmd[128];
                            snprintf(cmd, sizeof(cmd),
                                "qdbus6 org.kde.kglobalaccel /component/kwin "
                                "org.kde.kglobalaccel.Component.invokeShortcut "
                                "\"Window to Desktop %d\"", num);
                            run_cmd(cmd);
                        }
                        else if (!shift_down && is_number_key(code, &num)) {
                            char cmd[128];
                            snprintf(cmd, sizeof(cmd),
                                "qdbus6 org.kde.KWin /KWin "
                                "org.kde.KWin.setCurrentDesktop %d", num);
                            run_cmd(cmd);
                        }
                        break;
                }
            }

            if (is_media_key(code) && (value == 1 || value == 2)) {
                long long now = time_ms();
                if (now - last_time[code] >= COOLDOWN_MS) {
                    last_time[code] = now;
                    handle_media_key(code);
                }
            }
        }
    }

    for (int i = 0; i < nfds; i++) {
        close(devs[i].fd);
    }

    return 0;
}
