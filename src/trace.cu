struct Hit {float t; int id; float3 normal;};
__device__ float boundsHit(float3 ro,float3 inv,float3 lo,float3 hi,float limit){
  float3 a=(lo-ro)*inv;float3 b=(hi-ro)*inv;float3 nearV=min3(a,b);float3 farV=max3(a,b);
  float t0=fmaxf(0.001f,fmaxf(nearV.x,fmaxf(nearV.y,nearV.z)));
  float t1=fminf(limit,fminf(farV.x,fminf(farV.y,farV.z)));return t0<=t1?t0:1.0e20f;
}
__device__ float safeInv(float x){return 1.0f/(fabsf(x)<1e-8f?(x<0?-1e-8f:1e-8f):x);}
__device__ Hit objectHit(const float4* objects,const float4* rayGeometry,const float4* rockPlanes,int id,int rank,float3 ro,float3 rd,float limit,float time,int shadow,int reference){
  Hit hit;hit.t=limit;hit.id=-9;hit.normal=v3(0,1,0);
  float4 aa;float4 bb;float4 cc;float4 dd;
  if(reference!=0){
    // Independent, uncached transform path retained for the numerical/image oracle.
    aa=objects[id*4];float4 b=objects[id*4+1];float4 d=objects[id*4+3];int mat=int(objects[id*4+2].w);
    if(d.w>0.5f){float3 ba=xyz(b)-xyz(aa);float length=len3(ba);bb=b;cc=v4(ba/fmaxf(length,1e-8f),length);dd=make_float4((b.w-aa.w)/fmaxf(length,1e-8f),0,0,float(mat+16));}
    else{float3 axis=xyz(d);float3 u=basisU(axis,b.w);float3 v=cross3(axis,u);bb=v4(u/b.x,0);cc=v4(axis/b.y,0);dd=v4(v/b.z,float(mat));if(mat==2||mat==8)aa=v4(xyz(aa)+windOffset(xyz(aa),time),aa.w);}
  }else{aa=rayGeometry[rank*4];bb=rayGeometry[rank*4+1];cc=rayGeometry[rank*4+2];dd=rayGeometry[rank*4+3];}
  float3 q=ro-xyz(aa);int material=int(dd.w);
  if(material>=16){
    float3 axis=xyz(cc);float length=cc.w;float y0=dot3(q,axis);float yd=dot3(rd,axis);
    float slope=dd.x;float radius=aa.w+slope*y0;
    float3 op=q-axis*y0;float3 dp=rd-axis*yd;
    float qa=dot3(dp,dp)-slope*slope*yd*yd;float qb=dot3(op,dp)-radius*slope*yd;float qc=dot3(op,op)-radius*radius;
    float disc=qb*qb-qa*qc;
    if(disc>=0&&qa>1e-10f){float t=(-qb-sqrtf(disc))/qa;float y=y0+t*yd;if(t>0.002f&&t<hit.t&&y>0&&y<length){hit.t=t;hit.id=id;if(shadow!=0)return hit;hit.normal=unit(q+rd*t-axis*y-axis*((aa.w+slope*y)*slope));}}
    for(int k=0;k<2;k++){float3 oc=ro-(k==0?xyz(aa):xyz(bb));float r=k==0?aa.w:bb.w;float bs=dot3(oc,rd);float cs=dot3(oc,oc)-r*r;float ds=bs*bs-cs;if(ds>=0){float t=-bs-sqrtf(ds);if(t>0.002f&&t<hit.t){hit.t=t;hit.id=id;if(shadow!=0)return hit;hit.normal=unit(oc+rd*t);}}}
  }else{
    float3 u=xyz(bb);float3 axis=xyz(cc);float3 v=xyz(dd);
    float3 o=v3(dot3(q,u),dot3(q,axis),dot3(q,v));float3 d=v3(dot3(rd,u),dot3(rd,axis),dot3(rd,v));
    if(material==4){
      float enter=0.002f;float leave=limit;float3 normal=v3(0,1,0);int base=rockIndex(id)*ROCK_PLANES;
      for(int plane=0;plane<ROCK_PLANES;plane++){
        float4 face=rockPlanes[base+plane];float3 pn=xyz(face);
        float denominator=dot3(pn,d);float numerator=face.w-dot3(pn,o);
        if(fabsf(denominator)<1e-9f){if(numerator<0)leave=-1;}
        else{float t=numerator/denominator;if(denominator<0){if(t>enter){enter=t;normal=pn;}}else leave=fminf(leave,t);}
        if(enter>leave)return hit;
      }
      if(enter<=leave&&enter>0.002f&&enter<limit){hit.t=enter;hit.id=id;if(shadow==0)hit.normal=unit(u*normal.x+axis*normal.y+v*normal.z);}
      return hit;
    }
    float qa=dot3(d,d);float qb=dot3(o,d);float qc=dot3(o,o)-1;float disc=qb*qb-qa*qc;
    if(disc>=0){float t=(-qb-sqrtf(disc))/qa;if(t<=0.002f)t=(-qb+sqrtf(disc))/qa;
      if(t>0.002f&&t<hit.t){float3 p=o+d*t;hit.t=t;hit.id=id;if(shadow==0)hit.normal=unit(u*p.x+axis*p.y+v*p.z);}}
  }
  return hit;
}
__device__ Hit forestHit(const float4* objects,const float4* bounds,const float4* rayGeometry,const float4* rockPlanes,float3 ro,float3 rd,float limit,float time,int shadow,int reference){
  Hit best;best.t=limit;best.id=-9;best.normal=v3(0,1,0);
  float3 inv=v3(safeInv(rd.x),safeInv(rd.y),safeInv(rd.z));
  int stack[32];int top=0;int node=1;int needsTest=1;
  for(int iteration=0;iteration<4096;iteration++){
    if(needsTest==0||boundsHit(ro,inv,xyz(bounds[node*2]),xyz(bounds[node*2+1]),best.t)<best.t){
      if(node>=OBJECTS){Hit h=objectHit(objects,rayGeometry,rockPlanes,int(bounds[node*2].w),node-OBJECTS,ro,rd,best.t,time,shadow,reference);if(h.id>=0){best=h;if(shadow!=0)return best;}}
      else {
        int l=node*2;int r=l+1;float dl=boundsHit(ro,inv,xyz(bounds[l*2]),xyz(bounds[l*2+1]),best.t);float dr=boundsHit(ro,inv,xyz(bounds[r*2]),xyz(bounds[r*2+1]),best.t);
        // The chosen child's bounds were just tested. Retest only deferred nodes,
        // because a closer hit may have shortened the ray since they were stacked.
        if(dl<best.t||dr<best.t){if(dl<dr){if(dr<best.t){stack[top]=r;top++;}node=l;}else{if(dl<best.t){stack[top]=l;top++;}node=r;}needsTest=reference;continue;}
      }
    }
    if(top==0)break;top--;node=stack[top];needsTest=1;
  }
  return best;
}
__device__ Hit terrainHit(const float* terrain,float3 ro,float3 rd,float limit,int loc,int shadow){
  Hit h;h.t=limit;h.id=-9;h.normal=v3(0,1,0);
  float t=0.03f;float prev=0.0f;
  for(int k=0;k<256;k++){
    float3 p=ro+rd*t;if(t>=limit||p.y>54.0f)break;
    float d=p.y-cachedHeight(terrain,p.x,p.z,loc);
    if(d<0.003f){if(shadow!=0){h.t=t;h.id=-1;return h;}float a=prev;float b=t;for(int j=0;j<7;j++){float m=(a+b)*0.5f;float3 v=ro+rd*m;if(v.y>cachedHeight(terrain,v.x,v.z,loc))a=m;else b=m;}h.t=(a+b)*0.5f;h.id=-1;h.normal=cachedNormal(terrain,ro+rd*h.t,loc);return h;}
    // Keep grazing rays advancing across the low-frequency height field; a fixed tiny
    // floor exhausted the traversal budget above almost-flat bank sections.
    prev=t;t+=fminf(5.5f,fmaxf(d*0.62f,0.13f+t*0.004f));
  }
  return h;
}
__device__ float3 waterNormal(float3 p,float time){
  float ax=p.x*2.0f+p.z*0.85f+time*1.3f;float az=p.z*3.8f-p.x*0.44f-time*1.12f;
  return unit(v3(-0.014f*cosf(ax)*2.0f-0.005f*cosf(az)*(-0.44f),1,-0.014f*cosf(ax)*0.85f-0.005f*cosf(az)*3.8f));
}
__device__ Hit sceneHit(const float4* objects,const float4* bounds,const float4* rayGeometry,const float4* rockPlanes,const float* terrain,float3 ro,float3 rd,float limit,int loc,float time,int shadow,int reference){
  Hit best;best.t=limit;best.id=-9;best.normal=v3(0,1,0);
  if(shadow==0){
    // Bound primary traversal by the visible water interface before walking the BVH.
    if(fabsf(rd.y)>0.00001f){float t=(0.16f-ro.y)/rd.y;if(t>0.005f&&t<best.t){float3 p=ro+rd*t;if(cachedHeight(terrain,p.x,p.z,loc)<0.159f){best.t=t;best.id=-2;best.normal=waterNormal(p,time);}}}
    Hit ground=terrainHit(terrain,ro,rd,best.t,loc,shadow);if(ground.id==-1)best=ground;
  }
  Hit tree=forestHit(objects,bounds,rayGeometry,rockPlanes,ro,rd,best.t,time,shadow,reference);if(tree.id>=0)best=tree;
  if(shadow!=0&&best.id>=0)return best;
  if(shadow!=0){Hit ground=terrainHit(terrain,ro,rd,best.t,loc,shadow);if(ground.id==-1)best=ground;}
  return best;
}
__device__ float3 surfaceColour(const float4* objects,const unsigned int* atlas,Hit h,float3 p,int loc,float footprint){
  if(h.id==-2)return v3(0.94f,0.98f,0.96f);
  if(h.id==-1){
    float3 soil=xyz(materialSample(atlas,p.x*0.25f,p.z*0.25f,0,footprint*0.25f));
    float detail=fbm(p*0.7f);soil*=0.73f+detail*0.6f;
    float wet=1-smoothf(0.13f,0.70f,p.y);soil*=1-wet*0.24f;
    // Exposed quartz sand and pebbles remain visible through the shallow margins.
    soil=mix3(soil,soil*v3(1.40f,1.45f,1.32f),smoothf(0.25f,-0.7f,p.y)*0.6f);
    float grass=smoothf(22.8f,27.5f,p.z)*smoothf(0.42f,0.68f,noise3(p*0.55f));
    soil=mix3(soil,v3(0.15f,0.18f,0.07f),grass*0.7f);
    // Procedural fallen gum leaves and grit, in world coordinates, with distance filtering.
    float2 cell=make_float2(floorf(p.x*6),floorf(p.z*6));float2 q=make_float2(fractf(p.x*6)-0.5f,fractf(p.z*6)-0.5f);
    unsigned int key=(unsigned int)(int(cell.x))*7177u^(unsigned int)(int(cell.y))*313u;
    float angle=rnd(key)*TAU;float u=q.x*cosf(angle)+q.y*sinf(angle);float v=-q.x*sinf(angle)+q.y*cosf(angle);
    float leaf=smoothf(1.08f,0.87f,u*u/0.23f+v*v/0.006f)*(rnd(key+1u)>0.52f?1.0f:0.0f);
    soil=mix3(soil,v3(0.20f,0.095f,0.026f)*(0.7f+rnd(key+2u)*0.6f),leaf*(1-sat(footprint*8)));
    return soil;
  }
  int id=h.id;float4 mat=objects[id*4+2];float3 colour=xyz(mat);
  if(int(mat.w)==1){
    float patch=fbm(p*v3(5.0f,1.6f,5.0f));
    float strip=noise3(p*v3(23.0f,1.8f,23.0f)+v3(patch*3.0f,0,0));
    colour=mix3(colour*0.44f,colour*1.12f,smoothf(0.29f,0.64f,patch));
    colour=mix3(colour,v3(0.19f,0.10f,0.049f),smoothf(0.53f,0.65f,strip)*0.78f);
    float scars=smoothf(0.67f,0.73f,noise3(p*v3(37,3.0f,37)));colour*=1-scars*0.32f*(1-sat(footprint*10));
  } else if(int(mat.w)==4){
    colour=xyz(rockTexture(atlas,p,h.normal,footprint))*colour/v3(0.46f,0.35f,0.22f);
    colour*=1-(1-smoothf(0.13f,0.36f,p.y))*0.30f;
    float lichen=smoothf(0.62f,0.80f,noise3(p*12.0f))*smoothf(0.25f,0.8f,h.normal.y);colour=mix3(colour,v3(0.25f,0.29f,0.12f),lichen*0.35f);
  } else if(int(mat.w)==2||int(mat.w)==8){
    float4 a=objects[id*4];float4 b=objects[id*4+1];float3 axis=xyz(objects[id*4+3]);float3 u=basisU(axis,b.w);float3 q=p-xyz(a);
    float across=dot3(q,u)/b.x;float along=dot3(q,axis)/b.y;
    float vein=1-smoothf(0.025f,0.11f,fabsf(across));float ribs=powf(fmaxf(0,sinf(along*52+fabsf(across)*13)),16);
    colour*=0.80f+noise3(p*20)*0.28f;colour=mix3(colour,colour*1.4f,(vein*0.34f+ribs*0.09f)*(1-sat(footprint*4)));
  }
  return colour;
}
__device__ int materialAt(const float4* objects,int id){if(id<0)return id;return int(objects[id*4+2].w);}
__device__ float3 cosineRay(float3 n,float r1,float r2){float r=sqrtf(r1);float a=TAU*r2;float3 u=tangent(n);float3 v=cross3(n,u);return unit(u*(cosf(a)*r)+v*(sinf(a)*r)+n*sqrtf(1-r1));}
