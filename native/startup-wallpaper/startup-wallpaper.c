// SPDX-License-Identifier: MIT
// A single-monitor startup still. No image decoding, GPU context, or input grab.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-layer-shell-client.h"
#include "presentation-time-client.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *shell;
static struct wl_surface *surface;
static struct wp_presentation *presentation;
static clockid_t presentation_clock = CLOCK_MONOTONIC;
struct frame { struct wl_buffer *buffer; uint32_t *pixels; bool busy; };
static struct frame frames[2];
static uint32_t *original;
static void *mapping;
static size_t frame_bytes;
static const char *ready_path;
static int width, height, scale;
static volatile sig_atomic_t running = 1;
static volatile sig_atomic_t retire_requested = 0;
static bool submitted = false, failed = false;
static bool configured = false;
static bool feedback_pending = false, display_acknowledged = false;
static double first_acknowledged;
static unsigned tick;
static bool static_scene;

static double now(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
}
static double uptime(void) {
    struct timespec time;
    clock_gettime(CLOCK_BOOTTIME, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
}
static void acknowledge_display(const char *method) {
    if (display_acknowledged) return;
    display_acknowledged = true;
    first_acknowledged = now();
    fprintf(stdout, "Bridge %s at uptime %.6f\n", method, uptime());
    fflush(stdout);
}
static bool can_retire(double current) {
    // Keep the brief indicator from being destroyed before its first display
    // acknowledgement. Apps already start concurrently and never wait on this.
    return retire_requested && display_acknowledged && current - first_acknowledged >= .15;
}
static void presentation_clock_id(void *data, struct wp_presentation *object, uint32_t clock_id) {
    (void)data; (void)object; presentation_clock = (clockid_t)clock_id;
}
static const struct wp_presentation_listener presentation_listener = { .clock_id = presentation_clock_id };
static void sync_output(void *data, struct wp_presentation_feedback *feedback, struct wl_output *output) {
    (void)data; (void)feedback; (void)output;
}
static void presented(void *data, struct wp_presentation_feedback *feedback, uint32_t seconds_hi,
                      uint32_t seconds_lo, uint32_t nanoseconds, uint32_t refresh,
                      uint32_t sequence_hi, uint32_t sequence_lo, uint32_t flags) {
    (void)data; (void)refresh; (void)sequence_hi; (void)sequence_lo;
    fprintf(stdout, "Bridge presentation timestamp %llu.%09u clock %d flags 0x%x\n",
            (unsigned long long)(((uint64_t)seconds_hi << 32) | seconds_lo), nanoseconds,
            (int)presentation_clock, flags);
    acknowledge_display("presented");
    feedback_pending = false;
    if (feedback) wp_presentation_feedback_destroy(feedback);
}
static void discarded(void *data, struct wp_presentation_feedback *feedback) {
    (void)data;
    fprintf(stdout, "Bridge frame discarded at uptime %.6f\n", uptime());
    fflush(stdout);
    feedback_pending = false;
    if (feedback) wp_presentation_feedback_destroy(feedback);
}
static const struct wp_presentation_feedback_listener feedback_listener = {
    .sync_output = sync_output, .presented = presented, .discarded = discarded
};
static void frame_done(void *data, struct wl_callback *callback, uint32_t timestamp) {
    (void)data; (void)timestamp;
    wl_callback_destroy(callback);
    // A frame callback is only a rendering hint, never label it presentation.
    acknowledge_display("frame-callback-fallback");
    feedback_pending = false;
}
static const struct wl_callback_listener frame_listener = { .done = frame_done };
static void released(void *data, struct wl_buffer *buffer) {
    (void)buffer; ((struct frame *)data)->busy = false;
}
static const struct wl_buffer_listener buffer_listener = { .release = released };
static void draw_indicator(struct frame *frame) {
    int radius = height / 70;
    if (radius < 5) radius = 5;
    if (radius > 40) radius = 40;
    int cx = width / 2, cy = height * 3 / 4;
    // Restore only this small region. No full-frame copying per animation tick.
    for (int y = cy - radius - 5; y <= cy + radius + 5; ++y) {
        if (y < 0 || y >= height) continue;
        for (int x = cx - radius - 5; x <= cx + radius + 5; ++x) {
            if (x < 0 || x >= width) continue;
            frame->pixels[y * width + x] = original[y * width + x];
        }
    }
    for (unsigned segment = 0; segment < 12; ++segment) {
        double angle = segment * 2 * 3.141592653589793 / 12;
        int sx = cx + (int)(sin(angle) * radius), sy = cy - (int)(cos(angle) * radius);
        unsigned alpha = 45 + ((segment + 12 - tick % 12) % 12) * 19;
        for (int y = sy - 2; y <= sy + 2; ++y) for (int x = sx - 2; x <= sx + 2; ++x) {
            if (x < 0 || x >= width || y < 0 || y >= height) continue;
            uint32_t bg = original[y * width + x], pixel = 0xff000000;
            for (unsigned shift = 0; shift < 24; shift += 8)
                pixel |= (((bg >> shift & 255) * (255 - alpha) + 255 * alpha) / 255) << shift;
            frame->pixels[y * width + x] = pixel;
        }
    }
}
static void paint(void) {
    struct frame *frame = !frames[0].busy ? &frames[0] : !frames[1].busy ? &frames[1] : NULL;
    if (!frame) return;
    if (!static_scene) draw_indicator(frame);
    frame->busy = true;
    wl_surface_attach(surface, frame->buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, width, height);
    if (!display_acknowledged && !feedback_pending) {
        feedback_pending = true;
        if (presentation) {
            struct wp_presentation_feedback *feedback = wp_presentation_feedback(presentation, surface);
            wp_presentation_feedback_add_listener(feedback, &feedback_listener, NULL);
        } else {
            struct wl_callback *callback = wl_surface_frame(surface);
            wl_callback_add_listener(callback, &frame_listener, NULL);
        }
    }
    wl_surface_commit(surface);
    ++tick;
}

static void stop(int signal_number) { (void)signal_number; running = 0; }
static void retire(int signal_number) { (void)signal_number; retire_requested = 1; }
static void synced(void *data, struct wl_callback *callback, uint32_t serial) {
    (void)data; (void)serial;
    wl_callback_destroy(callback);
    if (submitted) return;
    int fd = open(ready_path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (fd < 0) { failed = true; running = 0; return; }
    close(fd);
    submitted = true;
}
static const struct wl_callback_listener sync_listener = { .done = synced };
static void configure(void *data, struct zwlr_layer_surface_v1 *layer,
                      uint32_t serial, uint32_t logical_width, uint32_t logical_height) {
    (void)data;
    zwlr_layer_surface_v1_ack_configure(layer, serial);
    if (logical_width != (uint32_t)(width / scale) || logical_height != (uint32_t)(height / scale)) {
        fprintf(stderr, "Startup still: output size changed; using the regular wallpaper helper.\n");
        failed = true; running = 0; return;
    }
    wl_surface_set_buffer_scale(surface, scale);
    configured = true;
    paint();
    struct wl_callback *callback = wl_display_sync(display);
    wl_callback_add_listener(callback, &sync_listener, NULL);
}
static void closed(void *data, struct zwlr_layer_surface_v1 *layer) {
    (void)data; (void)layer; running = 0;
}
static const struct zwlr_layer_surface_v1_listener layer_listener = {
    .configure = configure, .closed = closed
};
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    (void)data;
    if (!strcmp(interface, wl_compositor_interface.name) && version >= 4)
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (!strcmp(interface, wl_shm_interface.name))
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (!strcmp(interface, zwlr_layer_shell_v1_interface.name))
        shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
    else if (!strcmp(interface, wp_presentation_interface.name)) {
        presentation = wl_registry_bind(registry, name, &wp_presentation_interface, 1);
        wp_presentation_add_listener(presentation, &presentation_listener, NULL);
    }
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener registry_listener = {
    .global = global, .global_remove = global_remove
};
static int dimension(const char *text) {
    char *end;
    errno = 0;
    long value = strtol(text, &end, 10);
    return errno || !*text || *end || value <= 0 || value > 16384 ? 0 : (int)value;
}
int main(int argc, char **argv) {
    const char *static_option = getenv("HYPR_STARTUP_STATIC");
    static_scene = static_option && !strcmp(static_option, "1");
    const char *verify = getenv("HYPR_STARTUP_VERIFY");
    const bool verification_mode = verify && !strcmp(verify, "1");
    if (argc != 6) {
        fprintf(stderr, "Usage: hypr-start-wall width height scale pixels.bgrx ready-file\n");
        return 2;
    }
    width = dimension(argv[1]); height = dimension(argv[2]); scale = dimension(argv[3]);
    if (!width || !height || !scale || width % scale || height % scale || scale > 8)
        return 2;
    int64_t bytes = (int64_t)width * height * 4;
    if (bytes > INT_MAX) return 2;
    int fd = open(argv[4], O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    struct stat info;
    if (fd < 0 || fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_size != bytes) {
        if (fd >= 0) close(fd);
        return 2;
    }
    ready_path = argv[5];
    frame_bytes = (size_t)bytes;
    original = mmap(NULL, frame_bytes, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (original == MAP_FAILED || bytes > INT_MAX / 2) return 2;
    fd = memfd_create("hypr-start-wall", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0 || ftruncate(fd, bytes * 2)) return 2;
    mapping = mmap(NULL, frame_bytes * 2, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapping == MAP_FAILED) { close(fd); return 2; }
    fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_SEAL);
    struct sigaction action = { .sa_handler = stop };
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL); sigaction(SIGINT, &action, NULL);
    action.sa_handler = retire; sigaction(SIGUSR1, &action, NULL);
    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "Bridge: Wayland connection failed.\n"); close(fd); return 2; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !compositor || !shm || !shell) {
        close(fd); wl_display_disconnect(display); return 2;
    }
    fprintf(stdout, "Bridge client version=3 presentation-feedback=%d verify=%d at uptime %.6f\n", presentation != NULL, verification_mode, uptime());
    fflush(stdout);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int)(bytes * 2));
    for (int i = 0; i < 2; ++i) {
        frames[i].pixels = (uint32_t *)((char *)mapping + i * frame_bytes);
        memcpy(frames[i].pixels, original, frame_bytes);
        frames[i].buffer = wl_shm_pool_create_buffer(pool, (int)(i * bytes), width, height, width * 4, WL_SHM_FORMAT_XRGB8888);
        wl_buffer_add_listener(frames[i].buffer, &buffer_listener, &frames[i]);
    }
    wl_shm_pool_destroy(pool); close(fd);
    surface = wl_compositor_create_surface(compositor);
    // This is visual-only: never cover desktop pointer or touch input,
    // including when the regular wallpaper daemon cannot take over.
    struct wl_region *input = wl_compositor_create_region(compositor);
    wl_surface_set_input_region(surface, input);
    wl_region_destroy(input);
    struct zwlr_layer_surface_v1 *layer = zwlr_layer_shell_v1_get_layer_surface(
        shell, surface, NULL, verification_mode ? ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY : ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, "hypr-startup-wallpaper");
    zwlr_layer_surface_v1_add_listener(layer, &layer_listener, NULL);
    zwlr_layer_surface_v1_set_anchor(layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(layer, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(layer, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
    wl_surface_commit(surface);
    double deadline = now() + 10, next_tick = now() + .08;
    double handoff_deadline = deadline;
    bool handoff_started = false;
    while (running && now() < deadline) {
        if (retire_requested && !handoff_started) {
            handoff_started = true;
            handoff_deadline = now() + 2;
        }
        if (can_retire(now())) break;
        if (handoff_started && now() >= handoff_deadline) {
            fprintf(stderr, "Bridge handoff timed out waiting for display acknowledgement.\n");
            break;
        }
        if (configured && now() >= next_tick) {
            paint();
            next_tick = now() + .08;
        }
        while (wl_display_prepare_read(display) != 0) {
            if (wl_display_dispatch_pending(display) < 0) goto cleanup;
        }
        struct pollfd event = { .fd = wl_display_get_fd(display), .events = POLLIN };
        if (wl_display_flush(display) < 0) {
            if (errno != EAGAIN) { wl_display_cancel_read(display); break; }
            event.events |= POLLOUT;
        }
        int result = poll(&event, 1, 20);
        if (result > 0 && (event.revents & POLLIN)) {
            if (wl_display_read_events(display) < 0) break;
        } else wl_display_cancel_read(display);
        if ((result < 0 && errno != EINTR) || (event.revents & (POLLERR | POLLHUP))) break;
        if (wl_display_dispatch_pending(display) < 0) break;
    }
cleanup:
    fprintf(stdout, "Bridge retired at uptime %.6f (display-acknowledged=%d, handoff=%d)\n",
            uptime(), display_acknowledged, (int)retire_requested);
    fflush(stdout);
    zwlr_layer_surface_v1_destroy(layer); wl_surface_destroy(surface);
    for (int i = 0; i < 2; ++i) wl_buffer_destroy(frames[i].buffer);
    if (presentation) wp_presentation_destroy(presentation);
    wl_registry_destroy(registry); wl_display_disconnect(display);
    munmap(mapping, frame_bytes * 2); munmap(original, frame_bytes);
    return failed || !submitted || !display_acknowledged ? 2 : 0;
}
