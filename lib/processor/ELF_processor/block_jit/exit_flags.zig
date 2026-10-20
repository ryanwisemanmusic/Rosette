//! A fused writer's flags left as a record on the way out of a block.
//!
//! Xenia compiles every PowerPC compare-and-branch to a `cmp` or `test` and
//! a `jcc`. The translator answers the branch from NZCV, but an edge that
//! leaves the block owes all six x86 flags to whatever runs next, and paid
//! for them there: a parity fold, the zero, sign, carry and overflow bits,
//! a load and a store of `rflags` - about eighteen instructions on every
//! such exit. The block that runs next almost always overwrites every flag
//! before it reads one.
//!
//! So an exit edge stores the writer's operands, result, kind and size in
//! the scratch record instead (three or four instructions), and every block
//! begins by dealing with a record its predecessor may have left: a block
//! that writes all six flags before it reads any clears it (one store); any
//! other block settles it first, through the existing helper, out of line.
//! The record therefore never lives inside a block, and nothing in a block
//! changes. Leaving a chain settles it as before (the epilogue's completion),
//! and the interpreter never sees one.
//!
//! Not for `inc`/`dec` (CF is not theirs), a run whose operands were saved
//! for a memory reader, blocks whose exits owe exact flags (the cross-checked
//! register-only blocks), or resident loops, which re-enter their own body
//! past the entry.
const core = @import("core.zig");
const a64 = @import("arm64_encode");

/// Offline control: false materialises the flags at every exit, as before.
pub var enabled: bool = true;
/// Exit edges compiled to leave a record (not executions), for benchmarks.
pub var compiled_records: u64 = 0;

/// Where the record lives in the scratch, and the helper that settles it.
pub const Offsets = struct { kind: u32, a: u32, r: u32, helper: u32, scratch: a64.Reg, helpers: a64.Reg, state: a64.Reg };

const t0: a64.Reg = 9;
const t3: a64.Reg = 12;
const t4: a64.Reg = 13;

/// The fall-through of the jcc at `index` leaves the block straight away:
/// the jcc is the last instruction, or only a direct `jmp` follows it.
pub fn finalEdge(insns: []const core.Insn, index: usize) bool {
    if (index + 1 == insns.len) return true;
    return index + 2 == insns.len and insns[index + 1].decoded.op == .jmp_rel8 and !insns[index + 1].force_fallback;
}

/// Exits of this kind may leave a record.
pub fn deferrable(c: anytype, fused: core.Fused, owed: u8) bool {
    if (!enabled or owed == 0 or fused.saved or c.exact_exit_flags or c.resident_loop != null) return false;
    return switch (fused.kind) {
        .add, .sub, .logic => true,
        .inc, .dec => false,
    };
}

/// The record of `a op b = r`: operands where the run keeps them, the result
/// in t0, kind and size in one halfword. `flags.apply*` masks each value at
/// the size, so cached 64-bit registers can be stored as they are.
pub fn emitRecord(c: anytype, fused: core.Fused, o: Offsets) core.Error!void {
    const kind: core.FlagKind = switch (fused.kind) {
        .add => .add,
        .sub => .sub,
        .logic => .logic,
        .inc, .dec => unreachable,
    };
    if (kind != .logic) {
        var b = fused.b_reg;
        if (fused.b_imm) |imm| {
            try c.a.loadConstant(t4, imm);
            b = t4;
        }
        try c.emitChecked(a64.stp(.signed_offset, fused.a_reg, b, o.scratch, @intCast(o.a)));
    }
    try c.emitChecked(a64.strImm(.doubleword, t0, o.scratch, o.r));
    const code: u64 = @as(u64, @intFromEnum(kind)) | @as(u64, @intFromEnum(fused.size)) << 8;
    try c.a.loadConstant(t3, code);
    try c.emitChecked(a64.strImm(.half, t3, o.scratch, o.kind));
    compiled_records +%= 1;
}

/// At the chain entry, before the register cache is loaded: nothing but the
/// frame and the pinned pointers is live, so the helper is called bare.
pub fn emitEntry(a: anytype, live_in: u8, o: Offsets) core.Error!void {
    if (!enabled) return;
    if (live_in == 0) {
        // Every flag is written before any is read: a record left by the
        // block before describes nothing anyone will see.
        try a.emit(a64.strImm(.byte, a64.wzr, o.scratch, o.kind).?);
        return;
    }
    const settle = try a.createLabel();
    const back = try a.createLabel();
    try a.emit(a64.ldrImm(.byte, t0, o.scratch, o.kind).?);
    try a.branchIfNonZero(.w32, t0, settle);
    const section = a.section;
    a.section = .cold;
    a.placeLabel(settle);
    try a.emit(a64.mov(.x64, 0, o.state));
    try a.emit(a64.ldrImm(.doubleword, t0, o.helpers, o.helper).?);
    try a.emit(a64.blr(t0));
    try a.branch(back);
    a.section = section;
    a.placeLabel(back);
}
