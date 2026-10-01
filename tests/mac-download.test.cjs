const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.join(__dirname,'..'),html=fs.readFileSync(path.join(root,'public/index.html'),'utf8');
for(const id of ['downloadMac','homeDownload']){
 const link=html.match(new RegExp('<a[^>]*id="'+id+'"[^>]*>'))?.[0];
 assert(link);assert(link.includes('href="/mac-early-access"'));assert(!link.includes(' download'));
}
assert(html.includes('Mac app in development'));
const header=html.split('<header class="header wrap">')[1].split('</header>')[0];
for(const id of ['stories','how','creators'])assert(!header.includes('href="#'+id+'"'));
const form=fs.readFileSync(path.join(root,'public/mac-early-access.html'),'utf8');
assert.equal(form.split('<fieldset>').length-1,4);
assert(form.indexOf('id="email"')<form.indexOf('name="budgetRange"'));
assert(form.includes('USD'));assert(form.includes('Not sure yet'));assert(form.includes('type="email"'));
assert.equal((form.match(/name="budgetRange"/g)||[]).length,7);
assert(!form.includes('id="monthlyUsd"'));assert(!form.includes('Applying does not guarantee'));
for(const value of ['enthusiast','creator','editor','studio','brand','other'])assert(form.includes('value="'+value+'"'));
for(const value of ['youtube','tiktok','instagram'])assert(form.includes('name="platforms" value="'+value+'"'));
const js=fs.readFileSync(path.join(root,'public/mac-early-access.js'),'utf8');
assert(js.includes("fetch('/api/mac-applications'"));assert(js.includes('data?.ok!==true'));assert(!js.includes('localStorage'));
console.log('PASS: Four-question Mac application with real submission and price last.');
