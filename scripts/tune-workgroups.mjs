import {chromium} from 'playwright';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {compile,serializableArtifact} from '../vendor/cuda-webshader/compiler/compiler.js';
const source=(await Promise.all(['common','game','generate','materials','trace','render'].map(f=>readFile(`src/${f}.cu`,'utf8')))).join('\n');
const variants=[[8,8,1],[8,4,1],[16,4,1],[16,2,1],[4,8,1],[32,2,1],[4,4,1]];
const artifacts=variants.map(workgroupSize=>serializableArtifact(compile(source,{entry:'tracePaths',workgroupSize})));
const browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
const page=await browser.newPage({viewport:{width:1440,height:900}});const errors=[],rows=[];
page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
const stats=values=>{const a=[...values].sort((a,b)=>a-b);return {medianMs:a[Math.floor(a.length*.5)],p95Ms:a[Math.floor(a.length*.95)]};};
try{
  await page.goto('http://127.0.0.1:4327');await page.waitForFunction(()=>forestDiagnostics?.ready||forestDiagnostics?.errors.length,{},{timeout:240000});
  await page.evaluate(()=>forestTest.start(1));let expected;
  for(const i of [...variants.keys(),...variants.keys()].map((v,i)=>i<variants.length?v:variants.length-1-v)){
    await page.evaluate(a=>forestTest.setTraceVariant(a),artifacts[i]);
    await page.evaluate(()=>forestTest.render(8,{width:960,frame:0,reset:true,force:true}));
    const result=await page.evaluate(()=>forestTest.render(28,{force:true}));
    await page.evaluate(()=>forestTest.render(1,{frame:317,reset:true,force:true}));
    const pixels=await page.evaluate(()=>forestTest.read('pixels'));
    const hash=createHash('sha256').update(new Uint32Array(pixels)).digest('hex');expected??=hash;assert.equal(hash,expected,'Workgroup shape changes rendered pixels');
    const row={group:variants[i],...stats(result.times),hash};rows.push(row);console.log(row);
  }
  assert.deepEqual(errors,[]);await writeFile('artifacts/workgroup-comparison.json',JSON.stringify({sourceSha256:createHash('sha256').update(source).digest('hex'),rows,errors,boundary:'Same scene/sample sequence at 960x600 and four bounces. Forward/reverse variant order, 8 warm and 28 timed frames each. Queue completion, excludes simulation and compositor.'},null,2));
}finally{await browser.close();}
