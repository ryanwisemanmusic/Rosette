//! Xenia's GPU command processor, replayed offline through the production
//! PE executor: the register-write path that Halo 3's heavy scenes spend
//! most of GPU Commands' translated instructions in. No GPU, driver or
//! emulator runs; the five functions are the shipped bytes
//! (`process/impl/xenia_register_write_bytes.zig`, copied read only from
//! xenia_canary.exe) with their outside-function rel32 fields relocated.
//!
//! Every PM4 register write is a loop iteration around a virtual
//! `VulkanCommandProcessor::WriteRegister`, which calls the base
//! `CommandProcessor::WriteRegister` and returns through a dirty-bit tail:
//! 48-61 instructions in five to eight translated blocks. Run
//! 20261017T020143Z-3cc55620b9d9's heavy title-screen windows executed ~57M
//! GPU Commands instructions per frame in 10.3-instruction blocks.
//!
//! The native loop-head gate (`process/impl/xenia_register_writes.zig`) is
//! proven here by full-state differential comparison: the whole guest
//! memory and every register after Xenia's own code, gate on and gate off,
//! over randomized packets that include special, logged, dirty-tracked and
//! wrapping registers.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const ElfState = P.ElfState;
const MEM_BASE = I._MEM_BASE;
const signatures = @import("../impl/xenia_register_write_bytes.zig");
const gate = @import("../impl/xenia_register_writes.zig");

const code: usize = 0x1000;
const f_type0: usize = code;
const f_base_write: usize = code + 0x100;
const f_vulkan_write: usize = code + 0x200;
const f_from_memory: usize = code + 0x400;
const f_range: usize = code + 0x600;
/// `HandleSpecialRegisterWrite`: returns to `WriteRegister`'s caller.
const stub_special: usize = code + 0x700;
/// `logging::ShouldLog`: false, so the logged path stores nothing.
const stub_should_log: usize = code + 0x710;
/// Packet overflow and one-register mode, never reached by these packets.
const stub_unreached: usize = code + 0x720;
const driver: usize = code + 0x800;
const image_end: usize = driver;
const object: usize = 0x10000;
const vtable: usize = 0x14000;
const texture_cache: usize = 0x16000;
const register_file: usize = 0x20000;
const ring: usize = 0x40000;
const constants: usize = 0x60000;
const stack_top: usize = 0x7f000;
const memory_size: usize = 0x80000;
const ring_capacity: u32 = 0x10000;
/// Each pass starts the read offset 64 bytes before the end, so the ring
/// wraps within the first sixteen registers.
const ring_start: u32 = ring_capacity - 64;
const register_count: usize = 0x5100;

pub const Packet = struct { kind: gate.Kind, base: u32, count: u32 };

pub const Run = struct {
    terminated: bool,
    faulted: bool,
    cpu_ns: u64,
    retired: u64,
    block_executions: u64,
    regs: P.ElfRegs,
    memory: []u8,
    fn deinit(run: *Run) void {
        t.allocator.free(run.memory);
    }
};

fn rel32(from: usize, to: usize) i32 {
    return @intCast(@as(i64, @intCast(to)) - @as(i64, @intCast(from)));
}

fn threadCpu() u64 {
    var stamp: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &stamp) == 0);
    return @as(u64, @intCast(stamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(stamp.nsec));
}

const Emitter = struct {
    mem: []u8,
    at: usize,
    fn bytes(e: *Emitter, values: []const u8) void {
        @memcpy(e.mem[e.at..][0..values.len], values);
        e.at += values.len;
    }
    fn imm32(e: *Emitter, value: u32) void {
        std.mem.writeInt(u32, e.mem[e.at..][0..4], value, .little);
        e.at += 4;
    }
    fn imm64(e: *Emitter, value: u64) void {
        std.mem.writeInt(u64, e.mem[e.at..][0..8], value, .little);
        e.at += 8;
    }
    fn call(e: *Emitter, target: usize) void {
        e.bytes(&.{0xE8});
        e.imm32(@bitCast(rel32(e.at + 4, target)));
    }
};

pub fn addresses() gate.Addresses {
    return .{
        .execute_packet_type0 = MEM_BASE + f_type0,
        .base_write_register = MEM_BASE + f_base_write,
        .vulkan_write_register = MEM_BASE + f_vulkan_write,
        .write_registers_from_memory = MEM_BASE + f_from_memory,
        .write_register_range_from_ring = MEM_BASE + f_range,
    };
}

/// The five functions at their test addresses, every rel32 that leaves its
/// function pointed at the base `WriteRegister` or a stub.
fn install(mem: []u8) void {
    const placed = [_]struct { function: signatures.Function, at: usize }{
        .{ .function = signatures.execute_packet_type0, .at = f_type0 },
        .{ .function = signatures.base_write_register, .at = f_base_write },
        .{ .function = signatures.vulkan_write_register, .at = f_vulkan_write },
        .{ .function = signatures.write_registers_from_memory, .at = f_from_memory },
        .{ .function = signatures.write_register_range_from_ring, .at = f_range },
    };
    for (placed) |entry| {
        @memcpy(mem[entry.at..][0..entry.function.bytes.len], entry.function.bytes);
        for (entry.function.external) |external| {
            const target: usize = switch (external.kind) {
                .base_write_register => f_base_write,
                .masked => switch (external.build_target) {
                    0x1401c8dc0 => stub_special,
                    0x140112c60 => stub_should_log,
                    else => stub_unreached,
                },
            };
            const field = entry.at + external.offset;
            std.mem.writeInt(i32, mem[field..][0..4], rel32(field + 4, target), .little);
        }
    }
    mem[stub_special] = 0xC3; // ret
    mem[stub_should_log..][0..3].* = .{ 0x31, 0xC0, 0xC3 }; // xor eax, eax ; ret
    mem[stub_unreached] = 0xF4; // hlt
}

fn seed(state: *ElfState, random: std.Random) void {
    const mem = state.mem;
    @memset(mem[object..][0..0x2000], 0);
    std.mem.writeInt(u64, mem[object..][0..8], MEM_BASE + vtable, .little);
    std.mem.writeInt(u64, mem[object + 0x08 ..][0..8], MEM_BASE + ring, .little);
    std.mem.writeInt(u32, mem[object + 0x10 ..][0..4], ring_capacity, .little);
    std.mem.writeInt(u32, mem[object + 0x14 ..][0..4], ring_start, .little);
    std.mem.writeInt(u32, mem[object + 0x18 ..][0..4], ring_capacity / 2, .little);
    std.mem.writeInt(u64, mem[object + 0x38 ..][0..8], MEM_BASE + register_file, .little);
    mem[object + 0xe58] = @intFromBool(random.uintLessThan(u8, 4) != 0);
    std.mem.writeInt(u32, mem[object + 0x1798 ..][0..4], random.int(u32) | 0xFFFF_0000, .little);
    for (0..8) |word| std.mem.writeInt(u64, mem[object + 0x17c8 + word * 8 ..][0..8], random.int(u64), .little);
    std.mem.writeInt(u64, mem[object + 0x1450 ..][0..8], if (random.boolean()) MEM_BASE + texture_cache else 0, .little);
    @memset(mem[texture_cache..][0..0x1000], 0xFF);
    @memset(mem[vtable..][0..0x100], 0);
    std.mem.writeInt(u64, mem[vtable + 0x70 ..][0..8], MEM_BASE + f_vulkan_write, .little);
    std.mem.writeInt(u64, mem[vtable + 0x78 ..][0..8], MEM_BASE + f_from_memory, .little);
    std.mem.writeInt(u64, mem[vtable + 0x80 ..][0..8], MEM_BASE + f_range, .little);
    @memset(mem[register_file..][0 .. register_count * 4], 0);
    for (0..ring_capacity / 4) |word| std.mem.writeInt(u32, mem[ring + word * 4 ..][0..4], random.int(u32), .big);
    for (0..0x1000) |word| std.mem.writeInt(u32, mem[constants + word * 4 ..][0..4], random.int(u32), .big);
}

/// Per pass: reset the ring read offset, then each packet through its
/// entry point, as `ExecutePacket` and the SET_CONSTANT / LOAD_ALU_CONSTANT
/// handlers reach them.
fn emitDriver(mem: []u8, packets: []const Packet) void {
    var e = Emitter{ .mem = mem, .at = driver };
    e.bytes(&.{ 0x48, 0x83, 0xEC, 0x28 }); // sub rsp, 0x28
    const loop = e.at;
    e.bytes(&.{ 0x48, 0xB9 }); // mov rcx, object
    e.imm64(MEM_BASE + object);
    e.bytes(&.{ 0xC7, 0x41, 0x14 }); // mov dword [rcx+0x14], ring_start
    e.imm32(ring_start);
    for (packets) |packet| {
        e.bytes(&.{ 0x48, 0xB9 }); // mov rcx, object
        e.imm64(MEM_BASE + object);
        switch (packet.kind) {
            .none => {},
            .packet_type0 => {
                e.bytes(&.{0xBA}); // mov edx, header
                e.imm32(((packet.count - 1) << 16) | packet.base);
                e.call(f_type0);
            },
            .range_from_ring => {
                e.bytes(&.{ 0x48, 0x8D, 0x51, 0x08 }); // lea rdx, [rcx+8]: the reader
                e.bytes(&.{ 0x41, 0xB8 }); // mov r8d, base
                e.imm32(packet.base);
                e.bytes(&.{ 0x41, 0xB9 }); // mov r9d, count
                e.imm32(packet.count);
                e.call(f_range);
            },
            .from_memory => {
                e.bytes(&.{0xBA}); // mov edx, base
                e.imm32(packet.base);
                e.bytes(&.{ 0x49, 0xB8 }); // mov r8, constants
                e.imm64(MEM_BASE + constants);
                e.bytes(&.{ 0x41, 0xB9 }); // mov r9d, count
                e.imm32(packet.count);
                e.call(f_from_memory);
            },
        }
    }
    e.bytes(&.{ 0x48, 0xFF, 0xCB }); // dec rbx
    e.bytes(&.{ 0x0F, 0x85 }); // jnz loop
    e.imm32(@bitCast(rel32(e.at + 4, loop)));
    // No flag survives a call under the Windows x64 calling convention,
    // and the translator materializes none at a call or return
    // (`flags_dead_at_calls`): the CF `dec` leaves alone would be a stale
    // value in any translated run. Define every flag before stopping.
    e.bytes(&.{ 0x48, 0x39, 0xE4 }); // cmp rsp, rsp
    e.bytes(&.{0xF4}); // hlt
}

pub const Mode = enum { interpreted, translated, gated };

/// Replays `passes` passes of `packets` and returns the whole guest state.
pub fn replay(packets: []const Packet, mode: Mode, passes: u64, seed_value: u64) !Run {
    var state = ElfState.initWithMemory(t.allocator, memory_size);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    // The functions are xenia_canary.exe's own text, as in a live run;
    // with no image bounds every call would be refused as unproven.
    state.image_low = MEM_BASE + code;
    state.image_high = MEM_BASE + image_end;
    install(state.mem);
    var prng = std.Random.DefaultPrng.init(seed_value);
    seed(&state, prng.random());
    emitDriver(state.mem, packets);
    const saved = gate.enabled;
    defer gate.enabled = saved;
    gate.enabled = mode == .gated;
    if (mode == .gated) try t.expect(gate.armAt(&state, addresses()));
    state.regs.rbx = passes;
    state.regs.rsp = MEM_BASE + stack_top;
    state.regs.rip = MEM_BASE + driver;
    state.regs.rflags = 0x2;
    state.block_jit_enabled = mode != .interpreted;
    state.block_jit_hot_threshold = 2;
    const started = threadCpu();
    state.runWithLimit(1_000_000 + passes * 2_000_000);
    const cpu_ns = threadCpu() - started;
    var run = Run{
        .terminated = state.terminated,
        .faulted = state.faulted,
        .cpu_ns = cpu_ns,
        .retired = 0,
        .block_executions = 0,
        .regs = state.regs,
        .memory = try t.allocator.dupe(u8, state.mem),
    };
    if (state.block_jit) |jit| {
        run.retired = jit.instructions_retired;
        run.block_executions = jit.executions;
    }
    return run;
}

fn registers(packets: []const Packet) u64 {
    var total: u64 = 0;
    for (packets) |packet| total += packet.count;
    return total;
}

/// Bases chosen to cover every branch of `WriteRegister` and its Vulkan
/// tail: float constants either side of 0x400, bool/loop, fetch, the 0x21xx
/// and 0x22xx/0x23xx dirty groups, special registers and the logged range.
const bases = [_]u32{ 0x4000, 0x43e0, 0x4400, 0x47f0, 0x4900, 0x4920, 0x4800, 0x48b8, 0x2100, 0x21f8, 0x2200, 0x2280, 0x2380, 0x2398, 0x0570, 0x1920, 0x0a2f, 0x4ff0, 0x0100, 0x5000 };

fn randomPackets(buffer: []Packet, random: std.Random) []Packet {
    const count = 1 + random.uintLessThan(usize, buffer.len);
    for (buffer[0..count]) |*packet| {
        const kind: gate.Kind = @enumFromInt(1 + random.uintLessThan(u32, 3));
        const base = bases[random.uintLessThan(usize, bases.len)] +% random.uintLessThan(u32, 8);
        // Type-0 packets carry a 15-bit base and at most 0x4000 registers.
        packet.* = .{ .kind = kind, .base = base & 0x7fff, .count = 1 + random.uintLessThan(u32, 40) };
    }
    return buffer[0..count];
}

fn expectSameState(reference: *const Run, other: *const Run) !void {
    try t.expect(reference.terminated and !reference.faulted);
    try t.expect(other.terminated and !other.faulted);
    try t.expectEqualDeep(reference.regs, other.regs);
    if (!std.mem.eql(u8, reference.memory, other.memory)) {
        const at = std.mem.indexOfDiff(u8, reference.memory, other.memory).?;
        std.debug.print("command replay: guest memory differs first at 0x{x}\n", .{at});
        return error.TestUnexpectedResult;
    }
}

test "Xenia command replay: the native loop-head gate leaves exactly the state Xenia's code leaves" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    var prng = std.Random.DefaultPrng.init(0x5EED_C0DE);
    const before = gate.counters.registers[1].load(.monotonic) + gate.counters.registers[2].load(.monotonic) + gate.counters.registers[3].load(.monotonic);
    const exits_before = gate.counters.loop_exits.load(.monotonic);
    var buffer: [12]Packet = undefined;
    for (0..128) |case| {
        const packets = randomPackets(&buffer, prng.random());
        const seed_value = 0xA11CE + case;
        var interpreted = try replay(packets, .interpreted, 2, seed_value);
        defer interpreted.deinit();
        var translated = try replay(packets, .translated, 6, seed_value);
        defer translated.deinit();
        var gated = try replay(packets, .gated, 6, seed_value);
        defer gated.deinit();
        // Passes after the first repeat the same writes, so the interpreted
        // reference with fewer passes ends in the same state.
        try expectSameState(&interpreted, &translated);
        try expectSameState(&translated, &gated);
    }
    const after = gate.counters.registers[1].load(.monotonic) + gate.counters.registers[2].load(.monotonic) + gate.counters.registers[3].load(.monotonic);
    try t.expect(after > before);
    // Final iterations ran natively too, not only the ones before them.
    try t.expect(gate.counters.loop_exits.load(.monotonic) > exits_before);
}

test "Xenia command replay: every entry kind runs natively and stops before special and logged registers" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const cases = [_]Packet{
        .{ .kind = .packet_type0, .base = 0x4000, .count = 64 },
        .{ .kind = .range_from_ring, .base = 0x4400, .count = 64 },
        .{ .kind = .from_memory, .base = 0x4380, .count = 256 },
        .{ .kind = .packet_type0, .base = 0x0570, .count = 24 }, // 0x578-0x57f are special
        .{ .kind = .range_from_ring, .base = 0x4ffc, .count = 12 }, // past 0x5002 logs
        .{ .kind = .from_memory, .base = 0x1920, .count = 8 }, // 0x1922-0x1925 are special
    };
    for (cases) |packet| {
        const kind = @intFromEnum(packet.kind);
        const native_before = gate.counters.registers[kind].load(.monotonic);
        const exits_before = gate.counters.loop_exits.load(.monotonic);
        const stops_before = gate.counters.stops[@intFromEnum(gate.Stop.special_register)].load(.monotonic) + gate.counters.stops[@intFromEnum(gate.Stop.logged_register)].load(.monotonic);
        var translated = try replay(&.{packet}, .translated, 4, 77);
        defer translated.deinit();
        var gated = try replay(&.{packet}, .gated, 4, 77);
        defer gated.deinit();
        try expectSameState(&translated, &gated);
        try t.expect(gate.counters.registers[kind].load(.monotonic) > native_before);
        // A final register that logs is Xenia's to run; any other ends the
        // loop natively.
        const final_register = packet.base + packet.count - 1;
        if (final_register <= 0x5002) try t.expect(gate.counters.loop_exits.load(.monotonic) > exits_before);
        const stops = gate.counters.stops[@intFromEnum(gate.Stop.special_register)].load(.monotonic) + gate.counters.stops[@intFromEnum(gate.Stop.logged_register)].load(.monotonic);
        if (packet.base == 0x0570 or packet.base == 0x4ffc or packet.base == 0x1920) try t.expect(stops > stops_before);
    }
}

test "Xenia command replay: a changed byte, call target or vtable leaves Xenia's code in charge" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(t.allocator, memory_size);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.image_low = MEM_BASE + code;
    state.image_high = MEM_BASE + image_end;
    install(state.mem);
    try t.expect(gate.verify(&state, addresses()));
    // One byte of the Vulkan dirty tail.
    state.mem[f_vulkan_write + 0x30] ^= 1;
    try t.expect(!gate.verify(&state, addresses()));
    state.mem[f_vulkan_write + 0x30] ^= 1;
    // The base WriteRegister call reaching anything else.
    const field = f_from_memory + 0x82;
    const original = std.mem.readInt(i32, state.mem[field..][0..4], .little);
    std.mem.writeInt(i32, state.mem[field..][0..4], original + 16, .little);
    try t.expect(!gate.verify(&state, addresses()));
    std.mem.writeInt(i32, state.mem[field..][0..4], original, .little);
    try t.expect(gate.verify(&state, addresses()));
    // A masked field may point anywhere.
    std.mem.writeInt(i32, state.mem[f_base_write + 0x40 ..][0..4], 0x1234, .little);
    try t.expect(gate.verify(&state, addresses()));

    // A virtual WriteRegister other than the proven one: the gate refuses
    // every type-0 iteration and the run still matches.
    const packet = Packet{ .kind = .packet_type0, .base = 0x4000, .count = 32 };
    const refusals_before = gate.counters.stops[@intFromEnum(gate.Stop.virtual_target)].load(.monotonic);
    var replaced = try replayWithVtable(packet, f_base_write);
    defer replaced.deinit();
    try t.expect(gate.counters.stops[@intFromEnum(gate.Stop.virtual_target)].load(.monotonic) > refusals_before);
}

/// The loader's resolver, answering the five mangled names at this test's
/// addresses (or all but one).
const Names = struct {
    missing: ?[]const u8 = null,
    fn resolve(_: *const anyopaque, _: u64, _: []u8) ?P.GuestSymbol {
        return null;
    }
    fn addressOf(context: *const anyopaque, name: []const u8) ?u64 {
        const self: *const Names = @ptrCast(@alignCast(context));
        if (self.missing) |missing| if (std.mem.eql(u8, missing, name)) return null;
        const a = addresses();
        const known = [_]struct { symbol: []const u8, address: u64 }{
            .{ .symbol = signatures.execute_packet_type0.symbol, .address = a.execute_packet_type0 },
            .{ .symbol = signatures.base_write_register.symbol, .address = a.base_write_register },
            .{ .symbol = signatures.vulkan_write_register.symbol, .address = a.vulkan_write_register },
            .{ .symbol = signatures.write_registers_from_memory.symbol, .address = a.write_registers_from_memory },
            .{ .symbol = signatures.write_register_range_from_ring.symbol, .address = a.write_register_range_from_ring },
        };
        for (known) |entry| if (std.mem.eql(u8, entry.symbol, name)) return entry.address;
        return null;
    }
};

test "Xenia command replay: gates arm from the loader's mangled symbols, and not without all five" {
    const a = addresses();
    for ([_]?[]const u8{ null, signatures.write_register_range_from_ring.symbol }) |missing| {
        var state = ElfState.initWithMemory(t.allocator, memory_size);
        defer state.deinit();
        state.windows_runtime_enabled = true;
        state.image_low = MEM_BASE + code;
        state.image_high = MEM_BASE + image_end;
        install(state.mem);
        // No resolver yet: no gate, and nothing decided that a later
        // resolver could not change.
        try t.expectEqual(@as(u32, 0), gate.gateKind(&state, a.execute_packet_type0 + gate.type0_loop_offset));
        try t.expectEqual(@as(u8, 0), state.xenia_register_writes.stage.load(.acquire));
        var names = Names{ .missing = missing };
        state.guest_symbol_resolver = .{ .context = &names, .resolve = Names.resolve, .address_of = Names.addressOf };
        const expected: [3]u32 = if (missing == null) .{ 1, 2, 3 } else .{ 0, 0, 0 };
        try t.expectEqual(expected[0], gate.gateKind(&state, a.execute_packet_type0 + gate.type0_loop_offset));
        try t.expectEqual(expected[1], gate.gateKind(&state, a.write_register_range_from_ring + gate.ring_loop_offset));
        try t.expectEqual(expected[2], gate.gateKind(&state, a.write_registers_from_memory + gate.memory_loop_offset));
        // Only the loop heads carry gates.
        try t.expectEqual(@as(u32, 0), gate.gateKind(&state, a.execute_packet_type0));
        try t.expectEqual(missing == null, gate.isGateAddress(&state, a.write_registers_from_memory + gate.memory_loop_offset));
    }
}

/// A type-0 replay whose vtable's WriteRegister slot names `target`.
fn replayWithVtable(packet: Packet, target: usize) !Run {
    var state = ElfState.initWithMemory(t.allocator, memory_size);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.image_low = MEM_BASE + code;
    state.image_high = MEM_BASE + image_end;
    install(state.mem);
    var prng = std.Random.DefaultPrng.init(9);
    seed(&state, prng.random());
    std.mem.writeInt(u64, state.mem[vtable + 0x70 ..][0..8], MEM_BASE + target, .little);
    emitDriver(state.mem, &.{packet});
    try t.expect(gate.armAt(&state, addresses()));
    state.regs.rbx = 4;
    state.regs.rsp = MEM_BASE + stack_top;
    state.regs.rip = MEM_BASE + driver;
    state.regs.rflags = 0x2;
    state.block_jit_enabled = true;
    state.block_jit_hot_threshold = 2;
    state.runWithLimit(10_000_000);
    try t.expect(state.terminated and !state.faulted);
    return .{ .terminated = true, .faulted = false, .cpu_ns = 0, .retired = 0, .block_executions = 0, .regs = state.regs, .memory = try t.allocator.dupe(u8, state.mem) };
}

/// The workloads timed by the benchmark below.
pub const profiles = [_]struct { name: []const u8, packets: []const Packet }{
    .{ .name = "type0_64_constants", .packets = &.{ .{ .kind = .packet_type0, .base = 0x4000, .count = 64 }, .{ .kind = .packet_type0, .base = 0x4400, .count = 64 } } },
    .{ .name = "set_constant_range_64", .packets = &.{ .{ .kind = .range_from_ring, .base = 0x4000, .count = 64 }, .{ .kind = .range_from_ring, .base = 0x4400, .count = 64 } } },
    .{ .name = "load_alu_constant_256", .packets = &.{.{ .kind = .from_memory, .base = 0x4380, .count = 256 }} },
    // Halo's sampled indirect buffer: ~16 type-0 packets of ~10 registers
    // per draw, among them fetch and dirty-tracked state.
    .{ .name = "draw_state_small_packets", .packets = &.{
        .{ .kind = .packet_type0, .base = 0x2100, .count = 3 },     .{ .kind = .packet_type0, .base = 0x2280, .count = 8 },
        .{ .kind = .packet_type0, .base = 0x2380, .count = 12 },    .{ .kind = .packet_type0, .base = 0x4800, .count = 12 },
        .{ .kind = .packet_type0, .base = 0x4900, .count = 8 },     .{ .kind = .range_from_ring, .base = 0x4000, .count = 16 },
        .{ .kind = .range_from_ring, .base = 0x4400, .count = 16 }, .{ .kind = .packet_type0, .base = 0x2200, .count = 6 },
    } },
};

test "Xenia command replay CPU timing (ROSETTE_COMMAND_REPLAY_BENCH=1)" {
    if (std.c.getenv("ROSETTE_COMMAND_REPLAY_BENCH") == null) return error.SkipZigTest;
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const passes: u64 = if (std.c.getenv("ROSETTE_COMMAND_REPLAY_PASSES")) |text| std.fmt.parseInt(u64, std.mem.span(text), 10) catch 20_000 else 20_000;
    if (std.c.getenv("ROSETTE_COMMAND_REPLAY_PROFILE")) |mode| {
        // One long single-mode run for an external sampling profiler.
        const chosen: usize = if (std.c.getenv("ROSETTE_COMMAND_REPLAY_PROFILE_INDEX")) |text| std.fmt.parseInt(usize, std.mem.span(text), 10) catch 0 else 0;
        var run = try replay(profiles[@min(chosen, profiles.len - 1)].packets, if (std.mem.eql(u8, std.mem.span(mode), "on")) .gated else .translated, passes, 1);
        defer run.deinit();
        std.debug.print("command_replay profile_run cpu_ns={d}\n", .{run.cpu_ns});
        return;
    }
    for (profiles, 0..) |profile, index| {
        const writes = registers(profile.packets) * passes;
        for (0..7) |pair| {
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                const native_before = nativeRegisters();
                const gates_before = gateCalls();
                var run = try replay(profile.packets, if (enabled) .gated else .translated, passes, 0xBE7C4 + index);
                defer run.deinit();
                try t.expect(run.terminated and !run.faulted);
                std.debug.print("command_replay profile={d} name={s} pair={d} enabled={} register_writes={d} cpu_ns={d} retired={d} blocks={d} native_registers={d} gate_calls={d}\n", .{ index, profile.name, pair, enabled, writes, run.cpu_ns, run.retired, run.block_executions, nativeRegisters() - native_before, gateCalls() - gates_before });
            }
        }
    }
}

fn nativeRegisters() u64 {
    var total: u64 = 0;
    for (gate.counters.registers[1..]) |*value| total += value.load(.monotonic);
    return total;
}

fn gateCalls() u64 {
    var total: u64 = 0;
    for (gate.counters.gate_calls[1..]) |*value| total += value.load(.monotonic);
    return total;
}
