//! A full TLB span is already admitted by the caller. Split an unaligned
//! scalar only as far as its natural alignment requires, retaining ascending
//! acquire/release accesses and touching precisely the operand's bytes.
const a64 = @import("arm64_encode");
const byte_lanes = @import("ordered_lanes.zig");

pub fn emit(a: anytype, data: a64.Reg, host: a64.Reg, bytes: u8, store: bool) !void {
    if (bytes <= 2) {
        if (store) try byte_lanes.scalarStore(a, host, bytes) else try byte_lanes.scalarLoad(a, data, host, bytes);
        return;
    }
    const halves = try a.createLabel();
    const single_bytes = try a.createLabel();
    const done = try a.createLabel();
    if (bytes == 8) {
        try a.emit(a64.logicalImmediate(.x64, .andop, 11, host, 3).?);
        try a.branchIfNonZero(.x64, 11, halves);
        try lanes(a, data, host, bytes, .word, 4, store);
        try a.branch(done);
    }
    a.placeLabel(halves);
    try a.emit(a64.logicalImmediate(.x64, .andop, 11, host, 1).?);
    try a.branchIfNonZero(.x64, 11, single_bytes);
    try lanes(a, data, host, bytes, .half, 2, store);
    try a.branch(done);
    a.placeLabel(single_bytes);
    if (store) try byte_lanes.scalarStore(a, host, bytes) else try byte_lanes.scalarLoad(a, data, host, bytes);
    a.placeLabel(done);
}

fn lanes(a: anytype, data: a64.Reg, host: a64.Reg, bytes: u8, size: a64.MemSize, width: u8, store: bool) !void {
    if (!store) try a.emit(a64.eorReg(.x64, data, data, data));
    var offset: u8 = 0;
    while (offset < bytes) : (offset += width) {
        const shift: u6 = @intCast(offset * 8);
        if (store) {
            try a.emit(if (shift == 0) a64.mov(.x64, 11, data) else a64.lsrImm(.x64, 11, data, shift));
            try a.emit(a64.stlr(size, 11, host));
        } else {
            try a.emit(a64.ldar(size, 11, host));
            if (shift != 0) try a.emit(a64.lslImm(.x64, 11, 11, shift));
            try a.emit(a64.orrReg(.x64, data, data, 11));
        }
        if (offset + width != bytes) try a.emit(a64.addImm(.x64, host, host, width).?);
    }
}
