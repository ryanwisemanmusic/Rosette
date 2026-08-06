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
const opaque_lifetime_recovery = @import("diagnostics").opaque_lifetime_recovery;
const guest_assertion_recovery = @import("guest_abi").guest_assertion_recovery;
const vt = @import("vtable");
const guest_log = @import("guest_log.zig");
const generated_endian_contract = @import("generated_endian_contract.zig");
const near_null_causality = @import("near_null_causality.zig");
const recovery_ledger = @import("recovery_ledger.zig");
const bounded_dispatch_fst = @import("bounded_dispatch_fst.zig");
const generated_block = @import("execution_history").generated_block;
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
        const section = self.metadata.sectionAtAddress(address) orelse return false;
        return isExecutableMachOSection(section);
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
        const mutation = captureMemoryMutation(self, vaddr, 4);
        noteGuestWrite(self, vaddr, 4);
        std.mem.writeInt(u32, bytes[0..4], val, .little);
        commitMemoryMutation(self, mutation, .partial_scalar);
        return;
    }
    const off = translateGuest(self, vaddr, 4, .write) orelse return;
    if (off + 4 <= self.mem.len) {
        const mutation = captureMemoryMutation(self, vaddr, 4);
        self.initializer_memory.capture(self.mem, @intCast(off), 4);
        noteGuestWrite(self, vaddr, 4);
        std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
        commitMemoryMutation(self, mutation, .partial_scalar);
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
        if (self.write_diagnostics_armed) {
            const prev = std.mem.readInt(u64, bytes[0..8], .little);
            self.memory_writes.record(self.allocator, vaddr, prev, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
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
        if (self.write_diagnostics_armed) {
            const prev = std.mem.readInt(u64, self.mem[off..][0..8], .little);
            self.memory_writes.record(self.allocator, vaddr, prev, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
        }
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

fn decodedInstructionAt(self: anytype, rip: u64) ?DecodedInsn {
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

/// Decide the single owner of a generated-code scalar load fault. Pure with
/// respect to guest state: it reads registers and decodes the faulting
/// instruction but mutates nothing, so the answer cannot be perturbed by the
/// repair it selects.
pub fn classifyGeneratedScalarFault(
    self: anytype,
    fault_address: u64,
    bytes: u8,
) GeneratedFaultClassification {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "has_xenia_compat")) return .{};
    if (!self.has_xenia_compat) return .{};
    if (!self.sparse_memory.isExecutable(self.regs.rip, 1)) return .{};

    const fault = decodedInstructionAt(self, self.regs.rip) orelse return .{};
    if (!isBaseOnlyZeroDisplacementForm(fault)) return .{};
    // The 0x67 address-size override makes the address 32-bit; read the base at
    // that width. A zero EBX with garbage in the upper half of RBX is still an
    // exactly-zero 32-bit address and must qualify.
    const address_size: Size = if (fault.has_0x67) .bits32 else .bits64;
    const base_value = self.regVal(fault.sib_base_reg, address_size);
    const common: GeneratedFaultClassification = .{
        .fault = fault,
        .base_value = base_value,
        .address_size = address_size,
    };

    if (base_value == 0 and fault_address == 0) {
        if (comptime !@hasField(State, "generated_null_scalar_read") or
            !@hasField(State, "last_generated_null_read_rip"))
        {
            return .{};
        }
        // One definition of the eligible address form, shared with the unit
        // tests that pin it. Re-stating the bits here is how the owners drifted
        // apart the first time.
        if (!isGeneratedNullScalarAddressForm(fault)) return .{};
        if (bytes != 1 and bytes != 2 and bytes != 4) return .{};
        var owned = common;
        // Xenia's indirection-table load is not a generic nullable scalar: it
        // is a control-transfer decision, and satisfying it as a zero-filled
        // read would feed a null function pointer to the following `jmp rax`.
        owned.owner = if (isBoundedDispatchIndirectionForm(fault))
            .null_base_dispatch
        else
            .null_base_scalar;
        return owned;
    }

    if (comptime !@hasField(State, "generated_endian_contract")) return .{};
    if (bytes != 4 or base_value == 0 or fault_address == 0) return .{};
    if (fault.op != .mov_reg32_mem32 or !fault.has_0x67) return .{};
    if (base_value != fault_address) return .{};
    var owned = common;
    owned.owner = .endian_swapped_base;
    return owned;
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
                if (isGuestModuleAddress(self.regs.rcx)) " rcx=guest" else "",
                if (isGuestModuleAddress(self.regs.r8)) " r8=guest" else "",
                if (isGuestModuleAddress(self.regs.r15)) " r15=guest" else "",
            },
        );
        // RCX is intentionally diagnostic-only here. Xenia does not load the
        // authoritative guest return until after the indirection-table load;
        // the bounded witness above uses the fixed [rsp+0x58] slot instead.
        if (isGuestModuleAddress(self.regs.rcx) and fault.sib_base_reg == .bl_bx_ebx_rbx) {
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

/// Detect Xenia's dead function-exit epilogue emitted after a tail-call
/// dispatch: `add rsp, imm8/32; [dec mem]; ret` — the CALL_POSSIBLE_RETURN
/// path in X64Emitter::CallIndirect, reachable only via `je epilogue`. A null
/// tail dispatch recovery must NEVER fall through into it: the frame teardown
/// has already run before the dispatch, so executing it again double-
/// deallocates the frame and the `ret` pops a local (the guest return
/// address). Pure byte check so it is unit-testable without a state.
pub fn isFunctionExitEpilogueBytes(bytes: []const u8) bool {
    if (bytes.len < 4) return false;
    var off: usize = 0;
    if (bytes[0] == 0x48 and bytes[1] == 0x83 and bytes[2] == 0xC4) {
        off = 4; // add rsp, imm8
    } else if (bytes[0] == 0x48 and bytes[1] == 0x81 and bytes[2] == 0xC4) {
        off = 8; // add rsp, imm32
    } else {
        return false;
    }
    if (bytes.len <= off) return false;
    // Optional profiler decrement before the ret: dec dword [rsi-0x14]
    // (FF 4E EC) or its REX.W form (48 FF 4E EC). Length guards are checked
    // BEFORE the byte reads so a truncated mapping slice cannot index OOB.
    var i = off;
    while (i + 3 <= bytes.len) {
        if (i + 4 <= bytes.len and bytes[i] == 0x48 and bytes[i + 1] == 0xFF and bytes[i + 2] == 0x4E) {
            i += 4;
            continue;
        }
        if (bytes[i] == 0xFF and bytes[i + 1] == 0x4E) {
            i += 3;
            continue;
        }
        break;
    }
    return i < bytes.len and bytes[i] == 0xC3;
}

const BoundedTailShape = struct {
    transfer_rip: u64 = 0,
    transfer_len: u8 = 0,
    transfer_distance: u8 = 0,
    jmp_rax: bool = false,
    dead_epilogue: bool = false,
    /// A `mov r64,[rsp+disp]` was seen between the indirection load and the
    /// tail transfer: Xenia reloading the guest return address for the callee.
    /// Independent confirmation of the guest-return stack displacement.
    return_slot_reload_seen: bool = false,
    return_slot_reload_offset: u64 = 0,
};

/// Walk forward from the null-base load through at most 16 instructions / 64
/// bytes. This is the bounded "tape" of the dispatch transducer. No allocation,
/// unbounded search, or speculative target execution is permitted.
fn boundedTailShape(self: anytype, load_rip: u64, load_len: u8) BoundedTailShape {
    var cursor = load_rip +| load_len;
    var instruction_count: u8 = 0;
    var return_slot_seen = false;
    var return_slot_offset: u64 = 0;
    while (instruction_count < 16 and cursor > load_rip and cursor - load_rip <= 64) : (instruction_count += 1) {
        const decoded = decodedInstructionAt(self, cursor) orelse return .{};
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
            const decoded = decodedInstructionAt(ctx.state, address) orelse return null;
            return .{
                .len = decoded.len,
                .defines_register = definesRegister(decoded, ctx.register),
            };
        }
    };
    const located = generated_block.findDefinition(
        Ctx,
        .{ .state = self, .register = reg },
        anchor_rip,
        .{},
        Ctx.decode,
    );

    var result = BoundedDefinition{
        .origin = located.origin,
        .block_start = located.block_start,
        .block_length = located.block_length,
        .instruction_address = located.instruction_address,
        .distance = located.distance,
    };
    if (located.origin != .defined_in_block) return result;

    const decoded = decodedInstructionAt(self, located.instruction_address) orelse return result;
    result.found = true;
    result.op = decoded.op;
    result.from_memory = loadsFromMemory(decoded.op);
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

    var start = load_rip -| 32;
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
                witness.stack_value_valid = isGuestModuleAddress(witness.stack_value);
                witness.guest_return = witness.stack_value;
                witness.guest_return_valid = witness.stack_value_valid;
            }
        }

        const target_value = self.regVal(compare.dst_reg, .bits32);
        witness.target = .{
            .value = target_value,
            .register_name = @tagName(compare.dst_reg),
            .valid = isGuestModuleAddress(target_value),
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

/// Return true only when the observed conditional branch lands at the first
/// byte after the observed `jmp rax`. This keeps the branch proof finite and
/// ties it to the same dead epilogue identified by boundedTailShape.
pub fn branchTargetsDeadDispatchEpilogue(branch_target: u64, transfer_rip: u64, transfer_len: u8) bool {
    return branch_target != 0 and transfer_rip != 0 and transfer_len != 0 and
        branch_target == transfer_rip +| transfer_len;
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
    // whichever source supplied the value. Retained history is preferred only
    // because it is an observation of the register rather than a
    // reconstruction of where it should have come from.
    const evidence: struct { value: u64, source: bounded_dispatch_fst.Machine.ClearedTargetSource } =
        if (cleared) |recovered|
            .{ .value = recovered.value, .source = .retained_history }
        else if (definition.found and definition.from_memory and definition.source_readable)
            .{ .value = @as(u32, @truncate(definition.source_value)), .source = .definition_reread }
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
    if (!output.redirects()) {
        if (should_log) {
            machoCapturePrint(
                "macho-processor: bounded dispatch FST rejected 0x67 null-base load: thread=0x{x} load_rip=0x{x} state={s} reason={s} candidate={s}:0x{x} candidate_aliases_null_base={} guest_return=0x{x} rcx=0x{x} stack_slot=0x{x} stack_value=0x{x} compare_rip=0x{x} branch_rip=0x{x} branch_target=0x{x} transfer_rip=0x{x} transfer_len={d} distance={d} jmp_rax={} dead_epilogue={} branch_to_epilogue={} host_return_not_guest={} frame_return=0x{x} executable={}; refusing zero-fill\n",
                .{ self.active_guest_thread, self.regs.rip, @tagName(output.state), @tagName(output.reason), candidate.register_name, candidate.value, candidate.aliases_null_base, witness.guest_return, self.regs.rcx, witness.stack_slot, witness.stack_value, witness.compare_rip, witness.branch_rip, witness.branch_target, tail.transfer_rip, tail.transfer_len, tail.transfer_distance, tail.jmp_rax, tail.dead_epilogue, branch_targets_dead_epilogue, frame_proof.return_not_guest, host_return, frame_proof.return_executable },
            );
            // The aliasing rejections are about retained history, not about the
            // register file, so report what history actually said. Otherwise a
            // run reads "target not proven" for a target that was proven — zero
            // — and the search goes to the transducer rather than to whoever
            // cleared the base register.
            if (candidate.aliases_null_base) {
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST evidence: base={s} live=0x0 (the fault's own definition) source={s} value=0x{x} guest_return_slot=[rsp+0x{x}]=0x{x}; a redirect along the guest predicate edge requires the recovered value to equal the return slot\n",
                    .{
                        candidate.register_name,
                        @tagName(evidence.source),
                        evidence.value,
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
                machoCapturePrint(
                    "macho-processor: bounded dispatch FST block: origin={s} block_start=0x{x} block_length={d} anchor=0x{x} register={s}; {s}\n",
                    .{
                        @tagName(definition.origin),
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

    // A redirect that lands back on the same load is not progress. Both routes
    // out of this transducer re-enter generated code, so the loop guard has to
    // cover them; without it a permanently cleared base register would redirect
    // forever instead of surfacing.
    if (!recoveryLoopAllowed(&self.bounded_dispatch_recoveries, "bounded_dispatch", self.regs.rip)) return false;

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
        .return_not_guest = !isGuestModuleAddress(return_address),
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
        const guest = isGuestModuleAddress(value);
        if (guest or idx < 6) {
            machoCapturePrint(
                "macho-processor:   frame stack[rsp+0x{x}]=0x{x}{s}\n",
                .{ idx * 8, value, if (guest) " (guest-window)" else "" },
            );
        }
    }
    // RCX is printed only as contextual state. At the null-base load it is not
    // authoritative; the guest return witness is the fixed [rsp+0x58] slot.
    if (isGuestModuleAddress(self.regs.rcx)) {
        machoCapturePrint(
            "macho-processor: generated dispatch: rcx=0x{x} ({s}) = Xenia GUEST_RET_ADDR candidate; guest resumes at this module address\n",
            .{ self.regs.rcx, guestModuleName(self.regs.rcx) },
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
pub fn tryRecoverGeneratedNullIndirectTransfer(self: anytype, kind: []const u8) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "has_xenia_compat") or
        !@hasField(State, "sparse_memory") or
        !@hasField(State, "generated_null_indirect") or
        !@hasField(State, "last_generated_null_read_rip"))
    {
        return false;
    }
    if (!self.has_xenia_compat) return false;
    if (!self.sparse_memory.isExecutable(self.regs.rip, 1)) return false;

    const fault = decodedInstructionAt(self, self.regs.rip) orelse return false;
    if (!isGeneratedNullTransferOp(fault.op)) return false;
    if (fault.op == .call_reg64 or fault.op == .call_mem64) return false;
    const after = self.guestMemoryConst(self.regs.rip +| fault.len, 16) orelse return false;
    if (!isFunctionExitEpilogueBytes(after)) return false;
    // Same host-frame proof as the other two consumers. This site previously
    // required only a non-zero executable `[rbp+8]` — no frame alignment, no
    // readable saved frame pointer, no guest-window exclusion — so it accepted
    // frames the transducer rejected and vice versa.
    const frame_proof = hostFrameProof(self);
    if (!frame_proof.usable()) return false;
    if (!recoveryLoopAllowed(&self.generated_null_indirect, "null_indirect_transfer", self.regs.rip)) return false;

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
    }
    return true;
}

// Xenia's guest physical memory window: Xbox 360 guest RAM mapped at
// 0x80000000 with the XEX modules inside it — xboxkrnl.exe (0x80000000),
// xam.xex (0x801C0000), and the game module (0x82000000). JIT-generated code
// that transfers to an address in this window has dispatched through an
// *unpatched indirection-table sentinel*: Xenia initializes
// indirection_table[guest_addr] = guest_addr so a first-execution trap can
// translate the guest function on demand. We have no trap path, so the
// transfer is the same recoverable code-cache miss as the null case.
pub const GUEST_MODULE_BASE: u32 = 0x80000000;
pub const GUEST_MODULE_END: u32 = 0xA0000000;

pub fn isGuestModuleAddress(address: u64) bool {
    // Guest sentinels are canonical 32-bit addresses: zero-extended
    // (0x82582cc8) or sign-extended (0xffffffff8313e528). Reject genuine
    // 64-bit host pointers (heap/JIT, e.g. 0x108313e528) whose low 32 bits
    // happen to land in the guest window — those must not be skipped.
    const high: u32 = @truncate(address >> 32);
    if (high != 0 and high != 0xFFFFFFFF) return false;
    const low: u32 = @truncate(address);
    return low >= GUEST_MODULE_BASE and low < GUEST_MODULE_END;
}

/// Classify a guest-window address into the known Xenia module it belongs to.
/// Fault-time only; returns a static label.
fn guestModuleName(address: u64) []const u8 {
    const low: u32 = @truncate(address);
    if (low < 0x801C0000) return "xboxkrnl.exe";
    if (low < 0x803C0000) return "xam.xex";
    if (low >= 0x82000000 and low < 0x83000000) return "<game module>";
    return "guest-ram/other-module";
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
    const in_window = isGuestModuleAddress(target);
    const sparse_bytes = self.sparse_memory.bytesConst(target, 16);
    const raw = if (sparse_bytes) |b| b else (self.guestMemoryConst(target, 16) orelse &[_]u8{});
    const shown = raw[0..@min(@as(usize, 16), raw.len)];
    machoCapturePrint(
        "macho-processor: invalid control-flow target poll: target=0x{x} target32=0x{x} sign_extended={} zero_extended={} guest_module_window={} module={s} readable={} bytes={any}\n",
        .{ target, low, sign_extended, zero_extended, in_window, if (in_window) guestModuleName(target) else "<none>", raw.len != 0, shown },
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

    const fault = decodedInstructionAt(self, context.instruction_address) orelse return false;
    if (!isGeneratedDispatchMissOp(fault.op)) return false;
    if (!isGuestModuleAddress(context.target_address)) return false;
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
                guestModuleName(context.target_address),
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

pub fn readMemVal(self: anytype, addr: u64, size: Size) u64 {
    const State = @TypeOf(self.*);
    const bytes = bytesForSize(size);
    // Sparse mappings live outside the contiguous Mach-O image.  The memory
    // manager already knows how to read them, so don't require an unrelated
    // main-image offset before dispatching the read.  Writes have always
    // followed this ordering; keeping reads symmetric prevents valid mprotect
    // activations from being reported as permission faults.
    var effective_address = addr;
    var sparse_readable = self.sparse_memory.bytesConst(effective_address, bytes) != null;
    var off = if (sparse_readable) null else translateGuest(self, effective_address, bytes, .read);
    if (!sparse_readable and off == null) {
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
                    sparse_readable = self.sparse_memory.bytesConst(effective_address, bytes) != null;
                    off = if (sparse_readable) null else translateGuest(self, effective_address, bytes, .read);
                }
            },
            .null_base_dispatch => {
                if (tryRedirectBoundedNullDispatch(self, classification.fault)) return 0;
            },
            .null_base_scalar => {
                if (tryRecoverGeneratedNullScalarRead(self, classification, bytes)) return 0;
            },
        }
        if (!sparse_readable and off == null) {
            const snapshot = currentInstructionSnapshot(self);
            const instruction = if (snapshot.operation.len != 0) snapshot.operation else @tagName(if (self.execution_history.latestFor(self.active_guest_thread)) |e| e.op else .invalid);
            terminateForGuestAccess(self, effective_address, bytes, .read, instruction);
            return 0;
        }
    }
    const ctx: *anyopaque = @ptrCast(self);
    return memReadMemVal(&ms(self), effective_address, size, off, .{
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
    // This callback is reached from every interpreted 64-bit memory read.
    // Reject the overwhelmingly common non-candidate case before consulting
    // allocation metadata or building symbol evidence. Non-zero recovery is
    // opt-in and disabled by the default safety policy.
    if (current_value >= 0x1000 and !self.vtable_tracker.policy.repair_nonzero_corruption) return null;

    const has_heap_history = self.vtable_tracker.hasTrustedHistory(address);
    const has_modeled_history = current_value < 0x1000 and self.vtable_stack_registry.contains(address);
    if (!has_heap_history and !has_modeled_history) return null;

    const exact_live_base = has_heap_history and self.memory_forwarder.allocationSize(address) != null;

    // Phase 1: low-read recovery (value < 0x1000, e.g. cleared to 0 or small sentinel)
    if (has_heap_history) {
        if (self.vtable_tracker.assessLowRead(
            address,
            current_value,
            exact_live_base,
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
    if (has_modeled_history) {
        if (self.vtable_stack_registry.assessLowRead(address, current_value)) |recovery| {
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
    }

    return null;
}

fn logAndReturnRecovery(self: anytype, address: u64, recovery: vt.Recovery, observed: u64) ?u64 {
    const symbol = self.metadata.nearestSymbol(recovery.value) orelse return null;
    if (!self.vtable_tracker.noteRecovery(address, recovery.generation)) return null;
    const kind = if (observed < 0x1000) "low-read" else "corruption";
    machoCapturePrint(
        "macho-processor: trusted vtable {s} recovery: object=0x{x} generation={d} allocation_size={d} observed=0x{x} restored=0x{x} vtable={s}+0x{x} established_by=0x{x}@{d} last_write=0x{x}@{d} prior_recoveries={d} thread=0x{x}\n",
        .{
            kind,
            address,
            recovery.generation,
            self.memory_forwarder.allocationSize(address) orelse 0,
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
    return recovery.value;
}

pub fn logLiveVtableGuardSummary(self: anytype) void {
    machoCapturePrint(
        "macho-processor: vtable runtime: low_reads_checked={d} recoveries={d} write_time_mutations={d} tracked_objects={d} establishments={d} transitions={d} rejected_candidates={d} low_clears={d} retired={d} heap_corruption_detections={d} guard_tracked={d} memory_writes={d} range_mutations={d} truncated_range_mutations={d}; recovery requires a live allocation base and strict mapped Itanium ZTV evidence\n",
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
            self.memory_writes.range_mutations,
            self.memory_writes.truncated_range_mutations,
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
    // R3 (N4): vtable/provenance tracking is fault-time diagnostics. The flag
    // gates it so unarmed runs pay one branch per 64-bit store instead of the
    // allocation probe + observeWrite (+ occasional write-protection work).
    if (!self.write_diagnostics_armed) return;
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
            "macho-processor: vtable cleared: object=0x{x} gen={d} vtable=0x{x}({s}+0x{x}) writer=0x{x} {s}+0x{x} step={d} thread=0x{x}\n",
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
            },
        );
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
        if (self.sparse_memory.bytes(addr, 8, true)) |storage| {
            std.mem.writeInt(u64, storage[0..8], result.previous_vptr, .little);
        } else {
            const off = translateGuest(self, addr, 8, .write) orelse return;
            if (off + 8 <= self.mem.len) {
                std.mem.writeInt(u64, self.mem[off..][0..8], result.previous_vptr, .little);
            }
        }
        self.vtable_tracker.live_vtable_write_protections +|= 1;
        const vtable_symbol = self.metadata.nearestSymbol(result.previous_vptr);
        const prot_writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
        machoCapturePrint(
            "macho-processor: vptr write-protection: object=0x{x} gen={d} vtable=0x{x}({s}+0x{x}) restored_by=0x{x} {s}+0x{x} step={d} thread=0x{x}\n",
            .{
                addr,
                result.generation,
                result.previous_vptr,
                self.metadata.symbolLabel(result.previous_vptr),
                if (vtable_symbol) |s| s.offset else 0,
                self.regs.rip,
                self.metadata.symbolLabel(self.regs.rip),
                if (prot_writer_symbol) |s| s.offset else 0,
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

pub fn writeMemVal(self: anytype, addr: u64, size: Size, val: u64) void {
    const bytes = bytesForSize(size);
    if (self.sparse_memory.bytes(addr, bytes, true)) |storage| {
        recordMemoryAccess(self, addr, size, "write", val);
        noteGuestWrite(self, addr, bytes);
        if (size == .bits64 and (addr & 7) == 0) {
            if (self.write_diagnostics_armed) {
                const previous = std.mem.readInt(u64, storage[0..8], .little);
                self.memory_writes.record(self.allocator, addr, previous, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
            }
            std.mem.writeInt(u64, storage[0..8], val, .little);
        } else {
            const mutation = captureMemoryMutation(self, addr, bytes);
            switch (size) {
                .bits8 => storage[0] = @truncate(val),
                .bits16 => std.mem.writeInt(u16, storage[0..2], @truncate(val), .little),
                .bits32 => std.mem.writeInt(u32, storage[0..4], @truncate(val), .little),
                .bits64 => std.mem.writeInt(u64, storage[0..8], val, .little),
            }
            commitMemoryMutation(self, mutation, .partial_scalar);
        }
        recordAllocationWrite(self, addr, size, val);
        // Suspicious write: 64-bit value pointing into executable (code) segment
        // written to any heap/data memory — tree node structural corruption pattern.
        // Values below 0x100000 are not plausible code pointers (e.g. MicroProfile token IDs).
        // Only function_prologue values are genuinely suspicious; generic
        // code_address writes are legitimate initialization (Export struct
        // function pointer storage, hash table bucket counts, CommandVar
        // default value pointers).
        if (self.write_diagnostics_armed and size == .bits64 and val >= MIN_PLAUSIBLE_CODE_POINTER and val >= self.executable_min and val < self.executable_max) {
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
                            self.metadata.symbolLabel(self.regs.rip),
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
        const snapshot = currentInstructionSnapshot(self);
        const instruction = if (snapshot.operation.len != 0) snapshot.operation else @tagName(if (self.execution_history.latestFor(self.active_guest_thread)) |e| e.op else .invalid);
        terminateForGuestAccess(self, addr, bytes, .write, instruction);
        return;
    };
    recordMemoryAccess(self, addr, size, "write", val);
    self.initializer_memory.capture(self.mem, @intCast(off), bytes);
    noteGuestWrite(self, addr, bytes);
    if (size == .bits64 and (addr & 7) == 0) {
        if (self.write_diagnostics_armed) {
            const previous = std.mem.readInt(u64, self.mem[off..][0..8], .little);
            self.memory_writes.record(self.allocator, addr, previous, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
        }
        std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
    } else {
        const mutation = captureMemoryMutation(self, addr, bytes);
        switch (size) {
            .bits8 => self.mem[off] = @truncate(val),
            .bits16 => std.mem.writeInt(u16, self.mem[off..][0..2], @truncate(val), .little),
            .bits32 => std.mem.writeInt(u32, self.mem[off..][0..4], @truncate(val), .little),
            .bits64 => std.mem.writeInt(u64, self.mem[off..][0..8], val, .little),
        }
        commitMemoryMutation(self, mutation, .partial_scalar);
    }
    recordAllocationWrite(self, addr, size, val);
    // Suspicious write: 64-bit value pointing into executable (code) segment
    // written to any heap/data memory — tree node structural corruption pattern.
    // Values below 0x100000 are not plausible code pointers (e.g. MicroProfile token IDs).
    // Only function_prologue values are genuinely suspicious; generic
    // code_address writes are legitimate initialization (Export struct
    // function pointer storage, hash table bucket counts, CommandVar
    // default value pointers).
    if (self.write_diagnostics_armed and size == .bits64 and val >= 0x100000 and val >= self.executable_min and val < self.executable_max) {
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
                        self.metadata.symbolLabel(self.regs.rip),
                        if (writer_symbol) |s| s.offset else 0,
                        self.executed_steps,
                    },
                );
            }
        }
    }
    timerQueueWatchWrite(self, addr, size, val);
}

pub fn captureMemoryMutation(
    self: anytype,
    address: u64,
    length: u64,
) memory_write_provenance.MutationCapture {
    // R3 (N4): the before-image capture re-reads every overlapping pointer
    // slot (a full memory probe per store). It is fault-time diagnostics; when
    // write diagnostics are unarmed (the default fast path) return an empty
    // capture so stores pay nothing for it. commitMemoryMutation applies the
    // matching gate.
    if (!self.write_diagnostics_armed) return .{ .address = address, .length = length };
    return self.memory_writes.captureMutation(self, address, length);
}

pub fn commitMemoryMutation(
    self: anytype,
    capture: memory_write_provenance.MutationCapture,
    kind: memory_write_provenance.WriteKind,
) void {
    // R3 (N4): matching gate to captureMemoryMutation. When unarmed the
    // capture is empty and the re-read/compare/record work is skipped.
    if (!self.write_diagnostics_armed) return;
    // The writer recorded below is `regs.rip` — the *faulting guest*
    // instruction — even when the write came from a Rosette repair rather than
    // from the guest. Reclassify while a repair is in flight so consumers can
    // tell the two apart instead of blaming a guest symbol for our own store.
    const attributed_kind: memory_write_provenance.WriteKind =
        if (comptime @hasField(@TypeOf(self.*), "host_repair_in_flight"))
            (if (self.host_repair_in_flight) .host_repair else kind)
        else
            kind;
    self.memory_writes.commitMutation(
        self.allocator,
        self,
        capture,
        self.regs.rip,
        self.executed_steps,
        self.active_guest_thread,
        attributed_kind,
    );
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
    const fault = decodeTraceInstruction(self, fault_entry) orelse return false;
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
        const instruction_len = currentGuestInstructionLength(self);
        if (self.deliverGuestSignal(GUEST_SIGSEGV, self.regs.rip, instruction_len, address, access, bytes, instruction)) {
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
    // P1-2 (perf audit): this runs on every guest load/store, and its
    // currentInstructionSnapshot() re-decodes the current instruction purely
    // for the ring buffer. The ring is only consumed post-fault, so gate the
    // whole path behind the diagnostic flag; the default fast path is a direct
    // slice read.
    if (!self.memory_trace_enabled) return;
    const bytes = bytesForSize(size);
    const offset = translateGuest(self, address, bytes, if (std.mem.eql(u8, access, "write")) .write else .read);
    const backed = if (offset) |off| off + bytes <= self.mem.len else false;
    const trace_count: usize = self.execution_history.countFor(self.active_guest_thread);
    const instruction_snapshot = if (self.sparse_memory.isExecutable(self.regs.rip, 1))
        currentInstructionSnapshot(self)
    else
        InstructionSnapshot{};
    const instruction = if (instruction_snapshot.operation.len != 0)
        instruction_snapshot.operation
    else if (trace_count == 0)
        "<runtime>"
    else
        @tagName(if (self.execution_history.latestFor(self.active_guest_thread)) |e| e.op else .invalid);
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

pub fn writeMem128(self: anytype, addr: u64, value: [16]u8) void {
    if (self.sparse_memory.bytes(addr, 16, true)) |storage| {
        noteGuestWrite(self, addr, 16);
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
    const touches_sparse_code = self.sparse_memory.isExecutable(address, count);
    if (!touches_image_code and !touches_sparse_code) return;

    self.code_generation +%= 1;
    if (self.code_generation == 0) self.code_generation = 1;

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
        @memset(self.decode_cache, .{});
        return;
    }
    // Any x86 instruction overlapping this write must begin between
    // address-14 and end-1. Probe exact candidate starts with the same hash as
    // decodeAt; this preserves precise invalidation without reverting to a
    // global cache flush for each small Xenia JIT patch.
    var candidate = first_candidate;
    while (candidate <= last_candidate) : (candidate += 1) {
        const cache_index = constants.decodeCacheIndex(candidate);
        const entry = &self.decode_cache[cache_index];
        if (entry.rip == std.math.maxInt(u64)) continue;
        const instruction_length = @max(@as(u64, entry.decoded.len), 1);
        const instruction_end = entry.rip +| instruction_length;
        if (entry.rip < end and instruction_end > address) {
            entry.* = .{};
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
    self.memory_forwarder.release(address);
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
