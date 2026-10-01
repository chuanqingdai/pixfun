"""Real offline inference + deterministic grouping rules; no production database writes."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from local_people import PeopleEngine, choose_group, subject_eligible


class PeopleTests(unittest.TestCase):
    def test_transient_and_small_faces_are_suppressed(self):
        self.assertFalse(subject_eligible([{'time': 0, 'area': .1, 'central': True}]))
        self.assertFalse(subject_eligible([{'time': t, 'area': .001, 'central': True} for t in [0, 3, 6, 9]]))
        self.assertTrue(subject_eligible([{'time': t, 'area': .02, 'central': True} for t in [0, 3, 6]]))
        self.assertFalse(subject_eligible([{'time': 0, 'area': .05, 'central': False}], photo=True))
        self.assertTrue(subject_eligible([{'time': 0, 'area': .05, 'central': True}], photo=True))

    def test_ambiguous_and_simultaneous_people_never_merge(self):
        self.assertEqual(choose_group({'a': .8, 'b': .6}, set()), 'a')
        self.assertIsNone(choose_group({'a': .8, 'b': .75}, set()))
        self.assertIsNone(choose_group({'a': .54}, set()))
        self.assertIsNone(choose_group({'a': .8}, {'a'}))

    def test_real_models_group_same_person_across_assets_and_cache(self):
        import cv2 as cv
        cv.setNumThreads(2)
        source = ROOT / 'public/media/travel/creator-cafe.jpg'
        original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory(prefix='pixfun-people-test-') as directory:
            directory = Path(directory)
            variant = directory / 'variant.jpg'
            cv.imwrite(str(variant), cv.convertScaleAbs(cv.imread(str(source)), alpha=.96, beta=4))
            records = [{'id': 'one', 'kind': 'image', 'file': {'name': source.name}}, {'id': 'two', 'kind': 'image', 'file': {'name': variant.name}}]
            class Library:
                def __init__(self): self.directory = directory
                def list(self): return records
                def get(self, key): return next(x for x in records if x['id'] == key), (source if key == 'one' else variant)
            engine = PeopleEngine(Library(), ROOT / 'build-desktop/people-models')
            engine.run(records)
            result = engine.snapshot()
            self.assertEqual(result['state'], 'complete', result['errors'])
            self.assertTrue(any(set(p['mediaIDs']) == {'one', 'two'} for p in result['people']), result)
            self.assertNotIn('anchor', json.dumps(result))
            ids = [p['id'] for p in result['people']]
            engine.run(records)
            self.assertEqual([p['id'] for p in engine.snapshot()['people']], ids)
            engine.pool.shutdown()
            reopened = PeopleEngine(Library(), ROOT / 'build-desktop/people-models')
            self.assertEqual([p['id'] for p in reopened.snapshot()['people']], ids)
            reopened.pool.shutdown()
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), original_hash)

    def test_corrupt_cache_is_preserved(self):
        with tempfile.TemporaryDirectory(prefix='pixfun-people-damaged-') as directory:
            root = Path(directory); (root / 'people').mkdir()
            file = root / 'people/analysis.json'; file.write_text('broken')
            class Library:
                def __init__(self): self.directory = root
                def list(self): return []
            engine = PeopleEngine(Library(), ROOT / 'build-desktop/people-models')
            with self.assertRaises(ValueError): engine.start()
            self.assertEqual(file.read_text(), 'broken')
            engine.pool.shutdown()


if __name__ == '__main__': unittest.main()
