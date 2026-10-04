import {chromium} from 'playwright';
import {writeFile} from 'node:fs/promises';
const browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
const page=await browser.newPage({viewport:{width:1440,height:900}});const errors=[];
page.on('pageerror',e=>{errors.push(String(e));console.log('ERROR',String(e));});
page.on('console',m=>{if(m.type()==='error'){errors.push(m.text());console.log('CONSOLE',m.text());}});
try{
  await page.goto('http://127.0.0.1:4327');
  await page.waitForFunction(()=>window.forestDiagnostics?.ready||window.forestDiagnostics?.errors.length,{},{timeout:180000});
  console.log(JSON.stringify(await page.evaluate(()=>forestDiagnostics),null,2));
  if(await page.evaluate(()=>forestDiagnostics.errors.length))throw Error('GPU initialization failed');
  await page.evaluate(()=>forestTest.hold());
  const t=Date.now();await page.evaluate(()=>forestTest.render(24,{reset:true}));console.log('24 passes ms',Date.now()-t);
  await page.screenshot({path:'artifacts/revised-menu.png'});
  await page.evaluate(()=>forestTest.start(1));await page.evaluate(()=>forestTest.render(96,{reset:true,width:1920}));
  await page.screenshot({path:'artifacts/revised-scene.png'});
  const summary=await page.evaluate(()=>forestTest.summary());console.log('SUMMARY',JSON.stringify(summary));
  await writeFile('artifacts/initial-validation.json',JSON.stringify({errors,summary,diagnostics:await page.evaluate(()=>forestDiagnostics)},null,2));
}finally{await browser.close();}
