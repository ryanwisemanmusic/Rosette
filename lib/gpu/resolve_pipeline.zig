//! Getting the picture out of EDRAM and into somewhere the guest can reach,
//! with the guest-visibility question asked explicitly.
//!
//! The defect this exists for
//! --------------------------
//! A rendered target the title cannot read is not a frame. The 2026-08-31 run
//! never got that far — zero resolves, zero colour resolves — but the shape of
//! the eventual failure is predictable and worth instrumenting before it
//! happens: a resolve that runs, writes host memory, and never becomes visible
//! through the guest's own alias produces a working renderer and a black
//! screen, and every counter on the emulator side reads healthy.
//!
//! So a resolve has a destination stated three ways, a copied-byte count, a
//! checksum taken on the guest's own route, and a separate coherency step. The
//! checksum is what turns "the resolve ran" into "the guest can see it".

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;
pub const Address = bridge.contract.Address;

/// The stages one resolve passes through.
pub const Stage = enum(u8) {
    /// Source EDRAM range and destination were decoded from registers.
    described = 0,
    /// The destination range is mapped and writable.
    destination_mapped = 1,
    /// Bytes were copied.
    copied = 2,
    /// The copy was made visible through the guest's own alias.
    coherent = 3,
    /// A checksum taken through the guest route changed.
    guest_visible_change = 4,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .described => "described",
            .destination_mapped => "destination mapped",
            .copied => "copied",
            .coherent => "coherent",
            .guest_visible_change => "guest-visible change",
        };
    }

    pub fn owner(self: Stage) []const u8 {
        return switch (self) {
            .described => "guest:title",
            .destination_mapped, .copied, .coherent, .guest_visible_change => "emulator:gpu",
        };
    }

    pub fn gapMeans(self: Stage) []const u8 {
        return switch (self) {
            .described => "no resolve has been described. The title has not asked for its render target to be copied anywhere, and nothing downstream is missing",
            .destination_mapped => "a resolve names a destination that is not mapped or not writable. The title asked for a copy into somewhere the emulator cannot write",
            .copied => "the destination is mapped and nothing was copied. The resolve path ran and moved no bytes",
            .coherent => "bytes were copied and no coherency step made them visible through the guest's alias. On a host with a coarser page granule than the guest's, this is exactly where a correct copy becomes an invisible one",
            .guest_visible_change => "the copy is coherent and a checksum taken through the guest's own route did not change. Either the resolve wrote what was already there, or it wrote somewhere other than where the guest reads",
        };
    }
};

pub const stage_count: usize = @typeInfo(Stage).@"enum".fields.len;

/// One resolve.
pub const Resolve = struct {
    id: u64 = 0,
    guest_step: u64 = 0,
    source: SourceClass = .unknown,
    /// EDRAM side.
    edram_base_tile: u32 = 0,
    edram_tiles: u32 = 0,
    /// Destination, named on every route so an alias split is visible.
    destination: Address = .{},
    format: u32 = 0,
    pitch: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    bytes_expected: u64 = 0,
    bytes_copied: u64 = 0,
    /// Checksums taken through the *guest's* route, before and after.
    checksum_before: u64 = 0,
    checksum_after: u64 = 0,
    checksum_sampled: bool = false,
    reached: [stage_count]bool = [_]bool{false} ** stage_count,

    pub fn note(self: *Resolve, stage: Stage) void {
        self.reached[@intFromEnum(stage)] = true;
    }

    pub fn has(self: Resolve, stage: Stage) bool {
        return self.reached[@intFromEnum(stage)];
    }

    pub fn firstGap(self: Resolve) ?Stage {
        var index: usize = 0;
        while (index < stage_count) : (index += 1) {
            if (!self.reached[index]) return @enumFromInt(index);
        }
        return null;
    }

    /// Whether every byte the description promised actually moved. A short
    /// copy produces a partly-updated surface, which is worse than none.
    pub fn copyComplete(self: Resolve) bool {
        return self.bytes_expected != 0 and self.bytes_copied == self.bytes_expected;
    }

    pub fn guestVisibleChange(self: Resolve) bool {
        return self.checksum_sampled and self.checksum_before != self.checksum_after;
    }

    /// The audit's criterion: a resolve into a readable guest range whose
    /// checksum changed, from an authentic source.
    pub fn provesGuestVisibleOutput(self: Resolve) bool {
        return self.firstGap() == null and
            self.copyComplete() and
            self.guestVisibleChange() and
            self.source == .guest_authentic;
    }
};

pub const Verdict = enum(u8) {
    /// Nothing has asked for a resolve.
    none_requested,
    /// Resolves are described and none completes.
    blocked,
    /// A resolve copied fewer bytes than it promised.
    short_copy,
    /// Copies complete and nothing the guest can see changed.
    invisible_to_guest,
    /// A resolve produced a guest-visible change.
    guest_visible,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .none_requested => "none-requested",
            .blocked => "BLOCKED",
            .short_copy => "SHORT-COPY",
            .invisible_to_guest => "INVISIBLE-TO-GUEST",
            .guest_visible => "guest-visible",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .none_requested => "the title has not asked for a resolve. There is no copy to explain and no frame source to expect",
            .blocked => "resolves are described and none reaches a guest-visible change. The first missing stage names who owns it",
            .short_copy => "a resolve moved fewer bytes than its description promised. A partly-updated surface is worse than an unwritten one, because it looks like output",
            .invisible_to_guest => "copies complete and a checksum taken through the guest's own route never changes. The picture is being written somewhere the guest does not read — on a host with a coarser page granule than the guest's, this is the shape an alias defect takes",
            .guest_visible => "a resolve produced a change the guest can see. There is a frame source",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .short_copy or self == .invisible_to_guest;
    }
};

pub const max_resolves: usize = 24;

pub const Summary = struct {
    resolves: u64 = 0,
    retained: usize = 0,
    dropped: u64 = 0,
    completed: u64 = 0,
    short_copies: u64 = 0,
    guest_visible_changes: u64 = 0,
    bytes_copied: u64 = 0,
    reached: [stage_count]u64 = [_]u64{0} ** stage_count,
};

pub const Ledger = struct {
    resolves: [max_resolves]Resolve = [_]Resolve{.{}} ** max_resolves,
    count: usize = 0,
    write_index: usize = 0,
    dropped: u64 = 0,
    total: u64 = 0,
    next_id: u64 = 1,

    pub fn begin(self: *Ledger, guest_step: u64, source: SourceClass) *Resolve {
        self.total +|= 1;
        if (self.count >= max_resolves) self.dropped +|= 1;
        const slot = &self.resolves[self.write_index];
        self.write_index = (self.write_index + 1) % max_resolves;
        if (self.count < max_resolves) self.count += 1;
        slot.* = .{ .id = self.next_id, .guest_step = guest_step, .source = source };
        self.next_id += 1;
        return slot;
    }

    pub fn retained(self: *const Ledger) []const Resolve {
        return self.resolves[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{ .resolves = self.total, .retained = self.count, .dropped = self.dropped };
        for (self.retained()) |resolve| {
            if (resolve.firstGap() == null) out.completed +|= 1;
            if (resolve.bytes_expected != 0 and !resolve.copyComplete() and resolve.has(.copied)) {
                out.short_copies +|= 1;
            }
            if (resolve.guestVisibleChange()) out.guest_visible_changes +|= 1;
            out.bytes_copied +|= resolve.bytes_copied;
            var index: usize = 0;
            while (index < stage_count) : (index += 1) {
                if (resolve.reached[index]) out.reached[index] +|= 1;
            }
        }
        return out;
    }

    pub fn frontier(self: *const Ledger) ?Stage {
        if (self.count == 0) return .described;
        const totals = self.summary();
        var index: usize = 0;
        while (index < stage_count) : (index += 1) {
            if (totals.reached[index] == 0) return @enumFromInt(index);
        }
        return null;
    }

    pub fn verdict(self: *const Ledger) Verdict {
        if (self.total == 0) return .none_requested;
        const totals = self.summary();
        if (totals.short_copies != 0) return .short_copy;
        if (totals.guest_visible_changes != 0) return .guest_visible;
        if (totals.reached[@intFromEnum(Stage.coherent)] != 0) return .invisible_to_guest;
        return .blocked;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.resolves;
        hash = hash *% 31 +% totals.guest_visible_changes;
        hash = hash *% 31 +% totals.bytes_copied;
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

fn describedResolve(ledger: *Ledger, source: SourceClass) *Resolve {
    const resolve = ledger.begin(1000, source);
    resolve.edram_base_tile = 0;
    resolve.edram_tiles = 128;
    resolve.destination = .{ .guest_virtual = 0xA000_0000, .guest_physical = 0x1FC0_0000, .host = 0x4_6F00_0000 };
    resolve.width = 1280;
    resolve.height = 720;
    resolve.bytes_expected = 1280 * 720 * 4;
    resolve.note(.described);
    return resolve;
}

test "no resolve requested is not a defect and explains its own zero" {
    const ledger = Ledger{};
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.none_requested, verdict);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expectEqual(Stage.described, ledger.frontier().?);
}

test "a copy the guest cannot see is a defect and not a quiet title" {
    var ledger = Ledger{};
    const resolve = describedResolve(&ledger, .guest_authentic);
    resolve.note(.destination_mapped);
    resolve.note(.copied);
    resolve.bytes_copied = resolve.bytes_expected;
    resolve.note(.coherent);
    resolve.checksum_sampled = true;
    resolve.checksum_before = 0x1234;
    resolve.checksum_after = 0x1234;

    try std.testing.expect(resolve.copyComplete());
    try std.testing.expect(!resolve.guestVisibleChange());
    try std.testing.expect(!resolve.provesGuestVisibleOutput());
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.invisible_to_guest, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "alias defect") != null);
}

test "a short copy outranks everything else the resolve did" {
    var ledger = Ledger{};
    const resolve = describedResolve(&ledger, .guest_authentic);
    resolve.note(.destination_mapped);
    resolve.note(.copied);
    resolve.bytes_copied = resolve.bytes_expected / 2;
    resolve.note(.coherent);
    resolve.checksum_sampled = true;
    resolve.checksum_after = 0xFFFF;

    try std.testing.expect(!resolve.copyComplete());
    try std.testing.expect(resolve.guestVisibleChange());
    try std.testing.expect(!resolve.provesGuestVisibleOutput());
    try std.testing.expectEqual(Verdict.short_copy, ledger.verdict());
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().short_copies);
}

test "a complete authentic resolve proves guest-visible output" {
    var ledger = Ledger{};
    const resolve = describedResolve(&ledger, .guest_authentic);
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        resolve.note(@enumFromInt(field.value));
    }
    resolve.bytes_copied = resolve.bytes_expected;
    resolve.checksum_sampled = true;
    resolve.checksum_before = 0;
    resolve.checksum_after = 0xDEAD;

    try std.testing.expect(resolve.provesGuestVisibleOutput());
    try std.testing.expectEqual(Verdict.guest_visible, ledger.verdict());
    try std.testing.expect(ledger.frontier() == null);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().completed);
}

test "a synthetic resolve crosses every stage and proves nothing" {
    var ledger = Ledger{};
    const resolve = describedResolve(&ledger, .synthetic);
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        resolve.note(@enumFromInt(field.value));
    }
    resolve.bytes_copied = resolve.bytes_expected;
    resolve.checksum_sampled = true;
    resolve.checksum_after = 1;
    try std.testing.expect(!resolve.provesGuestVisibleOutput());
}

test "an unmapped destination names its stage and its owner" {
    var ledger = Ledger{};
    _ = describedResolve(&ledger, .guest_authentic);
    try std.testing.expectEqual(Stage.destination_mapped, ledger.frontier().?);
    try std.testing.expectEqual(Verdict.blocked, ledger.verdict());
    try std.testing.expectEqualStrings("emulator:gpu", Stage.destination_mapped.owner());
    try std.testing.expectEqualStrings("guest:title", Stage.described.owner());
}

test "an unsampled checksum is not a proof that nothing changed" {
    var resolve = Resolve{};
    resolve.checksum_before = 1;
    resolve.checksum_after = 2;
    try std.testing.expect(!resolve.guestVisibleChange());
    resolve.checksum_sampled = true;
    try std.testing.expect(resolve.guestVisibleChange());
}

test "the resolve window is a ring and the totals are durable" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_resolves + 4) : (index += 1) {
        _ = ledger.begin(index, .guest_authentic);
    }
    try std.testing.expectEqual(max_resolves, ledger.retained().len);
    try std.testing.expectEqual(@as(u64, 4), ledger.dropped);
    try std.testing.expectEqual(@as(u64, max_resolves + 4), ledger.summary().resolves);
}

test "every stage names an owner and what its gap means" {
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        try std.testing.expect(stage.label().len != 0);
        try std.testing.expect(stage.owner().len != 0);
        try std.testing.expect(stage.gapMeans().len != 0);
    }
    try std.testing.expectEqual(@as(usize, 5), stage_count);
}
