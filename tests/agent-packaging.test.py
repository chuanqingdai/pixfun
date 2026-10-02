"""Real bundled render tests, with explicitly fixture model descriptions."""
import importlib.util
import json
from pathlib import Path
import threading
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('photo_tests',ROOT/'tests/photo-edit.test.py')
photos=importlib.util.module_from_spec(spec); spec.loader.exec_module(photos)
import agent_packaging as packaging
from photo_source import fit_photo_duration
from agent_engine import starter_brief

class PackagingTests(unittest.TestCase):
    def setUp(self):
        if self._testMethodName not in ('test_negatives_and_default_styles','test_layouts_are_safe_and_end_cleanly'):
            photos.PhotoEditTests.setUp(self)
    tearDown=photos.PhotoEditTests.tearDown
    start=photos.PhotoEditTests.start
    planner=photos.PhotoEditTests.planner
    verify=photos.PhotoEditTests.verify
    photos=photos.PhotoEditTests.photos

    def test_negatives_and_default_styles(self):
        for prompt in ('no effects', '不要动效', 'without animation'):
            self.assertEqual(packaging.resolve({},None,True,prompt),{'style':'none','text':'none','motion':'none'})
        self.assertEqual(packaging.resolve({},None,True,'no text')['text'],'none')
        self.assertEqual(packaging.resolve({},None,False)['text'],'none')
        old={'style':'city-notes','text':'none','motion':'none'}
        self.assertEqual(packaging.resolve({},old,True),old)
        shots=[{'mediaId':str(i),'start':0,'end':3} for i in range(3)]
        records={str(i):{'kind':'image'} for i in range(3)}
        self.assertEqual([s['end'] for s in fit_photo_duration(shots,records,12)],[4,4,4])
        self.assertEqual(shots[0]['end'],3)
        records['0']['kind']='video'
        self.assertEqual(fit_photo_duration(shots,records,12),shots)
        for prompt, intent in [('Summarize my media and suggest what to use.', 'analyze'),
                               ('Create a travel video with a clear story.', 'create'),
                               ('Make a short travel highlight reel from the best moments.', 'create')]:
            for short in (False, True):
                brief = starter_brief({'prompt': prompt}, short)
                self.assertEqual(brief['intent'], intent)
                self.assertNotIn('finishingRequest', brief)
                self.assertNotIn('packagingRequest', brief)
        run={'prompt':'Create a travel video with a clear story.'}
        self.assertEqual(starter_brief(run)['intent'],'create')
        self.assertIsNone(starter_brief({**run,'prompt':run['prompt']+' Clone a voice.'}))
        self.assertIsNone(starter_brief({**run,'context':[{'prompt':'Earlier direction'}]}))
        self.assertIsNone(starter_brief({**run,'previousTimeline':[{'id':'old'}]}))

    def test_layouts_are_safe_and_end_cleanly(self):
        for width,height in ((1280,720),(720,1280),(720,720)):
            for index in range(3):
                d=packaging.component({'id':'s','mediaId':'p','start':0,'end':5,'label':'By the water'},index,3,
                    {'kind':'image'},packaging.resolve({},None,True),width,height)
                x,y,w,h=d['viewport']
                self.assertTrue(x>=0 and y>=0 and x+w<=width and y+h<=height)
                self.assertEqual((w%2,h%2),(0,0))
                self.assertEqual(bool(d['text']),index<2)
                self.assertIsNone(d['sourceRange'])
                self.assertLess(.96*1.025,1)  # all source edges stay inside the motion viewport

    def test_city_notes_real_render_and_revision_cache(self):
        self.models.routerPatch={'packagingRequest':{'style':'city-notes','text':'auto','motion':'gentle'}}
        ids=self.photos()
        run=self.verify(ids,'visionflow-travel-short','9:16')
        manifest=json.loads((self.agent.root/run['id']/'packaging-v1.json').read_text())
        self.assertEqual(manifest['settings']['style'],'city-notes')
        preview=next(a['path'] for a in run['artifacts'] if a['type']=='preview')
        def frame(t):
            return self.agent.command(['ffmpeg','-v','error','-ss',str(t),'-i',preview,'-frames:v','1','-f','rawvideo','-pix_fmt','rgb24','-'],threading.Event())
        self.assertNotEqual(frame(.1),frame(1.5),'Title/photo animation must change actual output frames')
        shots=run['timeline']; shots[0]['end']=3.5
        self.agent.action({'id':run['id'],'action':'timeline','version':run['version'],'timeline':shots})
        done=photos.base.wait(self.agent,self.agent.action({'id':run['id'],'action':'approve'})['id'],timeout=300)
        self.assertEqual(done['status'],'completed',done['message'])
        self.assertEqual(done['renderStats']['reusedShots'],2)
        self.assertEqual(done['packaging'],run['packaging'])

    def test_short_single_shot_needs_one_vision_call_and_no_summary(self):
        # Use an actual five-second continuous source, not the existing longer
        # caption/subtitle fixture, which correctly takes the full pipeline.
        clip=Path(self.temp.name)/'continuous.mp4'
        self.agent.command(['ffmpeg','-v','error','-y','-i',ROOT/'public/media/travel/story/rest.mp4',
                            '-t','5','-an','-c:v','mpeg4','-q:v','3',clip],threading.Event())
        mid=self.library.register([str(clip)])['items'][0]['id']
        _,result=self.agent.understand({'mode':'local'},mid,threading.Event(),progress=lambda _:None)
        self.assertTrue(result['output']['shots'])
        self.assertEqual(len(self.models.calls),1)
        self.agent.understand({'mode':'local'},mid,threading.Event(),progress=lambda _:None)
        self.assertEqual(len(self.models.calls),1)

    def test_photo_checkpoint_reuses_inference_after_interruption(self):
        mid=self.photos()[0]; event=threading.Event()
        self.agent.observe({'mode':'local'},mid,event,progress=lambda _:None)
        calls=len(self.models.calls)
        with self.library.connect() as db: db.execute('DELETE FROM agent_analysis')
        self.agent.observe({'mode':'local'},mid,event,progress=lambda _:None)
        self.assertEqual(len(self.models.calls),calls)

if __name__=='__main__': unittest.main()
