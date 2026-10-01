/* Shortest-column masonry; DOM/focus order remains the media's original order. */
(() => {
  'use strict';
  function positions(heights, columns, width, gap=18){
    columns=Math.max(1,Math.floor(columns));
    const columnWidth=Math.max(0,(width-gap*(columns-1))/columns),bottoms=Array(columns).fill(0);
    const cards=heights.map(height=>{
      const column=bottoms.indexOf(Math.min(...bottoms)),y=bottoms[column];
      bottoms[column]=y+height+gap;
      return {x:column*(columnWidth+gap),y,width:columnWidth};
    });
    return {cards,height:heights.length?Math.max(...bottoms)-gap:0};
  }
  function mount(grid){
    if(!grid||typeof ResizeObserver==='undefined')return;
    let frame=0,lastWidth=-1,children=new Set();
    const sizes=new WeakMap();
    const schedule=()=>{if(!frame)frame=requestAnimationFrame(layout);};
    const resize=new ResizeObserver(entries=>{
      for(const {target,contentRect}of entries){
        if(target===grid){if(Math.abs(contentRect.width-lastWidth)>.5)schedule();}
        else if(Math.abs(contentRect.height-(sizes.get(target)??-1))>.5){sizes.set(target,contentRect.height);schedule();}
      }
    });
    function layout(){
      frame=0;
      const width=grid.clientWidth;if(!width)return;
      lastWidth=width;
      const style=getComputedStyle(grid),columns=Number(style.getPropertyValue('--masonry-columns'))||4,gap=parseFloat(style.columnGap)||18;
      const cards=Array.from(grid.children);
      const itemWidth=Math.max(0,(width-gap*(columns-1))/columns);
      grid.dataset.masonry='true';
      cards.forEach(card=>{card.style.width=`${itemWidth}px`;});
      const result=positions(cards.map(card=>card.getBoundingClientRect().height),columns,width,gap);
      cards.forEach((card,index)=>{const p=result.cards[index];card.style.transform=`translate(${p.x}px, ${p.y}px)`;});
      grid.style.height=`${result.height}px`;
    }
    function refresh(){
      const next=new Set(grid.children);
      children.forEach(card=>{if(!next.has(card))resize.unobserve(card);});
      next.forEach(card=>{if(!children.has(card))resize.observe(card);});
      children=next;schedule();
    }
    const mutations=new MutationObserver(refresh);mutations.observe(grid,{childList:true});
    resize.observe(grid);window.addEventListener('resize',schedule,{passive:true});refresh();
    return ()=>{cancelAnimationFrame(frame);resize.disconnect();mutations.disconnect();window.removeEventListener('resize',schedule);};
  }
  if(typeof module!=='undefined'&&module.exports){module.exports={positions};return;}
  window.PixfunMasonry={mount};
})();
