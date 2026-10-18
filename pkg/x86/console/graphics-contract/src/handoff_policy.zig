//! Generic bit-mask and dependency checks for ordered handoff contracts.

pub fn requiredBitsPresent(observed: u64, required: u64) bool {
    return observed & required == required;
}

pub fn dependenciesPreserved(observed: u16, edges: anytype) bool {
    for (edges) |edge| {
        const from_bit = @as(u16, 1) << @as(u4, @intCast(@intFromEnum(edge.from)));
        const to_bit = @as(u16, 1) << @as(u4, @intCast(@intFromEnum(edge.to)));
        if (observed & to_bit != 0 and observed & from_bit == 0) return false;
    }
    return true;
}
