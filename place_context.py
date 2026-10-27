"""Coordinate-bound address/boundary results, separate from originals and corrections."""
import math
import re


def compact_place(place):
    area = place.get('area')
    if not area:
        return place['label']
    chinese = place.get('language') == 'zh-Hans'
    city = place.get('city')
    if not city:
        city = next((p for p in place['label'].split(' · ') if p.endswith('市') and '区' not in p), None)
    parent = (place.get('region') if place.get('placeKind') == 'lake' else city) or place.get('region') or ''
    if chinese and parent.endswith(('市', '省')):
        parent = parent[:-1]
    name = place.get('shortName') or area
    if place.get('areaRelation') == 'nearby':
        name += '附近' if chinese else ' vicinity'
    return ' '.join(p for p in (parent, name) if p)


def validate_place(item, value):
    if not isinstance(value, dict) or (value.get('version'), value.get('provider')) not in (
            (2, 'apple-geocoder'), (3, 'apple-osm')):
        raise ValueError('Unsupported place result')
    original = (item.get('metadata') or {}).get('location') or {}
    for key, limit in (('latitude', 90), ('longitude', 180)):
        number = value.get(key)
        if (isinstance(number, bool) or not isinstance(number, (int, float)) or not math.isfinite(number)
                or abs(number) > limit or original.get(key) != number):
            raise ValueError('Place coordinates do not match this media')
    if value.get('language') not in ('zh-Hans', 'en'):
        raise ValueError('Unsupported place language')
    stamp = value.get('resolvedAt')
    if isinstance(stamp, bool) or not isinstance(stamp, (int, float)) or not math.isfinite(stamp) or stamp <= 0:
        raise ValueError('Invalid place timestamp')
    result = {key: value[key] for key in ('version', 'provider', 'latitude', 'longitude', 'language', 'resolvedAt')}
    for key in ('label', 'area', 'nearbyName'):
        text = value.get(key)
        if text is not None and (not isinstance(text, str) or len(text) > 500):
            raise ValueError('Invalid place text')
        result[key] = text.strip() if text else None
    if not result['label'] or result['area'] and result['area'] not in result['label']:
        raise ValueError('Place label must contain the supplied area')
    for key in ('city', 'region', 'shortName', 'shortNameSource'):
        text = value.get(key)
        if text is not None:
            if not isinstance(text, str) or not text.strip() or len(text) > 200:
                raise ValueError('Invalid place naming component')
            result[key] = text.strip()
    if result.get('shortName') and result.get('shortNameSource') not in ('map-short-name', 'user-alias'):
        raise ValueError('Place short name requires provenance')
    if value['version'] == 2 and value.get('displayName') is not None:
        if not result['area'] or value['displayName'] != compact_place(result):
            raise ValueError('Invalid concise address label')
        result['displayName'] = value['displayName']
    if value['version'] == 3:
        for key in ('displayName', 'boundaryID', 'areaRelation', 'placeKind'):
            text = value.get(key)
            if not isinstance(text, str) or not text.strip() or len(text) > 500:
                raise ValueError('Invalid boundary evidence')
            result[key] = text.strip()
        relation = result['areaRelation']
        if relation not in ('inside', 'nearby') or result['placeKind'] not in ('campus', 'lake', 'scenic', 'park', 'attraction'):
            raise ValueError('Unsupported boundary relation')
        pattern = r'(area|way)/[1-9][0-9]*' if relation == 'inside' else r'(way|relation)/[1-9][0-9]*'
        name = result.get('shortName') or result['area']
        if not re.fullmatch(pattern, result['boundaryID']) or not name or name not in result['displayName']:
            raise ValueError('Boundary identity or display name mismatch')
        if relation == 'nearby':
            suffix = '附近' if result['language'] == 'zh-Hans' else ' vicinity'
            if result['placeKind'] != 'lake' or not result['displayName'].endswith(name + suffix):
                raise ValueError('Nearby water must remain explicitly qualified')
    return result


def description_context(item):
    context = {k: v for k, v in (item.get('context') or {}).items()
               if k in ('location', 'device', 'shotOn', 'captureTime') and isinstance(v, str)
               and v.strip() and v.lower() not in ('unknown', 'unspecified', 'none', 'n/a', '未知', '无')}
    if context.get('location'):
        return context  # Explicit user context always wins.
    original = (item.get('metadata') or {}).get('location') or {}
    if isinstance(original.get('name'), str) and original['name'].strip():
        context['location'] = original['name'].strip()
        return context
    try:
        place = validate_place(item, item.get('resolvedPlace'))
    except ValueError:
        return context
    # Do not promote a nearby faculty/hospital into the filmed subject.
    context['location'] = place.get('displayName') or compact_place(place)
    return context
