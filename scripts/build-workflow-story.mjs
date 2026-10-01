// Licensed stock footage for the landing-page workflow. See ASSETS.md.
import {mkdirSync, existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const sources = [
  ['coffee',43165], ['trail',43151], ['hike',43155],
  ['look',43159], ['snow',4282], ['clouds',4303],
  ['vista',42490], ['together',43161], ['selfie',43150],
  ['camp',43137], ['fire',22730], ['stars',4124]
];
const cache='qa/workflow-story/sources', output='public/media/travel/story';
mkdirSync(cache,{recursive:true});mkdirSync(output,{recursive:true});
function run(command,args){const r=spawnSync(command,args,{encoding:'utf8'});if(r.status!==0)throw Error(r.stderr);return r.stdout;}
await Promise.all(sources.map(async([name,id])=>{
  const file=`${cache}/${id}.mp4`;
  if(process.argv.includes('--contact-only'))return;
  if(existsSync(`${output}/${name}.mp4`)&&existsSync(`${output}/${name}.jpg`))return;
  if(!existsSync(file)){
    const {spawn}=await import('node:child_process');
    await new Promise((resolve,reject)=>{const p=spawn('curl',['-fL','--retry','2','--max-time','90','-o',file,`https://assets.mixkit.co/videos/${id}/${id}-720.mp4`]);p.on('exit',code=>code===0?resolve():reject(Error(`Download ${id}: ${code}`)));});
  }
  const info=JSON.parse(run('ffprobe',['-v','error','-show_streams','-show_format','-of','json',file]));
  const video=info.streams.find(s=>s.codec_type==='video');
  if(Math.abs(video.width/video.height-16/9)>.02)throw Error(`${name} is not native 16:9`);
  run('ffmpeg',['-hide_banner','-loglevel','error','-y','-i',file,'-t','9','-an','-vf','scale=1280:720,setsar=1,fps=24','-c:v','libx264','-preset','fast','-crf','24','-pix_fmt','yuv420p','-movflags','+faststart',`${output}/${name}.mp4`]);
  run('ffmpeg',['-hide_banner','-loglevel','error','-y','-ss','1.5','-i',`${output}/${name}.mp4`,'-frames:v','1','-q:v','3',`${output}/${name}.jpg`]);
  console.log(`${name}: ${video.width}x${video.height}, source ${info.format.duration}s`);
}));
run('ffmpeg',['-hide_banner','-loglevel','error','-y',...sources.flatMap(([name])=>['-i',`${output}/${name}.jpg`]),'-filter_complex',sources.map((_,i)=>`[${i}:v]scale=384:216[v${i}]`).join(';')+';'+sources.map((_,i)=>`[v${i}]`).join('')+`xstack=inputs=${sources.length}:layout=`+sources.map((_,i)=>`${i%3*384}_${Math.floor(i/3)*216}`).join('|')+'[out]','-map','[out]','-frames:v','1','qa/workflow-story/contact.jpg']);
