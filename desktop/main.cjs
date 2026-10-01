'use strict';
const {app, BrowserWindow, Menu, dialog, ipcMain, session, shell} = require('electron');
const {spawn} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {collectMedia, isOwnPage} = require('./security.cjs');

app.setName('Pixfun');
let window, service, origin, stopping=false, startupError;
const token=crypto.randomBytes(32).toString('hex'), nativeToken=crypto.randomBytes(32).toString('hex');
const root=path.resolve(__dirname,'..');
const resources=app.isPackaged?process.resourcesPath:root;
const store=process.env.PIXFUN_TEST_DATA_DIR || path.join(app.getPath('userData'),'Library');
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance',()=>{if(window){if(window.isMinimized())window.restore();window.show();window.focus();}});
  app.whenReady().then(boot).catch(showFailure);
}

async function api(route,payload,native=false){
  if(!origin)throw new Error('The local service is not ready.');
  const response=await fetch(origin+route,{method:payload?'POST':'GET',headers:{Authorization:`Bearer ${token}`,...(native?{'X-Pixfun-Native':nativeToken}:{}),...(payload?{'Content-Type':'application/json'}:{})},body:payload?JSON.stringify(payload):undefined});
  const result=await response.json();
  if(!response.ok||!result.ok)throw new Error(result.error||'Local service request failed.');
  return result;
}

function startService(){
  fs.mkdirSync(store,{recursive:true});
  const log=fs.openSync(path.join(store,'service.log'),'a');
  const bins=app.isPackaged?[path.join(resources,'bin')]:[path.join(root,'build-desktop/media/bin')];
  const program=app.isPackaged?path.join(resources,'backend/pixfun-service/pixfun-service'):path.join(root,'.desktop-venv/bin/python');
  const args=app.isPackaged?[]:[path.join(root,'desktop_service.py')];
  const env={...process.env,PATH:[...bins,process.env.PATH].join(path.delimiter),PYTHONUNBUFFERED:'1',PIXFUN_DATA_DIR:store,PIXFUN_PUBLIC_DIR:path.join(resources,'public'),PIXFUN_SERVICE_TOKEN:token,PIXFUN_NATIVE_TOKEN:nativeToken};
  service=spawn(program,args,{env,stdio:['ignore','pipe',log]});
  fs.closeSync(log);
  return new Promise((resolve,reject)=>{
    let buffer='',settled=false;
    const timer=setTimeout(()=>finish(new Error('The local service did not start within 30 seconds.')),30000);
    const finish=(error,value)=>{if(settled)return;settled=true;clearTimeout(timer);error?reject(error):resolve(value);};
    service.once('error',error=>finish(error));
    service.stdout.on('data',chunk=>{
      buffer+=chunk.toString();
      for(let end;(end=buffer.indexOf('\n'))>=0;){
        const line=buffer.slice(0,end);buffer=buffer.slice(end+1);
        try{const data=JSON.parse(line);if(data.ready&&Number.isInteger(data.port)&&data.port>0&&data.port<65536)finish(null,`http://127.0.0.1:${data.port}`);}catch{}
      }
    });
    service.once('exit',code=>{finish(new Error(`Local service stopped (${code}).`));if(!stopping&&settled)showFailure(new Error('The local service stopped. Relaunch Pixfun to continue. Your library is saved.'));});
  });
}

function trusted(event){
  if(event.sender!==window?.webContents || event.senderFrame!==window.webContents.mainFrame || !isOwnPage(event.senderFrame.url,origin))throw new Error('Untrusted window');
}
async function pick(folder=false,replaceId){
  const result=await dialog.showOpenDialog(window,{title:replaceId?'Locate original media':folder?'Import a footage folder':'Import footage',properties:folder?['openDirectory']:replaceId?['openFile']:['openFile','multiSelections'],filters:folder?undefined:[{name:'Videos, photos & audio',extensions:['mp4','mov','m4v','mkv','webm','avi','mts','m2ts','ogv','jpg','jpeg','png','webp','gif','avif','heic','heif','bmp','tif','tiff','mp3','wav','m4a','aac','flac','ogg','aiff','aif','opus']}]});
  if(result.canceled)return {ok:true,items:[],errors:[]};
  const selected=await collectMedia(result.filePaths,folder);
  const resultData=await api(replaceId?'/api/desktop/locate':'/api/desktop/register',{paths:selected.paths,...(replaceId?{id:replaceId}:{})},true);
  resultData.errors.push(...selected.errors);
  return resultData;
}
function installIPC(){
  ipcMain.handle('pixfun:pick',async(event,folder)=>{trusted(event);return pick(folder===true);});
  ipcMain.handle('pixfun:drop',async(event,paths)=>{trusted(event);const selected=await collectMedia(paths,true);const result=await api('/api/desktop/register',{paths:selected.paths},true);result.errors.push(...selected.errors);return result;});
  ipcMain.handle('pixfun:reveal',async(event,id)=>{trusted(event);const result=await api(`/api/desktop/native/${encodeURIComponent(id)}`,undefined,true);shell.showItemInFolder(result.path);});
  ipcMain.handle('pixfun:locate',async(event,id)=>{trusted(event);if(typeof id!=='string'||!/^[a-f0-9]{32}$/.test(id))throw new Error('Invalid media ID');return pick(false,id);});
  ipcMain.handle('pixfun:settings',async event=>{trusted(event);return api('/api/desktop/settings');});
}

function buildMenu(){
  const command=name=>window?.webContents.send('pixfun:command',name);
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {label:'Pixfun',submenu:[{role:'about'},{type:'separator'},{role:'hide'},{role:'hideOthers'},{role:'unhide'},{type:'separator'},{role:'quit'}]},
    {label:'File',submenu:[{label:'Import Footage…',accelerator:'CmdOrCtrl+O',click:()=>command('import')},{label:'Import Folder…',accelerator:'CmdOrCtrl+Shift+O',click:()=>command('folder')},{type:'separator'},{role:'close'}]},
    {role:'editMenu'},
    {label:'View',submenu:[{label:'Home',accelerator:'CmdOrCtrl+1',click:()=>command('home')},{label:'Media',accelerator:'CmdOrCtrl+2',click:()=>command('media')},{label:'Skills',accelerator:'CmdOrCtrl+3',click:()=>command('skills')},{label:'Project',accelerator:'CmdOrCtrl+4',click:()=>command('history')},{type:'separator'},{role:'resetZoom'},{role:'zoomIn'},{role:'zoomOut'},{role:'togglefullscreen'},...(!app.isPackaged?[{role:'toggleDevTools'}]:[])]},
    {role:'windowMenu'},
    {label:'Help',submenu:[{label:'About This Preview',click:()=>dialog.showMessageBox(window,{type:'info',title:'Pixfun for Mac',message:'Local workspace preview',detail:'Your original files stay in place. Media analysis and scene previews run locally. This build does not include AI scene recognition, speech models, automatic editing, or export.\n\nUse File → Import Footage to get started.'})},{label:'Show App Data in Finder',click:()=>shell.showItemInFolder(path.join(store,'library.sqlite3'))}]}
  ]));
}

async function boot(){
  if(process.platform==='darwin')app.dock.setIcon(path.join(__dirname,'icon.png'));
  installIPC();buildMenu();
  window=new BrowserWindow({width:1320,height:860,minWidth:960,minHeight:640,title:'Pixfun',backgroundColor:'#151819',titleBarStyle:'hiddenInset',trafficLightPosition:{x:18,y:15},show:false,webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,webSecurity:true,partition:'persist:pixfun-desktop'}});
  window.on('closed',()=>{window=null;app.quit();});
  const webSession=window.webContents.session;
  webSession.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
  webSession.setPermissionCheckHandler(()=>false);
  window.webContents.setWindowOpenHandler(()=>({action:'deny'}));
  window.webContents.on('will-navigate',(event,url)=>{if(!isOwnPage(url,origin))event.preventDefault();});
  window.webContents.on('will-attach-webview',event=>event.preventDefault());
  window.webContents.on('will-prevent-unload',event=>event.preventDefault());
  await window.loadFile(path.join(__dirname,'loading.html'));
  window.show();
  if(!app.isPackaged&&process.env.PIXFUN_PREVIEW_STARTUP==='1')return;
  window.webContents.send('pixfun:startup-status','Opening your local library…');
  origin=await startService();
  webSession.webRequest.onBeforeRequest((details,callback)=>callback({cancel:!isOwnPage(details.url,origin)&&!details.url.startsWith('blob:')&&details.url!=='devtools://devtools/bundled/inspector.html'}));
  webSession.webRequest.onBeforeSendHeaders({urls:[origin+'/*']},(details,callback)=>callback({requestHeaders:{...details.requestHeaders,Authorization:`Bearer ${token}`}}));
  const health=await api('/api/health');
  if(!health.tools.ffmpeg||!health.tools.ffprobe)throw new Error('The bundled media tools are missing. Rebuild the app.');
  window.webContents.send('pixfun:startup-status','Loading your workspace…');
  await window.loadURL(origin+'/#workspace/home');
}

async function showFailure(error){
  if(stopping||startupError)return;startupError=true;
  await dialog.showMessageBox({type:'error',title:'Pixfun could not start',message:error.message,detail:`Your files have not been changed. Diagnostic log: ${path.join(store,'service.log')}`,buttons:['Quit']});
  app.quit();
}
app.on('before-quit',event=>{
  if(stopping||!service||service.exitCode!==null)return;
  event.preventDefault();stopping=true;
  service.once('exit',()=>app.quit());
  service.kill('SIGTERM');
  const timer=setTimeout(()=>{service.kill('SIGKILL');app.quit();},5000);timer.unref();
});
