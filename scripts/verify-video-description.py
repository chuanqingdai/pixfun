"""Real local inference, using project examples and an isolated cache."""
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import argparse

ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
parser=argparse.ArgumentParser()
parser.add_argument('--reuse-qa-cache',type=Path,help='Reuse an isolated previous verification cache, never the real library.')
args=parser.parse_args()
workspace=args.reuse_qa_cache or Path(tempfile.mkdtemp(prefix='pixfun-description-real-'))
if args.reuse_qa_cache and (not workspace.name.startswith('pixfun-description-real-') or not workspace.is_dir()):
    parser.error('Use a previous isolated pixfun-description-real- directory.')
os.environ['PIXFUN_DATA_DIR']=str(workspace)
from desktop_service import Library
from agent_engine import AgentEngine
from video_description import VideoDescriptions
library=Library(workspace); agent=AgentEngine(library); service=VideoDescriptions(library,agent)
results=[]
try:
    for filename in ('public/media/travel/story/coffee.mp4','public/media/travel/travel-edit-example.mp4'):
        source=(ROOT/filename).resolve()
        item=next((entry for entry in library.list() if library.get(entry['id'])[1].resolve()==source),None)
        if item is None: item=library.register([str(source)])['items'][0]
        started=time.monotonic(); service.start(item['id'],force=True); previous=None
        deadline=time.monotonic()+900
        while time.monotonic()<deadline:
            value=library.get(item['id'])[0].get('videoDescription',{})
            if value.get('message')!=previous: print(value.get('message'),flush=True); previous=value.get('message')
            if value.get('status') not in ('queued','running'): break
            time.sleep(.5)
        else: service.stop(item['id']); raise TimeoutError('Description case timed out')
        results.append({'file':filename,'seconds':round(time.monotonic()-started,1),'result':value})
        print(json.dumps(results[-1],ensure_ascii=False),flush=True)
finally:
    service.stop(); agent.close(); library.close()
    (ROOT/'build-native/video-description-cases.json').write_text(json.dumps({'workspace':str(workspace),'cases':results},ensure_ascii=False,indent=2))
if len(results)!=2 or any(r['result']['status']!='ready' for r in results): raise SystemExit(1)
