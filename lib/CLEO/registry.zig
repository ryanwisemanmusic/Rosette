const std = @import("std");
const types = @import("types.zig");
pub const AVX = @import("AVX/root.zig");
pub const AVX2 = @import("AVX2/root.zig");
pub const AVX512F = @import("AVX512F/root.zig");
pub const AVX512DQ = @import("AVX512DQ/root.zig");
pub const AVX512BW = @import("AVX512BW/root.zig");
pub const AVX512BF16 = @import("AVX512BF16/root.zig");
pub const VAES = @import("VAES/root.zig");
pub const SYSTEM = @import("SYSTEM/root.zig");

pub const metas = [_]types.InstructionMeta{
    AVX.ADDPD.meta,
    AVX.ADDPS.meta,
    AVX.ADDSUBPD.meta,
    AVX.ADDSUBPS.meta,
    AVX.ANDNPD.meta,
    AVX.ANDNPS.meta,
    AVX.ANDPD.meta,
    AVX.ANDPS.meta,
    AVX.BLENDPD.meta,
    AVX.BLENDPS.meta,
    AVX.BLENDVPD.meta,
    AVX.BLENDVPS.meta,
    AVX.CMPPD.meta,
    AVX.CMPPS.meta,
    AVX.DIVPD.meta,
    AVX.DIVPS.meta,
    AVX.DPPS.meta,
    AVX.LDDQU.meta,
    AVX.MOVAPD.meta,
    AVX.MOVAPS.meta,
    AVX.MOVDDUP.meta,
    AVX.MOVMSKPD.meta,
    AVX.MOVMSKPS.meta,
    AVX.MULPD.meta,
    AVX.MULPS.meta,
    AVX.MOVNTPD.meta,
    AVX.MOVNTPS.meta,
    AVX.MOVSHDUP.meta,
    AVX.MOVSLDUP.meta,
    AVX.MOVUPD.meta,
    AVX.MOVUPS.meta,
    AVX.ORPD.meta,
    AVX.ORPS.meta,
    AVX.SQRTPD.meta,
    AVX.SQRTPS.meta,
    AVX.SUBPD.meta,
    AVX.SUBPS.meta,
    AVX.VMOVAPD.meta,
    AVX.VMOVAPS.meta,
    AVX.VMOVDDUP.meta,
    AVX.VMOVMSKPD.meta,
    AVX.VMOVMSKPS.meta,
    AVX.VMOVNTPD.meta,
    AVX.VMOVNTPS.meta,
    AVX.VMOVSHDUP.meta,
    AVX.VMOVSLDUP.meta,
    AVX.VMOVUPD.meta,
    AVX.VMOVUPS.meta,
    AVX.SHUFPD.meta,
    AVX.SHUFPS.meta,
    AVX.XORPD.meta,
    AVX.XORPS.meta,
    AVX.VFMADD132PD.meta,
    AVX.VFMADD132PS.meta,
    AVX.VFMADD213PD.meta,
    AVX.VFMADD213PS.meta,
    AVX.VFMADD231PD.meta,
    AVX.VFMADD231PS.meta,
    AVX.VFMSUB132PD.meta,
    AVX.VFMSUB132PS.meta,
    AVX.VFMSUB213PD.meta,
    AVX.VFMSUB213PS.meta,
    AVX.VFMSUB231PD.meta,
    AVX.VFMSUB231PS.meta,
    AVX.VFNMADD132PD.meta,
    AVX.VFNMADD132PS.meta,
    AVX.VFNMADD213PD.meta,
    AVX.VFNMADD213PS.meta,
    AVX.VFNMADD231PD.meta,
    AVX.VFNMADD231PS.meta,
    AVX.VFNMSUB132PD.meta,
    AVX.VFNMSUB132PS.meta,
    AVX.VFNMSUB213PD.meta,
    AVX.VFNMSUB213PS.meta,
    AVX.VFNMSUB231PD.meta,
    AVX.VFNMSUB231PS.meta,
    AVX.VFMADDSUB132PD.meta,
    AVX.VFMADDSUB132PS.meta,
    AVX.VFMADDSUB213PD.meta,
    AVX.VFMADDSUB213PS.meta,
    AVX.VFMADDSUB231PD.meta,
    AVX.VFMADDSUB231PS.meta,
    AVX.VFMSUBADD132PD.meta,
    AVX.VFMSUBADD132PS.meta,
    AVX.VFMSUBADD213PD.meta,
    AVX.VFMSUBADD213PS.meta,
    AVX.VFMSUBADD231PD.meta,
    AVX.VFMSUBADD231PS.meta,
    AVX.VFMADDRND231PD.meta,
    AVX2.MOVDQA.meta,
    AVX2.MOVDQU.meta,
    AVX2.MOVNTDQ.meta,
    AVX2.MOVNTDQA.meta,
    AVX2.PMAXSB.meta,
    AVX2.PMAXSD.meta,
    AVX2.PMAXSW.meta,
    AVX2.PMAXUB.meta,
    AVX2.PMAXUD.meta,
    AVX2.PMAXUW.meta,
    AVX2.PMINSB.meta,
    AVX2.PMINSD.meta,
    AVX2.PMINSW.meta,
    AVX2.PMINUB.meta,
    AVX2.PMINUD.meta,
    AVX2.PMINUW.meta,
    AVX2.VMOVDQA.meta,
    AVX2.VMOVDQU.meta,
    AVX2.VMOVNTDQ.meta,
    AVX2.VMOVNTDQA.meta,
    AVX2.VPADDB.meta,
    AVX2.VPADDW.meta,
    AVX2.VPADDD.meta,
    AVX2.VPADDQ.meta,
    AVX2.VPSUBB.meta,
    AVX2.VPSUBW.meta,
    AVX2.VPSUBD.meta,
    AVX2.VPSUBQ.meta,
    AVX2.VPCMPEQB.meta,
    AVX2.VPCMPEQW.meta,
    AVX2.VPCMPEQD.meta,
    AVX2.VPCMPEQQ.meta,
    AVX2.VPCMPGTB.meta,
    AVX2.VPCMPGTW.meta,
    AVX2.VPCMPGTD.meta,
    AVX2.VPCMPGTQ.meta,
    AVX2.VPMULLW.meta,
    AVX2.VPMULLD.meta,
    AVX2.VPOR.meta,
    AVX2.VPSUBSB.meta,
    AVX2.VPSUBSW.meta,
    AVX2.VPSUBUSB.meta,
    AVX2.VPSUBUSW.meta,
    AVX512F.ADDPD.meta,
    AVX512F.ADDPS.meta,
    AVX512F.CMPPD.meta,
    AVX512F.CMPPS.meta,
    AVX512F.DIVPD.meta,
    AVX512F.DIVPS.meta,
    AVX512F.MULPD.meta,
    AVX512F.MULPS.meta,
    AVX512F.PMAXSD.meta,
    AVX512F.PMAXSQ.meta,
    AVX512F.PMAXUD.meta,
    AVX512F.PMAXUQ.meta,
    AVX512F.PMINSD.meta,
    AVX512F.PMINSQ.meta,
    AVX512F.PMINUD.meta,
    AVX512F.PMINUQ.meta,
    AVX512F.SHUFPD.meta,
    AVX512F.SHUFPS.meta,
    AVX512F.SQRTPD.meta,
    AVX512F.SQRTPS.meta,
    AVX512F.VMOVDQA32.meta,
    AVX512F.VMOVDQA64.meta,
    AVX512F.VMOVDQU32.meta,
    AVX512F.VMOVDQU64.meta,
    AVX512F.VPORD.meta,
    AVX512F.VPORQ.meta,
    AVX512F.SUBPD.meta,
    AVX512F.SUBPS.meta,
    AVX512F.VPADDD.meta,
    AVX512F.VPADDQ.meta,
    AVX512F.VPSUBD.meta,
    AVX512F.VPSUBQ.meta,
    AVX512F.VPCMPEQD.meta,
    AVX512F.VPCMPEQQ.meta,
    AVX512F.VPCMPGTD.meta,
    AVX512F.VPCMPGTQ.meta,
    AVX512F.VPMULLD.meta,
    AVX512F.VFMADD132PD.meta,
    AVX512F.VFMADD132PS.meta,
    AVX512F.VFMADD213PD.meta,
    AVX512F.VFMADD213PS.meta,
    AVX512F.VFMADD231PD.meta,
    AVX512F.VFMADD231PS.meta,
    AVX512F.VFMSUB132PD.meta,
    AVX512F.VFMSUB132PS.meta,
    AVX512F.VFMSUB213PD.meta,
    AVX512F.VFMSUB213PS.meta,
    AVX512F.VFMSUB231PD.meta,
    AVX512F.VFMSUB231PS.meta,
    AVX512F.VFNMADD132PD.meta,
    AVX512F.VFNMADD132PS.meta,
    AVX512F.VFNMADD213PD.meta,
    AVX512F.VFNMADD213PS.meta,
    AVX512F.VFNMADD231PD.meta,
    AVX512F.VFNMADD231PS.meta,
    AVX512F.VFNMSUB132PD.meta,
    AVX512F.VFNMSUB132PS.meta,
    AVX512F.VFNMSUB213PD.meta,
    AVX512F.VFNMSUB213PS.meta,
    AVX512F.VFNMSUB231PD.meta,
    AVX512F.VFNMSUB231PS.meta,
    AVX512F.VFMADDSUB132PD.meta,
    AVX512F.VFMADDSUB132PS.meta,
    AVX512F.VFMADDSUB213PD.meta,
    AVX512F.VFMADDSUB213PS.meta,
    AVX512F.VFMADDSUB231PD.meta,
    AVX512F.VFMADDSUB231PS.meta,
    AVX512F.VFMSUBADD132PD.meta,
    AVX512F.VFMSUBADD132PS.meta,
    AVX512F.VFMSUBADD213PD.meta,
    AVX512F.VFMSUBADD213PS.meta,
    AVX512F.VFMSUBADD231PD.meta,
    AVX512F.VFMSUBADD231PS.meta,
    AVX512F.VFMADDRND231PD.meta,
    AVX512DQ.ORPD.meta,
    AVX512DQ.ORPS.meta,
    AVX512DQ.XORPD.meta,
    AVX512DQ.XORPS.meta,
    AVX512DQ.ANDPS.meta,
    AVX512DQ.ANDPD.meta,
    AVX512DQ.ANDNPS.meta,
    AVX512DQ.ANDNPD.meta,
    AVX512BW.PMAXSB.meta,
    AVX512BW.PMAXSW.meta,
    AVX512BW.PMAXUB.meta,
    AVX512BW.PMAXUW.meta,
    AVX512BW.PMINSB.meta,
    AVX512BW.PMINSW.meta,
    AVX512BW.PMINUB.meta,
    AVX512BW.PMINUW.meta,
    AVX512BW.VPADDB.meta,
    AVX512BW.VPADDW.meta,
    AVX512BW.VPSUBB.meta,
    AVX512BW.VPSUBW.meta,
    AVX512BW.VPCMPEQB.meta,
    AVX512BW.VPCMPEQW.meta,
    AVX512BW.VPCMPGTB.meta,
    AVX512BW.VPCMPGTW.meta,
    AVX512BW.VPMULLW.meta,
    AVX512BW.VPSUBSB.meta,
    AVX512BW.VPSUBSW.meta,
    AVX512BW.VPSUBUSB.meta,
    AVX512BW.VPSUBUSW.meta,
    AVX512BW.VMOVDQU8.meta,
    AVX512BW.VMOVDQU16.meta,
    AVX512BF16.VDPBF16PS.meta,
    VAES.AESDEC.meta,
    VAES.AESDECLAST.meta,
    VAES.AESENC.meta,
    VAES.AESENCLAST.meta,
    SYSTEM.LDTILECFG.meta,
    SYSTEM.LOADIWKEY.meta,
    SYSTEM.MOVDIR64B.meta,
};

pub fn tableCount() usize {
    return metas.len;
}

pub fn findByName(name: []const u8) ?types.InstructionMeta {
    for (metas) |meta| if (std.ascii.eqlIgnoreCase(meta.name, name)) return meta;
    return null;
}

pub fn validateAll() types.SafetyError!void {
    for (metas) |meta| try types.validateMeta(meta);
}

pub fn completedCount(features: types.FeatureSet) usize {
    var count: usize = 0;
    for (metas) |meta| {
        if (types.safetyReport(meta, features).ok()) count += 1;
    }
    return count;
}

pub fn progressPermille(features: types.FeatureSet) u16 {
    if (metas.len == 0) return 0;
    return @intCast((completedCount(features) * 1000) / metas.len);
}

pub fn validateRuntimeAbi(runtime_abi: anytype) void {
    runtime_abi.cleo.init();
    defer runtime_abi.cleo.deinit();

    const features = types.FeatureSet.cleoEmulated();
    for (metas) |meta| {
        const plan = meta.plan();
        runtime_abi.cleo.validateWideInstruction(.{
            .name = meta.name,
            .family = meta.family,
            .source_path = meta.source_path,
            .required_feature = @tagName(meta.required_feature),
            .operation = @tagName(meta.operation),
            .max_width_bits = meta.max_width_bits,
            .element_bits = meta.element_bits,
            .block_bits = plan.block_bits,
            .block_count = plan.block_count,
            .uses_neon_blocks = plan.uses_neon_blocks,
            .requires_scalar_fixup = plan.requires_scalar_fixup,
            .supports_masking = plan.supports_masking,
            .supports_broadcast = plan.supports_broadcast,
            .asm_template_present = meta.asm_template.len != 0,
        });
    }
    runtime_abi.cleo.validateRegistry(tableCount(), completedCount(features), progressPermille(features));
}

test "CLEO registry covers current wide ISA tables" {
    try std.testing.expectEqual(@as(usize, 245), tableCount());
    try validateAll();
    const all_features = types.FeatureSet.all();
    try std.testing.expectEqual(tableCount(), completedCount(all_features));
    try std.testing.expectEqual(@as(u16, 1000), progressPermille(all_features));
    const runtime_features = types.FeatureSet.cleoEmulated();
    try std.testing.expect(completedCount(runtime_features) <= tableCount());
    try std.testing.expect(progressPermille(runtime_features) <= 1000);
    try std.testing.expect(findByName("VADDPS") == null);
    try std.testing.expect(findByName("ADDPS") != null);
}
