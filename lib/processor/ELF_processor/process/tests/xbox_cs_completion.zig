//! Xbox critical-section calls completed inside translated code
//! (`impl/xbox_critical_section_transfer.zig`), through the production
//! translator, hook tables and glue: Xenia's GuestToHostThunk shape, `mov
//! rcx, <PPCContext> ; mov rax, <trampoline> ; call rax`, on a section in
//! guest memory. An uncontended Enter or Leave runs in place and the call
//! goes on at its return; anything that could wait or wake declines without
//! touching the section, and the per-step hook runs it as before.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const ElfState = P.ElfState;
const MEM_BASE = I._MEM_BASE;
const protocol = I._xbox_critical_section;
const transfer = @import("../impl/xbox_critical_section_transfer.zig");
const jit_glue = @import("../impl/block_jit.zig");

const code: usize = 0x100000;
const enter_rip = MEM_BASE + code + 0x400;
const leave_rip = MEM_BASE + code + 0x480;
const context = MEM_BASE + 0x20000;
const membase = MEM_BASE + 0x40000;
const guest_section: u32 = 0x2400;
const section = membase + guest_section;
const pcr: u32 = 0x3000;
const me: u32 = 0x7000_0100;
const other: u32 = 0x7000_0200;

fn movImm64(mem: []u8, at: *usize, rex_reg: [2]u8, value: u64) void {
    mem[at.*..][0..2].* = rex_reg;
    mem[at.* + 2 ..][0..8].* = @bitCast(value);
    at.* += 10;
}

fn callThrough(mem: []u8, at: *usize, trampoline: u64) void {
    movImm64(mem, at, .{ 0x48, 0xB9 }, context); // mov rcx, context
    movImm64(mem, at, .{ 0x48, 0xB8 }, trampoline); // mov rax, trampoline
    mem[at.*..][0..2].* = .{ 0xFF, 0xD0 }; // call rax
    at.* += 2;
}

/// Enter `depth` times, inc r9, leave `depth` times; dec r8 ; jnz ; exit.
fn install(state: *ElfState, depth: usize) u64 {
    const mem = state.mem;
    var at = code;
    for (0..depth) |_| callThrough(mem, &at, enter_rip);
    mem[at..][0..3].* = .{ 0x49, 0xFF, 0xC1 }; // inc r9
    at += 3;
    for (0..depth) |_| callThrough(mem, &at, leave_rip);
    mem[at..][0..3].* = .{ 0x49, 0xFF, 0xC8 }; // dec r8
    mem[at + 3 ..][0..2].* = .{ 0x0F, 0x85 }; // jnz start
    mem[at + 5 ..][0..4].* = @bitCast(@as(i32, @intCast(@as(i64, @intCast(code)) - @as(i64, @intCast(at + 9)))));
    mem[at + 9 ..][0..3].* = .{ 0x48, 0x39, 0xE4 }; // cmp rsp, rsp
    mem[at + 12 ..][0..2].* = .{ 0xEB, 0xFE }; // jmp $
    // The trampolines are hooked; were one ever run, `ret` alone would
    // leave the section untouched and fail the checks.
    mem[enter_rip - MEM_BASE] = 0xC3;
    mem[leave_rip - MEM_BASE] = 0xC3;
    return MEM_BASE + at + 12;
}

fn writeSection(state: *ElfState, owner: u32, recursion: i32, lock: i32) void {
    const at = section - MEM_BASE;
    @memset(state.mem[at..][0..protocol.Offset.size], 0);
    state.mem[at + protocol.Offset.header_type] = protocol.event_synchronization_object;
    std.mem.writeInt(i32, state.mem[at + protocol.Offset.lock_count ..][0..4], lock, .little);
    std.mem.writeInt(i32, state.mem[at + protocol.Offset.recursion ..][0..4], recursion, .big);
    std.mem.writeInt(u32, state.mem[at + protocol.Offset.owner ..][0..4], owner, .big);
}

fn sectionBytes(state: *const ElfState) [protocol.Offset.size]u8 {
    return state.mem[section - MEM_BASE ..][0..protocol.Offset.size].*;
}

fn setup(state: *ElfState, depth: usize) u64 {
    state.setParallelGuestExecution(true);
    state.windows_runtime_enabled = true;
    state.image_low = MEM_BASE + code;
    state.image_high = MEM_BASE + code + 0x800;
    state.configureWindowsExecutableRanges(&[_]I._WindowsExecutableRange{.{ .guest_base = MEM_BASE + code, .length = 0x800 }});
    const exit = install(state, depth);
    std.debug.assert(state.xbox_critical_section_hooks.arm("RtlEnterCriticalSection", enter_rip));
    std.debug.assert(state.xbox_critical_section_hooks.arm("RtlLeaveCriticalSection", leave_rip));
    jit_glue.publishBlockJitHookFilter(state);
    state.write64(context + I._PPC_CONTEXT_VIRTUAL_MEMBASE, membase);
    state.write64(context + I._ppcContextGpr(3), guest_section);
    state.write64(context + I._ppcContextGpr(13), pcr);
    state.write32(membase + pcr + protocol.pcr_current_thread, @byteSwap(me));
    writeSection(state, 0, 0, protocol.free_lock_count);
    state.block_jit_enabled = true;
    state.block_jit_hot_threshold = 1;
    state.regs.rsp = MEM_BASE + 0x7f000;
    state.regs.rflags = 0x2;
    return exit;
}

fn runLoop(state: *ElfState, exit: u64, passes: u64) !void {
    state.regs.rip = MEM_BASE + code;
    state.regs.r8 = passes;
    var steps: usize = 0;
    while (state.regs.rip != exit and !state.terminated) : (steps += 1) {
        _ = state.step();
        try t.expect(steps < 10_000_000);
    }
    try t.expectEqual(exit, state.regs.rip);
    try t.expectEqual(@as(u64, MEM_BASE + 0x7f000), state.regs.rsp);
}

const Outcome = struct { r9: u64, bytes: [protocol.Offset.size]u8, enters: u64, leaves: u64, completed: u64, acquired: u64, recursed: u64, entries: u64 };

fn runProgram(depth: usize, passes: u64, completion: bool) !Outcome {
    transfer.completion_enabled = completion;
    defer transfer.completion_enabled = true;
    var state = ElfState.init(t.allocator);
    defer state.deinit();
    defer state.setParallelGuestExecution(false);
    const exit = setup(&state, depth);
    try runLoop(&state, exit, passes);
    const hooks = &state.xbox_critical_section_hooks;
    const enter = @intFromEnum(protocol.Export.enter);
    const leave = @intFromEnum(protocol.Export.leave);
    return .{
        .r9 = state.regs.r9,
        .bytes = sectionBytes(&state),
        .enters = hooks.calls[enter],
        .leaves = hooks.calls[leave],
        .completed = hooks.jit_completed_calls[enter] + hooks.jit_completed_calls[leave],
        .acquired = state.xbox_critical_section_stats.acquired,
        .recursed = state.xbox_critical_section_stats.recursed,
        .entries = state.block_jit.?.dispatch_entries,
    };
}

test "Xbox critical-section completion: translated enter and leave run in place with the hook's results" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const passes: u64 = 2000;
    for ([_]usize{ 1, 2 }) |depth| {
        const native = try runProgram(depth, passes, true);
        const hooked = try runProgram(depth, passes, false);
        // The same guest results and protocol counts either way: every
        // section byte, every enter and leave, every acquisition.
        try t.expectEqual(passes, native.r9);
        try t.expectEqual(hooked.r9, native.r9);
        try t.expectEqualSlices(u8, &hooked.bytes, &native.bytes);
        try t.expectEqual(passes * depth, native.enters);
        try t.expectEqual(passes * depth, native.leaves);
        try t.expectEqual(hooked.enters, native.enters);
        try t.expectEqual(hooked.leaves, native.leaves);
        try t.expectEqual(passes, native.acquired);
        try t.expectEqual(passes * (depth - 1), native.recursed);
        try t.expectEqual(hooked.acquired, native.acquired);
        try t.expectEqual(hooked.recursed, native.recursed);
        // Free at the end: lock_count -1, no owner.
        try t.expectEqual(protocol.free_lock_count, std.mem.readInt(i32, native.bytes[protocol.Offset.lock_count..][0..4], .little));
        try t.expectEqual(@as(u32, 0), std.mem.readInt(u32, native.bytes[protocol.Offset.owner..][0..4], .big));
        // Only the first, interpreted pass took the hook; the loop no longer
        // leaves translated code for its calls.
        try t.expect(native.completed >= 2 * depth * (passes - 2));
        try t.expectEqual(@as(u64, 0), hooked.completed);
        try t.expect(native.entries * 20 < hooked.entries);
    }
}

test "Xbox critical-section completion: anything that could wait or wake declines before touching the section" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.init(t.allocator);
    defer state.deinit();
    defer state.setParallelGuestExecution(false);
    _ = setup(&state, 1);
    state.regs.rcx = context;
    const observed: u32 = @intFromEnum(transfer.Outcome.observed);
    const completed: u32 = @intFromEnum(transfer.Outcome.completed);
    const ret: u64 = MEM_BASE + code;
    const cases = [_]struct { owner: u32, recursion: i32, lock: i32, api: u64, expect: u32 }{
        // Another thread holds it: Enter would spin and count.
        .{ .owner = other, .recursion = 1, .lock = 0, .api = enter_rip, .expect = observed },
        // A waiter counted itself: the last Leave must wake it.
        .{ .owner = me, .recursion = 1, .lock = 1, .api = leave_rip, .expect = observed },
        // A Leave by a thread that does not own a recursion.
        .{ .owner = other, .recursion = 2, .lock = 1, .api = leave_rip, .expect = observed },
        // Free, then ours to recurse and release: in place.
        .{ .owner = 0, .recursion = 0, .lock = -1, .api = enter_rip, .expect = completed },
        .{ .owner = me, .recursion = 1, .lock = 0, .api = enter_rip, .expect = completed },
        .{ .owner = me, .recursion = 2, .lock = 1, .api = leave_rip, .expect = completed },
        .{ .owner = me, .recursion = 1, .lock = 0, .api = leave_rip, .expect = completed },
    };
    for (cases) |case| {
        writeSection(&state, case.owner, case.recursion, case.lock);
        const before = sectionBytes(&state);
        try t.expectEqual(case.expect, transfer.observe(&state, case.api, ret));
        const after = sectionBytes(&state);
        if (case.expect == observed) try t.expectEqualSlices(u8, &before, &after);
        if (case.expect == completed) try t.expect(!std.mem.eql(u8, &before, &after));
    }
    // A grant pending for this section: the hook collects it.
    writeSection(&state, 0, 0, protocol.free_lock_count);
    state.owner_xbox_cs_wait = section;
    try t.expectEqual(observed, transfer.observe(&state, enter_rip, ret));
    try t.expectEqual(protocol.free_lock_count, std.mem.readInt(i32, sectionBytes(&state)[protocol.Offset.lock_count..][0..4], .little));
    state.owner_xbox_cs_wait = 0;
    // The other exports keep their own routes.
    try t.expectEqual(@as(u32, 0), transfer.observe(&state, MEM_BASE + code + 0x500, ret));
}

fn threadCpu() u64 {
    var stamp: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &stamp) == 0);
    return @as(u64, @intCast(stamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(stamp.nsec));
}

test "Xbox critical-section completion: CPU per enter/leave pair, in place and through the hook (ROSETTE_CALL_RETURN_BENCH=1)" {
    if (std.c.getenv("ROSETTE_CALL_RETURN_BENCH") == null) return error.SkipZigTest;
    const label: []const u8 = if (std.c.getenv("ROSETTE_CALL_RETURN_BINARY")) |raw| std.mem.sliceTo(raw, 0) else "current";
    const pair: []const u8 = if (std.c.getenv("ROSETTE_CALL_RETURN_PAIR")) |raw| std.mem.sliceTo(raw, 0) else "0";
    defer transfer.completion_enabled = true;
    const passes: u64 = 200_000;
    for ([_]bool{ false, true, false, true }) |completion| {
        transfer.completion_enabled = completion;
        var state = ElfState.init(t.allocator);
        defer state.deinit();
        defer state.setParallelGuestExecution(false);
        const exit = setup(&state, 1);
        try runLoop(&state, exit, 64);
        const entries = state.block_jit.?.dispatch_entries;
        const started = threadCpu();
        try runLoop(&state, exit, passes);
        const elapsed = threadCpu() - started;
        try t.expectEqual(passes + 64, state.regs.r9);
        std.debug.print("xbox_cs series_pair={s} binary={s} completion={} passes={d} cpu_ns={d} dispatch_entries={d} ns_per_pair={d:.2}\n", .{
            pair,                                                               label, completion, passes, elapsed, state.block_jit.?.dispatch_entries - entries,
            @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(passes)),
        });
    }
}
