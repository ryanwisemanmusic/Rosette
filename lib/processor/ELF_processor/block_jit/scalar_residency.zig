//! Pure VEX.128 scalar arithmetic can use the existing private XMM cache.
//! Memory, legacy, wide and observer boundaries retain ordinary publication.
const core = @import("core.zig");
const a64 = @import("arm64_encode");
pub fn candidate(d: core.DecodedInsn) bool {
    if (!d.is_reg_form or d.legacy_sse or d.vector_256 or d.vector_512 or d.is_evex) return false;
    return switch (d.op) {
        .vaddss, .vsubss, .vmulss, .vdivss, .vminss, .vmaxss, .vaddsd, .vsubsd, .vmulsd, .vdivsd, .vminsd, .vmaxsd => true,
        else => false,
    };
}
pub fn emit(self: anytype, insn: core.Insn, index: u32, form: anytype, result: a64.Reg) core.Error!void {
    var lhs: a64.Reg = 1;
    var rhs: a64.Reg = 2;
    if (insn.decoded.is_reg_form) {
        if (self.resident_vectors and self.forward_xmm) self.scalar_resident_ops += 1;
        const operands = try self.vectorOperands(insn, index);
        lhs = operands.lhs;
        rhs = operands.rhs;
    }
    switch (form.kind) {
        .add => try self.emit(a64.fadd(form.fp, 3, lhs, rhs)),
        .sub => try self.emit(a64.fsub(form.fp, 3, lhs, rhs)),
        .mul => try self.emit(a64.fmul(form.fp, 3, lhs, rhs)),
        .div => try self.emit(a64.fdiv(form.fp, 3, lhs, rhs)),
        .min => {
            try self.emit(a64.fcmp(form.fp, lhs, rhs));
            try self.emit(a64.fcsel(form.fp, 3, lhs, rhs, .mi));
        },
        .max => {
            try self.emit(a64.fcmp(form.fp, lhs, rhs));
            try self.emit(a64.fcsel(form.fp, 3, lhs, rhs, .gt));
        },
    }
    if (result != lhs) try self.emit(a64.vmov(result, lhs));
    try self.emit(a64.vinsLane(if (form.fp == .single) .s4 else .d2, result, 0, 3, 0));
    try self.storeXmm(insn.decoded.xmm_dst, result);
    try self.clearUpper(insn.decoded.xmm_dst, insn.decoded.op);
    if (!insn.decoded.is_reg_form) try self.emitAbortCheck(index);
}
