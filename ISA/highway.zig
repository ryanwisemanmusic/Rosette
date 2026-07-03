const std = @import("std");

pub const Width = enum(u8) {
    bits8 = 8,
    bits16 = 16,
    bits32 = 32,
    bits64 = 64,

    pub fn bits(self: Width) u8 {
        return @intFromEnum(self);
    }
};

const FlagValue = enum { clear, set, preserve, undefined };
const Flags = struct {
    cf: FlagValue = .preserve,
    pf: FlagValue = .preserve,
    af: FlagValue = .preserve,
    zf: FlagValue = .preserve,
    sf: FlagValue = .preserve,
    of: FlagValue = .preserve,
};
const IntegerResult = struct { dest: u64, flags: Flags };

pub const Backend = enum {
    elf64,
    macho64,
    pe32,
    cs218,
};

pub const Family = enum {
    scalar_integer,
    scalar_memory,
    control_flow,
    memory,
    simd,
    system,
};

pub const Route = enum {
    shared,
    adapter,
    pending,
};

pub const Capability = struct {
    decode: Route,
    execute: Route,
};

pub const BinaryOp = enum {
    add,
    adc,
    sub,
    sbb,
    bit_and,
    bit_or,
    bit_xor,
    cmp,
    test_bits,
};

pub const LegacyDirection = enum { rm_destination, register_destination };

pub const LegacyBinaryEncoding = struct {
    op: BinaryOp,
    direction: LegacyDirection,
    byte_width: bool,
};

pub const Group1Encoding = struct {
    op: BinaryOp,
    writes_result: bool,
};

pub fn classifyLegacyBinaryOpcode(opcode: u8) ?LegacyBinaryEncoding {
    const family: BinaryOp = switch (opcode & 0xF8) {
        0x00 => .add,
        0x08 => .bit_or,
        0x10 => .adc,
        0x18 => .sbb,
        0x20 => .bit_and,
        0x28 => .sub,
        0x30 => .bit_xor,
        0x38 => .cmp,
        else => return null,
    };
    return .{
        .op = family,
        .direction = if ((opcode & 0x02) != 0) .register_destination else .rm_destination,
        .byte_width = (opcode & 0x01) == 0,
    };
}

pub fn classifyGroup1(extension: u3) Group1Encoding {
    return switch (extension) {
        0 => .{ .op = .add, .writes_result = true },
        1 => .{ .op = .bit_or, .writes_result = true },
        2 => .{ .op = .adc, .writes_result = true },
        3 => .{ .op = .sbb, .writes_result = true },
        4 => .{ .op = .bit_and, .writes_result = true },
        5 => .{ .op = .sub, .writes_result = true },
        6 => .{ .op = .bit_xor, .writes_result = true },
        7 => .{ .op = .cmp, .writes_result = false },
    };
}

pub const Result = struct {
    value: u64,
    rflags: u32,
    writeback: bool,
};

pub const MemoryDirection = enum {
    memory_to_register,
    register_to_memory,
};

pub const MemoryResult = struct {
    value: u64,
    rflags: u32,
    write_register: bool,
    write_memory: bool,
};

pub fn capability(backend: Backend, family: Family) Capability {
    return switch (family) {
        .scalar_integer => .{ .decode = .adapter, .execute = .shared },
        .scalar_memory => .{ .decode = .adapter, .execute = .shared },
        .control_flow, .memory => .{ .decode = .adapter, .execute = .adapter },
        .simd => switch (backend) {
            .elf64, .macho64 => .{ .decode = .adapter, .execute = .adapter },
            .pe32, .cs218 => .{ .decode = .pending, .execute = .pending },
        },
        .system => switch (backend) {
            .elf64, .macho64 => .{ .decode = .adapter, .execute = .adapter },
            .pe32 => .{ .decode = .adapter, .execute = .adapter },
            .cs218 => .{ .decode = .pending, .execute = .pending },
        },
    };
}

pub fn evaluateMemory(
    op: BinaryOp,
    width: Width,
    register_value: u64,
    memory_value: u64,
    direction: MemoryDirection,
    rflags: u32,
) MemoryResult {
    const evaluated = switch (direction) {
        .memory_to_register => evaluate(op, width, register_value, memory_value, rflags),
        .register_to_memory => evaluate(op, width, memory_value, register_value, rflags),
    };
    return .{
        .value = evaluated.value,
        .rflags = evaluated.rflags,
        .write_register = evaluated.writeback and direction == .memory_to_register,
        .write_memory = evaluated.writeback and direction == .register_to_memory,
    };
}

pub fn evaluate(op: BinaryOp, width: Width, lhs: u64, rhs: u64, rflags: u32) Result {
    const borrow = (rflags & 1) != 0;
    const evaluated = switch (op) {
        .add => addCarry(width, lhs, rhs, false),
        .adc => addCarry(width, lhs, rhs, borrow),
        .sub, .cmp => subBorrow(width, lhs, rhs, false),
        .sbb => subBorrow(width, lhs, rhs, borrow),
        .bit_and => logical(width, lhs & rhs),
        .bit_or => logical(width, lhs | rhs),
        .bit_xor => logical(width, lhs ^ rhs),
        .test_bits => logical(width, lhs & rhs),
    };
    return .{
        .value = evaluated.dest,
        .rflags = applyFlags(rflags, evaluated.flags),
        .writeback = op != .cmp and op != .test_bits,
    };
}

pub const MemoryAccess = enum { read, write, execute, atomic_read_modify_write };
pub const MemoryFault = enum { unmapped, permission_denied, address_overflow, unaligned_atomic, backend_rejected };

pub const MemoryCheck = struct {
    address: u64,
    bytes: u8,
    access: MemoryAccess,
    fault: ?MemoryFault = null,

    pub fn allowed(self: MemoryCheck) bool {
        return self.fault == null;
    }
};

pub const AtomicOrder = enum { unordered, acquire, release, acquire_release, sequential };

pub const AtomicTransaction = struct {
    address: u64,
    width: Width,
    order: AtomicOrder,
    locked: bool,
    before: u64,
    after: u64,
    committed: bool,
};

pub fn validateAtomic(address: u64, width: Width, locked: bool) MemoryCheck {
    const bytes: u8 = width.bits() / 8;
    return .{
        .address = address,
        .bytes = bytes,
        .access = if (locked) .atomic_read_modify_write else .write,
        .fault = null,
    };
}

pub fn validateRange(base: u64, length: usize, address: u64, width: Width, access: MemoryAccess, permitted: bool) MemoryCheck {
    const bytes: u8 = width.bits() / 8;
    const relative = address -| base;
    const outside = address < base or relative > length or bytes > length -| @as(usize, @intCast(relative));
    return .{
        .address = address,
        .bytes = bytes,
        .access = access,
        .fault = if (outside) .unmapped else if (!permitted) .permission_denied else null,
    };
}

pub const ControlKind = enum { jump, call, return_from_call, conditional_jump };
pub const ControlTransfer = struct {
    kind: ControlKind,
    source: u64,
    target: u64,
    return_address: ?u64 = null,
    taken: bool = true,
};

pub fn relativeControl(kind: ControlKind, source: u64, length: u8, displacement: i64, taken: bool) ControlTransfer {
    const next = source +% length;
    return .{
        .kind = kind,
        .source = source,
        .target = if (taken) next +% @as(u64, @bitCast(displacement)) else next,
        .return_address = if (kind == .call) next else null,
        .taken = taken,
    };
}

pub fn directControl(kind: ControlKind, source: u64, length: u8, target: u64, taken: bool) ControlTransfer {
    const next = source +% length;
    return .{
        .kind = kind,
        .source = source,
        .target = if (taken) target else next,
        .return_address = if (kind == .call) next else null,
        .taken = taken,
    };
}

pub const SystemDomain = enum { syscall, import, privileged, exception, process_exit };
pub const SystemDisposition = enum { forward, emulate, deny, diagnostic_stop };
pub const SystemBoundary = struct {
    domain: SystemDomain,
    number: u64 = 0,
    symbol: []const u8 = "",
    disposition: SystemDisposition,
};

pub fn systemBoundary(backend: Backend, domain: SystemDomain, number: u64, symbol: []const u8) SystemBoundary {
    const disposition: SystemDisposition = switch (domain) {
        .syscall => if (backend == .pe32) .emulate else .forward,
        .import => .forward,
        .privileged => .deny,
        .exception => .emulate,
        .process_exit => .emulate,
    };
    return .{ .domain = domain, .number = number, .symbol = symbol, .disposition = disposition };
}

pub const SimdProvider = enum { cleo, native_adapter, pending };
pub const SimdRequest = struct {
    mnemonic: []const u8,
    vector_bits: u16,
    element_bits: u8,
};

pub fn simdProvider(backend: Backend, request: SimdRequest) SimdProvider {
    if (request.vector_bits > 512 or request.element_bits == 0) return .pending;
    return switch (backend) {
        .elf64, .macho64, .pe32 => .cleo,
        .cs218 => .native_adapter,
    };
}

pub fn widthFromBits(bits: u8) ?Width {
    return switch (bits) {
        8 => .bits8,
        16 => .bits16,
        32 => .bits32,
        64 => .bits64,
        else => null,
    };
}

fn boolFlag(value: bool) FlagValue {
    return if (value) .set else .clear;
}

fn widthMask(width: Width) u64 {
    return if (width == .bits64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(width.bits())) - 1;
}

fn truncate(width: Width, value: u128) u64 {
    return @truncate(value & widthMask(width));
}

fn signMask(width: Width) u64 {
    return @as(u64, 1) << @intCast(width.bits() - 1);
}

fn sizeParityFlags(width: Width, value: u64) Flags {
    return .{
        .sf = boolFlag((value & signMask(width)) != 0),
        .zf = boolFlag(value == 0),
        .pf = boolFlag(@popCount(@as(u8, @truncate(value))) % 2 == 0),
    };
}

fn addCarry(width: Width, lhs: u64, rhs: u64, carry: bool) IntegerResult {
    const lhs_t = lhs & widthMask(width);
    const rhs_t = rhs & widthMask(width);
    const wide = @as(u128, lhs_t) + @as(u128, rhs_t) + @intFromBool(carry);
    const value = truncate(width, wide);
    var flags = sizeParityFlags(width, value);
    flags.cf = boolFlag(wide > widthMask(width));
    flags.af = boolFlag(((lhs_t ^ rhs_t ^ value) & 0x10) != 0);
    flags.of = boolFlag((~(lhs_t ^ rhs_t) & (lhs_t ^ value) & signMask(width)) != 0);
    return .{ .dest = value, .flags = flags };
}

fn subBorrow(width: Width, lhs: u64, rhs: u64, borrow: bool) IntegerResult {
    const mask = widthMask(width);
    const lhs_t = lhs & mask;
    const rhs_t = rhs & mask;
    const subtrahend = @as(u128, rhs_t) + @intFromBool(borrow);
    const value: u64 = @truncate((@as(u128, lhs_t) -% subtrahend) & mask);
    var flags = sizeParityFlags(width, value);
    flags.cf = boolFlag(@as(u128, lhs_t) < subtrahend);
    flags.af = boolFlag(((lhs_t ^ rhs_t ^ value) & 0x10) != 0);
    flags.of = boolFlag(((lhs_t ^ rhs_t) & (lhs_t ^ value) & signMask(width)) != 0);
    return .{ .dest = value, .flags = flags };
}

fn logical(width: Width, wide: u64) IntegerResult {
    const value = wide & widthMask(width);
    var flags = sizeParityFlags(width, value);
    flags.cf = .clear;
    flags.of = .clear;
    flags.af = .undefined;
    return .{ .dest = value, .flags = flags };
}

fn applyFlags(initial: u32, flags: Flags) u32 {
    var result = initial;
    applyFlag(&result, 1 << 0, flags.cf);
    applyFlag(&result, 1 << 2, flags.pf);
    applyFlag(&result, 1 << 4, flags.af);
    applyFlag(&result, 1 << 6, flags.zf);
    applyFlag(&result, 1 << 7, flags.sf);
    applyFlag(&result, 1 << 11, flags.of);
    return result;
}

fn applyFlag(rflags: *u32, mask: u32, value: FlagValue) void {
    switch (value) {
        .set => rflags.* |= mask,
        .clear => rflags.* &= ~mask,
        .preserve, .undefined => {},
    }
}

test "all runtime backends share scalar register and memory execution" {
    inline for (std.meta.tags(Backend)) |backend| {
        inline for (.{ Family.scalar_integer, Family.scalar_memory }) |family| {
            const support = capability(backend, family);
            try std.testing.expectEqual(Route.shared, support.execute);
            try std.testing.expect(support.decode != .pending);
        }
    }
}

test "binary highway preserves control flags and provides complete arithmetic flags" {
    const control_flags: u32 = (1 << 9) | (1 << 10);
    const result = evaluate(.add, .bits8, 0xFF, 1, control_flags);
    try std.testing.expectEqual(@as(u64, 0), result.value);
    try std.testing.expect((result.rflags & (1 << 0)) != 0);
    try std.testing.expect((result.rflags & (1 << 6)) != 0);
    try std.testing.expectEqual(control_flags, result.rflags & control_flags);
}

test "SBB mask idiom uses incoming carry" {
    const clear = evaluate(.sbb, .bits32, 0, 0, 0);
    try std.testing.expectEqual(@as(u64, 0), clear.value);
    const set = evaluate(.sbb, .bits32, 0, 0, 1);
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFF), set.value);
    try std.testing.expect((set.rflags & 1) != 0);
}

test "memory transaction contract keeps operand direction and compare read-only" {
    const load = evaluateMemory(.sub, .bits32, 10, 3, .memory_to_register, 0);
    try std.testing.expectEqual(@as(u64, 7), load.value);
    try std.testing.expect(load.write_register);
    try std.testing.expect(!load.write_memory);

    const store = evaluateMemory(.sub, .bits32, 3, 10, .register_to_memory, 0);
    try std.testing.expectEqual(@as(u64, 7), store.value);
    try std.testing.expect(!store.write_register);
    try std.testing.expect(store.write_memory);

    const compare = evaluateMemory(.cmp, .bits32, 3, 10, .register_to_memory, 0);
    try std.testing.expect(!compare.write_register);
    try std.testing.expect(!compare.write_memory);
}

test "legacy decoder classification is shared across binary and Group1 forms" {
    const sbb = classifyLegacyBinaryOpcode(0x19).?;
    try std.testing.expectEqual(BinaryOp.sbb, sbb.op);
    try std.testing.expectEqual(LegacyDirection.rm_destination, sbb.direction);
    try std.testing.expect(!sbb.byte_width);
    try std.testing.expectEqual(BinaryOp.cmp, classifyGroup1(7).op);
    try std.testing.expect(!classifyGroup1(7).writes_result);
}

test "control, atomic, SIMD, and system boundaries are explicit" {
    const call = relativeControl(.call, 0x1000, 5, 0x20, true);
    try std.testing.expectEqual(@as(u64, 0x1025), call.target);
    try std.testing.expectEqual(@as(u64, 0x1005), call.return_address.?);
    try std.testing.expectEqual(@as(u64, 0x2020), directControl(.conditional_jump, 0x2000, 2, 0x2020, true).target);
    const locked = validateAtomic(3, .bits32, true);
    try std.testing.expect(locked.allowed());
    try std.testing.expectEqual(MemoryAccess.atomic_read_modify_write, locked.access);
    try std.testing.expectEqual(MemoryFault.unmapped, validateRange(0x1000, 16, 0x1010, .bits32, .read, true).fault.?);
    try std.testing.expectEqual(SimdProvider.cleo, simdProvider(.macho64, .{ .mnemonic = "VADDPS", .vector_bits = 256, .element_bits = 32 }));
    try std.testing.expectEqual(SystemDisposition.deny, systemBoundary(.elf64, .privileged, 0, "HLT").disposition);
}
