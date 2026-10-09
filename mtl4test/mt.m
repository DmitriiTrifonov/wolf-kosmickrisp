#import <Metal/Metal.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static int has(void){ for(uint32_t i=0;i<_dyld_image_count();i++) if(strstr(_dyld_get_image_name(i),"MetalTools")) return 1; return 0; }
int main(void){ @autoreleasepool {
  id<MTLDevice> d=MTLCreateSystemDefaultDevice(); printf("after device: MetalTools=%d class=%s\n",has(),object_getClassName(d));
  (void)[MTLCaptureManager sharedCaptureManager]; printf("after capture manager: MetalTools=%d\n",has());
  id<MTLDevice> d2=MTLCreateSystemDefaultDevice(); printf("device class now=%s same=%d\n",object_getClassName(d2), d==d2);
}}
