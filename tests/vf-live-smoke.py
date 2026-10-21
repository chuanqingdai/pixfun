"""Read-only live catalog checks. --semantic uses the existing cached text model."""
import argparse
import hashlib
import json
from pathlib import Path
import time
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import ProxyHandler, Request, build_opener

parser = argparse.ArgumentParser()
parser.add_argument('--base', default='http://127.0.0.1:8765')
parser.add_argument('--output', required=True)
parser.add_argument('--semantic', action='store_true')
args = parser.parse_args()
opener = build_opener(ProxyHandler({}))


def request(route, params=None, headers=None):
    url = args.base + route + ('?' + urlencode(params) if params else '')
    try:
        with opener.open(Request(url, headers=headers or {}), timeout=180) as r:
            return r.status, dict(r.headers), r.read()
    except HTTPError as e:
        return e.code, dict(e.headers), e.read()


def api(route, params=None):
    code, _, raw = request('/api/vf/' + route, params)
    assert code == 200, (route, code, raw[:300])
    result = json.loads(raw); assert result['ok']; return result


report = {'counts': api('status')['counts']}
rows, offset = [], 0
while True:
    batch = api('search', {'mode': 'text', 'k': 100, 'offset': offset})['shots']
    rows.extend(batch)
    if len(batch) < 100: break
    offset += 100
assert len({r['id'] for r in rows}) == len(rows) == report['counts']['shots']
report['pagination_unique_shots'] = len(rows)
report['catalogs'] = sorted({r['asset'].split('/')[0] for r in rows})
report['hdr_display_shots'] = sum(any(f.get('display_profile') for f in r['frames']) for r in rows)
report['flagged_transcripts'] = sum(not s['searchable'] for r in rows for s in r['transcript_segments'])
text = api('search', {'q': '霍比屯', 'mode': 'text', 'k': 10})['shots']
assert text and all('霍比屯' in r['context'].get('place', '') for r in text)
report['text_search_hobbiton'] = len(text)
tags = api('search', {'tag': '新西兰之行', 'mode': 'text', 'k': 100})['shots']
assert tags and all(any(t['tag'] == '新西兰之行' for t in r['tags']) for r in tags)
report['tag_search_new_zealand_first_page'] = len(tags)
reference = text[0]
related = api('search', {'similar': reference['id'], 'k': 6})['shots']
assert len(related) == 6 and all(r['id'] != reference['id'] for r in related)
assert all(r['start'] <= r['match']['match_t'] < r['end'] for r in related)
report['similar_count'] = len(related)
for row in text:
    code, headers, raw = request('/api/vf/frame/' + quote(row['representative'], safe=''))
    assert code == 200 and headers['Content-Type'].startswith('image/') and raw[:3] == b'\xff\xd8\xff'
report['representative_images_loaded'] = len(text)
code, headers, raw = request('/api/vf/video/' + reference['id'], headers={'Range': 'bytes=0-1023'})
assert code == 206 and len(raw) == 1024 and headers['Content-Range'].startswith('bytes 0-1023/')
assert request('/api/vf/video/' + reference['id'], headers={'Range': 'bytes=999999999999-'})[0] == 416
report['video_ranges'] = '206 valid / 416 invalid'
assert request('/api/vf/status', headers={'Origin': 'https://other.example'})[0] == 403
assert request('/api/vf/status', headers={'Host': 'other.example:8765'})[0] == 403
assert request('/api/vf/status', headers={'Sec-Fetch-Site': 'cross-site'})[0] == 403
assert request('/api/vf/frame/not-found')[0] == 404
assert request('/api/vf/search', {'k': 1001})[0] == 400
assert request('/api/vf/search', {'url': 'https://other.example'})[0] == 400
report['access_checks'] = 'passed'
if args.semantic:
    start = time.monotonic()
    semantic = api('search', {'q': '湖边的风景', 'mode': 'hybrid', 'k': 6})['shots']
    assert semantic and all(r.get('match') for r in semantic)
    report['semantic'] = {'query': '湖边的风景', 'returned': len(semantic),
                          'seconds': round(time.monotonic() - start, 2)}
output = Path(args.output); output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
