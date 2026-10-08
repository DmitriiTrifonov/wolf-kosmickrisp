/*
 * fiberfix: dinput8.dll proxy that fixes inline GetCurrentFiber() on
 * Wine/CrossOver for macOS.
 *
 * MSVC inlines GetCurrentFiber() as "mov reg, gs:[0x20]". On macOS, Wine's
 * gs points at the Darwin TSD area, which only mirrors some TEB fields
 * (gs:[0x30] is the TEB self pointer) but not FiberData at 0x20, so games
 * read garbage there and crash in SwitchToFiber.
 *
 * The game's code is encrypted on disk by its DRM, so it is patched in
 * memory the first time it calls a fiber API (by then it is decrypted):
 * every "mov r64, gs:[0x20]" becomes "call stub; nop4", where the stub reads
 * NtCurrentTeb()->FiberData through gs:[0x30].
 */
#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static HMODULE real_dinput8;
static BOOL patched;
static FILE *logf;

static void log_msg(const char *fmt, ...)
{
    va_list ap;
    if (!logf)
        return;
    va_start(ap, fmt);
    vfprintf(logf, fmt, ap);
    va_end(ap);
    fflush(logf);
}

/* For each of the 16 registers: mov reg, gs:[0x30]; mov reg, [reg+0x20]; ret */
static unsigned char *make_stubs(unsigned char *near_addr)
{
    unsigned char *stubs = NULL;
    /* Must be within +-2GB of the patched code for rel32 calls. */
    for (INT64 delta = 0x10000000; delta < 0x70000000 && !stubs; delta += 0x1000000) {
        stubs = VirtualAlloc(near_addr - delta, 0x1000, MEM_RESERVE | MEM_COMMIT,
                             PAGE_EXECUTE_READWRITE);
        if (!stubs)
            stubs = VirtualAlloc(near_addr + delta, 0x1000, MEM_RESERVE | MEM_COMMIT,
                                 PAGE_EXECUTE_READWRITE);
    }
    if (!stubs)
        return NULL;

    for (int reg = 0; reg < 16; reg++) {
        unsigned char *p = stubs + reg * 16;
        unsigned char rex = reg < 8 ? 0x48 : 0x4c;
        unsigned char r = reg & 7;
        /* mov reg, gs:[0x30] */
        *p++ = 0x65; *p++ = rex; *p++ = 0x8b; *p++ = 0x04 | (r << 3); *p++ = 0x25;
        *p++ = 0x30; *p++ = 0; *p++ = 0; *p++ = 0;
        /* mov reg, [reg+0x20] (rsp/r12 base needs a SIB byte; never used for these) */
        unsigned char rex2 = 0x48 | (reg >= 8 ? 0x05 : 0);
        *p++ = rex2; *p++ = 0x8b;
        if (r == 4) { /* rsp/r12 */
            *p++ = 0x44 | (r << 3); *p++ = 0x24; *p++ = 0x20;
        } else {
            *p++ = 0x40 | (r << 3) | r; *p++ = 0x20;
        }
        *p++ = 0xc3; /* ret */
    }
    return stubs;
}

static void patch_module(HMODULE mod)
{
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)mod;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)((BYTE *)mod + dos->e_lfanew);
    IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt);
    unsigned char *stubs = make_stubs((unsigned char *)mod);
    int count = 0;

    if (!stubs) {
        log_msg("fiberfix: could not allocate stubs near %p\n", mod);
        return;
    }

    for (int i = 0; i < nt->FileHeader.NumberOfSections; i++, sec++) {
        if (!(sec->Characteristics & IMAGE_SCN_MEM_EXECUTE))
            continue;
        unsigned char *start = (unsigned char *)mod + sec->VirtualAddress;
        SIZE_T size = sec->Misc.VirtualSize;
        DWORD old;
        if (!VirtualProtect(start, size, PAGE_EXECUTE_READWRITE, &old))
            continue;
        for (SIZE_T j = 0; j + 9 <= size; j++) {
            unsigned char *p = start + j;
            /* 65 REX.W 8B /r(mod=00,rm=100) SIB=25 disp32=0x20 */
            if (p[0] != 0x65 || (p[1] != 0x48 && p[1] != 0x4c) || p[2] != 0x8b ||
                (p[3] & 0xc7) != 0x04 || p[4] != 0x25 ||
                p[5] != 0x20 || p[6] || p[7] || p[8])
                continue;
            int reg = ((p[3] >> 3) & 7) + (p[1] == 0x4c ? 8 : 0);
            INT64 rel = (stubs + reg * 16) - (p + 5);
            if (rel > INT_MAX || rel < INT_MIN)
                continue;
            p[0] = 0xe8;
            *(INT32 *)(p + 1) = (INT32)rel;
            p[5] = 0x0f; p[6] = 0x1f; p[7] = 0x40; p[8] = 0x00; /* nop dword [rax+0] */
            count++;
            j += 8;
        }
        VirtualProtect(start, size, old, &old);
    }
    FlushInstructionCache(GetCurrentProcess(), NULL, 0);
    log_msg("fiberfix: patched %d GetCurrentFiber sites in %p (stubs %p)\n", count, mod, stubs);
}

static void ensure_patched(void)
{
    if (patched)
        return;
    patched = TRUE;
    patch_module(GetModuleHandleW(NULL));
}

/* IAT hooks: patch the (by now decrypted) game code on first fiber use. */
static LPVOID (WINAPI *real_ConvertThreadToFiber)(LPVOID);
static LPVOID (WINAPI *real_CreateFiberEx)(SIZE_T, SIZE_T, DWORD, LPFIBER_START_ROUTINE, LPVOID);

static LPVOID WINAPI hook_ConvertThreadToFiber(LPVOID param)
{
    ensure_patched();
    return real_ConvertThreadToFiber(param);
}

static LPVOID WINAPI hook_CreateFiberEx(SIZE_T commit, SIZE_T reserve, DWORD flags,
                                        LPFIBER_START_ROUTINE start, LPVOID param)
{
    ensure_patched();
    return real_CreateFiberEx(commit, reserve, flags, start, param);
}

static void hook_iat(HMODULE mod)
{
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)mod;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)((BYTE *)mod + dos->e_lfanew);
    IMAGE_DATA_DIRECTORY *dir = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    IMAGE_IMPORT_DESCRIPTOR *imp = (IMAGE_IMPORT_DESCRIPTOR *)((BYTE *)mod + dir->VirtualAddress);
    HMODULE k32 = GetModuleHandleA("kernel32.dll");
    FARPROC conv = GetProcAddress(k32, "ConvertThreadToFiber");
    FARPROC create = GetProcAddress(k32, "CreateFiberEx");
    int hooked = 0;

    real_ConvertThreadToFiber = (void *)conv;
    real_CreateFiberEx = (void *)create;

    for (; dir->VirtualAddress && imp->Name; imp++) {
        IMAGE_THUNK_DATA *thunk = (IMAGE_THUNK_DATA *)((BYTE *)mod + imp->FirstThunk);
        for (; thunk->u1.Function; thunk++) {
            FARPROC *slot = (FARPROC *)&thunk->u1.Function;
            FARPROC repl = NULL;
            if (*slot == conv)
                repl = (FARPROC)hook_ConvertThreadToFiber;
            else if (*slot == create)
                repl = (FARPROC)hook_CreateFiberEx;
            if (!repl)
                continue;
            DWORD old;
            VirtualProtect(slot, sizeof(*slot), PAGE_READWRITE, &old);
            *slot = repl;
            VirtualProtect(slot, sizeof(*slot), old, &old);
            hooked++;
        }
    }
    log_msg("fiberfix: hooked %d IAT entries\n", hooked);
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    if (reason == DLL_PROCESS_ATTACH) {
        char path[MAX_PATH];
        DisableThreadLibraryCalls(inst);
        logf = fopen("C:\\fiberfix.log", "w");
        GetSystemDirectoryA(path, sizeof(path));
        strcat(path, "\\dinput8.dll");
        real_dinput8 = LoadLibraryA(path);
        log_msg("fiberfix: loaded, real dinput8 %p\n", real_dinput8);
        hook_iat(GetModuleHandleW(NULL));
    }
    return TRUE;
}

/* dinput8 forwarding */
#define FORWARD(name, ret, params, args)                                  \
    __declspec(dllexport) ret WINAPI name params                         \
    {                                                                     \
        ret (WINAPI *fn) params = (void *)GetProcAddress(real_dinput8, #name); \
        return fn ? fn args : (ret)E_FAIL;                                \
    }

FORWARD(DirectInput8Create, HRESULT, (HINSTANCE a, DWORD b, REFIID c, LPVOID *d, LPUNKNOWN e), (a, b, c, d, e))
FORWARD(DllCanUnloadNow, HRESULT, (void), ())
FORWARD(DllGetClassObject, HRESULT, (REFCLSID a, REFIID b, LPVOID *c), (a, b, c))
FORWARD(DllRegisterServer, HRESULT, (void), ())
FORWARD(DllUnregisterServer, HRESULT, (void), ())
