/*
 * Rosette macOS LLP64 override for win32/windows_base.h.
 *
 * On macOS this file is picked up earlier in the include search order than
 * include/shims/win32/win32/windows_base.h (the existing shim wrapper) and
 * include/win32/windows_base.h (the upstream-mirrored canonical), neither
 * of which is modified. Both upstream files are skipped on macOS via their
 * own outermost guards, which we pre-define below.
 *
 * The purpose is to keep the LLP64 ABI shape (LONG=4, ULONG=4, DWORD=4,
 * WCHAR=2, GUID=16, OVERLAPPED=32, ...) on a host whose native C runtime
 * is LP64, so that translated Windows assembly sees the same field offsets
 * and operand widths it would on Windows x64.
 */
#ifndef ROSETTE_SHIMS_MACOS_WIN32_WINDOWS_BASE_H
#define ROSETTE_SHIMS_MACOS_WIN32_WINDOWS_BASE_H

#include <stdint.h>

/* Activate centralised Clang warning suppression before any third-party
 * headers are processed by translate-c.  This eliminates the need for
 * per-patch -Wno-* pragma injection into windows.h, sysinfo.h, and the
 * hundreds of transitive Win32 SDK headers. */
#include <compiler_compat.h>

/* Suppress the upstream canonical (guarded by #ifndef _WINDOWS_) and the
 * existing shim wrapper (guarded by its own #ifndef ...). Defining both
 * here means any later #include of either file is a no-op. */
#ifndef _WINDOWS_
#define _WINDOWS_
#endif
#ifndef ROSETTE_SHIMS_WIN32_WINDOWS_BASE_H
#define ROSETTE_SHIMS_WIN32_WINDOWS_BASE_H
#endif

#if defined(__cplusplus)
extern "C" {
#endif

/* ========================================================================== */
/* Compiler / calling-convention macros                                       */
/* ========================================================================== */
#ifndef _WIN64
#if defined(__LP64__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
#define _WIN64 1
#endif
#endif

#ifndef __stdcall
#define __stdcall
#endif
#ifndef __cdecl
#define __cdecl
#endif
#ifndef __override
#define __override
#endif
#ifndef __int64
#define __int64 long long
#endif
#ifndef __uint64
#define __uint64 unsigned long long
#endif
#ifndef FORCEINLINE
#define FORCEINLINE __attribute__((always_inline)) inline
#endif

#ifndef _WIN64
#if defined(__LP64__) || defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
#define _WIN64 1
#endif
#endif

/* ========================================================================== */
/* Some Win32 typenames are identical to C++ builtins — guard for C++ as      */
/* well as for Objective‑C which owns its own definitions.                    */
/* ========================================================================== */
#ifndef __OBJC__
#ifndef interface
#define interface             struct
#endif
#endif
#ifndef __cdecl
#define __cdecl
#endif
#ifndef __override
#define __override
#endif
#ifndef __int64
#define __int64 long long
#endif
#ifndef __uint64
#define __uint64 unsigned long long
#endif
#ifndef FORCEINLINE
#define FORCEINLINE __attribute__((always_inline)) inline
#endif

#define _CRTALLOC(x)        __attribute__((section(x)))
#define DECLSPEC_ALIGN(x)   __attribute__((aligned(x)))

#define NTAPI       __stdcall
#define WINAPI      __stdcall
#define APIENTRY    __stdcall
#define CALLBACK    __stdcall

#define STDMETHODCALLTYPE   __stdcall
#define STDMETHODVCALLTYPE  __cdecl
#define STDAPICALLTYPE      __stdcall
#define STDAPIVCALLTYPE     __cdecl

#ifndef TRUE
#define TRUE  (1)
#endif
#ifndef FALSE
#define FALSE (0)
#endif
#ifndef NULL
#  ifdef __cplusplus
#    define NULL __nullptr
#  else
#    define NULL ((void *)0)
#  endif
#endif
#ifdef UNICODE
#  define __TEXT(x) L ## x
#  define TEXT(x)   __TEXT(x)
#else
#  define TEXT(x) x
#endif
#ifndef PATH_MAX
#define PATH_MAX 260
#endif
#define MAX_PATH 260

#ifndef FAR
#define FAR
#endif
#ifndef NEAR
#define NEAR
#endif
#define MAKEINTRESOURCE(i) ((LPCSTR)(ULONG_PTR)((WORD)(i)))

#define MAKEWORD(a, b) \
            ((WORD)(((BYTE)(((DWORD_PTR)(a)) & 0xffULL)) | \
            ((WORD)((BYTE)(((DWORD_PTR)(b)) & 0xffULL))) << 8))
#define MAKELONG(a, b) \
            ((LONG)(((WORD)(((DWORD_PTR)(a)) & 0xffffULL)) | \
            ((DWORD)((WORD)(((DWORD_PTR)(b)) & 0xffffULL))) << 16))
#define LOWORD(l) ((WORD)(((DWORD_PTR)(l)) & 0xffffULL))
#define HIWORD(l) ((WORD)((((DWORD_PTR)(l)) >> 16) & 0xffffULL))
#define MAKELPARAM(l, h) ((LPARAM)(((WORD)(l)) | ((DWORD)((WORD)(h))) << 16))
#define LOBYTE(w) ((BYTE)(((DWORD_PTR)(w)) & 0xffULL))
#define HIBYTE(w) ((BYTE)((((DWORD_PTR)(w)) >> 8) & 0xffULL))

#define interface             struct
#define PURE
#define THIS_                 INTERFACE * This,
#define THIS                  INTERFACE * This
#define STDMETHOD(method)         HRESULT (STDMETHODCALLTYPE * method)
#define STDMETHOD_(type, method)  type    (STDMETHODCALLTYPE * method)
#define STDMETHODV(method)        HRESULT (STDMETHODVCALLTYPE * method)
#define STDMETHODV_(type, method) type    (STDMETHODVCALLTYPE * method)
#define IFACEMETHOD(method)         __override STDMETHOD(method)
#define IFACEMETHOD_(type, method)  __override STDMETHOD_(type,method)
#define IFACEMETHODV(method)        __override STDMETHODV(method)
#define IFACEMETHODV_(type, method) __override STDMETHODV_(type,method)
#define BEGIN_INTERFACE
#define END_INTERFACE

#ifdef CONST_VTABLE
#  undef CONST_VTBL
#  define CONST_VTBL const
#  define DECLARE_INTERFACE(iface) \
    typedef interface iface { const struct iface##Vtbl * lpVtbl; } iface; \
    typedef const struct iface##Vtbl iface##Vtbl; \
    const struct iface##Vtbl
#else
#  undef CONST_VTBL
#  define CONST_VTBL
#  define DECLARE_INTERFACE(iface) \
    typedef interface iface { struct iface##Vtbl * lpVtbl; } iface; \
    typedef struct iface##Vtbl iface##Vtbl; \
    struct iface##Vtbl
#endif
#define DECLARE_INTERFACE_(iface, baseiface) DECLARE_INTERFACE(iface)

#define HRESULT_IS_WIN32(x)    ((((x) >> 16) & 0xFFFFU) == 0x8U)
#define HRESULT_IS_FAILURE(x)  ((((x) >> 31) & 0x1U) == 0x1U)
#define HRESULT_FACILITY(x)    (((x) >> 16) & 0xFFFFU)
#define HRESULT_CODE(x)        ((x) & 0xFFFFU)
#define HRESULT_FROM_WIN32(x)  (0x80070000U | (x))

/* ========================================================================== */
/* Basic Types -- LLP64 widths (Win32 x64 ABI) on an LP64 host.               */
/*   LONG / ULONG / DWORD are 4 bytes (NOT host `long` which is 8).           */
/*   WCHAR is 2 bytes (NOT host wchar_t which is 4).                          */
/*   Pointer-derived types are 8 bytes (matches both Win32 x64 and macOS x64).*/
/* ========================================================================== */
/* In Objective‑C, BOOL is a built-in typedef (bool); we must not
   redefine it.  In plain C and C++, BOOL is not predefined, so we
   provide the Win32 LLP64-compatible definition. */
#ifndef __OBJC__
#ifndef BOOL
typedef int                 BOOL;
#endif
#endif
typedef char                CHAR;
typedef short               SHORT;
typedef int                 INT;
typedef int32_t             LONG;
typedef unsigned char       UCHAR;
typedef unsigned short      USHORT;
typedef unsigned int        UINT;
typedef uint32_t            ULONG;
typedef unsigned char       BYTE;
typedef unsigned short      WORD;
typedef float               FLOAT;
typedef uint32_t            DWORD;

/* WCHAR is 16-bit on Win32; macOS native wchar_t is 32-bit, so we cannot
 * reuse it. Provide a fixed 16-bit alias directly. */
typedef uint16_t            WCHAR;
typedef WCHAR *             PWCHAR;
typedef WORD                ATOM;
typedef unsigned int        ULONG32;
typedef uint64_t            DWORD64;
typedef uint64_t            ULONG64;
typedef int32_t             INT32;
typedef int64_t             INT64;
typedef uint64_t            DWORDLONG;
typedef int64_t             LONGLONG;
typedef uint64_t            ULONGLONG;

typedef CHAR *              PCHAR;
typedef ULONG *             PULONG;
typedef BYTE *              PBYTE;
typedef ULONG64 *           PULONG64;
typedef DWORD64 *           PDWORD64;

typedef void                VOID;
typedef void *              PVOID;
typedef void *              LPVOID;
typedef BOOL *              PBOOL;
typedef BOOL *              LPBOOL;
typedef WORD *              PWORD;
typedef LONG *              PLONG;
typedef LONG *              LPLONG;
typedef DWORD *             PDWORD;
typedef BYTE *              LPBYTE;
typedef DWORD *             LPDWORD;
typedef const void *        LPCVOID;

typedef LPVOID              HANDLE;
typedef HANDLE              HINSTANCE;
typedef HANDLE              HWND;
typedef HINSTANCE           HMODULE;
typedef HANDLE              HDC;
typedef HANDLE              HGLRC;
typedef HANDLE              HMENU;
typedef HANDLE *            PHANDLE;
typedef HANDLE *            LPHANDLE;

#define INVALID_HANDLE_VALUE   ((HANDLE)(LONG_PTR)-1)
#define DECLARE_HANDLE(name)   struct name##__{int unused;}; typedef struct name##__ *name

typedef WCHAR *             PWSTR;

/* Pointer-derived types: 8 bytes on x86_64 / arm64 (LP64), same as Win32 x64. */
typedef int64_t             INT_PTR;
typedef int64_t             LONG_PTR;
typedef uint64_t            UINT_PTR;
typedef uint64_t            ULONG_PTR;
typedef ULONG_PTR           DWORD_PTR;
typedef DWORD_PTR *         PDWORD_PTR;
typedef ULONG_PTR           SIZE_T;
typedef LONG_PTR            SSIZE_T;

typedef CHAR *              LPSTR;
typedef WCHAR *             LPWSTR;
typedef const CHAR *        LPCSTR;
typedef const WCHAR *       LPCWSTR;
typedef const WCHAR *       PCWSTR;

#if defined(UNICODE)
typedef WCHAR               TCHAR;
typedef WCHAR               TBYTE;
typedef LPCWSTR             LPCTSTR;
typedef LPWSTR              LPTSTR;
#else
typedef char                TCHAR;
typedef unsigned char       TBYTE;
typedef LPCSTR              LPCTSTR;
typedef LPSTR               LPTSTR;
#endif

#define MINCHAR             0x80
#define MAXCHAR             0x7f
#define MINSHORT            0x8000
#define MAXSHORT            0x7fff
#define MINLONG             0x80000000
#define MAXLONG             0x7fffffff
#define MAXBYTE             0xff
#define MAXWORD             0xffff
#define MAXDWORD            0xffffffff

typedef INT_PTR (WINAPI *FARPROC)(void);
typedef INT_PTR (WINAPI *NEARPROC)(void);
typedef INT_PTR (WINAPI *PROC)(void);

typedef DWORD               ACCESS_MASK;
typedef ACCESS_MASK *       PACCESS_MASK;

typedef HANDLE              HICON;
typedef HANDLE              HBRUSH;
typedef HICON               HCURSOR;

typedef LONG                HRESULT;
typedef LONG_PTR            LRESULT;
typedef LONG_PTR            LPARAM;
typedef UINT_PTR            WPARAM;

typedef void *              HGDIOBJ;
typedef HANDLE              HKEY;
typedef HKEY *              PHKEY;
typedef ACCESS_MASK         REGSAM;

/* ========================================================================== */
/* Error codes                                                                */
/* ========================================================================== */
#define ERROR_SUCCESS               0L
#define ERROR_FILE_NOT_FOUND        2L
#define ERROR_PATH_NOT_FOUND        3L
#define ERROR_TOO_MANY_OPEN_FILES   4L
#define ERROR_ACCESS_DENIED         5L
#define ERROR_NO_MORE_FILES         18L
#define ERROR_SHARING_VIOLATION     32L
#define ERROR_FILE_EXISTS           80L
#define ERROR_INVALID_PARAMETER     87L
#define ERROR_INSUFFICIENT_BUFFER   122L
#define ERROR_ALREADY_EXISTS        183L
#define ERROR_MORE_DATA             234L
#define ERROR_CANT_ACCESS_FILE      1920L

/* ========================================================================== */
/* DllMain reasons                                                            */
/* ========================================================================== */
#define DLL_PROCESS_ATTACH      (1)
#define DLL_PROCESS_DETACH      (0)
#define DLL_THREAD_ATTACH       (2)
#define DLL_THREAD_DETACH       (3)

/* ========================================================================== */
/* Structures -- LLP64-correct sizes:                                         */
/*   OVERLAPPED            = 32  (ULONG_PTR x2 + 8-byte union + HANDLE)       */
/*   SECURITY_ATTRIBUTES   = 24  (DWORD + pad + LPVOID + BOOL + pad)          */
/*   LARGE_INTEGER         = 8   (i64 union)                                  */
/*   ULARGE_INTEGER        = 8                                                */
/*   FILETIME              = 8                                                */
/*   GUID                  = 16  (DWORD + WORD + WORD + 8 bytes)              */
/* ========================================================================== */
typedef struct _OVERLAPPED {
    ULONG_PTR Internal;
    ULONG_PTR InternalHigh;
    union {
        struct {
            DWORD Offset;
            DWORD OffsetHigh;
        };
        PVOID Pointer;
    };
    HANDLE hEvent;
} OVERLAPPED, *LPOVERLAPPED;

typedef struct _SECURITY_ATTRIBUTES {
    DWORD  nLength;
    LPVOID lpSecurityDescriptor;
    BOOL   bInheritHandle;
} SECURITY_ATTRIBUTES, *PSECURITY_ATTRIBUTES, *LPSECURITY_ATTRIBUTES;

typedef union _LARGE_INTEGER {
    struct {
        DWORD LowPart;
        LONG  HighPart;
    };
    struct {
        DWORD LowPart;
        LONG  HighPart;
    } u;
    LONGLONG QuadPart;
} LARGE_INTEGER, *PLARGE_INTEGER;

typedef union _ULARGE_INTEGER {
    struct {
        DWORD LowPart;
        DWORD HighPart;
    };
    struct {
        DWORD LowPart;
        DWORD HighPart;
    } u;
    ULONGLONG QuadPart;
} ULARGE_INTEGER, *PULARGE_INTEGER;

typedef struct _FILETIME {
    DWORD dwLowDateTime;
    DWORD dwHighDateTime;
} FILETIME, *PFILETIME, *LPFILETIME;

/* GUID uses fixed-width DWORD/WORD instead of `unsigned long`/`unsigned short`
 * so that Data1 stays 4 bytes on an LP64 host (where `unsigned long` is 8). */
typedef struct _GUID {
    DWORD Data1;
    WORD  Data2;
    WORD  Data3;
    BYTE  Data4[8];
} GUID;

/* ========================================================================== */
/* Memory Basic Information Structures (from io.h)                            */
/* ========================================================================== */
typedef struct _MEMORY_BASIC_INFORMATION32 {
    DWORD       BaseAddress;
    DWORD       AllocationBase;
    DWORD       AllocationProtect;
    DWORD       RegionSize;
    DWORD       State;
    DWORD       Protect;
    DWORD       Type;
} MEMORY_BASIC_INFORMATION32, *PMEMORY_BASIC_INFORMATION32;

typedef struct DECLSPEC_ALIGN(16) _MEMORY_BASIC_INFORMATION64 {
    ULONGLONG   BaseAddress;
    ULONGLONG   AllocationBase;
    DWORD       AllocationProtect;
    DWORD       __alignment1;
    ULONGLONG   RegionSize;
    DWORD       State;
    DWORD       Protect;
    DWORD       Type;
    DWORD       __alignment2;
} MEMORY_BASIC_INFORMATION64, *PMEMORY_BASIC_INFORMATION64;
#if defined(_WIN64)
typedef MEMORY_BASIC_INFORMATION64  MEMORY_BASIC_INFORMATION;
typedef PMEMORY_BASIC_INFORMATION64 PMEMORY_BASIC_INFORMATION;
#else
typedef MEMORY_BASIC_INFORMATION32  MEMORY_BASIC_INFORMATION;
typedef PMEMORY_BASIC_INFORMATION32 PMEMORY_BASIC_INFORMATION;
#endif

#if defined(__cplusplus)
}
#endif

#endif /* ROSETTE_SHIMS_MACOS_WIN32_WINDOWS_BASE_H */
