#include <windows.h>
#include <stdio.h>
static void *fd(void){ return (void*)__readgsqword(0x20); }
static DWORD WINAPI th(void *p){ printf("thread: FiberData=%p IsThreadAFiber=%d\n", fd(), IsThreadAFiber()); return 0; }
int main(void){
  setvbuf(stdout,0,_IONBF,0);
  printf("main: FiberData=%p IsThreadAFiber=%d\n", fd(), IsThreadAFiber());
  HANDLE h=CreateThread(0,0,th,0,0,0); WaitForSingleObject(h,INFINITE);
  void *f=ConvertThreadToFiber(0); printf("after convert: %p FiberData=%p\n", f, fd());
  return 0; }
