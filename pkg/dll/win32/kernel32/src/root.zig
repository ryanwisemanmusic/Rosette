//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

pub const dll_name = "KERNEL32.dll";
pub const stem = "kernel32";
pub const match_prefix = "";
pub const subsystem_name = "kernel";

pub const degraded_imports = [_][]const u8{
    "AcquireSRWLockExclusive",
    "AddVectoredExceptionHandler",
    "AllocConsole",
    "CancelIo",
    "CancelIoEx",
    "CancelWaitableTimer",
    "CompareStringA",
    "CreateDirectoryW",
    "CreateHardLinkW",
    "CreateIoCompletionPort",
    "CreateWaitableTimerA",
    "CreateWaitableTimerW",
    "DeviceIoControl",
    "DuplicateHandle",
    "EnumResourceNamesW",
    "ExitProcess",
    "FindFirstVolumeW",
    "FindNextVolumeW",
    "FindVolumeClose",
    "FlushInstructionCache",
    "FlushViewOfFile",
    "GetConsoleMode",
    "GetConsoleScreenBufferInfo",
    "GetDiskFreeSpaceExW",
    "GetFileInformationByHandle",
    "GetFileTime",
    "GetFileType",
    "GetLocaleInfoA",
    "GetModuleHandleExW",
    "GetOverlappedResult",
    "GetProcessAffinityMask",
    "GetStartupInfoW",
    "GetStdHandle",
    "GetSystemPowerStatus",
    "GetThreadContext",
    "GetThreadId",
    "GetThreadPriority",
    "GetTimeZoneInformation",
    "GetVolumeInformationW",
    "GlobalLock",
    "GlobalMemoryStatusEx",
    "GlobalUnlock",
    "InitializeConditionVariable",
    "InitializeSRWLock",
    "InitOnceBeginInitialize",
    "InitOnceComplete",
    "K32GetModuleBaseNameA",
    "K32GetModuleInformation",
    "lstrlenW",
    "MoveFileExA",
    "MoveFileExW",
    "MulDiv",
    "OpenProcess",
    "OutputDebugStringA",
    "OutputDebugStringW",
    "PeekNamedPipe",
    "QueueUserAPC",
    "RaiseException",
    "ReleaseSRWLockExclusive",
    "RemoveDirectoryW",
    "RemoveVectoredContinueHandler",
    "RemoveVectoredExceptionHandler",
    "ResumeThread",
    "RtlCaptureContext",
    "RtlCaptureStackBackTrace",
    "RtlDeleteFunctionTable",
    "RtlInstallFunctionTableCallback",
    "RtlLookupFunctionEntry",
    "RtlUnwindEx",
    "RtlVirtualUnwind",
    "SetConsoleTextAttribute",
    "SetErrorMode",
    "SetFileAttributesW",
    "SetPriorityClass",
    "SetProcessAffinityMask",
    "SetThreadAffinityMask",
    "SetThreadExecutionState",
    "SetThreadPriority",
    "SetWaitableTimer",
    "SignalObjectAndWait",
    "SleepConditionVariableCS",
    "SleepConditionVariableSRW",
    "SuspendThread",
    "TerminateProcess",
    "TerminateThread",
    "TryAcquireSRWLockExclusive",
    "VerifyVersionInfoA",
    "VerifyVersionInfoW",
    "VerSetConditionMask",
    "WaitNamedPipeW",
    "WakeAllConditionVariable",
    "WakeConditionVariable",
    "WriteConsoleW",
};

pub fn matches(name: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(name, stem)) return true;
    return name.len == stem.len + 4 and
        std.ascii.eqlIgnoreCase(name[0..stem.len], stem) and
        std.ascii.eqlIgnoreCase(name[stem.len..], ".dll");
}

pub fn hasDegradedImport(function_name: []const u8) bool {
    for (degraded_imports) |known| {
        if (std.mem.eql(u8, function_name, known)) return true;
    }
    return false;
}

test "DLL identity is case-insensitive and the degraded inventory is local" {
    try std.testing.expect(matches("KERNEL32.dll"));
    try std.testing.expect(matches("kernel32"));
    try std.testing.expect(hasDegradedImport("AcquireSRWLockExclusive"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}

// --- generated export table: tools/dll/generate_export_tables.py ---
/// Every name this image imports from KERNEL32.dll, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{
    .{ .name = "AcquireSRWLockExclusive", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "AddVectoredExceptionHandler", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "AllocConsole", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "AttachConsole", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CancelIo", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "CancelIoEx", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "CancelWaitableTimer", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CloseHandle", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "CompareStringA", .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "returns CSTR_LESS_THAN/EQUAL/GREATER_THAN (1/2/3); zero is failure" },
    .{ .name = "CreateDirectoryW", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "CreateEventA", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CreateEventW", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CreateFileA", .convention = .invalid_handle, .behaviour = .served, .reviewed = true },
    .{ .name = "CreateFileMappingW", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CreateFileW", .convention = .invalid_handle, .behaviour = .served, .reviewed = true },
    .{ .name = "CreateHardLinkW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "CreateIoCompletionPort", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CreateMutexW", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CreateSemaphoreA", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CreateSemaphoreW", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CreateThread", .convention = .handle, .behaviour = .served, .reviewed = true },
    .{ .name = "CreateTimerQueueTimer", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CreateWaitableTimerA", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "CreateWaitableTimerW", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "DeleteCriticalSection", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "DeleteFileW", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "DeleteTimerQueueTimer", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "DeviceIoControl", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "DuplicateHandle", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "EnterCriticalSection", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "EnumResourceNamesW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "ExitProcess", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "ExitThread", .convention = .void_call, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "FindClose", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "FindFirstFileW", .convention = .invalid_handle, .behaviour = .served, .reviewed = true },
    .{ .name = "FindFirstVolumeW", .convention = .invalid_handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "FindNextFileW", .arity = 2, .convention = .bool32, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "FALSE with ERROR_NO_MORE_FILES is how every directory walk ends" },
    .{ .name = "FindNextVolumeW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "FindVolumeClose", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "FlushFileBuffers", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "FlushInstructionCache", .convention = .bool32, .behaviour = .modelled, .reviewed = true, .note = "a BOOL where FALSE is failure; Rosette's memory is one flat permissive mapping, so these succeed" },
    .{ .name = "FlushViewOfFile", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "a BOOL where FALSE is failure; Rosette's memory is one flat permissive mapping, so these succeed" },
    .{ .name = "FormatMessageA", .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "FormatMessageW", .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "FreeLibrary", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetCommandLineW", .arity = 0, .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetConsoleMode", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetConsoleScreenBufferInfo", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetCurrentProcess", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetCurrentProcessId", .convention = .zero_count, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetCurrentThread", .convention = .handle, .behaviour = .served, .reviewed = true },
    .{ .name = "GetCurrentThreadId", .convention = .zero_count, .behaviour = .served, .reviewed = true },
    .{ .name = "GetDiskFreeSpaceExW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetEnvironmentVariableA", .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "GetFileAttributesExW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetFileAttributesW", .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "INVALID_FILE_ATTRIBUTES is 0xFFFFFFFF; zero is a valid attribute set" },
    .{ .name = "GetFileInformationByHandle", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetFileSize", .arity = 2, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "INVALID_FILE_SIZE is 0xFFFFFFFF; a zero-length file really is zero" },
    .{ .name = "GetFileSizeEx", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "GetFileTime", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetFileType", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "FILE_TYPE_UNKNOWN is 0 and means the call failed" },
    .{ .name = "GetFullPathNameW", .convention = .zero_count, .behaviour = .served, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "GetHandleInformation", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetLastError", .arity = 0, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "the error code itself; zero is ERROR_SUCCESS" },
    .{ .name = "GetLocaleInfoA", .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "GetModuleFileNameA", .convention = .zero_count, .behaviour = .served, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "GetModuleFileNameW", .convention = .zero_count, .behaviour = .served, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "GetModuleHandleA", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetModuleHandleExW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetModuleHandleW", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetOverlappedResult", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "GetProcAddress", .arity = 2, .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "NULL is the documented answer for an export a module does not have, and libusb and SDL both probe with it" },
    .{ .name = "GetProcessAffinityMask", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetQueuedCompletionStatus", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetStartupInfoW", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetStdHandle", .arity = 1, .convention = .invalid_handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetSystemDirectoryA", .convention = .zero_count, .behaviour = .served, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "GetSystemInfo", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetSystemPowerStatus", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetSystemTimeAsFileTime", .convention = .void_call, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetTempPathW", .convention = .zero_count, .behaviour = .served, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "GetThreadContext", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "GetThreadId", .convention = .zero_count, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetThreadPriority", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "THREAD_PRIORITY_ERROR_RETURN is 0x7FFFFFFF; zero is THREAD_PRIORITY_NORMAL" },
    .{ .name = "GetTickCount", .arity = 0, .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetTickCount64", .arity = 0, .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetTimeZoneInformation", .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "GetVersionExA", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetVolumeInformationW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GlobalAddAtomW", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GlobalAlloc", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GlobalDeleteAtom", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns zero on success, so a zero here is the opposite of a refusal" },
    .{ .name = "GlobalFree", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GlobalLock", .arity = 1, .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GlobalMemoryStatusEx", .convention = .bool32, .behaviour = .modelled, .reviewed = true, .note = "a BOOL where FALSE is failure; Rosette's memory is one flat permissive mapping, so these succeed" },
    .{ .name = "GlobalUnlock", .arity = 1, .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "InitOnceBeginInitialize", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "InitOnceComplete", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "InitializeConditionVariable", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "InitializeCriticalSection", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "InitializeCriticalSectionAndSpinCount", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "InitializeSRWLock", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "IsDebuggerPresent", .arity = 0, .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "FALSE means no debugger, which is the answer" },
    .{ .name = "K32GetModuleBaseNameA", .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "K32GetModuleInformation", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "LeaveCriticalSection", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "LoadLibraryA", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "LoadLibraryExW", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "LoadLibraryW", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "LocalFree", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "MapViewOfFile", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "MapViewOfFileEx", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "MoveFileExA", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "MoveFileExW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "MulDiv", .arity = 3, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns -1 on overflow, so zero is an ordinary result" },
    .{ .name = "MultiByteToWideChar", .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "OpenProcess", .convention = .handle, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "OutputDebugStringA", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "OutputDebugStringW", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "PeekNamedPipe", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "PostQueuedCompletionStatus", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "QueryPerformanceCounter", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "QueryPerformanceFrequency", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "QueueUserAPC", .convention = .bool32, .behaviour = .modelled, .reviewed = true, .note = "queued to the target thread and run inside its next alertable wait, which then answers WAIT_IO_COMPLETION; a thread already blocked in one is woken to run it" },
    .{ .name = "RaiseException", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "ReadFile", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "ReleaseMutex", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "ReleaseSRWLockExclusive", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "ReleaseSemaphore", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "RemoveDirectoryW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "RemoveVectoredContinueHandler", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "RemoveVectoredExceptionHandler", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "ResetEvent", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "ResumeThread", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the previous suspend count; (DWORD)-1 is failure" },
    .{ .name = "RtlCaptureContext", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "RtlCaptureStackBackTrace", .arity = 4, .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "RtlDeleteFunctionTable", .convention = .void_call, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "RtlInstallFunctionTableCallback", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "RtlLookupFunctionEntry", .arity = 3, .convention = .handle, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "NULL means the address has no unwind data, which is normal for JIT output" },
    .{ .name = "RtlUnwindEx", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "RtlVirtualUnwind", .arity = 8, .convention = .handle, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetConsoleTextAttribute", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetEndOfFile", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "SetEnvironmentVariableA", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetErrorMode", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the previous mode; zero is a valid previous mode" },
    .{ .name = "SetEvent", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetFileAttributesW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetFilePointer", .arity = 4, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "INVALID_SET_FILE_POINTER is 0xFFFFFFFF; offset zero is the start of the file" },
    .{ .name = "SetFilePointerEx", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "SetLastError", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "SetPriorityClass", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetProcessAffinityMask", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetThreadAffinityMask", .arity = 2, .convention = .zero_count, .behaviour = .refused_by_policy, .reviewed = true, .note = "returns the previous mask; zero is failure" },
    .{ .name = "SetThreadContext", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetThreadExecutionState", .arity = 1, .convention = .zero_count, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetThreadPriority", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetUnhandledExceptionFilter", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "SetWaitableTimer", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SignalObjectAndWait", .arity = 4, .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "Sleep", .arity = 1, .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "SleepConditionVariableCS", .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "FALSE with ERROR_TIMEOUT is the timeout path, not a failure" },
    .{ .name = "SleepConditionVariableSRW", .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "FALSE with ERROR_TIMEOUT is the timeout path, not a failure" },
    .{ .name = "SleepEx", .arity = 2, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "0 means the wait completed rather than being alerted" },
    .{ .name = "SuspendThread", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the previous suspend count; (DWORD)-1 is failure. The cooperative scheduler does not run a thread whose count is non-zero" },
    .{ .name = "TerminateProcess", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "TerminateThread", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "TlsAlloc", .arity = 0, .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "TLS_OUT_OF_INDEXES is 0xFFFFFFFF; index 0 is valid, so zero is a real slot" },
    .{ .name = "TlsFree", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "TlsGetValue", .arity = 1, .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a legitimate stored value; the caller checks GetLastError to tell them apart" },
    .{ .name = "TlsSetValue", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "TryAcquireSRWLockExclusive", .arity = 1, .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "FALSE means the lock was held, which is the answer the caller asked for" },
    .{ .name = "TryEnterCriticalSection", .arity = 1, .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "FALSE means the lock was held, which is the answer the caller asked for" },
    .{ .name = "UnmapViewOfFile", .convention = .bool32, .behaviour = .modelled, .reviewed = true, .note = "a BOOL where FALSE is failure; Rosette's memory is one flat permissive mapping, so these succeed" },
    .{ .name = "VerSetConditionMask", .arity = 3, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "VerifyVersionInfoA", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "VerifyVersionInfoW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "VirtualAlloc", .convention = .handle, .behaviour = .served, .reviewed = true },
    .{ .name = "VirtualFree", .convention = .bool32, .behaviour = .served, .reviewed = true, .note = "a BOOL where FALSE is failure; Rosette's memory is one flat permissive mapping, so these succeed" },
    .{ .name = "VirtualProtect", .convention = .bool32, .behaviour = .served, .reviewed = true, .note = "a BOOL where FALSE is failure; Rosette's memory is one flat permissive mapping, so these succeed" },
    .{ .name = "VirtualQuery", .convention = .zero_count, .behaviour = .served, .reviewed = true, .note = "returns bytes written into MEMORY_BASIC_INFORMATION; zero is failure" },
    .{ .name = "WaitForMultipleObjects", .arity = 4, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns WAIT_OBJECT_0 + index, so zero is the first object signalling" },
    .{ .name = "WaitForMultipleObjectsEx", .arity = 4, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns WAIT_OBJECT_0 + index, so zero is the first object signalling" },
    .{ .name = "WaitForSingleObject", .arity = 2, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "WAIT_OBJECT_0 is 0; WAIT_TIMEOUT is 258 and WAIT_FAILED is 0xFFFFFFFF" },
    .{ .name = "WaitForSingleObjectEx", .arity = 2, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "WAIT_OBJECT_0 is 0; WAIT_TIMEOUT is 258 and WAIT_FAILED is 0xFFFFFFFF" },
    .{ .name = "WaitNamedPipeW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "WakeAllConditionVariable", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "WakeConditionVariable", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "WideCharToMultiByte", .convention = .zero_count, .behaviour = .modelled, .reviewed = true, .note = "returns characters written; zero means the call failed and GetLastError says why" },
    .{ .name = "WriteConsoleW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "WriteFile", .convention = .bool32, .behaviour = .served, .reviewed = true },
    .{ .name = "__C_specific_handler", .arity = 4, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns an EXCEPTION_DISPOSITION; every value including zero is meaningful" },
    .{ .name = "lstrlenW", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
};

pub const surface = export_contract.Surface{
    .dll_name = dll_name,
    .stem = stem,
    .exports = &exports,
};

/// What this library's ABI says about one export, or null when the image does
/// not import it. Null is a real answer: it means the guest cannot reach this
/// name through the import table, whatever else it might do.
pub fn findExport(function_name: []const u8) ?export_contract.Export {
    return surface.find(function_name);
}

test "the declared surface is complete, unique, and agrees with itself" {
    try std.testing.expect(exports.len != 0);
    try std.testing.expect(!export_contract.hasDuplicate(&exports));
    for (exports) |entry| {
        try std.testing.expect(entry.name.len != 0);
        if (entry.arity) |arity| try std.testing.expect(arity <= export_contract.max_declared_arity);
        // A name declared here must also be findable, or `findExport` and the
        // table would disagree about the same library.
        try std.testing.expect(findExport(entry.name) != null);
    }
    try std.testing.expectEqual(@as(?export_contract.Export, null), findExport("__not_in_this_dll__"));
    // Every degraded name is part of the surface: the two lists described the
    // same library and nothing compared them.
    for (degraded_imports) |name| {
        try std.testing.expect(findExport(name) != null);
    }
}
// --- end generated export table ---
