"""Run the exact three native starter prompts against real local inference.

An optional isolated travel-chain library reuses previously analyzed footage.
Never opens the production library or uploads footage. Approval is explicit.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('workspace', nargs='?', type=Path)
parser.add_argument('--case', choices=('all', 'analyze', 'create', 'highlights'), default='all')
args = parser.parse_args()
workspace = args.workspace or Path(tempfile.mkdtemp(prefix='pixfun-travel-chain-'))
if not workspace.is_dir() or not workspace.name.startswith('pixfun-travel-chain-'):
    raise ValueError('Use an isolated travel-chain test library only.')
os.environ['PIXFUN_DATA_DIR'] = str(workspace)
from desktop_service import Library
from agent_engine import AgentEngine

source = (ROOT/'native/Sources/Pixfun/AgentModels.swift').read_text()
prompts = dict(re.findall(r'\.init\(id: "(analyze|create|highlights)",[^\n]+prompt: "([^"\n]+)"\)', source))
assert set(prompts) == {'analyze', 'create', 'highlights'}
if args.case != 'all':
    prompts = {args.case: prompts[args.case]}
library = Library(workspace)
agent = AgentEngine(library)
destination = ROOT/('build-native/starter-prompts' + ('' if args.case == 'all' else '-'+args.case) + '.json')
destination.parent.mkdir(exist_ok=True)
report = {'workspace': str(workspace), 'reusedAnalysisLibrary': args.workspace is not None,
          'scope': 'Real local model and rendering; not native UI or full audiovisual QA', 'cases': []}

def record(name, passed, **evidence):
    report['cases'].append({'case': name, 'pass': bool(passed), **evidence})
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(name, 'PASS' if passed else 'FAIL', flush=True)
    if not passed:
        raise AssertionError(name)

def wait(key):
    deadline = time.monotonic() + 900
    previous = None
    while time.monotonic() < deadline:
        run = agent.get(key)
        if run['message'] != previous:
            print(run['message'], flush=True)
            previous = run['message']
        if run['status'] not in ('queued', 'running'):
            return run
        time.sleep(.3)
    agent.action({'id': key, 'action': 'stop'})
    raise TimeoutError('Task exceeded 15 minutes')

try:
    items = library.register([str(ROOT/'public/media/travel/story'/name) for name in ('camp.mp4', 'clouds.mp4')])['items']
    ids = [item['id'] for item in items]
    for name, prompt in prompts.items():
        run = wait(agent.start({'prompt': prompt, 'mediaIds': ids, 'requestId': uuid.uuid4().hex, 'mode': 'local'})['id'])
        has_preview = any(a['type'] == 'preview' for a in run['artifacts'])
        if name == 'analyze':
            analysis = run.get('analysisReport') or {}
            materials = analysis.get('materials', [])
            record(name, run['status'] == 'completed' and run['intent'] == 'analyze'
                   and analysis.get('overview') and {m['mediaId'] for m in materials} == set(ids)
                   and all(m.get('content') and m.get('suggestion') for m in materials)
                   and not run['timeline'] and not has_preview, prompt=prompt, run=run)
        else:
            record(name, run['intent'] == 'create'
                   and run['status'] == 'completed'
                   and run['timeline'] and has_preview
                   and run.get('skillExecution', {}).get('id') == 'visionflow-travel-director'
                   and run.get('skillNotice'), prompt=prompt, run=run)
        if name in ('create', 'highlights'):
            rendered = run
            preview = next((a for a in rendered['artifacts'] if a['type'] == 'preview'), None)
            record('automatic-preview', rendered['status'] == 'completed' and preview, run=rendered)
            path = preview['path']
            info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', path]))
            decode = subprocess.run(['ffmpeg', '-v', 'error', '-xerror', '-i', path, '-f', 'null', '-'], capture_output=True, text=True)
            video = next(s for s in info['streams'] if s['codec_type'] == 'video')
            record('preview-decode', decode.returncode == 0 and not decode.stderr.strip()
                   and abs(float(info['format']['duration']) - rendered['duration']) < .15
                   and abs(video['width']/video['height'] - 16/9) < .01,
                   path=path, duration=info['format']['duration'], stderr=decode.stderr)
finally:
    agent.close()
    library.close()
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print('Report: ' + str(destination), flush=True)
