const {test}=require('node:test'),assert=require('node:assert/strict');
const {positions}=require('../public/media-masonry.js');
test('Unequal cards pack into the shortest column without row-height gaps',()=>{
 const result=positions([200,400,250,100,300],3,936,18);
 assert.deepEqual(result.cards.map(p=>[p.x,p.y]),[[0,0],[318,0],[636,0],[0,218],[636,268]]);
 assert.equal(result.height,568);assert.equal(result.cards[0].width,300);
});
test('Resize, empty and filtered sets recompute bounds without overlaps',()=>{
 for(const columns of [1,2,3,4]){
  const heights=[180,500,240,220,410,210,510,210,120],result=positions(heights,columns,940,18);
  result.cards.forEach((card,index)=>{
   assert(card.x+card.width<=940.001);assert(card.y+heights[index]<=result.height+.001);
   result.cards.slice(0,index).forEach((other,j)=>{if(card.x===other.x)assert(card.y>=other.y+heights[j]+18);});
  });
 }
 assert.deepEqual(positions([],4,940),{cards:[],height:0});
 assert.equal(positions([180],4,940).height,180);
});
