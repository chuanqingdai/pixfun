"""Tool policy, score validation and worker boundaries; no model downloads or GPU."""
import ast
import math
from pathlib import Path
import sys
import threading
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

    def test_gateway_rejects_unknown_operations_before_starting_worker(self):
        gateway = ModelGateway.__new__(ModelGateway)
        with self.assertRaisesRegex(ValueError, 'Unsupported local operation'):
            gateway.local({'operation': 'shell'}, threading.Event())
        ast.parse((ROOT/'scripts/agent-model-worker.py').read_text())


if __name__ == '__main__': unittest.main()
