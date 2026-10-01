const {test}=require('node:test'),assert=require('node:assert/strict');
const {editingOverview,compactDescription}=require('../public/asset-understanding.js');
const base={id:'clip',kind:'video',file:{name:'travel.mp4'},metadata:{duration:120,width:1920,height:1080}};
test('Descriptions keep original detail while presenting a short readable overview',()=>{
 const text='A traveler walks through a busy market. '+ 'People prepare food beside the stalls. '.repeat(15);
 const item={...base,description:text,result:{analysis:{assetUnderstanding:{scene:['Market'],subjects:['Traveler'],actions:['Walking']}}}};
 const overview=editingOverview(item);assert(overview.summary.length<=241);assert.equal(overview.fullSummary,text.trim());assert.equal(overview.source,'Saved description');
 assert.deepEqual(overview.rows[0],['On screen','Market · Traveler']);assert.deepEqual(overview.rows[1],['Action','Walking']);
 assert(!JSON.stringify(overview).includes('1920'),'File specifications do not substitute for content');
 assert.equal(compactDescription('Short description.'),'Short description.');
});
test('Structured editing briefs stay structured and do not invent new advice',()=>{
 const overview=editingOverview({...base,description:'Theme: Family day out.\nKey shots: Trail walk and picnic.\nSuggested use: A quiet ending.\nWatch out: Wind noise.'});
 assert.equal(overview.summary,'Family day out.');assert.equal(overview.rows.length,1);assert(overview.editingNotes.some(([k,v])=>k==='Suggested use'&&v==='A quiet ending.'));assert(!overview.fullSummary.includes('Wind noise'),'Nonvisual notes live outside the video description');
});
test('Absent visual recognition never borrows subtitles for the video description',()=>{
 const cues=[{start:0,end:3,text:'We are visiting the park today'},{start:3,end:6,text:'to learn about archaeology.'},{start:45,end:49,text:'This layer is exposed along the river.'},{start:90,end:95,text:'Please leave anything you find in place.'}];
 const overview=editingOverview({...base,result:{analysis:{subtitleCues:cues,segments:[{id:'one',start:0,end:120,label:'Exciting highlight'}]}}});
 assert.equal(overview.summary,'');assert.equal(overview.hasVisualContent,false);assert.deepEqual(overview.moments,[]);
 assert(!JSON.stringify(overview).includes('archaeology'));assert(!JSON.stringify(overview).includes('Exciting highlight'));
});
test('Scene notes provide grounded timestamps; technical-only files remain honest',()=>{
 const item={...base,result:{analysis:{segments:[{id:'a',start:0,end:30,assetUnderstanding:{title:'Market arrival',summary:'People walk between food stalls.'}},{id:'b',start:30,end:90}]}},sceneNotes:{b:{title:'Lunch stop',description:'A shared meal.'}}};
 const overview=editingOverview(item);assert.equal(overview.momentLabel,'Scene notes');assert.equal(overview.moments[1].start,30);assert.equal(overview.moments[1].source,'Saved note');
 const empty=editingOverview(base);assert.equal(empty.summary,'');assert.deepEqual(empty.rows,[]);assert.deepEqual(empty.moments,[]);
});
test('Transcript excerpts are not shown in descriptions even with substantive dialogue',()=>{
 const overview=editingOverview({...base,result:{analysis:{subtitleCues:[{start:0,end:3,text:'Hey everybody, welcome to our science day and thank you for joining us today.'},{start:10,end:15,text:'These objects must stay where they were found, because their position helps us understand the history of this place.'},{start:110,end:115,text:'Happy science day! Bye!'}]}}});
 assert.equal(overview.moments.length,0);assert.equal(overview.summary,'');
});
