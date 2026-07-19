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
    running = 0;
}

static long long time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int is_media_key(int code) {
    switch (code) {
        case KEY_VOLUMEUP:
        case KEY_VOLUMEDOWN:
        case KEY_MUTE:
        case KEY_BRIGHTNESSUP:
        case KEY_BRIGHTNESSDOWN:
        case KEY_PLAYPAUSE:
        case KEY_NEXTSONG:
        case KEY_PREVIOUSSONG:
        case KEY_STOPCD:
        case KEY_MICMUTE:
        case KEY_MEDIA:
            return 1;
    }
    return 0;
}

typedef struct {
    int fd;
    int grab; /* 1=grabbed exclusively, 0=monitor only */
} DeviceEntry;

static int open_input_devices(DeviceEntry *devs, int max) {
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
            close(fd);
            continue;
        }
        if (!(bits & (1 << EV_KEY))) {
            close(fd);
            continue;
        }

        unsigned long keybits[KEY_MAX / (sizeof(unsigned long) * 8) + 1] = {0};
        if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybits)), keybits) < 0) {
            close(fd);
            continue;
        }

        int has_media = 0;
        int media_keys[] = {KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_MUTE,
                           KEY_BRIGHTNESSUP, KEY_BRIGHTNESSDOWN,
                           KEY_PLAYPAUSE, KEY_NEXTSONG, KEY_PREVIOUSSONG,
                           KEY_STOPCD, KEY_MICMUTE, KEY_MEDIA};
        for (int i = 0; i < (int)(sizeof(media_keys)/sizeof(media_keys[0])); i++) {
            int k = media_keys[i];
            if (keybits[k / (sizeof(unsigned long) * 8)] & (1UL << (k % (sizeof(unsigned long) * 8)))) {
                has_media = 1;
                break;
            }
        }

        if (!has_media) {
            close(fd);
            continue;
        }

        /* Check if this is a full keyboard (has letter keys) */
        int has_letters = 0;
        for (int k = KEY_A; k <= KEY_Z; k++) {
            if (keybits[k / (sizeof(unsigned long) * 8)] & (1UL << (k % (sizeof(unsigned long) * 8)))) {
                has_letters = 1;
                break;
            }
        }

        devs[count].fd = fd;
        if (has_letters) {
            /* Keyboard: monitor only, don't grab */
            devs[count].grab = 0;
            fprintf(stderr, "rocket-media-keys: monitoring keyboard: %s [%s]\n", path, name);
        } else {
            /* Dedicated media device: grab exclusively */
            ioctl(fd, EVIOCGRAB, 1);
            devs[count].grab = 1;
            fprintf(stderr, "rocket-media-keys: grabbed %s [%s]\n", path, name);
        }
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

static void handle_key(int code, int value) {
    if (value != 1) return;

    switch (code) {
        case KEY_BRIGHTNESSUP:
            run_cmd("brightnessctl s 5%+");
            break;
        case KEY_BRIGHTNESSDOWN:
            run_cmd("brightnessctl s 5%-");
            break;
        case KEY_VOLUMEUP:
            run_cmd("pamixer -i 5");
            break;
        case KEY_VOLUMEDOWN:
            run_cmd("pamixer -d 5");
            break;
        case KEY_MUTE:
        case KEY_MEDIA:
            run_cmd("pamixer -t");
            break;
        case KEY_MICMUTE:
            run_cmd("pamixer --source @DEFAULT_SOURCE@ -t");
            break;
        case KEY_PLAYPAUSE:
        case KEY_STOPCD:
            run_cmd("playerctl play-pause");
            break;
        case KEY_NEXTSONG:
            run_cmd("playerctl next");
            break;
        case KEY_PREVIOUSSONG:
            run_cmd("playerctl previous");
            break;
    }
}

int main(void) {
    signal(SIGTERM, handle_signal);
    signal(SIGINT, handle_signal);

    DeviceEntry devs[MAX_DEVICES];
    int nfds = open_input_devices(devs, MAX_DEVICES);

    if (nfds == 0) {
        fprintf(stderr, "rocket-media-keys: no input devices with media keys found\n");
        return 1;
    }

    fprintf(stderr, "rocket-media-keys: monitoring %d device(s)\n", nfds);

    long long last_time[KEY_MAX + 1] = {0};

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

            if (ev.type == EV_KEY && ev.code <= KEY_MAX) {
                /* For non-grabbed keyboards, only process media keys */
                if (!devs[i].grab && !is_media_key(ev.code))
                    continue;

                long long now = time_ms();
                if (now - last_time[ev.code] >= COOLDOWN_MS) {
                    last_time[ev.code] = now;
                    handle_key(ev.code, ev.value);
                }
            }
        }
    }

    for (int i = 0; i < nfds; i++) {
        if (devs[i].grab)
            ioctl(devs[i].fd, EVIOCGRAB, 0);
        close(devs[i].fd);
    }

    return 0;
}
