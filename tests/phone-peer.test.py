"""Real encrypted loopback data channel and isolated library; no personal media."""
import asyncio
import base64
import hashlib
import io
import json
from pathlib import Path
import secrets
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from aiortc import RTCPeerConnection, RTCConfiguration, RTCSessionDescription
from desktop_service import Library, PHOTO, VIDEO
from media_sync import MediaSync
from phone_peer import PeerSession, seal, unseal, phone_token
from phone_sync import PhoneError

class PeerTests(unittest.TestCase):
    def test_service_denial_is_not_misreported_as_user_network_failure(self):
        peer=object.__new__(PeerSession)
        peer.origin='https://test.invalid'; peer.room='0'*64; peer.host_token='1'*64
        for code,part in [(403,'denied access'),(401,'denied access'),(429,'Too many'),(503,'temporarily unavailable')]:
            with self.subTest(code=code), patch('phone_peer.build_opener') as opener:
                opener.return_value.open.side_effect=HTTPError(peer.origin,code,'hidden detail',{},io.BytesIO(b''))
                with self.assertRaisesRegex(PhoneError,part) as error: peer.signal('create')
                self.assertNotIn('hidden detail',str(error.exception))

    def test_start_preserves_actionable_service_error(self):
        peer=object.__new__(PeerSession)
        peer.loop=None; peer.prepare=lambda:None
        with patch('phone_peer.asyncio.run_coroutine_threadsafe') as start, patch.object(peer,'stop'):
            start.return_value.result.side_effect=PhoneError('The pairing service denied access (HTTP 403).')
            with self.assertRaisesRegex(PhoneError,'HTTP 403'): peer.start()

    def test_signaling_authentication_and_tamper(self):
        key=secrets.token_urlsafe(32); room=secrets.token_hex(32)
        value={'type':'offer','sdp':'fingerprint:example'}
        encrypted=seal(key,room,'offer',value)
        self.assertEqual(unseal(key,room,'offer',encrypted),value)
        self.assertNotIn('fingerprint',encrypted)
        for secret,r,role in [(secrets.token_urlsafe(32),room,'offer'),(key,room,'answer'),(key,'0'*64,'offer')]:
            with self.assertRaises(Exception): unseal(secret,r,role,encrypted)
        self.assertEqual(len(phone_token(key)),64)

    def test_real_peer_upload_and_integrity(self):
        with tempfile.TemporaryDirectory(prefix='pixfun-peer-test-') as tmp:
            root=Path(tmp); (root/'copies').mkdir()
            lib=Library(root/'library'); queued=[];lib.enqueue=queued.append
            sync=MediaSync(lib,PHOTO,VIDEO,monitor=False)
            sync.configure_storage({'kind':'working','path':str(root/'copies')})
            r=sync.browser_import;r.origin='https://test.invalid'
            with patch.object(r,'start'):r.begin({})
            peer=PeerSession(r,r.session,'https://test.invalid');r.peer=peer
            signal={}
            def signaling(action,**data):
                if action=='create': signal.update(data);return {'expiresAt':r.session['expiresAt']}
                if action=='poll': return {'answer':signal.get('answer')}
                if action=='delete': signal['deleted']=True;return {}
            peer.signal=signaling
            try:
                peer.start()
                self.assertTrue(peer.public_url.startswith('https://test.invalid/import#v1.'))
                asyncio.run(self.transfer(peer,signal,r,queued))
                assets=sync.assets();self.assertEqual(len(assets),1)
                self.assertEqual(Path(assets[0]['workingPath']).read_bytes(),b'peer-test'*12000)
            finally:
                sync.close();peer.thread.join(5);lib.close()
                self.assertFalse(peer.thread.is_alive())

    async def transfer(self,peer,signal,r,queued):
        pc=RTCPeerConnection(RTCConfiguration(iceServers=[]));opened=asyncio.Event();channels=[];pending={};seq=0
        @pc.on('datachannel')
        def datachannel(channel):
            channels.append(channel)
            @channel.on('open')
            def ready():opened.set()
            if channel.readyState=='open': opened.set()
            @channel.on('message')
            def message(raw):
                value=json.loads(raw);future=pending.pop(value['id'],None)
                if future and not future.done():future.set_result(value)
        async def rpc(path,data=None,token=''):
            nonlocal seq
            seq+=1;future=asyncio.get_running_loop().create_future();pending[seq]=future
            channels[0].send(json.dumps(dict(id=seq,path=path,data=data or {},token=token)))
            value=await asyncio.wait_for(future,10)
            return value
        try:
            offer=unseal(peer.secret,peer.room,'offer',signal['offer'])
            await pc.setRemoteDescription(RTCSessionDescription(**offer))
            await pc.setLocalDescription(await pc.createAnswer())
            signal['answer']=seal(peer.secret,peer.room,'answer',dict(type='answer',sdp=pc.localDescription.sdp))
            await asyncio.wait_for(opened.wait(),15)
            wrong=await rpc('/import/session',dict(secret='invalid',client='a'*64));self.assertIn('error',wrong)
            claim=await rpc('/import/session',dict(secret=peer.secret,client='a'*64));token=claim['result']['token']
            denied=await rpc('/import/start',{},'wrong');self.assertIn('error',denied)
            denied=await rpc('/api/desktop/library',{},token);self.assertIn('error',denied)
            data=b'peer-test'*12000
            meta=dict(fileName='synthetic.jpg',assetId='test',sha256=hashlib.sha256(data).hexdigest(),size=len(data))
            self.assertIn('result',await rpc('/import/start',dict(files=[meta]),token))
            self.assertIn('result',await rpc('/import/file-begin',meta,token))
            for offset in range(0,len(data),32768):
                chunk=data[offset:offset+32768]
                result=await rpc('/import/file-chunk',dict(offset=offset,chunk=base64.b64encode(chunk).decode()),token)
                self.assertEqual(result['result']['received'],offset+len(chunk))
            self.assertIn('result',await rpc('/import/file-end',{},token))
            result=await rpc('/import/complete',{},token);self.assertEqual(result['result']['completed'],1)
            self.assertEqual(len(queued),1)
            self.assertTrue(signal.get('deleted'))
            self.assertNotIn('url',r.snapshot())
        finally: await pc.close()

if __name__=='__main__':unittest.main()
