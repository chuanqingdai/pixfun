'use strict';
// Local preparation only. Install pinned dependencies separately; no runtime download.
const fs=require('node:fs'), path=require('node:path');
const root=path.resolve(__dirname,'..');
const runtime=path.join(root,'build-native/hyperframes-runtime');
const upstream=path.join(root,'build-native/hyperframes-upstream');
const vf=process.env.PIXFUN_VF_ROOT || path.join(require('node:os').homedir(),'work/visionflow/vf-agent');
const showcase=path.join(runtime,'showcase');
fs.mkdirSync(showcase,{recursive:true});
const gsap='https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js';
for (const name of ['hw-write-title','nyc-paris-flight','split-flap-board']) {
  const source=path.join(upstream,'registry/blocks',name);
  const manifest=JSON.parse(fs.readFileSync(path.join(source,'registry-item.json'),'utf8'));
  for (const entry of manifest.files) {
    const target=path.resolve(showcase,entry.target);
    if (!target.startsWith(showcase+path.sep)) throw new Error('Invalid template path');
    fs.mkdirSync(path.dirname(target),{recursive:true});
    fs.copyFileSync(path.join(source,entry.path),target);
    if (entry.path.endsWith('.html')) fs.writeFileSync(target,fs.readFileSync(target,'utf8').replaceAll(gsap,'gsap.min.js'));
  }
  fs.copyFileSync(path.join(source,'registry-item.json'),path.join(showcase,name+'.registry.json'));
}
fs.copyFileSync(path.join(runtime,'node_modules/gsap/dist/gsap.min.js'),path.join(showcase,'gsap.min.js'));
fs.writeFileSync(path.join(showcase,'index.html'),fs.readFileSync(path.join(vf,'examples/hyperframes_showcase/index.html'),'utf8').replaceAll(gsap,'gsap.min.js'));
fs.copyFileSync(path.join(root,'native/HYPERFRAMES.md'),path.join(showcase,'README.md'));
fs.copyFileSync(path.join(upstream,'LICENSE'),path.join(showcase,'HYPERFRAMES-LICENSE'));
const node=path.join(runtime,'node-v24.6.0-darwin-arm64/bin/node');
if (!fs.existsSync(node)) throw new Error('Extract official node-v24.6.0-darwin-arm64 first.');
fs.copyFileSync(node,path.join(runtime,'node.next')); fs.chmodSync(path.join(runtime,'node.next'),0o755);
fs.renameSync(path.join(runtime,'node.next'),path.join(runtime,'node'));
fs.copyFileSync(path.join(runtime,'node-v24.6.0-darwin-arm64/LICENSE'),path.join(runtime,'NODE-LICENSE'));
console.log('Prepared offline official showcase:',showcase);
