"""Optional upstream aesthetic inference; requires explicitly trusted local weights.

PIXFUN_BEAUTY_MANIFEST is an administrator-configured JSON file, not a model or
media input. It pins ranker/AVA files by SHA-256. Pickle is executable: never set
this variable to a manifest from an untrusted upload. No heuristic replacement.
"""
import hashlib
import json
import math
import os
from pathlib import Path


def configuration():
    path = os.environ.get('PIXFUN_BEAUTY_MANIFEST')
    if not path: return None
    doc = json.loads(Path(path).read_text())
    if doc.get('tier') not in ('full','slim'): raise ValueError('Specify the trained aesthetic feature tier.')
    for key in ('ranker','ava'):
        entry = doc[key]; source = Path(entry['path'])
        if not source.is_absolute() or not source.is_file() or source.stat().st_size > 128*1024*1024:
            raise ValueError('Trusted aesthetic weights are missing.')
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('Aesthetic weight checksum mismatch.')
    return doc


def score(images):
    config = configuration()
    if not config: raise ValueError('Private aesthetic weights are not configured. No substitute score was generated.')
    if not isinstance(images, list) or not 1 <= len(images) <= 400: raise ValueError('Select 1–400 source frames.')
    from vf_agent import aesthetic, ranker
    aesthetic.AVA_HEAD = config['ava']['path']
    try:
        features = aesthetic.features(images, tier=config['tier'])
        _, _, values = ranker.predict(features, config['ranker']['path'])
        values = [float(v) for v in values]
        if len(values) != len(images) or not all(math.isfinite(v) for v in values): raise ValueError('Invalid aesthetic predictions.')
        # Tied images receive the same within-project percentile, not confidence.
        percentiles = [round(100*sum(w < v for w in values)/max(1,len(values)-1),1) for v in values]
        return {'scores':values,'percentiles':percentiles,'source':'VisionFlow trained aesthetic ranker',
                'note':'Relative to these source frames; not an absolute quality score.'}
    finally:
        aesthetic._sg = None; ranker._m = None
