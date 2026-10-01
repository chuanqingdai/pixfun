(() => {
  'use strict';
  const $=id=>document.getElementById(id);
  const backgrounds={enthusiast:'旅游爱好者',creator:'平台创作者',editor:'独立导演 / 剪辑师',studio:'工作室 / 制作团队',brand:'品牌 / 营销团队',other:'其他',legacy:'未填写（历史申请）'};
  const platforms={youtube:'YouTube',tiktok:'TikTok',instagram:'Instagram',bilibili:'Bilibili',xiaohongshu:'RedNote',other:'其他'};
  const budgets={free:'仅免费','1-9':'$1–9','10-19':'$10–19','20-39':'$20–39','40-69':'$40–69','70+':'$70+',unsure:'暂不确定'};
  const legacyTypes={travel:'旅游',outdoor:'户外',family:'家庭',commercial:'商业',other:'其他'};
  let rows=[],filtered=[];
  function budgetKey(row){if(budgets[row.budget_range])return row.budget_range;const n=row.monthly_usd;return n==null?'unsure':n===0?'free':n<10?'1-9':n<20?'10-19':n<40?'20-39':n<70?'40-69':'70+';}
  function budgetText(row){return row.budget_range?budgets[row.budget_range]:row.monthly_usd==null?'暂不确定':`$${row.monthly_usd}（原填写金额）`;}
  function platformText(row){return (row.platforms||'').split(',').filter(Boolean).map(p=>platforms[p]||p).join(' · ');}
  function el(tag,text){const node=document.createElement(tag);if(text!=null)node.textContent=text;return node;}
  function render(){
    const query=$('applicationSearch').value.trim().toLowerCase(),role=$('backgroundFilter').value,budget=$('budgetFilter').value;
    filtered=rows.filter(row=>(role==='all'||(row.background||'legacy')===role)&&(budget==='all'||budgetKey(row)===budget)&&[row.email,row.need,platformText(row)].join(' ').toLowerCase().includes(query));
    $('applicationRows').replaceChildren();
    for(const row of filtered){
      const tr=el('tr'),identity=el('td'),roleCell=el('td'),price=el('td',budgetText(row)),need=el('td');
      const email=el('a',row.email);email.href='mailto:'+encodeURIComponent(row.email);identity.append(email,el('small',new Date(row.created_at).toLocaleString('zh-CN')));
      roleCell.append(el('span',backgrounds[row.background||'legacy']||'其他'));
      const context=row.background?platformText(row):'原素材类型：'+(legacyTypes[row.creator_type]||'其他');if(context)roleCell.append(el('small',context));
      const preview=el('p',row.need);preview.className='need-preview';need.append(preview);
      const details=el('details');details.append(el('summary','查看完整需求'),el('p',row.need));need.append(details);
      tr.append(identity,roleCell,price,need);$('applicationRows').append(tr);
    }
    $('applicationCount').textContent=`${filtered.length} / ${rows.length} 位申请者`;
    $('applicationEmpty').hidden=filtered.length>0;
    $('applicationEmpty').textContent=rows.length?'没有匹配的申请，试试调整筛选条件。':'还没有申请。问卷提交后会自动汇总到这里。';
    $('exportApplications').disabled=!filtered.length;
  }
  async function load(){
    $('refreshApplications').disabled=true;$('adminStatus').hidden=false;$('adminStatus').className='';$('adminStatus').textContent='正在读取申请…';$('adminContent').hidden=true;
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);
    try{
      const response=await fetch('/api/admin/mac-applications',{cache:'no-store',signal:controller.signal});const data=await response.json();
      if(!response.ok||!data.ok||!Array.isArray(data.applications))throw new Error('load');rows=data.applications;
      $('totalApplications').textContent=rows.length;$('recentApplications').textContent=rows.filter(r=>Date.parse(r.created_at)>=Date.now()-7*86400000).length;
      $('paidApplications').textContent=rows.filter(r=>!['free','unsure'].includes(budgetKey(r))).length;
      $('budgetDistribution').replaceChildren();
      for(const [key,label] of Object.entries(budgets)){const count=rows.filter(r=>budgetKey(r)===key).length,cell=el('div');cell.className='budget-cell';const meter=el('meter');meter.min=0;meter.max=Math.max(rows.length,1);meter.value=count;meter.setAttribute('aria-label',label);cell.append(el('span',label),el('strong',String(count)),meter);$('budgetDistribution').append(cell);}
      render();$('adminContent').hidden=false;$('adminStatus').hidden=true;
    }catch{$('adminStatus').className='admin-error';$('adminStatus').textContent='无法读取申请。请在运行 Pixfun 的本机打开此页面，然后重试。';}
    finally{clearTimeout(timer);$('refreshApplications').disabled=false;}
  }
  // Quote every cell and neutralize spreadsheet formulas in all untrusted fields.
  function csvCell(value){let text=String(value??'');if(/^[\s\uFEFF]*[=+@-]/u.test(text)||/^[\t\r\n]/.test(text))text="'"+text;return '"'+text.replace(/"/g,'""')+'"';}
  $('exportApplications').addEventListener('click',()=>{
    const records=[['提交时间','邮箱','个人背景','发布平台','创作需求','月预算（USD）'],...filtered.map(r=>[r.created_at,r.email,backgrounds[r.background||'legacy'],platformText(r),r.need,budgetText(r)])];
    const blob=new Blob(['\uFEFF'+records.map(r=>r.map(csvCell).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=el('a');a.href=url;a.download=`pixfun-applications-${new Date().toISOString().slice(0,10)}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  });
  $('applicationSearch').addEventListener('input',render);$('backgroundFilter').addEventListener('change',render);$('budgetFilter').addEventListener('change',render);$('refreshApplications').addEventListener('click',load);load();
})();
