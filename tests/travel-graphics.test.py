"""Contracts use doubles; the opt-in render test uses the actual worker/Chrome."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT),str(ROOT/'scripts')]
from agent_models import ModelGateway
from agent_hyperframes import validate_title
from vf_travel_graphics import render_document
from vf_hyperframes import counter_steps


class Contracts(unittest.TestCase):
    def test_counter_final_value_has_readable_hold(self):
        for duration in (2.5, 3.5, 4.6):
            for total in (1, 3, 99, 9999):
                steps = counter_steps(total, duration)
                self.assertEqual(steps[0]['v'], '0')
                self.assertEqual(steps[-1]['v'], str(total))
                self.assertGreaterEqual(duration-.6-(steps[-1]['t']+.4), .999)
                self.assertTrue(all(b['t']-a['t'] >= .399 for a,b in zip(steps,steps[1:])))

    def test_route_marker_faces_increasing_path_direction(self):
        doc = render_document(dict(kind='route',text='',origin='A',destination='B',duration=4.6))
        self.assertIn('M21 0 L-17 -9 L-12 -2 L-27 0 L-12 2 L-17 9 Z', doc)
        self.assertIn('x=340+1000*p', doc)

    def test_only_supplied_labels_and_offline_scripts(self):
        for item in [dict(kind='route',text='',origin='北京 <script>',destination='上海'),
                     dict(kind='airport',text='上海 </script>')]:
            doc=render_document(dict(validate_title(item),duration=2.5))
            self.assertNotIn('https://',doc)
            self.assertNotIn('NYC',doc)
            self.assertNotIn('NOW BOARDING',doc if item['kind']=='route' else doc.split('var vars =')[1].split(';')[0])
            self.assertNotIn('上海 </script>',doc)

    def test_beauty_api_does_not_change_library_or_film(self):
        spec=importlib.util.spec_from_file_location('base',ROOT/'tests/agent.test.py')
        base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
        case=base.AgentTests();case.setUp()
        try:
            before=case.library.get(case.asset)
            service=case.agent.beauty_sort
            with patch.object(case.agent.models,'capabilities',return_value={'localBeauty':False}):
                with self.assertRaisesRegex(ValueError,'not installed'):service.request({'mediaIds':[case.asset]})
            def scores(images,cancel):return {'scores':[.1,.9,.5][:len(images)]}
            with patch.object(case.agent.models,'capabilities',return_value={'localBeauty':True}),patch.object(case.agent.models,'beauty',side_effect=scores,create=True):
                job=service.request({'mediaIds':[case.asset]})
                for _ in range(100):
                    job=service.request({'jobId':job['id']})
                    if job['status']!='running':break
                    time.sleep(.1)
            self.assertEqual(job['status'],'completed',job)
            self.assertEqual(job['scores'][case.asset],.5)
            self.assertEqual(before,case.library.get(case.asset))
            self.assertEqual(case.agent.list(),[])
        finally:case.doCleanups()


@unittest.skipUnless(os.environ.get('PIXFUN_TEST_HYPERFRAMES')=='1','requires HyperFrames')
class Render(unittest.TestCase):
    def test_travel_overlays(self):
        folder=Path(tempfile.mkdtemp(prefix='travel-graphics-',dir=ROOT/'build-native'))
        gateway=ModelGateway(folder)
        try:
            items=[dict(kind='route',text='',origin='北京',destination='上海'),dict(kind='airport',text='上海 HONGQIAO'),
                   dict(kind='counter',text='旅途纪念',total=9999),dict(kind='end',text='下一段旅程，再见')]
            outputs=[]
            for value in items:
                spec=dict(validate_title(value),duration=2.5,start=0)
                result=gateway.hyperframes([spec],folder,threading.Event())
                output=Path(result['overlays'][0]['path'])
                subprocess.run(['ffmpeg','-v','error','-xerror','-i',str(output),'-f','null','-'],check=True,timeout=60)
                data=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(output)]))
                self.assertAlmostEqual(float(data['streams'][0]['duration']),2.5,delta=.04)
                self.assertIn('a',data['streams'][0]['pix_fmt'])
                frame=folder/(value['kind']+'.png')
                subprocess.run(['ffmpeg','-v','error','-y','-ss','1.9','-i',str(output),'-frames:v','1',str(frame)],check=True)
                outputs.append({'kind':value['kind'],'movie':str(output),'frame':str(frame)})
            (folder/'report.json').write_text(json.dumps(outputs,indent=2))
            print('Real renders:',folder,flush=True)
        finally:gateway.close()

if __name__=='__main__':unittest.main()
