import {chromium} from 'playwright';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {compareCachedRendering} from './render-oracle.mjs';
import {benchmarkRendering} from './benchmark-render.mjs';
const browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
const page=await browser.newPage({viewport:{width:1440,height:900}});const errors=[];
page.on('pageerror',e=>{errors.push(String(e));console.log('ERROR',String(e));});
page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
try{
  await page.goto('http://127.0.0.1:4327');await page.waitForFunction(()=>forestDiagnostics?.ready||forestDiagnostics?.errors.length,{},{timeout:240000});
  if(await page.evaluate(()=>forestDiagnostics.errors.length))throw Error('GPU initialization failed');
  console.log('Ready');await page.evaluate(()=>forestTest.start(1));
  const benchmark=await benchmarkRendering(page);
  const equivalence=await compareCachedRendering(page);console.log('Equivalence',equivalence);
  await page.evaluate(()=>forestTest.start(1));await page.evaluate(()=>forestTest.render(96,{width:1920,hour:16.2,frame:0,reset:true}));
  await writeFile('artifacts/new-rock-shapes.png',Buffer.from(await page.evaluate(()=>forestTest.pixelSnapshot())));
  await page.screenshot({path:'artifacts/new-rock-shapes-ui.png'});
  assert.deepEqual(errors,[]);
  const report={sourceSha256:await page.evaluate(()=>forestDiagnostics.sourceSha256),...benchmark,equivalence,errors,summary:await page.evaluate(()=>forestTest.summary())};
  await writeFile('artifacts/geometry-cache-comparison.json',JSON.stringify(report,null,2));console.log('Captured');
}finally{await browser.close();}
