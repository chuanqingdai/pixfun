// Download real travel footage with per-file provenance; never alters existing Media entries.
import fs from 'node:fs';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const exec = promisify(execFile);
const root=path.resolve('data/travel-import-20260927');
fs.mkdirSync(root,{recursive:true});
const get=async url=>(await exec('curl',['-L','--fail','--silent','--show-error','--max-time','40',url],{maxBuffer:12e6})).stdout;
const clean=s=>s.replace(/<[^>]*>/g,' ').replace(/&amp;/g,'&').replace(/\s+/g,' ').trim();
const categories=['city','food','beach','underwater','snow','boat'];
if(process.argv.includes('--discover')){
  for(const topic of categories){
    try{const html=await get(`https://mixkit.co/free-stock-video/${topic}/`);
    console.log(topic,[...new Set([...html.matchAll(/href="(\/free-stock-video\/[^" ]+-\d+\/)"/g)].map(x=>x[1]))].slice(0,9));}
    catch(e){console.log(topic,e.message);}
  }
  process.exit();
}
const selections = [
  ...[
    ['Tokyo Pedestrian Walk','City walk','pedestrian-walk-in-tokyo-4231'],
    ['Times Square in the Rain','Urban nightlife','times-square-during-a-rainy-night-4332'],
    ['City Train under a Bridge','Urban transit','city-train-driving-under-a-bridge-1606'],
    ['Spaghetti at the Table','Food travel','serving-parmesan-cheese-in-spaghetti-bolognese-close-up-engraving-12171'],
    ['Cafe Coffee Break','Cafe hopping','woman-drinking-coffee-in-a-cafe-223'],
    ['Orange Beach Sunset','Beach escape','bright-orange-sunset-on-beach-2168'],
    ['Sea Turtle on the Reef','Underwater wildlife','sea-turtle-feeding-on-the-seabed-4465'],
    ['Swiss Alps Time Lapse','Alpine landscape','swiss-alps-snow-background-time-lapse-4283'],
    ['Island Marina from Above','Island sailing','beautiful-coast-with-motorboats-and-a-pier-seen-from-the-5363'],
    ['Forest Road Journey','Road trip','traveling-on-an-empty-road-covered-in-trees-4852'],
    ['Desert Road from Above','Desert adventure','road-that-passes-through-the-rugged-relief-of-a-desert-51792'],
    ['Flight Preparing for Departure','Air travel','flight-getting-ready-for-departure-4065'],
    ['Night from a Car Window','Night drive','view-out-of-a-car-window-at-night-42037'],
    ['Arriving at the Hotel','Hotel stay','couple-arriving-at-their-accommodation-101723'],
  ].map(([name,theme,slug])=>({name,theme,page:`https://mixkit.co/free-stock-video/${slug}/`})),
  ...[
    ['Yellowstone Fountain Geyser','Geothermal nature','4D22CDC8-155D-451F-6712CC6A99529123'],
    ['Arches Desert Waterfall','Desert rainfall','74731EDF-C017-7C7B-3698C2541F508E00'],
    ['Morning Fog over Yellowstone','River valley soundscape','B81C04A3-155D-451F-67E109B6D4E47DC3'],
    ['Yellowstone Off-Peak Travel Guide','Shoulder-season travel','774ED29A-92F0-4524-99BF-24E9F522EE8B'],
    ['Yellowstone Bison','Wildlife watching','F945D0A2-155D-451F-67A3EB8493064929'],
    ['Yellowstone Winter Travel Guide','Narrated winter travel','ACBD450A-B52D-4DBF-A04C-2BEB4865A258'],
    ['Zion Wilderness with a Ranger','Wilderness hiking guide','2EF0117C-155D-451F-6718752F14528384'],
    ['Lake Clark Alaska Journey','Alaska landscape and wildlife','a7ea1719-005e-42cd-b7c9-79cda436ecad'],
    ['Zion National Park Visitor Guide','Canyon travel guide','9FA3B222-155D-451F-67211732D9E00AEB'],
  ].map(([name,theme,id])=>({name,theme,page:`https://www.nps.gov/media/video/view.htm?id=${id}`})),
];
async function collect(entry){
  const cached=path.join(root,entry.name+'.json');
  if(fs.existsSync(cached)){const record=JSON.parse(fs.readFileSync(cached));if(fs.statSync(record.file).size===record.bytes)return record;}
  const html=await get(entry.page);fs.writeFileSync(path.join(root,entry.name+'.source.html'),html);
  let url,license,credit;
  if(entry.page.includes('mixkit.co')){
    if(!html.includes('commercial or personal use'))throw Error('Free license not confirmed: '+entry.name);
    const urls=[...html.matchAll(/https:\/\/assets\.mixkit\.co\/videos\/[^"\s<>]+\.mp4/g)].map(x=>x[0]);
    const download=html.match(/value="([^" ]*\/free-stock-video\/download\/[^" ]*type=1080p)"/);
    if(download){const panel=await get('https://mixkit.co'+download[1].replace(/&amp;/g,'&'));url=panel.match(/data-download--modal-url-value="([^"]+)"/)?.[1];}
    url ||= urls.find(x=>x.includes('-1080.mp4'))||urls.find(x=>x.includes('-720.mp4'));
    license='Mixkit Stock Video Free License';credit='Mixkit contributor (see source page)';
  }else{
    const urls=[...html.matchAll(/<source src="([^"]+\.mp4)"/g)].map(x=>x[1]);
    url=urls.find(x=>x.includes('1080p'))||urls.find(x=>x.includes('720p'))||urls[0];
    credit=clean(html.match(/<h[23][^>]*>Credit<\/h[23]>([\s\S]*?)(?=<h[23]|<\/section>)/i)?.[1]||'');
    if(!credit.includes('NPS')||credit.includes('©'))throw Error('Public-domain NPS credit not confirmed: '+entry.name+' '+credit);
    license='Public domain — NPS credit without copyright symbol';
  }
  if(!url)throw Error('No downloadable source: '+entry.name);
  const file=path.join(root,entry.name+'.mp4');
  if(!fs.existsSync(file))await exec('curl',['-L','--fail','--silent','--show-error','--retry','2','--max-time','240',url,'-o',file],{maxBuffer:1e6});
  const probe=JSON.parse((await exec('ffprobe',['-v','error','-show_streams','-show_format','-of','json',file])).stdout);
  const v=probe.streams.find(x=>x.codec_type==='video'),a=probe.streams.find(x=>x.codec_type==='audio');
  if(!v)throw Error('Missing video: '+entry.name);
  let volume=null;
  if(a){const r=await exec('ffmpeg',['-hide_banner','-i',file,'-vn','-af','volumedetect','-f','null','-'],{maxBuffer:2e6});volume=r.stderr.match(/mean_volume: ([^\n]+)/)?.[1];}
  const record={...entry,file,url,license,credit,duration:Number(probe.format.duration),width:v.width,height:v.height,bytes:Number(probe.format.size),audio:a?{codec:a.codec_name,channels:a.channels,sampleRate:a.sample_rate,duration:Number(a.duration||probe.format.duration),meanVolume:volume}:null};
  fs.writeFileSync(path.join(root,entry.name+'.json'),JSON.stringify(record,null,2));
  console.log(JSON.stringify(record));return record;
}
const results=[];
for(let i=0;i<selections.length;i+=3){
  const batch=await Promise.all(selections.slice(i,i+3).map(e=>collect(e).catch(error=>{console.error('FAILED',e.name,error.message);return null;})));
  results.push(...batch.filter(Boolean));
  fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(results,null,2));
}
