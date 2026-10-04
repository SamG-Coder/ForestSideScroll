__global__ void initGame(float* state,int mode){
  for(int i=0;i<32;i++)state[i]=0;
  state[0]=-4;state[2]=19.82f;state[1]=groundHeight(state[0],state[2],0);
  state[6]=1;state[9]=float(mode);state[10]=15.4f;
  state[19]=76;
  state[11]=state[0];state[12]=state[2];state[13]=state[0];state[14]=state[2];
}
__global__ void stepGame(float* state,float dt,float inputX,float inputZ,int sprint,int interact,int paused,float clockRate,float setHour){
  state[13]=state[11];state[14]=state[12];state[18]=0;
  if(setHour>=0)state[10]=setHour;
  if(paused!=0)return;
  float t=clampf(dt,0,0.1f);int loc=int(state[7]);
  float ix=inputX;float iz=inputZ;float il=sqrtf(ix*ix+iz*iz);if(il>1){ix/=il;iz/=il;}
  float speed=sprint!=0?3.8f:2.3f;float response=1-expf(-t*(il>0?13.5f:16.5f));
  state[3]=mixf(state[3],ix*speed,response);state[4]=mixf(state[4],iz*speed,response);
  if(fabsf(state[3])<0.005f)state[3]=0;if(fabsf(state[4])<0.005f)state[4]=0;
  float oldX=state[0];float oldZ=state[2];
  state[0]=clampf(state[0]+state[3]*t,-96,96);
  state[2]=clampf(state[2]+state[4]*t,loc==0?16.2f:16.4f,loc==0?24.4f:24.8f);
  state[1]=groundHeight(state[0],state[2],loc);
  state[5]+=sqrtf((state[0]-oldX)*(state[0]-oldX)+(state[2]-oldZ)*(state[2]-oldZ));
  if(fabsf(state[3])>0.03f)state[6]=state[3]>0?1:-1;
  state[15]+=t;state[10]=fractf((state[10]+t*clockRate)/24.0f)*24.0f;
  int mask=int(state[8]);
  float tx=loc==0?72.0f:70.0f;float tz=loc==0?19.72f:20.15f;
  float distance=sqrtf((state[0]-tx)*(state[0]-tx)+(state[2]-tz)*(state[2]-tz));state[19]=distance;
  if(int(state[9])==1){
    if(distance<=5&&(loc==0||(mask&1)!=0)){mask|=loc==0?1:2;state[8]=float(mask);}
    if(interact!=0&&loc==0&&state[0]>=91.2f&&(mask&1)!=0){
      state[7]=1;state[0]=-89;state[2]=20.92f;state[16]=1;state[18]=1;
    } else if(interact!=0&&loc==1&&state[0]<=-91.2f&&(mask&2)!=0){
      state[7]=0;state[0]=89;state[2]=19.28f;state[6]=-1;state[17]=1;state[18]=1;
    }
  }
  if(state[18]>0){state[3]=0;state[4]=0;state[1]=groundHeight(state[0],state[2],int(state[7]));state[11]=state[0];state[12]=state[2];state[13]=state[0];state[14]=state[2];}
  state[11]=mixf(state[11],state[0]+state[3]*0.16f,1-expf(-t*6.4f));
  state[12]=mixf(state[12],state[2]+state[4]*0.12f,1-expf(-t*6.4f));
}
