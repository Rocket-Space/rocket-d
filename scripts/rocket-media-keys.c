#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <signal.h>
#include <time.h>
#include <linux/input.h>

#define MAX_DEVICES 16
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

static int open_input_devices(int *fds, int max) {
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

        /* Get device name */
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

        /* Check if this device has media/brightness keys */
        unsigned long keybits[KEY_MAX / (sizeof(unsigned long) * 8) + 1] = {0};
        if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybits)), keybits) < 0) {
            close(fd);
            continue;
        }

        int media_keys[] = {KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_MUTE,
                           KEY_BRIGHTNESSUP, KEY_BRIGHTNESSDOWN,
                           KEY_PLAYPAUSE, KEY_NEXTSONG, KEY_PREVIOUSSONG,
                           KEY_MICMUTE, KEY_MEDIA};

        int has_media = 0;
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

        /* Skip full keyboards - only grab dedicated media/hotkey devices */
        int has_letters = 0;
        for (int k = KEY_A; k <= KEY_Z; k++) {
            if (keybits[k / (sizeof(unsigned long) * 8)] & (1UL << (k % (sizeof(unsigned long) * 8)))) {
                has_letters = 1;
                break;
            }
        }
        if (has_letters) {
            fprintf(stderr, "rocket-media-keys: skipping keyboard: %s (%s)\n", name, path);
            close(fd);
            continue;
        }

        /* Grab the device exclusively */
        ioctl(fd, EVIOCGRAB, 1);
        fds[count++] = fd;
        fprintf(stderr, "rocket-media-keys: grabbed %s [%s]\n", path, name);
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

    int fds[MAX_DEVICES];
    int nfds = open_input_devices(fds, MAX_DEVICES);

    if (nfds == 0) {
        fprintf(stderr, "rocket-media-keys: no dedicated media key devices found\n");
        return 1;
    }

    fprintf(stderr, "rocket-media-keys: monitoring %d device(s)\n", nfds);

    long long last_time[KEY_MAX + 1] = {0};

    while (running) {
        fd_set rfds;
        FD_ZERO(&rfds);
        int maxfd = 0;

        for (int i = 0; i < nfds; i++) {
            FD_SET(fds[i], &rfds);
            if (fds[i] > maxfd) maxfd = fds[i];
        }

        struct timeval tv = {0, 100000};
        int ret = select(maxfd + 1, &rfds, NULL, NULL, &tv);
        if (ret < 0) break;

        for (int i = 0; i < nfds; i++) {
            if (!FD_ISSET(fds[i], &rfds)) continue;

            struct input_event ev;
            ssize_t n = read(fds[i], &ev, sizeof(ev));
            if (n != sizeof(ev)) continue;

            if (ev.type == EV_KEY && ev.code <= KEY_MAX) {
                long long now = time_ms();
                if (now - last_time[ev.code] >= COOLDOWN_MS) {
                    last_time[ev.code] = now;
                    handle_key(ev.code, ev.value);
                }
            }
        }
    }

    for (int i = 0; i < nfds; i++) {
        ioctl(fds[i], EVIOCGRAB, 0);
        close(fds[i]);
    }

    return 0;
}
