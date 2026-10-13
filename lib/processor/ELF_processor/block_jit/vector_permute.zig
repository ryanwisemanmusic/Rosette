//! VPERMILPS control dwords contain a two-bit index within each 128-bit lane.
//! Build all sixteen TBL byte indexes with vector integer arithmetic. No
//! floating-point arithmetic or dependency on the discarded control bits.
const a64 = @import("arm64_encode");

pub fn variable(assembler: anytype, dst: a64.Reg, source: a64.Reg, control: a64.Reg, indexes: a64.Reg, constant: a64.Reg, scalar: a64.Reg) !void {
    try assembler.emit(a64.movz(.w32, scalar, 3, 0));
    try assembler.emit(a64.vdupGpr(.s4, constant, scalar));
    try assembler.emit(a64.vand(indexes, control, constant));
    // (control & 3) * 0x04040404 repeats the selected byte offset in each
    // byte of its dword: 0, 4, 8 or 12. There are no carries between bytes.
    try assembler.loadConstant(scalar, 0x04040404);
    try assembler.emit(a64.vdupGpr(.s4, constant, scalar));
    try assembler.emit(a64.vmul(.s4, indexes, indexes, constant));
    try assembler.loadConstant(scalar, 0x03020100);
    try assembler.emit(a64.vdupGpr(.s4, constant, scalar));
    try assembler.emit(a64.vadd(.s4, indexes, indexes, constant));
    try assembler.emit(a64.vtbl(dst, source, indexes));
}
