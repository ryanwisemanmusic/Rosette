//! Pure CRT math imports with no shared Windows table state. Only the exact
//! registered exp2/exp2f surface is admitted; its arithmetic and ABI return
//! are the ordinary CRT handler's, including XMM0 clearing and LastError.
const std = @import("std");
const crt_math = @import("crt_math.zig");

pub fn candidate(dll: []const u8, name: []const u8) ?usize {
    const index: usize = if (std.mem.eql(u8, name, "exp2")) 0 else if (std.mem.eql(u8, name, "exp2f")) 1 else return null;
    inline for (.{ "api-ms-win-crt-math-l1-1-0.dll", "ucrtbase.dll", "msvcrt.dll" }) |module| {
        if (std.ascii.eqlIgnoreCase(dll, module)) return index;
    }
    return null;
}

pub fn tryFunction(comptime host: type, state: anytype, dll: []const u8, name: []const u8, return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "windows_fast_math") or !@hasDecl(State, "windowsGuestContextField")) return false;
    const index = candidate(dll, name) orelse return false;
    if (!state.windows_fast_math.enabled or !state.parallel_guest_execution or !state.windows_runtime_enabled or
        state.diagnose_abi or return_rip == null) return false;
    // Preserve requested memory tracing of the return stack and the ordinary
    // diagnostic import snapshots. Exhausted write traces need no slow route.
    if (comptime @hasDecl(State, "windowsMemoryTraceLive")) {
        if (state.windowsMemoryTraceLive()) return false;
    }
    if (comptime @hasField(State, "trace_write_address")) {
        if (state.trace_write_address != null) return false;
    }
    const scope = host.begin(state);
    defer host.end(state, scope);
    // Reuse the same width, numeric implementation and side effects instead
    // of introducing approximate math or a second floating-point contract.
    if (!crt_math.tryExp2(host, state, name, return_rip)) return false;
    _ = state.windows_fast_math.calls[index].fetchAdd(1, .monotonic);
    state.windowsGuestContextField("windows_current_import").* = if (index == 0) "exp2" else "exp2f";
    return true;
}

test "fast math admits only the registered CRT base-two surface" {
    try std.testing.expectEqual(@as(?usize, 0), candidate("API-MS-WIN-CRT-MATH-L1-1-0.DLL", "exp2"));
    try std.testing.expectEqual(@as(?usize, 1), candidate("ucrtbase.dll", "exp2f"));
    try std.testing.expectEqual(@as(?usize, null), candidate("user32.dll", "exp2"));
    try std.testing.expectEqual(@as(?usize, null), candidate("ucrtbase.dll", "Exp2"));
    try std.testing.expectEqual(@as(?usize, null), candidate("ucrtbase.dll", "frexp"));
}
