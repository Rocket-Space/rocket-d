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
#define COOLDOWN_MS 100

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
    int is_keyboard;
} DeviceEntry;

static int open_devices(DeviceEntry *devs, int max) {
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

        int has_media = 0;
        int media_keys[] = {KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_MUTE,
                           KEY_BRIGHTNESSUP, KEY_BRIGHTNESSDOWN,
                           KEY_PLAYPAUSE, KEY_NEXTSONG, KEY_PREVIOUSSONG,
                           KEY_STOPCD, KEY_MICMUTE, KEY_MEDIA};
        for (int i = 0; i < (int)(sizeof(media_keys)/sizeof(media_keys[0])); i++) {
            int k = media_keys[i];
            if (keybits[k / (sizeof(unsigned long) * 8)] & (1UL << (k % (sizeof(unsigned long) * 8)))) {
                has_media = 1; break;
            }
        }

        if (!has_letters && !has_media) {
            close(fd); continue;
        }

        devs[count].fd = fd;
        devs[count].is_keyboard = has_letters;
        fprintf(stderr, "rocket-media-keys: %s %s [%s]\n",
                has_letters ? "monitoring keyboard:" : "monitoring media device:",
                path, name);
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
        case KEY_BRIGHTNESSUP:    run_cmd("brightnessctl s 10%+ -q 2>/dev/null; p=$(brightnessctl -m | awk -F, '{gsub(/%/,\"\",$4); print $4}'); notify-send -a brightness -h string:x-canonical-private-synchronous:brightness -h int:value:$p \"$p%\" -t 1000 2>/dev/null"); break;
        case KEY_BRIGHTNESSDOWN:  run_cmd("brightnessctl s 10%- -q 2>/dev/null; [ $(brightnessctl get) -eq 0 ] && brightnessctl set 1 -q 2>/dev/null; p=$(brightnessctl -m | awk -F, '{gsub(/%/,\"\",$4); print $4}'); notify-send -a brightness -h string:x-canonical-private-synchronous:brightness -h int:value:$p \"$p%\" -t 1000 2>/dev/null"); break;
        case KEY_VOLUMEUP:        run_cmd("pamixer -i 5; p=$(pamixer --get-volume); [ $(pamixer --get-mute) = 'true' ] && notify-send -a volume -h string:x-canonical-private-synchronous:volume -i audio-volume-muted \"Muted\" -t 1000 2>/dev/null || notify-send -a volume -h string:x-canonical-private-synchronous:volume -h int:value:$p \"$p%\" -t 1000 2>/dev/null"); break;
        case KEY_VOLUMEDOWN:      run_cmd("pamixer -d 5; p=$(pamixer --get-volume); [ $(pamixer --get-mute) = 'true' ] && notify-send -a volume -h string:x-canonical-private-synchronous:volume -i audio-volume-muted \"Muted\" -t 1000 2>/dev/null || notify-send -a volume -h string:x-canonical-private-synchronous:volume -h int:value:$p \"$p%\" -t 1000 2>/dev/null"); break;
        case KEY_MUTE: case KEY_MEDIA: run_cmd("pamixer -t; [ $(pamixer --get-mute) = 'true' ] && notify-send -a volume -h string:x-canonical-private-synchronous:volume -i audio-volume-muted \"Muted\" -t 1000 2>/dev/null || notify-send -a volume -h string:x-canonical-private-synchronous:volume -h int:value:$(pamixer --get-volume) \"$(pamixer --get-volume)%\" -t 1000 2>/dev/null"); break;
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
    int nfds = open_devices(devs, MAX_DEVICES);

    if (nfds == 0) {
        fprintf(stderr, "rocket-media-keys: no keyboards found\n");
        return 1;
    }

    fprintf(stderr, "rocket-media-keys: monitoring %d device(s)\n", nfds);

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

            int code = ev.code;
            int value = ev.value;

            /* Media keys: handle on all devices */
            if (is_media_key(code) && (value == 1 || value == 2)) {
                long long now = time_ms();
                long long cd = (code == KEY_BRIGHTNESSUP || code == KEY_BRIGHTNESSDOWN)
                               ? 80 : 150;
                if (now - last_time[code] >= cd) {
                    last_time[code] = now;
                    handle_media_key(code);
                }
            }

            /* Meta combos: only on keyboard devices */
            if (!devs[i].is_keyboard) continue;

            if (!is_media_key(code) && !is_meta_key(code)
                && code != KEY_LEFTALT && code != KEY_RIGHTALT
                && code != KEY_LEFTSHIFT && code != KEY_RIGHTSHIFT
                && !meta_down)
                continue;

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
                    case KEY_B:
                        run_cmd("if pgrep -x waybar > /dev/null; then killall waybar; else waybar &>/dev/null & fi");
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
        }
    }

    for (int i = 0; i < nfds; i++) {
        close(devs[i].fd);
    }

    return 0;
}
