"""Use the Mac model gateway and editorial prompts; cache raw evidence for review."""
import json, sys, threading
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from agent_models import ModelGateway
from video_description import DESCRIPTION_PROMPT
DATA=ROOT/'data/landing-cases-v2'
gateway=ModelGateway(DATA); cancel=threading.Event()
try:
    for item in json.loads((DATA/'manifest.json').read_text()):
        key=item['id']; media=ROOT/f'public/media/cases/v3/{key}.mp4'
        speech=DATA/(key+'.speech.json')
        if '--speech' in sys.argv:
            if item['audio'] and (not speech.exists() or speech.stat().st_mtime < media.stat().st_mtime):
                print('Transcribing '+key,flush=True)
                speech.write_text(json.dumps(gateway.transcribe(media,cancel),ensure_ascii=False,indent=2))
                print('Saved '+str(speech),flush=True)
            continue
        result=DATA/(key+'.model.json')
        if result.exists() and result.stat().st_mtime >= media.stat().st_mtime: continue
        cues=json.loads(speech.read_text()).get('cues',[]) if speech.exists() else []
        # Keep the description contract separate from shot JSON. The original combined
        # prompt produced only description drafts, so it must not imply validated cuts.
        prompt=DESCRIPTION_PROMPT+'\nThe contact sheet is sampled every 2 seconds, left to right then top to bottom; black trailing tiles are padding, not footage. Duration: '+str(item['videoDuration'])+'. This is a multi-scene video. Audio is supported only by the supplied transcript; do not infer ambient sounds. Never invent dates, places, people identities, relationships or capture devices. Return the title/full_description contract above, in Chinese (100–200 characters). This is a draft requiring editorial review, not exact cut detection.\nSpeech evidence: '+json.dumps(cues,ensure_ascii=False)+'\nSource metadata (location only if unambiguously established): '+json.dumps([{'page':s['page'],'credit':s['credit']} for s in item['sources']])
        print('Understanding '+key,flush=True)
        value=gateway.ask(prompt,cancel,images=[str(DATA/(key+'-contact.jpg'))],max_tokens=3000)
        result.write_text(json.dumps({'model':'Qwen3-VL-4B · MLX','result':value},ensure_ascii=False,indent=2))
        print('Saved '+str(result),flush=True)
finally: gateway.close()
