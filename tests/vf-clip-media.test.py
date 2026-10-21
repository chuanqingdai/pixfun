"""Actual FFmpeg nonzero-start/audio/colour regression, using synthetic media only."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app
from vf_bridge import Catalog, prepare_clip


class ClipMediaTests(unittest.TestCase):
    def test_nonzero_start_decodes_the_selected_colour_and_keeps_audio(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); source = root / 'video' / 'shot'; source.parent.mkdir()
            # 0–2s red, 2–4s blue, 4–6s green. Clip selects only 2.04–3.96s.
            subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-threads', '2',
                            '-filter_threads', '2', '-f', 'lavfi', '-i', 'color=red:s=160x90:r=25:d=6',
                            '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:duration=6',
                            '-vf', "drawbox=color=blue:t=fill:enable='between(t,2,3.999)',drawbox=color=green:t=fill:enable='gte(t,4)'",
                            '-c:v', 'libx264', '-threads', '2', '-c:a', 'aac', '-f', 'mp4', str(source)], check=True)
            value = dict(id='shot', asset='synthetic.mp4', start=2.04, end=3.96, online=True,
                         playback=dict(start=2.04, end=3.96, origin=0), representative=None,
                         context={}, scores={}, tags=[], transcript_segments=[])
            catalog = Catalog('unused'); catalog.base = lambda: str(root) + '/'
            catalog.shot = Mock(return_value=value); catalog.open = lambda *a, **kw: io.BytesIO(b'x')
            with patch.object(app, 'UPLOADS', root / 'uploads'), patch.object(app, 'JOBS', root / 'jobs'):
                app.JOBS.mkdir()
                result = prepare_clip(catalog, app, 'shot')
                path = Path(app.read_job(result['jobId'])['sourcePath'])
                frames = subprocess.check_output(['ffmpeg', '-v', 'error', '-threads', '2', '-filter_threads', '2',
                                                  '-i', str(path), '-vf', 'scale=1:1', '-pix_fmt', 'rgb24',
                                                  '-f', 'rawvideo', '-threads', '2', '-'])
                self.assertEqual(len(frames) // 3, 48)
                self.assertTrue(all(frames[i+2] > 200 and frames[i] < 40 and frames[i+1] < 40
                                    for i in range(0, len(frames), 3)), 'Clip contains frames from another colour/shot')
                media = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', str(path)]))
                video = next(s for s in media['streams'] if s['codec_type'] == 'video')
                audio = next(s for s in media['streams'] if s['codec_type'] == 'audio')
                self.assertEqual(float(video['start_time']), 0.)
                self.assertEqual(float(audio['start_time']), 0.)
                self.assertAlmostEqual(float(video['duration']), 1.92, places=2)
                self.assertLess(abs(float(video['duration']) - float(audio['duration'])), .04)
                self.assertEqual((video['width'], video['height']), (160, 90))


if __name__ == '__main__': unittest.main()
