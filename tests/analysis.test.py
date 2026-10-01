#!/usr/bin/env python3
"""Regression checks for timeline segmentation and representative frames."""

import sys
import types
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.modules.setdefault("cgi", types.ModuleType("cgi"))

from app import build_creative_plan, make_segments, make_structure_cues, subtitle_time_seconds


def assert_contiguous(segments: list[dict], duration: float) -> None:
    assert segments[0]["start"] == 0
    assert segments[-1]["end"] == duration
    for current, following in zip(segments, segments[1:]):
        assert current["end"] == following["start"]


single_shot_minute = make_segments(60, [])
assert len(single_shot_minute) == 6, "A one-minute video needs a useful multi-segment editor timeline"
assert_contiguous(single_shot_minute, 60)
assert single_shot_minute[0]['boundary']['type'] == 'video_start'
assert all(s['boundary']['type'] == 'time_split' for s in single_shot_minute[1:])

gradual_short = make_segments(30, [])
assert len(gradual_short) == 4, "A 30-second video should expose multiple representative scenes"
assert_contiguous(gradual_short, 30)

detected_cuts = make_segments(32, [3.2, 8.5, 19.0, 27.4])
assert len(detected_cuts) == 5, "Detected scene boundaries must be preserved"
assert [segment["start"] for segment in detected_cuts[1:]] == [3.2, 8.5, 19.0, 27.4]
assert_contiguous(detected_cuts, 32)
assert all(s['boundary']['type'] == 'detected_cut' for s in detected_cuts[1:])

dense_storyboard = make_segments(60, [3, 7, 12, 18, 24, 30, 36, 42, 48, 54])
assert len(dense_storyboard) == 8, "Dense edits should remain scannable in the timeline"
assert_contiguous(dense_storyboard, 60)
assert sum(s['containedCutCount'] for s in dense_storyboard) == 3, 'Grouped cuts retain evidence instead of disappearing'

very_short = make_segments(5, [])
assert len(very_short) == 1, "Very short clips should not be over-segmented"

structure = make_structure_cues(detected_cuts, [
    {"start": 0.2, "end": 2.8, "text": "Stop scrolling: this changes everything."},
    {"start": 9.0, "end": 16.0, "text": "Here is the main idea and how it works."},
    {"start": 28.0, "end": 31.5, "text": "Try it for yourself today."},
], 32)
assert [cue["label"] for cue in structure] == ["Hook", "Setup", "Core idea", "Proof / payoff", "CTA"]
assert_contiguous(structure, 32)
assert structure[0]["summary"].startswith("Stop scrolling")
assert structure[-1]["summary"].startswith("Try it")
assert sum(len(cue["sceneIds"]) for cue in structure) == len(detected_cuts)

assert subtitle_time_seconds("00:01:02,500") == 62.5
assert subtitle_time_seconds("01:02.250") == 62.25
assert subtitle_time_seconds("invalid") == 0

creative_plan = build_creative_plan({
    "instructions": "Replace the presenter with a man in a black suit. Translate the voice and captions into Spanish. Keep the shot order and pacing."
})
assert creative_plan["ready"] is True
assert [item["label"] for item in creative_plan["items"]] == ["Presenter", "Language", "Keep"]

asset_plan = build_creative_plan({"instructions": "Replace the product with my product."})
assert asset_plan["ready"] is False
assert asset_plan["missing"], "Owned product requests should ask for a reference asset"

print("PASS: Timeline segmentation, subtitle timestamps, and content structure are stable.")
