#include <windows.h>
#include <stdio.h>
int main(void){
  setvbuf(stdout,0,_IONBF,0);
  unsigned char *teb=(unsigned char*)__readgsqword(0x30);
  printf("gs:30=%p NtCurrentTeb=%p\n", teb, NtCurrentTeb());
  void *f=ConvertThreadToFiber((void*)0x1234);
  printf("fiber=%p teb->FiberData=%p GetFiberData=%p\n", f, *(void**)(teb+0x20), GetFiberData());
  return 0; }
