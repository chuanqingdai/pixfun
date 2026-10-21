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
from urllib.parse import urlparse, unquote, parse_qs, quote

import app as engine
from photo_source import prepare_photo
from media_metadata import photo_capture_metadata
from agent_engine import AgentEngine
from agent_editor import assist as editor_assist
from video_description import VideoDescriptions
from shot_analysis import ShotAnalyses
from vf_native import NativeCatalog, validate_source
from vf_bridge import BridgeError
from agent_models import CapabilityMissing
from media_sync import MediaSync
from media_analysis import MediaAnalysis

VIDEO = {'.mp4', '.mov', '.m4v', '.mkv', '.webm', '.avi', '.mts', '.m2ts', '.ogv', '.lrf'}
PHOTO = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif', '.heic', '.heif', '.bmp', '.tif', '.tiff'}
AUDIO = {'.mp3', '.wav', '.m4a', '.aac', '.flac', '.ogg', '.aiff', '.aif', '.opus'}
FINAL = {'ready', 'error', 'cancelled'}

# Some bundled SQLite builds can deadlock when opening a connection concurrently
# with another connection's final close (including WAL teardown). Serialize only
# lifecycle calls; queries/transactions still use independent WAL connections.
_sqlite_lifecycle = threading.RLock()


class Cancelled(Exception):
    pass


class Library:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.path = self.directory / 'library.sqlite3'
        self.lock = threading.RLock()
        self.cancel = {}
        self.content_analysis = None
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
        with _sqlite_lifecycle:
            db = sqlite3.connect(self.path, timeout=15)
        try:
            with db:
                yield db
        finally:
            with _sqlite_lifecycle:
                db.close()

    def list(self):
        with self.connect() as db:
            rows = db.execute('SELECT record, source FROM media WHERE removed=0 ORDER BY rowid').fetchall()
        records = []
        for raw, source in rows:
            record = json.loads(raw)
            if not Path(source).is_file():
                record.update(status='error', missing=True, error='Original file not found. Locate it to reconnect this item.')
            elif record.get('status') == 'ready' and record.get('kind') == 'video' and not record.get('vfCatalog'):
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
        record, source = json.loads(row[0]), Path(row[1])
        validate_source(record, source)
        return record, source

    def map_metadata(self, media_id):
        """Explicit, one-file local read. No analysis, source edits or database mutations."""
        record, source = self.get(media_id)
        if record.get('isExample') or record.get('kind') not in ('image', 'video'):
            raise ValueError('No original capture metadata for this item')
        playback_source = source
        # Explicit metadata reads use the catalog-linked camera file, not a
        # stripped proxy header. This does NOT certify a render-time mapping.
        original = (record.get('vfCatalog') or {}).get('originalSource')
        if original: source = Path(original).resolve(strict=True)
        before = source.stat()
        if record['kind'] == 'image':
            metadata = photo_capture_metadata(source)
        else:
            metadata = engine.probe_media(source)
            if not metadata.get('available'): raise ValueError('Original metadata could not be read')
        after = source.stat()
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError('Source changed during metadata read; try again')
        validate_source(record, playback_source)
        return {**{key: metadata.get(key) for key in ('camera', 'captureDeviceID', 'capturedAt', 'dateSource', 'location')},
                'metadataSource': 'catalog-linked-original' if original else 'original-file'}

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
        batch_id = uuid.uuid4().hex
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
                        'importedAt': previous.get('importedAt') or time.time()*1000,
                        'importBatchId': previous.get('importBatchId', batch_id),
                        'url': f'/api/desktop/media/{media_id}'
                    }
                    record['context'] = previous.get('context', {})
                    for field in ('syncSourceId', 'syncSourceName', 'syncSourceKind', 'originalFileName'):
                        if field in previous: record[field] = previous[field]
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
            if self.content_analysis:
                self.content_analysis.schedule(media_id)
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
                try: metadata.update(photo_capture_metadata(source))
                except (OSError, ValueError, TypeError): pass  # Unsupported original formats remain unlocated.
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
                analysis.update(subtitleCues=[], subtitleState='pending' if metadata.get('hasAudio') else 'silent',
                                subtitleMessage='Speech recognition runs during content analysis.' if metadata.get('hasAudio') else 'This video has no audio track')
                analysis.update(engine.extract_subtitle_track(source, job_id, metadata))
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
        from media_commands import bounded_command
        process = subprocess.Popen(bounded_command(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
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
        if urlparse(self.path).path in ('/api/desktop/library', '/api/desktop/projects', '/api/desktop/locations', '/api/desktop/sync'):
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
                if self.server.vf and not self.authorized(native=True): return
                self.send_json({'ok': True, 'items': self.server.library.list()})
            elif path == '/api/desktop/vf/status':
                self.send_json(self.server.vf.status if self.server.vf else {'connected':False,'message':'VisionFlow is not configured','assets':0,'shots':0})
            elif path == '/api/desktop/vf/search':
                if not self.authorized(native=True): return
                if not self.server.vf: raise ValueError('VisionFlow is not configured')
                if any(r['status'] in ('queued','running') for r in self.server.agent.list()):
                    raise ValueError('Wait for the current analysis to finish before visual search.')
                params = parse_qs(urlparse(self.path).query)
                with self.server.agent.models.lock, self.server.agent.models.resources.lease('model', threading.Event()):
                    self.send_json({'matches': self.server.vf.search(params.get('q',[''])[0],params.get('similar',[None])[0],params.get('collection',[None])[0])})
            elif path.startswith('/api/desktop/vf/frame/'):
                if not self.server.vf: raise FileNotFoundError()
                ident = path[len('/api/desktop/vf/frame/'):]
                if len(ident)>500: raise ValueError('Invalid frame ID')
                with self.server.vf.catalog.open('frame/'+quote(ident,safe='')) as response:
                    data=response.read(10*1024*1024+1)
                    if len(data)>10*1024*1024: raise ValueError('Frame too large')
                    self.send_response(200); self.send_header('Content-Type','image/jpeg')
                    self.send_header('Content-Length',str(len(data))); self.send_header('Cache-Control','no-store')
                    self.end_headers(); self.wfile.write(data)
            elif path == '/api/desktop/locations':
                # Absolute paths are native-only; never expose them to the web renderer.
                # Use the index, not disk enumeration, so missing originals remain locatable.
                if self.authorized(native=True):
                    with self.server.library.connect() as db:
                        rows = db.execute('SELECT id, source FROM media WHERE removed=0 ORDER BY rowid').fetchall()
                    self.send_json({'ok': True, 'items': [{'id': media_id, 'path': source} for media_id, source in rows]})
            elif path == '/api/desktop/projects':
                self.send_json({'ok': True, 'projects': self.server.library.projects()})
            elif path == '/api/desktop/sync':
                if self.authorized(native=True): self.send_json(self.server.media_sync.snapshot())
            elif path == '/api/desktop/agent/runs':
                if self.authorized(native=True): self.send_json({'runs': self.server.agent.list()})
            elif path == '/api/desktop/agent/capabilities':
                if self.authorized(native=True): self.send_json(self.server.agent.models.capabilities())
            elif path == '/api/desktop/agent/catalog':
                if self.authorized(native=True): self.send_json(self.server.catalog.status())
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
        except (BridgeError, ValueError) as exc:
            self.send_json({'ok':False,'error':str(exc)},getattr(exc,'status',400))

    def do_POST(self):
        if not self.authorized():
            return
        path = urlparse(self.path).path
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 <= length <= 128 * 1024:
                self.send_json({'ok': False, 'error': 'Request too large'},413)
                return
            if (path.startswith('/api/desktop/vf/') or path.startswith('/api/desktop/analysis/') or path.startswith('/api/desktop/agent/') or path.startswith('/api/desktop/description/') or path.startswith('/api/desktop/shots/') or path in ('/api/desktop/register', '/api/desktop/locate', '/api/desktop/sync')) and not self.authorized(native=True):
                return
            payload = self.read_json()
            if not isinstance(payload, dict):
                raise ValueError('Invalid request')
            library = self.server.library
            if path == '/api/desktop/analysis/map-metadata':
                if not isinstance(payload.get('id'), str): raise ValueError('A media ID is required')
                self.send_json({'ok': True, 'metadata': library.map_metadata(payload['id'])})
            elif path == '/api/desktop/analysis/place':
                from place_context import validate_place
                if not isinstance(payload.get('id'), str): raise ValueError('A media ID is required')
                record, _ = library.get(payload['id'])
                place = validate_place(record, payload.get('place'))
                library.patch(payload['id'], resolvedPlace=place)
                # No visual re-analysis or implicit full-library regeneration.
                self.send_json({'ok': True})
            elif path == '/api/desktop/agent/media-tags':
                from media_evidence import validate_corrections
                key = payload.get('id')
                if not isinstance(key,str): raise ValueError('A registered media ID is required')
                library.get(key)
                library.patch(key, tagCorrections=validate_corrections(payload))
                self.send_json({'ok':True})
            elif path == '/api/desktop/agent/catalog':
                if payload.get('action') == 'stop':
                    self.server.catalog.stop()
                    self.send_json({'ok':True})
                else:
                    self.send_json(self.server.catalog.start(payload))
            elif path == '/api/desktop/analysis/retry-failed':
                ids = [item['id'] for item in library.list()
                       if (item.get('mediaAnalysis') or {}).get('status') == 'failed']
                count = sum(self.server.content_analysis.schedule(key) for key in ids)
                self.send_json({'ok':True, 'queued':count})
            elif path == '/api/desktop/analysis/reanalyze':
                ids = payload.get('ids')
                if ids is None: ids = [item['id'] for item in library.list()]
                if not isinstance(ids, list) or any(not isinstance(key, str) for key in ids): raise ValueError('Invalid media IDs')
                for key in ids: library.get(key)
                count = sum(self.server.content_analysis.schedule(key, force=True) for key in dict.fromkeys(ids))
                self.send_json({'ok':True, 'queued':count})
            elif path == '/api/desktop/projects':
                self.send_json({'ok': True, 'project': library.save_project(payload)})
            elif path == '/api/desktop/vf/sync':
                if not self.server.vf: raise ValueError('VisionFlow is not configured')
                if library.cancel or any(r['status'] in ('queued','running') for r in self.server.agent.list()):
                    raise ValueError('Finish pending tasks before refreshing the catalog.')
                self.send_json(self.server.vf.sync())
            elif path == '/api/desktop/sync':
                try: self.send_json(self.server.media_sync.action(payload))
                except OSError as exc: self.send_json({'ok':False,'error':MediaSync.friendly(exc)},400)
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
            elif path == '/api/desktop/agent/export':
                self.send_json({'export': self.server.agent.exports.action(payload)})
            elif path == '/api/desktop/agent/editor-assist':
                self.send_json(editor_assist(self.server.agent, payload))
            elif path == '/api/desktop/agent/beauty-sort':
                self.send_json({'job': self.server.agent.beauty_sort.request(payload)})
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
                item, _ = library.get(payload['id'])
                if item.get('status') != 'ready': library.enqueue(payload['id'])
                # Retry incomplete stages with the same source/cache signatures.
                # Full reanalysis remains a separate explicit action.
                self.server.content_analysis.schedule(payload['id'])
                self.send_json({'ok':True})
            elif path == '/api/desktop/stop':
                self.server.catalog.stop()
                library.stop()
                self.server.content_analysis.stop()
                self.server.descriptions.stop()
                self.server.shots.stop()
                self.send_json({'ok':True})
            elif path in ('/api/desktop/remove','/api/desktop/restore'):
                if path.endswith('remove'):
                    self.server.content_analysis.stop(payload['id'])
                    record, _ = library.get(payload['id'])
                    if record['status'] not in FINAL:
                        raise ValueError('Stop processing before removing this item')
                with library.connect() as db:
                    db.execute('UPDATE media SET removed=? WHERE id=?',(int(path.endswith('remove')),payload['id']))
                self.send_json({'ok':True})
            elif path == '/api/desktop/settings':
                if payload.get('key') not in ('skill', 'projectDraft', 'language') or not isinstance(payload.get('value'),str):
                    raise ValueError('Invalid setting')
                key = payload['key']
                if key == 'language':
                    if not self.authorized(native=True): return
                    if payload['value'] not in ('en', 'zh-Hans'): raise ValueError('Unsupported language')
                limit = 80 if key == 'skill' else 40000
                if len(payload['value']) > limit:
                    raise ValueError('Setting is too long')
                if key == 'projectDraft' and not isinstance(json.loads(payload['value']), dict):
                    raise ValueError('Invalid draft')
                with library.connect() as db:
                    db.execute('INSERT OR REPLACE INTO settings(key,value) VALUES (?,?)',(key,payload['value']))
                if key == 'language': self.server.agent.models.output_language = payload['value']
                self.send_json({'ok':True})
            else:
                self.send_error(404)
        except FileNotFoundError as exc:
            self.send_json({'ok':False,'error':str(exc)},404)
        except (CapabilityMissing, TimeoutError) as exc:
            self.send_json({'ok':False,'error':str(exc)[:300]},503)
        except (BridgeError, ValueError, KeyError, TypeError, sqlite3.Error) as exc:
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
    # First use starts with an empty library; samples are not user imports.
    server = engine.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    server.library, server.token, server.native_token = library, token, native
    state_file = os.environ.get('VF_LIBRARY_STATE')
    server.vf = NativeCatalog(state_file,library) if state_file else None
    if server.vf:
        try: server.vf.sync()
        except (BridgeError, ValueError, OSError): pass # Saved native projects remain usable offline.
    server.agent = AgentEngine(library)
    from media_catalog import MediaCatalog
    server.catalog = MediaCatalog(library, server.agent)
    server.descriptions = VideoDescriptions(library, server.agent)
    server.shots = ShotAnalyses(library, server.agent)
    server.content_analysis = MediaAnalysis(library, server.agent, server.descriptions, server.shots)
    library.content_analysis = server.content_analysis
    server.media_sync = MediaSync(library, PHOTO, VIDEO)
    server.media_sync.browser_import.analysis = server.content_analysis.schedule
    # Explicit one-time local maintenance request; never auto-force every launch.
    request = os.environ.get('PIXFUN_REANALYZE_LIBRARY', '')
    with library.connect() as db:
        saved = db.execute('SELECT value FROM settings WHERE key=?', ('analysisMaintenanceRequest',)).fetchone()
    force_all = bool(request and (not saved or saved[0] != request))
    server.content_analysis.recover(force_all=force_all)
    if force_all:
        with library.connect() as db: db.execute('INSERT OR REPLACE INTO settings VALUES (?,?)', ('analysisMaintenanceRequest', request))
    def shutdown(*_):
        server.catalog.stop()
        server.media_sync.stopping.set()
        for event in list(server.media_sync.events.values()): event.set()
        library.stop()
        server.content_analysis.closing = True
        server.content_analysis.stop()
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
        server.media_sync.close()
        server.content_analysis.close()
        server.descriptions.stop()
        server.shots.stop()
        server.agent.close()
        library.close()
        server.server_close()
        service_lock.close()


if __name__ == '__main__':
    main()
