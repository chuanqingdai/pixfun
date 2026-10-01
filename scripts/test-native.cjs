'use strict';
// Works with Command Line Tools alone; XCTest requires the full Xcode bundle.
const fs = require('node:fs'), path = require('node:path'), {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..'), output = path.join(root, 'build-native/NativeModelTests');
const cache = path.join(root, 'build-native/cache/clang');
fs.mkdirSync(cache, {recursive:true});
function run(command, args) {
  const result = spawnSync(command, args, {cwd:root, stdio:'inherit', env:{...process.env, CLANG_MODULE_CACHE_PATH:cache}});
  if (result.status !== 0) process.exit(result.status || 1);
}
run('swiftc', ['-parse-as-library', '-target', `${process.arch === 'arm64' ? 'arm64' : 'x86_64'}-apple-macosx13.0`, '-module-cache-path', cache,
  'native/Sources/Pixfun/Models.swift', 'native/Sources/Pixfun/AgentModels.swift', 'native/Sources/Pixfun/EditorModels.swift', 'native/Sources/Pixfun/LocalService.swift', 'native/Sources/Pixfun/WorkspaceStore.swift', 'native/Tests/ModelTests.swift', '-o', output]);
run(output, []);
const fontOutput = path.join(root, 'build-native/NativeFontTests');
run('swiftc', ['-parse-as-library', '-module-cache-path', cache, 'native/Tests/FontTests.swift', '-o', fontOutput]);
run(fontOutput, []);
const {skills,buildBrief} = require('../public/desktop-skills.js');
for (const skill of skills) {
  if(skill.structure.length !== skill.beats.length || buildBrief(skill, '').length > 4000) throw new Error(`Invalid native skill: ${skill.id}`);
}
console.log(`Passed ${skills.length} creator skill compatibility checks.`);
