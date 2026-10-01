'use strict';
// Explicit build-time download only. The packaged app never downloads models.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'),out=path.join(root,'build-desktop/people-models');
fs.mkdirSync(out,{recursive:true});
for(const [name,model,hash] of [
 ['yunet','face_detection_yunet/face_detection_yunet_2023mar.onnx','8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4'],
 ['sface','face_recognition_sface/face_recognition_sface_2021dec.onnx','0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79']
]) {
 const file=path.join(out,name+'.onnx');
 const valid=()=>fs.existsSync(file)&&crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')===hash;
 if(!valid()) {
  if(!process.argv.includes('--download'))throw Error(`Missing/invalid ${name}. Run node scripts/prepare-people-models.cjs --download`);
  const temp=file+'.download';
  execFileSync('curl',['-fL','--retry','2',`https://github.com/opencv/opencv_zoo/raw/refs/heads/main/models/${model}`,'-o',temp],{stdio:'inherit'});
  if(crypto.createHash('sha256').update(fs.readFileSync(temp)).digest('hex')!==hash)throw Error(`Model hash mismatch: ${name}`);
  fs.renameSync(temp,file);
 }
}
for(const name of ['YuNet-LICENSE','SFace-LICENSE'])fs.copyFileSync(path.join(root,'desktop/people-licenses',name),path.join(out,name));
console.log('Verified offline YuNet/SFace models and licenses.');
