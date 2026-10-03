"""Read-only case audit and isolated re-edit. Never modifies the production library."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import re

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--library', required=True, type=Path)
parser.add_argument('--run', required=True)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--render', action='store_true')
args = parser.parse_args()
output = args.output.resolve()
assert output.is_relative_to(ROOT / 'build-native'), 'Only project-local case output is supported'
output.mkdir(parents=True, exist_ok=True)
os.environ['PATH'] = str(ROOT/'build-desktop/media/bin') + os.pathsep + os.environ['PATH']
sys.path.insert(0, str(ROOT))

def write(name, data):
    (output/name).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

def command(params, timeout=300):
    result = subprocess.run(list(map(str, params)), capture_output=True, timeout=timeout)
    if result.returncode: raise RuntimeError(result.stderr.decode(errors='replace')[-4000:])
    return result.stdout

with sqlite3.connect(args.library.resolve().as_uri()+'?mode=ro', uri=True) as db:
    source_run = json.loads(db.execute('SELECT record FROM agent_runs WHERE id=?', (args.run,)).fetchone()[0])
    rows = [db.execute('SELECT id,source,record,removed FROM media WHERE id=?', (mid,)).fetchone() for mid in source_run['mediaIds']]
assert all(row and Path(row[1]).is_file() for row in rows), 'Missing case source'
records = {row[0]:json.loads(row[2]) for row in rows}
names = {record['file']['name']:mid for mid,record in records.items()}
if not args.render:
    write('original-run.json', source_run)
    write('media.json', [{'id':row[0], 'path':row[1], 'record':records[row[0]]} for row in rows])
    for row in rows:
        record = records[row[0]]; name = record['file']['name']
        target = output/(name+'.png')
        source = row[1]
        if record['kind'] == 'image':
            from photo_source import prepare_photo
            source = prepare_photo(source, output/'photos', command)
            graph = 'scale=480:270:force_original_aspect_ratio=decrease,pad=480:270:(ow-iw)/2:(oh-ih)/2'
        else:
            duration = record['metadata']['duration']
            graph = f'fps={3/duration},scale=320:180:force_original_aspect_ratio=decrease,pad=320:180:(ow-iw)/2:(oh-ih)/2,tile=3x1'
        command(['ffmpeg','-v','error','-y','-i',source,'-vf',graph,'-frames:v','1',target])
        print(name, '=>', target, flush=True)
    sys.exit(0)

import copy
import hashlib
import threading
import time
import uuid
from desktop_service import Library
from agent_engine import AgentEngine, validate_timeline
from travel_skill import resolve_skill, DEFAULT_SKILL, coverage_report, validate_story_structure
import agent_finishing as finishing
from music_library import catalog, credit

class NoModels:
    def close(self): pass

plan = json.loads((output/'rearrangement.json').read_text())
shots = [{**shot,'mediaId':names[shot.pop('file')]} for shot in copy.deepcopy(plan['shots'])]
shots = validate_timeline(shots, records)
validate_story_structure(shots, records)
coverage = coverage_report(shots, records)
assert not coverage['requiresDecision']
write('coverage.json', coverage)
write('timeline.json', shots)
workspace = output/'library'
os.environ['PIXFUN_DATA_DIR'] = str(workspace)
library = Library(workspace)
agent = AgentEngine(library, NoModels())
stats = {row[1]:(Path(row[1]).stat().st_size,Path(row[1]).stat().st_mtime_ns) for row in rows}
try:
    with library.connect() as db:
        db.executemany('INSERT OR REPLACE INTO media VALUES (?,?,?,?)',rows)
    duration = sum(s['end']-s['start'] for s in shots)
    run = copy.deepcopy(source_run)
    run.update(id=uuid.uuid4().hex, projectId=uuid.uuid4().hex, status='running', stage='render', version=1,
        artifacts=[], timelineHistory=[], timeline=shots, finishing=plan['finishing'],
        packaging={'style':'none','text':'none','motion':'gentle'}, skillExecution=resolve_skill(DEFAULT_SKILL),
        finishingRequest={'music':'add','transition':'keep'}, events=[], progressUpdates=[], duration=duration,
        prompt='Rearrange the 14-source case against Travel Vlog; isolated review copy.',
        storySummary=plan['summary'], resultText=plan['limitations'])
    with library.connect() as db:
        db.execute('INSERT INTO agent_runs VALUES (?,?,?,?,?)',(run['id'],run['projectId'],uuid.uuid4().hex,json.dumps(run),time.time()*1000))
    folder = agent.root/run['id']; folder.mkdir()
    cancel = threading.Event(); agent.cancels[run['id']] = cancel
    agent.render(run,folder,cancel)
    rendered = agent.get(run['id'])
    video = Path(next(a['path'] for a in rendered['artifacts'] if a['type']=='preview'))
    # Use a fresh filename; all original previews and editor drafts stay untouched.
    import shutil
    destination = output/'rearranged-review.mp4'
    # This case export adds measured two-pass loudness, without silently changing
    # the editor's stored volume settings or claiming that its renderer does this.
    measured = subprocess.run(['ffmpeg','-hide_banner','-nostats','-i',str(video),'-vn',
        '-af','loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json','-f','null','-'],capture_output=True,text=True,timeout=300)
    assert measured.returncode == 0
    (output/'loudness-pass1.log').write_text(measured.stderr)
    values = json.loads(measured.stderr[measured.stderr.rfind('{'):measured.stderr.rfind('}')+1])
    normalize = ('loudnorm=I=-16:TP=-1.5:LRA=11:linear=true'
        f":measured_I={values['input_i']}:measured_TP={values['input_tp']}"
        f":measured_LRA={values['input_lra']}:measured_thresh={values['input_thresh']}:offset={values['target_offset']}")
    command(['ffmpeg','-v','error','-y','-i',video,'-map','0:v:0','-map','0:a:0',
        '-c:v','copy','-af',normalize,'-c:a','aac','-b:a','192k','-ar','48000','-ac','2','-movflags','+faststart',destination])
    probe = json.loads(command(['ffprobe','-v','error','-show_format','-show_streams','-of','json',destination]))
    command(['ffmpeg','-v','error','-xerror','-i',destination,'-f','null','-'])
    scan = subprocess.run(['ffmpeg','-hide_banner','-nostats','-i',str(destination),'-vf','blackdetect=d=0.02:pix_th=0.1,freezedetect=n=-50dB:d=1',
        '-af','ebur128=peak=true,silencedetect=n=-50dB:d=0.2','-f','null','-'],capture_output=True,text=True,timeout=300)
    (output/'scan.log').write_text(scan.stderr)
    assert scan.returncode == 0
    assert all((Path(path).stat().st_size,Path(path).stat().st_mtime_ns)==stamp for path,stamp in stats.items())
    track = catalog()[plan['finishing']['music']['mediaId']][0]
    (output/'music-credits.txt').write_text(credit(track))
    loudness_summary = scan.stderr.rsplit('Summary:',1)[-1]
    integrated = re.search(r'I:\s+(-?[\d.]+) LUFS',loudness_summary)
    peak = re.search(r'Peak:\s+(-?[\d.]+) dBFS',loudness_summary)
    write('qa.json', {'status':'NEEDS_REVIEW','sourceRun':args.run,'newRun':run['id'],
        'video':str(destination),'sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),
        'probe':probe,'coverage':coverage,'fullDecode':'PASS','sourceFilesUnchanged':True,
        'finalAudio':{'integratedLUFS':float(integrated[1]) if integrated else None,
                      'truePeakDBTP':float(peak[1]) if peak else None,'method':'Two-pass loudnorm; final AAC remeasured with ebur128'},
        'scope':'Three sampled frames per video and each photo; not continuous audiovisual review.',
        'limitations':plan['limitations'], 'skillPending':run['skillExecution']['pending']})
    print('VIDEO '+str(destination),flush=True)
finally:
    agent.close(); library.close()
