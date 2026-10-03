"""Measure actual audio, cut boundaries, and subpixel photo motion (fixture models)."""
import importlib.util
import json
from pathlib import Path
import threading
import unittest
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('photos', ROOT / 'tests/photo-edit.test.py')
photos = importlib.util.module_from_spec(spec)
spec.loader.exec_module(photos)
import agent_packaging as packaging


class TravelFinishRegression(unittest.TestCase):
    setUp = photos.PhotoEditTests.setUp
    tearDown = photos.PhotoEditTests.tearDown
    start = photos.PhotoEditTests.start
    planner = photos.PhotoEditTests.planner
    photos = photos.PhotoEditTests.photos

    def test_default_photo_film_has_audible_music_and_visible_transitions(self):
        ids = self.photos()
        with self.planner():
            run = photos.base.wait(self.agent, self.start('Create a travel video with a clear story.', mediaIds=ids)['id'], timeout=300)
        self.assertEqual(run['status'], 'completed', run['message'])
        self.assertTrue(run['automaticMusic'])
        self.assertEqual(run['finishing']['transition']['kind'], 'fade')
        self.assertFalse(run['finishing']['narration'])
        preview = next(a['path'] for a in run['artifacts'] if a['type'] == 'preview')
        cancel = threading.Event()
        pcm = self.agent.command(['ffmpeg','-v','error','-i',preview,'-vn','-ac','1','-ar','16000','-f','f32le','-'], cancel)
        audio = np.frombuffer(pcm, dtype='<f4')
        self.assertGreater(float(np.sqrt(np.mean(audio ** 2))), .005)
        def light(t):
            raw = self.agent.command(['ffmpeg','-v','error','-ss',str(t),'-i',preview,'-frames:v','1','-vf','scale=1:1,format=gray','-f','rawvideo','-'], cancel)
            return raw[0]
        self.assertLess(light(3), 15)
        self.assertGreater(light(1), 20)
        probe = json.loads(self.agent.command(['ffprobe','-v','error','-show_format','-of','json',preview],cancel))
        self.assertIn('CC BY', probe['format']['tags']['comment'])
        self.agent.command(['ffmpeg','-v','error','-xerror','-i',preview,'-f','null','-'],cancel)

    def test_photo_motion_is_subpixel_not_integer_crop_jumps(self):
        # A bright marker makes movement objectively measurable frame by frame.
        folder = Path(self.temp.name)
        pixels = np.zeros((180, 320, 3), dtype=np.uint8)
        pixels[70:91, 55:76] = 255
        source = folder / 'motion-marker.ppm'
        source.write_bytes(b'P6\n320 180\n255\n' + pixels.tobytes())
        design = packaging.component({'id':'s','mediaId':'p','start':0,'end':3},0,1,{'kind':'image'},
                                     {'style':'none','text':'none','motion':'gentle'},320,180)
        _, graph = packaging.filters(self.agent, design,320,180,folder,threading.Event(),1)
        raw = self.agent.command(['ffmpeg','-v','error','-loop','1','-framerate','30','-i',source,
            '-filter_complex_threads','1','-filter_complex',graph,'-map','[picture]','-frames:v','90',
            '-pix_fmt','gray','-f','rawvideo','-'],threading.Event())
        frames = np.frombuffer(raw,dtype=np.uint8).reshape(90,180,320).astype(float)
        weights = frames.sum(axis=1)
        centers = (weights * np.arange(320)).sum(axis=1) / weights.sum(axis=1)
        movement = np.diff(centers)
        self.assertGreater(centers[0]-centers[-1], 2)
        self.assertLess(float(np.max(np.abs(movement))), .15, 'no whole-pixel jumps')
        self.assertLess(float(np.max(movement)), .03, 'no backward wobble')
        self.assertLess(float(np.max(np.abs(np.diff(movement)))), .07, 'smooth frame-to-frame velocity')


if __name__ == '__main__': unittest.main()
