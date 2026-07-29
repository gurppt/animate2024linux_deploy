/* App-local Version API proxy: establish a process-wide MTA before Adobe DVA
 * workers use COM, then forward the complete API to version_real.dll. */
#include <windows.h>
#include <combaseapi.h>
static HMODULE real;
static CO_MTA_USAGE_COOKIE cookie;
static void ensure(void)
{
    static volatile LONG state;
    LONG previous = InterlockedCompareExchange(&state, 1, 0);
    if (previous == 2) return;
    if (previous == 1) { while (state != 2) Sleep(0); return; }
    CoIncrementMTAUsage(&cookie);
    real = LoadLibraryW(L"version_real.dll");
    if (!real)
        real = LoadLibraryW(L"C:\\Program Files\\Adobe\\Adobe Animate 2024\\version_real.dll");
    InterlockedExchange(&state, 2);
}
#define STUB(ret, name, params, args) \
    ret p##name params { ensure(); static FARPROC fn; \
    if (!fn && real) fn=GetProcAddress(real,#name); return ((ret(*)params)fn)args; }
STUB(BOOL,GetFileVersionInfoA,(LPCSTR a,DWORD b,DWORD c,LPVOID d),(a,b,c,d))
STUB(BOOL,GetFileVersionInfoW,(LPCWSTR a,DWORD b,DWORD c,LPVOID d),(a,b,c,d))
STUB(BOOL,GetFileVersionInfoExA,(DWORD a,LPCSTR b,DWORD c,DWORD d,LPVOID e),(a,b,c,d,e))
STUB(BOOL,GetFileVersionInfoExW,(DWORD a,LPCWSTR b,DWORD c,DWORD d,LPVOID e),(a,b,c,d,e))
STUB(DWORD,GetFileVersionInfoSizeA,(LPCSTR a,LPDWORD b),(a,b))
STUB(DWORD,GetFileVersionInfoSizeW,(LPCWSTR a,LPDWORD b),(a,b))
STUB(DWORD,GetFileVersionInfoSizeExA,(DWORD a,LPCSTR b,LPDWORD c),(a,b,c))
STUB(DWORD,GetFileVersionInfoSizeExW,(DWORD a,LPCWSTR b,LPDWORD c),(a,b,c))
STUB(DWORD,VerFindFileA,(DWORD a,LPCSTR b,LPCSTR c,LPCSTR d,LPSTR e,PUINT f,LPSTR g,PUINT h),(a,b,c,d,e,f,g,h))
STUB(DWORD,VerFindFileW,(DWORD a,LPCWSTR b,LPCWSTR c,LPCWSTR d,LPWSTR e,PUINT f,LPWSTR g,PUINT h),(a,b,c,d,e,f,g,h))
STUB(DWORD,VerInstallFileA,(DWORD a,LPCSTR b,LPCSTR c,LPCSTR d,LPCSTR e,LPCSTR f,LPSTR g,PUINT h),(a,b,c,d,e,f,g,h))
STUB(DWORD,VerInstallFileW,(DWORD a,LPCWSTR b,LPCWSTR c,LPCWSTR d,LPCWSTR e,LPCWSTR f,LPWSTR g,PUINT h),(a,b,c,d,e,f,g,h))
STUB(DWORD,VerLanguageNameA,(DWORD a,LPSTR b,DWORD c),(a,b,c))
STUB(DWORD,VerLanguageNameW,(DWORD a,LPWSTR b,DWORD c),(a,b,c))
STUB(BOOL,VerQueryValueA,(LPCVOID a,LPCSTR b,LPVOID*c,PUINT d),(a,b,c,d))
STUB(BOOL,VerQueryValueW,(LPCVOID a,LPCWSTR b,LPVOID*c,PUINT d),(a,b,c,d))
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID reserved)
{ (void)reserved; if(reason==DLL_PROCESS_ATTACH)DisableThreadLibraryCalls(h); return TRUE; }
