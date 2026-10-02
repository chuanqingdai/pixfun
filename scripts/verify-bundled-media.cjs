'use strict';
// Exercise the distributable binaries, never the developer's PATH tools.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
function verify(bin) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'pixfun-bundle-media-'));
  const run = (name, args) => execFileSync(path.join(bin, name), args, {encoding:'utf8', timeout:30000});
  const png = path.join(directory, 'still.png'), movie = path.join(directory, 'preview.mp4');
  run('ffmpeg', ['-v','error','-i',path.join(root,'public/media/travel/story/coffee.jpg'),'-frames:v','1',png]);
  run('ffmpeg', ['-v','error','-loop','1','-framerate','30','-i',png,'-t','0.5','-vf','scale=320:180','-c:v','mpeg4','-pix_fmt','yuv420p',movie]);
  const probe = JSON.parse(run('ffprobe', ['-v','error','-show_streams','-of','json',movie]));
  if (!probe.streams.some(s => s.width === 320 && s.height === 180)) throw Error('Bundled image-to-video validation failed');
  run('ffmpeg', ['-v','error','-xerror','-i',movie,'-f','null','-']);
  console.log('Bundled JPEG → PNG → video → full decode: PASS');
}
module.exports = verify;
if (require.main === module) verify(path.resolve(process.argv[2] || path.join(root,'build-desktop/media/bin')));
