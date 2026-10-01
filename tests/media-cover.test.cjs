const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('public/library.js','utf8');
function cover(item){
 const context={item,duration:n=>String(n),el:(tag,text,cls)=>({tag,text,cls,children:[],style:{setProperty(k,v){this[k]=v;}},events:{},append(...children){this.children.push(...children)},addEventListener(name,fn){this.events[name]=fn;}})};
 vm.runInNewContext(source.slice(source.indexOf('  function cover('),source.indexOf('  function select('))+';result=cover(item);',context);
 return context.result;
}
test('Portrait covers retain native ratio and do not stretch legacy cropped thumbnails',()=>{
 const item={kind:'video',status:'ready',url:'original.mp4',metadata:{width:1080,height:1920},result:{analysis:{segments:[{thumbnailUrl:'cropped.jpg'}]}}};
 const result=cover(item);assert.equal(result.style['--media-ratio'],'1080 / 1920');assert.equal(result.children[0].tag,'video');assert.match(result.children[0].src,/original.mp4/);
 item.result.analysis.segments[0].thumbnailFit='native';
 const updated=cover(item);assert.equal(updated.children[0].tag,'img');assert.equal(updated.children[0].src,'cropped.jpg');
});
test('Landscape, square and loading media keep their own dimensions',()=>{
 for(const [width,height]of [[1920,1080],[3000,3000]]){
  const result=cover({kind:'image',url:'photo.jpg',metadata:{width,height}});assert.equal(result.style['--media-ratio'],`${width} / ${height}`);
 }
 const result=cover({kind:'video',url:'phone.mov'}),video=result.children[0];
 video.videoWidth=1080;video.videoHeight=1920;video.events.loadedmetadata();assert.equal(result.style['--media-ratio'],'1080 / 1920');
});
