"""Real installed VisionFlow compiler through the production CPU worker; no MLX."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from agent_models import ModelGateway, AgentCancelled, CapabilityMissing, LocalWorkerError
from scripts.vf_story import validate_beats, normalize_beats, section_beats


class StoryEngineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pixfun-story-engine-')
        self.folder = Path(self.temp.name)
        self.gateway = ModelGateway(self.folder)
        if not self.gateway.capabilities().get('localStory'):
            self.temp.cleanup()
            self.skipTest('Installed VisionFlow 0.9.1 runtime unavailable')
        self.cancel = threading.Event()
        self.photo = ROOT/'public/images/pixfun-lockup-v2.png'
        self.video = ROOT/'native/Examples/wild-alaska/wild-alaska.mp4'
        self.context = self.gateway.story(dict(action='context', sources=[
            dict(mediaId='p', path=str(self.photo), kind='image', description='Brand illustration'),
            dict(mediaId='v', path=str(self.video), kind='video', duration=10, description='Wildlife footage')],
            transcripts=[dict(mediaId='v', start=1, end=2, text='Unverified speech')]), self.cancel)
        self.shots = [dict(id='one', mediaId='p', start=0, end=1.5, label='Opening', reason='Establish theme', locked=True, section='body'),
                      dict(id='two', mediaId='v', start=1, end=4, label='Event', reason='Show action', section='body')]

    def tearDown(self):
        self.gateway.close()
        self.temp.cleanup()

    def compile(self, **overrides):
        job = dict(action='compile', context=self.context, shots=self.shots,
                   project='test-story', folder=str(self.folder/'story'), request='A concise story', summary='Theme then action',
                   sourceAudio={'v':True}, requiredMediaIds=['p', 'v'],
                   beats=[dict(first=0, title='Opening', intent='Establish', bridge='Then action'),
                          dict(first=1, title='Event', intent='Action', bridge='')])
        return self.gateway.story({**job, **overrides}, self.cancel)

    def test_real_engine_handoff_and_compilation_without_model(self):
        self.gateway.vision = ''
        self.assertIsNone(self.gateway.process)
        self.assertIn('每个镜头', self.context['guidance'])
        speech = next(i for i in self.context['hints']['items'] if i['origin'] == 'indexed_asr')
        self.assertEqual(speech['trust'], 'machine_unreviewed')
        result = self.compile()
        self.assertEqual(result['timeline'], self.shots)
        self.assertEqual(result['chapters'], 2)
        plan = json.loads(Path(result['path']).read_text())
        self.assertEqual(plan['status'], 'new_story_pending_review')
        self.assertEqual(plan['beats'][1]['timeline_start'], 1.5)
        self.assertEqual(plan['beats'][1]['clips'][0]['source_range'], [1, 4])
        self.assertEqual(result['summary'], plan['logline'])
        self.assertEqual(result['outline'][0], dict(id=plan['beats'][0]['id'], title='Opening',
                         intent='Establish', bridge='Then action', shotIds=['one']))
        self.assertEqual(result['outline'][1]['shotIds'], ['two'])
        self.assertEqual(result['sourceNames']['v'], self.video.name)
        self.assertEqual(result['sourceKinds']['p'], 'photo')
        self.assertTrue(all(c['status'] == 'covered' for c in result['coverage']))
        self.assertEqual(result['qc']['aesthetic_review'], 'not_run')
        self.assertEqual(self.gateway.observations['story'], 'verified')
        self.assertIsNone(self.gateway.process)

    def test_no_beats_preserves_short_photo_and_locked_shot(self):
        self.assertEqual(self.compile(beats=None)['timeline'], self.shots)

    def test_recovered_chapters_compile_without_changing_sources_or_cuts(self):
        for beats in (normalize_beats([dict(first=1, title='Opening'), dict(first=2, title='Event')], 2),
                      section_beats(self.shots)):
            result = self.compile(beats=beats)
            self.assertEqual(result['timeline'], self.shots)
            self.assertEqual([sid for b in result['outline'] for sid in b['shotIds']], ['one', 'two'])

    def test_duplicate_names_use_exact_media_ids(self):
        # Engine names use unique library IDs, not user filenames.
        context = copy.deepcopy(self.context)
        context['records'][1]['source'] = context['records'][0]['source']
        context['records'][1]['source_fingerprint'] = context['records'][0]['source_fingerprint']
        context['records'][1]['kind'] = 'photo'
        shots = [self.shots[0], dict(self.shots[1], start=0, end=2)]
        self.assertEqual(self.compile(context=context, shots=shots)['timeline'], shots)

    def test_changed_source_is_rejected(self):
        context = copy.deepcopy(self.context)
        context['records'][0]['source_fingerprint'][1] += 1
        with self.assertRaisesRegex(LocalWorkerError, 'changed'):
            self.compile(context=context)
        self.assertFalse((self.folder/'story/story.json').exists())

    def test_out_of_range_is_rejected(self):
        shots = [self.shots[0], dict(self.shots[1], end=11)]
        with self.assertRaisesRegex(LocalWorkerError, 'outside source'):
            self.compile(shots=shots)

    def test_missing_required_source_is_rejected(self):
        with self.assertRaisesRegex(LocalWorkerError, 'anchors missing'):
            self.compile(requiredMediaIds=['absent'])

    def test_rule_flags_do_not_block_story(self):
        result = self.compile(shots=[dict(self.shots[0], end=25), self.shots[1]])
        self.assertEqual(result['qc']['issues'][0]['kind'], 'long_hold')
        self.assertTrue(Path(result['path']).exists())

    def test_cancellation_does_not_start_model(self):
        self.cancel.set()
        with self.assertRaises(AgentCancelled): self.compile()
        self.assertIsNone(self.gateway.process)

    def test_missing_adapter_is_not_reported_connected(self):
        with patch.object(self.gateway, 'worker', str(self.folder/'agent-model-worker.py')):
            self.assertFalse(self.gateway.capabilities()['localStory'])
            with self.assertRaises(CapabilityMissing): self.compile()

    def test_invalid_chapters_are_rejected(self):
        for beats in ([], [{'first':True}], [{'first':1}], [{'first':0}, {'first':0}], [{'first':0}, {'first':2}]):
            with self.subTest(beats=beats), self.assertRaises(ValueError): validate_beats(beats, 2)


class ChapterBoundaryTests(unittest.TestCase):
    def test_one_based_conversion_preserves_metadata_and_input(self):
        original = [dict(first=1, title='A', intent='Theme'), dict(first=3, title='B', bridge='End')]
        self.assertEqual([b['first'] for b in normalize_beats(original, 4)], [0, 2])
        self.assertEqual(original[0]['first'], 1)
        self.assertEqual(normalize_beats(original, 4)[1]['bridge'], 'End')
        zero = [dict(first=0), dict(first=2)]
        self.assertEqual(normalize_beats(zero, 4), zero)

    def test_ambiguous_or_invalid_boundaries_are_not_silently_reordered(self):
        for beats in ([], [{'first':True}], [{'first':'1'}], [{'first':2}], [{'first':0}, {'first':0}],
                      [{'first':1}, {'first':1}], [{'first':1}, {'first':5}], [{'first':0}, {'first':4}]):
            with self.subTest(beats=beats), self.assertRaises(ValueError): normalize_beats(beats, 4)

    def test_fallback_preserves_every_contiguous_section(self):
        shots = [dict(section=s, label=str(i), reason='Existing reason') for i, s in enumerate(['intro','body','body','outro'])]
        beats = section_beats(shots)
        validate_beats(beats, len(shots))
        self.assertEqual([b['first'] for b in beats], [0, 1, 3])
        self.assertEqual(beats[1]['intent'], 'Existing reason')


if __name__ == '__main__': unittest.main()
