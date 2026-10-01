'use strict';
const fs=require('node:fs/promises');
const path=require('node:path');
const extensions=new Set('mp4 mov m4v mkv webm avi mts m2ts ogv jpg jpeg png webp gif avif heic heif bmp tif tiff mp3 wav m4a aac flac ogg aiff aif opus'.split(' '));
function isOwnPage(url,origin){try{return !!origin&&new URL(url).origin===origin;}catch{return false;}}
async function collectMedia(input,folders=false){
  if(!Array.isArray(input)||input.length>1000||input.some(p=>typeof p!=='string'||!path.isAbsolute(p)))throw new Error('Invalid file selection');
  const paths=[],errors=[],seen=new Set();let scanned=0,truncated=false;
  async function visit(file,depth=0){
    if(paths.length>=100||++scanned>10000){truncated=true;return;}
    try{
      const info=await fs.lstat(file);
      if(info.isSymbolicLink())return; // Folder imports must not escape through links.
      if(info.isDirectory()&&folders&&depth<20){for(const name of await fs.readdir(file)){if(name.startsWith('.'))continue;await visit(path.join(file,name),depth+1);if(truncated)break;}}
      else if(info.isFile()&&extensions.has(path.extname(file).slice(1).toLowerCase())){const resolved=await fs.realpath(file);if(!seen.has(resolved)){seen.add(resolved);paths.push(resolved);}}
    }catch{errors.push(`${path.basename(file)}: cannot read this file`);}
  }
  for(const file of input)await visit(file);
  if(truncated)errors.push('This batch is limited to 100 media files. Import the remaining files in another batch.');
  if(!paths.length&&!errors.length)errors.push('No supported videos, photos, or audio files were found.');
  return {paths,errors};
}
module.exports={collectMedia,isOwnPage};
