const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process');
const {buildTravelStory,travelStoryShotAt,workflowPresentation,workflowScrollEnabled,workflowMediaRow,travelScrollState}=require('../public/travel.js');
test('Workflow heading shares section typography at every breakpoint',()=>{
 const travel=fs.readFileSync(path.resolve(__dirname,'../public/travel.css'),'utf8');
 const workflow=fs.readFileSync(path.resolve(__dirname,'../public/workflow-story.css'),'utf8');
 const polish=fs.readFileSync(path.resolve(__dirname,'../public/polish.css'),'utf8');
 assert.doesNotMatch(travel,/\.workflow-sticky \.travel-section-head h2\{/);
 assert.doesNotMatch(workflow,/#how[^{}]*\.travel-section-head h2\{/);
 assert.match(polish,/#outcomeTitle,#workflowTitle,#creatorsTitle,#voicesTitle,#closingTitle\{max-width:32ch/);
});
test('Pinned story follows six scroll ranges and falls back on compact or reduced-motion screens',()=>{
 assert.equal(workflowScrollEnabled(1366,700,false),true);
 assert.equal(workflowScrollEnabled(1000,650,false),true);
 assert.equal(workflowScrollEnabled(1366,600,false),false);
 assert.equal(workflowScrollEnabled(390,844,false),false);
 assert.equal(workflowScrollEnabled(1366,900,true),false);
 for(let stage=0;stage<6;stage++){
  const distance=(stage+.2)/6*(3220-700);
  assert.equal(travelScrollState(-distance,3220,700).stage,stage);
 }
});
test('Pinned frame has one viewport height and content cannot grow its grid tracks',()=>{
 const css=fs.readFileSync(path.resolve(__dirname,'../public/workflow-story.css'),'utf8');
 const script=fs.readFileSync(path.resolve(__dirname,'../public/travel.js'),'utf8');
 assert.match(css,/#how\.is-scrollable \.workflow-sticky\{[^}]*height:100dvh;min-height:0;max-height:100dvh/);
 assert.match(css,/#how\.is-scrollable \.workflow-demo \.demo-main\{[^}]*grid-template-rows:var\(--workflow-media-row,minmax\(0,1fr\)\) 176px/);
 assert.match(css,/#how\.is-scrollable \.demo-context\{[^}]*overflow:visible;align-self:start/);
 assert(!css.includes('overflow-y:auto'),'No nested context scrollbar');
 assert(!script.includes('sticky.style.top'),'No variable negative sticky offset when a step grows');
});
test('Every stage shares a top-aligned media row and landscape source covers do not stretch',()=>{
 assert.equal(workflowMediaRow(640,800),360);
 assert.equal(workflowMediaRow(640,550),350);
 assert.equal(workflowMediaRow(640,800,2),360);
 assert.equal(workflowMediaRow(640,800,0),366);
 assert.equal(workflowMediaRow(640,550,2),360,'Steps without a timeline reserve no empty second row');
 assert.equal(workflowMediaRow(640,100),0);
 assert.equal(workflowMediaRow(640,550,1,390),390,'Text height participates in row sizing');
 const css=fs.readFileSync(path.resolve(__dirname,'../public/workflow-story.css'),'utf8');
 assert.match(css,/#how\.is-scrollable \.demo-preview\{[^}]*justify-content:flex-start/);
 assert.match(css,/#how\.is-scrollable \.source-grid img\{width:100%;height:auto;aspect-ratio:16\/9/);
 assert(!css.includes('grid-template-rows:repeat(3,minmax(0,1fr))'));
 assert.match(css,/#how\.is-scrollable \.workflow-sticky\{[^}]*justify-content:center/);
 assert.match(css,/height:var\(--workflow-content-height,500px\)/);
});
test('Historical left step rail and unboxed demo are restored without changing the story',()=>{
 const css=fs.readFileSync(path.resolve(__dirname,'../public/workflow-story.css'),'utf8');
 assert.match(css,/#how\.is-scrollable \.workflow-shell\{[^}]*display:grid;grid-template-columns:170px minmax\(0,1fr\)/);
 assert.match(css,/#how \.workflow-steps\{display:flex;flex-direction:column/);
 assert.match(css,/#how \.workflow-demo\{padding:0;border:0;border-radius:0;background:transparent;box-shadow:none/);
 assert.match(css,/#how \.workflow-steps button\[aria-current\]\{border-left-color:var\(--accent\);color:var\(--ink\);background:none/);
});
test('Adventure has twelve distinct shots, four purposeful chapters and contiguous timing',()=>{
 for(const style of ['Cinematic','Travel diary','Quick highlights']){
  const story=buildTravelStory(style);
  assert.equal(story.shots.length,12);
  assert.equal(new Set(story.shots.map(s=>s.image)).size,12);
  assert.deepEqual(story.acts.map(a=>a.title),['Departure','Into the wild','The reward','After dark']);
  assert.equal(story.shots[0].image,'coffee');
  assert.equal(story.shots.at(-1).image,'stars');
  assert.equal(story.shots.reduce((sum,s)=>sum+s.duration,0),story.total);
  story.shots.forEach((shot,index)=>{
   assert(shot.duration>0);assert(shot.reason.length>20);
   if(index)assert.equal(shot.start,story.shots[index-1].end);
   assert.equal(travelStoryShotAt(story,shot.start),index);
   assert.equal(travelStoryShotAt(story,shot.end-.001),index);
  });
  story.acts.forEach((act,i)=>{assert.equal(story.shots.filter(s=>s.act===i).length,3);if(i)assert.equal(act.start,story.acts[i-1].end);});
  assert.equal(story.acts.at(-1).end,story.total);
  assert.equal(travelStoryShotAt(story,story.total),11);
 }
});
test('Refinement reallocates two seconds, preserves all footage and the night ending',()=>{
 assert.equal(buildTravelStory().total,45);
 assert.equal(buildTravelStory('Quick highlights').total,30);
 assert(buildTravelStory('Travel diary').shots[8].duration>buildTravelStory().shots[8].duration);
 for(const style of ['Cinematic','Travel diary','Quick highlights']){
  const original=buildTravelStory(style),refined=buildTravelStory(style,true);
  assert.equal(refined.total,original.total);
  assert.equal(refined.shots[7].duration-original.shots[7].duration,2);
  assert.equal(original.shots[0].duration-refined.shots[0].duration,1);
  assert.equal(original.shots[1].duration-refined.shots[1].duration,1);
  assert.deepEqual(refined.shots.slice(8),original.shots.slice(8));
  assert.deepEqual(buildTravelStory(style),original,'Undo does not mutate the original shot list');
 }
});
test('Each preview is a real 16:9 video long enough for every edit variant',()=>{
 const root=path.resolve(__dirname,'../public/media/travel/story');
 for(const shot of buildTravelStory().shots){
  const file=path.join(root,shot.image+'.mp4');
  assert(fs.statSync(file).size>10000);
  assert(fs.statSync(path.join(root,shot.image+'.jpg')).size>1000);
  const info=JSON.parse(execFileSync('ffprobe',['-v','error','-show_streams','-show_format','-of','json',file],{encoding:'utf8'}));
  const stream=info.streams.find(s=>s.codec_type==='video');
  assert.equal(stream.width/stream.height,16/9,shot.image);
  for(const style of ['Cinematic','Travel diary','Quick highlights'])for(const refined of [false,true]){
   const duration=buildTravelStory(style,refined).shots.find(s=>s.image===shot.image).duration;
   assert(Number(info.format.duration)>=duration,shot.image+' must not freeze before the edit point');
  }
 }
});
test('Six steps keep the same project and expose only the relevant working area',()=>{
 for(let index=0;index<6;index++){
  const view=workflowPresentation(index);
  assert.equal(view.viewer,index>0);assert.equal(view.sources,index===0);
  assert.equal(view.timeline,index>=3);assert.equal(view.styles,index===2);
 }
 const html=fs.readFileSync(path.resolve(__dirname,'../public/index.html'),'utf8');
 const workflow=html.split('<section class="travel-workflow"')[1].split('<section class="creator-section"')[0];
 assert.equal((workflow.match(/data-story-shot="/g)||[]).length,12);
 assert.equal((workflow.match(/class="story-chapter"/g)||[]).length,4);
 assert(!workflow.includes('project-family'),'No portrait placeholders');
 assert(workflow.includes('WORKFLOW PREVIEW'),'Curated example is not misrepresented as generated live');
 const script=fs.readFileSync(path.resolve(__dirname,'../public/travel.js'),'utf8');
 assert(script.includes("addEventListener('scroll',queueScroll,{passive:true})"),'Desktop workflow follows native page scroll');
 assert(script.includes("document.activeElement.matches('textarea,input,select')"),'Focused requirements are never replaced by scrolling');
 assert(script.includes("if(!scrollEnabled&&(bounds.top<0"),'Selecting a shot in the pinned story does not move the page');
 assert(script.includes("byId('demoApplyRefine').addEventListener('click'"));
 assert(workflow.includes('id="demoRequirements"'),'Step three accepts a written brief');
 assert(!workflow.includes('id="demoBriefReview"'),'Static editing stages do not repeat the brief');
 for(const id of ['demoVideo','demoPlay','demoNext','demoPlaybackTime','demoPlaybackError']){
  assert(!workflow.includes('id="'+id+'"'),id+' is removed rather than just hidden');
  assert(!script.includes("byId('"+id+"')"),id+' has no dangling listeners');
 }
 assert(!workflow.includes('Silent stock preview'));
 assert(script.includes('if(!briefEdited)requirements.value=exampleBrief(selectedStyle)'),'Changing pacing never overwrites a user-edited brief');
});
test('Understanding annotations and film direction are distinct, non-interactive and honest about location',()=>{
 const html=fs.readFileSync(path.resolve(__dirname,'../public/index.html'),'utf8');
 const script=fs.readFileSync(path.resolve(__dirname,'../public/travel.js'),'utf8');
 const css=fs.readFileSync(path.resolve(__dirname,'../public/workflow-story.css'),'utf8');
 assert(html.includes('Exact location not provided'));
 assert(html.includes('EXAMPLE FILM · 45s · CINEMATIC'));
 assert(script.includes("byId('demoSceneInsights').hidden=!view.labels"));
 assert(script.includes("byId('demoFilmDirection').hidden=!view.styles"));
 assert(script.includes('index===2?6:index===1||index===4?7:0'),'Brief uses the landscape, understanding uses the travelers');
 assert.match(css,/\.film-direction-overlay\{[^}]*pointer-events:none/);
 const overlays=html.split('id="demoSceneInsights"')[1].split('<aside')[0];
 assert(!overlays.includes('<button'),'No extra interactions over the preview');
});
test('second step explains AI understanding and separates observation from editing advice',()=>{
 const html=fs.readFileSync(path.resolve(__dirname,'../public/index.html'),'utf8');
 const script=fs.readFileSync(path.resolve(__dirname,'../public/travel.js'),'utf8');
 const panel=html.split('<div id="demoUnderstanding"')[1].split('<div id="demoStyle"')[0];
 assert(html.includes('<span>02</span> Analyze with AI'));
 assert(html.includes('AI UNDERSTANDING · EXAMPLE'));
 assert(panel.includes('AI models describe the action, suggest shot boundaries'));
 for(const label of ['Content','Framing','Use']) assert(panel.includes('<dt>'+label+'</dt>'));
 assert(!panel.includes('The reward after the walk'));
 assert(!panel.includes('Their trail selfie'));
 assert(script.includes('AI models describe the content, suggest shot boundaries'));
});
test('workflow labels use clear actions without implying a live export control',()=>{
 const html=fs.readFileSync(path.resolve(__dirname,'../public/index.html'),'utf8');
 const nav=html.split('<nav class="workflow-steps"')[1].split('</nav>')[0];
 const labels=['Import footage','Analyze with AI','Describe your idea','Build your story','Refine your edit','Review your film'];
 labels.forEach((label,index)=>assert(nav.includes(`<span>0${index+1}</span> ${label}</button>`)));
 assert.equal((nav.match(/data-stage=/g)||[]).length,6);
});
