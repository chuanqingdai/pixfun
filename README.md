# Pixfun — Local video studio

An English-language landing page and local video workspace for turning a reference edit into a reusable creative blueprint. The five-stage story covers reference selection, structural deconstruction, asset replacement planning, rebuilding, and export while clearly separating the product vision from the current prototype.

## Run on this Mac

```sh
cd "/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app"
/usr/bin/python3 app.py
```

Open http://127.0.0.1:8765/ . This existing server uses Python's `cgi` module and therefore requires Python 3.9–3.12, not 3.13+. Rendering requires FFmpeg/ffprobe and Pillow; platform links require yt-dlp. If platform access requires a proxy, start the server with your existing HTTP_PROXY / HTTPS_PROXY environment settings. The app does not change system network settings.

## Available today

- Local video file upload and drag-and-drop (up to 500 MB).
- YouTube video-link import via yt-dlp; subject to network, YouTube availability, and access permissions.
- Real metadata, automatic scene-change detection, and an N-segment visual timeline.
- One-click FFmpeg splitting: every detected scene becomes an independently playable and downloadable MP4 clip.
- A focused creative-direction prompt for describing the version you want.
- Manual script notes, including clearing saved notes.
- Timed hook/story/CTA text over original footage and audio, exported as a padded 720 × 1280 MP4.
- Original logo, responsive English landing, native-scroll five-scene demo, and reduced-motion/static fallback.
- A focused three-step workspace after import: Review & direction → Edit text → Export. Creative direction uses one compact request field below the review timeline. Each step reveals only its relevant controls. Original/result previews, retry-safe output retention, and home/resume controls preserve in-memory edits. Reloading the page does not restore the open workspace; saved briefs remain on disk.
- A front-facing speaker cover and four distinct conference shots across the illustrative timeline; see ASSETS.md for provenance and prompts.

## Important limits

Creative briefs and references are saved, not automatically executed. Person replacement, footage replacement, script translation, dubbing, automatic transcription, generative footage, and auto-publishing are not connected. On-screen Spanish text in the demo is a prepared example, not a model-generated result.

Only download, edit, and publish videos you own or are authorized to use. Pixfun does not bypass YouTube restrictions, private-video access, DRM, or platform terms.

The current sample cover and four timeline images are AI-generated conference scenes, not frames from a real recording. Earlier coastal images and the credited KOLD thumbnail remain on disk but are no longer referenced by the page.

All videos, reference files, briefs, and outputs are stored in `data/`. This version has no login and is intended for trusted loopback/local use, not public hosting. Uploaded files are not automatically deleted.

## Verification

```sh
node tests/motion.test.cjs
node tests/studio.test.cjs
node tests/smoke.cjs /absolute/path/to/a/test-video.mp4
```

The first command checks all five landing-page scene states, 1,001 forward/backward progress samples, English UI copy, required IDs, local assets, and anchors. The second checks the three-step studio controller, and the third creates a local test project and checks upload, metadata, scene detection, real MP4 clip splitting and downloads, saved briefs and references, script notes, rendering, and rejected invalid URL schemes.

The studio controller also has DOM-independent regression tests for step navigation, merged direction input, save/render failure recovery, original/result comparison, timeline seeking, home/resume, and unsaved-change warnings. Desktop and mobile browser interaction screenshots are available in `qa/`.
