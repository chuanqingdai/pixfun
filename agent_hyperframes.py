"""Existing preview pipeline integration; motion graphics never extend the edit."""
import json
from pathlib import Path
import shutil
import zipfile


def validate_title(value):
    if not isinstance(value, dict) or value.get('kind') not in ('none','title','place','route','airport','counter','end'):
        raise ValueError('Choose an available title style.')
    text = value.get('text', '')
    if not isinstance(text, str) or len(text) > 64 or any(ord(c) < 32 for c in text):
        raise ValueError('Use a plain title up to 64 characters.')
    result = {'kind':value['kind'], 'text':text.strip()}
    if value['kind'] == 'route':
        for field in ('origin','destination'):
            label = value.get(field)
            if not isinstance(label,str) or not 1 <= len(label.strip()) <= 24 or any(ord(c)<32 for c in label):
                raise ValueError('Enter departure and arrival names, up to 24 characters each.')
            result[field] = label.strip()
        if result['origin'].casefold() == result['destination'].casefold():
            raise ValueError('Choose two different locations for the route.')
        result['text'] = result['origin'] + ' → ' + result['destination']
    elif value['kind'] != 'none' and not text.strip(): raise ValueError('Enter the title to display.')
    if value['kind'] == 'airport' and (len(text.strip().upper())>24 or any(ord(c)>0xffff for c in text)):
        raise ValueError('Use up to 24 letters, numbers or Chinese characters for the board.')
    if value['kind'] == 'counter':
        total = value.get('total')
        if type(total) is not int or not 1 <= total <= 9999:
            raise ValueError('Enter the actual total, from 1 to 9999. Counts are never inferred from footage.')
        if len(text.strip()) > 24: raise ValueError('Use a counter label up to 24 characters.')
        result['total'] = total
    return result


def items(shots, title, chosen=None):
    from agent_packaging import title_text
    # Keep the opening montage untouched; title the first sufficiently long shot.
    chosen = validate_title(chosen) if chosen else None
    if chosen and chosen['kind']=='none': return []
    if chosen and chosen['kind']=='end':
        total = sum(round((s['end']-s['start'])*30)/30 for s in shots)
        if total < 2.5: return []
        duration = min(total,4.6)
        return [{**chosen,'start':total-duration,'duration':duration,'shotId':shots[-1]['id']}]
    result = []; time = 0
    for shot in shots:
        duration = round((shot['end']-shot['start'])*30)/30
        if duration >= 2.5 and not result:
            result.append({**dict(kind='title', start=time, duration=min(duration,4.6), text=title_text(shot.get('label')) if shot.get('label') else title,
                               shotId=shot['id']), **(chosen or {})})
        time += duration
    return result


def apply(engine, run, folder, source, target, width, height, codec, cancel):
    from agent_packaging import title_text
    chosen = (run.get('finishing') or {}).get('motionTitle')
    spec = items(run['timeline'], title_text(run['timeline'][0].get('label')), chosen)
    if not spec:
        # No space for a legible title: keep the edit rather than adding black frames.
        shutil.copy2(source, target)
        return None
    engine.progress(run['id'], 'Rendering motion titles locally', 'render')
    result = engine.models.hyperframes(spec, engine.root/'hyperframes-cache', cancel)
    current = source
    for index, overlay in enumerate(result['overlays']):
        destination = target if index == len(result['overlays'])-1 else folder/f'hf-pass-{index}.mp4'
        start = overlay['start']
        graph = (f'[1:v]scale={width}:{height}:force_original_aspect_ratio=decrease,'
                 f'format=rgba,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0x00000000,'
                 f'setpts=PTS-STARTPTS+{start}/TB[title];'
                 '[0:v][title]overlay=eof_action=pass:repeatlast=0[v]')
        engine.command(['ffmpeg','-v','error','-y','-i',current,'-i',overlay['path'],
            '-filter_complex_threads','1','-filter_complex',graph,'-map','[v]','-map','0:a:0',
            *codec,'-pix_fmt','yuv420p','-c:a','copy','-movflags','+faststart',destination],cancel,300)
        current = destination
    project_file = folder/f'hyperframes-v{run["version"]}.zip'
    with zipfile.ZipFile(project_file,'w',zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('manifest.json',json.dumps({'engine':result['engine'],'items':spec},ensure_ascii=False,indent=2))
        archive.writestr('README.txt','Generated with VisionFlow 0.9.1 package_hf.py.\n'
            'Install Node.js >=22, FFmpeg and hyperframes@0.8.123.\n'
            'Set HYPERFRAMES_NO_TELEMETRY=1 and HYPERFRAMES_SKIP_SKILLS=1.\n'
            'For each folder: hyperframes render FOLDER -o overlay.mov --format mov --fps 30 --workers 1\n'
            'Transparent graphics only; original user media is not included.\n')
        for overlay in result['overlays']:
            project = Path(overlay['project'])
            for name in ('index.html','hyperframes.json','gsap.min.js'):
                archive.write(project/name,project.name+'/'+name)
        templates = Path(getattr(engine.models,'worker',Path(__file__).parent/'scripts/agent-model-worker.py')).parent/'hyperframes-templates'
        if templates.is_dir():
            for name in ('LICENSE','NOTICE'):
                archive.write(templates/name,'licenses/hyperframes/'+name)
    return str(project_file)
