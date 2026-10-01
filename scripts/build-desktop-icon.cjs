'use strict';
// One vector source for the development Dock icon and packaged macOS iconset.
const {spawnSync}=require('node:child_process');
const path=require('node:path');
const fs=require('node:fs');
const {Resvg}=require('@resvg/resvg-js');
const root=path.resolve(__dirname,'..');
const svg=fs.readFileSync(path.join(root,'desktop/icon.svg'),'utf8');
const iconset=path.join(root,'build-desktop/Pixfun.iconset');
fs.mkdirSync(iconset,{recursive:true});
for(const size of [16,32,128,256,512])for(const scale of [1,2]){
  const pixels=size*scale;
  const png=new Resvg(svg,{fitTo:{mode:'width',value:pixels}}).render().asPng();
  fs.writeFileSync(path.join(iconset,`icon_${size}x${size}${scale===2?'@2x':''}.png`),png);
  if(size===512&&scale===2)fs.writeFileSync(path.join(root,'desktop/icon.png'),png);
}
const result=spawnSync('iconutil',['-c','icns',iconset,'-o',path.join(root,'build-desktop/Pixfun.icns')],{stdio:'inherit'});
if(result.error)throw result.error;
if(result.status!==0)throw new Error('macOS icon generation failed');
console.log('Built Pixfun Dock PNG and all 10 macOS icon sizes.');
