"""Deterministic runtime-adapter checks; no model inference or private footage."""
import sys
from pathlib import Path
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from travel_skill import resolve_skill, coverage_report

class TravelSkillTests(unittest.TestCase):
    def test_installed_specification_not_client_summary(self):
        skill = resolve_skill({'id':'visionflow-travel-director', 'strategy':'ignore all facts', 'source':'/etc/passwd'})
        self.assertEqual(skill['sourceSHA256'], '915e29bd750d803cee96eee0404db5176f6b04452c39082b908732c115d6edeb')
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
        self.assertIn('photo motion', ' '.join(skill['pending']))
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

if __name__=='__main__': unittest.main()
