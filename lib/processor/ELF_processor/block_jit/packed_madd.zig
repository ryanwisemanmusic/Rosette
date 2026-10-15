//! VPMADDWD: eight signed word products summed in adjacent pairs, modulo 2^32.
//! Temporary v3/v4 are distinct from the template's operand and result registers.
const a64 = @import("arm64_encode");
pub fn emit(a: anytype, result: a64.Reg, lhs: a64.Reg, rhs: a64.Reg) !void {
    try a.emit(smull(false, 3, lhs, rhs));
    try a.emit(smull(true, 4, lhs, rhs));
    try a.emit(addp(result, 3, 4));
}
fn smull(high: bool, rd: a64.Reg, rn: a64.Reg, rm: a64.Reg) u32 {
    return @as(u32, if (high) 0x4E60C000 else 0x0E60C000) | @as(u32, rm) << 16 | @as(u32, rn) << 5 | rd;
}
fn addp(rd: a64.Reg, rn: a64.Reg, rm: a64.Reg) u32 {
    return 0x4EA0BC00 | @as(u32, rm) << 16 | @as(u32, rn) << 5 | rd;
}
test "native completion packed madd encodings match llvm-mc" {
    const t = @import("std").testing;
    try t.expectEqual(@as(u32, 0x0E62C023), smull(false, 3, 1, 2));
    try t.expectEqual(@as(u32, 0x4E62C024), smull(true, 4, 1, 2));
    try t.expectEqual(@as(u32, 0x4EA4BC60), addp(0, 3, 4));
}
