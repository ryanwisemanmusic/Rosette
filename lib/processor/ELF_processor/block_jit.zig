//! x86-64 block translation to ARM64 for the PE64 route.
//!
//! The interpreter in `process.zig` executes Xenia's x86-64 one instruction
//! at a time: probe the decode cache, validate the entry, resolve the
//! effective address, dispatch through the executor, account. On 2026-09-17
//! that cost about 230 host cycles per guest instruction, and the title's
//! main thread needs about 23 million of them per frame. No amount of
//! trimming the per-instruction path closes a gap of that size; the path has
//! to stop being per-instruction. This file is the second execution tier: a
//! straight-line run of guest instructions is decoded once and emitted as one
//! ARM64 function that performs the same architected state changes.
//!
//! ## What it is, and what it is not
//!
//! Guest state stays in `ElfState` in memory. Every emitted instruction loads
//! its operands from the register file and stores its result back, exactly as
//! the interpreter does; there is no register allocation. That is a deliberate
//! first version: the win is removing the fetch, decode, validate and dispatch
//! work, which is most of the 230 cycles, and a memory-resident register file
//! keeps every emitted sequence auditable as a flat list against the
//! interpreter arm it mirrors. The register-file traffic it leaves behind is
//! L1-resident.
//!
//! The compiled subset is the integer core a compiler emits most: moves,
//! zero/sign extension, `lea`, the Group-1 arithmetic and logic on registers
//! and immediates, `inc`/`dec`/`neg`/`not`, shifts by immediate, `imul`,
//! `cmovcc`/`setcc`, `push`/`pop`, and the conditional and unconditional
//! relative branches, which end a block. Loads and stores go through
//! `ElfState`'s own `readMemVal`/`writeMemVal` via C-ABI helpers, so the
//! null-page rule, the mapped-memory model, the page-protection faults and the
//! code-generation bumps all keep applying. Anything else in the middle of a
//! block is handed to the interpreter for that one instruction, through a
//! helper that resolves the address and calls `execute`; anything that
//! transfers control other than a relative branch (`call`, `ret`, indirect
//! jumps, `syscall`, `hlt`) ends the block *before* it, so the interpreter's
//! own arm, with its milestone, kernel-call, accelerator and shim hooks, runs
//! it at the next step.
//!
//! ## Flags
//!
//! Flags are computed eagerly and exactly as `flags.zig` computes them,
//! including PF and AF, and the instructions that leave a flag alone in the
//! interpreter leave it alone here (shifts do not touch PF or AF; `inc`/`dec`
//! keep CF). The emitted flag sequences are the largest cost in this version
//! and the first thing a second version should make lazy; they are kept exact
//! first because a jcc that reads a flag the interpreter would have set
//! differently is a divergence that no differential test of straight-line
//! code will show.
//!
//! ## Calling convention
//!
//! A block is `fn (state, helpers) callconv(.c) u32`. It returns how many of
//! its instructions completed; the guest RIP is always left in
//! `state.regs.rip` by whichever path left the block. x19 holds the state,
//! x20 the register file, x21 the helper table and x22 the scratch record for
//! the life of the block; x9-x14 are scratch and nothing lives in them across
//! a helper call.

const std = @import("std");
const a64 = @import("arm64_encode");
const x64_decoder = @import("x64_decoder");

pub const Assembler = a64.assembler.Assembler;
pub const Label = a64.assembler.Label;
pub const CodeMemory = a64.code_memory.CodeCache;
pub const CodeMemoryError = a64.code_memory.Error;

pub const DecodedInsn = x64_decoder.DecodedInsn;
pub const Op = x64_decoder.Op;
pub const RegId = x64_decoder.RegId;
pub const Size = x64_decoder.OperandSize;
pub const Cond = x64_decoder.Condition;
pub const Segment = x64_decoder.Segment;
pub const Regs = x64_decoder.Regs;

pub const Error = a64.assembler.Error || CodeMemoryError || error{NothingToCompile};

/// The functions emitted code calls, reached through a per-block table so no
/// absolute address has to be materialised at every call site.
pub const Helpers = extern struct {
    /// `readMemVal(state, address, size)`. Sets the abort flag when the read
    /// left a fault pending or ended the run.
    read: *const fn (state: *anyopaque, address: u64, size: u8) callconv(.c) u64,
    /// `writeMemVal(state, address, size, value)`. Same abort rule.
    write: *const fn (state: *anyopaque, address: u64, size: u8, value: u64) callconv(.c) void,
    /// Execute instruction `index` of the block through the interpreter.
    /// Returns 0 when the block may continue with the next instruction and
    /// nonzero when it must stop (control transfer, fault, termination).
    interpret: *const fn (state: *anyopaque, block: *const Block, index: u32) callconv(.c) u32,
    /// The block these helpers belong to, for the interpret call.
    block: *const Block,
};

const helper_read_offset: u32 = @offsetOf(Helpers, "read");
const helper_write_offset: u32 = @offsetOf(Helpers, "write");
const helper_interpret_offset: u32 = @offsetOf(Helpers, "interpret");
const helper_block_offset: u32 = @offsetOf(Helpers, "block");

/// The block's view of the state it is running in, written by emitted code
/// and read by the helpers. Lives inside the state at `Layout.scratch_offset`.
pub const Scratch = extern struct {
    /// Set to nonzero by a helper when the block must stop after the current
    /// instruction (a fault is pending or the run ended).
    abort: u8 = 0,
    pad: [3]u8 = .{ 0, 0, 0 },
    /// The index of the instruction about to call a helper, stored by the
    /// emitted code just before the call, so the helper can name the
    /// instruction (its RIP, op and length) without the code materialising
    /// any of them.
    index: u32 = 0,
    /// The block being executed, set by the glue before entry.
    block: ?*const Block = null,
};

/// Where the emitted code finds the state it works on.
pub const Layout = struct {
    /// Byte offset of the `Regs` register file inside the state.
    regs_offset: u32,
    /// Byte offset of the `Scratch` record inside the state.
    scratch_offset: u32,
};

const scratch_abort_offset: u32 = @offsetOf(Scratch, "abort");
const scratch_index_offset: u32 = @offsetOf(Scratch, "index");

pub const Insn = struct {
    rip: u64,
    len: u8,
    /// The decode as it comes out of the decoder: `addr` is the displacement,
    /// not an effective address.
    decoded: DecodedInsn,
    segment: Segment,
    /// The glue asks for the interpreter although a template exists: a
    /// relative jump into an address one of the RIP hooks would intercept.
    force_fallback: bool = false,
};

pub const BlockFn = *const fn (state: *anyopaque, helpers: *const Helpers) callconv(.c) u32;

pub const Block = struct {
    helpers: Helpers,
    start_rip: u64,
    /// One past the last byte the block covers.
    end_rip: u64,
    insns: []Insn,
    /// The instruction bytes the block was compiled from, for revalidation
    /// after the source's generation moves.
    bytes: []u8,
    code: []const u32,
    native_count: u32,
    fallback_count: u32,
    /// No memory access and no fallback: the block can be cross-checked
    /// against the interpreter by running both on the register file.
    register_only: bool,
    /// Source identity, owned by the glue. Mirrors the decode cache entry.
    source_mapped: bool = false,
    source_kind: u8 = 0,
    source_index: usize = 0,
    source_generation: ?u64 = null,
    executions: u64 = 0,
    instructions_retired: u64 = 0,
    verified: bool = false,

    pub fn entry(self: *const Block) BlockFn {
        return @ptrCast(self.code.ptr);
    }
};

pub const Compiled = struct {
    code: []const u32,
    native_count: u32,
    fallback_count: u32,
    register_only: bool,
};

// ---------------------------------------------------------------------------
// The compiled subset
// ---------------------------------------------------------------------------

/// Whether a template exists for the instruction as decoded. Not every form
/// of an op is compiled (a 16-bit shift is not), so this is a function of the
/// whole decode, not of the op alone.
pub fn isNative(d: DecodedInsn) bool {
    if (d.lock or d.is_evex) return false;
    return switch (d.op) {
        .nop => d.len != 2,
        .mov_reg8_reg8, .mov_reg16_reg16, .mov_reg32_reg32, .mov_reg64_reg64 => true,
        .mov_reg_imm => true,
        .mov_reg8_mem8, .mov_reg16_mem16, .mov_reg32_mem32, .mov_reg64_mem64 => memoryOperandSupported(d),
        .mov_mem8_reg8, .mov_mem16_reg16, .mov_mem32_reg32, .mov_mem64_reg64 => memoryOperandSupported(d),
        .mov_mem8_imm8, .mov_mem16_imm16, .mov_mem32_imm32, .mov_mem64_imm32 => memoryOperandSupported(d),
        .movzx_reg32_mem8, .movzx_reg32_mem16, .movsx_reg32_mem8, .movsx_reg32_mem16 => d.is_reg_form or memoryOperandSupported(d),
        .movsxd_reg64_reg32 => true,
        .movsxd_reg64_mem32 => memoryOperandSupported(d),
        .lea_reg_mem => memoryOperandSupported(d) and d.size != .bits8,
        .add_reg8_reg8, .add_reg16_reg16, .add_reg32_reg32, .add_reg64_reg64 => true,
        .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64 => true,
        .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64 => true,
        .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64 => true,
        .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64 => true,
        .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64 => true,
        .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64 => true,
        .add_reg8_imm8, .add_reg16_imm8, .add_reg32_imm8, .add_reg64_imm8 => true,
        .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8 => true,
        .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8 => true,
        .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8 => true,
        .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8 => true,
        .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => true,
        .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32 => true,
        .sub_reg16_imm32, .sub_reg32_imm32, .sub_reg64_imm32 => true,
        .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32 => true,
        .or_reg16_imm32, .or_reg32_imm32, .or_reg64_imm32 => true,
        .xor_reg16_imm32, .xor_reg32_imm32, .xor_reg64_imm32 => true,
        .cmp_reg16_imm32, .cmp_reg32_imm32, .cmp_reg64_imm32 => true,
        .add_accum_imm, .sub_accum_imm, .and_accum_imm, .or_accum_imm, .xor_accum_imm, .cmp_accum_imm => true,
        .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => true,
        .inc_reg8, .inc_reg16, .inc_reg32, .inc_reg64 => true,
        .dec_reg8, .dec_reg16, .dec_reg32, .dec_reg64 => true,
        .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => true,
        .not_reg8, .not_reg16, .not_reg32, .not_reg64 => true,
        .shl_reg_imm, .shr_reg_imm, .sar_reg_imm => d.size == .bits32 or d.size == .bits64,
        .imul_reg64_reg64, .imul_reg32_reg32 => true,
        .imul_reg32_reg32_imm8, .imul_reg32_reg32_imm32, .imul_reg64_reg64_imm8, .imul_reg64_reg64_imm32 => d.is_reg_form,
        .cmovcc_reg_reg => d.size == .bits32 or d.size == .bits64,
        .setcc_reg8 => true,
        .push_reg, .push_imm, .pop_reg => true,
        .cdqe, .cdq, .cqo => true,
        .bswap_reg => d.size == .bits32 or d.size == .bits64,
        .jcc_rel8, .jcc_rel32, .jmp_rel8 => true,
        else => false,
    };
}

/// A relative branch: compiled as the block's last instruction.
pub fn isTerminator(op: Op) bool {
    return switch (op) {
        .jcc_rel8, .jcc_rel32, .jmp_rel8 => true,
        else => false,
    };
}

/// Instructions the interpreter must run at a step boundary of its own, so a
/// block ends before them: everything that transfers control other than a
/// relative branch, and everything that reaches the host or the scheduler.
pub fn endsBlockBefore(d: DecodedInsn) bool {
    return switch (d.op) {
        .call_rel32, .call_mem64, .call_reg64, .ret, .jmp_mem64, .jmp_reg64 => true,
        .loop, .loope, .loopne, .jrcxz => true,
        .syscall, .hlt, .ud2, .cpuid, .rdtsc, .rdtscp, .xgetbv, .invalid => true,
        // `pause` (F3 90) decodes as a two-byte nop and is the cooperative
        // scheduling point; the interpreter has to see it.
        .nop => d.len == 2,
        else => false,
    };
}

fn memoryOperandSupported(d: DecodedInsn) bool {
    // fs/gs-relative operands add a segment base the interpreter reads from
    // the register file; they are supported. Real-mode style segments are
    // not a long-mode concern. What is refused is an address-size override
    // together with a rip-relative operand, a form no compiler emits and
    // whose interpretation would need care this version has not taken.
    return !(d.has_0x67 and d.rip_relative);
}

// ---------------------------------------------------------------------------
// Register assignment inside a block
// ---------------------------------------------------------------------------

const r_state: a64.Reg = 19;
const r_regs: a64.Reg = 20;
const r_helpers: a64.Reg = 21;
const r_scratch: a64.Reg = 22;
const t0: a64.Reg = 9;
const t1: a64.Reg = 10;
const t2: a64.Reg = 11;
const t3: a64.Reg = 12;
const t4: a64.Reg = 13;
const t5: a64.Reg = 14;

const rip_offset: u32 = @offsetOf(Regs, "rip");
const rflags_offset: u32 = @offsetOf(Regs, "rflags");
const SegmentStateType = @FieldType(Regs, "segments");
const fs_base_offset: u32 = @offsetOf(Regs, "segments") + @offsetOf(SegmentStateType, "fs") + @offsetOf(@FieldType(SegmentStateType, "fs"), "base");
const gs_base_offset: u32 = @offsetOf(Regs, "segments") + @offsetOf(SegmentStateType, "gs") + @offsetOf(@FieldType(SegmentStateType, "gs"), "base");

const RFL_CF: u32 = x64_decoder.RFL_CF;
const RFL_PF: u32 = x64_decoder.RFL_PF;
const RFL_AF: u32 = x64_decoder.RFL_AF;
const RFL_ZF: u32 = x64_decoder.RFL_ZF;
const RFL_SF: u32 = x64_decoder.RFL_SF;
const RFL_OF: u32 = x64_decoder.RFL_OF;

fn bits(size: Size) u7 {
    return switch (size) {
        .bits8 => 8,
        .bits16 => 16,
        .bits32 => 32,
        .bits64 => 64,
    };
}

fn maskFor(size: Size) u64 {
    return switch (size) {
        .bits8 => 0xFF,
        .bits16 => 0xFFFF,
        .bits32 => 0xFFFF_FFFF,
        .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
    };
}

fn arm(size: Size) a64.Width {
    return if (size == .bits64) .x64 else .w32;
}

fn gprOffset(id: RegId) u32 {
    return @as(u32, @intFromEnum(id)) * 8;
}

fn signExtendImm8(imm: u64) u64 {
    const signed: i8 = @bitCast(@as(u8, @truncate(imm)));
    return @bitCast(@as(i64, signed));
}

/// The interpreter's `testImmForSize`: an imm32 form is sign-extended to
/// 64 bits, the narrower forms are masked.
fn immForSize(imm: u64, size: Size) u64 {
    return switch (size) {
        .bits8 => imm & 0xFF,
        .bits16 => imm & 0xFFFF,
        .bits32 => imm & 0xFFFF_FFFF,
        .bits64 => @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(imm)))))),
    };
}

const ArithKind = enum { add, sub, logic };
const BinaryOp = enum { add, sub, bit_and, bit_or, bit_xor, cmp, tst };

fn binaryOpOf(op: Op) ?BinaryOp {
    return switch (op) {
        .add_reg8_reg8, .add_reg16_reg16, .add_reg32_reg32, .add_reg64_reg64, .add_reg8_imm8, .add_reg16_imm8, .add_reg32_imm8, .add_reg64_imm8, .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32, .add_accum_imm => .add,
        .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64, .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8, .sub_reg16_imm32, .sub_reg32_imm32, .sub_reg64_imm32, .sub_accum_imm => .sub,
        .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64, .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8, .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32, .and_accum_imm => .bit_and,
        .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64, .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8, .or_reg16_imm32, .or_reg32_imm32, .or_reg64_imm32, .or_accum_imm => .bit_or,
        .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64, .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8, .xor_reg16_imm32, .xor_reg32_imm32, .xor_reg64_imm32, .xor_accum_imm => .bit_xor,
        .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64, .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8, .cmp_reg16_imm32, .cmp_reg32_imm32, .cmp_reg64_imm32, .cmp_accum_imm => .cmp,
        .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64, .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => .tst,
        else => null,
    };
}

const ImmediateShape = enum { none, imm8, imm32, test_imm };

fn immediateShapeOf(op: Op) ImmediateShape {
    return switch (op) {
        .add_reg8_imm8, .add_reg16_imm8, .add_reg32_imm8, .add_reg64_imm8, .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8, .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8, .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8, .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8, .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => .imm8,
        .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32, .sub_reg16_imm32, .sub_reg32_imm32, .sub_reg64_imm32, .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32, .or_reg16_imm32, .or_reg32_imm32, .or_reg64_imm32, .xor_reg16_imm32, .xor_reg32_imm32, .xor_reg64_imm32, .cmp_reg16_imm32, .cmp_reg32_imm32, .cmp_reg64_imm32 => .imm32,
        .add_accum_imm, .sub_accum_imm, .and_accum_imm, .or_accum_imm, .xor_accum_imm, .cmp_accum_imm => .imm32,
        .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => .test_imm,
        else => .none,
    };
}

/// The immediate as the interpreter arm sees it.
fn immediateValue(d: DecodedInsn) u64 {
    return switch (immediateShapeOf(d.op)) {
        .imm8 => if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm),
        .imm32, .test_imm => immForSize(d.imm, d.size),
        .none => d.imm,
    };
}

// ---------------------------------------------------------------------------
// The compiler
// ---------------------------------------------------------------------------

const ExitStub = struct {
    label: Label,
    completed: u32,
    /// The RIP to store before returning, or null when the interpreter
    /// already set it (a fallback that transferred control).
    rip: ?u64,
};

const Compiler = struct {
    a: *Assembler,
    layout: Layout,
    insns: []const Insn,
    end_rip: u64,
    epilogue: Label,
    exits: std.ArrayList(ExitStub),
    allocator: std.mem.Allocator,
    native_count: u32 = 0,
    fallback_count: u32 = 0,
    touches_memory: bool = false,

    fn emit(self: *Compiler, word: u32) Error!void {
        try self.a.emit(word);
    }

    fn emitChecked(self: *Compiler, word: ?u32) Error!void {
        // Every offset this compiler forms is a register-file slot or a
        // helper-table slot, both small and aligned; an unencodable one is
        // a compiler bug, not a guest property.
        try self.a.emit(word.?);
    }

    /// `dst = &state + offset`, whatever the offset's size.
    fn emitStateAddress(self: *Compiler, dst: a64.Reg, offset: u32) Error!void {
        if (a64.addImm(.x64, dst, r_state, offset)) |word| {
            try self.emit(word);
            return;
        }
        try self.a.loadConstant(dst, offset);
        try self.emit(a64.add(.x64, dst, r_state, dst));
    }

    fn emitPrologue(self: *Compiler) Error!void {
        try self.emitChecked(a64.stp(.pre_index, 29, 30, a64.sp, -48));
        try self.emitChecked(a64.stp(.signed_offset, r_state, r_regs, a64.sp, 16));
        try self.emitChecked(a64.stp(.signed_offset, r_helpers, r_scratch, a64.sp, 32));
        try self.emitChecked(a64.addImm(.x64, 29, a64.sp, 0));
        try self.emit(a64.mov(.x64, r_state, 0));
        try self.emit(a64.mov(.x64, r_helpers, 1));
        try self.emitStateAddress(r_regs, self.layout.regs_offset);
        try self.emitStateAddress(r_scratch, self.layout.scratch_offset);
    }

    fn emitEpilogue(self: *Compiler) Error!void {
        self.a.placeLabel(self.epilogue);
        try self.emitChecked(a64.ldp(.signed_offset, r_helpers, r_scratch, a64.sp, 32));
        try self.emitChecked(a64.ldp(.signed_offset, r_state, r_regs, a64.sp, 16));
        try self.emitChecked(a64.ldp(.post_index, 29, 30, a64.sp, 48));
        try self.emit(a64.ret());
    }

    /// Create an exit that stores `rip` (when given) and returns `completed`.
    fn exitStub(self: *Compiler, completed: u32, rip: ?u64) Error!Label {
        const label = try self.a.createLabel();
        try self.exits.append(self.allocator, .{ .label = label, .completed = completed, .rip = rip });
        return label;
    }

    fn emitExitStubs(self: *Compiler) Error!void {
        for (self.exits.items) |stub| {
            self.a.placeLabel(stub.label);
            if (stub.rip) |rip| {
                try self.a.loadConstant(t0, rip);
                try self.emitChecked(a64.strImm(.doubleword, t0, r_regs, rip_offset));
            }
            try self.a.loadConstant(0, stub.completed);
            try self.a.branch(self.epilogue);
        }
    }

    // -- register file --------------------------------------------------------

    /// Load a register operand, zero-extended to the host register, at the
    /// operand's width.
    fn loadReg(self: *Compiler, dst: a64.Reg, id: RegId, high8: bool, size: Size) Error!void {
        const offset = gprOffset(id);
        switch (size) {
            .bits64 => try self.emitChecked(a64.ldrImm(.doubleword, dst, r_regs, offset)),
            .bits32 => try self.emitChecked(a64.ldrImm(.word, dst, r_regs, offset)),
            .bits16 => try self.emitChecked(a64.ldrImm(.half, dst, r_regs, offset)),
            .bits8 => try self.emitChecked(a64.ldrImm(.byte, dst, r_regs, offset + @as(u32, @intFromBool(high8)))),
        }
    }

    /// Store a result at the operand's width: 64 and 32 replace the whole
    /// register (32 zero-extends, as x86 does), 16 and 8 merge.
    fn storeReg(self: *Compiler, id: RegId, high8: bool, size: Size, src: a64.Reg) Error!void {
        const offset = gprOffset(id);
        switch (size) {
            .bits64 => try self.emitChecked(a64.strImm(.doubleword, src, r_regs, offset)),
            .bits32 => {
                // A w-register write already zeroed the upper half, but a
                // template that computed in x registers may not have; one
                // move makes the contract hold regardless.
                try self.emit(a64.mov(.w32, src, src));
                try self.emitChecked(a64.strImm(.doubleword, src, r_regs, offset));
            },
            .bits16 => try self.emitChecked(a64.strImm(.half, src, r_regs, offset)),
            .bits8 => try self.emitChecked(a64.strImm(.byte, src, r_regs, offset + @as(u32, @intFromBool(high8)))),
        }
    }

    fn loadFlags(self: *Compiler, dst: a64.Reg) Error!void {
        try self.emitChecked(a64.ldrImm(.word, dst, r_regs, rflags_offset));
    }

    fn storeFlags(self: *Compiler, src: a64.Reg) Error!void {
        try self.emitChecked(a64.strImm(.word, src, r_regs, rflags_offset));
    }

    /// `dst = dst & ~mask` for a 32-bit flags word, materialising the mask
    /// when the bitmask encoding refuses it.
    fn clearFlagBits(self: *Compiler, dst: a64.Reg, mask: u32) Error!void {
        const keep: u32 = ~mask;
        if (a64.logicalImmediate(.w32, .andop, dst, dst, keep)) |word| {
            try self.emit(word);
            return;
        }
        try self.a.loadConstant(t5, keep);
        try self.emit(a64.andReg(.w32, dst, dst, t5));
    }

    /// `flags |= bit_value << shift`, where `bit_value` is 0 or 1 in a
    /// w-register.
    fn orFlagBit(self: *Compiler, flags: a64.Reg, bit_value: a64.Reg, shift: u6) Error!void {
        try self.emit(a64.logicalShifted(.w32, .orr, flags, flags, bit_value, shift));
    }

    /// Set the low bit of `dst` to the parity flag of `value`'s low byte:
    /// 1 when the byte has an even number of one bits.
    fn emitParity(self: *Compiler, dst: a64.Reg, value: a64.Reg) Error!void {
        try self.emit(a64.logicalShifted(.w32, .eor, dst, value, value, 4) | (0b01 << 22)); // eor dst, value, value lsr #4
        try self.emit(a64.logicalShifted(.w32, .eor, dst, dst, dst, 2) | (0b01 << 22)); // lsr #2
        try self.emit(a64.logicalShifted(.w32, .eor, dst, dst, dst, 1) | (0b01 << 22)); // lsr #1
        try self.emit(a64.logicalImmediate(.w32, .andop, dst, dst, 1).?);
        try self.emit(a64.logicalImmediate(.w32, .eor, dst, dst, 1).?);
    }

    /// ZF, SF and PF of `result` (already masked to `size`) into `flags`.
    fn emitResultFlags(self: *Compiler, flags: a64.Reg, result: a64.Reg, size: Size) Error!void {
        const width = arm(size);
        try self.emitChecked(a64.cmpImm(width, result, 0));
        try self.emit(a64.cset(.w32, t4, .eq));
        try self.orFlagBit(flags, t4, 6);
        try self.emit(a64.ubfx(width, t4, result, @intCast(bits(size) - 1), 1));
        try self.orFlagBit(flags, t4, 7);
        try self.emitParity(t4, result);
        try self.orFlagBit(flags, t4, 2);
    }

    /// The flags of `a op b = r` exactly as `flags.applyAdd`, `applySub` and
    /// `applyLogic` compute them. `a`, `b` and `r` hold values masked to
    /// `size`; `r` may alias neither `a` nor `b`.
    fn emitArithmeticFlags(self: *Compiler, kind: ArithKind, size: Size, a: a64.Reg, b: a64.Reg, r: a64.Reg) Error!void {
        const width = arm(size);
        const w = bits(size);
        try self.loadFlags(t3);
        const mask: u32 = switch (kind) {
            .add, .sub => RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF,
            .logic => RFL_CF | RFL_PF | RFL_ZF | RFL_SF | RFL_OF,
        };
        try self.clearFlagBits(t3, mask);
        try self.emitResultFlags(t3, r, size);
        if (kind != .logic) {
            // AF: bit 4 of a ^ b ^ r.
            try self.emit(a64.eorReg(.w32, t4, a, b));
            try self.emit(a64.eorReg(.w32, t4, t4, r));
            try self.emit(a64.ubfx(.w32, t4, t4, 4, 1));
            try self.orFlagBit(t3, t4, 4);
            // CF.
            switch (kind) {
                .add => if (size == .bits64) {
                    // r = a + b mod 2^64 carried out exactly when r < a.
                    try self.emit(a64.cmp(.x64, r, a));
                    try self.emit(a64.cset(.w32, t4, .lo));
                } else {
                    // Both inputs are zero-extended, so the true sum's bit
                    // `w` is the carry.
                    try self.emit(a64.add(.x64, t4, a, b));
                    try self.emit(a64.ubfx(.x64, t4, t4, @intCast(w), 1));
                },
                .sub => {
                    try self.emit(a64.cmp(width, a, b));
                    try self.emit(a64.cset(.w32, t4, .lo));
                },
                .logic => unreachable,
            }
            try self.orFlagBit(t3, t4, 0);
            // OF: the sign bit of (a ^ r) & (add ? ~(a ^ b) : (a ^ b)).
            try self.emit(a64.eorReg(width, t4, a, b));
            try self.emit(a64.eorReg(width, t5, a, r));
            switch (kind) {
                .add => try self.emit(a64.bicReg(width, t5, t5, t4)),
                .sub => try self.emit(a64.andReg(width, t5, t5, t4)),
                .logic => unreachable,
            }
            try self.emit(a64.ubfx(width, t4, t5, @intCast(w - 1), 1));
            try self.orFlagBit(t3, t4, 11);
        }
        try self.storeFlags(t3);
    }

    // -- effective addresses --------------------------------------------------

    /// `dst = ` the effective address of the instruction's memory operand,
    /// as `resolveMemoryAddress` computes it from the live register file.
    fn emitEffectiveAddress(self: *Compiler, dst: a64.Reg, insn: Insn) Error!void {
        const d = insn.decoded;
        var displacement: u64 = d.addr;
        if (d.rip_relative) displacement +%= insn.rip +% d.len;
        try self.a.loadConstant(dst, displacement);
        if (d.sib_has_base) {
            try self.loadReg(t0, d.sib_base_reg, false, .bits64);
            try self.emit(a64.add(.x64, dst, dst, t0));
        }
        if (d.sib_has_index) {
            try self.loadReg(t0, d.sib_index_reg, false, .bits64);
            try self.emit(a64.addSubShifted(.x64, .add, false, dst, dst, t0, d.sib_scale));
        }
        if (d.has_0x67) try self.emit(a64.mov(.w32, dst, dst));
        switch (insn.segment) {
            .fs => {
                try self.emitChecked(a64.ldrImm(.doubleword, t0, r_regs, fs_base_offset));
                try self.emit(a64.add(.x64, dst, dst, t0));
            },
            .gs => {
                try self.emitChecked(a64.ldrImm(.doubleword, t0, r_regs, gs_base_offset));
                try self.emit(a64.add(.x64, dst, dst, t0));
            },
            else => {},
        }
    }

    // -- helper calls ---------------------------------------------------------

    fn emitCallHelper(self: *Compiler, offset: u32) Error!void {
        try self.emitChecked(a64.ldrImm(.doubleword, t0, r_helpers, offset));
        try self.emit(a64.blr(t0));
    }

    /// Tell the helpers which instruction is calling.
    fn emitCurrentIndex(self: *Compiler, index: u32) Error!void {
        try self.a.loadConstant(t0, index);
        try self.emitChecked(a64.strImm(.word, t0, r_scratch, scratch_index_offset));
    }

    /// x0 = read(state, x1, size), on behalf of instruction `index`.
    fn emitRead(self: *Compiler, size: Size, index: u32) Error!void {
        self.touches_memory = true;
        try self.emitCurrentIndex(index);
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.a.loadConstant(2, @intFromEnum(size));
        try self.emitCallHelper(helper_read_offset);
    }

    /// write(state, x1, size, x3), on behalf of instruction `index`.
    fn emitWrite(self: *Compiler, size: Size, index: u32) Error!void {
        self.touches_memory = true;
        try self.emitCurrentIndex(index);
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.a.loadConstant(2, @intFromEnum(size));
        try self.emitCallHelper(helper_write_offset);
    }

    /// Leave the block after instruction `index` when a helper asked for it.
    fn emitAbortCheck(self: *Compiler, index: u32) Error!void {
        const next_rip = self.insns[index].rip +% self.insns[index].len;
        const stub = try self.exitStub(index + 1, next_rip);
        try self.emitChecked(a64.ldrImm(.byte, t0, r_scratch, scratch_abort_offset));
        try self.a.branchIfNonZero(.w32, t0, stub);
    }

    // -- conditions -----------------------------------------------------------

    /// `dst` (w) = 1 when `cond` holds for the flags in `flags` (w), else 0.
    /// Mirrors `flags.evalCond`. Uses t5 as its own scratch, so `dst` may be
    /// any other temporary: the first version used t4 and was handed t4 as
    /// `dst`, which made every two-flag condition read its own output.
    fn emitCondition(self: *Compiler, dst: a64.Reg, flags: a64.Reg, cond: Cond) Error!void {
        const base: Cond = @enumFromInt(@intFromEnum(cond) & 0xE);
        switch (base) {
            .o => try self.emit(a64.ubfx(.w32, dst, flags, 11, 1)),
            .b => try self.emit(a64.logicalImmediate(.w32, .andop, dst, flags, 1).?),
            .e => try self.emit(a64.ubfx(.w32, dst, flags, 6, 1)),
            .be => {
                try self.emit(a64.ubfx(.w32, t5, flags, 6, 1));
                try self.emit(a64.logicalImmediate(.w32, .andop, dst, flags, 1).?);
                try self.emit(a64.orrReg(.w32, dst, dst, t5));
            },
            .s => try self.emit(a64.ubfx(.w32, dst, flags, 7, 1)),
            .p => try self.emit(a64.ubfx(.w32, dst, flags, 2, 1)),
            .l => {
                try self.emit(a64.ubfx(.w32, t5, flags, 7, 1));
                try self.emit(a64.ubfx(.w32, dst, flags, 11, 1));
                try self.emit(a64.eorReg(.w32, dst, dst, t5));
            },
            .le => {
                try self.emit(a64.ubfx(.w32, t5, flags, 7, 1));
                try self.emit(a64.ubfx(.w32, dst, flags, 11, 1));
                try self.emit(a64.eorReg(.w32, dst, dst, t5));
                try self.emit(a64.ubfx(.w32, t5, flags, 6, 1));
                try self.emit(a64.orrReg(.w32, dst, dst, t5));
            },
            else => unreachable,
        }
        if (@intFromEnum(cond) & 1 != 0) try self.emit(a64.logicalImmediate(.w32, .eor, dst, dst, 1).?);
    }

    // -- instructions ---------------------------------------------------------

    const Emitted = enum { native, fallback };

    fn emitFallback(self: *Compiler, index: u32) Error!void {
        self.fallback_count += 1;
        try self.emitCurrentIndex(index);
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitChecked(a64.ldrImm(.doubleword, 1, r_helpers, helper_block_offset));
        try self.a.loadConstant(2, index);
        try self.emitCallHelper(helper_interpret_offset);
        const stub = try self.exitStub(index + 1, null);
        try self.a.branchIfNonZero(.w32, 0, stub);
    }

    fn emitInsn(self: *Compiler, index: u32) Error!Emitted {
        const insn = self.insns[index];
        const d = insn.decoded;
        if (insn.force_fallback or !isNative(d)) {
            try self.emitFallback(index);
            return .fallback;
        }
        self.native_count += 1;
        switch (d.op) {
            .nop => {},
            .mov_reg8_reg8, .mov_reg16_reg16, .mov_reg32_reg32, .mov_reg64_reg64 => {
                const size: Size = switch (d.op) {
                    .mov_reg8_reg8 => .bits8,
                    .mov_reg16_reg16 => .bits16,
                    .mov_reg32_reg32 => .bits32,
                    else => .bits64,
                };
                try self.loadReg(t1, d.src_reg, d.src_high8, size);
                try self.storeReg(d.dst_reg, d.dst_high8, size, t1);
            },
            .mov_reg_imm => {
                try self.a.loadConstant(t1, d.imm & maskFor(d.size));
                try self.storeReg(d.dst_reg, d.dst_high8, d.size, t1);
            },
            .mov_reg8_mem8, .mov_reg16_mem16, .mov_reg32_mem32, .mov_reg64_mem64 => {
                const size: Size = switch (d.op) {
                    .mov_reg8_mem8 => .bits8,
                    .mov_reg16_mem16 => .bits16,
                    .mov_reg32_mem32 => .bits32,
                    else => .bits64,
                };
                try self.emitEffectiveAddress(1, insn);
                try self.emitRead(size, index);
                try self.storeReg(d.dst_reg, d.dst_high8, size, 0);
                try self.emitAbortCheck(index);
            },
            .mov_mem8_reg8, .mov_mem16_reg16, .mov_mem32_reg32, .mov_mem64_reg64 => {
                const size: Size = switch (d.op) {
                    .mov_mem8_reg8 => .bits8,
                    .mov_mem16_reg16 => .bits16,
                    .mov_mem32_reg32 => .bits32,
                    else => .bits64,
                };
                try self.loadReg(3, d.src_reg, d.src_high8, size);
                try self.emitEffectiveAddress(1, insn);
                try self.emitWrite(size, index);
                try self.emitAbortCheck(index);
            },
            .mov_mem8_imm8, .mov_mem16_imm16, .mov_mem32_imm32, .mov_mem64_imm32 => {
                const size: Size = switch (d.op) {
                    .mov_mem8_imm8 => .bits8,
                    .mov_mem16_imm16 => .bits16,
                    .mov_mem32_imm32 => .bits32,
                    else => .bits64,
                };
                try self.a.loadConstant(3, d.imm);
                try self.emitEffectiveAddress(1, insn);
                try self.emitWrite(size, index);
                try self.emitAbortCheck(index);
            },
            .movzx_reg32_mem8, .movzx_reg32_mem16 => {
                const source_size: Size = if (d.op == .movzx_reg32_mem8) .bits8 else .bits16;
                if (d.is_reg_form) {
                    try self.loadReg(t1, d.src_reg, d.src_high8, source_size);
                    try self.storeReg(d.dst_reg, false, d.size, t1);
                } else {
                    try self.emitEffectiveAddress(1, insn);
                    try self.emitRead(source_size, index);
                    try self.storeReg(d.dst_reg, false, d.size, 0);
                    try self.emitAbortCheck(index);
                }
            },
            .movsx_reg32_mem8, .movsx_reg32_mem16 => {
                const source_size: Size = if (d.op == .movsx_reg32_mem8) .bits8 else .bits16;
                // The interpreter widens a 16-bit destination to 32 bits.
                const dst_size: Size = if (d.size == .bits64) .bits64 else .bits32;
                const value: a64.Reg = if (d.is_reg_form) t1 else 0;
                if (d.is_reg_form) {
                    try self.loadReg(t1, d.src_reg, d.src_high8, source_size);
                } else {
                    try self.emitEffectiveAddress(1, insn);
                    try self.emitRead(source_size, index);
                }
                const width = arm(dst_size);
                if (source_size == .bits8) {
                    try self.emit(a64.sxtb(width, t2, value));
                } else {
                    try self.emit(a64.sxth(width, t2, value));
                }
                try self.storeReg(d.dst_reg, false, dst_size, t2);
                if (!d.is_reg_form) try self.emitAbortCheck(index);
            },
            .movsxd_reg64_reg32 => {
                try self.loadReg(t1, d.src_reg, false, .bits32);
                try self.emit(a64.sxtw(t2, t1));
                try self.storeReg(d.dst_reg, false, .bits64, t2);
            },
            .movsxd_reg64_mem32 => {
                try self.emitEffectiveAddress(1, insn);
                try self.emitRead(.bits32, index);
                try self.emit(a64.sxtw(t2, 0));
                try self.storeReg(d.dst_reg, false, .bits64, t2);
                try self.emitAbortCheck(index);
            },
            .lea_reg_mem => {
                try self.emitEffectiveAddress(t1, insn);
                try self.storeReg(d.dst_reg, false, d.size, t1);
            },
            .add_reg8_reg8, .add_reg16_reg16, .add_reg32_reg32, .add_reg64_reg64, .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64, .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64, .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64, .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64, .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64, .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64 => {
                try self.loadReg(t1, d.dst_reg, d.dst_high8, d.size);
                try self.loadReg(t2, d.src_reg, d.src_high8, d.size);
                try self.emitBinary(binaryOpOf(d.op).?, d.size, d.dst_reg, d.dst_high8);
            },
            .add_reg8_imm8, .add_reg16_imm8, .add_reg32_imm8, .add_reg64_imm8, .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8, .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8, .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8, .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8, .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8, .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32, .sub_reg16_imm32, .sub_reg32_imm32, .sub_reg64_imm32, .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32, .or_reg16_imm32, .or_reg32_imm32, .or_reg64_imm32, .xor_reg16_imm32, .xor_reg32_imm32, .xor_reg64_imm32, .cmp_reg16_imm32, .cmp_reg32_imm32, .cmp_reg64_imm32, .add_accum_imm, .sub_accum_imm, .and_accum_imm, .or_accum_imm, .xor_accum_imm, .cmp_accum_imm, .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => {
                try self.loadReg(t1, d.dst_reg, d.dst_high8, d.size);
                try self.a.loadConstant(t2, immediateValue(d) & maskFor(d.size));
                try self.emitBinary(binaryOpOf(d.op).?, d.size, d.dst_reg, d.dst_high8);
            },
            .inc_reg8, .inc_reg16, .inc_reg32, .inc_reg64, .dec_reg8, .dec_reg16, .dec_reg32, .dec_reg64 => {
                const size: Size = switch (d.op) {
                    .inc_reg8, .dec_reg8 => .bits8,
                    .inc_reg16, .dec_reg16 => .bits16,
                    .inc_reg32, .dec_reg32 => .bits32,
                    else => .bits64,
                };
                const is_inc = switch (d.op) {
                    .inc_reg8, .inc_reg16, .inc_reg32, .inc_reg64 => true,
                    else => false,
                };
                try self.emitIncDec(d.dst_reg, size, is_inc);
            },
            .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
                // setFlagsSub(0, a, r): a subtraction with a zero left side.
                try self.emit(a64.mov(.x64, t1, a64.xzr));
                try self.loadReg(t2, d.dst_reg, false, d.size);
                try self.emitBinary(.sub, d.size, d.dst_reg, false);
            },
            .not_reg8, .not_reg16, .not_reg32, .not_reg64 => {
                try self.loadReg(t1, d.dst_reg, false, d.size);
                try self.emit(a64.mvn(arm(d.size), t1, t1));
                try self.storeReg(d.dst_reg, false, d.size, t1);
            },
            .shl_reg_imm, .shr_reg_imm, .sar_reg_imm => try self.emitShift(d),
            .imul_reg64_reg64, .imul_reg32_reg32 => {
                // The interpreter arm names the width itself and ignores
                // `d.size`; the first differential run caught a 64-bit
                // product truncated to 32 bits from trusting the field.
                const size: Size = if (d.op == .imul_reg64_reg64) .bits64 else .bits32;
                try self.loadReg(t1, d.dst_reg, false, size);
                try self.loadReg(t2, d.src_reg, false, size);
                try self.emitImul(d.dst_reg, size);
            },
            .imul_reg32_reg32_imm8, .imul_reg32_reg32_imm32, .imul_reg64_reg64_imm8, .imul_reg64_reg64_imm32 => {
                const size: Size = switch (d.op) {
                    .imul_reg32_reg32_imm8, .imul_reg32_reg32_imm32 => .bits32,
                    else => .bits64,
                };
                const immediate: u64 = switch (d.op) {
                    .imul_reg32_reg32_imm8, .imul_reg64_reg64_imm8 => signExtendImm8(d.imm),
                    else => @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(d.imm)))))),
                };
                try self.loadReg(t1, d.src_reg, false, size);
                try self.a.loadConstant(t2, immediate & maskFor(size));
                try self.emitImul(d.dst_reg, size);
            },
            .cmovcc_reg_reg => {
                try self.loadFlags(t3);
                try self.emitCondition(t4, t3, d.cond);
                try self.loadReg(t1, d.dst_reg, false, d.size);
                try self.loadReg(t2, d.src_reg, false, d.size);
                try self.emitChecked(a64.cmpImm(.w32, t4, 0));
                try self.emit(a64.csel(arm(d.size), t1, t2, t1, .ne));
                try self.storeReg(d.dst_reg, false, d.size, t1);
            },
            .setcc_reg8 => {
                try self.loadFlags(t3);
                try self.emitCondition(t4, t3, d.cond);
                try self.storeReg(d.dst_reg, d.dst_high8, .bits8, t4);
            },
            .push_reg, .push_imm => {
                if (d.op == .push_reg) {
                    try self.loadReg(3, d.src_reg, false, .bits64);
                } else {
                    try self.a.loadConstant(3, d.imm);
                }
                try self.loadReg(1, .ah_sp_esp_rsp, false, .bits64);
                try self.emitChecked(a64.subImm(.x64, 1, 1, 8));
                try self.storeReg(.ah_sp_esp_rsp, false, .bits64, 1);
                try self.emitWrite(.bits64, index);
                try self.emitAbortCheck(index);
            },
            .pop_reg => {
                try self.loadReg(1, .ah_sp_esp_rsp, false, .bits64);
                try self.emitRead(.bits64, index);
                try self.loadReg(t1, .ah_sp_esp_rsp, false, .bits64);
                try self.emitChecked(a64.addImm(.x64, t1, t1, 8));
                try self.storeReg(.ah_sp_esp_rsp, false, .bits64, t1);
                try self.storeReg(d.dst_reg, false, .bits64, 0);
                try self.emitAbortCheck(index);
            },
            .cdqe => {
                try self.loadReg(t1, .al_ax_eax_rax, false, .bits32);
                try self.emit(a64.sxtw(t1, t1));
                try self.storeReg(.al_ax_eax_rax, false, .bits64, t1);
            },
            .cdq => {
                try self.loadReg(t1, .al_ax_eax_rax, false, .bits32);
                try self.emit(a64.asrImm(.w32, t1, t1, 31));
                try self.storeReg(.dl_dx_edx_rdx, false, .bits32, t1);
            },
            .cqo => {
                try self.loadReg(t1, .al_ax_eax_rax, false, .bits64);
                try self.emit(a64.asrImm(.x64, t1, t1, 63));
                try self.storeReg(.dl_dx_edx_rdx, false, .bits64, t1);
            },
            .bswap_reg => {
                try self.loadReg(t1, d.dst_reg, false, d.size);
                try self.emit(a64.rev(arm(d.size), t1, t1));
                try self.storeReg(d.dst_reg, false, d.size, t1);
            },
            .jcc_rel8, .jcc_rel32 => {
                // The decoder keeps the displacement in `addr` for jcc.
                const next = insn.rip +% d.len;
                const target = next +% d.addr;
                try self.loadFlags(t3);
                try self.emitCondition(t4, t3, d.cond);
                const taken = try self.exitStub(index + 1, target);
                try self.a.branchIfNonZero(.w32, t4, taken);
                const not_taken = try self.exitStub(index + 1, next);
                try self.a.branch(not_taken);
            },
            .jmp_rel8 => {
                const next = insn.rip +% d.len;
                const target = next +% d.imm;
                const stub = try self.exitStub(index + 1, target);
                try self.a.branch(stub);
            },
            else => unreachable,
        }
        return .native;
    }

    /// `dst op= t2` with t1 holding the destination's current value, both
    /// masked to `size`; writes the result (except cmp/test) and the flags.
    fn emitBinary(self: *Compiler, op: BinaryOp, size: Size, dst: RegId, dst_high8: bool) Error!void {
        const width = arm(size);
        // t0 = result, masked to the width.
        switch (op) {
            .add => try self.emit(a64.add(width, t0, t1, t2)),
            .sub, .cmp => try self.emit(a64.sub(width, t0, t1, t2)),
            .bit_and, .tst => try self.emit(a64.andReg(width, t0, t1, t2)),
            .bit_or => try self.emit(a64.orrReg(width, t0, t1, t2)),
            .bit_xor => try self.emit(a64.eorReg(width, t0, t1, t2)),
        }
        if (size == .bits8 or size == .bits16) {
            try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(size)).?);
        }
        const kind: ArithKind = switch (op) {
            .add => .add,
            .sub, .cmp => .sub,
            .bit_and, .bit_or, .bit_xor, .tst => .logic,
        };
        try self.emitArithmeticFlags(kind, size, t1, t2, t0);
        switch (op) {
            .cmp, .tst => {},
            else => try self.storeReg(dst, dst_high8, size, t0),
        }
    }

    /// `inc`/`dec`, with `flags.applyIncDec`: CF is preserved.
    fn emitIncDec(self: *Compiler, dst: RegId, size: Size, is_inc: bool) Error!void {
        const width = arm(size);
        const w = bits(size);
        try self.loadReg(t1, dst, false, size);
        if (is_inc) {
            try self.emitChecked(a64.addImm(width, t0, t1, 1));
        } else {
            try self.emitChecked(a64.subImm(width, t0, t1, 1));
        }
        if (size == .bits8 or size == .bits16) {
            try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(size)).?);
        }
        try self.loadFlags(t3);
        try self.clearFlagBits(t3, RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF);
        try self.emitResultFlags(t3, t0, size);
        // OF: inc overflows from the largest positive, dec from the smallest
        // negative.
        const sign: u64 = @as(u64, 1) << @intCast(w - 1);
        try self.a.loadConstant(t4, if (is_inc) sign - 1 else sign);
        try self.emit(a64.cmp(width, t1, t4));
        try self.emit(a64.cset(.w32, t4, .eq));
        try self.orFlagBit(t3, t4, 11);
        // AF: the low nibble wrapped.
        try self.emit(a64.logicalImmediate(.w32, .andop, t4, t1, 0xF).?);
        try self.emitChecked(a64.cmpImm(.w32, t4, if (is_inc) 0xF else 0));
        try self.emit(a64.cset(.w32, t4, .eq));
        try self.orFlagBit(t3, t4, 4);
        try self.storeFlags(t3);
        try self.storeReg(dst, false, size, t0);
    }

    /// Shift by an immediate at 32 or 64 bits, with the interpreter's
    /// `setFlagsShl/Shr/Sar`: CF, SF, ZF, and OF only when the count is one;
    /// PF and AF untouched; nothing when the count is zero.
    fn emitShift(self: *Compiler, d: DecodedInsn) Error!void {
        const size = d.size;
        const width = arm(size);
        const w = bits(size);
        const count: u6 = @intCast(d.imm & (if (size == .bits64) @as(u64, 0x3F) else 0x1F));
        try self.loadReg(t1, d.dst_reg, false, size);
        if (count == 0) {
            // `shlValue` still re-writes the register at its width.
            try self.storeReg(d.dst_reg, false, size, t1);
            return;
        }
        switch (d.op) {
            .shl_reg_imm => try self.emit(a64.lslImm(width, t0, t1, count)),
            .shr_reg_imm => try self.emit(a64.lsrImm(width, t0, t1, count)),
            .sar_reg_imm => try self.emit(a64.asrImm(width, t0, t1, count)),
            else => unreachable,
        }
        try self.loadFlags(t3);
        var mask: u32 = RFL_CF | RFL_SF | RFL_ZF;
        if (count == 1) mask |= RFL_OF;
        try self.clearFlagBits(t3, mask);
        // ZF and SF (PF deliberately not: the interpreter leaves it).
        try self.emitChecked(a64.cmpImm(width, t0, 0));
        try self.emit(a64.cset(.w32, t4, .eq));
        try self.orFlagBit(t3, t4, 6);
        try self.emit(a64.ubfx(width, t4, t0, @intCast(w - 1), 1));
        try self.orFlagBit(t3, t4, 7);
        // CF: the last bit shifted out.
        const cf_bit: u6 = switch (d.op) {
            .shl_reg_imm => @intCast(w - count),
            else => count - 1,
        };
        try self.emit(a64.ubfx(width, t4, t1, cf_bit, 1));
        try self.orFlagBit(t3, t4, 0);
        if (count == 1) {
            switch (d.op) {
                .shl_reg_imm => {
                    // OF = msb(result) != CF.
                    try self.emit(a64.ubfx(width, t5, t0, @intCast(w - 1), 1));
                    try self.emit(a64.eorReg(.w32, t4, t4, t5));
                },
                .shr_reg_imm => try self.emit(a64.ubfx(width, t4, t1, @intCast(w - 1), 1)),
                .sar_reg_imm => try self.emit(a64.mov(.w32, t4, a64.wzr)),
                else => unreachable,
            }
            try self.orFlagBit(t3, t4, 11);
        }
        try self.storeFlags(t3);
        try self.storeReg(d.dst_reg, false, size, t0);
    }

    /// `dst = low bits of t1 * t2`; CF = OF = the signed product does not fit.
    fn emitImul(self: *Compiler, dst: RegId, size: Size) Error!void {
        if (size == .bits64) {
            try self.emit(a64.mul(.x64, t0, t1, t2));
            try self.emit(a64.smulh(t4, t1, t2));
            try self.emit(a64.asrImm(.x64, t5, t0, 63));
            try self.emit(a64.cmp(.x64, t4, t5));
        } else {
            try self.emit(a64.smull(t0, t1, t2));
            try self.emit(a64.sxtw(t4, t0));
            try self.emit(a64.cmp(.x64, t4, t0));
        }
        try self.emit(a64.cset(.w32, t4, .ne));
        try self.loadFlags(t3);
        try self.clearFlagBits(t3, RFL_CF | RFL_OF);
        try self.orFlagBit(t3, t4, 0);
        try self.orFlagBit(t3, t4, 11);
        try self.storeFlags(t3);
        try self.storeReg(dst, false, size, t0);
    }
};

/// Compile `insns` (contiguous, `end_rip` one past the last byte) into
/// `memory`. A block whose every instruction would be a fallback is refused:
/// it would cost a helper call per instruction and save nothing.
pub fn compile(allocator: std.mem.Allocator, memory: *CodeMemory, layout: Layout, insns: []const Insn, end_rip: u64) Error!Compiled {
    if (insns.len == 0) return Error.NothingToCompile;
    var native: u32 = 0;
    for (insns) |insn| {
        if (!insn.force_fallback and isNative(insn.decoded)) native += 1;
    }
    if (native == 0) return Error.NothingToCompile;

    var assembler = Assembler.init(allocator);
    defer assembler.deinit();
    var compiler = Compiler{
        .a = &assembler,
        .layout = layout,
        .insns = insns,
        .end_rip = end_rip,
        .epilogue = try assembler.createLabel(),
        .exits = .empty,
        .allocator = allocator,
    };
    defer compiler.exits.deinit(allocator);

    try compiler.emitPrologue();
    var terminated = false;
    for (insns, 0..) |insn, index| {
        _ = try compiler.emitInsn(@intCast(index));
        if (isTerminator(insn.decoded.op) and !insn.force_fallback) {
            terminated = true;
            break;
        }
    }
    if (!terminated) {
        const stub = try compiler.exitStub(@intCast(insns.len), end_rip);
        try assembler.branch(stub);
    }
    try compiler.emitExitStubs();
    try compiler.emitEpilogue();
    const words = try assembler.finish();

    const code = try memory.reserve(words.len);
    memory.beginWrite();
    @memcpy(code, words);
    memory.endWrite(code);
    return .{
        .code = code,
        .native_count = compiler.native_count,
        .fallback_count = compiler.fallback_count,
        .register_only = !compiler.touches_memory and compiler.fallback_count == 0,
    };
}

// ---------------------------------------------------------------------------
// Tests
//
// These run the emitted code on this host against a small state and compare
// with the same flag helpers the interpreter uses. They check the templates;
// the interpreter-versus-block differential tests live with the interpreter
// in process.zig.
// ---------------------------------------------------------------------------

const testing = std.testing;

const TestState = struct {
    regs: Regs = .{},
    scratch: Scratch = .{},
    reads: u32 = 0,
    writes: u32 = 0,
    interprets: u32 = 0,
    last_interpret_index: u32 = 0,
    last_helper_index: u32 = 0,
    interpret_result: u32 = 0,
    abort_on_access: bool = false,
    memory: [4096]u8 = [_]u8{0} ** 4096,

    const layout = Layout{
        .regs_offset = @offsetOf(TestState, "regs"),
        .scratch_offset = @offsetOf(TestState, "scratch"),
    };

    fn read(state_ptr: *anyopaque, address: u64, size: u8) callconv(.c) u64 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.reads += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) state.scratch.abort = 1;
        const width: usize = @as(usize, 1) << @intCast(size);
        if (address + width > state.memory.len) return 0;
        var value: u64 = 0;
        for (0..width) |i| value |= @as(u64, state.memory[@intCast(address + i)]) << @intCast(i * 8);
        return value;
    }

    fn write(state_ptr: *anyopaque, address: u64, size: u8, value: u64) callconv(.c) void {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.writes += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) state.scratch.abort = 1;
        const width: usize = @as(usize, 1) << @intCast(size);
        if (address + width > state.memory.len) return;
        for (0..width) |i| state.memory[@intCast(address + i)] = @truncate(value >> @intCast(i * 8));
    }

    fn interpret(state_ptr: *anyopaque, block: *const Block, index: u32) callconv(.c) u32 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.interprets += 1;
        state.last_interpret_index = index;
        // The scratch index must agree with the argument.
        if (state.scratch.index != index) state.regs.r15 = 0xBAD_1DE7;
        // Pretend the instruction advanced RIP by its length, as `execute`
        // would for a non-branch.
        const insn = block.insns[index];
        state.regs.rip = insn.rip + insn.len;
        return state.interpret_result;
    }
};

const TestHarness = struct {
    memory: CodeMemory,
    block: Block,
    insns: std.ArrayList(Insn),

    fn init() !TestHarness {
        if (!CodeMemory.available()) return error.SkipZigTest;
        return .{
            .memory = try CodeMemory.init(256 * 1024),
            .block = undefined,
            .insns = .empty,
        };
    }

    fn deinit(self: *TestHarness) void {
        self.insns.deinit(testing.allocator);
        self.memory.deinit();
    }

    fn add(self: *TestHarness, rip: u64, len: u8, d: DecodedInsn) !void {
        var decoded = d;
        decoded.len = len;
        try self.insns.append(testing.allocator, .{ .rip = rip, .len = len, .decoded = decoded, .segment = .ds });
    }

    /// Compile the queued instructions and run them once on `state`.
    fn run(self: *TestHarness, state: *TestState) !u32 {
        const insns = self.insns.items;
        const last = insns[insns.len - 1];
        const compiled = try compile(testing.allocator, &self.memory, TestState.layout, insns, last.rip + last.len);
        self.block = .{
            .helpers = undefined,
            .start_rip = insns[0].rip,
            .end_rip = last.rip + last.len,
            .insns = insns,
            .bytes = &.{},
            .code = compiled.code,
            .native_count = compiled.native_count,
            .fallback_count = compiled.fallback_count,
            .register_only = compiled.register_only,
        };
        self.block.helpers = .{
            .read = TestState.read,
            .write = TestState.write,
            .interpret = TestState.interpret,
            .block = &self.block,
        };
        state.scratch.abort = 0;
        state.scratch.block = &self.block;
        return self.block.entry()(state, &self.block.helpers);
    }
};

fn regReg(op: Op, size: Size, dst: RegId, src: RegId) DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = dst, .src_reg = src, .is_reg_form = true };
}

fn regImm(op: Op, size: Size, dst: RegId, imm: u64) DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = dst, .imm = imm, .is_reg_form = true, .uses_imm = true };
}

test "register moves respect operand width and zero extension" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rax = 0x1122_3344_5566_7788;
    state.regs.rbx = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rcx = 0xAAAA_AAAA_AAAA_AAAA;
    // mov ebx, eax ; mov cl, al ; mov ch, al ; mov dx, ax ; mov r9, 0x123456789 ; mov r10d, 0xFFFFFFFF
    try h.add(0x1000, 2, regReg(.mov_reg32_reg32, .bits32, .bl_bx_ebx_rbx, .al_ax_eax_rax));
    try h.add(0x1002, 2, regReg(.mov_reg8_reg8, .bits8, .cl_cx_ecx_rcx, .al_ax_eax_rax));
    var high = regReg(.mov_reg8_reg8, .bits8, .cl_cx_ecx_rcx, .al_ax_eax_rax);
    high.dst_high8 = true;
    try h.add(0x1004, 2, high);
    try h.add(0x1006, 3, regReg(.mov_reg16_reg16, .bits16, .dl_dx_edx_rdx, .al_ax_eax_rax));
    try h.add(0x1009, 10, regImm(.mov_reg_imm, .bits64, .r9b_r9w_r9d_r9, 0x1_2345_6789));
    try h.add(0x1013, 6, regImm(.mov_reg_imm, .bits32, .r10b_r10w_r10d_r10, 0xFFFF_FFFF));
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 6), completed);
    try testing.expectEqual(@as(u64, 0x5566_7788), state.regs.rbx);
    try testing.expectEqual(@as(u64, 0xAAAA_AAAA_AAAA_8888), state.regs.rcx);
    try testing.expectEqual(@as(u64, 0x7788), state.regs.rdx);
    try testing.expectEqual(@as(u64, 0x1_2345_6789), state.regs.r9);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.r10);
    try testing.expectEqual(@as(u64, 0x1019), state.regs.rip);
    try testing.expect(h.block.register_only);
}

fn referenceBinary(op: BinaryOp, size: Size, a: u64, b: u64, rflags: *u32) u64 {
    const mask = maskFor(size);
    const r: u64 = switch (op) {
        .add => (a +% b) & mask,
        .sub, .cmp => (a -% b) & mask,
        .bit_and, .tst => (a & b) & mask,
        .bit_or => (a | b) & mask,
        .bit_xor => (a ^ b) & mask,
    };
    switch (op) {
        .add => x64_decoder.applyAdd(rflags, a, b, r, size),
        .sub, .cmp => x64_decoder.applySub(rflags, a, b, r, size),
        else => x64_decoder.applyLogic(rflags, r, size),
    }
    return r;
}

test "register arithmetic produces the interpreter's flags at every width" {
    var h = try TestHarness.init();
    defer h.deinit();
    var prng = std.Random.DefaultPrng.init(0x5EED_0001);
    const random = prng.random();
    const ops = [_]struct { op: Op, kind: BinaryOp, size: Size }{
        .{ .op = .add_reg64_reg64, .kind = .add, .size = .bits64 },
        .{ .op = .add_reg32_reg32, .kind = .add, .size = .bits32 },
        .{ .op = .add_reg16_reg16, .kind = .add, .size = .bits16 },
        .{ .op = .add_reg8_reg8, .kind = .add, .size = .bits8 },
        .{ .op = .sub_reg64_reg64, .kind = .sub, .size = .bits64 },
        .{ .op = .sub_reg32_reg32, .kind = .sub, .size = .bits32 },
        .{ .op = .sub_reg16_reg16, .kind = .sub, .size = .bits16 },
        .{ .op = .sub_reg8_reg8, .kind = .sub, .size = .bits8 },
        .{ .op = .and_reg64_reg64, .kind = .bit_and, .size = .bits64 },
        .{ .op = .or_reg32_reg32, .kind = .bit_or, .size = .bits32 },
        .{ .op = .xor_reg16_reg16, .kind = .bit_xor, .size = .bits16 },
        .{ .op = .cmp_reg64_reg64, .kind = .cmp, .size = .bits64 },
        .{ .op = .cmp_reg8_reg8, .kind = .cmp, .size = .bits8 },
        .{ .op = .test_reg32_reg32, .kind = .tst, .size = .bits32 },
    };
    for (ops) |entry| {
        for (0..64) |_| {
            var state = TestState{};
            const a = switch (random.uintLessThan(u8, 4)) {
                0 => random.int(u64),
                1 => maskFor(entry.size),
                2 => @as(u64, 1) << @intCast(bits(entry.size) - 1),
                else => random.int(u8),
            };
            const b = switch (random.uintLessThan(u8, 4)) {
                0 => random.int(u64),
                1 => maskFor(entry.size),
                2 => a,
                else => random.int(u8),
            };
            state.regs.rsi = a;
            state.regs.rdi = b;
            state.regs.rflags = (random.int(u32) & 0xFFF) | 0x2;
            var expected_flags = state.regs.rflags;
            const expected = referenceBinary(entry.kind, entry.size, a & maskFor(entry.size), b & maskFor(entry.size), &expected_flags);
            h.insns.clearRetainingCapacity();
            try h.add(0x2000, 3, regReg(entry.op, entry.size, .dh_si_esi_rsi, .bh_di_edi_rdi));
            _ = try h.run(&state);
            try testing.expectEqual(expected_flags, state.regs.rflags);
            const expected_reg: u64 = switch (entry.kind) {
                .cmp, .tst => a,
                else => switch (entry.size) {
                    .bits64, .bits32 => expected,
                    .bits16 => (a & ~@as(u64, 0xFFFF)) | expected,
                    .bits8 => (a & ~@as(u64, 0xFF)) | expected,
                },
            };
            try testing.expectEqual(expected_reg, state.regs.rsi);
            try testing.expectEqual(b, state.regs.rdi);
        }
    }
}

test "immediate forms sign-extend the way the interpreter does" {
    var h = try TestHarness.init();
    defer h.deinit();
    // add rax, -1 (imm8) ; and ecx, 0x80000000 (imm32) ; cmp rdx, -2 (imm32 sign-extended) ; test al, 0x80
    var state = TestState{};
    state.regs.rax = 5;
    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rdx = 0xFFFF_FFFF_FFFF_FFFE;
    state.regs.rflags = 0x2;
    try h.add(0x3000, 4, regImm(.add_reg64_imm8, .bits64, .al_ax_eax_rax, 0xFF));
    try h.add(0x3004, 6, regImm(.and_reg32_imm32, .bits32, .cl_cx_ecx_rcx, 0x8000_0000));
    try h.add(0x300A, 7, regImm(.cmp_reg64_imm32, .bits64, .dl_dx_edx_rdx, 0xFFFF_FFFE));
    try h.add(0x3011, 2, regImm(.test_reg8_imm8, .bits8, .al_ax_eax_rax, 0x80));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 4), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x8000_0000), state.regs.rcx);
    // cmp rdx, -2 with rdx == -2: ZF set. test al(4), 0x80: ZF set, SF clear, PF set (zero has even parity).
    try testing.expect(state.regs.rflags & RFL_ZF != 0);
    try testing.expect(state.regs.rflags & RFL_SF == 0);
    try testing.expect(state.regs.rflags & RFL_PF != 0);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
}

test "inc, dec, neg, not, shifts and imul follow the interpreter's flag rules" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    // inc eax from 0x7FFFFFFF: OF set, CF preserved (set beforehand).
    state.regs.rax = 0x7FFF_FFFF;
    state.regs.rflags = 0x2 | RFL_CF;
    try h.add(0x4000, 2, .{ .op = .inc_reg32, .size = .bits32, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x8000_0000), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_AF != 0);

    // dec rbx from 0: SF set, AF set (low nibble was zero), ZF clear.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0;
    state.regs.rflags = 0x2;
    try h.add(0x4000, 3, .{ .op = .dec_reg64, .size = .bits64, .dst_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FFFF), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expect(state.regs.rflags & RFL_AF != 0);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);

    // neg ecx (5): result -5, CF set (nonzero), matches applySub(0, 5, r).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rcx = 5;
    state.regs.rflags = 0x2;
    try h.add(0x4000, 2, .{ .op = .neg_reg32, .size = .bits32, .dst_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    var reference: u32 = 0x2;
    _ = referenceBinary(.sub, .bits32, 0, 5, &reference);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFB), state.regs.rcx);
    try testing.expectEqual(reference, state.regs.rflags);

    // not rdx leaves flags alone.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdx = 0x00FF;
    state.regs.rflags = 0x8D7;
    try h.add(0x4000, 3, .{ .op = .not_reg64, .size = .bits64, .dst_reg = .dl_dx_edx_rdx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FF00), state.regs.rdx);
    try testing.expectEqual(@as(u32, 0x8D7), state.regs.rflags);

    // shl rsi, 1 with the top bit set: CF set, OF = msb(result) != CF, PF untouched.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rsi = 0xC000_0000_0000_0001;
    state.regs.rflags = 0x2 | RFL_PF;
    try h.add(0x4000, 4, regImm(.shl_reg_imm, .bits64, .dh_si_esi_rsi, 1));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x8000_0000_0000_0002), state.regs.rsi);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF == 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expect(state.regs.rflags & RFL_PF != 0);

    // shr edi, 4 on 0x1F: result 1, CF = bit 3 = 1, ZF clear; OF untouched (count != 1).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdi = 0xFFFF_FFFF_0000_001F;
    state.regs.rflags = 0x2 | RFL_OF;
    try h.add(0x4000, 3, regImm(.shr_reg_imm, .bits32, .bh_di_edi_rdi, 4));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 1), state.regs.rdi);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);

    // sar r8, 63 on a negative value: all ones, CF = bit 62.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.r8 = 0x8000_0000_0000_0000;
    state.regs.rflags = 0x2;
    try h.add(0x4000, 4, regImm(.sar_reg_imm, .bits64, .r8b_r8w_r8d_r8, 63));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FFFF), state.regs.r8);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);

    // imul r9d, r10d overflowing: CF and OF set, low 32 bits kept.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.r9 = 0x7FFF_FFFF;
    state.regs.r10 = 2;
    state.regs.rflags = 0x2;
    try h.add(0x4000, 4, regReg(.imul_reg32_reg32, .bits32, .r9b_r9w_r9d_r9, .r10b_r10w_r10d_r10));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFE), state.regs.r9);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_OF != 0);

    // imul r11, r12, 3 fitting: flags clear.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.r12 = 7;
    state.regs.rflags = 0x2 | RFL_CF | RFL_OF;
    var imm_form = regReg(.imul_reg64_reg64_imm8, .bits64, .r11b_r11w_r11d_r11, .r12b_r12w_r12d_r12);
    imm_form.imm = 3;
    try h.add(0x4000, 4, imm_form);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 21), state.regs.r11);
    try testing.expect(state.regs.rflags & (RFL_CF | RFL_OF) == 0);
}

test "conditions, conditional moves and setcc evaluate every x86 condition" {
    var h = try TestHarness.init();
    defer h.deinit();
    const flag_values = [_]u32{ 0x2, RFL_CF, RFL_ZF, RFL_SF, RFL_OF, RFL_PF, RFL_SF | RFL_OF, RFL_ZF | RFL_CF, RFL_ZF | RFL_SF, 0x8D5 };
    for (flag_values) |flags| {
        for (0..16) |cond_index| {
            const cond: Cond = @enumFromInt(cond_index);
            var state = TestState{};
            state.regs.rflags = flags;
            state.regs.rax = 0x1111_1111_1111_1111;
            state.regs.rbx = 0x2222_2222_2222_2222;
            h.insns.clearRetainingCapacity();
            var setcc: DecodedInsn = .{ .op = .setcc_reg8, .size = .bits8, .dst_reg = .cl_cx_ecx_rcx, .cond = cond, .is_reg_form = true };
            setcc.dst_high8 = false;
            try h.add(0x5000, 3, setcc);
            var cmov = regReg(.cmovcc_reg_reg, .bits32, .al_ax_eax_rax, .bl_bx_ebx_rbx);
            cmov.cond = cond;
            try h.add(0x5003, 3, cmov);
            _ = try h.run(&state);
            const expected = x64_decoder.evalCond(flags, cond);
            try testing.expectEqual(@as(u64, @intFromBool(expected)), state.regs.rcx & 0xFF);
            // A 32-bit cmov zero-extends whether or not it moves.
            try testing.expectEqual(if (expected) @as(u64, 0x2222_2222) else @as(u64, 0x1111_1111), state.regs.rax);
        }
    }
}

test "relative branches leave the right rip and count on both paths" {
    var h = try TestHarness.init();
    defer h.deinit();
    // cmp rax, rbx ; jne +0x20 (rel8 in `addr`)
    var jcc: DecodedInsn = .{ .op = .jcc_rel8, .cond = .ne, .addr = 0x20 };
    jcc.rip_relative = true;
    for ([_]bool{ true, false }) |equal| {
        var state = TestState{};
        state.regs.rax = 10;
        state.regs.rbx = if (equal) 10 else 11;
        h.insns.clearRetainingCapacity();
        try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        try h.add(0x6003, 2, jcc);
        const completed = try h.run(&state);
        try testing.expectEqual(@as(u32, 2), completed);
        try testing.expectEqual(if (equal) @as(u64, 0x6005) else @as(u64, 0x6025), state.regs.rip);
    }
    // jmp -0x10 (rel8 in `imm`), and a negative displacement wraps correctly.
    h.insns.clearRetainingCapacity();
    var state = TestState{};
    try h.add(0x7000, 2, .{ .op = .jmp_rel8, .imm = @bitCast(@as(i64, -0x10)) });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x6FF2), state.regs.rip);
    // A block that ends without a branch stores the fall-through rip.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    try h.add(0x8000, 1, .{ .op = .nop, .len = 1 });
    try h.add(0x8001, 3, regReg(.mov_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try testing.expectEqual(@as(u32, 2), try h.run(&state));
    try testing.expectEqual(@as(u64, 0x8004), state.regs.rip);
}

test "memory operands reach the helpers with the resolved address and an abort stops the block after the instruction" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    // mov rax, [rbx + rcx*8 + 0x10] with rbx=0x100 rcx=2 → address 0x120
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 0xDEAD_BEEF_CAFE_F00D, .little);
    state.regs.rbx = 0x100;
    state.regs.rcx = 2;
    var load: DecodedInsn = .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .al_ax_eax_rax, .addr = 0x10 };
    load.sib_has_base = true;
    load.sib_base_reg = .bl_bx_ebx_rbx;
    load.sib_has_index = true;
    load.sib_index_reg = .cl_cx_ecx_rcx;
    load.sib_scale = 3;
    try h.add(0x9000, 5, load);
    // mov [rip + 0x100], eax → address = 0x9005 + 0x100 = 0x9105, beyond the test memory: write is dropped but counted.
    var store: DecodedInsn = .{ .op = .mov_mem32_reg32, .size = .bits32, .src_reg = .al_ax_eax_rax, .addr = 0x100, .rip_relative = true };
    store.len = 6;
    try h.add(0x9005, 6, store);
    // lea rdx, [rbx + 0x40]
    var lea: DecodedInsn = .{ .op = .lea_reg_mem, .size = .bits64, .dst_reg = .dl_dx_edx_rdx, .addr = 0x40 };
    lea.sib_has_base = true;
    lea.sib_base_reg = .bl_bx_ebx_rbx;
    try h.add(0x900B, 4, lea);
    // push rax ; pop rsi
    state.regs.rsp = 0x800;
    try h.add(0x900F, 1, .{ .op = .push_reg, .src_reg = .al_ax_eax_rax });
    try h.add(0x9010, 1, .{ .op = .pop_reg, .dst_reg = .dh_si_esi_rsi });
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 5), completed);
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF_CAFE_F00D), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x140), state.regs.rdx);
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF_CAFE_F00D), state.regs.rsi);
    try testing.expectEqual(@as(u64, 0x800), state.regs.rsp);
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF_CAFE_F00D), std.mem.readInt(u64, state.memory[0x7F8..][0..8], .little));
    try testing.expectEqual(@as(u32, 2), state.reads);
    try testing.expectEqual(@as(u32, 2), state.writes);
    // The pop was instruction 4 and was the last helper caller.
    try testing.expectEqual(@as(u32, 4), state.last_helper_index);
    try testing.expect(!h.block.register_only);

    // The same block with a helper that raises the abort flag: the load
    // completes (rax written), then the block leaves with rip at the store.
    state = TestState{};
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 0x1234, .little);
    state.regs.rbx = 0x100;
    state.regs.rcx = 2;
    state.regs.rsp = 0x800;
    state.abort_on_access = true;
    const aborted = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), aborted);
    try testing.expectEqual(@as(u64, 0x1234), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x9005), state.regs.rip);
}

test "an unsupported instruction is handed to the interpreter helper and its exit request ends the block" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rax = 1;
    state.regs.rbx = 2;
    // add rax, rbx ; <unsupported: shl rax, cl> ; add rax, rbx
    try h.add(0xA000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0xA003, 3, .{ .op = .shl_reg_cl, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    try h.add(0xA006, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 3), completed);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u32, 1), state.last_interpret_index);
    try testing.expectEqual(@as(u64, 5), state.regs.rax);
    try testing.expectEqual(@as(u64, 0xA009), state.regs.rip);
    try testing.expectEqual(@as(u32, 2), h.block.native_count);
    try testing.expectEqual(@as(u32, 1), h.block.fallback_count);

    // When the interpreter says the block must stop, it stops after that
    // instruction with the interpreter's rip untouched.
    state = TestState{};
    state.regs.rax = 1;
    state.regs.rbx = 2;
    state.interpret_result = 1;
    completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 2), completed);
    try testing.expectEqual(@as(u64, 3), state.regs.rax);
    try testing.expectEqual(@as(u64, 0xA006), state.regs.rip);
}

test "a block with nothing native to emit is refused" {
    var h = try TestHarness.init();
    defer h.deinit();
    try h.add(0xB000, 3, .{ .op = .shl_reg_cl, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    var state = TestState{};
    try testing.expectError(Error.NothingToCompile, h.run(&state));
}

test "the block boundary rules keep control transfers and the scheduling point with the interpreter" {
    try testing.expect(endsBlockBefore(.{ .op = .call_rel32 }));
    try testing.expect(endsBlockBefore(.{ .op = .ret }));
    try testing.expect(endsBlockBefore(.{ .op = .nop, .len = 2 }));
    try testing.expect(!endsBlockBefore(.{ .op = .nop, .len = 1 }));
    try testing.expect(isTerminator(.jcc_rel32) and isTerminator(.jmp_rel8) and !isTerminator(.call_rel32));
    try testing.expect(!isNative(.{ .op = .add_reg64_reg64, .lock = true }));
    try testing.expect(!isNative(.{ .op = .shl_reg_imm, .size = .bits16 }));
    try testing.expect(isNative(.{ .op = .shl_reg_imm, .size = .bits32 }));
}
