# Pixfun Native (macOS)

This is the default Mac client, implemented in **SwiftUI + AppKit + AVKit**. It does not embed Electron, Chromium, WKWebView, HTML, or JavaScript UI. The website is a separate product surface and is unchanged.

## Architecture and current scope

- `PixfunApp.swift`: a native window, sidebar, system menus and keyboard commands.
- `Theme.swift`: web-aligned charcoal/gold palette, bundled DM Sans typography, flat primary/secondary/quiet buttons, search fields, card hover states and sidebar navigation. File panels, contextual menus and AVKit playback remain native; no web renderer is introduced. Font files and the OFL license are packaged locally, with no font network requests.
- `HomeView.swift`: a dedicated new-project composer with file/folder imports, attached covers and creator skill. Existing conversations never replace Home. Home and each project's follow-up draft are persisted separately; legacy project-bound drafts migrate without deleting their text.
- `ProjectsView.swift`: responsive 16:9 video-cover cards, project titles and localized last-edit date/time. Cards open an in-window project child page with Agent results/conversation or the saved brief. Media selection returns to the initiating composer. Returning Home or switching projects preserves unsent drafts. Background analysis progress does not change the displayed edit time; explicit timeline edits do.
- `PromptEditor.swift`: AppKit plain-text composer with aligned placeholder/caret insets, no empty scroller gutter or focus outline, 120–220 pt content-driven height, multiline input and native undo. Marked IME text is not replaced during SwiftUI updates. The sidebar reuses the approved `pixfun-lockup-v2.png` web asset rather than a substitute symbol or retyped wordmark.
- `MediaView.swift`: video/photo/favorite categories, folder filtering (including descendants), explicit filename vs all-information search, natural name/duration sorting, portrait-aware masonry, shared selection into Home, native AVPlayerView, full searchable subtitle track and seekable segments. Details are an in-window Media child page, not a sheet. Back preserves filters and returns to the selected card. The selectable full local path supports Copy path and Show in Finder, including the last indexed path of missing files.
- `SkillsView.swift`: nine creator strategies with benefits, story structure, pacing, sound and material handling; Use skill inserts the strategy into Home. Travel Vlog summarizes the supplied VisionFlow v5.4 specification in five story beats and six principles, with an existing licensed travel cover. The exact original lives in `creator-skills/visionflow-travel-director/SKILL.md` and is bundled under `CreatorSkills/`; Full skill opens it locally. The Home brief carries a concise strategy and versioned source reference, not the full document or a claim that the production engine is connected.
- `WorkspaceStore.swift`: native file panels, deduplicated recursive imports, draft persistence, project history, favorites, soft removal/undo, missing-original relinking and Finder actions.
- `PlaceViews.swift`: compact location shortcuts inside the Media masonry scroll area. Locations come from existing metadata. Person grouping, avatar filters, person detail controls and automatic face scans have been removed; their service routes no longer exist and face models are no longer included in the native package. Existing people-cache files are left untouched, but are not loaded or used.
- `LocalService.swift`: launches and authenticates to the bundled Python/FFmpeg analysis engine on a random **loopback-only** port. The engine is not rewritten in Swift. It stops when the app exits; a parent watchdog also stops it after a crash. No public API key is needed.

The Agent workspace now connects the installed local VisionFlow/MLX runtime for intent routing, sampled visual understanding, speech transcription, semantic search and grounded rough-cut planning. Local optical-flow/quality/OCR evidence informs planning. Users review a timeline before FFmpeg builds a preview, edit source ranges/order/locks, and export the result with a native save panel. See [Agent architecture, API contracts and limitations](AGENT-ARCHITECTURE.md). Large-model runtimes/weights are **not bundled**: they must already be installed or explicitly configured. Cloud use is optional and asks task-specific permission; real cloud integration remains unverified until a provider, models and credentials are supplied. Generated music, voiceover and publishing are not implemented. No transcript is presented as a visual description. Audio can be attached in Home but is intentionally excluded from Media categories.

## Build and run

Current verified build: Apple Silicon, macOS 13+, Swift 5.10 / Xcode Command Line Tools. Intel and App Store distribution have not been verified. No Swift package dependencies are downloaded.

```sh
# Existing repository toolchain/resources: .desktop-venv (PyInstaller), bundled FFmpeg, ICNS.
# For their initial setup, see ../desktop/README.md.
npm run desktop:backend
npm run desktop:pack
open dist-native/Pixfun.app

# Build + open the native client (default):
npm run desktop

# Optional development DMG (not notarized):
npm run desktop:dist

# Original Electron implementation, retained intentionally:
npm run desktop:legacy
```

`dist-native/Pixfun.app` contains the runtime and tools; installed users do **not** need Python, Node.js, a website server, or npm. `scripts/build-native.cjs` builds/signs in a staging directory and preserves the previous generated app under `build-native/package-*/Previous-Pixfun.app` before replacement. Never rebuild a running bundle. Signing is ad hoc for local development; **Developer ID signing and Apple notarization are still required for public distribution**. The website remains early-access-only and does not offer this development app as a download.

## Data compatibility and safety

- The conversation composer has one trailing action: Stop while a task runs, Send/Continue when idle. Pending actions display their spinner inside that same button; Stop and Send never appear together. Stopping keeps the unsent draft and attachments, and Send retains its validation and keyboard shortcut.

- Model settings use 46-point, full-width controls with persistent labels, plain text-field styling and masked API-key entry. The form scrolls within a screen-height-aware sheet; Cancel/Save and save errors stay in its fixed footer. Local tool diagnostics are collapsed by default. Draft settings still commit only after a successful save, with task-specific cloud consent unchanged.

- Agent turns show only the current plain-English step and an indeterminate spinner while running. Repeated task summaries, window counters, progress totals and work-log lists are not rendered. The underlying events remain stored for diagnostics. Finished turns show their results; clarification, permission questions, retry/stop controls and actionable errors remain available.

- Reimporting an already indexed original returns the existing item without an alert, duplicate attachment or repeated analysis. Ready/busy/error states and cached analysis are preserved; real import failures are still reported. Media covers and composer thumbnails show their own processing indicator, which clears when the corresponding work completes.

- Shot cards expose native hover tooltips with the shot name, time range and full editorial description. The same description is available to accessibility users. Missing/queued/failed analysis uses English guidance; subtitle text and technical split notes never substitute for a visual description. Existing descriptions remain available while reanalysis runs.

- One offline **Wild Alaska** example is bundled under `Resources/public/examples/wild-alaska`. It is a 1080p continuous 3:29 excerpt from the credited NPS Lake Clark film, with original narration/music, prepared visual cuts, official source captions and an English editorial description. Media shows a gold **Sample** badge and puts it first in the default order; it is not presented as raw camera footage or freshly generated model output. Startup indexes its bundle path once; app relocation refreshes that reference without overwriting user analysis/favorites or restoring a removed example. The video is not copied into the user library. Build assets with `python3 scripts/build-native-example.py`; source and credit are retained in `SOURCE.txt`. Normal local understanding can be run from the detail page. Built-in UI copy defaults to English; existing user/model-authored content is not translated.

- Uses the existing `~/Library/Application Support/Pixfun/Library/library.sqlite3`, original paths and analysis outputs. No library copy or destructive migration is performed.
- Quit the old Electron client first. The native client detects its bundle ID, and the updated private service obtains an exclusive lock before touching the library.
- Originals are referenced, never moved or deleted. Remove from Media soft-deletes the library entry; Undo restores it.
- Adding local files does not upload them or copy originals into the app. Only the reference index, project data and derived analysis caches (e.g. thumbnails/subtitles) are stored. Folder filtering reads the existing index; it never scans unrelated folders. Absolute paths are delivered only through the native-authenticated `/api/desktop/locations` endpoint, not the web renderer's library response.
- New native drafts are atomically written to `native-draft.json`. On first launch the native app reads the Electron `projectDraft` setting when no native draft exists. Projects/favorites/media remain shared; unsent draft synchronization back to Electron is not provided.
- Set `PIXFUN_TEST_DATA_DIR` to an **explicit temporary directory** to run QA without writing to your real library.
- `native-service.log` records startup/runtime errors without tokens. No media uploads or telemetry are implemented.

### Local people analysis

YuNet and SFace weights are packaged with pinned SHA-256 verification and their MIT/Apache licenses. OpenCV/NumPy and their notices are bundled. No model download or cloud API is used at runtime. Face crops and face embeddings are derived biometric data, kept only in the local library's `people/` cache (directory 0700, files 0600); names, roles, merges and exclusions are in `native-people.json` (0600). Originals are never modified or copied. Do not publish this cache or include it in diagnostic uploads.

Analysis samples every three seconds (at most 600 frames per video). It suppresses small/brief appearances using face size, persistence and prominence, not knowledge of who is a companion or bystander. It can miss brief appearances, masked/side-facing people, or split one person into several groups. Similarity groups are not verified identities. Manual corrections survive rescans; merges can be separated again. The app shows completed-file progress and allows stopping; completed files are cached for restart. No accuracy guarantee or full-frame coverage is claimed.

## Verification

### Editorial video descriptions

Opening a video detail requests a local, cached editorial title and 100–200-character Chinese description, using the supplied prompt verbatim in `video_description.py`. This is separate from the complete transcript. The local vision model samples three frames per six-second window across the video; existing subtitles or local speech recognition supply dialogue evidence. Long evidence is summarized in chronological batches, including the ending. This is sampled understanding, not frame-exhaustive observation. Missing capture metadata is omitted from the title rather than guessed. Titles are searchable display metadata; original files are never renamed. Stop, retry/regenerate, interrupted work, and model errors have explicit states; regeneration retains the previous successful text until replacement succeeds. The existing Agent queue is shared to avoid competing GPU workers.

Run `tests/video-description.test.py` for isolated contracts and `scripts/verify-video-description.py` for real offline model checks on the two repository travel examples. Results are saved under `build-native/video-description-cases.json`.

### Editable shot breakdown

`shot_analysis.py` preserves the supplied editor/storyboard prompt and its exact `video_summary` / `shots` output schema. Six-second sampling windows remain observation evidence, not automatic shots. Full-frame-rate, downscaled scene-change candidates and sampled semantic candidates are reviewed against before/after frames; ordinary action continuity can therefore remain one editable unit. Visual cut positions come from frame timestamps. Semantic candidates are approximate (±3 seconds), explicitly labeled for review rather than presented as frame-accurate boundaries.

Each accepted interval receives subject/action/change descriptions, shot size, capture/motion, reaction, story roles, an editorial score, duplicate/unusable review flags, and a duration-bounded edit recommendation. Dialogue must occur literally in overlapping subtitle/ASR evidence and is labeled for verification. The installed runtime has no environmental-sound classifier: unsupported sound labels are removed and `audio` remains empty, not populated from visual guesses. No inferred identity or automatic deletion is implemented. These are editorial suggestions, not verified narrative facts.

Media details show these editable shots, their explanations and regeneration state; the Agent reuses the same result for analysis, retrieval and story planning. Analysis-only runs also produce the exact JSON as a file artifact. Original files and the fallback basic-navigation record are preserved. Tests: `tests/shot-analysis.test.py`, `scripts/verify-shot-analysis.py`; real-case report: `build-native/shot-analysis-cases.json`.

```sh
npm run test:desktop
PATH="$PWD/build-desktop/media/bin:$PATH" .desktop-venv/bin/python tests/desktop-service.test.py -v
PIXFUN_TEST_FROZEN=1 PATH="$PWD/build-desktop/media/bin:$PATH" .desktop-venv/bin/python tests/desktop-service.test.py -v
```

Native model tests use `swiftc` rather than XCTest, so full Xcode is not required. They exercise legacy decoding, portrait dimensions, search, truthful split labels, timestamps, draft round-trip, duplicate attachment prevention, supported-file enumeration, symlink exclusion and the 100-file limit. Backend integration tests use temporary databases and verify authentication, importing, analysis, stop/retry, relinking, subtitle completeness, project/skill persistence and single-engine locking.
