"""Parameterised, offline travel cards for HyperFrames.

Route is explicitly a schematic, not a geographic map or actual flight path.
Board animation is a seek-safe, absolute-time flap treatment; no sample flight
numbers, dates, airports or destinations are ever inserted as user facts.
"""
import html
import json
import re
from pathlib import Path


def airport_document(text, duration):
    if not 1 <= len(text.strip()) <= 24 or any(ord(c)<32 or ord(c)>0xffff for c in text):
        raise ValueError('Invalid airport board text.')
    # Official HyperFrames split-flap-board, pinned with its Apache-2.0 license.
    # Keep the original seek-safe mechanism; replace demo data and CDN loading.
    doc = (Path(__file__).parent/'hyperframes-templates/split-flap-board.html').read_text()
    alphabet = ''.join(dict.fromkeys(' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,'+text.upper()))
    if len(text.upper()) > 24: raise ValueError('The uppercase board text is too long.')
    values = dict(boardText=text,flapAlphabet=alphabet,cellCount=len(text.upper()),
                  flipDuration=max(.03,min(.06,(duration-.65)/(len(alphabet)+8))),cellStagger=.012)
    encoded = json.dumps(values,ensure_ascii=True).replace('<','\\u003c')
    doc = re.sub(r'var vars =.*?\{\};',lambda _: 'var vars = '+encoded+';',doc,count=1,flags=re.S)
    doc = re.sub(r'data-composition-variables=\'.*?\'', '', doc,count=1,flags=re.S)
    doc = doc.replace('https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js','gsap.min.js')
    doc = doc.replace('data-duration="3.5"',f'data-duration="{duration}"')
    doc = doc.replace('</style>', '''#sf-bg{inset:570px 100px 130px!important;border-radius:24px;border:1px solid #ffffff25}
#sf-board{top:570px!important;bottom:130px!important}.sf-glyph{font-family:'PingFang SC',monospace!important}
</style>''',1)
    # Leave readable dwell time even for long Chinese text at the 2.5s minimum.
    doc = doc.replace('tl.to(driver, { t: duration, duration: duration, ease: "none" }, 0);',
        'tl.to(driver, { t: duration * 2, duration: duration * .65, ease: "none" }, 0);'
        'tl.to("#sf-bg,#sf-board",{opacity:0,duration:.2},duration-.2);')
    return doc


def page(inner, script, duration):
    return '''<!doctype html><html><head><meta charset="UTF-8">
<script src="gsap.min.js"></script><style>
*{box-sizing:border-box;margin:0}html,body{width:1920px;height:1080px;overflow:hidden;background:transparent}
#main{position:relative;width:1920px;height:1080px;font-family:'PingFang SC',sans-serif;color:#f5f2e9}
.card{position:absolute;left:120px;right:120px;bottom:115px;height:410px;border:1px solid #ffffff30;
border-radius:28px;background:linear-gradient(130deg,#121c22f5,#243536f5);box-shadow:0 16px 45px #0005}
.eyebrow{position:absolute;top:35px;left:48px;font-size:22px;letter-spacing:4px;color:#d8b881}
.label{font-size:48px;font-weight:600;fill:#f5f2e9}.sub{font-size:20px;fill:#b6c4c4;letter-spacing:3px}
.cell{display:inline-flex;position:relative;width:var(--cw);height:100px;perspective:700px;
align-items:center;justify-content:center;border-radius:7px;background:#293235;
font:600 var(--fs)/1 'PingFang SC',monospace;box-shadow:0 8px 10px #0004}
.cell:after{content:'';position:absolute;left:0;right:0;top:50%;height:2px;background:#080d0e}
</style></head><body><div id="main" data-composition-id="main" data-start="0"
data-duration="DURATION" data-width="1920" data-height="1080">INNER</div><script>
const tl=gsap.timeline({paused:true});window.__timelines={main:tl};
SCRIPT
</script></body></html>'''.replace('DURATION',str(duration)).replace('SCRIPT',script).replace('INNER',inner)


def render_document(item):
    duration = float(item['duration'])
    text = str(item['text'])
    if item['kind'] == 'airport': return airport_document(text, duration)
    if item['kind'] == 'route':
        origin, destination = (item.get(k,'').strip() for k in ('origin','destination'))
        if not all(1 <= len(v) <= 24 and not any(ord(c)<32 for c in v) for v in (origin,destination)) or origin.casefold()==destination.casefold():
            raise ValueError('Enter two different route locations.')
        size = min(48, int(590/max(len(origin),len(destination))))
        inner = f'''<div class="card"><div class="eyebrow">JOURNEY · ROUTE SCHEMATIC</div>
<svg width="1680" height="410" viewBox="0 0 1680 410">
<path d="M340 210 Q840 -10 1340 210" fill="none" stroke="#d8b88140" stroke-width="3"/>
<path id="line" d="M340 210 Q840 -10 1340 210" pathLength="1" fill="none" stroke="#d8b881" stroke-width="4" stroke-dasharray="1"/>
<circle cx="340" cy="210" r="8" fill="#d8b881"/><circle cx="1340" cy="210" r="8" fill="#d8b881"/>
<g id="plane"><path d="M21 0 L-17 -9 L-12 -2 L-27 0 L-12 2 L-17 9 Z" fill="#f5f2e9"/></g>
<text x="340" y="287" text-anchor="middle" class="label" style="font-size:{size}px">{html.escape(origin)}</text>
<text x="1340" y="287" text-anchor="middle" class="label" style="font-size:{size}px">{html.escape(destination)}</text>
<text x="340" y="330" text-anchor="middle" class="sub">FROM</text><text x="1340" y="330" text-anchor="middle" class="sub">TO</text>
</svg></div>'''
        paint = '''const p=Math.max(0,Math.min(1,(t-.25)/(duration*.55)));
document.getElementById('line').style.strokeDashoffset=1-p;
const x=340+1000*p,y=210-440*p*(1-p),a=Math.atan2(-440+880*p,1000)*180/Math.PI;
document.getElementById('plane').setAttribute('transform',`translate(${x} ${y}) rotate(${a})`);'''
    else: raise ValueError('Unknown travel graphic.')
    script = f'''const duration={duration};
const driver={{}};let time=0;function paint(t){{{paint}}}
Object.defineProperty(driver,'t',{{get:()=>time,set:v=>{{time=v;paint(v)}}}});
paint(0);tl.to(driver,{{t:duration,duration,ease:'none'}},0);
tl.fromTo('.card',{{opacity:0,y:18}},{{opacity:1,y:0,duration:.25}},0);
tl.to('.card',{{opacity:0,duration:.25}},duration-.25);'''
    return page(inner,script,duration)
