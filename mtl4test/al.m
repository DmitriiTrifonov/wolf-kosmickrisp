// MTL4CommandAllocator growth: does reset shrink allocatedSize? what about uncommitted cmd buffers?
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static int regions(void){ char c[128]; snprintf(c,sizeof c,"vmmap -w %d 2>/dev/null | grep -c '^IOAccelerator (graphics)'",getpid()); FILE*f=popen(c,"r"); int n=0; fscanf(f,"%d",&n); pclose(f); return n; }
int main(int argc,char**argv){ @autoreleasepool {
  const char *mode = argc>1?argv[1]:"commit"; int encs = argc>2?atoi(argv[2]):2000;
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  id<MTL4CommandQueue> q=[dev newMTL4CommandQueue];
  id<MTL4CommandAllocator> al=[dev newCommandAllocator];
  id<MTLSharedEvent> ev=[dev newSharedEvent]; uint64_t t=0;
  for (int it=0; it<(argc>3?atoi(argv[3]):6); it++) @autoreleasepool {
    for (int c=0;c<20;c++) {
      id<MTL4CommandBuffer> cb=[dev newCommandBuffer];
      [cb beginCommandBufferWithAllocator:al];
      for (int e=0;e<encs/20;e++){ id<MTL4ComputeCommandEncoder> en=[cb computeCommandEncoder]; [en endEncoding]; }
      [cb endCommandBuffer];
      if (!strcmp(mode,"commit") || (!strcmp(mode,"some") && c%2)) { const id<MTL4CommandBuffer> a[1]={cb}; [q commit:a count:1]; }
      [cb release];
    }
    [q signalEvent:ev value:++t]; [ev waitUntilSignaledValue:t timeoutMS:5000];
    uint64_t before=[al allocatedSize]; [al reset]; uint64_t after=[al allocatedSize];
    if (it%5==0 || it>=(argc>3?atoi(argv[3]):6)-1) printf("mode=%s it=%d before_reset=%lluKB after_reset=%lluKB\n", mode, it, before>>10, after>>10);
  }
  printf("regions before allocator release=%d\n", regions());
  [al release]; sleep(1);
  printf("regions after allocator release=%d\n", regions());
}}
