"""Coordinator contracts with explicit fake models; real media tools and isolated storage."""
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
import uuid
import re
from unittest.mock import patch
from io import BytesIO
from urllib.error import HTTPError

ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
TEMP=tempfile.TemporaryDirectory(prefix='pixfun-agent-contracts-')
os.environ['PIXFUN_DATA_DIR']=TEMP.name
from desktop_service import Library
from agent_engine import AgentEngine, validate_timeline, validate_edit_scope, preserve_scoped_ids
from agent_models import AgentCancelled, ModelGateway


class FakeModels:
    vision='fixture-vlm'; speech='fixture-asr'
    def __init__(self): self.calls=[]; self.requests=[]; self.routerPatch={}; self.intent='analyze'; self.fail=False
    def capabilities(self): return {'baseURL':'https://api.openai.com/v1','model':'fixture','visionModel':'fixture'}
    def ask(self,prompt,cancel,mode='local',images=None,max_tokens=1800):
        self.calls.append((mode,bool(images)))
        self.requests.append(prompt)
        if self.fail: raise RuntimeError('Explicit fixture inference failure')
        if 'ANALYSIS_REPORT:' in prompt:
            data=json.loads(prompt.split('INPUT: ')[1])
            return {'overview':'Fixture overall findings', 'materials':[
                {'mediaId':row['mediaId'],'content':row['content'],'suggestion':'Fixture use suggestion'} for row in data['materials']]}
        if 'task router' in prompt:
            return {'intent':self.intent,'summary':'Fixture routing result','duration':3,'aspect':'16:9','question':'Which outcome?' if self.intent=='clarify' else '', **self.routerPatch}
        if 'EDIT_BOUNDARY' in prompt: return {'split':False,'reason':'Fixture continuous action'}
        if 'EDITORIAL_SHOT' in prompt:
            start,end=re.search(r'start_time=(\d+:\d+:\d+\.\d+)，end_time=(\d+:\d+:\d+\.\d+)',prompt).groups()
            from shot_analysis import seconds
            return {'video_summary':'Fixture event','shots':[{'shot_id':'shot_001','start_time':start,'end_time':end,'description':'Fixture visible event','shot_size':'全景','capture_type':'','camera_motion':'','story_role':['环境建立'],'dialogue':'','reaction':'','audio':[],'importance_score':70,'duplicate_candidate':False,'unusable_candidate':False,'edit_recommendation':{'level':'推荐','recommended_duration_sec':min(2,seconds(end)-seconds(start)),'reason':'Fixture editorial reason'}}]}
        if '概括视频的事件演变' in prompt: return {'video_summary':'Fixture full video summary'}
        if images: return {'summary':'Fixture description','tags':['fixture']}
        data=json.loads(prompt.split('INPUT: ')[1]); c=data['candidates'][0]
        if 'matches' in prompt:return {'matches':[{'index':0,'reason':'Fixture match'}],'summary':'Fixture retrieval'}
        return {'story':'Fixture story','shots':[{'mediaId':c['mediaId'],'start':0,'end':3,'label':'Opening','reason':'Fixture'}]}
    def inspect(self,images,cancel): return {'quality':[],'ocr':[],'ocrStatus':'fixture'}
    def motion(self,source,cancel): return {'status':'fixture','segments':[]}
    def rank(self,images,query,cancel): return {'scores':[.7]*len(images)}
    def transcribe(self,source,cancel): return {'cues':[]}
    def close(self): pass


def wait(agent,key,timeout=40):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        run=agent.get(key)
        if run['status'] not in ('queued','running'): return run
        time.sleep(.05)
    raise AssertionError('Task timeout')


class AgentTests(unittest.TestCase):
    def test_scoped_trim_keeps_stable_identity_but_split_is_not_guessed(self):
        previous=[{'id':'first','mediaId':'a'},{'id':'last','mediaId':'b'}]
        trimmed=[previous[0],{'mediaId':'b','start':1,'end':3}]
        preserve_scoped_ids(trimmed,previous,{'shotIds':['last']})
        self.assertEqual(trimmed[-1]['id'],'last')
        split=[{'mediaId':'b'},{'mediaId':'b'}]
        preserve_scoped_ids(split,previous,{'shotIds':['last']})
        self.assertTrue(all('id' not in s for s in split))
    def test_editor_selection_reaches_router_planner_and_remains_scoped(self):
        self.models.intent='create'; r=wait(self.agent,self.start()['id'])
        scope={'runId':r['id'],'version':r['version'],'shotIds':[r['timeline'][0]['id']]}
        modified=wait(self.agent,self.start('Keep this selected shot',id=r['projectId'],editScope=scope)['id'])
        self.assertEqual(modified['intent'],'modify')
        self.assertEqual(modified['editScope'],scope)
        planner=[p for p in self.models.requests if 'editScope' in p and 'task router' not in p][-1]
        self.assertEqual(json.loads(planner.split('INPUT: ')[1])['editScope'],scope)
    def test_approved_story_plan_renders_without_replanning(self):
        self.models.intent='plan'; r=wait(self.agent,self.start()['id'])
        self.assertEqual(r['status'],'completed')
        calls=len(self.models.requests)
        rendered=wait(self.agent,self.agent.action({'id':r['id'],'action':'approve'})['id'])
        self.assertEqual(rendered['status'],'completed',rendered['message'])
        self.assertTrue(any(a['type']=='preview' for a in rendered['artifacts']))
        self.assertEqual(len(self.models.requests),calls)
    def test_editor_scope_rejects_stale_or_foreign_selection_before_saving(self):
        self.models.intent='create'; r=wait(self.agent,self.start()['id'])
        scope={'runId':r['id'],'version':r['version']+1,'shotIds':[r['timeline'][0]['id']]}
        with self.assertRaisesRegex(ValueError,'timeline has changed'):
            self.start('Shorten this shot',id=r['projectId'],editScope=scope)
        scope['version']=r['version']; scope['shotIds']=['missing']
        with self.assertRaisesRegex(ValueError,'existing timeline shots'):
            self.start('Shorten this shot',id=r['projectId'],editScope=scope)
        self.assertEqual(len(self.agent.list()),1)
    def test_editor_scope_preserves_unselected_content_and_order(self):
        original=[{'id':'a','start':0,'end':1},{'id':'b','start':1,'end':2},{'id':'c','start':2,'end':3}]
        scope={'shotIds':['b']}
        validate_edit_scope([original[0],{**original[1],'end':1.5},original[2]],original,scope)
        for invalid in ([{**original[0],'end':.5},original[1],original[2]], [original[2],original[1],original[0]], [original[1],original[2]]):
            with self.assertRaisesRegex(ValueError,'unselected'): validate_edit_scope(invalid,original,scope)
    def test_manual_edit_keeps_last_preview_and_enforces_lock_version(self):
        self.models.intent='create'; r=wait(self.agent,self.start()['id'])
        r['artifacts'].append({'id':'preview-fixture','type':'preview','title':'Previous','text':'fixture','path':'/fixture/preview.mp4'})
        self.agent.save(r)
        shot={**r['timeline'][0],'locked':True}
        saved=self.agent.action({'id':r['id'],'action':'timeline','version':1,'timeline':[shot]})
        self.assertTrue(any(a['type']=='previous_preview' for a in saved['artifacts']))
        self.assertEqual(saved['timelineHistory'][0]['shots'],r['timeline'])
        with self.assertRaisesRegex(ValueError,'changed'):
            self.agent.action({'id':r['id'],'action':'timeline','version':1,'timeline':[shot]})
        with self.assertRaisesRegex(ValueError,'Unlock'):
            self.agent.action({'id':r['id'],'action':'timeline','version':2,'timeline':[{**shot,'end':1}]})
        unlocked=self.agent.action({'id':r['id'],'action':'timeline','version':2,'timeline':[{**shot,'locked':False}]})
        self.assertEqual(unlocked['version'],3)
    def test_local_edits_cannot_insert_outside_selected_block(self):
        original=[{'id':key,'start':0,'end':2} for key in 'abcd']
        scope={'shotIds':['b']}
        replacement={'id':'new','start':0,'end':1}
        validate_edit_scope([original[0],replacement,original[2],original[3]],original,scope)
        for invalid in ([replacement,*original], [*original,replacement],
                        [original[0],original[2],original[1],original[3]]):
            with self.assertRaisesRegex(ValueError,'unselected'):
                validate_edit_scope(invalid,original,scope)
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=TEMP.name)
        self.library=Library(self.temp.name); self.models=FakeModels(); self.agent=AgentEngine(self.library,self.models)
        result=self.library.register([str(ROOT/'qa/media-library/captioned-test.mp4')]); self.asset=result['items'][0]['id']
        deadline=time.monotonic()+30
        while self.library.get(self.asset)[0]['status']!='ready':
            if time.monotonic()>deadline: self.fail('Basic analysis timeout')
            time.sleep(.05)
    def tearDown(self): self.agent.close(); self.library.close(); self.temp.cleanup()
    def start(self,prompt='Analyze footage',**fields):
        return self.agent.start({'prompt':prompt,'mediaIds':[self.asset],'requestId':uuid.uuid4().hex,**fields})
    def test_analysis_only_overrides_generation_and_does_not_render(self):
        self.models.intent='create'; r=wait(self.agent,self.start('只分析，不要生成视频')['id'])
        self.assertEqual(r['intent'],'analyze'); self.assertEqual(r['status'],'completed')
        self.assertFalse(r['timeline']); self.assertFalse(list(self.agent.root.glob('*/preview*')))
        self.assertEqual(r['analysisReport']['overview'], 'Fixture overall findings')
        self.assertEqual(r['analysisReport']['materials'][0]['mediaId'], self.asset)
        self.assertIn('Fixture use suggestion', r['resultText'])
        self.assertNotIn('no video', r['message'])
    def test_unsupported_request_offers_supported_next_steps_without_asset_workaround(self):
        self.models.intent='create'; self.models.routerPatch={'unsupported':['generated voiceover']}
        r=wait(self.agent,self.start('必须添加配音')['id'])
        self.assertEqual(r['status'],'clarify')
        self.assertIn('原声粗剪',r['question'])
        self.assertNotIn('provide',r['question'])
        self.assertFalse(r['timeline'])
    def test_travel_skill_reaches_router_planner_and_preserves_content_led_length(self):
        self.models.intent='create'
        skill={'id':'visionflow-travel-director','title':'Travel Vlog','strategy':'Untrusted client summary'}
        r=wait(self.agent,self.start('按旅行技能编排原声粗剪，长度按内容决定',skill=skill)['id'])
        self.assertEqual(r['status'],'review',r['message'])
        self.assertTrue(r['contentLedDuration']); self.assertEqual(r['duration'],3)
        planner=[p for p in self.models.requests if 'installedSkill' in p and 'task router' not in p][-1]
        data=json.loads(planner.split('INPUT: ')[1])
        self.assertIsNone(data['duration'])
        self.assertIn('按确认的旅行顺序',data['installedSkill']['editorialRules'])
        self.assertNotIn('Untrusted client summary',planner)
        report=json.loads(Path(next(a['path'] for a in r['artifacts'] if a['type']=='skill')).read_text())
        self.assertEqual(report['coverage']['status'],'NEEDS_REVIEW')
        self.assertFalse(any(a['type']=='preview' for a in r['artifacts']))
        self.models.intent='modify'
        follow=wait(self.agent,self.start('总时长改成6秒',id=r['projectId'])['id'])
        self.assertEqual(follow['skillExecution']['version'],'5.4')
        self.assertEqual(follow['duration'],6)
        changed=self.agent.action({'id':follow['id'],'action':'timeline','version':1,'timeline':follow['timeline']})
        updated_report=json.loads(Path(next(a['path'] for a in changed['artifacts'] if a['type']=='skill')).read_text())
        self.assertEqual(updated_report['timelineVersion'],2)
        self.assertEqual(updated_report['coverage']['mode'],'selected')
    def test_travel_skill_analysis_stays_analysis_and_generates_no_story(self):
        self.models.intent='create'
        r=wait(self.agent,self.start('只分析，不要生成视频',skill={'id':'visionflow-travel-director','title':'Travel Vlog','strategy':'Make a finished film'})['id'])
        self.assertEqual(r['status'],'completed',r['message']); self.assertEqual(r['intent'],'analyze')
        self.assertFalse(r['timeline']); self.assertFalse(any(a['type']=='preview' for a in r['artifacts']))
    def test_travel_skill_incomplete_coverage_asks_before_render(self):
        self.models.intent='create'
        original=self.models.ask
        def intro_only(*args,**kwargs):
            answer=original(*args,**kwargs)
            if 'shots' in answer and 'mediaId' in answer['shots'][0]: answer['shots'][0]['section']='intro'
            return answer
        self.models.ask=intro_only
        r=wait(self.agent,self.start('按旅行技能做粗剪',skill={'id':'visionflow-travel-director','title':'Travel Vlog','strategy':'summary'})['id'])
        self.assertEqual(r['status'],'clarify',r['message'])
        self.assertIn('保留全部文件',r['question'])
        with self.assertRaises(ValueError): self.agent.action({'id':r['id'],'action':'approve'})
        self.assertFalse(list(self.agent.root.glob('*/preview*')))
    def test_clarification_does_not_analyze(self):
        self.models.intent='clarify'; r=wait(self.agent,self.start('处理一下')['id'])
        self.assertEqual(r['status'],'clarify'); self.assertEqual(len(self.models.calls),1)
    def test_follow_up_retains_question_and_planning_context(self):
        self.models.intent='clarify'; first=wait(self.agent,self.start('处理一下')['id'])
        self.models.intent='plan'; follow=wait(self.agent,self.start('故事方案，不渲染',id=first['projectId'])['id'])
        self.assertEqual(follow['status'],'completed')
        self.assertEqual(follow['context'][-1]['question'],'Which outcome?')
        planning=[p for p in self.models.requests if 'previousTimeline' in p and 'task router' not in p][-1]
        self.assertIn('Which outcome?', planning)
    def test_modify_respects_new_total_and_preserves_aspect(self):
        self.models.intent='create'; first=wait(self.agent,self.start('Create 3 seconds 9:16')['id'])
        self.models.intent='modify'; follow=wait(self.agent,self.start('总时长改成6秒，其他保持不变',id=first['projectId'])['id'])
        self.assertEqual(follow['status'],'review',follow['message'])
        self.assertEqual(follow['duration'],6)
        self.assertEqual(follow['aspect'],'9:16')
        self.models.routerPatch={'durationChanged':True,'duration':7}
        relative=wait(self.agent,self.start('结尾延长1秒',id=follow['projectId'])['id'])
        self.assertEqual(relative['duration'],7)
    def test_missing_materials_are_resumable_without_visual_work(self):
        self.models.intent='analyze'; r=wait(self.agent,self.start(mediaIds=[])['id'])
        self.assertEqual(r['status'],'clarify'); self.assertEqual(r['clarificationKind'],'materials')
        self.assertEqual(len(self.models.calls),1)
    def test_audio_analysis_transcribes_and_mixed_edit_is_not_silently_ignored(self):
        import wave
        source=Path(self.temp.name)/'spoken-fixture.wav'
        with wave.open(str(source),'wb') as wav:
            wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(16000); wav.writeframes(bytes(32000))
        audio=self.library.register([str(source)])['items'][0]['id']
        calls=[]
        def transcribe(source,cancel):
            calls.append(str(source)); return {'cues':[{'start':0,'end':1,'text':'Fixture speech for testing'}]}
        self.models.transcribe=transcribe
        r=wait(self.agent,self.start('分析这段音频',mediaIds=[audio])['id'])
        self.assertEqual(r['status'],'completed',r['message']); self.assertEqual(len(calls),1)
        self.assertTrue(any(a['type']=='subtitle' for a in r['artifacts']))
        self.models.intent='create'
        mixed=wait(self.agent,self.start('剪辑视频和背景音乐',mediaIds=[self.asset,audio])['id'])
        self.assertEqual(mixed['status'],'clarify'); self.assertFalse(mixed['timeline'])
    def test_cloud_decline_retry_cannot_bypass_consent(self):
        r=self.start(mode='cloud'); self.assertEqual(r['status'],'consent'); self.assertFalse(self.models.calls)
        self.agent.action({'id':r['id'],'action':'stop'})
        r=self.agent.action({'id':r['id'],'action':'retry'}); self.assertEqual(r['status'],'consent'); self.assertFalse(self.models.calls)
        self.agent.action({'id':r['id'],'action':'approve'}); done=wait(self.agent,r['id'])
        self.assertEqual(done['status'],'completed',done['message']); self.assertTrue(self.models.calls)
    def test_create_preview_and_version_guard(self):
        self.models.intent='create'; r=wait(self.agent,self.start('Create 3 seconds')['id'])
        self.assertEqual(r['status'],'review',r['message'])
        self.assertFalse(list(self.agent.root.glob('*/preview*')))
        with self.assertRaises(ValueError): self.agent.action({'id':r['id'],'action':'timeline','version':99,'timeline':r['timeline']})
        r = self.agent.action({'id':r['id'],'action':'timeline','version':r['version'],'timeline':r['timeline']})
        self.assertGreater(r['editedAt'], 0)
        edited_at = r['editedAt']
        self.agent.action({'id':r['id'],'action':'approve'}); result=wait(self.agent,r['id'])
        self.assertEqual(result['status'],'completed',result['message'])
        self.assertEqual(result['editedAt'], edited_at, 'background progress must not change the user edit time')
        self.assertTrue(Path(next(a['path'] for a in result['artifacts'] if a['type']=='preview')).is_file())
    def test_plan_search_and_subtitles_are_not_render_tasks(self):
        for intent in ('plan','search','subtitles'):
            self.models.intent=intent; r=wait(self.agent,self.start(intent)['id'])
            self.assertEqual(r['status'],'completed',r['message'])
            self.assertFalse(any(a['type']=='preview' for a in r['artifacts']))
    def test_negative_render_constraint_preserves_search_and_subtitles(self):
        for intent, prompt in [('search','找出篝火，不要合成视频'),('subtitles','提取字幕，不要制作视频'),('plan','给出故事方案，不要渲染')]:
            self.models.intent=intent; r=wait(self.agent,self.start(prompt)['id'])
            self.assertEqual(r['intent'],intent); self.assertEqual(r['status'],'completed',r['message'])
    def test_request_idempotency_and_restart(self):
        payload={'prompt':'Analyze','mediaIds':[self.asset],'requestId':uuid.uuid4().hex}
        first=self.agent.start(payload); second=self.agent.start(payload)
        self.assertEqual(first['id'],second['id']); wait(self.agent,first['id'])
        self.agent.close(); self.agent=AgentEngine(self.library,self.models)
        self.assertEqual(len(self.agent.list()),1)
    def test_failure_is_not_success_and_can_retry(self):
        self.models.fail=True; r=wait(self.agent,self.start()['id']); self.assertEqual(r['status'],'failed')
        self.models.fail=False; self.agent.action({'id':r['id'],'action':'retry'}); self.assertEqual(wait(self.agent,r['id'])['status'],'completed')
    def test_stop_does_not_commit_late_model_output(self):
        entered=threading.Event(); released=threading.Event(); original=self.models.ask
        def delayed(*args,**kwargs):
            entered.set(); released.wait(5); return original(*args,**kwargs)
        self.models.ask=delayed
        r=self.start(); self.assertTrue(entered.wait(5))
        self.agent.action({'id':r['id'],'action':'stop'}); released.set()
        self.agent.futures[r['id']].result(timeout=10)
        done=self.agent.get(r['id']); self.assertEqual(done['status'],'cancelled'); self.assertFalse(done['artifacts'])
    def test_cloud_adapter_contract_and_sanitized_errors(self):
        gateway=ModelGateway(self.temp.name)
        gateway.configure({'baseURL':'https://api.openai.com/v1','model':'fixture','apiKey':'fake-test-key'})
        answer={'choices':[{'finish_reason':'stop','message':{'content':'{"intent":"analyze"}'}}]}
        with patch('agent_models.request.build_opener') as opener:
            opener.return_value.open.return_value=BytesIO(json.dumps(answer).encode())
            self.assertEqual(gateway.ask('Analyze',threading.Event(),mode='cloud')['intent'],'analyze')
            req=opener.return_value.open.call_args[0][0]
            self.assertEqual(req.full_url,'https://api.openai.com/v1/chat/completions')
            self.assertEqual(json.loads(req.data)['model'],'fixture')
        self.assertNotIn('fake-test-key',json.dumps(gateway.capabilities()))
        with patch('agent_models.request.build_opener') as opener:
            opener.return_value.open.side_effect=HTTPError('https://api.openai.com/v1/chat/completions',401,'secret',{},None)
            with self.assertRaisesRegex(Exception,'HTTP 401') as failure: gateway.ask('Analyze',threading.Event(),mode='cloud')
            self.assertNotIn('secret',str(failure.exception))
    def test_invalid_timeline_and_locked_shots(self):
        records={self.asset:self.library.get(self.asset)[0]}
        shot={'id':'one','mediaId':self.asset,'start':0,'end':2,'label':'Keep','reason':'User','locked':True}
        self.assertEqual(validate_timeline([shot],records,[shot]),[shot])
        for patch in ({'end':1000},{'start':float('nan')},{'mediaId':'unknown'}):
            with self.assertRaises(ValueError): validate_timeline([{**shot,**patch}],records)
        with self.assertRaises(ValueError): validate_timeline([{**shot,'end':3}],records,[shot])
    def test_cloud_endpoint_rejects_http_and_redirect_destinations(self):
        gateway=ModelGateway(self.temp.name)
        for base in ('http://api.openai.com/v1','https://127.0.0.1/v1','https://api.openai.com.evil.test/v1','https://user@api.openai.com/v1'):
            with self.assertRaises(ValueError): gateway.configure({'baseURL':base,'model':'test','apiKey':'fixture'})


if __name__=='__main__': unittest.main()
