//! Eager x86 ADD/SUB flags from a width-matched ARM operation. The inputs
//! and result remain intact; narrow and carry-in operations use the old path.
const a64 = @import("arm64_encode");

pub fn eligible(size: anytype, kind: anytype, carry: bool, live: u8) bool {
    return (size == .bits32 or size == .bits64) and kind != .logic and !carry and live & 32 != 0;
}

/// t3 already contains the old flags with precisely the live bits cleared.
/// t4/t5 are the existing flag computation temporaries; t6 may hold
/// an unlocked memory operand address and must survive. No helper or
/// guest memory operation is introduced. SUB's ARM carry means no borrow.
pub fn emit(c: anytype, size: anytype, kind: anytype, a: a64.Reg, b: a64.Reg, r: a64.Reg, live: u8) !void {
    const width: a64.Width = if (size == .bits64) .x64 else .w32;
    if (!c.fresh_arithmetic_nzcv) try c.emit(a64.addSubShifted(width, if (kind == .add) .add else .sub, true, a64.xzr, a, b, 0));
    try c.emit(a64.mrsNzcv(14));
    // N and Z have the same relative positions in NZCV and RFLAGS.
    const nz: u32 = (if (live & 16 != 0) @as(u32, 1) << 31 else 0) |
        (if (live & 8 != 0) @as(u32, 1) << 30 else 0);
    if (nz != 0) {
        try c.emit(a64.logicalImmediate(.w32, .andop, 13, 14, nz).?);
        try c.emit(a64.logicalShifted(.w32, .orr, 12, 12, 13, 24) | (0b01 << 22));
    }
    if (live & 1 != 0) {
        try c.emit(a64.ubfx(.w32, 13, 14, 29, 1));
        if (kind == .sub) try c.emit(a64.logicalImmediate(.w32, .eor, 13, 13, 1).?);
        try c.emit(a64.orrReg(.w32, 12, 12, 13));
    }
    // V maps directly to x86 OF at this width.
    try c.emit(a64.ubfx(.w32, 13, 14, 28, 1));
    try c.emit(a64.logicalShifted(.w32, .orr, 12, 12, 13, 11));
    if (live & 4 != 0) {
        try c.emit(a64.eorReg(.w32, 13, a, b));
        try c.emit(a64.eorReg(.w32, 13, 13, r));
        try c.emit(a64.logicalImmediate(.w32, .andop, 13, 13, 16).?);
        try c.emit(a64.orrReg(.w32, 12, 12, 13));
    }
    if (live & 2 != 0) {
        try c.emit(a64.logicalShifted(.w32, .eor, 13, r, r, 4) | (0b01 << 22));
        try c.emit(a64.logicalShifted(.w32, .eor, 13, 13, 13, 2) | (0b01 << 22));
        try c.emit(a64.logicalShifted(.w32, .eor, 13, 13, 13, 1) | (0b01 << 22));
        try c.emit(a64.logicalImmediate(.w32, .andop, 13, 13, 1).?);
        try c.emit(a64.logicalImmediate(.w32, .eor, 13, 13, 1).?);
        try c.emit(a64.logicalShifted(.w32, .orr, 12, 12, 13, 2));
    }
}
