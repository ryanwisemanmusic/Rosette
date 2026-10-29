//! Win32 startup-information queries used by narrow PE compatibility paths.

const std = @import("std");

pub fn handle(comptime api: type, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (!std.mem.eql(u8, name, "GetStartupInfoA") and !std.mem.eql(u8, name, "GetStartupInfoW")) return false;
    const startup_info = api._arg(state, 0, direct_return_rip);
    if (startup_info == 0 or state.guestMemory(startup_info, 104) == null) {
        api._guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
    } else {
        _ = api._fillGuest(state, startup_info, 104, 0);
        state.write32(startup_info, 104);
        api._guestStateField(state, "windows_last_error").* = 0;
    }
    // STARTUPINFOA and STARTUPINFOW share a Win64 layout; both APIs return void.
    api._finish(state, direct_return_rip);
    return true;
}
