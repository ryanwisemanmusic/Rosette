//! Xenia's GPU register-write loops, run natively at their loop heads.
//!
//! Every PM4 register write Xenia's command processor performs is a loop
//! iteration around `VulkanCommandProcessor::WriteRegister`, which calls the
//! base `CommandProcessor::WriteRegister` and then updates a dirty bit: type-0
//! packets (`ExecutePacketType0`), SET_CONSTANT ranges
//! (`WriteRegisterRangeFromRing`) and LOAD_ALU_CONSTANT
//! (`VulkanCommandProcessor::WriteRegistersFromMem`). Translated, one register
//! is 48-61 instructions in five to eight blocks, and block hops dominate:
//! 27-45 ns a register in the offline replay of the shipped bytes. Halo 3's
//! heavy scenes write a few hundred registers per draw on the GPU Commands
//! thread, the critical thread of those frames.
//!
//! A translated block that starts at one of the three loop heads calls
//! `entryGate` before it loads its register cache. At a loop head every
//! caller-saved register and every flag is dead: the iteration recomputes
//! them before reading them. The gate runs iterations natively, advances
//! only the loop's own callee-saved induction registers, and always leaves
//! the final iteration to the real code, which therefore leaves the exact
//! registers, flags and stack slots the guest would have. It stops at an
//! iteration boundary, before any side effect of that iteration, whenever it
//! cannot prove the iteration: a special or logged register, a page the
//! translator's TLB does not admit, a different virtual `WriteRegister`, or a
//! changed image. The guest code then runs that iteration itself.
//!
//! Memory is reached through this executor's own software TLB under the
//! translator's admission rules, with the acquire/release lanes translated
//! code uses; the image's five functions must match
//! `xenia_register_write_bytes.zig` exactly before any gate is compiled.
const std = @import("std");
const process = @import("../../process.zig");
const life = @import("lifecycle.zig");
const jit = @import("block_jit.zig");
const guest_memory = @import("guest_memory.zig");
const signatures = @import("xenia_register_write_bytes.zig");
const ElfState = process.ElfState;
const I = process.__ProcessInternals;
const Tlb = I._block_jit.Tlb;

/// Internal control for offline comparison; production keeps it on.
pub var enabled: bool = true;

pub const Kind = enum(u32) { none = 0, packet_type0 = 1, range_from_ring = 2, from_memory = 3 };

/// Loop heads inside their functions: `ExecutePacketType0`'s at
/// 0x1401cfd90, `WriteRegisterRangeFromRing`'s at 0x1401c9230 and
/// `WriteRegistersFromMem`'s loop top at 0x140a473be in the supported build.
pub const type0_loop_offset: u64 = 0x50;
pub const ring_loop_offset: u64 = 0x20;
pub const memory_loop_offset: u64 = 0x6e;

pub const Addresses = struct {
    execute_packet_type0: u64,
    base_write_register: u64,
    vulkan_write_register: u64,
    write_registers_from_memory: u64,
    write_register_range_from_ring: u64,
};

/// Per process, one field of `ElfState`.
pub const Armed = struct {
    /// 0 unresolved, 1 resolving, 2 resolved.
    stage: std.atomic.Value(u8) = .init(0),
    resolved: bool = false,
    addresses: Addresses = undefined,
    /// The image code generation the bytes were proven at.
    generation: u64 = 0,
};

pub const Stop = enum { special_register, logged_register, unadmitted_page, misaligned, virtual_target, invariant, image_changed, store_queue };

/// Process-wide counts, published at the existing report points.
pub const Counters = struct {
    gate_calls: [4]std.atomic.Value(u64) = @splat(.init(0)),
    registers: [4]std.atomic.Value(u64) = @splat(.init(0)),
    stops: [std.meta.fields(Stop).len]std.atomic.Value(u64) = @splat(.init(0)),
    /// Gates that ran the final iteration too and left at the loop's exit.
    loop_exits: std.atomic.Value(u64) = .init(0),
};
pub var counters: Counters = .{};

fn note(counter: *std.atomic.Value(u64), amount: u64) void {
    if (amount != 0) _ = counter.fetchAdd(amount, .monotonic);
}

// -- arming --------------------------------------------------------------------

fn functions(addresses: Addresses) [5]struct { function: signatures.Function, address: u64 } {
    return .{
        .{ .function = signatures.execute_packet_type0, .address = addresses.execute_packet_type0 },
        .{ .function = signatures.base_write_register, .address = addresses.base_write_register },
        .{ .function = signatures.vulkan_write_register, .address = addresses.vulkan_write_register },
        .{ .function = signatures.write_registers_from_memory, .address = addresses.write_registers_from_memory },
        .{ .function = signatures.write_register_range_from_ring, .address = addresses.write_register_range_from_ring },
    };
}

/// Whether the image holds the supported bytes at `addresses`: every byte
/// equal except masked rel32 fields, and both calls into the base
/// `WriteRegister` reaching `addresses.base_write_register`.
pub fn verify(self: *ElfState, addresses: Addresses) bool {
    for (functions(addresses)) |entry| {
        const expected = entry.function.bytes;
        const source = jit.fetchCodeRange(self, entry.address, expected.len) orelse return false;
        var copy: [0x200]u8 = undefined;
        if (expected.len > copy.len) return false;
        jit.copyGuestCode(self, copy[0..expected.len], source);
        var masked: [0x200]bool = @splat(false);
        for (entry.function.external) |external| {
            const at: usize = external.offset;
            for (at..at + 4) |byte| masked[byte] = true;
            if (external.kind == .base_write_register) {
                const displacement: i32 = @bitCast(std.mem.readInt(u32, copy[at..][0..4], .little));
                const target = entry.address +% at +% 4 +% @as(u64, @bitCast(@as(i64, displacement)));
                if (target != addresses.base_write_register) return false;
            }
        }
        for (expected, copy[0..expected.len], 0..) |want, have, index| {
            if (!masked[index] and want != have) return false;
        }
    }
    return true;
}

fn currentGeneration(self: *ElfState) u64 {
    return guest_memory.loadCodeGeneration(&self.windows_image_code_generation);
}

fn fromSymbols(self: *ElfState) ?Addresses {
    const resolver = self.guest_symbol_resolver orelse return null;
    const address_of = resolver.address_of orelse return null;
    return .{
        .execute_packet_type0 = address_of(resolver.context, signatures.execute_packet_type0.symbol) orelse return null,
        .base_write_register = address_of(resolver.context, signatures.base_write_register.symbol) orelse return null,
        .vulkan_write_register = address_of(resolver.context, signatures.vulkan_write_register.symbol) orelse return null,
        .write_registers_from_memory = address_of(resolver.context, signatures.write_registers_from_memory.symbol) orelse return null,
        .write_register_range_from_ring = address_of(resolver.context, signatures.write_register_range_from_ring.symbol) orelse return null,
    };
}

fn publish(self: *ElfState, addresses: ?Addresses) void {
    const armed = &self.xenia_register_writes;
    armed.resolved = false;
    if (addresses) |found| {
        armed.generation = currentGeneration(self);
        if (verify(self, found)) {
            armed.addresses = found;
            armed.resolved = true;
        }
    }
    armed.stage.store(2, .release);
}

/// The proven addresses, resolving them from the image's COFF symbols the
/// first time any executor asks.
fn resolve(self: *ElfState) ?*const Addresses {
    const armed = &self.xenia_register_writes;
    while (true) {
        switch (armed.stage.load(.acquire)) {
            2 => return if (armed.resolved) &armed.addresses else null,
            1 => std.atomic.spinLoopHint(),
            else => {
                // Before the loader installs its resolver there is nothing to
                // decide yet; only an answer from it is kept.
                if (self.guest_symbol_resolver == null) return null;
                if (armed.stage.cmpxchgWeak(0, 1, .acquire, .monotonic) == null) publish(self, fromSymbols(self));
            },
        }
    }
}

/// Arm at explicit addresses (offline replays place the shipped bytes
/// elsewhere); the same byte proof applies.
pub fn armAt(self: *ElfState, addresses: Addresses) bool {
    publish(self, addresses);
    return self.xenia_register_writes.resolved;
}

/// Whether `address` is one of the three loop heads, without re-proving
/// the bytes: the block that starts there will (`gateKind`).
pub fn isGateAddress(self: *ElfState, address: u64) bool {
    if (!enabled or !self.windows_runtime_enabled or self.block_jit_verify_memory) return false;
    const addresses = resolve(self) orelse return false;
    return address == addresses.execute_packet_type0 +% type0_loop_offset or
        address == addresses.write_register_range_from_ring +% ring_loop_offset or
        address == addresses.write_registers_from_memory +% memory_loop_offset;
}

/// The gate a block starting at `rip` carries, or 0. Called when a block is
/// compiled, so the bytes are proven again for the block that will use them.
pub fn gateKind(self: *ElfState, rip: u64) u32 {
    if (!enabled or !self.windows_runtime_enabled or self.block_jit_verify_memory) return 0;
    const addresses = resolve(self) orelse return 0;
    const kind: Kind = if (rip == addresses.execute_packet_type0 +% type0_loop_offset)
        .packet_type0
    else if (rip == addresses.write_register_range_from_ring +% ring_loop_offset)
        .range_from_ring
    else if (rip == addresses.write_registers_from_memory +% memory_loop_offset)
        .from_memory
    else
        return 0;
    if (currentGeneration(self) != self.xenia_register_writes.generation or !verify(self, addresses.*)) return 0;
    return @intFromEnum(kind);
}

// -- guest memory --------------------------------------------------------------

/// Guest memory through this executor's TLB. Every page is admitted by
/// `blockJitTlbConsider`, exactly as a translated access's helper admits it,
/// and a translation is reused only while the global TLB epoch - which every
/// cross-executor invalidation moves first - stays where it was.
const Memory = struct {
    self: *ElfState,
    tlb: *Tlb,
    parallel: bool,
    epoch: u64,

    fn init(self: *ElfState) Memory {
        const parallel = self.parallel_guest_execution;
        return .{
            .self = self,
            .tlb = jit.activeBlockJitTlb(self),
            .parallel = parallel,
            .epoch = if (parallel) self.block_jit_tlb_epoch.load(.acquire) else 0,
        };
    }

    /// Whether an invalidation began since the translations were taken.
    fn moved(m: *Memory) bool {
        if (!m.parallel) return false;
        const epoch = m.self.block_jit_tlb_epoch.load(.acquire);
        if (epoch == m.epoch) return false;
        m.epoch = epoch;
        return true;
    }

    fn probe(m: *const Memory, base: u64, write: bool) ?[*]u8 {
        const tag = base >> Tlb.page_shift;
        const entry = if (write) &m.tlb.write[Tlb.index(tag)] else &m.tlb.read[Tlb.index(tag)];
        if (@atomicLoad(u64, &entry.tag, .monotonic) != tag) return null;
        return @ptrFromInt(base +% @atomicLoad(u64, &entry.delta, .monotonic));
    }

    /// The host base of the page holding a naturally aligned access.
    fn page(m: *Memory, address: u64, width: u8, write: bool) ?[*]u8 {
        if (address & (width - 1) != 0) return null;
        const base = address & ~(Tlb.page_bytes - 1);
        if (m.probe(base, write)) |translated| return translated;
        jit.blockJitTlbConsider(m.self, address, width, write);
        return m.probe(base, write);
    }

    fn host(m: *Memory, address: u64, width: u8, write: bool) ?[*]u8 {
        const base = m.page(address, width, write) orelse return null;
        return base + (address & (Tlb.page_bytes - 1));
    }
};

/// One page translation, reused while consecutive accesses stay on it.
const PageCache = struct {
    page: u64 = std.math.maxInt(u64),
    host: [*]u8 = undefined,

    inline fn get(c: *PageCache, m: *Memory, address: u64, comptime width: u8, comptime write: bool) ?[*]u8 {
        if (address & (width - 1) != 0) return null;
        const page = address & ~(Tlb.page_bytes - 1);
        if (page != c.page) return c.refill(m, address, width, write);
        return c.host + (address - page);
    }

    fn refill(c: *PageCache, m: *Memory, address: u64, width: u8, write: bool) ?[*]u8 {
        const page = address & ~(Tlb.page_bytes - 1);
        c.host = m.page(address, width, write) orelse return null;
        c.page = page;
        return c.host + (address - page);
    }
};

fn load(comptime T: type, pointer: [*]u8) T {
    return @atomicLoad(T, @as(*const T, @ptrCast(@alignCast(pointer))), .acquire);
}

fn store(comptime T: type, pointer: [*]u8, value: T) void {
    @atomicStore(T, @as(*T, @ptrCast(@alignCast(pointer))), value, .release);
}

// -- one register --------------------------------------------------------------

/// `CommandProcessor::WriteRegister`'s paths that are not the plain store:
/// above 0x5002 it logs, and these addresses tail-call
/// `HandleSpecialRegisterWrite`.
fn special(index: u32) ?Stop {
    if (index > 0x5002) return .logged_register;
    if (index & 0x7ff8 == 0x578 or index -% 0x1922 < 4 or index == 0xa31) return .special_register;
    return null;
}

/// Where `VulkanCommandProcessor::WriteRegister` clears a dirty bit after
/// the store: the 32-bit word and mask to AND, and for a fetch constant the
/// byte at +0x1798 it clears first.
const Dirty = struct {
    word: ?[*]u8 = null,
    mask: u32 = 0,
    fetch_byte: ?[*]u8 = null,
};

fn applyDirty(dirty: Dirty) void {
    if (dirty.fetch_byte) |byte| store(u8, byte, load(u8, byte) & 0xef);
    if (dirty.word) |word| store(u32, word, load(u32, word) & dirty.mask);
}

/// One iteration's dirty update, and what its path leaves in the
/// caller-saved registers it writes: only the final iteration's values
/// survive, and only when the gate runs that iteration too.
const Effects = struct {
    dirty: Dirty = .{},
    rax: u64,
    rcx: u64,
    rdx: u64 = 0,
};

/// What every iteration of one call reads through the same objects. None of
/// it is written by the loop or, while the GPU thread runs it, by anyone
/// else, so it is read once per call; the per-register words it points at
/// (usage bits, dirty word, read offset) are still read and written per
/// iteration, in the iteration's order.
const Frame = struct {
    this: u64,
    /// [this+0x38]: the register file the base `WriteRegister` stores into.
    registers: u64,
    /// [this+0xe58]: whether float-constant usage is tracked.
    tracked: bool,
    /// this+0x17c8 + 8k: the vertex (k < 4) and pixel (k >= 4) usage words.
    usage: [8][*]u8,
    /// this+0x1798, written as a word or, for fetch constants, a byte.
    dirty: [*]u8,
    /// [this+0x1450], the texture cache, and its fetch-constant word +0x8b0.
    cache: u64,
    fetch_word: ?[*]u8,
    source: PageCache = .{},
    target: PageCache = .{},

    fn resolve(m: *Memory, this: u64) ?Frame {
        var frame = Frame{
            .this = this,
            .registers = load(u64, m.host(this +% 0x38, 8, false) orelse return null),
            .tracked = load(u8, m.host(this +% 0xe58, 1, false) orelse return null) == 1,
            .usage = undefined,
            .dirty = m.host(this +% 0x1798, 4, true) orelse return null,
            .cache = load(u64, m.host(this +% 0x1450, 8, false) orelse return null),
            .fetch_word = null,
        };
        for (&frame.usage, 0..) |*word, k| word.* = m.host(this +% 0x17c8 + k * 8, 8, false) orelse return null;
        if (frame.cache != 0) frame.fetch_word = m.host(frame.cache +% 0x8b0, 4, true) orelse return null;
        return frame;
    }

    /// The usage word `btq` tests for a float constant `relative`
    /// registers past 0x4000: vertex below 0x400, pixel above.
    fn usageWord(f: *const Frame, relative: u32) u64 {
        const bit = relative >> 2;
        return load(u64, f.usage[if (relative < 0x400) relative >> 8 else 4 + ((bit -% 0x100) >> 6)]);
    }

    fn usageMask(relative: u32) u32 {
        return if (relative < 0x400) 0xfffffffd else 0xfffffffb;
    }

    fn fetchShift(register: u32) u32 {
        return (register & 0xff) * 0xab >> 10;
    }

    /// `VulkanCommandProcessor::WriteRegister`'s tail for `index`, after
    /// the base store, with rcx = this on entry.
    /// `full`: also what the path leaves in rax and rcx; only a final
    /// iteration's survive, so the others skip them.
    inline fn vulkanEffects(f: *const Frame, index: u32, comptime full: bool) Effects {
        _ = full; // inlined, the unused register values fold away
        const this = f.this;
        if (index & 0xfffff800 == 0x4000) {
            if (!f.tracked) return .{ .rax = 0x4000, .rcx = this };
            const relative = index -% 0x4000;
            const bit = relative >> 2;
            const word = f.usageWord(relative);
            if ((word >> @intCast(bit & 63)) & 1 == 0) return .{ .rax = bit, .rcx = word };
            return .{ .dirty = .{ .word = f.dirty, .mask = usageMask(relative) }, .rax = usageMask(relative), .rcx = word };
        }
        if (index -% 0x4900 <= 0x27) return .{ .dirty = .{ .word = f.dirty, .mask = 0xfffffff7 }, .rax = 0xfffffff7, .rcx = this };
        if (index -% 0x4800 <= 0xbf) {
            const word = f.fetch_word orelse return .{ .dirty = .{ .fetch_byte = f.dirty }, .rax = index -% 0x4800, .rcx = this };
            const shift = fetchShift(index);
            const mask = std.math.rotl(u32, 0xfffffffe, @as(u5, @intCast(shift & 31)));
            return .{ .dirty = .{ .fetch_byte = f.dirty, .word = word, .mask = mask }, .rax = mask, .rcx = shift };
        }
        if (index -% 0x2100 < 3 or index -% 0x2286 < 2 or index == 0x21fb) return .{ .dirty = .{ .word = f.dirty, .mask = 0xffffffbf }, .rax = 0xffffffbf, .rcx = this };
        // setae al / setne cl over the two compares, then `testb al, cl`.
        const above: u32 = @intFromBool(index -% 0x2388 >= 0x18);
        const other: u64 = @intFromBool(index != 0x2204);
        const rcx = (this & ~@as(u64, 0xff)) | other;
        if (above & other != 0) return .{ .rax = ((index -% 0x2388) & 0xffffff00) | above, .rcx = rcx };
        return .{ .dirty = .{ .word = f.dirty, .mask = 0xffffffdf }, .rax = 0xffffffdf, .rcx = rcx };
    }
};

/// The ring a loop reads its big-endian values from: the reader's read
/// offset (advanced per iteration) and capacity, its data, and the value
/// the read offset wraps to (`cmove`'s zero register).
const Ring = struct {
    offset: [*]u8,
    capacity: [*]u8,
    data: u64,
    wrap: u32,

    fn resolve(m: *Memory, reader: u64, data_field: u64, capacity_field: u64, offset_field: u64, wrap: u32) ?Ring {
        return .{
            .offset = m.host(reader +% offset_field, 4, true) orelse return null,
            .capacity = m.host(reader +% capacity_field, 4, false) orelse return null,
            .data = load(u64, m.host(reader +% data_field, 8, false) orelse return null),
            .wrap = wrap,
        };
    }
};

/// The stack slots a final iteration writes below the loop's rsp: return
/// addresses, `VulkanCommandProcessor::WriteRegister`'s pushed rsi and rdi,
/// and the base `WriteRegister`'s spill of its register number.
const Footprint = struct {
    slots: [4]?[*]u8 = @splat(null),
    values: [4]u64 = @splat(0),
    spill: [*]u8 = undefined,
    count: usize = 0,

    fn slot(f: *Footprint, m: *Memory, address: u64, value: u64) bool {
        f.slots[f.count] = m.host(address, 8, true) orelse return false;
        f.values[f.count] = value;
        f.count += 1;
        return true;
    }

    fn write(f: *const Footprint, index: u32) void {
        for (f.slots[0..f.count], f.values[0..f.count]) |pointer, value| store(u64, pointer.?, value);
        store(u32, f.spill, index);
    }
};

/// One ring iteration: advance the read offset, read the big-endian word,
/// store the register, clear its dirty bit. Every page is proven before
/// the first store; a null return has written nothing. `footprint`, for
/// the final iteration, is proven first and written in program order.
inline fn ringRegister(comptime final: bool, m: *Memory, frame: *Frame, ring: *const Ring, index: u32, footprint: *const Footprint, last: *Last) ?Stop {
    if (special(index)) |stop| return stop;
    const read_offset = load(u32, ring.offset);
    const source = frame.source.get(m, ring.data +% read_offset, 4, false) orelse return .unadmitted_page;
    const target = frame.target.get(m, frame.registers +% @as(u64, index) * 4, 4, true) orelse return .unadmitted_page;
    const effects = frame.vulkanEffects(index, final);
    const next = read_offset +% 4;
    store(u32, ring.offset, if (next == load(u32, ring.capacity)) ring.wrap else next);
    const value = @byteSwap(load(u32, source));
    if (final) footprint.write(index);
    store(u32, target, value);
    applyDirty(effects.dirty);
    if (final) last.* = .{ .value = value, .effects = effects };
    return null;
}

const Last = struct { value: u32 = 0, effects: Effects = .{ .rax = 0, .rcx = 0 } };

/// `[this]` must still dispatch `WriteRegister` to the proven Vulkan body.
fn virtualTargetMatches(m: *Memory, this: u64, addresses: *const Addresses) bool {
    const vtable = load(u64, m.host(this, 8, false) orelse return false);
    const slot = m.host(vtable +% 0x70, 8, false) orelse return false;
    return load(u64, slot) == addresses.vulkan_write_register;
}

// -- the gate ------------------------------------------------------------------

/// Where `ExecutePacketType0`'s and `WriteRegisterRangeFromRing`'s virtual
/// calls return to and where their loops exit, and the same for
/// `WriteRegistersFromMem`'s base call.
pub const type0_return_offset: u64 = 0x77;
pub const type0_exit_offset: u64 = 0x7d;
pub const ring_return_offset: u64 = 0x44;
pub const ring_exit_offset: u64 = 0x4a;
pub const memory_return_offset: u64 = 0x86;
pub const memory_exit_offset: u64 = 0x1c4;
/// The base call's return inside `VulkanCommandProcessor::WriteRegister`.
pub const vulkan_return_offset: u64 = 0x10;

const Outcome = union(enum) { stay, exited, stopped: Stop };

/// Called by a gated block before its register cache is loaded, with the
/// register file current. Returns 1 when the gate ran the loop to its exit
/// and left RIP there: the block then leaves without running its code.
/// Otherwise the block's own code runs the remaining iterations.
pub fn entryGate(state_ptr: *anyopaque, kind_value: u32) callconv(.c) u32 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    if (kind_value == 0 or kind_value > 3) return 0;
    const kind: Kind = @enumFromInt(kind_value);
    note(&counters.gate_calls[kind_value], 1);
    switch (run(self, kind)) {
        .stay => return 0,
        .exited => {
            note(&counters.loop_exits, 1);
            return 1;
        },
        .stopped => |stop| {
            note(&counters.stops[@intFromEnum(stop)], 1);
            return 0;
        },
    }
}

fn run(self: *ElfState, kind: Kind) Outcome {
    if (!enabled) return .stay;
    const armed = &self.xenia_register_writes;
    if (armed.stage.load(.acquire) != 2 or !armed.resolved) return .{ .stopped = .invariant };
    if (currentGeneration(self) != armed.generation) return .{ .stopped = .image_changed };
    if (jit.activeGuestTsoStoreBuffer(self)) |buffer| if (!buffer.isEmpty()) return .{ .stopped = .store_queue };
    const regs = life.guestContextField(self, "regs");
    var m = Memory.init(self);
    var done: u32 = 0;
    // The base WriteRegister leaves its register file in r9, and a final
    // iteration that logs instead of storing does not load it again: an
    // iteration run here must leave r9 as that iteration would have.
    var file: u64 = 0;
    defer {
        if (done != 0) regs.r9 = file;
        note(&counters.registers[@intFromEnum(kind)], done);
    }
    const a = &armed.addresses;
    switch (kind) {
        .none => return .stay,
        // rdi = this, ebx = register, esi = iterations left (this one
        // included), r15d = the wrap value `cmove` takes; the reader is
        // `this` itself (data +8, capacity +0x10, read offset +0x14).
        // rbx = the RingBuffer (data +0, capacity +8, read offset +0xc),
        // r14 = this, edi = register, esi = iterations left, ebp = wrap.
        .packet_type0, .range_from_ring => {
            const type0 = kind == .packet_type0;
            const left: u32 = @truncate(regs.rsi);
            if (left == 0) return .stay;
            const this = if (type0) regs.rdi else regs.r14;
            if (!virtualTargetMatches(&m, this, a)) return .{ .stopped = .virtual_target };
            var frame = Frame.resolve(&m, this) orelse return .{ .stopped = .unadmitted_page };
            var ring = (if (type0) Ring.resolve(&m, this, 0x8, 0x10, 0x14, @truncate(regs.r15)) else Ring.resolve(&m, regs.rbx, 0x0, 0x8, 0xc, @truncate(regs.rbp))) orelse return .{ .stopped = .unadmitted_page };
            file = frame.registers;
            var last: Last = .{};
            var footprint: Footprint = .{};
            // The loop's register (ebx or edi) and count (esi) as each
            // iteration leaves them, published to the register file on
            // every way out: the next iteration's loop-head state.
            var index: u32 = @truncate(if (type0) regs.rbx else regs.rdi);
            defer {
                if (type0) regs.rbx = index else regs.rdi = index;
                regs.rsi = left - done;
            }
            while (true) : (done += 1) {
                if (m.moved()) {
                    frame = Frame.resolve(&m, this) orelse return .{ .stopped = .unadmitted_page };
                    ring = (if (type0) Ring.resolve(&m, this, 0x8, 0x10, 0x14, ring.wrap) else Ring.resolve(&m, regs.rbx, 0x0, 0x8, 0xc, ring.wrap)) orelse return .{ .stopped = .unadmitted_page };
                }
                if (done + 1 == left) {
                    // The final iteration. call [vtable+0x70]: its return
                    // address; the Vulkan body's push rsi and push rdi; its
                    // own call's return; the base body's spill at its
                    // rsp+0x24. All proven before the first store.
                    const rsp = regs.rsp;
                    const own_return = if (type0) a.execute_packet_type0 +% type0_return_offset else a.write_register_range_from_ring +% ring_return_offset;
                    if (!footprint.slot(&m, rsp -% 8, own_return) or !footprint.slot(&m, rsp -% 16, left - done) or
                        !footprint.slot(&m, rsp -% 24, if (type0) regs.rdi else index) or !footprint.slot(&m, rsp -% 0x48, a.vulkan_write_register +% vulkan_return_offset))
                        return .{ .stopped = .unadmitted_page };
                    footprint.spill = m.host(rsp -% 0x5c, 4, true) orelse return .{ .stopped = .unadmitted_page };
                    if (ringRegister(true, &m, &frame, &ring, index, &footprint, &last)) |stop| return .{ .stopped = stop };
                    regs.rax = last.effects.rax;
                    regs.rcx = last.effects.rcx;
                    regs.rdx = index;
                    regs.r8 = last.value;
                    index +%= 1;
                    regs.rip = if (type0) a.execute_packet_type0 +% type0_exit_offset else a.write_register_range_from_ring +% ring_exit_offset;
                    done += 1;
                    return .exited;
                }
                if (ringRegister(false, &m, &frame, &ring, index, &footprint, &last)) |stop| return .{ .stopped = stop };
                index +%= 1;
            }
        },
        // rsi = source words, rbp = i, r12 = count, r13 = first register,
        // rbx = this, r15 = this + 0x1798; the base-relative constants at
        // [rsp+0x20], [rsp+0x28] and [rsp+0x30] and edi = first - 0x4900
        // are the prologue's.
        .from_memory => {
            if (regs.r12 <= regs.rbp) return .stay;
            const this = regs.rbx;
            if (regs.r15 != this +% 0x1798) return .{ .stopped = .invariant };
            var frame = Frame.resolve(&m, this) orelse return .{ .stopped = .unadmitted_page };
            var constants = Constants.resolve(&m, regs.rsp) orelse return .{ .stopped = .unadmitted_page };
            file = frame.registers;
            var last: Last = .{};
            var footprint: Footprint = .{};
            while (true) : (done += 1) {
                if (m.moved()) {
                    frame = Frame.resolve(&m, this) orelse return .{ .stopped = .unadmitted_page };
                    constants = Constants.resolve(&m, regs.rsp) orelse return .{ .stopped = .unadmitted_page };
                }
                if (regs.rbp + 1 == regs.r12) {
                    // The final iteration. call base: its return address,
                    // and the base body's spill at its rsp+0x24.
                    if (!footprint.slot(&m, regs.rsp -% 8, a.write_registers_from_memory +% memory_return_offset)) return .{ .stopped = .unadmitted_page };
                    footprint.spill = m.host(regs.rsp -% 0x1c, 4, true) orelse return .{ .stopped = .unadmitted_page };
                    if (memoryRegister(true, &m, &frame, &constants, regs, &footprint, &last)) |stop| return .{ .stopped = stop };
                    regs.rax = last.effects.rax;
                    regs.rcx = last.effects.rcx;
                    regs.rdx = last.effects.rdx;
                    regs.r8 = last.value;
                    regs.r14 = regs.r13 +% regs.rbp;
                    regs.rbp += 1;
                    regs.rip = a.write_registers_from_memory +% memory_exit_offset;
                    done += 1;
                    return .exited;
                }
                if (memoryRegister(false, &m, &frame, &constants, regs, &footprint, &last)) |stop| return .{ .stopped = stop };
                regs.rbp += 1;
            }
        },
    }
}

/// `WriteRegistersFromMem`'s prologue constants on its stack: register base
/// minus 0x2388 at +0x20, minus 0x4800 at +0x28 and minus 0x4000 at +0x30.
const Constants = struct {
    minus_2388: u64,
    minus_4800: u64,
    minus_4000: u64,

    fn resolve(m: *Memory, rsp: u64) ?Constants {
        return .{
            .minus_2388 = load(u64, m.host(rsp +% 0x20, 8, false) orelse return null),
            .minus_4800 = load(u64, m.host(rsp +% 0x28, 8, false) orelse return null),
            .minus_4000 = load(u64, m.host(rsp +% 0x30, 8, false) orelse return null),
        };
    }
};

/// One iteration of `WriteRegistersFromMem` at its loop top.
inline fn memoryRegister(comptime final: bool, m: *Memory, frame: *Frame, constants: *const Constants, regs: anytype, footprint: *const Footprint, last: *Last) ?Stop {
    const i = regs.rbp;
    const index: u32 = @truncate(regs.r13 +% i);
    if (special(index)) |stop| return stop;
    const source = frame.source.get(m, regs.rsi +% i * 4, 4, false) orelse return .unadmitted_page;
    const target = frame.target.get(m, frame.registers +% @as(u64, index) * 4, 4, true) orelse return .unadmitted_page;
    const effects = memoryEffects(frame, constants, regs, index, final);
    const value = @byteSwap(load(u32, source));
    if (final) footprint.write(index);
    store(u32, target, value);
    applyDirty(effects.dirty);
    if (final) last.* = .{ .value = value, .effects = effects };
    return null;
}

/// `WriteRegistersFromMem`'s own inlined dirty logic after its base call:
/// the same masks as the Vulkan tail, reached through its precomputed
/// stack constants and edi, with rcx = this and rdx = the register on
/// entry and r15 = this + 0x1798.
inline fn memoryEffects(frame: *const Frame, constants: *const Constants, regs: anytype, index: u32, comptime full: bool) Effects {
    _ = full; // inlined, the unused register values fold away
    const i = regs.rbp;
    const ebp: u32 = @truncate(i);
    const word = regs.r15;
    if (index & 0xfffff800 == 0x4000) {
        if (!frame.tracked) return .{ .rax = 0x4000, .rcx = frame.this, .rdx = index };
        const relative: u32 = @truncate(constants.minus_4000 +% i);
        const bit = relative >> 2;
        const mask = Frame.usageMask(relative);
        const set = (frame.usageWord(relative) >> @intCast(bit & 63)) & 1 != 0;
        return .{ .dirty = if (set) .{ .word = frame.dirty, .mask = mask } else .{}, .rax = mask, .rcx = bit, .rdx = word };
    }
    const bools: u32 = @as(u32, @truncate(regs.rdi)) +% ebp;
    if (bools < 0x28) return .{ .dirty = .{ .word = frame.dirty, .mask = 0xfffffff7 }, .rax = 0xfffffff7, .rcx = bools, .rdx = word };
    const fetch: u32 = @as(u32, @truncate(constants.minus_4800)) +% ebp;
    if (fetch <= 0xbf) {
        const cache_word = frame.fetch_word orelse return .{ .dirty = .{ .fetch_byte = frame.dirty }, .rax = fetch, .rcx = bools, .rdx = 0 };
        const shift = Frame.fetchShift(@truncate(regs.r13 +% i));
        const mask = std.math.rotl(u32, 0xfffffffe, @as(u5, @intCast(shift & 31)));
        return .{ .dirty = .{ .fetch_byte = frame.dirty, .word = cache_word, .mask = mask }, .rax = mask, .rcx = shift, .rdx = frame.cache +% 0x8b0 };
    }
    if (index -% 0x2100 < 3) return .{ .dirty = .{ .word = frame.dirty, .mask = 0xffffffbf }, .rax = 0xffffffbf, .rcx = index -% 0x2100, .rdx = word };
    if (index -% 0x2286 < 2 or index == 0x21fb) return .{ .dirty = .{ .word = frame.dirty, .mask = 0xffffffbf }, .rax = 0xffffffbf, .rcx = index -% 0x2286, .rdx = word };
    const at_2204 = i -% 0x2204 +% regs.r13;
    if (@as(u32, @truncate(at_2204)) == 0) return .{ .dirty = .{ .word = frame.dirty, .mask = 0xffffffdf }, .rax = 0xffffffdf, .rcx = at_2204, .rdx = word };
    const range: u32 = @as(u32, @truncate(constants.minus_2388)) +% ebp;
    return .{ .dirty = if (range > 0x17) .{} else .{ .word = frame.dirty, .mask = 0xffffffdf }, .rax = 0xffffffdf, .rcx = range, .rdx = word };
}

// -- report --------------------------------------------------------------------

var last_pulse_ns = std.atomic.Value(u64).init(0);

/// Cumulative counts once per five seconds from whichever worker reaches
/// its progress boundary first, so a run's report windows can be
/// differenced into registers per presented frame.
pub fn pulse(now: u64) void {
    const last = last_pulse_ns.load(.monotonic);
    if (last != 0 and now -% last < 5 * std.time.ns_per_s) return;
    if (last_pulse_ns.cmpxchgStrong(last, now, .monotonic, .monotonic) != null) return;
    const c = &counters;
    const calls = c.gate_calls[1].load(.monotonic) + c.gate_calls[2].load(.monotonic) + c.gate_calls[3].load(.monotonic);
    if (last == 0 or calls == 0) return;
    std.log.info("PE64 XENIA REGISTER WRITES PULSE: native_registers(type0/ring/memory)={d}/{d}/{d} gate_calls={d} loop_exits={d}; cumulative, for differencing against the five-second graphics windows; counts, not saved time", .{
        c.registers[1].load(.monotonic), c.registers[2].load(.monotonic), c.registers[3].load(.monotonic), calls, c.loop_exits.load(.monotonic),
    });
}

pub fn report(self: *const ElfState) void {
    if (comptime @import("builtin").is_test) return;
    const armed = &self.xenia_register_writes;
    if (armed.stage.load(.acquire) != 2) return;
    const c = &counters;
    const v = struct {
        fn of(value: *const std.atomic.Value(u64)) u64 {
            return value.load(.monotonic);
        }
    }.of;
    std.log.info("PE64 XENIA REGISTER WRITES: armed={} gates(type0/ring/memory)={d}/{d}/{d} loop_exits={d} native_registers(type0/ring/memory)={d}/{d}/{d} stops(special/logged/unadmitted/misaligned/virtual/invariant/image/store_queue)={d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}; loop iterations run natively at verified loop heads, leaving the guest's own registers, stack slots and loop exit; every stop leaves its iteration to Xenia's code; counts, not saved time", .{
        armed.resolved,
        v(&c.gate_calls[1]),
        v(&c.gate_calls[2]),
        v(&c.gate_calls[3]),
        v(&c.loop_exits),
        v(&c.registers[1]),
        v(&c.registers[2]),
        v(&c.registers[3]),
        v(&c.stops[0]),
        v(&c.stops[1]),
        v(&c.stops[2]),
        v(&c.stops[3]),
        v(&c.stops[4]),
        v(&c.stops[5]),
        v(&c.stops[6]),
        v(&c.stops[7]),
    });
}
