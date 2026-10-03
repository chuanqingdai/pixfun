'use strict';
// Build an isolated UI fixture; launch it through the normal UI automation tools.
const fs = require('node:fs'), path = require('node:path'), {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const app = path.join(root, 'build-native/StoryPopoverSmoke.app');
const contents = path.join(app, 'Contents');
fs.mkdirSync(path.join(contents, 'MacOS'), {recursive: true});
const source = 'native/Sources/Pixfun';
const result = spawnSync('swiftc', ['-parse-as-library', '-D', 'PIXFUN_LAYOUT_TEST', '-target', `${process.arch === 'arm64' ? 'arm64' : 'x86_64'}-apple-macosx13.0`, '-module-cache-path', path.join(root, 'build-native/cache/clang'),
  ...fs.readdirSync(path.join(root, source)).filter(f => f.endsWith('.swift')).map(f => `${source}/${f}`),
  'native/Tests/StoryPopoverSmokeApp.swift', '-o', path.join(contents, 'MacOS/StoryPopoverSmoke')], {cwd: root, stdio: 'inherit'});
if (result.status !== 0) process.exit(result.status || 1);
fs.writeFileSync(path.join(contents, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>StoryPopoverSmoke</string><key>CFBundleIdentifier</key><string>com.pixfun.popover-smoke</string><key>CFBundleName</key><string>StoryPopoverSmoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>`);
console.log(app);
