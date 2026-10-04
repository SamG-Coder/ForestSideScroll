import {chromium} from 'playwright';
import {writeFile} from 'node:fs/promises';
const name=process.argv[2]||'lighting-profile';
const browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
const page=await browser.newPage({viewport:{width:1440,height:900}});
try{
  await page.goto('http://127.0.0.1:4327');
  await page.waitForFunction(()=>forestDiagnostics?.ready||forestDiagnostics?.errors.length,{},{timeout:180000});
  await page.evaluate(()=>forestTest.start(1));
  await page.evaluate(()=>forestTest.render(4,{width:960,reset:true}));
  const timing=await page.evaluate(()=>forestTest.render(32,{force:true}));
  const profile=await page.evaluate(async()=>{
    const {ComputeBatch}=await import('./vendor/cuda-webshader/runtime/runtime.js');
    const dispatch=ComputeBatch.prototype.dispatch,submit=ComputeBatch.prototype.submit;
    const pending=[],rows=[];
    ComputeBatch.prototype.dispatch=function(invocation,groups,indirect){
      if(!this.runtime.device.features.has('timestamp-query'))return dispatch.call(this,invocation,groups,indirect);
      this.endPass();
      if(!this.probes)this.probes={names:[],query:this.runtime.device.createQuerySet({type:'timestamp',count:64})};
      const index=this.probes.names.length*2;
      this.timestampWrites={querySet:this.probes.query,beginningOfPassWriteIndex:index,endOfPassWriteIndex:index+1};this.passCount=0;
      this.probes.names.push(invocation.kernel.artifact.name);
      const value=dispatch.call(this,invocation,groups,indirect);this.endPass();this.timestampWrites=undefined;return value;
    };
    ComputeBatch.prototype.submit=function(){
      if(!this.probes)return submit.call(this);
      this.endPass();const {names,query}=this.probes,device=this.runtime.device;
      const resolve=device.createBuffer({size:512,usage:GPUBufferUsage.QUERY_RESOLVE|GPUBufferUsage.COPY_SRC});
      const read=device.createBuffer({size:512,usage:GPUBufferUsage.COPY_DST|GPUBufferUsage.MAP_READ});
      this.encoder.resolveQuerySet(query,0,names.length*2,resolve,0);this.encoder.copyBufferToBuffer(resolve,0,read,0,512);
      submit.call(this);pending.push((async()=>{await read.mapAsync(GPUMapMode.READ);const times=new BigUint64Array(read.getMappedRange());
        names.forEach((name,i)=>rows.push({name,ms:Number(times[i*2+1]-times[i*2])/1e6}));read.unmap();read.destroy();resolve.destroy();query.destroy();})());
    };
    try{await forestTest.render(16,{force:true});await Promise.all(pending);return rows;}
    finally{ComputeBatch.prototype.dispatch=dispatch;ComputeBatch.prototype.submit=submit;}
  });
  const stats=values=>{const a=values.sort((a,b)=>a-b);return {medianMs:a[Math.floor(a.length*.5)],p95Ms:a[Math.floor(a.length*.95)],samples:a.length};};
  const kernels=Object.fromEntries([...new Set(profile.map(x=>x.name))].map(n=>[n,stats(profile.filter(x=>x.name===n).map(x=>x.ms))]));
  const report={sourceSha256:await page.evaluate(()=>forestDiagnostics.sourceSha256),adapter:await page.evaluate(()=>forestDiagnostics.adapter),width:timing.width,height:timing.height,render:stats(timing.times),gpuKernels:kernels,errors:await page.evaluate(()=>forestDiagnostics.errors),boundary:'Warm, frozen 960 x 600 four-bounce view. Render includes submission to queue completion; individual kernels use GPU timestamp queries in separate passes. Excludes simulation, RAF waiting and compositor.'};
  await writeFile(`artifacts/${name}.json`,JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
}finally{await browser.close();}
