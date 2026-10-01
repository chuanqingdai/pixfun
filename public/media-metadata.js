/* Local metadata only: never infer subjects or shooting dates from filenames. */
(() => {
  function dateText(value) {
    if(typeof value!=='string')return '';
    const match=value.match(/^(\d{4})[:-](\d{2})[:-](\d{2})[T ](\d{2}):(\d{2}):(\d{2})/);
    if(!match)return '';
    const [,y,m,d,h,min,s]=match;
    const date=new Date(Date.UTC(+y,+m-1,+d,+h,+min,+s));
    if(+y<1900||date.getUTCFullYear()!==+y||date.getUTCMonth()!==+m-1||date.getUTCDate()!==+d||+h>23||+min>59||+s>59)return '';
    // Preserve the recorded local date; EXIF frequently has no timezone.
    return `${y}-${m}-${d} ${h}:${min}`;
  }
  function readExif(buffer) {
    try {
      const v=new DataView(buffer);
      if(v.getUint16(0)!==0xffd8)return {};
      for(let pos=2;pos+4<v.byteLength;){
        const marker=v.getUint16(pos),length=v.getUint16(pos+2),end=pos+2+length;
        if(marker===0xffda||marker===0xffd9||length<2||end>v.byteLength)break;
        if(marker===0xffe1&&length>=16&&v.getUint32(pos+4)===0x45786966&&v.getUint16(pos+8)===0){
          const base=pos+10,byteOrder=v.getUint16(base),little=byteOrder===0x4949;
          if(![0x4949,0x4d4d].includes(byteOrder)||v.getUint16(base+2,little)!==42)return {};
          const inside=(p,n)=>p>=base&&p+n<=end;
          const ascii=(entry)=>{
            const count=v.getUint32(entry+4,little);
            if(v.getUint16(entry+2,little)!==2||!count||count>256)return '';
            const p=count<=4?entry+8:base+v.getUint32(entry+8,little);
            if(!inside(p,count))return '';
            return new TextDecoder().decode(new Uint8Array(buffer,p,count)).replace(/\0.*$/s,'').trim();
          };
          const fields={},seen=new Set();
          function ifd(offset,depth=0){
            const p=base+offset;if(depth>1||seen.has(p)||!inside(p,2))return;seen.add(p);
            const count=v.getUint16(p,little);if(count>512||!inside(p+2,count*12))return;
            for(let i=0;i<count;i++){
              const e=p+2+i*12,tag=v.getUint16(e,little);
              if(tag===0x8769&&v.getUint16(e+2,little)===4)ifd(v.getUint32(e+8,little),depth+1);
              if(tag===0x9003)fields.capturedAt=ascii(e);
              if(tag===0x0110)fields.camera=ascii(e);
            }
          }
          ifd(v.getUint32(base+4,little));
          if(!dateText(fields.capturedAt))delete fields.capturedAt;
          if(fields.capturedAt)fields.dateSource='EXIF DateTimeOriginal';
          return fields;
        }
        pos=end;
      }
    } catch { /* Missing or malformed EXIF must not fail import. */ }
    return {};
  }
  function tags(item) {
    const m=item.metadata||{},result=[];
    const captured=dateText(m.capturedAt),created=dateText(m.mediaCreatedAt);
    if(captured)result.push(`Shot ${captured.slice(0,10)}`);
    else if(created)result.push(`Created ${created.slice(0,10)}`);
    if(m.camera)result.push(String(m.camera).slice(0,80));
    if(m.width&&m.height)result.push(m.height>m.width?'Portrait':m.height===m.width?'Square':'Landscape');
    if(m.width&&m.height){const edge=Math.min(m.width,m.height);if(edge>=2160)result.push('4K');else if(edge>=1080)result.push('1080p');}
    if(item.kind==='video'&&typeof m.hasAudio==='boolean')result.push(m.hasAudio?'Audio':'Silent');
    if(item.result?.analysis.subtitleCues?.length)result.push('Subtitles');
    return result;
  }
  function searchText(item){return [item.file.name,item.kind==='image'?'Photo':'Video',...tags(item),dateText(item.metadata?.capturedAt),dateText(item.metadata?.mediaCreatedAt)].join(' ').toLowerCase();}
  const api={dateText,readExif,tags,searchText};
  if(typeof module!=='undefined')module.exports=api;else window.PixfunMetadata=api;
})();
