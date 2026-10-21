# Agent story compilation

Create, plan and AI modification requests use the installed VisionFlow 0.9.1
story engine without selecting a skill. Analysis, retrieval and subtitles do not
compile stories. Skills still require explicit invocation; no Travel Vlog opening
montage is added by default. New-film creation analyzes the selected material,
waits for itinerary confirmation, then prepares the script for explicit approval
before rendering. Confirmation snapshots remain in the conversation history.

## Map-first creation

The Media map's Create action now starts the same local workflow directly. It
does not replace an unsent conversation draft or navigate to the conversation.
`creationSurface: "map"` is persisted with the run; project history and the map's
Continue menu reopen that run after navigation or restart.

The existing map remains on the left and a 340-point work column shows one
current stage: per-source analysis progress, pending itinerary, story strategy,
or preview. Source covers open Media details; selecting a route row or shot
focuses its map point. Story badges identify shot numbers (including repeated
uses); dashed connections continue to mean capture order, not actual travel.
Unlocated sources are selectable from the map header and remain in the review
list without invented pins.

Only pending itinerary pins are draggable. `trip_coordinates` validates WGS84
ranges, membership and the proposal's `updatedAt` revision, saves a pending
overlay, and does not mutate original media. Typed coordinates provide an
alternative to pointer dragging; restoring the original position is explicit.
Moving a coordinate clears its previous place label and does not silently start
geocoding. `confirm_trip` persists derived locations through the existing
workflow; `ignore_trip` does not apply them. Both itinerary and script approval
remain manual gates with immutable answered snapshots. Story compilation still
uses the engine handoff, compiler and audit below; the map is presentation, not
a new inference engine.

The UI intentionally does not introduce a second editor, road routing, automatic
GPS correction, or freeform Agent chat. Fine-grained timeline editing continues
in the existing editor. Failure keeps completed work and exposes retry in place.

1. `ModelGateway.story(context)` runs `story_hints.handoff` and returns the
   engine's director guidance. Indexed descriptions and source-timed transcripts
   remain unverified evidence. The existing text model proposes shots and chapter
   intentions using these inputs; no additional model pass is introduced.
2. After timeline/selection/lock validation, `ModelGateway.story(compile)` calls
   `story_restore.compile_plan`, the same compiler used by `vf story create`.
   The adapter supplies exact library IDs, paths, source fingerprints and ranges;
   model output never supplies filesystem paths. Engine output is mapped back to
   the existing timeline while retaining shot IDs, locks, labels and sections.
3. Source and required-coverage failures stop with an error. `story_qc.audit`
   attention flags are advisory, not a new approval gate or aesthetic verdict.
   Existing Pixfun sound/title/transition resolution and rendering follow.

The CPU-only worker does not load MLX or create another material catalog.
Cancellation, bounded timeout and capability observations use the existing
worker infrastructure. Missing engine/adapter fails explicitly; no silent fake
story fallback. The packaging script ships `vf_story.py` beside the worker.

Each run writes `story-vN/story.json` with chapters, exact sources, source ranges,
coverage, evidence handoff and rule checks. `storyExecution.timelineVersion`
identifies the Pixfun edit it describes. Manual edits or undo mark it stale and
retain the original artifact; they do not silently overwrite the user's edit or
start AI planning. Sound QC is not claimed: the compiler receives the visual edit
before Pixfun resolves final sound.

Verification:

```sh
.desktop-venv/bin/python tests/story-engine.test.py
.desktop-venv/bin/python tests/agent.test.py
python3 scripts/verify-packaged-agent.py dist-native/Pixfun.app --cases photos --require-story-engine
```

The first suite uses the real installed engine and production CPU worker. Agent
contracts use fixture inference, including a real-engine compilation/render test.
The packaged check uses real local inference and isolated storage, never the
production project database.

## Native editor assistance

The existing Replace picker requests `POST /api/desktop/agent/editor-assist`
with native authorization. `agent_editor.py` scopes sources to the saved run,
validates the current draft/version, and calls the CPU story worker. It does not
save the draft, enqueue analysis, invoke a model, load a skill or create a catalog.

The adapter uses VisionFlow's `story_cut.interval` to center an exact-duration
replacement inside cached shot evidence, and `story_hints.coverage` to exclude
already-used ranges. Ranking uses shared cached story roles and description
terms (including Chinese bigrams), not semantic inference or a beauty score.
At most three alternatives are returned, preferring different sources. Same-file
alternatives are allowed outside the current range. Missing, stale, too-short or
unusable evidence is not promoted; the complete manual project-media list remains.
Before application the source revision is checked again. Native application also
checks the draft has not changed, validates the edit, preserves the shot ID and
section, and records one ordinary undo transaction. Smart replacement keeps the
duration, so it does not move other clips or retime captions and narration.

`story_qc.audit` runs on a debounced snapshot of the current draft, not the stale
compiled story artifact. Only long-hold and adjacent repeated-source hints appear
inside selected clip details; clicking locates without modifying or playing.
These are review prompts, not aesthetic judgments. Sound QC is deliberately not
claimed, and review failure never gates editing or export. Canceled/stale responses
are ignored; CPU requests have a 12-second cancellation deadline.

```sh
.desktop-venv/bin/python tests/editor-assist.test.py
.desktop-venv/bin/python tests/desktop-service.test.py DesktopServiceTests.test_editor_assistance_native_readonly_and_exact_replacement
node scripts/test-native.cjs
```

## Speech-boundary trim assistance

The selected video's existing trim controls request `trim` assistance. No speech
recognition is started. Source-bound local ASR requires its current file/model
signature; embedded captions require matching imported file size and mtime;
sidecar captions are read locally again, with the same source identity checks.
Unknown/stale, silent, invalid, proxy-domain, rejected or music-only evidence is
not offered. Cue-level ASR remains unverified speech, not word alignment.

The story worker validates evidence through `story_hints.handoff`. Consecutive
unfinished cues are joined until terminal punctuation or a 350 ms gap; overlapping
cues and unpunctuated blocks over 35 seconds do not yield cut points. Punctuation
inside a cue never invents additional timestamps. These are references to check
against original audio, not a claim of precise sentence detection.

Only candidate starts/ends within one second of the corresponding trim edge are
offered. Markers are passive; dragging and typed times never snap. Applying a
suggestion explicitly rechecks source and transcript revisions, respects existing
draft/lock/layer validation and records one normal undo transaction. Cancellation
or a changed selection/draft/run discards the response. Missing speech leaves the
ordinary controls unchanged. Music beat snapping is not implemented in this round.

Isolated interactive UI fixture (no production library or media writes):

```sh
node scripts/build-story-popover-smoke.cjs --speech
```
