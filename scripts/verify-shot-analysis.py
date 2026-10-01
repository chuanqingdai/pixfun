"""Real offline editorial analysis on isolated repository travel examples."""
import json
import os
from pathlib import Path
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
workspace=Path(tempfile.mkdtemp(prefix='pixfun-shots-real-')); os.environ['PIXFUN_DATA_DIR']=str(workspace)
from desktop_service import Library
from agent_engine import AgentEngine
from shot_analysis import ShotAnalyses, seconds, validate_shot
library=Library(workspace); agent=AgentEngine(library); service=ShotAnalyses(library,agent); results=[]
print('Isolated cache: '+str(workspace),flush=True)
try:
    for name in ('public/media/travel/story/coffee.mp4','public/media/travel/travel-edit-example.mp4'):
        item=library.register([str(ROOT/name)])['items'][0]; start=time.monotonic(); service.start(item['id']); last=None
        deadline=time.monotonic()+1200
        while time.monotonic()<deadline:
            state=library.get(item['id'])[0].get('shotAnalysis',{})
            if state.get('message')!=last: last=state.get('message'); print(last,flush=True)
            if state.get('status') not in ('queued','running'): break
            time.sleep(.5)
        else: raise TimeoutError('Editorial analysis timed out')
        result={'file':name,'elapsed':round(time.monotonic()-start,1),'state':state}
        results.append(result); print(json.dumps(result,ensure_ascii=False),flush=True)
        if state['status']=='ready':
            shots=state['output']['shots']; duration=library.get(item['id'])[0]['metadata']['duration']
            assert seconds(shots[0]['start_time'])==0 and abs(seconds(shots[-1]['end_time'])-duration)<.002
            assert all(a['end_time']==b['start_time'] for a,b in zip(shots,shots[1:]))
            if name.endswith('coffee.mp4'): assert len(shots)==1, 'Ordinary continuous cup movement should not be oversplit'
            if name.endswith('travel-edit-example.mp4'): assert len(shots)>=2, 'Distinct travel scenes should be independently editable'
finally:
    service.stop(); agent.close(); library.close()
    (ROOT/'build-native/shot-analysis-cases.json').write_text(json.dumps({'workspace':str(workspace),'cases':results},ensure_ascii=False,indent=2))
if len(results)!=2 or any(x['state']['status']!='ready' for x in results): raise SystemExit(1)
