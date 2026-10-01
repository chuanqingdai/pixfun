// Source discovery only: fetch public catalog metadata; never touch user footage.
import {execFileSync} from 'node:child_process';
const get=url=>execFileSync('curl',['-L','--fail','--silent','--show-error','--max-time','40',url],{encoding:'utf8',maxBuffer:8e6});
const topics=process.argv.slice(2);
for(const topic of topics){
 const html=get(`https://mixkit.co/free-stock-video/${topic}/`);
 const links=[...new Set([...html.matchAll(/href="(\/free-stock-video\/[^" ]+-\d+\/)"/g)].map(x=>x[1]))].slice(0,8);
 for(const link of links){try{
  const page=get('https://mixkit.co'+link);
  const duration=page.match(/"duration"\s*:\s*"([^"]+)"/)?.[1];
  const video=[...page.matchAll(/https:\/\/assets\.mixkit\.co\/videos\/[^"\s<>]+\.mp4/g)].map(x=>x[0]).find(x=>x.includes('-720.mp4'));
  console.log(JSON.stringify({topic,page:'https://mixkit.co'+link,duration,free:page.includes('commercial or personal use'),video}));
 }catch(e){console.error(link,e.message.slice(0,100));}}
}
