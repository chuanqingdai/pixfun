/* Shared, evidence-based scene navigation for web reports and the Mac library. */
(() => {
  'use strict';
  const clean=value=>typeof value==='string'?value.trim():'';
  const time=value=>{const n=Math.max(0,Number(value)||0);return `${Math.floor(n/60)}:${String(Math.floor(n%60)).padStart(2,'0')}`;};
  function describe(segment,index,analysis={},notes={}){
    const content=segment.assetUnderstanding||analysis.sceneUnderstanding?.[segment.id]||{};
    const note=notes[segment.id]||{};
    const environment=Array.isArray(content.scene)?content.scene.map(clean).filter(Boolean):[];
    const summary=clean(note.description)||clean(content.summary);
    const title=clean(note.title)||clean(content.title)||environment.slice(0,2).join(' · ')||`Segment ${index+1}`;
    let method=segment.boundary?.type;
    if(Number(segment.start)===0)method='video_start';
    if(!method){
      if(analysis.segmentationMethod==='time-sampled')method='time_split';
      else if(Array.isArray(analysis.cuts))method=analysis.cuts.some(cut=>Math.abs(cut-segment.start)<=.015)?'detected_cut':'time_split';
    }
    const reasons={
      video_start:['Video start','The beginning of this video.'],
      detected_cut:['Detected cut','A visual change was detected at the start of this segment.'],
      time_split:['Time-based split','A longer span was divided for navigation; this is not a confirmed scene change.'],
      scene_change:['Scene change',clean(segment.boundary?.reason)||'A content transition was recorded at this boundary.'],
    };
    const [boundary,reason]=reasons[method]||['Unrecorded boundary','This earlier analysis did not record the reason for this split.'];
    const cutCount=Number.isInteger(segment.containedCutCount)?segment.containedCutCount:Array.isArray(analysis.cuts)?analysis.cuts.filter(c=>c>segment.start+.015&&c<segment.end-.015).length:0;
    return {title,summary,boundary,reason,range:`${time(segment.start)}–${time(segment.end)}`,cutCount,edited:!!(clean(note.title)||clean(note.description))};
  }
  function activeIndex(segments,now){return segments.findIndex((s,i)=>now>=s.start&&(now<s.end||i===segments.length-1&&now===s.end));}
  function mount({analysis={},preview,notes={},onSave,title='Scenes'}){
    const node=(tag,text,cls)=>{const e=document.createElement(tag);if(text!=null)e.textContent=text;if(cls)e.className=cls;return e;};
    const segments=(analysis.segments||[]).filter(s=>Number.isFinite(s.start)&&Number.isFinite(s.end)&&s.start>=0&&s.end>s.start);
    const group=node('section',null,'scene-browser');group.setAttribute('aria-label','Scene navigation');
    const heading=node('div',null,'scene-browser-heading');heading.append(node('h2',title),node('span',`${segments.length} segments · Select to jump`));group.append(heading);
    if(!segments.length){group.append(node('p','No scene segments available.'));return group;}
    const strip=node('div',null,'scene-browser-strip'),detail=node('div',null,'scene-browser-detail');
    const navigation=node('div',null,'scene-strip-navigation'),previous=node('button','‹'),next=node('button','›');
    previous.type=next.type='button';previous.setAttribute('aria-label','Previous segments');next.setAttribute('aria-label','Next segments');
    navigation.append(previous,next);heading.append(navigation);
    const updateNavigation=()=>{const max=Math.max(0,strip.scrollWidth-strip.clientWidth);navigation.hidden=max<=1;previous.disabled=strip.scrollLeft<=1;next.disabled=strip.scrollLeft>=max-1;};
    const move=direction=>{const max=Math.max(0,strip.scrollWidth-strip.clientWidth),left=Math.max(0,Math.min(max,strip.scrollLeft+direction*Math.max(100,strip.clientWidth*.8)));strip.scrollTo({left,behavior:typeof matchMedia==='function'&&matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});};
    previous.onclick=()=>move(-1);next.onclick=()=>move(1);strip.addEventListener('scroll',updateNavigation,{passive:true});
    const detailTop=node('div',null,'scene-detail-top'),detailTitle=node('strong'),boundary=node('span',null,'scene-boundary'),description=node('p'),reason=node('p',null,'scene-boundary-reason');
    detailTop.append(detailTitle,boundary);detail.append(detailTop,description,reason);group.append(strip,detail);
    const entries=[];let selected=-1,editing=false;
    function paintCard(entry){const info=describe(entry.segment,entry.index,analysis,notes);entry.name.textContent=info.title;entry.name.title=info.title;entry.button.setAttribute('aria-label',`${info.title}, ${info.range}`);}
    for(const [index,segment]of segments.entries()){
      const button=node('button',null,'scene-browser-card');button.type='button';
      if(segment.thumbnailUrl){const image=node('img');image.src=segment.thumbnailUrl;image.alt='';image.loading='lazy';button.append(image);}
      const copy=node('span',null,'scene-card-copy'),name=node('strong'),range=node('time',describe(segment,index,analysis,notes).range);copy.append(name,range);button.append(copy);
      const entry={button,name,segment,index};entries.push(entry);paintCard(entry);
      button.onclick=()=>{cancelEdit();select(index);const seek=()=>{preview.currentTime=segment.start;};if(preview.readyState>=1)seek();else preview.addEventListener('loadedmetadata',seek,{once:true});};strip.append(button);
    }
    function select(index){
      if(index<0||index===selected)return;selected=index;
      entries.forEach((e,i)=>i===index?e.button.setAttribute('aria-current','true'):e.button.removeAttribute('aria-current'));
      const info=describe(segments[index],index,analysis,notes);detailTitle.textContent=info.title;boundary.textContent=info.boundary;
      description.textContent=info.summary||'No visual description yet.';
      reason.textContent=info.reason+(info.cutCount?` Contains ${info.cutCount} additional detected cut${info.cutCount===1?'':'s'}; this is a grouped navigation segment.`:'');
    }
    let editButton,form;
    function cancelEdit(){if(!editing)return;editing=false;form?.remove();if(editButton)editButton.hidden=false;}
    if(onSave){
      editButton=node('button','Edit notes','scene-edit');editButton.type='button';editButton.setAttribute('aria-label','Edit scene notes');detailTop.append(editButton);
      editButton.onclick=()=>{
        editing=true;preview.pause?.();editButton.hidden=true;const index=selected,segment=segments[index],info=describe(segment,index,analysis,notes);
        form=node('form',null,'scene-notes-form');const titleLabel=node('label','Title'),input=node('input');input.value=info.title.startsWith('Segment ')?'':info.title;input.maxLength=80;input.required=true;titleLabel.append(input);
        const descLabel=node('label','Description'),textarea=node('textarea');textarea.value=info.summary;textarea.maxLength=400;textarea.rows=2;descLabel.append(textarea);
        const actions=node('div'),save=node('button','Save notes'),cancel=node('button','Cancel'),status=node('p');status.setAttribute('role','status');save.type='submit';cancel.type='button';cancel.onclick=cancelEdit;actions.append(save,cancel);form.append(titleLabel,descLabel,actions,status);detail.append(form);input.focus();
        form.onsubmit=async event=>{event.preventDefault();if(!input.value.trim())return;save.disabled=cancel.disabled=true;entries.forEach(e=>e.button.disabled=true);
          const next={...notes,[segment.id]:{title:input.value.trim(),description:textarea.value.trim()}};
          try{await onSave(next);notes=next;cancelEdit();paintCard(entries[index]);selected=-1;select(index);}catch{status.textContent='Could not save these notes. Please retry.';}finally{save.disabled=cancel.disabled=false;entries.forEach(e=>e.button.disabled=false);}
        };
      };
    }
    const sync=()=>{if(!editing)select(activeIndex(segments,preview.currentTime||0));};
    preview._disposeScenes?.();
    const observer=typeof ResizeObserver==='function'?new ResizeObserver(updateNavigation):null;observer?.observe(strip);
    const frame=typeof requestAnimationFrame==='function'?requestAnimationFrame(updateNavigation):null;
    preview._disposeScenes=()=>{preview.removeEventListener('timeupdate',sync);preview.removeEventListener('seeked',sync);strip.removeEventListener('scroll',updateNavigation);observer?.disconnect();if(frame!==null)cancelAnimationFrame(frame);};
    preview.addEventListener('timeupdate',sync);preview.addEventListener('seeked',sync);select(Math.max(0,activeIndex(segments,preview.currentTime||0)));
    return group;
  }
  const api={describe,activeIndex,time,mount};if(typeof module!=='undefined')module.exports=api;else window.PixfunScenes=api;
})();
