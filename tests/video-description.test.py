"""Description contracts with explicit model fixtures, isolated from the real library."""
import concurrent.futures
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
TEMP=tempfile.TemporaryDirectory(prefix='pixfun-description-test-'); os.environ['PIXFUN_DATA_DIR']=TEMP.name
from desktop_service import Library
from video_description import VideoDescriptions, DESCRIPTION_PROMPT, validate_description, validate_grounding, omit_unverified_trim_note, omit_editorial_advice
from agent_models import AgentCancelled, ModelOutputError, CapabilityMissing

DESCRIPTION='Two travelers share a quiet moment at a wooded campsite, with a cup movement and shared glance as the key visual beats.\n\n1. Campsite view: Two people sit across a picnic table, with cups, camping equipment and a tent visible nearby.\n2. Cup movement: One person lifts a cup while the framing remains close to the table.\n3. Shared glance: The pair turn toward each other, keeping the activity within the same setting.\n\nEditing note: Use the scene to establish camp life or as a quiet pause between walking scenes.'

class Models:
    vision='fixture'; speech='fixture'
    def __init__(self): self.prompts=[]; self.invalid=False; self.block=None
    def capabilities(self): return {'localModel':'fixture','localSpeech':False}
    def ask(self,prompt,cancel,**kwargs):
        self.prompts.append(prompt)
        if self.block:
            self.block.set()
            while not cancel.wait(.01): pass
            raise AgentCancelled()
        return {'title':'Two travelers share drinks at camp','full_description':'Too short' if self.invalid else DESCRIPTION}

class Agent:
    def __init__(self,library): self.library=library; self.models=Models(); self.pool=concurrent.futures.ThreadPoolExecutor(max_workers=1)
    def ready_source(self,key,cancel): return self.library.get(key)
    def observe(self,run,key,cancel,progress=None,window_seconds=15):
        progress('Window 1/2')
        return self.library.get(key)[0], {'segments':[{'start':0,'end':2,'summary':'开头人物端杯','facts':{'raw_stable_ranges_test_only':[0,1]}},{'start':2,'end':4,'summary':'结尾人物交流','facts':{}}]}

class DescriptionTests(unittest.TestCase):
    def test_newly_observed_focus_reaches_description_without_stale_record_retry(self):
        original=self.agent.observe
        def observe(*args,**kwargs):
            stale,visual=original(*args,**kwargs)
            tags=[{'id':'subject:people','category':'subject','key':'people','label':'People','source':'visual-primary-subject',
                   'evidence':[{'text':'The camera follows the person in checkered clothing'}]},
                  {'id':'activity:walking','category':'activity','key':'walking','label':'Walking & hiking','source':'visual-primary-activity',
                   'evidence':[{'subject':'people','text':'The followed person walks along the road'}]}]
            self.library.patch(self.id,analysisEvidence={'version':1,'focusVersion':2,'tags':tags})
            return stale,visual
        self.agent.observe=observe
        self.service.start(self.id)
        state=self.finish()
        self.assertEqual(state['status'],'ready',state.get('message'))
        self.assertEqual(len(self.agent.models.prompts),1)
        self.assertIn('primaryFocus',self.agent.models.prompts[0])
        self.assertIn('person in checkered clothing',self.agent.models.prompts[0])
        self.assertIn('followed person walks',self.agent.models.prompts[0])
        self.assertEqual(state['signature'],self.service.signature(*self.library.get(self.id)))

    def test_user_perspective_keeps_location_grounding_and_never_invents_intent(self):
        for phrase in ('where they were, what happened', 'never as proof', 'private intention',
                       'not an inventory', 'If the lake name or sunset is unverified'):
            self.assertIn(phrase,DESCRIPTION_PROMPT)

    def test_readability_rewrite_cannot_drop_verified_shooting_area(self):
        value={'title':'喷泉旁有人经过','full_description':'一位穿深色外套的人从喷泉旁走过，背景有米色建筑。'}
        result=validate_grounding(value,{'location':'清华大学'})
        self.assertEqual(result['title'],'喷泉旁有人经过｜清华大学')
        self.assertEqual(result['full_description'],value['full_description'])
        self.assertEqual(validate_grounding(value,{}),value)

    def test_inline_numbered_changes_get_paragraphs_without_changing_facts(self):
        from video_description import normalize_description, CHINESE_DESCRIPTION_PROMPT
        body='广场上的喷泉正在喷水，背景有米色建筑与绿树。1. 行人走近：一人从喷泉右侧走过。'
        result=normalize_description({'title':'广场喷泉','full_description':body})
        self.assertEqual(result['full_description'],body.replace('。1.','。\n\n1.'))
        self.assertIn('不是摄影技术报告',CHINESE_DESCRIPTION_PROMPT)
        self.assertIn('不要编造用户想拍的原因',CHINESE_DESCRIPTION_PROMPT)

    def test_camera_heavy_overview_gets_one_text_only_rewrite(self):
        from unittest.mock import Mock
        self.agent.models.output_language='zh-Hans'
        original={'title':'喷泉旁行人经过','full_description':'镜头推近中央喷泉，一名穿深色外套的人从喷泉右侧走过，背景有米色建筑。'}
        revised={'title':'喷泉旁行人经过','full_description':'一名穿深色外套的人从中央喷泉右侧走过，喷泉后方是米色建筑。'}
        self.agent.models.ask=Mock(side_effect=[original,revised])
        self.agent.observe=Mock(wraps=self.agent.observe)
        self.service.start(self.id);state=self.finish()
        self.assertEqual(state['status'],'ready')
        self.assertEqual(state['full_description'],revised['full_description'])
        self.assertEqual(state['attempts'],2)
        self.assertEqual(self.agent.observe.call_count,1)
        self.assertNotIn('images',self.agent.models.ask.call_args.kwargs)

    def test_optional_style_failure_keeps_valid_description_and_does_not_retry(self):
        from unittest.mock import Mock
        self.agent.models.output_language='zh-Hans'
        original={'title':'喷泉旁行人经过','full_description':'镜头推近中央喷泉，一名穿深色外套的人从喷泉右侧走过，背景有米色建筑。'}
        self.agent.models.ask=Mock(side_effect=[original,TimeoutError('worker timeout')])
        self.service.start(self.id);state=self.finish()
        self.assertEqual(state['status'],'ready')
        self.assertEqual(state['full_description'],original['full_description'])
        self.assertEqual(self.agent.models.ask.call_count,2)

    def test_resolved_area_flows_into_description_and_changes_signature(self):
        item,source = self.library.get(self.id)
        before=self.service.signature(item,source)
        metadata={**(item.get('metadata') or {}),'location':{'latitude':40.0036,'longitude':116.3181}}
        place={'version':2,'provider':'apple-geocoder','language':'zh-Hans','latitude':40.0036,'longitude':116.3181,
            'label':'北京市 · 海淀区 · 清华大学 · 至善路','area':'清华大学','nearbyName':'清华大学药学院','resolvedAt':1792100000}
        self.library.patch(self.id,metadata=metadata,resolvedPlace=place)
        item,source=self.library.get(self.id)
        self.assertNotEqual(before,self.service.signature(item,source))
        self.service.start(self.id)
        self.assertEqual(self.finish()['status'],'ready')
        prompt=self.agent.models.prompts[-1]
        self.assertIn('清华大学',prompt)
        self.assertNotIn('清华大学药学院',prompt)
        self.assertIn('not proof that a particular building',prompt)

    def test_readable_chinese_overview_and_distinct_changes(self):
        simple={'title':'平台上的五人', 'full_description':'五位身着黑色长袍的人站在木质平台上，手持金边托盘，背景有石雕和树木。'}
        self.assertEqual(validate_description(simple,'zh-Hans'),simple)
        detail={**simple,'full_description':simple['full_description']+'\n\n1. 人物转身：中间一人转身并向前移动。\n2. 画面推进：镜头缓慢推近，托盘在画面中更加清楚。'}
        self.assertEqual(validate_description(detail,'zh-Hans'),detail)
        for body in (simple['full_description']+'\n1. 转身：中间一人转身。\n2. 人物：中间一人转身。',
                     simple['full_description']+'\n2. 转身：中间一人转身。',
                     '木质平台上的人。'*30):
            with self.subTest(body=body[:50]),self.assertRaises(ValueError):
                validate_description({**simple,'full_description':body},'zh-Hans')
        self.assertIn('not keyword lists',DESCRIPTION_PROMPT)
        self.assertIn('Clothing alone does not establish',DESCRIPTION_PROMPT)

    def test_place_finishing_during_generation_reuses_visual_evidence(self):
        from unittest.mock import Mock
        item,_=self.library.get(self.id)
        self.library.patch(self.id,metadata={**item['metadata'],'location':{'latitude':40.0036,'longitude':116.3181}})
        place={'version':2,'provider':'apple-geocoder','language':'zh-Hans','latitude':40.0036,'longitude':116.3181,
               'label':'北京市 · 海淀区 · 清华大学','area':'清华大学','nearbyName':'清华大学药学院','resolvedAt':1792100000}
        original=self.agent.models.ask
        def ask(prompt,cancel,**kwargs):
            result=original(prompt,cancel,**kwargs)
            if len(self.agent.models.prompts)==1: self.library.patch(self.id,resolvedPlace=place)
            return result
        self.agent.models.ask=ask
        self.agent.observe=Mock(wraps=self.agent.observe)
        self.service.start(self.id)
        state=self.finish()
        self.assertEqual(state['status'],'ready',state.get('message'))
        self.assertEqual(state['attempts'],2)
        self.assertEqual(self.agent.observe.call_count,1)
        self.assertNotIn('清华大学',self.agent.models.prompts[0])
        self.assertIn('清华大学',self.agent.models.prompts[1])
        self.assertNotIn('药学院',self.agent.models.prompts[1])

    def test_english_simple_scene_does_not_require_invented_changes(self):
        value={'title':'People holding trays', 'full_description':'Five people in dark robes stand on a wooden platform holding gold-rimmed trays, with stone sculptures and trees behind them in sunlight.'}
        self.assertEqual(validate_description(value),value)

    def test_duplicate_chinese_changes_repair_using_same_evidence(self):
        from unittest.mock import Mock
        self.agent.models.output_language='zh-Hans'
        overview='五位身着黑色长袍的人站在木质平台上，手持金边托盘，背景有树木。'
        self.agent.models.ask=Mock(side_effect=[
            {'title':'平台上的五人','full_description':overview+'\n1. 转身：中间一人转身。\n2. 人物：中间一人转身。'},
            {'title':'平台上的五人','full_description':overview+'\n1. 转身：中间一人转身并向前移动。'}])
        self.agent.observe=Mock(wraps=self.agent.observe)
        self.service.start(self.id)
        result=self.finish()
        self.assertEqual(result['status'],'ready',result.get('message'))
        self.assertEqual(result['attempts'],2)
        self.assertEqual(self.agent.observe.call_count,1)

    def test_extra_fields_are_normalized_without_another_model_call(self):
        self.agent.models.ask = lambda *args, **kwargs: {'title':'Camp life', 'full_description':DESCRIPTION, 'tags':['camp']}
        self.service.start(self.id)
        value = self.finish()
        self.assertEqual(value['status'], 'ready', value.get('message'))
        self.assertEqual(value['attempts'], 1)

    def test_parser_error_is_repaired_without_reobserving(self):
        from unittest.mock import Mock
        original = self.agent.observe
        self.agent.observe = Mock(side_effect=original)
        self.agent.models.ask = Mock(side_effect=[ModelOutputError('Invalid JSON'), {'title':'Camp life','full_description':DESCRIPTION}])
        self.service.start(self.id)
        value = self.finish()
        self.assertEqual(value['status'], 'ready', value.get('message'))
        self.assertEqual(value['attempts'], 2)
        self.assertEqual(self.agent.observe.call_count, 1)

    def test_bad_format_budget_and_runtime_failure_do_not_loop(self):
        from unittest.mock import Mock
        for failure, expected in ((ModelOutputError('bad JSON'), 2), (CapabilityMissing('no memory'), 1), (TimeoutError('timeout'), 1)):
            self.agent.models.ask = Mock(side_effect=failure)
            self.service.start(self.id, True)
            value = self.finish()
            self.assertEqual(value['status'], 'failed')
            self.assertEqual(self.agent.models.ask.call_count, expected)

    def test_fenced_json_is_normalized_but_prose_is_not_executed(self):
        from video_description import normalize_description
        result = normalize_description({'raw':'```json\n'+json.dumps({'title':'Camp life','full_description':DESCRIPTION})+'\n```'})
        self.assertEqual(result['title'], 'Camp life')
        with self.assertRaises(ModelOutputError): normalize_description("__import__('os').system('echo unsafe')")

    def test_local_speech_is_saved_for_detail_search_and_cache(self):
        with self.library.connect() as db: db.execute('CREATE TABLE IF NOT EXISTS agent_analysis (signature TEXT PRIMARY KEY, record TEXT NOT NULL)')
        item, source = self.library.get(self.id)
        original_name = item['file']['name']
        self.library.patch(self.id, metadata={**item['metadata'],'hasAudio':True,'duration':10}, result={'analysis':{'segments':[], 'subtitleCues':[], 'subtitleState':'pending'}})
        self.agent.models.capabilities = lambda: {'localSpeech':True,'localModel':'fixture'}
        calls=[]
        def transcribe(source, cancel):
            calls.append(source)
            return {'language':'zh','cues':[{'start':0,'end':2,'text':'沿着河边往前走。'},{'start':3,'end':4,'text':'这里就是入口。'}]}
        self.agent.models.transcribe=transcribe
        cues,_=self.service.speech(self.library.get(self.id)[0],source,threading.Event())
        saved=self.library.get(self.id)[0]
        self.assertEqual(saved['result']['analysis']['subtitleCues'],cues)
        self.assertEqual(saved['result']['analysis']['subtitleState'],'transcribed')
        self.assertEqual(saved['result']['analysis']['subtitleLanguage'],'zh')
        self.assertEqual(saved['result']['analysis']['segments'],[])
        self.assertEqual(saved['file']['name'],original_name)
        self.service.speech(saved,source,threading.Event())
        self.assertEqual(len(calls),1)

    def test_authored_repeated_subtitles_are_not_filtered_as_asr(self):
        item,source=self.library.get(self.id)
        cue={'start':0,'end':1,'text':'Hello ' * 30}
        item['result']={'analysis':{'subtitleCues':[cue],'subtitleState':'embedded'}}
        self.assertEqual(self.service.speech(item,source,threading.Event())[0],[cue])

    def test_chinese_output_and_language_cache(self):
        from product_language import language_instruction
        self.assertIn('简体中文', language_instruction('zh-Hans'))
        self.assertIn('English', language_instruction('en'))
        item, source = self.library.get(self.id)
        original_signature = self.service.signature(item, source)
        self.agent.models.output_language = 'zh-Hans'
        self.assertNotEqual(original_signature, self.service.signature(item, source))
        value = {'title':'河边的人物与山景', 'full_description':'河水从石墙旁流过，岸边停着汽车，两个人站在水边。\n\n1. 河岸：画面可见河流和石墙。\n2. 人物：镜头向右移动，露出两名行人和远处山体。'}
        self.agent.models.ask = lambda prompt, cancel, **kwargs: value
        self.service.start(self.id)
        result = self.finish()
        self.assertEqual(result['status'], 'ready', result.get('message'))
        self.assertEqual(result['full_description'], value['full_description'])
        with self.assertRaises(ValueError): validate_description({'title':'River', 'full_description':DESCRIPTION}, 'zh-Hans')

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=TEMP.name); self.library=Library(self.temp.name); self.agent=Agent(self.library)
        self.id=self.library.register([str(ROOT/'qa/media-library/captioned-test.mp4')])['items'][0]['id']
        deadline=time.monotonic()+15
        while self.library.get(self.id)[0]['status']!='ready':
            if time.monotonic()>deadline: self.fail('metadata timeout')
            time.sleep(.03)
        self.service=VideoDescriptions(self.library,self.agent)
    def tearDown(self): self.service.stop(); self.agent.pool.shutdown(wait=True); self.library.close(); self.temp.cleanup()
    def finish(self):
        self.service.jobs[self.id][1].result(timeout=10)
        return self.library.get(self.id)[0]['videoDescription']
    def test_full_prompt_all_windows_and_cache(self):
        original=self.library.get(self.id)[0]['file']['name']
        self.service.start(self.id); value=self.finish()
        self.assertEqual(value['status'],'ready',value['message']); validate_description({k:value[k] for k in ('title','full_description')})
        self.assertIn(DESCRIPTION_PROMPT,self.agent.models.prompts[0]); self.assertIn('结尾人物交流',self.agent.models.prompts[0])
        self.assertNotIn('raw_stable_ranges_test_only',self.agent.models.prompts[0])
        self.assertNotIn('Editing note:', value['full_description'])
        self.assertEqual(self.library.get(self.id)[0]['file']['name'],original)
        calls=len(self.agent.models.prompts); self.service.start(self.id); self.assertEqual(len(self.agent.models.prompts),calls)
    def test_metadata_change_invalidates_cache(self):
        self.service.start(self.id); old=self.finish()
        self.library.patch(self.id,context={'location':'User confirmed place'})
        self.service.start(self.id); new=self.finish()
        self.assertNotEqual(old['signature'],new['signature']); self.assertEqual(len(self.agent.models.prompts),2)
    def test_description_reuses_reviewed_shots_and_tracks_revision(self):
        from media_evidence import source_stamp, shot_revision
        from unittest.mock import patch
        _,source=self.library.get(self.id)
        shots=[{'id':'canonical-a','start':0.,'end':4.,'label':'The travelers lift cups at a picnic table.'}]
        revision=shot_revision(shots)
        self.library.patch(self.id,shotAnalysis={'status':'ready','sourceStamp':source_stamp(source),'revision':revision,'segments':shots})
        with patch.object(self.agent,'observe',side_effect=AssertionError('Must reuse reviewed shots')):
            self.service.start(self.id); value=self.finish()
        self.assertEqual(value['status'],'ready',value.get('message'))
        self.assertEqual(value['shotRevision'],revision)
        self.assertEqual(value['shotReferences'],[{'id':'canonical-a','start':0.,'end':4.}])
        self.assertIn('canonical-a',self.agent.models.prompts[0])
        self.assertNotIn('开头人物端杯',self.agent.models.prompts[0])
        shots[0]['label']='A corrected visual account'
        self.library.patch(self.id,shotAnalysis={'status':'ready','sourceStamp':source_stamp(source),'revision':revision,'segments':shots})
        self.assertNotEqual(value['signature'],self.service.signature(*self.library.get(self.id)))
    def test_failed_regeneration_retains_last_good_result(self):
        self.service.start(self.id); old=self.finish(); self.agent.models.invalid=True
        self.service.start(self.id,True); new=self.finish()
        self.assertEqual(new['status'],'failed'); self.assertEqual(new['full_description'],old['full_description'])
        calls=len(self.agent.models.prompts); self.service.start(self.id); self.assertEqual(len(self.agent.models.prompts),calls)
    def test_cancel_never_commits_late_output(self):
        entered=threading.Event(); self.agent.models.block=entered
        self.service.start(self.id); self.assertTrue(entered.wait(3)); self.service.stop(self.id)
        self.assertEqual(self.finish()['status'],'cancelled')
    def test_restart_marks_interrupted(self):
        self.library.patch(self.id,videoDescription={'status':'running'})
        VideoDescriptions(self.library,self.agent)
        self.assertEqual(self.library.get(self.id)[0]['videoDescription']['status'],'interrupted')
    def test_schema_rejects_short_long_extra_fields(self):
        for value in ({'title':'有效标题','full_description':'短'}, {'title':'有效标题','full_description':'字'*201},{'title':'有效标题','full_description':DESCRIPTION,'extra':'no'}):
            with self.assertRaises(ValueError): validate_description(value)
        self.assertEqual(validate_grounding({'title':'营地喝饮料｜无地点 · 手持','full_description':DESCRIPTION},{})['title'],'营地喝饮料')
        self.assertEqual(validate_grounding({'title':'营地喝饮料｜阿勒泰 · Pocket 3','full_description':DESCRIPTION},{'location':'阿勒泰'})['title'],'营地喝饮料｜阿勒泰')
        with self.assertRaises(ValueError): validate_grounding({'title':'营地互动','full_description':'无动作推进或叙事转折'},{})
    def test_scannable_format_requires_overview_and_consecutive_moments(self):
        for text in (DESCRIPTION.replace('1. ', '3. '), DESCRIPTION.replace('\n', ' '),
                     DESCRIPTION[DESCRIPTION.index('1. '):]):
            with self.subTest(text=text[:40]), self.assertRaises(ValueError):
                validate_description({'title':'Camp life','full_description':text})
        value=validate_description({'title':'Camp life','full_description':DESCRIPTION})
        self.assertEqual(value['full_description'],DESCRIPTION)
        self.assertIn('NOT detected cuts',DESCRIPTION_PROMPT)
        self.assertNotIn('one natural paragraph',DESCRIPTION_PROMPT)
    def test_overview_cannot_hide_another_wall_of_text(self):
        value={'title':'Camp life','full_description':('visible '*41)+'\n\n1. Opening view: A person sits by a river.'}
        with self.assertRaisesRegex(ValueError,'overview'): validate_description(value)
    def test_timecodes_cannot_exceed_duration_or_have_invalid_seconds(self):
        for stamp in ('6:20','0:96'):
            with self.subTest(stamp=stamp), self.assertRaisesRegex(ValueError,'timestamps'):
                validate_grounding({'title':'River','full_description':f'1. View at {stamp}: River.'},{},10.96)
        value={'title':'River','full_description':'1. View at 0:06: River.'}
        self.assertEqual(validate_grounding(value,{},10.96),value)
        with self.assertRaisesRegex(ValueError,'trim ranges'):
            validate_description({'title':'Camp life','full_description':DESCRIPTION+' At 0:03.'})
    def test_optional_unverified_trim_note_is_omitted_without_losing_moments(self):
        value={'title':'Camp life','full_description':DESCRIPTION.split('\n\nEditing note:')[0]+'\n\nEditing note: Use [6:20–10:96].\nAnd keep another invalid range.\n\nVerification note: Check the transcript.'}
        cleaned=omit_unverified_trim_note(value)
        self.assertNotIn('6:20',cleaned['full_description'])
        self.assertNotIn('invalid range',cleaned['full_description'])
        self.assertIn('3. Shared glance',cleaned['full_description'])
        self.assertIn('Verification note:',cleaned['full_description'])
        self.assertIn('6:20',value['full_description'])
        validate_description(cleaned)
    def test_long_evidence_keeps_last_chunk(self):
        evidence=[{'start':i,'text':('开头' if i==0 else '结尾标识' if i==7 else '中间')+'描述'*1200} for i in range(8)]
        def summary(prompt,cancel,**kwargs):
            self.agent.models.prompts.append(prompt); return {'summary':'保留结尾标识' if '结尾标识' in prompt else '前半部分概要'}
        self.agent.models.ask=summary
        result=self.service.compact(evidence,threading.Event())
        self.assertIn('结尾标识',json.dumps(result,ensure_ascii=False))
        self.assertEqual(result[0]['start'], 0)
    def test_objective_description_keeps_visual_changes_without_edit_advice(self):
        value={'title':'Camp life','full_description':DESCRIPTION+'\nContinued advice.\n\nVerification note: Clothing color is unclear.'}
        cleaned=omit_editorial_advice(value)
        self.assertNotIn('Editing note:',cleaned['full_description'])
        self.assertNotIn('Continued advice',cleaned['full_description'])
        self.assertIn('3. Shared glance',cleaned['full_description'])
        self.assertIn('Clothing color is unclear',cleaned['full_description'])
        self.assertIn('Editing note:',value['full_description'])
        self.assertIn('Do not call the entire video static',DESCRIPTION_PROMPT)
        self.assertIn('ending',DESCRIPTION_PROMPT)
        self.assertIn('not evidence of a cut',DESCRIPTION_PROMPT)

if __name__=='__main__': unittest.main()
