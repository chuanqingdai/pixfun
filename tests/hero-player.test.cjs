const assert=require('node:assert/strict');
const {bindHeroPlaylist}=require('../public/hero-player.js');
class Element {
  constructor(){this.events={};this.attrs={};this.dataset={};this.style={setProperty:(k,v)=>{this.style[k]=v;}};}
  addEventListener(type,fn){(this.events[type]??=[]).push(fn);}
  emit(type){for(const fn of this.events[type]||[])fn();}
  setAttribute(k,v){this.attrs[k]=v;}
  getAttribute(k){return this.attrs[k];}
}
function setup(overrides={},linked=false,withControl=true) {
  const environment={visible:true,hidden:false,studio:false,reduced:false,saveData:false,...overrides};
  const video=new Element();Object.assign(video,{paused:true,ended:false,error:null,duration:8,currentTime:0,loop:true,readyState:4,plays:0,loads:0});
  video.play=()=>{video.plays++;if(video.reject)return Promise.reject(video.reject);video.paused=false;video.emit('playing');return Promise.resolve();};
  video.pause=()=>{video.paused=true;video.emit('pause');};
  video.load=()=>{video.loads++;video.currentTime=0;video.ended=false;video.error=null;};
  const buttons=['citywalk','food','luxury','islands','alpine'].map((name,i)=>{
    const b=new Element();b.dataset={film:name,label:name,src:'/hero-'+name+'.mp4',poster:'/hero-'+name+'.jpg'};b.setAttribute(linked?'aria-current':'aria-pressed',String(i===0));return b;
  });
  const callbacks=new Map();let timerId=0;
  const timers={set:(fn,ms)=>{callbacks.set(++timerId,{fn,ms});return timerId;},clear:id=>callbacks.delete(id)};
  const frame=new Element(),poster=new Element();
  const control=withControl?new Element():null;
  const player=bindHeroPlaylist({video,poster,buttons,frame,linked,control,getEnvironment:()=>environment,timers});
  const selected=()=>buttons.findIndex(b=>b.getAttribute(linked?'aria-current':'aria-pressed')==='true');
  const end=()=>{video.currentTime=8;video.ended=true;video.paused=true;video.emit('ended');};
  const timeout=()=>{const active=[...callbacks.values()];callbacks.clear();active.forEach(x=>x.fn());};
  return {video,buttons,frame,poster,environment,player,selected,end,timeout,callbacks,control};
}
(async()=>{
  const mobile=setup({compact:true});mobile.video.dataset.src='/large.mp4';
  mobile.buttons.forEach((b,i)=>{b.dataset.mobileSrc='/mobile-'+i+'.mp4';});
  mobile.player.manage();assert.equal(mobile.video.src,'/mobile-0.mp4');
  mobile.end();assert.equal(mobile.video.src,'/mobile-1.mp4','Rotation also uses compact sources');
  mobile.environment.compact=false;mobile.end();assert.equal(mobile.video.src,mobile.buttons[2].dataset.src,'Desktop keeps its original source');
  for(const restriction of ['reduced','saveData','hidden']){
    const lazy=setup({[restriction]:true});lazy.video.dataset.src='/initial.mp4';
    lazy.player.manage();assert.equal(lazy.video.loads,0,'Restricted hero does not download video');
    assert.equal(lazy.video.src,undefined);
    lazy.environment[restriction]=false;lazy.player.manage();
    assert.equal(lazy.video.src,'/initial.mp4');assert.equal(lazy.video.loads,1);
    lazy.player.manage();assert.equal(lazy.video.loads,1,'Source is attached only once');
  }
  let s=setup();s.player.manage();assert.equal(s.video.loop,false);assert.equal(s.video.paused,false);
  for(const expected of [1,2,3,4,0,1]){s.end();assert.equal(s.selected(),expected);assert.equal(s.video.currentTime,0);assert.equal(s.video.paused,false);}
  assert.equal(s.video.loads,6,'Exactly one change per real ended event');
  s.buttons[3].emit('click');assert.equal(s.selected(),3);s.end();assert.equal(s.selected(),4,'Manual selection continues from the selected theme');
  s.buttons[4].emit('click');assert.equal(s.video.paused,true);s.player.manage();assert.equal(s.video.paused,true,'Manual pause persists through visibility/resize updates');assert.equal(s.callbacks.size,0);s.timeout();assert.equal(s.selected(),4);
  s.buttons[4].emit('click');assert.equal(s.video.paused,false);s.end();assert.equal(s.selected(),0);

  for(const key of ['hidden','studio']){s=setup();s.player.manage();s.environment[key]=true;s.player.manage();assert.equal(s.video.paused,true);s.end();assert.equal(s.selected(),0,'No rotation outside landing');s.environment[key]=false;s.player.manage();assert.equal(s.selected(),1);}
  s=setup();s.player.manage();s.video.currentTime=3;s.environment.visible=false;s.player.manage();assert.equal(s.video.paused,true);assert.equal(s.callbacks.size,0);s.environment.visible=true;s.player.manage();assert.equal(s.video.currentTime,3,'Resume the same time after scrolling back');

  for(const key of ['reduced','saveData']){s=setup({[key]:true});s.player.manage();assert.equal(s.video.plays,0);s.buttons[0].emit('click');assert.equal(s.video.paused,false);s.end();assert.equal(s.selected(),0,'Explicit playback does not override reduced-motion rotation preference');assert.equal(s.video.paused,true);}
  s=setup();s.player.manage();s.environment.reduced=true;s.player.manage();assert.equal(s.video.paused,true,'Changed motion preference pauses immediately');

  s=setup();s.player.manage();s.video.emit('error');assert.equal(s.selected(),1,'Skip failed media');
  s.timeout();assert.equal(s.selected(),2,'Skip a stalled/unresponsive clip');
  s.video.emit('error');s.video.emit('error');s.video.emit('error');assert.equal(s.video.paused,true);assert.equal(s.callbacks.size,0,'All failures stop, never an infinite request loop');
  s.buttons[0].emit('click');assert.equal(s.selected(),0);assert.equal(s.video.paused,false,'A manual click retries a failed clip');

  s=setup();s.video.reject=Object.assign(new Error('blocked'),{name:'NotAllowedError'});s.player.manage();await new Promise(resolve=>setImmediate(resolve));assert.equal(s.frame.dataset.playback,'blocked');assert.equal(s.callbacks.size,0);s.timeout();assert.equal(s.selected(),0,'Autoplay refusal does not spin through files');delete s.video.reject;s.buttons[0].emit('click');await Promise.resolve();assert.equal(s.video.paused,false);

  s=setup();s.video.play=()=>new Promise((resolve,reject)=>{s.video.rejectOld=reject;});s.player.manage();const rejectOld=s.video.rejectOld;s.video.play=()=>{s.video.paused=false;return Promise.resolve();};s.buttons[2].emit('click');rejectOld(new Error('old playback rejected'));await new Promise(resolve=>setImmediate(resolve));assert.notEqual(s.frame.dataset.playback,'blocked','Stale playback promises cannot stop a newer selection');assert.equal(s.selected(),2);
  console.log('PASS: Natural 5-case rotation, wraparound, selection, pause, visibility, reduced motion, data saving, stalled/failed media, blocked autoplay and rapid-switch races.');
  s=setup({},true);s.player.manage();s.buttons[2].emit('click');assert.equal(s.selected(),0,'Case links must navigate without a playback click handler');
  s.control.emit('click');assert.equal(s.video.paused,true);s.player.manage();assert.equal(s.video.paused,true);s.control.emit('click');assert.equal(s.video.paused,false);s.end();assert.equal(s.selected(),1);
  assert.equal(s.buttons[0].getAttribute('aria-pressed'),undefined,'Navigation links never act as toggle buttons');
  console.log('PASS: Linked cases retain navigation, separate pause/resume and current-preview indication.');
  s=setup({},true,false);s.player.manage();assert.equal(s.video.paused,false);
  s.end();assert.equal(s.selected(),1,'Linked previews still rotate with no visible playback button');
  s.environment.reduced=true;s.player.manage();assert.equal(s.video.paused,true,'Reduced-motion preference remains respected');
  assert.doesNotMatch(require('node:fs').readFileSync(require('node:path').join(__dirname,'../public/index.html'),'utf8'),/heroPreviewToggle|Use Pause previews/);
})();
