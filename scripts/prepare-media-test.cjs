'use strict';
// Synthetic local regression footage. No user media or network downloads.
const fs = require('node:fs'), path = require('node:path'), {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const folder = path.join(root, 'qa/media-library');
fs.mkdirSync(folder, {recursive:true});
const target = path.join(folder, 'captioned-test.mp4');
if (!fs.existsSync(target)) {
  const result = spawnSync('ffmpeg', ['-v','error','-f','lavfi','-i','testsrc2=size=320x180:rate=10:duration=3',
    '-f','lavfi','-i','sine=frequency=440:duration=3','-c:v','mpeg4','-q:v','5','-c:a','aac','-shortest', target], {stdio:'inherit'});
  if (result.status !== 0) throw new Error('Synthetic Media fixture generation failed. Install FFmpeg with lavfi support.');
}
console.log('Synthetic Media fixture ready.');
