"""Read-only host + real VisionFlow CPU editor assistance; no inference."""
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
TEMP = tempfile.TemporaryDirectory(prefix='pixfun-editor-test-')
os.environ['PIXFUN_DATA_DIR'] = TEMP.name
from agent_models import ModelGateway
from agent_editor import assist, source_revision
from shot_analysis import analysis_signature


class EditorAssistTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pixfun-editor-assist-')
        self.root = Path(self.temp.name)
        self.gateway = ModelGateway(self.root)
        if not self.gateway.capabilities().get('localStory'):
            self.temp.cleanup(); self.skipTest('VisionFlow runtime unavailable')
        # Source contents need not decode: assistance reads only cached evidence.
        self.paths = {mid: self.root/(mid+'.mp4') for mid in ('a', 'b', 'c')}
        for path in self.paths.values(): path.write_bytes(b'test-source')
        self.records = {mid: dict(id=mid, kind='video', status='ready', file={'name':mid}, metadata={'duration':60}) for mid in self.paths}
        self.shots = [dict(id='one', mediaId='a', start=0, end=4, label='River landscape', reason='Establish the river', locked=False, section='body')]
        self.run = dict(id='f'*32, version=1, status='completed', mediaIds=list(self.paths), timeline=self.shots, mode='local')
        self.engine = SimpleNamespace(models=self.gateway, get=lambda key: copy.deepcopy(self.run),
            library=SimpleNamespace(get=lambda mid: (copy.deepcopy(self.records[mid]), self.paths[mid])))
        for mid in self.records:
            self.records[mid]['shotAnalysis'] = dict(status='ready', segments=[dict(start=0, end=4, editorial={'description':'River landscape', 'story_role':['Establishing']}),
                dict(start=12, end=22, editorial={'description':'River landscape with trees', 'story_role':['Establishing']})],
                signature=analysis_signature(self.engine, self.records[mid], self.paths[mid], 'local'))

    def tearDown(self):
        self.gateway.close(); self.temp.cleanup()

    def call(self, action='replace', **kw):
        return assist(self.engine, dict(id=self.run['id'], version=1, action=action, shots=self.shots, shotId='one', **kw))

    def test_recommendations_exact_duration_nonzero_range_and_no_mutation(self):
        before = json.dumps(self.run, sort_keys=True)
        result = self.call()
        self.assertTrue(1 <= len(result['recommendations']) <= 3)
        self.assertTrue(any(c['mediaId']=='a' and c['start'] >= 12 for c in result['recommendations']))
        for c in result['recommendations']:
            self.assertEqual(c['end']-c['start'], 4)
            self.assertEqual(c['revision'], source_revision(self.paths[c['mediaId']]))
        self.assertEqual(json.dumps(self.run, sort_keys=True), before)
        self.assertIsNone(self.gateway.process)

    def test_used_ranges_and_unusable_candidates_are_not_recommended(self):
        self.shots.append(dict(self.shots[0], id='two', mediaId='b', start=0, end=60))
        for s in self.records['c']['shotAnalysis']['segments']: s['editorial']['unusable_candidate'] = True
        result = self.call()
        self.assertTrue(result['recommendations'])
        self.assertEqual({c['mediaId'] for c in result['recommendations']}, {'a'})

    def test_no_cache_does_not_invent_recommendations(self):
        for r in self.records.values(): r.pop('shotAnalysis')
        self.assertEqual(self.call()['recommendations'], [])

    def test_stale_cache_is_not_used(self):
        for path in self.paths.values(): path.write_bytes(b'changed-source')
        self.assertEqual(self.call()['recommendations'], [])

    def test_short_and_invalid_ranges_are_not_extended(self):
        for r in self.records.values():
            r['shotAnalysis']['segments'] = [dict(start=10, end=12, editorial={'description':'River landscape'}),
                dict(start=59, end=65, editorial={'description':'River landscape'})]
        self.assertEqual(self.call()['recommendations'], [])

    def test_rules_are_advisory_and_follow_current_draft(self):
        shots = [dict(self.shots[0], end=25), dict(self.shots[0], id='two', start=20, end=28)]
        result = assist(self.engine, dict(id=self.run['id'], version=1, action='review', shots=shots))
        self.assertEqual({i['kind'] for i in result['issues']}, {'long_hold', 'repeated_source'})
        self.assertEqual(self.run['timeline'], self.shots)
        self.assertEqual(self.call('review')['issues'], [])
        self.assertIsNone(self.gateway.process)

    def test_apply_rechecks_source_revision(self):
        c = self.call()['recommendations'][0]
        self.assertTrue(self.call('validate', candidate=c)['ok'])
        self.paths[c['mediaId']].write_bytes(b'changed-after-menu-opened')
        with self.assertRaisesRegex(ValueError, 'source changed'): self.call('validate', candidate=c)

    def test_lock_version_and_scope_guards(self):
        self.run['version'] = 2
        with self.assertRaisesRegex(ValueError, 'timeline changed'): self.call()
        self.run['version'] = 1; self.shots[0]['locked'] = True
        with self.assertRaisesRegex(ValueError, 'unlocked'): self.call()
        self.shots[0]['locked'] = False
        with self.assertRaisesRegex(ValueError, 'unavailable'): self.call('validate', candidate={'mediaId':'outside'})

    def test_photo_replacement_preserves_hold_without_seek(self):
        self.records['b'].update(kind='image', description='River landscape')
        result = self.call()
        photo = next(c for c in result['recommendations'] if c['mediaId']=='b')
        self.assertEqual((photo['start'], photo['end']), (0,4))
        self.assertTrue(self.call('validate', candidate=photo)['ok'])

    def test_chinese_evidence_and_recommendation_diversity(self):
        self.shots[0].update(label='湖边行走', reason='交代湖边环境')
        for r in self.records.values():
            for s in r['shotAnalysis']['segments']:
                s['editorial'].update(description='人物沿湖边小路行走', story_role=[])
        result = self.call()['recommendations']
        self.assertEqual({c['mediaId'] for c in result}, {'a','b','c'})

    def test_validation_cannot_change_duration_or_seek_photo(self):
        c = self.call()['recommendations'][0]
        with self.assertRaisesRegex(ValueError, 'duration'):
            self.call('validate', candidate={**c, 'end':c['end']+1})
        self.records[c['mediaId']]['kind'] = 'image'
        with self.assertRaisesRegex(ValueError, 'duration'):
            self.call('validate', candidate={**c, 'start':1, 'end':5})

    def speech(self, cues, state='transcribed'):
        path = self.paths['a']; stat = path.stat()
        signature = hashlib.sha256(f'{path}:{stat.st_size}:{stat.st_mtime_ns}:speech:{self.gateway.speech}'.encode()).hexdigest()
        self.records['a']['result'] = {'analysis':dict(subtitleState=state, subtitleSource='local-asr', subtitleSignature=signature, subtitleCues=cues)}

    def test_speech_boundaries_join_unfinished_cues_without_inventing_word_times(self):
        self.speech([dict(start=1, end=2, text='我们沿着'), dict(start=2, end=3.2, text='小路前行。'), dict(start=4, end=6, text='停下来。看看湖面。')])
        guide = self.call('trim')['speech']
        self.assertEqual([(b['edge'], b['time']) for b in guide['boundaries']], [('start',1),('end',3.2),('start',4),('end',6)])
        self.assertEqual(guide['kind'], 'asr')
        self.assertIn('小路', guide['boundaries'][0]['text'])
        self.assertIsNone(self.gateway.process)
        self.assertEqual(self.shots[0]['end'], 4)

    def test_speech_missing_stale_or_silent_has_no_guidance(self):
        self.assertIsNone(self.call('trim')['speech'])
        self.speech([dict(start=1, end=3, text='A sentence.')])
        self.paths['a'].write_bytes(b'changed')
        self.assertIsNone(self.call('trim')['speech'])
        self.speech([dict(start=1, end=3, text='A sentence.')])
        self.records['a']['metadata']['hasAudio'] = False
        self.assertIsNone(self.call('trim')['speech'])

    def test_speech_ambiguous_and_invalid_cues_are_not_cut_points(self):
        self.speech([dict(start=1, end=3, text='First.'), dict(start=2, end=4, text='Overlapping.'),
            dict(start=10, end=11, text='[Music]'), dict(start=12, end=13, text='Proxy.', time_domain='catalog_proxy'),
            dict(start=20, end=70, text='Outside source.'), dict(start=30, end=31, text='Keep this.')], 'partial')
        marks = self.call('trim')['speech']['boundaries']
        self.assertEqual([m['time'] for m in marks], [30,31])

    def test_speech_apply_rechecks_transcript_and_source(self):
        self.speech([dict(start=1, end=3, text='Sentence.')])
        guide = self.call('trim')['speech']; candidate = {**guide, **guide['boundaries'][0]}
        self.assertTrue(self.call('validate-trim', candidate=candidate)['ok'])
        self.speech([dict(start=1.2, end=3, text='Sentence.')])
        with self.assertRaisesRegex(ValueError, 'Speech timing changed'):
            self.call('validate-trim', candidate=candidate)

    def test_sidecar_times_are_current_and_bound_to_original(self):
        path = self.paths['a']; stat = path.stat()
        self.records['a']['file'].update(size=stat.st_size, lastModified=int(stat.st_mtime*1000))
        self.records['a']['result'] = {'analysis':dict(subtitleState='sidecar', subtitleCues=[dict(start=50,end=51,text='Old caption.')])}
        sidecar = path.with_suffix('.srt'); sidecar.write_text('1\n00:00:01,000 --> 00:00:03,000\nCurrent caption.\n', encoding='utf-8')
        guide = self.call('trim')['speech']
        self.assertEqual(guide['kind'], 'subtitle')
        self.assertEqual([b['time'] for b in guide['boundaries']], [1,3])
        candidate = {**guide, **guide['boundaries'][0]}
        sidecar.write_text('1\n00:00:02,000 --> 00:00:03,000\nEdited caption.\n', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'Speech timing changed'): self.call('validate-trim', candidate=candidate)
        sidecar.unlink()
        self.assertIsNone(self.call('trim')['speech'])

    def test_speech_does_not_guess_missing_ends_or_cut_long_unpunctuated_blocks(self):
        self.speech([dict(start=0, end=36, text='Unpunctuated block'), dict(start=40, text='No end')])
        self.assertEqual(self.call('trim')['speech']['boundaries'], [])


if __name__ == '__main__': unittest.main()
