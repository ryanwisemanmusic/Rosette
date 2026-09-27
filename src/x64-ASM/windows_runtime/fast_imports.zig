//! Narrow imports whose parallel execution is safe without the Win32 runtime
//! table lock. Each candidate has an explicit contract and a small test
//! surface; growing this list requires proving that the handler has no shared
//! mutable state beyond its guest-memory output.

const std = @import("std");

pub fn isPreciseTimeQuery(
    dll_name: []const u8,
    function_name: []const u8,
    direct_return_rip: ?u64,
    parallel: bool,
    runtime_enabled: bool,
    diagnose_abi: bool,
    trace_windows_memory: bool,
    trace_write_address: bool,
) bool {
    if (!parallel or !runtime_enabled or diagnose_abi or trace_windows_memory or trace_write_address) return false;
    if (direct_return_rip == null) return false;
    if (!std.mem.eql(u8, function_name, "GetSystemTimePreciseAsFileTime")) return false;

    inline for (.{
        "kernel32.dll",
        "kernelbase.dll",
        "api-ms-win-core-sysinfo-l1-1-0.dll",
        "api-ms-win-core-sysinfo-l1-2-0.dll",
        "api-ms-win-core-sysinfo-l1-2-1.dll",
        "api-ms-win-core-sysinfo-l1-2-2.dll",
        "api-ms-win-core-sysinfo-l1-2-3.dll",
    }) |module| {
        if (std.ascii.eqlIgnoreCase(dll_name, module)) return true;
    }
    return false;
}

/// Execute only an exact registered PE import stub that the policy above has
/// proven safe to run concurrently. The caller validates static IAT bindings
/// or the dynamic GetProcAddress registration before reaching this adapter.
/// The host adapter preserves the runtime-call store-buffer boundary and the
/// normal Windows ABI return convention.
pub fn tryPreciseTimeQuery(host: anytype, state: anytype, dll_name: []const u8, function_name: []const u8, direct_return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "parallel_guest_execution") or
        !@hasField(State, "windows_runtime_enabled") or
        !@hasField(State, "diagnose_abi") or
        !@hasDecl(State, "windowsGuestFastFileTime") or
        !@hasDecl(State, "windowsGuestContextField") or
        !@hasDecl(State, "beginWindowsFastImportStoreScope") or
        !@hasDecl(State, "endWindowsFastImportStoreScope") or
        !@hasDecl(State, "noteWindowsFastTimeImport") or
        !@hasDecl(State, "noteWindowsGuestClockRead")) return false;

    // The mapped-write trace spends a fixed budget and then observes
    // nothing; only a trace with budget left needs the locked path. Gating
    // on the flag alone kept every GetSystemTimePreciseAsFileTime of the
    // 2026-09-26 run on the runtime lock (77,893 calls in 5 s, waits up to
    // 51 ms), because the launcher turns the trace on by default.
    const trace_windows_memory = if (comptime @hasDecl(State, "windowsMemoryTraceLive"))
        state.windowsMemoryTraceLive()
    else if (comptime @hasField(State, "trace_windows_memory"))
        state.trace_windows_memory
    else
        false;
    const trace_write_address = if (comptime @hasField(State, "trace_write_address")) state.trace_write_address != null else false;
    if (!isPreciseTimeQuery(
        dll_name,
        function_name,
        direct_return_rip,
        state.parallel_guest_execution,
        state.windows_runtime_enabled,
        state.diagnose_abi,
        trace_windows_memory,
        trace_write_address,
    )) return false;

    const scope = host.begin(state);
    defer host.end(state, scope);

    const return_rip = direct_return_rip.?;
    state.noteWindowsFastTimeImport(return_rip);
    const regs = state.windowsGuestContextField("regs");
    const output = regs.rcx;
    if (output != 0) state.write64(output, state.windowsGuestFastFileTime());
    regs.rax = 1;
    state.noteWindowsGuestClockRead();
    host.completeCall(state, direct_return_rip);
    state.clearWindowsFastTimeImportReturn();
    return true;
}

test "precise-time fast path accepts only known direct parallel imports" {
    const direct_return: ?u64 = 0x1400_1234;
    try std.testing.expect(isPreciseTimeQuery(
        "KERNEL32.DLL",
        "GetSystemTimePreciseAsFileTime",
        direct_return,
        true,
        true,
        false,
        false,
        false,
    ));
    try std.testing.expect(isPreciseTimeQuery(
        "api-ms-win-core-sysinfo-l1-2-1.dll",
        "GetSystemTimePreciseAsFileTime",
        direct_return,
        true,
        true,
        false,
        false,
        false,
    ));
    try std.testing.expect(!isPreciseTimeQuery(
        "kernel32.dll",
        "GetSystemTimePreciseAsFileTime",
        null,
        true,
        true,
        false,
        false,
        false,
    ));
    try std.testing.expect(!isPreciseTimeQuery(
        "kernel32.dll",
        "GetSystemTimePreciseAsFileTime",
        direct_return,
        false,
        true,
        false,
        false,
        false,
    ));
    try std.testing.expect(!isPreciseTimeQuery(
        "kernel32.dll",
        "GetSystemTimeAsFileTime",
        direct_return,
        true,
        true,
        false,
        false,
        false,
    ));
    try std.testing.expect(!isPreciseTimeQuery(
        "kernel32.dll",
        "GetSystemTimePreciseAsFileTime",
        direct_return,
        true,
        true,
        true,
        false,
        false,
    ));
    try std.testing.expect(!isPreciseTimeQuery(
        "kernel32.dll",
        "GetSystemTimePreciseAsFileTime",
        direct_return,
        true,
        true,
        false,
        true,
        false,
    ));
}

test "precise-time fast path writes the guest FILETIME and returns to its direct caller" {
    const Registers = struct {
        rax: u64 = 0,
        rcx: u64 = 0,
        rip: u64 = 0,
    };
    const Context = struct { regs: Registers = .{} };
    const FakeState = struct {
        parallel_guest_execution: bool = true,
        windows_runtime_enabled: bool = true,
        diagnose_abi: bool = false,
        context: Context = .{ .regs = .{ .rcx = 0x2000, .rip = 0x1400_1000 } },
        value_written: u64 = 0,
        address_written: u64 = 0,
        fast_imports: u32 = 0,
        clock_reads: u32 = 0,
        scope_begins: u32 = 0,
        scope_ends: u32 = 0,

        fn windowsGuestContextField(self: *@This(), comptime field: []const u8) *@FieldType(Context, field) {
            return &@field(self.context, field);
        }

        fn beginWindowsFastImportStoreScope(self: *@This()) void {
            self.scope_begins += 1;
        }

        fn endWindowsFastImportStoreScope(self: *@This(), _: void) void {
            self.scope_ends += 1;
        }

        fn noteWindowsFastTimeImport(self: *@This(), _: u64) void {
            self.fast_imports += 1;
        }

        fn clearWindowsFastTimeImportReturn(_: *@This()) void {}

        fn windowsGuestFastFileTime(_: *@This()) u64 {
            return 0x01DC_1234_5678_9ABC;
        }

        fn noteWindowsGuestClockRead(self: *@This()) void {
            self.clock_reads += 1;
        }

        fn write64(self: *@This(), address: u64, value: u64) void {
            self.address_written = address;
            self.value_written = value;
        }
    };
    const FakeHost = struct {
        fn begin(state: *FakeState) void {
            state.beginWindowsFastImportStoreScope();
        }

        fn end(state: *FakeState, scope: void) void {
            state.endWindowsFastImportStoreScope(scope);
        }

        fn completeCall(state: *FakeState, return_rip: ?u64) void {
            state.context.regs.rip = return_rip.?;
        }
    };

    var state: FakeState = .{};
    try std.testing.expect(tryPreciseTimeQuery(
        FakeHost,
        &state,
        "kernel32.dll",
        "GetSystemTimePreciseAsFileTime",
        0x1400_2345,
    ));
    try std.testing.expectEqual(@as(u64, 0x2000), state.address_written);
    try std.testing.expectEqual(@as(u64, 0x01DC_1234_5678_9ABC), state.value_written);
    try std.testing.expectEqual(@as(u64, 1), state.context.regs.rax);
    try std.testing.expectEqual(@as(u64, 0x1400_2345), state.context.regs.rip);
    try std.testing.expectEqual(@as(u32, 1), state.fast_imports);
    try std.testing.expectEqual(@as(u32, 1), state.clock_reads);
    try std.testing.expectEqual(@as(u32, 1), state.scope_begins);
    try std.testing.expectEqual(@as(u32, 1), state.scope_ends);
}
