// Primitive record: a = centre or capsule start/radius; b = ellipsoid radii or end;
// c = linear albedo / material; d = ellipsoid long axis / shape (0 ellipsoid, 1 capsule).
// Materials: 1 gum bark, 2 gum leaf, 3 undergrowth/litter, 4 sandstone, 8 fern pinna.
__device__ void ellipsoid(float4* objects,int id,float3 centre,float3 radii,float3 axis,float3 colour,int mat){
  objects[id*4]=v4(centre,0);objects[id*4+1]=v4(radii,(mat==2||mat==3)?rnd((unsigned int)(id)*17171u)*TAU:0.0f);
  objects[id*4+2]=v4(colour,float(mat));objects[id*4+3]=v4(unit(axis),0);
}
__device__ void capsule(float4* objects,int id,float3 a,float3 b,float r,float3 colour,int mat){
  objects[id*4]=v4(a,r);objects[id*4+1]=v4(b,r);
  objects[id*4+2]=v4(colour,float(mat));objects[id*4+3]=make_float4(0,1,0,1);
}
__device__ void taper(float4* objects,int id,float3 a,float3 b,float r0,float r1,float3 colour){capsule(objects,id,a,b,r0,colour,1);objects[id*4+1]=v4(b,r1);}
// Four growth architectures with different branching and crown proportions.
// 0: tall smooth-barked gum; 1: old spreading gum; 2: narrow young gum; 3: forked ironbark.
__device__ int treeForm(unsigned int seed){return int(rnd(seed+89u)*4.0f);}
__device__ float3 trunkPoint(float3 root,float height,float lean,float phase,float t){
  return root+v3(lean*t+sinf(t*5.0f+phase)*0.67f*t,height*t,cosf(t*3.4f+phase)*0.87f*t);
}
__device__ float3 limbPoint(float3 root,float h,float lean,float phase,int branch,float t,unsigned int seed){
  int form=treeForm(seed);int group=branch/3;int fork=branch-group*3;
  float mainAngle=float(group)*2.399963f+phase;
  float angle=mainAngle+(float(fork)-1)*0.68f;
  float attach=0.24f+float(group)*0.10f;
  if(form==0)attach=0.48f+float(branch)*0.029f;
  if(form==2)attach=0.48f+float(branch)*0.036f;
  if(form==3){group=branch/4;mainAngle=float(group)*2.14f+phase;angle=mainAngle+float(branch%4-1)*0.50f;attach=0.15f+float(group)*0.12f;}
  float3 start=trunkPoint(root,h,lean,phase,attach);
  float spread=(0.24f+rnd(seed+(unsigned int)(branch)*67u)*0.19f)*h;
  if(form==0)spread*=0.68f;if(form==1)spread*=1.15f;if(form==2)spread*=0.43f;if(form==3)spread*=0.79f;
  float endHeight=0.69f+rnd(seed+(unsigned int)(branch)*313u)*0.32f;
  if(form==0)endHeight=0.76f+rnd(seed+(unsigned int)(branch)*313u)*0.27f;
  if(form==2)endHeight=attach+0.17f;
  endHeight=fmaxf(endHeight,attach+0.27f);
  float3 end=trunkPoint(root,h,lean,phase,endHeight)+v3(cosf(angle)*spread,0,sinf(angle)*spread*0.72f);
  float3 junction=trunkPoint(root,h,lean,phase,attach+(form==1?0.12f:0.18f))+v3(cosf(mainAngle)*spread*0.42f,0,sinf(mainAngle)*spread*0.31f);
  float3 p;
  if(t<0.45f){float u=t/0.45f;float3 control=start+v3(cosf(mainAngle)*spread*0.08f,h*0.13f,sinf(mainAngle)*spread*0.06f);p=start*((1-u)*(1-u))+control*(2*u*(1-u))+junction*(u*u);}
  else {float u=(t-0.45f)/0.55f;float3 control=mix3(junction,end,0.60f);control.y=mixf(junction.y,end.y,0.35f);p=junction*((1-u)*(1-u))+control*(2*u*(1-u))+end*(u*u);}
  p.x+=sinf(t*PI)*sinf(mainAngle)*0.10f;return p;
}
__device__ float3 twigPoint(float3 root,float h,float lean,float phase,int branch,int twig,float t,unsigned int seed){
  float3 start=limbPoint(root,h,lean,phase,branch,0.60f+float(twig)*0.050f,seed);
  float angle=float(branch)*2.399963f+phase+float(twig)*1.83f;
  float length=h*(0.10f+0.06f*rnd(seed+(unsigned int)(branch*71+twig)*11u));
  if(treeForm(seed)==2)length*=0.57f;
  return start+v3(cosf(angle)*length,sinf(float(twig)*2.7f)*length*0.32f+length*0.33f,sinf(angle)*length*0.76f)*t;
}
__device__ void backgroundTree(float4* objects,int id,int location,unsigned int masterSeed){
  int index=(id-FOREGROUND_OBJECTS)/512;int slot=(id-FOREGROUND_OBJECTS)-index*512;
  int col=index/8;int row=index-col*8;
  unsigned int seed=hashU((unsigned int)(index)*9973u+masterSeed+(unsigned int)(location)*31033u+71471u);
  int form=treeForm(seed);
  float x=(float(col)-31.5f)*4.0f+(rnd(seed+1u)-0.5f)*3.3f;
  float z=33.0f+float(row)*8.3f+(rnd(seed+2u)-0.5f)*5.7f;
  float height=12.0f+rnd(seed+3u)*13.0f;
  if(form==2)height*=0.71f;
  float phase=rnd(seed+4u)*TAU;float lean=(rnd(seed+5u)-0.5f)*(form==1?5.5f:3.0f);
  float3 root=v3(x,groundHeight(x,z,location)-0.10f,z);
  float radius=(0.10f+height*0.009f)*(form==2?0.57f:1.0f);
  float3 bark=mix3(v3(0.28f,0.24f,0.16f),v3(0.61f,0.59f,0.47f),rnd(seed+6u));
  if(form==3)bark*=0.50f;
  float3 green=mix3(v3(0.19f,0.22f,0.090f),v3(0.35f,0.34f,0.155f),rnd(seed+7u));
  if(slot<16){float a=float(slot)/16;float b=float(slot+1)/16;float top=form==1||form==3?0.69f:0.94f;
    taper(objects,id,trunkPoint(root,height,lean,phase,a*top),trunkPoint(root,height,lean,phase,b*top),radius*powf(1-a,0.80f)+0.010f,radius*powf(1-b,0.80f)+0.010f,bark);
  }else if(slot<48){int branch=(slot-16)/4;int seg=(slot-16)-branch*4;float a=float(seg)/4;float b=float(seg+1)/4;
    taper(objects,id,limbPoint(root,height,lean,phase,branch,a,seed),limbPoint(root,height,lean,phase,branch,b,seed),radius*(0.6f-0.5f*a),radius*(0.6f-0.5f*b),bark);
  }else if(slot<80){int branch=(slot-48)/4;int twig=(slot-48)-branch*4;
    taper(objects,id,twigPoint(root,height,lean,phase,branch,twig*2,0,seed),twigPoint(root,height,lean,phase,branch,twig*2,1,seed),0.024f,0.010f,bark);
  }else{int n=slot-80;int branch=n/54;int twig=(n-branch*54)/14;
    unsigned int ls=hashU(seed+(unsigned int)(n)*881u);float t=0.38f+rnd(ls+9u)*0.77f;
    float3 p=twigPoint(root,height,lean,phase,branch,twig*2,t,seed);
    float angle=rnd(ls+1u)*TAU;float length=(0.21f+rnd(ls+2u)*0.28f)*(1.0f+float(row)*0.08f);
    float3 axis=unit(v3(cosf(angle)*0.5f,-0.45f-rnd(ls+3u)*0.65f,sinf(angle)*0.5f));
    p+=v3((rnd(ls+4u)-0.5f)*1.45f,(rnd(ls+5u)-0.5f)*0.85f,(rnd(ls+6u)-0.5f)*1.45f);
    // Larger distant leaf clusters retain broken, overlapping crowns in the side view.
    ellipsoid(objects,id,p,v3(length*0.26f,length,0.015f),axis,green*(0.67f+rnd(ls+7u)*0.48f),2);
  }
}
__device__ float3 fernCurve(float3 root,float angle,float length,float t){
  return root+v3(cosf(angle)*length*t,length*(2.0f*t-1.55f*t*t)+0.035f,sinf(angle)*length*t);
}
__device__ void undergrowth(float4* objects,int id,int slot,float cellX,int row,int loc,unsigned int seed){
  if(slot<288){
    int plant=slot/144;int part=slot-plant*144;int frond=part/24;int pinna=part-frond*24;
    unsigned int fs=hashU(seed+881u+(unsigned int)(plant)*3719u);
    float fx=cellX+(rnd(fs)-0.5f)*6.7f;float fz=shore(fx,loc)+3.1f+rnd(fs+1u)*5.0f;
    if(row>0)fz=20.7f+float(row-1)*4.5f+rnd(fs+1u)*3.7f;
    float3 root=v3(fx,groundHeight(fx,fz,loc),fz);
    float length=(0.85f+rnd(fs+2u)*0.80f)*(0.79f+rnd(fs+(unsigned int)(frond)*53u)*0.30f);
    float angle=float(frond)*2.399963f+rnd(fs+3u)*TAU;float3 direction=v3(cosf(angle),0,sinf(angle));
    float3 side=v3(-sinf(angle),0,cosf(angle));float3 green=mix3(v3(0.065f,0.16f,0.030f),v3(0.19f,0.30f,0.064f),rnd(fs+4u));
    if(pinna<4){float a=float(pinna)*0.25f;float b=float(pinna+1)*0.25f;capsule(objects,id,fernCurve(root,angle,length,a),fernCurve(root,angle,length,b),0.008f*(1-a)+0.002f,green*0.65f,3);}
    else {
      int pair=(pinna-4)/2;float sign=(pinna%2)==0?1.0f:-1.0f;float t=0.16f+float(pair)*0.084f;
      float leafLength=length*(0.075f+0.18f*powf(sinf(t*PI),0.7f))*(1-t*0.52f);
      float3 axis=unit(side*sign+direction*0.42f+v3(0,0.18f-t*0.36f,0));
      float3 p=fernCurve(root,angle,length,t)+axis*leafLength*0.71f;
      ellipsoid(objects,id,p,v3(leafLength*(plant==0?0.21f:0.31f),leafLength,0.005f),axis,green*(0.8f+0.26f*rnd(fs+(unsigned int)(part)*113u)),8);
    }
  }else if(slot<352){
    int patch=(slot-288)/16;int blade=((slot-288)%16)/2;int segment=slot%2;
    unsigned int ps=hashU(seed+(unsigned int)(patch)*7121u+51u);int kind=int(rnd(ps+8u)*3.0f);
    float px=cellX+(rnd(ps)-0.5f)*8.0f;float pz=shore(px,loc)+2.4f+rnd(ps+1u)*6.8f;
    if(row>0)pz=23.0f+float(row)*4.0f+rnd(ps+1u)*5;
    float h=0.42f+rnd(ps+2u)*0.66f;float angle=float(blade)*2.399963f+rnd(ps+3u)*TAU;
    float3 root=v3(px,groundHeight(px,pz,loc),pz);float spread=kind==0?0.7f:kind==1?0.31f:0.55f;
    float a=float(segment)*0.5f;float b=float(segment+1)*0.5f;
    float3 pa=root+v3(cosf(angle)*h*a*a*spread,h*a*(1-a*0.26f),sinf(angle)*h*a*a*spread);
    float3 pb=root+v3(cosf(angle)*h*b*b*spread,h*b*(1-b*0.26f),sinf(angle)*h*b*b*spread);
    float3 colour=mix3(v3(0.15f,0.22f,0.055f),v3(0.39f,0.30f,0.12f),rnd(ps+4u));
    if(kind==2&&segment==1&&blade%2==0){capsule(objects,id,pa,pb,0.025f,v3(0.43f,0.31f,0.055f),3);}
    else ellipsoid(objects,id,(pa+pb)*0.5f,v3(kind==1?0.014f:0.025f,len3(pb-pa)*0.58f,0.004f),unit(pb-pa),colour,3);
  }else if(slot<368){
    unsigned int rs=hashU(seed+(unsigned int)(slot)*3149u);float rx=cellX+(rnd(rs)-0.5f)*8;
    float rz=shore(rx,loc)+(rnd(rs+1u)-0.30f)*8.0f;if(row>0)rz=34.0f+float(row)*7.0f+rnd(rs+1u)*28;
    float size=0.10f+powf(rnd(rs+2u),4.0f)*0.95f;
    // Distinct geological forms: bedding slabs, tapered wedges, fractured blocks,
    // and long splinters. Their cutting planes are cached separately for tracing.
    int form=int(rnd(rs+10u)*4.0f);float3 radii=v3(size,size*0.60f,size*0.77f);
    if(form==0)radii=v3(size*(1.35f+rnd(rs+11u)*0.45f),size*(0.20f+rnd(rs+3u)*0.12f),size*(0.69f+rnd(rs+7u)*0.45f));
    if(form==1)radii=v3(size*(1.15f+rnd(rs+11u)*0.35f),size*(0.48f+rnd(rs+3u)*0.30f),size*(0.48f+rnd(rs+7u)*0.35f));
    if(form==2)radii=v3(size*(0.88f+rnd(rs+11u)*0.32f),size*(0.63f+rnd(rs+3u)*0.40f),size*(0.72f+rnd(rs+7u)*0.37f));
    if(form==3)radii=v3(size*(1.55f+rnd(rs+11u)*0.50f),size*(0.31f+rnd(rs+3u)*0.32f),size*(0.34f+rnd(rs+7u)*0.26f));
    float3 axis=unit(v3((rnd(rs+5u)-0.5f)*0.53f,1,(rnd(rs+6u)-0.5f)*0.43f));
    // Embed the bedding into the bank, so broad slabs meet the sloping soil.
    ellipsoid(objects,id,v3(rx,groundHeight(rx,rz,loc)-radii.y*0.14f,rz),radii,axis,v3(0.43f,0.33f,0.22f)*(0.76f+0.5f*rnd(rs+4u)),4);
    objects[id*4].w=float(form);
    objects[id*4+1].w=rnd(rs+9u)*TAU;
  }else{
    unsigned int bs=hashU(seed+(unsigned int)(slot)*1669u);float lx=cellX+(rnd(bs)-0.5f)*8;float lz=shore(lx,loc)+3.0f+rnd(bs+1u)*8.0f;
    float angle=rnd(bs+2u)*TAU;float3 p=v3(lx,groundHeight(lx,lz,loc)+0.017f,lz);
    ellipsoid(objects,id,p,v3(0.028f,0.11f+rnd(bs+3u)*0.13f,0.005f),unit(v3(cosf(angle),0.04f,sinf(angle))),v3(0.19f,0.11f,0.045f)*(0.6f+rnd(bs+4u)),3);
  }
}
__global__ void generateScene(float4* objects,int location,unsigned int masterSeed){
  int id=int(blockIdx.x*blockDim.x+threadIdx.x);if(id>=OBJECTS)return;
  if(id>=FOREGROUND_OBJECTS){backgroundTree(objects,id,location,masterSeed);return;}
  int cell=id/PER_CELL;int slot=id-cell*PER_CELL;int col=cell/4;int row=cell-col*4;
  unsigned int seed=hashU((unsigned int)(cell)*7213u+masterSeed+(unsigned int)(location)*7919u);
  int form=treeForm(seed);
  float cellX=(float(col)-15.5f)*8.0f;
  float x=cellX+(rnd(seed+1u)-0.5f)*5.6f;
  float z=27.2f+float(row)*10.5f+(rnd(seed+2u)-0.5f)*6.5f;
  if(row>=2)z+=float(row-1)*9.0f;
  float3 root=v3(x,groundHeight(x,z,location)-0.08f,z);
  float height=11.0f+rnd(seed+3u)*10.0f+float(row)*0.5f;
  if(form==0)height*=1.12f;if(form==1)height*=0.85f;if(form==2)height*=0.65f;
  float phase=rnd(seed+4u)*TAU;float lean=(rnd(seed+5u)-0.5f)*(form==1?5.6f:2.3f);
  float trunkRadius=(0.16f+height*0.015f)*(form==1?1.45f:form==2?0.44f:1.0f);
  float3 bark=mix3(v3(0.32f,0.27f,0.20f),v3(0.61f,0.58f,0.49f),rnd(seed+6u));
  if(rnd(seed+8u)<0.22f)bark=v3(0.33f,0.19f,0.10f);
  if(form==3)bark*=0.46f;
  float3 green=mix3(v3(0.13f,0.17f,0.071f),v3(0.28f,0.30f,0.14f),rnd(seed+7u));
  if(form==2)green=mix3(green,v3(0.25f,0.31f,0.21f),0.6f);
  if(slot<24){
    float a=float(slot)/24.0f;float b=float(slot+1)/24.0f;
    float top=form==1||form==3?0.70f:0.94f;
    taper(objects,id,trunkPoint(root,height,lean,phase,a*top),trunkPoint(root,height,lean,phase,b*top),trunkRadius*powf(1-a,0.8f)+0.016f,trunkRadius*powf(1-b,0.8f)+0.016f,bark);
  } else if(slot<96){
    int branch=(slot-24)/6;int seg=(slot-24)-branch*6;float a=float(seg)/6.0f;float b=float(seg+1)/6.0f;
    taper(objects,id,limbPoint(root,height,lean,phase,branch,a,seed),limbPoint(root,height,lean,phase,branch,b,seed),trunkRadius*(0.55f-0.45f*a)*(1.0f-float(branch)*0.020f),trunkRadius*(0.55f-0.45f*b)*(1.0f-float(branch)*0.020f),bark);
  } else if(slot<288){
    int branch=(slot-96)/16;int twig=((slot-96)-branch*16)/2;int seg=(slot-96)-branch*16-twig*2;
    taper(objects,id,twigPoint(root,height,lean,phase,branch,twig,float(seg)*0.5f,seed),twigPoint(root,height,lean,phase,branch,twig,float(seg+1)*0.5f,seed),(0.026f+height*0.0011f)*(seg==0?1.0f:0.6f),(0.026f+height*0.0011f)*(seg==0?0.6f:0.2f),bark*0.8f);
  } else if(slot<1632){
    int n=slot-288;int branch=n/112;int twig=(n-branch*112)/16;
    unsigned int ls=hashU(seed+(unsigned int)(n)*3719u);
    float t=0.5f+rnd(ls+9u)*0.55f;
    float3 centre=twigPoint(root,height,lean,phase,branch,twig,t,seed);
    float a=rnd(ls+1u)*TAU;float length=0.12f+rnd(ls+2u)*0.17f;
    float3 axis=unit(v3(cosf(a)*0.45f,-0.60f-rnd(ls+3u)*0.40f,sinf(a)*0.40f));
    centre+=axis*length*0.65f+v3((rnd(ls+4u)-0.5f)*1.05f,(rnd(ls+8u)-0.5f)*0.55f,(rnd(ls+5u)-0.5f)*1.05f);
    ellipsoid(objects,id,centre,v3(length*0.16f,length,0.007f),axis,green*(0.65f+rnd(ls+6u)*0.55f),2);
  } else undergrowth(objects,id,slot-1632,cellX,row,location,seed);
}

__device__ unsigned int spreadBits(unsigned int n){
  unsigned int x=n&1023u;x=(x|(x<<16))&50331903u;x=(x|(x<<8))&50393103u;x=(x|(x<<4))&51130563u;x=(x|(x<<2))&153391689u;return x;
}
__global__ void spatialKeys(const float4* objects,unsigned int* keys,unsigned int* order){
  int id=int(blockIdx.x*blockDim.x+threadIdx.x);if(id>=OBJECTS)return;
  float3 p=xyz(objects[id*4]);if(objects[id*4+3].w>0.5f)p=(p+xyz(objects[id*4+1]))*0.5f;
  float3 q=(p+v3(144,8,16))*(1023.0f/288.0f);
  keys[id]=spreadBits((unsigned int)(clampf(q.x,0,1023)))|(spreadBits((unsigned int)(clampf(q.y,0,1023)))<<1)|(spreadBits((unsigned int)(clampf(q.z,0,1023)))<<2);order[id]=(unsigned int)(id);
}
__global__ void buildLeaves(const float4* objects,const unsigned int* order,float4* bounds){
  int rank=int(blockIdx.x*blockDim.x+threadIdx.x);if(rank>=OBJECTS)return;int id=int(order[rank]);
  float4 a=objects[id*4];float4 b=objects[id*4+1];float4 d=objects[id*4+3];
  float3 lo;float3 hi;
  if(d.w>0.5f){float3 r=v3(a.w,a.w,a.w);lo=min3(xyz(a),xyz(b))-r;hi=max3(xyz(a),xyz(b))+r;}
  else {float3 ax=xyz(d);float3 u=basisU(ax,b.w);float3 v=cross3(ax,u);float3 extent=abs3(u)*b.x+abs3(ax)*b.y+abs3(v)*b.z;lo=xyz(a)-extent;hi=xyz(a)+extent;}
  if(int(objects[id*4+2].w)==2||int(objects[id*4+2].w)==8){lo-=v3(0.10f,0.02f,0.06f);hi+=v3(0.10f,0.02f,0.06f);}
  int node=OBJECTS+rank;bounds[node*2]=v4(lo,float(id));bounds[node*2+1]=v4(hi,0);
}
__global__ void buildLevel(float4* bounds,int start,int count){
  int i=int(blockIdx.x*blockDim.x+threadIdx.x);if(i>=count)return;int n=start+i;
  bounds[n*2]=v4(min3(xyz(bounds[n*4]),xyz(bounds[n*4+2])),0);
  bounds[n*2+1]=v4(max3(xyz(bounds[n*4+1]),xyz(bounds[n*4+3])),0);
}

// Store transforms in the same Morton order as the BVH leaves, keeping the
// records visited by neighbouring rays together in memory.
__global__ void prepareRayGeometry(const float4* objects,const unsigned int* order,float4* rayGeometry){
  int rank=int(blockIdx.x*blockDim.x+threadIdx.x);if(rank>=OBJECTS)return;int id=int(order[rank]);
  float4 a=objects[id*4];float4 b=objects[id*4+1];float4 d=objects[id*4+3];int mat=int(objects[id*4+2].w);
  rayGeometry[rank*4]=a;
  if(d.w>0.5f){float3 ba=xyz(b)-xyz(a);float length=len3(ba);rayGeometry[rank*4+1]=b;rayGeometry[rank*4+2]=v4(ba/fmaxf(length,1e-8f),length);rayGeometry[rank*4+3]=make_float4((b.w-a.w)/fmaxf(length,1e-8f),0,0,float(mat+16));}
  else{float3 axis=xyz(d);float3 u=basisU(axis,b.w);float3 v=cross3(axis,u);rayGeometry[rank*4+1]=v4(u/b.x,0);rayGeometry[rank*4+2]=v4(axis/b.y,0);rayGeometry[rank*4+3]=v4(v/b.z,float(mat));}
}
__global__ void updateLeafMotion(const float4* objects,const unsigned int* order,float4* rayGeometry,float time){
  int rank=int(blockIdx.x*blockDim.x+threadIdx.x);if(rank>=OBJECTS)return;int id=int(order[rank]);int mat=int(objects[id*4+2].w);
  if(mat==2||mat==8){float4 a=objects[id*4];rayGeometry[rank*4]=v4(xyz(a)+windOffset(xyz(a),time),a.w);}
}
__global__ void prepareRockPlanes(const float4* objects,float4* rockPlanes){
  int rock=int(blockIdx.x*blockDim.x+threadIdx.x);if(rock>=ROCK_COUNT)return;
  int id=(rock/16)*PER_CELL+1984+rock%16;int form=int(objects[id*4].w);
  unsigned int seed=hashU((unsigned int)(id)*1771u+(unsigned int)(form)*4291u);int index=0;
  for(int i=0;i<125;i++){
    int xx=i%5-2;int yy=(i/5)%5-2;int zz=i/25-2;
    if(xx>-2&&xx<2&&yy>-2&&yy<2&&zz>-2&&zz<2)continue;
    float3 n=unit(v3(float(xx),float(yy),float(zz)));float l1=fabsf(n.x)+fabsf(n.y)+fabsf(n.z);
    float distance=0.57f*l1+0.25f;
    distance+=(rnd(seed+(unsigned int)(i)*43u)-0.5f)*0.09f;
    // A skewed bedding face and unequal end cuts break bilateral symmetry.
    distance+=n.x*(rnd(seed+51u)-0.5f)*0.18f+n.z*(rnd(seed+71u)-0.5f)*0.14f;
    rockPlanes[rock*ROCK_PLANES+index]=v4(n,distance);index++;
  }
  for(int cut=0;cut<6;cut++){
    float sx=(cut&1)==0?1.0f:-1.0f;float sz=(cut&2)==0?1.0f:-1.0f;
    float3 n=unit(v3(sx*(0.48f+rnd(seed+(unsigned int)(cut)*53u)*0.44f),0.58f+rnd(seed+(unsigned int)(cut)*131u)*0.5f,sz*(0.24f+rnd(seed+(unsigned int)(cut)*71u)*0.43f)));
    float distance=0.75f+rnd(seed+(unsigned int)(cut)*29u)*0.22f;
    if(form==0){n=unit(v3(sx*0.21f,1,sz*0.12f));distance=0.68f+rnd(seed+(unsigned int)(cut)*13u)*0.16f;}
    if(form==1&&cut==0){n=unit(v3(0.73f,1,-0.17f));distance=0.46f;}
    if(form==3&&cut==0){n=unit(v3(0.60f,0.33f,1));distance=0.58f;}
    rockPlanes[rock*ROCK_PLANES+98+cut]=v4(n,distance);
  }
}
