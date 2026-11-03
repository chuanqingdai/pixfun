"""Packaged HTTP → original media → H.264 export, no inference or production writes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import subprocess
import tempfile
import time
import uuid
from urllib.request import Request, urlopen
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
args = parser.parse_args()
resources = args.app.resolve()/'Contents/Resources'
workspace = Path(tempfile.mkdtemp(prefix='pixfun-packaged-export-'))
token, native = secrets.token_hex(32), secrets.token_hex(32)
env = {**os.environ, 'PATH':str(resources/'bin')+':/usr/bin:/bin:/usr/sbin:/sbin',
       'PIXFUN_DATA_DIR':str(workspace), 'PIXFUN_PUBLIC_DIR':str(resources/'public'),
       'PIXFUN_AGENT_WORKER':str(resources/'agent-model-worker.py'), 'PIXFUN_MUSIC_DIR':str(resources/'Music'),
       'PIXFUN_SERVICE_TOKEN':token, 'PIXFUN_NATIVE_TOKEN':native, 'PIXFUN_PARENT_PID':str(os.getpid())}
report = {'workspace':str(workspace), 'scope':'Packaged export using a fixture saved timeline; no model inference', 'cases':[]}
log = (workspace/'service.log').open('w')
service = subprocess.Popen([str(resources/'backend/pixfun-service/pixfun-service')], env=env,
                           stdout=subprocess.PIPE, stderr=log, text=True)
try:
    ready = json.loads(service.stdout.readline()); base = 'http://127.0.0.1:'+str(ready['port'])
    def api(route, data=None, authorized=True):
        headers = {'Authorization':'Bearer '+token, 'Content-Type':'application/json'}
        if authorized: headers['X-Pixfun-Native'] = native
        request = Request(base+'/api/desktop/'+route, data=None if data is None else json.dumps(data).encode(), headers=headers)
        with urlopen(request, timeout=30) as response: return json.load(response)
    try: api('agent/export', {'action':'status','exportId':'unknown'}, authorized=False)
    except HTTPError as exc: assert exc.code == 401
    else: raise AssertionError('Export must require native authorization')
    paths = [ROOT/'qa/media-library/captioned-test.mp4', ROOT/'public/media/travel/story/coffee.jpg']
    before = {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    records = api('register', {'paths':list(map(str,paths))})['items']
    ids = [r['id'] for r in records]
    deadline = time.monotonic()+60
    while True:
        rows = [r for r in api('library')['items'] if r['id'] in ids]
        if all(r['status'] == 'ready' for r in rows): break
        assert time.monotonic() < deadline, 'Import timeout'
        time.sleep(.2)
    run = dict(id=uuid.uuid4().hex, projectId=uuid.uuid4().hex, requestId=uuid.uuid4().hex,
               status='completed', intent='create', version=1, aspect='16:9', mediaIds=ids,
               timeline=[dict(id=uuid.uuid4().hex,mediaId=mid,start=0,end=.5,label='Source '+str(i),reason='Export fixture',locked=False) for i,mid in enumerate(ids)],
               finishing={'captions':[dict(id='caption',start=0,end=.5,text='Source export')], 'originalVolume':.5},
               packaging={'style':'none','text':'none','motion':'none'},
               artifacts=[dict(id='preview',type='preview',title='Preview',text='',path='/missing/preview.mp4')])
    with sqlite3.connect(workspace/'library.sqlite3') as db:
        db.execute('INSERT INTO agent_runs VALUES(?,?,?,?,?)',(run['id'],run['projectId'],run['requestId'],json.dumps(run),time.time()))
    def wait(job):
        deadline = time.monotonic()+120
        while job['status'] in ('queued','running'):
            assert time.monotonic() < deadline, 'Export timeout'
            time.sleep(.2); job = api('agent/export',{'action':'status','exportId':job['id']})['export']
        return job
    for quality in ('1080p','4k'):
        for aspect in ('16:9','9:16','1:1'):
            run['aspect'] = aspect
            with sqlite3.connect(workspace/'library.sqlite3') as db:
                db.execute('UPDATE agent_runs SET record=? WHERE id=?',(json.dumps(run),run['id']))
            job = wait(api('agent/export',{'id':run['id'],'version':1,'resolution':quality})['export'])
            assert job['status'] == 'completed', job['message']
            probe = json.loads(subprocess.check_output([str(resources/'bin/ffprobe'),'-v','error','-show_streams','-show_format','-of','json',job['path']]))
            video = next(s for s in probe['streams'] if s['codec_type'] == 'video')
            long, short = (1920,1080) if quality == '1080p' else (3840,2160)
            assert (video['width'],video['height']) == {'16:9':(long,short),'9:16':(short,long),'1:1':(short,short)}[aspect]
            assert video['codec_name'] == 'h264'
            assert any(s['codec_type'] == 'audio' for s in probe['streams'])
            assert abs(float(probe['format']['duration'])-1) < .15
            subprocess.run([str(resources/'bin/ffmpeg'),'-v','error','-xerror','-i',job['path'],'-f','null','-'],check=True,capture_output=True,timeout=60)
            manifest = json.loads((Path(job['path']).parent/'export.json').read_text())
            assert manifest['timeline'] == run['timeline'] and manifest['finishing'] == run['finishing']
            assert manifest['usesPreview'] is False
            with sqlite3.connect(workspace/'library.sqlite3') as db:
                assert json.loads(db.execute('SELECT record FROM agent_runs WHERE id=?',(run['id'],)).fetchone()[0]) == run
            report['cases'].append(dict(job, aspect=aspect))
            print('PASS',quality,aspect,video['width'],video['height'],flush=True)
    assert before == {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    report['pass'] = True
finally:
    service.terminate()
    try: service.wait(timeout=20)
    except subprocess.TimeoutExpired: service.kill(); service.wait()
    log.close()
    target = workspace/'report.json'; target.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print('REPORT',target,flush=True)
