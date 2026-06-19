/* Win32 API stubs and GUID definitions for mscoree_main.c.
 * Only defines symbols that are not FORCEINLINE in windows.h shims. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <stdarg.h>
#include <wchar.h>

#define COBJMACROS
#include "windef.h"
#include "winbase.h"
#include "winuser.h"
#include "winnls.h"
#include "winreg.h"
#include "ole2.h"
#include "strongname.h"
#include "cor.h"
#include "mscoree.h"
#include "metahost.h"
#include "cordebug.h"
#include "wine/debug.h"

#ifdef __APPLE__
extern int rosette_mscoree_show_managed_window(void);
#endif

/* ══════════════════════════════════════════════════════════════════════════
 * GUID Definitions
 * ══════════════════════════════════════════════════════════════════════════ */
#define DEFINE_GUID_(name, l, w1, w2, b1, b2, b3, b4, b5, b6, b7, b8) \
    const GUID name = { l, w1, w2, { b1, b2, b3, b4, b5, b6, b7, b8 } }

DEFINE_GUID_(IID_IUnknown,             0x00000000, 0x0000, 0x0000, 0xC0,0x00,0x00,0x00,0x00,0x00,0x00,0x46);
DEFINE_GUID_(IID_IClassFactory,        0x00000001, 0x0000, 0x0000, 0xC0,0x00,0x00,0x00,0x00,0x00,0x00,0x46);
DEFINE_GUID_(IID_ICLRRuntimeInfo,      0x293E1399, 0x1B4C, 0x4B67, 0xB6,0x40,0xD1,0xAF,0xD8,0x02,0x7C,0x26);
DEFINE_GUID_(IID_ICLRMetaHost,         0x6C1043AA, 0x03A3, 0x41D6, 0x8D,0x32,0xB4,0xD7,0x8E,0x85,0xEC,0x70);
DEFINE_GUID_(IID_ICLRDebugging,        0xD287AE55, 0x6030, 0x4C84, 0x86,0x62,0x16,0x4B,0x95,0x90,0xEE,0x35);
DEFINE_GUID_(CLSID_CLRMetaHost,        0xCB73FE2B, 0x55C2, 0x4663, 0xA8,0x7B,0xA7,0xD2,0xA2,0xDF,0xD1,0xF2);
DEFINE_GUID_(CLSID_CLRMetaHostPolicy,  0xE2190695, 0x77B2, 0x492E, 0x8E,0x14,0xC4,0xB3,0xA7,0xFD,0xD5,0x93);
DEFINE_GUID_(CLSID_CLRDebuggingLegacy, 0xD2A7A531, 0xE76D, 0x4D6C, 0x81,0xFD,0x96,0xE7,0x9B,0x2C,0x0B,0xA4);
DEFINE_GUID_(IID_ICorDebug,            0x3D6F5F61, 0x7538, 0x11D3, 0x8D,0x5B,0x00,0x10,0x4B,0x35,0xE7,0xEF);

/* ══════════════════════════════════════════════════════════════════════════
 * Registry (non-inline functions)
 * ══════════════════════════════════════════════════════════════════════════ */

LONG WINAPI RegOpenKeyExW(HKEY hKey, LPCWSTR lpSubKey, DWORD ulOptions, REGSAM samDesired, PHKEY phkResult)
{
    (void)hKey; (void)lpSubKey; (void)ulOptions; (void)samDesired;
    fprintf(stderr, "  [stub] RegOpenKeyExW\n");
    *phkResult = NULL;
    return 2L; /* ERROR_FILE_NOT_FOUND */
}

/* Note: RegQueryValueExW, RegSetValueExW, RegCloseKey are FORCEINLINE in windows.h */

/* ══════════════════════════════════════════════════════════════════════════
 * Win32 base (non-inline functions)
 * ══════════════════════════════════════════════════════════════════════════ */

HANDLE WINAPI GetCurrentProcess(void) { return (HANDLE)(ULONG_PTR)1; }

FARPROC WINAPI GetProcAddress(HMODULE hModule, LPCSTR lpProcName)
{
    (void)hModule;
    if (lpProcName) fprintf(stderr, "  [stub] GetProcAddress(%s)\n", lpProcName);
    return NULL;
}

HMODULE WINAPI LoadLibraryA(LPCSTR lpLibFileName)
{
    fprintf(stderr, "  [stub] LoadLibraryA(%s)\n", lpLibFileName);
    return NULL;
}

HMODULE WINAPI LoadLibraryW(LPCWSTR lpLibFileName)
{
    fprintf(stderr, "  [stub] LoadLibraryW\n");
    return NULL;
}

BOOL WINAPI FreeLibrary(HMODULE hLibModule) { (void)hLibModule; return FALSE; }

BOOL WINAPI CloseHandle(HANDLE hObject) { (void)hObject; return TRUE; }

BOOL WINAPI CreateProcessW(LPCWSTR lpApplicationName, LPWSTR lpCommandLine,
                LPSECURITY_ATTRIBUTES lpProcessAttributes, LPSECURITY_ATTRIBUTES lpThreadAttributes,
                BOOL bInheritHandles, DWORD dwCreationFlags, LPVOID lpEnvironment,
                LPCWSTR lpCurrentDirectory, LPSTARTUPINFOW lpStartupInfo,
                LPPROCESS_INFORMATION lpProcessInformation)
{
    (void)lpApplicationName; (void)lpCommandLine; (void)lpProcessAttributes;
    (void)lpThreadAttributes; (void)bInheritHandles; (void)dwCreationFlags;
    (void)lpEnvironment; (void)lpCurrentDirectory; (void)lpStartupInfo; (void)lpProcessInformation;
    fprintf(stderr, "  [stub] CreateProcessW\n");
    return FALSE;
}

DWORD WINAPI WaitForSingleObject(HANDLE hHandle, DWORD dwMilliseconds)
{
    (void)hHandle; (void)dwMilliseconds;
    return 0; /* WAIT_OBJECT_0 */
}

static pthread_key_t tls_key;
static int tls_key_once = 0;
static void tls_init(void) {
    if (!tls_key_once) { pthread_key_create(&tls_key, NULL); tls_key_once = 1; }
}

DWORD WINAPI TlsAlloc(void) { tls_init(); return (DWORD)(ULONG_PTR)&tls_key; }
LPVOID WINAPI TlsGetValue(DWORD dwTlsIndex) { (void)dwTlsIndex; tls_init(); return pthread_getspecific(tls_key); }
BOOL WINAPI TlsSetValue(DWORD dwTlsIndex, LPVOID lpTlsValue) { (void)dwTlsIndex; tls_init(); return pthread_setspecific(tls_key, lpTlsValue) == 0; }
BOOL WINAPI TlsFree(DWORD dwTlsIndex) { (void)dwTlsIndex; return TRUE; }

LONG WINAPI InterlockedIncrement(LONG volatile *Addend) { return __sync_add_and_fetch(Addend, 1); }
LONG WINAPI InterlockedDecrement(LONG volatile *Addend) { return __sync_sub_and_fetch(Addend, 1); }

BOOL WINAPI IsWow64Process(HANDLE hProcess, PBOOL Wow64Process) { (void)hProcess; if (Wow64Process) *Wow64Process = FALSE; return TRUE; }

/* Note: lstrcpyW, lstrlenW/A, GetModuleHandleA/W are FORCEINLINE in windows.h */

/* ══════════════════════════════════════════════════════════════════════════
 * Locale / NLS
 * ══════════════════════════════════════════════════════════════════════════ */

int WINAPI WideCharToMultiByte(UINT CodePage, DWORD dwFlags, LPCWSTR lpWideCharStr,
                int cchWideChar, LPSTR lpMultiByteStr, int cbMultiByte,
                LPCSTR lpDefaultChar, LPBOOL lpUsedDefaultChar)
{
    (void)dwFlags; (void)lpDefaultChar; (void)lpUsedDefaultChar;
    if (cchWideChar == -1) { /* count including null */
        cchWideChar = 0;
        while (lpWideCharStr[cchWideChar]) cchWideChar++;
        cchWideChar++;
    }
    if (!lpMultiByteStr) return cchWideChar;
    int written = 0;
    for (int i = 0; i < cchWideChar && written < cbMultiByte - 1; i++) {
        WCHAR wc = lpWideCharStr[i];
        if (wc < 0x80) { lpMultiByteStr[written++] = (char)wc; }
        else if (wc < 0x800) {
            if (written + 2 > cbMultiByte) break;
            lpMultiByteStr[written++] = (char)(0xC0 | (wc >> 6));
            lpMultiByteStr[written++] = (char)(0x80 | (wc & 0x3F));
        } else {
            if (written + 3 > cbMultiByte) break;
            lpMultiByteStr[written++] = (char)(0xE0 | (wc >> 12));
            lpMultiByteStr[written++] = (char)(0x80 | ((wc >> 6) & 0x3F));
            lpMultiByteStr[written++] = (char)(0x80 | (wc & 0x3F));
        }
    }
    lpMultiByteStr[written] = 0;
    return written;
}

int WINAPI MultiByteToWideChar(UINT CodePage, DWORD dwFlags, LPCSTR lpMultiByteStr,
                int cbMultiByte, LPWSTR lpWideCharStr, int cchWideChar)
{
    (void)CodePage; (void)dwFlags;
    if (cbMultiByte == -1) cbMultiByte = (int)strlen(lpMultiByteStr) + 1;
    if (!lpWideCharStr) return cbMultiByte;
    int written = 0;
    for (int i = 0; i < cbMultiByte && written < cchWideChar; i++) {
        unsigned char c = (unsigned char)lpMultiByteStr[i];
        if (c < 0x80) { lpWideCharStr[written++] = c; }
        else if ((c & 0xE0) == 0xC0 && i + 1 < cbMultiByte) {
            lpWideCharStr[written++] = (WCHAR)((c & 0x1F) << 6) | (lpMultiByteStr[++i] & 0x3F);
        } else if ((c & 0xF0) == 0xE0 && i + 2 < cbMultiByte) {
            lpWideCharStr[written++] = (WCHAR)((c & 0x0F) << 12) | ((lpMultiByteStr[++i] & 0x3F) << 6) | (lpMultiByteStr[++i] & 0x3F);
        }
    }
    return written;
}

/* ══════════════════════════════════════════════════════════════════════════
 * COM stubs
 * ══════════════════════════════════════════════════════════════════════════ */

HRESULT WINAPI CoInitialize(LPVOID pvReserved) { (void)pvReserved; return S_OK; }
void WINAPI CoUninitialize(void) {}
HRESULT WINAPI CoInitializeEx(LPVOID pvReserved, DWORD dwCoInit) { (void)pvReserved; (void)dwCoInit; return S_OK; }
HRESULT WINAPI CoCreateInstance(REFCLSID rclsid, IUnknown *pUnkOuter, DWORD dwClsContext, REFIID riid, LPVOID *ppv) { (void)rclsid; (void)pUnkOuter; (void)dwClsContext; (void)riid; (void)ppv; return CLASS_E_CLASSNOTAVAILABLE; }
HRESULT WINAPI CLSIDFromString(LPCWSTR lpsz, LPCLSID pclsid) { (void)lpsz; (void)pclsid; return E_NOTIMPL; }
/* CoTaskMemAlloc/Free declared in ole2.h but with wrong return type for CoTaskMemAlloc.
 * If needed, fix ole2.h's declaration to return LPVOID. */

/* ══════════════════════════════════════════════════════════════════════════
 * Heap stubs
 * ══════════════════════════════════════════════════════════════════════════ */

HANDLE WINAPI GetProcessHeap(void) { return (HANDLE)(ULONG_PTR)1; }
LPVOID WINAPI HeapAlloc(HANDLE hHeap, DWORD dwFlags, SIZE_T dwBytes) { (void)hHeap; (void)dwFlags; return malloc(dwBytes); }
BOOL WINAPI HeapFree(HANDLE hHeap, DWORD dwFlags, LPVOID lpMem) { (void)hHeap; (void)dwFlags; free(lpMem); return TRUE; }

/* ══════════════════════════════════════════════════════════════════════════
 * String stubs (non-inline Windows string functions)
 * ══════════════════════════════════════════════════════════════════════════ */

LPWSTR WINAPI lstrcatW(LPWSTR lpString1, LPCWSTR lpString2)
{
    if (!lpString1 || !lpString2) return lpString1;
    WCHAR *p = lpString1;
    while (*p) p++;
    while ((*p++ = *lpString2++) != 0);
    return lpString1;
}

LPSTR WINAPI lstrcatA(LPSTR lpString1, LPCSTR lpString2)
{
    if (!lpString1 || !lpString2) return lpString1;
    strcat(lpString1, lpString2);
    return lpString1;
}

int WINAPI lstrcmpiW(LPCWSTR lpString1, LPCWSTR lpString2)
{
    if (!lpString1 && !lpString2) return 0;
    if (!lpString1) return -1;
    if (!lpString2) return 1;
    for (;;) {
        WCHAR c1 = *lpString1++, c2 = *lpString2++;
        if (c1 >= 'a' && c1 <= 'z') c1 -= 32;
        if (c2 >= 'a' && c2 <= 'z') c2 -= 32;
        if (c1 != c2) return (c1 > c2) ? 1 : -1;
        if (c1 == 0) return 0;
    }
}

int WINAPI lstrcmpiA(LPCSTR lpString1, LPCSTR lpString2)
{
    if (!lpString1 && !lpString2) return 0;
    if (!lpString1) return -1;
    if (!lpString2) return 1;
    return strcasecmp(lpString1, lpString2);
}

/* ══════════════════════════════════════════════════════════════════════════
 * Other Win32 stubs
 * ══════════════════════════════════════════════════════════════════════════ */

DWORD WINAPI GetFileAttributesW(LPCWSTR lpFileName) { (void)lpFileName; return (DWORD)-1; }
DWORD WINAPI GetFileAttributesA(LPCSTR lpFileName) { (void)lpFileName; return (DWORD)-1; }
BOOL WINAPI DeleteFileW(LPCWSTR lpFileName) { (void)lpFileName; return FALSE; }
BOOL WINAPI MoveFileW(LPCWSTR lpExistingFileName, LPCWSTR lpNewFileName) { (void)lpExistingFileName; (void)lpNewFileName; return FALSE; }
DWORD WINAPI GetModuleFileNameW(HMODULE hModule, LPWSTR lpFilename, DWORD nSize) { (void)hModule; if (lpFilename && nSize > 0) lpFilename[0] = 0; return 0; }
DWORD WINAPI GetEnvironmentVariableW(LPCWSTR lpName, LPWSTR lpBuffer, DWORD nSize) { (void)lpName; if (lpBuffer && nSize > 0) lpBuffer[0] = 0; return 0; }
BOOL WINAPI SetEnvironmentVariableW(LPCWSTR lpName, LPCWSTR lpValue) { (void)lpName; (void)lpValue; return FALSE; }
DWORD WINAPI GetLastError(void) { return 0L; }
void WINAPI SetLastError(DWORD dwErrCode) { (void)dwErrCode; }
HLOCAL WINAPI LocalFree(HLOCAL hMem) { free((void*)hMem); return NULL; }
void WINAPI OutputDebugStringA(LPCSTR lpOutputString) { if (lpOutputString) fprintf(stderr,"  [dbg] %s", lpOutputString); }
void WINAPI OutputDebugStringW(LPCWSTR lpOutputString) { if (lpOutputString) fprintf(stderr,"  [dbg] %ls", (const wchar_t *)lpOutputString); }

/* ══════════════════════════════════════════════════════════════════════════
 * Wine-specific stubs
 * ══════════════════════════════════════════════════════════════════════════ */

void wine_dbg_printf(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
}

HRESULT WINAPI __wine_register_resources(void) { return S_OK; }
HRESULT WINAPI __wine_unregister_resources(void) { return S_OK; }

/* Wine debug channel variable for winediag (declared extern in debug.h, defined here) */
struct __wine_debug_channel __wine_dbch_winediag = { 0xFF, "winediag" };

/* ══════════════════════════════════════════════════════════════════════════
 * mscoree private function stubs (mscoree_private.h)
 * ══════════════════════════════════════════════════════════════════════════ */

/* ── Runtime detection ───────────────────────────────────────────────── */

struct CLRRuntimeInfo_impl
{
    ICLRRuntimeInfo ICLRRuntimeInfo_iface;
    DWORD major, minor, build;
    void *loaded_runtime;
};

static struct CLRRuntimeInfo_impl g_fake_v4_runtime = {
    .major = 4, .minor = 0, .build = 30319, .loaded_runtime = NULL
};

HRESULT get_runtime_info(LPCWSTR exefile, LPCWSTR version, LPCWSTR config_file,
    IStream *config_stream, DWORD startup_flags, DWORD runtimeinfo_flags, BOOL legacy,
    ICLRRuntimeInfo **result)
{
    (void)exefile; (void)version; (void)config_file; (void)config_stream;
    (void)startup_flags; (void)runtimeinfo_flags; (void)legacy;
    fprintf(stderr, "  [stub] get_runtime_info\n");
    /* Return a fake v4.0.30319 runtime so callers can proceed */
    if (result)
        *result = &g_fake_v4_runtime.ICLRRuntimeInfo_iface;
    return S_OK;
}

BOOL get_mono_path(LPWSTR path, BOOL skip_local)
{
    (void)skip_local;
    if (path) path[0] = 0;
    fprintf(stderr, "  [stub] get_mono_path\n");
    return FALSE;
}

void expect_no_runtimes(void)
{
    fprintf(stderr, "  [stub] expect_no_runtimes\n");
}

HRESULT create_monodata(REFCLSID clsid, LPVOID *ppObj)
{
    (void)clsid; (void)ppObj;
    fprintf(stderr, "  [stub] create_monodata\n");
    return E_NOTIMPL;
}

/* ── CLRMetaHost stubs ──────────────────────────────────────────────── */

HRESULT CLRMetaHost_CreateInstance(REFIID riid, void **ppobj)
{
    (void)riid; (void)ppobj;
    fprintf(stderr, "  [stub] CLRMetaHost_CreateInstance\n");
    return E_NOTIMPL;
}

HRESULT CLRMetaHostPolicy_CreateInstance(REFIID riid, void **ppobj)
{
    (void)riid; (void)ppobj;
    fprintf(stderr, "  [stub] CLRMetaHostPolicy_CreateInstance\n");
    return E_NOTIMPL;
}

HRESULT WINAPI CLRMetaHost_GetVersionFromFile(ICLRMetaHost* iface,
    LPCWSTR pwzFilePath, LPWSTR pwzBuffer, DWORD *pcchBuffer)
{
    (void)iface; (void)pwzFilePath; (void)pwzBuffer; (void)pcchBuffer;
    fprintf(stderr, "  [stub] CLRMetaHost_GetVersionFromFile\n");
    return E_NOTIMPL;
}

HRESULT WINAPI CLRMetaHost_ExitProcess(ICLRMetaHost* iface, INT32 iExitCode)
{
    (void)iface; (void)iExitCode;
    fprintf(stderr, "  [stub] CLRMetaHost_ExitProcess\n");
    return E_NOTIMPL;
}

HRESULT WINAPI CLRMetaHost_GetRuntime(ICLRMetaHost* iface,
    LPCWSTR pwzVersion, REFIID iid, LPVOID *ppRuntime)
{
    (void)iface; (void)pwzVersion; (void)iid; (void)ppRuntime;
    fprintf(stderr, "  [stub] CLRMetaHost_GetRuntime\n");
    /* Return our fake v4 runtime */
    if (ppRuntime)
        *ppRuntime = &g_fake_v4_runtime.ICLRRuntimeInfo_iface;
    return S_OK;
}

/* ── ICLRRuntimeInfo_GetRuntimeHost ─────────────────────────────────── */

HRESULT ICLRRuntimeInfo_GetRuntimeHost(ICLRRuntimeInfo *iface, struct RuntimeHost **result)
{
    (void)iface; (void)result;
    fprintf(stderr, "  [stub] ICLRRuntimeInfo_GetRuntimeHost\n");
    return E_NOTIMPL;
}

/* ── RuntimeHost stubs ──────────────────────────────────────────────── */

HRESULT RuntimeHost_CreateManagedInstance(struct RuntimeHost *This,
    LPCWSTR name, IUnknown **result)
{
    (void)This; (void)name; (void)result;
    fprintf(stderr, "  [stub] RuntimeHost_CreateManagedInstance\n");
    return E_NOTIMPL;
}

void runtimehost_init(void)
{
    fprintf(stderr, "  [stub] runtimehost_init\n");
}

void runtimehost_uninit(void)
{
    fprintf(stderr, "  [stub] runtimehost_uninit\n");
}

/* ══════════════════════════════════════════════════════════════════════════
 * GetSystemDirectoryW
 * ══════════════════════════════════════════════════════════════════════════ */

/* ══════════════════════════════════════════════════════════════════════════
 * _CorExeMain — .NET executable entry point
 * ══════════════════════════════════════════════════════════════════════════ */

/* _CorExeMain is the entry point that .NET executables jump to from their
 * modified PE header. It takes no arguments and returns an HRESULT. The
 * real implementation would find the .NET assembly, load the CLR, and run it.
 * This stub simply delegates to _CorExeMain2 using the current process image
 * or returns S_OK if that's not available. */
__int32 WINAPI _CorExeMain(void)
{
    fprintf(stderr, "  [mscoree] _CorExeMain called (stub)\n");
#ifdef __APPLE__
    if (getenv("ROSETTE_MANAGED_GUI") && strcmp(getenv("ROSETTE_MANAGED_GUI"), "1") == 0)
        return rosette_mscoree_show_managed_window();
#endif
    return S_OK;
}

/* ══════════════════════════════════════════════════════════════════════════
 * GetSystemDirectoryW
 * ══════════════════════════════════════════════════════════════════════════ */

UINT WINAPI GetSystemDirectoryW(LPWSTR lpBuffer, UINT uSize)
{
    static const WCHAR prefix[] = {'/', 'u', 's', 'r', 0};
    if (lpBuffer && uSize >= 5) {
        memcpy(lpBuffer, prefix, sizeof(prefix));
        return 4;
    }
    return uSize >= 5 ? 4 : 0;
}
