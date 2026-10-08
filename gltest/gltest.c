#include <windows.h>
#include <stdio.h>
#include <GL/gl.h>
typedef HGLRC (WINAPI *PFNCCA)(HDC, HGLRC, const int *);
#define WGL_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB 0x2092
#define WGL_CONTEXT_PROFILE_MASK_ARB 0x9126
#define WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB 0x2
int main(void){
  setvbuf(stdout,0,_IONBF,0);
  printf("start\n");
  HWND w=CreateWindowA("STATIC","t",WS_OVERLAPPEDWINDOW,0,0,320,240,0,0,0,0);
  HDC dc=GetDC(w);
  PIXELFORMATDESCRIPTOR pfd={sizeof pfd,1,PFD_DRAW_TO_WINDOW|PFD_SUPPORT_OPENGL|PFD_DOUBLEBUFFER,PFD_TYPE_RGBA,32,0,0,0,0,0,0,8,0,0,0,0,0,0,24,8};
  int pf=ChoosePixelFormat(dc,&pfd); printf("ChoosePixelFormat=%d\n",pf);
  printf("SetPixelFormat=%d\n",SetPixelFormat(dc,pf,&pfd));
  HGLRC rc=wglCreateContext(dc); printf("wglCreateContext=%p err=%lu\n",rc,GetLastError());
  if(!rc) return 1;
  printf("MakeCurrent=%d\n",wglMakeCurrent(dc,rc));
  printf("VENDOR=%s\nRENDERER=%s\nVERSION=%s\n",glGetString(GL_VENDOR),glGetString(GL_RENDERER),glGetString(GL_VERSION));
  PFNCCA cca=(PFNCCA)wglGetProcAddress("wglCreateContextAttribsARB");
  int a[]={WGL_CONTEXT_MAJOR_VERSION_ARB,3,WGL_CONTEXT_MINOR_VERSION_ARB,2,WGL_CONTEXT_PROFILE_MASK_ARB,WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB,0};
  HGLRC rc2=cca?cca(dc,0,a):0; printf("CreateContextAttribs 3.2 compat=%p err=0x%lx\n",rc2,GetLastError());
  if(rc2){wglMakeCurrent(dc,rc2); printf("VERSION2=%s\n",glGetString(GL_VERSION));}
  printf("done\n"); return 0;}
