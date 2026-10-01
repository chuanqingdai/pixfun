/* Single-file web analysis. The native app keeps its independent library. */
(() => {
  'use strict';
  const kindOf=file=>/^image\//.test(file.type)||/\.(jpe?g|png|webp|gif|avif|heic|heif|bmp|tiff?)$/i.test(file.name)?'image':/^video\//.test(file.type)||/\.(mp4|mov|m4v|mkv|webm|avi|mts|m2ts|ogv)$/i.test(file.name)?'video':null;
  function validate(files){
    if(files.length!==1)return 'Choose one video or photo at a time.';
    if(!kindOf(files[0]))return 'Choose a video or photo, such as MP4, MOV, JPEG, or PNG.';
    if(!files[0].size||files[0].size>500*1024*1024)return 'Choose a file between 1 byte and 500 MB.';
    return '';
  }
  const pending=item=>!!item&&['reading','uploading','analyzing','understanding'].includes(item.status);
  function repetitive(text){const words=String(text).toLowerCase().match(/[\p{L}\p{N}_]+/gu)||[];if(words.length<16)return false;for(let width=1;width<=4;width++)for(let offset=0;offset<width;offset++){const counts=new Map();let total=0,max=0;for(let i=offset;i+width<=words.length;i+=width){const chunk=words.slice(i,i+width).join(' '),count=(counts.get(chunk)||0)+1;counts.set(chunk,count);max=Math.max(max,count);total++;}if(total>=8&&max/total>=.8)return true;}return false;}
  function visualDescription(item){return item.description||item.result?.analysis.assetUnderstanding?.summary||'';}
  function editingSummary(text){
    const labels=['Theme','Key shots','Suggested use','Watch out'];
    const lines=String(text||'').trim().split(/\n+/).map(line=>line.trim()).filter(Boolean);
    const rows=labels.map(label=>{const line=lines.find(line=>line.toLowerCase().startsWith(label.toLowerCase()+':'));return line?[label,line.slice(label.length+1).trim()]:null;}).filter(row=>row&&row[1]);
    return rows.length===4&&lines.length===4?rows:[];
  }
  const time=n=>`${Math.floor((n||0)/60)}:${String(Math.floor((n||0)%60)).padStart(2,'0')}`;
  if(typeof document==='undefined'){module.exports={kindOf,validate,pending,time,repetitive,visualDescription,editingSummary};return;}
  if(window.PixfunDesktop)return;
  const $=id=>document.getElementById(id),assets=window.PixfunAssets,metadata=window.PixfunMetadata;
  let current=null,request=null,db=null,preview=null,task=0,routeVersion=0;
  function node(tag,text,cls){const el=document.createElement(tag);if(text!=null)el.textContent=text;if(cls)el.className=cls;return el;}
  function notice(text){$('webAnalysisNotice').textContent=text;$('webAnalysisNotice').hidden=!text;}
  const storageReady=new Promise(resolve=>{
    try{const open=indexedDB.open('pixfun-footage-library',1);
      open.onupgradeneeded=()=>open.result.createObjectStore('media',{keyPath:'id'});
      open.onsuccess=()=>{db=open.result;resolve();};open.onerror=()=>resolve();open.onblocked=()=>resolve();
    }catch{resolve();}
  });
  async function stored(mode,action){
    await storageReady;if(!db)throw new Error('Browser storage is unavailable. Keep this page open to retain your analysis.');
    return new Promise((resolve,reject)=>{const tx=db.transaction('media',mode),req=action(tx.objectStore('media'));tx.oncomplete=()=>resolve(req.result);tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error);});
  }
  async function save(item,strict=false){const {url,...record}=item;try{await stored('readwrite',store=>store.put(record));}catch(error){notice('This file could not be saved in your browser. Keep this page open to retain your analysis.');if(strict)throw error;}}
  function setPage(active){
    document.title=active?'Footage analysis — Pixfun':'Pixfun — AI Video Editing for Travel Creators';
    document.body.classList.toggle('web-analysis-mode',active);document.body.classList.remove('library-mode','studio-mode');
    $('mediaLibrary').hidden=true;$('webAnalysis').hidden=!active;
    if(active){$('results').hidden=true;$('sourceVideo').pause();$('outputVideo').pause();}
    else preview?.pause?.();
    document.dispatchEvent(new Event('pixfun:viewchange'));
  }
  function showRoute(){
    routeVersion++;
    history.pushState(null,'',current?`#analysis/${current.id}`:'#analyze');setPage(true);render();
    window.scrollTo({top:0,behavior:'instant'});$('webAnalysisTitle').focus({preventScroll:true});
  }
  async function restoreRoute(){
    const token=++routeVersion,hash=location.hash;
    if(hash==='#library'||hash.startsWith('#workspace/'))history.replaceState(null,'','#analyze');
    const active=location.hash==='#analyze'||location.hash.startsWith('#analysis/');setPage(active);if(!active)return;
    if(location.hash==='#analyze'){preview?.pause?.();$('webUpload').hidden=false;$('webAnalysisReport').hidden=true;$('webNewFile').hidden=true;$('webAnalysisTitle').textContent='Understand your footage.';$('webAnalysisMeta').textContent='Explore one video or photo, from the first frame to the details.';return;}
    const id=location.hash.slice('#analysis/'.length);
    if(current?.id===id){render();return;}
    if(pending(current)){history.replaceState(null,'',`#analysis/${current.id}`);render();notice('Finish or stop the current analysis before opening another file.');return;}
    try{
      const saved=await stored('readonly',store=>store.get(id));if(token!==routeVersion)return;
      if(!saved?.file)throw new Error('This analysis is not available in this browser. Import the original file to start again.');
      if(current)URL.revokeObjectURL(current.url);current={...saved,url:URL.createObjectURL(saved.file)};
      if(pending(current)||current.status==='queued'){current.status='cancelled';current.error='Analysis was interrupted. Retry to continue.';await save(current);}
      notice('');render();
    }catch(error){if(token!==routeVersion)return;history.replaceState(null,'','#analyze');await restoreRoute();notice(error.message);}
  }
  function choose(){if(pending(current)){showRoute();notice('Finish or stop the current analysis before importing another file.');return;}$('fileInput').click();}
  async function importFiles(fileList){
    const files=Array.from(fileList||[]);if(!files.length)return;
    const error=validate(files);if(error){if($('webAnalysis').hidden){setPage(true);history.pushState(null,'','#analyze');await restoreRoute();}notice(error);$('fileInput').value='';return;}
    if(pending(current)){showRoute();notice('Finish or stop the current analysis before importing another file.');return;}
    preview?.pause?.();if(current)URL.revokeObjectURL(current.url);
    const file=files[0];current={id:crypto.randomUUID(),file,kind:kindOf(file),url:URL.createObjectURL(file),metadata:null,result:null,error:null,status:'reading'};
    $('fileInput').value='';notice('');showRoute();await analyze(current);
  }
  function updateProgress(item){
    if(item!==current)return;
    const loading=pending(item);$('webAnalysisProgress').hidden=!loading;$('webNewFile').disabled=loading;
    $('webStop').textContent=item.status==='understanding'?'Stop waiting':'Stop';
    $('webProgressLabel').textContent=item.status==='uploading'?`Uploading footage${Number.isFinite(item.uploadPercent)?` · ${item.uploadPercent}%`:''}`:item.status==='understanding'?'Understanding visual content with GPT…':item.status==='analyzing'?'Analyzing scenes and audio…':'Reading your file…';
    $('webUploadProgress').hidden=item.status!=='uploading'||!Number.isFinite(item.uploadPercent);
    $('webUploadProgress').value=item.uploadPercent||0;
  }
  function readImage(item){return new Promise((resolve,reject)=>{
    const image=new Image(),timer=setTimeout(()=>{image.src='';reject(new Error('This photo could not be decoded. Try JPEG, PNG, or WebP.'));},20000);
    image.onload=async()=>{clearTimeout(timer);try{resolve({width:image.naturalWidth,height:image.naturalHeight,size:item.file.size,...metadata.readExif(await item.file.slice(0,262144).arrayBuffer())});}catch(error){reject(error);}};
    image.onerror=()=>{clearTimeout(timer);reject(new Error('This browser cannot display this photo. Convert it to JPEG or PNG and retry.'));};image.src=item.url;
  });}
  function upload(item){return new Promise((resolve,reject)=>{
    const xhr=new XMLHttpRequest();request=xhr;xhr.open('POST','/api/import');xhr.timeout=900000;
    xhr.upload.onprogress=event=>{if(event.lengthComputable){item.uploadPercent=Math.round(event.loaded/event.total*100);updateProgress(item);}};
    xhr.upload.onload=()=>{item.status='analyzing';updateProgress(item);};
    xhr.onload=()=>{try{const result=JSON.parse(xhr.responseText);if(xhr.status<200||xhr.status>=300||!result.ok)throw new Error(result.error||'Analysis failed. Please retry.');resolve(result);}catch(error){reject(error instanceof SyntaxError?new Error('The analysis service returned an invalid response. Please retry.'):error);}};
    xhr.onerror=()=>reject(new Error('Cannot reach the analysis service. Check your connection and retry.'));
    xhr.ontimeout=()=>reject(new Error('Analysis timed out. Try a shorter video or retry.'));
    xhr.onabort=()=>reject(new Error('Analysis stopped. Retry when you are ready.'));
    const form=new FormData();form.append('file',item.file);xhr.send(form);
  });}
  async function analyze(item){
    const token=++task;item.error=null;item.status=item.kind==='image'?'reading':'uploading';render();await save(item);
    if(token!==task)return;
    try{
      const result=item.kind==='image'?await readImage(item):await upload(item);if(token!==task)return;
      if(item.kind==='image')item.metadata=result;else{item.result=result;item.metadata=result.analysis.metadata;}
      await save(item);if(token!==task)return;
      item.status='understanding';updateProgress(item);
      const visual=await cloudAnalysis(item,token);if(token!==task)return;
      applyVisual(item,visual);item.status='ready';
    }catch(error){if(token!==task)return;item.status='error';item.error=error.message;}
    request=null;await save(item);if(item===current){updateProgress(item);renderResults();updateMeta();}
  }
  async function photoFrame(item){
    const image=new Image();image.src=item.url;await image.decode();
    const ratio=Math.min(1,960/Math.max(image.naturalWidth,image.naturalHeight)),canvas=document.createElement('canvas');
    canvas.width=Math.max(1,Math.round(image.naturalWidth*ratio));canvas.height=Math.max(1,Math.round(image.naturalHeight*ratio));
    canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);return canvas.toDataURL('image/jpeg',.85);
  }
  async function cloudAnalysis(item,token){
    try{
      const payload=item.kind==='image'?{image:await photoFrame(item)}:{jobId:item.result?.jobId};
      if(token!==task)return {visualAnalysis:{state:'cancelled'}};
      if(item.kind==='video'&&!payload.jobId)return {visualAnalysis:{state:'missing_source',message:'Import this file again to analyze its visual content.'}};
      return await new Promise(resolve=>{
        const xhr=new XMLHttpRequest();request=xhr;xhr.open('POST','/api/vision');xhr.setRequestHeader('Content-Type','application/json');xhr.timeout=240000;
        const failure=(message,state='error')=>resolve({visualAnalysis:{state,message}});
        xhr.onload=()=>{try{const result=JSON.parse(xhr.responseText);if(xhr.status>=200&&xhr.status<300&&result.ok)resolve(result.analysis);else failure(result.error||'Visual analysis failed. Please retry.',result.state);}catch{failure('Visual analysis returned an invalid response. Please retry.');}};
        xhr.onerror=()=>failure('Could not connect to cloud visual analysis. Please retry.');xhr.ontimeout=()=>failure('Visual analysis timed out. Please retry.');xhr.onabort=()=>failure('Visual analysis stopped.','cancelled');xhr.send(JSON.stringify(payload));
      });
    }catch{return {visualAnalysis:{state:'error',message:'Could not prepare this image for visual analysis. Try JPEG or PNG.'}};}
  }
  function applyVisual(item,analysis){item.result={...(item.result||{}),analysis:{...(item.result?.analysis||{}),...analysis,metadata:item.metadata}};}
  async function analyzeVisualOnly(item){
    if(pending(current))return;const token=++task;item.status='understanding';item.error=null;notice('');render();
    const result=await cloudAnalysis(item,token);if(token!==task)return;request=null;applyVisual(item,result);item.status='ready';await save(item);if(item===current){updateProgress(item);renderResults();}
  }
  function seek(seconds){if(!preview||current?.kind!=='video')return;if(preview.readyState>=1)preview.currentTime=seconds;else preview.addEventListener('loadedmetadata',()=>preview.currentTime=seconds,{once:true});preview.scrollIntoView({block:'center',behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});}
  function section(title){const group=node('section',null,'web-report-section');group.append(node('h2',title));$('webAnalysisSections').append(group);return group;}
  function facts(title,rows){const values=rows.filter(([,value])=>value!==null&&value!==undefined&&value!=='');if(!values.length)return;const group=section(title),dl=node('dl');for(const [label,value]of values){const row=node('div');row.append(node('dt',label),node('dd',String(value)));dl.append(row);}group.append(dl);}
  function updateMeta(){
    if(!current)return;const m=current.metadata||{};
    $('webAnalysisMeta').textContent=[current.kind==='video'?'Video':'Photo',current.kind==='video'&&m.duration?time(m.duration):'',m.width&&m.height?`${m.width} × ${m.height}`:'',`${(current.file.size/1048576).toFixed(1)} MB`].filter(Boolean).join(' · ');
  }
  function render(){
    if(!current)return;$('webUpload').hidden=true;$('webAnalysisReport').hidden=false;$('webNewFile').hidden=false;
    $('webAnalysisTitle').textContent=current.title||current.file.name;updateMeta();
    document.title=`${current.title||current.file.name} — Pixfun`;
    if($('webAnalysisPreview').dataset.id!==current.id){
      preview?._disposeScenes?.();preview?.pause?.();preview=node(current.kind==='image'?'img':'video');preview.src=current.url;
      if(current.kind==='video'){preview.controls=true;preview.playsInline=true;preview.preload='metadata';}else preview.alt=current.title||current.file.name;
      $('webAnalysisPreview').replaceChildren(preview);$('webAnalysisPreview').dataset.id=current.id;
    }
    updateProgress(current);renderResults();
  }
  function renderResults(){
    const item=current;if(!item)return;preview?._disposeScenes?.();$('webAnalysisSections').replaceChildren();$('webAnalysisScenes').replaceChildren();
    if(pending(item))return;
    if(item.error){const group=section(item.status==='cancelled'?'Analysis stopped':'Unable to analyze this file');group.append(node('p',item.error));const retry=node('button','Retry analysis','button secondary');retry.type='button';retry.style.marginTop='20px';retry.onclick=()=>{notice('');analyze(item);};group.append(retry);}
    const segments=item.result?.analysis.segments||[],asset=assets.normalize(item),card=assets.buildAssetCard(asset),m=item.metadata||{};
    if(segments.length){
      $('webAnalysisScenes').append(window.PixfunScenes.mount({analysis:item.result.analysis,preview,notes:item.sceneNotes||{},onSave:async notes=>{await save({...item,sceneNotes:notes},true);item.sceneNotes=notes;}}));
    }
    if(item.status==='ready'){
      const vision=item.result?.analysis.visualAnalysis;
      const description=section('Editing summary'),heading=description.querySelector('h2'),head=node('div',null,'web-section-heading'),edit=node('button','Edit','text-button'),text=node('div',null,'web-editing-summary');
      function renderSummary(){
        text.replaceChildren();const value=visualDescription(item),rows=editingSummary(value);
        if(rows.length){const dl=node('dl');for(const [label,value] of rows){const row=node('div');row.append(node('dt',label),node('dd',value));dl.append(row);}text.append(dl);}
        else if(value.length>300){
          // Legacy prose remains available, but no longer dominates the report.
          const first=value.match(/^.*?[.!?](?:\s|$)/s)?.[0]?.trim()||value;
          text.append(node('p',first.length>220?first.slice(0,217)+'…':first));
          const details=node('details'),label=node('summary','Full description');details.append(label,node('p',value));text.append(details);
        }else text.append(node('p',value||vision?.message||'Visual content has not been analyzed yet.'));
      }
      renderSummary();
      edit.type='button';edit.setAttribute('aria-label','Edit description');head.append(heading,edit);description.append(head,text);
      if(vision?.state!=='ready'){const analyzeButton=node('button',vision?'Retry visual analysis':'Analyze content','button secondary');analyzeButton.type='button';analyzeButton.style.marginTop='16px';analyzeButton.onclick=()=>analyzeVisualOnly(item);description.append(analyzeButton);}
      else{description.append(node('p',`GPT · ${vision.frameCount} sampled ${item.kind==='image'?'image':'frames'}`,'web-analysis-source'));}
      edit.onclick=()=>{
        const input=node('textarea',null,'web-description-input');input.value=visualDescription(item);input.rows=5;input.maxLength=8000;input.setAttribute('aria-label','Footage description');
        const actions=node('div',null,'web-description-actions'),saveButton=node('button','Save','button secondary'),cancel=node('button','Cancel','text-button');saveButton.type=cancel.type='button';actions.append(saveButton,cancel);text.hidden=true;edit.hidden=true;description.append(input,actions);input.focus();
        const finish=()=>{input.remove();actions.remove();text.hidden=false;edit.hidden=false;edit.focus();};cancel.onclick=finish;
        saveButton.onclick=async()=>{item.description=input.value.trim();await save(item);renderSummary();finish();};
      };
      facts('Content',[['Subjects',asset.subjects.join(' · ')],['Objects',asset.objects.join(' · ')],['Scenes',asset.scene.join(' · ')],['Actions',asset.actions.join(' · ')],['Visual style',asset.visualStyle.join(' · ')],['Visible text',asset.visibleText.join(' · ')],['Location',asset.location.join(', ')]]);
      if(asset.uncertainties.length)section('Analysis limitations').append(node('p',asset.uncertainties.join('\n')));
      facts('Capture',[['Shot on',asset.capturedAt],['Camera',asset.camera],['Method',card.captureLabel],['Shot size',assets.labels.shotSize[asset.capture.shotSize]],['Movement',assets.labels.cameraMotion[asset.capture.cameraMotion]],['Slow motion',asset.capture.slowMotion===true?'Yes':null]]);
      const use=asset.editing;
      facts('Editing suggestions',[['Role',assets.labels.shotRole[use.shotRole]],['Recommended for',assets.labels.recommendedUse[use.recommendedUse]],['Suggested length',use.suggestedDuration?`${use.suggestedDuration.min}–${use.suggestedDuration.max} seconds`:null],['Importance',use.importance===null?null:`${Math.round(use.importance*100)} / 100`]]);
      facts('Quality',Object.entries(asset.quality).map(([key,value])=>[key[0].toUpperCase()+key.slice(1),Array.isArray(value)?value.join(' · '):value===null?null:`${value} / 100`]));
      facts('Audio',[['Audio track',asset.hasAudio===null?null:asset.hasAudio?'Detected':'No audio track'],['Codec',m.audioCodec],['Speech',asset.audio.hasSpeech===null?null:asset.audio.hasSpeech?'Detected':'None detected'],['Language',item.result?.analysis.subtitleLanguage],['Ambient sounds',asset.audio.ambientTypes.join(' · ')],['Useful ambience',asset.audio.hasUsefulAmbientSound===null?null:asset.audio.hasUsefulAmbientSound?'Yes':'No'],['Quality',asset.audio.audioQuality===null?null:`${asset.audio.audioQuality} / 100`],['Issues',asset.audio.issues.join(' · ')]]);
      if(item.kind==='video'){
        const transcript=section('Transcript');
        const embedded=item.result?.analysis.subtitleState==='embedded',cues=asset.subtitleCues.filter(cue=>embedded||!repetitive(cue.text)),rejected=cues.length!==asset.subtitleCues.length;
        if(rejected)transcript.append(node('p','Repetitive speech recognition was excluded. The transcript needs review.'));
        if(cues.length)for(const cue of cues){const row=node('button',null,'web-transcript-row');row.type='button';row.append(node('time',time(cue.start)),node('span',cue.text));row.onclick=()=>seek(cue.start);transcript.append(row);}
        else if(!rejected){const raw=asset.audio.speechText||item.result?.analysis.transcript||'';transcript.append(node('p',!embedded&&repetitive(raw)?'Repetitive speech recognition was excluded. The transcript needs review.':raw||item.result?.analysis.subtitleMessage||(asset.hasAudio===false?'This video has no audio track.':'No transcript was extracted from this video.')));}
      }
      const warnings=item.result?.analysis.warnings;if(Array.isArray(warnings)&&warnings.length)section('Analysis notes').append(node('p',warnings.join('\n')));
    }
    facts('File details',[['Filename',item.file.name],['Type',item.kind==='video'?'Video':'Photo'],['File size',`${(item.file.size/1048576).toFixed(1)} MB`],['Resolution',m.width&&m.height?`${m.width} × ${m.height}`:null],['Orientation',asset.orientation],['Duration',m.duration?time(m.duration):null],['Frame rate',m.fps?`${m.fps} fps`:null],['Video codec',m.videoCodec],['Subtitle tracks',m.subtitleCount||null],['Subtitle codec',m.subtitleCodec],['Media created',metadata.dateText(m.mediaCreatedAt)],['Date source',m.dateSource]]);
  }
  $('webStop').onclick=async()=>{if(!pending(current))return;const cloud=current.status==='understanding';task++;request?.abort();request=null;current.status=cloud?'ready':'cancelled';current.error=cloud?null:'Analysis stopped. You can retry this file or import another one.';if(cloud)applyVisual(current,{visualAnalysis:{state:'cancelled',message:'Stopped waiting. Cloud analysis may still finish; retry to retrieve the result.'}});await save(current);render();};
  $('webChooseFile').onclick=$('webNewFile').onclick=choose;
  $('fileInput').multiple=false;
  $('webAnalysis').addEventListener('dragover',event=>{event.preventDefault();$('webAnalysis').classList.add('is-dragging');});
  $('webAnalysis').addEventListener('dragleave',event=>{if(!$('webAnalysis').contains(event.relatedTarget))$('webAnalysis').classList.remove('is-dragging');});
  $('webAnalysis').addEventListener('drop',event=>{event.preventDefault();event.stopPropagation();$('webAnalysis').classList.remove('is-dragging');importFiles(event.dataTransfer.files);});
  window.addEventListener('hashchange',restoreRoute);
  window.addEventListener('beforeunload',event=>{if(pending(current)){event.preventDefault();event.returnValue='';}});
  window.PixfunLibrary={importFiles,open:active=>active?showRoute():location.hash='',get hasFiles(){return !!current;}};
  restoreRoute();
})();
