//! What a guest address *is*, when no symbol names it.
//!
//! ## The hole this fills
//!
//! Rosette's symbol resolver answers one question: which function in the
//! loaded image covers this address. That question has no answer for most of
//! a running process's address space, and the resolver correctly says
//! nothing - so a report prints `<unnamed>` and the reader is left with a
//! bare hexadecimal number.
//!
//! On the 2026-09-12 run that cost three of the most interesting lines in the
//! log. The busiest worker in the process sat at `0x1430b25b0` under
//! `at=<unnamed>`; the address is five hundred bytes past the end of the PE
//! image, which makes it one of Rosette's own import thunks - a fact Rosette
//! knew and did not say. `Main XThread` sat at `0xa000044b`, which is inside
//! a block the guest had allocated executable and filled with code it
//! generated itself. Neither is a symbol gap. Both are regions with an owner
//! and a name, and nothing was writing them down.
//!
//! ## Why this is not a Xenia package
//!
//! Nothing here knows what an emulator is. The regions are the ones any
//! hosted process has: the image the loader mapped, the thunks the host
//! synthesised, the heap, the stacks, and whatever the guest allocated with
//! execute permission and then jumped into. A JIT is only interesting here
//! because it is the last of those, and every program with a JIT produces
//! the same shape.
//!
//! ## What this package proves, and what it does not
//!
//! It is a lookup over ranges somebody else established. It discovers
//! nothing: a region is here because a loader mapped it, a handler allocated
//! it, or a runtime reserved it, and the caller is the one that knows. An
//! address in no region reports `unmapped`, which is a real answer - it means
//! the address belongs to nothing Rosette has recorded, and that is worth
//! seeing rather than hiding behind `<unnamed>`.

const std = @import("std");

/// What kind of thing occupies a range of guest address space.
///
/// Ordered from most specific to least, because `describe` prefers the
/// narrowest region containing an address and ties are broken by this order.
pub const RegionKind = enum {
    /// Executable bytes the image loader mapped.
    image_code,
    /// Read-only or writable bytes the image loader mapped.
    image_data,
    /// A stub the host synthesised so a guest call into an import lands
    /// somewhere it can intercept. Guest code branches here constantly and
    /// none of it is in the image's symbol table.
    import_thunk,
    /// A trampoline the host built so it can call back into guest code.
    callback_trampoline,
    /// Memory the guest allocated with execute permission and then ran. For
    /// a program with a JIT this is where most of its own work happens, and
    /// it has no symbols by construction because it did not exist at link
    /// time.
    generated_code,
    /// The guest's general allocation arena.
    guest_heap,
    /// A thread stack.
    guest_stack,
    /// An address the guest reads and writes to talk to a device.
    device_memory,
    /// Recorded, named, but not one of the above.
    other,

    pub fn label(self: RegionKind) []const u8 {
        return switch (self) {
            .image_code => "image-code",
            .image_data => "image-data",
            .import_thunk => "import-thunk",
            .callback_trampoline => "callback-trampoline",
            .generated_code => "generated-code",
            .guest_heap => "guest-heap",
            .guest_stack => "guest-stack",
            .device_memory => "device-memory",
            .other => "region",
        };
    }

    /// Whether instructions are expected to execute here. A guest rip in a
    /// region that is not code is a much stronger finding than one in a
    /// region that is - it means control flow left the code entirely.
    pub fn isCode(self: RegionKind) bool {
        return switch (self) {
            .image_code, .import_thunk, .callback_trampoline, .generated_code => true,
            .image_data, .guest_heap, .guest_stack, .device_memory, .other => false,
        };
    }

    /// Whether a report should treat an address here as attributable to the
    /// program's own author. Nothing in a host-synthesised region is.
    pub fn isGuestOwned(self: RegionKind) bool {
        return switch (self) {
            .import_thunk, .callback_trampoline => false,
            else => true,
        };
    }
};

pub const label_capacity: usize = 48;

pub const Region = struct {
    start: u64 = 0,
    /// One past the last byte. A zero-length region is never stored.
    end: u64 = 0,
    kind: RegionKind = .other,
    label_buffer: [label_capacity]u8 = [_]u8{0} ** label_capacity,
    label_length: u8 = 0,
    /// How many times an address in this region has been looked up. A region
    /// nothing ever asks about is dead weight in the table, and one that
    /// answers most of the questions is where a reader should look.
    lookups: u64 = 0,

    pub fn label(self: *const Region) []const u8 {
        return self.label_buffer[0..self.label_length];
    }

    pub fn length(self: *const Region) u64 {
        return if (self.end > self.start) self.end - self.start else 0;
    }

    pub fn contains(self: *const Region, address: u64) bool {
        return address >= self.start and address < self.end;
    }
};

/// A bounded, ordered set of address regions.
///
/// Bounded because the alternative is an allocator on a path that answers
/// questions during a crash report. Sixty-four is well past what a hosted
/// process needs: an image has under twenty sections, and the host adds a
/// handful of its own.
pub const Map = struct {
    pub const capacity: usize = 64;

    regions: [capacity]Region = [_]Region{.{}} ** capacity,
    count: usize = 0,
    /// Regions that did not fit. Reported, so a truncated map never looks
    /// complete.
    overflow: u32 = 0,
    /// Lookups that landed in no region at all.
    unmapped_lookups: u64 = 0,

    /// Record a range. Later inserts of the same range replace the earlier
    /// one, so a loader that refines its own answer - "this was the heap,
    /// it is now the heap and this much of it is executable" - wins.
    ///
    /// Returns false only when the table is full or the range is empty.
    pub fn insert(self: *Map, start: u64, length: u64, kind: RegionKind, label: []const u8) bool {
        if (length == 0) return false;
        const end = start +| length;
        if (end <= start) return false;
        for (self.regions[0..self.count]) |*existing| {
            if (existing.start != start or existing.end != end) continue;
            existing.kind = kind;
            existing.label_length = storeLabel(&existing.label_buffer, label);
            return true;
        }
        if (self.count == capacity) {
            self.overflow +|= 1;
            return false;
        }
        var region = Region{ .start = start, .end = end, .kind = kind };
        region.label_length = storeLabel(&region.label_buffer, label);
        self.regions[self.count] = region;
        self.count += 1;
        return true;
    }

    /// Grow a region to cover an address, or create it.
    ///
    /// For a range whose extent is discovered rather than declared: a JIT
    /// buffer is allocated in pieces and the interesting fact is that the
    /// whole span belongs to one producer. `granule` rounds the growth so a
    /// region does not creep one page at a time.
    pub fn extend(self: *Map, address: u64, granule: u64, kind: RegionKind, label: []const u8) bool {
        const step = if (granule == 0) 1 else granule;
        const low = address - (address % step);
        const high = low +| step;
        for (self.regions[0..self.count]) |*existing| {
            if (existing.kind != kind) continue;
            // Adjacent or overlapping within one granule of this region.
            if (address +| step < existing.start or address > existing.end +| step) continue;
            if (low < existing.start) existing.start = low;
            if (high > existing.end) existing.end = high;
            return true;
        }
        return self.insert(low, step, kind, label);
    }

    /// The narrowest recorded region containing an address.
    ///
    /// Narrowest, not first: an image's sections sit inside the span the
    /// loader reserved for the whole image, and answering "the image" when a
    /// caller could have been told "the image's `.text`" throws away the
    /// better answer.
    pub fn find(self: *const Map, address: u64) ?*const Region {
        var best: ?*const Region = null;
        for (self.regions[0..self.count]) |*region| {
            if (!region.contains(address)) continue;
            const better = if (best) |current| region.length() < current.length() else true;
            if (better) best = region;
        }
        return best;
    }

    /// The same, counting the lookup so the report can say which regions the
    /// run actually asked about.
    pub fn lookup(self: *Map, address: u64) ?*const Region {
        var best: ?usize = null;
        for (self.regions[0..self.count], 0..) |*region, index| {
            if (!region.contains(address)) continue;
            const better = if (best) |current| region.length() < self.regions[current].length() else true;
            if (better) best = index;
        }
        const index = best orelse {
            self.unmapped_lookups +|= 1;
            return null;
        };
        self.regions[index].lookups +|= 1;
        return &self.regions[index];
    }

    /// `kind:label+0xoffset` for an address, or an empty slice when nothing
    /// recorded covers it.
    ///
    /// Empty rather than a placeholder, so a caller that already has a symbol
    /// can prefer it and a caller that does not can print its own marker.
    pub fn describe(self: *const Map, address: u64, buffer: []u8) []const u8 {
        const region = self.find(address) orelse return "";
        const offset = address - region.start;
        if (region.label_length == 0) {
            return std.fmt.bufPrint(buffer, "{s}+0x{x}", .{ region.kind.label(), offset }) catch "";
        }
        return std.fmt.bufPrint(buffer, "{s}:{s}+0x{x}", .{ region.kind.label(), region.label(), offset }) catch "";
    }

    /// Whether an address is in a region instructions are expected to run in.
    /// An unmapped address answers false, which is the honest reading: a rip
    /// nothing accounts for is not known to be code.
    pub fn isExecutable(self: *const Map, address: u64) bool {
        const region = self.find(address) orelse return false;
        return region.kind.isCode();
    }

    fn storeLabel(destination: *[label_capacity]u8, source: []const u8) u8 {
        const length = @min(destination.len, source.len);
        var written: usize = 0;
        // A label goes straight into a log line and can come from a guest
        // string, so anything unprintable is folded rather than emitted.
        while (written < length) : (written += 1) {
            const byte = source[written];
            destination[written] = if (byte >= 0x20 and byte < 0x7F) byte else '?';
        }
        return @intCast(written);
    }
};

test "an address in no region is unmapped, not misattributed" {
    var map = Map{};
    var buffer: [96]u8 = undefined;
    // Before anything is recorded, every address is unmapped. Saying so is
    // the point: `<unnamed>` reads as "Rosette has no symbol", and this reads
    // as "Rosette has no record of this memory at all".
    try std.testing.expectEqual(@as(?*const Region, null), map.find(0x140001000));
    try std.testing.expectEqualStrings("", map.describe(0x140001000, &buffer));
    try std.testing.expect(!map.isExecutable(0x140001000));

    try std.testing.expect(map.insert(0x140001000, 0x1000, .image_code, ".text"));
    try std.testing.expectEqualStrings("image-code:.text+0x40", map.describe(0x140001040, &buffer));
    try std.testing.expect(map.isExecutable(0x140001040));
    // One past the end belongs to nobody.
    try std.testing.expectEqualStrings("", map.describe(0x140002000, &buffer));
}

test "the narrowest region wins, because it is the better answer" {
    var map = Map{};
    var buffer: [96]u8 = undefined;
    try std.testing.expect(map.insert(0x140000000, 0x100000, .image_data, "xenia_canary.exe"));
    try std.testing.expect(map.insert(0x140001000, 0x1000, .image_code, ".text"));
    // Both contain the address. The section is the useful answer.
    try std.testing.expectEqualStrings("image-code:.text+0x0", map.describe(0x140001000, &buffer));
    // Outside the section, the image span still answers.
    try std.testing.expectEqualStrings("image-data:xenia_canary.exe+0x8000", map.describe(0x140008000, &buffer));
}

test "the three addresses the 2026-09-12 run could not name" {
    var map = Map{};
    var buffer: [96]u8 = undefined;
    // The PE image ends at 0x1430b2000. Everything the report printed as
    // `<unnamed>` was on one side or the other of that line.
    try std.testing.expect(map.insert(0x140000000, 0x030b2000, .image_data, "xenia_canary.exe"));
    try std.testing.expect(map.insert(0x1430b2000, 0x200000, .import_thunk, "win32-import-stubs"));

    // The busiest worker in the run, at 24% of the interpreter.
    try std.testing.expectEqualStrings(
        "import-thunk:win32-import-stubs+0x5b0",
        map.describe(0x1430b25b0, &buffer),
    );
    // Two more threads sat here.
    try std.testing.expectEqualStrings(
        "import-thunk:win32-import-stubs+0x7cef0",
        map.describe(0x14312eef0, &buffer),
    );
    // And `Main XThread`, inside a block the guest allocated executable.
    try std.testing.expect(map.extend(0xa000044b, 0x10000, .generated_code, "guest JIT"));
    try std.testing.expectEqualStrings("generated-code:guest JIT+0x44b", map.describe(0xa000044b, &buffer));

    // A host-synthesised region is not the guest's own code, and a report
    // that blames the guest for time spent in one is blaming the wrong party.
    try std.testing.expect(!map.find(0x1430b25b0).?.kind.isGuestOwned());
    try std.testing.expect(map.find(0xa000044b).?.kind.isGuestOwned());
}

test "a discovered region grows by granules rather than one page at a time" {
    var map = Map{};
    try std.testing.expect(map.extend(0xa0000000, 0x10000, .generated_code, "guest JIT"));
    const before = map.count;
    // Another address in the same granule adds nothing.
    try std.testing.expect(map.extend(0xa0000abc, 0x10000, .generated_code, "guest JIT"));
    try std.testing.expectEqual(before, map.count);
    // An adjacent granule grows the existing region instead of making a new
    // one, or a JIT that emits a megabyte would fill the table by itself.
    try std.testing.expect(map.extend(0xa0018000, 0x10000, .generated_code, "guest JIT"));
    try std.testing.expectEqual(before, map.count);
    const region = map.find(0xa0018000).?;
    try std.testing.expect(region.start <= 0xa0000000);
    try std.testing.expect(region.end >= 0xa0019000);

    // A different kind at the same address is a separate region: memory can
    // be a heap block and a code buffer, and which one the reader wants
    // depends on whether they are looking at a rip or a pointer.
    try std.testing.expect(map.extend(0xa0000000, 0x10000, .guest_heap, "VirtualAlloc"));
    try std.testing.expect(map.count > before);
}

test "lookups are counted, and an unmapped address is counted too" {
    var map = Map{};
    try std.testing.expect(map.insert(0x140001000, 0x1000, .image_code, ".text"));
    _ = map.lookup(0x140001040);
    _ = map.lookup(0x140001080);
    try std.testing.expectEqual(@as(u64, 2), map.regions[0].lookups);
    try std.testing.expectEqual(@as(?*const Region, null), map.lookup(0x900000000));
    try std.testing.expectEqual(@as(u64, 1), map.unmapped_lookups);
}

test "a full table says so rather than dropping quietly" {
    var map = Map{};
    for (0..Map.capacity) |index| {
        try std.testing.expect(map.insert(0x1000 * (index + 1), 0x100, .other, "filler"));
    }
    try std.testing.expect(!map.insert(0xF000_0000, 0x100, .other, "one too many"));
    try std.testing.expectEqual(@as(u32, 1), map.overflow);
    // And an empty range is refused rather than stored as a region that can
    // never contain anything.
    try std.testing.expect(!map.insert(0x1000, 0, .other, "empty"));
}

test "a label from guest memory cannot put control bytes in a log line" {
    var map = Map{};
    var buffer: [96]u8 = undefined;
    const noisy = [_]u8{ 'J', 'I', 'T', 0x07, '\n', 'x' };
    try std.testing.expect(map.insert(0x2000, 0x100, .generated_code, &noisy));
    try std.testing.expectEqualStrings("generated-code:JIT??x+0x10", map.describe(0x2010, &buffer));
}
