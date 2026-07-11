# Orzen

Orzen is a native, local-first media hub for macOS and iPhone. It brings
catalog discovery, personal collections, Stremio-compatible addons, subtitles,
and stream playback into a cinematic SwiftUI interface built for Apple
platforms.

![Orzen home screen](docs/images/orzen-home.png)

## Highlights

- Browse featured, popular, new, genre, movie, and series catalogs powered by
  Cinemeta.
- Search movies and series, open rich title details, and explore seasons and
  episodes.
- Keep a personal library with Watchlist, Watching, Watched, Dropped, and
  Favorites collections.
- Install and configure Stremio-compatible addons from their manifest URLs to
  resolve streams and subtitles.
- Resume films and episodes, remember audio and subtitle selections, and move
  through a series with next-episode support.
- Play compatible direct HTTP/HTTPS streams with the native player; macOS can
  also use VLC or libmpv for broader format compatibility.
- Keep browsing usable during network failures with local fallback content and
  cached Cinemeta catalog data.

## Platforms

Orzen is a universal SwiftUI project with dedicated layouts and playback flows
for the Apple platforms it currently targets:

| Platform | Minimum version | Experience |
| --- | --- | --- |
| macOS | 14.2 | Full desktop interface with sidebar navigation and native, VLC, and libmpv playback options. |
| iPhone | iOS 17 | Touch-first layout with native AVFoundation playback for compatible direct streams. |

The macOS app uses a hidden-title-bar window with a minimum size of 1280 × 780.
On iPhone, the player can present in landscape while the rest of the app stays
portrait-oriented.

## Features

### Discover

- Home shelves for featured titles, in-progress viewing, watchlist items, and
  curated movie and series sections.
- Dedicated Movies and Series catalog screens with filters.
- Search across remote Cinemeta results and locally available fallback items.
- Artwork-led title pages with metadata, descriptions, seasons, episodes, and
  available sources.

### Organize

- Add titles to Favorites, Watchlist, Watched, or Dropped.
- Automatically maintain the Watching row from saved playback progress.
- Persist collections, watch history, resume positions, and track preferences
  locally on the device.

### Addons and playback

- Validate, install, enable, disable, and configure Stremio-compatible addon
  manifests.
- Collect stream sources and external subtitles from enabled addons.
- Select the source, audio track, subtitle track, and subtitle preferences.
- Use AVFoundation for direct playback; use VLC or libmpv on macOS when a
  stream needs a broader playback engine.
- Save progress and continue from the previous position; completed episodes can
  advance to the next one.

## Architecture

The project is organized around focused SwiftUI views and reusable domain
services:

```text
orzen/
├── Components/       Reusable catalog, title-detail, playback, and control UI
├── Features/         Home, search, movies, series, collections, and addons
├── Models/           Catalog, stream, subtitle, and playback domain models
├── Services/         Cinemeta, Stremio, subtitle, source, and player services
├── Stores/           Observable app state, caches, collections, and progress
├── Support/          Platform support and the libmpv OpenGL bridge
├── Assets.xcassets/  App icons, accent color, and visual assets
├── ContentView.swift App-level navigation routing
├── Sidebar.swift     Desktop shell and shared layout metrics
└── OrzenApp.swift    App entry point and platform window configuration
```

## Technology

- Swift and SwiftUI
- Swift concurrency (`async` / `await`) and actor-based caches
- `URLSession`, `UserDefaults`, and Keychain-backed local storage
- Cinemeta catalog metadata
- Stremio-compatible manifests, stream sources, and subtitles
- AVFoundation, VLCKit, and libmpv-based playback integrations
- SF Symbols and native Apple platform APIs

## Requirements

- Xcode with SwiftUI support
- macOS 14.2 or later to run the desktop target
- iOS 17 or later to run the iPhone target
- Internet access for live Cinemeta metadata and addon-provided sources
- CocoaPods, for the VLC integration:

  ```sh
  gem install cocoapods
  pod install
  ```

- Optional, on macOS: Homebrew `mpv` when building with libmpv support:

  ```sh
  brew install mpv
  ```

The Xcode configuration expects the Homebrew libmpv headers and libraries at
`/opt/homebrew/include` and `/opt/homebrew/lib`.

## Run locally

1. Install the CocoaPods dependencies from the repository root:

   ```sh
   pod install
   ```

2. Open [Orzen.xcworkspace](Orzen.xcworkspace) in Xcode.
3. Select the `Orzen` scheme and a macOS or iPhone run destination.
4. Build and run.

Orzen fetches catalog content at runtime. If a request cannot complete, the app
uses its cached data when available and otherwise shows local fallback catalog
items so the interface remains testable offline.

## Data and privacy

Catalog responses are cached in memory and on disk. Collections, playback
progress, track selections, and addon configuration are stored locally;
private addon data is mirrored through Keychain storage. Orzen does not bundle
or host media—stream availability comes from the addons configured by the user.
