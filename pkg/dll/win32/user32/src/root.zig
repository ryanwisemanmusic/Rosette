//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

pub const dll_name = "USER32.dll";
pub const stem = "user32";
pub const match_prefix = "";
pub const subsystem_name = "windowing";

pub const degraded_imports = [_][]const u8{
    "AttachThreadInput",
    "CallNextHookEx",
    "CallWindowProcW",
    "ChangeDisplaySettingsExW",
    "ClipCursor",
    "CloseClipboard",
    "CopyImage",
    "CreateIconFromResource",
    "CreateIconIndirect",
    "DialogBoxIndirectParamW",
    "DrawTextW",
    "EmptyClipboard",
    "EndDialog",
    "EnumDisplayDevicesW",
    "EnumDisplayMonitors",
    "EnumDisplaySettingsW",
    "FillRect",
    "FlashWindowEx",
    "GetAsyncKeyState",
    "GetClassInfoExW",
    "GetClipboardData",
    "GetClipboardSequenceNumber",
    "GetClipCursor",
    "GetDesktopWindow",
    "GetDlgItem",
    "GetDoubleClickTime",
    "GetForegroundWindow",
    "GetKeyboardLayout",
    "GetKeyboardState",
    "GetMenu",
    "GetMessageExtraInfo",
    "GetMessageTime",
    "GetParent",
    "GetRawInputData",
    "GetRawInputDeviceInfoA",
    "GetRawInputDeviceList",
    "GetWindowTextLengthW",
    "GetWindowTextW",
    "GetWindowThreadProcessId",
    "IntersectRect",
    "IsClipboardFormatAvailable",
    "IsIconic",
    "KillTimer",
    "MapVirtualKeyW",
    "MonitorFromPoint",
    "MonitorFromRect",
    "MsgWaitForMultipleObjects",
    "OpenClipboard",
    "PostThreadMessageW",
    "PtInRect",
    "RegisterRawInputDevices",
    "RegisterWindowMessageA",
    "SetActiveWindow",
    "SetClipboardData",
    "SetCursorPos",
    "SetForegroundWindow",
    "SetLayeredWindowAttributes",
    "SetTimer",
    "SetWindowRgn",
    "SetWindowsHookExW",
    "SystemParametersInfoA",
    "SystemParametersInfoW",
    "ToUnicode",
    "TrackMouseEvent",
    "UnhookWindowsHookEx",
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
    try std.testing.expect(matches("USER32.dll"));
    try std.testing.expect(matches("user32"));
    try std.testing.expect(hasDegradedImport("AttachThreadInput"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}

// --- generated export table: tools/dll/generate_export_tables.py ---
/// Every name this image imports from USER32.dll, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{
    .{ .name = "AdjustWindowRectEx", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "AppendMenuW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "AttachThreadInput", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CallNextHookEx", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the window procedure's own result, which is arbitrary" },
    .{ .name = "CallWindowProcW", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "returns the window procedure's own result, which is arbitrary" },
    .{ .name = "ChangeDisplaySettingsExW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "ClientToScreen", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "ClipCursor", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CloseClipboard", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "CopyImage", .convention = .handle, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "CreateIconFromResource", .convention = .handle, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "CreateIconFromResourceEx", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "CreateIconIndirect", .convention = .handle, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "CreateMenu", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "CreatePopupMenu", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "CreateWindowExA", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "CreateWindowExW", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "DefWindowProcW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the window procedure's own result, which is arbitrary" },
    .{ .name = "DestroyIcon", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "DestroyMenu", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "DestroyWindow", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "DialogBoxIndirectParamW", .convention = .handle, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "DispatchMessageW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the window procedure's own result, which is arbitrary" },
    .{ .name = "DrawMenuBar", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "DrawTextW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "EmptyClipboard", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "EnableMenuItem", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "EndDialog", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "EnumDisplayDevicesW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "EnumDisplayMonitors", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "EnumDisplaySettingsW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "FillRect", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "FlashWindowEx", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetAsyncKeyState", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetCapture", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetClassInfoExW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "GetClassLongPtrW", .arity = 2, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetClientRect", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetClipCursor", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetClipboardData", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetClipboardSequenceNumber", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetCursorPos", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetDC", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetDesktopWindow", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetDlgItem", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetDoubleClickTime", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetFocus", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetForegroundWindow", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetKeyState", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetKeyboardLayout", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetKeyboardState", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetMenu", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetMenuInfo", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetMessageExtraInfo", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetMessageTime", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetMessageW", .arity = 4, .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns FALSE for WM_QUIT, which is how every message loop ends, and -1 for a real error" },
    .{ .name = "GetMonitorInfoW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetParent", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "GetPropW", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetRawInputData", .arity = 5, .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "returns bytes copied, or (UINT)-1 on error; a zero-size query is how the caller sizes its buffer" },
    .{ .name = "GetRawInputDeviceInfoA", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "GetRawInputDeviceList", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetSystemMetrics", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetUpdateRect", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetWindowLongPtrW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetWindowLongW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetWindowPlacement", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetWindowRect", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "GetWindowTextLengthW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetWindowTextW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "GetWindowThreadProcessId", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "IntersectRect", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "InvalidateRect", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "IsClipboardFormatAvailable", .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "FALSE is the answer to a question, not a failure to answer it" },
    .{ .name = "IsIconic", .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "FALSE is the answer to a question, not a failure to answer it" },
    .{ .name = "KillTimer", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "LoadCursorW", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "LoadIconW", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "MapVirtualKeyW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "MessageBoxA", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "MessageBoxW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "MonitorFromPoint", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "MonitorFromRect", .arity = 2, .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "MonitorFromWindow", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "MsgWaitForMultipleObjects", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "OpenClipboard", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "PeekMessageW", .arity = 5, .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "FALSE means the queue was empty" },
    .{ .name = "PostMessageW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "PostQuitMessage", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "PostThreadMessageW", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "PtInRect", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "RegisterClassExA", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "RegisterClassExW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "RegisterClassW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "RegisterDeviceNotificationW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "RegisterRawInputDevices", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "RegisterWindowMessageA", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "ReleaseCapture", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "ReleaseDC", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "RemovePropW", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "ScreenToClient", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SendMessageW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the window procedure's own result, which is arbitrary" },
    .{ .name = "SetActiveWindow", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "SetCapture", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "SetClipboardData", .convention = .handle, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "SetCursor", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "SetCursorPos", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetFocus", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "SetForegroundWindow", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetLayeredWindowAttributes", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetMenu", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetMenuInfo", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetPropW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetTimer", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "SetWindowLongPtrW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "SetWindowLongW", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "SetWindowPlacement", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetWindowPos", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetWindowRgn", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetWindowTextW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetWindowsHookExW", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
    .{ .name = "ShowWindow", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SystemParametersInfoA", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SystemParametersInfoW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "ToUnicode", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "TrackMouseEvent", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "TranslateMessage", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "UnhookWindowsHookEx", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "UnregisterClassA", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "UnregisterClassW", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "UnregisterDeviceNotification", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "ValidateRect", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "VkKeyScanW", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns -1 when the character has no key; the low byte is the key code" },
    .{ .name = "WindowFromPoint", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "NULL is a normal answer for a lookup that found nothing" },
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
