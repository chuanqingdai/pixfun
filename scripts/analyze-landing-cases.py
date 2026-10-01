"""Precompute public demo evidence with the installed local model, outside the user's library."""
import json
import sys
import threading
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from agent_models import ModelGateway

folder = ROOT / 'data/landing-cases-20261001'
gateway = ModelGateway(folder)
cancel = threading.Event()
try:
    for source in json.loads((folder / 'sources.json').read_text()):
        output = folder / (source['id'] + '.analysis.json')
        if output.exists():
            continue
        duration = source['duration']
        times = [round(duration * i / 6 + .1, 2) for i in range(6)]
        images = [str(folder / f"{source['id']}-contact.jpg")]
        prompt = '''Analyze these chronological frames as a senior film editor. This is a real continuous source clip, NOT a montage. Ground every observation in the supplied images. Do not invent location names, identities, relationships, sounds, dialogue, motion speed or camera models. No audio evidence is supplied. Write concise natural English. Explain visible action and changes, what is worth keeping, and its potential role in a travel story. Do not manufacture cuts: if the subject, camera and event remain continuous, return ONE shot covering the full source. Separate shots only for a clear scene or meaningful action-stage change supported by frames. Return JSON only with this schema:
{"title":"A concise factual event title","description":"80–120 word chronological description, including useful visual detail and limitations","subjects":["visible subjects, not inferred identities"],"tags":["up to four visual search terms"],"shots":[{"start":0,"end":0,"title":"short meaningful title","description":"what visibly happens and changes","size":"shot size","capture":"observed camera viewpoint","motion":"apparent movement; if uncertain say not verified from sampled frames","role":"suggested story role","recommendation":"Keep or Recommended or Compress","useDuration":4,"reason":"specific editing rationale","caution":"repetition or caveat, or empty string"}],"highlight":{"start":0,"reason":"why this 5-second interval is a useful editorial choice"}}
The highlight is exactly 5 seconds and must fit inside the source. Shot intervals must cover the full source from 0 to its measured duration with no overlaps or gaps. Recommended durations must fit their intervals. Recommendations are editorial judgments, not objective quality scores.
'''+json.dumps({'duration':duration,'frameTimes':times})
        print('Analyzing '+source['id'], flush=True)
        prompt += '\nThe image is a 3-column, 2-row contact sheet. Read left to right, top row then bottom row. These are samples, NOT separate shots. Use at most two shot intervals. Keep the JSON concise.'
        result = gateway.ask(prompt, cancel, images=images, max_tokens=1100)
        output.write_text(json.dumps({'model':'Qwen3-VL-4B · MLX','frameTimes':times,'result':result},ensure_ascii=False,indent=2))
        print(json.dumps(result,ensure_ascii=False), flush=True)
finally:
    gateway.close()
