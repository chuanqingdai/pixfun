// Ten source-backed examples. This prepares files; importing uses the normal desktop UI.
import fs from 'node:fs';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const exec=promisify(execFile), root=path.resolve('data/representative-media-20260927');
const imports=path.join(root,'import');
fs.mkdirSync(imports,{recursive:true});fs.mkdirSync(path.join(root,'frames'),{recursive:true});
const proxy=process.env.PIXFUN_DOWNLOAD_PROXY;
const curl=async(args)=>exec('curl',[...(proxy?['--proxy',proxy]:[]),'-L','--fail','--silent','--show-error','--retry','2','--max-time','240',...args],{maxBuffer:8e6});
const clean=s=>String(s||'').replace(/<[^>]+>/g,' ').replace(/&amp;/g,'&').replace(/\s+/g,' ').trim();
const entries=[
 {name:'Victoria Falls - Phone Panorama',title:'Victoria-falls.webm',device:'iPhone 7 Plus',location:'Victoria Falls, Zambia',theme:'Phone panorama',evidence:'Source description: Shot on iPhone 7 Plus.'},
 {name:'Pattaya - Action Camera City View',title:'(-L3) XAVCS 30FPS 1080p on Sony Action Cam AS200V.webm',device:'Sony AS200V',location:'Pattaya, Thailand',theme:'Action camera city panorama',evidence:'Camera model in source title and description.'},
 {name:'Bavaria - Countryside Harvest',title:'Iffeldorf, Maisernte 2017-10 (1).webm',device:'Sony SLT-A58',location:'Iffeldorf, Bavaria',theme:'Countryside observation',evidence:'Source category: Taken with Sony SLT-A58.'},
 {name:'Antur Fort - Aerial Approach',title:'Dji 0315.webm',device:'',location:'Antur Fort, Maharashtra',theme:'Aerial landmark',evidence:'Device model not confirmed; do not infer it from the filename.'},
 {name:'Capri - Villa Jovis Walkthrough',title:'Villa Jovis GoPro walkthrough.webm',device:'GoPro',location:'Villa Jovis, Capri',theme:'Continuous heritage walkthrough',evidence:'GoPro in source title; exact model not specified.'},
 {name:'Ningaloo - Underwater Turtle',title:'Sea turtle swimming.jpg',device:'GoPro HERO7 Black',location:'Ningaloo Reef, Australia',theme:'Square underwater photo',evidence:'Source EXIF: GoPro HERO7 Black.'},
 {name:'Waddinxveen - Aerial Neighborhood',title:'Aerial view of Waddinxveen (by drone).jpg',device:'DJI drone',location:'Waddinxveen, Netherlands',theme:'High-resolution aerial photo',evidence:'Source EXIF manufacturer DJI. Exact consumer model not independently verified.'},
 {name:'Spaghetti - Portrait Food Detail',cached:'Spaghetti at the Table',device:'',location:'',theme:'Portrait food close-up'},
 {name:'Times Square - Rainy Night',cached:'Times Square in the Rain',device:'',location:'Times Square, New York',theme:'Low-light urban scene'},
 {name:'Yellowstone - Geyser Field Recording',cached:'Yellowstone Fountain Geyser',device:'',location:'Yellowstone National Park',theme:'Natural sound and landscape',trim:{start:7,duration:55}}
];
async function prepare(e,index){
 let source;
 if(e.title){
  const metadataPath=path.join(root,`${e.name}.source.json`);
  let info;
  if(fs.existsSync(metadataPath))info=JSON.parse(fs.readFileSync(metadataPath));
  else{
   const url='https://commons.wikimedia.org/w/api.php?'+new URLSearchParams({action:'query',format:'json',titles:'File:'+e.title,prop:'imageinfo',iiprop:'url|size|extmetadata|metadata'});
   const data=JSON.parse((await curl([url])).stdout);info=Object.values(data.query.pages)[0].imageinfo[0];
   fs.writeFileSync(metadataPath,JSON.stringify(info,null,2));
  }
  const m=info.extmetadata;e.page=info.descriptionurl;e.credit=clean(m.Artist?.value);e.license=m.LicenseShortName?.value;e.licenseUrl=m.LicenseUrl?.value;
  if(!/^(CC BY|CC0)/.test(e.license))throw Error(`Unreviewed license: ${e.name}`);
  source=path.join(root,e.name+path.extname(e.title));
  if(!fs.existsSync(source))await curl([info.url,'-o',source]);
  if(fs.statSync(source).size!==info.size)throw Error(`Incomplete download: ${e.name}`);
 }else{
  const cached=JSON.parse(fs.readFileSync(path.resolve('data/travel-import-20260927',e.cached+'.json')));
  e.page=cached.page;e.credit=cached.credit;e.license=cached.license;e.licenseUrl=cached.page.includes('mixkit')?'https://mixkit.co/license/#videoFree':'https://www.nps.gov/aboutus/disclaimer.htm';
  source=path.resolve('data/travel-import-20260927/import',e.cached+'.mp4');
  e.evidence='Source does not identify the camera; device intentionally omitted.';
 }
 const photo=/\.jpg$/i.test(source),out=path.join(imports,e.name+(photo?'.jpg':'.mp4'));
 if(!fs.existsSync(out)){
  if(e.trim)await exec('ffmpeg',['-v','error','-n','-ss',String(e.trim.start),'-i',source,'-t',String(e.trim.duration),'-map','0:v:0','-map','0:a?','-c:v','h264_videotoolbox','-b:v','5M','-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-movflags','+faststart',out],{maxBuffer:2e6});
  else if(photo||e.cached)fs.copyFileSync(source,out);
  else await exec('ffmpeg',['-v','error','-n','-i',source,'-map','0:v:0','-map','0:a?','-c:v','h264_videotoolbox','-b:v','6M','-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-movflags','+faststart',out],{maxBuffer:2e6});
 }
 const probe=JSON.parse((await exec('ffprobe',['-v','error','-show_streams','-show_format','-of','json',out])).stdout);
 const v=probe.streams.find(s=>s.codec_type==='video');if(!v)throw Error(`No image stream: ${e.name}`);
 Object.assign(e,{file:out,kind:photo?'image':'video',duration:photo?null:Number(probe.format.duration),width:v.width,height:v.height,hasAudio:probe.streams.some(s=>s.codec_type==='audio'),bytes:fs.statSync(out).size});
 const original=JSON.parse((await exec('ffprobe',['-v','error','-show_format','-show_streams','-of','json',source])).stdout);
 if(!photo&&Math.abs((e.trim?.duration??Number(original.format.duration))-e.duration)>.2)throw Error(`Unexpected duration: ${e.name}`);
 const ov=original.streams.find(s=>s.codec_type==='video');if(v.width!==ov.width||v.height!==ov.height)throw Error(`Dimensions changed: ${e.name}`);
 fs.writeFileSync(out.replace(/\.[^.]+$/,'.pixfun.json'),JSON.stringify({device:e.device,location:e.location,source:e.page,credit:e.credit,license:`${e.license} · ${e.licenseUrl}`},null,2));
 const frame=path.join(root,'frames',`${String(index+1).padStart(2,'0')}.jpg`);
 if(!fs.existsSync(frame))await exec('ffmpeg',['-v','error','-n',...(!photo?['-ss',String(Math.min(e.duration*.4,35))]:[]),'-i',out,'-frames:v','1','-vf','scale=384:216:force_original_aspect_ratio=decrease,pad=384:216:(ow-iw)/2:(oh-ih)/2',frame]);
 console.log(JSON.stringify({name:e.name,duration:e.duration,device:e.device,hasAudio:e.hasAudio,bytes:e.bytes}));
}
// Limit network and encoder concurrency.
let cursor=0;await Promise.all([0,1].map(async()=>{while(cursor<entries.length){const i=cursor++;await prepare(entries[i],i);}}));
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(entries,null,2));
await exec('ffmpeg',['-v','error','-y','-start_number','1','-i',path.join(root,'frames','%02d.jpg'),'-vf','tile=2x5','-frames:v','1',path.join(root,'review.jpg')]);
const time=n=>n===null?'Photo':`${Math.floor(n/60)}:${String(Math.floor(n%60)).padStart(2,'0')}`;
fs.writeFileSync(path.join(root,'SOURCES.md'),`# Representative travel media\n\nTen additional examples prepared for the Mac Media library. Original duration, aspect ratio, and dimensions retained; no synthetic audio, repeated footage, added titles, or upscaling. WebM videos are transcoded to H.264/AAC for native playback; sound content is retained. Photos are unchanged. Source descriptions and device labels are provenance, not AI recognition. Device models are left blank when unverified.\n\nEach source retains its own license; CC BY-SA derivatives retain that license. No endorsement is implied.\n\n| Title | Type / length | Device | Scene | Source / credit / license |\n|---|---|---|---|---|\n${entries.map(e=>`| ${e.name} | ${time(e.duration)} | ${e.device||'Not specified'} | ${e.theme} | [Source](${e.page}) · ${e.credit} · [${e.license}](${e.licenseUrl}) |`).join('\n')}\n\n## Device evidence\n${entries.map(e=>`- **${e.name}:** ${e.evidence}`).join('\n')}\n`);
const sourcesPath=path.join(root,'SOURCES.md');
fs.writeFileSync(sourcesPath,fs.readFileSync(sourcesPath,'utf8').replace('Original duration, aspect ratio, and dimensions retained;','Original aspect ratio and dimensions retained; full duration retained except the explicitly documented geyser excerpt;')+'\n## Geyser excerpt\n\nThe Fountain Geyser source has opening and closing title cards. The imported field-recording excerpt uses source 00:07–01:02 (55 seconds), retaining the corresponding original sound, with no titles, music added, looping, or speed changes. The uncut source is preserved separately.\n');
console.log('Prepared 10 files:',imports);
