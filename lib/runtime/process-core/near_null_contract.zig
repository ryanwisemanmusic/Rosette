//! Semantic policy for near-null observations.
//!
//! A small address is not, by itself, a recoverable condition.  In particular,
//! an attempted load or store through a null C++ receiver is a real ownership
//! failure and continuing would merely move the corruption downstream.  This
//! module keeps that decision separate from the (necessarily heuristic)
//! provenance reporters so diagnostics may become richer without silently
//! turning new fault shapes into permissive recovery rules.

const std = @import("std");
/// The address-space bound, the Itanium mangling rule, and the libc++ layout
/// arithmetic all moved to `pkg/common/abi/near-null-shape`. They are settled
/// before a process starts; what stays here is the *policy* built on top of
/// them — whether a near-null dereference may be tolerated, and whether Rosette
/// may manufacture storage for it. That distinction is the whole reason the two
/// halves are separate files.
const shape = @import("near_null_shape");

pub const ReceiverShape = shape.ReceiverShape;
pub const near_null_limit = shape.near_null_limit;

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
    /// What the receiver value looks like arithmetically. Carried alongside the
    /// policy verdict because the two answer different questions: `kind` says
    /// what rule was violated, `receiver_shape` says which investigation finds
    /// the cause. A zero receiver at a zero-offset accessor is as consistent
    /// with an empty container as with a clobbered pointer, and only one of
    /// those hunts succeeds.
    receiver_shape: ReceiverShape = .mapped,
    /// True when the faulting callee's receiver is the container or pointer
    /// itself rather than a displaced field.
    zero_offset_accessor: bool = false,

    /// One sentence naming what this receiver value is consistent with.
    pub fn shapeExplanation(self: Finding) []const u8 {
        return shape.shapeExplanation(self.receiver_shape, self.zero_offset_accessor);
    }

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

    const receiver_shape = shape.classifyReceiver(input.sysv_this);
    const zero_offset_accessor = shape.isZeroOffsetAccessor(input.symbol);

    if (!input.dereferences_memory) {
        return .{
            .domain = domain,
            .kind = .optional_sentinel,
            .acceptance = .accepted_value_only,
            .receiver_shape = receiver_shape,
            .zero_offset_accessor = zero_offset_accessor,
        };
    }

    const kind: Kind = if (domain == .host_native and
        input.base_is_zero and
        input.sysv_this == 0 and
        looksLikeCppMember(input.symbol))
        .null_receiver
    else if (input.base_is_zero and shape.isNearNull(input.effective_address))
        .derived_near_null
    else
        .unknown;

    return .{
        .domain = domain,
        .kind = kind,
        .acceptance = .rejected_dereference,
        .receiver_shape = receiver_shape,
        .zero_offset_accessor = zero_offset_accessor,
    };
}

/// Itanium-mangled non-static C++ member functions start with `ZN` after the
/// Mach-O assembler's one or two leading underscores are removed. `K`
/// immediately after `N` denotes a const-qualified member, as in
/// KernelState::memory() const.
pub fn looksLikeCppMember(symbol: []const u8) bool {
    return shape.looksLikeCppMember(symbol);
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

test "the Vulkan queue finding reads as an empty container" {
    // Reproduces the 2026-08-24 terminal near-null exactly: a const member of
    // `unique_ptr` entered with `this == 0`. The policy verdict is unchanged —
    // still refused, still no manufactured storage — but the finding now also
    // says the value is what `&queues[0]` looks like when `queues` is empty,
    // which is a different hunt from a clobbered pointer.
    const callee = "__ZNKSt3__110unique_ptrIN2xe2ui6vulkan12VulkanDevice5QueueENS_14default_deleteIS5_EEEptB7v160006Ev";
    const finding = classify(.{
        .generated_rip = false,
        .native_image_rip = true,
        .effective_address = 0,
        .base_is_zero = true,
        .sysv_this = 0,
        .symbol = callee,
        .dereferences_memory = true,
    });
    try std.testing.expectEqual(Kind.null_receiver, finding.kind);
    try std.testing.expectEqual(Acceptance.rejected_dereference, finding.acceptance);
    try std.testing.expectEqual(ReceiverShape.exact_zero, finding.receiver_shape);
    try std.testing.expect(finding.zero_offset_accessor);
    try std.testing.expect(std.mem.indexOf(u8, finding.shapeExplanation(), "empty") != null);
}

test "a displaced field is not reported as a container" {
    const finding = classify(.{
        .generated_rip = false,
        .native_image_rip = true,
        .effective_address = 0x1c,
        .base_is_zero = true,
        .sysv_this = 0x1c,
        .symbol = "_ZN2xe7Example3runEv",
        .dereferences_memory = true,
    });
    try std.testing.expectEqual(ReceiverShape.member_displacement, finding.receiver_shape);
    try std.testing.expect(!finding.zero_offset_accessor);
    try std.testing.expect(!finding.receiver_shape.admitsEmptyContainer());
}
