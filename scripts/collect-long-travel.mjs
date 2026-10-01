// Curated NPS field recordings. Keep source copies and licensing alongside originals.
import fs from 'node:fs';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const exec=promisify(execFile),root=path.resolve('data/travel-long-20260927');
fs.mkdirSync(root,{recursive:true});
const picks=[
 ['Kennesaw - Assault Trail Walk','E4AB62CA-6266-43B2-88D7-E0E97DC1AD23','Kennesaw Mountain, Georgia'],
 ['Kennesaw - Woodland Ranger Talk','04EEAA2E-4D1E-4468-A9B6-05103DA07BC7','Kennesaw Mountain, Georgia'],
 ['Glacier - Archaeology Field Visit','261b879f-efa9-4f45-8dcb-8a20df93cdc5','Glacier National Park, Montana']
];
const clean=s=>s.replace(/<[^>]*>/g,' ').replace(/&amp;/g,'&').replace(/\s+/g,' ').trim();
async function collect([name,id,location]){
 const source=`https://www.nps.gov/media/video/view.htm?id=${id}`;
 const html=(await exec('curl',['-LfsS','--max-time','60',source],{maxBuffer:5e6})).stdout;
 const credit=clean(html.match(/<h[23][^>]*>Credit<\/h[23]>([\s\S]*?)(?=<h[23]|<\/section>)/i)?.[1]||'');
 if(!credit.startsWith('NPS')||credit.includes('©'))throw Error('Review rights: '+credit);
 const urls=[...html.matchAll(/<source src="([^"]+\.mp4)"/g)].map(m=>m[1]);
 const url=urls.find(u=>u.includes('1080p'))||urls.find(u=>u.includes('720p'))||urls[0];
 if(!url)throw Error('Missing original: '+name);
 fs.writeFileSync(path.join(root,name+'.source.html'),html);
 const file=path.join(root,name+'.mp4'),temporary=file+'.part';
 if(!fs.existsSync(file)){
  await exec('curl',['-LfsS','--retry','2','--max-time','600',url,'-o',temporary]);
  const probe=JSON.parse((await exec('ffprobe',['-v','error','-show_format','-show_streams','-of','json',temporary],{maxBuffer:2e6})).stdout);
  if(!probe.streams.some(s=>s.codec_type==='audio')||Number(probe.format.duration)<500)throw Error('Expected long video with audio');
  fs.renameSync(temporary,file);
 }
 const probe=JSON.parse((await exec('ffprobe',['-v','error','-show_format','-show_streams','-of','json',file],{maxBuffer:2e6})).stdout);
 const context={location,source,credit,license:'Public domain (NPS source credit; no copyright symbol)'};
 fs.writeFileSync(path.join(root,name+'.pixfun.json'),JSON.stringify(context,null,2));
 const record={name,file,...context,download:url,duration:Number(probe.format.duration),bytes:Number(probe.format.size),streams:probe.streams.map(s=>({type:s.codec_type,codec:s.codec_name,width:s.width,height:s.height,duration:s.duration}))};
 console.log(JSON.stringify(record));return record;
}
const results=await Promise.all(picks.map(p=>collect(p).catch(e=>({name:p[0],error:e.message}))));
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(results,null,2));
fs.writeFileSync(path.join(root,'SOURCES.md'),'# Long-form travel field recordings\n\nDownloaded from NPS official source pages. These are published ranger field recordings, not camera-original RAW files. Some contain brief intro/outro titles. Original audio is retained; no looping, time stretching, music replacement, or recomposition. Devices are not specified by the source and are intentionally omitted.\n\n'+results.map(r=>r.error?`- ${r.name}: ${r.error}`:`- **${r.name}** — ${Math.floor(r.duration/60)}:${String(Math.round(r.duration%60)).padStart(2,'0')} — ${r.credit}\n  [Source & usage terms](${r.source}) · ${r.location}`).join('\n\n'));
if(results.some(r=>r.error))process.exitCode=1;
