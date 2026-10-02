# Pixfun — Local video studio

## Repository contents and local assets

Website resources, application source, tests and build scripts are versioned here.
Downloaded source footage (`data/`), local models, user databases, credentials,
build outputs and new QA captures are intentionally excluded. Existing historical
QA files remain tracked.

The 199 MB offline Mac sample
`native/Examples/wild-alaska/wild-alaska.mp4` is versioned with **Git LFS**.
Its thumbnails, manifest and source attribution remain ordinary Git files.
Install Git LFS before cloning (`brew install git-lfs` on macOS). In an existing
checkout, download the full sample before packaging:

```sh
git lfs install --local
git lfs pull
git lfs fsck
```

The MP4 must be the real video, not the small LFS pointer included in some ZIP
downloads. The native packager rejects a missing or incomplete sample. Website
case studies do not depend on this file. To regenerate the sample from its
credited source, see the input paths in `scripts/build-native-example.py`.

## Native Mac client

The default Mac client is now SwiftUI / AppKit / AVKit, with the existing bundled Python / FFmpeg local engine. Run `npm run desktop` or open `dist-native/Pixfun.app`. The legacy Electron version remains available through `npm run desktop:legacy`. See [native/README.md](native/README.md) for build commands, data compatibility and current limitations. This migration does not change the website or early-access application flow.

## Multi-file workspace

Open `/#workspace/home` for Home (import, Mac availability, three travel showcases and quick-start guides), `/#library` for Media, or `/#workspace/skills` for creative preferences. Hero **Import footage** opens the native multi-file chooser for photos and videos. Media also supports folder selection and drag/drop.

The library keeps files and extracted results in this browser's IndexedDB. Images are decoded locally for dimensions and orientation; videos use the existing `/api/import` analysis endpoint one at a time. Limits: 500 MB per file and 100 files per selection. Unsupported files are skipped; individual errors can be retried. Stop cancels waiting on the active request, not an already-running server process. Removing a browser-library entry does not delete the original file or server-generated media.

Mac download currently displays an honest coming-soon dialog. Semantic people/place/highlight recognition and applying Skills to automatic edits are not implemented. Skills currently saves a local creative preference. Showcase videos are labeled real footage samples, not product-generated edits.

Regression check: `node tests/library.test.cjs`. Browser QA notes are in `design-qa.md`.

An English-language landing page and local video workspace for turning a reference edit into a reusable creative blueprint. The five-stage story covers reference selection, structural deconstruction, asset replacement planning, creation, and export while clearly separating the product vision from the current prototype.

## Run on this Mac

```sh
cd "/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app"
/usr/bin/python3 app.py
```

For local speech transcription on Apple Silicon, install the isolated MLX Whisper runtime once:

```sh
/usr/bin/python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-transcription.txt
```

Open http://127.0.0.1:8765/ . This existing server uses Python's `cgi` module and therefore requires Python 3.9–3.12, not 3.13+. Rendering requires FFmpeg/ffprobe and Pillow; platform links require yt-dlp. The first transcription downloads and caches the multilingual Whisper Small model in `data/models/`; subsequent videos reuse it locally. If platform access requires a proxy, start the server with your existing HTTP_PROXY / HTTPS_PROXY environment settings. The app does not change system network settings.

## Available today

- Local video file upload and drag-and-drop (up to 500 MB).
- YouTube video-link import via yt-dlp; subject to network, YouTube availability, and access permissions.
- Real metadata, automatic scene-change detection, and an N-segment visual timeline.
- Server-extracted representative frames for every detected storyboard segment.
- Embedded subtitle extraction with local speech-to-text fallback, rendered in a dedicated seekable subtitle list below the storyboard timeline.
- A focused creative-direction prompt that parses natural language into a structured plan in the background and carries it directly into the editing conversation.
- Manual script notes, including clearing saved notes.
- Timed hook/story/CTA text over original footage and audio, exported as a padded 720 × 1280 MP4.
- Original logo, responsive English landing, native-scroll five-scene demo, and reduced-motion/static fallback.
- A focused two-step workspace after import: Create → Export. Create uses a responsive split layout: the player, continuous storyboard timeline, and extracted subtitles stay visible on the left while a minimal GPT-style Pixfun conversation runs on the right. The first request becomes the opening user turn without navigating away from the video. Directions are preserved on disk and translated into the opening/main/closing fields used by export. Original/result previews, retry-safe output retention, and home/resume controls preserve in-memory edits. Reloading the page does not restore the open workspace; saved briefs remain on disk.
- A front-facing speaker cover and four distinct conference shots across the illustrative timeline; see ASSETS.md for provenance and prompts.

## Important limits

Creative briefs are converted into a structured plan in the background, but advanced person replacement, footage replacement, script translation, dubbing, generative footage, and auto-publishing are not automatically executed yet. Speech transcription and timestamped subtitle extraction run locally; text accuracy depends on the video's audio quality and the Whisper model. On-screen Spanish text in the demo is a prepared example, not a model-generated result.

Only download, edit, and publish videos you own or are authorized to use. Pixfun does not bypass YouTube restrictions, private-video access, DRM, or platform terms.

The current sample cover and four timeline images are AI-generated conference scenes, not frames from a real recording. Earlier coastal images and the credited KOLD thumbnail remain on disk but are no longer referenced by the page.

All videos, reference files, briefs, and outputs are stored in `data/`. This version has no login and is intended for trusted loopback/local use, not public hosting. Uploaded files are not automatically deleted.

## Mac early-access applications (web only)

The website links to `/mac-early-access` instead of offering a Mac download. Four questions cover personal background (traveler, platform creator, editor, studio, brand, or other), editing needs, email, and monthly USD subscription budget. Professional creators can also select publishing platforms. Budget choices are free-only, $1–9, $10–19, $20–39, $40–69, $70+, and not sure. The existing desktop client is unchanged.

`POST /api/mac-applications` validates and saves applications to `data/mac-applications.sqlite3` (or the configured `PIXFUN_DATA_DIR`). The database has owner-only permissions and is excluded from Git and public file routes. Repeated emails do not create duplicates or replace previous answers. No confirmation email or invitation is sent automatically. Access the database only as the site operator; do not expose it as a download.

Open `http://127.0.0.1:8765/admin/mac-applications` on the Mac running the server to view real applications, search needs/email/platforms, filter by background and budget, and export the filtered list as CSV. CSV cells are escaped to prevent spreadsheet formula execution. The viewer has no public navigation entry, browser persistence or third-party data integration. Its data endpoint requires a loopback client and exact local Host; cross-site browser requests and forwarded/proxied requests are rejected. This is a trusted single-user local operator view, not multi-user authentication: other trusted processes on the same machine can access it. Do not use a proxy that strips forwarding headers to expose it publicly. Public or remote administration needs authentication before deployment.

The v2 schema adds background, platform and budget-range columns without overwriting historical records. Old exact prices remain visible and are grouped only for statistics; old applications are labeled as missing personal background rather than inferring it from video type.

Run `PYTHONPYCACHEPREFIX=/tmp/pixfun-python-cache python3 tests/mac-applications.test.py` to verify temporary-storage submission, validation, rate limiting and private storage. Applications on localhost are not publicly reachable; public collection requires a secured deployment and persistent private storage first.

## Verification

Native analysis-only turns now save an `analysisReport` with an overall finding and one content/use-suggestion entry per source. The extra writing pass uses the task's already-approved local/cloud text route and existing analysis evidence, not another video scan. Incomplete, malformed, unavailable, or oversized summaries fall back to the actual findings for every source; cancellation still stops the task. The conversation shows findings directly, while shot evidence, source-time links, and downloads stay expandable. Historical turns are grouped from their saved artifacts at display time without changing the library or rerunning models. Interface labels remain English; new report prose follows the request language.

Report regression checks: `/usr/bin/python3 tests/agent-report.test.py`, `/usr/bin/python3 tests/agent.test.py`, `node scripts/test-native.cjs`, and `node --test tests/native-desktop.test.cjs`. Native builds can be staged with `node scripts/build-native.cjs --stage-only` to avoid interrupting the installed client.

```sh
node tests/motion.test.cjs
node tests/studio.test.cjs
node tests/smoke.cjs /absolute/path/to/a/test-video.mp4
```

The first command checks all five landing-page scene states, 1,001 forward/backward progress samples, English UI copy, required IDs, local assets, and anchors. The second checks the two-step split studio controller, and the third creates a local test project and checks upload, metadata, storyboard detection, segment thumbnails, saved briefs and references, rendering, and rejected invalid URL schemes.

The studio controller also has DOM-independent regression tests for split-layout structure, step navigation, inline conversation, save/render failure recovery, original/result comparison, timeline seeking, home/resume, and unsaved-change warnings. Desktop and mobile browser interaction screenshots are available in `qa/`.
