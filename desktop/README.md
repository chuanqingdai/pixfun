# Pixfun for Mac — local preview

## What works

- Opens directly in the Mac-only Home composer, with Media / Skills / Project in the sidebar.
- Compose a video brief, attach a folder, videos/photos/audio, or existing Media. Saved project briefs and unsent drafts persist in SQLite; projects can be reopened and continued. This is a brief workflow, not an automatic video-generation engine.
- Native multiple-file and recursive-folder selection, drag/drop, keyboard shortcuts.
- SQLite library in `~/Library/Application Support/Pixfun/Library`. Original footage is referenced, never copied or modified. The browser's IndexedDB library is untouched and is not automatically migrated.
- Local metadata, scene segmentation/thumbnails and embedded subtitle extraction using bundled FFmpeg/FFprobe.
- Background queue with real cancellation, retry and interruption recovery. Analysis runs while navigating the workspace, but stops on quitting the app.
- Favorites, descriptions and creative-style preference survive relaunch.
- Video/image/audio previews, timestamp seeking, search, missing-file relinking and Show in Finder.
- Mutually exclusive All media / Videos / Photos / Audio / Favorites categories. No stacked Filters. Device and location tags come from actual metadata, source sidecars, or user edits; missing context is not padded with Landscape/MP4.
- Long videos (>3 minutes) use eight time-sampled navigation chapters instead of expensive repeated scene scans. These are labeled navigation chapters, not AI-recognized scenes. Short videos retain cut detection with estimated splits.
- Native scrollbars are hidden without disabling scrolling. Web single-file analysis is unchanged.
- Removing a record is a soft delete with Undo; no original file is deleted.

## Not included yet

Visual understanding, generated semantic tags, speech-to-text models, automatic editing/export and automatic updates are not implemented by this desktop shell. Skills currently save a preference only. Existing honest frontend fallbacks remain. The desktop build extracts **embedded subtitles only**; it does not depend on the web development server's MLX environment.

This build is Apple Silicon (arm64), unsigned / not notarized, for local development testing. Intel, OS compatibility across other Macs, signing, notarization and public distribution need a separate release pass. Do not disable Gatekeeper globally to run it. A production backend should move from this machine's Python 3.9 runtime to a supported Python release (3.12 is compatible with the legacy web engine's `cgi` dependency).

## Development

Prerequisites: macOS, Node 22+, Xcode command-line tools, Python 3.9–3.12.

```sh
npm ci
python3.12 -m venv .desktop-venv
.desktop-venv/bin/python -m pip install pyinstaller==6.20.0
npm run desktop:media
npm run desktop
```

On this development machine `.desktop-venv` was created using the existing Python 3.9 environment. The UI / service use an ephemeral loopback port, not the website's port 8765. Startup authenticates requests using secrets held only by the desktop main process; arbitrary-path imports require a separate native-only capability. The renderer has no Node access, a sandboxed isolated preload and a restrictive CSP. External navigation, popups, remote network requests and device permission requests are denied.

## Package

```sh
npm run desktop:media # once; official FFmpeg source, LGPL-only build
npm run desktop:dist
```

Outputs: `dist-desktop/mac-arm64/Pixfun.app`, `dist-desktop/Pixfun-0.1.4-arm64.dmg`.
Packaging reuses the installed, pinned Electron distribution instead of downloading it again.
The DMG is assembled and checksum-verified by macOS `hdiutil`, with an Applications shortcut for installation. The desktop icon is rendered from `desktop/icon.svg` at native Retina sizes. To inspect the startup design without a running backend in development, use `PIXFUN_PREVIEW_STARTUP=1 npm run desktop`; normal startup never waits artificially.
The bundle includes the standalone Python service, FFmpeg/FFprobe, their corresponding source/license/build instructions and the existing website assets. It excludes user files, SQLite libraries, model weights, credentials and the test video collection.

## Website download

The website's **Download for Mac** links directly to `/downloads/pixfun-mac.dmg`.
`app.py` serves only `dist-desktop/Pixfun-<package.json version>-arm64.dmg` as an attachment, with HEAD and byte-range support. Missing releases return 404 rather than silently downloading an older version. The directory is not publicly browsable.

The current installer is an unsigned, unnotarized preview for Apple Silicon, macOS 12 or later; there is no Intel build. For hosting, deploy the version-matched DMG alongside `app.py` and `package.json`. Static-only hosting must publish the installer separately and update the download links; localhost downloads do not make a public release.

## Test

```sh
npm run test:desktop
.desktop-venv/bin/python tests/desktop-service.test.py
PIXFUN_TEST_FROZEN=1 .desktop-venv/bin/python tests/desktop-service.test.py
node tests/library.test.cjs
node tests/library-import.test.cjs
node tests/asset-understanding.test.cjs
node tests/scene-timeline.test.cjs
.desktop-venv/bin/python tests/mac-download.test.py
node tests/mac-download.test.cjs
```

Service integration tests use temporary databases and verify auth/origin restrictions, native import grants, reference-only storage, real analysis, range playback, restart persistence, duplicate handling, soft delete/restore, missing-file relink, cancellation and retry. For isolated UI QA, launch with `PIXFUN_TEST_DATA_DIR` set to an explicit test directory; never point it at a browser data directory.

Diagnostics: `Library/service.log`. Quit/relaunch restarts the local service without resetting the library.

Shortcuts: `⌘O` import, `⌘⇧O` folder, `⌘1/2/3/4` Home/Media/Skills/Project, `⌘Q` quit.
