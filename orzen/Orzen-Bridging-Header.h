#import <mpv/client.h>
#import <mpv/render.h>
#import <mpv/render_gl.h>
#import <OpenGL/gl3.h>

void *orzen_mpv_get_proc_address(void *ctx, const char *name);

typedef struct {
    int audio_track_count;
    int subtitle_track_count;
    char audio_languages[512];
    char subtitle_languages[512];
} OrzenMediaTrackSnapshot;

int orzen_mpv_probe_tracks(const char *path, OrzenMediaTrackSnapshot *snapshot);

#import "Support/OrzenTorrentBridge.h"
