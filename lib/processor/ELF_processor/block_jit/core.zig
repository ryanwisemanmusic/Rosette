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
const testing = std.testing;
const a64 = @import("arm64_encode");
const host_fp_control = @import("../host_fp_control.zig");
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
    /// Publish prior temporal stores and perform a guest non-temporal vector
    /// write through the memory-class-aware path. This must not use the
    /// ordinary direct-TLB store template, which has no store-buffer state.
    write128_non_temporal: *const fn (state: *anyopaque, address: u64, value: *const [16]u8) callconv(.c) void,
    /// Whether an otherwise external indirect target is inside the known
    /// executable Xenia code-cache view and is not owned by a runtime hook.
    /// Returns 0 to leave the transfer to the interpreter.
    mapped_transfer: *const fn (state: *anyopaque, target: u64) callconv(.c) u8,
    /// Exact counterpart to the image hook Bloom filter. A positive Bloom
    /// bit is only a candidate: retired census hooks and hash collisions must
    /// not force a hot indirect transfer through the interpreter forever.
    /// Returns 1 only when the current runtime still owns this exact target.
    hooked_transfer: *const fn (state: *anyopaque, target: u64) callconv(.c) u8,
    /// A `call [slot]` or `jmp [slot]` through an import address table slot,
    /// answered on one of the runtime's lock-free import lanes without
    /// leaving translated code. `call_return` is the call's next RIP, or 0
    /// for a jump - a thunk's tail call, whose return address is on the guest
    /// stack. Returns 1 when the import completed: RIP is the return address
    /// and, for a jump, the return address has been popped. Returns 0 with
    /// nothing changed, and the instruction takes the interpreter's import
    /// path.
    import_transfer: *const fn (state: *anyopaque, slot: u64, call_return: u64) callconv(.c) u32,
    /// Execute one raw x87 stack copy/80-bit transfer without entering the
    /// general instruction interpreter. The helper owns the guest x87 stack
    /// and memory-fault contract; zero means the translated block may continue.
    x87_raw_transfer: *const fn (state: *anyopaque, block: *const Block, index: u32) callconv(.c) u32,
    /// Execute one x87 arithmetic/comparison memory operand without entering
    /// the general instruction interpreter. This remains a helper because the
    /// guest x87 format and status are modeled in Rosette, but lets the rest of
    /// a hot block stay translated.
    x87_memory: *const fn (state: *anyopaque, block: *const Block, index: u32) callconv(.c) u32,
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
const helper_write128_non_temporal_offset: u32 = @offsetOf(Helpers, "write128_non_temporal");
const helper_mapped_transfer_offset: u32 = @offsetOf(Helpers, "mapped_transfer");
const helper_hooked_transfer_offset: u32 = @offsetOf(Helpers, "hooked_transfer");
const helper_import_transfer_offset: u32 = @offsetOf(Helpers, "import_transfer");
const helper_x87_raw_transfer_offset: u32 = @offsetOf(Helpers, "x87_raw_transfer");
const helper_x87_memory_offset: u32 = @offsetOf(Helpers, "x87_memory");
const helper_interpret_offset: u32 = @offsetOf(Helpers, "interpret");
const helper_block_offset: u32 = @offsetOf(Helpers, "block");
const helper_flags_offset: u32 = @offsetOf(Helpers, "flags");

/// The block's view of the state it is running in, written by emitted code
/// and read by the helpers. Lives inside the state at `Layout.scratch_offset`
/// for inline layouts; with `.pointers_in_scratch` it is the executing guest
/// context's own record, and the block's entry receives it directly.
pub const Scratch = extern struct {
    /// Set to nonzero by a helper when the block must stop after the current
    /// instruction (a fault is pending or the run ended).
    abort: u8 = 0,
    /// Nonzero when a `call`, an indirect `jmp`, or a `ret` must go to the
    /// interpreter's arm: a call or transfer trace is on, or - for `ret` -
    /// this thread has a return capture armed. The glue sets them at every
    /// entry and when a capture is armed or completed; each check is then
    /// one byte load beside `abort`, where reading the state's own fields
    /// took five instructions each.
    call_guard: u8 = 0,
    jmp_guard: u8 = 0,
    ret_guard: u8 = 0,
    /// Published at entry only when the parallel direct-memory executor has
    /// no guest store queue. Streaming stores may then use the admitted
    /// write page with release ordering; all other modes drain via a helper.
    direct_non_temporal: u8 = 0,
    /// The index of the instruction about to call a helper, stored by the
    /// emitted code just before the call, so the helper can name the
    /// instruction (its RIP, op and length) without the code materialising
    /// any of them.
    index: u32 = 0,
    /// The block being executed, set by the glue before entry.
    block: ?*const Block = null,
    /// The executing context's register files and TLB, for layouts with
    /// `.register_files = .pointers_in_scratch`: the glue binds them before
    /// entry and the prologue loads them from here. Kept in this record
    /// rather than in the shared state so that guest threads on different
    /// host threads, each running translated code, cannot overwrite each
    /// other's binding - the record is per context, the state is not.
    regs_file: u64 = 0,
    xmm_file: u64 = 0,
    ymm_hi_file: u64 = 0,
    zmm_hi_file: u64 = 0,
    tlb_file: u64 = 0,
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
    /// for the scheduler. A helper that sets `abort` sets this too, so the
    /// native chain reads only this word before every hop.
    chain_break: u32 = 0,
    chain_reserved: u32 = 0,
    /// What every block that left through `exit_path` since the glue's entry
    /// retired, `instructions << chain_count_shift | blocks`: one add of
    /// `x0 << shift` and one of 1 per block. The glue accounts a whole chain
    /// from this, the two ledgers below and the last block - which is what
    /// let the chain stop being bounded by a 64-entry log. The log forced a
    /// return to the glue every 64 blocks; Halo 3's main thread made 83.8
    /// million such round trips on 2026-10-01.
    chain_count: u64 = 0,
    /// The chain leaves once `chain_count` reaches this: the glue's remaining
    /// instruction budget, shifted the same way.
    chain_budget: u64 = 0,
    /// The instructions in `chain_count` that image blocks retired, and
    /// those mapped blocks outside the code cache retired. The rest ran in
    /// the code cache, which is where nearly every hop is, so the common
    /// block pays nothing for either code-fetch ledger.
    chain_retired_image: u64 = 0,
    chain_retired_other_mapped: u64 = 0,
    /// The block that hopped to `block`, for the stack-collapse report.
    chain_previous: ?*const Block = null,
    /// This thread's jump cache (`jump_cache_entries` links), or null.
    jump_cache: ?[*]Link = null,
    /// A fused flag writer's operands and result, kept while the readers
    /// after it reach memory (whose probes and helpers reuse every
    /// temporary): what an exit in the middle of the run derives the x86
    /// flags from. And NZCV across a helper call inside such a run.
    fused_a: u64 = 0,
    fused_b: u64 = 0,
    fused_r: u64 = 0,
    saved_nzcv: u64 = 0,
    /// The skip counter (`skip_reg`) across a helper call, which clobbers
    /// it.
    skip_spill: u64 = 0,
    /// FPCR writes the translated `ldmxcsr` made since the glue last
    /// harvested this count: loads that changed FZ or RMode. A load that
    /// leaves them as they are writes nothing, because `msr fpcr` costs
    /// about 3 ns even then and about 12 ns with stores in flight when it
    /// changes them (M2 Max, 2026-10-11): Xenia reloads MXCSR around every
    /// switch between PowerPC FPU and VMX code and after every host call.
    fpcr_writes: u64 = 0,
};

/// `Scratch.chain_count` keeps blocks below this bit and instructions above.
pub const chain_count_shift: u6 = 24;
pub const chain_count_blocks_mask: u64 = (@as(u64, 1) << chain_count_shift) - 1;

/// Page pointers local to a block. x29 is callee-saved; x30's caller return
/// address is on the stack, and helper calls preserve its page pointer in
/// a separate stack slot. Neither pointer survives a block boundary.
const hoist_hosts = [_]a64.Reg{ 29, 30 };
/// The widest displacement span one hoist covers: one page. Xenia's PowerPC
/// contexts are page-aligned and about 0xB00 bytes, so every span through
/// rsi - general and vector registers together - is admitted; a base at a
/// random offset with a wide span falls back to the ordinary probe.
const hoist_max_span: u64 = 4096;
const hoist_disp_bias: u64 = 1 << 63;

const HoistCandidate = struct { base: ?RegId, disp: u64, bytes: u64 };
const Hoist = struct {
    planned: bool = false,
    /// null represents an absolute or RIP-relative operand.
    base: ?RegId = null,
    dmin: u64 = 0,
    span: u64 = 0,
    aligned: bool = false,
    write: bool = false,
    live: bool = false,
};
const HoistedOffset = struct { slot: usize, offset: u64 };

const FusedExit = struct {
    label: Label,
    fused: Fused,
    /// The x86 flags the edge must find in `rflags`.
    owed: u8,
    stub: Label,
};

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
    /// Emitted inside a fused flag run: the out-of-line probe and helper
    /// must leave NZCV as they found it.
    nzcv_live: bool = false,
    /// The access is its instruction's last effect, so the abort check
    /// belongs after the helper in this out-of-line path, the only place
    /// `abort` can be set - not on the hot path after every access.
    abort_exit: ?ColdAbortExit = null,
    /// Where a load's value goes (the helper returns it in x0), and where a
    /// store's value is (the helper takes it in x3).
    dest: a64.Reg = 0,
    value: a64.Reg = 3,
};

const ColdAbortExit = struct {
    completed: u32,
    next_rip: u64,
    /// The fused run the access is inside, whose flags the exit owes.
    fused: ?Fused,
};

/// The paths of a probed scalar access that a TLB hit never runs - the
/// byte-by-byte access of an unaligned operand and the helper call on a
/// miss - emitted after the block body (`emitColdMemory`). Inline, every
/// access's hot path ended in a taken branch over about twenty-five words
/// it does not run, in the middle of the code the next access fetches.
const ColdMemory = struct {
    /// The unaligned operand's path, for a 2- to 8-byte access.
    unaligned: ?Label,
    slow: Label,
    done: Label,
    size: Size,
    index: u32,
    is_write: bool,
    /// A read's destination (the helper returns the value in x0).
    dest: a64.Reg,
    /// The access is inside a fused flag run: the probe and the helper
    /// must leave NZCV as they found it.
    nzcv_live: bool,
};

/// An operand whose address depends on at most one guest register. Indexed,
/// segmented and 32-bit address arithmetic retain their ordinary probes.
fn hoistCandidate(insn: Insn) ?HoistCandidate {
    const d = insn.decoded;
    if (insn.force_fallback or !isNative(d)) return null;
    if (d.is_reg_form or d.sib_has_index or d.has_0x67) return null;
    if (insn.segment == .fs or insn.segment == .gs or d.op == .lea_reg_mem or d.op == .vzeroupper) return null;
    if (!isVectorNative(d) and std.mem.indexOf(u8, @tagName(d.op), "_mem") == null) return null;
    // A vector operand is read or written as whole 16-byte halves.
    const bytes: u64 = if (isVectorNative(d)) (if (d.vector_256) 32 else 16) else @max(bits(d.size) / 8, 1);
    if (d.rip_relative) return .{ .base = null, .disp = insn.rip +% d.len +% d.addr, .bytes = bytes };
    return .{ .base = if (d.sib_has_base) d.sib_base_reg else null, .disp = d.addr, .bytes = bytes };
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

/// Whether an access needs no page-span check after its TLB hit: a
/// power-of-two access the caller aligns naturally cannot leave its page.
fn tlbProbeSpanProven(access_bytes: u64, alignment_guarded: bool) bool {
    if (access_bytes <= 1) return true;
    return alignment_guarded and std.math.isPowerOfTwo(access_bytes) and access_bytes <= Tlb.page_bytes;
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
    /// GPU Commands reported 727 million admitted-page fills in the
    /// 2026-10-06 run. Keep the table at 32K entries: growing the inline
    /// read/write pair beyond 1 MiB per executor makes test and worker stack
    /// frames too large, while the folded index addresses the observed
    /// aliasing without increasing the hot-path footprint.
    pub const entries: usize = 32768;
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
        self.invalidateRangeTables(base, length, true, true);
    }

    /// The same for the read table, the write table, or both: a page made
    /// read-only keeps its read entries.
    pub fn invalidateRangeTables(self: *Tlb, base: u64, length: u64, reads: bool, writes: bool) void {
        if (length == 0 or !(reads or writes)) return;
        const first = base >> page_shift;
        const last = (base +| (length - 1)) >> page_shift;
        if (last - first + 1 >= @min(entries, invalidate_scan_limit)) {
            self.flush(reads, writes);
            return;
        }
        var tag = first;
        while (true) : (tag += 1) {
            const slot = index(tag);
            if (reads and self.read[slot].tag == tag) self.read[slot] = .{};
            if (writes and self.write[slot].tag == tag) self.write[slot] = .{};
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

    // -- parallel mode --------------------------------------------------------
    //
    // Each executor fills only its own table, but a protection or mapping
    // change made by one thread invalidates every thread's table while its
    // owner may be probing it. The emitted probe reads `tag` and then
    // `delta` with plain loads, so another thread must never write a delta:
    // it only ever retires a tag. A probe then sees either the old tag with
    // its old, still-valid delta, or a miss. The owner's own fill writes the
    // delta before the tag, and its own later probes see both in program
    // order.

    /// The owner's fill in parallel mode: the delta, then the tag, the tag
    /// sequentially consistent so the caller's epoch re-check that follows
    /// cannot be ordered before it.
    pub fn fillOrdered(self: *Tlb, is_write: bool, page: u64, host: [*]u8) void {
        const tag = page >> page_shift;
        const table = if (is_write) &self.write else &self.read;
        const entry = &table[index(tag)];
        @atomicStore(u64, &entry.delta, @intFromPtr(host) -% page, .monotonic);
        @atomicStore(u64, &entry.tag, tag, .seq_cst);
    }

    /// Retire the tag `fillOrdered` just wrote for `page`, if it is still
    /// that page's: the fill raced an invalidation.
    pub fn retireOrdered(self: *Tlb, is_write: bool, page: u64) void {
        const tag = page >> page_shift;
        const table = if (is_write) &self.write else &self.read;
        const entry = &table[index(tag)];
        if (@atomicLoad(u64, &entry.tag, .seq_cst) == tag) @atomicStore(u64, &entry.tag, invalid_tag, .seq_cst);
    }

    /// `flush` from a thread other than this table's owner: tags only.
    pub fn flushOrdered(self: *Tlb, reads: bool, writes: bool) void {
        if (reads) {
            for (&self.read) |*entry| @atomicStore(u64, &entry.tag, invalid_tag, .seq_cst);
        }
        if (writes) {
            for (&self.write) |*entry| @atomicStore(u64, &entry.tag, invalid_tag, .seq_cst);
        }
    }

    /// `invalidateRange` from a thread other than this table's owner.
    pub fn invalidateRangeOrdered(self: *Tlb, base: u64, length: u64) void {
        self.invalidateRangeOrderedTables(base, length, true, true);
    }

    pub fn invalidateRangeOrderedTables(self: *Tlb, base: u64, length: u64, reads: bool, writes: bool) void {
        if (length == 0 or !(reads or writes)) return;
        const first = base >> page_shift;
        const last = (base +| (length - 1)) >> page_shift;
        if (last - first + 1 >= @min(entries, invalidate_scan_limit)) {
            self.flushOrdered(reads, writes);
            return;
        }
        var tag = first;
        while (true) : (tag += 1) {
            const slot = index(tag);
            if (reads and @atomicLoad(u64, &self.read[slot].tag, .seq_cst) == tag) @atomicStore(u64, &self.read[slot].tag, invalid_tag, .seq_cst);
            if (writes and @atomicLoad(u64, &self.write[slot].tag, .seq_cst) == tag) @atomicStore(u64, &self.write[slot].tag, invalid_tag, .seq_cst);
            if (tag == last) break;
        }
    }
};

/// ARM's condition over NZCV, as the hardware evaluates it.
fn armConditionHolds(cond: a64.Cond, n: bool, z: bool, c: bool, v: bool) bool {
    const base = switch (@as(a64.Cond, @enumFromInt(@intFromEnum(cond) & 0xE))) {
        .eq => z,
        .hs => c,
        .mi => n,
        .vs => v,
        .hi => c and !z,
        .ge => n == v,
        .gt => !z and n == v,
        else => unreachable,
    };
    return if (@intFromEnum(cond) & 1 != 0) !base else base;
}

test "every fused x86 condition agrees with its ARM condition over random operands" {
    var prng = std.Random.DefaultPrng.init(0x5eed_f00d);
    const random = prng.random();
    const interesting = [_]u64{ 0, 1, 2, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFF, 0x7FFF_FFFF_FFFF_FFFF, 0x8000_0000_0000_0000, 0xFFFF_FFFF_FFFF_FFFF };
    var checked: u32 = 0;
    for ([_]Size{ .bits32, .bits64 }) |size| {
        const w = bits(size);
        const mask = maskFor(size);
        const sign: u64 = @as(u64, 1) << @intCast(w - 1);
        for ([_]FusedKind{ .sub, .add, .logic, .inc, .dec }) |kind| {
            for (0..4000) |round| {
                const a = (if (round < interesting.len * interesting.len) interesting[round / interesting.len] else random.int(u64)) & mask;
                const b = (if (round < interesting.len * interesting.len) interesting[round % interesting.len] else random.int(u64)) & mask;
                var rflags: u32 = 0x2;
                var n = false;
                var z = false;
                var c = false;
                var v = false;
                switch (kind) {
                    .sub => {
                        const r = (a -% b) & mask;
                        x64_decoder.applySub(&rflags, a, b, r, size);
                        n = (r & sign) != 0;
                        z = r == 0;
                        c = a >= b;
                        v = ((a ^ b) & (a ^ r) & sign) != 0;
                    },
                    .add => {
                        const r = (a +% b) & mask;
                        x64_decoder.applyAdd(&rflags, a, b, r, size);
                        n = (r & sign) != 0;
                        z = r == 0;
                        c = @as(u128, a) + @as(u128, b) > mask;
                        v = (~(a ^ b) & (a ^ r) & sign) != 0;
                    },
                    .logic => {
                        const r = a & b;
                        x64_decoder.applyLogic(&rflags, r, size);
                        n = (r & sign) != 0;
                        z = r == 0;
                    },
                    .inc, .dec => {
                        const r = (if (kind == .inc) a +% 1 else a -% 1) & mask;
                        x64_decoder.applyIncDec(&rflags, a, r, size, kind == .inc);
                        n = (r & sign) != 0;
                        z = r == 0;
                        // adds/subs with 1: C is the carry or NOT borrow.
                        c = if (kind == .inc) a == mask else a != 0;
                        v = if (kind == .inc) a == sign - 1 else a == sign;
                    },
                }
                for (0..16) |code| {
                    const cond: Cond = @enumFromInt(code);
                    const arm_cond = fusedCondition(kind, cond) orelse continue;
                    try testing.expectEqual(x64_decoder.evalCond(rflags, cond), armConditionHolds(arm_cond, n, z, c, v));
                    checked += 1;
                }
            }
        }
    }
    // Every kind maps at least the equality and signed conditions.
    try testing.expect(checked > 200_000);
}

test "a naturally aligned access needs no page-span check after its TLB hit" {
    // A byte never leaves its page, guarded or not.
    try testing.expect(tlbProbeSpanProven(1, false));
    // A guarded power-of-two access is aligned to its size, so it ends on
    // the page it starts on.
    for ([_]u64{ 2, 4, 8, 16 }) |bytes| {
        try testing.expect(tlbProbeSpanProven(bytes, true));
        try testing.expect(!tlbProbeSpanProven(bytes, false));
    }
    // A 16-byte vector guarded only to 8 can straddle at 0xFF8, and a
    // hoisted span is not an access size at all: both keep the check.
    try testing.expect(!tlbProbeSpanProven(24, true));
    try testing.expect(!tlbProbeSpanProven(Tlb.page_bytes * 2, true));
}

test "an ordered invalidation retires tags and never touches a delta" {
    const tlb = try std.testing.allocator.create(Tlb);
    defer std.testing.allocator.destroy(tlb);
    tlb.* = Tlb.empty;
    var bytes: [8192]u8 align(4096) = undefined;
    tlb.fillOrdered(false, 0x1_0000_0000, &bytes);
    tlb.fillOrdered(true, 0x1_0000_1000, bytes[4096..].ptr);
    const read_slot = Tlb.index(0x1_0000_0000 >> Tlb.page_shift);
    const delta = tlb.read[read_slot].delta;
    try std.testing.expectEqual(@intFromPtr(&bytes) + 0x10, @intFromPtr(tlb.lookup(false, 0x1_0000_0010).?));
    tlb.invalidateRangeOrdered(0x1_0000_0000, 16);
    try std.testing.expect(tlb.lookup(false, 0x1_0000_0010) == null);
    // A probe that read the old tag just before still pairs it with the
    // delta that tag was filled with.
    try std.testing.expectEqual(delta, tlb.read[read_slot].delta);
    try std.testing.expect(tlb.lookup(true, 0x1_0000_1008) != null);
    tlb.retireOrdered(true, 0x1_0000_1000);
    try std.testing.expect(tlb.lookup(true, 0x1_0000_1008) == null);
    tlb.fillOrdered(false, 0x2000, &bytes);
    tlb.flushOrdered(true, false);
    try std.testing.expect(tlb.lookup(false, 0x2004) == null);
}

test "the folded GPU TLB keeps pages that collided in the prior 8192-entry table" {
    try testing.expectEqual(@as(usize, 32768), Tlb.entries);
    const first_tag: u64 = 1;
    const second_tag: u64 = 8192;
    const previous_mask: u64 = 8191;
    try testing.expectEqual(
        (first_tag ^ (first_tag >> Tlb.fold_shift)) & previous_mask,
        (second_tag ^ (second_tag >> Tlb.fold_shift)) & previous_mask,
    );
    try testing.expect(Tlb.index(first_tag) != Tlb.index(second_tag));

    const tlb = try std.testing.allocator.create(Tlb);
    defer std.testing.allocator.destroy(tlb);
    tlb.* = Tlb.empty;
    var pages: [8192]u8 align(4096) = undefined;
    tlb.fill(false, first_tag << Tlb.page_shift, &pages);
    tlb.fill(false, second_tag << Tlb.page_shift, pages[4096..].ptr);
    try testing.expectEqual(@intFromPtr(&pages), @intFromPtr(tlb.lookup(false, first_tag << Tlb.page_shift).?));
    try testing.expectEqual(@intFromPtr(pages[4096..].ptr), @intFromPtr(tlb.lookup(false, second_tag << Tlb.page_shift).?));
}

const tlb_write_offset: u32 = @offsetOf(Tlb, "write");

/// Where the emitted code finds the state it works on.
pub const Layout = struct {
    /// Byte offset of the `Regs` register file inside the state.
    regs_offset: u32,
    /// Byte offset of the `Scratch` record inside the state.
    scratch_offset: u32,
    /// Byte offset of the inline TLB or active-TLB pointer inside the state.
    tlb_offset: u32,
    /// Production PE state selects the active cooperative guest thread's
    /// TLB through a pointer. Small translator fixtures keep an inline TLB.
    tlb_indirect: bool = false,
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
    /// A stable guest-address interval for Xenia's dedicated generated-code
    /// mapping. Targets inside this view are already known not to be image
    /// hooks, so emitted transfers can skip the per-target C helper. Zero
    /// bounds disable the inline admission path.
    code_cache_low_offset: u32,
    code_cache_high_offset: u32,
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
    /// Byte offsets of the exact, permanently pinned RtlEnter/LeaveCritical-
    /// Section trampolines. They are checked only after a Bloom hit, since
    /// those two targets dominate the Halo 3 indirect-transfer profile.
    xbox_critical_section_enter_offset: u32 = 0,
    xbox_critical_section_leave_offset: u32 = 0,
    image_targets_hooked_offset: u32,
    /// For a `call_rel32` whose target is a milestone tracepoint (see
    /// `Insn.milestone_gate`): the `[n]u8` "saturated" flags and the `[n]u64`
    /// hit counters, indexed by milestone. Only read for an instruction the
    /// glue gave a gate, so a glue that never gates may leave them zero.
    milestone_saturated_offset: u32 = 0,
    milestone_hits_offset: u32 = 0,
    /// Where the register files are. `.inline_in_state`: at the offsets
    /// above, inside the state (small translator fixtures).
    /// `.pointers_in_scratch`: the block's entry receives the executing
    /// guest context's `Scratch` record as its third argument, and that
    /// record holds pointers to the context's register files and TLB
    /// (`Scratch.regs_file` ...); the offsets above are then unused. That is
    /// what lets guest threads on several host threads run translated code
    /// at once, each on its own registers.
    register_files: RegisterFiles = .inline_in_state,
};

pub const RegisterFiles = enum { inline_in_state, pointers_in_scratch };

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
const scratch_call_guard_offset: u32 = @offsetOf(Scratch, "call_guard");
const scratch_jmp_guard_offset: u32 = @offsetOf(Scratch, "jmp_guard");
const scratch_ret_guard_offset: u32 = @offsetOf(Scratch, "ret_guard");
const scratch_direct_non_temporal_offset: u32 = @offsetOf(Scratch, "direct_non_temporal");
const scratch_regs_file_offset: u32 = @offsetOf(Scratch, "regs_file");
const scratch_xmm_file_offset: u32 = @offsetOf(Scratch, "xmm_file");
const scratch_ymm_hi_file_offset: u32 = @offsetOf(Scratch, "ymm_hi_file");
const scratch_zmm_hi_file_offset: u32 = @offsetOf(Scratch, "zmm_hi_file");
const scratch_tlb_file_offset: u32 = @offsetOf(Scratch, "tlb_file");
const scratch_transfer_target_offset: u32 = @offsetOf(Scratch, "transfer_target");
const scratch_index_offset: u32 = @offsetOf(Scratch, "index");
const scratch_vector_offset: u32 = @offsetOf(Scratch, "vector");
const scratch_flag_kind_offset: u32 = @offsetOf(Scratch, "flag_kind");
const scratch_flag_size_offset: u32 = @offsetOf(Scratch, "flag_size");
const scratch_flag_a_offset: u32 = @offsetOf(Scratch, "flag_a");
const scratch_flag_b_offset: u32 = @offsetOf(Scratch, "flag_b");
const scratch_flag_r_offset: u32 = @offsetOf(Scratch, "flag_r");
const scratch_chain_break_offset: u32 = @offsetOf(Scratch, "chain_break");
const scratch_chain_count_offset: u32 = @offsetOf(Scratch, "chain_count");
const scratch_chain_budget_offset: u32 = @offsetOf(Scratch, "chain_budget");
const scratch_chain_retired_image_offset: u32 = @offsetOf(Scratch, "chain_retired_image");
const scratch_chain_retired_other_mapped_offset: u32 = @offsetOf(Scratch, "chain_retired_other_mapped");
const scratch_chain_previous_offset: u32 = @offsetOf(Scratch, "chain_previous");
const scratch_jump_cache_offset: u32 = @offsetOf(Scratch, "jump_cache");
const scratch_fused_a_offset: u32 = @offsetOf(Scratch, "fused_a");
const scratch_fused_b_offset: u32 = @offsetOf(Scratch, "fused_b");
const scratch_fused_r_offset: u32 = @offsetOf(Scratch, "fused_r");
const scratch_saved_nzcv_offset: u32 = @offsetOf(Scratch, "saved_nzcv");
const scratch_skip_spill_offset: u32 = @offsetOf(Scratch, "skip_spill");
const scratch_fpcr_writes_offset: u32 = @offsetOf(Scratch, "fpcr_writes");
const scratch_block_offset: u32 = @offsetOf(Scratch, "block");

pub const FallbackReason = enum(u8) {
    missing_native_template,
    native_slow_path,
    hook_observation,
    vector_policy_disabled,

    pub fn label(self: FallbackReason) []const u8 {
        return switch (self) {
            .missing_native_template => "missing-native-template",
            .native_slow_path => "native-slow-path",
            .hook_observation => "hook-observation",
            .vector_policy_disabled => "vector-policy-disabled",
        };
    }
};

pub const Insn = struct {
    rip: u64,
    len: u8,
    /// The decode as it comes out of the decoder: `addr` is the displacement,
    /// not an effective address.
    decoded: DecodedInsn,
    segment: Segment,
    /// The glue asks for the interpreter although a template exists, with
    /// `fallback_reason` naming the policy that owns that decision.
    force_fallback: bool = false,
    fallback_reason: FallbackReason = .missing_native_template,
    /// A `call_rel32` into a milestone tracepoint the glue may stop
    /// observing: native once the milestone's saturated flag is set, with its
    /// hit counter bumped in place; the interpreter's arm until then.
    milestone_gate: ?u16 = null,
};

/// A block's entry: the state the helpers receive, the block's helper table,
/// and - for `.pointers_in_scratch` layouts - the executing context's scratch
/// record (inline layouts ignore it).
pub const BlockFn = *const fn (state: *anyopaque, helpers: *const Helpers, scratch: *Scratch) callconv(.c) u32;

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
    /// Some conditional branch jumps forward inside the block instead of
    /// leaving it, so its instructions do not always run in order: a
    /// cross-check following the interpreter resumes at that branch's
    /// target.
    internal_edges: bool = false,
    /// Bit i: instruction i is a branch whose taken edge stays in the block.
    /// Only these: a forward branch whose target reads a live flag still
    /// leaves, and a cross-check that followed it inside the block compared
    /// the interpreter's longer run with the translation's exit and dropped
    /// a correct block.
    internal_sources: u128 = 0,
    /// A block the glue cross-checks against the interpreter before trusting
    /// it although it reaches memory (`ROSETTE_BLOCK_JIT_VERIFY_MEMORY`); a
    /// register-only block is always checked.
    needs_verify: bool = false,
    touches_vectors: bool = false,
    touches_x87: bool = false,
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
    /// The live generation word for this block's source: the word of the
    /// code page it starts on, the mapping's own, or the image's. Every
    /// place it can point into lives as long as the run, so the pointer is
    /// stable; that is what lets the native chain validate a successor
    /// without calling back into the glue.
    generation_ptr: ?*const u64 = null,
    /// What a hop into this block proves, read by the native chain from
    /// the block itself rather than from the link that names it: the word
    /// to load (`generation_ptr`, or `chain_never` while the block may not
    /// be entered by a hop), the value it must hold, and where to enter.
    /// The glue arms these (`armChain`) once the block's bytes are proven
    /// at a generation, and re-arms them at every revalidation.
    chain_gen_ptr: u64 = 0,
    chain_generation: u64 = 0,
    chain_entry_address: u64 = 0,
    chain_never: u64 = 1,
    /// The last `link_ways` distinct successors this block went to. One
    /// link was not enough: a block ending in a branch alternates between
    /// its two successors, and on 2026-09-21 64% of chain exits were a
    /// successor the single link did not name - native chains averaged 4.6
    /// blocks. A `ret` that returns to more callers than there are ways
    /// falls through to the thread's jump cache.
    links: [link_ways]Link = @splat(.{}),
    /// The way the next new successor replaces: round robin.
    link_victim: u8 = 0,

    pub fn entry(self: *const Block) BlockFn {
        return @ptrCast(self.code.ptr);
    }

    /// Let hops enter this block while `word` holds `generation`.
    pub fn armChain(self: *Block, word: *const u64, generation: u64) void {
        self.chain_gen_ptr = @intFromPtr(word);
        self.chain_generation = generation;
        self.chain_entry_address = @intFromPtr(self.code.ptr) + self.chain_entry;
    }

    /// No hop may enter this block: its proof loads `chain_never` (1) and
    /// expects 0.
    pub fn disarmChain(self: *Block) void {
        self.chain_gen_ptr = @intFromPtr(&self.chain_never);
        self.chain_generation = 0;
        self.chain_entry_address = @intFromPtr(self.code.ptr) + self.chain_entry;
    }
};

/// Ways in a block's successor cache.
pub const link_ways: usize = 4;

/// One successor a block chained to, or one jump-cache entry: the guest
/// address, and the table slot the block for it was in. Everything else a
/// hop needs is read from the block that occupies that slot now, which is
/// also what makes a link safe against the slot being refilled: a block
/// for another address fails the `start_rip` comparison, and an unarmed or
/// rewritten one fails its generation. A link that recorded the block's
/// own pointer could be satisfied by a different block allocated at a
/// freed one's address.
pub const Link = extern struct {
    rip: u64 = 0,
    slot: usize = 0,
};

/// A thread's jump cache: the successors of every block, direct-mapped by
/// guest address. A block probes its own ways first, then this - which is
/// where a `ret` back to its eleventh caller, or an indirect call through
/// a table, finds its successor without returning to the glue. Each such
/// return cost about 25 ns in the glue against 8 for a hop.
pub const jump_cache_entries: usize = 1 << 14;
pub const jump_cache_shift: u6 = 14;

pub fn jumpCacheIndex(rip: u64) usize {
    return @intCast((rip ^ (rip >> jump_cache_shift)) & (jump_cache_entries - 1));
}

pub const Compiled = struct {
    code: []const u32,
    /// Byte offset of the entry that skips the prologue.
    chain_entry: u32,
    native_count: u32,
    fallback_count: u32,
    register_only: bool,
    /// Which register files and memory the block's code reaches, for the
    /// memory-aware cross-check (`ROSETTE_BLOCK_JIT_VERIFY_MEMORY`).
    touches_memory: bool = false,
    touches_vectors: bool = false,
    touches_x87: bool = false,
    /// Conditional branches fused with the flag writer before them.
    fused_branches: u32 = 0,
    /// Flag writers fused with the conditional readers after them.
    fused_runs: u32 = 0,
    /// Instructions whose flag computation the liveness pass removed.
    flags_elided: u32,
    /// Flag writers whose emission was narrowed to a subset of the six.
    flags_narrowed: u32,
    /// The flags the block's `ret` hands back to its caller under the
    /// Windows calling convention (`returnFlagsLive`); zero for any other
    /// block. Nonzero means a helper returns a result in a flag.
    return_flags: u8 = 0,
    /// Guest registers held in host registers for this block.
    cached_registers: u8 = 0,
    /// Memory accesses served through a hoisted base pointer.
    hoisted_accesses: u32 = 0,
    /// Conditional branches whose taken edge stays in the block.
    internal_edges: u32 = 0,
    /// Which instructions those are (`Block.internal_sources`).
    internal_sources: u128 = 0,
    upper_clears_elided: u32 = 0,
    xmm_loads_forwarded: u32 = 0,
};

// ---------------------------------------------------------------------------
// The compiled subset
// ---------------------------------------------------------------------------

/// Whether a template exists for the instruction as decoded. Not every form
/// of an op is compiled (a 16-bit shift is not), so this is a function of the
/// whole decode, not of the op alone.
pub fn isNative(d: DecodedInsn) bool {
    if (d.is_evex) return false;
    // A malformed LOCK encoding is #UD, not a candidate for a translated
    // template. Leave it for the shared interpreter guard so it terminates
    // consistently instead of silently executing an unlocked operation.
    if (!lockPrefixAllowed(d)) return false;
    // A `lock` prefix is honoured only by the atomic templates, which make
    // it a real host atomic; every other locked form stays interpreted.
    if (d.lock) {
        const form = atomicForm(d.op) orelse return false;
        if ((form == .bit_set or form == .bit_reset or form == .bit_complement) and
            d.size == .bits8) return false;
    }
    if (isVectorNative(d)) return true;
    const wide = d.size == .bits32 or d.size == .bits64;
    return switch (d.op) {
        .nop => d.len != 2,
        // The 32-bit op tags also carry 66-prefixed 16-bit operands. Select
        // the LSE encoding from the decoded width so a word update cannot
        // overwrite the neighbouring two bytes.
        .xchg_mem8_reg8 => !d.is_reg_form and memoryOperandSupported(d),
        .xchg_mem32_reg32, .xchg_mem64_reg64 => !d.src_high8 and !d.is_reg_form and memoryOperandSupported(d),
        .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64, .xadd_mem32_reg32, .xadd_mem64_reg64 => d.size != .bits8 and !d.is_reg_form and memoryOperandSupported(d),
        .cmpxchg_mem8_reg8, .cmpxchg_mem16_reg16, .xadd_mem8_reg8 => !d.src_high8 and !d.is_reg_form and memoryOperandSupported(d),
        .cmpxchg8b_mem => !d.is_reg_form and memoryOperandSupported(d),
        .cmpxchg16b_mem => !d.is_reg_form and memoryOperandSupported(d),
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
        .xchg_reg8_reg8, .xchg_reg32_reg32, .xchg_reg64_reg64 => d.is_reg_form,
        .xchg_accum_reg => true,
        // These register-only forms have no memory admission or atomicity
        // edge. Keep the memory forms interpreted unless their native path
        // can prove its full access contract.
        .mul_reg8 => true,
        .popcnt_reg_reg => d.is_reg_form,
        // Group 1 arithmetic and logic: register, immediate and memory forms.
        else => blk: {
            if (atomicForm(d.op)) |form| {
                if (form == .update) break :blk !d.is_reg_form and memoryOperandSupported(d);
            }
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
                // CL is masked to five bits for narrow operands. Counts at
                // or above the operand width stay on the interpreter's
                // guarded path; smaller counts have the same result and
                // defined flag bits in the native template.
                .shl_reg_cl, .shr_reg_cl, .sar_reg_cl => true,
                // The 2026-09-22 Halo 3 run reached the interpreter about
                // 19.6 million times for `shl [mem], cl`. Use the same
                // guarded memory path as the register forms, including the
                // watched-page helper for writes.
                .shl_mem_cl, .shr_mem_cl, .sar_mem_cl => !d.is_reg_form and memoryOperandSupported(d),
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
                .bt_mem_imm,
                .bts_mem_imm,
                .btr_mem_imm,
                .btc_mem_imm,
                .bt_mem_reg,
                .bts_mem_reg,
                .btr_mem_reg,
                .btc_mem_reg,
                => d.size != .bits8 and memoryOperandSupported(d),
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
                // Fence widths are lowered separately in emitInsn; none
                // needs a guest-interpreter round trip.
                .mfence, .lfence, .sfence => true,
                .push_reg, .push_imm, .pop_reg => true,
                .cdqe, .cdq, .cqo => true,
                .bswap_reg => wide,
                .jcc_rel8, .jcc_rel32, .jmp_rel8 => true,
                // The zero-return marker and optional call/return observers
                // still hand the operation to the interpreter at runtime.
                // Both forms of RET apply their architectural stack cleanup
                // before completing that transfer.
                .ret => true,
                // 1,689,686,672 fallbacks, 31%, second only to `ret`. The
                // glue decides per call site whether the interpreter's arm
                // has a hook for this target and forces the fallback when it
                // does, so reaching here means the arm would only push and
                // jump - see `blockJitCallTargetPlain`.
                .call_rel32 => true,
                // The transfer emitter reads and preserves a call target
                // before it adjusts RSP, so RSP-based operands are safe. IAT
                // checks, hooks, image policy and external mapping proof
                // remain runtime gates in the emitted path.
                .jmp_reg64 => true,
                .call_reg64 => true,
                .call_mem64 => memoryOperandSupported(d),
                // A jump through memory is a jump table or an import thunk:
                // Xenia reaches memcpy and memset through one-instruction
                // `jmp [IAT]` thunks, which used to be refused outright -
                // a block of nothing but a fallback - so every call of them
                // took two interpreter steps and the runtime lock.
                .jmp_mem64 => memoryOperandSupported(d),
                // Exact raw x87 transfers use a focused helper rather than
                // the general instruction interpreter.
                .fld_mem80, .fstp_mem80 => !d.is_reg_form and memoryOperandSupported(d),
                .fld_st, .fstp_st => d.is_reg_form,
                // x87 memory arithmetic and compares still use the shared
                // guest x87 model, but they no longer force every instruction
                // in their generated-code block through the interpreter.
                .x87_memory => !d.is_reg_form and memoryOperandSupported(d) and
                    (d.size == .bits16 or d.size == .bits32 or d.size == .bits64),
                else => false,
            };
        },
    };
}

fn isX87RawTransfer(d: DecodedInsn) bool {
    return switch (d.op) {
        .fld_mem80, .fstp_mem80 => !d.is_reg_form and memoryOperandSupported(d),
        .fld_st, .fstp_st => d.is_reg_form,
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
///
/// x25-x28 come first, so the busiest guest registers get them. The rest
/// are caller-saved registers no template uses (x4-x7, x17): a helper call
/// would clobber them, so `emitCallHelper` spills them to the register file
/// around it and reloads them after. Helper calls are on cold paths, while
/// four registers were too few for Xenia's code, which keeps ten or more
/// x86 registers busy per block: the rest went through the register file
/// on every use, and a dependent chain through memory waits on
/// store-to-load forwarding at every step.
const cache_host_regs = [_]a64.Reg{ 25, 26, 27, 28, 4, 5, 6, 7, 17 };
/// How many of `cache_host_regs` (the first ones) survive a C call.
const cache_callee_saved: u8 = 4;
/// A guest register is cached only if the block touches it at least this
/// often: caching costs a load in, and a store out if the block writes it.
/// Two uses already repay that when one feeds the other.
const cache_min_uses: u32 = 2;
/// In a block with internal forward edges (`planInternalEdges`): how many
/// of its instructions the taken edges have jumped over so far. Every exit
/// subtracts it from the count its stub names, so the retired count stays
/// exact on every path. ip0 is otherwise used only by the locked adc/sbb
/// and cmpxchg16b templates, whose blocks get no internal edges.
const skip_reg: a64.Reg = 16;
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
        .adc_reg8_mem8, .adc_reg16_mem16, .adc_reg32_mem32, .adc_reg64_mem64, .adc_mem8_reg8, .adc_mem16_reg16, .adc_mem32_reg32, .adc_mem64_reg64, .adc_mem8_imm8, .adc_mem16_imm8, .adc_mem32_imm8, .adc_mem64_imm8, .adc_mem16_imm32, .adc_mem32_imm32, .adc_mem64_imm32 => .adc,
        .sbb_reg8_reg8, .sbb_reg16_reg16, .sbb_reg32_reg32, .sbb_reg64_reg64, .sbb_reg8_imm8, .sbb_reg16_imm8, .sbb_reg32_imm8, .sbb_reg64_imm8, .sbb_reg16_imm32, .sbb_reg32_imm32, .sbb_reg64_imm32, .sbb_accum_imm => .sbb,
        .sbb_reg8_mem8, .sbb_reg16_mem16, .sbb_reg32_mem32, .sbb_reg64_mem64, .sbb_mem8_reg8, .sbb_mem16_reg16, .sbb_mem32_reg32, .sbb_mem64_reg64, .sbb_mem8_imm8, .sbb_mem16_imm8, .sbb_mem32_imm8, .sbb_mem64_imm8, .sbb_mem16_imm32, .sbb_mem32_imm32, .sbb_mem64_imm32 => .sbb,
        else => null,
    };
}

fn binaryShapeOf(op: Op) BinaryShape {
    return switch (op) {
        .add_reg8_mem8, .add_reg16_mem16, .add_reg32_mem32, .add_reg64_mem64, .sub_reg8_mem8, .sub_reg16_mem16, .sub_reg32_mem32, .sub_reg64_mem64, .and_reg8_mem8, .and_reg16_mem16, .and_reg32_mem32, .and_reg64_mem64, .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64, .xor_reg8_mem8, .xor_reg16_mem16, .xor_reg32_mem32, .xor_reg64_mem64, .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64, .adc_reg8_mem8, .adc_reg16_mem16, .adc_reg32_mem32, .adc_reg64_mem64, .sbb_reg8_mem8, .sbb_reg16_mem16, .sbb_reg32_mem32, .sbb_reg64_mem64 => .reg_mem,
        .add_mem8_reg8, .add_mem16_reg16, .add_mem32_reg32, .add_mem64_reg64, .sub_mem8_reg8, .sub_mem16_reg16, .sub_mem32_reg32, .sub_mem64_reg64, .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64, .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64, .xor_mem8_reg8, .xor_mem16_reg16, .xor_mem32_reg32, .xor_mem64_reg64, .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64, .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64, .adc_mem8_reg8, .adc_mem16_reg16, .adc_mem32_reg32, .adc_mem64_reg64, .sbb_mem8_reg8, .sbb_mem16_reg16, .sbb_mem32_reg32, .sbb_mem64_reg64 => .mem_reg,
        .add_mem8_imm8, .add_mem16_imm8, .add_mem32_imm8, .add_mem64_imm8, .add_mem16_imm32, .add_mem32_imm32, .add_mem64_imm32, .sub_mem8_imm8, .sub_mem16_imm8, .sub_mem32_imm8, .sub_mem64_imm8, .sub_mem16_imm32, .sub_mem32_imm32, .sub_mem64_imm32, .and_mem8_imm8, .and_mem16_imm8, .and_mem32_imm8, .and_mem64_imm8, .and_mem16_imm32, .and_mem32_imm32, .and_mem64_imm32, .or_mem8_imm8, .or_mem16_imm8, .or_mem32_imm8, .or_mem64_imm8, .or_mem16_imm32, .or_mem32_imm32, .or_mem64_imm32, .xor_mem8_imm8, .xor_mem16_imm8, .xor_mem32_imm8, .xor_mem64_imm8, .xor_mem16_imm32, .xor_mem32_imm32, .xor_mem64_imm32, .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8, .cmp_mem16_imm32, .cmp_mem32_imm32, .cmp_mem64_imm32, .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32, .adc_mem8_imm8, .adc_mem16_imm8, .adc_mem32_imm8, .adc_mem64_imm8, .adc_mem16_imm32, .adc_mem32_imm32, .adc_mem64_imm32, .sbb_mem8_imm8, .sbb_mem16_imm8, .sbb_mem32_imm8, .sbb_mem64_imm8, .sbb_mem16_imm32, .sbb_mem32_imm32, .sbb_mem64_imm32 => .mem_imm,
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
        .shl_reg_cl, .shr_reg_cl, .sar_reg_cl, .shl_mem_cl, .shr_mem_cl, .sar_mem_cl => .{ .writes = F_CF | F_ZF | F_SF | F_OF },
        .rol_reg_imm, .ror_reg_imm => blk: {
            const count = @as(u64, shiftCount(d)) % bits(d.size);
            if (count == 0) break :blk .{};
            const written: u8 = F_CF | (if (count == 1) F_OF else 0);
            break :blk .{ .writes = written, .kills = written };
        },
        .rol_reg_cl, .ror_reg_cl => .{ .writes = F_CF | F_OF },
        .imul_reg64_reg64, .imul_reg32_reg32, .imul_reg64_mem64, .imul_reg32_mem32, .imul_reg32_reg32_imm8, .imul_reg32_reg32_imm32, .imul_reg64_reg64_imm8, .imul_reg64_reg64_imm32, .imul_reg32_mem32_imm8, .imul_reg32_mem32_imm32, .imul_reg64_mem64_imm8, .imul_reg64_mem64_imm32 => .{ .writes = F_CF | F_OF, .kills = F_CF | F_OF },
        .mul_reg8 => .{ .writes = F_CF | F_OF, .kills = F_CF | F_OF },
        .popcnt_reg_reg => .{ .writes = F_ALL, .kills = F_ALL },
        .bt_reg_reg,
        .bts_reg_reg,
        .btr_reg_reg,
        .btc_reg_reg,
        .bt_reg_imm,
        .bts_reg_imm,
        .btr_reg_imm,
        .btc_reg_imm,
        .bt_mem_imm,
        .bts_mem_imm,
        .btr_mem_imm,
        .btc_mem_imm,
        .bt_mem_reg,
        .bts_mem_reg,
        .btr_mem_reg,
        .btc_mem_reg,
        => .{ .writes = F_CF, .kills = F_CF },
        .cmpxchg_mem8_reg8, .cmpxchg_mem16_reg16, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64, .xadd_mem8_reg8, .xadd_mem32_reg32, .xadd_mem64_reg64 => .{ .writes = F_ALL, .kills = F_ALL },
        .cmpxchg8b_mem, .cmpxchg16b_mem => .{ .writes = F_ZF, .kills = F_ZF },
        .bsf_reg_reg, .bsr_reg_reg => .{ .writes = F_ZF, .kills = F_ZF },
        .tzcnt_reg_reg, .lzcnt_reg_reg => .{ .writes = F_ZF | F_CF, .kills = F_ZF | F_CF },
        .cmovcc_reg_reg, .cmovcc_reg_mem, .setcc_reg8, .setcc_mem8, .jcc_rel8, .jcc_rel32 => .{ .reads = conditionReads(d.cond) },
        .vucomiss, .vucomisd => .{ .writes = F_ALL, .kills = F_ALL },
        .vptest, .vtestps, .vtestpd => .{ .writes = F_ALL, .kills = F_ALL },
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

/// `flagLiveness` with the set live where the block ends, as `exitFlagsLive`
/// computes it: zero into a `call` under the calling convention, what a
/// helper returns through a `ret`, every flag otherwise. A conditional
/// branch inside the block still leaves with all six live.
pub fn flagLivenessToExit(insns: []const Insn, wants: []bool, live_out: ?[]u8, exit_live: u8) u32 {
    return flagLivenessToExitFall(insns, wants, live_out, null, null, exit_live);
}

/// The same, also giving per instruction the flags live after it along
/// its fall-through only: for a conditional branch, without the taken
/// edge's demand for all six. A writer fused with the branch that follows
/// it owes the taken edge everything, but the fall-through only this.
pub fn flagLivenessToExitFall(insns: []const Insn, wants: []bool, live_out: ?[]u8, live_fall_out: ?[]u8, live_in_out: ?[]u8, exit_live: u8) u32 {
    var live: u8 = exit_live;
    var elided: u32 = 0;
    var index = insns.len;
    while (index > 0) {
        index -= 1;
        if (live_fall_out) |out| out[index] = live;
        if (isConditionalBranch(insns[index].decoded.op)) live = F_ALL;
        const effects = flagEffects(insns[index]);
        wants[index] = (effects.writes & live) != 0;
        if (live_out) |out| out[index] = live;
        if (effects.writes != 0 and !wants[index]) elided += 1;
        live = (live & ~effects.kills) | effects.reads;
        // What a jump to this instruction must find in `rflags`: every way
        // out of the block counts as reading all six, so this is never less
        // than whatever the code at this address will read.
        if (live_in_out) |out| out[index] = live;
    }
    return elided;
}

/// What a flag writer fused with the conditional branch after it leaves in
/// NZCV, which decides how each x86 condition maps onto an ARM one.
pub const FusedKind = enum { sub, add, logic, inc, dec };

/// A flag writer whose flags only the branch right after it reads in
/// place: it sets NZCV with one ARM instruction, the branch tests NZCV,
/// and the x86 flags are written to `rflags` only on the paths that leave
/// or still read them. Its operands stay in t1 and t2 and its result in
/// t0 until the branch has used them.
pub const Fused = struct {
    kind: FusedKind,
    size: Size,
    /// The x86 flags the writer writes (`F_*`).
    writes: u8,
    /// Readers still to come: the run of `jcc`, `setcc` and `cmovcc` right
    /// after the writer that test NZCV instead of `rflags`.
    remaining: u8 = 1,
    /// A reader reaches memory, whose probe and helper reuse every
    /// temporary: the writer's operands and result are kept in scratch
    /// (`fused_a/b/r`) for any exit that still owes its flags.
    saved: bool = false,
    /// Where the writer's operands are while the run lasts: t1 and t2, or,
    /// for a `cmp` or `test` read straight from the register cache
    /// (`emitFusedCompareDirect`), the cache registers themselves and an
    /// immediate - the paths that derive x86 flags copy them into t1 and t2
    /// first, at the writer's width.
    a_reg: a64.Reg = t1,
    b_reg: a64.Reg = t2,
    b_imm: ?u64 = null,
};

/// The ARM condition that holds exactly when x86 `cond` does after `kind`
/// set NZCV, or null when no single one does.
pub fn fusedCondition(kind: FusedKind, cond: Cond) ?a64.Cond {
    const base: Cond = @enumFromInt(@intFromEnum(cond) & 0xE);
    const positive: a64.Cond = switch (kind) {
        // ARM C after a subtraction is NOT borrow; x86 CF is the borrow.
        .sub => switch (base) {
            .o => .vs,
            .b => .lo,
            .e => .eq,
            .be => .ls,
            .s => .mi,
            .l => .lt,
            .le => .le,
            else => return null,
        },
        // After an addition both carries agree, so `above` has no single
        // ARM condition.
        .add => switch (base) {
            .o => .vs,
            .b => .hs,
            .e => .eq,
            .s => .mi,
            .l => .lt,
            .le => .le,
            else => return null,
        },
        // inc and dec leave CF alone, and NZCV's C is not it.
        .inc, .dec => switch (base) {
            .o => .vs,
            .e => .eq,
            .s => .mi,
            .l => .lt,
            .le => .le,
            else => return null,
        },
        // A logic operation clears CF and OF, as ANDS clears C and V.
        .logic => switch (base) {
            .e, .be => .eq,
            .s => .mi,
            .l => .lt,
            .le => .le,
            else => return null,
        },
    };
    return if (@intFromEnum(cond) & 1 != 0) positive.invert() else positive;
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

const PackedFloatForm = struct { lanes: a64.FpLanes, kind: FloatBinary };

fn packedFloatForm(op: Op) ?PackedFloatForm {
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

/// Memory read-modify-writes that must be host-atomic before guest execution
/// can be split across host threads. `xchg` with memory is locked whether or
/// not it carries the prefix. The arithmetic/logic update forms use a CAS
/// loop because ARM's LSE has no single-instruction AND/OR/XOR or SUB form.
/// Acquire-release atomics preserve the locked operation's ordering edge.
const AtomicForm = enum {
    exchange,
    compare_exchange,
    compare_exchange8b,
    compare_exchange16b,
    exchange_add,
    update,
    increment,
    decrement,
    negate,
    bitwise_not,
    bit_set,
    bit_reset,
    bit_complement,
};

fn atomicForm(op: Op) ?AtomicForm {
    return switch (op) {
        .xchg_mem8_reg8, .xchg_mem32_reg32, .xchg_mem64_reg64 => .exchange,
        .cmpxchg_mem8_reg8, .cmpxchg_mem16_reg16, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64 => .compare_exchange,
        .cmpxchg8b_mem => .compare_exchange8b,
        .cmpxchg16b_mem => .compare_exchange16b,
        .xadd_mem8_reg8, .xadd_mem32_reg32, .xadd_mem64_reg64 => .exchange_add,
        .bts_mem_imm => .bit_set,
        .btr_mem_imm => .bit_reset,
        .btc_mem_imm => .bit_complement,
        .bts_mem_reg => .bit_set,
        .btr_mem_reg => .bit_reset,
        .btc_mem_reg => .bit_complement,
        .inc_mem8, .inc_mem16, .inc_mem32, .inc_mem64 => .increment,
        .dec_mem8, .dec_mem16, .dec_mem32, .dec_mem64 => .decrement,
        .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => .negate,
        .not_mem8, .not_mem16, .not_mem32, .not_mem64 => .bitwise_not,
        .add_mem8_reg8,
        .add_mem16_reg16,
        .add_mem32_reg32,
        .add_mem64_reg64,
        .add_mem8_imm8,
        .add_mem16_imm8,
        .add_mem32_imm8,
        .add_mem64_imm8,
        .add_mem16_imm32,
        .add_mem32_imm32,
        .add_mem64_imm32,
        .sub_mem8_reg8,
        .sub_mem16_reg16,
        .sub_mem32_reg32,
        .sub_mem64_reg64,
        .sub_mem8_imm8,
        .sub_mem16_imm8,
        .sub_mem32_imm8,
        .sub_mem64_imm8,
        .sub_mem16_imm32,
        .sub_mem32_imm32,
        .sub_mem64_imm32,
        .and_mem8_reg8,
        .and_mem16_reg16,
        .and_mem32_reg32,
        .and_mem64_reg64,
        .and_mem8_imm8,
        .and_mem16_imm8,
        .and_mem32_imm8,
        .and_mem64_imm8,
        .and_mem16_imm32,
        .and_mem32_imm32,
        .and_mem64_imm32,
        .or_mem8_reg8,
        .or_mem16_reg16,
        .or_mem32_reg32,
        .or_mem64_reg64,
        .or_mem8_imm8,
        .or_mem16_imm8,
        .or_mem32_imm8,
        .or_mem64_imm8,
        .or_mem16_imm32,
        .or_mem32_imm32,
        .or_mem64_imm32,
        .xor_mem8_reg8,
        .xor_mem16_reg16,
        .xor_mem32_reg32,
        .xor_mem64_reg64,
        .xor_mem8_imm8,
        .xor_mem16_imm8,
        .xor_mem32_imm8,
        .xor_mem64_imm8,
        .xor_mem16_imm32,
        .xor_mem32_imm32,
        .xor_mem64_imm32,
        .adc_mem8_reg8,
        .adc_mem16_reg16,
        .adc_mem32_reg32,
        .adc_mem64_reg64,
        .adc_mem8_imm8,
        .adc_mem16_imm8,
        .adc_mem32_imm8,
        .adc_mem64_imm8,
        .adc_mem16_imm32,
        .adc_mem32_imm32,
        .adc_mem64_imm32,
        .sbb_mem8_reg8,
        .sbb_mem16_reg16,
        .sbb_mem32_reg32,
        .sbb_mem64_reg64,
        .sbb_mem8_imm8,
        .sbb_mem16_imm8,
        .sbb_mem32_imm8,
        .sbb_mem64_imm8,
        .sbb_mem16_imm32,
        .sbb_mem32_imm32,
        .sbb_mem64_imm32,
        => .update,
        else => null,
    };
}

/// Whether an explicitly supplied LOCK prefix is architecturally valid for
/// this decoded form. Valid memory operations may still use the interpreter
/// when the native path cannot prove alignment or protection state.
pub fn lockPrefixAllowed(d: DecodedInsn) bool {
    if (!d.lock) return true;
    if (d.is_reg_form) return false;
    if (atomicForm(d.op) != null) return true;
    switch (d.op) {
        .adc_mem8_reg8,
        .adc_mem16_reg16,
        .adc_mem32_reg32,
        .adc_mem64_reg64,
        .sbb_mem8_reg8,
        .sbb_mem16_reg16,
        .sbb_mem32_reg32,
        .sbb_mem64_reg64,
        .adc_mem8_imm8,
        .adc_mem16_imm8,
        .adc_mem32_imm8,
        .adc_mem64_imm8,
        .adc_mem16_imm32,
        .adc_mem32_imm32,
        .adc_mem64_imm32,
        .sbb_mem8_imm8,
        .sbb_mem16_imm8,
        .sbb_mem32_imm8,
        .sbb_mem64_imm8,
        .sbb_mem16_imm32,
        .sbb_mem32_imm32,
        .sbb_mem64_imm32,
        => return true,
        else => {},
    }
    if (d.op == .cmpxchg8b_mem or d.op == .cmpxchg16b_mem or
        d.op == .bts_mem_reg or d.op == .btr_mem_reg or d.op == .btc_mem_reg)
    {
        return true;
    }
    if (isIncDec(d.op)) |form| return form.mem;
    switch (d.op) {
        .neg_mem8,
        .neg_mem16,
        .neg_mem32,
        .neg_mem64,
        .not_mem8,
        .not_mem16,
        .not_mem32,
        .not_mem64,
        => return true,
        else => {},
    }
    if (binaryOpOf(d.op)) |operation| {
        if (binaryShapeOf(d.op) != .mem_reg and binaryShapeOf(d.op) != .mem_imm) return false;
        return switch (operation) {
            .add, .adc, .sub, .sbb, .bit_and, .bit_or, .bit_xor => true,
            .cmp, .tst => false,
        };
    }
    return false;
}

pub fn isVectorNative(d: DecodedInsn) bool {
    if (d.is_evex or d.vector_512 or d.opmask != 0 or d.evex_broadcast) return false;
    // MOVQ r/m64 -> XMM has identical low-128-bit behavior in its legacy and
    // VEX forms. The legacy form preserves YMM upper state, so its emitter
    // deliberately skips the VEX upper-clear below.
    if (d.legacy_sse) return switch (d.op) {
        // These forms account for measured worker fallbacks in the Halo 3
        // trace. Their legacy encodings update only XMM state; the YMM upper
        // half must survive, unlike the corresponding VEX.128 operation.
        .movups_xmm_mem,
        .movups_mem_xmm,
        .vmovss_xmm_mem,
        .vmovsd_xmm_mem,
        .vmovss_mem_xmm,
        .vmovsd_mem_xmm,
        => memoryOperandSupported(d),
        // PUNPCKLQDQ is a pure 128-bit lane interleave. The VEX emitter below
        // already models it; suppressing the upper clear gives it legacy SSE
        // semantics without changing its low XMM result.
        .vpunpcklqdq => d.is_reg_form or memoryOperandSupported(d),
        .vmovq_xmm_reg64, .vmovq_reg64_xmm, .movaps_xmm_xmm => d.is_reg_form,
        else => false,
    };
    if (d.vector_256) {
        if (d.op == .vextractf128) return memoryOperandSupported(d);
        if (d.op == .vinsertf128 or d.op == .vpermilps) return d.is_reg_form or memoryOperandSupported(d);
        if (d.op == .vmovmskps or d.op == .vmovmskpd) return d.is_reg_form;
        if (d.op == .vptest or d.op == .vtestps or d.op == .vtestpd) return d.is_reg_form or memoryOperandSupported(d);
        if (packedFloatForm(d.op) != null or bitwiseForm(d.op) != null) return d.is_reg_form or memoryOperandSupported(d);
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
        .vmovmskps, .vmovmskpd => d.is_reg_form,
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
        .vsqrtps, .vsqrtpd, .vsqrtss, .vsqrtsd, .vrcpps, .vrcpss, .vrsqrtps => d.is_reg_form or memoryOperandSupported(d),
        .vcvtss2sd, .vcvtsd2ss, .vcvtps2pd, .vcvtpd2ps, .vcvtdq2ps, .vcvttps2dq, .vcvtps2dq => d.is_reg_form or memoryOperandSupported(d),
        .vcvtsi2ss_xmm_reg, .vcvtsi2sd_xmm_reg => d.size == .bits32 or d.size == .bits64,
        .vcvtsi2ss_xmm_mem, .vcvtsi2sd_xmm_mem => (d.size == .bits32 or d.size == .bits64) and memoryOperandSupported(d),
        .vcvttss2si, .vcvttsd2si, .vcvtss2si, .vcvtsd2si => (d.size == .bits32 or d.size == .bits64) and (d.is_reg_form or memoryOperandSupported(d)),
        .vucomiss, .vucomisd => d.is_reg_form or memoryOperandSupported(d),
        .vcmpps, .vcmppd => d.is_reg_form or memoryOperandSupported(d),
        .vptest, .vtestps, .vtestpd => d.is_reg_form or memoryOperandSupported(d),
        .vpermilps => d.is_reg_form or memoryOperandSupported(d),
        .vextractf128 => d.vector_256 and memoryOperandSupported(d),
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
    /// The RIP the block leaves to, or null when a helper already stored it
    /// in the register file (a fallback or a shim that transferred control).
    rip: ?u64,
    /// The RIP is already in `r_exit_rip` (an indirect transfer's target).
    rip_in_register: bool = false,
};

/// Where an exit hands its RIP to the chain. Only the leave path writes it
/// to the register file: a chain hop never needed it there, and storing it
/// in every exit stub only to load it again in the chain put a store and a
/// dependent load on every hop.
const r_exit_rip: a64.Reg = 8;

const Compiler = struct {
    a: *Assembler,
    layout: Layout,
    insns: []const Insn,
    end_rip: u64,
    /// The code-fetch ledger this block's retired instructions count to.
    ledger: Ledger = .image,
    /// Exits owe every flag (`Options.exact_exit_flags`).
    exact_exit_flags: bool = false,
    /// A helper that may set `abort` was called since the last abort check
    /// (`emitAbortCheck`).
    abort_unchecked: bool = false,
    epilogue: Label,
    exit_path: Label,
    epilogue_path: Label,
    exits: std.ArrayList(ExitStub),
    /// Full-probe paths of hoisted accesses, emitted after the block body so
    /// the hot path is the pointer test and the access alone.
    cold_accesses: std.ArrayList(ColdAccess) = .empty,
    cold_memory: std.ArrayList(ColdMemory) = .empty,
    allocator: std.mem.Allocator,
    /// Per instruction: whether its flag computation must be emitted.
    flag_wants: []const bool,
    flag_live: []const u8,
    /// Per instruction, the flags a later instruction *in this block* reads.
    /// What a deferrable writer owes eagerly; the record carries the rest.
    flag_live_block: []const u8,
    /// Per instruction, the flags live after it along its fall-through.
    flag_live_fall: []const u8,
    /// Per instruction, the flags live before it: what a jump to it owes.
    flag_live_in: []const u8,
    /// Set while emitting a flag writer the next instruction's branch
    /// fuses with; the writer's compute sets NZCV and hands this on.
    fuse_pending: ?Fused = null,
    /// The fused writer whose flags are still owed, for the branch.
    fused: ?Fused = null,
    /// NZCV holds a fused writer's answer that a later reader still tests:
    /// emitted code must not change it (probes compare without flags, and
    /// helper calls save and restore it).
    nzcv_live: bool = false,
    /// Taken edges of fused branches: the flags owed, then the exit.
    fused_exits: std.ArrayList(FusedExit) = .empty,
    native_count: u32 = 0,
    fallback_count: u32 = 0,
    /// Conditional branches that tested NZCV set by the flag writer
    /// before them.
    fused_branches: u32 = 0,
    /// Flag writers whose readers tested NZCV.
    fused_runs: u32 = 0,
    touches_memory: bool = false,
    /// Reads or writes the vector register files. The glue's register-only
    /// cross-check restores only the general registers between its two
    /// runs, so a block that changes vector state must not be cross-checked
    /// (it would apply its vector effects twice); the differential tests
    /// cover vector templates instead.
    touches_vectors: bool = false,
    /// x87 has its own context-resident register file and is outside the GPR
    /// cross-check, even for register-only stack transfers.
    touches_x87: bool = false,
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
    /// Guest registers some instruction in the block writes (bit = register
    /// number), as the first pass found them; only these are written back
    /// from the cache. A register the block never writes holds exactly what
    /// the register file does - the interpreter calls reload the cache after
    /// changing it - so storing it again would only cost. All of them in a
    /// counting pass.
    written: u16 = 0,
    cache_written: u16 = 0xFFFF,
    flag_settles: u32 = 0,
    /// The two busiest address bases, admitted once per block and
    /// invalidated whenever their guest register changes. Constants may
    /// share the second pointer with no base register at all.
    hoists: [hoist_hosts.len]Hoist = @splat(.{}),
    hoisted_accesses: u32 = 0,
    /// Internal forward edges (`planInternalEdges`). Per instruction: for a
    /// conditional branch, the later instruction its taken edge jumps to;
    /// for a target, its label and the state every edge into it brings
    /// (whether x29 still holds the hoist on all of them, and whether any of
    /// them still owes an abort check).
    internal_target: []?u32 = &.{},
    internal_label: []?Label = &.{},
    internal_hoist: [][hoist_hosts.len]bool = &.{},
    internal_abort: []bool = &.{},
    /// A target was reached along the fall-through with NZCV still owed to
    /// a reader, which an edge from elsewhere could not supply: the block
    /// is emitted again without internal edges.
    internal_conflict: bool = false,
    uses_skip_counter: bool = false,
    internal_edges: u32 = 0,
    internal_sources: u128 = 0,
    /// A dominating VEX.128 write already zeroed these private register-file
    /// lanes. Facts are local to straight-line code, never an entry/edge.
    last_xmm: ?u8 = null,
    forward_xmm: bool = false,
    zero_ymm: u32 = 0,
    zero_zmm: u32 = 0,
    upper_clears_elided: u32 = 0,
    xmm_loads_forwarded: u32 = 0,

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
        try self.emitChecked(a64.stp(.pre_index, 29, 30, a64.sp, -112));
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
        switch (self.layout.register_files) {
            .inline_in_state => {
                try self.emitStateAddress(r_regs, self.layout.regs_offset);
                try self.emitStateAddress(r_scratch, self.layout.scratch_offset);
                if (self.layout.tlb_indirect) {
                    try self.emitStateScalar(.doubleword, r_tlb, self.layout.tlb_offset);
                } else {
                    try self.emitStateAddress(r_tlb, self.layout.tlb_offset);
                }
                try self.emitStateAddress(r_spare, self.layout.xmm_offset);
            },
            .pointers_in_scratch => {
                // The executing context's record arrives in x2, and its
                // files are found through it: nothing here reads a binding
                // another host thread could be rewriting.
                try self.emit(a64.mov(.x64, r_scratch, 2));
                try self.emitChecked(a64.ldrImm(.doubleword, r_regs, r_scratch, scratch_regs_file_offset));
                try self.emitChecked(a64.ldrImm(.doubleword, r_tlb, r_scratch, scratch_tlb_file_offset));
                try self.emitChecked(a64.ldrImm(.doubleword, r_spare, r_scratch, scratch_xmm_file_offset));
            },
        }
    }

    const VectorFile = enum { ymm_hi, zmm_hi };

    /// `dst` = the address `extra` bytes into the executing context's
    /// ymm-upper or zmm-upper file.
    fn emitRegisterFileAddress(self: *Compiler, dst: a64.Reg, file: VectorFile, extra: u32) Error!void {
        switch (self.layout.register_files) {
            .inline_in_state => {
                const offset = switch (file) {
                    .ymm_hi => self.layout.ymm_hi_offset,
                    .zmm_hi => self.layout.zmm_hi_offset,
                };
                return self.emitStateAddress(dst, offset + extra);
            },
            .pointers_in_scratch => try self.emitChecked(a64.ldrImm(.doubleword, dst, r_scratch, switch (file) {
                .ymm_hi => scratch_ymm_hi_file_offset,
                .zmm_hi => scratch_zmm_hi_file_offset,
            })),
        }
        if (extra == 0) return;
        if (extra <= 4095) {
            try self.emitChecked(a64.addImm(.x64, dst, dst, @intCast(extra)));
        } else {
            try self.a.loadConstant(t5, extra);
            try self.emit(a64.add(.x64, dst, dst, t5));
        }
    }

    fn emitEpilogue(self: *Compiler) Error!void {
        self.a.placeLabel(self.epilogue);
        try self.emitChecked(a64.ldp(.signed_offset, cache_host_regs[2], cache_host_regs[3], a64.sp, 80));
        try self.emitChecked(a64.ldp(.signed_offset, cache_host_regs[0], cache_host_regs[1], a64.sp, 64));
        try self.emitChecked(a64.ldp(.signed_offset, r_tlb, r_spare, a64.sp, 48));
        try self.emitChecked(a64.ldp(.signed_offset, r_helpers, r_scratch, a64.sp, 32));
        try self.emitChecked(a64.ldp(.signed_offset, r_state, r_regs, a64.sp, 16));
        try self.emitChecked(a64.ldp(.post_index, 29, 30, a64.sp, 112));
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
                try self.a.loadConstant(r_exit_rip, rip);
            } else if (!stub.rip_in_register) {
                try self.emitChecked(a64.ldrImm(.doubleword, r_exit_rip, r_regs, rip_offset));
            }
            try self.a.loadConstant(0, stub.completed);
            try self.a.branch(self.exit_path);
        }
    }

    /// An exit whose RIP the template has just put in `r_exit_rip`.
    fn exitStubWithRipInRegister(self: *Compiler, completed: u32) Error!Label {
        const label = try self.a.createLabel();
        try self.exits.append(self.allocator, .{ .label = label, .completed = completed, .rip = null, .rip_in_register = true });
        return label;
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
        self.written |= @as(u16, 1) << @intCast(index);
        for (&self.hoists) |*hoist| {
            if (hoist.base == id) hoist.live = false;
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

    /// `storeReg` for a source already zero-extended to 64 bits, as every
    /// 32-bit load leaves it: the 32-bit case needs no extending move.
    fn storeRegExtended(self: *Compiler, id: RegId, high8: bool, size: Size, src: a64.Reg) Error!void {
        if (size != .bits32) return self.storeReg(id, high8, size, src);
        const index: usize = @intFromEnum(id);
        self.use_counts[index] +|= 1;
        self.written |= @as(u16, 1) << @intCast(index);
        for (&self.hoists) |*hoist| {
            if (hoist.base == id) hoist.live = false;
        }
        if (self.cache_slot[index]) |slot| {
            try self.emit(a64.mov(.x64, cache_host_regs[slot], src));
            return;
        }
        try self.emitChecked(a64.strImm(.doubleword, src, r_regs, gprOffset(id)));
    }

    /// Read every cached guest register out of the register file.
    fn emitCacheLoad(self: *Compiler) Error!void {
        for (self.cache_ids[0..self.cache_count], 0..) |id, slot| {
            try self.emitChecked(a64.ldrImm(.doubleword, cache_host_regs[slot], r_regs, gprOffset(id)));
        }
    }

    /// Write back every cached guest register the block writes anywhere.
    /// Whole registers, on every path: one the block writes on some other
    /// path still holds exactly what memory does here, so writing it is
    /// harmless, while one the block never writes (`written`, from the
    /// counting pass) needs no store at all. Xenia's context and membase
    /// registers, read on every instruction and never written, are the
    /// common case.
    fn emitCacheWriteBack(self: *Compiler) Error!void {
        for (self.cache_ids[0..self.cache_count], 0..) |id, slot| {
            if (self.cache_written & (@as(u16, 1) << @intFromEnum(id)) == 0) continue;
            try self.emitChecked(a64.strImm(.doubleword, cache_host_regs[slot], r_regs, gprOffset(id)));
        }
    }

    /// Around a C call: the cache registers it would clobber, to their
    /// register-file slots and back. Clean ones too, since the call loses
    /// them either way; a helper that changes a guest register changes its
    /// slot, so the reload also picks that up.
    fn emitCallerSavedCacheSpill(self: *Compiler, reload: bool) Error!void {
        if (self.cache_count <= cache_callee_saved) return;
        for (self.cache_ids[cache_callee_saved..self.cache_count], cache_callee_saved..) |id, slot| {
            if (reload) {
                try self.emitChecked(a64.ldrImm(.doubleword, cache_host_regs[slot], r_regs, gprOffset(id)));
            } else {
                try self.emitChecked(a64.strImm(.doubleword, cache_host_regs[slot], r_regs, gprOffset(id)));
            }
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
    /// already stored. It accounts what this block retired, and then - if
    /// the successor is a block it went to before, or one the thread's jump
    /// cache names, and that block is still valid - jumps straight into its
    /// body instead of returning.
    ///
    /// That jump is the point. Returning costs an indirect call's
    /// misprediction, a probe of the block table to find the successor
    /// again, and a trip through the glue's loop - about 25 ns against 8
    /// for a hop - all for a block that retires about twenty instructions.
    /// What a hop proves is read from the block in the named slot now: it
    /// is a block for this guest address, it is armed, and its source still
    /// carries the generation its bytes were proven at.
    fn emitChainAttempt(self: *Compiler) Error!void {
        self.a.placeLabel(self.exit_path);
        // The stub's count assumes every instruction before the exit ran;
        // internal edges jumped over `skip_reg` of them.
        if (self.uses_skip_counter) try self.emit(a64.sub(.x64, 0, 0, skip_reg));
        // Whatever runs next - a chained block, the glue, the interpreter,
        // a fault handler building a context - reads guest registers from
        // the register file, so the cache has to be there first.
        try self.emitCacheWriteBack();
        const leave = self.epilogue_path;
        // Account this block, whether or not the chain goes on: one more
        // block, x0 more instructions. x0 stays as it is, since it is also
        // what the glue receives when this is the last block.
        try self.emitChecked(a64.ldrImm(.doubleword, t1, r_scratch, scratch_chain_count_offset));
        try self.emit(a64.addSubShifted(.x64, .add, false, t1, t1, 0, chain_count_shift));
        try self.emitChecked(a64.addImm(.x64, t1, t1, 1));
        try self.emitChecked(a64.strImm(.doubleword, t1, r_scratch, scratch_chain_count_offset));
        switch (self.ledger) {
            .code_cache => {},
            .image, .other_mapped => {
                const offset = if (self.ledger == .image) scratch_chain_retired_image_offset else scratch_chain_retired_other_mapped_offset;
                try self.emitChecked(a64.ldrImm(.doubleword, t3, r_scratch, offset));
                try self.emit(a64.add(.x64, t3, t3, 0));
                try self.emitChecked(a64.strImm(.doubleword, t3, r_scratch, offset));
            },
        }
        // A helper has asked for the scheduler, the run has ended, or a
        // fault is pending (a helper that sets `abort` sets this too); or
        // the glue's instruction budget for this step is spent.
        try self.emitChecked(a64.ldrImm(.word, t0, r_scratch, scratch_chain_break_offset));
        try self.a.branchIfNonZero(.w32, t0, leave);
        try self.emitChecked(a64.ldrImm(.doubleword, t3, r_scratch, scratch_chain_budget_offset));
        try self.emit(a64.cmp(.x64, t1, t3));
        try self.a.branchCond(.hs, leave);
        // t4 = the successor's guest address, t2 = this block.
        try self.emit(a64.mov(.x64, t4, r_exit_rip));
        try self.emitChecked(a64.ldrImm(.doubleword, t2, r_helpers, helper_block_offset));
        const prove = try self.a.createLabel();
        // A block that leaves through `ret` or an indirect transfer has more
        // successors than ways, so it asks the jump cache first; any other
        // asks its own ways first, where a direct exit always is.
        const indirect = self.endsIndirect();
        if (indirect) {
            const ways = try self.a.createLabel();
            try self.emitJumpCacheProbe(prove, ways);
            self.a.placeLabel(ways);
            try self.emitWayScan(prove);
            try self.a.branch(leave);
        } else {
            try self.emitWayScan(prove);
            try self.emitJumpCacheProbe(prove, leave);
        }
        // t6 = the link. t5 = the block in its slot now, acquired: a slot
        // is published after the block in it is complete.
        self.a.placeLabel(prove);
        try self.emitChecked(a64.ldrImm(.doubleword, t3, t6, @offsetOf(Link, "slot")));
        try self.emit(a64.ldar(.doubleword, t5, t3));
        try self.a.branchIfZero(.x64, t5, leave);
        try self.emitChecked(a64.ldrImm(.doubleword, t3, t5, @offsetOf(Block, "start_rip")));
        try self.emit(a64.cmp(.x64, t3, t4));
        try self.a.branchCond(.ne, leave);
        // Mapped code generations are release-published by any guest worker
        // that writes code; the block's armed generation is the one its
        // bytes were proven at.
        try self.emitChecked(a64.ldrImm(.doubleword, t3, t5, @offsetOf(Block, "chain_gen_ptr")));
        try self.emitChecked(a64.ldrImm(.doubleword, t3, t3, 0));
        try self.emitChecked(a64.ldrImm(.doubleword, t1, t5, @offsetOf(Block, "chain_generation")));
        try self.emit(a64.cmp(.x64, t3, t1));
        try self.a.branchCond(.ne, leave);
        // Go. `scratch.block` follows the chain because the continuation
        // check reads it to decide whether a store hit the code ahead.
        try self.emitChecked(a64.strImm(.doubleword, t2, r_scratch, scratch_chain_previous_offset));
        try self.emitChecked(a64.strImm(.doubleword, t5, r_scratch, scratch_block_offset));
        try self.emitStateOffsetAddress(r_helpers, t5, @offsetOf(Block, "helpers"));
        try self.emitChecked(a64.ldrImm(.doubleword, t3, t5, @offsetOf(Block, "chain_entry_address")));
        try self.emit(a64.br(t3));
    }

    /// Whether the block's last instruction is a transfer whose target is
    /// only known at run time.
    fn endsIndirect(self: *const Compiler) bool {
        if (self.insns.len == 0) return false;
        return switch (self.insns[self.insns.len - 1].decoded.op) {
            .ret, .jmp_reg64, .jmp_mem64, .call_reg64, .call_mem64 => true,
            else => false,
        };
    }

    /// Branch to `prove` with t6 = the way whose address is t4. Each way
    /// costs only its address compare; the way that matches is proved once.
    fn emitWayScan(self: *Compiler, prove: Label) Error!void {
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
    }

    /// Branch to `prove` with t6 = the jump-cache entry for t4 when it names
    /// t4, else to `miss`.
    fn emitJumpCacheProbe(self: *Compiler, prove: Label, miss: Label) Error!void {
        try self.emitChecked(a64.ldrImm(.doubleword, t3, r_scratch, scratch_jump_cache_offset));
        try self.a.branchIfZero(.x64, t3, miss);
        try self.emit(a64.lsrImm(.x64, t5, t4, jump_cache_shift));
        try self.emit(a64.eorReg(.x64, t5, t5, t4));
        try self.emit(a64.logicalImmediate(.x64, .andop, t5, t5, jump_cache_entries - 1).?);
        try self.emit(a64.addSubShifted(.x64, .add, false, t6, t3, t5, std.math.log2_int(usize, @sizeOf(Link))));
        try self.emitChecked(a64.ldrImm(.doubleword, t5, t6, @offsetOf(Link, "rip")));
        try self.emit(a64.cmp(.x64, t5, t4));
        try self.a.branchCond(.ne, miss);
        try self.a.branch(prove);
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
        // Leaving for the glue: now the register file needs the RIP.
        try self.emitChecked(a64.strImm(.doubleword, r_exit_rip, r_regs, rip_offset));
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
        // Only the flags this instruction writes *and* something later
        // reads are cleared and recomputed. The rest keep their previous
        // value, which is exactly what being dead means - and when the
        // record is armed, "later" means later *in this block*, because
        // anything that leaves reads them from the record. Without the
        // record, `emit_flag_mask` is the live-out set with every exit
        // counted as reading all six: a `cmp` feeding Xenia's three `setcc`
        // into a condition register computes ZF, SF and OF, not parity, the
        // auxiliary carry and the carry too. This was F_ALL from when the
        // record was introduced until 2026-10-02, which left the per-flag
        // liveness computed and unused.
        const live = if (defer_rest) self.flag_live_block[self.current] else self.emit_flag_mask;
        if (!defer_rest and !self.emit_flags) return;
        try self.emitArithmeticFlagsLive(kind, size, a, b, r, carry_in_t6, live);
    }

    /// The flags of `a op b = r` that `live` names, into `rflags`.
    fn emitArithmeticFlagsLive(self: *Compiler, kind: ArithKind, size: Size, a: a64.Reg, b: a64.Reg, r: a64.Reg, carry_in_t6: bool, live: u8) Error!void {
        const width = arm(size);
        const w = bits(size);
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
        if (d.sib_has_base) {
            // The base straight into `dst` and a displacement that fits an
            // immediate folded into one add or sub: `[rsi+0x40]` costs two
            // instructions rather than a constant load, a register move and
            // an add, and one when the base is cached. Most of Xenia's
            // operands are a register plus a small displacement.
            if (self.cachedRegister(d.sib_base_reg)) |host| {
                try self.emitAddDisplacementFrom(dst, host, displacement);
            } else {
                try self.loadReg(dst, d.sib_base_reg, false, .bits64);
                try self.emitAddDisplacement(dst, displacement);
            }
        } else {
            try self.a.loadConstant(dst, displacement);
        }
        if (d.sib_has_index) {
            const index_reg = self.cachedRegister(d.sib_index_reg) orelse blk: {
                try self.loadReg(t0, d.sib_index_reg, false, .bits64);
                break :blk t0;
            };
            try self.emit(a64.addSubShifted(.x64, .add, false, dst, dst, index_reg, d.sib_scale));
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

    /// The host register caching guest `id` whole, for an address.
    fn cachedRegister(self: *const Compiler, id: RegId) ?a64.Reg {
        const slot = self.cache_slot[@intFromEnum(id)] orelse return null;
        return cache_host_regs[slot];
    }

    /// `dst = base + displacement`, one instruction when it fits.
    fn emitAddDisplacementFrom(self: *Compiler, dst: a64.Reg, base: a64.Reg, displacement: u64) Error!void {
        const negative = displacement >> 63 != 0;
        const magnitude: u64 = if (negative) (~displacement +% 1) else displacement;
        if (magnitude <= 0xFFF) {
            try self.emitChecked(if (negative) a64.subImm(.x64, dst, base, magnitude) else a64.addImm(.x64, dst, base, magnitude));
            return;
        }
        try self.a.loadConstant(t0, displacement);
        try self.emit(a64.add(.x64, dst, base, t0));
    }

    /// `dst += displacement` (a sign-extended x86 displacement), as one
    /// immediate add or sub when it fits.
    fn emitAddDisplacement(self: *Compiler, dst: a64.Reg, displacement: u64) Error!void {
        if (displacement == 0) return;
        const negative = displacement >> 63 != 0;
        const magnitude: u64 = if (negative) (~displacement +% 1) else displacement;
        if (magnitude <= 0xFFF) {
            try self.emitChecked(if (negative) a64.subImm(.x64, dst, dst, magnitude) else a64.addImm(.x64, dst, dst, magnitude));
            return;
        }
        try self.a.loadConstant(t0, displacement);
        try self.emit(a64.add(.x64, dst, dst, t0));
    }

    // -- helper calls ---------------------------------------------------------

    fn emitCallHelper(self: *Compiler, offset: u32) Error!void {
        self.last_xmm = null;
        try self.emitCallerSavedCacheSpill(false);
        // BLR overwrites LR. Its caller return address remains at sp+8;
        // sp+96 preserves the second page pointer independently of it.
        if (self.hoists[1].planned) try self.emitChecked(a64.strImm(.doubleword, hoist_hosts[1], a64.sp, 96));
        if (self.uses_skip_counter) try self.emitChecked(a64.strImm(.doubleword, skip_reg, r_scratch, scratch_skip_spill_offset));
        if (self.nzcv_live) {
            // A C call does not preserve NZCV, and a fused run's later
            // readers test it.
            try self.emit(a64.mrsNzcv(t0));
            try self.emitChecked(a64.strImm(.doubleword, t0, r_scratch, scratch_saved_nzcv_offset));
            try self.emitChecked(a64.ldrImm(.doubleword, t0, r_helpers, offset));
            try self.emit(a64.blr(t0));
            try self.emitChecked(a64.ldrImm(.doubleword, t1, r_scratch, scratch_saved_nzcv_offset));
            try self.emit(a64.msrNzcv(t1));
        } else {
            try self.emitChecked(a64.ldrImm(.doubleword, t0, r_helpers, offset));
            try self.emit(a64.blr(t0));
        }
        if (self.hoists[1].planned) try self.emitChecked(a64.ldrImm(.doubleword, hoist_hosts[1], a64.sp, 96));
        try self.emitCallerSavedCacheSpill(true);
        if (self.uses_skip_counter) try self.emitChecked(a64.ldrImm(.doubleword, skip_reg, r_scratch, scratch_skip_spill_offset));
        // The flag helper never sets `abort`; any other helper leaves the
        // instruction's abort check to emit.
        if (offset != helper_flags_offset) self.abort_unchecked = true;
    }

    /// Tell the helpers which instruction is calling.
    fn emitCurrentIndex(self: *Compiler, index: u32) Error!void {
        try self.a.loadConstant(t0, index);
        try self.emitChecked(a64.strImm(.word, t0, r_scratch, scratch_index_offset));
    }

    /// The TLB probe shared by loads and stores: with the guest address in
    /// x1, leaves the host address in t4 and falls through on a hit, or
    /// branches to `slow` on a miss or an access that leaves the page.
    /// Clobbers t2, t3 and t5; never t6, which some callers hold across it.
    ///
    /// `alignment_guarded` says the caller rejects a host pointer that is
    /// not aligned to `access_bytes` before it touches memory. A naturally
    /// aligned access of a power-of-two size cannot leave its page, so the
    /// page-span compare is then redundant and is not emitted. Guest and
    /// host addresses share the page offset, so the caller's guard on the
    /// host pointer is the same test on the guest operand.
    ///
    /// The tag and the delta come from one `ldp`. Only the table's owner ever
    /// writes a delta - other threads only retire tags - so the pair read is
    /// either the entry's valid tag with its valid delta, or a miss.
    fn emitTlbProbe(self: *Compiler, is_write: bool, access_bytes: u64, alignment_guarded: bool, slow: Label) Error!void {
        try self.emit(a64.lsrImm(.x64, t2, 1, Tlb.page_shift));
        try self.emit(a64.logicalShifted(.x64, .eor, t3, t2, t2, Tlb.fold_shift) | (0b01 << 22)); // eor t3, t2, t2, lsr #fold
        try self.emit(a64.logicalImmediate(.x64, .andop, t3, t3, Tlb.entries - 1).?);
        try self.emit(a64.addSubShifted(.x64, .add, false, t3, r_tlb, t3, 4));
        if (is_write) try self.emitChecked(a64.addImm(.x64, t3, t3, tlb_write_offset));
        try self.emitChecked(a64.ldp(.signed_offset, t4, t5, t3, 0));
        // The tag compare leaves NZCV alone: a fused flag writer's readers
        // may still need it across this access.
        try self.emit(a64.eorReg(.x64, t4, t4, t2));
        try self.a.branchIfNonZero(.x64, t4, slow);
        if (!tlbProbeSpanProven(access_bytes, alignment_guarded)) {
            try self.emit(a64.logicalImmediate(.x64, .andop, t2, 1, Tlb.page_bytes - 1).?);
            if (self.nzcv_live) {
                // offset + bytes - 1 reaches the next page exactly when it
                // carries into bit 12; no compare, so NZCV survives.
                try self.emitChecked(a64.addImm(.x64, t2, t2, access_bytes - 1));
                try self.emit(a64.lsrImm(.x64, t2, t2, Tlb.page_shift));
                try self.a.branchIfNonZero(.x64, t2, slow);
            } else {
                try self.emitChecked(a64.cmpImm(.x64, t2, Tlb.page_bytes - access_bytes));
                try self.a.branchCond(.hi, slow);
            }
        }
        try self.emit(a64.add(.x64, t4, 1, t5));
    }

    /// Ordered scalar access on a naturally aligned, proven host pointer.
    /// Acquire/release is sufficient for the shared path's load/load,
    /// load/store and store/store edges, and also orders more than x86
    /// requires at a store/load edge. The caller routes legal x86 unaligned
    /// accesses through the byte-atomic helper before reaching this point.
    fn emitOrderedScalar(self: *Compiler, is_write: bool, size: Size, data: a64.Reg, host: a64.Reg) Error!void {
        const ms = memSize(size);
        try self.emit(if (is_write) a64.stlr(ms, data, host) else a64.ldar(ms, data, host));
    }

    /// Preserve the x86 allowance for tearing on ordinary unaligned scalar
    /// accesses while keeping each host byte access data-race-free. The
    /// mapping's page-span check runs before this helper, so even the final
    /// byte cannot cross into an unadmitted page.
    fn emitOrderedUnalignedScalarLoad(self: *Compiler, size: Size, destination: a64.Reg, host: a64.Reg) Error!void {
        const byte_count = bits(size) / 8;
        try self.emit(a64.eorReg(.x64, destination, destination, destination));
        for (0..byte_count) |byte_index| {
            try self.emit(a64.ldar(.byte, t2, host));
            const shift: u6 = @intCast(byte_index * 8);
            if (shift != 0) try self.emit(a64.lslImm(.x64, t2, t2, shift));
            try self.emit(a64.orrReg(.x64, destination, destination, t2));
            if (byte_index + 1 != byte_count) try self.emitChecked(a64.addImm(.x64, host, host, 1));
        }
    }

    fn emitOrderedUnalignedScalarStore(self: *Compiler, size: Size, host: a64.Reg) Error!void {
        const byte_count = bits(size) / 8;
        for (0..byte_count) |byte_index| {
            const shift: u6 = @intCast(byte_index * 8);
            if (shift == 0) {
                try self.emit(a64.mov(.x64, t2, 3));
            } else {
                try self.emit(a64.lsrImm(.x64, t2, 3, shift));
            }
            try self.emit(a64.stlr(.byte, t2, host));
            if (byte_index + 1 != byte_count) try self.emitChecked(a64.addImm(.x64, host, host, 1));
        }
    }

    /// Route a host pointer that does not meet the host atomic instruction's
    /// natural alignment to the guest memory helper. Guest and host addresses
    /// preserve the same page offset in the TLB, so testing the translated
    /// pointer is equivalent to testing the guest operand.
    fn emitHostAlignmentGuard(self: *Compiler, host: a64.Reg, byte_count: u64, slow: Label) Error!void {
        if (byte_count <= 1) return;
        const scratch: a64.Reg = if (host == t5) t6 else t5;
        try self.emit(a64.logicalImmediate(.x64, .andop, scratch, host, byte_count - 1).?);
        try self.a.branchIfNonZero(.x64, scratch, slow);
    }

    /// Form a host pointer into the admitted hoisted page span. The caller
    /// passes a scratch destination so the hoisted base remains available to
    /// the other accesses in the same span.
    fn emitHostOffset(self: *Compiler, destination: a64.Reg, base: a64.Reg, offset: u64) Error!void {
        if (offset == 0) {
            try self.emit(a64.mov(.x64, destination, base));
        } else if (offset <= 4095) {
            try self.emitChecked(a64.addImm(.x64, destination, base, offset));
        } else {
            try self.a.loadConstant(t6, offset);
            try self.emit(a64.add(.x64, destination, base, t6));
        }
    }

    /// Access a vector memory operand as two ordered 64-bit guest accesses.
    /// X86 does not promise atomicity for arbitrary 128-bit vector operands;
    /// the scalar lanes avoid host-language data races with scalar accesses
    /// while retaining the possibility of a torn vector value.
    fn emitOrderedVectorLoad(self: *Compiler, vector: a64.Reg, host: a64.Reg) Error!void {
        try self.emit(a64.mov(.x64, t1, host));
        try self.emitOrderedScalar(false, .bits64, t0, host);
        try self.emit(a64.vinsGpr(.d2, vector, 0, t0));
        try self.emitChecked(a64.addImm(.x64, host, t1, 8));
        try self.emitOrderedScalar(false, .bits64, t2, host);
        try self.emit(a64.vinsGpr(.d2, vector, 1, t2));
    }

    fn emitOrderedVectorStore(self: *Compiler, vector: a64.Reg, host: a64.Reg) Error!void {
        try self.emit(a64.mov(.x64, t1, host));
        try self.emit(a64.vumov(.d2, t0, vector, 0));
        try self.emitOrderedScalar(true, .bits64, t0, host);
        try self.emitChecked(a64.addImm(.x64, host, t1, 8));
        try self.emit(a64.vumov(.d2, t0, vector, 1));
        try self.emitOrderedScalar(true, .bits64, t0, host);
    }

    /// A TLB hit already proves all sixteen bytes accessible. A packed x86
    /// vector need not be eight-byte aligned: choose aligned qwords, dwords,
    /// or bytes, retaining the same acquire/release ordering and permitted
    /// tearing instead of calling and re-admitting an already valid page.
    fn emitOrderedVectorAccess(self: *Compiler, vector: a64.Reg, host: a64.Reg, is_write: bool) Error!void {
        const words = try self.a.createLabel();
        const bytes = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.emit(a64.logicalImmediate(.x64, .andop, t0, host, 7).?);
        try self.a.branchIfNonZero(.x64, t0, words);
        if (is_write) try self.emitOrderedVectorStore(vector, host) else try self.emitOrderedVectorLoad(vector, host);
        try self.a.branch(done);
        self.a.placeLabel(words);
        try self.emit(a64.logicalImmediate(.x64, .andop, t0, host, 3).?);
        try self.a.branchIfNonZero(.x64, t0, bytes);
        try self.emitOrderedVectorLanes(vector, host, is_write, .s4, .word, 4);
        try self.a.branch(done);
        self.a.placeLabel(bytes);
        try self.emitOrderedVectorLanes(vector, host, is_write, .b16, .byte, 1);
        self.a.placeLabel(done);
    }

    fn emitOrderedVectorLanes(self: *Compiler, vector: a64.Reg, host: a64.Reg, is_write: bool, lanes: a64.Lanes, size: a64.MemSize, comptime width: usize) Error!void {
        try self.emit(a64.mov(.x64, t1, host));
        for (0..16 / width) |lane| {
            if (is_write) {
                try self.emit(a64.vumov(lanes, t0, vector, @intCast(lane)));
                try self.emit(a64.stlr(size, t0, t1));
            } else {
                try self.emit(a64.ldar(size, t0, t1));
                try self.emit(a64.vinsGpr(lanes, vector, @intCast(lane), t0));
            }
            if (lane + 1 != 16 / width) try self.emitChecked(a64.addImm(.x64, t1, t1, width));
        }
    }

    /// x0 = read(state, x1, size), on behalf of instruction `index`: through
    /// the TLB when the page is admitted, through the helper otherwise.
    fn emitRead(self: *Compiler, size: Size, index: u32) Error!void {
        return self.emitReadInto(size, index, 0);
    }

    /// The read into `dest`: straight from the host page on a TLB hit, from
    /// the helper's x0 otherwise. Zero-extended at 32 bits either way.
    fn emitReadInto(self: *Compiler, size: Size, index: u32, dest: a64.Reg) Error!void {
        return self.emitProbedScalar(false, size, index, dest);
    }

    /// write(state, x1, size, x3), on behalf of instruction `index`.
    fn emitWrite(self: *Compiler, size: Size, index: u32) Error!void {
        return self.emitProbedScalar(true, size, index, 3);
    }

    /// The hot path of a probed scalar access - alignment test, TLB probe,
    /// one ordered access - falling through on a hit; the unaligned and the
    /// helper paths go out of line (`ColdMemory`). The guest address is in
    /// x1, a store's value in x3.
    fn emitProbedScalar(self: *Compiler, is_write: bool, size: Size, index: u32, data: a64.Reg) Error!void {
        self.touches_memory = true;
        const access_bytes = bits(size) / 8;
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        var unaligned: ?Label = null;
        if (access_bytes > 1 and access_bytes <= 8) {
            const label = try self.a.createLabel();
            try self.emit(a64.logicalImmediate(.x64, .andop, t2, 1, access_bytes - 1).?);
            try self.a.branchIfNonZero(.x64, t2, label);
            unaligned = label;
        }
        try self.emitTlbProbe(is_write, access_bytes, true, slow);
        try self.emitOrderedScalar(is_write, size, data, t4);
        self.a.placeLabel(done);
        try self.cold_memory.append(self.allocator, .{
            .unaligned = unaligned,
            .slow = slow,
            .done = done,
            .size = size,
            .index = index,
            .is_write = is_write,
            .dest = if (is_write) 0 else data,
            .nzcv_live = self.nzcv_live,
        });
        // The helper the miss calls may set `abort`; the instruction's own
        // check stays on the hot path, as it was when the call was inline.
        self.abort_unchecked = true;
    }

    /// Every probed access's unaligned path and helper call
    /// (`emitProbedScalar`), after the block body, each branching back to
    /// where its access completes.
    fn emitColdMemory(self: *Compiler) Error!void {
        var position: usize = 0;
        while (position < self.cold_memory.items.len) : (position += 1) {
            const cold = self.cold_memory.items[position];
            self.nzcv_live = cold.nzcv_live;
            defer self.nzcv_live = false;
            const access_bytes = bits(cold.size) / 8;
            if (cold.unaligned) |label| {
                self.a.placeLabel(label);
                try self.emitTlbProbe(cold.is_write, access_bytes, false, cold.slow);
                if (cold.is_write) {
                    try self.emitOrderedUnalignedScalarStore(cold.size, t4);
                } else {
                    try self.emitOrderedUnalignedScalarLoad(cold.size, cold.dest, t4);
                }
                try self.a.branch(cold.done);
            }
            self.a.placeLabel(cold.slow);
            try self.emitCurrentIndex(cold.index);
            try self.emit(a64.mov(.x64, 0, r_state));
            try self.a.loadConstant(2, @intFromEnum(cold.size));
            try self.emitCallHelper(if (cold.is_write) helper_write_offset else helper_read_offset);
            if (!cold.is_write and cold.dest != 0) try self.emit(a64.mov(.x64, cold.dest, 0));
            try self.a.branch(cold.done);
        }
    }

    /// Leave the block after instruction `index` when a helper asked for it.
    /// The instruction completes first: a helper may ask to stop and still
    /// have served its access. Only a helper sets `abort`, so nothing is
    /// emitted when no helper that could set it was called since the last
    /// check.
    fn emitAbortCheck(self: *Compiler, index: u32) Error!void {
        if (!self.abort_unchecked) return;
        self.abort_unchecked = false;
        if (self.fused) |fused| {
            // Inside a fused run: whoever runs next may read any of the
            // writer's flags, which are only in NZCV and in scratch.
            const next = self.insns[index].rip +% self.insns[index].len;
            const abort_path = try self.a.createLabel();
            try self.fused_exits.append(self.allocator, .{
                .label = abort_path,
                .fused = fused,
                .owed = fused.writes,
                .stub = try self.exitStub(index + 1, next),
            });
            try self.emitChecked(a64.ldrImm(.byte, t0, r_scratch, scratch_abort_offset));
            try self.a.branchIfNonZero(.w32, t0, abort_path);
            return;
        }
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

    /// Branch to `slow` for hooked image targets and external values the
    /// runtime cannot prove belong to the dedicated generated-code view. A
    /// proven Xenia code-cache address may take the native transfer template;
    /// every other out-of-image target remains classified by the interpreter.
    /// Clobbers x0-x1 and t0-t4; the original target is preserved in scratch.
    fn emitHookedTargetCheck(self: *Compiler, reg: a64.Reg, slow: Label) Error!void {
        const external = try self.a.createLabel();
        const external_unmapped = try self.a.createLabel();
        const external_outside_published_range = try self.a.createLabel();
        const checked = try self.a.createLabel();
        try self.emitStateScalar(.doubleword, t0, self.layout.image_low_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.lo, external);
        try self.emitStateScalar(.doubleword, t0, self.layout.image_high_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.hs, external);
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
        const bloom_miss = try self.a.createLabel();
        try self.a.branchIfZero(.w32, t3, bloom_miss);
        // Most Bloom hits are stale/retired census targets and should reach
        // the exact helper. These two are different: the guest critical-
        // section bridge keeps them pinned, and millions of calls hit them.
        // Check just those positive hits inline so the pinned fast bridge
        // does not pay an extra C helper call on every enter/leave.
        const not_enter = try self.a.createLabel();
        try self.emitStateScalar(.doubleword, t0, self.layout.xbox_critical_section_enter_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.ne, not_enter);
        try self.a.branch(slow);
        self.a.placeLabel(not_enter);
        const not_leave = try self.a.createLabel();
        try self.emitStateScalar(.doubleword, t0, self.layout.xbox_critical_section_leave_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.ne, not_leave);
        try self.a.branch(slow);
        self.a.placeLabel(not_leave);
        // The filter intentionally has one bit per address. Do not make its
        // false positives permanent interpreter exits: save the target, ask
        // the glue's exact hook tables, and continue natively on a miss.
        try self.emitChecked(a64.strImm(.doubleword, reg, r_scratch, scratch_transfer_target_offset));
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitChecked(a64.ldrImm(.doubleword, 1, r_scratch, scratch_transfer_target_offset));
        try self.emitCallHelper(helper_hooked_transfer_offset);
        try self.a.branchIfNonZero(.w32, 0, slow);
        try self.emitChecked(a64.ldrImm(.doubleword, reg, r_scratch, scratch_transfer_target_offset));
        self.a.placeLabel(bloom_miss);
        try self.a.branch(checked);

        self.a.placeLabel(external);
        // The dedicated code-cache mapping is immutable for the duration of
        // a translated step (map/unmap takes the guest address-space write
        // gate). Its published interval is therefore sufficient proof for
        // the hot Xenia generated-code target. Keep the general callback for
        // every other external address, where it still checks mapping source,
        // import stubs, synthetic entries, and hooks.
        try self.emitStateScalar(.doubleword, t0, self.layout.code_cache_high_offset);
        try self.a.branchIfZero(.x64, t0, external_unmapped);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.hs, external_outside_published_range);
        try self.emitStateScalar(.doubleword, t0, self.layout.code_cache_low_offset);
        try self.emit(a64.cmp(.x64, reg, t0));
        try self.a.branchCond(.lo, external_outside_published_range);
        try self.a.branch(checked);

        // Once the dedicated code-cache interval is published, the runtime
        // callback below cannot admit any target outside it: it checks this
        // exact view and interval again. The run profile showed 11.7M such
        // helper calls and zero admissions. Keep the callback only for the
        // bootstrap/unpublished case; a known out-of-range target can go
        // straight to the interpreter-owned transfer path.
        self.a.placeLabel(external_outside_published_range);
        try self.a.branch(slow);

        self.a.placeLabel(external_unmapped);
        try self.emitChecked(a64.strImm(.doubleword, reg, r_scratch, scratch_transfer_target_offset));
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitChecked(a64.ldrImm(.doubleword, 1, r_scratch, scratch_transfer_target_offset));
        try self.emitCallHelper(helper_mapped_transfer_offset);
        try self.a.branchIfZero(.w32, 0, slow);
        try self.emitChecked(a64.ldrImm(.doubleword, reg, r_scratch, scratch_transfer_target_offset));
        self.a.placeLabel(checked);
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
        for (&self.hoists) |*hoist| hoist.live = false;
        self.zero_ymm = 0;
        self.zero_zmm = 0;
        const stub = try self.exitStub(index + 1, null);
        try self.a.branchIfNonZero(.w32, 0, stub);
    }

    /// With x1 = an import slot's address: ask the runtime's lock-free import
    /// lanes to complete the call or tail jump through it, and branch to
    /// `declined` when none will - the interpreter's import path then runs
    /// the instruction from the start, because a declining lane changes
    /// nothing. On success RIP is already the return address.
    fn emitImportTransfer(self: *Compiler, index: u32, call_return: u64, declined: Label) Error!void {
        try self.emitCurrentIndex(index);
        // The lane reads the call's arguments and writes RAX, RIP and, for a
        // jump, RSP, all in the register file.
        try self.emitCacheWriteBack();
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.a.loadConstant(2, call_return);
        try self.emitCallHelper(helper_import_transfer_offset);
        try self.emitCacheLoad();
        for (&self.hoists) |*hoist| hoist.live = false;
        self.zero_ymm = 0;
        self.zero_zmm = 0;
        try self.a.branchIfZero(.w32, 0, declined);
    }

    /// These operations preserve the interpreter's exact raw x87 bytes and
    /// stack-fault behavior, but bypass its general opcode dispatch and
    /// fallback accounting. The focused helper returns nonzero only when the
    /// current block must leave (fault, termination, or modified continuation).
    fn emitX87RawTransferCall(self: *Compiler, index: u32) Error!void {
        try self.emitCurrentIndex(index);
        try self.emitCacheWriteBack();
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitChecked(a64.ldrImm(.doubleword, 1, r_helpers, helper_block_offset));
        try self.a.loadConstant(2, index);
        try self.emitCallHelper(helper_x87_raw_transfer_offset);
        try self.emitCacheLoad();
        for (&self.hoists) |*hoist| hoist.live = false;
        self.zero_ymm = 0;
        self.zero_zmm = 0;
        const stub = try self.exitStub(index + 1, null);
        try self.a.branchIfNonZero(.w32, 0, stub);
    }

    fn emitX87MemoryCall(self: *Compiler, index: u32) Error!void {
        try self.emitCurrentIndex(index);
        try self.emitCacheWriteBack();
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitChecked(a64.ldrImm(.doubleword, 1, r_helpers, helper_block_offset));
        try self.a.loadConstant(2, index);
        try self.emitCallHelper(helper_x87_memory_offset);
        try self.emitCacheLoad();
        for (&self.hoists) |*hoist| hoist.live = false;
        self.zero_ymm = 0;
        self.zero_zmm = 0;
        const stub = try self.exitStub(index + 1, null);
        try self.a.branchIfNonZero(.w32, 0, stub);
    }

    /// x1 = the effective address, then x0 = the operand read at `size`.
    /// Select up to two independent spans: context plus stack, another
    /// object, or constants. Indexed accesses retain their own probes.
    fn planHoist(self: *Compiler) void {
        const groups = 17; // sixteen guest registers plus absolute addresses
        var counts: [groups]u32 = @splat(0);
        var low: [groups]u64 = @splat(std.math.maxInt(u64));
        var high: [groups]u64 = @splat(0);
        var stores: [groups]bool = @splat(false);
        for (self.insns) |insn| {
            const candidate = hoistCandidate(insn) orelse continue;
            const index: usize = if (candidate.base) |base| @intFromEnum(base) else 16;
            counts[index] += 1;
            if (mayStoreMemoryOperand(insn.decoded.op)) stores[index] = true;
            const key = candidate.disp +% hoist_disp_bias;
            low[index] = @min(low[index], key);
            high[index] = @max(high[index], key +% candidate.bytes);
        }
        for (&self.hoists, 0..) |*hoist, slot| {
            var best: ?usize = null;
            for (counts, 0..) |count, index| {
                if (count < @as(u32, if (slot == 0) 2 else 4) or high[index] -% low[index] > hoist_max_span) continue;
                if (best == null or count > counts[best.?]) best = index;
            }
            const chosen = best orelse break;
            counts[chosen] = 0;
            hoist.* = .{
                .planned = true,
                .base = if (chosen < 16) @enumFromInt(chosen) else null,
                .dmin = low[chosen] -% hoist_disp_bias,
                .span = high[chosen] -% low[chosen],
                .write = stores[chosen],
            };
            const slack = hoist.dmin & 7;
            if (hoist.span + slack <= hoist_max_span) {
                hoist.dmin -%= slack;
                hoist.span += slack;
                hoist.aligned = true;
            }
        }
    }

    fn hoistedOffset(self: *const Compiler, insn: Insn, size: Size) ?HoistedOffset {
        return self.hoistedOffsetBytes(insn, bits(size) / 8, 0);
    }

    /// Find an admitted span containing this whole access, including the
    /// upper half of a 256-bit operand. Zero host pointers use cold probes.
    fn hoistedOffsetBytes(self: *const Compiler, insn: Insn, bytes: u64, extra: u64) ?HoistedOffset {
        const candidate = hoistCandidate(insn) orelse return null;
        for (self.hoists, 0..) |hoist, slot| {
            if (!hoist.planned or !hoist.live or candidate.base != hoist.base) continue;
            const offset = (candidate.disp -% hoist.dmin) +% extra;
            if (offset > hoist.span or bytes > hoist.span - offset) continue;
            return .{ .slot = slot, .offset = offset };
        }
        return null;
    }

    /// Resolve a span only when an instruction first uses it, including
    /// after a base write or an internal edge that skipped its admission.
    fn maybeEmitHoist(self: *Compiler, insn: Insn) Error!void {
        const candidate = hoistCandidate(insn) orelse return;
        for (&self.hoists, 0..) |*hoist, slot| {
            if (!hoist.planned or hoist.live or candidate.base != hoist.base) continue;
            const miss = try self.a.createLabel();
            const done = try self.a.createLabel();
            if (hoist.base) |base| {
                if (self.cachedRegister(base)) |host| {
                    try self.emitAddDisplacementFrom(1, host, hoist.dmin);
                } else {
                    try self.a.loadConstant(1, hoist.dmin);
                    try self.loadReg(t0, base, false, .bits64);
                    try self.emit(a64.add(.x64, 1, 1, t0));
                }
            } else {
                try self.a.loadConstant(1, hoist.dmin);
            }
            try self.emitTlbProbe(hoist.write, hoist.span, false, miss);
            if (hoist.aligned) {
                try self.emit(a64.logicalImmediate(.x64, .andop, t5, t4, 7).?);
                try self.a.branchIfNonZero(.x64, t5, miss);
            }
            try self.emit(a64.mov(.x64, hoist_hosts[slot], t4));
            try self.a.branch(done);
            self.a.placeLabel(miss);
            try self.emit(a64.mov(.x64, hoist_hosts[slot], 31));
            self.a.placeLabel(done);
            hoist.live = true;
        }
    }

    /// The hot path of a hoisted access: x0 = the operand (read) or the
    /// operand = x3 (write) through x29, and a branch to the ordinary probe,
    /// emitted out of line, when x29 is zero.
    fn emitHoistedAccess(self: *Compiler, insn: Insn, size: Size, index: u32, offset: HoistedOffset, is_write: bool) Error!void {
        return self.emitHoistedAccessAborting(insn, size, index, offset, is_write, false);
    }

    /// `last_effect`: nothing of the instruction remains after this access,
    /// so the out-of-line path checks `abort` itself and the hot path does
    /// not check it at all.
    fn emitHoistedAccessAborting(self: *Compiler, insn: Insn, size: Size, index: u32, offset: HoistedOffset, is_write: bool, last_effect: bool) Error!void {
        return self.emitHoistedAccessWith(insn, size, index, offset, is_write, last_effect, if (is_write) 3 else 0);
    }

    /// A hoisted access whose value is `data`: the register a load lands in
    /// or a store takes it from, which may be a guest register's cache.
    fn emitHoistedAccessWith(self: *Compiler, insn: Insn, size: Size, index: u32, offset: HoistedOffset, is_write: bool, last_effect: bool, data: a64.Reg) Error!void {
        const full = try self.a.createLabel();
        const resume_at = try self.a.createLabel();
        try self.a.branchIfZero(.x64, hoist_hosts[offset.slot], full);
        try self.emitHostAccess(is_write, size, data, offset, full);
        self.a.placeLabel(resume_at);
        const abort_exit: ?ColdAbortExit = if (last_effect) .{
            .completed = index + 1,
            .next_rip = insn.rip +% insn.len,
            .fused = self.fused,
        } else null;
        try self.cold_accesses.append(self.allocator, .{
            .full = full,
            .resume_at = resume_at,
            .insn = insn,
            .size = size,
            .index = index,
            .is_write = is_write,
            .nzcv_live = self.nzcv_live,
            .abort_exit = abort_exit,
            .dest = if (is_write) 0 else data,
            .value = if (is_write) data else 3,
        });
        self.touches_memory = true;
        self.hoisted_accesses += 1;
        // Otherwise the ordinary path out of line calls a helper that may
        // ask the block to stop, and the instruction's abort check has to
        // be emitted although that call is placed after the block body.
        if (!last_effect) self.abort_unchecked = true;
    }

    /// The fused writer at `index`, when the instructions right after it
    /// are a run of conditional readers - `jcc`, `setcc`, `cmovcc` - that
    /// read only flags the writer writes and each map onto one ARM
    /// condition. Xenia compiles a PowerPC compare to exactly this: a `cmp`
    /// and three `setcc` into the condition-register bytes, or a `test`
    /// and a branch. The writer must have register or immediate operands:
    /// a memory operand's helper may stop the block before anything has
    /// written the flags it owes.
    fn fusibleRun(self: *const Compiler, index: u32) ?Fused {
        if (index + 1 >= self.insns.len) return null;
        const writer = self.insns[index];
        if (writer.force_fallback or !isNative(writer.decoded) or writer.decoded.lock) return null;
        const d = writer.decoded;
        var size = d.size;
        const kind: FusedKind = if (binaryOpOf(d.op)) |op| blk: {
            const shape = binaryShapeOf(d.op);
            if (shape != .reg_reg and shape != .reg_imm) return null;
            break :blk switch (op) {
                .add => .add,
                .sub, .cmp => .sub,
                .bit_and, .tst, .bit_or, .bit_xor => .logic,
                .adc, .sbb => return null,
            };
        } else if (isIncDec(d.op)) |form| blk: {
            if (form.mem) return null;
            size = incDecSize(d.op);
            break :blk if (form.inc) .inc else .dec;
        } else return null;
        const writes = flagEffects(writer).writes;
        var remaining: u8 = 0;
        var saved = false;
        var position = index + 1;
        while (position < self.insns.len and remaining < 8) : (position += 1) {
            const reader = self.insns[position];
            if (reader.force_fallback or !isNative(reader.decoded)) break;
            switch (reader.decoded.op) {
                .jcc_rel8, .jcc_rel32, .setcc_reg8, .cmovcc_reg_reg => {},
                .setcc_mem8, .cmovcc_reg_mem => saved = true,
                else => break,
            }
            if (fusedCondition(kind, reader.decoded.cond) == null) break;
            if ((conditionReads(reader.decoded.cond) & ~writes) != 0) break;
            remaining += 1;
        }
        if (remaining == 0) return null;
        return .{ .kind = kind, .size = size, .writes = writes, .remaining = remaining, .saved = saved };
    }

    /// One reader of the fused run has been emitted. After the last, the
    /// writer's flags still live after it are written to `rflags`.
    fn emitFusedReaderDone(self: *Compiler, index: u32) Error!void {
        var fused = self.fused orelse return;
        fused.remaining -= 1;
        if (fused.remaining != 0) {
            self.fused = fused;
            return;
        }
        self.fused = null;
        self.nzcv_live = false;
        try self.emitFusedFlags(fused, fused.writes & self.flag_live[index]);
    }

    /// The writer has set NZCV: keep its operands where the run's exits
    /// can still find them, and hand the run to its readers.
    fn beginFusedRun(self: *Compiler, fused: Fused) Error!void {
        if (fused.saved) {
            try self.emitChecked(a64.strImm(.doubleword, t1, r_scratch, scratch_fused_a_offset));
            try self.emitChecked(a64.strImm(.doubleword, t2, r_scratch, scratch_fused_b_offset));
            try self.emitChecked(a64.strImm(.doubleword, t0, r_scratch, scratch_fused_r_offset));
        }
        self.fuse_pending = null;
        self.fused = fused;
        self.nzcv_live = true;
        self.fused_runs += 1;
    }

    /// The flags a jump to `target` must find in `rflags`: the block's own
    /// live-in at that instruction when `target` is one of its instructions,
    /// every flag otherwise.
    /// Find the conditional branches whose taken edge can jump to a later
    /// instruction of this block instead of leaving it.
    ///
    /// Xenia follows every float conversion it emits - each PowerPC lfs,
    /// frsp and stfs - with `cmp ; jbe` over a short NaN-payload fix-up,
    /// and the common case takes the branch. A trace follows the
    /// fall-through, so the common case left the block there: on Halo 3's
    /// main thread a block ran about 25 instructions on average, and every
    /// exit paid a cache write-back, a chain proof and an indirect branch,
    /// and the next block a cache load and a hoist probe.
    ///
    /// An edge qualifies when its target is a later instruction of the
    /// trace and no flag is live into it (`flag_live_in`, which counts
    /// every way out of the block as reading all six): the taken edge then
    /// owes no flag, so it jumps straight to the target. A branch to the
    /// next instruction (`je +0`) becomes no branch at all. Skipped
    /// instructions do not retire: `skip_reg` counts them for the exits.
    fn planInternalEdges(self: *Compiler, allowed: bool) Error!void {
        const count = self.insns.len;
        self.internal_target = try self.allocator.alloc(?u32, count);
        @memset(self.internal_target, null);
        self.internal_label = try self.allocator.alloc(?Label, count);
        @memset(self.internal_label, null);
        self.internal_hoist = try self.allocator.alloc([hoist_hosts.len]bool, count);
        @memset(self.internal_hoist, @splat(true));
        self.internal_abort = try self.allocator.alloc(bool, count);
        @memset(self.internal_abort, false);
        if (!allowed) return;
        for (self.insns) |insn| {
            // Their templates use ip0 as a temporary.
            if (insn.decoded.lock or insn.decoded.op == .cmpxchg16b_mem or insn.decoded.op == .cmpxchg8b_mem) return;
        }
        for (self.insns, 0..) |insn, index| {
            const d = insn.decoded;
            if (!isConditionalBranch(d.op) or insn.force_fallback or !isNative(d)) continue;
            if (index + 1 >= count) continue;
            // `internal_sources` names each source in one bit.
            if (index >= @bitSizeOf(u128)) continue;
            const target_rip = insn.rip +% d.len +% d.addr;
            var target = index + 1;
            while (target < count and self.insns[target].rip != target_rip) : (target += 1) {}
            if (target >= count) continue;
            if (target > index + 1) {
                if (self.flag_live_in[target] != 0) continue;
                self.uses_skip_counter = true;
                if (self.internal_label[target] == null) self.internal_label[target] = try self.a.createLabel();
            }
            self.internal_target[index] = @intCast(target);
        }
    }

    fn freeInternalEdges(self: *Compiler) void {
        self.allocator.free(self.internal_target);
        self.allocator.free(self.internal_label);
        self.allocator.free(self.internal_hoist);
        self.allocator.free(self.internal_abort);
        self.internal_target = &.{};
        self.internal_label = &.{};
        self.internal_hoist = &.{};
        self.internal_abort = &.{};
    }

    /// Where internal edges arrive: the fall-through and every jump to here
    /// must agree on the state the code after assumes. x29 holds the hoist
    /// only if it does on all of them, and an abort check any of them owes
    /// is still owed.
    fn placeInternalTarget(self: *Compiler, index: u32) void {
        if (index >= self.internal_label.len) return;
        const label = self.internal_label[index] orelse return;
        if (self.fused != null or self.nzcv_live) self.internal_conflict = true;
        self.a.placeLabel(label);
        self.last_xmm = null;
        self.zero_ymm = 0;
        self.zero_zmm = 0;
        for (&self.hoists, 0..) |*hoist, slot| hoist.live = hoist.live and self.internal_hoist[index][slot];
        self.abort_unchecked = self.abort_unchecked or self.internal_abort[index];
    }

    /// The conditional branch at `index`, whose taken edge stays in the
    /// block: to `target`, with `skip_reg` counting the instructions it
    /// jumps over.
    fn emitInternalBranch(self: *Compiler, index: u32, target: u32, d: DecodedInsn) Error!void {
        const skipped: u64 = target - index - 1;
        self.internal_edges += 1;
        self.internal_sources |= @as(u128, 1) << @intCast(index);
        if (skipped != 0) {
            for (self.hoists, 0..) |hoist, slot| self.internal_hoist[target][slot] = self.internal_hoist[target][slot] and hoist.live;
            self.internal_abort[target] = self.internal_abort[target] or self.abort_unchecked;
        }
        const label = if (skipped != 0) self.internal_label[target].? else null;
        if (self.fused) |fused| {
            // NZCV holds the writer's answer. The taken edge owes nothing
            // (no flag is live at the target); the fall-through pays what
            // the original template would have.
            const condition = fusedCondition(fused.kind, d.cond).?;
            if (label) |taken| {
                try self.emitChecked(a64.addImm(.x64, t5, skip_reg, skipped));
                try self.emit(a64.csel(.x64, skip_reg, t5, skip_reg, condition));
                try self.a.branchCond(condition, taken);
            }
            self.fused_branches += 1;
            if (fused.remaining == 1) {
                self.fused = null;
                self.nzcv_live = false;
                try self.emitFusedFlags(fused, fused.writes & self.flag_live_fall[index]);
            } else {
                var rest = fused;
                rest.remaining -= 1;
                self.fused = rest;
            }
            return;
        }
        // The flags are in `rflags` already, which is all either edge needs.
        const taken = label orelse return;
        try self.loadFlags(t3);
        try self.emitCondition(t4, t3, d.cond);
        try self.emitChecked(a64.cmpImm(.w32, t4, 0));
        try self.emitChecked(a64.addImm(.x64, t5, skip_reg, skipped));
        try self.emit(a64.csel(.x64, skip_reg, t5, skip_reg, .ne));
        try self.a.branchCond(.ne, taken);
    }

    fn liveInAt(self: *const Compiler, target: u64) u8 {
        for (self.insns, 0..) |insn, position| {
            if (insn.rip == target) return self.flag_live_in[position];
        }
        return F_ALL;
    }

    /// The fused writer's flags that `owed` names, into `rflags`, from its
    /// operands in t1 and t2 and its result in t0.
    fn emitFusedFlags(self: *Compiler, fused: Fused, owed: u8) Error!void {
        if (owed == 0) return;
        if (fused.saved) {
            try self.emitChecked(a64.ldrImm(.doubleword, t1, r_scratch, scratch_fused_a_offset));
            try self.emitChecked(a64.ldrImm(.doubleword, t2, r_scratch, scratch_fused_b_offset));
            try self.emitChecked(a64.ldrImm(.doubleword, t0, r_scratch, scratch_fused_r_offset));
        } else {
            // Operands read in place: the flag derivation wants them in t1
            // and t2, zero-extended at the writer's width.
            const width = arm(fused.size);
            if (fused.a_reg != t1) try self.emit(a64.mov(width, t1, fused.a_reg));
            if (fused.b_imm) |imm| {
                try self.a.loadConstant(t2, imm);
            } else if (fused.b_reg != t2) {
                try self.emit(a64.mov(width, t2, fused.b_reg));
            }
        }
        switch (fused.kind) {
            .add => try self.emitArithmeticFlagsLive(.add, fused.size, t1, t2, t0, false, owed),
            .sub => try self.emitArithmeticFlagsLive(.sub, fused.size, t1, t2, t0, false, owed),
            .logic => try self.emitArithmeticFlagsLive(.logic, fused.size, t1, t2, t0, false, owed),
            .inc => try self.emitIncDecFlags(fused.size, true, owed),
            .dec => try self.emitIncDecFlags(fused.size, false, owed),
        }
    }

    /// Every fused branch's taken edge: the flags it owes, then its exit.
    fn emitFusedExits(self: *Compiler) Error!void {
        for (self.fused_exits.items) |exit| {
            self.a.placeLabel(exit.label);
            try self.emitFusedFlags(exit.fused, exit.owed);
            try self.a.branch(exit.stub);
        }
    }

    /// Every hoisted access's ordinary path: the effective address, the
    /// TLB probe and the helper, then back to where the access resumes.
    fn emitColdAccesses(self: *Compiler) Error!void {
        for (self.cold_accesses.items) |cold| {
            self.a.placeLabel(cold.full);
            self.nzcv_live = cold.nzcv_live;
            defer self.nzcv_live = false;
            if (cold.vector) |v| {
                if (cold.is_write)
                    try self.emitStoreVecProbed(cold.insn, cold.index, v, cold.vector_offset)
                else
                    try self.emitLoadVecProbed(cold.insn, cold.index, v, cold.vector_offset);
            } else {
                if (cold.is_write and cold.value != 3) try self.emit(a64.mov(.x64, 3, cold.value));
                try self.emitEffectiveAddress(1, cold.insn);
                if (cold.is_write) try self.emitWrite(cold.size, cold.index) else try self.emitRead(cold.size, cold.index);
                if (!cold.is_write and cold.dest != 0) try self.emit(a64.mov(.x64, cold.dest, 0));
            }
            if (cold.abort_exit) |exit| {
                const stub = try self.exitStub(exit.completed, exit.next_rip);
                const target = if (exit.fused) |fused| blk: {
                    const path = try self.a.createLabel();
                    try self.fused_exits.append(self.allocator, .{ .label = path, .fused = fused, .owed = fused.writes, .stub = stub });
                    break :blk path;
                } else stub;
                try self.emitChecked(a64.ldrImm(.byte, t0, r_scratch, scratch_abort_offset));
                try self.a.branchIfNonZero(.w32, t0, target);
            }
            try self.a.branch(cold.resume_at);
        }
    }

    /// A 128-bit access through the hoisted pointer, with the ordinary one
    /// out of line for when x29 is zero.
    fn emitHoistedVector(self: *Compiler, insn: Insn, index: u32, v: a64.Reg, byte_offset: u32, offset: HoistedOffset, is_write: bool) Error!void {
        const full = try self.a.createLabel();
        const resume_at = try self.a.createLabel();
        try self.a.branchIfZero(.x64, hoist_hosts[offset.slot], full);
        try self.emitHostOffset(t5, hoist_hosts[offset.slot], offset.offset);
        if (!self.hoistProvesAlignment(offset, 8)) {
            try self.emitOrderedVectorAccess(v, t5, is_write);
        } else if (is_write) {
            try self.emitOrderedVectorStore(v, t5);
        } else {
            try self.emitOrderedVectorLoad(v, t5);
        }
        self.a.placeLabel(resume_at);
        try self.cold_accesses.append(self.allocator, .{ .full = full, .resume_at = resume_at, .insn = insn, .size = .bits64, .index = index, .is_write = is_write, .vector = v, .vector_offset = byte_offset, .nzcv_live = self.nzcv_live });
        self.touches_memory = true;
        self.hoisted_accesses += 1;
        self.abort_unchecked = true;
    }

    /// Ordered access through the selected span, with an alignment guard
    /// only when the admission did not already prove it.
    fn emitHostAccess(self: *Compiler, is_write: bool, size: Size, data: a64.Reg, selected: HoistedOffset, slow: Label) Error!void {
        const offset = selected.offset;
        const host = hoist_hosts[selected.slot];
        const aligned = self.hoistProvesAlignment(selected, bits(size) / 8);
        if (aligned and offset != 0 and offset <= 255) {
            const ms = memSize(size);
            const offset_i: i64 = @intCast(offset);
            try self.emitChecked(if (is_write) a64.stlur(ms, data, host, offset_i) else a64.ldapur(ms, data, host, offset_i));
            return;
        }
        if (offset == 0) {
            if (!aligned) try self.emitHostAlignmentGuard(host, bits(size) / 8, slow);
            try self.emitOrderedScalar(is_write, size, data, host);
            return;
        }
        try self.emitHostOffset(t5, host, offset);
        if (!aligned) try self.emitHostAlignmentGuard(t5, bits(size) / 8, slow);
        try self.emitOrderedScalar(is_write, size, data, t5);
    }

    fn hoistProvesAlignment(self: *const Compiler, selected: HoistedOffset, bytes: u64) bool {
        if (!self.hoists[selected.slot].aligned or bytes > 8) return false;
        return bytes <= 1 or selected.offset % bytes == 0;
    }

    /// A load straight into `dest` (a guest register's cache): no trip
    /// through x0 and back.
    fn emitLoadOperandInto(self: *Compiler, insn: Insn, size: Size, index: u32, dest: a64.Reg) Error!void {
        if (self.hoistedOffset(insn, size)) |offset| {
            try self.emitHoistedAccessWith(insn, size, index, offset, false, false, dest);
            return;
        }
        try self.emitEffectiveAddress(1, insn);
        try self.emitReadInto(size, index, dest);
    }

    /// A store of `value`, the instruction's last effect when `last_effect`:
    /// through the hoist straight from `value`, otherwise through x3, the
    /// write helper's argument.
    fn emitStoreValueLast(self: *Compiler, insn: Insn, size: Size, index: u32, value: a64.Reg, last_effect: bool) Error!void {
        if (self.hoistedOffset(insn, size)) |offset| {
            if (self.hoists[offset.slot].write) {
                try self.emitHoistedAccessWith(insn, size, index, offset, true, last_effect, value);
                return;
            }
        }
        if (value != 3) try self.emit(a64.mov(.x64, 3, value));
        try self.emitEffectiveAddress(1, insn);
        try self.emitWrite(size, index);
    }

    /// Move the MXCSR value in w0 onto the host FPCR, as
    /// `host_fp_control.applyGuestMxcsr` does for the interpreter: FZ is
    /// FTZ | DAZ, RMode is RC with its two bits swapped. The translated
    /// arithmetic that follows obeys FPCR, not the stored field.
    fn emitMxcsrToFpcr(self: *Compiler) Error!void {
        // Write FPCR only when FZ or RMode change. `msr fpcr` synchronises:
        // it waits for the stores in flight even when the value is the one
        // already there. The comparison uses no flags, so it is safe inside
        // anything that keeps NZCV live.
        const unchanged = try self.a.createLabel();
        try self.emit(a64.mrsFpcr(t1));
        try self.emit(a64.mov(.x64, t3, t1));
        try self.emit(a64.ubfx(.w32, t0, 0, 15, 1));
        try self.emit(a64.ubfx(.w32, t2, 0, 6, 1));
        try self.emit(a64.orrReg(.w32, t0, t0, t2));
        try self.emit(a64.bfi(.x64, t1, t0, 24, 1));
        try self.emit(a64.ubfx(.w32, t0, 0, 14, 1));
        try self.emit(a64.bfi(.x64, t1, t0, 22, 1));
        try self.emit(a64.ubfx(.w32, t0, 0, 13, 1));
        try self.emit(a64.bfi(.x64, t1, t0, 23, 1));
        try self.emit(a64.eorReg(.x64, t3, t3, t1));
        try self.a.branchIfZero(.x64, t3, unchanged);
        try self.emit(a64.msrFpcr(t1));
        try self.emitChecked(a64.ldrImm(.doubleword, t3, r_scratch, scratch_fpcr_writes_offset));
        try self.emitChecked(a64.addImm(.x64, t3, t3, 1));
        try self.emitChecked(a64.strImm(.doubleword, t3, r_scratch, scratch_fpcr_writes_offset));
        self.a.placeLabel(unchanged);
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
        try self.emitStoreX3(insn, size, index);
    }

    /// Store x3 to the instruction's memory operand at `size`. A store may
    /// use the hoisted pointer only when it came from the write TLB: that is
    /// what keeps code pages (self-modifying code) and watched pages
    /// (Xenia's GPU write watch) on the write helper. Every plain store
    /// form comes here, so a block that hoisted `rsi` for its context
    /// stores through it too; `mov [rsi+d], reg` and `setcc [rsi+d]` used to
    /// probe the write TLB again each time.
    fn emitStoreX3(self: *Compiler, insn: Insn, size: Size, index: u32) Error!void {
        return self.emitStoreX3Last(insn, size, index, false);
    }

    /// `emitStoreX3` for a store that is its instruction's last effect.
    fn emitStoreX3Last(self: *Compiler, insn: Insn, size: Size, index: u32, last_effect: bool) Error!void {
        if (self.hoistedOffset(insn, size)) |offset| {
            if (self.hoists[offset.slot].write) {
                try self.emitHoistedAccessAborting(insn, size, index, offset, true, last_effect);
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
        // Only these templates load all their inputs before producing v0,
        // and keep it through their final upper clear. Every other template
        // discards the forwarding fact before emitting anything.
        self.forward_xmm = !insn.force_fallback and isVectorNative(d) and d.is_reg_form and !d.vector_256 and
            (packedIntegerForm(d.op) != null or packedFloatForm(d.op) != null or bitwiseForm(d.op) != null or unpackForm(d.op) != null or (d.op == .vmovdqu_xmm_xmm or d.op == .vmovdqa_xmm_xmm or d.op == .vmovups_xmm_xmm or d.op == .vmovaps_xmm_xmm or d.op == .vmovupd_xmm_xmm or d.op == .vmovapd_xmm_xmm));
        if (!self.forward_xmm) self.last_xmm = null;
        if (isConditionalBranch(d.op)) {
            self.zero_ymm = 0;
            self.zero_zmm = 0;
        }
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
        self.fuse_pending = if (self.fused == null) self.fusibleRun(index) else null;
        if (isX87RawTransfer(d)) {
            self.touches_x87 = true;
            self.touches_memory = self.touches_memory or d.op == .fld_mem80 or d.op == .fstp_mem80;
            try self.emitX87RawTransferCall(index);
            return .native;
        }
        if (d.op == .x87_memory) {
            self.touches_x87 = true;
            self.touches_memory = true;
            try self.emitX87MemoryCall(index);
            return .native;
        }
        if (try self.emitVectorInsn(insn, index)) return .native;
        // A lock-prefixed arithmetic/logic memory update cannot use the
        // ordinary load/compute/store template: that would tear under a
        // concurrent guest execution context. Its CAS loop is the native
        // implementation of the whole read-modify-write.
        if (d.lock) {
            if (atomicForm(d.op)) |form| {
                try self.emitAtomic(insn, index, form);
                return .native;
            }
        }
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
                if (self.cachedWhole(d.dst_reg, d.dst_high8, size)) |dst| {
                    // Straight into the cache register: a 32-bit move
                    // zero-extends on both machines.
                    if (self.cachedWhole(d.src_reg, d.src_high8, size)) |src| {
                        try self.emit(a64.mov(arm(size), dst, src));
                    } else {
                        try self.loadReg(dst, d.src_reg, d.src_high8, size);
                    }
                    self.noteDirectWrite(d.dst_reg);
                } else {
                    try self.loadReg(t1, d.src_reg, d.src_high8, size);
                    try self.storeReg(d.dst_reg, d.dst_high8, size, t1);
                }
            },
            .mov_reg_imm => {
                if (self.cachedWhole(d.dst_reg, d.dst_high8, d.size)) |dst| {
                    try self.a.loadConstant(dst, d.imm & maskFor(d.size));
                    self.noteDirectWrite(d.dst_reg);
                } else {
                    try self.a.loadConstant(t1, d.imm & maskFor(d.size));
                    try self.storeReg(d.dst_reg, d.dst_high8, d.size, t1);
                }
            },
            .mov_reg8_mem8, .mov_reg16_mem16, .mov_reg32_mem32, .mov_reg64_mem64 => {
                const size: Size = switch (d.op) {
                    .mov_reg8_mem8 => .bits8,
                    .mov_reg16_mem16 => .bits16,
                    .mov_reg32_mem32 => .bits32,
                    else => .bits64,
                };
                if (self.cachedWhole(d.dst_reg, d.dst_high8, size)) |host| {
                    // Straight into the cache register: a 32-bit load
                    // zero-extends on both machines.
                    try self.emitLoadOperandInto(insn, size, index, host);
                    self.noteDirectWrite(d.dst_reg);
                } else {
                    try self.emitLoadOperand(insn, size, index);
                    try self.storeRegExtended(d.dst_reg, d.dst_high8, size, 0);
                }
                try self.emitAbortCheck(index);
            },
            .mov_mem8_reg8, .mov_mem16_reg16, .mov_mem32_reg32, .mov_mem64_reg64 => {
                const size: Size = switch (d.op) {
                    .mov_mem8_reg8 => .bits8,
                    .mov_mem16_reg16 => .bits16,
                    .mov_mem32_reg32 => .bits32,
                    else => .bits64,
                };
                if (!d.src_high8 and self.cachedRegister(d.src_reg) != null) {
                    // The store's low bytes straight from the cache register.
                    try self.emitStoreValueLast(insn, size, index, self.cachedRegister(d.src_reg).?, true);
                } else {
                    try self.loadReg(3, d.src_reg, d.src_high8, size);
                    try self.emitStoreX3Last(insn, size, index, true);
                }
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
                try self.emitStoreX3Last(insn, size, index, true);
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
                try self.emitMxcsrToFpcr();
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
                try self.emitStoreX3Last(insn, d.size, index, true);
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
                // Straight into a cached destination, unless the address
                // still has to read that register as its index after the
                // base has been written there. Xenia forms every guest
                // address with a displacement this way, `lea edx, [r13d+0x60]`.
                if (self.cachedWhole(d.dst_reg, false, d.size)) |host| {
                    const index_host: ?a64.Reg = if (d.sib_has_index) self.cachedRegister(d.sib_index_reg) else null;
                    if (index_host == null or index_host.? != host) {
                        try self.emitEffectiveAddress(host, insn);
                        // A 32-bit address-size operand ends its address
                        // already truncated, unless a segment base follows.
                        const truncated = d.has_0x67 and insn.segment != .fs and insn.segment != .gs;
                        if (d.size == .bits32 and !truncated) try self.emit(a64.mov(.w32, host, host));
                        self.noteDirectWrite(d.dst_reg);
                        return .native;
                    }
                }
                try self.emitEffectiveAddress(t1, insn);
                try self.storeReg(d.dst_reg, false, d.size, t1);
            },
            .xchg_reg8_reg8, .xchg_reg32_reg32, .xchg_reg64_reg64 => {
                try self.loadReg(t1, d.dst_reg, d.dst_high8, d.size);
                try self.loadReg(t2, d.src_reg, d.src_high8, d.size);
                try self.storeReg(d.dst_reg, d.dst_high8, d.size, t2);
                try self.storeReg(d.src_reg, d.src_high8, d.size, t1);
            },
            .xchg_accum_reg => {
                try self.loadReg(t1, .al_ax_eax_rax, false, d.size);
                try self.loadReg(t2, d.src_reg, false, d.size);
                try self.storeReg(.al_ax_eax_rax, false, d.size, t2);
                try self.storeReg(d.src_reg, false, d.size, t1);
            },
            .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
                // setFlagsSub(0, a, r): a subtraction with a zero left side.
                // A byte operand may be AH..BH (`dst_high8`).
                try self.emit(a64.mov(.x64, t1, a64.xzr));
                try self.loadReg(t2, d.dst_reg, d.dst_high8, d.size);
                try self.emitBinaryCompute(.sub, d.size);
                try self.storeReg(d.dst_reg, d.dst_high8, d.size, t0);
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
                try self.loadReg(t1, d.dst_reg, d.dst_high8, d.size);
                try self.emit(a64.mvn(arm(d.size), t1, t1));
                try self.storeReg(d.dst_reg, d.dst_high8, d.size, t1);
            },
            .not_mem8, .not_mem16, .not_mem32, .not_mem64 => {
                try self.emitLoadOperand(insn, d.size, index);
                try self.emit(a64.mvn(arm(d.size), t0, 0));
                if (d.size == .bits8 or d.size == .bits16) try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(d.size)).?);
                try self.emitStoreOperand(insn, d.size, index);
                try self.emitAbortCheck(index);
            },
            .shl_reg_imm, .shr_reg_imm, .sar_reg_imm => try self.emitShift(d),
            .shl_reg_cl, .shr_reg_cl, .sar_reg_cl => try self.emitShiftCl(insn, index),
            .shl_mem_cl, .shr_mem_cl, .sar_mem_cl => try self.emitShiftCl(insn, index),
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
            .mul_reg8 => {
                // The byte form multiplies AL by the explicit source and
                // writes the full unsigned product to AX. Only CF and OF are
                // defined, both set exactly when the high byte is nonzero.
                try self.loadReg(t1, .al_ax_eax_rax, false, .bits8);
                try self.loadReg(t2, d.src_reg, d.src_high8, .bits8);
                try self.emit(a64.umull(t0, t1, t2));
                try self.storeReg(.al_ax_eax_rax, false, .bits16, t0);
                if (self.emit_flags) {
                    try self.emit(a64.lsrImm(.x64, t4, t0, 8));
                    try self.emitChecked(a64.cmpImm(.x64, t4, 0));
                    try self.emit(a64.cset(.w32, t4, .ne));
                    try self.loadFlags(t3);
                    try self.clearFlagBits(t3, RFL_CF | RFL_OF);
                    try self.orFlagBit(t3, t4, 0);
                    try self.orFlagBit(t3, t4, 11);
                    try self.storeFlags(t3);
                }
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
            .xchg_mem8_reg8, .xchg_mem32_reg32, .xchg_mem64_reg64 => try self.emitAtomic(insn, index, .exchange),
            .cmpxchg_mem8_reg8, .cmpxchg_mem16_reg16, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64 => if (d.lock)
                try self.emitAtomic(insn, index, .compare_exchange)
            else
                try self.emitNonAtomicCompareExchange(insn, index),
            .xadd_mem8_reg8, .xadd_mem32_reg32, .xadd_mem64_reg64 => if (d.lock)
                try self.emitAtomic(insn, index, .exchange_add)
            else
                try self.emitNonAtomicExchangeAdd(insn, index),
            .cmpxchg8b_mem => try self.emitAtomic(insn, index, .compare_exchange8b),
            .cmpxchg16b_mem => try self.emitAtomic(insn, index, .compare_exchange16b),
            .bt_mem_imm => try self.emitBitTestMemory(insn, index, .probe),
            .bts_mem_imm => try self.emitBitTestMemory(insn, index, .set),
            .btr_mem_imm => try self.emitBitTestMemory(insn, index, .reset),
            .btc_mem_imm => try self.emitBitTestMemory(insn, index, .complement),
            .bt_mem_reg => try self.emitBitTestMemoryRegister(insn, index, .probe),
            .bts_mem_reg => try self.emitBitTestMemoryRegister(insn, index, .set),
            .btr_mem_reg => try self.emitBitTestMemoryRegister(insn, index, .reset),
            .btc_mem_reg => try self.emitBitTestMemoryRegister(insn, index, .complement),
            .bsf_reg_reg, .bsr_reg_reg => try self.emitBitScan(d),
            .tzcnt_reg_reg, .lzcnt_reg_reg => try self.emitCountZeros(d),
            .popcnt_reg_reg => try self.emitPopulationCount(d),
            .cmovcc_reg_reg => {
                if (self.fused) |fused| {
                    try self.loadReg(t3, d.dst_reg, false, d.size);
                    try self.loadReg(t4, d.src_reg, false, d.size);
                    try self.emit(a64.csel(arm(d.size), t3, t4, t3, fusedCondition(fused.kind, d.cond).?));
                    try self.storeReg(d.dst_reg, false, d.size, t3);
                    try self.emitFusedReaderDone(index);
                    return .native;
                }
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
                if (self.fused) |fused| {
                    try self.loadReg(t3, d.dst_reg, false, d.size);
                    try self.emit(a64.csel(arm(d.size), t3, 0, t3, fusedCondition(fused.kind, d.cond).?));
                    try self.storeReg(d.dst_reg, false, d.size, t3);
                    try self.emitAbortCheck(index);
                    try self.emitFusedReaderDone(index);
                    return .native;
                }
                try self.loadFlags(t3);
                try self.emitCondition(t4, t3, d.cond);
                try self.loadReg(t1, d.dst_reg, false, d.size);
                try self.emitChecked(a64.cmpImm(.w32, t4, 0));
                try self.emit(a64.csel(arm(d.size), t1, 0, t1, .ne));
                try self.storeReg(d.dst_reg, false, d.size, t1);
                try self.emitAbortCheck(index);
            },
            .setcc_reg8 => {
                if (self.fused) |fused| {
                    try self.emit(a64.cset(.w32, t4, fusedCondition(fused.kind, d.cond).?));
                    try self.storeReg(d.dst_reg, d.dst_high8, .bits8, t4);
                    try self.emitFusedReaderDone(index);
                    return .native;
                }
                try self.loadFlags(t3);
                try self.emitCondition(t4, t3, d.cond);
                try self.storeReg(d.dst_reg, d.dst_high8, .bits8, t4);
            },
            .setcc_mem8 => {
                if (self.fused) |fused| {
                    try self.emit(a64.cset(.w32, 3, fusedCondition(fused.kind, d.cond).?));
                    try self.emitStoreX3Last(insn, .bits8, index, true);
                    try self.emitAbortCheck(index);
                    try self.emitFusedReaderDone(index);
                    return .native;
                }
                // The condition goes straight into the store helper's value
                // register, which `emitEffectiveAddress` does not touch.
                try self.loadFlags(t3);
                try self.emitCondition(3, t3, d.cond);
                try self.emitStoreX3Last(insn, .bits8, index, true);
                try self.emitAbortCheck(index);
            },
            .mfence => try self.emit(a64.dmbIsh()),
            .lfence => try self.emit(a64.dmbIshLd()),
            .sfence => try self.emit(a64.dmbIshSt()),
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
                if (self.cachedWhole(d.dst_reg, false, d.size)) |dst| {
                    try self.emit(a64.rev(arm(d.size), dst, dst));
                    self.noteDirectWrite(d.dst_reg);
                } else {
                    try self.loadReg(t1, d.dst_reg, false, d.size);
                    try self.emit(a64.rev(arm(d.size), t1, t1));
                    try self.storeReg(d.dst_reg, false, d.size, t1);
                }
            },
            .jcc_rel8, .jcc_rel32 => {
                if (index < self.internal_target.len) {
                    if (self.internal_target[index]) |target_index| {
                        try self.emitInternalBranch(index, target_index, d);
                        return .native;
                    }
                }
                // The decoder keeps the displacement in `addr` for jcc.
                const next = insn.rip +% d.len;
                const target = next +% d.addr;
                if (self.fused) |fused| {
                    // NZCV holds the writer's answer: branch on it, and pay
                    // for the x86 flags only on the edges that still owe
                    // them - on the taken edge, everything the code there
                    // may read; on the fall-through, once the run ends,
                    // only what is read again before it is overwritten.
                    const taken_path = try self.a.createLabel();
                    try self.a.branchCond(fusedCondition(fused.kind, d.cond).?, taken_path);
                    try self.fused_exits.append(self.allocator, .{
                        .label = taken_path,
                        .fused = fused,
                        // A jump back into this block - a loop's back-edge
                        // to its head - owes only what the code there reads.
                        .owed = if (self.exact_exit_flags) fused.writes else fused.writes & self.liveInAt(target),
                        .stub = try self.exitStub(index + 1, target),
                    });
                    self.fused_branches += 1;
                    if (fused.remaining == 1) {
                        self.fused = null;
                        self.nzcv_live = false;
                        try self.emitFusedFlags(fused, fused.writes & self.flag_live_fall[index]);
                    } else {
                        var rest = fused;
                        rest.remaining -= 1;
                        self.fused = rest;
                    }
                    if (index + 1 == self.insns.len) {
                        const not_taken = try self.exitStub(index + 1, next);
                        try self.a.branch(not_taken);
                    }
                    return .native;
                }
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
                try self.emitChecked(a64.ldrImm(.byte, t0, r_scratch, scratch_call_guard_offset));
                try self.a.branchIfNonZero(.w32, t0, slow);
                if (insn.milestone_gate) |milestone| {
                    // Until the glue says this milestone has seen enough, its
                    // entry is the interpreter's to record. After that only
                    // the count is kept, here.
                    try self.emitStateScalar(.byte, t0, self.layout.milestone_saturated_offset + milestone);
                    try self.a.branchIfZero(.w32, t0, slow);
                    try self.emitStateAddress(t1, self.layout.milestone_hits_offset + @as(u32, milestone) * 8);
                    try self.emitChecked(a64.ldrImm(.doubleword, t0, t1, 0));
                    try self.emitChecked(a64.addImm(.x64, t0, t0, 1));
                    try self.emitChecked(a64.strImm(.doubleword, t0, t1, 0));
                }
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
            .jmp_reg64, .jmp_mem64, .call_reg64, .call_mem64 => {
                const next_rip = insn.rip +% d.len;
                const is_call = d.op == .call_reg64 or d.op == .call_mem64;
                const from_memory = d.op == .call_mem64 or d.op == .jmp_mem64;
                const slow = try self.a.createLabel();
                const import: ?Label = if (from_memory) try self.a.createLabel() else null;
                try self.emitChecked(a64.ldrImm(.byte, t0, r_scratch, if (is_call) scratch_call_guard_offset else scratch_jmp_guard_offset));
                try self.a.branchIfNonZero(.w32, t0, slow);
                // x0 = the target. A memory operand inside the image may be
                // an import slot, which a lock-free import lane may answer
                // and the interpreter's shim owns otherwise.
                if (from_memory) {
                    try self.emitEffectiveAddress(1, insn);
                    try self.emitImportSlotCheck(1, import.?);
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
                try self.emit(a64.mov(.x64, r_exit_rip, 0));
                const taken = try self.exitStubWithRipInRegister(index + 1);
                try self.a.branch(taken);
                if (import) |slot_path| {
                    // x1 still holds the slot's address.
                    self.a.placeLabel(slot_path);
                    try self.emitImportTransfer(index, if (is_call) next_rip else 0, slow);
                    const imported = try self.exitStub(index + 1, null);
                    try self.a.branch(imported);
                }
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
                try self.emitChecked(a64.ldrImm(.byte, t0, r_scratch, scratch_ret_guard_offset));
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
                const pop_bytes = d.imm & 0xFFFF;
                if (pop_bytes != 0) {
                    try self.a.loadConstant(t5, pop_bytes);
                    try self.emit(a64.add(.x64, t1, t1, t5));
                }
                try self.storeReg(.ah_sp_esp_rsp, false, .bits64, t1);
                try self.emit(a64.mov(.x64, r_exit_rip, 0));
                const taken = try self.exitStubWithRipInRegister(index + 1);
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
        const shape = binaryShapeOf(d.op);
        if (!self.emit_flags and (shape == .reg_reg or shape == .reg_imm)) {
            // A register `cmp` or `test` whose flags nothing reads computes
            // nothing anyone can observe.
            if (!writes) return;
            if (try self.emitGroup1Direct(op, d, shape)) return;
        }
        if (!writes and (shape == .reg_reg or shape == .reg_imm)) {
            if (try self.emitFusedCompareDirect(op, d, index, shape)) return;
        }
        switch (shape) {
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

    /// A `cmp` or `test` that starts a fused run, with its operands read
    /// where they are: a cached guest register in place, an immediate in
    /// the instruction. Xenia guards every guest memory access with
    /// `cmp r32, esi ; jae` and compiles every PowerPC compare-and-branch
    /// to a `cmp` or `test` and a `jcc`; each copied both operands into t1
    /// and t2 for the flag derivation that only an exit owing flags runs.
    /// That copy now happens there (`emitFusedFlags`). Not when a reader
    /// of the run writes one of the operands' registers, so a later exit
    /// would see the new value, nor when the run saves its operands for a
    /// memory reader. Returns false, having emitted nothing, otherwise.
    fn emitFusedCompareDirect(self: *Compiler, op: BinaryOp, d: DecodedInsn, index: u32, shape: BinaryShape) Error!bool {
        var fused = self.fuse_pending orelse return false;
        if (fused.saved) return false;
        const size = d.size;
        if (size != .bits32 and size != .bits64) return false;
        const width = arm(size);
        const a_cached = self.cachedWhole(d.dst_reg, d.dst_high8, size);
        const b_cached: ?a64.Reg = if (shape == .reg_reg) self.cachedWhole(d.src_reg, d.src_high8, size) else null;
        // Nothing to save: both operands would be loaded into t1 and t2.
        if (shape == .reg_reg and a_cached == null and b_cached == null) return false;
        if (a_cached != null and self.fusedRunWrites(index, fused.remaining, d.dst_reg)) return false;
        if (b_cached != null and self.fusedRunWrites(index, fused.remaining, d.src_reg)) return false;
        const a: a64.Reg = a_cached orelse t1;
        var word: u32 = undefined;
        switch (shape) {
            .reg_reg => {
                const b = b_cached orelse t2;
                word = if (op == .cmp) a64.subs(width, t0, a, b) else a64.logicalShifted(width, .ands, t0, a, b, 0);
                fused.b_reg = b;
            },
            .reg_imm => {
                const imm = immediateValue(d) & maskFor(size);
                word = (if (op == .cmp) a64.subsImm(width, t0, a, imm) else a64.logicalImmediate(width, .ands, t0, a, imm)) orelse return false;
                fused.b_imm = imm;
            },
            else => return false,
        }
        if (a_cached == null) try self.loadReg(t1, d.dst_reg, d.dst_high8, size);
        if (shape == .reg_reg and b_cached == null) try self.loadReg(t2, d.src_reg, d.src_high8, size);
        try self.emit(word);
        fused.a_reg = a;
        try self.beginFusedRun(fused);
        return true;
    }

    /// Whether a reader of the fused run after the writer at `index` writes
    /// guest register `id` (`setcc` into its byte, `cmovcc` into it).
    fn fusedRunWrites(self: *const Compiler, index: u32, remaining: u8, id: RegId) bool {
        var position = index + 1;
        var left = remaining;
        while (left > 0 and position < self.insns.len) : ({
            position += 1;
            left -= 1;
        }) {
            const reader = self.insns[position].decoded;
            switch (reader.op) {
                .setcc_reg8, .cmovcc_reg_reg, .cmovcc_reg_mem => if (reader.dst_reg == id) return true,
                else => {},
            }
        }
        return false;
    }

    /// The host register caching guest `id`, for a whole 32- or 64-bit
    /// access; null when it is not cached or the access merges.
    fn cachedWhole(self: *const Compiler, id: RegId, high8: bool, size: Size) ?a64.Reg {
        if (high8 or (size != .bits32 and size != .bits64)) return null;
        const slot = self.cache_slot[@intFromEnum(id)] orelse return null;
        return cache_host_regs[slot];
    }

    /// The register-file effects of writing guest `id` directly in its
    /// cache register, which `storeReg` would otherwise have done.
    fn noteDirectWrite(self: *Compiler, id: RegId) void {
        self.use_counts[@intFromEnum(id)] +|= 1;
        self.written |= @as(u16, 1) << @intFromEnum(id);
        for (&self.hoists) |*hoist| {
            if (hoist.base == id) hoist.live = false;
        }
    }

    /// `dst op= src` straight into the cache register when no flag is
    /// wanted and the destination is a cached 32- or 64-bit register: one
    /// instruction where the general template loads both operands into
    /// temporaries, computes, zero-extends and moves the result back - five
    /// for Xenia's `add eax, 1`. A 32-bit ARM operation zero-extends exactly
    /// as the x86 one does. False when the form does not apply.
    fn emitGroup1Direct(self: *Compiler, op: BinaryOp, d: DecodedInsn, shape: BinaryShape) Error!bool {
        if (op == .adc or op == .sbb or op == .cmp or op == .tst) return false;
        const size = d.size;
        const dst = self.cachedWhole(d.dst_reg, d.dst_high8, size) orelse return false;
        const width = arm(size);
        if (shape == .reg_reg) {
            const src = self.cachedWhole(d.src_reg, d.src_high8, size) orelse blk: {
                try self.loadReg(t2, d.src_reg, d.src_high8, size);
                break :blk t2;
            };
            try self.emit(switch (op) {
                .add => a64.add(width, dst, dst, src),
                .sub => a64.sub(width, dst, dst, src),
                .bit_and => a64.andReg(width, dst, dst, src),
                .bit_or => a64.orrReg(width, dst, dst, src),
                .bit_xor => a64.eorReg(width, dst, dst, src),
                else => unreachable,
            });
        } else {
            const mask = maskFor(size);
            const imm = immediateValue(d) & mask;
            switch (op) {
                .add, .sub => {
                    const negated = (0 -% imm) & mask;
                    const is_add = op == .add;
                    if (imm <= 4095) {
                        try self.emitChecked(if (is_add) a64.addImm(width, dst, dst, imm) else a64.subImm(width, dst, dst, imm));
                    } else if (negated <= 4095) {
                        try self.emitChecked(if (is_add) a64.subImm(width, dst, dst, negated) else a64.addImm(width, dst, dst, negated));
                    } else {
                        try self.a.loadConstant(t2, imm);
                        try self.emit(if (is_add) a64.add(width, dst, dst, t2) else a64.sub(width, dst, dst, t2));
                    }
                },
                .bit_and, .bit_or, .bit_xor => {
                    const logical: a64.LogicalOp = switch (op) {
                        .bit_and => .andop,
                        .bit_or => .orr,
                        else => .eor,
                    };
                    if (a64.logicalImmediate(width, logical, dst, dst, imm)) |word| {
                        try self.emit(word);
                    } else {
                        try self.a.loadConstant(t2, imm);
                        try self.emit(a64.logicalShifted(width, logical, dst, dst, t2, 0));
                    }
                },
                else => unreachable,
            }
        }
        self.noteDirectWrite(d.dst_reg);
        return true;
    }

    /// t0 = t1 op t2, masked to `size`, with the flags (when wanted). Both
    /// inputs hold values masked to `size`.
    fn emitBinaryCompute(self: *Compiler, op: BinaryOp, size: Size) Error!void {
        const width = arm(size);
        if (self.fuse_pending) |fused| {
            // One flag-setting instruction; the readers after it test NZCV
            // and the x86 flags are written only where they are still owed.
            if (size == .bits8 or size == .bits16) {
                // The x86 result at its width, then NZCV from the operands
                // shifted to the top of a 32-bit register, which is the
                // narrow operation's carry, overflow, sign and zero.
                const shift: u6 = @intCast(32 - bits(size));
                switch (op) {
                    .add => try self.emit(a64.add(.w32, t0, t1, t2)),
                    .sub, .cmp => try self.emit(a64.sub(.w32, t0, t1, t2)),
                    .bit_and, .tst => try self.emit(a64.andReg(.w32, t0, t1, t2)),
                    .bit_or => try self.emit(a64.orrReg(.w32, t0, t1, t2)),
                    .bit_xor => try self.emit(a64.eorReg(.w32, t0, t1, t2)),
                    .adc, .sbb => unreachable,
                }
                try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(size)).?);
                switch (op) {
                    .add, .sub, .cmp => {
                        try self.emit(a64.lslImm(.w32, t3, t1, shift));
                        try self.emit(a64.lslImm(.w32, t4, t2, shift));
                        try self.emit(if (op == .add) a64.adds(.w32, a64.xzr, t3, t4) else a64.subs(.w32, a64.xzr, t3, t4));
                    },
                    else => {
                        try self.emit(a64.lslImm(.w32, t3, t0, shift));
                        try self.emit(a64.logicalShifted(.w32, .ands, a64.xzr, t3, t3, 0));
                    },
                }
            } else switch (op) {
                .add => try self.emit(a64.adds(width, t0, t1, t2)),
                .sub, .cmp => try self.emit(a64.subs(width, t0, t1, t2)),
                .bit_and, .tst => try self.emit(a64.logicalShifted(width, .ands, t0, t1, t2, 0)),
                .bit_or, .bit_xor => {
                    try self.emit(if (op == .bit_or) a64.orrReg(width, t0, t1, t2) else a64.eorReg(width, t0, t1, t2));
                    try self.emit(a64.logicalShifted(width, .ands, a64.xzr, t0, t0, 0));
                },
                .adc, .sbb => unreachable,
            }
            try self.beginFusedRun(fused);
            return;
        }
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
            // FE's byte register may be AH..BH (`dst_high8`).
            try self.loadReg(t1, d.dst_reg, d.dst_high8, size);
        }
        try self.emitIncDecCompute(size, is_inc);
        if (mem) {
            try self.emitStoreOperand(insn, size, index);
            try self.emitAbortCheck(index);
        } else {
            try self.storeReg(d.dst_reg, d.dst_high8, size, t0);
        }
    }

    /// t0 = t1 ± 1 masked, with `flags.applyIncDec`: CF is preserved.
    fn emitIncDecCompute(self: *Compiler, size: Size, is_inc: bool) Error!void {
        const width = arm(size);
        if (self.fuse_pending) |fused| {
            if (size == .bits8 or size == .bits16) {
                const shift: u6 = @intCast(32 - bits(size));
                try self.emitChecked(if (is_inc) a64.addImm(.w32, t0, t1, 1) else a64.subImm(.w32, t0, t1, 1));
                try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(size)).?);
                try self.emit(a64.lslImm(.w32, t3, t1, shift));
                try self.a.loadConstant(t4, @as(u64, 1) << shift);
                try self.emit(if (is_inc) a64.adds(.w32, a64.xzr, t3, t4) else a64.subs(.w32, a64.xzr, t3, t4));
            } else {
                try self.emitChecked(if (is_inc) a64.addsImm(width, t0, t1, 1) else a64.subsImm(width, t0, t1, 1));
            }
            try self.beginFusedRun(fused);
            return;
        }
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
        // compute every flag an exit could read: with the record armed,
        // all of them; without it, the live-out set, which counts every
        // exit as reading all six.
        try self.emitIncDecFlags(size, is_inc, if (defer_flags) F_ALL else self.emit_flag_mask);
    }

    /// The flags of `inc`/`dec` t1 = t0 that `live` names, into `rflags`.
    fn emitIncDecFlags(self: *Compiler, size: Size, is_inc: bool, live: u8) Error!void {
        const width = arm(size);
        const w = bits(size);
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

    /// Shift by `cl`: the count is masked, a zero count leaves memory
    /// untouched (or re-writes a register at its width), and OF is written
    /// only when the count is one (`setFlagsShl/Shr/Sar`). Narrow operands
    /// use the interpreter only when the masked count reaches their width,
    /// where the host's shift and the emulator's undefined-flag convention
    /// need not agree.
    fn emitShiftCl(self: *Compiler, insn: Insn, index: u32) Error!void {
        const d = insn.decoded;
        const size = d.size;
        const width = arm(size);
        const w = bits(size);
        const is_mem = d.op == .shl_mem_cl or d.op == .shr_mem_cl or d.op == .sar_mem_cl;
        const slow = if (w < 32) try self.a.createLabel() else null;
        const done = try self.a.createLabel();
        // The narrow slow edge re-enters the interpreter, which reads
        // rflags from the guest register file. Materialise a preceding lazy
        // flag record before either edge can reach that helper.
        if (slow != null) try self.emitSettleFlags();
        try self.loadReg(t2, .cl_cx_ecx_rcx, false, .bits8);
        try self.emit(a64.logicalImmediate(.w32, .andop, t2, t2, if (size == .bits64) 0x3F else 0x1F).?);
        if (slow) |label| {
            try self.a.loadConstant(t5, w);
            try self.emitChecked(a64.cmp(.w32, t2, t5));
            try self.a.branchCond(.hs, label);
        }
        if (is_mem) {
            try self.emitLoadOperand(insn, size, index);
            // emitRead returns the memory value in x0. Like the other
            // read/modify/write paths, defer the abort check until the write
            // path unless a zero count takes the no-write branch; preserve the
            // value first because the abort check uses x0 as scratch.
            try self.emit(a64.mov(.x64, t1, 0));
            try self.emitAbortCheck(index);
            // Effective-address and memory helpers use x2 as scratch, so
            // recover CL after the read before choosing zero/shift paths.
            try self.loadReg(t2, .cl_cx_ecx_rcx, false, .bits8);
            try self.emit(a64.logicalImmediate(.w32, .andop, t2, t2, if (size == .bits64) 0x3F else 0x1F).?);
        } else {
            try self.loadReg(t1, d.dst_reg, d.dst_high8, size);
        }
        const zero = try self.a.createLabel();
        try self.a.branchIfZero(.w32, t2, zero);
        if (d.op == .sar_reg_cl or d.op == .sar_mem_cl) {
            if (w < 32) try self.emit(a64.sbfx(.w32, t1, t1, 0, @intCast(w)));
        }
        switch (d.op) {
            .shl_reg_cl, .shl_mem_cl => try self.emit(a64.lslv(width, t0, t1, t2)),
            .shr_reg_cl, .shr_mem_cl => try self.emit(a64.lsrv(width, t0, t1, t2)),
            .sar_reg_cl, .sar_mem_cl => try self.emit(a64.asrv(width, t0, t1, t2)),
            else => unreachable,
        }
        if (w < 32) try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, (@as(u64, 1) << @intCast(w)) - 1).?);
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
                .shl_reg_cl, .shl_mem_cl => {
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
                .shl_reg_cl, .shl_mem_cl => {
                    try self.emit(a64.ubfx(width, t4, t0, @intCast(w - 1), 1));
                    try self.emit(a64.eorReg(.w32, t4, t4, t6));
                },
                .shr_reg_cl, .shr_mem_cl => try self.emit(a64.ubfx(width, t4, t1, @intCast(w - 1), 1)),
                .sar_reg_cl, .sar_mem_cl => try self.emit(a64.mov(.w32, t4, a64.wzr)),
                else => unreachable,
            }
            try self.emit(a64.ubfx(.w32, t5, t3, 11, 1));
            try self.emitChecked(a64.cmpImm(.w32, t2, 1));
            try self.emit(a64.csel(.w32, t4, t4, t5, .eq));
            try self.clearFlagBits(t3, RFL_OF);
            try self.orFlagBit(t3, t4, 11);
            try self.storeFlags(t3);
        }
        if (is_mem) {
            try self.emitStoreOperand(insn, size, index);
            try self.emitAbortCheck(index);
        } else {
            try self.storeReg(d.dst_reg, d.dst_high8, size, t0);
        }
        try self.a.branch(done);
        self.a.placeLabel(zero);
        // A zero-count memory shift does not write its operand. A register
        // destination still gets the width-specific write (notably the
        // zero-extension of a 32-bit register result).
        if (!is_mem) try self.storeReg(d.dst_reg, d.dst_high8, size, t1);
        try self.a.branch(done);
        if (slow) |label| {
            self.a.placeLabel(label);
            try self.emitInterpretCall(index);
        }
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

    const BitTestKind = enum { probe, set, reset, complement };

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
            .complement => try self.emit(a64.eorReg(width, t0, t1, t5)),
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
    /// Locked Group-1 updates use a compare-and-swap retry loop so the
    /// complete read/compute/write remains atomic even when a future guest
    /// scheduler runs this context beside another one.
    fn emitAtomic(self: *Compiler, insn: Insn, index: u32, form: AtomicForm) Error!void {
        if (form == .compare_exchange8b) {
            try self.emitAtomicCompareExchange8b(insn, index);
            return;
        }
        if (form == .compare_exchange16b) {
            try self.emitAtomicCompareExchange16b(insn, index);
            return;
        }
        const d = insn.decoded;
        const size = d.size;
        const width = arm(size);
        const bytes: u64 = bits(size) / 8;
        self.touches_memory = true;
        if (form == .bit_set or form == .bit_reset or form == .bit_complement) {
            try self.emitAtomicBitTest(insn, index, form);
            return;
        }
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.emitEffectiveAddress(1, insn);
        try self.emitTlbProbe(true, bytes, true, slow);
        if (bytes > 1) {
            try self.emit(a64.logicalImmediate(.x64, .andop, t5, 1, bytes - 1).?);
            try self.a.branchIfNonZero(.x64, t5, slow);
        }
        // A LOCK operation is a full ordering fence on x86. LSE's acquire /
        // release variants provide the atomic update, while these barriers
        // also order guest accesses on both sides of the transaction.
        try self.emit(a64.dmbIsh());
        switch (form) {
            .exchange => {
                try self.loadReg(t0, d.src_reg, d.src_high8, size);
                try self.emit(a64.swpalScalar(memSize(size), t0, t1, t4));
                try self.storeReg(d.src_reg, d.src_high8, size, t1);
            },
            .compare_exchange => {
                try self.emit(a64.mov(.x64, 2, t4));
                try self.loadReg(t1, .al_ax_eax_rax, false, size);
                try self.emit(a64.mov(width, 3, t1));
                try self.loadReg(t0, d.src_reg, false, size);
                try self.emit(a64.casalScalar(memSize(size), 3, t0, 2));
                try self.emit(a64.mov(width, t2, 3));
                try self.emit(a64.sub(width, t0, t1, t2));
                if (size == .bits8 or size == .bits16) try self.emit(a64.ubfx(.w32, t0, t0, 0, @intCast(bits(size))));
                try self.emitArithmeticFlags(.sub, size, t1, t2, t0, false);
                const matched = try self.a.createLabel();
                try self.emit(a64.cmp(width, t1, t2));
                try self.a.branchCond(.eq, matched);
                try self.storeReg(.al_ax_eax_rax, false, size, t2);
                self.a.placeLabel(matched);
            },
            .compare_exchange8b => unreachable,
            .compare_exchange16b => unreachable,
            .exchange_add => {
                try self.loadReg(t2, d.src_reg, false, size);
                try self.emit(a64.ldaddalScalar(memSize(size), t2, t1, t4));
                try self.emit(a64.add(width, t0, t1, t2));
                if (size == .bits8 or size == .bits16) try self.emit(a64.ubfx(.w32, t0, t0, 0, @intCast(bits(size))));
                try self.emitArithmeticFlags(.add, size, t1, t2, t0, false);
                try self.storeReg(d.src_reg, false, size, t1);
            },
            .update => {
                const op = binaryOpOf(d.op).?;
                switch (binaryShapeOf(d.op)) {
                    .mem_reg => try self.loadReg(t2, d.src_reg, d.src_high8, size),
                    .mem_imm => try self.a.loadConstant(t2, immediateValue(d) & maskFor(size)),
                    else => unreachable,
                }
                const carry_operation = op == .adc or op == .sbb;
                if (carry_operation) {
                    // CAS may retry after another guest thread changed the
                    // word. Keep the instruction's input CF in ip0 (x16),
                    // which none of the retry arithmetic touches, and only
                    // publish flags after the operation commits.
                    try self.loadFlags(t3);
                    try self.emit(a64.logicalImmediate(.w32, .andop, t5, t3, 1).?);
                    try self.emit(a64.mov(.x64, 16, t5));
                }
                const retry = try self.a.createLabel();
                self.a.placeLabel(retry);
                try self.emitChecked(a64.ldrImm(memSize(size), t1, t4, 0).?);
                switch (op) {
                    .add => try self.emit(a64.add(width, t0, t1, t2)),
                    .sub => try self.emit(a64.sub(width, t0, t1, t2)),
                    .adc, .sbb => try self.emitAtomicCarryResult(size, op == .adc),
                    .bit_and => try self.emit(a64.andReg(width, t0, t1, t2)),
                    .bit_or => try self.emit(a64.orrReg(width, t0, t1, t2)),
                    .bit_xor => try self.emit(a64.eorReg(width, t0, t1, t2)),
                    else => unreachable,
                }
                if (size == .bits8 or size == .bits16) try self.emit(a64.ubfx(.w32, t0, t0, 0, @intCast(bits(size))));
                try self.emit(a64.mov(width, 3, t1));
                try self.emit(a64.casalScalar(memSize(size), 3, t0, t4));
                try self.emit(a64.cmp(width, 3, t1));
                try self.a.branchCond(.ne, retry);
                const kind: ArithKind = switch (op) {
                    .add => .add,
                    .sub => .sub,
                    .adc => .add,
                    .sbb => .sub,
                    .bit_and, .bit_or, .bit_xor => .logic,
                    else => unreachable,
                };
                try self.emitArithmeticFlags(kind, size, t1, t2, t0, carry_operation);
            },
            .increment, .decrement => {
                const is_inc = form == .increment;
                const retry = try self.a.createLabel();
                // Flag synthesis uses t4 as scratch, so keep the admitted
                // pointer in t6 while the value is loaded and retried.
                try self.emit(a64.mov(.x64, t6, t4));
                self.a.placeLabel(retry);
                try self.emitChecked(a64.ldrImm(memSize(size), t1, t6, 0).?);
                if (is_inc) {
                    try self.emitChecked(a64.addImm(width, t0, t1, 1));
                } else {
                    try self.emitChecked(a64.subImm(width, t0, t1, 1));
                }
                if (size == .bits8 or size == .bits16) {
                    try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(size)).?);
                }
                try self.emit(a64.mov(width, 3, t1));
                try self.emit(a64.casalScalar(memSize(size), 3, t0, t6));
                try self.emit(a64.cmp(width, 3, t1));
                try self.a.branchCond(.ne, retry);
                // Recompute the committed value and INC/DEC flags from the
                // successful old value; CF is preserved by this helper.
                try self.emitIncDecCompute(size, is_inc);
            },
            .negate => {
                const retry = try self.a.createLabel();
                try self.emit(a64.mov(.x64, t6, t4));
                try self.emit(a64.mov(width, t2, 31));
                self.a.placeLabel(retry);
                try self.emitChecked(a64.ldrImm(memSize(size), t1, t6, 0).?);
                try self.emit(a64.sub(width, t0, t2, t1));
                if (size == .bits8 or size == .bits16) {
                    try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(size)).?);
                }
                try self.emit(a64.mov(width, 3, t1));
                try self.emit(a64.casalScalar(memSize(size), 3, t0, t6));
                try self.emit(a64.cmp(width, 3, t1));
                try self.a.branchCond(.ne, retry);
                try self.emitArithmeticFlags(.sub, size, t2, t1, t0, false);
            },
            .bitwise_not => {
                const retry = try self.a.createLabel();
                try self.emit(a64.mov(.x64, t6, t4));
                self.a.placeLabel(retry);
                try self.emitChecked(a64.ldrImm(memSize(size), t1, t6, 0).?);
                try self.emit(a64.mvn(width, t0, t1));
                if (size == .bits8 or size == .bits16) {
                    try self.emit(a64.logicalImmediate(.w32, .andop, t0, t0, maskFor(size)).?);
                }
                try self.emit(a64.mov(width, 3, t1));
                try self.emit(a64.casalScalar(memSize(size), 3, t0, t6));
                try self.emit(a64.cmp(width, 3, t1));
                try self.a.branchCond(.ne, retry);
            },
            .bit_set, .bit_reset, .bit_complement => unreachable,
        }
        try self.emit(a64.dmbIsh());
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitInterpretCall(index);
        self.a.placeLabel(done);
    }

    /// CMPXCHG8B compares EDX:EAX against one aligned 64-bit memory value,
    /// conditionally stores ECX:EBX, and changes only ZF. Keeping the pair
    /// composition and split in this template avoids an interpreter call for
    /// this Xenos runtime primitive while one CASAL remains the indivisible
    /// memory operation.
    fn emitAtomicCompareExchange8b(self: *Compiler, insn: Insn, index: u32) Error!void {
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        const matched = try self.a.createLabel();
        try self.emitEffectiveAddress(1, insn);
        try self.emitTlbProbe(true, 8, true, slow);
        try self.emitHostAlignmentGuard(t4, 8, slow);
        try self.emit(a64.dmbIsh());

        try self.loadReg(t0, .al_ax_eax_rax, false, .bits32);
        try self.loadReg(t1, .dl_dx_edx_rdx, false, .bits32);
        try self.emit(a64.lslImm(.x64, t1, t1, 32));
        try self.emit(a64.orrReg(.x64, t3, t0, t1));
        try self.emit(a64.mov(.x64, t6, t3));

        try self.loadReg(t0, .bl_bx_ebx_rbx, false, .bits32);
        try self.loadReg(t1, .cl_cx_ecx_rcx, false, .bits32);
        try self.emit(a64.lslImm(.x64, t1, t1, 32));
        try self.emit(a64.orrReg(.x64, t2, t0, t1));
        // CASAL writes the observed word back into the expected-value
        // register (t3), whether the exchange succeeds or fails.
        try self.emit(a64.casalScalar(.doubleword, t3, t2, t4));
        try self.emit(a64.cmp(.x64, t3, t6));
        if (self.emit_flags) {
            try self.emit(a64.cset(.w32, t4, .eq));
            try self.loadFlags(t0);
            try self.clearFlagBits(t0, RFL_ZF);
            try self.orFlagBit(t0, t4, 6);
            try self.storeFlags(t0);
        }
        try self.a.branchCond(.eq, matched);

        // Failure returns the complete observed EDX:EAX pair. The compare
        // result in t3 and original expected value in t6 stay live until the
        // branch above; only then are the two architectural registers split.
        try self.emit(a64.ubfx(.w32, t0, t3, 0, 32));
        try self.emit(a64.lsrImm(.x64, t1, t3, 32));
        try self.storeReg(.al_ax_eax_rax, false, .bits32, t0);
        try self.storeReg(.dl_dx_edx_rdx, false, .bits32, t1);
        self.a.placeLabel(matched);
        try self.emit(a64.dmbIsh());
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitInterpretCall(index);
        self.a.placeLabel(done);
    }

    /// CMPXCHG16B compares RDX:RAX with the two adjacent memory words and,
    /// on a match, stores RCX:RBX. CASPAL consumes even/odd register pairs:
    /// the expected pair is x10/x11 and the desired pair x12/x13. The
    /// returned observed pair is used both for the failure registers and for
    /// the instruction's sole defined flag, ZF.
    fn emitAtomicCompareExchange16b(self: *Compiler, insn: Insn, index: u32) Error!void {
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        const matched = try self.a.createLabel();
        try self.emitEffectiveAddress(1, insn);
        try self.emitTlbProbe(true, 16, true, slow);
        try self.emitHostAlignmentGuard(t4, 16, slow);
        // Preserve the probed host address before t4 is reused to load RCX,
        // the high half of the desired value pair.
        try self.emit(a64.mov(.x64, 16, t4));
        try self.emit(a64.dmbIsh());

        try self.loadReg(t1, .al_ax_eax_rax, false, .bits64);
        try self.loadReg(t2, .dl_dx_edx_rdx, false, .bits64);
        try self.emit(a64.mov(.x64, t5, t1));
        try self.emit(a64.mov(.x64, t6, t2));
        try self.loadReg(t3, .bl_bx_ebx_rbx, false, .bits64);
        try self.loadReg(t4, .cl_cx_ecx_rcx, false, .bits64);
        // x16 is outside the allocated CASP pairs and holds the host address.
        try self.emit(a64.caspal(t1, t3, 16));

        try self.emit(a64.cmp(.x64, t1, t5));
        try self.emit(a64.cset(.w32, t0, .eq));
        try self.emit(a64.cmp(.x64, t2, t6));
        try self.emit(a64.cset(.w32, t5, .eq));
        try self.emit(a64.andReg(.w32, t0, t0, t5));
        if (self.emit_flags) {
            try self.loadFlags(t4);
            try self.clearFlagBits(t4, RFL_ZF);
            try self.orFlagBit(t4, t0, 6);
            try self.storeFlags(t4);
        }
        try self.a.branchIfNonZero(.w32, t0, matched);

        // A mismatch copies the exact memory pair returned by CASPAL into
        // RDX:RAX; the successful path leaves both registers untouched.
        try self.storeReg(.al_ax_eax_rax, false, .bits64, t1);
        try self.storeReg(.dl_dx_edx_rdx, false, .bits64, t2);
        self.a.placeLabel(matched);
        try self.emit(a64.dmbIsh());
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitInterpretCall(index);
        self.a.placeLabel(done);
    }

    /// Unprefixed CMPXCHG and XADD are ordinary read/modify/write sequences,
    /// not indivisible transactions. Use the admitted write page directly
    /// without paying for a host CAS; a page that needs helper semantics
    /// still takes the interpreter's complete instruction path.
    fn emitNonAtomicCompareExchange(self: *Compiler, insn: Insn, index: u32) Error!void {
        const d = insn.decoded;
        const size = d.size;
        const width = arm(size);
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        const mismatch = try self.a.createLabel();
        try self.emitEffectiveAddress(1, insn);
        try self.emitTlbProbe(true, bits(size) / 8, true, slow);
        try self.emitHostAlignmentGuard(t4, bits(size) / 8, slow);
        try self.emitOrderedScalar(false, size, t2, t4);
        // Arithmetic flag materialization uses t4/t5. Preserve the admitted
        // host address across it so the following ordered store cannot be
        // redirected through a flag scratch value.
        try self.emit(a64.mov(.x64, t6, t4));
        try self.loadReg(t1, .al_ax_eax_rax, false, size);
        try self.emit(a64.sub(width, t0, t1, t2));
        if (size == .bits8 or size == .bits16) try self.emit(a64.ubfx(.w32, t0, t0, 0, @intCast(bits(size))));
        try self.emitArithmeticFlags(.sub, size, t1, t2, t0, false);
        try self.emit(a64.cmp(width, t1, t2));
        try self.a.branchCond(.ne, mismatch);
        try self.loadReg(t0, d.src_reg, false, size);
        try self.emitOrderedScalar(true, size, t0, t6);
        try self.a.branch(done);
        self.a.placeLabel(mismatch);
        try self.storeReg(.al_ax_eax_rax, false, size, t2);
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitInterpretCall(index);
        self.a.placeLabel(done);
    }

    fn emitNonAtomicExchangeAdd(self: *Compiler, insn: Insn, index: u32) Error!void {
        const d = insn.decoded;
        const size = d.size;
        const width = arm(size);
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        try self.emitEffectiveAddress(1, insn);
        try self.emitTlbProbe(true, bits(size) / 8, true, slow);
        try self.emitHostAlignmentGuard(t4, bits(size) / 8, slow);
        try self.emitOrderedScalar(false, size, t1, t4);
        // `emitArithmeticFlags` can reuse t4; the host pointer survives in
        // the otherwise-unused t6 until the ordered store commits.
        try self.emit(a64.mov(.x64, t6, t4));
        try self.loadReg(t2, d.src_reg, false, size);
        try self.emit(a64.add(width, t0, t1, t2));
        if (size == .bits8 or size == .bits16) try self.emit(a64.ubfx(.w32, t0, t0, 0, @intCast(bits(size))));
        try self.emitArithmeticFlags(.add, size, t1, t2, t0, false);
        try self.emitOrderedScalar(true, size, t0, t6);
        try self.storeReg(d.src_reg, false, size, t1);
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitInterpretCall(index);
        self.a.placeLabel(done);
    }

    /// Locked BTS/BTR/BTC with an immediate bit index. The CAS retry loop
    /// publishes the bit change atomically and computes CF from the value
    /// whose update actually committed.
    fn emitAtomicBitTest(self: *Compiler, insn: Insn, index: u32, form: AtomicForm) Error!void {
        const d = insn.decoded;
        const size = d.size;
        const width = arm(size);
        const byte_count = bits(size) / 8;
        const register_index = d.op == .bts_mem_reg or d.op == .btr_mem_reg or d.op == .btc_mem_reg;
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        const retry = try self.a.createLabel();
        if (register_index) {
            try self.emitBitTestMemoryRegisterAddress(insn);
            try self.emitBitTestMemoryRegisterMask(d, t6);
        } else {
            try self.emitEffectiveAddress(1, insn);
            const bit: u6 = @intCast(d.imm & (bits(size) - 1));
            try self.a.loadConstant(t6, @as(u64, 1) << bit);
        }
        try self.emitTlbProbe(true, byte_count, true, slow);
        try self.emitHostAlignmentGuard(t4, byte_count, slow);
        try self.emit(a64.dmbIsh());
        self.a.placeLabel(retry);
        try self.emitChecked(a64.ldrImm(memSize(size), t1, t4, 0));
        switch (form) {
            .bit_set => try self.emit(a64.orrReg(width, t0, t1, t6)),
            .bit_reset => try self.emit(a64.bicReg(width, t0, t1, t6)),
            .bit_complement => try self.emit(a64.eorReg(width, t0, t1, t6)),
            else => unreachable,
        }
        try self.emit(a64.mov(width, 3, t1));
        try self.emit(a64.casalScalar(memSize(size), 3, t0, t4));
        try self.emit(a64.cmp(width, 3, t1));
        try self.a.branchCond(.ne, retry);
        if (self.emit_flags) {
            try self.emit(a64.andReg(width, t0, t1, t6));
            try self.emitChecked(a64.cmpImm(width, t0, 0));
            try self.emit(a64.cset(.w32, t4, .ne));
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_CF);
            try self.orFlagBit(t3, t4, 0);
            try self.storeFlags(t3);
        }
        try self.emit(a64.dmbIsh());
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitInterpretCall(index);
        self.a.placeLabel(done);
    }

    /// Compute the memory element selected by a register bit index. For the
    /// memory form, the signed high bits select preceding/following elements;
    /// only the low operand-width bits select the bit inside that element.
    fn emitBitTestMemoryRegisterAddress(self: *Compiler, insn: Insn) Error!void {
        const d = insn.decoded;
        var displacement: u64 = d.addr;
        if (d.rip_relative) displacement +%= insn.rip +% d.len;
        try self.a.loadConstant(1, displacement);
        if (d.sib_has_base) {
            try self.loadReg(t0, d.sib_base_reg, false, .bits64);
            try self.emit(a64.add(.x64, 1, 1, t0));
        }
        if (d.sib_has_index) {
            try self.loadReg(t0, d.sib_index_reg, false, .bits64);
            try self.emit(a64.addSubShifted(.x64, .add, false, 1, 1, t0, d.sib_scale));
        }

        try self.loadReg(t2, d.src_reg, d.src_high8, d.size);
        try self.emit(a64.sbfm(.x64, t5, t2, 0, @intCast(bits(d.size) - 1)));
        const element_shift: u6 = @intCast(@ctz(bits(d.size)));
        const byte_shift: u6 = @intCast(@ctz(bits(d.size) / 8));
        try self.emit(a64.asrImm(.x64, t5, t5, element_shift));
        try self.emit(a64.lslImm(.x64, t5, t5, byte_shift));
        try self.emit(a64.add(.x64, 1, 1, t5));
        if (d.has_0x67) try self.emit(a64.mov(.w32, 1, 1));
        switch (insn.segment) {
            .fs => {
                try self.emitChecked(a64.ldrImm(.doubleword, t0, r_regs, fs_base_offset));
                try self.emit(a64.add(.x64, 1, 1, t0));
            },
            .gs => {
                try self.emitChecked(a64.ldrImm(.doubleword, t0, r_regs, gs_base_offset));
                try self.emit(a64.add(.x64, 1, 1, t0));
            },
            else => {},
        }
    }

    /// Compute the width-limited result and carry/borrow out for a locked
    /// ADC/SBB CAS attempt. x16 contains the instruction's original CF, not
    /// the flags from a failed attempt. t6 carries the out bit to flag
    /// synthesis after the compare/exchange succeeds.
    fn emitAtomicCarryResult(self: *Compiler, size: Size, is_add: bool) Error!void {
        const width_bits = bits(size);
        if (is_add) {
            if (size == .bits64) {
                try self.emit(a64.adds(.x64, t0, t1, t2));
                try self.emit(a64.cset(.w32, t5, .hs));
                try self.emit(a64.adds(.x64, t0, t0, 16));
                try self.emit(a64.cset(.w32, t6, .hs));
                try self.emit(a64.orrReg(.w32, t6, t6, t5));
            } else {
                try self.emit(a64.add(.x64, t0, t1, t2));
                try self.emit(a64.add(.x64, t0, t0, 16));
                try self.emit(a64.ubfx(.x64, t6, t0, @intCast(width_bits), 1));
                try self.emit(a64.logicalImmediate(.x64, .andop, t0, t0, maskFor(size)).?);
            }
        } else if (size == .bits64) {
            try self.emit(a64.subs(.x64, t0, t1, t2));
            try self.emit(a64.cset(.w32, t5, .lo));
            try self.emit(a64.subs(.x64, t0, t0, 16));
            try self.emit(a64.cset(.w32, t6, .lo));
            try self.emit(a64.orrReg(.w32, t6, t6, t5));
        } else {
            try self.emit(a64.sub(.x64, t0, t1, t2));
            try self.emit(a64.sub(.x64, t0, t0, 16));
            try self.emit(a64.ubfx(.x64, t6, t0, @intCast(width_bits), 1));
            try self.emit(a64.logicalImmediate(.x64, .andop, t0, t0, maskFor(size)).?);
        }
    }

    /// `destination = 1 << (index & (operand_bits - 1))` for a memory bit
    /// operation. `destination` must survive the TLB probe when it is `t6`.
    fn emitBitTestMemoryRegisterMask(self: *Compiler, d: DecodedInsn, destination: a64.Reg) Error!void {
        try self.loadReg(t2, d.src_reg, d.src_high8, d.size);
        try self.emit(a64.logicalImmediate(.x64, .andop, t2, t2, bits(d.size) - 1).?);
        try self.a.loadConstant(t5, 1);
        try self.emit(a64.lslv(.x64, destination, t5, t2));
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
            .complement => try self.emit(a64.eorReg(width, t0, 0, t5)),
        }
        try self.emitStoreOperand(insn, size, index);
        try self.emitAbortCheck(index);
    }

    /// `bt`/`bts`/`btr`/`btc [mem], reg`. The high signed index bits select
    /// the addressed operand-sized element. A modifying operation uses the
    /// ordinary ordered read/write helpers unless LOCK routed it through the
    /// CAS implementation above.
    fn emitBitTestMemoryRegister(self: *Compiler, insn: Insn, index: u32, kind: BitTestKind) Error!void {
        const d = insn.decoded;
        const width = arm(d.size);
        try self.emitBitTestMemoryRegisterAddress(insn);
        try self.emitRead(d.size, index);
        try self.emitAbortCheck(index);
        try self.emit(a64.mov(.x64, t1, 0));
        try self.emitBitTestMemoryRegisterMask(d, t5);
        if (self.emit_flags) {
            try self.emit(a64.andReg(width, t4, t1, t5));
            try self.emitChecked(a64.cmpImm(width, t4, 0));
            try self.emit(a64.cset(.w32, t4, .ne));
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_CF);
            try self.orFlagBit(t3, t4, 0);
            try self.storeFlags(t3);
        }
        if (kind == .probe) return;
        switch (kind) {
            .probe => unreachable,
            .set => try self.emit(a64.orrReg(width, t0, t1, t5)),
            .reset => try self.emit(a64.bicReg(width, t0, t1, t5)),
            .complement => try self.emit(a64.eorReg(width, t0, t1, t5)),
        }
        try self.emit(a64.mov(.x64, t6, t0));
        try self.emitBitTestMemoryRegisterAddress(insn);
        try self.emit(a64.mov(.x64, 3, t6));
        try self.emitWrite(d.size, index);
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

    /// Population count for the register forms. The SWAR sequence operates
    /// on a zero-extended source, so it covers 16-, 32-, and 64-bit operands
    /// without a memory helper or an architecture-specific host instruction.
    fn emitPopulationCount(self: *Compiler, d: DecodedInsn) Error!void {
        try self.loadReg(t1, d.src_reg, false, d.size);
        try self.emit(a64.mov(.x64, t0, t1));

        // x = x - ((x >> 1) & 0x5555...)
        try self.emit(a64.lsrImm(.x64, t2, t0, 1));
        try self.emit(a64.logicalImmediate(.x64, .andop, t2, t2, 0x5555_5555_5555_5555).?);
        try self.emit(a64.sub(.x64, t0, t0, t2));

        // Sum adjacent 2-bit fields, then 4-bit fields.
        try self.emit(a64.logicalImmediate(.x64, .andop, t1, t0, 0x3333_3333_3333_3333).?);
        try self.emit(a64.lsrImm(.x64, t2, t0, 2));
        try self.emit(a64.logicalImmediate(.x64, .andop, t2, t2, 0x3333_3333_3333_3333).?);
        try self.emit(a64.add(.x64, t0, t1, t2));
        try self.emit(a64.lsrImm(.x64, t2, t0, 4));
        try self.emit(a64.add(.x64, t1, t0, t2));
        try self.emit(a64.logicalImmediate(.x64, .andop, t0, t1, 0x0F0F_0F0F_0F0F_0F0F).?);

        // Fold each byte into the low byte, then retain the maximum count.
        try self.emit(a64.lsrImm(.x64, t2, t0, 8));
        try self.emit(a64.add(.x64, t0, t0, t2));
        try self.emit(a64.lsrImm(.x64, t2, t0, 16));
        try self.emit(a64.add(.x64, t0, t0, t2));
        if (d.size == .bits64) {
            try self.emit(a64.lsrImm(.x64, t2, t0, 32));
            try self.emit(a64.add(.x64, t0, t0, t2));
        }
        try self.emit(a64.logicalImmediate(.x64, .andop, t0, t0, 0x7F).?);

        if (self.emit_flags) {
            try self.loadFlags(t3);
            try self.clearFlagBits(t3, RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF);
            try self.emitChecked(a64.cmpImm(.x64, t0, 0));
            try self.emit(a64.cset(.w32, t4, .eq));
            try self.orFlagBit(t3, t4, 6);
            try self.storeFlags(t3);
        }
        try self.storeReg(d.dst_reg, false, d.size, t0);
    }

    // -- vector register file and memory ------------------------------------------

    fn xmmOffset(index: u8) u32 {
        return @as(u32, index) * 16;
    }

    fn loadXmm(self: *Compiler, v: a64.Reg, index: u8) Error!void {
        if (self.forward_xmm and self.last_xmm == index) {
            if (v != v0) try self.emit(a64.vmov(v, v0));
            self.xmm_loads_forwarded += 1;
            return;
        }
        if (v == v0) self.last_xmm = null;
        try self.emitChecked(a64.vldrQ(v, r_spare, xmmOffset(index)));
    }

    fn storeXmm(self: *Compiler, index: u8, v: a64.Reg) Error!void {
        // Still publish every architectural result to its private register
        // file. Forwarding saves a subsequent load, never delays a write.
        try self.emitChecked(a64.vstrQ(v, r_spare, xmmOffset(index)));
        self.last_xmm = if (self.forward_xmm and v == v0) index else null;
    }

    fn loadYmmHigh(self: *Compiler, v: a64.Reg, index: u8) Error!void {
        try self.emitRegisterFileAddress(t0, .ymm_hi, xmmOffset(index));
        try self.emitChecked(a64.vldrQ(v, t0, 0));
    }

    fn storeYmmHigh(self: *Compiler, index: u8, v: a64.Reg) Error!void {
        self.zero_ymm &= ~(@as(u32, 1) << @intCast(index));
        try self.emitRegisterFileAddress(t0, .ymm_hi, xmmOffset(index));
        try self.emitChecked(a64.vstrQ(v, t0, 0));
    }

    /// Put the OR of a vector's two 64-bit lanes in `result`. A non-zero
    /// result means at least one tested bit is set. VTESTPS/PD discard the
    /// floating payload bits after reduction; VPTEST retains every bit.
    fn emitVectorAnySet(self: *Compiler, vector: a64.Reg, result: a64.Reg, scratch: a64.Reg, op: Op) Error!void {
        try self.emit(a64.vumov(.d2, result, vector, 0));
        try self.emit(a64.vumov(.d2, scratch, vector, 1));
        try self.emit(a64.orrReg(.x64, result, result, scratch));
        const sign_mask: ?u64 = switch (op) {
            .vtestps => 0x8000_0000_8000_0000,
            .vtestpd => 0x8000_0000_0000_0000,
            else => null,
        };
        if (sign_mask) |mask| try self.emit(a64.logicalImmediate(.x64, .andop, result, result, mask).?);
    }

    fn emitVectorTest(self: *Compiler, insn: Insn, index: u32) Error!void {
        const d = insn.decoded;
        // The interpreter evaluates the complete memory source before it
        // changes flags. Check each half immediately so a fault never leaves
        // partial flag state behind.
        if (!d.is_reg_form) try self.emitSettleFlags();
        if (d.is_reg_form) {
            try self.loadXmm(v2, d.xmm_src2);
            if (d.vector_256) try self.loadYmmHigh(v3, d.xmm_src2);
        } else {
            try self.emitLoadVecOffset(insn, index, v2, 0);
            try self.emitAbortCheck(index);
            if (d.vector_256) {
                try self.emitLoadVecOffset(insn, index, v3, 16);
                try self.emitAbortCheck(index);
            }
        }
        if (!self.emit_flags) return;
        // Clear flags before the reductions: clearFlagBits may borrow t5 as
        // its materialised-mask register, while t4/t5 hold the two reduced
        // predicates below.
        try self.loadFlags(t3);
        try self.clearFlagBits(t3, RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF);
        try self.loadXmm(v1, d.xmm_src);
        try self.emit(a64.vand(v4, v1, v2));
        try self.emitVectorAnySet(v4, t4, t0, d.op);
        try self.emit(a64.vbic(v5, v2, v1));
        try self.emitVectorAnySet(v5, t5, t0, d.op);
        if (d.vector_256) {
            try self.loadYmmHigh(v1, d.xmm_src);
            try self.emit(a64.vand(v4, v1, v3));
            try self.emitVectorAnySet(v4, t6, t0, d.op);
            try self.emit(a64.orrReg(.x64, t4, t4, t6));
            try self.emit(a64.vbic(v5, v3, v1));
            try self.emitVectorAnySet(v5, t6, t0, d.op);
            try self.emit(a64.orrReg(.x64, t5, t5, t6));
        }
        try self.emitChecked(a64.cmpImm(.x64, t4, 0));
        try self.emit(a64.cset(.w32, t6, .eq));
        try self.orFlagBit(t3, t6, 6);
        try self.emitChecked(a64.cmpImm(.x64, t5, 0));
        try self.emit(a64.cset(.w32, t6, .eq));
        try self.orFlagBit(t3, t6, 0);
        try self.storeFlags(t3);
    }

    fn emitPackedFloat(self: *Compiler, form: PackedFloatForm, dst: a64.Reg, lhs: a64.Reg, rhs: a64.Reg) Error!void {
        switch (form.kind) {
            .add => try self.emit(a64.vfadd(form.lanes, dst, lhs, rhs)),
            .sub => try self.emit(a64.vfsub(form.lanes, dst, lhs, rhs)),
            .mul => try self.emit(a64.vfmul(form.lanes, dst, lhs, rhs)),
            .div => try self.emit(a64.vfdiv(form.lanes, dst, lhs, rhs)),
            // `applyVexArithmetic`: min is `if (a < b) a else b`, max
            // `if (a > b) a else b`: the second operand for NaN and ties.
            .min => {
                try self.emit(a64.vfcmgt(form.lanes, dst, rhs, lhs));
                try self.emit(a64.vbsl(dst, lhs, rhs));
            },
            .max => {
                try self.emit(a64.vfcmgt(form.lanes, dst, lhs, rhs));
                try self.emit(a64.vbsl(dst, lhs, rhs));
            },
        }
    }

    fn emitBitwise(self: *Compiler, kind: VectorBitwise, dst: a64.Reg, lhs: a64.Reg, rhs: a64.Reg) Error!void {
        try self.emit(switch (kind) {
            .and_ => a64.vand(dst, lhs, rhs),
            // `~left & right`.
            .andn => a64.vbic(dst, rhs, lhs),
            .or_ => a64.vorr(dst, lhs, rhs),
            .xor => a64.veor(dst, lhs, rhs),
        });
    }

    /// Clear the upper YMM half of `index` (every VEX.128 write), and the
    /// ZMM upper half too for the forms the EVEX executor serves. The upper
    /// files are addressed from the state base: a Zig struct's fields may be
    /// laid out in any order, so nothing assumes they follow `xmm`.
    fn clearUpper(self: *Compiler, index: u8, op: Op) Error!void {
        const bit = @as(u32, 1) << @intCast(index);
        const ymm = self.zero_ymm & bit == 0;
        const zmm = evexRouted(op) and self.zero_zmm & bit == 0;
        if (!ymm) self.upper_clears_elided += 1;
        if (!ymm and !zmm) return;
        try self.emit(a64.vmoviZero(v7));
        if (ymm) {
            try self.emitRegisterFileAddress(t0, .ymm_hi, xmmOffset(index));
            try self.emitChecked(a64.vstrQ(v7, t0, 0));
            self.zero_ymm |= bit;
        }
        if (zmm) {
            try self.emitRegisterFileAddress(t0, .zmm_hi, @as(u32, index) * 32);
            try self.emitChecked(a64.vstrQ(v7, t0, 0));
            try self.emitChecked(a64.vstrQ(v7, t0, 16));
            self.zero_zmm |= bit;
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
        try self.emitTlbProbe(false, 16, false, slow);
        try self.emitOrderedVectorAccess(v, t4, false);
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
        const non_temporal = insn.decoded.op == .vmovntps or insn.decoded.op == .vmovntdq;
        if (!non_temporal) {
            if (self.hoistedOffsetBytes(insn, 16, byte_offset)) |offset| {
                if (!self.hoists[offset.slot].write) return self.emitStoreVecProbed(insn, index, v, byte_offset);
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
        const non_temporal = insn.decoded.op == .vmovntps or insn.decoded.op == .vmovntdq;
        const slow = try self.a.createLabel();
        const done = try self.a.createLabel();
        if (non_temporal) {
            // The admission proof is identical to a temporal store's. The
            // extra guard proves there are no older queued stores to drain.
            // Recheck at runtime so a compiled block is safe after a mode
            // switch, and keep watched/protected/straddling pages on the
            // class-aware path. STLR is stronger than x86's NT ordering.
            try self.emitChecked(a64.ldrImm(.byte, t2, r_scratch, scratch_direct_non_temporal_offset));
            try self.a.branchIfZero(.w32, t2, slow);
        }
        try self.emitTlbProbe(true, 16, false, slow);
        try self.emitOrderedVectorAccess(v, t4, true);
        try self.a.branch(done);
        self.a.placeLabel(slow);
        try self.emitChecked(a64.vstrQ(v, r_scratch, scratch_vector_offset));
        try self.emitCurrentIndex(index);
        try self.emit(a64.mov(.x64, 0, r_state));
        try self.emitChecked(a64.addImm(.x64, 2, r_scratch, scratch_vector_offset));
        try self.emitCallHelper(if (non_temporal) helper_write128_non_temporal_offset else helper_write128_offset);
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

    /// Set v to the all-ones/all-zeros lane mask of predicate `imm & 15`
    /// between v1 (left) and v2 (right), as `VexComparePredicate.evaluate`.
    /// Bit 4 only selects the signalling variant of the same relation.
    fn emitFloatCompareMask(self: *Compiler, lanes: a64.FpLanes, v: a64.Reg, imm: u8) Error!void {
        switch (@as(u4, @truncate(imm))) {
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
            8 => {
                // EQ_UQ: equal, or either operand a NaN.
                try self.emit(a64.vfcmeq(lanes, v3, v1, v1));
                try self.emit(a64.vfcmeq(lanes, v4, v2, v2));
                try self.emit(a64.vand(v3, v3, v4));
                try self.emit(a64.vfcmeq(lanes, v, v1, v2));
                try self.emit(a64.vnot(v3, v3));
                try self.emit(a64.vorr(v, v, v3));
            },
            9 => {
                // NGE_US: FCMGE is false for a NaN, so its inverse is true.
                try self.emit(a64.vfcmge(lanes, v, v1, v2));
                try self.emit(a64.vnot(v, v));
            },
            10 => {
                try self.emit(a64.vfcmgt(lanes, v, v1, v2));
                try self.emit(a64.vnot(v, v));
            },
            11 => try self.emit(a64.vmoviZero(v)),
            12 => {
                // NEQ_OQ: both ordered and not equal.
                try self.emit(a64.vfcmeq(lanes, v3, v1, v1));
                try self.emit(a64.vfcmeq(lanes, v4, v2, v2));
                try self.emit(a64.vand(v3, v3, v4));
                try self.emit(a64.vfcmeq(lanes, v, v1, v2));
                try self.emit(a64.vbic(v, v3, v));
            },
            13 => try self.emit(a64.vfcmge(lanes, v, v1, v2)),
            14 => try self.emit(a64.vfcmgt(lanes, v, v1, v2)),
            15 => try self.emit(a64.vmovi8(v, 0xFF)),
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
            // `convertFloatToDword` rounds to nearest, ties to even.
            try self.emit(a64.vfrint(.nearest_even, .s4, v3, v2));
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

    fn emitPermilpsImmediate(self: *Compiler, dst: a64.Reg, source: a64.Reg, imm: u64) Error!void {
        for (0..4) |lane| {
            const source_lane: u32 = @intCast((imm >> @intCast(lane * 2)) & 3);
            try self.emit(a64.vinsLane(.s4, dst, @intCast(lane), source, source_lane));
        }
    }

    /// Build a byte table index from the low two bits of each control dword.
    /// Each selected float contributes its four bytes without crossing a
    /// 128-bit lane, matching VPERMILPS for both XMM and each YMM half.
    fn emitPermilpsVariable(self: *Compiler, dst: a64.Reg, source: a64.Reg, control: a64.Reg) Error!void {
        try self.emit(a64.vmoviZero(v4));
        try self.emit(a64.vmoviZero(v5));
        for (0..4) |lane| {
            try self.emit(a64.vumov(.s4, t1, control, @intCast(lane)));
            try self.emit(a64.logicalImmediate(.w32, .andop, t1, t1, 3).?);
            try self.emit(a64.lslImm(.w32, t1, t1, 2));
            // The selected dword's byte offset goes into all four index
            // bytes, so the table reads bytes offset..offset+3. Only the low
            // byte held it before: every result took bytes 1-3 from dword 0.
            try self.emit(a64.logicalShifted(.w32, .orr, t1, t1, t1, 8));
            try self.emit(a64.logicalShifted(.w32, .orr, t1, t1, t1, 16));
            try self.emit(a64.vinsGpr(.s4, v4, @intCast(lane), t1));
            try self.a.loadConstant(t1, 0x0302_0100);
            try self.emit(a64.vinsGpr(.s4, v5, @intCast(lane), t1));
        }
        try self.emit(a64.vadd(.s4, v4, v4, v5));
        try self.emit(a64.vtbl(dst, source, v4));
    }

    fn emitVectorMoveMask(self: *Compiler, d: DecodedInsn) Error!void {
        const packed_double = d.op == .vmovmskpd;
        const lanes_per_half: u32 = if (packed_double) 2 else 4;
        const total_lanes = lanes_per_half * (if (d.vector_256) @as(u32, 2) else 1);
        try self.emit(a64.mov(.w32, 0, a64.wzr));
        try self.loadXmm(v1, d.xmm_src);
        if (d.vector_256) try self.loadYmmHigh(v2, d.xmm_src);
        for (0..total_lanes) |lane| {
            const vector = if (lane < lanes_per_half) v1 else v2;
            const vector_lane: u32 = @intCast(lane % lanes_per_half);
            try self.emit(a64.vumov(if (packed_double) .d2 else .s4, t1, vector, vector_lane));
            try self.emit(a64.lsrImm(.x64, t1, t1, if (packed_double) 63 else 31));
            if (lane != 0) try self.emit(a64.lslImm(.w32, t1, t1, @intCast(lane)));
            try self.emit(a64.orrReg(.w32, 0, 0, t1));
        }
        try self.storeReg(d.dst_reg, false, .bits32, 0);
    }

    fn emitPermilps(self: *Compiler, insn: Insn, index: u32) Error!void {
        const d = insn.decoded;
        if (d.uses_imm) {
            const low_source = v1;
            const high_source = v2;
            if (d.vector_256) {
                if (d.is_reg_form) {
                    try self.loadXmm(low_source, d.xmm_src);
                    try self.loadYmmHigh(high_source, d.xmm_src);
                } else {
                    try self.emitLoadVecOffset(insn, index, low_source, 0);
                    try self.emitAbortCheck(index);
                    try self.emitLoadVecOffset(insn, index, high_source, 16);
                    try self.emitAbortCheck(index);
                }
                try self.emitPermilpsImmediate(v0, low_source, d.imm);
                try self.emitPermilpsImmediate(v1, high_source, d.imm);
                try self.storeXmm(d.xmm_dst, v0);
                try self.storeYmmHigh(d.xmm_dst, v1);
            } else {
                try self.loadUnarySource(insn, index, low_source);
                try self.emitPermilpsImmediate(v0, low_source, d.imm);
                try self.storeXmm(d.xmm_dst, v0);
                try self.clearUpper(d.xmm_dst, d.op);
                if (touchesMemory(d)) try self.emitAbortCheck(index);
            }
            return;
        }

        if (d.vector_256) {
            if (d.is_reg_form) {
                try self.loadXmm(v2, d.xmm_src2);
                try self.loadYmmHigh(v3, d.xmm_src2);
            } else {
                try self.emitLoadVecOffset(insn, index, v2, 0);
                try self.emitAbortCheck(index);
                try self.emitLoadVecOffset(insn, index, v3, 16);
                try self.emitAbortCheck(index);
            }
            try self.loadXmm(v1, d.xmm_src);
            try self.emitPermilpsVariable(v0, v1, v2);
            try self.storeXmm(d.xmm_dst, v0);
            try self.loadYmmHigh(v1, d.xmm_src);
            try self.emitPermilpsVariable(v0, v1, v3);
            try self.storeYmmHigh(d.xmm_dst, v0);
        } else {
            try self.loadSource2(insn, index, v2);
            if (touchesMemory(d)) try self.emitAbortCheck(index);
            try self.loadXmm(v1, d.xmm_src);
            try self.emitPermilpsVariable(v0, v1, v2);
            try self.storeXmm(d.xmm_dst, v0);
            try self.clearUpper(d.xmm_dst, d.op);
        }
    }

    /// The vector templates. True when the instruction was emitted here.
    fn emitVectorInsn(self: *Compiler, insn: Insn, index: u32) Error!bool {
        const d = insn.decoded;
        if (!isVectorNative(d)) return false;
        self.touches_vectors = true;
        const dst = d.xmm_dst;
        if (d.op == .vptest or d.op == .vtestps or d.op == .vtestpd) {
            try self.emitVectorTest(insn, index);
            return true;
        }
        if (d.op == .vextractf128) {
            if ((d.imm & 1) == 0) {
                try self.loadXmm(v0, d.xmm_src);
            } else {
                try self.loadYmmHigh(v0, d.xmm_src);
            }
            if (d.is_reg_form) {
                try self.storeXmm(dst, v0);
                try self.clearUpper(dst, d.op);
            } else {
                try self.emitStoreVecOffset(insn, index, v0, 0);
                try self.emitAbortCheck(index);
            }
            return true;
        }
        if (d.op == .vmovmskps or d.op == .vmovmskpd) {
            try self.emitVectorMoveMask(d);
            return true;
        }
        if (d.op == .vpermilps) {
            try self.emitPermilps(insn, index);
            return true;
        }
        if (d.vector_256) {
            if (d.op == .vinsertf128) {
                // Read the XMM/m128 insert source before touching either
                // destination half. A failed memory read therefore leaves
                // the architectural vector register unchanged.
                if (d.is_reg_form) {
                    try self.loadXmm(v2, d.xmm_src2);
                } else {
                    try self.emitLoadVec(insn, index, v2);
                    try self.emitAbortCheck(index);
                }
                try self.loadXmm(v1, d.xmm_src);
                try self.loadYmmHigh(v3, d.xmm_src);
                if ((d.imm & 1) == 0) {
                    try self.storeXmm(dst, v2);
                    try self.storeYmmHigh(dst, v3);
                } else {
                    try self.storeXmm(dst, v1);
                    try self.storeYmmHigh(dst, v2);
                }
                return true;
            }
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
            if (packedFloatForm(d.op)) |form| {
                if (d.is_reg_form) {
                    try self.loadXmm(v2, d.xmm_src2);
                    try self.loadYmmHigh(v3, d.xmm_src2);
                } else {
                    try self.emitLoadVecOffset(insn, index, v2, 0);
                    try self.emitAbortCheck(index);
                    try self.emitLoadVecOffset(insn, index, v3, 16);
                    try self.emitAbortCheck(index);
                }
                try self.loadXmm(v1, d.xmm_src);
                try self.emitPackedFloat(form, v0, v1, v2);
                try self.storeXmm(dst, v0);
                try self.loadYmmHigh(v1, d.xmm_src);
                try self.emitPackedFloat(form, v0, v1, v3);
                try self.storeYmmHigh(dst, v0);
                return true;
            }
            if (bitwiseForm(d.op)) |kind| {
                if (d.is_reg_form) {
                    try self.loadXmm(v2, d.xmm_src2);
                    try self.loadYmmHigh(v3, d.xmm_src2);
                } else {
                    try self.emitLoadVecOffset(insn, index, v2, 0);
                    try self.emitAbortCheck(index);
                    try self.emitLoadVecOffset(insn, index, v3, 16);
                    try self.emitAbortCheck(index);
                }
                try self.loadXmm(v1, d.xmm_src);
                try self.emitBitwise(kind, v0, v1, v2);
                try self.storeXmm(dst, v0);
                try self.loadYmmHigh(v1, d.xmm_src);
                try self.emitBitwise(kind, v0, v1, v3);
                try self.storeYmmHigh(dst, v0);
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
            try self.emitPackedFloat(form, v0, v1, v2);
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
            try self.emitBitwise(kind, v0, v1, v2);
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
            if (!d.legacy_sse) try self.clearUpper(dst, d.op);
            if (touchesMemory(d)) try self.emitAbortCheck(index);
            return true;
        }
        if (shiftForm(d.op)) |form| register_count: {
            if (d.uses_imm or form.kind == .left_bytes or form.kind == .right_bytes) break :register_count;
            // `executeVexPackedShift`'s register forms (0F D1-D3, E1-E2,
            // F1-F3): vvvv shifted by the low 64 bits of r/m, every lane the
            // same. USHL/SSHL take a signed per-lane byte count and give
            // x86's result exactly at +-width (zero, or the sign for SSHL),
            // so the count is clamped to the width and negated for a right
            // shift.
            try self.loadXmm(v1, d.xmm_src);
            try self.loadSource2(insn, index, v2);
            try self.emit(a64.vumov(.d2, t0, v2, 0));
            const width: u16 = @intCast(form.lanes.elementBits());
            try self.emit(a64.movz(.x64, t1, width, 0));
            try self.emit(a64.cmpImm(.x64, t0, width).?);
            try self.emit(a64.csel(.x64, t0, t0, t1, .lo));
            if (form.kind != .left) try self.emit(a64.neg(.x64, t0, t0));
            try self.emit(a64.vdupGpr(form.lanes, v3, t0));
            try self.emit(if (form.kind == .right_arithmetic) a64.vsshlReg(form.lanes, v0, v1, v3) else a64.vushlReg(form.lanes, v0, v1, v3));
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
            .movups_xmm_mem => {
                try self.emitLoadVec(insn, index, v0);
                try self.storeXmm(dst, v0);
                try self.emitAbortCheck(index);
            },
            .movups_mem_xmm => {
                try self.loadXmm(v0, d.xmm_src);
                try self.emitStoreVec(insn, index, v0);
                try self.emitAbortCheck(index);
            },
            .movaps_xmm_xmm => {
                try self.loadXmm(v0, d.xmm_src);
                try self.storeXmm(dst, v0);
            },
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
                if (!d.legacy_sse) try self.clearUpper(dst, d.op);
            },
            .vmovd_xmm_mem32, .vmovq_xmm_mem64, .vmovss_xmm_mem, .vmovsd_xmm_mem => {
                const wide = d.op == .vmovq_xmm_mem64 or d.op == .vmovsd_xmm_mem;
                try self.emitLoadOperand(insn, if (wide) .bits64 else .bits32, index);
                try self.emit(if (wide) a64.fmovFromGpr(v0, 0) else a64.fmovSFromW(v0, 0));
                try self.storeXmm(dst, v0);
                if (!d.legacy_sse) try self.clearUpper(dst, d.op);
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
                // `executeVpalignr`: bytes shift.. of the r/m operand (low)
                // then vvvv (high); 32 and beyond is zero.
                try self.loadSource2(insn, index, v2);
                try self.loadXmm(v1, d.xmm_src);
                const shift: u64 = @min(d.imm & 0xFF, 32);
                if (shift >= 32) {
                    try self.emit(a64.vmoviZero(v0));
                } else if (shift >= 16) {
                    try self.emit(a64.vmoviZero(v7));
                    try self.emit(a64.vext(v0, v1, v7, @intCast(shift - 16)));
                } else if (shift == 0) {
                    try self.emit(a64.vmov(v0, v2));
                } else {
                    try self.emit(a64.vext(v0, v2, v1, @intCast(shift)));
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
            .vrcpss => {
                // The interpreter models VRCPSS as the host single-precision
                // reciprocal. Keep VEX's upper lanes from SRC1 and compute
                // only lane 0 from SRC2 (or the scalar memory operand).
                try self.loadScalarSource2(insn, index, .single, v2);
                try self.loadXmm(v0, d.xmm_src);
                try self.emit(a64.vfmovOne(v3));
                try self.emit(a64.fdiv(.single, v3, v3, v2));
                try self.emit(a64.vinsLane(.s4, v0, 0, v3, 0));
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
                try self.emitRegisterFileAddress(t0, .ymm_hi, 0);
                for (0..32) |register| {
                    try self.emitChecked(a64.vstrQ(v7, t0, xmmOffset(@intCast(register))));
                }
                self.zero_ymm = std.math.maxInt(u32);
            },
            else => return false,
        }
        return true;
    }
};

/// Compile `insns` (contiguous, `end_rip` one past the last byte) into
/// `memory`. A block whose every instruction would be a fallback is refused:
/// it would cost a helper call per instruction and save nothing.
/// Which code-fetch ledger a block's instructions belong to, decided when
/// it is compiled. The glue takes the code cache's share as the chain's
/// total minus the other two, so the common block pays nothing for it.
pub const Ledger = enum(u8) { image, code_cache, other_mapped };

pub const Options = struct {
    ledger: Ledger = .image,
    /// The calling convention's rule: no flag is passed into a `call`, so a
    /// block that ends at one owes no flag to whatever runs next, and a
    /// `ret` owes only what `returnFlagsLive` finds a helper returning.
    /// Without it every block's last flag writer computes all six for an
    /// exit nothing reads, and Xenia's code cache is a call or a return
    /// every twenty instructions.
    flags_dead_at_calls: bool = false,
    /// Every exit leaves all six flags in `rflags`, even a back-edge into
    /// the block whose target reads fewer.
    exact_exit_flags: bool = false,
    /// Let a conditional branch to a later instruction of the block jump
    /// there instead of leaving (`planInternalEdges`).
    internal_edges: bool = true,
};

/// Whether `op` transfers into or back out of a function.
pub fn isCallOrReturn(op: Op) bool {
    return switch (op) {
        .call_rel32, .call_reg64, .call_mem64, .ret => true,
        else => false,
    };
}

/// An instruction whose only effect is the flags it writes. A compiler
/// never leaves one right before a return, because under the calling
/// convention nothing could read it.
fn isPureFlagWriter(op: Op) bool {
    if (binaryOpOf(op)) |binary| return binary == .cmp or binary == .tst;
    return switch (op) {
        .bt_reg_reg, .bt_reg_imm, .bt_mem_imm, .bt_mem_reg => true,
        .vucomiss, .vucomisd, .vptest, .vtestps, .vtestpd => true,
        else => false,
    };
}

/// `add rsp, n` or `sub rsp, n`: the epilogue's stack adjustment, whose
/// flags no caller reads.
fn isStackAdjustment(d: DecodedInsn) bool {
    const binary = binaryOpOf(d.op) orelse return false;
    return (binary == .add or binary == .sub) and d.is_reg_form and d.dst_reg == .ah_sp_esp_rsp;
}

/// The flags a block that ends at `ret` owes its caller under the Windows
/// calling convention.
///
/// The convention passes no flag back through a return, and compiled code
/// keeps to it. A hand-written helper need not. Xenia's reserved-store
/// helper - the host half of every PowerPC `stwcx.` - ends
/// `setz al ; setc ah ; cmp ax, 0x0101 ; ret`, and its caller reads the
/// answer with `setz`. Treating that `cmp` as dead let a store that never
/// happened report success whenever a stale ZF was set: a lost update in
/// every lwarx/stwcx. loop under contention. On 2026-10-03 one desynchronised
/// Halo 3's two-slot render queue, and its render thread polled the empty
/// slot until the run ended. So a return owes:
///  - every flag, when the block's last flag writer only computes flags
///    (cmp, test, bt, ucomis, ptest) and nothing after it in the block reads
///    them: it is there to be returned. `cmp ; setl al ; ret` is not that -
///    the compiler's `setl` consumed it;
///  - ZF and CF, the flags helpers return a boolean in, when the block is not
///    the image's compiled code and its last flag writer is not the
///    epilogue's stack adjustment;
///  - nothing otherwise, which keeps every compiled epilogue free.
pub fn returnFlagsLive(insns: []const Insn, ledger: Ledger) u8 {
    var consumed = false;
    var index = insns.len - 1;
    while (index > 0) {
        index -= 1;
        const insn = insns[index];
        // The interpreter writes every flag into rflags itself.
        if (insn.force_fallback or !isNative(insn.decoded)) return 0;
        const effects = flagEffects(insn);
        if (effects.writes == 0) {
            if (effects.reads != 0) consumed = true;
            continue;
        }
        if (isPureFlagWriter(insn.decoded.op) and !consumed) return F_ALL;
        if (ledger != .image and !isStackAdjustment(insn.decoded)) return F_ZF | F_CF;
        return 0;
    }
    return 0;
}

/// The flags live where the block ends: every flag after anything but a
/// call or a return; under the Windows calling convention, none into a
/// callee and what `returnFlagsLive` says back through a return.
pub fn exitFlagsLive(insns: []const Insn, options: Options) u8 {
    const last = insns[insns.len - 1].decoded.op;
    if (!options.flags_dead_at_calls or !isCallOrReturn(last)) return F_ALL;
    if (last != .ret) return 0;
    return returnFlagsLive(insns, options.ledger);
}

pub fn compile(allocator: std.mem.Allocator, memory: *CodeMemory, layout: Layout, insns: []const Insn, end_rip: u64) Error!Compiled {
    return compileWith(allocator, memory, layout, insns, end_rip, .{});
}

pub fn compileWith(allocator: std.mem.Allocator, memory: *CodeMemory, layout: Layout, insns: []const Insn, end_rip: u64, options: Options) Error!Compiled {
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
    const live_fall = try allocator.alloc(u8, insns.len);
    defer allocator.free(live_fall);
    const live_in = try allocator.alloc(u8, insns.len);
    defer allocator.free(live_in);
    const exit_live = exitFlagsLive(insns, options);
    const elided = flagLivenessToExitFall(insns, wants, live, live_fall, live_in, exit_live);
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
    var written: u16 = 0xFFFF;
    // A register-only block is cross-checked against the interpreter on
    // its first run, register by register and flag by flag, so its exits
    // owe every flag; any other block's back-edge owes only what the code
    // at its target reads.
    var exact_exit_flags = false;
    var allow_internal = options.internal_edges;
    {
        var scratch_assembler = Assembler.init(allocator);
        defer scratch_assembler.deinit();
        var counting = try emitBlock(allocator, &scratch_assembler, layout, insns, end_rip, wants, live, live_block, live_fall, live_in, null, 0xFFFF, allow_internal, options);
        defer counting.compiler.exits.deinit(allocator);
        defer counting.compiler.cold_accesses.deinit(allocator);
        defer counting.compiler.cold_memory.deinit(allocator);
        defer counting.compiler.fused_exits.deinit(allocator);
        defer counting.compiler.freeInternalEdges();
        counts = counting.compiler.use_counts;
        written = counting.compiler.written;
        const first = &counting.compiler;
        exact_exit_flags = !first.touches_memory and !first.touches_vectors and !first.touches_x87 and first.fallback_count == 0;
        if (first.internal_conflict) allow_internal = false;
    }

    var assembler = Assembler.init(allocator);
    defer assembler.deinit();
    var exits = options;
    exits.exact_exit_flags = exits.exact_exit_flags or exact_exit_flags;
    var pass = try emitBlock(allocator, &assembler, layout, insns, end_rip, wants, live, live_block, live_fall, live_in, counts, written, allow_internal, exits);
    if (pass.compiler.internal_conflict) {
        // The same flag decisions as the counting pass, so this should not
        // happen; if it does, the block is emitted without internal edges.
        pass.compiler.exits.deinit(allocator);
        pass.compiler.cold_accesses.deinit(allocator);
        pass.compiler.cold_memory.deinit(allocator);
        pass.compiler.fused_exits.deinit(allocator);
        pass.compiler.freeInternalEdges();
        assembler.deinit();
        assembler = Assembler.init(allocator);
        pass = try emitBlock(allocator, &assembler, layout, insns, end_rip, wants, live, live_block, live_fall, live_in, counts, written, false, exits);
    }
    defer pass.compiler.exits.deinit(allocator);
    defer pass.compiler.cold_accesses.deinit(allocator);
    defer pass.compiler.cold_memory.deinit(allocator);
    defer pass.compiler.fused_exits.deinit(allocator);
    defer pass.compiler.freeInternalEdges();
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
        .register_only = !pass.compiler.touches_memory and !pass.compiler.touches_vectors and !pass.compiler.touches_x87 and pass.compiler.fallback_count == 0,
        .touches_memory = pass.compiler.touches_memory,
        .touches_vectors = pass.compiler.touches_vectors,
        .touches_x87 = pass.compiler.touches_x87,
        .flags_elided = elided,
        .flags_narrowed = pass.compiler.flags_narrowed,
        .return_flags = if (options.flags_dead_at_calls and insns[insns.len - 1].decoded.op == .ret) exit_live else 0,
        .fused_branches = pass.compiler.fused_branches,
        .fused_runs = pass.compiler.fused_runs,
        .cached_registers = pass.compiler.cache_count,
        .hoisted_accesses = pass.compiler.hoisted_accesses,
        .internal_edges = pass.compiler.internal_edges,
        .internal_sources = pass.compiler.internal_sources,
        .upper_clears_elided = pass.compiler.upper_clears_elided,
        .xmm_loads_forwarded = pass.compiler.xmm_loads_forwarded,
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
    live_fall: []const u8,
    live_in: []const u8,
    cache_counts: ?[16]u32,
    cache_written: u16,
    allow_internal: bool,
    options: Options,
) Error!EmittedBlock {
    var compiler = Compiler{
        .a = assembler,
        .layout = layout,
        .insns = insns,
        .end_rip = end_rip,
        .ledger = options.ledger,
        .exact_exit_flags = options.exact_exit_flags,
        .epilogue = try assembler.createLabel(),
        .exit_path = try assembler.createLabel(),
        .epilogue_path = try assembler.createLabel(),
        .exits = .empty,
        .allocator = allocator,
        .flag_wants = wants,
        .flag_live = live,
        .flag_live_block = live_block,
        .flag_live_fall = live_fall,
        .flag_live_in = live_in,
    };
    errdefer compiler.exits.deinit(allocator);
    errdefer compiler.cold_accesses.deinit(allocator);
    errdefer compiler.cold_memory.deinit(allocator);
    errdefer compiler.fused_exits.deinit(allocator);
    compiler.cache_written = cache_written;
    if (cache_counts) |counts| compiler.chooseCache(counts);
    compiler.planHoist();
    try compiler.planInternalEdges(allow_internal);
    errdefer compiler.freeInternalEdges();

    try compiler.emitPrologue();
    // Where a chained block enters: the frame is already established and
    // every cached pointer but `helpers` is already right. The guest
    // register cache is loaded *after* this point, because a chained block
    // has to load its own cache just as an entered one does.
    const chain_entry_bytes: u32 = @intCast(assembler.words.items.len * @sizeOf(u32));
    try compiler.emitCacheLoad();
    if (compiler.uses_skip_counter) try assembler.emit(a64.mov(.x64, skip_reg, a64.xzr));
    var terminated = false;
    for (insns, 0..) |insn, index| {
        compiler.placeInternalTarget(@intCast(index));
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
    try compiler.emitColdMemory();
    try compiler.emitFusedExits();
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

pub const _test_api = struct {
    pub const _a64 = a64;
    pub const _host_fp_control = host_fp_control;
    pub const _x64_decoder = x64_decoder;
    pub const _Assembler = Assembler;
    pub const _Label = Label;
    pub const _CodeMemory = CodeMemory;
    pub const _CodeMemoryError = CodeMemoryError;
    pub const _DecodedInsn = DecodedInsn;
    pub const _Op = Op;
    pub const _RegId = RegId;
    pub const _Size = Size;
    pub const _Cond = Cond;
    pub const _Segment = Segment;
    pub const _Regs = Regs;
    pub const _Error = Error;
    pub const _Helpers = Helpers;
    pub const _helper_read_offset = helper_read_offset;
    pub const _helper_write_offset = helper_write_offset;
    pub const _helper_read128_offset = helper_read128_offset;
    pub const _helper_write128_offset = helper_write128_offset;
    pub const _helper_write128_non_temporal_offset = helper_write128_non_temporal_offset;
    pub const _helper_mapped_transfer_offset = helper_mapped_transfer_offset;
    pub const _helper_hooked_transfer_offset = helper_hooked_transfer_offset;
    pub const _helper_import_transfer_offset = helper_import_transfer_offset;
    pub const _helper_x87_raw_transfer_offset = helper_x87_raw_transfer_offset;
    pub const _helper_x87_memory_offset = helper_x87_memory_offset;
    pub const _helper_interpret_offset = helper_interpret_offset;
    pub const _helper_block_offset = helper_block_offset;
    pub const _helper_flags_offset = helper_flags_offset;
    pub const _Scratch = Scratch;
    pub const _chain_count_shift = chain_count_shift;
    pub const _chain_count_blocks_mask = chain_count_blocks_mask;
    pub const _hoist_hosts = hoist_hosts;
    pub const _hoist_max_span = hoist_max_span;
    pub const _hoist_disp_bias = hoist_disp_bias;
    pub const _HoistCandidate = HoistCandidate;
    pub const _Hoist = Hoist;
    pub const _HoistedOffset = HoistedOffset;
    pub const _FusedExit = FusedExit;
    pub const _ColdAccess = ColdAccess;
    pub const _ColdAbortExit = ColdAbortExit;
    pub const _ColdMemory = ColdMemory;
    pub const _hoistCandidate = hoistCandidate;
    pub const _mayStoreMemoryOperand = mayStoreMemoryOperand;
    pub const _tlbProbeSpanProven = tlbProbeSpanProven;
    pub const _FlagKind = FlagKind;
    pub const _Tlb = Tlb;
    pub const _armConditionHolds = armConditionHolds;
    pub const _tlb_write_offset = tlb_write_offset;
    pub const _Layout = Layout;
    pub const _RegisterFiles = RegisterFiles;
    pub const _hook_filter_bytes = hook_filter_bytes;
    pub const _hook_filter_shift = hook_filter_shift;
    pub const _hook_filter_multiplier = hook_filter_multiplier;
    pub const _hookFilterBit = hookFilterBit;
    pub const _hookFilterAdd = hookFilterAdd;
    pub const _hookFilterHas = hookFilterHas;
    pub const _scratch_abort_offset = scratch_abort_offset;
    pub const _scratch_call_guard_offset = scratch_call_guard_offset;
    pub const _scratch_jmp_guard_offset = scratch_jmp_guard_offset;
    pub const _scratch_ret_guard_offset = scratch_ret_guard_offset;
    pub const _scratch_direct_non_temporal_offset = scratch_direct_non_temporal_offset;
    pub const _scratch_regs_file_offset = scratch_regs_file_offset;
    pub const _scratch_xmm_file_offset = scratch_xmm_file_offset;
    pub const _scratch_ymm_hi_file_offset = scratch_ymm_hi_file_offset;
    pub const _scratch_zmm_hi_file_offset = scratch_zmm_hi_file_offset;
    pub const _scratch_tlb_file_offset = scratch_tlb_file_offset;
    pub const _scratch_transfer_target_offset = scratch_transfer_target_offset;
    pub const _scratch_index_offset = scratch_index_offset;
    pub const _scratch_vector_offset = scratch_vector_offset;
    pub const _scratch_flag_kind_offset = scratch_flag_kind_offset;
    pub const _scratch_flag_size_offset = scratch_flag_size_offset;
    pub const _scratch_flag_a_offset = scratch_flag_a_offset;
    pub const _scratch_flag_b_offset = scratch_flag_b_offset;
    pub const _scratch_flag_r_offset = scratch_flag_r_offset;
    pub const _scratch_chain_break_offset = scratch_chain_break_offset;
    pub const _scratch_chain_count_offset = scratch_chain_count_offset;
    pub const _scratch_chain_budget_offset = scratch_chain_budget_offset;
    pub const _scratch_chain_retired_image_offset = scratch_chain_retired_image_offset;
    pub const _scratch_chain_retired_other_mapped_offset = scratch_chain_retired_other_mapped_offset;
    pub const _scratch_chain_previous_offset = scratch_chain_previous_offset;
    pub const _scratch_jump_cache_offset = scratch_jump_cache_offset;
    pub const _scratch_fused_a_offset = scratch_fused_a_offset;
    pub const _scratch_fused_b_offset = scratch_fused_b_offset;
    pub const _scratch_fused_r_offset = scratch_fused_r_offset;
    pub const _scratch_saved_nzcv_offset = scratch_saved_nzcv_offset;
    pub const _scratch_skip_spill_offset = scratch_skip_spill_offset;
    pub const _scratch_fpcr_writes_offset = scratch_fpcr_writes_offset;
    pub const _scratch_block_offset = scratch_block_offset;
    pub const _FallbackReason = FallbackReason;
    pub const _Insn = Insn;
    pub const _BlockFn = BlockFn;
    pub const _Block = Block;
    pub const _link_ways = link_ways;
    pub const _Link = Link;
    pub const _jump_cache_entries = jump_cache_entries;
    pub const _jump_cache_shift = jump_cache_shift;
    pub const _jumpCacheIndex = jumpCacheIndex;
    pub const _Compiled = Compiled;
    pub const _isNative = isNative;
    pub const _isX87RawTransfer = isX87RawTransfer;
    pub const _isTerminator = isTerminator;
    pub const _isConditionalBranch = isConditionalBranch;
    pub const _isFallbackTerminator = isFallbackTerminator;
    pub const _endsBlockBefore = endsBlockBefore;
    pub const _memoryOperandSupported = memoryOperandSupported;
    pub const _r_state = r_state;
    pub const _r_regs = r_regs;
    pub const _r_helpers = r_helpers;
    pub const _r_scratch = r_scratch;
    pub const _r_tlb = r_tlb;
    pub const _r_spare = r_spare;
    pub const _cache_host_regs = cache_host_regs;
    pub const _cache_callee_saved = cache_callee_saved;
    pub const _cache_min_uses = cache_min_uses;
    pub const _skip_reg = skip_reg;
    pub const _t0 = t0;
    pub const _t1 = t1;
    pub const _t2 = t2;
    pub const _t3 = t3;
    pub const _t4 = t4;
    pub const _t5 = t5;
    pub const _t6 = t6;
    pub const _rip_offset = rip_offset;
    pub const _rflags_offset = rflags_offset;
    pub const _mxcsr_offset = mxcsr_offset;
    pub const _SegmentStateType = SegmentStateType;
    pub const _fs_base_offset = fs_base_offset;
    pub const _gs_base_offset = gs_base_offset;
    pub const _RFL_CF = RFL_CF;
    pub const _RFL_PF = RFL_PF;
    pub const _RFL_AF = RFL_AF;
    pub const _RFL_ZF = RFL_ZF;
    pub const _RFL_SF = RFL_SF;
    pub const _RFL_OF = RFL_OF;
    pub const _bits = bits;
    pub const _maskFor = maskFor;
    pub const _arm = arm;
    pub const _memSize = memSize;
    pub const _gprOffset = gprOffset;
    pub const _signExtendImm8 = signExtendImm8;
    pub const _immForSize = immForSize;
    pub const _ArithKind = ArithKind;
    pub const _defer_flags = defer_flags;
    pub const _BinaryOp = BinaryOp;
    pub const _BinaryShape = BinaryShape;
    pub const _binaryOpOf = binaryOpOf;
    pub const _binaryShapeOf = binaryShapeOf;
    pub const _binaryTouchesMemory = binaryTouchesMemory;
    pub const _ImmediateShape = ImmediateShape;
    pub const _immediateShapeOf = immediateShapeOf;
    pub const _immediateValue = immediateValue;
    pub const _isIncDec = isIncDec;
    pub const _incDecSize = incDecSize;
    pub const _F_CF = F_CF;
    pub const _F_PF = F_PF;
    pub const _F_AF = F_AF;
    pub const _F_ZF = F_ZF;
    pub const _F_SF = F_SF;
    pub const _F_OF = F_OF;
    pub const _F_ALL = F_ALL;
    pub const _conditionReads = conditionReads;
    pub const _liveFlagBits = liveFlagBits;
    pub const _FlagEffects = FlagEffects;
    pub const _shiftCount = shiftCount;
    pub const _flagEffects = flagEffects;
    pub const _flagWants = flagWants;
    pub const _flagLiveness = flagLiveness;
    pub const _flagLivenessToExit = flagLivenessToExit;
    pub const _flagLivenessToExitFall = flagLivenessToExitFall;
    pub const _FusedKind = FusedKind;
    pub const _Fused = Fused;
    pub const _fusedCondition = fusedCondition;
    pub const _flagLivenessFrom = flagLivenessFrom;
    pub const _v0 = v0;
    pub const _v1 = v1;
    pub const _v2 = v2;
    pub const _v3 = v3;
    pub const _v4 = v4;
    pub const _v5 = v5;
    pub const _v6 = v6;
    pub const _v7 = v7;
    pub const _evexRouted = evexRouted;
    pub const _VectorBinary = VectorBinary;
    pub const _packedIntegerForm = packedIntegerForm;
    pub const _FloatBinary = FloatBinary;
    pub const _PackedFloatForm = PackedFloatForm;
    pub const _packedFloatForm = packedFloatForm;
    pub const _scalarFloatForm = scalarFloatForm;
    pub const _VectorBitwise = VectorBitwise;
    pub const _bitwiseForm = bitwiseForm;
    pub const _unpackForm = unpackForm;
    pub const _ShiftKind = ShiftKind;
    pub const _shiftForm = shiftForm;
    pub const _extendForm = extendForm;
    pub const _ymmMoveForm = ymmMoveForm;
    pub const _AtomicForm = AtomicForm;
    pub const _atomicForm = atomicForm;
    pub const _lockPrefixAllowed = lockPrefixAllowed;
    pub const _isVectorNative = isVectorNative;
    pub const _ExitStub = ExitStub;
    pub const _r_exit_rip = r_exit_rip;
    pub const _Compiler = Compiler;
    pub const _Ledger = Ledger;
    pub const _Options = Options;
    pub const _isCallOrReturn = isCallOrReturn;
    pub const _isPureFlagWriter = isPureFlagWriter;
    pub const _isStackAdjustment = isStackAdjustment;
    pub const _returnFlagsLive = returnFlagsLive;
    pub const _exitFlagsLive = exitFlagsLive;
    pub const _compile = compile;
    pub const _compileWith = compileWith;
    pub const _EmittedBlock = EmittedBlock;
    pub const _emitBlock = emitBlock;
};
