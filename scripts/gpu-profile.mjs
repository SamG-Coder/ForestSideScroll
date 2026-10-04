export async function profileKernels(page,settings={}){
  const rows=await page.evaluate(async settings=>{
    const {ComputeBatch}=await import('./vendor/cuda-webshader/runtime/runtime.js');
    const dispatch=ComputeBatch.prototype.dispatch,submit=ComputeBatch.prototype.submit;
    const pending=[],rows=[];
    ComputeBatch.prototype.dispatch=function(invocation,groups,indirect){
      if(!this.runtime.device.features.has('timestamp-query'))return dispatch.call(this,invocation,groups,indirect);
      this.endPass();
      if(!this.probes)this.probes={names:[],query:this.runtime.device.createQuerySet({type:'timestamp',count:64})};
      const index=this.probes.names.length*2;
      this.timestampWrites={querySet:this.probes.query,beginningOfPassWriteIndex:index,endOfPassWriteIndex:index+1};this.passCount=0;
      this.probes.names.push(invocation.kernel.artifact.name+(invocation.values.step?` step ${invocation.values.step}`:''));
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
    try{await forestTest.render(16,{...settings,frame:0,reset:true,force:true});await Promise.all(pending);return rows;}
    finally{ComputeBatch.prototype.dispatch=dispatch;ComputeBatch.prototype.submit=submit;}
  },settings);
  const stats=values=>{const a=[...values].sort((a,b)=>a-b);return {medianMs:a[Math.floor(a.length*.5)],p95Ms:a[Math.floor(a.length*.95)],samples:a.length};};
  return Object.fromEntries([...new Set(rows.map(x=>x.name))].map(n=>[n,stats(rows.filter(x=>x.name===n).map(x=>x.ms))]));
}
