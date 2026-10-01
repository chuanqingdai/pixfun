const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const read=name=>fs.readFileSync(require('node:path').join(__dirname,'../public',name),'utf8');
test('Preload the actual first poster, never fetch decorative video eagerly',()=>{
 const html=read('index.html');
 const preload=html.match(/href="([^"]+)" as="image"/)[1];
 assert.equal(preload,html.match(/id="heroPoster"[^>]*src="([^"]+)"/)[1]);
 const hero=html.match(/<video id="heroFilm"[\s\S]*?<\/video>/)[0];
 assert.match(hero,/preload="none"/);assert.match(hero,/data-src=/);
 assert.doesNotMatch(hero,/<source|\ssrc=/);
});
test('Public pages share touch and reduced-motion refinements',()=>{
 for(const page of ['index.html','footage-case.html','mac-early-access.html'])assert.match(read(page),/site-refinements.css/);
 const css=read('site-refinements.css');
 assert.match(css,/prefers-reduced-motion:reduce/);assert.match(css,/pointer:fine/);
 assert.match(css,/max-width:999px/);assert.match(css,/font-size:16px/);
 assert.doesNotMatch(css,/overflow-y\s*:\s*(auto|scroll)/);
 for(const file of ['footage-case.css','mac-early-access.css'])assert.equal((read(file).match(/font-display:swap/g)||[]).length,2);
});
test('Hidden workspace images no longer compete with landing content',()=>{
 const html=read('index.html');
 for(const tag of html.match(/<img[^>]+>/g).slice(7))assert.match(tag,/loading="lazy"/);
 assert.match(html,/beautiful films, <span class="hero-multiplier">10/);
 assert.doesNotMatch(html,/id="heroPreviewToggle"/);
});
test('All mobile previews retain duration and reduce bytes without replacing full sources',()=>{
 const path=require('node:path');const {execFileSync}=require('node:child_process');
 const tags=read('index.html').match(/<a[^>]+data-film[^>]+>/g);
 assert.equal(tags.length,5);
 for(const tag of tags){
  const source=path.join(__dirname,'../public',tag.match(/data-src="([^"]+)"/)[1].replace('/assets/',''));
  const mobile=path.join(__dirname,'../public',tag.match(/data-mobile-src="([^"]+)"/)[1].replace('/assets/',''));
  assert.ok(fs.statSync(mobile).size<fs.statSync(source).size*.6);
  const probe=JSON.parse(execFileSync('ffprobe',['-v','error','-show_streams','-show_format','-of','json',mobile],{encoding:'utf8'}));
  assert.equal(probe.streams[0].width,640);assert.ok(Math.abs(Number(probe.format.duration)-5)<.1);
  assert.equal(probe.streams[0].codec_name,'h264');
 }
});
