const decoder = @import("decoder.zig");

pub const BridgeStatus = enum {
    unsupported,
    metadata_only,
};

pub const BridgeResult = struct {
    status: BridgeStatus,
    op: decoder.Op,
};

/// Stable adapter point for routing decoded x86-64 instructions into the ISA
/// truth layer as that layer becomes executable/DBT-ready.
pub fn describe(decoded: decoder.DecodedInsn) BridgeResult {
    return .{
        .status = .metadata_only,
        .op = decoded.op,
    };
}
