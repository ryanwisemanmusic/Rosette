//! Shorter templates for the memory forms Xenia's x64 output is made of,
//! where the general template moved every operand through temporaries.
//!
//! - `movbe r32/r64, [m]`: the byte swap lands in the guest register's cache
//!   (`rev w27, w0`) instead of `rev w10, w0 ; mov w10, w10 ; mov x27, x10`.
//! - `movbe [m], r32/r64`: swapped straight from the cache into x3.
//! - `add/sub/and/or/xor r, [m]` with dead flags: one ARM operation into
//!   the cached destination after the load, where the general template
//!   copied both operands to temporaries, computed, zero-extended and moved
//!   the result back (five instructions).
//! - `add/sub/and/or/xor/inc/dec [m], r/imm` with dead flags: computed from
//!   the loaded value straight into the store's x3.
//! - `[base + index]` with both registers cached and no displacement: one
//!   `add` instead of `add #0` and an `add` (`effectiveAddress`).
//!
//! Every access goes through the same `emitLoadOperand`/`emitStoreX3` and
//! abort check as the general template, in the same order: only register
//! moves around them go. Narrow destinations (8/16-bit merges), live
//! flags, `adc`/`sbb` and compares keep the general templates.
const core = @import("core.zig");
const a64 = @import("arm64_encode");

/// Offline control: false emits the general templates (the before side of
/// the benchmarks). Production leaves it on.
pub var enabled: bool = true;

/// Counts of compiled (not executed) uses, for the benchmarks.
pub var compiled: [5]u64 = @splat(0);
pub const Kind = enum(u3) { movbe_load, movbe_store, reg_mem, mem_update, address };

const x0: a64.Reg = 0;
const x3: a64.Reg = 3;
const t2: a64.Reg = 11;

fn note(kind: Kind) void {
    compiled[@intFromEnum(kind)] +%= 1;
}

fn width(size: core.Size) a64.Width {
    return if (size == .bits64) .x64 else .w32;
}

/// `dst = lhs op rhs` without flags for the four Group-1 operations it
/// can do in one instruction; false for any other.
fn emitOp(c: anytype, op: core.BinaryOp, w: a64.Width, dst: a64.Reg, lhs: a64.Reg, rhs: a64.Reg) core.Error!bool {
    try c.emit(switch (op) {
        .add => a64.add(w, dst, lhs, rhs),
        .sub => a64.sub(w, dst, lhs, rhs),
        .bit_and => a64.andReg(w, dst, lhs, rhs),
        .bit_or => a64.orrReg(w, dst, lhs, rhs),
        .bit_xor => a64.eorReg(w, dst, lhs, rhs),
        else => return false,
    });
    return true;
}

fn simpleOp(op: core.BinaryOp) bool {
    return switch (op) {
        .add, .sub, .bit_and, .bit_or, .bit_xor => true,
        else => false,
    };
}

/// `dst = lhs op imm` without flags, through t2 when the immediate does not
/// encode.
fn emitOpImm(c: anytype, op: core.BinaryOp, size: core.Size, dst: a64.Reg, lhs: a64.Reg, raw: u64) core.Error!void {
    const w = width(size);
    const mask = core.maskFor(size);
    const imm = raw & mask;
    switch (op) {
        .add, .sub => {
            const negated = (0 -% imm) & mask;
            const is_add = op == .add;
            if (imm <= 4095) {
                try c.emitChecked(if (is_add) a64.addImm(w, dst, lhs, imm) else a64.subImm(w, dst, lhs, imm));
            } else if (negated <= 4095) {
                try c.emitChecked(if (is_add) a64.subImm(w, dst, lhs, negated) else a64.addImm(w, dst, lhs, negated));
            } else {
                try c.a.loadConstant(t2, imm);
                try c.emit(if (is_add) a64.add(w, dst, lhs, t2) else a64.sub(w, dst, lhs, t2));
            }
        },
        .bit_and, .bit_or, .bit_xor => {
            const logical: a64.LogicalOp = switch (op) {
                .bit_and => .andop,
                .bit_or => .orr,
                else => .eor,
            };
            if (a64.logicalImmediate(w, logical, dst, lhs, imm)) |word| {
                try c.emit(word);
            } else {
                try c.a.loadConstant(t2, imm);
                try c.emit(a64.logicalShifted(w, logical, dst, lhs, t2, 0));
            }
        },
        else => unreachable,
    }
}

/// True when the instruction was emitted here.
pub fn emit(c: anytype, insn: core.Insn, index: u32) core.Error!bool {
    if (!enabled) return false;
    const d = insn.decoded;
    switch (d.op) {
        .movbe_reg_mem => {
            const dst = c.cachedWhole(d.dst_reg, false, d.size) orelse return false;
            try c.emitLoadOperand(insn, d.size, index);
            try c.emit(a64.rev(width(d.size), dst, x0));
            c.noteDirectWrite(d.dst_reg);
            try c.emitAbortCheck(index);
            note(.movbe_load);
            return true;
        },
        .movbe_mem_reg => {
            if (d.size != .bits32 and d.size != .bits64) return false;
            const src = c.cachedWhole(d.src_reg, false, d.size) orelse return false;
            try c.emit(a64.rev(width(d.size), x3, src));
            try c.emitStoreX3Last(insn, d.size, index, true);
            try c.emitAbortCheck(index);
            note(.movbe_store);
            return true;
        },
        else => {},
    }
    if (c.emit_flags or d.lock) return false;
    if (core.isIncDec(d.op)) |form| {
        if (!form.mem) return false;
        const size = core.incDecSize(d.op);
        try c.emitLoadOperand(insn, size, index);
        // Only the low `size` bytes are stored, so a narrow form needs no mask.
        const w = width(size);
        try c.emitChecked(if (form.inc) a64.addImm(w, x3, x0, 1) else a64.subImm(w, x3, x0, 1));
        try c.emitStoreX3(insn, size, index);
        try c.emitAbortCheck(index);
        note(.mem_update);
        return true;
    }
    const op = core.binaryOpOf(d.op) orelse return false;
    if (!simpleOp(op)) return false;
    switch (core.binaryShapeOf(d.op)) {
        .reg_mem => {
            const dst = c.cachedWhole(d.dst_reg, d.dst_high8, d.size) orelse return false;
            try c.emitLoadOperand(insn, d.size, index);
            _ = try emitOp(c, op, width(d.size), dst, dst, x0);
            c.noteDirectWrite(d.dst_reg);
            try c.emitAbortCheck(index);
            note(.reg_mem);
            return true;
        },
        .mem_reg => {
            // A byte register operand may be AH..BH; leave those to the
            // general template.
            if (d.src_high8) return false;
            try c.emitLoadOperand(insn, d.size, index);
            const src = c.cachedRegister(d.src_reg) orelse blk: {
                try c.loadReg(t2, d.src_reg, false, d.size);
                break :blk t2;
            };
            _ = try emitOp(c, op, if (d.size == .bits64) .x64 else .w32, x3, x0, src);
            try c.emitStoreX3(insn, d.size, index);
            try c.emitAbortCheck(index);
            note(.mem_update);
            return true;
        },
        .mem_imm => {
            try c.emitLoadOperand(insn, d.size, index);
            try emitOpImm(c, op, if (d.size == .bits64) .bits64 else .bits32, x3, x0, core.immediateValue(d));
            try c.emitStoreX3(insn, d.size, index);
            try c.emitAbortCheck(index);
            note(.mem_update);
            return true;
        },
        else => return false,
    }
}

/// `dst = base + index << scale` in one instruction when both are cached,
/// there is no displacement, no 0x67 truncation and no segment base.
pub fn effectiveAddress(c: anytype, dst: a64.Reg, insn: core.Insn) core.Error!bool {
    if (!enabled) return false;
    const d = insn.decoded;
    if (!d.sib_has_base or !d.sib_has_index or d.rip_relative or d.addr != 0 or d.has_0x67) return false;
    switch (insn.segment) {
        .fs, .gs => return false,
        else => {},
    }
    const base = c.cachedRegister(d.sib_base_reg) orelse return false;
    const index = c.cachedRegister(d.sib_index_reg) orelse return false;
    try c.emit(a64.addSubShifted(.x64, .add, false, dst, base, index, d.sib_scale));
    note(.address);
    return true;
}
