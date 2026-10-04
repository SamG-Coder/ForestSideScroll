import assert from 'node:assert/strict';

export async function compareCachedRendering(page){
  const original=await page.evaluate(()=>forestTest.hold());const viewport=page.viewportSize();const results=[];
  // A partial bottom workgroup checks pixel coverage at the image boundary.
  await page.setViewportSize({width:1440,height:907});
  try{
    for(const [location,time] of [[0,0],[0,.73],[0,5.8],[1,5.8]]){
      const result=await page.evaluate(async({location,time})=>{
        const state=await forestTest.hold();state[7]=location;state[15]=time;state[0]=-4;state[11]=-4;state[13]=-4;state[2]=19.82;state[12]=19.82;state[14]=19.82;
        await forestTest.setState(state);
        await forestTest.render(1,{width:768,frame:317,reset:true,referenceGeometry:true,force:true});
        const expected=await forestTest.read('pixels');const guide=await forestTest.read('guide');const radiance=await forestTest.read('radiance');
        await forestTest.render(1,{frame:317,reset:true,referenceGeometry:false,force:true});
        const pixels=await forestTest.read('pixels');const tested=await forestTest.read('guide');const raw=await forestTest.read('radiance');
        let mismatchedPixels=0,mismatchedHits=0,maxPositionError=0,maxRadianceError=0,nonFinite=0;
        for(let i=0;i<pixels.length;i++){
          if(pixels[i]!==expected[i])mismatchedPixels++;
          if(guide[i*4+3]!==tested[i*4+3])mismatchedHits++;
          for(let c=0;c<3;c++){const k=i*4+c;maxPositionError=Math.max(maxPositionError,Math.abs(guide[k]-tested[k]));maxRadianceError=Math.max(maxRadianceError,Math.abs(radiance[k]-raw[k]));if(!Number.isFinite(raw[k]))nonFinite++;}
        }
        return {location,time,pixels:pixels.length,mismatchedPixels,mismatchedHits,maxPositionError,maxRadianceError,nonFinite};
      },{location,time});
      assert.equal(result.nonFinite,0);assert.equal(result.mismatchedPixels,0);assert.equal(result.mismatchedHits,0);assert.equal(result.maxPositionError,0);assert(result.maxRadianceError<1e-5);results.push(result);
    }
  }finally{await page.setViewportSize(viewport);await page.evaluate(s=>forestTest.setState(s),original);}
  return results;
}
