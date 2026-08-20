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
const memory_write_provenance = memory_mod.memory_write_provenance;
const memory_provenance = @import("dyld").memory_provenance;
const pointer_firewall = @import("dyld").pointer_firewall;
const semantic_fault_classifier = @import("diagnostics").semantic_fault_classifier;
const zero_adjudication = @import("diagnostics").zero_adjudication;
const opaque_lifetime_recovery = @import("diagnostics").opaque_lifetime_recovery;
const guest_assertion_recovery = @import("guest_abi").guest_assertion_recovery;
const vt = @import("vtable");
const guest_log = @import("guest_log.zig");
const generated_endian_contract = @import("generated_endian_contract.zig");
const near_null_causality = @import("near_null_causality.zig");
pub const ownership = @import("ownership");
const recovery_ledger = ownership.ledger;
const bounded_dispatch_fst = @import("bounded_dispatch_fst.zig");
const generated_block = @import("execution_history").generated_block;
const dispatch_shape = @import("execution_history").dispatch_shape;
const bounded_scan_mod = @import("execution_history").bounded_scan;
const scan_limits = bounded_scan_mod.Limits;
const guest_address_space = @import("guest_address_space");
// Hardware facts the fault path has to ask before interpreting a protection
// failure: a no-access page inside the GPU register aperture is the delivery
// mechanism, not a defect.
const device_tree = @import("device_tree");
const dispatch_table = @import("dispatch_table");
const byte_order = @import("byte_order");
const dispatch_recovery = @import("dispatch_recovery");
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
const ENDIAN_EVIDENCE_BUFFER_LEN = constants.ENDIAN_EVIDENCE_BUFFER_LEN;
const GUEST_SIGSEGV = constants.GUEST_SIGSEGV;

// Historically observed displacement of the emitter's guest-return stack slot
// (Xenia's StackLayout::GUEST_RET_ADDR, `rsp+0x58`). This is **not** a gate: the
// bounded witness discovers the displacement from the comparison it finds, and
// the tail scan confirms it independently. The value survives only so a run can
// report when what it observed differs from what previous runs did — a layout
// change should read as a layout change, not as a missing witness.
const OBSERVED_TYPICAL_GUEST_RET_ADDR_OFFSET: u64 = 0x58;

const mappedOffset = macho_core.utils.mappedOffset;

const InstructionSnapshot = struct {
    operation: []const u8 = "",
    length: u8 = 0,
    bytes: [16]u8 = [_]u8{0} ** 16,
    byte_count: u8 = 0,
};

fn currentInstructionSnapshot(self: anytype) InstructionSnapshot {
    const rip = self.regs.rip;
    const source: []const u8 = if (self.sparse_memory.executableBytesConst(rip, 16)) |sparse_code|
        sparse_code
    else blk: {
        const offset = translateGuest(self, rip, 1, .execute) orelse return .{};
        if (offset >= self.mem.len) return .{};
        break :blk self.mem[@intCast(offset)..][0..@min(@as(usize, 16), self.mem.len - @as(usize, @intCast(offset)))];
    };
    if (source.len == 0) return .{};
    const decoded = decodeInsn(source);
    var snapshot = InstructionSnapshot{
        .operation = @tagName(decoded.op),
        .length = decoded.len,
        .byte_count = @intCast(@min(source.len, @as(usize, 16))),
    };
    @memcpy(snapshot.bytes[0..snapshot.byte_count], source[0..snapshot.byte_count]);
    return snapshot;
}

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
        .write => self.sparse_memory.bytes(address, size, true) != null,
        .execute => self.sparse_memory.isExecutable(address, size),
    };
    return .{
        .mapped = sparse_mapped or mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) != null,
        .allowed = sparse_allowed or translateGuest(self, address, size, access) != null,
        .region = self.memory_regions.find(address, size),
        .pointer_policy = self.pointer_firewall.policyAt(address),
    };
}

/// Whether the mapped-image section containing `address` holds instructions,
/// remembering the last section's extent so the answer is a range compare
/// rather than a search.
///
/// This is on the instruction hot path, and without the memo every single
/// instruction pays a binary search over the section index plus up to four
/// string comparisons against section names — to re-derive a fact that cannot
/// change. Sections are fixed once the image is loaded, so the containing
/// range and its verdict are both immutable, which is what makes a one-entry
/// cache sound rather than merely lucky.
///
/// One entry is enough because instruction fetch is local: straight-line code
/// and loops stay inside a single section for millions of consecutive steps,
/// so a bigger cache would buy hit rate that a single entry already has.
///
/// The mutable parts of the decision deliberately stay outside this: sparse
/// mappings and page permissions can change under `mmap`/`mprotect`, so
/// caching those would be caching something that moves.
fn cachedSectionExecutable(self: anytype, address: u64) bool {
    if (address >= self.executable_section_low and address < self.executable_section_high) {
        return self.executable_section_verdict;
    }
    const section = self.metadata.sectionAtAddress(address) orelse return false;
    const verdict = isExecutableMachOSection(section);
    // Diagnostic callers hold this state by const pointer; they still read the
    // memo, they just cannot refresh it.
    if (!@typeInfo(@TypeOf(self)).pointer.is_const) {
        self.executable_section_low = section.address;
        self.executable_section_high = section.address +| section.size;
        self.executable_section_verdict = verdict;
    }
    return verdict;
}

fn isExecutableMachOSection(section: anytype) bool {
    // Mach-O segment permissions are page/segment-level, but __TEXT also
    // contains non-code sections such as __gcc_except_tab, __const, and
    // __cstring. Those bytes must never become instruction targets merely
    // because their containing segment is r-x. Keep the code-section rule
    // local to the mapped-image path; sparse JIT pages and synthetic thunks
    // are handled separately below.
    if (section.flags & 0x8000_0000 != 0 or section.flags & 0x0000_0400 != 0) return true;
    return std.mem.eql(u8, section.name, "__text") or
        std.mem.eql(u8, section.name, "__stubs") or
        std.mem.eql(u8, section.name, "__stub_helper") or
        std.mem.eql(u8, section.name, "__auth_stubs");
}

pub fn isExecutableAddress(self: anytype, address: u64) bool {
    // This is called from the instruction hot path. Sparse JIT pages and
    // mapped Mach-O instructions are the overwhelmingly common cases. Check
    // them before the synthetic-region registry, whose lookup is linear in
    // the number of ABI bindings. Segment permissions alone are not
    // sufficient: exception tables and other read-only data live inside the
    // r-x __TEXT segment, so mapped addresses still need section validation.
    if (self.sparse_memory.isExecutable(address, 1)) return true;
    if (translateGuest(self, address, 1, .execute) != null) {
        return cachedSectionExecutable(self, address);
    }

    // Synthetic thunks live outside the mapped image. Only pay for their
    // provenance lookup after both normal executable address spaces miss.
    return self.memory_regions.permitsSyntheticExecution(address, 1);
}

test "Mach-O exception-table sections are not executable instruction targets" {
    const executable_text = .{ .name = "__text", .flags = @as(u32, 0) };
    const exception_table = .{ .name = "__gcc_except_tab", .flags = @as(u32, 0) };
    try std.testing.expect(isExecutableMachOSection(executable_text));
    try std.testing.expect(!isExecutableMachOSection(exception_table));
}

test "Mach-O pure-instruction section flags are executable" {
    const pure_instructions = .{ .name = "__custom", .flags = @as(u32, 0x8000_0000) };
    try std.testing.expect(isExecutableMachOSection(pure_instructions));
}

/// Explain a mapped-but-non-code Mach-O target at the control-flow boundary.
/// Segment-level permissions alone are not enough to diagnose this case:
/// `__TEXT` commonly contains exception tables and other data next to code.
pub fn logNonExecutableTarget(self: anytype, address: u64, context: ?types.ControlTransferContext) void {
    const section = self.metadata.sectionAtAddress(address);
    const symbol = self.metadata.nearestSymbol(address);
    const mapped = self.addrToOffset(address) != null;
    const bytes = self.guestMemoryConst(address, 16) orelse &[_]u8{};
    machoCapturePrint(
        "macho-processor: non-executable Mach-O target: target=0x{x} mapped={} section={s} section_range=0x{x}..0x{x} section_flags=0x{x} nearest={s}+0x{x} bytes={any} pending_kind={s} source=0x{x} return=0x{x}\n",
        .{
            address,
            mapped,
            if (section) |value| value.name else "<none>",
            if (section) |value| value.address else 0,
            if (section) |value| value.address +| value.size else 0,
            if (section) |value| value.flags else 0,
            if (symbol) |value| value.name else "<none>",
            if (symbol) |value| value.offset else 0,
            bytes,
            if (context) |value| value.kind else "<none>",
            if (context) |value| value.instruction_address else 0,
            if (context) |value| value.return_address else 0,
        },
    );
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

/// F6 (throughput audit): the sparse mapping is consulted first and
/// `translateGuest` only when it misses.
///
/// These used to pass `translateGuest(...)` as an argument, which Zig evaluates
/// before the call — while the callee checks the sparse mapping first and only
/// looks at the offset if that missed. So a sparse-backed read paid for a full
/// contiguous-image translation it discarded, and a contiguous read paid for a
/// sparse probe it did not need. Both directions paid for the path not taken,
/// on every access.
inline fn linearOffset(self: anytype, vaddr: u64, comptime count: u64) ?u64 {
    if (self.sparse_memory.bytesConst(vaddr, count) != null) return null;
    return translateGuest(self, vaddr, count, .read);
}

pub fn read8(self: anytype, vaddr: u64) u8 {
    return memory_mod.read8(&ms(self), vaddr, linearOffset(self, vaddr, 1));
}

pub fn read16(self: anytype, vaddr: u64) u16 {
    return memory_mod.read16(&ms(self), vaddr, linearOffset(self, vaddr, 2));
}

pub fn read32(self: anytype, vaddr: u64) u32 {
    return memory_mod.read32(&ms(self), vaddr, linearOffset(self, vaddr, 4));
}

pub fn read64(self: anytype, vaddr: u64) u64 {
    return memory_mod.read64(&ms(self), vaddr, linearOffset(self, vaddr, 8));
}

pub fn write8(self: anytype, vaddr: u64, val: u8) void {
    if (self.sparse_memory.bytes(vaddr, 1, true)) |bytes| {
        const mutation = captureMemoryMutation(self, vaddr, 1);
        noteGuestWrite(self, vaddr, 1);
        bytes[0] = val;
        commitMemoryMutation(self, mutation, .partial_scalar);
        return;
    }
    const off = translateGuest(self, vaddr, 1, .write) orelse return;
    if (off < self.mem.len) {
        const mutation = captureMemoryMutation(self, vaddr, 1);
        self.initializer_memory.capture(self.mem, @intCast(off), 1);
        noteGuestWrite(self, vaddr, 1);
        self.mem[off] = val;
        commitMemoryMutation(self, mutation, .partial_scalar);
    }
}

pub fn write16(self: anytype, vaddr: u64, val: u16) void {
    if (self.sparse_memory.bytes(vaddr, 2, true)) |bytes| {
        const mutation = captureMemoryMutation(self, vaddr, 2);
        noteGuestWrite(self, vaddr, 2);
        std.mem.writeInt(u16, bytes[0..2], val, .little);
        commitMemoryMutation(self, mutation, .partial_scalar);
        return;
    }
    const off = translateGuest(self, vaddr, 2, .write) orelse return;
    if (off + 2 <= self.mem.len) {
        const mutation = captureMemoryMutation(self, vaddr, 2);
        self.initializer_memory.capture(self.mem, @intCast(off), 2);
        noteGuestWrite(self, vaddr, 2);
        std.mem.writeInt(u16, self.mem[off..][0..2], val, .little);
        commitMemoryMutation(self, mutation, .partial_scalar);
    }
}

pub fn write32(self: anytype, vaddr: u64, val: u32) void {
    if (self.sparse_memory.bytes(vaddr, 4, true)) |bytes| {
        const pointer_provenance = shouldRecordGuestCodePointer(self, .bits32, val) and
            !self.write_diagnostics_armed and !self.provenance_watch.covers(vaddr);
        const previous = if (pointer_provenance) std.mem.readInt(u32, bytes[0..4], .little) else 0;
        const mutation = captureMemoryMutation(self, vaddr, 4);
        noteGuestWrite(self, vaddr, 4);
        std.mem.writeInt(u32, bytes[0..4], val, .little);
        commitMemoryMutation(self, mutation, .partial_scalar);
        if (pointer_provenance) recordGuestCodePointerWrite(self, vaddr, previous, val);
        return;
    }
    const off = translateGuest(self, vaddr, 4, .write) orelse return;
    if (off + 4 <= self.mem.len) {
        const pointer_provenance = shouldRecordGuestCodePointer(self, .bits32, val) and
            !self.write_diagnostics_armed and !self.provenance_watch.covers(vaddr);
        const previous = if (pointer_provenance) std.mem.readInt(u32, self.mem[off..][0..4], .little) else 0;
        const mutation = captureMemoryMutation(self, vaddr, 4);
        self.initializer_memory.capture(self.mem, @intCast(off), 4);
        noteGuestWrite(self, vaddr, 4);
        std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
        commitMemoryMutation(self, mutation, .partial_scalar);
        if (pointer_provenance) recordGuestCodePointerWrite(self, vaddr, previous, val);
    }
}

/// Retain the rare stores that can explain a guest-code dispatch even when
/// full write diagnostics are disabled. Both the native and byte-reversed
/// representations count: the latter is precisely the defect diagnosed by the
/// generated-endian contract. This avoids tracing ordinary integer stores.
fn shouldRecordGuestCodePointer(self: anytype, size: Size, value: u64) bool {
    return switch (size) {
        .bits32 => blk: {
            const narrowed: u32 = @truncate(value);
            break :blk isGuestAddress(self, narrowed) or
                isGuestAddress(self, @byteSwap(narrowed));
        },
        .bits64 => isGuestAddress(self, value) or
            isGuestAddress(self, @byteSwap(value)),
        else => false,
    };
}

fn recordGuestCodePointerWrite(
    self: anytype,
    address: u64,
    previous_value: u64,
    value: u64,
) void {
    const kind: memory_write_provenance.WriteKind =
        if (comptime @hasField(@TypeOf(self.*), "host_repair_in_flight"))
            (if (self.host_repair_in_flight) .host_repair else .scalar)
        else
            .scalar;
    self.memory_writes.recordKind(
        self.allocator,
        address,
        previous_value,
        value,
        self.regs.rip,
        self.executed_steps,
        self.active_guest_thread,
        kind,
    );
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
    if (self.write_diagnostics_armed and
        val >= MIN_PLAUSIBLE_CODE_POINTER and val >= self.executable_min and val < self.executable_max)
    {
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
                        self.metadata.symbolLabel(self.regs.rip),
                        if (writer_symbol) |s| s.offset else 0,
                        self.executed_steps,
                    },
                );
            }
        }
    }
    if (self.sparse_memory.bytes(vaddr, 8, true)) |bytes| {
        const provenance = provenanceWanted(self, vaddr);
        const pointer_provenance = shouldRecordGuestCodePointer(self, .bits64, val);
        if (provenance or pointer_provenance) {
            const prev = std.mem.readInt(u64, bytes[0..8], .little);
            if (provenance) {
                self.memory_writes.record(self.allocator, vaddr, prev, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
            } else {
                recordGuestCodePointerWrite(self, vaddr, prev, val);
            }
        }
        noteGuestWrite(self, vaddr, 8);
        std.mem.writeInt(u64, bytes[0..8], val, .little);
        // Observe only after the guest write commits.  Failed translations
        // must not manufacture vptr history.
        recordAllocationWrite(self, vaddr, .bits64, val);
        return;
    }
    const off = translateGuest(self, vaddr, 8, .write) orelse return;
    if (off + 8 <= self.mem.len) {
        const provenance = provenanceWanted(self, vaddr);
        const pointer_provenance = shouldRecordGuestCodePointer(self, .bits64, val);
        if (provenance or pointer_provenance) {
            const prev = std.mem.readInt(u64, self.mem[off..][0..8], .little);
            if (provenance) {
                self.memory_writes.record(self.allocator, vaddr, prev, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
            } else {
                recordGuestCodePointerWrite(self, vaddr, prev, val);
            }
        }
        self.initializer_memory.capture(self.mem, @intCast(off), 8);
        noteGuestWrite(self, vaddr, 8);
        std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
        recordAllocationWrite(self, vaddr, .bits64, val);
    }
}

/// F6 (throughput audit): no `ensureGuestAccess` pre-check.
///
/// `push` is the second instruction of nearly every function and `call`
/// performs one too, so this pair is among the hottest paths in the runtime.
/// The pre-check probed the sparse mappings and ran `translateGuest`, and then
/// `write64`/`read64` did both again — two full translations for one stack
/// slot. Both accessors already fault correctly on an inaccessible stack.
pub fn push(self: anytype, val: u64) void {
    self.regs.rsp -|= 8;
    write64(self, self.regs.rsp, val);
}

pub fn pop(self: anytype) u64 {
    const val = read64(self, self.regs.rsp);
    self.regs.rsp +|= 8;
    return val;
}

/// Decode the instruction at `rip` **without resolving its memory operand**.
///
/// `DecodedInsn.addr` is left as the raw displacement. Callers that need an
/// effective address must resolve it themselves against whichever register
/// snapshot is correct for their question — see `decodeWithSnapshotOperands`.
///
/// Named for what it does not do: three functions here decode an instruction
/// and they differ precisely in *which register file* resolves the operand, so
/// a name that only says "decode" hides the one thing a caller must choose.
fn decodeStatic(self: anytype, rip: u64) ?DecodedInsn {
    const source: []const u8 = if (self.sparse_memory.executableBytesConst(rip, 16)) |sparse_code|
        sparse_code
    else blk: {
        const offset = translateGuest(self, rip, 1, .execute) orelse return null;
        if (offset >= self.mem.len) return null;
        break :blk self.mem[@intCast(offset)..][0..@min(@as(usize, 16), self.mem.len - @as(usize, @intCast(offset)))];
    };
    if (source.len == 0) return null;
    const decoded = decodeInsn(source);
    return if (decoded.op == .invalid) null else decoded;
}

fn decodedMemoryEvent(event: exit_diagnostics.MemoryAccessEvent) ?DecodedInsn {
    if (event.instruction_byte_count == 0) return null;
    const count: usize = @min(event.instruction_byte_count, event.instruction_bytes.len);
    const decoded = decodeInsn(event.instruction_bytes[0..count]);
    return if (decoded.op == .invalid) null else decoded;
}

/// Which subsystem owns a generated-code scalar load fault.
///
/// These classes are mutually exclusive by construction. They used to be
/// re-derived independently inside each recovery, from live register state, in
/// a fall-through chain — and one of those recoveries writes the very register
/// the chain keys on (`tryRecoverGeneratedEndianAddress` calls `setReg` on the
/// base). Ownership could therefore change underneath the chain, which is how a
/// change to endian handling moved faults into the near-null owner. Deciding
/// once, before any repair runs, is what keeps the owners separable.
pub const GeneratedFaultOwner = enum {
    /// Not a recoverable generated-code scalar load.
    none,
    /// `mov r32,[base]` under 0x67 whose base holds a byte-swapped address.
    /// Requires a *non-zero* base: a zero base is never a swapped address, and
    /// letting this class claim zero is what made two owners overlap.
    endian_swapped_base,
    /// Xenia's 32-bit indirection-table load `67 8B 03` with EBX == 0. Owned
    /// exclusively by the bounded dispatch transducer; never zero-filled.
    null_base_dispatch,
    /// Any other small scalar load from an exactly-zero base.
    null_base_scalar,
};

pub const GeneratedFaultClassification = struct {
    owner: GeneratedFaultOwner = .none,
    fault: DecodedInsn = undefined,
    base_value: u64 = 0,
    address_size: Size = .bits64,
};

/// The claim input: everything the owners are allowed to decide on. Assembled
/// once, from state no repair has touched.
pub const GeneratedFaultClaim = struct {
    op: x64_decoder.Op,
    has_override: bool,
    base_reg: x64_decoder.RegId,
    dst_reg: x64_decoder.RegId,
    base_value: u64,
    fault_address: u64,
    width: u8,
    base_only_zero_displacement: bool,
    scalar_load_form: bool,
    indirection_form: bool,
};

fn claimsEndianSwappedBase(claim: GeneratedFaultClaim) bool {
    // A zero base is never a byte-swapped address. Omitting this is what let
    // two owners match the same fault and made declaration order the tie-break.
    return claim.base_only_zero_displacement and claim.width == 4 and
        claim.base_value != 0 and claim.fault_address != 0 and
        claim.op == .mov_reg32_mem32 and claim.has_override and
        claim.base_value == claim.fault_address;
}

fn claimsNullBaseDispatch(claim: GeneratedFaultClaim) bool {
    return claim.base_only_zero_displacement and claim.scalar_load_form and
        claim.base_value == 0 and claim.fault_address == 0 and
        (claim.width == 1 or claim.width == 2 or claim.width == 4) and
        claim.indirection_form;
}

fn claimsNullBaseScalar(claim: GeneratedFaultClaim) bool {
    return claim.base_only_zero_displacement and claim.scalar_load_form and
        claim.base_value == 0 and claim.fault_address == 0 and
        (claim.width == 1 or claim.width == 2 or claim.width == 4) and
        !claim.indirection_form;
}

pub const GeneratedFaultArbiter = ownership.Arbiter(GeneratedFaultOwner, GeneratedFaultClaim);

pub const generated_fault_claims = [_]GeneratedFaultArbiter.Claim{
    .{ .owner = .endian_swapped_base, .matches = claimsEndianSwappedBase },
    .{ .owner = .null_base_dispatch, .matches = claimsNullBaseDispatch },
    .{ .owner = .null_base_scalar, .matches = claimsNullBaseScalar },
};

/// Decide the single owner of a generated-code scalar load fault.
///
/// Pure with respect to guest state: it decodes and reads registers but mutates
/// nothing, so the answer cannot be perturbed by the repair it selects.
///
/// Selection runs through `ownership.Arbiter`, which evaluates **every** claim
/// rather than short-circuiting. That makes disjointness a continuously checked
/// property instead of an argued one: if two owners ever match the same fault
/// again, the run says so instead of quietly handing it to whichever predicate
/// happens to be listed first.
pub fn classifyGeneratedScalarFault(
    self: anytype,
    fault_address: u64,
    bytes: u8,
) GeneratedFaultClassification {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "has_xenia_compat")) return .{};
    if (!self.has_xenia_compat) return .{};
    if (!self.sparse_memory.isExecutable(self.regs.rip, 1)) return .{};

    const fault = decodeStatic(self, self.regs.rip) orelse return .{};
    const address_size: Size = if (fault.has_0x67) .bits32 else .bits64;
    const base_value = if (fault.sib_has_base)
        self.regVal(fault.sib_base_reg, address_size)
    else
        0;

    const claim = GeneratedFaultClaim{
        .op = fault.op,
        .has_override = fault.has_0x67,
        .base_reg = fault.sib_base_reg,
        .dst_reg = fault.dst_reg,
        .base_value = base_value,
        .fault_address = fault_address,
        .width = bytes,
        .base_only_zero_displacement = isBaseOnlyZeroDisplacementForm(fault),
        .scalar_load_form = isGeneratedNullScalarAddressForm(fault),
        .indirection_form = isBoundedDispatchIndirectionForm(fault),
    };

    const outcome = self.generated_fault_arbiter.decide(claim);
    if (outcome.ambiguous()) {
        machoCapturePrint(
            "macho-processor: generated fault ownership CONFLICT: rip=0x{x} address=0x{x} width={d} owners={s} and {s} both claimed this fault; the selection is ambiguous and whichever ran first would have won silently. This is an ownership defect, not a guest condition\n",
            .{ self.regs.rip, fault_address, bytes, @tagName(outcome.owner.?), @tagName(outcome.conflict.?) },
        );
        return .{};
    }
    const owner = outcome.owner orelse return .{};

    // Field-availability gates are about the *state*, not the claim, so they
    // stay here rather than inside a predicate.
    switch (owner) {
        .endian_swapped_base => {
            if (comptime !@hasField(State, "generated_endian_contract")) return .{};
        },
        .null_base_dispatch, .null_base_scalar => {
            if (comptime !@hasField(State, "generated_null_scalar_read") or
                !@hasField(State, "last_generated_null_read_rip")) return .{};
        },
        .none => return .{},
    }

    return .{
        .owner = owner,
        .fault = fault,
        .base_value = base_value,
        .address_size = address_size,
    };
}

/// Base-only, zero-displacement addressing with no index and no RIP-relative
/// component — the shape every generated-code scalar recovery requires.
pub fn isBaseOnlyZeroDisplacementForm(fault: DecodedInsn) bool {
    if (fault.sib_has_index or fault.rip_relative) return false;
    if (!fault.sib_has_base) return false;
    return fault.addr == 0;
}

/// Xenia's 32-bit indirection-table load, `67 8B 03` — `mov eax, dword [ebx]`
/// under an address-size override. Sole property of the bounded dispatch
/// transducer.
pub fn isBoundedDispatchIndirectionForm(fault: DecodedInsn) bool {
    return fault.op == .mov_reg32_mem32 and fault.has_0x67 and
        fault.sib_base_reg == .bl_bx_ebx_rbx and
        fault.dst_reg == .al_ax_eax_rax;
}

fn tryRecoverGeneratedEndianAddress(
    self: anytype,
    classification: GeneratedFaultClassification,
    fault_address: u64,
    bytes: u8,
) ?u64 {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "generated_endian_contract")) return null;
    const fault = classification.fault;

    var load: ?generated_endian_contract.MovbeLoad = null;
    var witness: ?generated_endian_contract.ComparisonWitness = null;
    // Production evidence path: the always-on endian evidence ring, written at
    // the execute site without re-decode. The diagnostic memory trace below is
    // gated behind ROSETTE_MACHO_MEMORY_TRACE (off by default) so it cannot be
    // the sole evidence source for the contract.
    if (comptime @hasField(@TypeOf(self.*), "endian_evidence_entries")) {
        const evidence_count: usize = if (self.endian_evidence_filled) ENDIAN_EVIDENCE_BUFFER_LEN else self.endian_evidence_index;
        var examined: usize = 0;
        while (examined < evidence_count and examined < 8 and (load == null or witness == null)) : (examined += 1) {
            const distance: u8 = @intCast(examined + 1);
            const index = (self.endian_evidence_index + ENDIAN_EVIDENCE_BUFFER_LEN - 1 - examined) % ENDIAN_EVIDENCE_BUFFER_LEN;
            const entry = self.endian_evidence_entries[index];
            if (entry.width_bytes != 4) continue;
            if (witness == null and entry.kind == .cmp_witness and
                entry.register == @as(u8, @intCast(@intFromEnum(fault.sib_base_reg))))
            {
                witness = .{
                    .execution = entry.execution,
                    .instruction_address = entry.instruction_address,
                    .width_bytes = entry.width_bytes,
                    .compared_register = entry.register,
                    .memory_value = entry.raw_value,
                    .distance = distance,
                };
            }
            if (load == null and entry.kind == .movbe_load and
                entry.register == @as(u8, @intCast(@intFromEnum(fault.sib_base_reg))))
            {
                const raw_value: u32 = @truncate(entry.raw_value);
                load = .{
                    .execution = entry.execution,
                    .instruction_address = entry.instruction_address,
                    .source_address = entry.source_address,
                    .width_bytes = entry.width_bytes,
                    .destination_register = entry.register,
                    .raw_value = raw_value,
                    .swapped_value = generated_endian_contract.swapped(raw_value, .dword),
                    .distance = distance,
                };
            }
        }
    }
    // Fallback: the diagnostic memory trace (ROSETTE_MACHO_MEMORY_TRACE=1)
    // records every access with instruction bytes; use it when the always-on
    // ring did not yield both pieces of evidence.
    if (load == null or witness == null) {
        const count: usize = if (self.memory_trace_filled) MEMORY_TRACE_BUFFER_LEN else self.memory_trace_index;
        var examined: usize = 0;
        while (examined < count and examined < 8 and (load == null or witness == null)) : (examined += 1) {
            const distance: u8 = @intCast(examined + 1);
            const index = (self.memory_trace_index + MEMORY_TRACE_BUFFER_LEN - 1 - examined) % MEMORY_TRACE_BUFFER_LEN;
            const event = self.memory_trace_entries[index];
            const decoded = decodedMemoryEvent(event) orelse continue;
            if (witness == null and decoded.op == .cmp_reg32_mem32 and
                decoded.dst_reg == fault.sib_base_reg and event.bytes == 4 and
                std.mem.eql(u8, event.access, "read"))
            {
                witness = .{
                    .execution = .{
                        .present = event.provenance_present,
                        .thread_handle = event.thread_handle,
                        .scheduler_epoch = event.scheduler_epoch,
                        .step = event.step,
                    },
                    .instruction_address = event.instruction_address,
                    .width_bytes = event.bytes,
                    .compared_register = @intCast(@intFromEnum(decoded.dst_reg)),
                    .memory_value = @as(u32, @truncate(event.value)),
                    .distance = distance,
                };
            }
            if (load == null and decoded.op == .movbe_reg_mem and decoded.size == .bits32 and
                decoded.dst_reg == fault.sib_base_reg and event.bytes == 4 and
                std.mem.eql(u8, event.access, "read"))
            {
                const raw_value: u32 = @truncate(event.value);
                load = .{
                    .execution = .{
                        .present = event.provenance_present,
                        .thread_handle = event.thread_handle,
                        .scheduler_epoch = event.scheduler_epoch,
                        .step = event.step,
                    },
                    .instruction_address = event.instruction_address,
                    .source_address = event.address,
                    .width_bytes = event.bytes,
                    .destination_register = @intCast(@intFromEnum(decoded.dst_reg)),
                    .raw_value = raw_value,
                    .swapped_value = generated_endian_contract.swapped(raw_value, .dword),
                    .distance = distance,
                };
            }
        }
    }
    const unswapped_candidate: u32 = @truncate(generated_endian_contract.swapped(fault_address, .dword));
    const candidate_readable = self.sparse_memory.bytesConst(unswapped_candidate, bytes) != null or
        translateGuest(self, unswapped_candidate, bytes, .read) != null;
    const observed_load = load orelse {
        if (candidate_readable) {
            machoCapturePrint(
                "macho-processor: generated endian contract rejected: reason=movbe_evidence_missing fault_rip=0x{x} invalid=0x{x} candidate=0x{x} witness_seen={}\n",
                .{ self.regs.rip, fault_address, unswapped_candidate, witness != null },
            );
        }
        return null;
    };
    const observed_witness = witness orelse {
        machoCapturePrint(
            "macho-processor: generated endian contract rejected: reason=comparison_witness_missing fault_rip=0x{x} invalid=0x{x} candidate=0x{x} movbe=0x{x}\n",
            .{ self.regs.rip, fault_address, unswapped_candidate, observed_load.instruction_address },
        );
        return null;
    };
    const assessment = generated_endian_contract.assess(observed_load, observed_witness, .{
        .execution = .{
            .present = true,
            .thread_handle = self.active_guest_thread,
            .scheduler_epoch = self.cooperative_thread_switches,
            .step = self.executed_steps,
        },
        .address = fault_address,
        .width_bytes = bytes,
        .base_register = @intCast(@intFromEnum(fault.sib_base_reg)),
        .address_size_override = fault.has_0x67,
        .base_only = fault.sib_has_base and !fault.sib_has_index and !fault.rip_relative,
        .displacement = fault.addr,
        .generated_code = true,
        .original_value_readable = candidate_readable,
    });
    const recovery = switch (assessment) {
        .recovery => |recovery| recovery,
        .rejected => |reason| {
            machoCapturePrint(
                "macho-processor: generated endian contract rejected: reason={s} fault_rip=0x{x} invalid=0x{x} candidate=0x{x} base={s} movbe=0x{x}/0x{x} witness=0x{x}/0x{x} distances={d}/{d} provenance(load/witness/fault)={}/{}:{}@{d}/{}/{}:{}@{d}/{}/{}:{}@{d} candidate_readable={}\n",
                .{
                    @tagName(reason),
                    self.regs.rip,
                    fault_address,
                    unswapped_candidate,
                    @tagName(fault.sib_base_reg),
                    observed_load.raw_value,
                    observed_load.swapped_value,
                    observed_witness.memory_value,
                    observed_witness.instruction_address,
                    observed_load.distance,
                    observed_witness.distance,
                    observed_load.execution.present,
                    observed_load.execution.thread_handle,
                    observed_load.execution.scheduler_epoch,
                    observed_load.execution.step,
                    observed_witness.execution.present,
                    observed_witness.execution.thread_handle,
                    observed_witness.execution.scheduler_epoch,
                    observed_witness.execution.step,
                    true,
                    self.active_guest_thread,
                    self.cooperative_thread_switches,
                    self.executed_steps,
                    candidate_readable,
                },
            );
            return null;
        },
    };

    const previous_writer = self.memory_writes.lookup(recovery.source_address);
    const source_writable = self.sparse_memory.bytes(recovery.source_address, 4, true) != null or
        translateGuest(self, recovery.source_address, 4, .write) != null;
    self.setReg(fault.sib_base_reg, .bits32, recovery.address);
    if (source_writable) {
        // Persist the proven guest-big-endian representation. The raw memory
        // word becomes the swapped value, so the next architectural MOVBE
        // produces the witnessed guest code address without recovery.
        //
        // This is a Rosette-authored store into guest memory, and it outlives
        // the fault: any later reader of this slot — including the near-null
        // causality chain looking for a producer — sees a value no guest
        // instruction wrote. Marked as such so the ledger says so.
        writeMemValAsHostRepair(self, recovery.source_address, .bits32, fault_address);
    }
    self.generated_endian_contract.note();
    machoCapturePrint(
        "macho-processor: generated endian contract repair #{d}: fault_rip=0x{x} base={s} invalid=0x{x} restored=0x{x} movbe=0x{x} source=0x{x} witness=0x{x} source_rewritten={} writer=0x{x}@{d} writer_thread=0x{x}; classification=xenia_guest_return_address_host_endian\n",
        .{
            self.generated_endian_contract.recoveries,
            self.regs.rip,
            @tagName(fault.sib_base_reg),
            fault_address,
            recovery.address,
            recovery.producer_instruction,
            recovery.source_address,
            recovery.witness_instruction,
            source_writable,
            if (previous_writer) |writer| writer.instruction_address else 0,
            if (previous_writer) |writer| writer.step else 0,
            if (previous_writer) |writer| writer.thread else 0,
        },
    );
    return recovery.address;
}

/// Apply the generated-endian contract at the CALL_POSSIBLE_RETURN predicate,
/// before a proven byte-reversed guest return can fall through into Xenia's
/// indirection table. The comparison is an independent witness: its stack
/// operand contains the original guest address, while the live register holds
/// exactly the MOVBE-swapped form loaded earlier in the same scheduler slice.
///
/// This does not choose a branch. It repairs the demonstrated byte-order
/// boundary, then the ordinary CMP/Jcc instructions decide control flow.
pub fn tryRepairGeneratedEndianBeforeDispatch(
    self: anytype,
    compared_register: RegId,
    comparison_address: u64,
    comparison_value: u64,
    comparison_len: u8,
) ?u64 {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "generated_endian_contract") or
        !@hasField(State, "endian_evidence_entries") or
        !@hasField(State, "has_xenia_compat"))
    {
        return null;
    }
    if (!self.has_xenia_compat) return null;
    if (comptime @hasField(State, "executable_min") and @hasField(State, "executable_max")) {
        if (self.regs.rip >= self.executable_min and self.regs.rip < self.executable_max) return null;
    }

    // Most comparisons, including generated ones, compare equal. Establish
    // that a repair could be needed before probing executable mappings or
    // decoding the following branch/dispatch pair.
    const register_index: u8 = @intCast(@intFromEnum(compared_register));
    const live_value: u32 = @truncate(self.regVal(compared_register, .bits32));
    const witness_value: u32 = @truncate(comparison_value);
    if (live_value == 0 or live_value == witness_value) return null;
    if (!self.sparse_memory.isExecutable(self.regs.rip, comparison_len)) return null;

    // Prove the exact generated tail before treating the comparison as a
    // return-address witness: CMP; JE; address-size MOV EAX,[same register].
    const branch_rip = self.regs.rip +| comparison_len;
    const branch = decodeStatic(self, branch_rip) orelse return null;
    if ((branch.op != .jcc_rel8 and branch.op != .jcc_rel32) or
        branch.cond != .e or branch.len == 0)
    {
        return null;
    }
    const dispatch_rip = branch_rip +| branch.len;
    const dispatch = decodeStatic(self, dispatch_rip) orelse return null;
    if (!isBoundedDispatchIndirectionForm(dispatch) or
        dispatch.sib_base_reg != compared_register)
    {
        return null;
    }

    var load: ?generated_endian_contract.MovbeLoad = null;
    const evidence_count: usize = if (self.endian_evidence_filled)
        ENDIAN_EVIDENCE_BUFFER_LEN
    else
        self.endian_evidence_index;
    var examined: usize = 0;
    while (examined < evidence_count and examined < 8) : (examined += 1) {
        const index = (self.endian_evidence_index + ENDIAN_EVIDENCE_BUFFER_LEN - 1 - examined) % ENDIAN_EVIDENCE_BUFFER_LEN;
        const entry = self.endian_evidence_entries[index];
        if (entry.kind != .movbe_load or entry.width_bytes != 4 or
            entry.register != register_index)
        {
            continue;
        }
        const raw_value: u32 = @truncate(entry.raw_value);
        load = .{
            .execution = entry.execution,
            .instruction_address = entry.instruction_address,
            .source_address = entry.source_address,
            .width_bytes = entry.width_bytes,
            .destination_register = entry.register,
            .raw_value = raw_value,
            .swapped_value = generated_endian_contract.swapped(raw_value, .dword),
            .distance = @intCast(examined + 1),
        };
        break;
    }
    const observed_load = load orelse return null;

    // The source must still contain the value the MOVBE evidence recorded.
    // Otherwise a concurrent or later store invalidated the proof.
    const source_bytes = self.guestMemoryConst(observed_load.source_address, 4) orelse return null;
    if (source_bytes.len < 4 or
        std.mem.readInt(u32, source_bytes[0..4], .little) != @as(u32, @truncate(observed_load.raw_value)))
    {
        return null;
    }

    const candidate_readable = self.sparse_memory.bytesConst(witness_value, 4) != null or
        translateGuest(self, witness_value, 4, .read) != null;
    const assessment = generated_endian_contract.assess(observed_load, .{
        .execution = .{
            .present = true,
            .thread_handle = self.active_guest_thread,
            .scheduler_epoch = self.cooperative_thread_switches,
            .step = self.executed_steps,
        },
        .instruction_address = self.regs.rip,
        .width_bytes = 4,
        .compared_register = register_index,
        .memory_value = witness_value,
        .distance = 1,
    }, .{
        // The verified fall-through dispatch is the pending fault boundary.
        // Giving it the next step preserves the contract's strict load <
        // witness < use ordering without claiming it has executed already.
        .execution = .{
            .present = true,
            .thread_handle = self.active_guest_thread,
            .scheduler_epoch = self.cooperative_thread_switches,
            .step = self.executed_steps +| 1,
        },
        .address = live_value,
        .width_bytes = 4,
        .base_register = register_index,
        .address_size_override = dispatch.has_0x67,
        .base_only = dispatch.sib_has_base and !dispatch.sib_has_index and !dispatch.rip_relative,
        .displacement = dispatch.addr,
        .generated_code = true,
        .original_value_readable = candidate_readable,
    });
    const recovery = switch (assessment) {
        .recovery => |value| value,
        .rejected => return null,
    };

    const previous_writer = self.memory_writes.lookup(recovery.source_address);
    const source_writable = self.sparse_memory.bytes(recovery.source_address, 4, true) != null or
        translateGuest(self, recovery.source_address, 4, .write) != null;
    self.setReg(compared_register, .bits32, recovery.address);
    if (source_writable) {
        // Store the representation MOVBE expects. The live (invalid) value is
        // byte-swapped relative to the restored guest address, so writing it
        // makes the next MOVBE load naturally produce the restored address.
        writeMemValAsHostRepair(self, recovery.source_address, .bits32, live_value);
    }
    self.generated_endian_contract.note();
    machoCapturePrint(
        "macho-processor: generated endian contract proactive repair #{d}: compare_rip=0x{x} compare_source=0x{x} dispatch_rip=0x{x} register={s} invalid=0x{x} restored=0x{x} movbe=0x{x} source=0x{x} source_rewritten={} writer=0x{x}@{d} writer_thread=0x{x}; CMP/Jcc will now execute normally\n",
        .{
            self.generated_endian_contract.recoveries,
            self.regs.rip,
            comparison_address,
            dispatch_rip,
            @tagName(compared_register),
            live_value,
            recovery.address,
            recovery.producer_instruction,
            recovery.source_address,
            source_writable,
            if (previous_writer) |writer| writer.instruction_address else 0,
            if (previous_writer) |writer| writer.step else 0,
            if (previous_writer) |writer| writer.thread else 0,
        },
    );
    return recovery.address;
}

/// The scalar GPR load-from-memory ops eligible for generated-code near-null
/// recovery. 64-bit loads are deliberately excluded: they are owned by the
/// vtable/XModule recovery paths and must never be satisfied as zero-fill.
pub fn isGeneratedNullScalarLoadOp(op: x64_decoder.Op) bool {
    return switch (op) {
        .mov_reg8_mem8, .mov_reg16_mem16, .mov_reg32_mem32 => true,
        else => false,
    };
}

/// Addressing-form gate shared by the recovery and its tests: a small scalar
/// load with base-only, zero-displacement addressing (no index, no
/// RIP-relative component). The exact `67 8B 03` Xenia indirection form is
/// subsequently removed from the generic zero-fill path and handled only by
/// the bounded dispatch transducer.
pub fn isGeneratedNullScalarAddressForm(fault: DecodedInsn) bool {
    if (!isGeneratedNullScalarLoadOp(fault.op)) return false;
    return isBaseOnlyZeroDisplacementForm(fault);
}

/// Recover a near-null scalar load executed inside JIT-generated (sparse)
/// executable code. Xenia's Xbyak fragments materialize cvar/global addresses
/// through a base register; when that materialization produced 0 (an unset
/// flag, e.g. perf_monitor_detailed_metrics), the `mov r32, [base+0]` load
/// reads a zero-filled scalar rather than terminating the guest. This is kept
/// deliberately narrower than the endian contract (which runs first and owns
/// byte-swap repairs, including the 0x67 form, when it can prove movbe and
/// comparison evidence) and than the vtable/XModule recoveries (64-bit loads
/// only): only small scalar loads from an exactly-zero effective address in
/// generated code qualify, and writes are never masked.
fn tryRecoverGeneratedNullScalarRead(
    self: anytype,
    classification: GeneratedFaultClassification,
    bytes: u8,
) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "generated_null_scalar_read") or
        !@hasField(State, "last_generated_null_read_rip"))
    {
        return false;
    }
    const fault = classification.fault;
    const addr_size = classification.address_size;

    self.generated_null_scalar_read.note();
    // Link this recovered read to the next generated null indirect transfer
    // (Xenia's indirection-table `jmp(rax)` dispatch): if the zero-fill
    // becomes a null function pointer, the transfer recovery reports the
    // connection back to this read in its own throttled log line.
    self.last_generated_null_read_rip = self.regs.rip;
    // The zero-filled read can sit inside a hot JIT loop (e.g. a per-block
    // perf-monitor check); log only the first few and power-of-two milestones
    // to avoid flooding the run while still revealing the earliest RIPs.
    if (self.generated_null_scalar_read.shouldLog()) {
        const raw = self.guestMemoryConst(self.regs.rip, 16) orelse &[_]u8{};
        const raw_len: usize = @min(@as(usize, fault.len), raw.len);
        machoCapturePrint(
            "macho-processor: generated null scalar read recovery #{d}: fault_rip=0x{x} op={s} effective=0x0 base={s}=0x0 displacement=0x0 addr_size={s} has_0x67={} width={d} bytes={any} symbol={s}; satisfied as zero-filled generated read\n",
            .{
                self.generated_null_scalar_read.recoveries,
                self.regs.rip,
                @tagName(fault.op),
                @tagName(fault.sib_base_reg),
                @tagName(addr_size),
                fault.has_0x67,
                bytes,
                raw[0..raw_len],
                self.metadata.symbolLabel(self.regs.rip),
            },
        );
        // Fault-time materialization window: how was the base register set?
        // Xenia's indirection dispatch is `mov ebx, <guest_target>;
        // mov eax, dword[ebx]`, so the preceding instructions reveal whether
        // the guest branch target itself was 0 or the address was
        // mis-materialized (e.g. a RIP-relative lea computed wrong).
        const thread_handle = if (@hasField(State, "active_guest_thread")) self.active_guest_thread else 0;
        const thread_id = if (@hasField(State, "threadNumericId")) self.threadNumericId(thread_handle) else 0;
        machoCapturePrint(
            "macho-processor:   null read thread=0x{x} tid={d} gpr rax=0x{x} rcx=0x{x} rdx=0x{x} rbx=0x{x} rsi=0x{x} rdi=0x{x} r8=0x{x} r9=0x{x} r10=0x{x} r11=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x} rsp=0x{x} rbp=0x{x}{s}{s}{s}\n",
            .{
                thread_handle,
                thread_id,
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.rbx,
                self.regs.rsi,
                self.regs.rdi,
                self.regs.r8,
                self.regs.r9,
                self.regs.r10,
                self.regs.r11,
                self.regs.r12,
                self.regs.r13,
                self.regs.r14,
                self.regs.r15,
                self.regs.rsp,
                self.regs.rbp,
                if (isGuestAddress(self, self.regs.rcx)) " rcx=guest" else "",
                if (isGuestAddress(self, self.regs.r8)) " r8=guest" else "",
                if (isGuestAddress(self, self.regs.r15)) " r15=guest" else "",
            },
        );
        // RCX is intentionally diagnostic-only here. Xenia does not load the
        // authoritative guest return until after the indirection-table load;
        // the bounded witness above uses the fixed [rsp+0x58] slot instead.
        if (isGuestAddress(self, self.regs.rcx) and fault.sib_base_reg == .bl_bx_ebx_rbx) {
            machoCapturePrint(
                "macho-processor:   null read contextual RCX: rcx=0x{x} ({s}) is a guest-window value, but the authoritative return witness is [rsp+0x58]; the base register was zero so the indirection entry was unread\n",
                .{
                    self.regs.rcx,
                    self.metadata.symbolLabel(self.regs.rcx),
                },
            );
        }
        dumpPrecedingInstructionWindow(self, self.regs.rip, 5);
    }
    return true;
}

/// Indirect-control-transfer ops eligible for generated-code null-target
/// recovery. When JIT-generated code tail-dispatches through a function
/// pointer (Xenia's code-cache indirection dispatch: `mov eax, dword[ebx];
/// ...; jmp(rax)` from X64Emitter::Call/CallIndirect) and the pointer
/// materialized as 0 — a guest branch target of 0 or an unpatched indirection
/// entry — the transfer is a recoverable code-cache miss rather than a
/// translated-program bug: the caller falls through to the following epilogue
/// (the return path) and the run continues.
pub fn isGeneratedNullTransferOp(op: x64_decoder.Op) bool {
    return switch (op) {
        .jmp_reg64, .call_reg64, .jmp_mem64, .call_mem64 => true,
        else => false,
    };
}

/// Ops eligible for the generated-code guest-dispatch recovery. Broader than
/// the null transfer gate: a generated-code `ret` that pops an unpatched guest
/// sentinel (a corrupt frame, e.g. after a double-deallocated tail dispatch)
/// is the same code-cache-miss family and must be repairable too.
pub fn isGeneratedDispatchMissOp(op: x64_decoder.Op) bool {
    return switch (op) {
        .jmp_reg64, .call_reg64, .jmp_mem64, .call_mem64, .ret => true,
        else => false,
    };
}

/// The generated dispatch shape has one owner: `execution_history.dispatch_shape`.
/// These delegate so existing call sites — including the unit tests in
/// `lib/Mach-O/process.zig` that pin the byte encodings — keep working while the
/// recognizer and its reasoning live in one place.
pub fn isFunctionExitEpilogueBytes(bytes: []const u8) bool {
    return dispatch_shape.isFunctionExitEpilogue(bytes);
}

pub fn branchTargetsDeadDispatchEpilogue(branch_target: u64, transfer_rip: u64, transfer_len: u8) bool {
    return dispatch_shape.branchTargetsEpilogue(branch_target, transfer_rip, transfer_len);
}

/// The recognised dispatch shape. Owned by `execution_history.dispatch_shape`;
/// this alias keeps the local call sites readable.
const BoundedTailShape = dispatch_shape.Shape;

/// Walk forward from the null-base load through at most 16 instructions / 64
/// bytes. This is the bounded "tape" of the dispatch transducer. No allocation,
/// unbounded search, or speculative target execution is permitted.
fn boundedTailShape(self: anytype, load_rip: u64, load_len: u8) BoundedTailShape {
    var cursor = load_rip +| load_len;
    var instruction_count: u8 = 0;
    var return_slot_seen = false;
    var return_slot_offset: u64 = 0;
    const limits = scan_limits.tail_shape;
    while (instruction_count < limits.max_instructions and
        cursor > load_rip and limits.withinBytes(load_rip, cursor)) : (instruction_count += 1)
    {
        const decoded = decodeStatic(self, cursor) orelse return .{};
        if (decoded.len == 0) return .{};
        // Xenia reloads the guest return address from the same stack slot the
        // CALL_POSSIBLE_RETURN predicate compared against, to pass it to the
        // dispatched function (`mov rcx,[rsp+disp]`). Recording the
        // displacement here gives a second, independent observation of the
        // slot, so the backward scan's discovery can be cross-checked instead
        // of trusted because it matched a hardcoded constant.
        if (decoded.op == .mov_reg64_mem64 and !decoded.has_0x67 and
            decoded.sib_has_base and !decoded.sib_has_index and
            !decoded.rip_relative and decoded.sib_base_reg == .ah_sp_esp_rsp and
            !return_slot_seen)
        {
            return_slot_seen = true;
            return_slot_offset = decoded.addr;
        }
        if (decoded.op == .jmp_reg64) {
            const after = self.guestMemoryConst(cursor +| decoded.len, 16) orelse &[_]u8{};
            return .{
                .transfer_rip = cursor,
                .transfer_len = decoded.len,
                .transfer_distance = @intCast(@min(cursor - load_rip, std.math.maxInt(u8))),
                .jmp_rax = decoded.dst_reg == .al_ax_eax_rax,
                .dead_epilogue = isFunctionExitEpilogueBytes(after),
                .return_slot_reload_seen = return_slot_seen,
                .return_slot_reload_offset = return_slot_offset,
            };
        }
        // A different control-flow boundary ends this straight-line proof.
        // Following it would turn a bounded recognizer into speculative
        // execution and could accidentally join unrelated generated blocks.
        switch (decoded.op) {
            .jmp_rel8,
            .jcc_rel8,
            .jcc_rel32,
            .jmp_mem64,
            .call_rel32,
            .call_reg64,
            .call_mem64,
            .ret,
            => return .{},
            else => {},
        }
        cursor +|= decoded.len;
    }
    return .{};
}

/// The instruction that defined a register, recovered by decoding the generated
/// code backwards from a known instruction boundary.
///
/// This exists because retained execution history is the wrong tool for a
/// first-observation fault. The instruction ring is 256 entries shared by every
/// live guest thread, so a thread that has been running for a billion steps has
/// a window of a few dozen entries — and if the register was already zero when
/// that window opened, history can only report "always zero", which is true and
/// useless. The generated code, by contrast, still says exactly where the value
/// was supposed to come from, and it says so on the very first execution.
const BoundedDefinition = struct {
    found: bool = false,
    /// Three-way outcome from the block reader: unresolved, defined here, or
    /// live-in from a predecessor block.
    origin: generated_block.Origin = .block_unresolved,
    /// Whether the search range converged or stopped at its ceiling.
    convergence: bounded_scan_mod.Convergence = .unresolved,
    /// Window the reconstruction actually needed.
    window_bytes: u64 = 0,
    block_start: u64 = 0,
    block_length: u8 = 0,
    instruction_address: u64 = 0,
    op: x64_decoder.Op = .invalid,
    /// The definition loaded the register from memory.
    from_memory: bool = false,
    /// Effective source address, recomputed from the fault-time register file.
    /// Sound only for operands whose base register is stable across the window
    /// (stack- and context-relative operands in a tail sequence); reported as
    /// recomputed, never as observed.
    source_address: u64 = 0,
    source_readable: bool = false,
    source_value: u64 = 0,
    /// Width of the load that produced the value. A dispatch-table entry is as
    /// wide as the instruction that read it, and a neighbourhood probe that
    /// guesses the stride reads the wrong slots.
    source_bytes: u8 = 0,
    /// The definition set the register from an immediate.
    from_immediate: bool = false,
    immediate: u64 = 0,
    /// Distance in instructions back from the anchor.
    distance: u8 = 0,
};

/// True when `op` writes `reg` as its destination register. Deliberately a
/// closed list of the forms a JIT emits to materialise a dispatch target;
/// anything absent yields "no definition found", never a wrong one.
fn definesRegister(decoded: DecodedInsn, reg: x64_decoder.RegId) bool {
    if (decoded.dst_reg != reg) return false;
    return switch (decoded.op) {
        .mov_reg8_mem8,
        .mov_reg16_mem16,
        .mov_reg32_mem32,
        .mov_reg64_mem64,
        .mov_reg8_reg8,
        .mov_reg16_reg16,
        .mov_reg32_reg32,
        .mov_reg64_reg64,
        .mov_reg_imm,
        .lea_reg_mem,
        .pop_reg,
        .movbe_reg_mem,
        .xor_reg32_reg32,
        .xor_reg64_reg64,
        => true,
        else => false,
    };
}

fn loadsFromMemory(op: x64_decoder.Op) bool {
    return switch (op) {
        .mov_reg8_mem8,
        .mov_reg16_mem16,
        .mov_reg32_mem32,
        .mov_reg64_mem64,
        .movbe_reg_mem,
        => true,
        else => false,
    };
}

/// Decode backwards from `anchor_rip` to find the instruction that defined
/// `reg`, and re-read its memory source at fault time.
///
/// The block reconstruction itself lives in the execution-history library
/// (`generated_block`), which is where the anchoring rule and its tests belong;
/// this function supplies the x86 decode and the operand resolution. The
/// important product is the three-way `Origin`: a register that is never
/// written in the reconstructed block is **live-in from a predecessor**, which
/// is a finding that says where to look next, not a failure to find anything.
fn boundedBaseDefinition(
    self: anytype,
    anchor_rip: u64,
    reg: x64_decoder.RegId,
) BoundedDefinition {
    const Ctx = struct {
        state: @TypeOf(self),
        register: x64_decoder.RegId,

        fn decode(ctx: @This(), address: u64) ?generated_block.Decoded {
            const decoded = decodeStatic(ctx.state, address) orelse return null;
            return .{
                .len = decoded.len,
                .defines_register = definesRegister(decoded, ctx.register),
            };
        }
    };
    // Adaptive: the block boundary is *found* by widening until the answer
    // stops moving, not asserted by a constant. The window it needed and
    // whether it converged are both reported.
    const located = generated_block.findDefinitionAdaptive(
        Ctx,
        .{ .state = self, .register = reg },
        anchor_rip,
        .{},
        Ctx.decode,
    );

    var result = BoundedDefinition{
        .origin = located.origin,
        .convergence = located.convergence,
        .window_bytes = located.window_bytes,
        .block_start = located.block_start,
        .block_length = located.block_length,
        .instruction_address = located.instruction_address,
        .distance = located.distance,
    };
    if (located.origin != .defined_in_block) return result;

    const decoded = decodeStatic(self, located.instruction_address) orelse return result;
    result.found = true;
    result.op = decoded.op;
    result.from_memory = loadsFromMemory(decoded.op);
    result.source_bytes = bytesForSize(decoded.size);
    result.from_immediate = decoded.op == .mov_reg_imm;
    result.immediate = decoded.imm;
    if (!result.from_memory) return result;

    // Resolve the operand against the fault-time register file the same way the
    // executor would. Sound only for operands whose base is stable across the
    // window (stack- and context-relative operands in a tail sequence), so this
    // is always reported as recomputed rather than observed.
    const addr_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
    var effective: u64 = decoded.addr;
    if (decoded.sib_has_base) effective +%= self.regVal(decoded.sib_base_reg, addr_size);
    if (decoded.sib_has_index) {
        effective +%= self.regVal(decoded.sib_index_reg, addr_size) << @as(u6, decoded.sib_scale);
    }
    if (decoded.rip_relative) effective +%= located.instruction_address + decoded.len;
    if (addr_size == .bits32) effective = @as(u32, @truncate(effective));
    result.source_address = effective;
    if (self.guestMemoryConst(effective, 8)) |slot| {
        if (slot.len >= 8) {
            result.source_readable = true;
            result.source_value = std.mem.readInt(u64, slot[0..8], .little);
        } else if (slot.len >= 4) {
            result.source_readable = true;
            result.source_value = std.mem.readInt(u32, slot[0..4], .little);
        }
    }
    return result;
}

/// How far a value can be followed back through register-to-register moves.
///
/// Generated code routinely materialises a value in one register and moves it
/// into the one the instruction needs — Xenia's `CallIndirect` does exactly this
/// (`mov ebx, reg32; mov eax, [ebx]`). A def-use scan that stops at the move
/// reports `op=mov_reg32_reg32 from_memory=false` and the search ends one hop
/// short of every useful answer, which is where naming the writer of a
/// byte-reversed guest address kept dying.
///
/// Bounded because this is a reader, not a search: each hop re-runs the same
/// block reconstruction, and a chain longer than this is not a copy chain, it is
/// a computation the reader has no business unwinding.
pub const max_move_chain: u8 = 6;

pub const ValueOrigin = struct {
    pub const Hop = struct {
        instruction_address: u64 = 0,
        op: x64_decoder.Op = .invalid,
        from: x64_decoder.RegId = .al_ax_eax_rax,
        to: x64_decoder.RegId = .al_ax_eax_rax,
        /// Constant added by this hop. Non-zero only for address arithmetic,
        /// where the followed register carries the value and the displacement
        /// is the field offset applied to it.
        displacement: i64 = 0,
    };

    pub const Terminal = enum {
        /// Followed to an instruction that read guest memory. `definition`
        /// carries the address; this is the answer the search wants.
        memory_load,
        /// Followed to an immediate. The value was materialised in code, so no
        /// store is responsible for it.
        immediate,
        /// Followed to `xor reg, reg` — the instruction that *made the value
        /// zero*. For a near-null fault this is the end of the search and not
        /// a step on the way to it: nothing produced the null, an instruction
        /// created it, and this names that instruction.
        zeroed,
        /// An address form with no register operand: `lea reg, [disp]` or a
        /// RIP-relative `lea`. The value is a constant the code computed, so
        /// no register and no store is responsible for it.
        computed_constant,
        /// Address arithmetic combining two registers, or scaling one. The
        /// value has more than one producer, so attributing it to a single
        /// register would be a guess. Both operands are named instead.
        address_arithmetic,
        /// The value was popped off the stack. The producing store is the push
        /// or the frame write, which is not reconstructible from the
        /// instruction stream alone — naming the pop is the honest stopping
        /// point.
        stack_load,
        /// A definition was found but it is none of the forms this reader
        /// follows — a call result, a real arithmetic combination, something
        /// else.
        opaque_definition,
        /// No definition could be reconstructed at some hop.
        unresolved,
        /// The chain was still moving when the bound was reached. Not a
        /// failure — a stated limit, and the caller is told so rather than
        /// being handed the last hop as though it were the origin.
        depth_exhausted,
    };

    terminal: Terminal = .unresolved,
    /// Definition at the end of the chain.
    definition: BoundedDefinition = .{},
    hops: [max_move_chain]Hop = [_]Hop{.{}} ** max_move_chain,
    hop_count: u8 = 0,
    /// Sum of the constants the followed address arithmetic applied. The
    /// terminal value plus this is the faulting value, which is what makes a
    /// chain through `lea` reportable rather than merely followed.
    total_displacement: i64 = 0,
    /// The register the chain declined to follow, set only for
    /// `address_arithmetic`. Naming it turns a dead end into the next thing to
    /// look at.
    unfollowed: x64_decoder.RegId = .al_ax_eax_rax,
    /// Constant value for `computed_constant`.
    constant: u64 = 0,
};

/// True when `op` copies one register into another without transforming it, so
/// following it preserves the identity of the value. Deliberately a closed list:
/// an op absent from it ends the chain as `opaque_definition`, which is a
/// reported outcome, never a wrong attribution.
fn isRegisterMove(op: x64_decoder.Op) bool {
    return switch (op) {
        .mov_reg8_reg8,
        .mov_reg16_reg16,
        .mov_reg32_reg32,
        .mov_reg64_reg64,
        => true,
        else => false,
    };
}

/// `xor reg, reg` against itself. The one arithmetic form whose result needs no
/// evaluation: it is zero, always, and every JIT emits it to materialise a null.
fn isSelfZeroing(decoded: DecodedInsn) bool {
    return switch (decoded.op) {
        .xor_reg32_reg32, .xor_reg64_reg64 => decoded.src_reg == decoded.dst_reg,
        else => false,
    };
}

/// How a `lea` produces its value.
///
/// A `lea` is the *most* transparent definition in the instruction set — its
/// result is literally `base + index*scale + disp`, every term of which is
/// named in the encoding — and treating it as opaque ends a search one hop
/// before the register that actually went wrong. Generated code reaches guest
/// fields exactly this way: `lea edx, [ebx+0x20]` then a load through `edx`, so
/// a chain that stops at the `lea` reports the field offset as the origin and
/// never mentions the pointer.
const LeaShape = union(enum) {
    /// Exactly one register contributes at scale 1: the value is that
    /// register plus a constant, so following it preserves the identity of the
    /// pointer being computed.
    single: struct { register: x64_decoder.RegId, displacement: i64 },
    /// No register contributes; the value is a constant.
    constant: u64,
    /// Two registers, or one that is scaled. More than one producer.
    combined: struct { first: x64_decoder.RegId, second: x64_decoder.RegId },
};

fn leaShape(decoded: DecodedInsn, instruction_address: u64) LeaShape {
    const displacement: i64 = @bitCast(decoded.addr);
    if (decoded.rip_relative) {
        return .{ .constant = instruction_address +% decoded.len +% decoded.addr };
    }
    const scaled_index = decoded.sib_has_index and decoded.sib_scale != 0;
    if (decoded.sib_has_base and decoded.sib_has_index) {
        return .{ .combined = .{ .first = decoded.sib_base_reg, .second = decoded.sib_index_reg } };
    }
    if (decoded.sib_has_base) {
        return .{ .single = .{ .register = decoded.sib_base_reg, .displacement = displacement } };
    }
    if (decoded.sib_has_index) {
        if (scaled_index) {
            return .{ .combined = .{ .first = decoded.sib_index_reg, .second = decoded.sib_index_reg } };
        }
        return .{ .single = .{ .register = decoded.sib_index_reg, .displacement = displacement } };
    }
    return .{ .constant = decoded.addr };
}

/// Follow a register back through moves to whatever actually produced its value.
pub fn boundedValueOrigin(
    self: anytype,
    anchor_rip: u64,
    register: x64_decoder.RegId,
) ValueOrigin {
    var result = ValueOrigin{};
    var anchor = anchor_rip;
    var reg = register;

    var step: u8 = 0;
    while (step < max_move_chain) : (step += 1) {
        const definition = boundedBaseDefinition(self, anchor, reg);
        result.definition = definition;
        if (!definition.found) {
            result.terminal = .unresolved;
            return result;
        }
        if (definition.from_memory) {
            result.terminal = .memory_load;
            return result;
        }
        if (definition.from_immediate) {
            result.terminal = .immediate;
            return result;
        }
        const decoded = decodeStatic(self, definition.instruction_address) orelse {
            result.terminal = .unresolved;
            return result;
        };
        if (isSelfZeroing(decoded)) {
            result.terminal = .zeroed;
            return result;
        }
        if (definition.op == .pop_reg) {
            result.terminal = .stack_load;
            return result;
        }

        // Which register the next hop follows, and what constant this hop adds
        // to it.
        var next_reg: x64_decoder.RegId = undefined;
        var hop_displacement: i64 = 0;
        if (definition.op == .lea_reg_mem) {
            switch (leaShape(decoded, definition.instruction_address)) {
                .constant => |value| {
                    result.terminal = .computed_constant;
                    result.constant = value;
                    return result;
                },
                .combined => |pair| {
                    result.terminal = .address_arithmetic;
                    result.definition.op = definition.op;
                    result.unfollowed = pair.second;
                    // Report the first operand as the chain's end rather than
                    // silently picking one to follow: with two producers, a
                    // single attribution would be a guess.
                    result.hops[@min(result.hop_count, result.hops.len - 1)] = .{
                        .instruction_address = definition.instruction_address,
                        .op = definition.op,
                        .from = pair.first,
                        .to = reg,
                    };
                    if (result.hop_count < result.hops.len) result.hop_count += 1;
                    return result;
                },
                .single => |source| {
                    next_reg = source.register;
                    hop_displacement = source.displacement;
                },
            }
        } else if (isRegisterMove(definition.op)) {
            // A move whose source is its own destination cannot be followed,
            // and following it would loop.
            if (decoded.src_reg == reg) {
                result.terminal = .opaque_definition;
                return result;
            }
            next_reg = decoded.src_reg;
        } else {
            result.terminal = .opaque_definition;
            return result;
        }

        if (result.hop_count < result.hops.len) {
            result.hops[result.hop_count] = .{
                .instruction_address = definition.instruction_address,
                .op = definition.op,
                .from = next_reg,
                .to = reg,
                .displacement = hop_displacement,
            };
            result.hop_count += 1;
        }
        result.total_displacement +%= hop_displacement;
        // The definition search is strictly backwards from the anchor, so a
        // self-referential address advance (`lea rbx, [rbx+0x20]`) moves the
        // anchor rather than looping.
        anchor = definition.instruction_address;
        reg = next_reg;
    }
    result.terminal = .depth_exhausted;
    return result;
}

/// Report a followed chain and, when it ends at a load, put that slot under
/// write provenance so the next run names the store.
fn reportValueOrigin(self: anytype, label: []const u8, origin: ValueOrigin) void {
    machoCapturePrint(
        "macho-processor: {s} origin chain: terminal={s} hops={d} instruction=0x{x} op={s} from_memory={} source_address=0x{x} readable={} value=0x{x} from_immediate={} immediate=0x{x}\n",
        .{
            label,
            @tagName(origin.terminal),
            origin.hop_count,
            origin.definition.instruction_address,
            @tagName(origin.definition.op),
            origin.definition.from_memory,
            origin.definition.source_address,
            origin.definition.source_readable,
            origin.definition.source_value,
            origin.definition.from_immediate,
            origin.definition.immediate,
        },
    );
    var index: usize = 0;
    while (index < origin.hop_count) : (index += 1) {
        const hop = origin.hops[index];
        machoCapturePrint(
            "  {s} hop[{d}]: 0x{x} {s} {s} <- {s} + {d}\n",
            .{
                label,
                index,
                hop.instruction_address,
                @tagName(hop.op),
                @tagName(hop.to),
                @tagName(hop.from),
                hop.displacement,
            },
        );
    }

    switch (origin.terminal) {
        .zeroed => machoCapturePrint(
            "macho-processor: {s} origin chain: the value was SET TO ZERO by the instruction at 0x{x} ({s}); the displacement the chain accumulated is {d}, so the faulting address is that offset applied to a register a nearby instruction had just cleared. Nothing loaded a bad pointer here — the null is the code's own constant, and the question is which branch reached a zeroing that the following dereference did not expect\n",
            .{ label, origin.definition.instruction_address, @tagName(origin.definition.op), origin.total_displacement },
        ),
        .computed_constant => machoCapturePrint(
            "macho-processor: {s} origin chain: the value is the CONSTANT 0x{x}, computed by the address form at 0x{x}. No register carried it and no store produced it, so provenance has nothing to watch; the defect is upstream in whatever selected this address\n",
            .{ label, origin.constant, origin.definition.instruction_address },
        ),
        .address_arithmetic => machoCapturePrint(
            "macho-processor: {s} origin chain: the value combines TWO registers at 0x{x} ({s}); the unfollowed operand is {s}. Attributing it to one of them would be a guess, so both are named. Re-run the chain against {s} to take the other branch\n",
            .{
                label,
                origin.definition.instruction_address,
                @tagName(origin.definition.op),
                @tagName(origin.unfollowed),
                @tagName(origin.unfollowed),
            },
        ),
        .stack_load => machoCapturePrint(
            "macho-processor: {s} origin chain: the value was POPPED off the stack at 0x{x}. The producing write is the matching push or frame store, which the instruction stream alone does not name; the stack slot is the thing to watch\n",
            .{ label, origin.definition.instruction_address },
        ),
        else => {},
    }

    if (origin.terminal != .memory_load or origin.definition.source_address == 0) return;
    const seeded = self.provenance_watch.watchPage(origin.definition.source_address, .declared);

    // Which store to go and find depends on what the loaded value *is*. A
    // pointer that names the wrong memory and a slot seeded with a constant
    // that was never a pointer are both "a bad address loaded from memory",
    // and only the first is a byte-order question. Deciding that here keeps
    // the report from sending the reader after a conversion bug whenever the
    // slot simply holds a small integer.
    //
    // No mapping probe is offered: this runtime's mapping table describes the
    // emulated x86 process, while the value is an address in whatever guest
    // that process is itself emulating. Answering "is it mapped" from the
    // wrong address space would be worse than declining to answer, so the
    // plausibility floor is the only discriminator used.
    const value_verdict = zero_adjudication.adjudicate(.{
        .value = origin.definition.source_value,
        .width_bytes = origin.definition.source_bytes,
        .domain = .address,
        .writer = if (self.memory_writes.lookup(origin.definition.source_address) != null) .unknown else .none,
    });

    if (value_verdict.finding == .non_address_constant) {
        machoCapturePrint(
            "macho-processor: {s} origin chain: the value was LOADED from guest memory at 0x{x} (width={d}), and it is 0x{x} — too small to have ever been an address. Provenance is now watching that page (newly_seeded={} entries={d}/{d}); the next store to it is attributed. Byte order is not the question here: no conversion of a real pointer produces this, so the slot was seeded with a non-address constant and that store is the defect (code=0x{x})\n",
            .{
                label,
                origin.definition.source_address,
                origin.definition.source_bytes,
                origin.definition.source_value,
                seeded,
                self.provenance_watch.count,
                self.provenance_watch.entries.len,
                value_verdict.notificationCode() orelse 0,
            },
        );
    } else {
        machoCapturePrint(
            "macho-processor: {s} origin chain: the value was LOADED from guest memory at 0x{x} (width={d}). Provenance is now watching that page (newly_seeded={} entries={d}/{d}); the next store to it is attributed, which names whoever wrote a guest address in the wrong byte order. That store is the defect — the conversion must happen exactly once, at the guest-memory boundary\n",
            .{
                label,
                origin.definition.source_address,
                origin.definition.source_bytes,
                seeded,
                self.provenance_watch.count,
                self.provenance_watch.entries.len,
            },
        );
    }
    if (self.memory_writes.lookup(origin.definition.source_address)) |writer| {
        machoCapturePrint(
            "macho-processor: {s} origin chain: slot already has a recorded writer rip=0x{x} {s} value=0x{x} kind={s} step={d} thread=0x{x}\n",
            .{
                label,
                writer.instruction_address,
                self.metadata.symbolLabel(writer.instruction_address),
                writer.value,
                @tagName(writer.kind),
                writer.step,
                writer.thread,
            },
        );
    }
}

const GuestReturnCandidate = struct {
    value: u64 = 0,
    register_name: []const u8 = "<none>",
    valid: bool = false,
    /// The comparison read the same register the faulting load used as its
    /// base. Its live value is therefore the already-proven zero, not a
    /// snapshot that later evidence could improve.
    aliases_null_base: bool = false,
};

const CallPossibleReturnWitness = struct {
    target: GuestReturnCandidate = .{},
    guest_return: u64 = 0,
    guest_return_valid: bool = false,
    stack_slot: u64 = 0,
    stack_value: u64 = 0,
    stack_value_valid: bool = false,
    compare_rip: u64 = 0,
    branch_rip: u64 = 0,
    branch_target: u64 = 0,
    /// Displacement of the guest-return stack slot as *observed* in the
    /// generated fragment, not as assumed from a build-time constant.
    guest_ret_addr_offset: u64 = 0,
    offset_discovered: bool = false,
};

/// Recover the bounded CALL_POSSIBLE_RETURN witness:
/// `cmp target32, dword [rsp+disp]; je epilogue; mov eax,[ebx]`. The stack slot
/// is authoritative at this point; RCX is not, because the guest return is
/// reloaded into RCX only after the indirection-table load and frame teardown.
/// We deliberately inspect only a 32-byte/15-byte-instruction backward window
/// and require the compare's fall-through branch to land exactly at the faulting
/// load. This is a finite tape window, not a general reverse execution search.
///
/// The stack displacement is **discovered, not assumed**. Requiring it to equal
/// a build-time constant meant that any change to the emitter's stack layout
/// silently produced `compare_rip == 0`, which turned every guest-side proof
/// false and surfaced a layout change as a near-null causality problem. The
/// scan now accepts whatever displacement the compare uses, and the caller
/// cross-checks it against the independent reload observed in the forward
/// window.
///
/// `null_base_reg` is the faulting load's base register. When the comparison
/// turns out to read that same register — the usual emission — the recovered
/// "target" is the proven zero rather than an independent observation, and the
/// candidate is flagged so the transducer decides on that fact instead of
/// waiting for evidence that cannot exist.
fn callPossibleReturnWitness(
    self: anytype,
    load_rip: u64,
    null_base_reg: x64_decoder.RegId,
) CallPossibleReturnWitness {
    var witness = CallPossibleReturnWitness{};

    var start = load_rip -| scan_limits.predicate_witness.max_bytes;
    while (start < load_rip) : (start += 1) {
        const bytes = self.guestMemoryConst(start, 16) orelse continue;
        const compare = decodeInsn(bytes);
        if (compare.op != .cmp_reg32_mem32 or compare.len == 0 or
            compare.has_0x67 or !compare.sib_has_base or compare.sib_has_index or
            compare.rip_relative or compare.sib_base_reg != .ah_sp_esp_rsp or
            start + compare.len >= load_rip)
        {
            continue;
        }
        const branch_rip = start + compare.len;
        const branch_bytes = self.guestMemoryConst(branch_rip, 16) orelse continue;
        const branch = decodeInsn(branch_bytes);
        if (branch.op != .jcc_rel8 and branch.op != .jcc_rel32) continue;
        if (branch.cond != .e or branch.len == 0 or branch_rip + branch.len != load_rip) continue;

        // The displacement the predicate actually used. Everything downstream
        // reads the slot from here, so a layout change moves the slot instead
        // of invalidating the witness.
        witness.guest_ret_addr_offset = compare.addr;
        witness.offset_discovered = true;
        witness.stack_slot = self.regs.rsp +| compare.addr;
        if (self.guestMemoryConst(witness.stack_slot, 4)) |slot_bytes| {
            if (slot_bytes.len >= 4) {
                witness.stack_value = std.mem.readInt(u32, slot_bytes[0..4], .little);
                witness.stack_value_valid = isGuestAddress(self, witness.stack_value);
                witness.guest_return = witness.stack_value;
                witness.guest_return_valid = witness.stack_value_valid;
            }
        }

        const target_value = self.regVal(compare.dst_reg, .bits32);
        witness.target = .{
            .value = target_value,
            .register_name = @tagName(compare.dst_reg),
            .valid = isGuestAddress(self, target_value),
            .aliases_null_base = compare.dst_reg == null_base_reg,
        };
        witness.compare_rip = start;
        witness.branch_rip = branch_rip;
        // JCC `addr` is the signed displacement. Compute the absolute target
        // exactly as the executor does; comparing the raw displacement to the
        // tail RIP would authorize or reject the wrong epilogue.
        witness.branch_target = x64_decoder.highway.relativeControl(
            .conditional_jump,
            branch_rip,
            branch.len,
            @bitCast(branch.addr),
            true,
        ).target;
        return witness;
    }
    return witness;
}

/// Everything known about where the dispatch target's zero came from.
///
/// Runs on both outcomes. It previously ran only on the rejection path, so the
/// moment the transducer started *continuing* past the fault the evidence that
/// justified the continuation stopped being printed — the run acted on a
/// finding it no longer reported.
fn reportZeroOriginEvidence(
    self: anytype,
    candidate: GuestReturnCandidate,
    definition: BoundedDefinition,
) void {
    if (definition.from_memory) {
        var relative_buffer: [256]u8 = undefined;
        const relative = describeAddressAgainstRegisters(self, definition.source_address, &relative_buffer);
        const writer = self.memory_writes.lookup(definition.source_address);
        machoCapturePrint(
            "macho-processor: bounded dispatch FST source slot: register={s} address=0x{x} = {s} width_read=64 value=0x{x} readable={}; this is the field the dispatch target was loaded from\n",
            .{ candidate.register_name, definition.source_address, relative, definition.source_value, definition.source_readable },
        );
        if (writer) |entry| {
            machoCapturePrint(
                "macho-processor: bounded dispatch FST source slot: last writer rip=0x{x} {s} value=0x{x} kind={s} step={d} thread=0x{x}\n",
                .{ entry.instruction_address, self.metadata.symbolLabel(entry.instruction_address), entry.value, @tagName(entry.kind), entry.step, entry.thread },
            );
        } else {
            // Provenance is no longer a flag the operator had to set
            // before knowing which address mattered: the watch set
            // learns structure pages from generated code as it runs.
            // Report which of the three states this actually is.
            const watched = self.provenance_watch.covers(definition.source_address);
            machoCapturePrint(
                "macho-processor: bounded dispatch FST source slot: no writer recorded. watched={} globally_armed={} watch(entries={d}/{d} overflows={d} recorded_stores={d} rejected_stores={d})\n",
                .{
                    watched,
                    self.write_diagnostics_armed,
                    self.provenance_watch.count,
                    self.provenance_watch.entries.len,
                    self.provenance_watch.overflows,
                    self.provenance_watch.recorded,
                    self.provenance_watch.rejected,
                },
            );
            // An absence of provenance only speaks about the guest when the
            // storage under the address is still the storage the guest wrote
            // to. Check that before drawing the conclusion, not after.
            if (self.guest_lifetime.covers(definition.source_address)) |record| {
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST source slot: this address holds no writer BECAUSE ROSETTE DISCARDED ITS BACKING — range base=0x{x} length={d} reason={s} discards={d} last_discard_step={d}. Provenance for this range was retired at that point, so \"nothing ever stored here\" is a fact about the runtime, not about the guest. The missing evidence is Rosette's, not the program's\n",
                    .{ record.base, record.size, @tagName(record.reason), record.generation, record.step },
                );
            } else if (watched or self.write_diagnostics_armed) {
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST source slot: this address WAS under write provenance, holds no entry, and its backing was never discarded by the runtime — nothing ever stored here. The zero is an UNINITIALISED field, not a cleared one: look for the guest store that should have written it (an unimplemented instruction or an initialisation path Rosette never runs), not for a corrupting writer\n",
                    .{},
                );
            } else {
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST source slot: this address was NOT under write provenance, so nothing can be concluded about its writer. The watch seeds from generated-code structure-field loads; if it filled before reaching this page, raise ownership.watch.max_entries or set ROSETTE_MACHO_WRITE_DIAGNOSTICS=1\n",
                    .{},
                );
            }
        }
    }
    // The field-access shape over the whole run. This is what
    // separates "the store is missing" from "the store ran and
    // produced the wrong value" — two different bugs that look
    // identical at the fault site, because the evidence for the
    // first is an absence measured elsewhere.
    if (definition.from_memory and definition.source_address != 0) {
        const base_reg_value = self.regs.rsi;
        const field_base = if (definition.source_address >= base_reg_value)
            base_reg_value
        else
            0;
        if (field_base != 0) {
            const offset = definition.source_address - field_base;
            if (self.guest_fields.lookup(field_base, offset)) |field| {
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST field shape: base=0x{x} offset=0x{x} reads={d} writes={d} read_only={}; {s}\n",
                    .{
                        field_base,                offset, field.reads, field.writes,
                        field.access().readOnly(),
                        if (field.access().readOnly())
                            "generated code READ this field and NEVER WROTE it in the entire run — the store the guest expected is missing. This is an emulation gap, not a corrupted value: look for the instruction or kernel path that should have written it"
                        else
                            "generated code both read and wrote this field, so a store did run — the value is wrong rather than absent. Arm write provenance on the page to name the writer",
                    },
                );
            } else {
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST field shape: base=0x{x} offset=0x{x} NOT OBSERVED — no generated-code access to this field was profiled, so the load that faulted is the first and only one. Nothing can be concluded about missing stores from this run\n",
                    .{ field_base, offset },
                );
            }
            var neighbourhood: [12]@import("guest_structure").Field = undefined;
            const found = self.guest_fields.neighbours(field_base, offset, 0x20, &neighbourhood);
            var index: usize = 0;
            while (index < found) : (index += 1) {
                const field = neighbourhood[index];
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST field neighbour: base=0x{x} offset=0x{x} reads={d} writes={d}\n",
                    .{ field_base, field.offset, field.reads, field.writes },
                );
            }
        }
    }
}

/// Everything the aliasing case decided on, printed on every outcome.
///
/// The aliasing rejections are about the *recovered* value, not about the
/// register file, so a run has to see what each source actually said. Otherwise
/// it reads "target not proven" for a target that was proven — zero — and the
/// search goes to the transducer rather than to whoever cleared the register.
/// The same is true of a continuation: acting on evidence without printing it
/// leaves a reader the verdict and none of the reasoning.
fn reportAliasingEvidence(
    self: anytype,
    candidate: GuestReturnCandidate,
    witness: CallPossibleReturnWitness,
    definition: BoundedDefinition,
    cleared: ?near_null_causality.ClearedValue,
    source: bounded_dispatch_fst.Machine.ClearedTargetSource,
    value: u64,
) void {
    if (!candidate.aliases_null_base) return;
    machoCapturePrint(
        "macho-processor: bounded dispatch FST evidence: base={s} live=0x0 (the fault's own definition) source={s} value=0x{x} guest_return_slot=[rsp+0x{x}]=0x{x}; a redirect along the guest predicate edge requires the recovered value to equal the return slot\n",
        .{
            candidate.register_name,
            @tagName(source),
            value,
            witness.guest_ret_addr_offset,
            witness.stack_value,
        },
    );
    machoCapturePrint(
        "macho-processor: bounded dispatch FST evidence: retained_history available={} value=0x{x} distance={d}; definition_reread found={} instruction=0x{x} op={s} distance={d} from_memory={} source_address=0x{x} readable={} value=0x{x} from_immediate={} immediate=0x{x}\n",
        .{
            cleared != null,
            if (cleared) |recovered| recovered.value else 0,
            if (cleared) |recovered| recovered.retained_distance else 0,
            definition.found,
            definition.instruction_address,
            @tagName(definition.op),
            definition.distance,
            definition.from_memory,
            definition.source_address,
            definition.source_readable,
            definition.source_value,
            definition.from_immediate,
            definition.immediate,
        },
    );
    // Two independent answers to one question. When they disagree, the run must
    // say so rather than quietly report only the winner: a history sample that
    // survived eviction is not a claim about recency, and a reader comparing it
    // against the re-read is entitled to know they differ.
    if (cleared != null and definition.found and definition.from_memory and definition.source_readable) {
        const history32: u32 = @truncate(cleared.?.value);
        const reread32: u32 = @truncate(definition.source_value);
        if (history32 != reread32) {
            machoCapturePrint(
                "macho-processor: bounded dispatch FST evidence DISAGREEMENT: definition_reread=0x{x} retained_history=0x{x} (distance={d}); the re-read is authoritative — it reads the memory the defining instruction reads, at fault time, and owes nothing to ring retention. The history value is the most recent sample that escaped eviction from a bounded window shared with every guest thread, which is not the same as the most recent value\n",
                .{ reread32, history32, cleared.?.retained_distance },
            );
        }
    }
    reportZeroOriginEvidence(self, candidate, definition);
    machoCapturePrint(
        "macho-processor: bounded dispatch FST block: origin={s} convergence={s} window_bytes={d} block_start=0x{x} block_length={d} anchor=0x{x} register={s}; {s}\n",
        .{
            @tagName(definition.origin),
            @tagName(definition.convergence),
            definition.window_bytes,
            definition.block_start,
            definition.block_length,
            witness.compare_rip,
            candidate.register_name,
            switch (definition.origin) {
                .defined_in_block => "the value was produced in this fragment; its source is reported above",
                .live_in_to_block => "the register is never written in this fragment — it is live-in from a predecessor block, so the producer is upstream of the reconstructed block and neither evidence source can reach it from here",
                .block_unresolved => "no candidate block start decoded cleanly onto the anchor, so the fragment could not be reconstructed; the bytes before the comparison are not a decodable instruction stream at any offset in the window",
            },
        },
    );
}

/// How much of this block the bounded machine can get through, at the moment it
/// could not get through this site.
///
/// One line, at a halt only. The individual report says what stopped here; this
/// says whether that is one gap or the shape of the run — the difference between
/// investigating this instruction and investigating the recogniser that failed
/// to claim it.
fn reportDispatchCoverage(self: anytype, block_start: u64) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "dispatch_census")) return;
    const overall = self.dispatch_census.coverage();
    const block = self.dispatch_census.coverageForBlock(block_start);
    machoCapturePrint(
        "macho-processor: dispatch coverage: this_block(start=0x{x}) sites={d} traversed={d} mixed={d} halting={d} | run sites={d} traversed={d} mixed={d} halting={d} observations={d} passes={d} halts={d} overflow_sites={d}; {s}\n",
        .{
            block_start,
            block.sites,
            block.clean,
            block.mixed,
            block.halting,
            overall.sites,
            overall.clean,
            overall.mixed,
            overall.halting,
            self.dispatch_census.observations,
            self.dispatch_census.traversals,
            self.dispatch_census.halts,
            self.dispatch_census.overflow_sites,
            if (overall.halting == 0 and overall.mixed == 0)
                "every site the machine has met was traversed; this is the first gap"
            else if (overall.mixed != 0)
                "at least one site is sometimes traversable and sometimes not — the difference between those two register states is the defect, and it is more informative than any always-halting site"
            else
                "more than one distinct site halts, so this is the shape recogniser's coverage rather than one stubborn instruction",
        },
    );
}

/// Effective addresses at or below this are near-null: a pointer that was
/// never set, or one that was set and then lost most of its value. Above it,
/// a protection fault is about the page, not about the pointer.
const near_null_effective_limit: u64 = 0x10000;

fn protectionFaultGuestEffective(
    mapping_effective: u64,
    base_is_anchor: bool,
    index_value: u64,
    index_scale_log2: u2,
    displacement: u64,
    address_is_32_bit: bool,
) u64 {
    if (!base_is_anchor) return mapping_effective;
    var effective = displacement +% (index_value << index_scale_log2);
    if (address_is_32_bit) effective = @as(u32, @truncate(effective));
    return effective;
}

test "protection fault near-null classification uses translated guest pointer" {
    // A write-watch activation starts at the protected page, making the host
    // mapping-relative offset small. The translated index remains the actual
    // guest pointer and must keep this out of near-null diagnostics.
    try std.testing.expectEqual(
        @as(u64, 0xA510_C1C0),
        protectionFaultGuestEffective(0x1C0, true, 0xA510_C1C0, 0, 0, false),
    );
    // The genuine fault from the same run carried guest pointer 1 and still
    // belongs to the causality path.
    try std.testing.expectEqual(
        @as(u64, 1),
        protectionFaultGuestEffective(1, true, 1, 0, 0, false),
    );
    try std.testing.expectEqual(
        @as(u64, 0x1C0),
        protectionFaultGuestEffective(0x1C0, false, 0xA510_C1C0, 0, 0, false),
    );
}

/// What produced the address a protection fault refused.
///
/// The fault site knew the address and the instruction *name* and nothing else,
/// so a pointer that arrived as `0x1` reached the guest's signal handler with
/// no record of where the `1` came from — and a near-null protection fault is
/// almost never a question about the page. The page is protected deliberately;
/// the pointer is the finding.
///
/// This reuses the evidence the near-null owner already produces rather than
/// growing a second version of it: full operand decode, the register file, the
/// byte-order survey, and a bounded def-use walk on the base register through
/// register moves to whatever actually produced the value.
///
/// Runs only on a confirmed protection fault, which is already a terminal-class
/// event, and only when the effective address is near-null. A fault at a real
/// address gets the page diagnostics it always did.
/// Record a protection fault that landed in the Xenos register aperture.
///
/// The aperture's pages are unreadable by design — that is the mechanism, not a
/// defect — so every register access the guest performs arrives here and
/// nowhere else. Counting them is what lets the run state positively that the
/// title did or did not program the GPU, instead of inferring it from a log
/// line nobody wrote.
fn observeRegisterApertureAccess(self: anytype, address: u64, access: GuestAccess, delivered: bool) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_register_aperture")) return;
    // The aperture is a fact in *guest* terms and the fault is in host terms.
    // The emulator's own discovered mapping base is the only thing that relates
    // them, so the range is derived from it rather than from a constant — a
    // hardcoded membase would silently attribute unrelated faults to GPU
    // registers the first time the mapping moved.
    const aperture_host = self.xenia_memory_views.virtualHostAddress(
        device_tree.gpu.xenos.register_aperture_base,
    ) orelse return;
    if (address < aperture_host) return;
    const offset = address - aperture_host;
    if (offset >= device_tree.gpu.xenos.register_aperture_size) return;

    self.gpu_register_aperture.observe(
        device_tree.gpu.xenos.register_aperture_base + offset,
        access == .write,
        storedValueForFault(self),
        if (delivered) .delivered else .undelivered,
        self.regs.rip,
        self.active_guest_thread,
        self.executed_steps,
    );
    // A delivered store is the point at which the emulator's register
    // handler accepted the write.  Keep a backend-neutral mirror as well so
    // the Xenos PM4/state path can explain draws that were preceded by direct
    // MMIO programming rather than by a type-0 ring packet.  This mirror never
    // makes an undelivered fault look successful.
    if (delivered and access == .write and address % device_tree.gpu.xenos.register_stride == 0) {
        if (device_tree.gpu.xenos.registerIndexOf(device_tree.gpu.xenos.register_aperture_base + offset)) |register| {
            self.gpu_xenos_runtime.observeRegisterWrite(@intCast(register), @truncate(storedValueForFault(self)));
        }
    }
}

/// The value a faulting store was trying to write, when the instruction form
/// makes it recoverable. A register write whose value is unknown says almost
/// nothing — the ring base register's *value* is the ring address — so this is
/// worth recovering, and worth reporting as zero rather than guessed when the
/// form does not carry it.
fn storedValueForFault(self: anytype) u64 {
    const decoded = decodeStatic(self, self.regs.rip) orelse return 0;
    return switch (decoded.op) {
        .mov_mem8_reg8,
        .mov_mem16_reg16,
        .mov_mem32_reg32,
        .mov_mem64_reg64,
        .movbe_mem_reg,
        => self.regVal(decoded.src_reg, decoded.size),
        .mov_mem8_imm8, .mov_mem16_imm16, .mov_mem32_imm32, .mov_mem64_imm32 => decoded.imm,
        else => 0,
    };
}

fn reportProtectionFaultOperands(self: anytype, address: u64, bytes: u8, access: GuestAccess) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_address_space")) return;
    // Relative to the mapping the address is actually in. The process image
    // base is the wrong origin for a sparse address — it yields an enormous
    // offset for every one of them, which is how this reporter silently skipped
    // the exact faults it was written for.
    const origin = self.sparse_memory.containingMappingBase(address) orelse self.mem_base;
    const mapping_effective = address -| origin;
    const decoded = decodeStatic(self, self.regs.rip) orelse return;
    const base_value = if (decoded.sib_has_base) self.regVal(decoded.sib_base_reg, .bits64) else 0;
    const base_is_anchor = decoded.sib_has_base and decoded.sib_has_index and
        !isGuestMappedValue(self, base_value) and
        self.sparse_memory.containingMappingBase(base_value) == base_value;
    const index_value = if (decoded.sib_has_index) self.regVal(decoded.sib_index_reg, .bits64) else 0;

    // Xenia's translated guest accesses are emitted as
    // `[guest_membase + guest_address]`. A narrow sparse activation may start
    // at the protected guest page, so `address - activation_base` can be 0x1c0
    // even though the guest pointer is the perfectly valid 0xA510C1C0. Calling
    // that near-null sent the causality machinery after a healthy JIT store.
    // Once the base is proven to be the mapping anchor, the index (plus the
    // instruction displacement) is the guest-visible pointer that must be
    // tested. For ordinary address forms, retain the mapping-relative value.
    const effective = protectionFaultGuestEffective(
        mapping_effective,
        base_is_anchor,
        index_value,
        decoded.sib_scale,
        decoded.addr,
        decoded.has_0x67,
    );
    if (effective > near_null_effective_limit) return;

    machoCapturePrint(
        "macho-processor: near-null protection fault: rip=0x{x} address=0x{x} guest_effective=0x{x} bytes={d} access={s} op={s} len={d} has_0x67={} base({s})=0x{x} index({s},scale={d})=0x{x} displacement=0x{x} rip_relative={} symbol={s}; the page is protected deliberately, so the pointer is the finding, not the page\n",
        .{
            self.regs.rip,
            address,
            effective,
            bytes,
            @tagName(access),
            @tagName(decoded.op),
            decoded.len,
            decoded.has_0x67,
            if (decoded.sib_has_base) @tagName(decoded.sib_base_reg) else "<none>",
            base_value,
            if (decoded.sib_has_index) @tagName(decoded.sib_index_reg) else "<none>",
            @as(u8, 1) << decoded.sib_scale,
            index_value,
            decoded.addr,
            decoded.rip_relative,
            self.metadata.symbolLabel(self.regs.rip),
        },
    );
    // The register file plus the byte-order survey: a near-null pointer whose
    // 64-bit byte reversal is a guest address is a conversion defect, not a
    // missing store, and the two want opposite investigations.
    near_null_causality.dumpTerminal(self, effective);
    // Follow the operand that *varies*, not whichever one is written first.
    //
    // Translated guest loads are emitted as `[membase + guest_address]`, so the
    // base register holds a runtime constant and the index holds the value that
    // decides the address. Walking the base spends the whole retained tape
    // proving the membase never changed and then reports UNDECIDABLE — a true
    // statement about the wrong operand, and it reads like a failure of the
    // walk rather than a question that was never asked.
    //
    // A base that is not a plausible guest value and does not vary is the
    // membase or an equivalent anchor; when an index is present alongside it,
    // the index is the causal operand.
    const causal: ?x64_decoder.RegId = if (base_is_anchor)
        decoded.sib_index_reg
    else if (decoded.sib_has_base)
        decoded.sib_base_reg
    else if (decoded.sib_has_index)
        decoded.sib_index_reg
    else
        null;
    if (causal) |register| {
        machoCapturePrint(
            "macho-processor: near-null protection fault: causal operand={s} (base={s} anchor={} index={s}); {s}\n",
            .{
                @tagName(register),
                if (decoded.sib_has_base) @tagName(decoded.sib_base_reg) else "<none>",
                base_is_anchor,
                if (decoded.sib_has_index) @tagName(decoded.sib_index_reg) else "<none>",
                if (base_is_anchor)
                    "the base register holds a mapping anchor (a guest membase), so it is a constant by construction and cannot be the cause. The index carries the guest address and is the operand worth following"
                else
                    "the base register is the addressing operand that varies",
            },
        );
        reportValueOrigin(self, "near-null protection fault", boundedValueOrigin(self, self.regs.rip, register));
    }
}

/// A null base register that is not null: the address is there, byte-reversed.
///
/// A 32-bit guest address whose eight bytes were reversed — a 64-bit load from
/// big-endian guest memory that was never converted — has **zero in its low
/// 32 bits**. Every 32-bit addressing form then computes an effective address of
/// zero, and the fault presents as a null pointer, several instructions after
/// the load that actually went wrong. The whole near-null machinery downstream
/// answers questions about that zero, correctly, and about the wrong thing.
///
/// The register still holds the address. Reversing it produces a guest address,
/// and reversing an unrelated value essentially never does — which is what makes
/// this a decision and not a guess. The same standard the endian contract
/// already applies at one width, applied where the null is manufactured.
///
/// The repair corrects the *register*, not memory: the value in the register is
/// what was mis-converted, and rewriting guest memory to compensate would leave
/// a second wrong value behind for the next reader. Recorded as a host repair so
/// no later diagnosis attributes the corrected register to the guest.
///
/// Returns the corrected effective address when it acted.
fn tryRepairByteReversedBase(self: anytype, classification: GeneratedFaultClassification) ?u64 {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "generated_byte_order_repair")) return null;
    const fault = classification.fault;
    if (!fault.sib_has_base or fault.sib_has_index or fault.rip_relative) return null;
    // Only a zero *effective* address is manufactured this way; a non-zero one
    // is a different question and this must not answer it.
    if (classification.base_value != 0) return null;

    const whole = self.regVal(fault.sib_base_reg, .bits64);
    const Window = struct {
        state: @TypeOf(self),
        fn isGuest(ctx: @This(), address: u64) bool {
            return isGuestAddress(ctx.state, address);
        }
    };
    const finding = byte_order.survey.classify(Window, .{ .state = self }, whole, Window.isGuest);
    if (finding.order != .reversed64 or !finding.low_half_zero) return null;
    // The corrected address has to be usable, or the repair has proven nothing.
    if (self.sparse_memory.bytesConst(finding.corrected, 1) == null and
        translateGuest(self, finding.corrected, 1, .read) == null)
    {
        return null;
    }
    if (!recoveryLoopAllowed(&self.generated_byte_order_repair, "byte_order_base", self.regs.rip)) {
        return null;
    }

    self.generated_byte_order_repair.note();
    self.setReg(fault.sib_base_reg, .bits64, finding.corrected);
    noteDispatchSite(self, self.regs.rip, .byte_order_repair, .traversed, 0);
    if (self.generated_byte_order_repair.shouldLog()) {
        // Follow the reversed value back to whatever produced it. The repair
        // keeps the run alive; this is what makes the next run able to name the
        // store that skipped its conversion.
        reportValueOrigin(self, "byte-reversed base", boundedValueOrigin(self, self.regs.rip, fault.sib_base_reg));
        machoCapturePrint(
            "macho-processor: byte-reversed base repaired #{d}: thread=0x{x} rip=0x{x} base={s} observed=0x{x} corrected=0x{x} readable=true; the register was NOT null — it held a guest address whose eight bytes were never converted from big-endian, which puts zero in the low half and makes every 32-bit addressing form compute a null. The near-null path is not entered for this fault\n",
            .{
                self.generated_byte_order_repair.recoveries,
                self.active_guest_thread,
                self.regs.rip,
                @tagName(fault.sib_base_reg),
                whole,
                finding.corrected,
            },
        );
        machoCapturePrint(
            "macho-processor: byte-reversed base: the conversion is the defect, not this repair. A 64-bit load of guest memory produced a value in host byte order; see the BYTE ORDER SURVEY for whether this run has one such site or several\n",
            .{},
        );
    }
    return finding.corrected +% fault.addr;
}

/// Record a dispatch-recovery outcome against the site's census.
///
/// Individual recoveries each report themselves and every report reads like the
/// last. The census is what says whether the run met one stubborn site or forty,
/// and whether the sites it halts on are the ones it always halts on.
pub fn noteDispatchSite(
    self: anytype,
    rip: u64,
    family: dispatch_recovery.Family,
    outcome: dispatch_recovery.Outcome,
    halt_reason: u16,
) void {
    noteDispatchSiteInBlock(self, rip, 0, family, outcome, halt_reason);
}

/// As above, for callers that already reconstructed the containing block.
/// Block reconstruction is the expensive part of this diagnosis, so it is never
/// repeated here: a site whose block is unknown is recorded with zero, which the
/// census reports as its own group rather than silently merging.
pub fn noteDispatchSiteInBlock(
    self: anytype,
    rip: u64,
    block_start: u64,
    family: dispatch_recovery.Family,
    outcome: dispatch_recovery.Outcome,
    halt_reason: u16,
) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "dispatch_census")) return;
    self.dispatch_census.note(rip, block_start, family, outcome, halt_reason);
}

/// Run the fail-closed bounded dispatch transducer for the exact Xenia
/// address-size-override layout. Returns true only after it has installed a
/// proven continuation; callers may then finish the current scalar load without
/// advancing RIP. The load's destination register still receives the zero the
/// caller returns — harmless on both routes, since the epilogue and the host
/// caller each discard EAX, and it is the same behaviour the host frame return
/// has always had.
///
/// The caller reaches this only via `classifyGeneratedScalarFault` returning
/// `.null_base_dispatch`, which is the sole definition of this layout.
fn tryRedirectBoundedNullDispatch(self: anytype, fault: DecodedInsn) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "bounded_dispatch")) return false;

    const exact_layout = isBoundedDispatchIndirectionForm(fault) and
        isBaseOnlyZeroDisplacementForm(fault);
    if (!exact_layout) return false;

    const witness = callPossibleReturnWitness(self, self.regs.rip, fault.sib_base_reg);
    const candidate = witness.target;
    // When the comparison read the null base itself, the register file cannot
    // testify about the target — the fault is defined by that register being
    // zero. Retained execution history is the only admissible witness, so ask
    // it for the value the register carried before it was cleared. Recovered
    // only in the aliasing case: elsewhere the live value is authoritative and
    // history would be a second, weaker opinion about the same question.
    const cleared = if (candidate.aliases_null_base)
        near_null_causality.lastNonZeroBeforeClear(self, fault.sib_base_reg, 0xFFFF_FFFF)
    else
        null;
    // Second, ring-independent source: the generated code still records where
    // the base register was supposed to get its value. Decode backwards from
    // the comparison (a known instruction boundary) to the defining
    // instruction, and re-read its memory source now. This is what answers a
    // first-observation fault, where the shared 256-entry instruction ring has
    // nothing to say about a thread that has been running for a billion steps.
    const definition = if (candidate.aliases_null_base and witness.compare_rip != 0)
        boundedBaseDefinition(self, witness.compare_rip, fault.sib_base_reg)
    else
        BoundedDefinition{};
    // Admissibility is equality with the independently-read guest return slot,
    // whichever source supplied the value. The *order* of preference is not
    // arbitrary, and it used to be backwards.
    //
    // Retained history won by default on the reasoning that an observation of
    // the register beats a reconstruction of where it should have come from.
    // That reasoning does not survive the ring's actual shape:
    // `lastNonZeroBeforeClear` walks back to the most recent *surviving*
    // non-zero sample with no recency bound, over a bounded window shared with
    // every other guest thread. On a thread a billion steps in, the surviving
    // sample is whatever escaped eviction rather than whatever was recent — in
    // the run that motivated this it produced 0x182474c0, an unrelated host
    // pointer, for a register whose defining load was fifteen bytes away.
    //
    // The definition re-read asks the direct question instead: find the
    // instruction that defined the register and read the memory it reads, now.
    // It is available on a first observation, owes nothing to retention, and is
    // the value the guest itself would have loaded. History is now the
    // fallback for when the definition cannot be reconstructed, and a
    // disagreement between the two is reported rather than silently resolved.
    const definition_readable = definition.found and definition.from_memory and
        definition.source_readable;
    const evidence: struct { value: u64, source: bounded_dispatch_fst.Machine.ClearedTargetSource } =
        if (definition_readable)
            .{ .value = @as(u32, @truncate(definition.source_value)), .source = .definition_reread }
        else if (cleared) |recovered|
            .{ .value = recovered.value, .source = .retained_history }
        else
            .{ .value = 0, .source = .none };
    const tail = boundedTailShape(self, self.regs.rip, fault.len);
    if (comptime @hasField(State, "generated_dispatch_compare_witnesses") and
        @hasField(State, "generated_dispatch_compare_misses"))
    {
        if (witness.compare_rip != 0) {
            self.generated_dispatch_compare_witnesses +|= 1;
        } else {
            self.generated_dispatch_compare_misses +|= 1;
        }
    }
    // One shared definition of the host-frame proof, so tightening it moves all
    // three consumers together instead of only this one.
    const frame_proof = hostFrameProof(self);
    const frame_pointer = frame_proof.frame_pointer;
    const saved_frame_pointer = frame_proof.saved_frame_pointer;
    const host_return = frame_proof.return_address;
    const branch_targets_dead_epilogue = branchTargetsDeadDispatchEpilogue(
        witness.branch_target,
        tail.transfer_rip,
        tail.transfer_len,
    );

    // The zero is explained when the defining instruction was located and its
    // memory source re-read. Which explanation it is depends on whether that
    // memory is still the memory the guest's stores went to: a range whose
    // backing Rosette replaced or re-homed reads zero for reasons that have
    // nothing to do with the guest, and reporting that as an uninitialised
    // field sends the reader after a store that may well have run.
    const discarded_source = if (definition.found and definition.from_memory)
        guestRangeDiscarded(self, definition.source_address)
    else
        null;
    const zero_origin: bounded_dispatch_fst.Machine.ZeroOrigin =
        if (!(definition.found and definition.from_memory and
            definition.source_readable and definition.source_value == 0))
            .unidentified
        else if (discarded_source != null)
            .discarded_backing
        else
            .uninitialised_field;

    const output = self.bounded_dispatch.evaluate(.{
        .xenia_compat = self.has_xenia_compat,
        .generated_executable = self.sparse_memory.isExecutable(self.regs.rip, 1),
        .address32_eax_from_ebx = exact_layout,
        .base_value32 = @truncate(self.regs.rbx),
        .guest_target_aliases_null_base = candidate.aliases_null_base,
        .guest_target = candidate.value,
        .guest_return = witness.guest_return,
        .guest_target_valid = candidate.valid and witness.compare_rip != 0,
        .guest_return_valid = witness.guest_return_valid and witness.compare_rip != 0,
        .cleared_target_retained = evidence.source != .none and witness.compare_rip != 0,
        .cleared_target = evidence.value,
        .cleared_target_source = evidence.source,
        .predicate_edge_target = if (branch_targets_dead_epilogue) witness.branch_target else 0,
        .zero_origin = zero_origin,
        .allow_assumed_continuation = self.allow_assumed_dispatch_continuation,
        .tail_jmp_rax_found = tail.jmp_rax,
        .dead_epilogue_found = tail.dead_epilogue,
        .branch_targets_dead_epilogue = branch_targets_dead_epilogue,
        .host_return_not_guest = frame_proof.return_not_guest,
        .frame_pointer = if (frame_proof.frame_aligned) frame_pointer else 0,
        .saved_frame_pointer = saved_frame_pointer,
        .saved_frame_pointer_valid = frame_proof.saved_frame_pointer_valid,
        .host_return = host_return,
        .host_return_executable = frame_proof.return_executable,
    });

    const should_log = recovery_ledger.throttled(self.bounded_dispatch.observations);
    // Census before reporting. A halt that cannot say how many other sites in
    // this block were traversed is a report with no sense of scale, and the
    // scale is the thing that decides whether to chase this site or the shape
    // recogniser that failed to claim it.
    noteDispatchSiteInBlock(
        self,
        self.regs.rip,
        definition.block_start,
        .bounded_dispatch,
        if (output.continues()) .traversed else .halted,
        @intFromEnum(output.reason),
    );
    if (!output.continues()) {
        if (should_log) {
            machoCapturePrint(
                "macho-processor: bounded dispatch FST rejected 0x67 null-base load: thread=0x{x} load_rip=0x{x} state={s} reason={s} candidate={s}:0x{x} candidate_aliases_null_base={} guest_return=0x{x} rcx=0x{x} stack_slot=0x{x} stack_value=0x{x} compare_rip=0x{x} branch_rip=0x{x} branch_target=0x{x} transfer_rip=0x{x} transfer_len={d} distance={d} jmp_rax={} dead_epilogue={} branch_to_epilogue={} host_return_not_guest={} frame_return=0x{x} executable={}; refusing zero-fill\n",
                .{ self.active_guest_thread, self.regs.rip, @tagName(output.state), @tagName(output.reason), candidate.register_name, candidate.value, candidate.aliases_null_base, witness.guest_return, self.regs.rcx, witness.stack_slot, witness.stack_value, witness.compare_rip, witness.branch_rip, witness.branch_target, tail.transfer_rip, tail.transfer_len, tail.transfer_distance, tail.jmp_rax, tail.dead_epilogue, branch_targets_dead_epilogue, frame_proof.return_not_guest, host_return, frame_proof.return_executable },
            );
            reportDispatchCoverage(self, definition.block_start);
            reportAliasingEvidence(self, candidate, witness, definition, cleared, evidence.source, evidence.value);
            // The guest-return stack displacement is discovered, then confirmed
            // against the reload in the tail. Report both, and say plainly when
            // they disagree or when the observed layout has moved: that is a
            // layout finding, not a missing witness.
            machoCapturePrint(
                "macho-processor: bounded dispatch FST layout: guest_ret_addr_offset discovered={} value=0x{x} tail_reload_seen={} tail_reload_offset=0x{x} agree={} previously_observed=0x{x} matches_previous={}\n",
                .{
                    witness.offset_discovered,
                    witness.guest_ret_addr_offset,
                    tail.return_slot_reload_seen,
                    tail.return_slot_reload_offset,
                    witness.offset_discovered and tail.return_slot_reload_seen and
                        witness.guest_ret_addr_offset == tail.return_slot_reload_offset,
                    OBSERVED_TYPICAL_GUEST_RET_ADDR_OFFSET,
                    witness.offset_discovered and
                        witness.guest_ret_addr_offset == OBSERVED_TYPICAL_GUEST_RET_ADDR_OFFSET,
                },
            );
        }
        return false;
    }

    // A continuation that lands back on the same load is not progress. All
    // three routes out of this transducer re-enter guest execution, so the loop
    // guard has to cover them; without it a permanently uninitialised field
    // would continue forever instead of surfacing.
    if (!recoveryLoopAllowed(&self.bounded_dispatch_recoveries, "bounded_dispatch", self.regs.rip)) return false;

    // An assumption is not a proof, and the run must say so every time it acts
    // on one — not only in the summary. This is the line that tells a reader
    // the guest state after this point is Rosette's construction, not the
    // program's.
    if (output.assumed()) {
        switch (output.zero_origin) {
            .discarded_backing => {
                const record = discarded_source.?;
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST CONTINUING ON A STATED ASSUMPTION #{d}: load_rip=0x{x} target=provably zero, origin=field at 0x{x} ({s}) inside a range ROSETTE DISCARDED — base=0x{x} length={d} reason={s} discards={d} last_discard_step={d}. The field reads zero, but the storage behind it was replaced by the runtime, so this is NOT evidence that the guest failed to write it: any store it made went to memory that no longer exists. Do not look for a missing guest store on the strength of this line; look at why the range is being re-mapped. Returning the abandoned frame to its host caller 0x{x} so the NEXT failure becomes observable. Guest state past this point is assumed, not emulated\n",
                    .{
                        self.bounded_dispatch.assumed_continuations,
                        self.regs.rip,
                        definition.source_address,
                        self.metadata.symbolLabel(definition.instruction_address),
                        record.base,
                        record.size,
                        @tagName(record.reason),
                        record.generation,
                        record.step,
                        output.host_rip,
                    },
                );
            },
            else => {
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST CONTINUING ON A STATED ASSUMPTION #{d}: load_rip=0x{x} target=provably zero, origin=uninitialised field at 0x{x} ({s}), backing never discarded by the runtime. Everything provable was proven — dispatch shape, epilogue, branch edge, host frame — but what the guest intended cannot be, because the field it would have branched through was never written. Returning the abandoned frame to its host caller 0x{x} so the run continues and the NEXT failure becomes observable. Guest state past this point is assumed, not emulated; treat subsequent diagnostics accordingly\n",
                    .{
                        self.bounded_dispatch.assumed_continuations,
                        self.regs.rip,
                        definition.source_address,
                        self.metadata.symbolLabel(definition.instruction_address),
                        output.host_rip,
                    },
                );
            },
        }
        // The evidence this continuation rests on. This reporting documented
        // itself as running on both outcomes and did not: it was reached only
        // from the rejection branch, so from the moment the transducer started
        // continuing past the fault, the run acted on a finding it no longer
        // printed. A reader of that log could see the verdict and never the
        // reasoning.
        if (should_log) {
            reportAliasingEvidence(self, candidate, witness, definition, cleared, output.cleared_target_source, evidence.value);
        }
    }

    // Only this family's ledger. The transducer used to bump the null-scalar
    // read counter and the frame-return counter as well, which made both of
    // those report work they had not done; the redirect kind below already says
    // which continuation was taken. `last_generated_null_read_rip` is likewise
    // left alone: it records a *zero-filled read*, and this path never performs
    // one, so claiming it would fabricate a linkage for the transfer recoveries.
    self.bounded_dispatch_recoveries.note();
    self.pending_control_transfer = null;
    if (should_log) {
        machoCapturePrint(
            "macho-processor: bounded dispatch FST redirect #{d}: thread=0x{x} load_rip=0x{x} encoding=67_8b_03 kind={s} candidate={s}:0x{x} aliases_null_base={} evidence_source={s} evidence_value=0x{x} guest_return=0x{x} stack_slot=0x{x} compare_rip=0x{x} branch_rip=0x{x} branch_target=0x{x} transfer_rip=0x{x} transfer_len={d} distance={d} target=0x{x} ({s}) rsp=0x{x}->0x{x} rbp=0x{x}->0x{x}; exact CALL_POSSIBLE_RETURN witness\n",
            .{
                self.bounded_dispatch.redirects,
                self.active_guest_thread,
                self.regs.rip,
                @tagName(output.redirect),
                candidate.register_name,
                candidate.value,
                candidate.aliases_null_base,
                @tagName(output.cleared_target_source),
                evidence.value,
                witness.guest_return,
                witness.stack_slot,
                witness.compare_rip,
                witness.branch_rip,
                witness.branch_target,
                tail.transfer_rip,
                tail.transfer_len,
                tail.transfer_distance,
                output.host_rip,
                self.metadata.symbolLabel(output.host_rip),
                self.regs.rsp,
                if (output.rewritesStack()) output.host_rsp else self.regs.rsp,
                self.regs.rbp,
                if (output.rewritesStack()) output.host_rbp else self.regs.rbp,
            },
        );
    }
    // Only the host frame return substitutes for a teardown that will never
    // run. The predicate edge leads into Xenia's epilogue, which performs its
    // own `add rsp,imm; ret` — rewriting the stack here would deallocate the
    // frame twice and make the `ret` pop a local.
    if (output.rewritesStack()) {
        self.regs.rsp = output.host_rsp;
        self.regs.rbp = output.host_rbp;
    }
    self.regs.rip = output.host_rip;
    return true;
}

/// One definition of "the current rbp frame is a usable host continuation".
///
/// Three call sites used to answer this question independently, in different
/// orders, with different predicates: the transducer required 8-byte frame
/// alignment and a non-guest return, `applyGeneratedDispatchFrameReturn`
/// re-derived the same three checks inline, and the null-indirect transfer
/// recovery required neither alignment nor a readable saved frame pointer.
/// Tightening any one of them moved only that one, which is what made an
/// unrelated subsystem appear to regress.
pub const HostFrameProof = struct {
    frame_pointer: u64 = 0,
    saved_frame_pointer: u64 = 0,
    return_address: u64 = 0,
    frame_readable: bool = false,
    frame_aligned: bool = false,
    saved_frame_pointer_valid: bool = false,
    return_executable: bool = false,
    return_not_guest: bool = false,

    /// Every condition, evaluated together. A caller may inspect the individual
    /// fields for reporting, but must gate on this.
    pub fn usable(self: HostFrameProof) bool {
        return self.frame_readable and self.frame_aligned and
            self.saved_frame_pointer_valid and self.return_executable and
            self.return_not_guest and self.frame_pointer != 0 and
            self.return_address != 0 and
            self.frame_pointer <= std.math.maxInt(u64) - 16;
    }

    /// Continuation registers implied by the proof — exactly `leave; ret`.
    pub fn continuationStackPointer(self: HostFrameProof) u64 {
        return self.frame_pointer +| 16;
    }
};

pub fn hostFrameProof(self: anytype) HostFrameProof {
    const frame_pointer = self.regs.rbp;
    if (frame_pointer == 0) return .{};
    const frame_bytes = self.guestMemoryConst(frame_pointer, 16) orelse
        return .{ .frame_pointer = frame_pointer };
    if (frame_bytes.len < 16) return .{ .frame_pointer = frame_pointer };
    const saved_frame_pointer = std.mem.readInt(u64, frame_bytes[0..8], .little);
    const return_address = std.mem.readInt(u64, frame_bytes[8..16], .little);
    return .{
        .frame_pointer = frame_pointer,
        .saved_frame_pointer = saved_frame_pointer,
        .return_address = return_address,
        .frame_readable = true,
        .frame_aligned = frame_pointer & 7 == 0,
        .saved_frame_pointer_valid = saved_frame_pointer == 0 or
            self.guestMemoryConst(saved_frame_pointer, 8) != null,
        .return_executable = return_address != 0 and isExecutableAddress(self, return_address),
        .return_not_guest = !isGuestAddress(self, return_address),
    };
}

/// Per-family loop guard. If one family recovers repeatedly at the same site
/// the guest is not progressing, and continuing would spin forever. Returns
/// false to stop recovering and let the terminal diagnostics take over.
///
/// `ledger` must be the calling family's own ledger. The single shared guard
/// this replaces was reset by whichever family recovered last, so no family had
/// an independent budget and a recovery alternating between two sites never
/// reached the limit.
fn recoveryLoopAllowed(
    ledger: *recovery_ledger.Ledger,
    family: []const u8,
    instruction_address: u64,
) bool {
    if (ledger.loopAllowed(instruction_address)) return true;
    machoCapturePrint(
        "macho-processor: generated dispatch recovery loop: family={s} rip=0x{x} recovered {d} consecutive times (limit={d}); guest not progressing, stopping recovery\n",
        .{ family, instruction_address, ledger.consecutive, recovery_ledger.Ledger.consecutive_limit },
    );
    return false;
}

/// Return a JIT-generated frame to its host caller via the rbp frame pointer
/// (exactly `leave; ret` semantics): rip = [rbp+8], rsp = rbp+16. This is the
/// correct recovery for generated-code tail dispatches (null function pointer
/// or unpatched guest sentinel): the bytes after the dispatch are Xenia's dead
/// function-exit epilogue, so falling through double-deallocates the frame.
/// Returns false when no usable frame exists (rbp unreadable, or the return
/// address is not executable), in which case the caller must not continue.
pub fn applyGeneratedDispatchFrameReturn(self: anytype, why: []const u8) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "generated_dispatch_frame_return")) return false;
    const proof = hostFrameProof(self);
    if (!proof.usable()) return false;
    const frame_pointer = proof.frame_pointer;
    const saved_frame_pointer = proof.saved_frame_pointer;
    const return_address = proof.return_address;

    self.generated_dispatch_frame_return.note();
    if (self.generated_dispatch_frame_return.shouldLog()) {
        machoCapturePrint(
            "macho-processor: generated dispatch frame return: why={s} return=[rbp+8]=0x{x} (exec, {s}) rsp=0x{x}->0x{x} rbp=0x{x}->0x{x}; abandoned JIT frame returned to host caller (leave;ret)\n",
            .{
                why,
                return_address,
                self.metadata.symbolLabel(return_address),
                self.regs.rsp,
                frame_pointer + 16,
                frame_pointer,
                saved_frame_pointer,
            },
        );
    }
    self.pending_control_transfer = null;
    self.regs.rsp = frame_pointer + 16;
    self.regs.rbp = saved_frame_pointer;
    self.regs.rip = return_address;
    return true;
}

/// Fault-time dump of the frame state around a generated-code dispatch miss:
/// the rbp frame's return address, the top-of-stack qwords (flagging
/// guest-window values such as the Xenia GUEST_RET_ADDR slot), the rcx guest
/// return candidate, and whether the bytes after the transfer look like the
/// dead function-exit epilogue. Runs only inside throttled recoveries, never
/// on the hot path.
fn dumpGeneratedDispatchStackFrame(self: anytype, instruction_address: u64, transfer_len: usize) void {
    const rbp = self.regs.rbp;
    const frame_ret_bytes = self.guestMemoryConst(rbp + 8, 8) orelse &[_]u8{};
    const frame_ret: u64 = if (frame_ret_bytes.len >= 8)
        std.mem.readInt(u64, frame_ret_bytes[0..8], .little)
    else
        0;
    const frame_ret_exec = frame_ret != 0 and isExecutableAddress(self, frame_ret);
    const frame_ret_symbol = if (frame_ret_exec) self.metadata.nearestSymbol(frame_ret) else null;
    const caller_rsp_bytes = self.guestMemoryConst(rbp + 16, 8) orelse &[_]u8{};
    const caller_rsp: u64 = if (caller_rsp_bytes.len >= 8)
        std.mem.readInt(u64, caller_rsp_bytes[0..8], .little)
    else
        0;
    machoCapturePrint(
        "macho-processor: generated dispatch frame: source_rip=0x{x} rsp=0x{x} rbp=0x{x} [rbp+8]=0x{x} (exec={}, {s}) [rbp+16]=0x{x}\n",
        .{
            instruction_address,
            self.regs.rsp,
            rbp,
            frame_ret,
            frame_ret_exec,
            if (frame_ret_symbol) |s| s.name else "<unreadable>",
            caller_rsp,
        },
    );
    // Top-of-stack qwords, always showing the first few and flagging every
    // guest-window value (e.g. the guest return address in GUEST_RET_ADDR).
    const rsp = self.regs.rsp;
    var idx: usize = 0;
    while (idx < 12) : (idx += 1) {
        const slot = rsp + idx * 8;
        const bytes = self.guestMemoryConst(slot, 8) orelse break;
        if (bytes.len < 8) break;
        const value = std.mem.readInt(u64, bytes[0..8], .little);
        const guest = isGuestAddress(self, value);
        if (guest or idx < 6) {
            machoCapturePrint(
                "macho-processor:   frame stack[rsp+0x{x}]=0x{x}{s}\n",
                .{ idx * 8, value, if (guest) " (guest-window)" else "" },
            );
        }
    }
    // RCX is printed only as contextual state. At the null-base load it is not
    // authoritative; the guest return witness is the fixed [rsp+0x58] slot.
    if (isGuestAddress(self, self.regs.rcx)) {
        machoCapturePrint(
            "macho-processor: generated dispatch: rcx=0x{x} ({s}) = Xenia GUEST_RET_ADDR candidate; guest resumes at this module address\n",
            .{ self.regs.rcx, describeGuestRegion(self, self.regs.rcx) },
        );
    }
    // Epilogue-shape check on the bytes immediately after the transfer.
    const after = self.guestMemoryConst(instruction_address + transfer_len, 16) orelse &[_]u8{};
    const after_len: usize = @min(after.len, @as(usize, 16));
    if (after_len >= 4) {
        machoCapturePrint(
            "macho-processor: generated dispatch: bytes-after-transfer={any} dead_function_exit_epilogue={} (fall-through would double-deallocate)\n",
            .{ after[0..after_len], isFunctionExitEpilogueBytes(after[0..after_len]) },
        );
    }
}

/// Decode and print up to `depth` instructions immediately preceding
/// `from_rip`. Fault-time only (the recoveries that call this are throttled),
/// so the cost of the exhaustive 15-byte backward scan (x86 instructions are
/// at most 15 bytes) is never paid on the hot path. Each step finds the
/// latest candidate start `s` in [cursor-15, cursor) whose decoded length
/// lands exactly on `cursor`.
fn dumpPrecedingInstructionWindow(self: anytype, from_rip: u64, depth: usize) void {
    var cursor = from_rip;
    var idx: usize = 0;
    while (idx < depth) : (idx += 1) {
        var found: ?u64 = null;
        var s = cursor -| 15;
        while (s < cursor) : (s += 1) {
            const bytes = self.guestMemoryConst(s, 16) orelse break;
            if (bytes.len == 0) break;
            const decoded = decodeInsn(bytes);
            if (decoded.op == .invalid or decoded.len == 0 or decoded.len > 15) continue;
            if (s + decoded.len == cursor) found = s;
        }
        const start = found orelse break;
        const bytes = self.guestMemoryConst(start, 16) orelse break;
        const decoded = decodeInsn(bytes);
        if (decoded.op == .invalid or decoded.len == 0) break;
        const shown = bytes[0..@min(@as(usize, decoded.len), bytes.len)];
        machoCapturePrint(
            "macho-processor:   pre[{d}] rip=0x{x} op={s} len={d} bytes={any}\n",
            .{ idx, start, @tagName(decoded.op), decoded.len, shown },
        );
        cursor = start;
    }
}

/// Recover a null indirect transfer (jmp/call through a zero function
/// pointer) executed inside JIT-generated (sparse) executable code. This is
/// Xenia's code-cache indirection dispatch: when the guest branch target was
/// 0 or the indirection entry is unpatched, the loaded pointer is 0 and the
/// tail-call would terminate the guest. The caller falls through to the
/// host frame return (the return path back to GuestFunction::Call) instead,
/// keeping the run alive. The counter and throttled log record every skip so
/// the pattern stays observable, and the preceding-instruction window shows
/// how the null pointer was produced. Gated to the Xenia compat workload and
/// to generated code only — Mach-O text code that jumps through null is a
/// real translated-program bug and still terminates. Non-tail calls are never
/// skipped because inventing a successful callback return would hide behavior.
/// Who owns the continuation after a recovered null transfer.
///
/// This used to be a `bool`, and the caller decided what to do next — frame
/// return, else advance past the transfer. That gave the continuation *two*
/// owners, and the caller always won because it ran second. A recovery that had
/// already proven where execution must resume, installed RIP and RSP, and
/// returned `true` had both overwritten by a generic frame return that discards
/// the guest call chain. The run recorded the proof and then threw it away, in
/// adjacent log lines.
pub const NullTransferOutcome = enum {
    /// Nothing was recovered; the caller must terminate.
    refused,
    /// Recovery approved, continuation not chosen. The caller installs it, as
    /// it always did.
    approved,
    /// The recovery proved and installed the continuation itself. The caller
    /// must not touch RIP or RSP: anything it does here replaces a proof with a
    /// default.
    continuation_installed,

    pub fn recovered(self: NullTransferOutcome) bool {
        return self != .refused;
    }

    pub fn callerMayContinue(self: NullTransferOutcome) bool {
        return self == .approved;
    }
};

pub fn tryRecoverGeneratedNullIndirectTransfer(self: anytype, kind: []const u8) NullTransferOutcome {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "has_xenia_compat") or
        !@hasField(State, "sparse_memory") or
        !@hasField(State, "generated_null_indirect") or
        !@hasField(State, "last_generated_null_read_rip"))
    {
        return .refused;
    }
    if (!self.has_xenia_compat) return .refused;
    if (!self.sparse_memory.isExecutable(self.regs.rip, 1)) return .refused;

    const fault = decodeStatic(self, self.regs.rip) orelse return .refused;
    if (!isGeneratedNullTransferOp(fault.op)) return .refused;
    if (fault.op == .call_reg64 or fault.op == .call_mem64) return .refused;
    const after = self.guestMemoryConst(self.regs.rip +| fault.len, 16) orelse return .refused;
    if (!isFunctionExitEpilogueBytes(after)) return .refused;
    // Same host-frame proof as the other two consumers. This site previously
    // required only a non-zero executable `[rbp+8]` — no frame alignment, no
    // readable saved frame pointer, no guest-window exclusion — so it accepted
    // frames the transducer rejected and vice versa.
    const frame_proof = hostFrameProof(self);
    if (!frame_proof.usable()) return .refused;
    if (!recoveryLoopAllowed(&self.generated_null_indirect, "null_indirect_transfer", self.regs.rip)) return .refused;

    // Before abandoning the frame: this may not be a dispatch at all.
    if (tryRecoverMissedGuestReturn(self, fault)) return .continuation_installed;

    self.generated_null_indirect.note();
    const linked = if (self.last_generated_null_read_rip != 0 and
        self.regs.rip > self.last_generated_null_read_rip and
        self.regs.rip - self.last_generated_null_read_rip <= 64)
        self.last_generated_null_read_rip
    else
        0;
    const linked_distance = if (linked != 0) self.regs.rip - linked else 0;
    if (self.generated_null_indirect.shouldLog()) {
        const thread_handle = if (@hasField(State, "active_guest_thread")) self.active_guest_thread else 0;
        const thread_id = if (@hasField(State, "threadNumericId")) self.threadNumericId(thread_handle) else 0;
        const raw = self.guestMemoryConst(self.regs.rip, 16) orelse &[_]u8{};
        const raw_len: usize = @min(@as(usize, fault.len), raw.len);
        machoCapturePrint(
            "macho-processor: generated null indirect transfer recovery #{d}: thread=0x{x} tid={d} kind={s} rip=0x{x} op={s} len={d} bytes={any} linked_null_read_rip=0x{x} linked_distance={d} symbol={s}; verified tail dispatch will return through host frame (never fall through dead epilogue)\n",
            .{
                self.generated_null_indirect.recoveries,
                thread_handle,
                thread_id,
                kind,
                self.regs.rip,
                @tagName(fault.op),
                fault.len,
                raw[0..raw_len],
                linked,
                linked_distance,
                self.metadata.symbolLabel(self.regs.rip),
            },
        );
        dumpGeneratedDispatchStackFrame(self, self.regs.rip, fault.len);
        dumpPrecedingInstructionWindow(self, self.regs.rip, 5);
        reportNullTransferOrigin(self, fault);
    }
    return .approved;
}

/// A tail dispatch that is not a dispatch: the guest was returning.
///
/// Xenia guards an indirect transfer with `CALL_POSSIBLE_RETURN` —
/// `cmp target32, [rsp+GUEST_RET_ADDR]; je epilogue` — so a "call" whose target
/// is the function's own guest return address is recognised as a return and
/// takes the epilogue instead. When the target register holds that address with
/// its bytes reversed, the compare cannot match: the predicate falls through,
/// the indirection table is consulted with a value that is not a guest address
/// at all, the slot reads zero, and a *return* becomes a null dispatch.
///
/// Everything needed to prove that is available at the transfer, and none of it
/// is a guess:
///
///   1. the transfer register was defined by a load whose base register is the
///      dispatch target (the bounded def-use scan finds the instruction),
///   2. that base value is not a guest address, but its byte-reversal is —
///      only one of the two orders can be, so the reversal is decidable,
///   3. the reversal equals the guest return address the emitter has already
///      loaded into RCX two instructions earlier, and
///   4. the bytes after the transfer are the function-exit epilogue.
///
/// The correct continuation is the one the epilogue performs. Its stack
/// adjustment and stackpoint decrement have *already* run — they precede the
/// transfer, which is why falling through would undo them twice — so what
/// remains of the epilogue is its `ret`, and performing that resumes the guest's
/// caller exactly as the unbroken predicate would have. The saved return address
/// is verified executable first; anything less falls back to the frame return.
///
/// Counted apart from the null-indirect family: those are dispatches that could
/// not be resolved, this is a dispatch that should never have happened.
fn tryRecoverMissedGuestReturn(self: anytype, fault: DecodedInsn) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "generated_missed_guest_return")) return false;

    const definition = boundedBaseDefinition(self, self.regs.rip, fault.dst_reg);
    if (!definition.found or !definition.from_memory) return false;
    const load = decodeStatic(self, definition.instruction_address) orelse return false;
    if (!load.sib_has_base or load.sib_has_index or load.rip_relative) return false;

    const address_size: Size = if (load.has_0x67) .bits32 else .bits64;
    const base_value = self.regVal(load.sib_base_reg, address_size);
    const Window = struct {
        state: @TypeOf(self),
        fn isGuest(ctx: @This(), address: u64) bool {
            return isGuestAddress(ctx.state, address);
        }
    };
    const inverted = generated_endian_contract.classifyInverted32(
        Window,
        .{ .state = self },
        base_value,
        Window.isGuest,
    );
    if (!inverted.inverted) return false;

    // RCX is the guest return address the emitter loads from GUEST_RET_ADDR
    // immediately before tearing the frame down. Comparing against a live
    // register avoids re-reading a stack slot whose RSP has already moved.
    const guest_return: u32 = @truncate(self.regs.rcx);
    if (inverted.corrected != guest_return) return false;

    const after = self.regs.rip +| fault.len;
    const epilogue_bytes = self.guestMemoryConst(after, 16) orelse return false;
    if (!isFunctionExitEpilogueBytes(epilogue_bytes)) return false;

    const saved_return = read64(self, self.regs.rsp);
    if (saved_return == 0 or !isExecutableAddress(self, saved_return)) return false;
    if (!recoveryLoopAllowed(&self.generated_missed_guest_return, "missed_guest_return", self.regs.rip)) {
        return false;
    }

    self.generated_missed_guest_return.note();
    if (self.generated_missed_guest_return.shouldLog()) {
        machoCapturePrint(
            "macho-processor: missed guest return recovered #{d}: thread=0x{x} transfer_rip=0x{x} load_rip=0x{x} base={s} observed=0x{x} byte_reversed=0x{x} guest_return(rcx)=0x{x} match=true; the CALL_POSSIBLE_RETURN predicate could not match because the target register held the guest return address with its bytes reversed, so a RETURN was executed as an indirect dispatch and its table slot read zero. Resuming the guest caller at 0x{x} ({s}) — the epilogue's stack adjustment and stackpoint decrement already ran ahead of the transfer, so only its `ret` remained\n",
            .{
                self.generated_missed_guest_return.recoveries,
                self.active_guest_thread,
                self.regs.rip,
                definition.instruction_address,
                @tagName(load.sib_base_reg),
                base_value,
                inverted.corrected,
                guest_return,
                saved_return,
                self.metadata.symbolLabel(saved_return),
            },
        );
        // Walk one step further back: what produced the reversed value? The
        // base register was itself defined somewhere, and if that definition
        // read guest memory, that slot is where a guest code address was stored
        // in the wrong byte order.
        const origin = boundedValueOrigin(self, definition.instruction_address, load.sib_base_reg);
        reportValueOrigin(self, "missed guest return", origin);
        const producer = origin.definition;
        machoCapturePrint(
            "macho-processor: missed guest return producer: register={s} found={} instruction=0x{x} op={s} distance={d} from_memory={} source_address=0x{x} readable={} value=0x{x} from_immediate={} immediate=0x{x} block_origin={s}\n",
            .{
                @tagName(load.sib_base_reg),
                producer.found,
                producer.instruction_address,
                @tagName(producer.op),
                producer.distance,
                producer.from_memory,
                producer.source_address,
                producer.source_readable,
                producer.source_value,
                producer.from_immediate,
                producer.immediate,
                @tagName(producer.origin),
            },
        );
        if (producer.found and producer.from_memory and producer.source_address != 0) {
            // Seed provenance here rather than asking an operator to predict the
            // address before the run. This is exactly what the watch set exists
            // for, and the address only becomes knowable at this fault.
            const seeded = self.provenance_watch.watchPage(producer.source_address, .declared);
            machoCapturePrint(
                "macho-processor: missed guest return: provenance now watching the page holding 0x{x} (newly_seeded={} entries={d}/{d}). The next store to it will be attributed, which names whoever wrote a guest code address in host byte order. That writer is the defect; this recovery only keeps the run alive past it\n",
                .{ producer.source_address, seeded, self.provenance_watch.count, self.provenance_watch.entries.len },
            );
        } else {
            machoCapturePrint(
                "macho-processor: missed guest return: the reversed value is the finding, not this recovery. A guest code address reached generated code in host byte order, which means a store of that address into guest memory skipped its big-endian conversion. The producing instruction was not reconstructible from here; arm ROSETTE_MACHO_WRITE_DIAGNOSTICS=1 to name the writer. Every dispatch guarded by CALL_POSSIBLE_RETURN is exposed to the same defect\n",
                .{},
            );
        }
    }
    self.pending_control_transfer = null;
    self.regs.rip = saved_return;
    self.regs.rsp = self.regs.rsp +| 8;
    return true;
}

/// Where the null transfer target came from, and whether its zero is anomalous.
///
/// This path used to print two decoded predecessors and stop, which is not
/// enough to distinguish the two things a reader needs to separate: a register
/// that was clobbered, and a *table slot* that was read correctly and held zero.
/// The bounded def-use scan the dispatch transducer already owns answers the
/// first; when the answer is "loaded from memory", the table probe answers the
/// second by reading the neighbourhood of that slot.
///
/// Both are bounded, run only inside the throttled recovery, and neither
/// assumes anything about which translator produced the code.
fn reportNullTransferOrigin(self: anytype, fault: DecodedInsn) void {
    const definition = boundedBaseDefinition(self, self.regs.rip, fault.dst_reg);
    machoCapturePrint(
        "macho-processor: null transfer origin: register={s} found={} instruction=0x{x} op={s} distance={d} from_memory={} source_address=0x{x} readable={} value=0x{x} from_immediate={} immediate=0x{x} block_origin={s} convergence={s}\n",
        .{
            @tagName(fault.dst_reg),
            definition.found,
            definition.instruction_address,
            @tagName(definition.op),
            definition.distance,
            definition.from_memory,
            definition.source_address,
            definition.source_readable,
            definition.source_value,
            definition.from_immediate,
            definition.immediate,
            @tagName(definition.origin),
            @tagName(definition.convergence),
        },
    );
    if (!definition.found or !definition.from_memory or definition.source_address == 0) {
        machoCapturePrint(
            "macho-processor: null transfer origin: no memory source was reconstructed, so the zero cannot be attributed to a dispatch-table slot. The register was either clobbered or defined outside the reconstructed block\n",
            .{},
        );
        return;
    }
    const entry_bytes: u64 = if (definition.source_bytes == 0) 4 else definition.source_bytes;
    const Reader = struct {
        state: @TypeOf(self),
        fn read(ctx: @This(), address: u64, bytes: u64) ?u64 {
            const raw = ctx.state.guestMemoryConst(address, bytes) orelse return null;
            return switch (bytes) {
                4 => if (raw.len >= 4) std.mem.readInt(u32, raw[0..4], .little) else null,
                8 => if (raw.len >= 8) std.mem.readInt(u64, raw[0..8], .little) else null,
                else => null,
            };
        }
    };
    const found = dispatch_table.probe.probe(
        Reader,
        .{ .state = self },
        definition.source_address,
        entry_bytes,
        16,
        Reader.read,
    );
    machoCapturePrint(
        "macho-processor: null transfer table probe: slot=0x{x} entry_bytes={d} population={s} sampled={d} readable={d} zero={d} nonzero={d} dominant=0x{x} x{d} distinct={d} range=[0x{x},0x{x}] zero_is_anomalous={}; {s}\n",
        .{
            definition.source_address,
            entry_bytes,
            @tagName(found.population),
            found.sampled,
            found.readable,
            found.zero,
            found.nonzero,
            found.dominant_value,
            found.dominant_count,
            found.distinct_values,
            found.first_slot,
            found.last_slot,
            found.population.zeroIsAnomalous(),
            found.describe(),
        },
    );
    if (found.population == .uniform_default and found.dominant_value != 0) {
        machoCapturePrint(
            "macho-processor: null transfer table probe: the host's default entry is 0x{x} ({s}, executable={}). That is where this dispatch would have gone had the slot carried the default, and it is almost certainly the host's not-yet-translated resolver. Skipping the dispatch bypasses that resolver, so the guest function is never translated and never runs\n",
            .{
                found.dominant_value,
                self.metadata.symbolLabel(found.dominant_value),
                isExecutableAddress(self, found.dominant_value),
            },
        );
    }
}

// The guest window is *derived*, not asserted. `guest_address_space.Model`
// accumulates observations from the sparse mappings and reports whether an
// answer is derived or still running on its bootstrap default. These wrappers
// exist so the ten call sites read the same as before while the knowledge lives
// where it belongs.
//
// Retained only as the model's bootstrap range; see guest-address-space.
pub const GUEST_MODULE_BASE: u32 = guest_address_space.window.bootstrap_base;
pub const GUEST_MODULE_END: u32 = guest_address_space.window.bootstrap_end;

/// True when `address` is a canonical 32-bit value inside the observed guest
/// window. Canonical form (zero- or sign-extended) is x86-64 semantics and
/// stays a rule; the window itself comes from the model.
pub fn isGuestModuleAddressIn(model: *const guest_address_space.Model, address: u64) bool {
    return model.isGuestAddress(address);
}

/// The predicate every decision site uses: canonical 32-bit form, against the
/// window this run actually observed.
///
/// This had two owners for a long time. The model-aware form above was
/// documented as the one to prefer and had *no callers*, so every recovery —
/// including the dispatch transducer's target/return proofs and its
/// `host_return_not_guest` gate — ran on the bootstrap constants while the
/// model was fed on every mapping and then discarded. Two answers to a question
/// that decides where guest control flow resumes, one of them dead.
///
/// Moving the sites here was blocked on the model widening its window over the
/// executable JIT code cache; `Model.observe` now refuses that, and the model
/// still falls back to the bootstrap range until an observation arrives, so an
/// early fault answers exactly as before.
pub fn isGuestAddress(self: anytype, address: u64) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_address_space")) return isGuestModuleAddress(address);
    return isGuestModuleAddressIn(&self.guest_address_space, address);
}

/// True when `address` is a canonical 32-bit value that lands in *any* mapping
/// the guest actually made — not only the module window.
///
/// `isGuestAddress` answers "is this a guest **module** address", which is the
/// right question for a dispatch target and the wrong one for byte-order
/// evidence. A guest stack pointer, a guest heap pointer and a physical-view
/// pointer are all guest values that can arrive byte-reversed, and none of them
/// is in the module window: the survey that only knew the window scored
/// `r10 = byteswap64(r12)` as unrelated, when `r12` was a live guest stack
/// pointer sitting in the next register.
///
/// Canonical form stays a rule — a genuine 64-bit host pointer whose low half
/// happens to land in a mapping is not a guest value — but membership is
/// answered from the mappings the run observed rather than from one range.
pub fn isGuestMappedValue(self: anytype, address: u64) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_address_space")) return isGuestModuleAddress(address);
    const classified = self.guest_address_space.classify(address);
    return classified.in_window or classified.region != null;
}

/// Free-function form, for sites with no state handle and for tests that pin
/// the bootstrap range itself. Everything that makes a decision should use
/// `isGuestAddress`.
pub fn isGuestModuleAddress(address: u64) bool {
    const low = guest_address_space.canonical32(address) orelse return false;
    return low >= GUEST_MODULE_BASE and low < GUEST_MODULE_END;
}

/// Describe where a guest-window address lives, from observed mappings rather
/// than from hardcoded module names. `xboxkrnl.exe` / `xam.xex` / `<game
/// module>` were split points for one title's layout; an observed region base
/// and size is factual for any workload.
fn describeGuestRegion(self: anytype, address: u64) []const u8 {
    const classified = self.guest_address_space.classify(address);
    if (!classified.in_window) return "<outside-guest-window>";
    if (classified.region != null) return "guest-mapped-region";
    return if (classified.trustworthy())
        "guest-window (no containing mapping observed)"
    else
        "guest-window (bootstrap default; no mapping observed yet)";
}

/// Poll the target address of an invalid control-flow transfer. Fault-time
/// only — this runs solely at the terminal raise site (or inside the
/// throttled recovery), never on the hot path. Classifies the address against
/// the guest module window, reads any bytes present at the target (guest code
/// would be big-endian PPC, the definitive unpatched-sentinel signature), and
/// records the full GPR snapshot so the next failure is self-diagnosing.
pub fn dumpGuestDispatchTargetPoll(self: anytype, target: u64) void {
    const low: u32 = @truncate(target);
    const sign_extended = (target >> 32) == 0xFFFFFFFF;
    const zero_extended = (target >> 32) == 0;
    const in_window = isGuestAddress(self, target);
    const sparse_bytes = self.sparse_memory.bytesConst(target, 16);
    const raw = if (sparse_bytes) |b| b else (self.guestMemoryConst(target, 16) orelse &[_]u8{});
    const shown = raw[0..@min(@as(usize, 16), raw.len)];
    machoCapturePrint(
        "macho-processor: invalid control-flow target poll: target=0x{x} target32=0x{x} sign_extended={} zero_extended={} guest_module_window={} module={s} readable={} bytes={any}\n",
        .{ target, low, sign_extended, zero_extended, in_window, if (in_window) describeGuestRegion(self, target) else "<none>", raw.len != 0, shown },
    );
    machoCapturePrint(
        "macho-processor: invalid control-flow target poll: gpr rax=0x{x} rcx=0x{x} rdx=0x{x} rbx=0x{x} rsp=0x{x} rbp=0x{x} rsi=0x{x} rdi=0x{x}\n",
        .{ self.regs.rax, self.regs.rcx, self.regs.rdx, self.regs.rbx, self.regs.rsp, self.regs.rbp, self.regs.rsi, self.regs.rdi },
    );
    machoCapturePrint(
        "macho-processor: invalid control-flow target poll: gpr r8=0x{x} r9=0x{x} r10=0x{x} r11=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x} rip=0x{x} rflags=0x{x}\n",
        .{ self.regs.r8, self.regs.r9, self.regs.r10, self.regs.r11, self.regs.r12, self.regs.r13, self.regs.r14, self.regs.r15, self.regs.rip, self.regs.rflags },
    );
}

/// Recover an indirect transfer from JIT-generated code to an address in the
/// Xenia guest module window. Generated code dispatching through the
/// indirection table reads the *unpatched sentinel* — the guest function
/// address itself, zero-extended (0x82582cc8) or sign-extended
/// (0xffffffff8313e528) — where native Xenia would trap to translate the guest
/// function on first execution. With no trap path, this is the same recoverable
/// code-cache miss as the null case: the transfer is skipped and the run stays
/// alive. A call that already pushed its return address pops it and continues
/// after the call; a jump falls through to the epilogue. Gated to the Xenia
/// compat workload and to generated-code indirect transfers only — Mach-O text
/// code that transfers to a bogus target is a real translated-program bug and
/// still terminates.
pub fn tryRecoverGeneratedGuestDispatchMiss(self: anytype, context: anytype, return_already_pushed: bool) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "has_xenia_compat") or
        !@hasField(State, "sparse_memory") or
        !@hasField(State, "generated_guest_dispatch") or
        !@hasField(State, "last_generated_null_read_rip"))
    {
        return false;
    }
    if (!self.has_xenia_compat) return false;
    if (!self.sparse_memory.isExecutable(context.instruction_address, 1)) return false;

    const fault = decodeStatic(self, context.instruction_address) orelse return false;
    if (!isGeneratedDispatchMissOp(fault.op)) return false;
    if (!isGuestAddress(self, context.target_address)) return false;
    if (!recoveryLoopAllowed(&self.generated_guest_dispatch, "guest_dispatch_miss", context.instruction_address)) return false;

    self.generated_guest_dispatch.note();
    const linked = if (self.last_generated_null_read_rip != 0 and
        context.instruction_address > self.last_generated_null_read_rip and
        context.instruction_address - self.last_generated_null_read_rip <= 64)
        self.last_generated_null_read_rip
    else
        0;
    if (self.generated_guest_dispatch.shouldLog()) {
        const raw = self.guestMemoryConst(context.instruction_address, 16) orelse &[_]u8{};
        const raw_len: usize = @min(@as(usize, fault.len), raw.len);
        machoCapturePrint(
            "macho-processor: generated guest dispatch recovery #{d}: kind={s} source_rip=0x{x} target=0x{x} target32=0x{x} module={s} linked_null_read_rip=0x{x} symbol={s}; unpatched indirection sentinel skipped (fall through)\n",
            .{
                self.generated_guest_dispatch.recoveries,
                context.kind,
                context.instruction_address,
                context.target_address,
                @as(u32, @truncate(context.target_address)),
                describeGuestRegion(self, context.target_address),
                linked,
                self.metadata.symbolLabel(context.instruction_address),
            },
        );
        machoCapturePrint("macho-processor:   transfer bytes={any}\n", .{raw[0..raw_len]});
        dumpPrecedingInstructionWindow(self, context.instruction_address, 5);
        dumpGeneratedDispatchStackFrame(self, context.instruction_address, fault.len);
        dumpGuestDispatchTargetPoll(self, context.target_address);
    }

    self.pending_control_transfer = null;
    if (fault.op == .call_reg64 or fault.op == .call_mem64) {
        // Non-tail call dispatch: the code after the call is the return path
        // (the call's post-call epilogue handles the guest return). Pop the
        // already-pushed return, or continue after the call when it was never
        // pushed, so the stack stays balanced.
        if (return_already_pushed) {
            self.regs.rsp +|= 8;
            self.regs.rip = context.return_address;
        } else {
            self.regs.rip = context.instruction_address + fault.len;
        }
        return true;
    }
    // Tail jmp or ret to a guest-module address: the bytes after a tail
    // dispatch are Xenia's dead function-exit epilogue (CALL_POSSIBLE_RETURN
    // path), so falling through double-deallocates the frame and the `ret`
    // pops a local (the guest return address). Return to the host caller via
    // the rbp frame instead, exactly like `leave; ret`.
    if (applyGeneratedDispatchFrameReturn(self, context.kind)) {
        return true;
    }
    return false;
}

/// Outcome of the scalar-read recovery cascade.
///
/// `satisfied_zero` covers both the recoveries that answer the load as zero and
/// the terminal case, because the caller does the same thing for both: return
/// zero. Which of the two happened is recorded in the ledgers and, for the
/// terminal case, in `terminal_memory_failure`.
const ScalarReadResolution = union(enum) {
    resolved: struct { address: u64, storage: ?[]const u8, offset: ?u64 },
    satisfied_zero,
};

/// F1 (throughput audit): the scalar-read fault cascade, held out of line.
///
/// Reached only when a load's address translates through neither the sparse
/// mappings nor the contiguous image — that is, essentially never on a healthy
/// run. Inlined, it made `readMemVal` a 16 KB function of which 81% of the call
/// sites were diagnostic formatting, and `readMemVal` is the most frequently
/// executed function in the program. The interpreter's hot closure measured
/// 189 KB against a 128-192 KB L1I, so this code was evicting the loop that
/// calls it.
///
/// Behaviour is unchanged: same classification, same owners, same order, same
/// early returns. `noinline` is required rather than advisory — the function
/// has one call site, so LLVM inlines it straight back otherwise.
noinline fn recoverScalarReadFault(self: anytype, addr: u64, bytes: u8) ScalarReadResolution {
    var effective_address = addr;
    var sparse_storage: ?[]const u8 = null;
    var sparse_readable = false;
    var off: ?u64 = null;

    // Decide the owner once, from state no repair has touched yet, and
    // dispatch to exactly that owner. The previous fall-through chain
    // re-derived ownership after each attempt, so the endian repair —
    // which writes the base register — could hand its own fault to the
    // near-null owners. One classification, one owner, no cascade.
    const classification = classifyGeneratedScalarFault(self, effective_address, bytes);
    switch (classification.owner) {
        .none => {},
        .endian_swapped_base => {
            if (tryRecoverGeneratedEndianAddress(self, classification, effective_address, bytes)) |recovered_address| {
                effective_address = recovered_address;
                sparse_storage = self.sparse_memory.bytesConst(effective_address, bytes);
                sparse_readable = sparse_storage != null;
                off = if (sparse_readable) null else translateGuest(self, effective_address, bytes, .read);
            }
        },
        .null_base_dispatch => {
            // A base register is only null if it is *actually* null. A
            // 32-bit guest address that arrived byte-reversed as 64 bits
            // has zero in its low half, so it reads as null through every
            // 32-bit addressing form while the address it should have
            // carried is still sitting in the register. Ask that question
            // before treating the zero as an absence — it is the difference
            // between a pointer that was never set and a pointer that was
            // set and not converted.
            if (tryRepairByteReversedBase(self, classification)) |repaired| {
                effective_address = repaired;
                sparse_storage = self.sparse_memory.bytesConst(effective_address, bytes);
                sparse_readable = sparse_storage != null;
                off = if (sparse_readable) null else translateGuest(self, effective_address, bytes, .read);
            } else if (tryRedirectBoundedNullDispatch(self, classification.fault)) {
                return .satisfied_zero;
            }
        },
        .null_base_scalar => {
            if (tryRepairByteReversedBase(self, classification)) |repaired| {
                effective_address = repaired;
                sparse_storage = self.sparse_memory.bytesConst(effective_address, bytes);
                sparse_readable = sparse_storage != null;
                off = if (sparse_readable) null else translateGuest(self, effective_address, bytes, .read);
            } else if (tryRecoverGeneratedNullScalarRead(self, classification, bytes)) {
                return .satisfied_zero;
            }
        },
    }
    if (!sparse_readable and off == null) {
        const snapshot = currentInstructionSnapshot(self);
        const instruction = if (snapshot.operation.len != 0) snapshot.operation else @tagName(if (self.execution_history.latestFor(self.active_guest_thread)) |e| e.op else .invalid);
        terminateForGuestAccess(self, effective_address, bytes, .read, instruction);
        return .satisfied_zero;
    }
    return .{ .resolved = .{ .address = effective_address, .storage = sparse_storage, .offset = off } };
}

pub fn readMemVal(self: anytype, addr: u64, size: Size) u64 {
    const State = @TypeOf(self.*);
    const bytes = bytesForSize(size);
    // Xenos register pages are intentionally no-access in the guest mapping.
    // Service a direct load from the same register file used by PM4 before the
    // ordinary sparse/linear-memory probes turn it into a protection fault.
    // This preserves the hardware-facing contract for polling code without
    // making the aperture an ordinary writable memory region.
    if (readXenosRegister(self, addr, size)) |value| {
        observeDirectXenosRegisterAccess(self, value.guest_address, false, value.value);
        return value.value;
    }
    // Sparse mappings live outside the contiguous Mach-O image.  The memory
    // manager already knows how to read them, so don't require an unrelated
    // main-image offset before dispatching the read.  Writes have always
    // followed this ordering; keeping reads symmetric prevents valid mprotect
    // activations from being reported as permission faults.
    var effective_address = addr;
    // Keep the slice, not just the fact that there was one. The probe is the
    // expensive half of deciding where this address lives, and the read below
    // needs exactly what it already found.
    var sparse_storage = self.sparse_memory.bytesConst(effective_address, bytes);
    const sparse_readable = sparse_storage != null;
    var off = if (sparse_readable) null else translateGuest(self, effective_address, bytes, .read);
    if (!sparse_readable and off == null) {
        switch (recoverScalarReadFault(self, effective_address, bytes)) {
            .satisfied_zero => return 0,
            .resolved => |resolved| {
                effective_address = resolved.address;
                sparse_storage = resolved.storage;
                off = resolved.offset;
            },
        }
    }
    // The read itself, written out rather than dispatched through the memory
    // manager's callback form.
    //
    // That form cost three things on every single load, all of them invisible
    // at the call site: it re-probed the sparse mapping this function had
    // already probed above; it reached both observers through function
    // pointers, so their fast rejections happened *after* an indirect call and
    // a pair of pointer casts; and it asked the vtable observer about every
    // 64-bit value, including the overwhelming majority that its own first
    // line immediately rejects. A load is the most frequent thing a guest
    // does, so each of those is multiplied by everything.
    //
    // Both observers are still called, under exactly the conditions their own
    // bodies test first — the conditions are simply asked here, where they
    // cost a compare instead of a call.
    _ = State;
    if (sparse_storage) |storage| {
        var value = readSized(storage, size);
        if (size == .bits64 and vtableRecoveryWanted(self, effective_address, value)) {
            if (recoverLiveAllocationVtable(self, effective_address, value)) |recovered| {
                if (self.sparse_memory.bytes(effective_address, @sizeOf(u64), true)) |mutable| {
                    std.mem.writeInt(u64, mutable[0..8], recovered, .little);
                    value = recovered;
                }
            }
        }
        if (memoryTraceWanted(self)) recordMemoryAccess(self, effective_address, size, "read", value);
        return value;
    }

    const offset = off orelse return 0;
    if (offset + bytes > self.mem.len) return 0;
    var value = readSized(self.mem[@intCast(offset)..], size);
    if (size == .bits64 and vtableRecoveryWanted(self, effective_address, value)) {
        if (recoverLiveAllocationVtable(self, effective_address, value)) |recovered| {
            std.mem.writeInt(u64, self.mem[@intCast(offset)..][0..8], recovered, .little);
            value = recovered;
        }
    }
    if (memoryTraceWanted(self)) recordMemoryAccess(self, effective_address, size, "read", value);
    return value;
}

const XenosRegisterRead = struct {
    guest_address: u64,
    value: u64,
};

/// Resolve either a console virtual Xenos aperture address or the host address
/// of the same mapped aperture back to its dword register stream. The latter
/// form is needed only for paths that are already operating on a translated
/// host fault address; normal interpreter loads use the former.
fn readXenosRegister(self: anytype, address: u64, size: Size) ?XenosRegisterRead {
    const State = @TypeOf(self.*);
    const byte_count: u64 = bytesForSize(size);
    var guest_address: ?u64 = if (device_tree.gpu.xenos.registerApertureContains(address)) address else null;
    if (guest_address == null) {
        if (comptime !@hasField(State, "xenia_memory_views")) return null;
        const host_base = self.xenia_memory_views.virtualHostAddress(
            device_tree.gpu.xenos.register_aperture_base,
        ) orelse return null;
        if (address < host_base) return null;
        const offset = address - host_base;
        if (offset >= device_tree.gpu.xenos.register_aperture_size) return null;
        guest_address = device_tree.gpu.xenos.register_aperture_base + offset;
    }
    const guest = guest_address.?;
    const offset = guest - device_tree.gpu.xenos.register_aperture_base;
    if (offset +| byte_count > device_tree.gpu.xenos.register_aperture_size) return null;
    if (comptime !@hasField(State, "gpu_xenos_runtime")) return null;

    var value: u64 = 0;
    var byte_index: u64 = 0;
    while (byte_index < byte_count) : (byte_index += 1) {
        const dword_offset = offset + byte_index;
        const register = device_tree.gpu.xenos.registerIndexOf(
            device_tree.gpu.xenos.register_aperture_base + (dword_offset & ~@as(u64, 3)),
        ) orelse return null;
        const dword = self.gpu_xenos_runtime.readRegister(@intCast(register));
        const shift: u5 = @intCast((dword_offset & 3) * 8);
        value |= (@as(u64, (dword >> shift) & 0xFF)) << @as(u6, @intCast(byte_index * 8));
    }
    return .{ .guest_address = guest, .value = value };
}

fn observeDirectXenosRegisterAccess(self: anytype, address: u64, is_write: bool, value: u64) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_register_aperture")) return;
    self.gpu_register_aperture.observe(
        address,
        is_write,
        value,
        .delivered,
        self.regs.rip,
        self.active_guest_thread,
        self.executed_steps,
    );
    if (comptime @hasField(State, "gpu_register_aperture_reachable")) {
        self.gpu_register_aperture_reachable = true;
    }
}

fn readSized(storage: []const u8, size: Size) u64 {
    return switch (size) {
        .bits8 => storage[0],
        .bits16 => std.mem.readInt(u16, storage[0..2], .little),
        .bits32 => std.mem.readInt(u32, storage[0..4], .little),
        .bits64 => std.mem.readInt(u64, storage[0..8], .little),
    };
}

/// Whether the vtable observer can possibly do anything for this value.
///
/// Mirrors the first line of `recoverLiveAllocationVtable`. Asking it here
/// turns the common 64-bit load — a pointer, a count, anything at or above
/// 0x1000 — from "indirect call that returns null" into one compare.
inline fn vtableRecoveryWanted(self: anytype, address: u64, value: u64) bool {
    if (value >= 0x1000 and !self.vtable_tracker.policy.repair_nonzero_corruption) return false;
    // F7 (throughput audit): the value test alone was the wrong gate. Its
    // comment reasoned that "a pointer, a count, anything at or above 0x1000"
    // is the common case — but values *below* 0x1000 are the most common thing
    // a program loads: zero, null, booleans, small counts, enum tags, loop
    // indices. So the supposedly rare path ran constantly, and its first act
    // was two `AutoHashMap` probes (a Wyhash plus a random probe into a table
    // that grows with the heap) on an address that in almost every case had
    // never had a vptr written to it.
    //
    // A tracked vptr lives either in a live heap allocation or in the modelled
    // stack registry. Both answer "definitely not here" in two comparisons.
    // This is the same range-gate-before-lookup shape already used by
    // `withinArena` and `execution_tracepoints.Set.mightMatch`.
    return self.memory_forwarder.withinArena(address) or
        self.vtable_stack_registry.mightContain(address);
}

/// Whether the memory-access ring can possibly want this access.
///
/// Mirrors the outer gate of `recordMemoryAccess`: the flag forces recording
/// everywhere, and otherwise only generated code is recorded. The budget check
/// deliberately stays inside, because taking from it is a state change and must
/// happen once, at the point that actually records.
inline fn memoryTraceWanted(self: anytype) bool {
    if (self.memory_trace_enabled) return true;
    return self.regs.rip < self.executable_min or self.regs.rip >= self.executable_max;
}

/// How far back a vptr slot may sit from the start of its object before this
/// runtime stops trying to attribute it.
///
/// A secondary base's vptr lies at the offset of that base subobject, which for
/// the shapes that occur in practice is within the first few pointers of the
/// object. The bound exists because the alternative — asking which allocation
/// contains an arbitrary interior address — is a linear scan over every live
/// allocation, and putting that on a path taken by ordinary guest writes costs
/// more as the run gets longer. A class whose secondary base sits beyond this
/// is simply not tracked, which is the behaviour that already existed.
/// The base of the live allocation owning `address`, in bounded time.
///
/// `memory_forwarder.allocationSize` answers in O(1) but only at an exact base,
/// and `containingAllocation` answers for interior addresses by scanning every
/// live allocation. Neither is usable here on its own: the first cannot see a
/// secondary vptr, and the second turned a per-write check into work
/// proportional to the heap and cost roughly an order of magnitude of
/// throughput, degrading as the run allocated more.
///
/// Walking back pointer-by-pointer is O(1) hash lookups with a stated bound.
/// The first base found going backwards is the only candidate: anything before
/// it belongs to a different block, so a base that does not cover `address`
/// means `address` is not in a tracked allocation rather than "keep looking".
const LiveAllocation = struct { base: u64, size: u64 };

fn owningAllocationBase(self: anytype, address: u64) ?LiveAllocation {
    // The overwhelming majority of tracked slots: a primary vptr at the
    // object's own base. One hash lookup, which is exactly what this cost
    // before secondary bases were tracked at all.
    if (self.memory_forwarder.allocationSize(address)) |size| {
        return .{ .base = address, .size = size };
    }
    // Two comparisons reject everything that is not heap. An image pointer
    // stored into a global, a static or a stack slot never reaches the probe.
    if (!self.memory_forwarder.withinArena(address)) return null;

    var probe = address;
    var steps: usize = 0;
    while (steps < vt.max_subobject_slots and probe >= 8) : (steps += 1) {
        probe -= 8;
        const size = self.memory_forwarder.allocationSize(probe) orelse continue;
        return if (address - probe < size) .{ .base = probe, .size = size } else null;
    }
    return null;
}

/// Resolve liveness from an existing vptr record without rediscovering the
/// owner by walking backwards. This also handles secondary bases at any offset
/// already admitted by the tracker and prevents a future probe-bound change
/// from invalidating previously established ownership.
fn liveOwnerForTrackedVptr(self: anytype, address: u64) ?LiveAllocation {
    const record = self.vtable_tracker.lookupRecord(address) orelse return null;
    const base = if (record.owner_base != 0) record.owner_base else address;
    const size = self.memory_forwarder.allocationSize(base) orelse return null;
    if (address < base or address - base >= size) return null;
    return .{ .base = base, .size = size };
}

pub fn recoverLiveAllocationVtable(self: anytype, address: u64, current_value: u64) ?u64 {
    // This callback is reached from every interpreted 64-bit memory read.
    // Reject the overwhelmingly common non-candidate case before consulting
    // allocation metadata or building symbol evidence. Non-zero recovery is
    // opt-in and disabled by the default safety policy.
    if (current_value >= 0x1000 and !self.vtable_tracker.policy.repair_nonzero_corruption) return null;

    const has_heap_history = self.vtable_tracker.hasTrustedHistory(address);
    const has_modeled_history = current_value < 0x1000 and self.vtable_stack_registry.contains(address);
    if (!has_heap_history and !has_modeled_history) return null;

    const exact_live_base = has_heap_history and self.memory_forwarder.allocationSize(address) != null;
    // A secondary base's vptr sits at a non-zero offset inside the object, so
    // "is this the allocation base" is the wrong liveness question for it —
    // asking it left every multiple-inheritance object with its primary vptr
    // repaired and its secondary still cleared. What authorises the repair is
    // the tracked record at this exact address; liveness only has to establish
    // that the storage is still the same object, which is what the owner check
    // below adds. Without it, an allocation that was freed and handed to a
    // different class could have the previous occupant's vtable written into
    // what is now an ordinary data member — silently, and with no fault
    // anywhere to report it. That would be worse than the null being repaired.
    const within_live_allocation = has_heap_history and liveOwnerForTrackedVptr(self, address) != null;

    // Phase 1: low-read recovery (value < 0x1000, e.g. cleared to 0 or small sentinel)
    if (has_heap_history) {
        if (self.vtable_tracker.assessLowRead(
            address,
            current_value,
            within_live_allocation,
        )) |recovery| {
            return logAndReturnRecovery(self, address, recovery, current_value);
        }
    }

    // Phase 2: non-zero corruption recovery (value >= 0x1000 but NOT a valid vtable)
    // Build evidence for the current value.  If the evidence is rejected, the
    // allocation's vptr has been corrupted to a non-zero invalid pointer.
    // Skip the expensive evidence-building when the address has no vtable
    // history — only tracked vtables can be restored.
    if (current_value >= 0x1000 and exact_live_base) {
        const current_evidence = vtableIdentityEvidence(self, current_value);
        const current_rejection = current_evidence.rejection(self.vtable_tracker.policy);
        if (self.vtable_tracker.assessCorruption(
            address,
            current_value,
            current_rejection,
            exact_live_base,
        )) |corruption| {
            return logAndReturnRecovery(self, address, corruption, current_value);
        }
    }

    // Phase 3: modeled/stack-local object recovery — fallback for objects
    // whose vtable was written by Rosette's synthetic C++ object model
    // (e.g. basic_streambuf subobjects in stringstreams).  These are not
    // tracked by memory_forwarder.allocationSize(), so the heap-based
    // recovery above returns null even when a known vptr was corrupted.
    //
    // Only low-value reads are repaired; non-zero corruption recovery
    // for modeled objects is intentionally not supported to avoid false
    // positives from objects that legitimately change their vptr.
    if (has_modeled_history) return recoverModeledStackVtable(self, address, current_value);

    return null;
}

/// Phase 3 reporting, held out of line (F1). Reached only for an address the
/// synthetic C++ object model itself wrote a vptr to.
noinline fn recoverModeledStackVtable(self: anytype, address: u64, current_value: u64) ?u64 {
    const recovery = self.vtable_stack_registry.assessLowRead(address, current_value) orelse return null;
    if (!self.vtable_stack_registry.noteRecovery(address, recovery.generation)) return null;
    const recovered = recovery.value;
    const kind = "stack-modeled low-read";
    const symbol = self.metadata.nearestSymbol(recovered);
    const prior = recovery.prior_recoveries;
    machoCapturePrint(
        "macho-processor: trusted vtable {s} recovery: object=0x{x} generation={d} allocation_size=0 observed=0x{x} restored=0x{x} vtable={s}+0x{x} established_by=0x{x}@{d} last_write=0x{x}@{d} prior_recoveries={d} thread=0x{x}\n",
        .{
            kind,
            address,
            recovery.generation,
            current_value,
            recovered,
            self.metadata.symbolLabel(recovered),
            if (symbol) |s| s.offset else 0,
            recovery.established_by.writer_rip,
            recovery.established_by.writer_step,
            recovery.last_write.writer_rip,
            recovery.last_write.writer_step,
            prior,
            self.active_guest_thread,
        },
    );
    return recovered;
}

noinline fn logAndReturnRecovery(self: anytype, address: u64, recovery: vt.Recovery, observed: u64) ?u64 {
    const symbol = self.metadata.nearestSymbol(recovery.value) orelse return null;
    if (!self.vtable_tracker.noteRecovery(address, recovery.generation)) return null;
    const kind = if (observed < 0x1000) "low-read" else "corruption";
    // Which subobject this vptr belongs to. A repair at a non-zero offset is a
    // secondary base's vptr, and reading the log without that offset makes two
    // repairs on one object look like two unrelated objects.
    const allocation = liveOwnerForTrackedVptr(self, address) orelse owningAllocationBase(self, address);
    const object_base = if (allocation) |live| live.base else address;
    machoCapturePrint(
        "macho-processor: trusted vtable {s} recovery: object=0x{x} subobject_offset={d} slot={s} generation={d} allocation_size={d} observed=0x{x} restored=0x{x} vtable={s}+0x{x} established_by=0x{x}@{d} last_write=0x{x}@{d} prior_recoveries={d} thread=0x{x}\n",
        .{
            kind,
            address,
            address -% object_base,
            if (address == object_base) "primary" else "secondary_base",
            recovery.generation,
            self.memory_forwarder.allocationSize(object_base) orelse 0,
            observed,
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
    if (observed < 0x1000) {
        machoCapturePrint(
            "macho-processor: VTABLE OWNERSHIP FRONTIER: first_invalid=tracked_vptr_storage_divergence slot=0x{x} expected=0x{x} observed=0x{x} generation={d} owner_base=0x{x} last_tracked_writer=0x{x}@{d}; the live object's bytes no longer match the last accepted vptr transition. Recovery is authorised by exact slot identity plus live-allocation ownership. Every *guest* store width now reports through the mutation contract, so a producer that reached here unseen is a host-side write — Rosette code that took a mutable range from guestMemory (mmap fill, file read, an import shim's output buffer) — or an alias-coherence defect. If the writer had been a guest store there would be a `mutation=` line naming it at the step it happened\n",
            .{
                address,
                recovery.value,
                observed,
                recovery.generation,
                object_base,
                recovery.last_write.writer_rip,
                recovery.last_write.writer_step,
            },
        );
        // New unique predictor case: the vptr reading low means a bypassing
        // bulk/native write zeroed this object's header, and only the vptr
        // slot is being repaired. Scan the header region for every *other*
        // zeroed pointer slot and predict the casualty they will produce —
        // the next native member call that reads one of those fields (e.g. an
        // ownership pointer at +0x8) will carry a null receiver. This fires
        // before the fault: the first vptr re-read after the clobber precedes
        // the member call that dereferences the field.
        reportObjectHeaderClobber(self, object_base, recovery);
    }
    return recovery.value;
}

/// Scan the header region of a live tracked object whose vptr was just
/// observed reading low, and feed every other zeroed pointer slot to the
/// near-null predictor as an `object_header_clobber` event. Only slots that
/// read as exactly zero are listed — a legitimate null field would be noise,
/// but the vptr being zero is proof a bulk write ran through this region, so
/// the co-zeroed slots are the fields the next member call will dereference
/// as null.
fn reportObjectHeaderClobber(self: anytype, object_base: u64, recovery: vt.Recovery) void {
    if (!@hasField(@TypeOf(self.*), "near_null_predictor")) return;
    const allocation_size = self.memory_forwarder.allocationSize(object_base) orelse return;
    const scan_len: usize = @intCast(@min(allocation_size, 64));
    const bytes = guestMemoryConst(self, object_base, scan_len) orelse return;
    var zeroed: [8]u64 = undefined;
    var count: usize = 0;
    var off: usize = 0;
    while (off + 8 <= scan_len) : (off += 8) {
        const value = std.mem.readInt(u64, bytes[off..][0..8], .little);
        if (value == 0) {
            if (count < zeroed.len) {
                zeroed[count] = off;
                count += 1;
            }
        }
    }
    if (count == 0) return;
    const type_symbol = self.metadata.symbolLabel(recovery.value);
    self.near_null_predictor.noteObjectHeaderClobber(
        self,
        object_base,
        type_symbol,
        allocation_size,
        zeroed[0..count],
        recovery.last_write.writer_step,
    );
}

pub fn logLiveVtableGuardSummary(self: anytype) void {
    // Printed first: the counters below say how many restores happened, and
    // that number is only readable next to how many were refused and why.
    if (comptime @hasField(@TypeOf(self.*), "vtable_clobber_predictor")) {
        self.vtable_clobber_predictor.dump("vtable_guard_summary");
    }
    machoCapturePrint(
        "macho-processor: vtable runtime: low_reads_checked={d} recoveries={d} write_time_mutations={d} tracked_objects={d} establishments={d} transitions={d} rejected_candidates={d} low_clears={d} retired={d} heap_corruption_detections={d} vptr_range_mutations={d} vptr_truncated_ranges={d} atomic_rollbacks={d} atomic_qwords_restored={d} guard_tracked={d} memory_writes={d} provenance_range_mutations={d} provenance_truncated_ranges={d}; recovery requires a tracked vptr slot inside a live allocation and a complete mapped Itanium ZTV dispatch head (offset-to-top, RTTI, and first slot) — the slot may be a secondary base's vptr at a non-zero offset, not only the object's primary\n",
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
            self.vtable_tracker.range_mutations,
            self.vtable_tracker.truncated_range_mutations,
            self.vtable_tracker.atomic_mutation_rollbacks,
            self.vtable_tracker.atomic_qwords_restored,
            self.guard_rollback.count(),
            self.memory_writes.entries.count(),
            self.memory_writes.range_mutations,
            self.memory_writes.truncated_range_mutations,
        },
    );
}

/// Decide what a vtable clobber means from block identity alone.
///
/// Separated from the reporting so the reasoning is testable without a machine
/// state: this is the sentence a reader will act on, and it is the part that
/// can be wrong in a way no compiler catches.
pub fn clobberVerdict(has_base: bool, base_block: ?u64, target_block: ?u64) []const u8 {
    if (!has_base) {
        return "no base register in the address expression; the target was formed from a displacement or index alone";
    }
    if (base_block == null and target_block == null) {
        return "neither the writer's base pointer nor the byte it wrote belongs to a tracked live allocation; both are outside the forwarded arena";
    }
    if (base_block == null) {
        return "WRITER POINTER IS NOT A LIVE ALLOCATION: the base register does not point inside any tracked block, so it is stale or garbage. The defect is whatever produced this pointer, not the allocator";
    }
    if (target_block == null) {
        return "the writer's base is a live allocation but the byte it wrote is outside every tracked block: the write ran past the end of its own buffer";
    }
    if (base_block.? == target_block.?) {
        return "ALLOCATOR OVERLAP: the writer's base and the clobbered byte are the SAME live allocation, so a live object occupies memory the runtime handed to this writer. Investigate allocation reuse, not the writer";
    }
    return "WRITER ESCAPED ITS BLOCK: the base register points into one live allocation and the write landed in a different one. The write crossed a block boundary — check the length or index that carried it there";
}

/// Explain a vtable clobber by asking where the *writer* thought it was writing.
///
/// Naming the writing function is not a diagnosis. `fmt::detail::to_pointer`
/// legitimately writes into a formatting buffer; the question is why that
/// buffer's address landed on a live object's vtable slot. There are exactly
/// two ways that happens, and they need opposite repairs:
///
///   * The writer's own pointer is wrong. Its base register points into a
///     *different* allocation than the byte it wrote, so it walked out of its
///     buffer, or was handed a stale/garbage pointer. The defect is upstream of
///     the write, in whatever produced that pointer.
///   * The writer's pointer is right and the allocator is wrong. Base and
///     target belong to the same allocation — which means the runtime handed
///     that allocation out while a live object still occupied it, and the two
///     objects overlap.
///
/// One line decides which. Without it the report names a function and leaves
/// the reader to guess, which is how a corrupted-buffer bug and an overlapping
/// -allocation bug become indistinguishable.
///
/// Diagnostic-only: reached solely from the clobber path, which is already
/// throttled, and `containingAllocation` scans allocations linearly.
pub fn reportClobberWriterProvenance(self: anytype, target: u64) void {
    const target_allocation = self.memory_forwarder.containingAllocation(target);

    const bytes = self.guestMemoryConst(self.regs.rip, 16) orelse {
        machoCapturePrint(
            "macho-processor: vtable clobber provenance: target=0x{x} writer_rip=0x{x} decode=unavailable; the writing instruction's bytes are unreadable, so the address expression cannot be recovered\n",
            .{ target, self.regs.rip },
        );
        return;
    };
    const decoded = decodeInsn(bytes);
    const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
    const base_value = if (decoded.sib_has_base)
        x64_decoder.regVal(&self.regs, decoded.sib_base_reg, address_size)
    else
        0;
    const base_allocation = if (decoded.sib_has_base)
        self.memory_forwarder.containingAllocation(base_value)
    else
        null;

    // The verdict. Same allocation on both sides means the writer was inside
    // its own block and the block overlapped a live object.
    const verdict = clobberVerdict(
        decoded.sib_has_base,
        if (base_allocation) |block| block.base else null,
        if (target_allocation) |block| block.base else null,
    );

    machoCapturePrint(
        "macho-processor: vtable clobber provenance: target=0x{x} writer_rip=0x{x} op={s} base({s})=0x{x} index({s},scale={d}) disp=0x{x} target_block={s} base_block={s} verdict={s}\n",
        .{
            target,
            self.regs.rip,
            @tagName(decoded.op),
            if (decoded.sib_has_base) @tagName(decoded.sib_base_reg) else "<none>",
            base_value,
            if (decoded.sib_has_index) @tagName(decoded.sib_index_reg) else "<none>",
            @as(u8, 1) << decoded.sib_scale,
            decoded.addr,
            if (target_allocation != null) "live" else "<untracked>",
            if (base_allocation != null) "live" else "<untracked>",
            verdict,
        },
    );
    if (target_allocation) |block| {
        machoCapturePrint(
            "macho-processor: vtable clobber provenance:   target block base=0x{x} size={d} offset=0x{x}\n",
            .{ block.base, block.size, block.offset },
        );
    }
    if (base_allocation) |block| {
        machoCapturePrint(
            "macho-processor: vtable clobber provenance:   writer block base=0x{x} size={d} offset=0x{x} bytes_to_end={d}\n",
            .{ block.base, block.size, block.offset, block.size - block.offset },
        );
    }
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
    const offset_to_top = std.mem.readInt(i64, table[0..8], .little);
    const offset_bound: i64 = @intCast(@min(
        self.vtable_tracker.policy.max_offset_to_top,
        @as(u64, std.math.maxInt(i64)),
    ));
    evidence.offset_to_top_plausible =
        offset_to_top >= -offset_bound and offset_to_top <= offset_bound;
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
    recordAllocationWriteKind(self, addr, size, val, .scalar, addr, 8);
}

/// Ask the clobber predictor whether this restore is a repair or a corruption.
///
/// Held out of line because the caller is on the store path and this is reached
/// only from the `trusted_value_cleared` branch — twelve times in a
/// three-billion-step run. A refusal also retires the record: once a slot is
/// judged to be live scratch there is nothing to defend, and leaving the record
/// in place would keep paying the Bloom hit and keep re-asking the same
/// question every time the guest reuses that stack depth.
noinline fn vtableClobberRestoreAllowed(
    self: anytype,
    address: u64,
    owner_base: u64,
    expected_vptr: u64,
    observed: u64,
) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "vtable_clobber_predictor")) return true;
    const verdict = self.vtable_clobber_predictor.assess(
        address,
        owner_base,
        expected_vptr,
        observed,
        self.regs.rip,
        self.regs.rsp,
        self.regs.rbp,
        self.executed_steps,
        self.active_guest_thread,
    );
    if (!verdict.refused()) return true;
    _ = self.vtable_tracker.retireAddress(address);
    return false;
}

fn writeTrackedSlotDirect(self: anytype, address: u64, value: u64) bool {
    if (self.sparse_memory.bytes(address, 8, true)) |storage| {
        std.mem.writeInt(u64, storage[0..8], value, .little);
        return true;
    }
    const off = translateGuest(self, address, 8, .write) orelse return false;
    if (off + 8 > self.mem.len) return false;
    std.mem.writeInt(u64, self.mem[off..][0..8], value, .little);
    return true;
}

fn recordAllocationWriteKind(
    self: anytype,
    addr: u64,
    size: Size,
    val: u64,
    mutation_kind: vt.MutationKind,
    mutation_address: u64,
    mutation_length: u64,
) void {
    if (size != .bits64) return;
    if (addr < 0x1000 or (addr & 7) != 0) return;

    // Correctness and diagnostics have different owners here.
    //
    // An authentic constructor write of an image-owned `_ZTV` address point
    // must always establish identity. Otherwise read-time recovery silently
    // depends on ROSETTE_MACHO_WRITE_DIAGNOSTICS and the same constructed C++
    // object is valid in an instrumented run but has a null vptr in a normal
    // run. Keep the production path cheap: two image-range comparisons reject
    // ordinary integers, heap/stack pointers and JIT addresses before either
    // an allocation-map lookup or a symbol lookup.
    //
    // Once a slot has trusted history, clears and replacements are a
    // correctness concern in every run, not optional write diagnostics.  The
    // Bloom filter keeps the normal-store cost bounded to two bit tests, and a
    // real hash lookup confirms positives before any ownership/symbol work.
    const plausible_vtable = shouldObserveVtableWrite(
        self.write_diagnostics_armed,
        val,
        self.mapped_min,
        self.image_end,
    );
    const tracked_slot = self.vtable_tracker.mightContain(addr) and
        self.vtable_tracker.hasTrustedHistory(addr);
    if (!plausible_vtable and !tracked_slot) return;

    // Destination ownership is cheaper and more selective than symbol/section
    // classification. Prove this write lands in a live allocation before asking
    // metadata to identify an image pointer as an Itanium vtable.
    //
    // Deliberately the *containing* allocation and not the exact base: a class
    // with multiple inheritance writes a vptr per non-primary base at non-zero
    // offsets inside the object, and requiring offset zero dropped every one of
    // them here — before evidence was even built. The read side then had
    // nothing to recover from, so a cleared secondary vptr stayed null and the
    // first virtual call through that base dispatched through it.
    //
    // The cost is unchanged in the common case: `shouldObserveVtableWrite`
    // above has already rejected everything whose value is not an image
    // pointer, so this lookup is only reached by the rare write that plausibly
    // stores a vtable.
    const owner = if (tracked_slot)
        (liveOwnerForTrackedVptr(self, addr) orelse return)
    else
        (owningAllocationBase(self, addr) orelse return);
    const evidence = vtableIdentityEvidence(self, val);
    if (!self.write_diagnostics_armed and !tracked_slot and
        !evidence.isTrusted(self.vtable_tracker.policy)) return;
    const result = self.vtable_tracker.observeWrite(
        addr,
        evidence,
        .{
            .writer_rip = self.regs.rip,
            .writer_step = self.executed_steps,
            .writer_thread = self.active_guest_thread,
            .owner_base = owner.base,
            .mutation_kind = mutation_kind,
        },
    );
    const transition_count = self.vtable_tracker.trusted_transitions;
    // N7 (perf audit): the lifecycle-transition log (a full formatted write
    // per object during static init) is gated behind
    // initializer_detail_logging. observeWrite above is untouched — vptr
    // write-protection recovery is correctness-bearing, only the log is
    // diagnostic. Failure-path vtable diagnostics in initializers.zig remain
    // unconditional.
    if (self.initializer_detail_logging and
        result.disposition == .valid_transition and
        recovery_ledger.throttled(transition_count))
    {
        const previous_symbol = self.metadata.nearestSymbol(result.previous_vptr);
        const previous_origin = vt.ownership.classifyOrigin(result.previous_vptr, self.metadata);
        const current_symbol = self.metadata.nearestSymbol(result.trusted_vptr);
        const current_origin = vt.ownership.classifyOrigin(result.trusted_vptr, self.metadata);
        machoCapturePrint(
            "macho-processor: vtable lifecycle transition: object=0x{x} generation={d} previous=0x{x}({s}+0x{x}) origin={s} current=0x{x}({s}+0x{x}) origin={s} writer=0x{x} step={d} thread=0x{x}\n",
            .{
                addr,
                result.generation,
                result.previous_vptr,
                self.metadata.symbolLabel(result.previous_vptr),
                if (previous_symbol) |s| s.offset else 0,
                @tagName(previous_origin),
                result.trusted_vptr,
                self.metadata.symbolLabel(result.trusted_vptr),
                if (current_symbol) |s| s.offset else 0,
                @tagName(current_origin),
                self.regs.rip,
                self.executed_steps,
                self.active_guest_thread,
            },
        );
    }

    // Log when a known vtable allocation base is cleared to zero (or a small
    // sentinel < 0x1000).  The first 8 events are logged individually; after
    // that only power-of-two milestones.  This matches the transition throttle
    // pattern and prevents log flooding while still revealing the writer RIP
    // for the earliest occurrences.
    if (result.disposition == .trusted_value_cleared and
        result.previous_vptr >= 0x1000 and
        recovery_ledger.throttled(self.vtable_tracker.low_clears_observed))
    {
        const vtable_symbol = self.metadata.nearestSymbol(result.previous_vptr);
        const writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
        const writer_name = self.metadata.symbolLabel(self.regs.rip);
        const writer_off = if (writer_symbol) |s| s.offset else 0;
        machoCapturePrint(
            "macho-processor: vtable cleared: object=0x{x} gen={d} vtable=0x{x}({s}+0x{x}) writer=0x{x} {s}+0x{x} step={d} thread=0x{x} mutation={s} range=[0x{x},+0x{x})\n",
            .{
                addr,
                result.generation,
                result.previous_vptr,
                self.metadata.symbolLabel(result.previous_vptr),
                if (vtable_symbol) |s| s.offset else 0,
                self.regs.rip,
                writer_name,
                writer_off,
                self.executed_steps,
                self.active_guest_thread,
                @tagName(mutation_kind),
                mutation_address,
                mutation_length,
            },
        );
        reportClobberWriterProvenance(self, addr);
    }

    // Write-side vptr protection: when a zero/small-value write clears a
    // trusted vtable pointer at a still-live allocation base, immediately
    // restore the vptr.  This prevents the cascade where a zeroed vptr gets
    // read before the allocation is retired (forgetAddress), and prevents
    // corrupted reads during shutdown.  The write-back is direct (bypassing
    // write64/writeMemVal) to avoid re-entering recordAllocationWrite.
    if (result.disposition == .trusted_value_cleared and
        result.previous_vptr >= 0x1000)
    {
        // The restore is a store Rosette performs into guest memory, so it has
        // to answer for itself. A tracked slot inside the writing thread's own
        // frame is scratch the current call owns, not an object header, and
        // writing a vtable pointer there hands the writer a pointer it will
        // dereference. Judged here rather than at the read side because this
        // is the only point that still has the writer's registers.
        if (!vtableClobberRestoreAllowed(self, addr, owner.base, result.previous_vptr, val)) return;
        if (!writeTrackedSlotDirect(self, addr, result.previous_vptr)) return;
        self.vtable_tracker.live_vtable_write_protections +|= 1;
        const vtable_symbol = self.metadata.nearestSymbol(result.previous_vptr);
        const prot_writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
        machoCapturePrint(
            "macho-processor: VTABLE MUTATION CONTRACT: first_invalid=trusted_vptr_overwrite slot=0x{x} owner_base=0x{x} subobject_offset=0x{x} generation={d} expected=0x{x}({s}+0x{x}) observed=0x{x} writer=0x{x} {s}+0x{x} step={d} thread=0x{x} mutation={s} range=[0x{x},+0x{x}) action=restore_trusted_vptr\n",
            .{
                addr,
                owner.base,
                addr - owner.base,
                result.generation,
                result.previous_vptr,
                self.metadata.symbolLabel(result.previous_vptr),
                if (vtable_symbol) |s| s.offset else 0,
                val,
                self.regs.rip,
                self.metadata.symbolLabel(self.regs.rip),
                if (prot_writer_symbol) |s| s.offset else 0,
                self.executed_steps,
                self.active_guest_thread,
                @tagName(mutation_kind),
                mutation_address,
                mutation_length,
            },
        );
    }
}

/// Whether a 64-bit allocation-base store can affect trusted vtable identity.
///
/// Armed diagnostics must see all values so they can attribute clears and
/// corruption. The production path only admits pointers into the original
/// Mach-O image; strict `_ZTV` evidence is checked immediately afterwards.
pub fn shouldObserveVtableWrite(
    write_diagnostics_armed: bool,
    value: u64,
    mapped_min: u64,
    image_end: u64,
) bool {
    if (write_diagnostics_armed) return true;
    return mapped_min != std.math.maxInt(u64) and
        value >= mapped_min and value < image_end;
}

test "production vtable observation is independent from diagnostic provenance" {
    const mapped_min: u64 = 0x4000;
    const image_end: u64 = 0x0200_0000;

    // The VulkanPresenter vptr shape: an address point in Mach-O data must be
    // admitted even in the ordinary non-diagnostic run.
    try std.testing.expect(shouldObserveVtableWrite(
        false,
        0x0198_1b10,
        mapped_min,
        image_end,
    ));

    // Heap, stack and generated-code values stay off the symbol/allocation
    // lookup path. Full diagnostics intentionally admits them for attribution.
    try std.testing.expect(!shouldObserveVtableWrite(
        false,
        0x0678_ebb0,
        mapped_min,
        image_end,
    ));
    try std.testing.expect(shouldObserveVtableWrite(
        true,
        0,
        mapped_min,
        image_end,
    ));
    try std.testing.expect(!shouldObserveVtableWrite(
        false,
        0x0198_1b10,
        std.math.maxInt(u64),
        image_end,
    ));
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
            self.metadata.symbolLabel(self.regs.rip),
        },
    );
}

/// Whether the GPU ring watch has been armed at all. Two loads and a compare,
/// asked before the call rather than as its first statement.
inline fn ringBufferWatchActive(self: anytype) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_ring_watch_base")) return false;
    return self.gpu_ring_watch_base != 0 and self.gpu_ring_watch_size != 0;
}

/// Whether a store can possibly be a vtable establishment. Mirrors the first
/// two lines of `recordAllocationWrite`: only an aligned 64-bit store above the
/// null page can be one, which excludes every byte the JIT emits.
inline fn allocationWriteWanted(addr: u64, size: Size) bool {
    return size == .bits64 and addr >= 0x1000 and (addr & 7) == 0;
}

/// Whether a store could possibly be the heap-corruption pattern the write
/// diagnostics look for: an aligned 64-bit store of a value inside the host
/// image's executable range.
///
/// Note the two former copies of this test disagreed on their lower bound —
/// the sparse arm used `MIN_PLAUSIBLE_CODE_POINTER`, the linear arm the literal
/// `0x100000`. They are the same number; the constant now names it once, so a
/// future change to it cannot move only one of the two arms.
inline fn suspiciousCodePointerWriteWanted(self: anytype, size: Size, val: u64) bool {
    return self.write_diagnostics_armed and size == .bits64 and
        val >= MIN_PLAUSIBLE_CODE_POINTER and
        val >= self.executable_min and val < self.executable_max;
}

/// Report a 64-bit store of a function-prologue address into heap or mapped
/// data — the tree-node structural corruption pattern.
///
/// Held out of line (F1): reached only under `ROSETTE_MACHO_WRITE_DIAGNOSTICS`,
/// and both former copies were inlined into `writeMemVal`, which every guest
/// store calls.
noinline fn reportSuspiciousCodePointerWrite(self: anytype, addr: u64, val: u64, route: []const u8) void {
    if (self.memory_forwarder.allocationSize(addr) == null and !isAddressInMappedMemory(self, addr)) return;
    if (!detectFunctionProloguePtr(val)) return;
    self.vtable_tracker.heap_corruption_detections +|= 1;
    const writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
    machoCapturePrint(
        "macho-processor: suspicious allocation write ({s}): addr=0x{x} value=0x{x} (function prologue) writer=0x{x} {s}+0x{x} step={d}\n",
        .{
            route,
            addr,
            val,
            self.regs.rip,
            self.metadata.symbolLabel(self.regs.rip),
            if (writer_symbol) |s| s.offset else 0,
            self.executed_steps,
        },
    );
}

/// A store whose address translates through neither the sparse mappings nor
/// the contiguous image. Terminal unless it is an initializer dependency the
/// runtime can defer. Held out of line for the same reason as the read side.
noinline fn reportScalarWriteFault(self: anytype, addr: u64, size: Size, bytes: u8) void {
    if (deferInitializerRuntimeDependency(self, addr, size)) return;
    const snapshot = currentInstructionSnapshot(self);
    const instruction = if (snapshot.operation.len != 0) snapshot.operation else @tagName(if (self.execution_history.latestFor(self.active_guest_thread)) |e| e.op else .invalid);
    terminateForGuestAccess(self, addr, bytes, .write, instruction);
}

pub fn writeMemVal(self: anytype, addr: u64, size: Size, val: u64) void {
    // Each of these observers begins by testing state the store already has in
    // hand, and every one of those tests used to happen on the far side of a
    // call. A store is the other most frequent thing a guest does — the JIT
    // code generator writes every byte it emits — so the gates are asked here,
    // where an uninterested observer costs a compare instead of a call frame.
    if (ringBufferWatchActive(self)) noteRingBufferWrite(self, addr, size, val);
    const bytes = bytesForSize(size);
    if (self.sparse_memory.bytes(addr, bytes, true)) |storage| {
        if (memoryTraceWanted(self)) recordMemoryAccess(self, addr, size, "write", val);
        noteGuestWrite(self, addr, bytes);
        if (size == .bits64 and (addr & 7) == 0) {
            const provenance = provenanceWanted(self, addr);
            const pointer_provenance = shouldRecordGuestCodePointer(self, size, val);
            if (provenance or pointer_provenance) {
                const previous = std.mem.readInt(u64, storage[0..8], .little);
                if (provenance) {
                    self.memory_writes.record(self.allocator, addr, previous, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
                } else {
                    recordGuestCodePointerWrite(self, addr, previous, val);
                }
            }
            std.mem.writeInt(u64, storage[0..8], val, .little);
        } else {
            const pointer_provenance = shouldRecordGuestCodePointer(self, size, val) and
                !self.write_diagnostics_armed and !self.provenance_watch.covers(addr);
            const pointer_previous: u64 = if (pointer_provenance and size == .bits32)
                std.mem.readInt(u32, storage[0..4], .little)
            else
                0;
            const mutation = captureMemoryMutation(self, addr, bytes);
            switch (size) {
                .bits8 => storage[0] = @truncate(val),
                .bits16 => std.mem.writeInt(u16, storage[0..2], @truncate(val), .little),
                .bits32 => std.mem.writeInt(u32, storage[0..4], @truncate(val), .little),
                .bits64 => std.mem.writeInt(u64, storage[0..8], val, .little),
            }
            commitMemoryMutation(self, mutation, .partial_scalar);
            if (pointer_provenance) recordGuestCodePointerWrite(self, addr, pointer_previous, val);
        }
        if (allocationWriteWanted(addr, size)) recordAllocationWrite(self, addr, size, val);
        // Suspicious write: 64-bit value pointing into executable (code) segment
        // written to any heap/data memory — tree node structural corruption pattern.
        // Values below 0x100000 are not plausible code pointers (e.g. MicroProfile token IDs).
        // Only function_prologue values are genuinely suspicious; generic
        // code_address writes are legitimate initialization (Export struct
        // function pointer storage, hash table bucket counts, CommandVar
        // default value pointers).
        if (suspiciousCodePointerWriteWanted(self, size, val)) {
            reportSuspiciousCodePointerWrite(self, addr, val, "writeMemVal sparse");
        }
        if (self.timer_queue_watch.active) timerQueueWatchWrite(self, addr, size, val);
        return;
    }
    const off = translateGuest(self, addr, bytes, .write) orelse {
        reportScalarWriteFault(self, addr, size, bytes);
        return;
    };
    if (memoryTraceWanted(self)) recordMemoryAccess(self, addr, size, "write", val);
    self.initializer_memory.capture(self.mem, @intCast(off), bytes);
    noteGuestWrite(self, addr, bytes);
    if (size == .bits64 and (addr & 7) == 0) {
        const provenance = provenanceWanted(self, addr);
        const pointer_provenance = shouldRecordGuestCodePointer(self, size, val);
        if (provenance or pointer_provenance) {
            const previous = std.mem.readInt(u64, self.mem[off..][0..8], .little);
            if (provenance) {
                self.memory_writes.record(self.allocator, addr, previous, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
            } else {
                recordGuestCodePointerWrite(self, addr, previous, val);
            }
        }
        std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
    } else {
        const pointer_provenance = shouldRecordGuestCodePointer(self, size, val) and
            !self.write_diagnostics_armed and !self.provenance_watch.covers(addr);
        const pointer_previous: u64 = if (pointer_provenance and size == .bits32)
            std.mem.readInt(u32, self.mem[off..][0..4], .little)
        else
            0;
        const mutation = captureMemoryMutation(self, addr, bytes);
        switch (size) {
            .bits8 => self.mem[off] = @truncate(val),
            .bits16 => std.mem.writeInt(u16, self.mem[off..][0..2], @truncate(val), .little),
            .bits32 => std.mem.writeInt(u32, self.mem[off..][0..4], @truncate(val), .little),
            .bits64 => std.mem.writeInt(u64, self.mem[off..][0..8], val, .little),
        }
        commitMemoryMutation(self, mutation, .partial_scalar);
        if (pointer_provenance) recordGuestCodePointerWrite(self, addr, pointer_previous, val);
    }
    if (allocationWriteWanted(addr, size)) recordAllocationWrite(self, addr, size, val);
    // Suspicious write: 64-bit value pointing into executable (code) segment
    // written to any heap/data memory — tree node structural corruption pattern.
    // Values below 0x100000 are not plausible code pointers (e.g. MicroProfile token IDs).
    // Only function_prologue values are genuinely suspicious; generic
    // code_address writes are legitimate initialization (Export struct
    // function pointer storage, hash table bucket counts, CommandVar
    // default value pointers).
    if (suspiciousCodePointerWriteWanted(self, size, val)) {
        reportSuspiciousCodePointerWrite(self, addr, val, "writeMemVal reg");
    }
    if (self.timer_queue_watch.active) timerQueueWatchWrite(self, addr, size, val);
}

/// Should this store be recorded in write provenance?
///
/// Either the global flag is on, or the address falls in a watched region.
/// The watch set is what replaces "re-run with ROSETTE_MACHO_WRITE_DIAGNOSTICS
///=1" as the answer to "who wrote this field" — a flag asks the operator to
/// predict, before the run, which address will matter.
pub fn provenanceWanted(self: anytype, address: u64) bool {
    if (self.write_diagnostics_armed) return true;
    if (comptime !@hasField(@TypeOf(self.*), "provenance_watch")) return false;
    return self.provenance_watch.contains(address);
}

/// Report a guest store that landed inside the GPU command ring.
///
/// The first such store is the transition the whole graphics stack is waiting
/// on: it is the difference between "the producer prepared a packet and did not
/// publish it" and "the producer never ran". Bounded to the first few, because
/// once the ring is being written the interesting fact is that it started, not
/// every dword.
///
/// Deliberately observation only — nothing here writes to the ring, advances a
/// pointer, or reports a payload the guest did not produce.
pub fn noteRingBufferWrite(self: anytype, address: u64, size: Size, value: u64) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_ring_watch_base")) return;
    const base = self.gpu_ring_watch_base;
    if (base == 0 or self.gpu_ring_watch_size == 0) return;
    // The ring address Xenia prints is Xbox physical, but interpreted x86
    // stores use one of Xenia's host aliases. Compare against the discovered
    // translated aliases first. The low-32 fallback is retained for runtimes
    // that do not expose the view model yet.
    var ring_offset: ?u64 = null;
    if (comptime @hasField(State, "gpu_ring_watch_host_physical")) {
        const physical = self.gpu_ring_watch_host_physical;
        const virtual = self.gpu_ring_watch_host_virtual;
        if (physical != 0 and address >= physical and address - physical < self.gpu_ring_watch_size) {
            ring_offset = address - physical;
        } else if (virtual != 0 and address >= virtual and address - virtual < self.gpu_ring_watch_size) {
            ring_offset = address - virtual;
        }
    }
    if (ring_offset == null) {
        const low: u32 = @truncate(address);
        const ring_low: u32 = @truncate(base);
        if (low >= ring_low and low -% ring_low < self.gpu_ring_watch_size) {
            ring_offset = low -% ring_low;
        }
    }
    const offset = ring_offset orelse return;

    self.gpu_ring_writes +|= 1;
    if (!recovery_ledger.throttled(self.gpu_ring_writes)) return;
    machoCapturePrint(
        "macho-processor: gpu ring write #{d}: address=0x{x} ring_offset=0x{x} width={d} value=0x{x} rip=0x{x} {s} thread=0x{x}; this is an authentic guest store into the command ring — the producer is running. The view used is the address above; if the command processor reads a different physical alias of this page it will not see this dword\n",
        .{
            self.gpu_ring_writes,
            address,
            offset,
            bytesForSize(size),
            value,
            self.regs.rip,
            self.metadata.symbolLabel(self.regs.rip),
            self.active_guest_thread,
        },
    );
}

pub const MemoryMutationCapture = struct {
    provenance: memory_write_provenance.MutationCapture,
    vtables: vt.MutationCapture,
};

pub fn captureMemoryMutation(
    self: anytype,
    address: u64,
    length: u64,
) MemoryMutationCapture {
    const vtables = self.vtable_tracker.captureMutation(self, address, length);
    // R3 (N4): the before-image capture re-reads every overlapping pointer
    // slot (a full memory probe per store). It is fault-time diagnostics; when
    // write diagnostics are unarmed (the default fast path) return an empty
    // provenance capture so stores pay nothing for it. Vptr capture is a
    // separate correctness contract and uses its Bloom prefilter even when
    // generic provenance is disabled.
    const provenance = if (provenanceWanted(self, address) or vtables.count != 0)
        self.memory_writes.captureMutation(self, address, length)
    else
        memory_write_provenance.MutationCapture{ .address = address, .length = length };
    return .{ .provenance = provenance, .vtables = vtables };
}

pub fn commitMemoryMutation(
    self: anytype,
    capture: MemoryMutationCapture,
    kind: memory_write_provenance.WriteKind,
) void {
    // R3 (N4): matching gate to captureMemoryMutation. When unarmed the
    // capture is empty and the re-read/compare/record work is skipped.
    // The writer recorded below is `regs.rip` — the *faulting guest*
    // instruction — even when the write came from a Rosette repair rather than
    // from the guest. Reclassify while a repair is in flight so consumers can
    // tell the two apart instead of blaming a guest symbol for our own store.
    const attributed_kind: memory_write_provenance.WriteKind =
        if (comptime @hasField(@TypeOf(self.*), "host_repair_in_flight"))
            (if (self.host_repair_in_flight) .host_repair else kind)
        else
            kind;
    if (capture.provenance.count != 0 and provenanceWanted(self, capture.provenance.address)) {
        self.memory_writes.commitMutation(
            self.allocator,
            self,
            capture.provenance,
            self.regs.rip,
            self.executed_steps,
            self.active_guest_thread,
            attributed_kind,
        );
    }

    if (capture.vtables.count != 0) self.vtable_tracker.range_mutations +|= 1;
    if (capture.vtables.truncated) {
        self.vtable_tracker.truncated_range_mutations +|= 1;
        if (recovery_ledger.throttled(self.vtable_tracker.truncated_range_mutations)) {
            machoCapturePrint(
                "macho-processor: VTABLE MUTATION CONTRACT: coverage=truncated range=[0x{x},+0x{x}) retained_slots={d} tracked_slots={d} writer=0x{x} step={d} thread=0x{x}; no conclusion or repair is claimed for omitted vptr slots\n",
                .{
                    capture.vtables.address,
                    capture.vtables.length,
                    capture.vtables.count,
                    self.vtable_tracker.trackedAllocationCount(),
                    self.regs.rip,
                    self.executed_steps,
                    self.active_guest_thread,
                },
            );
        }
    }

    const vtable_kind: vt.MutationKind = switch (attributed_kind) {
        .scalar => .scalar,
        .partial_scalar => .partial_scalar,
        .bulk_fill => .bulk_fill,
        .bulk_copy => .bulk_copy,
        .vector_store => .vector_store,
        .host_repair => .host_repair,
    };
    for (capture.vtables.slots[0..capture.vtables.count]) |slot| {
        const current_record = self.vtable_tracker.lookupRecord(slot.address) orelse continue;
        if (current_record.generation != slot.generation) continue;
        const bytes = guestMemoryConst(self, slot.address, 8) orelse continue;
        const value = std.mem.readInt(u64, bytes[0..8], .little);
        if (value == slot.value) continue;
        const protections_before = self.vtable_tracker.live_vtable_write_protections;
        recordAllocationWriteKind(
            self,
            slot.address,
            .bits64,
            value,
            vtable_kind,
            capture.vtables.address,
            capture.vtables.length,
        );
        if (self.vtable_tracker.live_vtable_write_protections == protections_before) continue;

        // A memset/memcpy/partial store that invalidates a live vptr is one
        // atomic mutation contract, not an isolated eight-byte accident. The
        // same write may have cleared XObject's KernelState* (the immediately
        // following field in the observed Xbdm casualty), so restoring only
        // the vptr merely postpones the ownership crash. Roll back every
        // captured slot from this mutation that belongs to the same live
        // allocation. This is bounded by MutationCapture and is activated only
        // after exact vptr identity proves the whole mutation invalid.
        const owner = liveOwnerForTrackedVptr(self, slot.address) orelse continue;
        var restored_qwords: u64 = 0;
        for (capture.provenance.slots[0..capture.provenance.count]) |before| {
            if (before.address < owner.base or before.address - owner.base >= owner.size) continue;
            if (!writeTrackedSlotDirect(self, before.address, before.value)) continue;
            restored_qwords +|= 1;
        }
        self.vtable_tracker.atomic_mutation_rollbacks +|= 1;
        self.vtable_tracker.atomic_qwords_restored +|= restored_qwords;
        machoCapturePrint(
            "macho-processor: VTABLE MUTATION CONTRACT: action=rollback_invalid_atomic_mutation owner_base=0x{x} owner_size=0x{x} vptr_slot=0x{x} mutation={s} range=[0x{x},+0x{x}) restored_qword_chunks={d} capture_truncated={}; adjacent ownership and lifetime fields were restored from the same before-image because the mutation had already violated the live type identity\n",
            .{
                owner.base,
                owner.size,
                slot.address,
                @tagName(vtable_kind),
                capture.vtables.address,
                capture.vtables.length,
                restored_qwords,
                capture.provenance.truncated or capture.vtables.truncated,
            },
        );
    }
}

/// Perform a guest-memory write that Rosette originates as part of a fault
/// repair, marking it as host-authored in the write-provenance ledger.
///
/// Every recovery that writes guest memory must go through here. A repair that
/// writes through the ordinary path is indistinguishable from guest behaviour
/// afterwards, and the causality chain will confidently attribute it to
/// whichever guest instruction happened to be faulting.
pub fn writeMemValAsHostRepair(self: anytype, addr: u64, size: Size, val: u64) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "host_repair_in_flight")) {
        self.writeMemVal(addr, size, val);
        return;
    }
    const previous = self.host_repair_in_flight;
    self.host_repair_in_flight = true;
    defer self.host_repair_in_flight = previous;
    self.writeMemVal(addr, size, val);
}

pub fn deferInitializerRuntimeDependency(self: anytype, address: u64, size: Size) bool {
    if (self.initializer_checkpoint == null or address >= 0x1000 or size != .bits64) return false;

    const trace_count: usize = self.execution_history.countFor(self.active_guest_thread);
    if (trace_count == 0) return false;
    const fault_entry = self.execution_history.latestFor(self.active_guest_thread) orelse return false;
    if (fault_entry.rip != self.regs.rip or fault_entry.thread_handle != self.active_guest_thread) return false;
    const fault = decodeWithSnapshotOperands(self, fault_entry) orelse return false;
    if (fault.op != .mov_mem64_reg64 or !fault.sib_has_base) return false;
    const base_register = fault.sib_base_reg;
    if (traceRegisterValue(fault_entry, base_register) != address) return false;

    var after = address;
    var same_thread_distance: usize = 0;
    var reverse_index = trace_count;
    while (reverse_index != 0) {
        reverse_index -= 1;
        const entry = self.execution_history.chronological(self.active_guest_thread, reverse_index) orelse continue;
        same_thread_distance += 1;
        const before = traceRegisterValue(entry, base_register);
        if (before == after) {
            after = before;
            continue;
        }

        const producer = decodeWithSnapshotOperands(self, entry) orelse return false;
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

/// Decode the instruction recorded in a trace entry and resolve its memory
/// operand against **that entry's register snapshot** — the values as they were
/// when the instruction executed, not as they are now.
///
/// Using live registers here would compute an address the instruction never
/// touched, which is how a historical load gets attributed to the wrong slot.
pub fn decodeWithSnapshotOperands(self: anytype, entry: TraceEntry) ?DecodedInsn {
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
        if (self.sparse_memory.containsMapped(address, bytes)) {
            self.sparse_memory.logAccessFailure(address, bytes, access == .write);
        } else {
            // Do not label a primary contiguous-mapping denial as a sparse
            // contract failure. In particular, this exposes mmap/heap page
            // ownership collisions: a perfectly live allocation may be
            // denied because an earlier mprotect covered its shared page.
            const mapped_offset = mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address);
            const page_index = if (mapped_offset) |offset| offset / PAGE_SIZE else 0;
            const page_permissions: u8 = if (mapped_offset != null and page_index < self.page_permissions.len)
                self.page_permissions[@intCast(page_index)]
            else
                0;
            const allocation = self.memory_forwarder.containingAllocation(address);
            machoCapturePrint(
                "macho-processor: primary access contract FAILED: address=0x{x} end=0x{x} length={d} access={s} page_index={d} page_range=[0x{x},0x{x}) permissions={c}{c}{c} live_allocation={} allocation_base=0x{x} allocation_size={d} allocation_offset={d} diagnosis={s}\n",
                .{
                    address,
                    address +| bytes,
                    bytes,
                    @tagName(access),
                    page_index,
                    self.mem_base +| page_index *| PAGE_SIZE,
                    self.mem_base +| (page_index +| 1) *| PAGE_SIZE,
                    @as(u8, if (page_permissions & PAGE_READ != 0) 'r' else '-'),
                    @as(u8, if (page_permissions & PAGE_WRITE != 0) 'w' else '-'),
                    @as(u8, if (page_permissions & PAGE_EXECUTE != 0) 'x' else '-'),
                    allocation != null,
                    if (allocation) |live| live.base else 0,
                    if (allocation) |live| live.size else 0,
                    if (allocation) |live| live.offset else 0,
                    if (allocation != null) "live heap object denied by page permissions; inspect mmap page ownership/mprotect overlap" else "mapped address denied by primary page permissions",
                },
            );
        }
        // A protection fault at a *near-null* effective address is a different
        // finding from one at a real address: the page is protected on purpose
        // (a null-page guard), so the question is never "why is this page
        // protected" but "what made the pointer near-null". That question has
        // an evidence path already — the same operand decode, register survey
        // and def-use walk the near-null owner uses — and this site was not
        // taking it, so a pointer that became 0x1 arrived at the guest's signal
        // handler with nothing recorded about where the 1 came from.
        //
        // Delivering the signal is still correct: the guest installed the guard
        // and has a handler. Only the evidence was missing.
        reportProtectionFaultOperands(self, address, bytes, access);
        const instruction_len = currentGuestInstructionLength(self);
        const delivered = self.deliverGuestSignal(GUEST_SIGSEGV, self.regs.rip, instruction_len, address, access, bytes, instruction);
        // A fault inside the GPU register aperture is not a fault: it is how a
        // register write is delivered. Record it before deciding anything else,
        // because whether these arrive is the difference between "the title
        // never programmed the GPU" and "the title programmed it and Rosette
        // dropped the writes" — two opposite findings that otherwise both
        // present as an absence of log lines.
        observeRegisterApertureAccess(self, address, access, delivered);
        if (delivered) {
            machoCapturePrint(
                "macho-processor: mapped guest protection fault routed to SIGSEGV handler: rip=0x{x} address=0x{x} bytes={d} access={s} instruction={s}\n",
                .{ self.regs.rip, address, bytes, @tagName(access), instruction },
            );
            // This fault has a real consumer and is no longer the process's
            // active diagnostic transaction. Retaining its pinned thread here
            // would make a later fatal near-null walk the handled fault's tape.
            near_null_causality.clearFaultContext(self);
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
                self.metadata.symbolLabel(self.regs.rip),
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
    const instruction_snapshot = currentInstructionSnapshot(self);
    self.terminal_memory_failure = .{
        .instruction_address = self.regs.rip,
        .instruction = instruction,
        .decoded_instruction = instruction_snapshot.operation,
        .instruction_length = instruction_snapshot.length,
        .instruction_bytes = instruction_snapshot.bytes,
        .instruction_byte_count = instruction_snapshot.byte_count,
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
    self.dumpCoopBootstrapTrace();
    self.dumpMemInitTrace();
    self.dumpCoopHeartbeatTrace();
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
                e.step,                           e.rip,
                self.metadata.symbolLabel(e.rip), if (symbol) |s| s.offset else 0,
            },
        );
    }
}

pub fn currentGuestInstructionLength(self: anytype) u8 {
    if (self.execution_history.latestFor(self.active_guest_thread)) |latest| {
        if (latest.rip == self.regs.rip and latest.len != 0) return latest.len;
    }
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
                self.metadata.symbolLabel(access.instruction_address),
                if (reader) |symbol| symbol.offset else 0,
                access.instruction,
            },
        );
        if (self.memory_writes.lookup(access.address)) |writer| {
            const symbol = self.metadata.nearestSymbol(writer.instruction_address);
            machoCapturePrint(
                "macho-processor: near-null producer last writer: slot=0x{x} previous=0x{x} value=0x{x} kind={s} writer=0x{x} {s}+0x{x} step={d} age_steps={d} thread=0x{x}\n",
                .{
                    writer.address,
                    writer.previous_value,
                    writer.value,
                    @tagName(writer.kind),
                    writer.instruction_address,
                    self.metadata.symbolLabel(writer.instruction_address),
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
    const fault_thread = self.active_guest_thread;
    const count: usize = self.execution_history.countFor(fault_thread);
    var after = terminal_value;
    var same_thread_entries: usize = 0;
    const excluded_entries: usize = 0;
    var reverse_index = count;
    while (reverse_index != 0) {
        reverse_index -= 1;
        const entry = self.execution_history.chronological(fault_thread, reverse_index) orelse continue;
        same_thread_entries += 1;
        const before = traceRegisterValue(entry, register);
        if (before != after) {
            const symbol = self.metadata.nearestSymbol(entry.rip);
            machoCapturePrint(
                "macho-processor: near-null {s} register transition: thread=0x{x} register={s} before=0x{x} after=0x{x} caused_by=0x{x} {s}+0x{x} op={s} same_thread_distance={d} cross_thread_entries_excluded={d}\n",
                .{ role, fault_thread, @tagName(register), before, after, entry.rip, self.metadata.symbolLabel(entry.rip), if (symbol) |resolved| resolved.offset else 0, @tagName(entry.op), same_thread_entries, excluded_entries },
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

/// Delegates to the one owner of the RegId-to-snapshot-field mapping:
/// `TraceEntry` itself. Retained as a name because `process.zig` re-exports
/// it; the mapping no longer lives here.
pub fn traceRegisterValue(entry: TraceEntry, register: RegId) u64 {
    return entry.registerValue(register);
}

pub fn recordMemoryAccess(self: anytype, address: u64, size: Size, access: []const u8, value: u64) void {
    // P1-2 (perf audit): this runs on every guest load/store, and its
    // currentInstructionSnapshot() re-decodes the current instruction purely
    // for the ring buffer. The ring is only consumed post-fault.
    //
    // Gated behaviourally rather than by a flag, for the same reason the
    // instruction history is: the only consumer is the near-null causality
    // chain's exact-producer attribution, and it only ever asks about
    // generated code. Recording exactly there is ~2% of executed steps, so the
    // ring exists when it is needed instead of requiring the operator to have
    // predicted, before the run, that this fault would happen.
    //
    // The flag still forces it on everywhere, for host-code investigations.
    if (!self.memory_trace_enabled) {
        const generated = self.regs.rip < self.executable_min or self.regs.rip >= self.executable_max;
        if (!generated) return;
        // Budgeted: the snapshot below re-decodes the current instruction on
        // every access, which is the single most expensive observer here. A
        // bounded prefix keeps the path hot for the rest of the run, and the
        // exhaustion is reported so a later empty ring is not misread as "this
        // never happened".
        if (!self.memory_trace_budget.take()) return;
    }
    const bytes = bytesForSize(size);
    // recordMemoryAccess is invoked only after a read succeeded or after the
    // write path selected a valid sparse/linear mapping. Re-translating the
    // same address is useful only for full diagnostics; the lightweight
    // generated-code ring can accurately mark the completed access backed.
    const backed = if (self.memory_trace_enabled) blk: {
        const offset = translateGuest(self, address, bytes, if (std.mem.eql(u8, access, "write")) .write else .read);
        break :blk if (offset) |off| off + bytes <= self.mem.len else self.sparse_memory.containsMapped(address, bytes);
    } else true;
    const latest_trace = self.execution_history.latestFor(self.active_guest_thread);
    // Exact bytes are opt-in. In the default generated-code ring, execution
    // history already owns the decoded operation; re-decoding every memory
    // access merely to duplicate its bytes was the dominant observer cost.
    const instruction_snapshot = if (self.memory_trace_enabled and
        self.sparse_memory.isExecutable(self.regs.rip, 1))
        currentInstructionSnapshot(self)
    else
        InstructionSnapshot{};
    const instruction = if (instruction_snapshot.operation.len != 0)
        instruction_snapshot.operation
    else if (latest_trace) |entry|
        @tagName(entry.op)
    else
        "<runtime>";
    // Check for near-null or negative addresses (high bit set in 64-bit, or very small positive addresses)
    const near_null = (address & 0x8000_0000_0000_0000) != 0 or address < 0x1000;
    self.memory_trace_entries[self.memory_trace_index] = .{
        .provenance_present = true,
        .thread_handle = self.active_guest_thread,
        .scheduler_epoch = self.cooperative_thread_switches,
        .step = self.executed_steps,
        .instruction_address = self.regs.rip,
        .instruction = instruction,
        .instruction_length = instruction_snapshot.length,
        .instruction_bytes = instruction_snapshot.bytes,
        .instruction_byte_count = instruction_snapshot.byte_count,
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

/// Always-on endian-contract evidence recorder. The generated-endian contract
/// substantiates a repair from a MOVBE load plus a 32-bit register/memory
/// comparison. The diagnostic memory trace above is gated behind
/// ROSETTE_MACHO_MEMORY_TRACE (off by default), so in production runs the
/// contract would otherwise see an empty ring and reject every legitimate
/// repair as `movbe_evidence_missing`. This recorder runs at the execute site
/// where the instruction is already decoded, so it costs only a small ring
/// write (no re-decode), and is written unconditionally.
pub fn recordEndianEvidence(
    self: anytype,
    kind: generated_endian_contract.EvidenceKind,
    register: RegId,
    source_address: u64,
    size: Size,
    raw_value: u64,
) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "endian_evidence_entries")) return;
    // The contract is Xenia-specific; skip the ring write for non-Xenia guests
    // so the always-on recorder stays effectively free outside the compat path.
    if (comptime @hasField(State, "has_xenia_compat")) {
        if (!self.has_xenia_compat) return;
    }
    // Evidence can only authorize a generated-code repair. Keep native Mach-O
    // comparisons and MOVBE instructions out even if a future call site
    // forgets to apply its own hot-path gate.
    if (comptime @hasField(State, "executable_min") and @hasField(State, "executable_max")) {
        if (self.regs.rip >= self.executable_min and self.regs.rip < self.executable_max) return;
    }
    self.endian_evidence_entries[self.endian_evidence_index] = .{
        .kind = kind,
        .execution = .{
            .present = true,
            .thread_handle = self.active_guest_thread,
            .scheduler_epoch = self.cooperative_thread_switches,
            .step = self.executed_steps,
        },
        .instruction_address = self.regs.rip,
        .source_address = source_address,
        .width_bytes = bytesForSize(size),
        .register = @intCast(@intFromEnum(register)),
        .raw_value = raw_value,
    };
    self.endian_evidence_index = (self.endian_evidence_index + 1) % ENDIAN_EVIDENCE_BUFFER_LEN;
    if (self.endian_evidence_index == 0) self.endian_evidence_filled = true;
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

/// A 128-bit guest store is a *ranged* mutation and must answer to the same
/// contract as `write8`/`write16`/`write32` and the bulk import handlers.
///
/// It did not, and that was a hole nothing else could cover. `write64` observes
/// the exact slot it writes, the narrow scalar widths capture the qword they sit
/// inside, and `memset`/`memcpy` capture the range the caller asked for — but a
/// compiler-inlined zero fill emits `movaps`/`vmovdqu` stores directly and
/// reaches none of those. Sixteen bytes of a live C++ object could therefore be
/// replaced with no `observeWrite`, no write-time vptr restore, no provenance
/// entry and no atomic rollback of the ownership fields beside the vptr. The
/// damage surfaced only at the next virtual call, whose "last tracked writer"
/// was still the constructor — in the observed casualty, 1.8 billion steps
/// earlier — so the producer was unnameable by construction rather than by bad
/// luck.
///
/// Cost is the same shape the narrow scalar writes already pay: for a sixteen
/// byte range `captureMutation` is two page-filter bit tests before it looks at
/// anything, and `commitMemoryMutation` walks zero slots when they miss.
pub fn writeMem128(self: anytype, addr: u64, value: [16]u8) void {
    if (self.sparse_memory.bytes(addr, 16, true)) |storage| {
        const mutation = captureMemoryMutation(self, addr, 16);
        noteGuestWrite(self, addr, 16);
        @memcpy(storage[0..16], value[0..]);
        commitMemoryMutation(self, mutation, .vector_store);
        return;
    }
    const off = translateGuest(self, addr, 16, .write) orelse {
        terminateForGuestAccess(self, addr, 16, .write, "vector_write");
        return;
    };
    const mutation = captureMemoryMutation(self, addr, 16);
    self.initializer_memory.capture(self.mem, @intCast(off), 16);
    noteGuestWrite(self, addr, 16);
    @memcpy(self.mem[off..][0..16], value[0..]);
    commitMemoryMutation(self, mutation, .vector_store);
}

pub fn guestMemory(self: anytype, addr: u64, count: u64) ?[]u8 {
    if (self.sparse_memory.bytes(addr, count, true)) |bytes| {
        noteGuestWrite(self, addr, count);
        return bytes;
    }
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
    if (count == 0) return;
    const end = address +| count;
    const touches_image_code =
        self.executable_min != std.math.maxInt(u64) and
        address < self.executable_max and end > self.executable_min;
    // Short-circuit rather than computing both. The sparse probe is the
    // expensive half, and a write that already touches image code has its
    // answer; `and`/`or` in Zig are short-circuiting but two `const` bindings
    // are not, so this was paying for the probe on every store that hit the
    // cheap case.
    if (!touches_image_code and !self.sparse_memory.isExecutable(address, count)) return;

    // Xenia emits and patches translated x64 in a sparse RWX code cache
    // (normally 0xA0000000..0xAFFFFFFF). Invalidate only cached instructions
    // whose bytes overlap the write. A global generation flush on every JIT
    // byte store is correct but makes concurrent compilation prohibitively
    // expensive.
    const maximum_instruction_length: u64 = 15;
    const first_candidate = address -| (maximum_instruction_length - 1);
    const last_candidate = end - 1;
    const candidate_count = last_candidate - first_candidate + 1;
    if (candidate_count >= @as(u64, @intCast(self.decode_cache.len))) {
        // F3: the *only* place the generation moves. A wholesale flush cannot
        // name which entries it invalidated, so every surviving entry has to
        // re-prove itself by byte comparison — which is exactly what a
        // generation mismatch asks for.
        self.code_generation +%= 1;
        if (self.code_generation == 0) self.code_generation = 1;
        @memset(self.decode_cache, .{});
        self.decode_cache_pages.reset();
        return;
    }
    // F4: a code-cache page is written far more often than it is executed
    // from. One bit test rejects the 15-candidate walk below for every write
    // to a page that has never had a decode cached in it — which is most of
    // what the JIT emitter does. The bit is set in `decodeWithLiveOperands`
    // when an entry is populated, so a set bit means "an entry may exist
    // here", never the reverse.
    if (!self.decode_cache_pages.anyCoveringRange(first_candidate, last_candidate)) return;

    // Any x86 instruction overlapping this write must begin between
    // address-14 and end-1. Probe exact candidate starts with the same hash as
    // decodeWithLiveOperands; this preserves precise invalidation without reverting to a
    // global cache flush for each small Xenia JIT patch.
    //
    // F3: this walk is precise — it clears exactly the entries whose bytes the
    // write touched — so the global `code_generation` bump that used to
    // accompany it was pure redundancy with a large cost. It invalidated the
    // fast path of every *unrelated* entry in the program, and Xbyak emits one
    // byte at a time, so during code generation essentially every instruction
    // fetch fell through to the byte-comparison path. The bump now happens
    // only where precision is actually lost (the flush above).
    var candidate = first_candidate;
    while (candidate <= last_candidate) : (candidate += 1) {
        // Every way of the set, not one slot: the cache is set-associative, and
        // an invalidation that clears only one way leaves a stale decode
        // reachable in the other. That is the failure this loop exists to
        // prevent, so it has to enumerate exactly what the lookup enumerates.
        const set_base = constants.decodeCacheSetBase(candidate);
        for (self.decode_cache[set_base..][0..constants.DECODE_CACHE_WAYS]) |*entry| {
            if (entry.rip == std.math.maxInt(u64)) continue;
            const instruction_length = @max(@as(u64, entry.decoded.len), 1);
            const instruction_end = entry.rip +| instruction_length;
            if (entry.rip < end and instruction_end > address) {
                entry.* = .{};
            }
        }
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
    const address = self.memory_forwarder.allocate(self, size, alignment) orelse return null;
    // A released heap-backed mmap may have left page permissions read-only or
    // inaccessible. Allocation is a new lifetime and must re-establish the
    // ordinary malloc contract before the caller initializes the object.
    self.setPagePermissions(address, @max(size, 1), PAGE_READ | PAGE_WRITE);
    return address;
}

pub fn guestHeapRelease(self: anytype, address: u64) void {
    self.memory_forwarder.releaseFrom(address, self.regs.rip);
    self.vtable_tracker.forgetAddress(address);
}

pub fn guestHeapContains(self: anytype, address: u64) bool {
    return self.memory_forwarder.allocationSize(address) != null;
}

pub fn forgetMemoryWriteProvenance(self: anytype, address: u64, length: u64) void {
    self.memory_writes.forgetRange(self.allocator, address, length);
    // Allocation start/reuse is a hard lifecycle boundary.  Retire any
    // trusted vptr belonging to the former occupant before the new
    // allocation becomes visible.
    self.vtable_tracker.forgetAddress(address);
}

/// Describe a fault-time address in terms of the live register file.
///
/// The def-use scan resolves a source address like `0x40e0000130`, which is
/// opaque on its own. Expressing it as `rsi+0x130` identifies it as a field of
/// whatever structure that register points at — a guest context, a heap object,
/// a stack frame — without knowing any layout, and it is the difference between
/// "a load returned zero" and "the field at context+0x130 is zero".
///
/// Purely behavioural: it reports which live registers the address is near,
/// with no table of expected structures.
fn describeAddressAgainstRegisters(self: anytype, address: u64, out: []u8) []const u8 {
    const Candidate = struct { name: []const u8, value: u64 };
    const candidates = [_]Candidate{
        .{ .name = "rax", .value = self.regs.rax },
        .{ .name = "rbx", .value = self.regs.rbx },
        .{ .name = "rcx", .value = self.regs.rcx },
        .{ .name = "rdx", .value = self.regs.rdx },
        .{ .name = "rsi", .value = self.regs.rsi },
        .{ .name = "rdi", .value = self.regs.rdi },
        .{ .name = "rbp", .value = self.regs.rbp },
        .{ .name = "rsp", .value = self.regs.rsp },
        .{ .name = "r8", .value = self.regs.r8 },
        .{ .name = "r13", .value = self.regs.r13 },
        .{ .name = "r14", .value = self.regs.r14 },
        .{ .name = "r15", .value = self.regs.r15 },
    };
    // A structure field is a small positive displacement from a base pointer.
    // Anything larger is a coincidence, not a relationship.
    const field_window: u64 = 0x1000;
    var written: usize = 0;
    for (candidates) |candidate| {
        if (candidate.value == 0 or address < candidate.value) continue;
        const delta = address - candidate.value;
        if (delta > field_window) continue;
        const chunk = std.fmt.bufPrint(
            out[written..],
            "{s}{s}+0x{x}",
            .{ if (written == 0) "" else ", ", candidate.name, delta },
        ) catch break;
        written += chunk.len;
    }
    if (written == 0) return "<no live register within 0x1000 below this address>";
    return out[0..written];
}

/// Record a guest mapping with the address-space model. Only mappings large
/// enough to be a guest RAM reservation may define the window; the model
/// enforces that, and retains everything else for containment reporting.
fn noteGuestMapping(self: anytype, address: u64, length: u64, prot: u32) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_address_space")) return;
    self.guest_address_space.observe(.{
        .base = address,
        .size = length,
        .executable = prot & 4 != 0,
        .writable = prot & 2 != 0,
    });
}

/// A guest range whose backing Rosette has just thrown away.
///
/// Four observers key on the guest address and outlive the bytes behind it:
/// write provenance, the vtable tracker, the decoded-instruction cache, and —
/// through the lifetime registry — anything that later asks whether an absence
/// of provenance means the guest never wrote. Retiring them here is what keeps
/// "nobody stored to this field" a statement about the guest instead of a
/// statement about Rosette's memory management.
///
/// Deliberately one function: the previous arrangement had the sparse manager
/// own placement, `guestMapFile` own registration, and nobody own invalidation,
/// so each new observer inherited the gap by default.
pub fn noteGuestRangeDiscarded(
    self: anytype,
    address: u64,
    length: u64,
    reason: ownership.lifetime.Reason,
) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_lifetime")) return;
    if (length == 0) return;
    self.guest_lifetime.note(address, length, reason, self.executed_steps);
    // Provenance and vtable identity describe bytes that no longer exist.
    forgetMemoryWriteProvenance(self, address, length);
    // Executable bytes at these addresses are new bytes. `noteGuestWrite`
    // returns immediately for non-executable ranges, so this costs nothing on
    // the ordinary data mapping.
    noteGuestWrite(self, address, length);
    if (recovery_ledger.throttled(self.guest_lifetime.events)) {
        machoCapturePrint(
            "macho-processor: guest range backing discarded #{d}: base=0x{x} length={d} reason={s} generation={d} step={d}; write provenance, vtable identity and decoded bytes for this range are retired. Any later \"nothing was ever stored here\" about this range is a statement about Rosette's memory management, not about the guest\n",
            .{
                self.guest_lifetime.events,
                address,
                length,
                @tagName(reason),
                if (self.guest_lifetime.covers(address)) |record| record.generation else 1,
                self.executed_steps,
            },
        );
    }
}

/// True when `address` lies in a range whose backing Rosette discarded, so an
/// absence of recorded writes there is not evidence about the guest.
pub fn guestRangeDiscarded(self: anytype, address: u64) ?ownership.lifetime.Record {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_lifetime")) return null;
    return self.guest_lifetime.lookup(address);
}

pub fn guestMapFile(self: anytype, address: u64, length: u64, prot: u32, flags: u32, host_fd: std.posix.fd_t, offset: u64) bool {
    const map_fixed: u32 = 0x0010;
    const fixed = flags & map_fixed != 0;
    // Asked *before* the map, because afterwards the previous mapping is gone
    // and there is nothing left to detect. MAP_FIXED over an exact match is
    // ordinary POSIX and the manager is right to honour it; what was missing is
    // that the discard was invisible to everyone keyed by guest address.
    const replaces = fixed and self.sparse_memory.replacesExisting(address, length);
    const mapped = if (fixed)
        self.sparse_memory.mapFixed(address, length, prot, flags, host_fd, offset)
    else
        self.sparse_memory.mapFile(address, length, prot, flags, host_fd, offset);
    if (!mapped) return false;
    if (replaces) noteGuestRangeDiscarded(self, address, length, .fixed_map_replaced);
    // Feed the guest address-space model. This is the observation that lets the
    // window be derived instead of asserted; without it every classification
    // would silently run on the bootstrap default forever.
    noteGuestMapping(self, address, length, prot);
    _ = self.memory_regions.register(address, length, .{
        .read = prot & 1 != 0,
        .write = prot & 2 != 0,
        .execute = prot & 4 != 0,
    }, .guest_mmap, "sparse 64K guest mmap", self.regs.rip);
    _ = self.pointer_firewall.register(address, length, .{ .kind = .guest_backed, .may_dereference = true, .may_execute = prot & 4 != 0, .owner = "sparse 64K guest mmap" });
    return true;
}

/// Place a non-MAP_FIXED mapping at the address the guest hinted, when that
/// range is free.
///
/// POSIX: a non-null `addr` without MAP_FIXED is a *hint*. The kernel honours it
/// when the range is available and picks its own address otherwise, and it
/// never replaces an existing mapping. Rosette discarded every hint that was
/// not the x64 code-cache window and always answered from the guest heap, which
/// is indistinguishable to the guest from the hint never being available — so a
/// guest that finds a free slot by asking for one and checking what it got can
/// never find one. That is not hypothetical: it is how a process allocates
/// per-thread state at a fixed low-32-bit pattern, and answering every probe
/// with "somewhere else" makes the scan run to exhaustion.
///
/// Returns the guest base when the mapping was placed at the hint, or null when
/// the caller should fall through to ordinary placement. Never replaces
/// anything — that is the entire difference between a hint and MAP_FIXED.
pub fn guestMapHinted(
    self: anytype,
    address: u64,
    length: u64,
    prot: u32,
    flags: u32,
    host_fd: std.posix.fd_t,
    offset: u64,
) ?u64 {
    if (address == 0 or length == 0) return null;
    if (address % std.heap.page_size_min != 0) return null;
    const effective_length = sparse_virtual_memory.pageRoundedLength(length) orelse return null;
    if (!self.sparse_memory.rangeIsFree(address, effective_length)) return null;
    if (!self.sparse_memory.mapFixed(address, length, prot, flags, host_fd, offset)) return null;
    noteGuestMapping(self, address, effective_length, prot);
    _ = self.memory_regions.register(address, effective_length, .{
        .read = prot & 1 != 0,
        .write = prot & 2 != 0,
        .execute = prot & 4 != 0,
    }, .guest_mmap, "hinted sparse guest mmap", self.regs.rip);
    _ = self.pointer_firewall.register(address, effective_length, .{
        .kind = .guest_backed,
        .may_dereference = true,
        .may_execute = prot & 4 != 0,
        .owner = "hinted sparse guest mmap",
    });
    return address;
}

pub fn guestMapAnywhereWithBacking(self: anytype, length: u64, prot: u32, flags: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
    const address = self.sparse_memory.mapAnywhereWithBacking(length, prot, flags, host_fd, offset) orelse return null;
    const effective_length = sparse_virtual_memory.pageRoundedLength(length) orelse return null;
    noteGuestMapping(self, address, effective_length, prot);
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
    // This route places the two mappings that actually define the guest layout
    // — the 32-bit-reachable guest RAM window and the JIT code cache — and was
    // the only mapping path that never told the address-space model. With it
    // silent, every observation the model did receive was a host-side view
    // above 4 GB, all of which it correctly ignores, so it spent whole runs on
    // its bootstrap default while reporting `observed_regions=17
    // ignored_observations=17`. The model distinguishes the two by the
    // `executable` flag; only guest RAM may define the window.
    noteGuestMapping(self, address, effective_length, prot);
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
    // A later mapping at the same guest address is a different lifetime that
    // happens to share a name. Retire the address-keyed records now, while the
    // boundary is still observable.
    noteGuestRangeDiscarded(self, address, effective_length, .unmapped);
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
    const effective_length = sparse_virtual_memory.guestProtectionRoundedLength(address, length) orelse return false;
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
    // Publishing pages as executable is a code-cache boundary even when the
    // bytes were written while the mapping was non-executable. Invalidate the
    // affected decoded range before any generated code may enter it.
    if (prot & 4 != 0) noteGuestWrite(self, address, effective_length);
    return true;
}

/// Applies mprotect semantics to the processor's primary contiguous mapping.
/// The previous import bridge merely checked whether memory was accessible and
/// returned success, leaving the page permission table unchanged. That made a
/// successful mprotect lie to the translated process.
pub fn guestProtectMappedMemory(self: anytype, address: u64, length: u64, prot: u32) bool {
    if (length == 0) return false;
    const offset = mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) orelse return false;
    const end = std.math.add(u64, offset, length) catch return false;
    if (end > self.mem.len) return false;
    self.setPagePermissions(address, length, @truncate(prot & 0x07));
    _ = self.memory_regions.register(address, length, .{
        .read = prot & 1 != 0,
        .write = prot & 2 != 0,
        .execute = prot & 4 != 0,
    }, .guest_mmap, "primary guest mprotect", self.regs.rip);
    _ = self.pointer_firewall.register(address, length, .{
        .kind = .guest_backed,
        .may_dereference = prot != 0,
        .may_execute = prot & 4 != 0,
        .owner = "primary guest mprotect",
    });
    if (prot & 4 != 0) noteGuestWrite(self, address, length);
    return true;
}

pub fn renderProcSelfMaps(self: anytype, output: []u8) []const u8 {
    return self.sparse_memory.renderProcSelfMaps(output);
}

pub fn guestCString(self: anytype, addr: u64, max_len: usize) ?[]const u8 {
    if (addr == 0 or max_len == 0) return null;
    // Sparse-backed strings (guest mmap of files, XISO/XEX image mappings,
    // JIT data pages, native-bridged memory) live outside the primary image
    // and are invisible to translateGuest. Every other guest accessor
    // (guestMemory / guestMemoryConst) consults sparse memory first; C-string
    // reads must too, otherwise strlen/strcmp/path-style imports against
    // sparse-backed strings fall through to "unresolved import" (rax=0) even
    // though the bytes are present and readable.
    if (self.sparse_memory.bytesConst(addr, 1) != null) {
        // Grow geometrically until the terminator, max_len, or the readable
        // span end is reached.
        var probe: usize = @min(max_len, 256);
        while (probe <= max_len) {
            const bytes = self.sparse_memory.bytesConst(addr, probe) orelse break;
            if (std.mem.indexOfScalar(u8, bytes, 0)) |end| return bytes[0..end];
            if (probe == max_len) return null;
            probe = @min(max_len, probe + (probe >> 1));
        }
        // The probe outgrew the readable span. Bisect to the exact span
        // length so a string that ends at a sparse-mapping boundary is still
        // resolved rather than rejected as "no terminator found".
        var low: usize = 1;
        var high: usize = probe;
        while (low + 1 < high) {
            const mid = low + (high - low) / 2;
            if (self.sparse_memory.bytesConst(addr, mid) != null) {
                low = mid;
            } else {
                high = mid;
            }
        }
        if (self.sparse_memory.bytesConst(addr, low)) |bytes| {
            if (std.mem.indexOfScalar(u8, bytes, 0)) |end| return bytes[0..end];
        }
        return null;
    }
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

const SparseCStringTestState = struct {
    sparse_memory: sparse_virtual_memory.Manager,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    mapped_min: u64,
    pointer_firewall: pointer_firewall.Firewall,
    page_permissions: []u8,
};

fn sparseCStringTestState(allocator: std.mem.Allocator) !struct {
    state: SparseCStringTestState,
    manager: sparse_virtual_memory.Manager,
    firewall: pointer_firewall.Firewall,
} {
    var manager = sparse_virtual_memory.Manager.init(allocator);
    errdefer manager.deinit();
    var firewall = pointer_firewall.Firewall.init(allocator);
    errdefer firewall.deinit();
    const image = try allocator.alloc(u8, 4096);
    errdefer allocator.free(image);
    @memset(image, 0);
    const perms = try allocator.alloc(u8, 1);
    errdefer allocator.free(perms);
    perms[0] = 0; // primary image intentionally unreadable: only sparse backing is readable

    const base: u64 = 0x8000_0000;
    const darwin_map_private_anonymous_fixed: u32 = 0x0002 | 0x1000 | 0x0010;
    if (!manager.mapFile(base, sparse_virtual_memory.PAGE_64K, 3, darwin_map_private_anonymous_fixed, -1, 0)) {
        return error.TestUnexpectedResult;
    }
    return .{
        .state = .{
            .sparse_memory = manager,
            .mem = image,
            .mem_base = 0,
            .mem_size = 4096,
            .mapped_min = 0x1000,
            .pointer_firewall = firewall,
            .page_permissions = perms,
        },
        .manager = manager,
        .firewall = firewall,
    };
}

test "guestCString reads sparse-backed strings outside the primary image" {
    // `manager.bytes` needs mutable storage; a const binding here is why this
    // test stopped compiling the moment the module gained a test target.
    var setup = try sparseCStringTestState(std.testing.allocator);
    defer setup.state.sparse_memory.deinit();
    defer setup.firewall.deinit();
    defer std.testing.allocator.free(setup.state.mem);
    defer std.testing.allocator.free(setup.state.page_permissions);
    const state = &setup.state;

    const base: u64 = 0x8000_0000;
    const bytes = setup.state.sparse_memory.bytes(base, 16, true) orelse return error.TestUnexpectedResult;
    @memcpy(bytes[0..11], "hello world");
    bytes[11] = 0;

    // A string inside a sparse mapping (guest mmap of a file, XISO/XEX image,
    // JIT data) resolves even though the primary-image translation cannot see
    // it; before the sparse path existed this read failed and the caller
    // reported an unresolved import returning 0.
    const string = guestCString(state, base, 1 << 20) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("hello world", string);

    // Zero pointers stay rejected regardless of backing.
    try std.testing.expect(guestCString(state, 0, 1 << 20) == null);

    // Addresses in neither the sparse mappings nor the primary image reject.
    try std.testing.expect(guestCString(state, 0xDEAD_BEEF, 1 << 20) == null);
}

test "guestCString resolves a sparse string that ends at the mapping boundary" {
    // `manager.bytes` needs mutable storage; a const binding here is why this
    // test stopped compiling the moment the module gained a test target.
    var setup = try sparseCStringTestState(std.testing.allocator);
    defer setup.state.sparse_memory.deinit();
    defer setup.firewall.deinit();
    defer std.testing.allocator.free(setup.state.mem);
    defer std.testing.allocator.free(setup.state.page_permissions);
    const state = &setup.state;

    const base: u64 = 0x8000_0000;
    // 500-byte string whose terminator is the final byte of the 64 KiB
    // mapping. The geometric probe overshoots the mapping and the bisect must
    // recover the exact readable span to find the terminator.
    const tail = base + sparse_virtual_memory.PAGE_64K - 500;
    const tail_bytes = setup.state.sparse_memory.bytes(tail, 500, true) orelse return error.TestUnexpectedResult;
    for (0..499) |index| tail_bytes[index] = 'a';
    tail_bytes[499] = 0;

    const long = guestCString(state, tail, 1 << 20) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 499), long.len);
    try std.testing.expectEqual(@as(u8, 'a'), long[0]);
    try std.testing.expectEqual(@as(u8, 'a'), long[498]);

    // A non-terminated read that outgrows max_len rejects like the primary
    // image path does.
    const untruncated = setup.state.sparse_memory.bytes(tail, 500, true) orelse return error.TestUnexpectedResult;
    untruncated[0] = 'b';
    try std.testing.expect(guestCString(state, tail, 32) == null);
}

// The memo must answer exactly as the search does, including for the sections
// that live inside r-x __TEXT and are not code. A cache that returned "still
// executable" for an address just past __text would turn an exception table
// into an instruction stream.
test "the executable-section memo agrees with the search at range edges" {
    const Section = struct { name: []const u8, address: u64, size: u64, flags: u32 };
    const Meta = struct {
        sections: []const Section,
        fn sectionAtAddress(self: *const @This(), address: u64) ?Section {
            for (self.sections) |section| {
                if (address >= section.address and address < section.address + section.size) return section;
            }
            return null;
        }
    };
    const Host = struct {
        metadata: Meta,
        executable_section_low: u64 = 1,
        executable_section_high: u64 = 0,
        executable_section_verdict: bool = false,
    };

    var host = Host{ .metadata = .{ .sections = &.{
        .{ .name = "__text", .address = 0x1000, .size = 0x1000, .flags = 0 },
        .{ .name = "__gcc_except_tab", .address = 0x2000, .size = 0x1000, .flags = 0 },
    } } };

    // Warm on __text, then walk off its end into the exception table.
    try std.testing.expect(cachedSectionExecutable(&host, 0x1000));
    try std.testing.expect(cachedSectionExecutable(&host, 0x1FFF));
    try std.testing.expect(!cachedSectionExecutable(&host, 0x2000));
    // Coming back re-warms rather than keeping the stale verdict.
    try std.testing.expect(cachedSectionExecutable(&host, 0x1800));
    try std.testing.expect(!cachedSectionExecutable(&host, 0x2800));
    // An address in no section is not executable and leaves no range behind.
    try std.testing.expect(!cachedSectionExecutable(&host, 0x9000));
    try std.testing.expect(cachedSectionExecutable(&host, 0x1234));
}

test "an unwarmed memo matches nothing" {
    const Section = struct { name: []const u8, address: u64, size: u64, flags: u32 };
    const Meta = struct {
        fn sectionAtAddress(_: *const @This(), _: u64) ?Section {
            return null;
        }
    };
    const Host = struct {
        metadata: Meta = .{},
        executable_section_low: u64 = 1,
        executable_section_high: u64 = 0,
        executable_section_verdict: bool = true,
    };
    var host = Host{};
    // The sentinel range must not swallow address 0, or a null RIP would read
    // as executable before anything has been looked up.
    try std.testing.expect(!cachedSectionExecutable(&host, 0));
    try std.testing.expect(!cachedSectionExecutable(&host, 1));
}

// The verdict is the sentence a reader acts on. Getting it backwards sends the
// investigation at the allocator when the writer's pointer was stale, or at the
// writer when the runtime handed out memory that was still in use.
test "a vtable clobber verdict separates a bad writer pointer from allocator overlap" {
    const a: u64 = 0x1000;
    const b: u64 = 0x2000;

    // Writer inside its own block, and that block also holds the live object:
    // the allocator handed out occupied memory.
    try std.testing.expect(std.mem.startsWith(
        u8,
        clobberVerdict(true, a, a),
        "ALLOCATOR OVERLAP",
    ));

    // Writer's base in one block, write landed in another: it walked out.
    try std.testing.expect(std.mem.startsWith(
        u8,
        clobberVerdict(true, a, b),
        "WRITER ESCAPED ITS BLOCK",
    ));

    // Base register points at nothing tracked: the pointer itself is the bug.
    try std.testing.expect(std.mem.startsWith(
        u8,
        clobberVerdict(true, null, a),
        "WRITER POINTER IS NOT A LIVE ALLOCATION",
    ));

    // These two are findings, not accusations, and must not claim either bug.
    const past_end = clobberVerdict(true, a, null);
    try std.testing.expect(std.mem.indexOf(u8, past_end, "past the end") != null);
    try std.testing.expect(std.mem.indexOf(u8, past_end, "ALLOCATOR OVERLAP") == null);

    const neither = clobberVerdict(true, null, null);
    try std.testing.expect(std.mem.indexOf(u8, neither, "outside the forwarded arena") != null);
    try std.testing.expect(std.mem.indexOf(u8, neither, "WRITER ESCAPED") == null);

    // No base register: the address came from a displacement or index, so
    // neither conclusion is available and the report must not invent one.
    const no_base = clobberVerdict(false, a, a);
    try std.testing.expect(std.mem.indexOf(u8, no_base, "no base register") != null);
    try std.testing.expect(std.mem.indexOf(u8, no_base, "ALLOCATOR OVERLAP") == null);
}
