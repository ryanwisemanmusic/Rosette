//! Pure VEX.128 rearrangements whose templates snapshot every input before
//! changing a destination. No memory, helper, legacy or wide form admitted.
const core = @import("core.zig");
pub fn candidate(d: core.DecodedInsn) bool {
    if (!d.is_reg_form or d.legacy_sse or d.vector_256 or d.vector_512 or d.is_evex) return false;
    return switch (d.op) {
        .vpshufb,
        .vpshufd,
        .vshufps,
        .vshufpd,
        .vpackssdw,
        .vpacksswb,
        .vpackuswb,
        .vpackusdw,
        .vpmaddwd,
        .vpmuludq,
        .vpblendw,
        .vinsertps,
        => true,
        else => false,
    };
}
