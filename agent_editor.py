"""Read-only, bounded native editor assistance. No model calls or skill loading."""
import hashlib
import json
import math
import re
import threading


def source_speech(engine, record, path):
    """Only source-bound cached speech or current local subtitle evidence. No ASR."""
    from transcript_quality import checked_cues
    from app import local_subtitle_track
    if record['kind'] != 'video' or record['status'] != 'ready' or (record.get('metadata') or {}).get('hasAudio') is False or not path.is_file():
        return None
    revision = source_revision(path); stat = path.stat()
    analysis = (record.get('result') or {}).get('analysis') or {}
    state = analysis.get('subtitleState')
    kind = 'subtitle'
    if analysis.get('subtitleSource') == 'local-asr' and state in ('transcribed', 'partial'):
        signature = hashlib.sha256(f'{path}:{stat.st_size}:{stat.st_mtime_ns}:speech:{engine.models.speech}'.encode()).hexdigest()
        if record.get('analysisRevision'):
            signature = hashlib.sha256((signature+record['analysisRevision']).encode()).hexdigest()
        if analysis.get('subtitleSignature') != signature:
            return None
        kind = 'asr'
    elif state in ('sidecar', 'embedded'):
        file = record.get('file') or {}
        if file.get('size') != stat.st_size or file.get('lastModified') != int(stat.st_mtime * 1000):
            return None
        if state == 'sidecar':
            # Read the current caption file; never reuse a removed/edited sidecar.
            analysis = local_subtitle_track(path)
            if not analysis.get('subtitleCues'):
                return None
    else:
        return None
    duration = (record.get('metadata') or {}).get('duration')
    if not isinstance(duration, (int, float)) or not math.isfinite(duration) or duration <= 0:
        return None
    raw = analysis.get('subtitleCues') or []
    if not isinstance(raw, list) or len(raw) > 5000:
        return None
    cues = [c for c in raw if isinstance(c, dict) and isinstance(c.get('text'), str) and c['text'].strip()
            and not re.fullmatch(r'\s*(?:\[[^\]]*\]|\([^)]*\)|（[^）]*）|[♪♫\s]+)\s*', c['text'])]
    cues = checked_cues(cues, duration)[0]
    # Reject explicitly uncertain/non-source evidence, not just invalid times.
    cues = [dict(start=c['start'], end=c['end'], text=c['text'].strip()[:1000]) for c in cues
            if c['end'] <= duration and c.get('time_domain', 'source_audio') in ('source_audio', 'source_video')
            and c.get('timing_status') not in ('unreliable', 'rejected', 'proxy')
            and c.get('trust') not in ('unquotable', 'rejected') and c.get('searchable', True)]
    if revision != source_revision(path):
        return None
    evidence = hashlib.sha256(json.dumps([revision, kind, cues], ensure_ascii=False, sort_keys=True).encode()).hexdigest()
    return dict(mediaId=record['id'], revision=revision, evidenceRevision=evidence, kind=kind, duration=duration, cues=cues)


def source_revision(path):
    stat = path.stat()
    return hashlib.sha256(f'{path.resolve()}:{stat.st_size}:{stat.st_mtime_ns}'.encode()).hexdigest()


def assist(engine, payload):
    from agent_engine import validate_timeline, number
    from shot_analysis import analysis_signature
    action = payload.get('action')
    if action not in ('review', 'replace', 'validate', 'trim', 'validate-trim'):
        raise ValueError('Unknown editor assistance action')
    run = engine.get(payload.get('id'))
    if payload.get('version') != run['version'] or run['status'] not in ('completed', 'review'):
        raise ValueError('The timeline changed. Reopen the editor before retrying.')
    records, paths = {}, {}
    # Only this project's sources; payloads never supply filesystem paths.
    for mid in run['mediaIds']:
        try:
            record, path = engine.library.get(mid)
        except FileNotFoundError:
            continue
        if record['kind'] in ('video', 'image'):
            records[mid], paths[mid] = record, path
    raw = payload.get('shots')
    if not isinstance(raw, list) or any(not isinstance(s, dict) or not isinstance(s.get('id'), str) or not s['id'] for s in raw):
        raise ValueError('Invalid editor timeline')
    shots = validate_timeline(raw, records)
    target = next((s for s in shots if s['id'] == payload.get('shotId')), None)
    if action != 'review' and (target is None or target['locked'] or any(s['id'] == target['id'] and s.get('locked') for s in run['timeline'])):
        raise ValueError('Select an unlocked clip')
    speech = source_speech(engine, records[target['mediaId']], paths[target['mediaId']]) if action in ('trim', 'validate-trim') else None
    if action == 'validate':
        candidate = payload.get('candidate') or {}
        mid = candidate.get('mediaId'); record = records.get(mid); path = paths.get(mid)
        if not record or record['status'] != 'ready' or not path.is_file() or source_revision(path) != candidate.get('revision'):
            raise ValueError('Replacement source changed or is unavailable. Reopen Replace.')
        limit = 60 if record['kind'] == 'image' else (record.get('metadata') or {}).get('duration', 0)
        a, b = number(candidate.get('start'), 0, limit), number(candidate.get('end'), 0, limit)
        if abs((b-a)-(target['end']-target['start'])) > .001 or (record['kind'] == 'image' and a != 0):
            raise ValueError('Replacement must preserve this clip duration')
        return {'ok': True, 'recommendations': [], 'issues': []}
    sources = []
    if action == 'replace':
        for mid, record in records.items():
            path = paths[mid]
            if record['status'] != 'ready' or not path.is_file():
                continue
            revision = source_revision(path)
            analysis = record.get('shotAnalysis') or {}
            # Stale cached observations cannot recommend exact source ranges.
            valid = analysis.get('status') == 'ready' and analysis.get('signature') == analysis_signature(engine, record, path, run.get('mode', 'local'))
            segments = analysis.get('segments', []) if valid else []
            sources.append(dict(id=mid, kind=record['kind'], duration=(record.get('metadata') or {}).get('duration', 0),
                revision=revision, segments=segments,
                description=record.get('description') or (record.get('videoDescription') or {}).get('full_description', '')))
            if revision != source_revision(path):
                sources.pop()
    cancel = threading.Event()
    timer = threading.Timer(12, cancel.set)
    timer.daemon = True; timer.start()
    try:
        result = engine.models.story(dict(action='editor', mode=action, shots=shots,
            kinds={mid: r['kind'] for mid, r in records.items()}, sources=sources, shotId=payload.get('shotId'), speech=speech), cancel)
    finally:
        timer.cancel()
    if engine.get(run['id'])['version'] != run['version']:
        raise ValueError('The timeline changed. Retry with the current edit.')
    if speech and source_revision(paths[speech['mediaId']]) != speech['revision']:
        raise ValueError('Source changed. Reopen the clip to refresh speech boundaries.')
    if action == 'validate-trim':
        candidate = payload.get('candidate') or {}
        guide = result.get('speech')
        if not guide or any(candidate.get(k) != guide.get(k) for k in ('mediaId', 'revision', 'evidenceRevision')) or not any(
                candidate.get('edge') == b['edge'] and candidate.get('time') == b['time'] for b in guide['boundaries']):
            raise ValueError('Speech timing changed. Reopen the clip to refresh boundaries.')
    return result
