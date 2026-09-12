//! Static facts for the HID-class Windows DLL import surface.
//!
//! HID discovery is optional for Xenia's graphics path, but the import is
//! still a real Windows contract. Keeping it in its own package preserves the
//! one-DLL-per-folder boundary and lets name-only imports recover their HID
//! identity through the catalogue.

const std = @import("std");

pub const dll_name = "HID.dll";
pub const stem = "hid";
pub const match_prefix = "";
pub const subsystem_name = "device_enumeration";

/// The HID surface a Windows controller stack resolves dynamically.
///
/// SDL loads `hid.dll` twice for two different jobs and both are all-or-
/// nothing. `WIN_LoadHIDDLL` resolves seven names and unloads the library if
/// any one is missing, which disables the raw-input joystick backend
/// entirely; hidapi's `lookup_functions` resolves twelve and returns -1 the
/// same way. So a partial inventory is worth nothing here: either every name
/// on one of those lists resolves, or that backend is gone.
///
/// Naming them is not claiming a device. Rosetta enumerates no HID devices,
/// so these entry points exist and then honestly report that the handle they
/// were given is not one of ours - which is what a Windows machine with no
/// HID device attached also does.
pub const degraded_imports = [_][]const u8{
    "HidD_GetHidGuid",
    // WIN_LoadHIDDLL's list.
    "HidD_GetManufacturerString",
    "HidD_GetProductString",
    "HidP_GetCaps",
    "HidP_GetButtonCaps",
    "HidP_GetValueCaps",
    "HidP_MaxDataListLength",
    "HidP_GetData",
    // hidapi's additional list.
    "HidD_GetAttributes",
    "HidD_GetSerialNumberString",
    "HidD_SetFeature",
    "HidD_GetFeature",
    "HidD_GetIndexedString",
    "HidD_GetPreparsedData",
    "HidD_FreePreparsedData",
    "HidD_SetNumInputBuffers",
    "HidD_SetOutputReport",
    "HidD_GetPhysicalDescriptor",
    "HidD_GetInputReport",
    "HidD_FlushQueue",
    "HidP_GetUsages",
    "HidP_GetUsageValue",
    "HidP_MaxUsageListLength",
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

test "HID identity is case-insensitive and owns the device GUID import" {
    try std.testing.expect(matches("HID.dll"));
    try std.testing.expect(matches("hid"));
    try std.testing.expect(hasDegradedImport("HidD_GetHidGuid"));
    try std.testing.expect(!hasDegradedImport("SetupDiGetClassDevsA"));
}

test "the whole of SDL's raw-input list is owned, because a partial list is worth nothing" {
    // WIN_LoadHIDDLL resolves these seven and unloads the library if any one
    // of them is absent. Missing a single name costs the entire backend, so
    // the list is asserted rather than trusted to review.
    const win_load_hid_dll = [_][]const u8{
        "HidD_GetManufacturerString",
        "HidD_GetProductString",
        "HidP_GetCaps",
        "HidP_GetButtonCaps",
        "HidP_GetValueCaps",
        "HidP_MaxDataListLength",
        "HidP_GetData",
    };
    for (win_load_hid_dll) |name| {
        if (!hasDegradedImport(name)) {
            std.debug.print("hid.dll inventory is missing '{s}'\n", .{name});
            return error.MissingRawInputExport;
        }
    }

    // libusb's `hid_init` list, which differs from hidapi's by two names and
    // fails the same way.
    const libusb_hid = [_][]const u8{
        "HidD_GetAttributes",
        "HidD_GetHidGuid",
        "HidD_GetPreparsedData",
        "HidD_FreePreparsedData",
        "HidD_GetManufacturerString",
        "HidD_GetProductString",
        "HidD_GetSerialNumberString",
        "HidD_GetIndexedString",
        "HidP_GetCaps",
        "HidD_SetNumInputBuffers",
        "HidD_GetPhysicalDescriptor",
        "HidD_FlushQueue",
        "HidP_GetValueCaps",
    };
    for (libusb_hid) |name| {
        if (!hasDegradedImport(name)) {
            std.debug.print("hid.dll inventory is missing '{s}'\n", .{name});
            return error.MissingLibusbHidExport;
        }
    }

    // hidapi's lookup_functions list, same all-or-nothing rule.
    const hidapi = [_][]const u8{
        "HidD_GetAttributes",
        "HidD_GetSerialNumberString",
        "HidD_GetManufacturerString",
        "HidD_GetProductString",
        "HidD_SetFeature",
        "HidD_GetFeature",
        "HidD_GetIndexedString",
        "HidD_GetPreparsedData",
        "HidD_FreePreparsedData",
        "HidP_GetCaps",
        "HidD_SetNumInputBuffers",
        "HidD_SetOutputReport",
    };
    for (hidapi) |name| {
        if (!hasDegradedImport(name)) {
            std.debug.print("hid.dll inventory is missing '{s}'\n", .{name});
            return error.MissingHidapiExport;
        }
    }
}

test "the inventory has no duplicate names" {
    for (degraded_imports, 0..) |name, index| {
        for (degraded_imports[index + 1 ..]) |later| {
            try std.testing.expect(!std.mem.eql(u8, name, later));
        }
    }
}
