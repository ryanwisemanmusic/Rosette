pub const PMAXSB = @import("PMAXSB.zig");
pub const PMAXSW = @import("PMAXSW.zig");
pub const PMAXUB = @import("PMAXUB.zig");
pub const PMAXUW = @import("PMAXUW.zig");
pub const PMINSB = @import("PMINSB.zig");
pub const PMINSW = @import("PMINSW.zig");
pub const PMINUB = @import("PMINUB.zig");
pub const PMINUW = @import("PMINUW.zig");
pub const VPADDB = @import("VPADDB.zig");
pub const VPADDW = @import("VPADDW.zig");
pub const VPSUBB = @import("VPSUBB.zig");
pub const VPSUBW = @import("VPSUBW.zig");
pub const VPCMPEQB = @import("VPCMPEQB.zig");
pub const VPCMPEQW = @import("VPCMPEQW.zig");
pub const VPCMPGTB = @import("VPCMPGTB.zig");
pub const VPCMPGTW = @import("VPCMPGTW.zig");
pub const VPMULLW = @import("VPMULLW.zig");
pub const VPSUBSB = @import("VPSUBSB.zig");
pub const VPSUBSW = @import("VPSUBSW.zig");
pub const VPSUBUSB = @import("VPSUBUSB.zig");
pub const VPSUBUSW = @import("VPSUBUSW.zig");
pub const VMOVDQU8 = @import("VMOVDQU8.zig");
pub const VMOVDQU16 = @import("VMOVDQU16.zig");
pub const VPMOVWB = @import("VPMOVWB.zig");
pub const VPMOVSWB = @import("VPMOVSWB.zig");
pub const VPMOVUSWB = @import("VPMOVUSWB.zig");
pub const VPABSB = @import("VPABSB.zig");
pub const VPABSW = @import("VPABSW.zig");
pub const VPAVGB = @import("VPAVGB.zig");
pub const VPAVGW = @import("VPAVGW.zig");

const types = @import("../types.zig");

pub const metas = [_]types.InstructionMeta{
    PMAXSB.meta,
    PMAXSW.meta,
    PMAXUB.meta,
    PMAXUW.meta,
    PMINSB.meta,
    PMINSW.meta,
    PMINUB.meta,
    PMINUW.meta,
    VPADDB.meta,
    VPADDW.meta,
    VPSUBB.meta,
    VPSUBW.meta,
    VPCMPEQB.meta,
    VPCMPEQW.meta,
    VPCMPGTB.meta,
    VPCMPGTW.meta,
    VPMULLW.meta,
    VPSUBSB.meta,
    VPSUBSW.meta,
    VPSUBUSB.meta,
    VPSUBUSW.meta,
    VMOVDQU8.meta,
    VMOVDQU16.meta,
    VPMOVWB.meta,
    VPMOVSWB.meta,
    VPMOVUSWB.meta,
    VPABSB.meta,
    VPABSW.meta,
    VPAVGB.meta,
    VPAVGW.meta,
};

pub fn validateAll() types.SafetyError!void {
    for (metas) |meta| try types.validateMeta(meta);
}
