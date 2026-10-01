const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync(require('node:path').join(__dirname,'../public/library.js'),'utf8');
class Element {
  constructor(tag,text,cls=''){this.tag=tag;this.textContent=text;this.className=cls;this.children=[];this.attrs={};this.dataset={};this.styles={};this.style={setProperty:(k,v)=>this.styles[k]=v};this.classList={add:c=>this.className+=' '+c};}
  append(...children){this.children.push(...children);}
  setAttribute(k,v){this.attrs[k]=v;}
  querySelector(selector){return this.children.find(c=>selector.startsWith('.')?c.className.split(' ').includes(selector.slice(1)):c.dataset.mediaId===selector.match(/"(.*)"/)[1])||this.children.map(c=>c.querySelector(selector)).find(Boolean);}
}
const grid=new Element('div');
const context=vm.createContext({el:(...args)=>new Element(...args),document:{createElementNS:(_,tag)=>new Element(tag)},cover:()=>new Element('span',null,'media-cover'),assets:require('../public/asset-understanding.js'),mediaInfo:require('../public/media-metadata.js'),selected:null,selection:null,selectedSegment:null,size:()=> '2 MB',select:()=>{},byId:()=>grid});
const declarations=source.slice(source.indexOf('  const labels ='),source.indexOf("  if(typeof document"));
const tile=source.slice(source.indexOf('  function tile('),source.indexOf('  function render()'));
const update=source.slice(source.indexOf('  function updateTileProgress('),source.indexOf('  async function processQueue()'));
const badge=source.slice(source.indexOf('  function captureBadge('),source.indexOf('  function cover('));
vm.runInContext(declarations+badge+tile+update+';this.makeTile=tile;this.update=updateTileProgress;',context);
const item={id:'qa-video',file:{name:'trip.mp4',size:2000},status:'queued'};
for(const status of ['queued','reading','uploading','analyzing']){
  item.status=status;item.uploadPercent=null;
  const card=context.makeTile(item);
  assert.ok(card.querySelector('.media-import-overlay'),status+' is shown within the card');
  assert.equal(card.querySelector('.media-state'),undefined,'No duplicate loading caption');
  if(status==='uploading'){
    grid.children=[card];item.uploadPercent=47;context.update(item);
    assert.equal(grid.children[0],card,'Upload progress does not rebuild the card');
    assert.equal(card.querySelector('.media-import-label').textContent,'Uploading 47%');
    assert.equal(card.querySelector('.media-import-bar').attrs['aria-valuenow'],'47');
    assert.equal(card.querySelector('.media-import-bar').styles['--upload-progress'],'47%');
  }
}
for(const status of ['ready','error','cancelled']){
  item.status=status;
  const card=context.makeTile(item);
  assert.equal(card.querySelector('.media-import-overlay'),undefined,status+' removes the loading overlay');
  if(status!=='ready')assert.ok(card.querySelector('.media-state').textContent);
  assert.equal(card.dataset.mediaId,item.id,'The same media identity is kept');
}
grid.children=[];assert.doesNotThrow(()=>context.update(item),'Filtering or leaving Media during upload is safe');
const semantic=context.makeTile({...item,status:'ready',kind:'video',metadata:{duration:28,width:3840,height:2160},assetUnderstanding:{summary:'Waves beneath a coastal cliff',capture:{cameraMode:'drone',shotSize:'wide',cameraMotion:'push'},editing:{shotRole:'establishing',importance:.95},quality:{issues:['Slight shake']}}});
assert.equal(semantic.querySelector('.shot-title').textContent,'trip');
assert.equal(semantic.querySelector('.shot-summary').textContent,'Waves beneath a coastal cliff');
assert.equal(semantic.querySelector('.shot-capture').children[0].tag,'svg');
assert.equal(semantic.querySelector('.shot-role').textContent,'Establishing');
assert.equal(semantic.querySelector('.shot-edit-tags').children.length,3);
assert.equal(semantic.querySelector('.shot-quality-warning').textContent,'Slight shake');
assert.equal(semantic.querySelector('.shot-filename'),undefined,'Semantic card filename stays in tooltip/details');
console.log('PASS: Inline queued, reading, upload percentage, analyzing, ready, failure and stopped states; targeted updates and hidden cards.');
