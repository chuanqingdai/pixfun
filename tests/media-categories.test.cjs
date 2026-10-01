const assert=require('node:assert/strict');
const {inCategory}=require('../public/library.js');
const assets=require('../public/asset-understanding.js');
const items=[
  {id:'v1',kind:'video',favorite:true,file:{name:'Coast.mp4'},metadata:{width:1920,height:1080}},
  {id:'v2',kind:'video',favorite:false,file:{name:'City.mp4'}},
  {id:'p1',kind:'image',favorite:true,file:{name:'Mountain.jpg'}},
  {id:'p2',kind:'image',file:{name:'Cafe.jpg'}}
];
const visible=(category,query='')=>items.filter(item=>inCategory(item,category)&&assets.matches(assets.normalize(item),{},query)).map(i=>i.id);
assert.deepEqual(visible('all'),['v1','v2','p1','p2']);
assert.deepEqual(visible('video'),['v1','v2']);
assert.deepEqual(visible('image'),['p1','p2']);
assert.deepEqual(visible('favorites'),['v1','p1'],'Favorites includes both types, independent of previous category');
assert.deepEqual(visible('video'),['v1','v2'],'Switching away does not retain a favorite constraint');
assert.deepEqual(visible('favorites','Mountain'),['p1']);
assert.deepEqual(visible('all','Landscape'),['v1'],'Card tags remain searchable');
items[0].favorite=false;
assert.deepEqual(visible('favorites'),['p1'],'Unstarring removes an item from Favorites immediately');
assert.deepEqual(visible('unknown'),[]);
console.log('PASS: Four exclusive media categories, mixed-type Favorites, search, and unstar behavior.');
