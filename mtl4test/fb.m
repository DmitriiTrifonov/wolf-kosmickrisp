// Does MTL4CommitFeedback report GPUStartTime/GPUEndTime?
#import <Metal/Metal.h>
#include <stdio.h>
int main(void){ @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  id<MTL4CommandQueue> q=[dev newMTL4CommandQueue];
  id<MTL4CommandAllocator> al=[dev newCommandAllocator];
  MTL4CommitOptions *opt=[MTL4CommitOptions new];
  __block int calls=0;
  [opt addFeedbackHandler:^(id<MTL4CommitFeedback> fb){ calls++; printf("feedback start=%f end=%f dur=%.3fms err=%p\n", fb.GPUStartTime, fb.GPUEndTime, (fb.GPUEndTime-fb.GPUStartTime)*1e3, fb.error); }];
  id<MTLBuffer> b=[dev newBufferWithLength:64<<20 options:MTLResourceStorageModePrivate];
  id<MTLResidencySet> set=[dev newResidencySetWithDescriptor:[MTLResidencySetDescriptor new] error:nil]; [set addAllocation:b]; [set commit]; [q addResidencySet:set];
  id<MTLSharedEvent> ev=[dev newSharedEvent];
  for (int i=0;i<3;i++){
    [al reset];
    id<MTL4CommandBuffer> cb=[dev newCommandBuffer]; [cb beginCommandBufferWithAllocator:al];
    id<MTL4ComputeCommandEncoder> e=[cb computeCommandEncoder]; for(int k=0;k<20;k++) [e fillBuffer:b range:NSMakeRange(0,64<<20) value:k]; [e endEncoding];
    [cb endCommandBuffer];
    const id<MTL4CommandBuffer> a[1]={cb};
    [q commit:a count:1 options:opt];
    [q signalEvent:ev value:i+1]; [ev waitUntilSignaledValue:i+1 timeoutMS:5000];
  }
  [NSThread sleepForTimeInterval:0.5];
  printf("calls=%d\n", calls);
}}
