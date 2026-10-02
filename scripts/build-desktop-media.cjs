'use strict';
// Build independent LGPL-only command line programs, without optional GPL/nonfree libraries.
const {spawnSync}=require('node:child_process');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const root=path.resolve(__dirname,'..'),build=path.join(root,'build-desktop');
const archive=path.join(build,'ffmpeg-source.tar.xz'),version='9.0.2';
const source=path.join(build,`ffmpeg-${version}`),prefix=path.join(build,'media');
fs.mkdirSync(build,{recursive:true});
function run(command,args,cwd=root){const result=spawnSync(command,args,{cwd,stdio:'inherit',env:{...process.env,MACOSX_DEPLOYMENT_TARGET:'12.0'}});if(result.status!==0)throw new Error(`${command} failed (${result.status})`);}
if(!fs.existsSync(archive))run('curl',['--fail','--location','--max-time','600',`https://ffmpeg.org/releases/ffmpeg-${version}.tar.xz`,'-o',archive]);
const digest=require('node:crypto').createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
if(digest!=='8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e')throw new Error('FFmpeg source checksum mismatch.');
run('xz',['--test',archive]);
if(!fs.existsSync(source))run('tar',['-xf',archive,'-C',build]);
const flags=[`--prefix=${prefix}`,'--disable-autodetect','--disable-gpl','--disable-nonfree','--disable-network','--disable-doc','--disable-debug','--disable-shared','--enable-static','--disable-ffplay','--disable-indevs','--disable-outdevs','--extra-cflags=-mmacosx-version-min=12.0','--extra-ldflags=-mmacosx-version-min=12.0'];
// PNG decoding/encoding needs zlib even with dependency autodetection disabled.
flags.push('--enable-zlib');
run('./configure',flags,source);
run('make',['-j',String(Math.max(2,Math.min(6,os.cpus().length))),'install'],source);
fs.mkdirSync(path.join(prefix,'licenses'),{recursive:true});
for(const file of ['COPYING.LGPLv2.1','LICENSE.md','RELEASE'])fs.copyFileSync(path.join(source,file),path.join(prefix,'licenses',file));
console.log('Built LGPL-only FFmpeg and FFprobe for this Mac. Full corresponding source is included in the app bundle.');
