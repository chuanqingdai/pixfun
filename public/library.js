/* Multi-file ingestion. Only measured/extracted results are presented as analysis. */
(() => {
  'use strict';
  const byId = id => document.getElementById(id);
  const items = [];
  let view = 'all', page = 'media', selected = null, selectedSegment = null, running = false, stopped = false, activeRequest = null, database = null, skill = '';
  const kindOf = file => file.type.startsWith('image/') || /\.(jpe?g|png|webp|gif|avif|heic|heif|bmp|tiff?)$/i.test(file.name) ? 'image' : file.type.startsWith('video/') || /\.(mp4|mov|m4v|mkv|webm|avi|mts|m2ts|ogv)$/i.test(file.name) ? 'video' : file.type.startsWith('audio/') || /\.(mp3|wav|m4a|aac|flac|ogg|aiff?|opus)$/i.test(file.name) ? 'audio' : null;
  const duration = n => `${Math.floor((n || 0) / 60)}:${String(Math.floor((n || 0) % 60)).padStart(2, '0')}`;
  const size = n => `${(n / 1024 / 1024).toFixed(1)} MB`;
  const inCategory=(item,category)=>category==='all'||(category==='favorites'?!!item.favorite:item.kind===category);
  function createSelection(ids=[]) {
    const chosen=new Set(ids.filter(id=>typeof id==='string').slice(0,100));
    return {has:id=>chosen.has(id),values:()=>Array.from(chosen),toggle(id){if(chosen.has(id)){chosen.delete(id);return true;}if(chosen.size>=100)return false;chosen.add(id);return true;}};
  }
  const labels = { queued:'Queued', reading:'Reading file…', uploading:'Uploading…', analyzing:'Analyzing…', ready:'Ready', error:'Needs attention', cancelled:'Stopped' };
  const isPending = item => ['queued','reading','uploading','analyzing'].includes(item.status);
  const importLabel = item => item.status==='uploading' && Number.isFinite(item.uploadPercent) ? `Uploading ${item.uploadPercent}%` : labels[item.status];
  if(typeof document==='undefined') { module.exports={kindOf,duration,size,inCategory,createSelection};return; }
  const mediaInfo=window.PixfunMetadata;
  const assets=window.PixfunAssets;
  const desktop=window.PixfunDesktop;
  // The web product has its own single-file analysis flow.
  if(!desktop)return;
  byId('fileInput').multiple=true;
  let desktopSnapshot='',desktopPolling=false;
  let selection=null;
  const selectionBar=el('div',null,'media-selection-bar');selectionBar.hidden=true;selectionBar.setAttribute('aria-label','Choose project media');
  const selectionCount=el('span'),selectionOnly=el('button','Selected only','text-button'),selectionCancel=el('button','Cancel','button secondary'),selectionDone=el('button','Use in prompt','button primary');
  const selectForProject=el('button','Select media','button secondary');selectForProject.type='button';selectForProject.onclick=()=>window.PixfunWorkspace?.chooseMedia();byId('mediaImportActions').prepend(selectForProject);
  selectionCount.setAttribute('role','status');
  for(const button of [selectionOnly,selectionCancel,selectionDone])button.type='button';
  selectionOnly.onclick=()=>{if(selection){selection.only=!selection.only;render();}};
  selectionCancel.onclick=()=>{const origin=selection?.origin||'home';selection=null;navigate(origin);if(origin==='media')selectForProject.focus();else document.getElementById('attachLibrary')?.focus();};
  selectionDone.onclick=()=>{if(!selection)return;const {draft,onConfirm}=selection;selection=null;onConfirm(draft.values());};
  selectionBar.append(selectionCount,selectionOnly,selectionCancel,selectionDone);
  byId('mediaBrowseBar').before(selectionBar);
  function startSelection(ids,onConfirm){selection={draft:createSelection(ids),only:false,onConfirm,origin:page};navigate('media');selectionDone.focus({preventScroll:true});}
  function toggleSelection(item){if(!selection)return;if(!selection.draft.toggle(item.id)){notice('Choose up to 100 files per project.');return;}notice('');render();byId('libraryGrid').querySelector(`[data-media-id="${item.id}"] .media-tile-open`)?.focus({preventScroll:true});}

  function el(tag, text, cls) { const node = document.createElement(tag); if(text != null) node.textContent=text; if(cls) node.className=cls; return node; }
  function notice(text) { byId('libraryNotice').textContent=text; }
  function databaseAction(mode, action) {
    return new Promise((resolve,reject) => {
      if(!database) return resolve([]);
      const tx=database.transaction('media',mode), request=action(tx.objectStore('media'));
      tx.oncomplete=()=>resolve(request?.result); tx.onerror=()=>reject(tx.error); tx.onabort=()=>reject(tx.error);
    });
  }
  async function save(item) {
    if(desktop){try{await desktopRequest('update',{id:item.id,favorite:!!item.favorite,description:item.description||'',title:item.title||''});}catch(error){notice(error.message);}return;}
    const {url,...record}=item;
    try { await databaseAction('readwrite',store=>store.put(record)); }
    catch { notice('Browser storage is full or unavailable. Keep this tab open; new files may not survive a refresh.'); }
  }
  function open(active, push=true) {
    if(desktop&&!active){active=true;page='home';}
    document.body.classList.toggle('library-mode',active);
    byId('mediaLibrary').hidden=!active;
    if(active) { document.body.classList.remove('studio-mode'); byId('results').hidden=true; byId('sourceVideo').pause(); byId('outputVideo').pause(); }
    if(!active) byId('mediaDetailDialog').close();
    if(push) history.pushState(null,'',active?(page==='media'?'#library':`#workspace/${page}`):'#');
    document.dispatchEvent(new Event('pixfun:viewchange'));
    window.scrollTo({top:0,behavior:'instant'});
    if(active) byId('libraryTitle').focus({preventScroll:true});
  }
  const initialization = new Promise(resolve=> {
    if(desktop){
      (async()=>{try{const result=await desktop.settings();skill=result.settings.skill||'';await refreshDesktop();}catch(error){notice(error.message);}finally{resolve();setInterval(refreshDesktop,1000);}})();
      return;
    }
    try {
      const request=indexedDB.open('pixfun-footage-library',1);
      request.onupgradeneeded=()=>request.result.createObjectStore('media',{keyPath:'id'});
      request.onerror=()=>{notice('Browser storage is unavailable. Keep this tab open while working.');resolve();};
      request.onsuccess=async()=>{
        database=request.result;
        try {
          const saved=await databaseAction('readonly',store=>store.getAll());
          for(const item of saved) { item.url=URL.createObjectURL(item.file); if(!['ready','error','cancelled'].includes(item.status)) {item.status='cancelled';item.error='Processing was interrupted. Retry to continue.';} items.push(item); }
          selected=null; render();
          for(const item of items.filter(i=>i.kind==='image'&&i.metadata)) {
            Object.assign(item.metadata,mediaInfo.readExif(await item.file.slice(0,262144).arrayBuffer()));
          }
          render();
        } catch { notice('Saved files could not be restored. You can import them again.'); }
        resolve();
      };
    } catch { notice('Browser storage is unavailable. Files will remain in this tab only.');resolve(); }
  });
  async function importFiles(files) {
    if(desktop){return importNative(false,files);}
    const chosen=Array.from(files || []); if(!chosen.length) return;
    page='media'; view='all';byId('librarySearch').value='';open(true); await initialization;
    const errors=[]; let added=0;
    for(const file of chosen.slice(0,100)) {
      const kind=kindOf(file);
      if(!kind) { errors.push(`${file.name}: unsupported file type`);continue; }
      if(file.size===0 || file.size>500*1024*1024) {errors.push(`${file.name}: file must be between 1 byte and 500 MB`);continue;}
      if(items.some(item=>item.file.name===file.name && item.file.size===file.size && item.file.lastModified===file.lastModified)) {errors.push(`${file.name}: already imported`);continue;}
      const item={id:crypto.randomUUID(),file,kind,url:URL.createObjectURL(file),status:'queued',metadata:null,result:null,error:null};
      items.push(item); added++; render(); await save(item);
    }
    if(chosen.length>100) errors.push('Only the first 100 files in this batch were considered. Import the rest in another batch.');
    notice(errors.length ? errors.slice(0,3).join(' · ')+(errors.length>3 ? ` · ${errors.length-3} more skipped files`:''):'');
    byId('fileInput').value=''; byId('folderInput').value='';
    render(); renderInspector(); if(added) processQueue();
  }
  async function desktopRequest(action,payload){
    const response=await fetch(`/api/desktop/${action}`,payload?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}:{});
    const result=await response.json();if(!response.ok||!result.ok)throw new Error(result.error||'Cannot reach the local service. Relaunch Pixfun to reconnect.');return result;
  }
  async function refreshDesktop(){
    if(desktopPolling)return;desktopPolling=true;
    try{
      const result=await desktopRequest('library'),snapshot=JSON.stringify(result.items);
      if(snapshot===desktopSnapshot)return;
      desktopSnapshot=snapshot;
      const before=items.find(i=>i.id===selected);
      items.splice(0,items.length,...result.items);
      running=items.some(isPending);render();
      document.dispatchEvent(new Event('pixfun:mediachange'));
      if(selected&&JSON.stringify(items.find(i=>i.id===selected))!==JSON.stringify(before)){
        const currentTime=byId('libraryInspector').querySelector('video')?.currentTime;
        renderInspector(currentTime);
      }
    }catch(error){notice(error.message);}finally{desktopPolling=false;}
  }
  async function importNative(folder=false,files,stayOnHome=false){
    await initialization;
    try{
      const result=files?await desktop.importFiles(Array.from(files)):await desktop.chooseFiles(folder);
      if(!result.items.length&&!result.errors.length)return;
      if(!stayOnHome){page='media';view='all';byId('librarySearch').value='';open(true);}
      notice(result.errors.slice(0,3).join(' · '));await refreshDesktop();
      return result;
    }catch(error){notice(error.message);}
  }
  function chooseImport(folder=false){if(desktop)return importNative(folder);byId(folder?'folderInput':'fileInput').click();}
  async function imageMetadata(item) {
    const metadata=await new Promise((resolve,reject)=> {
      const image=new Image(); const timeout=setTimeout(()=>{image.src='';reject(new Error('This image could not be decoded. Try JPEG, PNG, or WebP.'));},20000);
      image.onload=()=>{clearTimeout(timeout);resolve({width:image.naturalWidth,height:image.naturalHeight,size:item.file.size,format:item.file.type || item.file.name.split('.').pop()});};
      image.onerror=()=>{clearTimeout(timeout);reject(new Error('This browser cannot preview this image. Convert HEIC or RAW files to JPEG or PNG, then retry.'));}; image.src=item.url;
    });
    return {...metadata,...mediaInfo.readExif(await item.file.slice(0,262144).arrayBuffer())};
  }
  function analyzeVideo(item) {
    return new Promise((resolve,reject)=> {
      const xhr=new XMLHttpRequest(); activeRequest=xhr;
      xhr.open('POST','/api/import'); xhr.timeout=900000;
      xhr.upload.onprogress=event=>{if(event.lengthComputable && event.total>0){item.uploadPercent=Math.min(100,Math.round(event.loaded/event.total*100));updateTileProgress(item);}};
      xhr.upload.onload=()=>{item.status='analyzing';render();if(selected===item.id)renderInspector();announceImport(item);};
      xhr.onload=()=>{try {const result=JSON.parse(xhr.responseText);if(xhr.status<200 || xhr.status>=300 || !result.ok) throw new Error(result.error || 'Analysis failed.');resolve(result);} catch(error){reject(error instanceof SyntaxError ? new Error('The analysis service returned an invalid response. Please retry.') : error);}};
      xhr.onerror=()=>reject(new Error('Cannot reach the analysis service. Check that the local server is running, then retry.'));
      xhr.ontimeout=()=>reject(new Error('Analysis timed out. Try a shorter clip or retry.'));
      xhr.onabort=()=>reject(new Error('Processing stopped. Retry when you are ready.'));
      const data=new FormData();data.append('file',item.file);xhr.send(data);
    });
  }
  function progress() {
    byId('cancelImport').hidden=!running;
  }
  function announceImport(item) {
    byId('libraryImportStatus').textContent=`${item.file.name}: ${labels[item.status]}`;
  }
  function updateTileProgress(item) {
    // Update only the importing tile; do not rebuild previews on each upload event.
    const card=byId('libraryGrid').querySelector(`[data-media-id="${item.id}"]`);
    if(!card)return;
    const label=card.querySelector('.media-import-label'), bar=card.querySelector('.media-import-bar');
    if(label)label.textContent=importLabel(item);
    if(bar){bar.setAttribute('aria-valuenow',String(item.uploadPercent));bar.style.setProperty('--upload-progress',`${item.uploadPercent}%`);}
  }
  async function processQueue() {
    if(running) return; running=true;stopped=false; progress();
    let item;
    while(!stopped && (item=items.find(i=>i.status==='queued'))) {
      item.status=item.kind==='image'?'reading':'uploading';item.uploadPercent=null;item.error=null;render();if(selected===item.id)renderInspector();announceImport(item);
      try {
        if(item.kind==='image') item.metadata=await imageMetadata(item);
        else {item.result=await analyzeVideo(item);item.metadata=item.result.analysis.metadata;}
        item.status=stopped?'cancelled':'ready';
      } catch(error) {item.status=stopped?'cancelled':'error';item.error=error.message;}
      activeRequest=null;await save(item);render();if(selected===item.id)renderInspector();progress();announceImport(item);
    }
    running=false;progress();
    if(stopped)notice('Stopped waiting. Current server analysis may finish in the background.');
    if(items.some(i=>i.status==='queued'))processQueue();
  }
  function matches(item,segment) { return (!selection?.only||selection.draft.has(item.id)) && inCategory(item,view) && assets.matches(assets.normalize(item,segment),{},byId('librarySearch').value); }
  function captureBadge(card){
    if(!card.captureKey)return null;
    const badge=el('span',null,'shot-capture');badge.title=`Capture: ${card.captureLabel}`;
    const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('aria-hidden','true');
    for(const d of assets.capturePaths[card.captureKey]||[]){const path=document.createElementNS('http://www.w3.org/2000/svg','path');path.setAttribute('d',d);svg.append(path);}
    badge.append(svg,el('span',card.captureLabel));return badge;
  }
  function cover(item, segment) {
    const box=el('span',null,'media-cover'), thumbnail=segment||item.result?.analysis?.segments?.find(s=>s.thumbnailUrl);
    const metadata=item.metadata||item.result?.analysis?.metadata||{};
    const setRatio=(width,height)=>{if(width>0&&height>0&&Number.isFinite(width/height))box.style.setProperty('--media-ratio',`${width} / ${height}`);};
    setRatio(metadata.width,metadata.height);
    // Legacy thumbnails were cropped to 16:9. Use the original frame for other ratios.
    const legacyCrop=metadata.width&&metadata.height&&Math.abs(metadata.width/metadata.height-16/9)>.03;
    const src=thumbnail?.thumbnailFit==='native'||!legacyCrop?thumbnail?.thumbnailUrl:null;
    if(item.kind==='audio'){box.classList.add('audio-cover');box.append(el('span','♫','audio-cover-symbol'));}
    else if(item.kind==='image'||src) {const image=el('img');image.src=src||item.url;image.alt='';image.loading='lazy';image.addEventListener('load',()=>setRatio(image.naturalWidth,image.naturalHeight));box.append(image);}
    else if(item.status!=='error') {const video=el('video');video.src=item.url+`#t=${segment?.thumbnailTime||0.1}`;video.preload='metadata';video.muted=true;video.playsInline=true;video.addEventListener('loadedmetadata',()=>setRatio(video.videoWidth,video.videoHeight));box.append(video);}
    else box.append(el('span','Preview unavailable'));
    box.append(el('small',segment?`${duration(segment.start)}–${duration(segment.end)}`:item.kind==='image'?'PHOTO':item.metadata?.duration?duration(item.metadata.duration):item.kind==='audio'?'AUDIO':'VIDEO'));return box;
  }
  function select(item, seek) { selected=item.id;selectedSegment=seek??null;byId('mediaDetailDialog').showModal();renderInspector(seek); }
  function tile(item,segment,index) {
    const cardData=assets.buildAssetCard(assets.normalize(item,segment));
    const tile=el('article',null,'media-tile shot-card');tile.dataset.mediaId=item.id;
    const button=el('button',null,'media-tile-open');button.type='button';button.setAttribute('aria-haspopup','dialog');button.title=`${item.file.name}${segment?` · Segment ${index+1}`:''}`;
    const pending=isPending(item), preview=cover(item,segment);
    if(pending) {
      tile.classList.add('is-importing');
      const overlay=el('span',null,'media-import-overlay '+item.status);
      const spinner=el('span',null,'media-import-spinner');spinner.setAttribute('aria-hidden','true');
      overlay.append(spinner,el('span',importLabel(item),'media-import-label'));
      if(item.status==='uploading') {
        const bar=el('span',null,'media-import-bar');bar.setAttribute('role','progressbar');bar.setAttribute('aria-label',`Uploading ${item.file.name}`);bar.setAttribute('aria-valuemin','0');bar.setAttribute('aria-valuemax','100');
        if(Number.isFinite(item.uploadPercent)){bar.setAttribute('aria-valuenow',String(item.uploadPercent));bar.style.setProperty('--upload-progress',`${item.uploadPercent}%`);}
        overlay.append(bar);
      }
      preview.append(overlay);
    }
    if(!pending){const badge=captureBadge(cardData);if(badge)preview.append(badge);if(cardData.primaryRole)preview.append(el('span',cardData.primaryRole,'shot-role'));preview.append(el('span','Preview','shot-preview-hint'));}
    const caption=el('span',null,'media-caption');caption.append(el('strong',cardData.title,'shot-title'));
    if(cardData.summary)caption.append(el('span',cardData.summary,'shot-summary'));
    if(cardData.discoveryTags.length){const tags=el('span',null,'shot-discovery-tags');cardData.discoveryTags.forEach(tag=>{const label=el('span',tag);label.title=tag;tags.append(label);});caption.append(tags);}
    if(cardData.tags.length){const tags=el('span',null,'shot-edit-tags');cardData.tags.forEach(tag=>tags.append(el('span',tag,tag==='Highlight'?'shot-highlight':'')));caption.append(tags);}
    if(cardData.status.length)caption.append(el('span',cardData.status.join(' · '),'shot-technical'));
    if(cardData.warning)caption.append(el('span',cardData.warning,'shot-quality-warning'));
    if(['error','cancelled'].includes(item.status))caption.append(el('span',labels[item.status],'media-state '+item.status));
    button.append(preview,caption);button.onclick=()=>selection?toggleSelection(item):select(item,segment?.start);tile.append(button);
    if(selection){
      const picked=selection.draft.has(item.id);tile.classList.add('is-selectable');if(picked)tile.classList.add('is-picked');
      button.removeAttribute('aria-haspopup');button.setAttribute('aria-pressed',String(picked));button.setAttribute('aria-label',`Select ${item.file.name}`);
      const check=el('span',picked?'✓':'','media-pick-check');check.setAttribute('aria-hidden','true');preview.append(check);
      const hint=preview.querySelector('.shot-preview-hint');if(hint)hint.textContent=picked?'Deselect':'Select';
      const inspect=el('button','Preview','media-pick-preview');inspect.type='button';inspect.setAttribute('aria-label',`Preview ${item.file.name}`);inspect.onclick=()=>select(item);tile.append(inspect);
      return tile;
    }
    const favorite=el('button',null,'shot-favorite');favorite.type='button';favorite.title=item.favorite?'Remove from favorites':'Add to favorites';favorite.setAttribute('aria-label',`${favorite.title}: ${item.file.name}`);favorite.setAttribute('aria-pressed',String(!!item.favorite));
    const star=document.createElementNS('http://www.w3.org/2000/svg','svg');star.setAttribute('viewBox','0 0 24 24');star.setAttribute('aria-hidden','true');
    const starPath=document.createElementNS('http://www.w3.org/2000/svg','path');starPath.setAttribute('d','m12 3 2.8 5.7 6.3.9-4.6 4.5 1.1 6.3-5.6-3-5.6 3 1.1-6.3L2.9 9.6l6.3-.9L12 3Z');star.append(starPath);favorite.append(star);
    favorite.onclick=async()=>{item.favorite=!item.favorite;await save(item);render();byId('libraryGrid').querySelector(`[data-media-id="${item.id}"] .shot-favorite`)?.focus();};tile.append(favorite);
    return tile;
  }
  function render() {
    selectionBar.hidden=!selection||page!=='media';
    selectForProject.hidden=!!selection;
    if(selection){selectionCount.textContent=`${selection.draft.values().length} selected`;selectionOnly.setAttribute('aria-pressed',String(selection.only));}
    byId('mediaImportActions').hidden=page!=='media'||!!selection;byId('librarySummary').hidden=page!=='media';
    byId('workspaceHome').hidden=page!=='home';byId('workspaceSkills').hidden=page!=='skills';byId('mediaViews').hidden=page!=='media';
    if(byId('workspaceHistory'))byId('workspaceHistory').hidden=page!=='history';
    document.querySelector('.library-heading').hidden=page==='home';
    byId('mediaBrowseBar').hidden=page!=='media';

    document.querySelector('.library-toolbar').hidden=page!=='media';document.querySelector('.library-layout').hidden=page!=='media';
    document.querySelectorAll('[data-workspace-page]').forEach(button=>{button.removeAttribute('aria-current');if(button.dataset.workspacePage===page)button.setAttribute('aria-current','page');});
    document.querySelectorAll('[data-library-view]').forEach(button=>{button.removeAttribute('aria-current');if(button.dataset.libraryView===view)button.setAttribute('aria-current','page');});
    document.querySelectorAll('[data-skill]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.skill===skill)));
    byId('allCount').textContent=items.length;
    document.querySelectorAll('[data-home-skill]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.homeSkill===skill)));
    const homeGrid=byId('homeMediaGrid');homeGrid?.replaceChildren();
    for(const item of homeGrid?items.slice(-4):[]) {
      const button=el('button',null,'home-media-card');button.type='button';button.setAttribute('aria-haspopup','dialog');button.append(cover(item),el('strong',item.file.name));button.onclick=()=>select(item);homeGrid.append(button);
    }
    if(byId('homeMediaEmpty'))byId('homeMediaEmpty').hidden=items.length>0;
    if(items.length){byId('resumeStudio').hidden=false;byId('resumeStudio').textContent='Open workspace';}
    byId('libraryTitle').textContent=page==='home'?'Home':page==='history'?'Project':page==='skills'?'Skills':'Media';
    const total=items.filter(i=>i.kind==='video').reduce((sum,i)=>sum+(i.metadata?.duration||0),0);
    const countLabel=(count,name)=>`${count} ${name}${count===1?'':'s'}`;
    byId('librarySummary').textContent=items.length?`${countLabel(items.length,'file')} · ${countLabel(items.filter(i=>i.kind==='video').length,'video')} · ${countLabel(items.filter(i=>i.kind==='image').length,'photo')}${items.some(i=>i.kind==='audio')?' · '+items.filter(i=>i.kind==='audio').length+' audio':''}${total?' · '+duration(total)+' of video':''}`:'Import videos, photos, or audio to start your library.';
    const grid=byId('libraryGrid');grid.replaceChildren();
    for(const item of items)if(matches(item))grid.append(tile(item));
    byId('libraryEmpty').hidden=grid.children.length>0;
    const empty=byId('libraryEmpty'),searching=!!byId('librarySearch').value.trim();
    empty.querySelector('h2').textContent=selection?.only?'No selected media in this view.':searching?'No matching media.':view==='favorites'?'No favorites yet.':!items.length?'Bring every angle of your trip.':view==='image'?'No photos yet.':view==='audio'?'No audio yet.':'No videos yet.';
    empty.querySelector('p').textContent=searching?'Try another filename, device, place, or description.':view==='favorites'?'Star any media file to find it here.':'Import videos, photos, or audio, or drop them here.';
    byId('emptyImport').hidden=view==='favorites'||searching;
    empty.querySelector('small').hidden=view==='favorites'||searching;
    progress();
  }
  function sceneTimeline(item,preview){
    return window.PixfunScenes.mount({analysis:item.result?.analysis||{},preview,notes:item.sceneNotes||{},title:item.result?.analysis.segmentationMethod==='time-sampled'?'Browse video':'Scenes'});
  }
  function renderInspector(seek) {
    if(!byId('mediaDetailDialog').open)return;
    const box=byId('libraryInspector');box.querySelectorAll('video,audio').forEach(video=>video._disposeScenes?.());box.replaceChildren();const item=items.find(i=>i.id===selected);
    if(!item)return;
    const segment=selectedSegment==null?null:item.result?.analysis.segments?.find(s=>s.start===selectedSegment);
    const asset=assets.normalize(item,segment),card=assets.buildAssetCard(asset);
    byId('mediaDetailTitle').textContent=asset.title;
    byId('mediaDetailTitle').title=asset.title;
    const preview=el(item.kind==='image'?'img':item.kind==='audio'?'audio':'video');preview.src=item.url;
    if(item.kind!=='image'){
      preview.controls=true;preview.playsInline=true;preview.preload='metadata';preview.poster=item.result?.analysis.segments?.find(s=>s.thumbnailUrl)?.thumbnailUrl||'';
      const start=seek??selectedSegment;if(start!=null)preview.addEventListener('loadedmetadata',()=>{preview.currentTime=start;},{once:true});
    }else preview.alt=card.title;
    const previewColumn=el('div',null,'media-detail-preview');previewColumn.append(preview);if(item.kind==='video')previewColumn.append(sceneTimeline(item,preview));box.append(previewColumn);
    const info=el('div',null,'media-detail-info');info.tabIndex=0;info.setAttribute('role','region');info.setAttribute('aria-label','Media information');box.append(info);
    function section(title,values,parent=info){
      const entries=values.filter(([,v])=>v!==null&&v!==undefined&&v!=='');if(!entries.length)return;
      const group=el('section',null,'asset-detail-section');group.append(el('h3',title));const dl=el('dl');entries.forEach(([k,v])=>dl.append(el('dt',k),el('dd',String(v))));group.append(dl);parent.append(group);
    }
    const insights=assets.detailSections(asset),overview=assets.editingOverview(item,segment),understanding=el('section',null,'asset-detail-section asset-understanding');
    understanding.append(el('h3',item.kind==='image'?'Image description':'Video description'));
    if(overview.summary)understanding.append(el('p',overview.summary,'asset-summary'));
    if(overview.rows.length){const list=el('dl',null,'asset-overview-facts');for(const [label,value]of overview.rows)list.append(el('dt',label),el('dd',value));understanding.append(list);}
    if(overview.fullSummary&&overview.fullSummary.replace(/\s+/g,' ').trim()!==overview.summary){const full=el('details',null,'asset-full-summary');full.append(el('summary','Full description'),el('p',overview.fullSummary,'asset-summary'));understanding.append(full);}
    if(!overview.hasVisualContent)understanding.append(el('p',isPending(item)?'Reading this file…':'No visual description yet.','asset-analysis-notice'));
    if(overview.moments.length){
      const moments=el('div',null,'asset-content-moments');moments.append(el('h4',overview.momentLabel));
      for(const moment of overview.moments){const button=el('button',null,'asset-content-moment');button.type='button';const copy=el('span');if(moment.title)copy.append(el('strong',moment.title));if(moment.text)copy.append(el('span',moment.text));button.append(el('time',duration(moment.start)),copy);button.setAttribute('aria-label',`Jump to ${duration(moment.start)}: ${moment.title||moment.text}`);button.title=moment.source;button.onclick=()=>{const jump=()=>preview.currentTime=moment.start;if(preview.readyState>=1)jump();else preview.addEventListener('loadedmetadata',jump,{once:true});previewColumn.scrollIntoView?.({block:'nearest',behavior:'instant'});};moments.append(button);}
      understanding.append(moments);
    }
    info.append(understanding);
    if(insights.tags.length){
      const tags=el('section',null,'asset-detail-section asset-search-section');tags.append(el('h3','Tags'));
      for(const [label,values]of insights.tags){
        const row=el('div',null,'asset-tag-group');row.append(el('h4',label));const list=el('div',null,'asset-search-tags');
        for(const value of values){const button=el('button',value,'asset-search-tag');button.type='button';button.title=label==='Location'?`Search Media for this location: ${value}`:`Search Media for: ${value}`;button.setAttribute('aria-label',button.title);
          const icon=el('span',null,'asset-tag-search-icon');icon.setAttribute('aria-hidden','true');button.append(icon);
          button.onclick=()=>{byId('mediaDetailDialog').close();view='all';byId('librarySearch').value=value;render();byId('librarySearch').focus();};list.append(button);}
        row.append(list);tags.append(row);
      }info.append(tags);
    }
    section('Editing notes',[...insights.editing,...overview.editingNotes]);
    if(insights.cautions.length){const checks=el('section',null,'asset-detail-section asset-edit-checks');checks.append(el('h3','Check before use'));const list=el('ul');for(const issue of insights.cautions)list.append(el('li',issue));checks.append(list);info.append(checks);}
    if(item.kind!=='image')section('Sound',[
      ['Audio track',asset.hasAudio===null?null:asset.hasAudio?'Present':'Silent'],
      ['Speech',asset.audio.hasSpeech===null?null:asset.audio.hasSpeech?'Detected':'Not detected'],
      ['Ambience',asset.audio.ambientTypes.join(' · ')|| (asset.audio.hasUsefulAmbientSound===true?'Useful ambient sound':null)]
    ]);
    if(asset.subtitleCues.length||asset.audio.speechText){
      const transcript=el('section',null,'asset-detail-section');transcript.append(el('h3','Transcript'));info.append(transcript);
      if(asset.subtitleCues.length){
        for(const cue of asset.subtitleCues){const row=el('button',null,'asset-transcript-row');row.type='button';row.append(el('time',duration(cue.start)),el('span',cue.text));row.onclick=()=>{if(preview.readyState>=1)preview.currentTime=cue.start;else preview.addEventListener('loadedmetadata',()=>preview.currentTime=cue.start,{once:true});};transcript.append(row);}
      }else transcript.append(el('p',asset.audio.speechText));
    }
    const meta=item.metadata||{};
    const fileDetails=el('details',null,'asset-file-details');fileDetails.append(el('summary','File details'));info.append(fileDetails);
    section('Original file',[
      ['Filename',item.file.name],['Type',item.kind==='image'?'Photo':item.kind==='audio'?'Audio':'Video'],['Size',size(item.file.size)],
      ['Resolution',meta.width&&meta.height?`${meta.width} × ${meta.height}`:null],['Duration',item.kind!=='image'?duration(meta.duration):null],
      ['Frame rate',meta.fps?`${meta.fps} fps`:null],['Shot on',mediaInfo.dateText(meta.capturedAt)],
      ['Media created',mediaInfo.dateText(meta.mediaCreatedAt)],['Date source',meta.dateSource],
      ['Segments',item.kind==='video'&&item.status==='ready'?item.result?.analysis.segments?.length:null]
    ],fileDetails);
    if(item.error)info.append(el('p',item.error,'shot-quality-warning'));
    if(desktop){
      section('Source',[['Credit',item.context?.credit],['License',item.context?.license]],fileDetails);
      if(item.context?.source){try{const url=new URL(item.context.source);if(url.protocol==='https:'||url.protocol==='http:'){const source=el('a','View source','asset-source-link');source.href=url.href;source.target='_blank';source.rel='noopener noreferrer';fileDetails.append(source);}}catch{}}
      const reveal=el('button',item.missing?'Locate original file…':'Show in Finder','text-button');reveal.type='button';reveal.onclick=async()=>{try{if(item.missing){await desktop.locate(item.id);await refreshDesktop();}else await desktop.reveal(item.id);}catch(error){notice(error.message);}};(item.missing?info:fileDetails).append(reveal);
    }
    if(['error','cancelled'].includes(item.status)&&!item.missing){const retry=el('button','Retry analysis','button secondary');retry.type='button';retry.onclick=async()=>{if(desktop){try{await desktopRequest('retry',{id:item.id});await refreshDesktop();}catch(error){notice(error.message);}return;}item.status='queued';item.error=null;render();renderInspector();processQueue();};info.append(retry);}
    if(['ready','error','cancelled'].includes(item.status)){
      const remove=el('button','Remove from library','media-remove-link');remove.type='button';remove.onclick=async()=>{
        if(desktop){try{await desktopRequest('remove',{id:item.id});byId('mediaDetailDialog').close();await refreshDesktop();notice('Removed from the library. Original file unchanged. ');const undo=el('button','Undo','text-button');undo.type='button';undo.onclick=async()=>{try{await desktopRequest('restore',{id:item.id});await refreshDesktop();notice('');}catch(error){notice(error.message);}};byId('libraryNotice').append(undo);}catch(error){notice(error.message);}return;}
        try{await databaseAction('readwrite',store=>store.delete(item.id));byId('mediaDetailDialog').close();items.splice(items.indexOf(item),1);URL.revokeObjectURL(item.url);render();byId('libraryTitle').focus();notice('Removed from this browser library. Your original file is unchanged.');}
        catch{notice('Could not remove this item from browser storage. Please retry.');}
      };info.append(remove);
    }
  }
  byId('mediaDetailDialog').addEventListener('close',()=>{byId('libraryInspector').querySelectorAll('video,audio').forEach(video=>{video.pause();video._disposeScenes?.();});byId('libraryInspector').replaceChildren();selected=null;selectedSegment=null;});
  window.PixfunMasonry?.mount(byId('libraryGrid'));
  byId('mediaDetailDialog').addEventListener('click',event=>{if(event.target!==byId('mediaDetailDialog'))return;const rect=event.target.getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)event.target.close();});
  ['homeImport','tutorialImport'].forEach(id=>byId(id).onclick=()=>chooseImport());
  document.querySelectorAll('[data-tutorial-page]').forEach(button=>button.onclick=()=>navigate(button.dataset.tutorialPage));
  document.querySelectorAll('[data-showcase]').forEach(button=>button.onclick=()=>{byId('showcaseDialogTitle').textContent=button.dataset.showcaseTitle;byId('showcaseVideo').src=`/assets/media/travel/hero-${button.dataset.showcase}.mp4`;byId('showcaseDialog').showModal();byId('showcaseVideo').play().catch(()=>{});});
  byId('showcaseDialog').addEventListener('close',()=>{byId('showcaseVideo').pause();byId('showcaseVideo').removeAttribute('src');byId('showcaseVideo').load();});
  ['libraryImport','emptyImport'].forEach(id=>byId(id).onclick=()=>chooseImport());
  byId('importFolder').onclick=()=>chooseImport(true);
  byId('folderInput').onchange=event=>importFiles(event.target.files);
  byId('librarySearch').oninput=render;
  document.querySelectorAll('[data-library-view]').forEach(button=>button.onclick=()=>{view=button.dataset.libraryView;render();});
  document.addEventListener('pixfun:category',event=>{if(['all','video','image','audio','favorites'].includes(event.detail)){view=event.detail;render();}});
  function navigate(next) {if(next!=='media')selection=null;page=next;notice('');history.replaceState(null,'',page==='media'?'#library':`#workspace/${page}`);view='all';byId('librarySearch').value='';byId('mediaDetailDialog').close();render();byId('libraryTitle').focus({preventScroll:true});window.scrollTo({top:0,behavior:'instant'});document.dispatchEvent(new CustomEvent('pixfun:workspacepage',{detail:page}));}
  document.querySelectorAll('[data-workspace-page]').forEach(button=>button.onclick=()=>navigate(button.dataset.workspacePage));
  document.querySelectorAll('[data-home-skill]').forEach(button=>button.onclick=()=>{navigate('skills');const target=Array.from(document.querySelectorAll('[data-skill]')).find(card=>card.dataset.skill===button.dataset.homeSkill);target?.scrollIntoView({block:'center',behavior:'instant'});});
  byId('homeSkills').onclick=()=>navigate('skills');
  document.querySelectorAll('[data-skill]').forEach(button=>button.onclick=async()=>{skill=button.dataset.skill;try{if(desktop)await desktopRequest('settings',{key:'skill',value:skill});else localStorage.setItem('pixfun-creative-skill',skill);byId('skillStatus').textContent=`${skill} selected. Your creative preference is saved.`;}catch{byId('skillStatus').textContent=`${skill} selected for this session. Storage is unavailable.`;}render();});
  byId('cancelImport').onclick=async()=>{if(desktop){try{await desktopRequest('stop',{});await refreshDesktop();}catch(error){notice(error.message);}return;}stopped=true;activeRequest?.abort();items.filter(i=>i.status==='queued').forEach(i=>{i.status='cancelled';save(i);});render();};
  document.querySelectorAll('.library-sidebar a').forEach(link=>link.onclick=event=>{event.preventDefault();if(desktop)navigate('home');else open(false);});
  byId('mediaLibrary').addEventListener('dragover',event=>event.preventDefault());
  byId('mediaLibrary').addEventListener('drop',event=>{event.preventDefault();if(page==='home'&&window.PixfunWorkspace)window.PixfunWorkspace.attach(false,event.dataTransfer.files);else importFiles(event.dataTransfer.files);});
  function restoreRoute() {let hash=location.hash;const routes=['#library','#workspace/home','#workspace/skills','#workspace/history'];if(desktop&&!routes.includes(hash)){hash='#workspace/home';history.replaceState(null,'',hash);}const active=routes.includes(hash);if(active){page=hash==='#library'?'media':hash.split('/')[1];if(page!=='media')selection=null;render();}open(active,false);document.dispatchEvent(new CustomEvent('pixfun:workspacepage',{detail:page}));}
  window.addEventListener('hashchange',restoreRoute);
  window.PixfunLibrary={importFiles,open,importNative,navigate,startSelection,createCover:cover,openMedia:id=>{const item=items.find(item=>item.id===id);if(item){navigate('media');select(item);}},getItems:()=>items.slice(),get page(){return page;},get hasFiles(){return items.length>0;}};
  initialization.then(restoreRoute);
})();
