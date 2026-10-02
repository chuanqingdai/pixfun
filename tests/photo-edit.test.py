"""Real import/decode/render tests; model descriptions and edit choices are fixtures."""
import importlib.util
import json
from pathlib import Path
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('agent_tests', ROOT / 'tests/agent.test.py')
base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
from agent_engine import validate_timeline
from photo_source import apply_default_photo_pacing

class PhotoEditTests(unittest.TestCase):
    setUp = base.AgentTests.setUp
    tearDown = base.AgentTests.tearDown
    start = base.AgentTests.start

    def planner(self):
        original = self.models.ask
        self.models.intent = 'create'
        def ask(prompt, cancel, *args, **kwargs):
            if 'Plan an edit using only' in prompt:
                data = json.loads(prompt.split('INPUT: ')[-1])
                ids = list(dict.fromkeys(c['mediaId'] for c in data['candidates']))
                return {'story':'Fixture picture sequence', 'shots':[
                    {'mediaId':mid,'start':0,'end':3,'label':'Travel view','reason':'Fixture complementary view'} for mid in ids]}
            return original(prompt, cancel, *args, **kwargs)
        return patch.object(self.models, 'ask', side_effect=ask)

    def photos(self):
        return [self.library.register([str(ROOT/'public/media/travel/story'/name)])['items'][0]['id']
                for name in ('coffee.jpg','selfie.jpg','rest.jpg')]

    def verify(self, ids, skill='visionflow-travel-director', aspect='16:9'):
        before = {mid:self.library.get(mid)[1].read_bytes() for mid in ids}
        with self.planner():
            run = base.wait(self.agent, self.start(f'Create a {len(ids)*3}-second travel video {aspect}',
                mediaIds=ids, skill={'id':skill, 'title':'Travel', 'strategy':'Use the installed travel strategy.'})['id'], timeout=90)
        self.assertEqual(run['status'], 'completed', run['message'])
        self.assertEqual({s['mediaId'] for s in run['timeline']}, set(ids))
        self.assertEqual(run['question'], '')
        preview = next(a for a in run['artifacts'] if a['type']=='preview')
        probe = json.loads(self.agent.command(['ffprobe','-v','error','-show_format','-show_streams','-of','json',preview['path']], threading.Event()))
        self.assertAlmostEqual(float(probe['format']['duration']), len(ids)*3, delta=.3)
        video = next(s for s in probe['streams'] if s['codec_type']=='video')
        self.assertEqual((video['width'],video['height']), (720,1280) if aspect=='9:16' else (1280,720))
        self.agent.command(['ffmpeg','-v','error','-i',preview['path'],'-f','null','-'], threading.Event())
        for mid in ids: self.assertEqual(before[mid], self.library.get(mid)[1].read_bytes())
        return run

    def test_three_photos_and_saved_duration_edit(self):
        ids = self.photos()
        run = self.verify(ids)
        for mid in ids:
            metadata = self.library.get(mid)[0]['metadata']
            self.assertIsNone(metadata['duration']); self.assertFalse(metadata['hasAudio'])
        shots = run['timeline']; shots[0]['end'] = 4
        revised = self.agent.action({'id':run['id'],'action':'timeline','version':run['version'],'timeline':shots})
        done = base.wait(self.agent,self.agent.action({'id':run['id'],'action':'approve'})['id'])
        self.assertEqual(done['status'],'completed',done['message'])
        self.assertEqual(sum(s['end']-s['start'] for s in done['timeline']),10)

    def test_mixed_photos_and_video(self): self.verify([self.asset, self.photos()[0]])
    def test_video_only(self): self.verify([self.asset])
    def test_travel_short_photos_portrait(self):
        run = self.verify(self.photos(), 'visionflow-travel-short', '9:16')
        self.assertEqual(run['skillExecution']['id'],'visionflow-travel-short')
        self.assertEqual(run['skillExecution']['coverage']['status'],'NEEDS_REVIEW')
    def test_travel_short_mixed(self): self.verify([self.asset,self.photos()[0]], 'visionflow-travel-short')
    def test_travel_short_video_only(self): self.verify([self.asset], 'visionflow-travel-short')
    def test_old_photo_block_can_resume_without_reimport(self):
        mid = self.photos()[0]
        self.models.intent = 'clarify'
        run = base.wait(self.agent,self.start('Create a video',mediaIds=[mid])['id'])
        run.update(question='Add a video to start editing. Audio can be used as background music; photo slideshows are not supported yet.', clarificationKind='materials')
        self.agent.save(run)
        self.models.intent = 'create'
        resumed = base.wait(self.agent,self.agent.action({'id':run['id'],'action':'retry'})['id'])
        self.assertEqual(resumed['status'],'completed',resumed['message'])
        self.assertEqual(resumed['mediaIds'],[mid])
    def test_heic_decode_and_render(self):
        source = Path(self.temp.name)/'fixture.heic'
        self.agent.command(['/usr/bin/sips','-s','format','heic',ROOT/'public/media/travel/story/coffee.jpg','--out',source], threading.Event())
        mid = self.library.register([str(source)])['items'][0]['id']
        self.verify([mid])
    def test_photo_ranges_are_display_durations(self):
        record = {'id':'p','kind':'image','metadata':{'duration':None}}
        shot = {'mediaId':'p','start':0,'end':4}
        self.assertEqual(validate_timeline([shot],{'p':record})[0]['end'],4)
        normalized = validate_timeline([{**shot,'start':3,'end':6}],{'p':record})[0]
        self.assertEqual((normalized['start'],normalized['end']),(0,3))
        for change in ({'start':-1},{'end':61},{'end':float('nan')}):
            with self.assertRaises(ValueError): validate_timeline([{**shot,**change}],{'p':record})

    def test_default_photo_hold_is_not_the_technical_sixty_second_limit(self):
        records = {'p':{'kind':'image'}, 'v':{'kind':'video'}}
        shots = [{'mediaId':'p','start':0,'end':60}, {'mediaId':'v','start':2,'end':9}]
        paced = apply_default_photo_pacing(shots, records, True)
        self.assertEqual(paced[0]['end'], 5)
        self.assertEqual(paced[1], shots[1])
        self.assertEqual(shots[0]['end'], 60)
        self.assertEqual(apply_default_photo_pacing(shots, records, False), shots)
        empty = [{'mediaId':'p','start':0,'end':0}]
        self.assertEqual(apply_default_photo_pacing(empty, records, True)[0]['end'], 3)
        self.assertEqual(apply_default_photo_pacing(empty, records, False), empty)

    def test_zero_length_photo_observation_is_not_a_zero_length_edit(self):
        ids = self.photos()
        self.models.intent = 'modify'
        original = self.models.ask
        def ask(prompt, *args, **kwargs):
            if 'Plan an edit using only' in prompt:
                data = json.loads(prompt.split('INPUT: ')[-1])
                self.assertTrue(all('end' not in c and c['sourceKind']=='image' for c in data['candidates']))
                return {'story':'Travel photos', 'shots':[{'mediaId':mid,'start':0,'end':0,
                        'label':'Travel photo','reason':'Visible location'} for mid in ids]}
            return original(prompt, *args, **kwargs)
        with patch.object(self.models, 'ask', side_effect=ask):
            run = base.wait(self.agent, self.start('编辑成一个视频', mediaIds=ids)['id'], timeout=90)
        self.assertEqual(run['status'], 'completed', run['message'])
        self.assertEqual([s['end'] for s in run['timeline']], [3,3,3])
        self.assertTrue(any(a['type']=='preview' for a in run['artifacts']))

if __name__ == '__main__': unittest.main()
