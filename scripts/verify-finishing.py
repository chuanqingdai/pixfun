"""Real local router/planner, cached real footage analysis, system speech and bundled FFmpeg.

Only an isolated acceptance-test library may be reused; no production data or cloud calls.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
workspace=Path(sys.argv[1]) if len(sys.argv)>1 else Path(tempfile.mkdtemp(prefix='pixfun-travel-chain-'))
if not workspace.is_dir() or not workspace.name.startswith('pixfun-travel-chain-'): raise ValueError('Use an isolated acceptance library only')
os.environ['PIXFUN_DATA_DIR']=str(workspace)
from desktop_service import Library
from agent_engine import AgentEngine

library=Library(workspace); agent=AgentEngine(library)
report={'workspace':str(workspace),'scope':'Real local routing/planning and media rendering; cached visual evidence; not native UI or subjective audiovisual review','checks':[]}
destination=ROOT/'build-native/finishing-acceptance.json'
original_ask=agent.models.ask
def observed_ask(prompt,*args,**kwargs):
    answer=original_ask(prompt,*args,**kwargs)
    if 'task router' in prompt: report['router']=answer
    if prompt.startswith(('Plan an edit','Plan sound')): report.setdefault('proposals',[]).append(answer)
    return answer
agent.models.ask=observed_ask

def check(name,ok,**evidence):
    report['checks'].append({'name':name,'pass':bool(ok),**evidence})
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(name,'PASS' if ok else 'FAIL',flush=True)
    if not ok: raise AssertionError(name)

def wait(key):
    deadline=time.monotonic()+600; previous=None
    while time.monotonic()<deadline:
        run=agent.get(key)
        if run['message']!=previous: print(run['message'],flush=True); previous=run['message']
        if run['status'] not in ('queued','running'): return run
        time.sleep(.3)
    agent.action({'id':key,'action':'stop'}); raise TimeoutError('Finishing acceptance timed out')

try:
    ids=[i['id'] for i in library.register([str(ROOT/'public/media/travel/story'/name) for name in ('camp.mp4','clouds.mp4')])['items']]
    prompt='Create a 12-second travel video using both attached videos. Add Carefree from the bundled music library at low volume with automatic ducking. Add a fade through black between clips. Add this English voiceover once in the first 6 seconds: "A quiet moment before the next adventure." Keep original sound where available. Show the plan and narration script for approval first.'
    run=wait(agent.start({'prompt':prompt,'mediaIds':ids,'requestId':uuid.uuid4().hex,'mode':'local'})['id'])
    f=run.get('finishing') or {}
    check('local-plan',run['status']=='review' and f.get('music',{}).get('mediaId')=='music-carefree' and f.get('narration') and f.get('transition',{}).get('kind')=='fade',run=run)
    check('approval-gate',not any(a['type']=='preview' for a in run['artifacts']))
    done=wait(agent.action({'id':run['id'],'action':'approve'})['id'])
    preview=next((a for a in done['artifacts'] if a['type']=='preview'),None)
    check('real-voice-music-transition-render',done['status']=='completed' and preview,run=done)
    decoded=subprocess.run(['ffmpeg','-v','error','-xerror','-i',preview['path'],'-f','null','-'],capture_output=True,text=True)
    check('full-decode',decoded.returncode==0 and not decoded.stderr,stderr=decoded.stderr,path=preview['path'])
finally:
    agent.close(); library.close()
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print('Report:',destination,flush=True)
