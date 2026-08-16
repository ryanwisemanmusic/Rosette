//! Semantic policy for near-null observations.
//!
//! A small address is not, by itself, a recoverable condition.  In particular,
//! an attempted load or store through a null C++ receiver is a real ownership
//! failure and continuing would merely move the corruption downstream.  This
//! module keeps that decision separate from the (necessarily heuristic)
//! provenance reporters so diagnostics may become richer without silently
//! turning new fault shapes into permissive recovery rules.

const std = @import("std");

pub const Domain = enum {
    guest_generated,
    host_native,
    unknown,
};

pub const Kind = enum {
    /// A native C++ member function was entered with the SysV `this` argument
    /// equal to zero and subsequently dereferenced a value derived from it.
    null_receiver,
    /// An actual access was attempted through a zero base plus a small field
    /// displacement, but a receiver boundary has not yet been proven.
    derived_near_null,
    /// A zero value is being inspected as data (for example by a comparison),
    /// not dereferenced.  Such values may be valid API sentinels.
    optional_sentinel,
    unknown,
};

pub const Acceptance = enum {
    /// Continuing is forbidden: the instruction performs a memory access and
    /// there is no storage contract behind the near-null address.
    rejected_dereference,
    /// Zero may be accepted only as a value.  It must never be materialised as
    /// readable or writable memory by the near-null recovery machinery.
    accepted_value_only,
};

pub const Input = struct {
    generated_rip: bool,
    native_image_rip: bool,
    effective_address: u64,
    base_is_zero: bool,
    sysv_this: u64,
    symbol: []const u8,
    dereferences_memory: bool,
};

pub const Finding = struct {
    domain: Domain,
    kind: Kind,
    acceptance: Acceptance,

    pub fn isNativeNullReceiver(self: Finding) bool {
        return self.domain == .host_native and self.kind == .null_receiver;
    }
};

pub fn classify(input: Input) Finding {
    const domain: Domain = if (input.generated_rip)
        .guest_generated
    else if (input.native_image_rip)
        .host_native
    else
        .unknown;

    if (!input.dereferences_memory) {
        return .{
            .domain = domain,
            .kind = .optional_sentinel,
            .acceptance = .accepted_value_only,
        };
    }

    const kind: Kind = if (domain == .host_native and
        input.base_is_zero and
        input.sysv_this == 0 and
        looksLikeCppMember(input.symbol))
        .null_receiver
    else if (input.base_is_zero and input.effective_address < 0x1000)
        .derived_near_null
    else
        .unknown;

    return .{
        .domain = domain,
        .kind = kind,
        .acceptance = .rejected_dereference,
    };
}

/// Itanium-mangled non-static C++ member functions start with `ZN` after the
/// Mach-O assembler's one or two leading underscores are removed. `K`
/// immediately after `N` denotes a const-qualified member, as in
/// KernelState::memory() const.
pub fn looksLikeCppMember(symbol: []const u8) bool {
    var start: usize = 0;
    while (start < symbol.len and start < 2 and symbol[start] == '_') : (start += 1) {}
    return std.mem.startsWith(u8, symbol[start..], "ZN");
}

test "native C++ null receiver dereference is never accepted" {
    const finding = classify(.{
        .generated_rip = false,
        .native_image_rip = true,
        .effective_address = 0x58,
        .base_is_zero = true,
        .sysv_this = 0,
        .symbol = "_ZNK2xe6kernel11KernelState6memoryEv",
        .dereferences_memory = true,
    });
    try std.testing.expectEqual(Domain.host_native, finding.domain);
    try std.testing.expectEqual(Kind.null_receiver, finding.kind);
    try std.testing.expectEqual(Acceptance.rejected_dereference, finding.acceptance);
    try std.testing.expect(finding.isNativeNullReceiver());
}

test "Mach-O's double-underscore member symbol is recognized" {
    try std.testing.expect(looksLikeCppMember("__ZNK2xe6kernel11KernelState6memoryEv"));
    try std.testing.expect(looksLikeCppMember("_ZN2xe7Example3runEv"));
    try std.testing.expect(looksLikeCppMember("ZN2xe7Example3runEv"));
    try std.testing.expect(!looksLikeCppMember("___ZN2xe7Example3runEv"));
    try std.testing.expect(!looksLikeCppMember("_some_c_api"));
}

test "optional null is accepted only as a value" {
    const finding = classify(.{
        .generated_rip = false,
        .native_image_rip = true,
        .effective_address = 0,
        .base_is_zero = true,
        .sysv_this = 0,
        .symbol = "_some_c_api",
        .dereferences_memory = false,
    });
    try std.testing.expectEqual(Kind.optional_sentinel, finding.kind);
    try std.testing.expectEqual(Acceptance.accepted_value_only, finding.acceptance);
}

test "generated near-null is not mislabeled as a native receiver" {
    const finding = classify(.{
        .generated_rip = true,
        .native_image_rip = false,
        .effective_address = 0x10,
        .base_is_zero = true,
        .sysv_this = 0,
        .symbol = "<outside-image:generated-or-heap>",
        .dereferences_memory = true,
    });
    try std.testing.expectEqual(Domain.guest_generated, finding.domain);
    try std.testing.expectEqual(Kind.derived_near_null, finding.kind);
    try std.testing.expect(!finding.isNativeNullReceiver());
}
