//! What counts as a "guest address", derived from observation rather than
//! asserted from a constant.
//!
//! The predicate this replaces was `low >= 0x80000000 and low < 0xA0000000`,
//! with module names hardcoded to `xboxkrnl.exe` / `xam.xex` / `<game module>`.
//! One owner, so no disagreement — but the knowledge was in the wrong place.
//! Ten call sites gate recovery decisions on it, and every one of them silently
//! reclassifies if a guest maps outside the assumed range. The failure then
//! surfaces somewhere else entirely, which is the pattern this codebase keeps
//! hitting.
//!
//! Two things here are genuinely architectural and stay as rules:
//!
//!   * **Canonical form.** A 32-bit guest address appearing in a 64-bit
//!     register is either zero-extended or sign-extended. A host pointer whose
//!     low 32 bits happen to land in the window (`0x1082582cc8`) is not a guest
//!     address. This is x86-64 semantics, not Xenia's.
//!
//!   * **Window membership.** Whether an address is inside the guest's mapped
//!     region is a question about the mapped region — so it is answered from
//!     the mappings, not from a literal.
//!
//! Everything else is learned. Until evidence arrives the model reports that it
//! is running on its bootstrap default, so a run can never quietly depend on a
//! guess.

const std = @import("std");

/// Where the current window came from. Printed alongside any classification so
/// a reader can tell a derived answer from a defaulted one.
pub const Source = enum {
    /// No observation yet; the bootstrap range is in use.
    bootstrap_default,
    /// Derived from a large guest reservation observed at map time.
    observed_reservation,
    /// Explicitly supplied by a loader that knows the layout.
    declared,

    pub fn derived(self: Source) bool {
        return self != .bootstrap_default;
    }
};

/// Bootstrap range, used only until a mapping is observed. Kept because a
/// recovery consulted before the first mapping must answer *something*, and
/// answering "everything is outside the guest" would let recoveries fire on
/// addresses they should refuse. It is never silently authoritative: `Source`
/// travels with every answer.
pub const bootstrap_base: u32 = 0x8000_0000;
pub const bootstrap_end: u32 = 0xA000_0000;

/// A guest address in canonical form, or null when the value cannot be one.
///
/// Rejects genuine 64-bit host pointers whose low half falls in range, and
/// normalises the sign-extended form so callers compare like with like.
pub fn canonical32(address: u64) ?u32 {
    const high: u32 = @truncate(address >> 32);
    if (high != 0 and high != 0xFFFF_FFFF) return null;
    return @truncate(address);
}

pub const Region = struct {
    base: u64,
    size: u64,
    executable: bool = false,
    writable: bool = false,

    pub fn contains(self: Region, address: u64) bool {
        return address >= self.base and address - self.base < self.size;
    }

    pub fn end(self: Region) u64 {
        return self.base +| self.size;
    }
};

pub const Classification = struct {
    /// The value is a canonical 32-bit address inside the guest window.
    in_window: bool = false,
    /// Canonical low half, when the value could be a guest address at all.
    canonical: ?u32 = null,
    /// The observed region containing the address, when one does.
    region: ?Region = null,
    source: Source = .bootstrap_default,

    /// The classification rests on a derived window, not the bootstrap default.
    pub fn trustworthy(self: Classification) bool {
        return self.source.derived();
    }
};

pub const max_regions = 32;

pub const Model = struct {
    base: u64 = bootstrap_base,
    end: u64 = bootstrap_end,
    source: Source = .bootstrap_default,
    regions: [max_regions]Region = undefined,
    region_count: usize = 0,
    /// Observations that did not widen the window, retained for reporting.
    ignored_observations: u64 = 0,

    /// Smallest reservation that can define the guest window. A guest RAM
    /// window is measured in hundreds of megabytes; small mappings are heap or
    /// code-cache pages and must not redefine it.
    pub const min_window_bytes: u64 = 16 * 1024 * 1024;

    pub fn declare(self: *Model, base: u64, end: u64) void {
        if (end <= base) return;
        self.base = base;
        self.end = end;
        self.source = .declared;
    }

    /// Record a mapping. Only canonical, sufficiently large regions may define
    /// the window; every mapping is retained as a region for containment
    /// reporting, which is what replaces the hardcoded module names.
    pub fn observe(self: *Model, region: Region) void {
        if (self.region_count < self.regions.len) {
            self.regions[self.region_count] = region;
            self.region_count += 1;
        }
        const low = canonical32(region.base) orelse {
            self.ignored_observations +|= 1;
            return;
        };
        if (region.size < min_window_bytes) {
            self.ignored_observations +|= 1;
            return;
        }
        // An executable reservation is a code cache, not guest RAM, and it is
        // routinely large enough to pass the size gate. Part of what the window
        // predicate exists to decide is whether a return address belongs to the
        // *generated host code* or to the guest — `host_return_not_guest` in the
        // dispatch transducer is exactly that question — so admitting the
        // generated-code region into the window would erase the distinction the
        // window is consulted for. Retained above as a region for containment
        // reporting; never allowed to widen.
        if (region.executable) {
            self.ignored_observations +|= 1;
            return;
        }
        const region_end: u64 = @as(u64, low) +| region.size;
        if (self.source == .declared) return;
        if (self.source == .bootstrap_default) {
            self.base = low;
            self.end = region_end;
            self.source = .observed_reservation;
            return;
        }
        // Widen to cover every observed guest reservation.
        if (low < self.base) self.base = low;
        if (region_end > self.end) self.end = region_end;
    }

    pub fn classify(self: *const Model, address: u64) Classification {
        const low = canonical32(address) orelse return .{ .source = self.source };
        var result = Classification{
            .canonical = low,
            .source = self.source,
            .in_window = low >= self.base and low < self.end,
        };
        var index: usize = 0;
        while (index < self.region_count) : (index += 1) {
            const region = self.regions[index];
            if (region.contains(low)) {
                result.region = region;
                break;
            }
        }
        return result;
    }

    pub fn isGuestAddress(self: *const Model, address: u64) bool {
        return self.classify(address).in_window;
    }
};

test "canonical form rejects host pointers that alias the window" {
    // 0x1082582cc8's low half is inside the window, but the high half makes it
    // a real 64-bit host pointer. Treating it as guest would let a dispatch
    // recovery skip a genuine host target.
    try std.testing.expectEqual(@as(?u32, null), canonical32(0x1082582cc8));
    try std.testing.expectEqual(@as(u32, 0x82582cc8), canonical32(0x82582cc8).?);
    try std.testing.expectEqual(@as(u32, 0x8313e528), canonical32(0xffffffff8313e528).?);
}

test "bootstrap answers are marked untrustworthy until evidence arrives" {
    var model = Model{};
    const before = model.classify(0x82582cc8);
    try std.testing.expect(before.in_window);
    try std.testing.expect(!before.trustworthy());

    model.observe(.{ .base = 0x8000_0000, .size = 0x2000_0000 });
    const after = model.classify(0x82582cc8);
    try std.testing.expect(after.in_window);
    try std.testing.expect(after.trustworthy());
    try std.testing.expectEqual(Source.observed_reservation, after.source);
}

test "a guest that maps outside the assumed range is classified correctly" {
    // The whole point: a layout the hardcoded constant would have rejected.
    var model = Model{};
    model.observe(.{ .base = 0x4000_0000, .size = 0x2000_0000 });
    try std.testing.expect(model.isGuestAddress(0x4100_0000));
    try std.testing.expect(!model.isGuestAddress(0x8258_2cc8));
    try std.testing.expectEqual(@as(u64, 0x4000_0000), model.base);
    try std.testing.expectEqual(@as(u64, 0x6000_0000), model.end);
}

test "small mappings never redefine the window" {
    var model = Model{};
    model.observe(.{ .base = 0x8000_0000, .size = 0x2000_0000 });
    const base_before = model.base;
    const end_before = model.end;
    // A code-cache page must not widen the guest RAM window.
    model.observe(.{ .base = 0x1000, .size = 0x4000, .executable = true });
    try std.testing.expectEqual(base_before, model.base);
    try std.testing.expectEqual(end_before, model.end);
    try std.testing.expectEqual(@as(u64, 1), model.ignored_observations);
}

test "multiple guest reservations widen rather than replace" {
    var model = Model{};
    model.observe(.{ .base = 0x8000_0000, .size = 0x1000_0000 });
    model.observe(.{ .base = 0x9000_0000, .size = 0x1000_0000 });
    try std.testing.expectEqual(@as(u64, 0x8000_0000), model.base);
    try std.testing.expectEqual(@as(u64, 0xA000_0000), model.end);
    try std.testing.expect(model.isGuestAddress(0x9500_0000));
}

// The reconciliation that had to happen before the ten decision sites could be
// moved onto the model. Under Xenia the JIT code cache is a 256 MB executable
// reservation immediately above the 512 MB guest RAM window, so a model that
// widened on it would answer "guest" for every generated-code address — and
// `host_return_not_guest`, which decides whether an abandoned frame may be
// returned to its host caller, would start refusing every legitimate frame.
test "an executable reservation is a code cache and never widens guest RAM" {
    var model = Model{};
    model.observe(.{ .base = 0x8000_0000, .size = 0x2000_0000, .writable = true });
    try std.testing.expectEqual(Source.observed_reservation, model.source);

    model.observe(.{ .base = 0xA000_0000, .size = 0x1000_0000, .executable = true });
    try std.testing.expectEqual(@as(u64, 0x8000_0000), model.base);
    try std.testing.expectEqual(@as(u64, 0xA000_0000), model.end);
    try std.testing.expect(!model.isGuestAddress(0xA005_9878));
    try std.testing.expectEqual(@as(u64, 1), model.ignored_observations);

    // Still retained for containment reporting — ignored for the window is not
    // ignored for the record.
    const classified = model.classify(0xA005_9878);
    try std.testing.expect(!classified.in_window);
    try std.testing.expect(classified.region != null);
    try std.testing.expect(classified.region.?.executable);
}

// The observed layout, in order, as `noteGuestMapping` now feeds it. The
// derived answer must land exactly on the bootstrap range: that equality is
// what makes moving the decision sites onto the model a no-op rather than a
// reclassification.
test "the observed Xenia layout derives exactly the bootstrap window" {
    var model = Model{};
    // Guest RAM: 512 MB at 0x80000000, read/write.
    model.observe(.{ .base = 0x8000_0000, .size = 0x2000_0000, .writable = true });
    // JIT code cache: 256 MB at 0xA0000000, executable.
    model.observe(.{ .base = 0xA000_0000, .size = 0x1000_0000, .executable = true });
    // Host-side file views far above the 32-bit window.
    model.observe(.{ .base = 0x3_4D7D_0000, .size = 0x2000_0000, .writable = true });
    model.observe(.{ .base = 0x4_0D7D_0000, .size = 0x2000_0000, .writable = true });

    try std.testing.expectEqual(Source.observed_reservation, model.source);
    try std.testing.expectEqual(@as(u64, bootstrap_base), model.base);
    try std.testing.expectEqual(@as(u64, bootstrap_end), model.end);
    try std.testing.expect(model.isGuestAddress(0x8258_2cc8));
    try std.testing.expect(!model.isGuestAddress(0xA005_9878));
    try std.testing.expect(!model.isGuestAddress(0x13fa70));
}

test "a declared layout wins over later observations" {
    var model = Model{};
    model.declare(0x2000_0000, 0x3000_0000);
    model.observe(.{ .base = 0x8000_0000, .size = 0x2000_0000 });
    try std.testing.expectEqual(Source.declared, model.source);
    try std.testing.expect(model.isGuestAddress(0x2500_0000));
    try std.testing.expect(!model.isGuestAddress(0x8258_2cc8));
}

test "containment reports the observed region instead of a hardcoded name" {
    var model = Model{};
    model.observe(.{ .base = 0x8000_0000, .size = 0x2000_0000, .writable = true });
    const found = model.classify(0x8258_2cc8);
    try std.testing.expect(found.region != null);
    try std.testing.expectEqual(@as(u64, 0x8000_0000), found.region.?.base);
    try std.testing.expect(found.region.?.writable);
}
