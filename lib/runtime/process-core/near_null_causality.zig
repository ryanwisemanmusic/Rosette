//! Fault-triggered near-null dataflow diagnostics.
//!
//! This module deliberately records no additional hot-path log output. It
//! consumes the bounded instruction, memory-access, allocation, and last-writer
//! histories already maintained by MachOState, and emits a causal chain only
//! after a terminal near-null access has been confirmed.

const std = @import("std");
const x64_decoder = @import("x64_decoder");
const macho_core = @import("macho_core");
const machoCapturePrint = @import("dyld").event_log.machoCapturePrint;

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
    if (!decoded.sib_has_base and !decoded.sib_has_index and !decoded.rip_relative) {
        machoCapturePrint(
            "macho-processor: near-null causality: terminal rip=0x{x} op={s} effective=0x{x}; decoder exposed no address expression\n",
            .{ self.regs.rip, @tagName(decoded.op), effective_address },
        );
        return;
    }

    const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
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

    machoCapturePrint(
        "macho-processor: near-null causality: terminal rip=0x{x} op={s} effective=0x{x} displacement=0x{x} base({s})=0x{x} index({s},scale={d})=0x{x} rip_component=0x{x}\n",
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
        },
    );

    // A zero C++ `this` argument is the strongest causal landmark in the
    // retained trace. Resolve it before following the terminal arithmetic,
    // which may otherwise end at a callee's copied zero stack local.
    const invalid_this_explained = dumpZeroThisRoot(self);

    if (decoded.sib_has_base) {
        dumpRegisterChain(
            self,
            decoded.sib_base_reg,
            base_value,
            "base",
            !invalid_this_explained,
        );
    }
    if (decoded.sib_has_index) {
        dumpRegisterChain(
            self,
            decoded.sib_index_reg,
            index_value,
            "index",
            !invalid_this_explained,
        );
    }
}

fn dumpRegisterChain(
    self: anytype,
    register: RegId,
    terminal_value: u64,
    role: []const u8,
    allow_direct_producer: bool,
) void {
    const count: usize = if (self.trace_filled) self.trace_entries.len else self.trace_index;
    if (count == 0) return;

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
        const transition = findPreviousTransition(self, register, after, &cursor) orelse break;
        const symbol = self.metadata.nearestSymbol(transition.instruction_address);
        machoCapturePrint(
            "macho-processor: near-null causality: {s}_chain[{d}] register={s} before=0x{x} after=0x{x} instruction=0x{x} {s}+0x{x} retained_distance={d}\n",
            .{
                role,
                chain_depth,
                @tagName(register),
                transition.before,
                transition.after,
                transition.instruction_address,
                if (symbol) |resolved| resolved.name else "<unknown>",
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
            if (caller) |resolved| resolved.name else "<unknown>",
            if (caller) |resolved| resolved.offset else 0,
            boundary.callee_address,
            if (callee) |resolved| resolved.name else "<unknown>",
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
    const count: usize = if (self.trace_filled) self.trace_entries.len else self.trace_index;
    if (count < 2) return null;

    const fault_thread = self.active_guest_thread;
    var best: ?CallBoundary = null;
    var ordinal: usize = 0;
    while (ordinal + 1 < count) : (ordinal += 1) {
        const entry = self.trace_entries[chronologicalTraceIndex(self, count, ordinal)];
        if (entry.thread_handle != fault_thread or entry.rdi != 0 or !isCall(entry)) continue;

        const callee_address =
            nextSameThreadRip(self, count, ordinal + 1, fault_thread) orelse continue;
        const callee = self.metadata.nearestSymbol(callee_address) orelse continue;
        // Zero is a valid scalar first argument for many C functions. Limit
        // the inference to Xenia C++ instance methods, where RDI is `this`.
        if (!std.mem.startsWith(u8, callee.name, "__ZN2xe") and
            !std.mem.startsWith(u8, callee.name, "_ZN2xe"))
        {
            continue;
        }
        best = .{
            .ordinal = ordinal,
            .call_address = entry.rip,
            .callee_address = callee_address,
        };
    }
    return best;
}

fn findPreviousTransition(
    self: anytype,
    register: RegId,
    expected_after: u64,
    cursor: *usize,
) ?Transition {
    const count: usize = if (self.trace_filled) self.trace_entries.len else self.trace_index;
    const fault_thread = self.active_guest_thread;
    var after = expected_after;
    var retained_distance: usize = 0;
    while (cursor.* != 0) {
        cursor.* -= 1;
        const index = chronologicalTraceIndex(self, count, cursor.*);
        const entry = self.trace_entries[index];
        if (entry.thread_handle != fault_thread) continue;
        retained_distance += 1;
        const before = traceRegisterValue(entry, register);
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
            access.bytes != @sizeOf(u64) or
            access.value != transition.after)
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
    const trace_count: usize = if (self.trace_filled)
        self.trace_entries.len
    else
        self.trace_index;
    if (transition.trace_ordinal >= trace_count) return null;
    const entry = self.trace_entries[
        chronologicalTraceIndex(
            self,
            trace_count,
            transition.trace_ordinal,
        )
    ];
    const decoded = self.decodeTraceInstruction(entry) orelse return null;
    if (decoded.op != .mov_reg64_mem64 or
        decoded.dst_reg != transition.register)
    {
        return null;
    }
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
                if (reader) |symbol| symbol.name else "<unknown>",
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
                if (reader) |symbol| symbol.name else "<unknown>",
                if (reader) |symbol| symbol.offset else 0,
            },
        );
    }

    if (self.memory_writes.lookup(producer.slot)) |writer| {
        const writer_symbol = self.metadata.nearestSymbol(writer.instruction_address);
        machoCapturePrint(
            "macho-processor: near-null causality: producer_last_writer slot=0x{x} previous=0x{x} value=0x{x} kind={s} writer=0x{x} {s}+0x{x} step={d} age_steps={d} thread=0x{x}\n",
            .{
                writer.address,
                writer.previous_value,
                writer.value,
                @tagName(writer.kind),
                writer.instruction_address,
                if (writer_symbol) |resolved| resolved.name else "<unknown>",
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
            "macho-processor: near-null causality: producer_last_writer slot=0x{x} absent; no retained pointer-bearing initialization or clear reached this member\n",
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
    if (!std.mem.eql(u8, role, "this") and terminal_register_value < 0x1000) {
        if (self.memory_forwarder.containingAllocation(producer.slot)) |allocation| {
            machoCapturePrint(
                "macho-processor: near-null ROOT CAUSE: class=zero_container_backing_pointer_to_derived_near_null allocation=0x{x} member_offset=0x{x} source_slot=0x{x} source_value=0x0 derived_{s}=0x{x} displaced_prior_register=0x{x}; inspect the source slot's clear/free/reuse history, not the terminal stdlib helper\n",
                .{
                    allocation.base,
                    allocation.offset,
                    producer.slot,
                    role,
                    terminal_register_value,
                    previous_register_value,
                },
            );
            return;
        }
        machoCapturePrint(
            "macho-processor: near-null ROOT CAUSE: class=zero_backing_pointer_to_derived_near_null source_slot=0x{x} source_value=0x0 derived_{s}=0x{x} displaced_prior_register=0x{x}; inspect the source slot's clear/free/reuse history, not the terminal stdlib helper\n",
            .{
                producer.slot,
                role,
                terminal_register_value,
                previous_register_value,
            },
        );
        return;
    }
    if (self.memory_forwarder.containingAllocation(producer.slot)) |allocation| {
        machoCapturePrint(
            "macho-processor: near-null ROOT CAUSE: class=null_object_member_to_invalid_this object=0x{x} member_offset=0x{x} member_slot=0x{x} member_value=0x0 displaced_prior_register=0x{x}; inspect object/base-constructor initialization or the call that supplied this dependency, not the terminal container access\n",
            .{ allocation.base, allocation.offset, producer.slot, previous_register_value },
        );
        return;
    }
    machoCapturePrint(
        "macho-processor: near-null ROOT CAUSE: class=zero_pointer_load_to_invalid_this source_slot=0x{x} displaced_prior_register=0x{x}; inspect the exact producer and its initialization path\n",
        .{ producer.slot, previous_register_value },
    );
}

fn chronologicalTraceIndex(self: anytype, count: usize, ordinal: usize) usize {
    const start: usize = if (self.trace_filled) self.trace_index else 0;
    return (start + ordinal) % count;
}

fn chronologicalMemoryIndex(self: anytype, count: usize, ordinal: usize) usize {
    const start: usize = if (self.memory_trace_filled) self.memory_trace_index else 0;
    return (start + ordinal) % count;
}

fn nextSameThreadRip(self: anytype, count: usize, start_ordinal: usize, thread: u64) ?u64 {
    var ordinal = start_ordinal;
    while (ordinal < count) : (ordinal += 1) {
        const entry = self.trace_entries[chronologicalTraceIndex(self, count, ordinal)];
        if (entry.thread_handle == thread) return entry.rip;
    }
    return null;
}

fn isCall(entry: TraceEntry) bool {
    return std.mem.startsWith(u8, @tagName(entry.op), "call_");
}

fn traceRegisterValue(entry: TraceEntry, register: RegId) u64 {
    return switch (@intFromEnum(register)) {
        0 => entry.rax,
        1 => entry.rcx,
        2 => entry.rdx,
        3 => entry.rbx,
        4 => entry.rsp,
        5 => entry.rbp,
        6 => entry.rsi,
        7 => entry.rdi,
        8 => entry.r8,
        9 => entry.r9,
        10 => entry.r10,
        11 => entry.r11,
        12 => entry.r12,
        13 => entry.r13,
        14 => entry.r14,
        15 => entry.r15,
    };
}
