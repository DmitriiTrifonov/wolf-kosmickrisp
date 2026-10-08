#include <windows.h>
#include <stdio.h>
HRESULT WINAPI DirectInput8Create(HINSTANCE,DWORD,REFIID,LPVOID*,LPUNKNOWN);
static void *volatile keep;
int main(void){
  setvbuf(stdout,0,_IONBF,0);
  keep=(void*)DirectInput8Create;
  void *f=ConvertThreadToFiber((void*)0x1234);
  printf("fiber=%p GetCurrentFiber=%p GetFiberData=%p\n", f, GetCurrentFiber(), GetFiberData());
  return 0; }
