"""Fresh real-local inference checks, reusing only the explicitly isolated test cache."""
import json
import os
from pathlib import Path
import sys
import time
import uuid
import subprocess

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
prior = json.loads((ROOT / 'build-native/agent-real-cases.json').read_text())
workspace = Path(prior['workspace'])
if not workspace.name.startswith('pixfun-agent-real-') or not workspace.is_dir():
    raise RuntimeError('Isolated real-model fixture library is unavailable.')
os.environ['PIXFUN_DATA_DIR'] = str(workspace)
from desktop_service import Library
from agent_engine import AgentEngine

library = Library(workspace)
agent = AgentEngine(library)
destination = ROOT / 'qa/agent-capability-audit/current-real-cases.json'
report = {'startedAt': time.time(), 'scope': 'Real local routing, report writing, planning and rendering; source understanding reused from isolated test cache.', 'cases': []}

def wait(key):
    deadline = time.monotonic() + 360
    last = None
    while time.monotonic() < deadline:
        run = agent.get(key)
        if run['message'] != last:
            print(run['message'], flush=True); last = run['message']
        if run['status'] not in ('queued', 'running'): return run
        time.sleep(.25)
    agent.action({'id': key, 'action': 'stop'})
    raise TimeoutError('Acceptance case timed out after six minutes.')

def start(name, prompt, ids, check):
    began = time.monotonic()
    run = wait(agent.start({'prompt': prompt, 'mediaIds': ids, 'requestId': uuid.uuid4().hex, 'mode': 'local'})['id'])
    row = {'case': name, 'seconds': round(time.monotonic()-began, 1), 'pass': bool(check(run)), 'run': run}
    report['cases'].append(row)
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(name, row['pass'], flush=True)
    return run

try:
    records = library.list()
    ids = [r['id'] for r in records if r['file']['name'] in ('coffee.mp4', 'fire.mp4')]
    if len(ids) != 2: raise RuntimeError('Expected the two public camping fixtures.')
    start('analysis-report', '只分析这两段素材：总体有哪些内容，每个文件适合怎么用？不要制作视频。', ids,
          lambda r: r['status']=='completed' and r['intent']=='analyze' and r.get('analysisReport',{}).get('synthesized') is True
          and len(r['analysisReport']['materials'])==2 and len(r['analysisReport']['overview'])>30
          and all(x['content'] and x['suggestion'] for x in r['analysisReport']['materials']) and not r['timeline'])
    start('find-campfire', '找出包含篝火的片段，给出对应时间，不要合成视频。', ids,
          lambda r: r['status']=='completed' and r['intent']=='search' and any(a['type']=='match' and a['title']=='fire.mp4' for a in r['artifacts'])
          and not any(a['type']=='match' and a['title']=='coffee.mp4' for a in r['artifacts']))
    cut = start('six-second-plan', '用这两段素材剪一个6秒16:9视频，先营地咖啡后篝火，每段3秒，保留原声，不添加音乐、字幕或配音。', ids,
          lambda r: r['status']=='review' and len(r['timeline'])==2 and abs(sum(s['end']-s['start'] for s in r['timeline'])-6)<.1)
    if cut['status']=='review':
        began=time.monotonic(); rendered=wait(agent.action({'id':cut['id'],'action':'approve'})['id'])
        preview=next((a for a in rendered['artifacts'] if a['type']=='preview'),None)
        probe={}
        if preview and Path(preview['path']).is_file():
            probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',preview['path']]))
        video=next((s for s in probe.get('streams',[]) if s['codec_type']=='video'),{})
        passed=rendered['status']=='completed' and abs(float(probe.get('format',{}).get('duration',0))-6)<.15 and video.get('width',0)*9==video.get('height',1)*16
        report['cases'].append({'case':'rendered-mp4','seconds':round(time.monotonic()-began,1),'pass':passed,'probe':probe,'run':rendered})
    start('unsupported-edit', '请用这些素材生成视频，必须添加自动生成的配乐、配音和转场。', ids,
          lambda r: r['status']=='clarify' and not r['timeline'] and not any(a['type']=='preview' for a in r['artifacts']))
finally:
    agent.close(); library.close()
    report['finishedAt']=time.time()
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({'passed':sum(c['pass'] for c in report['cases']),'total':len(report['cases']),'report':str(destination)}),flush=True)
if len(report['cases'])!=5 or not all(c['pass'] for c in report['cases']): sys.exit(1)
