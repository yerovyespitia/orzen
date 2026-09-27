#include <TargetConditionals.h>
#include "OrzenTorrentBridge.h"

#if TARGET_OS_OSX

#include <libtorrent/download_priority.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace lt = libtorrent;

struct OrzenTorrentSession {
    lt::session session;
};

struct OrzenTorrentHandle {
    lt::torrent_handle handle;
    std::string preferred_episode;
    std::string relative_file_path;
    int selected_file = -1;
};

static void copy_text(char *destination, int capacity, std::string const& value) {
    if (destination == nullptr || capacity <= 0) return;
    std::strncpy(destination, value.c_str(), static_cast<size_t>(capacity - 1));
    destination[capacity - 1] = '\0';
}

static std::string lowercase(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

static bool is_video(std::string const& path) {
    auto const lower = lowercase(path);
    for (auto const* extension : {".mkv", ".mp4", ".m4v", ".mov", ".avi", ".webm", ".ts"}) {
        if (lower.size() >= std::strlen(extension)
            && lower.compare(lower.size() - std::strlen(extension), std::strlen(extension), extension) == 0) {
            return true;
        }
    }
    return false;
}

static void select_video(OrzenTorrentHandle *torrent) {
    if (torrent->selected_file >= 0) return;
    auto const info = torrent->handle.torrent_file();
    if (!info) return;

    auto const& files = info->files();
    int selected = -1;
    std::int64_t largest = -1;
    auto const episode = lowercase(torrent->preferred_episode);
    for (int i = 0; i < files.num_files(); ++i) {
        lt::file_index_t const index{i};
        auto const path = files.file_path(index);
        if (!is_video(path)) continue;
        auto const size = files.file_size(index);
        if (!episode.empty() && lowercase(path).find(episode) != std::string::npos) {
            selected = i;
            break;
        }
        if (size > largest) {
            largest = size;
            selected = i;
        }
    }
    if (selected < 0) return;

    std::vector<lt::download_priority_t> priorities(
        static_cast<size_t>(files.num_files()), lt::dont_download);
    priorities[static_cast<size_t>(selected)] = lt::default_priority;
    torrent->handle.prioritize_files(priorities);
    torrent->selected_file = selected;
    torrent->relative_file_path = files.file_path(lt::file_index_t{selected});
}

static void *add_torrent(OrzenTorrentSession *session, lt::add_torrent_params params,
    const char *save_path, const char *preferred_episode, char *error, int error_length) {
    if (session == nullptr || save_path == nullptr) {
        copy_text(error, error_length, "Invalid torrent session or destination.");
        return nullptr;
    }
    params.save_path = save_path;
    lt::error_code ec;
    auto handle = session->session.add_torrent(std::move(params), ec);
    if (ec) {
        copy_text(error, error_length, ec.message());
        return nullptr;
    }
    auto *torrent = new OrzenTorrentHandle{handle, preferred_episode == nullptr ? "" : preferred_episode, "", -1};
    select_video(torrent);
    return torrent;
}

extern "C" void *orzen_torrent_session_create(void) {
    try { return new OrzenTorrentSession{}; }
    catch (...) { return nullptr; }
}

extern "C" void orzen_torrent_session_destroy(void *session) {
    delete static_cast<OrzenTorrentSession *>(session);
}

extern "C" void *orzen_torrent_add_magnet(void *session, const char *magnet,
    const char *save_path, const char *preferred_episode, char *error, int error_length) {
    if (magnet == nullptr) return nullptr;
    lt::error_code ec;
    auto params = lt::parse_magnet_uri(magnet, ec);
    if (ec) {
        copy_text(error, error_length, ec.message());
        return nullptr;
    }
    return add_torrent(static_cast<OrzenTorrentSession *>(session), std::move(params),
        save_path, preferred_episode, error, error_length);
}

extern "C" void *orzen_torrent_add_file(void *session, const char *torrent_path,
    const char *save_path, const char *preferred_episode, char *error, int error_length) {
    if (torrent_path == nullptr) return nullptr;
    try {
        auto params = lt::load_torrent_file(torrent_path);
        return add_torrent(static_cast<OrzenTorrentSession *>(session), std::move(params),
            save_path, preferred_episode, error, error_length);
    } catch (std::exception const& exception) {
        copy_text(error, error_length, exception.what());
        return nullptr;
    }
}

extern "C" void orzen_torrent_poll(void *opaque_torrent, OrzenTorrentSnapshot *snapshot) {
    if (opaque_torrent == nullptr || snapshot == nullptr) return;
    std::memset(snapshot, 0, sizeof(*snapshot));
    auto *torrent = static_cast<OrzenTorrentHandle *>(opaque_torrent);
    try {
        select_video(torrent);
        auto const status = torrent->handle.status();
        snapshot->has_metadata = torrent->selected_file >= 0;
        snapshot->download_rate = status.download_rate;
        if (status.errc) copy_text(snapshot->error_message,
            sizeof(snapshot->error_message), status.errc.message());
        if (torrent->selected_file < 0) return;

        auto const info = torrent->handle.torrent_file();
        auto const file_index = lt::file_index_t{torrent->selected_file};
        snapshot->file_size = info->files().file_size(file_index);
        auto const progress = torrent->handle.file_progress();
        if (static_cast<size_t>(torrent->selected_file) < progress.size()) {
            snapshot->downloaded_bytes = progress[static_cast<size_t>(torrent->selected_file)];
        }
        if (snapshot->file_size > 0) {
            snapshot->progress = std::min(1.0,
                static_cast<double>(snapshot->downloaded_bytes) / static_cast<double>(snapshot->file_size));
        }
        snapshot->is_finished = status.is_finished || snapshot->progress >= 1.0;
        copy_text(snapshot->relative_file_path,
            sizeof(snapshot->relative_file_path), torrent->relative_file_path);
    } catch (std::exception const& exception) {
        copy_text(snapshot->error_message, sizeof(snapshot->error_message), exception.what());
    }
}

extern "C" void orzen_torrent_pause(void *torrent) {
    if (torrent != nullptr) static_cast<OrzenTorrentHandle *>(torrent)->handle.pause();
}

extern "C" void orzen_torrent_resume(void *torrent) {
    if (torrent != nullptr) static_cast<OrzenTorrentHandle *>(torrent)->handle.resume();
}

extern "C" void orzen_torrent_remove(void *session, void *torrent) {
    if (torrent == nullptr) return;
    auto *handle = static_cast<OrzenTorrentHandle *>(torrent);
    if (session != nullptr) static_cast<OrzenTorrentSession *>(session)->session.remove_torrent(handle->handle);
    delete handle;
}

#else

#include <cstring>

extern "C" void *orzen_torrent_session_create(void) { return nullptr; }
extern "C" void orzen_torrent_session_destroy(void *) {}
extern "C" void *orzen_torrent_add_magnet(void *, const char *, const char *, const char *, char *, int) { return nullptr; }
extern "C" void *orzen_torrent_add_file(void *, const char *, const char *, const char *, char *, int) { return nullptr; }
extern "C" void orzen_torrent_poll(void *, OrzenTorrentSnapshot *snapshot) {
    if (snapshot != nullptr) std::memset(snapshot, 0, sizeof(*snapshot));
}
extern "C" void orzen_torrent_pause(void *) {}
extern "C" void orzen_torrent_resume(void *) {}
extern "C" void orzen_torrent_remove(void *, void *) {}

#endif
