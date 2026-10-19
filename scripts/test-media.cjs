'use strict';
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const python=process.env.PIXFUN_TEST_PYTHON || (fs.existsSync(path.join(root,'.desktop-venv/bin/python'))?path.join(root,'.desktop-venv/bin/python'):'python3');
function run(command,args){const result=spawnSync(command,args,{cwd:root,stdio:'inherit'});if(result.status!==0)process.exit(result.status||1);}
run(process.execPath,['scripts/prepare-media-test.cjs']);
for(const name of ['analysis-resources','media-analysis','media-evidence','media-capture','media-catalog','place-context',
  'media-sync','phone-import-analysis','browser-import','phone-peer','phone-sync','video-description','shot-analysis','duplicate-import']) {
  run(python,[`tests/${name}.test.py`]);
}
run(process.execPath,['--test','tests/native-desktop.test.cjs','tests/place-names.test.cjs','tests/media-detail-layout.test.cjs']);
run(process.execPath,['scripts/test-native.cjs']);
