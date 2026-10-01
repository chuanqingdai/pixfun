#!/usr/bin/env python3
"""Local MVP for turning a reference short video into editable variants.

The web server itself uses the Python standard library. Optional local tools:
  - ffmpeg / ffprobe for media inspection and rendering
  - yt-dlp for URL ingestion
  - a project-local MLX Whisper environment for speech transcription
"""

from __future__ import annotations

import cgi
import base64
import html
import json
import math
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import time
import threading
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import unquote, urlparse
from transcript_quality import checked_cues


ROOT = Path(__file__).resolve().parent
PUBLIC = Path(os.environ.get("PIXFUN_PUBLIC_DIR", str(ROOT / "public")))
DATA = Path(os.environ.get("PIXFUN_DATA_DIR", str(ROOT / "data")))
UPLOADS = DATA / "uploads"
JOBS = DATA / "jobs"
OUTPUTS = DATA / "outputs"
TRANSCRIBER = ROOT / "scripts" / "transcribe_media.py"
TRANSCRIBER_PYTHON = ROOT / ".venv" / "bin" / "python"
VISION_LOCK = threading.Lock()
APPLICATION_LOCK = threading.Lock()
APPLICATION_ATTEMPTS = {}
for folder in (UPLOADS, JOBS, OUTPUTS):
    folder.mkdir(parents=True, exist_ok=True)


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def run_command(args: list[str], timeout: int = 120) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired as exc:
        return 124, exc.stdout or "", f"command timed out after {timeout}s"
    except OSError as exc:
        return 127, "", str(exc)


def safe_name(name: str, fallback: str = "source.mp4") -> str:
    name = Path(name or fallback).name
    name = re.sub(r"[^\w.\-\u4e00-\u9fff ]+", "_", name).strip(" .")
    return name or fallback


def json_bytes(payload: object) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def read_job(job_id: str) -> dict:
    if not isinstance(job_id, str) or not re.fullmatch(r"[0-9a-f]{12}", job_id):
        raise FileNotFoundError("Invalid job ID")
    path = JOBS / f"{job_id}.json"
    if not path.exists():
        raise FileNotFoundError(job_id)
    return json.loads(path.read_text(encoding="utf-8"))


def write_job(job: dict) -> None:
    (JOBS / f"{job['id']}.json").write_text(
        json.dumps(job, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def media_url(kind: str, job_id: str, filename: str) -> str:
    return f"/media/{kind}/{job_id}/{filename}"


def probe_media(source: Path) -> dict:
    if not command_exists("ffprobe"):
        return {"available": False, "message": "ffprobe was not found. Video metadata cannot be read."}
    code, stdout, stderr = run_command(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(source),
        ],
        timeout=30,
    )
    if code != 0:
        return {"available": False, "message": stderr[-500:] or "ffprobe could not read the video."}
    try:
        data = json.loads(stdout)
    except json.JSONDecodeError:
        return {"available": False, "message": "ffprobe returned unreadable data."}
    streams = data.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), {})
    audio = next((s for s in streams if s.get("codec_type") == "audio"), {})
    subtitles = [s for s in streams if s.get("codec_type") == "subtitle"]
    fmt = data.get("format", {})
    tags = {**video.get("tags", {}), **fmt.get("tags", {})}
    duration = float(fmt.get("duration") or video.get("duration") or 0)
    width = int(video.get("width") or 0)
    height = int(video.get("height") or 0)
    fps_value = video.get("r_frame_rate") or "0/1"
    try:
        n, d = fps_value.split("/")
        fps = round(float(n) / float(d), 2) if float(d) else 0
    except (ValueError, ZeroDivisionError):
        fps = 0
    return {
        "available": True,
        "capturedAt": tags.get("com.apple.quicktime.creationdate"),
        "mediaCreatedAt": tags.get("creation_time"),
        "dateSource": "QuickTime creationdate" if tags.get("com.apple.quicktime.creationdate") else "Container creation_time" if tags.get("creation_time") else None,
        "camera": tags.get("com.apple.quicktime.model") or tags.get("model"),
        "duration": round(duration, 2),
        "durationLabel": format_duration(duration),
        "width": width,
        "height": height,
        "fps": fps,
        "hasAudio": bool(audio),
        "hasSubtitles": bool(subtitles),
        "subtitleCount": len(subtitles),
        "subtitleCodec": subtitles[0].get("codec_name", "unknown") if subtitles else None,
        "videoCodec": video.get("codec_name", "unknown"),
        "audioCodec": audio.get("codec_name", "unknown") if audio else None,
        "size": int(fmt.get("size") or source.stat().st_size),
        "format": fmt.get("format_name", "unknown"),
        "orientation": "Portrait" if height >= width else "Landscape",
    }


def format_duration(seconds: float) -> str:
    total = max(0, int(round(seconds)))
    minutes, sec = divmod(total, 60)
    return f"{minutes}:{sec:02d}" if minutes else f"0:{sec:02d}"


def minimum_segment_count(duration: float) -> int:
    if duration < 8:
        return 1
    if duration < 16:
        return 3
    return min(8, max(4, math.ceil(duration / 10)))


def detect_cuts(source: Path, duration: float) -> list[float]:
    if not command_exists("ffmpeg"):
        return []
    desired_cuts = max(0, minimum_segment_count(duration) - 1)
    cuts: list[float] = []
    # Start conservative, then lower the threshold for animation, dissolves,
    # and subtle camera changes until enough real storyboard boundaries exist.
    for threshold in (0.35, 0.28, 0.22, 0.16):
        filter_expr = rf"select=gt(scene\,{threshold}),showinfo"
        code, _, stderr = run_command(
            [
                "ffmpeg", "-hide_banner", "-i", str(source), "-vf", filter_expr,
                "-an", "-f", "null", "-",
            ],
            timeout=90,
        )
        if code not in (0, 1):
            continue
        candidate: list[float] = []
        for match in re.finditer(r"pts_time:([0-9.]+)", stderr):
            value = float(match.group(1))
            if 0.4 < value < max(0.5, duration - 0.3):
                if not candidate or value - candidate[-1] > 0.7:
                    candidate.append(round(value, 2))
        if len(candidate) > len(cuts):
            cuts = candidate
        if len(cuts) >= desired_cuts:
            break
    # Keep the timeline scannable while sampling boundaries across the whole
    # video instead of dropping the ending when many rapid cuts are detected.
    # Keep all detected boundaries as evidence. make_segments may group them
    # for navigation, but must not erase the additional cuts inside a group.
    return cuts


def make_segments(duration: float, cuts: list[float]) -> list[dict]:
    if duration <= 0:
        duration = 30
    points = sorted({0.0, duration, *[cut for cut in cuts if 0.4 < cut < duration - 0.3]})
    minimum_count = minimum_segment_count(duration)
    if len(points) - 1 > 8:
        interior = points[1:-1]
        points = [0.0] + [interior[round(index * (len(interior) - 1) / 6)] for index in range(7)] + [duration]
    # Scene detection can miss gradual animation, talking-head edits, and long
    # dissolves. Preserve detected cuts, then subdivide the longest remaining
    # spans so the editor always exposes a useful multi-shot timeline.
    while len(points) - 1 < minimum_count:
        spans = [(points[index + 1] - points[index], index) for index in range(len(points) - 1)]
        span, index = max(spans, default=(0, 0))
        if span < 1.3:
            break
        points.append(round(points[index] + span / 2, 3))
        points.sort()
    raw = []
    for start, end in zip(points, points[1:]):
        if end - start >= 0.65:
            raw.append((start, end))
    # The semantic labels are intentionally editable heuristics in the MVP.
    labels = ["Opening hook", "Problem / conflict", "Evidence / demonstration", "Turning point / reaction", "Closing CTA"]
    result = []
    for index, (start, end) in enumerate(raw[:8]):
        if index == 0:
            label = labels[0]
        elif end >= duration - max(3, duration * 0.14):
            label = labels[-1]
        else:
            label = labels[min(index, len(labels) - 2)]
        result.append(
            {
                "id": f"seg-{index + 1}",
                "label": label,
                "start": round(start, 2),
                "end": round(end, 2),
                "duration": round(end - start, 2),
                "boundary": {"type": "video_start" if start == 0 else "detected_cut" if any(abs(start - cut) < 0.015 for cut in cuts) else "time_split"},
                "containedCutCount": sum(start + 0.015 < cut < end - 0.015 for cut in cuts),
                "percent": round((end - start) / duration * 100, 1),
                "note": "Refine the dialogue or scene description in the next step.",
            }
        )
    if not result:
        step = duration / 5
        result = [
            {
                "id": f"seg-{i + 1}",
                "label": labels[i],
                "start": round(i * step, 2),
                "end": round((i + 1) * step, 2),
                "duration": round(step, 2),
                "boundary": {"type": "video_start" if i == 0 else "time_split"},
                "containedCutCount": 0,
                "percent": 20,
                "note": "Initial duration-based segments. Review and adjust as needed.",
            }
            for i in range(5)
        ]
    return result


def make_timeline_thumbnails(source: Path, job_id: str, segments: list[dict]) -> list[dict]:
    """Extract one representative frame for every editor timeline segment."""
    if not command_exists("ffmpeg"):
        return segments
    output_dir = OUTPUTS / job_id
    output_dir.mkdir(parents=True, exist_ok=True)
    for index, segment in enumerate(segments[:24]):
        start = max(0.0, float(segment.get("start") or 0))
        span = max(0.05, float(segment.get("duration") or 0))
        timestamp = min(float(segment.get("end") or start + span) - 0.08, start + max(0.08, span * 0.42))
        filename = f"timeline-{index + 1:02d}.jpg"
        output = output_dir / filename
        code, _, _ = run_command(
            [
                "ffmpeg", "-y", "-ss", f"{max(0, timestamp):.3f}", "-i", str(source),
                "-frames:v", "1", "-vf",
                "scale=480:480:force_original_aspect_ratio=decrease,setsar=1",
                "-q:v", "3", str(output),
            ],
            timeout=30,
        )
        if code == 0 and output.exists() and output.stat().st_size > 0:
            segment["thumbnailUrl"] = media_url("output", job_id, filename)
            segment["thumbnailTime"] = round(max(0, timestamp), 2)
            segment["thumbnailFit"] = "native"
    return segments


def subtitle_time_seconds(value: str) -> float:
    parts = value.strip().replace(",", ".").split(":")
    try:
        if len(parts) == 3:
            return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
        if len(parts) == 2:
            return float(parts[0]) * 60 + float(parts[1])
    except ValueError:
        return 0.0
    return 0.0


def parse_subtitle_text(content: str) -> list[dict]:
    """Read complete SRT/WebVTT captions, retaining all cues and their text."""
    cues = []
    timestamp = r"(?:\d+:)?\d{2}:\d{2}[.,]\d{3}"
    for block in re.split(r"\n\s*\n", content.lstrip("\ufeff").replace("\r\n", "\n").strip()):
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        if not lines or re.match(r"^(NOTE|STYLE|REGION)(?:\s|$)", lines[0]):
            continue
        for index, line in enumerate(lines):
            # Some NPS VTT exports use comma-separated start/end timestamps.
            match = re.match(rf"^({timestamp})\s*(?:-->|,)\s*({timestamp})(?:\s.*)?$", line)
            if not match:
                continue
            start, end = map(subtitle_time_seconds, match.groups())
            text = html.unescape(re.sub(r"<[^>]+>", "", " ".join(lines[index + 1:]))).replace(r"\N", " ").strip()
            if text and end > start:
                cues.append({"id": f"sub-{len(cues) + 1}", "start": round(start, 3), "end": round(end, 3), "text": text})
            break
    return cues


def local_subtitle_track(source: Path, previous_signature=None) -> dict:
    """Read a same-name local caption file; never fetch remote transcripts."""
    for suffix in (".vtt", ".srt", ".en.vtt", ".en.srt"):
        path = source.with_suffix(suffix)
        try:
            stat = path.stat()
            if not path.is_file() or stat.st_size > 5 * 1024 * 1024:
                continue
            signature = f"{path.name}:{stat.st_mtime_ns}:{stat.st_size}"
            if signature == previous_signature:
                return {}
            cues = parse_subtitle_text(path.read_text(encoding="utf-8-sig", errors="replace"))
            if cues:
                return {"subtitleCues": cues, "subtitleState": "sidecar", "subtitleSource": path.name,
                        "subtitleSignature": signature, "subtitleMessage": "Imported from a local caption file"}
        except OSError:
            continue
    return {}


def extract_subtitle_cues(source: Path, job_id: str) -> list[dict]:
    """Extract the first editable subtitle stream into timeline-aligned cues."""
    if not command_exists("ffmpeg"):
        return []
    output_dir = OUTPUTS / job_id
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / "subtitle-track.srt"
    code, _, _ = run_command(
        ["ffmpeg", "-y", "-i", str(source), "-map", "0:s:0", "-c:s", "srt", str(output)],
        timeout=60,
    )
    if code != 0 or not output.exists() or output.stat().st_size == 0:
        output.unlink(missing_ok=True)
        return []
    return parse_subtitle_text(output.read_text(encoding="utf-8", errors="replace"))


def transcribe_audio_cues(source: Path, job_id: str) -> tuple[list[dict], dict]:
    """Create timed subtitle cues from speech with the project-local MLX Whisper runtime."""
    if not TRANSCRIBER_PYTHON.exists() or not TRANSCRIBER.exists():
        return [], {"state": "unavailable", "message": "Local speech transcription is not installed"}
    output_dir = OUTPUTS / job_id
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / "speech-transcript.json"
    code, _, stderr = run_command(
        [str(TRANSCRIBER_PYTHON), str(TRANSCRIBER), str(source), str(output)],
        timeout=600,
    )
    if code != 0 or not output.exists():
        return [], {"state": "unavailable", "message": (stderr.strip().splitlines()[-1] if stderr.strip() else "Speech transcription failed")[:240]}
    try:
        payload = json.loads(output.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return [], {"state": "unavailable", "message": "Speech transcription returned invalid data"}
    cues = []
    for item in payload.get("cues", [])[:300]:
        try:
            start = max(0.0, float(item.get("start") or 0))
            end = max(start, float(item.get("end") or start))
        except (TypeError, ValueError):
            continue
        text = " ".join(str(item.get("text") or "").split())
        if text and end > start:
            cues.append({"id": f"sub-{len(cues) + 1}", "start": round(start, 2), "end": round(end, 2), "text": text[:500]})
    cues, rejected = checked_cues(cues)
    rejected += int(payload.get("rejectedCount") or 0)
    return cues, {
        "state": "partial" if cues and rejected else "unreliable" if rejected else "transcribed" if cues else "silent",
        "message": "Repetitive speech recognition was excluded. The transcript needs review." if rejected else "" if cues else "No speech was detected in this video",
        "language": payload.get("language") if cues else None,
        "text": " ".join(cue["text"] for cue in cues),
        "model": payload.get("model"),
    }


def make_structure_cues(segments: list[dict], subtitle_cues: list[dict], duration: float) -> list[dict]:
    """Group contiguous scenes into a small, timeline-aligned content structure."""
    if not segments:
        return []
    duration = max(float(duration or 0), float(segments[-1].get("end") or 0), 0.01)
    role_sets = {
        1: [("core", "Core idea", "Main message")],
        2: [("hook", "Hook", "Opening beat"), ("cta", "CTA", "Closing action")],
        3: [("hook", "Hook", "Opening beat"), ("core", "Core idea", "Main message"), ("cta", "CTA", "Closing action")],
        4: [("hook", "Hook", "Opening beat"), ("setup", "Setup", "Context and tension"), ("core", "Core idea", "Main message"), ("cta", "CTA", "Closing action")],
        5: [("hook", "Hook", "Opening beat"), ("setup", "Setup", "Context and tension"), ("core", "Core idea", "Main message"), ("proof", "Proof / payoff", "Evidence or reveal"), ("cta", "CTA", "Closing action")],
    }
    role_count = min(5, len(segments))
    roles = role_sets[role_count]
    result: list[dict] = []
    for index, (role, label, fallback) in enumerate(roles):
        first = round(index * len(segments) / role_count)
        last = round((index + 1) * len(segments) / role_count)
        grouped = segments[first:max(first + 1, last)]
        start = float(grouped[0].get("start") or 0)
        end = float(grouped[-1].get("end") or start)
        matching_text = [
            " ".join(str(cue.get("text") or "").split())
            for cue in subtitle_cues
            if float(cue.get("end") or 0) > start and float(cue.get("start") or 0) < end
        ]
        summary = " ".join(part for part in matching_text if part).strip()
        if len(summary) < 4:
            summary = fallback
        if len(summary) > 96:
            summary = summary[:93].rstrip() + "…"
        result.append({
            "id": f"beat-{index + 1}",
            "role": role,
            "label": label,
            "start": round(start, 2),
            "end": round(end, 2),
            "duration": round(max(0, end - start), 2),
            "percent": round(max(0, end - start) / duration * 100, 1),
            "sceneIds": [segment.get("id") for segment in grouped if segment.get("id")],
            "summary": summary,
            "confidence": "estimated",
        })
    return result


def build_creative_plan(brief: dict, has_references: bool = False) -> dict:
    """Turn a natural-language direction into a concise, capability-aware plan."""
    instruction = " ".join(str(brief.get("instructions") or "").split())[:5000]
    clauses = [part.strip(" .") for part in re.split(r"[.!?;\n]+|(?<=[，。；！？])", instruction) if part.strip(" .")]
    categories = [
        ("Presenter", r"presenter|person|character|face|man|woman|male|female|人物|角色|男性|女性|主播|讲述者"),
        ("Setting", r"setting|scene|background|studio|office|location|场景|背景|演播室|办公室"),
        ("Language", r"language|translate|translation|subtitle|caption|voice|dub|spanish|english|语言|翻译|字幕|配音|西班牙语|英语"),
        ("Script", r"script|dialogue|rewrite|message|copy|hook|cta|台词|文案|脚本|改写|开场|结尾"),
        ("Product & brand", r"product|brand|logo|offer|商品|产品|品牌|标志|优惠"),
        ("Style", r"style|premium|cinematic|energetic|minimal|funny|风格|高级|电影感|活力|极简|幽默"),
        ("Pacing", r"pace|pacing|rhythm|faster|slower|shorten|tempo|节奏|加快|减慢|缩短"),
        ("Keep", r"\bkeep\b|preserve|retain|same|保留|保持|不变"),
    ]
    items = []
    used = set()
    for label, pattern in categories:
        matching = [clause for clause in clauses if re.search(pattern, clause, re.I)]
        if label == "Pacing":
            matching = [clause for clause in matching if not re.search(r"\bkeep\b|preserve|retain|保留|保持|不变", clause, re.I)]
        if matching:
            value = ". ".join(matching)[:360]
            key = (label, value.lower())
            if key not in used:
                items.append({"label": label, "value": value, "status": "planned"})
                used.add(key)
    explicit = [
        ("Presenter", brief.get("person")),
        ("Language", brief.get("language") if str(brief.get("language") or "").lower() not in {"", "keep"} else ""),
        ("Script", brief.get("dialogue")),
        ("Product & brand", brief.get("material")),
    ]
    for label, value in explicit:
        value = " ".join(str(value or "").split())
        if value and not any(item["label"] == label for item in items):
            items.append({"label": label, "value": value[:360], "status": "planned"})
    if not items and instruction:
        items.append({"label": "Creative direction", "value": instruction[:500], "status": "planned"})
    needs_reference = bool(re.search(r"\b(my|our)\s+(product|logo|photo|footage|presenter|character)\b|我的(产品|标志|照片|素材|人物)", instruction, re.I))
    missing = [] if has_references or not needs_reference else ["Add the product, brand, presenter, or footage reference mentioned in your request."]
    return {"items": items, "missing": missing, "ready": bool(items) and not missing}


def make_analysis(source: Path, source_name: str, source_url: str = "") -> dict:
    metadata = probe_media(source)
    duration = float(metadata.get("duration") or 30)
    cuts = detect_cuts(source, duration)
    segments = make_segments(duration, cuts)
    aspect = "9:16" if metadata.get("height", 0) >= metadata.get("width", 1) else "16:9"
    return {
        "sourceName": source_name,
        "sourceUrl": source_url,
        "metadata": metadata,
        "cutCount": len(cuts),
        "cuts": cuts,
        "segments": segments,
        "formatGuess": "Talking-head / UGC short video" if aspect == "9:16" else "Landscape / explainer video",
        "hookScore": 78 if duration <= 45 else 61,
        "structureScore": 72 if len(segments) >= 4 else 54,
        "suggestedVariables": [
            {"key": "hook", "label": "Opening hook", "value": "Open with a compelling question in the first 3 seconds."},
            {"key": "subject", "label": "Subject / product", "value": "Use your own product, presenter, or topic."},
            {"key": "cta", "label": "Closing CTA", "value": "End with a clear, actionable next step."},
        ],
        "transcript": "",
    }


def ffmpeg_escape(value: str) -> str:
    value = (value or "").replace("\\", "\\\\").replace("'", r"\'")
    value = value.replace(":", r"\:").replace("%", r"\%")
    value = value.replace("[", r"\[").replace("]", r"\]")
    return value.replace("\n", " ")[:180]


def font_path() -> Optional[str]:
    candidates = [
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    return next((path for path in candidates if Path(path).exists()), None)


def make_text_overlay(path: Path, text: str, font_size: int, y: int) -> bool:
    """Create a transparent PNG overlay without relying on ffmpeg drawtext."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return False
    font_file = font_path()
    try:
        font = ImageFont.truetype(font_file, font_size) if font_file else ImageFont.load_default()
    except OSError:
        font = ImageFont.load_default()
    image = Image.new("RGBA", (720, 1280), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    clean = " ".join((text or "").split())[:180]
    if not clean:
        return False
    # Keep the MVP overlay legible on both Chinese and Latin text.
    lines: list[str] = []
    current = ""
    for char in clean:
        candidate = current + char
        box = draw.textbbox((0, 0), candidate, font=font)
        if box[2] - box[0] > 620 and current:
            lines.append(current)
            current = char
        else:
            current = candidate
    if current:
        lines.append(current)
    lines = lines[:3]
    widths = [draw.textbbox((0, 0), line, font=font)[2] for line in lines]
    line_height = font_size + 9
    total_height = line_height * len(lines)
    box_left = max(24, int((720 - max(widths)) / 2 - 25))
    box_right = min(696, int((720 + max(widths)) / 2 + 25))
    box_top = max(12, y - 14)
    box_bottom = min(1268, box_top + total_height + 28)
    draw.rounded_rectangle((box_left, box_top, box_right, box_bottom), radius=16, fill=(0, 0, 0, 178))
    for index, line in enumerate(lines):
        width = draw.textbbox((0, 0), line, font=font)[2]
        draw.text(((720 - width) / 2, box_top + 12 + index * line_height), line, font=font, fill=(255, 255, 255, 255))
    image.save(path, "PNG")
    return True


def render_variant(job: dict, hook: str, subject: str, cta: str) -> tuple[bool, str, str]:
    source = Path(job["sourcePath"])
    output_name = f"variant-{int(time.time())}.mp4"
    output = OUTPUTS / job["id"] / output_name
    output.parent.mkdir(parents=True, exist_ok=True)
    if not command_exists("ffmpeg"):
        return False, "", "FFmpeg is required to render a video"
    meta = job.get("analysis", {}).get("metadata", {})
    duration = float(meta.get("duration") or 30)
    overlay_dir = output.parent / "overlays"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    overlay_paths = [overlay_dir / "hook.png", overlay_dir / "subject.png", overlay_dir / "cta.png"]
    overlays_ok = all(
        [
            make_text_overlay(overlay_paths[0], hook, 42, 70),
            make_text_overlay(overlay_paths[1], subject, 34, 1010),
            make_text_overlay(overlay_paths[2], cta, 40, 1110),
        ]
    )
    if not overlays_ok:
        return False, "", "Pillow is required to create text overlays; check your installation and text fields"
    base = "[0:v]scale=720:1280:force_original_aspect_ratio=decrease,pad=720:1280:(ow-iw)/2:(oh-ih)/2[base]"
    filter_complex = (
        base
        + f";[base][1:v]overlay=0:0:enable='between(t,0,3)'[v1]"
        + f";[v1][2:v]overlay=0:0:enable='between(t,3,{max(3, duration - 3):.2f})'[v2]"
        + f";[v2][3:v]overlay=0:0:enable='gte(t,{max(0, duration - 3):.2f})',format=yuv420p[v]"
    )
    code, _, stderr = run_command(
        [
            "ffmpeg", "-y", "-i", str(source),
            "-i", str(overlay_paths[0]), "-i", str(overlay_paths[1]), "-i", str(overlay_paths[2]),
            "-filter_complex", filter_complex, "-map", "[v]", "-map", "0:a?",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-c:a", "aac", "-movflags", "+faststart", str(output)
        ],
        timeout=180,
    )
    if code != 0 or not output.exists():
        return False, "", stderr[-900:] or "FFmpeg rendering failed"
    return True, media_url("output", job["id"], output_name), ""


class Handler(BaseHTTPRequestHandler):
    # HTTP header values are Latin-1 encoded by BaseHTTPRequestHandler.
    server_version = "BaokuanMVP/0.1"

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def send_json(self, payload: object, status: int = 200) -> None:
        data = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path in ('/admin/mac-applications', '/api/admin/mac-applications'):
            if not self.allow_local_application_admin():
                self.send_json({'ok': False, 'error': 'Open this page directly on the Mac running Pixfun.'}, 403)
                return
            if path == '/admin/mac-applications':
                self.send_file(PUBLIC / 'mac-applications-admin.html')
            else:
                from mac_applications import list_applications
                try:
                    self.send_json({'ok': True, 'applications': list_applications(DATA / 'mac-applications.sqlite3')})
                except Exception:
                    self.send_json({'ok': False, 'error': 'Applications could not be loaded. Try again.'}, 503)
            return
        if path in ("/mac-early-access", "/mac-early-access/"):
            self.send_file(PUBLIC / "mac-early-access.html")
            return
        if path.rstrip('/') in {"/stories/" + name for name in ("alpine", "citywalk", "food", "outdoors", "islands")}:
            self.send_file(PUBLIC / "footage-case.html")
            return
        if path == "/downloads/pixfun-mac.dmg":
            self.send_mac_installer()
            return
        if path == "/api/health":
            self.send_json(
                {
                    "ok": True,
                    "tools": {
                        "ffmpeg": command_exists("ffmpeg"),
                        "ffprobe": command_exists("ffprobe"),
                        "yt-dlp": command_exists("yt-dlp"),
                        "transcription": TRANSCRIBER_PYTHON.exists() and TRANSCRIBER.exists(),
                    },
                }
            )
            return
        if path.startswith("/media/"):
            parts = path.split("/")
            if len(parts) == 5 and parts[1] == "media":
                kind, job_id, filename = parts[2], parts[3], safe_name(parts[4])
                root = UPLOADS if kind == "upload" else OUTPUTS
                target = (root / job_id / filename).resolve()
                if target.is_file() and target.is_relative_to(root.resolve()):
                    self.send_file(target)
                    return
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if path == "/" or path == "/index.html":
            self.send_file(PUBLIC / "index.html")
            return
        if path.startswith("/assets/"):
            target = (PUBLIC / path.removeprefix("/assets/")).resolve()
            if target.is_file() and target.is_relative_to(PUBLIC.resolve()):
                self.send_file(target)
                return
        self.send_error(HTTPStatus.NOT_FOUND)

    def do_HEAD(self) -> None:
        if unquote(urlparse(self.path).path) == "/downloads/pixfun-mac.dmg":
            self.send_mac_installer(head_only=True)
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def send_mac_installer(self, head_only: bool = False) -> None:
        # Publish only the current packaged release, never a client-supplied path.
        try:
            version = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]
            if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", version):
                raise ValueError("Invalid release version")
            releases = (ROOT / "dist-desktop").resolve()
            filename = f"Pixfun-{version}-arm64.dmg"
            target = (releases / filename).resolve()
            if not target.is_relative_to(releases) or not target.is_file() or not target.stat().st_size:
                raise FileNotFoundError(filename)
        except (OSError, ValueError, KeyError, TypeError):
            self.send_error(HTTPStatus.NOT_FOUND, "Mac installer is unavailable. Please try again later.")
            return
        self.send_file(target, download_name=filename, head_only=head_only)

    def send_file(self, target: Path, download_name: Optional[str] = None, head_only: bool = False) -> None:
        size = target.stat().st_size
        start, end = 0, max(0, size - 1)
        partial = False
        range_header = self.headers.get("Range", "").strip()
        match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header) if range_header else None
        if match and size:
            first, last = match.groups()
            try:
                if first:
                    start = int(first)
                    end = min(int(last), size - 1) if last else size - 1
                elif last:
                    suffix = min(int(last), size)
                    start, end = size - suffix, size - 1
                partial = start <= end and 0 <= start < size
            except ValueError:
                partial = False
            if not partial:
                self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
        length = end - start + 1 if size else 0
        self.send_response(HTTPStatus.PARTIAL_CONTENT if partial else HTTPStatus.OK)
        content_type = "text/vtt; charset=utf-8" if target.suffix.lower() == ".vtt" else mimetypes.guess_type(str(target))[0] or "application/octet-stream"
        self.send_header("Content-Type", "application/x-apple-diskimage" if download_name else content_type)
        if download_name:
            self.send_header("Content-Disposition", f'attachment; filename="{download_name}"')
            self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store" if download_name or target.is_relative_to(PUBLIC.resolve()) else "private, max-age=3600")
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head_only:
            return
        try:
            with target.open("rb") as stream:
                stream.seek(start)
                remaining = length
                while remaining:
                    chunk = stream.read(min(256 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length).decode("utf-8")) if length else {}

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        limits = {"/api/mac-applications": 8192, "/api/import": 501 * 1024 * 1024, "/api/brief": 101 * 1024 * 1024, "/api/vision": 4 * 1024 * 1024}
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_json({"ok": False, "error": "Invalid request size"}, 400)
            return
        if length < 0 or length > limits.get(parsed.path, 128 * 1024):
            self.close_connection = True
            self.send_json({"ok": False, "error": "Request exceeds the upload limit"}, 413)
            return
        if parsed.path == "/api/mac-applications":
            self.handle_mac_application()
        elif parsed.path == "/api/import":
            self.handle_import()
        elif parsed.path == "/api/vision":
            self.handle_vision()
        elif parsed.path == "/api/brief":
            self.handle_brief()
        elif parsed.path == "/api/analyze":
            self.handle_analyze()
        elif parsed.path == "/api/direction":
            self.handle_direction()
        elif parsed.path == "/api/render":
            self.handle_render()
        else:
            self.send_error(HTTPStatus.NOT_FOUND)

    def allow_local_application_admin(self) -> bool:
        # This operator view is intentionally unavailable through public hosts or proxies.
        host = self.headers.get('Host', '')
        port = self.server.server_address[1]
        if self.client_address[0] not in ('127.0.0.1', '::1') or host not in (f'127.0.0.1:{port}', f'localhost:{port}', f'[::1]:{port}'):
            return False
        if any(key.lower().startswith(('forwarded', 'x-forwarded-', 'x-real-ip')) for key in self.headers):
            return False
        origin = self.headers.get('Origin')
        return (not origin or origin in ('http://' + host, 'https://' + host)) and self.headers.get('Sec-Fetch-Site', 'none') in ('none', 'same-origin')

    def handle_mac_application(self) -> None:
        from mac_applications import save_application, validate_application
        origin, host = self.headers.get("Origin"), self.headers.get("Host", "")
        if self.headers.get("Content-Type", "").split(';')[0].strip() != "application/json" or (origin and origin not in ("http://" + host, "https://" + host)) or self.headers.get("Sec-Fetch-Site") == "cross-site":
            self.send_json({"ok": False, "error": "Submit from the Pixfun application page."}, 403)
            return
        try:
            data = self.read_json()
            validate_application(data)
            if data.get('website'):
                raise ValueError('Please try submitting the form again.')
        except (ValueError, TypeError, UnicodeError):
            self.send_json({"ok": False, "error": "Check your email, editing needs, monthly budget and contact consent."}, 400)
            return
        now, address = time.monotonic(), self.client_address[0]
        with APPLICATION_LOCK:
            for key in list(APPLICATION_ATTEMPTS):
                if now - APPLICATION_ATTEMPTS[key][0] >= 600:
                    del APPLICATION_ATTEMPTS[key]
            start, count = APPLICATION_ATTEMPTS.get(address, (now, 0))
            if count >= 5:
                self.send_json({"ok": False, "error": "Too many requests. Please try again in 10 minutes."}, 429)
                return
            APPLICATION_ATTEMPTS[address] = (start, count + 1)
        try:
            with APPLICATION_LOCK:
                save_application(DATA / "mac-applications.sqlite3", data)
        except Exception:
            self.send_json({"ok": False, "error": "We could not save your application. Please try again later."}, 503)
            return
        self.send_json({"ok": True}, 201)

    def handle_vision(self) -> None:
        # Web-only opt-in endpoint. Native service has a separate route allowlist.
        from cloud_vision import VisionError, configuration, video_frames, analyze_frames
        origin = self.headers.get("Origin")
        host = self.headers.get("Host", "")
        if not self.headers.get("Content-Type", "").startswith("application/json") or (origin and origin not in ("http://" + host, "https://" + host)):
            self.send_json({"ok": False, "error": "Use the same-origin web analysis page."}, 403)
            return
        if not configuration()["configured"]:
            self.send_json({"ok": False, "state": "not_configured", "error": "Cloud visual analysis needs a server API key. File details remain available."}, 503)
            return
        if not VISION_LOCK.acquire(blocking=False):
            self.send_json({"ok": False, "state": "error", "error": "Another visual analysis is running. Please retry shortly."}, 429)
            return
        try:
            payload = self.read_json()
            if not isinstance(payload, dict):
                raise ValueError("Invalid request")
            job = None
            if payload.get("jobId"):
                if not re.fullmatch(r"[a-f0-9]{12}", str(payload["jobId"])):
                    raise ValueError("Invalid job")
                job = read_job(payload["jobId"])
                if job["analysis"].get("visualAnalysis", {}).get("state") == "ready":
                    self.send_json({"ok": True, "analysis": job["analysis"]})
                    return
                frames = video_frames(Path(job["sourcePath"]), job["analysis"]["segments"], run_command)
            else:
                image = payload.get("image", "")
                if not isinstance(image, str) or not image.startswith("data:image/jpeg;base64,"):
                    raise ValueError("Invalid photo")
                data = base64.b64decode(image.split(",", 1)[1], validate=True)
                if not data.startswith(b"\xff\xd8\xff") or len(data) > 3 * 1024 * 1024:
                    raise ValueError("Invalid photo")
                frames = [{"id": "photo", "time": 0, "image": image}]
            result = analyze_frames(frames)
            analysis = job["analysis"] if job else {"segments": [], "subtitleCues": []}
            analysis["assetUnderstanding"] = result["assetUnderstanding"]
            analysis["visualAnalysis"] = result["visualAnalysis"]
            for segment in analysis.get("segments", []):
                if segment["id"] in result["sceneUnderstanding"]:
                    segment["assetUnderstanding"] = result["sceneUnderstanding"][segment["id"]]
            if analysis.get("subtitleState") != "embedded":
                cues, rejected = checked_cues(analysis.get("subtitleCues", []))
                if rejected:
                    analysis.update(subtitleCues=cues, transcript=" ".join(c["text"] for c in cues),
                                    subtitleState="partial" if cues else "unreliable", subtitleLanguage=analysis.get("subtitleLanguage") if cues else None,
                                    subtitleMessage="Repetitive speech recognition was excluded. The transcript needs review.")
                    analysis["structureCues"] = make_structure_cues(analysis["segments"], cues, analysis.get("metadata", {}).get("duration", 0))
                    analysis["tracks"] = {"scenes": analysis["segments"], "subtitles": cues, "structure": analysis["structureCues"]}
            if job:
                write_job(job)
            self.send_json({"ok": True, "analysis": analysis})
        except VisionError as exc:
            self.send_json({"ok": False, "state": exc.state, "error": str(exc)}, 503 if exc.state == "not_configured" else 502)
        except FileNotFoundError:
            self.send_json({"ok": False, "state": "missing_source", "error": "The source is no longer on the server. Import this file again."}, 404)
        except (ValueError, TypeError, KeyError):
            self.send_json({"ok": False, "state": "error", "error": "Invalid visual analysis request."}, 400)
        finally:
            VISION_LOCK.release()

    def handle_brief(self) -> None:
        content_type = self.headers.get("Content-Type", "")
        if not content_type.startswith("multipart/form-data"):
            self.send_json({"ok": False, "error": "Expected a multipart creative brief"}, 400)
            return
        form = cgi.FieldStorage(fp=self.rfile, headers=self.headers, environ={
            "REQUEST_METHOD": "POST", "CONTENT_TYPE": content_type,
            "CONTENT_LENGTH": self.headers.get("Content-Length", "0"),
        })
        try:
            job = read_job(form.getfirst("jobId", ""))
            raw = json.loads(form.getfirst("brief", "{}"))
            if not isinstance(raw, dict):
                raise ValueError("Invalid brief")
        except FileNotFoundError:
            self.send_json({"ok": False, "error": "Project not found"}, 404)
            return
        except (ValueError, TypeError):
            self.send_json({"ok": False, "error": "Invalid creative brief"}, 400)
            return
        brief = {key: str(raw.get(key, ""))[:5000] for key in (
            "material", "person", "dialogue", "language", "instructions"
        )}
        entries = form["references"] if "references" in form else []
        if not isinstance(entries, list):
            entries = [entries]
        if len(entries) > 5:
            self.send_json({"ok": False, "error": "A maximum of 5 reference files is allowed"}, 400)
            return
        pending = []
        total = 0
        for entry in entries:
            if not entry.filename:
                continue
            name = safe_name(entry.filename)
            if Path(name).suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp", ".mp4", ".mov", ".webm"}:
                self.send_json({"ok": False, "error": "References must be PNG, JPEG, WebP, MP4, MOV, or WebM"}, 400)
                return
            content = entry.file.read(100 * 1024 * 1024 + 1)
            total += len(content)
            if total > 100 * 1024 * 1024:
                self.send_json({"ok": False, "error": "Reference files must total 100 MB or less"}, 413)
                return
            pending.append((name, content))
        references = list(job.get("references", []))
        if len(references) + len(pending) > 5:
            self.send_json({"ok": False, "error": "This project already has references; a total of 5 is allowed"}, 400)
            return
        folder = UPLOADS / job["id"] / "references"
        folder.mkdir(parents=True, exist_ok=True)
        for name, content in pending:
            stored_name = f"{uuid.uuid4().hex[:8]}-{name}"
            (folder / stored_name).write_bytes(content)
            references.append({"name": name, "storedName": stored_name, "size": len(content)})
        job["creativeBrief"] = brief
        job["references"] = references
        plan = build_creative_plan(brief, bool(references))
        job["creativePlan"] = plan
        job["briefUpdatedAt"] = int(time.time())
        write_job(job)
        self.send_json({"ok": True, "brief": brief, "plan": plan, "references": references, "applied": False})

    def handle_import(self) -> None:
        content_type = self.headers.get("Content-Type", "")
        fields: dict[str, str] = {}
        upload_file: Optional[tuple[str, bytes]] = None
        if content_type.startswith("multipart/form-data"):
            env = {"REQUEST_METHOD": "POST", "CONTENT_TYPE": content_type}
            form = cgi.FieldStorage(fp=self.rfile, headers=self.headers, environ=env)
            for key in ("url", "localPath"):
                if key in form and not isinstance(form[key], list):
                    fields[key] = str(form[key].value or "").strip()
            if "file" in form and not isinstance(form["file"], list) and form["file"].filename:
                upload_file = (safe_name(form["file"].filename), form["file"].file.read())
        else:
            fields = self.read_json()
        job_id = uuid.uuid4().hex[:12]
        source: Optional[Path] = None
        source_name = ""
        source_url = fields.get("url", "")
        if upload_file:
            source_name, contents = upload_file
            folder = UPLOADS / job_id
            folder.mkdir(parents=True, exist_ok=True)
            source = folder / source_name
            source.write_bytes(contents)
        elif fields.get("localPath"):
            candidate = Path(fields["localPath"]).expanduser().resolve()
            if candidate.is_file():
                source = candidate
                source_name = candidate.name
            else:
                self.send_json({"ok": False, "error": "The local video file does not exist"}, 400)
                return
        elif source_url:
            parsed_source = urlparse(source_url)
            if parsed_source.scheme not in {"http", "https"} or not parsed_source.hostname:
                self.send_json({"ok": False, "error": "Use a valid http or https video URL"}, 400)
                return
            if not command_exists("yt-dlp"):
                self.send_json({"ok": False, "error": "Install yt-dlp to import video links, or upload a local video instead"}, 400)
                return
            folder = UPLOADS / job_id
            folder.mkdir(parents=True, exist_ok=True)
            source = folder / "source.mp4"
            code, _, stderr = run_command(["yt-dlp", "--no-playlist", "--merge-output-format", "mp4", "-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b", "-o", str(source), "--", source_url], timeout=300)
            if code != 0 or not source.exists():
                self.send_json({"ok": False, "error": stderr[-1000:] or "Video download failed"}, 400)
                return
            source_name = "source.mp4"
        else:
            self.send_json({"ok": False, "error": "Provide a video link, local path, or uploaded file"}, 400)
            return
        metadata = probe_media(source)
        if not metadata.get("available") or not metadata.get("width") or not metadata.get("duration"):
            self.send_json({"ok": False, "error": "Cannot read this video. Use a valid video file and check that FFmpeg is installed."}, 400)
            return
        analysis = make_analysis(source, source_name, source_url)
        analysis["segments"] = make_timeline_thumbnails(source, job_id, analysis["segments"])
        analysis["subtitleCues"] = extract_subtitle_cues(source, job_id)
        if analysis["subtitleCues"]:
            analysis["subtitleState"] = "embedded"
            analysis["subtitleMessage"] = "Extracted from the video's subtitle track"
        elif analysis["metadata"].get("hasAudio"):
            analysis["subtitleCues"], transcription = transcribe_audio_cues(source, job_id)
            analysis["subtitleState"] = transcription.get("state", "unavailable")
            analysis["subtitleMessage"] = transcription.get("message", "")
            analysis["subtitleLanguage"] = transcription.get("language")
            analysis["transcript"] = transcription.get("text", "")
            if analysis["subtitleCues"]:
                analysis["transcriptState"] = "Extracted from video speech"
        else:
            analysis["subtitleState"] = "silent"
            analysis["subtitleMessage"] = "This video has no audio track"
        analysis["structureCues"] = make_structure_cues(
            analysis["segments"], analysis["subtitleCues"], float(analysis["metadata"].get("duration") or 0)
        )
        analysis["tracks"] = {
            "scenes": analysis["segments"],
            "subtitles": analysis["subtitleCues"],
            "structure": analysis["structureCues"],
        }
        job = {"id": job_id, "createdAt": int(time.time()), "sourcePath": str(source), "analysis": analysis}
        write_job(job)
        relative_media = None
        if source.parent == UPLOADS / job_id:
            relative_media = media_url("upload", job_id, source.name)
        self.send_json({"ok": True, "jobId": job_id, "analysis": analysis, "sourceUrl": relative_media})

    def handle_analyze(self) -> None:
        payload = self.read_json()
        try:
            job = read_job(payload.get("jobId", ""))
        except FileNotFoundError:
            self.send_json({"ok": False, "error": "Project not found"}, 404)
            return
        transcript = str(payload.get("transcript", "")).strip()
        job["analysis"]["transcript"] = transcript
        job["analysis"]["transcriptState"] = "Manual notes saved"
        write_job(job)
        self.send_json({"ok": True, "jobId": job["id"], "analysis": job["analysis"]})

    def handle_direction(self) -> None:
        payload = self.read_json()
        try:
            job = read_job(payload.get("jobId", ""))
        except FileNotFoundError:
            self.send_json({"ok": False, "error": "Project not found"}, 404)
            return
        prompt = " ".join(str(payload.get("prompt") or "").split())[:2000]
        if not prompt:
            self.send_json({"ok": False, "error": "Add a direction for Pixfun"}, 400)
            return
        raw_draft = payload.get("draft") if isinstance(payload.get("draft"), dict) else {}
        draft = {key: " ".join(str(raw_draft.get(key) or "").split())[:100] for key in ("hook", "subject", "cta")}
        messages = list(job.get("directionConversation", []))[-39:]
        messages.append({"role": "user", "text": prompt, "createdAt": int(time.time())})
        job["directionConversation"] = messages
        job["directionDraft"] = draft
        job["directionUpdatedAt"] = int(time.time())
        write_job(job)
        self.send_json({"ok": True, "prompt": prompt, "draft": draft, "messageCount": len(messages)})

    def handle_render(self) -> None:
        payload = self.read_json()
        try:
            job = read_job(payload.get("jobId", ""))
        except FileNotFoundError:
            self.send_json({"ok": False, "error": "Project not found"}, 404)
            return
        hook = str(payload.get("hook", "Your opening hook"))
        subject = str(payload.get("subject", "Your story"))
        cta = str(payload.get("cta", "Start creating"))
        ok, output_url, error = render_variant(job, hook, subject, cta)
        if not ok:
            self.send_json({"ok": False, "error": error}, 400)
            return
        self.send_json({"ok": True, "outputUrl": output_url, "values": {"hook": hook, "subject": subject, "cta": cta}})

def main() -> None:
    host = os.environ.get("BAOKUAN_HOST", "127.0.0.1")
    port = int(os.environ.get("BAOKUAN_PORT", "8765"))
    print(f"Pixfun local studio: http://{host}:{port}")
    print("Use only video content you own or are authorized to use.")
    ThreadingHTTPServer((host, port), Handler).serve_forever()


if __name__ == "__main__":
    main()
