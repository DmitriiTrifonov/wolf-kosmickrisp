// Heap churn: mimic KosmicKrisp kk_alloc_bo/kk_destroy_bo and see if VM regions are reclaimed.
// usage: hc <iters> <flags>  flags: s=sparsePageSize16 r=residency set q=MTL4 queue submits c=touch contents
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
static int regions(void){ char c[128]; snprintf(c,sizeof c,"vmmap -w %d 2>/dev/null | grep -c '^IOAccelerator (graphics)'",getpid()); FILE*f=popen(c,"r"); int n=0; fscanf(f,"%d",&n); pclose(f); return n; }
int main(int argc,char**argv){ @autoreleasepool {
  int iters = argc>1?atoi(argv[1]):5000; const char *fl = argc>2?argv[2]:"";
  int S=!!strchr(fl,'s'), R=!!strchr(fl,'r'), Q=!!strchr(fl,'q'), C=!!strchr(fl,'c');
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  MTLResidencySetDescriptor *rd=[[MTLResidencySetDescriptor new] autorelease]; rd.initialCapacity=100;
  id<MTLResidencySet> set=[dev newResidencySetWithDescriptor:rd error:nil];
  id<MTL4CommandQueue> q=[dev newMTL4CommandQueue];
  id<MTL4CommandAllocator> al=[dev newCommandAllocator];
  if (R) { [q addResidencySet:set]; }
  id<MTLSharedEvent> ev=[dev newSharedEvent]; uint64_t ticket=0;
  printf("flags=%s start regions=%d\n", fl, regions());
  for (int i=0;i<iters;i++) @autoreleasepool {
    MTLHeapDescriptor *hd=[[MTLHeapDescriptor new] autorelease];
    hd.type=MTLHeapTypePlacement;
    hd.resourceOptions=MTLResourceStorageModeShared|MTLResourceCPUCacheModeDefaultCache|MTLResourceHazardTrackingModeUntracked;
    hd.size=32768; if (S) hd.sparsePageSize=MTLSparsePageSize16;
    id<MTLHeap> h=[dev newHeapWithDescriptor:hd];
    id<MTLBuffer> b=[h newBufferWithLength:32768 options:hd.resourceOptions offset:0];
    if (C) memset([b contents],1,64);
    if (R) { [set addAllocation:h]; [set commit]; [set requestResidency]; }
    if (Q && (i%8)==0) {
      [al reset];
      id<MTL4CommandBuffer> cb=[dev newCommandBuffer];
      [cb beginCommandBufferWithAllocator:al];
      id<MTL4ComputeCommandEncoder> e=[cb computeCommandEncoder]; [e endEncoding];
      [cb endCommandBuffer];
      const id<MTL4CommandBuffer> cbs[1]={cb};
      [q commit:cbs count:1];
      [q signalEvent:ev value:++ticket];
      [ev waitUntilSignaledValue:ticket timeoutMS:1000];
      [cb release];
    }
    if (R) { [set removeAllocation:h]; }
    [b release]; [h release];
    if (R && (i%8)==7) [set commit];
  }
  if (R) [set commit];
  sleep(1);
  printf("flags=%s after %d heaps: regions=%d\n", fl, iters, regions());
}}
