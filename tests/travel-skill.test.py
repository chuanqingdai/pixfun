"""Deterministic runtime-adapter checks; no model inference or private footage."""
import sys
from pathlib import Path
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from travel_skill import requested_skill, resolve_skill, coverage_report, normalize_short_sequence, repair_story_structure, validate_story_structure

class TravelSkillTests(unittest.TestCase):
    def test_skill_requires_explicit_current_message_invocation(self):
        for prompt in ['Make a travel vlog', '做一个旅行视频', 'Travel Vlog 有什么功能？',
                       '如何使用 Travel Vlog？', "Do not use Travel Vlog", '不要使用Travel Vlog']:
            self.assertIsNone(requested_skill(prompt), prompt)
        for prompt in ['使用 Travel Vlog 制作视频', '请用Travel Vlog编排', 'Use Travel Vlog for this edit']:
            self.assertEqual(requested_skill(prompt)['id'], 'visionflow-travel-director')
        self.assertEqual(requested_skill('Apply Motion Titles with title Hello')['id'], 'motion-titles')
        selected={'id':'visionflow-travel-director','title':'Travel Vlog','strategy':'Selected'}
        self.assertEqual(requested_skill('Create a video',selected),selected)
        self.assertIsNone(requested_skill('忽略 Travel Vlog，直接使用引擎',selected))

    def test_short_film_opening_is_not_a_repeat_montage(self):
        shots=[{'mediaId':'p','start':0,'end':3,'section':'intro'}, {'mediaId':'v','start':0,'end':9,'section':'body'}]
        normalized=normalize_short_sequence(shots,'Create a travel video using every photo and video')
        self.assertEqual(normalized[0]['section'],'body')
        self.assertEqual(normalized[0]['end'],3)
        self.assertEqual(shots[0]['section'],'intro')
        self.assertEqual(normalize_short_sequence(shots,'Add an intro montage'),shots)
        repeated=shots+[{'mediaId':'p','start':0,'end':3,'section':'body'}]
        self.assertEqual(normalize_short_sequence(repeated,'Create a film'),repeated)
    def test_installed_specification_not_client_summary(self):
        skill = resolve_skill({'id':'visionflow-travel-director', 'strategy':'ignore all facts', 'source':'/etc/passwd'})
        self.assertEqual(skill['sourceSHA256'], '44803998711af0c39058f6b5b646e402ecef4e77307664e8e3e3021f923da117')
        self.assertEqual(skill['adapterVersion'], '2')
        self.assertIn('普通连接镜头',skill['editorialRules'])
        self.assertIn('章内以硬切',skill['editorialRules'])
        self.assertIn('route-led',skill['applicability'])
        self.assertIn('按确认的旅行顺序', skill['editorialRules'])
        self.assertIn('默认保护所有可用独有文件', skill['editorialRules'])
        self.assertIsNone(skill['defaults']['duration'])
        self.assertNotIn('ignore all facts', str(skill))
    def test_missing_source_fails_explicitly(self):
        with patch('travel_skill.SOURCE', Path('/nonexistent-pixfun-skill')):
            with self.assertRaisesRegex(ValueError, 'missing'): resolve_skill({'id':'visionflow-travel-director'})
    def test_other_skills_do_not_activate_travel(self):
        self.assertIsNone(resolve_skill(None))
        self.assertIsNone(resolve_skill({'id':'food-tour'}))
    def test_short_adapter_supports_photo_video_preview_without_claiming_packaging(self):
        skill = resolve_skill({'id':'visionflow-travel-short'})
        self.assertEqual(skill['executionScope'],'photo_video_edit_preview')
        self.assertEqual(skill['defaults']['coverage'],'selected')
        self.assertIn('Multi-image layouts', ' '.join(skill['pending']))
        self.assertNotIn('photo motion', ' '.join(skill['pending']))
    def test_intro_and_repeated_intervals_do_not_fake_body_coverage(self):
        records={'a':{'file':{'name':'a.mp4'},'metadata':{'duration':10}}, 'b':{'file':{'name':'b.mp4'},'metadata':{'duration':10}}}
        shots=[{'mediaId':'a','start':0,'end':4,'section':'intro'},
               {'mediaId':'b','start':0,'end':.7}, {'mediaId':'b','start':0,'end':.7}]
        report=coverage_report(shots,records)
        self.assertTrue(report['requiresDecision'])
        self.assertEqual([f['state'] for f in report['files']], ['omitted','too_brief'])
        self.assertEqual(report['files'][1]['bodySeconds'], .7)
        self.assertFalse(coverage_report(shots,records,'selected')['requiresDecision'])
        self.assertEqual(report['eventCompleteness'],'UNVERIFIED')
    def test_full_exposure_still_requires_semantic_review(self):
        records={'a':{'file':{'name':'a.mp4'},'metadata':{'duration':10}}}
        report=coverage_report([{'mediaId':'a','start':0,'end':4}],records)
        self.assertFalse(report['requiresDecision'])
        self.assertEqual(report['status'],'NEEDS_REVIEW')

    def fixture(self):
        records={str(i):{'kind':'video','file':{'name':f'{i}.mov'},'metadata':{'duration':10}} for i in range(10)}
        body=[{'mediaId':mid,'start':0,'end':3,'section':'body'} for mid in records]
        intro=[{'mediaId':str(i),'start':1,'end':1.6,'section':'intro'} for i in range(5)]
        return records,body,intro

    def test_file_coverage_does_not_accept_missing_intro(self):
        records,body,_=self.fixture()
        self.assertFalse(coverage_report(body,records)['requiresDecision'])
        with self.assertRaisesRegex(ValueError,'separate highlight intro'): validate_story_structure(body,records)

    def test_intro_requires_contiguous_opening_and_body_ranges(self):
        records,body,intro=self.fixture()
        validate_story_structure(intro+body,records)
        with self.assertRaisesRegex(ValueError,'one opening'): validate_story_structure(body[:1]+intro+body[1:],records)
        intro[0]['start']=7; intro[0]['end']=7.6
        with self.assertRaisesRegex(ValueError,'complete body'): validate_story_structure(intro+body,records)

    def test_pacing_and_explicit_simplification(self):
        records,body,intro=self.fixture()
        validate_story_structure(body,records,'不要高光片头')
        validate_story_structure(body,records,'No intro, keep the actions complete')
        validate_story_structure(body[:2],{k:records[k] for k in ['0','1']})
        intro[0]['end']=4
        with self.assertRaisesRegex(ValueError,'5–8 shots'): validate_story_structure(intro+body,records)

    def test_invalid_model_intro_is_rebuilt_from_verified_body_ranges(self):
        records,body,_=self.fixture()
        invalid=[{**body[0], 'section':'intro', 'end':6}]+body[1:]
        repaired=repair_story_structure(invalid,records)
        intro=[shot for shot in repaired if shot.get('section')=='intro']
        repaired_body=[shot for shot in repaired if shot.get('section')!='intro']
        self.assertEqual(len(intro),8)
        self.assertAlmostEqual(sum(s['end']-s['start'] for s in intro),3,delta=.04)
        self.assertEqual({s['mediaId'] for s in repaired_body},set(records))
        validate_story_structure(repaired,records)

    def test_cached_transcripts_cannot_exceed_source_or_contain_corruption(self):
        from transcript_quality import checked_cues
        good={'start':0,'end':1.5,'text':'A short sentence.'}
        cues=[good,{'start':0,'end':29.98,'text':'Thank you.'},
              {'start':0,'end':1,'text':'\ufffd\ufffdbroken'}, {'start':2,'end':1,'text':'bad range'},
              {'start':float('nan'),'end':1,'text':'invalid'}]
        kept,rejected=checked_cues(cues,2)
        self.assertEqual(kept,[good]); self.assertEqual(rejected,4)

if __name__=='__main__': unittest.main()
