#include <TargetConditionals.h>

#if TARGET_OS_OSX
#include "../Orzen-Bridging-Header.h"
#include <dlfcn.h>
#include <ctype.h>
#include <stdio.h>
#include <string.h>

void *orzen_mpv_get_proc_address(void *ctx, const char *name) {
    (void)ctx;
    return dlsym(RTLD_DEFAULT, name);
}

static void append_language(char *buffer, size_t capacity, const char *language) {
    if (language == NULL || language[0] == '\0' || strcmp(language, "und") == 0) return;
    size_t length = strlen(buffer);
    size_t value_length = strlen(language);
    if (length + value_length + 2 >= capacity) return;
    if (length > 0) buffer[length++] = ',';
    memcpy(buffer + length, language, value_length + 1);
}

static int contains_ignore_case(const char *text, const char *needle) {
    if (text == NULL || needle == NULL) return 0;
    for (const char *start = text; *start != '\0'; ++start) {
        const char *a = start;
        const char *b = needle;
        while (*a != '\0' && *b != '\0' && tolower((unsigned char)*a) == tolower((unsigned char)*b)) {
            ++a;
            ++b;
        }
        if (*b == '\0') return 1;
    }
    return 0;
}

int orzen_mpv_probe_tracks(const char *path, OrzenMediaTrackSnapshot *snapshot) {
    if (path == NULL || snapshot == NULL) return 0;
    memset(snapshot, 0, sizeof(*snapshot));
    mpv_handle *handle = mpv_create();
    if (handle == NULL) return 0;
    mpv_set_option_string(handle, "config", "no");
    mpv_set_option_string(handle, "vo", "null");
    mpv_set_option_string(handle, "ao", "null");
    mpv_set_option_string(handle, "pause", "yes");
    if (mpv_initialize(handle) < 0) {
        mpv_terminate_destroy(handle);
        return 0;
    }

    const char *command[] = {"loadfile", path, "replace", NULL};
    if (mpv_command(handle, command) < 0) {
        mpv_terminate_destroy(handle);
        return 0;
    }

    int loaded = 0;
    for (int attempt = 0; attempt < 10; ++attempt) {
        mpv_event *event = mpv_wait_event(handle, 1.0);
        if (event->event_id == MPV_EVENT_FILE_LOADED) { loaded = 1; break; }
        if (event->event_id == MPV_EVENT_END_FILE || event->event_id == MPV_EVENT_SHUTDOWN) break;
    }
    if (!loaded) {
        mpv_terminate_destroy(handle);
        return 0;
    }

    int64_t count = 0;
    if (mpv_get_property(handle, "track-list/count", MPV_FORMAT_INT64, &count) < 0) {
        mpv_terminate_destroy(handle);
        return 0;
    }
    for (int64_t index = 0; index < count; ++index) {
        char property[80];
        snprintf(property, sizeof(property), "track-list/%lld/type", (long long)index);
        char *type = mpv_get_property_string(handle, property);
        if (type == NULL) continue;
        int is_audio = strcmp(type, "audio") == 0;
        int is_subtitle = strcmp(type, "sub") == 0;
        mpv_free(type);
        if (!is_audio && !is_subtitle) continue;

        if (is_audio) snapshot->audio_track_count++;
        if (is_subtitle) snapshot->subtitle_track_count++;
        snprintf(property, sizeof(property), "track-list/%lld/lang", (long long)index);
        char *language = mpv_get_property_string(handle, property);
        snprintf(property, sizeof(property), "track-list/%lld/title", (long long)index);
        char *title = mpv_get_property_string(handle, property);
        const char *tag = language;
        if (language != NULL && (strcmp(language, "spa") == 0 || strcmp(language, "es") == 0)) {
            if (contains_ignore_case(title, "latin") || contains_ignore_case(title, "latino")) {
                tag = "es-419";
            } else if (contains_ignore_case(title, "castellano")) {
                tag = "es-ES";
            }
        }
        if (is_audio) append_language(snapshot->audio_languages, sizeof(snapshot->audio_languages), tag);
        if (is_subtitle) append_language(snapshot->subtitle_languages, sizeof(snapshot->subtitle_languages), tag);
        if (title != NULL) mpv_free(title);
        if (language != NULL) mpv_free(language);
    }
    mpv_terminate_destroy(handle);
    return 1;
}
#else
void *orzen_mpv_get_proc_address(void *ctx, const char *name) {
    (void)ctx;
    (void)name;
    return 0;
}
#endif
