// Paint the background first, then trees/soil, rocks, foliage and finally water.
// Coverage is accumulated with colour, not taken from a noisy primary-ray ID.
__device__ float paintCoverage(float4 mask,int layer){
  if(layer<0)return sat(1-mask.x-mask.y-mask.z-mask.w);
  if(layer==0)return sat(mask.x);if(layer==1)return sat(mask.y);if(layer==2)return sat(mask.z);return sat(mask.w);
}
__device__ float3 paintLayer(const float4* source,const float4* coverage,int x,int y,int width,int height,int layer,float depth){
  float3 colour=xyz(source[y*width+x]);float scale=fmaxf(0.75f,float(height)/600.0f);
  float reach=(0.65f+depth*1.75f)*scale;
  // Broader background strokes, flatter rock facets, fine foliage dabs, and
  // horizontal water strokes give each layer its own surface character.
  float rx=0.85f;float ry=1.10f;
  if(layer<0){rx=1.3f;ry=1.2f;}if(layer==1){rx=1.15f;ry=0.65f;}if(layer==2){rx=0.50f;ry=0.90f;}if(layer==3){rx=1.85f;ry=0.35f;}
  float3 painted=v3(0,0,0);float regionWeight=0;
  for(int region=0;region<4;region++){
    int sx=(region&1)==0?-1:1;int sy=(region&2)==0?-1:1;
    float3 sum=v3(0,0,0);float lsum=0;float squared=0;float weight=0;
    for(int yy=0;yy<3;yy++)for(int xx=0;xx<3;xx++){
      int px=x+int(floorf(float(sx*xx)*reach*rx+float(sy*yy)*reach*0.15f+0.5f));
      int py=y+int(floorf(float(sy*yy)*reach*ry+0.5f));
      if(px<0||py<0||px>=width||py>=height)continue;int j=py*width+px;
      // Brush samples stay in their own material layer at object boundaries.
      float w=paintCoverage(coverage[j],layer);if(w<0.0001f)continue;float3 c=xyz(source[j]);
      float luminance=dot3(c,v3(0.2126f,0.7152f,0.0722f));luminance=luminance/(0.12f+luminance);
      sum+=c*w;lsum+=luminance*w;squared+=luminance*luminance*w;weight+=w;
    }
    if(weight>0.0001f){float mean=lsum/weight;float variance=fmaxf(0,squared/weight-mean*mean);float score=0.006f+variance+0.014f/weight;
      float w=1.0f/(score*score);painted+=sum/weight*w;regionWeight+=w;}
  }
  painted=regionWeight>0?painted/regionWeight:colour;
  float luminance=fmaxf(0.0001f,dot3(painted,v3(0.2126f,0.7152f,0.0722f)));
  float steps=layer==2?36.0f:(layer==3?42.0f:26.0f);float level=sqrtf(luminance)*steps;
  float pigment=(floorf(level)+smoothf(0.32f,0.68f,fractf(level)))/steps;
  painted*=mixf(1.0f,pigment*pigment/luminance,0.45f);
  float u=(float(x)-float(y)*0.15f)/scale;float v=float(y)/scale;
  if(layer==3){u=float(y)/scale;v=float(x)/scale;}
  float bristle=sinf(u*2.35f+sinf(v*0.17f)*0.55f);float dab=sinf(u*0.47f+v*0.19f)*sinf(v*0.31f);
  painted*=1.0f+(0.032f*bristle+0.025f*dab)*(layer<0?0.25f:1.0f);
  return max3(painted,v3(0,0,0));
}
__global__ void paintScene(const float4* source,const float4* coverage,unsigned int* pixels,int width,int height,float exposure,int bgra,float strength,float treeDepth,float rockDepth,float foliageDepth,float waterDepth){
  int x=int(blockIdx.x*blockDim.x+threadIdx.x);int y=int(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int i=y*width+x;
  float3 colour=xyz(source[i]);float3 adjustment=v3(0,0,0);float amount=sat(strength);float4 mask=coverage[i];
  if(amount>0){
    for(int layer=-1;layer<4;layer++){
      float weight=paintCoverage(mask,layer);float depth=treeDepth;
      if(layer==1)depth=rockDepth;if(layer==2)depth=foliageDepth;if(layer==3)depth=waterDepth;
      depth=sat(depth);if(weight<0.0001f||depth<=0)continue;
      float3 painted=paintLayer(source,coverage,x,y,width,height,layer,depth);
      adjustment+=(painted-colour)*(amount*depth*weight);
    }
  }
  // Coverage-weighted composition retains actual occlusion and subpixel gaps.
  // Zero depth leaves that layer's original colour intact.
  colour+=adjustment;
  float3 c=colour*exposure;c=v3(powf(film(c.x),1.0f/2.2f),powf(film(c.y),1.0f/2.2f),powf(film(c.z),1.0f/2.2f));
  unsigned int r=(unsigned int)(c.x*255+0.5f);unsigned int g=(unsigned int)(c.y*255+0.5f);unsigned int b=(unsigned int)(c.z*255+0.5f);
  pixels[i]=bgra!=0?(b|(g<<8)|(r<<16)|4278190080u):(r|(g<<8)|(b<<16)|4278190080u);
}
