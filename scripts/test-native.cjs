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
run('swiftc', ['-parse-as-library', 'native/Sources/Pixfun/AppLanguage.swift', 'native/Sources/Pixfun/MediaCatalog.swift', 'native/Sources/Pixfun/PlaceNameResolver.swift', 'native/Sources/Pixfun/PlaceBoundaryLookup.swift', 'native/Sources/Pixfun/PlaceFallbackLookup.swift', '-target', `${process.arch === 'arm64' ? 'arm64' : 'x86_64'}-apple-macosx13.0`, '-module-cache-path', cache,
  'native/Sources/Pixfun/Models.swift', 'native/Sources/Pixfun/MediaMapData.swift', 'native/Sources/Pixfun/MediaSearch.swift', 'native/Sources/Pixfun/MediaSyncModels.swift', 'native/Sources/Pixfun/AgentModels.swift', 'native/Sources/Pixfun/VideoExport.swift', 'native/Sources/Pixfun/EditorModels.swift', 'native/Sources/Pixfun/StoryTimeline.swift', 'native/Sources/Pixfun/LocalService.swift', 'native/Sources/Pixfun/WorkspaceStore.swift', 'native/Tests/ModelTests.swift', '-o', output]);
run(output, []);
const fontOutput = path.join(root, 'build-native/NativeFontTests');
run('swiftc', ['-parse-as-library', '-module-cache-path', cache, 'native/Tests/FontTests.swift', '-o', fontOutput]);
run(fontOutput, []);
const promptOutput = path.join(root, 'build-native/NativePromptEditorTests');
run('swiftc', ['-parse-as-library', '-module-cache-path', cache,
  'native/Sources/Pixfun/Models.swift', 'native/Sources/Pixfun/MediaSearch.swift',
  'native/Sources/Pixfun/Theme.swift', 'native/Sources/Pixfun/PromptEditor.swift',
  'native/Tests/PromptEditorTests.swift', '-o', promptOutput]);
run(promptOutput, []);
const themeOutput = path.join(root, 'build-native/NativeThemeTests');
run('swiftc', ['-parse-as-library', '-module-cache-path', cache,
  'native/Sources/Pixfun/Models.swift', 'native/Sources/Pixfun/MediaSearch.swift',
  'native/Sources/Pixfun/Theme.swift', 'native/Tests/ThemeTests.swift', '-o', themeOutput]);
run(themeOutput, []);
const keyboardOutput = path.join(root, 'build-native/StoryKeyboardTests');
run('swiftc', ['-parse-as-library', '-module-cache-path', cache,
  'native/Sources/Pixfun/StoryPlaybackKeys.swift', 'native/Tests/StoryKeyboardTests.swift', '-o', keyboardOutput]);
run(keyboardOutput, []);
const mediaPlaybackOutput = path.join(root, 'build-native/MediaPlaybackTests');
run('swiftc', ['-parse-as-library', '-module-cache-path', cache,
  'native/Sources/Pixfun/MediaPlayback.swift', 'native/Tests/MediaPlaybackTests.swift', '-o', mediaPlaybackOutput]);
run(mediaPlaybackOutput, [path.join(root, 'native/Examples/wild-alaska/wild-alaska.mp4')]);
const {skills,buildBrief} = require('../public/desktop-skills.js');
for (const skill of skills) {
  if(skill.structure.length !== skill.beats.length || buildBrief(skill, '').length > 4000) throw new Error(`Invalid native skill: ${skill.id}`);
}
console.log(`Passed ${skills.length} creator skill compatibility checks.`);
