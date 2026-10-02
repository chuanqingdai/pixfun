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
from shot_analysis import validate_shot, normalize_shot_response, single_shot_prompt, stamp, seconds, ShotAnalyses, SHOT_PROMPT, summarize_video

def shot_fixture():
    return {'shot_id':'shot_001','start_time':stamp(0),'end_time':stamp(2.92),
            'description':'A traveler walks across a wooden bridge.', 'shot_size':'Medium shot',
            'capture_type':'Tracking','camera_motion':'Following','story_role':['Action'],
            'dialogue':'','reaction':'','audio':[],'importance_score':78,
            'duplicate_candidate':False,'unusable_candidate':False,
            'edit_recommendation':{'level':'Recommended','recommended_duration_sec':3,'reason':'Keep the complete crossing.'}}

class ShotResponseTests(unittest.TestCase):
    def test_equivalent_single_shot_shapes_and_rounding(self):
        shot=shot_fixture()
        shapes=[shot, {'shots':[shot]}, {'video_summary':'Crossing','shots':[shot]},
                {'shot':shot}, {'EDITORIAL_SHOT':{'shots':[shot]}}, {'result':{'shot':shot}},
                {**shot,'video_summary':'Crossing'}, {'shots':[shot],'confidence':.9}]
        for value in shapes:
            with self.subTest(keys=list(value)):
                clean=normalize_shot_response(value,0,2.92,[])
                self.assertEqual(clean['description'],shot['description'])
                self.assertEqual(clean['edit_recommendation']['recommended_duration_sec'],2.92)
        self.assertEqual(shot['edit_recommendation']['recommended_duration_sec'],3,'Do not mutate raw model evidence')

    def test_multiple_or_missing_shots_are_not_silently_discarded(self):
        shot=shot_fixture()
        for value in ({'shots':[shot,shot]},{'shots':[]},{'shot':shot,'shots':[shot]},
                      {'video_summary':'No shot'},{'shots':'invalid'},[],None):
            with self.subTest(value=type(value)):
                with self.assertRaises(ValueError): normalize_shot_response(value,0,2.92,[])

    def test_real_ranges_and_material_overages_stay_strict(self):
        for key,value in [('start_time',stamp(.1)),('end_time',stamp(3)),('importance_score',False),('description','')]:
            with self.assertRaises(ValueError): normalize_shot_response({**shot_fixture(),key:value},0,2.92,[])
        for duration in (4, True, '3', float('nan'), -1):
            shot=shot_fixture(); shot['edit_recommendation']['recommended_duration_sec']=duration
            with self.assertRaises(ValueError): normalize_shot_response(shot,0,2.92,[])

    def test_prompt_uses_one_actual_interval_not_example_duration(self):
        prompt=single_shot_prompt(6,8.92)
        self.assertNotIn('Split on significant changes',prompt)
        self.assertIn('SAME shot',prompt)
        self.assertIn('"start_time":"00:00:06.000"',prompt)
        self.assertIn('"end_time":"00:00:08.920"',prompt)
        self.assertIn('"recommended_duration_sec":2.92',prompt)
        self.assertNotIn('00:00:08.200',prompt)

class ShotTests(unittest.TestCase):
    # Use the existing isolated library/model fixture without inheriting its tests.
    setUp=base.AgentTests.setUp
    tearDown=base.AgentTests.tearDown
    def test_direct_shot_output_completes_without_model_retry(self):
        original=self.models.ask
        responses=[]
        def flat(prompt,*args,**kwargs):
            result=original(prompt,*args,**kwargs)
            if 'EDITORIAL_SHOT' in prompt:
                responses.append(prompt)
                return result['shots'][0]
            return result
        self.models.ask=flat
        _,result=self.agent.understand({'mode':'local'},self.asset,threading.Event(),progress=lambda _:None)
        self.assertEqual(len(responses),len(result['output']['shots']))

    def test_multiple_shots_receive_bounded_correction_not_first_shot_selection(self):
        original=self.models.ask; responses=[]
        def malformed(prompt,*args,**kwargs):
            result=original(prompt,*args,**kwargs)
            if 'EDITORIAL_SHOT' in prompt:
                responses.append(prompt)
                if len(responses)==1: return {'shots':[result['shots'][0],result['shots'][0]]}
            return result
        self.models.ask=malformed
        _,result=self.agent.understand({'mode':'local'},self.asset,threading.Event(),progress=lambda _:None)
        self.assertEqual(len(responses),len(result['output']['shots'])+1)
        self.assertIn('exactly one shot',responses[1])
        self.assertIn('Previous response',responses[1])

    def test_json_parse_error_can_be_corrected_and_invalid_shape_still_fails(self):
        original=self.models.ask; attempts=[]
        def malformed(prompt,*args,**kwargs):
            if 'EDITORIAL_SHOT' in prompt:
                attempts.append(prompt)
                if len(attempts)==1: raise ValueError('Model did not return a valid structured result.')
                return {'video_summary':'Missing shot'}
            return original(prompt,*args,**kwargs)
        self.models.ask=malformed
        with self.assertRaisesRegex(ValueError,'Shot output failed validation'):
            self.agent.understand({'mode':'local'},self.asset,threading.Event(),progress=lambda _:None)
        self.assertEqual(len(attempts),3)
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
