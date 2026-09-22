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
//! The compiled subset is the integer core a compiler and Xenia's own x64
//! emitter produce most: moves, `movbe`, zero/sign extension, `lea`, the
//! Group-1 arithmetic and logic on registers, immediates and memory operands
//! (both directions), `adc`/`sbb`, `inc`/`dec`/`neg`/`not`, shifts and
//! rotates by immediate and by `cl`, `imul`, the one-operand `mul`/`imul`,
//! `div`/`idiv` when the quotient provably fits, `bt`/`bts`/`btr`,
//! `bsf`/`bsr`/`tzcnt`/`lzcnt`, `cmovcc`/`setcc`, `xchg`, `push`/`pop`, and
//! the relative branches, which end a block.
//!
//! Loads and stores take one of two paths. The fast path is a software TLB
//! that lives in the state (`Tlb`): a direct-mapped table of guest pages whose
//! host bytes may be touched directly, one table for reads and one for writes.
//! The emitted code hashes the page, compares the tag, checks that the access
//! stays inside the page, and loads or stores through the host pointer: about
//! a dozen instructions and no call. Every miss calls `ElfState`'s own
//! `readMemVal`/`writeMemVal` through the C-ABI helpers, so the null-page
//! rule, the mapped-memory model, the page-protection faults and the
//! code-generation bumps all keep applying; the glue decides after each such
//! access whether the page may enter the TLB (accessible, backed, not
//! executable code for writes, no trace watch) and invalidates entries when
//! protection or mappings change. The TLB never holds a page a helper would
//! have refused, so the fast path can never fault.
//!
//! Anything else in the middle of a block is handed to the interpreter for
//! that one instruction, through a helper that resolves the address and calls
//! `execute`. Control transfers other than relative branches (`call`, `ret`,
//! indirect jumps, `loop`) are compiled the same way but *end* the block: the
//! interpreter's own arm, with its milestone, kernel-call, accelerator and
//! shim hooks, runs the transfer and the block returns to `step` at the
//! target. The instructions that reach the host or the scheduler (`syscall`,
//! `hlt`, `cpuid`, `pause`) still end a block before themselves.
//!
//! ## Flags
//!
//! Flags are computed exactly as `flags.zig` computes them, including PF and
//! AF, and the instructions that leave a flag alone in the interpreter leave
//! it alone here (shifts do not touch PF or AF; `inc`/`dec` keep CF). They are
//! not computed eagerly for every instruction: a liveness pass over the block
//! finds the writers whose every written flag is overwritten by a later native
//! writer before any reader, and those emit no flag code at all. Readers are
//! `jcc`/`setcc`/`cmovcc`/`adc`/`sbb`, every interpreted instruction, and the
//! end of the block; an abort exit after a memory helper is not a reader,
//! because execution resumes on the same straight-line path either at the
//! faulting instruction or after it, and the writer that made the flags dead
//! still runs before anything can read them.
//!
//! ## Calling convention
//!
//! A block is `fn (state, helpers) callconv(.c) u32`. It returns how many of
//! its instructions completed; the guest RIP is always left in
//! `state.regs.rip` by whichever path left the block. x19 holds the state,
//! x20 the register file, x21 the helper table, x22 the scratch record, x23
//! the TLB and x24 the vector register file for the life of the block;
//! x9-x15 are scratch and nothing lives in them across a helper call.

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
    /// left a fault pending or ended the run. The glue may install the page
    /// in the read TLB afterwards.
    read: *const fn (state: *anyopaque, address: u64, size: u8) callconv(.c) u64,
    /// `writeMemVal(state, address, size, value)`. Same abort rule; may
    /// install the page in the write TLB.
    write: *const fn (state: *anyopaque, address: u64, size: u8, value: u64) callconv(.c) void,
    /// `readMem128(state, address)` into `out` (the scratch vector slot).
    read128: *const fn (state: *anyopaque, address: u64, out: *[16]u8) callconv(.c) void,
    /// `writeMem128(state, address, value.*)` from the scratch vector slot.
    write128: *const fn (state: *anyopaque, address: u64, value: *const [16]u8) callconv(.c) void,
    /// Execute instruction `index` of the block through the interpreter.
    /// Returns 0 when the block may continue with the next instruction and
    /// nonzero when it must stop (control transfer, fault, termination).
    interpret: *const fn (state: *anyopaque, block: *const Block, index: u32) callconv(.c) u32,
    /// The block these helpers belong to, for the interpret call.
    block: *const Block,
    /// Apply the deferred flag record to `rflags` and clear it. Called on
    /// the way out of a block, and by the interpret helper before the
    /// interpreter can read a flag the record still owns.
    flags: *const fn (state: *anyopaque) callconv(.c) void,
};

const helper_read_offset: u32 = @offsetOf(Helpers, "read");
const helper_write_offset: u32 = @offsetOf(Helpers, "write");
const helper_read128_offset: u32 = @offsetOf(Helpers, "read128");
const helper_write128_offset: u32 = @offsetOf(Helpers, "write128");
const helper_interpret_offset: u32 = @offsetOf(Helpers, "interpret");
const helper_block_offset: u32 = @offsetOf(Helpers, "block");
const helper_flags_offset: u32 = @offsetOf(Helpers, "flags");

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
    /// The 16-byte value a vector memory helper reads into or writes from.
    vector: [16]u8 align(16) = @splat(0),
    /// The deferred flag record: which arithmetic produced the flags that
    /// `regs.rflags` does not yet hold in full, and the values to derive
    /// them from. Zero means `rflags` is complete and authoritative.
    ///
    /// Materialising all six x86 flags costs about thirty ARM instructions -
    /// a six-instruction parity fold, four for the auxiliary carry, five for
    /// overflow - and a translated block pays it at *every* arithmetic
    /// instruction, because anything that leaves the block may read any
    /// flag. Recording the operands instead lets a writer compute only what
    /// a later instruction in its own block actually reads, and hands the
    /// rest to one call on the way out.
    flag_kind: u8 = 0,
    flag_size: u8 = 0,
    flag_reserved: [6]u8 = @splat(0),
    flag_a: u64 = 0,
    flag_b: u64 = 0,
    flag_r: u64 = 0,
    /// An indirect call's target, held across the push: the push can call
    /// a helper, and helpers keep no temporary.
    transfer_target: u64 = 0,
    /// Set by a helper that has made continuing in translated code wrong:
    /// the run ended, a fault is pending, a thread switched, or a shim asked
    /// for the scheduler. The native chain reads it before every hop.
    chain_break: u32 = 0,
    /// How many entries of `chain_log` are filled.
    chain_depth: u32 = 0,
    /// What the native chain ran, for the glue to account exactly as it
    /// accounts a block it dispatched itself. Without this the per-block
    /// counters, `last_instruction_rip` and the title's code-fetch ledger
    /// would all stop seeing anything that chained.
    chain_log: [chain_log_capacity]ChainLogEntry = @splat(.{}),
};

/// One block the native chain retired.
pub const ChainLogEntry = extern struct {
    block: u64 = 0,
    retired: u32 = 0,
    reserved: u32 = 0,
};

/// Bounds the chain the same way the glue's loop bounds its own, and bounds
/// the log that records it. The two are the same number on purpose: the log
/// cannot overflow because the chain stops first.
pub const chain_log_capacity: usize = 64;

/// The host register holding the hoisted base's host address inside a
/// block. x29 is saved and restored by the prologue and epilogue and read by
/// nothing the translator emits, and every helper preserves it.
const hoist_host: a64.Reg = 29;
/// The widest displacement span one hoist covers: one page. Xenia's PowerPC
/// contexts are page-aligned and about 0xB00 bytes, so every span through
/// rsi - general and vector registers together - is admitted; a base at a
/// random offset with a wide span falls back to the ordinary probe.
const hoist_max_span: u64 = 4096;
const hoist_disp_bias: u64 = 1 << 63;

const HoistCandidate = struct { base: RegId, disp: u64, bytes: u64 };

const ColdAccess = struct {
    full: Label,
    resume_at: Label,
    insn: Insn,
    size: Size,
    index: u32,
    is_write: bool,
    /// A 128-bit access through vector register `vector`, `vector_offset`
    /// bytes past the operand.
    vector: ?a64.Reg = null,
    vector_offset: u32 = 0,
};

/// A plain `[base + disp]` integer memory operand: no index, no segment,
/// no rip-relative or 32-bit address arithmetic. Only these can share one
/// translated page pointer.
fn hoistCandidate(insn: Insn) ?HoistCandidate {
    const d = insn.decoded;
    if (insn.force_fallback or !isNative(d)) return null;
    if (d.is_reg_form or !d.sib_has_base or d.sib_has_index or d.rip_relative or d.has_0x67) return null;
    if (insn.segment == .fs or insn.segment == .gs) return null;
    // A vector operand is read or written as whole 16-byte halves.
    const bytes: u64 = if (isVectorNative(d)) (if (d.vector_256) 32 else 16) else @max(bits(d.size) / 8, 1);
    return .{ .base = d.sib_base_reg, .disp = d.addr, .bytes = bytes };
}

/// Whether an op can write its memory operand: its first operand is the
/// memory one (`add_mem32_reg32`, `mov_mem64_imm32`, `setcc_mem8`,
/// `inc_mem16`). Conservative - `cmp_mem32_reg32` answers yes - because a
/// yes only asks the hoist for a write admission it may not get.
fn mayStoreMemoryOperand(op: Op) bool {
    const name = @tagName(op);
    const underscore = std.mem.indexOfScalar(u8, name, '_') orelse return false;
    return std.mem.startsWith(u8, name[underscore + 1 ..], "mem");
}

/// `Scratch.flag_kind`. Mirrors `flags.applyAdd`/`applySub`/`applyLogic`.
pub const FlagKind = enum(u8) { none = 0, add = 1, sub = 2, logic = 3 };

/// The software TLB the emitted code consults before calling a memory helper.
/// Direct-mapped on the guest page number; a tag of `invalid_tag` is empty.
/// `delta` is host address minus guest address for the page, so the emitted
/// code forms the host pointer with one add. Reads and writes have separate
/// tables because a page may be readable but watched for writes (Xenia's
/// physical-heap access callbacks) or hold code (writes must bump the
/// decode generation, reads need not).
pub const Tlb = extern struct {
    /// 2026-09-20: 787 million fills against 824 million lookups - almost
    /// every miss was a capacity miss, on a direct-mapped table of 1024
    /// entries against a working set of hundreds of megabytes. Eight times
    /// the entries costs 256 KiB of state and nothing on the probe, which
    /// masks with `entries - 1` either way.
    pub const entries: usize = 8192;
    /// A range wider than this is flushed rather than walked. Without it a
    /// larger table turns every wide protection change - and Xenia's write
    /// watch makes those constantly - into thousands of iterations.
    pub const invalidate_scan_limit: usize = 1024;
    pub const page_shift: u6 = 12;
    pub const page_bytes: u64 = 1 << page_shift;
    pub const invalid_tag: u64 = std.math.maxInt(u64);

    /// Bits of the page number folded into the index. Direct-mapping on the
    /// low bits alone made every page 32 MiB apart share an entry, and
    /// Xenia's layout is built of exactly such strides: its physical views
    /// at 0xA0000000, 0xC0000000 and 0xE0000000 are one set of pages seen
    /// 512 MiB apart, and its heaps begin on 32 MiB boundaries. On
    /// 2026-09-21 the table took 815 million fills in a 514 s run.
    pub const fold_shift: u6 = 13;

    /// The entry a page number lives in: the emitted probe computes the same
    /// thing as one `eor` with a shifted operand and one `and`.
    pub fn index(tag: u64) usize {
        return @intCast((tag ^ (tag >> fold_shift)) & (entries - 1));
    }

    pub const Entry = extern struct {
        tag: u64 = invalid_tag,
        delta: u64 = 0,
    };

    read: [entries]Entry,
    write: [entries]Entry,

    pub const empty: Tlb = .{
        .read = [_]Entry{.{}} ** entries,
        .write = [_]Entry{.{}} ** entries,
    };

    pub fn flush(self: *Tlb, reads: bool, writes: bool) void {
        if (reads) @memset(&self.read, .{});
        if (writes) @memset(&self.write, .{});
    }

    /// Admit `page` (page-aligned guest address) backed by `host`.
    pub fn fill(self: *Tlb, is_write: bool, page: u64, host: [*]u8) void {
        const tag = page >> page_shift;
        const table = if (is_write) &self.write else &self.read;
        table[index(tag)] = .{ .tag = tag, .delta = @intFromPtr(host) -% page };
    }

    /// Drop every entry covering `[base, base + length)`.
    pub fn invalidateRange(self: *Tlb, base: u64, length: u64) void {
        if (length == 0) return;
        const first = base >> page_shift;
        const last = (base +| (length - 1)) >> page_shift;
        if (last - first + 1 >= @min(entries, invalidate_scan_limit)) {
            self.flush(true, true);
            return;
        }
        var tag = first;
        while (true) : (tag += 1) {
            const slot = index(tag);
            if (self.read[slot].tag == tag) self.read[slot] = .{};
            if (self.write[slot].tag == tag) self.write[slot] = .{};
            if (tag == last) break;
        }
    }

    pub fn lookup(self: *const Tlb, is_write: bool, address: u64) ?[*]u8 {
        const tag = address >> page_shift;
        const table = if (is_write) &self.write else &self.read;
        const entry = table[index(tag)];
        if (entry.tag != tag) return null;
        return @ptrFromInt(address +% entry.delta);
    }
};

const tlb_write_offset: u32 = @offsetOf(Tlb, "write");

/// Where the emitted code finds the state it works on.
pub const Layout = struct {
    /// Byte offset of the `Regs` register file inside the state.
    regs_offset: u32,
    /// Byte offset of the `Scratch` record inside the state.
    scratch_offset: u32,
    /// Byte offset of the `Tlb` inside the state.
    tlb_offset: u32,
    /// Byte offsets of the `[32][16]u8` xmm and ymm-upper register files
    /// and the `[32][32]u8` zmm-upper file, each addressed from the state.
    xmm_offset: u32,
    ymm_hi_offset: u32,
    zmm_hi_offset: u32,
    /// Byte offset of the `bool` that turns the ABI call-stack trace on.
    /// The interpreter's `call` and `ret` arms feed that trace, so a native
    /// transfer template reads this and leaves the instruction to the
    /// interpreter whenever it is set. Read at run time rather than decided
    /// at compile time: a block outlives the moment it was translated in.
    trace_calls_offset: u32,
    /// Byte offset of the `u32` count of armed guest return captures. A
    /// `ret` that completes one carries a whole evidence path (the UI font
    /// atlas and scissor captures), and only the interpreter has it.
    return_captures_offset: u32,
    /// Byte offset of a `bool` that is set while any trace the `call` arm
    /// emits from is on (the Windows callback trace and the thread trace).
    /// The glue keeps it, because those are two fields and this is a hot
    /// path; one load answers both.
    trace_transfers_offset: u32,
    /// Byte offsets of the `u64` bounds of the guest image. Every hook an
    /// interpreter `call`/`jmp` arm keys on its target is an address inside
    /// the image (Xenia's kernel-export entries, milestones, accelerators,
    /// winpthreads), so an indirect transfer whose target lands outside it -
    /// Xenia's generated PowerPC code - only pushes and jumps.
    image_low_offset: u32,
    image_high_offset: u32,
    /// Byte offsets of the `u64` bounds of the import address table, the
    /// only memory an indirect call's operand may not come from natively
    /// (the dynamic-function shim keys on those slots). Zero bounds mean
    /// unknown, and the image range stands in.
    iat_low_offset: u32,
    iat_high_offset: u32,
    /// Byte offset of the `[hook_filter_bytes]u8` bloom filter of hooked
    /// image addresses, and of the `u8` switch that, while nonzero, sends
    /// every image target to the interpreter regardless of the filter.
    hook_filter_offset: u32,
    image_targets_hooked_offset: u32,
};

/// The hooked-target bloom filter: 2^17 bits. Against the ~750 addresses a
/// Xenia image hooks, about one image target in 170 is a false positive,
/// and a false positive only costs the interpreter's arm.
pub const hook_filter_bytes: usize = 1 << 14;
const hook_filter_shift: u6 = 64 - 17;
const hook_filter_multiplier: u64 = 0x9E37_79B9_7F4A_7C15;

pub fn hookFilterBit(address: u64) u32 {
    return @truncate((address *% hook_filter_multiplier) >> hook_filter_shift);
}

pub fn hookFilterAdd(filter: *[hook_filter_bytes]u8, address: u64) void {
    const bit = hookFilterBit(address);
    filter[bit >> 3] |= @as(u8, 1) << @intCast(bit & 7);
}

pub fn hookFilterHas(filter: *const [hook_filter_bytes]u8, address: u64) bool {
    const bit = hookFilterBit(address);
    return (filter[bit >> 3] >> @intCast(bit & 7)) & 1 != 0;
}

const scratch_abort_offset: u32 = @offsetOf(Scratch, "abort");
const scratch_transfer_target_offset: u32 = @offsetOf(Scratch, "transfer_target");
const scratch_index_offset: u32 = @offsetOf(Scratch, "index");
const scratch_vector_offset: u32 = @offsetOf(Scratch, "vector");
const scratch_flag_kind_offset: u32 = @offsetOf(Scratch, "flag_kind");
const scratch_flag_size_offset: u32 = @offsetOf(Scratch, "flag_size");
const scratch_flag_a_offset: u32 = @offsetOf(Scratch, "flag_a");
const scratch_flag_b_offset: u32 = @offsetOf(Scratch, "flag_b");
const scratch_flag_r_offset: u32 = @offsetOf(Scratch, "flag_r");
const scratch_chain_break_offset: u32 = @offsetOf(Scratch, "chain_break");
const scratch_chain_depth_offset: u32 = @offsetOf(Scratch, "chain_depth");
const scratch_chain_log_offset: u32 = @offsetOf(Scratch, "chain_log");
const scratch_block_offset: u32 = @offsetOf(Scratch, "block");

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
    /// No memory access, no fallback and no vector state: the block can be
    /// cross-checked against the interpreter by running both on the general
    /// register file.
    register_only: bool,
    /// Source identity, owned by the glue. Mirrors the decode cache entry.
    source_mapped: bool = false,
    source_kind: u8 = 0,
    source_index: usize = 0,
    source_generation: ?u64 = null,
    executions: u64 = 0,
    instructions_retired: u64 = 0,
    verified: bool = false,
    /// Byte offset from `code.ptr` of the entry that skips the prologue.
    /// A chained block arrives with the frame already established and every
    /// cached pointer but `helpers` already correct, so it must not run the
    /// prologue again - that would push a frame per hop and never pop it.
    chain_entry: u32 = 0,
    /// The live generation word for this block's source. Both arrays it can
    /// point into are fixed members of the state, so the pointer is stable
    /// for the life of the run; that is what lets the native chain validate
    /// a successor without calling back into the glue.
    generation_ptr: ?*const u64 = null,
    /// The last `link_ways` distinct successors this block went to, each
    /// with everything needed to prove it is still where it should be. One
    /// link was not enough: a block ending in a branch alternates between
    /// its two successors and a `ret` returns to every caller, and on
    /// 2026-09-21 64% of chain exits were a successor the single link did
    /// not name - native chains averaged 4.6 blocks.
    links: [link_ways]Link = @splat(.{}),
    /// The way the next new successor replaces: round robin.
    link_victim: u8 = 0,

    pub fn entry(self: *const Block) BlockFn {
        return @ptrCast(self.code.ptr);
    }
};

/// Ways in a block's successor cache.
pub const link_ways: usize = 4;

/// One successor a block chained to: its guest address, its entry past the
/// prologue, its helper table, the table slot it lives in with the pointer
/// that slot must still hold, and its source generation.
pub const Link = extern struct {
    rip: u64 = 0,
    entry: usize = 0,
    helpers: usize = 0,
    slot: usize = 0,
    block: usize = 0,
    gen_ptr: usize = 0,
    generation: u64 = 0,
};

pub const Compiled = struct {
    code: []const u32,
    /// Byte offset of the entry that skips the prologue.
    chain_entry: u32,
    native_count: u32,
    fallback_count: u32,
    register_only: bool,
    /// Instructions whose flag computation the liveness pass removed.
    flags_elided: u32,
    /// Flag writers whose emission was narrowed to a subset of the six.
    flags_narrowed: u32,
    /// Guest registers held in host registers for this block.
    cached_registers: u8 = 0,
    /// Memory accesses served through a hoisted base pointer.
    hoisted_accesses: u32 = 0,
};

// ---------------------------------------------------------------------------
// The compiled subset
// ---------------------------------------------------------------------------

/// Whether a template exists for the instruction as decoded. Not every form
/// of an op is compiled (a 16-bit shift is not), so this is a function of the
/// whole decode, not of the op alone.
pub fn isNative(d: DecodedInsn) bool {
    if (d.is_evex) return false;
    // A `lock` prefix is honoured only by the atomic templates, which make
    // it a real host atomic; every other locked form stays interpreted.
    if (d.lock and atomicForm(d.op) == null) return false;
    if (isVectorNative(d)) return true;
    const wide = d.size == .bits32 or d.size == .bits64;
    return switch (d.op) {
        .nop => d.len != 2,
        // The 32-bit ops also carry 66-prefixed 16-bit operands, and a word
        // atomic has no single LSE instruction: a 32-bit SWPAL/LDADDAL on a
        // 16-bit field writes the next two bytes too (an XADD carries into
        // them). Those stay with the interpreter.
        .xchg_mem32_reg32, .xchg_mem64_reg64, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64, .xadd_mem32_reg32, .xadd_mem64_reg64 => wide and !d.is_reg_form and memoryOperandSupported(d),
        .mov_reg8_reg8, .mov_reg16_reg16, .mov_reg32_reg32, .mov_reg64_reg64 => true,
        .mov_reg_imm => true,
        .mov_reg8_mem8, .mov_reg16_mem16, .mov_reg32_mem32, .mov_reg64_mem64 => memoryOperandSupported(d),
        .mov_mem8_reg8, .mov_mem16_reg16, .mov_mem32_reg32, .mov_mem64_reg64 => memoryOperandSupported(d),
        .mov_mem8_imm8, .mov_mem16_imm16, .mov_mem32_imm32, .mov_mem64_imm32 => memoryOperandSupported(d),
        .movbe_reg_mem, .movbe_mem_reg => d.size != .bits8 and memoryOperandSupported(d),
        // 10.6 million `ldmxcsr` fallbacks on 2026-09-21: Xenia's JIT loads
        // MXCSR around every PPC FPSCR change. Nothing native reads the
        // field, so the interpreter's whole effect is the 32-bit store.
        .ldmxcsr_mem32, .stmxcsr_mem32 => !d.is_reg_form and memoryOperandSupported(d),
        .movzx_reg32_mem8, .movzx_reg32_mem16, .movsx_reg32_mem8, .movsx_reg32_mem16 => d.is_reg_form or memoryOperandSupported(d),
        .movsxd_reg64_reg32 => true,
        .movsxd_reg64_mem32 => memoryOperandSupported(d),
        .lea_reg_mem => memoryOperandSupported(d) and d.size != .bits8,
        .xchg_reg32_reg32, .xchg_reg64_reg64 => d.is_reg_form,
        .xchg_accum_reg => true,
        // Group 1 arithmetic and logic: register, immediate and memory forms.
        else => blk: {
            if (binaryOpOf(d.op)) |_| {
                break :blk !binaryTouchesMemory(d.op) or memoryOperandSupported(d);
            }
            break :blk switch (d.op) {
                .inc_reg8, .inc_reg16, .inc_reg32, .inc_reg64 => true,
                .dec_reg8, .dec_reg16, .dec_reg32, .dec_reg64 => true,
                .inc_mem8, .inc_mem16, .inc_mem32, .inc_mem64 => memoryOperandSupported(d),
                .dec_mem8, .dec_mem16, .dec_mem32, .dec_mem64 => memoryOperandSupported(d),
                .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => true,
                .not_reg8, .not_reg16, .not_reg32, .not_reg64 => true,
                .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => memoryOperandSupported(d),
                .not_mem8, .not_mem16, .not_mem32, .not_mem64 => memoryOperandSupported(d),
                // 8- and 16-bit shifts are native while the count stays
                // inside the operand: past it x86 leaves CF to the
                // interpreter's reading of an undefined bit. 35 million
                // narrow `shr` fallbacks on 2026-09-21.
                .shl_reg_imm, .shr_reg_imm, .sar_reg_imm => wide or shiftCount(d) < bits(d.size),
                .shl_reg_cl, .shr_reg_cl, .sar_reg_cl => wide,
                // Narrow immediate rotates too: `rol r16, 8` is how compilers
                // spell a 16-bit byte swap, 31 million fallbacks on 2026-09-21.
                .rol_reg_imm, .ror_reg_imm => true,
                .rol_reg_cl, .ror_reg_cl => wide,
                .imul_reg64_reg64, .imul_reg32_reg32 => true,
                .imul_reg64_mem64, .imul_reg32_mem32 => memoryOperandSupported(d),
                .imul_reg32_reg32_imm8, .imul_reg32_reg32_imm32, .imul_reg64_reg64_imm8, .imul_reg64_reg64_imm32 => d.is_reg_form,
                .imul_reg32_mem32_imm8, .imul_reg32_mem32_imm32, .imul_reg64_mem64_imm8, .imul_reg64_mem64_imm32 => !d.is_reg_form and memoryOperandSupported(d),
                .mul_reg32, .mul_reg64, .imul_reg32, .imul_reg64 => true,
                .div_reg32, .div_reg64, .idiv_reg32, .idiv_reg64 => true,
                .bt_reg_reg, .bts_reg_reg, .btr_reg_reg, .bt_reg_imm, .bts_reg_imm, .btr_reg_imm => d.size != .bits8,
                // The immediate form never moves the address, so it is a
                // plain read, a bit, and a write. `btr [mem], imm` was the
                // largest fallback on 2026-09-21: 62 million calls.
                .bt_mem_imm, .bts_mem_imm, .btr_mem_imm => d.size != .bits8 and memoryOperandSupported(d),
                .bsf_reg_reg, .bsr_reg_reg => d.size != .bits8,
                .tzcnt_reg_reg, .lzcnt_reg_reg => wide,
                .cmovcc_reg_reg => wide,
                .cmovcc_reg_mem => wide and memoryOperandSupported(d),
                .setcc_reg8 => true,
                // `setcc [mem]` was 78% of every interpreter fallback the
                // 2026-09-19 Halo 3 run made: 5.8 billion of 7.4 billion calls.
                // Xenia's PowerPC backend writes each condition-register bit
                // with one of these, so a title's every compare reaches it.
                .setcc_mem8 => !d.is_reg_form and memoryOperandSupported(d),
                // A fence is a `dmb ish` here; it needs no interpreter step.
                .mfence, .lfence, .sfence => true,
                .push_reg, .push_imm, .pop_reg => true,
                .cdqe, .cdq, .cqo => true,
                .bswap_reg => wide,
                .jcc_rel8, .jcc_rel32, .jmp_rel8 => true,
                // 2026-09-20: 2,162,247,062 interpreter fallbacks, 39% of
                // every one the Halo 3 run made, and the single largest
                // entry in FALLBACK OPS. A plain `ret` is a pop into RIP;
                // everything else its interpreter arm does is guarded by
                // state this template reads for itself. `ret imm16` (0xC2)
                // also decodes to this op and the interpreter's arm ignores
                // the pop count, so it stays where it is rather than having
                // that behaviour reproduced here.
                .ret => d.imm == 0,
                // 1,689,686,672 fallbacks, 31%, second only to `ret`. The
                // glue decides per call site whether the interpreter's arm
                // has a hook for this target and forces the fallback when it
                // does, so reaching here means the arm would only push and
                // jump - see `blockJitCallTargetPlain`.
                .call_rel32 => true,
                // 2026-09-21: 84, 89 and 44 million fallbacks. A target
                // outside the image carries no hook, so the template only
                // pushes and jumps there and hands everything else to the
                // interpreter at run time. An operand the push could move
                // (rsp) or a rip-relative slot (an import table entry, which
                // the dynamic-function shim keys on) stays interpreted.
                .jmp_reg64 => true,
                .call_reg64 => d.dst_reg != .ah_sp_esp_rsp,
                .call_mem64 => memoryOperandSupported(d) and !d.rip_relative and
                    !(d.sib_has_base and d.sib_base_reg == .ah_sp_esp_rsp) and
                    !(d.sib_has_index and d.sib_index_reg == .ah_sp_esp_rsp),
                else => false,
            };
        },
    };
}

/// A relative branch: compiled as the block's last instruction.
pub fn isTerminator(op: Op) bool {
    return switch (op) {
        .jcc_rel8, .jcc_rel32, .jmp_rel8 => true,
        else => false,
    };
}

/// A branch with two successors, one of which is the next instruction.
///
/// A block does not have to stop at one. Its taken edge leaves through an
/// exit stub and its not-taken edge is simply the next byte, so a block that
/// continues across it stays a single contiguous byte range - which is what
/// revalidation, the source generation and `block.bytes` all assume. Doing
/// so is the cheapest way to raise `mean_block_len`, and every per-block
/// cost - the indirect call into the block, the hash probe that found it,
/// the prologue and the epilogue - is paid once per block rather than once
/// per basic block.
pub fn isConditionalBranch(op: Op) bool {
    return switch (op) {
        .jcc_rel8, .jcc_rel32 => true,
        else => false,
    };
}

/// A control transfer the interpreter must perform (its arm carries the
/// milestone, kernel-call, accelerator and shim hooks). It is compiled as a
/// fallback and ends the block: the block returns to `step` at the target.
/// Before 2026-09-19 these ended a block *before* themselves, which cost a
/// full `step` (hook gates, hotness probe, decode-cache probe, dispatch) per
/// call and return, and made every call and return address a candidate block
/// start that was refused, thrashing the hotness table.
pub fn isFallbackTerminator(op: Op) bool {
    return switch (op) {
        .call_rel32, .call_mem64, .call_reg64, .ret, .jmp_mem64, .jmp_reg64 => true,
        .loop, .loope, .loopne, .jrcxz => true,
        else => false,
    };
}

/// Instructions the interpreter must run at a step boundary of its own, so a
/// block ends before them: everything that reaches the host or the scheduler.
pub fn endsBlockBefore(d: DecodedInsn) bool {
    return switch (d.op) {
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
const r_tlb: a64.Reg = 23;
const r_spare: a64.Reg = 24;
/// Host registers that hold guest registers for the length of a block.
///
/// Callee-saved, so they survive the memory helpers - which are C calls -
/// without a spill; that is what makes caching pay. Only the interpreter
/// reads and writes the guest register file directly, so only around its
/// call, and on the way out of the block, does the cache have to agree with
/// memory.
const cache_host_regs = [_]a64.Reg{ 25, 26, 27, 28 };
/// A guest register is cached only if the block touches it at least this
/// often: caching costs a load in and a store out, so fewer uses than this
/// cannot come out ahead.
const cache_min_uses: u32 = 3;
const t0: a64.Reg = 9;
const t1: a64.Reg = 10;
const t2: a64.Reg = 11;
const t3: a64.Reg = 12;
const t4: a64.Reg = 13;
const t5: a64.Reg = 14;
const t6: a64.Reg = 15;

const rip_offset: u32 = @offsetOf(Regs, "rip");
const rflags_offset: u32 = @offsetOf(Regs, "rflags");
const mxcsr_offset: u32 = @offsetOf(Regs, "mxcsr");
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

fn memSize(size: Size) a64.MemSize {
    return switch (size) {
        .bits8 => .byte,
        .bits16 => .half,
        .bits32 => .word,
        .bits64 => .doubleword,
    };
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

/// Whether an arithmetic writer records its operands and leaves the flags no
/// later instruction in its block reads to be derived on the way out.
///
/// Measured on 2026-09-20 and turned off. Deferring cut `add` from 32 ARM
/// words to 11 and bought nothing: 16.4 billion completions, about two per
/// block execution, cost roughly what the smaller code saved (216.0M
/// instructions/s against 218.0M without it). Native chaining then made it
/// actively worse - a chain hop does not pass the completion, so a record
/// has to be settled at whichever successor first reads a flag it owns, and
/// those settles are calls in the middle of hot blocks.
///
/// The version worth having is one where the record crosses a block boundary
/// and is only ever materialised by something that truly reads a flag, which
/// means teaching the interpreter to read the record rather than `rflags`.
/// Until then the eager path is both faster and simpler, and everything the
/// deferred path needs is still here behind this.
const defer_flags = false;
const BinaryOp = enum { add, sub, bit_and, bit_or, bit_xor, cmp, tst, adc, sbb };

/// Where a Group-1 instruction's operands live.
const BinaryShape = enum {
    /// dst register, src register.
    reg_reg,
    /// dst register, immediate.
    reg_imm,
    /// dst register, src memory (`add reg, [mem]`).
    reg_mem,
    /// dst memory, src register (`add [mem], reg`).
    mem_reg,
    /// dst memory, immediate.
    mem_imm,
};

fn binaryOpOf(op: Op) ?BinaryOp {
    return switch (op) {
        .add_reg8_reg8, .add_reg16_reg16, .add_reg32_reg32, .add_reg64_reg64, .add_reg8_imm8, .add_reg16_imm8, .add_reg32_imm8, .add_reg64_imm8, .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32, .add_accum_imm => .add,
        .add_reg8_mem8, .add_reg16_mem16, .add_reg32_mem32, .add_reg64_mem64, .add_mem8_reg8, .add_mem16_reg16, .add_mem32_reg32, .add_mem64_reg64, .add_mem8_imm8, .add_mem16_imm8, .add_mem32_imm8, .add_mem64_imm8, .add_mem16_imm32, .add_mem32_imm32, .add_mem64_imm32 => .add,
        .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64, .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8, .sub_reg16_imm32, .sub_reg32_imm32, .sub_reg64_imm32, .sub_accum_imm => .sub,
        .sub_reg8_mem8, .sub_reg16_mem16, .sub_reg32_mem32, .sub_reg64_mem64, .sub_mem8_reg8, .sub_mem16_reg16, .sub_mem32_reg32, .sub_mem64_reg64, .sub_mem8_imm8, .sub_mem16_imm8, .sub_mem32_imm8, .sub_mem64_imm8, .sub_mem16_imm32, .sub_mem32_imm32, .sub_mem64_imm32 => .sub,
        .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64, .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8, .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32, .and_accum_imm => .bit_and,
        .and_reg8_mem8, .and_reg16_mem16, .and_reg32_mem32, .and_reg64_mem64, .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64, .and_mem8_imm8, .and_mem16_imm8, .and_mem32_imm8, .and_mem64_imm8, .and_mem16_imm32, .and_mem32_imm32, .and_mem64_imm32 => .bit_and,
        .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64, .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8, .or_reg16_imm32, .or_reg32_imm32, .or_reg64_imm32, .or_accum_imm => .bit_or,
        .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64, .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64, .or_mem8_imm8, .or_mem16_imm8, .or_mem32_imm8, .or_mem64_imm8, .or_mem16_imm32, .or_mem32_imm32, .or_mem64_imm32 => .bit_or,
        .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64, .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8, .xor_reg16_imm32, .xor_reg32_imm32, .xor_reg64_imm32, .xor_accum_imm => .bit_xor,
        .xor_reg8_mem8, .xor_reg16_mem16, .xor_reg32_mem32, .xor_reg64_mem64, .xor_mem8_reg8, .xor_mem16_reg16, .xor_mem32_reg32, .xor_mem64_reg64, .xor_mem8_imm8, .xor_mem16_imm8, .xor_mem32_imm8, .xor_mem64_imm8, .xor_mem16_imm32, .xor_mem32_imm32, .xor_mem64_imm32 => .bit_xor,
        .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64, .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8, .cmp_reg16_imm32, .cmp_reg32_imm32, .cmp_reg64_imm32, .cmp_accum_imm => .cmp,
        .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64, .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64, .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8, .cmp_mem16_imm32, .cmp_mem32_imm32, .cmp_mem64_imm32 => .cmp,
        .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64, .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => .tst,
        .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64, .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => .tst,
        .adc_reg8_reg8, .adc_reg16_reg16, .adc_reg32_reg32, .adc_reg64_reg64, .adc_reg8_imm8, .adc_reg16_imm8, .adc_reg32_imm8, .adc_reg64_imm8, .adc_reg16_imm32, .adc_reg32_imm32, .adc_reg64_imm32, .adc_accum_imm => .adc,
        .adc_reg8_mem8, .adc_reg16_mem16, .adc_reg32_mem32, .adc_reg64_mem64 => .adc,
        .sbb_reg8_reg8, .sbb_reg16_reg16, .sbb_reg32_reg32, .sbb_reg64_reg64, .sbb_reg8_imm8, .sbb_reg16_imm8, .sbb_reg32_imm8, .sbb_reg64_imm8, .sbb_reg16_imm32, .sbb_reg32_imm32, .sbb_reg64_imm32, .sbb_accum_imm => .sbb,
        .sbb_reg8_mem8, .sbb_reg16_mem16, .sbb_reg32_mem32, .sbb_reg64_mem64 => .sbb,
        else => null,
    };
}

fn binaryShapeOf(op: Op) BinaryShape {
    return switch (op) {
        .add_reg8_mem8, .add_reg16_mem16, .add_reg32_mem32, .add_reg64_mem64, .sub_reg8_mem8, .sub_reg16_mem16, .sub_reg32_mem32, .sub_reg64_mem64, .and_reg8_mem8, .and_reg16_mem16, .and_reg32_mem32, .and_reg64_mem64, .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64, .xor_reg8_mem8, .xor_reg16_mem16, .xor_reg32_mem32, .xor_reg64_mem64, .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64, .adc_reg8_mem8, .adc_reg16_mem16, .adc_reg32_mem32, .adc_reg64_mem64, .sbb_reg8_mem8, .sbb_reg16_mem16, .sbb_reg32_mem32, .sbb_reg64_mem64 => .reg_mem,
        .add_mem8_reg8, .add_mem16_reg16, .add_mem32_reg32, .add_mem64_reg64, .sub_mem8_reg8, .sub_mem16_reg16, .sub_mem32_reg32, .sub_mem64_reg64, .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64, .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64, .xor_mem8_reg8, .xor_mem16_reg16, .xor_mem32_reg32, .xor_mem64_reg64, .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64, .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64 => .mem_reg,
        .add_mem8_imm8, .add_mem16_imm8, .add_mem32_imm8, .add_mem64_imm8, .add_mem16_imm32, .add_mem32_imm32, .add_mem64_imm32, .sub_mem8_imm8, .sub_mem16_imm8, .sub_mem32_imm8, .sub_mem64_imm8, .sub_mem16_imm32, .sub_mem32_imm32, .sub_mem64_imm32, .and_mem8_imm8, .and_mem16_imm8, .and_mem32_imm8, .and_mem64_imm8, .and_mem16_imm32, .and_mem32_imm32, .and_mem64_imm32, .or_mem8_imm8, .or_mem16_imm8, .or_mem32_imm8, .or_mem64_imm8, .or_mem16_imm32, .or_mem32_imm32, .or_mem64_imm32, .xor_mem8_imm8, .xor_mem16_imm8, .xor_mem32_imm8, .xor_mem64_imm8, .xor_mem16_imm32, .xor_mem32_imm32, .xor_mem64_imm32, .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8, .cmp_mem16_imm32, .cmp_mem32_imm32, .cmp_mem64_imm32, .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => .mem_imm,
        else => if (immediateShapeOf(op) == .none) .reg_reg else .reg_imm,
    };
}

fn binaryTouchesMemory(op: Op) bool {
    return switch (binaryShapeOf(op)) {
        .reg_mem, .mem_reg, .mem_imm => true,
        else => false,
    };
}

const ImmediateShape = enum { none, imm8, imm32, test_imm };

fn immediateShapeOf(op: Op) ImmediateShape {
    return switch (op) {
        .add_reg8_imm8, .add_reg16_imm8, .add_reg32_imm8, .add_reg64_imm8, .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8, .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8, .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8, .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8, .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => .imm8,
        .adc_reg8_imm8, .adc_reg16_imm8, .adc_reg32_imm8, .adc_reg64_imm8, .sbb_reg8_imm8, .sbb_reg16_imm8, .sbb_reg32_imm8, .sbb_reg64_imm8 => .imm8,
        .add_mem8_imm8, .add_mem16_imm8, .add_mem32_imm8, .add_mem64_imm8, .sub_mem8_imm8, .sub_mem16_imm8, .sub_mem32_imm8, .sub_mem64_imm8, .and_mem8_imm8, .and_mem16_imm8, .and_mem32_imm8, .and_mem64_imm8, .or_mem8_imm8, .or_mem16_imm8, .or_mem32_imm8, .or_mem64_imm8, .xor_mem8_imm8, .xor_mem16_imm8, .xor_mem32_imm8, .xor_mem64_imm8, .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8 => .imm8,
        .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32, .sub_reg16_imm32, .sub_reg32_imm32, .sub_reg64_imm32, .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32, .or_reg16_imm32, .or_reg32_imm32, .or_reg64_imm32, .xor_reg16_imm32, .xor_reg32_imm32, .xor_reg64_imm32, .cmp_reg16_imm32, .cmp_reg32_imm32, .cmp_reg64_imm32 => .imm32,
        .adc_reg16_imm32, .adc_reg32_imm32, .adc_reg64_imm32, .sbb_reg16_imm32, .sbb_reg32_imm32, .sbb_reg64_imm32 => .imm32,
        .add_mem16_imm32, .add_mem32_imm32, .add_mem64_imm32, .sub_mem16_imm32, .sub_mem32_imm32, .sub_mem64_imm32, .and_mem16_imm32, .and_mem32_imm32, .and_mem64_imm32, .or_mem16_imm32, .or_mem32_imm32, .or_mem64_imm32, .xor_mem16_imm32, .xor_mem32_imm32, .xor_mem64_imm32, .cmp_mem16_imm32, .cmp_mem32_imm32, .cmp_mem64_imm32 => .imm32,
        .add_accum_imm, .sub_accum_imm, .and_accum_imm, .or_accum_imm, .xor_accum_imm, .cmp_accum_imm, .adc_accum_imm, .sbb_accum_imm => .imm32,
        .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => .test_imm,
        .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => .test_imm,
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

fn isIncDec(op: Op) ?struct { inc: bool, mem: bool } {
    return switch (op) {
        .inc_reg8, .inc_reg16, .inc_reg32, .inc_reg64 => .{ .inc = true, .mem = false },
        .dec_reg8, .dec_reg16, .dec_reg32, .dec_reg64 => .{ .inc = false, .mem = false },
        .inc_mem8, .inc_mem16, .inc_mem32, .inc_mem64 => .{ .inc = true, .mem = true },
        .dec_mem8, .dec_mem16, .dec_mem32, .dec_mem64 => .{ .inc = false, .mem = true },
        else => null,
    };
}

fn incDecSize(op: Op) Size {
    return switch (op) {
        .inc_reg8, .dec_reg8, .inc_mem8, .dec_mem8 => .bits8,
        .inc_reg16, .dec_reg16, .inc_mem16, .dec_mem16 => .bits16,
        .inc_reg32, .dec_reg32, .inc_mem32, .dec_mem32 => .bits32,
        else => .bits64,
    };
}

// ---------------------------------------------------------------------------
// Flag liveness
// ---------------------------------------------------------------------------

const F_CF: u8 = 1;
const F_PF: u8 = 2;
const F_AF: u8 = 4;
const F_ZF: u8 = 8;
const F_SF: u8 = 16;
const F_OF: u8 = 32;
const F_ALL: u8 = 63;

/// The `RFL_*` bits of the flags register that a liveness mask keeps. The two
/// sets are separate on purpose: liveness is a dense six-bit set, the flags
/// register is the architectural layout, and a template that confused them
/// would clear the wrong bit.
/// The flags an x86 condition code actually consults.
///
/// Declaring `jcc`/`setcc`/`cmovcc` as reading every flag is correct but
/// keeps every flag live, which defeats per-flag liveness entirely: a `cmp`
/// followed by `jne` would still compute parity, the auxiliary carry and
/// overflow for a branch that reads only the zero flag. The condition's low
/// bit selects the negation, so the four-value group `cond & 0xE` decides
/// what is read.
fn conditionReads(cond: Cond) u8 {
    return switch (@as(Cond, @enumFromInt(@intFromEnum(cond) & 0xE))) {
        .o => F_OF,
        .b => F_CF,
        .e => F_ZF,
        .be => F_CF | F_ZF,
        .s => F_SF,
        .p => F_PF,
        .l => F_SF | F_OF,
        .le => F_SF | F_OF | F_ZF,
        else => F_ALL,
    };
}

fn liveFlagBits(live: u8) u32 {
    var kept: u32 = 0;
    if ((live & F_CF) != 0) kept |= RFL_CF;
    if ((live & F_PF) != 0) kept |= RFL_PF;
    if ((live & F_AF) != 0) kept |= RFL_AF;
    if ((live & F_ZF) != 0) kept |= RFL_ZF;
    if ((live & F_SF) != 0) kept |= RFL_SF;
    if ((live & F_OF) != 0) kept |= RFL_OF;
    return kept;
}

/// What an instruction does to the six arithmetic flags. `writes` is every
/// flag the template may store; `kills` is every flag it *always* overwrites
/// (a `shl cl` may write nothing when the count is zero, so it kills
/// nothing); `reads` is every flag its result depends on.
const FlagEffects = struct {
    reads: u8 = 0,
    writes: u8 = 0,
    kills: u8 = 0,
};

fn shiftCount(d: DecodedInsn) u6 {
    return @intCast(d.imm & (if (d.size == .bits64) @as(u64, 0x3F) else 0x1F));
}

pub fn flagEffects(insn: Insn) FlagEffects {
    const d = insn.decoded;
    if (insn.force_fallback or !isNative(d)) return .{ .reads = F_ALL };
    if (binaryOpOf(d.op)) |op| {
        return switch (op) {
            .add, .sub, .cmp => .{ .writes = F_ALL, .kills = F_ALL },
            .adc, .sbb => .{ .reads = F_CF, .writes = F_ALL, .kills = F_ALL },
            .bit_and, .bit_or, .bit_xor, .tst => .{ .writes = F_ALL & ~F_AF, .kills = F_ALL & ~F_AF },
        };
    }
    if (isIncDec(d.op)) |_| return .{ .writes = F_ALL & ~F_CF, .kills = F_ALL & ~F_CF };
    return switch (d.op) {
        .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64, .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => .{ .writes = F_ALL, .kills = F_ALL },
        .shl_reg_imm, .shr_reg_imm, .sar_reg_imm => blk: {
            const count = shiftCount(d);
            if (count == 0) break :blk .{};
            const written: u8 = F_CF | F_ZF | F_SF | (if (count == 1) F_OF else 0);
            break :blk .{ .writes = written, .kills = written };
        },
        .shl_reg_cl, .shr_reg_cl, .sar_reg_cl => .{ .writes = F_CF | F_ZF | F_SF | F_OF },
        .rol_reg_imm, .ror_reg_imm => blk: {
            const count = @as(u64, shiftCount(d)) % bits(d.size);
            if (count == 0) break :blk .{};
            const written: u8 = F_CF | (if (count == 1) F_OF else 0);
            break :blk .{ .writes = written, .kills = written };
        },
        .rol_reg_cl, .ror_reg_cl => .{ .writes = F_CF | F_OF },
        .imul_reg64_reg64, .imul_reg32_reg32, .imul_reg64_mem64, .imul_reg32_mem32, .imul_reg32_reg32_imm8, .imul_reg32_reg32_imm32, .imul_reg64_reg64_imm8, .imul_reg64_reg64_imm32, .imul_reg32_mem32_imm8, .imul_reg32_mem32_imm32, .imul_reg64_mem64_imm8, .imul_reg64_mem64_imm32 => .{ .writes = F_CF | F_OF, .kills = F_CF | F_OF },
        .bt_reg_reg, .bts_reg_reg, .btr_reg_reg, .bt_reg_imm, .bts_reg_imm, .btr_reg_imm => .{ .writes = F_CF, .kills = F_CF },
        .bt_mem_imm, .bts_mem_imm, .btr_mem_imm => .{ .writes = F_CF, .kills = F_CF },
        .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64, .xadd_mem32_reg32, .xadd_mem64_reg64 => .{ .writes = F_ALL, .kills = F_ALL },
        .bsf_reg_reg, .bsr_reg_reg => .{ .writes = F_ZF, .kills = F_ZF },
        .tzcnt_reg_reg, .lzcnt_reg_reg => .{ .writes = F_ZF | F_CF, .kills = F_ZF | F_CF },
        .cmovcc_reg_reg, .cmovcc_reg_mem, .setcc_reg8, .setcc_mem8, .jcc_rel8, .jcc_rel32 => .{ .reads = conditionReads(d.cond) },
        .vucomiss, .vucomisd => .{ .writes = F_ALL, .kills = F_ALL },
        else => .{},
    };
}

/// For each instruction, whether its flag computation must be emitted:
/// true when some flag it may write is live afterwards. Live-out at the end
/// of the block is every flag, since the next block or the interpreter may
/// read any of them.
pub fn flagWants(insns: []const Insn, wants: []bool) u32 {
    var scratch: [1]u8 = undefined;
    _ = &scratch;
    return flagLiveness(insns, wants, null);
}

/// For each instruction, whether its flag computation must be emitted at all,
/// and - when `live_out` is given - *which* flags are still read afterwards.
///
/// The second answer is what makes the difference. Emitting the flags of one
/// `add` costs about twenty-five instructions: a six-instruction parity fold,
/// four for the auxiliary carry, five for overflow, three each for zero and
/// sign. x86 code almost never reads parity or the auxiliary carry, and a
/// `cmp` before a `jne` reads only the zero flag - so the all-or-nothing gate
/// kept the other twenty on every one of them. Live-out is per flag for the
/// same reason liveness is worth computing at all.
///
/// A flag that is not live is left holding its previous value rather than
/// cleared, which is what "dead" means: nothing reads it before something
/// else writes it. Live-out at the end of the block is every flag, because
/// the next block or the interpreter may read any of them.
pub fn flagLiveness(insns: []const Insn, wants: []bool, live_out: ?[]u8) u32 {
    return flagLivenessFrom(insns, wants, live_out, F_ALL);
}

/// The same pass with the block's own live-out set.
///
/// `F_ALL` is what leaving the block costs when the flags have to be in
/// `rflags` by then. Pass `0` for the set a writer owes when the rest of its
/// flags ride out in the deferred record instead: then only a reader inside
/// this block counts, and a conditional branch is just another reader rather
/// than a demand for all six.
pub fn flagLivenessFrom(insns: []const Insn, wants: []bool, live_out: ?[]u8, initial: u8) u32 {
    var live: u8 = initial;
    var elided: u32 = 0;
    var index = insns.len;
    while (index > 0) {
        index -= 1;
        // A conditional branch's taken edge leaves the block, and whatever
        // runs next may read any flag. Union that in before deciding what
        // this instruction owes: without it, a flag narrowed away because
        // some later instruction in the trace overwrites it would leave
        // through the branch holding a stale value. A caller that passed
        // `0` has said the record carries that, so the branch is only a
        // reader of its own condition.
        if (initial != 0 and isConditionalBranch(insns[index].decoded.op)) live = F_ALL;
        const effects = flagEffects(insns[index]);
        wants[index] = (effects.writes & live) != 0;
        if (live_out) |out| out[index] = live;
        if (effects.writes != 0 and !wants[index]) elided += 1;
        live = (live & ~effects.kills) | effects.reads;
    }
    return elided;
}

// ---------------------------------------------------------------------------
// Vector (SSE/AVX 128-bit) templates
//
// Xenia's x64 backend keeps every PPC VMX and FPU value in an XMM register
// and every guest load or store goes through a byte swap (`vpshufb` with a
// constant mask, or `movbe`), so the title's own code is dominated by the
// VEX.128 forms below. Each template mirrors the interpreter arm it stands
// in for: the same source fields, the same lane rules, and the same
// clearing of the upper register halves (VEX.128 clears the YMM upper half;
// the forms the EVEX executor also serves clear the ZMM upper half too).
// 256-bit, legacy-SSE and EVEX forms stay with the interpreter.
//
// v0 is the result, v1 the first source, v2 the second, v3-v6 temporaries and
// v7 a zero or constant; nothing lives in a vector register across a helper
// call.
// ---------------------------------------------------------------------------

const v0: a64.Reg = 0;
const v1: a64.Reg = 1;
const v2: a64.Reg = 2;
const v3: a64.Reg = 3;
const v4: a64.Reg = 4;
const v5: a64.Reg = 5;
const v6: a64.Reg = 6;
const v7: a64.Reg = 7;

/// The VEX.128 forms the executor routes to the EVEX engine, which clears
/// the ZMM upper half as well as the YMM one (`evex.handles`).
fn evexRouted(op: Op) bool {
    return switch (op) {
        .vpxor, .vpaddd, .vpslld, .vpshufd, .vpshufb, .vpalignr => true,
        .vmovd_xmm_reg32, .vmovd_xmm_mem32 => true,
        .vpackssdw, .vpacksswb, .vpackuswb, .vpackusdw => true,
        .vpabsb, .vpabsw, .vpabsd => true,
        .vpmovsxbw, .vpmovsxbd, .vpmovsxbq, .vpmovsxwd, .vpmovsxwq, .vpmovsxdq => true,
        .vpmovzxbw, .vpmovzxbd, .vpmovzxbq, .vpmovzxwd, .vpmovzxwq, .vpmovzxdq => true,
        .vblendps, .vblendpd => true,
        .vpbroadcastw, .vpbroadcastd, .vpbroadcastq, .vbroadcastss => true,
        .vmovshdup, .vmovsldup, .vmovddup => true,
        else => false,
    };
}

const VectorBinary = enum { add, sub, mul, cmeq, cmgt, smax, smin, umax, umin, sqadd, uqadd, sqsub, uqsub, urhadd };

fn packedIntegerForm(op: Op) ?struct { lanes: a64.Lanes, kind: VectorBinary } {
    return switch (op) {
        .vpaddb => .{ .lanes = .b16, .kind = .add },
        .vpaddw => .{ .lanes = .h8, .kind = .add },
        .vpaddd => .{ .lanes = .s4, .kind = .add },
        .vpaddq => .{ .lanes = .d2, .kind = .add },
        .vpsubb => .{ .lanes = .b16, .kind = .sub },
        .vpsubw => .{ .lanes = .h8, .kind = .sub },
        .vpsubd => .{ .lanes = .s4, .kind = .sub },
        .vpsubq => .{ .lanes = .d2, .kind = .sub },
        .vpmullw => .{ .lanes = .h8, .kind = .mul },
        .vpmulld_38 => .{ .lanes = .s4, .kind = .mul },
        .vpcmpeqb => .{ .lanes = .b16, .kind = .cmeq },
        .vpcmpeqw => .{ .lanes = .h8, .kind = .cmeq },
        .vpcmpeqd => .{ .lanes = .s4, .kind = .cmeq },
        .vpcmpeqq => .{ .lanes = .d2, .kind = .cmeq },
        .vpcmpgtb => .{ .lanes = .b16, .kind = .cmgt },
        .vpcmpgtw => .{ .lanes = .h8, .kind = .cmgt },
        .vpcmpgtd => .{ .lanes = .s4, .kind = .cmgt },
        .vpcmpgtq => .{ .lanes = .d2, .kind = .cmgt },
        .vpminsb => .{ .lanes = .b16, .kind = .smin },
        .vpminsw => .{ .lanes = .h8, .kind = .smin },
        .vpminsd => .{ .lanes = .s4, .kind = .smin },
        .vpmaxsb => .{ .lanes = .b16, .kind = .smax },
        .vpmaxsw => .{ .lanes = .h8, .kind = .smax },
        .vpmaxsd => .{ .lanes = .s4, .kind = .smax },
        .vpminub => .{ .lanes = .b16, .kind = .umin },
        .vpminuw => .{ .lanes = .h8, .kind = .umin },
        .vpminud => .{ .lanes = .s4, .kind = .umin },
        .vpmaxub => .{ .lanes = .b16, .kind = .umax },
        .vpmaxuw => .{ .lanes = .h8, .kind = .umax },
        .vpmaxud => .{ .lanes = .s4, .kind = .umax },
        .vpaddsb => .{ .lanes = .b16, .kind = .sqadd },
        .vpaddsw => .{ .lanes = .h8, .kind = .sqadd },
        .vpsubsb => .{ .lanes = .b16, .kind = .sqsub },
        .vpsubsw => .{ .lanes = .h8, .kind = .sqsub },
        .vpaddusb => .{ .lanes = .b16, .kind = .uqadd },
        .vpaddusw => .{ .lanes = .h8, .kind = .uqadd },
        .vpsubusb => .{ .lanes = .b16, .kind = .uqsub },
        .vpsubusw => .{ .lanes = .h8, .kind = .uqsub },
        .vpavgb => .{ .lanes = .b16, .kind = .urhadd },
        .vpavgw => .{ .lanes = .h8, .kind = .urhadd },
        else => null,
    };
}

const FloatBinary = enum { add, sub, mul, div, min, max };

fn packedFloatForm(op: Op) ?struct { lanes: a64.FpLanes, kind: FloatBinary } {
    return switch (op) {
        .vaddps => .{ .lanes = .s4, .kind = .add },
        .vsubps => .{ .lanes = .s4, .kind = .sub },
        .vmulps => .{ .lanes = .s4, .kind = .mul },
        .vdivps => .{ .lanes = .s4, .kind = .div },
        .vminps => .{ .lanes = .s4, .kind = .min },
        .vmaxps => .{ .lanes = .s4, .kind = .max },
        .vaddpd => .{ .lanes = .d2, .kind = .add },
        .vsubpd => .{ .lanes = .d2, .kind = .sub },
        .vmulpd => .{ .lanes = .d2, .kind = .mul },
        .vdivpd => .{ .lanes = .d2, .kind = .div },
        .vminpd => .{ .lanes = .d2, .kind = .min },
        .vmaxpd => .{ .lanes = .d2, .kind = .max },
        else => null,
    };
}

fn scalarFloatForm(op: Op) ?struct { fp: a64.FpWidth, kind: FloatBinary } {
    return switch (op) {
        .vaddss => .{ .fp = .single, .kind = .add },
        .vsubss => .{ .fp = .single, .kind = .sub },
        .vmulss => .{ .fp = .single, .kind = .mul },
        .vdivss => .{ .fp = .single, .kind = .div },
        .vminss => .{ .fp = .single, .kind = .min },
        .vmaxss => .{ .fp = .single, .kind = .max },
        .vaddsd => .{ .fp = .double, .kind = .add },
        .vsubsd => .{ .fp = .double, .kind = .sub },
        .vmulsd => .{ .fp = .double, .kind = .mul },
        .vdivsd => .{ .fp = .double, .kind = .div },
        .vminsd => .{ .fp = .double, .kind = .min },
        .vmaxsd => .{ .fp = .double, .kind = .max },
        else => null,
    };
}

const VectorBitwise = enum { and_, andn, or_, xor };

fn bitwiseForm(op: Op) ?VectorBitwise {
    return switch (op) {
        .vandps, .vandpd, .vpand => .and_,
        .vandnps, .vandnpd, .vpandn => .andn,
        .vorps, .vorpd, .vpor => .or_,
        .vxorps, .vxorpd, .vpxor => .xor,
        else => null,
    };
}

fn unpackForm(op: Op) ?struct { lanes: a64.Lanes, high: bool } {
    return switch (op) {
        .vpunpcklbw => .{ .lanes = .b16, .high = false },
        .vpunpcklwd => .{ .lanes = .h8, .high = false },
        .vpunpckldq, .vunpcklps => .{ .lanes = .s4, .high = false },
        .vpunpcklqdq, .vunpcklpd => .{ .lanes = .d2, .high = false },
        .vpunpckhbw => .{ .lanes = .b16, .high = true },
        .vpunpckhwd => .{ .lanes = .h8, .high = true },
        .vpunpckhdq, .vunpckhps => .{ .lanes = .s4, .high = true },
        .vpunpckhqdq, .vunpckhpd => .{ .lanes = .d2, .high = true },
        else => null,
    };
}

const ShiftKind = enum { left, right_logical, right_arithmetic, left_bytes, right_bytes };

fn shiftForm(op: Op) ?struct { lanes: a64.Lanes, kind: ShiftKind } {
    return switch (op) {
        .vpsllw => .{ .lanes = .h8, .kind = .left },
        .vpslld => .{ .lanes = .s4, .kind = .left },
        .vpsllq => .{ .lanes = .d2, .kind = .left },
        .vpsrlw => .{ .lanes = .h8, .kind = .right_logical },
        .vpsrld => .{ .lanes = .s4, .kind = .right_logical },
        .vpsrlq => .{ .lanes = .d2, .kind = .right_logical },
        .vpsraw => .{ .lanes = .h8, .kind = .right_arithmetic },
        .vpsrad => .{ .lanes = .s4, .kind = .right_arithmetic },
        .vpslldq => .{ .lanes = .b16, .kind = .left_bytes },
        .vpsrldq => .{ .lanes = .b16, .kind = .right_bytes },
        else => null,
    };
}

/// `vpmovzx*`/`vpmovsx*`: the source lane width and how many doublings.
fn extendForm(op: Op) ?struct { source: a64.Lanes, steps: u8, signed: bool } {
    return switch (op) {
        .vpmovzxbw => .{ .source = .b16, .steps = 1, .signed = false },
        .vpmovzxbd => .{ .source = .b16, .steps = 2, .signed = false },
        .vpmovzxbq => .{ .source = .b16, .steps = 3, .signed = false },
        .vpmovzxwd => .{ .source = .h8, .steps = 1, .signed = false },
        .vpmovzxwq => .{ .source = .h8, .steps = 2, .signed = false },
        .vpmovzxdq => .{ .source = .s4, .steps = 1, .signed = false },
        .vpmovsxbw => .{ .source = .b16, .steps = 1, .signed = true },
        .vpmovsxbd => .{ .source = .b16, .steps = 2, .signed = true },
        .vpmovsxbq => .{ .source = .b16, .steps = 3, .signed = true },
        .vpmovsxwd => .{ .source = .h8, .steps = 1, .signed = true },
        .vpmovsxwq => .{ .source = .h8, .steps = 2, .signed = true },
        .vpmovsxdq => .{ .source = .s4, .steps = 1, .signed = true },
        else => null,
    };
}

/// The x86 vector forms with a template. 128-bit VEX only: the 256-bit,
/// legacy-SSE and EVEX encodings keep their interpreter arms.
/// The 256-bit forms this translator serves: plain moves, done as two
/// 128-bit halves through the same register file and memory helpers the
/// 128-bit templates use. Everything else at 256 bits stays with the
/// interpreter. `vmovdqa_mem_ymm` alone was 99 million fallback calls on
/// 2026-09-20.
fn ymmMoveForm(op: Op) ?enum { load, store, register } {
    return switch (op) {
        .vmovdqu_ymm_mem, .vmovdqa_ymm_mem, .vmovups_ymm_mem, .vmovaps_ymm_mem, .vmovupd_ymm_mem, .vmovapd_ymm_mem => .load,
        // A non-temporal store is a store; the hint only concerns a cache
        // this translator does not model. Xenia's `vastcpy_impl_avx` streams
        // with it: 48 million fallback calls on 2026-09-21.
        .vmovdqu_mem_ymm, .vmovdqa_mem_ymm, .vmovups_mem_ymm, .vmovaps_mem_ymm, .vmovupd_mem_ymm, .vmovapd_mem_ymm, .vmovntps, .vmovntdq => .store,
        .vmovdqu_ymm_ymm, .vmovdqa_ymm_ymm, .vmovups_ymm_ymm, .vmovaps_ymm_ymm, .vmovupd_ymm_ymm, .vmovapd_ymm_ymm => .register,
        else => null,
    };
}

/// The memory read-modify-writes compiled as single LSE atomics. `xchg` with
/// memory is locked whether or not it carries the prefix, and `cmpxchg` /
/// `xadd` are the spinlock and counter primitives, so these three are the
/// ones a second host thread would first need to be real atomics. The
/// acquire-release forms are sequentially consistent, which is at least as
/// strong as x86's TSO for a locked operation.
const AtomicForm = enum { exchange, compare_exchange, exchange_add };

fn atomicForm(op: Op) ?AtomicForm {
    return switch (op) {
        .xchg_mem32_reg32, .xchg_mem64_reg64 => .exchange,
        .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64 => .compare_exchange,
        .xadd_mem32_reg32, .xadd_mem64_reg64 => .exchange_add,
        else => null,
    };
}

pub fn isVectorNative(d: DecodedInsn) bool {
    if (d.is_evex or d.legacy_sse or d.vector_512 or d.opmask != 0 or d.evex_broadcast) return false;
    if (d.vector_256) {
        // 2026-09-21: 6.5 million `vcvtps2pd ymm, xmm/m128` fallbacks.
        if (d.op == .vcvtps2pd) return d.is_reg_form or memoryOperandSupported(d);
        const form = ymmMoveForm(d.op) orelse return false;
        return if (form == .register) d.is_reg_form else memoryOperandSupported(d);
    }
    if (packedIntegerForm(d.op) != null or packedFloatForm(d.op) != null or scalarFloatForm(d.op) != null) return memoryOperandSupported(d);
    if (bitwiseForm(d.op) != null or unpackForm(d.op) != null or shiftForm(d.op) != null or extendForm(d.op) != null) return memoryOperandSupported(d);
    return switch (d.op) {
        .vmovdqu_xmm_xmm, .vmovdqa_xmm_xmm, .vmovups_xmm_xmm, .vmovaps_xmm_xmm, .vmovupd_xmm_xmm, .vmovapd_xmm_xmm => true,
        .vmovdqu_xmm_mem, .vmovdqa_xmm_mem, .vmovups_xmm_mem, .vmovaps_xmm_mem, .vmovupd_xmm_mem, .vmovapd_xmm_mem => memoryOperandSupported(d),
        .vmovdqu_mem_xmm, .vmovdqa_mem_xmm, .vmovups_mem_xmm, .vmovaps_mem_xmm, .vmovupd_mem_xmm, .vmovapd_mem_xmm => memoryOperandSupported(d),
        .vmovntps, .vmovntdq => !d.is_reg_form and memoryOperandSupported(d),
        .vmovd_xmm_reg32, .vmovq_xmm_reg64, .vmovd_reg32_xmm, .vmovq_reg64_xmm, .vmovq_xmm_xmm => true,
        .vmovd_xmm_mem32, .vmovq_xmm_mem64, .vmovd_mem32_xmm, .vmovq_mem64_xmm => memoryOperandSupported(d),
        .vmovss_xmm_mem, .vmovsd_xmm_mem, .vmovss_mem_xmm, .vmovsd_mem_xmm => memoryOperandSupported(d),
        .vmovss_xmm_xmm_xmm, .vmovsd_xmm_xmm_xmm => true,
        .vmovlps_xmm_xmm_mem64, .vmovlpd_xmm_xmm_mem64, .vmovhps_xmm_xmm_mem64, .vmovhpd_xmm_xmm_mem64 => memoryOperandSupported(d),
        .vmovlps_mem64_xmm, .vmovlpd_mem64_xmm, .vmovhps_mem64_xmm, .vmovhpd_mem64_xmm => memoryOperandSupported(d),
        .vmovhlps, .vmovlhps => d.is_reg_form,
        .vmovddup, .vmovsldup, .vmovshdup => d.is_reg_form or memoryOperandSupported(d),
        .vpshufb, .vpshufd, .vshufps => d.is_reg_form or memoryOperandSupported(d),
        .vpackssdw, .vpacksswb, .vpackuswb, .vpackusdw => d.is_reg_form or memoryOperandSupported(d),
        .vpabsb, .vpabsw, .vpabsd => d.is_reg_form or memoryOperandSupported(d),
        .vpextrb, .vpextrw, .vpextrd, .vpextrq => d.is_reg_form or memoryOperandSupported(d),
        .vpinsrb_xmm_xmm_reg32, .vpinsrw, .vpinsrd, .vpinsrq => d.is_reg_form or memoryOperandSupported(d),
        .vpinsrb_xmm_xmm_mem8 => memoryOperandSupported(d),
        .vpalignr => d.is_reg_form or memoryOperandSupported(d),
        .vblendps, .vblendpd => d.is_reg_form or memoryOperandSupported(d),
        .vblendvps, .vblendvpd, .vpblendvb => d.is_reg_form or memoryOperandSupported(d),
        .vbroadcastss, .vpbroadcastw, .vpbroadcastd, .vpbroadcastq => d.is_reg_form or memoryOperandSupported(d),
        .vsqrtps, .vsqrtpd, .vsqrtss, .vsqrtsd, .vrcpps, .vrsqrtps => d.is_reg_form or memoryOperandSupported(d),
        .vcvtss2sd, .vcvtsd2ss, .vcvtps2pd, .vcvtpd2ps, .vcvtdq2ps, .vcvttps2dq, .vcvtps2dq => d.is_reg_form or memoryOperandSupported(d),
        .vcvtsi2ss_xmm_reg, .vcvtsi2sd_xmm_reg => d.size == .bits32 or d.size == .bits64,
        .vcvtsi2ss_xmm_mem, .vcvtsi2sd_xmm_mem => (d.size == .bits32 or d.size == .bits64) and memoryOperandSupported(d),
        .vcvttss2si, .vcvttsd2si, .vcvtss2si, .vcvtsd2si => (d.size == .bits32 or d.size == .bits64) and (d.is_reg_form or memoryOperandSupported(d)),
        .vucomiss, .vucomisd => d.is_reg_form or memoryOperandSupported(d),
        .vcmpps, .vcmppd => d.is_reg_form or memoryOperandSupported(d),
        .vroundps, .vroundpd, .vroundss, .vroundsd => d.is_reg_form or memoryOperandSupported(d),
        .vzeroupper => true,
        // 2026-09-21 fallbacks: vpmuludq 19.1M, vinsertps 6.3M, vpblendw
        // 6.2M, vshufpd 4.6M - all VEX.128 here, the ymm forms stay
        // interpreted.
        .vpmuludq, .vpblendw, .vshufpd, .vinsertps => d.is_reg_form or memoryOperandSupported(d),
        else => false,
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
    exit_path: Label,
    epilogue_path: Label,
    exits: std.ArrayList(ExitStub),
    /// Full-probe paths of hoisted accesses, emitted after the block body so
    /// the hot path is the pointer test and the access alone.
    cold_accesses: std.ArrayList(ColdAccess) = .empty,
    allocator: std.mem.Allocator,
    /// Per instruction: whether its flag computation must be emitted.
    flag_wants: []const bool,
    flag_live: []const u8,
    /// Per instruction, the flags a later instruction *in this block* reads.
    /// What a deferrable writer owes eagerly; the record carries the rest.
    flag_live_block: []const u8,
    native_count: u32 = 0,
    fallback_count: u32 = 0,
    touches_memory: bool = false,
    /// Reads or writes the vector register files. The glue's register-only
    /// cross-check restores only the general registers between its two
    /// runs, so a block that changes vector state must not be cross-checked
    /// (it would apply its vector effects twice); the differential tests
    /// cover vector templates instead.
    touches_vectors: bool = false,
    /// The instruction being emitted, whether its flags are wanted at all,
    /// and which of them are still read after it.
    current: u32 = 0,
    emit_flags: bool = true,
    emit_flag_mask: u8 = F_ALL,
    flags_narrowed: u32 = 0,
    /// The flags the deferred record would supply at this point in the
    /// emission, or none. Tracked linearly, which is exactly right: a
    /// conditional branch's other edge leaves the block, so the fall-through
    /// order the compiler emits in *is* the order that continues.
    /// In the compact `F_*` space, not the x86 `RFL_*` one: it is compared
    /// against `flagEffects().writes`, and mixing the two layouts silently
    /// mis-answers "does this writer cover the record".
    pending_record: u8 = if (defer_flags) F_ALL else 0,
    /// Per guest register, the index into `cache_host_regs` that holds it for
    /// this block, or null when it lives only in the register file.
    cache_slot: [16]?u8 = @splat(null),
    cache_ids: [cache_host_regs.len]RegId = undefined,
    cache_count: u8 = 0,
    /// Every `loadReg`/`storeReg`, counted by guest register. The first pass
    /// over a block only counts; the second caches what the first found.
    use_counts: [16]u32 = @splat(0),
    flag_settles: u32 = 0,
    /// Base-register hoisting (`planHoist`): the guest register most of the
    /// block's plain `[base+disp]` accesses go through, the lowest
    /// displacement and the span they cover, and whether x29 currently holds
    /// the host address of `base + hoist_dmin` (or zero, when the span was
    /// not admitted as one page). Xenia's JIT addresses every PowerPC
    /// register through the context block in rsi, so almost every guest
    /// instruction it emits is such an access; each used to pay a full TLB
    /// probe, and now pays one per block.
    hoist_base: ?RegId = null,
    hoist_dmin: u64 = 0,
    hoist_span: u64 = 0,
    /// Whether any access through the base can store. A read-only span is
    /// translated through the read TLB: constants and vtables in read-only
    /// data never receive a write admission, and asking for one would make
    /// the hoist fail on every execution of the block.
    hoist_write: bool = false,
    hoist_live: bool = false,
    hoisted_accesses: u32 = 0,

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

    /// Load a small scalar out of the state, whatever its offset.
    ///
    /// `ldr` reaches 4 KiB at byte scale, and the state's transfer-guard
    /// fields sit far past that - the state carries the TLB and the decode
    /// cache. Materialise the address first when the immediate does not fit,
    /// exactly as `emitStateAddress` does for the pointers the prologue
    /// caches. `dst` is the only register touched either way.
    fn emitStateScalar(self: *Compiler, size: a64.MemSize, dst: a64.Reg, offset: u32) Error!void {
        if (a64.ldrImm(size, dst, r_state, offset)) |word| {
            try self.emit(word);
            return;
        }
        try self.emitStateAddress(dst, offset);
        try self.emitChecked(a64.ldrImm(size, dst, dst, 0));
    }

    fn emitPrologue(self: *Compiler) Error!void {
        try self.emitChecked(a64.stp(.pre_index, 29, 30, a64.sp, -96));
        try self.emitChecked(a64.stp(.signed_offset, r_state, r_regs, a64.sp, 16));
        try self.emitChecked(a64.stp(.signed_offset, r_helpers, r_scratch, a64.sp, 32));
        try self.emitChecked(a64.stp(.signed_offset, r_tlb, r_spare, a64.sp, 48));
        // The guest register cache lives in x25-x28, which the caller owns.
        // Saved once per entry from the glue; a chained block arrives past
        // this and reuses the same frame, and the block that finally leaves
        // restores them.
        try self.emitChecked(a64.stp(.signed_offset, cache_host_regs[0], cache_host_regs[1], a64.sp, 64));
        try self.emitChecked(a64.stp(.signed_offset, cache_host_regs[2], cache_host_regs[3], a64.sp, 80));
        try self.emitChecked(a64.addImm(.x64, 29, a64.sp, 0));
        try self.emit(a64.mov(.x64, r_state, 0));
        try self.emit(a64.mov(.x64, r_helpers, 1));
        try self.emitStateAddress(r_regs, self.layout.regs_offset);
        try self.emitStateAddress(r_scratch, self.layout.scratch_offset);
        try self.emitStateAddress(r_tlb, self.layout.tlb_offset);
        try self.emitStateAddress(r_spare, self.layout.xmm_offset);
    }

    fn emitEpilogue(self: *Compiler) Error!void {
        self.a.placeLabel(self.epilogue);
        try self.emitChecked(a64.ldp(.signed_offset, cache_host_regs[2], cache_host_regs[3], a64.sp, 80));
        try self.emitChecked(a64.ldp(.signed_offset, cache_host_regs[0], cache_host_regs[1], a64.sp, 64));
        try self.emitChecked(a64.ldp(.signed_offset, r_tlb, r_spare, a64.sp, 48));
        try self.emitChecked(a64.ldp(.signed_offset, r_helpers, r_scratch, a64.sp, 32));
        try self.emitChecked(a64.ldp(.signed_offset, r_state, r_regs, a64.sp, 16));
        try self.emitChecked(a64.ldp(.post_index, 29, 30, a64.sp, 96));
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
            try self.a.branch(self.exit_path);
        }
    }

    // -- register file --------------------------------------------------------

    /// Load a register operand, zero-extended to the host register, at the
    /// operand's width.
    fn loadReg(self: *Compiler, dst: a64.Reg, id: RegId, high8: bool, size: Size) Error!void {
        const index: usize = @intFromEnum(id);
        self.use_counts[index] +|= 1;
        if (self.cache_slot[index]) |slot| {
            // The same zero-extended value the load would have produced, read
            // from the register that already holds it.
            const host = cache_host_regs[slot];
            switch (size) {
                .bits64 => try self.emit(a64.mov(.x64, dst, host)),
                .bits32 => try self.emit(a64.mov(.w32, dst, host)),
                .bits16 => try self.emit(a64.ubfx(.w32, dst, host, 0, 16)),
                .bits8 => try self.emit(a64.ubfx(.w32, dst, host, if (high8) 8 else 0, 8)),
            }
            return;
        }
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
        const index: usize = @intFromEnum(id);
        self.use_counts[index] +|= 1;
        if (self.hoist_base) |base| {
            if (base == id) self.hoist_live = false;
        }
        if (self.cache_slot[index]) |slot| {
            // x86's width rules, applied to the cached copy instead of memory:
            // 64 and 32 replace the register (32 zero-extends), 16 and 8
            // merge into it.
            const host = cache_host_regs[slot];
            switch (size) {
                .bits64 => try self.emit(a64.mov(.x64, host, src)),
                .bits32 => {
                    // The uncached path zero-extends `src` in place before it
                    // stores; keep that side effect, since a template may
                    // read `src` again afterwards.
                    try self.emit(a64.mov(.w32, src, src));
                    try self.emit(a64.mov(.x64, host, src));
                },
                .bits16 => try self.emit(a64.bfi(.x64, host, src, 0, 16)),
                .bits8 => try self.emit(a64.bfi(.x64, host, src, if (high8) 8 else 0, 8)),
            }
            return;
        }
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

    /// Read every cached guest register out of the register file.
    fn emitCacheLoad(self: *Compiler) Error!void {
        for (self.cache_ids[0..self.cache_count], 0..) |id, slot| {
            try self.emitChecked(a64.ldrImm(.doubleword, cache_host_regs[slot], r_regs, gprOffset(id)));
        }
    }

    /// Write every cached guest register back. Whole registers, clean or
    /// not: a register this block never wrote still holds exactly what
    /// memory does, so writing it is harmless, and tracking which were
    /// written would need a different answer on every path to every exit.
    fn emitCacheWriteBack(self: *Compiler) Error!void {
        for (self.cache_ids[0..self.cache_count], 0..) |id, slot| {
            try self.emitChecked(a64.strImm(.doubleword, cache_host_regs[slot], r_regs, gprOffset(id)));
        }
    }

    /// Choose which guest registers to cache from a counting pass's totals:
    /// the most used, as many as there are host registers, and only those
    /// used often enough to repay the load in and the store out.
    fn chooseCache(self: *Compiler, counts: [16]u32) void {
        var taken: [16]bool = @splat(false);
        self.cache_count = 0;
        while (self.cache_count < cache_host_regs.len) {
            var best: ?usize = null;
            for (counts, 0..) |count, index| {
                if (taken[index] or count < cache_min_uses) continue;
                if (best == null or count > counts[best.?]) best = index;
            }
            const chosen = best orelse break;
            taken[chosen] = true;
            self.cache_slot[chosen] = self.cache_count;
            self.cache_ids[self.cache_count] = @enumFromInt(chosen);
            self.cache_count += 1;
        }
    }

    fn loadFlags(self: *Compiler, dst: a64.Reg) Error!void {
        try self.emitChecked(a64.ldrImm(.word, dst, r_regs, rflags_offset));
    }

    /// Write `rflags` and give up any deferred record.
    ///
    /// Every eager flag write in this compiler ends here, which is what
    /// makes the record safe: after any flag-writing instruction, the record
    /// either describes that instruction or is clear. A writer that defers
    /// re-arms it *after* calling this.
    fn storeFlags(self: *Compiler, src: a64.Reg) Error!void {
        try self.emitChecked(a64.strImm(.word, src, r_regs, rflags_offset));
        try self.emitChecked(a64.strImm(.byte, a64.wzr, r_scratch, scratch_flag_kind_offset));
        self.pending_record = 0;
    }

    /// Record `a op b = r` so the flags this instruction did not compute can
    /// be derived on the way out of the block.
    fn emitDeferFlags(self: *Compiler, kind: FlagKind, size: Size, a: a64.Reg, b: a64.Reg, r: a64.Reg, computed: u8) Error!void {
        const owned: u8 = switch (kind) {
            .none => 0,
            .add, .sub => F_ALL,
            // `applyLogic` leaves AF alone, so the record does not own it.
            .logic => F_ALL & ~F_AF,
        };
        // Whatever was computed eagerly is already right in `rflags`, so the
        // record only owes the rest. Without this every reader of a flag the
        // writer just computed would settle for nothing.
        self.pending_record = owned & ~computed;
        try self.a.loadConstant(t4, @intFromEnum(kind));
        try self.emitChecked(a64.strImm(.byte, t4, r_scratch, scratch_flag_kind_offset));
        try self.a.loadConstant(t4, @intFromEnum(size));
        try self.emitChecked(a64.strImm(.byte, t4, r_scratch, scratch_flag_size_offset));
        try self.emitChecked(a64.strImm(.doubleword, a, r_scratch, scratch_flag_a_offset));
        try self.emitChecked(a64.strImm(.doubleword, b, r_scratch, scratch_flag_b_offset));
        try self.emitChecked(a64.strImm(.doubleword, r, r_scratch, scratch_flag_r_offset));
    }

    /// Complete a pending record before an instruction that would otherwise
    /// destroy it.
    ///
    /// An eager flag writer reads `rflags`, changes the bits it owns and
    /// writes the word back. If a record is pending, the bits it has not yet
    /// contributed are stale in that word, and writing it back loses them.
    /// Only a writer that overwrites everything the record holds is exempt -
    /// which is why consecutive arithmetic costs nothing and mixing classes
    /// costs one call.
    ///
    /// Emitted between instructions, never inside a template: it clobbers x0
    /// and the helper-call temporary, and at an instruction boundary nothing
    /// is live in them.
    fn emitSettleFlags(self: *Compiler) Error!void {
        if (self.pending_record == 0) return;
        self.pending_record = 0;
        self.flag_settles += 1;
        const done = try self.a.createLabel();
        try self.emitChecked(a64.ldrImm(.byte, t0, r_scratch, scratch_flag_kind_offset));
        try self.a.branchIfZero(.w32, t0, done);
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitCallHelper(helper_flags_offset);
        self.a.placeLabel(done);
    }

    /// Everything a block does on its way out, before the epilogue.
    ///
    /// Every exit stub branches here with the retired count in x0 and RIP
    /// already stored. It records what this block did, and then - if the
    /// successor it went to last time is still exactly where it was - jumps
    /// straight into that block's body instead of returning.
    ///
    /// That jump is the point. Returning costs an indirect call's
    /// misprediction, a probe of a two-megabyte table to find the successor
    /// again, and a trip through the glue's loop, all for a block that
    /// retires about twenty instructions. Four facts have to hold, and each
    /// is a load and a compare: the successor is the same guest address, it
    /// still occupies the table slot it did, that slot still holds the same
    /// block, and its source has not been rewritten underneath it.
    fn emitChainAttempt(self: *Compiler) Error!void {
        self.a.placeLabel(self.exit_path);
        // Whatever runs next - a chained block, the glue, the interpreter,
        // a fault handler building a context - reads guest registers from
        // the register file, so the cache has to be there first.
        try self.emitCacheWriteBack();
        const leave = self.epilogue_path;
        // Record (block, retired). The chain stops at `chain_log_capacity`,
        // so the log cannot overflow - but check anyway rather than trust an
        // invariant held in another file.
        try self.emitChecked(a64.ldrImm(.doubleword, t2, r_helpers, helper_block_offset));
        try self.emitChecked(a64.ldrImm(.word, t1, r_scratch, scratch_chain_depth_offset));
        try self.emitChecked(a64.cmpImm(.w32, t1, chain_log_capacity));
        try self.a.branchCond(.hs, leave);
        try self.emitStateOffsetAddress(t3, r_scratch, scratch_chain_log_offset);
        try self.emit(a64.addSubShifted(.x64, .add, false, t3, t3, t1, 4));
        try self.emitChecked(a64.strImm(.doubleword, t2, t3, @offsetOf(ChainLogEntry, "block")));
        try self.emitChecked(a64.strImm(.word, 0, t3, @offsetOf(ChainLogEntry, "retired")));
        try self.emitChecked(a64.addImm(.x64, t1, t1, 1));
        try self.emitChecked(a64.strImm(.word, t1, r_scratch, scratch_chain_depth_offset));
        // Stop while the log still has room for the successor's entry.
        // Hopping with a full log would run a block that never gets
        // recorded, and the glue would account fewer instructions than
        // actually retired - which is not a statistic, it is the guest
        // clock and the interpreter's idea of how far the run has got.
        try self.emitChecked(a64.cmpImm(.w32, t1, chain_log_capacity));
        try self.a.branchCond(.hs, leave);
        // A helper has asked for the scheduler, the run has ended, or a
        // fault is pending.
        try self.emitChecked(a64.ldrImm(.word, t0, r_scratch, scratch_chain_break_offset));
        try self.a.branchIfNonZero(.w32, t0, leave);
        try self.emitChecked(a64.ldrImm(.byte, t0, r_scratch, scratch_abort_offset));
        try self.a.branchIfNonZero(.w32, t0, leave);
        // A successor this block went to before, still where it was. Each
        // way costs only its address compare; the way that matches is
        // proved once, below. A matching way whose proof fails leaves, and
        // the glue re-arms that same way.
        const prove = try self.a.createLabel();
        try self.emitChecked(a64.ldrImm(.doubleword, t4, r_regs, rip_offset));
        for (0..link_ways) |way| {
            const base: u32 = @intCast(@offsetOf(Block, "links") + way * @sizeOf(Link));
            const next_way = try self.a.createLabel();
            try self.emitChecked(a64.ldrImm(.doubleword, t3, t2, base + @offsetOf(Link, "rip")));
            try self.emit(a64.cmp(.x64, t3, t4));
            try self.a.branchCond(.ne, next_way);
            try self.emitStateOffsetAddress(t6, t2, base);
            try self.a.branch(prove);
            self.a.placeLabel(next_way);
        }
        try self.a.branch(leave);
        self.a.placeLabel(prove);
        try self.emitChecked(a64.ldrImm(.doubleword, t3, t6, @offsetOf(Link, "slot")));
        try self.a.branchIfZero(.x64, t3, leave);
        try self.emitChecked(a64.ldrImm(.doubleword, t4, t3, 0));
        try self.emitChecked(a64.ldrImm(.doubleword, t5, t6, @offsetOf(Link, "block")));
        try self.emit(a64.cmp(.x64, t4, t5));
        try self.a.branchCond(.ne, leave);
        try self.emitChecked(a64.ldrImm(.doubleword, t3, t6, @offsetOf(Link, "gen_ptr")));
        try self.emitChecked(a64.ldrImm(.doubleword, t4, t3, 0));
        try self.emitChecked(a64.ldrImm(.doubleword, t3, t6, @offsetOf(Link, "generation")));
        try self.emit(a64.cmp(.x64, t4, t3));
        try self.a.branchCond(.ne, leave);
        // Go. `scratch.block` follows the chain because the continuation
        // check reads it to decide whether a store hit the code ahead.
        try self.emitChecked(a64.strImm(.doubleword, t5, r_scratch, scratch_block_offset));
        try self.emitChecked(a64.ldrImm(.doubleword, r_helpers, t6, @offsetOf(Link, "helpers")));
        try self.emitChecked(a64.ldrImm(.doubleword, t3, t6, @offsetOf(Link, "entry")));
        try self.emit(a64.br(t3));
    }

    /// `dst = base + offset`, whatever the offset's size.
    fn emitStateOffsetAddress(self: *Compiler, dst: a64.Reg, base: a64.Reg, offset: u32) Error!void {
        if (a64.addImm(.x64, dst, base, offset)) |word| {
            try self.emit(word);
            return;
        }
        try self.a.loadConstant(dst, offset);
        try self.emit(a64.add(.x64, dst, base, dst));
    }

    /// The one place a block completes its deferred flags: reached only when
    /// the chain did not take, because a chained block's flags are settled
    /// by whichever block finally leaves.
    fn emitFlagCompletion(self: *Compiler) Error!void {
        self.a.placeLabel(self.epilogue_path);
        try self.emitChecked(a64.ldrImm(.byte, t0, r_scratch, scratch_flag_kind_offset));
        try self.a.branchIfZero(.w32, t0, self.epilogue);
        // x0 carries the retired count back to the glue and the helper takes
        // the state in x0, so park it in a callee-saved register the
        // epilogue is about to reload anyway.
        try self.emit(a64.mov(.x64, r_spare, 0));
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitCallHelper(helper_flags_offset);
        try self.emit(a64.mov(.x64, 0, r_spare));
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

    /// ZF, SF and PF of `result` (already masked to `size`) into `flags`,
    /// each only when something still reads it. Parity is the expensive one:
    /// a four-step fold and two masks for a flag x86 code almost never
    /// consults.
    fn emitResultFlags(self: *Compiler, flags: a64.Reg, result: a64.Reg, size: Size, live: u8) Error!void {
        const width = arm(size);
        if ((live & F_ZF) != 0) {
            try self.emitChecked(a64.cmpImm(width, result, 0));
            try self.emit(a64.cset(.w32, t4, .eq));
            try self.orFlagBit(flags, t4, 6);
        }
        if ((live & F_SF) != 0) {
            try self.emit(a64.ubfx(width, t4, result, @intCast(bits(size) - 1), 1));
            try self.orFlagBit(flags, t4, 7);
        }
        if ((live & F_PF) != 0) {
            try self.emitParity(t4, result);
            try self.orFlagBit(flags, t4, 2);
        }
    }

    /// The flags of `a op b = r` exactly as `flags.applyAdd`, `applySub` and
    /// `applyLogic` compute them, and as `highway.addCarry`/`subBorrow`
    /// compute them for `adc`/`sbb`. `a`, `b` and `r` hold values masked to
    /// `size`; `r` may alias neither `a` nor `b`. With `carry_in_t6`, the
    /// carry out was computed by the template into t6 (the `cmp r, a`
    /// derivation below is wrong once a carry-in can make `r == a`).
    fn emitArithmeticFlags(self: *Compiler, kind: ArithKind, size: Size, a: a64.Reg, b: a64.Reg, r: a64.Reg, carry_in_t6: bool) Error!void {
        // `a op b = r` is everything the six flags are a function of, so the
        // ones no later instruction *in this block* reads do not have to be
        // computed here at all: the record carries them to whoever leaves
        // the block. `adc`/`sbb` are the exception - their carry-in is not
        // in the record - so they stay eager and clear it.
        const defer_rest = defer_flags and !carry_in_t6;
        try self.emitArithmeticFlagsEager(kind, size, a, b, r, carry_in_t6, defer_rest);
        // Armed last, because every eager path above ends in `storeFlags`,
        // which gives the record up: after any flag-writing instruction the
        // record either describes it or is clear, and that is the whole
        // invariant this rests on.
        if (defer_rest) try self.emitDeferFlags(switch (kind) {
            .add => .add,
            .sub => .sub,
            .logic => .logic,
        }, size, a, b, r, self.flag_live_block[self.current]);
    }

    fn emitArithmeticFlagsEager(self: *Compiler, kind: ArithKind, size: Size, a: a64.Reg, b: a64.Reg, r: a64.Reg, carry_in_t6: bool, defer_rest: bool) Error!void {
        const width = arm(size);
        const w = bits(size);
        // Only the flags this instruction writes *and* something later
        // reads are cleared and recomputed. The rest keep their previous
        // value, which is exactly what being dead means - and when the
        // record is armed, "later" means later *in this block*, because
        // anything that leaves reads them from the record.
        const live = if (defer_rest) self.flag_live_block[self.current] else F_ALL;
        if (!defer_rest and !self.emit_flags) return;
        const written: u32 = switch (kind) {
            .add, .sub => RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF,
            .logic => RFL_CF | RFL_PF | RFL_ZF | RFL_SF | RFL_OF,
        };
        const mask: u32 = written & liveFlagBits(live);
        if (mask == 0) return;
        try self.loadFlags(t3);
        try self.clearFlagBits(t3, mask);
        try self.emitResultFlags(t3, r, size, live);
        if (kind != .logic) {
            // AF: bit 4 of a ^ b ^ r.
            if ((live & F_AF) != 0) {
                try self.emit(a64.eorReg(.w32, t4, a, b));
                try self.emit(a64.eorReg(.w32, t4, t4, r));
                try self.emit(a64.ubfx(.w32, t4, t4, 4, 1));
                try self.orFlagBit(t3, t4, 4);
            }
            // CF.
            if ((live & F_CF) != 0) {
                if (carry_in_t6) {
                    try self.emit(a64.mov(.w32, t4, t6));
                } else switch (kind) {
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
            }
            // OF: the sign bit of (a ^ r) & (add ? ~(a ^ b) : (a ^ b)).
            if ((live & F_OF) != 0) {
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

    /// The TLB probe shared by loads and stores: with the guest address in
    /// x1, leaves the host address in t4 and falls through on a hit, or
    /// branches to `slow` on a miss or an access that leaves the page.
    fn emitTlbProbe(self: *Compiler, is_write: bool, access_bytes: u64, slow: Label) Error!void {
        try self.emit(a64.lsrImm(.x64, t2, 1, Tlb.page_shift));
        try self.emit(a64.logicalShifted(.x64, .eor, t3, t2, t2, Tlb.fold_shift) | (0b01 << 22)); // eor t3, t2, t2, lsr #fold
        try self.emit(a64.logicalImmediate(.x64, .andop, t3, t3, Tlb.entries - 1).?);
        try self.emit(a64.addSubShifted(.x64, .add, false, t3, r_tlb, t3, 4));
        if (is_write) try self.emitChecked(a64.addImm(.x64, t3, t3, tlb_write_offset));
        try self.emitChecked(a64.ldrImm(.doubleword, t4, t3, 0));
        try self.emit(a64.cmp(.x64, t4, t2));
        try self.a.branchCond(.ne, slow);
        try self.emit(a64.logicalImmediate(.x64, .andop, t5, 1, Tlb.page_bytes - 1).?);
        try self.emitChecked(a64.cmpImm(.x64, t5, Tlb.page_bytes - access_bytes));
        try self.a.branchCond(.hi, slow);
        try self.emitChecked(a64.ldrImm(.doubleword, t4, t3, 8));
        try self.emit(a64.add(.x64, t4, 1, t4));
    }

    /// x0 = read(state, x1, size), on behalf of instruction `index`: through
    /// the TLB when the page is admitted, through the helper otherwise.
    fn emitRead(self: *Compiler, size: Size, index: u32) Error!void {
        self.touches_memory = true;
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.emitTlbProbe(false, bits(size) / 8, slow);
        try self.emitChecked(a64.ldrImm(memSize(size), 0, t4, 0));
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitCurrentIndex(index);
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.a.loadConstant(2, @intFromEnum(size));
        try self.emitCallHelper(helper_read_offset);
        self.a.placeLabel(done);
    }

    /// write(state, x1, size, x3), on behalf of instruction `index`.
    fn emitWrite(self: *Compiler, size: Size, index: u32) Error!void {
        self.touches_memory = true;
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.emitTlbProbe(true, bits(size) / 8, slow);
        try self.emitChecked(a64.strImm(memSize(size), 3, t4, 0));
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitCurrentIndex(index);
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.a.loadConstant(2, @intFromEnum(size));
        try self.emitCallHelper(helper_write_offset);
        self.a.placeLabel(done);
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
        try self.emitInterpretCall(index);
    }

    /// Branch to `slow` when the address in `reg` is an import slot: inside
    /// the import address table, or inside the image when the table's bounds
    /// are unknown. Clobbers t0.
    fn emitImportSlotCheck(self: *Compiler, reg: a64.Reg, slow: Label) Error!void {
        const unknown = try self.a.createLabel();
        const outside = try self.a.createLabel();
        try self.emitStateScalar(.doubleword, t0, self.layout.iat_high_offset);
        try self.a.branchIfZero(.x64, t0, unknown);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.hs, outside);
        try self.emitStateScalar(.doubleword, t0, self.layout.iat_low_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.hs, slow);
        try self.a.branch(outside);
        self.a.placeLabel(unknown);
        try self.emitImageRangeCheck(reg, slow);
        self.a.placeLabel(outside);
    }

    /// Branch to `slow` when the target in `reg` is inside the image and
    /// either the master switch is on or the hook filter names it. A target
    /// outside the image carries no hook and falls through. Clobbers t0,
    /// t2-t4.
    fn emitHookedTargetCheck(self: *Compiler, reg: a64.Reg, slow: Label) Error!void {
        const plain = try self.a.createLabel();
        try self.emitStateScalar(.doubleword, t0, self.layout.image_low_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.lo, plain);
        try self.emitStateScalar(.doubleword, t0, self.layout.image_high_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.hs, plain);
        try self.emitStateScalar(.byte, t0, self.layout.image_targets_hooked_offset);
        try self.a.branchIfNonZero(.w32, t0, slow);
        try self.a.loadConstant(t2, hook_filter_multiplier);
        try self.emit(a64.mul(.x64, t2, reg, t2));
        try self.emit(a64.lsrImm(.x64, t2, t2, hook_filter_shift));
        try self.emit(a64.lsrImm(.x64, t3, t2, 3));
        try self.emitStateAddress(t4, self.layout.hook_filter_offset);
        try self.emit(a64.ldrReg(.byte, t3, t4, t3));
        try self.emit(a64.logicalImmediate(.w32, .andop, t2, t2, 7).?);
        try self.emit(a64.lsrv(.w32, t3, t3, t2));
        try self.emit(a64.logicalImmediate(.w32, .andop, t3, t3, 1).?);
        try self.a.branchIfNonZero(.w32, t3, slow);
        self.a.placeLabel(plain);
    }

    /// Branch to `slow` when the address in `reg` lies inside the guest
    /// image. Clobbers t0.
    fn emitImageRangeCheck(self: *Compiler, reg: a64.Reg, slow: Label) Error!void {
        const outside = try self.a.createLabel();
        try self.emitStateScalar(.doubleword, t0, self.layout.image_low_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.lo, outside);
        try self.emitStateScalar(.doubleword, t0, self.layout.image_high_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.lo, slow);
        self.a.placeLabel(outside);
    }

    /// The call into the interpreter for instruction `index`, without
    /// claiming the instruction as a fallback.
    ///
    /// A guarded template - `call` and `ret` - is native code with an
    /// interpreter escape it takes only when an instrument is armed. Counting
    /// its escape as a fallback would put the instruction in both halves of
    /// `compiled_instructions(native/fallback)` and inflate exactly the
    /// number these templates exist to reduce.
    fn emitInterpretCall(self: *Compiler, index: u32) Error!void {
        try self.emitCurrentIndex(index);
        // The interpreter reads and writes guest registers in memory. Hand
        // it the cache's values, and take back whatever it changed.
        try self.emitCacheWriteBack();
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitChecked(a64.ldrImm(.doubleword, 1, r_helpers, helper_block_offset));
        try self.a.loadConstant(2, index);
        try self.emitCallHelper(helper_interpret_offset);
        // x25-x28 survived the call, but the guest registers they stand for
        // may not have. Reload into the cache only - w0 is the interpreter's
        // answer and is read next.
        try self.emitCacheLoad();
        // The interpreter may have moved the hoisted base register.
        self.hoist_live = false;
        const stub = try self.exitStub(index + 1, null);
        try self.a.branchIfNonZero(.w32, 0, stub);
    }

    /// x1 = the effective address, then x0 = the operand read at `size`.
    /// Choose the block's hoisting base: the guest register with the most
    /// plain `[base+disp]` accesses, if there are at least two and their
    /// displacements span no more than a page.
    fn planHoist(self: *Compiler) void {
        var counts: [16]u32 = @splat(0);
        var low: [16]u64 = @splat(std.math.maxInt(u64));
        var high: [16]u64 = @splat(0);
        var stores: [16]bool = @splat(false);
        for (self.insns) |insn| {
            const candidate = hoistCandidate(insn) orelse continue;
            const index: usize = @intFromEnum(candidate.base);
            counts[index] += 1;
            if (mayStoreMemoryOperand(insn.decoded.op)) stores[index] = true;
            // Displacements as signed values shifted into unsigned order.
            const key = candidate.disp +% hoist_disp_bias;
            low[index] = @min(low[index], key);
            high[index] = @max(high[index], key +% candidate.bytes);
        }
        var best: ?usize = null;
        for (counts, 0..) |count, index| {
            // One hoist costs about one probe, so two accesses already pay.
            if (count < 2) continue;
            if (high[index] -% low[index] > hoist_max_span) continue;
            if (best == null or count > counts[best.?]) best = index;
        }
        const chosen = best orelse return;
        self.hoist_base = @enumFromInt(chosen);
        self.hoist_dmin = low[chosen] -% hoist_disp_bias;
        self.hoist_span = high[chosen] -% low[chosen];
        self.hoist_write = stores[chosen];
    }

    /// The offset from the hoisted host pointer for `insn`'s operand, when
    /// the hoist is live and the whole `size`-byte access lies inside the
    /// admitted span; null otherwise, and the ordinary probe runs.
    fn hoistedOffset(self: *const Compiler, insn: Insn, size: Size) ?u64 {
        return self.hoistedOffsetBytes(insn, bits(size) / 8, 0);
    }

    /// The same for an access of `bytes` bytes starting `extra` past the
    /// operand's address (the upper half of a 256-bit move).
    fn hoistedOffsetBytes(self: *const Compiler, insn: Insn, bytes: u64, extra: u64) ?u64 {
        const base = self.hoist_base orelse return null;
        if (!self.hoist_live) return null;
        const candidate = hoistCandidate(insn) orelse return null;
        if (candidate.base != base) return null;
        const offset = (candidate.disp -% self.hoist_dmin) +% extra;
        if (offset > self.hoist_span or bytes > self.hoist_span - offset) return null;
        return offset;
    }

    /// Before an instruction that will use the hoisted base, and only
    /// between instructions - never inside a template's own branches -
    /// translate `base + dmin` once: x29 gets its host address when the
    /// write TLB admits the page and the whole span stays on it, zero
    /// otherwise.
    fn maybeEmitHoist(self: *Compiler, insn: Insn) Error!void {
        const base = self.hoist_base orelse return;
        if (self.hoist_live) return;
        const candidate = hoistCandidate(insn) orelse return;
        if (candidate.base != base) return;
        const miss = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.a.loadConstant(1, self.hoist_dmin);
        try self.loadReg(t0, base, false, .bits64);
        try self.emit(a64.add(.x64, 1, 1, t0));
        try self.emitTlbProbe(self.hoist_write, self.hoist_span, miss);
        try self.emit(a64.mov(.x64, hoist_host, t4));
        try self.a.branch(done);
        self.a.placeLabel(miss);
        try self.emit(a64.mov(.x64, hoist_host, 31));
        self.a.placeLabel(done);
        self.hoist_live = true;
    }

    /// The hot path of a hoisted access: x0 = the operand (read) or the
    /// operand = x3 (write) through x29, and a branch to the ordinary probe,
    /// emitted out of line, when x29 is zero.
    fn emitHoistedAccess(self: *Compiler, insn: Insn, size: Size, index: u32, offset: u64, is_write: bool) Error!void {
        const full = try self.a.createLabel();
        const resume_at = try self.a.createLabel();
        try self.a.branchIfZero(.x64, hoist_host, full);
        try self.emitHostAccess(is_write, size, if (is_write) 3 else 0, offset);
        self.a.placeLabel(resume_at);
        try self.cold_accesses.append(self.allocator, .{ .full = full, .resume_at = resume_at, .insn = insn, .size = size, .index = index, .is_write = is_write });
        self.touches_memory = true;
        self.hoisted_accesses += 1;
    }

    /// Every hoisted access's ordinary path: the effective address, the
    /// TLB probe and the helper, then back to where the access resumes.
    fn emitColdAccesses(self: *Compiler) Error!void {
        for (self.cold_accesses.items) |cold| {
            self.a.placeLabel(cold.full);
            if (cold.vector) |v| {
                if (cold.is_write)
                    try self.emitStoreVecProbed(cold.insn, cold.index, v, cold.vector_offset)
                else
                    try self.emitLoadVecProbed(cold.insn, cold.index, v, cold.vector_offset);
            } else {
                try self.emitEffectiveAddress(1, cold.insn);
                if (cold.is_write) try self.emitWrite(cold.size, cold.index) else try self.emitRead(cold.size, cold.index);
            }
            try self.a.branch(cold.resume_at);
        }
    }

    /// A 128-bit access through the hoisted pointer, with the ordinary one
    /// out of line for when x29 is zero.
    fn emitHoistedVector(self: *Compiler, insn: Insn, index: u32, v: a64.Reg, byte_offset: u32, offset: u64, is_write: bool) Error!void {
        const full = try self.a.createLabel();
        const resume_at = try self.a.createLabel();
        try self.a.branchIfZero(.x64, hoist_host, full);
        const word = if (is_write) a64.vstrQ(v, hoist_host, @intCast(offset)) else a64.vldrQ(v, hoist_host, @intCast(offset));
        if (word) |encoded| {
            try self.emit(encoded);
        } else {
            try self.a.loadConstant(t5, offset);
            try self.emit(a64.add(.x64, t5, hoist_host, t5));
            try self.emitChecked(if (is_write) a64.vstrQ(v, t5, 0) else a64.vldrQ(v, t5, 0));
        }
        self.a.placeLabel(resume_at);
        try self.cold_accesses.append(self.allocator, .{ .full = full, .resume_at = resume_at, .insn = insn, .size = .bits64, .index = index, .is_write = is_write, .vector = v, .vector_offset = byte_offset });
        self.touches_memory = true;
        self.hoisted_accesses += 1;
    }

    /// `data` to or from `[x29 + offset]` at `size`.
    fn emitHostAccess(self: *Compiler, is_write: bool, size: Size, data: a64.Reg, offset: u64) Error!void {
        const ms = memSize(size);
        const word = if (is_write) a64.strImm(ms, data, hoist_host, @intCast(offset)) else a64.ldrImm(ms, data, hoist_host, @intCast(offset));
        if (word) |encoded| {
            try self.emit(encoded);
            return;
        }
        try self.a.loadConstant(t5, offset);
        try self.emit(a64.add(.x64, t5, hoist_host, t5));
        try self.emitChecked(if (is_write) a64.strImm(ms, data, t5, 0) else a64.ldrImm(ms, data, t5, 0));
    }

    fn emitLoadOperand(self: *Compiler, insn: Insn, size: Size, index: u32) Error!void {
        if (self.hoistedOffset(insn, size)) |offset| {
            try self.emitHoistedAccess(insn, size, index, offset, false);
            return;
        }
        try self.emitEffectiveAddress(1, insn);
        try self.emitRead(size, index);
    }

    /// Store t0 to the instruction's memory operand at `size`, recomputing
    /// the address (the helpers clobber every temporary).
    fn emitStoreOperand(self: *Compiler, insn: Insn, size: Size, index: u32) Error!void {
        try self.emit(a64.mov(.x64, 3, t0));
        // A store may use the hoisted pointer only when it came from the
        // write TLB: that is what keeps code pages (self-modifying code) and
        // watched pages (Xenia's GPU write watch) on the write helper.
        if (self.hoist_write) {
            if (self.hoistedOffset(insn, size)) |offset| {
                try self.emitHoistedAccess(insn, size, index, offset, true);
                return;
            }
        }
        try self.emitEffectiveAddress(1, insn);
        try self.emitWrite(size, index);
    }

    fn emitInsn(self: *Compiler, index: u32) Error!Emitted {
        const insn = self.insns[index];
        const d = insn.decoded;
        self.current = index;
        try self.maybeEmitHoist(insn);
        self.emit_flags = self.flag_wants[index];
        self.emit_flag_mask = self.flag_live[index];
        if (self.emit_flags and (self.emit_flag_mask & flagEffects(insn).writes) != flagEffects(insn).writes) {
            self.flags_narrowed += 1;
        }
        const effects = flagEffects(insn);
        if (insn.force_fallback or !isNative(d)) {
            // `blockJitInterpret` settles the record before the interpreter
            // runs, so nothing is emitted here - but the tracker has to know.
            self.pending_record = 0;
            try self.emitFallback(index);
            return .fallback;
        }
        // A reader of a flag the record owns, or a writer that would not
        // overwrite all of them, has to settle first. The record can be
        // pending before this block's first instruction, because a native
        // chain hop enters here without passing the completion on the way
        // out of the block before it.
        if (effects.reads != 0 and (self.pending_record & effects.reads) != 0) {
            try self.emitSettleFlags();
        }
        if (effects.writes != 0 and (self.pending_record & ~effects.writes) != 0) {
            try self.emitSettleFlags();
        }
        self.native_count += 1;
        if (try self.emitVectorInsn(insn, index)) return .native;
        if (binaryOpOf(d.op)) |op| {
            try self.emitGroup1(op, insn, index);
            return .native;
        }
        if (isIncDec(d.op)) |form| {
            try self.emitIncDecInsn(form.inc, form.mem, incDecSize(d.op), insn, index);
            return .native;
        }
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
                try self.emitLoadOperand(insn, size, index);
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
            .movbe_reg_mem => {
                // `byteSwap(size, readMemVal(...))`.
                try self.emitLoadOperand(insn, d.size, index);
                try self.emitByteSwap(t1, 0, d.size);
                try self.storeReg(d.dst_reg, false, d.size, t1);
                try self.emitAbortCheck(index);
            },
            .ldmxcsr_mem32 => {
                try self.emitLoadOperand(insn, .bits32, index);
                try self.emitChecked(a64.strImm(.word, 0, r_regs, mxcsr_offset));
                try self.emitAbortCheck(index);
            },
            .stmxcsr_mem32 => {
                try self.emitChecked(a64.ldrImm(.word, t0, r_regs, mxcsr_offset));
                try self.emitStoreOperand(insn, .bits32, index);
                try self.emitAbortCheck(index);
            },
            .movbe_mem_reg => {
                try self.loadReg(t1, d.src_reg, false, d.size);
                try self.emitByteSwap(3, t1, d.size);
                try self.emitEffectiveAddress(1, insn);
                try self.emitWrite(d.size, index);
                try self.emitAbortCheck(index);
            },
            .movzx_reg32_mem8, .movzx_reg32_mem16 => {
                const source_size: Size = if (d.op == .movzx_reg32_mem8) .bits8 else .bits16;
                if (d.is_reg_form) {
                    try self.loadReg(t1, d.src_reg, d.src_high8, source_size);
                    try self.storeReg(d.dst_reg, false, d.size, t1);
                } else {
                    try self.emitLoadOperand(insn, source_size, index);
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
                    try self.emitLoadOperand(insn, source_size, index);
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
                try self.emitLoadOperand(insn, .bits32, index);
                try self.emit(a64.sxtw(t2, 0));
                try self.storeReg(d.dst_reg, false, .bits64, t2);
                try self.emitAbortCheck(index);
            },
            .lea_reg_mem => {
                try self.emitEffectiveAddress(t1, insn);
                try self.storeReg(d.dst_reg, false, d.size, t1);
            },
            .xchg_reg32_reg32, .xchg_reg64_reg64 => {
                try self.loadReg(t1, d.dst_reg, false, d.size);
                try self.loadReg(t2, d.src_reg, false, d.size);
                try self.storeReg(d.dst_reg, false, d.size, t2);
                try self.storeReg(d.src_reg, false, d.size, t1);
            },
            .xchg_accum_reg => {
                try self.loadReg(t1, .al_ax_eax_rax, false, d.size);
                try self.loadReg(t2, d.src_reg, false, d.size);
                try self.storeReg(.al_ax_eax_rax, false, d.size, t2);
                try self.storeReg(d.src_reg, false, d.size, t1);
            },
            .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
                // setFlagsSub(0, a, r): a subtraction with a zero left side.
                try self.emit(a64.mov(.x64, t1, a64.xzr));
                try self.loadReg(t2, d.dst_reg, false, d.size);
                try self.emitBinaryCompute(.sub, d.size);
                try self.storeReg(d.dst_reg, false, d.size, t0);
            },
            .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => {
                try self.emitLoadOperand(insn, d.size, index);
                try self.emit(a64.mov(.x64, t1, a64.xzr));
                try self.emit(a64.mov(.x64, t2, 0));
                try self.emitBinaryCompute(.sub, d.size);
                try self.emitStoreOperand(insn, d.size, index);
                try self.emitAbortCheck(index);
            },
            .not_reg8, .not_reg16, .not_reg32, .not_reg64 => {
                try self.loadReg(t1, d.dst_reg, false, d.size);
                try self.emit(a64.mvn(arm(d.size), t1, t1));
                try self.storeReg(d.dst_reg, false, d.size, t1);
            },
            .not_mem8, .not_mem16, .not_mem32, .not_mem64 => {
                try self.emitLoadOperand(insn, d.size, index);
                try self.emit(a64.mvn(arm(d.size), t0, 0));
                if (d.size == .bits8 or d.size == .bits16) try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(d.size)).?);
                try self.emitStoreOperand(insn, d.size, index);
                try self.emitAbortCheck(index);
            },
            .shl_reg_imm, .shr_reg_imm, .sar_reg_imm => try self.emitShift(d),
            .shl_reg_cl, .shr_reg_cl, .sar_reg_cl => try self.emitShiftCl(d),
            .rol_reg_imm, .ror_reg_imm => try self.emitRotateImm(d),
            .rol_reg_cl, .ror_reg_cl => try self.emitRotateCl(d),
            .imul_reg64_reg64, .imul_reg32_reg32 => {
                // The interpreter arm names the width itself and ignores
                // `d.size`; the first differential run caught a 64-bit
                // product truncated to 32 bits from trusting the field.
                const size: Size = if (d.op == .imul_reg64_reg64) .bits64 else .bits32;
                try self.loadReg(t1, d.dst_reg, false, size);
                try self.loadReg(t2, d.src_reg, false, size);
                try self.emitImul(d.dst_reg, size);
            },
            .imul_reg64_mem64, .imul_reg32_mem32 => {
                const size: Size = if (d.op == .imul_reg64_mem64) .bits64 else .bits32;
                try self.emitLoadOperand(insn, size, index);
                try self.loadReg(t1, d.dst_reg, false, size);
                try self.emit(a64.mov(.x64, t2, 0));
                try self.emitImul(d.dst_reg, size);
                try self.emitAbortCheck(index);
            },
            .imul_reg32_reg32_imm8, .imul_reg32_reg32_imm32, .imul_reg64_reg64_imm8, .imul_reg64_reg64_imm32, .imul_reg32_mem32_imm8, .imul_reg32_mem32_imm32, .imul_reg64_mem64_imm8, .imul_reg64_mem64_imm32 => {
                const size: Size = switch (d.op) {
                    .imul_reg32_reg32_imm8, .imul_reg32_reg32_imm32, .imul_reg32_mem32_imm8, .imul_reg32_mem32_imm32 => .bits32,
                    else => .bits64,
                };
                const immediate: u64 = switch (d.op) {
                    .imul_reg32_reg32_imm8, .imul_reg64_reg64_imm8, .imul_reg32_mem32_imm8, .imul_reg64_mem64_imm8 => signExtendImm8(d.imm),
                    else => @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(d.imm)))))),
                };
                if (d.is_reg_form) {
                    try self.loadReg(t1, d.src_reg, false, size);
                } else {
                    try self.emitLoadOperand(insn, size, index);
                    try self.emit(a64.mov(.x64, t1, 0));
                }
                try self.a.loadConstant(t2, immediate & maskFor(size));
                try self.emitImul(d.dst_reg, size);
                if (!d.is_reg_form) try self.emitAbortCheck(index);
            },
            .mul_reg32, .imul_reg32 => {
                try self.loadReg(t1, .al_ax_eax_rax, false, .bits32);
                try self.loadReg(t2, d.src_reg, false, .bits32);
                if (d.op == .mul_reg32) {
                    try self.emit(a64.umull(t0, t1, t2));
                } else {
                    try self.emit(a64.smull(t0, t1, t2));
                }
                try self.emit(a64.lsrImm(.x64, t4, t0, 32));
                try self.storeReg(.al_ax_eax_rax, false, .bits32, t0);
                try self.storeReg(.dl_dx_edx_rdx, false, .bits32, t4);
            },
            .mul_reg64, .imul_reg64 => {
                try self.loadReg(t1, .al_ax_eax_rax, false, .bits64);
                try self.loadReg(t2, d.src_reg, false, .bits64);
                try self.emit(a64.mul(.x64, t0, t1, t2));
                if (d.op == .mul_reg64) {
                    try self.emit(a64.umulh(t4, t1, t2));
                } else {
                    try self.emit(a64.smulh(t4, t1, t2));
                }
                try self.storeReg(.al_ax_eax_rax, false, .bits64, t0);
                try self.storeReg(.dl_dx_edx_rdx, false, .bits64, t4);
            },
            .div_reg32, .div_reg64, .idiv_reg32, .idiv_reg64 => try self.emitDivide(d, index),
            .bt_reg_reg => try self.emitBitTest(d, .probe, false),
            .bts_reg_reg => try self.emitBitTest(d, .set, false),
            .btr_reg_reg => try self.emitBitTest(d, .reset, false),
            .bt_reg_imm => try self.emitBitTest(d, .probe, true),
            .bts_reg_imm => try self.emitBitTest(d, .set, true),
            .btr_reg_imm => try self.emitBitTest(d, .reset, true),
            .xchg_mem32_reg32, .xchg_mem64_reg64, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64, .xadd_mem32_reg32, .xadd_mem64_reg64 => try self.emitAtomic(insn, index, atomicForm(d.op).?),
            .bt_mem_imm => try self.emitBitTestMemory(insn, index, .probe),
            .bts_mem_imm => try self.emitBitTestMemory(insn, index, .set),
            .btr_mem_imm => try self.emitBitTestMemory(insn, index, .reset),
            .bsf_reg_reg, .bsr_reg_reg => try self.emitBitScan(d),
            .tzcnt_reg_reg, .lzcnt_reg_reg => try self.emitCountZeros(d),
            .cmovcc_reg_reg => {
                try self.loadFlags(t3);
                try self.emitCondition(t4, t3, d.cond);
                try self.loadReg(t1, d.dst_reg, false, d.size);
                try self.loadReg(t2, d.src_reg, false, d.size);
                try self.emitChecked(a64.cmpImm(.w32, t4, 0));
                try self.emit(a64.csel(arm(d.size), t1, t2, t1, .ne));
                try self.storeReg(d.dst_reg, false, d.size, t1);
            },
            .cmovcc_reg_mem => {
                // The interpreter reads the operand whether or not the move
                // happens (a fault on it is raised either way), and rewrites
                // a 32-bit destination at its width when it does not.
                try self.emitLoadOperand(insn, d.size, index);
                try self.loadFlags(t3);
                try self.emitCondition(t4, t3, d.cond);
                try self.loadReg(t1, d.dst_reg, false, d.size);
                try self.emitChecked(a64.cmpImm(.w32, t4, 0));
                try self.emit(a64.csel(arm(d.size), t1, 0, t1, .ne));
                try self.storeReg(d.dst_reg, false, d.size, t1);
                try self.emitAbortCheck(index);
            },
            .setcc_reg8 => {
                try self.loadFlags(t3);
                try self.emitCondition(t4, t3, d.cond);
                try self.storeReg(d.dst_reg, d.dst_high8, .bits8, t4);
            },
            .setcc_mem8 => {
                // The condition goes straight into the store helper's value
                // register, which `emitEffectiveAddress` does not touch.
                try self.loadFlags(t3);
                try self.emitCondition(3, t3, d.cond);
                try self.emitEffectiveAddress(1, insn);
                try self.emitWrite(.bits8, index);
                try self.emitAbortCheck(index);
            },
            .mfence, .lfence, .sfence => try self.emit(a64.dmbIsh()),
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
                // The not-taken edge is the next instruction. When the trace
                // continues across this branch that is simply the next thing
                // emitted, so only a branch that ends the block needs a stub
                // for it.
                if (index + 1 == self.insns.len) {
                    const not_taken = try self.exitStub(index + 1, next);
                    try self.a.branch(not_taken);
                }
            },
            .jmp_rel8 => {
                const next = insn.rip +% d.len;
                const target = next +% d.imm;
                const stub = try self.exitStub(index + 1, target);
                try self.a.branch(stub);
            },
            .call_rel32 => {
                // Everything the interpreter's arm does beyond pushing the
                // return address and jumping is either keyed on the target,
                // which the glue has already ruled out for this call site,
                // or gated on a trace that is read here. Both traces are run
                // configuration rather than anything a block can change, but
                // they are read rather than baked in: a block outlives the
                // moment it was translated in.
                const next_rip = insn.rip +% d.len;
                const target = next_rip +% @as(u64, @bitCast(d.imm));
                const slow = try self.a.createLabel();
                try self.emitStateScalar(.byte, t0, self.layout.trace_calls_offset);
                try self.a.branchIfNonZero(.w32, t0, slow);
                try self.emitStateScalar(.byte, t0, self.layout.trace_transfers_offset);
                try self.a.branchIfNonZero(.w32, t0, slow);
                // push(next_rip), exactly as the `push_imm` template does.
                try self.a.loadConstant(3, next_rip);
                try self.loadReg(1, .ah_sp_esp_rsp, false, .bits64);
                try self.emitChecked(a64.subImm(.x64, 1, 1, 8));
                try self.storeReg(.ah_sp_esp_rsp, false, .bits64, 1);
                try self.emitWrite(.bits64, index);
                try self.emitAbortCheck(index);
                const taken = try self.exitStub(index + 1, target);
                try self.a.branch(taken);
                self.a.placeLabel(slow);
                try self.emitInterpretCall(index);
                const consumed = try self.exitStub(index + 1, next_rip);
                try self.a.branch(consumed);
            },
            .jmp_reg64, .call_reg64, .call_mem64 => {
                const next_rip = insn.rip +% d.len;
                const is_call = d.op != .jmp_reg64;
                const slow = try self.a.createLabel();
                try self.emitStateScalar(.byte, t0, self.layout.trace_transfers_offset);
                try self.a.branchIfNonZero(.w32, t0, slow);
                if (is_call) {
                    try self.emitStateScalar(.byte, t0, self.layout.trace_calls_offset);
                    try self.a.branchIfNonZero(.w32, t0, slow);
                }
                // x0 = the target. A memory operand inside the image may be
                // an import slot the interpreter's shim owns.
                if (d.op == .call_mem64) {
                    try self.emitEffectiveAddress(1, insn);
                    try self.emitImportSlotCheck(1, slow);
                    try self.emitRead(.bits64, index);
                    try self.emitAbortCheck(index);
                } else {
                    try self.loadReg(0, d.dst_reg, false, .bits64);
                }
                try self.a.branchIfZero(.x64, 0, slow);
                try self.emitHookedTargetCheck(0, slow);
                if (is_call) {
                    try self.emitChecked(a64.strImm(.doubleword, 0, r_scratch, scratch_transfer_target_offset));
                    // push(next_rip), exactly as the `call_rel32` template does.
                    try self.a.loadConstant(3, next_rip);
                    try self.loadReg(1, .ah_sp_esp_rsp, false, .bits64);
                    try self.emitChecked(a64.subImm(.x64, 1, 1, 8));
                    try self.storeReg(.ah_sp_esp_rsp, false, .bits64, 1);
                    try self.emitWrite(.bits64, index);
                    try self.emitAbortCheck(index);
                    try self.emitChecked(a64.ldrImm(.doubleword, 0, r_scratch, scratch_transfer_target_offset));
                }
                try self.emitChecked(a64.strImm(.doubleword, 0, r_regs, rip_offset));
                const taken = try self.exitStub(index + 1, null);
                try self.a.branch(taken);
                self.a.placeLabel(slow);
                try self.emitInterpretCall(index);
                const consumed = try self.exitStub(index + 1, next_rip);
                try self.a.branch(consumed);
            },
            .ret => {
                // The interpreter's `ret` arm does four things beyond the
                // pop, and this template must not silently drop any of them:
                //
                //   1. completes an armed guest return capture,
                //   2. feeds the ABI call stack when `trace_calls` is on,
                //   3. logs the worker completion marker on a zero return
                //      address,
                //   4. logs an EscapeString return under `trace_string_memory`
                //      - which cannot be on here, because per-instruction
                //      tracing refuses to create the translator at all.
                //
                // 1 and 2 are state, so they are read here; 3 is a property
                // of the popped value. Each check sits before anything is
                // mutated, and the pop's read is pure, so handing the
                // instruction back to the interpreter costs only the work
                // already done and repeats nothing that had an effect.
                const slow = try self.a.createLabel();
                try self.emitStateScalar(.byte, t0, self.layout.trace_calls_offset);
                try self.a.branchIfNonZero(.w32, t0, slow);
                try self.emitStateScalar(.word, t0, self.layout.return_captures_offset);
                try self.a.branchIfNonZero(.w32, t0, slow);
                // x1 = rsp, then x0 = [rsp]. The read does not move rsp.
                try self.loadReg(1, .ah_sp_esp_rsp, false, .bits64);
                try self.emitRead(.bits64, index);
                try self.emitAbortCheck(index);
                try self.a.branchIfZero(.x64, 0, slow);
                // Commit. The helper may have clobbered every temporary, so
                // rsp is re-read from the register file exactly as `pop_reg`
                // does rather than reused from x1.
                try self.loadReg(t1, .ah_sp_esp_rsp, false, .bits64);
                try self.emitChecked(a64.addImm(.x64, t1, t1, 8));
                try self.storeReg(.ah_sp_esp_rsp, false, .bits64, t1);
                try self.emitChecked(a64.strImm(.doubleword, 0, r_regs, rip_offset));
                const taken = try self.exitStub(index + 1, null);
                try self.a.branch(taken);
                self.a.placeLabel(slow);
                try self.emitInterpretCall(index);
                // The interpret call leaves through its own stub when the
                // interpreter transferred control. Falling through means a
                // shim consumed the transfer and left RIP after the
                // instruction, which is where the block ends - the same tail
                // `compile` gives every other fallback terminator.
                const consumed = try self.exitStub(index + 1, insn.rip +% insn.len);
                try self.a.branch(consumed);
            },
            else => unreachable,
        }
        return .native;
    }

    /// `dst = byteSwap(size, src)` for 16, 32 and 64 bits (`src` is
    /// zero-extended at `size`).
    fn emitByteSwap(self: *Compiler, dst: a64.Reg, src: a64.Reg, size: Size) Error!void {
        switch (size) {
            .bits16 => try self.emit(a64.rev16(.w32, dst, src)),
            .bits32 => try self.emit(a64.rev(.w32, dst, src)),
            .bits64 => try self.emit(a64.rev(.x64, dst, src)),
            .bits8 => unreachable,
        }
    }

    /// The Group-1 family in every operand shape, with `highway.evaluate`'s
    /// operand order: the destination is the left operand.
    fn emitGroup1(self: *Compiler, op: BinaryOp, insn: Insn, index: u32) Error!void {
        const d = insn.decoded;
        const size = d.size;
        const writes = op != .cmp and op != .tst;
        switch (binaryShapeOf(d.op)) {
            .reg_reg => {
                try self.loadReg(t1, d.dst_reg, d.dst_high8, size);
                try self.loadReg(t2, d.src_reg, d.src_high8, size);
                try self.emitBinaryCompute(op, size);
                if (writes) try self.storeReg(d.dst_reg, d.dst_high8, size, t0);
            },
            .reg_imm => {
                try self.loadReg(t1, d.dst_reg, d.dst_high8, size);
                try self.a.loadConstant(t2, immediateValue(d) & maskFor(size));
                try self.emitBinaryCompute(op, size);
                if (writes) try self.storeReg(d.dst_reg, d.dst_high8, size, t0);
            },
            .reg_mem => {
                try self.emitLoadOperand(insn, size, index);
                try self.loadReg(t1, d.dst_reg, d.dst_high8, size);
                // `emitRead` and the hoisted read path return the memory
                // value in x0. Keep it as the right hand operand; using a
                // scratch register here can retain the address calculation
                // instead of the loaded guest value.
                try self.emit(a64.mov(.x64, t2, 0));
                try self.emitBinaryCompute(op, size);
                if (writes) try self.storeReg(d.dst_reg, d.dst_high8, size, t0);
                try self.emitAbortCheck(index);
            },
            .mem_reg => {
                try self.emitLoadOperand(insn, size, index);
                // The loaded memory value is the left operand for a
                // memory/register form.  Copy it before loading the source
                // register into t2 so emitBinaryCompute sees both operands.
                try self.emit(a64.mov(.x64, t1, 0));
                try self.loadReg(t2, d.src_reg, d.src_high8, size);
                try self.emitBinaryCompute(op, size);
                if (writes) try self.emitStoreOperand(insn, size, index);
                try self.emitAbortCheck(index);
            },
            .mem_imm => {
                try self.emitLoadOperand(insn, size, index);
                // As above, x0 is the value read from the guest address.
                try self.emit(a64.mov(.x64, t1, 0));
                try self.a.loadConstant(t2, immediateValue(d) & maskFor(size));
                try self.emitBinaryCompute(op, size);
                if (writes) try self.emitStoreOperand(insn, size, index);
                try self.emitAbortCheck(index);
            },
        }
    }

    /// t0 = t1 op t2, masked to `size`, with the flags (when wanted). Both
    /// inputs hold values masked to `size`.
    fn emitBinaryCompute(self: *Compiler, op: BinaryOp, size: Size) Error!void {
        const width = arm(size);
        switch (op) {
            .adc, .sbb => return self.emitCarryCompute(op == .adc, size),
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
            .adc, .sbb => unreachable,
        };
        try self.emitArithmeticFlags(kind, size, t1, t2, t0, false);
    }

    /// `adc`/`sbb`: t0 = t1 ± t2 ± CF with `highway.addCarry`/`subBorrow`'s
    /// flags. The carry out is computed here into t6 because a carry-in can
    /// make the result equal the left operand without a carry having
    /// happened, which is what the plain add/sub derivation assumes.
    fn emitCarryCompute(self: *Compiler, is_add: bool, size: Size) Error!void {
        const w = bits(size);
        try self.loadFlags(t3);
        try self.emit(a64.logicalImmediate(.w32, .andop, t5, t3, 1).?);
        if (size == .bits64) {
            const cond: a64.Cond = if (is_add) .hs else .lo;
            if (is_add) {
                try self.emit(a64.adds(.x64, t0, t1, t2));
                try self.emit(a64.cset(.w32, t6, cond));
                try self.emit(a64.adds(.x64, t0, t0, t5));
            } else {
                try self.emit(a64.subs(.x64, t0, t1, t2));
                try self.emit(a64.cset(.w32, t6, cond));
                try self.emit(a64.subs(.x64, t0, t0, t5));
            }
            try self.emit(a64.cset(.w32, t4, cond));
            try self.emit(a64.orrReg(.w32, t6, t6, t4));
        } else {
            if (is_add) {
                try self.emit(a64.add(.x64, t0, t1, t2));
                try self.emit(a64.add(.x64, t0, t0, t5));
            } else {
                try self.emit(a64.sub(.x64, t0, t1, t2));
                try self.emit(a64.sub(.x64, t0, t0, t5));
            }
            // Zero-extended inputs: bit `w` of the exact result is the carry
            // out of an add and the borrow of a subtract.
            try self.emit(a64.ubfx(.x64, t6, t0, @intCast(w), 1));
            try self.emit(a64.logicalImmediate(.x64, .andop, t0, t0, maskFor(size)).?);
        }
        try self.emitArithmeticFlags(if (is_add) .add else .sub, size, t1, t2, t0, true);
    }

    /// `inc`/`dec` on a register or a memory operand.
    fn emitIncDecInsn(self: *Compiler, is_inc: bool, mem: bool, size: Size, insn: Insn, index: u32) Error!void {
        const d = insn.decoded;
        if (mem) {
            try self.emitLoadOperand(insn, size, index);
            try self.emit(a64.mov(.x64, t1, 0));
        } else {
            try self.loadReg(t1, d.dst_reg, false, size);
        }
        try self.emitIncDecCompute(size, is_inc);
        if (mem) {
            try self.emitStoreOperand(insn, size, index);
            try self.emitAbortCheck(index);
        } else {
            try self.storeReg(d.dst_reg, false, size, t0);
        }
    }

    /// t0 = t1 ± 1 masked, with `flags.applyIncDec`: CF is preserved.
    fn emitIncDecCompute(self: *Compiler, size: Size, is_inc: bool) Error!void {
        const width = arm(size);
        const w = bits(size);
        if (is_inc) {
            try self.emitChecked(a64.addImm(width, t0, t1, 1));
        } else {
            try self.emitChecked(a64.subImm(width, t0, t1, 1));
        }
        if (size == .bits8 or size == .bits16) {
            try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(size)).?);
        }
        if (!self.emit_flags) return;
        // `inc`/`dec` preserve CF; the rest follow the same per-flag rule as
        // the arithmetic templates, so a flag is cleared only where it is
        // also recomputed.
        // `inc`/`dec` are not in the deferred record - it has no shape for
        // "preserves CF" - so this writer owns `rflags` outright and must
        // compute every flag an exit could read, not just the ones read in
        // this block.
        const live = F_ALL;
        const mask: u32 = (RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF) & liveFlagBits(live);
        if (mask == 0) return;
        try self.loadFlags(t3);
        try self.clearFlagBits(t3, mask);
        try self.emitResultFlags(t3, t0, size, live);
        // OF: inc overflows from the largest positive, dec from the smallest
        // negative.
        if ((live & F_OF) != 0) {
            const sign: u64 = @as(u64, 1) << @intCast(w - 1);
            try self.a.loadConstant(t4, if (is_inc) sign - 1 else sign);
            try self.emit(a64.cmp(width, t1, t4));
            try self.emit(a64.cset(.w32, t4, .eq));
            try self.orFlagBit(t3, t4, 11);
        }
        // AF: the low nibble wrapped.
        if ((live & F_AF) != 0) {
            try self.emit(a64.logicalImmediate(.w32, .andop, t4, t1, 0xF).?);
            try self.emitChecked(a64.cmpImm(.w32, t4, if (is_inc) 0xF else 0));
            try self.emit(a64.cset(.w32, t4, .eq));
            try self.orFlagBit(t3, t4, 4);
        }
        try self.storeFlags(t3);
    }

    /// Shift by an immediate at 32 or 64 bits, with the interpreter's
    /// `setFlagsShl/Shr/Sar`: CF, SF, ZF, and OF only when the count is one;
    /// PF and AF untouched; nothing when the count is zero.
    fn emitShift(self: *Compiler, d: DecodedInsn) Error!void {
        const size = d.size;
        const width = arm(size);
        const w = bits(size);
        const count: u6 = shiftCount(d);
        try self.loadReg(t1, d.dst_reg, d.dst_high8, size);
        if (count == 0) {
            // `shlValue` still re-writes the register at its width.
            try self.storeReg(d.dst_reg, d.dst_high8, size, t1);
            return;
        }
        switch (d.op) {
            .shl_reg_imm => try self.emit(a64.lslImm(width, t0, t1, count)),
            .shr_reg_imm => try self.emit(a64.lsrImm(width, t0, t1, count)),
            .sar_reg_imm => if (w < 32) {
                // Sign-extend the narrow operand first; the arithmetic
                // shift then brings copies of its sign bit down.
                try self.emit(a64.sbfx(.w32, t0, t1, 0, @intCast(w)));
                try self.emit(a64.asrImm(.w32, t0, t0, count));
            } else try self.emit(a64.asrImm(width, t0, t1, count)),
            else => unreachable,
        }
        // At 8 and 16 bits the 32-bit host result carries bits above the
        // operand, which ZF and SF must not see.
        if (w < 32) try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, (@as(u64, 1) << @intCast(w)) - 1).?);
        if (self.emit_flags) {
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
        }
        try self.storeReg(d.dst_reg, d.dst_high8, size, t0);
    }

    /// Shift by `cl` at 32 or 64 bits: the count is masked, a zero count
    /// only re-writes the register at its width, and OF is written only
    /// when the count is one (`setFlagsShl/Shr/Sar`).
    fn emitShiftCl(self: *Compiler, d: DecodedInsn) Error!void {
        const size = d.size;
        const width = arm(size);
        const w = bits(size);
        try self.loadReg(t1, d.dst_reg, false, size);
        try self.loadReg(t2, .cl_cx_ecx_rcx, false, .bits8);
        try self.emit(a64.logicalImmediate(.w32, .andop, t2, t2, if (size == .bits64) 0x3F else 0x1F).?);
        const zero = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.a.branchIfZero(.w32, t2, zero);
        switch (d.op) {
            .shl_reg_cl => try self.emit(a64.lslv(width, t0, t1, t2)),
            .shr_reg_cl => try self.emit(a64.lsrv(width, t0, t1, t2)),
            .sar_reg_cl => try self.emit(a64.asrv(width, t0, t1, t2)),
            else => unreachable,
        }
        if (self.emit_flags) {
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_CF | RFL_SF | RFL_ZF);
            try self.emitChecked(a64.cmpImm(width, t0, 0));
            try self.emit(a64.cset(.w32, t4, .eq));
            try self.orFlagBit(t3, t4, 6);
            try self.emit(a64.ubfx(width, t4, t0, @intCast(w - 1), 1));
            try self.orFlagBit(t3, t4, 7);
            // CF into t6: bit (w - count) of the input for a left shift,
            // bit (count - 1) for a right shift.
            switch (d.op) {
                .shl_reg_cl => {
                    try self.a.loadConstant(t5, w);
                    try self.emit(a64.sub(.w32, t5, t5, t2));
                },
                else => try self.emitChecked(a64.subImm(.w32, t5, t2, 1)),
            }
            try self.emit(a64.lsrv(width, t6, t1, t5));
            try self.emit(a64.logicalImmediate(.w32, .andop, t6, t6, 1).?);
            try self.orFlagBit(t3, t6, 0);
            // OF, only when the count is one; otherwise the old bit stays.
            switch (d.op) {
                .shl_reg_cl => {
                    try self.emit(a64.ubfx(width, t4, t0, @intCast(w - 1), 1));
                    try self.emit(a64.eorReg(.w32, t4, t4, t6));
                },
                .shr_reg_cl => try self.emit(a64.ubfx(width, t4, t1, @intCast(w - 1), 1)),
                .sar_reg_cl => try self.emit(a64.mov(.w32, t4, a64.wzr)),
                else => unreachable,
            }
            try self.emit(a64.ubfx(.w32, t5, t3, 11, 1));
            try self.emitChecked(a64.cmpImm(.w32, t2, 1));
            try self.emit(a64.csel(.w32, t4, t4, t5, .eq));
            try self.clearFlagBits(t3, RFL_OF);
            try self.orFlagBit(t3, t4, 11);
            try self.storeFlags(t3);
        }
        try self.storeReg(d.dst_reg, false, size, t0);
        try self.a.branch(done);
        self.a.placeLabel(zero);
        try self.storeReg(d.dst_reg, false, size, t1);
        self.a.placeLabel(done);
    }

    /// `rol`/`ror` by an immediate at 32 or 64 bits (`executeRotate`): a
    /// zero count does nothing at all; CF is the bit rotated around, OF is
    /// written only for a count of one.
    fn emitRotateImm(self: *Compiler, d: DecodedInsn) Error!void {
        const size = d.size;
        const width = arm(size);
        const w = bits(size);
        // The interpreter reduces a narrow count modulo the width, and a
        // count that reduces to zero does nothing - flags included.
        const count: u6 = @intCast(@as(u64, shiftCount(d)) % w);
        if (count == 0) return;
        const left = d.op == .rol_reg_imm;
        try self.loadReg(t1, d.dst_reg, d.dst_high8, size);
        if (w < 32) {
            // 8 and 16 bits (`rol ax, 8` is a 16-bit byte swap): the two
            // halves of the rotation, joined and cut back to the operand.
            const up: u6 = if (left) count else @intCast(w - count);
            const down: u6 = if (left) @intCast(w - count) else count;
            try self.emit(a64.lslImm(.w32, t0, t1, up));
            try self.emit(a64.lsrImm(.w32, t5, t1, down));
            try self.emit(a64.orrReg(.w32, t0, t0, t5));
            try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, (@as(u64, 1) << @intCast(w)) - 1).?);
        } else {
            try self.emit(a64.rorImm(width, t0, t1, if (left) @intCast(w - count) else count));
        }
        if (self.emit_flags) {
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_CF | (if (count == 1) RFL_OF else 0));
            if (left) {
                try self.emit(a64.logicalImmediate(.w32, .andop, t4, t0, 1).?);
            } else {
                try self.emit(a64.ubfx(width, t4, t0, @intCast(w - 1), 1));
            }
            try self.orFlagBit(t3, t4, 0);
            if (count == 1) {
                if (left) {
                    // OF = msb(result) != CF.
                    try self.emit(a64.ubfx(width, t5, t0, @intCast(w - 1), 1));
                    try self.emit(a64.eorReg(.w32, t4, t5, t4));
                } else {
                    // OF = CF != bit (w - 2) of the result.
                    try self.emit(a64.ubfx(width, t5, t0, @intCast(w - 2), 1));
                    try self.emit(a64.eorReg(.w32, t4, t4, t5));
                }
                try self.orFlagBit(t3, t4, 11);
            }
            try self.storeFlags(t3);
        }
        try self.storeReg(d.dst_reg, d.dst_high8, size, t0);
    }

    /// `rol`/`ror` by `cl` at 32 or 64 bits.
    fn emitRotateCl(self: *Compiler, d: DecodedInsn) Error!void {
        const size = d.size;
        const width = arm(size);
        const w = bits(size);
        const left = d.op == .rol_reg_cl;
        try self.loadReg(t1, d.dst_reg, false, size);
        try self.loadReg(t2, .cl_cx_ecx_rcx, false, .bits8);
        try self.emit(a64.logicalImmediate(.w32, .andop, t2, t2, if (size == .bits64) 0x3F else 0x1F).?);
        const done = try self.a.createLabel();
        try self.a.branchIfZero(.w32, t2, done);
        if (left) {
            try self.a.loadConstant(t5, w);
            try self.emit(a64.sub(.w32, t5, t5, t2));
            try self.emit(a64.rorv(width, t0, t1, t5));
        } else {
            try self.emit(a64.rorv(width, t0, t1, t2));
        }
        if (self.emit_flags) {
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_CF);
            if (left) {
                try self.emit(a64.logicalImmediate(.w32, .andop, t6, t0, 1).?);
            } else {
                try self.emit(a64.ubfx(width, t6, t0, @intCast(w - 1), 1));
            }
            try self.orFlagBit(t3, t6, 0);
            if (left) {
                try self.emit(a64.ubfx(width, t4, t0, @intCast(w - 1), 1));
                try self.emit(a64.eorReg(.w32, t4, t4, t6));
            } else {
                try self.emit(a64.ubfx(width, t4, t0, @intCast(w - 2), 1));
                try self.emit(a64.eorReg(.w32, t4, t6, t4));
            }
            try self.emit(a64.ubfx(.w32, t5, t3, 11, 1));
            try self.emitChecked(a64.cmpImm(.w32, t2, 1));
            try self.emit(a64.csel(.w32, t4, t4, t5, .eq));
            try self.clearFlagBits(t3, RFL_OF);
            try self.orFlagBit(t3, t4, 11);
            try self.storeFlags(t3);
        }
        try self.storeReg(d.dst_reg, false, size, t0);
        self.a.placeLabel(done);
    }

    /// `dst = low bits of t1 * t2`; CF = OF = the signed product does not fit.
    fn emitImul(self: *Compiler, dst: RegId, size: Size) Error!void {
        if (size == .bits64) {
            try self.emit(a64.mul(.x64, t0, t1, t2));
            if (self.emit_flags) {
                try self.emit(a64.smulh(t4, t1, t2));
                try self.emit(a64.asrImm(.x64, t5, t0, 63));
                try self.emit(a64.cmp(.x64, t4, t5));
            }
        } else {
            try self.emit(a64.smull(t0, t1, t2));
            if (self.emit_flags) {
                try self.emit(a64.sxtw(t4, t0));
                try self.emit(a64.cmp(.x64, t4, t0));
            }
        }
        if (self.emit_flags) {
            try self.emit(a64.cset(.w32, t4, .ne));
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_CF | RFL_OF);
            try self.orFlagBit(t3, t4, 0);
            try self.orFlagBit(t3, t4, 11);
            try self.storeFlags(t3);
        }
        try self.storeReg(dst, false, size, t0);
    }

    /// `div`/`idiv` at 32 or 64 bits when the quotient provably fits: a
    /// zero divisor, a high half that would overflow, or a divisor of -1
    /// (the one signed case that overflows with a fitting high half) go to
    /// the interpreter, which raises #DE exactly as it always did.
    fn emitDivide(self: *Compiler, d: DecodedInsn, index: u32) Error!void {
        const size: Size = switch (d.op) {
            .div_reg32, .idiv_reg32 => .bits32,
            else => .bits64,
        };
        const signed = d.op == .idiv_reg32 or d.op == .idiv_reg64;
        const width = arm(size);
        const w = bits(size);
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.loadReg(t2, d.src_reg, false, size);
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

    const BitTestKind = enum { probe, set, reset };

    /// `bt`/`bts`/`btr` on a register (`bit_test.applyRegister`): the index
    /// is reduced modulo the operand width, CF is the selected bit.
    fn emitBitTest(self: *Compiler, d: DecodedInsn, kind: BitTestKind, immediate: bool) Error!void {
        const size = d.size;
        const width = arm(size);
        const w = bits(size);
        try self.loadReg(t1, d.dst_reg, false, size);
        if (immediate) {
            const bit: u6 = @intCast(d.imm & (w - 1));
            if (self.emit_flags) try self.emit(a64.ubfx(width, t4, t1, bit, 1));
            try self.a.loadConstant(t5, @as(u64, 1) << bit);
        } else {
            try self.loadReg(t2, d.src_reg, false, size);
            try self.emit(a64.logicalImmediate(.w32, .andop, t2, t2, w - 1).?);
            if (self.emit_flags) {
                try self.emit(a64.lsrv(width, t4, t1, t2));
                try self.emit(a64.logicalImmediate(.w32, .andop, t4, t4, 1).?);
            }
            try self.a.loadConstant(t5, 1);
            try self.emit(a64.lslv(width, t5, t5, t2));
        }
        switch (kind) {
            .probe => {},
            .set => try self.emit(a64.orrReg(width, t0, t1, t5)),
            .reset => try self.emit(a64.bicReg(width, t0, t1, t5)),
        }
        if (self.emit_flags) {
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_CF);
            try self.orFlagBit(t3, t4, 0);
            try self.storeFlags(t3);
        }
        if (kind != .probe) try self.storeReg(d.dst_reg, false, size, t0);
    }

    /// A locked read-modify-write as one LSE atomic on the host address the
    /// write TLB gives. Anything the fast path cannot prove - a page that is
    /// not admitted for writes (watched, or holding code), or an address
    /// that is not naturally aligned, which an LSE atomic would fault on -
    /// is handed to the interpreter whole, so nothing is half done.
    /// Semantics are the interpreter's arms: `cmpxchg` compares the
    /// accumulator, sets the flags of `cmp acc, old`, and on a mismatch
    /// loads the accumulator with the old value; `xadd` sets the flags of
    /// the add and returns the old value in the register; `xchg` swaps.
    fn emitAtomic(self: *Compiler, insn: Insn, index: u32, form: AtomicForm) Error!void {
        const d = insn.decoded;
        const size = d.size;
        const width = arm(size);
        const bytes: u64 = bits(size) / 8;
        self.touches_memory = true;
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.emitEffectiveAddress(1, insn);
        try self.emitTlbProbe(true, bytes, slow);
        try self.emit(a64.logicalImmediate(.x64, .andop, t5, 1, bytes - 1).?);
        try self.a.branchIfNonZero(.x64, t5, slow);
        switch (form) {
            .exchange => {
                try self.loadReg(t0, d.src_reg, false, size);
                try self.emit(a64.swpal(width, t0, t1, t4));
                try self.storeReg(d.src_reg, false, size, t1);
            },
            .compare_exchange => {
                try self.emit(a64.mov(.x64, 2, t4));
                try self.loadReg(t1, .al_ax_eax_rax, false, size);
                try self.emit(a64.mov(width, 3, t1));
                try self.loadReg(t0, d.src_reg, false, size);
                try self.emit(a64.casal(width, 3, t0, 2));
                try self.emit(a64.mov(width, t2, 3));
                try self.emit(a64.sub(width, t0, t1, t2));
                try self.emitArithmeticFlags(.sub, size, t1, t2, t0, false);
                const matched = try self.a.createLabel();
                try self.emit(a64.cmp(width, t1, t2));
                try self.a.branchCond(.eq, matched);
                try self.storeReg(.al_ax_eax_rax, false, size, t2);
                self.a.placeLabel(matched);
            },
            .exchange_add => {
                try self.loadReg(t2, d.src_reg, false, size);
                try self.emit(a64.ldaddal(width, t2, t1, t4));
                try self.emit(a64.add(width, t0, t1, t2));
                try self.emitArithmeticFlags(.add, size, t1, t2, t0, false);
                try self.storeReg(d.src_reg, false, size, t1);
            },
        }
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitInterpretCall(index);
        self.a.placeLabel(done);
    }

    /// `bt`/`bts`/`btr [mem], imm` (`executeBitTestMemory`): the immediate
    /// is reduced modulo the width and never moves the address. CF is the
    /// selected bit, set before the write exactly as the interpreter does;
    /// a write that faults is retried from the same memory, so the CF it
    /// leaves is the one the retry recomputes.
    fn emitBitTestMemory(self: *Compiler, insn: Insn, index: u32, kind: BitTestKind) Error!void {
        const d = insn.decoded;
        const size = d.size;
        const width = arm(size);
        const w = bits(size);
        const bit: u6 = @intCast(d.imm & (w - 1));
        try self.emitLoadOperand(insn, size, index);
        try self.emitAbortCheck(index);
        if (self.emit_flags) {
            try self.emit(a64.ubfx(width, t4, 0, bit, 1));
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_CF);
            try self.orFlagBit(t3, t4, 0);
            try self.storeFlags(t3);
        }
        if (kind == .probe) return;
        try self.a.loadConstant(t5, @as(u64, 1) << bit);
        switch (kind) {
            .probe => unreachable,
            .set => try self.emit(a64.orrReg(width, t0, 0, t5)),
            .reset => try self.emit(a64.bicReg(width, t0, 0, t5)),
        }
        try self.emitStoreOperand(insn, size, index);
        try self.emitAbortCheck(index);
    }

    /// `bsf`/`bsr` (`cpu.bitScan`): a zero source sets ZF and leaves the
    /// destination alone; otherwise ZF is clear and the destination is the
    /// bit index. Other flags untouched.
    fn emitBitScan(self: *Compiler, d: DecodedInsn) Error!void {
        const size = d.size;
        const width = arm(size);
        const host_bits: u64 = if (size == .bits64) 64 else 32;
        try self.loadReg(t1, d.src_reg, false, size);
        const zero = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.a.branchIfZero(width, t1, zero);
        if (d.op == .bsf_reg_reg) {
            try self.emit(a64.rbit(width, t0, t1));
            try self.emit(a64.clz(width, t0, t0));
        } else {
            try self.emit(a64.clz(width, t0, t1));
            try self.a.loadConstant(t4, host_bits - 1);
            try self.emit(a64.sub(width, t0, t4, t0));
        }
        try self.storeReg(d.dst_reg, false, size, t0);
        if (self.emit_flags) {
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_ZF);
            try self.storeFlags(t3);
        }
        try self.a.branch(done);
        self.a.placeLabel(zero);
        if (self.emit_flags) {
            try self.loadFlags(t3);
            try self.emit(a64.logicalImmediate(.w32, .orr, t3, t3, RFL_ZF).?);
            try self.storeFlags(t3);
        }
        self.a.placeLabel(done);
    }

    /// `tzcnt`/`lzcnt` at 32 or 64 bits: the count is the operand width for
    /// a zero source, CF says the source was zero, ZF says the count is.
    fn emitCountZeros(self: *Compiler, d: DecodedInsn) Error!void {
        const size = d.size;
        const width = arm(size);
        try self.loadReg(t1, d.src_reg, false, size);
        if (d.op == .tzcnt_reg_reg) {
            try self.emit(a64.rbit(width, t0, t1));
            try self.emit(a64.clz(width, t0, t0));
        } else {
            try self.emit(a64.clz(width, t0, t1));
        }
        try self.storeReg(d.dst_reg, false, size, t0);
        if (self.emit_flags) {
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_ZF | RFL_CF);
            try self.emitChecked(a64.cmpImm(width, t1, 0));
            try self.emit(a64.cset(.w32, t4, .eq));
            try self.orFlagBit(t3, t4, 0);
            try self.emitChecked(a64.cmpImm(width, t0, 0));
            try self.emit(a64.cset(.w32, t4, .eq));
            try self.orFlagBit(t3, t4, 6);
            try self.storeFlags(t3);
        }
    }

    // -- vector register file and memory ------------------------------------------

    fn xmmOffset(index: u8) u32 {
        return @as(u32, index) * 16;
    }

    fn loadXmm(self: *Compiler, v: a64.Reg, index: u8) Error!void {
        try self.emitChecked(a64.vldrQ(v, r_spare, xmmOffset(index)));
    }

    fn storeXmm(self: *Compiler, index: u8, v: a64.Reg) Error!void {
        try self.emitChecked(a64.vstrQ(v, r_spare, xmmOffset(index)));
    }

    fn loadYmmHigh(self: *Compiler, v: a64.Reg, index: u8) Error!void {
        try self.emitStateAddress(t0, self.layout.ymm_hi_offset + xmmOffset(index));
        try self.emitChecked(a64.vldrQ(v, t0, 0));
    }

    fn storeYmmHigh(self: *Compiler, index: u8, v: a64.Reg) Error!void {
        try self.emitStateAddress(t0, self.layout.ymm_hi_offset + xmmOffset(index));
        try self.emitChecked(a64.vstrQ(v, t0, 0));
    }

    /// Clear the upper YMM half of `index` (every VEX.128 write), and the
    /// ZMM upper half too for the forms the EVEX executor serves. The upper
    /// files are addressed from the state base: a Zig struct's fields may be
    /// laid out in any order, so nothing assumes they follow `xmm`.
    fn clearUpper(self: *Compiler, index: u8, op: Op) Error!void {
        try self.emit(a64.vmoviZero(v7));
        try self.emitStateAddress(t0, self.layout.ymm_hi_offset + xmmOffset(index));
        try self.emitChecked(a64.vstrQ(v7, t0, 0));
        if (evexRouted(op)) {
            try self.emitStateAddress(t0, self.layout.zmm_hi_offset + @as(u32, index) * 32);
            try self.emitChecked(a64.vstrQ(v7, t0, 0));
            try self.emitChecked(a64.vstrQ(v7, t0, 16));
        }
    }

    /// v = the 16 bytes at the instruction's memory operand: through the
    /// TLB when the page is admitted, through the 128-bit helper otherwise.
    fn emitLoadVec(self: *Compiler, insn: Insn, index: u32, v: a64.Reg) Error!void {
        try self.emitLoadVecOffset(insn, index, v, 0);
    }

    /// The same, `byte_offset` further along: the upper half of a 256-bit
    /// access lives sixteen bytes above the lower one.
    fn emitLoadVecOffset(self: *Compiler, insn: Insn, index: u32, v: a64.Reg, byte_offset: u32) Error!void {
        if (self.hoistedOffsetBytes(insn, 16, byte_offset)) |offset| {
            try self.emitHoistedVector(insn, index, v, byte_offset, offset, false);
            return;
        }
        try self.emitLoadVecProbed(insn, index, v, byte_offset);
    }

    /// The ordinary 128-bit load: the operand's address, the TLB probe, and
    /// the helper when the page is not admitted.
    fn emitLoadVecProbed(self: *Compiler, insn: Insn, index: u32, v: a64.Reg, byte_offset: u32) Error!void {
        self.touches_memory = true;
        try self.emitEffectiveAddress(1, insn);
        if (byte_offset != 0) try self.emitChecked(a64.addImm(.x64, 1, 1, byte_offset));
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.emitTlbProbe(false, 16, slow);
        try self.emitChecked(a64.vldrQ(v, t4, 0));
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitCurrentIndex(index);
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitChecked(a64.addImm(.x64, 2, r_scratch, scratch_vector_offset));
        try self.emitCallHelper(helper_read128_offset);
        try self.emitChecked(a64.vldrQ(v, r_scratch, scratch_vector_offset));
        self.a.placeLabel(done);
    }

    /// Store v to the instruction's memory operand.
    fn emitStoreVec(self: *Compiler, insn: Insn, index: u32, v: a64.Reg) Error!void {
        try self.emitStoreVecOffset(insn, index, v, 0);
    }

    fn emitStoreVecOffset(self: *Compiler, insn: Insn, index: u32, v: a64.Reg, byte_offset: u32) Error!void {
        if (self.hoist_write) {
            if (self.hoistedOffsetBytes(insn, 16, byte_offset)) |offset| {
                try self.emitHoistedVector(insn, index, v, byte_offset, offset, true);
                return;
            }
        }
        try self.emitStoreVecProbed(insn, index, v, byte_offset);
    }

    /// The ordinary 128-bit store, as `emitLoadVecProbed`.
    fn emitStoreVecProbed(self: *Compiler, insn: Insn, index: u32, v: a64.Reg, byte_offset: u32) Error!void {
        self.touches_memory = true;
        try self.emitEffectiveAddress(1, insn);
        if (byte_offset != 0) try self.emitChecked(a64.addImm(.x64, 1, 1, byte_offset));
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.emitTlbProbe(true, 16, slow);
        try self.emitChecked(a64.vstrQ(v, t4, 0));
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitChecked(a64.vstrQ(v, r_scratch, scratch_vector_offset));
        try self.emitCurrentIndex(index);
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitChecked(a64.addImm(.x64, 2, r_scratch, scratch_vector_offset));
        try self.emitCallHelper(helper_write128_offset);
        self.a.placeLabel(done);
    }

    /// v = the second source: xmm_src2, or the memory operand.
    fn loadSource2(self: *Compiler, insn: Insn, index: u32, v: a64.Reg) Error!void {
        if (insn.decoded.is_reg_form) {
            try self.loadXmm(v, insn.decoded.xmm_src2);
        } else {
            try self.emitLoadVec(insn, index, v);
        }
    }

    /// v = a unary source that the interpreter reads from xmm_src (register
    /// form) or memory.
    fn loadUnarySource(self: *Compiler, insn: Insn, index: u32, v: a64.Reg) Error!void {
        if (insn.decoded.is_reg_form) {
            try self.loadXmm(v, insn.decoded.xmm_src);
        } else {
            try self.emitLoadVec(insn, index, v);
        }
    }

    /// The low scalar of the second source into v (upper lanes zero): from
    /// xmm_src2's low lane or a 32/64-bit memory read.
    fn loadScalarSource2(self: *Compiler, insn: Insn, index: u32, fp: a64.FpWidth, v: a64.Reg) Error!void {
        if (insn.decoded.is_reg_form) {
            try self.loadXmm(v, insn.decoded.xmm_src2);
            return;
        }
        try self.emitLoadOperand(insn, if (fp == .single) .bits32 else .bits64, index);
        if (fp == .single) {
            try self.emit(a64.fmovSFromW(v, 0));
        } else {
            try self.emit(a64.fmovFromGpr(v, 0));
        }
    }

    /// Whether the instruction read memory (so the abort flag must be checked).
    fn touchesMemory(d: DecodedInsn) bool {
        return !d.is_reg_form;
    }

    /// Set v to the all-ones/all-zeros lane mask of predicate `imm & 7`
    /// between v1 (left) and v2 (right), as `VexComparePredicate.evaluate`.
    fn emitFloatCompareMask(self: *Compiler, lanes: a64.FpLanes, v: a64.Reg, imm: u8) Error!void {
        switch (imm & 7) {
            0 => try self.emit(a64.vfcmeq(lanes, v, v1, v2)),
            1 => try self.emit(a64.vfcmgt(lanes, v, v2, v1)),
            2 => try self.emit(a64.vfcmge(lanes, v, v2, v1)),
            3 => {
                // Unordered: either operand is a NaN.
                try self.emit(a64.vfcmeq(lanes, v3, v1, v1));
                try self.emit(a64.vfcmeq(lanes, v4, v2, v2));
                try self.emit(a64.vand(v, v3, v4));
                try self.emit(a64.vnot(v, v));
            },
            4 => {
                try self.emit(a64.vfcmeq(lanes, v, v1, v2));
                try self.emit(a64.vnot(v, v));
            },
            5 => {
                try self.emit(a64.vfcmgt(lanes, v, v2, v1));
                try self.emit(a64.vnot(v, v));
            },
            6 => {
                try self.emit(a64.vfcmge(lanes, v, v2, v1));
                try self.emit(a64.vnot(v, v));
            },
            7 => {
                try self.emit(a64.vfcmeq(lanes, v3, v1, v1));
                try self.emit(a64.vfcmeq(lanes, v4, v2, v2));
                try self.emit(a64.vand(v, v3, v4));
            },
            else => unreachable,
        }
    }

    /// Packed float to signed dword with the interpreter's rule: NaN and
    /// out-of-range lanes become the integer indefinite 0x80000000. The
    /// hardware conversion saturates, so a positive overflow reads
    /// 0x7FFFFFFF (which no single can produce legitimately) and a NaN reads
    /// zero; both are rewritten.
    fn emitPackedFloatToDword(self: *Compiler, truncate: bool) Error!void {
        // v2 = source, v0 = result.
        if (truncate) {
            try self.emit(a64.vfcvtzs(.s4, v0, v2));
        } else {
            // `convertFloatToDword` rounds half away from zero.
            try self.emit(a64.vfrint(.nearest_away, .s4, v3, v2));
            try self.emit(a64.vfcvtzs(.s4, v0, v3));
        }
        try self.emit(a64.vmovi32(v5, 0x80, 3, true)); // 0x7FFFFFFF
        try self.emit(a64.vcmeq(.s4, v4, v0, v5));
        try self.emit(a64.veor(v0, v0, v4)); // 0x7FFFFFFF -> 0x80000000 where saturated high
        try self.emit(a64.vfcmeq(.s4, v4, v2, v2)); // ordered lanes
        try self.emit(a64.vmovi32(v5, 0x80, 3, false)); // 0x80000000
        try self.emit(a64.vbic(v5, v5, v4)); // indefinite where NaN
        try self.emit(a64.vorr(v0, v0, v5));
    }

    /// Scalar float to signed integer (`convertVexFloatToSigned`): round
    /// (toward zero, or to nearest even), then NaN and values outside the
    /// destination's range give the indefinite value. The rounded value in
    /// v3 is compared against +2^bits-1 because the saturating conversion
    /// cannot tell a legitimate maximum from an overflow.
    fn emitScalarFloatToInt(self: *Compiler, fp: a64.FpWidth, to_64: bool, truncate: bool) Error!void {
        // v2 = source scalar; result in x0.
        try self.emit(a64.frintScalar(if (truncate) .toward_zero else .nearest_even, fp, v3, v2));
        try self.emit(a64.fcvtzsScalar(fp, to_64, 0, v3));
        const limit: u64 = if (fp == .single) (if (to_64) 0x5F00_0000 else 0x4F00_0000) else (if (to_64) 0x43E0_0000_0000_0000 else 0x41E0_0000_0000_0000);
        try self.a.loadConstant(t4, limit);
        if (fp == .single) {
            try self.emit(a64.fmovSFromW(v4, t4));
        } else {
            try self.emit(a64.fmovFromGpr(v4, t4));
        }
        try self.emit(a64.fcmp(fp, v3, v4));
        try self.emit(a64.cset(.w32, t4, .ge));
        try self.emit(a64.cset(.w32, t5, .vs));
        try self.emit(a64.orrReg(.w32, t4, t4, t5));
        try self.a.loadConstant(t5, if (to_64) @as(u64, 0x8000_0000_0000_0000) else 0x8000_0000);
        try self.emitChecked(a64.cmpImm(.w32, t4, 0));
        try self.emit(a64.csel(.x64, 0, t5, 0, .ne));
    }

    /// The x86 flags of an ordered/unordered scalar compare
    /// (`setVexComparisonFlags`): unordered sets ZF, PF and CF; less sets
    /// CF; equal sets ZF; OF, SF and AF are cleared.
    fn emitCompareFlags(self: *Compiler, fp: a64.FpWidth) Error!void {
        if (!self.emit_flags) return;
        try self.emit(a64.fcmp(fp, v1, v2));
        try self.loadFlags(t3);
        try self.clearFlagBits(t3, RFL_OF | RFL_SF | RFL_ZF | RFL_AF | RFL_PF | RFL_CF);
        try self.emit(a64.cset(.w32, t4, .vs));
        try self.orFlagBit(t3, t4, 0);
        try self.orFlagBit(t3, t4, 2);
        try self.orFlagBit(t3, t4, 6);
        try self.emit(a64.cset(.w32, t4, .mi));
        try self.orFlagBit(t3, t4, 0);
        try self.emit(a64.cset(.w32, t4, .eq));
        try self.orFlagBit(t3, t4, 6);
        try self.storeFlags(t3);
    }

    fn roundModeOf(imm: u64) a64.RoundMode {
        if (imm & 4 != 0) return .nearest_even;
        return switch (imm & 3) {
            0 => .nearest_even,
            1 => .toward_minus,
            2 => .toward_plus,
            else => .toward_zero,
        };
    }

    /// The vector templates. True when the instruction was emitted here.
    fn emitVectorInsn(self: *Compiler, insn: Insn, index: u32) Error!bool {
        const d = insn.decoded;
        if (!isVectorNative(d)) return false;
        self.touches_vectors = true;
        const dst = d.xmm_dst;
        if (d.vector_256) {
            if (d.op == .vcvtps2pd) {
                // Four singles from the 128-bit source: the low two to the
                // xmm half, the high two to the upper half.
                try self.loadSource2(insn, index, v2);
                try self.emit(a64.vfcvtl(v0, v2));
                try self.emit(a64.vfcvtl2(v1, v2));
                try self.storeXmm(dst, v0);
                try self.storeYmmHigh(dst, v1);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
                return true;
            }
            // Two 128-bit halves, and no upper-half clear: at 256 bits the
            // upper half is what the instruction writes.
            switch (ymmMoveForm(d.op).?) {
                .load => {
                    try self.emitLoadVecOffset(insn, index, v0, 0);
                    try self.storeXmm(dst, v0);
                    try self.emitLoadVecOffset(insn, index, v0, 16);
                    try self.storeYmmHigh(dst, v0);
                    try self.emitAbortCheck(index);
                },
                .store => {
                    try self.loadXmm(v0, d.xmm_src);
                    try self.emitStoreVecOffset(insn, index, v0, 0);
                    try self.loadYmmHigh(v0, d.xmm_src);
                    try self.emitStoreVecOffset(insn, index, v0, 16);
                    try self.emitAbortCheck(index);
                },
                .register => {
                    try self.loadXmm(v0, d.xmm_src);
                    try self.storeXmm(dst, v0);
                    try self.loadYmmHigh(v0, d.xmm_src);
                    try self.storeYmmHigh(dst, v0);
                },
            }
            return true;
        }
        // Memory operands are read before any vector register is loaded: a
        // TLB miss calls a helper, and helpers keep no vector register.
        if (packedIntegerForm(d.op)) |form| {
            try self.loadSource2(insn, index, v2);
            try self.loadXmm(v1, d.xmm_src);
            try self.emit(switch (form.kind) {
                .add => a64.vadd(form.lanes, v0, v1, v2),
                .sub => a64.vsub(form.lanes, v0, v1, v2),
                .mul => a64.vmul(form.lanes, v0, v1, v2),
                .cmeq => a64.vcmeq(form.lanes, v0, v1, v2),
                .cmgt => a64.vcmgt(form.lanes, v0, v1, v2),
                .smax => a64.vsmax(form.lanes, v0, v1, v2),
                .smin => a64.vsmin(form.lanes, v0, v1, v2),
                .umax => a64.vumax(form.lanes, v0, v1, v2),
                .umin => a64.vumin(form.lanes, v0, v1, v2),
                .sqadd => a64.vsqadd(form.lanes, v0, v1, v2),
                .uqadd => a64.vuqadd(form.lanes, v0, v1, v2),
                .sqsub => a64.vsqsub(form.lanes, v0, v1, v2),
                .uqsub => a64.vuqsub(form.lanes, v0, v1, v2),
                .urhadd => a64.vurhadd(form.lanes, v0, v1, v2),
            });
            try self.storeXmm(dst, v0);
            try self.clearUpper(dst, d.op);
            if (touchesMemory(d)) try self.emitAbortCheck(index);
            return true;
        }
        if (packedFloatForm(d.op)) |form| {
            try self.loadSource2(insn, index, v2);
            try self.loadXmm(v1, d.xmm_src);
            switch (form.kind) {
                .add => try self.emit(a64.vfadd(form.lanes, v0, v1, v2)),
                .sub => try self.emit(a64.vfsub(form.lanes, v0, v1, v2)),
                .mul => try self.emit(a64.vfmul(form.lanes, v0, v1, v2)),
                .div => try self.emit(a64.vfdiv(form.lanes, v0, v1, v2)),
                // `applyVexArithmetic`: min is `if (a < b) a else b`, max
                // `if (a > b) a else b`: the second operand for NaN and ties.
                .min => {
                    try self.emit(a64.vfcmgt(form.lanes, v0, v2, v1));
                    try self.emit(a64.vbsl(v0, v1, v2));
                },
                .max => {
                    try self.emit(a64.vfcmgt(form.lanes, v0, v1, v2));
                    try self.emit(a64.vbsl(v0, v1, v2));
                },
            }
            try self.storeXmm(dst, v0);
            try self.clearUpper(dst, d.op);
            if (touchesMemory(d)) try self.emitAbortCheck(index);
            return true;
        }
        if (scalarFloatForm(d.op)) |form| {
            try self.loadScalarSource2(insn, index, form.fp, v2);
            try self.loadXmm(v1, d.xmm_src);
            switch (form.kind) {
                .add => try self.emit(a64.fadd(form.fp, v3, v1, v2)),
                .sub => try self.emit(a64.fsub(form.fp, v3, v1, v2)),
                .mul => try self.emit(a64.fmul(form.fp, v3, v1, v2)),
                .div => try self.emit(a64.fdiv(form.fp, v3, v1, v2)),
                .min => {
                    try self.emit(a64.fcmp(form.fp, v1, v2));
                    try self.emit(a64.fcsel(form.fp, v3, v1, v2, .mi));
                },
                .max => {
                    try self.emit(a64.fcmp(form.fp, v1, v2));
                    try self.emit(a64.fcsel(form.fp, v3, v1, v2, .gt));
                },
            }
            try self.emit(a64.vmov(v0, v1));
            try self.emit(a64.vinsLane(if (form.fp == .single) .s4 else .d2, v0, 0, v3, 0));
            try self.storeXmm(dst, v0);
            try self.clearUpper(dst, d.op);
            if (touchesMemory(d)) try self.emitAbortCheck(index);
            return true;
        }
        if (bitwiseForm(d.op)) |kind| {
            try self.loadSource2(insn, index, v2);
            try self.loadXmm(v1, d.xmm_src);
            try self.emit(switch (kind) {
                .and_ => a64.vand(v0, v1, v2),
                // `~left & right`.
                .andn => a64.vbic(v0, v2, v1),
                .or_ => a64.vorr(v0, v1, v2),
                .xor => a64.veor(v0, v1, v2),
            });
            try self.storeXmm(dst, v0);
            try self.clearUpper(dst, d.op);
            if (touchesMemory(d)) try self.emitAbortCheck(index);
            return true;
        }
        if (unpackForm(d.op)) |form| {
            try self.loadSource2(insn, index, v2);
            try self.loadXmm(v1, d.xmm_src);
            try self.emit(if (form.high) a64.vzip2(form.lanes, v0, v1, v2) else a64.vzip1(form.lanes, v0, v1, v2));
            try self.storeXmm(dst, v0);
            try self.clearUpper(dst, d.op);
            if (touchesMemory(d)) try self.emitAbortCheck(index);
            return true;
        }
        if (shiftForm(d.op)) |form| {
            // `executeVexPackedShift`: the source is xmm_src or memory, the
            // count is the immediate; a count at or past the lane width
            // zeroes (logical) or fills with the sign (arithmetic).
            try self.loadUnarySource(insn, index, v1);
            const count: u64 = d.imm & 0xFF;
            const width: u64 = if (form.kind == .left_bytes or form.kind == .right_bytes) 16 else form.lanes.elementBits();
            if (count == 0) {
                try self.emit(a64.vmov(v0, v1));
            } else switch (form.kind) {
                .left => if (count >= width) try self.emit(a64.vmoviZero(v0)) else try self.emit(a64.vshl(form.lanes, v0, v1, @intCast(count))),
                .right_logical => if (count >= width) try self.emit(a64.vmoviZero(v0)) else try self.emit(a64.vushr(form.lanes, v0, v1, @intCast(count))),
                .right_arithmetic => try self.emit(a64.vsshr(form.lanes, v0, v1, @intCast(@min(count, width)))),
                .left_bytes => if (count >= 16) try self.emit(a64.vmoviZero(v0)) else {
                    try self.emit(a64.vmoviZero(v7));
                    try self.emit(a64.vext(v0, v7, v1, @intCast(16 - count)));
                },
                .right_bytes => if (count >= 16) try self.emit(a64.vmoviZero(v0)) else {
                    try self.emit(a64.vmoviZero(v7));
                    try self.emit(a64.vext(v0, v1, v7, @intCast(count)));
                },
            }
            try self.storeXmm(dst, v0);
            try self.clearUpper(dst, d.op);
            if (touchesMemory(d)) try self.emitAbortCheck(index);
            return true;
        }
        if (extendForm(d.op)) |form| {
            try self.loadUnarySource(insn, index, v0);
            var lanes = form.source;
            for (0..form.steps) |_| {
                try self.emit(if (form.signed) a64.vsxtl(lanes, v0, v0) else a64.vuxtl(lanes, v0, v0));
                lanes = @enumFromInt(@intFromEnum(lanes) + 1);
            }
            try self.storeXmm(dst, v0);
            try self.clearUpper(dst, d.op);
            if (touchesMemory(d)) try self.emitAbortCheck(index);
            return true;
        }
        switch (d.op) {
            .vmovdqu_xmm_xmm, .vmovdqa_xmm_xmm, .vmovups_xmm_xmm, .vmovaps_xmm_xmm, .vmovupd_xmm_xmm, .vmovapd_xmm_xmm => {
                try self.loadXmm(v0, d.xmm_src);
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
            },
            .vpmuludq => {
                // `multiplyUnsignedEvenDwords`: the low dword of each qword
                // of each source, as a 64-bit unsigned product. `uzp1`
                // gathers the even dwords into the low half for `umull`.
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v1, d.xmm_src);
                try self.emit(a64.vuzp1(.s4, v1, v1, v1));
                try self.emit(a64.vuzp1(.s4, v2, v2, v2));
                try self.emit(a64.vumull(v0, v1, v2));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vpblendw => {
                // `blendPackedWords`: word i from SRC2 when bit i is set.
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v0, d.xmm_src);
                for (0..8) |lane| {
                    if ((d.imm >> @intCast(lane)) & 1 != 0) try self.emit(a64.vinsLane(.h8, v0, @intCast(lane), v2, @intCast(lane)));
                }
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vshufpd => {
                // `shufflePackedDoublesLane`: element 0 is SRC1[bit 0],
                // element 1 is SRC2[bit 1] - a bit picks an element, never
                // a source.
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v1, d.xmm_src);
                try self.emit(a64.vinsLane(.d2, v0, 0, v1, @intCast(d.imm & 1)));
                try self.emit(a64.vinsLane(.d2, v0, 1, v2, @intCast((d.imm >> 1) & 1)));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vinsertps => {
                // `executeVinsertps`: SRC1 with one dword replaced - SRC2's
                // lane imm[7:6], or the 32-bit memory operand - at lane
                // imm[5:4], then the lanes in imm[3:0] zeroed. The memory
                // read comes first: helpers keep no vector register.
                const source_lane: u32 = if (d.is_reg_form) @intCast((d.imm >> 6) & 3) else 0;
                if (d.is_reg_form) {
                    try self.loadXmm(v2, d.xmm_src2);
                } else {
                    try self.emitLoadOperand(insn, .bits32, index);
                    try self.emit(a64.fmovSFromW(v2, 0));
                }
                try self.loadXmm(v0, d.xmm_src);
                try self.emit(a64.vinsLane(.s4, v0, @intCast((d.imm >> 4) & 3), v2, source_lane));
                if (d.imm & 0xF != 0) {
                    try self.emit(a64.vmovi8(v3, 0));
                    for (0..4) |lane| {
                        if ((d.imm >> @intCast(lane)) & 1 != 0) try self.emit(a64.vinsLane(.s4, v0, @intCast(lane), v3, 0));
                    }
                }
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vmovdqu_xmm_mem, .vmovdqa_xmm_mem, .vmovups_xmm_mem, .vmovaps_xmm_mem, .vmovupd_xmm_mem, .vmovapd_xmm_mem => {
                try self.emitLoadVec(insn, index, v0);
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                try self.emitAbortCheck(index);
            },
            .vmovdqu_mem_xmm, .vmovdqa_mem_xmm, .vmovups_mem_xmm, .vmovaps_mem_xmm, .vmovupd_mem_xmm, .vmovapd_mem_xmm, .vmovntps, .vmovntdq => {
                try self.loadXmm(v0, d.xmm_src);
                try self.emitStoreVec(insn, index, v0);
                try self.emitAbortCheck(index);
            },
            .vmovd_xmm_reg32, .vmovq_xmm_reg64 => {
                try self.loadReg(0, d.src_reg, false, if (d.op == .vmovd_xmm_reg32) .bits32 else .bits64);
                try self.emit(if (d.op == .vmovd_xmm_reg32) a64.fmovSFromW(v0, 0) else a64.fmovFromGpr(v0, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
            },
            .vmovd_xmm_mem32, .vmovq_xmm_mem64, .vmovss_xmm_mem, .vmovsd_xmm_mem => {
                const wide = d.op == .vmovq_xmm_mem64 or d.op == .vmovsd_xmm_mem;
                try self.emitLoadOperand(insn, if (wide) .bits64 else .bits32, index);
                try self.emit(if (wide) a64.fmovFromGpr(v0, 0) else a64.fmovSFromW(v0, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                try self.emitAbortCheck(index);
            },
            .vmovd_reg32_xmm, .vmovq_reg64_xmm => {
                try self.loadXmm(v1, d.xmm_src);
                const wide = d.op == .vmovq_reg64_xmm;
                try self.emit(if (wide) a64.vumov(.d2, 0, v1, 0) else a64.vumov(.s4, 0, v1, 0));
                try self.storeReg(d.dst_reg, false, if (wide) .bits64 else .bits32, 0);
            },
            .vmovd_mem32_xmm, .vmovq_mem64_xmm, .vmovss_mem_xmm, .vmovsd_mem_xmm => {
                const wide = d.op == .vmovq_mem64_xmm or d.op == .vmovsd_mem_xmm;
                try self.loadXmm(v1, d.xmm_src);
                try self.emit(if (wide) a64.vumov(.d2, 3, v1, 0) else a64.vumov(.s4, 3, v1, 0));
                try self.emitEffectiveAddress(1, insn);
                try self.emitWrite(if (wide) .bits64 else .bits32, index);
                try self.emitAbortCheck(index);
            },
            .vmovq_xmm_xmm => {
                try self.loadXmm(v1, d.xmm_src);
                try self.emit(a64.vmoviZero(v0));
                try self.emit(a64.vinsLane(.d2, v0, 0, v1, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
            },
            .vmovss_xmm_xmm_xmm, .vmovsd_xmm_xmm_xmm => {
                try self.loadXmm(v2, d.xmm_src2);
                try self.loadXmm(v0, d.xmm_src);
                try self.emit(if (d.op == .vmovss_xmm_xmm_xmm) a64.vinsLane(.s4, v0, 0, v2, 0) else a64.vinsLane(.d2, v0, 0, v2, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
            },
            .vmovlps_xmm_xmm_mem64, .vmovlpd_xmm_xmm_mem64, .vmovhps_xmm_xmm_mem64, .vmovhpd_xmm_xmm_mem64 => {
                const high = d.op == .vmovhps_xmm_xmm_mem64 or d.op == .vmovhpd_xmm_xmm_mem64;
                try self.emitLoadOperand(insn, .bits64, index);
                try self.loadXmm(v0, d.xmm_src);
                try self.emit(a64.vinsGpr(.d2, v0, if (high) 1 else 0, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                try self.emitAbortCheck(index);
            },
            .vmovlps_mem64_xmm, .vmovlpd_mem64_xmm, .vmovhps_mem64_xmm, .vmovhpd_mem64_xmm => {
                const high = d.op == .vmovhps_mem64_xmm or d.op == .vmovhpd_mem64_xmm;
                try self.loadXmm(v1, d.xmm_src);
                try self.emit(a64.vumov(.d2, 3, v1, if (high) 1 else 0));
                try self.emitEffectiveAddress(1, insn);
                try self.emitWrite(.bits64, index);
                try self.emitAbortCheck(index);
            },
            .vmovhlps, .vmovlhps => {
                // VEX: the low quadword from SRC2's high half (hlps) or the
                // high quadword from SRC2's low half (lhps), the rest from SRC1.
                try self.loadXmm(v0, d.xmm_src);
                try self.loadXmm(v2, d.xmm_src2);
                try self.emit(if (d.op == .vmovhlps) a64.vinsLane(.d2, v0, 0, v2, 1) else a64.vinsLane(.d2, v0, 1, v2, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
            },
            .vmovddup, .vmovsldup, .vmovshdup => {
                try self.loadUnarySource(insn, index, v1);
                switch (d.op) {
                    .vmovddup => try self.emit(a64.vdupLane(.d2, v0, v1, 0)),
                    .vmovsldup => try self.emit(a64.vtrn1(.s4, v0, v1, v1)),
                    else => try self.emit(a64.vtrn2(.s4, v0, v1, v1)),
                }
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vpshufb => {
                // `shuffleBytes`: a selector with bit 7 set gives zero, else
                // the byte at selector & 15. After masking with 0x8F, the
                // former are indices of 128 and up, which `tbl` maps to zero.
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v1, d.xmm_src);
                try self.emit(a64.vmovi8(v3, 0x8F));
                try self.emit(a64.vand(v2, v2, v3));
                try self.emit(a64.vtbl(v0, v1, v2));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vpshufd => {
                try self.loadUnarySource(insn, index, v1);
                for (0..4) |lane| {
                    const selected: u32 = @intCast((d.imm >> @intCast(lane * 2)) & 3);
                    try self.emit(a64.vinsLane(.s4, v0, @intCast(lane), v1, selected));
                }
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vshufps => {
                // Lanes 0 and 1 from SRC1, 2 and 3 from SRC2, each selected
                // by two control bits.
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v1, d.xmm_src);
                for (0..4) |lane| {
                    const selected: u32 = @intCast((d.imm >> @intCast(lane * 2)) & 3);
                    try self.emit(a64.vinsLane(.s4, v0, @intCast(lane), if (lane < 2) v1 else v2, selected));
                }
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vpackssdw, .vpacksswb, .vpackuswb, .vpackusdw => {
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v1, d.xmm_src);
                switch (d.op) {
                    .vpacksswb => {
                        try self.emit(a64.vsqxtn(.b16, false, v0, v1));
                        try self.emit(a64.vsqxtn(.b16, true, v0, v2));
                    },
                    .vpackuswb => {
                        try self.emit(a64.vsqxtun(.b16, false, v0, v1));
                        try self.emit(a64.vsqxtun(.b16, true, v0, v2));
                    },
                    .vpackssdw => {
                        try self.emit(a64.vsqxtn(.h8, false, v0, v1));
                        try self.emit(a64.vsqxtn(.h8, true, v0, v2));
                    },
                    else => {
                        try self.emit(a64.vsqxtun(.h8, false, v0, v1));
                        try self.emit(a64.vsqxtun(.h8, true, v0, v2));
                    },
                }
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vpabsb, .vpabsw, .vpabsd => {
                try self.loadUnarySource(insn, index, v1);
                const lanes: a64.Lanes = switch (d.op) {
                    .vpabsb => .b16,
                    .vpabsw => .h8,
                    else => .s4,
                };
                try self.emit(a64.vabs(lanes, v0, v1));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vpextrb, .vpextrw, .vpextrd, .vpextrq => {
                const lanes: a64.Lanes = switch (d.op) {
                    .vpextrb => .b16,
                    .vpextrw => .h8,
                    .vpextrd => .s4,
                    else => .d2,
                };
                const lane: u32 = @intCast(d.imm & (@as(u64, 16) / (lanes.elementBits() / 8) - 1));
                try self.loadXmm(v1, d.xmm_src);
                if (d.is_reg_form) {
                    try self.emit(a64.vumov(lanes, 0, v1, lane));
                    try self.storeReg(d.dst_reg, false, if (d.op == .vpextrq) .bits64 else .bits32, 0);
                } else {
                    try self.emit(a64.vumov(lanes, 3, v1, lane));
                    try self.emitEffectiveAddress(1, insn);
                    try self.emitWrite(d.size, index);
                    try self.emitAbortCheck(index);
                }
            },
            .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8, .vpinsrw, .vpinsrd, .vpinsrq => {
                const lanes: a64.Lanes = switch (d.op) {
                    .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8 => .b16,
                    .vpinsrw => .h8,
                    .vpinsrd => .s4,
                    else => .d2,
                };
                const lane: u32 = @intCast(d.imm & (@as(u64, 16) / (lanes.elementBits() / 8) - 1));
                if (d.is_reg_form) {
                    try self.loadReg(0, d.src_reg, false, if (d.op == .vpinsrq) .bits64 else .bits32);
                } else {
                    try self.emitLoadOperand(insn, d.size, index);
                }
                try self.loadXmm(v0, d.xmm_src);
                try self.emit(a64.vinsGpr(lanes, v0, lane, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (!d.is_reg_form) try self.emitAbortCheck(index);
            },
            .vpalignr => {
                // `executeVpalignr`: bytes shift.. of first (xmm_src, low)
                // then second (rm, high); 32 and beyond is zero.
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v1, d.xmm_src);
                const shift: u64 = @min(d.imm & 0xFF, 32);
                if (shift >= 32) {
                    try self.emit(a64.vmoviZero(v0));
                } else if (shift >= 16) {
                    try self.emit(a64.vmoviZero(v7));
                    try self.emit(a64.vext(v0, v2, v7, @intCast(shift - 16)));
                } else if (shift == 0) {
                    try self.emit(a64.vmov(v0, v1));
                } else {
                    try self.emit(a64.vext(v0, v1, v2, @intCast(shift)));
                }
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vblendps, .vblendpd => {
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v0, d.xmm_src);
                const lanes: a64.Lanes = if (d.op == .vblendps) .s4 else .d2;
                const count: u32 = if (d.op == .vblendps) 4 else 2;
                for (0..count) |lane| {
                    if ((d.imm >> @intCast(lane)) & 1 != 0) try self.emit(a64.vinsLane(lanes, v0, @intCast(lane), v2, @intCast(lane)));
                }
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vblendvps, .vblendvpd, .vpblendvb => {
                // `blendPackedElements`: the mask lane's sign bit selects
                // the second source.
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v1, d.xmm_src);
                try self.loadXmm(v3, d.xmm_mask);
                switch (d.op) {
                    .vblendvps => try self.emit(a64.vsshr(.s4, v3, v3, 31)),
                    .vblendvpd => try self.emit(a64.vsshr(.d2, v3, v3, 63)),
                    else => try self.emit(a64.vsshr(.b16, v3, v3, 7)),
                }
                try self.emit(a64.vbsl(v3, v2, v1));
                try self.storeXmm(dst, v3);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vbroadcastss, .vpbroadcastw, .vpbroadcastd, .vpbroadcastq => {
                const lanes: a64.Lanes = switch (d.op) {
                    .vpbroadcastw => .h8,
                    .vpbroadcastq => .d2,
                    else => .s4,
                };
                if (d.is_reg_form) {
                    try self.loadXmm(v1, d.xmm_src);
                    try self.emit(a64.vdupLane(lanes, v0, v1, 0));
                } else {
                    const size: Size = switch (lanes) {
                        .h8 => .bits16,
                        .d2 => .bits64,
                        else => .bits32,
                    };
                    try self.emitLoadOperand(insn, size, index);
                    try self.emit(a64.vdupGpr(lanes, v0, 0));
                }
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (!d.is_reg_form) try self.emitAbortCheck(index);
            },
            .vsqrtps, .vsqrtpd => {
                try self.loadSource2(insn, index, v2);
                try self.emit(a64.vfsqrt(if (d.op == .vsqrtps) .s4 else .d2, v0, v2));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vrcpps, .vrsqrtps => {
                // Exact, as `approximateReciprocal` computes it: 1 / x and
                // 1 / sqrt(x) in single precision.
                try self.loadSource2(insn, index, v2);
                try self.emit(a64.vfmovOne(v3));
                if (d.op == .vrsqrtps) {
                    try self.emit(a64.vfsqrt(.s4, v2, v2));
                }
                try self.emit(a64.vfdiv(.s4, v0, v3, v2));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vsqrtss, .vsqrtsd => {
                const fp: a64.FpWidth = if (d.op == .vsqrtss) .single else .double;
                try self.loadScalarSource2(insn, index, fp, v2);
                try self.loadXmm(v0, d.xmm_src);
                try self.emit(a64.fsqrt(fp, v3, v2));
                try self.emit(a64.vinsLane(if (fp == .single) .s4 else .d2, v0, 0, v3, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vcvtss2sd, .vcvtsd2ss => {
                const from_single = d.op == .vcvtss2sd;
                try self.loadScalarSource2(insn, index, if (from_single) .single else .double, v2);
                try self.loadXmm(v0, d.xmm_src);
                try self.emit(if (from_single) a64.fcvtDouble(v3, v2) else a64.fcvtSingle(v3, v2));
                try self.emit(if (from_single) a64.vinsLane(.d2, v0, 0, v3, 0) else a64.vinsLane(.s4, v0, 0, v3, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vcvtps2pd, .vcvtpd2ps => {
                try self.loadSource2(insn, index, v2);
                try self.emit(if (d.op == .vcvtps2pd) a64.vfcvtl(v0, v2) else a64.vfcvtn(v0, v2));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vcvtdq2ps => {
                try self.loadSource2(insn, index, v2);
                try self.emit(a64.vscvtf(.s4, v0, v2));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vcvttps2dq, .vcvtps2dq => {
                try self.loadSource2(insn, index, v2);
                try self.emitPackedFloatToDword(d.op == .vcvttps2dq);
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vcvtsi2ss_xmm_reg, .vcvtsi2sd_xmm_reg, .vcvtsi2ss_xmm_mem, .vcvtsi2sd_xmm_mem => {
                const fp: a64.FpWidth = if (d.op == .vcvtsi2ss_xmm_reg or d.op == .vcvtsi2ss_xmm_mem) .single else .double;
                const from_64 = d.size == .bits64;
                if (d.is_reg_form or d.op == .vcvtsi2ss_xmm_reg or d.op == .vcvtsi2sd_xmm_reg) {
                    try self.loadReg(0, d.src_reg, false, d.size);
                } else {
                    try self.emitLoadOperand(insn, d.size, index);
                }
                try self.loadXmm(v0, d.xmm_src);
                try self.emit(a64.scvtfScalar(fp, from_64, v3, 0));
                try self.emit(a64.vinsLane(if (fp == .single) .s4 else .d2, v0, 0, v3, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (d.op == .vcvtsi2ss_xmm_mem or d.op == .vcvtsi2sd_xmm_mem) try self.emitAbortCheck(index);
            },
            .vcvttss2si, .vcvttsd2si, .vcvtss2si, .vcvtsd2si => {
                const fp: a64.FpWidth = if (d.op == .vcvttss2si or d.op == .vcvtss2si) .single else .double;
                const truncate = d.op == .vcvttss2si or d.op == .vcvttsd2si;
                // The source is xmm_src (register) or memory.
                if (d.is_reg_form) {
                    try self.loadXmm(v2, d.xmm_src);
                } else {
                    try self.emitLoadOperand(insn, if (fp == .single) .bits32 else .bits64, index);
                    try self.emit(if (fp == .single) a64.fmovSFromW(v2, 0) else a64.fmovFromGpr(v2, 0));
                }
                try self.emitScalarFloatToInt(fp, d.size == .bits64, truncate);
                try self.storeReg(d.dst_reg, false, d.size, 0);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vucomiss, .vucomisd => {
                const fp: a64.FpWidth = if (d.op == .vucomiss) .single else .double;
                try self.loadScalarSource2(insn, index, fp, v2);
                try self.loadXmm(v1, d.xmm_src);
                try self.emitCompareFlags(fp);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vcmpps, .vcmppd => {
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v1, d.xmm_src);
                try self.emitFloatCompareMask(if (d.op == .vcmpps) .s4 else .d2, v0, @truncate(d.imm));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vroundps, .vroundpd => {
                // `roundVexFloat` returns NaN and infinity unchanged (an
                // SNaN stays signalling), so the rounded lanes are selected
                // only where the source is ordered.
                try self.loadSource2(insn, index, v2);
                const lanes: a64.FpLanes = if (d.op == .vroundps) .s4 else .d2;
                try self.emit(a64.vfrint(roundModeOf(d.imm), lanes, v3, v2));
                try self.emit(a64.vfcmeq(lanes, v0, v2, v2));
                try self.emit(a64.vbsl(v0, v3, v2));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vroundss, .vroundsd => {
                const fp: a64.FpWidth = if (d.op == .vroundss) .single else .double;
                try self.loadScalarSource2(insn, index, fp, v2);
                try self.loadXmm(v0, d.xmm_src);
                try self.emit(a64.frintScalar(roundModeOf(d.imm), fp, v3, v2));
                try self.emit(a64.fcmp(fp, v2, v2));
                try self.emit(a64.fcsel(fp, v3, v2, v3, .vs));
                try self.emit(a64.vinsLane(if (fp == .single) .s4 else .d2, v0, 0, v3, 0));
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            },
            .vzeroupper => {
                try self.emit(a64.vmoviZero(v7));
                try self.emitStateAddress(t0, self.layout.ymm_hi_offset);
                for (0..32) |register| {
                    try self.emitChecked(a64.vstrQ(v7, t0, xmmOffset(@intCast(register))));
                }
            },
            else => return false,
        }
        return true;
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

    const wants = try allocator.alloc(bool, insns.len);
    defer allocator.free(wants);
    const live = try allocator.alloc(u8, insns.len);
    defer allocator.free(live);
    const elided = flagLiveness(insns, wants, live);
    const live_block = try allocator.alloc(u8, insns.len);
    defer allocator.free(live_block);
    const block_wants = try allocator.alloc(bool, insns.len);
    defer allocator.free(block_wants);
    _ = flagLivenessFrom(insns, block_wants, live_block, 0);

    // Two passes over the same instructions. The first emits into a scratch
    // assembler only to count how often each guest register is touched -
    // every access goes through `loadReg`/`storeReg`, including the implicit
    // ones (rsp for a push, rdx for a divide), so counting there is exact
    // where a scan of the decoded operands would not be. The second pass
    // caches the busiest of them in host registers and emits for real.
    var counts: [16]u32 = @splat(0);
    {
        var scratch_assembler = Assembler.init(allocator);
        defer scratch_assembler.deinit();
        var counting = try emitBlock(allocator, &scratch_assembler, layout, insns, end_rip, wants, live, live_block, null);
        defer counting.compiler.exits.deinit(allocator);
        defer counting.compiler.cold_accesses.deinit(allocator);
        counts = counting.compiler.use_counts;
    }

    var assembler = Assembler.init(allocator);
    defer assembler.deinit();
    var pass = try emitBlock(allocator, &assembler, layout, insns, end_rip, wants, live, live_block, counts);
    defer pass.compiler.exits.deinit(allocator);
    defer pass.compiler.cold_accesses.deinit(allocator);
    const words = try assembler.finish();

    const code = try memory.reserve(words.len);
    memory.beginWrite();
    @memcpy(code, words);
    memory.endWrite(code);
    return .{
        .code = code,
        .chain_entry = pass.chain_entry_bytes,
        .native_count = pass.compiler.native_count,
        .fallback_count = pass.compiler.fallback_count,
        .register_only = !pass.compiler.touches_memory and !pass.compiler.touches_vectors and pass.compiler.fallback_count == 0,
        .flags_elided = elided,
        .flags_narrowed = pass.compiler.flags_narrowed,
        .cached_registers = pass.compiler.cache_count,
        .hoisted_accesses = pass.compiler.hoisted_accesses,
    };
}

const EmittedBlock = struct {
    compiler: Compiler,
    chain_entry_bytes: u32,
};

/// Emit one whole block into `assembler`. With `cache_counts`, the busiest
/// guest registers those counts name are held in host registers throughout.
fn emitBlock(
    allocator: std.mem.Allocator,
    assembler: *Assembler,
    layout: Layout,
    insns: []const Insn,
    end_rip: u64,
    wants: []const bool,
    live: []const u8,
    live_block: []const u8,
    cache_counts: ?[16]u32,
) Error!EmittedBlock {
    var compiler = Compiler{
        .a = assembler,
        .layout = layout,
        .insns = insns,
        .end_rip = end_rip,
        .epilogue = try assembler.createLabel(),
        .exit_path = try assembler.createLabel(),
        .epilogue_path = try assembler.createLabel(),
        .exits = .empty,
        .allocator = allocator,
        .flag_wants = wants,
        .flag_live = live,
        .flag_live_block = live_block,
    };
    errdefer compiler.exits.deinit(allocator);
    errdefer compiler.cold_accesses.deinit(allocator);
    if (cache_counts) |counts| compiler.chooseCache(counts);
    compiler.planHoist();

    try compiler.emitPrologue();
    // Where a chained block enters: the frame is already established and
    // every cached pointer but `helpers` is already right. The guest
    // register cache is loaded *after* this point, because a chained block
    // has to load its own cache just as an entered one does.
    const chain_entry_bytes: u32 = @intCast(assembler.words.items.len * @sizeOf(u32));
    try compiler.emitCacheLoad();
    var terminated = false;
    for (insns, 0..) |insn, index| {
        const emitted = try compiler.emitInsn(@intCast(index));
        const op = insn.decoded.op;
        if (isTerminator(op) or isFallbackTerminator(op)) {
            if (emitted == .fallback) {
                // The interpreter either transferred control (the fallback
                // returned nonzero and the block already left) or a shim
                // consumed the transfer and left RIP at the next
                // instruction, which is where this block ends.
                const stub = try compiler.exitStub(@intCast(index + 1), insn.rip +% insn.len);
                try assembler.branch(stub);
                terminated = true;
                break;
            }
            // A conditional branch the glue kept in the middle of a trace
            // falls through to the next instruction; anything else, and a
            // conditional that is the last instruction, ends the block.
            if (!isConditionalBranch(op) or index + 1 == insns.len) {
                terminated = true;
                break;
            }
        }
    }
    if (!terminated) {
        const stub = try compiler.exitStub(@intCast(insns.len), end_rip);
        try assembler.branch(stub);
    }
    try compiler.emitColdAccesses();
    try compiler.emitExitStubs();
    try compiler.emitChainAttempt();
    try compiler.emitFlagCompletion();
    try compiler.emitEpilogue();
    return .{ .compiler = compiler, .chain_entry_bytes = chain_entry_bytes };
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
    tlb: Tlb = Tlb.empty,
    xmm: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    ymm_hi: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    zmm_hi: [32][32]u8 = [_][32]u8{[_]u8{0} ** 32} ** 32,
    reads: u32 = 0,
    writes: u32 = 0,
    interprets: u32 = 0,
    flag_completions: u32 = 0,
    last_interpret_index: u32 = 0,
    last_helper_index: u32 = 0,
    interpret_result: u32 = 0,
    /// The flags the interpret helper saw, so a test can prove the writer
    /// before a fallback still materialised them.
    flags_at_interpret: u32 = 0,
    abort_on_access: bool = false,
    /// The two pieces of state the native transfer templates read before
    /// they will run, standing in for the glue's own fields.
    trace_calls: bool = false,
    trace_transfers: bool = false,
    return_captures: u32 = 0,
    image_low: u64 = 0,
    image_high: u64 = 0,
    iat_low: u64 = 0,
    iat_high: u64 = 0,
    hook_filter: [hook_filter_bytes]u8 = @splat(0),
    image_targets_hooked: u8 = 1,
    memory: [4096]u8 = [_]u8{0} ** 4096,

    const layout = Layout{
        .regs_offset = @offsetOf(TestState, "regs"),
        .scratch_offset = @offsetOf(TestState, "scratch"),
        .tlb_offset = @offsetOf(TestState, "tlb"),
        .xmm_offset = @offsetOf(TestState, "xmm"),
        .ymm_hi_offset = @offsetOf(TestState, "ymm_hi"),
        .zmm_hi_offset = @offsetOf(TestState, "zmm_hi"),
        .trace_calls_offset = @offsetOf(TestState, "trace_calls"),
        .return_captures_offset = @offsetOf(TestState, "return_captures"),
        .trace_transfers_offset = @offsetOf(TestState, "trace_transfers"),
        .image_low_offset = @offsetOf(TestState, "image_low"),
        .image_high_offset = @offsetOf(TestState, "image_high"),
        .iat_low_offset = @offsetOf(TestState, "iat_low"),
        .iat_high_offset = @offsetOf(TestState, "iat_high"),
        .hook_filter_offset = @offsetOf(TestState, "hook_filter"),
        .image_targets_hooked_offset = @offsetOf(TestState, "image_targets_hooked"),
    };

    fn read(state_ptr: *anyopaque, address: u64, size: u8) callconv(.c) u64 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.reads += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) state.scratch.abort = 1;
        const width: usize = @as(usize, 1) << @intCast(size);
        if (address +| width > state.memory.len) return 0;
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
        if (address +| width > state.memory.len) return;
        for (0..width) |i| state.memory[@intCast(address + i)] = @truncate(value >> @intCast(i * 8));
    }

    fn read128(state_ptr: *anyopaque, address: u64, out: *[16]u8) callconv(.c) void {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.reads += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) state.scratch.abort = 1;
        out.* = @splat(0);
        if (address +| 16 > state.memory.len) return;
        @memcpy(out, state.memory[@intCast(address)..][0..16]);
    }

    fn write128(state_ptr: *anyopaque, address: u64, value: *const [16]u8) callconv(.c) void {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.writes += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) state.scratch.abort = 1;
        if (address +| 16 > state.memory.len) return;
        @memcpy(state.memory[@intCast(address)..][0..16], value);
    }

    /// Settle the deferred flag record exactly as the glue's helper does,
    /// so a test sees the flags the interpreter would have seen.
    fn flags(state_ptr: *anyopaque) callconv(.c) void {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        if (state.scratch.flag_kind == 0) return;
        state.flag_completions += 1;
        const size: Size = @enumFromInt(state.scratch.flag_size);
        switch (state.scratch.flag_kind) {
            @intFromEnum(FlagKind.add) => x64_decoder.applyAdd(&state.regs.rflags, state.scratch.flag_a, state.scratch.flag_b, state.scratch.flag_r, size),
            @intFromEnum(FlagKind.sub) => x64_decoder.applySub(&state.regs.rflags, state.scratch.flag_a, state.scratch.flag_b, state.scratch.flag_r, size),
            @intFromEnum(FlagKind.logic) => x64_decoder.applyLogic(&state.regs.rflags, state.scratch.flag_r, size),
            else => {},
        }
        state.scratch.flag_kind = 0;
    }

    fn interpret(state_ptr: *anyopaque, block: *const Block, index: u32) callconv(.c) u32 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        flags(state_ptr);
        state.interprets += 1;
        state.last_interpret_index = index;
        state.flags_at_interpret = state.regs.rflags;
        // The scratch index must agree with the argument.
        if (state.scratch.index != index) state.regs.r15 = 0xBAD_1DE7;
        // Pretend the instruction advanced RIP by its length, as `execute`
        // would for a non-branch.
        const insn = block.insns[index];
        state.regs.rip = insn.rip + insn.len;
        return state.interpret_result;
    }

    /// Admit the whole test memory (guest page 0) to the TLB.
    fn admitMemory(self: *TestState, reads: bool, writes: bool) void {
        if (reads) self.tlb.fill(false, 0, &self.memory);
        if (writes) self.tlb.fill(true, 0, &self.memory);
    }
};

const TestHarness = struct {
    memory: CodeMemory,
    block: Block,
    insns: std.ArrayList(Insn),
    flags_elided: u32 = 0,

    fn init() !TestHarness {
        if (!CodeMemory.available()) return error.SkipZigTest;
        return .{
            .memory = try CodeMemory.init(8 * 1024 * 1024),
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
        self.flags_elided = compiled.flags_elided;
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
            .read128 = TestState.read128,
            .write128 = TestState.write128,
            .interpret = TestState.interpret,
            .block = &self.block,
            .flags = TestState.flags,
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

/// A memory operand `[rbx + disp]`.
fn baseDisp(op: Op, size: Size, reg: RegId, disp: u64) DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = reg, .src_reg = reg, .addr = disp, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx };
}

fn baseDispAt(op: Op, size: Size, base: RegId, disp: u64) DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = base, .src_reg = base, .addr = disp, .sib_has_base = true, .sib_base_reg = base };
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
        .adc, .sbb => unreachable,
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

test "locked exchange, compare-exchange and exchange-add are single host atomics with the interpreter's results" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 5, .little);

    // lock cmpxchg [rbx + 0x20], rcx with rax == [mem]: stored, ZF set.
    state.regs.rax = 5;
    state.regs.rcx = 0x77;
    var cas = baseDisp(.cmpxchg_mem64_reg64, .bits64, .cl_cx_ecx_rcx, 0x20);
    cas.lock = true;
    try h.add(0x1000, 5, cas);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x77), std.mem.readInt(u64, state.memory[0x120..][0..8], .little));
    try testing.expectEqual(@as(u64, 5), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);

    // Again: now rax (5) != [mem] (0x77), so nothing is stored, rax takes
    // the old value, ZF is clear and CF is the borrow of 5 - 0x77.
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x77), std.mem.readInt(u64, state.memory[0x120..][0..8], .little));
    try testing.expectEqual(@as(u64, 0x77), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);

    // xchg [rbx + 0x20], edx: a 32-bit swap, zero-extending edx.
    h.insns.clearRetainingCapacity();
    state.regs.rdx = 0xFFFF_FFFF_0000_0009;
    try h.add(0x1000, 3, baseDisp(.xchg_mem32_reg32, .bits32, .dl_dx_edx_rdx, 0x20));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x77), state.regs.rdx);
    try testing.expectEqual(@as(u32, 9), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));

    // lock xadd [rbx + 0x20], esi: memory gets the sum, esi the old value.
    h.insns.clearRetainingCapacity();
    state.regs.rsi = 3;
    var xadd = baseDisp(.xadd_mem32_reg32, .bits32, .dh_si_esi_rsi, 0x20);
    xadd.lock = true;
    try h.add(0x1000, 4, xadd);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 12), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expectEqual(@as(u64, 9), state.regs.rsi);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // A misaligned address would fault as an LSE atomic: the interpreter
    // takes the whole instruction instead.
    h.insns.clearRetainingCapacity();
    state.regs.rbx = 0x101;
    try h.add(0x1000, 4, xadd);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.interprets);

    // Every other locked form is still the interpreter's.
    try testing.expect(!isNative(.{ .op = .add_mem32_reg32, .size = .bits32, .lock = true }));
}

test "bit tests on memory with an immediate, and narrow immediate shifts, are native" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    std.mem.writeInt(u32, state.memory[0x120..][0..4], 0x8000_0005, .little);
    state.regs.rbx = 0x100;
    state.regs.rflags = 0x2;
    // btr dword [rbx + 0x20], 31 ; bts dword [rbx + 0x20], 1
    var btr = baseDisp(.btr_mem_imm, .bits32, .al_ax_eax_rax, 0x20);
    btr.imm = 31;
    try h.add(0x1000, 5, btr);
    var bts = baseDisp(.bts_mem_imm, .bits32, .al_ax_eax_rax, 0x20);
    bts.imm = 1;
    try h.add(0x1005, 5, bts);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u32, 0x0000_0007), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    // CF is the bit `bts` found: bit 1 of 0x5 was clear.
    try testing.expect(state.regs.rflags & RFL_CF == 0);

    // bt only probes: CF from bit 2, memory untouched.
    h.insns.clearRetainingCapacity();
    var bt = baseDisp(.bt_mem_imm, .bits32, .al_ax_eax_rax, 0x20);
    bt.imm = 2;
    try h.add(0x1000, 5, bt);
    _ = try h.run(&state);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expectEqual(@as(u32, 0x0000_0007), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));

    // shr al, 3 leaves the rest of rax alone; CF is bit 2 of 0xF4.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x1234_56F4;
    try h.add(0x2000, 3, regImm(.shr_reg_imm, .bits8, .al_ax_eax_rax, 3));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x1234_561E), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF != 0);

    // sar bx, 4 brings the 16-bit sign down and sets SF; bit 3 of 0x8018 is
    // CF.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0xAAAA_8018;
    try h.add(0x2000, 4, regImm(.sar_reg_imm, .bits16, .bl_bx_ebx_rbx, 4));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0xAAAA_F801), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);

    // A count past the operand stays with the interpreter.
    try testing.expect(!isNative(regImm(.shl_reg_imm, .bits8, .al_ax_eax_rax, 9)));

    // shr ah, 4: the high byte, with AL left exactly as it was.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x1234_F0A5;
    var high = regImm(.shr_reg_imm, .bits8, .al_ax_eax_rax, 4);
    high.dst_high8 = true;
    try h.add(0x2000, 3, high);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x1234_0FA5), state.regs.rax);

    // rol ax, 8 is a 16-bit byte swap; CF is the low bit of the result.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x1111_2233;
    try h.add(0x2000, 4, regImm(.rol_reg_imm, .bits16, .al_ax_eax_rax, 8));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x1111_3322), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF == 0);

    // ror bl, 1 from 1: 0x80, CF = the new msb, OF = CF ^ bit 6.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0xFF01;
    try h.add(0x2000, 2, regImm(.ror_reg_imm, .bits8, .bl_bx_ebx_rbx, 1));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFF80), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
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

test "a condition keeps only the flags it reads live" {
    try testing.expectEqual(F_ZF, conditionReads(.e));
    try testing.expectEqual(F_ZF, conditionReads(.ne));
    try testing.expectEqual(F_CF, conditionReads(.b));
    try testing.expectEqual(F_CF | F_ZF, conditionReads(.be));
    try testing.expectEqual(F_SF | F_OF, conditionReads(.l));
    try testing.expectEqual(F_SF | F_OF | F_ZF, conditionReads(.le));
    try testing.expectEqual(F_PF, conditionReads(.p));
    try testing.expectEqual(F_OF, conditionReads(.o));
    // The flags-register bits a liveness mask keeps.
    try testing.expectEqual(RFL_ZF, liveFlagBits(F_ZF));
    try testing.expectEqual(RFL_CF | RFL_OF, liveFlagBits(F_CF | F_OF));
    try testing.expectEqual(RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF, liveFlagBits(F_ALL));
}

test "flag liveness narrows a compare to the conditions that consume it" {
    // The shape Xenia's PowerPC backend emits for a condition-register
    // update: one compare, a run of `setcc` reading it, and the next compare
    // killing what is left. Only the flags those conditions read have to be
    // computed, so the parity fold, the auxiliary carry and the carry are
    // skipped on the hottest instruction in the translated stream.
    var insns: [3]Insn = undefined;
    var cmp = regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx);
    cmp.len = 3;
    insns[0] = .{ .rip = 0x1000, .len = 3, .decoded = cmp, .segment = .ds };
    var set: DecodedInsn = .{ .op = .setcc_reg8, .size = .bits8, .dst_reg = .cl_cx_ecx_rcx, .cond = .ne, .is_reg_form = true };
    set.len = 3;
    insns[1] = .{ .rip = 0x1003, .len = 3, .decoded = set, .segment = .ds };
    var cmp2 = regReg(.cmp_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx);
    cmp2.len = 3;
    insns[2] = .{ .rip = 0x1006, .len = 3, .decoded = cmp2, .segment = .ds };

    var wants: [3]bool = undefined;
    var live: [3]u8 = undefined;
    _ = flagLiveness(&insns, &wants, &live);
    try testing.expect(wants[0]);
    try testing.expectEqual(F_ZF, live[0]);
    try testing.expectEqual(@as(u8, 0), live[1]);
    // The last flag writer in the block computes everything: the next block
    // or the interpreter may read any flag.
    try testing.expectEqual(F_ALL, live[2]);
}

test "a branch that ends a block keeps every flag live across it" {
    // `jcc` reads its condition but kills nothing, so flags stay live past
    // it, and the block ends there with all of them live-out. This is the
    // honest limit of per-flag liveness: a compare feeding only a terminating
    // branch still materialises all six. Lifting it needs lazy flags, not a
    // better liveness pass.
    var insns: [2]Insn = undefined;
    var cmp = regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx);
    cmp.len = 3;
    insns[0] = .{ .rip = 0x1000, .len = 3, .decoded = cmp, .segment = .ds };
    var jcc: DecodedInsn = .{ .op = .jcc_rel8, .cond = .ne, .addr = 0x10 };
    jcc.len = 2;
    insns[1] = .{ .rip = 0x1003, .len = 2, .decoded = jcc, .segment = .ds };

    var wants: [2]bool = undefined;
    var live: [2]u8 = undefined;
    _ = flagLiveness(&insns, &wants, &live);
    try testing.expect(wants[0]);
    try testing.expectEqual(F_ALL, live[0]);
    try testing.expectEqual(F_ALL, live[1]);
}

test "flag liveness keeps a flag its writer does not kill" {
    // `and` leaves the auxiliary carry undefined, so it does not kill it and
    // the earlier `add` must still compute it.
    var insns: [2]Insn = undefined;
    var add_insn = regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx);
    add_insn.len = 3;
    insns[0] = .{ .rip = 0x2000, .len = 3, .decoded = add_insn, .segment = .ds };
    var and_insn = regReg(.and_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx);
    and_insn.len = 3;
    insns[1] = .{ .rip = 0x2003, .len = 3, .decoded = and_insn, .segment = .ds };

    var wants: [2]bool = undefined;
    var live: [2]u8 = undefined;
    _ = flagLiveness(&insns, &wants, &live);
    try testing.expectEqual(F_AF, live[0] & F_AF);
    try testing.expectEqual(F_ALL, live[1]);
}

test "setcc to memory and the fences are translated, not interpreted" {
    var h = try TestHarness.init();
    defer h.deinit();
    // `setcc [mem]` was 78% of every interpreter fallback the 2026-09-19
    // Halo 3 run made - 5.8 billion of 7.4 billion calls - because Xenia's
    // PowerPC backend writes each condition-register bit with one.
    const flag_values = [_]u32{ 0x2, RFL_CF, RFL_ZF, RFL_SF, RFL_OF, RFL_PF, RFL_SF | RFL_OF, RFL_ZF | RFL_CF, 0x8D5 };
    for (flag_values) |flags| {
        for (0..16) |cond_index| {
            const cond: Cond = @enumFromInt(cond_index);
            var state = TestState{};
            state.regs.rflags = flags;
            state.regs.rbx = 0x100;
            state.memory[0x140] = 0xA5;
            h.insns.clearRetainingCapacity();
            var set = baseDisp(.setcc_mem8, .bits8, .al_ax_eax_rax, 0x40);
            set.cond = cond;
            try h.add(0x7000, 7, set);
            try h.add(0x7007, 3, DecodedInsn{ .op = .mfence });
            const completed = try h.run(&state);
            try testing.expectEqual(@as(u32, 2), completed);
            const expected = x64_decoder.evalCond(flags, cond);
            try testing.expectEqual(@as(u8, @intFromBool(expected)), state.memory[0x140]);
            // One byte written, through the store helper, and nothing handed
            // to the interpreter.
            try testing.expectEqual(@as(u32, 1), state.writes);
            try testing.expectEqual(@as(u32, 0), state.interprets);
            try testing.expectEqual(@as(u64, 0x700A), state.regs.rip);
            // The condition is read, so the flags must survive the store.
            try testing.expectEqual(flags, state.regs.rflags);
        }
    }
}

test "setcc to memory writes exactly one byte and leaves its neighbours" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rflags = RFL_ZF;
    state.regs.rbx = 0x200;
    state.memory[0x20F] = 0x77;
    state.memory[0x210] = 0x55;
    state.memory[0x211] = 0x99;
    var set = baseDisp(.setcc_mem8, .bits8, .al_ax_eax_rax, 0x10);
    set.cond = .e;
    try h.add(0x8000, 7, set);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 1), state.memory[0x210]);
    try testing.expectEqual(@as(u8, 0x77), state.memory[0x20F]);
    try testing.expectEqual(@as(u8, 0x99), state.memory[0x211]);
    // A register-form setcc must not reach the memory template.
    var reg_form: DecodedInsn = .{ .op = .setcc_mem8, .size = .bits8, .dst_reg = .cl_cx_ecx_rcx, .cond = .e, .is_reg_form = true };
    reg_form.len = 3;
    try testing.expect(!isNative(reg_form));
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
    // add rax, rbx ; <unsupported: lahf> ; add rax, rbx
    try h.add(0xA000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0xA003, 3, .{ .op = .lahf, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
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
    try h.add(0xB000, 3, .{ .op = .lahf, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    var state = TestState{};
    try testing.expectError(Error.NothingToCompile, h.run(&state));
    // A lone control transfer is refused when the transfer itself is a
    // helper call: the block would buy no native work at all.
    h.insns.clearRetainingCapacity();
    // `call [rip + slot]` is an import-table call the dynamic-function shim
    // owns, so it is always the interpreter's.
    try h.add(0xB000, 6, .{ .op = .call_mem64, .rip_relative = true });
    try testing.expectError(Error.NothingToCompile, h.run(&state));
    // A lone `ret` is not one of those any more. It compiles to a guarded
    // pop into RIP, which is worth a block on its own: the alternative is a
    // full interpreter step, whose hook gates, hotness probe and decode
    // cache lookup cost more than this block's prologue and epilogue.
    h.insns.clearRetainingCapacity();
    try h.add(0xB000, 1, .{ .op = .ret });
    state.admitMemory(true, true);
    state.regs.rsp = 0x200;
    std.mem.writeInt(u64, state.memory[0x200..][0..8], 0xFEED, .little);
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u64, 0xFEED), state.regs.rip);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "the block boundary rules: host-reaching instructions end a block before themselves, control transfers end it as fallbacks" {
    try testing.expect(endsBlockBefore(.{ .op = .syscall }));
    try testing.expect(endsBlockBefore(.{ .op = .hlt }));
    try testing.expect(endsBlockBefore(.{ .op = .cpuid }));
    try testing.expect(endsBlockBefore(.{ .op = .nop, .len = 2 }));
    try testing.expect(!endsBlockBefore(.{ .op = .nop, .len = 1 }));
    try testing.expect(!endsBlockBefore(.{ .op = .call_rel32 }));
    try testing.expect(!endsBlockBefore(.{ .op = .ret }));
    try testing.expect(isFallbackTerminator(.call_rel32) and isFallbackTerminator(.ret) and isFallbackTerminator(.jmp_reg64) and isFallbackTerminator(.call_mem64) and isFallbackTerminator(.loop));
    try testing.expect(!isFallbackTerminator(.jcc_rel8) and !isFallbackTerminator(.add_reg64_reg64));
    try testing.expect(isTerminator(.jcc_rel32) and isTerminator(.jmp_rel8) and !isTerminator(.call_rel32));
    try testing.expect(!isNative(.{ .op = .add_reg64_reg64, .lock = true }));
    // A narrow shift is native while its count stays inside the operand.
    try testing.expect(isNative(.{ .op = .shl_reg_imm, .size = .bits16 }));
    try testing.expect(!isNative(.{ .op = .shl_reg_imm, .size = .bits16, .imm = 16 }));
    try testing.expect(isNative(.{ .op = .shl_reg_imm, .size = .bits32 }));
    try testing.expect(isNative(.{ .op = .shl_reg_cl, .size = .bits64 }));
    try testing.expect(isNative(.{ .op = .add_mem32_reg32, .size = .bits32 }));
    try testing.expect(isNative(.{ .op = .movbe_reg_mem, .size = .bits32 }));
    try testing.expect(!isNative(.{ .op = .movbe_reg_mem, .size = .bits8 }));
    // A direct call is native as far as this predicate is concerned; the
    // glue decides per call site, because whether the interpreter's arm has
    // a hook for it is a property of the target, not of the encoding.
    try testing.expect(isNative(.{ .op = .call_rel32 }));
    try testing.expect(isNative(.{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx }));
    try testing.expect(!isNative(.{ .op = .call_reg64, .dst_reg = .ah_sp_esp_rsp }));
    try testing.expect(!isNative(.{ .op = .div_reg8, .size = .bits8 }));
    try testing.expect(isNative(.{ .op = .div_reg32, .size = .bits32 }));
}

test "a control transfer is compiled as the block's last instruction and nothing after it is emitted" {
    var h = try TestHarness.init();
    defer h.deinit();
    // mov rax, rbx ; call [rip + slot] ; add rax, rbx (never part of the
    // block). An import-table call stays the interpreter's, which is what
    // this test is about.
    try h.add(0xC000, 3, regReg(.mov_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0xC003, 5, .{ .op = .call_mem64, .rip_relative = true });
    try h.add(0xC008, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var state = TestState{};
    state.regs.rbx = 7;
    state.interpret_result = 1;
    var completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 2), completed);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u32, 1), state.last_interpret_index);
    try testing.expectEqual(@as(u64, 7), state.regs.rax);
    try testing.expectEqual(@as(u32, 1), h.block.native_count);
    try testing.expectEqual(@as(u32, 1), h.block.fallback_count);
    // A shim that consumed the call leaves RIP at the next instruction and
    // says "continue": the block still ends there.
    state = TestState{};
    state.regs.rbx = 9;
    state.interpret_result = 0;
    completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 2), completed);
    try testing.expectEqual(@as(u64, 0xC008), state.regs.rip);
    try testing.expectEqual(@as(u64, 9), state.regs.rax);
}

test "plain [base+disp] accesses share one hoisted page translation and stay correct when it cannot be made" {
    var h = try TestHarness.init();
    defer h.deinit();
    // mov rax, [rbx+0x20] ; mov [rbx+0x40], rcx ; mov edx, [rbx+0x24] ; add rax, [rbx+0x28]
    try h.add(0x1000, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
    try h.add(0x1004, 4, baseDisp(.mov_mem64_reg64, .bits64, .cl_cx_ecx_rcx, 0x40));
    try h.add(0x1008, 3, baseDisp(.mov_reg32_mem32, .bits32, .dl_dx_edx_rdx, 0x24));
    try h.add(0x100B, 4, baseDisp(.add_reg64_mem64, .bits64, .al_ax_eax_rax, 0x28));
    {
        const insns = h.insns.items;
        const last = insns[insns.len - 1];
        const compiled = try compile(testing.allocator, &h.memory, TestState.layout, insns, last.rip + last.len);
        try testing.expect(compiled.hoisted_accesses >= 3);
    }
    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        state.admitMemory(admitted, admitted);
        std.mem.writeInt(u64, state.memory[0x120..][0..8], 0x1111_2222_3333_4444, .little);
        std.mem.writeInt(u64, state.memory[0x128..][0..8], 5, .little);
        state.regs.rbx = 0x100;
        state.regs.rcx = 0xABCD;
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 0x1111_2222_3333_4444 + 5), state.regs.rax);
        try testing.expectEqual(@as(u64, 0x1111_2222), state.regs.rdx);
        try testing.expectEqual(@as(u64, 0xABCD), std.mem.readInt(u64, state.memory[0x140..][0..8], .little));
        // Without admission every access took the ordinary probe's helper.
        if (!admitted) try testing.expect(state.reads >= 3 and state.writes >= 1);
    }

    // 128-bit moves through the same base share the hoisted pointer too:
    // vmovdqu xmm0, [rbx+0x40] ; vmovdqu [rbx+0x60], xmm0 ; mov rax, [rbx+0x20]
    {
        h.insns.clearRetainingCapacity();
        var load = baseDisp(.vmovdqu_xmm_mem, .bits64, .al_ax_eax_rax, 0x40);
        load.xmm_dst = 0;
        var store = baseDisp(.vmovdqu_mem_xmm, .bits64, .al_ax_eax_rax, 0x60);
        store.xmm_src = 0;
        try h.add(0x1000, 5, load);
        try h.add(0x1005, 5, store);
        try h.add(0x100A, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
        const insns = h.insns.items;
        const last = insns[insns.len - 1];
        const compiled = try compile(testing.allocator, &h.memory, TestState.layout, insns, last.rip + last.len);
        try testing.expect(compiled.hoisted_accesses >= 3);
        for ([_]bool{ true, false }) |admitted| {
            var vstate = TestState{};
            vstate.admitMemory(admitted, admitted);
            vstate.regs.rbx = 0x100;
            for (0..16) |i| vstate.memory[0x140 + i] = @intCast(0xA0 + i);
            std.mem.writeInt(u64, vstate.memory[0x120..][0..8], 9, .little);
            _ = try h.run(&vstate);
            try testing.expectEqualSlices(u8, vstate.memory[0x140..0x150], vstate.memory[0x160..0x170]);
            try testing.expectEqual(@as(u64, 9), vstate.regs.rax);
        }
    }

    // A new base mid-block is translated again before it is used.    // A new base mid-block is translated again before it is used.
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
    try h.add(0x1004, 4, baseDisp(.mov_reg64_mem64, .bits64, .dl_dx_edx_rdx, 0x28));
    try h.add(0x1008, 3, regReg(.mov_reg64_reg64, .bits64, .bl_bx_ebx_rbx, .dh_si_esi_rsi));
    try h.add(0x100B, 4, baseDisp(.mov_reg64_mem64, .bits64, .cl_cx_ecx_rcx, 0x20));
    try h.add(0x100F, 4, baseDisp(.mov_reg64_mem64, .bits64, .r8b_r8w_r8d_r8, 0x28));
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rsi = 0x800;
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 1, .little);
    std.mem.writeInt(u64, state.memory[0x128..][0..8], 2, .little);
    std.mem.writeInt(u64, state.memory[0x820..][0..8], 3, .little);
    std.mem.writeInt(u64, state.memory[0x828..][0..8], 4, .little);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u64, 2), state.regs.rdx);
    try testing.expectEqual(@as(u64, 3), state.regs.rcx);
    try testing.expectEqual(@as(u64, 4), state.regs.r8);
}

test "constructor vptr stores preserve RIP-relative image addresses with cached registers" {
    var h = try TestHarness.init();
    defer h.deinit();

    // This is the memory shape used by XObject/XThread constructors: a
    // RIP-relative LEA materialises an image vtable address, then a cached
    // register is stored at the object's base followed by ordinary scalar
    // and vector field stores.  Exercise both TLB modes because the live PE
    // path uses the direct page when it has been admitted.
    var lea: DecodedInsn = .{ .op = .lea_reg_mem, .size = .bits64, .dst_reg = .al_ax_eax_rax, .addr = 0x1200, .rip_relative = true };
    lea.len = 7;
    const vptr_store = baseDisp(.mov_mem64_reg64, .bits64, .al_ax_eax_rax, 0);
    var type_store = baseDisp(.mov_mem32_imm32, .bits32, .al_ax_eax_rax, 0x10);
    type_store.imm = 3;
    var vector_store = baseDisp(.vmovups_mem_xmm, .bits64, .al_ax_eax_rax, 0x20);
    vector_store.xmm_src = 0;
    try h.add(0x1000, 7, lea);
    try h.add(0x1007, 4, vptr_store);
    try h.add(0x100B, 5, type_store);
    try h.add(0x1010, 5, vector_store);

    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        if (admitted) state.admitMemory(true, true);
        state.regs.rcx = 0x200;
        state.regs.rbx = 0x200;
        state.regs.rdx = 0xAABB_CCDD_EEFF_0011;
        state.xmm[0] = @splat(0x5A);
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 0x1000 + 7 + 0x1200), std.mem.readInt(u64, state.memory[0x200..][0..8], .little));
        try testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, state.memory[0x210..][0..4], .little));
        try testing.expectEqualSlices(u8, &([_]u8{0x5A} ** 16), state.memory[0x220..0x230]);
    }
}

test "XThread constructor stores keep its vptr through cached base and YMM fields" {
    var h = try TestHarness.init();
    defer h.deinit();

    // This is the straight-line portion of XThread::XThread after its base
    // constructors return.  It is deliberately kept close to the PE bytes:
    // the constructor's vptr LEA, a VEX zeroing fallback, three 256-bit
    // stores, scalar fields, and the final base-register adjustment.
    var lea: DecodedInsn = .{ .op = .lea_reg_mem, .size = .bits64, .dst_reg = .al_ax_eax_rax, .addr = 0x10124F1, .rip_relative = true };
    lea.len = 7;
    try h.add(0x140231C10, 7, lea);
    var vptr_store = baseDispAt(.mov_mem64_reg64, .bits64, .dh_si_esi_rsi, 0);
    vptr_store.src_reg = .al_ax_eax_rax;
    try h.add(0x140231C17, 3, vptr_store);
    try h.add(0x140231C1A, 4, .{ .op = .vxorps, .size = .bits32, .xmm_dst = 0, .xmm_src = 0, .xmm_src2 = 0, .is_reg_form = true });
    for ([_]struct { rip: u64, disp: u64 }{
        .{ .rip = 0x140231C1E, .disp = 0x98 },
        .{ .rip = 0x140231C26, .disp = 0xB8 },
        .{ .rip = 0x140231C2E, .disp = 0xCC },
    }) |store| {
        var ymm_store = baseDispAt(.vmovups_mem_ymm, .bits64, .dh_si_esi_rsi, store.disp);
        ymm_store.vector_256 = true;
        ymm_store.xmm_src = 0;
        try h.add(store.rip, 8, ymm_store);
    }
    var word_store = baseDispAt(.mov_mem16_imm16, .bits16, .dh_si_esi_rsi, 0xEC);
    word_store.imm = 1;
    try h.add(0x140231C36, 9, word_store);
    const byte_store = baseDispAt(.mov_mem8_imm8, .bits8, .dh_si_esi_rsi, 0xEE);
    try h.add(0x140231C3F, 7, byte_store);
    try h.add(0x140231C46, 11, baseDispAt(.mov_mem64_imm32, .bits64, .dh_si_esi_rsi, 0xF0));
    try h.add(0x140231C51, 10, baseDispAt(.mov_mem32_imm32, .bits32, .dh_si_esi_rsi, 0xF8));
    try h.add(0x140231C5B, 11, baseDispAt(.mov_mem64_imm32, .bits64, .dh_si_esi_rsi, 0x100));
    try h.add(0x140231C66, 10, baseDispAt(.mov_mem32_imm32, .bits32, .dh_si_esi_rsi, 0x210));
    try h.add(0x140231C70, 7, regImm(.add_reg64_imm32, .bits64, .dh_si_esi_rsi, 0x218));
    try h.add(0x140231C77, 3, regReg(.mov_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dh_si_esi_rsi));
    try h.add(0x140231C7A, 2, regReg(.xor_reg32_reg32, .bits32, .dl_dx_edx_rdx, .dl_dx_edx_rdx));
    try h.add(0x140231C7C, 3, .{ .op = .vzeroupper, .size = .bits32, .is_reg_form = true });

    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        if (admitted) state.admitMemory(true, true);
        state.regs.rsi = 0x200;
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 0x141244108), std.mem.readInt(u64, state.memory[0x200..][0..8], .little));
        try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, state.memory[0x2EC..][0..2], .little));
        try testing.expectEqual(@as(u8, 0), state.memory[0x2EE]);
        try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.memory[0x2F0..][0..8], .little));
        try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, state.memory[0x2F8..][0..4], .little));
        try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.memory[0x300..][0..8], .little));
        try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, state.memory[0x410..][0..4], .little));
        try testing.expectEqual(@as(u64, 0x418), state.regs.rsi);
        try testing.expectEqual(@as(u64, 0x418), state.regs.rcx);
        try testing.expectEqual(@as(u64, 0), state.regs.rdx);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), state.memory[0x298..0x2B8]);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), state.memory[0x2B8..0x2D8]);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), state.memory[0x2CC..0x2EC]);
    }
}

test "admitted pages are read and written through the TLB without a helper call, and a page-crossing access is not" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 0x0102_0304_0506_0708, .little);
    state.regs.rbx = 0x100;
    state.regs.rcx = 0xAABB_CCDD_EEFF_0011;
    // mov rax, [rbx + 0x20] ; mov [rbx + 0x40], rcx ; mov dx, [rbx + 0x22] ; mov byte [rbx + 0x50], 0x7F
    try h.add(0x1000, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
    try h.add(0x1004, 4, baseDisp(.mov_mem64_reg64, .bits64, .cl_cx_ecx_rcx, 0x40));
    try h.add(0x1008, 5, baseDisp(.mov_reg16_mem16, .bits16, .dl_dx_edx_rdx, 0x22));
    var imm_store = baseDisp(.mov_mem8_imm8, .bits8, .al_ax_eax_rax, 0x50);
    imm_store.imm = 0x7F;
    try h.add(0x100D, 4, imm_store);
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 4), completed);
    try testing.expectEqual(@as(u32, 0), state.reads);
    try testing.expectEqual(@as(u32, 0), state.writes);
    try testing.expectEqual(@as(u64, 0x0102_0304_0506_0708), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x0506), state.regs.rdx);
    try testing.expectEqual(@as(u64, 0xAABB_CCDD_EEFF_0011), std.mem.readInt(u64, state.memory[0x140..][0..8], .little));
    try testing.expectEqual(@as(u8, 0x7F), state.memory[0x150]);
    try testing.expect(!h.block.register_only);

    // Only the read side admitted: the store goes to the helper.
    state = TestState{};
    state.admitMemory(true, false);
    state.regs.rbx = 0x100;
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.reads);
    try testing.expectEqual(@as(u32, 2), state.writes);

    // An eight-byte load at the last four bytes of the page leaves the
    // page: the helper is called although the page is admitted.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0xFFC;
    try h.add(0x2000, 3, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0));
    try h.add(0x2003, 3, baseDisp(.mov_reg32_mem32, .bits32, .cl_cx_ecx_rcx, 0));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.reads);
    // A different page than the admitted one misses.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x1000;
    try h.add(0x2000, 3, baseDisp(.mov_reg32_mem32, .bits32, .cl_cx_ecx_rcx, 0x10));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.reads);
}

test "the TLB admits, looks up and invalidates by page" {
    var tlb = Tlb.empty;
    var bytes: [8192]u8 align(4096) = undefined;
    tlb.fill(false, 0x1_0000_0000, &bytes);
    tlb.fill(true, 0x1_0000_1000, bytes[4096..].ptr);
    try testing.expectEqual(@intFromPtr(&bytes) + 0x123, @intFromPtr(tlb.lookup(false, 0x1_0000_0123).?));
    try testing.expect(tlb.lookup(true, 0x1_0000_0123) == null);
    try testing.expectEqual(@intFromPtr(&bytes) + 4096 + 8, @intFromPtr(tlb.lookup(true, 0x1_0000_1008).?));
    // An aliasing page (same index, other tag) misses rather than lies.
    try testing.expect(tlb.lookup(false, 0x1_0040_0123) == null);
    tlb.invalidateRange(0x1_0000_0800, 0x10);
    try testing.expect(tlb.lookup(false, 0x1_0000_0123) == null);
    try testing.expect(tlb.lookup(true, 0x1_0000_1008) != null);
    tlb.invalidateRange(0, std.math.maxInt(u64));
    try testing.expect(tlb.lookup(true, 0x1_0000_1008) == null);
    tlb.fill(false, 0x2000, &bytes);
    tlb.flush(false, true);
    try testing.expect(tlb.lookup(false, 0x2004) != null);
    tlb.flush(true, false);
    try testing.expect(tlb.lookup(false, 0x2004) == null);
}

test "flag computation is elided only for writers no reader can observe" {
    var h = try TestHarness.init();
    defer h.deinit();
    // add rax, rbx ; add rcx, rdx: the first writer's flags are dead.
    var state = TestState{};
    state.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rbx = 1;
    state.regs.rcx = 5;
    state.regs.rdx = 3;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 3, regReg(.add_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), h.flags_elided);
    var expected: u32 = 0x2;
    _ = referenceBinary(.add, .bits64, 5, 3, &expected);
    try testing.expectEqual(expected, state.regs.rflags);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u64, 8), state.regs.rcx);

    // A fallback between them reads every flag: nothing is elided, and the
    // interpret helper sees the first add's flags (CF, ZF, PF, AF).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rbx = 1;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 1, .{ .op = .lahf });
    try h.add(0x1004, 3, regReg(.add_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), h.flags_elided);
    expected = 0x2;
    _ = referenceBinary(.add, .bits64, 0xFFFF_FFFF_FFFF_FFFF, 1, &expected);
    try testing.expectEqual(expected, state.flags_at_interpret);

    // inc leaves CF alone, so an add before it keeps its flags (CF is
    // live), while an inc before an add is dead.
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 3, .{ .op = .inc_reg64, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    state = TestState{};
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), h.flags_elided);
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 3, .{ .op = .inc_reg64, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    try h.add(0x1003, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    state = TestState{};
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), h.flags_elided);

    // A conditional branch reads the flags of the writer before it, and a
    // shift by cl may write nothing, so it kills nothing.
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 3, .{ .op = .shl_reg_cl, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    try h.add(0x1006, 2, .{ .op = .jcc_rel8, .cond = .e, .addr = 0x10 });
    state = TestState{};
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), h.flags_elided);
}

test "shifts by cl and rotates follow the interpreter's count and flag rules" {
    var h = try TestHarness.init();
    defer h.deinit();
    // shl rax, cl with cl = 1 on 0x8000...1: result 2, CF set, OF set (msb 0 != CF 1).
    var state = TestState{};
    state.regs.rax = 0x8000_0000_0000_0001;
    state.regs.rcx = 0x41; // masked to 1
    state.regs.rflags = 0x2 | RFL_PF;
    try h.add(0x1000, 3, .{ .op = .shl_reg_cl, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 2), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expect(state.regs.rflags & RFL_PF != 0);
    try testing.expect(state.regs.rflags & (RFL_ZF | RFL_SF) == 0);

    // shl eax, cl with a zero count: flags untouched, the register is
    // rewritten at 32 bits (zero-extended).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0xFFFF_FFFF_0000_0001;
    state.regs.rcx = 0x20; // masked to 0 at 32 bits
    state.regs.rflags = 0x8D5;
    try h.add(0x1000, 2, .{ .op = .shl_reg_cl, .size = .bits32, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u32, 0x8D5), state.regs.rflags);

    // shr edx, cl (31) on 0x80000000: 1, CF = bit 30 = 0, OF untouched.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdx = 0x8000_0000;
    state.regs.rcx = 31;
    state.regs.rflags = 0x2 | RFL_OF | RFL_CF;
    try h.add(0x1000, 2, .{ .op = .shr_reg_cl, .size = .bits32, .dst_reg = .dl_dx_edx_rdx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 1), state.regs.rdx);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);

    // sar rsi, cl (2) on -8: -2, CF = bit 1 = 0, SF set.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rsi = @bitCast(@as(i64, -8));
    state.regs.rcx = 2;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, .{ .op = .sar_reg_cl, .size = .bits64, .dst_reg = .dh_si_esi_rsi, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), state.regs.rsi);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);

    // rol eax, 1 on 0x80000001: 3, CF 1, OF = msb(result) 0 != CF → set.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x8000_0001;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, regImm(.rol_reg_imm, .bits32, .al_ax_eax_rax, 1));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 3), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_OF != 0);

    // ror rbx, cl (1) on 1: 0x8000..., CF 1, OF = CF != bit 62 → set.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 1;
    state.regs.rcx = 1;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, .{ .op = .ror_reg_cl, .size = .bits64, .dst_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x8000_0000_0000_0000), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_OF != 0);

    // rol rbx, 8 on 0x0102...: rotated, CF = low bit of result, OF untouched.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0x0102_0304_0506_0781;
    state.regs.rflags = 0x2 | RFL_OF;
    try h.add(0x1000, 4, regImm(.rol_reg_imm, .bits64, .bl_bx_ebx_rbx, 8));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x0203_0405_0607_8101), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_OF != 0);

    // A zero rotate count does nothing, not even a rewrite.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0xFFFF_FFFF_0000_0001;
    state.regs.rcx = 32;
    state.regs.rflags = 0x8D5;
    try h.add(0x1000, 2, .{ .op = .rol_reg_cl, .size = .bits32, .dst_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_0000_0001), state.regs.rbx);
    try testing.expectEqual(@as(u32, 0x8D5), state.regs.rflags);
}

test "bit tests, bit scans and zero counts follow bit_test and cpu.bitScan" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rax = 0x20;
    state.regs.r8 = 0;
    state.regs.r9 = 65; // bit 1 modulo 64
    state.regs.rcx = 0xF;
    state.regs.rflags = 0x2;
    // bt eax, 5 ; bts r8, r9 ; btr rcx, 3
    try h.add(0x1000, 4, regImm(.bt_reg_imm, .bits32, .al_ax_eax_rax, 5));
    try h.add(0x1004, 4, regReg(.bts_reg_reg, .bits64, .r8b_r8w_r8d_r8, .r9b_r9w_r9d_r9));
    try h.add(0x1008, 4, regImm(.btr_reg_imm, .bits64, .cl_cx_ecx_rcx, 3));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 2), state.regs.r8);
    try testing.expectEqual(@as(u64, 7), state.regs.rcx);
    try testing.expect(state.regs.rflags & RFL_CF != 0); // the last one: bit 3 of 0xF
    // bt alone reports CF and writes nothing.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x20;
    state.regs.rflags = 0x2 | RFL_CF;
    try h.add(0x1000, 4, regImm(.bt_reg_imm, .bits32, .al_ax_eax_rax, 4));
    _ = try h.run(&state);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expectEqual(@as(u64, 0x20), state.regs.rax);

    // bsf eax, ebx (0x100) → 8, ZF clear; bsf with zero → destination kept, ZF set.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x1111;
    state.regs.rbx = 0x100;
    state.regs.rflags = 0x2 | RFL_ZF;
    try h.add(0x1000, 3, regReg(.bsf_reg_reg, .bits32, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 8), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    state = TestState{};
    state.regs.rax = 0x1111;
    state.regs.rbx = 0;
    state.regs.rflags = 0x2;
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x1111), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);
    // bsr rcx, rdx (top bit) → 63; bsr ax, bx (0x400) → 10.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdx = 0x8000_0000_0000_0000;
    state.regs.rbx = 0x0400;
    try h.add(0x1000, 4, regReg(.bsr_reg_reg, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    try h.add(0x1004, 4, regReg(.bsr_reg_reg, .bits16, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 63), state.regs.rcx);
    try testing.expectEqual(@as(u64, 10), state.regs.rax);

    // tzcnt eax, ebx (0) → 32, CF set, ZF clear; lzcnt rcx, rdx (1) → 63.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0;
    state.regs.rdx = 1;
    try h.add(0x1000, 4, regReg(.tzcnt_reg_reg, .bits32, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 32), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_ZF == 0);
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 5, regReg(.lzcnt_reg_reg, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 63), state.regs.rcx);
    try testing.expect(state.regs.rflags & (RFL_CF | RFL_ZF) == 0);
    // tzcnt of 1 → 0: ZF set, CF clear.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdx = 1;
    try h.add(0x1000, 5, regReg(.tzcnt_reg_reg, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0), state.regs.rcx);
    try testing.expect(state.regs.rflags & RFL_ZF != 0 and state.regs.rflags & RFL_CF == 0);
}

test "adc and sbb produce highway.addCarry and subBorrow's results at every width" {
    var h = try TestHarness.init();
    defer h.deinit();
    var prng = std.Random.DefaultPrng.init(0xADC_5BB);
    const random = prng.random();
    const forms = [_]struct { op: Op, size: Size, adc: bool }{
        .{ .op = .adc_reg64_reg64, .size = .bits64, .adc = true },
        .{ .op = .adc_reg32_reg32, .size = .bits32, .adc = true },
        .{ .op = .adc_reg16_reg16, .size = .bits16, .adc = true },
        .{ .op = .adc_reg8_reg8, .size = .bits8, .adc = true },
        .{ .op = .sbb_reg64_reg64, .size = .bits64, .adc = false },
        .{ .op = .sbb_reg32_reg32, .size = .bits32, .adc = false },
        .{ .op = .sbb_reg16_reg16, .size = .bits16, .adc = false },
        .{ .op = .sbb_reg8_reg8, .size = .bits8, .adc = false },
    };
    for (forms) |form| {
        for (0..48) |_| {
            var state = TestState{};
            const a = switch (random.uintLessThan(u8, 3)) {
                0 => random.int(u64),
                1 => maskFor(form.size),
                else => random.int(u8),
            };
            const b = switch (random.uintLessThan(u8, 3)) {
                0 => random.int(u64),
                1 => maskFor(form.size),
                else => 0,
            };
            state.regs.rsi = a;
            state.regs.rdi = b;
            state.regs.rflags = (random.int(u32) & 0xFFF) | 0x2;
            const width: x64_decoder.highway.Width = switch (form.size) {
                .bits8 => .bits8,
                .bits16 => .bits16,
                .bits32 => .bits32,
                .bits64 => .bits64,
            };
            const reference = x64_decoder.highway.evaluate(if (form.adc) .adc else .sbb, width, a & maskFor(form.size), b & maskFor(form.size), state.regs.rflags);
            h.insns.clearRetainingCapacity();
            try h.add(0x2000, 3, regReg(form.op, form.size, .dh_si_esi_rsi, .bh_di_edi_rdi));
            _ = try h.run(&state);
            try testing.expectEqual(reference.rflags, state.regs.rflags);
            const expected_reg: u64 = switch (form.size) {
                .bits64, .bits32 => reference.value,
                .bits16 => (a & ~@as(u64, 0xFFFF)) | reference.value,
                .bits8 => (a & ~@as(u64, 0xFF)) | reference.value,
            };
            try testing.expectEqual(expected_reg, state.regs.rsi);
        }
    }
}

test "256-bit moves carry both halves and leave the upper one alone" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rbx = 0x100;
    for (0..16) |byte| {
        state.memory[0x120 + byte] = @intCast(0x10 + byte);
        state.memory[0x130 + byte] = @intCast(0xA0 + byte);
    }
    // A 256-bit load fills the low half from the operand and the upper half
    // from sixteen bytes further along - and must not clear the upper half
    // the way every VEX.128 write does.
    var load = vecMem(.vmovdqa_ymm_mem, 3, 0, 0x20);
    load.vector_256 = true;
    try h.add(0x9000, 7, load);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 0x10), state.xmm[3][0]);
    try testing.expectEqual(@as(u8, 0x1F), state.xmm[3][15]);
    try testing.expectEqual(@as(u8, 0xA0), state.ymm_hi[3][0]);
    try testing.expectEqual(@as(u8, 0xAF), state.ymm_hi[3][15]);
    // Both halves came from memory, so both reached the store helper.
    try testing.expectEqual(@as(u32, 2), state.reads);

    // A 256-bit store writes both halves back, sixteen bytes apart.
    h.insns.clearRetainingCapacity();
    state.reads = 0;
    state.writes = 0;
    for (0..16) |byte| {
        state.xmm[5][byte] = @intCast(0x40 + byte);
        state.ymm_hi[5][byte] = @intCast(0x80 + byte);
    }
    var store = vecMem(.vmovdqa_mem_ymm, 0, 5, 0x40);
    store.vector_256 = true;
    try h.add(0x9100, 7, store);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 0x40), state.memory[0x140]);
    try testing.expectEqual(@as(u8, 0x4F), state.memory[0x14F]);
    try testing.expectEqual(@as(u8, 0x80), state.memory[0x150]);
    try testing.expectEqual(@as(u8, 0x8F), state.memory[0x15F]);
    try testing.expectEqual(@as(u32, 2), state.writes);

    // Register to register moves both halves and asks the interpreter for
    // nothing.
    h.insns.clearRetainingCapacity();
    state.interprets = 0;
    var move: DecodedInsn = .{ .op = .vmovdqa_ymm_ymm, .size = .bits32, .xmm_dst = 9, .xmm_src = 5, .is_reg_form = true };
    move.vector_256 = true;
    try h.add(0x9200, 4, move);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 0x40), state.xmm[9][0]);
    try testing.expectEqual(@as(u8, 0x80), state.ymm_hi[9][0]);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "a 256-bit form that is not a plain move still goes to the interpreter" {
    // Only moves are served at 256 bits; anything else would need every lane
    // template widened, and a half-widened one is worse than none.
    var arithmetic: DecodedInsn = .{ .op = .vpaddd, .size = .bits32, .xmm_dst = 1, .xmm_src = 2, .xmm_src2 = 3, .is_reg_form = true };
    arithmetic.vector_256 = true;
    try testing.expect(!isVectorNative(arithmetic));
    var narrow = arithmetic;
    narrow.vector_256 = false;
    try testing.expect(isVectorNative(narrow));
}

test "movbe, xchg, one-operand multiply and guarded divide" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rcx = 0x1122_3344_5566_7788;
    state.memory[0x100] = 0x01;
    state.memory[0x101] = 0x02;
    state.memory[0x102] = 0x03;
    state.memory[0x103] = 0x04;
    // movbe eax, [rbx] ; movbe [rbx + 8], rcx ; movbe dx, [rbx]
    try h.add(0x1000, 4, baseDisp(.movbe_reg_mem, .bits32, .al_ax_eax_rax, 0));
    try h.add(0x1004, 5, baseDisp(.movbe_mem_reg, .bits64, .cl_cx_ecx_rcx, 8));
    try h.add(0x1009, 5, baseDisp(.movbe_reg_mem, .bits16, .dl_dx_edx_rdx, 0));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x0102_0304), state.regs.rax);
    try testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 }, state.memory[0x108..0x110]);
    try testing.expectEqual(@as(u64, 0x0102), state.regs.rdx);

    // xchg rax, rbx ; xchg eax, ecx (accumulator form)
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 1;
    state.regs.rbx = 2;
    state.regs.rcx = 0xFFFF_FFFF_0000_0003;
    try h.add(0x1000, 3, regReg(.xchg_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 1, .{ .op = .xchg_accum_reg, .size = .bits32, .src_reg = .cl_cx_ecx_rcx });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 3), state.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.regs.rbx);
    try testing.expectEqual(@as(u64, 2), state.regs.rcx);

    // mul rbx: 2^64-1 * 2 = 0x1_FFFF_FFFF_FFFF_FFFE ; imul ebx (-3 * 4).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rbx = 2;
    try h.add(0x1000, 3, .{ .op = .mul_reg64, .size = .bits64, .src_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FFFE), state.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.regs.rdx);
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0xFFFF_FFFD;
    state.regs.rbx = 4;
    try h.add(0x1000, 2, .{ .op = .imul_reg32, .size = .bits32, .src_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFF4), state.regs.rax);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.rdx);

    // div ecx (100 / 7) natively; idiv rcx (-100 / 7) natively.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 100;
    state.regs.rdx = 0;
    state.regs.rcx = 7;
    try h.add(0x1000, 2, .{ .op = .div_reg32, .size = .bits32, .src_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 14), state.regs.rax);
    try testing.expectEqual(@as(u64, 2), state.regs.rdx);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = @bitCast(@as(i64, -100));
    state.regs.rdx = @bitCast(@as(i64, -1));
    state.regs.rcx = 7;
    try h.add(0x1000, 3, .{ .op = .idiv_reg64, .size = .bits64, .src_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -14))), state.regs.rax);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), state.regs.rdx);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    // A high half that would overflow, a zero divisor and a divisor of -1
    // all go to the interpreter.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 100;
    state.regs.rdx = 1;
    state.regs.rcx = 7;
    try h.add(0x1000, 2, .{ .op = .div_reg32, .size = .bits32, .src_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u64, 100), state.regs.rax);
    state = TestState{};
    state.regs.rcx = 0;
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 5;
    state.regs.rdx = 0;
    state.regs.rcx = 0xFFFF_FFFF;
    try h.add(0x1000, 2, .{ .op = .idiv_reg32, .size = .bits32, .src_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.interprets);
}

test "Group-1 memory forms, inc/dec/neg/not on memory, imul and cmov from memory" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x200;
    state.regs.rax = 10;
    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF;
    std.mem.writeInt(u64, state.memory[0x210..][0..8], 5, .little);
    std.mem.writeInt(u32, state.memory[0x200..][0..4], 3, .little);
    std.mem.writeInt(u32, state.memory[0x204..][0..4], 0xFFFF_FFFF, .little);
    std.mem.writeInt(u64, state.memory[0x208..][0..8], 6, .little);
    state.memory[0x218] = 0x0F;
    std.mem.writeInt(u64, state.memory[0x220..][0..8], 7, .little);
    std.mem.writeInt(u32, state.memory[0x230..][0..4], 99, .little);
    // add [rbx+0x10], rax        → 15
    // sub eax, [rbx]             → 7
    // cmp dword [rbx], 5         → 3 - 5: CF set
    // inc dword [rbx+4]          → 0 (ZF), CF kept from cmp
    // neg qword [rbx+8]          → -6
    // not byte [rbx+0x18]        → 0xF0
    // imul rax, [rbx+0x20]       → 49
    // cmovne ecx, [rbx+0x30]     → ZF was cleared by neg (-6 is nonzero), so the move happens: ecx = 99
    var add_mem = baseDisp(.add_mem64_reg64, .bits64, .al_ax_eax_rax, 0x10);
    add_mem.src_reg = .al_ax_eax_rax;
    try h.add(0x1000, 4, add_mem);
    try h.add(0x1004, 2, baseDisp(.sub_reg32_mem32, .bits32, .al_ax_eax_rax, 0));
    var cmp_imm = baseDisp(.cmp_mem32_imm8, .bits32, .al_ax_eax_rax, 0);
    cmp_imm.imm = 5;
    try h.add(0x1006, 3, cmp_imm);
    try h.add(0x1009, 3, baseDisp(.inc_mem32, .bits32, .al_ax_eax_rax, 4));
    try h.add(0x100C, 4, baseDisp(.neg_mem64, .bits64, .al_ax_eax_rax, 8));
    try h.add(0x1010, 3, baseDisp(.not_mem8, .bits8, .al_ax_eax_rax, 0x18));
    try h.add(0x1013, 5, baseDisp(.imul_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
    var cmov = baseDisp(.cmovcc_reg_mem, .bits32, .cl_cx_ecx_rcx, 0x30);
    cmov.cond = .ne;
    try h.add(0x1018, 4, cmov);
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 8), completed);
    try testing.expectEqual(@as(u64, 15), std.mem.readInt(u64, state.memory[0x210..][0..8], .little));
    try testing.expectEqual(@as(u64, 49), state.regs.rax);
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, state.memory[0x204..][0..4], .little));
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -6))), std.mem.readInt(u64, state.memory[0x208..][0..8], .little));
    try testing.expectEqual(@as(u8, 0xF0), state.memory[0x218]);
    try testing.expectEqual(@as(u64, 99), state.regs.rcx);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    try testing.expect(state.regs.rflags & (RFL_CF | RFL_OF) == 0); // imul's product fits
    try testing.expectEqual(@as(u32, 0), state.reads + state.writes);
}

fn vecRegs(op: Op, dst: u8, src: u8, src2: u8) DecodedInsn {
    return .{ .op = op, .size = .bits32, .xmm_dst = dst, .xmm_src = src, .xmm_src2 = src2, .is_reg_form = true };
}

fn vecMem(op: Op, dst: u8, src: u8, disp: u64) DecodedInsn {
    return .{ .op = op, .size = .bits32, .xmm_dst = dst, .xmm_src = src, .addr = disp, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx };
}

fn lanes32(values: [4]u32) [16]u8 {
    var bytes: [16]u8 = undefined;
    for (values, 0..) |value, lane| std.mem.writeInt(u32, bytes[lane * 4 ..][0..4], value, .little);
    return bytes;
}

fn floats32(values: [4]f32) [16]u8 {
    var bytes: [16]u8 = undefined;
    for (values, 0..) |value, lane| std.mem.writeInt(u32, bytes[lane * 4 ..][0..4], @bitCast(value), .little);
    return bytes;
}

test "vector moves, logic and integer arithmetic follow the lane rules and clear the upper halves" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    const a = lanes32(.{ 0x0000_0001, 0x8000_0000, 0xFFFF_FFFF, 0x1234_5678 });
    const b = lanes32(.{ 0x0000_0002, 0x7FFF_FFFF, 0x0000_0001, 0x1234_5678 });
    state.xmm[1] = a;
    state.xmm[2] = b;
    state.ymm_hi[0] = @splat(0xAA);
    state.ymm_hi[3] = @splat(0xAA);
    state.zmm_hi[0] = @splat(0xBB);
    state.zmm_hi[3] = @splat(0xBB);
    // vmovaps xmm0, xmm1 ; vpxor xmm3, xmm1, xmm2 ; vpaddd xmm4, xmm1, xmm2 ; vpcmpgtd xmm5, xmm1, xmm2 ; vpminub xmm6, xmm1, xmm2 ; vpaddusw xmm7, xmm1, xmm2
    try h.add(0x1000, 4, vecRegs(.vmovaps_xmm_xmm, 0, 1, 0));
    try h.add(0x1004, 4, vecRegs(.vpxor, 3, 1, 2));
    try h.add(0x1008, 4, vecRegs(.vpaddd, 4, 1, 2));
    try h.add(0x100C, 4, vecRegs(.vpcmpgtd, 5, 1, 2));
    try h.add(0x1010, 4, vecRegs(.vpminub, 6, 1, 2));
    try h.add(0x1014, 4, vecRegs(.vpaddusw, 7, 1, 2));
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 6), completed);
    try testing.expectEqualSlices(u8, &a, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0xBB} ** 32), &state.zmm_hi[0]); // not an EVEX-routed form
    try testing.expectEqualSlices(u8, &lanes32(.{ 3, 0xFFFF_FFFF, 0xFFFF_FFFE, 0 }), &state.xmm[3]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[3]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), &state.zmm_hi[3]); // vpxor is EVEX-routed
    try testing.expectEqualSlices(u8, &lanes32(.{ 3, 0xFFFF_FFFF, 0, 0x2468_ACF0 }), &state.xmm[4]);
    // signed: 1 > 2 no; INT_MIN > INT_MAX no; -1 > 1 no; equal no.
    try testing.expectEqualSlices(u8, &lanes32(.{ 0, 0, 0, 0 }), &state.xmm[5]);
    // unsigned byte minimum: lane 1 is 00 00 00 80 against FF FF FF 7F.
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x0000_0001, 0x7F00_0000, 0x0000_0001, 0x1234_5678 }), &state.xmm[6]);
    // unsigned saturating word add: 0x0001+0x0002, 0x8000+0x7FFF=0xFFFF, 0xFFFF+0x0001 saturates, 0xFFFF+0x0000...
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x0000_0003, 0xFFFF_FFFF, 0xFFFF_FFFF, 0x2468_ACF0 }), &state.xmm[7]);
    // Vector state is outside the glue's register-only cross-check, so a
    // block of vector ops is not offered for it.
    try testing.expect(!h.block.register_only);
}

test "vector loads and stores go through the TLB when admitted and through the 128-bit helpers otherwise" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    const pattern = lanes32(.{ 0x11111111, 0x22222222, 0x33333333, 0x44444444 });
    @memcpy(state.memory[0x120..0x130], &pattern);
    state.xmm[1] = lanes32(.{ 5, 6, 7, 8 });
    // vmovdqu xmm0, [rbx + 0x20] ; vmovaps [rbx + 0x40], xmm1 ; vpaddd xmm2, xmm1, [rbx + 0x20]
    try h.add(0x1000, 5, vecMem(.vmovdqu_xmm_mem, 0, 0, 0x20));
    try h.add(0x1005, 5, vecMem(.vmovaps_mem_xmm, 0, 1, 0x40));
    var add_mem = vecMem(.vpaddd, 2, 1, 0x20);
    add_mem.xmm_src2 = 0;
    try h.add(0x100A, 5, add_mem);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.reads + state.writes);
    try testing.expectEqualSlices(u8, &pattern, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 5, 6, 7, 8 }), state.memory[0x140..0x150]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x11111116, 0x22222228, 0x3333333A, 0x4444444C }), &state.xmm[2]);
    // Nothing admitted: the same block calls the helpers.
    state = TestState{};
    state.regs.rbx = 0x100;
    @memcpy(state.memory[0x120..0x130], &pattern);
    state.xmm[1] = lanes32(.{ 5, 6, 7, 8 });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 2), state.reads);
    try testing.expectEqual(@as(u32, 1), state.writes);
    try testing.expectEqualSlices(u8, &pattern, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 5, 6, 7, 8 }), state.memory[0x140..0x150]);
}

fn doubles64(values: [2]f64) [16]u8 {
    var bytes: [16]u8 = undefined;
    for (values, 0..) |value, lane| std.mem.writeInt(u64, bytes[lane * 8 ..][0..8], @bitCast(value), .little);
    return bytes;
}

test "Xenia's hot vector and MXCSR forms run natively with the interpreter's lane rules" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.xmm[1] = lanes32(.{ 0xFFFF_FFFF, 0xDEAD_BEEF, 3, 0x1234_5678 });
    state.xmm[2] = lanes32(.{ 2, 0xCAFE_BABE, 0x8000_0000, 7 });
    state.xmm[7] = floats32(.{ 1.5, -2.0, 3.25, 1.0e30 });
    for ([_]usize{ 0, 3, 4, 5, 6, 8 }) |dst| state.ymm_hi[dst] = @splat(0xAA);
    std.mem.writeInt(u32, state.memory[0x110..][0..4], 0x0000_9FC0, .little);
    std.mem.writeInt(u32, state.memory[0x130..][0..4], 0x4242_4242, .little);
    // vpmuludq xmm0, xmm1, xmm2
    try h.add(0x1000, 4, vecRegs(.vpmuludq, 0, 1, 2));
    // vpblendw xmm3, xmm1, xmm2, 0xA5
    var blend = vecRegs(.vpblendw, 3, 1, 2);
    blend.imm = 0xA5;
    try h.add(0x1004, 6, blend);
    // vshufpd xmm4, xmm1, xmm2, 1
    var shuf = vecRegs(.vshufpd, 4, 1, 2);
    shuf.imm = 1;
    try h.add(0x100A, 5, shuf);
    // vinsertps xmm5, xmm1, xmm2, (2 << 6) | (1 << 4) | 0b1000
    var insert = vecRegs(.vinsertps, 5, 1, 2);
    insert.imm = (2 << 6) | (1 << 4) | 0b1000;
    try h.add(0x100F, 6, insert);
    // vcvtps2pd ymm6, xmm7
    var widen = vecRegs(.vcvtps2pd, 6, 0, 7);
    widen.vector_256 = true;
    try h.add(0x1015, 4, widen);
    // vinsertps xmm8, xmm1, [rbx+0x30], (3 << 6) | (2 << 4) | 0b0001 - a memory
    // source ignores the source-lane bits.
    var insert_mem = vecMem(.vinsertps, 8, 1, 0x30);
    insert_mem.imm = (3 << 6) | (2 << 4) | 0b0001;
    try h.add(0x1019, 7, insert_mem);
    // ldmxcsr [rbx+0x10] ; stmxcsr [rbx+0x20]
    try h.add(0x1020, 4, baseDisp(.ldmxcsr_mem32, .bits32, .al_ax_eax_rax, 0x10));
    try h.add(0x1024, 4, baseDisp(.stmxcsr_mem32, .bits32, .al_ax_eax_rax, 0x20));
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 8), completed);
    var products: [16]u8 = undefined;
    std.mem.writeInt(u64, products[0..8], 0xFFFF_FFFF * 2, .little);
    std.mem.writeInt(u64, products[8..16], 3 * 0x8000_0000, .little);
    try testing.expectEqualSlices(u8, &products, &state.xmm[0]);
    var blended: [16]u8 = undefined;
    for (0..8) |lane| {
        const from = if ((@as(u8, 0xA5) >> @intCast(lane)) & 1 != 0) state.xmm[2] else state.xmm[1];
        @memcpy(blended[lane * 2 ..][0..2], from[lane * 2 ..][0..2]);
    }
    try testing.expectEqualSlices(u8, &blended, &state.xmm[3]);
    try testing.expectEqualSlices(u8, state.xmm[1][8..16], state.xmm[4][0..8]);
    try testing.expectEqualSlices(u8, state.xmm[2][0..8], state.xmm[4][8..16]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0xFFFF_FFFF, 0x8000_0000, 3, 0 }), &state.xmm[5]);
    try testing.expectEqualSlices(u8, &doubles64(.{ 1.5, -2.0 }), &state.xmm[6]);
    try testing.expectEqualSlices(u8, &doubles64(.{ 3.25, @as(f64, @as(f32, 1.0e30)) }), &state.ymm_hi[6]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0, 0xDEAD_BEEF, 0x4242_4242, 0x1234_5678 }), &state.xmm[8]);
    for ([_]usize{ 0, 3, 4, 5, 8 }) |dst| try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[dst]);
    try testing.expectEqual(@as(u32, 0x9FC0), state.regs.mxcsr);
    try testing.expectEqual(@as(u32, 0x9FC0), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expectEqual(@as(u32, 0), state.reads + state.writes);
    try testing.expectEqual(@as(@TypeOf(h.block.fallback_count), 0), h.block.fallback_count);
}

test "shuffles, blends, packs, extends and shifts follow the interpreter's lane rules" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.xmm[1] = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    state.xmm[2] = .{ 15, 0x80, 1, 0x8F, 3, 3, 3, 3, 0, 0, 0, 0, 14, 13, 12, 11 };
    state.xmm[3] = lanes32(.{ 0x0000_9000, 0xFFFF_7000, 0x8000_0000, 0x7FFF_FFFF });
    state.xmm[4] = lanes32(.{ 0x8000_0000, 0x0000_0001, 0x8000_0000, 0x0000_0002 });
    // vpshufb xmm0, xmm1, xmm2 ; vpshufd xmm5, xmm1, 0x1B ; vpunpcklbw xmm6, xmm1, xmm2 ; vpblendvb xmm7, xmm1, xmm2 (mask xmm4)
    try h.add(0x1000, 5, vecRegs(.vpshufb, 0, 1, 2));
    var shufd = vecRegs(.vpshufd, 5, 1, 0);
    shufd.imm = 0x1B;
    try h.add(0x1005, 5, shufd);
    try h.add(0x100A, 4, vecRegs(.vpunpcklbw, 6, 1, 2));
    var blend = vecRegs(.vpblendvb, 7, 1, 2);
    blend.xmm_mask = 4;
    try h.add(0x100E, 5, blend);
    // vpackssdw xmm8, xmm3, xmm4 ; vpmovzxbw xmm9, xmm2 ; vpslld xmm10, xmm3, 33 ; vpsrad xmm11, xmm3, 40 ; vpsrldq xmm12, xmm1, 4 ; vpalignr xmm13, xmm1, xmm2, 4
    try h.add(0x1013, 4, vecRegs(.vpackssdw, 8, 3, 4));
    try h.add(0x1017, 5, vecRegs(.vpmovzxbw, 9, 2, 0));
    var shl = vecRegs(.vpslld, 10, 3, 0);
    shl.imm = 33;
    try h.add(0x101C, 5, shl);
    var sra = vecRegs(.vpsrad, 11, 3, 0);
    sra.imm = 40;
    try h.add(0x1021, 5, sra);
    var srldq = vecRegs(.vpsrldq, 12, 1, 0);
    srldq.imm = 4;
    try h.add(0x1026, 5, srldq);
    var alignr = vecRegs(.vpalignr, 13, 1, 2);
    alignr.imm = 4;
    try h.add(0x102B, 6, alignr);
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 10), completed);
    try testing.expectEqualSlices(u8, &.{ 15, 0, 1, 0, 3, 3, 3, 3, 0, 0, 0, 0, 14, 13, 12, 11 }, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &.{ 12, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3 }, &state.xmm[5]);
    try testing.expectEqualSlices(u8, &.{ 0, 15, 1, 0x80, 2, 1, 3, 0x8F, 4, 3, 5, 3, 6, 3, 7, 3 }, &state.xmm[6]);
    // Mask sign bytes: bytes 3 and 11 of xmm4 are 0x80: those lanes take xmm2.
    try testing.expectEqualSlices(u8, &.{ 0, 1, 2, 0x8F, 4, 5, 6, 7, 8, 9, 10, 0, 12, 13, 14, 15 }, &state.xmm[7]);
    // packssdw: 0x9000 -> 0x7FFF, 0xFFFF7000 (-36864) -> 0x8000, INT_MIN -> 0x8000, INT_MAX -> 0x7FFF; then xmm4's lanes.
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x8000_7FFF, 0x7FFF_8000, 0x0001_8000, 0x0002_8000 }), &state.xmm[8]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x0080_000F, 0x008F_0001, 0x0003_0003, 0x0003_0003 }), &state.xmm[9]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0, 0, 0, 0 }), &state.xmm[10]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0, 0xFFFF_FFFF, 0xFFFF_FFFF, 0 }), &state.xmm[11]);
    try testing.expectEqualSlices(u8, &.{ 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0, 0, 0, 0 }, &state.xmm[12]);
    try testing.expectEqualSlices(u8, &.{ 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 15, 0x80, 1, 0x8F }, &state.xmm[13]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), &state.zmm_hi[0]); // vpshufb is EVEX-routed: cleared (was zero anyway)
}

test "float templates: min and max ordering, compare predicates, conversions, rounding and compare flags" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    const nan: f32 = @bitCast(@as(u32, 0x7FC0_0000));
    state.xmm[1] = floats32(.{ 1.0, nan, -0.0, 2.5 });
    state.xmm[2] = floats32(.{ 2.0, 3.0, 0.0, 2.5 });
    state.xmm[3] = floats32(.{ 3.0e9, -3.0e9, 1.5, nan });
    state.xmm[4] = floats32(.{ 2.5, 3.5, -2.5, 1.0 });
    // vminps xmm0, xmm1, xmm2 ; vmaxps xmm5, xmm1, xmm2 ; vcmpps xmm6, xmm1, xmm2, 1 (lt) ; vcvttps2dq xmm7, xmm3 ; vcvtps2dq xmm8, xmm4 ; vroundps xmm9, xmm4, 0
    try h.add(0x1000, 4, vecRegs(.vminps, 0, 1, 2));
    try h.add(0x1004, 4, vecRegs(.vmaxps, 5, 1, 2));
    var cmp = vecRegs(.vcmpps, 6, 1, 2);
    cmp.imm = 1;
    try h.add(0x1008, 5, cmp);
    try h.add(0x100D, 4, vecRegs(.vcvttps2dq, 7, 0, 3));
    try h.add(0x1011, 4, vecRegs(.vcvtps2dq, 8, 0, 4));
    var round = vecRegs(.vroundps, 9, 0, 4);
    round.imm = 0;
    try h.add(0x1015, 6, round);
    _ = try h.run(&state);
    // min: 1<2 -> 1 ; NaN<3 false -> 3 ; -0<0 false -> 0 ; 2.5<2.5 false -> 2.5
    try testing.expectEqualSlices(u8, &floats32(.{ 1.0, 3.0, 0.0, 2.5 }), &state.xmm[0]);
    // max: 1>2 false -> 2 ; NaN -> 3 ; -0>0 false -> 0 ; -> 2.5
    try testing.expectEqualSlices(u8, &floats32(.{ 2.0, 3.0, 0.0, 2.5 }), &state.xmm[5]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0xFFFF_FFFF, 0, 0, 0 }), &state.xmm[6]);
    // truncating: 3e9 and -3e9 out of range, NaN -> indefinite; 1.5 -> 1
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x8000_0000, 0x8000_0000, 1, 0x8000_0000 }), &state.xmm[7]);
    // rounding half away from zero: 2.5 -> 3, 3.5 -> 4, -2.5 -> -3, 1
    try testing.expectEqualSlices(u8, &lanes32(.{ 3, 4, 0xFFFF_FFFD, 1 }), &state.xmm[8]);
    // round to nearest even: 2.5 -> 2, 3.5 -> 4, -2.5 -> -2, 1
    try testing.expectEqualSlices(u8, &floats32(.{ 2.0, 4.0, -2.0, 1.0 }), &state.xmm[9]);

    // A signalling NaN survives vroundps unchanged; vucomiss sets ZF|PF|CF
    // for an unordered pair, CF for less, ZF for equal.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.xmm[1] = lanes32(.{ 0x7F80_0001, 0x3F80_0000, 0, 0 });
    state.xmm[2] = floats32(.{ 1.0, 2.0, 0, 0 });
    state.xmm[3] = floats32(.{ 1.0, 0, 0, 0 });
    state.regs.rflags = 0x2 | RFL_OF | RFL_SF;
    round = vecRegs(.vroundps, 0, 0, 1);
    round.imm = 3;
    try h.add(0x1000, 6, round);
    try h.add(0x1006, 4, vecRegs(.vucomiss, 0, 1, 2)); // SNaN vs 1.0: unordered
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x7F80_0001), std.mem.readInt(u32, state.xmm[0][0..4], .little));
    try testing.expectEqual(@as(u32, 0x2 | RFL_ZF | RFL_PF | RFL_CF), state.regs.rflags);
    h.insns.clearRetainingCapacity();
    state.regs.rflags = 0x2;
    try h.add(0x1000, 4, vecRegs(.vucomiss, 0, 3, 2)); // 1.0 vs 1.0: equal
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x2 | RFL_ZF), state.regs.rflags);
    h.insns.clearRetainingCapacity();
    state.regs.rflags = 0x2;
    try h.add(0x1000, 4, vecRegs(.vucomiss, 0, 2, 1)); // 1.0 (lane 0 of xmm2) vs SNaN: unordered again
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x2 | RFL_ZF | RFL_PF | RFL_CF), state.regs.rflags);

    // Scalar conversions: NaN and 2^31 give the indefinite value, a
    // double just under 2^31 rounds to a legitimate INT_MAX, negatives
    // saturate to INT_MIN, and vcvtsi2sd / vcvtsd2ss merge into lane 0.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    var doubles: [16]u8 = undefined;
    std.mem.writeInt(u64, doubles[0..8], @bitCast(@as(f64, 2147483647.4)), .little);
    std.mem.writeInt(u64, doubles[8..16], @bitCast(@as(f64, 2147483648.0)), .little);
    state.xmm[1] = doubles;
    var big: [16]u8 = undefined;
    std.mem.writeInt(u64, big[0..8], @bitCast(@as(f64, 2147483648.0)), .little);
    std.mem.writeInt(u64, big[8..16], @bitCast(@as(f64, -1.0e12)), .little);
    state.xmm[2] = big;
    state.xmm[3] = floats32(.{ nan, 0, 0, 0 });
    state.regs.r8 = @bitCast(@as(i64, -7));
    var cvt1: DecodedInsn = .{ .op = .vcvtsd2si, .size = .bits32, .dst_reg = .al_ax_eax_rax, .xmm_src = 1, .is_reg_form = true };
    try h.add(0x1000, 5, cvt1);
    var cvt2: DecodedInsn = .{ .op = .vcvttsd2si, .size = .bits32, .dst_reg = .cl_cx_ecx_rcx, .xmm_src = 2, .is_reg_form = true };
    try h.add(0x1005, 5, cvt2);
    var cvt3: DecodedInsn = .{ .op = .vcvttss2si, .size = .bits64, .dst_reg = .dl_dx_edx_rdx, .xmm_src = 3, .is_reg_form = true };
    try h.add(0x100A, 5, cvt3);
    var cvt4: DecodedInsn = .{ .op = .vcvtsi2sd_xmm_reg, .size = .bits64, .src_reg = .r8b_r8w_r8d_r8, .xmm_dst = 4, .xmm_src = 1, .is_reg_form = true };
    try h.add(0x100F, 5, cvt4);
    try h.add(0x1014, 4, vecRegs(.vcvtsd2ss, 5, 3, 4));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x7FFF_FFFF), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x8000_0000), state.regs.rcx);
    try testing.expectEqual(@as(u64, 0x8000_0000_0000_0000), state.regs.rdx);
    try testing.expectEqual(@as(u64, @bitCast(@as(f64, -7.0))), std.mem.readInt(u64, state.xmm[4][0..8], .little));
    try testing.expectEqual(@as(u64, @bitCast(@as(f64, 2147483648.0))), std.mem.readInt(u64, state.xmm[4][8..16], .little));
    try testing.expectEqual(@as(u32, @bitCast(@as(f32, -7.0))), std.mem.readInt(u32, state.xmm[5][0..4], .little));
    try testing.expectEqualSlices(u8, state.xmm[3][4..16], state.xmm[5][4..16]);
    _ = &cvt1;
    _ = &cvt2;
    _ = &cvt3;
    _ = &cvt4;
}

test "general-register transfers, extract, insert and broadcast" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rax = 0xFFFF_FFFF_1234_5678;
    state.regs.rcx = 0x0102_0304_0506_0708;
    state.xmm[1] = lanes32(.{ 0xAAAA_AAAA, 0xBBBB_BBBB, 0xCCCC_CCCC, 0xDDDD_DDDD });
    state.ymm_hi[2] = @splat(0x11);
    std.mem.writeInt(u32, state.memory[0x130..][0..4], 0x3F80_0000, .little);
    // vmovd xmm2, eax ; vmovq xmm3, rcx ; vmovd edx, xmm1 ; vmovq rsi, xmm1 ; vpextrd edi, xmm1, 2 ; vpinsrd xmm4, xmm1, eax, 1 ; vbroadcastss xmm5, [rbx + 0x30]
    var movd: DecodedInsn = .{ .op = .vmovd_xmm_reg32, .size = .bits32, .src_reg = .al_ax_eax_rax, .xmm_dst = 2, .is_reg_form = true };
    try h.add(0x1000, 4, movd);
    var movq: DecodedInsn = .{ .op = .vmovq_xmm_reg64, .size = .bits64, .src_reg = .cl_cx_ecx_rcx, .xmm_dst = 3, .is_reg_form = true };
    try h.add(0x1004, 5, movq);
    var movd_out: DecodedInsn = .{ .op = .vmovd_reg32_xmm, .size = .bits32, .dst_reg = .dl_dx_edx_rdx, .xmm_src = 1, .is_reg_form = true };
    try h.add(0x1009, 4, movd_out);
    var movq_out: DecodedInsn = .{ .op = .vmovq_reg64_xmm, .size = .bits64, .dst_reg = .dh_si_esi_rsi, .xmm_src = 1, .is_reg_form = true };
    try h.add(0x100D, 5, movq_out);
    var extract: DecodedInsn = .{ .op = .vpextrd, .size = .bits32, .dst_reg = .bh_di_edi_rdi, .xmm_src = 1, .imm = 2, .is_reg_form = true };
    try h.add(0x1012, 6, extract);
    var insert: DecodedInsn = .{ .op = .vpinsrd, .size = .bits32, .src_reg = .al_ax_eax_rax, .xmm_dst = 4, .xmm_src = 1, .imm = 1, .is_reg_form = true };
    try h.add(0x1018, 6, insert);
    try h.add(0x101E, 5, vecMem(.vbroadcastss, 5, 0, 0x30));
    _ = try h.run(&state);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x1234_5678, 0, 0, 0 }), &state.xmm[2]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[2]);
    try testing.expectEqual(@as(u64, 0x0102_0304_0506_0708), std.mem.readInt(u64, state.xmm[3][0..8], .little));
    try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.xmm[3][8..16], .little));
    try testing.expectEqual(@as(u64, 0xAAAA_AAAA), state.regs.rdx);
    try testing.expectEqual(@as(u64, 0xBBBB_BBBB_AAAA_AAAA), state.regs.rsi);
    try testing.expectEqual(@as(u64, 0xCCCC_CCCC), state.regs.rdi);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0xAAAA_AAAA, 0x1234_5678, 0xCCCC_CCCC, 0xDDDD_DDDD }), &state.xmm[4]);
    try testing.expectEqualSlices(u8, &floats32(.{ 1.0, 1.0, 1.0, 1.0 }), &state.xmm[5]);
    try testing.expectEqual(@as(u32, 0), state.reads);
    _ = &movd;
    _ = &movq;
    _ = &movd_out;
    _ = &movq_out;
    _ = &extract;
    _ = &insert;
}

test "ret is native, and every instrument its interpreter arm carries still stops it" {
    var h = try TestHarness.init();
    defer h.deinit();

    // A return address sitting at rsp inside the harness's guest page.
    const stack: u64 = 0x100;
    const return_rip: u64 = 0x1234_5678;

    // The plain case: pop into RIP, rsp += 8, and the interpreter is never
    // asked. This is the 2,162,247,062-call path.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        std.mem.writeInt(u64, state.memory[stack..][0..8], return_rip, .little);
        h.insns.clearRetainingCapacity();
        try h.add(0xB000, 1, .{ .op = .ret });
        const completed = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), completed);
        try testing.expectEqual(return_rip, state.regs.rip);
        try testing.expectEqual(stack + 8, state.regs.rsp);
        try testing.expectEqual(@as(u32, 0), state.interprets);
    }

    // Each guard hands the instruction back with nothing mutated, so the
    // interpreter sees exactly the machine the instruction started on.
    const Guard = struct { trace_calls: bool, captures: u32, value: u64 };
    for ([_]Guard{
        // The ABI call stack is fed from the interpreter's arm.
        .{ .trace_calls = true, .captures = 0, .value = return_rip },
        // A return capture completes on this boundary.
        .{ .trace_calls = false, .captures = 1, .value = return_rip },
        // A zero return address is the cooperative worker's completion
        // marker, which the interpreter recognises and reports.
        .{ .trace_calls = false, .captures = 0, .value = 0 },
    }) |guard| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.trace_calls = guard.trace_calls;
        state.return_captures = guard.captures;
        std.mem.writeInt(u64, state.memory[stack..][0..8], guard.value, .little);
        h.insns.clearRetainingCapacity();
        try h.add(0xB000, 1, .{ .op = .ret });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(@as(u32, 0), state.last_interpret_index);
        // Nothing was committed before the hand-back: rsp is untouched, and
        // RIP is where the harness's interpreter stub put it rather than
        // anywhere this template chose.
        try testing.expectEqual(stack, state.regs.rsp);
    }

    // `ret imm16` decodes to the same op with a pop count the interpreter's
    // arm does not apply. Reproducing that here would bake the discrepancy
    // into translated code, so the template declines it.
    try testing.expect(!isNative(.{ .op = .ret, .imm = 4 }));
    try testing.expect(isNative(.{ .op = .ret, .imm = 0 }));

    // A faulting pop leaves through the abort path with the instruction not
    // retired, and never reaches the commit.
    {
        var state = TestState{};
        state.regs.rsp = stack;
        state.abort_on_access = true;
        std.mem.writeInt(u64, state.memory[stack..][0..8], return_rip, .little);
        h.insns.clearRetainingCapacity();
        try h.add(0xB000, 1, .{ .op = .ret });
        _ = try h.run(&state);
        try testing.expectEqual(stack, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0xB001), state.regs.rip);
    }
}

test "an indirect transfer outside the image is native; inside it, or to zero, the interpreter has it" {
    var h = try TestHarness.init();
    defer h.deinit();
    const stack: u64 = 0x200;
    // call rbx, to a target outside the image: push and jump.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0xA000_1000;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u64, 0xA000_1000), state.regs.rip);
        try testing.expectEqual(stack - 8, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0xC002), std.mem.readInt(u64, state.memory[stack - 8 ..][0..8], .little));
    }
    // The same call into the image, and a jump to zero: handed back with
    // the stack untouched.
    for ([_]u64{ 0x1_4000_2000, 0 }) |target| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = target;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = if (target == 0) .jmp_reg64 else .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(stack, state.regs.rsp);
    }
    // With the filter built, an image target the filter does not name is
    // native, one it names is the interpreter's.
    for ([_]bool{ false, true }) |hooked| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0x1_4000_2000;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        state.image_targets_hooked = 0;
        if (hooked) hookFilterAdd(&state.hook_filter, 0x1_4000_2000);
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, if (hooked) 1 else 0), state.interprets);
        try testing.expectEqual(if (hooked) stack else stack - 8, state.regs.rsp);
    }
    // call [rbx + 0x20]: an operand in the import address table is the
    // dynamic-function shim's; one elsewhere (a vtable) is native.
    for ([_]bool{ true, false }) |in_iat| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0x100;
        std.mem.writeInt(u64, state.memory[0x120..][0..8], 0xA000_3000, .little);
        state.image_targets_hooked = 0;
        state.iat_low = if (in_iat) 0x100 else 0x800;
        state.iat_high = if (in_iat) 0x200 else 0x900;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 3, baseDisp(.call_mem64, .bits64, .al_ax_eax_rax, 0x20));
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, if (in_iat) 1 else 0), state.interprets);
        if (!in_iat) try testing.expectEqual(@as(u64, 0xA000_3000), state.regs.rip);
    }
    // jmp rbx outside the image sets RIP and pushes nothing.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0xA000_2000;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .jmp_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u64, 0xA000_2000), state.regs.rip);
        try testing.expectEqual(stack, state.regs.rsp);
    }
}

test "a direct call pushes its return address natively and still ends the block" {
    var h = try TestHarness.init();
    defer h.deinit();
    const stack: u64 = 0x200;

    // mov rax, rbx ; call +0x100. The call is the block's last instruction
    // whether or not it is native, and the pushed value is the address of
    // the instruction after it.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rbx = 7;
        state.regs.rsp = stack;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 3, regReg(.mov_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        try h.add(0xC003, 5, .{ .op = .call_rel32, .imm = 0x100 });
        const completed = try h.run(&state);
        try testing.expectEqual(@as(u32, 2), completed);
        try testing.expectEqual(@as(u64, 0xC008 + 0x100), state.regs.rip);
        try testing.expectEqual(stack - 8, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0xC008), std.mem.readInt(u64, state.memory[stack - 8 ..][0..8], .little));
        try testing.expectEqual(@as(u64, 7), state.regs.rax);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u32, 2), h.block.native_count);
    }

    // Either transfer trace hands the instruction back with the stack
    // untouched, so the interpreter's arm sees the machine it expects.
    for ([_]bool{ true, false }) |messages| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.trace_transfers = messages;
        state.trace_calls = !messages;
        h.insns.clearRetainingCapacity();
        try h.add(0xC003, 5, .{ .op = .call_rel32, .imm = 0x100 });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(stack, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.memory[stack - 8 ..][0..8], .little));
    }

    // A push that faults leaves through the abort path: the block stops at
    // the call without retiring it, and RIP is the call's own address plus
    // its length rather than the target.
    {
        var state = TestState{};
        state.regs.rsp = stack;
        state.abort_on_access = true;
        h.insns.clearRetainingCapacity();
        try h.add(0xC003, 5, .{ .op = .call_rel32, .imm = 0x100 });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 0xC008), state.regs.rip);
    }
}

test "emitted code writes the scratch index and vector slot before any helper reads them" {
    // The glue resets only `abort` and `block` between executions, because
    // the state escapes into the helpers and zeroing the rest is a store it
    // cannot optimise away. That is sound only while every helper that reads
    // `index` or the vector slot is preceded by emitted code writing it.
    // Poison both and prove the helpers never see the poison.
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.scratch.index = 0xDEAD;
    state.scratch.vector = @splat(0xA5);
    state.regs.rbx = 0x100;
    std.mem.writeInt(u64, state.memory[0x100..][0..8], 0x1122_3344_5566_7788, .little);

    // A load through the helper (the TLB is empty, so the slow path runs),
    // then an instruction with no template at all.
    var load: DecodedInsn = .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .al_ax_eax_rax };
    load.sib_has_base = true;
    load.sib_base_reg = .bl_bx_ebx_rbx;
    try h.add(0x9000, 3, load);
    try h.add(0x9003, 1, .{ .op = .lahf, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    state.interpret_result = 1;
    _ = try h.run(&state);

    // The read helper was told instruction 0 and the interpreter helper
    // instruction 1; neither saw 0xDEAD. `interpret` itself cross-checks the
    // scratch index against its argument and pokes r15 when they disagree.
    try testing.expectEqual(@as(u32, 1), state.reads);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u32, 1), state.last_interpret_index);
    try testing.expect(state.regs.r15 != 0xBAD_1DE7);
    try testing.expectEqual(@as(u64, 0x1122_3344_5566_7788), state.regs.rax);

    // A 128-bit store fills the vector slot from the register file first, so
    // a poisoned slot never reaches the write helper either.
    var state2 = TestState{};
    state2.scratch.vector = @splat(0xA5);
    state2.xmm[1] = @splat(0x3C);
    state2.regs.rbx = 0x200;
    h.insns.clearRetainingCapacity();
    const vstore = vecMem(.vmovups_mem_xmm, 0, 1, 0);
    try testing.expect(isNative(vstore));
    try h.add(0x9000, 4, vstore);
    _ = try h.run(&state2);
    try testing.expectEqual(@as(u32, 1), state2.writes);
    try testing.expectEqualSlices(u8, &[_]u8{0x3C} ** 16, state2.memory[0x200..][0..16]);
}

test "emitted code size per instruction, and a trace costing less than its basic blocks" {
    // A census rather than an exact check: these are the numbers that decide
    // what is worth optimising, and a silent regression in any of them is a
    // silent regression in the whole translated lane. Bounds are generous
    // enough that an unrelated encoding change does not fail, and tight
    // enough that a doubling does.
    var h = try TestHarness.init();
    defer h.deinit();
    const Sizes = struct {
        fn of(hh: *TestHarness) !usize {
            const insns = hh.insns.items;
            const last = insns[insns.len - 1];
            const compiled = try compile(testing.allocator, &hh.memory, TestState.layout, insns, last.rip + last.len);
            return compiled.code.len;
        }
        fn single(hh: *TestHarness, rip: u64, len: u8, d: DecodedInsn) !usize {
            hh.insns.clearRetainingCapacity();
            try hh.add(rip, len, d);
            return of(hh);
        }
    };

    // The fixed cost of being a block at all: prologue, exit stub, epilogue.
    // `mov r64,r64` is two instructions of actual work on top of it, so this
    // is what every additional block execution pays for nothing.
    const overhead = try Sizes.single(&h, 0x1000, 3, regReg(.mov_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx)) - 2;
    // The chain attempt lives here too: a block's exit records what it ran
    // and decides whether to jump straight into its successor. Four link
    // ways cost five words each before the one shared proof.
    try testing.expect(overhead >= 15 and overhead <= 110);

    // Flags dominate arithmetic: an `add` is one instruction of arithmetic
    // and about thirty of flag materialisation. This is the largest single
    // item left in the translated lane and the reason lazy flags is the next
    // structural change worth making.
    const add_cost = try Sizes.single(&h, 0x1000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx)) - overhead;
    // Was 32 before the deferred record: an `add` is one instruction of
    // arithmetic, a handful of stores, and only the flags a later
    // instruction in the same block actually reads.
    try testing.expect(add_cost >= 20 and add_cost <= 44);

    // A guest memory access is a TLB probe plus an out-of-line helper call.
    var load: DecodedInsn = .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .al_ax_eax_rax };
    load.sib_has_base = true;
    load.sib_base_reg = .bl_bx_ebx_rbx;
    const load_cost = try Sizes.single(&h, 0x1000, 3, load) - overhead;
    try testing.expect(load_cost >= 12 and load_cost <= 40);

    // Three basic blocks of `cmp; jcc; add` as one trace, against what the
    // same nine instructions cost as three separate blocks. The words saved
    // are the smaller half of the win: the larger half is two block
    // executions that never happen, each of which is an indirect call into
    // the translation cache and a probe of a two-megabyte table.
    var jcc: DecodedInsn = .{ .op = .jcc_rel8, .cond = .ne, .addr = 0x20 };
    jcc.rip_relative = true;
    h.insns.clearRetainingCapacity();
    var rip: u64 = 0x6000;
    for (0..3) |_| {
        try h.add(rip, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
        try h.add(rip, 2, jcc);
        rip += 2;
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    const trace_words = try Sizes.of(&h);
    const cmp_cost = try Sizes.single(&h, 0x1000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx)) - overhead;
    const jcc_cost = try Sizes.single(&h, 0x1000, 2, jcc) - overhead;
    const separate = 3 * overhead + 3 * cmp_cost + 3 * jcc_cost + 3 * add_cost;
    try testing.expect(trace_words < separate);
}

test "a block continues across a conditional branch and its taken edge still leaves" {
    var h = try TestHarness.init();
    defer h.deinit();
    // cmp rax, rbx ; jne +0x20 ; add rax, rbx
    var jcc: DecodedInsn = .{ .op = .jcc_rel8, .cond = .ne, .addr = 0x20 };
    jcc.rip_relative = true;

    for ([_]bool{ true, false }) |equal| {
        var state = TestState{};
        state.regs.rax = 10;
        state.regs.rbx = if (equal) 10 else 11;
        h.insns.clearRetainingCapacity();
        try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        try h.add(0x6003, 2, jcc);
        try h.add(0x6005, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        const completed = try h.run(&state);
        if (equal) {
            // Not taken: the trace runs straight on into the add, which is
            // the whole point - no exit, no second block, no hash probe.
            try testing.expectEqual(@as(u32, 3), completed);
            try testing.expectEqual(@as(u64, 20), state.regs.rax);
            try testing.expectEqual(@as(u64, 0x6008), state.regs.rip);
        } else {
            // Taken: the edge leaves through its stub, with the two
            // instructions before it retired and the add untouched.
            try testing.expectEqual(@as(u32, 2), completed);
            try testing.expectEqual(@as(u64, 10), state.regs.rax);
            try testing.expectEqual(@as(u64, 0x6025), state.regs.rip);
        }
        // All three were compiled into one block either way.
        try testing.expectEqual(@as(u32, 3), h.block.native_count);
    }

    // The branch's taken edge is a block exit, so the flags of the compare
    // before it are live even though the add after it overwrites them.
    // Without that, the taken edge would leave holding stale flags.
    h.insns.clearRetainingCapacity();
    try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x6003, 2, jcc);
    try h.add(0x6005, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var state = TestState{};
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), h.flags_elided);

    // Take the branch out and the compare's flags are dead, because the add
    // overwrites every one of them before anything can read them.
    h.insns.clearRetainingCapacity();
    try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x6003, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var state2 = TestState{};
    _ = try h.run(&state2);
    try testing.expectEqual(@as(u32, 1), h.flags_elided);

    // A conditional branch that is the block's last instruction still emits
    // both edges, because there is no next instruction to fall into.
    h.insns.clearRetainingCapacity();
    try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x6003, 2, jcc);
    var state3 = TestState{};
    state3.regs.rax = 1;
    state3.regs.rbx = 1;
    try testing.expectEqual(@as(u32, 2), try h.run(&state3));
    try testing.expectEqual(@as(u64, 0x6005), state3.regs.rip);
}

test "busy guest registers live in host registers for a whole block, and meet memory at every boundary" {
    var h = try TestHarness.init();
    defer h.deinit();

    // rax is read and written by every instruction, rbx read by every one:
    // both cross the threshold and are cached.
    h.insns.clearRetainingCapacity();
    var rip: u64 = 0x8000;
    for (0..4) |_| {
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    const insns = h.insns.items;
    const last = insns[insns.len - 1];
    const compiled = try compile(testing.allocator, &h.memory, TestState.layout, insns, last.rip + last.len);
    try testing.expect(compiled.cached_registers >= 2);

    // Executed, the cached arithmetic retires exactly what memory would have.
    var state = TestState{};
    state.regs.rax = 1;
    state.regs.rbx = 10;
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 41), state.regs.rax);
    try testing.expectEqual(@as(u64, 10), state.regs.rbx);

    // Every sub-register width merges into the cached copy exactly as x86
    // writes it: 32 zero-extends, 16 and both 8-bit halves merge.
    h.insns.clearRetainingCapacity();
    rip = 0x8100;
    for (0..3) |_| {
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    try h.add(rip, 2, regReg(.mov_reg32_reg32, .bits32, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    rip += 2;
    var state2 = TestState{};
    state2.regs.rax = 0xFFFF_FFFF_0000_0000;
    state2.regs.rbx = 0x1111_1111_2222_2222;
    _ = try h.run(&state2);
    // mov eax, ebx: the upper half of rax is cleared, not kept.
    try testing.expectEqual(@as(u64, 0x2222_2222), state2.regs.rax);

    var high8: DecodedInsn = regReg(.mov_reg8_reg8, .bits8, .al_ax_eax_rax, .bl_bx_ebx_rbx);
    high8.dst_high8 = true; // mov ah, bl
    h.insns.clearRetainingCapacity();
    rip = 0x8200;
    for (0..3) |_| {
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    try h.add(rip, 2, high8);
    var state3 = TestState{};
    state3.regs.rax = 0x1122_3344_5566_7700;
    state3.regs.rbx = 0x01;
    _ = try h.run(&state3);
    // Three adds of 1, then bl (0x01) into ah only.
    try testing.expectEqual(@as(u64, 0x1122_3344_5566_0103), state3.regs.rax);

    // An instruction with no template in the middle: the interpreter sees
    // the cache's values in memory, and whatever it writes comes back.
    h.insns.clearRetainingCapacity();
    rip = 0x8300;
    for (0..3) |_| {
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    try h.add(rip, 1, .{ .op = .lahf, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    rip += 1;
    try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var state4 = TestState{};
    state4.regs.rax = 5;
    state4.regs.rbx = 2;
    state4.interpret_result = 0;
    _ = try h.run(&state4);
    // 5 + 2*3 = 11 in memory before the interpreter; its stub advances RIP
    // and leaves rax alone, so the add after it reads 11 back, not 5.
    try testing.expectEqual(@as(u32, 1), state4.interprets);
    try testing.expectEqual(@as(u64, 13), state4.regs.rax);
}
