import {ForestRenderer,OBJECT_COUNT,PAINT_DEPTHS} from './gpu.js';
const $=id=>document.getElementById(id);
const diag=window.forestDiagnostics={ready:false,errors:[],frames:0,renderer:'CUDA → WGSL → WebGPU',proceduralPrimitives:OBJECT_COUNT,frameTimes:[]};
const keys=new Set();const options={width:960,bounces:4,exposure:1.25,clock:true,oilPaint:false,paintStrength:0.75,paintDepths:{...PAINT_DEPTHS}};
let renderer,busy=false,testing=false,menu=true,still=false,pendingMode=null,pendingHour=-1,interact=false,resize=true,last=performance.now(),lastHud=0;
let gameState=null,continueState=null,framesSinceReset=0;
function fail(error){const message=String(error?.message||error);diag.errors.push(message);$('error').hidden=false;$('error').textContent=`The river could not open.\n${message}`;$('loading').hidden=true;console.error(error);}
function setStill(value){still=value;$('photo-banner').hidden=!still||menu;$('photo').firstChild.textContent=still?'Resume exploring ':'Pause for a still view ';renderer.reset=1;framesSinceReset=0;}
function showMenu(value){if(value&&gameState?.[9]===1){saveProgress();continueState=[...gameState];$('play').firstChild.textContent='Continue journey ';}menu=value;$('menu').hidden=!value;$('hud').hidden=value;$('photo-banner').hidden=value||!still;$('interact').hidden=true;keys.clear();renderer.reset=1;}
$('settings-button').onclick=()=>{$('settings').hidden=!$('settings').hidden;};$('close-settings').onclick=()=>{$('settings').hidden=true;};
$('play').onclick=()=>{pendingMode=1;};$('demo').onclick=()=>{pendingMode=2;};
$('quality').onchange=e=>{options.width=Number(e.target.value);resize=true;};
$('bounces').onchange=e=>{options.bounces=Number(e.target.value);renderer.reset=1;};
$('exposure').oninput=e=>{options.exposure=Number(e.target.value);};
function syncPaintControls(){
  $('oil-paint').checked=options.oilPaint;$('paint-strength').value=String(options.paintStrength);$('paint-strength').disabled=!options.oilPaint;$('paint-value').textContent=`${Math.round(options.paintStrength*100)}%`;
  $('paint-layers').disabled=!options.oilPaint;
  for(const [layer,depth] of Object.entries(options.paintDepths)){$(`depth-${layer}`).value=String(depth);$(`depth-${layer}-value`).textContent=`${Math.round(depth*100)}%`;}
}
function savePaintPreference(){try{localStorage.setItem('secret-river-oil-paint-v2',JSON.stringify({enabled:options.oilPaint,strength:options.paintStrength,depths:options.paintDepths}));}catch{}}
try{const paint=JSON.parse(localStorage.getItem('secret-river-oil-paint-v2')??localStorage.getItem('secret-river-oil-paint-v1')??localStorage.getItem('secret-river-foliage-style-v1'));if(typeof paint?.enabled==='boolean'&&Number.isFinite(paint.strength)&&paint.strength>=0&&paint.strength<=1){options.oilPaint=paint.enabled;options.paintStrength=paint.strength;for(const key of Object.keys(PAINT_DEPTHS)){const depth=paint.depths?.[key];if(Number.isFinite(depth)&&depth>=0&&depth<=1)options.paintDepths[key]=depth;}}}catch{}
syncPaintControls();
$('oil-paint').onchange=e=>{options.oilPaint=e.target.checked;syncPaintControls();savePaintPreference();};
$('paint-strength').oninput=e=>{options.paintStrength=Number(e.target.value);syncPaintControls();savePaintPreference();};
for(const layer of Object.keys(PAINT_DEPTHS))$(`depth-${layer}`).oninput=e=>{options.paintDepths[layer]=Number(e.target.value);syncPaintControls();savePaintPreference();};
$('hour').onchange=e=>{pendingHour=Number(e.target.value);renderer.reset=1;};
$('day-cycle').onchange=e=>{options.clock=e.target.checked;};
$('photo').onclick=()=>setStill(!still);$('resume').onclick=()=>setStill(false);
$('capture').onclick=async()=>{try{await idle();testing=true;await renderer.render({...options,frozen:menu||still});const blob=await renderer.snapshot();const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='secret-river.png';a.click();setTimeout(()=>URL.revokeObjectURL(url),5000);}catch(e){fail(e);}finally{testing=false;}};
function relevantTarget(event){return /^(INPUT|SELECT|BUTTON)$/.test(event.target?.tagName);}
window.addEventListener('keydown',e=>{
  if(relevantTarget(e))return;
  if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Space'].includes(e.code))e.preventDefault();
  keys.add(e.code);if(e.repeat)return;
  if(e.code==='Escape'){if(!$('settings').hidden)$('settings').hidden=true;else showMenu(!menu);}
  if(e.code==='KeyP')setStill(!still);
  if(e.code==='KeyE'||e.code==='Enter'){if(menu)pendingMode=1;else interact=true;}
  if(menu&&e.code==='Space')pendingMode=1;
});
window.addEventListener('keyup',e=>keys.delete(e.code));window.addEventListener('blur',()=>keys.clear());
document.addEventListener('visibilitychange',()=>{keys.clear();last=performance.now();});
window.addEventListener('resize',()=>{resize=true;});
function saveProgress(){if(!gameState||gameState[9]!==1)return;try{localStorage.setItem('secret-river-webcuda-v1',JSON.stringify({version:1,state:gameState}));}catch{}}
function loadProgress(){try{const data=JSON.parse(localStorage.getItem('secret-river-webcuda-v1'));const a=data?.state;if(data?.version===1&&Array.isArray(a)&&a.length===32&&a.every(Number.isFinite)&&[0,1].includes(a[7])&&a[0]>=-96&&a[0]<=96&&a[2]>=16.2&&a[2]<=24.8&&a[8]>=0&&a[8]<=3&&a[9]===1&&a[10]>=0&&a[10]<24){continueState=a;$('play').firstChild.textContent='Continue journey ';}}catch{}}
function hud(now){
  if(!gameState)return;
  if(now-lastHud<200)return;lastHud=now;const s=gameState,loc=s[7],mask=s[8];
  $('location').textContent=loc===0?'Wisemans Ferry':'Macdonald River';$('region').textContent=loc===0?'HAWKESBURY RIVER · BROAD REACH':'FIRST BRANCH';
  const hour=s[10];$('time-label').textContent=hour<6||hour>=20?'NIGHT':hour<11?'MORNING':hour<14?'MIDDAY':hour<17?'LATE AFTERNOON':'SUNSET';
  let text='Follow the bank to the eastern bend.';let distance=s[19];let total=76;
  if(s[9]===2){text='Explore the riverbank at your own pace.';distance=0;}
  else if(s[17]){text='Both riverbanks surveyed. The path is yours to wander.';distance=0;}
  else if(loc===0&&(mask&1)){text='Broad Reach surveyed. Continue east to the crossing.';distance=Math.max(0,94-s[0]);total=22;}
  else if(loc===1&&(mask&2)){text='First Branch traced. Return west to Broad Reach.';distance=Math.max(0,s[0]+94);total=164;}
  else if(loc===1){text='Follow the narrower bank to the upstream bend.';total=159;}
  $('objective').textContent=text;$('distance').textContent=distance>0?`${Math.ceil(distance)} m along the bank`:(s[9]===2?'Riverbank demo':'Journey complete');$('progress-fill').style.width=`${Math.max(0,Math.min(100,100-distance/total*100))}%`;
  const near=s[9]===1&&((loc===0&&s[0]>=91.2&&(mask&1))||(loc===1&&s[0]<=-91.2&&(mask&2)));
  $('interact').hidden=!near||menu||still;$('interact').querySelector('span').textContent=loc===0?'Continue into First Branch':'Return to Broad Reach';
  const samples=diag.frameTimes.slice(-30);const avg=samples.reduce((a,b)=>a+b,0)/Math.max(1,samples.length);
  $('status').textContent=still||menu?`${Math.min(renderer.stillLimit,renderer.samples)} / ${renderer.stillLimit} samples${renderer.samples>=renderer.stillLimit?' · ready':''} · ${renderer.width} × ${renderer.height}`:`${Math.round(avg)} ms render · ${renderer.width} × ${renderer.height}`;
}
async function idle(){while(busy)await new Promise(resolve=>setTimeout(resolve,10));}
async function frame(now){
  if(testing||document.hidden){last=now;requestAnimationFrame(frame);return;}
  busy=true;const started=performance.now();
  try{
    if(pendingMode!==null){const mode=pendingMode;pendingMode=null;if(mode===1&&continueState){await renderer.writeState(continueState);gameState=continueState;continueState=null;}else gameState=await renderer.init(mode);showMenu(false);setStill(false);$('scene').focus();}
    if(resize){resize=false;await renderer.resize(options.width,innerWidth/innerHeight);framesSinceReset=0;}
    const dt=Math.min(0.1,Math.max(0,(now-last)/1000));last=now;
    const oldLocation=renderer.location;
    const inputX=Number(keys.has('KeyD')||keys.has('ArrowRight'))-Number(keys.has('KeyA')||keys.has('ArrowLeft'));
    const inputZ=Number(keys.has('KeyW')||keys.has('ArrowUp'))-Number(keys.has('KeyS')||keys.has('ArrowDown'));
    gameState=await renderer.simulate({dt,inputX,inputZ,sprint:Number(keys.has('ShiftLeft')||keys.has('ShiftRight')),interact:Number(interact),paused:Number(menu||still),clockRate:options.clock?0.006:0,setHour:pendingHour});
    interact=false;pendingHour=-1;if(renderer.reset)framesSinceReset=0;
    const traced=await renderer.render({bounces:options.bounces,exposure:options.exposure,frozen:menu||still,oilPaint:options.oilPaint,paintStrength:options.paintStrength,paintDepths:options.paintDepths});
    framesSinceReset=renderer.samples;diag.cache={...renderer.counters};diag.frames++;diag.state=gameState;diag.width=renderer.width;diag.height=renderer.height;diag.location=renderer.location;diag.accumulationPasses=framesSinceReset;if(traced)diag.frameTimes.push(performance.now()-started);if(diag.frameTimes.length>180)diag.frameTimes.shift();
    if(diag.frames%120===0||oldLocation!==renderer.location)saveProgress();hud(now);
    if(!diag.ready){diag.ready=true;$('loading').hidden=true;$('play').disabled=false;$('demo').disabled=false;}
  }catch(error){fail(error);busy=false;return;}
  busy=false;requestAnimationFrame(frame);
}
try{
  renderer=await ForestRenderer.create($('scene'),text=>{$('loading-text').textContent=text;},fail);
  diag.adapter=renderer.runtime.describe();diag.sourceSha256=renderer.manifest.sourceSha256;loadProgress();
  // Diagnostic controls operate the actual GPU kernels and buffers used by play.
  window.forestTest={
    async hold(){testing=true;await idle();return renderer.readState();},
    release(){testing=false;last=performance.now();},
    async start(mode=1){testing=true;await idle();gameState=await renderer.init(mode);showMenu(false);still=true;return gameState;},
    async advance(input,steps=1){testing=true;await idle();for(let i=0;i<steps;i++)gameState=await renderer.simulate({dt:0.1,clockRate:0,...input});diag.state=gameState;hud(performance.now()+1000);return gameState;},
    async setState(values){testing=true;await idle();await renderer.writeState(values);gameState=await renderer.readState();return gameState;},
    async render(samples=1,settings={}){testing=true;await idle();if(settings.width)await renderer.resize(settings.width,innerWidth/innerHeight);if(settings.hour!==undefined)gameState=await renderer.simulate({paused:1,setHour:settings.hour});if(settings.reset)renderer.reset=1;if(settings.frame!==undefined)renderer.frame=settings.frame;const times=[];for(let i=0;i<samples;i++){gameState=await renderer.simulate(settings.input||{paused:1});const t=performance.now();await renderer.render({...options,frozen:true,...settings});times.push(performance.now()-t);}diag.state=gameState;framesSinceReset=renderer.samples;diag.cache={...renderer.counters};diag.width=renderer.width;diag.height=renderer.height;hud(performance.now()+1000);return {width:renderer.width,height:renderer.height,frames:renderer.frame,times,cache:{...renderer.counters},samples:renderer.samples};},
    async pixelSnapshot(){await idle();const blob=await renderer.snapshot();return Array.from(new Uint8Array(await blob.arrayBuffer()));},
    async setTraceVariant(artifact){testing=true;await idle();if(artifact.name!=='tracePaths')throw Error('Expected a tracePaths diagnostic variant');renderer.kernels.tracePaths=await renderer.runtime.kernel(artifact);renderer.reset=1;},
    async lightingStats(){await idle();const r=await renderer.runtime.read(renderer.raw);const g=await renderer.runtime.read(renderer.guides[1-renderer.ping]);const h=await renderer.runtime.read(renderer.history[1-renderer.ping]);let reused=0,water=0,waterReused=0,maxAge=0;for(let i=0;i<r.length;i+=4){if(r[i+3]<0)reused++;if(g[i+3]===-2){water++;if(r[i+3]<0)waterReused++;}maxAge=Math.max(maxAge,(h[i+3]-Math.floor(h[i+3]))*16);}return {reused,water,waterReused,maxAge,pixels:r.length/4};},
    async rockStats(){
      testing=true;await idle();const objects=await renderer.runtime.read(renderer.objects);const planes=await renderer.runtime.read(renderer.rockPlanes);const transforms=await renderer.runtime.read(renderer.rayGeometry);
      const forms=[0,0,0,0];let invalidPlanes=0,invalidTransforms=0,maxAxisExtent=0,minAspect=Infinity,maxAspect=0,axisPlanes=0;
      for(let r=0;r<2048;r++){const id=Math.floor(r/16)*2048+1984+r%16;const k=id*16;forms[objects[k+3]]++;const aspect=objects[k+4]/objects[k+5];minAspect=Math.min(minAspect,aspect);maxAspect=Math.max(maxAspect,aspect);
        for(let f=0;f<104;f++){const j=(r*104+f)*4;const n=planes.subarray(j,j+3);const length=Math.hypot(...n);if(!Number.isFinite(length)||Math.abs(length-1)>1e-5||!Number.isFinite(planes[j+3])||planes[j+3]<=0)invalidPlanes++;
          if(n.some(v=>Math.abs(v)>.99999)){axisPlanes++;maxAxisExtent=Math.max(maxAxisExtent,planes[j+3]);}}}
      for(const v of transforms)if(!Number.isFinite(v))invalidTransforms++;
      return {forms,planesPerRock:104,invalidPlanes,invalidTransforms,maxAxisExtent,axisPlanes,minAspect,maxAspect,cacheBytes:planes.byteLength+transforms.byteLength};
    },
    async bankStats(){
      testing=true;await idle();const terrain=await renderer.runtime.read(renderer.terrain);const atlas=await renderer.runtime.read(renderer.atlas,Uint32Array);const objects=await renderer.runtime.read(renderer.objects);const order=await renderer.runtime.read(renderer.order,Uint32Array);const keys=await renderer.runtime.read(renderer.spatialKeys,Uint32Array);
      const seen=new Uint8Array(OBJECT_COUNT);let invalidOrder=0,unsorted=0,ferns=0,rocks=0,actorMaterials=0;for(let i=0;i<OBJECT_COUNT;i++){if(order[i]>=OBJECT_COUNT||seen[order[i]])invalidOrder++;else seen[order[i]]=1;if(i&&keys[i]<keys[i-1])unsorted++;const mat=objects[i*16+11];if(mat===8)ferns++;if(mat===4)rocks++;if(mat>=5&&mat<=7)actorMaterials++;}
      const depths=[];for(let x=-20;x<=20;x+=.5){const ix=Math.round((x+144)/288*4095);for(const z of [10,11,12,13,14]){const iy=Math.round((z+16)/144*2047);const depth=.16-terrain[iy*4096+ix];if(depth>0)depths.push(depth);}}
      let finite=true;for(const v of terrain)if(!Number.isFinite(v)){finite=false;break;}
      const sha=async a=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',a.buffer))).map(x=>x.toString(16).padStart(2,'0')).join('');
      return {finite,invalidOrder,unsorted,ferns,rocks,actorMaterials,terrainSize:[4096,2048],materialSize:[2048,2048],mipLevels:12,depthMin:Math.min(...depths),depthMax:Math.max(...depths),shallowSamples:depths.filter(x=>x<.5).length,deepSamples:depths.filter(x=>x>1.2).length,terrainHash:await sha(terrain),atlasHash:await sha(atlas)};
    },
    async read(name){await idle();const map={objects:renderer.objects,bounds:renderer.bounds,terrain:renderer.terrain,atlas:renderer.atlas,radiance:renderer.raw,guide:renderer.guides[1-renderer.ping],history:renderer.history[1-renderer.ping],albedo:renderer.albedo,filtered:renderer.filtered[1-renderer.ping],coverage:renderer.coverage[1-renderer.ping],pixels:renderer.pixels};if(!map[name])throw Error('Unknown buffer');return Array.from(await renderer.runtime.read(map[name],name==='pixels'||name==='atlas'?Uint32Array:Float32Array));},
    async summary(){await idle();const a=await renderer.runtime.read(renderer.raw);let finite=true,min=Infinity,max=-Infinity,mean=0;for(let i=0;i<a.length;i++){finite&&=Number.isFinite(a[i]);if(i%4!==3){min=Math.min(min,a[i]);max=Math.max(max,a[i]);mean+=a[i];}}return {finite,min,max,mean:mean/(a.length/4*3),state:await renderer.readState(),runtime:renderer.runtime.stats};},
    async regenerate(seed){testing=true;await idle();renderer.seed=seed;await renderer.generate(renderer.location);},
    async geometry(){
      testing=true;await idle();const a=await renderer.runtime.read(renderer.objects);const b=await renderer.runtime.read(renderer.bounds);let finite=true;let invalidRadii=0;let invalidBounds=0;
      for(const v of a)if(!Number.isFinite(v)){finite=false;break;}
      for(let i=0;i<OBJECT_COUNT;i++){const k=i*16;if(a[k+15]===0){if(a[k+4]<=0||a[k+5]<=0||a[k+6]<=0)invalidRadii++;}else if(a[k+3]<=0||a[k+7]<=0)invalidRadii++;}
      for(let i=1;i<OBJECT_COUNT*2;i++){for(let c=0;c<3;c++){const lo=b[i*8+c],hi=b[i*8+4+c];if(!Number.isFinite(lo)||!Number.isFinite(hi)||lo>hi)invalidBounds++;if(i<OBJECT_COUNT){if(lo>b[i*16+c]+1e-5||lo>b[i*16+8+c]+1e-5||hi<b[i*16+4+c]-1e-5||hi<b[i*16+12+c]-1e-5)invalidBounds++;}}}
      const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',a.buffer))).map(x=>x.toString(16).padStart(2,'0')).join('');return {hash,finite,invalidRadii,invalidBounds,objects:OBJECT_COUNT};
    },
    async transport(bounces){
      testing=true;await idle();renderer.frame=317;renderer.reset=1;await renderer.render({...options,bounces,frozen:true});const a=await renderer.runtime.read(renderer.raw);const g=await renderer.runtime.read(renderer.guides[1-renderer.ping]);let water=0,count=0,total=0;for(let i=0;i<a.length;i+=4){const luminance=a[i]*0.2126+a[i+1]*0.7152+a[i+2]*0.0722;total+=luminance;if(g[i+3]===-2){water+=luminance;count++;}}return {mean:total/(a.length/4),waterMean:water/Math.max(1,count),waterPixels:count};
    },
    async save(){await idle();saveProgress();return JSON.parse(localStorage.getItem('secret-river-webcuda-v1'));},
    get cache(){return {...renderer.counters,samples:renderer.samples,limit:renderer.stillLimit};},get manifest(){return renderer.manifest;},get options(){return {...options,paintDepths:{...options.paintDepths}};}
  };
  requestAnimationFrame(frame);
}catch(error){fail(error);}
