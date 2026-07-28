//! Guest memory translation, provenance, vtable lifecycle tracking, sparse
//! mappings, and terminal memory-access diagnostics.
//!
//! MachOState owns storage. This module owns the invariants that make a guest
//! address readable, writable, executable, or intentionally opaque.

const std = @import("std");
const x64_decoder = @import("x64_decoder");
const macho_core = @import("macho_core");
const types = macho_core.types;
const constants = macho_core.constants;
const decodeInsn = macho_core.decoder.decodeInsn;
const compat_runtime = @import("macho_compat_runtime");
const exit_diagnostics = @import("exit_diagnostics");
const initialization_resolution = @import("init").initialization_engine;
const initializer_dependency = @import("init").initializer_dependency;
const memory_mod = @import("memory");
const sparse_virtual_memory = memory_mod.sparse_virtual_memory;
const memory_provenance = @import("dyld").memory_provenance;
const pointer_firewall = @import("dyld").pointer_firewall;
const semantic_fault_classifier = @import("diagnostics").semantic_fault_classifier;
const opaque_lifetime_recovery = @import("diagnostics").opaque_lifetime_recovery;
const guest_assertion_recovery = @import("guest_abi").guest_assertion_recovery;
const vt = @import("vtable");
const guest_log = @import("guest_log.zig");
const near_null_causality = @import("near_null_causality.zig");
const machoCapturePrint = @import("dyld").event_log.machoCapturePrint;

const Size = x64_decoder.OperandSize;
const RegId = x64_decoder.RegId;
const DecodedInsn = x64_decoder.DecodedInsn;
const TraceEntry = types.TraceEntry;
const GuestAccess = types.GuestAccess;
const GuestAccessDescription = types.GuestAccessDescription;
const bytesForSize = memory_mod.bytesForSize;
const memReadMemVal = memory_mod.readMemVal;
const MemReadCallbacks = memory_mod.ReadMemValCallbacks;

const PAGE_SIZE = constants.PAGE_SIZE;
const PAGE_READ = constants.PAGE_READ;
const PAGE_WRITE = constants.PAGE_WRITE;
const PAGE_EXECUTE = constants.PAGE_EXECUTE;
const TRACE_BUFFER_LEN = constants.TRACE_BUFFER_LEN;
const MEMORY_TRACE_BUFFER_LEN = constants.MEMORY_TRACE_BUFFER_LEN;
const GUEST_SIGSEGV = constants.GUEST_SIGSEGV;

const mappedOffset = macho_core.utils.mappedOffset;

pub fn addrToOffset(self: anytype, vaddr: u64) ?u64 {
    if (!self.pointer_firewall.mayDereference(vaddr)) return null;
    return mappedOffset(self.mem_base, self.mem_size, self.mapped_min, vaddr);
}

pub fn setPagePermissions(self: anytype, address: u64, size: u64, permissions: u8) void {
    if (size == 0 or address < self.mem_base) return;
    const start_offset = address - self.mem_base;
    const end_offset = std.math.add(u64, start_offset, size) catch return;
    const first_page = start_offset / PAGE_SIZE;
    const end_page = @min((end_offset +| PAGE_SIZE - 1) / PAGE_SIZE, self.page_permissions.len);
    var page = first_page;
    while (page < end_page) : (page += 1) self.page_permissions[@intCast(page)] = permissions;
}

pub fn translateGuest(self: anytype, address: u64, size: u64, access: GuestAccess) ?u64 {
    if (!self.pointer_firewall.mayDereference(address)) return null;
    const offset = mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) orelse return null;
    const end = std.math.add(u64, offset, size) catch return null;
    if (end > self.mem.len) return null;
    if (size == 0) return offset;
    const required: u8 = switch (access) {
        .read => PAGE_READ,
        .write => PAGE_WRITE,
        .execute => PAGE_EXECUTE,
    };
    const first_page = offset / PAGE_SIZE;
    const last_page = (end - 1) / PAGE_SIZE;
    var page = first_page;
    while (page <= last_page) : (page += 1) {
        if (page >= self.page_permissions.len or self.page_permissions[@intCast(page)] & required == 0) return null;
    }
    return offset;
}

pub fn describeGuestAccess(self: anytype, address: u64, size: u64, access: GuestAccess) GuestAccessDescription {
    const sparse_mapped = self.sparse_memory.containsMapped(address, size);
    const sparse_allowed = switch (access) {
        .read => self.sparse_memory.bytesConst(address, size) != null,
        .write => false,
        .execute => false,
    };
    return .{
        .mapped = sparse_mapped or mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) != null,
        .allowed = sparse_allowed or translateGuest(self, address, size, access) != null,
        .region = self.memory_regions.find(address, size),
        .pointer_policy = self.pointer_firewall.policyAt(address),
    };
}

pub fn isExecutableAddress(self: anytype, address: u64) bool {
    return self.sparse_memory.isExecutable(address, 1) or translateGuest(self, address, 1, .execute) != null;
}

pub fn diagnosticSymbol(self: anytype, address: u64) ?exit_diagnostics.SymbolizedAddress {
    if (address == 0) return null;
    const symbol = self.metadata.nearestSymbol(address) orelse return null;
    return .{
        .address = address,
        .symbol = symbol.name,
        .symbol_offset = symbol.offset,
    };
}

/// Build a MemoryState referencing this MachOState's memory fields.
pub fn ms(self: anytype) memory_mod.MemoryState {
    return .{
        .allocator = self.allocator,
        .mem = self.mem,
        .mem_base = self.mem_base,
        .mem_size = self.mem_size,
        .heap_next = self.heap_next,
        .page_permissions = self.page_permissions,
        .sparse_memory = &self.sparse_memory,
    };
}

pub fn read8(self: anytype, vaddr: u64) u8 {
    return memory_mod.read8(&ms(self), vaddr, translateGuest(self, vaddr, 1, .read));
}

pub fn read16(self: anytype, vaddr: u64) u16 {
    return memory_mod.read16(&ms(self), vaddr, translateGuest(self, vaddr, 2, .read));
}

pub fn read32(self: anytype, vaddr: u64) u32 {
    return memory_mod.read32(&ms(self), vaddr, translateGuest(self, vaddr, 4, .read));
}

pub fn read64(self: anytype, vaddr: u64) u64 {
    return memory_mod.read64(&ms(self), vaddr, translateGuest(self, vaddr, 8, .read));
}

pub fn write8(self: anytype, vaddr: u64, val: u8) void {
    if (self.sparse_memory.bytes(vaddr, 1, true)) |bytes| {
        bytes[0] = val;
        return;
    }
    const off = translateGuest(self, vaddr, 1, .write) orelse return;
    if (off < self.mem.len) {
        self.initializer_memory.capture(self.mem, @intCast(off), 1);
        noteGuestWrite(self, vaddr, 1);
        self.mem[off] = val;
    }
}

pub fn write16(self: anytype, vaddr: u64, val: u16) void {
    if (self.sparse_memory.bytes(vaddr, 2, true)) |bytes| {
        std.mem.writeInt(u16, bytes[0..2], val, .little);
        return;
    }
    const off = translateGuest(self, vaddr, 2, .write) orelse return;
    if (off + 2 <= self.mem.len) {
        self.initializer_memory.capture(self.mem, @intCast(off), 2);
        noteGuestWrite(self, vaddr, 2);
        std.mem.writeInt(u16, self.mem[off..][0..2], val, .little);
    }
}

pub fn write32(self: anytype, vaddr: u64, val: u32) void {
    if (self.sparse_memory.bytes(vaddr, 4, true)) |bytes| {
        std.mem.writeInt(u32, bytes[0..4], val, .little);
        return;
    }
    const off = translateGuest(self, vaddr, 4, .write) orelse return;
    if (off + 4 <= self.mem.len) {
        self.initializer_memory.capture(self.mem, @intCast(off), 4);
        noteGuestWrite(self, vaddr, 4);
        std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
    }
}
pub fn write64(self: anytype, vaddr: u64, val: u64) void {
    // Suspicious write: value points into executable (code) memory — likely
    // a tree node pointer getting corrupted with function prologue bytes.
    // Values below 0x100000 (1 MB) are not plausible code pointers (Xenia
    // entry point is at 0x13fa20; MicroProfile token IDs start at 0x10000).
    // Only function_prologue values are genuinely suspicious; generic
    // code_address writes are legitimate initialization (Export struct
    // function pointer storage, hash table bucket counts, CommandVar
    // default value pointers).
    if (val >= MIN_PLAUSIBLE_CODE_POINTER and val >= self.executable_min and val < self.executable_max) {
        if (self.memory_forwarder.allocationSize(vaddr) != null or isAddressInMappedMemory(self, vaddr)) {
            if (detectFunctionProloguePtr(val)) {
                self.vtable_tracker.heap_corruption_detections +|= 1;
                const writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
                machoCapturePrint(
                    "macho-processor: suspicious allocation write: addr=0x{x} value=0x{x} (function prologue) writer=0x{x} {s}+0x{x} step={d}\n",
                    .{
                        vaddr,
                        val,
                        self.regs.rip,
                        if (writer_symbol) |s| s.name else "<unknown>",
                        if (writer_symbol) |s| s.offset else 0,
                        self.executed_steps,
                    },
                );
            }
        }
    }
    if (self.sparse_memory.bytes(vaddr, 8, true)) |bytes| {
        const prev = std.mem.readInt(u64, bytes[0..8], .little);
        self.memory_writes.record(self.allocator, vaddr, prev, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
        std.mem.writeInt(u64, bytes[0..8], val, .little);
        // Observe only after the guest write commits.  Failed translations
        // must not manufacture vptr history.
        recordAllocationWrite(self, vaddr, .bits64, val);
        return;
    }
    const off = translateGuest(self, vaddr, 8, .write) orelse return;
    if (off + 8 <= self.mem.len) {
        const prev = std.mem.readInt(u64, self.mem[off..][0..8], .little);
        self.memory_writes.record(self.allocator, vaddr, prev, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
        self.initializer_memory.capture(self.mem, @intCast(off), 8);
        noteGuestWrite(self, vaddr, 8);
        std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
        recordAllocationWrite(self, vaddr, .bits64, val);
    }
}

pub fn push(self: anytype, val: u64) void {
    self.regs.rsp -|= 8;
    if (!ensureGuestAccess(self, self.regs.rsp, 8, .write, "stack_push")) return;
    write64(self, self.regs.rsp, val);
}

pub fn pop(self: anytype) u64 {
    if (!ensureGuestAccess(self, self.regs.rsp, 8, .read, "stack_pop")) return 0;
    const val = read64(self, self.regs.rsp);
    self.regs.rsp +|= 8;
    return val;
}

pub fn readMemVal(self: anytype, addr: u64, size: Size) u64 {
    const State = @TypeOf(self.*);
    const bytes = bytesForSize(size);
    // Sparse mappings live outside the contiguous Mach-O image.  The memory
    // manager already knows how to read them, so don't require an unrelated
    // main-image offset before dispatching the read.  Writes have always
    // followed this ordering; keeping reads symmetric prevents valid mprotect
    // activations from being reported as permission faults.
    const sparse_readable = self.sparse_memory.bytesConst(addr, bytes) != null;
    const off = if (sparse_readable) null else translateGuest(self, addr, bytes, .read);
    if (!sparse_readable and off == null) {
        terminateForGuestAccess(self, addr, bytes, .read, @tagName(self.trace_entries[if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1].op));
        return 0;
    }
    const ctx: *anyopaque = @ptrCast(self);
    return memReadMemVal(&ms(self), addr, size, off, .{
        .ctx = ctx,
        .recoverVtable = struct {
            fn recover(c: *anyopaque, a: u64, suspect: u64) ?u64 {
                const st: *State = @ptrCast(@alignCast(c));
                return recoverLiveAllocationVtable(st, a, suspect);
            }
        }.recover,
        .recordAccess = struct {
            fn record(c: *anyopaque, a: u64, bytes_count: u8, v: u64) void {
                const st: *State = @ptrCast(@alignCast(c));
                const sz: Size = switch (bytes_count) {
                    1 => .bits8,
                    2 => .bits16,
                    4 => .bits32,
                    8 => .bits64,
                    else => .bits64,
                };
                recordMemoryAccess(st, a, sz, "read", v);
            }
        }.record,
    });
}

pub fn recoverLiveAllocationVtable(self: anytype, address: u64, current_value: u64) ?u64 {
    const exact_live_base = self.memory_forwarder.allocationSize(address) != null;
    const recovery = self.vtable_tracker.assessLowRead(
        address,
        current_value,
        exact_live_base,
    ) orelse return null;
    const symbol = self.metadata.nearestSymbol(recovery.value) orelse return null;
    if (!self.vtable_tracker.noteRecovery(address, recovery.generation)) return null;
    machoCapturePrint(
        "macho-processor: trusted vtable low-read recovery: object=0x{x} generation={d} allocation_size={d} observed=0x{x} restored=0x{x} vtable={s}+0x{x} established_by=0x{x}@{d} last_write=0x{x}@{d} prior_recoveries={d} thread=0x{x}\n",
        .{
            address,
            recovery.generation,
            self.memory_forwarder.allocationSize(address) orelse 0,
            current_value,
            recovery.value,
            symbol.name,
            symbol.offset,
            recovery.established_by.writer_rip,
            recovery.established_by.writer_step,
            recovery.last_write.writer_rip,
            recovery.last_write.writer_step,
            recovery.prior_recoveries,
            self.active_guest_thread,
        },
    );
    return recovery.value;
}

pub fn logLiveVtableGuardSummary(self: anytype) void {
    machoCapturePrint(
        "macho-processor: vtable runtime: low_reads_checked={d} recoveries={d} write_time_mutations={d} tracked_objects={d} establishments={d} transitions={d} rejected_candidates={d} low_clears={d} retired={d} heap_corruption_detections={d} guard_tracked={d} memory_writes={d}; recovery requires a live allocation base and strict mapped Itanium ZTV evidence\n",
        .{
            self.vtable_tracker.live_vtable_guard_checks,
            self.vtable_tracker.live_vtable_guard_recoveries,
            self.vtable_tracker.live_vtable_write_protections,
            self.vtable_tracker.trackedAllocationCount(),
            self.vtable_tracker.trusted_establishments,
            self.vtable_tracker.trusted_transitions,
            self.vtable_tracker.rejected_candidates,
            self.vtable_tracker.low_clears_observed,
            self.vtable_tracker.retired_records,
            self.vtable_tracker.heap_corruption_detections,
            self.guard_rollback.count(),
            self.memory_writes.entries.count(),
        },
    );
}

pub fn hasLiveAllocationVtableHistory(self: anytype, address: u64) bool {
    if (self.memory_forwarder.allocationSize(address) == null) return false;
    return self.vtable_tracker.hasTrustedHistory(address);
}

pub fn vtableIdentityEvidence(self: anytype, value: u64) vt.IdentityEvidence {
    var evidence = vt.IdentityEvidence{ .value = value };
    const symbol = self.metadata.nearestSymbol(value) orelse return evidence;
    evidence.symbol_name = symbol.name;
    evidence.symbol_offset = symbol.offset;

    if (value < 16) return evidence;
    const table = guestMemoryConst(self, value - 16, 24) orelse return evidence;
    evidence.header_mapped = true;
    const typeinfo = std.mem.readInt(u64, table[8..16], .little);
    evidence.typeinfo_plausible =
        typeinfo == 0 or guestMemoryConst(self, typeinfo, 1) != null;
    const first_slot = std.mem.readInt(u64, table[16..24], .little);
    evidence.first_slot_plausible =
        first_slot == 0 or isExecutableAddress(self, first_slot);
    return evidence;
}

/// Record only validated vptr identities.  Generic write provenance remains
/// in memory_writes and cannot authorize vptr recovery.
pub fn recordAllocationWrite(self: anytype, addr: u64, size: Size, val: u64) void {
    if (size != .bits64) return;
    if (addr < 0x1000 or (addr & 7) != 0) return;
    _ = self.memory_forwarder.allocationSize(addr) orelse return;
    const result = self.vtable_tracker.observeWrite(
        addr,
        vtableIdentityEvidence(self, val),
        .{
            .writer_rip = self.regs.rip,
            .writer_step = self.executed_steps,
            .writer_thread = self.active_guest_thread,
        },
    );
    const transition_count = self.vtable_tracker.trusted_transitions;
    if (result.disposition == .valid_transition and
        (transition_count <= 8 or std.math.isPowerOfTwo(transition_count)))
    {
        const previous_symbol = self.metadata.nearestSymbol(result.previous_vptr);
        const current_symbol = self.metadata.nearestSymbol(result.trusted_vptr);
        machoCapturePrint(
            "macho-processor: vtable lifecycle transition: object=0x{x} generation={d} previous=0x{x}({s}+0x{x}) current=0x{x}({s}+0x{x}) writer=0x{x} step={d} thread=0x{x}\n",
            .{
                addr,
                result.generation,
                result.previous_vptr,
                if (previous_symbol) |s| s.name else "<unknown>",
                if (previous_symbol) |s| s.offset else 0,
                result.trusted_vptr,
                if (current_symbol) |s| s.name else "<unknown>",
                if (current_symbol) |s| s.offset else 0,
                self.regs.rip,
                self.executed_steps,
                self.active_guest_thread,
            },
        );
    }
}

/// Check if a pointer value looks like x86 function prologue bytes.
/// Returns true if `value` starts with common push rbp; mov rbp, rsp patterns.
/// This indicates heap corruption where code bytes overwrote a data pointer.
/// Returns true if `addr` falls within the guest memory heap/data region
/// (between the mapped image end and the stack start).  This catches writes
/// to tree nodes and other heap allocations that aren't tracked by
/// memory_forwarder.allocationSize (which only checks allocation bases).
pub fn isAddressInMappedMemory(self: anytype, addr: u64) bool {
    const stack_start = self.mem_base + self.mem_size -| self.stack_size;
    return addr >= self.mapped_min and addr < stack_start;
}

/// Classify a writer's RIP offset within a known function to provide
/// semantic context for vtable protection logs.  For example, offset
/// 0x23 within __tree_right_rotate is the "mov [rdi+0x48], rsi" write
/// that clears a tree node's parent pointer — when the node and vtable
/// share the same allocation, this overwrites vtable[9] (offset 0x48).
pub fn classifyWriterRipOffset(name: []const u8, offset: u64) []const u8 {
    if (std.mem.indexOf(u8, name, "__tree_right_rotate") != null) {
        if (offset < 0x10) return "tree_rotate_prologue";
        if (offset < 0x30) return "tree_rotate_parent_write";
        return "tree_rotate_body";
    }
    if (std.mem.indexOf(u8, name, "__tree_left_rotate") != null) {
        if (offset < 0x10) return "tree_rotate_prologue";
        if (offset < 0x30) return "tree_rotate_parent_write";
        return "tree_rotate_body";
    }
    if (std.mem.indexOf(u8, name, "__tree_insert_node") != null) {
        if (offset < 0x10) return "tree_insert_prologue";
        return "tree_insert_body";
    }
    return "unknown";
}

/// Minimum value that could plausibly be a guest code pointer.
/// Values below this are clearly small integers (e.g. MicroProfile token
/// IDs starting at 0x10000). Xenia's entry point is at 0x13fa20 (~1.3 MB).
const MIN_PLAUSIBLE_CODE_POINTER: u64 = 0x100000;

pub fn detectFunctionProloguePtr(value: u64) bool {
    if (value & 0xFF != 0x55) return false; // must start with push rbp
    const byte1 = @as(u8, @truncate((value >> 8) & 0xFF));
    // 55 48 89 e5 (push rbp; mov rbp, rsp)
    // 55 48 8b ec (push rbp; mov rbp, rsp)
    // 55 48 81 ec (push rbp; sub rsp, imm32)
    if (byte1 == 0x48) {
        const byte2 = @as(u8, @truncate((value >> 16) & 0xFF));
        return byte2 == 0x89 or byte2 == 0x8b or byte2 == 0x81;
    }
    // 55 53 48 8b ec (push rbp; push rbx; mov rbp, rsp)
    if (byte1 == 0x53) {
        const byte2 = @as(u8, @truncate((value >> 16) & 0xFF));
        return byte2 == 0x48;
    }
    return false;
}

/// Dump heap corruption diagnostics when a pointer value looks like
/// x86 function prologue bytes rather than a valid data address.
/// `value` is the corrupted pointer value (e.g., from rax register).
/// `fault_rip` is the instruction that attempted to dereference it.
pub fn dumpHeapCorruptionDiagnostics(self: anytype, value: u64, fault_rip: u64) void {
    if (value < 0x1000) return;
    if (!detectFunctionProloguePtr(value)) return;
    self.vtable_tracker.heap_corruption_detections +|= 1;
    machoCapturePrint(
        "macho-processor: heap corruption detected: value=0x{x} matches function prologue pattern (55 48 89 e5 ...) fault_rip=0x{x}\n",
        .{ value, fault_rip },
    );
    // We can't infer the corrupted storage address from the value alone,
    // so report the faulting symbol and leave storage provenance to the
    // generic memory-write tracker.
    const writer_symbol = self.metadata.nearestSymbol(fault_rip);
    if (writer_symbol) |s| {
        machoCapturePrint(
            "macho-processor:   fault context: {s}+0x{x}\n",
            .{ s.name, s.offset },
        );
    }
}

pub fn timerQueueWatchWrite(self: anytype, addr: u64, size: Size, val: u64) void {
    if (!self.timer_queue_watch.active) return;
    if (self.timer_queue_watch.logged_writes >= 32) {
        self.timer_queue_watch.active = false;
        return;
    }
    if (addr != self.timer_queue_watch.state_addr) return;
    self.timer_queue_watch.logged_writes +|= 1;
    const state_name = guest_assertion_recovery.timerQueueStateName(@as(u8, @truncate(val)));
    const symbol = self.metadata.nearestSymbol(self.regs.rip);
    machoCapturePrint(
        "  timer queue state write #{d}: addr=0x{x} size={s} val={s}({d}) rip=0x{x} thread=0x{x} symbol={s}\n",
        .{
            self.timer_queue_watch.logged_writes,
            addr,
            @tagName(size),
            state_name,
            @as(u8, @truncate(val)),
            self.regs.rip,
            self.active_guest_thread,
            if (symbol) |s| s.name else "<unknown>",
        },
    );
}

pub fn writeMemVal(self: anytype, addr: u64, size: Size, val: u64) void {
    const bytes = bytesForSize(size);
    if (self.sparse_memory.bytes(addr, bytes, true)) |storage| {
        recordMemoryAccess(self, addr, size, "write", val);
        if (size == .bits64) {
            self.memory_writes.record(
                self.allocator,
                addr,
                std.mem.readInt(u64, storage[0..8], .little),
                val,
                self.regs.rip,
                self.executed_steps,
                self.active_guest_thread,
            );
        }
        switch (size) {
            .bits8 => storage[0] = @truncate(val),
            .bits16 => std.mem.writeInt(u16, storage[0..2], @truncate(val), .little),
            .bits32 => std.mem.writeInt(u32, storage[0..4], @truncate(val), .little),
            .bits64 => std.mem.writeInt(u64, storage[0..8], val, .little),
        }
        recordAllocationWrite(self, addr, size, val);
        // Suspicious write: 64-bit value pointing into executable (code) segment
        // written to any heap/data memory — tree node structural corruption pattern.
        // Values below 0x100000 are not plausible code pointers (e.g. MicroProfile token IDs).
        // Only function_prologue values are genuinely suspicious; generic
        // code_address writes are legitimate initialization (Export struct
        // function pointer storage, hash table bucket counts, CommandVar
        // default value pointers).
        if (size == .bits64 and val >= MIN_PLAUSIBLE_CODE_POINTER and val >= self.executable_min and val < self.executable_max) {
            if (self.memory_forwarder.allocationSize(addr) != null or isAddressInMappedMemory(self, addr)) {
                if (detectFunctionProloguePtr(val)) {
                    self.vtable_tracker.heap_corruption_detections +|= 1;
                    const writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
                    machoCapturePrint(
                        "macho-processor: suspicious allocation write (writeMemVal sparse): addr=0x{x} value=0x{x} (function prologue) writer=0x{x} {s}+0x{x} step={d}\n",
                        .{
                            addr,
                            val,
                            self.regs.rip,
                            if (writer_symbol) |s| s.name else "<unknown>",
                            if (writer_symbol) |s| s.offset else 0,
                            self.executed_steps,
                        },
                    );
                }
            }
        }
        timerQueueWatchWrite(self, addr, size, val);
        return;
    }
    const off = translateGuest(self, addr, bytes, .write) orelse {
        if (deferInitializerRuntimeDependency(self, addr, size)) return;
        terminateForGuestAccess(self, addr, bytes, .write, @tagName(self.trace_entries[if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1].op));
        return;
    };
    recordMemoryAccess(self, addr, size, "write", val);
    if (size == .bits64) {
        self.memory_writes.record(
            self.allocator,
            addr,
            std.mem.readInt(u64, self.mem[off..][0..8], .little),
            val,
            self.regs.rip,
            self.executed_steps,
            self.active_guest_thread,
        );
    }
    self.initializer_memory.capture(self.mem, @intCast(off), bytes);
    noteGuestWrite(self, addr, bytes);
    switch (size) {
        .bits8 => self.mem[off] = @truncate(val),
        .bits16 => std.mem.writeInt(u16, self.mem[off..][0..2], @truncate(val), .little),
        .bits32 => std.mem.writeInt(u32, self.mem[off..][0..4], @truncate(val), .little),
        .bits64 => std.mem.writeInt(u64, self.mem[off..][0..8], val, .little),
    }
    recordAllocationWrite(self, addr, size, val);
    // Suspicious write: 64-bit value pointing into executable (code) segment
    // written to any heap/data memory — tree node structural corruption pattern.
    // Values below 0x100000 are not plausible code pointers (e.g. MicroProfile token IDs).
    // Only function_prologue values are genuinely suspicious; generic
    // code_address writes are legitimate initialization (Export struct
    // function pointer storage, hash table bucket counts, CommandVar
    // default value pointers).
    if (size == .bits64 and val >= 0x100000 and val >= self.executable_min and val < self.executable_max) {
        if (self.memory_forwarder.allocationSize(addr) != null or isAddressInMappedMemory(self, addr)) {
            if (detectFunctionProloguePtr(val)) {
                self.vtable_tracker.heap_corruption_detections +|= 1;
                const writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
                machoCapturePrint(
                    "macho-processor: suspicious allocation write (writeMemVal reg): addr=0x{x} value=0x{x} (function prologue) writer=0x{x} {s}+0x{x} step={d}\n",
                    .{
                        addr,
                        val,
                        self.regs.rip,
                        if (writer_symbol) |s| s.name else "<unknown>",
                        if (writer_symbol) |s| s.offset else 0,
                        self.executed_steps,
                    },
                );
            }
        }
    }
    timerQueueWatchWrite(self, addr, size, val);
}

pub fn deferInitializerRuntimeDependency(self: anytype, address: u64, size: Size) bool {
    if (self.initializer_checkpoint == null or address >= 0x1000 or size != .bits64) return false;

    const trace_count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
    if (trace_count == 0) return false;
    const latest_index = if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1;
    const fault_entry = self.trace_entries[latest_index];
    if (fault_entry.rip != self.regs.rip or fault_entry.thread_handle != self.active_guest_thread) return false;
    const fault = decodeTraceInstruction(self, fault_entry) orelse return false;
    if (fault.op != .mov_mem64_reg64 or !fault.sib_has_base) return false;
    const base_register = fault.sib_base_reg;
    if (traceRegisterValue(fault_entry, base_register) != address) return false;

    var after = address;
    var same_thread_distance: usize = 0;
    var reverse_index = trace_count;
    while (reverse_index != 0) {
        reverse_index -= 1;
        const index = if (self.trace_filled)
            (self.trace_index + reverse_index) % TRACE_BUFFER_LEN
        else
            reverse_index;
        const entry = self.trace_entries[index];
        if (entry.thread_handle != self.active_guest_thread) continue;
        same_thread_distance += 1;
        const before = traceRegisterValue(entry, base_register);
        if (before == after) {
            after = before;
            continue;
        }

        const producer = decodeTraceInstruction(self, entry) orelse return false;
        const producer_is_pointer_load = producer.op == .mov_reg64_mem64;
        const source_address = producer.addr;
        const source_offset = translateGuest(self, source_address, @sizeOf(u64), .read) orelse return false;
        const source_value = std.mem.readInt(u64, self.mem[source_offset..][0..8], .little);
        const region = self.memory_regions.find(source_address, @sizeOf(u64)) orelse return false;
        const source_class: initializer_dependency.SourceClass = switch (region.kind) {
            .macho_data => .writable_image_data,
            .import_got => .import_pointer,
            else => .other,
        };
        const decision = initializer_dependency.classify(.{
            .initializer_active = true,
            .fault_address = address,
            .access_width = bytesForSize(size),
            .store_uses_base_register = true,
            .producer_is_pointer_load = producer_is_pointer_load,
            .producer_destination_matches_base = producer.dst_reg == base_register,
            .producer_source_address = source_address,
            .producer_source_value = source_value,
            .producer_distance = same_thread_distance,
            .source_readable = region.permissions.read,
            .source_writable = region.permissions.write,
            .source_class = source_class,
        });
        if (decision != .defer_and_retry) return false;

        self.initializer_abort_requested = true;
        self.initializer_abort_reason = .runtime_dependency;
        const section = self.metadata.sectionAtAddress(source_address);
        const initializer = self.initializer_resolver.current();
        const source_symbol = self.metadata.nearestSymbol(source_address);
        const source_symbol_name = if (source_symbol) |resolved|
            if (resolved.offset == 0) resolved.name else "<no-exact-symbol>"
        else
            "<unknown>";
        if (initializer == null or initializer.?.attempts == 1) {
            machoCapturePrint(
                "macho-processor: initializer dependency deferred: initializer={d}/{d} attempt={d} fault_rip=0x{x} null_store=0x{x} base={s} producer_rip=0x{x} source_slot=0x{x} source_symbol={s} source_region={s}/{s} source_value=0x{x} distance={d}; transaction will roll back before retry\n",
                .{
                    if (initializer) |record| record.index + 1 else 0,
                    self.metadata.initializer_addresses.len,
                    if (initializer) |record| record.attempts else 0,
                    self.regs.rip,
                    address,
                    @tagName(base_register),
                    entry.rip,
                    source_address,
                    source_symbol_name,
                    @tagName(region.kind),
                    if (section) |resolved| resolved.name else region.owner,
                    source_value,
                    same_thread_distance,
                },
            );
        }
        return true;
    }
    return false;
}

pub fn decodeTraceInstruction(self: anytype, entry: TraceEntry) ?DecodedInsn {
    const instruction_bytes: []const u8 = if (self.sparse_memory.executableBytesConst(entry.rip, 16)) |sparse_code|
        sparse_code
    else blk: {
        const offset = translateGuest(self, entry.rip, 1, .execute) orelse return null;
        break :blk self.mem[offset..];
    };
    var decoded = decodeInsn(instruction_bytes);
    const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
    if (decoded.sib_has_index) {
        const index_value = traceRegisterValue(entry, decoded.sib_index_reg);
        decoded.addr +%= (if (address_size == .bits32) @as(u32, @truncate(index_value)) else index_value) << @as(u6, decoded.sib_scale);
    }
    if (decoded.sib_has_base) {
        const base_value = traceRegisterValue(entry, decoded.sib_base_reg);
        decoded.addr +%= if (address_size == .bits32) @as(u32, @truncate(base_value)) else base_value;
    }
    if (decoded.rip_relative) decoded.addr +%= entry.rip + decoded.len;
    if (address_size == .bits32) decoded.addr = @as(u32, @truncate(decoded.addr));
    return decoded;
}

pub fn ensureGuestAccess(self: anytype, address: u64, bytes: u8, access: GuestAccess, instruction: []const u8) bool {
    if (access == .read and self.sparse_memory.bytesConst(address, bytes) != null) return true;
    if (access == .write and self.sparse_memory.bytes(address, bytes, true) != null) return true;
    if (access == .execute and self.sparse_memory.isExecutable(address, bytes)) return true;
    if (translateGuest(self, address, bytes, access) != null) return true;
    terminateForGuestAccess(self, address, bytes, access, instruction);
    return false;
}

pub fn terminateForGuestAccess(self: anytype, address: u64, bytes: u8, access: GuestAccess, instruction: []const u8) void {
    if (self.terminal_memory_failure != null) return;
    if (tryQuarantineOpaqueDestructor(self, address)) return;
    const description = describeGuestAccess(self, address, bytes, access);
    if (access != .execute and description.mapped and !description.allowed) {
        const instruction_len = currentGuestInstructionLength(self);
        if (self.deliverGuestSignal(GUEST_SIGSEGV, self.regs.rip, instruction_len, address, access)) {
            machoCapturePrint(
                "macho-processor: mapped guest protection fault routed to SIGSEGV handler: rip=0x{x} address=0x{x} bytes={d} access={s} instruction={s}\n",
                .{ self.regs.rip, address, bytes, @tagName(access), instruction },
            );
            return;
        }
    }
    if (!self.toml_fault_diagnostics_dumped) {
        if (self.metadata.nearestSymbol(self.regs.rip)) |symbol| {
            const toml_symbol = std.mem.indexOf(u8, symbol.name, "toml") != null;
            const patch_db_symbol = std.mem.indexOf(u8, symbol.name, "PatchDB") != null or
                std.mem.indexOf(u8, symbol.name, "patcher") != null;
            if (toml_symbol or patch_db_symbol) {
                self.toml_fault_diagnostics_dumped = true;
                machoCapturePrint(
                    "macho-processor: TOML/PatchDB guest access fault: rip=0x{x} symbol={s}+0x{x} address=0x{x} bytes={d} access={s}; dumping stream and schema state before termination\n",
                    .{ self.regs.rip, symbol.name, symbol.offset, address, bytes, @tagName(access) },
                );
                self.libcxx_streams.dumpPatchTomlDiagnostics("TOML/PatchDB guest memory fault");
                if (patch_db_symbol and address < 0x1000) {
                    self.libcxx_streams.dumpPatchPostParseDiagnosis("near-null access in PatchDB::ReadPatchFile");
                }
            }
        }
    }
    if (address < 0x1000) dumpTerminalAddressProvenance(self, address);
    const policy = description.pointer_policy;
    const fault: []const u8 = if (policy != null and !policy.?.may_dereference)
        "opaque_identity_dereference"
    else if (description.mapped)
        "permission_denied"
    else
        "unmapped";
    if (self.summary_output_fd >= 0) {
        var summary_buffer: [1024]u8 = undefined;
        const symbol = self.metadata.nearestSymbol(self.regs.rip);
        const region = description.region;
        const summary_line = std.fmt.bufPrint(
            &summary_buffer,
            "step={d} event=memory_fault rip=0x{x} symbol={s}+0x{x} instruction={s} access={s} address=0x{x} bytes={d} fault={s} mapped={} runtime_allowed={} region={s} owner={s} permissions={c}{c}{c}\n",
            .{
                self.executed_steps,
                self.regs.rip,
                if (symbol) |resolved| resolved.name else "<unknown>",
                if (symbol) |resolved| resolved.offset else 0,
                instruction,
                @tagName(access),
                address,
                bytes,
                fault,
                description.mapped,
                description.allowed,
                if (region) |resolved| @tagName(resolved.kind) else "none",
                if (region) |resolved| resolved.owner else "none",
                @as(u8, if (region != null and region.?.permissions.read) 'r' else '-'),
                @as(u8, if (region != null and region.?.permissions.write) 'w' else '-'),
                @as(u8, if (region != null and region.?.permissions.execute) 'x' else '-'),
            },
        ) catch "";
        _ = guest_log.hostWriteFdAll(self.summary_output_fd, summary_line);
    }
    self.terminal_memory_failure = .{
        .instruction_address = self.regs.rip,
        .instruction = instruction,
        .address = address,
        .bytes = bytes,
        .access = @tagName(access),
        .fault = fault,
        .mapped = description.mapped,
    };
    // Check for heap corruption when the access involves reading a pointer
    // that looks like function prologue bytes — a common symptom of buffer
    // overflow or use-after-free where code bytes overwrote data pointers.
    if (bytes == 8 or bytes == 4) {
        // The offending value may be in rax (if this was a dereference of
        // a computed address), or we check the fault address itself.
        dumpHeapCorruptionDiagnostics(self, self.regs.rax, self.regs.rip);
    }
    dumpStepTraceBuffer(self);
    self.dumpGtkBootstrapTrace();
    self.dumpMemInitTrace();
    self.dumpGtkHeartbeatTrace();
    self.dumpUiHandoffTrace();
    self.faulted = true;
    self.terminated = true;
    self.exit_code = 127;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.memory_access_violation);
}

pub fn dumpStepTraceBuffer(self: anytype) void {
    if (!self.step_trace_filled and self.step_trace_index == 0) return;
    machoCapturePrint("macho-processor: step trace buffer (most recent {d} entries):\n", .{
        if (self.step_trace_filled) 5 else @as(usize, @intCast(self.step_trace_index)),
    });
    const count: usize = if (self.step_trace_filled) 5 else @intCast(self.step_trace_index);
    const start: usize = if (self.step_trace_filled) self.step_trace_index else 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const idx = (start + i) % 5;
        const e = &self.step_trace_entries[idx];
        const symbol = self.metadata.nearestSymbol(e.rip);
        machoCapturePrint(
            "  step={d} rip=0x{x} at {s}+0x{x}\n",
            .{
                e.step,                                  e.rip,
                if (symbol) |s| s.name else "<unknown>", if (symbol) |s| s.offset else 0,
            },
        );
    }
}

pub fn currentGuestInstructionLength(self: anytype) u8 {
    const latest_index = if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1;
    const latest = self.trace_entries[latest_index];
    if (latest.rip == self.regs.rip and latest.len != 0) return latest.len;
    const instruction_bytes: []const u8 = if (self.sparse_memory.executableBytesConst(self.regs.rip, 16)) |sparse_code|
        sparse_code
    else blk: {
        const offset = translateGuest(self, self.regs.rip, 1, .execute) orelse return 1;
        break :blk self.mem[offset..];
    };
    const decoded = decodeInsn(instruction_bytes);
    return if (decoded.len != 0) decoded.len else 1;
}

pub fn tryQuarantineOpaqueDestructor(self: anytype, address: u64) bool {
    const policy = self.pointer_firewall.policyAt(address) orelse return false;
    if (policy.kind != .opaque_identity or policy.may_dereference) return false;
    const address_is_this = self.regs.rdi == address or self.regs.rsi == address;
    const symbol = self.metadata.nearestSymbol(self.regs.rip) orelse return false;
    if (!opaque_lifetime_recovery.shouldQuarantine(symbol.name, true, address_is_this)) return false;

    var return_address: u64 = 0;
    var restored_via: []const u8 = "";
    if (guestMemoryConst(self, self.regs.rsp, 8) != null) {
        const candidate = read64(self, self.regs.rsp);
        if (isExecutableAddress(self, candidate)) {
            return_address = candidate;
            self.regs.rsp +|= 8;
            restored_via = "rsp";
        }
    }
    if (return_address == 0 and self.regs.rbp != 0 and guestMemoryConst(self, self.regs.rbp, 16) != null) {
        const candidate = read64(self, self.regs.rbp + 8);
        if (isExecutableAddress(self, candidate)) {
            const previous_rbp = read64(self, self.regs.rbp);
            self.regs.rsp = self.regs.rbp +| 16;
            self.regs.rbp = previous_rbp;
            return_address = candidate;
            restored_via = "rbp";
        }
    }
    if (return_address == 0) return false;

    self.regs.rip = return_address;
    self.opaque_destructor_quarantines +|= 1;
    machoCapturePrint(
        "macho-processor: opaque lifetime quarantine #{d}: destructor={s} this=0x{x} owner={s} restored_caller=0x{x} via={s}; skipped invalid guest cleanup without dereferencing API identity\n",
        .{ self.opaque_destructor_quarantines, symbol.name, address, policy.owner, return_address, restored_via },
    );
    return true;
}

pub fn dumpTerminalAddressProvenance(self: anytype, effective_address: u64) void {
    near_null_causality.dumpTerminal(self, effective_address);
}

pub fn dumpNearNullProducerSlot(self: anytype) void {
    const count: usize = if (self.memory_trace_filled) MEMORY_TRACE_BUFFER_LEN else self.memory_trace_index;
    var reverse_index = count;
    while (reverse_index != 0) {
        reverse_index -= 1;
        const index = if (self.memory_trace_filled)
            (self.memory_trace_index + reverse_index) % MEMORY_TRACE_BUFFER_LEN
        else
            reverse_index;
        const access = self.memory_trace_entries[index];
        if (!std.mem.eql(u8, access.access, "read") or access.value != 0 or
            access.bytes != @sizeOf(u64) or access.address < 0x1000 or
            access.instruction_address == self.regs.rip)
        {
            continue;
        }

        const reader = self.metadata.nearestSymbol(access.instruction_address);
        machoCapturePrint(
            "macho-processor: near-null producer slot: loaded_zero_from=0x{x} reader=0x{x} {s}+0x{x} op={s}\n",
            .{
                access.address,
                access.instruction_address,
                if (reader) |symbol| symbol.name else "<unknown>",
                if (reader) |symbol| symbol.offset else 0,
                access.instruction,
            },
        );
        if (self.memory_writes.lookup(access.address)) |writer| {
            const symbol = self.metadata.nearestSymbol(writer.instruction_address);
            machoCapturePrint(
                "macho-processor: near-null producer last writer: slot=0x{x} previous=0x{x} value=0x{x} writer=0x{x} {s}+0x{x} step={d} age_steps={d} thread=0x{x}\n",
                .{
                    writer.address,
                    writer.previous_value,
                    writer.value,
                    writer.instruction_address,
                    if (symbol) |resolved| resolved.name else "<unknown>",
                    if (symbol) |resolved| resolved.offset else 0,
                    writer.step,
                    self.executed_steps -| writer.step,
                    writer.thread,
                },
            );
        } else {
            machoCapturePrint(
                "macho-processor: near-null producer last writer: slot=0x{x} not retained (tracked_slots={d} dropped_slots={d})\n",
                .{ access.address, self.memory_writes.entries.count(), self.memory_writes.dropped_slots },
            );
        }
        return;
    }
}

pub fn dumpRegisterTransition(self: anytype, register: RegId, terminal_value: u64, role: []const u8) void {
    const count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
    const fault_thread = self.active_guest_thread;
    var after = terminal_value;
    var same_thread_entries: usize = 0;
    var excluded_entries: usize = 0;
    var reverse_index = count;
    while (reverse_index != 0) {
        reverse_index -= 1;
        const index = if (self.trace_filled)
            (self.trace_index + reverse_index) % TRACE_BUFFER_LEN
        else
            reverse_index;
        const entry = self.trace_entries[index];
        if (entry.thread_handle != fault_thread) {
            excluded_entries += 1;
            continue;
        }
        same_thread_entries += 1;
        const before = traceRegisterValue(entry, register);
        if (before != after) {
            const symbol = self.metadata.nearestSymbol(entry.rip);
            machoCapturePrint(
                "macho-processor: near-null {s} register transition: thread=0x{x} register={s} before=0x{x} after=0x{x} caused_by=0x{x} {s}+0x{x} op={s} same_thread_distance={d} cross_thread_entries_excluded={d}\n",
                .{ role, fault_thread, @tagName(register), before, after, entry.rip, if (symbol) |resolved| resolved.name else "<unknown>", if (symbol) |resolved| resolved.offset else 0, @tagName(entry.op), same_thread_entries, excluded_entries },
            );
            return;
        }
        after = before;
    }
    machoCapturePrint(
        "macho-processor: near-null {s} register transition: thread=0x{x} register={s} remained 0x{x} throughout {d} retained same-thread instructions; excluded {d} cross-thread entries\n",
        .{ role, fault_thread, @tagName(register), terminal_value, same_thread_entries, excluded_entries },
    );
}

pub fn traceRegisterValue(entry: TraceEntry, register: RegId) u64 {
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

pub fn recordMemoryAccess(self: anytype, address: u64, size: Size, access: []const u8, value: u64) void {
    const bytes = bytesForSize(size);
    const offset = translateGuest(self, address, bytes, if (std.mem.eql(u8, access, "write")) .write else .read);
    const backed = if (offset) |off| off + bytes <= self.mem.len else false;
    const trace_count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
    const instruction = if (trace_count == 0)
        "<runtime>"
    else blk: {
        const latest_index = if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1;
        break :blk @tagName(self.trace_entries[latest_index].op);
    };
    // Check for near-null or negative addresses (high bit set in 64-bit, or very small positive addresses)
    const near_null = (address & 0x8000_0000_0000_0000) != 0 or address < 0x1000;
    self.memory_trace_entries[self.memory_trace_index] = .{
        .instruction_address = self.regs.rip,
        .instruction = instruction,
        .address = address,
        .bytes = bytes,
        .access = access,
        .value = value,
        .backed = backed,
        .near_null = near_null,
    };
    self.memory_trace_index = (self.memory_trace_index + 1) % MEMORY_TRACE_BUFFER_LEN;
    if (self.memory_trace_index == 0) self.memory_trace_filled = true;
}

pub fn readMem128(self: anytype, addr: u64) [16]u8 {
    var value = [_]u8{0} ** 16;
    if (self.sparse_memory.bytesConst(addr, 16)) |storage| {
        @memcpy(value[0..], storage[0..16]);
        return value;
    }
    const off = translateGuest(self, addr, 16, .read) orelse {
        terminateForGuestAccess(self, addr, 16, .read, "vector_read");
        return value;
    };
    @memcpy(value[0..], self.mem[off..][0..16]);
    return value;
}

pub fn writeMem128(self: anytype, addr: u64, value: [16]u8) void {
    if (self.sparse_memory.bytes(addr, 16, true)) |storage| {
        @memcpy(storage[0..16], value[0..]);
        return;
    }
    const off = translateGuest(self, addr, 16, .write) orelse {
        terminateForGuestAccess(self, addr, 16, .write, "vector_write");
        return;
    };
    self.initializer_memory.capture(self.mem, @intCast(off), 16);
    noteGuestWrite(self, addr, 16);
    @memcpy(self.mem[off..][0..16], value[0..]);
}

pub fn guestMemory(self: anytype, addr: u64, count: u64) ?[]u8 {
    if (self.sparse_memory.bytes(addr, count, true)) |bytes| return bytes;
    if (count > std.math.maxInt(usize)) return null;
    const off = translateGuest(self, addr, count, .write) orelse return null;
    const off_usize: usize = @intCast(off);
    const count_usize: usize = @intCast(count);
    if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
    self.initializer_memory.capture(self.mem, off_usize, count_usize);
    noteGuestWrite(self, addr, count);
    return self.mem[off_usize .. off_usize + count_usize];
}

pub fn noteGuestWrite(self: anytype, address: u64, count: u64) void {
    if (count == 0 or self.executable_min == std.math.maxInt(u64)) return;
    const end = address +| count;
    if (address < self.executable_max and end > self.executable_min) {
        self.code_generation +%= 1;
        if (self.code_generation == 0) self.code_generation = 1;
    }
}

pub fn guestMemoryConst(self: anytype, addr: u64, count: u64) ?[]const u8 {
    if (self.sparse_memory.bytesConst(addr, count)) |bytes| return bytes;
    if (count > std.math.maxInt(usize)) return null;
    const off = translateGuest(self, addr, count, .read) orelse return null;
    const off_usize: usize = @intCast(off);
    const count_usize: usize = @intCast(count);
    if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
    return self.mem[off_usize .. off_usize + count_usize];
}

pub fn guestAlloc(self: anytype, requested_size: u64, alignment: u64) ?u64 {
    const size = @max(requested_size, 1);
    const mask = alignment - 1;
    const start = (self.heap_next + mask) & ~mask;
    const end = std.math.add(u64, start, size) catch return null;
    const stack_floor = self.mem_base + self.mem_size -| self.stack_size;
    if (end > stack_floor) return null;
    const storage = guestMemory(self, start, size) orelse return null;
    @memset(storage, 0);
    self.heap_next = end;
    _ = self.memory_regions.register(start, size, .{}, .guest_heap, "guestAlloc", self.regs.rip);
    _ = self.pointer_firewall.register(start, size, .{ .kind = .owned_guest, .may_dereference = true, .owner = "guestAlloc" });
    return start;
}

pub fn registerSyntheticRegion(self: anytype, address: u64, size: u64, kind: memory_provenance.RegionKind, owner: []const u8, policy: pointer_firewall.Policy) void {
    const permissions: memory_provenance.Permissions = switch (kind) {
        .synthetic_vtable, .synthetic_typeinfo => .{ .write = false },
        else => .{},
    };
    _ = self.memory_regions.register(address, size, permissions, kind, owner, self.regs.rip);
    _ = self.pointer_firewall.register(address, size, policy);
}

pub fn registerOpaqueHandle(self: anytype, address: u64, owner: []const u8) void {
    _ = self.memory_regions.register(address, 1, .{ .read = false, .write = false }, .objc_handle, owner, self.regs.rip);
    _ = self.pointer_firewall.register(address, 1, .{ .kind = .opaque_identity, .may_dereference = false, .owner = owner });
}

pub fn registerOpaqueApiHandle(self: anytype, address: u64, owner: []const u8) void {
    _ = self.memory_regions.register(address, 1, .{ .read = false, .write = false }, .synthetic_handle, owner, self.regs.rip);
    _ = self.pointer_firewall.register(address, 1, .{ .kind = .opaque_identity, .may_dereference = false, .owner = owner });
}

pub fn registerSyntheticThunk(self: anytype, address: u64, size: u64, owner: []const u8) void {
    _ = self.memory_regions.register(address, size, .{ .read = false, .write = false, .execute = true }, .synthetic_thunk, owner, self.regs.rip);
    _ = self.pointer_firewall.register(address, size, .{ .kind = .opaque_identity, .may_dereference = false, .may_execute = true, .owner = owner });
}

pub fn guestHeapAllocate(self: anytype, size: u64, alignment: u64) ?u64 {
    return self.memory_forwarder.allocate(self, size, alignment);
}

pub fn guestHeapRelease(self: anytype, address: u64) void {
    self.memory_forwarder.release(address);
    self.vtable_tracker.forgetAddress(address);
}

pub fn guestHeapContains(self: anytype, address: u64) bool {
    return self.memory_forwarder.allocationSize(address) != null;
}

pub fn forgetMemoryWriteProvenance(self: anytype, address: u64) void {
    self.memory_writes.forget(address);
    // Allocation start/reuse is a hard lifecycle boundary.  Retire any
    // trusted vptr belonging to the former occupant before the new
    // allocation becomes visible.
    self.vtable_tracker.forgetAddress(address);
}

pub fn guestMapFile(self: anytype, address: u64, length: u64, prot: u32, flags: u32, host_fd: std.posix.fd_t, offset: u64) bool {
    const map_fixed: u32 = 0x0010;
    const mapped = if (flags & map_fixed != 0)
        self.sparse_memory.mapFixed(address, length, prot, flags, host_fd, offset)
    else
        self.sparse_memory.mapFile(address, length, prot, flags, host_fd, offset);
    if (!mapped) return false;
    _ = self.memory_regions.register(address, length, .{
        .read = prot & 1 != 0,
        .write = prot & 2 != 0,
        .execute = prot & 4 != 0,
    }, .guest_mmap, "sparse 64K guest mmap", self.regs.rip);
    _ = self.pointer_firewall.register(address, length, .{ .kind = .guest_backed, .may_dereference = true, .may_execute = prot & 4 != 0, .owner = "sparse 64K guest mmap" });
    return true;
}

pub fn guestMapAnywhereWithBacking(self: anytype, length: u64, prot: u32, flags: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
    const address = self.sparse_memory.mapAnywhereWithBacking(length, prot, flags, host_fd, offset) orelse return null;
    const effective_length = sparse_virtual_memory.pageRoundedLength(length) orelse return null;
    _ = self.memory_regions.register(address, effective_length, .{
        .read = prot & 1 != 0,
        .write = prot & 2 != 0,
        .execute = prot & 4 != 0,
    }, .guest_mmap, "OS-selected sparse guest mmap", self.regs.rip);
    _ = self.pointer_firewall.register(address, length, .{
        .kind = .guest_backed,
        .may_dereference = true,
        .may_execute = prot & 4 != 0,
        .owner = "OS-selected sparse guest mmap",
    });
    return address;
}

pub fn guestMapBackendWithBacking(self: anytype, length: u64, prot: u32, flags: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
    const backend_indirection_size: u64 = 0x1FFF_FFFF;
    const backend_code_size: u64 = 0x0FFF_FFFF;
    const executable = prot & 4 != 0;
    const preferred_base: ?u64 = if (!executable and length == backend_indirection_size)
        0x8000_0000
    else if (executable and length == backend_code_size)
        0xA000_0000
    else
        null;
    const maximum_end: ?u64 = if (preferred_base != null) 0x1_0000_0000 else null;
    const address = self.sparse_memory.mapAnywhereWithHintAndBacking(
        length,
        prot,
        flags,
        host_fd,
        offset,
        preferred_base,
        maximum_end,
    ) orelse return null;
    const effective_length = sparse_virtual_memory.pageRoundedLength(length) orelse return null;
    _ = self.memory_regions.register(address, effective_length, .{
        .read = prot & 1 != 0,
        .write = prot & 2 != 0,
        .execute = prot & 4 != 0,
    }, .guest_mmap, "low-window backend sparse mmap", self.regs.rip);
    _ = self.pointer_firewall.register(address, effective_length, .{
        .kind = .guest_backed,
        .may_dereference = true,
        .may_execute = prot & 4 != 0,
        .owner = "low-window backend sparse mmap",
    });
    machoCapturePrint(
        "macho-processor: x64 backend placement contract: requested_length={d} effective_length={d} preferred_base=0x{x} result=0x{x} result_end=0x{x} executable={} below_4g={} pointer_truncation_safe={}\n",
        .{ length, effective_length, preferred_base orelse 0, address, address +| effective_length, executable, address +| effective_length <= 0x1_0000_0000, !executable or address < 0x1_0000_0000 },
    );
    return address;
}

pub fn guestReserveAddressSpace(self: anytype, length: u64) ?u64 {
    const anon_private: u32 = 0x1000 | 0x2;
    return guestReserveAddressSpaceWithBacking(self, length, anon_private, -1, 0);
}

pub fn guestReserveAddressSpaceWithBacking(self: anytype, length: u64, flags: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
    const address = self.sparse_memory.reserveAnywhereWithBacking(length, flags, host_fd, offset) orelse return null;
    _ = self.memory_regions.register(address, length, .{ .read = false, .write = false }, .guest_mmap, "sparse guest address-space reservation", self.regs.rip);
    _ = self.pointer_firewall.register(address, length, .{ .kind = .guest_backed, .may_dereference = false, .owner = "sparse guest address-space reservation" });
    return address;
}

pub fn guestUnmapFile(self: anytype, address: u64, length: u64) bool {
    if (!self.sparse_memory.unmap(address, length)) return false;
    const effective_length = sparse_virtual_memory.pageRoundedLength(length) orelse return false;
    _ = self.memory_regions.register(
        address,
        effective_length,
        .{ .read = false, .write = false, .execute = false },
        .guest_unmapped,
        "sparse guest munmap",
        self.regs.rip,
    );
    _ = self.pointer_firewall.register(address, effective_length, .{
        .kind = .guest_backed,
        .may_dereference = false,
        .may_execute = false,
        .owner = "sparse guest munmap",
    });
    return true;
}

pub fn guestProtectSparseMemory(self: anytype, address: u64, length: u64, prot: u32) bool {
    if (!self.sparse_memory.protect(address, length, prot)) return false;
    const effective_length = sparse_virtual_memory.pageRoundedLength(length) orelse return false;
    _ = self.memory_regions.register(address, effective_length, .{
        .read = prot & 1 != 0,
        .write = prot & 2 != 0,
        .execute = prot & 4 != 0,
    }, .guest_mmap, "sparse guest mprotect", self.regs.rip);
    _ = self.pointer_firewall.register(address, effective_length, .{
        .kind = .guest_backed,
        // The firewall answers whether this is backed guest address space;
        // the region/page permissions above decide the specific access kind.
        .may_dereference = prot != 0,
        .may_execute = prot & 4 != 0,
        .owner = "sparse guest mprotect",
    });
    return true;
}

pub fn renderProcSelfMaps(self: anytype, output: []u8) []const u8 {
    return self.sparse_memory.renderProcSelfMaps(output);
}

pub fn guestCString(self: anytype, addr: u64, max_len: usize) ?[]const u8 {
    if (addr == 0) return null;
    const off = translateGuest(self, addr, 1, .read) orelse return null;
    const off_usize: usize = @intCast(off);
    if (off_usize >= self.mem.len) return null;
    const available = self.mem[off_usize..@min(self.mem.len, off_usize + max_len)];
    const end = std.mem.indexOfScalar(u8, available, 0) orelse return null;
    return available[0..end];
}

pub fn cxxExceptionTypeName(self: anytype, type_info_address: u64) ?[]const u8 {
    const name_address = read64(self, type_info_address +| 8);
    return guestCString(self, name_address, 4096);
}

pub fn cxxExceptionMessage(self: anytype, object_address: u64) ?[]const u8 {
    const runtime_error_message = read64(self, object_address +| 8);
    if (guestCString(self, runtime_error_message, 4096)) |message| {
        if (message.len != 0) return message;
    }
    const message_view = compat_runtime.libcppStringView(self, object_address +| 8) orelse return null;
    if (message_view.length == 0 or message_view.length > 4096) return null;
    const message = guestMemoryConst(self, message_view.address, message_view.length) orelse return null;
    for (message) |byte| {
        if (byte < 0x20 or byte > 0x7E) return null;
    }
    return message;
}

pub fn guestWriteCString(self: anytype, addr: u64, bytes: []const u8) bool {
    if (guestMemory(self, addr, bytes.len + 1)) |buf| {
        @memcpy(buf[0..bytes.len], bytes);
        buf[bytes.len] = 0;
        return true;
    }
    return false;
}
