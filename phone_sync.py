"""Opt-in, upload-only HTTPS receiver. Never exposes the desktop API to the LAN.

Pairing QR pins the certificate and carries a single-use, five-minute secret.
Phone credentials can only send media; they cannot choose paths or read files.
Interrupted files retry from the beginning; completed files are idempotent.
"""
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import uuid


class PhoneError(ValueError):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


class PhoneSync:
    MAX_FILE = 32 * 1024**3

    def __init__(self, owner):
        self.owner = owner
        self.server = self.thread = None
        self.pairing = None
        self.active = None
        self.idle = threading.Event()
        self.idle.set()
        self.cancel = threading.Event()
        self.last_seen = {}
        self.error = None
        self.fingerprint = None
        with owner.library.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS sync_phones(id TEXT PRIMARY KEY,record TEXT NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS sync_wifi(id INTEGER PRIMARY KEY,record TEXT NOT NULL)')

    def config(self):
        with self.owner.library.connect() as db:
            row = db.execute('SELECT record FROM sync_wifi WHERE id=1').fetchone()
        return json.loads(row[0]) if row else {}

    def save_config(self, value):
        with self.owner.library.connect() as db:
            db.execute('INSERT OR REPLACE INTO sync_wifi VALUES (1,?)', (json.dumps(value),))

    def phones(self):
        with self.owner.library.connect() as db:
            return [json.loads(row[0]) for row in db.execute('SELECT record FROM sync_phones ORDER BY rowid')]

    def save(self, phone):
        with self.owner.library.connect() as db:
            db.execute('INSERT INTO sync_phones VALUES (?,?) ON CONFLICT(id) DO UPDATE SET record=excluded.record', (phone['id'], json.dumps(phone)))

    def busy(self, key=None):
        return bool(self.active and (key is None or self.active == key))

    def snapshot(self):
        with self.owner.lock:
            devices = []
            for phone in self.phones():
                if phone.get('browserImport'): continue
                online = bool(self.server and time.monotonic() - self.last_seen.get(phone['id'], -1000) < 75)
                busy = self.busy(phone['id'])
                public = {k: v for k, v in phone.items() if k != 'credential'}
                public.update(connected=online, busy=busy,
                    status='Paused' if not phone['automatic'] else phone['status'] if busy or phone['status']=='Needs Attention' else 'Connected' if online else 'Offline')
                devices.append(public)
            pairing = self.pairing
            if pairing and pairing['expiresAt'] <= time.time():
                self.pairing = pairing = None
            return devices, dict(enabled=bool(self.server), error=self.error,
                pairing={k: v for k, v in pairing.items() if k != 'secret'} if pairing else None)

    def start(self, host='0.0.0.0', port=None):
        """Only called by explicit pairing/enable, or a previously enabled startup."""
        from media_sync import connected
        with self.owner.lock:
            if self.server: return
            if self.owner.stopping.is_set(): raise PhoneError('Pixfun is closing.')
            if not connected(self.owner.storage().get('working')):
                raise PhoneError('Choose a connected save location first.')
            directory = self.owner.library.directory / 'phone-sync'
            if directory.is_symlink(): raise PhoneError('Pairing storage is not safe.')
            directory.mkdir(mode=0o700, exist_ok=True)
            os.chmod(directory, 0o700)
            cert, key = directory / 'certificate.pem', directory / 'private-key.pem'
            if cert.is_symlink() or key.is_symlink(): raise PhoneError('Pairing certificate is not safe.')
            if not cert.exists() or not key.exists():
                # No shell, no user-provided arguments, and no certificate secrets in logs.
                result = subprocess.run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048',
                    '-nodes', '-keyout', str(key), '-out', str(cert), '-days', '3650',
                    '-subj', '/CN=Pixfun Media Sync'], capture_output=True, timeout=20)
                if result.returncode: raise PhoneError('Could not prepare secure phone pairing.')
            os.chmod(key, 0o600)
            der = ssl.PEM_cert_to_DER_cert(cert.read_text())
            self.fingerprint = hashlib.sha256(der).hexdigest()
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(str(cert), str(key))
            config = self.config()
            server = PhoneServer((host, port if port is not None else config.get('port', 0)), PhoneHandler)
            server.receiver = self
            server.tls = context
            self.server = server
            self.error = None
            self.thread = threading.Thread(target=server.serve_forever, daemon=True)
            self.thread.start()
            self.save_config(dict(enabled=True, port=server.server_port))

    def restore(self):
        if self.config().get('enabled'):
            try: self.start()
            except (OSError, ValueError, subprocess.SubprocessError):
                self.error = 'Wi-Fi sync is unavailable. Check the save location, then enable it again.'

    def pair_begin(self, payload):
        with self.owner.lock:
            if payload.get('workingPath'):
                self.owner.configure_storage(dict(kind='working', path=payload['workingPath']))
            self.start()
            # macOS advertises its stable LocalHostName through mDNS on the LAN.
            try:
                name = subprocess.check_output(['/usr/sbin/scutil', '--get', 'LocalHostName'], timeout=3).decode().strip()
            except (OSError, subprocess.SubprocessError):
                name = socket.gethostname().split('.')[0]
            if not re.fullmatch(r'[A-Za-z0-9-]{1,63}', name): raise PhoneError('The Mac network name is unavailable.')
            secret = secrets.token_urlsafe(32)
            info = dict(version=1, endpoint=f'https://{name}.local:{self.server.server_port}',
                        fingerprint=self.fingerprint, secret=secret, expiresAt=int(time.time()+300))
            self.pairing = dict(secret=secret, expiresAt=info['expiresAt'], payload=json.dumps(info, separators=(',', ':')))

    def pair(self, payload):
        with self.owner.lock:
            pending = self.pairing
            secret = payload.get('secret', '')
            if not isinstance(secret, str) or not pending or pending['expiresAt'] <= time.time() or not hmac.compare_digest(secret, pending['secret']):
                raise PhoneError('Pairing expired. Create a new code on your Mac.', 401)
            name = payload.get('name', '')
            if not isinstance(name, str) or not name.strip() or len(name) > 80 or any(ord(c) < 32 for c in name):
                raise PhoneError('Use a device name up to 80 characters.')
            if len(self.phones()) >= 12: raise PhoneError('Remove an unused phone before pairing another.')
            token = secrets.token_urlsafe(32)
            key = uuid.uuid4().hex
            self.save(dict(id=key, name=name.strip(), kind='phone', credential=hashlib.sha256(token.encode()).hexdigest(),
                automatic=True, photos=True, videos=True, status='Connected', message='Waiting for authorized media from your phone.',
                lastSync=None, completed=0, total=0, failed=0, skipped=0, bytes=0, totalBytes=0))
            self.pairing = None
            self.last_seen[key] = time.monotonic()
            return dict(id=key, token=token)

    def authorize(self, header):
        if not header.startswith('Bearer ') or len(header) > 256: raise PhoneError('Pair this phone first.', 401)
        hashed = hashlib.sha256(header[7:].encode()).hexdigest()
        with self.owner.lock:
            phone = next((p for p in self.phones() if hmac.compare_digest(p['credential'], hashed)), None)
            if not phone: raise PhoneError('Phone access was removed. Pair again.', 401)
            self.last_seen[phone['id']] = time.monotonic()
            return phone

    def phone_action(self, payload):
        with self.owner.lock:
            phone = next((p for p in self.phones() if p['id'] == payload.get('id')), None)
            if not phone: raise PhoneError('Phone not found.')
            action = payload['action']
            if action == 'phoneRemove':
                if self.busy(phone['id']): raise PhoneError('Pause and wait for the transfer before removing this phone.')
                with self.owner.library.connect() as db: db.execute('DELETE FROM sync_phones WHERE id=?', (phone['id'],))
            elif action in ('phonePause', 'phoneResume'):
                phone['automatic'] = action == 'phoneResume'
                self.save(phone)
                if not phone['automatic'] and self.busy(phone['id']): self.cancel.set()
            else: raise PhoneError('Unknown phone action.')

    def ready(self, phone):
        from media_sync import connected
        if not phone['automatic']: raise PhoneError('Sync is paused on your Mac.', 409)
        storage = self.owner.storage().get('working')
        if not connected(storage): raise PhoneError('Reconnect the save location on your Mac.', 409)
        return storage

    def metadata(self, value):
        if not isinstance(value, dict): raise PhoneError('Invalid media metadata.')
        name, identity, sha, size = (value.get(k) for k in ('fileName', 'assetId', 'sha256', 'size'))
        if (not isinstance(name, str) or not 1 <= len(name.encode()) <= 180 or name in ('.', '..') or
                any(c in name for c in '/\\:') or name.startswith('.') or any(ord(c) < 32 for c in name)):
            raise PhoneError('Invalid media filename.')
        if not isinstance(identity, str) or not 1 <= len(identity) <= 512: raise PhoneError('Invalid media identity.')
        if not isinstance(sha, str) or not re.fullmatch('[0-9a-f]{64}', sha): raise PhoneError('Invalid media checksum.')
        if type(size) is not int or not 0 < size <= self.MAX_FILE: raise PhoneError('Media must be between 1 byte and 32 GB.')
        if Path(name).suffix.lower() not in self.owner.photos | self.owner.videos: raise PhoneError('Only supported photos and videos can be synced.')
        return dict(fileName=name, fileSize=size, sha256=sha, key=hashlib.sha256((identity+':'+sha).encode()).hexdigest())

    def existing(self, phone, meta):
        from media_sync import connected, digest
        asset = next((a for a in self.owner.assets(phone['id']) if a['key'] == meta['key']), None)
        if asset and asset.get('status') == 'ready':
            if not connected(asset['targetStorage']):
                raise PhoneError('Reconnect the storage holding this copy before verifying it.', 409)
            path = Path(asset['workingPath'])
            if (not path.is_symlink() and path.is_file() and Path(asset['targetStorage']['path']) in path.resolve().parents
                    and path.stat().st_size == meta['fileSize'] and digest(path) == meta['sha256']): return asset
        return None

    def receive(self, phone, meta, reader, length, guard=None):
        from media_sync import connected, digest, publish_exclusive
        if length != meta['fileSize']: raise PhoneError('File size does not match metadata.')
        key = phone['id']
        with self.owner.lock:
            if guard: guard()
            phone = next((p for p in self.phones() if p['id'] == key), None)
            if not phone: raise PhoneError('Phone access was removed.', 401)
            storage = self.ready(phone)
            if self.active or self.owner.busy(): raise PhoneError('Another import is running. Retry shortly.', 409)
            self.active = key
            self.idle.clear()
            self.cancel.clear()
        temporary = None
        try:
            if self.existing(phone, meta): return dict(complete=True, duplicate=True)
            old = next((a for a in self.owner.assets(key) if a['key'] == meta['key']), None)
            # Reuse an interrupted registration, but never overwrite an altered copy.
            asset = old if old and old.get('status') != 'ready' else dict(meta, id=uuid.uuid4().hex, sourceId=key)
            if old and old.get('status') == 'ready':
                old['key'] += ':'+old['id']; self.owner.save_asset(old)
            if not asset.get('workingPath'):
                asset.update(targetStorage=storage, workingPath=str(Path(storage['path'])/'Pixfun Media'/key/asset['id']/meta['fileName']))
            storage = asset['targetStorage']
            target = Path(asset['workingPath'])
            def check():
                if guard: guard()
                if self.cancel.is_set() or self.owner.stopping.is_set(): raise PhoneError('Sync paused. Completed files are kept.', 409)
                if not connected(storage): raise PhoneError('Save location disconnected. Reconnect it and retry.', 409)
                if target.is_symlink() or Path(storage['path']) not in target.resolve().parents: raise PhoneError('Save location changed. Choose it again.', 409)
            check()
            if shutil.disk_usage(storage['path']).free < length + 64*1024**2:
                raise PhoneError('Not enough storage. Free space on the destination and retry.', 409)
            target.parent.mkdir(parents=True, exist_ok=True)
            check()
            with self.owner.lock:
                fd, temporary = tempfile.mkstemp(prefix='.pixfun-phone-', suffix='.partial', dir=target.parent)
                with self.owner.library.connect() as db:
                    db.execute('INSERT INTO sync_partials VALUES (?,?)', (temporary,json.dumps(dict(storage=storage,inode=os.fstat(fd).st_ino))))
                self.owner.active_partials.add(temporary)
                phone.update(status='Importing', total=phone['completed']+1, bytes=0, totalBytes=length, message=meta['fileName'])
                self.save_progress(phone)
            received = 0; last = 0.0
            with os.fdopen(fd, 'wb') as writer:
                while received < length:
                    check()
                    data = reader.read(min(1024*1024, length-received))
                    if not data: raise PhoneError('Connection interrupted. This file will retry.', 409)
                    writer.write(data); received += len(data)
                    if time.monotonic()-last > 0.5:
                        last = time.monotonic()
                        with self.owner.lock:
                            phone.update(bytes=received); self.save_progress(phone)
                writer.flush(); os.fsync(writer.fileno())
            with self.owner.lock:
                phone.update(status='Verifying', bytes=received); self.save_progress(phone)
            if digest(Path(temporary), self.cancel) != meta['sha256']: raise PhoneError('Copy verification failed. This file will retry.', 409)
            check()
            asset['status'] = 'pending'; self.owner.save_asset(asset)
            if target.exists():
                if digest(target) != meta['sha256']: raise PhoneError('Destination contains a different file. It was not replaced.', 409)
            else: publish_exclusive(Path(temporary), target)
            result = self.owner.library.register([str(target)])
            if result['errors'] or not result['items']: raise PhoneError('Copy saved. Retry to finish adding it to Media.', 409)
            mid = result['items'][0]['id']
            self.owner.library.patch(mid, syncSourceId=key, syncSourceName=phone['name'], syncSourceKind='phone', importBatchId=phone.get('batchId'), originalFileName=meta['fileName'])
            asset.update(status='ready', mediaId=mid, archiveStatus='pending')
            self.owner.save_asset(asset)
            with self.owner.lock:
                phone.update(status='Connected', completed=phone['completed']+1, lastSync=time.time(), message='Verified copies are available in Media.')
                self.save_progress(phone)
            self.owner.archive_pending()
            return dict(complete=True, duplicate=False)
        except Exception as exc:
            with self.owner.lock:
                latest = next((p for p in self.phones() if p['id'] == key), None)
                if latest:
                    latest.update(status='Needs Attention', message=self.owner.friendly(exc))
                    self.save(latest)
            raise
        finally:
            with self.owner.lock:
                # A pause issued while copying must survive the stale local record.
                latest = next((p for p in self.phones() if p['id'] == key), None)
                if latest:
                    if not latest['automatic']: latest['status']='Paused'
                    elif latest['status'] in ('Importing','Verifying'): latest['status']='Connected'
                    self.save(latest)
                self.active = None
                if temporary: self.owner.active_partials.discard(temporary)
            try: self.owner.cleanup_partials()
            finally: self.idle.set()

    def save_progress(self, phone):
        latest = next((p for p in self.phones() if p['id'] == phone['id']), None)
        if latest:
            phone['automatic'] = latest['automatic']
            self.save(phone)

    def stop(self, persist=False):
        self.cancel.set()
        self.pairing = None
        server, self.server = self.server, None
        if server:
            server.shutdown(); server.server_close()
            with server.connections_lock:
                for connection in list(server.connections):
                    try: connection.shutdown(socket.SHUT_RDWR)
                    except OSError: pass
        if self.thread: self.thread.join(timeout=3)
        self.idle.wait(timeout=25)
        if persist:
            config = self.config(); config['enabled'] = False; self.save_config(config)


class PhoneServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 4

    def __init__(self, *args):
        self.slots = threading.BoundedSemaphore(4)
        self.connections = set()
        self.connections_lock = threading.Lock()
        super().__init__(*args)

    def verify_request(self, request, address):
        ip = ipaddress.ip_address(address[0])
        return ip.is_private or ip.is_loopback

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request); return
        try: super().process_request(request, address)
        except Exception:
            self.slots.release(); raise

    def process_request_thread(self, request, address):
        try: super().process_request_thread(request, address)
        finally: self.slots.release()

    def handle_error(self, request, address): pass  # No tokens, filenames or TLS errors in logs.


class PhoneHandler(BaseHTTPRequestHandler):
    server_version = 'PixfunSync'
    sys_version = ''

    def setup(self):
        self.request.settimeout(20)
        self.request = self.server.tls.wrap_socket(self.request, server_side=True)
        with self.server.connections_lock: self.server.connections.add(self.request)
        super().setup()

    def finish(self):
        try: super().finish()
        finally:
            with self.server.connections_lock: self.server.connections.discard(self.request)
            self.request.close()

    def log_message(self, *args): pass

    def reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'close')
        self.end_headers(); self.wfile.write(data)
        self.close_connection = True

    def handle_sync(self):
        receiver = self.server.receiver
        try:
            if self.headers.get('Transfer-Encoding'): raise PhoneError('Use a fixed content length.', 400)
            if len(self.headers.get_all('Content-Length', [])) != 1: raise PhoneError('Content length required.')
            length = int(self.headers['Content-Length'])
            if length < 0: raise PhoneError('Invalid content length.')
            # Consume bounded control bodies before replying, including auth failures.
            # Closing a TLS socket with unread request data can reset the connection
            # before the phone receives our actionable error response.
            body = None
            if self.command == 'POST':
                if length > 8192: raise PhoneError('Request too large.', 413)
                body = self.rfile.read(length)
            if self.headers.get('Origin'): raise PhoneError('Use the paired Pixfun phone app.', 403)
            if self.path not in ('/v1/pair', '/v1/status', '/v1/check', '/v1/upload'):
                raise PhoneError('Not found.', 404)
            phone = None if self.path == '/v1/pair' else receiver.authorize(self.headers.get('Authorization', ''))
            if self.path == '/v1/upload':
                if self.command != 'PUT': raise PhoneError('Method not allowed.', 405)
                raw = self.headers.get('X-Pixfun-Media', '')
                if len(raw) > 8192: raise PhoneError('Metadata too large.')
                import base64
                meta = receiver.metadata(json.loads(base64.b64decode(raw, validate=True)))
                result = receiver.receive(phone, meta, self.rfile, length)
            else:
                if self.command != 'POST': raise PhoneError('Method not allowed.', 405)
                value = json.loads(body)
                if not isinstance(value, dict): raise PhoneError('Invalid request.')
                if self.path == '/v1/pair': result = receiver.pair(value)
                elif self.path == '/v1/status':
                    receiver.ready(phone)
                    result = dict(ready=True, photos=phone['photos'], videos=phone['videos'])
                else:
                    storage = receiver.ready(phone)
                    meta = receiver.metadata(value)
                    complete = bool(receiver.existing(phone, meta))
                    if not complete and shutil.disk_usage(storage['path']).free < meta['fileSize'] + 64*1024**2:
                        raise PhoneError('Not enough storage. Free space on the destination and retry.', 409)
                    result = dict(complete=complete)
            self.reply(200, result)
        except PhoneError as exc: self.reply(exc.status, dict(error=str(exc)))
        except (ValueError, TypeError, KeyError): self.reply(400, dict(error='Invalid sync request.'))
        except Exception: self.reply(409, dict(error='Transfer interrupted. Completed files are kept; retry when connected.'))

    do_POST = handle_sync
    do_PUT = handle_sync
