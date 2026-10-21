#!/usr/bin/env python3
"""Run the Pixfun web frontend against one existing local VisionFlow catalog."""
from __future__ import annotations

import json
import os
import re
from urllib.parse import parse_qs, quote, unquote, urlsplit

import app as engine
from vf_bridge import BridgeError, Catalog, prepare_clip


class Handler(engine.Handler):
    timeout = 30

    def log_message(self, *args):
        pass  # Avoid logging private queries, transcript text and access tokens.

    def local_request(self):
        host = self.headers.get('Host')
        expected = f'127.0.0.1:{self.server.server_port}'
        navigation = (self.command == 'GET' and urlsplit(self.path).path in ('/', '/index.html', '/library')
                      and self.headers.get('Sec-Fetch-Mode') == 'navigate'
                      and self.headers.get('Sec-Fetch-Dest') == 'document')
        return (host == expected and self.client_address[0] == '127.0.0.1'
                and self.headers.get('Origin') in (None, 'http://' + expected)
                and (navigation or self.headers.get('Sec-Fetch-Site') not in ('cross-site', 'same-site'))
                and not any(k.lower().startswith(('forwarded', 'x-forwarded-', 'x-real-ip')) for k in self.headers))

    def end_headers(self):
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        super().end_headers()

    def send_bytes(self, data, kind):
        self.send_response(200)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def fail(self, error):
        self.send_json({'ok': False, 'error': str(error)}, getattr(error, 'status', 400))

    def do_GET(self):
        if not self.local_request():
            return self.send_json({'ok': False, 'error': 'Local same-origin access only.'}, 403)
        parsed = urlsplit(self.path)
        path = parsed.path
        params = {k: v[-1] for k, v in parse_qs(parsed.query).items()}
        catalog = self.server.catalog
        try:
            if path == '/library':
                return self.send_file(engine.PUBLIC / 'vf-library.html')
            if path in ('/', '/index.html'):
                html = (engine.PUBLIC / 'index.html').read_text()
                html = html.replace('</head>', '<script defer src="/assets/vf-entry.js"></script></head>')
                return self.send_bytes(html.encode(), 'text/html; charset=utf-8')
            if path == '/api/vf/status':
                return self.send_json(dict(ok=True, **catalog.json('api/status')))
            if path == '/api/vf/search':
                return self.send_json({'ok': True, 'shots': catalog.search(params)})
            if path == '/api/vf/shot':
                return self.send_json({'ok': True, 'shot': catalog.shot(params.get('shot_id'))})
            if path == '/api/vf/job':
                job = engine.read_job(params.get('id', ''))
                if not job.get('vfSource'):
                    raise BridgeError('This is not a catalog editing job.', 404)
                return self.send_json(dict(ok=True, jobId=job['id'], analysis=job['analysis'],
                                           sourceUrl=engine.media_url('upload', job['id'], 'source.mp4')))
            if path.startswith(('/api/vf/frame/', '/api/vf/video/')):
                kind, ident = path[len('/api/vf/'):].split('/', 1)
                ident = unquote(ident)
                # Frame IDs contain rational time bases (e.g. "1/90000").
                # Encode the entire opaque ID; vf-agent resolves it with SQL,
                # never as a filesystem path.
                if not ident or len(ident) > 500 or any(ord(c) < 32 for c in ident):
                    raise BridgeError('Invalid media ID.')
                headers = {'Range': self.headers['Range']} if self.headers.get('Range') else {}
                with catalog.open(kind + '/' + quote(ident, safe=''), headers=headers) as response:
                    self.send_response(response.status)
                    for name in ('Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges'):
                        if response.headers.get(name):
                            self.send_header(name, response.headers[name])
                    self.send_header('Cache-Control', 'no-store')
                    self.end_headers()
                    while block := response.read(256 * 1024):
                        self.wfile.write(block)
                return
            if path.startswith('/api/vf/'):
                raise BridgeError('Unknown catalog endpoint.', 404)
            return super().do_GET()
        except (BrokenPipeError, ConnectionResetError):
            pass
        except FileNotFoundError:
            self.fail(BridgeError('Editing job not found.', 404))
        except (BridgeError, ValueError, KeyError, TypeError) as exc:
            self.fail(exc)

    def do_POST(self):
        if not self.local_request():
            return self.send_json({'ok': False, 'error': 'Local same-origin access only.'}, 403)
        path = urlsplit(self.path).path
        if path == '/api/vision':
            return self.fail(BridgeError('Cloud analysis is disabled in catalog integration mode.', 403))
        if path == '/api/vf/use-shot':
            try:
                if self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
                    raise BridgeError('Expected JSON.')
                size = int(self.headers.get('Content-Length', 0))
                if not 0 < size <= 4096:
                    self.close_connection = True
                    raise BridgeError('Invalid request size.', 413)
                data = json.loads(self.rfile.read(size))
                if not isinstance(data, dict) or set(data) != {'shot_id'}:
                    raise BridgeError('Only shot_id is accepted.')
                return self.send_json(prepare_clip(self.server.catalog, engine, data['shot_id']))
            except (BridgeError, ValueError, TypeError, KeyError) as exc:
                return self.fail(exc)
        if path.startswith('/api/vf/'):
            return self.fail(BridgeError('Unknown catalog endpoint.', 404))
        if path == '/api/render':
            if not self.server.catalog.work_lock.acquire(blocking=False):
                return self.fail(BridgeError('Another clip or render is running.', 409))
            try:
                return super().do_POST()
            finally:
                self.server.catalog.work_lock.release()
        return super().do_POST()


def main():
    state = os.environ.get('VF_LIBRARY_STATE')
    if not state:
        raise SystemExit('Set VF_LIBRARY_STATE to the unified catalog server.json path.')
    catalog = Catalog(state)
    catalog.json('api/status')  # Fail early; do not silently fall back to demo data.
    server = engine.ThreadingHTTPServer(('127.0.0.1', int(os.environ.get('PIXFUN_PORT', '8765'))), Handler)
    server.catalog = catalog
    print(f'Pixfun + VisionFlow: http://127.0.0.1:{server.server_port}/library', flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
