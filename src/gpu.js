import {GpuRuntime} from '../vendor/cuda-webshader/runtime/runtime.js';

export const OBJECT_COUNT=524288;
export const PAINT_DEPTHS=Object.freeze({trees:.70,rocks:.50,foliage:.35,water:.60});
export class ForestRenderer{
  static async create(canvas,onProgress,onError,{native=false}={}){
    const self=new ForestRenderer();
    self.runtime=await GpuRuntime.create({backend:'webgpu',onError});
    try{
    if(native){
      await self.runtime.enableNativeInterop({requirements:{sharedBuffers:true,gpuBufferToTexture:true,maxResourceBytes:67108864,sharedBytes:268435456,resources:28,blocksPerLaunch:131072}});
      if(!self.runtime.native)throw Error(self.runtime.nativeInteropStatus?.reason||'Native CUDA sharing does not meet the forest requirements.');
    }
    self.compute=self.runtime.native||self.runtime;
    self.backend=native?'native-cuda':'webgpu';
    self.allocate=(bytes,options)=>native?self.runtime.createSharedBuffer(bytes,options):self.runtime.createBuffer(bytes,options);
    self.canvas=canvas;self.context=canvas.getContext('webgpu');
    self.format=navigator.gpu.getPreferredCanvasFormat();
    self.manifest=await (await fetch('./generated/manifest.json')).json();
    self.kernels={};
    for(const {entry} of self.manifest.entries){
      if(entry==='traceReference'||entry==='paintScene')continue;
      onProgress(`Preparing ${entry==='tracePaths'?'light transport':entry==='generateScene'?'the forest':'the riverbank'}`);
      const response=await fetch(`./generated/${entry}.json`);if(!response.ok)throw Error(`Missing compiled kernel ${entry}`);
      self.kernels[entry]=await self.compute.kernel(await response.json());
    }
    self.objects=await self.allocate(OBJECT_COUNT*64,{label:'CUDA procedural forest'});
    self.bounds=await self.allocate(OBJECT_COUNT*2*32,{label:'CUDA generated BVH'});
    self.rayGeometry=await self.allocate(OBJECT_COUNT*64,{label:'Cached ray transforms and leaf poses'});
    self.rockPlanes=await self.allocate(2048*104*16,{label:'Cached sandstone fracture planes'});
    self.spatialKeys=await self.allocate(OBJECT_COUNT*4,{label:'Geometry Morton keys'});
    self.order=await self.allocate(OBJECT_COUNT*4,{label:'Spatially ordered primitive IDs'});
    self.terrain=await self.allocate(4096*2048*4,{label:'Cached CUDA terrain heights'});
    self.atlas=await self.allocate(5592405*2*4,{label:'2048 px soil and sandstone with mipmaps'});
    self.state=await self.allocate(32*4,{label:'CUDA game state'});
    self.frame=0;self.reset=1;self.ping=0;self.location=0;self.seed=5359585;self.samples=0;self.stillLimit=128;
    self.counters={tracedFrames:0,reusedFrames:0,terrainBakes:0,materialBakes:0,geometryBakes:0,rockBakes:0,motionUpdates:0,resolvePasses:0,paintPasses:0};
    await self.compute.batch().dispatch(self.kernels.initGame.bind({state:self.state},{mode:0}),[1,1,1]).submit();
    const materials=self.compute.batch();materials.dispatch(self.kernels.bakeMaterials.bind({atlas:self.atlas},{}),[256,256,1]);
    for(let level=1;level<12;level++)materials.dispatch(self.kernels.materialMip.bind({atlas:self.atlas},{level}),[Math.ceil((2048>>level)/8),Math.ceil((2048>>level)/8),1]);
    await materials.submit();self.counters.materialBakes++;
    await self.generate(0);
    return self;
    }catch(error){await Promise.resolve(self.runtime.dispose()).catch(()=>{});throw error;}
  }
  async generate(location){
    this.location=location;
    const generated=this.compute.batch();
    generated.dispatch(this.kernels.generateScene.bind({objects:this.objects},{location,masterSeed:this.seed}),[OBJECT_COUNT/64,1,1]);
    generated.dispatch(this.kernels.prepareRockPlanes.bind({objects:this.objects,rockPlanes:this.rockPlanes},{}),[2048/64,1,1]);
    this.counters.geometryBakes++;this.counters.rockBakes++;
    generated.dispatch(this.kernels.spatialKeys.bind({objects:this.objects,keys:this.spatialKeys,order:this.order},{}),[OBJECT_COUNT/128,1,1]);await generated.submit();
    await this.runtime.sortPairs(this.spatialKeys,this.order,{count:OBJECT_COUNT});
    const batch=this.compute.batch();
    batch.dispatch(this.kernels.prepareRayGeometry.bind({objects:this.objects,order:this.order,rayGeometry:this.rayGeometry},{}),[OBJECT_COUNT/128,1,1]);
    if(this.terrainLocation!==location){batch.dispatch(this.kernels.bakeTerrain.bind({terrain:this.terrain},{location}),[512,256,1]);this.counters.terrainBakes++;this.terrainLocation=location;}
    batch.dispatch(this.kernels.buildLeaves.bind({objects:this.objects,order:this.order,bounds:this.bounds},{}),[OBJECT_COUNT/128,1,1]);
    for(let count=OBJECT_COUNT/2;count>=1;count/=2)batch.dispatch(this.kernels.buildLevel.bind({bounds:this.bounds},{start:count,count}),[Math.ceil(count/128),1,1]);
    await batch.submit();await this.runtime.idle();this.reset=1;this.lastWindTime=null;
  }
  async resize(width,aspect){
    width=Math.max(256,Math.ceil(width/64)*64);const height=Math.max(160,Math.round(width/aspect));
    if(this.width===width&&this.height===height)return;
    await this.runtime.idle();
    if(this.targets)for(const target of this.targets){
      this.runtime.destroyBuffer(target);
      // Shared-resource destruction is asynchronous in the browser. Drain each
      // retirement before the next allocation/retirement to keep the session alive.
      if(this.backend==='native-cuda')await this.runtime.idle();
    }
    this.width=width;this.height=height;this.canvas.width=width;this.canvas.height=height;
    this.context.configure({device:this.runtime.device,format:this.format,alphaMode:'opaque',usage:GPUTextureUsage.COPY_DST|GPUTextureUsage.RENDER_ATTACHMENT});
    this.targets=[];
    const make=async(stride,label)=>{const buffer=await this.allocate(width*height*stride,{label});this.targets.push(buffer);return buffer;};
    this.raw=await make(16,'Path radiance');this.albedo=await make(16,'Surface albedo');this.guides=[await make(16,'Surface positions 0'),await make(16,'Surface positions 1')];
    this.normals=[await make(16,'Surface normals 0'),await make(16,'Surface normals 1')];
    this.history=[await make(16,'Temporal lighting 0'),await make(16,'Temporal lighting 1')];
    this.spatial=await make(16,'Spatial filter');
    this.filtered=[await make(16,'Stable image 0'),await make(16,'Stable image 1')];
    this.coverage=[await make(16,'Paint layer coverage 0'),await make(16,'Paint layer coverage 1')];
    this.pixels=await make(4,'CUDA RGBA pixels');this.reset=1;
  }
  async init(mode){
    await this.compute.batch().dispatch(this.kernels.initGame.bind({state:this.state},{mode}),[1,1,1]).submit();
    if(this.location!==0)await this.generate(0);this.reset=1;this.lastSimPaused=false;return this.readState();
  }
  async simulate({dt=0,inputX=0,inputZ=0,sprint=0,interact=0,paused=0,clockRate=0.006,setHour=-1}={}){
    if(paused&&this.lastSimPaused&&setHour<0&&this.cachedState)return this.cachedState;
    if(setHour>=0&&this.cachedState?.[10]!==setHour)this.reset=1;
    await this.compute.batch().dispatch(this.kernels.stepGame.bind({state:this.state},{dt,inputX,inputZ,sprint,interact,paused,clockRate,setHour}),[1,1,1]).submit();
    const state=await this.readState();
    this.lastSimPaused=Boolean(paused);
    if(state[7]!==this.location)await this.generate(state[7]);
    return state;
  }
  async readState(){this.cachedState=Array.from(await this.runtime.read(this.state));return this.cachedState;}
  async writeState(values){await this.runtime.idle();this.runtime.write(this.state,new Float32Array(values));this.cachedState=[...values];this.lastSimPaused=false;if(values[7]!==this.location)await this.generate(values[7]);this.reset=1;}
  async render({bounces=4,exposure=1.25,frozen=false,useLightingCache=true,referenceGeometry=false,oilPaint=false,paintStrength=0.75,paintDepths={},force=false}={}){
    if(referenceGeometry&&!this.kernels.traceReference)this.kernels.traceReference=await this.compute.kernel(await (await fetch('./generated/traceReference.json')).json());
    const paintAmount=oilPaint?Math.max(0,Math.min(1,paintStrength)):0;
    const depths={};for(const [key,fallback] of Object.entries(PAINT_DEPTHS))depths[key]=Number.isFinite(paintDepths[key])?Math.max(0,Math.min(1,paintDepths[key])):fallback;
    const paintKey=paintAmount>0?[paintAmount,...Object.values(depths)].join(':'):'0';
    if(paintAmount>0&&!this.kernels.paintScene)this.kernels.paintScene=await this.compute.kernel(await (await fetch('./generated/paintScene.json')).json());
    const {width,height}=this;const groups=[Math.ceil(width/8),Math.ceil(height/8),1];
    const s=this.cachedState||await this.readState();
    const signature=[width,height,bounces,frozen,referenceGeometry,s[7],s[10],s[11],s[12],s[15]].join(':');
    if(this.lastBounces!==bounces||this.lastFrozen!==frozen)this.reset=1;
    if(this.reset||signature!==this.stillSignature)this.samples=0;
    this.stillSignature=signature;this.lastBounces=bounces;this.lastFrozen=frozen;
    if(frozen&&!force&&!this.reset&&this.samples>=this.stillLimit){
      this.counters.reusedFrames++;
      if(exposure!==this.lastExposure||paintKey!==this.lastPaintKey){const batch=this.compute.batch();this.resolve(batch,1-this.ping,exposure,paintAmount,depths,paintKey);await this.present(batch);await this.runtime.idle();}
      return false;
    }
    const p=this.ping;const old=1-p;const batch=this.compute.batch();
    if(this.lastWindTime!==s[15]){batch.dispatch(this.kernels.updateLeafMotion.bind({objects:this.objects,order:this.order,rayGeometry:this.rayGeometry},{time:s[15]}),[OBJECT_COUNT/128,1,1]);this.lastWindTime=s[15];this.counters.motionUpdates++;}
    const reuseLighting=Number(useLightingCache&&!frozen&&!this.reset&&Math.abs(s[10]-(this.lastHour??-99))<0.003);
    const tracer=this.kernels[referenceGeometry?'traceReference':'tracePaths'];const block=tracer.artifact.metadata.workgroupSize;
    batch.dispatch(tracer.bind({objects:this.objects,bounds:this.bounds,rayGeometry:this.rayGeometry,rockPlanes:this.rockPlanes,terrain:this.terrain,atlas:this.atlas,state:this.state,oldGuide:this.guides[old],oldNormals:this.normals[old],oldHistory:this.history[old],radiance:this.raw,guide:this.guides[p],normals:this.normals[p],albedo:this.albedo},{width,height,frame:this.frame,bounces,reuseLighting}),[Math.ceil(width/block[0]),Math.ceil(height/block[1]),1]);
    batch.dispatch(this.kernels.accumulate.bind({radiance:this.raw,guide:this.guides[p],normals:this.normals[p],oldGuide:this.guides[old],oldNormals:this.normals[old],oldHistory:this.history[old],history:this.history[p],state:this.state},{width,height,reset:this.reset,frozen:Number(frozen)}),groups);
    const filter=this.kernels.filterImage;
    const filterInputs={guide:this.guides[p],normals:this.normals[p],albedo:this.albedo,oldImage:this.filtered[old],oldGuide:this.guides[old],oldNormals:this.normals[old],oldCoverage:this.coverage[old],coverage:this.coverage[p],state:this.state};
    const filterValues={width,height,reset:this.reset,frozen:Number(frozen)};
    batch.dispatch(filter.bind({...filterInputs,source:this.history[p],filtered:this.spatial},{...filterValues,step:1}),groups);
    batch.dispatch(filter.bind({...filterInputs,source:this.spatial,filtered:this.filtered[p]},{...filterValues,step:2}),groups);
    this.resolve(batch,p,exposure,paintAmount,depths,paintKey);
    await this.present(batch);
    await this.runtime.idle();this.ping=old;this.reset=0;this.frame++;this.samples++;this.lastHour=s[10];this.lastExposure=exposure;this.counters.tracedFrames++;
    return true;
  }
  resolve(batch,p,exposure,paintAmount,depths,paintKey){
    const {width,height}=this;const groups=[Math.ceil(width/8),Math.ceil(height/8),1];const values={width,height,exposure,bgra:Number(this.format==='bgra8unorm')};
    if(paintAmount>0){batch.dispatch(this.kernels.paintScene.bind({source:this.filtered[p],coverage:this.coverage[p],pixels:this.pixels},{...values,strength:paintAmount,treeDepth:depths.trees,rockDepth:depths.rocks,foliageDepth:depths.foliage,waterDepth:depths.water}),groups);this.counters.paintPasses++;}
    else batch.dispatch(this.kernels.resolveImage.bind({source:this.filtered[p],pixels:this.pixels},values),groups);
    this.counters.resolvePasses++;this.lastExposure=exposure;this.lastPaintKey=paintKey;
  }
  async present(batch){
    if(this.backend==='native-cuda'){
      await batch.submit();
      const encoder=this.runtime.device.createCommandEncoder();
      encoder.copyBufferToTexture({buffer:this.pixels.gpuBuffer,bytesPerRow:this.width*4},{texture:this.context.getCurrentTexture()},[this.width,this.height]);
      this.runtime.device.queue.submit([encoder.finish()]);return;
    }
    batch.endPass();batch.encoder.copyBufferToTexture({buffer:this.pixels.gpuBuffer,bytesPerRow:this.width*4},{texture:this.context.getCurrentTexture()},[this.width,this.height]);batch.submit();}
  async dispose(){await this.runtime.idle().catch(()=>{});await this.runtime.dispose();}
  async snapshot(){
    const values=await this.runtime.read(this.pixels,Uint32Array);const bytes=new Uint8ClampedArray(values.buffer);
    if(this.format==='bgra8unorm')for(let i=0;i<bytes.length;i+=4){const r=bytes[i];bytes[i]=bytes[i+2];bytes[i+2]=r;}
    const canvas=document.createElement('canvas');canvas.width=this.width;canvas.height=this.height;canvas.getContext('2d').putImageData(new ImageData(bytes,this.width,this.height),0,0);
    return new Promise(resolve=>canvas.toBlob(resolve,'image/png'));
  }
}
