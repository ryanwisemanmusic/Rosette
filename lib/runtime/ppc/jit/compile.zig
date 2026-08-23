//! PowerPC to ARM64 block compilation.
//!
//! This is the third pipeline stage the direct path can run in. The first two
//! are decode (ISA/ppc/decode) and interpretation (lib/runtime/ppc); this one
//! removes the interpreter's per-instruction overhead - fetch, decode, dispatch
//! through a switch, and construct an outcome - by emitting ARM64 that performs
//! the same architected state changes directly.
//!
//! What it does *not* do is allocate registers. Guest state stays in the
//! `State` struct in memory and every instruction loads its operands and stores
//! its result, exactly as the interpreter does. That is a deliberate v1 choice:
//! a register allocator is where a recompiler stops being verifiable by
//! inspection, and the dispatch overhead it would not remove is the larger term
//! to begin with. The load/store traffic it leaves behind is L1-resident.
//!
//! ## The compiled subset
//!
//! Integer arithmetic, logical operations, shifts, rotates, compares, and the
//! displacement and indexed load/store forms. Anything else *ends the block*:
//! the compiler stops, the block returns, and the interpreter executes the next
//! instruction before the next block starts. That keeps the compiler's
//! correctness argument small - every instruction it emits, it emits fully -
//! and it is why `compile` returning a short block is a normal outcome rather
//! than a failure.
//!
//! ## Calling convention
//!
//! A compiled block is `fn (state, membase, memlen, exit) callconv(.c) void`.
//! It calls nothing, so it needs no prologue, no frame, and no callee-saved
//! registers: x0-x3 hold the arguments for the life of the block and x9-x17 are
//! scratch. The absence of a prologue is not a micro-optimisation - it is what
//! makes the emitted code auditable as a flat sequence.
//!
//! ## Reservations
//!
//! `lwarx`/`stwcx.` are not compiled, so a reservation can only be established
//! outside a block. A store inside a block still has to break one that covers
//! its address, and the check is emitted inline: two instructions on the common
//! path where no reservation is held, five more when one is. Skipping it would
//! let a guest's lock loop observe a successful `stwcx.` across a conflicting
//! store, which is the one failure mode a spin lock cannot recover from.

const std = @import("std");
const a64 = @import("arm64_encode");
const ppc_decode = @import("ppc_decode");
const state_mod = @import("../state.zig");
const asm_mod = @import("assembler.zig");

const Assembler = asm_mod.Assembler;
const Label = asm_mod.Label;
const State = state_mod.State;
const Op = ppc_decode.Op;
const Instruction = ppc_decode.Instruction;
const fields = ppc_decode.fields;

pub const Error = asm_mod.Error || error{NothingToCompile};

/// Why a compiled block returned.
pub const ExitReason = enum(u32) {
    /// The block ran to its end. `address` is where the interpreter resumes.
    fallthrough = 0,
    /// A guest memory access was out of range. `address` is the instruction
    /// that faulted, and no architected state was changed by it.
    memory_fault = 1,
};

/// The record a block fills in before returning.
pub const BlockExit = extern struct {
    reason: u32 = 0,
    address: u32 = 0,
    retired: u32 = 0,
    reserved: u32 = 0,
};

pub const BlockFn = *const fn (
    state: *State,
    membase: [*]u8,
    memlen: u64,
    exit: *BlockExit,
) callconv(.c) void;

// ---------------------------------------------------------------------------
// Register assignment inside a compiled block
// ---------------------------------------------------------------------------

/// Guest register file.
const r_state: a64.Reg = 0;
/// Base of guest memory: `membase[guest_address]`.
const r_membase: a64.Reg = 1;
/// Size of guest memory in bytes.
const r_memlen: a64.Reg = 2;
/// Where to write the exit record.
const r_exit: a64.Reg = 3;

// Scratch. Nothing outlives one instruction except through `State`.
const t0: a64.Reg = 9;
const t1: a64.Reg = 10;
const t2: a64.Reg = 11;
const t3: a64.Reg = 12;
const t4: a64.Reg = 13;

const gpr_base = @offsetOf(State, "gpr");
const fpr_base = @offsetOf(State, "fpr");
const cr_offset = @offsetOf(State, "cr");
const lr_offset = @offsetOf(State, "lr");
const ctr_offset = @offsetOf(State, "ctr");
const xer_ca_offset = @offsetOf(State, "xer") + @offsetOf(state_mod.Xer, "ca");
const xer_so_offset = @offsetOf(State, "xer") + @offsetOf(state_mod.Xer, "so");
const fpscr_offset = @offsetOf(State, "fpscr");
const pc_offset = @offsetOf(State, "pc");
const retired_offset = @offsetOf(State, "instructions_retired");
const reservation_offset = @offsetOf(State, "reservation");
const res_valid_offset = reservation_offset + @offsetOf(state_mod.Reservation, "valid");
const res_address_offset = reservation_offset + @offsetOf(state_mod.Reservation, "address");

/// A compiled block, ready to run.
pub const Block = struct {
    /// First guest instruction the block covers.
    guest_start: u32,
    /// One past the last guest instruction the block covers.
    guest_end: u32,
    /// Guest instructions compiled into it.
    instruction_count: u32,
    /// The executable code, in the code cache.
    code: []const u32,

    pub fn entry(self: Block) BlockFn {
        return @ptrCast(self.code.ptr);
    }
};

/// True when `op` is one the compiler emits code for. Anything else ends a
/// block; that is the normal way a block terminates, not an error.
pub fn isCompilable(insn: Instruction) bool {
    // The overflow-enable and record forms of the arithmetic instructions need
    // XER.OV and CR0 respectively. CR0 is emitted; XER.OV is not, so an OE
    // instruction ends the block rather than being compiled without its
    // side effect.
    if (insn.oe()) return false;
    return switch (insn.op) {
        .addi,
        .addis,
        .addx,
        .subfx,
        .negx,
        .mulli,
        .mullwx,
        .mulldx,
        .andx,
        .andcx,
        .orx,
        .orcx,
        .xorx,
        .nandx,
        .norx,
        .eqvx,
        .andix,
        .andisx,
        .ori,
        .oris,
        .xori,
        .xoris,
        .extsbx,
        .extshx,
        .extswx,
        .cntlzwx,
        .cntlzdx,
        .slwx,
        .srwx,
        .sldx,
        .srdx,
        .srawix,
        .rlwinmx,
        .rlwimix,
        .rldiclx,
        .rldicrx,
        .cmp,
        .cmpl,
        .cmpi,
        .cmpli,
        .lbz,
        .lhz,
        .lha,
        .lwz,
        .ld,
        .lwa,
        .stb,
        .sth,
        .stw,
        .std,
        .lbzx,
        .lhzx,
        .lhax,
        .lwzx,
        .lwax,
        .ldx,
        .stbx,
        .sthx,
        .stwx,
        .stdx,
        => true,
        .bx,
        .bcx,
        .bclrx,
        .bcctrx,
        .lfs,
        .lfsu,
        .lfsx,
        .lfsux,
        .lfd,
        .lfdu,
        .lfdx,
        .lfdux,
        .stfs,
        .stfsu,
        .stfsx,
        .stfsux,
        .stfd,
        .stfdu,
        .stfdx,
        .stfdux,
        .faddx,
        .faddsx,
        .fsubx,
        .fsubsx,
        .fmulx,
        .fmulsx,
        .fdivx,
        .fdivsx,
        .fsqrtx,
        .fsqrtsx,
        .fmaddx,
        .fmaddsx,
        .fmsubx,
        .fmsubsx,
        .fnmaddx,
        .fnmaddsx,
        .fnmsubx,
        .fnmsubsx,
        .fmrx,
        .fnegx,
        .fabsx,
        .fnabsx,
        .frspx,
        => true,
        else => false,
    };
}

fn isCompiledBranch(insn: Instruction) bool {
    return switch (insn.op) {
        .bx, .bcx, .bclrx, .bcctrx => true,
        else => false,
    };
}

const Compiler = struct {
    a: *Assembler,
    /// Guest instructions emitted so far, for the retired count and the fault
    /// stubs' view of how far the block got.
    retired: u32 = 0,
    /// Whether any store was emitted; drives the reservation check.
    fault_stubs: std.ArrayList(FaultStub),
    allocator: std.mem.Allocator,

    const FaultStub = struct {
        label: Label,
        address: u32,
        retired: u32,
    };

    fn gprOffset(reg: u5) u32 {
        return @intCast(gpr_base + @as(u32, reg) * 8);
    }

    fn loadGpr(self: *Compiler, dst: a64.Reg, reg: u5) Error!void {
        try self.a.emit(a64.ldrImm(.doubleword, dst, r_state, gprOffset(reg)).?);
    }

    /// Load rA, or a literal zero when the encoding means "no base register".
    fn loadGprOrZero(self: *Compiler, dst: a64.Reg, reg: u5) Error!void {
        if (reg == 0) {
            try self.a.emit(a64.mov(.x64, dst, a64.xzr));
        } else {
            try self.loadGpr(dst, reg);
        }
    }

    fn storeGpr(self: *Compiler, reg: u5, src: a64.Reg) Error!void {
        try self.a.emit(a64.strImm(.doubleword, src, r_state, gprOffset(reg)).?);
    }

    fn fprOffset(reg: u5) u32 {
        return @intCast(fpr_base + @as(u32, reg) * @sizeOf(f64));
    }

    fn loadFpr(self: *Compiler, dst: a64.Reg, reg: u5) Error!void {
        try self.a.emit(a64.ldrFpImm(.double, dst, r_state, fprOffset(reg)).?);
    }

    fn storeFpr(self: *Compiler, reg: u5, src: a64.Reg) Error!void {
        try self.a.emit(a64.strFpImm(.double, src, r_state, fprOffset(reg)).?);
    }

    /// Keep the PPC FPR representation canonical: even a single-precision
    /// instruction leaves an f64 value in State.fpr, rounded through the
    /// single-precision format rather than leaving a raw four-byte register
    /// half in the state slot.
    fn widenSingle(self: *Compiler, dst: a64.Reg, src: a64.Reg) Error!void {
        try self.a.emit(a64.fcvtDouble(dst, src));
    }

    /// Update the result-class field of FPSCR. Arithmetic and conversion
    /// instructions in the interpreter expose this field even when Rc=0. The
    /// host FP instructions provide the ordered comparison flags; V is the
    /// unordered/NaN indication, so the final csel gives NaN priority over the
    /// equality flag ARM also reports for an unordered compare.
    fn emitFprf(self: *Compiler, value: a64.Reg) Error!void {
        try self.a.loadConstant(t4, 0);
        try self.a.emit(a64.fmovFromGpr(3, t4));
        try self.a.emit(a64.fcmp(.double, value, 3));
        try self.a.loadConstant(t2, 8); // negative
        try self.a.loadConstant(t3, 4); // positive
        try self.a.emit(a64.csel(.w32, t2, t2, t3, .lt));
        try self.a.loadConstant(t3, 2); // zero
        try self.a.emit(a64.csel(.w32, t2, t3, t2, .eq));
        try self.a.loadConstant(t3, 1); // NaN/unordered
        try self.a.emit(a64.csel(.w32, t2, t3, t2, .vs));
        try self.a.emit(a64.ldrImm(.word, t3, r_state, fpscr_offset).?);
        try self.a.emit(a64.bfi(.w32, t3, t2, 12, 4));
        try self.a.emit(a64.strImm(.word, t3, r_state, fpscr_offset).?);
    }

    fn emitCr1IfRc(self: *Compiler, insn: Instruction) Error!void {
        if (!insn.rc()) return;
        try self.a.emit(a64.ldrImm(.word, t1, r_state, fpscr_offset).?);
        try self.a.emit(a64.lsrImm(.w32, t1, t1, 28));
        try self.andConstant(t1, t1, 0xF);
        try self.emitCrFieldWrite(1, t1);
    }

    /// Set a sticky FPSCR bit when the flags from the preceding FP compare
    /// satisfy `condition`. The interpreter's divide-by-zero path needs this
    /// for normal finite operands; the sticky FX bit follows it.
    fn emitStickyFpscrBit(self: *Compiler, condition: a64.Cond, bit: u5) Error!void {
        const flag_mask = (@as(u32, 1) << @as(u5, @intCast(31 - @as(u32, bit)))) | (@as(u32, 1) << 31);
        try self.a.loadConstant(t2, flag_mask);
        try self.a.emit(a64.csel(.w32, t2, t2, a64.wzr, condition));
        try self.a.emit(a64.ldrImm(.word, t3, r_state, fpscr_offset).?);
        try self.a.emit(a64.orrReg(.w32, t3, t3, t2));
        try self.a.emit(a64.strImm(.word, t3, r_state, fpscr_offset).?);
    }

    /// Add a 64-bit constant to `dst`, using an immediate form when one exists.
    fn addConstant(self: *Compiler, dst: a64.Reg, src: a64.Reg, value: i64) Error!void {
        if (value == 0) {
            if (dst != src) try self.a.emit(a64.mov(.x64, dst, src));
            return;
        }
        if (value > 0) {
            if (a64.addImm(.x64, dst, src, @intCast(value))) |word| {
                try self.a.emit(word);
                return;
            }
        } else {
            const magnitude: u64 = @intCast(-value);
            if (a64.subImm(.x64, dst, src, magnitude)) |word| {
                try self.a.emit(word);
                return;
            }
        }
        try self.a.loadConstant(t4, @bitCast(value));
        try self.a.emit(a64.add(.x64, dst, src, t4));
    }

    /// AND `dst` with a 64-bit mask, materialising it when it has no bitmask
    /// encoding.
    fn andConstant(self: *Compiler, dst: a64.Reg, src: a64.Reg, mask: u64) Error!void {
        if (a64.logicalImmediate(.x64, .andop, dst, src, mask)) |word| {
            try self.a.emit(word);
            return;
        }
        try self.a.loadConstant(t4, mask);
        try self.a.emit(a64.andReg(.x64, dst, src, t4));
    }

    /// Write CR0 from a result already in `value`, as Rc=1 requires.
    ///
    /// The comparison is against zero as a *signed 64-bit* value, and the SO
    /// bit comes from XER rather than from the comparison, which is why this
    /// cannot be folded into whatever flags the operation happened to leave.
    fn emitCr0(self: *Compiler, value: a64.Reg) Error!void {
        try self.a.emit(a64.cmpImm(.x64, value, 0).?);
        try self.a.emit(a64.cset(.w32, t2, .lt));
        try self.a.emit(a64.lslImm(.w32, t2, t2, 3));
        try self.a.emit(a64.cset(.w32, t3, .gt));
        try self.a.emit(a64.logicalShifted(.w32, .orr, t2, t2, t3, 2));
        try self.a.emit(a64.cset(.w32, t3, .eq));
        try self.a.emit(a64.logicalShifted(.w32, .orr, t2, t2, t3, 1));
        try self.a.emit(a64.ldrImm(.byte, t3, r_state, xer_so_offset).?);
        try self.a.emit(a64.orrReg(.w32, t2, t2, t3));
        try self.emitCrFieldWrite(0, t2);
    }

    /// Insert a four-bit field value into the packed CR word. Field 0 is at the
    /// *high* end, so the bit position counts down.
    fn emitCrFieldWrite(self: *Compiler, field: u3, value: a64.Reg) Error!void {
        try self.a.emit(a64.ldrImm(.word, t1, r_state, cr_offset).?);
        const lsb: u6 = @intCast((7 - @as(u32, field)) * 4);
        try self.a.emit(a64.bfi(.w32, t1, value, lsb, 4));
        try self.a.emit(a64.strImm(.word, t1, r_state, cr_offset).?);
    }

    fn recordIfRc(self: *Compiler, insn: Instruction, value: a64.Reg) Error!void {
        if (insn.rc()) try self.emitCr0(value);
    }

    // -- memory -------------------------------------------------------------

    /// Compute an effective address into t0, wrapped to the 32-bit guest space.
    fn emitEffectiveAddress(self: *Compiler, insn: Instruction, indexed: bool) Error!void {
        if (indexed) {
            const f = insn.x();
            try self.loadGprOrZero(t0, f.ra());
            try self.loadGpr(t1, f.rb());
            try self.a.emit(a64.add(.x64, t0, t0, t1));
        } else {
            const f = insn.d();
            try self.loadGprOrZero(t0, f.ra());
            try self.addConstant(t0, t0, immediateDisplacement(insn));
        }
        // The Xbox 360 address space is 32-bit; a computation that carried into
        // the high half would address memory the guest cannot name.
        try self.a.emit(a64.mov(.w32, t0, t0));
    }

    /// Emit the bounds check, branching to a fault stub for `address` when the
    /// access would leave the mapping.
    fn emitBoundsCheck(self: *Compiler, address: u32, size: u32) Error!void {
        const stub = try self.a.createLabel();
        try self.fault_stubs.append(self.allocator, .{
            .label = stub,
            .address = address,
            .retired = self.retired,
        });
        try self.a.emit(a64.addImm(.x64, t1, t0, size).?);
        try self.a.emit(a64.cmp(.x64, t1, r_memlen));
        try self.a.branchCond(.hi, stub);
    }

    /// The displacement of a non-indexed memory instruction.
    ///
    /// `ld`, `lwa`, and `std` are DS-form: their displacement is fourteen bits
    /// scaled by four, and the low two bits of the field carry the extended
    /// opcode. Reading them as a D-form sixteen-bit displacement produces an
    /// address that is right whenever the opcode bits happen to be zero, which
    /// is exactly half the time.
    fn immediateDisplacement(insn: Instruction) i64 {
        return switch (insn.op) {
            .ld, .lwa, .std => insn.ds().dsField(),
            else => insn.d().simm(),
        };
    }

    /// Break a reservation that covers the address in t0.
    ///
    /// The common case is no reservation at all, which costs a load and a
    /// not-taken branch. The rest only runs when the guest is between an
    /// `lwarx` and its `stwcx.`.
    fn emitBreakReservation(self: *Compiler) Error!void {
        const done = try self.a.createLabel();
        try self.a.emit(a64.ldrImm(.byte, t2, r_state, res_valid_offset).?);
        try self.a.branchIfZero(.w32, t2, done);
        try self.a.emit(a64.ldrImm(.word, t3, r_state, res_address_offset).?);
        // The reservation covers a whole cache block.
        // The mask is a 32-bit bitmask immediate, so it has to be expressed in
        // 32 bits: the 64-bit complement of 127 has no 32-bit encoding.
        try self.a.emit(a64.logicalImmediate(.w32, .andop, t2, t0, ~@as(u32, 127)).?);
        try self.a.emit(a64.cmp(.w32, t2, t3));
        try self.a.branchCond(.ne, done);
        try self.a.emit(a64.strImm(.byte, a64.wzr, r_state, res_valid_offset).?);
        self.a.placeLabel(done);
    }

    const LoadShape = struct {
        size: a64.MemSize,
        /// Bytes the access touches, for the bounds check.
        bytes: u32,
        /// How to turn the loaded big-endian value into the architected result.
        conversion: enum { none, swap16_zero, swap16_sign, swap32_zero, swap32_sign, swap64 },
    };

    fn emitLoad(self: *Compiler, insn: Instruction, indexed: bool, shape: LoadShape) Error!void {
        const rt = if (indexed) insn.x().rt() else insn.d().rt();
        try self.emitEffectiveAddress(insn, indexed);
        try self.emitBoundsCheck(insn.address, shape.bytes);
        try self.a.emit(a64.ldrReg(shape.size, t1, r_membase, t0));
        switch (shape.conversion) {
            .none => {},
            .swap16_zero => try self.a.emit(a64.rev16(.w32, t1, t1)),
            .swap16_sign => {
                try self.a.emit(a64.rev16(.w32, t1, t1));
                try self.a.emit(a64.sxth(.x64, t1, t1));
            },
            .swap32_zero => try self.a.emit(a64.rev(.w32, t1, t1)),
            .swap32_sign => {
                try self.a.emit(a64.rev(.w32, t1, t1));
                try self.a.emit(a64.sxtw(t1, t1));
            },
            .swap64 => try self.a.emit(a64.rev(.x64, t1, t1)),
        }
        try self.storeGpr(rt, t1);
    }

    fn emitStore(self: *Compiler, insn: Instruction, indexed: bool, shape: LoadShape) Error!void {
        const rs = if (indexed) insn.x().rs() else insn.d().rs();
        // The data goes in t3, not t1: the effective-address computation and
        // the bounds check both use t1 as scratch, and holding the store data
        // there would write whatever the address arithmetic left behind.
        try self.loadGpr(t3, rs);
        try self.emitEffectiveAddress(insn, indexed);
        try self.emitBoundsCheck(insn.address, shape.bytes);
        switch (shape.conversion) {
            .none => {},
            .swap16_zero, .swap16_sign => try self.a.emit(a64.rev16(.w32, t3, t3)),
            .swap32_zero, .swap32_sign => try self.a.emit(a64.rev(.w32, t3, t3)),
            .swap64 => try self.a.emit(a64.rev(.x64, t3, t3)),
        }
        try self.a.emit(a64.strReg(shape.size, t3, r_membase, t0));
        // Safe to reuse t3 now: the store has consumed it.
        try self.emitBreakReservation();
    }

    // -- scalar floating point ---------------------------------------------

    fn emitFloatLoad(self: *Compiler, insn: Instruction, indexed: bool, single: bool, update: bool) Error!void {
        const fd = if (indexed) insn.x().fd() else insn.d().fd();
        const ra = if (indexed) insn.x().ra() else insn.d().ra();
        try self.emitEffectiveAddress(insn, indexed);
        try self.emitBoundsCheck(insn.address, if (single) 4 else 8);
        // PPC memory is big-endian while the host scalar loads are little-
        // endian. Read through a GPR, reverse the guest byte order, then move
        // the exact bits into the FP register. The scalar FP encoder
        // intentionally only exposes immediate forms; t1 is the host pointer
        // and t0 remains the guest address for update-form writeback.
        try self.a.emit(a64.add(.x64, t1, r_membase, t0));
        try self.a.emit(a64.ldrImm(if (single) .word else .doubleword, t2, t1, 0).?);
        try self.a.emit(a64.rev(if (single) .w32 else .x64, t2, t2));
        try self.a.emit(a64.fmovFromGpr(0, t2));
        if (single) {
            try self.a.emit(a64.fcvtDouble(0, 0));
        }
        try self.storeFpr(fd, 0);
        if (update) try self.storeGpr(ra, t0);
    }

    fn emitFloatStore(self: *Compiler, insn: Instruction, indexed: bool, single: bool, update: bool) Error!void {
        const fs = if (indexed) insn.x().fs() else insn.d().fs();
        const ra = if (indexed) insn.x().ra() else insn.d().ra();
        try self.loadFpr(0, fs);
        if (single) try self.a.emit(a64.fcvtSingle(0, 0));
        try self.emitEffectiveAddress(insn, indexed);
        try self.emitBoundsCheck(insn.address, if (single) 4 else 8);
        try self.a.emit(a64.add(.x64, t1, r_membase, t0));
        try self.a.emit(a64.fmovToGpr(t2, 0));
        try self.a.emit(a64.rev(if (single) .w32 else .x64, t2, t2));
        try self.a.emit(a64.strImm(if (single) .word else .doubleword, t2, t1, 0).?);
        try self.emitBreakReservation();
        if (update) try self.storeGpr(ra, t0);
    }

    const FloatBinary = enum { add, subtract, multiply, divide };

    fn emitFloatBinary(self: *Compiler, insn: Instruction, single: bool, kind: FloatBinary) Error!void {
        const f = insn.a();
        try self.loadFpr(0, f.fa());
        // The PPC A-form fmul/fmuls source is FC; the other binary forms use
        // FB. This is easy to miss because all five fields are present.
        try self.loadFpr(1, if (kind == .multiply) f.fc() else f.fb());

        if (kind == .divide) {
            // fdiv/fdivs raise ZX (and the sticky FX summary) for a finite
            // numerator and zero denominator. Match the interpreter's NaN
            // guard explicitly: ARM reports an unordered self-compare for a
            // NaN, even though it also reports the zero comparison as equal.
            try self.a.loadConstant(t4, 0);
            try self.a.emit(a64.fmovFromGpr(3, t4));
            const width: a64.FpWidth = if (single) .single else .double;
            if (single) {
                try self.a.emit(a64.fcvtSingle(0, 0));
                try self.a.emit(a64.fcvtSingle(1, 1));
            }
            try self.a.emit(a64.fcmp(width, 1, 3));
            try self.a.emit(a64.cset(.w32, t2, .eq));
            try self.a.emit(a64.fcmp(width, 0, 0));
            try self.a.emit(a64.cset(.w32, t3, .vs));
            try self.a.loadConstant(t4, 1);
            try self.a.emit(a64.eorReg(.w32, t3, t3, t4));
            try self.a.emit(a64.andReg(.w32, t2, t2, t3));
            try self.a.emit(a64.cmpImm(.w32, t2, 0).?);
            try self.emitStickyFpscrBit(.ne, 5); // FPSCR.ZX + FPSCR.FX
            if (single) {
                try self.a.emit(a64.fcvtDouble(0, 0));
                try self.a.emit(a64.fcvtDouble(1, 1));
            }
        }

        const width: a64.FpWidth = if (single) .single else .double;
        if (single) {
            try self.a.emit(a64.fcvtSingle(0, 0));
            try self.a.emit(a64.fcvtSingle(1, 1));
        }
        switch (kind) {
            .add => try self.a.emit(a64.fadd(width, 0, 0, 1)),
            .subtract => try self.a.emit(a64.fsub(width, 0, 0, 1)),
            .multiply => try self.a.emit(a64.fmul(width, 0, 0, 1)),
            .divide => try self.a.emit(a64.fdiv(width, 0, 0, 1)),
        }
        if (single) try self.widenSingle(0, 0);
        try self.storeFpr(f.fd(), 0);
        try self.emitFprf(0);
        try self.emitCr1IfRc(insn);
    }

    fn emitFloatUnary(self: *Compiler, insn: Instruction, single: bool, kind: enum { sqrt }) Error!void {
        const f = insn.a();
        try self.loadFpr(0, f.fb());
        const width: a64.FpWidth = if (single) .single else .double;
        if (single) try self.a.emit(a64.fcvtSingle(0, 0));
        switch (kind) {
            .sqrt => try self.a.emit(a64.fsqrt(width, 0, 0)),
        }
        if (single) try self.widenSingle(0, 0);
        try self.storeFpr(f.fd(), 0);
        try self.emitFprf(0);
        try self.emitCr1IfRc(insn);
    }

    fn emitFloatFma(self: *Compiler, insn: Instruction, single: bool, subtract: bool, negate: bool) Error!void {
        const f = insn.a();
        try self.loadFpr(0, f.fa());
        try self.loadFpr(1, f.fb());
        try self.loadFpr(2, f.fc());
        const width: a64.FpWidth = if (single) .single else .double;
        if (single) {
            try self.a.emit(a64.fcvtSingle(0, 0));
            try self.a.emit(a64.fcvtSingle(1, 1));
            try self.a.emit(a64.fcvtSingle(2, 2));
        }
        if (subtract) {
            try self.a.emit(a64.fmsub(width, 0, 0, 2, 1));
        } else {
            try self.a.emit(a64.fmadd(width, 0, 0, 2, 1));
        }
        if (negate) try self.a.emit(a64.fneg(width, 0, 0));
        if (single) try self.widenSingle(0, 0);
        try self.storeFpr(f.fd(), 0);
        try self.emitFprf(0);
        try self.emitCr1IfRc(insn);
    }

    fn emitFloatMove(self: *Compiler, insn: Instruction, kind: enum { copy, negate, absolute, negative_absolute }) Error!void {
        const f = insn.x();
        try self.loadFpr(0, f.fb());
        switch (kind) {
            .copy => {},
            .negate => try self.a.emit(a64.fneg(.double, 0, 0)),
            .absolute => try self.a.emit(a64.fabs(.double, 0, 0)),
            .negative_absolute => {
                try self.a.emit(a64.fabs(.double, 0, 0));
                try self.a.emit(a64.fneg(.double, 0, 0));
            },
        }
        try self.storeFpr(f.fd(), 0);
        try self.emitCr1IfRc(insn);
    }

    fn emitRoundToSingle(self: *Compiler, insn: Instruction) Error!void {
        const f = insn.x();
        try self.loadFpr(0, f.fb());
        try self.a.emit(a64.fcvtSingle(0, 0));
        try self.widenSingle(0, 0);
        try self.storeFpr(f.fd(), 0);
        try self.emitFprf(0);
        try self.emitCr1IfRc(insn);
    }

    // -- compares -----------------------------------------------------------

    /// Write a CR field from a comparison of two values already in registers.
    fn emitCompare(
        self: *Compiler,
        field: u3,
        lhs: a64.Reg,
        rhs: a64.Reg,
        signed: bool,
    ) Error!void {
        try self.a.emit(a64.cmp(.x64, lhs, rhs));
        try self.a.emit(a64.cset(.w32, t2, if (signed) .lt else .lo));
        try self.a.emit(a64.lslImm(.w32, t2, t2, 3));
        try self.a.emit(a64.cset(.w32, t3, if (signed) .gt else .hi));
        try self.a.emit(a64.logicalShifted(.w32, .orr, t2, t2, t3, 2));
        try self.a.emit(a64.cset(.w32, t3, .eq));
        try self.a.emit(a64.logicalShifted(.w32, .orr, t2, t2, t3, 1));
        try self.a.emit(a64.ldrImm(.byte, t3, r_state, xer_so_offset).?);
        try self.a.emit(a64.orrReg(.w32, t2, t2, t3));
        try self.emitCrFieldWrite(field, t2);
    }

    /// Narrow a value to the width the L bit selects, so a 32-bit compare of
    /// two 64-bit registers gives the 32-bit answer.
    fn emitNarrow(self: *Compiler, reg: a64.Reg, wide: bool, signed: bool) Error!void {
        if (wide) return;
        if (signed) {
            try self.a.emit(a64.sxtw(reg, reg));
        } else {
            try self.a.emit(a64.mov(.w32, reg, reg));
        }
    }

    /// Materialise the branch predicate in t2 and leave NZCV set for the
    /// `csel` that chooses the target. PPC branches do not share ARM64's
    /// condition flags: BO combines an optional CTR decrement/test with an
    /// optional bit from the packed CR, so both tests have to be evaluated
    /// explicitly.
    fn emitBranchPredicate(self: *Compiler, bo: u5, bi: u5) Error!void {
        const ignore_condition = (bo & 0b10000) != 0;
        const condition_wanted = (bo >> 3) & 1;
        const skip_ctr = (bo & 0b00100) != 0;
        const branch_if_ctr_zero = (bo & 0b00010) != 0;

        if (skip_ctr) {
            try self.a.loadConstant(t2, 1);
        } else {
            try self.a.emit(a64.ldrImm(.doubleword, t4, r_state, ctr_offset).?);
            try self.a.emit(a64.subImm(.x64, t4, t4, 1).?);
            try self.a.emit(a64.strImm(.doubleword, t4, r_state, ctr_offset).?);
            try self.a.emit(a64.cmpImm(.x64, t4, 0).?);
            try self.a.emit(a64.cset(.w32, t2, if (branch_if_ctr_zero) .eq else .ne));
        }

        if (ignore_condition) {
            try self.a.loadConstant(t3, 1);
        } else {
            try self.a.emit(a64.ldrImm(.word, t4, r_state, cr_offset).?);
            const bit_shift: u6 = @intCast(31 - @as(u32, bi));
            try self.a.emit(a64.lsrImm(.w32, t4, t4, bit_shift));
            try self.andConstant(t4, t4, 1);
            try self.a.emit(a64.cmpImm(.w32, t4, 0).?);
            try self.a.emit(a64.cset(.w32, t3, if (condition_wanted != 0) .ne else .eq));
        }

        try self.a.emit(a64.andReg(.w32, t2, t2, t3));
        try self.a.emit(a64.cmpImm(.w32, t2, 0).?);
    }
};

/// Compile a run of guest instructions starting at `address`.
///
/// Stops at the first instruction outside the compiled subset, at the first
/// instruction that cannot be fetched, or after `max_instructions`. Returns an
/// owned instruction stream the caller copies into a code cache and frees, plus
/// how many guest instructions it covers.
pub fn compile(
    allocator: std.mem.Allocator,
    memory: anytype,
    address: u32,
    max_instructions: u32,
    out_count: *u32,
) Error![]u32 {
    var assembler = Assembler.init(allocator);
    // The label and fixup tables are compile-time bookkeeping and go away
    // either way; only the instruction stream is handed to the caller, and only
    // when compilation succeeds.
    defer {
        assembler.labels.deinit(allocator);
        assembler.fixups.deinit(allocator);
    }
    errdefer assembler.words.deinit(allocator);

    var compiler = Compiler{
        .a = &assembler,
        .fault_stubs = .empty,
        .allocator = allocator,
    };
    defer compiler.fault_stubs.deinit(allocator);

    var pc = address;
    var count: u32 = 0;
    var ended_in_branch = false;
    while (count < max_instructions) {
        const word = memory.fetch(pc) catch break;
        const insn = ppc_decode.decodeWord(pc, word);
        if (!insn.isValid() or !isCompilable(insn)) break;
        if (isCompiledBranch(insn)) {
            count += 1;
            compiler.retired += 1;
            try emitBranch(&compiler, insn, compiler.retired);
            ended_in_branch = true;
            break;
        }
        try emitInstruction(&compiler, insn);
        compiler.retired += 1;
        count += 1;
        pc +%= 4;
    }

    if (count == 0) return Error.NothingToCompile;

    // Normal exit: the guest resumes at the instruction after the block. A
    // compiled branch already emitted its target-selecting exit above.
    if (!ended_in_branch) try emitExit(&compiler, .fallthrough, pc, count);

    // Fault stubs, out of line. Each one knows its own guest address and how
    // many instructions had retired, so the interpreter resumes exactly where
    // the compiled code stopped.
    for (compiler.fault_stubs.items) |stub| {
        assembler.placeLabel(stub.label);
        try emitExit(&compiler, .memory_fault, stub.address, stub.retired);
    }

    _ = try assembler.finish();
    out_count.* = count;
    // Hand the caller an owned copy: the assembler's label and fixup tables go
    // away with it, and the code has to outlive them.
    return assembler.words.toOwnedSlice(allocator);
}

fn emitExit(c: *Compiler, reason: ExitReason, address: u32, retired: u32) Error!void {
    // The guest PC is part of architected state, so the block writes it rather
    // than leaving the caller to infer it from the exit record.
    try c.a.loadConstant(t0, address);
    try emitExitAddress(c, reason, t0, retired);
}

/// Finish a block when the guest address is already in `address_reg`. This is
/// the branch form of `emitExit`: the selected target is data in the guest
/// state, not a compile-time fallthrough address.
fn emitExitAddress(c: *Compiler, reason: ExitReason, address_reg: a64.Reg, retired: u32) Error!void {
    try c.a.emit(a64.strImm(.word, address_reg, r_state, pc_offset).?);
    try c.a.emit(a64.strImm(.word, address_reg, r_exit, @offsetOf(BlockExit, "address")).?);

    try c.a.loadConstant(t1, @intFromEnum(reason));
    try c.a.emit(a64.strImm(.word, t1, r_exit, @offsetOf(BlockExit, "reason")).?);

    try c.a.loadConstant(t1, retired);
    try c.a.emit(a64.strImm(.word, t1, r_exit, @offsetOf(BlockExit, "retired")).?);

    // Retired instructions accumulate in the guest state as well, so a
    // throughput measurement does not have to know whether a run went through
    // the interpreter or a compiled block.
    try c.a.emit(a64.ldrImm(.doubleword, t2, r_state, retired_offset).?);
    try c.a.emit(a64.add(.x64, t2, t2, t1));
    try c.a.emit(a64.strImm(.doubleword, t2, r_state, retired_offset).?);

    try c.a.emit(a64.ret());
}

fn branchTarget(address: u32, displacement: i64, absolute: bool) u32 {
    const raw: u32 = @truncate(@as(u64, @bitCast(displacement)));
    return if (absolute) raw else address +% raw;
}

/// Emit a branch as a target-selecting exit. This is deliberately not block
/// chaining yet: returning to the dispatcher keeps invalidation and thread
/// return handling in one place, while removing the interpreter's branch
/// decode/dispatch from hot integer loops.
fn emitBranch(c: *Compiler, insn: Instruction, retired: u32) Error!void {
    switch (insn.op) {
        .bx => {
            const f = insn.i();
            if (f.lk()) {
                try c.a.loadConstant(t1, insn.nextAddress());
                try c.a.emit(a64.strImm(.doubleword, t1, r_state, lr_offset).?);
            }
            try c.a.loadConstant(t0, branchTarget(insn.address, f.li(), f.aa()));
            try emitExitAddress(c, .fallthrough, t0, retired);
        },
        .bcx => {
            const f = insn.b();
            if (f.lk()) {
                try c.a.loadConstant(t4, insn.nextAddress());
                try c.a.emit(a64.strImm(.doubleword, t4, r_state, lr_offset).?);
            }
            try c.a.loadConstant(t0, branchTarget(insn.address, f.bd(), f.aa()));
            try c.a.loadConstant(t1, insn.nextAddress());
            try c.emitBranchPredicate(f.bo(), f.bi());
            try c.a.emit(a64.csel(.x64, t0, t0, t1, .ne));
            try emitExitAddress(c, .fallthrough, t0, retired);
        },
        .bclrx, .bcctrx => {
            const f = insn.xl();
            const source_offset: u32 = if (insn.op == .bclrx)
                @intCast(lr_offset)
            else
                @intCast(ctr_offset);
            try c.a.emit(a64.ldrImm(.doubleword, t0, r_state, source_offset).?);
            try c.andConstant(t0, t0, ~@as(u64, 3));
            if (f.lk()) {
                try c.a.loadConstant(t4, insn.nextAddress());
                try c.a.emit(a64.strImm(.doubleword, t4, r_state, lr_offset).?);
            }
            try c.a.loadConstant(t1, insn.nextAddress());
            const bo = if (insn.op == .bcctrx) f.bo() | 0b00100 else f.bo();
            try c.emitBranchPredicate(bo, f.bi());
            try c.a.emit(a64.csel(.x64, t0, t0, t1, .ne));
            try emitExitAddress(c, .fallthrough, t0, retired);
        },
        else => unreachable,
    }
}

fn emitInstruction(c: *Compiler, insn: Instruction) Error!void {
    switch (insn.op) {
        // -- scalar floating point loads/stores ----------------------------
        .lfs => try c.emitFloatLoad(insn, false, true, false),
        .lfsu => try c.emitFloatLoad(insn, false, true, true),
        .lfsx => try c.emitFloatLoad(insn, true, true, false),
        .lfsux => try c.emitFloatLoad(insn, true, true, true),
        .lfd => try c.emitFloatLoad(insn, false, false, false),
        .lfdu => try c.emitFloatLoad(insn, false, false, true),
        .lfdx => try c.emitFloatLoad(insn, true, false, false),
        .lfdux => try c.emitFloatLoad(insn, true, false, true),
        .stfs => try c.emitFloatStore(insn, false, true, false),
        .stfsu => try c.emitFloatStore(insn, false, true, true),
        .stfsx => try c.emitFloatStore(insn, true, true, false),
        .stfsux => try c.emitFloatStore(insn, true, true, true),
        .stfd => try c.emitFloatStore(insn, false, false, false),
        .stfdu => try c.emitFloatStore(insn, false, false, true),
        .stfdx => try c.emitFloatStore(insn, true, false, false),
        .stfdux => try c.emitFloatStore(insn, true, false, true),

        // -- scalar floating point arithmetic -------------------------------
        .faddx => try c.emitFloatBinary(insn, false, .add),
        .faddsx => try c.emitFloatBinary(insn, true, .add),
        .fsubx => try c.emitFloatBinary(insn, false, .subtract),
        .fsubsx => try c.emitFloatBinary(insn, true, .subtract),
        .fmulx => try c.emitFloatBinary(insn, false, .multiply),
        .fmulsx => try c.emitFloatBinary(insn, true, .multiply),
        .fdivx => try c.emitFloatBinary(insn, false, .divide),
        .fdivsx => try c.emitFloatBinary(insn, true, .divide),
        .fsqrtx => try c.emitFloatUnary(insn, false, .sqrt),
        .fsqrtsx => try c.emitFloatUnary(insn, true, .sqrt),
        .fmaddx => try c.emitFloatFma(insn, false, false, false),
        .fmaddsx => try c.emitFloatFma(insn, true, false, false),
        .fmsubx => try c.emitFloatFma(insn, false, true, false),
        .fmsubsx => try c.emitFloatFma(insn, true, true, false),
        .fnmaddx => try c.emitFloatFma(insn, false, false, true),
        .fnmaddsx => try c.emitFloatFma(insn, true, false, true),
        .fnmsubx => try c.emitFloatFma(insn, false, true, true),
        .fnmsubsx => try c.emitFloatFma(insn, true, true, true),
        .fmrx => try c.emitFloatMove(insn, .copy),
        .fnegx => try c.emitFloatMove(insn, .negate),
        .fabsx => try c.emitFloatMove(insn, .absolute),
        .fnabsx => try c.emitFloatMove(insn, .negative_absolute),
        .frspx => try c.emitRoundToSingle(insn),

        // -- add / subtract -------------------------------------------------
        .addi, .addis => {
            const f = insn.d();
            const shift: u6 = if (insn.op == .addis) 16 else 0;
            try c.loadGprOrZero(t0, f.ra());
            try c.addConstant(t0, t0, f.simm() << shift);
            try c.storeGpr(f.rd(), t0);
        },
        .addx => {
            const f = insn.xo();
            try c.loadGpr(t0, f.ra());
            try c.loadGpr(t1, f.rb());
            try c.a.emit(a64.add(.x64, t0, t0, t1));
            try c.storeGpr(f.rd(), t0);
            try c.recordIfRc(insn, t0);
        },
        .subfx => {
            const f = insn.xo();
            try c.loadGpr(t0, f.ra());
            try c.loadGpr(t1, f.rb());
            try c.a.emit(a64.sub(.x64, t0, t1, t0));
            try c.storeGpr(f.rd(), t0);
            try c.recordIfRc(insn, t0);
        },
        .negx => {
            const f = insn.xo();
            try c.loadGpr(t0, f.ra());
            try c.a.emit(a64.neg(.x64, t0, t0));
            try c.storeGpr(f.rd(), t0);
            try c.recordIfRc(insn, t0);
        },

        // -- multiply --------------------------------------------------------
        .mulli => {
            const f = insn.d();
            try c.loadGpr(t0, f.ra());
            try c.a.loadConstant(t1, @bitCast(f.simm()));
            try c.a.emit(a64.mul(.x64, t0, t0, t1));
            try c.storeGpr(f.rd(), t0);
        },
        .mullwx => {
            const f = insn.xo();
            try c.loadGpr(t0, f.ra());
            try c.loadGpr(t1, f.rb());
            // mullw is the full 64-bit product of the two low words.
            try c.a.emit(a64.smull(t0, t0, t1));
            try c.storeGpr(f.rd(), t0);
            try c.recordIfRc(insn, t0);
        },
        .mulldx => {
            const f = insn.xo();
            try c.loadGpr(t0, f.ra());
            try c.loadGpr(t1, f.rb());
            try c.a.emit(a64.mul(.x64, t0, t0, t1));
            try c.storeGpr(f.rd(), t0);
            try c.recordIfRc(insn, t0);
        },

        // -- logical ---------------------------------------------------------
        .andx, .andcx, .orx, .orcx, .xorx, .nandx, .norx, .eqvx => {
            const f = insn.x();
            // The logical forms write rA and read rS: the destination is the
            // second named register, the reverse of the arithmetic forms.
            try c.loadGpr(t0, f.rs());
            try c.loadGpr(t1, f.rb());
            switch (insn.op) {
                .andx => try c.a.emit(a64.andReg(.x64, t0, t0, t1)),
                .andcx => try c.a.emit(a64.bicReg(.x64, t0, t0, t1)),
                .orx => try c.a.emit(a64.orrReg(.x64, t0, t0, t1)),
                .orcx => try c.a.emit(a64.ornReg(.x64, t0, t0, t1)),
                .xorx => try c.a.emit(a64.eorReg(.x64, t0, t0, t1)),
                .nandx => {
                    try c.a.emit(a64.andReg(.x64, t0, t0, t1));
                    try c.a.emit(a64.mvn(.x64, t0, t0));
                },
                .norx => {
                    try c.a.emit(a64.orrReg(.x64, t0, t0, t1));
                    try c.a.emit(a64.mvn(.x64, t0, t0));
                },
                .eqvx => try c.a.emit(a64.eonReg(.x64, t0, t0, t1)),
                else => unreachable,
            }
            try c.storeGpr(f.ra(), t0);
            try c.recordIfRc(insn, t0);
        },
        .andix, .andisx, .ori, .oris, .xori, .xoris => {
            const f = insn.d();
            const shift: u6 = switch (insn.op) {
                .andisx, .oris, .xoris => 16,
                else => 0,
            };
            const value = f.uimm() << shift;
            try c.loadGpr(t0, f.rs());
            const op: a64.LogicalOp = switch (insn.op) {
                .andix, .andisx => .andop,
                .ori, .oris => .orr,
                else => .eor,
            };
            if (value == 0) {
                // `ori r,r,0` is the canonical nop and `andi. r,r,0` clears;
                // both have no bitmask encoding, so they are special-cased.
                if (op == .andop) try c.a.emit(a64.mov(.x64, t0, a64.xzr));
            } else if (a64.logicalImmediate(.x64, op, t0, t0, value)) |word| {
                try c.a.emit(word);
            } else {
                try c.a.loadConstant(t1, value);
                try c.a.emit(a64.logicalShifted(.x64, op, t0, t0, t1, 0));
            }
            try c.storeGpr(f.ra(), t0);
            // andi. and andis. always write CR0; the or/xor immediates never do.
            if (op == .andop) try c.emitCr0(t0);
        },

        // -- extend and count -------------------------------------------------
        .extsbx, .extshx, .extswx => {
            const f = insn.x();
            try c.loadGpr(t0, f.rs());
            switch (insn.op) {
                .extsbx => try c.a.emit(a64.sxtb(.x64, t0, t0)),
                .extshx => try c.a.emit(a64.sxth(.x64, t0, t0)),
                else => try c.a.emit(a64.sxtw(t0, t0)),
            }
            try c.storeGpr(f.ra(), t0);
            try c.recordIfRc(insn, t0);
        },
        .cntlzwx, .cntlzdx => {
            const f = insn.x();
            try c.loadGpr(t0, f.rs());
            if (insn.op == .cntlzwx) {
                try c.a.emit(a64.clz(.w32, t0, t0));
            } else {
                try c.a.emit(a64.clz(.x64, t0, t0));
            }
            try c.storeGpr(f.ra(), t0);
            try c.recordIfRc(insn, t0);
        },

        // -- shifts -------------------------------------------------------------
        .slwx, .srwx, .sldx, .srdx => {
            const f = insn.x();
            try c.loadGpr(t0, f.rs());
            try c.loadGpr(t1, f.rb());
            const word_form = insn.op == .slwx or insn.op == .srwx;
            // A PowerPC shift count at or past the width clears the result,
            // where ARM64 masks the count and wraps. The out-of-range case is
            // therefore selected explicitly rather than left to the shift.
            const limit: u64 = if (word_form) 32 else 64;
            const mask: u64 = if (word_form) 0x3F else 0x7F;
            try c.andConstant(t1, t1, mask);
            if (word_form and insn.op == .slwx) {
                try c.a.emit(a64.mov(.w32, t0, t0));
            } else if (word_form) {
                try c.a.emit(a64.mov(.w32, t0, t0));
            }
            if (insn.op == .slwx or insn.op == .sldx) {
                try c.a.emit(a64.lslv(.x64, t2, t0, t1));
            } else {
                try c.a.emit(a64.lsrv(.x64, t2, t0, t1));
            }
            if (word_form and insn.op == .slwx) {
                try c.a.emit(a64.mov(.w32, t2, t2));
            }
            try c.a.emit(a64.cmpImm(.x64, t1, limit).?);
            try c.a.emit(a64.csel(.x64, t0, a64.xzr, t2, .hs));
            try c.storeGpr(f.ra(), t0);
            try c.recordIfRc(insn, t0);
        },
        .srawix => {
            const f = insn.x();
            const shift: u6 = f.sh();
            try c.loadGpr(t0, f.rs());
            try c.a.emit(a64.asrImm(.w32, t1, t0, shift));
            // XER.CA is set when the value was negative *and* a one bit fell
            // off the right; shifting back left and comparing detects the loss.
            try c.a.emit(a64.lslImm(.w32, t2, t1, shift));
            try c.a.emit(a64.cmp(.w32, t2, t0));
            try c.a.emit(a64.cset(.w32, t2, .ne));
            try c.a.emit(a64.lsrImm(.w32, t3, t0, 31));
            try c.a.emit(a64.andReg(.w32, t2, t2, t3));
            try c.a.emit(a64.strImm(.byte, t2, r_state, xer_ca_offset).?);
            try c.a.emit(a64.sxtw(t1, t1));
            try c.storeGpr(f.ra(), t1);
            try c.recordIfRc(insn, t1);
        },

        // -- rotate ---------------------------------------------------------------
        .rlwinmx, .rlwimix => {
            const f = insn.m();
            try c.loadGpr(t0, f.rs());
            try emitRotateWord(c, t0, f.sh());
            const mask = fields.mask64(@as(u32, f.mb()) + 32, @as(u32, f.me()) + 32);
            try c.andConstant(t0, t0, mask);
            if (insn.op == .rlwimix) {
                // Keep the destination bits the mask does not cover.
                try c.loadGpr(t1, f.ra());
                try c.andConstant(t1, t1, ~mask);
                try c.a.emit(a64.orrReg(.x64, t0, t0, t1));
            }
            try c.storeGpr(f.ra(), t0);
            try c.recordIfRc(insn, t0);
        },
        .rldiclx, .rldicrx => {
            const f = insn.md();
            try c.loadGpr(t0, f.rs());
            const rotate = f.sh();
            if (rotate != 0) {
                try c.a.emit(a64.rorImm(.x64, t0, t0, @intCast(64 - @as(u32, rotate))));
            }
            const mask = if (insn.op == .rldiclx)
                fields.mask64(f.mb(), 63)
            else
                fields.mask64(0, f.me());
            try c.andConstant(t0, t0, mask);
            try c.storeGpr(f.ra(), t0);
            try c.recordIfRc(insn, t0);
        },

        // -- compare -----------------------------------------------------------------
        .cmp, .cmpl => {
            const f = insn.x();
            const signed = insn.op == .cmp;
            try c.loadGpr(t0, f.ra());
            try c.loadGpr(t1, f.rb());
            try c.emitNarrow(t0, f.l() != 0, signed);
            try c.emitNarrow(t1, f.l() != 0, signed);
            try c.emitCompare(f.crfd(), t0, t1, signed);
        },
        .cmpi, .cmpli => {
            const f = insn.d();
            const signed = insn.op == .cmpi;
            try c.loadGpr(t0, f.ra());
            try c.emitNarrow(t0, f.l() != 0, signed);
            if (signed) {
                try c.a.loadConstant(t1, @bitCast(f.simm()));
            } else {
                try c.a.loadConstant(t1, f.uimm());
            }
            try c.emitCompare(f.crfd(), t0, t1, signed);
        },

        // -- loads --------------------------------------------------------------------
        .lbz => try c.emitLoad(insn, false, .{ .size = .byte, .bytes = 1, .conversion = .none }),
        .lhz => try c.emitLoad(insn, false, .{ .size = .half, .bytes = 2, .conversion = .swap16_zero }),
        .lha => try c.emitLoad(insn, false, .{ .size = .half, .bytes = 2, .conversion = .swap16_sign }),
        .lwz => try c.emitLoad(insn, false, .{ .size = .word, .bytes = 4, .conversion = .swap32_zero }),
        .ld => try c.emitLoad(insn, false, .{ .size = .doubleword, .bytes = 8, .conversion = .swap64 }),
        .lwa => try c.emitLoad(insn, false, .{ .size = .word, .bytes = 4, .conversion = .swap32_sign }),
        .lbzx => try c.emitLoad(insn, true, .{ .size = .byte, .bytes = 1, .conversion = .none }),
        .lhzx => try c.emitLoad(insn, true, .{ .size = .half, .bytes = 2, .conversion = .swap16_zero }),
        .lhax => try c.emitLoad(insn, true, .{ .size = .half, .bytes = 2, .conversion = .swap16_sign }),
        .lwzx => try c.emitLoad(insn, true, .{ .size = .word, .bytes = 4, .conversion = .swap32_zero }),
        .lwax => try c.emitLoad(insn, true, .{ .size = .word, .bytes = 4, .conversion = .swap32_sign }),
        .ldx => try c.emitLoad(insn, true, .{ .size = .doubleword, .bytes = 8, .conversion = .swap64 }),

        // -- stores ---------------------------------------------------------------------
        .stb => try c.emitStore(insn, false, .{ .size = .byte, .bytes = 1, .conversion = .none }),
        .sth => try c.emitStore(insn, false, .{ .size = .half, .bytes = 2, .conversion = .swap16_zero }),
        .stw => try c.emitStore(insn, false, .{ .size = .word, .bytes = 4, .conversion = .swap32_zero }),
        .std => try c.emitStore(insn, false, .{ .size = .doubleword, .bytes = 8, .conversion = .swap64 }),
        .stbx => try c.emitStore(insn, true, .{ .size = .byte, .bytes = 1, .conversion = .none }),
        .sthx => try c.emitStore(insn, true, .{ .size = .half, .bytes = 2, .conversion = .swap16_zero }),
        .stwx => try c.emitStore(insn, true, .{ .size = .word, .bytes = 4, .conversion = .swap32_zero }),
        .stdx => try c.emitStore(insn, true, .{ .size = .doubleword, .bytes = 8, .conversion = .swap64 }),

        else => unreachable, // isCompilable gates this switch.
    }
}

/// Rotate the low 32 bits left by `amount` and duplicate the result into both
/// halves of the register, which is what the word rotate-and-mask forms operate
/// on. Rotating the 64-bit register instead silently changes every rlwinm.
fn emitRotateWord(c: *Compiler, reg: a64.Reg, amount: u5) Error!void {
    if (amount != 0) {
        // A left rotate by n is a right rotate by 32-n in the 32-bit view.
        try c.a.emit(a64.rorImm(.w32, reg, reg, @intCast(32 - @as(u32, amount))));
    } else {
        try c.a.emit(a64.mov(.w32, reg, reg));
    }
    try c.a.emit(a64.logicalShifted(.x64, .orr, reg, reg, reg, 32));
}

// ---------------------------------------------------------------------------
// Tests
//
// The compiler's correctness argument is differential: for the same starting
// state, a compiled block and the interpreter must produce the same architected
// state. Those tests live in root.zig, where both are available. What is tested
// here is the shape of the decision - which instructions the compiler claims,
// and where a block stops.
// ---------------------------------------------------------------------------

const testing = std.testing;

fn decode(word: u32) Instruction {
    return ppc_decode.decodeWord(0x8200_0000, word);
}

test "the compiled subset is the integer and memory core" {
    try testing.expect(isCompilable(decode(0x38600001))); // li r3, 1
    try testing.expect(isCompilable(decode(0x7C632214))); // add r3, r3, r4
    try testing.expect(isCompilable(decode(0x80640000))); // lwz r3, 0(r4)
    try testing.expect(isCompilable(decode(0x90640000))); // stw r3, 0(r4)
    try testing.expect(isCompilable(decode(0x54630FFE))); // rlwinm
}

test "unsupported side effects still end a block" {
    // The branch forms now compile their architected target selection and
    // return to the dispatcher; floating point and SPR side effects still
    // terminate the block for the interpreter.
    try testing.expect(isCompilable(decode(0x4E800020))); // blr
    try testing.expect(isCompilable(decode(0x4082FFF4))); // bne
    // Scalar floating point has a direct ARM64 lowering now.
    try testing.expect(isCompilable(decode(0xFC000024))); // fdiv
    // An SPR move: the interpreter owns the SPR model.
    try testing.expect(!isCompilable(decode(0x7C0803A6))); // mtlr r0
    // A load-and-reserve: the reservation protocol is not compiled.
    try testing.expect(!isCompilable(decode(0x7C601828))); // lwarx
}

test "an overflow-enabled arithmetic instruction is refused, not compiled without XER" {
    // add. r3, r4, r5 is compilable; addo. is not, because XER.OV is not
    // emitted and compiling it would drop the overflow the guest asked for.
    try testing.expect(isCompilable(decode(0x7C642A15)));
    try testing.expect(!isCompilable(decode(0x7C642E15)));
}
