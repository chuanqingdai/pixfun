const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {skills,buildBrief}=require('../public/desktop-skills.js');
test('every skill begins with a distinct scope and a boundary',()=>{
 assert.equal(new Set(skills.map(s=>s.applicability)).size,skills.length);
 for(const skill of skills){
  assert(skill.applicability && skill.notFor);
  const brief=buildBrief(skill,'');
  assert(brief.startsWith(`${skill.title}\nBest for: ${skill.applicability}\nNot for: ${skill.notFor}`));
  assert(brief.indexOf('Best for:')<brief.indexOf('Story framework:'));
 }
 const native=fs.readFileSync('native/Sources/Pixfun/SkillsView.swift','utf8');
 assert(native.indexOf('skill.applicability')<native.indexOf('Story framework'));
});
test('all skill covers use distinct real photography with recorded sources',()=>{
 const crypto=require('node:crypto');
 const provenance=require('../public/media/travel/skill-photo-covers.json');
 assert.equal(new Set(skills.map(skill=>skill.image)).size,skills.length);
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
 assert.equal(new Set(hashes).size,skills.length);
});
test('ten creator skills carry material-specific editorial strategies',()=>{
 assert.equal(skills.length,10);assert.equal(new Set(skills.map(t=>t.id)).size,10);
 for(const skill of skills){assert(skill.structure.length>=3);assert.equal(skill.materials.length,2);assert(skill.sound&&skill.pacing&&skill.avoid);assert(fs.existsSync(`public/media/travel/${skill.image}.jpg`));assert(!skill.stage);}
 const food=skills.find(skill=>skill.id==='food-tour');
 const brief=buildBrief(food,'Keep it under 3 minutes.');assert(brief.includes('Food tour'));assert(brief.includes(food.sound));assert(brief.includes(food.beats[0]));assert(brief.includes('Keep it under 3 minutes.'));
 assert(buildBrief(skills[0],'').includes('Use the strategy above'));
 for(const skill of skills){assert(skill.value&&skill.example);assert.equal(skill.beats.length,skill.structure.length);assert.equal(skill.handling.length,2);assert(buildBrief(skill,'').length<=4000);assert(buildBrief(skill,'x'.repeat(2500)).length<=5000);}
});
test('Travel Short is second without a badge and exposes the planning specification',()=>{
 assert.equal(skills[0].id,'visionflow-travel-director');
 const skill=skills[1];assert.equal(skill.id,'visionflow-travel-short');assert(!skill.featured);
 assert.equal(skill.version,'1.1');assert.equal(skill.workflow.length,9);assert.equal(skill.templates.length,6);
 assert.equal(new Set(skill.templates.map(t=>t.title)).size,6);
 assert.equal(skill.materialCases.length,3);assert(skill.materialCases[0].title.includes('3 photos'));
 assert.equal(skill.actionTitle,'Use this skill');assert(skill.capabilityNote.includes('single-panel layouts'));
 assert(skill.capabilityNote.includes('not yet rendering presets'));
 assert(buildBrief(skill,'').includes('Honor the requested outcome'));
 const path=require('node:path'),root=path.join('creator-skills',path.dirname(skill.source));
 const source=fs.readFileSync(path.join('creator-skills',skill.source),'utf8');
 for(const ref of ['packaging-templates.md','material-adaptation.md']){
  assert(source.includes(`references/${ref}`));assert(fs.statSync(path.join(root,'references',ref)).size>1000);
 }
 assert(fs.readFileSync('scripts/build-native.cjs','utf8').includes("path.join(path.dirname(destination), 'references')"));
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
