# Shot library integration

The ingestion pipeline and the presentation adapter are separate. `public/asset-understanding.js` normalizes model results, builds compact card data, and provides search/filter values. `public/asset-understanding.d.ts` documents the optional semantic payload.

## Provider contract

- Whole-asset model output: `importResult.analysis.assetUnderstanding`.
- Per-shot output: `importResult.analysis.segments[n].assetUnderstanding`.
- A photo/local adapter may attach `item.assetUnderstanding`.
- Measured dimensions, duration, FPS, audio presence and recording dates remain in `item.metadata`. They are not inferred from semantic labels.
- Human-readable model output should be English. Enum values are mapped to English UI labels.
- Unknown fields must be omitted, not filled with default scores or false booleans.
- Whole-video semantics are never copied onto every detected segment.

## UI rules

Cards use the real asset title (user title, metadata title, then filename without its extension). A real model summary is secondary. Capture icon, one main shot role, up to three editing attributes, duration and compact technical/audio state appear only when available. No generic landscape/video titles or unavailable-analysis placeholders are rendered. The full filename remains in the tooltip and Original file section. A high frame rate does not prove slow motion, a camera model does not prove a filming method, and an embedded subtitle track does not prove dialogue. Legacy `hookScore`, `formatGuess`, and heuristic segment roles are never treated as model output.

Six filter groups use only observed values: Content, Scene/event, Capture, Shot, Edit use, Quality/audio. Date range, resolution, orientation, device and place are secondary filters. Related quick tags replace processing-status tabs. Values and counts intersect the current media category, favorite scope, search query and other selected groups; selected zero-result values remain removable. Search includes filenames, descriptions, tags, places, recording dates, speech text and extracted subtitles. Missing capture dates never pass a date-range filter. Favorites are persisted with the asset in IndexedDB.

Details remain a modal with a persistent title and icon-only close button. The preview stays visible while categorized information scrolls independently; there are no tabs. Below the video, a scrubber and scene thumbnails seek existing segment boundaries and track playback. These boundaries may include estimated splits. Descriptions prefer saved user notes, then real model summaries, otherwise a factual metadata description; the fallback is not a visual-content analysis. User descriptions are editable and persisted. Sections contain actual editing, capture, content, quality, audio, transcript and original-file data. Transcript rows seek the preview. Closing pauses/unloads preview and restores focus through native dialog behavior.

## Web cloud analysis (2026-09-27)

The web-only `/api/vision` route now produces overall and per-scene `assetUnderstanding`
using OpenAI Responses with sampled frames. It requires a server `OPENAI_API_KEY`;
see `CLOUD-ANALYSIS.md`. The web report displays full descriptions instead of
metadata fallback sentences. Objects, visible text, visual style, and uncertainty
are preserved. Long visual summaries are no longer truncated to card-label length.
Older saved results require an explicit **Analyze content** action. The Mac service
does not dispatch this cloud route and currently has no bundled local vision model.

## Base/local analysis limits

The base/local backend supplies measured metadata, cuts and optional subtitles, but does not itself emit semantic `assetUnderstanding`. The web cloud route adds that output only after successful model analysis. Existing footage without visual analysis uses its actual title/filename and measured metadata, not invented scene descriptions. Missing semantic fields are omitted. Timeline insertion and similar-shot retrieval are not connected and are not exposed as fake buttons. No fixture data is inserted into the real library.

## Regression checks

Run `node tests/asset-understanding.test.cjs`, `node tests/library.test.cjs`, `node tests/library-import.test.cjs`, and the metadata tests. The semantic test fixture is test-only and covers populated results, unknown states, malformed fields, date/audio filters, and per-shot isolation.
