/* Landing enhancement only. The readable page and native controls work without it. */
(() => {
  'use strict';
  const browserTimers = {set:(fn,ms)=>setTimeout(fn,ms),clear:id=>clearTimeout(id)};
  function bindImageMedia(image, timers = browserTimers) {
    let timer;
    function settle(state) {
      timers.clear(timer);
      image.dataset.mediaState = state;
      image.removeAttribute('aria-busy');
    }
    function refresh() {
      timers.clear(timer);
      if (image.complete) { settle(image.naturalWidth ? 'ready' : 'error'); return; }
      image.dataset.mediaState = 'loading';
      image.setAttribute('aria-busy','true');
      // Never keep a skeleton running forever on a slow/offline connection.
      timer = timers.set(() => settle('fallback'),8000);
    }
    image.addEventListener('load',() => settle('ready'));
    image.addEventListener('error',() => settle('error'));
    refresh();
    return refresh;
  }
  function bindHeroMedia(video, poster, frame, timers = browserTimers) {
    let timer;
    function settle(state) {
      timers.clear(timer);
      frame.dataset.mediaState = state;
      frame.removeAttribute('aria-busy');
    }
    function fallback() { settle(poster.complete && poster.naturalWidth ? 'poster' : 'error'); }
    function begin() {
      timers.clear(timer);
      frame.dataset.mediaState = poster.complete && poster.naturalWidth ? 'poster' : 'loading';
      frame.setAttribute('aria-busy','true');
      timer = timers.set(fallback,6000);
    }
    function ready() { if(video.readyState >= 2) settle('ready'); }
    frame.classList.add('media-enhanced');
    video.addEventListener('loadstart',begin);
    video.addEventListener('loadeddata',ready);
    video.addEventListener('playing',ready);
    video.addEventListener('error',fallback);
    poster.addEventListener('load',() => { if(frame.dataset.mediaState !== 'ready') frame.dataset.mediaState = 'poster'; });
    poster.addEventListener('error',() => { if(frame.dataset.mediaState !== 'ready') settle('error'); });
    if(video.readyState >= 2) ready(); else begin();
    return {begin,fallback};
  }
  if(typeof module !== 'undefined' && module.exports) {module.exports={bindImageMedia,bindHeroMedia};return;}

  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const animations = new Set();
  function animate(element, keyframes, duration=500) {
    if(!element || reduced.matches || document.hidden || !element.animate) return;
    const animation = element.animate(keyframes,{duration,easing:'cubic-bezier(.22,1,.36,1)'});
    animations.add(animation);
    animation.finished.catch(() => {}).finally(() => animations.delete(animation));
    return animation;
  }
  function stopAnimations() {animations.forEach(animation=>animation.cancel());animations.clear();}
  reduced.addEventListener('change',() => {if(reduced.matches)stopAnimations();});

  // Small, one-off entrance; content remains visible if motion is disabled,
  // scripts fail or the page opens in the background.
  animate(document.querySelector('.hero-intro'),[{transform:'translateY(10px)'},{transform:'translateY(0)'}],600);

  const hero = document.getElementById('heroFilm');
  bindHeroMedia(hero,document.getElementById('heroPoster'),hero.parentElement);
  const images = document.querySelectorAll('.film-selector img,.source-pile img,.example-cover img,.source-grid img,#demoImage,#stylePicker img,.creator-grid article>img');
  function observeImage(image) {
    const refresh = bindImageMedia(image);
    // The workflow reuses its image element as the selected step changes.
    if(image.id === 'demoImage') new MutationObserver(refresh).observe(image,{attributes:true,attributeFilter:['src']});
  }
  const lazyMedia = 'IntersectionObserver' in window ? new IntersectionObserver(entries => entries.forEach(entry=>{
    if(!entry.isIntersecting)return;
    lazyMedia.unobserve(entry.target);
    observeImage(entry.target);
  }),{rootMargin:'200px'}) : null;
  images.forEach(image => {
    image.decoding='async';
    // Offscreen lazy images have not started loading: don't start their timeout yet.
    if(lazyMedia && image.loading==='lazy' && !image.complete) lazyMedia.observe(image);
    else observeImage(image);
  });

  if('IntersectionObserver' in window) {
    const reveal = new IntersectionObserver(entries => entries.forEach(entry => {
      if(!entry.isIntersecting)return;
      reveal.unobserve(entry.target);
      animate(entry.target,[{opacity:.35,transform:'translateY(16px)'},{opacity:1,transform:'translateY(0)'}],650);
    }),{threshold:.08});
    document.querySelectorAll('#stories .travel-section-head,.edit-example,.share-destinations,.creator-grid article,.voices-heading,.voice-card,.travel-faq .travel-section-head,.travel-faq-list,.closing-content').forEach(element=>reveal.observe(element));
  }
  let stageAnimations=[];
  document.getElementById('how').addEventListener('pixfun:stagechange',() => {
    stageAnimations.forEach(animation=>animation?.cancel());
    stageAnimations = [...document.querySelectorAll('.demo-summary,.demo-main')].map(element=>animate(element,[{opacity:.5,transform:'translateY(7px)'},{opacity:1,transform:'translateY(0)'}],340));
  });
  document.querySelectorAll('.travel-faq details').forEach(details=>details.addEventListener('toggle',()=>{
    if(details.open) animate(details.querySelector('p'),[{opacity:0,transform:'translateY(-4px)'},{opacity:1,transform:'translateY(0)'}],260);
  }));

  const menu = document.querySelector('.mobile-menu');
  const menuButton = menu.querySelector('summary');
  const resume=document.getElementById('resumeStudio'),mobileResume=document.getElementById('mobileResume');
  const syncResume=()=>{mobileResume.hidden=resume.hidden;};
  new MutationObserver(syncResume).observe(resume,{attributes:true,attributeFilter:['hidden']});
  syncResume();
  mobileResume.addEventListener('click',()=>{menu.open=false;resume.click();});
  menu.querySelectorAll('a').forEach(link=>link.addEventListener('click',event=>{
    const target=document.querySelector(link.hash);
    if(!target)return;
    event.preventDefault();
    menu.open=false;
    if(location.hash!==link.hash)history.pushState(null,'',link.hash);
    target.scrollIntoView({behavior:reduced.matches?'instant':'smooth',block:'start'});
    const heading=target?.querySelector('h2');
    if(heading){heading.setAttribute('tabindex','-1');heading.focus({preventScroll:true});}
  }));
  document.addEventListener('keydown',event=>{if(event.key==='Escape' && menu.open){menu.open=false;menuButton.focus();}});
  document.addEventListener('click',event=>{if(menu.open && !menu.contains(event.target))menu.open=false;});
  window.addEventListener('pixfun:viewchange',()=>{menu.open=false;stopAnimations();});
  document.addEventListener('visibilitychange',()=>{
    document.body.classList.toggle('page-inactive',document.hidden);
    if(document.hidden)stopAnimations();
  });
})();
