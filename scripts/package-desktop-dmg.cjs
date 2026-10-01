'use strict';
// Use macOS's own packaging utility; no additional downloaded DMG helper.
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const app=path.join(root,'dist-desktop/mac-arm64/Pixfun.app');
const version=require('../package.json').version;
const output=path.join(root,`dist-desktop/Pixfun-${version}-arm64.dmg`);
if(!fs.existsSync(path.join(app,'Contents/MacOS/Pixfun')))throw new Error('Build Pixfun.app first.');
const staging=fs.mkdtempSync(path.join(os.tmpdir(),'pixfun-dmg-'));
try{
  fs.cpSync(app,path.join(staging,'Pixfun.app'),{recursive:true,verbatimSymlinks:true});
  fs.symlinkSync('/Applications',path.join(staging,'Applications'));
  const built=spawnSync('hdiutil',['create','-volname','Pixfun','-srcfolder',staging,'-format','UDZO','-ov',output],{stdio:'inherit'});
  if(built.status!==0)throw new Error('DMG creation failed.');
  const verified=spawnSync('hdiutil',['verify',output],{stdio:'inherit'});
  if(verified.status!==0)throw new Error('DMG verification failed.');
  console.log(output);
}finally{
  fs.rmSync(staging,{recursive:true,force:true}); // Only this invocation's mkdtemp directory.
}
