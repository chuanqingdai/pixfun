"""Reviewed local v0.9.1/v0.9.2 adapter. One immutable-source catalog per media item.

No discovery, downloads, cloud calls or source writes. The native service chooses
all paths; requests from UI contain registered media IDs, never filesystem paths.
"""
import json
import math
import copy
from pathlib import Path
from vf_agent import sampling
from vf_agent.storage import atomic_json, fingerprint, digest


def sample(source, folder):
    source, folder = Path(source), Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    saved = folder / 'observation.json'
    stamp = fingerprint(source)
    if saved.is_file():
        observation = json.loads(saved.read_text())
        if (observation.get('fingerprint') == stamp and
                observation.get('observation_status') == 'complete' and
                all(Path(f['path']).is_file() for f in observation['frames'])):
            return {'status': 'ready', 'observation': observation}
    try:
        observation = sampling.observe(source, folder/'frames', log=lambda _: None)
    except ValueError as error:
        if str(error).startswith(('HDR requires', 'Rotated video requires')):
            return {'status': 'unsupported', 'message': str(error)}
        raise
    if observation['observation_status'] != 'complete':
        raise ValueError('Sampling is incomplete; previous results were kept')
    if fingerprint(source) != stamp:
        raise ValueError('Source changed during sampling')
    atomic_json(saved, observation)
    return {'status': 'ready', 'observation': observation}


def index(source, folder, context, speech, shots=None, revision=None):
    from vf_agent import shot_library
    result = sample(source, folder)
    if result['status'] != 'ready': return result
    folder = Path(folder)
    observation = copy.deepcopy(result['observation'])
    mapping = {}
    if shots:
        expected = digest([[s['id'],s['start'],s['end']] for s in shots])
        if revision != expected: raise ValueError('Shot revision mismatch')
        previous, seen = 0., set()
        for s in shots:
            start, end = s['start'], s['end']
            if (not isinstance(s['id'],str) or s['id'] in seen or
                    any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in (start,end)) or
                    start != previous or not start < end <= observation['observed_end_s']+1e-6):
                raise ValueError('Invalid reviewed shot intervals')
            previous = end; seen.add(s['id'])
            mapping[digest([observation['asset_id'],start,end])[:32]] = s['id']
        if abs(previous-observation['observed_end_s']) > .1: raise ValueError('Incomplete reviewed shot coverage')
        observation['shots'] = [{'shot_id':s['id'],'start':s['start'],'end':s['end']} for s in shots]
        folder = folder/('reviewed-'+revision)
        folder.mkdir(parents=True,exist_ok=True)
    manifest = folder/'manifest.json'
    report = folder/'sampling.json'
    name = Path(source).name
    atomic_json(manifest, {'assets': [{'name': name, 'approved': True}]})
    atomic_json(report, {'schema': 1, 'project': str(folder/'project'), 'manifest': str(manifest),
        'assets': [{'name': name, 'status': 'pending_review', 'observation': observation,
                    'context': context, 'speech': speech, 'candidates': []}]})
    counts = shot_library.import_report(report, folder/'catalog', log=lambda _: None)
    atomic_json(folder/'shot-map.json', mapping)
    return {'status': 'ready', 'counts': counts}


def search(catalogs, query):
    from vf_agent import shot_library
    # Reuse one model and one query embedding across all per-asset catalogs.
    encoders = {}
    hits, failures = [], []
    for entry in catalogs:
        try:
            root = Path(entry['folder'])/'catalog'
            mapping_path = Path(entry['folder'])/'shot-map.json'
            mapping = json.loads(mapping_path.read_text()) if mapping_path.is_file() else {}
            with shot_library.connect(root) as con:
                spec = json.loads(dict(con.execute('SELECT key,value FROM settings'))['model_spec'])
            revision = spec['revision']
            if revision not in encoders:
                encoder = shot_library.Encoder(revision=revision)
                vector = encoder.encode(text=query)
                class QueryEncoder:
                    def __init__(self, spec, value): self.spec, self.value = spec, value
                    def encode(self, **kwargs): return self.value
                encoders[revision] = QueryEncoder(encoder.spec, vector)
            for row in shot_library.Library(root, encoders[revision]).search(query, mode='visual', k=10):
                match = row['match']
                hits.append({'mediaId': entry['mediaId'], 'shotId': mapping.get(row['id'],row['id']),
                    'shotStart':row['start'], 'boundarySource':'reviewed' if row['id'] in mapping else 'detected',
                    'start': match.get('match_t', row['start']), 'end': row['end'],
                    'similarity': match.get('similarity', 0), 'label': 'Visual match'})
        except Exception:
            # No private paths or raw encoder errors in the UI response.
            failures.append(entry['mediaId'])
    hits.sort(key=lambda h: (-h['similarity'], h['mediaId'], h['start']))
    return {'hits': hits[:100], 'unavailable': failures,
            'note': 'Visual similarity is not confidence. Review the matched frame.'}


def handle(job):
    action = job['action']
    if action == 'sample': return sample(job['source'], job['folder'])
    if action == 'index': return index(job['source'], job['folder'], job.get('context', {}), job.get('speech', []),job.get('shots'),job.get('shotRevision'))
    if action == 'search': return search(job['catalogs'], job['query'])
    raise ValueError('Unsupported catalog operation')
