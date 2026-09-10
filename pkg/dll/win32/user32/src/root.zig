//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");

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
