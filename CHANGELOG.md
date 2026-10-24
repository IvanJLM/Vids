# Changelog

## 1.1.0 — 2026-10-24

- Lighter playback: the floating controls are taken away while a video plays
  untouched and come back on mouse move or pause. AVKit kept redrawing them
  even hidden; 4K HEVC now takes about 3.5 % CPU instead of 13 %, with ten
  fewer threads. Nothing changes on screen.
- macOS can no longer quit Vids mid-video when its window is hidden,
  minimized or on another space (automatic termination is off).
- Videos opened together from Finder no longer open exactly on top of each
  other.
- The hide timer wakes the Mac less, and stops with its window.
- README and the "can't play" message list every format Vids opens (3GP,
  3G2, DV and MPEG-2 video included).
- benchmark.sh no longer writes into your preferences, and checks the video
  exists before building.

## 1.0.0 — 2026-10-24

First release. A native Swift/AppKit video player written from scratch, on
AVFoundation and AVKit, with no third-party code.

- Plays MP4, MOV, M4V, AVI, MPEG, TS and 3GP with the Mac's hardware decoders
  (H.264, HEVC, ProRes, AV1), HDR included.
- One window per video at its own size, keeping its shape; phone videos
  upright, anamorphic videos unstretched.
- Title bar hidden in the picture: the window buttons fade in on mouse move
  and out two seconds later, with the pointer.
- QuickTime's floating controls, with audio and subtitle track menus also in
  the Playback menu.
- Space, arrows (5 s skips and volume), M, F, ⌘0/⌘1/⌘2, double-click for
  full screen, drag to move, drop to replace. Volume is remembered.
- Clear message for files macOS can't play (MKV, WebM…); they are never
  claimed as Vids files.
- Quits when the last window closes. No preferences.
- Offers once to become the default player, one format at a time.
