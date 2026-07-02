pub const ADDPD = @import("ADDPD.zig");
pub const ADDPS = @import("ADDPS.zig");
pub const ADDSUBPD = @import("ADDSUBPD.zig");
pub const ADDSUBPS = @import("ADDSUBPS.zig");
pub const ANDNPD = @import("ANDNPD.zig");
pub const ANDNPS = @import("ANDNPS.zig");
pub const ANDPD = @import("ANDPD.zig");
pub const ANDPS = @import("ANDPS.zig");
pub const BLENDPD = @import("BLENDPD.zig");
pub const BLENDPS = @import("BLENDPS.zig");
pub const BLENDVPD = @import("BLENDVPD.zig");
pub const BLENDVPS = @import("BLENDVPS.zig");
pub const CMPPD = @import("CMPPD.zig");
pub const CMPPS = @import("CMPPS.zig");
pub const DIVPD = @import("DIVPD.zig");
pub const DIVPS = @import("DIVPS.zig");
pub const DPPS = @import("DPPS.zig");
pub const LDDQU = @import("LDDQU.zig");
pub const MOVAPD = @import("MOVAPD.zig");
pub const MOVAPS = @import("MOVAPS.zig");
pub const MOVDDUP = @import("MOVDDUP.zig");
pub const MOVMSKPD = @import("MOVMSKPD.zig");
pub const MOVMSKPS = @import("MOVMSKPS.zig");
pub const MULPD = @import("MULPD.zig");
pub const MULPS = @import("MULPS.zig");
pub const MOVNTPD = @import("MOVNTPD.zig");
pub const MOVNTPS = @import("MOVNTPS.zig");
pub const MOVSHDUP = @import("MOVSHDUP.zig");
pub const MOVSLDUP = @import("MOVSLDUP.zig");
pub const MOVUPD = @import("MOVUPD.zig");
pub const MOVUPS = @import("MOVUPS.zig");
pub const ORPD = @import("ORPD.zig");
pub const ORPS = @import("ORPS.zig");
pub const SQRTPD = @import("SQRTPD.zig");
pub const SQRTPS = @import("SQRTPS.zig");
pub const SUBPD = @import("SUBPD.zig");
pub const SUBPS = @import("SUBPS.zig");
pub const VMOVAPD = @import("VMOVAPD.zig");
pub const VMOVAPS = @import("VMOVAPS.zig");
pub const VMOVDDUP = @import("VMOVDDUP.zig");
pub const VMOVMSKPD = @import("VMOVMSKPD.zig");
pub const VMOVMSKPS = @import("VMOVMSKPS.zig");
pub const VMOVNTPD = @import("VMOVNTPD.zig");
pub const VMOVNTPS = @import("VMOVNTPS.zig");
pub const VMOVSHDUP = @import("VMOVSHDUP.zig");
pub const VMOVSLDUP = @import("VMOVSLDUP.zig");
pub const VMOVUPD = @import("VMOVUPD.zig");
pub const VMOVUPS = @import("VMOVUPS.zig");
pub const SHUFPD = @import("SHUFPD.zig");
pub const SHUFPS = @import("SHUFPS.zig");
pub const XORPD = @import("XORPD.zig");
pub const XORPS = @import("XORPS.zig");

const types = @import("../types.zig");

pub const metas = [_]types.InstructionMeta{
    ADDPD.meta,
    ADDPS.meta,
    ADDSUBPD.meta,
    ADDSUBPS.meta,
    ANDNPD.meta,
    ANDNPS.meta,
    ANDPD.meta,
    ANDPS.meta,
    BLENDPD.meta,
    BLENDPS.meta,
    BLENDVPD.meta,
    BLENDVPS.meta,
    CMPPD.meta,
    CMPPS.meta,
    DIVPD.meta,
    DIVPS.meta,
    DPPS.meta,
    LDDQU.meta,
    MOVAPD.meta,
    MOVAPS.meta,
    MOVDDUP.meta,
    MOVMSKPD.meta,
    MOVMSKPS.meta,
    MULPD.meta,
    MULPS.meta,
    MOVNTPD.meta,
    MOVNTPS.meta,
    MOVSHDUP.meta,
    MOVSLDUP.meta,
    MOVUPD.meta,
    MOVUPS.meta,
    ORPD.meta,
    ORPS.meta,
    SQRTPD.meta,
    SQRTPS.meta,
    SUBPD.meta,
    SUBPS.meta,
    VMOVAPD.meta,
    VMOVAPS.meta,
    VMOVDDUP.meta,
    VMOVMSKPD.meta,
    VMOVMSKPS.meta,
    VMOVNTPD.meta,
    VMOVNTPS.meta,
    VMOVSHDUP.meta,
    VMOVSLDUP.meta,
    VMOVUPD.meta,
    VMOVUPS.meta,
    SHUFPD.meta,
    SHUFPS.meta,
    XORPD.meta,
    XORPS.meta,
};

pub fn validateAll() types.SafetyError!void {
    for (metas) |meta| try types.validateMeta(meta);
}
