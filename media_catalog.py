"""Native-only asynchronous catalog bridge; never index merely by searching."""
import hashlib
import json
from pathlib import Path
import threading
import uuid
from agent_models import AgentCancelled
from media_evidence import canonical_shots, shot_revision


def source_key(source):
    stat = source.stat()
    return hashlib.sha256(f'{source.resolve()}:{stat.st_size}:{stat.st_mtime_ns}:vf-sample-091-v1'.encode()).hexdigest()


def sampling(agent, source, cancel):
    if cancel.is_set(): raise AgentCancelled()
    folder = agent.root/'catalogs'/source_key(source)
    # VisionFlow 0.9.1 fingerprint contract. Cache hits need neither a helper
    # process nor the model lock, and never unload the resident vision model.
    saved = folder/'observation.json'
    def stamp():
        stat = source.stat()
        return [str(source.resolve()), stat.st_size, stat.st_mtime_ns, stat.st_ino]
    before = stamp()
    if saved.is_file():
        try:
            observation = json.loads(saved.read_text())
            if (isinstance(observation, dict) and observation.get('fingerprint') == before and
                    observation.get('observation_status') == 'complete' and
                    observation.get('frames') and observation.get('shots') and
                    all(Path(f['path']).is_file() for f in observation['frames']) and stamp() == before):
                if cancel.is_set(): raise AgentCancelled()
                return {'status': 'ready', 'observation': observation}
        except (ValueError, KeyError, TypeError, OSError):
            pass  # Missing/corrupt caches are rebuilt, not treated as evidence.
    return agent.models.local({'operation': 'catalog', 'model': 'local-tools', 'action': 'sample',
                              'source': str(source), 'folder': str(folder)}, cancel)


def representative_frames(observation, start, end, limit=3):
    frames = [f for f in observation['frames'] if start <= f['t'] < end and Path(f['path']).is_file()]
    safe = [f for f in frames if all(abs(f['t']-s['start']) >= .12 for s in observation['shots'][1:])]
    frames = safe or frames
    # Temporal coverage plus action evidence, without sending hundreds of frames to VLM.
    chosen = []
    for fraction in (.15, .5, .85)[:limit]:
        candidates = [f for f in frames if f not in chosen]
        if candidates:
            target = start+(end-start)*fraction
            best = min(candidates, key=lambda f: abs(f['t']-target)-min(.3, f.get('metrics', {}).get('change', 0)))
            chosen.append(best)
    action = [f for f in frames if f not in chosen and f.get('metrics', {}).get('change', 0) >= .06]
    if action:
        chosen.append(max(action, key=lambda f: f['metrics']['change']))
    return sorted(chosen, key=lambda f: f['t'])


class MediaCatalog:
    def __init__(self, library, agent):
        self.library, self.agent = library, agent
        self.lock = threading.RLock()
        self.job = None
        self.cancel = threading.Event()

    def entries(self):
        entries, eligible, stale = [], 0, 0
        for item in self.library.list():
            if item['kind'] != 'video': continue
            eligible += 1
            state = item.get('vectorIndex') or {}
            _, source = self.library.get(item['id'])
            if state.get('status') != 'ready': continue
            key = state.get('sourceKey', '')
            if not isinstance(key, str) or len(key) != 64 or any(c not in '0123456789abcdef' for c in key): continue
            if source.is_file() and source_key(source) != key:
                stale += 1; continue
            shots = canonical_shots(item, source)
            revision = shot_revision(shots) if shots else None
            if state.get('shotRevision') != revision:
                stale += 1; continue
            folder = self.agent.root/'catalogs'/key
            if revision: folder = folder/('reviewed-'+revision)
            if (folder/'catalog/shots.sqlite3').is_file():
                entries.append({'mediaId': item['id'], 'folder': str(folder)})
        return entries, eligible, stale

    def status(self):
        entries, total, stale = self.entries()
        with self.lock:
            job = json.loads(json.dumps(self.job)) if self.job else None
        return {'indexed': len(entries), 'total': total, 'stale': stale, 'job': job}

    def start(self, payload):
        action = payload.get('action')
        if action not in ('index', 'search'): raise ValueError('Invalid catalog action')
        query = payload.get('query', '')
        if action == 'search' and (not isinstance(query, str) or not 1 <= len(query.strip()) <= 500):
            raise ValueError('Search requires 1–500 characters')
        ids = payload.get('ids')
        if action == 'index':
            if not isinstance(ids, list) or not ids or len(ids)>1000 or any(not isinstance(i,str) for i in ids):
                raise ValueError('Select 1–1000 registered videos')
            ids = list(dict.fromkeys(ids))
            for key in ids:
                item, source = self.library.get(key)
                if item['kind'] != 'video': raise ValueError('Visual indexing currently supports videos')
        with self.lock:
            if self.job and self.job['status'] == 'running': raise ValueError('Local search or indexing is already running')
            self.cancel = threading.Event()
            self.job = {'id': uuid.uuid4().hex, 'action': action, 'status': 'running', 'done': 0,
                        'total': len(ids or []), 'message': 'Queued for local processing', 'hits': [], 'failures': []}
            response = dict(self.job)
            self.agent.pool.submit(self.run, action, ids or [], query.strip(), self.cancel)
            return {'job': response}

    def update(self, **fields):
        with self.lock: self.job.update(fields)

    def run(self, action, ids, query, cancel):
        try:
            if cancel.is_set(): raise AgentCancelled()
            if action == 'search':
                entries, _, _ = self.entries()
                if not entries: raise ValueError('Build a local visual index first. Search does not analyze videos.')
                self.update(message='Searching indexed frames locally')
                result = self.agent.models.local({'operation':'catalog','model':'SigLIP2','action':'search',
                    'catalogs':entries,'query':query},cancel)
                if cancel.is_set(): raise AgentCancelled()
                self.update(hits=result['hits'], failures=result['unavailable'], message=result['note'])
            else:
                failures = []
                for n,key in enumerate(ids):
                    if cancel.is_set(): raise AgentCancelled()
                    item, source = self.library.get(key)
                    self.update(message=f'Indexing video {n+1}/{len(ids)}')
                    try:
                        if not source.is_file(): raise ValueError('Original is offline')
                        duration = float((item.get('metadata') or {}).get('duration') or 0)
                        if not 0 < duration <= 3600: raise ValueError('Supported duration is up to 60 minutes')
                        stamp = source_key(source)
                        shots = canonical_shots(item, source)
                        revision = shot_revision(shots) if shots else None
                        context = item.get('context') or {}
                        result = self.agent.models.local({'operation':'catalog','model':'SigLIP2','action':'index',
                            'source':str(source),'folder':str(self.agent.root/'catalogs'/stamp),
                            'shots':[{'id':s['id'],'start':s['start'],'end':s['end']} for s in shots],
                            'shotRevision':revision,
                            'context':{'place':context.get('location',''), 'note':item.get('description',''),
                                       'tags':item.get('analysisTags',[])},
                            'speech':((item.get('result') or {}).get('analysis') or {}).get('subtitleCues',[])},cancel)
                        if cancel.is_set(): raise AgentCancelled()
                        if source_key(source) != stamp: raise ValueError('Source changed during indexing')
                        latest, _ = self.library.get(key)
                        current = canonical_shots(latest,source)
                        if (shot_revision(current) if current else None) != revision:
                            raise ValueError('Shot boundaries changed during indexing')
                        self.library.patch(key, vectorIndex={'status':result['status'],'sourceKey':stamp,
                            'shotRevision':revision, 'engineVersion':'0.9.1','message':result.get('message','')})
                        if result['status'] != 'ready': failures.append(key)
                    except AgentCancelled: raise
                    except Exception:
                        failures.append(key)
                    self.update(done=n+1, failures=failures)
                self.update(message='Indexing complete' if not failures else 'Some videos could not be indexed; previous results were kept')
            self.update(status='completed')
        except AgentCancelled:
            self.update(status='cancelled',message='Stopped; completed indexes were kept')
        except Exception as error:
            self.update(status='failed',message=str(error)[:250])

    def stop(self): self.cancel.set()
