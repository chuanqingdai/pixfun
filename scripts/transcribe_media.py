#!/usr/bin/env python3
"""Transcribe one media file with MLX Whisper and write normalized JSON cues."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("HF_HOME", str(ROOT / "data" / "models" / "huggingface"))
MODEL = os.environ.get("PIXFUN_WHISPER_MODEL", "mlx-community/whisper-small-mlx")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: transcribe_media.py MEDIA OUTPUT_JSON", file=sys.stderr)
        return 2
    source = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2]).resolve()
    if not source.is_file():
        print("media file not found", file=sys.stderr)
        return 2

    import mlx_whisper

    result = mlx_whisper.transcribe(
        str(source),
        path_or_hf_repo=MODEL,
        verbose=False,
        word_timestamps=False,
    )
    cues = []
    for segment in result.get("segments", []):
        start = max(0.0, float(segment.get("start") or 0))
        end = max(start, float(segment.get("end") or start))
        text = " ".join(str(segment.get("text") or "").split())
        if text and end > start:
            cues.append({"start": round(start, 2), "end": round(end, 2), "text": text[:500]})
    payload = {
        "model": MODEL,
        "language": result.get("language"),
        "text": " ".join(str(result.get("text") or "").split()),
        "cues": cues[:300],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
