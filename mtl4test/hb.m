#import <Metal/Metal.h>
#include <stdio.h>
#include <unistd.h>
static int regions(void){ char c[128]; snprintf(c,sizeof c,"vmmap -w %d 2>/dev/null | grep -c '^IOAccelerator (graphics)'",getpid()); FILE*f=popen(c,"r"); int n=0; fscanf(f,"%d",&n); pclose(f); return n; }
int main(void){ @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  MTLHeapDescriptor *hd=[MTLHeapDescriptor new]; hd.size=64<<20; hd.type=MTLHeapTypePlacement; hd.storageMode=MTLStorageModeShared; hd.hazardTrackingMode=MTLHazardTrackingModeUntracked;
  id<MTLHeap> h=[dev newHeapWithDescriptor:hd];
  printf("start regions=%d\n", regions());
  NSMutableArray *keep=[NSMutableArray new];
  for(int i=0;i<3000;i++){ id<MTLBuffer> b=[h newBufferWithLength:4096 options:MTLResourceStorageModeShared|MTLResourceHazardTrackingModeUntracked offset:(i%1000)*16384]; [keep addObject:b]; [b release]; }
  printf("3000 live heap buffers regions=%d\n", regions());
  [keep removeAllObjects];
  printf("released regions=%d\n", regions());
  NSMutableArray *tex=[NSMutableArray new];
  for(int i=0;i<3000;i++){ MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:64 height:64 mipmapped:NO]; td.storageMode=MTLStorageModeShared; td.resourceOptions=MTLResourceStorageModeShared|MTLResourceHazardTrackingModeUntracked; id<MTLTexture> t=[h newTextureWithDescriptor:td offset:(i%1000)*16384]; id<MTLTexture> v=[t newTextureViewWithPixelFormat:MTLPixelFormatBGRA8Unorm]; [tex addObject:t]; [tex addObject:v]; [t release]; [v release]; }
  printf("3000 live heap textures+views regions=%d\n", regions());
}}
