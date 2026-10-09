// Cost of a KK-style bridge call (autoreleasepool + one ObjC setter) under Rosetta
#import <Metal/Metal.h>
#include <stdio.h>
#include <mach/mach_time.h>
static double now_us(void){ static mach_timebase_info_data_t tb; if(!tb.denom) mach_timebase_info(&tb); return mach_absolute_time()*(double)tb.numer/tb.denom/1e3; }
int main(void){ @autoreleasepool {
  MTL4RenderPassDescriptor *rp=[MTL4RenderPassDescriptor new];
  int N=200000; double t0=now_us();
  for(int i=0;i<N;i++){ @autoreleasepool { MTLRenderPassColorAttachmentDescriptor *a=rp.colorAttachments[i&7]; a.loadAction=MTLLoadActionDontCare; } }
  double t1=now_us();
  for(int i=0;i<N;i++){ MTLRenderPassColorAttachmentDescriptor *a=rp.colorAttachments[i&7]; a.loadAction=MTLLoadActionDontCare; }
  double t2=now_us();
  for(int i=0;i<N/100;i++){ @autoreleasepool { MTL4RenderPassDescriptor *r=[MTL4RenderPassDescriptor new]; [r release]; } }
  double t3=now_us();
  printf("get+set with pool: %.3fus  without pool: %.3fus  new descriptor: %.2fus\n",(t1-t0)/N,(t2-t1)/N,(t3-t2)/(N/100));
}}
