"""Routing/safety contracts plus opt-in actual HTML→MOV→MP4 integration."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import threading
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
import agent_packaging as packaging
from agent_hyperframes import items
from agent_models import ModelGateway


class Contracts(unittest.TestCase):
    def test_explicit_request_and_negatives(self):
        self.assertEqual(packaging.resolve({},None,False,'Add a HyperFrames motion title')['style'],'hyperframes-title')
        for negative in ('no text','不要字幕','no effects','不要动效','去掉动态片名','不加动态片名','remove HyperFrames'):
            result=packaging.resolve({'style':'hyperframes-title','text':'auto'},None,False,'Add HyperFrames, '+negative)
            self.assertEqual(result['text'],'none')

    def test_no_extra_intro_or_unreadable_short_title(self):
        shots=[dict(id='intro',start=0,end=1,label='Opening'),dict(id='body',start=0,end=4,label='Quiet lake')]
        self.assertEqual(items(shots,'Fallback'),[dict(kind='title',start=1,duration=4,text='Quiet lake',shotId='body')])
        self.assertEqual(items(shots[:1],'Fallback'),[])

    def test_no_postcard_or_duplicate_title(self):
        design=packaging.component(dict(id='s',mediaId='m',start=0,end=4,label='Lake'),0,1,
            {'kind':'video'},{'style':'hyperframes-title','motion':'gentle','text':'auto'},720,1280)
        self.assertEqual(design['style'],'none'); self.assertEqual(design['text'],'')
        self.assertEqual(design['viewport'],[0,0,720,1280])


@unittest.skipUnless(os.environ.get('PIXFUN_TEST_HYPERFRAMES')=='1','requires installed HyperFrames / Chrome')
class RealRender(unittest.TestCase):
    def test_actual_render_reuse_and_remove(self):
        spec=importlib.util.spec_from_file_location('photo_tests',ROOT/'tests/photo-edit.test.py')
        photos=importlib.util.module_from_spec(spec);spec.loader.exec_module(photos)
        case=photos.PhotoEditTests(); case.setUp()
        gateway=ModelGateway(case.temp.name)
        try:
            case.models.hyperframes=gateway.hyperframes
            original_caps=case.models.capabilities()
            case.models.capabilities=lambda:{**original_caps,'localHyperframes':True}
            case.models.routerPatch={'packagingRequest':{'style':'hyperframes-title','text':'auto','motion':'gentle'}}
            with case.planner():
                run=photos.base.wait(case.agent,case.start('Create a video. Add a HyperFrames motion title',
                    mediaIds=[case.asset])['id'],timeout=600)
            self.assertEqual(run['status'],'completed',run['message'])
            artifact=next(a for a in run['artifacts'] if a['type']=='motion-project')
            with zipfile.ZipFile(artifact['path']) as z:
                self.assertTrue(any(n.endswith('index.html') for n in z.namelist()))
                self.assertFalse(any(n.endswith('.jpg') for n in z.namelist()))
            preview=next(a for a in run['artifacts'] if a['type']=='preview')['path']
            case.agent.command(['ffmpeg','-v','error','-xerror','-i',preview,'-f','null','-'],threading.Event())
            cache=list((case.agent.root/'hyperframes-cache').glob('*/overlay.mov'))
            self.assertEqual(len(cache),1); stamp=cache[0].stat().st_mtime_ns
            # Re-render same edit uses cached transparent graphics and source segments.
            case.agent.render(run,Path(preview).parent,threading.Event())
            self.assertEqual(cache[0].stat().st_mtime_ns,stamp)
            # Title and its absence must produce different actual output pixels.
            frame=case.agent.command(['ffmpeg','-v','error','-ss','1','-i',preview,'-frames:v','1','-f','md5','-'],threading.Event())
            run=case.agent.get(run['id'])
            finish={**run.get('finishing',{}),'motionTitle':{'kind':'place','text':'湖畔 · Lakeside'}}
            changed=case.agent.action({'id':run['id'],'action':'timeline','version':run['version'],
                                      'timeline':run['timeline'],'finishing':finish})
            self.assertEqual(changed['finishing']['motionTitle'],finish['motionTitle'])
            self.assertEqual(changed['timeline'],run['timeline'])
            case.agent.cancels[run['id']]=threading.Event()
            case.agent.render(changed,Path(preview).parent,threading.Event())
            run=case.agent.get(run['id'])
            self.assertEqual(run['finishing']['motionTitle']['kind'],'place')
            archive=next(a['path'] for a in run['artifacts'] if a['type']=='motion-project')
            with zipfile.ZipFile(archive) as z:
                self.assertEqual(json.loads(z.read('manifest.json'))['items'][0]['kind'],'place')
            run['finishing']['motionTitle']={'kind':'none','text':''}
            run['version']+=1;case.agent.save(run)
            case.agent.render(run,Path(preview).parent,threading.Event())
            removed=case.agent.get(run['id']); bare=next(a for a in removed['artifacts'] if a['type']=='preview')['path']
            self.assertNotEqual(frame,case.agent.command(['ffmpeg','-v','error','-ss','1','-i',bare,'-frames:v','1','-f','md5','-'],threading.Event()))
            self.assertFalse(any(a['type']=='motion-project' for a in removed['artifacts']))
            print('PASS actual title render, source preservation, cached rerender, remove title, project export')
        finally:
            gateway.close();case.doCleanups()


if __name__=='__main__': unittest.main()
