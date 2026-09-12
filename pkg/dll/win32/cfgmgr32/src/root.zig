//! Static facts for the Configuration Manager Windows DLL import surface.
//!
//! `cfgmgr32` is the device-tree half of PnP: `SetupAPI` enumerates device
//! *interfaces*, and `CM_*` walks the parent/child/sibling links between the
//! device nodes behind them. Nothing links against it - a USB or HID stack
//! loads it at runtime and resolves what it needs.
//!
//! ## Why the whole list, not the two names a log happened to show
//!
//! libusb's `init_dlls` resolves `CM_Get_Parent` and `CM_Get_Child` with
//! `ret_on_failure = true` and returns false if either is missing, which
//! takes the entire WinUSB backend with it. Its `DLL_LOAD_FUNC` macro also
//! tries the bare name, then `nameA`, then `nameW` before giving up - which
//! is why one missing export shows up as three refusals in a run log and
//! reads like three separate gaps.
//!
//! Naming these is not claiming a device tree. Rosetta enumerates no PnP
//! devices, so every locator reports `CR_NO_SUCH_DEVNODE` and every walk
//! reports `CR_NO_SUCH_DEVINST` - which is also what a Windows machine
//! answers for a devnode that is not there.

const std = @import("std");

pub const dll_name = "cfgmgr32.dll";
pub const stem = "cfgmgr32";
pub const match_prefix = "";
pub const subsystem_name = "device_enumeration";

pub const degraded_imports = [_][]const u8{
    // Device-tree traversal. libusb needs the first two or its WinUSB
    // backend does not initialize at all.
    "CM_Get_Parent",
    "CM_Get_Child",
    "CM_Get_Sibling",
    "CM_Get_Depth",
    // Device instance identity.
    "CM_Get_Device_ID",
    "CM_Get_Device_IDA",
    "CM_Get_Device_IDW",
    "CM_Get_Device_ID_Size",
    "CM_Get_Device_ID_ListA",
    "CM_Get_Device_ID_ListW",
    "CM_Get_Device_ID_List_SizeA",
    "CM_Get_Device_ID_List_SizeW",
    "CM_Locate_DevNodeA",
    "CM_Locate_DevNodeW",
    // Node properties and status, which a stack consults before deciding a
    // device is usable.
    "CM_Get_DevNode_Status",
    "CM_Get_DevNode_Registry_PropertyA",
    "CM_Get_DevNode_Registry_PropertyW",
    "CM_Get_DevNode_PropertyW",
    // Interface enumeration, the CM_ mirror of the SetupAPI calls.
    "CM_Get_Device_Interface_ListA",
    "CM_Get_Device_Interface_ListW",
    "CM_Get_Device_Interface_List_SizeA",
    "CM_Get_Device_Interface_List_SizeW",
    "CM_Get_Device_Interface_PropertyW",
    // Notification registration, which a hot-plug-aware stack arms early.
    "CM_Register_Notification",
    "CM_Unregister_Notification",
    "CM_MapCrToWin32Err",
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

test "cfgmgr32 identity is case-insensitive, as a runtime-probed library's name always is" {
    try std.testing.expect(matches("cfgmgr32.dll"));
    try std.testing.expect(matches("Cfgmgr32.DLL"));
    try std.testing.expect(matches("cfgmgr32"));
    try std.testing.expect(!matches("cfgmgr32ex.dll"));
}

test "libusb's all-or-nothing pair is owned, in all three spellings its macro tries" {
    // `DLL_LOAD_FUNC` tries the bare name, then +A, then +W. A run log shows
    // one missing export as three refusals; the inventory has to answer the
    // spelling that actually exists.
    try std.testing.expect(hasDegradedImport("CM_Get_Parent"));
    try std.testing.expect(hasDegradedImport("CM_Get_Child"));
    // `CM_Get_Child` has no A/W form on Windows either, so those two stay
    // absent on purpose: answering them would claim an export that does not
    // exist, and the caller falls through to the bare name regardless.
    try std.testing.expect(!hasDegradedImport("CM_Get_ChildA"));
    try std.testing.expect(!hasDegradedImport("CM_Get_ChildW"));
    // The ones that genuinely are A/W pairs carry both.
    try std.testing.expect(hasDegradedImport("CM_Locate_DevNodeA"));
    try std.testing.expect(hasDegradedImport("CM_Locate_DevNodeW"));
}

test "the inventory has no duplicate names" {
    for (degraded_imports, 0..) |name, index| {
        for (degraded_imports[index + 1 ..]) |later| {
            try std.testing.expect(!std.mem.eql(u8, name, later));
        }
    }
}
