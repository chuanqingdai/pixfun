'use strict';
const path = require('node:path');
const {spawnSync} = require('node:child_process');

// PyInstaller reopens its archive by pathname on lazy imports. Replacing a live
// bundle mixes the old in-memory index with new bytes, causing zlib failures.
function assertAppStopped(app, readProcesses = () => spawnSync('/bin/ps', ['-axo', 'command='], {encoding:'utf8'})) {
  const result = readProcesses();
  if (result.error || result.status !== 0 || typeof result.stdout !== 'string') {
    throw new Error('Cannot verify whether Pixfun is running. The installed app was not changed.');
  }
  const executables = [path.join(app, 'Contents/MacOS/Pixfun'),
    path.join(app, 'Contents/Resources/backend/pixfun-service/pixfun-service')];
  const active = result.stdout.split('\n').some(line => executables.some(file => {
    const command = line.trim();
    return command === file || command.startsWith(file + ' ');
  }));
  if (active) throw new Error('Pixfun or its service is still running. Quit Pixfun before installing; the installed app was not changed.');
}
module.exports = {assertAppStopped};
