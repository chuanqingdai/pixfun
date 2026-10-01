const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const assets=require('../public/asset-understanding.js');
const sample={id:'test',kind:'video',status:'ready',url:'local.mp4',file:{name:'My trip.mp4',size:1024},metadata:{duration:30,width:1920,height:1080,hasAudio:true,capturedAt:'2025-08-12T10:00:00Z'},context:{device:'Sony FX3',location:'Kyoto'},result:{analysis:{assetUnderstanding:{summary:'A cook prepares noodles at a street stall.',scene:['Night market'],subjects:['Cook'],objects:['Wok'],actions:['Stir frying'],visualStyle:['Warm light'],visibleText:['Noodles'],keywords:['Food tour'],capture:{shotSize:'close_up',cameraMotion:'static'},editing:{shotRole:'detail',recommendedUse:'b_roll',suggestedDuration:{min:3,max:5}},quality:{issues:['Focus shift']},audio:{hasSpeech:true,ambientTypes:['Kitchen sounds']},uncertainties:['Location inferred from supplied tags']},segments:[{id:'s1',start:0,end:10,assetUnderstanding:{title:'Dinner service',summary:'A bowl is served.',objects:['Ceramic bowl']}}],subtitleCues:[{start:2,end:4,text:'Enjoy your meal'}]}}};
test('Editing content and every visible tag are grounded and searchable',()=>{
 const asset=assets.normalize(sample),detail=assets.detailSections(asset);
 assert.equal(detail.summary,'A cook prepares noodles at a street stall.');
 assert(detail.editing.some(([k,v])=>k==='Use as'&&v==='B-roll'));
 assert(detail.editing.some(([k,v])=>k==='Suggested cut'&&v==='3–5 sec'));
 for(const [,tags]of detail.tags)for(const tag of tags)assert(assets.matches(asset,{},tag),tag);
 for(const term of ['Ceramic bowl','Dinner service','A bowl is served','Enjoy your meal'])assert(assets.matches(asset,{},term));
 assert(detail.cautions.includes('Focus shift'));
 assert(!detail.editing.some(([k])=>k==='Importance'));
 const empty=assets.detailSections(assets.normalize({kind:'video',file:{name:'drone_highlight.mp4'},metadata:{duration:30,width:1920,height:1080}}));
 assert.equal(empty.hasContent,false);assert.equal(empty.summary,'');assert.deepEqual(empty.editing,[]);assert.deepEqual(empty.tags,[]);
});
class Element{
 constructor(tag,text,cls){this.tag=tag;this.textContent=text||'';this.className=cls||'';this.children=[];this.attrs={};this.open=false;this.readyState=1;}
 append(...values){this.children.push(...values);}replaceChildren(...values){this.children=values;}
 querySelectorAll(){return [];}
 setAttribute(k,v){this.attrs[k]=v;}addEventListener(){}focus(){this.focused=true;}close(){this.open=false;}
}
function render(item){
 const nodes={mediaDetailDialog:new Element('dialog'),libraryInspector:new Element('div'),mediaDetailTitle:new Element('h2'),librarySearch:new Element('input')};nodes.mediaDetailDialog.open=true;
 const context={items:[item],selected:item.id,selectedSegment:null,assets,byId:id=>nodes[id],el:(...args)=>new Element(...args),sceneTimeline:()=>new Element('section','Scenes'),isPending:()=>false,desktop:{},mediaInfo:{dateText:x=>x||''},duration:n=>String(n||0),size:n=>String(n),render:()=>{},view:'video',URL,notice:()=>{}};
 const source=fs.readFileSync('public/library.js','utf8');
 vm.runInNewContext(source.slice(source.indexOf('  function renderInspector('),source.indexOf("  byId('mediaDetailDialog').addEventListener('close'"))+';renderInspector();',context);
 const walk=node=>[node,...node.children.flatMap(walk)];
 return {nodes,all:walk(nodes.libraryInspector),context};
}
test('Read-only details have clickable search tags, seekable transcript and collapsed file info',()=>{
 const {nodes,all,context}=render(sample);
 assert.equal(nodes.mediaDetailTitle.textContent,'My trip');
 assert(!all.some(n=>['input','textarea','form'].includes(n.tag)));
 assert(!all.some(n=>['Edit','Save tags','Edit description'].includes(n.textContent)));
 assert(all.some(n=>n.textContent==='Editing notes'));
 assert(all.some(n=>n.tag==='h3'&&n.textContent==='Tags'));
 assert(all.some(n=>n.tag==='h4'&&n.textContent==='Location'));
 assert(!all.some(n=>n.textContent==='Place'||n.textContent==='Find related footage'));
 const location=all.find(n=>n.className==='asset-search-tag'&&n.textContent==='Kyoto');
 assert.equal(location.attrs['aria-label'],'Search Media for this location: Kyoto');
 assert(location.children.some(n=>n.className==='asset-tag-search-icon'&&n.attrs['aria-hidden']==='true'));
 assert(all.some(n=>n.className==='asset-file-details'&&!n.open));
 const cue=all.find(n=>n.className==='asset-transcript-row');cue.onclick();assert.equal(all.find(n=>n.tag==='video').currentTime,2);
 all.find(n=>n.className==='asset-search-tag'&&n.textContent==='Wok').onclick();
 assert.equal(nodes.mediaDetailDialog.open,false);assert.equal(nodes.librarySearch.value,'Wok');assert.equal(context.view,'all');assert(nodes.librarySearch.focused);
 location.onclick();assert.equal(nodes.librarySearch.value,'Kyoto');assert.equal(context.view,'all');
});
test('Missing understanding does not fabricate metadata prose or show empty transcript',()=>{
 const {all}=render({id:'empty',kind:'image',status:'ready',file:{name:'photo.jpg',size:32},metadata:{width:3000,height:2000},context:{device:'Camera'}});
 assert(all.some(n=>n.textContent==='No visual description yet.'));
 assert(!all.some(n=>n.textContent==='Transcript'||n.textContent==='Sound'));
 assert(!all.some(n=>/scene segments available|Add a description/.test(n.textContent)));
});
test('Overview gives compact content and clickable evidence without replacing full subtitles',()=>{
 const {all}=render(sample);assert(all.some(n=>n.textContent==='Video description'));assert(all.some(n=>n.textContent==='On screen'));
 const moment=all.find(n=>n.className==='asset-content-moment');assert(moment);moment.onclick();assert.equal(all.find(n=>n.tag==='video').currentTime,0);
 assert(all.some(n=>n.className==='asset-transcript-row'),'Complete transcript remains available');
});
