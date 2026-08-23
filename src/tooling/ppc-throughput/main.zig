//! Measure PowerPC interpreter and recompiler throughput.
//!
//! The audit that motivated the direct PowerPC path projected instruction rates
//! for three implementations and measured none of them. This measures two of
//! the three on the machine it is run on, over a workload shaped like the code
//! that dominates a guest's hot path: an integer loop with loads and stores.
//!
//! It is deliberately not a test. A throughput assertion fails when the machine
//! is busy, which trains people to ignore it; a number printed on demand does
//! not. Run it, read the numbers, and put them in the document with the date
//! and the machine.

const std = @import("std");
const ppc = @import("ppc_runtime");

/// The measured workload: a counted loop that touches memory every iteration.
///
/// The shape matters more than the exact instructions. A loop of pure register
/// arithmetic overstates a recompiler (no memory, no bounds checks); a loop of
/// pure loads understates it (the memory system dominates). This is roughly the
/// mix a guest's inner loops actually have.
const workload = [_]u32{
    0x38600000, // li    r3, 0            ; sum
    0x38800000, // li    r4, 0            ; index
    0x3CA00000, // lis   r5, 0            ; data base
    0x60A50400, // ori   r5, r5, 0x400
    // loop:
    0x7CC52A14, // add   r6, r5, r5       ; some arithmetic
    0x80E50000, // lwz   r7, 0(r5)
    0x7C673A14, // add   r3, r7, r7
    0x54E7103A, // rlwinm r7, r7, 2, 0, 29
    0x90E50000, // stw   r7, 0(r5)
    0x38840001, // addi  r4, r4, 1
    0x7C043800, // cmpw  cr0, r4, r7
    0x4082FFE4, // bne   loop
    0x44000002, // sc
};

/// The address of the loop body, which is what goes hot.
const loop_start: u32 = 16;
/// Guest instructions the compiler claims from the body. The closing `bne` is
/// control flow and ends the block, so it is measured on neither side.
const compiled_body: u32 = 7;
const memory_size: usize = 8192;

fn setup(state: *ppc.State, buffer: []u8) void {
    @memset(buffer, 0);
    for (workload, 0..) |word, i| {
        std.mem.writeInt(u32, buffer[i * 4 ..][0..4], word, .big);
    }
    state.* = .{};
    state.pc = 0;
}

fn runInterpreted(iterations: u64, buffer: []u8) !struct { retired: u64, nanos: u64 } {
    var state: ppc.State = .{};
    setup(&state, buffer);
    var ctx = ppc.Context.init(&state, ppc.Memory.fromSlice(buffer, 0));

    const started = nowNanos();
    var executed: u64 = 0;
    while (executed < iterations) : (executed += 1) {
        state.pc = loop_start;
        // The same instruction count the compiled block covers, so the two
        // measurements are over identical work. The loop's closing branch is
        // outside the compiled subset and is excluded from both.
        var steps: u32 = 0;
        while (steps < compiled_body) : (steps += 1) {
            _ = ppc.step(&ctx) catch break;
        }
    }
    const nanos = nowNanos() - started;
    return .{ .retired = state.instructions_retired, .nanos = nanos };
}

fn runCompiled(
    allocator: std.mem.Allocator,
    iterations: u64,
    buffer: []u8,
) !?struct { retired: u64, nanos: u64, blocks: u64 } {
    if (!ppc.jit.Jit.available()) return null;

    var state: ppc.State = .{};
    setup(&state, buffer);
    const memory = ppc.Memory.fromSlice(buffer, 0);

    var jit = try ppc.jit.Jit.init(allocator, 4 * 1024 * 1024);
    defer jit.deinit();

    const block = (try jit.compileAt(memory, loop_start)) orelse return null;

    const started = nowNanos();
    var executed: u64 = 0;
    while (executed < iterations) : (executed += 1) {
        state.pc = loop_start;
        _ = jit.run(block, &state, memory);
    }
    const nanos = nowNanos() - started;
    return .{
        .retired = state.instructions_retired,
        .nanos = nanos,
        .blocks = block.instruction_count,
    };
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const buffer = try allocator.alloc(u8, memory_size);
    defer allocator.free(buffer);

    const iterations: u64 = 2_000_000;

    // A tiny writer over std.debug's stderr: this tool prints a handful of
    // lines and has no reason to carry a buffered-writer setup for them.
    const w = &Report{};

    try w.print("PowerPC throughput, {d} iterations of a {d}-instruction loop body\n", .{
        iterations, compiled_body,
    });
    try w.print("{s}\n", .{"-" ** 64});

    // Warm the caches so the first measurement is not paying for cold pages.
    _ = try runInterpreted(1000, buffer);

    const interpreted = try runInterpreted(iterations, buffer);
    const interpreted_rate = rate(interpreted.retired, interpreted.nanos);
    try w.print("interpreter   {d:>12} insns  {d:>8.1} ms  {d:>10.2} M insns/s\n", .{
        interpreted.retired,
        @as(f64, @floatFromInt(interpreted.nanos)) / 1_000_000.0,
        interpreted_rate,
    });

    if (try runCompiled(allocator, iterations, buffer)) |compiled| {
        const compiled_rate = rate(compiled.retired, compiled.nanos);
        try w.print("recompiler    {d:>12} insns  {d:>8.1} ms  {d:>10.2} M insns/s\n", .{
            compiled.retired,
            @as(f64, @floatFromInt(compiled.nanos)) / 1_000_000.0,
            compiled_rate,
        });
        try w.print("{s}\n", .{"-" ** 64});
        try w.print("speedup       {d:.2}x   (block covers {d} guest instructions)\n", .{
            compiled_rate / interpreted_rate,
            compiled.blocks,
        });
    } else {
        try w.print("recompiler    unavailable on this host\n", .{});
    }
    try w.flush();
}

extern "c" fn clock_gettime_nsec_np(clock_id: c_int) u64;

/// Monotonic nanoseconds. CLOCK_UPTIME_RAW (8) does not count time the machine
/// spent asleep, which is the clock a throughput measurement wants.
fn nowNanos() u64 {
    return clock_gettime_nsec_np(8);
}

/// Somewhere to print to that does not depend on which writer interface the
/// standard library currently exposes.
const Report = struct {
    pub fn print(_: *const Report, comptime fmt: []const u8, args: anytype) !void {
        std.debug.print(fmt, args);
    }
    pub fn flush(_: *const Report) !void {}
};

fn rate(instructions: u64, nanos: u64) f64 {
    if (nanos == 0) return 0;
    return @as(f64, @floatFromInt(instructions)) * 1000.0 /
        @as(f64, @floatFromInt(nanos));
}
