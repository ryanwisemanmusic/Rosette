//! Private XMM residency within a straight-line sequence of pure 128-bit
//! register operations. v16-v31 are caller-saved and unused by templates.
//! The compiler publishes dirty slots before every observer, helper, entry
//! target or exit. Guest memory, YMM/ZMM semantics and flags stay separate.
const a64 = @import("arm64_encode");

fn eligible(c: anytype, index: u8) bool {
    return c.resident_vectors and c.forward_xmm and index < 16;
}

pub fn destination(c: anytype, index: u8) a64.Reg {
    return if (eligible(c, index)) @intCast(16 + index) else 0;
}

pub fn load(c: anytype, v: a64.Reg, index: u8, base: a64.Reg) !void {
    if (eligible(c, index)) {
        const bit = @as(u16, 1) << @intCast(index);
        const host: a64.Reg = @intCast(16 + index);
        if (c.xmm_valid & bit == 0) {
            try c.a.emit(a64.vldrQ(host, base, @as(u32, index) * 16).?);
            c.xmm_valid |= bit;
        } else c.xmm_loads_forwarded += 1;
        if (v != host) try c.a.emit(a64.vmov(v, host));
        return;
    }
    if (c.forward_xmm and c.last_xmm == index) {
        if (v != 0) try c.a.emit(a64.vmov(v, 0));
        c.xmm_loads_forwarded += 1;
        return;
    }
    if (v == 0) c.last_xmm = null;
    try c.a.emit(a64.vldrQ(v, base, @as(u32, index) * 16).?);
}

pub fn operand(c: anytype, index: u8, temporary: a64.Reg, base: a64.Reg) !a64.Reg {
    const result: a64.Reg = if (eligible(c, index)) @intCast(16 + index) else temporary;
    try load(c, result, index, base);
    return result;
}

pub fn store(c: anytype, index: u8, v: a64.Reg, base: a64.Reg) !void {
    if (eligible(c, index)) {
        const bit = @as(u16, 1) << @intCast(index);
        const host: a64.Reg = @intCast(16 + index);
        if (v != host) try c.a.emit(a64.vmov(host, v));
        if (c.xmm_dirty & bit != 0) c.xmm_stores_elided += 1;
        c.xmm_valid |= bit;
        c.xmm_dirty |= bit;
        c.last_xmm = null;
    } else {
        try c.a.emit(a64.vstrQ(v, base, @as(u32, index) * 16).?);
        c.last_xmm = if (c.forward_xmm and v == 0) index else null;
    }
}

pub fn flush(c: anytype, base: a64.Reg) !void {
    for (0..16) |index| {
        if (c.xmm_dirty & (@as(u16, 1) << @intCast(index)) != 0)
            try c.a.emit(a64.vstrQ(@intCast(16 + index), base, @intCast(index * 16)).?);
    }
    c.xmm_valid = 0;
    c.xmm_dirty = 0;
    c.last_xmm = null;
}
