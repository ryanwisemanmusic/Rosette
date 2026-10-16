//! Narrow imports whose parallel execution is safe without the Win32 runtime
//! table lock. Each candidate has an explicit contract and a small test
//! surface; growing this list requires proving that the handler has no shared
//! mutable state beyond its guest-memory output. The set: the clock queries
//! (GetSystemTimePreciseAsFileTime, QueryPerformanceCounter and
//! QueryPerformanceFrequency) and the C runtime's memcpy, memmove and memset.

const std = @import("std");
const crt_scan = @import("crt_scan.zig");

/// The clock queries the time lane answers. Each reads only the published
/// clock counter or a constant and writes one 64-bit guest output.
///
/// QueryPerformanceCounter is the hot one. Xenia's x64 backend compiles every
/// PowerPC `mftb` to `Clock::QueryGuestTickCount`, which calls it, so Halo 3's
/// render thread was inside it at every thread pulse of the 2026-09-30 run,
/// each call paying the runtime lock and then the guest clock's mutex.
pub const TimeQuery = enum(u2) { precise_file_time, performance_counter, performance_frequency };

/// On again since 2026-10-02. It was turned off after the 2026-09-30
/// round-3 run deadlocked at boot on Xenia's global critical region (with
/// a cheaper clock cadence in the same build). That deadlock was later
/// found in Xenia itself - `KeInsertQueueDpc_entry` runs the title's DPC
/// inline while it holds the lock - and is mitigated by lending the lock
/// (`yieldXeniaGlobalMutexForBackoff`); the clock cadence came back in
/// round 6 without it recurring. The answer is the published clock, which
/// every executor refreshes about every sixteen thousand instructions.
pub const counter_queries_enabled = true;

pub fn timeQuery(function_name: []const u8) ?TimeQuery {
    if (std.mem.eql(u8, function_name, "GetSystemTimePreciseAsFileTime")) return .precise_file_time;
    if (std.mem.eql(u8, function_name, "QueryPerformanceCounter")) return .performance_counter;
    if (std.mem.eql(u8, function_name, "QueryPerformanceFrequency")) return .performance_frequency;
    return null;
}

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
    const query = timeQuery(function_name) orelse return false;
    if (query != .precise_file_time and !counter_queries_enabled) return false;

    inline for (.{
        "kernel32.dll",
        "kernelbase.dll",
        "api-ms-win-core-profile-l1-1-0.dll",
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
        !@hasDecl(State, "windowsGuestFastClockTicks") or
        !@hasDecl(State, "windowsGuestClockHz") or
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
    const query = timeQuery(function_name).?;
    state.noteWindowsFastTimeImport(return_rip, query);
    const regs = state.windowsGuestContextField("regs");
    const output = regs.rcx;
    const value = switch (query) {
        .precise_file_time => state.windowsGuestFastFileTime(),
        .performance_counter => state.windowsGuestFastClockTicks(),
        .performance_frequency => state.windowsGuestClockHz(),
    };
    if (output != 0) state.write64(output, value);
    regs.rax = 1;
    // A frequency is a constant, not a reading; the locked handler does not
    // count it towards the scheduler's clock-poll detection either.
    if (query != .performance_frequency) state.noteWindowsGuestClockRead();
    host.completeCall(state, direct_return_rip);
    state.clearWindowsFastTimeImportReturn();
    return true;
}

/// The C runtime's block copy and fill. Their handlers touch nothing but the
/// guest memory they name: no handle, heap or window table. Xenia's host
/// code calls them constantly - the GPU command processor's uploads are
/// memcpy and memset - and each one paid the ordinary import's runtime lock,
/// register snapshot and call-site decode, about 3.6 microseconds, for a copy
/// that is usually a few dozen bytes.
pub const CrtMemoryOp = enum(u2) { copy, move, fill };

/// CRT calls which appeared frequently in the Oct 5 import histogram. The
/// compare/length operations read only guest bytes; strxfrm is admitted only
/// for the known C-locale behavior and uses the coordinated guest writer.
pub const CrtStringOp = enum(u2) { compare_bytes, string_length, compare_strings, locale_transform };

const crt_string_scan_limit: usize = 1 << 20;
const crt_compare_chunk_bytes: usize = 512;

pub fn crtStringOp(dll_name: []const u8, function_name: []const u8) ?CrtStringOp {
    if (!isWindowsModule(dll_name, .{
        "api-ms-win-crt-private-l1-1-0.dll",
        "api-ms-win-crt-string-l1-1-0.dll",
        "msvcrt.dll",
        "ucrtbase.dll",
        "ucrtbased.dll",
        "vcruntime140.dll",
    })) return null;
    if (std.mem.eql(u8, function_name, "memcmp")) return .compare_bytes;
    if (std.mem.eql(u8, function_name, "strlen")) return .string_length;
    if (std.mem.eql(u8, function_name, "strcmp")) return .compare_strings;
    if (std.mem.eql(u8, function_name, "strxfrm")) return .locale_transform;
    return null;
}

/// Fast implementations of the high-count CRT imports in the Oct 5 run. The
/// caller has already validated the exact import binding; this lane is enabled
/// only in parallel runtime mode, with string/memory tracing off and no runtime
/// dispatch held by this context. Reads are coordinated snapshots, and the
/// C-locale transform stages source bytes before its coordinated output write.
pub fn tryCrtStrings(host: anytype, state: anytype, dll_name: []const u8, function_name: []const u8, direct_return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "parallel_guest_execution") or
        !@hasField(State, "windows_runtime_enabled") or
        !@hasField(State, "diagnose_abi") or
        !@hasDecl(State, "windowsGuestContextField") or
        !@hasDecl(State, "copyFromGuest") or
        !@hasDecl(State, "copyToGuest") or
        !@hasDecl(State, "guestMemory") or
        !@hasDecl(State, "guestMemoryTailConst") or
        !@hasDecl(State, "beginWindowsFastImportStoreScope") or
        !@hasDecl(State, "endWindowsFastImportStoreScope") or
        !@hasDecl(State, "windowsFastCrtImportMayBypassRuntimeLock") or
        !@hasDecl(State, "noteWindowsFastCrtStringImport")) return false;
    const op = crtStringOp(dll_name, function_name) orelse return false;
    if (!state.parallel_guest_execution or !state.windows_runtime_enabled or state.diagnose_abi) return false;
    if (direct_return_rip == null or !state.windowsFastCrtImportMayBypassRuntimeLock()) return false;
    // The mapped-write trace does not observe reads. Keep read-only imports
    // off the shared dispatcher while that trace is live; only strxfrm writes
    // guest bytes and therefore retains the trace's ordinary path.
    if (op == .locale_transform) {
        if (comptime @hasDecl(State, "windowsMemoryTraceLive")) {
            if (state.windowsMemoryTraceLive()) return false;
        }
        if (comptime @hasField(State, "trace_write_address")) {
            if (state.trace_write_address != null) return false;
        }
    }
    if (comptime @hasField(State, "trace_windows_mappings")) {
        if (state.trace_windows_mappings) return false;
    }
    if (comptime @hasField(State, "trace_string_memory")) {
        if (state.trace_string_memory) return false;
    }

    const scope = host.begin(state);
    defer host.end(state, scope);

    const regs = state.windowsGuestContextField("regs");
    const result: ?i64 = switch (op) {
        .compare_bytes => if (fastCompareGuestRanges(state, regs.rcx, regs.rdx, regs.r8)) |value| value else null,
        .string_length => if (fastCStringLength(state, regs.rcx)) |value| value else null,
        .compare_strings => if (fastCompareGuestStrings(state, regs.rcx, regs.rdx)) |value| value else null,
        .locale_transform => fastCrtStrxfrm(state, regs.rcx, regs.rdx, regs.r8),
    };
    if (result == null) return false;
    regs.rax = @bitCast(result.?);
    state.noteWindowsFastCrtStringImport(op);
    host.completeCall(state, direct_return_rip);
    return true;
}

/// The current Windows runtime uses the C locale, where `strxfrm` copies the
/// source bytes and returns the full source length. Xenia calls this from its
/// option parser's regex path; stage short strings before writing so an
/// overlapping source/destination pair has the same behavior as the locked
/// handler. The scan copies each guest chunk directly into the staging buffer,
/// avoiding a second guest snapshot of the same prefix. Longer or unreadable
/// inputs return to that handler unchanged.
const crt_strxfrm_source_limit: usize = 512;

fn fastCrtStrxfrm(state: anytype, destination: u64, source: u64, capacity: u64) ?i64 {
    // When the caller only asks for the length, avoid staging bytes that will
    // not be written. For the common transforming form, stage and inspect in
    // one coordinated guest read per chunk.
    if (destination == 0 or capacity == 0) {
        const source_length = fastCStringLength(state, source) orelse return null;
        if (source_length > crt_strxfrm_source_limit) return null;
        return source_length;
    }

    var staged: [crt_strxfrm_source_limit + 1]u8 = undefined;
    const source_length = fastCStringStage(state, source, &staged) orelse return null;
    if (source_length < 0 or source_length > crt_strxfrm_source_limit) return null;
    const length: usize = @intCast(source_length);

    const capacity_usize: usize = if (capacity > std.math.maxInt(usize))
        std.math.maxInt(usize)
    else
        @intCast(capacity);
    const copy_count = @min(length, capacity_usize);
    const needs_terminator = copy_count < capacity_usize;
    const output_count = copy_count + @intFromBool(needs_terminator);
    if (needs_terminator) staged[copy_count] = 0;
    if (state.guestMemory(destination, @intCast(output_count)) == null) return null;
    if (!state.copyToGuest(destination, staged[0..output_count])) return null;
    return source_length;
}

fn fastCStringStage(state: anytype, address: u64, staged: []u8) ?i32 {
    const tail = state.guestMemoryTailConst(address, staged.len) orelse return null;
    if (tail.len == 0) return null;

    var offset: usize = 0;
    while (offset < tail.len) {
        const amount = @min(crt_compare_chunk_bytes, tail.len - offset);
        const at = std.math.add(u64, address, offset) catch return null;
        if (!state.copyFromGuest(staged[offset..][0..amount], at)) return null;
        if (crt_scan.firstZero(staged[offset..][0..amount])) |terminator| {
            return std.math.cast(i32, offset + terminator) orelse null;
        }
        offset += amount;
    }
    return null;
}

fn fastCompareGuestRanges(state: anytype, left: u64, right: u64, count: u64) ?i32 {
    if (count == 0) return 0;
    if (count > std.math.maxInt(usize)) return null;
    var left_bytes: [crt_compare_chunk_bytes]u8 = undefined;
    var right_bytes: [crt_compare_chunk_bytes]u8 = undefined;
    var offset: u64 = 0;
    while (offset < count) {
        const amount: usize = @intCast(@min(count - offset, crt_compare_chunk_bytes));
        const left_address = std.math.add(u64, left, offset) catch return null;
        const right_address = std.math.add(u64, right, offset) catch return null;
        if (!state.copyFromGuest(left_bytes[0..amount], left_address) or
            !state.copyFromGuest(right_bytes[0..amount], right_address)) return null;
        if (crt_scan.firstDifference(left_bytes[0..amount], right_bytes[0..amount])) |difference| {
            return @as(i32, left_bytes[difference]) - @as(i32, right_bytes[difference]);
        }
        offset += amount;
    }
    return 0;
}

fn fastCStringLength(state: anytype, address: u64) ?i32 {
    const tail = state.guestMemoryTailConst(address, crt_string_scan_limit) orelse return null;
    if (tail.len == 0) return null;
    var chunk: [crt_compare_chunk_bytes]u8 = undefined;
    var offset: usize = 0;
    while (offset < tail.len) {
        const amount = @min(tail.len - offset, chunk.len);
        const at = std.math.add(u64, address, offset) catch return null;
        if (!state.copyFromGuest(chunk[0..amount], at)) return null;
        if (crt_scan.firstZero(chunk[0..amount])) |terminator| {
            return std.math.cast(i32, offset + terminator) orelse null;
        }
        offset += amount;
    }
    // The ordinary handler treats an unreadable or unterminated bounded
    // snapshot as a refusal. Let it preserve its existing diagnostics.
    return null;
}

fn fastCompareGuestStrings(state: anytype, left: u64, right: u64) ?i32 {
    const left_tail = state.guestMemoryTailConst(left, crt_string_scan_limit) orelse return null;
    const right_tail = state.guestMemoryTailConst(right, crt_string_scan_limit) orelse return null;
    if (left_tail.len == 0 or right_tail.len == 0) return null;

    var left_bytes: [crt_compare_chunk_bytes]u8 = undefined;
    var right_bytes: [crt_compare_chunk_bytes]u8 = undefined;
    var offset: usize = 0;
    while (offset < crt_string_scan_limit) {
        if (offset >= left_tail.len or offset >= right_tail.len) return null;
        const amount = @min(crt_compare_chunk_bytes, @min(left_tail.len - offset, right_tail.len - offset));
        const left_address = std.math.add(u64, left, offset) catch return null;
        const right_address = std.math.add(u64, right, offset) catch return null;
        if (!state.copyFromGuest(left_bytes[0..amount], left_address) or
            !state.copyFromGuest(right_bytes[0..amount], right_address)) return null;
        switch (crt_scan.compareStringChunk(left_bytes[0..amount], right_bytes[0..amount])) {
            .continue_scan => offset += amount,
            .result => |result| return result,
        }
    }
    // Unterminated bounded snapshots remain on the ordinary CRT path.
    return null;
}

pub fn crtMemoryOp(dll_name: []const u8, function_name: []const u8) ?CrtMemoryOp {
    const op: CrtMemoryOp = if (std.mem.eql(u8, function_name, "memcpy"))
        .copy
    else if (std.mem.eql(u8, function_name, "memmove"))
        .move
    else if (std.mem.eql(u8, function_name, "memset"))
        .fill
    else
        return null;
    inline for (.{
        "api-ms-win-crt-private-l1-1-0.dll",
        "api-ms-win-crt-string-l1-1-0.dll",
        "msvcrt.dll",
        "ucrtbase.dll",
        "ucrtbased.dll",
        "vcruntime140.dll",
        "ntdll.dll",
    }) |module| {
        if (std.ascii.eqlIgnoreCase(dll_name, module)) return op;
    }
    return null;
}

/// Run memcpy, memmove or memset without the runtime lock, through the
/// state's own TSO-aware writers (`copyGuestRange`, `fillGuestMemory`), which
/// keep the overlap direction, the device and fault-routed memory classes
/// and the executable-write generations the locked handler relies on.
///
/// Only the success path is taken here. Both writers resolve every byte
/// before they write one, so a range they refuse is returned untouched to
/// the ordinary handler, which reports the unreadable pointer. Any trace the
/// ordinary handler would feed keeps the call on that path too.
/// The identity queries Xenia makes on every recursive-mutex entry and
/// logging call: GetCurrentThreadId, GetCurrentThread, GetCurrentProcess and
/// GetCurrentProcessId. Each is a constant or the calling context's own
/// thread ID, so none needs the runtime lock. On 2026-10-02 they were 3.4M
/// calls at about 2.7 us each through the locked dispatcher.
pub const IdentityQuery = enum { thread_id, thread, process, process_id };

pub fn identityQuery(dll_name: []const u8, function_name: []const u8) ?IdentityQuery {
    if (!std.ascii.eqlIgnoreCase(dll_name, "KERNEL32.dll") and !std.ascii.eqlIgnoreCase(dll_name, "api-ms-win-core-processthreads-l1-1-0.dll")) return null;
    if (std.mem.eql(u8, function_name, "GetCurrentThreadId")) return .thread_id;
    if (std.mem.eql(u8, function_name, "GetCurrentThread")) return .thread;
    if (std.mem.eql(u8, function_name, "GetCurrentProcess")) return .process;
    if (std.mem.eql(u8, function_name, "GetCurrentProcessId")) return .process_id;
    return null;
}

pub fn tryIdentityQuery(host: anytype, state: anytype, dll_name: []const u8, function_name: []const u8, direct_return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "parallel_guest_execution") or
        !@hasField(State, "windows_runtime_enabled") or
        !@hasField(State, "diagnose_abi") or
        !@hasDecl(State, "currentWindowsThreadId") or
        !@hasDecl(State, "windowsGuestContextField") or
        !@hasDecl(State, "beginWindowsFastImportStoreScope") or
        !@hasDecl(State, "endWindowsFastImportStoreScope")) return false;
    const query = identityQuery(dll_name, function_name) orelse return false;
    if (!state.parallel_guest_execution or !state.windows_runtime_enabled or state.diagnose_abi) return false;
    if (direct_return_rip == null) return false;
    const scope = host.begin(state);
    defer host.end(state, scope);
    const regs = state.windowsGuestContextField("regs");
    regs.rax = switch (query) {
        .thread_id => state.currentWindowsThreadId(),
        .thread => std.math.maxInt(u64) - 1,
        .process => std.math.maxInt(u64),
        .process_id => 1,
    };
    if (comptime @hasDecl(State, "noteWindowsFastIdentityImport")) state.noteWindowsFastIdentityImport();
    host.completeCall(state, direct_return_rip);
    return true;
}

/// A read-only process-topology query. The process and system masks are
/// published atomically by ElfState; the two guest output stores retain the
/// ordinary runtime-call TSO boundary.
pub fn tryProcessAffinityMask(host: anytype, state: anytype, dll_name: []const u8, function_name: []const u8, direct_return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "parallel_guest_execution") or
        !@hasField(State, "windows_runtime_enabled") or
        !@hasField(State, "diagnose_abi") or
        !@hasDecl(State, "windowsFastAffinityMasks") or
        !@hasDecl(State, "windowsGuestContextField") or
        !@hasDecl(State, "guestMemory") or
        !@hasDecl(State, "write64") or
        !@hasDecl(State, "beginWindowsFastImportStoreScope") or
        !@hasDecl(State, "endWindowsFastImportStoreScope") or
        !@hasDecl(State, "noteWindowsFastAffinityImport")) return false;
    if (!std.mem.eql(u8, function_name, "GetProcessAffinityMask")) return false;
    if (!isWindowsModule(dll_name, .{ "kernel32.dll", "kernelbase.dll", "api-ms-win-core-processthreads-l1-1-0.dll" })) return false;
    if (!state.parallel_guest_execution or !state.windows_runtime_enabled or state.diagnose_abi or direct_return_rip == null) return false;
    if (comptime @hasDecl(State, "windowsMemoryTraceLive")) {
        if (state.windowsMemoryTraceLive()) return false;
    }
    if (comptime @hasField(State, "trace_write_address")) {
        if (state.trace_write_address != null) return false;
    }
    if (comptime @hasField(State, "trace_windows_mappings")) {
        if (state.trace_windows_mappings) return false;
    }

    const scope = host.begin(state);
    defer host.end(state, scope);

    const regs = state.windowsGuestContextField("regs");
    const process_output = regs.rdx;
    const system_output = regs.r8;
    // Match the locked handler: validate both destinations before writing
    // either one, and let its error path handle invalid guest pointers.
    if (process_output == 0 or system_output == 0 or
        state.guestMemory(process_output, 8) == null or state.guestMemory(system_output, 8) == null) return false;
    const masks = state.windowsFastAffinityMasks();
    state.write64(process_output, masks[0]);
    state.write64(system_output, masks[1]);
    state.windowsGuestContextField("windows_last_error").* = 0;
    regs.rax = 1;
    state.noteWindowsFastAffinityImport(direct_return_rip.?);
    host.completeCall(state, direct_return_rip);
    if (comptime @hasDecl(State, "clearWindowsFastTimeImportReturn")) state.clearWindowsFastTimeImportReturn();
    return true;
}

/// `Sleep(0)` is a scheduler yield, not a timed park. Only direct, parallel
/// worker calls with no Xenia-global-mutex ownership use this path; nonzero
/// Sleep and SleepEx stay in the scheduler-aware dispatcher.
pub fn trySleepZero(host: anytype, state: anytype, dll_name: []const u8, function_name: []const u8, direct_return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "parallel_guest_execution") or
        !@hasField(State, "windows_runtime_enabled") or
        !@hasField(State, "diagnose_abi") or
        !@hasDecl(State, "windowsFastCrtImportMayBypassRuntimeLock") or
        !@hasDecl(State, "windowsGuestContextField") or
        !@hasDecl(State, "requestWindowsGuestSliceYield") or
        !@hasDecl(State, "windowsFastSleepZeroImportAllowed") or
        !@hasDecl(State, "beginWindowsFastImportStoreScope") or
        !@hasDecl(State, "endWindowsFastImportStoreScope") or
        !@hasDecl(State, "noteWindowsFastSleepZeroImport")) return false;
    if (!std.mem.eql(u8, function_name, "Sleep") or !isWindowsModule(dll_name, .{ "kernel32.dll", "kernelbase.dll" })) return false;
    if (!state.parallel_guest_execution or !state.windows_runtime_enabled or state.diagnose_abi or direct_return_rip == null) return false;
    if (!state.windowsFastCrtImportMayBypassRuntimeLock()) return false;
    const regs = state.windowsGuestContextField("regs");
    if (regs.rcx != 0) return false;

    const scope = host.begin(state);
    defer host.end(state, scope);
    if (!state.windowsFastSleepZeroImportAllowed()) return false;

    regs.rax = 0;
    state.noteWindowsFastSleepZeroImport(direct_return_rip.?);
    host.completeCall(state, direct_return_rip);
    state.requestWindowsGuestSliceYield();
    if (comptime @hasDecl(State, "clearWindowsFastTimeImportReturn")) state.clearWindowsFastTimeImportReturn();
    return true;
}

fn isWindowsModule(dll_name: []const u8, comptime modules: anytype) bool {
    inline for (modules) |module| {
        if (std.ascii.eqlIgnoreCase(dll_name, module)) return true;
    }
    return false;
}

test "identity queries are recognised by name and DLL" {
    try std.testing.expectEqual(IdentityQuery.thread_id, identityQuery("KERNEL32.dll", "GetCurrentThreadId").?);
    try std.testing.expectEqual(IdentityQuery.process, identityQuery("kernel32.dll", "GetCurrentProcess").?);
    try std.testing.expectEqual(@as(?IdentityQuery, null), identityQuery("KERNEL32.dll", "GetThreadId"));
    try std.testing.expectEqual(@as(?IdentityQuery, null), identityQuery("USER32.dll", "GetCurrentThreadId"));
}

pub fn tryCrtMemory(host: anytype, state: anytype, dll_name: []const u8, function_name: []const u8, direct_return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "parallel_guest_execution") or
        !@hasField(State, "windows_runtime_enabled") or
        !@hasField(State, "diagnose_abi") or
        !@hasDecl(State, "copyGuestRange") or
        !@hasDecl(State, "fillGuestMemory") or
        !@hasDecl(State, "windowsGuestContextField") or
        !@hasDecl(State, "beginWindowsFastImportStoreScope") or
        !@hasDecl(State, "endWindowsFastImportStoreScope") or
        !@hasDecl(State, "noteWindowsFastCrtImport")) return false;
    const op = crtMemoryOp(dll_name, function_name) orelse return false;
    if (!state.parallel_guest_execution or !state.windows_runtime_enabled or state.diagnose_abi) return false;
    if (direct_return_rip == null) return false;
    if (comptime @hasDecl(State, "windowsMemoryTraceLive")) {
        if (state.windowsMemoryTraceLive()) return false;
    }
    if (comptime @hasField(State, "trace_write_address")) {
        if (state.trace_write_address != null) return false;
    }
    if (comptime @hasField(State, "trace_windows_mappings")) {
        if (state.trace_windows_mappings) return false;
    }
    if (comptime @hasField(State, "trace_string_memory")) {
        if (state.trace_string_memory) return false;
    }

    const scope = host.begin(state);
    defer host.end(state, scope);

    const regs = state.windowsGuestContextField("regs");
    const destination = regs.rcx;
    const count = regs.r8;
    const done = count == 0 or switch (op) {
        .copy, .move => state.copyGuestRange(destination, regs.rdx, count),
        .fill => state.fillGuestMemory(destination, count, @truncate(regs.rdx)),
    };
    if (!done) return false;
    regs.rax = destination;
    state.noteWindowsFastCrtImport(op);
    host.completeCall(state, direct_return_rip);
    return true;
}

test "the CRT memory lane accepts only memcpy memmove and memset from C runtime modules" {
    try std.testing.expectEqual(CrtMemoryOp.copy, crtMemoryOp("api-ms-win-crt-private-l1-1-0.dll", "memcpy").?);
    try std.testing.expectEqual(CrtMemoryOp.move, crtMemoryOp("API-MS-WIN-CRT-PRIVATE-L1-1-0.DLL", "memmove").?);
    try std.testing.expectEqual(CrtMemoryOp.fill, crtMemoryOp("api-ms-win-crt-string-l1-1-0.dll", "memset").?);
    try std.testing.expectEqual(CrtMemoryOp.copy, crtMemoryOp("msvcrt.dll", "memcpy").?);
    try std.testing.expect(crtMemoryOp("kernel32.dll", "memcpy") == null);
    try std.testing.expect(crtMemoryOp("api-ms-win-crt-string-l1-1-0.dll", "memcmp") == null);
    try std.testing.expect(crtMemoryOp("api-ms-win-crt-string-l1-1-0.dll", "strlen") == null);
}

test "the CRT memory lane copies fills and returns, and hands refusals back untouched" {
    const Registers = struct { rax: u64 = 0, rcx: u64 = 0, rdx: u64 = 0, r8: u64 = 0, rip: u64 = 0 };
    const Context = struct { regs: Registers = .{} };
    const FakeState = struct {
        parallel_guest_execution: bool = true,
        windows_runtime_enabled: bool = true,
        diagnose_abi: bool = false,
        trace_string_memory: bool = false,
        context: Context = .{},
        memory: [64]u8 = @splat(0),
        crt_calls: u32 = 0,
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
        fn noteWindowsFastCrtImport(self: *@This(), _: CrtMemoryOp) void {
            self.crt_calls += 1;
        }
        fn copyGuestRange(self: *@This(), destination: u64, source: u64, count: u64) bool {
            if (destination + count > self.memory.len or source + count > self.memory.len) return false;
            std.mem.copyForwards(u8, self.memory[@intCast(destination)..][0..@intCast(count)], self.memory[@intCast(source)..][0..@intCast(count)]);
            return true;
        }
        fn fillGuestMemory(self: *@This(), destination: u64, count: u64, value: u8) bool {
            if (destination + count > self.memory.len) return false;
            @memset(self.memory[@intCast(destination)..][0..@intCast(count)], value);
            return true;
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
    for (state.memory[0..8], 0..) |*byte, index| byte.* = @intCast(index + 1);
    state.context.regs = .{ .rcx = 32, .rdx = 0, .r8 = 8 };
    try std.testing.expect(tryCrtMemory(FakeHost, &state, "api-ms-win-crt-private-l1-1-0.dll", "memcpy", 0x1400_1000));
    try std.testing.expectEqualSlices(u8, state.memory[0..8], state.memory[32..40]);
    try std.testing.expectEqual(@as(u64, 32), state.context.regs.rax);
    try std.testing.expectEqual(@as(u64, 0x1400_1000), state.context.regs.rip);

    state.context.regs = .{ .rcx = 40, .rdx = 0xAB, .r8 = 4 };
    try std.testing.expect(tryCrtMemory(FakeHost, &state, "api-ms-win-crt-string-l1-1-0.dll", "memset", 0x1400_2000));
    try std.testing.expectEqualSlices(u8, &.{ 0xAB, 0xAB, 0xAB, 0xAB }, state.memory[40..44]);
    try std.testing.expectEqual(@as(u64, 40), state.context.regs.rax);

    // A zero count dereferences nothing and still answers the destination.
    state.context.regs = .{ .rcx = 0x7777_0000, .rdx = 0x7777_1000, .r8 = 0 };
    try std.testing.expect(tryCrtMemory(FakeHost, &state, "api-ms-win-crt-private-l1-1-0.dll", "memmove", 0x1400_3000));
    try std.testing.expectEqual(@as(u64, 0x7777_0000), state.context.regs.rax);

    // A range the writer refuses goes back to the ordinary handler with
    // nothing written and no return taken.
    state.context.regs = .{ .rcx = 60, .rdx = 0, .r8 = 8, .rip = 0x1400_4000 };
    try std.testing.expect(!tryCrtMemory(FakeHost, &state, "api-ms-win-crt-private-l1-1-0.dll", "memcpy", 0x1400_5000));
    try std.testing.expectEqual(@as(u64, 0x1400_4000), state.context.regs.rip);
    try std.testing.expectEqual(@as(u32, 3), state.crt_calls);
    try std.testing.expectEqual(state.scope_begins, state.scope_ends);

    // A trace the ordinary handler feeds keeps the call there.
    state.trace_string_memory = true;
    state.context.regs = .{ .rcx = 32, .rdx = 0, .r8 = 8 };
    try std.testing.expect(!tryCrtMemory(FakeHost, &state, "api-ms-win-crt-private-l1-1-0.dll", "memcpy", 0x1400_6000));
}

test "the CRT read-only string lane compares and measures guest snapshots without the runtime lock" {
    const Registers = struct { rax: u64 = 0, rcx: u64 = 0, rdx: u64 = 0, r8: u64 = 0, rip: u64 = 0 };
    const Context = struct { regs: Registers = .{} };
    const FakeState = struct {
        parallel_guest_execution: bool = true,
        windows_runtime_enabled: bool = true,
        diagnose_abi: bool = false,
        trace_string_memory: bool = false,
        trace_windows_mappings: bool = false,
        trace_write_address: ?u64 = null,
        memory_trace_live: bool = false,
        context: Context = .{},
        memory: [2048]u8 = @splat(0),
        calls: [4]u32 = @splat(0),
        copy_calls: u32 = 0,
        copied_bytes: usize = 0,
        scope_begins: u32 = 0,
        scope_ends: u32 = 0,

        fn windowsGuestContextField(self: *@This(), comptime field: []const u8) *@FieldType(Context, field) {
            return &@field(self.context, field);
        }
        fn windowsFastCrtImportMayBypassRuntimeLock(_: *@This()) bool {
            return true;
        }
        fn windowsMemoryTraceLive(self: *@This()) bool {
            return self.memory_trace_live;
        }
        fn beginWindowsFastImportStoreScope(self: *@This()) void {
            self.scope_begins += 1;
        }
        fn endWindowsFastImportStoreScope(self: *@This(), _: void) void {
            self.scope_ends += 1;
        }
        fn noteWindowsFastCrtStringImport(self: *@This(), op: CrtStringOp) void {
            self.calls[@intFromEnum(op)] += 1;
        }
        fn guestMemoryTailConst(self: *@This(), address: u64, maximum: usize) ?[]const u8 {
            if (address >= self.memory.len) return null;
            const start: usize = @intCast(address);
            return self.memory[start..@min(self.memory.len, start +| maximum)];
        }
        fn copyFromGuest(self: *@This(), destination: []u8, address: u64) bool {
            if (address > self.memory.len) return false;
            const start: usize = @intCast(address);
            if (destination.len > self.memory.len - start) return false;
            self.copy_calls += 1;
            self.copied_bytes += destination.len;
            @memcpy(destination, self.memory[start..][0..destination.len]);
            return true;
        }
        fn guestMemory(self: *@This(), address: u64, count: u64) ?[]u8 {
            if (address >= self.memory.len) return null;
            const start: usize = @intCast(address);
            const length: usize = std.math.cast(usize, count) orelse return null;
            if (length > self.memory.len - start) return null;
            return self.memory[start..][0..length];
        }
        fn copyToGuest(self: *@This(), address: u64, source: []const u8) bool {
            const destination = self.guestMemory(address, @intCast(source.len)) orelse return false;
            @memcpy(destination, source);
            return true;
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

    try std.testing.expectEqual(CrtStringOp.compare_bytes, crtStringOp("api-ms-win-crt-private-l1-1-0.dll", "memcmp").?);
    try std.testing.expectEqual(CrtStringOp.string_length, crtStringOp("API-MS-WIN-CRT-STRING-L1-1-0.DLL", "strlen").?);
    try std.testing.expectEqual(CrtStringOp.compare_strings, crtStringOp("ucrtbase.dll", "strcmp").?);
    try std.testing.expectEqual(CrtStringOp.locale_transform, crtStringOp("api-ms-win-crt-string-l1-1-0.dll", "strxfrm").?);
    try std.testing.expect(crtStringOp("kernel32.dll", "memcmp") == null);
    try std.testing.expect(crtStringOp("ucrtbase.dll", "strncmp") == null);

    var state: FakeState = .{};
    @memcpy(state.memory[0..6], "alpha\x00");
    @memcpy(state.memory[16..22], "alpha\x00");
    state.memory[40] = 0x10;
    state.memory[41] = 0x20;
    state.memory[48] = 0x10;
    state.memory[49] = 0x21;

    state.context.regs = .{ .rcx = 40, .rdx = 48, .r8 = 2 };
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "api-ms-win-crt-private-l1-1-0.dll", "memcmp", 0x1400_1000));
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -1))), state.context.regs.rax);

    state.context.regs = .{ .rcx = 0 };
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "api-ms-win-crt-string-l1-1-0.dll", "strlen", 0x1400_2000));
    try std.testing.expectEqual(@as(u64, 5), state.context.regs.rax);

    state.context.regs = .{ .rcx = 0, .rdx = 16 };
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strcmp", 0x1400_3000));
    try std.testing.expectEqual(@as(u64, 0), state.context.regs.rax);
    try std.testing.expectEqual(@as(u64, 0x1400_3000), state.context.regs.rip);
    try std.testing.expectEqual([_]u32{ 1, 1, 1, 0 }, state.calls);
    try std.testing.expectEqual(state.scope_begins, state.scope_ends);

    // A shared equal prefix is visited once, including strings longer than a
    // guest snapshot chunk. A late mismatch still returns the first byte's
    // signed difference, and a terminator takes precedence over later bytes.
    @memset(state.memory[128..828], 'q');
    @memset(state.memory[1024..1724], 'q');
    state.memory[828] = 0;
    state.memory[1724] = 0;
    state.context.regs = .{ .rcx = 128, .rdx = 1024 };
    state.copy_calls = 0;
    state.copied_bytes = 0;
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strcmp", 0x1400_3050));
    try std.testing.expectEqual(@as(u64, 0), state.context.regs.rax);
    // The new path reads four bounded chunks. The previous implementation
    // scanned both strings for NUL (four chunks), then copied the shared
    // prefix again (four more chunks): 3448 bytes in eight snapshots here.
    try std.testing.expectEqual(@as(u32, 4), state.copy_calls);
    try std.testing.expectEqual(@as(usize, 2048), state.copied_bytes);

    state.memory[1024 + 517] = 'r';
    state.context.regs = .{ .rcx = 128, .rdx = 1024 };
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strcmp", 0x1400_3060));
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -1))), state.context.regs.rax);

    state.memory[128 + 511] = 0;
    state.memory[1024 + 511] = 'r';
    state.context.regs = .{ .rcx = 128, .rdx = 1024 };
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strcmp", 0x1400_3070));
    try std.testing.expect(state.context.regs.rax == 0 or @as(i64, @bitCast(state.context.regs.rax)) < 0);

    // The launcher enables a mapped-write trace. Read-only operations still
    // use snapshots, while the transforming operation is kept on the locked
    // path when a guest write would need tracing.
    state.memory_trace_live = true;
    state.context.regs = .{ .rcx = 0 };
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strlen", 0x1400_3100));
    @memcpy(state.memory[64..70], "hello\x00");
    state.context.regs = .{ .rcx = 80, .rdx = 64, .r8 = 8 };
    try std.testing.expect(!tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strxfrm", 0x1400_3200));
    state.memory_trace_live = false;

    state.context.regs = .{ .rcx = 80, .rdx = 64, .r8 = 8 };
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strxfrm", 0x1400_3300));
    try std.testing.expectEqual(@as(u64, 5), state.context.regs.rax);
    try std.testing.expectEqualStrings("hello\x00", state.memory[80..86]);
    try std.testing.expectEqual(@as(u64, 0x1400_3300), state.context.regs.rip);

    // The staging scan reads each source chunk once. The former length scan
    // plus copy read this 400-byte prefix twice (512 + 400 bytes total).
    @memset(state.memory[256..656], 'z');
    state.memory[656] = 0;
    state.copy_calls = 0;
    state.copied_bytes = 0;
    state.context.regs = .{ .rcx = 800, .rdx = 256, .r8 = 512 };
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strxfrm", 0x1400_3350));
    try std.testing.expectEqual(@as(u64, 400), state.context.regs.rax);
    try std.testing.expectEqualSlices(u8, state.memory[256..657], state.memory[800..1201]);
    try std.testing.expectEqual(@as(u32, 1), state.copy_calls);
    try std.testing.expectEqual(@as(usize, 512), state.copied_bytes);

    // strxfrm copies exactly capacity bytes and does not append NUL when the
    // transformed source is at least that long.
    @memset(state.memory[96..102], 0xA5);
    state.context.regs = .{ .rcx = 96, .rdx = 64, .r8 = 5 };
    try std.testing.expect(tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strxfrm", 0x1400_3400));
    try std.testing.expectEqualStrings("hello", state.memory[96..101]);
    try std.testing.expectEqual(@as(u8, 0xA5), state.memory[101]);

    state.trace_write_address = 80;
    state.context.regs = .{ .rcx = 80, .rdx = 64, .r8 = 8 };
    try std.testing.expect(!tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strxfrm", 0x1400_3500));
    state.trace_write_address = null;

    // An invalid pointer or an active string trace must leave the call to the
    // ordinary handler, which retains its fault accounting and byte trace.
    state.context.regs = .{ .rcx = 0x1000 };
    try std.testing.expect(!tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strlen", 0x1400_4000));
    state.trace_string_memory = true;
    state.context.regs = .{ .rcx = 0 };
    try std.testing.expect(!tryCrtStrings(FakeHost, &state, "ucrtbase.dll", "strlen", 0x1400_5000));
    try std.testing.expectEqual([_]u32{ 1, 2, 4, 3 }, state.calls);
}

pub const CrtHeapOp = enum(u2) { malloc_uninitialized, calloc_zeroed, aligned_malloc, free };

/// The allocator functions that dominated the 2026-10-05 run. Keep this to
/// CRT DLLs and direct imports; Win32 heaps, realloc variants, tracing modes,
/// and calls made from inside a runtime dispatch continue through the full
/// handler. The state allocator keeps its existing metadata lock.
pub fn crtHeapOp(dll_name: []const u8, function_name: []const u8) ?CrtHeapOp {
    if (!isWindowsModule(dll_name, .{
        "api-ms-win-crt-heap-l1-1-0.dll",
        "msvcrt.dll",
        "ucrtbase.dll",
        "ucrtbased.dll",
        "vcruntime140.dll",
    })) return null;
    if (std.mem.eql(u8, function_name, "malloc") or std.mem.eql(u8, function_name, "_malloc_base")) return .malloc_uninitialized;
    if (std.mem.eql(u8, function_name, "calloc")) return .calloc_zeroed;
    if (std.mem.eql(u8, function_name, "_aligned_malloc")) return .aligned_malloc;
    if (std.mem.eql(u8, function_name, "free") or std.mem.eql(u8, function_name, "_free_base") or std.mem.eql(u8, function_name, "_aligned_free")) return .free;
    return null;
}

pub fn tryCrtHeap(host: anytype, state: anytype, dll_name: []const u8, function_name: []const u8, direct_return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "parallel_guest_execution") or
        !@hasField(State, "windows_runtime_enabled") or
        !@hasField(State, "diagnose_abi") or
        !@hasDecl(State, "windowsFastCrtImportMayBypassRuntimeLock") or
        !@hasDecl(State, "windowsGuestContextField") or
        !@hasDecl(State, "guestAlloc") or
        !@hasDecl(State, "guestAllocUninitialized") or
        !@hasDecl(State, "releaseGuestAllocation") or
        !@hasDecl(State, "beginWindowsFastImportStoreScope") or
        !@hasDecl(State, "endWindowsFastImportStoreScope") or
        !@hasDecl(State, "noteWindowsFastHeapImport")) return false;
    const op = crtHeapOp(dll_name, function_name) orelse return false;
    if (!state.parallel_guest_execution or !state.windows_runtime_enabled or state.diagnose_abi or direct_return_rip == null) return false;
    if (!state.windowsFastCrtImportMayBypassRuntimeLock()) return false;
    if (comptime @hasDecl(State, "windowsMemoryTraceLive")) {
        if (state.windowsMemoryTraceLive()) return false;
    }
    if (comptime @hasField(State, "trace_write_address")) {
        if (state.trace_write_address != null) return false;
    }
    if (comptime @hasField(State, "trace_windows_mappings")) {
        if (state.trace_windows_mappings) return false;
    }
    if (comptime @hasField(State, "trace_allocations")) {
        if (state.trace_allocations) return false;
    }
    if (comptime @hasField(State, "trace_string_memory")) {
        if (state.trace_string_memory) return false;
    }

    const scope = host.begin(state);
    defer host.end(state, scope);
    const regs = state.windowsGuestContextField("regs");
    switch (op) {
        .malloc_uninitialized => regs.rax = state.guestAllocUninitialized(regs.rcx, 16) orelse 0,
        .calloc_zeroed => regs.rax = state.guestAlloc(regs.rcx *| regs.rdx, 16) orelse 0,
        .aligned_malloc => regs.rax = state.guestAllocUninitialized(regs.rcx, regs.rdx) orelse 0,
        .free => {
            _ = state.releaseGuestAllocation(regs.rcx);
            regs.rax = 0;
        },
    }
    const counter: enum(u2) { allocation, calloc, free } = switch (op) {
        .malloc_uninitialized, .aligned_malloc => .allocation,
        .calloc_zeroed => .calloc,
        .free => .free,
    };
    state.noteWindowsFastHeapImport(counter);
    host.completeCall(state, direct_return_rip);
    return true;
}

test "CRT heap fast dispatch preserves malloc versus calloc contracts" {
    const Registers = struct { rax: u64 = 0, rcx: u64 = 0, rdx: u64 = 0, rip: u64 = 0 };
    const Context = struct { regs: Registers = .{} };
    const FakeState = struct {
        parallel_guest_execution: bool = true,
        windows_runtime_enabled: bool = true,
        diagnose_abi: bool = false,
        trace_string_memory: bool = false,
        context: Context = .{},
        next_ptr: u64 = 0x1000,
        uninitialized_bytes: u64 = 0,
        zeroed_bytes: u64 = 0,
        freed: u64 = 0,
        fast_ops: [3]u32 = @splat(0),
        scope_begins: u32 = 0,
        scope_ends: u32 = 0,

        fn windowsGuestContextField(self: *@This(), comptime field: []const u8) *@FieldType(Context, field) {
            return &@field(self.context, field);
        }
        fn windowsFastCrtImportMayBypassRuntimeLock(_: *@This()) bool {
            return true;
        }
        fn beginWindowsFastImportStoreScope(self: *@This()) u8 {
            self.scope_begins += 1;
            return 1;
        }
        fn endWindowsFastImportStoreScope(self: *@This(), scope: u8) void {
            std.debug.assert(scope == 1);
            self.scope_ends += 1;
        }
        fn guestAllocUninitialized(self: *@This(), size: u64, _: u64) ?u64 {
            self.uninitialized_bytes += size;
            self.next_ptr += size;
            return self.next_ptr;
        }
        fn guestAlloc(self: *@This(), size: u64, _: u64) ?u64 {
            self.zeroed_bytes += size;
            self.next_ptr += size;
            return self.next_ptr;
        }
        fn releaseGuestAllocation(self: *@This(), ptr: u64) bool {
            self.freed = ptr;
            return true;
        }
        fn noteWindowsFastHeapImport(self: *@This(), op: anytype) void {
            self.fast_ops[@intFromEnum(op)] += 1;
        }
    };
    const FakeHost = struct {
        fn begin(state: *FakeState) u8 {
            return state.beginWindowsFastImportStoreScope();
        }
        fn end(state: *FakeState, scope: u8) void {
            state.endWindowsFastImportStoreScope(scope);
        }
        fn completeCall(state: *FakeState, return_rip: ?u64) void {
            state.context.regs.rip = return_rip.?;
        }
    };

    try std.testing.expectEqual(CrtHeapOp.malloc_uninitialized, crtHeapOp("API-MS-WIN-CRT-HEAP-L1-1-0.DLL", "malloc").?);
    try std.testing.expectEqual(CrtHeapOp.calloc_zeroed, crtHeapOp("ucrtbase.dll", "calloc").?);
    try std.testing.expectEqual(CrtHeapOp.aligned_malloc, crtHeapOp("msvcrt.dll", "_aligned_malloc").?);
    try std.testing.expect(crtHeapOp("kernel32.dll", "malloc") == null);
    try std.testing.expect(crtHeapOp("ucrtbase.dll", "realloc") == null);

    var state: FakeState = .{};
    state.context.regs = .{ .rcx = 32 };
    try std.testing.expect(tryCrtHeap(FakeHost, &state, "api-ms-win-crt-heap-l1-1-0.dll", "malloc", 0x1400_1000));
    try std.testing.expectEqual(@as(u64, 32), state.uninitialized_bytes);
    try std.testing.expectEqual(@as(u64, 0), state.zeroed_bytes);
    try std.testing.expectEqual(@as(u64, 0x1400_1000), state.context.regs.rip);

    state.context.regs = .{ .rcx = 4, .rdx = 8 };
    try std.testing.expect(tryCrtHeap(FakeHost, &state, "ucrtbase.dll", "calloc", 0x1400_2000));
    try std.testing.expectEqual(@as(u64, 32), state.zeroed_bytes);

    state.context.regs = .{ .rcx = 0x1234 };
    try std.testing.expect(tryCrtHeap(FakeHost, &state, "ucrtbase.dll", "free", 0x1400_3000));
    try std.testing.expectEqual(@as(u64, 0x1234), state.freed);
    try std.testing.expectEqual(@as(u64, 0), state.context.regs.rax);
    try std.testing.expectEqual(state.scope_begins, state.scope_ends);

    state.diagnose_abi = true;
    state.context.regs.rip = 0x1400_4000;
    try std.testing.expect(!tryCrtHeap(FakeHost, &state, "ucrtbase.dll", "malloc", 0x1400_5000));
    try std.testing.expectEqual(@as(u64, 0x1400_4000), state.context.regs.rip);
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
    try std.testing.expect(counter_queries_enabled);
    try std.testing.expect(isPreciseTimeQuery(
        "KERNEL32.dll",
        "QueryPerformanceCounter",
        direct_return,
        true,
        true,
        false,
        false,
        false,
    ));
    try std.testing.expect(isPreciseTimeQuery(
        "api-ms-win-core-profile-l1-1-0.dll",
        "QueryPerformanceFrequency",
        direct_return,
        true,
        true,
        false,
        false,
        false,
    ));
    try std.testing.expect(!isPreciseTimeQuery(
        "user32.dll",
        "QueryPerformanceCounter",
        direct_return,
        true,
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

        fn noteWindowsFastTimeImport(self: *@This(), _: u64, _: TimeQuery) void {
            self.fast_imports += 1;
        }

        fn clearWindowsFastTimeImportReturn(_: *@This()) void {}

        fn windowsGuestFastFileTime(_: *@This()) u64 {
            return 0x01DC_1234_5678_9ABC;
        }

        fn windowsGuestFastClockTicks(_: *@This()) u64 {
            return 0x1234_5678;
        }

        fn windowsGuestClockHz(_: *@This()) u64 {
            return 1_000_000;
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

    // QueryPerformanceCounter writes the published tick count and counts as
    // a clock read; QueryPerformanceFrequency writes the constant and does not.
    state.context.regs.rcx = 0x3000;
    try std.testing.expect(tryPreciseTimeQuery(FakeHost, &state, "KERNEL32.dll", "QueryPerformanceCounter", 0x1400_3456));
    try std.testing.expectEqual(@as(u64, 0x3000), state.address_written);
    try std.testing.expectEqual(@as(u64, 0x1234_5678), state.value_written);
    try std.testing.expectEqual(@as(u64, 0x1400_3456), state.context.regs.rip);
    try std.testing.expectEqual(@as(u32, 2), state.clock_reads);
    try std.testing.expect(tryPreciseTimeQuery(FakeHost, &state, "KERNEL32.dll", "QueryPerformanceFrequency", 0x1400_4567));
    try std.testing.expectEqual(@as(u64, 1_000_000), state.value_written);
    try std.testing.expectEqual(@as(u64, 1), state.context.regs.rax);
    try std.testing.expectEqual(@as(u32, 2), state.clock_reads);
    try std.testing.expectEqual(@as(u32, 3), state.fast_imports);
    try std.testing.expectEqual(@as(u32, 3), state.scope_ends);
}

test "GetProcessAffinityMask fast path validates both outputs before writing" {
    const Registers = struct {
        rax: u64 = 0xAAAA,
        rcx: u64 = 0,
        rdx: u64 = 0x1000,
        r8: u64 = 0x1010,
        rip: u64 = 0x1400_1000,
    };
    const Context = struct {
        regs: Registers = .{},
        windows_last_error: u32 = 99,
    };
    const FakeState = struct {
        parallel_guest_execution: bool = true,
        windows_runtime_enabled: bool = true,
        diagnose_abi: bool = false,
        trace_write_address: ?u64 = null,
        trace_windows_mappings: bool = false,
        memory: [24]u8 = [_]u8{0xA5} ** 24,
        context: Context = .{},
        allow_system_output: bool = true,
        fast_imports: u32 = 0,
        scope_begins: u32 = 0,
        scope_ends: u32 = 0,
        return_field: u64 = 0,

        fn windowsGuestContextField(self: *@This(), comptime field: []const u8) *@FieldType(Context, field) {
            return &@field(self.context, field);
        }

        fn guestMemory(self: *@This(), address: u64, length: usize) ?[]u8 {
            if (address < 0x1000) return null;
            const offset: usize = @intCast(address - 0x1000);
            if (offset + length > self.memory.len) return null;
            if (!self.allow_system_output and address >= 0x1010) return null;
            return self.memory[offset .. offset + length];
        }

        fn write64(self: *@This(), address: u64, value: u64) void {
            const offset: usize = @intCast(address - 0x1000);
            std.mem.writeInt(u64, self.memory[offset..][0..8], value, .little);
        }

        fn windowsFastAffinityMasks(_: *@This()) [2]u64 {
            return .{ 0x55, 0xAA };
        }

        fn beginWindowsFastImportStoreScope(self: *@This()) u32 {
            self.scope_begins += 1;
            return 7;
        }

        fn endWindowsFastImportStoreScope(self: *@This(), scope: u32) void {
            std.debug.assert(scope == 7);
            self.scope_ends += 1;
        }

        fn noteWindowsFastAffinityImport(self: *@This(), return_rip: u64) void {
            self.fast_imports += 1;
            self.return_field = return_rip;
        }

        fn clearWindowsFastTimeImportReturn(self: *@This()) void {
            self.return_field = 0;
        }
    };
    const FakeHost = struct {
        fn begin(state: *FakeState) u32 {
            return state.beginWindowsFastImportStoreScope();
        }

        fn end(state: *FakeState, scope: u32) void {
            state.endWindowsFastImportStoreScope(scope);
        }

        fn completeCall(state: *FakeState, return_rip: ?u64) void {
            state.context.regs.rip = return_rip.?;
        }
    };

    var state: FakeState = .{};
    try std.testing.expect(tryProcessAffinityMask(FakeHost, &state, "kernel32.dll", "GetProcessAffinityMask", 0x1400_2345));
    try std.testing.expectEqual(@as(u64, 0x55), std.mem.readInt(u64, state.memory[0..8], .little));
    try std.testing.expectEqual(@as(u64, 0xAA), std.mem.readInt(u64, state.memory[16..24], .little));
    try std.testing.expectEqual(@as(u64, 1), state.context.regs.rax);
    try std.testing.expectEqual(@as(u64, 0x1400_2345), state.context.regs.rip);
    try std.testing.expectEqual(@as(u32, 0), state.context.windows_last_error);
    try std.testing.expectEqual(@as(u32, 1), state.fast_imports);
    try std.testing.expectEqual(@as(u64, 0), state.return_field);
    try std.testing.expectEqual(@as(u32, 1), state.scope_begins);
    try std.testing.expectEqual(@as(u32, 1), state.scope_ends);

    state = .{};
    state.allow_system_output = false;
    try std.testing.expect(!tryProcessAffinityMask(FakeHost, &state, "kernel32.dll", "GetProcessAffinityMask", 0x1400_2345));
    try std.testing.expectEqual([_]u8{0xA5} ** 24, state.memory);
    try std.testing.expectEqual(@as(u32, 1), state.scope_begins);
    try std.testing.expectEqual(@as(u32, 1), state.scope_ends);
}

test "Sleep zero fast lane yields only for an eligible parallel worker" {
    const Registers = struct {
        rax: u64 = 0xAAAA,
        rcx: u64 = 0,
        rip: u64 = 0x1400_1000,
    };
    const Context = struct { regs: Registers = .{} };
    const FakeState = struct {
        parallel_guest_execution: bool = true,
        windows_runtime_enabled: bool = true,
        diagnose_abi: bool = false,
        context: Context = .{},
        allowed: bool = true,
        yields: u32 = 0,
        fast_imports: u32 = 0,
        scope_begins: u32 = 0,
        scope_ends: u32 = 0,
        return_field: u64 = 0,

        fn windowsGuestContextField(self: *@This(), comptime field: []const u8) *@FieldType(Context, field) {
            return &@field(self.context, field);
        }

        fn windowsFastCrtImportMayBypassRuntimeLock(_: *@This()) bool {
            return true;
        }

        fn windowsFastSleepZeroImportAllowed(self: *@This()) bool {
            return self.allowed;
        }

        fn requestWindowsGuestSliceYield(self: *@This()) void {
            self.yields += 1;
        }

        fn beginWindowsFastImportStoreScope(self: *@This()) u32 {
            self.scope_begins += 1;
            return 9;
        }

        fn endWindowsFastImportStoreScope(self: *@This(), scope: u32) void {
            std.debug.assert(scope == 9);
            self.scope_ends += 1;
        }

        fn noteWindowsFastSleepZeroImport(self: *@This(), return_rip: u64) void {
            self.fast_imports += 1;
            self.return_field = return_rip;
        }

        fn clearWindowsFastTimeImportReturn(self: *@This()) void {
            self.return_field = 0;
        }
    };
    const FakeHost = struct {
        fn begin(state: *FakeState) u32 {
            return state.beginWindowsFastImportStoreScope();
        }

        fn end(state: *FakeState, scope: u32) void {
            state.endWindowsFastImportStoreScope(scope);
        }

        fn completeCall(state: *FakeState, return_rip: ?u64) void {
            state.context.regs.rip = return_rip.?;
        }
    };

    var state: FakeState = .{};
    try std.testing.expect(trySleepZero(FakeHost, &state, "kernel32.dll", "Sleep", 0x1400_2345));
    try std.testing.expectEqual(@as(u64, 0), state.context.regs.rax);
    try std.testing.expectEqual(@as(u64, 0x1400_2345), state.context.regs.rip);
    try std.testing.expectEqual(@as(u32, 1), state.yields);
    try std.testing.expectEqual(@as(u32, 1), state.fast_imports);
    try std.testing.expectEqual(@as(u64, 0), state.return_field);
    try std.testing.expectEqual(@as(u32, 1), state.scope_begins);
    try std.testing.expectEqual(@as(u32, 1), state.scope_ends);

    state = .{};
    state.context.regs.rcx = 1;
    try std.testing.expect(!trySleepZero(FakeHost, &state, "kernel32.dll", "Sleep", 0x1400_2345));
    try std.testing.expectEqual(@as(u32, 0), state.scope_begins);

    state = .{};
    state.allowed = false;
    try std.testing.expect(!trySleepZero(FakeHost, &state, "kernel32.dll", "Sleep", 0x1400_2345));
    try std.testing.expectEqual(@as(u32, 0), state.yields);
    try std.testing.expectEqual(@as(u32, 1), state.scope_ends);
}

test "no fast import lane admits a vulkan-1.dll name, so Vulkan stubs may skip them" {
    // `register_import.tryStub` returns early for dynamic vulkan-1.dll stubs
    // (Xenia's ~17,000 Vulkan calls per heavy frame). That is exact only
    // while every lane gates on its own modules: the pure predicates are
    // checked here; the Sleep, affinity, NT-yield and SRW lanes compare
    // against literal kernel32/kernelbase/ntdll/api-ms-win-core names.
    const fast_math = @import("fast_math.zig");
    const names = [_][]const u8{
        "memcpy",                         "memmove",                 "memset",                    "memcmp",           "strlen",           "strcmp",
        "strxfrm",                        "malloc",                  "_malloc_base",              "calloc",           "_aligned_malloc",  "free",
        "_free_base",                     "_aligned_free",           "exp2",                      "exp2f",            "log10",            "GetCurrentThreadId",
        "GetCurrentThread",               "GetCurrentProcess",       "GetCurrentProcessId",       "Sleep",            "NtDelayExecution", "GetProcessAffinityMask",
        "GetSystemTimePreciseAsFileTime", "QueryPerformanceCounter", "QueryPerformanceFrequency", "vkCmdDrawIndexed", "vkQueueSubmit",    "vkUpdateDescriptorSets",
    };
    for ([_][]const u8{ "vulkan-1.dll", "VULKAN-1.DLL", "Vulkan-1.dll" }) |dll| for (names) |name| {
        try std.testing.expect(crtStringOp(dll, name) == null);
        try std.testing.expect(crtMemoryOp(dll, name) == null);
        try std.testing.expect(crtHeapOp(dll, name) == null);
        try std.testing.expect(identityQuery(dll, name) == null);
        try std.testing.expect(fast_math.candidate(dll, name) == null);
        try std.testing.expect(!isPreciseTimeQuery(dll, name, 0x1400_2345, true, true, false, false, false));
    };
    // Positive controls: the same predicates admit their own modules.
    try std.testing.expect(crtStringOp("ucrtbase.dll", "strlen") != null);
    try std.testing.expect(crtMemoryOp("ucrtbase.dll", "memcpy") != null);
    try std.testing.expect(crtHeapOp("ucrtbase.dll", "malloc") != null);
    try std.testing.expect(identityQuery("KERNEL32.dll", "GetCurrentThreadId") != null);
    try std.testing.expect(fast_math.candidate("ucrtbase.dll", "exp2") != null);
    try std.testing.expect(isPreciseTimeQuery("kernel32.dll", "QueryPerformanceCounter", 0x1400_2345, true, true, false, false, false));
}
