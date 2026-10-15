//! Guarded scalar completion: existing register DIV/IDIV plus memory DIV32.
//! Zero divisors and dividends outside the existing fast contract retain the
//! original interpreter path. Native memory reads use the ordinary TLB helper.
const core = @import("core.zig");
const a64 = @import("arm64_encode");
const Size = core.Size;
const t0: a64.Reg = 9;
const t1: a64.Reg = 10;
const t2: a64.Reg = 11;
const t4: a64.Reg = 13;
const t5: a64.Reg = 14;
fn arm(size: Size) a64.Width {
    return if (size == .bits64) .x64 else .w32;
}
fn bits(size: Size) u8 {
    return if (size == .bits64) 64 else 32;
}
pub fn divide(self: anytype, insn: core.Insn, index: u32) core.Error!void {
    const d = insn.decoded;
    const size: Size = switch (d.op) {
        .div_reg32, .idiv_reg32, .div_mem32 => .bits32,
        else => .bits64,
    };
    const signed = d.op == .idiv_reg32 or d.op == .idiv_reg64;
    const width = arm(size);
    const w = bits(size);
    const slow = try self.a.createLabel();
    const done = try self.a.createLabel();
    if (d.op == .div_mem32) {
        try self.emitLoadOperand(insn, size, index);
        try self.emitAbortCheck(index);
        try self.emit(a64.mov(.w32, t2, 0));
    } else try self.loadReg(t2, d.src_reg, false, size);
    try self.a.branchIfZero(width, t2, slow);
    try self.loadReg(t1, .al_ax_eax_rax, false, size);
    try self.loadReg(t4, .dl_dx_edx_rdx, false, size);
    if (signed) {
        try self.emitChecked(a64.addSubImmediate(width, .add, true, a64.xzr, t2, 1)); // cmn t2, #1
        try self.a.branchCond(.eq, slow);
        try self.emit(a64.asrImm(width, t5, t1, @intCast(w - 1)));
        try self.emit(a64.cmp(width, t5, t4));
        try self.a.branchCond(.ne, slow);
        try self.emit(a64.sdiv(width, t0, t1, t2));
    } else {
        try self.a.branchIfNonZero(width, t4, slow);
        try self.emit(a64.udiv(width, t0, t1, t2));
    }
    try self.emit(a64.msub(width, t4, t0, t2, t1));
    try self.storeReg(.al_ax_eax_rax, false, size, t0);
    try self.storeReg(.dl_dx_edx_rdx, false, size, t4);
    try self.a.branch(done);
    self.a.placeLabel(slow);
    try self.emitFallback(index);
    self.a.placeLabel(done);
}

pub fn cwde(self: anytype) core.Error!void {
    try self.loadReg(t1, .al_ax_eax_rax, false, .bits16);
    try self.emit(a64.sxth(.w32, t1, t1));
    try self.storeReg(.al_ax_eax_rax, false, .bits32, t1);
}
