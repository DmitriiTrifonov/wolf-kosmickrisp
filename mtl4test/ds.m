#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static int regions(void){ char c[128]; snprintf(c,sizeof c,"vmmap -w %d 2>/dev/null | grep -c '^IOAccelerator (graphics)'",getpid()); FILE*f=popen(c,"r"); int n=0; fscanf(f,"%d",&n); pclose(f); return n; }
int main(void){
  @autoreleasepool {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    printf("start regions=%d\n", regions());
    for (int i=0;i<3000;i++) @autoreleasepool {
      MTLDepthStencilDescriptor *d=[MTLDepthStencilDescriptor new];
      d.depthWriteEnabled = i&1; d.depthCompareFunction = (MTLCompareFunction)(i%8);
      MTLStencilDescriptor *s=[MTLStencilDescriptor new]; s.readMask=i&0xff; s.writeMask=(i>>8)&0xff;
      d.frontFaceStencil=s; d.backFaceStencil=s;
      id<MTLDepthStencilState> st=[dev newDepthStencilStateWithDescriptor:d];
      [st release]; [s release]; [d release];
    }
    printf("after 3000 created+released DS states regions=%d\n", regions());
  }
  return 0; }
