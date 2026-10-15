//! Existing parallel fast dispatch plus a narrow exact registered-tail surface.
const std = @import("std");
const fast_math = @import("fast_math.zig");
const fast_imports = @import("fast_imports.zig");

pub fn tryFunction(comptime host: type, state: anytype, dll_name: []const u8, function_name: []const u8, direct_return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    // SRW retains its runtime mutex and owner/waiter synchronization.
    if (comptime @hasDecl(State, "tryWindowsSrwImport")) {
        if (std.ascii.eqlIgnoreCase(dll_name, "kernel32.dll") or
            std.ascii.startsWithIgnoreCase(dll_name, "api-ms-win-core-synch-"))
        {
            if (state.tryWindowsSrwImport(function_name, direct_return_rip)) return true;
        }
    }
    if (comptime @hasDecl(State, "windowsFastCrtImportMayBypassRuntimeLock")) {
        if (state.windowsFastCrtImportMayBypassRuntimeLock()) {
            if (fast_math.tryFunction(host, state, dll_name, function_name, direct_return_rip) or
                fast_imports.tryCrtHeap(host, state, dll_name, function_name, direct_return_rip)) return true;
            if (fast_imports.tryCrtMemory(host, state, dll_name, function_name, direct_return_rip)) return true;
            if (fast_imports.tryCrtStrings(host, state, dll_name, function_name, direct_return_rip)) return true;
            if (fast_imports.tryProcessAffinityMask(host, state, dll_name, function_name, direct_return_rip)) return true;
        }
    }
    if (@import("fast_nt_yield.zig").tryFunction(host, state, dll_name, function_name, direct_return_rip) or
        fast_imports.trySleepZero(host, state, dll_name, function_name, direct_return_rip)) return true;
    if (comptime @hasDecl(State, "windowsFastImportMayBypassRuntimeLock")) {
        if (!state.windowsFastImportMayBypassRuntimeLock()) return false;
    }
    if (fast_imports.tryIdentityQuery(host, state, dll_name, function_name, direct_return_rip)) return true;
    return fast_imports.tryPreciseTimeQuery(host, state, dll_name, function_name, direct_return_rip);
}

pub fn tryRegisteredTail(comptime host: type, state: anytype, dll: []const u8, name: []const u8, rip: ?u64) bool {
    if (!state.windowsFastCrtImportMayBypassRuntimeLock()) return false;
    if (std.mem.eql(u8, name, "NtDelayExecution") or std.mem.eql(u8, name, "NtYieldExecution"))
        return @import("fast_nt_yield.zig").tryFunction(host, state, dll, name, rip);
    if (fast_math.candidate(dll, name) != null)
        return fast_math.tryFunction(host, state, dll, name, rip);
    return false;
}
