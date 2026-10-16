import sys
from pathlib import Path
import threading
import unittest
from unittest.mock import Mock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from phone_import_analysis import schedule

class AnalysisTests(unittest.TestCase):
    def test_video_queues_existing_local_description_and_shot_analysis(self):
        lib=Mock();lib.get.return_value=({'kind':'video'},None)
        agent=Mock();descriptions=Mock();shots=Mock()
        schedule(lib,agent,descriptions,shots,threading.Event(),'v')
        descriptions.start.assert_called_once_with('v');shots.start.assert_called_once_with('v')
        agent.observe.assert_not_called()

    def test_photo_uses_local_mode_and_runs_off_request_thread(self):
        lib=Mock();lib.get.return_value=({'kind':'image'},None);agent=Mock();stop=threading.Event()
        schedule(lib,agent,Mock(),Mock(),stop,'p')
        agent.observe.assert_not_called()
        agent.pool.submit.call_args[0][0]()
        self.assertEqual(agent.observe.call_args[0],({'mode':'local'},'p',stop))
        self.assertEqual(lib.patch.call_args[1]['phoneImportAnalysis']['status'],'ready')

    def test_no_cloud_fallback_on_model_failure(self):
        lib=Mock();lib.get.return_value=({'kind':'image'},None);agent=Mock();agent.observe.side_effect=RuntimeError('missing')
        schedule(lib,agent,Mock(),Mock(),threading.Event(),'p');agent.pool.submit.call_args[0][0]()
        self.assertEqual(agent.observe.call_count,1)
        self.assertEqual(lib.patch.call_args[1]['phoneImportAnalysis']['status'],'failed')

if __name__=='__main__':unittest.main()
