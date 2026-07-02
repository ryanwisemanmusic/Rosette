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
pub const VPOR = @import("VPOR.zig");

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
    VPOR.meta,
};

pub fn validateAll() types.SafetyError!void {
    for (metas) |meta| try types.validateMeta(meta);
}
