"""Isolated resource/worker regressions. No real models or personal media."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from analysis_resources import AnalysisResources, prepared_windows, memory_snapshot
from agent_models import AgentCancelled, ModelGateway, LocalWorkerError, retryable_analysis_error, worker_response_error

HEALTHY = {'total':32*1024**3, 'available':12*1024**3, 'pressure':1}


class ResourcesTests(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.sample = dict(HEALTHY)
        self.resources = AnalysisResources(lambda:self.sample, lambda:self.now)
        self.cancel = threading.Event()

    def tearDown(self): self.resources.shutdown()

    def healthy(self):
        self.resources.status()
        self.now += 11
        self.assertEqual(self.resources.status()['preprocessingLimit'], 2)

    def test_pressure_headroom_unknown_and_recovery_hysteresis(self):
        self.assertTrue(self.resources.status()['serial'])
        self.healthy()
        for sample in ({**HEALTHY, 'pressure':2}, {**HEALTHY, 'pressure':4},
                       {**HEALTHY, 'available':1024**3}, {**HEALTHY, 'total':8*1024**3}, None):
            self.now += 2; self.sample = sample
            self.assertTrue(self.resources.status()['serial'])
        self.sample = dict(HEALTHY); self.now += 2
        self.assertTrue(self.resources.status()['serial'])
        self.now += 11
        self.assertFalse(self.resources.status()['serial'])

    def test_two_preparations_can_overlap_one_model_but_not_a_third(self):
        self.healthy()
        entered = [threading.Event() for _ in range(3)]
        release = threading.Event()
        def work(index):
            entered[index].set()
            release.wait(3)
        futures = []
        try:
            with self.resources.lease('model', self.cancel):
                futures = [self.resources.submit(self.cancel, work, i) for i in range(3)]
                self.assertTrue(entered[0].wait(2)); self.assertTrue(entered[1].wait(2))
                self.assertFalse(entered[2].wait(.05))
                self.assertEqual(self.resources.status()['active'], {'model':1, 'prepare':2})
        finally:
            release.set()
            for future in futures: future.result(timeout=3)

    def test_pressure_drains_inflight_and_blocks_overlap_with_model(self):
        self.healthy()
        entered = threading.Event()
        try:
            with self.resources.lease('model', self.cancel):
                self.sample = {**HEALTHY, 'pressure':2}; self.now += 2
                future = self.resources.submit(self.cancel, entered.set)
                self.assertFalse(entered.wait(.1))
            future.result(timeout=2)
            self.assertTrue(entered.is_set())
        finally: self.cancel.set()

    def test_model_lane_is_single_even_on_large_machine(self):
        self.sample = {**HEALTHY, 'total':128*1024**3, 'available':80*1024**3}
        self.healthy()
        entered = threading.Event()
        def another():
            with self.resources.lease('model', self.cancel): entered.set()
        with ThreadPoolExecutor(max_workers=1) as pool:
            with self.resources.lease('model', self.cancel):
                future = pool.submit(another)
                self.assertFalse(entered.wait(.1))
            future.result(timeout=2)

    def test_sixteen_gib_machine_keeps_preprocessing_serial(self):
        self.sample = {**HEALTHY, 'total':16*1024**3, 'available':8*1024**3}
        self.resources.status(); self.now += 30
        self.assertEqual(self.resources.status()['preprocessingLimit'], 1)
        self.assertTrue(self.resources.status()['serial'])

    def test_cancel_waiting_preprocess_and_disallow_inference_inside_it(self):
        with self.resources.lease('model', threading.Event()):
            future = self.resources.submit(self.cancel, lambda:None)
            self.cancel.set()
            with self.assertRaises(AgentCancelled): future.result(timeout=2)
        with self.resources.lease('prepare', threading.Event()):
            with self.assertRaises(RuntimeError):
                with self.resources.lease('model', threading.Event()): pass

    def test_window_lookahead_is_bounded_and_drained_on_failure(self):
        self.healthy()
        seen = []
        def prepare(index, start, end, token):
            seen.append(index)
            return index
        with self.assertRaisesRegex(ValueError, 'consumer'):
            with prepared_windows(self.resources, [(i,i+1) for i in range(100)], self.cancel, prepare) as windows:
                self.assertEqual(next(windows), (0,0,1,0))
                raise ValueError('consumer failure')
        self.assertLessEqual(len(seen), 3)
        self.assertEqual(self.resources.status()['active'], {'model':0,'prepare':0})

    def test_memory_probe_parses_native_pressure_without_cpu_count(self):
        vm = 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free: 100.\nPages inactive: 200.\nPages speculative: 5.\n'
        with patch('analysis_resources.sys.platform', 'darwin'), patch('analysis_resources.subprocess.check_output', side_effect=['17179869184\n2\n', vm]):
            self.assertEqual(memory_snapshot(), {'total':17179869184,'pressure':2,'available':305*16384})


class RoutingTests(unittest.TestCase):
    def test_worker_failure_classification_does_not_retry_configuration_or_format(self):
        from agent_models import ModelOutputError, CapabilityMissing
        for exc in (ModelOutputError('bad JSON'), CapabilityMissing('missing runtime'), FileNotFoundError()):
            self.assertFalse(retryable_analysis_error(exc))
        self.assertTrue(retryable_analysis_error(worker_response_error('RuntimeError: Metal out of memory')))
        self.assertFalse(retryable_analysis_error(worker_response_error('ValueError: unsupported codec')))

    def test_preprocessor_exit_after_ok_is_not_accepted_and_exit_code_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            worker=Path(folder)/'worker.py'
            worker.write_text('import sys\nprint(\'{"ok":true,"value":{}}\',flush=True)\nsys.exit(7)\n')
            model=ModelGateway(folder);model.python=sys.executable;model.worker=str(worker)
            model.capabilities=lambda:{'engineVersion':'0.9.1'}
            try:
                with self.assertRaisesRegex(LocalWorkerError, 'inspect, exit 7') as result:
                    model.prepare_local({'operation':'inspect'},threading.Event())
                self.assertTrue(retryable_analysis_error(result.exception))
            finally:model.resources.shutdown()

    def test_preprocessor_sigkill_retries_once_and_degrades_to_serial(self):
        with tempfile.TemporaryDirectory() as folder:
            marker=Path(folder)/'attempted'
            worker=Path(folder)/'worker.py'
            worker.write_text(f'import json,os,signal,sys\nfrom pathlib import Path\np=Path({str(marker)!r})\njson.loads(sys.stdin.readline())\nif not p.exists(): p.write_text("1"); os.kill(os.getpid(),signal.SIGKILL)\nprint(json.dumps({{"ok":True,"value":{{"retried":True}}}}))\n')
            model=ModelGateway(folder);model.python=sys.executable;model.worker=str(worker)
            model.capabilities=lambda:{'engineVersion':'0.9.1'}
            try:
                self.assertEqual(model.prepare_local({'operation':'inspect'},threading.Event()), {'retried':True})
                self.assertTrue(model.resources.status()['serial'])
            finally:model.resources.shutdown()
    def test_installed_cpu_worker_on_repository_fixture_without_model_process(self):
        import os
        with tempfile.TemporaryDirectory() as folder:
            model = ModelGateway(folder)
            if not Path(model.python).is_file() or model.capabilities()['engineVersion'] not in ('0.9.1', '0.9.2'):
                model.resources.shutdown()
                self.skipTest('Installed compatible VisionFlow runtime unavailable')
            try:
                with patch.dict(os.environ, {'PATH':str(ROOT/'build-desktop/media/bin')+os.pathsep+os.environ.get('PATH','')}):
                    sample = model.local({'operation':'catalog', 'action':'sample',
                        'source':str(ROOT/'qa/media-library/captioned-test.mp4'), 'folder':folder}, threading.Event())
                    self.assertEqual(sample['status'], 'ready')
                    frame = sample['observation']['frames'][0]['path']
                    result = model.inspect([frame], threading.Event())
                    self.assertEqual(len(result['quality']), 1)
                    motion = model.motion(ROOT/'qa/media-library/captioned-test.mp4', threading.Event())
                    self.assertIn(motion['status'], ('complete', 'insufficient-frames'))
                self.assertIsNone(model.process)
            finally:
                model.resources.shutdown(); model.close()

    def test_light_tasks_never_use_or_close_resident_model(self):
        with tempfile.TemporaryDirectory() as folder:
            model = ModelGateway(folder)
            model.process = sentinel = object()
            model.prepare_local = Mock(return_value={'ready':True})
            model.close = Mock()
            try:
                for payload in ({'operation':'inspect'}, {'operation':'motion'}, {'operation':'catalog','action':'sample'}):
                    self.assertEqual(model.local(payload, threading.Event()), {'ready':True})
                self.assertIs(model.process, sentinel)
                model.close.assert_not_called()
                self.assertEqual(model.prepare_local.call_count, 3)
            finally: model.resources.shutdown()

    def test_sample_cache_never_starts_any_process_and_invalidates_changed_source(self):
        from types import SimpleNamespace
        from media_catalog import sampling, source_key
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root/'clip.mp4'; source.write_bytes(b'fixture')
            frame = root/'frame.jpg'; frame.write_bytes(b'fixture')
            stat = source.stat()
            saved = root/'catalogs'/source_key(source); saved.mkdir(parents=True)
            observation = {'fingerprint':[str(source.resolve()),stat.st_size,stat.st_mtime_ns,stat.st_ino],
                           'observation_status':'complete','frames':[{'path':str(frame)}], 'shots':[{'start':0,'end':1}]}
            (saved/'observation.json').write_text(json.dumps(observation))
            local = Mock(return_value={'status':'rebuilt'})
            agent = SimpleNamespace(root=root, models=SimpleNamespace(local=local))
            self.assertEqual(sampling(agent,source,threading.Event())['status'], 'ready')
            local.assert_not_called()
            source.write_bytes(b'changed fixture')
            self.assertEqual(sampling(agent,source,threading.Event())['status'], 'rebuilt')
            local.assert_called_once()

    def test_helper_protocol_environment_and_resident_process_survive(self):
        # A fake installed worker tests the real subprocess protocol, not inference.
        with tempfile.TemporaryDirectory() as folder:
            worker = Path(folder)/'worker.py'
            worker.write_text('import json,sys,os\nj=json.loads(sys.stdin.readline())\nprint(json.dumps({"ok":True,"value":{"helper":"--preprocess-only" in sys.argv,"secret":os.environ.get("TEST_PRIVATE_KEY")}}))\n')
            model = ModelGateway(folder); model.python = sys.executable; model.worker = str(worker)
            model.capabilities = lambda:{'engineVersion':'0.9.1'}
            model.process = sentinel = object()
            try:
                with patch.dict('os.environ', {'TEST_PRIVATE_KEY':'must-not-leak'}):
                    result = model.local({'operation':'inspect','images':[]}, threading.Event())
                self.assertEqual(result, {'helper':True,'secret':None})
                self.assertIs(model.process, sentinel)
            finally: model.resources.shutdown()


if __name__ == '__main__': unittest.main()
