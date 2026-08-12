//! Fault-triggered near-null dataflow diagnostics.
//!
//! This module deliberately records no additional hot-path log output. It
//! consumes the bounded instruction, memory-access, allocation, and last-writer
//! histories already maintained by MachOState, and emits a causal chain only
//! after a terminal near-null access has been confirmed.

const std = @import("std");
const x64_decoder = @import("x64_decoder");
const macho_core = @import("macho_core");
const vtable_ownership = @import("vtable").ownership;
const memory_write_provenance = @import("memory").memory_write_provenance;
const scan_limits = @import("execution_history").bounded_scan.Limits;
const machoCapturePrint = @import("dyld").event_log.machoCapturePrint;
const byte_order = @import("byte_order");
const memory_access = @import("memory_access.zig");

const RegId = x64_decoder.RegId;
const Size = x64_decoder.OperandSize;
const TraceEntry = macho_core.types.TraceEntry;
const decodeInsn = macho_core.decoder.decodeInsn;

const Transition = struct {
    instruction_address: u64,
    trace_ordinal: usize,
    register: RegId,
    before: u64,
    after: u64,
    retained_distance: usize,
};

const Producer = struct {
    slot: u64,
    instruction_address: u64,
};

const CallBoundary = struct {
    ordinal: usize,
    call_address: u64,
    callee_address: u64,
};

pub fn dumpTerminal(self: anytype, effective_address: u64) void {
    const bytes = self.guestMemoryConst(self.regs.rip, 16) orelse return;
    const decoded = decodeInsn(bytes);
    const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;

    // Fault-time instruction bytes and full GPR snapshot. This block runs only
    // in the confirmed near-null terminal path (never in the hot loop), so the
    // exact encoding (e.g. a 0x67 address-size override, a REX/MOVBE form, or a
    // register-materialized address) and the entire register file are recorded
    // to make the next failure self-explanatory.
    const raw_len: usize = @min(@as(usize, decoded.len), bytes.len);
    machoCapturePrint(
        "macho-processor: near-null causality: terminal bytes={any} len={d} addr_size={s} has_0x67={} generated_rip={} op={s}\n",
        .{
            bytes[0..raw_len],
            decoded.len,
            @tagName(address_size),
            decoded.has_0x67,
            self.sparse_memory.isExecutable(self.regs.rip, 1),
            @tagName(decoded.op),
        },
    );
    machoCapturePrint(
        "macho-processor: near-null causality: gpr rax=0x{x} rcx=0x{x} rdx=0x{x} rbx=0x{x} rsp=0x{x} rbp=0x{x} rsi=0x{x} rdi=0x{x}\n",
        .{
            self.regs.rax,
            self.regs.rcx,
            self.regs.rdx,
            self.regs.rbx,
            self.regs.rsp,
            self.regs.rbp,
            self.regs.rsi,
            self.regs.rdi,
        },
    );
    machoCapturePrint(
        "macho-processor: near-null causality: gpr r8=0x{x} r9=0x{x} r10=0x{x} r11=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x} rip=0x{x} rflags=0x{x}\n",
        .{
            self.regs.r8,
            self.regs.r9,
            self.regs.r10,
            self.regs.r11,
            self.regs.r12,
            self.regs.r13,
            self.regs.r14,
            self.regs.r15,
            self.regs.rip,
            self.regs.rflags,
        },
    );

    reportByteOrderSurvey(self);

    if (!decoded.sib_has_base and !decoded.sib_has_index and !decoded.rip_relative) {
        machoCapturePrint(
            "macho-processor: near-null causality: terminal rip=0x{x} op={s} effective=0x{x}; decoder exposed no address expression\n",
            .{ self.regs.rip, @tagName(decoded.op), effective_address },
        );
        return;
    }

    const base_value = if (decoded.sib_has_base)
        x64_decoder.regVal(&self.regs, decoded.sib_base_reg, address_size)
    else
        0;
    const index_value = if (decoded.sib_has_index)
        x64_decoder.regVal(&self.regs, decoded.sib_index_reg, address_size)
    else
        0;
    const scaled_index = index_value << @as(u6, decoded.sib_scale);
    const rip_component = if (decoded.rip_relative) self.regs.rip + decoded.len else 0;

    const src_value = switch (decoded.op) {
        .mov_mem64_reg64,
        .mov_mem32_reg32,
        .mov_mem16_reg16,
        .mov_mem8_reg8,
        => x64_decoder.regVal(&self.regs, decoded.src_reg, address_size),
        else => 0,
    };

    machoCapturePrint(
        "macho-processor: near-null causality: terminal rip=0x{x} op={s} effective=0x{x} displacement=0x{x} base({s})=0x{x} index({s},scale={d})=0x{x} rip_component=0x{x} src({s})=0x{x} symbol={s}\n",
        .{
            self.regs.rip,
            @tagName(decoded.op),
            effective_address,
            decoded.addr,
            if (decoded.sib_has_base) @tagName(decoded.sib_base_reg) else "<none>",
            base_value,
            if (decoded.sib_has_index) @tagName(decoded.sib_index_reg) else "<none>",
            @as(u8, 1) << decoded.sib_scale,
            scaled_index,
            rip_component,
            @tagName(decoded.src_reg),
            src_value,
            self.metadata.symbolLabel(self.regs.rip),
        },
    );
    // Vtable ownership diagnostics: if the crash involves a write of a
    // non-zero value through a null pointer, check whether that value
    // is a vtable and classify its origin (host-resolved vs guest-written).
    // This separates host-side issues (corrupted dyld binding) from
    // guest-side issues (null `this` in Xenia's constructors).
    if (src_value >= 0x1000 and (decoded.op == .mov_mem64_reg64 or
        decoded.op == .mov_mem32_reg32 or
        decoded.op == .mov_mem16_reg16))
    {
        const origin = vtable_ownership.classifyOrigin(src_value, self.metadata);
        if (origin != .unknown) {
            const origin_str = @tagName(origin);
            const symbol = self.metadata.nearestSymbol(src_value);
            machoCapturePrint(
                "macho-processor: vtable ownership: value=0x{x} origin={s} symbol={s}+0x{x}\n",
                .{
                    src_value,
                    origin_str,
                    self.metadata.symbolLabel(src_value),
                    if (symbol) |s| s.offset else @as(i64, 0),
                },
            );
            if (effective_address == 0) {
                const writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
                machoCapturePrint(
                    "macho-processor: vtable consistency: null this (this=0x0) — guest-side bug: constructor called on null object at {s}+0x{x}\n",
                    .{
                        self.metadata.symbolLabel(self.regs.rip),
                        if (writer_symbol) |s| s.offset else 0,
                    },
                );
            }
        }
    }

    // A zero C++ `this` argument is the strongest causal landmark in the
    // retained trace. Resolve it before following the terminal arithmetic,
    // which may otherwise end at a callee's copied zero stack local.
    const invalid_this_explained = dumpZeroThisRoot(self);

    // `base_value`/`index_value` were read at the terminal instruction's
    // address width. The trace ring stores whole 64-bit registers, so the walk
    // must compare at the same width. Under a 0x67 override a base register
    // holding, say, 0x1_0000_0000 reads as 0 in the address expression while
    // every trace entry reads as 0x1_0000_0000 — an unmasked comparison would
    // report the most recent entry as a fabricated 0x1_0000_0000 -> 0
    // transition and attribute the fault to an instruction that never touched
    // the register. Every 0x67 fault handed here by the bounded dispatch
    // transducer takes this path.
    const address_mask: u64 = addressWidthMask(address_size);
    if (decoded.sib_has_base) {
        dumpRegisterChain(
            self,
            decoded.sib_base_reg,
            base_value,
            address_mask,
            "base",
            !invalid_this_explained,
        );
    }
    if (decoded.sib_has_index) {
        dumpRegisterChain(
            self,
            decoded.sib_index_reg,
            index_value,
            address_mask,
            "index",
            !invalid_this_explained,
        );
    }
}

/// Whether the register file holds guest addresses with their bytes reversed.
///
/// This runs before the causal walk on purpose. A 32-bit guest address reversed
/// as a 64-bit value leaves **zero in the low half**, so a dispatch or load
/// through the low register faults on a null base — and every question the walk
/// then asks is about the null. The walk answers those questions correctly and
/// the answers are about a symptom.
///
/// One reversed register is a site. More than one, independently, is the
/// conversion path itself, and that is a different investigation. Only the count
/// distinguishes them, and nothing was counting.
fn reportByteOrderSurvey(self: anytype) void {
    const Window = struct {
        state: @TypeOf(self),
        fn isGuest(ctx: @This(), address: u64) bool {
            // Any observed guest mapping, not just the module window: a guest
            // stack or heap pointer that arrived byte-reversed is the same
            // defect as a reversed code address, and scoring it "unrelated"
            // is how a systematic conversion failure reads as a single site.
            return memory_access.isGuestMappedValue(ctx.state, address);
        }
    };
    const slots = [_]byte_order.Slot{
        .{ .name = "rax", .value = self.regs.rax },
        .{ .name = "rcx", .value = self.regs.rcx },
        .{ .name = "rdx", .value = self.regs.rdx },
        .{ .name = "rbx", .value = self.regs.rbx },
        .{ .name = "rsp", .value = self.regs.rsp },
        .{ .name = "rbp", .value = self.regs.rbp },
        .{ .name = "rsi", .value = self.regs.rsi },
        .{ .name = "rdi", .value = self.regs.rdi },
        .{ .name = "r8", .value = self.regs.r8 },
        .{ .name = "r9", .value = self.regs.r9 },
        .{ .name = "r10", .value = self.regs.r10 },
        .{ .name = "r11", .value = self.regs.r11 },
        .{ .name = "r12", .value = self.regs.r12 },
        .{ .name = "r13", .value = self.regs.r13 },
        .{ .name = "r14", .value = self.regs.r14 },
        .{ .name = "r15", .value = self.regs.r15 },
    };
    const found = byte_order.survey.survey(Window, .{ .state = self }, &slots, Window.isGuest);
    if (found.reversed() == 0) return;

    machoCapturePrint(
        "macho-processor: near-null causality: BYTE ORDER SURVEY examined={d} native_guest={d} reversed32={d} reversed64={d} ambiguous={d} reversed_with_null_low_half={d} independent={d} systematic={}; {s}\n",
        .{
            found.examined,
            found.native,
            found.reversed32,
            found.reversed64,
            found.ambiguous,
            found.null_low_half,
            found.independent,
            found.systematic(),
            if (found.systematic())
                "more than one register independently holds a guest address in host byte order, so this is the guest-memory conversion path and not a single bad instruction. Do not spend the investigation on the faulting address"
            else if (found.independent <= 1 and found.reversed() > 1)
                "several registers classify as reversed, but they hold one allocation's worth of pointers rather than independent data — one witness, not several. A host pointer whose low byte lands in the guest window reverses into it by arithmetic alone, so treat this as coincidence and investigate the faulting address normally"
            else
                "one register holds a guest address in host byte order; the fault site and the conversion site may be the same instruction",
        },
    );
    var index: usize = 0;
    while (index < found.reported) : (index += 1) {
        const finding = found.findings[index];
        machoCapturePrint(
            "macho-processor: near-null causality: byte order {s}=0x{x} order={s} corrected=0x{x}{s}\n",
            .{
                found.names[index],
                found.values[index],
                @tagName(finding.order),
                finding.corrected,
                if (finding.low_half_zero)
                    "; its low 32 bits are ZERO, so any dispatch or load through the low half of this register faults on a null base — a null derived from byte order, not from a missing store"
                else
                    "",
            },
        );
    }
}

/// Comparison mask for register values observed at a given address width.
/// Widths narrower than the trace ring's storage must be masked on both sides
/// or the walk compares an architectural truncation against a whole register.
fn addressWidthMask(size: Size) u64 {
    return switch (size) {
        .bits8 => 0xFF,
        .bits16 => 0xFFFF,
        .bits32 => 0xFFFF_FFFF,
        .bits64 => std.math.maxInt(u64),
    };
}

fn dumpRegisterChain(
    self: anytype,
    register: RegId,
    terminal_value: u64,
    value_mask: u64,
    role: []const u8,
    allow_direct_producer: bool,
) void {
    const count: usize = self.execution_history.countFor(self.active_guest_thread);
    // Report the tape before walking it. A bounded machine that cannot reach
    // the evidence must say so; the previous behaviour was to print nothing at
    // all, which reads as "no cause found" when it means "not looked far
    // enough". The ring is process-wide and filtered per thread, so the useful
    // depth is the same-thread count, not the ring size.
    const window = retainedWindow(self);
    const memory_trace_status: []const u8 = if (window.memory_entries != 0)
        ""
    else if (!self.memory_trace_enabled)
        "; memory trace disabled by ROSETTE_MACHO_MEMORY_TRACE=0; exact memory-producer attribution is unavailable"
    else
        "; memory trace enabled but no entries were retained for this thread";
    machoCapturePrint(
        "macho-processor: near-null causality: {s}_window register={s} terminal=0x{x} mask=0x{x} thread=0x{x} thread_entries={d}/{d} saturated={} live_threads={d} evicted_threads={d} recorded={d} filtered={d} status=\"{s}\" memory_trace_entries={d}{s}\n",
        .{
            role,
            @tagName(register),
            terminal_value,
            value_mask,
            self.active_guest_thread,
            window.same_thread,
            window.capacity,
            window.saturated,
            window.live_threads,
            window.evictions,
            window.recorded,
            window.skipped,
            window.reason,
            window.memory_entries,
            memory_trace_status,
        },
    );
    if (count == 0) return;
    if (window.same_thread == 0) {
        machoCapturePrint(
            "macho-processor: near-null causality: {s}_chain UNDECIDABLE register={s}; the retained instruction ring holds no entries for the faulting thread, so no transition can be recovered. This is a tape limit, not an absence of cause\n",
            .{ role, @tagName(register) },
        );
        return;
    }

    var cursor = count;
    var after = terminal_value;
    var chain_depth: usize = 0;
    var producer: ?Producer = null;
    var producer_before: u64 = 0;
    var modeled_streambuf: ?u64 = null;

    // Container iterators commonly copy a derived address through six or more
    // helpers before the terminal access. Keep this bounded, but deep enough
    // to reach the backing-slot load rather than stopping at values such as
    // 0x40 that were merely added to a null block pointer.
    while (cursor != 0 and chain_depth < 12) {
        const transition = findPreviousTransition(self, register, after, value_mask, &cursor) orelse {
            // No transition anywhere in the retained window means the register
            // held this value for the whole tape. That is a decidable and very
            // specific finding — the value was not produced within reach — and
            // it must not be reported as silence.
            if (chain_depth == 0) {
                machoCapturePrint(
                    "macho-processor: near-null causality: {s}_chain UNDECIDABLE register={s} value=0x{x}; the register held this value across all {d} retained same-thread entries, so its producer predates the tape. Look upstream of the retained window: the defining instruction is outside it, not missing\n",
                    .{ role, @tagName(register), terminal_value, window.same_thread },
                );
            }
            break;
        };
        const symbol = self.metadata.nearestSymbol(transition.instruction_address);
        // Decode the instruction that performed the transition. A value pair on
        // its own leaves the reader to infer the operation — `0x80000000 -> 0x1`
        // is a sign-bit extract, but only if you notice that 0x80000000 >> 31
        // is 1. Naming the op turns a puzzle into a reading, and the bytes make
        // it checkable when the decoder and the reader disagree.
        var op_bytes: [8]u8 = undefined;
        var op_len: usize = 0;
        var op_name: []const u8 = "<undecoded>";
        if (self.guestMemoryConst(transition.instruction_address, 16)) |raw| {
            const decoded_transition = decodeInsn(raw);
            if (decoded_transition.op != .invalid and decoded_transition.len != 0) {
                op_name = @tagName(decoded_transition.op);
                op_len = @min(@as(usize, decoded_transition.len), op_bytes.len);
                @memcpy(op_bytes[0..op_len], raw[0..op_len]);
            }
        }
        machoCapturePrint(
            "macho-processor: near-null causality: {s}_chain[{d}] register={s} before=0x{x} after=0x{x} instruction=0x{x} op={s} bytes={any} {s}+0x{x} retained_distance={d}\n",
            .{
                role,
                chain_depth,
                @tagName(register),
                transition.before,
                transition.after,
                transition.instruction_address,
                op_name,
                op_bytes[0..op_len],
                self.metadata.symbolLabel(transition.instruction_address),
                if (symbol) |resolved| resolved.offset else 0,
                transition.retained_distance,
            },
        );

        if (comptime @hasField(@TypeOf(self.*), "libcxx_streams")) {
            if (self.libcxx_streams.modeledStreamObjectForAddress(transition.before)) |streambuf| {
                modeled_streambuf = streambuf;
            }
        }

        if (allow_direct_producer) {
            if (findExactProducer(self, transition)) |exact_producer| {
                producer = exact_producer;
                producer_before = transition.before;
                dumpProducer(self, exact_producer);
                break;
            }
        }

        after = transition.before;
        chain_depth += 1;
    }

    if (producer) |exact_producer| {
        if (modeled_streambuf) |streambuf| {
            machoCapturePrint(
                "macho-processor: near-null ROOT CAUSE: class=modeled_libcpp_streambuf_native_fallback streambuf=0x{x} source_slot=0x{x} derived_{s}=0x{x}; Rosette modeled this stream object but execution escaped into a native libc++ get-area path. Extend libcpp_stream_bridge/local symbol interception; do not repair the terminal near-null address\n",
                .{ streambuf, exact_producer.slot, role, terminal_value },
            );
            return;
        }
        dumpRootClassification(
            self,
            exact_producer,
            producer_before,
            role,
            terminal_value,
        );
    }
}

fn dumpZeroThisRoot(self: anytype) bool {
    const boundary = findZeroThisBoundary(self) orelse return false;
    const caller = self.metadata.nearestSymbol(boundary.call_address);
    const callee = self.metadata.nearestSymbol(boundary.callee_address);
    machoCapturePrint(
        "macho-processor: near-null causality: invalid_this_boundary call=0x{x} {s}+0x{x} this=0x0 callee=0x{x} {s}+0x{x}\n",
        .{
            boundary.call_address,
            self.metadata.symbolLabel(boundary.call_address),
            if (caller) |resolved| resolved.offset else 0,
            boundary.callee_address,
            self.metadata.symbolLabel(boundary.callee_address),
            if (callee) |resolved| resolved.offset else 0,
        },
    );

    // Register snapshots are captured before each instruction. Starting at
    // the call and walking backward therefore finds the instruction that
    // changed RDI to zero in the caller, not a copied zero inside the callee.
    var cursor = boundary.ordinal + 1;
    const transition = findPreviousTransition(
        self,
        .bh_di_edi_rdi,
        0,
        std.math.maxInt(u64),
        &cursor,
    ) orelse {
        machoCapturePrint(
            "macho-processor: near-null causality: invalid_this_producer unavailable; the caller-side RDI transition predates retained history\n",
            .{},
        );
        return false;
    };
    const producer = findExactProducer(self, transition) orelse {
        machoCapturePrint(
            "macho-processor: near-null causality: invalid_this_producer instruction=0x{x} before=0x{x} after=0x0 but no exact same-instruction 64-bit zero read was retained\n",
            .{ transition.instruction_address, transition.before },
        );
        return false;
    };

    dumpProducer(self, producer);
    dumpRootClassification(self, producer, transition.before, "this", 0);
    return true;
}

fn findZeroThisBoundary(self: anytype) ?CallBoundary {
    const count: usize = self.execution_history.countFor(self.active_guest_thread);
    if (count < 2) return null;

    const fault_thread = self.active_guest_thread;
    var best: ?CallBoundary = null;
    var ordinal: usize = 0;
    while (ordinal + 1 < count) : (ordinal += 1) {
        const entry = traceEntry(self, ordinal) orelse continue;
        if (entry.thread_handle != fault_thread or entry.rdi != 0 or !isCall(entry)) continue;

        const callee_address =
            nextSameThreadRip(self, count, ordinal + 1, fault_thread) orelse continue;
        // Zero is a valid scalar first argument for many C functions, so a
        // zero RDI at a call is only a `this` fault when the callee actually
        // dereferences it. Decide that from the callee's own instructions
        // rather than from its name: a symbol-prefix test only recognises the
        // one program whose namespace was hardcoded, and silently stops
        // classifying anything else — including the same program built with a
        // different mangling, and every statically linked dependency.
        if (!calleeDereferencesFirstArgument(self, callee_address)) continue;
        best = .{
            .ordinal = ordinal,
            .call_address = entry.rip,
            .callee_address = callee_address,
        };
    }
    return best;
}

/// How much tape the causality walk actually has. The instruction ring is
/// process-wide, so a run with many live guest threads leaves each one only a
/// fraction of it — the number that matters is the same-thread count.
pub const RetainedWindow = struct {
    /// Why an empty window is empty. Reported verbatim, because "the recogniser
    /// found nothing" and "nothing was recorded" are different findings and the
    /// second was silently presented as the first for a long time.
    reason: []const u8,
    recorded: u64,
    skipped: u64,
    same_thread: usize,
    capacity: usize,
    /// The thread has filled its window, so "not found" may mean "overwritten".
    saturated: bool,
    live_threads: usize,
    evictions: u64,
    memory_entries: usize,
};

pub fn retainedWindow(self: anytype) RetainedWindow {
    const window = self.execution_history.windowFor(self.active_guest_thread);
    const memory_entries: usize = if (self.memory_trace_filled)
        self.memory_trace_entries.len
    else
        self.memory_trace_index;
    return .{
        .reason = if (window.emptyBecauseDisabled())
            "instruction history recording is DISABLED; this is not an absence of evidence"
        else if (window.emptyBecauseFiltered())
            filteredWindowReason(
                self.regs.rip >= self.executable_min and
                    self.regs.rip < self.executable_max,
            )
        else if (window.thread_entries == 0)
            "recording is enabled but nothing was retained for this thread yet"
        else
            "retained",
        .recorded = window.recorded,
        .skipped = window.skipped,
        .same_thread = window.thread_entries,
        .capacity = window.thread_capacity,
        .saturated = window.saturated(),
        .live_threads = window.live_threads,
        .evictions = window.evictions,
        .memory_entries = memory_entries,
    };
}

/// Explain an empty generated-code-only history without changing a deliberate
/// host-code filter into a false runtime defect. A generated fault with no
/// retained entries remains a real policy/ordering problem; a native Mach-O
/// fault is outside this tape by construction.
pub fn filteredWindowReason(fault_in_host_image: bool) []const u8 {
    return if (fault_in_host_image)
        "fault is in native Mach-O host code, intentionally outside the generated-code-only history; use fault-local ownership evidence or explicitly enable all-instruction tracing"
    else
        "fault is in generated code but no instruction in this thread passed the generated-code-only policy; this is a policy or ordering defect";
}

test "filtered history distinguishes native exclusion from generated policy defect" {
    try std.testing.expect(std.mem.indexOf(
        u8,
        filteredWindowReason(true),
        "intentionally outside",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        filteredWindowReason(false),
        "policy or ordering defect",
    ) != null);
}

/// The value a register held on the faulting thread at the most recent
/// retained point where it was not zero, together with how many same-thread
/// trace entries back that was.
pub const ClearedValue = struct {
    value: u64,
    retained_distance: usize,
};

/// Recover the value a register held before it was most recently cleared to
/// zero, from the retained instruction trace of the faulting thread.
///
/// This exists because a fault whose defining condition is "this register is
/// zero" destroys the only snapshot a fault-time read could return. Any
/// question about what the register was *supposed* to hold has to be answered
/// from history, not from the register file. The walk is bounded by the trace
/// ring itself, filters to the faulting thread, and reports the distance so a
/// caller can require recency or record it for audit.
///
/// Returns null when the register is zero throughout retained history — which
/// is the honest answer, not a licence to guess.
pub fn lastNonZeroBeforeClear(self: anytype, register: RegId, value_mask: u64) ?ClearedValue {
    const count: usize = self.execution_history.countFor(self.active_guest_thread);
    if (count == 0) return null;

    var cursor = count;
    var retained_distance: usize = 0;
    while (cursor != 0) {
        cursor -= 1;
        const entry = traceEntry(self, cursor) orelse continue;
        retained_distance += 1;
        const observed = traceRegisterValue(entry, register) & value_mask;
        if (observed != 0) {
            return .{ .value = observed, .retained_distance = retained_distance };
        }
    }
    return null;
}

/// Decide whether a callee treats its first integer argument (RDI under the
/// System V ABI) as a pointer it dereferences, by reading a bounded prologue
/// window of the callee itself. This is the behavioural replacement for asking
/// whether the callee's symbol belongs to a particular program's namespace.
///
/// The window is a finite tape: at most 12 instructions or 48 bytes, no
/// branches followed, no speculative execution. It answers yes on the first
/// memory operand based or indexed on RDI, and no as soon as RDI is redefined
/// before any such use (the callee took a scalar, or reloaded the register),
/// or when control flow leaves the straight-line prologue without an answer.
/// Undecided is reported as no, so a missing answer never manufactures a
/// `this` boundary.
fn calleeDereferencesFirstArgument(self: anytype, callee_address: u64) bool {
    const arg0: RegId = .bh_di_edi_rdi;
    const limits = scan_limits.callee_prologue;
    var cursor = callee_address;
    var examined: u8 = 0;
    while (examined < limits.max_instructions and
        cursor >= callee_address and limits.withinBytes(callee_address, cursor)) : (examined += 1)
    {
        const bytes = self.guestMemoryConst(cursor, 16) orelse return false;
        const decoded = decodeInsn(bytes);
        if (decoded.op == .invalid or decoded.len == 0) return false;

        if (!decoded.rip_relative and
            ((decoded.sib_has_base and decoded.sib_base_reg == arg0) or
                (decoded.sib_has_index and decoded.sib_index_reg == arg0)))
        {
            return true;
        }

        switch (decoded.op) {
            // Leaving straight-line code ends the proof. Following the edge
            // would turn a bounded reader into a search.
            .jmp_rel8,
            .jmp_reg64,
            .jmp_mem64,
            .jcc_rel8,
            .jcc_rel32,
            .call_rel32,
            .call_reg64,
            .call_mem64,
            .ret,
            => return false,
            // Redefinitions of the argument register itself. Conservative on
            // purpose: an op missing from this list only costs a few more
            // instructions of window, never a wrong `true`.
            .mov_reg32_reg32,
            .mov_reg64_reg64,
            .mov_reg_imm,
            .mov_reg32_mem32,
            .mov_reg64_mem64,
            .lea_reg_mem,
            .pop_reg,
            .xor_reg32_reg32,
            .xor_reg64_reg64,
            => if (decoded.dst_reg == arg0) return false,
            else => {},
        }
        cursor +|= decoded.len;
    }
    return false;
}

fn findPreviousTransition(
    self: anytype,
    register: RegId,
    expected_after: u64,
    value_mask: u64,
    cursor: *usize,
) ?Transition {
    // Entries are already partitioned per thread, so no filtering is needed:
    // every retained entry here belongs to the faulting thread by construction.
    var after = expected_after & value_mask;
    var retained_distance: usize = 0;
    while (cursor.* != 0) {
        cursor.* -= 1;
        const entry = traceEntry(self, cursor.*) orelse continue;
        retained_distance += 1;
        const before = traceRegisterValue(entry, register) & value_mask;
        if (before != after) {
            return .{
                .instruction_address = entry.rip,
                .trace_ordinal = cursor.*,
                .register = register,
                .before = before,
                .after = after,
                .retained_distance = retained_distance,
            };
        }
        after = before;
    }
    return null;
}

fn findExactProducer(self: anytype, transition: Transition) ?Producer {
    // A register becoming zero is only attributed to a memory slot when the
    // retained memory event was emitted by that exact instruction. This avoids
    // the old failure mode of choosing an unrelated recent zero-valued stack
    // read.
    if (transition.after != 0) return null;
    const count: usize = if (self.memory_trace_filled)
        self.memory_trace_entries.len
    else
        self.memory_trace_index;
    var reverse = count;
    while (reverse != 0) {
        reverse -= 1;
        const index = chronologicalMemoryIndex(self, count, reverse);
        const access = self.memory_trace_entries[index];
        if (access.instruction_address != transition.instruction_address or
            !std.mem.eql(u8, access.access, "read") or
            (access.bytes != 1 and access.bytes != 2 and access.bytes != 4 and access.bytes != 8) or
            access.value != 0)
        {
            continue;
        }
        return .{
            .slot = access.address,
            .instruction_address = access.instruction_address,
        };
    }

    // The memory-access ring is intentionally shorter than the instruction
    // ring. Reconstruct the effective address from the exact historical
    // instruction snapshot when a helper-heavy libc++ path has already pushed
    // the read out of the memory ring.
    const trace_count: usize = self.execution_history.countFor(self.active_guest_thread);
    if (transition.trace_ordinal >= trace_count) return null;
    const entry = traceEntry(self, transition.trace_ordinal) orelse return null;
    const decoded = self.decodeWithSnapshotOperands(entry) orelse return null;
    const load_size: Size = switch (decoded.op) {
        .mov_reg8_mem8 => .bits8,
        .mov_reg16_mem16 => .bits16,
        .mov_reg32_mem32 => .bits32,
        .mov_reg64_mem64 => .bits64,
        .movbe_reg_mem => decoded.size,
        else => return null,
    };
    if (decoded.dst_reg != transition.register) return null;

    // Re-reading is admissible only if the source still demonstrates the
    // transition. The previous implementation returned every historical
    // MOV64 address without checking its value and therefore attributed a
    // later MOVBE-produced zero to an unrelated earlier slot.
    const byte_count: usize = switch (load_size) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32 => 4,
        .bits64 => 8,
    };
    const source = self.guestMemoryConst(decoded.addr, byte_count) orelse return null;
    if (source.len < byte_count) return null;
    const raw_value: u64 = switch (load_size) {
        .bits8 => source[0],
        .bits16 => std.mem.readInt(u16, source[0..2], .little),
        .bits32 => std.mem.readInt(u32, source[0..4], .little),
        .bits64 => std.mem.readInt(u64, source[0..8], .little),
    };
    const loaded_value = if (decoded.op == .movbe_reg_mem)
        x64_decoder.byteSwap(load_size, raw_value)
    else
        raw_value;
    const value_mask: u64 = switch (load_size) {
        .bits8 => std.math.maxInt(u8),
        .bits16 => std.math.maxInt(u16),
        .bits32 => std.math.maxInt(u32),
        .bits64 => std.math.maxInt(u64),
    };
    if ((loaded_value & value_mask) != (transition.after & value_mask)) return null;
    return .{
        .slot = decoded.addr,
        .instruction_address = transition.instruction_address,
    };
}

fn dumpProducer(self: anytype, producer: Producer) void {
    const reader = self.metadata.nearestSymbol(producer.instruction_address);
    if (self.memory_forwarder.containingAllocation(producer.slot)) |allocation| {
        machoCapturePrint(
            "macho-processor: near-null causality: exact_producer loaded_zero_from=0x{x} reader=0x{x} {s}+0x{x} allocation_base=0x{x} member_offset=0x{x} allocation_size={d}\n",
            .{
                producer.slot,
                producer.instruction_address,
                self.metadata.symbolLabel(producer.instruction_address),
                if (reader) |symbol| symbol.offset else 0,
                allocation.base,
                allocation.offset,
                allocation.size,
            },
        );
    } else {
        machoCapturePrint(
            "macho-processor: near-null causality: exact_producer loaded_zero_from=0x{x} reader=0x{x} {s}+0x{x} allocation=<not-forwarded>\n",
            .{
                producer.slot,
                producer.instruction_address,
                self.metadata.symbolLabel(producer.instruction_address),
                if (reader) |symbol| symbol.offset else 0,
            },
        );
    }

    if (self.memory_writes.lookup(producer.slot)) |writer| {
        const writer_symbol = self.metadata.nearestSymbol(writer.instruction_address);
        // A host-authored repair records the faulting guest RIP as its writer.
        // Say so before the symbol is printed, or the next reader concludes that
        // a guest function wrote a value Rosette wrote.
        if (memory_write_provenance.isHostAuthored(writer.kind)) {
            machoCapturePrint(
                "macho-processor: near-null causality: producer_last_writer slot=0x{x} value=0x{x} kind=host_repair; this slot was last written by a Rosette fault repair, not by the guest. The recorded writer 0x{x} is the guest instruction that was faulting at the time and did not perform this store — do not attribute guest behaviour to it. Investigate the repair that wrote here\n",
                .{ writer.address, writer.value, writer.instruction_address },
            );
            return;
        }
        machoCapturePrint(
            "macho-processor: near-null causality: producer_last_writer slot=0x{x} previous=0x{x} value=0x{x} kind={s} writer=0x{x} {s}+0x{x} step={d} age_steps={d} thread=0x{x}\n",
            .{
                writer.address,
                writer.previous_value,
                writer.value,
                @tagName(writer.kind),
                writer.instruction_address,
                self.metadata.symbolLabel(writer.instruction_address),
                if (writer_symbol) |resolved| resolved.offset else 0,
                writer.step,
                self.executed_steps -| writer.step,
                writer.thread,
            },
        );
        if (writer.value != 0) {
            machoCapturePrint(
                "macho-processor: near-null causality: provenance divergence slot=0x{x} tracked_value=0x{x} observed_value=0x0; a write bypassed retained scalar provenance (partial store, bulk fill/copy, or host-side mutation). Range-mutation tracking is required before attributing this to the recorded writer\n",
                .{ producer.slot, writer.value },
            );
        }
        if (self.memory_writes.lookupPrevious(producer.slot)) |previous_writer| {
            const previous_symbol =
                self.metadata.nearestSymbol(previous_writer.instruction_address);
            machoCapturePrint(
                "macho-processor: near-null causality: producer_prior_writer slot=0x{x} previous=0x{x} value=0x{x} kind={s} writer=0x{x} {s}+0x{x} step={d} age_steps={d} thread=0x{x}; retained_before_latest_clear_or_replacement=true\n",
                .{
                    previous_writer.address,
                    previous_writer.previous_value,
                    previous_writer.value,
                    @tagName(previous_writer.kind),
                    previous_writer.instruction_address,
                    if (previous_symbol) |resolved| resolved.name else "<unknown>",
                    if (previous_symbol) |resolved| resolved.offset else 0,
                    previous_writer.step,
                    self.executed_steps -| previous_writer.step,
                    previous_writer.thread,
                },
            );
        }
    } else {
        machoCapturePrint(
            "macho-processor: near-null causality: producer_last_writer slot=0x{x} absent; no retained initialization or clear reached this member. This is missing evidence, not proof that no write occurred: the bounded watch may have armed after initialization or filled before this page was discovered\n",
            .{producer.slot},
        );
    }
}

fn dumpRootClassification(
    self: anytype,
    producer: Producer,
    previous_register_value: u64,
    role: []const u8,
    terminal_register_value: u64,
) void {
    const producer_history = if (self.memory_writes.lookup(producer.slot) != null)
        "retained"
    else
        "not_retained";
    if (!std.mem.eql(u8, role, "this") and terminal_register_value < 0x1000) {
        if (self.memory_forwarder.containingAllocation(producer.slot)) |allocation| {
            machoCapturePrint(
                "macho-processor: near-null FIRST INVALID TRANSITION: class=zero_container_backing_pointer_to_derived_near_null allocation=0x{x} member_offset=0x{x} source_slot=0x{x} source_value=0x0 derived_{s}=0x{x} displaced_prior_register=0x{x} producer_history={s}; this proves where valid state became zero-derived, not why the source was zero. Inspect its producer/dependency path, not the terminal helper\n",
                .{
                    allocation.base,
                    allocation.offset,
                    producer.slot,
                    role,
                    terminal_register_value,
                    previous_register_value,
                    producer_history,
                },
            );
            return;
        }
        machoCapturePrint(
            "macho-processor: near-null FIRST INVALID TRANSITION: class=zero_backing_pointer_to_derived_near_null source_slot=0x{x} source_value=0x0 derived_{s}=0x{x} displaced_prior_register=0x{x} producer_history={s}; this proves where valid state became zero-derived, not why the source was zero. Correlate earlier failed dependencies or allocations before attributing a clear\n",
            .{
                producer.slot,
                role,
                terminal_register_value,
                previous_register_value,
                producer_history,
            },
        );
        return;
    }
    if (self.memory_forwarder.containingAllocation(producer.slot)) |allocation| {
        machoCapturePrint(
            "macho-processor: near-null FIRST INVALID TRANSITION: class=null_object_member_to_invalid_this object=0x{x} member_offset=0x{x} member_slot=0x{x} member_value=0x0 displaced_prior_register=0x{x} producer_history={s}; inspect object initialization or the dependency that supplied this member\n",
            .{ allocation.base, allocation.offset, producer.slot, previous_register_value, producer_history },
        );
        return;
    }
    machoCapturePrint(
        "macho-processor: near-null FIRST INVALID TRANSITION: class=zero_pointer_load_to_invalid_this source_slot=0x{x} displaced_prior_register=0x{x} producer_history={s}; inspect the source's producer and initialization path\n",
        .{ producer.slot, previous_register_value, producer_history },
    );
}

/// Chronological entry for the faulting thread. All ring arithmetic lives in
/// the execution-history library now; this is the one accessor this module
/// needs, and it can no longer disagree with any other consumer's copy.
fn traceEntry(self: anytype, ordinal: usize) ?TraceEntry {
    return self.execution_history.chronological(self.active_guest_thread, ordinal);
}

fn chronologicalMemoryIndex(self: anytype, count: usize, ordinal: usize) usize {
    const start: usize = if (self.memory_trace_filled) self.memory_trace_index else 0;
    return (start + ordinal) % count;
}

fn nextSameThreadRip(self: anytype, count: usize, start_ordinal: usize, thread: u64) ?u64 {
    var ordinal = start_ordinal;
    while (ordinal < count) : (ordinal += 1) {
        const entry = traceEntry(self, ordinal) orelse continue;
        if (entry.thread_handle == thread) return entry.rip;
    }
    return null;
}

fn isCall(entry: TraceEntry) bool {
    return std.mem.startsWith(u8, @tagName(entry.op), "call_");
}

/// Delegates to the one owner of the RegId-to-snapshot-field mapping:
/// `TraceEntry` itself. This module used to carry its own copy.
fn traceRegisterValue(entry: TraceEntry, register: RegId) u64 {
    return entry.registerValue(register);
}
