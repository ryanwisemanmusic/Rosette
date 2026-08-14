const std = @import("std");

/// Recovery is deliberately separated from observation.  The tracker may
/// learn about vptrs in either mode, but only the second mode may propose a
/// repair, and only when a low value is about to be consumed from the exact
/// base of a still-live allocation.
pub const RecoveryMode = enum {
    observe_only,
    repair_trusted_low_read,
};

pub const Policy = struct {
    recovery_mode: RecoveryMode = .repair_trusted_low_read,

    /// Itanium vtable address points are offsets into a `_ZTV` object.  Keep
    /// this finite because "nearest symbol" queries may otherwise associate an
    /// arbitrary heap pointer with a very distant vtable symbol.
    max_symbol_offset: u64 = 0x1000,
    require_mapped_header: bool = true,

    /// When `true`, the tracker may also propose recovery when a value at a
    /// tracked allocation base is read as non-zero (>= 0x1000) but is NOT a
    /// valid vtable identity.  This covers corruption patterns where the
    /// vptr is overwritten with a non-zero invalid pointer rather than
    /// cleared to zero.
    ///
    /// The caller is responsible for passing the rejection (if any) of the
    /// current value via `assessCorruption`.  The tracker itself has no
    /// access to symbol metadata and cannot build IdentityEvidence.
    repair_nonzero_corruption: bool = false,
};

/// How many pointer slots past an object's base may hold a tracked vptr.
///
/// One number, used by both sides on purpose. The write side probes backwards
/// this far to find the object a secondary base's vptr belongs to, and free
/// retires forwards this far to take those slots with it. If the two ever
/// disagreed, a slot could be tracked and never retired — a stale vtable
/// waiting for the storage to be handed to something else.
///
/// It is a bound rather than a search because the alternative on either side is
/// work proportional to the heap, on a path taken by ordinary guest writes.
pub const max_subobject_slots: usize = 8;

pub const Provenance = struct {
    writer_rip: u64 = 0,
    writer_step: u64 = 0,
    writer_thread: u64 = 0,
    /// Base of the allocation the written slot belongs to.
    ///
    /// A class with multiple inheritance keeps one vptr per non-primary base at
    /// a non-zero offset inside the object, so a tracked slot is not always the
    /// allocation base. Recording which object a slot belongs to is what makes
    /// two things possible: retiring every slot of an allocation when it is
    /// freed, and refusing to restore a vptr into storage that has since been
    /// handed to a different object.
    owner_base: u64 = 0,
};

pub const IdentityRejection = enum {
    low_address,
    unaligned_address,
    missing_symbol,
    non_vtable_symbol,
    before_address_point,
    symbol_offset_too_large,
    unaligned_symbol_offset,
    unmapped_header,
};

/// Evidence is assembled by the Mach-O integration, while the policy decision
/// remains runtime-library code and is independently testable.
pub const IdentityEvidence = struct {
    value: u64,
    symbol_name: ?[]const u8 = null,
    symbol_offset: u64 = std.math.maxInt(u64),
    header_mapped: bool = false,
    typeinfo_plausible: bool = false,
    first_slot_plausible: bool = false,

    pub fn rejection(self: IdentityEvidence, policy: Policy) ?IdentityRejection {
        if (self.value < 0x1000) return .low_address;
        if ((self.value & 7) != 0) return .unaligned_address;
        const name = self.symbol_name orelse return .missing_symbol;
        if (!isItaniumVtableSymbol(name)) return .non_vtable_symbol;

        // A primary address point normally starts after offset-to-top and
        // typeinfo (16 bytes).  Secondary address points may be farther into
        // the same symbol, but must remain aligned and tightly bounded.
        if (self.symbol_offset < 16) return .before_address_point;
        if (self.symbol_offset > policy.max_symbol_offset) return .symbol_offset_too_large;
        if ((self.symbol_offset & 7) != 0) return .unaligned_symbol_offset;
        if (policy.require_mapped_header and !self.header_mapped) return .unmapped_header;
        return null;
    }

    pub fn isTrusted(self: IdentityEvidence, policy: Policy) bool {
        return self.rejection(policy) == null;
    }
};

/// Accept only an Itanium `_ZTV` mangled-name marker at the beginning of a
/// Mach-O symbol (allowing the platform's one or two leading underscores).
/// A substring match anywhere in a demangled or unrelated symbol is not
/// sufficient identity evidence.
pub fn isItaniumVtableSymbol(name: []const u8) bool {
    var start: usize = 0;
    while (start < name.len and start < 2 and name[start] == '_') : (start += 1) {}
    return std.mem.startsWith(u8, name[start..], "ZTV");
}

pub const AllocationRecord = struct {
    generation: u64,
    trusted_vptr: u64,
    trusted_symbol_offset: u64,
    established_by: Provenance,
    last_write: Provenance,
    last_observed_value: u64,
    valid_transitions: u64 = 0,
    low_clears_observed: u64 = 0,
    recoveries: u64 = 0,
    /// The object this slot belongs to. Equal to the slot address for a
    /// primary vptr and lower for every secondary base's.
    owner_base: u64 = 0,
};

pub const WriteDisposition = enum {
    ignored_non_vtable,
    established,
    valid_transition,
    repeated,
    trusted_value_cleared,
    observed_non_vtable,
};

pub const WriteResult = struct {
    disposition: WriteDisposition,
    generation: u64 = 0,
    previous_vptr: u64 = 0,
    trusted_vptr: u64 = 0,
};

pub const Recovery = struct {
    value: u64,
    generation: u64,
    symbol_offset: u64,
    established_by: Provenance,
    last_write: Provenance,
    prior_recoveries: u64,
};

/// Categories used by the generic memory-provenance diagnostics.  These are
/// intentionally not vtable identity and must never authorize a vptr repair.
pub const SuspiciousValueType = enum {
    function_prologue,
    code_address,
    none,

    pub fn classify(value: u64, executable_min: u64, executable_max: u64) SuspiciousValueType {
        if (detectFunctionProloguePtr(value)) return .function_prologue;
        if (value >= executable_min and value < executable_max) return .code_address;
        return .none;
    }
};

pub fn isAddressInMappedMemory(addr: u64, mapped_min: u64, mem_base: u64, mem_size: u64, stack_size: u64) bool {
    const stack_start = mem_base + mem_size -| stack_size;
    return addr >= mapped_min and addr < stack_start;
}

pub fn detectFunctionProloguePtr(value: u64) bool {
    if (value & 0xFF != 0x55) return false;
    const byte1 = @as(u8, @truncate((value >> 8) & 0xFF));
    if (byte1 == 0x48) {
        const byte2 = @as(u8, @truncate((value >> 16) & 0xFF));
        return byte2 == 0x89 or byte2 == 0x8b or byte2 == 0x81;
    }
    if (byte1 == 0x53) {
        return @as(u8, @truncate((value >> 16) & 0xFF)) == 0x48;
    }
    return false;
}

test "vtable identity requires a bounded Itanium address point" {
    const policy = Policy{};
    try std.testing.expect((IdentityEvidence{
        .value = 0x1950b28,
        .symbol_name = "__ZTVN2xe7ExampleE",
        .symbol_offset = 0x50,
        .header_mapped = true,
    }).isTrusted(policy));

    // The exact false-positive shape from the regression: an ordinary heap
    // pointer associated with a vtable millions of bytes away.
    try std.testing.expect(!(IdentityEvidence{
        .value = 0x46b85c0,
        .symbol_name = "__ZTVN2xe7ExampleE",
        .symbol_offset = 0x26501ff,
        .header_mapped = true,
    }).isTrusted(policy));
    try std.testing.expectEqual(
        IdentityRejection.symbol_offset_too_large,
        (IdentityEvidence{
            .value = 0x46b85c0,
            .symbol_name = "__ZTVN2xe7ExampleE",
            .symbol_offset = 0x26501ff,
            .header_mapped = true,
        }).rejection(policy).?,
    );
    try std.testing.expect(!(IdentityEvidence{
        .value = 0x1950b08,
        .symbol_name = "__ZNSt3__16vectorIiEE",
        .symbol_offset = 0x20,
        .header_mapped = true,
    }).isTrusted(policy));
    try std.testing.expect(!(IdentityEvidence{
        .value = 0x1950b08,
        .symbol_name = "__ZTVN2xe7ExampleE",
        .symbol_offset = 8,
        .header_mapped = true,
    }).isTrusted(policy));
}

test "Itanium vtable symbol marker is anchored" {
    try std.testing.expect(isItaniumVtableSymbol("__ZTVN2xe7ExampleE"));
    try std.testing.expect(isItaniumVtableSymbol("_ZTVN2xe7ExampleE"));
    try std.testing.expect(isItaniumVtableSymbol("ZTVN2xe7ExampleE"));
    try std.testing.expect(!isItaniumVtableSymbol("__ZN4test11mentionsZTVEv"));
}

test "generic provenance helpers remain independent" {
    try std.testing.expect(detectFunctionProloguePtr(0xe5894855));
    try std.testing.expect(!detectFunctionProloguePtr(0x12345678));
    try std.testing.expect(isAddressInMappedMemory(0x8000, 0x4000, 0, 0x10000, 0x2000));
    try std.testing.expectEqual(
        SuspiciousValueType.code_address,
        SuspiciousValueType.classify(0x5000, 0x4000, 0x8000),
    );
}
