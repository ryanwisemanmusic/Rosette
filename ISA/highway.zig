const std = @import("std");
const math = @import("Math/core.zig");

pub const Width = math.Width;

pub const Backend = enum {
    elf64,
    macho64,
    pe32,
    cs218,
};

pub const Family = enum {
    scalar_integer,
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
    sub,
    sbb,
    bit_and,
    bit_or,
    bit_xor,
    cmp,
    test_bits,
};

pub const Result = struct {
    value: u64,
    rflags: u32,
    writeback: bool,
};

pub fn capability(backend: Backend, family: Family) Capability {
    return switch (family) {
        .scalar_integer => .{ .decode = .adapter, .execute = .shared },
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

pub fn evaluate(op: BinaryOp, width: Width, lhs: u64, rhs: u64, rflags: u32) Result {
    const borrow = (rflags & 1) != 0;
    const evaluated = switch (op) {
        .add => math.add(width, lhs, rhs),
        .sub, .cmp => math.sub(width, lhs, rhs),
        .sbb => math.sbb(width, lhs, rhs, borrow),
        .bit_and => math.bitAnd(width, lhs, rhs),
        .bit_or => math.bitOr(width, lhs, rhs),
        .bit_xor => math.bitXor(width, lhs, rhs),
        .test_bits => math.testBits(width, lhs, rhs),
    };
    return .{
        .value = evaluated.dest,
        .rflags = applyFlags(rflags, evaluated.flags),
        .writeback = op != .cmp and op != .test_bits,
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

fn applyFlags(initial: u32, flags: math.Flags) u32 {
    var result = initial;
    applyFlag(&result, 1 << 0, flags.cf);
    applyFlag(&result, 1 << 2, flags.pf);
    applyFlag(&result, 1 << 4, flags.af);
    applyFlag(&result, 1 << 6, flags.zf);
    applyFlag(&result, 1 << 7, flags.sf);
    applyFlag(&result, 1 << 11, flags.of);
    return result;
}

fn applyFlag(rflags: *u32, mask: u32, value: math.FlagValue) void {
    switch (value) {
        .set => rflags.* |= mask,
        .clear => rflags.* &= ~mask,
        .preserve, .undefined => {},
    }
}

test "all runtime backends share scalar integer execution" {
    inline for (std.meta.tags(Backend)) |backend| {
        const support = capability(backend, .scalar_integer);
        try std.testing.expectEqual(Route.shared, support.execute);
        try std.testing.expect(support.decode != .pending);
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
