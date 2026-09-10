//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");

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
    "SetThreadContext",
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
