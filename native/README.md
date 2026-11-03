# Pixfun Native (macOS)

This is the default Mac client, implemented in **SwiftUI + AppKit + AVKit**. It does not embed Electron, Chromium, WKWebView, HTML, or JavaScript UI. The website is a separate product surface and is unchanged.

## Media 0.2.0

- Trip location corrections expand inside the current Agent message, sharing its scroll area. Select affected media and a reference, then apply; errors retain the selection, and successful corrections return to trip confirmation without starting story planning.
- Includes the restored Motion Titles, Journey Route and Highlight Counter skills, with graphic options in the existing Agent/editor controls. See [motion graphics](HYPERFRAMES.md) for runtime requirements and validation.
- Import original photos/videos in place, or configure verified-copy sync from cards, folders and paired phones. Keep original filenames and source references. The empty library emphasizes manual import and also offers sync.
- Browse by type, favorite, import date, source folder/device, place, scene, primary subject and activity. Search saved descriptions, shot evidence, transcripts and on-screen text; optional local visual indexing adds seekable scene matches.
- Read an overall video description followed by distinct moments when present. Shot navigation stays below the player; secondary analysis, measurements and provenance are collapsed. Editorial estimates and sampled technical measurements retain separate labels.
- Show available capture time, device, dimensions, frame rate, codecs, audio and GPS metadata. Hide the card's time row until a valid capture time is available. Container creation time is not substituted for capture time.
- Generate evidence-backed subject/activity tags, keep background details searchable, and support manual tag corrections. Chinese is the default for the interface and newly generated analysis; settings use a draft and apply only after confirmation.
- Resume interrupted content-analysis queues, reuse completed evidence, and retry transient failures with bounded backoff. Library removal requires confirmation and preserves original files.
- Optional Apple coordinate lookup provides address context. A separate, default-off OpenStreetMap boundary toggle can group mapped campuses, parks and scenic areas. Lake proximity remains qualified as “nearby”; missing or ambiguous boundaries preserve the address. User-saved place names take priority.

Boundary lookup sends coordinates only, caches results locally, and displays OpenStreetMap attribution. The community Overpass endpoint is for a limited pilot, capped at 100 requests/day with service-error cooldown. Production must configure an operated/contracted HTTPS endpoint using `PixfunBoundaryEndpoint` in the signed app's Info.plist. Public-service availability and boundary coverage are not guaranteed.

- Place chips use city plus named area, including legacy Apple results; the full address, canonical map name and original GPS remain available and searchable.
- A separately consented Nominatim fallback can discover candidates and verify Polygon/MultiPolygon containment, including holes. Nearest POIs and bounding rectangles are not containment evidence. Cached polygons can serve other coordinates inside the same mapped area without repeated requests.
- The fallback is serial, capped at 30 HTTP requests/day with at least 1.1 seconds between requests and error backoff. Configure a stable self-hosted/contracted base URL with `PixfunPlaceFallbackEndpoint` for production. HTTP 403/406 blocks the Overpass endpoint across restarts rather than rotating identities or mirrors.
- Explicit local place-name preferences are scoped by city and canonical area in `placeDisplayAliases.v1`; they change the concise caption, not source coordinates, canonical names or files. No campus/scenic-name whitelist or filename-based assignment is built into lookup.

Media verification (synthetic fixtures, no personal library changes):

```sh
node scripts/test-media.cjs
node scripts/build-desktop-backend.cjs --skip-icon
node scripts/build-native.cjs --stage-only
```

Use the existing desktop Python environment with the dependencies in `desktop/phone-requirements.txt`; FFmpeg with lavfi support generates the synthetic test clip. Visual-index and optional aesthetic checks require their configured local models. Tests report unavailable optional integrations as skips.

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

## Pixfun design system and appearance

The client uses semantic light/dark colors, system Chinese/Latin typography, 40-point standard controls, 40-point navigation rows, 28-point page headings and 16:9 media cards. Gold button fills retain dark labels in both appearances; gold text, selected navigation, input borders and focus colors have independent light values. Player footage is not recolored.

Settings → General → Appearance offers **Follow system / Light / Dark**, defaulting to Follow system. The preference is stored locally as `appAppearance`; system mode clears the application appearance override. AppKit is the sole appearance authority so dismissing a preview cannot leave the main window in a different theme. Selecting an appearance previews it across the app. **Save** persists it; **Cancel** restores the previously saved appearance. Appearance-only changes do not validate or write cloud credentials.

Settings use one surface per group, 16-point row padding, a 24-point column gap, 14-point labels/descriptions, 240-point field columns, and content-driven row heights. Containers below 560 points stack labels above controls. Location permissions and model configuration retain their existing behavior; the footer keeps Cancel/Save and errors visible while the form scrolls.

`native/Tests/ThemeTests.swift` resolves the actual dynamic AppKit palette in Aqua and Dark Aqua and checks text, button, input-boundary and selection contrast. `scripts/test-native.cjs` includes this check along with existing native regressions. Appearance persistence and draft isolation are covered by the native model tests.

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

- Model settings use the shared design-system rows and 40-point fields with persistent labels, plain text-field styling and masked API-key entry. The form scrolls within a screen-height-aware sheet; Cancel/Save and save errors stay in its fixed footer. Local tool diagnostics are collapsed by default. Draft settings still commit only after a successful save, with task-specific cloud consent unchanged.

- Agent turns show the current step and a collapsible per-material list with filenames, completed count, and analyzing/waiting/failed/paused states. A partial finding does not mark a whole material complete. Completed states survive failure and restart; filenames open the existing Media detail view. Older tasks use their saved analysis counters. Clarification, retry/stop controls and results remain in the conversation.

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
