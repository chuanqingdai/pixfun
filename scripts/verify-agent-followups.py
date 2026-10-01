"""Real local inference audit using only the isolated library from verify-agent-local.

No production library access, cloud requests or media copying. Exits nonzero on
failed acceptance checks and saves the actual model results for human review.
"""
import json
import os
from pathlib import Path
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
prior = json.loads((ROOT / 'build-native/agent-real-cases.json').read_text())
workspace = Path(prior['workspace'])
if not workspace.name.startswith('pixfun-agent-real-') or not workspace.is_dir():
    raise RuntimeError('Run the isolated real-model walkthrough first.')
os.environ['PIXFUN_DATA_DIR'] = str(workspace)
from desktop_service import Library
from agent_engine import AgentEngine

library = Library(workspace)
agent = AgentEngine(library)
report = {'workspace': str(workspace), 'cases': []}
destination = ROOT / 'build-native/agent-followup-cases.json'


def wait(key):
    deadline = time.monotonic() + 600
    message = None
    while time.monotonic() < deadline:
        run = agent.get(key)
        if run['message'] != message:
            print(run['message'], flush=True)
            message = run['message']
        if run['status'] not in ('queued', 'running'):
            return run
        time.sleep(.25)
    agent.action({'id': key, 'action': 'stop'})
    raise TimeoutError('Follow-up exceeded 10 minutes')


def record(name, run, passed, started):
    report['cases'].append({'case': name, 'pass': bool(passed), 'seconds': round(time.monotonic()-started, 1), 'run': run})
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(name, 'PASS' if passed else 'FAIL', flush=True)


def start(prompt, ids, **fields):
    return wait(agent.start({'prompt': prompt, 'mediaIds': ids, 'requestId': uuid.uuid4().hex, 'mode': 'local', **fields})['id'])


try:
    base = next(r for r in agent.list() if r['intent'] == 'create' and r['status'] == 'completed')
    latest = next(r for r in agent.list() if r['projectId'] == base['projectId'] and r.get('timeline'))
    ids = base['mediaIds']
    selected = latest['timeline'][-1]
    protected = latest['timeline'][:-1]
    t = time.monotonic()
    scoped = start('只把选中的最后一个篝火片段缩短为2秒，其他镜头的字段和顺序完全不变，保留ID。不加任何新元素。', ids,
                   id=base['projectId'], editScope={'runId': latest['id'], 'version': latest['version'], 'shotIds': [selected['id']]})
    shots = scoped.get('timeline', [])
    record('scoped-local-edit', scoped, scoped['status'] == 'review' and shots[:-1] == protected
           and shots[-1]['id'] == selected['id'] and abs(shots[-1]['end']-shots[-1]['start']-2) < .01, t)
    if scoped['status'] == 'review':
        t = time.monotonic()
        rendered = wait(agent.action({'id': scoped['id'], 'action': 'approve'})['id'])
        preview = next((a for a in rendered['artifacts'] if a['type'] == 'preview'), None)
        record('scoped-edit-render', rendered, rendered['status'] == 'completed' and preview
               and Path(preview['path']).is_file(), t)
    t = time.monotonic()
    skill = start('使用旅行Vlog技能，按内容组织营地生活到夜晚篝火的故事，两个文件都保留，先给故事方案，不渲染。', ids,
                  skill={'id': 'visionflow-travel-director', 'title': 'Travel Vlog', 'strategy': 'Use the installed Travel Vlog specification.'})
    execution = skill.get('skillExecution', {})
    record('travel-skill-real-plan', skill, skill['status'] == 'completed' and skill['intent'] == 'plan'
           and execution.get('version') == '5.4' and execution.get('coverage', {}).get('requiresDecision') is False
           and not any(a['type'] == 'preview' for a in skill['artifacts']), t)
    t = time.monotonic()
    unsupported = start('做一个6秒视频，必须添加自动生成的音乐、配音和转场。', ids)
    record('unsupported-needs-confirmation', unsupported, unsupported['status'] == 'clarify'
           and not any(a['type'] == 'preview' for a in unsupported['artifacts']), t)
    t = time.monotonic()
    missing = start('帮我剪一个6秒16:9原声视频，不加音乐字幕。', [])
    record('missing-materials-clarification', missing, missing['status'] == 'clarify'
           and missing.get('clarificationKind') == 'materials', t)
finally:
    report['capabilities'] = agent.models.capabilities()
    agent.close()
    library.close()
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps({'passed': sum(c['pass'] for c in report['cases']), 'total': len(report['cases']), 'report': str(destination)}), flush=True)
if len(report['cases']) != 5 or not all(c['pass'] for c in report['cases']):
    sys.exit(1)
