"""Real packaged service, bundled codecs and local models; isolated test library.

No fake model, source-module import, developer FFmpeg, or production database writes.
Use --replay-library to reuse the most recent failed task's original sources read-only.
"""
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

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('--replay-library', type=Path)
parser.add_argument('--replay-run')
parser.add_argument('--workspace', type=Path, help='Reuse an isolated packaged-agent test library and its analysis cache')
parser.add_argument('--cases', default='photos,mixed,videos')
args = parser.parse_args()
resources = args.app.resolve()/'Contents/Resources'
workspace = args.workspace.resolve() if args.workspace else Path(tempfile.mkdtemp(prefix='pixfun-packaged-agent-'))
if not workspace.is_dir() or not workspace.name.startswith('pixfun-packaged-agent-'):
    raise ValueError('Only an existing isolated packaged-agent test library may be reused')
token, native = secrets.token_hex(32), secrets.token_hex(32)
env = {**os.environ, 'PATH':str(resources/'bin')+':/usr/bin:/bin:/usr/sbin:/sbin',
       'PIXFUN_DATA_DIR':str(workspace), 'PIXFUN_PUBLIC_DIR':str(resources/'public'),
       'PIXFUN_AGENT_WORKER':str(resources/'agent-model-worker.py'),
       'PIXFUN_MUSIC_DIR':str(resources/'Music'), 'PIXFUN_SERVICE_TOKEN':token,
       'PIXFUN_NATIVE_TOKEN':native, 'PIXFUN_PARENT_PID':str(os.getpid()), 'PYTHONUNBUFFERED':'1'}
env.pop('PIXFUN_EXAMPLE_DIR', None)
report = {'workspace':str(workspace), 'app':str(args.app.resolve()),
          'scope':'Packaged HTTP service + real local models + bundled media tools; not native UI automation', 'cases':[]}
def media(name, *arguments):
    return subprocess.check_output([str(resources/'bin'/name), *map(str,arguments)], timeout=120)

photos = [ROOT/'public/media/travel/story'/name for name in ('coffee.jpg','selfie.jpg','rest.jpg')]
if args.replay_library:
    with sqlite3.connect(args.replay_library.resolve().as_uri()+'?mode=ro', uri=True) as db:
        row = (db.execute('SELECT record FROM agent_runs WHERE id=?',(args.replay_run,)).fetchone() if args.replay_run else
               db.execute("SELECT record FROM agent_runs WHERE json_extract(record,'$.status')='failed' ORDER BY updated DESC LIMIT 1").fetchone())
        failed = json.loads(row[0])
        photos = [Path(db.execute('SELECT source FROM media WHERE id=?',(mid,)).fetchone()[0]) for mid in failed['mediaIds']]
        report['replayedSourceRun'] = failed['id']
        assert photos, 'Failed task has no material'

log = (workspace/'service.log').open('w')
service = subprocess.Popen([str(resources/'backend/pixfun-service/pixfun-service')], env=env,
                           stdout=subprocess.PIPE, stderr=log, text=True)
try:
    ready = json.loads(service.stdout.readline())
    base = 'http://127.0.0.1:'+str(ready['port'])
    def api(path, payload=None):
        request = Request(base+'/api/'+path, data=None if payload is None else json.dumps(payload).encode(),
                          headers={'Authorization':'Bearer '+token,'X-Pixfun-Native':native,'Content-Type':'application/json'})
        with urlopen(request, timeout=30) as response: return json.load(response)
    report['health'] = api('health')
    def wait(run):
        deadline, previous = time.monotonic()+900, None
        while run['status'] in ('queued','running'):
            assert time.monotonic()<deadline, 'Packaged agent timed out'
            if run['message'] != previous:
                print(run['message'], flush=True); previous=run['message']
            time.sleep(1)
            run = next(r for r in api('desktop/agent/runs')['runs'] if r['id']==run['id'])
        return run
    def check(run, ids):
        assert run['status']=='completed', run['message']
        assert not run.get('question'), run['question']
        assert {s['mediaId'] for s in run['timeline']}==set(ids), 'Missing material'
        preview = next(a for a in run['artifacts'] if a['type']=='preview')
        probe = json.loads(media('ffprobe','-v','error','-show_streams','-show_format','-of','json',preview['path']))
        expected = sum(s['end']-s['start'] for s in run['timeline'])
        assert abs(float(probe['format']['duration'])-expected)<.5
        assert any(s['codec_type']=='video' for s in probe['streams'])
        media('ffmpeg','-v','error','-xerror','-i',preview['path'],'-f','null','-')
        return {'preview':preview['path'],'duration':probe['format']['duration'],'streams':probe['streams']}
    for case in args.cases.split(','):
        paths = photos if case=='photos' else [ROOT/'public/media/travel/story/rest.mp4']
        if case=='mixed': paths = [photos[0], *paths]
        print('CASE '+case, flush=True)
        before = {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        ids = [i['id'] for i in api('desktop/register',{'paths':list(map(str,paths))})['items']]
        prompt = '编辑成一个视频，使用全部素材，不加配乐、旁白或字幕。' if case=='photos' else 'Create a travel video using every attached photo and video. Use original sound, no music, narration or text.'
        run = wait(api('desktop/agent/start',{'prompt':prompt,'mediaIds':ids,'requestId':uuid.uuid4().hex,'mode':'local'})['run'])
        entry = {'case':case,'run':run}; report['cases'].append(entry)
        entry.update(check(run, ids))
        image_ids = {i['id'] for i in api('desktop/library')['items'] if i['kind']=='image'}
        assert all(s['end']-s['start'] <= 5 for s in run['timeline'] if s['mediaId'] in image_ids), 'Default still is too long'
        # The same action endpoints used by the editor: save a photo hold, render revision.
        if case=='photos':
            shots = json.loads(json.dumps(run['timeline'])); shots[0]['end'] += .5
            revised = api('desktop/agent/action',{'id':run['id'],'action':'timeline','version':run['version'],'timeline':shots})['run']
            revised = wait(api('desktop/agent/action',{'id':run['id'],'action':'approve'})['run'])
            entry['revision'] = check(revised, ids)
        assert before == {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, 'Source was modified'
        entry['pass'] = True
        print('PASS '+case, flush=True)
    report['pass'] = True
finally:
    service.terminate()
    try: service.wait(timeout=30)
    except subprocess.TimeoutExpired: service.kill(); service.wait()
    log.close()
    destination = workspace/('report-'+uuid.uuid4().hex[:8]+'.json')
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print('REPORT '+str(destination),flush=True)
