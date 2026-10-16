import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from desktop_service import Library


class DuplicateImports(unittest.TestCase):
    def test_import_batches_and_source_survive_reimport_and_relocation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            paths = [root/name for name in ('a.mp4', 'b.mp4', 'c.mp4', 'moved.mp4')]
            for path in paths: path.write_bytes(b'fixture')
            library = Library(root/'library')
            try:
                with patch.object(library, 'enqueue'):
                    self.assertEqual(library.list(), [])
                    first = library.register([str(p) for p in paths[:2]])['items']
                    self.assertEqual(first[0]['importBatchId'], first[1]['importBatchId'])
                    third = library.register([str(paths[2])])['items'][0]
                    self.assertNotEqual(first[0]['importBatchId'], third['importBatchId'])
                    repeat = library.register([str(paths[0])])['items'][0]
                    self.assertEqual(repeat['importBatchId'], first[0]['importBatchId'])
                    library.patch(first[0]['id'], status='ready', syncSourceId='phone', syncSourceName='Travel phone', syncSourceKind='phone')
                    moved = library.register([str(paths[3])], replace_id=first[0]['id'])['items'][0]
                    self.assertEqual(moved['syncSourceKind'], 'phone')
                    self.assertEqual(moved['syncSourceName'], 'Travel phone')
                    self.assertEqual(moved['importedAt'], first[0]['importedAt'])
                    self.assertEqual(moved['importBatchId'], first[0]['importBatchId'])
            finally: library.close()

    def test_reuse_completed_and_busy_media_without_work_or_popup(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            first, second = root/'coffee.mp4', root/'new.mp4'
            first.write_bytes(b'fixture'); second.write_bytes(b'fixture')
            library = Library(root/'library')
            try:
                with patch.object(library, 'enqueue') as enqueue:
                    initial = library.register([str(first)])['items'][0]
                    self.assertEqual(enqueue.call_count, 1)
                    for status in ['queued', 'analyzing', 'ready', 'error', 'cancelled']:
                        library.patch(initial['id'], status=status, favorite=True, description='Keep me')
                        enqueue.reset_mock()
                        reused = library.register([str(first), str(first)])
                        self.assertEqual(reused['errors'], [])
                        self.assertEqual(len(reused['items']), 1)
                        self.assertEqual(reused['items'][0]['id'], initial['id'])
                        self.assertEqual(reused['items'][0]['status'], status)
                        self.assertTrue(reused['items'][0]['favorite'])
                        self.assertEqual(reused['items'][0]['description'], 'Keep me')
                        enqueue.assert_not_called()
                    mixed = library.register([str(first), str(second), str(root/'missing.mp4')])
                    self.assertEqual(len(mixed['items']), 2)
                    self.assertEqual(len(mixed['errors']), 1, 'Real missing-file failures remain visible')
                    enqueue.assert_called_once_with(mixed['items'][1]['id'])
                    conflict = library.register([str(first)], replace_id=mixed['items'][1]['id'])
                    self.assertEqual(conflict['items'], [])
                    self.assertIn('another library item', conflict['errors'][0])
                    self.assertEqual(len(library.list()), 2)
            finally:
                library.close()


if __name__ == '__main__': unittest.main()
