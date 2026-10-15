//! Width-preserving native atomic updates. Existing admission and full
//! ordering fences remain in the block compiler.
const a64 = @import("arm64_encode");
const Op = @import("x64_decoder").Op;

pub const Form = enum {
    exchange,
    compare_exchange,
    compare_exchange8b,
    compare_exchange16b,
    exchange_add,
    update,
    increment,
    decrement,
    negate,
    bitwise_not,
    bit_set,
    bit_reset,
    bit_complement,
};

pub fn of(op: Op) ?Form {
    return switch (op) {
        .xchg_mem8_reg8, .xchg_mem32_reg32, .xchg_mem64_reg64 => .exchange,
        .cmpxchg_mem8_reg8, .cmpxchg_mem16_reg16, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64 => .compare_exchange,
        .cmpxchg8b_mem => .compare_exchange8b,
        .cmpxchg16b_mem => .compare_exchange16b,
        .xadd_mem8_reg8, .xadd_mem32_reg32, .xadd_mem64_reg64 => .exchange_add,
        .bts_mem_imm => .bit_set,
        .btr_mem_imm => .bit_reset,
        .btc_mem_imm => .bit_complement,
        .bts_mem_reg => .bit_set,
        .btr_mem_reg => .bit_reset,
        .btc_mem_reg => .bit_complement,
        .inc_mem8, .inc_mem16, .inc_mem32, .inc_mem64 => .increment,
        .dec_mem8, .dec_mem16, .dec_mem32, .dec_mem64 => .decrement,
        .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => .negate,
        .not_mem8, .not_mem16, .not_mem32, .not_mem64 => .bitwise_not,
        .add_mem8_reg8,
        .add_mem16_reg16,
        .add_mem32_reg32,
        .add_mem64_reg64,
        .add_mem8_imm8,
        .add_mem16_imm8,
        .add_mem32_imm8,
        .add_mem64_imm8,
        .add_mem16_imm32,
        .add_mem32_imm32,
        .add_mem64_imm32,
        .sub_mem8_reg8,
        .sub_mem16_reg16,
        .sub_mem32_reg32,
        .sub_mem64_reg64,
        .sub_mem8_imm8,
        .sub_mem16_imm8,
        .sub_mem32_imm8,
        .sub_mem64_imm8,
        .sub_mem16_imm32,
        .sub_mem32_imm32,
        .sub_mem64_imm32,
        .and_mem8_reg8,
        .and_mem16_reg16,
        .and_mem32_reg32,
        .and_mem64_reg64,
        .and_mem8_imm8,
        .and_mem16_imm8,
        .and_mem32_imm8,
        .and_mem64_imm8,
        .and_mem16_imm32,
        .and_mem32_imm32,
        .and_mem64_imm32,
        .or_mem8_reg8,
        .or_mem16_reg16,
        .or_mem32_reg32,
        .or_mem64_reg64,
        .or_mem8_imm8,
        .or_mem16_imm8,
        .or_mem32_imm8,
        .or_mem64_imm8,
        .or_mem16_imm32,
        .or_mem32_imm32,
        .or_mem64_imm32,
        .xor_mem8_reg8,
        .xor_mem16_reg16,
        .xor_mem32_reg32,
        .xor_mem64_reg64,
        .xor_mem8_imm8,
        .xor_mem16_imm8,
        .xor_mem32_imm8,
        .xor_mem64_imm8,
        .xor_mem16_imm32,
        .xor_mem32_imm32,
        .xor_mem64_imm32,
        .adc_mem8_reg8,
        .adc_mem16_reg16,
        .adc_mem32_reg32,
        .adc_mem64_reg64,
        .adc_mem8_imm8,
        .adc_mem16_imm8,
        .adc_mem32_imm8,
        .adc_mem64_imm8,
        .adc_mem16_imm32,
        .adc_mem32_imm32,
        .adc_mem64_imm32,
        .sbb_mem8_reg8,
        .sbb_mem16_reg16,
        .sbb_mem32_reg32,
        .sbb_mem64_reg64,
        .sbb_mem8_imm8,
        .sbb_mem16_imm8,
        .sbb_mem32_imm8,
        .sbb_mem64_imm8,
        .sbb_mem16_imm32,
        .sbb_mem32_imm32,
        .sbb_mem64_imm32,
        => .update,
        else => null,
    };
}

/// A single acquire-release LSE operation. The operand and returned old
/// value must use distinct non-XZR registers; callers synthesize the guest
/// result and flags from that old value, after the update commits.
pub const Operation = enum { add, sub, bit_and, bit_or, bit_xor };
pub fn emit(a: anytype, size: a64.MemSize, operation: Operation, operand: a64.Reg, old: a64.Reg, host: a64.Reg, temp: a64.Reg) !void {
    const width: a64.Width = if (size == .doubleword) .x64 else .w32;
    switch (operation) {
        .add => try a.emit(a64.ldaddalScalar(size, operand, old, host)),
        .sub => {
            try a.emit(a64.sub(width, temp, a64.xzr, operand));
            try a.emit(a64.ldaddalScalar(size, temp, old, host));
        },
        .bit_and => {
            try a.emit(a64.mvn(width, temp, operand));
            try a.emit(logical(size, .clear, temp, old, host));
        },
        .bit_or => try a.emit(logical(size, .set, operand, old, host)),
        .bit_xor => try a.emit(logical(size, .eor, operand, old, host)),
    }
}
const Logic = enum(u32) { clear = 0x1000, eor = 0x2000, set = 0x3000 };
fn logical(size: a64.MemSize, operation: Logic, rs: a64.Reg, rt: a64.Reg, rn: a64.Reg) u32 {
    return a64.ldaddalScalar(size, rs, rt, rn) | @intFromEnum(operation);
}

test "atomic update LSE encodings match the ARM assembler" {
    const t = @import("std").testing;
    // Independent llvm-mc -triple=aarch64 -mattr=+lse encoding.
    try t.expectEqual(@as(u32, 0xB8E11062), logical(.word, .clear, 1, 2, 3));
    try t.expectEqual(@as(u32, 0xF8E430C5), logical(.doubleword, .set, 4, 5, 6));
    try t.expectEqual(@as(u32, 0x38E72128), logical(.byte, .eor, 7, 8, 9));
    try t.expectEqual(@as(u32, 0x78E131FD), logical(.half, .set, 1, 29, 15));
}
