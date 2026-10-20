"""Bundled motion skills: parameter-only adapters, never downloaded instructions."""
import hashlib
from pathlib import Path
import re

from agent_hyperframes import items, validate_title

ROOT = Path(__file__).resolve().parent/'creator-skills'
CATALOG = {
    'motion-titles': ('Motion Titles', 'Travel photos or videos that need one opening title, place label or closing line.', ('title', 'place', 'end')),
    'journey-route': ('Journey Route', 'Travel photos or videos that need a visual connection between two confirmed places.', ('route',)),
    'highlight-counter': ('Highlight Counter', 'Travel photos or videos that need one confirmed number and a short label.', ('counter',)),
}

ROUTING_RULE = '''Selected motion skills add one graphic, not a new editorial strategy.
Do not turn analyze/search/answer requests into creation. Preserve an existing edit's shots and sound.
New films use content-led duration and 16:9 unless the user specifies otherwise; no automatic music or transitions.
For Journey Route, ask for departure and arrival names if missing. For Highlight Counter ask for an exact integer and label.
'''
PLANNING_RULE = '''Use installedSkill.editorialRules. Also return a separate motionGraphic object:
Motion Titles: {"kind":"title|place|end","text":"short on-screen text"}.
Journey Route: {"kind":"route","origin":"user-provided place","destination":"user-provided place","text":""}.
Highlight Counter: {"kind":"counter","text":"user-provided label","total":3}.
Use only installedSkill.allowedKinds. Title text must occur in the user request or a proposed shot label;
route labels, counter label and exact count must occur in the user request, never inferred from footage.
If missing, return motionGraphic:null; never fabricate parameters. No paths, URLs, HTML, scripts or commands.
For an existing timeline preserve every shot unchanged; this skill only changes its graphic layer.
No automatic music, voiceover or transitions. One graphic per film, at least 2.5s of readable time.
'''


def resolve_motion_skill(chosen):
    key = (chosen or {}).get('id')
    if key not in CATALOG:
        return None
    title, scope, kinds = CATALOG[key]
    source = (ROOT/key/'SKILL.md').read_text(encoding='utf-8')
    # Integrity values are bundled code, not a client-provided or editable sidecar manifest.
    expected = DIGESTS.get(key)
    digest = hashlib.sha256(source.encode()).hexdigest()
    if digest != expected:
        raise ValueError('Motion skill changed since review. Restore the bundled specification before use.')
    return dict(id=key, title=title, applicability=scope, version='1.1', adapterVersion='1',
                sourceSHA256=digest, editorialRules=source.split('---', 2)[2].strip(),
                defaults=dict(aspect='16:9', duration=None, coverage='selected', music='on_request', transition='none'),
                allowedKinds=list(kinds), executionScope='bundled_motion_graphic',
                pending=['Multi-title chapter layouts', 'Geographic maps and tracking'])


def disabled(prompt):
    return bool(re.search(r'(?:no|without|remove|don.t (?:add|use)).*?(?:text|titles?|graphics?|effects?|hyperframes)|(?:不要|不加|去掉|删除).*?(?:标题|片名|文字|字幕|动效|特效|路线|数字)', prompt, re.I))


def present(value, prompt):
    value = value.casefold()
    return bool(re.search(r'(?<!\w)'+re.escape(value)+r'(?!\w)', prompt.casefold())) if value.isascii() else value in prompt


def apply_plan(skill, prompt, proposal, shots, finishing, capabilities, scope=None):
    """Validate factual parameters and preserve unrelated layers before rendering."""
    if not skill or skill.get('id') not in CATALOG:
        return finishing
    result = dict(finishing)
    if disabled(prompt):
        result['motionTitle'] = {'kind':'none', 'text':''}
        return result
    if not capabilities.get('localHyperframes'):
        raise ValueError('This skill needs the local motion renderer. No cloud fallback will be used.')
    if not isinstance(proposal, dict):
        raise ValueError('Provide the graphic text; routes need two place names and counters need an exact number and label.')
    if set(proposal) - {'kind','text','origin','destination','total'}:
        raise ValueError('Motion skills accept text and numbers only, not code, URLs or file paths.')
    if proposal.get('kind') not in CATALOG[skill['id']][2]:
        raise ValueError('Choose a graphic supported by the selected skill.')
    chosen = validate_title(proposal)
    if any(re.search(r'://|<|>|[\\/]', str(v)) for k,v in chosen.items() if k != 'kind' and isinstance(v,str)):
        raise ValueError('Use plain graphic labels, not markup, URLs or file paths.')
    if chosen['kind'] == 'route':
        if not all(present(chosen[k], prompt) for k in ('origin','destination')):
            raise ValueError('Provide both route names in your request; locations are never guessed.')
    elif chosen['kind'] == 'counter':
        if not present(chosen['text'], prompt) or not re.search(r'(?<![\d.])'+str(chosen['total'])+r'(?![\d.])', prompt):
            raise ValueError('Provide the exact number and its label in your request; counts are never inferred.')
    elif not present(chosen['text'], prompt) and chosen['text'] not in [s.get('label') for s in shots]:
        raise ValueError('Supply the title wording or use an existing shot label.')
    placements = items(shots, '', chosen)
    if not placements:
        raise ValueError('This graphic needs a shot lasting at least 2.5 seconds; your timeline was not extended.')
    if scope and (chosen['kind'] == 'end' or any(p['shotId'] not in scope.get('shotIds',[]) for p in placements)):
        raise ValueError('The graphic falls outside the selected clips. Select the opening clip or edit the whole film.')
    result['motionTitle'] = chosen
    return result


# Updated only alongside reviewed specifications and their tests.
DIGESTS = {
    'motion-titles': '76fae0b868fab2139e8ac4a3e8ee27a9af4701c92b2df0a1740a0575731783a2',
    'journey-route': 'e9d6053c495c2f5fcaaf599488a9d5bc7eb247cabadf0ebe0ad3063714bd58d9',
    'highlight-counter': '4bce9f5c511ac070a8ffc7b1552303cc0270caa0c2c2329491c7362db124a6e1',
}
