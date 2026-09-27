#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int has_metadata;
    int is_finished;
    double progress;
    int64_t file_size;
    int64_t downloaded_bytes;
    int download_rate;
    char relative_file_path[4096];
    char error_message[512];
} OrzenTorrentSnapshot;

void *orzen_torrent_session_create(void);
void orzen_torrent_session_destroy(void *session);
void *orzen_torrent_add_magnet(void *session, const char *magnet, const char *save_path, const char *preferred_episode, char *error, int error_length);
void *orzen_torrent_add_file(void *session, const char *torrent_path, const char *save_path, const char *preferred_episode, char *error, int error_length);
void orzen_torrent_poll(void *torrent, OrzenTorrentSnapshot *snapshot);
void orzen_torrent_pause(void *torrent);
void orzen_torrent_resume(void *torrent);
void orzen_torrent_remove(void *session, void *torrent);

#ifdef __cplusplus
}
#endif
