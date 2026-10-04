// All scenery, materials, simulation, ray traversal and light transport are authored in CUDA.
// Float4 arrays keep the compiler/runtime ABI explicit. There are no imported meshes or textures.
#define PI 3.14159265359f
#define TAU 6.28318530718f
#define OBJECTS 524288
#define FOREGROUND_OBJECTS 262144
#define CELLS 640
#define PER_CELL 2048
#define TERRAIN_W 4096
#define TERRAIN_H 2048
#define ATLAS_SIZE 2048
#define ATLAS_TEXELS 5592405
#define ROCK_COUNT 2048
#define ROCK_PLANES 104
#define REFERENCE_GEOMETRY 0
__device__ int rockIndex(int id){return (id/PER_CELL)*16+(id%PER_CELL)-1984;}

__device__ float clampf(float x,float a,float b){return fminf(b,fmaxf(a,x));}
__device__ float sat(float x){return clampf(x,0.0f,1.0f);}
__device__ float mixf(float a,float b,float t){return a+(b-a)*t;}
__device__ float smoothf(float a,float b,float x){float t=sat((x-a)/(b-a));return t*t*(3.0f-2.0f*t);}
__device__ float fractf(float x){return x-floorf(x);}
__device__ float3 v3(float x,float y,float z){return make_float3(x,y,z);}
__device__ float3 xyz(float4 a){return v3(a.x,a.y,a.z);}
__device__ float4 v4(float3 a,float w){return make_float4(a.x,a.y,a.z,w);}
__device__ float dot3(float3 a,float3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
__device__ float3 cross3(float3 a,float3 b){return v3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x);}
__device__ float len3(float3 a){return sqrtf(dot3(a,a));}
__device__ float3 unit(float3 a){return a/ sqrtf(fmaxf(1.0e-16f,dot3(a,a)));}
__device__ float3 min3(float3 a,float3 b){return v3(fminf(a.x,b.x),fminf(a.y,b.y),fminf(a.z,b.z));}
__device__ float3 max3(float3 a,float3 b){return v3(fmaxf(a.x,b.x),fmaxf(a.y,b.y),fmaxf(a.z,b.z));}
__device__ float3 abs3(float3 a){return v3(fabsf(a.x),fabsf(a.y),fabsf(a.z));}
__device__ float3 mix3(float3 a,float3 b,float t){return a+(b-a)*t;}
__device__ float3 reflect3(float3 d,float3 n){return d-n*(2.0f*dot3(d,n));}
__device__ float3 windOffset(float3 p,float time){float phase=p.x*0.31f+p.z*0.17f;return v3((sinf(phase+time*1.5f)-sinf(phase))*0.045f,(cosf(phase+time*1.1f)-cosf(phase))*0.008f,(sinf(phase*1.3f+time*1.24f)-sinf(phase*1.3f))*0.025f);}
__device__ float3 tangent(float3 n){return unit(cross3(n,fabsf(n.y)<0.95f?v3(0,1,0):v3(1,0,0)));}
__device__ float3 basisU(float3 axis,float twist){float3 u=tangent(axis);return u*cosf(twist)+cross3(axis,u)*sinf(twist);}
__device__ unsigned int hashU(unsigned int x){x^=x>>16;x*=2146121005u;x^=x>>15;x*=2221713035u;x^=x>>16;return x;}
__device__ float rnd(unsigned int x){return float(hashU(x)&16777215u)*(1.0f/16777216.0f);}
__device__ float lattice(int x,int y,int z){return rnd((unsigned int)(x)*73856093u^(unsigned int)(y)*19349663u^(unsigned int)(z)*83492791u);}
__device__ float noise3(float3 p){
  float3 i=v3(floorf(p.x),floorf(p.y),floorf(p.z));
  float3 f=p-i;f=f*f*(v3(3,3,3)-f*2.0f);
  int x=int(i.x);int y=int(i.y);int z=int(i.z);
  float a=mixf(lattice(x,y,z),lattice(x+1,y,z),f.x);
  float b=mixf(lattice(x,y+1,z),lattice(x+1,y+1,z),f.x);
  float c=mixf(lattice(x,y,z+1),lattice(x+1,y,z+1),f.x);
  float d=mixf(lattice(x,y+1,z+1),lattice(x+1,y+1,z+1),f.x);
  return mixf(mixf(a,b,f.y),mixf(c,d,f.y),f.z);
}
__device__ float fbm(float3 p){return noise3(p)*0.57f+noise3(p*2.03f+v3(3.2f,1.1f,5.4f))*0.28f+noise3(p*4.17f)*0.15f;}
// Original Secret River location shore/road/height knots, evaluated in CUDA.
__device__ float4 profile(float x,int location){
  float4 a=make_float4(-96,20.25f,13.4f,1.78f);
  float4 b=make_float4(-48,19.55f,12.0f,1.84f);
  float4 c=make_float4(0,19.85f,10.6f,1.90f);
  float4 d=make_float4(48,20.35f,13.2f,1.95f);
  float4 e=make_float4(96,19.1f,13.9f,1.99f);
  if(location==1){a=make_float4(-96,20.8f,14,1.70f);b=make_float4(-52,21.4f,12.6f,1.76f);c=make_float4(-8,20.7f,11.4f,1.82f);d=make_float4(40,19.9f,10.2f,1.88f);e=make_float4(96,20.5f,13.1f,1.93f);}
  if(x>b.x){a=b;b=c;if(x>c.x){a=c;b=d;if(x>d.x){a=d;b=e;}}}
  float t=smoothf(a.x,b.x,x);return a+(b-a)*t;
}
__device__ float shore(float x,int loc){return profile(x,loc).z+0.24f*sinf(x*0.43f)+0.12f*sinf(x*1.27f);}
__device__ float groundHeight(float x,float z,int loc){
  float4 p=profile(x,loc);float s=z-shore(x,loc);
  // A continuous, seeded shelf: sandbars alternate with scour pockets along the bank.
  // Fade the variation onto dry land so the original playable bank stays connected.
  float shelf=fbm(v3(x*0.19f,2.1f+float(loc)*4.0f,z*0.23f));
  float channel=fbm(v3(x*0.075f,8.7f+float(loc),z*0.16f));
  float ledge=-0.14f-powf(shelf,1.7f)*1.9f;
  float deep=-2.5f-channel*2.6f;
  float bed=mixf(deep,ledge,smoothf(-10.0f,-0.3f,s));
  float shoreOffset=(shelf-0.5f)*1.6f;
  float h=mixf(bed,p.w,smoothf(0.0f+shoreOffset,4.5f,s));
  float n=fbm(v3(x*0.35f,1.7f,z*0.35f))-0.5f;
  h+=n*0.22f*smoothf(0,3,s);
  h+=(noise3(v3(x*7.1f,3.4f,z*7.1f))-0.5f)*0.032f*smoothf(0.5f,3.0f,s);
  h+=fmaxf(0.0f,z-26.0f)*(loc==1?0.049f:0.023f);
  h+=smoothf(52,95,z)*(9.0f+12.0f*fbm(v3(x*0.025f,2,z*0.035f)));
  return h;
}
__device__ float3 groundNormal(float3 p,int loc){float e=0.035f;return unit(v3(groundHeight(p.x-e,p.z,loc)-groundHeight(p.x+e,p.z,loc),2*e,groundHeight(p.x,p.z-e,loc)-groundHeight(p.x,p.z+e,loc)));}
// State: xyz, velocity xz, distance, facing, location, objective mask, mode,
// hour, camera x/z, previous camera x/z, simulation time, travelled/returned, revision.
__device__ float3 sunDirection(float hour){float phase=(hour-6.0f)/12.0f*PI;return unit(v3(-cosf(phase)*0.83f,sinf(phase),-0.38f));}
__device__ float3 sunColour(float hour){float y=sunDirection(hour).y;return mix3(v3(4.2f,1.45f,0.42f),v3(4.0f,3.68f,2.94f),smoothf(0.04f,0.65f,y))*smoothf(-0.07f,0.07f,y);}
__device__ float3 sky(float3 d,float hour){
  float day=smoothf(-0.16f,0.18f,sunDirection(hour).y);
  float3 horizon=mix3(v3(0.024f,0.040f,0.084f),v3(0.49f,0.62f,0.76f),day);
  float3 zenith=mix3(v3(0.008f,0.020f,0.048f),v3(0.16f,0.34f,0.56f),day);
  float3 c=mix3(horizon,zenith,smoothf(-0.03f,0.85f,d.y));
  float glow=powf(fmaxf(0.0f,dot3(d,sunDirection(hour))),32.0f);
  c+=sunColour(hour)*glow*0.035f;
  return c;
}
