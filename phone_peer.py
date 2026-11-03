"""Authenticated WebRTC data channel; HTTPS carries encrypted SDP only.

No STUN/TURN, HTTP listener, desktop API forwarding, or cloud file transport.
The QR key authenticates DTLS fingerprints via AES-GCM encrypted signaling.
"""
import asyncio
import base64
import hashlib
import hmac
import json
import queue
import secrets
import threading
import time
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.error import HTTPError
from urllib.parse import urlsplit
from phone_sync import PhoneError

DEFAULT_ORIGIN = 'https://pixfun-pair.xiaosheng567.chatgpt.site'

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward a pairing capability to another endpoint.
        return None

def unb64(value): return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))
def b64(value): return base64.urlsafe_b64encode(value).decode().rstrip('=')
def phone_token(secret): return hmac.new(unb64(secret), b'pixfun-phone-auth-v1', hashlib.sha256).hexdigest()

def seal(secret, room, role, value):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    nonce=secrets.token_bytes(12)
    return b64(nonce+AESGCM(unb64(secret)).encrypt(nonce,json.dumps(value).encode(),f'pixfun-pair-v1:{role}:{room}'.encode()))

def unseal(secret, room, role, value):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    raw=unb64(value)
    return json.loads(AESGCM(unb64(secret)).decrypt(raw[:12],raw[12:],f'pixfun-pair-v1:{role}:{room}'.encode()))

class ChunkReader:
    def __init__(self): self.chunks=queue.Queue(2); self.closed=threading.Event()
    def read(self,n):
        deadline=time.monotonic()+35
        while not self.closed.is_set() and time.monotonic()<deadline:
            try: return self.chunks.get(timeout=.25)
            except queue.Empty: pass
        raise PhoneError('Connection interrupted. Completed files are kept.',409)
    def put(self,data):
        deadline=time.monotonic()+10
        while not self.closed.is_set() and time.monotonic()<deadline:
            try: self.chunks.put(data,timeout=.25); return
            except queue.Full: pass
        raise PhoneError('Transfer paused. Scan a new code.',409)
    def close(self): self.closed.set()

class PeerSession:
    def __init__(self,receiver,session,origin):
        self.receiver=receiver; self.session=session; self.origin=origin.rstrip('/')
        p=urlsplit(self.origin)
        if p.scheme!='https' or not p.hostname or p.path or p.query or p.fragment or p.username or p.password:
            raise PhoneError('The secure pairing service is unavailable. Update Pixfun and try again.')
        self.room=secrets.token_hex(32); self.host_token=secrets.token_hex(32)
        self.secret=session['secret']; self.public_url=None; self.pc=None; self.channel=None
        self.reader=None; self.upload_task=None; self.received=0; self.length=0
        self.closed=threading.Event(); self.loop=asyncio.new_event_loop(); self.pending=0
        self.thread=threading.Thread(target=self.run,daemon=True,name='Pixfun phone connection')
        self.thread.start()

    def run(self):
        asyncio.set_event_loop(self.loop)
        self.loop.run_forever()
        tasks=asyncio.all_tasks(self.loop)
        for task in tasks: task.cancel()
        self.loop.run_until_complete(asyncio.gather(*tasks,return_exceptions=True))
        self.loop.run_until_complete(self.loop.shutdown_asyncgens())
        self.loop.run_until_complete(self.loop.shutdown_default_executor())
        self.loop.close()

    def signal(self,action,**data):
        payload=json.dumps(dict(action=action,id=self.room,**data)).encode()
        request=Request(self.origin+'/api/pair',data=payload,headers={
            'Content-Type':'application/json','Authorization':'Bearer '+self.host_token},method='POST')
        try:
            with build_opener(NoRedirect()).open(request,timeout=8) as response:
                if urlsplit(response.url).netloc != urlsplit(self.origin).netloc: raise ValueError()
                raw=response.read(60001)
                if len(raw)>60000: raise ValueError()
                return json.loads(raw)
        except HTTPError as exc:
            code=exc.code; exc.close()
            if code in (401,403):
                raise PhoneError('The pairing service denied access. Phone import is unavailable until service access is restored (HTTP '+str(code)+').') from None
            if code==429:
                raise PhoneError('Too many pairing attempts. Wait a few minutes before trying New code.') from None
            raise PhoneError('The pairing service is temporarily unavailable (HTTP '+str(code)+'). Try again later.') from None
        except Exception:
            raise PhoneError('Could not reach secure pairing. Check your internet connection, then try New code.') from None

    def start(self):
        future=asyncio.run_coroutine_threadsafe(self.prepare(),self.loop)
        try: future.result(timeout=22)
        except PhoneError:
            future.cancel(); self.stop()
            raise
        except Exception:
            future.cancel(); self.stop()
            raise PhoneError('Could not prepare phone import. Check your internet connection, then try New code.') from None

    async def prepare(self):
        from aiortc import RTCPeerConnection, RTCConfiguration
        self.pc=RTCPeerConnection(RTCConfiguration(iceServers=[]))
        self.channel=self.pc.createDataChannel('pixfun-import-v1',ordered=True)
        self.commands=asyncio.Queue(4)
        self.channel.on('message',self.on_message)
        self.channel.on('close',self.disconnected)
        @self.pc.on('connectionstatechange')
        async def changed():
            if self.pc.connectionState=='failed': self.fail('Could not connect directly. Use the same Wi-Fi, avoid guest networks, then create a new code.')
        await self.pc.setLocalDescription(await self.pc.createOffer())
        offer=seal(self.secret,self.room,'offer',dict(type='offer',sdp=self.pc.localDescription.sdp))
        result=await asyncio.to_thread(self.signal,'create',offer=offer,
            hostHash=hashlib.sha256(self.host_token.encode()).hexdigest(),
            phoneHash=hashlib.sha256(phone_token(self.secret).encode()).hexdigest())
        self.session['expiresAt']=min(self.session['expiresAt'],result['expiresAt'])
        self.public_url=self.origin+'/import#v1.'+self.room+'.'+self.secret
        asyncio.create_task(self.consume()); asyncio.create_task(self.poll())

    async def poll(self):
        from aiortc import RTCSessionDescription
        errors=0; answered_at=None
        while not self.closed.is_set() and self.session['phase']=='waiting' and time.time()<self.session['expiresAt']:
            try:
                result=await asyncio.to_thread(self.signal,'poll'); errors=0
                if result.get('answer'):
                    answer=unseal(self.secret,self.room,'answer',result['answer'])
                    if answer.get('type')!='answer' or len(answer.get('sdp',''))>32000: raise ValueError()
                    await self.pc.setRemoteDescription(RTCSessionDescription(**answer))
                    answered_at=time.monotonic()
                    try: await asyncio.to_thread(self.signal,'delete')
                    except PhoneError: pass
                    break
            except Exception:
                errors+=1
                if errors>=3: self.fail('Connection setup failed. Check your internet connection and create a new code.'); return
            await asyncio.sleep(1)
        # Keep expiration enforced even when neither device is polling the desktop UI.
        while not self.closed.is_set() and self.session['phase'] not in ('complete','cancelled','expired'):
            if answered_at and self.session['phase']=='waiting' and time.monotonic()-answered_at>35:
                self.fail('Could not connect directly. Use the same Wi-Fi, avoid guest networks, then create a new code.'); return
            if time.time()>=self.session['expiresAt']:
                self.fail('This code expired. Create a new code.'); return
            await asyncio.sleep(1)
        if self.session['phase']=='complete':
            await asyncio.sleep(2)
            await self.shutdown()

    def on_message(self,message):
        if self.closed.is_set(): return
        if not isinstance(message,str) or len(message)>220000:
            self.fail('Invalid transfer message. Create a new code.'); return
        try: self.commands.put_nowait(message)
        except asyncio.QueueFull: self.fail('Transfer sent too quickly. Create a new code.')

    async def consume(self):
        while not self.closed.is_set():
            raw=await self.commands.get(); command={}
            try:
                command=json.loads(raw)
                if not isinstance(command,dict) or not isinstance(command.get('id'),int): raise ValueError()
                result=await self.dispatch(command)
                reply=dict(id=command['id'],result=result)
            except Exception as exc:
                reply=dict(id=command.get('id') if isinstance(command,dict) else None,error=str(exc) if isinstance(exc,PhoneError) else 'Transfer interrupted. Completed files are kept. Retry or scan a new code.')
            if self.channel.readyState=='open': self.channel.send(json.dumps(reply))

    async def dispatch(self,c):
        r=self.receiver; data=c.get('data',{}); route=c.get('path')
        if not isinstance(data,dict): raise PhoneError('Invalid request.')
        with r.owner.lock:
            if r.session is not self.session: raise PhoneError('This session ended.',401)
            if route=='/import/session': return r.claim(data)
            s=r.authorize('Bearer '+str(c.get('token','')))
        if route=='/import/file-chunk':
            if not self.reader or not self.upload_task: raise PhoneError('No file is being received.',409)
            if self.upload_task.done(): return self.upload_task.result()
            encoded=data.get('chunk','')
            if not isinstance(encoded,str) or len(encoded)>44000: raise PhoneError('Chunk too large.',413)
            try: chunk=base64.b64decode(encoded,validate=True)
            except Exception: raise PhoneError('Invalid chunk.') from None
            if not chunk or len(chunk)>32768 or data.get('offset')!=self.received or self.received+len(chunk)>self.length:
                raise PhoneError('File position changed. Retry this file.',409)
            await asyncio.to_thread(self.reader.put,chunk); self.received+=len(chunk)
            return dict(received=self.received)
        if route=='/import/file-end':
            if not self.upload_task or self.received!=self.length: raise PhoneError('File is incomplete.',409)
            try: return await self.upload_task
            finally: self.reader.close(); self.reader=None; self.upload_task=None
        if route=='/import/file-begin':
            if self.upload_task and not self.upload_task.done(): raise PhoneError('A file is still being received.',409)
            if not r.operation.acquire(blocking=False): raise PhoneError('Another transfer is running.',409)
            try:
                meta=r.selected(s,data); self.length=meta['fileSize']; self.received=0; self.reader=ChunkReader()
            except Exception: r.operation.release(); raise
            async def receive():
                try: return await asyncio.to_thread(r.receive,s,data,self.reader,self.length)
                finally: r.operation.release()
            self.upload_task=asyncio.create_task(receive())
            return dict(ready=True)
        if self.upload_task and not self.upload_task.done(): raise PhoneError('Wait for this file to finish.',409)
        if route=='/import/check': return await asyncio.to_thread(r.check,s,data)
        with r.owner.lock:
            if route=='/import/start': return r.start_batch(s,data)
            if route=='/import/complete': return r.complete(s)
            if route=='/import/status': return dict(phase=s['phase'],completed=s['completed'],skipped=s['skipped'],maxFile=r.MAX_FILE,maxFiles=r.MAX_FILES)
        raise PhoneError('Not found.',404)

    def fail(self,message):
        if self.closed.is_set() or self.session['phase'] in ('complete','cancelled','expired'): return
        self.session.update(phase='expired',secret='',token='',error=message)
        if self.reader: self.reader.close()
        asyncio.create_task(self.shutdown())

    def disconnected(self):
        if self.session['phase']=='complete': asyncio.create_task(self.shutdown())
        else: self.fail('Phone disconnected. Completed files are kept. Create a new code.')

    async def shutdown(self):
        if self.closed.is_set(): return
        self.closed.set()
        if self.reader: self.reader.close()
        if self.upload_task:
            try: await self.upload_task
            except Exception: pass
        if self.pc: await self.pc.close()
        try: await asyncio.to_thread(self.signal,'delete')
        except Exception: pass
        self.loop.call_soon(self.loop.stop)

    def stop(self):
        if not self.closed.is_set() and self.loop.is_running(): asyncio.run_coroutine_threadsafe(self.shutdown(),self.loop)
