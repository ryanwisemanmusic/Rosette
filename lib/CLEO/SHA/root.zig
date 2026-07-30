pub const SHA1MSG1 = @import("SHA1MSG1.zig");
pub const SHA1MSG2 = @import("SHA1MSG2.zig");
pub const SHA1NEXTE = @import("SHA1NEXTE.zig");
pub const SHA1RNDS4 = @import("SHA1RNDS4.zig");
pub const SHA256MSG1 = @import("SHA256MSG1.zig");
pub const SHA256MSG2 = @import("SHA256MSG2.zig");
pub const SHA256RNDS2 = @import("SHA256RNDS2.zig");

const types = @import("../types.zig");

pub const metas = [_]types.InstructionMeta{
    SHA1MSG1.meta,
    SHA1MSG2.meta,
    SHA1NEXTE.meta,
    SHA1RNDS4.meta,
    SHA256MSG1.meta,
    SHA256MSG2.meta,
    SHA256RNDS2.meta,
};

pub fn validateAll() types.SafetyError!void {
    for (metas) |meta| try types.validateMeta(meta);
}
