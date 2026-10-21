"""Read-only catalog evidence for planning; never manufacture editorial analysis.

Exact ranges use the playback clock. Explicit Analyze still runs Pixfun's full
analysis. A changed source, missing fingerprint or empty scan cannot be reused.
"""
import copy
import math
from pathlib import Path

from vf_native import validate_source


def catalog_evidence(record, source):
    reference = record.get('vfCatalog') or {}
    if not reference.get('fingerprint') or record.get('status') != 'ready':
        return None
    validate_source(record, Path(source))
    analysis = (record.get('result') or {}).get('analysis') or {}
    duration = (record.get('metadata') or {}).get('duration')
    if not isinstance(duration, (float, int)) or not math.isfinite(duration): return None
    saved = {s['id']: s for s in reference.get('shots', [])}
    segments = []
    for segment in analysis.get('segments', []):
        evidence = saved.get(segment.get('id'))
        if evidence is None: continue
        start, end = segment.get('start'), segment.get('end')
        if not all(type(v) in (int, float) and math.isfinite(v) for v in (start, end)) or not 0 <= start < end <= duration:
            raise ValueError('Invalid saved catalog interval. Refresh the catalog.')
        context = evidence.get('context') or {}
        # Context is explicitly labeled; it is not a newly observed visual claim.
        summary = 'Saved catalog shot'
        if context.get('place'):
            summary += ' · ' + ('confirmed filming area: ' if context.get('place_confirmed') else 'unverified place context: ') + context['place']
        if context.get('note'): summary += ' · catalog note: ' + context['note']
        segments.append(dict(id=segment['id'], mediaId=record['id'], start=start, end=end,
                             summary=summary, thumbnailUrl=segment.get('thumbnailUrl'),
                             boundary=copy.deepcopy(segment.get('boundary')), evidenceSource='visionflow-catalog',
                             catalogScores=copy.deepcopy(evidence.get('scores') or {})))
    if not segments: return None
    return dict(segments=segments, evidenceSource='visionflow-catalog',
                evidenceLimits='Saved shot boundaries, context and scan scores only; no new visual/editorial analysis. Place context does not prove a visible landmark. Scores may predate display repair.',
                speechEvidence=dict(cues=copy.deepcopy(analysis.get('subtitleCues') or []),
                    source='visionflow-catalog-filtered', excluded=reference.get('excludedTranscripts', 0)))
