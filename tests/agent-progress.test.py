"""Durable intermediate progress; fixture models and isolated media storage."""
import importlib.util
from pathlib import Path
import unittest
import threading
import shutil
from unittest.mock import patch

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
        self.assertEqual(stages, ['intent', 'highlights', 'understand', 'transcribe', 'report'])
        media = [u for u in updates if u['kind'] == 'media']
        self.assertEqual([u['mediaId'] for u in media], [self.asset])
        self.assertLess(updates.index(media[0]), next(i for i, u in enumerate(updates) if u.get('stage') == 'report'))
        self.assertEqual(self.agent.get(run['id'])['progressUpdates'], updates)
        self.assertEqual([(row['mediaId'], row['status']) for row in run['materialProgress']], [(self.asset, 'completed')])

    def test_partial_findings_are_running_until_the_material_finishes(self):
        entered, release = threading.Event(), threading.Event()
        understand = self.agent.understand
        def blocked(run, media_id, cancel):
            record, result = understand(run, media_id, cancel)
            entered.set()
            release.wait(10)
            return record, result
        with patch.object(self.agent, 'understand', side_effect=blocked):
            run = self.start()
            try:
                self.assertTrue(entered.wait(15))
                live = self.agent.get(run['id'])
                self.assertEqual(live['materialProgress'][0]['status'], 'running')
                self.assertTrue(any(a.get('mediaId') == self.asset for a in live['artifacts']))
            finally:
                release.set()
            finished = base.wait(self.agent, run['id'])
        self.assertEqual(finished['materialProgress'][0]['status'], 'completed')

    def test_failure_marks_current_material_and_retry_completes_it(self):
        with patch.object(self.agent, 'understand', side_effect=RuntimeError('Fixture analysis failure')):
            run = base.wait(self.agent, self.start()['id'])
        self.assertEqual(run['status'], 'failed')
        self.assertEqual(run['materialProgress'][0]['status'], 'failed')
        future = self.agent.futures.get(run['id'])
        if future: future.result(timeout=10)
        finished = base.wait(self.agent, self.agent.action({'id': run['id'], 'action': 'retry'})['id'])
        self.assertEqual(finished['status'], 'completed', finished['message'])
        self.assertEqual(finished['materialProgress'][0]['status'], 'completed')

    def test_multi_file_failure_keeps_completed_and_waiting_files_distinct(self):
        paths = [Path(self.temp.name) / name for name in ('second.mp4', 'third.mp4')]
        for path in paths: shutil.copyfile(ROOT / 'qa/media-library/captioned-test.mp4', path)
        added = self.library.register([str(path) for path in paths])['items']
        ids = [self.asset] + [item['id'] for item in added]
        understand = self.agent.understand
        def fail_second(run, media_id, cancel):
            if media_id == ids[1]: raise RuntimeError('Second material failed')
            return understand(run, media_id, cancel)
        with patch.object(self.agent, 'understand', side_effect=fail_second):
            run = base.wait(self.agent, self.start(mediaIds=ids)['id'])
        self.assertEqual(run['status'], 'failed')
        self.assertEqual([row['mediaId'] for row in run['materialProgress']], ids)
        self.assertEqual([row['status'] for row in run['materialProgress']], ['completed', 'failed', 'pending'])

    def test_stale_snapshot_and_terminal_status_preserve_material_states(self):
        run = base.wait(self.agent, self.start()['id'])
        run['status'] = 'running'
        self.agent.save(run)
        self.agent.material_progress(run['id'], self.asset, 'running')
        stale = self.agent.get(run['id'])
        self.agent.material_progress(run['id'], self.asset, 'completed')
        self.agent.save(stale)
        self.assertEqual(self.agent.get(run['id'])['materialProgress'][0]['status'], 'completed')
        self.agent.material_progress(run['id'], self.asset, 'running')
        stopped = self.agent.get(run['id'])
        stopped['status'] = 'interrupted'
        self.agent.save(stopped)
        self.assertEqual(self.agent.get(run['id'])['materialProgress'][0]['status'], 'paused')

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
