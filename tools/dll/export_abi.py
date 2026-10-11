"""Per-name Windows ABI knowledge for `tools/generate_dll_export_tables.py`.

What each entry says, and why each field is here:

* ``convention`` - what the return value means. This is the field the
  heuristic in ``pkg/dll/win32/return-contract`` could only guess at, and the
  guess is why two thirds of a run's imports were classified ``unjudged``.
* ``zero`` - True when a zero return is a *meaningful answer* rather than the
  absence of one. ``memcmp`` returning zero means equal; ``WaitForSingleObject``
  returning zero is ``WAIT_OBJECT_0``. Marking these is what keeps the real
  refusals from being buried under the most frequent successful calls.
* ``arity`` - Microsoft x64 integer argument count, or None where nobody has
  checked. None rather than zero: zero is a real answer.

Conventions use the names in ``ReturnConvention``: void_call, bool32, handle,
invalid_handle, zero_count, lstatus, hresult, ntstatus, winsock_status.
"""

# A CRT function returning a computed value: zero is data, never a status.
VALUE = ("zero_count", True)
# A CRT function returning a pointer where NULL is failure.
PTR = ("handle", False)
# A CRT function returning a pointer where NULL is an ordinary "not found".
PTR_OPTIONAL = ("handle", True)
# Win32 BOOL where FALSE is failure.
BOOL = ("bool32", False)
# Win32 BOOL where FALSE is a legitimate negative answer.
BOOL_ANSWER = ("bool32", True)
# A count/length/index where zero is ordinary.
COUNT = ("zero_count", True)
# A count where zero means the call failed.
COUNT_FAILS_AT_ZERO = ("zero_count", False)
VOID = ("void_call", True)
HANDLE = ("handle", False)
INVALID_HANDLE = ("invalid_handle", False)
HRESULT = ("hresult", False)
LSTATUS = ("lstatus", False)
NTSTATUS = ("ntstatus", False)
WSA = ("winsock_status", False)

# name -> (convention, zero_is_an_answer, arity, note)
# Only names needing something other than the per-DLL default appear as
# overrides; the generator falls back to the DLL's default rule.
OVERRIDES = {}


def _add(names, shape, arity=None, note=""):
    convention, zero = shape
    for name in names:
        OVERRIDES[name] = (convention, zero, arity, note)


# ---------------------------------------------------------------- kernel32 --
# Synchronisation: the wait family's zero is WAIT_OBJECT_0, which is success.
# Reading it as failure made the single most frequent successful call in a
# Xenia run look like a refusal.
_add(["WaitForSingleObject", "WaitForSingleObjectEx"], COUNT, 2,
     "WAIT_OBJECT_0 is 0; WAIT_TIMEOUT is 258 and WAIT_FAILED is 0xFFFFFFFF")
_add(["WaitForMultipleObjects", "WaitForMultipleObjectsEx"], COUNT, 4,
     "returns WAIT_OBJECT_0 + index, so zero is the first object signalling")
_add(["SignalObjectAndWait"], COUNT, 4)
_add(["SleepEx"], COUNT, 2, "0 means the wait completed rather than being alerted")
_add(["Sleep"], VOID, 1)
_add(["SwitchToThread"], BOOL_ANSWER, 0, "FALSE means there was nobody else to run, which is an answer")
_add(["EnterCriticalSection", "LeaveCriticalSection", "DeleteCriticalSection",
      "InitializeCriticalSection", "InitializeSRWLock", "AcquireSRWLockExclusive",
      "AcquireSRWLockShared", "ReleaseSRWLockExclusive", "ReleaseSRWLockShared",
      "WakeAllConditionVariable", "WakeConditionVariable", "InitializeConditionVariable",
      "InitializeCriticalSectionAndSpinCount"], VOID)
_add(["TryEnterCriticalSection", "TryAcquireSRWLockExclusive", "TryAcquireSRWLockShared"],
     BOOL_ANSWER, 1, "FALSE means the lock was held, which is the answer the caller asked for")
_add(["SleepConditionVariableCS", "SleepConditionVariableSRW"], BOOL_ANSWER, None,
     "FALSE with ERROR_TIMEOUT is the timeout path, not a failure")

# Memory.
_add(["VirtualAlloc", "VirtualAllocEx", "MapViewOfFile", "MapViewOfFileEx",
      "HeapAlloc", "HeapReAlloc", "LocalAlloc", "LocalReAlloc", "GlobalAlloc",
      "GlobalReAlloc", "HeapCreate", "GetProcessHeap", "VirtualAllocFromApp"], HANDLE)
_add(["VirtualFree", "VirtualFreeEx", "VirtualProtect", "VirtualProtectEx",
      "UnmapViewOfFile", "HeapFree", "HeapDestroy", "HeapSetInformation",
      "FlushViewOfFile", "FlushInstructionCache", "GlobalMemoryStatusEx"], BOOL, None,
     "a BOOL where FALSE is failure; Rosette's memory is one flat permissive mapping, so these succeed")
_add(["VirtualQuery", "VirtualQueryEx"], COUNT_FAILS_AT_ZERO, None,
     "returns bytes written into MEMORY_BASIC_INFORMATION; zero is failure")
_add(["HeapSize"], COUNT_FAILS_AT_ZERO, 3, "returns (SIZE_T)-1 on failure")
_add(["GlobalLock", "GlobalUnlock"], PTR_OPTIONAL, 1)

# Handles and modules.
_add(["CreateFileA", "CreateFileW", "CreateFile2", "FindFirstFileA", "FindFirstFileW",
      "FindFirstFileExA", "FindFirstFileExW", "FindFirstVolumeW",
      "FindFirstChangeNotificationW"], INVALID_HANDLE)
_add(["CreateFileMappingA", "CreateFileMappingW", "OpenFileMappingW", "CreateEventA",
      "CreateEventW", "CreateEventExW", "CreateMutexA", "CreateMutexW",
      "CreateSemaphoreA", "CreateSemaphoreW", "CreateThread", "CreateWaitableTimerW",
      "CreateIoCompletionPort", "OpenProcess", "OpenThread", "LoadLibraryA",
      "LoadLibraryW", "LoadLibraryExA", "LoadLibraryExW", "GetModuleHandleA",
      "GetModuleHandleW", "GetCurrentProcess", "GetCurrentThread"], HANDLE)
_add(["GetProcAddress"], PTR, 2,
     "NULL is the documented answer for an export a module does not have, and libusb and SDL both probe with it")
_add(["GetStdHandle"], INVALID_HANDLE, 1)
_add(["CloseHandle", "FindClose", "FindVolumeClose", "FreeLibrary",
      "DuplicateHandle", "SetHandleInformation"], BOOL)
_add(["GetFileType"], COUNT_FAILS_AT_ZERO, 1, "FILE_TYPE_UNKNOWN is 0 and means the call failed")

# Errors, environment, misc.
_add(["GetLastError"], COUNT, 0, "the error code itself; zero is ERROR_SUCCESS")
_add(["SetLastError", "SetLastErrorEx"], VOID, None)
_add(["OutputDebugStringA", "OutputDebugStringW", "DebugBreak", "RaiseException",
      "ExitProcess", "ExitThread", "RtlUnwind", "RtlUnwindEx", "InitializeSListHead",
      "GetSystemTimeAsFileTime", "GetSystemTimePreciseAsFileTime", "GetLocalTime",
      "GetSystemTime", "GetSystemInfo", "GetNativeSystemInfo", "GetStartupInfoA",
      "GetStartupInfoW", "RtlCaptureContext", "RtlDeleteFunctionTable"], VOID)
_add(["IsDebuggerPresent"], BOOL_ANSWER, 0, "FALSE means no debugger, which is the answer")
_add(["IsProcessorFeaturePresent"], BOOL_ANSWER, 1, "FALSE means the feature is absent, which is the answer")
_add(["QueryPerformanceCounter", "QueryPerformanceFrequency"], BOOL)
_add(["GetTickCount", "GetTickCount64"], COUNT, 0)
_add(["GetCurrentProcessId", "GetCurrentThreadId", "GetThreadId", "GetProcessId"], COUNT_FAILS_AT_ZERO, None)
_add(["MulDiv"], VALUE, 3, "returns -1 on overflow, so zero is an ordinary result")
_add(["SetErrorMode"], COUNT, 1, "returns the previous mode; zero is a valid previous mode")
_add(["SetThreadExecutionState"], COUNT_FAILS_AT_ZERO, 1)
_add(["SetThreadAffinityMask"], COUNT_FAILS_AT_ZERO, 2, "returns the previous mask; zero is failure")
_add(["SuspendThread", "ResumeThread"], COUNT, 1, "returns the previous suspend count; (DWORD)-1 is failure")
_add(["RtlLookupFunctionEntry"], PTR_OPTIONAL, 3, "NULL means the address has no unwind data, which is normal for JIT output")
_add(["RtlVirtualUnwind"], PTR_OPTIONAL, 8)
_add(["RtlCaptureStackBackTrace"], COUNT, 4)
_add(["RtlInstallFunctionTableCallback", "RtlAddFunctionTable"], BOOL)
_add(["lstrlenA", "lstrlenW"], VALUE, 1)
_add(["CompareStringA", "CompareStringW", "CompareStringEx"], COUNT_FAILS_AT_ZERO, None,
     "returns CSTR_LESS_THAN/EQUAL/GREATER_THAN (1/2/3); zero is failure")
_add(["MultiByteToWideChar", "WideCharToMultiByte", "GetLocaleInfoA", "GetLocaleInfoW",
      "GetTimeZoneInformation", "GetModuleFileNameA", "GetModuleFileNameW",
      "GetSystemDirectoryA", "GetSystemDirectoryW", "GetWindowsDirectoryW",
      "GetTempPathW", "GetCurrentDirectoryW", "GetFullPathNameW", "GetLongPathNameW",
      "GetShortPathNameW", "GetFinalPathNameByHandleW", "GetEnvironmentVariableA",
      "GetEnvironmentVariableW", "ExpandEnvironmentStringsW", "GetVolumePathNameW",
      "K32GetModuleBaseNameA", "FormatMessageA", "FormatMessageW"],
     COUNT_FAILS_AT_ZERO, None,
     "returns characters written; zero means the call failed and GetLastError says why")
_add(["GetDiskFreeSpaceExW", "GetVolumeInformationW", "GetFileInformationByHandle",
      "GetFileTime", "SetFileTime", "GetFileSizeEx", "SetFilePointerEx",
      "ReadFile", "WriteFile", "FlushFileBuffers", "SetEndOfFile", "DeviceIoControl",
      "GetOverlappedResult", "PeekNamedPipe", "WaitNamedPipeW", "CancelIo", "CancelIoEx",
      "MoveFileExA", "MoveFileExW", "CopyFileW", "DeleteFileA", "DeleteFileW",
      "CreateDirectoryA", "CreateDirectoryW", "RemoveDirectoryW", "SetCurrentDirectoryW",
      "SetFileAttributesW", "CreateHardLinkW", "FindNextVolumeW",
      "GetQueuedCompletionStatus", "PostQueuedCompletionStatus",
      "GetConsoleMode", "SetConsoleMode", "GetConsoleScreenBufferInfo",
      "SetConsoleTextAttribute", "WriteConsoleW", "AllocConsole", "FreeConsole",
      "SetPriorityClass", "SetThreadPriority", "TerminateThread", "TerminateProcess",
      "GetExitCodeThread", "GetExitCodeProcess", "GetThreadContext", "SetThreadContext",
      "GetSystemPowerStatus", "EnumResourceNamesW", "QueryUserAPC"], BOOL)
_add(["FindNextFileA", "FindNextFileW"], BOOL_ANSWER, 2,
     "FALSE with ERROR_NO_MORE_FILES is how every directory walk ends")
_add(["GetFileAttributesA", "GetFileAttributesW"], COUNT, None,
     "INVALID_FILE_ATTRIBUTES is 0xFFFFFFFF; zero is a valid attribute set")
_add(["QueueUserAPC"], BOOL)

# ------------------------------------------------------------------ user32 --
# Almost all of USER32 is BOOL or a handle, but the exceptions matter: several
# of the most-called names return a value whose zero is ordinary, and reading
# those as refusals would fill a report with the message pump.
_add(["GetMessageA", "GetMessageW"], BOOL_ANSWER, 4,
     "returns FALSE for WM_QUIT, which is how every message loop ends, and -1 for a real error")
_add(["PeekMessageA", "PeekMessageW"], BOOL_ANSWER, 5, "FALSE means the queue was empty")
_add(["DispatchMessageA", "DispatchMessageW", "CallWindowProcA", "CallWindowProcW",
      "DefWindowProcA", "DefWindowProcW", "SendMessageA", "SendMessageW",
      "CallNextHookEx"], VALUE, None, "returns the window procedure's own result, which is arbitrary")
_add(["TranslateMessage", "PostMessageA", "PostMessageW", "PostThreadMessageW",
      "ShowWindow", "UpdateWindow", "MoveWindow", "SetWindowPos", "DestroyWindow",
      "InvalidateRect", "ValidateRect", "GetClientRect", "GetWindowRect",
      "AdjustWindowRect", "AdjustWindowRectEx", "ClientToScreen", "ScreenToClient",
      "SetWindowTextA", "SetWindowTextW", "EnableWindow", "IsWindowVisible",
      "BringWindowToTop", "SetForegroundWindow", "ShowCursor", "SetCursorPos",
      "GetCursorPos", "ClipCursor", "GetClipCursor", "TrackMouseEvent",
      "SystemParametersInfoA", "SystemParametersInfoW", "EnumDisplayDevicesW",
      "EnumDisplaySettingsW", "EnumDisplayMonitors", "GetMonitorInfoW",
      "OpenClipboard", "CloseClipboard", "EmptyClipboard", "SetLayeredWindowAttributes",
      "FlashWindowEx", "PtInRect", "IntersectRect", "UnhookWindowsHookEx",
      "KillTimer", "AttachThreadInput", "GetKeyboardState", "SetProcessDPIAware",
      "GetRawInputDeviceInfoA", "RegisterRawInputDevices", "UnregisterClassA",
      "UnregisterClassW", "GetClassInfoExW", "EndDialog", "SetWindowRgn"], BOOL)
_add(["IsIconic", "IsZoomed", "IsWindowEnabled", "IsClipboardFormatAvailable"], BOOL_ANSWER, None,
     "FALSE is the answer to a question, not a failure to answer it")
_add(["CreateWindowExA", "CreateWindowExW", "GetDC", "GetWindowDC", "BeginPaint",
      "LoadCursorA", "LoadCursorW", "LoadIconA", "LoadIconW", "LoadImageA", "LoadImageW",
      "SetCursor", "SetCapture", "GetCapture", "GetFocus", "SetFocus", "GetActiveWindow",
      "SetActiveWindow", "GetForegroundWindow", "GetDesktopWindow", "GetParent",
      "SetParent", "GetMenu", "GetDlgItem", "MonitorFromWindow", "MonitorFromPoint",
      "CreateIconIndirect", "CreateIconFromResource", "CopyImage", "GetClipboardData",
      "SetClipboardData", "SetWindowsHookExW", "GetKeyboardLayout",
      "DialogBoxIndirectParamW", "WindowFromPoint"], PTR_OPTIONAL, None,
     "NULL is a normal answer for a lookup that found nothing")
_add(["RegisterClassA", "RegisterClassW", "RegisterClassExA", "RegisterClassExW",
      "RegisterWindowMessageA", "RegisterWindowMessageW", "RegisterClipboardFormatW",
      "SetTimer", "GetWindowThreadProcessId", "MapVirtualKeyW", "GetDoubleClickTime",
      "GetClipboardSequenceNumber", "GetMessageTime", "GetMessageExtraInfo",
      "GetWindowTextLengthW", "GetWindowTextW", "MsgWaitForMultipleObjects",
      "ToUnicode", "DrawTextW", "FillRect", "MessageBoxA", "MessageBoxW",
      "ChangeDisplaySettingsExW", "SetWindowLongA", "SetWindowLongW",
      "SetWindowLongPtrA", "SetWindowLongPtrW", "GetWindowLongA", "GetWindowLongW",
      "GetWindowLongPtrA", "GetWindowLongPtrW", "GetSystemMetrics",
      "GetAsyncKeyState", "GetKeyState", "DestroyIcon", "DestroyCursor",
      "ReleaseCapture", "ReleaseDC", "EndPaint", "PostQuitMessage",
      "SetProcessDpiAwarenessContext"], COUNT, None)

# ------------------------------------------------------------------- gdi32 --
# GDI is a handle-and-BOOL surface. Rosette draws through Metal, so none of it
# is served; the point of declaring it is that a NULL device context is a
# refusal the guest branches on and must be visible as one.
_add(["CreateCompatibleDC", "CreateDCW", "CreateBitmap", "CreateCompatibleBitmap",
      "CreateDIBSection", "CreateFontIndirectW", "CreateFontW", "CreatePen",
      "CreateRectRgn", "CreateSolidBrush", "SelectObject", "GetStockObject"], PTR, None,
     "NULL is failure: the caller is about to draw through whatever it gets back")
_add(["DeleteDC", "DeleteObject", "BitBlt", "Rectangle", "ExtTextOutW",
      "GetTextExtentPoint32A", "GetTextExtentPoint32W", "GetTextMetricsW",
      "SetPixelFormat", "DescribePixelFormat", "SwapBuffers", "GetDeviceGammaRamp",
      "SetDeviceGammaRamp", "GetICMProfileW"], BOOL)
_add(["ChoosePixelFormat", "GetPixelFormat", "CombineRgn", "GetDIBits",
      "GetDeviceCaps", "SetBkMode", "SetTextColor"], COUNT_FAILS_AT_ZERO, None)

# ------------------------------------------------------------------- imm32 --
# The IME surface. Xenia touches it on every window message; none of it is
# reachable on macOS, and all of it has a documented "no IME" answer.
_add(["ImmGetContext", "ImmAssociateContext"], PTR_OPTIONAL, None,
     "NULL means no input context, which is the correct answer with no IME")
_add(["ImmReleaseContext", "ImmSetCompositionWindow", "ImmSetCandidateWindow",
      "ImmSetCompositionStringW", "ImmNotifyIME"], BOOL)
_add(["ImmGetCompositionStringW", "ImmGetCandidateListW", "ImmGetIMEFileNameA"],
     COUNT, None, "returns bytes copied; zero means nothing to copy, which is normal")

# --------------------------------------------------------------------- CRT --
# The C runtime is where a wrong answer is most dangerous. A refused Win32
# call tells the guest it failed; a CRT function that returns the wrong number
# is indistinguishable from one that returned the right one, and the guest
# carries it forward. Every one of these is a pure function Rosette can
# compute exactly, so `not_implemented` here is a correctness hazard rather
# than a missing feature.
_add(["acos", "asin", "atan", "atan2", "cbrt", "ceil", "cos", "cosh", "exp", "exp2",
      "exp2f", "expf", "fabs", "floor", "fmod", "frexp", "hypot", "ldexp", "log",
      "log10", "log2", "log2f", "logf", "modf", "nextafter", "pow", "powf", "scalbn",
      "sin", "sinh", "sqrt", "sqrtf", "tan", "tanh", "trunc", "round", "nanf",
      "lrintf", "_copysign", "_hypot", "_scalb"], VALUE, None,
     "a pure floating-point function: zero is a result, and a wrong answer is invisible to the guest")
_add(["_finite", "_isnan", "_isnanf", "isnan", "isinf"], BOOL_ANSWER, 1,
     "a predicate: FALSE is the answer")
_add(["__setusermatherr"], VOID, 1)

_add(["strlen", "wcslen", "strnlen", "wcsnlen", "strcspn", "strspn", "mbrlen",
      "wcscoll", "wcsxfrm", "strcoll", "strxfrm", "_strnicmp", "_stricmp",
      "_wcsicmp", "_wcsnicmp", "strcmp", "strncmp", "wcscmp", "wcsncmp", "memcmp"],
     VALUE, None, "a comparison or a length: zero means equal or empty, never failure")
_add(["strcpy", "strncpy", "strcat", "strncat", "wcscpy", "wcsncpy", "wcscat",
      "wcsncat", "memcpy", "memmove", "memset", "_strdup", "_wcsdup", "strtok",
      "strtok_s", "wcstok"], PTR_OPTIONAL, None,
     "returns its destination or NULL; the string family never sets errno")
_add(["strchr", "strrchr", "strstr", "wcschr", "wcsrchr", "wcsstr", "memchr"],
     PTR_OPTIONAL, None, "NULL means not found, which is the answer")
_add(["towlower", "towupper", "tolower", "toupper", "iswspace", "iswalpha",
      "iswdigit", "isalpha", "isdigit", "isspace", "isupper", "islower"], VALUE, 1)

_add(["atof", "atoi", "atol", "strtod", "strtof", "strtol", "strtoll", "strtoul",
      "strtoull", "wcstod", "wcstol", "wcstoul", "wcstoll", "wcstoull", "_atoi64",
      "_wtoi", "_wtoi64"], VALUE, None,
     "a conversion: zero is what an unparsable string produces and is a legitimate result")
_add(["mbrtowc", "wcrtomb", "mbstowcs", "wcstombs", "_ecvt_s", "_gcvt_s"], VALUE, None,
     "returns characters converted, or (size_t)-1 on an invalid sequence")
_add(["___mb_cur_max_func"], VALUE, 0)

_add(["clock", "time", "_time64", "_mktime64", "_mkgmtime64", "_tzset",
      "__daylight", "__timezone", "__tzname", "_wutime64"], VALUE, None,
     "a time value or a pointer to one; (time_t)-1 is the failure value, not zero")
_add(["_gmtime64", "_localtime64", "_gmtime64_s", "_localtime64_s"], PTR_OPTIONAL, None)
_add(["strftime", "wcsftime"], COUNT, None,
     "returns characters written, and zero means the buffer was too small - which callers probe for deliberately")

_add(["malloc", "calloc", "realloc", "_recalloc", "_aligned_malloc",
      "_aligned_realloc", "_malloc_base", "_expand"], PTR, None)
_add(["free", "_aligned_free", "_free_base"], VOID, 1)
_add(["_msize"], VALUE, 1)

_add(["fopen", "_wfopen"], PTR, None)
_add(["fopen_s", "_wfopen_s"], COUNT, 3,
     "returns errno_t; zero is success and the FILE* is written through the first argument")
_add(["freopen_s"], COUNT, 4,
     "returns errno_t; zero is success and the FILE* is written through the first argument")
_add(["_sopen", "_wsopen"], COUNT, 4,
     "returns a CRT descriptor; zero is a valid descriptor and -1 is failure")
_add(["_wopen", "_open"], COUNT, 2,
     "returns a CRT descriptor; zero is a valid descriptor and -1 is failure")
_add(["_open_osfhandle"], COUNT, 2,
     "returns a CRT descriptor; zero is a valid descriptor and -1 is failure")
_add(["_get_osfhandle"], HANDLE, 1,
     "returns the underlying guest handle, or -1 when the descriptor is invalid")
_add(["fclose", "fflush", "fgetpos", "fsetpos", "ferror", "feof", "_fseeki64",
      "_ftelli64", "_telli64", "rewind", "setvbuf"], VALUE, None,
     "a stdio status where zero is success and EOF (-1) is failure")
_add(["fread", "fwrite"], COUNT, None, "returns items transferred; zero is a short read, not a failure")
_add(["fgetc", "getc", "getwc", "fgetwc", "fputc", "putc", "putwc", "fputwc",
      "ungetc", "ungetwc", "_isatty"], VALUE, None, "returns the character or EOF")
_add(["fgets", "fgetws", "fputs", "fputws"], PTR_OPTIONAL, None)
_add(["__stdio_common_vfprintf", "__stdio_common_vfwprintf", "__stdio_common_vsprintf",
      "__stdio_common_vswprintf", "__stdio_common_vsnprintf_s", "_snprintf",
      "_vsnprintf", "vsnprintf", "sprintf", "snprintf", "fprintf", "printf"],
     VALUE, None, "returns characters written, or negative on error; zero is an empty result")

_add(["_access", "_waccess", "_wchdir", "_wchmod", "_wfullpath", "_wgetcwd",
      "_findclose", "_wfindfirst64i32", "_wfindnext64i32", "_wunlink", "_wrename",
      "_wmkdir", "_wrmdir", "_wstat64i32"], VALUE, None,
     "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer")
_add(["_get_errno", "_set_errno"], VALUE, 1,
     "returns errno_t; zero is success and the errno value is read or written through the argument")
_add(["_errno", "_doserrno"], VALUE, None)
_add(["_assert", "abort", "exit", "_exit", "quick_exit", "atexit"], VOID, None)
_add(["_crt_at_quick_exit", "_crt_atexit"], VALUE, 1,
     "returns errno_t: zero registers the guest callback, nonzero rejects it")
_add(["bsearch", "qsort"], PTR_OPTIONAL, None, "bsearch returns NULL when the key is absent, which is the answer")
_add(["rand_s"], VALUE, 1, "returns an errno_t: zero is success")

# ------------------------------------------------------------ small surfaces --
_add(["SysFreeString"], VOID, 1)
_add(["SysAllocString", "SysAllocStringLen"], PTR, None)
_add(["SysStringLen"], VALUE, 1)
_add(["QISearch"], HRESULT, 4)
_add(["GetFileVersionInfoA", "GetFileVersionInfoW", "VerQueryValueA", "VerQueryValueW"], BOOL)
_add(["GetFileVersionInfoSizeA", "GetFileVersionInfoSizeW"], COUNT_FAILS_AT_ZERO, 2)
_add(["CM_Get_Device_IDA", "CM_Get_Parent", "CM_Locate_DevNodeA", "CM_Get_Device_IDW",
      "CM_Get_DevNode_Status"], NTSTATUS, None,
     "a CONFIGRET, which shares NTSTATUS' shape: CR_SUCCESS is zero")
_add(["SetupDiEnumDeviceInfo", "SetupDiEnumDeviceInterfaces",
      "SetupDiGetDeviceInterfaceDetailA", "SetupDiGetDeviceRegistryPropertyA",
      "SetupDiDestroyDeviceInfoList"], BOOL)
_add(["SetupDiGetClassDevsA", "SetupDiGetClassDevsW"], INVALID_HANDLE, 4)
_add(["waveInOpen", "waveInClose", "waveInAddBuffer", "waveInPrepareHeader",
      "waveInUnprepareHeader", "waveInReset", "waveInStart", "waveInStop",
      "waveInGetDevCapsW", "waveOutOpen", "waveOutClose", "waveOutWrite",
      "waveOutPrepareHeader", "waveOutUnprepareHeader", "waveOutReset",
      "waveOutPause", "waveOutRestart", "waveOutGetDevCapsW", "waveOutSetVolume",
      "waveOutGetVolume", "waveOutGetPosition", "timeBeginPeriod", "timeEndPeriod",
      "timeGetDevCaps"], COUNT, None,
     "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error")
_add(["timeGetTime"], COUNT, 0)
_add(["DwmSetWindowAttribute", "DwmExtendFrameIntoClientArea", "DwmFlush"], HRESULT, None)

# ---------------------------------------------------------------- winsock --
# The Winsock BSD surface. Everything here uses SOCKET_ERROR (-1), not zero,
# so a zero from `recv` means the peer closed and a zero from `bind` means it
# worked - opposite readings under one spelling family, which is exactly the
# case a per-name declaration exists for.
_add(["socket", "accept"], INVALID_HANDLE, None, "INVALID_SOCKET is (SOCKET)-1, not NULL")
_add(["bind", "connect", "listen", "shutdown", "closesocket", "getsockname",
      "getsockopt", "setsockopt", "ioctlsocket"], VALUE, None,
     "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal")
_add(["recv", "recvfrom"], VALUE, None,
     "returns bytes received; zero means the peer performed an orderly shutdown, which is an answer")
_add(["send", "sendto"], VALUE, None, "returns bytes sent; -1 is SOCKET_ERROR")
_add(["select"], VALUE, 5, "returns ready descriptors; zero means the timeout expired")
_add(["htonl", "ntohl", "htons", "ntohs", "inet_addr"], VALUE, 1, "a pure byte-order or parse conversion")
_add(["__WSAFDIsSet"], BOOL_ANSWER, 2)
_add(["WSAGetLastError"], VALUE, 0, "the error code itself; zero means no error")
_add(["WSAStartup", "WSACleanup"], WSA, None)

# ---------------------------------------------------------------- registry --
# Xenia keeps its persistent flags here. Every one of these is an LSTATUS, so
# zero is ERROR_SUCCESS and the value carries the reason.
_add(["RegOpenKeyA", "RegOpenKeyW", "RegOpenKeyExA", "RegOpenKeyExW",
      "RegCreateKeyA", "RegCreateKeyW", "RegCreateKeyExA", "RegCreateKeyExW",
      "RegQueryValueExA", "RegQueryValueExW", "RegSetValueExA", "RegSetValueExW",
      "RegGetValueA", "RegGetValueW", "RegCloseKey", "RegFlushKey",
      "RegDeleteValueW", "RegEnumKeyExW", "RegEnumValueW"], LSTATUS, None)
_add(["OpenProcessToken", "AdjustTokenPrivileges", "LookupPrivilegeValueW"], BOOL)

# --------------------------------------------------------------- COM/shell --
_add(["CoInitializeEx", "CoCreateInstance", "CLSIDFromString", "PropVariantClear",
      "SHGetKnownFolderPath", "SHGetFolderPathW"], HRESULT, None)
_add(["CoUninitialize", "CoTaskMemFree", "DragAcceptFiles", "DragFinish"], VOID, None)
_add(["CommandLineToArgvW"], PTR, 2)
_add(["DragQueryFileW"], COUNT, 4, "returns characters copied, or the file count when the index is 0xFFFFFFFF")
_add(["ShellExecuteW"], VALUE, 6, "returns a pseudo-HINSTANCE; a value above 32 is success")

# ---------------------------------------------------------------- bcrypt --
_add(["BCryptOpenAlgorithmProvider", "BCryptCloseAlgorithmProvider", "BCryptGenRandom"],
     NTSTATUS, None, "STATUS_SUCCESS is zero; Xenia uses this only as an entropy source")

# ------------------------------------------------------------- CRT runtime --
# The `__p_*` family return pointers to the CRT's own globals. A NULL from any
# of them is dereferenced immediately by the caller, so they are the most
# dangerous refusals in the whole surface.
_add(["__p___argc", "__p___argv", "__p___wargv", "__p__wcmdln", "__p__commode",
      "__p__fmode", "__p__environ", "__p__wenviron", "__acrt_iob_func",
      "_errno", "localeconv"], PTR, None,
     "returns a pointer to a CRT global the caller dereferences without checking; NULL is a guest crash")
_add(["_get_wpgmptr"], VALUE, 1,
     "returns errno_t; zero is success and writes the guest-owned executable path through wchar_t**")
_add(["_initterm"], VOID, 2)
_add(["_initterm_e"], VALUE, 2,
     "returns the first nonzero initializer result")
_add(["_cexit"], VOID)
_add(["_configure_narrow_argv",
      "_configure_wide_argv", "_initialize_narrow_environment",
      "_initialize_wide_environment", "_set_app_type", "_set_new_mode", "_set_invalid_parameter_handler",
      "_lock_file", "_unlock_file"], VALUE, None,
     "a CRT bootstrap hook whose zero is success or is ignored entirely")
_add(["_register_thread_local_exe_atexit_callback"], VOID, 1,
     "stores one guest TLS-exit callback; it is invoked with DLL_PROCESS_DETACH during full CRT cleanup")
_add(["_beginthreadex"], PTR, 6)
_add(["_endthreadex", "longjmp"], VOID, None)
_add(["_setjmp"], VALUE, 2, "returns zero on the direct call and non-zero when longjmp resumes it - both are answers")
_add(["signal"], PTR_OPTIONAL, 2, "returns the previous handler, or SIG_ERR (-1)")
_add(["strerror", "asctime"], PTR_OPTIONAL, 1)
_add(["setlocale"], PTR_OPTIONAL, 2, "NULL means the locale could not be set, which callers probe for")
_add(["getenv"], PTR_OPTIONAL, 1, "NULL means the variable is unset, which is the answer")
_add(["SetEnvironmentVariableA", "SetEnvironmentVariableW"], BOOL)

# ---------------------------------------------------------------- CRT I/O --
_add(["_close", "_fileno", "_read", "_write", "_lseeki64", "_filelengthi64",
      "_chsize_s", "fseek", "ftell", "puts", "_fstat64", "_wstat64",
      "_fdopen", "_setmode"], VALUE, None,
     "a POSIX-shaped stdio status or count where -1 is the failure value, not zero")
_add(["_strrev", "_ultoa", "_itoa", "_i64toa", "_ui64toa"], PTR_OPTIONAL, None)
_add(["btowc", "wctob", "iswctype", "wctype", "isalnum", "isblank", "iscntrl",
      "isgraph", "isprint", "ispunct", "isxdigit"], VALUE, None,
     "a character classification: zero means the predicate is false, which is the answer")
_add(["llrint", "llrintf"], VALUE, 1)

# --------------------------------------------------------------- remaining --
_add(["waveInGetNumDevs", "waveOutGetNumDevs"], COUNT, 0,
     "returns the device count; zero means no devices, which is an answer and not a failure")
_add(["waveOutGetErrorTextW"], COUNT, 3, "an MMRESULT: zero is MMSYSERR_NOERROR")
_add(["PlaySoundW"], BOOL, 3)
_add(["CreateDXGIFactory1", "CreateDXGIFactory2"], HRESULT, None)
_add(["TlsAlloc"], COUNT_FAILS_AT_ZERO, 0, "TLS_OUT_OF_INDEXES is 0xFFFFFFFF; index 0 is valid, so zero is a real slot")
_add(["TlsGetValue"], PTR_OPTIONAL, 1, "NULL is a legitimate stored value; the caller checks GetLastError to tell them apart")
_add(["TlsSetValue", "TlsFree", "SetEvent", "ResetEvent", "ReleaseMutex",
      "ReleaseSemaphore", "SetWaitableTimer", "CancelWaitableTimer",
      "CreateTimerQueueTimer", "DeleteTimerQueueTimer", "GetProcessAffinityMask",
      "SetProcessAffinityMask", "GetHandleInformation", "GetFileAttributesExW",
      "K32GetModuleInformation", "GetModuleHandleExW", "InitOnceBeginInitialize",
      "InitOnceComplete", "VerifyVersionInfoA", "VerifyVersionInfoW",
      "GetVersionExA", "AttachConsole", "GetUpdateRect", "GetWindowPlacement",
      "SetWindowPlacement", "SetMenu", "SetMenuInfo", "GetMenuInfo", "DrawMenuBar",
      "EnableMenuItem", "AppendMenuW", "DestroyMenu", "SetPropW", "DragQueryPoint",
      "RegisterDeviceNotificationW", "UnregisterDeviceNotification",
      "GetRawInputDeviceList"], BOOL)
_add(["CreateWaitableTimerA", "CreateMenu", "CreatePopupMenu",
      "CreateIconFromResourceEx", "GetPropW", "RemovePropW", "LocalFree",
      "GlobalFree", "AddVectoredExceptionHandler",
      "SetUnhandledExceptionFilter"], PTR_OPTIONAL, None)
_add(["RemoveVectoredExceptionHandler", "RemoveVectoredContinueHandler"], COUNT, 1)
_add(["GetFileSize"], COUNT, 2, "INVALID_FILE_SIZE is 0xFFFFFFFF; a zero-length file really is zero")
_add(["SetFilePointer"], COUNT, 4, "INVALID_SET_FILE_POINTER is 0xFFFFFFFF; offset zero is the start of the file")
_add(["GetThreadPriority"], VALUE, 1, "THREAD_PRIORITY_ERROR_RETURN is 0x7FFFFFFF; zero is THREAD_PRIORITY_NORMAL")
_add(["GlobalAddAtomW"], COUNT_FAILS_AT_ZERO, 1)
_add(["GlobalDeleteAtom"], COUNT, 1, "returns zero on success, so a zero here is the opposite of a refusal")
_add(["GetClassLongPtrW"], COUNT, 2)
_add(["MonitorFromRect"], PTR_OPTIONAL, 2)
_add(["VkKeyScanW"], VALUE, 1, "returns -1 when the character has no key; the low byte is the key code")
_add(["VerSetConditionMask"], VALUE, 3)
_add(["__C_specific_handler"], VALUE, 4, "returns an EXCEPTION_DISPOSITION; every value including zero is meaningful")
_add(["GetCommandLineA", "GetCommandLineW"], PTR, 0)
_add(["GetRawInputData"], COUNT, 5,
     "returns bytes copied, or (UINT)-1 on error; a zero-size query is how the caller sizes its buffer")

# Names whose Rosette handler reaches a real host resource, rather than
# answering from a model it keeps itself. The distinction is the difference
# between "the guest's file was opened" and "the guest was handed a handle
# Rosette invented", and only a person can draw it.
SERVED = set("""
CreateFileA CreateFileW CreateFile2 ReadFile WriteFile CloseHandle SetFilePointerEx
GetFileSizeEx FlushFileBuffers SetEndOfFile DeleteFileA DeleteFileW CopyFileW
CreateDirectoryA CreateDirectoryW FindFirstFileA FindFirstFileW FindNextFileA
FindNextFileW FindClose GetFileAttributesA GetFileAttributesW SetCurrentDirectoryW
GetCurrentDirectoryW GetFullPathNameW GetTempPathW GetModuleFileNameA GetModuleFileNameW
GetSystemDirectoryA GetSystemDirectoryW GetWindowsDirectoryW
VirtualAlloc VirtualAllocEx VirtualFree VirtualFreeEx VirtualProtect VirtualProtectEx
VirtualQuery VirtualQueryEx HeapAlloc HeapReAlloc HeapFree HeapSize
malloc calloc realloc free _aligned_malloc _aligned_free _recalloc _msize
QueryPerformanceCounter QueryPerformanceFrequency GetSystemTimeAsFileTime
GetSystemTimePreciseAsFileTime GetTickCount GetTickCount64 timeGetTime
waveOutOpen waveOutClose waveOutWrite waveOutPrepareHeader waveOutUnprepareHeader
waveOutReset waveOutGetDevCapsW waveOutGetNumDevs
CreateThread ExitThread GetCurrentThreadId GetCurrentThread SetThreadDescription
""".split())

# Reached through GetProcAddress rather than the import table: hidapi and
# libusb resolve these by name after loading setupapi themselves.
_add(["SetupDiGetDeviceInstanceIdA", "SetupDiGetDeviceInstanceIdW"], BOOL, 5)
_add(["SetupDiOpenDevRegKey", "SetupDiOpenDeviceInterfaceRegKey"], INVALID_HANDLE, None,
     "returns a registry key or INVALID_HANDLE_VALUE, not NULL")
