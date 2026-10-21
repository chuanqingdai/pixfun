"""Local HTTP adapter for an existing vf-agent catalog; no models or DB copies."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


class BridgeError(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Catalog:
    def __init__(self, state_file):
        self.state_file = Path(state_file).expanduser()
        self.opener = build_opener(ProxyHandler({}), NoRedirect())
        self.work_lock = threading.Lock()

    def base(self):
        try:
            url = json.loads(self.state_file.read_text())['url']
            parsed = urlsplit(url)
            if (parsed.scheme != 'http' or parsed.hostname != '127.0.0.1'
                    or parsed.username or parsed.password or not parsed.port
                    or parsed.query or parsed.fragment
                    or not re.fullmatch(r'/[A-Za-z0-9_-]{32}/', parsed.path)):
                raise ValueError('Invalid catalog address')
            return url
        except (OSError, ValueError, KeyError, TypeError):
            raise BridgeError('Configure VF_LIBRARY_STATE with the running catalog server.json.', 503)

    def open(self, route, *, headers=None):
        # Routes are built by the adapter, never an arbitrary URL from a browser.
        try:
            return self.opener.open(Request(self.base() + route, headers=headers or {}), timeout=120)
        except HTTPError as exc:
            try:
                message = json.loads(exc.read(8192)).get('error', 'Catalog request failed')
            except (ValueError, AttributeError):
                message = 'Catalog request failed'
            finally:
                exc.close()
            raise BridgeError(message, exc.code)
        except (URLError, TimeoutError, ConnectionError):
            raise BridgeError('The VisionFlow catalog is offline. Start library serve, then retry.', 503)

    def json(self, route, params=None):
        with self.open(route + ('?' + urlencode(params) if params else '')) as response:
            raw = response.read(32 * 1024 * 1024 + 1)
        if len(raw) > 32 * 1024 * 1024:
            raise BridgeError('Catalog response too large. Reduce the page size.', 502)
        try:
            return json.loads(raw)
        except ValueError:
            raise BridgeError('Invalid catalog response.', 502)

    def shot(self, shot_id):
        if not isinstance(shot_id, str) or not 0 < len(shot_id) <= 500:
            raise BridgeError('A valid shot ID is required.')
        return self.json('api/shot', {'shot_id': shot_id})

    def search(self, params):
        allowed = {'q', 'mode', 'similar', 'tag', 'place', 'date', 'k', 'offset', 'release_model'}
        if set(params) - allowed:
            raise BridgeError('Unsupported search parameter.')
        if not 1 <= int(params.get('k', 48)) <= 100 or int(params.get('offset', 0)) < 0:
            raise BridgeError('Use a page size between 1 and 100.')
        options = {'k': 48}
        options.update(params)
        return self.json('api/search', options)


def clip_analysis(shot, metadata):
    """Map video-relative catalog evidence into a zero-based editing clip."""
    start, end = float(shot['start']), float(shot['end'])
    span = end - start
    segment = dict(id='seg-1', label=shot['context'].get('place') or 'Catalog shot',
                   start=0., end=span, duration=span, percent=100,
                   boundary={'type': 'catalog_shot'}, containedCutCount=0,
                   note=shot['context'].get('note', ''), thumbnailFit='native')
    if shot.get('representative'):
        segment['thumbnailUrl'] = '/api/vf/frame/' + quote(shot['representative'], safe='')
    cues, excluded = [], []
    for word in shot.get('transcript_segments', []):
        # Unverified clock mappings and flagged ASR must never become edit text.
        if not word.get('searchable') or word.get('timing_status') == 'legacy_clock_unverified':
            excluded.append(word)
            continue
        lo, hi = max(start, word['overlap_start']), min(end, word['overlap_end'])
        if hi > lo:
            cues.append(dict(start=lo-start, end=hi-start, text=word['text'],
                             human_verified=word.get('human_verified', False),
                             sourceStart=word['start'], sourceEnd=word['end'],
                             clipped=word['start'] < start or word['end'] > end))
    return dict(sourceName=shot['asset'], metadata=metadata, cuts=[], cutCount=0,
                segments=[segment], subtitleCues=cues,
                subtitleState='catalog' if cues else 'unavailable',
                subtitleMessage='Catalog transcript; machine text needs review. Cross-shot sentences retain full text with clipped timing.',
                transcript='\n'.join(c['text'] for c in cues), transcriptState='Catalog transcript',
                structureCues=[], tracks={'scenes': [segment], 'subtitles': cues, 'structure': []},
                catalogEvidence=dict(shotId=shot['id'], start=start, end=end,
                                     playback=shot['playback'], context=shot['context'],
                                     scores=shot['scores'], tags=shot['tags'],
                                     coverChoice=shot.get('cover_choice'),
                                     excludedTranscripts=excluded))


def prepare_clip(catalog, engine, shot_id):
    if not catalog.work_lock.acquire(blocking=False):
        raise BridgeError('Another clip or render is running. Retry when it finishes.', 409)
    try:
        shot = catalog.shot(shot_id)
        start, end = float(shot['playback']['start']), float(shot['playback']['end'])
        span = end - start
        if not shot['online']:
            raise BridgeError('Source media is offline. Reconnect its disk before editing.', 409)
        if not all(math.isfinite(v) for v in (start, end)) or start < 0 or not 0 < span <= 600:
            raise BridgeError('This pilot accepts individual shots of up to 10 minutes.')
        media_route = 'video/' + quote(shot['id'], safe='')
        # The catalog validates the source fingerprint, even when reusing a job.
        with catalog.open(media_route, headers={'Range': 'bytes=0-0'}) as response:
            response.read(1)
        identity = json.dumps({'version': 1, 'shot': shot}, sort_keys=True, ensure_ascii=False)
        job_id = hashlib.sha256(identity.encode()).hexdigest()[:12]
        try:
            job = engine.read_job(job_id)
            if Path(job['sourcePath']).is_file():
                return dict(ok=True, jobId=job_id, analysis=job['analysis'],
                            sourceUrl=engine.media_url('upload', job_id, 'source.mp4'), reused=True)
        except FileNotFoundError:
            pass
        folder = engine.UPLOADS / job_id
        folder.mkdir(parents=True, exist_ok=True)
        temporary, target = folder / 'source.pending.mp4', folder / 'source.mp4'
        try:
            code, _, _ = engine.run_command([
                'ffmpeg', '-nostdin', '-v', 'error', '-y', '-threads', '2',
                '-filter_threads', '2', '-rw_timeout', '30000000', '-ss', str(start),
                '-i', catalog.base() + media_route, '-t', str(span),
                '-map', '0:v:0', '-map', '0:a:0?', '-sn',
                '-vf', 'scale=w=min(1280\\,iw):h=min(1280\\,ih):force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1',
                '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-threads', '2',
                '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k',
                '-movflags', '+faststart', str(temporary)], timeout=900)
            if code != 0 or not temporary.is_file():
                raise BridgeError('Could not prepare this shot. Check the source and FFmpeg.', 502)
            metadata = engine.probe_media(temporary)
            if not metadata.get('available') or abs(metadata.get('duration', 0) - span) > .15:
                raise BridgeError('Prepared clip duration does not match the shot. No job was saved.', 502)
            temporary.replace(target)
            analysis = clip_analysis(shot, metadata)
            job = dict(id=job_id, createdAt=int(time.time()), sourcePath=str(target),
                       analysis=analysis, vfSource=dict(shotId=shot_id, start=shot['start'],
                                                      end=shot['end'], playback=shot['playback']))
            engine.write_job(job)
            return dict(ok=True, jobId=job_id, analysis=analysis,
                        sourceUrl=engine.media_url('upload', job_id, 'source.mp4'), reused=False)
        finally:
            temporary.unlink(missing_ok=True)
    finally:
        catalog.work_lock.release()
