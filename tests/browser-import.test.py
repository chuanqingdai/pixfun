"""Temporary libraries and loopback-only HTTP/TLS; no production configuration."""
import base64
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from desktop_service import Library, PHOTO, VIDEO
from media_sync import MediaSync
from browser_import import BrowserHandler
from phone_sync import PhoneError, PhoneServer


class BrowserImportTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='pixfun-browser-import-test-')
        self.root=Path(self.temp.name).resolve();self.work=self.root/'copies';self.work.mkdir()
        self.library=Library(self.root/'library');self.queued=[];self.library.enqueue=self.queued.append
        self.sync=MediaSync(self.library,PHOTO,VIDEO,monitor=False)
        self.sync.configure_storage(dict(kind='working',path=str(self.work)))
        self.web=self.sync.browser_import;self.web.origin='https://localhost:8443'
        with patch.object(self.web,'start'):self.web.begin({})
        self.secret=self.web.session['secret']
        self.credentials=self.web.claim(dict(secret=self.secret,client='a'*64))
        self.auth='Bearer '+self.credentials['token'];self.s=self.web.authorize(self.auth)
        self.data=b'isolation-test-media'
        self.meta=dict(fileName='test.jpg',assetId='selected',sha256=hashlib.sha256(self.data).hexdigest(),size=len(self.data))

    def tearDown(self):
        self.sync.close();self.library.close();self.temp.cleanup()

    def start(self):return self.web.start_batch(self.s,dict(files=[self.meta]))
    def upload(self):return self.web.receive(self.s,self.meta,io.BytesIO(self.data),len(self.data))

    def test_complete_revokes_upload_and_reuses_library_analysis_queue(self):
        recognized=[];self.web.analysis=recognized.append
        self.start();self.upload();result=self.web.complete(self.s)
        self.assertEqual(result,dict(complete=True,completed=1,skipped=0))
        self.assertEqual(len(self.queued),1)
        self.assertEqual(recognized,self.queued)
        item,_=self.library.get(self.queued[0]);self.assertEqual(item['importBatchId'],self.s['batch'])
        self.assertEqual(item['syncSourceName'],'Phone import')
        self.assertEqual(self.sync.snapshot()['devices'],[])
        with self.assertRaises(PhoneError):self.upload()
        with self.assertRaises(PhoneError):self.web.claim(dict(secret=self.secret,client='a'*64))
        self.assertEqual(self.web.complete(self.s),result)

    def test_no_tokens_or_pairing_links_in_connected_snapshot(self):
        snapshot=json.dumps(self.sync.snapshot())
        self.assertNotIn(self.secret,snapshot);self.assertNotIn(self.credentials['token'],snapshot)
        self.assertNotIn('"url"',json.dumps(self.web.snapshot()))

    def test_redeem_once_same_browser_can_retry_lost_response(self):
        self.assertEqual(self.web.claim(dict(secret=self.secret,client='a'*64)),self.credentials)
        with self.assertRaises(PhoneError):self.web.claim(dict(secret=self.secret,client='b'*64))

    def test_expired_pending_and_connected_sessions(self):
        self.s['expiresAt']=time.time()-1
        with self.assertRaises(PhoneError):self.web.authorize(self.auth)
        self.assertEqual(self.web.snapshot()['phase'],'expired')
        with patch.object(self.web,'start'):self.web.begin({})
        self.web.session['expiresAt']=time.time()-1
        self.assertNotIn('url',self.web.snapshot())

    def test_new_code_revokes_previous_token(self):
        with patch.object(self.web,'start'):self.web.begin({})
        with self.assertRaises(PhoneError):self.web.authorize(self.auth)
        self.assertTrue(self.web.snapshot()['url'].startswith('https://localhost:8443/import#'))

    def test_cross_session_dedup_and_no_reanalysis(self):
        self.start();self.upload();self.web.complete(self.s)
        with patch.object(self.web,'start'):self.web.begin({})
        c=self.web.claim(dict(secret=self.web.session['secret'],client='b'*64));self.s=self.web.authorize('Bearer '+c['token'])
        self.meta['fileName']='renamed.jpg';self.start()
        self.assertTrue(self.web.check(self.s,self.meta)['complete'])
        self.assertEqual(self.web.complete(self.s)['skipped'],1)
        self.assertEqual(len(self.queued),1)

    def test_cancel_keeps_completed_files_and_revokes_session(self):
        self.start();self.upload();self.web.cancel_session()
        with self.assertRaises(PhoneError):self.web.authorize(self.auth)
        self.assertTrue(Path(self.sync.assets()[0]['workingPath']).is_file())

    def test_cancel_during_upload_never_publishes(self):
        self.start();web=self.web
        class CancelReader(io.BytesIO):
            def read(self,n):
                web.cancel_session()
                return super().read(n)
        with self.assertRaises(Exception):self.web.receive(self.s,self.meta,CancelReader(self.data),len(self.data))
        self.assertEqual(list(self.work.rglob('*.jpg')),[])

    def test_model_failure_does_not_fail_verified_transfer(self):
        def unavailable(_):raise RuntimeError('models unavailable')
        self.web.analysis=unavailable;self.start();self.upload()
        self.assertEqual(self.web.complete(self.s)['completed'],1)
        self.assertEqual(self.library.get(self.queued[0])[0]['phoneImportAnalysis']['status'],'failed')

    def test_manifest_fixed_and_complete_requires_all_files(self):
        self.start()
        with self.assertRaises(PhoneError):self.web.complete(self.s)
        with self.assertRaises(PhoneError):self.web.check(self.s,{**self.meta,'fileName':'different.jpg'})
        with self.assertRaises(PhoneError):self.web.start_batch(self.s,dict(files=[{**self.meta,'fileName':'different.jpg'}]))
        self.assertTrue(self.start()['ready'])

    def test_checksum_and_interruption_fail_without_publishing_then_retry(self):
        self.start()
        for data in (b'short',b'x'*len(self.data)):
            with self.assertRaises(PhoneError):self.web.receive(self.s,self.meta,io.BytesIO(data),len(self.data))
            self.assertEqual(list(self.work.rglob('*.jpg')),[])
        self.upload();self.assertEqual(self.web.complete(self.s)['completed'],1)

    def test_rejected_files_and_batch_limits(self):
        for files in ([],[self.meta]*201,[self.meta,self.meta],[{**self.meta,'fileName':'../x.jpg'}],[{**self.meta,'fileName':'a.html'}],[{**self.meta,'size':self.web.MAX_FILE+1}]):
            with self.subTest(files=len(files)),self.assertRaises(PhoneError):self.web.start_batch(self.s,dict(files=files))

    def test_save_folder_locked_during_batch(self):
        self.start()
        with self.assertRaises(ValueError):self.sync.configure_storage(dict(kind='working',path=str(self.work)))
        self.web.cancel_session();self.sync.configure_storage(dict(kind='working',path=str(self.work)))

    def test_unconfigured_or_http_transport_fails_closed(self):
        with patch.dict(os.environ,{'PIXFUN_PHONE_PAIR_ORIGIN':''},clear=True),self.assertRaises(PhoneError):self.web.start()
        with patch.dict(os.environ,{'PIXFUN_PHONE_WEB_ORIGIN':'http://localhost:8443'},clear=True),self.assertRaises(PhoneError):self.web.start()
        self.assertIsNone(self.web.server)

    def tls_server(self):
        cert=self.root/'cert.pem';key=self.root/'key.pem'
        subprocess.run(['/usr/bin/openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],capture_output=True,check=True)
        tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);tls.load_cert_chain(cert,key)
        server=PhoneServer(('127.0.0.1',0),BrowserHandler);server.receiver=self.web;server.tls=tls
        self.web.origin='https://localhost:'+str(server.server_port);self.web.server=server
        self.web.thread=threading.Thread(target=server.serve_forever,daemon=True);self.web.thread.start()
        return cert,key

    def test_tls_same_origin_narrow_api_and_entire_batch(self):
        cert,_=self.tls_server()
        context=ssl.create_default_context(cafile=str(cert))
        def request(method,path,data=b'{}',headers=None):
            conn=http.client.HTTPSConnection('localhost',self.web.server.server_port,context=context,timeout=5)
            head={'Origin':self.web.origin,'Authorization':self.auth};head.update(headers or {})
            conn.request(method,path,None if method=='GET' else data,head);res=conn.getresponse();body=res.read();status=res.status;responseHeaders=dict(res.getheaders());conn.close()
            return status,body,responseHeaders
        self.assertEqual(request('GET','/import')[0],200)
        self.assertIn('frame-ancestors',request('GET','/import')[2]['Content-Security-Policy'])
        self.assertEqual(request('GET','/api/desktop/sync')[0],404)
        self.assertEqual(request('GET','/import',headers={'Host':'evil.test'})[0],403)
        self.assertEqual(request('POST','/import/status',headers={'Origin':'https://evil.test'})[0],403)
        self.assertEqual(request('POST','/import/status',headers={'Authorization':'Bearer invalid'})[0],401)
        self.assertEqual(request('POST','/import/start',json.dumps({'files':[self.meta]}).encode())[0],200)
        meta=base64.b64encode(json.dumps(self.meta).encode()).decode()
        self.assertEqual(request('PUT','/import/file',self.data,{'X-Pixfun-Media':meta})[0],200)
        self.assertEqual(request('POST','/import/complete')[0],200)
        self.assertEqual(request('PUT','/import/file',self.data,{'X-Pixfun-Media':meta})[0],409)

    def test_self_signed_certificate_never_becomes_production_qr(self):
        cert,key=self.tls_server();self.web.stop()
        with patch.dict(os.environ,{'PIXFUN_PHONE_WEB_ORIGIN':'https://localhost:8443','PIXFUN_PHONE_WEB_CERT':str(cert),'PIXFUN_PHONE_WEB_KEY':str(key)}),self.assertRaises(PhoneError):self.web.start()
        self.assertIsNone(self.web.server)

    def test_trusted_matching_certificate_passes_preflight_on_loopback(self):
        cert,key=self.tls_server();self.web.stop()
        trusted=ssl.create_default_context(cafile=str(cert))
        # Explicit trust is scoped to this test client; never installed system-wide.
        with patch.dict(os.environ,{'PIXFUN_PHONE_WEB_ORIGIN':'https://localhost:8443','PIXFUN_PHONE_WEB_CERT':str(cert),'PIXFUN_PHONE_WEB_KEY':str(key)}), \
             patch('browser_import.ssl.create_default_context',return_value=trusted), \
             patch('browser_import.PhoneServer',side_effect=lambda address,handler:PhoneServer(('127.0.0.1',0),handler)):
            self.web.start()
        self.assertIsNotNone(self.web.server)
        self.assertEqual(self.web.origin,'https://localhost:8443')


if __name__=='__main__':unittest.main()
