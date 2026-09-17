# Pixfun — Local video studio

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

## Verification

```sh
node tests/motion.test.cjs
node tests/studio.test.cjs
node tests/smoke.cjs /absolute/path/to/a/test-video.mp4
```

The first command checks all five landing-page scene states, 1,001 forward/backward progress samples, English UI copy, required IDs, local assets, and anchors. The second checks the two-step split studio controller, and the third creates a local test project and checks upload, metadata, storyboard detection, segment thumbnails, saved briefs and references, rendering, and rejected invalid URL schemes.

The studio controller also has DOM-independent regression tests for split-layout structure, step navigation, inline conversation, save/render failure recovery, original/result comparison, timeline seeking, home/resume, and unsaved-change warnings. Desktop and mobile browser interaction screenshots are available in `qa/`.
