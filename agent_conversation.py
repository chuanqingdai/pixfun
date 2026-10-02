"""Persist actual questions, offered choices and responses independently of run state."""
import re
import time
import uuid


def requests_plan_review(prompt):
    """Only an explicit user gate may interrupt a supported generation request."""
    prompt = re.sub(r"(?:\bno\b|\bwithout\b|\bdo not\b|\bdon't\b|\bnever\b|不需要|无需|不用|不要|不必)[^.!?\n。！？]{0,100}(?:approval|confirmation|review|确认|审核)[^.!?\n。！？]*", '', prompt, flags=re.I)
    return bool(re.search(
        r'\b(?:after|once|until)\s+(?:I|we)\s+(?:approve|confirm|review)\b|'
        r'\b(?:for (?:my )?approval|approval before rendering|wait for (?:my )?(?:approval|confirmation))\b|'
        r'\b(?:show|give)\s+(?:me\s+)?(?:the\s+)?(?:plan|script)\s+first\b|'
        r'\b(?:let me|I (?:want|need) to)\s+review\s+(?:the\s+)?(?:plan|script)\s+first\b|'
        r'(?:先.{0,8}(?:看|确认|审核).{0,6}(?:方案|脚本)|(?:等|待).{0,4}(?:确认|同意).{0,5}(?:再|后)|确认后再)',
        prompt, re.I))


def requests_plan_only(prompt):
    prompt = re.sub(r"(?:don't|do not|not just|不要只|不只是)[^.;\n。；]{0,60}(?:plan|方案)[^.;\n。；]*", '', prompt, flags=re.I)
    return bool(re.search(r'\bplan only\b|\bonly (?:a |the )?plan\b|只.{0,3}(?:方案|规划)|(?:方案|规划).{0,8}(?:不渲染|不生成)', prompt, re.I))


def decision(run):
    status = run['status']
    question = run.get('question', '')
    options = []
    video_only = status == 'clarify' and (run.get('clarificationKind') in ('video_only','visual_only') or
        question.startswith('This rough-cut workflow currently uses video and its original sound only.'))
    if status == 'consent':
        options = [('approve', 'Allow this task'), ('stop', 'Decline')]
    elif video_only:
        options = [('use_visuals', 'Use photos & videos') if run.get('clarificationKind') == 'visual_only' else ('use_videos', 'Use videos only'), ('change_files', 'Change files')]
    elif status == 'review' or (status == 'completed' and run.get('intent') == 'plan' and run.get('timeline') and
                                not any(a['type'] == 'preview' for a in run.get('artifacts', []))):
        question = question or 'Review the plan. Build a preview, or describe your changes.'
        options = [('approve', 'Build preview')]
    elif status in ('failed', 'cancelled', 'interrupted'):
        question = question or run.get('message') or 'Try this task again?'
        options = [('retry', 'Retry')]
    elif status != 'clarify' or not question:
        return None
    elif run.get('choices'):
        options = [(choice['id'], choice['label']) for choice in run['choices']]
    return {'status': status, 'version': run.get('version', 1), 'question': question,
            'options': [{'id': key, 'label': label} for key, label in options],
            'resultText': run.get('resultText', '')}


def capture_decision(run):
    current = decision(run)
    history = run.setdefault('conversationHistory', [])
    pending = next((item for item in reversed(history) if item['state'] == 'pending'), None)
    if pending:
        if current and all(pending.get(k) == current.get(k) for k in ('status', 'version', 'question', 'options')):
            return pending
        pending['state'] = 'closed'
    if current:
        item = dict(current, id=uuid.uuid4().hex, createdAt=time.time()*1000, state='pending', selected=None, response=None)
        history.append(item)
        return item
    return None


def answer_decision(run, action=None, response=None, close=True):
    item = capture_decision(run)
    if item is None:
        return
    if action is None and response:
        action = next((choice['id'] for choice in run.get('choices', []) if choice['prompt'] == response), None)
    option = next((value for value in item['options'] if value['id'] == action), None)
    if action is not None and option is None:
        return
    item.update(selected=action, response=response if response is not None else option['label'],
                answeredAt=time.time()*1000, state='answered' if close else 'pending')
