/* Landing workflow: a curated stock-footage example, never a live AI edit. */
(() => {
  'use strict';
  function travelScrollState(top, height, viewport) {
    const progress = Math.max(0, Math.min(1, -top / Math.max(1, height - viewport)));
    return {progress, stage:Math.min(5, Math.floor(progress * 6)), playhead:4 + progress * 91};
  }
  function workflowPresentation(index) {
    return {sources:index===0, viewer:index>0, timeline:index>=3, labels:index===1, styles:index===2};
  }
  function workflowScrollEnabled(width,height,reduced){return width>=1000&&height>=650&&!reduced;}
  function workflowMediaRow(width,available,stage=3,contextHeight=0){
    const natural=stage===0?width*27/64+96:width*9/16;
    return Math.max(0,Math.min(Math.max(332,natural,contextHeight),available-(stage>=3?200:0)));
  }
  const storyShots = [
    {image:'coffee',title:'Morning coffee',act:0,alt:'Two travelers sharing coffee beside their tent',reason:'Meet the travelers at camp before following them into the forest.'},
    {image:'trail',title:'Into the forest',act:0,alt:'Two hikers walking between pine trees',reason:'Move from the stillness of camp into a tracking shot. The journey begins.'},
    {image:'hike',title:'Follow the trail',act:0,alt:'A high view of hikers following a narrow trail',reason:'Widen the frame to show where the travelers are headed.'},
    {image:'look',title:'A moment to look',act:1,alt:'A hiker looking up among the trees',reason:'Follow the hiker’s gaze to motivate the next cut to an open landscape.'},
    {image:'snow',title:'Beyond the treeline',act:1,alt:'Clouds brushing a steep snow-covered mountain peak',reason:'Cut from the upward glance to a remote snowy peak. Its scale adds tension before the landscape opens up.'},
    {image:'clouds',title:'Above the clouds',act:1,alt:'Clouds drifting below a rugged snowy mountain range',reason:'Carry the snowy ridgeline into moving cloud. A short atmospheric beat raises anticipation before the reveal.'},
    {image:'vista',title:'The view opens',act:2,alt:'An aerial view of a mountain landscape and lake',reason:'Release the tension with an open landscape after the tight forest and cloud-covered peaks.'},
    {image:'together',title:'Take it all in',act:2,alt:'Two hikers embracing while looking out over the mountains',reason:'Return from the landscape to the people. Their shared pause is the emotional peak.'},
    {image:'selfie',title:'Keep the memory',act:2,alt:'The hikers taking a photo together on the trail',reason:'Turn the view into a memory with a candid photo together.'},
    {image:'camp',title:'Back at camp',act:3,alt:'A traveler unpacking a backpack at camp',reason:'Unpacking signals the return. Let the pace settle before the transition to night.'},
    {image:'fire',title:'A little warmth',act:3,alt:'Wood burning on a campfire in the dark',reason:'Bridge daylight and night with a close view of the fire. Warmth answers the cold mountain imagery.'},
    {image:'stars',title:'Under the stars',act:3,alt:'A star-filled night sky above dark mountain silhouettes',reason:'Pull back from the fire to the night sky. Hold the final view and let the adventure settle.'}
  ];
  function buildTravelStory(style='Cinematic',refined=false) {
    const lengths=({'Cinematic':[3,3,3,2,4,3,5,4,3,4,5,6],'Travel diary':[4,3,3,2,3,2,4,4,4,4,5,7],'Quick highlights':[2,2,2,1,3,2,4,3,2,2,3,4]}[style]||[3,3,3,2,4,3,5,4,3,4,5,6]).slice();
    if(refined){lengths[0]--;lengths[1]--;lengths[7]+=2;}
    let time=0;
    const shots=storyShots.map((shot,index)=>({...shot,start:time,end:time+=lengths[index],duration:lengths[index]}));
    const acts=['Departure','Into the wild','The reward','After dark'].map((title,index)=>{
      const clips=shots.filter(shot=>shot.act===index);
      return {title,start:clips[0].start,end:clips.at(-1).end};
    });
    return {shots,acts,total:time,extra:refined?2:0};
  }
  function travelStoryShotAt(story,time){return Math.max(0,story.shots.findIndex((shot,index)=>time<shot.end||index===story.shots.length-1));}
  if(typeof module!=='undefined'&&module.exports){module.exports={travelScrollState,workflowScrollEnabled,workflowMediaRow,workflowPresentation,buildTravelStory,travelStoryShotAt};return;}

  const byId=id=>document.getElementById(id);
  const section=byId('how'),demo=section.querySelector('.workflow-demo');
  const stageButtons=[...section.querySelectorAll('[data-stage]')].filter(el=>el.tagName==='BUTTON');
  const poster=byId('demoImage');
  const reducedMotion=window.matchMedia('(prefers-reduced-motion: reduce)');
  const mediaRoot='/assets/media/travel/story/';
  let active=0,selectedStyle='Cinematic',refined=false,heroVisible=false;
  const requirements=byId('demoRequirements');
  let briefEdited=false;
  const exampleBrief=style=>'Make a '+buildTravelStory(style).total+'-second '+({'Cinematic':'cinematic adventure','Travel diary':'personal travel diary','Quick highlights':'fast-paced adventure highlight'}[style])+'. Build tension with the snowy peaks, hold the view, keep our selfie, and end with the campfire and stars.';
  const stages=[
    ['One trip. All the moments.','Start with the people, places, and details you want to remember.'],
    ['Understand with AI.','AI models describe the content, suggest shot boundaries, and explain what is worth keeping.'],
    ['Tell us the film you want to make.','Describe your story, length, pace, and the moments that must stay.'],
    ['A little tension. A view worth the journey.','Departure, wild peaks, a shared reward, and a night under the stars.'],
    ['Change the emphasis, not the whole story.','Try one precise change and compare the result.'],
    ['One complete adventure.','Twelve shots connect departure, discovery, a shared reward, and a quiet ending.']
  ];
  const storyTime=seconds=>Math.floor(seconds/60)+':'+String(Math.floor(seconds%60)).padStart(2,'0');
  const getStory=()=>buildTravelStory(selectedStyle,refined);
  function selectShot(index){
    const story=getStory(),shot=story.shots[index];
    poster.hidden=false;poster.src=mediaRoot+shot.image+'.jpg';poster.alt=shot.alt;
    byId('demoStoryShot').textContent=shot.title;
    byId('demoStoryReason').textContent=shot.reason;
    byId('demoStoryPosition').textContent=String(index+1).padStart(2,'0')+' / '+story.shots.length+' · '+storyTime(shot.start)+'–'+storyTime(shot.end);
    section.querySelectorAll('[data-story-act]').forEach(button=>button.setAttribute('aria-pressed',String(Number(button.dataset.storyAct)===shot.act)));
    section.querySelectorAll('[data-story-shot]').forEach(button=>button.setAttribute('aria-pressed',String(Number(button.dataset.storyShot)===index)));
  }
  function renderStory(){
    const story=getStory();
    byId('demoStoryMeta').textContent=story.shots.length+' shots · '+story.total+'s · '+selectedStyle;
    byId('demoDirectionMeta').textContent='EXAMPLE FILM · '+story.total+'s · '+selectedStyle.toUpperCase();
    byId('demoFinishStory').textContent=story.shots.length+' shots · '+story.total+' seconds';
    section.querySelectorAll('[data-story-shot]').forEach(button=>{
      const shot=story.shots[Number(button.dataset.storyShot)];
      button.setAttribute('aria-label',shot.title+', '+storyTime(shot.start)+' to '+storyTime(shot.end));
      button.title=shot.title+' · '+storyTime(shot.start)+'–'+storyTime(shot.end);
      const end=document.createElement('span');end.className='story-shot-end';end.textContent='–'+storyTime(shot.end);
      button.querySelector('small').replaceChildren(document.createTextNode(storyTime(shot.start)),end);
    });
    section.querySelectorAll('[data-story-act]').forEach((button,index)=>{
      const act=story.acts[index];
      button.querySelector('time').textContent=storyTime(act.start)+'–'+storyTime(act.end);
    });
    byId('demoRefineRequest').textContent='“Hold the mountain view longer. Keep it at '+story.total+' seconds.”';
    byId('demoApplyRefine').textContent=refined?'Undo change':'Apply to example';
    byId('demoRefineChange').hidden=!refined;
    byId('demoRefineChange').textContent='Viewpoint +2s · Opening −2s · Total '+story.total+'s';
  }
  function setStage(index){
    active=index;
    const view=workflowPresentation(index);
    byId('demoSources').hidden=!view.sources;
    byId('demoViewer').hidden=!view.viewer;
    byId('demoTimeline').hidden=!view.timeline;
    byId('demoSceneInsights').hidden=!view.labels;
    byId('demoFilmDirection').hidden=!view.styles;
    ['demoImport','demoUnderstanding','demoStyle','demoArrange','demoRefine','demoFinish'].forEach((id,i)=>byId(id).hidden=i!==index);
    demo.dataset.stage=String(index);
    stageButtons.forEach((button,i)=>{if(i===index)button.setAttribute('aria-current','step');else button.removeAttribute('aria-current');});
    byId('demoHeading').textContent=stages[index][0];byId('demoDescription').textContent=stages[index][1];
    renderStory();
    if(view.viewer)selectShot(index===5?11:index===2?6:index===1||index===4?7:0);
    fitWorkflowLayout();
    section.dispatchEvent(new CustomEvent('pixfun:stagechange',{detail:{index}}));
  }
  // Native page scrolling drives the pinned story. Never trap wheel/touch input.
  let scrollFrame=0,scrollEnabled=false;
  const main=demo.querySelector('.demo-main');
  function fitWorkflowLayout(){
    if(!scrollEnabled)return;
    const width=parseFloat(getComputedStyle(main).gridTemplateColumns);
    const sticky=section.querySelector('.workflow-sticky');
    const available=sticky.clientHeight-section.querySelector('.travel-section-head').offsetHeight-76;
    if(Number.isFinite(width)){
      const contextHeight=byId('demoContext').getBoundingClientRect().height;
      const row=workflowMediaRow(width,available,active,contextHeight);
      section.style.setProperty('--workflow-media-row',row+'px');
      section.style.setProperty('--workflow-content-height',(row+(active>=3?200:0))+'px');
    }
  }
  new ResizeObserver(fitWorkflowLayout).observe(main);
  new ResizeObserver(fitWorkflowLayout).observe(byId('demoContext'));
  new ResizeObserver(fitWorkflowLayout).observe(section.querySelector('.travel-section-head'));
  function scrollPosition(index){
    return window.scrollY+section.getBoundingClientRect().top+
      (index+.2)/6*(section.offsetHeight-window.innerHeight);
  }
  function goToStage(index){
    setStage(index);
    if(scrollEnabled)window.scrollTo({top:scrollPosition(index),behavior:'instant'});
  }
  function updateScroll(){
    scrollFrame=0;
    if(!scrollEnabled||section.getClientRects().length===0)return;
    const bounds=section.getBoundingClientRect();
    if(bounds.top>window.innerHeight||bounds.bottom<0)return;
    const state=travelScrollState(bounds.top,bounds.height,window.innerHeight);
    // Never replace an active text field while the visitor is writing a brief.
    const editing=section.contains(document.activeElement)&&document.activeElement.matches('textarea,input,select');
    if(!editing&&state.stage!==active)setStage(state.stage);
    section.style.setProperty('--workflow-drift',((state.progress*6%1)-.5)*12+'px');
  }
  function queueScroll(){if(!scrollFrame)scrollFrame=requestAnimationFrame(updateScroll);}
  function configureScroll(){
    const previous=scrollEnabled,bounds=section.getBoundingClientRect();
    scrollEnabled=workflowScrollEnabled(window.innerWidth,window.innerHeight,reducedMotion.matches);
    section.classList.toggle('is-scrollable',scrollEnabled);
    fitWorkflowLayout();
    if(!scrollEnabled)section.style.removeProperty('--workflow-drift');
    if(previous!==scrollEnabled&&bounds.top<=0&&bounds.bottom>0){
      window.scrollTo({top:scrollEnabled?scrollPosition(active):window.scrollY+section.getBoundingClientRect().top,behavior:'instant'});
    }
    queueScroll();
  }
  window.addEventListener('scroll',queueScroll,{passive:true});
  window.addEventListener('resize',configureScroll);
  reducedMotion.addEventListener('change',configureScroll);
  stageButtons.forEach((button,index)=>button.addEventListener('click',()=>goToStage(index)));
  section.querySelectorAll('[data-story-shot],[data-story-act]').forEach(button=>button.addEventListener('click',()=>{
    selectShot(button.hasAttribute('data-story-shot')?Number(button.dataset.storyShot):Number(button.dataset.storyAct)*3);
    const preview=byId('demoViewer'),bounds=preview.getBoundingClientRect();
    if(!scrollEnabled&&(bounds.top<0||bounds.bottom>window.innerHeight))preview.scrollIntoView({block:'start',behavior:reducedMotion.matches?'instant':'smooth'});
  }));
  section.querySelectorAll('[data-style]').forEach(button=>button.addEventListener('click',()=>{
    selectedStyle=button.dataset.style;
    if(!briefEdited)requirements.value=exampleBrief(selectedStyle);
    section.querySelectorAll('[data-style]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
    renderStory();selectShot(6);
  }));
  byId('demoApplyRefine').addEventListener('click',()=>{refined=!refined;renderStory();selectShot(7);});
  requirements.addEventListener('input',()=>{briefEdited=true;});

  const hero=byId('heroFilm');
  const playlist=window.PixfunHeroPlayer.bindHeroPlaylist({
    video:hero,poster:byId('heroPoster'),buttons:[...document.querySelectorAll('[data-film]')],frame:hero.parentElement,selector:document.querySelector('.film-selector'),linked:true,
    getEnvironment:()=>({visible:heroVisible,hidden:document.hidden,compact:window.innerWidth<=600,studio:document.body.classList.contains('studio-mode')||document.body.classList.contains('library-mode')||document.body.classList.contains('web-analysis-mode'),reduced:reducedMotion.matches,saveData:!!navigator.connection?.saveData})
  });
  document.querySelectorAll('[data-upload]').forEach(button=>button.addEventListener('click',()=>{
    if(byId('uploadBtn').disabled)return;
    byId('create').scrollIntoView({behavior:reducedMotion.matches?'instant':'smooth',block:'center'});
    byId('uploadBtn').click();
  }));
  function manageVideo(){playlist.manage();}
  new IntersectionObserver(entries=>{heroVisible=entries[0].isIntersecting;manageVideo();},{threshold:.15}).observe(hero);
  window.addEventListener('pixfun:viewchange',manageVideo);
  document.addEventListener('visibilitychange',manageVideo);
  reducedMotion.addEventListener('change',manageVideo);
  setStage(0);
  manageVideo();
  configureScroll();
})();
