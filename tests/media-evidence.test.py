"""Pure fixture tests: no private library, inference or model downloads."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import media_evidence as evidence


class EvidenceTests(unittest.TestCase):
    def focus(self, category='people', activity='walking', attention=None):
        return {'category': category, 'description':'framed subject', 'reason':'Camera deliberately maintains this subject in view',
                'attention':attention or ['sustained_framing'],
                'activities':[] if activity is None else [{'category':activity,'reason':'This subject visibly performs the action'}]}

    def window(self, subjects, start=0, end=6):
        return {'start':start,'end':end,'focusVersion':2,'summary':'A deliberately framed subject with background activity.',
                'primary_subjects':subjects,'tags':['background cyclists','trees','car']}

    def test_followed_walker_does_not_inherit_background_cycling(self):
        tags=evidence.tags_from_observations({'segments':[self.window([self.focus()])]})
        self.assertEqual([t['key'] for t in tags if t['category']=='subject'], ['people'])
        self.assertEqual([t['key'] for t in tags if t['category']=='activity'], ['walking'])
        walking=next(t for t in tags if t['id']=='activity:walking')
        self.assertEqual(walking['evidence'][0]['subject'], 'people')
        self.assertEqual(walking['source'], 'visual-primary-activity')
        self.assertIn('detail:background cyclists', {t['id'] for t in tags})

    def test_nonhuman_focus_is_not_overridden_by_people_or_background_actions(self):
        for category in ('buildings','landscape','food','plants','animals'):
            with self.subTest(category=category):
                window=self.window([self.focus(category, None)])
                window['tags'] += ['people walking','running child']
                tags=evidence.tags_from_observations({'segments':[window]})
                self.assertEqual([t['key'] for t in tags if t['category']=='subject'], [category])
                self.assertEqual([t for t in tags if t['category']=='activity'], [])

    def test_deliberately_followed_bicycle_is_allowed_as_primary(self):
        tags=evidence.tags_from_observations({'segments':[self.window([self.focus('vehicles','cycling',['camera_following'])])]})
        self.assertEqual([t['key'] for t in tags if t['category']=='subject'], ['vehicles'])
        self.assertEqual([t['key'] for t in tags if t['category']=='activity'], ['cycling'])

    def test_foreground_only_is_not_focus_evidence(self):
        self.assertIsNone(evidence.normalized_primary_subjects([self.focus(attention=['foreground_emphasis'])], strict=True))
        self.assertIsNotNone(evidence.normalized_primary_subjects([self.focus(attention=['foreground_emphasis','camera_following'])], strict=True))

    def test_invalid_or_empty_modern_focus_never_reverts_to_keyword_guessing(self):
        for primary in (None, [], ['people'], [self.focus(attention=['largest_object'])]):
            window=self.window(primary)
            window['summary']='镜头跟随穿格子衬衫的人行走，背景有骑车人。'
            tags=evidence.tags_from_observations({'segments':[window]})
            self.assertFalse(any(t['category'] in ('subject','activity') for t in tags))
            self.assertTrue(any(t['category']=='detail' for t in tags))

    def test_legacy_first_clause_is_not_a_keyword_order_vote(self):
        cases=[('镜头跟随穿格子衬衫的人行走，左侧自行车道上骑车人与汽车逐渐靠近。',['people'],['walking']),
               ('镜头聚焦建筑，行人在背景中走过。',['buildings'],[]),
               ('A boy walks with a dog; cars are behind them.',[],[]),
               ('No person is visible; a car passes.',[],[])]
        for summary,subjects,actions in cases:
            tags=evidence.tags_from_observations({'segments':[{'start':0,'end':6,'summary':summary,'tags':['cyclists','car','trees']}]})
            self.assertEqual([t['key'] for t in tags if t['category']=='subject'], subjects)
            self.assertEqual([t['key'] for t in tags if t['category']=='activity'], actions)

    def test_separate_scenes_do_not_make_coprimary_subjects(self):
        windows=[self.window([self.focus()],0,6), self.window([self.focus('vehicles',None)],6,12)]
        self.assertEqual(evidence.primary_subject_keys({'segments':windows}), ['people'])

    def test_shared_focus_requires_sustained_overlap_not_a_tiny_tail(self):
        pair=[self.focus(),self.focus('animals',None)]
        self.assertEqual(evidence.primary_subject_keys({'segments':[self.window(pair)]}), ['people','animals'])
        self.assertEqual(evidence.primary_subject_keys({'segments':[self.window([pair[0]]),self.window(pair,6,6.05)]}), ['people'])

    def test_duplicate_windows_do_not_outvote_longer_focus(self):
        short=self.window([self.focus()],0,2)
        long=self.window([self.focus('landscape',None)],2,10)
        self.assertEqual(evidence.primary_subject_keys({'segments':[short]*10+[long]}), ['landscape'])

    def test_still_photo_has_focus_without_fake_video_duration(self):
        window={**self.window([self.focus('buildings',None)],0,0),'kind':'image'}
        self.assertEqual(evidence.primary_subject_keys({'segments':[window]}), ['buildings'])
        self.assertEqual(window['end'],0)

    def test_strict_focus_gets_one_repair_then_abstains(self):
        calls=[]
        def ask(prompt):
            calls.append(prompt)
            return {'summary':'A child walks.', 'tags':['child'], 'primary_subjects':[{'category':'people','reason':'Visible'}]}
        result=evidence.read_observation(ask,evidence.SUBJECT_PROMPT,require_focus=True)
        self.assertEqual(len(calls),2)
        self.assertEqual(result['focusVersion'],2)
        self.assertIsNone(result['primary_subjects'])
        self.assertEqual(result['summary'],'A child walks.')

    def test_prose_receives_focus_and_respects_user_override(self):
        tags=evidence.tags_from_observations({'segments':[self.window([self.focus()])]})
        item={'analysisEvidence':{'tags':tags}}
        context=evidence.description_focus(item)
        self.assertEqual(context['subjects'][0]['category'],'people')
        self.assertEqual(context['activities'][0]['category'],'walking')
        item['tagCorrections']=evidence.validate_corrections({'added':[{'category':'subject','label':'Buildings'}]})
        context=evidence.description_focus(item)
        self.assertEqual([t['category'] for t in context['subjects']],['buildings'])
        self.assertEqual(context['activities'],[])

    def test_malformed_actions_do_not_become_activity_tags(self):
        for actions in ([{'category':'cycling'}], ['walking'], [{'category':'flying','reason':'Visible'}], [{'category':{},'reason':'Visible'}], [{'category':'walking','reason':'Maybe moving'}]):
            focus={**self.focus(), 'activities':actions}
            self.assertIsNone(evidence.normalized_primary_subjects([focus],strict=True))
        self.assertIsNone(evidence.normalized_primary_subjects([{**self.focus(),'category':[]}],strict=True))

    def test_ocr_kept_separate_from_subtitles_and_visual_tags(self):
        result=evidence.observation_evidence({'segments':[{'start':2,'end':8,'tags':['河流'], 'facts':{'ocr':[{'text':'出口','confidence':.9},{'text':'出口','confidence':.9},{'text':'Uncertain','confidence':.1}]}}]})
        self.assertEqual(result['onScreenText'],[{'text':'出口','confidence':.9,'start':2,'end':8}])
        self.assertNotIn('subtitleCues',result)
        self.assertEqual(result['tags'][0]['id'],'scene:water')
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)/'test.mov'; self.path.write_bytes(b'fixture')
    def tearDown(self): self.tmp.cleanup()
    def test_stable_shot_identity_and_source_change(self):
        ident = evidence.shot_id(self.path,0,2)
        self.assertEqual(ident,evidence.shot_id(self.path,0.,2.))
        self.assertNotEqual(ident,evidence.shot_id(self.path,0,3))
        self.path.write_bytes(b'new fixture')
        self.assertNotEqual(ident,evidence.shot_id(self.path,0,2))
    def test_geometry_revision_not_description_revision(self):
        shots=[{'id':'one','start':0,'end':2,'label':'Old'}]
        old=evidence.shot_revision(shots)
        shots[0]['label']='Edited description'
        self.assertEqual(old,evidence.shot_revision(shots))
        shots[0]['end']=3
        self.assertNotEqual(old,evidence.shot_revision(shots))
    def test_stale_source_not_used_as_canonical(self):
        item={'shotAnalysis':{'revision':'rev','sourceStamp':evidence.source_stamp(self.path),
                              'segments':[{'id':'one','start':0,'end':2}]}}
        self.assertEqual(len(evidence.canonical_shots(item,self.path)),1)
        self.path.write_bytes(b'changed')
        self.assertEqual(evidence.canonical_shots(item,self.path),[])
    def test_offline_original_keeps_saved_canonical_reference(self):
        item={'shotAnalysis':{'revision':'rev','sourceStamp':evidence.source_stamp(self.path),'segments':[{'id':'one'}]}}
        self.path.unlink()
        self.assertEqual(len(evidence.canonical_shots(item,self.path)),1)
    def test_multiple_subjects_and_time_provenance(self):
        result={'segments':[{'start':1,'end':5,'tags':['river','two people','cars','river'], 'primary_subjects':[
            {'category':'people','reason':'Camera follows the pair'}, {'category':'vehicles','reason':'The car occupies the other half throughout'}]}]}
        tags=evidence.tags_from_observations(result,[{'id':'a','start':0,'end':3},{'id':'b','start':3,'end':6}])
        by_id={t['id']:t for t in tags}
        self.assertTrue({'scene:water','subject:people','subject:vehicles'} <= set(by_id))
        ref=by_id['scene:water']['evidence']
        self.assertEqual(ref,[{'start':1,'end':5,'shotIds':['a','b'],'text':'river'}])
        self.assertIn('河流',by_id['scene:water']['aliases'])
    def test_unknown_and_negated_subjects_not_promoted(self):
        tags=evidence.tags_from_observations({'segments':[{'start':0,'end':0,'tags':['no people','possibly mountain','未知',None,'stone wall']}]})
        self.assertEqual([t['id'] for t in tags],['detail:stone wall'])
    def test_background_objects_remain_searchable_but_not_subjects(self):
        result={'segments':[{'start':0,'end':10,'summary':'A woman walks; trees and a car are behind her.',
            'tags':['woman','trees','car'],'primary_subjects':[{'category':'people','reason':'Camera follows the woman throughout'}]}]}
        tags=evidence.tags_from_observations(result)
        self.assertEqual([t['key'] for t in tags if t['category']=='subject'],['people'])
        self.assertTrue({'detail:trees','detail:car'} <= {t['id'] for t in tags})
    def test_legacy_background_does_not_override_filming_focus(self):
        result={'segments':[{'start':0,'end':10,'summary':'镜头聚焦喷泉，背景是树木与行人。','tags':['喷泉','树木','行人']}]}
        self.assertEqual([t['key'] for t in evidence.tags_from_observations(result) if t['category']=='subject'],['buildings'])
    def test_primary_subjects_are_bounded_and_allow_scenery(self):
        value=[{'category':k,'reason':'Clearly framed throughout'} for k in ('landscape','buildings','people')]
        self.assertEqual(len(evidence.normalized_primary_subjects(value)),2)
        result={'segments':[{'start':0,'end':8,'tags':['sunset','small people','trees'],
            'primary_subjects':[{'category':'landscape','reason':'Sunset fills the frame'}]}]}
        self.assertEqual([t['key'] for t in evidence.tags_from_observations(result) if t['category']=='subject'],['landscape'])
    def test_raw_metrics_do_not_become_aesthetic_or_project_scores(self):
        shot={'importance_score':82,'edit_recommendation':{'reason':'Opening'}}
        result=evidence.assessments(shot,[{'facts':{'quality':[{'sharp_all':10,'clip_hi':.2},{'sharp_all':30,'mean_L':float('nan')}]}}])
        self.assertEqual(result['editorial']['value'],82)
        self.assertEqual(result['technical']['metrics'][0],{'key':'sharp_all','value':20,'samples':2})
        self.assertEqual(result['aesthetic'],{'status':'not_evaluated'})
        self.assertEqual(result['projectRelevance'],{'status':'not_evaluated'})
    def test_subject_schema_retries_once_then_preserves_visual_evidence(self):
        calls=[]
        def ask(prompt):
            calls.append(prompt)
            return {'summary':'A man walks. Trees in the background.', 'tags':['man','trees'], 'primary_subjects':['man']}
        value=evidence.read_observation(ask,evidence.SUBJECT_PROMPT)
        self.assertEqual(len(calls),2)
        self.assertIsNone(value['primary_subjects'])
        self.assertEqual([t['key'] for t in evidence.tags_from_observations({'segments':[{'start':0,'end':6,**value}]}) if t['category']=='subject'],['people'])
    def test_schema_repair_accepts_explicit_focus_and_negative_background_reason(self):
        good={'summary':'A woman walks.', 'tags':['woman'], 'primary_subjects':[{'category':'people','reason':'Camera follows her, not the background trees'}]}
        calls=[]
        def ask(prompt):
            calls.append(prompt)
            return {'category':'people'} if len(calls)==1 else good
        self.assertEqual(evidence.read_observation(ask,''),good)
        self.assertEqual(len(calls),2)
    def test_short_clip_main_clause_does_not_require_inventory_tags(self):
        tags=evidence.tags_from_observations({'segments':[{'start':0,'end':3,'summary':'A fountain fills the view. Trees in the background.','tags':[]}]})
        self.assertEqual([t['key'] for t in tags if t['category']=='subject'],['buildings'])
        tags=evidence.tags_from_observations({'segments':[{'start':0,'end':3,'summary':'No people are visible.','tags':[]}]})
        self.assertEqual(tags,[])
    def test_missing_metrics_are_unavailable_not_zero(self):
        result=evidence.assessments({'importance_score':40,'edit_recommendation':{'reason':'Context'}},[])
        self.assertEqual(result['technical']['status'],'unavailable')
        self.assertEqual(result['technical']['metrics'],[])
    def test_user_corrections_scoped_and_canonical(self):
        result=evidence.validate_corrections({'hidden':['subject:people'], 'added':[{'category':'scene','label':' Lakes & rivers '}]})
        self.assertEqual(result['added'][0]['id'],'scene:water')
        self.assertEqual(result['added'][0]['source'],'user')
        self.assertEqual(result['added'][0]['evidence'],[])
        for payload in ({'added':[{'category':'location','label':'Guessed place'}]}, {'hidden':'all'}, {'added':[{'category':'scene','label':'x'*49}]}):
            with self.assertRaises(ValueError): evidence.validate_corrections(payload)


if __name__=='__main__': unittest.main()
