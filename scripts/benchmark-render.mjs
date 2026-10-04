import {execFileSync} from 'node:child_process';
export async function benchmarkRendering(page){
  const stats=values=>{const a=[...values].sort((a,b)=>a-b);return {medianMs:a[Math.floor(a.length*.5)],p95Ms:a[Math.floor(a.length*.95)],samples:a.length};};
  for(const referenceGeometry of [true,false,true,false])await page.evaluate(referenceGeometry=>forestTest.render(24,{width:960,frame:0,reset:true,referenceGeometry,force:true}),referenceGeometry);
  const batches=[];
  for(const referenceGeometry of [true,false,false,true]){
    await page.evaluate(referenceGeometry=>forestTest.render(8,{width:960,frame:0,reset:true,referenceGeometry,force:true}),referenceGeometry);
    const result=await page.evaluate(referenceGeometry=>forestTest.render(48,{referenceGeometry,force:true}),referenceGeometry);
    let gpu='unavailable';try{gpu=execFileSync('nvidia-smi',['--query-gpu=utilization.gpu,clocks.current.graphics,power.draw','--format=csv,noheader'],{encoding:'utf8'}).trim();}catch{}
    batches.push({referenceGeometry,...stats(result.times),gpu});console.log('BENCHMARK',batches.at(-1));
  }
  // Interleave identical random samples as well as larger ABBA batches, reducing
  // the influence of changing load from other applications on the shared GPU.
  const pairs=await page.evaluate(async()=>{
    const rows=[];
    for(let sample=0;sample<64;sample++){
      const row={sample};
      for(const referenceGeometry of sample%2?[false,true]:[true,false]){
        const result=await forestTest.render(1,{width:960,frame:317+sample,reset:true,referenceGeometry,force:true});
        row[referenceGeometry?'referenceMs':'optimizedMs']=result.times[0];
      }
      row.savedMs=row.referenceMs-row.optimizedMs;rows.push(row);
    }
    return rows;
  });
  const paired={reference:stats(pairs.map(p=>p.referenceMs)),optimized:stats(pairs.map(p=>p.optimizedMs)),difference:stats(pairs.map(p=>p.savedMs)),pairs};
  console.log('PAIRED BENCHMARK',{reference:paired.reference,optimized:paired.optimized,difference:paired.difference});
  return {batches,paired,boundary:'ABBA order, one browser/adapter, identical scene, 960x600 and four bounces. Both pipelines prewarmed with 48 frames, then 8 warm and 48 timed samples per batch. Also 64 interleaved pairs of identical random samples, alternating which variant goes first. Includes submission to queue completion; excludes simulation, RAF and compositor. Reference recomputes transforms, retests BVH child bounds, and uses 8x8 trace workgroups. Production caches transforms in spatial order, skips redundant bounds tests, and uses 8x4 trace workgroups. Rock planes and the original untiled filter are shared by both variants.'};
}
