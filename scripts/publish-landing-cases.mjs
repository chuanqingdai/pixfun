// Build the public case catalog from measured media and explicitly reviewed editorial decisions.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const dir=path.resolve('data/landing-cases-20261001');
const target=path.resolve('public/media/cases');
const sources=JSON.parse(fs.readFileSync(path.join(dir,'sources.json')));
const reviews=JSON.parse(fs.readFileSync(path.join(dir,'editorial-review.json')));
const render=process.argv.includes('--render');
const run=args=>execFileSync('ffmpeg',['-v','error','-y','-threads','2',...args],{stdio:'inherit'});
const catalog=sources.map(source=>{
 const review=reviews[source.id],base='/assets/media/cases/'+source.id;
 const modelPath=path.join(dir,source.id+'.analysis.json');
 const model=fs.existsSync(modelPath)?JSON.parse(fs.readFileSync(modelPath)).model:null;
 const {sourceFile,sourceURL,...metadata}=source;
 const item={...metadata,...review,poster:base+'.jpg',preview:base+'-preview.mp4',analysisModel:model?model+' + editorial review':'Editorial review of sampled frames'};
 item.shots=review.shots.map((shot,i)=>({...shot,end:shot.end==='duration'?source.duration:shot.end,thumbnail:base+'-shot-'+i+'.jpg'}));
 if(render){
  run(['-ss',String(review.highlight.start),'-i',sourceFile,'-t','5','-an','-vf','scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2','-c:v','libx264','-threads','2','-preset','fast','-crf','23','-pix_fmt','yuv420p','-movflags','+faststart',path.join(target,source.id+'-preview.mp4')]);
  run(['-ss',String(review.highlight.start+1),'-i',sourceFile,'-frames:v','1','-vf','scale=1280:-2','-q:v','2',path.join(target,source.id+'.jpg')]);
  for(const [i,shot] of item.shots.entries())run(['-ss',String(Math.min(shot.end-.1,shot.start+1)),'-i',sourceFile,'-frames:v','1','-vf','scale=640:-2','-q:v','3',path.join(target,source.id+'-shot-'+i+'.jpg')]);
 }
 return item;
});
if(catalog.length!==5)throw Error('All five verified sources are required.');
fs.writeFileSync(path.join(target,'catalog.json'),JSON.stringify(catalog,null,2));
console.log('Published '+catalog.length+' reviewed examples.');
