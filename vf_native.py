"""Reference-only projection of a VisionFlow catalog into the native media UI.

The catalog remains authoritative. Pixfun caches its metadata, not source files,
frames or vectors. A refresh never enqueues analysis or resets user edits.
"""
import copy
import hashlib
import json
import math
from pathlib import Path
import sqlite3
import threading
import time
from urllib.parse import quote

from vf_bridge import Catalog, BridgeError
from media_metadata import location_from_tags, device_id_from_tags


def media_id(asset):
    return 'vf-' + hashlib.sha256(asset.encode()).hexdigest()[:24]


def frame_url(shot, frame_id):
    if not frame_id:
        return None
    frame = next((f for f in shot.get('frames', []) if f.get('frame_id') == frame_id), {})
    # A display repair changes pixels without changing the selected frame ID.
    # Version the URL so SwiftUI reloads already-visible images after refresh.
    revision = frame.get('display_sha256') or frame.get('image_sha256') or 'original'
    return '/api/desktop/vf/frame/' + quote(frame_id, safe='') + '?v=' + quote(revision, safe='')


def project_asset(shots):
    first = shots[0]
    meta = first['metadata']
    context = first.get('context') or {}
    origin = float(first['playback']['origin'])
    streams = meta.get('media', {}).get('data', {}).get('streams', [])
    video = next((s for s in streams if s.get('codec_type') == 'video' and not s.get('disposition', {}).get('attached_pic')), {})
    duration = max(float(s['end']) for s in shots) + origin
    width, height = video.get('width'), video.get('height')
    rotation = meta.get('observation', {}).get('transform', {}).get('rotation', 0)
    if abs(float(rotation or 0)) % 180 == 90:
        width, height = height, width
    identity = media_id(first['asset'])
    segments, cues, seen, evidence, tags, excluded = [], [], set(), [], set(), 0
    for s in shots:
        if not math.isclose(float(s['playback']['origin']), origin, abs_tol=1e-9):
            raise ValueError('Mixed playback clocks for one asset')
        start, end = float(s['playback']['start']), float(s['playback']['end'])
        if not all(math.isfinite(x) for x in (start, end)) or not 0 <= start < end:
            raise ValueError('Invalid catalog interval')
        thumb = frame_url(s, s.get('representative'))
        segments.append(dict(id=s['id'], label=f"{s['context'].get('place') or 'Catalog shot'} · {len(segments)+1}",
                             start=start, end=end, thumbnailUrl=thumb, boundary={'type':'catalog_shot'},
                             note=s['context'].get('note', '')))
        tags.update(t['tag'] for t in s.get('tags', []) if t.get('tag'))
        # Scores and context stay evidence, never synthetic editorial truth.
        evidence.append({k: s.get(k) for k in ('id','start','end','scores','context','cover_choice')})
        for t in s.get('transcript_segments', []):
            if t['id'] in seen: continue
            seen.add(t['id'])
            if not t.get('searchable') or t.get('timing_status') == 'legacy_clock_unverified':
                excluded += 1
                continue
            begin, finish = max(origin, float(t['start'])+origin), min(duration, float(t['end'])+origin)
            if finish > begin:
                cues.append(dict(start=begin, end=finish, text=t['text'], human_verified=t.get('human_verified',False)))
    tags.update(filter(None, [context.get('collection'), context.get('date')]))
    source = first['source']
    fp = meta.get('observation', {}).get('fingerprint')
    metadata = dict(width=width, height=height, duration=duration,
                    hasAudio=any(s.get('codec_type')=='audio' for s in streams))
    capture_tags = {}
    for stream in streams:
        capture_tags.update(stream.get('tags', {}))
    capture_tags.update(meta.get('media', {}).get('data', {}).get('format', {}).get('tags', {}))
    capture_tags = {str(k).lower(): v for k, v in capture_tags.items()}
    metadata.update(location=location_from_tags(capture_tags), camera=capture_tags.get('com.apple.quicktime.model') or capture_tags.get('model'),
                    capturedAt=capture_tags.get('com.apple.quicktime.creationdate'), mediaCreatedAt=capture_tags.get('creation_time'),
                    dateSource='QuickTime creationdate' if capture_tags.get('com.apple.quicktime.creationdate') else None,
                    captureDeviceID=device_id_from_tags(capture_tags), captureMetadataVersion=2,
                    videoCodec=video.get('codec_name'),
                    audioCodec=next((a.get('codec_name') for a in streams if a.get('codec_type') == 'audio'), None))
    try:
        num, den = video.get('avg_frame_rate','0/1').split('/')
        metadata['fps'] = float(num)/float(den) if float(den) else None
    except (ValueError, ZeroDivisionError): pass
    record = dict(id=identity, file=dict(name=context.get('original_name') or Path(first['asset']).name,
                  size=fp[1] if fp else None, type='video/mp4'), kind='video', status='ready',
                  metadata=metadata, favorite=False, description='',
                  context=dict(location=context.get('place') or '', source='VisionFlow',
                               collection=context.get('collection') or '', date=context.get('date') or '',
                               locationStatus='confirmed' if context.get('place_confirmed') else 'needs review'),
                  analysisTags=sorted(tags), coverUrl=segments[0]['thumbnailUrl'],
                  url=f'/api/desktop/media/{identity}',
                  result={'analysis':dict(segments=segments, subtitleCues=sorted(cues,key=lambda t:t['start']),
                      subtitleState='catalog', subtitleMessage='Saved machine transcript; flagged or unverified timing entries excluded.')},
                  vfCatalog=dict(asset=first['asset'], collection=context.get('collection') or '',
                      originalSource=context.get('original_source') or source, source=source,
                      fingerprint=fp, origin=origin, shots=evidence, excludedTranscripts=excluded))
    return record, source


def validate_source(record, source):
    info = record.get('vfCatalog')
    if not info: return
    fp = info.get('fingerprint')
    if fp:
        stat = source.stat()
        if (len(fp) < 4 or str(source.resolve()) != fp[0] or stat.st_size != fp[1]
                or stat.st_mtime_ns != fp[2] or (isinstance(fp[3],int) and stat.st_ino != fp[3])):
            raise FileNotFoundError('Catalog source changed. Refresh or repair the VisionFlow catalog before editing.')


class NativeCatalog:
    def __init__(self, state_file, library):
        self.catalog = Catalog(state_file)
        self.library = library
        self.lock = threading.Lock()
        self.status = dict(connected=False, message='Not synchronized', assets=0, shots=0)

    def sync(self):
        if not self.lock.acquire(blocking=False): raise ValueError('Catalog refresh already running')
        try:
            grouped, offset = {}, 0
            while True:
                page = self.catalog.search({'k':100,'offset':offset,'mode':'text'})
                for shot in page: grouped.setdefault(shot['asset'], []).append(shot)
                if len(page) < 100: break
                offset += len(page)
            projected = [project_asset(sorted(shots,key=lambda s:s['start'])) for shots in grouped.values()]
            # Backup before the first catalog import; SQLite backup includes WAL.
            backup = self.library.directory / 'before-visionflow.sqlite3'
            if not backup.exists():
                with self.library.connect() as db, sqlite3.connect(backup) as out: db.backup(out)
            with self.library.lock, self.library.connect() as db:
                for incoming, source in projected:
                    incoming['vfCatalog']['projectedContext'] = copy.deepcopy(incoming['context'])
                    row = db.execute('SELECT id,record,removed FROM media WHERE id=? OR source=?', (incoming['id'],source)).fetchone()
                    if row:
                        previous = json.loads(row[1])
                        # Existing imports retain their identity, annotations and analysis.
                        incoming['id'] = row[0]
                        incoming['url'] = f'/api/desktop/media/{row[0]}'
                        for key in ('favorite','description','title','videoDescription','shotAnalysis',
                                    'tagCorrections','resolvedPlace','locationReview','analysisEvidence',
                                    'mediaAnalysis','analysisRevision','vectorIndex','syncSourceId','syncSourceName',
                                    'syncSourceKind','importBatchId','importedAt'):
                            if key in previous: incoming[key] = previous[key]
                        old_projection = previous.get('vfCatalog', {}).get('projectedContext', {})
                        for key, value in previous.get('context', {}).items():
                            if isinstance(value,str) and (key not in old_projection or value != old_projection[key]): incoming['context'][key] = value
                        if not previous.get('vfCatalog') and previous.get('result'):
                            incoming['result'] = previous['result']
                        db.execute('UPDATE media SET source=?,record=? WHERE id=?', (source,json.dumps(incoming,ensure_ascii=False),row[0]))
                    else:
                        db.execute('INSERT INTO media(id,source,record) VALUES(?,?,?)', (incoming['id'],source,json.dumps(incoming,ensure_ascii=False)))
            self.status = dict(connected=True, message='Using existing VisionFlow analysis', assets=len(projected),
                               shots=sum(len(s) for s in grouped.values()), updatedAt=time.time())
            return self.status
        except Exception as exc:
            self.status = {**self.status, 'connected':False, 'message':str(exc)[:250]}
            raise
        finally:
            self.lock.release()

    def search(self, query='', similar=None, collection=None):
        params = dict(q=query, mode='hybrid', k=30, release_model='1')
        if similar: params['similar'] = similar
        if collection: params['tag'] = collection
        # Reuse the existing vector index, not a second encoder/index in this app.
        found = self.catalog.search(params)
        with self.library.connect() as db:
            mapping = {json.loads(raw).get('vfCatalog',{}).get('asset'): mid for mid,raw in db.execute('SELECT id,record FROM media WHERE removed=0')}
        result = []
        for shot in found:
            if shot['asset'] not in mapping: continue
            origin = shot['playback']['origin']
            result.append(dict(mediaId=mapping[shot['asset']], shotId=shot['id'],
                               start=shot.get('match',{}).get('match_t',shot['start'])+origin,
                               label=shot['context'].get('place') or 'Visual match',
                               thumbnailUrl='/api/desktop/vf/frame/'+quote(shot.get('match',{}).get('match_frame_id') or shot['representative'],safe='')))
        return result
