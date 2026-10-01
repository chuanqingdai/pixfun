"""Offline word alignment of narrated examples, using the installed Mac ASR model."""
import json, os, sys
from pathlib import Path
os.environ['HF_HUB_OFFLINE']='1';os.environ['TRANSFORMERS_OFFLINE']='1';os.environ['HF_HUB_DISABLE_TELEMETRY']='1'
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from agent_models import cached_model
import mlx_whisper
DATA=ROOT/'data/landing-cases-v2'
model=cached_model('mlx-community/whisper-large-v3-turbo-q4')
if not model: raise RuntimeError('Install the Mac speech model first; no download fallback.')
for item in json.loads((DATA/'manifest.json').read_text()):
    if not item['audio']: continue
    source=ROOT/f"public/media/cases/v3/{item['id']}.mp4"
    output=DATA/(item['id']+'.aligned.json')
    if output.exists() and output.stat().st_mtime>source.stat().st_mtime: continue
    print('Aligning '+item['id'],flush=True)
    result=mlx_whisper.transcribe(str(source),path_or_hf_repo=model,word_timestamps=True,condition_on_previous_text=False,verbose=False,language='en')
    words=[dict(start=float(w['start']),end=float(w['end']),text=w['word']) for s in result.get('segments',[]) for w in s.get('words',[])]
    output.write_text(json.dumps({'words':words,'text':result.get('text','')},ensure_ascii=False,indent=2))
    print('Saved '+item['id'],flush=True)
