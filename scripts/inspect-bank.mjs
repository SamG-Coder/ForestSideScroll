import {chromium} from 'playwright';
import {writeFile} from 'node:fs/promises';
const browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
const page=await browser.newPage({viewport:{width:1440,height:900}});const errors=[];
page.on('pageerror',e=>{errors.push(String(e));console.log('ERROR',String(e));});
page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
const stats=a=>{a.sort((a,b)=>a-b);return {median:a[Math.floor(a.length*.5)],p95:a[Math.floor(a.length*.95)]};};
try{
  await page.goto('http://127.0.0.1:4327');await page.waitForFunction(()=>forestDiagnostics?.ready||forestDiagnostics?.errors.length,{},{timeout:240000});console.log('Ready');
  await page.evaluate(()=>forestTest.start(1));
  const results={};
  for(const cached of [false,true]){
    await page.evaluate(cached=>forestTest.render(4,{width:960,frame:100,reset:true,frozen:false,useLightingCache:cached}),cached);
    const result=await page.evaluate(cached=>forestTest.render(32,{frozen:false,useLightingCache:cached}),cached);
    results[cached?'cached':'fresh']={...stats(result.times),lighting:await page.evaluate(()=>forestTest.lightingStats())};
    await writeFile(`artifacts/lighting-${cached?'cached':'fresh'}.png`,Buffer.from(await page.evaluate(()=>forestTest.pixelSnapshot())));
    console.log(cached?'Cached':'Fresh',results[cached?'cached':'fresh']);
  }
  await page.evaluate(()=>forestTest.render(64,{width:1920,hour:16.2,reset:true,frame:0}));
  await writeFile('artifacts/bank-revision.png',Buffer.from(await page.evaluate(()=>forestTest.pixelSnapshot())));
  await page.screenshot({path:'artifacts/bank-revision-ui.png'});console.log('Captured');
  results.errors=errors;results.summary=await page.evaluate(()=>forestTest.summary());
  await writeFile('artifacts/bank-inspection.json',JSON.stringify(results,null,2));
}finally{await browser.close();}
