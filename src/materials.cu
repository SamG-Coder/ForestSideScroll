// Reusable geometry/material caches. Generated once in CUDA; never baked lighting.
__global__ void bakeTerrain(float* terrain,int location){
  int x=int(blockIdx.x*blockDim.x+threadIdx.x);int y=int(blockIdx.y*blockDim.y+threadIdx.y);
  if(x>=TERRAIN_W||y>=TERRAIN_H)return;
  terrain[y*TERRAIN_W+x]=groundHeight(float(x)*288.0f/float(TERRAIN_W-1)-144.0f,float(y)*144.0f/float(TERRAIN_H-1)-16.0f,location);
}
__device__ float cachedHeight(const float* terrain,float x,float z,int loc){
  float u=(x+144.0f)*float(TERRAIN_W-1)/288.0f;float v=(z+16.0f)*float(TERRAIN_H-1)/144.0f;
  if(u<0||v<0||u>=float(TERRAIN_W-1)||v>=float(TERRAIN_H-1))return groundHeight(x,z,loc);
  int ix=int(floorf(u));int iy=int(floorf(v));float fx=fractf(u);float fy=fractf(v);int i=iy*TERRAIN_W+ix;
  return mixf(mixf(terrain[i],terrain[i+1],fx),mixf(terrain[i+TERRAIN_W],terrain[i+TERRAIN_W+1],fx),fy);
}
__device__ float3 cachedNormal(const float* terrain,float3 p,int loc){
  float e=0.07f;return unit(v3(cachedHeight(terrain,p.x-e,p.z,loc)-cachedHeight(terrain,p.x+e,p.z,loc),2*e,cachedHeight(terrain,p.x,p.z-e,loc)-cachedHeight(terrain,p.x,p.z+e,loc)));
}
__device__ float tileNoise(float x,float y,int cells,unsigned int seed){
  float px=x*float(cells);float py=y*float(cells);int ix=int(floorf(px));int iy=int(floorf(py));
  float fx=smoothf(0,1,fractf(px));float fy=smoothf(0,1,fractf(py));int mask=cells-1;
  float a=rnd((unsigned int)(ix&mask)*7177u^(unsigned int)(iy&mask)*313u^seed);
  float b=rnd((unsigned int)((ix+1)&mask)*7177u^(unsigned int)(iy&mask)*313u^seed);
  float c=rnd((unsigned int)(ix&mask)*7177u^(unsigned int)((iy+1)&mask)*313u^seed);
  float d=rnd((unsigned int)((ix+1)&mask)*7177u^(unsigned int)((iy+1)&mask)*313u^seed);
  return mixf(mixf(a,b,fx),mixf(c,d,fx),fy);
}
__device__ unsigned int packMaterial(float4 c){return (unsigned int)(sat(c.x)*255.0f+0.5f)|((unsigned int)(sat(c.y)*255.0f+0.5f)<<8)|((unsigned int)(sat(c.z)*255.0f+0.5f)<<16)|((unsigned int)(sat(c.w)*255.0f+0.5f)<<24);}
__device__ float4 unpackMaterial(unsigned int c){return make_float4(float(c&255u),float((c>>8)&255u),float((c>>16)&255u),float((c>>24)&255u))/255.0f;}
__device__ int mipOffset(int level){int size=ATLAS_SIZE>>level;return (ATLAS_SIZE*ATLAS_SIZE-size*size)*4/3;}
__global__ void bakeMaterials(unsigned int* atlas){
  int x=int(blockIdx.x*blockDim.x+threadIdx.x);int y=int(blockIdx.y*blockDim.y+threadIdx.y);if(x>=ATLAS_SIZE||y>=ATLAS_SIZE)return;
  float u=float(x)/float(ATLAS_SIZE);float v=float(y)/float(ATLAS_SIZE);
  float broad=tileNoise(u,v,4,7381u);float clods=tileNoise(u,v,32,371u);float grit=tileNoise(u,v,256,191u);float fine=tileNoise(u,v,1024,621u);
  float pebbles=smoothf(0.66f,0.83f,tileNoise(u,v,128,824u));
  float cracks=1-smoothf(0.014f,0.049f,fabsf(tileNoise(u,v,16,44u)-0.5f));
  float3 soil=mix3(v3(0.11f,0.068f,0.028f),v3(0.29f,0.20f,0.104f),broad*0.55f+clods*0.45f);
  soil*=0.68f+0.48f*grit+fine*0.18f;soil*=1-cracks*0.25f;
  soil=mix3(soil,v3(0.30f,0.24f,0.16f)*(0.85f+fine*0.25f),pebbles*0.40f);
  atlas[y*ATLAS_SIZE+x]=packMaterial(v4(soil,sat(clods*0.45f+grit*0.26f+pebbles*0.29f-cracks*0.2f)));
  float layers=sinf(v*TAU*24.0f+tileNoise(u,v,8,493u)*5.0f);
  float seams=smoothf(0.85f,0.97f,layers);float mineral=tileNoise(u,v,512,274u);float pits=smoothf(0.68f,0.86f,tileNoise(u,v,256,3177u));
  float3 stone=mix3(v3(0.35f,0.26f,0.155f),v3(0.60f,0.49f,0.33f),broad);
  stone*=0.77f+0.3f*mineral+0.12f*fine;stone*=1-seams*0.29f-pits*0.23f;
  stone=mix3(stone,v3(0.25f,0.115f,0.038f),smoothf(0.68f,0.86f,clods)*0.32f);
  atlas[ATLAS_TEXELS+y*ATLAS_SIZE+x]=packMaterial(v4(stone,sat(0.5f+grit*0.24f+mineral*0.12f-seams*0.22f-pits*0.27f)));
}
__global__ void materialMip(unsigned int* atlas,int level){
  int x=int(blockIdx.x*blockDim.x+threadIdx.x);int y=int(blockIdx.y*blockDim.y+threadIdx.y);int size=ATLAS_SIZE>>level;if(x>=size||y>=size)return;
  int previous=mipOffset(level-1);int current=mipOffset(level);int i=previous+y*4*size+x*2;
  for(int kind=0;kind<2;kind++){int base=kind*ATLAS_TEXELS;float4 c=unpackMaterial(atlas[base+i])+unpackMaterial(atlas[base+i+1])+unpackMaterial(atlas[base+i+size*2])+unpackMaterial(atlas[base+i+size*2+1]);atlas[base+current+y*size+x]=packMaterial(c*0.25f);}
}
__device__ float4 materialBilinear(const unsigned int* atlas,float u,float v,int kind,int level){
  int size=ATLAS_SIZE>>level;int mask=size-1;int offset=kind*ATLAS_TEXELS+mipOffset(level);
  float x=fractf(u)*float(size)-0.5f;float y=fractf(v)*float(size)-0.5f;int ix=int(floorf(x));int iy=int(floorf(y));float fx=fractf(x);float fy=fractf(y);
  float4 a=unpackMaterial(atlas[offset+(iy&mask)*size+(ix&mask)]);float4 b=unpackMaterial(atlas[offset+(iy&mask)*size+((ix+1)&mask)]);
  float4 c=unpackMaterial(atlas[offset+((iy+1)&mask)*size+(ix&mask)]);float4 d=unpackMaterial(atlas[offset+((iy+1)&mask)*size+((ix+1)&mask)]);
  return (a+(b-a)*fx)*(1-fy)+(c+(d-c)*fx)*fy;
}
__device__ float4 materialSample(const unsigned int* atlas,float u,float v,int kind,float footprint){
  float lod=clampf(logf(fmaxf(1.0f,footprint*float(ATLAS_SIZE)))*1.442695f,0,11);int level=int(lod);
  float4 a=materialBilinear(atlas,u,v,kind,level);float4 b=materialBilinear(atlas,u,v,kind,level<11?level+1:11);return a+(b-a)*fractf(lod);
}
__device__ float4 rockTexture(const unsigned int* atlas,float3 p,float3 n,float footprint){
  float3 w=abs3(n);w=w*w*w*w;w/=w.x+w.y+w.z;
  return materialSample(atlas,p.z*0.5f,p.y*0.5f,1,footprint*0.5f)*w.x+materialSample(atlas,p.x*0.5f,p.z*0.5f,1,footprint*0.5f)*w.y+materialSample(atlas,p.x*0.5f,p.y*0.5f,1,footprint*0.5f)*w.z;
}
