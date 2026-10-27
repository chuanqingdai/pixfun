'use strict';
// Build an isolated UI fixture; launch it through the normal UI automation tools.
const fs = require('node:fs'), path = require('node:path'), {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const skillsPreview = process.argv.includes('--skills');
const speechPreview = process.argv.includes('--speech');
const transitionsPreview = process.argv.includes('--transitions');
const conversationPreview = process.argv.includes('--conversation');
const mediaPreview = process.argv.includes('--media');
const syncPreview = process.argv.includes('--media-sync');
const graphicsPreview = process.argv.includes('--graphics');
const sidebarPreview = process.argv.includes('--sidebar');
const editorPreview = process.argv.includes('--editor');
const uxPreview = process.argv.includes('--ux');
const snapshot = skillsPreview && process.argv.includes('--snapshot');
const name = speechPreview ? 'StorySpeechSmoke' : sidebarPreview ? 'SidebarLayout' : graphicsPreview ? 'GraphicsLayout' : syncPreview ? 'MediaSyncLayout' : uxPreview ? 'UXCoreLayout' : editorPreview ? 'EditorP0Layout' : mediaPreview ? 'MediaLayout' : conversationPreview ? 'ConversationLayout' : transitionsPreview ? 'StoryTransitionLayout' : snapshot ? 'SkillsLayout' : skillsPreview ? 'SkillsSmoke' : 'StoryPopoverSmoke';
const app = path.join(root, `build-native/${name}.app`);
const contents = path.join(app, 'Contents');
fs.mkdirSync(path.join(contents, 'MacOS'), {recursive: true});
fs.cpSync(path.join(root, 'native/Localization'), path.join(contents, 'Resources'), {recursive:true});
const source = 'native/Sources/Pixfun';
const result = spawnSync('swiftc', ['-parse-as-library', '-D', 'PIXFUN_LAYOUT_TEST', '-target', `${process.arch === 'arm64' ? 'arm64' : 'x86_64'}-apple-macosx13.0`, '-module-cache-path', path.join(root, 'build-native/cache/clang'),
  ...(snapshot ? ['-D','PIXFUN_SKILLS_SNAPSHOT'] : []),
  ...fs.readdirSync(path.join(root, source)).filter(f => f.endsWith('.swift')).map(f => `${source}/${f}`),
  `native/Tests/${speechPreview ? 'StorySpeechSmokeApp' : sidebarPreview ? 'SidebarSmokeApp' : graphicsPreview ? 'GraphicsSmokeApp' : syncPreview ? 'MediaSyncSmokeApp' : uxPreview ? 'UXCoreSmokeApp' : editorPreview ? 'EditorP0SmokeApp' : mediaPreview ? 'MediaSmokeApp' : conversationPreview ? 'ConversationSmokeApp' : transitionsPreview ? 'StoryTransitionSmokeApp' : skillsPreview ? 'SkillsSmokeApp' : 'StoryPopoverSmokeApp'}.swift`, '-o', path.join(contents, 'MacOS', name)], {cwd: root, stdio: 'inherit'});
if (result.status !== 0) process.exit(result.status || 1);
fs.writeFileSync(path.join(contents, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>${name}</string><key>CFBundleIdentifier</key><string>com.pixfun.${name.toLowerCase()}</string><key>CFBundleName</key><string>${name}</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>`);
if (skillsPreview) {
  const resources=path.join(contents,'Resources');
  fs.mkdirSync(path.join(resources,'SkillCovers'),{recursive:true});
  const {skills,buildBrief}=require('../public/desktop-skills.js');
  fs.writeFileSync(path.join(resources,'skills.json'),JSON.stringify(skills.map(s=>({...s,strategy:buildBrief(s,'')}))));
  for (const s of skills.filter(s=>s.image)) fs.copyFileSync(path.join(root,`public/media/travel/${s.image}.jpg`),path.join(resources,`SkillCovers/${s.image}.jpg`));
  fs.cpSync(path.join(root,'creator-skills'),path.join(resources,'CreatorSkills'),{recursive:true});
}
console.log(app);
if (sidebarPreview || mediaPreview) {
  const resources = path.join(contents, 'Resources');
  fs.mkdirSync(path.join(resources, 'Brand'), {recursive:true});
  fs.cpSync(path.join(root, 'native/Welcome/Assets'), path.join(resources, 'Welcome'), {recursive:true});
  fs.mkdirSync(path.join(resources, 'Fonts'), {recursive:true});
  fs.copyFileSync(path.join(root, 'public/images/pixfun-lockup-v2.png'), path.join(resources, 'Brand/pixfun-lockup-v2.png'));
  for (const font of ['dm-sans-regular.ttf','dm-sans-semibold.ttf']) fs.copyFileSync(path.join(root, 'public/fonts', font), path.join(resources, 'Fonts', font));
}
