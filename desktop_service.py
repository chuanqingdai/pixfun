"""Private desktop service: reference-only imports, SQLite and cancellable local analysis.

Never run this as a public server. The Electron parent supplies per-launch secrets
and grants file access only after a native picker/drop. The web app stays separate.
"""
from __future__ import annotations

import concurrent.futures
import fcntl
from contextlib import contextmanager
import hmac
import json
import mimetypes
import os
from pathlib import Path
import re
import signal
import sqlite3
import subprocess
import threading
import time
import uuid
from urllib.parse import urlparse, unquote

import app as engine
from photo_source import prepare_photo
from agent_engine import AgentEngine
from video_description import VideoDescriptions
from shot_analysis import ShotAnalyses

VIDEO = {'.mp4', '.mov', '.m4v', '.mkv', '.webm', '.avi', '.mts', '.m2ts', '.ogv'}
PHOTO = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif', '.heic', '.heif', '.bmp', '.tif', '.tiff'}
AUDIO = {'.mp3', '.wav', '.m4a', '.aac', '.flac', '.ogg', '.aiff', '.aif', '.opus'}
FINAL = {'ready', 'error', 'cancelled'}


class Cancelled(Exception):
    pass


class Library:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.path = self.directory / 'library.sqlite3'
        self.lock = threading.RLock()
        self.cancel = {}
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        with self.connect() as db:
            db.execute('PRAGMA journal_mode=WAL')
            db.execute('CREATE TABLE IF NOT EXISTS media (id TEXT PRIMARY KEY, source TEXT UNIQUE NOT NULL, record TEXT NOT NULL, removed INTEGER NOT NULL DEFAULT 0)')
            db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY, record TEXT NOT NULL, updated INTEGER NOT NULL)')
        # Interrupted work is retained and retried explicitly, never silently lost.
        for record in self.list():
            if record['status'] not in FINAL:
                self.patch(record['id'], status='cancelled', error='Analysis was interrupted. Retry to continue.')

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        try:
            with db:
                yield db
        finally:
            db.close()

    def list(self):
        with self.connect() as db:
            rows = db.execute('SELECT record, source FROM media WHERE removed=0 ORDER BY rowid').fetchall()
        records = []
        for raw, source in rows:
            record = json.loads(raw)
            if not Path(source).is_file():
                record.update(status='error', missing=True, error='Original file not found. Locate it to reconnect this item.')
            elif record.get('status') == 'ready' and record.get('kind') == 'video':
                analysis = (record.get('result') or {}).get('analysis') or {}
                if not analysis.get('subtitleCues') or analysis.get('subtitleState') == 'sidecar':
                    track = engine.local_subtitle_track(Path(source), analysis.get('subtitleSignature'))
                    if track:
                        result = {**(record.get('result') or {}), 'analysis': {**analysis, **track}}
                        record = self.patch(record['id'], result=result)
            records.append(record)
        return records

    def get(self, media_id):
        with self.connect() as db:
            row = db.execute('SELECT record, source FROM media WHERE id=? AND removed=0', (media_id,)).fetchone()
        if not row:
            raise FileNotFoundError('Media not found')
        return json.loads(row[0]), Path(row[1])

    def install_example(self, directory):
        """Index the bundled example once. Never copy media or resurrect removed entries."""
        root = Path(directory).resolve()
        manifest = root / 'manifest.json'
        if not manifest.is_file():
            return
        sample = json.loads(manifest.read_text())
        source = (root / sample['filename']).resolve()
        if source.parent != root or not source.is_file():
            raise ValueError('Bundled example is missing or outside its directory')
        record = sample['record']
        # Keep authored sample copy separate from regenerable model output.
        # Existing analysis, progress and user metadata must remain untouched.
        record['sampleCopy'] = record.get('videoDescription')
        media_id = record['id']
        if not media_id.startswith('example-') or record.get('isExample') is not True:
            raise ValueError('Invalid bundled example identity')
        with self.lock, self.connect() as db:
            existing = db.execute('SELECT record FROM media WHERE id=?', (media_id,)).fetchone()
            if existing:
                # Bundle relocation must not discard favorites, new analysis or soft removal.
                saved = json.loads(existing[0])
                if saved.get('isExample'):
                    saved['sampleCopy'] = record['sampleCopy']
                    # Refresh only our unmodified prepared copy, never model/user output.
                    if (saved.get('videoDescription') or {}).get('model') == 'Prepared editorial example':
                        saved['videoDescription'] = record.get('videoDescription')
                    db.execute('UPDATE media SET source=?, record=? WHERE id=?',
                               (str(source), json.dumps(saved), media_id))
                return
            if db.execute('SELECT 1 FROM media WHERE source=?', (str(source),)).fetchone():
                return
            record['file']['size'] = source.stat().st_size
            record['url'] = f'/api/desktop/media/{media_id}'
            db.execute('INSERT INTO media(id,source,record) VALUES (?,?,?)',
                       (media_id, str(source), json.dumps(record)))

    def patch(self, media_id, **fields):
        with self.lock, self.connect() as db:
            row = db.execute('SELECT record FROM media WHERE id=? AND removed=0', (media_id,)).fetchone()
            if not row:
                raise FileNotFoundError('Media not found')
            record = json.loads(row[0])
            record.update(fields)
            db.execute('UPDATE media SET record=? WHERE id=?', (json.dumps(record), media_id))
            return record

    def register(self, paths, replace_id=None):
        if not isinstance(paths, list) or len(paths) > 100:
            raise ValueError('Import up to 100 files at a time.')
        added, errors, pending = [], [], []
        for value in paths:
            try:
                path = Path(value).resolve(strict=True)
                kind = 'video' if path.suffix.lower() in VIDEO else 'image' if path.suffix.lower() in PHOTO else 'audio' if path.suffix.lower() in AUDIO else None
                if not path.is_file() or not kind:
                    raise ValueError('Unsupported media file')
                stat = path.stat()
                if stat.st_size == 0:
                    raise ValueError('The file is empty')
                with self.lock, self.connect() as db:
                    duplicate = db.execute('SELECT id, removed FROM media WHERE source=?', (str(path),)).fetchone()
                    if duplicate and not duplicate[1] and duplicate[0] != replace_id:
                        if replace_id:
                            raise ValueError('This path belongs to another library item')
                        # Reuse the existing reference and analysis without scheduling work again.
                        if not any(item['id'] == duplicate[0] for item in added):
                            added.append(self.get(duplicate[0])[0])
                        continue
                    media_id = replace_id or (duplicate[0] if duplicate else uuid.uuid4().hex)
                    previous = self.get(replace_id)[0] if replace_id else {}
                    if replace_id and previous['status'] not in FINAL:
                        raise ValueError('Stop analysis before locating a replacement file')
                    record = {
                        'id': media_id, 'file': {'name': path.name, 'size': stat.st_size, 'lastModified': int(stat.st_mtime * 1000), 'type': mimetypes.guess_type(path.name)[0] or ''},
                        'kind': kind, 'status': 'queued', 'metadata': None, 'result': None, 'error': None,
                        'favorite': previous.get('favorite', False), 'description': previous.get('description', ''),
                        'url': f'/api/desktop/media/{media_id}'
                    }
                    record['context'] = previous.get('context', {})
                    sidecar = path.with_suffix('.pixfun.json')
                    if not previous and sidecar.is_file() and sidecar.stat().st_size < 16384:
                        try:
                            context = json.loads(sidecar.read_text())
                            record['context'] = {key: str(context[key])[:300] for key in ('device', 'location', 'source', 'credit', 'license') if isinstance(context.get(key), str)}
                        except (OSError, ValueError, AttributeError):
                            pass
                    if replace_id and duplicate and duplicate[0] != replace_id:
                        raise ValueError('This path belongs to another library item')
                    db.execute('INSERT INTO media(id,source,record,removed) VALUES (?,?,?,0) ON CONFLICT(id) DO UPDATE SET source=excluded.source,record=excluded.record,removed=0', (media_id,str(path),json.dumps(record)))
                added.append(record)
                pending.append(record['id'])
            except (OSError, ValueError, TypeError) as exc:
                errors.append(f'{Path(str(value)).name}: {exc}')
        for media_id in pending:
            self.enqueue(media_id)
        return {'items': added, 'errors': errors}

    def enqueue(self, media_id):
        with self.lock:
            if media_id in self.cancel:
                return
            self.patch(media_id, status='queued', error=None, missing=False)
            event = threading.Event()
            self.cancel[media_id] = event
            self.pool.submit(self.analyze, media_id, event)

    def analyze(self, media_id, event):
        current.event = event
        try:
            if event.is_set():
                raise Cancelled()
            record, source = self.get(media_id)
            if not source.is_file():
                raise ValueError('Original file not found. Locate it to reconnect this item.')
            self.patch(media_id, status='analyzing')
            decoded = source
            if record['kind'] == 'image':
                def decode_command(args):
                    code, _, error = engine.run_command(args, timeout=60)
                    if code != 0: raise ValueError('Could not decode this photo. Try a JPEG or PNG copy.')
                decoded = prepare_photo(source, engine.OUTPUTS, decode_command)
            metadata = engine.probe_media(decoded)
            if record['kind'] == 'image':
                metadata.update(duration=None, fps=None, hasAudio=False)
            if not metadata.get('available') or not (metadata.get('hasAudio') if record['kind'] == 'audio' else metadata.get('width')):
                raise ValueError('Cannot read this media. Try another format.')
            self.patch(media_id, metadata=metadata)
            result = None
            if record['kind'] == 'audio':
                result = {'ok': True, 'analysis': {'metadata': metadata, 'segments': [], 'subtitleCues': [], 'subtitleMessage': 'Audio playback is available. Local speech recognition is not installed.'}}
            if record['kind'] == 'image':
                self.patch(media_id, url=engine.media_url('output', decoded.parent.name, decoded.name))
            if record['kind'] == 'video':
                job_id = uuid.uuid4().hex[:12]
                duration = float(metadata.get('duration') or 0)
                # Long field recordings get bounded, evenly sampled navigation.
                # Do not run four full-resolution cut-detection passes or pretend
                # these chapters are AI-recognized scenes.
                sampled = duration > 180
                cuts = [] if sampled else engine.detect_cuts(source, duration)
                analysis = {'metadata': metadata, 'sourceName': source.name, 'cuts': cuts,
                            'segmentationMethod': 'time-sampled' if sampled else 'cuts-and-estimated-splits',
                            'segments': engine.make_segments(duration, cuts)}
                for index, segment in enumerate(analysis['segments']):
                    segment['label'] = f"{'Chapter' if sampled else 'Segment'} {index + 1}"
                    segment['note'] = 'Time-sampled navigation' if sampled else 'Detected cut or estimated split'
                analysis['segments'] = engine.make_timeline_thumbnails(source, job_id, analysis['segments'])
                analysis['subtitleCues'] = engine.extract_subtitle_cues(source, job_id)
                analysis['subtitleState'] = 'embedded' if analysis['subtitleCues'] else 'unavailable' if metadata.get('hasAudio') else 'silent'
                analysis['subtitleMessage'] = 'Extracted from the subtitle track' if analysis['subtitleCues'] else 'No embedded subtitles. Speech recognition is not bundled in this build.'
                if not analysis['subtitleCues']:
                    analysis.update(engine.local_subtitle_track(source))
                result = {'ok': True, 'jobId': job_id, 'analysis': analysis}
            if event.is_set():
                raise Cancelled()
            self.patch(media_id, status='ready', metadata=metadata, result=result, error=None)
        except Cancelled:
            self.patch(media_id, status='cancelled', error='Analysis stopped. Retry when you are ready.')
        except Exception as exc:
            self.patch(media_id, status='error', error=str(exc)[:500])
        finally:
            with self.lock:
                self.cancel.pop(media_id, None)
            current.event = None

    def stop(self):
        with self.lock:
            for event in self.cancel.values():
                event.set()

    def projects(self):
        with self.connect() as db:
            return [json.loads(row[0]) for row in db.execute('SELECT record FROM projects ORDER BY updated DESC, rowid DESC')]

    def save_project(self, payload):
        prompt = payload.get('prompt')
        ids = payload.get('mediaIds', [])
        skill = payload.get('skill')
        if skill is not None:
            required = {'id', 'title', 'strategy'}
            if not isinstance(skill, dict) or not required <= set(skill) or not set(skill) <= required | {'applicability'}:
                raise ValueError('Invalid creator skill')
            if any(not isinstance(skill[k], str) or not skill[k].strip() or len(skill[k]) > limit for k, limit in [('id', 80), ('title', 80), ('strategy', 4000)]):
                raise ValueError('Invalid creator skill')
            if 'applicability' in skill and (not isinstance(skill['applicability'],str) or not skill['applicability'].strip() or len(skill['applicability'])>400):
                raise ValueError('Invalid creator skill applicability')
        if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 5000:
            raise ValueError('Describe your video in 1–5000 characters.')
        if not isinstance(ids, list) or len(ids) > 100 or any(not isinstance(i, str) for i in ids):
            raise ValueError('Invalid project attachments')
        attachments = []
        for media_id in dict.fromkeys(ids):
            record, _ = self.get(media_id)
            attachments.append({'id': media_id, 'name': record['file']['name'], 'kind': record['kind']})
        project_id = payload.get('id') or uuid.uuid4().hex
        if not isinstance(project_id, str) or not re.fullmatch(r'[a-f0-9]{32}', project_id):
            raise ValueError('Invalid project')
        now = int(time.time() * 1000)
        with self.lock, self.connect() as db:
            row = db.execute('SELECT record FROM projects WHERE id=?', (project_id,)).fetchone()
            if payload.get('id') and not row:
                raise FileNotFoundError('Project not found')
            record = json.loads(row[0]) if row else {'id': project_id, 'title': prompt.strip().splitlines()[0][:72], 'createdAt': now, 'messages': []}
            if len(record['messages']) >= 100:
                raise ValueError('This project has reached 100 briefs. Start a new project.')
            record.update(updatedAt=now, status='draft', attachments=attachments)
            if 'skill' in payload:
                record['skill'] = skill
            record['messages'].append({'text': prompt.strip(), 'createdAt': now, 'attachments': attachments, 'skill': record.get('skill')})
            db.execute('INSERT INTO projects(id,record,updated) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET record=excluded.record,updated=excluded.updated', (project_id, json.dumps(record), now))
        return record

    def close(self):
        self.stop()
        self.pool.shutdown(wait=True)


current = threading.local()


def cancellable_command(args, timeout=120):
    event = getattr(current, 'event', None)
    if event and event.is_set():
        raise Cancelled()
    try:
        process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    except OSError as exc:
        return 127, '', str(exc)
    deadline = time.monotonic() + timeout
    while True:
        try:
            out, err = process.communicate(timeout=.2)
            return process.returncode, out, err
        except subprocess.TimeoutExpired:
            if (event and event.is_set()) or time.monotonic() > deadline:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.communicate(timeout=1)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()
                except ProcessLookupError:
                    pass
                if event and event.is_set():
                    raise Cancelled()
                return 124, '', f'Processing timed out after {timeout}s'


class Handler(engine.Handler):
    def log_message(self, format, *args):
        if urlparse(self.path).path in ('/api/desktop/library', '/api/desktop/projects', '/api/desktop/locations'):
            return # Idle polling must not grow service.log every second.
        super().log_message(format, *args)
    def authorized(self, native=False):
        expected = self.server.native_token if native else self.server.token
        name = 'X-Pixfun-Native' if native else 'Authorization'
        supplied = self.headers.get(name, '')
        if not native:
            supplied = supplied.removeprefix('Bearer ')
        origin = self.headers.get('Origin')
        allowed_origin = f'http://127.0.0.1:{self.server.server_port}'
        if origin and origin != allowed_origin:
            self.send_json({'ok': False, 'error': 'Origin denied'}, 403)
            return False
        if not expected or not hmac.compare_digest(supplied, expected):
            self.send_json({'ok': False, 'error': 'Unauthorized'}, 401)
            return False
        return True

    def end_headers(self):
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self'; font-src 'self'; object-src 'none'; frame-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
        super().end_headers()

    def do_GET(self):
        if not self.authorized():
            return
        path = unquote(urlparse(self.path).path)
        try:
            if path == '/api/desktop/library':
                self.send_json({'ok': True, 'items': self.server.library.list()})
            elif path == '/api/desktop/locations':
                # Absolute paths are native-only; never expose them to the web renderer.
                # Use the index, not disk enumeration, so missing originals remain locatable.
                if self.authorized(native=True):
                    with self.server.library.connect() as db:
                        rows = db.execute('SELECT id, source FROM media WHERE removed=0 ORDER BY rowid').fetchall()
                    self.send_json({'ok': True, 'items': [{'id': media_id, 'path': source} for media_id, source in rows]})
            elif path == '/api/desktop/projects':
                self.send_json({'ok': True, 'projects': self.server.library.projects()})
            elif path == '/api/desktop/agent/runs':
                if self.authorized(native=True): self.send_json({'runs': self.server.agent.list()})
            elif path == '/api/desktop/agent/capabilities':
                if self.authorized(native=True): self.send_json(self.server.agent.models.capabilities())
            elif path == '/api/desktop/settings':
                with self.server.library.connect() as db:
                    self.send_json({'ok': True, 'settings': dict(db.execute('SELECT key,value FROM settings'))})
            elif path.startswith('/api/desktop/native/'):
                if self.authorized(native=True):
                    _, source = self.server.library.get(path.rsplit('/',1)[1])
                    self.send_json({'ok': True, 'path': str(source)})
            elif path.startswith('/api/desktop/media/'):
                _, source = self.server.library.get(path.rsplit('/',1)[1])
                self.send_file(source)
            elif path == '/api/health':
                self.send_json({'ok': True, 'desktop': True, 'tools': {'ffmpeg': engine.command_exists('ffmpeg'), 'ffprobe': engine.command_exists('ffprobe'), 'transcription': False}})
            elif path in ('/', '/index.html') or path.startswith('/assets/') or path.startswith('/media/output/'):
                super().do_GET()
            else:
                self.send_error(404)
        except (FileNotFoundError, OSError):
            self.send_json({'ok': False, 'error': 'File not found. Locate the original file to continue.'},404)

    def do_POST(self):
        if not self.authorized():
            return
        path = urlparse(self.path).path
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 <= length <= 128 * 1024:
                self.send_json({'ok': False, 'error': 'Request too large'},413)
                return
            if (path.startswith('/api/desktop/agent/') or path.startswith('/api/desktop/description/') or path.startswith('/api/desktop/shots/') or path in ('/api/desktop/register', '/api/desktop/locate')) and not self.authorized(native=True):
                return
            payload = self.read_json()
            if not isinstance(payload, dict):
                raise ValueError('Invalid request')
            library = self.server.library
            if path == '/api/desktop/projects':
                self.send_json({'ok': True, 'project': library.save_project(payload)})
            elif path == '/api/desktop/description/start':
                if not isinstance(payload.get('id'),str): raise ValueError('A media ID is required')
                if not isinstance(payload.get('force',False),bool): raise ValueError('Invalid force option')
                self.send_json({'description':self.server.descriptions.start(payload.get('id'),payload.get('force',False))})
            elif path == '/api/desktop/description/stop':
                if not isinstance(payload.get('id'),str): raise ValueError('A media ID is required')
                self.server.descriptions.stop(payload['id']); self.send_json({'ok':True})
            elif path == '/api/desktop/shots/start':
                if not isinstance(payload.get('id'),str) or not isinstance(payload.get('force',False),bool): raise ValueError('A media ID and boolean force option are required')
                self.send_json({'analysis':self.server.shots.start(payload['id'],payload.get('force',False))})
            elif path == '/api/desktop/shots/stop':
                if not isinstance(payload.get('id'),str): raise ValueError('A media ID is required')
                self.server.shots.stop(payload['id']); self.send_json({'ok':True})
            elif path == '/api/desktop/agent/start':
                self.send_json({'run': self.server.agent.start(payload)})
            elif path == '/api/desktop/agent/action':
                self.send_json({'run': self.server.agent.action(payload)})
            elif path == '/api/desktop/agent/configure':
                if any(r['status'] in ('queued','running') for r in self.server.agent.list()):
                    raise ValueError('Finish or stop pending tasks before changing model configuration.')
                self.server.agent.models.configure(payload)
                self.send_json({'ok': True})
            elif path == '/api/desktop/register':
                self.send_json({'ok':True, **library.register(payload.get('paths'))})
            elif path == '/api/desktop/locate':
                self.send_json({'ok':True, **library.register(payload.get('paths'),payload.get('id'))})
            elif path == '/api/desktop/update':
                fields = {k: payload[k] for k in ('favorite','description','title') if k in payload}
                if 'favorite' in fields and not isinstance(fields['favorite'],bool):
                    raise ValueError('Invalid favorite')
                for key in ('description','title'):
                    if key in fields:
                        if not isinstance(fields[key],str):
                            raise ValueError('Invalid text')
                        fields[key] = fields[key][:240]
                if 'context' in payload:
                    context = payload['context']
                    if not isinstance(context, dict) or any(k not in ('device', 'location') or not isinstance(v, str) for k, v in context.items()):
                        raise ValueError('Invalid media context')
                    record, _ = library.get(payload['id'])
                    fields['context'] = {**record.get('context', {}), **{k: v.strip()[:120] for k, v in context.items()}}
                library.patch(payload['id'], **fields)
                self.send_json({'ok':True})
            elif path == '/api/desktop/retry':
                library.enqueue(payload['id'])
                self.send_json({'ok':True})
            elif path == '/api/desktop/stop':
                library.stop()
                self.send_json({'ok':True})
            elif path in ('/api/desktop/remove','/api/desktop/restore'):
                if path.endswith('remove'):
                    record, _ = library.get(payload['id'])
                    if record['status'] not in FINAL:
                        raise ValueError('Stop processing before removing this item')
                with library.connect() as db:
                    db.execute('UPDATE media SET removed=? WHERE id=?',(int(path.endswith('remove')),payload['id']))
                self.send_json({'ok':True})
            elif path == '/api/desktop/settings':
                if payload.get('key') not in ('skill', 'projectDraft') or not isinstance(payload.get('value'),str):
                    raise ValueError('Invalid setting')
                key = payload['key']
                limit = 80 if key == 'skill' else 40000
                if len(payload['value']) > limit:
                    raise ValueError('Setting is too long')
                if key == 'projectDraft' and not isinstance(json.loads(payload['value']), dict):
                    raise ValueError('Invalid draft')
                with library.connect() as db:
                    db.execute('INSERT OR REPLACE INTO settings(key,value) VALUES (?,?)',(key,payload['value']))
                self.send_json({'ok':True})
            else:
                self.send_error(404)
        except FileNotFoundError as exc:
            self.send_json({'ok':False,'error':str(exc)},404)
        except (ValueError, KeyError, TypeError, sqlite3.Error) as exc:
            self.send_json({'ok':False,'error':str(exc)[:300]},400)


def main():
    token, native = os.environ.get('PIXFUN_SERVICE_TOKEN',''), os.environ.get('PIXFUN_NATIVE_TOKEN','')
    if len(token) < 32 or len(native) < 32:
        raise SystemExit('Desktop launch secrets are required')
    # Both desktop implementations share a database. Never run two analyzers on it.
    engine.DATA.mkdir(parents=True, exist_ok=True)
    service_lock = (engine.DATA / 'desktop-service.lock').open('a')
    try:
        fcntl.flock(service_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit('This library is already open in another Pixfun client.')
    engine.run_command = cancellable_command
    library = Library(engine.DATA)
    if os.environ.get('PIXFUN_EXAMPLE_DIR'):
        library.install_example(os.environ['PIXFUN_EXAMPLE_DIR'])
    server = engine.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    server.library, server.token, server.native_token = library, token, native
    server.agent = AgentEngine(library)
    server.descriptions = VideoDescriptions(library, server.agent)
    server.shots = ShotAnalyses(library, server.agent)
    def shutdown(*_):
        library.stop()
        server.descriptions.stop()
        server.shots.stop()
        for event in server.agent.cancels.values(): event.set()
        threading.Thread(target=server.shutdown,daemon=True).start()
    signal.signal(signal.SIGTERM,shutdown)
    signal.signal(signal.SIGINT,shutdown)
    parent_pid = int(os.environ.get('PIXFUN_PARENT_PID', '0'))
    if parent_pid:
        def watch_parent():
            while os.getppid() == parent_pid:
                time.sleep(1)
            shutdown()
        threading.Thread(target=watch_parent, daemon=True).start()
    print(json.dumps({'ready':True,'port':server.server_port}),flush=True)
    try:
        server.serve_forever(poll_interval=.2)
    finally:
        server.descriptions.stop()
        server.shots.stop()
        server.agent.close()
        library.close()
        server.server_close()
        service_lock.close()


if __name__ == '__main__':
    main()
