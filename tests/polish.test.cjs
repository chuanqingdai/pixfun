const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {bindImageMedia,bindHeroMedia}=require('../public/polish.js');
class Element extends EventTarget {
  dataset={}; attrs={}; complete=false; naturalWidth=0; readyState=0;
  classList={add:()=>{}};
  setAttribute(key,value){this.attrs[key]=value;}
  removeAttribute(key){delete this.attrs[key];}
  fire(name){this.dispatchEvent(new Event(name));}
}
function clock(){const jobs=new Map();let id=0;return {set(fn){jobs.set(++id,fn);return id;},clear(id){jobs.delete(id);},flush(){const batch=[...jobs.values()];jobs.clear();batch.forEach(fn=>fn());},get count(){return jobs.size;}};}
{
  const image=new Element(),timers=clock(),refresh=bindImageMedia(image,timers);
  assert.equal(image.dataset.mediaState,'loading');assert.equal(image.attrs['aria-busy'],'true');
  image.complete=true;image.naturalWidth=1280;image.fire('load');
  assert.equal(image.dataset.mediaState,'ready');assert.equal(timers.count,0);assert.equal(image.attrs['aria-busy'],undefined);
  image.complete=false;refresh();timers.flush();assert.equal(image.dataset.mediaState,'fallback');
  image.fire('load');assert.equal(image.dataset.mediaState,'ready','Late media still replaces the fallback');
  image.fire('error');assert.equal(image.dataset.mediaState,'error');
}
{
  const cached=new Element();cached.complete=true;cached.naturalWidth=100;
  bindImageMedia(cached,clock());assert.equal(cached.dataset.mediaState,'ready','No skeleton flash for cached images');
  const failed=new Element();failed.complete=true;bindImageMedia(failed,clock());assert.equal(failed.dataset.mediaState,'error');
}
{
  const video=new Element(),poster=new Element(),frame=new Element(),timers=clock();
  bindHeroMedia(video,poster,frame,timers);assert.equal(frame.dataset.mediaState,'loading');
  poster.complete=true;poster.naturalWidth=1280;poster.fire('load');assert.equal(frame.dataset.mediaState,'poster');
  video.readyState=2;video.fire('loadeddata');assert.equal(frame.dataset.mediaState,'ready');assert.equal(timers.count,0);
  video.readyState=0;video.fire('loadstart');assert.equal(frame.dataset.mediaState,'poster','Keep the poster during case switches');
  timers.flush();assert.equal(frame.dataset.mediaState,'poster');assert.equal(frame.attrs['aria-busy'],undefined);
  video.fire('error');assert.equal(frame.dataset.mediaState,'poster','Video failure does not erase a loaded poster');
  poster.naturalWidth=0;poster.fire('error');assert.equal(frame.dataset.mediaState,'error');
  video.readyState=2;video.fire('playing');assert.equal(frame.dataset.mediaState,'ready','Recovery after a timeout remains possible');
}
const root=path.resolve(__dirname,'../public');
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const css=fs.readFileSync(path.join(root,'polish.css'),'utf8');
const js=fs.readFileSync(path.join(root,'polish.js'),'utf8');
assert.match(html,/as="image" fetchpriority="high"/);
assert.match(html,/id="heroPoster"[^>]*width="1280" height="720"/);
assert.match(html,/<details class="mobile-menu"><summary>Menu<\/summary>/);
assert.match(css,/min-height:44px/);assert.match(css,/prefers-reduced-motion:reduce/);
assert.match(css,/\.creator-grid article>img\{[^}]*height:auto;aspect-ratio:16\/9;object-fit:cover/,'Creator examples use a consistent 16:9 crop on desktop and mobile');
assert.match(css,/overflow-x:auto/);assert.match(js,/animation\.cancel\(\)/);
assert.doesNotMatch(css,/body[^{}]*\{[^}]*opacity:0/,'Never cover the entire page with a loading state');
assert.match(js,/Escape/);assert.match(js,/preventScroll:true/);
const footer=html.split('<footer class="footer site-footer wrap"')[1].split('</footer>')[0];
assert.match(footer,/Intelligent editing\./);
assert.match(footer,/aria-labelledby="footerProduct"/);
assert.match(footer,/aria-labelledby="footerExplore"/);
assert.deepEqual([...footer.matchAll(/<nav\b[^>]*>([\s\S]*?)<\/nav>/g)].flatMap(([,nav])=>[...nav.matchAll(/href="([^"]+)"/g)].map(([,href])=>href)),['/mac-early-access','#how','#faq'],'Footer only exposes current application, workflow and FAQ destinations');
assert.match(footer,/All rights reserved/);
assert.doesNotMatch(footer,/Made for the stories you bring home|Back to top/);
assert.match(footer,/id="engineText" hidden/,'Keep health status binding without marketing-page debug text');
for (const [,target] of footer.matchAll(/href="#([^"]+)"/g)) {
  assert.ok(html.includes(`id="${target}"`), `Footer link resolves: ${target}`);
}
assert.match(css,/\.studio-mode \.site-footer\{display:none\}/,'Hide the landing footer inside the studio');
console.log('PASS: Image/video loading, cache hits, timeout, failure, recovery, responsive targets and progressive enhancement.');
