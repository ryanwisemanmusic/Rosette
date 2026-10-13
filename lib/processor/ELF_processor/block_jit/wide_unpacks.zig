//! VEX.256 register unpacks interleave independently in each 128-bit lane.
//! Read all halves before publishing either half, including aliased sources.
const a64 = @import("arm64_encode");

pub fn registers(c: anytype, d: anytype, lanes: a64.Lanes, high: bool) !void {
    try c.loadXmm(1, d.xmm_src);
    try c.loadYmmHigh(2, d.xmm_src);
    try c.loadXmm(3, d.xmm_src2);
    try c.loadYmmHigh(4, d.xmm_src2);
    try c.emit(if (high) a64.vzip2(lanes, 0, 1, 3) else a64.vzip1(lanes, 0, 1, 3));
    try c.emit(if (high) a64.vzip2(lanes, 1, 2, 4) else a64.vzip1(lanes, 1, 2, 4));
    try c.storeXmm(d.xmm_dst, 0);
    try c.storeYmmHigh(d.xmm_dst, 1);
}
