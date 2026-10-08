#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
  int reuse = argc > 1 && atoi(argv[1]);
  @autoreleasepool {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    id<MTL4CommandQueue> q = [dev newMTL4CommandQueue];
    id<MTL4CommandAllocator> alloc = [dev newCommandAllocator];
    id<MTL4CommandBuffer> keep = reuse ? [dev newCommandBuffer] : nil;
    for (int i = 0; i < 5000; i++) {
      @autoreleasepool {
        id<MTL4CommandBuffer> cb = reuse ? keep : [dev newCommandBuffer];
        [cb beginCommandBufferWithAllocator:alloc];
        id<MTL4ComputeCommandEncoder> enc = [cb computeCommandEncoder];
        [enc endEncoding];
        [cb endCommandBuffer];
        const id<MTL4CommandBuffer> list[1] = { cb };
        [q commit:list count:1];
        id<MTLSharedEvent> ev = [dev newSharedEvent];
        [q signalEvent:ev value:1];
        [ev waitUntilSignaledValue:1 timeoutMS:1000];
        if (!reuse) [cb release];
        [alloc reset];
      }
    }
    char cmd[128]; snprintf(cmd, sizeof cmd, "vmmap -w %d 2>/dev/null | grep -c '^IOAccelerator (graphics)'", getpid());
    printf("reuse=%d regions: ", reuse); fflush(stdout); system(cmd);
  }
  return 0;
}
