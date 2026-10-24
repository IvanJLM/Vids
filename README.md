# Vids

A minimal, native video player for Apple Silicon Macs.

Vids does one thing: it plays a video, smoothly, and gets out of the way. It
is written from scratch in Swift and AppKit, with no third-party code. It
plays through AVFoundation, the engine behind QuickTime Player, so every
video is decoded by the Mac's media engine in hardware. The title bar
melts into the picture, as in [IINA](https://github.com/iina/iina), and
[mnmPlayer](https://github.com/basakil/mnmPlayer) was the reference for
keeping a native player light.

## Why

Same 4K HEVC video playing, measured on an M4 Pro Mac with macOS 26
(`./scripts/benchmark.sh <video> --compare`):

| | Vids 1.0 | IINA 1.5 |
|---|---|---|
| Memory (Activity Monitor) | 42 MB | 1219 MB |
| CPU | 6 % | 104 % |
| Energy impact | 8 | 104 |
| App size | 0.6 MB | 196 MB |

Other videos with Vids: 37 MB for 1080p HEVC, 105 MB for 4K ProRes HQ.

Vids quits when its last window closes, so it uses no memory at all when you
are not watching a video.

## What it does

- **Plays the video formats built into macOS**: MP4, MOV, M4V, AVI, MPEG and
  TS, with H.264, HEVC, ProRes and AV1 (M3 and later) video and AAC, AC-3, E-AC-3, MP3, FLAC
  and ALAC audio. HDR and Dolby Vision play in HDR on HDR displays.
- **One window per video**, opened at the video's own size (shrunk to fit the
  screen) and keeping its shape when you resize it. Phone videos stand upright.
- **The title bar disappears into the picture**: the close, minimize and zoom
  buttons show while the mouse moves and fade out two seconds after it stops,
  together with the pointer.
- **QuickTime's own controls**: play, scrub, volume, audio and subtitle tracks
  and full screen, shown on hover.
- **Double-click** the picture for full screen; drag it to move the window.
- Drop a video on a window to play it there. The volume is remembered.

There are no preferences, no playlists, no library, no "recent" list and no
auto-updates. Live Text and Visual Look Up on paused frames are off, so
pausing costs nothing.

MKV, WebM and WMV are not supported: macOS has no player for them, and Vids
won't bundle FFmpeg to get one. Vids never claims them, so they keep opening
in the app they use now.

## Shortcuts

| Key | Action |
|---|---|
| Space | Play / pause |
| ← → | Back / forward 5 seconds |
| ↑ ↓ | Volume up / down |
| M | Mute |
| ⌘0 / ⌘1 / ⌘2 | Half / actual / double size |
| F, ⌃⌘F, double-click | Full screen (Esc to leave) |
| ⇧⌘R | Show in Finder |

## Install

Requirements: an Apple Silicon Mac with macOS 15 or later, Xcode 26 or later,
and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
./scripts/install.sh
```

The script builds a Release copy, installs it in `/Applications` and asks
macOS to make Vids the default app for MP4, MOV, M4V, AVI, TS, MPEG and 3GP,
one format at a time, each in its own confirmation dialog. To skip that step,
run `./scripts/install.sh --no-default`.

To install on another Mac, run `./scripts/package.sh`, copy
`dist/Vids-<version>.zip` over, unzip it into `/Applications` and open Vids
once: it offers to become the default player.

## Development

```bash
./scripts/test.sh                       # unit tests (Debug build)
./scripts/benchmark.sh video.mp4        # memory, CPU and energy while playing
./scripts/bump-version.sh minor         # or patch / major, then fill in CHANGELOG.md
swift scripts/make-icon.swift           # redraw the app icon
```

The tests write their own small videos with AVAssetWriter, so the repository
holds no video files.

## License

MIT. See [LICENSE](LICENSE).
