import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {profileKernels} from './gpu-profile.mjs';
const hash=data=>createHash('sha256').update(data).digest('hex');
const manifest=JSON.parse(await readFile('generated/manifest.json','utf8'));
assert.equal(hash((await Promise.all(manifest.files.map(f=>readFile(`src/${f}.cu`,'utf8')))).join('\n')),manifest.sourceSha256);
for(const entry of manifest.entries){assert.equal(hash(await readFile(`generated/${entry.entry}.json`)),entry.sha256);assert.equal(hash(Buffer.from(await (await fetch(`http://127.0.0.1:4327/generated/${entry.entry}.json`)).arrayBuffer())),entry.sha256);}
const browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
const page=await browser.newPage({viewport:{width:1440,height:900},acceptDownloads:true});const errors=[],failedRequests=[],checks=[];
page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});page.on('response',r=>{if(r.status()>=400)failedRequests.push(`${r.status()} ${r.url()}`);});
const check=name=>{checks.push(name);console.log('PASS',name);};
try{
  await page.goto('http://127.0.0.1:4327/');await page.waitForFunction(()=>forestDiagnostics?.ready||forestDiagnostics?.errors.length,{},{timeout:240000});assert.deepEqual(await page.evaluate(()=>forestDiagnostics.errors),[]);
  assert.equal(await page.evaluate(()=>forestTest.backend.name),'webgpu');assert(await page.locator('#native-cuda').isDisabled());
  await page.evaluate(()=>forestTest.start(2));
  assert.equal(await page.evaluate(()=>forestTest.options.oilPaint),false);assert(await page.locator('#paint-strength').isDisabled());
  const defaultDepths=await page.evaluate(()=>forestTest.options.paintDepths);
  for(const layer of Object.keys(defaultDepths))assert(await page.locator(`#depth-${layer}`).isDisabled());
  await page.evaluate(()=>forestTest.render(128,{width:960,hour:16.2,frame:0,reset:true}));
  const mask=await page.evaluate(async()=>{
    const objects=await forestTest.read('objects'),guide=await forestTest.read('guide'),albedo=await forestTest.read('albedo');
    const pixels=await forestTest.read('pixels');const material=new Int8Array(pixels.length);const counts={};let wrongTags=0;
    for(let i=0;i<pixels.length;i++){const id=guide[i*4+3];const mat=id>=0?objects[id*16+11]:id;material[i]=mat;counts[mat]=(counts[mat]||0)+1;
      const masked=[2,3,8].includes(mat);if(masked!==[2,3,8].includes(albedo[i*4+3]))wrongTags++;}
    const hdr=new Float32Array(await forestTest.read('filtered'));const sha=async a=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',a.buffer))).map(x=>x.toString(16).padStart(2,'0')).join('');
    window.paintOracle={pixels,material,hdrHash:await sha(hdr),cache:forestTest.cache};return {counts,wrongTags};
  });
  assert.equal(mask.wrongTags,0);assert(mask.counts[2]>1000&&mask.counts[3]>100&&mask.counts[8]>100);check('Geometry identifies all visible material groups; default effect is off');
  await page.click('#settings-button');await page.check('#oil-paint');assert(!(await page.locator('#paint-strength').isDisabled()));
  const comparisons=[];
  for(const strength of [.35,.75,1,0]){
    await page.locator('#paint-strength').evaluate((el,value)=>{el.value=String(value);el.dispatchEvent(new Event('input',{bubbles:true}));},strength);
    await page.evaluate(()=>forestTest.render(1));
    const comparison=await page.evaluate(async()=>{
      const current=await forestTest.read('pixels'),before=window.paintOracle;const changed={};let outside=0,absolute=0,alphaErrors=0,foliage=0;
      for(let i=0;i<current.length;i++){const mat=before.material[i];const plant=[2,3,8].includes(mat);if(plant)foliage++;if(current[i]!==before.pixels[i]){changed[mat]=(changed[mat]||0)+1;if(!plant)outside++;}
        if((current[i]>>>24)!==255)alphaErrors++;if(plant)for(const shift of [0,8,16])absolute+=Math.abs(((current[i]>>>shift)&255)-((before.pixels[i]>>>shift)&255));}
      const hdr=new Float32Array(await forestTest.read('filtered'));const hdrHash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',hdr.buffer))).map(x=>x.toString(16).padStart(2,'0')).join('');
      return {strength:forestTest.options.paintStrength,changed,outside,alphaErrors,meanFoliageDifference:absolute/(foliage*3),hdrUnchanged:hdrHash===before.hdrHash,cache:forestTest.cache,originalCache:before.cache};
    });
    assert(comparison.strength===0?comparison.outside===0:comparison.outside>1000);assert.equal(comparison.alphaErrors,0);assert(comparison.hdrUnchanged);assert.equal(comparison.cache.tracedFrames,comparison.originalCache.tracedFrames);assert.equal(comparison.cache.geometryBakes,comparison.originalCache.geometryBakes);
    if(strength>0)for(const m of [-9,-2,-1,1,2,3,4,8])assert(comparison.changed[m]>50,`Material ${m} not painted`);else assert.deepEqual(comparison.changed,{});
    comparisons.push(comparison);console.log('Strength',strength,'foliage RGB difference',comparison.meanFoliageDifference);
  }
  assert(comparisons[1].meanFoliageDifference>comparisons[0].meanFoliageDifference);check('Painting changes sky, water, soil, trunks, rocks and all vegetation; zero strength restores exact original pixels');
  await page.locator('#paint-strength').evaluate(el=>{el.value='0.75';el.dispatchEvent(new Event('input',{bubbles:true}));});await page.evaluate(()=>forestTest.render(1));
  const held=await page.evaluate(async()=>{const before=forestTest.cache;await forestTest.render(8);return {before,after:forestTest.cache};});assert.equal(held.before.paintPasses,held.after.paintPasses);assert.equal(held.before.tracedFrames,held.after.tracedFrames);
  await page.uncheck('#oil-paint');await page.evaluate(()=>forestTest.render(1));assert(await page.evaluate(async()=>{const p=await forestTest.read('pixels');return p.every((v,i)=>v===paintOracle.pixels[i]);}));
  check('Toggling/adjusting a converged still runs only the final resolve; unchanged painted stills submit no new GPU passes; disabling restores exact pixels');
  await page.check('#oil-paint');await page.evaluate(()=>forestTest.render(1));
  const layerResults=[];
  for(const layer of Object.keys(defaultDepths)){
    for(const key of Object.keys(defaultDepths))await page.locator(`#depth-${key}`).evaluate((el,value)=>{el.value=String(value);el.dispatchEvent(new Event('input',{bubbles:true}));},Number(key===layer));
    await page.evaluate(()=>forestTest.render(1));
    const result=await page.evaluate(async layer=>{
      const coverage=await forestTest.read('coverage'),pixels=await forestTest.read('pixels');let invalid=0,changed=0,outside=0;const channel={trees:0,rocks:1,foliage:2,water:3}[layer];
      for(let i=0;i<pixels.length;i++){
        let sum=0;for(let c=0;c<4;c++){const v=coverage[i*4+c];if(!Number.isFinite(v)||v<0||v>1.000001)invalid++;sum+=v;}if(sum>1.000001)invalid++;
        let weight=coverage[i*4+channel];if(layer==='trees')weight+=Math.max(0,1-sum);
        if(pixels[i]!==paintOracle.pixels[i]){changed++;if(weight<.0001)outside++;}
      }
      return {layer,invalid,changed,outside,cache:forestTest.cache};
    },layer);
    assert.equal(result.invalid,0);assert.equal(result.outside,0);assert(result.changed>1000);assert.equal(result.cache.tracedFrames,comparisons[0].originalCache.tracedFrames);layerResults.push(result);
  }
  for(const layer of Object.keys(defaultDepths))await page.locator(`#depth-${layer}`).evaluate(el=>{el.value='0';el.dispatchEvent(new Event('input',{bubbles:true}));});
  await page.evaluate(()=>forestTest.render(1));assert(await page.evaluate(async()=>{const p=await forestTest.read('pixels');return p.every((v,i)=>v===paintOracle.pixels[i]);}));
  for(const [layer,depth] of Object.entries(defaultDepths))await page.locator(`#depth-${layer}`).evaluate((el,value)=>{el.value=String(value);el.dispatchEvent(new Event('input',{bubbles:true}));},depth);
  await page.evaluate(()=>forestTest.render(1));
  check('Each layer depth changes only its own stable coverage without retracing; all-zero depths restore exact pixels');
  const performance=await profileKernels(page,{oilPaint:true,paintStrength:.75});assert(performance.paintScene);console.log('GPU paint pass',performance.paintScene);
  await page.setViewportSize({width:1440,height:907});
  const state=await page.evaluate(()=>forestTest.hold());state[7]=1;state[0]=0;state[11]=0;state[13]=0;state[12]=20.7;state[14]=20.7;state[2]=20.7;
  await page.evaluate(s=>forestTest.setState(s),state);await page.evaluate(()=>forestTest.render(24,{width:768,oilPaint:true}));assert((await page.evaluate(()=>forestTest.summary())).finite);
  check('Painting works on the other bank with a partial bottom workgroup');
  await page.setViewportSize({width:1440,height:900});await page.selectOption('#quality','1920');await page.evaluate(()=>forestTest.start(2));
  await page.evaluate(()=>forestTest.render(128,{width:1920,hour:16.2,frame:0,reset:true,oilPaint:false}));await writeFile('artifacts/scene-paint-before.png',Buffer.from(await page.evaluate(()=>forestTest.pixelSnapshot())));
  await page.evaluate(()=>forestTest.render(1,{oilPaint:true}));await writeFile('artifacts/scene-paint-after.png',Buffer.from(await page.evaluate(()=>forestTest.pixelSnapshot())));await page.screenshot({path:'artifacts/scene-paint-settings.png'});
  const downloadEvent=page.waitForEvent('download');await page.click('#capture');const download=await downloadEvent;await download.saveAs('artifacts/scene-paint-export.png');
  assert.equal(hash(await readFile('artifacts/scene-paint-export.png')),hash(await readFile('artifacts/scene-paint-after.png')));check('PNG export contains the exact painted image');
  const savedDepths={trees:.55,rocks:.8,foliage:.65,water:.35};for(const [layer,depth] of Object.entries(savedDepths))await page.locator(`#depth-${layer}`).evaluate((el,value)=>{el.value=String(value);el.dispatchEvent(new Event('input',{bubbles:true}));},depth);
  await page.reload();await page.waitForFunction(()=>forestDiagnostics?.ready||forestDiagnostics?.errors.length,{},{timeout:240000});
  assert.equal(await page.evaluate(()=>forestTest.options.oilPaint),true);assert.equal(await page.evaluate(()=>forestTest.options.paintStrength),.75);assert.deepEqual(await page.evaluate(()=>forestTest.options.paintDepths),savedDepths);check('The toggle, strength and four layer depths survive a reload');
  assert.deepEqual(errors,[]);assert.deepEqual(failedRequests,[]);assert.deepEqual(await page.evaluate(()=>forestDiagnostics.errors),[]);check('No browser errors, GPU validation errors, or failed assets');
  await writeFile('artifacts/scene-paint-validation.json',JSON.stringify({sourceSha256:manifest.sourceSha256,checks,mask,comparisons,held,layerResults,gpuKernels:performance,errors,failedRequests,boundary:'Painting covers the whole scene in material layers after temporal antialiasing and replaces the final resolve; GPU timings are from 16 timestamped passes at 960x600. Excludes simulation and presentation.'},null,2));
  console.log('Checks',checks.length);
}finally{await browser.close();}
