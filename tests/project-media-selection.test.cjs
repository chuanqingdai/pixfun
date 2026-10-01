const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {createSelection,inCategory}=require('../public/library.js');
test('Selection is a separate draft that persists across media categories and search',()=>{
 const attachments=['video-a','photo-b'],draft=createSelection(attachments);
 draft.toggle('video-c');draft.toggle('photo-b');
 for(const category of ['all','video','image','favorites']){
  [{id:'video-a',kind:'video'},{id:'photo-b',kind:'image'}].filter(i=>inCategory(i,category));
  assert.deepEqual(draft.values(),['video-a','video-c']);
 }
 assert.deepEqual(attachments,['video-a','photo-b'],'Cancel never mutates committed attachments');
 const snapshot=draft.values();snapshot.push('external');assert(!draft.has('external'));
});
test('Selection deduplicates, supports clearing and enforces the 100-file limit',()=>{
 const draft=createSelection(['a','a']);assert.deepEqual(draft.values(),['a']);draft.toggle('a');assert.deepEqual(draft.values(),[]);
 for(let i=0;i<100;i++)assert(draft.toggle(String(i)));
 assert.equal(draft.toggle('overflow'),false);assert.equal(draft.values().length,100);
 assert(draft.toggle('0'));assert(draft.toggle('new'));assert.equal(draft.values().length,100);
});
test('From Media hands off to the existing grid and only commits on confirmation, keeping the prompt',()=>{
 const source=fs.readFileSync('public/desktop-workspace.js','utf8');
 let confirm,selectedIds;const calls=[],prompt={value:'Keep my story',focus(){calls.push('focus');}};
 const context={busy:false,attachments:[{id:'a',name:'A.mp4',kind:'video'}],library:{startSelection:(ids,fn)=>{selectedIds=ids;confirm=fn;},getItems:()=>[{id:'a',file:{name:'A.mp4'},kind:'video'},{id:'b',file:{name:'B.jpg'},kind:'image'}],navigate:p=>calls.push(p)},renderAttachments:()=>calls.push('render'),stash:()=>calls.push('stash'),status:()=>{},$:()=>prompt};
 vm.runInNewContext(source.slice(source.indexOf('  function chooseMedia('),source.indexOf("  $('attachLibrary').onclick="))+';chooseMedia();',context);
 assert.equal(selectedIds.join(','),'a');assert.equal(calls.length,0);assert.equal(context.attachments[0].id,'a');
 confirm(['b']);assert.equal(context.attachments[0].name,'B.jpg');assert.equal(prompt.value,'Keep my story');assert.deepEqual(calls,['render','stash','home','focus']);
 confirm([]);assert.equal(context.attachments.length,0,'Confirming zero files clears attachments');
 assert(!source.includes('project-media-picker'));assert(!source.includes('projectMediaChoices'));
  assert(source.includes('for(const a of attachments)'));assert(source.includes('library.createCover(item)'));
});
test('Media and Home share the same project-media selection entry point',()=>{
 const library=fs.readFileSync('public/library.js','utf8'),workspace=fs.readFileSync('public/desktop-workspace.js','utf8');
 assert(library.includes("selectForProject.onclick=()=>window.PixfunWorkspace?.chooseMedia()"));
 assert(library.includes("selectionDone=el('button','Use in prompt'"));
 assert(library.includes("byId('mediaImportActions').hidden=page!=='media'||!!selection"),'Import actions hide only while choosing project media');
 assert(workspace.includes("$('attachLibrary').onclick=chooseMedia"));
 assert(workspace.includes('window.PixfunWorkspace={attach,useSkill,chooseMedia}'));
});
