// Smaller decorative previews only; the full case-study videos are untouched.
const fs=require('node:fs');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const root=path.resolve(__dirname,'../public/media/cases/v3');
for(const name of ['islands','citywalk','food','outdoors','alpine']){
 const input=path.join(root,`${name}-preview.mp4`),output=path.join(root,`${name}-preview-mobile.mp4`);
 if(!fs.existsSync(output))execFileSync('ffmpeg',['-v','error','-n','-i',input,'-an','-vf','scale=640:-2','-c:v','libx264','-preset','slow','-crf','25','-pix_fmt','yuv420p','-movflags','+faststart',output],{stdio:'inherit'});
 console.log(`${name}: ${fs.statSync(input).size} → ${fs.statSync(output).size} bytes`);
}
