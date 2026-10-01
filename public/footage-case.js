/* Public, precomputed case studies; never query the visitor's media library. */
(() => {
 'use strict';
 const time=s=>`${Math.floor(s/60)}:${String(Math.floor(s%60)).padStart(2,'0')}`;
 function shotAt(shots,seconds){return Math.max(0,shots.findIndex((s,i)=>seconds>=s.start&&(seconds<s.end||i===shots.length-1)));}
 function validateCase(item){
  if(!item||!Array.isArray(item.shots)||!item.shots.length||!(item.duration>=20&&item.duration<=60))return false;
  let end=0;
  for(const shot of item.shots){if(!Number.isFinite(shot.start)||!Number.isFinite(shot.end)||Math.abs(shot.start-end)>.02||shot.end<=shot.start||shot.useDuration<0||shot.useDuration>shot.end-shot.start+.02)return false;end=shot.end;}
  let cueEnd=0;
  for(const cue of item.transcript||[]){if(!item.audio||!Number.isFinite(cue.start)||!Number.isFinite(cue.end)||cue.start<cueEnd-.02||cue.end<=cue.start||cue.end>item.duration+.02||!cue.text?.trim())return false;cueEnd=cue.end;}
  return Math.abs(end-item.duration)<.02&&item.highlight.start>=0&&item.highlight.start+5<=item.duration+.02;
 }
 if(typeof module!=='undefined'&&module.exports){module.exports={time,shotAt,validateCase};return;}
 const $=id=>document.getElementById(id);
 function node(tag,text,cls){const el=document.createElement(tag);if(text!=null)el.textContent=text;if(cls)el.className=cls;return el;}
 const id=decodeURIComponent(location.pathname.split('/').filter(Boolean).pop()||'');
 let stopAt=null,selected=-1,item;
 const video=$('caseVideo');
 function setShot(index){
  if(index===selected)return;
  selected=index;
  const shot=item.shots[index];
  [...$('shotGrid').children].forEach((button,i)=>button.setAttribute('aria-pressed',String(i===index)));
  const box=$('shotDetails');box.replaceChildren();
  box.append(node('p',`${time(shot.start)}–${time(shot.end)} · ${shot.size} · ${shot.capture}`,'shot-meta'),node('h3',shot.title),node('p',shot.description));
  for(const [label,value] of [['Camera',shot.motion],['Story role',shot.role],['Reaction',shot.reaction],['Speech',shot.dialogue],['Sound',shot.audio?.join(' · ')],[`${shot.recommendation} · ${shot.useDuration}s`,shot.reason],['Connect with',shot.connect],['Watch for',shot.caution]]){
   if(!value)continue;const row=node('div',null,'edit-decision');row.append(node('strong',label),node('p',value));box.append(row);
  }
 }
 function highlightCue(seconds){[...$('transcriptLines').children].forEach((line,i)=>{const cue=item.transcript[i];if(seconds>=cue.start&&seconds<cue.end)line.setAttribute('aria-current','true');else line.removeAttribute('aria-current');});}
 function seek(seconds,end=null){stopAt=end;video.currentTime=seconds;setShot(shotAt(item.shots,seconds));highlightCue(seconds);}
 function revealPlayer(){const rect=video.getBoundingClientRect();if(rect.bottom<0||rect.top>innerHeight)video.scrollIntoView({block:'start',behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});}
 async function load(){
  try{
   const response=await fetch('/assets/media/cases/catalog.json?v=3');if(!response.ok)throw Error('unavailable');
   const catalog=await response.json();item=catalog.find(c=>c.id===id);
   if(!validateCase(item))throw Error('missing');
   document.title=item.title+' — Pixfun';
   $('caseTitle').textContent=item.title;$('caseIndex').textContent=String(catalog.indexOf(item)+1).padStart(2,'0')+' / 05';
   $('caseSubtitle').textContent=`${time(item.duration)} · ${item.shots.length} shots${item.transcript?.length?' · Original audio · Transcript below':''}`;
   video.poster=item.poster;video.src=item.full;
   $('sourceDuration').textContent=`Full example · ${time(item.duration)} · 16:9`;
   $('fullDescription').textContent=item.description;
   $('highlightReason').textContent=item.highlight.reason;$('highlightRange').textContent=`Selected excerpt · ${time(item.highlight.start)}–${time(item.highlight.start+5)}`;
   if(item.subjects?.length){$('subjects').textContent=item.subjects.join(' · ');$('subjectsSection').hidden=false;}
   for(const tag of item.tags||[])$('tags').append(node('span',tag));
   $('shotCount').textContent=`${item.shots.length} shots · Select to jump`;
   item.shots.forEach((shot,index)=>{
    const button=node('button',null,'shot-card');button.type='button';button.setAttribute('aria-label',`View shot ${index+1}: ${shot.title}, ${time(shot.start)} to ${time(shot.end)}`);
    const preview=node('span',null,'shot-image'),img=node('img');img.src=shot.thumbnail;img.alt='';img.loading='lazy';preview.append(img);
    if(shot.highlight)preview.append(node('span','✦ Highlight','badge'));
    button.append(preview,node('strong',shot.title),node('small',`${time(shot.start)}–${time(shot.end)} · ${shot.recommendation}`));
    button.addEventListener('click',()=>{seek(shot.start);revealPlayer();});$('shotGrid').append(button);
   });
   if(item.transcript?.length){
    $('transcriptSection').hidden=false;$('captionDownload').href=item.captionFile;
    // Keep the footage clean. The complete transcript and downloadable VTT live
    // outside the player; no captions or editorial graphics are overlaid on it.
    for(const cue of item.transcript){const line=node('button',null,'transcript-line');line.type='button';line.append(node('span',time(cue.start),'cue-time'),node('span',cue.text));line.addEventListener('click',()=>{seek(cue.start);revealPlayer();});$('transcriptLines').append(line);}
   }
   $('exampleContext').textContent=item.context;
   for(const [label,value] of [['Duration',item.duration.toFixed(1)+' seconds'],['Resolution',item.width+' × '+item.height],['Audio',item.audio?'Original audio preserved':'Silent source clips'],['Analysis',item.analysisModel]])$('sourceFacts').append(node('dt',label),node('dd',value));
   for(const source of item.sources||[]){const row=node('p'),a=node('a',source.credit+' ↗');a.href=source.page;a.target='_blank';a.rel='noopener noreferrer';row.append(a,node('span',`${time(source.start)}–${time(source.start+source.duration)} · ${source.license}`));$('sourceList').append(row);}
   for(const other of catalog.filter(c=>c.id!==id)){
    const a=node('a');a.href='/stories/'+other.id;const img=node('img');img.src=other.poster;img.alt='';img.loading='lazy';a.append(img,node('strong',other.label+' ↗'),node('small',`${time(other.duration)} · View breakdown`));$('otherCases').append(a);
   }
   setShot(0);$('caseContent').hidden=false;$('caseStatus').hidden=true;
  }catch(error){$('caseStatus').replaceChildren(node('span',error.message==='missing'?'This example is not available. ':'The example could not load. '));const back=node('a','Back to examples');back.href='/#footage-examples';$('caseStatus').append(back);}
 }
 $('playHighlight').addEventListener('click',()=>{seek(item.highlight.start,item.highlight.start+5);video.play().catch(()=>{stopAt=null;});});
 video.addEventListener('timeupdate',()=>{if(!item)return;if(stopAt!==null&&video.currentTime>=stopAt){video.pause();stopAt=null;}setShot(shotAt(item.shots,video.currentTime));highlightCue(video.currentTime);});
 video.addEventListener('seeking',()=>{if(stopAt!==null&&(video.currentTime<item.highlight.start-.1||video.currentTime>stopAt+.2))stopAt=null;});
 video.addEventListener('error',()=>{$('videoError').hidden=false;});
 video.addEventListener('loadeddata',()=>{$('videoError').hidden=true;});
 $('retryVideo').addEventListener('click',()=>video.load());
 window.addEventListener('pagehide',()=>video.pause());
 load();
})();
