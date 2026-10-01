const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const {validateCase,shotAt}=require('../public/footage-case.js');
const root=path.resolve(__dirname,'../public');
const catalog=JSON.parse(fs.readFileSync(path.join(root,'media/cases/catalog.json')));
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const detail=fs.readFileSync(path.join(root,'footage-case.html'),'utf8');
const probe=file=>JSON.parse(execFileSync('ffprobe',['-v','error','-show_streams','-show_format','-of','json',file],{encoding:'utf8'}));
test('all five examples are complete, sourced and independent of user data',()=>{
 assert.equal(catalog.length,5);assert.equal(new Set(catalog.map(c=>c.id)).size,5);
 for(const item of catalog){
  assert.ok(validateCase(item),item.id);assert.match(item.sourcePage,/^https:\/\/(mixkit.co|www.nps.gov)\//);assert.ok(item.sources.every(s=>s.credit&&s.license&&s.page));
  assert.ok(item.shots.length>=3,item.id+' must demonstrate multiple scenes');
  assert.match(html,new RegExp(`href="/stories/${item.id}"[^>]*data-film`));
  for(const url of [item.full,item.preview,item.poster,...item.shots.map(s=>s.thumbnail)])assert.ok(fs.existsSync(path.join(root,url.replace('/assets/',''))),url);
 }
 assert.doesNotMatch(JSON.stringify(catalog),/\/Users\/|apiKey|sourceFile/);
});
test('five second excerpts are separate, light files; complete sources remain 20–60 seconds',()=>{
 for(const item of catalog){
  const preview=path.join(root,item.preview.replace('/assets/','')),full=path.join(root,item.full.replace('/assets/',''));
  const p=probe(preview),f=probe(full),v=f.streams.find(s=>s.codec_type==='video');
  assert.ok(Math.abs(Number(p.format.duration)-5)<.05,item.id+' preview duration');
  assert.ok(Math.abs(Number(f.format.duration)-item.duration)<.05,item.id+' source duration');
  assert.ok(v.width>=1280&&v.height>=720);assert.ok(Math.abs(v.width/v.height-16/9)<.01);
  assert.equal(f.streams.some(s=>s.codec_type==='audio'),item.audio);
  assert.equal(p.streams.some(s=>s.codec_type==='audio'),false,'homepage previews stay silent');
  assert.ok(fs.statSync(preview).size<6e6,item.id+' first-load budget');
  assert.ok(fs.statSync(preview).size<fs.statSync(full).size);
 }
});
test('shot intervals are contiguous and playback selection works at boundaries',()=>{
 const shots=catalog.find(c=>c.id==='food').shots;
 assert.equal(shotAt(shots,0),0);shots.forEach((s,i)=>assert.equal(shotAt(shots,s.start),i));assert.equal(shotAt(shots,23.99),2);
 const bad=structuredClone(catalog[0]);bad.highlight.start=bad.duration;assert.equal(validateCase(bad),false);
 const gap=structuredClone(catalog[0]);gap.shots[0].start=2;assert.equal(validateCase(gap),false);
});
test('narrated examples have complete, ordered, seekable captions from real ASR',()=>{
 const narrated=catalog.filter(c=>c.transcript?.length);assert.ok(narrated.length>=2);
 for(const item of narrated){
  assert.ok(item.audio);assert.match(item.analysisModel,/Whisper/);
  const raw=JSON.parse(fs.readFileSync(path.join(root,'../data/landing-cases-v2',item.id+'.speech.json')));assert.ok(raw.cues.length>0);
  const vtt=fs.readFileSync(path.join(root,item.captionFile.replace('/assets/','')),'utf8');assert.match(vtt,/^WEBVTT/);assert.equal((vtt.match(/ --> /g)||[]).length,item.transcript.length);
  for(const cue of item.transcript)assert.ok(vtt.includes(cue.text));
 }
 const bad=structuredClone(narrated[0]);bad.transcript[0].end=bad.duration+1;assert.equal(validateCase(bad),false);
 const overlap=structuredClone(narrated[0]);overlap.transcript[1].start=0;assert.equal(validateCase(overlap),false);
 assert.match(detail,/id="transcriptSection"[^>]*hidden/);assert.doesNotMatch(detail,/Transcript excerpts/);
});
test('editorial records retain the Mac understanding contract without invented audio',()=>{
 for(const item of catalog){
  assert.ok(item.full_description.length>=100&&item.full_description.length<=200);
  for(const shot of item.shots){
   const e=shot.editorial;assert.ok(e.shot_id&&e.description&&e.shot_size&&e.capture_type&&e.camera_motion);
   assert.ok(e.story_role.length>0);assert.ok(e.edit_recommendation.reason);assert.equal(e.audio.length,0);
   if(e.dialogue)assert.ok(item.transcript.some(c=>c.text===e.dialogue));
   assert.equal(shot.highlight,e.importance_score>=88);
  }
 }
});
test('examples keep the picture free of captions and the overview concise',()=>{
 const js=fs.readFileSync(path.join(root,'footage-case.js'),'utf8');
 assert.doesNotMatch(js,/node\('track'\)|track\.default\s*=\s*true/);
 for(const item of catalog){assert.ok(item.title.length<40);assert.ok(item.description.split(/\s+/).length<=55);}
 assert.match(catalog.find(c=>c.id==='outdoors').sourcePage,/DBA52FFD/);
 assert.match(catalog.find(c=>c.id==='alpine').sourcePage,/a7ea1719/);
 assert.ok(catalog.find(c=>c.id==='outdoors').sources[0].start>230,'avoid the original title and speaker labels');
 assert.ok(catalog.find(c=>c.id==='alpine').sources[0].start>100,'use the clean wildlife and mountain sequence');
});
test('quality revision uses fresh assets, complete highlights and full-HD sources where available',()=>{
 for(const item of catalog){
  assert.match(item.full,/\/v3\//);assert.match(item.preview,/\/v3\//);
  const containing=item.shots.find(s=>s.start<=item.highlight.start&&s.end>=item.highlight.start+5);
  assert.ok(containing,item.id+' highlight should not cut mid-preview into a weaker shot');
  const titleLink=html.match(new RegExp(`<a href="/stories/${item.id}"[^>]+>[\\s\\S]*?</a>`))[0];
  const shortLabel={citywalk:'Tokyo nights',outdoors:'Golden geysers'}[item.id]||item.label;
  assert.ok(titleLink.includes(item.preview));assert.ok(titleLink.includes(shortLabel));
  assert.ok(titleLink.includes(item.shots.length+' shots'));
  assert.doesNotMatch(titleLink,/View breakdown|Narrated/);
  if(item.id!=='outdoors')assert.equal(item.width,1920);
 }
 assert.equal(catalog.filter(c=>c.transcript.length).length,2);
});
test('hero preserves the requested title and introduces footage understanding',()=>{
 assert.match(html,/beautiful films, <span class="hero-multiplier">10/);assert.match(html,/AI that understands your scenes, actions, and key moments/);
 assert.doesNotMatch(html.split('id="footage-examples"')[1].split('</section>')[0],/8 seconds|<button[^>]+data-film/);
 assert.match(detail,/id="caseVideo" controls playsinline preload="metadata"/);assert.match(detail,/id="shotGrid"/);assert.doesNotMatch(detail,/<dialog|<textarea|Transcript excerpts/);
 assert.match(detail,/Precomputed example, editorially reviewed/);
});
