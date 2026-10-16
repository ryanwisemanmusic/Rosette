//! Pure whole-register operations, directly in an existing private cache.
//! Caller proves flag outputs dead for shifts, rotations and NEG. NOT never
//! changes flags. Narrow merges and zero rotations retain the ordinary path.
const a64 = @import("arm64_encode");
const core = @import("core.zig");
pub fn emit(a: anytype, d: core.DecodedInsn, host: a64.Reg) !bool {
    if (d.size != .bits32 and d.size != .bits64) return false;
    const width: a64.Width = if (d.size == .bits64) .x64 else .w32;
    const bits: u7 = if (d.size == .bits64) 64 else 32;
    const count: u6 = @intCast(d.imm & (bits - 1));
    const word = switch (d.op) {
        .shl_reg_imm => a64.lslImm(width, host, host, count),
        .shr_reg_imm => a64.lsrImm(width, host, host, count),
        .sar_reg_imm => a64.asrImm(width, host, host, count),
        .rol_reg_imm, .ror_reg_imm => blk: {
            // At count zero x86 ROL/ROR leaves even the upper half intact.
            if (count == 0) return false;
            break :blk a64.rorImm(width, host, host, if (d.op == .rol_reg_imm) @intCast(bits - count) else count);
        },
        .not_reg32, .not_reg64 => a64.mvn(width, host, host),
        .neg_reg32, .neg_reg64 => a64.sub(width, host, a64.xzr, host),
        else => return false,
    };
    try a.emit(word);
    return true;
}
