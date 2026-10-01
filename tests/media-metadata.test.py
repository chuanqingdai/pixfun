import json
import sys
import types
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.modules.setdefault('cgi', types.ModuleType('cgi'))
from app import probe_media

data = {'streams': [{'codec_type': 'video', 'width': 1920, 'height': 1080,
                    'tags': {'creation_time': '2025-01-01T00:00:00Z'}}],
        'format': {'size': '123', 'tags': {
            'com.apple.quicktime.creationdate': '2024-12-20T10:11:12-08:00',
            'com.apple.quicktime.model': 'iPhone 15'}}}
with patch('app.command_exists', return_value=True), patch('app.run_command', return_value=(0, json.dumps(data), '')):
    meta = probe_media(Path('not-needed.mp4'))
    assert meta['capturedAt'] == '2024-12-20T10:11:12-08:00'
    assert meta['mediaCreatedAt'] == '2025-01-01T00:00:00Z'
    assert meta['camera'] == 'iPhone 15'
    assert meta['dateSource'] == 'QuickTime creationdate'
data['format']['tags'] = {}
data['streams'][0]['tags'] = {}
with patch('app.command_exists', return_value=True), patch('app.run_command', return_value=(0, json.dumps(data), '')):
    meta = probe_media(Path('not-needed.mp4'))
    assert meta['capturedAt'] is None and meta['mediaCreatedAt'] is None
print('PASS: Video capture metadata is separate from container creation time; missing dates stay unknown.')
