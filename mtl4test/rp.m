// CPU cost of MTL4 render passes: one command buffer per pass (KosmicKrisp style) vs
// many render encoders in one command buffer. Empty passes, 1504x853 color+depth.
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <mach/mach_time.h>
static double now_ms(void){ static mach_timebase_info_data_t tb; if(!tb.denom) mach_timebase_info(&tb); return mach_absolute_time()*(double)tb.numer/tb.denom/1e6; }
int main(int argc,char**argv){ @autoreleasepool {
  int passes = argc>1?atoi(argv[1]):120, frames = argc>2?atoi(argv[2]):60; size_t vis = argc>3?atol(argv[3]):0;
  if (getenv("CAPMGR")) (void)[MTLCaptureManager sharedCaptureManager];
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  id<MTL4CommandQueue> q=[dev newMTL4CommandQueue];
  int NAL = getenv("NAL")?atoi(getenv("NAL")):3; id<MTL4CommandAllocator> al[4096]; for(int i=0;i<NAL;i++) al[i]=[dev newCommandAllocator]; int alc=0;
  MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1504 height:853 mipmapped:NO];
  td.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead; td.storageMode=MTLStorageModePrivate;
  id<MTLTexture> col=[dev newTextureWithDescriptor:td];
  int view = getenv("VIEW")!=NULL, ds = getenv("DS")!=NULL, ncol = getenv("NCOL")?atoi(getenv("NCOL")):1;
  td.pixelFormat = ds ? MTLPixelFormatDepth32Float_Stencil8 : MTLPixelFormatDepth32Float; id<MTLTexture> dep=[dev newTextureWithDescriptor:td];
  td.pixelFormat=MTLPixelFormatRGBA16Float; id<MTLTexture> cols[4]; for(int i=0;i<4;i++) cols[i]=[dev newTextureWithDescriptor:td];
  if (view) { col=[col newTextureViewWithPixelFormat:MTLPixelFormatBGRA8Unorm textureType:MTLTextureType2DArray levels:NSMakeRange(0,1) slices:NSMakeRange(0,1)];
              dep=[dep newTextureViewWithPixelFormat:dep.pixelFormat textureType:MTLTextureType2DArray levels:NSMakeRange(0,1) slices:NSMakeRange(0,1)]; }
  id<MTLBuffer> vb = vis ? [dev newBufferWithLength:vis options:MTLResourceStorageModeShared] : nil;
  int grow = getenv("GROW")?atoi(getenv("GROW")):0;
  for(int i=0;i<NAL && grow;i++) @autoreleasepool { id<MTL4CommandBuffer> cb=[dev newCommandBuffer]; [cb beginCommandBufferWithAllocator:al[i]]; for(int e=0;e<grow;e++){ id<MTL4ComputeCommandEncoder> en=[cb computeCommandEncoder]; [en endEncoding]; } [cb endCommandBuffer]; [cb release]; printf("allocator %d grown to %lluMB\n", i, [al[i] allocatedSize]>>20); [al[i] reset]; }
  int nres = getenv("RES")?atoi(getenv("RES")):0;
  if (nres) { MTLResidencySetDescriptor *rd=[MTLResidencySetDescriptor new]; id<MTLResidencySet> rs=[dev newResidencySetWithDescriptor:rd error:nil];
    for(int i=0;i<nres;i++){ id<MTLBuffer> b=[dev newBufferWithLength:65536 options:MTLResourceStorageModeShared]; [rs addAllocation:b]; }
    [rs addAllocation:col]; [rs addAllocation:dep]; [rs commit]; [q addResidencySet:rs]; }
  id<MTLSharedEvent> ev=[dev newSharedEvent]; uint64_t t=0;
  for (int mode=0; mode<3; mode++) {
    double cpu=0, gpu_wait=0;
    for (int f=0; f<frames; f++) @autoreleasepool {
      double t0=now_ms();
      int nb=0; id<MTL4CommandBuffer> cbs[4096];
      id<MTL4CommandBuffer> one=nil;
      if (mode==1) { one=[dev newCommandBuffer]; [one beginCommandBufferWithAllocator:al[0]]; }
      for (int p=0;p<passes;p++) {
        id<MTL4CommandBuffer> cb=one;
        if (mode!=1) { @autoreleasepool { cb=[dev newCommandBuffer]; [cb beginCommandBufferWithAllocator:al[(alc++)%NAL]]; } }
        @autoreleasepool {
          MTL4RenderPassDescriptor *rp=[MTL4RenderPassDescriptor new];
          rp.colorAttachments[0].texture=col; rp.colorAttachments[0].loadAction=MTLLoadActionLoad; rp.colorAttachments[0].storeAction=MTLStoreActionStore;
          for(int c=1;c<ncol;c++){ rp.colorAttachments[c].texture=cols[c]; rp.colorAttachments[c].loadAction=MTLLoadActionLoad; rp.colorAttachments[c].storeAction=MTLStoreActionStore; }
          if (ds) { rp.stencilAttachment.texture=dep; rp.stencilAttachment.loadAction=MTLLoadActionLoad; rp.stencilAttachment.storeAction=MTLStoreActionStore; }
          if (view) rp.renderTargetArrayLength=1;
          rp.depthAttachment.texture=dep; rp.depthAttachment.loadAction=MTLLoadActionLoad; rp.depthAttachment.storeAction=MTLStoreActionStore;
          if (vb) rp.visibilityResultBuffer=vb; rp.renderTargetWidth=1504; rp.renderTargetHeight=853;
          id<MTL4RenderCommandEncoder> en=[cb renderCommandEncoderWithDescriptor:rp];
          [en endEncoding]; [rp release];
          if (mode==2) { id<MTL4ComputeCommandEncoder> ce=[cb computeCommandEncoder]; [ce endEncoding]; }
        }
        if (mode!=1) { [cb endCommandBuffer]; cbs[nb++]=cb; }
        /* KK uses one allocator per encoder state; reuse only after the GPU is done, so
           in mode 0 we just cycle three (fine for a CPU cost measurement). */
      }
      if (mode==1) { [one endCommandBuffer]; cbs[nb++]=one; }
      if (getenv("FB")) { MTL4CommitOptions *o=[MTL4CommitOptions new]; [o addFeedbackHandler:^(id<MTL4CommitFeedback> fbk){ (void)fbk; }]; [q commit:cbs count:nb options:o]; [o release]; }
      else [q commit:cbs count:nb];
      double t1=now_ms(); cpu+=t1-t0;
      if (f==frames-1) { uint64_t tot=0; for(int i=0;i<NAL;i++) tot+=[al[i] allocatedSize]; printf("  allocators total=%lluMB\n", tot>>20); }
      [q signalEvent:ev value:++t]; [ev waitUntilSignaledValue:t timeoutMS:10000];
      gpu_wait+=now_ms()-t1;
      for(int i=0;i<nb;i++) [cbs[i] release];
      for(int i=0;i<NAL;i++) { if (getenv("FRESH")) { [al[i] release]; al[i]=[dev newCommandAllocator]; } else [al[i] reset]; }
    }
    const char *names[]={"cmdbuf-per-pass","one-cmdbuf","cmdbuf-per-pass+compute"};
    printf("%-24s passes=%d cpu=%.2fms/frame (%.1fus/pass) gpu_wait=%.2fms/frame\n", names[mode], passes, cpu/frames, cpu/frames/passes*1000, gpu_wait/frames);
  }
}}
