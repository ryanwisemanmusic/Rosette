//! Reuse the ordinary private GPR cache. Wide variable shifts rely on ARM's
//! identical low-five/six-bit count masking. Flag outputs must be dead;
//! narrow/memory shifts and live flags retain the original implementation.
const core = @import("core.zig");
const a64 = @import("arm64_encode");
pub const Kind = enum(u2) { variable_shift, conversion, multiply };
const rcx: core.RegId = .cl_cx_ecx_rcx;
const rax: core.RegId = .al_ax_eax_rax;
const rdx: core.RegId = .dl_dx_edx_rdx;

pub fn emit(c: anytype, insn: core.Insn, _: u32) core.Error!?Kind {
    const d = insn.decoded;
    switch (d.op) {
        .shl_reg_cl, .shr_reg_cl, .sar_reg_cl, .rol_reg_cl, .ror_reg_cl => {
            if (c.emit_flags or (d.size != .bits32 and d.size != .bits64)) return null;
            const dst = c.cachedWhole(d.dst_reg, d.dst_high8, d.size) orelse return null;
            const width: a64.Width = if (d.size == .bits64) .x64 else .w32;
            const rotate = d.op == .rol_reg_cl or d.op == .ror_reg_cl;
            var count: a64.Reg = c.cachedWhole(rcx, false, .bits64) orelse blk: {
                try c.loadReg(10, rcx, false, .bits32);
                break :blk 10;
            };
            // A zero 32-bit rotate must preserve the destination's upper
            // half. A zero shift still performs its width-specific write.
            const done = try c.a.createLabel();
            if (rotate and d.size == .bits32) {
                try c.emit(a64.logicalImmediate(.w32, .andop, 11, count, 31).?);
                try c.a.branchIfZero(.w32, 11, done);
            }
            if (d.op == .rol_reg_cl) {
                try c.emit(a64.sub(.w32, 11, a64.wzr, count));
                count = 11;
            }
            try c.emit(switch (d.op) {
                .shl_reg_cl => a64.lslv(width, dst, dst, count),
                .shr_reg_cl => a64.lsrv(width, dst, dst, count),
                .sar_reg_cl => a64.asrv(width, dst, dst, count),
                else => a64.rorv(width, dst, dst, count),
            });
            c.a.placeLabel(done);
            c.noteDirectWrite(d.dst_reg);
            return .variable_shift;
        },
        .movzx_reg32_mem8, .movzx_reg32_mem16, .movsx_reg32_mem8, .movsx_reg32_mem16, .movsxd_reg64_reg32, .cdqe, .cdq, .cqo => {
            const extension = d.op == .movsxd_reg64_reg32 or d.op == .cdqe or d.op == .cdq or d.op == .cqo;
            if (!extension and !d.is_reg_form) return null;
            const dst_id = if (d.op == .cdqe) rax else if (d.op == .cdq or d.op == .cqo) rdx else d.dst_reg;
            const src_id = if (d.op == .cdqe or d.op == .cdq or d.op == .cqo) rax else d.src_reg;
            const size: core.Size = if (d.op == .movsxd_reg64_reg32 or d.op == .cdqe or d.op == .cqo) .bits64 else if (d.op == .cdq) .bits32 else d.size;
            if (size != .bits32 and size != .bits64) return null;
            const dst = c.cachedWhole(dst_id, false, size) orelse return null;
            const src = c.cachedWhole(src_id, false, .bits64) orelse return null;
            const width: a64.Width = if (size == .bits64) .x64 else .w32;
            const byte = d.op == .movzx_reg32_mem8 or d.op == .movsx_reg32_mem8;
            try c.emit(switch (d.op) {
                .movzx_reg32_mem8, .movzx_reg32_mem16 => a64.ubfx(.w32, dst, src, if (byte and d.src_high8) 8 else 0, if (byte) 8 else 16),
                .movsx_reg32_mem8, .movsx_reg32_mem16 => a64.sbfx(width, dst, src, if (byte and d.src_high8) 8 else 0, if (byte) 8 else 16),
                .cdq => a64.asrImm(.w32, dst, src, 31),
                .cqo => a64.asrImm(.x64, dst, src, 63),
                else => a64.sxtw(dst, src),
            });
            c.noteDirectWrite(dst_id);
            return .conversion;
        },
        .imul_reg32_reg32, .imul_reg64_reg64 => {
            if (c.emit_flags) return null;
            // These opcodes define the width, as in the original template.
            const size: core.Size = if (d.op == .imul_reg64_reg64) .bits64 else .bits32;
            const dst = c.cachedWhole(d.dst_reg, false, size) orelse return null;
            const src = c.cachedWhole(d.src_reg, false, size) orelse return null;
            try c.emit(a64.mul(if (size == .bits64) .x64 else .w32, dst, dst, src));
            c.noteDirectWrite(d.dst_reg);
            return .multiply;
        },
        else => return null,
    }
}
