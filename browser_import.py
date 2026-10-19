"""One QR, one browser-selected batch. Upload-only, opt-in, trusted HTTPS.

No insecure fallback, reverse tunnel, desktop API forwarding or persistent pairing.
Production setup is documented in mobile/BROWSER-IMPORT.md.
"""
import hashlib
import hmac
import io
import ipaddress
import json
import os
from pathlib import Path
import secrets
import ssl
import threading
import time
from urllib.parse import urlsplit

from phone_sync import PhoneError, PhoneHandler, PhoneServer


class BrowserImport:
    MAX_FILE = 8 * 1024**3
    MAX_FILES = 200
    SOURCE = 'browser-phone-import'

    def __init__(self, owner):
        self.owner = owner
        self.server = self.thread = None
        self.session = None
        self.origin = None
        self.error = None
        self.operation = threading.Lock()
        self.analysis = None
        self.peer = None
        self.pair_origin = None

    def settings(self):
        origin = os.environ.get('PIXFUN_PHONE_WEB_ORIGIN', '').rstrip('/')
        parsed = urlsplit(origin)
        if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password
                or parsed.path or parsed.query or parsed.fragment):
            raise PhoneError('Phone import needs a trusted HTTPS address. Configure the phone web origin and TLS certificate first.')
        cert = os.environ.get('PIXFUN_PHONE_WEB_CERT', '')
        key = os.environ.get('PIXFUN_PHONE_WEB_KEY', '')
        if not cert or not key or not Path(cert).is_file() or not Path(key).is_file():
            raise PhoneError('Phone import needs a browser-trusted TLS certificate and private key.')
        return origin, cert, key, parsed.port or 443

    def start(self):
        if self.server: return
        if not os.environ.get('PIXFUN_PHONE_WEB_ORIGIN'):
            from phone_peer import DEFAULT_ORIGIN
            self.pair_origin = os.environ.get('PIXFUN_PHONE_PAIR_ORIGIN', DEFAULT_ORIGIN)
            if not self.pair_origin: raise PhoneError('Secure phone pairing is unavailable.')
            return
        origin, cert, key, port = self.settings()
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(cert, key)
        # Verify both trust chain and hostname before ever presenting a QR.
        # Explicit, opt-in LAN QA trust. Apple's LibreSSL may ignore SSL_CERT_FILE;
        # load the test CA only for this receiver's preflight, never system-wide.
        test_ca = os.environ.get('PIXFUN_PHONE_TEST_CA_FILE')
        bind_host = '0.0.0.0'
        if test_ca:
            try:
                address = ipaddress.IPv4Address(urlsplit(origin).hostname)
                private = any(address in ipaddress.ip_network(net) for net in
                              ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'))
            except ValueError:
                private = False
            if os.environ.get('PIXFUN_PHONE_LAN_TEST') != '1' or not private:
                raise PhoneError('Test certificates are only allowed in explicit private-LAN test mode.')
            bind_host = str(address)
        verifier = ssl.create_default_context(cafile=test_ca or None)
        client_in, client_out = ssl.MemoryBIO(), ssl.MemoryBIO()
        server_in, server_out = ssl.MemoryBIO(), ssl.MemoryBIO()
        client = verifier.wrap_bio(client_in, client_out, server_hostname=urlsplit(origin).hostname)
        server = context.wrap_bio(server_in, server_out, server_side=True)
        client_done = server_done = False
        try:
            for _ in range(20):
                if not client_done:
                    try: client.do_handshake(); client_done = True
                    except ssl.SSLWantReadError: pass
                server_in.write(client_out.read())
                if not server_done:
                    try: server.do_handshake(); server_done = True
                    except ssl.SSLWantReadError: pass
                client_in.write(server_out.read())
                if client_done and server_done: break
            if not client_done or not server_done: raise ssl.SSLError('Handshake incomplete')
        except ssl.SSLError:
            raise PhoneError('The phone import certificate is not trusted or does not match its HTTPS hostname.') from None
        listener = PhoneServer((bind_host, port), BrowserHandler)
        listener.receiver = self
        listener.tls = context
        self.origin = origin
        self.server = listener
        self.thread = threading.Thread(target=listener.serve_forever, daemon=True)
        self.thread.start()

    def begin(self, payload):
        with self.owner.lock:
            if self.owner.stopping.is_set(): raise PhoneError('Pixfun is closing.')
            if self.operation.locked() or self.owner.phone_sync.busy(self.SOURCE): raise PhoneError('Wait for the current file before creating a new code.')
            if payload.get('workingPath'):
                self.owner.configure_storage(dict(kind='working', path=payload['workingPath']))
            from media_sync import connected
            if not connected(self.owner.storage().get('working')): raise PhoneError('Choose a connected save location first.')
            try: self.start()
            except (ValueError, OSError) as exc:
                self.error = str(exc) if isinstance(exc, PhoneError) else 'Could not start secure phone import. Check the HTTPS configuration and port.'
                raise PhoneError(self.error) from None
            self.error = None
            self.session = dict(secret=secrets.token_urlsafe(32), expiresAt=time.time()+300,
                phase='waiting', completed=0, skipped=0, total=0, bytes=0, totalBytes=0,
                error=None, manifest={}, done=set(), batch=secrets.token_hex(16))
            if self.peer: self.peer.stop(); self.peer = None
            if self.pair_origin:
                from phone_peer import PeerSession
                self.peer = PeerSession(self,self.session,self.pair_origin)
            peer = self.peer
        if peer:
            try: peer.start()
            except PhoneError as exc:
                with self.owner.lock:
                    self.session.update(phase='idle',error=str(exc)); self.error=str(exc)
                raise

    def snapshot(self):
        with self.owner.lock:
            s = self.session
            if not s: return dict(phase='idle', error=self.error)
            self.expire(s)
            result = {k: s[k] for k in ('phase','expiresAt','completed','skipped','total','error')}
            if s['phase'] == 'waiting':
                if self.peer:
                    if self.peer.public_url: result['url'] = self.peer.public_url
                else: result['url'] = self.origin+'/import#'+s['secret']
            if self.owner.phone_sync.busy(self.SOURCE):
                phone = next((p for p in self.owner.phone_sync.phones() if p['id'] == self.SOURCE), {})
                result.update(bytes=phone.get('bytes', 0), totalBytes=phone.get('totalBytes', 0))
            return result

    def expire(self, s):
        if s['phase'] not in ('complete','cancelled','expired') and time.time() >= s['expiresAt']:
            s.update(phase='expired', error='This session expired. Scan a new code on your Mac.')
            if self.owner.phone_sync.busy(self.SOURCE): self.owner.phone_sync.cancel.set()

    def claim(self, value):
        with self.owner.lock:
            s = self.session
            secret, client = value.get('secret'), value.get('client')
            if not s or not isinstance(secret, str) or not hmac.compare_digest(secret, s['secret']):
                raise PhoneError('This code is no longer available. Scan a new code on your Mac.', 401)
            self.expire(s)
            if not isinstance(client, str) or len(client) != 64: raise PhoneError('Invalid browser session.')
            if s['phase'] == 'waiting':
                s.update(phase='connected', client=client, token=secrets.token_urlsafe(32), expiresAt=time.time()+7200)
            elif s['phase'] != 'connected' or s.get('client') != client:
                raise PhoneError('This code was used or expired. Scan a new code on your Mac.', 401)
            return dict(token=s['token'], expiresAt=s['expiresAt'], maxFile=self.MAX_FILE, maxFiles=self.MAX_FILES)

    def authorize(self, header):
        s = self.session
        if not s: raise PhoneError('Scan a new code on your Mac.', 401)
        self.expire(s)
        if (s['phase'] in ('waiting','cancelled','expired') or not header.startswith('Bearer ')
                or not hmac.compare_digest(header[7:], s.get('token', ''))):
            raise PhoneError('Session ended. Scan a new code on your Mac.', 401)
        return s

    def metadata(self, value):
        meta = self.owner.phone_sync.metadata(value)
        if meta['fileSize'] > self.MAX_FILE: raise PhoneError('Each file must be 8 GB or smaller.', 413)
        # Content identity survives filenames, new browsers and future QR sessions.
        meta['key'] = meta['sha256']
        return meta

    def start_batch(self, s, value):
        files = value.get('files')
        if not isinstance(files, list) or not 1 <= len(files) <= self.MAX_FILES:
            raise PhoneError('Choose between 1 and 200 photos or videos.')
        metadata = [self.metadata(v) for v in files]
        manifest = {m['key']: m for m in metadata}
        if len(manifest) != len(metadata): raise PhoneError('Remove identical files from this selection.')
        if s['phase'] == 'uploading' and s['manifest'] == manifest: return dict(ready=True)
        if s['phase'] != 'connected': raise PhoneError('This batch is already started or complete.', 409)
        receiver = self.owner.phone_sync
        old = next((p for p in receiver.phones() if p['id'] == self.SOURCE), {})
        phone = dict(id=self.SOURCE, name='Phone import', kind='phone', browserImport=True,
            credential=old.get('credential', hashlib.sha256(secrets.token_bytes(32)).hexdigest()),
            automatic=True, photos=True, videos=True, status='Connected', message='', lastSync=None,
            completed=0, total=0, failed=0, skipped=0, bytes=0, totalBytes=0, batchId=s['batch'])
        receiver.ready(phone)
        receiver.save(phone)
        s.update(manifest=manifest, total=len(manifest), phase='uploading')
        return dict(ready=True)

    def selected(self, s, value):
        if s['phase'] != 'uploading': raise PhoneError('This batch is not accepting files.', 409)
        meta = self.metadata(value)
        if s['manifest'].get(meta['key']) != meta: raise PhoneError('File is not in this batch.', 403)
        return meta

    def phone(self):
        return next(p for p in self.owner.phone_sync.phones() if p['id'] == self.SOURCE)

    def record_done(self, s, meta, duplicate):
        with self.owner.lock:
            if meta['key'] not in s['done']:
                s['done'].add(meta['key'])
                s['skipped' if duplicate else 'completed'] += 1
            s['error'] = None

    def check(self, s, value):
        meta = self.selected(s, value)
        complete = bool(self.owner.phone_sync.existing(self.phone(), meta))
        if complete: self.record_done(s, meta, True)
        return dict(complete=complete)

    def receive(self, s, value, reader, length):
        meta = self.selected(s, value)
        def guard():
            with self.owner.lock:
                self.expire(s)
                if self.session is not s or s['phase'] != 'uploading':
                    raise PhoneError('Session ended. Completed files are kept.', 401)
        result = self.owner.phone_sync.receive(self.phone(), meta, reader, length, guard=guard)
        self.record_done(s, meta, result['duplicate'])
        if not result['duplicate'] and self.analysis:
            asset = next(a for a in self.owner.assets(self.SOURCE) if a['key'] == meta['key'])
            try: self.analysis(asset['mediaId'])
            except Exception:
                self.owner.library.patch(asset['mediaId'], phoneImportAnalysis={'status':'failed',
                    'message':'Local analysis could not start. Imported files are kept.'})
        return result

    def complete(self, s):
        if s['phase'] == 'complete': return dict(complete=True, completed=s['completed'], skipped=s['skipped'])
        if s['phase'] != 'uploading' or set(s['manifest']) != s['done']:
            raise PhoneError('Some files are not finished. Retry the remaining files.', 409)
        s.update(phase='complete', secret='', error=None)
        return dict(complete=True, completed=s['completed'], skipped=s['skipped'])

    def cancel_session(self):
        with self.owner.lock:
            if self.session: self.session.update(phase='cancelled', secret='', token='')
            if self.owner.phone_sync.busy(self.SOURCE): self.owner.phone_sync.cancel.set()
            if self.peer: self.peer.stop()

    def stop(self):
        self.cancel_session()
        server, self.server = self.server, None
        if server:
            server.shutdown(); server.server_close()
            with server.connections_lock:
                for connection in list(server.connections):
                    try: connection.shutdown(2)
                    except OSError: pass
        if self.thread: self.thread.join(timeout=3)


class BrowserHandler(PhoneHandler):
    """Same-origin browser API; no desktop API, directory listing or media reads."""
    ASSETS = {'/import': ('phone-import.html','text/html; charset=utf-8'),
              '/phone-import.js': ('phone-import.js','text/javascript'),
              '/phone-import.css': ('phone-import.css','text/css'),
              '/phone-sha256.js': ('phone-sha256.js','text/javascript')}

    def send_data(self, status, data, content_type):
        self.send_response(status)
        for key, value in {'Content-Type':content_type, 'Content-Length':str(len(data)),
            'Cache-Control':'no-store', 'Connection':'close', 'X-Content-Type-Options':'nosniff',
            'Referrer-Policy':'no-referrer', 'Permissions-Policy':'camera=(), microphone=(), geolocation=()',
            'Content-Security-Policy':"default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"}.items():
            self.send_header(key,value)
        self.end_headers(); self.wfile.write(data); self.close_connection = True

    def reply(self, status, payload): self.send_data(status,json.dumps(payload).encode(),'application/json')

    def valid_host(self):
        if self.headers.get('Host') != urlsplit(self.server.receiver.origin).netloc:
            raise PhoneError('Invalid host.', 403)

    def do_GET(self):
        try:
            self.valid_host()
            if self.path not in self.ASSETS: raise PhoneError('Not found.',404)
            file, mime = self.ASSETS[self.path]
            self.send_data(200,(Path(__file__).parent/'phone-web'/file).read_bytes(),mime)
        except PhoneError as exc: self.reply(exc.status,dict(error=str(exc)))
        except OSError: self.reply(503,dict(error='Phone import page is unavailable.'))

    def handle_import(self):
        receiver = self.server.receiver
        acquired = False
        session = None
        try:
            if self.headers.get('Transfer-Encoding'): raise PhoneError('Use a fixed content length.')
            length = int(self.headers.get('Content-Length','-1'))
            if length < 0: raise PhoneError('Invalid content length.')
            # Drain small bodies before errors so TLS close does not hide the response.
            body = self.rfile.read(length) if length <= 8192 or self.command == 'POST' and length <= 200_000 else None
            self.valid_host()
            if self.headers.get('Origin') != receiver.origin: raise PhoneError('Open this page from the QR code.',403)
            routes = {'/import/session','/import/status','/import/start','/import/check','/import/complete'}
            if self.path not in routes | {'/import/file'}: raise PhoneError('Not found.',404)
            if self.command != ('PUT' if self.path == '/import/file' else 'POST'): raise PhoneError('Method not allowed.',405)
            if length > (receiver.MAX_FILE if self.path == '/import/file' else 200_000): raise PhoneError('Request too large.',413)
            acquired = receiver.operation.acquire(blocking=False)
            if not acquired: raise PhoneError('Another request is running. Retry shortly.',409)
            if self.path == '/import/file':
                raw = self.headers.get('X-Pixfun-Media','')
                if len(raw) > 8192: raise PhoneError('Invalid metadata.')
                import base64
                value = json.loads(base64.b64decode(raw,validate=True))
            else:
                value = json.loads(body)
            if not isinstance(value,dict): raise PhoneError('Invalid request.')
            with receiver.owner.lock:
                if self.path == '/import/session': result = receiver.claim(value)
                else:
                    session = receiver.authorize(self.headers.get('Authorization',''))
                    if self.path == '/import/status':
                        result = dict(phase=session['phase'],completed=session['completed'],skipped=session['skipped'],total=session['total'],maxFile=receiver.MAX_FILE,maxFiles=receiver.MAX_FILES)
                    elif self.path == '/import/start': result = receiver.start_batch(session,value)
                    elif self.path == '/import/complete': result = receiver.complete(session)
            # Hashing, receiving and disk verification must not block desktop polling.
            if self.path == '/import/check': result = receiver.check(session,value)
            elif self.path == '/import/file': result = receiver.receive(session,value,io.BytesIO(body) if body is not None else self.rfile,length)
            self.reply(200,result)
        except PhoneError as exc:
            if session: session['error'] = str(exc)
            self.reply(exc.status,dict(error=str(exc)))
        except (ValueError,TypeError,KeyError): self.reply(400,dict(error='Invalid import request.'))
        except Exception:
            if session: session['error'] = 'Transfer interrupted. Retry from your phone.'
            self.reply(409,dict(error='Transfer interrupted. Completed files are kept. Retry the remaining files.'))
        finally:
            if acquired: receiver.operation.release()

    do_POST = handle_import
    do_PUT = handle_import
