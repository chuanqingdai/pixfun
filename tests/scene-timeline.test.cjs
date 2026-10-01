const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'../public/library.js'),'utf8');
const sceneBrowser=require('../public/scene-browser.js');
class Node {
  constructor(tag,text,cls){this.tag=tag;this.textContent=text;this.className=cls;this.children=[];this.attrs={};this.values={};this.scrollLeft=0;this.clientWidth=300;this.scrollWidth=650;this.rect={left:0,right:300,width:300};this.events={};this.style={setProperty:(key,value)=>this.values[key]=value};}
  append(...children){this.children.push(...children);}
  setAttribute(key,value){this.attrs[key]=value;}
  removeAttribute(key){delete this.attrs[key];}
  getBoundingClientRect(){return this.rect;}
  addEventListener(name,fn){this.events[name]=fn;}
  removeEventListener(name){delete this.events[name];}
  scrollTo(options){this.scrollLeft=options.left;this.events.scroll?.();}
}
global.document={createElement:tag=>new Node(tag)};
const create=vm.runInNewContext(source.slice(source.indexOf('  function sceneTimeline('),source.indexOf('  function renderInspector('))+';sceneTimeline',{
  window:{PixfunScenes:sceneBrowser},
  el:(...args)=>new Node(...args),duration:n=>`${Math.floor(n/60)}:${String(Math.floor(n%60)).padStart(2,'0')}`,isPending:()=>false,
});
const events={};const video={readyState:1,currentTime:0,addEventListener:(name,fn)=>events[name]=fn,removeEventListener:()=>{}};
const segments=[{start:0,end:5,thumbnailUrl:'first.jpg'},{start:5,end:20,thumbnailUrl:'second.jpg'},{start:20,end:30,thumbnailUrl:'third.jpg'}];
const timeline=create({metadata:{duration:30},result:{analysis:{segments}}},video);
const [heading,strip]=timeline.children;
assert.equal(timeline.children.length,3,'Heading, scene buttons and selected detail; no duplicate seek controls');
assert.equal(heading.children[0].textContent,'Scenes');
assert.equal(strip.children[0].attrs['aria-current'],'true');
assert.equal(strip.children[0].children[0].tag,'img','No numbered badges over the image');
assert.equal(strip.children[0].children[1].children[1].textContent,'0:00–0:05');
strip.children[2].rect={left:350,right:450,width:100};
strip.children[2].onclick();
assert.equal(video.currentTime,20);
assert.equal(strip.children[2].attrs['aria-current'],'true');
assert.equal(strip.children[0].attrs['aria-current'],undefined);
assert.equal(strip.scrollLeft,0,'Scene strip never scrolls unexpectedly');
video.currentTime=30;events.timeupdate();
assert.equal(strip.children[2].attrs['aria-current'],'true','End time keeps the last scene selected');
video.currentTime=5;events.timeupdate();
assert.equal(strip.children[1].attrs['aria-current'],'true','Exact boundaries activate the next scene');
assert.equal(heading.children.length,3,'Compact previous/next buttons accompany the scene count');
const [previous,next]=heading.children[2].children;
assert.equal(previous.attrs['aria-label'],'Previous segments');assert.equal(next.attrs['aria-label'],'Next segments');
next.onclick();assert.equal(strip.scrollLeft,240);assert.equal(video.currentTime,5,'Browsing cards does not seek the video');
next.onclick();assert.equal(strip.scrollLeft,350);assert.equal(next.disabled,true,'Cannot scroll beyond the final card');
previous.onclick();previous.onclick();assert.equal(strip.scrollLeft,0);assert.equal(previous.disabled,true);
strip.scrollWidth=200;strip.events.scroll();assert(heading.children[2].hidden,'No arrows when all cards fit');
video._disposeScenes();assert.equal(strip.events.scroll,undefined,'Closing cleans up navigation listeners');
const css=fs.readFileSync(path.join(__dirname,'../public/shot-library.css'),'utf8');
assert.match(css,/\.media-detail-preview \.scene-browser \{[^}]*max-height:none;[^}]*overflow:visible/,'No nested scene scrolling or clipped explanation');
assert.match(css,/\.media-detail-info \{[^}]*overflow:visible/,'Transcript shares the dialog scroll instead of a second pane');
assert.match(css,/\.media-detail-preview \{[^}]*grid-template-columns:minmax\(0,1fr\)/,'The scene row cannot expand its grid column over the transcript');
const empty=create({metadata:{duration:0},result:{analysis:{segments:[]}}},video);
assert.equal(empty.children[1].textContent,'No scene segments available.');
delete global.document;
console.log('PASS: Single-click scene navigation, no duplicate controls, stable strip, boundaries and empty media.');
