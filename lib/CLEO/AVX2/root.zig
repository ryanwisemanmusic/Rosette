pub const MOVDQA = @import("MOVDQA.zig");
pub const MOVDQU = @import("MOVDQU.zig");
pub const MOVNTDQ = @import("MOVNTDQ.zig");
pub const MOVNTDQA = @import("MOVNTDQA.zig");
pub const PMAXSB = @import("PMAXSB.zig");
pub const PMAXSD = @import("PMAXSD.zig");
pub const PMAXSW = @import("PMAXSW.zig");
pub const PMAXUB = @import("PMAXUB.zig");
pub const PMAXUD = @import("PMAXUD.zig");
pub const PMAXUW = @import("PMAXUW.zig");
pub const PMINSB = @import("PMINSB.zig");
pub const PMINSD = @import("PMINSD.zig");
pub const PMINSW = @import("PMINSW.zig");
pub const PMINUB = @import("PMINUB.zig");
pub const PMINUD = @import("PMINUD.zig");
pub const PMINUW = @import("PMINUW.zig");
pub const VMOVDQA = @import("VMOVDQA.zig");
pub const VMOVDQU = @import("VMOVDQU.zig");
pub const VMOVNTDQ = @import("VMOVNTDQ.zig");
pub const VMOVNTDQA = @import("VMOVNTDQA.zig");
pub const VPADDB = @import("VPADDB.zig");
pub const VPADDW = @import("VPADDW.zig");
pub const VPADDD = @import("VPADDD.zig");
pub const VPADDQ = @import("VPADDQ.zig");
pub const VPSUBB = @import("VPSUBB.zig");
pub const VPSUBW = @import("VPSUBW.zig");
pub const VPSUBD = @import("VPSUBD.zig");
pub const VPSUBQ = @import("VPSUBQ.zig");
pub const VPCMPEQB = @import("VPCMPEQB.zig");
pub const VPCMPEQW = @import("VPCMPEQW.zig");
pub const VPCMPEQD = @import("VPCMPEQD.zig");
pub const VPCMPEQQ = @import("VPCMPEQQ.zig");
pub const VPCMPGTB = @import("VPCMPGTB.zig");
pub const VPCMPGTW = @import("VPCMPGTW.zig");
pub const VPCMPGTD = @import("VPCMPGTD.zig");
pub const VPCMPGTQ = @import("VPCMPGTQ.zig");
pub const VPMULLW = @import("VPMULLW.zig");
pub const VPMULLD = @import("VPMULLD.zig");
pub const VPOR = @import("VPOR.zig");
pub const VPSUBSB = @import("VPSUBSB.zig");
pub const VPSUBSW = @import("VPSUBSW.zig");
pub const VPSUBUSB = @import("VPSUBUSB.zig");
pub const VPSUBUSW = @import("VPSUBUSW.zig");

const types = @import("../types.zig");

pub const metas = [_]types.InstructionMeta{
    MOVDQA.meta,
    MOVDQU.meta,
    MOVNTDQ.meta,
    MOVNTDQA.meta,
    PMAXSB.meta,
    PMAXSD.meta,
    PMAXSW.meta,
    PMAXUB.meta,
    PMAXUD.meta,
    PMAXUW.meta,
    PMINSB.meta,
    PMINSD.meta,
    PMINSW.meta,
    PMINUB.meta,
    PMINUD.meta,
    PMINUW.meta,
    VMOVDQA.meta,
    VMOVDQU.meta,
    VMOVNTDQ.meta,
    VMOVNTDQA.meta,
    VPADDB.meta,
    VPADDW.meta,
    VPADDD.meta,
    VPADDQ.meta,
    VPSUBB.meta,
    VPSUBW.meta,
    VPSUBD.meta,
    VPSUBQ.meta,
    VPCMPEQB.meta,
    VPCMPEQW.meta,
    VPCMPEQD.meta,
    VPCMPEQQ.meta,
    VPCMPGTB.meta,
    VPCMPGTW.meta,
    VPCMPGTD.meta,
    VPCMPGTQ.meta,
    VPMULLW.meta,
    VPMULLD.meta,
    VPOR.meta,
    VPSUBSB.meta,
    VPSUBSW.meta,
    VPSUBUSB.meta,
    VPSUBUSW.meta,
};

pub fn validateAll() types.SafetyError!void {
    for (metas) |meta| try types.validateMeta(meta);
}
