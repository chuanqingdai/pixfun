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
from video_description import VideoDescriptions, DESCRIPTION_PROMPT, validate_description, validate_grounding
from agent_models import AgentCancelled

DESCRIPTION='两人在林间营地的野餐桌旁相对而坐，桌上摆着杯子和露营用品，后方可见帐篷。人物先端起杯子，随后面对彼此交流，动作集中在桌边，环境保持安静的视觉氛围。画面的价值在于交代同行者、营地生活和两人互动，可作为旅行故事的日常过程或休息段落，与行进中的镜头形成节奏对比。未提供可靠对白，不能判断具体谈话内容。'

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
        return {'title':'两人在林间营地喝饮料交流','full_description':'太短' if self.invalid else DESCRIPTION}

class Agent:
    def __init__(self,library): self.library=library; self.models=Models(); self.pool=concurrent.futures.ThreadPoolExecutor(max_workers=1)
    def ready_source(self,key,cancel): return self.library.get(key)
    def observe(self,run,key,cancel,progress=None,window_seconds=15):
        progress('Window 1/2')
        return self.library.get(key)[0], {'segments':[{'start':0,'end':2,'summary':'开头人物端杯','facts':{}},{'start':2,'end':4,'summary':'结尾人物交流','facts':{}}]}

class DescriptionTests(unittest.TestCase):
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
        self.assertEqual(self.library.get(self.id)[0]['file']['name'],original)
        calls=len(self.agent.models.prompts); self.service.start(self.id); self.assertEqual(len(self.agent.models.prompts),calls)
    def test_metadata_change_invalidates_cache(self):
        self.service.start(self.id); old=self.finish()
        self.library.patch(self.id,context={'location':'User confirmed place'})
        self.service.start(self.id); new=self.finish()
        self.assertNotEqual(old['signature'],new['signature']); self.assertEqual(len(self.agent.models.prompts),2)
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
    def test_long_evidence_keeps_last_chunk(self):
        evidence=[{'start':i,'text':('开头' if i==0 else '结尾标识' if i==7 else '中间')+'描述'*1200} for i in range(8)]
        def summary(prompt,cancel,**kwargs):
            self.agent.models.prompts.append(prompt); return {'summary':'保留结尾标识' if '结尾标识' in prompt else '前半部分概要'}
        self.agent.models.ask=summary
        result=self.service.compact(evidence,threading.Event())
        self.assertIn('结尾标识',json.dumps(result,ensure_ascii=False))

if __name__=='__main__': unittest.main()
