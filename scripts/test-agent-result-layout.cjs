'use strict';
const fs = require('node:fs'), path = require('node:path'), {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const source = 'native/Sources/Pixfun';
const cache = path.join(root, 'build-native/cache/clang');
const output = path.join(root, 'build-native/AgentResultLayoutTests');
fs.mkdirSync(cache, {recursive:true});
function run(command, args) {
  const result = spawnSync(command, args, {cwd:root, stdio:'inherit'});
  if (result.status !== 0) process.exit(result.status || 1);
}
run('swiftc', ['-parse-as-library', '-D', 'PIXFUN_LAYOUT_TEST', '-target', `${process.arch === 'arm64' ? 'arm64' : 'x86_64'}-apple-macosx13.0`, '-module-cache-path', cache,
  ...fs.readdirSync(path.join(root, source)).filter(file => file.endsWith('.swift')).map(file => `${source}/${file}`),
  'native/Tests/AgentResultLayoutTests.swift', '-o', output]);
run(output, [path.join(root, 'build-native/result-layout-audit')]);
