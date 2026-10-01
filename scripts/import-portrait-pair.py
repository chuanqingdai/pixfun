"""Import the two requested portrait clips through the desktop Library service.

Uses the same registration and analysis methods as the native picker. No raw
database writes, reimports of existing media, or modifications to originals.
"""
import json
import os
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[1]
STORE = Path('/Users/daichuanqing/Library/Application Support/Pixfun/Library')
database = STORE / 'library.sqlite3'
with sqlite3.connect(f'file:{database}?mode=ro', uri=True) as db:
    records = [json.loads(row[0]) for row in db.execute('SELECT record FROM media WHERE removed=0')]
if any(record.get('status') not in ('ready', 'error', 'cancelled') for record in records):
    raise SystemExit('Wait for existing imports to finish before running this import.')

os.environ['PIXFUN_DATA_DIR'] = str(STORE)
sys.path.insert(0, str(ROOT))
from desktop_service import Library

library = Library(STORE)
names = ['Forest - Family Trail Walk.mp4', 'Coast - Waves over Rocks.mp4']
paths = [str(ROOT / 'data/portrait-media-20260927/import' / name) for name in names]
result = library.register(paths)
print(json.dumps({'added': len(result['items']), 'errors': result['errors']}), flush=True)
library.pool.shutdown(wait=True)
for item in result['items']:
    record, _ = library.get(item['id'])
    print(json.dumps({'name': record['file']['name'], 'status': record['status'], 'metadata': record['metadata'], 'error': record['error']}), flush=True)
