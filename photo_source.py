"""Decode stills into a cached PNG without modifying the original photograph."""
import hashlib
import math
import os
from pathlib import Path
import uuid

PHOTO_HOLD_LIMIT = 60.0
DEFAULT_PHOTO_HOLD = 5.0

def fit_photo_duration(shots, records, target):
    """Honor explicit total duration for a new still-only film, at frame precision.

    Preserve the proposed relative pacing and shot order. Never lengthen video
    ranges, duplicate photos, or use this for manual/scoped timeline edits.
    """
    if target is None or not shots or any(records[s['mediaId']]['kind']!='image' for s in shots): return shots
    total_frames=round(float(target)*30)
    current=sum(s['end']-s['start'] for s in shots)
    if abs(current-target)<1/30: return shots
    result=[]; assigned=0; cumulative=0.0
    for index,shot in enumerate(shots):
        cumulative+=shot['end']-shot['start']
        endpoint=total_frames if index==len(shots)-1 else round(total_frames*cumulative/current)
        frames=endpoint-assigned; assigned=endpoint
        if not 8<=frames<=PHOTO_HOLD_LIMIT*30: raise ValueError('The requested photo-film duration needs different shot pacing.')
        result.append({**shot,'start':0.0,'end':round(frames/30,3)})
    return result

def apply_default_photo_pacing(shots, records, content_led):
    """A technical safety ceiling is not a sensible default edit duration."""
    if not content_led or not isinstance(shots, list):
        return shots
    result = []
    for shot in shots:
        if isinstance(shot, dict) and records.get(shot.get('mediaId'), {}).get('kind') == 'image':
            start, end = shot.get('start'), shot.get('end')
            if all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) for v in (start, end)) and 0 <= start <= end:
                # Models sometimes copy a photo's zero-length observation window.
                # It has no source duration; an unspecified still uses a 3s hold.
                hold = 3.0 if end == start else min(end-start, DEFAULT_PHOTO_HOLD)
                shot = {**shot, 'start':0.0, 'end':hold}
        result.append(shot)
    return result

def prepare_photo(source, directory, command):
    source = Path(source)
    stat = source.stat()
    signature = hashlib.sha256(f'{source}:{stat.st_size}:{stat.st_mtime_ns}:photo-v1'.encode()).hexdigest()
    directory = Path(directory) / ('photo-' + signature[:24])
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / 'still.png'
    if target.is_file() and target.stat().st_size:
        return target
    temporary = directory / (uuid.uuid4().hex + '.png')
    try:
        if source.suffix.lower() in ('.heic', '.heif') and Path('/usr/bin/sips').is_file():
            command(['/usr/bin/sips', '-s', 'format', 'png', str(source), '--out', str(temporary)])
        else:
            command(['ffmpeg', '-v', 'error', '-y', '-i', str(source), '-frames:v', '1', str(temporary)])
        if not temporary.is_file() or not temporary.stat().st_size:
            raise ValueError('Could not decode this photo. Try a JPEG or PNG copy.')
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return target

def prepare_render_photo(source, directory, width, height, command):
    """Decode/resize once, not a multi-megapixel PNG for every output frame."""
    normalized = prepare_photo(source, directory, command)
    target = normalized.parent / f'render-{width}x{height}.png'
    if target.is_file() and target.stat().st_size: return target
    temporary = target.parent / (uuid.uuid4().hex + '.png')
    try:
        command(['ffmpeg','-v','error','-y','-i',normalized,'-frames:v','1',
                 '-vf',f'scale={width}:{height}:force_original_aspect_ratio=decrease',temporary])
        if not temporary.is_file() or not temporary.stat().st_size: raise ValueError('Photo render proxy is empty.')
        os.replace(temporary,target)
    finally:
        temporary.unlink(missing_ok=True)
    return target
