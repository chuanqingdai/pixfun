# Pixfun split creation workspace — Design QA

- Latest scoped reference: `/var/folders/q0/9fgxy0s17b51hyks3h_1806w0000gn/T/codex-clipboard-185f5d40-702d-4344-ab93-eb97879b097d.png`
- Step-two redesign reference: `/var/folders/q0/9fgxy0s17b51hyks3h_1806w0000gn/T/codex-clipboard-aee620e0-5138-4e1e-a95d-c498b1112709.png`
- Primary visual reference: `/var/folders/q0/9fgxy0s17b51hyks3h_1806w0000gn/T/codex-clipboard-79a64b88-427d-40e9-8b9c-903b2fb9ddda.png`
- Supporting layout references: `/var/folders/q0/9fgxy0s17b51hyks3h_1806w0000gn/T/codex-clipboard-e6bce1b5-9886-4ae2-966d-40fe8bea5bc3.png`, `/var/folders/q0/9fgxy0s17b51hyks3h_1806w0000gn/T/codex-clipboard-9319f66f-2bd1-40b7-9743-23c9f7cfb8eb.png`, `/var/folders/q0/9fgxy0s17b51hyks3h_1806w0000gn/T/codex-clipboard-c87687df-111a-4db9-a486-f3628eae3ad6.png`
- Source visual truth: the existing Pixfun dark UI system plus the user-approved direction to keep the video visible beside a GPT-like conversation. Earlier studio captures document the original video/timeline state and the separate chat state.
- Browser-rendered implementation: `http://127.0.0.1:8765/?v=split-workspace-1#studio`, captured and reviewed inline from the Codex in-app browser after a real YouTube import.
- Viewport: 1071 × 951 CSS pixels at 1× density; implementation capture was 1071 × 951 pixels.
- State: imported 19-second horizontal video, four detected storyboard segments, four extracted subtitle cues, playhead at 00:00, followed by a submitted presenter/language request.

## Full-view comparison evidence

The former design separated Review and the Pixfun conversation into different screens. The revised full view keeps the player, continuous storyboard timeline, extracted subtitles, and subdued source metadata in the wider left pane. The narrower right pane contains only Pixfun, the message history, a bottom composer, and Export. This matches the approved product behavior: users can inspect the source while directing changes.

The live import demonstrated four real scene thumbnails and four extracted subtitle cues. The initial request changed from the one-line composer into a user message without navigating away, and the next composer remained anchored inside the right pane. Export opened only after confirmation and showed the existing render summary.

## Focused region comparison evidence

The media pane, timeline, subtitle list, chat header, conversation turns, and composer were large enough to inspect in the 1071 × 951 capture, so separate crops were not needed. The focused post-submit state confirmed that the composer did not overlap the timeline or subtitle rows and that the video remained visible beside the conversation.

## Findings

- GPT-style direction flow: the first request composer now lives at the bottom of the right pane with the concise `Describe changes…` prompt. After submission, the request appears as the first user turn in the same pane. The chat keeps only Pixfun, Export, messages, and the `Message Pixfun…` composer; the long context explanation, structured draft cards, visible success copy, bottom progress label, and Script notes remain removed.
- Direction composer display: fixed the Mac textarea chrome shown in `/var/folders/q0/9fgxy0s17b51hyks3h_1806w0000gn/T/codex-clipboard-c92b4a38-b1ae-4c62-a657-341dd8fd37eb.png`. The one-line state no longer shows a scrollbar or resize handle, the textarea and action button share a precise 50px control height, and scrolling appears only after the auto-growing field reaches its 120px cap. The redundant divider above the subdued step label is also removed.
- Landing-page import feedback: link analysis and local upload now place the active `Loading…` state inside the initiating button. The duplicate progress sentence below the controls is removed; validation and failure messages still appear there, and the original button label returns after an error.
- Direction input focus: the stable neutral focus treatment is retained. The input uses a distinct `#1c1721` surface inside a `#151219` composer without competing with the violet action button.
- Create to Export: Review and direction are merged into one Create panel. Pixfun parses the request in the background and converts it into a conversation turn in place; export stays disabled until the direction is confirmed.
- Subtitle presentation: extracted lines now live in a dedicated scrollable panel below the timeline. They no longer share the segment track or playhead geometry; every line keeps its own timestamp and seek action.
- No remaining P0, P1, or P2 issues for the requested split workspace.
- Fonts and typography: existing Pixfun type tokens, optical weights, compact labels, and hierarchy remain consistent; chat copy is readable at the narrower pane width.
- Spacing and layout rhythm: the 1.62/.92 desktop grid gives the player visual priority, while 24px pane spacing and 16px card radii match the product system. The layout stacks at 960px.
- Colors and visual tokens: violet focus, dark neutral surfaces, borders, and muted secondary text remain within the Pixfun palette with sufficient foreground contrast.
- Image quality and asset fidelity: the live player and server-extracted scene frames are used directly; no placeholder or recreated imagery replaces video content.
- Copy and content: labels are reduced to Create, Export, Video, Pixfun, Timeline, and Subtitles. No process explanation competes with the task.
- Hierarchy: video, storyboard, subtitle list, secondary metadata, and conversation read in task order.
- Alignment: storyboard clips remain contiguous and the playback cursor stays synchronized with the player.
- Visual tokens: violet focus, dark surfaces, borders, and typography stay within the Pixfun system.
- Responsiveness: the two panes become one column below 960px; the timeline remains horizontally scrollable when scenes exceed the available width.
- Accessibility: scenes and subtitle cues are keyboard-operable buttons with descriptive labels; the moving playhead remains decorative.
- Removed scope: per-scene clip downloads, download readiness copy, and the clip output list are absent from both UI and server routes.

## Comparison history

- Earlier P2: the fixed viewport composer covered lower subtitle content and separated video review from conversation. Fix: moved both composers into the right-pane grid and merged the first two steps. Post-fix evidence: the live post-submit capture shows the full video/timeline/subtitle stack beside the complete chat pane with no overlap.
- Earlier P2: three prominent steps overstated the workflow. Fix: reduced navigation to Create → Export and kept Export disabled until confirmation. Post-fix evidence: live interaction successfully submitted a request in Create and opened Export only through the right-pane action.

## Verification

- Real YouTube import produced four contiguous storyboard segments, four server-extracted thumbnails, and four subtitle cues.
- Initial direction and follow-up composer transitions were tested in the live browser.
- Export gating and the Back to create path were tested.
- Browser console errors checked: none.
- Embedded subtitle timestamp parsing is covered by regression tests.
- `python3 tests/analysis.test.py`: passed.
- `node tests/studio.test.cjs`: passed.
- `node tests/motion.test.cjs`: passed.
- `node tests/smoke.cjs <video>`: passed.
- `node --check public/pixfun.js`: passed.
- `git diff --check`: passed.

final result: passed
