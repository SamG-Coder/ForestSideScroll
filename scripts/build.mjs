import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {compile,serializableArtifact,COMPILER_VERSION} from '../vendor/cuda-webshader/compiler/compiler.js';
const provenance=JSON.parse(await readFile(new URL('../vendor/cuda-webshader/PROVENANCE.json',import.meta.url),'utf8'));
const nativePrelude=await readFile(new URL('../src/native-vectors.cuh',import.meta.url),'utf8');
const files=['common','game','generate','materials','trace','render','paint'];
const source=(await Promise.all(files.map(f=>readFile(new URL(`../src/${f}.cu`,import.meta.url),'utf8')))).join('\n');
const hash=s=>createHash('sha256').update(s).digest('hex');
await mkdir(new URL('../generated/',import.meta.url),{recursive:true});
const entries={initGame:1,stepGame:1,generateScene:64,prepareRayGeometry:128,prepareRockPlanes:64,updateLeafMotion:128,spatialKeys:128,buildLeaves:128,buildLevel:128,bakeTerrain:[8,8,1],bakeMaterials:[8,8,1],materialMip:[8,8,1],tracePaths:[8,4,1],traceReference:[8,8,1],accumulate:[8,8,1],filterImage:[8,8,1],resolveImage:[8,8,1],paintScene:[8,8,1]};
const manifest={compilerVersion:COMPILER_VERSION,compilerOrigin:'SamG-Coder/cuda-webshader',compilerRevision:provenance.revision,nativePreludeSha256:hash(nativePrelude),sourceSha256:hash(source),files,entries:[]};
for(const [entry,block] of Object.entries(entries)){
  const workgroupSize=Array.isArray(block)?block:[block,1,1];
  // Compile the uncached oracle separately, so its branches never cost registers
  // or instructions in the production shader. Both variants come from the CUDA source.
  const kernelSource=entry==='traceReference'?source.replace('#define REFERENCE_GEOMETRY 0','#define REFERENCE_GEOMETRY 1').replace('__global__ void tracePaths(','__global__ void traceReference('):source;
  const artifact=serializableArtifact(compile(kernelSource,{entry,workgroupSize,includeNativeSource:true}));
  // ChromiumRTXCuda accepts self-contained device code without preprocessor directives.
  artifact.native.source=nativePrelude+'\n'+artifact.native.source.replace(/^#define (\w+) ([0-9.eEfFuU+-]+)\s*$/gm,(_,name,value)=>`constexpr ${/[.eEfF]/.test(value)?'float':'int'} ${name} = ${value};`);
  if(/#|\\|%:|\?\?/.test(artifact.native.source))throw Error('Native source contains unsupported preprocessing');
  const json=JSON.stringify(artifact);
  await writeFile(new URL(`../generated/${entry}.json`,import.meta.url),json);
  await writeFile(new URL(`../generated/${entry}.wgsl`,import.meta.url),artifact.wgsl);
  manifest.entries.push({entry,workgroupSize,sourceSha256:hash(kernelSource),sha256:hash(json),wgslSha256:hash(artifact.wgsl),bindings:artifact.metadata.bindings.map(b=>b.name)});
  console.log(`${entry}: ${artifact.wgsl.length} WGSL bytes`);
}
await writeFile(new URL('../generated/manifest.json',import.meta.url),JSON.stringify(manifest,null,2));
