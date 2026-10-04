// Controlled disocclusion and stale-history inputs exercise the actual compiled
// filter independently of the scene and its stochastic path samples.
export async function checkTemporalControls(page){
  return page.evaluate(async()=>{
    const {GpuRuntime}=await import('./vendor/cuda-webshader/runtime/runtime.js');
    const runtime=await GpuRuntime.create();const kernel=await runtime.kernel(await (await fetch('./generated/filterImage.json')).json());
    const width=7,height=5,n=width*height,store={};
    const make=(name,data)=>{const b=runtime.createBuffer(data.byteLength);runtime.write(b,data);store[name]=b;};
    const image=new Float32Array(n*4),guide=new Float32Array(n*4),normals=new Float32Array(n*4),albedo=new Float32Array(n*4),old=new Float32Array(n*4),state=new Float32Array(32);
    state[12]=state[14]=26;
    const length=Math.hypot(.095,1),forward=[0,.095/length,1/length],up=[0,1/length,-.095/length];
    for(let y=0;y<height;y++)for(let x=0;x<width;x++){
      const i=(y*width+x)*4,sx=((x+.5)/width*2-1)*width/height*.4,sy=(1-(y+.5)/height*2)*.4;
      image.set([.2,.3,.4,12],i);old.set([2,0,2,12],i);albedo.set([.2,.3,.4,1],i);
      guide.set([sx*10,1.65+forward[1]*10+up[1]*sy*10,forward[2]*10+up[2]*sy*10,42],i);
      normals.set([0,0,-1,10],i);
    }
    make('source',image);make('guide',guide);make('normals',normals);make('albedo',albedo);make('oldImage',old);const mask=new Float32Array(n*4);for(let i=0;i<n;i++)mask[i*4]=1;make('oldCoverage',mask);make('coverage',new Float32Array(n*4));make('oldGuide',guide);make('oldNormals',normals);make('state',state);make('filtered',new Float32Array(n*4));
    async function run(reset){runtime.batch().dispatch(kernel.bind(store,{width,height,step:2,reset,frozen:0}),[1,1,1]).submit();await runtime.idle();return Array.from(await runtime.read(store.filtered));}
    function maximumError(a){let error=0;for(let i=0;i<a.length;i++)if(i%4!==3)error=Math.max(error,Math.abs(a[i]-image[i]));return error;}
    try{
      const reset=await run(1);
      const held=await run(0);
      // Move the camera; all previous geometry is now behind a newly revealed
      // surface. Strong magenta history must be rejected, including edge lanes.
      state[13]=-.01;runtime.write(store.state,state);
      const distant=guide.slice();for(let i=0;i<distant.length;i+=4){distant[i+2]+=100;distant[i+3]=99;}runtime.write(store.oldGuide,distant);
      const disoccluded=await run(0);
      // Valid geometry with wildly stale lighting must be clipped to today's
      // local range rather than leaving a saturated trail along a moving edge.
      runtime.write(store.oldGuide,guide);const clamped=await run(0);
      return {resetError:maximumError(reset),resetCounts:reset.filter((_,i)=>i%4===3),heldUsesHistory:maximumError(held)>.1,disocclusionError:maximumError(disoccluded),clampedError:maximumError(clamped),finite:[...reset,...held,...disoccluded,...clamped].every(Number.isFinite),width,height};
    }finally{for(const b of Object.values(store))runtime.destroyBuffer(b);runtime.device.destroy();}
  });
}
