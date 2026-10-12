//! Ordered unaligned operands on TLB-admitted normal memory. Lane widths
//! and acquire/release instructions match the existing route. A first load
//! clears unused vector lanes instead of depending on the previous vector.
const a64 = @import("arm64_encode");

pub fn vector(a: anytype, v: a64.Reg, host: a64.Reg, store: bool, lanes: a64.Lanes, size: a64.MemSize, comptime width: usize) !void {
    try a.emit(a64.mov(.x64, 10, host));
    for (0..16 / width) |lane| {
        if (store) {
            try a.emit(a64.vumov(lanes, 9, v, @intCast(lane)));
            try a.emit(a64.stlr(size, 9, 10));
        } else {
            try a.emit(a64.ldar(size, 9, 10));
            // LDARB/LDARW zero-extend. FMOV S initializes the low word and
            // clears the rest; all following byte/word lanes replace zeros.
            try a.emit(if (lane == 0) a64.fmovSFromW(v, 9) else a64.vinsGpr(lanes, v, @intCast(lane), 9));
        }
        if (lane + 1 != 16 / width) try a.emit(a64.addImm(.x64, 10, 10, width).?);
    }
}

pub fn scalarLoad(a: anytype, destination: a64.Reg, host: a64.Reg, bytes: u8) !void {
    try a.emit(a64.eorReg(.x64, destination, destination, destination));
    for (0..bytes) |index| {
        try a.emit(a64.ldar(.byte, 11, host));
        const shift: u6 = @intCast(index * 8);
        if (shift != 0) try a.emit(a64.lslImm(.x64, 11, 11, shift));
        try a.emit(a64.orrReg(.x64, destination, destination, 11));
        if (index + 1 != bytes) try a.emit(a64.addImm(.x64, host, host, 1).?);
    }
}

pub fn scalarStore(a: anytype, host: a64.Reg, bytes: u8) !void {
    for (0..bytes) |index| {
        const shift: u6 = @intCast(index * 8);
        try a.emit(if (shift == 0) a64.mov(.x64, 11, 3) else a64.lsrImm(.x64, 11, 3, shift));
        try a.emit(a64.stlr(.byte, 11, host));
        if (index + 1 != bytes) try a.emit(a64.addImm(.x64, host, host, 1).?);
    }
}
