"""Local-only bridge to VisionFlow 0.9.1's reviewed HyperFrames generators.

Only trusted generated HTML is rendered, never model-supplied HTML or commands.
No npx, download, cloud render, telemetry or automatic installation at runtime.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from agent_process_security import run_motion_render


def counter_steps(total, duration):
    """Leave >=1s at full opacity after the final .4s number entrance."""
    final_start = min(1.6, duration - 2.0)
    intervals = max(1, min(4, int((final_start-.05)/.4)))
    values = list(dict.fromkeys(round(total*k/intervals) for k in range(intervals+1)))
    return [{'t':.05+(final_start-.05)*i/(len(values)-1),'v':str(n)} for i,n in enumerate(values)]


def render(job, vf_root):
    runtime = Path(job['runtime']).resolve()
    node = runtime / 'node'
    cli = runtime / 'node_modules/hyperframes/bin/hyperframes.mjs'
    gsap = runtime / 'node_modules/gsap/dist/gsap.min.js'
    browser = Path(os.environ.get('PIXFUN_HYPERFRAMES_BROWSER','/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'))
    if not all(p.is_file() for p in (node, cli, gsap, browser)):
        raise RuntimeError('HyperFrames runtime is missing. Your existing preview is kept.')
    generator = Path(vf_root)/'scripts/package_hf.py'
    source = generator.read_bytes()
    if hashlib.sha256(source).hexdigest() != '7ddefa6c2ac55a962512fbbf09d28d8e54df7439a3afadd4d22ffbcd97d5710f':
        raise RuntimeError('The motion generator changed since review. Restore the reviewed version; no code was loaded.')
    spec = importlib.util.spec_from_file_location('vf_package_hf', generator)
    hf = importlib.util.module_from_spec(spec)
    # Execute exactly the reviewed bytes, not a second file read after validation.
    exec(compile(source, str(generator), 'exec'), hf.__dict__)
    # System fonts support Chinese without requiring the author's private fonts.
    hf.BASE_CSS = re.sub(r'@font-face\s*\{[^}]+\}', '', hf.BASE_CSS)
    folder = Path(job['folder']).resolve(); folder.mkdir(parents=True, exist_ok=True)
    overlays = []
    for item in job['items']:
        kind = item['kind']; duration = float(item['duration']); text = str(item['text'])
        if kind not in ('title', 'place', 'end', 'route', 'airport', 'counter') or not 1 <= duration <= 10 or not 1 <= len(text) <= 64:
            raise ValueError('Invalid motion-title specification.')
        if kind in ('route','airport'):
            from vf_travel_graphics import render_document
            doc = render_document(item)
        elif kind == 'title':
            doc = hf.el_title(dict(dur=duration, name=text, seal='', date=''), hf.PAL)
            text_width = sum(1 if ord(c)>255 else .6 for c in text)
            font_size = min(100, int(1500/max(1,text_width)))
            doc = doc.replace('font-size:210px', f'font-size:{font_size}px').replace('letter-spacing:12px', 'letter-spacing:2px')
        elif kind == 'place':
            doc = hf.el_place(dict(dur=duration, name=text, sub=''), hf.PAL)
            doc = doc.replace('>地</div>', '></div>').replace('letter-spacing:8px', 'letter-spacing:2px')
            text_width = sum(1 if ord(c)>255 else .6 for c in text)
            doc = doc.replace('font-size:68px', f'font-size:{min(68,int(1500/max(1,text_width)))}px')
        elif kind == 'counter':
            total = item.get('total')
            if type(total) is not int or not 1 <= total <= 9999 or len(text)>24 or duration<2.5:
                raise ValueError('Invalid counter total or label.')
            # The upstream number entrance takes .4s and exit starts at d-.6.
            # Reach the final value early enough for a readable full-opacity hold.
            steps = counter_steps(total, duration)
            doc = hf.el_counter(dict(start=0,end=duration,total=total,label=text,steps=steps), hf.PAL)
            # The upstream example is a stone-lion counter. Never leak its subject.
            doc = doc.replace('>狮</div>', '></div>')
            doc = doc.replace('width:250px', 'width:360px')
            doc = doc.replace('</style>', '.seal{display:none!important}</style>')
        else:
            doc = hf.el_end(dict(seal=''), dict(dur=duration, line1=text, line2=''), hf.PAL)
            doc = doc.replace('</style>', '#l1{max-width:80%;text-align:center;overflow-wrap:anywhere;font-size:64px!important;letter-spacing:2px!important}</style>')
            # Short endings still get a readable hold, not overlapping fixed-time animations.
            doc = doc.replace('duration:0.9,ease:"power2.out"},0.6', 'duration:0.45,ease:"power2.out"},0.15')
            doc = re.sub(r'tl.fromTo\("#(?:l2|seal)"[^\n]+\n', '', doc)
            doc = doc.replace('width:420,duration:0.9', 'width:420,duration:0.5').replace('},1.4);','},0.65);')
        # Empty ornaments do not imply a destination/date/claim that was not supplied.
        doc = doc.replace("font-family:'Brush'", "font-family:'Songti SC',serif")
        doc = doc.replace("font-family:'Kai'", "font-family:'PingFang SC',sans-serif")
        doc = doc.replace('window.__timelines["main"]', '(window.__timelines ||= {})["main"]')
        doc = doc.replace('</style>', '#seal,#date,#pin{display:none!important}</style>')
        # Deny remote resources and browser connections even inside the local server.
        policy = "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
        doc = re.sub(r'(<head[^>]*>)', lambda m: m[0] + '<meta http-equiv="Content-Security-Policy" content="'+policy+'">', doc, count=1, flags=re.I)
        digest = hashlib.sha256((doc + 'hf-0.8.123-isolated-v2').encode()).hexdigest()[:24]
        project = folder/digest; project.mkdir(exist_ok=True)
        (project/'index.html').write_text(doc, encoding='utf-8')
        (project/'hyperframes.json').write_text(json.dumps({'name':kind}), encoding='utf-8')
        shutil.copy2(gsap, project/'gsap.min.js')
        output = project/'overlay.mov'
        if not output.is_file():
            temporary = project/'rendering.mov'
            run_motion_render([str(node),str(cli),'render',str(project),'-o',str(temporary),
                '--format','mov','--fps','30','--workers','1'], runtime, browser, project)
            if not temporary.is_file():
                raise RuntimeError('Isolated motion rendering produced no output. Your previous preview is kept.')
            temporary.replace(output)
        overlays.append({**item,'path':str(output),'project':str(project)})
    return {'engine':'VisionFlow 0.9.1 / HyperFrames 0.8.123','overlays':overlays}
