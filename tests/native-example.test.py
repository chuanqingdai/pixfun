import json
import re
from pathlib import Path
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from desktop_service import Library


class ExampleTests(unittest.TestCase):
    def test_bundle_assets(self):
        root = ROOT / 'native/Examples/wild-alaska'
        sample = json.loads((root/'manifest.json').read_text())
        record = sample['record']
        self.assertFalse(re.search(r'[\u3400-\u9fff]', json.dumps(record, ensure_ascii=False)))
        self.assertTrue(record['isExample'])
        self.assertIn('Lakes and forest', record['videoDescription']['full_description'])
        self.assertIn('Text("Sample")', (ROOT/'native/Sources/Pixfun/MediaView.swift').read_text())
        self.assertGreater(record['metadata']['duration'], 180)
        self.assertEqual((record['metadata']['width'], record['metadata']['height']), (1920, 1080))
        self.assertGreater((root/sample['filename']).stat().st_size, 1000000)
        analysis = record['result']['analysis']
        self.assertGreater(len(analysis['segments']), 10)
        self.assertGreater(len(analysis['subtitleCues']), 10)
        last = 0
        for shot in analysis['segments']:
            self.assertAlmostEqual(shot['start'], last)
            self.assertGreater(shot['end'], shot['start'])
            self.assertTrue((root/shot['thumbnailUrl'].rsplit('/', 1)[1]).is_file())
            last = shot['end']
        self.assertAlmostEqual(last, record['metadata']['duration'])
        for cue in analysis['subtitleCues']:
            self.assertGreaterEqual(cue['start'], 0)
            self.assertLessEqual(cue['end'], last)
            self.assertLess(cue['start'], cue['end'])
        self.assertTrue((root/'cover.jpg').is_file())
        self.assertIn('not a new transcription', analysis['subtitleMessage'])

    def test_idempotency_removal_relocation_preserve_edits(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp).resolve()
            first, moved = base/'bundle1', base/'bundle2'
            sample = {'filename': 'sample.mp4', 'record': {
                'id': 'example-test-v1', 'isExample': True, 'kind': 'video', 'status': 'ready',
                'file': {'name': 'sample.mp4'}, 'videoDescription': {'status': 'ready', 'title': 'Wild Alaska', 'full_description': 'Prepared English sample.', 'model': 'Prepared editorial example'},
                'result': {'analysis': {'subtitleCues': [{'text': 'Sample'}]}}}}
            for folder in [first, moved]:
                folder.mkdir()
                (folder/'sample.mp4').write_bytes(b'fixture-video')
                (folder/'manifest.json').write_text(json.dumps(sample))
            library = Library(base/'library')
            try:
                library.install_example(first); library.install_example(first)
                self.assertEqual(len(library.list()), 1)
                self.assertEqual(library.cancel, {})
                library.patch('example-test-v1', favorite=True, videoDescription={'full_description': 'User analysis'})
                library.install_example(moved)
                record, source = library.get('example-test-v1')
                self.assertEqual(source, moved/'sample.mp4')
                self.assertTrue(record['favorite'])
                self.assertEqual(record['videoDescription']['full_description'], 'User analysis')
                self.assertEqual(record['sampleCopy']['title'], 'Wild Alaska')
                library.patch('example-test-v1', videoDescription={'status': 'running', 'title': '湖岸至山地自然生态巡礼', 'full_description': '旧中文分析'}, shotAnalysis={'status': 'queued'})
                library.install_example(moved)
                record, _ = library.get('example-test-v1')
                self.assertEqual(record['sampleCopy']['full_description'], 'Prepared English sample.')
                self.assertEqual(record['videoDescription']['status'], 'running')
                self.assertEqual(record['videoDescription']['full_description'], '旧中文分析')
                self.assertEqual(record['shotAnalysis']['status'], 'queued')
                self.assertTrue(record['favorite'])
                with library.connect() as db:
                    db.execute('UPDATE media SET removed=1 WHERE id=?', ('example-test-v1',))
                library.install_example(first)
                self.assertEqual(library.list(), [])
                with library.connect() as db:
                    db.execute('UPDATE media SET removed=0 WHERE id=?', ('example-test-v1',))
                self.assertEqual(len(library.list()), 1)
                self.assertFalse((base/'library/sample.mp4').exists())
                sample['filename'] = '../outside.mp4'
                (first/'manifest.json').write_text(json.dumps(sample))
                with self.assertRaises(ValueError): library.install_example(first)
            finally:
                library.close()


if __name__ == '__main__': unittest.main()
