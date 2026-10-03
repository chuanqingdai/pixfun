"""Real bundled-codec rendering in isolated storage; no production projects or model calls."""
import array
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import shutil
import sys
import threading
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
spec=importlib.util.spec_from_file_location('layer_contracts',ROOT/'tests/agent.test.py')
contracts=importlib.util.module_from_spec(spec); spec.loader.exec_module(contracts)
import agent_finishing as finishing


class LayerPolicyTests(unittest.TestCase):
    def test_invalid_captions_and_layer_references(self):
        cue=dict(id='c',text='Hello',start=0,end=1)
        shots=[dict(id='a',start=0,end=2),dict(id='b',start=0,end=2)]
        invalid=[{'captions':[{**cue,'end':5}]},{'captions':[{**cue,'start':float('nan')}]},
                 {'captions':[cue,{**cue,'id':'d','start':.5,'end':2}]},{'captions':[cue,cue]},
                 {'captions':[{**cue,'text':' '}]},{'originalMuted':'yes'},
                 {'clipAudio':[dict(shotId='missing',volume=1,muted=False)]},
                 {'seams':[dict(afterShotId='b',beforeShotId='a',kind='fade',duration=.2)]}]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError): finishing.validate(value,{},4,shots)

    def test_seam_overrides_are_pair_bound_and_duration_is_clamped(self):
        shots=[dict(id='a',start=0,end=.3),dict(id='b',start=0,end=2),dict(id='c',start=0,end=2)]
        value=finishing.validate(dict(transition={'kind':'fade','duration':.5},seams=[dict(afterShotId='b',beforeShotId='c',kind='none',duration=.2)]),{},4.3,shots)
        self.assertIn('d=0.099',finishing.transition_filters(value,0,3,.3,shots))
        self.assertNotIn('out',finishing.transition_filters(value,1,3,2,shots))
        self.assertEqual('',finishing.transition_filters(value,2,3,2,shots))


class LayerRenderTests(unittest.TestCase):
    setUp=contracts.AgentTests.setUp
    tearDown=contracts.AgentTests.tearDown
    start=contracts.AgentTests.start

    def test_insert_new_library_media_is_atomic_and_renders(self):
        self.models.intent='plan'
        run=contracts.wait(self.agent,self.start('Plan only')['id'])
        photo=self.library.register([str(ROOT/'public/media/travel/story/coffee.jpg')])['items'][0]['id']
        deadline=time.monotonic()+30
        while self.library.get(photo)[0]['status']!='ready':
            if time.monotonic()>deadline: self.fail('Photo import timeout')
            time.sleep(.05)
        shots=run['timeline']+[dict(id='inserted',mediaId=photo,start=0,end=3,label='Added photo',reason='',locked=False)]
        payload=dict(id=run['id'],action='timeline',version=run['version'],timeline=shots,finishing={})
        with self.assertRaises(ValueError): self.agent.action(payload)
        for change in (dict(additionalMediaIds=photo),
                       dict(additionalMediaIds=[photo],timeline=run['timeline']),
                       dict(additionalMediaIds=[photo],finishing={'captions':[dict(id='bad',text='Late',start=100,end=103)]})):
            with self.subTest(change=change), self.assertRaises(ValueError): self.agent.action({**payload,**change})
            current=self.agent.get(run['id'])
            self.assertEqual(current['version'],run['version'])
            self.assertEqual(current['mediaIds'],run['mediaIds'])
            self.assertEqual(current['timeline'],run['timeline'])
        saved=self.agent.action({**payload,'additionalMediaIds':[photo]})
        self.assertEqual(saved['mediaIds'],run['mediaIds']+[photo])
        self.assertEqual(saved['timeline'][-1]['mediaId'],photo)
        done=contracts.wait(self.agent,self.agent.action(dict(id=run['id'],action='approve'))['id'],timeout=120)
        self.assertEqual(done['status'],'completed',done['message'])
        preview=next(a['path'] for a in done['artifacts'] if a['type']=='preview')
        self.agent.command(['ffmpeg','-v','error','-xerror','-i',preview,'-f','null','-'],threading.Event())

    def test_manual_layers_render_audio_captions_seam_and_exact_export(self):
        cancel=threading.Event(); tone=Path(self.temp.name)/'tone.wav'; source=Path(self.temp.name)/'tone-video.mp4'
        contracts.write_test_tone(tone)
        self.agent.command(['ffmpeg','-v','error','-y','-i',ROOT/'qa/media-library/captioned-test.mp4','-i',tone,'-t','3','-map','0:v:0','-map','1:a:0','-c:v','copy','-c:a','aac',source],cancel)
        asset=self.library.register([str(source)])['items'][0]['id']
        self.models.intent='plan'
        run=contracts.wait(self.agent,self.start('Plan only',mediaIds=[asset])['id'])
        self.assertEqual(run['status'],'completed',run['message'])
        shots=[dict(id=key,mediaId=asset,start=0,end=3,label=key,reason='Fixture',locked=False) for key in ('a','b')]
        finish={'originalVolume':1,'transition':{'kind':'none','duration':.25}}
        saved=self.agent.action(dict(id=run['id'],action='timeline',version=run['version'],timeline=shots,finishing=finish))
        baseline=contracts.wait(self.agent,self.agent.action(dict(id=run['id'],action='approve'))['id'],timeout=120)
        self.assertEqual(baseline['status'],'completed',baseline['message'])
        base=next(a['path'] for a in baseline['artifacts'] if a['type']=='preview')
        finish.update(captions=[dict(id='en',text='A quiet journey',start=.5,end=1.5),dict(id='zh',text='旅行中的美好时光',start=3.5,end=4.5)],
                      clipAudio=[dict(shotId='a',volume=.5,muted=False),dict(shotId='b',volume=.8,muted=True)],
                      seams=[dict(afterShotId='a',beforeShotId='b',kind='fade',duration=.25)])
        saved=self.agent.action(dict(id=run['id'],action='timeline',version=baseline['version'],timeline=shots,finishing=finish))
        self.assertFalse(any(a['type']=='preview' for a in saved['artifacts']))
        with self.assertRaises(ValueError): self.agent.action(dict(id=run['id'],action='timeline',version=baseline['version'],timeline=shots,finishing=finish))
        done=contracts.wait(self.agent,self.agent.action(dict(id=run['id'],action='approve'))['id'],timeout=120)
        self.assertEqual(done['status'],'completed',done['message'])
        preview=next(a['path'] for a in done['artifacts'] if a['type']=='preview')
        shutil.copyfile(base, ROOT/'build-native/layers-qa-baseline.mp4')
        shutil.copyfile(preview, ROOT/'build-native/layers-qa-captioned.mp4')
        self.agent.command(['ffmpeg','-v','error','-xerror','-i',preview,'-f','null','-'],cancel)
        def rms(path,at):
            data=array.array('f'); data.frombytes(self.agent.command(['ffmpeg','-v','error','-ss',str(at),'-i',path,'-t','0.5','-vn','-ac','1','-ar','16000','-f','f32le','-'],cancel))
            return math.sqrt(sum(x*x for x in data)/len(data))
        self.assertAlmostEqual(rms(preview,.4)/rms(base,.4),.5,delta=.04)
        self.assertLess(rms(preview,3.5),.0001)
        def pixels(path,at):
            return self.agent.command(['ffmpeg','-v','error','-i',path,'-frames:v','1','-vf',f'select=eq(n\\,{round(at*30)}),crop=iw:ih/3:0:ih*2/3,scale=160:40,format=gray','-f','rawvideo','-'],cancel)
        def delta(at): return sum(abs(a-b) for a,b in zip(pixels(base,at),pixels(preview,at)))/6400
        self.assertGreater(delta(.8),3); self.assertGreater(delta(3.8),3)
        self.assertLess(delta(.2),2); self.assertLess(delta(1.7),2); self.assertLess(delta(4.7),2)
        seam=self.agent.command(['ffmpeg','-v','error','-ss','3','-i',preview,'-frames:v','1','-vf','scale=1:1,format=gray','-f','rawvideo','-'],cancel)
        self.assertLess(seam[0],15)
        probe=json.loads(self.agent.command(['ffprobe','-v','error','-show_format','-of','json',preview],cancel))
        self.assertAlmostEqual(float(probe['format']['duration']),6,delta=.15)
        exported=Path(self.temp.name)/'export.mp4'; shutil.copyfile(preview,exported)
        self.assertEqual(hashlib.sha256(Path(preview).read_bytes()).digest(),hashlib.sha256(exported.read_bytes()).digest())
        # Global mute keeps the remembered volume and overrides clip gains.
        finish.update(originalMuted=True,originalVolume=.7,captions=[])
        saved=self.agent.action(dict(id=run['id'],action='timeline',version=done['version'],timeline=shots,finishing=finish))
        muted=contracts.wait(self.agent,self.agent.action(dict(id=run['id'],action='approve'))['id'],timeout=120)
        self.assertEqual(muted['status'],'completed',muted['message'])
        self.assertEqual(muted['finishing']['originalVolume'],.7)
        self.assertLess(rms(next(a['path'] for a in muted['artifacts'] if a['type']=='preview'),.5),.0001)


if __name__=='__main__': unittest.main()
