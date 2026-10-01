const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {skills,buildBrief}=require('../public/desktop-skills.js');
test('all skill covers use distinct real photography with recorded sources',()=>{
 const crypto=require('node:crypto');
 const provenance=require('../public/media/travel/skill-photo-covers.json');
 assert.equal(new Set(skills.map(skill=>skill.image)).size,9);
 const hashes=skills.map(skill=>{
  assert.match(skill.image,/^skill-.+-photo-v3$/);
  const cover=provenance.covers.find(cover=>cover.id===skill.id);
  assert.equal(cover.image,skill.image);assert.equal(cover.kind,'real stock footage still');
  assert(/^https:\/\/(mixkit.co\/free-stock-video\/|www.pexels.com\/video\/)/.test(cover.url));
  const data=fs.readFileSync(`public/media/travel/${skill.image}.jpg`);
  assert.equal(data.readUInt16BE(0),0xffd8,'Cover must be a JPEG');
  assert(data.length>20000,'Cover must not be an empty placeholder');
  return crypto.createHash('sha256').update(data).digest('hex');
 });
 assert.equal(new Set(hashes).size,9);
});
test('nine creator skills carry material-specific editorial strategies',()=>{
 assert.equal(skills.length,9);assert.equal(new Set(skills.map(t=>t.id)).size,9);
 for(const skill of skills){assert(skill.structure.length>=3);assert.equal(skill.materials.length,2);assert(skill.sound&&skill.pacing&&skill.avoid);assert(fs.existsSync(`public/media/travel/${skill.image}.jpg`));assert(!skill.stage);}
 const food=skills.find(skill=>skill.id==='food-tour');
 const brief=buildBrief(food,'Keep it under 3 minutes.');assert(brief.includes('Food tour'));assert(brief.includes(food.sound));assert(brief.includes(food.beats[0]));assert(brief.includes('Keep it under 3 minutes.'));
 assert(buildBrief(skills[0],'').includes('Use the strategy above'));
 for(const skill of skills){assert(skill.value&&skill.example);assert.equal(skill.beats.length,skill.structure.length);assert.equal(skill.handling.length,2);assert(buildBrief(skill,'').length<=4000);assert(buildBrief(skill,'x'.repeat(2500)).length<=5000);}
});
test('travel Vlog preserves the full versioned specification separately from the concise brief',()=>{
 const skill=skills.find(skill=>skill.id==='visionflow-travel-director');
 assert.equal(skill.version,'5.4');assert.equal(skill.highlights.length,6);
 const source=fs.readFileSync(`creator-skills/${skill.source}`,'utf8');
 assert(source.includes('version: "5.4"'));assert(source.includes('## 9. 成片质检、修复与交付'));
 assert(source.length>20000);assert(buildBrief(skill,'').includes(`CreatorSkills/${skill.source}`));
 assert(skill.pacing.includes('not a fixed runtime'));assert(skill.handling[0].includes('every usable unique file'));
 const builder=fs.readFileSync('scripts/build-native.cjs','utf8');assert(builder.includes("'CreatorSkills', skill.source"));
 const detail=fs.readFileSync('native/Sources/Pixfun/SkillsView.swift','utf8');
 assert(detail.includes('Key principles'));assert(detail.includes('specificationURL'));
});
test('native creator skills hand off to Home, not a second input or automatic submission',()=>{
 const js=fs.readFileSync('public/desktop-skills.js','utf8');
 for(const text of ['if(!window.PixfunDesktop)return','Creator skills','useSkill','Use skill','Automatic editing is not connected yet.'])assert(js.includes(text),text);
 assert(!js.includes('Your direction (optional)'));assert(!js.includes("node('textarea')"));assert(!js.includes('/api/desktop/projects'));
 assert(!js.includes('setTimeout'),'No simulated generation');assert(!js.includes('aria-pressed'),'No default style selection');
 const workspace=fs.readFileSync('public/desktop-workspace.js','utf8');assert(workspace.includes('skill:activeSkill'));assert(workspace.includes('renderSkill();stash();library.navigate(\'home\')'));
});
test('using a skill keeps text and attachments, focuses Home, and does not save a project',()=>{
 const vm=require('node:vm'),source=fs.readFileSync('public/desktop-workspace.js','utf8');
 const text={value:'Keep this unsent request',focus(){this.focused=true;}},calls=[];
 const context={validSkill:()=>true,busy:false,activeSkill:null,renderSkill:()=>calls.push('render'),stash:()=>calls.push('draft'),library:{navigate:page=>calls.push(page)},status:()=>{},$:()=>text};
 const run=vm.runInNewContext(source.slice(source.indexOf('  function useSkill('),source.indexOf('  window.PixfunWorkspace='))+';useSkill',context);
 run({id:'city-walk',title:'City walk',strategy:'A route-led story'});assert.equal(text.value,'Keep this unsent request');assert(text.focused);assert.deepEqual(calls,['render','draft','home']);assert.equal(context.activeSkill.title,'City walk');
});
