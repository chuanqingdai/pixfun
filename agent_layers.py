"""Manual, timeline-bound layers. No model text is interpreted as a command/path."""
import hashlib
import json
import shutil
from pathlib import Path


def validate(value, out, duration, number, shots=None):
    muted = value.get('originalMuted', False)
    if not isinstance(muted, bool): raise ValueError('Invalid original sound mute state.')
    out['originalMuted'] = muted
    captions = value.get('captions') or []
    audio = value.get('clipAudio') or []
    seams = value.get('seams') or []
    for entries in (captions, audio, seams):
        if not isinstance(entries, list) or len(entries) > 80: raise ValueError('Use at most 80 items per layer.')
    ids = set(); last = 0
    out['captions'] = []
    for cue in captions:
        if not isinstance(cue, dict): raise ValueError('Invalid caption.')
        number(cue.get('start'), 0, duration)
    for cue in sorted(captions, key=lambda c: c.get('start', 0) if isinstance(c, dict) else 0):
        if not isinstance(cue, dict): raise ValueError('Invalid caption.')
        key, text = cue.get('id'), cue.get('text')
        if not isinstance(key, str) or not key or len(key) > 100 or key in ids: raise ValueError('Caption IDs must be unique.')
        if not isinstance(text, str) or not text.strip() or len(text) > 180 or any(ord(c) < 32 and c != '\n' for c in text):
            raise ValueError('Use 1–180 characters of plain caption text.')
        start = number(cue.get('start'), last, duration)
        end = number(cue.get('end'), start + .25, duration)
        out['captions'].append(dict(id=key, text=text.strip(), start=start, end=end)); last=end; ids.add(key)
    ids=set(); out['clipAudio']=[]
    for entry in audio:
        if not isinstance(entry, dict): raise ValueError('Invalid clip audio.')
        key=entry.get('shotId'); mute=entry.get('muted', False)
        if not isinstance(key,str) or not key or key in ids or not isinstance(mute,bool): raise ValueError('Invalid clip audio reference.')
        if shots is not None and not any(s['id']==key for s in shots): raise ValueError('Audio clip no longer exists.')
        out['clipAudio'].append(dict(shotId=key,volume=number(entry.get('volume',1),0,1),muted=mute)); ids.add(key)
    ids=set(); out['seams']=[]
    for entry in seams:
        if not isinstance(entry,dict): raise ValueError('Invalid transition seam.')
        left,right=entry.get('afterShotId'),entry.get('beforeShotId')
        if not isinstance(left,str) or not isinstance(right,str) or not left or not right or left==right or (left,right) in ids:
            raise ValueError('Invalid transition seam reference.')
        if entry.get('kind') not in ('none','fade'): raise ValueError('Use a cut or fade through black.')
        length=number(entry.get('duration',.25),.05,1)
        if shots is not None and not any(a['id']==left and b['id']==right for a,b in zip(shots,shots[1:])):
            raise ValueError('Transition clips are no longer adjacent.')
        out['seams'].append(dict(afterShotId=left,beforeShotId=right,kind=entry['kind'],duration=length)); ids.add((left,right))
    return out


def clip_gain(finish, shot_id):
    entry=next((a for a in finish.get('clipAudio',[]) if a['shotId']==shot_id),{})
    return 0 if entry.get('muted') else entry.get('volume',1)


def seam(finish, left, right):
    return next((s for s in finish.get('seams',[]) if s['afterShotId']==left['id'] and s['beforeShotId']==right['id']),finish['transition'])


def burn_captions(engine, run, folder, source, target, finish, width, height, duration, codec, cancel):
    """Burn the same subtitle pixels into the preview that is later copied on export."""
    helper=shutil.which('pixfun-title')
    if not helper: raise ValueError('The bundled caption renderer is missing. Rebuild the Mac app.')
    font=Path(helper).resolve().parent.parent/'Fonts/dm-sans-semibold.ttf'
    if not font.is_file(): font=Path(__file__).resolve().parent/'public/fonts/dm-sans-semibold.ttf'
    cues=finish.get('captions',[])
    current=source
    for offset in range(0,len(cues),8):
        batch=cues[offset:offset+8]
        engine.progress(run['id'],f'Rendering captions {offset+1}–{offset+len(batch)}/{len(cues)}','render')
        args=['ffmpeg','-v','error','-y','-i',current]; filters=['[0:v]setpts=PTS-STARTPTS[captionbase]']
        for index,cue in enumerate(batch):
            key=hashlib.sha256(cue['text'].encode()).hexdigest()[:20]
            request=folder/f'caption-{width}-{height}-{key}.json'; png=request.with_suffix('.png')
            request.write_text(json.dumps(dict(text=cue['text'],index='',width=round(width*.84),height=round(height*.17),dark=True,caption=True)),encoding='utf-8')
            engine.command([helper,request,png,font],cancel,30)
            args+=['-loop','1','-framerate','30','-i',png]
            filters.append(f'[{index+1}:v]format=rgba[c{index}]')
            base='captionbase' if index==0 else f'v{index-1}'
            filters.append(f"[{base}][c{index}]overlay=x=(W-w)/2:y=H-h-H*0.045:enable='gte(t,{cue['start']})*lt(t,{cue['end']})':shortest=1[v{index}]")
        destination=target if offset+8>=len(cues) else folder/f'v{run["version"]}-captions-{offset}.mp4'
        engine.command(args+['-filter_complex_threads','1','-filter_complex',';'.join(filters),'-map',f'[v{len(batch)-1}]','-map','0:a:0','-map_metadata','0',
            '-t',str(duration),*codec,'-pix_fmt','yuv420p','-c:a','copy','-movflags','+faststart',destination],cancel,300)
        current=destination
