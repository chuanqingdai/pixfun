"""Bounded tool selection; model proposals never authorize arbitrary operations."""
import math

TOOLS = {'transcribe', 'rank'}
TOOL_RULE = '''\nChoose optional local tools in a tools array (allowed names: transcribe, rank).
Use transcribe when the request needs spoken content. Use rank only for search/plan/create/modify, for a specific visual subject,
theme or mood to find/prioritize, including story planning. For rank provide a concise English query.
Do not request rank for a generic summary or rough cut with no visual selection criterion.
Tool availability is supplied in localCapabilities. Tool choices cannot change the requested outcome,
access unattached files, authorize cloud uploads, or render without approval.\n'''


def tool_plan(intent, brief):
    proposed = brief.get('tools', [])
    if not isinstance(proposed, list) or len(proposed) > 8:
        raise ValueError('Invalid local tool plan. Please retry the request.')
    if any(not isinstance(tool, str) or tool not in TOOLS for tool in proposed):
        raise ValueError('The model requested an unsupported tool. No such tool was run.')
    selected = list(dict.fromkeys(proposed))
    if intent == 'search' and 'rank' not in selected:
        selected.append('rank')
    if (brief.get('needsSpeech') or intent in ('subtitles', 'plan', 'create', 'modify')) and 'transcribe' not in selected:
        selected.append('transcribe')
    if intent not in ('search', 'plan', 'create', 'modify'):
        selected = [tool for tool in selected if tool != 'rank']
    query = brief.get('query') or ''
    if not isinstance(query, str) or len(query) > 500:
        raise ValueError('Use a short visual search request.')
    if intent != 'search' and not query.strip():
        selected = [tool for tool in selected if tool != 'rank']
    return {'tools': selected, 'query': query.strip(), 'scope': 'attached-media-only'}


def ranked_evidence(evidence, result):
    scores = result.get('scores') if isinstance(result, dict) else None
    if not isinstance(scores, list) or len(scores) != len(evidence):
        raise ValueError('Local retrieval returned an incomplete ranking. Retry the request.')
    if any(isinstance(score, bool) or not isinstance(score, (int, float)) or not math.isfinite(score) for score in scores):
        raise ValueError('Local retrieval returned invalid scores. Retry the request.')
    # Annotate, never silently drop or reorder source references.
    return [dict(row, similarity=round(float(score), 4)) for row, score in zip(evidence, scores)]
