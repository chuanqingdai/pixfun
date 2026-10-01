"""Real local model + real FFmpeg case walkthrough, isolated from the user's library."""
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import uuid
import subprocess

ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT))
workspace=Path(tempfile.mkdtemp(prefix='pixfun-agent-real-'))
os.environ['PIXFUN_DATA_DIR']=str(workspace)
from desktop_service import Library
from agent_engine import AgentEngine
library=Library(workspace); agent=AgentEngine(library)
report={'workspace':str(workspace),'cases':[]}


def wait(key):
    previous=None; deadline=time.monotonic()+1200
    while time.monotonic()<deadline:
        run=agent.get(key)
        if run['message']!=previous: print(run['message'],flush=True); previous=run['message']
        if run['status'] not in ('queued','running'): return run
        time.sleep(.5)
    agent.action({'id':key,'action':'stop'}); raise TimeoutError('Case exceeded 20 minutes')


def case(label,prompt,ids,expected,project=None):
    payload={'prompt':prompt,'mediaIds':ids,'requestId':uuid.uuid4().hex,'mode':'local'}
    if project:payload['id']=project
    started=time.monotonic(); run=wait(agent.start(payload)['id'])
    report['cases'].append({'case':label,'status':run['status'],'intent':run['intent'],'message':run['message'],
                           'summary':run['summary'],'result':run['resultText'],'seconds':round(time.monotonic()-started,1),
                           'artifacts':run['artifacts'],'timeline':run['timeline'],'pass':run['status']==expected})
    expected_intent={'ambiguous':'clarify','analysis-only':'analyze','semantic-search':'search','story-plan':'plan','rough-cut':'create','revise':'modify','subtitles-only':'subtitles','local-speech':'subtitles'}[label]
    report['cases'][-1]['pass'] &= run['intent']==expected_intent
    if label=='semantic-search': report['cases'][-1]['pass'] &= any(a['type']=='match' and a['title']=='fire.mp4' for a in run['artifacts']) and not any(a['type']=='match' and a['title']=='coffee.mp4' for a in run['artifacts'])
    if label in ('story-plan','rough-cut'): report['cases'][-1]['pass'] &= abs(sum(s['end']-s['start'] for s in run['timeline'])-6)<.1 and all(s['label'] not in ('story beat','Shot') for s in run['timeline'])
    if label=='revise': report['cases'][-1]['pass'] &= abs(sum(s['end']-s['start'] for s in run['timeline'])-7)<.1
    if label=='local-speech': report['cases'][-1]['pass'] &= any(a['type']=='subtitle' and 'glacier' in a['text'].lower() for a in run['artifacts'])
    print(label,run['status'],flush=True)
    (ROOT/'build-native/agent-real-cases.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    return run


try:
    items=library.register([str(ROOT/'public/media/travel/story/coffee.mp4'),str(ROOT/'public/media/travel/story/fire.mp4')])['items']
    ids=[x['id'] for x in items]
    while any(library.get(i)[0]['status'] not in ('ready','error') for i in ids):time.sleep(.2)
    case('ambiguous','处理一下这些素材',ids,'clarify')
    case('analysis-only','只分析这两段素材的画面和剪辑价值，不要生成视频。',ids,'completed')
    case('semantic-search','找出包含篝火的片段，不要合成视频。',ids,'completed')
    story=case('story-plan','只提供一个6秒旅行短片的故事方案，先营地生活后篝火收尾，保留原声。不要渲染。',ids,'completed')
    cut=case('rough-cut','用这两段素材剪一个6秒16:9旅行短片，先营地生活后篝火，每段3秒，保留原声，不加音乐字幕配音。',ids,'review')
    if cut['status']=='review':
        agent.action({'id':cut['id'],'action':'approve'}); rendered=wait(cut['id'])
        report['cases'].append({'case':'real-render','status':rendered['status'],'pass':rendered['status']=='completed','artifacts':rendered['artifacts']})
        case('revise','把结尾的篝火镜头延长1秒，其他保持不变。',ids,'review',cut['projectId'])
    case('subtitles-only','只提取已有字幕，没有字幕则本地识别人声，不要制作视频。',ids[:1],'completed')
    speech=workspace/'ranger-speech.wav'
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(ROOT/'data/travel-long-20260927/Glacier - Archaeology Field Visit.mp4'),'-t','20','-vn','-ar','16000','-ac','1',str(speech)],check=True)
    audio=library.register([str(speech)])['items'][0]['id']
    case('local-speech','请转写这段音频的人声，生成完整字幕，不需要剪辑视频。',[audio],'completed')
    report['capabilities']=agent.models.capabilities()
finally:
    agent.close(); library.close()
    (ROOT/'build-native/agent-real-cases.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({'report':str(ROOT/'build-native/agent-real-cases.json'),'passed':sum(x['pass'] for x in report['cases']),'total':len(report['cases'])}),flush=True)
