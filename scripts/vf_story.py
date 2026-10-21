"""Thin adapter to VisionFlow's native story handoff and story-create compiler.

No second catalog, model, skill, renderer, or UI. Paths come from the host library,
never from the model's proposal. Engine review flags are advisory, not approval.
"""
from pathlib import Path
import math
import re


def speech_boundaries(speech):
    """Cue-level sentence references, never fabricated word alignment or snapping."""
    if not speech:
        return None
    from vf_agent.story_hints import handoff
    row = dict(id=speech['mediaId'], name=speech['mediaId'], kind='video', duration=speech['duration'], source_fingerprint=speech['revision'])
    docs = [dict(record_id=row['id'], kind='source_asr', text=c['text'], start=c['start'], end=c['end'],
        time_domain='source_audio', status='machine_unreviewed', timing_status='cue_level') for c in speech['cues']]
    items = handoff([row], docs, [])['items']
    cues = sorted([dict(start=i['source_range'][0], end=i['source_range'][1], text=i['transcript']) for i in items], key=lambda c: (c['start'], c['end']))
    # Overlapping speakers/captions cannot provide an unambiguous cutting point.
    valid = []; previous_end = -1
    for i, c in enumerate(cues):
        overlaps = c['start'] < previous_end or (i+1 < len(cues) and cues[i+1]['start'] < c['end'])
        previous_end = max(previous_end, c['end'])
        if not overlaps:
            valid.append(c)
    boundaries = []; group = []
    def flush():
        if not group:
            return
        # A long continuous transcript is not proof of a single precise sentence.
        if group[-1]['end']-group[0]['start'] <= 35:
            text = ' '.join(c['text'] for c in group)[:280]
            boundaries.extend([dict(time=group[0]['start'], edge='start', text=text), dict(time=group[-1]['end'], edge='end', text=text)])
        group.clear()
    for c in valid:
        if group and c['start']-group[-1]['end'] >= .35:
            flush()
        group.append(c)
        if re.search(r'[。！？.!?][”’"\u0027）)]*$', c['text'].rstrip()):
            flush()
    flush()
    return {k: speech[k] for k in ('mediaId', 'revision', 'evidenceRevision', 'kind')} | dict(boundaries=boundaries)


def editor_assist(job):
    """Engine evidence coverage + editorial audit, adapted to one native timeline.

    Ranking is a transparent cached-text/role match, not a new semantic model or
    aesthetic score. No story-cut catalog or second editor is created.
    """
    if job['mode'] in ('trim', 'validate-trim'):
        return dict(ok=True, recommendations=[], issues=[], speech=speech_boundaries(job.get('speech')))
    from vf_agent.story_hints import coverage
    from vf_agent.story_cut import interval
    from vf_agent.story_qc import audit
    shots = job['shots']; kinds = job['kinds']; clips = []; cursor = 0.
    for s in shots:
        length = s['end']-s['start']
        clips.append(dict(id=s['id'], record_id=s['mediaId'], duration=length,
            source_range=None if kinds[s['mediaId']] == 'image' else [s['start'], s['end']],
            timeline_start=cursor, timeline_end=cursor+length, audio='silence'))
        cursor += length
    qc = audit(dict(beats=[dict(clips=clips)], narration=[]))
    result = dict(ok=True, recommendations=[], issues=[dict(shot=i['shot'], kind=i['kind']) for i in qc['issues']],
                  scope='cached_evidence_and_visual_rules_only')
    if job['mode'] == 'review':
        return result
    target = next(s for s in shots if s['id'] == job['shotId'])
    length = target['end']-target['start']

    def tokens(text):
        text = str(text).lower()
        words = set(re.findall(r'[a-z]{3,}', text)) - {'the', 'and', 'with', 'shot', 'video', 'this', 'scene', 'show'}
        for part in re.findall(r'[\u3400-\u9fff]+', text):
            words.update(part[i:i+2] for i in range(len(part)-1))
        return words

    current = next((r for r in job['sources'] if r['id'] == target['mediaId']), {})
    current_segments = [s for s in current.get('segments', []) if s.get('start', 0) < target['end'] and s.get('end', 0) > target['start']]
    roles = {r for s in current_segments for r in (s.get('editorial') or {}).get('story_role', [])}
    query = tokens(target.get('label', '')+' '+target.get('reason', '')+' '+ ' '.join((s.get('editorial') or {}).get('description', '') for s in current_segments))
    options = []
    for row in job['sources']:
        photo = row['kind'] == 'image'
        segments = [dict(start=0, end=60, editorial=dict(description=row.get('description', '')))] if photo else row.get('segments', [])
        for segment in segments:
            ed = segment.get('editorial') or {}
            if ed.get('unusable_candidate') or ed.get('duplicate_candidate'):
                continue
            a, b = segment.get('start'), segment.get('end')
            limit = 60 if photo else row['duration']
            if not all(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) for x in (a, b, limit)) or not 0 <= a < b <= limit or b-a < length:
                continue
            role_match = bool(roles.intersection(ed.get('story_role', [])))
            description = str(ed.get('description') or '')
            overlap = query & tokens(description)
            same = row['id'] == target['mediaId']
            if not overlap and not role_match and not same:
                continue
            # Use the engine's candidate-centered interval, but preserve the exact
            # duration and never extend past the cached evidence interval.
            span = interval(limit, length, {'range': [a, b]}) if not photo else [0, length]
            start = 0 if photo else max(a, min(b-length, sum(span)/2-length/2))
            end = start+length
            if same and (photo or max(start, target['start']) < min(end, target['end'])-.05):
                continue
            state, _ = coverage(row['id'], None if photo else [start, end], [c for c in clips if c['id'] != target['id']])
            if state in ('selected', 'partial'):
                continue
            score = len(overlap) + (3 if role_match else 0) + (1 if same else 0)
            options.append(dict(mediaId=row['id'], start=start, end=end, revision=row['revision'],
                reason='same_source' if same else 'shared_role' if role_match else 'related_description',
                description=description[:280], score=score))
    options.sort(key=lambda c: (-c['score'], c['mediaId'], c['start']))
    # Show a choice of sources before multiple moments from the same file.
    first, remaining, seen = [], [], set()
    for c in options:
        (remaining if c['mediaId'] in seen else first).append(c)
        seen.add(c['mediaId'])
    for c in first + remaining:
        if any(c['mediaId'] == old['mediaId'] and max(c['start'], old['start']) < min(c['end'], old['end']) for old in result['recommendations']):
            continue
        c.pop('score'); result['recommendations'].append(c)
        if len(result['recommendations']) == 3:
            break
    return result


def validate_beats(beats, count):
    if beats is None:
        return
    if not isinstance(beats, list) or not beats or any(not isinstance(b, dict) or type(b.get('first')) is not int for b in beats):
        raise ValueError('Story chapters require integer first-shot indices')
    bounds = [b['first'] for b in beats] + [count]
    if bounds[0] != 0 or any(a >= b for a, b in zip(bounds, bounds[1:])):
        raise ValueError('Story chapters must partition all shots, starting at zero')


def normalize_beats(beats, count):
    """Accept the common one-based convention, never sort or guess boundaries."""
    if (isinstance(beats, list) and beats and
            all(isinstance(b, dict) and type(b.get('first')) is int for b in beats) and
            beats[0]['first'] == 1):
        beats = [dict(b, first=b['first'] - 1) for b in beats]
    validate_beats(beats, count)
    return beats


def section_beats(shots):
    """Describe existing contiguous sections without changing any source cut."""
    return [dict(first=i, title=s.get('label', ''), intent=s.get('reason', ''), bridge='')
            for i, s in enumerate(shots)
            if i == 0 or s.get('section', 'body') != shots[i-1].get('section', 'body')]


def handle(job):
    if job.get('action') == 'editor':
        return editor_assist(job)
    from vf_agent.storage import fingerprint, atomic_json, atomic_text, digest
    from vf_agent.story_hints import handoff
    from vf_agent.story_qc import DIRECTOR_GUIDANCE
    action = job.get('action')
    if action == 'context':
        rows = []
        for source in job['sources']:
            path = Path(source['path']).resolve()
            if not path.is_file():
                raise ValueError('Story source is offline: ' + source['mediaId'])
            rows.append(dict(id=source['mediaId'], name=source['mediaId'], source=str(path),
                source_fingerprint=fingerprint(path), kind='photo' if source['kind'] == 'image' else 'video',
                duration=source.get('duration', 0), capture=source.get('capture', ''),
                description=dict(text=source.get('description', ''), status='machine_unreviewed')))
        docs = [dict(record_id=c['mediaId'], kind='source_asr', text=c['text'], start=c['start'],
                     end=c['end'], time_domain='source_audio', status='machine_unreviewed',
                     timing_status='unverified', searchable=True) for c in job.get('transcripts', [])]
        return dict(records=rows, documents=docs, hints=handoff(rows, docs, []), guidance=DIRECTOR_GUIDANCE)
    if action != 'compile':
        raise ValueError('Unsupported story action')
    from vf_agent.story_restore import compile_plan
    context = job['context']; rows = context['records']; by_id = {r['id']: r for r in rows}
    shots = job['shots']
    if not shots or len({s['id'] for s in shots}) != len(shots):
        raise ValueError('Story requires unique shot IDs')
    render_shots = []; cursor = 0.
    for shot in shots:
        row = by_id.get(shot['mediaId'])
        if row is None or fingerprint(row['source']) != row['source_fingerprint']:
            raise ValueError('Story source missing or changed: ' + shot['mediaId'])
        start, end = shot['start'], shot['end']; photo = row['kind'] == 'photo'
        if not all(isinstance(t, (int, float)) and not isinstance(t, bool) and math.isfinite(t) for t in (start, end)):
            raise ValueError('Invalid story source times')
        if not 0 <= start < end or (photo and start != 0) or (not photo and end > row['duration'] + .001):
            raise ValueError('Story interval outside source')
        render_shots.append(dict(stem=shot['id'], asset=row['id'], path=row['source'], photo=photo,
            start=cursor, dur=end-start, src_in=start, src_dur=row['duration'] if not photo else end,
            speed=1, vol=1 if job.get('sourceAudio', {}).get(row['id']) and not photo else 0,
            role=shot.get('reason', ''), transition='硬切'))
        cursor += end-start
    beats = job.get('beats')
    if not beats:
        # Existing/skill edits can have no chapter proposal. Preserve their exact
        # sections and cuts; never manufacture a mandatory opening montage.
        beats = section_beats(shots)
    validate_beats(beats, len(shots))
    beats = [dict(first=b['first'], title=str(b.get('title', '')), intent=str(b.get('intent', '')),
                  bridge=str(b.get('bridge', ''))) for b in beats]
    folder = Path(job['folder']); folder.mkdir(parents=True, exist_ok=True)
    render_path = folder/'render.json'; facts_path = folder/'request.txt'
    atomic_json(render_path, dict(shots=render_shots, narration=[], music=[], body_end=cursor, total=cursor))
    # The request is provenance, not confirmed facts; fact_terms deliberately stays empty.
    atomic_text(facts_path, job.get('request', ''))
    brief = dict(project=job['project'], origin='new_director_edit', title=job.get('summary', ''),
        logline=job.get('summary', ''), targets=[], script=dict(scope=job.get('request', '')),
        baseline='Pixfun Agent proposal', facts=str(facts_path), beats=beats,
        required=[dict(one_of=[mid], reason='User-required source') for mid in job.get('requiredMediaIds', [])])
    plan, compiled = compile_plan(folder, render_path, brief, rows)
    clips = [c for b in plan['beats'] for c in b['clips']]
    originals = {s['id']: s for s in shots}
    timeline = []
    for c in clips:
        shot = dict(originals[c['instance']])
        shot.update(start=c['source_range'][0] if c['source_range'] else 0,
                    end=c['source_range'][1] if c['source_range'] else c['duration'])
        timeline.append(shot)
    # Reasons belong to shot instances (the same source can appear twice).
    for c in clips:
        c['reason'] = originals[c['instance']].get('reason', '')
    plan['highlight_handoff'] = handoff(rows, context['documents'], clips)
    plan['finishing_scope'] = 'Visual story only; Pixfun resolves sound, titles and transitions separately.'
    plan['version'] = digest(plan)[:20]
    atomic_json(folder/'story.json', plan)
    atomic_json(folder/'compiled-render.json', compiled)
    return dict(timeline=timeline, version=plan['version'], path=str(folder/'story.json'),
                summary=plan['logline'],
                outline=[dict(id=b['id'], title=b['title'], intent=b['intent'], bridge=b['bridge'],
                              shotIds=[c['instance'] for c in b['clips']]) for b in plan['beats']],
                sourceNames={r['id']: Path(r['source']).name for r in rows},
                sourceKinds={r['id']: r['kind'] for r in rows},
                chapters=len(plan['beats']), qc=plan['editorial_qc'], coverage=plan['coverage'])
