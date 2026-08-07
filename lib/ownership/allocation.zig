//! Who owns a piece of guest memory, and therefore who may release it.
//!
//! Several allocators hand out guest addresses: the forwarded libc heap, the
//! runtime's own bump allocator, guest `mmap`, the workload's guest-physical
//! heaps, and native allocations the runtime only observes. They share one
//! address space, and the only thing that decided which of them a `free` belonged
//! to was **the address**.
//!
//! An address is not an owner. Two allocators issuing from the same range agree
//! about every address in it and disagree about which of them handed it out, and
//! the disagreement is invisible until a release: the forwarder is asked to free
//! something it never allocated, reports "never handed out by this forwarder",
//! and absorbs it. Observed: eight such frees inside the forwarder's own arena
//! before the workload had finished starting.
//!
//! Absorbing is the dangerous part. The block stays live in whichever allocator
//! *does* own it, the caller believes it is freed, and the resulting corruption
//! surfaces somewhere else entirely — which is the failure mode this whole
//! library exists to prevent.
//!
//! So provenance is recorded at allocation and consulted at release. A release
//! routed to the owner is correct however the ranges overlap; a release with no
//! recorded owner is *reported as unowned* rather than guessed at from its
//! address.

const std = @import("std");

/// Who issued an address. Not a memory *kind* — two allocators can both hand out
/// ordinary read/write guest memory and still be different owners.
pub const Owner = enum(u8) {
    /// No record. Never treat as a licence to release: it means the runtime
    /// does not know, which is the finding.
    unknown,
    /// The forwarded libc heap (`malloc`/`calloc`/`realloc`).
    forwarded_heap,
    /// The runtime's own bump allocator for guest-visible structures.
    runtime_internal,
    /// A guest `mmap` region.
    guest_mmap,
    /// The workload's own guest-physical heap. The runtime models the mapping
    /// but the workload maintains the page table, so it owns the lifetime.
    guest_physical,
    /// Memory the runtime observed but did not issue — a native allocation
    /// reached through a shim, for instance.
    external,

    /// Whether this runtime's forwarder is entitled to release it.
    pub fn releasableByForwarder(self: Owner) bool {
        return self == .forwarded_heap;
    }
};

pub const Record = struct {
    base: u64 = 0,
    size: u64 = 0,
    owner: Owner = .unknown,
    /// Guest instruction that requested the allocation, when known.
    instruction_address: u64 = 0,

    pub fn contains(self: Record, address: u64) bool {
        return self.size != 0 and address >= self.base and address - self.base < self.size;
    }
};

/// What a release should do.
pub const Disposition = enum(u8) {
    /// The forwarder owns it; release normally.
    release,
    /// A different allocator owns it. Do not release, and say which.
    foreign_owner,
    /// Not the base of a known allocation but inside one — an interior pointer.
    interior,
    /// No owner recorded at all.
    unowned,
};

pub const Verdict = struct {
    disposition: Disposition = .unowned,
    owner: Owner = .unknown,
    record: Record = .{},
};

/// Bounded. A registry that retains every allocation a run ever made is the
/// heap a second time; this tracks the ones whose ownership is *contested* —
/// seeded on release disagreements and on explicit declarations — which is a
/// far smaller set and the only one the routing decision needs.
pub const max_records: usize = 128;

pub const Registry = struct {
    records: [max_records]Record = [_]Record{.{}} ** max_records,
    count: usize = 0,
    next: usize = 0,
    declarations: u64 = 0,
    evictions: u64 = 0,
    /// Releases routed away from the forwarder because another allocator owned
    /// the address. Each of these was previously absorbed silently.
    foreign_releases: u64 = 0,
    /// Releases with no recorded owner.
    unowned_releases: u64 = 0,
    interior_releases: u64 = 0,

    pub fn declare(self: *Registry, base: u64, size: u64, owner: Owner, instruction_address: u64) void {
        if (size == 0 or owner == .unknown) return;
        self.declarations +|= 1;
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (self.records[index].base != base) continue;
            self.records[index] = .{
                .base = base,
                .size = size,
                .owner = owner,
                .instruction_address = instruction_address,
            };
            return;
        }
        if (self.count == self.records.len) self.evictions +|= 1;
        self.records[self.next] = .{
            .base = base,
            .size = size,
            .owner = owner,
            .instruction_address = instruction_address,
        };
        self.next = (self.next + 1) % self.records.len;
        if (self.count < self.records.len) self.count += 1;
    }

    pub fn lookup(self: *const Registry, address: u64) ?Record {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (self.records[index].base == address) return self.records[index];
        }
        return null;
    }

    pub fn containing(self: *const Registry, address: u64) ?Record {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (self.records[index].contains(address)) return self.records[index];
        }
        return null;
    }

    /// Decide what a release of `address` should do. `forwarder_owns` is the
    /// forwarder's own answer — it still knows its live set — and provenance is
    /// consulted only when the forwarder does not claim the address, which is
    /// exactly the case that used to be absorbed.
    pub fn route(self: *Registry, address: u64, forwarder_owns: bool) Verdict {
        if (address == 0) return .{ .disposition = .unowned };
        if (forwarder_owns) {
            return .{ .disposition = .release, .owner = .forwarded_heap };
        }
        if (self.lookup(address)) |record| {
            if (record.owner.releasableByForwarder()) {
                return .{ .disposition = .release, .owner = record.owner, .record = record };
            }
            self.foreign_releases +|= 1;
            return .{ .disposition = .foreign_owner, .owner = record.owner, .record = record };
        }
        if (self.containing(address)) |record| {
            self.interior_releases +|= 1;
            return .{ .disposition = .interior, .owner = record.owner, .record = record };
        }
        self.unowned_releases +|= 1;
        return .{ .disposition = .unowned };
    }
};

test "the forwarder's own live set still decides first" {
    var registry = Registry{};
    const verdict = registry.route(0x1000, true);
    try std.testing.expectEqual(Disposition.release, verdict.disposition);
    try std.testing.expectEqual(Owner.forwarded_heap, verdict.owner);
    try std.testing.expectEqual(@as(u64, 0), registry.unowned_releases);
}

// The case that was silently absorbed: an address inside the forwarder's arena
// that a different allocator issued. Routing by address would release it; routing
// by owner refuses and names the owner.
test "a foreign owner is named rather than absorbed" {
    var registry = Registry{};
    registry.declare(0x4717030, 0x100, .runtime_internal, 0xabc);
    const verdict = registry.route(0x4717030, false);
    try std.testing.expectEqual(Disposition.foreign_owner, verdict.disposition);
    try std.testing.expectEqual(Owner.runtime_internal, verdict.owner);
    try std.testing.expectEqual(@as(u64, 0xabc), verdict.record.instruction_address);
    try std.testing.expectEqual(@as(u64, 1), registry.foreign_releases);
}

test "an interior pointer is distinguished from a base" {
    var registry = Registry{};
    registry.declare(0x8000, 0x200, .guest_mmap, 0);
    const verdict = registry.route(0x8080, false);
    try std.testing.expectEqual(Disposition.interior, verdict.disposition);
    try std.testing.expectEqual(Owner.guest_mmap, verdict.owner);
    try std.testing.expectEqual(@as(u64, 0x8000), verdict.record.base);
    try std.testing.expectEqual(@as(u64, 1), registry.interior_releases);
}

test "an address with no recorded owner is reported, never guessed" {
    var registry = Registry{};
    const verdict = registry.route(0xdead0000, false);
    try std.testing.expectEqual(Disposition.unowned, verdict.disposition);
    try std.testing.expectEqual(Owner.unknown, verdict.owner);
    try std.testing.expectEqual(@as(u64, 1), registry.unowned_releases);
}

test "a redeclared base replaces its record instead of consuming a slot" {
    var registry = Registry{};
    registry.declare(0x2000, 0x10, .guest_mmap, 1);
    registry.declare(0x2000, 0x40, .guest_physical, 2);
    try std.testing.expectEqual(@as(usize, 1), registry.count);
    const record = registry.lookup(0x2000) orelse return error.TestFailed;
    try std.testing.expectEqual(Owner.guest_physical, record.owner);
    try std.testing.expectEqual(@as(u64, 0x40), record.size);
}

test "an owner the forwarder may release routes to release" {
    var registry = Registry{};
    registry.declare(0x3000, 0x10, .forwarded_heap, 0);
    // The forwarder lost track of it, but provenance says it is still ours.
    const verdict = registry.route(0x3000, false);
    try std.testing.expectEqual(Disposition.release, verdict.disposition);
    try std.testing.expectEqual(@as(u64, 0), registry.foreign_releases);
}

test "capacity is bounded and eviction is counted" {
    var registry = Registry{};
    var index: usize = 0;
    while (index < max_records) : (index += 1) {
        registry.declare(0x10000 + index * 0x100, 0x10, .guest_mmap, 0);
    }
    try std.testing.expectEqual(max_records, registry.count);
    try std.testing.expectEqual(@as(u64, 0), registry.evictions);
    registry.declare(0x9000_0000, 0x10, .guest_mmap, 0);
    try std.testing.expectEqual(@as(u64, 1), registry.evictions);
    try std.testing.expect(registry.lookup(0x9000_0000) != null);
}

test "a zero-size or unknown-owner declaration is refused" {
    var registry = Registry{};
    registry.declare(0x1000, 0, .guest_mmap, 0);
    registry.declare(0x1000, 0x10, .unknown, 0);
    try std.testing.expectEqual(@as(usize, 0), registry.count);
    try std.testing.expectEqual(@as(u64, 0), registry.declarations);
}
