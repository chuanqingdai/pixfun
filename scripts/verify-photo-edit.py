"""Real local-model photo-to-video smoke test in an isolated library, never the user's library."""
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
workspace = Path(tempfile.mkdtemp(prefix='pixfun-photo-edit-'))
os.environ['PIXFUN_DATA_DIR'] = str(workspace)
from desktop_service import Library
from agent_engine import AgentEngine

library = Library(workspace)
agent = AgentEngine(library)
destination = ROOT/'build-native/photo-edit-real-model.json'
report = {'workspace':str(workspace), 'scope':'Real local inference and render; not full audiovisual QA'}
try:
    ids = [item['id'] for item in library.register([str(ROOT/'public/media/travel/story'/name)
           for name in ('coffee.jpg','selfie.jpg','rest.jpg')])['items']]
    run = agent.start({'prompt':'Create a 9-second travel video from these three photos. Include every photo, keep the full images visible, and use no music or text.',
        'mediaIds':ids,'requestId':uuid.uuid4().hex,'mode':'local',
        'skill':{'id':'visionflow-travel-short','title':'Travel Short','strategy':'Use the installed short-film strategy.'}})
    deadline = time.monotonic()+600
    previous = None
    while run['status'] in ('queued','running'):
        if time.monotonic()>deadline:
            agent.action({'id':run['id'],'action':'stop'}); raise TimeoutError('Local photo test exceeded ten minutes')
        if run['message'] != previous: print(run['message'],flush=True); previous=run['message']
        time.sleep(.5); run=agent.get(run['id'])
    report['run']=run
    preview = next((a for a in run['artifacts'] if a['type']=='preview'),None)
    report['pass'] = run['status']=='completed' and bool(preview) and {s['mediaId'] for s in run['timeline']}==set(ids)
    if preview:
        report['probe']=json.loads(agent.command(['ffprobe','-v','error','-show_streams','-show_format','-of','json',preview['path']],threading.Event()))
        agent.command(['ffmpeg','-v','error','-xerror','-i',preview['path'],'-f','null','-'],threading.Event())
        report['pass'] = report['pass'] and abs(float(report['probe']['format']['duration'])-9)<.3
    print('PASS' if report['pass'] else 'FAIL',run['message'],flush=True)
finally:
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    agent.close(); library.close()
    print(destination,flush=True)
if not report.get('pass'): raise SystemExit(1)
