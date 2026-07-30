pub const GF2P8MULB = @import("GF2P8MULB.zig");
pub const GF2P8AFFINEQB = @import("GF2P8AFFINEQB.zig");
pub const GF2P8AFFINEINVQB = @import("GF2P8AFFINEINVQB.zig");

const types = @import("../types.zig");

pub const metas = [_]types.InstructionMeta{
    GF2P8MULB.meta,
    GF2P8AFFINEQB.meta,
    GF2P8AFFINEINVQB.meta,
};

pub fn validateAll() types.SafetyError!void {
    for (metas) |meta| try types.validateMeta(meta);
}
