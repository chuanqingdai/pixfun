// Build-only, licensed demonstration media. No source footage is imported into a user's library.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve('public/media/cases');
const evidence=path.resolve('data/landing-cases-20261001');
fs.mkdirSync(root,{recursive:true});fs.mkdirSync(evidence,{recursive:true});
const run=(bin,args)=>execFileSync(bin,args,{encoding:'utf8',maxBuffer:12e6});
const get=url=>run('curl',['-L','--fail','--silent','--show-error','--max-time','90',url]);
const cases=[
 ['alpine','Alpine scale','flying-over-a-monumental-rocky-mountain-with-visible-snow-and-51689'],
 ['citywalk','City after dark','side-by-side-aerial-view-of-a-city-at-night-49846'],
 ['food','Small rituals','preparing-a-bowl-with-yogurt-and-fruit-43925'],
 ['outdoors','The human moment','man-enjoying-the-wind-2385'],
 ['islands','Coastal calm','white-sand-beach-background-1564'],
];
const records=[];
for(const [id,label,slug] of cases){
 const page=`https://mixkit.co/free-stock-video/${slug}/`;
 const html=get(page);
 if(!html.includes('commercial or personal use'))throw Error('Free license not confirmed: '+id);
 fs.writeFileSync(path.join(evidence,id+'.source.html'),html);
 const download=html.match(/value="([^" ]*\/free-stock-video\/download\/[^" ]*type=1080p)"/);
 if(!download)throw Error('1080p download unavailable: '+id);
 const panel=get('https://mixkit.co'+download[1].replace(/&amp;/g,'&'));
 const url=panel.match(/data-download--modal-url-value="([^"]+)"/)?.[1];
 if(!url)throw Error('No download URL: '+id);
 const source=path.join(evidence,id+'.mp4');
 if(!fs.existsSync(source))run('curl',['-L','--fail','--silent','--show-error','--retry','2','--max-time','240',url,'-o',source]);
 const probe=JSON.parse(run('ffprobe',['-v','error','-show_streams','-show_format','-of','json',source]));
 const v=probe.streams.find(s=>s.codec_type==='video'),audio=probe.streams.some(s=>s.codec_type==='audio');
 const duration=Number(probe.format.duration);
 if(v.width<v.height||duration<20||duration>60)throw Error('Need landscape 20–60s: '+id+' '+duration+' '+v.width+'x'+v.height);
 const full=path.join(root,id+'.mp4');
 if(!fs.existsSync(full))run('ffmpeg',['-v','error','-i',source,'-map','0:v:0','-map','0:a?','-vf','scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2','-c:v','libx264','-preset','fast','-crf','22','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',full]);
 const record={id,label,sourcePage:page,sourceURL:url,license:'Mixkit Stock Video Free License',licenseURL:'https://mixkit.co/license/#videoFree',duration,width:v.width,height:v.height,fps:v.avg_frame_rate,audio,sourceFile:source,full:'/assets/media/cases/'+id+'.mp4'};
 records.push(record);
 for(let i=0;i<6;i++)run('ffmpeg',['-v','error','-y','-ss',String(duration*i/6+.1),'-i',source,'-frames:v','1','-vf','scale=512:-2','-q:v','3',path.join(evidence,`${id}-${i}.jpg`)]);
 run('ffmpeg',['-v','error','-y','-pattern_type','glob','-i',path.join(evidence,id+'-*.jpg'),'-vf','tile=3x2','-frames:v','1',path.join(evidence,id+'-contact.jpg')]);
 fs.writeFileSync(path.join(evidence,'sources.json'),JSON.stringify(records,null,2));
 console.log(JSON.stringify(record));
}
