const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {kindOf,inCategory}=require('../public/library.js'),assets=require('../public/asset-understanding.js');
test('audio formats and exclusive categories',()=>{
 for(const name of ['voice.wav','song.mp3','audio.M4A','field.flac','recording.aiff'])assert.equal(kindOf({name,type:''}),'audio');
 const audio={kind:'audio',favorite:true};assert.equal(inCategory(audio,'favorites'),true);assert.equal(inCategory(audio,'audio'),true);assert.equal(inCategory(audio,'video'),false);
});
test('only actual contextual tags are used and searchable',()=>{
 const asset=assets.normalize({kind:'video',file:{name:'test.mp4'},context:{device:'Sony FX3',location:'Kyoto'},metadata:{width:1920,height:1080}});
 assert.deepEqual(assets.discoveryTags?assets.discoveryTags(asset):assets.buildAssetCard(asset).discoveryTags,['Sony FX3','Kyoto']);
 assert(assets.matches(asset,{},'Kyoto'));assert(assets.matches(asset,{},'Sony FX3'));
});
test('native composer remains isolated from web and persists real drafts',()=>{
 const source=fs.readFileSync('public/desktop-workspace.js','utf8');
 assert(source.includes('if(!window.PixfunDesktop)return'));
 for(const text of ['Project','Files & audio','From Media','Automatic video generation is not connected yet.','/api/desktop/projects'])assert(source.includes(text));
 assert(!source.includes('Project history'));
 assert(!source.includes("node('button','Audio')"),'Media does not add an Audio category');
 assert(!source.includes("dataset.libraryView='audio'"),'Audio import remains available only without a dedicated category');
 for(const text of ['Bring your footage. Describe your film.','Saved to Project','Brief saved on this Mac.','Your direction (optional)','Tell me the story, length, and style'])assert(!source.includes(text));
 assert(source.includes("node('details',null,'project-saved')"));assert(source.includes("node('summary','Saved brief')"));
 assert(!source.includes('saved.open=true'),'Saved content is collapsed by default');
 assert(source.includes("node('p',m.text)"),'Original project requests remain available');
 const placeholder=source.match(/placeholder="([^"]+)"/)[1];
 assert.equal(placeholder,'Describe your story, length, and style…');
 assert(placeholder.length<50,'One short line of guidance');
 for(const removed of ['promptExample','useExample','exampleBrief','Try a travel story','Use this idea'])assert(!source.includes(removed),'Remove the entire example and its event handlers');
 const css=fs.readFileSync('public/desktop.css','utf8');assert(css.includes('scrollbar-width:none'));assert(css.includes('scrollbar-gutter:auto'));
 const library=fs.readFileSync('public/library.js','utf8');assert(!library.includes('relatedFilters'));assert(library.includes("querySelectorAll('video,audio')"));
 assert(!library.includes('Restored to your library.'),'Restoring media does not leave a redundant success banner');
 assert(library.includes("await desktopRequest('restore',{id:item.id});await refreshDesktop();notice('');"),'Successful restore clears the undo notice');
});
