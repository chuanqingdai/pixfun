"""Version-bound source exports, sharing the preview renderer but not its state.

Only private cache paths are written here. The native save panel owns destination
authorization and atomically installs a completely validated file afterwards.
"""
import copy
import json
from pathlib import Path
import threading
import time
import uuid

from agent_models import AgentCancelled, CapabilityMissing
from music_library import catalog


def profile(resolution, aspect):
    if resolution not in ('1080p', '4k') or aspect not in ('16:9', '9:16', '1:1'):
        raise ValueError('Choose 1080p or 4K with a supported aspect ratio.')
    short, long = (1080, 1920) if resolution == '1080p' else (2160, 3840)
    width, height = {'16:9':(long, short), '9:16':(short, long), '1:1':(short, short)}[aspect]
    return dict(resolution=resolution, width=width, height=height, bitrate='16M' if resolution == '1080p' else '50M')


def codec(settings, encoders):
    if 'h264_videotoolbox ' in encoders:
        return ['-c:v', 'h264_videotoolbox', '-b:v', settings['bitrate'], '-allow_sw', '1']
    if 'libx264 ' in encoders:
        return ['-c:v', 'libx264', '-preset', 'fast', '-crf', '17']
    raise CapabilityMissing('H.264 export encoder is unavailable. Update the app; the preview is kept.')


def fingerprint(source):
    source = Path(source).resolve(strict=True); st = source.stat()
    return [str(source), st.st_size, st.st_mtime_ns, st.st_ino]


class SourceSnapshot:
    def __init__(self, engine, run):
        self.entries = {}; self.identities = {}
        selected = {s['mediaId'] for s in run['timeline']}
        music = (run.get('finishing') or {}).get('music')
        if music: selected.add(music['mediaId'])
        bundled = catalog()
        for mid in selected:
            record, path = bundled[mid] if mid in bundled else engine.library.get(mid)
            reference = record.get('vfCatalog') or {}
            original = reference.get('originalSource')
            if original and Path(original).resolve() != Path(path).resolve():
                raise ValueError('该素材使用 VisionFlow 代理。原片与代理的时间、方向和 HDR 映射尚未验证，暂不能从原片导出；可继续使用预览。')
            self.entries[mid] = (copy.deepcopy(record), Path(path))
            self.identities[mid] = fingerprint(path)
        # The shared renderer only needs selected sources, not unused/offline attachments.
        run['mediaIds'] = list(selected)

    def get(self, mid): return self.entries[mid]

    def verify(self):
        for mid, (_, path) in self.entries.items():
            if fingerprint(path) != self.identities[mid]:
                raise ValueError('Original media changed during export. Export again from the current sources.')


class RenderSession:
    def __init__(self, manager, job_id, sources):
        self.manager = manager; self.job_id = job_id; self.library = sources

    def __getattr__(self, name): return getattr(self.manager.engine, name)

    def progress(self, _run_id, message, stage=None, **fields):
        self.manager.progress(self.job_id, message, **fields)


class VideoExports:
    def __init__(self, engine):
        self.engine = engine; self.lock = threading.RLock(); self.cancels = {}
        with engine.library.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS agent_exports (id TEXT PRIMARY KEY, record TEXT NOT NULL)')
            for key, raw in db.execute('SELECT id,record FROM agent_exports').fetchall():
                job = json.loads(raw)
                if job['status'] in ('queued', 'running'):
                    job.update(status='interrupted', message='Export interrupted. Export again; the existing destination is untouched.')
                    db.execute('UPDATE agent_exports SET record=? WHERE id=?', (json.dumps(job), key))

    def get(self, key):
        with self.engine.library.connect() as db:
            row = db.execute('SELECT record FROM agent_exports WHERE id=?', (key,)).fetchone()
        if not row: raise ValueError('Export not found.')
        return json.loads(row[0])

    def save(self, job):
        with self.engine.library.connect() as db:
            db.execute('INSERT OR REPLACE INTO agent_exports VALUES (?,?)', (job['id'], json.dumps(job)))

    def action(self, payload):
        with self.engine.lock, self.lock:
            action = payload.get('action', 'start')
            if action == 'status': return self.get(payload.get('exportId'))
            if action == 'cancel':
                job = self.get(payload.get('exportId'))
                if job['status'] in ('queued', 'running'):
                    self.cancels[job['id']].set()
                    job.update(status='cancelled', message='Export cancelled. The existing destination is untouched.')
                    self.save(job)
                return job
            if action != 'start': raise ValueError('Unknown export action.')
            if self.engine.closing: raise ValueError('The app is closing.')
            with self.engine.library.connect() as db:
                jobs = [json.loads(r[0]) for r in db.execute('SELECT record FROM agent_exports')]
            if any(j['status'] in ('queued', 'running') for j in jobs):
                raise ValueError('Wait for the current export or cancel it first.')
            run = self.engine.get(payload.get('id'))
            if run['status'] not in ('completed', 'review') or not run['timeline']:
                raise ValueError('Finish planning or editing the timeline before exporting.')
            if type(payload.get('version')) is not int or payload['version'] != run['version']:
                raise ValueError('The timeline changed. Export the current saved version.')
            settings = profile(payload.get('resolution', '1080p'), run['aspect'])
            snapshot = copy.deepcopy(run); sources = SourceSnapshot(self.engine, snapshot)
            key = uuid.uuid4().hex
            job = dict(id=key, runId=run['id'], timelineVersion=run['version'], **settings,
                       status='queued', message='Waiting to export from original media', completed=0,
                       total=len(run['timeline']), createdAt=time.time()*1000)
            cancel = threading.Event(); self.cancels[key] = cancel
            self.save(job)
            self.engine.pool.submit(self.execute, job, snapshot, sources, cancel)
            return job

    def progress(self, key, message, **fields):
        with self.lock:
            if self.cancels[key].is_set(): raise AgentCancelled()
            job = self.get(key)
            job.update(status='running', message=message, **fields); self.save(job)

    def execute(self, job, snapshot, sources, cancel):
        folder = self.engine.root/'exports'/job['id']
        try:
            if cancel.is_set(): raise AgentCancelled()
            folder.mkdir(parents=True, exist_ok=True)
            sources.verify()
            session = RenderSession(self, job['id'], sources)
            output = type(self.engine).render(session, snapshot, folder, cancel, export_profile=job)
            sources.verify()
            manifest = dict(timelineVersion=snapshot['version'], timeline=snapshot['timeline'], aspect=snapshot['aspect'],
                            finishing=snapshot.get('finishing', {}), packaging=snapshot.get('packaging', {}),
                            sources=sources.identities, usesPreview=False, **output)
            (folder/'export.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
            with self.lock:
                if cancel.is_set(): raise AgentCancelled()
                job.update(status='completed', message='Export ready', completed=job['total'], **output)
                self.save(job)
        except Exception as exc:
            with self.lock:
                if isinstance(exc, AgentCancelled):
                    job.update(status='interrupted' if self.engine.closing else 'cancelled', message='Export stopped. The existing destination is untouched.')
                else: job.update(status='failed', message=str(exc)[:600])
                self.save(job)

    def stop(self):
        for cancel in self.cancels.values(): cancel.set()
