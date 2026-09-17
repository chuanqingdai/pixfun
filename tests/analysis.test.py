#!/usr/bin/env python3
"""Regression checks for timeline segmentation and representative frames."""

import sys
import types
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.modules.setdefault("cgi", types.ModuleType("cgi"))

from app import build_creative_plan, make_segments, subtitle_time_seconds


def assert_contiguous(segments: list[dict], duration: float) -> None:
    assert segments[0]["start"] == 0
    assert segments[-1]["end"] == duration
    for current, following in zip(segments, segments[1:]):
        assert current["end"] == following["start"]


single_shot_minute = make_segments(60, [])
assert len(single_shot_minute) == 6, "A one-minute video needs a useful multi-segment editor timeline"
assert_contiguous(single_shot_minute, 60)

gradual_short = make_segments(30, [])
assert len(gradual_short) == 4, "A 30-second video should expose multiple representative scenes"
assert_contiguous(gradual_short, 30)

detected_cuts = make_segments(32, [3.2, 8.5, 19.0, 27.4])
assert len(detected_cuts) == 5, "Detected scene boundaries must be preserved"
assert [segment["start"] for segment in detected_cuts[1:]] == [3.2, 8.5, 19.0, 27.4]
assert_contiguous(detected_cuts, 32)

dense_storyboard = make_segments(60, [3, 7, 12, 18, 24, 30, 36, 42, 48, 54])
assert len(dense_storyboard) == 8, "Dense edits should remain scannable in the timeline"
assert_contiguous(dense_storyboard, 60)

very_short = make_segments(5, [])
assert len(very_short) == 1, "Very short clips should not be over-segmented"

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

print("PASS: Timeline segmentation and subtitle timestamps are stable.")
