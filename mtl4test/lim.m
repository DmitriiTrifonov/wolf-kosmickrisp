#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc,char**argv){ @autoreleasepool {
  unsigned long sz = strtoul(argv[1],0,0);
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  printf("recommendedMaxWorkingSetSize=%.1f GB\n", dev.recommendedMaxWorkingSetSize/1e9);
  NSMutableArray *a=[NSMutableArray new]; unsigned long total=0; int n=0;
  for(;;){ MTLHeapDescriptor *hd=[MTLHeapDescriptor new]; hd.size=sz; hd.type=MTLHeapTypePlacement; hd.storageMode=MTLStorageModeShared; hd.hazardTrackingMode=MTLHazardTrackingModeUntracked;
    id<MTLHeap> h=[dev newHeapWithDescriptor:hd]; [hd release]; if(!h) break; [a addObject:h]; [h release]; total+=sz; n++; if(total > (20UL<<30)) break; }
  printf("heap size %lu KB: got %d heaps, %.2f GB before failure\n", sz>>10, n, total/1073741824.0);
}}
