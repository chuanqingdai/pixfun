# Design QA — Workspace ingestion, Home and Skills, 2026-09-27

## Scope and visual reference

Extended the existing Pixfun product, preserving its approved neutral software palette, raster logo, DM Sans controls and Lora landing typography. User-defined structure: Hero import/Mac actions; multi-file ingestion; Home / Media / Skills navigation; Home actions, showcases and tutorials. No separate pixel-exact workspace mock was supplied, so workspace verification is against this structural brief and existing visual system, not a claim of mock fidelity.

- Reference: `qa/heading-audit/01-heroTitle.png` (1312 × 860).
- Implementation: `qa/media-library/hero-entry.png` (1312 × 860). Both displayed together in one comparison input. Same Hero state/theme and viewport, with the naturally changing background-video frame excluded from fidelity findings.
- Desktop workspace: `qa/media-library/home-desktop.png`, `home-guides.png`, `skills.png`, `processing.png`, `transcripts.png`, `error.png`.
- Mobile: `qa/media-library/home-mobile.png`, `media-mobile.png`; 390 × 844 viewport override, captured image 375 × 812. Responsive checks used live DOM dimensions, not scaled-image pixel measurements. Override reset after testing.
- `loading.png` captured the initial empty/preparation view; `processing.png` captured completion with a failed fixture. They are not evidence of an active processing animation. Active uploading/analysis status was observed in live DOM snapshots.

## Findings and fixes

- P2: progress initially said “ready” while newly staged files were still queued. Pending states now include queued, reading, uploading and analyzing; only settled items count toward completion.
- P2: opening a subtitle could briefly show a black preview. Extracted thumbnail is now supplied as the video poster. Clicking the second test cue verified currentTime = 3 seconds.
- P2: every segment of a selected source was highlighted. Selection now tracks the segment start as well as file ID.
- Added explicit tutorial “Read guide” / “Close guide” affordances and state-aware heading labels. Home is not labeled Footage Library anymore.

## Required visual surfaces

- Typography: preserved Hero layout; new two-button row fits. Workspace uses DM Sans, with smaller utility headings suited to repeated work. No text clipping observed in tested states.
- Spacing/layout: fixed-width desktop sidebar; flexible content and inspector; responsive top navigation and stacked inspector on mobile. DOM checks found no page-level horizontal overflow. Media categories intentionally scroll horizontally on narrow screens.
- Colors/tokens: neutral canvas/surfaces, gold primary action and selected state, inherited focus/error/success tokens. No new saturated brand palette.
- Imagery: existing real travel photos/video samples; no generated creator images. New workspace uses the approved transparent-composited logo. Showcase samples are explicitly not represented as AI-generated outputs.
- Copy: English UI; Mac is marked coming soon; measured metadata, extracted subtitles, and heuristic segments are distinct from unavailable semantic recognition. Skills saves preferences only; it does not claim to run an editing model.

## Functional verification

- Native chooser accepted an MP4 and two JPEGs in one selection and immediately entered the workspace. Images decoded locally; video analysis used the existing local API.
- Batch completion, metadata, thumbnails, type filters, selected-file preview and browser-storage restoration checked.
- Controlled subtitle fixture produced two extracted cues; clicking the second sought to 3 seconds.
- Controlled corrupt MP4 reached Needs attention; retry re-entered uploading and returned a readable error without blocking other files.
- Removed only the two agent-created test entries from browser storage via the UI. Original fixture files remain on disk and can be reimported.
- Home, Media and Skills navigation; tutorial expansion and Media jump; showcase video reached its 8-second end; dialog closing; Mac-unavailable dialog; selected skill persisted after reload; Open workspace entry from landing all checked.
- Latest reload showed no JavaScript console errors. Automated library, travel, studio, motion, polish, palette, creator-voices and hero-player checks passed.
- Not exhaustively tested: Safari/Firefox, disk quota exhaustion, 100-file scale, native directory selection on every browser, server-side cancellation (XHR stop only stops waiting; current server processing can finish).

## Remaining capability limits

People/place/highlight semantic recognition and automatic editing with Skills are not connected. No Mac binary exists. These are disclosed in the UI. The earlier single-video editor remains intact but is not the initial batch-import page.

final result: passed

---

# Design QA — Travel Vlog intelligent editing, 2026-09-26

## Final result: passed

### Source and scope

- Visual direction: `/Users/daichuanqing/.codex/generated_images/01a0aa1f-af9a-7801-8216-8fbc68d82ad8/exec-29b72cc8-c8a8-4186-b9fb-2b54472fac6a.png` (840 × 1870 concept image).
- User amendments override that concept: real stock footage only; immersive full-hero video including navigation; sand/cream compass wordmark; five independent five-second highlights; no cross-case montage; no separate Pause button or video-link entry; travel-specific intelligent-editing copy.
- Working page: `http://127.0.0.1:8765/?v=travel-vlog-7`.
- Browser: Codex in-app browser. Desktop CSS viewport 1146 × 870, mobile 390 × 844, tablet 840 × 1000. Viewport override reset after testing.

### Evidence and comparisons

- `qa/travel-redesign/desktop-final.png`: final hero and five-case navigation, 1131 × 859 screenshot pixels.
- `qa/travel-redesign/mobile-final.png`: final mobile hero, 375 × 812 screenshot pixels.
- `qa/travel-redesign/desktop-workflow.png`: style-selection state, timeline and active step.
- `qa/travel-redesign/mobile-workflow.png`: responsive selectable workflow.
- `qa/travel-redesign/tablet-full.png`: complete page composition, 825 × 5079 screenshot pixels; captured before final fifth-case/no-extra-controls refinement.
- `qa/travel-redesign/import-workspace.png`: real uploaded travel test video in the analysis workspace, three segments and no-audio subtitle empty state.
- Reference and full-page implementation were opened together in one comparison input. The returned browser capture has a small visible-canvas crop relative to CSS viewport; no density-related pixel mismatch was treated as a defect. Concept and implementation have different total heights intentionally: the concept is condensed, while the product has real text, a full-screen hero and responsive content. Compared section order, hierarchy and design language, not raw full-page pixel alignment.
- Focused desktop/mobile hero captures and workflow screenshot were inspected separately for text wrapping, control spacing, video crop, contrast and timeline visibility.

### Findings, fixes and re-checks

1. [P1, fixed] Legacy `.demo-timeline` styles made the new timeline transparent and absolutely positioned. Scoped overrides restore normal flow, opacity and geometry. Desktop workflow capture confirms the filmstrip is visible directly below the viewer.
2. [P2, fixed] Auto vertical margins created excess whitespace around the sticky workbench. The workflow container now uses horizontal auto margins only. Rechecked at laptop height and mobile width.
3. [P2, fixed] Mobile hero wrapped the display headline into three lines. Responsive font scale now preserves two clear lines, with no horizontal overflow at 390 px.
4. [P2, fixed] Some trimmed source excerpts ended early. All five preview MP4 files were checked with FFprobe and are exactly 5.000 seconds, including camping. Each is derived from a different source and has a distinct SHA-256.
5. [P2, resolved by user direction] Initial montage and automatic case switching did not match independent highlights. Removed the montage from the page, retained five separate files, and loop only the selected case. The active-case button toggles playback; no separate Pause control is present.
6. [P2, resolved by user direction] The hero had redundant labels and import entry points. Removed the second case headline, numbered field notes, extra availability copy and visible video-link entry. Link-import DOM hooks remain hidden for the existing controller's compatibility; copy now describes local-video import.

### Required design surfaces

- Typography: self-hosted Lora / Lora Italic for editorial headings and DM Sans for interface text. Cream wordmark and restrained scales replace the old saturated tech branding. No missing glyphs or clipped headings observed.
- Layout: full-bleed film extends behind the navigation. Hero actions stay grouped, case selectors sit along the bottom. Section order follows footage-to-story, six-stage workflow, creator niches, FAQ, closing CTA. Mobile workflow is selectable instead of requiring a long pinned scroll.
- Color: green-black surfaces, warm ivory, sand-gold selection states. Dark overlay keeps hero copy legible across the five real scenes. Focus styling remains visible.
- Images: only licensed real clips and extracted frames are loaded. No generated image, old speaker asset or generated-person case is linked by the landing page. Families and companions are stock performers, not claimed customers or people of an inferred nationality.
- Icons/brand: official Phosphor Compass SVG, recolored sand, plus typographic wordmark. Font and icon license files included.
- Copy: intelligent editing for travel Vlogs, including road trips, hiking, camping, slow/coastal travel and city diaries. Automatic arrangement and finishing are explicitly labeled workflow previews. Current actual functionality is described in FAQ; no claims of production-ready generative editing.

### Interaction and regression checks

- Independent case selection and playback source change: passed.
- Re-click selected case pauses playback: passed. Leaving the hero / entering Studio pauses the background video.
- Five distinct 5-second video files: FFprobe and hash checks passed. No automatic cross-case `ended` handler.
- Desktop stage navigation, sticky stage, travel-diary style selection and matching copy: passed.
- Mobile stage selection and FAQ expansion: passed.
- Real upload of the local coastal test fixture: passed, button loading visible, then Studio with three scene thumbnails, 8-second source metadata and correct no-audio caption state. Home and Studio do not overlap.
- Console errors/warnings on final page: none observed.
- Responsive overflow / broken loaded images: none at desktop, 840 px tablet and 390 px mobile.
- Reduced-motion behavior: CSS/JS guard reviewed; automatic video and pinned motion disabled when the preference matches. OS preference itself was not changed during this task.
- `node tests/travel.test.cjs`: passed.
- `node tests/motion.test.cjs`: passed (legacy geometry retained; current landing assertions updated).
- `node tests/studio.test.cjs`: passed.
- `/usr/bin/python3 tests/analysis.test.py`: passed.

### Remaining scope / follow-up

- This is the travel-positioned frontend with the existing analysis/editing service, not a new autonomous travel editing engine. Automatic story arrangement, music and color finishing remain future integrations.
- P3: replace generic stock with creator-owned case studies when available; do not invent endorsements or finished customer results.
- No deployment or GitHub push performed in this redesign turn. Existing unrelated changes preserved.

---

# Earlier Design QA — P0 video analysis tracks

- Implementation: `http://127.0.0.1:8765/?v=openmontage-p0-1#studio`
- Test source: OpenMontage 30-second demo video
- Browser: Codex in-app Browser, 1146 × 964
- State: imported video with scene thumbnails, timed subtitles, and content-structure analysis

## Verified behavior

- The scene timeline remains continuous and directly adjacent to the player.
- Every scene has a representative frame, start/end time, and proportional width.
- Hook, Setup, Core idea, Proof/payoff, and CTA labels are merged into the matching subtitle rows instead of occupying another track.
- Scene clips and subtitle rows are buttons that seek the source video.
- Timed subtitles remain in a compact, low-priority panel below the scene timeline.
- The desktop split workspace remains balanced; the added track does not overlap the chat pane or fixed composer.
- Narrow layouts retain one shared horizontal scroll width for scene and structure tracks.

## Data contract

The import API now returns `analysis.tracks.scenes`, `analysis.tracks.subtitles`, and `analysis.tracks.structure`. Structure beats contain scene IDs, time boundaries, duration, role, summary, and an explicit estimated-confidence marker.

## Automated checks

- Studio controller regression: passed
- Motion and DOM regression: passed
- Analysis segmentation and structure continuity: passed
- Python syntax and diff whitespace validation: passed
- Real-video import smoke test: passed (4 scenes, 4 structure beats, 9 subtitle cues)
- Media byte-range seek check: passed (`206 Partial Content`; invalid ranges return `416`)

## Findings

No blocking visual or interaction defects remain. Content-role labels are heuristic in this P0 and are intentionally marked as estimated in the API; semantic model scoring and speaker diarization belong in a later phase.

final result: passed

## Brand matte fix and creator perspectives — 2026-09-27

- Preview: `http://127.0.0.1:8765/?v=brand-voices-2`.
- Source: selected gold/ivory opposing-filmstrip logo; capital-P production asset `exec-105ea764-e88e-4db9-98f3-7d0eee48d52e.png`. Compared together with `qa/brand-footer-directions/pixfun-header-v2-fixed.png` (1312 × 860) in the same visual review.
- P2 found: opaque black matte remained around the logo over the hero video. Fixed using a dedicated SVG color-matrix compositing filter; the approved raster artwork and letterforms remain unchanged. Updated stylesheet cache version to 2.
- Desktop header and footer: complete capital-P wordmark, gold/ivory colors preserved, no rectangular black background. Evidence: `pixfun-header-v2-fixed.png`, `pixfun-footer-v2.png` in `qa/brand-footer-directions/`.
- Mobile: hero checked at 390 × 844, logo readable and not clipped; footer independently checked. Evidence: `pixfun-mobile-v2.png`; `pixfun-voices-mobile-v2.png` actually captures the footer due restored scroll position (not a card-layout screenshot).
- Reviews: centered heading, six scenario-specific English perspectives, three desktop columns and one mobile column. Read-only DOM check at 390 px confirmed six cards, 331 px column and no horizontal overflow. Removed repeated sample labels; retained one honest disclosure below the grid. No invented customer identities or ratings.
- Scope: verified in the Codex in-app browser; other browser engines not tested.
- Final visual result: passed for the logo fix. Existing typography, page palette and unrelated workflow behavior preserved.
