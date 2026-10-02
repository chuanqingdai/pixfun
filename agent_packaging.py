"""Deterministic, full-frame travel layouts, compiled to real FFmpeg filters.

These are two supported single-panel variants, not all six skill recipes.
Original photo pixels never leave the viewport; motion is editorial, not AI video.
"""
import json
import hashlib
import re
import shutil
from pathlib import Path

VERSION = 1
ROUTING = '''Packaging is supported: gentle full-photo motion, animated short titles,
Editorial Postcard (light) and City Notes (dark) single-panel layouts, and a short graphic reveal.
Return packagingRequest {"style":"keep|none|editorial-postcard|city-notes", "text":"keep|auto|none", "motion":"keep|gentle|none"}.
Travel Short defaults to Editorial Postcard. Other photo edits default to gentle full-photo motion without text.
No effects means style=none,text=none,motion=none; no text means text=none.
Never flag these implemented features as unsupported. Multi-image collages, 3D, tracked text,
cross-dissolves and dialogue captions remain unsupported. A generic request for stylish packaging uses Postcard.
'''

def resolve(value, previous, short=False, prompt=''):
    value = value if isinstance(value, dict) else {}
    result = {**{'style':'editorial-postcard' if short else 'none', 'text':'auto' if short else 'none', 'motion':'gentle'}, **(previous or {})}
    for key, allowed in (('style', ('none','editorial-postcard','city-notes')), ('text', ('auto','none')), ('motion', ('gentle','none'))):
        if value.get(key) in allowed: result[key] = value[key]
    # Explicit negatives override both model interpretation and skill defaults.
    if re.search(r'no (?:effects|animation)|without (?:effects|animation)|不要(?:特效|动效)|不加(?:特效|动效)', prompt, re.I):
        result.update(style='none', text='none', motion='none')
    if re.search(r'keep (?:the )?photos static|static photos|不要运镜|不要推近|图片保持静态', prompt, re.I): result['motion']='none'
    if re.search(r'no (?:text|titles|captions)|without (?:text|titles)|不要(?:文字|字幕)|不加(?:文字|字幕)|无字', prompt, re.I): result['text'] = 'none'
    if result['text'] == 'auto' and result['style'] == 'none': result['style'] = 'editorial-postcard'
    return {key:result[key] for key in ('style','text','motion')}

def title_text(label):
    text = ' '.join(str(label or '').split()).strip(' .:;—-')
    # Never silently clip a long sentence into a misleading title.
    return text if 1 <= len(text.split()) <= 6 and 1 <= len(text) <= 64 else 'Travel moments'

def component(shot, index, count, record, settings, width, height):
    duration = round((shot['end'] - shot['start']) * 30) / 30
    styled = settings['style'] != 'none'
    motion = record['kind'] == 'image' and settings['motion'] == 'gentle'
    # Last shot is a clean visual pause; a single-photo film has a clean tail.
    title = styled and settings['text'] == 'auto' and duration >= 2.5 and (count == 1 or index < count - 1)
    title_end = min(duration - (1.5 if count == 1 else .15), 3.2)
    if title_end < 2.25: title = False
    # Entire source fits in this fixed viewport; no subject detection/cropping needed.
    rect = [round(width*.06), round(height*.10), round(width*.88/2)*2, round(height*(.57 if title else .78)/2)*2] if styled else [0,0,width,height]
    return {'id':shot['id']+'-design', 'shotId':shot['id'], 'assetRefs':[shot['mediaId']],
            'durationFrames':round(duration*30), 'style':settings['style'], 'viewport':rect,
            'motion':motion, 'reveal':styled and index>0 and settings['motion'] != 'none',
            'text':title_text(shot.get('label')) if title else '',
            'animateTitle':settings['motion'] != 'none',
            'index':f'{index+1:02d} / {count:02d}', 'titleEnd':title_end,
            'keyframes':{'title':{'inFrames':9,'outFrames':8,'risePixels':round(height*.01)},
                         'photo':{'startScale':.96,'endScale':.985,'easing':'linear'},
                         'reveal':{'frames':9,'direction':'left-to-right'}},
            'sourceRange':None if record['kind']=='image' else [shot['start'],shot['end']]}

def filters(agent, design, width, height, folder, cancel, overlay_input):
    """Return extra PNG input arguments and a filter graph ending in [picture]."""
    duration = design['durationFrames']/30
    styled = design['style'] != 'none'
    dark = design['style'] == 'city-notes'
    color = '0x17201f' if dark else '0xf4f1e8' if styled else 'black'
    x,y,w,h = design['viewport']
    extra=[]; parts=[]
    if styled or design['motion']:
        # Zoom the padded *canvas*, never the actual photo bounds. 0.96→0.985
        # leaves a visible safety margin throughout, including extreme panoramas.
        sw,sh = max(2,int(w*.96)//2*2), max(2,int(h*.96)//2*2)
        initial=f'[0:v]scale={sw}:{sh}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color={color},setsar=1,fps=30'
        if design['motion']:
            frames=max(1,design['durationFrames']-1)
            initial+=f",zoompan=z='1+0.025*min(on/{frames},1)':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s={w}x{h}:fps=30"
        parts.append(initial+'[image]')
        parts.append(f'color=c={color}:s={width}x{height}:r=30:d={duration}[canvas]')
        if design['reveal']:
            parts.append("[image]format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lte(X,W*min(T/0.3,1)),255,0)':enable='lt(t,0.3)'[reveal]")
            image='reveal'
        else: image='image'
        parts.append(f'[canvas][{image}]overlay=x={x}:y={y}:shortest=1[base]')
    else:
        parts.append(f'[0:v]scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[base]')
    if design['text']:
        helper = shutil.which('pixfun-title')
        if not helper: raise RuntimeError('The bundled title renderer is missing. Rebuild the Mac app; no static fallback was substituted.')
        font = Path(helper).resolve().parent.parent/'Fonts/dm-sans-semibold.ttf'
        if not font.is_file(): font=Path(__file__).resolve().parent/'public/fonts/dm-sans-semibold.ttf'
        tw,th=round(width*.80),round(height*.18)
        request=folder/('title-'+hashlib.sha256(design['id'].encode()).hexdigest()[:20]+'.json'); png=request.with_suffix('.png')
        request.write_text(json.dumps({'text':design['text'],'index':design['index'],'width':tw,'height':th,'dark':dark}),encoding='utf-8')
        agent.command([helper,request,png,font],cancel,30)
        extra=['-loop','1','-framerate','30','-i',png]
        end=design['titleEnd']; rise=design['keyframes']['title']['risePixels']
        fade = f',fade=t=in:st=0.15:d=0.3:alpha=1,fade=t=out:st={end-.27:.3f}:d=0.27:alpha=1' if design['animateTitle'] else ''
        parts.append(f'[{overlay_input}:v]format=rgba{fade}[type]')
        offset = f'+{rise}*pow(1-min(max((t-0.15)/0.3,0),1),3)' if design['animateTitle'] else ''
        parts.append(f"[base][type]overlay=x={round(width*.07)}:y='{round(height*.70)}{offset}':enable='lte(t,{end})':shortest=1[picture]")
    else: parts.append('[base]null[picture]')
    return extra, ';'.join(parts)
