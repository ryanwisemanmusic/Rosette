//! Which fields of a guest structure the translation actually touches.
//!
//! A dispatch died on `mov rbx,[rsi+0x130]` returning zero. Everything about
//! *that instruction* is now known: the block is reconstructed, the operand
//! resolved, the value re-read. What remains unknown is a different kind of
//! question — not "what happened here" but "what never happened anywhere".
//!
//! A field that is read and never written is an emulation gap: some store the
//! guest expected is missing. A field that is read *and* written is a value
//! problem: the store ran and produced the wrong thing. These need opposite
//! investigations, and no amount of detail about the faulting instruction
//! distinguishes them, because the evidence is an *absence* elsewhere in the
//! run.
//!
//! So this records the shape of access itself: for each structure base and
//! offset that generated code touches, whether it was read, written, or both.
//! At a fault it can then say "this offset was read 41 times and written never,
//! while its neighbours at +0x128 and +0x138 were both written" — which turns
//! "probably an emulation gap" into a measurement with a neighbourhood.
//!
//! Bounded on purpose: a fixed number of bases and offsets, with overflow
//! counted. An unbounded profiler is a memory leak with a nice name.

const std = @import("std");

pub const Access = packed struct {
    read: bool = false,
    written: bool = false,

    pub fn readOnly(self: Access) bool {
        return self.read and !self.written;
    }
};

pub const Field = struct {
    offset: u32 = 0,
    reads: u32 = 0,
    writes: u32 = 0,
    used: bool = false,

    pub fn access(self: Field) Access {
        return .{ .read = self.reads != 0, .written = self.writes != 0 };
    }
};

pub const max_bases: usize = 4;
pub const max_fields: usize = 64;
/// Offsets beyond this are array indexing, not structure fields.
pub const max_offset: u32 = 0x1000;

pub const Base = struct {
    address: u64 = 0,
    used: bool = false,
    fields: [max_fields]Field = [_]Field{.{}} ** max_fields,
    field_count: usize = 0,
    /// Distinct offsets that arrived after the field table filled.
    field_overflows: u64 = 0,

    /// Direct-mapped slot for an offset. O(1) rather than a linear scan.
    ///
    /// This runs on every generated-code memory operand — tens of millions of
    /// times — so a scan of up to `max_fields` entries per access is a
    /// wall-clock cost the run cannot pay. Structure fields are 8-byte spaced,
    /// so indexing on `offset >> 3` distributes them without clustering.
    ///
    /// Collisions are *counted and refused*, never silently merged: two
    /// different offsets sharing a slot would combine their read/write counts
    /// and could report a field as written when its neighbour was.
    fn slotIndex(offset: u32) usize {
        return @as(usize, (offset >> 3)) & (max_fields - 1);
    }

    fn findConst(self: *const Base, offset: u32) ?*const Field {
        const slot = &self.fields[slotIndex(offset)];
        if (!slot.used or slot.offset != offset) return null;
        return slot;
    }

    fn obtain(self: *Base, offset: u32) ?*Field {
        const slot = &self.fields[slotIndex(offset)];
        if (slot.used) {
            if (slot.offset == offset) return slot;
            self.field_overflows +|= 1;
            return null;
        }
        slot.* = .{ .offset = offset, .used = true };
        self.field_count += 1;
        return slot;
    }
};

pub const Profile = struct {
    bases: [max_bases]Base = [_]Base{.{}} ** max_bases,
    base_count: usize = 0,
    base_overflows: u64 = 0,

    fn baseFor(self: *Profile, address: u64) ?*Base {
        var index: usize = 0;
        while (index < self.base_count) : (index += 1) {
            if (self.bases[index].address == address) return &self.bases[index];
        }
        if (self.base_count == self.bases.len) {
            self.base_overflows +|= 1;
            return null;
        }
        const slot = &self.bases[self.base_count];
        slot.* = .{ .address = address, .used = true };
        self.base_count += 1;
        return slot;
    }

    fn baseForConst(self: *const Profile, address: u64) ?*const Base {
        var index: usize = 0;
        while (index < self.base_count) : (index += 1) {
            if (self.bases[index].address == address) return &self.bases[index];
        }
        return null;
    }

    pub fn note(self: *Profile, base_address: u64, offset: u64, is_write: bool) void {
        if (base_address == 0) return;
        if (offset == 0 or offset > max_offset) return;
        const base = self.baseFor(base_address) orelse return;
        const field = base.obtain(@intCast(offset)) orelse return;
        if (is_write) field.writes +|= 1 else field.reads +|= 1;
    }

    pub fn lookup(self: *const Profile, base_address: u64, offset: u64) ?Field {
        const base = self.baseForConst(base_address) orelse return null;
        if (offset > max_offset) return null;
        const field = base.findConst(@intCast(offset)) orelse return null;
        return field.*;
    }

    /// Fields adjacent to `offset` within `radius` bytes, for reporting the
    /// neighbourhood of a suspicious one. Writes into `out`, returns the count.
    pub fn neighbours(
        self: *const Profile,
        base_address: u64,
        offset: u64,
        radius: u64,
        out: []Field,
    ) usize {
        const base = self.baseForConst(base_address) orelse return 0;
        var written: usize = 0;
        var index: usize = 0;
        while (index < base.fields.len and written < out.len) : (index += 1) {
            const field = base.fields[index];
            if (!field.used) continue;
            const delta = if (field.offset > offset) field.offset - offset else offset - field.offset;
            if (delta <= radius) {
                out[written] = field;
                written += 1;
            }
        }
        return written;
    }
};

test "a field read but never written is distinguishable from one that is both" {
    var profile = Profile{};
    var i: usize = 0;
    while (i < 41) : (i += 1) profile.note(0x40e0000000, 0x130, false);
    profile.note(0x40e0000000, 0x138, false);
    profile.note(0x40e0000000, 0x138, true);

    const gap = profile.lookup(0x40e0000000, 0x130).?;
    try std.testing.expectEqual(@as(u32, 41), gap.reads);
    try std.testing.expectEqual(@as(u32, 0), gap.writes);
    try std.testing.expect(gap.access().readOnly());

    const healthy = profile.lookup(0x40e0000000, 0x138).?;
    try std.testing.expect(!healthy.access().readOnly());
}

test "an untouched offset is absent rather than reported as read-only" {
    var profile = Profile{};
    profile.note(0x40e0000000, 0x130, false);
    // Never touched: no entry at all, which is a different claim from
    // "touched, never written".
    try std.testing.expectEqual(@as(?Field, null), profile.lookup(0x40e0000000, 0x200));
    try std.testing.expectEqual(@as(?Field, null), profile.lookup(0x99999999, 0x130));
}

test "array indexing and self-referential offsets are not structure fields" {
    var profile = Profile{};
    profile.note(0x40e0000000, 0x8000, false); // beyond a plausible struct
    profile.note(0x40e0000000, 0, false); // plain dereference
    profile.note(0, 0x130, false); // null base
    try std.testing.expectEqual(@as(usize, 0), profile.base_count);
}

test "neighbours localise a suspicious field" {
    var profile = Profile{};
    profile.note(0x40e0000000, 0x128, true);
    profile.note(0x40e0000000, 0x130, false);
    profile.note(0x40e0000000, 0x138, true);
    profile.note(0x40e0000000, 0x900, true); // far away

    var out: [8]Field = undefined;
    const found = profile.neighbours(0x40e0000000, 0x130, 0x10, &out);
    try std.testing.expectEqual(@as(usize, 3), found);
    // The far field is excluded, so the report is about the neighbourhood.
    for (out[0..found]) |field| try std.testing.expect(field.offset != 0x900);
}

test "capacity is bounded and overflow counted rather than silent" {
    var profile = Profile{};
    var base: u64 = 0;
    while (base < max_bases) : (base += 1) profile.note(0x1000 * (base + 1), 8, false);
    try std.testing.expectEqual(max_bases, profile.base_count);
    profile.note(0xDEAD0000, 8, false);
    try std.testing.expectEqual(@as(u64, 1), profile.base_overflows);
}

test "colliding offsets are refused rather than merged" {
    // Two offsets that map to the same direct-mapped slot must not combine
    // their counts: reporting a field as written because its slot-mate was
    // written would invert the very finding this profile exists to make.
    var profile = Profile{};
    const first: u64 = 0x8;
    const second: u64 = first + (max_fields * 8);
    profile.note(0x1000, first, false);
    profile.note(0x1000, second, true);

    const kept = profile.lookup(0x1000, first).?;
    try std.testing.expectEqual(@as(u32, 1), kept.reads);
    try std.testing.expectEqual(@as(u32, 0), kept.writes);
    try std.testing.expectEqual(@as(?Field, null), profile.lookup(0x1000, second));
    try std.testing.expect(profile.bases[0].field_overflows > 0);
}

test "lookup is O(1) and does not depend on insertion order" {
    var profile = Profile{};
    profile.note(0x1000, 0x200, true);
    profile.note(0x1000, 0x8, false);
    profile.note(0x1000, 0x130, false);
    try std.testing.expectEqual(@as(u32, 1), profile.lookup(0x1000, 0x130).?.reads);
    try std.testing.expectEqual(@as(u32, 1), profile.lookup(0x1000, 0x200).?.writes);
}
