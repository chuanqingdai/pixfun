"""Editorial contracts; fixture model outputs are not real-model QA."""
import copy
import importlib.util
import json
from pathlib import Path
import threading
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('agent_tests',ROOT/'tests/agent.test.py')
base=importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
from shot_analysis import validate_shot, stamp, seconds, ShotAnalyses, SHOT_PROMPT, summarize_video

class ShotTests(unittest.TestCase):
    # Use the existing isolated library/model fixture without inheriting its tests.
    setUp=base.AgentTests.setUp
    tearDown=base.AgentTests.tearDown
    def test_audio_without_subtitles_transcribes_and_reuses_speech_cache(self):
        record, _ = self.library.get(self.asset)
        record['metadata']['hasAudio'] = True
        record['result']['analysis']['subtitleCues'] = []
        self.library.patch(self.asset, metadata=record['metadata'], result=record['result'],
                           videoDescription={'status':'running','message':'Another description job'})
        with patch.object(self.models, 'capabilities', return_value={'localSpeech':True}), \
             patch.object(self.models, 'transcribe', return_value={'cues':[{'start':0,'end':1,'text':'The trail starts here.'}]}) as transcribe:
            for attempt in range(2):
                _, result = self.agent.understand({'mode':'local'}, self.asset, threading.Event(), progress=lambda _:None)
                self.assertTrue(result['output']['shots'])
                self.assertEqual(result['speechEvidence']['cues'][0]['text'], 'The trail starts here.')
                # Re-run editorial analysis, retaining only the separate speech cache.
                with self.library.connect() as db:
                    db.execute("DELETE FROM agent_analysis WHERE json_extract(record, '$.output') IS NOT NULL")
            self.assertEqual(transcribe.call_count, 1)
        self.assertEqual(self.library.get(self.asset)[0]['videoDescription']['status'], 'running')

    def test_editorial_pipeline_cache_and_coverage(self):
        service=ShotAnalyses(self.library,self.agent)
        key=self.asset
        item,result=self.agent.understand({'mode':'local'},key,threading.Event(),progress=lambda _:None)
        output=result['output']; self.assertEqual(set(output),{'video_summary','shots'})
        self.assertEqual(seconds(output['shots'][0]['start_time']),0)
        self.assertAlmostEqual(seconds(output['shots'][-1]['end_time']),item['metadata']['duration'],places=2)
        self.assertTrue(all(s['editorial']['edit_recommendation']['reason'] for s in result['segments']))
        calls=len(self.models.calls)
        self.agent.understand({'mode':'local'},key,threading.Event(),progress=lambda _:None)
        self.assertEqual(calls,len(self.models.calls))
        service.start(key,force=True); service.jobs[key][1].result(timeout=20)
        self.assertGreater(len(self.models.calls),calls)
        self.assertEqual(self.library.get(key)[0]['shotAnalysis']['status'],'ready')
    def test_cancel_preserves_previous_shots(self):
        service=ShotAnalyses(self.library,self.agent)
        self.library.patch(self.asset,shotAnalysis={'status':'ready','summary':'previous','segments':[]})
        event=threading.Event(); event.set(); service.generate(self.asset,event)
        state=self.library.get(self.asset)[0]['shotAnalysis']
        self.assertEqual(state['status'],'cancelled'); self.assertEqual(state['summary'],'previous')
    def test_timestamps_and_schema(self):
        self.assertEqual(stamp(3661.234),'01:01:01.234'); self.assertEqual(seconds('01:01:01.234'),3661.234)
        with self.assertRaises(ValueError): seconds('00:60:00.000')
        shot={'shot_id':'shot_001','start_time':stamp(0),'end_time':stamp(3),'description':'人物走上山路，背景为树木。','shot_size':'全景','capture_type':'','camera_motion':'','story_role':['行动'],'dialogue':'虚构对白','reaction':'','audio':['风声'],'importance_score':80,'duplicate_candidate':False,'unusable_candidate':False,'edit_recommendation':{'level':'推荐','recommended_duration_sec':2,'reason':'交代行进过程'}}
        clean=validate_shot(shot,0,3,[]); self.assertEqual(clean['audio'],[]); self.assertEqual(clean['dialogue'],'')
        valid=validate_shot({**shot,'dialogue':'快到了'},0,3,[{'text':'我们快到了'}]); self.assertEqual(valid['dialogue'],'快到了')
        for field,value in [('importance_score',101),('unusable_candidate','false'),('start_time',stamp(1))]:
            bad={**shot,field:value}
            with self.assertRaises(ValueError): validate_shot(bad,0,3,[])
        bad=copy.deepcopy(shot); bad['edit_recommendation']['recommended_duration_sec']=4
        with self.assertRaises(ValueError): validate_shot(bad,0,3,[])
    def test_summary_does_not_sum_people_across_shots(self):
        answers=iter([{'video_summary':'三人组徒步'},{'video_summary':'从驾车出行转到山林徒步。'}])
        self.models.ask=lambda *args,**kwargs: next(answers)
        summary=summarize_video(self.agent,[{'description':'两人在车内。'},{'description':'两人在山林中。'}],threading.Event(),'local')
        self.assertEqual(summary,'从驾车出行转到山林徒步。')

if __name__=='__main__': unittest.main()
