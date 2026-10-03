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
from agent_engine import AgentEngine, edit_receipt, validate_timeline, validate_edit_scope, preserve_scoped_ids, requested_total_duration, selected_duration_constraint, validate_requested_edit
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
            return {'video_summary':'Fixture event','shots':[{'shot_id':'shot_001','start_time':start,'end_time':end,'description':'Fixture visible event','shot_size':'Wide shot','capture_type':'','camera_motion':'','story_role':['Establishing'],'dialogue':'','reaction':'','audio':[],'importance_score':70,'duplicate_candidate':False,'unusable_candidate':False,'edit_recommendation':{'level':'Recommended','recommended_duration_sec':min(2,seconds(end)-seconds(start)),'reason':'Fixture editorial reason'}}]}
        if 'VIDEO_SUMMARY:' in prompt: return {'video_summary':'Fixture full video summary'}
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


def write_test_tone(path):
    # Test-only PCM fixture: bundled FFmpeg intentionally omits lavfi inputs.
    import array
    import math
    import wave
    samples = array.array('h', (round(4096 * math.sin(2 * math.pi * 440 * n / 48000)) for n in range(3 * 48000)))
    if sys.byteorder != 'little': samples.byteswap()
    with wave.open(str(path), 'wb') as wav:
        wav.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
        wav.writeframes(samples.tobytes())


class AgentTests(unittest.TestCase):
    def edit_fixture(self):
        # Persist a baseline and accepted edit without inference or rendering.
        with patch.object(self.agent, 'dispatch'):
            baseline = self.start()
        baseline.update(status='completed', intent='create', timeline=[{'id':'one', 'mediaId':self.asset,
            'start':0, 'end':3, 'label':'Opening', 'reason':'Fixture', 'locked':False}], aspect='9:16')
        baseline['finishing'] = {'music':None, 'narration':[], 'originalVolume':0.4,
                                 'transition':{'kind':'none','duration':0.25}}
        self.agent.save(baseline)
        with patch.object(self.agent, 'dispatch'):
            changed = self.start('Shorten the opening', id=baseline['projectId'],
                editBase={'runId':baseline['id'], 'version':baseline['version']})
        changed.update(status='completed', intent='modify', timeline=[{**baseline['timeline'][0], 'end':2}],
                       finishing={**baseline['finishing'], 'originalVolume':0}, aspect='16:9')
        changed['editReceipt'] = edit_receipt(changed)
        self.agent.save(changed)
        return baseline, changed

    def test_edit_receipt_and_undo_restore_exact_saved_draft(self):
        baseline, changed = self.edit_fixture()
        self.assertEqual(changed['editReceipt']['changedShotIds'], ['one'])
        self.assertTrue(changed['editReceipt']['soundOrCaptions'])
        restored = self.agent.action({'id':changed['id'], 'action':'undo_edit', 'version':changed['version']})
        self.assertEqual(restored['timeline'], baseline['timeline'])
        self.assertEqual(restored['finishing'], baseline['finishing'])
        self.assertEqual(restored['aspect'], baseline['aspect'])
        self.assertEqual(restored['duration'], 3)
        self.assertTrue(restored['editReceipt']['undone'])
        self.assertEqual(restored['status'], 'review')
        self.assertFalse(any(a['type']=='preview' for a in restored['artifacts']))
        with self.assertRaises(ValueError):
            self.agent.action({'id':changed['id'], 'action':'undo_edit', 'version':restored['version']})

    def test_undo_refuses_stale_version_and_later_requests(self):
        baseline, changed = self.edit_fixture()
        with self.assertRaises(ValueError):
            self.agent.action({'id':changed['id'], 'action':'undo_edit', 'version':0})
        changed['version'] += 1
        self.agent.save(changed)
        with self.assertRaises(ValueError):
            self.agent.action({'id':changed['id'], 'action':'undo_edit', 'version':changed['version']})
        changed['version'] -= 1
        self.agent.save(changed)
        with patch.object(self.agent, 'dispatch'):
            newer = self.start('Another request', id=changed['projectId'])
        newer['status'] = 'completed'; self.agent.save(newer)
        with self.assertRaises(ValueError):
            self.agent.action({'id':changed['id'], 'action':'undo_edit', 'version':changed['version']})
        self.assertEqual(self.agent.get(changed['id'])['timeline'], changed['timeline'])

    def test_whole_film_base_is_version_guarded_before_new_request(self):
        baseline, changed = self.edit_fixture()
        before = len(self.agent.list())
        with self.assertRaises(ValueError):
            self.start('Modify everything', id=changed['projectId'], editBase={'runId':baseline['id'], 'version':baseline['version']})
        self.assertEqual(len(self.agent.list()), before)

    def test_saved_draft_is_the_next_request_and_undo_baseline_without_rendering(self):
        baseline, changed = self.edit_fixture()
        saved = self.agent.action({'id':changed['id'], 'action':'timeline', 'version':changed['version'],
            'timeline':[{**changed['timeline'][0], 'end':1.5}], 'finishing':changed['finishing']})
        with patch.object(self.agent, 'dispatch'):
            request = self.start('Extend this clip', id=saved['projectId'],
                editBase={'runId':saved['id'], 'version':saved['version']},
                editScope={'runId':saved['id'], 'version':saved['version'], 'shotIds':['one']})
        self.assertEqual(request['previousTimeline'], saved['timeline'])
        self.assertEqual(request['previousFinishing'], saved['finishing'])
        self.assertIsNone(request['previousPreview'])
        request.update(timeline=[{**saved['timeline'][0], 'end':2}], finishing=saved['finishing'], status='completed')
        request['editReceipt'] = edit_receipt(request); self.agent.save(request)
        restored = self.agent.action({'id':request['id'], 'action':'undo_edit', 'version':request['version']})
        self.assertEqual(restored['timeline'][0]['end'], 1.5)
        self.assertEqual(restored['finishing'], saved['finishing'])

    def test_receipt_marks_only_clips_affected_by_caption_or_clip_audio(self):
        shots = [{'id':'a', 'start':0, 'end':2}, {'id':'b', 'start':0, 'end':2}]
        run = {'previousTimeline':shots, 'timeline':shots, 'version':1, 'previousFinishing':{},
               'finishing':{'clipAudio':[{'shotId':'b', 'volume':0.5, 'muted':False}]}}
        self.assertEqual(edit_receipt(run)['changedShotIds'], ['b'])
        run['finishing'] = {'captions':[{'id':'c', 'start':0, 'end':1, 'text':'Hi'}]}
        self.assertEqual(edit_receipt(run)['changedShotIds'], ['a'])
        run['finishing'] = {}; run['packaging'] = {'title':'New title'}
        self.assertTrue(edit_receipt(run)['packagingChanged'])
        self.assertEqual(edit_receipt(run)['changedShotIds'], ['a', 'b'])
        run['packaging'] = {}; run['finishing'] = {'musicMuted':False, 'narrationMuted':False, 'narrationVolume':1}
        self.assertFalse(edit_receipt(run)['soundOrCaptions'])
        self.assertEqual(edit_receipt(run)['changedShotIds'], [])

    def test_undo_does_not_present_generated_preview_as_restored_draft(self):
        baseline, changed = self.edit_fixture()
        changed['artifacts'] = [{'id':'generated', 'type':'preview', 'title':'Generated', 'text':'', 'path':str(ROOT/'qa/media-library/captioned-test.mp4')}]
        changed['previousPreview'] = {**changed['artifacts'][0], 'id':'baseline', 'title':'Baseline'}
        self.agent.save(changed)
        restored = self.agent.action({'id':changed['id'], 'action':'undo_edit', 'version':changed['version']})
        self.assertEqual(restored['artifacts'][0]['type'], 'previous_preview')
        self.assertEqual(restored['artifacts'][-1]['title'], 'Baseline')
        self.assertEqual(restored['artifacts'][-1]['type'], 'preview')
        self.assertEqual(restored['artifacts'][-1]['timelineVersion'], restored['version'])
        self.assertEqual(restored['artifacts'][0]['timelineVersion'], changed['version'])
        self.assertEqual(restored['status'], 'completed')

    def test_legacy_undo_keeps_default_finishing_renderable(self):
        baseline, changed = self.edit_fixture()
        changed['previousFinishing'] = {}; self.agent.save(changed)
        restored = self.agent.action({'id':changed['id'], 'action':'undo_edit', 'version':changed['version']})
        import agent_finishing
        finish = agent_finishing.validate(restored.get('finishing', {}), {}, restored['duration'], restored['timeline'])
        self.assertEqual(finish['originalVolume'], 1)
        self.assertEqual(finish['transition']['kind'], 'none')

    def test_highlight_starter_renders_even_when_model_router_would_plan(self):
        self.models.intent='plan'
        run=wait(self.agent,self.start('Make a short travel highlight reel from the best moments.')['id'])
        self.assertEqual(run['status'],'completed',run['message'])
        self.assertEqual(run['intent'],'create')
        self.assertEqual(run['coverageMode'],'selected')
        self.assertTrue(any(a['type']=='preview' for a in run['artifacts']))
        self.assertFalse(any('task router' in prompt for prompt in self.models.requests))

    def test_create_with_audio_without_subtitles_reaches_preview(self):
        # Real audio stream, no sidecar; model responses alone are fixtures.
        source = Path(self.temp.name) / 'audio-without-subtitles.mp4'
        tone = Path(self.temp.name) / 'tone.wav'
        write_test_tone(tone)
        self.agent.command(['ffmpeg','-v','error','-y','-i',ROOT/'qa/media-library/captioned-test.mp4',
            '-i',tone,'-t','3','-map','0:v:0','-map','1:a:0',
            '-c:v','copy','-c:a','aac',source], threading.Event())
        asset = self.library.register([str(source)])['items'][0]['id']
        self.models.intent = 'create'
        with patch.object(self.models, 'capabilities', return_value={**self.models.capabilities(), 'localSpeech':True}), \
             patch.object(self.models, 'transcribe', return_value={'cues':[]}) as transcribe:
            from video_description import VideoDescriptions
            def legacy_helper(*args, **kwargs):
                helper = VideoDescriptions(*args, **kwargs)
                del helper.library  # Reproduce the old incomplete helper initialization.
                return helper
            with patch('shot_analysis.VideoDescriptions', side_effect=legacy_helper):
                failed = wait(self.agent, self.start('Create a 3-second travel video', mediaIds=[asset])['id'])
            self.assertEqual(failed['status'], 'failed')
            self.assertIn("has no attribute 'library'", failed['message'])
            run = wait(self.agent, self.agent.action({'id':failed['id'], 'action':'retry'})['id'])
        self.assertEqual(run['status'], 'completed', run['message'])
        self.assertTrue(any(a['type']=='preview' for a in run['artifacts']))
        self.assertEqual(transcribe.call_count, 1)

    def test_clear_create_ignores_redundant_router_confirmation_and_renders(self):
        self.models.intent = 'create'; self.models.routerPatch = {'question':'Shall I create this video?'}
        run = wait(self.agent, self.start('Create a 3-second travel video')['id'])
        self.assertEqual(run['status'], 'completed', run['message'])
        self.assertEqual(run['question'], '')
        self.assertTrue(any(a['type']=='preview' for a in run['artifacts']))
        self.assertFalse(run.get('conversationHistory'))

    def test_explicit_plan_approval_is_respected_and_only_once(self):
        self.models.intent = 'create'
        run = wait(self.agent, self.start('Create a 3-second video. Show me the plan for approval before rendering.')['id'])
        self.assertEqual(run['status'], 'review', run['message'])
        self.assertFalse(any(a['type']=='preview' for a in run['artifacts']))
        done = wait(self.agent, self.agent.action({'id':run['id'], 'action':'approve'})['id'])
        self.assertEqual(done['status'], 'completed', done['message'])
        self.assertEqual(sum(item.get('selected')=='approve' for item in done['conversationHistory']), 1)

    def test_first_edit_does_not_ask_to_create_missing_timeline(self):
        self.models.intent = 'modify'
        self.models.routerPatch = {'question':'Create a rough cut first?'}
        run = wait(self.agent, self.start('编辑成一个视频')['id'])
        self.assertEqual(run['intent'], 'create')
        self.assertEqual(run['status'], 'completed', run['message'])
        self.assertEqual(run['question'], '')
        self.assertTrue(any(a['type']=='preview' for a in run['artifacts']))

    def test_plan_only_cannot_render_even_when_router_says_create(self):
        self.models.intent = 'create'
        run = wait(self.agent, self.start('Give me a plan only; do not render a video.')['id'])
        self.assertEqual(run['intent'], 'plan')
        self.assertEqual(run['status'], 'completed', run['message'])
        self.assertFalse(any(a['type']=='preview' for a in run['artifacts']))

    def test_partial_findings_are_published_before_completion_without_duplicate_shots(self):
        self.models.intent = 'clarify'
        run = wait(self.agent, self.start()['id'])
        run.update(status='running', question='')
        self.agent.save(run)
        record = self.library.get(self.asset)[0]
        segment = dict(mediaId=self.asset, start=0, end=2, summary='Visible trail and walker')
        self.agent.publish_analysis_progress(run, record, segment)
        current = self.agent.get(run['id'])
        self.assertEqual(current['status'], 'running')
        self.assertEqual(current['artifacts'][0]['type'], 'observation')
        segment['editorial'] = {'edit_recommendation': {'level':'Recommended','recommended_duration_sec':2,'reason':'Establish the trail'}}
        self.agent.publish_analysis_progress(run, record, segment)
        current = self.agent.get(run['id'])
        self.assertEqual([a['type'] for a in current['artifacts']], ['analysis'])
        self.agent.artifact(current,'analysis',record['file']['name'],'Final description',mediaId=self.asset,start=0,end=2)
        self.agent.save(current)
        self.assertEqual(len(self.agent.get(run['id'])['artifacts']),1)
        self.agent.publish_analysis_progress({'mode':'local'},record,segment)

    def test_follow_up_preserves_old_message_files_and_accepts_new_uploads(self):
        self.models.intent = 'clarify'
        first = wait(self.agent, self.start()['id'])
        second = wait(self.agent, self.start('Explain more', id=first['projectId'], messageMediaIds=[])['id'])
        self.assertEqual(second['messageAttachments'], [])
        self.assertEqual(second['mediaIds'], [self.asset])
        old = self.agent.get(first['id'])
        self.assertEqual(old['messageAttachments'][0]['id'], self.asset)
        self.assertEqual(old['conversationHistory'][0]['response'], 'Explain more')
        photo = self.library.register([str(ROOT/'public/media/travel/story/coffee.jpg')])['items'][0]['id']
        third = wait(self.agent, self.start('Also use this photo', id=first['projectId'], mediaIds=[self.asset,photo],messageMediaIds=[photo])['id'])
        self.assertEqual([a['id'] for a in third['messageAttachments']],[photo])
        self.assertEqual(len(self.agent.get(first['id'])['conversationHistory']),1)

    def test_model_selected_retrieval_informs_story_without_dropping_sources(self):
        self.models.intent = 'plan'
        self.models.routerPatch = {'tools': ['rank'], 'query': 'mountain view'}
        ranked = []
        self.models.rank = lambda images, query, cancel: ranked.append(query) or {'scores': [.7] * len(images)}
        run = wait(self.agent, self.start('Plan a mountain story')['id'])
        self.assertEqual(run['status'], 'completed', run['message'])
        self.assertEqual(ranked, ['mountain view'])
        planning = next(p for p in self.models.requests if p.startswith('Plan an edit using only'))
        inputs = json.loads(planning.split('INPUT: ')[1])
        self.assertTrue(all(c['similarity'] == .7 for c in inputs['candidates']))
        self.assertEqual(run['toolPlan']['scope'], 'attached-media-only')

    def test_story_reuses_shot_speech_without_second_transcription(self):
        self.models.intent = 'plan'
        original = self.agent.understand
        def understand(*args, **kwargs):
            record, result = original(*args, **kwargs)
            result = dict(result, speechEvidence={'source': 'local ASR', 'cues': [{'start': 0, 'end': 1, 'text': 'We made it to the summit.'}]})
            return record, result
        self.agent.understand = understand
        self.models.transcribe = lambda *args: self.fail('Speech already checked; must not transcribe twice')
        run = wait(self.agent, self.start('Plan a travel story')['id'])
        self.assertEqual(run['status'], 'completed', run['message'])
        planning = next(p for p in self.models.requests if p.startswith('Plan an edit using only'))
        self.assertEqual(json.loads(planning.split('INPUT: ')[1])['transcriptEvidence'][0]['text'], 'We made it to the summit.')

    def test_unsupported_tool_proposal_cannot_execute(self):
        self.models.intent = 'create'; self.models.routerPatch = {'tools': ['shell']}
        run = wait(self.agent, self.start('Make a rough cut')['id'])
        self.assertEqual(run['status'], 'failed')
        self.assertIn('unsupported tool', run['message'])
        self.assertFalse(run['timeline'])

    def test_invalid_source_range_explains_exact_repair_without_clamping(self):
        records = {'video': {'id': 'video', 'kind': 'video', 'metadata': {'duration': 9}}}
        for start, end in [(6, 12), (-1, 3), (0, None)]:
            with self.assertRaisesRegex(ValueError, '0 <= start < end <= 9.0'):
                validate_timeline([{'mediaId': 'video', 'start': start, 'end': end}], records)
        valid = validate_timeline([{'mediaId': 'video', 'start': 6, 'end': 9}], records)
        self.assertEqual((valid[0]['start'], valid[0]['end']), (6, 9))
    def test_total_duration_is_not_confused_with_each_shot_duration(self):
        for prompt in ('A 6-second story, each video appearing for 3 seconds.',
                       '每段3秒，总时长6秒', 'each clip 3 seconds, total duration of 6 seconds'):
            self.assertEqual(requested_total_duration(prompt)[1], '6')
        self.assertIsNone(requested_total_duration('Use each clip for 3 seconds'))
        self.assertEqual(requested_total_duration('Make a 2-minute video')[2], 'minute')
    def test_selected_duration_requires_a_real_timeline_change(self):
        shots=[{'id':'a','start':0,'end':3}, {'id':'b','start':3,'end':6}]
        scope={'shotIds':['b']}
        for prompt in ('Shorten only the selected final shot to 2 seconds.', '选中镜头缩短到2秒'):
            constraint=selected_duration_constraint(prompt,scope,shots)
            self.assertEqual(constraint['totalDuration'],5)
            with self.assertRaisesRegex(ValueError,'actually last'): validate_requested_edit(shots,constraint)
            validate_requested_edit([shots[0],{**shots[1],'end':5}],constraint)
        self.assertIsNone(selected_duration_constraint('Do not shorten the selected shot to 2 seconds',scope,shots))
    def test_model_cannot_claim_trim_without_changing_timeline(self):
        self.models.intent='create'; first=wait(self.agent,self.start('Create 3 seconds')['id'])
        self.models.intent='modify'
        run=wait(self.agent,self.start('Shorten the selected shot to 2 seconds',id=first['projectId'],
            editScope={'runId':first['id'],'version':first['version'],'shotIds':[first['timeline'][0]['id']]})['id'])
        self.assertEqual(run['status'],'failed')
        self.assertIn('actually last 2',run['message'])
        self.assertFalse(run['timeline'])
    def test_malformed_story_response_gets_one_bounded_repair(self):
        self.models.intent='plan'
        original=self.models.ask; planning=[]
        def malformed_once(prompt,*args,**kwargs):
            if prompt.startswith('Plan an edit using only'):
                planning.append(prompt)
                if len(planning)==1: raise ValueError('Model did not return a valid structured result.')
            return original(prompt,*args,**kwargs)
        self.models.ask=malformed_once
        run=wait(self.agent,self.start('Plan 3 seconds')['id'])
        self.assertEqual(run['status'],'completed',run['message'])
        self.assertEqual(len(planning),2)
        self.assertIn('Repair the invalid proposal',planning[-1])
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
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.library.close)
        self.addCleanup(self.agent.close)
        result=self.library.register([str(ROOT/'qa/media-library/captioned-test.mp4')]); self.asset=result['items'][0]['id']
        deadline=time.monotonic()+float(os.environ.get('PIXFUN_TEST_IMPORT_TIMEOUT','30'))
        while self.library.get(self.asset)[0]['status']!='ready':
            if time.monotonic()>deadline: self.fail('Basic analysis timeout')
            time.sleep(.05)
    def tearDown(self): pass  # addCleanup also runs when setUp fails.
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
        self.models.intent='create'; self.models.routerPatch={'unsupported':['voice cloning']}
        r=wait(self.agent,self.start('Clone a celebrity voice for the narration')['id'])
        self.assertEqual(r['status'],'clarify')
        self.assertIn('standard-voice narration',r['question'])
        self.assertNotIn('provide',r['question'])
        self.assertFalse(r['timeline'])
    def test_travel_skill_reaches_router_planner_and_preserves_content_led_length(self):
        self.models.intent='create'
        skill={'id':'visionflow-travel-director','title':'Travel Vlog','strategy':'Untrusted client summary'}
        r=wait(self.agent,self.start('按旅行技能编排原声粗剪，长度按内容决定',skill=skill)['id'])
        self.assertEqual(r['status'],'completed',r['message'])
        self.assertTrue(r['contentLedDuration']); self.assertEqual(r['duration'],3)
        planner=[p for p in self.models.requests if 'installedSkill' in p and 'task router' not in p][-1]
        data=json.loads(planner.split('INPUT: ')[1])
        self.assertIsNone(data['duration'])
        self.assertIn('按确认的旅行顺序',data['installedSkill']['editorialRules'])
        self.assertNotIn('Untrusted client summary',planner)
        report=json.loads(Path(next(a['path'] for a in r['artifacts'] if a['type']=='skill')).read_text())
        self.assertEqual(report['coverage']['status'],'NEEDS_REVIEW')
        self.assertTrue(any(a['type']=='preview' for a in r['artifacts']))
        self.models.intent='modify'
        follow=wait(self.agent,self.start('总时长改成6秒',id=r['projectId'])['id'])
        self.assertEqual(follow['skillExecution']['version'],'5.4')
        self.assertEqual(follow['duration'],6)
        changed=self.agent.action({'id':follow['id'],'action':'timeline','version':1,'timeline':follow['timeline']})
        updated_report=json.loads(Path(next(a['path'] for a in changed['artifacts'] if a['type']=='skill')).read_text())
        self.assertEqual(updated_report['timelineVersion'],2)
        self.assertEqual(updated_report['coverage']['mode'],'selected')
    def test_default_travel_skill_and_explicit_alternative(self):
        self.models.intent='create'
        r=wait(self.agent,self.start('Make a travel edit')['id'])
        self.assertEqual(r['skillExecution']['id'],'visionflow-travel-director')
        self.assertIn('Travel Vlog ·',r['skillNotice'])
        self.assertIn('route-led',r['skillNotice'])
        self.assertTrue(r['contentLedDuration'])
        other=wait(self.agent,self.start('Make an edit',skill={'id':'food-tour','title':'Food tour','strategy':'Food'})['id'])
        self.assertNotIn('skillNotice',other)
    def test_mixed_media_reaches_planning_without_type_confirmation(self):
        photo=self.library.register([str(ROOT/'public/media/travel/story/coffee.jpg')])['items'][0]['id']
        self.models.intent='plan'
        r=wait(self.agent,self.start('Plan a 3-second story',mediaIds=[self.asset,photo])['id'])
        self.assertNotEqual(r.get('clarificationKind'),'video_only')
        self.assertIn(photo,r['mediaIds'])
        self.assertEqual(r['intent'],'plan')
        self.assertTrue(any(a.get('mediaId')==photo and a['type']=='analysis' for a in r['artifacts']))
        self.assertEqual([a['id'] for a in r['messageAttachments']], [self.asset, photo])
        self.assertTrue(self.library.get(photo)[1].is_file())
        with self.library.connect() as db:
            project=json.loads(db.execute('SELECT record FROM projects WHERE id=?',(r['projectId'],)).fetchone()[0])
        self.assertEqual([a['id'] for a in project['attachments']],[self.asset,photo])
        with self.assertRaisesRegex(ValueError,'pending'):
            self.agent.action({'id':r['id'],'action':'use_videos'})
    def test_legacy_mixed_task_can_resume(self):
        photo=self.library.register([str(ROOT/'public/media/travel/story/coffee.jpg')])['items'][0]['id']
        self.models.intent='create'
        r=wait(self.agent,self.start(mediaIds=[self.asset,photo])['id'])
        r.pop('clarificationKind',None); r.pop('confirmedBrief',None); r['status']='clarify'
        r['question']='This rough-cut workflow currently uses video and its original sound only. Remove separate audio/photos to continue; music mixing and photo slideshows are not connected.'
        self.agent.save(r)
        resumed=wait(self.agent,self.agent.action({'id':r['id'],'action':'use_videos'})['id'])
        self.assertEqual(resumed['status'],'completed',resumed['message'])
        self.assertEqual(resumed['mediaIds'],[self.asset])
    def test_photo_only_creates_a_real_preview(self):
        photo=self.library.register([str(ROOT/'public/media/travel/story/coffee.jpg')])['items'][0]['id']
        self.models.intent='create'
        r=wait(self.agent,self.start(mediaIds=[photo])['id'])
        self.assertEqual(r['status'],'completed',r['message'])
        self.assertTrue(r['timeline'])
        self.assertTrue(any(a['type']=='preview' for a in r['artifacts']))
        with self.assertRaisesRegex(ValueError,'pending'):
            self.agent.action({'id':r['id'],'action':'use_videos'})
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
            if 'shots' in answer and 'mediaId' in answer['shots'][0]:
                # A normal three-second opening now counts as real coverage.
                # Exercise genuinely insufficient exposure, not the repaired label.
                answer['shots'][0].update(section='intro', end=.5)
            return answer
        self.models.ask=intro_only
        r=wait(self.agent,self.start('按旅行技能做粗剪',skill={'id':'visionflow-travel-director','title':'Travel Vlog','strategy':'summary'})['id'])
        self.assertEqual(r['status'],'clarify',r['message'])
        self.assertIn('include every file',r['question'])
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
        self.assertEqual(follow['status'],'completed',follow['message'])
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
        # Mixed visual/audio edits are supported now; verify the selected audio
        # reaches the actual preview instead of expecting the old limitation.
        self.assertEqual(mixed['status'],'completed', mixed['message'])
        self.assertTrue(mixed['timeline'])
        self.assertEqual(mixed['finishing']['music']['mediaId'], audio)
        self.assertTrue(any(a['type']=='preview' for a in mixed['artifacts']))
    def test_cloud_decline_retry_cannot_bypass_consent(self):
        r=self.start(mode='cloud'); self.assertEqual(r['status'],'consent'); self.assertFalse(self.models.calls)
        self.agent.action({'id':r['id'],'action':'stop'})
        r=self.agent.action({'id':r['id'],'action':'retry'}); self.assertEqual(r['status'],'consent'); self.assertFalse(self.models.calls)
        self.agent.action({'id':r['id'],'action':'approve'}); done=wait(self.agent,r['id'])
        self.assertEqual(done['status'],'completed',done['message']); self.assertTrue(self.models.calls)
    def test_create_preview_and_version_guard(self):
        self.models.intent='create'; r=wait(self.agent,self.start('Create 3 seconds')['id'])
        self.assertEqual(r['status'],'completed',r['message'])
        self.assertTrue(list(self.agent.root.glob('*/preview*')))
        self.assertFalse(any(item['status']=='review' for item in r.get('conversationHistory', [])))
        with self.assertRaisesRegex(ValueError, 'pending'):
            self.agent.action({'id':r['id'],'action':'approve'})
        with self.assertRaises(ValueError): self.agent.action({'id':r['id'],'action':'timeline','version':99,'timeline':r['timeline']})
        r = self.agent.action({'id':r['id'],'action':'timeline','version':r['version'],'timeline':r['timeline']})
        self.assertGreater(r['editedAt'], 0)
        edited_at = r['editedAt']
        self.agent.action({'id':r['id'],'action':'approve'}); result=wait(self.agent,r['id'])
        self.assertEqual(result['status'],'completed',result['message'])
        self.assertEqual(result['editedAt'], edited_at, 'background progress must not change the user edit time')
        self.assertTrue(Path(next(a['path'] for a in result['artifacts'] if a['type']=='preview')).is_file())
    def test_renderer_preserves_audible_source_not_just_an_empty_audio_track(self):
        # Synthetic tone is QA evidence only; never added to user footage or deliverables.
        import array
        import math
        source=Path(self.temp.name)/'test-tone-video.mp4'; cancel=threading.Event()
        tone=Path(self.temp.name)/'tone.wav'
        write_test_tone(tone)
        self.agent.command(['ffmpeg','-v','error','-y','-i',ROOT/'qa/media-library/captioned-test.mp4',
            '-i',tone,'-t','3','-map','0:v:0','-map','1:a:0',
            '-c:v','copy','-c:a','aac',source],cancel)
        asset=self.library.register([str(source)])['items'][0]['id']
        self.models.intent='create'
        run=wait(self.agent,self.start('Create 3 seconds with original sound only',mediaIds=[asset])['id'])
        rendered=run
        self.assertEqual(rendered['status'],'completed',rendered['message'])
        preview=next(a for a in rendered['artifacts'] if a['type']=='preview')
        self.assertIn('original sound',preview['text'])
        samples=array.array('f')
        samples.frombytes(self.agent.command(['ffmpeg','-v','error','-ss','0.5','-i',preview['path'],
            '-t','1','-vn','-ac','1','-ar','16000','-f','f32le','-'],cancel))
        self.assertGreater(len(samples),15000)
        self.assertGreater(math.sqrt(sum(x*x for x in samples)/len(samples)),.03)
        frequency=sum(a<=0<b for a,b in zip(samples,samples[1:]))/(len(samples)/16000)
        self.assertAlmostEqual(frequency,440,delta=3)
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
