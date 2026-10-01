import fs from 'node:fs';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const exec=promisify(execFile),root=path.resolve('data/travel-import-20260927');
const entries=JSON.parse(fs.readFileSync(path.join(root,'manifest.json')));
if(entries.length!==23)throw Error('Expected 23 validated downloads');
const directory=path.join(root,'import'),frames=path.join(root,'frames');
fs.mkdirSync(directory,{recursive:true});fs.mkdirSync(frames,{recursive:true});
for(let i=0;i<entries.length;i++){
  const e=entries[i],out=path.join(directory,e.name+'.mp4');
  const encoder=e.duration>180?['-c:v','h264_videotoolbox','-b:v',e.height>=1080?'3M':'2M']:['-c:v','libx264','-threads','4','-preset','veryfast','-crf','23'];
  if(!fs.existsSync(out))await exec('ffmpeg',['-hide_banner','-v','error','-n','-i',e.file,'-map','0:v:0','-map','0:a?',...encoder,'-pix_fmt','yuv420p','-c:a','copy','-movflags','+faststart','-metadata',`title=${e.name}`,'-metadata',`comment=Source: ${e.page}; Credit: ${e.credit}; License: ${e.license}; Full duration retained; video re-encoded, original audio copied.`,out],{maxBuffer:2e6});
  const probe=JSON.parse((await exec('ffprobe',['-v','error','-show_streams','-show_format','-of','json',out])).stdout);
  const v=probe.streams.find(s=>s.codec_type==='video'),a=probe.streams.find(s=>s.codec_type==='audio');
  if(v.width!==e.width||v.height!==e.height||Math.abs(Number(probe.format.duration)-e.duration)>.15||Boolean(a)!==Boolean(e.audio))throw Error('Media verification failed: '+e.name);
  e.importFile=out;e.importBytes=Number(probe.format.size);
  const frame=path.join(frames,String(i+1).padStart(2,'0')+'.jpg');
  if(!fs.existsSync(frame))await exec('ffmpeg',['-v','error','-n','-ss',String(Math.min(e.duration*.4,25)),'-i',out,'-frames:v','1','-vf','scale=320:180:force_original_aspect_ratio=decrease,pad=320:180:(ow-iw)/2:(oh-ih)/2','-q:v','3',frame]);
  console.log(`${i+1}/${entries.length} ${e.name}: ${(e.importBytes/1048576).toFixed(1)} MB`);
}
fs.writeFileSync(path.join(root,'import-manifest.json'),JSON.stringify(entries,null,2));
await exec('ffmpeg',['-v','error','-y','-start_number','1','-i',path.join(frames,'%02d.jpg'),'-vf','tile=4x6','-frames:v','1',path.join(root,'contact-sheet.jpg')]);
const time=n=>`${Math.floor(n/60)}:${String(Math.floor(n%60)).padStart(2,'0')}`;
const rows=entries.map((e,i)=>`| ${i+1} | ${e.name} | ${e.theme} | ${time(e.duration)} | ${e.width} × ${e.height} | ${e.audio?(parseFloat(e.audio.meanVolume)>-70?'Original audio retained':'Near-silent original audio track'):'No audio in source'} | [Source](${e.page}) | ${e.credit} | ${e.license} |`).join('\n');
fs.writeFileSync(path.join(root,'SOURCES.md'),`# Travel media imported into Pixfun\n\n${entries.length} real source videos, downloaded on 2026-09-27. No AI-generated imagery or added soundtracks. Original downloaded files are kept beside this document; browser-ready files are in import/.\n\nThe imported versions retain source dimensions and full duration, use H.264 video encoding, and copy original audio without recomposition. No upscaling. Two portrait videos are included. Source context is not an AI recognition result.\n\nMixkit items: [Stock Video Free License](https://mixkit.co/license/#videoFree). NPS items are credited to NPS without a copyright mark, with public-domain usage information on their linked source pages. No endorsement is implied.\n\n| # | File title | Travel theme | Duration | Resolution | Audio | Source | Credit | License |\n|---|---|---|---|---|---|---|---|---|\n${rows}\n`);
console.log(JSON.stringify({count:entries.length,totalSeconds:entries.reduce((n,e)=>n+e.duration,0),totalBytes:entries.reduce((n,e)=>n+e.importBytes,0),audible:entries.filter(e=>e.audio&&parseFloat(e.audio.meanVolume)>-70).length}));
