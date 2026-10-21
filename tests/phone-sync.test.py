"""Isolated phone protocol tests. TLS listens on loopback only, never the LAN."""
import base64
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import ssl
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from desktop_service import Library, PHOTO, VIDEO
from media_sync import MediaSync
from phone_sync import PhoneError


class PhoneSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pixfun-phone-test-')
        root = Path(self.temp.name).resolve()
        self.work = root/'work'; self.work.mkdir()
        self.library = Library(root/'database'); self.library.enqueue = lambda _: None
        self.sync = MediaSync(self.library, PHOTO, VIDEO, monitor=False)
        self.sync.configure_storage(dict(kind='working', path=str(self.work)))
        self.receiver = self.sync.phone_sync
        self.receiver.pairing = dict(secret='test-secret', expiresAt=time.time()+300, payload='test')
        self.credential = self.receiver.pair(dict(secret='test-secret', name='Test iPhone'))
        self.phone = self.receiver.authorize('Bearer '+self.credential['token'])
        self.data = b'test-media-payload'
        self.meta = self.receiver.metadata(dict(fileName='IMG_001.jpg', assetId='asset-001', size=len(self.data), sha256=hashlib.sha256(self.data).hexdigest()))

    def tearDown(self):
        self.sync.close(); self.library.close(); self.temp.cleanup()

    def upload(self, data=None):
        return self.receiver.receive(self.phone, self.meta, io.BytesIO(self.data if data is None else data), len(self.data))

    def test_disabled_by_default_and_no_secret_in_snapshot(self):
        self.assertIsNone(self.receiver.server)
        snapshot = self.sync.snapshot()
        self.assertFalse(snapshot['wifi']['enabled'])
        self.assertNotIn('credential', snapshot['devices'][0])
        self.assertNotIn(self.credential['token'], json.dumps(snapshot))

    def test_single_use_and_expired_pairing(self):
        with self.assertRaises(PhoneError): self.receiver.pair(dict(secret='test-secret', name='Second'))
        self.receiver.pairing = dict(secret='expired', expiresAt=time.time()-1)
        with self.assertRaises(PhoneError): self.receiver.pair(dict(secret='expired', name='Second'))
        self.assertEqual(len(self.receiver.phones()), 1)

    def test_revocation_prevents_authentication_but_keeps_files(self):
        self.upload()
        self.receiver.phone_action(dict(action='phoneRemove', id=self.phone['id']))
        with self.assertRaises(PhoneError): self.receiver.authorize('Bearer '+self.credential['token'])
        self.assertTrue(Path(self.sync.assets()[0]['workingPath']).is_file())

    def test_verified_import_and_idempotent_retry(self):
        self.assertTrue(self.upload()['complete'])
        self.assertTrue(self.upload()['duplicate'])
        self.assertEqual(len(self.sync.assets()), 1)
        self.assertEqual(Path(self.sync.assets()[0]['workingPath']).read_bytes(), self.data)
        self.assertEqual(self.receiver.phones()[0]['completed'], 1)
        self.assertFalse(self.sync.busy())

    def test_wrong_checksum_never_publishes(self):
        with self.assertRaises(PhoneError): self.upload(b'x'*len(self.data))
        self.assertEqual(self.sync.assets(), [])
        self.assertEqual(list(self.work.rglob('*.jpg')), [])
        self.assertEqual(list(self.work.rglob('*.partial')), [])

    def test_disconnected_upload_retries_without_duplicates(self):
        with self.assertRaises(PhoneError): self.upload(b'short')
        self.assertFalse(self.receiver.busy())
        self.assertTrue(self.upload()['complete'])
        self.assertEqual(len(self.sync.assets()), 1)

    def test_pause_before_upload_and_resume(self):
        self.receiver.phone_action(dict(action='phonePause', id=self.phone['id']))
        with self.assertRaises(PhoneError): self.upload()
        self.receiver.phone_action(dict(action='phoneResume', id=self.phone['id']))
        self.assertTrue(self.upload()['complete'])

    def test_pause_during_copy_does_not_get_overwritten(self):
        receiver = self.receiver
        key = self.phone['id']
        class PausingReader(io.BytesIO):
            def read(self, size):
                receiver.phone_action(dict(action='phonePause', id=key))
                return super().read(size)
        with self.assertRaises(Exception): receiver.receive(self.phone, self.meta, PausingReader(self.data), len(self.data))
        self.assertFalse(receiver.phones()[0]['automatic'])
        self.assertEqual(list(self.work.rglob('*.jpg')), [])

    def test_rejects_unsafe_names_and_media(self):
        valid = dict(fileName='a.jpg', assetId='a', size=1, sha256='a'*64)
        for name in ('../a.jpg', '/a.jpg', '.a.jpg', 'a\\b.jpg', 'a:b.jpg', 'a\n.jpg', 'script.py', 'a.pixfun.json'):
            with self.subTest(name=name), self.assertRaises(PhoneError): self.receiver.metadata({**valid, 'fileName':name})
        for size in (0, -1, True, 33*1024**3):
            with self.subTest(size=size), self.assertRaises(PhoneError): self.receiver.metadata({**valid, 'size':size})

    def test_symbolic_link_destination_does_not_escape(self):
        outside = self.work.parent/'outside'; outside.mkdir()
        (self.work/'Pixfun Media').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(PhoneError): self.upload()
        self.assertEqual(list(outside.iterdir()), [])

    def test_low_space_never_publishes(self):
        usage = type('Usage', (), {'free': 1})()
        with patch('phone_sync.shutil.disk_usage', return_value=usage), self.assertRaises(PhoneError): self.upload()
        self.assertEqual(list(self.work.rglob('*.jpg')), [])

    def test_storage_change_is_blocked_during_phone_copy(self):
        self.receiver.active = self.phone['id']
        try:
            with self.assertRaises(ValueError): self.sync.configure_storage(dict(kind='working', path=str(self.work)))
        finally: self.receiver.active = None

    def test_library_registration_retry_reuses_verified_copy(self):
        with patch.object(self.library, 'register', return_value=dict(errors=['error'],items=[])), self.assertRaises(PhoneError): self.upload()
        self.assertEqual(len(list(self.work.rglob('*.jpg'))), 1)
        self.assertTrue(self.upload()['complete'])
        self.assertEqual(len(list(self.work.rglob('*.jpg'))), 1)

    def test_changed_copy_is_preserved(self):
        self.upload()
        original = Path(self.sync.assets()[0]['workingPath']); original.write_bytes(b'user edit')
        self.upload()
        self.assertEqual(original.read_bytes(), b'user edit')
        self.assertEqual(len(self.sync.assets()), 2)

    def test_archive_reuses_existing_pipeline(self):
        archive = self.work.parent/'archive'; archive.mkdir()
        self.sync.configure_storage(dict(kind='archive',path=str(archive)))
        self.upload()
        self.sync.archive_future.result(timeout=10)
        asset = self.sync.assets()[0]
        self.assertEqual(asset['archiveStatus'], 'completed')
        self.assertEqual(Path(asset['archivePath']).read_bytes(), self.data)

    def test_restart_preserves_pairing_and_dedup(self):
        self.upload(); self.sync.close()
        self.sync = MediaSync(self.library, PHOTO, VIDEO, monitor=False)
        self.receiver = self.sync.phone_sync
        self.phone = self.receiver.authorize('Bearer '+self.credential['token'])
        self.assertTrue(self.upload()['duplicate'])
        self.assertIsNone(self.receiver.server)

    def request(self, method, path, data, headers=None):
        cert = self.library.directory/'phone-sync/certificate.pem'
        context = ssl.create_default_context(cafile=str(cert)); context.check_hostname = False
        connection = http.client.HTTPSConnection('127.0.0.1', self.receiver.server.server_port, context=context, timeout=5)
        connection.request(method, path, data, headers or {})
        response = connection.getresponse()
        result = response.status, json.loads(response.read())
        connection.close(); return result

    def test_tls_upload_and_narrow_api(self):
        self.receiver.start(host='127.0.0.1', port=0)
        auth = {'Authorization': 'Bearer '+self.credential['token']}
        self.assertEqual(self.request('POST','/v1/status',b'{}',auth)[0],200)
        self.assertEqual(self.request('POST','/v1/status',b'{}')[0],401)
        self.assertEqual(self.request('POST','/api/desktop/sync',b'{}',auth)[0],404)
        self.assertEqual(self.request('POST','/v1/status',b'{}',{**auth,'Origin':'http://evil.test'})[0],403)
        meta = dict(fileName='TLS.jpg',assetId='tls',size=len(self.data),sha256=hashlib.sha256(self.data).hexdigest())
        headers = {**auth, 'X-Pixfun-Media':base64.b64encode(json.dumps(meta).encode()).decode()}
        self.assertEqual(self.request('PUT','/v1/upload',self.data,headers)[0],200)
        self.assertEqual(len(self.sync.assets()),1)
        self.assertEqual(os.stat(self.library.directory/'phone-sync/private-key.pem').st_mode & 0o777,0o600)


if __name__ == '__main__': unittest.main()
