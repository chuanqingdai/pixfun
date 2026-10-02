"""Small, bundled CC BY catalog. No network requests or arbitrary model-supplied paths."""
import json
import os
from pathlib import Path


def catalog():
    root = Path(os.environ.get('PIXFUN_MUSIC_DIR', str(Path(__file__).resolve().parent / 'native/Music')))
    manifest = root / 'catalog.json'
    if not manifest.is_file(): return {}
    result = {}
    for track in json.loads(manifest.read_text())['tracks']:
        path = root / track['file']
        if path.parent.resolve() != root.resolve() or not path.is_file(): continue
        result[track['id']] = ({'id': track['id'], 'kind': 'audio', 'file': {'name': track['title']},
                              'metadata': {'duration': track['duration'], 'hasAudio': True},
                              'musicCredit': track, 'mood': track['mood']}, path)
    return result


def credit(record):
    track = record.get('musicCredit')
    if not track: return ''
    return (f'{track["title"]} — {track["author"]} (incompetech.com)\n'
            f'{track["source"]}\nLicensed under {track["license"]}: {track["licenseURL"]}\n'
            'Changes: excerpted/looped, volume adjusted and mixed with video audio.\n'
            'Include this credit in your published video description or end credits.')
