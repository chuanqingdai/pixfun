"""Re-render a saved edit in an isolated library; never alter the original task.

Uses saved shot choices, current renderer, and bundled audio/codecs. No model
inference, generated footage, production writes, or replacement of old previews.
"""
import argparse
import array
import json
import math
import os
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--library', required=True, type=Path)
parser.add_argument('--run', required=True)
parser.add_argument('--app', required=True, type=Path)
args = parser.parse_args()
resources = args.app.resolve() / 'Contents/Resources'
output = Path(tempfile.mkdtemp(prefix='finishing-repair-', dir=ROOT/'build-native'))
workspace = output / 'library'
os.environ['PIXFUN_DATA_DIR'] = str(workspace)
os.environ['PIXFUN_MUSIC_DIR'] = str(resources/'Music')
os.environ['PATH'] = str(resources/'bin') + os.pathsep + os.environ['PATH']
sys.path.insert(0, str(ROOT))
from desktop_service import Library
from agent_engine import AgentEngine
import agent_finishing as finishing
from music_library import catalog, credit

with sqlite3.connect(args.library.resolve().as_uri() + '?mode=ro', uri=True) as db:
    run = json.loads(db.execute('SELECT record FROM agent_runs WHERE id=?', (args.run,)).fetchone()[0])
    sources = [db.execute('SELECT id,source,record,removed FROM media WHERE id=?', (mid,)).fetchone() for mid in run['mediaIds']]
assert run['timeline'], 'Saved edit has no timeline'
assert all(row and Path(row[1]).is_file() for row in sources), 'Missing original source'
original_stats = {row[1]: (Path(row[1]).stat().st_size, Path(row[1]).stat().st_mtime_ns) for row in sources}
original_preview = next((a['path'] for a in run['artifacts'] if a['type'] == 'preview'), None)

class NoModels:
    def close(self): pass

library = Library(workspace)
agent = AgentEngine(library, NoModels())
report = {'sourceRun': args.run, 'scope': 'Saved timeline re-render only; no new model analysis', 'originalPreview': original_preview}
try:
    with library.connect() as db:
        db.executemany('INSERT INTO media VALUES (?,?,?,?)', sources)
    records = {row[0]: json.loads(row[2]) for row in sources}
    records.update({key:value[0] for key,value in catalog().items()})
    wanted = finishing.request({'music':'add','transition':'fade'})
    run.update(id=uuid.uuid4().hex, status='running', stage='render', question='', events=[], progressUpdates=[],
               finishingRequest=wanted, artifacts=[])
    run['finishing'] = finishing.resolve({'music': finishing.background_music(records)}, run.get('finishing'), wanted,
                                        records, sum(s['end']-s['start'] for s in run['timeline']))
    run['packaging'] = {**run.get('packaging', {}), 'motion':'gentle'}
    with library.connect() as db:
        db.execute('INSERT INTO agent_runs VALUES (?,?,?,?,?)', (run['id'],run['projectId'],uuid.uuid4().hex,json.dumps(run),time.time()*1000))
    cancel = threading.Event()
    agent.cancels[run['id']] = cancel
    folder = agent.root/run['id']
    folder.mkdir()
    started = time.monotonic()
    agent.render(run,folder,cancel)
    done = agent.get(run['id'])
    preview = Path(next(a['path'] for a in done['artifacts'] if a['type']=='preview'))
    destination = output/'preview-repaired.mp4'
    shutil.copy2(preview,destination)
    track = records[run['finishing']['music']['mediaId']]
    (output/'music-credits.txt').write_text(credit(track),encoding='utf-8')
    pcm = array.array('f')
    pcm.frombytes(agent.command(['ffmpeg','-v','error','-i',destination,'-vn','-ac','1','-ar','16000','-f','f32le','-'],cancel))
    rms = math.sqrt(sum(x*x for x in pcm)/len(pcm))
    assert rms > .005, 'Audio is effectively silent'
    boundary = run['timeline'][0]['end']-run['timeline'][0]['start']
    def luminance(at):
        return agent.command(['ffmpeg','-v','error','-ss',str(at),'-i',destination,'-frames:v','1',
                              '-vf','scale=1:1,format=gray','-f','rawvideo','-'],cancel)[0]
    cut_light = luminance(boundary)
    normal_light = luminance(boundary/2)
    assert cut_light < 15 and normal_light > cut_light + 10, 'No visible fade at the first boundary'
    assert all((Path(path).stat().st_size,Path(path).stat().st_mtime_ns)==stamp for path,stamp in original_stats.items())
    report.update(passed=True,preview=str(destination),music=track['file']['name'],audioRMS=rms,
                  boundaryLuminance=cut_light,midShotLuminance=normal_light,
                  renderSeconds=round(time.monotonic()-started,2),shots=len(run['timeline']))
finally:
    agent.close()
    library.close()
    (output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('REPORT '+str(output/'report.json'),flush=True)
