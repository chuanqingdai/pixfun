/* Only encrypted connection descriptions reach HTTPS. File RPCs use DTLS/SCTP. */
(() => {
  'use strict';
  const encode=new TextEncoder(),decode=new TextDecoder();
  const b64=bytes=>btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  const unb64=s=>Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-s.length%4)%4)),c=>c.charCodeAt(0));
  const hex=bytes=>[...bytes].map(n=>n.toString(16).padStart(2,'0')).join('');
  let pc,channel,serial=0;const pending=new Map();
  const disconnected='Connection interrupted. Keep both devices on the same Wi-Fi and scan a new code. Completed files are kept.';
  function close(){for(const item of pending.values()){clearTimeout(item.timer);item.reject(new Error(disconnected));}pending.clear();if(pc)pc.close();}
  async function signal(action,id,token,data={}){
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);
    try{const response=await fetch('/api/pair',{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},credentials:'omit',referrerPolicy:'no-referrer',signal:controller.signal,body:JSON.stringify({action,id,...data})});const r=await response.json();if(!response.ok)throw Error(r.error||'Could not connect. Create a new code.');return r;}finally{clearTimeout(timer);}
  }
  function rpc(path,data={},token=''){
    return new Promise((resolve,reject)=>{
      if(!channel||channel.readyState!=='open')return reject(Error(disconnected));
      const id=++serial,timer=setTimeout(()=>{pending.delete(id);reject(Error(disconnected));close();},path==='/import/file-end'?120000:35000);
      pending.set(id,{resolve,reject,timer});channel.send(JSON.stringify({id,path,data,token}));
    });
  }
  async function connect(fragment){
    if(!window.isSecureContext||!window.RTCPeerConnection||!crypto.subtle)throw Error('Open this link in Safari or Chrome using the QR code on your Mac.');
    const match=/^v1\.([a-f0-9]{64})\.([A-Za-z0-9_-]{43})$/.exec(fragment);
    if(!match)throw Error('Scan a new code on your Mac.');
    const [,id,secret]=match,rawKey=unb64(secret);
    const key=await crypto.subtle.importKey('raw',rawKey,'AES-GCM',false,['encrypt','decrypt']);
    const authKey=await crypto.subtle.importKey('raw',rawKey,{name:'HMAC',hash:'SHA-256'},false,['sign']);
    const auth=hex(new Uint8Array(await crypto.subtle.sign('HMAC',authKey,encode.encode('pixfun-phone-auth-v1'))));
    const aad=role=>encode.encode('pixfun-pair-v1:'+role+':'+id);
    const {offer}=await signal('offer',id,auth),packed=unb64(offer);
    let remote;try{remote=JSON.parse(decode.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:packed.slice(0,12),additionalData:aad('offer')},key,packed.slice(12))));}catch{throw Error('Could not verify this connection. Scan a new code.');}
    if(remote.type!=='offer'||typeof remote.sdp!=='string'||remote.sdp.length>32000)throw Error('Invalid connection. Scan a new code.');
    pc=new RTCPeerConnection({iceServers:[]});
    const ready=new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{reject(Error('Could not connect directly. Use the same Wi-Fi (not a guest network), allow local network access if asked, then scan a new code.'));close();},30000);
      pc.ondatachannel=event=>{
        if(channel||event.channel.label!=='pixfun-import-v1'){event.channel.close();return;}
        channel=event.channel;
        channel.onmessage=event=>{try{const r=JSON.parse(event.data),p=pending.get(r.id);if(p){pending.delete(r.id);clearTimeout(p.timer);r.error?p.reject(Error(r.error)):p.resolve(r.result);}}catch{close();}};
        channel.onopen=()=>{clearTimeout(timer);resolve();};
        channel.onclose=()=>{clearTimeout(timer);reject(Error(disconnected));close();};
      };
    });
    // Attach a handler now, even if gathering fails before the connection wait.
    ready.catch(()=>{});
    try{
      await pc.setRemoteDescription(remote);
      await pc.setLocalDescription(await pc.createAnswer());
      if(pc.iceGatheringState!=='complete')await new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>reject(Error('Wi-Fi connection timed out. Scan a new code.')),10000);
        pc.onicegatheringstatechange=()=>{if(pc.iceGatheringState==='complete'){clearTimeout(timer);resolve();}};
      });
      const nonce=crypto.getRandomValues(new Uint8Array(12));
      const ciphertext=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv:nonce,additionalData:aad('answer')},key,encode.encode(JSON.stringify({type:'answer',sdp:pc.localDescription.sdp}))));
      const out=new Uint8Array(12+ciphertext.length);out.set(nonce);out.set(ciphertext,12);
      await signal('answer',id,auth,{answer:b64(out)}); await ready;
      const client=hex(crypto.getRandomValues(new Uint8Array(32)));
      const result=await rpc('/import/session',{secret,client});
      history.replaceState(null,'',location.pathname);
      return {...result,phase:'connected'};
    }catch(e){close();throw e;}
  }
  async function upload(file,meta,token,progress){
    await rpc('/import/file-begin',meta,token);
    for(let offset=0;offset<file.size;offset+=32768){
      const data=new Uint8Array(await file.slice(offset,offset+32768).arrayBuffer());
      const result=await rpc('/import/file-chunk',{offset,chunk:btoa(String.fromCharCode(...data))},token);
      if(result.complete&&result.duplicate)return result;
      if(result.received!==offset+data.length)throw Error('Transfer interrupted. Scan a new code.');
      progress(result.received,file.size);
    }
    return rpc('/import/file-end',{},token);
  }
  window.PixfunPeer={connect,api:rpc,upload,close};
  window.addEventListener('pagehide',close);
})();
