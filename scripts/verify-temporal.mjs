import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {measureTemporal} from './temporal-sequence.mjs';
import {checkTemporalControls} from './temporal-controls.mjs';
const baseline=process.argv.includes('--baseline');
const browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
const page=await browser.newPage({viewport:{width:1440,height:900}});const errors=[];
page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
try{
  await page.goto('http://127.0.0.1:4327/');await page.waitForFunction(()=>forestDiagnostics?.ready||forestDiagnostics?.errors.length,{},{timeout:240000});assert.deepEqual(await page.evaluate(()=>forestDiagnostics.errors),[]);
  const sourceSha256=await page.evaluate(()=>forestDiagnostics.sourceSha256);const cases={};
  for(const [name,settings] of Object.entries({stationary:{},wind:{wind:true},moving:{wind:true,camera:true},painted:{wind:true,paint:true}})){
    cases[name]=await measureTemporal(page,settings);console.log(name,JSON.stringify(cases[name].groups));
    await writeFile(`artifacts/${baseline?'before':'after'}-jitter-${name}.png`,Buffer.from(await page.evaluate(()=>forestTest.pixelSnapshot())));
  }
  const controls=baseline?null:await checkTemporalControls(page);
  const report={sourceSha256,cases,controls,errors,boundary:'32 measured frames after 32 warmup frames, identical seed/camera/input/clock at 960x600; fixed wind isolates sampling flicker. Moving cases include genuine wind/camera changes. Unpainted cases disable the final painting pass.'};
  if(!baseline){
    const before=JSON.parse(await readFile('artifacts/before-jitter.json','utf8'));
    for(const name of ['stationary','wind'])for(const material of [2,3,8]){
      assert(cases[name].groups[material].mae8bit<before.cases[name].groups[material].mae8bit*.85,`${name} material ${material} did not reduce flicker by 15%`);
    }
    console.log('PASS underlying foliage flicker reduced with painting disabled');
    for(const m of [2,3,8])assert(cases.painted.groups[m].mae8bit<cases.wind.groups[m].mae8bit*1.1,`Painting adds foliage flicker for material ${m}`);
    assert(controls.finite&&controls.heldUsesHistory);assert(controls.resetError<1e-6&&controls.disocclusionError<1e-6);assert(controls.resetCounts.every(v=>v===1));assert(controls.clampedError<.003);
    console.log('PASS reset, disocclusion rejection, history clipping and partial workgroups');
  }
  assert.deepEqual(errors,[]);assert.deepEqual(await page.evaluate(()=>forestDiagnostics.errors),[]);
  await writeFile(`artifacts/${baseline?'before':'after'}-jitter.json`,JSON.stringify(report,null,2));
}finally{await browser.close();}
