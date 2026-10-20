"""Human-confirmed trip facts for the Agent conversation.

Generated place names and file GPS remain evidence.  This module only creates
and applies an explicit local overlay after the user confirms it; source media
is never rewritten.
"""
import json
import math
import re
import time


CONFIRM = re.compile(r'^\s*(?:确认|没问题|行程正确|位置正确|继续编排|按以上行程继续|confirm(?:ed)?|looks?\s+good|continue)\s*[.!。！]?\s*$', re.I)
IGNORE = re.compile(r'(?:忽略|不使用|不采用|不参考).{0,8}(?:位置|GPS|定位)|(?:without|ignore)\s+(?:the\s+)?(?:location|gps)', re.I)


def _finite(value, low, high):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and low <= value <= high


def _original_location(record):
    value = (record.get('metadata') or {}).get('location') or {}
    lat, lon = value.get('latitude'), value.get('longitude')
    if not (_finite(lat, -90, 90) and _finite(lon, -180, 180)):
        return None
    return {'latitude': float(lat), 'longitude': float(lon),
            'accuracy': value.get('horizontalAccuracy'), 'source': value.get('source', 'file-metadata')}


def _effective_location(record):
    original = _original_location(record)
    review = record.get('locationReview') or {}
    if review.get('source') == 'user-confirmed' and _finite(review.get('latitude'), -90, 90) and _finite(review.get('longitude'), -180, 180):
        return {'latitude': float(review['latitude']), 'longitude': float(review['longitude']),
                'source': 'user-confirmed'}
    return original


def _place(record):
    review = record.get('locationReview') or {}
    if review.get('source') == 'user-confirmed' and isinstance(review.get('place'), str) and review['place'].strip():
        return review['place'].strip()
    explicit = (record.get('context') or {}).get('location')
    if isinstance(explicit, str) and explicit.strip():
        return explicit.strip()
    resolved = record.get('resolvedPlace') or {}
    for key in ('displayName', 'area', 'label'):
        if isinstance(resolved.get(key), str) and resolved[key].strip():
            return resolved[key].strip()
    location = (record.get('metadata') or {}).get('location') or {}
    return location.get('name', '').strip() if isinstance(location.get('name'), str) else ''


def proposal(records, previous=None):
    """Build a stable numbered review list from selected records."""
    rows = sorted(records.values(), key=lambda r: ((r.get('metadata') or {}).get('capturedAt') or '9999', r['id']))
    entries = []
    old = {e.get('mediaId'): e for e in (previous or {}).get('entries', []) if isinstance(e, dict)}
    for number, record in enumerate(rows, 1):
        original = _original_location(record)
        effective = _effective_location(record)
        prior = old.get(record['id'], {})
        entries.append({'number': number, 'mediaId': record['id'], 'name': record['file']['name'],
                        'capturedAt': (record.get('metadata') or {}).get('capturedAt') or '',
                        'place': prior.get('place') or _place(record),
                        'originalLocation': original, 'location': prior.get('location') or effective,
                        'correction': prior.get('correction')})
    return {'version': 1, 'status': 'pending', 'useLocations': (previous or {}).get('useLocations', True),
            'entries': entries, 'updatedAt': time.time() * 1000}


def detailed_text(value):
    lines = []
    for entry in value.get('entries', []):
        captured = entry.get('capturedAt', '')
        stamp = captured[:16].replace('T', ' ') if captured else '时间未记录'
        place = entry.get('place') or '地点待确认'
        corrected = ' · 已纠偏' if entry.get('correction') else ''
        lines.append(f"{entry['number']}. {entry['name']} · {stamp} · {place}{corrected}")
    return '\n'.join(lines)


def question(value):
    return '高光分析已完成，请确认行程后继续故事编排。'


def correction_prompt(value, response):
    items = [{k: e.get(k) for k in ('number', 'mediaId', 'name', 'capturedAt', 'place')} for e in value.get('entries', [])]
    return '''Interpret ONLY the user's explicit trip correction. Return JSON only:
{"confirm":false,"ignoreLocations":false,"corrections":[{"numbers":[4,5],"place":"user-stated place or empty","anchorNumber":3}]}
Numbers and anchorNumber must refer to the supplied numbered items. An anchor means the user explicitly said those items are at/near that numbered item's position. Never infer an anchor or place from imagery, filenames, GPS, or general knowledge. If the user only confirms, set confirm=true and corrections=[]; if they explicitly reject using location, set ignoreLocations=true. Do not copy the example unless requested. INPUT: ''' + json.dumps({'items': items, 'response': response}, ensure_ascii=False)


def manual_correction(value, numbers, anchor_number, place=''):
    """Apply an explicit picker selection to the pending proposal, not the library."""
    if not isinstance(numbers, list) or not numbers or any(isinstance(n, bool) or not isinstance(n, int) for n in numbers):
        raise ValueError('请选择需要修正的素材。')
    if isinstance(anchor_number, bool) or not isinstance(anchor_number, int):
        raise ValueError('请选择一个位置参考素材。')
    if not isinstance(place, str) or len(place.strip()) > 200:
        raise ValueError('地点名称格式无效。')
    entries = [dict(e) for e in value.get('entries', [])]
    by_number = {e['number']: e for e in entries}
    if anchor_number not in by_number or any(n not in by_number for n in numbers):
        raise ValueError('行程已变化，请重新选择。')
    anchor = by_number[anchor_number]
    if not anchor.get('location'):
        raise ValueError('参考素材没有可用坐标。')
    label = place.strip() or anchor.get('place', '')
    for number in numbers:
        entry = by_number[number]
        entry['location'] = dict(anchor['location'])
        if label: entry['place'] = label
        entry['correction'] = {'kind': 'anchor', 'anchorNumber': anchor_number,
                               'anchorMediaId': anchor['mediaId'], 'response': 'picker'}
    result = dict(value)
    result.update(status='pending', entries=entries, updatedAt=time.time() * 1000)
    return result


def revise(value, response, ask, cancel, mode='local'):
    text = response.strip()
    if CONFIRM.fullmatch(text):
        result = dict(value); result.update(status='confirmed', updatedAt=time.time() * 1000)
        return result, True
    if IGNORE.search(text):
        result = dict(value); result.update(status='confirmed', useLocations=False, updatedAt=time.time() * 1000)
        return result, True
    answer = ask(correction_prompt(value, text), cancel, mode, max_tokens=1000)
    if answer.get('confirm') is True and not answer.get('corrections'):
        result = dict(value); result.update(status='confirmed', updatedAt=time.time() * 1000)
        return result, True
    if answer.get('ignoreLocations') is True:
        result = dict(value); result.update(status='confirmed', useLocations=False, updatedAt=time.time() * 1000)
        return result, True
    entries = [dict(e) for e in value.get('entries', [])]
    by_number = {e['number']: e for e in entries}
    corrections = answer.get('corrections')
    if not isinstance(corrections, list) or not corrections:
        raise ValueError('请说明需要修正的素材编号、实际地点，以及可参考的正确位置编号。')
    touched = set()
    for correction in corrections:
        if not isinstance(correction, dict): raise ValueError('行程修正格式无效。')
        numbers, anchor_number = correction.get('numbers'), correction.get('anchorNumber')
        place = correction.get('place', '')
        if (not isinstance(numbers, list) or not numbers or any(isinstance(n, bool) or not isinstance(n, int) or n not in by_number for n in numbers)
                or (anchor_number is not None and (isinstance(anchor_number, bool) or not isinstance(anchor_number, int) or anchor_number not in by_number))
                or not isinstance(place, str) or len(place.strip()) > 200):
            raise ValueError('行程修正引用了无效素材编号。')
        anchor = by_number.get(anchor_number)
        anchor_location = anchor.get('location') if anchor else None
        if anchor_number is not None and not anchor_location:
            raise ValueError('参考素材没有可用坐标，请换一个参考位置。')
        if not place.strip() and anchor is None:
            raise ValueError('请填写实际地点或指定参考位置。')
        for number in numbers:
            entry = by_number[number]
            if place.strip(): entry['place'] = place.strip()
            if anchor:
                entry['location'] = dict(anchor_location)
            entry['correction'] = {'kind': 'anchor' if anchor else 'place', 'anchorNumber': anchor_number,
                                   'anchorMediaId': anchor.get('mediaId') if anchor else None,
                                   'response': text[:500]}
            touched.add(number)
    if not touched: raise ValueError('未找到可应用的行程修正。')
    result = dict(value); result.update(status='pending', entries=entries, updatedAt=time.time() * 1000)
    return result, False


def apply(library, value):
    """Persist confirmed overlays; retain original coordinates alongside them."""
    if value.get('status') != 'confirmed': raise ValueError('行程尚未确认。')
    if not value.get('useLocations', True): return 0
    changed = 0
    for entry in value.get('entries', []):
        correction = entry.get('correction')
        if not correction: continue
        record, _ = library.get(entry['mediaId'])
        original = _original_location(record)
        location = entry.get('location')
        review = {'version': 1, 'source': 'user-confirmed', 'place': entry.get('place', ''),
                  'latitude': location.get('latitude') if location else None,
                  'longitude': location.get('longitude') if location else None,
                  'originalLatitude': original.get('latitude') if original else None,
                  'originalLongitude': original.get('longitude') if original else None,
                  'anchorMediaId': correction.get('anchorMediaId'), 'confirmedAt': time.time() * 1000}
        context = dict(record.get('context') or {})
        if review['place']: context['location'] = review['place']
        library.patch(entry['mediaId'], locationReview=review, context=context)
        changed += 1
    return changed


def planning_context(value):
    if not value or not value.get('useLocations', True): return {'status': 'confirmed', 'useLocations': False, 'items': []}
    return {'status': value.get('status'), 'useLocations': True,
            'items': [{'mediaId': e['mediaId'], 'capturedAt': e.get('capturedAt', ''), 'place': e.get('place', ''),
                       'locationStatus': 'user-confirmed' if e.get('correction') else 'file-metadata-unverified'}
                      for e in value.get('entries', [])]}
