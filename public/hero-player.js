/* A playlist of independent travel samples, advanced by actual media playback. */
(() => {
  'use strict';
  function bindHeroPlaylist({video,poster,buttons,frame,selector,linked=false,control,getEnvironment,timers={set:(fn,ms)=>setTimeout(fn,ms),clear:id=>clearTimeout(id)}}) {
    let index=Math.max(0,buttons.findIndex(b=>b.getAttribute(linked?'aria-current':'aria-pressed')==='true'));
    let manuallyPaused=false, explicitPlay=false, blocked=false, generation=0, watchdog;
    let previousRestricted=false;
    const failed=new Set();
    video.loop=false;
    video.muted=true;
    function environment() { return getEnvironment(); }
    function sourceFor(button){return environment().compact&&button.dataset.mobileSrc?button.dataset.mobileSrc:button.dataset.src;}
    function canPlay() {
      const e=environment();
      return e.visible&&!e.hidden&&!e.studio&&!manuallyPaused&&!blocked&&(!(e.reduced||e.saveData)||explicitPlay);
    }
    function canAdvance() {
      const e=environment();
      return canPlay()&&!e.reduced&&!e.saveData;
    }
    function clearWatch() {timers.clear(watchdog);watchdog=undefined;}
    function updateControls() {
      buttons.forEach((button,i)=>{
        const selected=i===index;
        button.setAttribute(linked?'aria-current':'aria-pressed',String(selected));
        button.title=linked?'Open full video and editorial breakdown':selected?(video.paused?'Play this preview':'Pause previews'):'Play this preview';
        button.setAttribute('aria-description',linked?'Open this example on its own page.':selected?(video.paused?'Select to resume playback.':'Select to pause the video and automatic rotation.'):'Select to start this 5-second preview.');
      });
      if(control){control.textContent=video.paused?'Play previews':'Pause previews';control.setAttribute('aria-label',video.paused?'Play five-second previews':'Pause five-second previews');}
      frame.dataset.playback=blocked?'blocked':video.paused?'paused':'playing';
    }
    function showSelected() {
      buttons.forEach(button=>button.style.setProperty('--clip-progress','0%'));
      frame.dataset.film=buttons[index].dataset.film;
      updateControls();
      // Only move the horizontal strip. Never scroll the page or move keyboard focus.
      if(selector&&selector.scrollWidth>selector.clientWidth) {
        const box=buttons[index].getBoundingClientRect(), strip=selector.getBoundingClientRect();
        if(box.left<strip.left||box.right>strip.right) selector.scrollTo({left:selector.scrollLeft+box.left-strip.left-(strip.width-box.width)/2,behavior:environment().reduced?'instant':'smooth'});
      }
    }
    function watch() {
      clearWatch();
      if(!canPlay())return;
      const ticket=generation;
      watchdog=timers.set(()=>{if(ticket===generation&&canPlay())recover();},12000);
    }
    function play() {
      if(!canPlay())return;
      // The public hero starts with a poster only. Do not request video bytes
      // until it is visible and motion/data preferences permit playback.
      if(video.dataset.src){
        const source=environment().compact&&buttons[index].dataset.mobileSrc?buttons[index].dataset.mobileSrc:video.dataset.src;
        delete video.dataset.src;
        video.src=source;
        video.load();
      }
      const ticket=generation;
      watch();
      Promise.resolve(video.play()).then(()=>{
        if(ticket!==generation)return;
        if(!canPlay())video.pause();
        updateControls();
      }).catch(error=>{
        if(ticket!==generation||error?.name==='AbortError')return;
        // A browser autoplay refusal is not a corrupt file: wait for a user click.
        blocked=true;
        clearWatch();
        updateControls();
      });
    }
    function select(next,{manual=false}={}) {
      if(next<0||next>=buttons.length)return;
      generation++;
      clearWatch();
      video.pause();
      index=next;
      if(manual){manuallyPaused=false;explicitPlay=true;blocked=false;failed.delete(index);}
      const button=buttons[index];
      // Keep a real poster visible during decoding rather than flashing black.
      frame.dataset.mediaState='poster';
      video.poster=button.dataset.poster;
      poster.src=button.dataset.poster;
      delete video.dataset.src;
      video.src=sourceFor(button);
      video.setAttribute('aria-label',button.dataset.label+' travel sample, 5 seconds');
      showSelected();
      video.load();
      if(canPlay())play();
    }
    function advance() {
      if(!canAdvance())return;
      for(let step=1;step<=buttons.length;step++){
        const next=(index+step)%buttons.length;
        if(!failed.has(next)){select(next);return;}
      }
      manuallyPaused=true;
      video.pause();
      clearWatch();
      updateControls();
    }
    function recover() {
      failed.add(index);
      clearWatch();
      if(canAdvance())advance();
      else {video.pause();updateControls();}
    }
    function manage() {
      const e=environment(), restricted=!!(e.reduced||e.saveData);
      if(restricted&&!previousRestricted)explicitPlay=false;
      previousRestricted=restricted;
      if(!canPlay()){video.pause();clearWatch();updateControls();return;}
      if(video.ended||failed.has(index)){advance();return;}
      if(video.paused)play();
    }
    if(!linked)buttons.forEach((button,i)=>button.addEventListener('click',()=>{
      if(i!==index||video.error||video.ended||failed.has(index)){select(i,{manual:true});return;}
      if(video.paused){manuallyPaused=false;explicitPlay=true;blocked=false;play();}
      else {manuallyPaused=true;explicitPlay=false;video.pause();clearWatch();}
      updateControls();
    }));
    if(control)control.addEventListener('click',()=>{
      if(video.paused){manuallyPaused=false;explicitPlay=true;blocked=false;if(video.ended){select(index,{manual:true});}else play();}
      else{manuallyPaused=true;explicitPlay=false;video.pause();clearWatch();}
      updateControls();
    });
    video.addEventListener('ended',()=>{
      clearWatch();
      if(canAdvance())advance();
      else {explicitPlay=false;updateControls();}
    });
    video.addEventListener('timeupdate',()=>{
      if(Number.isFinite(video.duration)&&video.duration>0)buttons[index].style.setProperty('--clip-progress',Math.min(100,video.currentTime/video.duration*100)+'%');
      // A stream may stop without a waiting event; real progress renews the guard.
      if(!video.paused&&!video.ended)watch();
    });
    video.addEventListener('playing',()=>{watch();updateControls();});
    video.addEventListener('pause',updateControls);
    video.addEventListener('waiting',watch);
    video.addEventListener('stalled',watch);
    video.addEventListener('error',recover);
    showSelected();
    return {manage};
  }
  if(typeof module!=='undefined'&&module.exports)module.exports={bindHeroPlaylist};
  else window.PixfunHeroPlayer={bindHeroPlaylist};
})();
