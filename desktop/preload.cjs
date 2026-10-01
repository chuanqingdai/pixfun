'use strict';
const {contextBridge,ipcRenderer,webUtils}=require('electron');
// No generic IPC, filesystem access, service secrets, or shell execution crosses this bridge.
contextBridge.exposeInMainWorld('PixfunDesktop',{
  version:'0.1.4',
  chooseFiles:folder=>ipcRenderer.invoke('pixfun:pick',folder===true),
  importFiles:files=>ipcRenderer.invoke('pixfun:drop',Array.from(files).map(file=>webUtils.getPathForFile(file)).filter(Boolean)),
  reveal:id=>ipcRenderer.invoke('pixfun:reveal',id),
  locate:id=>ipcRenderer.invoke('pixfun:locate',id),
  settings:()=>ipcRenderer.invoke('pixfun:settings'),
  onStartupStatus:callback=>{const listener=(_event,text)=>callback(text);ipcRenderer.on('pixfun:startup-status',listener);return()=>ipcRenderer.removeListener('pixfun:startup-status',listener);},
  onCommand:callback=>{const listener=(_event,command)=>callback(command);ipcRenderer.on('pixfun:command',listener);return()=>ipcRenderer.removeListener('pixfun:command',listener);}
});
