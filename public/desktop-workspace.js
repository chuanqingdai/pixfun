(() => {
  'use strict';
  if(!window.PixfunDesktop)return;
  const $=id=>document.getElementById(id),library=window.PixfunLibrary;
  const node=(tag,text,cls)=>{const e=document.createElement(tag);if(text)e.textContent=text;if(cls)e.className=cls;return e;};
  const historyButton=node('button','Project');historyButton.type='button';historyButton.dataset.workspacePage='history';historyButton.onclick=()=>library.navigate('history');document.querySelector('.library-sidebar nav').append(historyButton);
  const home=$('workspaceHome');
  home.innerHTML=`<div class="creator-home">
    <header class="creator-intro"><span class="creator-mark" aria-hidden="true">✦</span><h1>What will you create?</h1></header>
    <div id="projectThread" class="project-thread"></div>
    <form id="projectComposer" class="project-composer">
      <div id="projectSkill" class="project-skill" hidden></div>
      <div id="projectAttachments" class="project-attachments"></div>
      <label class="sr-only" for="projectPrompt">Describe your video requirements</label>
      <textarea id="projectPrompt" maxlength="5000" rows="4" placeholder="Describe your story, length, and style…" required></textarea>
      <div class="composer-actions"><div><button type="button" id="attachFolder"><span aria-hidden="true">＋</span> Folder</button><button type="button" id="attachFiles">Files & audio</button><button type="button" id="attachLibrary">From Media</button></div><button type="submit" id="saveProject" aria-label="Create project" title="Create project"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M12 19V5m-6 6 6-6 6 6"/></svg></button></div>
    </form>
    <div class="composer-meta"><span id="projectStatus" role="status"></span><button id="newProject" type="button" class="text-button" hidden>New project</button></div>
    <span id="projectSaveAnnouncement" class="sr-only" role="status"></span>
  </div>`;
  const history=node('section',null,'project-history');history.id='workspaceHistory';history.hidden=true;history.innerHTML='<p class="history-description">Pick up where you left off.</p><div id="projectList"></div><p id="historyStatus" role="status"></p>';home.after(history);
  let project=null,attachments=[],activeSkill=null,busy=false,draftDirty=false,saveTimer,saveQueue=Promise.resolve();
  // The service origin changes on each launch; keep drafts in SQLite, not origin-scoped storage.
  const stash=()=>{draftDirty=true;clearTimeout(saveTimer);const value=JSON.stringify({prompt:$('projectPrompt').value,attachments,projectId:project?.id,skill:activeSkill});saveTimer=setTimeout(()=>{saveQueue=saveQueue.catch(()=>{}).then(async()=>{const r=await fetch('/api/desktop/settings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({key:'projectDraft',value})});if(!r.ok)status('Draft could not be saved. Keep this window open.');}).catch(()=>status('Draft could not be saved. Keep this window open.'));},250);};
  const status=text=>$('projectStatus').textContent=text;
  const validSkill=skill=>skill&&typeof skill.id==='string'&&typeof skill.title==='string'&&typeof skill.strategy==='string'&&skill.id.length<=80&&skill.title.length<=80&&skill.strategy.length<=4000;
  function renderSkill(){const target=$('projectSkill');target.replaceChildren();target.hidden=!activeSkill;if(!activeSkill)return;const label=node('span',activeSkill.title),remove=node('button','×');label.title='Creator skill';remove.type='button';remove.setAttribute('aria-label',`Remove ${activeSkill.title} skill`);remove.onclick=()=>{activeSkill=null;renderSkill();stash();$('projectPrompt').focus();};target.append(node('small','Skill'),label,remove);}
  async function request(payload){const r=await fetch('/api/desktop/projects',payload?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}:{});const data=await r.json();if(!r.ok||!data.ok)throw Error(data.error||'Could not save your project. Try again.');return data;}
  function removeAttachment(id){
    if(busy)return;
    const index=attachments.findIndex(a=>a.id===id);if(index<0)return;
    const name=attachments[index].name,scroll=$('projectAttachments').querySelector('.attachment-covers')?.scrollLeft||0;
    attachments=attachments.filter(a=>a.id!==id);renderAttachments();stash();
    $('projectSaveAnnouncement').textContent=`${name} removed from this prompt.`;
    const strip=$('projectAttachments').querySelector('.attachment-covers');if(strip)strip.scrollLeft=scroll;
    const buttons=$('projectAttachments').querySelectorAll('.attachment-remove');
    (buttons[Math.min(index,buttons.length-1)]||$('projectPrompt')).focus({preventScroll:true});
  }
  function renderAttachments(){
    const list=$('projectAttachments'),items=library.getItems();list.replaceChildren();
    if(!attachments.length)return;
    const group=node('div',null,'project-media-stack');group.setAttribute('role','group');group.setAttribute('aria-label','Attached media');
    const stack=node('div',null,'attachment-covers');
    for(const a of attachments){
      const tile=node('div',null,'attachment-tile');tile.title=a.name;
      const item=items.find(i=>i.id===a.id),frame=item?library.createCover(item):node('span','◇','media-cover');frame.setAttribute('aria-hidden','true');
      const remove=node('button',null,'attachment-remove');remove.type='button';remove.setAttribute('aria-label',`Remove ${a.name} from prompt`);remove.title=`Remove ${a.name} from prompt`;
      remove.innerHTML='<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><path d="m4 4 8 8m0-8-8 8"/></svg>';
      remove.onclick=()=>removeAttachment(a.id);tile.append(frame,remove);stack.append(tile);
    }
    const button=node('button',null,'attachment-edit');button.type='button';button.setAttribute('aria-label',`Edit selection: ${attachments.length} files`);button.onclick=chooseMedia;
    const copy=node('span',null,'attachment-summary');copy.append(node('strong',`${attachments.length} file${attachments.length===1?'':'s'}`),node('span','Edit selection'));
    button.append(copy,node('span','›','attachment-chevron'));group.append(stack,button);list.append(group);
  }
  async function attach(folder=false,files){
    if(busy)return;const result=await library.importNative(folder,files,true);if(!result)return;
    for(const item of result.items)if(!attachments.some(a=>a.id===item.id)&&attachments.length<100)attachments.push({id:item.id,name:item.file.name,kind:item.kind});
    renderAttachments();stash();status(result.errors.length?result.errors.slice(0,2).join(' · '):`${result.items.length} file${result.items.length===1?'':'s'} attached`);
  }
  function renderThread(){
    const thread=$('projectThread');thread.replaceChildren();
    if(project){const saved=node('details',null,'project-saved');saved.append(node('summary','Saved brief'));thread.append(saved);
      project.messages.forEach(m=>{const article=node('article');if(m.skill?.title)article.append(node('span',`Skill · ${m.skill.title}`,'project-message-skill'));article.append(node('p',m.text));if(m.attachments.length)article.append(node('small',`${m.attachments.length} attached files`));saved.append(article);});
    }
    $('newProject').hidden=!project;$('saveProject').setAttribute('aria-label',project?'Save request':'Save brief');$('saveProject').title='Save a project brief. Automatic video generation is not connected yet.';
  }
  async function loadHistory(){
    const list=$('projectList');$('historyStatus').textContent='Loading projects…';
    try{const projects=(await request()).projects;list.replaceChildren();
      projects.forEach(p=>{const button=node('button',null,'project-row');button.type='button';const copy=node('span');copy.append(node('strong',p.title),node('small',`${p.attachments.length} files · ${new Date(p.updatedAt).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'})}`));button.append(copy,node('span','Draft ↗','project-row-state'));button.onclick=()=>{
        if($('projectPrompt').value.trim()&&!confirm('Replace the unsaved request with this project?'))return;
        project=p;attachments=p.attachments.slice();activeSkill=validSkill(p.skill)?p.skill:null;$('projectPrompt').value='';renderSkill();renderThread();renderAttachments();stash();status('');library.navigate('home');
      };list.append(button);});$('historyStatus').textContent=projects.length?'':'No projects yet. Start a brief in Home.';
    }catch(error){$('historyStatus').textContent=error.message;}
  }
  $('attachFolder').onclick=()=>attach(true);$('attachFiles').onclick=()=>attach();
  function chooseMedia(){
    if(busy)return;
    library.startSelection(attachments.map(a=>a.id),ids=>{
      const items=library.getItems();
      attachments=ids.map(id=>{const item=items.find(i=>i.id===id);return item?{id:item.id,name:item.file.name,kind:item.kind}:attachments.find(a=>a.id===id);}).filter(Boolean);
      renderAttachments();stash();status('');library.navigate('home');$('projectPrompt').focus({preventScroll:true});
    });
  }
  $('attachLibrary').onclick=chooseMedia;
  $('projectPrompt').oninput=stash;
  $('projectComposer').onsubmit=async event=>{
    event.preventDefault();const prompt=$('projectPrompt').value.trim();if(!prompt||busy)return;
    busy=true;$('saveProject').disabled=true;$('projectPrompt').readOnly=true;status('Saving…');$('projectSaveAnnouncement').textContent='';
    try{project=(await request({id:project?.id,prompt,mediaIds:attachments.map(a=>a.id),skill:activeSkill})).project;$('projectPrompt').value='';stash();renderThread();status('');$('projectSaveAnnouncement').textContent='Brief saved.';}
    catch(error){status(error.message);}finally{busy=false;$('saveProject').disabled=false;$('projectPrompt').readOnly=false;}
  };
  $('newProject').onclick=()=>{if($('projectPrompt').value.trim()&&!confirm('Discard the unsaved request and start a new project?'))return;project=null;attachments=[];activeSkill=null;$('projectPrompt').value='';renderSkill();renderThread();renderAttachments();stash();status('');$('projectPrompt').focus();};
  document.addEventListener('pixfun:mediachange',renderAttachments);document.addEventListener('pixfun:workspacepage',event=>{if(event.detail==='history')loadHistory();});
  // Selecting a skill attaches its strategy to the composer, never submits a project.
  function useSkill(skill){if(!validSkill(skill))return;if(busy){library.navigate('home');status('Finish saving the current request before changing skills.');return;}activeSkill={id:skill.id,title:skill.title,strategy:skill.strategy,...(typeof skill.applicability==='string'?{applicability:skill.applicability.slice(0,400)}:{})};renderSkill();stash();library.navigate('home');status('');$('projectPrompt').focus();}
  window.PixfunWorkspace={attach,useSkill,chooseMedia};renderThread();renderAttachments();renderSkill();
  window.PixfunDesktop.settings().then(async result=>{
    const draft=JSON.parse(result.settings.projectDraft||'null');if(!draft||draftDirty)return;
    const restoredProject=draft.projectId?(await request()).projects.find(p=>p.id===draft.projectId):null;if(draftDirty)return;
    project=restoredProject||null;activeSkill=validSkill(draft.skill)?draft.skill:null;renderSkill();$('projectPrompt').value=typeof draft.prompt==='string'?draft.prompt:'';
    attachments=Array.isArray(draft.attachments)?draft.attachments.filter(x=>x&&typeof x.id==='string'&&typeof x.name==='string').slice(0,100):[];renderThread();renderAttachments();
  }).catch(()=>status('Could not restore your draft. Saved projects are in Project.'));
})();
