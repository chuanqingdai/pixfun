"""Validated JPEG sampling, including the held final frame of VFR recordings."""
import json
from pathlib import Path


def extract_frame(command, source, destination, cancel, seconds=None):
    destination = Path(destination)
    temporary = destination.with_name(destination.stem + '.pending.jpg')
    seek = max(0., float(seconds)) if seconds is not None else None

    def sample(at):
        # Never mistake a file from a failed/previous attempt for a fresh frame.
        temporary.unlink(missing_ok=True)
        args = ['ffmpeg', '-v', 'error', '-y']
        if at is not None:
            args += ['-ss', str(at)]
        command(args + ['-i', source, '-frames:v', '1', '-vf',
                       'scale=768:768:force_original_aspect_ratio=decrease:out_range=pc,format=yuvj420p',
                       '-update', '1', temporary], cancel)
        if not temporary.is_file():
            return False
        data = temporary.read_bytes()
        return len(data) > 4 and data.startswith(b'\xff\xd8') and data.endswith(b'\xff\xd9')

    try:
        if not sample(seek):
            if seek is None:
                raise ValueError('Could not decode an image for local analysis.')
            # Container duration may include a held last frame with no packet at
            # the requested instant. Probe real presentation timestamps; never
            # fabricate a black frame or blindly reuse a stale output image.
            # Seek near the tail first. Very sparse GOPs may require a full scan.
            starts = list(dict.fromkeys((max(0., seek - 10), 0.)))
            found = False
            for start in starts:
                raw = command(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
                               '-read_intervals', f'{start}%{seek + .001}',
                               '-show_entries', 'frame=best_effort_timestamp_time',
                               '-of', 'json', source], cancel)
                times = []
                for frame in json.loads(raw).get('frames', []):
                    try:
                        value = float(frame['best_effort_timestamp_time'])
                    except (KeyError, ValueError, TypeError):
                        continue
                    if 0 <= value <= seek:
                        times.append(value)
                # Slightly precede the frame to avoid decimal/timebase rounding
                # seeking past it, especially on B-frame screen recordings.
                if times and sample(max(0., max(times) - .001)):
                    found = True
                    break
            if not found:
                raise ValueError('Could not read a video frame for local analysis. The source may be incomplete or damaged.')
        temporary.replace(destination)
        return destination
    finally:
        temporary.unlink(missing_ok=True)
