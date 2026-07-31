const std = @import("std");
const flags = @import("flags");

pub const OperandSize = flags.OperandSize;

pub const Operation = enum {
    probe,
    set,
    reset,
    complement,
};

pub const RegisterResult = struct {
    value: u64,
    carry: bool,
    bit_index: u6,
};

pub const MemoryOperand = struct {
    address: u64,
    bit_index: u6,
};

pub fn operandBitWidth(size: OperandSize) u7 {
    return switch (size) {
        .bits8 => 8,
        .bits16 => 16,
        .bits32 => 32,
        .bits64 => 64,
    };
}

/// Implements the architectural register/immediate forms of BT/BTS/BTR/BTC.
/// The source index is reduced modulo the *bit width* of the destination, not
/// the ordinal of the OperandSize enum.
pub fn applyRegister(size: OperandSize, value: u64, raw_index: u64, operation: Operation) RegisterResult {
    const width = operandBitWidth(size);
    const bit_index: u6 = @intCast(raw_index & (width - 1));
    const mask = @as(u64, 1) << bit_index;
    return .{
        .value = switch (operation) {
            .probe => value,
            .set => value | mask,
            .reset => value & ~mask,
            .complement => value ^ mask,
        },
        .carry = value & mask != 0,
        .bit_index = bit_index,
    };
}

pub fn resetRegister(size: OperandSize, value: u64, raw_index: u64) RegisterResult {
    return applyRegister(size, value, raw_index, .reset);
}

/// Resolves the architectural memory form of BTR. Unlike the register form,
/// high source-index bits select a preceding or following storage element.
pub fn memoryOperand(size: OperandSize, base_address: u64, raw_index: u64) ?MemoryOperand {
    if (size == .bits8) return null;
    const width: i64 = operandBitWidth(size);
    const byte_width = @divExact(width, 8);
    const signed_index: i64 = switch (size) {
        .bits16 => @as(i16, @bitCast(@as(u16, @truncate(raw_index)))),
        .bits32 => @as(i32, @bitCast(@as(u32, @truncate(raw_index)))),
        .bits64 => @bitCast(raw_index),
        .bits8 => unreachable,
    };
    const element_offset = @divFloor(signed_index, width);
    return .{
        .address = base_address +% @as(u64, @bitCast(element_offset * byte_width)),
        .bit_index = @intCast(@mod(signed_index, width)),
    };
}

/// Immediate bit offsets select a bit in the addressed storage element. The
/// assembler may fold high immediate bits into the effective-address
/// displacement, so the processor masks the encoded immediate to the operand
/// width rather than treating it as a signed register bit-string index.
pub fn memoryOperandImmediate(size: OperandSize, base_address: u64, raw_index: u64) ?MemoryOperand {
    if (size == .bits8) return null;
    const width = operandBitWidth(size);
    return .{
        .address = base_address,
        .bit_index = @intCast(raw_index & (width - 1)),
    };
}

test "BTR register form clears every bit in the architectural width" {
    const bit_two = resetRegister(.bits32, 0b100, 2);
    try std.testing.expectEqual(@as(u64, 0), bit_two.value);
    try std.testing.expect(bit_two.carry);
    try std.testing.expectEqual(@as(u6, 2), bit_two.bit_index);

    const bit_thirty_one = resetRegister(.bits32, 0x8000_0000, 31);
    try std.testing.expectEqual(@as(u64, 0), bit_thirty_one.value);
    try std.testing.expect(bit_thirty_one.carry);

    const wrapped = resetRegister(.bits32, 0b10, 33);
    try std.testing.expectEqual(@as(u6, 1), wrapped.bit_index);
    try std.testing.expectEqual(@as(u64, 0), wrapped.value);
}

test "BT family preserves the tested carry and applies the requested mutation" {
    const tested = applyRegister(.bits32, 0b0100, 2, .probe);
    try std.testing.expectEqual(@as(u64, 0b0100), tested.value);
    try std.testing.expect(tested.carry);

    const set = applyRegister(.bits32, 0, 5, .set);
    try std.testing.expectEqual(@as(u64, 0b10_0000), set.value);
    try std.testing.expect(!set.carry);

    const reset = applyRegister(.bits32, 0b10_0000, 5, .reset);
    try std.testing.expectEqual(@as(u64, 0), reset.value);
    try std.testing.expect(reset.carry);

    const complemented = applyRegister(.bits32, 0b10, 1, .complement);
    try std.testing.expectEqual(@as(u64, 0), complemented.value);
    try std.testing.expect(complemented.carry);
}

test "BTR memory form carries source-index high bits into the address" {
    const following = memoryOperand(.bits32, 0x1000, 35).?;
    try std.testing.expectEqual(@as(u64, 0x1004), following.address);
    try std.testing.expectEqual(@as(u6, 3), following.bit_index);

    const preceding = memoryOperand(.bits32, 0x1000, @bitCast(@as(i64, -1))).?;
    try std.testing.expectEqual(@as(u64, 0x0ffc), preceding.address);
    try std.testing.expectEqual(@as(u6, 31), preceding.bit_index);
}

test "BT immediate memory form masks within the addressed element" {
    const operand = memoryOperandImmediate(.bits32, 0x2000, 35).?;
    try std.testing.expectEqual(@as(u64, 0x2000), operand.address);
    try std.testing.expectEqual(@as(u6, 3), operand.bit_index);
}
