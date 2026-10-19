//! Translated-code working set: the cost of a block as the number of distinct
//! hot blocks grows. MAIN_THREAD in run 20261019T000531Z-75c25f53a39c executes
//! about 2.8 million blocks a frame while the title-screen camera moves, out of
//! 72,309 live blocks in 555 MiB of ARM64 code. A block that is cheap while a
//! handful of blocks are hot can be several times dearer when its code is
//! fetched from far away; this measures that curve through the production
//! translator, with blocks shaped like Xenia's x64 output (context loads and
//! stores through rsi, byte-swapped guest memory through rdi).
//!
//! `ROSETTE_CODE_WORKING_SET_BENCH=1 zig build code-working-set-check
//! -Doptimize=ReleaseFast` prints one `code_working_set` line per block count
//! and layout; without the variable only the correctness test runs.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const ElfState = P.ElfState;
const MEM_BASE = I._MEM_BASE;

/// The same file runs in a frozen pre-change tree for the before series,
/// where neither the layout control nor `cold_code` exists.
const has_layout = @hasDecl(I._block_jit, "code_layout");
const has_cold = @hasField(I._block_jit.Block, "cold_code");

const code: usize = 0x100000;
const stride: usize = 128;
const context: usize = 0x20000;
const guest: usize = 0x30000;
const stack_top: usize = 0x7f000;

fn threadCpu() u64 {
    var stamp: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &stamp) == 0);
    return @as(u64, @intCast(stamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(stamp.nsec));
}

fn rel32(from: usize, to: usize) [4]u8 {
    return @bitCast(@as(i32, @intCast(@as(i64, @intCast(to)) - @as(i64, @intCast(from)))));
}

/// One Xenia-shaped body: 8 instructions, 27 bytes.
const body = [_]u8{
    0x8B, 0x46, 0x40, // mov eax, [rsi+0x40]
    0x03, 0x46, 0x44, // add eax, [rsi+0x44]
    0x89, 0x46, 0x48, // mov [rsi+0x48], eax
    0x8B, 0x4E, 0x4C, // mov ecx, [rsi+0x4c]
    0x0F, 0x38, 0xF0, 0x14, 0x0F, // movbe edx, [rdi+rcx]
    0x01, 0xC2, // add edx, eax
    0x0F, 0x38, 0xF1, 0x14, 0x0F, // movbe [rdi+rcx], edx
    0x89, 0x56, 0x50, // mov [rsi+0x50], edx
};
pub const body_instructions = 8;

/// The same count of instructions on registers only: no memory access, so
/// almost no out-of-line code, while every hop still proves its successor.
const register_body = [_]u8{
    0x01, 0xC8, // add eax, ecx
    0x31, 0xC2, // xor edx, eax
    0x01, 0xD1, // add ecx, edx
    0x31, 0xC8, // xor eax, ecx
    0x01, 0xC2, // add edx, eax
    0x31, 0xD1, // xor ecx, edx
    0x01, 0xC8, // add eax, ecx
    0x31, 0xC2, // xor edx, eax
};

/// Writes `count` blocks of `repeat` bodies each, block i jumping to block
/// i+1 and the last one counting r8 down to block 0. Returns the exit rip, a
/// `jmp $` after the loop.
fn emit(mem: []u8, count: usize, repeat: usize, registers_only: bool) usize {
    const shape: []const u8 = if (registers_only) &register_body else &body;
    std.debug.assert(repeat * shape.len + 16 <= stride);
    for (0..count) |index| {
        var at = code + index * stride;
        for (0..repeat) |_| {
            @memcpy(mem[at..][0..shape.len], shape);
            at += shape.len;
        }
        if (index + 1 < count) {
            mem[at] = 0xE9; // jmp next
            mem[at + 1 ..][0..4].* = rel32(at + 5, code + (index + 1) * stride);
        } else {
            mem[at..][0..3].* = .{ 0x49, 0xFF, 0xC8 }; // dec r8
            mem[at + 3 ..][0..2].* = .{ 0x0F, 0x85 }; // jnz block 0
            mem[at + 5 ..][0..4].* = rel32(at + 9, code);
            mem[at + 9 ..][0..3].* = .{ 0x48, 0x39, 0xE4 }; // cmp rsp, rsp
            mem[at + 12 ..][0..2].* = .{ 0xEB, 0xFE }; // jmp $
            return at + 12;
        }
    }
    unreachable;
}

pub const Result = struct {
    cpu_ns: u64,
    block_executions: u64,
    retired: u64,
    compiled: u64,
    code_bytes: u64,
    hot_bytes: u64,
    cold_bytes: u64,
    context_value: u32,
    guest_value: u32,
};

/// Runs `passes` passes over `count` blocks after one warm-up pass that
/// compiles them all; only the timed passes are measured.
pub fn run(count: usize, repeat: usize, passes: u64, parallel: bool, registers_only: bool, split: bool) !Result {
    const saved = if (has_layout) I._block_jit.code_layout.split_all else false;
    defer if (has_layout) {
        I._block_jit.code_layout.split_all = saved;
    };
    if (has_layout) I._block_jit.code_layout.split_all = split;
    var state = ElfState.init(t.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    // Guest workers run in parallel mode: direct TLB fills and the parallel
    // chain budget, as MAIN_THREAD does.
    if (parallel) state.setParallelGuestExecution(true);
    defer if (parallel) state.setParallelGuestExecution(false);
    state.image_low = MEM_BASE + code;
    state.image_high = MEM_BASE + code + count * stride;
    state.configureWindowsExecutableRanges(&[_]I._WindowsExecutableRange{.{ .guest_base = MEM_BASE + code, .length = count * stride }});
    const exit = emit(state.mem, count, repeat, registers_only);
    @memset(state.mem[context..][0..0x100], 0);
    std.mem.writeInt(u32, state.mem[context + 0x40 ..][0..4], 3, .little);
    std.mem.writeInt(u32, state.mem[context + 0x44 ..][0..4], 4, .little);
    std.mem.writeInt(u32, state.mem[context + 0x4c ..][0..4], 0x10, .little);
    @memset(state.mem[guest..][0..0x100], 0);
    state.block_jit_enabled = true;
    state.block_jit_hot_threshold = 1;
    if (std.c.getenv("ROSETTE_CODE_WORKING_SET_WINDOW")) |raw| {
        const jit = state.blockJitActive() orelse return error.NoJit;
        if (@hasField(@TypeOf(jit.memory), "window_bytes")) jit.memory.window_bytes = std.fmt.parseInt(usize, std.mem.sliceTo(raw, 0), 0) catch jit.memory.window_bytes;
    }
    state.regs.rsi = MEM_BASE + context;
    state.regs.rdi = MEM_BASE + guest;
    state.regs.rsp = MEM_BASE + stack_top;
    state.regs.rflags = 0x2;
    var cpu_ns: u64 = 0;
    var executions: u64 = 0;
    var retired: u64 = 0;
    // Pass 0 interprets and compiles; pass 1 warms the chains; then timing.
    for ([_]u64{ 2, 1, passes }, 0..) |rounds, phase| {
        state.regs.rip = MEM_BASE + code;
        state.regs.r8 = rounds;
        const jit = state.block_jit orelse null;
        const executions_before = if (jit) |j| j.executions else 0;
        const retired_before = if (jit) |j| j.instructions_retired else 0;
        const started = threadCpu();
        while (state.regs.rip != MEM_BASE + exit and !state.terminated) _ = state.step();
        const elapsed = threadCpu() - started;
        try t.expectEqual(@as(u64, MEM_BASE + exit), state.regs.rip);
        if (phase == 2) {
            cpu_ns = elapsed;
            executions = state.block_jit.?.executions - executions_before;
            retired = state.block_jit.?.instructions_retired - retired_before;
        }
    }
    const jit = state.block_jit.?;
    if (std.c.getenv("ROSETTE_CODE_WORKING_SET_DUMP") != null) {
        if (state.blockJitFindValidSlot(jit, MEM_BASE + code + stride)) |found| {
            std.debug.print("code_working_set_dump hot=", .{});
            for (found.block.code) |word| std.debug.print("{x:0>8} ", .{word});
            if (has_cold) {
                std.debug.print("\ncode_working_set_dump cold=", .{});
                for (found.block.cold_code) |word| std.debug.print("{x:0>8} ", .{word});
            }
            std.debug.print("\n", .{});
        }
    }
    var hot_bytes: u64 = 0;
    var cold_bytes: u64 = 0;
    for (jit.blocks) |maybe| {
        const block = maybe orelse continue;
        hot_bytes += block.code.len * @sizeOf(u32);
        if (has_cold) cold_bytes += block.cold_code.len * @sizeOf(u32);
    }
    return .{
        .cpu_ns = cpu_ns,
        .block_executions = executions,
        .retired = retired,
        .compiled = jit.compiled,
        .code_bytes = if (@hasDecl(@TypeOf(jit.memory), "bytesInUse")) jit.memory.bytesInUse() else jit.memory.used,
        .hot_bytes = hot_bytes,
        .cold_bytes = cold_bytes,
        .context_value = std.mem.readInt(u32, state.mem[context + 0x50 ..][0..4], .little),
        .guest_value = std.mem.readInt(u32, state.mem[guest + 0x10 ..][0..4], .big),
    };
}

test "code working set: distinct blocks compile once and keep exact guest results in both layouts" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Each body adds [0x40]+[0x44]=7 to the big-endian guest word, then
    // stores it to [0x50]: after b bodies in total the word reads 7*b.
    for ([_]usize{ 1, 3 }) |repeat| {
        for ([_]bool{ false, true }) |split| {
            const count: usize = 64;
            const passes: u64 = 5;
            const result = try run(count, repeat, passes, true, false, split);
            const bodies = (2 + 1 + passes) * count * repeat;
            try t.expectEqual(@as(u32, @intCast(7 * bodies)), result.guest_value);
            try t.expectEqual(result.guest_value, result.context_value);
            try t.expect(result.compiled >= count);
            try t.expectEqual(passes * count, result.block_executions);
            // Split: the hot part is a fraction of the block; contiguous:
            // nothing is placed apart.
            if (split and has_layout) try t.expect(result.cold_bytes > 2 * result.hot_bytes) else try t.expectEqual(@as(u64, 0), result.cold_bytes);
        }
    }
}

test "code working set: per-block CPU as the number of hot blocks grows (ROSETTE_CODE_WORKING_SET_BENCH=1)" {
    if (std.c.getenv("ROSETTE_CODE_WORKING_SET_BENCH") == null) return error.SkipZigTest;
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const total: u64 = 4_000_000;
    const pairs: usize = if (std.c.getenv("ROSETTE_CODE_WORKING_SET_PAIRS")) |raw| std.fmt.parseInt(usize, std.mem.sliceTo(raw, 0), 10) catch 1 else 1;
    for ([_]struct { repeat: usize, registers_only: bool }{ .{ .repeat = 1, .registers_only = false }, .{ .repeat = 3, .registers_only = false }, .{ .repeat = 1, .registers_only = true } }) |shape| {
        const repeat = shape.repeat;
        // `ROSETTE_CODE_WORKING_SET_ONLY=<repeat>:<registers_only 0/1>:<blocks>` runs one point.
        const only = std.c.getenv("ROSETTE_CODE_WORKING_SET_ONLY");
        for ([_]usize{ 16, 256, 512, 1024, 2048, 4096, 8192, 32768 }) |count| {
            if (only == null and (count == 512 or count == 1024 or count == 4096) and std.c.getenv("ROSETTE_CODE_WORKING_SET_DENSE") == null) continue;
            if (only) |raw| {
                var buffer: [64]u8 = undefined;
                const want = std.fmt.bufPrint(&buffer, "{d}:{d}:{d}", .{ repeat, @intFromBool(shape.registers_only), count }) catch continue;
                if (!std.mem.eql(u8, std.mem.sliceTo(raw, 0), want)) continue;
            }
            const passes = @max(total / count, 4);
            for (0..pairs) |pair| for ([_]bool{ false, true }) |split| {
                // The frozen tree has one layout; its split rows would repeat it.
                if (split and !has_layout) continue;
                const result = try run(count, repeat, passes, true, shape.registers_only, split);
                std.debug.print("code_working_set tree={s} registers_only={} repeat={d} blocks={d} pair={d} split={} passes={d} cpu_ns={d} block_executions={d} retired={d} ns_per_block={d}.{d:0>2} code_bytes_per_block={d} hot_bytes_per_block={d} cold_bytes_per_block={d}\n", .{
                    if (has_layout) "current" else "before",
                    shape.registers_only,
                    repeat,
                    count,
                    pair,
                    split,
                    passes,
                    result.cpu_ns,
                    result.block_executions,
                    result.retired,
                    result.cpu_ns / result.block_executions,
                    result.cpu_ns * 100 / result.block_executions % 100,
                    result.code_bytes / @max(result.compiled, 1),
                    result.hot_bytes / @max(result.compiled, 1),
                    result.cold_bytes / @max(result.compiled, 1),
                });
            };
        }
    }
}
