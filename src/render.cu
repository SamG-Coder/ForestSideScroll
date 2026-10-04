__device__ float3 cameraForward(){return unit(v3(0,0.095f,1));}
__device__ float3 cameraUp(){float3 f=cameraForward();return v3(0,f.z,-f.y);}
__device__ float3 cameraOrigin(float x,float z){return v3(x,1.65f,z-26.0f);}
__global__ void tracePaths(const float4* objects,const float4* bounds,const float4* rayGeometry,const float4* rockPlanes,const float* terrain,const unsigned int* atlas,const float* state,const float4* oldGuide,const float4* oldNormals,const float4* oldHistory,float4* radiance,float4* guide,float4* normals,float4* albedo,int width,int height,int frame,int bounces,int reuseLighting){
  int referenceGeometry=REFERENCE_GEOMETRY;
  int x=int(blockIdx.x*blockDim.x+threadIdx.x);int y=int(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int pixel=y*width+x;
  unsigned int seed=hashU((unsigned int)(pixel)*9781u+(unsigned int)(frame)*6271u+381u);
  float jx=rnd(seed+1u)-0.5f;float jy=rnd(seed+2u)-0.5f;
  float scale=0.40f;float aspect=float(width)/float(height);
  float sx=((float(x)+0.5f+jx)/float(width)*2-1)*aspect*scale;
  float sy=(1-(float(y)+0.5f+jy)/float(height)*2)*scale;
  float3 ro=cameraOrigin(state[11],state[12]);
  float3 rd=unit(cameraForward()+v3(sx,0,0)+cameraUp()*sy);
  float3 throughput=v3(1,1,1);float3 light=v3(0,0,0);int loc=int(state[7]);
  float hour=state[10];float tm=state[15];float3 sun=sunDirection(hour);float3 sunE=sunColour(hour);
  if(sun.y<0){float moon=smoothf(0.0f,0.22f,-sun.y);sun=unit(v3(-0.52f,0.74f,-0.43f));sunE=v3(0.18f,0.25f,0.39f)*moon;}
  float3 firstPoint=ro+rd*350;float3 firstNormal=v3(0,0,0);float firstMat=-9;float firstDistance=350;
  int under=0;
  albedo[pixel]=make_float4(0,0,0,0);
  for(int bounce=0;bounce<6;bounce++){
    if(bounce>=bounces)break;
    Hit hit=sceneHit(objects,bounds,rayGeometry,rockPlanes,terrain,ro,rd,350,loc,tm,0,referenceGeometry);
    if(hit.id==-9){light+=throughput*sky(rd,hour);break;}
    float3 p=ro+rd*hit.t;float3 n=hit.normal;int mat=materialAt(objects,hit.id);
    if(bounce==0){firstPoint=p;firstNormal=n;firstMat=float(hit.id);firstDistance=hit.t;}
    if(under!=0){
      // Beer-Lambert transport over the actual refracted path to the variable riverbed.
      // A short path reveals sand and stones; deep pockets absorb and scatter more light.
      float3 trans=v3(expf(-hit.t*0.32f),expf(-hit.t*0.17f),expf(-hit.t*0.48f));
      float3 scatter=sky(v3(0,0.4f,1),hour)*v3(0.075f,0.16f,0.052f);
      light+=throughput*(v3(1,1,1)-trans)*scatter;throughput*=trans;
    }
    if(hit.id==-2){
      if(dot3(rd,n)>0)n=n*-1.0f;
      float cosI=clampf(-dot3(rd,n),0,1);float fresnel=0.0204f+0.9796f*powf(1-cosI,5);
      float waterDepth=fmaxf(0,0.16f-cachedHeight(terrain,p.x,p.z,loc));
      // Fade the grazing reflection at the wet margin so a thin film reveals its bed.
      fresnel*=mixf(0.10f,1.0f,smoothf(0.025f,1.15f,waterDepth));
      float probability=clampf(fresnel,0.18f,0.88f);
      float3 refl=unit(reflect3(rd,n));
      // The finite solar disk is sampled directly on the glossy water lobe.
      float highlight=powf(fmaxf(0.0f,dot3(refl,sun)),1400.0f);
      if(highlight>0.001f&&sun.y>0){Hit sh=sceneHit(objects,bounds,rayGeometry,rockPlanes,terrain,p+n*0.01f,sun,160,loc,tm,1,referenceGeometry);if(sh.id==-9)light+=throughput*sunE*(highlight*fresnel*8.0f);}
      if(rnd(seed+(unsigned int)(bounce)*131u+10u)<probability){throughput*=fresnel/probability;rd=refl;ro=p+n*0.013f;under=0;}
      else {float eta=under!=0?1.333f:0.75019f;float k=1-eta*eta*(1-cosI*cosI);if(k<0){rd=refl;ro=p+n*0.013f;}else{rd=unit(rd*eta+n*(eta*cosI-sqrtf(k)));ro=p-n*0.013f;under=under==0?1:0;throughput*=(1-fresnel)/(1-probability);}}
      continue;
    }
    int back=dot3(n,rd)>0?1:0;if(back!=0)n=n*-1.0f;

    float footprint=firstDistance*0.8f/float(height);
    float3 colour=surfaceColour(objects,atlas,hit,p,loc,footprint);
    // Preserve the visible material for foliage-aware denoising. Lighting
    // and light transport use only RGB, so this tag never enters the lighting.
    if(bounce==0)albedo[pixel]=v4(colour,float(mat));
    if(bounce==0&&reuseLighting!=0&&((x+y+frame)&1)==0){
      float3 q=p-cameraOrigin(state[13],state[14]);float depth=dot3(q,cameraForward());
      int px=int(floorf((q.x/(depth*0.4f*aspect)*0.5f+0.5f)*float(width)));
      int py=int(floorf((0.5f-dot3(q,cameraUp())/(depth*0.8f))*float(height)));
      if(px>=0&&py>=0&&px<width&&py<height&&depth>0){
        int j=py*width+px;float4 og=oldGuide[j];float4 on=oldNormals[j];float4 oh=oldHistory[j];float age=fractf(oh.w)*16.0f;
        // Exact primitive identity, geometric normal and position reject newly exposed
        // surfaces. A value can survive only one frame without a fresh traced sample.
        if(og.w==float(hit.id)&&dot3(xyz(on),firstNormal)>0.96f&&len3(xyz(og)-p)<0.015f+hit.t*0.0014f&&floorf(oh.w)>=1&&age<0.5f){
          radiance[pixel]=v4(xyz(oh),-1);guide[pixel]=v4(firstPoint,firstMat);normals[pixel]=v4(firstNormal,firstDistance);return;
        }
      }
    }
    if(mat==1||mat==4){float freq=mat==1?18.0f:48.0f;float3 q=p*freq;float e=0.08f;float3 gradient=v3(noise3(q+v3(e,0,0))-noise3(q-v3(e,0,0)),noise3(q+v3(0,e,0))-noise3(q-v3(0,e,0)),noise3(q+v3(0,0,e))-noise3(q-v3(0,0,e)));gradient-=n*dot3(gradient,n);n=unit(n-gradient*(mat==1?1.2f:0.85f));}
    if(mat==-1){
      float e=0.001f;float gx=materialSample(atlas,p.x*0.25f+e,p.z*0.25f,0,footprint*0.25f).w-materialSample(atlas,p.x*0.25f-e,p.z*0.25f,0,footprint*0.25f).w;
      float gz=materialSample(atlas,p.x*0.25f,p.z*0.25f+e,0,footprint*0.25f).w-materialSample(atlas,p.x*0.25f,p.z*0.25f-e,0,footprint*0.25f).w;
      n=unit(n-v3(gx,0,gz)*1.1f);
    }
    // A thin leaf has a diffuse transmission branch; both sides cast real ray shadows.
    float transmission=mat==2||mat==8?0.22f:0.0f;
    float3 su=tangent(sun);float3 sv=cross3(sun,su);
    float a=TAU*rnd(seed+(unsigned int)(bounce)*117u+34u);float rad=sqrtf(rnd(seed+(unsigned int)(bounce)*83u+22u))*0.017f;
    float3 ld=unit(sun+su*(cosf(a)*rad)+sv*(sinf(a)*rad));
    float nd=dot3(n,ld);float cosine=fmaxf(0,nd)*(1-transmission)+fmaxf(0,-nd)*transmission;
    if(cosine>0.001f&&sun.y>-0.03f){
      float3 side=nd>=0?n:n*-1;Hit shadow=sceneHit(objects,bounds,rayGeometry,rockPlanes,terrain,p+side*0.008f,ld,180,loc,tm,1,referenceGeometry);
      float sunPath=under!=0?fmaxf(0,0.16f-p.y)/fmaxf(0.12f,ld.y):0;
      float3 waterSun=v3(expf(-sunPath*0.32f),expf(-sunPath*0.17f),expf(-sunPath*0.48f));
      if(shadow.id==-9)light+=throughput*colour*sunE*waterSun*(cosine/PI);
    }
    if(bounce+1>=bounces)break;
    throughput*=colour;
    float3 hemisphere=n;
    if((mat==2||mat==8)&&rnd(seed+(unsigned int)(bounce)*197u+54u)<transmission)hemisphere=n*-1;
    rd=cosineRay(hemisphere,rnd(seed+(unsigned int)(bounce)*71u+61u),rnd(seed+(unsigned int)(bounce)*97u+89u));
    ro=p+hemisphere*0.008f;
    // Unbiased roulette after the second surface keeps rare long paths without
    // spending another full visibility query on every low-energy diffuse path.
    if(bounce>=1){float survival=clampf(fmaxf(throughput.x,fmaxf(throughput.y,throughput.z)),0.10f,0.95f);if(rnd(seed+(unsigned int)(bounce)*353u+17u)>survival)break;throughput/=survival;}
  }
  // Single-scattering distance approximation for aerial perspective, separate from surface bounces.
  float fog=1-expf(-fmaxf(0,firstDistance-20)*0.0028f);
  light=mix3(light,sky(v3(0,0.06f,1),hour)*0.56f,fog);
  radiance[pixel]=v4(max3(light,v3(0,0,0)),1);
  guide[pixel]=v4(firstPoint,firstMat);normals[pixel]=v4(firstNormal,firstDistance);
}
__global__ void accumulate(const float4* radiance,const float4* guide,const float4* normals,const float4* oldGuide,const float4* oldNormals,const float4* oldHistory,float4* history,const float* state,int width,int height,int reset,int frozen){
  int x=int(blockIdx.x*blockDim.x+threadIdx.x);int y=int(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int i=y*width+x;
  float4 g=guide[i];float4 n=normals[i];float3 value=xyz(radiance[i]);float count=1;
  if(reset==0){
    float3 q=xyz(g)-cameraOrigin(state[13],state[14]);float depth=dot3(q,cameraForward());
    float u=(q.x/(depth*0.4f*(float(width)/float(height)))*0.5f+0.5f)*float(width)-0.5f;
    float v=(0.5f-dot3(q,cameraUp())/(depth*0.8f))*float(height)-0.5f;
    int px=int(floorf(u+0.5f));int py=int(floorf(v+0.5f));
    if(px>=0&&py>=0&&px<width&&py<height&&depth>0){
      int j=py*width+px;float4 og=oldGuide[j];float4 on=oldNormals[j];float4 h=oldHistory[j];
      float threshold=0.06f+n.w*0.008f;float dist=len3(xyz(og)-xyz(g));
      if(g.w==og.w&&(g.w==-9||dot3(xyz(n),xyz(on))>0.82f)&&dist<threshold){
        float cap=frozen!=0?256.0f:12.0f;if(g.w==-2&&frozen==0)cap=5;
        if(radiance[i].w<0){count=floorf(h.w)+0.0625f;value=xyz(radiance[i]);}
        else {count=fminf(floorf(h.w)+1,cap);value=mix3(xyz(h),value,1/count);}
      }
    }
  }
  history[i]=v4(value,count);
}
__global__ void filterImage(const float4* source,const float4* guide,const float4* normals,const float4* albedo,const float4* oldImage,const float4* oldGuide,const float4* oldNormals,const float4* oldCoverage,const float* state,float4* filtered,float4* coverage,int width,int height,int step,int reset,int frozen){
  int x=int(blockIdx.x*blockDim.x+threadIdx.x);int y=int(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int i=y*width+x;
  float4 centre=source[i];float4 g=guide[i];float4 n=normals[i];
  float3 sum=xyz(centre)*4;float weights=4;
  for(int yy=-1;yy<=1;yy++)for(int xx=-1;xx<=1;xx++){
    if(xx==0&&yy==0)continue;int px=x+xx*step;int py=y+yy*step;if(px<0||py<0||px>=width||py>=height)continue;int j=py*width+px;
    float4 ng=guide[j];float4 nn=normals[j];int mat=int(albedo[i].w);int foliage=mat==2||mat==3||mat==8?1:0;
    // Leaflets smaller than a pixel need their neighbours to denoise. Primitive
    // identity alone left almost every grass/fern sample completely unfiltered.
    if(ng.w!=g.w&&(foliage==0||albedo[j].w!=albedo[i].w))continue;
    float normalWeight=g.w<0?1:powf(fmaxf(0,dot3(xyz(n),xyz(nn))),24);
    if(foliage!=0)normalWeight=0.35f+0.65f*fabsf(dot3(xyz(n),xyz(nn)));
    float depthWeight=expf(-fabsf(nn.w-n.w)/(0.05f+n.w*(foliage!=0?0.016f:0.006f)*float(step)));
    float colourWeight=expf(-len3(xyz(albedo[i])-xyz(albedo[j]))*14.0f);
    float w=normalWeight*depthWeight*colourWeight*(xx==0||yy==0?2.0f:1.0f);
    sum+=xyz(source[j])*w;weights+=w;
  }
  float strength=mixf(0.95f,0.15f,sat(centre.w/100.0f));
  float3 colour=mix3(xyz(centre),sum/weights,strength);float samples=centre.w;
  if(step==2){
    // Material coverage follows the same subpixel history as the image.
    float4 mask=make_float4(0,0,0,0);int mat=int(albedo[i].w);
    if(g.w==-2)mask.w=1;
    else if(g.w==-1||mat==1)mask.x=1;
    else if(mat==4)mask.y=1;
    else if(mat==2||mat==3||mat==8)mask.z=1;
    // Lighting history belongs to a surface; pixel coverage includes every
    // subpixel surface (including gaps between leaves). Keep these histories
    // separate so rejecting a light sample cannot make a silhouette sparkle.
    samples=1;
    if(reset==0){
      float cameraMotion=fabsf(state[11]-state[13])+fabsf(state[12]-state[14]);
      float3 previous=v3(0,0,0);float4 previousMask=make_float4(0,0,0,0);float previousCount=0;float validWeight=0;
      if(cameraMotion<0.000001f){float4 h=oldImage[i];previous=xyz(h);previousMask=oldCoverage[i];previousCount=h.w;validWeight=h.w>=1?1.0f:0.0f;}
      else {
        float3 q=xyz(g)-cameraOrigin(state[13],state[14]);float depth=dot3(q,cameraForward());
        float u=(q.x/(depth*0.4f*(float(width)/float(height)))*0.5f+0.5f)*float(width)-0.5f;
        float v=(0.5f-dot3(q,cameraUp())/(depth*0.8f))*float(height)-0.5f;
        int px=int(floorf(u));int py=int(floorf(v));float fx=fractf(u);float fy=fractf(v);
        // Bilinear reprojection avoids snapping history between screen pixels.
        // Depth/normal validation excludes newly exposed background surfaces.
        for(int yy=0;yy<2;yy++)for(int xx=0;xx<2;xx++){
          int hx=px+xx;int hy=py+yy;if(depth<=0||hx<0||hy<0||hx>=width||hy>=height)continue;int j=hy*width+hx;
          float4 og=oldGuide[j];float4 on=oldNormals[j];float4 h=oldImage[j];
          float distance=len3(xyz(og)-xyz(g));float normal=dot3(xyz(n),xyz(on));
          if(h.w<1||distance>0.08f+n.w*0.01f||(g.w!=og.w&&normal<0.65f))continue;
          float w=(xx==0?1-fx:fx)*(yy==0?1-fy:fy);previous+=xyz(h)*w;previousMask+=oldCoverage[j]*w;previousCount+=h.w*w;validWeight+=w;
        }
        if(validWeight>0){previous/=validWeight;previousMask/=validWeight;previousCount/=validWeight;}
      }
      if(validWeight>0.2f){
        if(cameraMotion>=0.000001f){
          float3 lo=colour;float3 hi=colour;
          for(int yy=-1;yy<=1;yy++)for(int xx=-1;xx<=1;xx++){
            int px=x+xx;int py=y+yy;if(px<0||py<0||px>=width||py>=height)continue;
            float3 c=xyz(source[py*width+px]);lo=min3(lo,c);hi=max3(hi,c);
          }
          float3 margin=(hi-lo)*0.08f+v3(0.002f,0.002f,0.002f);previous=max3(lo-margin,min3(hi+margin,previous));
        }
        float cap=frozen!=0?128.0f:(g.w==-2?6.0f:12.0f);if(cameraMotion>=0.000001f)cap=8;
        samples=fminf(previousCount+1,cap);colour=mix3(previous,colour,1/samples);mask=previousMask+(mask-previousMask)/samples;
      }
    }
    coverage[i]=mask;
  }
  filtered[i]=v4(colour,samples);
}
__device__ float film(float v){v=fmaxf(0,v);return sat(v*(2.51f*v+0.03f)/(v*(2.43f*v+0.59f)+0.14f));}
__global__ void resolveImage(const float4* source,unsigned int* pixels,int width,int height,float exposure,int bgra){
  int x=int(blockIdx.x*blockDim.x+threadIdx.x);int y=int(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int i=y*width+x;
  float3 c=xyz(source[i])*exposure;c=v3(powf(film(c.x),1.0f/2.2f),powf(film(c.y),1.0f/2.2f),powf(film(c.z),1.0f/2.2f));
  unsigned int r=(unsigned int)(c.x*255+0.5f);unsigned int g=(unsigned int)(c.y*255+0.5f);unsigned int b=(unsigned int)(c.z*255+0.5f);
  pixels[i]=bgra!=0?(b|(g<<8)|(r<<16)|4278190080u):(r|(g<<8)|(b<<16)|4278190080u);
}
