//! Generic displacement calculation for bounded relative branches.

pub const BranchRange = struct {
    minimum: i64,
    maximum: i64,
    alignment: u64,
};

/// `origin` is the architecture's branch base (for x86 rel32, the end of the
/// instruction; for ARM64 B, the current instruction address).
pub fn displacement(origin: u64, target: u64, range: BranchRange) ?i64 {
    if (range.minimum > 0 or range.maximum < 0 or range.alignment == 0) return null;
    if (origin % range.alignment != 0 or target % range.alignment != 0) return null;

    if (target >= origin) {
        const distance = target - origin;
        const maximum: u64 = @intCast(range.maximum);
        if (distance > maximum) return null;
        return @intCast(distance);
    }

    const distance = origin - target;
    if (range.minimum == 0) return null;
    const minimum_magnitude: u64 = @as(u64, @intCast(-(range.minimum + 1))) + 1;
    if (distance > minimum_magnitude) return null;
    if (distance == 0x8000_0000_0000_0000) return -@as(i64, 0x7fff_ffff_ffff_ffff) - 1;
    if (distance > 0x7fff_ffff_ffff_ffff) return null;
    return -@as(i64, @intCast(distance));
}
