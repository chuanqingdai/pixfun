(() => {
  'use strict';
  const $=id=>document.getElementById(id);
  let token='', selected=[], manifest=null, busy=false, batchStarted=false, finished=false;
  let maxFile=8*1024**3, maxFiles=200;
  const states=new Map();
  const savedKey='pixfunPhoneImport';
  const random=()=>[...crypto.getRandomValues(new Uint8Array(32))].map(v=>v.toString(16).padStart(2,'0')).join('');
  const bytes=n=>n>=1024**3?(n/1024**3).toFixed(1)+' GB':n>=1024**2?(n/1024**2).toFixed(1)+' MB':Math.ceil(n/1024)+' KB';
  function storageGet(){try{return JSON.parse(sessionStorage.getItem(savedKey)||'null');}catch{return null;}}
  function storageSet(value){try{if(value)sessionStorage.setItem(savedKey,JSON.stringify(value));else sessionStorage.removeItem(savedKey);}catch{/* Transfer still works in this open page. */}}
  function screen(name,title,guidance){
    document.body.dataset.screen=name;
    $('transferTitle').textContent=title;$('transferTitle').focus();
    $('guidance').textContent=guidance;
    $('chooser').hidden=name!=='choose';
    $('selectedFiles').hidden=name!=='choose'||!selected.length;
    $('start').hidden=name!=='choose'&&name!=='paused';
    $('progressArea').hidden=name!=='transfer';
    $('privacyNote').hidden=name!=='choose';
    $('result').hidden=name!=='complete';$('completionNote').hidden=name!=='complete';
    if(name!=='choose')$('selectedFiles').open=false;
  }
  function error(message){$('error').textContent=message;$('error').hidden=false;}
  async function api(path,data={}){
    if(window.PixfunPeer)return window.PixfunPeer.api(path,data,token);
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),30000);
    try{
      const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json',...(token?{'Authorization':'Bearer '+token}:{})},body:JSON.stringify(data),credentials:'omit',referrerPolicy:'no-referrer',signal:controller.signal});
      const result=await response.json();if(!response.ok)throw new Error(result.error||'Could not connect to your Mac.');return result;
    }finally{clearTimeout(timer);}
  }
  function renderFiles(){
    $('fileList').replaceChildren();
    selected.forEach((file,index)=>{const li=document.createElement('li'),name=document.createElement('span'),status=document.createElement('small');name.textContent=file.name;status.textContent=states.get(index)||bytes(file.size);li.append(name,status);$('fileList').append(li);});
    $('selection').textContent=`${selected.length} selected · ${bytes(selected.reduce((n,f)=>n+f.size,0))}`;
    $('selectedFiles').hidden=document.body.dataset.screen!=='choose'||!selected.length;
  }
  function showComplete(result){
    finished=true;busy=false;storageSet(null);
    screen('complete','Transfer complete','Your files are saved. Pixfun processes imported media on your Mac.');
    $('error').hidden=true;
    $('result').textContent=[result.completed?`${result.completed} imported`:'',result.skipped?`${result.skipped} already imported`:''].filter(Boolean).join(' · ')||'All files saved';
  }
  async function connect(){
    try{
      if(!window.isSecureContext)throw new Error('Use the secure link in the QR code on your Mac.');
      const secret=location.hash.slice(1),saved=storageGet();
      let status;
      if(window.PixfunPeer){
        storageSet(null);
        status=await window.PixfunPeer.connect(secret);token=status.token;
      }else if(secret){
        if(!/^[A-Za-z0-9_-]{40,64}$/.test(secret))throw new Error('This code is invalid. Scan a new code on your Mac.');
        const client=saved?.secret===secret?saved.client:random();storageSet({secret,client});
        const result=await api('/import/session',{secret,client});token=result.token;
        storageSet({token});history.replaceState(null,'',location.pathname);status={...result,phase:'connected'};
      }else if(saved?.token){token=saved.token;status=await api('/import/status');}
      else throw new Error('Scan the temporary QR code shown in Pixfun on your Mac.');
      maxFile=status.maxFile;maxFiles=status.maxFiles;
      if(status.phase==='complete'){showComplete(status);return;}
      if(status.phase==='uploading')throw new Error('This page was reloaded during a transfer. Completed files are safe. Scan a new code and select the files again; existing copies will be skipped.');
      screen('choose','Choose what to import','Connected to your Mac. No app to install.');$('start').hidden=true;
    }catch(e){screen('disconnected','Connect to your Mac','Open Import from phone in Pixfun, then scan the new code.');error(e.message||'Cannot connect. Keep both devices on the same Wi-Fi and try again.');}
  }
  $('files').addEventListener('change',()=>{
    if(busy||batchStarted)return;
    selected=[...$('files').files];manifest=null;states.clear();$('error').hidden=true;
    const invalid=selected.find(f=>f.size===0||f.size>maxFile||!(/\.(jpe?g|png|webp|gif|heic|heif|avif|tiff?|bmp|mp4|mov|m4v|webm|avi|mkv|mts|m2ts|ogv|lrf)$/i.test(f.name)));
    const valid=selected.length>0&&selected.length<=maxFiles&&!invalid;
    if(selected.length>maxFiles)error(`Choose up to ${maxFiles} files.`);
    else if(invalid)error(`${invalid.name}: choose a supported photo or video between 1 byte and 8 GB. RAW is not supported.`);
    $('start').disabled=!valid;$('start').hidden=!selected.length;renderFiles();
  });
  async function metadata(file,index){
    const hash=new window.PixfunSHA256();
    for(let offset=0;offset<file.size;offset+=2*1024**2){
      hash.update(new Uint8Array(await file.slice(offset,offset+2*1024**2).arrayBuffer()));
      $('progressLabel').textContent=`Preparing ${index+1} of ${selected.length} · ${file.name}`;
      $('progress').value=Math.min(100,(offset+2*1024**2)/file.size*100);
      await new Promise(resolve=>setTimeout(resolve,0));
    }
    const sha256=hash.hex();return {fileName:file.name,assetId:sha256,sha256,size:file.size};
  }
  function upload(file,meta,index){
    if(window.PixfunPeer)return window.PixfunPeer.upload(file,meta,token,(loaded,total)=>{
      $('progress').value=loaded/total*100;
      $('progressLabel').textContent=loaded===total?`Verifying ${file.name} on your Mac…`:`Sending ${index+1} of ${selected.length} · ${Math.round(loaded/total*100)}%`;
    });
    return new Promise((resolve,reject)=>{
      const request=new XMLHttpRequest();request.open('PUT','/import/file');request.timeout=30*60*1000;
      request.setRequestHeader('Authorization','Bearer '+token);
      const encoded=new TextEncoder().encode(JSON.stringify(meta));request.setRequestHeader('X-Pixfun-Media',btoa(String.fromCharCode(...encoded)));
      request.upload.onprogress=event=>{if(event.lengthComputable){$('progress').value=event.loaded/event.total*100;$('progressLabel').textContent=event.loaded===event.total?`Verifying ${file.name} on your Mac…`:`Sending ${index+1} of ${selected.length} · ${Math.round(event.loaded/event.total*100)}%`;}};
      request.onload=()=>{let result;try{result=JSON.parse(request.responseText);}catch{return reject(new Error('Unexpected response. Retry the remaining files.'));}if(request.status>=200&&request.status<300)resolve(result);else reject(new Error(result.error||'Transfer failed. Retry this file.'));};
      request.onerror=request.ontimeout=()=>reject(new Error('Connection interrupted. Keep both devices on the same Wi-Fi and retry. Completed files are kept.'));
      request.send(file);
    });
  }
  $('start').addEventListener('click',async()=>{
    if(busy||finished||!selected.length)return;
    busy=true;$('start').disabled=true;$('files').disabled=true;$('error').hidden=true;
    screen('transfer','Transferring to your Mac','Keep this page open, your phone unlocked and Pixfun running on your Mac.');
    try{
      if(!manifest){manifest=[];for(let i=0;i<selected.length;i++)manifest.push(await metadata(selected[i],i));}
      if(!batchStarted){await api('/import/start',{files:manifest});batchStarted=true;}
      for(let i=0;i<selected.length;i++){
        $('progress').value=0;$('progressLabel').textContent=`Checking ${i+1} of ${selected.length}…`;
        if(states.has(i))continue;
        const check=await api('/import/check',manifest[i]);
        if(check.complete){states.set(i,'Already imported');renderFiles();continue;}
        const result=await upload(selected[i],manifest[i],i);states.set(i,result.duplicate?'Already imported':'Imported');renderFiles();
      }
      showComplete(await api('/import/complete'));
    }catch(e){screen('paused','Transfer paused','Completed files are safe. Retry to send the remaining files.');error(e.message||'Transfer stopped. Retry the remaining files.');$('start').textContent='Retry remaining';$('start').disabled=false;busy=false;
      if(!batchStarted){manifest=null;$('files').disabled=false;}
    }
  });
  window.addEventListener('beforeunload',event=>{if(busy){event.preventDefault();event.returnValue='';}});
  connect();
})();
