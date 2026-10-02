import copy
import json
from pathlib import Path
import sys
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from agent_report import summarize_report, source_report, report_text
from agent_models import AgentCancelled


class Models:
    def __init__(self, answer=None, error=None): self.answer=answer; self.error=error; self.calls=[]
    def ask(self, prompt, cancel, mode, **kwargs):
        self.calls.append((prompt, mode))
        if self.error: raise self.error
        return self.answer


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.run={'prompt':'理解这些视频，做下分析','artifacts':[
            {'type':'analysis','mediaId':'camp','text':'整理背包。\n行动 · 推荐 · 3s\n用于出发准备。'},
            {'type':'analysis','mediaId':'camp','text':'拉上拉链。\n行动 · 推荐 · 2s\n用于出发准备。'},
            {'type':'analysis','mediaId':'clouds','text':'雪山与云海。\n高光 · 必留 · 5s\n展示开阔风景。'},
            {'type':'analysis','mediaId':'coffee','text':'营地里两个人煮咖啡的照片。'}]}
        self.records={k:{'kind':kind,'file':{'name':name}} for k,kind,name in [
            ('camp','video','camp.mp4'),('clouds','video','clouds.mp4'),('coffee','image','coffee.jpg')]}
        self.summaries={'camp':'人物打开背包，整理装备后拉上拉链。'}
        self.answer={'overview':'素材包含营地活动和山地风景，可考虑用准备、风景、休息的顺序组织。',
                     'materials':[{'mediaId':k,'content':'内容 '+k,'suggestion':'建议 '+k} for k in self.records]}
    def report(self, model, cancel=None):
        return summarize_report(self.run,self.records,self.summaries,model,cancel or threading.Event(),'local')
    def test_three_materials_are_visible_with_summary_and_advice(self):
        model=Models(self.answer); report=self.report(model)
        self.assertTrue(report['synthesized'])
        self.assertEqual([r['title'] for r in report['materials']],['camp.mp4','clouds.mp4','coffee.jpg'])
        self.assertEqual(report['materials'][2]['kind'],'image')
        self.assertIn('建议 camp',report_text(report))
        payload=json.loads(model.calls[0][0].split('INPUT: ')[1])
        self.assertEqual(payload['materials'][0]['content'],self.summaries['camp'])
        self.assertEqual(model.calls[0][1],'local')
    def test_incomplete_duplicate_foreign_and_malformed_answers_fall_back(self):
        variants=[{},[],None,{'overview':'','materials':[]},dict(self.answer,materials=self.answer['materials'][:1])]
        duplicate=copy.deepcopy(self.answer); duplicate['materials'][2]['mediaId']='camp'; variants.append(duplicate)
        foreign=copy.deepcopy(self.answer); foreign['materials'][2]['mediaId']='foreign'; variants.append(foreign)
        malformed=copy.deepcopy(self.answer); malformed['materials'][0]['content']=[]; variants.append(malformed)
        for answer in variants:
            with self.subTest(answer=answer):
                report=self.report(Models(answer)); self.assertFalse(report['synthesized'])
                self.assertEqual(len(report['materials']),3)
                self.assertEqual(report['materials'][0]['suggestion'],'用于出发准备。')
    def test_summary_failure_keeps_real_findings_and_no_invented_photo_advice(self):
        report=self.report(Models(error=RuntimeError('Unavailable')))
        self.assertEqual(report['materials'][2]['suggestion'],'')
        self.assertIn('雪山与云海', report_text(report))
        self.assertNotIn('no video', report_text(report))
    def test_cancel_is_not_reported_as_success(self):
        with self.assertRaises(AgentCancelled): self.report(Models(error=AgentCancelled()))
        cancel=threading.Event(); cancel.set(); model=Models(self.answer)
        with self.assertRaises(AgentCancelled): self.report(model,cancel)
        self.assertEqual(model.calls,[])
    def test_known_wrapper_is_validated_without_losing_the_written_report(self):
        self.assertTrue(self.report(Models({'ANALYSIS_REPORT':self.answer}))['synthesized'])
        self.assertFalse(self.report(Models({'ANALYSIS_REPORT':{'materials':[]}}))['synthesized'])
        self.assertFalse(self.report(Models({'ANALYSIS_REPORT':None}))['synthesized'])
    def test_large_report_preserves_all_evidence_without_model_truncation(self):
        self.summaries['camp']='内容'*13000
        model=Models(self.answer); report=self.report(model)
        self.assertEqual(model.calls,[])
        self.assertEqual(report['materials'][0]['content'],self.summaries['camp'])
    def test_speech_evidence_survives_video_summary(self):
        self.run['artifacts'].append({'type':'subtitle','mediaId':'camp','text':'Time to go.'})
        model=Models(self.answer); self.report(model)
        self.assertIn('Time to go.',model.calls[0][0])
    def test_no_findings_does_not_invent_analysis(self):
        self.run['artifacts']=[]
        report=source_report(self.run,self.records,{})
        self.assertTrue(all('No usable content' in r['content'] for r in report['materials']))
        self.assertIn('Here are the findings',report['overview'])
    def test_chinese_input_does_not_request_chinese_output(self):
        model=Models(self.answer);self.report(model)
        self.assertIn('Write in English by default',model.calls[0][0])
        self.run['prompt']='请用中文输出分析结果';self.run['artifacts']=[]
        self.assertIn('暂未提取到',source_report(self.run,self.records,{})['materials'][0]['content'])

if __name__=='__main__': unittest.main()
