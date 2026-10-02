"""Real local model + FFmpeg acceptance: mixed attachments, Travel Vlog, edit and undo.

Uses repository sample media in an isolated library; never opens the user's library.
No cloud calls. Full decode is technical QA, not a claim of audiovisual review.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
workspace = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix='pixfun-travel-chain-'))
if not workspace.name.startswith('pixfun-travel-chain-') or not workspace.is_dir():
    raise ValueError('Only an existing isolated travel-chain test library may be reused.')
os.environ['PIXFUN_DATA_DIR'] = str(workspace)
from desktop_service import Library
from agent_engine import AgentEngine

library = Library(workspace)
agent = AgentEngine(library)
report = {'workspace': str(workspace), 'scope': 'Real local inference and rendering; no full audiovisual review', 'cases': []}
destination = ROOT / 'build-native/travel-edit-chain.json'

def record(name, passed, **evidence):
    report['cases'].append({'case': name, 'pass': bool(passed), **evidence})
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(name, 'PASS' if passed else 'FAIL', flush=True)
    if not passed: raise AssertionError(name)

def wait(key):
    deadline = time.monotonic() + 900
    previous = None
    while time.monotonic() < deadline:
        run = agent.get(key)
        if run['message'] != previous:
            print(run['message'], flush=True); previous = run['message']
        if run['status'] not in ('queued', 'running'): return run
        time.sleep(.3)
    agent.action({'id': key, 'action': 'stop'})
    raise TimeoutError('Task exceeded 15 minutes')

def start(prompt, ids, **fields):
    return wait(agent.start({'prompt': prompt, 'mediaIds': ids, 'requestId': uuid.uuid4().hex,
                             'mode': 'local', **fields})['id'])

def render(run, name, seconds):
    rendered = run if any(a['type'] == 'preview' for a in run['artifacts']) else wait(agent.action({'id': run['id'], 'action': 'approve'})['id'])
    preview = next((a for a in rendered['artifacts'] if a['type'] == 'preview'), None)
    record(name, rendered['status'] == 'completed' and preview, run=rendered)
    path = preview['path']
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', path]))
    decode = subprocess.run(['ffmpeg', '-v', 'error', '-xerror', '-i', path, '-f', 'null', '-'], capture_output=True, text=True)
    record(name + '-decode', decode.returncode == 0 and not decode.stderr.strip()
           and abs(float(info['format']['duration']) - seconds) < .15
           and {s['codec_type'] for s in info['streams']} == {'audio', 'video'},
           path=path, measuredDuration=info['format']['duration'], stderr=decode.stderr)
    return rendered

try:
    items = library.register([str(ROOT/'public/media/travel/story'/name)
                              for name in ('camp.mp4', 'clouds.mp4', 'coffee.jpg')])['items']
    ids = [item['id'] for item in items]
    plan = start('Suggest a 6-second story structure using these files, with each video appearing for 3 seconds. Keep original sound. Give me the plan before creating a video.', ids)
    record('mixed-media-choice', plan['status'] == 'clarify' and plan.get('clarificationKind') == 'video_only'
           and 'coffee.jpg' in plan['question'] and not plan['timeline'], run=plan)
    plan = wait(agent.action({'id': plan['id'], 'action': 'use_videos'})['id'])
    record('default-skill-and-story', plan['status'] == 'completed' and plan['intent'] == 'plan'
           and plan.get('skillExecution', {}).get('id') == 'visionflow-travel-director'
           and plan.get('skillNotice') and len(plan['timeline']) == 2
           and plan['duration'] == 6 and 'Duration differs' not in plan['resultText']
           and {s['mediaId'] for s in plan['timeline']} == set(ids[:2]), run=plan)
    first = render(plan, 'initial-preview', 6)
    selected = first['timeline'][-1]
    revised = start('Shorten only the selected final shot to 2 seconds. Keep all other shots and IDs unchanged. Keep original sound.', ids[:2],
                    id=first['projectId'], editScope={'runId': first['id'], 'version': first['version'], 'shotIds': [selected['id']]})
    record('scoped-conversation-edit', revised['status'] == 'completed'
           and revised['timeline'][:-1] == first['timeline'][:-1]
           and revised['timeline'][-1]['id'] == selected['id']
           and abs(revised['timeline'][-1]['end'] - revised['timeline'][-1]['start'] - 2) < .01, run=revised)
    revised = render(revised, 'revised-preview', 5)
    restored = agent.action({'id': revised['id'], 'action': 'timeline', 'version': revised['version'], 'timeline': first['timeline']})
    record('undo-keeps-previous-preview', restored['timeline'] == first['timeline']
           and any(a['type'] == 'previous_preview' for a in restored['artifacts']), run=restored)
    render(restored, 'restored-preview', 6)
finally:
    report['capabilities'] = agent.models.capabilities()
    agent.close(); library.close()
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print('Report: ' + str(destination), flush=True)
