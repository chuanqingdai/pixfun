"""Decode stills into a cached PNG without modifying the original photograph."""
import hashlib
import math
import os
from pathlib import Path
import uuid

PHOTO_HOLD_LIMIT = 60.0
DEFAULT_PHOTO_HOLD = 5.0

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
