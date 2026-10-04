// The same frame sequence is used before/after. Painting is explicitly disabled
// for the underlying-renderer comparison; fixed wind isolates sampling flicker.
export async function measureTemporal(page,{wind=false,paint=false,camera=false}={}){
  return page.evaluate(async({wind,paint,camera})=>{
    await forestTest.start(2);
    const settings={width:960,frozen:false,foliagePaint:paint,oilPaint:paint,paintStrength:.75,useLightingCache:true,input:{dt:wind||camera?1/30:0,clockRate:0,inputX:camera?1:0}};
    await forestTest.render(32,{...settings,frame:0,reset:true,hour:16.2});
    let previous=await forestTest.read('pixels'),oldGuide=await forestTest.read('guide');
    const objects=await forestTest.read('objects');const sums={};
    for(let f=0;f<32;f++){
      await forestTest.render(1,settings);
      const pixels=await forestTest.read('pixels'),guide=await forestTest.read('guide'),history=await forestTest.read('history');
      for(let i=0;i<pixels.length;i++){
        const id=guide[i*4+3],mat=id>=0?objects[id*16+11]:id;
        const s=sums[mat]??={pixels:0,absolute:0,squared:0,large:0,switches:0,history:0,reset:0};
        let d=0;for(const shift of [0,8,16]){const delta=((pixels[i]>>>shift)&255)-((previous[i]>>>shift)&255);d+=Math.abs(delta);s.squared+=delta*delta;}
        s.absolute+=d;s.pixels++;if(d/3>16)s.large++;if(id!==oldGuide[i*4+3])s.switches++;
        const count=Math.floor(history[i*4+3]);s.history+=count;if(count<=1)s.reset++;
      }
      previous=pixels;oldGuide=guide;
    }
    const groups=Object.fromEntries(Object.entries(sums).map(([mat,s])=>[mat,{mae8bit:s.absolute/(s.pixels*3),rms8bit:Math.sqrt(s.squared/(s.pixels*3)),largeChanges:s.large/s.pixels,identitySwitches:s.switches/s.pixels,meanHistory:s.history/s.pixels,historyResets:s.reset/s.pixels,pixels:s.pixels}]));
    return {groups,frames:32,warmup:32,width:960,height:forestDiagnostics.height,wind,paint,camera,cache:forestTest.cache,state:forestDiagnostics.state};
  },{wind,paint,camera});
}
