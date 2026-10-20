//! Calls and returns between translated blocks, through the production
//! translator. Halo 3's MAIN_THREAD runs Xenia's x64 output, which calls a
//! compiled guest function with `call rel32`, one not yet compiled when the
//! caller was through its indirection table (`mov ebx, addr ; mov eax,
//! [ebx] ; call rax`), and returns with `ret`. A `ret` and a `call rax`
//! leave a block for an address known only at run time; this measures what
//! such a transfer costs as the number of hot functions grows.
//!
//! The program: `functions` Xenia-shaped functions (`sub rsp`, bodies that
//! load and store the context through rsi and byte-swapped guest memory
//! through rdi, `add rsp`, `ret`) in `depth` levels. A function above the
//! last level calls one of `utilities` popular leaves, then one random
//! function of the next level; so a utility returns to many call sites and
//! a level function to a few. `indirect_percent` of the call sites go
//! through the table. Functions sit at shuffled addresses, and a driver
//! calls a random first-level function per iteration.
//!
//! `ROSETTE_CALL_RETURN_BENCH=1 zig build call-return-check
//! -Doptimize=ReleaseFast` prints one `call_return` line per shape; without
//! the variable only the correctness test runs.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const ElfState = P.ElfState;
const MEM_BASE = I._MEM_BASE;

/// The same file runs in a frozen pre-change tree for the before series.
const has_indirect = @hasDecl(I._block_jit, "indirect_links");

const code: usize = 0x100000;
const context: usize = 0x20000;
const guest: usize = 0x30000;
const order_area: usize = 0x40000;
const table: usize = 0x50000;
const stack_top: usize = 0x7f000;
const order_len: usize = 4096;
const max_functions: usize = 8192;

pub const Shape = struct {
    functions: usize,
    depth: usize,
    utilities: usize,
    repeat: usize,
    indirect_percent: u8,
};

/// Host instructions retired and cycles of the calling thread, from the
/// kernel's fixed counters (no privilege needed): the IPC of translated code.
extern "c" fn thread_selfcounts(kind: c_int, buffer: *[2]u64, bytes: usize) c_int;
fn hostCounts() [2]u64 {
    var counts: [2]u64 = .{ 0, 0 };
    if (thread_selfcounts(1, &counts, @sizeOf([2]u64)) != 0) return .{ 0, 0 };
    return counts;
}

fn threadCpu() u64 {
    var stamp: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &stamp) == 0);
    return @as(u64, @intCast(stamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(stamp.nsec));
}

fn rel32(from: usize, to: usize) [4]u8 {
    return @bitCast(@as(i32, @intCast(@as(i64, @intCast(to)) - @as(i64, @intCast(from)))));
}

/// One Xenia-shaped body (the working-set benchmark's): 8 instructions.
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

const Program = struct {
    start: usize,
    exit: usize,
    stride: usize,
    count: usize,
    /// Bodies each first-level entry of the driver's order runs, from the
    /// call graph itself: the exact count both executors must reach.
    order_bodies: [order_len]u32,
};

fn emitBody(mem: []u8, at: *usize, repeat: usize) void {
    for (0..repeat) |_| {
        @memcpy(mem[at.*..][0..body.len], &body);
        at.* += body.len;
    }
}

fn emitCall(mem: []u8, at: *usize, target: usize, target_index: usize, indirect: bool) void {
    if (indirect) {
        mem[at.*..][0..2].* = .{ 0x48, 0xBB }; // mov rbx, imm64
        mem[at.* + 2 ..][0..8].* = @bitCast(@as(u64, MEM_BASE + table + target_index * 8));
        mem[at.* + 10 ..][0..3].* = .{ 0x48, 0x8B, 0x03 }; // mov rax, [rbx]
        mem[at.* + 13 ..][0..2].* = .{ 0xFF, 0xD0 }; // call rax
        at.* += 15;
    } else {
        mem[at.*] = 0xE8; // call rel32
        mem[at.* + 1 ..][0..4].* = rel32(at.* + 5, target);
        at.* += 5;
    }
}

/// Lays the program out and returns where the driver starts and stops.
fn emitProgram(mem: []u8, shape: Shape) Program {
    const per_level = (shape.functions - shape.utilities) / shape.depth;
    const count = shape.utilities + per_level * shape.depth;
    std.debug.assert(count <= max_functions);
    // sub rsp + three bodies + two calls + add rsp + ret
    const needed = 4 + 3 * shape.repeat * body.len + 2 * 15 + 5;
    const stride = std.math.ceilPowerOfTwo(usize, needed) catch unreachable;
    const slot = t.allocator.alloc(usize, count) catch unreachable;
    defer t.allocator.free(slot);
    for (slot, 0..) |*s, i| s.* = i;
    var prng = std.Random.DefaultPrng.init(0xca11_0000 + count * 131 + shape.depth);
    const random = prng.random();
    random.shuffle(usize, slot);
    const Address = struct {
        slots: []const usize,
        stride: usize,
        fn of(self: @This(), index: usize) usize {
            return code + self.slots[index] * self.stride;
        }
    };
    const address: Address = .{ .slots = slot, .stride = stride };
    const bodies = t.allocator.alloc(u32, count) catch unreachable;
    defer t.allocator.free(bodies);
    const utility_of = t.allocator.alloc(usize, count) catch unreachable;
    defer t.allocator.free(utility_of);
    const child_of = t.allocator.alloc(?usize, count) catch unreachable;
    defer t.allocator.free(child_of);
    @memset(child_of, null);
    for (0..count) |index| {
        var at = address.of(index);
        // The indirection table holds every function's address.
        std.mem.writeInt(u64, mem[table + index * 8 ..][0..8], MEM_BASE + at, .little);
        mem[at..][0..4].* = .{ 0x48, 0x83, 0xEC, 0x28 }; // sub rsp, 0x28
        at += 4;
        emitBody(mem, &at, shape.repeat);
        const level: ?usize = if (index < shape.utilities) null else (index - shape.utilities) / per_level;
        if (level) |l| if (l + 1 < shape.depth) {
            const utility = random.uintLessThan(usize, shape.utilities);
            emitCall(mem, &at, address.of(utility), utility, random.uintLessThan(u8, 100) < shape.indirect_percent);
            emitBody(mem, &at, shape.repeat);
            const child = shape.utilities + (l + 1) * per_level + random.uintLessThan(usize, per_level);
            emitCall(mem, &at, address.of(child), child, random.uintLessThan(u8, 100) < shape.indirect_percent);
            emitBody(mem, &at, shape.repeat);
            utility_of[index] = utility;
            child_of[index] = child;
        };
        mem[at..][0..4].* = .{ 0x48, 0x83, 0xC4, 0x28 }; // add rsp, 0x28
        mem[at + 4] = 0xC3; // ret
    }
    // Utilities are leaves; then deepest first: a function's bodies are its
    // own three and its callees'.
    const own: u32 = @intCast(shape.repeat);
    for (bodies[0..shape.utilities]) |*b| b.* = own;
    var index = count;
    while (index > shape.utilities) {
        index -= 1;
        bodies[index] = if (child_of[index]) |child| 3 * own + bodies[utility_of[index]] + bodies[child] else own;
    }
    var program: Program = .{ .start = 0, .exit = 0, .stride = stride, .count = count, .order_bodies = undefined };
    // The driver calls first-level functions in a fixed random order.
    for (0..order_len) |i| {
        const first = shape.utilities + random.uintLessThan(usize, per_level);
        std.mem.writeInt(u64, mem[order_area + i * 8 ..][0..8], MEM_BASE + address.of(first), .little);
        program.order_bodies[i] = bodies[first];
    }
    const head = code + count * stride;
    var at = head;
    mem[at..][0..4].* = .{ 0x4B, 0x8B, 0x04, 0xD3 }; // mov rax, [r11 + r10*8]
    mem[at + 4 ..][0..3].* = .{ 0x49, 0xFF, 0xC2 }; // inc r10
    mem[at + 7 ..][0..7].* = .{ 0x41, 0x81, 0xE2, 0xFF, 0x0F, 0x00, 0x00 }; // and r10d, 0xfff
    mem[at + 14 ..][0..2].* = .{ 0xFF, 0xD0 }; // call rax
    mem[at + 16 ..][0..3].* = .{ 0x49, 0xFF, 0xC8 }; // dec r8
    mem[at + 19 ..][0..2].* = .{ 0x0F, 0x85 }; // jnz head
    mem[at + 21 ..][0..4].* = rel32(at + 25, head);
    at += 25;
    mem[at..][0..3].* = .{ 0x48, 0x39, 0xE4 }; // cmp rsp, rsp
    mem[at + 3 ..][0..2].* = .{ 0xEB, 0xFE }; // jmp $
    program.start = head;
    program.exit = at + 3;
    return program;
}

/// What `iterations` driver iterations from order entry 0 leave in the
/// guest word every body adds 7 to.
fn expectedValue(program: *const Program, iterations: u64) u32 {
    var total: u64 = 0;
    for (0..iterations) |i| total += program.order_bodies[i % order_len];
    return @truncate(total *% 7);
}

pub const Result = struct {
    cpu_ns: u64 = 0,
    host_instructions: u64 = 0,
    host_cycles: u64 = 0,
    block_executions: u64 = 0,
    retired: u64 = 0,
    compiled: u64 = 0,
    native_hops: u64 = 0,
    dispatch_entries: u64 = 0,
    chain_misses: u64 = 0,
    direct_patches: u64 = 0,
    indirect_patches: u64 = 0,
    hot_bytes: u64 = 0,
    context_value: u32 = 0,
    guest_value: u32 = 0,
    rsp: u64 = 0,
    expected_value: u32 = 0,
};

fn prepare(state: *ElfState, shape: Shape, jit_enabled: bool) Program {
    state.windows_runtime_enabled = true;
    const program = emitProgram(state.mem, shape);
    state.image_low = MEM_BASE + code;
    const span = (program.count + 1) * program.stride;
    state.image_high = MEM_BASE + code + span;
    state.configureWindowsExecutableRanges(&[_]I._WindowsExecutableRange{.{ .guest_base = MEM_BASE + code, .length = span }});
    @memset(state.mem[context..][0..0x100], 0);
    std.mem.writeInt(u32, state.mem[context + 0x40 ..][0..4], 3, .little);
    std.mem.writeInt(u32, state.mem[context + 0x44 ..][0..4], 4, .little);
    std.mem.writeInt(u32, state.mem[context + 0x4c ..][0..4], 0x10, .little);
    @memset(state.mem[guest..][0..0x100], 0);
    state.block_jit_enabled = jit_enabled;
    state.block_jit_hot_threshold = 1;
    state.regs.rsi = MEM_BASE + context;
    state.regs.rdi = MEM_BASE + guest;
    state.regs.rsp = MEM_BASE + stack_top;
    state.regs.r11 = MEM_BASE + order_area;
    state.regs.r10 = 0;
    state.regs.rflags = 0x2;
    return program;
}

fn runTo(state: *ElfState, exit: usize) !void {
    while (state.regs.rip != MEM_BASE + exit and !state.terminated) _ = state.step();
    try t.expectEqual(@as(u64, MEM_BASE + exit), state.regs.rip);
}

/// Warm-up (every first-level path compiles and links), then `passes`
/// timed driver iterations.
pub fn run(shape: Shape, passes: u64) !Result {
    var state = ElfState.init(t.allocator);
    defer state.deinit();
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const program = prepare(&state, shape, true);
    // `ROSETTE_CALL_RETURN_FASTMEM_BOUND=1`: the offline upper bound of a
    // fixed host offset for guest memory (`block_jit/fastmem_bound.zig`).
    const has_bound = @hasDecl(I._block_jit, "fastmem_bound");
    if (has_bound) if (std.c.getenv("ROSETTE_CALL_RETURN_FASTMEM_BOUND")) |raw| {
        if (raw[0] == '1') I._block_jit.fastmem_bound.delta = @intFromPtr(state.mem.ptr) -% MEM_BASE;
    };
    defer if (has_bound) {
        I._block_jit.fastmem_bound.delta = null;
    };
    // `ROSETTE_CALL_RETURN_LEAN=0`: the general memory templates
    // (`block_jit/lean_memory.zig`) for an in-tree comparison.
    const has_lean = @hasDecl(I._block_jit, "lean_memory");
    if (has_lean) if (std.c.getenv("ROSETTE_CALL_RETURN_LEAN")) |raw| {
        I._block_jit.lean_memory.enabled = raw[0] != '0';
    };
    defer if (has_lean) {
        I._block_jit.lean_memory.enabled = true;
    };
    // `ROSETTE_CALL_RETURN_EXIT_FLAGS=0`: every exit materialises its flags
    // (`block_jit/exit_flags.zig` off).
    const has_exit_flags = @hasDecl(I._block_jit, "exit_flags");
    if (has_exit_flags) if (std.c.getenv("ROSETTE_CALL_RETURN_EXIT_FLAGS")) |raw| {
        I._block_jit.exit_flags.enabled = raw[0] != '0';
    };
    defer if (has_exit_flags) {
        I._block_jit.exit_flags.enabled = true;
    };
    // `ROSETTE_CALL_RETURN_SPLIT=1`: every block's cold paths placed apart
    // (`block_jit/code_layout.zig`, an offline layout).
    if (std.c.getenv("ROSETTE_CALL_RETURN_SPLIT")) |raw| I._block_jit.code_layout.split_all = raw[0] == '1';
    defer I._block_jit.code_layout.split_all = false;
    var result: Result = .{};
    for ([_]u64{ 2 * order_len, order_len, passes }, 0..) |rounds, phase| {
        state.regs.rip = MEM_BASE + program.start;
        state.regs.r8 = rounds;
        const jit = state.block_jit orelse null;
        const executions_before = if (jit) |j| j.executions else 0;
        const retired_before = if (jit) |j| j.instructions_retired else 0;
        const hops_before = if (jit) |j| j.native_chain_hops else 0;
        const entries_before = if (jit) |j| j.dispatch_entries else 0;
        const misses_before = if (jit) |j| j.chain_exits_miss else 0;
        const counts_before = hostCounts();
        const started = threadCpu();
        try runTo(&state, program.exit);
        const elapsed = threadCpu() - started;
        const counts_after = hostCounts();
        if (phase == 2) {
            const j = state.block_jit.?;
            result.cpu_ns = elapsed;
            result.host_instructions = counts_after[0] -% counts_before[0];
            result.host_cycles = counts_after[1] -% counts_before[1];
            result.block_executions = j.executions - executions_before;
            result.retired = j.instructions_retired - retired_before;
            result.native_hops = j.native_chain_hops - hops_before;
            result.dispatch_entries = j.dispatch_entries - entries_before;
            result.chain_misses = j.chain_exits_miss - misses_before;
        }
    }
    const jit = state.block_jit.?;
    result.compiled = jit.compiled;
    for (jit.blocks) |maybe| {
        const block = maybe orelse continue;
        result.hot_bytes += block.code.len * @sizeOf(u32);
    }
    // `ROSETTE_CALL_RETURN_DUMP=1`: the ARM64 words of the first function a
    // driver iteration enters, for disassembly.
    if (std.c.getenv("ROSETTE_CALL_RETURN_DUMP") != null) {
        const first = std.mem.readInt(u64, state.mem[order_area..][0..8], .little);
        if (state.blockJitFindValidSlot(jit, first)) |found| {
            std.debug.print("call_return_dump rip=0x{x} x86={d} words=", .{ first, found.block.insns.len });
            for (found.block.code) |word| std.debug.print("{x:0>8} ", .{word});
            std.debug.print("\n", .{});
        }
    }
    if (@hasField(@TypeOf(jit.*), "direct_patches")) result.direct_patches = jit.direct_patches;
    if (@hasField(@TypeOf(jit.*), "indirect_patches")) result.indirect_patches = jit.indirect_patches;
    result.context_value = std.mem.readInt(u32, state.mem[context + 0x50 ..][0..4], .little);
    result.guest_value = std.mem.readInt(u32, state.mem[guest + 0x10 ..][0..4], .big);
    result.rsp = state.regs.rsp;
    result.expected_value = expectedValue(&program, 3 * order_len + passes);
    return result;
}

/// The same program interpreted only: the reference for exact results. In
/// parallel mode, as the translated run: a cooperative interpreter queues
/// stores in its TSO buffer, and this reads guest memory directly.
fn interpret(shape: Shape, iterations: u64) !Result {
    var state = ElfState.init(t.allocator);
    defer state.deinit();
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const program = prepare(&state, shape, false);
    state.regs.rip = MEM_BASE + program.start;
    state.regs.r8 = iterations;
    try runTo(&state, program.exit);
    return .{
        .context_value = std.mem.readInt(u32, state.mem[context + 0x50 ..][0..4], .little),
        .guest_value = std.mem.readInt(u32, state.mem[guest + 0x10 ..][0..4], .big),
        .rsp = state.regs.rsp,
        .expected_value = expectedValue(&program, iterations),
    };
}

test "call return: translated calls through rel32 and the indirection table return exactly as interpreted" {
    for ([_]u8{ 0, 50, 100 }) |indirect| {
        const shape: Shape = .{ .functions = 96, .depth = 4, .utilities = 4, .repeat = 1, .indirect_percent = indirect };
        const translated = try run(shape, 1000);
        // Warm-up and timed passes together, interpreted.
        const reference = try interpret(shape, 2 * order_len + order_len + 1000);
        try t.expectEqual(translated.expected_value, reference.guest_value);
        try t.expectEqual(translated.expected_value, translated.guest_value);
        try t.expectEqual(reference.context_value, translated.context_value);
        try t.expectEqual(reference.guest_value, translated.guest_value);
        try t.expectEqual(reference.rsp, translated.rsp);
        try t.expectEqual(@as(u64, MEM_BASE + stack_top), translated.rsp);
        try t.expect(translated.native_hops > 0);
    }
}

test "call return: per-block CPU as hot functions grow (ROSETTE_CALL_RETURN_BENCH=1)" {
    if (std.c.getenv("ROSETTE_CALL_RETURN_BENCH") == null) return error.SkipZigTest;
    const label: []const u8 = if (std.c.getenv("ROSETTE_CALL_RETURN_BINARY")) |raw| std.mem.sliceTo(raw, 0) else "current";
    const pair: []const u8 = if (std.c.getenv("ROSETTE_CALL_RETURN_PAIR")) |raw| std.mem.sliceTo(raw, 0) else "0";
    if (has_indirect) if (std.c.getenv("ROSETTE_CALL_RETURN_INDIRECT_LINKS")) |raw| {
        I._block_jit.indirect_links.enabled = raw[0] != '0';
    };
    defer if (has_indirect) {
        I._block_jit.indirect_links.enabled = null;
    };
    const functions = [_]usize{ 256, 1024, 2048, 4096, 8192 };
    // `ROSETTE_CALL_RETURN_UTILITIES=<n>` changes how many popular leaves
    // share the call sites (default 16: a few functions with many callers).
    const utilities: usize = if (std.c.getenv("ROSETTE_CALL_RETURN_UTILITIES")) |raw| std.fmt.parseInt(usize, std.mem.sliceTo(raw, 0), 10) catch 16 else 16;
    for ([_]u8{ 0, 50, 100 }) |indirect| {
        for (functions) |count| {
            if (utilities * 2 > count) continue;
            const shape: Shape = .{ .functions = count, .depth = 8, .utilities = utilities, .repeat = 1, .indirect_percent = indirect };
            const r = try run(shape, 20_000);
            std.debug.print("call_return series_pair={s} binary={s} functions={d} depth={d} utilities={d} repeat={d} indirect={d} compiled={d} block_executions={d} retired={d} cpu_ns={d} native_hops={d} dispatch_entries={d} chain_misses={d} direct_patches={d} indirect_patches={d} hot_bytes_per_block={d} context_value={d} guest_value={d} ns_per_block={d:.2} host_per_x86={d:.2} ipc={d:.2}\n", .{
                pair,                                                                                       label,                                                                                          count,            shape.depth,
                shape.utilities,                                                                            shape.repeat,                                                                                   indirect,         r.compiled,
                r.block_executions,                                                                         r.retired,                                                                                      r.cpu_ns,         r.native_hops,
                r.dispatch_entries,                                                                         r.chain_misses,                                                                                 r.direct_patches, r.indirect_patches,
                r.hot_bytes / @max(r.compiled, 1),                                                          r.context_value,                                                                                r.guest_value,    @as(f64, @floatFromInt(r.cpu_ns)) / @as(f64, @floatFromInt(@max(r.block_executions, 1))),
                @as(f64, @floatFromInt(r.host_instructions)) / @as(f64, @floatFromInt(@max(r.retired, 1))), @as(f64, @floatFromInt(r.host_instructions)) / @as(f64, @floatFromInt(@max(r.host_cycles, 1))),
            });
        }
    }
}
