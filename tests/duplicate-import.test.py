import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from desktop_service import Library


class DuplicateImports(unittest.TestCase):
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
