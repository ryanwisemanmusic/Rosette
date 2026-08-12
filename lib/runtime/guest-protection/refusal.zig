//! Why a guest memory access was refused, and whether the refusal is correct.
//!
//! A protection fault is not one event. Three different situations produce an
//! identical observation — an access denied at an address the runtime has
//! mapped — and they call for opposite responses:
//!
//!   * **A deliberate trap.** The guest protected the page *itself*, to catch
//!     accesses: a guard page, a memory watch, an MMIO window. The refusal is
//!     the mechanism working, the guest has a handler, and delivering the signal
//!     is the whole point. Reporting it as a failure is reporting a success.
//!   * **A page-granularity artifact.** The guest's page is smaller than the
//!     host's, so protecting one guest page necessarily protects its neighbours.
//!     An access the *guest's* permissions allow is then refused by the *host's*,
//!     and the runtime — not the guest — is the reason. This one is a defect,
//!     and it is invisible without comparing the two permission sets.
//!   * **A genuine violation.** The guest's own permissions deny the access and
//!     nothing is installed to catch it.
//!
//! Only the second is Rosette's bug, only the third is the guest's, and the
//! first is neither. A single "access refused" line cannot distinguish them, so
//! every occurrence gets investigated from scratch and the one that matters is
//! indistinguishable from the two that do not.
//!
//! The discriminator is available and cheap: the guest's own permission for the
//! guest-sized page containing the address, compared against the host-level
//! refusal. When the guest would have allowed it, the enclosing host page is the
//! only thing that said no.

const std = @import("std");

/// Permission bits, in the order the runtime already uses them.
pub const Access = enum(u8) {
    read,
    write,
    execute,

    pub fn bit(self: Access) u8 {
        return switch (self) {
            .read => 1,
            .write => 2,
            .execute => 4,
        };
    }
};

pub const Classification = enum(u8) {
    /// The guest protected this page and has a handler for the trap. Delivering
    /// the fault is correct behaviour, not a failure.
    deliberate_trap,
    /// The guest's own permissions allow this access; only the enclosing host
    /// page denies it. The host page is larger than the guest page, so the
    /// runtime protected memory the guest did not ask to protect.
    page_granularity_artifact,
    /// The guest's permissions deny the access and nothing is installed to
    /// catch it.
    genuine_violation,
    /// The address is not in any mapping the runtime knows about.
    unmapped,

    /// Whether this refusal is the runtime's defect rather than the guest's
    /// behaviour. The only classification that should ever change Rosette.
    pub fn isRuntimeDefect(self: Classification) bool {
        return self == .page_granularity_artifact;
    }

    /// Whether the refusal is correct and expected.
    pub fn isExpected(self: Classification) bool {
        return self == .deliberate_trap;
    }
};

pub const Query = struct {
    address: u64 = 0,
    length: u64 = 0,
    access: Access = .read,
    /// Whether any mapping covers the address at all.
    mapped: bool = false,
    /// Permission bits the *host* mapping grants, i.e. what actually refused.
    host_permissions: u8 = 0,
    /// Permission bits the guest recorded for the guest-sized page containing
    /// the address. This is the metadata a runtime keeps precisely because the
    /// host cannot express it.
    guest_permissions: u8 = 0,
    /// The guest installed a fault handler that could service this.
    guest_handler_installed: bool = false,
    guest_page_size: u64 = 4096,
    host_page_size: u64 = 16384,
};

pub const Verdict = struct {
    classification: Classification = .unmapped,
    /// Guest pages that share the enclosing host page. Above one, protecting a
    /// single guest page necessarily affects neighbours.
    guest_pages_per_host_page: u64 = 1,
    /// Guest-page-aligned base of the access.
    guest_page_base: u64 = 0,
    /// Host-page-aligned base — the granularity the host actually enforced.
    host_page_base: u64 = 0,

    pub fn describe(self: Verdict) []const u8 {
        return switch (self.classification) {
            .unmapped => "no mapping covers this address; the refusal is not a protection decision at all",
            .deliberate_trap => "the guest protected this page and has a handler installed, so the refusal is the guest's own trap firing. Delivering the fault is correct — this is the mechanism working, not a failure, and it should not be counted against the runtime",
            .page_granularity_artifact => "the GUEST's permissions allow this access and only the enclosing HOST page denied it. The host page is larger than the guest page, so protecting one guest page also protected this one. This is the runtime's defect: the guest never asked for this address to be inaccessible",
            .genuine_violation => "the guest's own permissions deny this access and no handler is installed to service it. This is a guest-side fault",
        };
    }
};

pub fn classify(query: Query) Verdict {
    var verdict = Verdict{};
    if (query.guest_page_size != 0) {
        verdict.guest_page_base = query.address & ~(query.guest_page_size - 1);
    }
    if (query.host_page_size != 0) {
        verdict.host_page_base = query.address & ~(query.host_page_size - 1);
        if (query.guest_page_size != 0 and query.host_page_size >= query.guest_page_size) {
            verdict.guest_pages_per_host_page = query.host_page_size / query.guest_page_size;
        }
    }
    if (!query.mapped) {
        verdict.classification = .unmapped;
        return verdict;
    }

    const bit = query.access.bit();
    const guest_allows = query.guest_permissions & bit != 0;
    const host_allows = query.host_permissions & bit != 0;

    if (host_allows) {
        // Nothing refused it at the host level, so whatever refused it was the
        // guest's own metadata: a deliberate trap when a handler exists.
        verdict.classification = if (query.guest_handler_installed)
            .deliberate_trap
        else
            .genuine_violation;
        return verdict;
    }
    if (guest_allows) {
        // The guest permits it; only the coarser host page said no. That is the
        // runtime's granularity, not the guest's intent — and it stays a defect
        // even when a handler happens to exist, because the guest is being made
        // to service a trap it never installed.
        verdict.classification = .page_granularity_artifact;
        return verdict;
    }
    verdict.classification = if (query.guest_handler_installed)
        .deliberate_trap
    else
        .genuine_violation;
    return verdict;
}

test "a guest-protected page with a handler is the mechanism working" {
    const verdict = classify(.{
        .address = 0x34d830001,
        .length = 4,
        .access = .read,
        .mapped = true,
        .host_permissions = 0,
        .guest_permissions = 0,
        .guest_handler_installed = true,
    });
    try std.testing.expectEqual(Classification.deliberate_trap, verdict.classification);
    try std.testing.expect(verdict.classification.isExpected());
    try std.testing.expect(!verdict.classification.isRuntimeDefect());
}

// The one that is Rosette's bug, and the one a single "access refused" line
// could never surface: the guest allows the access and only the larger host
// page refuses it.
test "a guest-allowed access refused by the host page is the runtime's defect" {
    const verdict = classify(.{
        .address = 0x34d831000,
        .length = 4,
        .access = .read,
        .mapped = true,
        .host_permissions = 0,
        .guest_permissions = 1, // guest says readable
        .guest_handler_installed = false,
        .guest_page_size = 4096,
        .host_page_size = 16384,
    });
    try std.testing.expectEqual(Classification.page_granularity_artifact, verdict.classification);
    try std.testing.expect(verdict.classification.isRuntimeDefect());
    try std.testing.expectEqual(@as(u64, 4), verdict.guest_pages_per_host_page);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "runtime's defect") != null);
}

// A handler does not excuse it: the guest is being made to service a trap it
// never installed, and calling that expected would hide the granularity bug
// behind the guest's own error handling.
test "a handler does not turn a granularity artifact into an expected trap" {
    const verdict = classify(.{
        .address = 0x1000,
        .access = .write,
        .mapped = true,
        .host_permissions = 1, // readable but not writable at host level
        .guest_permissions = 3, // guest allows read and write
        .guest_handler_installed = true,
    });
    try std.testing.expectEqual(Classification.page_granularity_artifact, verdict.classification);
    try std.testing.expect(verdict.classification.isRuntimeDefect());
}

test "a denial both sides agree on, with no handler, is a guest fault" {
    const verdict = classify(.{
        .address = 0x2000,
        .access = .write,
        .mapped = true,
        .host_permissions = 1,
        .guest_permissions = 1,
        .guest_handler_installed = false,
    });
    try std.testing.expectEqual(Classification.genuine_violation, verdict.classification);
    try std.testing.expect(!verdict.classification.isRuntimeDefect());
    try std.testing.expect(!verdict.classification.isExpected());
}

test "an unmapped address is not a protection decision" {
    const verdict = classify(.{ .address = 0xdead0000, .mapped = false });
    try std.testing.expectEqual(Classification.unmapped, verdict.classification);
    try std.testing.expect(!verdict.classification.isRuntimeDefect());
}

test "an access the host permits is never blamed on granularity" {
    const verdict = classify(.{
        .address = 0x3000,
        .access = .read,
        .mapped = true,
        .host_permissions = 7,
        .guest_permissions = 0,
        .guest_handler_installed = true,
    });
    try std.testing.expectEqual(Classification.deliberate_trap, verdict.classification);
}

test "page bases are reported at both granularities" {
    const verdict = classify(.{
        .address = 0x34d833abc,
        .mapped = true,
        .guest_page_size = 4096,
        .host_page_size = 16384,
        .host_permissions = 0,
        .guest_permissions = 1,
    });
    try std.testing.expectEqual(@as(u64, 0x34d833000), verdict.guest_page_base);
    try std.testing.expectEqual(@as(u64, 0x34d830000), verdict.host_page_base);
    try std.testing.expectEqual(@as(u64, 4), verdict.guest_pages_per_host_page);
}

test "equal page sizes cannot produce a granularity artifact" {
    const verdict = classify(.{
        .address = 0x5000,
        .access = .read,
        .mapped = true,
        .host_permissions = 0,
        .guest_permissions = 0,
        .guest_handler_installed = false,
        .guest_page_size = 4096,
        .host_page_size = 4096,
    });
    try std.testing.expectEqual(@as(u64, 1), verdict.guest_pages_per_host_page);
    try std.testing.expectEqual(Classification.genuine_violation, verdict.classification);
}

/// Running counts, so a run can say whether its refusals were traps working or
/// the runtime's granularity leaking.
pub const Census = struct {
    deliberate_traps: u64 = 0,
    granularity_artifacts: u64 = 0,
    genuine_violations: u64 = 0,
    unmapped: u64 = 0,

    pub fn note(self: *Census, classification: Classification) void {
        switch (classification) {
            .deliberate_trap => self.deliberate_traps +|= 1,
            .page_granularity_artifact => self.granularity_artifacts +|= 1,
            .genuine_violation => self.genuine_violations +|= 1,
            .unmapped => self.unmapped +|= 1,
        }
    }

    pub fn total(self: Census) u64 {
        return self.deliberate_traps + self.granularity_artifacts +
            self.genuine_violations + self.unmapped;
    }
};

test "the census separates the runtime's refusals from the guest's" {
    var census = Census{};
    census.note(.deliberate_trap);
    census.note(.deliberate_trap);
    census.note(.page_granularity_artifact);
    census.note(.genuine_violation);
    try std.testing.expectEqual(@as(u64, 4), census.total());
    try std.testing.expectEqual(@as(u64, 2), census.deliberate_traps);
    try std.testing.expectEqual(@as(u64, 1), census.granularity_artifacts);
}
