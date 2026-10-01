// Public, licensed demo candidates only; no personal media or account access.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const dir=path.resolve('data/landing-quality-20261001');
fs.mkdirSync(dir,{recursive:true});
const pages=[
 'https://mixkit.co/free-stock-video/large-island-with-mountainous-relief-covered-with-trees-and-plants-38853/',
 'https://mixkit.co/free-stock-video/a-man-paddling-on-a-board-to-get-to-a-1579/',
 'https://mixkit.co/free-stock-video/paradise-port-on-an-island-2883/',
 'https://mixkit.co/free-stock-video/relief-on-a-coastline-at-sunset-from-above-36577/',
 'https://mixkit.co/free-stock-video/aerial-view-of-a-city-during-the-night-4308/',
 'https://mixkit.co/free-stock-video/quiet-tokyo-street-at-night-4451/',
 'https://mixkit.co/free-stock-video/neon-signs-with-japanese-letters-4447/',
 'https://mixkit.co/free-stock-video/large-paper-lamp-in-the-street-4109/',
 'https://mixkit.co/free-stock-video/cup-being-filled-with-coffee-in-a-coffee-machine-41865/',
 'https://mixkit.co/free-stock-video/coffee-beans-falling-on-a-layer-of-more-beans-4982/',
 'https://mixkit.co/free-stock-video/a-chef-covering-dough-with-flour-1669/',
 'https://mixkit.co/free-stock-video/breakfast-at-a-table-with-bread-coffee-and-fruit-4866/'
];
const run=(command,args)=>execFileSync(command,args,{encoding:'utf8',maxBuffer:12e6});
const results=[];
for(const page of pages){
 const id=page.match(/-(\d+)\/$/)[1];
 const html=run('curl',['-L','--fail','--silent','--show-error','--max-time','45',page]);
 fs.writeFileSync(path.join(dir,id+'.html'),html);
 if(!html.includes('commercial or personal use')||html.includes('720p Version for Personal Use only'))throw new Error('Not cleared for public demo: '+page);
 const candidates=[...html.matchAll(/https:\/\/assets\.mixkit\.co\/videos\/[^"\s<>]+\.mp4/g)].map(m=>m[0]);
 // The page's licensed full-HD download uses the same public asset ID.
 const url=candidates.find(s=>s.endsWith('-1080.mp4')) || `https://assets.mixkit.co/videos/${id}/${id}-1080.mp4`;
 const file=path.join(dir,id+'.mp4');
 if(!fs.existsSync(file))run('curl',['-L','--fail','--silent','--show-error','--max-time','120',url,'-o',file]);
 const probe=JSON.parse(run('ffprobe',['-v','error','-show_streams','-show_format','-of','json',file]));
 const v=probe.streams.find(s=>s.codec_type==='video');
 run('ffmpeg',['-v','error','-y','-i',file,'-vf','fps=1/4,scale=400:-2,tile=3x3','-frames:v','1',path.join(dir,id+'.jpg')]);
 const item={id,page,url,file,width:v.width,height:v.height,duration:Number(probe.format.duration),license:'Mixkit Stock Video Free License',licenseURL:'https://mixkit.co/license/#videoFree'};
 results.push(item);console.log(JSON.stringify(item));
 fs.writeFileSync(path.join(dir,'sources.json'),JSON.stringify(results,null,2));
}
