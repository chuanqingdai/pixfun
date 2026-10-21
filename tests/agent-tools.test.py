"""Tool policy, score validation and worker boundaries; no model downloads or GPU."""
import ast
import math
from pathlib import Path
import sys
import threading
import tempfile
import json
import subprocess
import os
from unittest.mock import patch
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from agent_tools import tool_plan, ranked_evidence
from agent_models import ModelGateway


class ToolTests(unittest.TestCase):
    def test_story_uses_speech_without_unnecessary_search(self):
        self.assertEqual(tool_plan('create', {})['tools'], ['transcribe'])
        self.assertEqual(tool_plan('analyze', {})['tools'], [])
        self.assertEqual(tool_plan('search', {})['tools'], ['rank'])

    def test_model_can_choose_tools_for_thematic_planning(self):
        plan = tool_plan('plan', {'tools': ['rank', 'rank'], 'query': 'mountain sunrise'})
        self.assertEqual(plan['tools'], ['rank', 'transcribe'])
        self.assertEqual(plan['scope'], 'attached-media-only')
        self.assertEqual(tool_plan('subtitles', {'tools': ['rank']})['tools'], ['transcribe'])

    def test_unknown_tools_and_malformed_plans_rejected(self):
        for tools in [['shell'], ['upload'], [{'tool': 'rank'}], 'rank', ['rank'] * 9]:
            with self.assertRaises(ValueError): tool_plan('create', {'tools': tools})
        with self.assertRaises(ValueError): tool_plan('search', {'query': ['path']})

    def test_ranking_preserves_all_sources_and_never_mutates_evidence(self):
        rows = [{'mediaId': 'a'}, {'mediaId': 'b'}]
        ranked = ranked_evidence(rows, {'scores': [.2, .9]})
        self.assertEqual([r['mediaId'] for r in ranked], ['a', 'b'])
        self.assertNotIn('similarity', rows[0])
        for scores in [[.2], [math.nan, .4], [True, .2], ['.2', .3]]:
            with self.assertRaises(ValueError): ranked_evidence(rows, {'scores': scores})

    def test_missing_dependencies_do_not_advertise_or_launch_inference(self):
        from agent_models import CapabilityMissing
        with tempfile.TemporaryDirectory() as folder:
            gateway = ModelGateway(folder)
            gateway.python = sys.executable
            gateway.vision = gateway.speech = gateway.retrieval = 'cached-model'
            with patch('agent_models.runtime_dependencies', return_value={}) as probe:
                caps = gateway.capabilities()
                self.assertFalse(caps['localVision']); self.assertFalse(caps['localSpeech'])
                self.assertFalse(caps['adaptiveSampling']); self.assertFalse(caps['localRetrieval'])
                with patch('agent_models.subprocess.Popen', side_effect=AssertionError('must not launch worker')):
                    with self.assertRaises(CapabilityMissing): gateway.ask('hello',threading.Event())
                probe.assert_called_once()
            gateway.resources.shutdown(); gateway.close()

    def test_host_and_worker_reject_unreviewed_runtime_versions(self):
        with tempfile.TemporaryDirectory() as folder:
            runtime=Path(folder); (runtime/'scripts').mkdir()
            (runtime/'scripts/vf_engine.py').write_text('')
            manifest=runtime/'pyproject.toml'
            gateway=ModelGateway(folder); gateway.runtime=runtime; gateway.python=sys.executable
            gateway.vision='cached-model'
            gateway._dependency_cache=(sys.executable, {'mlx.core':True,'mlx_vlm':True})
            for version in ('0.9.1','0.9.2'):
                manifest.write_text('version = "'+version+'"')
                self.assertTrue(gateway.capabilities()['localVision'])
            manifest.write_text('version = "0.9.3"')
            self.assertFalse(gateway.capabilities()['localVision'])
            result=subprocess.run([sys.executable,str(ROOT/'scripts/agent-model-worker.py'),'--preprocess-only'],
                input=json.dumps({'operation':'story'})+'\n', text=True, capture_output=True,
                env={**os.environ,'PIXFUN_VF_ROOT':folder}, timeout=5, check=True)
            reply=json.loads(result.stdout)
            self.assertFalse(reply['ok']); self.assertIn('incompatible runtime',reply['error'])
            gateway.resources.shutdown(); gateway.close()

    def test_gateway_rejects_unknown_operations_before_starting_worker(self):
        gateway = ModelGateway.__new__(ModelGateway)
        with self.assertRaisesRegex(ValueError, 'Unsupported local operation'):
            gateway.local({'operation': 'shell'}, threading.Event())
        ast.parse((ROOT/'scripts/agent-model-worker.py').read_text())


if __name__ == '__main__': unittest.main()
