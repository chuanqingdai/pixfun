#!/usr/bin/env python3
"""Local MVP for turning a reference short video into editable variants.

No third-party Python packages are required. Optional local tools:
  - ffmpeg / ffprobe for media inspection and rendering
  - yt-dlp for URL ingestion
"""

from __future__ import annotations

import cgi
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parent
PUBLIC = ROOT / "public"
DATA = ROOT / "data"
UPLOADS = DATA / "uploads"
JOBS = DATA / "jobs"
OUTPUTS = DATA / "outputs"
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
        return {"available": False, "message": "未找到 ffprobe，无法读取视频元数据"}
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
        return {"available": False, "message": stderr[-500:] or "ffprobe 读取失败"}
    try:
        data = json.loads(stdout)
    except json.JSONDecodeError:
        return {"available": False, "message": "ffprobe 返回了无法解析的数据"}
    streams = data.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), {})
    audio = next((s for s in streams if s.get("codec_type") == "audio"), {})
    fmt = data.get("format", {})
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
        "duration": round(duration, 2),
        "durationLabel": format_duration(duration),
        "width": width,
        "height": height,
        "fps": fps,
        "hasAudio": bool(audio),
        "videoCodec": video.get("codec_name", "unknown"),
        "audioCodec": audio.get("codec_name", "unknown") if audio else None,
        "size": int(fmt.get("size") or source.stat().st_size),
        "format": fmt.get("format_name", "unknown"),
        "orientation": "竖屏" if height >= width else "横屏",
    }


def format_duration(seconds: float) -> str:
    total = max(0, int(round(seconds)))
    minutes, sec = divmod(total, 60)
    return f"{minutes}:{sec:02d}" if minutes else f"0:{sec:02d}"


def detect_cuts(source: Path, duration: float) -> list[float]:
    if not command_exists("ffmpeg"):
        return []
    # showinfo emits pts_time for frames selected by the scene detector.
    filter_expr = r"select=gt(scene\,0.35),showinfo"
    code, _, stderr = run_command(
        [
            "ffmpeg",
            "-hide_banner",
            "-i",
            str(source),
            "-vf",
            filter_expr,
            "-an",
            "-f",
            "null",
            "-",
        ],
        timeout=90,
    )
    if code not in (0, 1):
        return []
    cuts = []
    for match in re.finditer(r"pts_time:([0-9.]+)", stderr):
        value = float(match.group(1))
        if 0.4 < value < max(0.5, duration - 0.3):
            if not cuts or value - cuts[-1] > 0.7:
                cuts.append(round(value, 2))
    return cuts[:24]


def make_segments(duration: float, cuts: list[float]) -> list[dict]:
    if duration <= 0:
        duration = 30
    points = [0.0] + cuts + [duration]
    raw = []
    for start, end in zip(points, points[1:]):
        if end - start >= 0.65:
            raw.append((start, end))
    # The semantic labels are intentionally editable heuristics in the MVP.
    labels = ["Hook 开场", "问题/冲突", "证明/展示", "转折/反应", "CTA 收束"]
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
                "percent": round((end - start) / duration * 100, 1),
                "note": "可在下一步替换为更准确的台词或画面说明",
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
                "percent": 20,
                "note": "基于时长的初始切分，建议人工校准",
            }
            for i in range(5)
        ]
    return result


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
        "formatGuess": "口播/UGC 短视频" if aspect == "9:16" else "横屏内容/讲解视频",
        "hookScore": 78 if duration <= 45 else 61,
        "structureScore": 72 if len(segments) >= 4 else 54,
        "suggestedVariables": [
            {"key": "hook", "label": "开场 Hook", "value": "3 秒内提出一个强冲突问题"},
            {"key": "subject", "label": "主体/产品", "value": "替换为你的产品、人物或主题"},
            {"key": "cta", "label": "结尾 CTA", "value": "保留一个明确、可执行的下一步"},
        ],
        "transcript": "尚未连接本地语音模型。你可以先在下方输入台词，后续接入 WhisperX 自动对齐。",
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


def split_video(job: dict) -> tuple[bool, list[dict], str]:
    """Render the detected timeline segments as independently playable MP4 files."""
    if not command_exists("ffmpeg"):
        return False, [], "FFmpeg is required to create video clips"
    source = Path(job["sourcePath"])
    segments = job.get("analysis", {}).get("segments", [])
    if not segments:
        return False, [], "No timeline segments are available for this video"
    output_dir = OUTPUTS / job["id"]
    output_dir.mkdir(parents=True, exist_ok=True)
    clips = []
    for index, segment in enumerate(segments[:24]):
        start = max(0.0, float(segment.get("start") or 0))
        duration = max(0.05, float(segment.get("duration") or 0))
        filename = f"clip-{index + 1:02d}.mp4"
        output = output_dir / filename
        if not output.exists() or output.stat().st_size < 1024:
            code, _, stderr = run_command(
                [
                    "ffmpeg", "-y", "-ss", f"{start:.3f}", "-i", str(source),
                    "-t", f"{duration:.3f}", "-map", "0:v:0", "-map", "0:a?",
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
                    "-c:a", "aac", "-movflags", "+faststart", "-avoid_negative_ts", "make_zero",
                    str(output),
                ],
                timeout=180,
            )
            if code != 0 or not output.exists():
                return False, clips, stderr[-900:] or f"Could not create clip {index + 1}"
        clips.append(
            {
                "id": segment.get("id") or f"seg-{index + 1}",
                "label": f"Scene {index + 1:02d}",
                "start": round(start, 2),
                "end": round(start + duration, 2),
                "duration": round(duration, 2),
                "filename": filename,
                "url": media_url("output", job["id"], filename),
            }
        )
    job["clips"] = clips
    job["clipsUpdatedAt"] = int(time.time())
    write_job(job)
    return True, clips, ""


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
        if path == "/api/health":
            self.send_json(
                {
                    "ok": True,
                    "tools": {
                        "ffmpeg": command_exists("ffmpeg"),
                        "ffprobe": command_exists("ffprobe"),
                        "yt-dlp": command_exists("yt-dlp"),
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

    def send_file(self, target: Path) -> None:
        content = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mimetypes.guess_type(str(target))[0] or "application/octet-stream")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length).decode("utf-8")) if length else {}

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        limits = {"/api/import": 501 * 1024 * 1024, "/api/brief": 101 * 1024 * 1024}
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_json({"ok": False, "error": "Invalid request size"}, 400)
            return
        if length < 0 or length > limits.get(parsed.path, 128 * 1024):
            self.close_connection = True
            self.send_json({"ok": False, "error": "Request exceeds the upload limit"}, 413)
            return
        if parsed.path == "/api/import":
            self.handle_import()
        elif parsed.path == "/api/brief":
            self.handle_brief()
        elif parsed.path == "/api/analyze":
            self.handle_analyze()
        elif parsed.path == "/api/render":
            self.handle_render()
        elif parsed.path == "/api/split":
            self.handle_split()
        else:
            self.send_error(HTTPStatus.NOT_FOUND)

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
        job["briefUpdatedAt"] = int(time.time())
        write_job(job)
        self.send_json({"ok": True, "brief": brief, "references": references, "applied": False})

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

    def handle_split(self) -> None:
        payload = self.read_json()
        try:
            job = read_job(payload.get("jobId", ""))
        except FileNotFoundError:
            self.send_json({"ok": False, "error": "Project not found"}, 404)
            return
        ok, clips, error = split_video(job)
        if not ok:
            self.send_json({"ok": False, "error": error}, 400)
            return
        self.send_json({"ok": True, "jobId": job["id"], "clips": clips, "count": len(clips)})


def main() -> None:
    host = os.environ.get("BAOKUAN_HOST", "127.0.0.1")
    port = int(os.environ.get("BAOKUAN_PORT", "8765"))
    print(f"Pixfun local studio: http://{host}:{port}")
    print("Use only video content you own or are authorized to use.")
    ThreadingHTTPServer((host, port), Handler).serve_forever()


if __name__ == "__main__":
    main()
