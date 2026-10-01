const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
const {collectMedia,isOwnPage}=require('../desktop/security.cjs');
test('only the exact private service origin is trusted',()=>{
  const origin='http://127.0.0.1:43123';
  assert.ok(isOwnPage(origin+'/#library',origin));
  for(const value of ['https://example.com','file:///etc/passwd','http://127.0.0.1:43124','http://127.0.0.1:43123.evil.test','javascript:alert(1)'])assert.ok(!isOwnPage(value,origin));
});
test('folder imports recurse, deduplicate, skip hidden files and symlinks',async()=>{
  const folder=await fs.mkdtemp(path.join(os.tmpdir(),'pixfun-selection-'));
  try{
    await fs.mkdir(path.join(folder,'trip'));
    for(const name of ['one.mp4','two.JPG','ignore.txt','.hidden.mov','trip/three.mov','trip/voice.m4a'])await fs.writeFile(path.join(folder,name),'fixture');
    await fs.symlink(path.join(folder,'one.mp4'),path.join(folder,'link.mp4'));
    const result=await collectMedia([folder,path.join(folder,'one.mp4')],true);
    assert.deepEqual(result.paths.map(p=>path.basename(p)).sort(),['one.mp4','three.mov','two.JPG','voice.m4a']);
    assert.equal(result.errors.length,0);
    await assert.rejects(collectMedia(['relative.mp4']),/Invalid/);
  }finally{await fs.rm(folder,{recursive:true});}
});
test('bridge and window security are kept on',async()=>{
  const source=await fs.readFile(path.join(__dirname,'../desktop/main.cjs'),'utf8');
  assert.match(source,/contextIsolation:true,nodeIntegration:false,sandbox:true,webSecurity:true/);
  assert.match(source,/setPermissionRequestHandler/);
  assert.match(source,/senderFrame!==window.webContents.mainFrame/);
  const bridge=await fs.readFile(path.join(__dirname,'../desktop/preload.cjs'),'utf8');
  assert.doesNotMatch(bridge,/exposeInMainWorld\(['"](?:require|ipcRenderer|fs|shell)/);
});
test('macOS Dock and packaged app use the same generated brand icon',async()=>{
  const root=path.resolve(__dirname,'..');
  const main=await fs.readFile(path.join(root,'desktop/main.cjs'),'utf8');
  const pkg=JSON.parse(await fs.readFile(path.join(root,'package.json'),'utf8'));
  assert.match(main,/process\.platform==='darwin'\)app\.dock\.setIcon\(path\.join\(__dirname,'icon\.png'\)\)/);
  assert(pkg.build.files.includes('desktop/*.png'));
  assert.equal(pkg.build.mac.icon,'build-desktop/Pixfun.icns');
  assert.match(pkg.scripts['desktop:legacy'],/desktop:icon/);
  const png=await fs.readFile(path.join(root,'desktop/icon.png'));
  assert.equal(png.subarray(1,4).toString(),'PNG');
  assert.equal(png.readUInt32BE(16),1024);
  assert.equal(png.readUInt32BE(20),1024);
  const icon=await fs.readFile(path.join(root,pkg.build.mac.icon));
  assert.equal(icon.subarray(0,4).toString(),'icns');
  assert.equal(icon.readUInt32BE(4),icon.length);
  for(const size of [16,32,128,256,512])for(const scale of [1,2]){
    const image=await fs.readFile(path.join(root,`build-desktop/Pixfun.iconset/icon_${size}x${size}${scale===2?'@2x':''}.png`));
    assert.equal(image.readUInt32BE(16),size*scale);
    assert.equal(image.readUInt32BE(20),size*scale);
  }
});
