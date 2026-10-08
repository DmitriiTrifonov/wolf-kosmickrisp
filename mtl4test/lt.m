#import <Metal/Metal.h>
#include <stdio.h>
#include <unistd.h>
static void fp(const char *t){ char c[200]; snprintf(c,sizeof c,"footprint %d 2>/dev/null | grep -E 'IOAccelerator \\(graphics\\)' | awk '{print \"%s\", $1$2, $5}'",getpid(),t); system(c); }
int main(void){ @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  id<MTLBuffer> buf=[dev newBufferWithLength:64<<20 options:MTLResourceStorageModeShared];
  memset(buf.contents,1,64<<20);
  fp("start");
  NSMutableArray *a=[NSMutableArray new];
  for(int i=0;i<3000;i++){ MTLTextureDescriptor *d=[MTLTextureDescriptor textureBufferDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:65536 resourceOptions:MTLResourceStorageModeShared usage:MTLTextureUsageShaderRead];
    id<MTLTexture> t=[buf newTextureWithDescriptor:d offset:(i%2000)*16384 bytesPerRow:65536*16]; [a addObject:t]; [t release]; }
  fp("3000_linear");
}}
