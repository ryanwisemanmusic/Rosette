//! Which host bytes a guest range really is, and what a fault at a host
//! granule is allowed to say about a guest page.
//!
//! The defect this exists for
//! --------------------------
//! macOS on Apple silicon uses 16 KiB pages. The guest assumes 4 KiB
//! protection pages. Xenia's mac memory path widens host writable ranges to
//! cope, which is necessary and means one guest protection operation can cover
//! three neighbouring guest pages it was never asked about.
//!
//! The consequences are not logging noise:
//!
//! * an unrelated guest page becomes writable, or stays writable;
//! * a write-watch attributes a neighbour's write to the wrong object;
//! * a protected kernel synchronization object is modified through an alias;
//! * ring, command buffer, shader, texture and frontbuffer ranges share one
//!   protection granule;
//! * a generation or invalidation is charged to the wrong guest page;
//! * a fault is raised at an address the guest instruction did not touch.
//!
//! So a fault that lands on a granule covering more than one owner is
//! `coarse` — it names the granule and refuses to name the guest page. That is
//! a weaker statement and a true one, and it is the difference between finding
//! an aliasing bug and chasing the wrong object for an afternoon.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const Address = bridge.contract.Address;

/// Host page granule on the platforms this runs on. Stated rather than
/// queried so a test can reason about the coarse case directly.
pub const host_granule_bytes: u32 = 16 * 1024;
pub const guest_page_bytes: u32 = 4 * 1024;

/// What a range is for. Two owners sharing one host granule is the condition
/// that makes attribution unsafe.
pub const Owner = enum(u8) {
    ring = 0,
    command_buffer = 1,
    edram_resolve_destination = 2,
    shader_storage = 3,
    texture_storage = 4,
    kernel_object = 5,
    frontbuffer = 6,
    title_general = 7,
    unknown = 255,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .ring => "ring",
            .command_buffer => "command-buffer",
            .edram_resolve_destination => "edram-resolve-destination",
            .shader_storage => "shader-storage",
            .texture_storage => "texture-storage",
            .kernel_object => "kernel-object",
            .frontbuffer => "frontbuffer",
            .title_general => "title-general",
            .unknown => "unknown",
        };
    }

    /// Whether a coarse-grained write into this owner's range can corrupt
    /// something the run depends on. A kernel object modified through a
    /// neighbour's protection change is the worst case in this list.
    pub fn corruptionIsCritical(self: Owner) bool {
        return switch (self) {
            .ring, .kernel_object, .command_buffer, .frontbuffer => true,
            else => false,
        };
    }
};

/// Which route an access took. A read through the physical alias and a read
/// through the virtual one can see different bytes, and a report that does not
/// say which was used cannot explain the difference.
pub const Route = enum(u8) {
    guest_virtual = 0,
    guest_physical = 1,
    host_direct = 2,
    unknown = 255,

    pub fn label(self: Route) []const u8 {
        return switch (self) {
            .guest_virtual => "guest-virtual",
            .guest_physical => "guest-physical",
            .host_direct => "host-direct",
            .unknown => "unknown",
        };
    }
};

/// One mapped range.
pub const Mapping = struct {
    owner: Owner = .unknown,
    guest_virtual: u32 = 0,
    guest_physical: u32 = 0,
    host: u64 = 0,
    bytes: u32 = 0,
    /// Bumped whenever the contents are known to have changed. A generation
    /// charged to the wrong page is how an invalidation misses.
    generation: u64 = 0,
    /// Whether this is a deliberate second view of the same physical bytes.
    intentional_alias: bool = false,
    writable: bool = false,

    pub fn endGuestVirtual(self: Mapping) u32 {
        return self.guest_virtual +| self.bytes;
    }

    /// The host granule this range starts in, and the one it ends in.
    pub fn firstGranule(self: Mapping) u64 {
        return self.host / host_granule_bytes;
    }

    pub fn lastGranule(self: Mapping) u64 {
        if (self.bytes == 0) return self.firstGranule();
        return (self.host + self.bytes - 1) / host_granule_bytes;
    }

    pub fn sharesGranuleWith(self: Mapping, other: Mapping) bool {
        if (self.host == 0 or other.host == 0) return false;
        return self.firstGranule() <= other.lastGranule() and
            other.firstGranule() <= self.lastGranule();
    }

    /// Whether the two describe the same physical bytes through different host
    /// mappings. That is legitimate when declared and a defect when not.
    pub fn aliasesPhysical(self: Mapping, other: Mapping) bool {
        if (self.guest_physical == 0 or other.guest_physical == 0) return false;
        if (self.guest_physical != other.guest_physical) return false;
        return self.host != other.host;
    }
};

/// How much a protection event is worth.
pub const Attribution = enum(u8) {
    /// The granule holds one owner. The event names a guest page.
    exact,
    /// The granule holds more than one owner. The event names the granule and
    /// nothing finer.
    coarse,
    /// No mapping claims the address.
    unmapped,

    pub fn label(self: Attribution) []const u8 {
        return switch (self) {
            .exact => "exact",
            .coarse => "COARSE",
            .unmapped => "UNMAPPED",
        };
    }

    pub fn describe(self: Attribution) []const u8 {
        return switch (self) {
            .exact => "the host granule holds one owner, so this event names a guest page and the object that owns it",
            .coarse => "the host granule covers more than one owner. The event names the granule and must not be used as exact causality: on a 16 KiB host page a guest protection change covers three neighbouring 4 KiB pages it was never asked about, and a write-watch here can charge a neighbour's write to the wrong object",
            .unmapped => "no mapping claims this address. The event is real and nothing here can say whose it is",
        };
    }

    /// Whether this event may be quoted as "this object was written".
    pub fn namesAnObject(self: Attribution) bool {
        return self == .exact;
    }
};

pub const max_mappings: usize = 32;

pub const Summary = struct {
    mappings: usize = 0,
    dropped: u64 = 0,
    /// Granules shared by more than one owner. Every one is a place where a
    /// protection event cannot be attributed.
    shared_granules: u64 = 0,
    /// The worst case: a shared granule where one of the owners is critical.
    critical_shared_granules: u64 = 0,
    undeclared_aliases: u64 = 0,
    events: u64 = 0,
    exact_events: u64 = 0,
    coarse_events: u64 = 0,
    unmapped_events: u64 = 0,

    pub fn anyDefect(self: Summary) bool {
        return self.critical_shared_granules != 0 or self.undeclared_aliases != 0;
    }
};

pub const Ledger = struct {
    mappings: [max_mappings]Mapping = [_]Mapping{.{}} ** max_mappings,
    count: usize = 0,
    dropped: u64 = 0,
    undeclared_aliases: u64 = 0,
    events: u64 = 0,
    exact_events: u64 = 0,
    coarse_events: u64 = 0,
    unmapped_events: u64 = 0,

    /// Declare a mapping. An undeclared alias — two mappings of the same
    /// physical bytes through different host addresses, neither marked
    /// intentional — is recorded, because the two will drift and nothing else
    /// in the system would notice.
    pub fn map(self: *Ledger, mapping: Mapping) ?*Mapping {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const existing = self.mappings[index];
            if (existing.aliasesPhysical(mapping) and
                !(existing.intentional_alias or mapping.intentional_alias))
            {
                self.undeclared_aliases +|= 1;
            }
        }
        if (self.count >= max_mappings) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.mappings[self.count];
        self.count += 1;
        slot.* = mapping;
        return slot;
    }

    pub fn retained(self: *const Ledger) []const Mapping {
        return self.mappings[0..self.count];
    }

    /// Which mappings a host address falls in.
    pub fn ownersAtGranule(self: *const Ledger, host: u64, out: []Owner) []Owner {
        const granule = host / host_granule_bytes;
        var written: usize = 0;
        for (self.retained()) |mapping| {
            if (mapping.host == 0) continue;
            if (granule < mapping.firstGranule() or granule > mapping.lastGranule()) continue;
            var duplicate = false;
            for (out[0..written]) |seen| {
                if (seen == mapping.owner) duplicate = true;
            }
            if (duplicate) continue;
            if (written >= out.len) break;
            out[written] = mapping.owner;
            written += 1;
        }
        return out[0..written];
    }

    /// Classify a protection or write-watch event at a host address.
    pub fn attribute(self: *Ledger, host: u64) Attribution {
        self.events +|= 1;
        var owners: [max_mappings]Owner = undefined;
        const found = self.ownersAtGranule(host, &owners);
        if (found.len == 0) {
            self.unmapped_events +|= 1;
            return .unmapped;
        }
        if (found.len > 1) {
            self.coarse_events +|= 1;
            return .coarse;
        }
        self.exact_events +|= 1;
        return .exact;
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{
            .mappings = self.count,
            .dropped = self.dropped,
            .undeclared_aliases = self.undeclared_aliases,
            .events = self.events,
            .exact_events = self.exact_events,
            .coarse_events = self.coarse_events,
            .unmapped_events = self.unmapped_events,
        };
        var left: usize = 0;
        while (left < self.count) : (left += 1) {
            var right: usize = left + 1;
            while (right < self.count) : (right += 1) {
                const a = self.mappings[left];
                const b = self.mappings[right];
                if (a.owner == b.owner) continue;
                if (!a.sharesGranuleWith(b)) continue;
                out.shared_granules +|= 1;
                if (a.owner.corruptionIsCritical() or b.owner.corruptionIsCritical()) {
                    out.critical_shared_granules +|= 1;
                }
            }
        }
        return out;
    }

    /// The audit's self-test: two adjacent guest pages with different owners,
    /// and changing one must not produce an event the other's page is charged
    /// with. Returns true when the two land in different host granules, which
    /// is the only condition under which the guarantee holds.
    pub fn adjacentPagesAreSeparable(self: *const Ledger, first_host: u64, second_host: u64) bool {
        _ = self;
        return (first_host / host_granule_bytes) != (second_host / host_granule_bytes);
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.mappings;
        hash = hash *% 31 +% totals.shared_granules;
        hash = hash *% 31 +% totals.undeclared_aliases;
        hash = hash *% 31 +% totals.coarse_events;
        return hash;
    }
};

// The 16 KiB-versus-4 KiB hazard, exactly. Four guest pages share one host
// granule, so a write-watch there cannot name which of them was written.
test "two owners in one host granule make every event there coarse" {
    var ledger = Ledger{};
    // Two 4 KiB guest pages at host offsets 0 and 4096 inside one 16 KiB
    // granule. This is the arrangement the widened host protection produces,
    // and it is the reason the granule is the finest thing an event can name.
    _ = ledger.map(.{ .owner = .ring, .guest_physical = 0x1FC9_B000, .host = 0x4_6F12_8000, .bytes = 0x1000 }).?;
    _ = ledger.map(.{ .owner = .kernel_object, .guest_physical = 0x1FC9_C000, .host = 0x4_6F12_9000, .bytes = 0x1000 }).?;

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), totals.shared_granules);
    try std.testing.expectEqual(@as(u64, 1), totals.critical_shared_granules);
    try std.testing.expect(totals.anyDefect());

    const attribution = ledger.attribute(0x4_6F12_9800);
    try std.testing.expectEqual(Attribution.coarse, attribution);
    try std.testing.expect(!attribution.namesAnObject());
    try std.testing.expect(std.mem.indexOf(u8, attribution.describe(), "wrong object") != null);
}

test "one owner in a granule makes an event name a page" {
    var ledger = Ledger{};
    _ = ledger.map(.{ .owner = .ring, .guest_physical = 0x1FC9_B000, .host = 0x4_6F12_8000, .bytes = 0x1000 }).?;
    const attribution = ledger.attribute(0x4_6F12_8100);
    try std.testing.expectEqual(Attribution.exact, attribution);
    try std.testing.expect(attribution.namesAnObject());
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().exact_events);
}

test "an address nothing maps is unattributed rather than guessed" {
    var ledger = Ledger{};
    _ = ledger.map(.{ .owner = .ring, .host = 0x1_0000, .bytes = 0x1000 }).?;
    const attribution = ledger.attribute(0x9_0000);
    try std.testing.expectEqual(Attribution.unmapped, attribution);
    try std.testing.expect(!attribution.namesAnObject());
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().unmapped_events);
}

test "an undeclared alias of the same physical bytes is recorded" {
    var ledger = Ledger{};
    _ = ledger.map(.{ .owner = .ring, .guest_physical = 0x1FC9_B000, .host = 0x4_6F12_B000, .bytes = 0x1000 }).?;
    _ = ledger.map(.{ .owner = .ring, .guest_physical = 0x1FC9_B000, .host = 0x4_4F12_B000, .bytes = 0x1000 }).?;
    try std.testing.expectEqual(@as(u64, 1), ledger.undeclared_aliases);
    try std.testing.expect(ledger.summary().anyDefect());
}

test "a declared alias is legitimate and not a finding" {
    var ledger = Ledger{};
    _ = ledger.map(.{ .owner = .ring, .guest_physical = 0x1FC9_B000, .host = 0x4_6F12_B000, .bytes = 0x1000 }).?;
    _ = ledger.map(.{
        .owner = .ring,
        .guest_physical = 0x1FC9_B000,
        .host = 0x4_4F12_B000,
        .bytes = 0x1000,
        .intentional_alias = true,
    }).?;
    try std.testing.expectEqual(@as(u64, 0), ledger.undeclared_aliases);
    // Same owner, so the shared-granule check does not fire either.
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().shared_granules);
}

// The audit's acceptance self-test.
test "adjacent guest pages are separable only in different host granules" {
    const ledger = Ledger{};
    // Two 4 KiB guest pages inside one 16 KiB host granule: not separable.
    try std.testing.expect(!ledger.adjacentPagesAreSeparable(0x4_0000, 0x4_1000));
    // A full granule apart: separable.
    try std.testing.expect(ledger.adjacentPagesAreSeparable(0x4_0000, 0x4_4000));
    try std.testing.expectEqual(@as(u32, 16 * 1024), host_granule_bytes);
    try std.testing.expectEqual(@as(u32, 4 * 1024), guest_page_bytes);
}

test "two non-critical owners sharing a granule is still unattributable" {
    var ledger = Ledger{};
    _ = ledger.map(.{ .owner = .texture_storage, .host = 0x8000, .bytes = 0x1000 }).?;
    _ = ledger.map(.{ .owner = .shader_storage, .host = 0x9000, .bytes = 0x1000 }).?;
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), totals.shared_granules);
    try std.testing.expectEqual(@as(u64, 0), totals.critical_shared_granules);
    try std.testing.expect(!totals.anyDefect());
    try std.testing.expectEqual(Attribution.coarse, ledger.attribute(0x8500));
}

test "the mapping table is bounded and every owner and route is named" {
    var ledger = Ledger{};
    var index: usize = 0;
    while (index < max_mappings + 2) : (index += 1) {
        _ = ledger.map(.{ .owner = .title_general, .host = 0x100000 + index * host_granule_bytes, .bytes = 16 });
    }
    try std.testing.expectEqual(max_mappings, ledger.retained().len);
    try std.testing.expectEqual(@as(u64, 2), ledger.dropped);

    inline for (@typeInfo(Owner).@"enum".fields) |field| {
        const which: Owner = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(Route).@"enum".fields) |field| {
        const which: Route = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
}
