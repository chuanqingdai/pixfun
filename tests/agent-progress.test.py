"""Durable intermediate progress; fixture models and isolated media storage."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('agent_tests', ROOT / 'tests/agent.test.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
from agent_engine import record_progress_update, observation_tags


class ProgressTests(unittest.TestCase):
    setUp = base.AgentTests.setUp
    tearDown = base.AgentTests.tearDown
    start = base.AgentTests.start

    def test_search_tags_reuse_observed_evidence_only(self):
        observed = {'segments': [{'summary': 'A guessed place must not become a tag',
            'tags': [' Lake ', 'lake', 'Walking', None, 'unknown', 'x' * 60]}, {'tags': 'not a tag array'}]}
        self.assertEqual(observation_tags(observed), ['Lake', 'Walking'])
        self.assertEqual(observation_tags({'segments': []}), [])
        self.assertEqual(len(observation_tags({'segments': [{'tags': ['tag ' + str(i) for i in range(50)]}]})), 24)

    def test_analysis_preserves_ordered_steps_and_material(self):
        run = base.wait(self.agent, self.start()['id'])
        self.assertEqual(run['status'], 'completed', run['message'])
        updates = run['progressUpdates']
        stages = [u['stage'] for u in updates if u['kind'] == 'stage']
        self.assertEqual(stages, ['intent', 'understand', 'report'])
        media = [u for u in updates if u['kind'] == 'media']
        self.assertEqual([u['mediaId'] for u in media], [self.asset])
        self.assertLess(updates.index(media[0]), next(i for i, u in enumerate(updates) if u.get('stage') == 'report'))
        self.assertEqual(self.agent.get(run['id'])['progressUpdates'], updates)

    def test_older_snapshot_cannot_erase_live_progress(self):
        run = base.wait(self.agent, self.start()['id'])
        run['status'] = 'running'
        self.agent.save(run)
        self.agent.progress(run['id'], 'Checking the finished video', 'render')
        self.agent.save(run)
        self.assertEqual(self.agent.get(run['id'])['progressUpdates'][-1]['stage'], 'verify')

    def test_repeated_windows_do_not_flood_the_conversation(self):
        run = {}
        for _ in range(5):
            record_progress_update(run, 'stage', 'understand')
            record_progress_update(run, 'media', self.asset)
        self.assertEqual(len(run['progressUpdates']), 2)
        record_progress_update(run, 'stage', 'plan')
        record_progress_update(run, 'stage', 'understand')
        self.assertEqual(len(run['progressUpdates']), 4, 'a real later retry is preserved')


if __name__ == '__main__': unittest.main()
