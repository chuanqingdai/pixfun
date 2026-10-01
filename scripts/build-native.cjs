'use strict';
// Offline, native macOS build. No Electron, browser runtime, or npm download.
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const cache = path.join(root, 'build-native/cache');
fs.mkdirSync(cache, {recursive:true});
const run = (command, args) => {
  const result = spawnSync(command, args, {cwd: root, stdio: 'inherit', env: {...process.env, CLANG_MODULE_CACHE_PATH:path.join(cache, 'clang'), SWIFTPM_MODULECACHE_OVERRIDE:path.join(cache, 'swift')}});
  if (result.status !== 0) process.exit(result.status || 1);
};
if (process.platform !== 'darwin') throw new Error('Build Pixfun Native on macOS with Xcode Command Line Tools.');
const required = ['build-desktop/backend/pixfun-service/pixfun-service', 'build-desktop/media/bin/ffmpeg', 'build-desktop/media/bin/ffprobe', 'build-desktop/Pixfun.icns'];
for (const file of required) if (!fs.existsSync(path.join(root,file))) throw new Error(`Missing ${file}. Run desktop:backend and desktop:media first.`);
const scratch = path.join(root, 'build-native');
run('swift', ['build', '--package-path', 'native', '--scratch-path', scratch, '--cache-path', cache, '-c', 'release', '--disable-sandbox']);
const output = path.join(root, 'dist-native');
fs.mkdirSync(output, {recursive:true});
const destinationApp = path.join(output, 'Pixfun.app');
const staging = fs.mkdtempSync(path.join(root, 'build-native/package-'));
const app = path.join(staging, 'Pixfun.app');
const contents = path.join(app, 'Contents'), resources = path.join(contents, 'Resources');
fs.mkdirSync(path.join(contents, 'MacOS'), {recursive:true});
fs.mkdirSync(resources, {recursive:true});
fs.copyFileSync(path.join(scratch, 'release/Pixfun'), path.join(contents, 'MacOS/Pixfun'));
fs.chmodSync(path.join(contents, 'MacOS/Pixfun'), 0o755);
for (const [source, destination] of [
  ['build-desktop/backend', 'backend'], ['build-desktop/media/bin', 'bin'],
  ['scripts/agent-model-worker.py', 'agent-model-worker.py'],
  ['.desktop-venv/lib/python3.9/site-packages/cv2/LICENSE.txt', 'licenses/opencv/LICENSE.txt'],
  ['.desktop-venv/lib/python3.9/site-packages/cv2/LICENSE-3RD-PARTY.txt', 'licenses/opencv/LICENSE-3RD-PARTY.txt'],
  ['.desktop-venv/lib/python3.9/site-packages/numpy-1.26.4.dist-info/LICENSE.txt', 'licenses/numpy/LICENSE.txt'],
  ['build-desktop/media/licenses', 'licenses/ffmpeg'], ['build-desktop/Pixfun.icns', 'Pixfun.icns'],
  ['desktop/THIRD-PARTY-NOTICES.md', 'THIRD-PARTY-NOTICES.md'],
  ['scripts/build-desktop-media.cjs', 'licenses/ffmpeg/build-desktop-media.cjs'],
  ['build-desktop/ffmpeg-source.tar.xz', 'licenses/ffmpeg/ffmpeg-source.tar.xz']
]) {
  const sourcePath = path.join(root, source);
  if (!fs.existsSync(sourcePath)) throw new Error(`Missing distribution resource: ${source}`);
  fs.cpSync(sourcePath, path.join(resources, destination), {recursive:true, verbatimSymlinks:true});
}
const {skills, buildBrief} = require('../public/desktop-skills.js');
fs.writeFileSync(path.join(resources, 'skills.json'), JSON.stringify(skills.map(skill => ({...skill, strategy:buildBrief(skill, '')})), null, 2));
fs.mkdirSync(path.join(resources, 'SkillCovers'), {recursive:true});
for (const skill of skills.filter(skill => skill.source)) {
  const destination = path.join(resources, 'CreatorSkills', skill.source);
  fs.mkdirSync(path.dirname(destination), {recursive:true});
  fs.copyFileSync(path.join(root, 'creator-skills', skill.source), destination);
}
fs.mkdirSync(path.join(resources, 'Fonts'), {recursive:true});
fs.mkdirSync(path.join(resources, 'Brand'), {recursive:true});
fs.copyFileSync(path.join(root, 'public/images/pixfun-lockup-v2.png'), path.join(resources, 'Brand/pixfun-lockup-v2.png'));
for (const font of ['dm-sans-regular.ttf', 'dm-sans-semibold.ttf', 'DM-Sans-OFL.txt']) {
  fs.copyFileSync(path.join(root, 'public/fonts', font), path.join(resources, 'Fonts', font));
}
fs.mkdirSync(path.join(resources, 'public'), {recursive:true});
const example = path.join(root, 'native/Examples/wild-alaska');
if (!fs.existsSync(path.join(example, 'manifest.json')) || !fs.existsSync(path.join(example, 'wild-alaska.mp4'))) {
  throw new Error('Missing native example. Run python3 scripts/build-native-example.py first.');
}
fs.cpSync(example, path.join(resources, 'public/examples/wild-alaska'), {recursive:true});
for (const skill of skills) fs.copyFileSync(path.join(root, `public/media/travel/${skill.image}.jpg`), path.join(resources, `SkillCovers/${skill.image}.jpg`));
fs.writeFileSync(path.join(contents, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Pixfun</string>
<key>CFBundleIdentifier</key><string>com.pixfun.native</string>
<key>CFBundleName</key><string>Pixfun</string>
<key>CFBundleDisplayName</key><string>Pixfun</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>200</string>
<key>CFBundleIconFile</key><string>Pixfun</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.video</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>`);
run('/usr/bin/codesign', ['--force', '--deep', '--sign', '-', app]);
run('/usr/bin/codesign', ['--verify', '--deep', '--strict', app]);
if (process.argv.includes('--stage-only')) {
  console.log(`Native app staged (installed app unchanged): ${app}`);
  process.exit(0);
}
if (fs.existsSync(destinationApp)) fs.renameSync(destinationApp, path.join(staging, 'Previous-Pixfun.app'));
fs.renameSync(app, destinationApp);
console.log(`Native app ready: ${destinationApp}`);
if (process.argv.includes('--open')) run('/usr/bin/open', [destinationApp]);
