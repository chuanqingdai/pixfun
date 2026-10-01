const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('public/desktop-workspace.js','utf8');
const removeSource=source.slice(source.indexOf('  function removeAttachment('),source.indexOf('  function renderAttachments('));
function fixture(count=7){
 const calls=[],media=Array.from({length:count},(_,i)=>({id:String(i),name:`Clip ${i}.mp4`}));
 const strip={scrollLeft:100},announcement={textContent:''},prompt={value:'Keep this story',focus:()=>calls.push('prompt-focus')};
 const context={busy:false,attachments:media.slice(),renderAttachments:()=>calls.push('render'),stash:()=>calls.push('save'),$:id=>id==='projectPrompt'?prompt:id==='projectSaveAnnouncement'?announcement:{querySelector:()=>strip,querySelectorAll:()=>context.attachments.map(a=>({focus:()=>calls.push(`focus-${a.id}`)}))}};
 vm.createContext(context);vm.runInContext(removeSource,context);
 return {context,calls,media,prompt,strip,announcement};
}
test('Inline removal affects only the attachment reference, including items beyond the first four',()=>{
 const f=fixture();f.context.removeAttachment('5');
 assert.equal(f.context.attachments.length,6);assert(!f.context.attachments.some(a=>a.id==='5'));
 assert.equal(f.media.length,7,'Original Media records remain intact');
 assert.equal(f.prompt.value,'Keep this story');assert.equal(f.strip.scrollLeft,100);
 assert.deepEqual(f.calls,['render','save','focus-6']);
 assert.match(f.announcement.textContent,/removed from this prompt/);
 assert(!removeSource.includes('fetch('));assert(!removeSource.includes('library.'));
});
test('Removing the last attachment returns focus to the prompt; stale IDs and busy saves are safe',()=>{
 const f=fixture(1);f.context.removeAttachment('missing');assert.equal(f.calls.length,0);
 f.context.busy=true;f.context.removeAttachment('0');assert.equal(f.context.attachments.length,1);
 f.context.busy=false;f.context.removeAttachment('0');assert.equal(f.context.attachments.length,0);
 assert.deepEqual(f.calls,['render','save','prompt-focus']);
});
test('Delete is a separate non-submit button revealed by hover, keyboard focus or touch',()=>{
 assert(source.includes("remove.type='button'"));assert(source.includes('Remove ${a.name} from prompt'));
 assert(source.includes("remove.onclick=()=>removeAttachment(a.id)"));
 const css=fs.readFileSync('public/desktop.css','utf8');
 assert(css.includes('.attachment-tile:hover .attachment-remove,.attachment-tile:focus-within .attachment-remove'));
 assert(css.includes('@media(hover:none),(pointer:coarse)'));
 assert(css.includes('#projectComposer #projectPrompt:focus-visible { outline:none!important;box-shadow:none!important;border:0; }'));
 assert(css.includes('.project-composer:focus-within { border-color:var(--line); }'));
 assert(css.includes('.attachment-remove:focus-visible'),'Other controls keep keyboard focus feedback');
});
