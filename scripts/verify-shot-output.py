"""Focused real-local-model regression with an isolated library and saved responses."""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('--capture-only', action='store_true')
args = parser.parse_args()
workspace = Path(tempfile.mkdtemp(prefix='pixfun-shot-output-'))
os.environ['PIXFUN_DATA_DIR'] = str(workspace)
os.environ['PATH'] = str(ROOT/'dist-native/Pixfun.app/Contents/Resources/bin') + os.pathsep + os.environ['PATH']
sys.path.insert(0, str(ROOT))
from desktop_service import Library
from agent_engine import AgentEngine
from shot_analysis import validate_shot, seconds

library = Library(workspace)
agent = AgentEngine(library)
original = agent.models.ask
responses = []
report = {'source': str(args.source.resolve()), 'workspace': str(workspace), 'mode': 'local', 'pass': False}

class Captured(Exception):
    pass

def ask(prompt, cancel, *positional, **keywords):
    result = original(prompt, cancel, *positional, **keywords)
    if 'EDITORIAL_SHOT' in prompt:
        responses.append({'prompt': prompt, 'response': result})
        (workspace/'responses.json').write_text(json.dumps(responses, ensure_ascii=False, indent=2))
        print('Response fields: '+', '.join(result), flush=True)
        if args.capture_only:
            raise Captured()
    return result

agent.models.ask = ask
try:
    mid = library.register([str(args.source.resolve())])['items'][0]['id']
    item, result = agent.understand({'mode': 'local'}, mid, threading.Event(), progress=lambda m: print(m, flush=True))
    for shot in result['output']['shots']:
        validate_shot(shot, seconds(shot['start_time']), seconds(shot['end_time']), result['speechEvidence']['cues'], item['metadata'].get('hasAudio', False))
    report.update(result=result, capabilities=agent.models.capabilities())
    report['pass'] = True
except Captured:
    report['capturedOnly'] = True
finally:
    agent.close()
    library.close()
    (workspace/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print('REPORT '+str(workspace/'report.json'), flush=True)
