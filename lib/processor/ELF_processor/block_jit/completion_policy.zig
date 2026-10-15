//! Newly native forms; used only to select the old interpreter in offline proofs.
const Op = @import("core.zig").Op;
pub fn contains(op: Op) bool {
    return switch (op) {
        .cwde, .div_mem32, .movaps_xmm_mem, .movaps_mem_xmm, .vpmaddwd => true,
        else => false,
    };
}
