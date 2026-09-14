//! Aggregate view of the per-DLL Windows import fact packages.
//!
//! Every real DLL has its own package under pkg/dll/win32/. This module is
//! only the linker/catalogue: it preserves the per-DLL ownership while
//! giving the runtime one stable query for direct and name-only lookups.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

const dll_win32_advapi32 = @import("dll_win32_advapi32");
const dll_win32_api_ms_win_crt_convert_l1_1_0 = @import("dll_win32_api_ms_win_crt_convert_l1_1_0");
const dll_win32_api_ms_win_crt_environment_l1_1_0 = @import("dll_win32_api_ms_win_crt_environment_l1_1_0");
const dll_win32_api_ms_win_crt_filesystem_l1_1_0 = @import("dll_win32_api_ms_win_crt_filesystem_l1_1_0");
const dll_win32_api_ms_win_crt_heap_l1_1_0 = @import("dll_win32_api_ms_win_crt_heap_l1_1_0");
const dll_win32_api_ms_win_crt_locale_l1_1_0 = @import("dll_win32_api_ms_win_crt_locale_l1_1_0");
const dll_win32_api_ms_win_crt_math_l1_1_0 = @import("dll_win32_api_ms_win_crt_math_l1_1_0");
const dll_win32_api_ms_win_crt_private_l1_1_0 = @import("dll_win32_api_ms_win_crt_private_l1_1_0");
const dll_win32_api_ms_win_crt_runtime_l1_1_0 = @import("dll_win32_api_ms_win_crt_runtime_l1_1_0");
const dll_win32_api_ms_win_crt_stdio_l1_1_0 = @import("dll_win32_api_ms_win_crt_stdio_l1_1_0");
const dll_win32_api_ms_win_crt_string_l1_1_0 = @import("dll_win32_api_ms_win_crt_string_l1_1_0");
const dll_win32_api_ms_win_crt_time_l1_1_0 = @import("dll_win32_api_ms_win_crt_time_l1_1_0");
const dll_win32_api_ms_win_crt_utility_l1_1_0 = @import("dll_win32_api_ms_win_crt_utility_l1_1_0");
const dll_win32_bcrypt = @import("dll_win32_bcrypt");
const dll_win32_cfgmgr32 = @import("dll_win32_cfgmgr32");
const dll_win32_dwmapi = @import("dll_win32_dwmapi");
pub const vulkan = @import("dll_win32_vulkan_1");
const dll_win32_dxgi = @import("dll_win32_dxgi");
const dll_win32_gdi32 = @import("dll_win32_gdi32");
const dll_win32_hid = @import("dll_win32_hid");
const dll_win32_imm32 = @import("dll_win32_imm32");
const dll_win32_libusbk = @import("dll_win32_libusbk");
const dll_win32_kernel32 = @import("dll_win32_kernel32");
const dll_win32_msvcrt = @import("dll_win32_msvcrt");
const dll_win32_ole32 = @import("dll_win32_ole32");
const dll_win32_oleaut32 = @import("dll_win32_oleaut32");
const dll_win32_setupapi = @import("dll_win32_setupapi");
const dll_win32_shcore = @import("dll_win32_shcore");
const dll_win32_shell32 = @import("dll_win32_shell32");
const dll_win32_shlwapi = @import("dll_win32_shlwapi");
const dll_win32_user32 = @import("dll_win32_user32");
const dll_win32_version = @import("dll_win32_version");
const dll_win32_winmm = @import("dll_win32_winmm");
const dll_win32_winusb = @import("dll_win32_winusb");
const dll_win32_wsock32 = @import("dll_win32_wsock32");
const dll_win32_dynamic = @import("dll_win32_dynamic");

pub const package_count: usize = 36;
pub const dll_package_count: usize = 35;

fn dynamicFallback(function_name: []const u8) bool {
    return dll_win32_dynamic.hasDegradedImport(function_name);
}

/// The declared ABI for one export of one library, or null when no package
/// declares it.
///
/// The answer the return contract's heuristic could not give. That heuristic
/// reads a name's spelling and is right often enough to *choose* a refusal
/// value, and wrong often enough that it cannot be used to *judge* one - under
/// it `WaitForSingleObject` returning WAIT_OBJECT_0 and `vkCreateInstance`
/// returning VK_SUCCESS are both a zero that looks like failure. A declared
/// export was looked up by a person, so its convention can be trusted to
/// accuse someone.
///
/// Null means no package owns this name, which is itself worth knowing: it is
/// a library Rosette answers for without having written down what the answers
/// mean.
pub fn declaredExport(dll_name: []const u8, function_name: []const u8) ?export_contract.Export {
    if (dll_win32_advapi32.matches(dll_name)) return dll_win32_advapi32.findExport(function_name);
    if (dll_win32_api_ms_win_crt_convert_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_convert_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_environment_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_environment_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_filesystem_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_filesystem_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_heap_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_heap_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_locale_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_locale_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_math_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_math_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_private_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_private_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_runtime_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_runtime_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_stdio_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_stdio_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_string_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_string_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_time_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_time_l1_1_0.findExport(function_name);
    if (dll_win32_api_ms_win_crt_utility_l1_1_0.matches(dll_name)) return dll_win32_api_ms_win_crt_utility_l1_1_0.findExport(function_name);
    if (dll_win32_bcrypt.matches(dll_name)) return dll_win32_bcrypt.findExport(function_name);
    if (dll_win32_dwmapi.matches(dll_name)) return dll_win32_dwmapi.findExport(function_name);
    if (dll_win32_dxgi.matches(dll_name)) return dll_win32_dxgi.findExport(function_name);
    if (dll_win32_gdi32.matches(dll_name)) return dll_win32_gdi32.findExport(function_name);
    if (dll_win32_imm32.matches(dll_name)) return dll_win32_imm32.findExport(function_name);
    if (dll_win32_kernel32.matches(dll_name)) return dll_win32_kernel32.findExport(function_name);
    if (dll_win32_msvcrt.matches(dll_name)) return dll_win32_msvcrt.findExport(function_name);
    if (dll_win32_ole32.matches(dll_name)) return dll_win32_ole32.findExport(function_name);
    if (dll_win32_oleaut32.matches(dll_name)) return dll_win32_oleaut32.findExport(function_name);
    if (dll_win32_setupapi.matches(dll_name)) return dll_win32_setupapi.findExport(function_name);
    if (dll_win32_shell32.matches(dll_name)) return dll_win32_shell32.findExport(function_name);
    if (dll_win32_shlwapi.matches(dll_name)) return dll_win32_shlwapi.findExport(function_name);
    if (dll_win32_user32.matches(dll_name)) return dll_win32_user32.findExport(function_name);
    if (dll_win32_version.matches(dll_name)) return dll_win32_version.findExport(function_name);
    if (dll_win32_winmm.matches(dll_name)) return dll_win32_winmm.findExport(function_name);
    if (dll_win32_wsock32.matches(dll_name)) return dll_win32_wsock32.findExport(function_name);
    return null;
}

test "a declared export beats a guess, and an unowned name says so" {
    // The two zeroes that made the heuristic unusable as an oracle.
    const wait = declaredExport("KERNEL32.dll", "WaitForSingleObject").?;
    try std.testing.expect(wait.reviewed);
    try std.testing.expect(wait.zero_is_an_answer);
    try std.testing.expect(!wait.valueIsRefusal(0));

    // And the one that was a real defect: FALSE from `VirtualProtect` is a
    // failure, and nothing but a per-name declaration can say so.
    const protect = declaredExport("KERNEL32.dll", "VirtualProtect").?;
    try std.testing.expect(protect.valueIsRefusal(0));
    try std.testing.expect(protect.isDecisive());

    // A name no package owns is null rather than a guessed shape.
    try std.testing.expectEqual(@as(?export_contract.Export, null), declaredExport("KERNEL32.dll", "__nobody_owns_this__"));
    try std.testing.expectEqual(@as(?export_contract.Export, null), declaredExport("third_party.dll", "VirtualProtect"));
}

/// Return whether an import has a per-DLL Rosetta ABI contract.
///
/// The caller still owns the Windows-surface identity gate. That keeps a
/// third-party DLL from borrowing a Win32 answer merely because it exports
/// a familiar spelling; this catalogue only answers the name/package part.
/// Whether Rosette declines this export on purpose rather than for want of
/// work.
///
/// The distinction is the difference between a to-do and a decision. The
/// 2026-09-12 run listed `WinUsb_ReadIsochPipeAsap` under `GAP`, which reads
/// as "Rosette has not got to this yet". It is the opposite: libusb probes
/// that name with `required = false`, and answering NULL is what keeps the
/// four isochronous entry points out of its required set, because Rosette
/// models no isochronous USB transport. Serving it would promise one.
///
/// Only packages that declare the distinction take part; everything else is
/// false, so a name nobody has thought about still reports as a gap.
pub fn isDeliberateExportRefusal(dll_name: []const u8, function_name: []const u8) bool {
    if (dll_win32_winusb.matches(dll_name) or dll_name.len == 0) {
        if (dll_win32_winusb.isDeliberateRefusal(function_name)) return true;
    }
    if (isAddressWaitName(function_name) and (dll_name.len == 0 or isSynchApiSet(dll_name))) return true;
    return false;
}

/// The Windows 8 address-wait primitives SDL probes when it builds a
/// semaphore.
///
/// SDL resolves `WaitOnAddress` and `WakeByAddressSingle` through
/// `GetProcAddress` and, when either is absent, builds its semaphores on
/// kernel semaphore objects instead. Rosetta models kernel semaphores through
/// the same wait-object state machine every other Win32 wait uses, and the
/// 2026-09-13 run's SDL audio thread reached WinMM on that fallback. Serving
/// the address waits would switch every SDL semaphore onto a second
/// synchronisation model for no gain, so NULL is the decision, not a to-do.
const address_wait_names = [_][]const u8{
    "WaitOnAddress",
    "WakeByAddressSingle",
    "WakeByAddressAll",
};

fn isAddressWaitName(function_name: []const u8) bool {
    for (address_wait_names) |name| {
        if (std.mem.eql(u8, name, function_name)) return true;
    }
    return false;
}

fn isSynchApiSet(dll_name: []const u8) bool {
    return std.ascii.startsWithIgnoreCase(dll_name, "api-ms-win-core-synch-");
}

test "a deliberate refusal is not a gap" {
    try std.testing.expect(isDeliberateExportRefusal("WINUSB.dll", "WinUsb_ReadIsochPipeAsap"));
    // libusb resolves it through a module handle, so the DLL name may be
    // absent at the point the refusal is recorded.
    try std.testing.expect(isDeliberateExportRefusal("", "WinUsb_ReadIsochPipeAsap"));
    // A name Rosette does serve, and a name nobody has considered, are both
    // false: only a declared decision counts.
    try std.testing.expect(!isDeliberateExportRefusal("WINUSB.dll", "WinUsb_Initialize"));
    try std.testing.expect(!isDeliberateExportRefusal("KERNEL32.dll", "SomethingUnplanned"));
}

test "SDL's address-wait probes are declined on purpose, and only from the synch API set" {
    try std.testing.expect(isDeliberateExportRefusal("api-ms-win-core-synch-l1-2-0.dll", "WaitOnAddress"));
    try std.testing.expect(isDeliberateExportRefusal("api-ms-win-core-synch-l1-2-0.dll", "WakeByAddressSingle"));
    try std.testing.expect(isDeliberateExportRefusal("", "WakeByAddressAll"));
    // A different library exporting the same spelling is not covered by the
    // decision, and neither is a neighbouring name in the right library.
    try std.testing.expect(!isDeliberateExportRefusal("user32.dll", "WaitOnAddress"));
    try std.testing.expect(!isDeliberateExportRefusal("api-ms-win-core-synch-l1-2-0.dll", "InitializeSRWLock"));
}

pub fn isContractImport(dll_name: []const u8, function_name: []const u8) bool {
    if (dll_name.len == 0) {
        if (dll_win32_advapi32.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_convert_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_environment_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_filesystem_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_heap_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_locale_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_math_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_private_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_runtime_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_stdio_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_string_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_time_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_api_ms_win_crt_utility_l1_1_0.hasDegradedImport(function_name)) return true;
        if (dll_win32_bcrypt.hasDegradedImport(function_name)) return true;
        if (dll_win32_cfgmgr32.hasDegradedImport(function_name)) return true;
        if (dll_win32_dwmapi.hasDegradedImport(function_name)) return true;
        if (dll_win32_dxgi.hasDegradedImport(function_name)) return true;
        if (dll_win32_gdi32.hasDegradedImport(function_name)) return true;
        if (dll_win32_hid.hasDegradedImport(function_name)) return true;
        if (dll_win32_imm32.hasDegradedImport(function_name)) return true;
        if (dll_win32_libusbk.hasDegradedImport(function_name)) return true;
        if (dll_win32_kernel32.hasDegradedImport(function_name)) return true;
        if (dll_win32_msvcrt.hasDegradedImport(function_name)) return true;
        if (dll_win32_ole32.hasDegradedImport(function_name)) return true;
        if (dll_win32_oleaut32.hasDegradedImport(function_name)) return true;
        if (dll_win32_setupapi.hasDegradedImport(function_name)) return true;
        if (dll_win32_shcore.hasDegradedImport(function_name)) return true;
        if (dll_win32_shell32.hasDegradedImport(function_name)) return true;
        if (dll_win32_shlwapi.hasDegradedImport(function_name)) return true;
        if (dll_win32_user32.hasDegradedImport(function_name)) return true;
        if (dll_win32_version.hasDegradedImport(function_name)) return true;
        if (dll_win32_winmm.hasDegradedImport(function_name)) return true;
        if (dll_win32_winusb.hasDegradedImport(function_name)) return true;
        if (dll_win32_wsock32.hasDegradedImport(function_name)) return true;
        return dynamicFallback(function_name);
    }
    if (dll_win32_advapi32.matches(dll_name)) {
        return dll_win32_advapi32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_convert_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_convert_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_environment_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_environment_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_filesystem_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_filesystem_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_heap_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_heap_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_locale_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_locale_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_math_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_math_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_private_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_private_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_runtime_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_runtime_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_stdio_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_stdio_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_string_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_string_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_time_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_time_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_api_ms_win_crt_utility_l1_1_0.matches(dll_name)) {
        return dll_win32_api_ms_win_crt_utility_l1_1_0.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_bcrypt.matches(dll_name)) {
        return dll_win32_bcrypt.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_cfgmgr32.matches(dll_name)) {
        return dll_win32_cfgmgr32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_dwmapi.matches(dll_name)) {
        return dll_win32_dwmapi.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_dxgi.matches(dll_name)) {
        return dll_win32_dxgi.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_gdi32.matches(dll_name)) {
        return dll_win32_gdi32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_hid.matches(dll_name)) {
        return dll_win32_hid.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_imm32.matches(dll_name)) {
        return dll_win32_imm32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_libusbk.matches(dll_name)) {
        return dll_win32_libusbk.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_kernel32.matches(dll_name)) {
        return dll_win32_kernel32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_msvcrt.matches(dll_name)) {
        return dll_win32_msvcrt.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_ole32.matches(dll_name)) {
        return dll_win32_ole32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_oleaut32.matches(dll_name)) {
        return dll_win32_oleaut32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_setupapi.matches(dll_name)) {
        return dll_win32_setupapi.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_shcore.matches(dll_name)) {
        return dll_win32_shcore.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_shell32.matches(dll_name)) {
        return dll_win32_shell32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_shlwapi.matches(dll_name)) {
        return dll_win32_shlwapi.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_user32.matches(dll_name)) {
        return dll_win32_user32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_version.matches(dll_name)) {
        return dll_win32_version.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_winmm.matches(dll_name)) {
        return dll_win32_winmm.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_winusb.matches(dll_name)) {
        return dll_win32_winusb.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_wsock32.matches(dll_name)) {
        return dll_win32_wsock32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    return dynamicFallback(function_name);
}

/// Compatibility spelling for older callers. New code should use
/// isContractImport: catalogued names are explicitly bound and are not
/// unresolved/degraded imports.
pub const isDegradedImport = isContractImport;

test "the catalogue keeps direct DLL ownership and dynamic compatibility" {
    try std.testing.expect(isDegradedImport("KERNEL32.dll", "GetThreadPriority"));
    try std.testing.expect(isDegradedImport("api-ms-win-crt-stdio-l1-1-0.dll", "__acrt_iob_func"));
    try std.testing.expect(isDegradedImport("", "LibK_GetVersion"));
    try std.testing.expect(!isDegradedImport("KERNEL32.dll", "CreateThread"));
    try std.testing.expect(isDegradedImport("WINUSB.dll", "WinUsb_AbortPipe"));
}
