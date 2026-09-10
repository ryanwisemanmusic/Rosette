//! Aggregate view of the per-DLL Windows import fact packages.
//!
//! Every real DLL has its own package under pkg/dll/win32/. This module is
//! only the linker/catalogue: it preserves the per-DLL ownership while
//! giving the runtime one stable query for direct and name-only lookups.

const std = @import("std");

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
const dll_win32_dwmapi = @import("dll_win32_dwmapi");
const dll_win32_dxgi = @import("dll_win32_dxgi");
const dll_win32_gdi32 = @import("dll_win32_gdi32");
const dll_win32_imm32 = @import("dll_win32_imm32");
const dll_win32_kernel32 = @import("dll_win32_kernel32");
const dll_win32_msvcrt = @import("dll_win32_msvcrt");
const dll_win32_ole32 = @import("dll_win32_ole32");
const dll_win32_oleaut32 = @import("dll_win32_oleaut32");
const dll_win32_setupapi = @import("dll_win32_setupapi");
const dll_win32_shell32 = @import("dll_win32_shell32");
const dll_win32_shlwapi = @import("dll_win32_shlwapi");
const dll_win32_user32 = @import("dll_win32_user32");
const dll_win32_version = @import("dll_win32_version");
const dll_win32_winmm = @import("dll_win32_winmm");
const dll_win32_wsock32 = @import("dll_win32_wsock32");
const dll_win32_dynamic = @import("dll_win32_dynamic");

pub const package_count: usize = 30;
pub const dll_package_count: usize = 29;

fn dynamicFallback(function_name: []const u8) bool {
    return dll_win32_dynamic.hasDegradedImport(function_name);
}

/// Return whether an import is in the bounded degraded inventory.
///
/// The caller still owns the Windows-surface identity gate. That keeps a
/// third-party DLL from borrowing a Win32 answer merely because it exports
/// a familiar spelling; this catalogue only answers the name/package part.
pub fn isDegradedImport(dll_name: []const u8, function_name: []const u8) bool {
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
        if (dll_win32_dwmapi.hasDegradedImport(function_name)) return true;
        if (dll_win32_dxgi.hasDegradedImport(function_name)) return true;
        if (dll_win32_gdi32.hasDegradedImport(function_name)) return true;
        if (dll_win32_imm32.hasDegradedImport(function_name)) return true;
        if (dll_win32_kernel32.hasDegradedImport(function_name)) return true;
        if (dll_win32_msvcrt.hasDegradedImport(function_name)) return true;
        if (dll_win32_ole32.hasDegradedImport(function_name)) return true;
        if (dll_win32_oleaut32.hasDegradedImport(function_name)) return true;
        if (dll_win32_setupapi.hasDegradedImport(function_name)) return true;
        if (dll_win32_shell32.hasDegradedImport(function_name)) return true;
        if (dll_win32_shlwapi.hasDegradedImport(function_name)) return true;
        if (dll_win32_user32.hasDegradedImport(function_name)) return true;
        if (dll_win32_version.hasDegradedImport(function_name)) return true;
        if (dll_win32_winmm.hasDegradedImport(function_name)) return true;
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
    if (dll_win32_dwmapi.matches(dll_name)) {
        return dll_win32_dwmapi.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_dxgi.matches(dll_name)) {
        return dll_win32_dxgi.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_gdi32.matches(dll_name)) {
        return dll_win32_gdi32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    if (dll_win32_imm32.matches(dll_name)) {
        return dll_win32_imm32.hasDegradedImport(function_name) or dynamicFallback(function_name);
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
    if (dll_win32_wsock32.matches(dll_name)) {
        return dll_win32_wsock32.hasDegradedImport(function_name) or dynamicFallback(function_name);
    }
    return dynamicFallback(function_name);
}

test "the catalogue keeps direct DLL ownership and dynamic compatibility" {
    try std.testing.expect(isDegradedImport("KERNEL32.dll", "GetThreadPriority"));
    try std.testing.expect(isDegradedImport("api-ms-win-crt-stdio-l1-1-0.dll", "__acrt_iob_func"));
    try std.testing.expect(isDegradedImport("", "LibK_GetVersion"));
    try std.testing.expect(!isDegradedImport("KERNEL32.dll", "CreateThread"));
}
