# Timeline playhead motion — Design QA

- Source visual truth: `/var/folders/q0/9fgxy0s17b51hyks3h_1806w0000gn/T/codex-clipboard-5eefd049-2264-474b-81e1-53fa45cc71d5.png`
- Browser-rendered implementation: `/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/timeline-playhead-multiclip-final.jpg`
- Focused implementation crop: `/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/timeline-playhead-final-crop.png`
- Combined comparison input: `/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/timeline-playhead-comparison.png`
- Responsive motion evidence: `/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/timeline-playhead-mobile-follow.jpg`
- Source pixels: 852 × 230. Implementation full screenshot: 1071 × 951 at 1× density. Focused crop: 880 × 185. Mobile screenshot: 375 × 812 after browser chrome.
- State: dark Studio Review screen, four detected clips, video playing in Scene 02 at approximately 00:04.

## Full-view comparison evidence

The implementation keeps the existing single-column Studio layout and places the active playhead inside the real imported-video timeline. The four clips retain their extracted frames and timestamps while the active clip receives the Pixfun violet outline.

## Focused comparison evidence

The combined comparison places the supplied reference and the live implementation in one image. Both show a vertical violet playhead crossing the active clip, a time label above the track, a `Now · time` badge next to the cursor, subdued inactive clips, and a highlighted current scene. The implementation intentionally omits the decorative audio waveform because this request concerns cursor motion and the local editor has no decoded waveform data.

## Findings

- No remaining P0/P1/P2 issue for the requested playhead behavior.
- Fonts and typography: compact numeric labels use the existing UI font and tabular numerals; the time and `Now` labels remain readable while moving.
- Spacing and layout rhythm: the label sits above the track and the contextual badge sits inside it, following the reference hierarchy without increasing timeline height.
- Colors and visual tokens: playhead, labels, active border, and glow use the existing Pixfun violet family; inactive clips keep the dark neutral treatment.
- Image quality and asset fidelity: timeline thumbnails continue to come from actual browser-extracted video frames rather than placeholders.
- Copy and content: `Now · 0:04`, scene names, and clip time ranges are concise and synchronized with the preview.
- Motion: `requestAnimationFrame` updates the playhead continuously during playback; pause, seek, and video end snap to the exact media time. On narrow screens, the horizontal timeline follows the cursor so the active clip stays visible.
- Accessibility: clips remain keyboard-operable buttons with `aria-pressed`; the decorative moving playhead stays out of the accessibility tree, avoiding noisy per-frame announcements.

## Comparison history

1. First pass P2: at 00:00 the `Now` badge overlapped the scene label because both occupied the upper-left corner of the active clip.
2. Fix: moved scene labels to the lower image edge above the timestamp row, leaving the upper area for the cursor badge.
3. Post-fix evidence: `qa/timeline-playhead-multiclip-final.jpg` shows Scene 02 highlighted with the playhead and both labels readable; `qa/timeline-playhead-mobile-follow.jpg` shows the narrow timeline automatically scrolled to Scene 03 at 00:07.

## Primary interactions tested

- Imported the 12-second four-scene test video and confirmed four detected timeline clips.
- Started native video playback and visually confirmed continuous playhead movement from Scene 01 into Scene 02.
- Confirmed active-scene border, top timestamp, and `Now` badge update together.
- Confirmed mobile horizontal follow at 00:07 keeps Scene 03 and the cursor in view.
- Confirmed pause/end synchronization through the registered playback lifecycle and controller regression tests.
- Browser console: no errors.

## Verification

- `node --check public/pixfun.js`: passed.
- `node tests/studio.test.cjs`: passed.
- `node tests/motion.test.cjs`: passed.

## Follow-up polish

The audio waveform shown in the reference remains intentionally absent. It can be added later when the editor exposes real waveform samples instead of a decorative approximation.

final result: passed
