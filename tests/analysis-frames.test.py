"""Real bundled-codec regressions plus explicit failure/cancellation contracts."""
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from analysis_frames import extract_frame
from agent_engine import AgentEngine
from agent_models import AgentCancelled


class AnalysisFrameTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pixfun-frame-test-')
        self.folder = Path(self.temp.name)
        self.cancel = threading.Event()
        self.calls = []

    def tearDown(self):
        self.temp.cleanup()

    def command(self, args, cancel):
        self.calls.append(args)
        args = [ROOT / 'dist-native/Pixfun.app/Contents/Resources/bin' / args[0], *args[1:]]
        return AgentEngine.command(None, args, cancel)

    def verify(self, source, seconds):
        target = self.folder / 'frame.jpg'
        extract_frame(self.command, source, target, self.cancel, seconds)
        self.command(['ffmpeg', '-v', 'error', '-xerror', '-i', target, '-f', 'null', '-'], self.cancel)
        self.assertGreater(target.stat().st_size, 100)
        self.assertFalse(target.with_name('frame.pending.jpg').exists())

    def test_held_final_frame_uses_real_timestamp(self):
        source = self.folder / 'held.mp4'
        # Last presentation timestamp is 0.5s; container duration is 1s.
        self.command(['ffmpeg', '-v', 'error', '-y', '-loop', '1', '-framerate', '2',
                      '-i', ROOT / 'public/media/travel/story/coffee.jpg', '-t', '1',
                      '-vf', 'scale=320:-2', '-c:v', 'mpeg4', source], self.cancel)
        self.verify(source, .85)
        self.assertTrue(any(c[0] == 'ffprobe' for c in self.calls))

    def test_regular_video_and_still(self):
        self.verify(ROOT / 'public/media/travel/story/rest.mp4', 1.)
        self.verify(ROOT / 'public/media/travel/story/coffee.jpg', None)
        self.assertFalse(any(c[0] == 'ffprobe' for c in self.calls))

    @unittest.skipUnless(os.environ.get('PIXFUN_FRAME_REGRESSION_SOURCE'), 'Original recording is opt-in')
    def test_original_screen_recording_all_sample_windows(self):
        source = Path(os.environ['PIXFUN_FRAME_REGRESSION_SOURCE'])
        for start in range(0, 31, 6):
            for fraction in (.15, .5, .85):
                with self.subTest(start=start, fraction=fraction):
                    self.verify(source, start + (min(start + 6, 30.89) - start) * fraction)
        self.assertTrue(any(c[0] == 'ffprobe' for c in self.calls))

    def test_empty_success_does_not_reuse_stale_destination(self):
        target = self.folder / 'frame.jpg'
        target.write_bytes(b'old destination')
        target.with_name('frame.pending.jpg').write_bytes(b'old partial')
        def empty(args, cancel):
            return b'{"frames":[]}' if args[0] == 'ffprobe' else b''
        with self.assertRaisesRegex(ValueError, 'Could not read a video frame'):
            extract_frame(empty, 'source.mov', target, self.cancel, 30.)
        self.assertEqual(target.read_bytes(), b'old destination')
        self.assertFalse(target.with_name('frame.pending.jpg').exists())

    def test_cancellation_and_decoder_error_are_not_retried(self):
        for error in (AgentCancelled(), ValueError('decoder error')):
            calls = []
            def fail(args, cancel):
                calls.append(args)
                raise error
            with self.assertRaises(type(error)):
                extract_frame(fail, 'source.mov', self.folder / 'frame.jpg', self.cancel, 30.)
            self.assertEqual(len(calls), 1)


if __name__ == '__main__':
    unittest.main()
