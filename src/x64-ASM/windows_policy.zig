//! Explicit Windows capability policy for Rosetta's PE runtime.
//!
//! This module owns names that Rosetta deliberately completes as unavailable
//! on the macOS host. Keeping the catalogue separate from the call dispatcher
//! makes the policy reviewable and prevents a large runtime file from becoming
//! the source of truth for both behaviour and package generation.

const std = @import("std");

/// Windows imports for which there is no truthful Rosetta-owned macOS model.
///
/// These names are not an accidental generic fallback: the dispatcher reaches
/// `completeWithImportFallback`, which records the ABI-specific refusal in the
/// import ledger. Do not add a name here until its package row has a reviewed
/// note explaining why a host-backed implementation would be misleading.
pub const refusals = [_][]const u8{
    "_ecvt_s",
    "_assert",
    "_crt_at_quick_exit",
    "__stdio_common_vfprintf",
    "__stdio_common_vfwprintf",
    "__stdio_common_vsprintf",
    "__stdio_common_vswprintf",
    "ungetc",
    "ungetwc",
    "strtok",
    "_wutime64",
    "bsearch",
    "_snprintf",
    "CancelIo",
    "CancelIoEx",
    "CreateHardLinkW",
    "DeviceIoControl",
    "EnumResourceNamesW",
    "FindFirstVolumeW",
    "FindNextVolumeW",
    "FindVolumeClose",
    "FlushViewOfFile",
    "GetOverlappedResult",
    "GetThreadContext",
    "MoveFileExA",
    "MoveFileExW",
    "OpenProcess",
    "PeekNamedPipe",
    "QueueUserAPC",
    "RemoveDirectoryW",
    "RtlCaptureStackBackTrace",
    "RtlDeleteFunctionTable",
    "RtlInstallFunctionTableCallback",
    "RtlLookupFunctionEntry",
    "RtlVirtualUnwind",
    "SetFileAttributesW",
    "SetPriorityClass",
    "SetThreadAffinityMask",
    "SetThreadExecutionState",
    "SignalObjectAndWait",
    "SuspendThread",
    "TerminateThread",
    "WaitNamedPipeW",
    "CM_Get_Device_IDA",
    "CM_Get_Parent",
    "CM_Locate_DevNodeA",
    "SetupDiEnumDeviceInfo",
    "SetupDiGetDeviceInterfaceDetailA",
    "SetupDiGetDeviceRegistryPropertyA",
    "SetupDiGetDeviceInstanceIdA",
    "SetupDiGetDeviceInstanceIdW",
    "SetupDiOpenDevRegKey",
    "SetupDiOpenDeviceInterfaceRegKey",
    "CallWindowProcW",
    "CopyImage",
    "CreateIconFromResource",
    "CreateIconIndirect",
    "DialogBoxIndirectParamW",
    "EndDialog",
    "EnumDisplayDevicesW",
    "EnumDisplayMonitors",
    "EnumDisplaySettingsW",
    "GetClassInfoExW",
    "GetRawInputData",
    "GetRawInputDeviceInfoA",
    "MsgWaitForMultipleObjects",
    "PostThreadMessageW",
    "SetClipboardData",
    "SetWindowRgn",
    "GetFileVersionInfoA",
    "GetFileVersionInfoSizeA",
    "VerQueryValueA",
    "waveInAddBuffer",
    "waveInClose",
    "waveInGetDevCapsW",
    "waveInOpen",
    "waveInPrepareHeader",
    "waveInReset",
    "waveInStart",
    "waveInUnprepareHeader",
};

pub fn contains(name: []const u8) bool {
    for (refusals) |refused| {
        if (std.mem.eql(u8, name, refused)) return true;
    }
    return false;
}

test "policy catalogue is explicit and nonzero" {
    try std.testing.expect(refusals.len > 0);
    try std.testing.expect(contains("CreateDXGIFactory1") == false);
    try std.testing.expect(contains("SetupDiEnumDeviceInfo"));
}
