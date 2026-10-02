import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from agent_conversation import capture_decision, answer_decision, requests_plan_review, requests_plan_only


class ConversationTests(unittest.TestCase):
    def test_only_explicit_review_requests_pause_generation(self):
        for prompt in ['Create a travel video', '生成视频，直接完成', 'No approval before rendering.',
                       'Do not ask for approval before rendering.', '不用确认，直接生成', 'Render without waiting for approval.']:
            self.assertFalse(requests_plan_review(prompt), prompt)
        for prompt in ['Show me the plan for approval before rendering.', 'Wait for my approval.',
                       'Create a video after I approve the plan.', 'Let me review the plan first.', '先确认方案，再制作', '等我确认后再生成']:
            self.assertTrue(requests_plan_review(prompt), prompt)
        self.assertTrue(requests_plan_only('Give me a plan only; do not render.'))
        self.assertFalse(requests_plan_only("Don't give me a plan only; render the video."))

    def test_direction_click_is_saved_as_answer_not_another_question(self):
        run = self.fixture(); run['clarificationKind'] = 'direction'
        run['choices'] = [{'id':'selected', 'label':'Use selected moments', 'prompt':'Use only selected moments.'}]
        answer_decision(run, response='Use only selected moments.')
        item = run['conversationHistory'][0]
        self.assertEqual(item['selected'], 'selected')
        self.assertEqual(item['state'], 'answered')
        self.assertEqual(item['options'][0]['label'], 'Use selected moments')

    def fixture(self):
        return dict(status='clarify', clarificationKind='video_only', question='Leave out the photos?',
                    resultText='', version=1, timeline=[], artifacts=[], intent='plan')

    def test_choice_and_question_survive_execution_and_reload(self):
        run = self.fixture()
        capture_decision(run); capture_decision(run)
        self.assertEqual(len(run['conversationHistory']), 1)
        answer_decision(run, action='use_videos')
        run.update(status='running', question='')
        capture_decision(run)
        restored = json.loads(json.dumps(run))['conversationHistory'][0]
        self.assertEqual(restored['question'], 'Leave out the photos?')
        self.assertEqual(restored['selected'], 'use_videos')
        self.assertEqual(restored['state'], 'answered')
        self.assertEqual([o['label'] for o in restored['options']], ['Use videos only', 'Change files'])

    def test_new_question_never_overwrites_old_question(self):
        run = self.fixture(); first = copy.deepcopy(capture_decision(run))
        run.update(question='A different question', clarificationKind='other')
        capture_decision(run)
        self.assertEqual(run['conversationHistory'][0]['question'], first['question'])
        self.assertEqual(len(run['conversationHistory']), 2)
        self.assertEqual(run['conversationHistory'][0]['state'], 'closed')

    def test_plan_snapshot_and_approval_remain_after_render(self):
        run = self.fixture(); run.update(status='completed', timeline=[{'id':'shot'}], question='', resultText='Original plan')
        capture_decision(run); answer_decision(run, action='approve')
        run.update(status='running', resultText='Preview is rendering')
        capture_decision(run)
        self.assertEqual(run['conversationHistory'][0]['resultText'], 'Original plan')
        self.assertEqual(run['conversationHistory'][0]['response'], 'Build preview')

    def test_free_text_reply_is_recorded_not_cloud_approval(self):
        run = self.fixture(); run.update(status='consent', cloudApproved=False)
        answer_decision(run, response='Keep it local')
        self.assertFalse(run['cloudApproved'])
        self.assertIsNone(run['conversationHistory'][0]['selected'])
        self.assertEqual(run['conversationHistory'][0]['response'], 'Keep it local')

    def test_changing_files_keeps_decision_pending(self):
        run = self.fixture(); answer_decision(run, action='change_files', close=False)
        capture_decision(run)
        self.assertEqual(len(run['conversationHistory']), 1)
        self.assertEqual(run['conversationHistory'][0]['state'], 'pending')

    def test_invalid_action_never_claims_approval(self):
        run = self.fixture(); answer_decision(run, action='approve')
        self.assertIsNone(run['conversationHistory'][0]['response'])


if __name__ == '__main__': unittest.main()
