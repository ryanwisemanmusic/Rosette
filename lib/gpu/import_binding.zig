//! Whether the kernel imports a title calls are actually bound, and what it
//! means when the emulator keeps asking.
//!
//! The emulator emits a "callback-missing import probe" for each graphics
//! export whenever it decides a callback has gone missing. During bootstrap it
//! can also emit a "thunk readiness" line before the call. Both report, per
//! ordinal: whether the import slot is committed/imported and translatable,
//! the word in it, the thunk address, the first two instructions at the thunk,
//! and whether those instructions are the kernel-export stub.
//!
//! Read carelessly, a probe firing looks like a binding failure — the emulator
//! is asking whether the import is bound, so presumably it is not. Read
//! exactly, the probe in the observed run reported every field healthy:
//! committed, translated, and `sc 2 / blr` at the thunk, which *is* the kernel
//! export trampoline. Nothing is unbound. The emulator is repeatedly checking a
//! binding that has been correct the whole time.
//!
//! That inverts the conclusion. If the imports are bound and the callback is
//! still considered missing, the defect is in whatever tracks callback state,
//! not in the loader — and a harness that "fixed" the binding would be fixing
//! something that was never broken while the real state machine stayed wrong.
//!
//! ## What a harness can and cannot do here
//!
//! Binding is the loader's. A thunk that is not a stub is a real defect and one
//! this module can name precisely — ordinal, address, and the two instruction
//! words that should have been there. Rebinding it from outside would mean
//! writing guest code, which is a different and much larger claim than writing
//! a kernel variable, so this reports and does not repair.

const std = @import("std");

/// The two instruction words a bound kernel export thunk starts with.
///
/// `sc 2` traps into the emulator's export dispatcher; `blr` returns to the
/// caller when it comes back. Any other pair means the slot points at something
/// that is not a kernel export, and the title calling it goes somewhere wrong
/// rather than failing.
pub const thunk_syscall_word: u32 = 0x44000042;
pub const thunk_return_word: u32 = 0x4E800020;

pub fn isExportThunk(word0: u32, word1: u32) bool {
    return word0 == thunk_syscall_word and word1 == thunk_return_word;
}

/// What a probe found for one ordinal. Ordered from healthy to worst, so the
/// worst state across a set is a max.
pub const Binding = enum(u8) {
    /// The probe has not reported this ordinal.
    unprobed = 0,
    /// Slot committed, translatable, and the thunk is the export stub.
    bound = 1,
    /// The thunk is reachable and does not begin with the export stub. The
    /// title calling this lands on something that is not a kernel export.
    thunk_not_a_stub = 2,
    /// The thunk address does not translate, so the call target is not mapped.
    thunk_unmapped = 3,
    /// The import slot itself is not committed or not translatable. The title
    /// cannot even load the address it would call.
    slot_unmapped = 4,

    pub fn label(self: Binding) []const u8 {
        return switch (self) {
            .unprobed => "unprobed",
            .bound => "bound",
            .thunk_not_a_stub => "THUNK-NOT-A-STUB",
            .thunk_unmapped => "THUNK-UNMAPPED",
            .slot_unmapped => "SLOT-UNMAPPED",
        };
    }

    pub fn healthy(self: Binding) bool {
        return self == .bound or self == .unprobed;
    }

    pub fn meaning(self: Binding) []const u8 {
        return switch (self) {
            .unprobed => "the emulator has not probed this ordinal, so nothing is known about it",
            .bound => "the slot is committed and translatable and the thunk begins with the kernel-export stub. This import is correctly bound and calling it will reach the emulator",
            .thunk_not_a_stub => "the thunk is reachable and does not begin with the export stub. A title calling this lands on whatever those instructions are, which is worse than an unbound import because it does not fail",
            .thunk_unmapped => "the thunk address does not translate, so the call target is not mapped and the call faults",
            .slot_unmapped => "the import slot is not committed or not translatable, so the title cannot load the address it would call",
        };
    }
};

pub const Entry = struct {
    ordinal: u16 = 0,
    binding: Binding = .unprobed,
    slot_address: u32 = 0,
    slot_word: u32 = 0,
    thunk_address: u32 = 0,
    thunk_word0: u32 = 0,
    thunk_word1: u32 = 0,
    probes: u64 = 0,
};

pub const max_entries = 24;

pub const Ledger = struct {
    entries: [max_entries]Entry = [_]Entry{.{}} ** max_entries,
    count: usize = 0,
    /// Probes for ordinals past the table's capacity.
    untracked_probes: u64 = 0,
    /// Total probes seen. The emulator re-probing is itself the signal this
    /// module is built to interpret, so it is counted rather than deduplicated.
    total_probes: u64 = 0,

    fn slot(self: *Ledger, ordinal: u16) ?*Entry {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.ordinal == ordinal) return entry;
        }
        if (self.count == max_entries) return null;
        const entry = &self.entries[self.count];
        entry.* = .{ .ordinal = ordinal };
        self.count += 1;
        return entry;
    }

    pub fn observe(
        self: *Ledger,
        ordinal: u16,
        slot_committed: bool,
        slot_translated: bool,
        slot_word: u32,
        slot_address: u32,
        thunk_translated: bool,
        thunk_address: u32,
        word0: u32,
        word1: u32,
    ) void {
        self.total_probes +|= 1;
        const entry = self.slot(ordinal) orelse {
            self.untracked_probes +|= 1;
            return;
        };
        entry.probes +|= 1;
        entry.slot_address = slot_address;
        entry.slot_word = slot_word;
        entry.thunk_address = thunk_address;
        entry.thunk_word0 = word0;
        entry.thunk_word1 = word1;
        entry.binding = if (!slot_committed or !slot_translated)
            .slot_unmapped
        else if (!thunk_translated)
            .thunk_unmapped
        else if (!isExportThunk(word0, word1))
            .thunk_not_a_stub
        else
            .bound;
    }

    pub fn worst(self: *const Ledger) Binding {
        var result: Binding = .unprobed;
        for (self.entries[0..self.count]) |entry| {
            if (@intFromEnum(entry.binding) > @intFromEnum(result)) result = entry.binding;
        }
        return result;
    }

    pub fn boundCount(self: *const Ledger) u32 {
        var count: u32 = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.binding == .bound) count += 1;
        }
        return count;
    }

    /// The finding, which is usually the opposite of what a probe firing looks
    /// like.
    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.count == 0)
            return "the emulator has not probed any import binding, so nothing here is known either way";
        const worst_binding = self.worst();
        if (!worst_binding.healthy()) return worst_binding.meaning();
        return "every import the emulator probed is correctly bound: committed, translatable, and beginning with the kernel-export stub. The emulator is repeatedly checking a binding that has been correct the whole time, so whatever it believes is missing is not the binding. Look at the state machine that decides a callback has gone missing, not at the loader — and note that a harness 'repairing' this would repair something that was never broken while the real defect stayed in place";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// A healthy probe, exactly as the observed run reported it for 0x1C3.
fn observeHealthy(ledger: *Ledger, ordinal: u16, slot_address: u32, thunk: u32) void {
    ledger.observe(
        ordinal,
        true,
        true,
        thunk,
        slot_address,
        true,
        thunk,
        thunk_syscall_word,
        thunk_return_word,
    );
}

test "the kernel export stub is recognised rather than assumed" {
    try std.testing.expect(isExportThunk(0x44000042, 0x4E800020));
    try std.testing.expect(!isExportThunk(0x44000002, 0x4E800020));
    try std.testing.expect(!isExportThunk(0x44000042, 0x60000000));
}

// The inversion this module exists for. A probe firing looks like a binding
// failure and in the observed run reported every field healthy.
test "a probed-and-healthy binding inverts the conclusion the probe suggests" {
    var ledger = Ledger{};
    observeHealthy(&ledger, 0x1C3, 0x820006C4, 0x8270DF84);
    observeHealthy(&ledger, 0x1D5, 0x820006FC, 0x8270E034);
    observeHealthy(&ledger, 0x25B, 0x820006DC, 0x8270D514);

    try std.testing.expectEqual(@as(u32, 3), ledger.boundCount());
    try std.testing.expectEqual(Binding.bound, ledger.worst());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "not the binding") != null);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "state machine") != null);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "never broken") != null);
}

// Worse than an unbound import, because it does not fail.
test "a thunk that is not the export stub is named as its own defect" {
    var ledger = Ledger{};
    ledger.observe(0x25B, true, true, 0x8270D514, 0x820006DC, true, 0x8270D514, 0x60000000, 0x4E800020);
    try std.testing.expectEqual(Binding.thunk_not_a_stub, ledger.worst());
    try std.testing.expect(!ledger.worst().healthy());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "does not fail") != null);
}

test "an uncommitted slot outranks every other defect" {
    var ledger = Ledger{};
    observeHealthy(&ledger, 0x1C3, 0x820006C4, 0x8270DF84);
    ledger.observe(0x1D5, true, true, 0, 0x820006FC, false, 0, 0, 0);
    try std.testing.expectEqual(Binding.thunk_unmapped, ledger.worst());

    ledger.observe(0x25B, false, false, 0, 0x820006DC, false, 0, 0, 0);
    try std.testing.expectEqual(Binding.slot_unmapped, ledger.worst());
    try std.testing.expectEqual(@as(u32, 1), ledger.boundCount());
}

// The emulator re-probing is itself the signal, so probes are counted rather
// than deduplicated.
test "repeated probes of the same ordinal are counted, not collapsed" {
    var ledger = Ledger{};
    var index: u32 = 0;
    while (index < 5) : (index += 1) observeHealthy(&ledger, 0x1C3, 0x820006C4, 0x8270DF84);
    try std.testing.expectEqual(@as(usize, 1), ledger.count);
    try std.testing.expectEqual(@as(u64, 5), ledger.entries[0].probes);
    try std.testing.expectEqual(@as(u64, 5), ledger.total_probes);
}

// A binding that degrades between probes has to be visible, or a run that
// started healthy reports healthy forever.
test "a later probe replaces an earlier verdict rather than being ignored" {
    var ledger = Ledger{};
    observeHealthy(&ledger, 0x1C3, 0x820006C4, 0x8270DF84);
    try std.testing.expectEqual(Binding.bound, ledger.worst());
    ledger.observe(0x1C3, true, true, 0x8270DF84, 0x820006C4, true, 0x8270DF84, 0, 0);
    try std.testing.expectEqual(Binding.thunk_not_a_stub, ledger.worst());
}

test "probes past capacity are counted rather than dropped silently" {
    var ledger = Ledger{};
    var ordinal: u16 = 1;
    while (ordinal <= max_entries) : (ordinal += 1) observeHealthy(&ledger, ordinal, 0, 0);
    try std.testing.expectEqual(@as(usize, max_entries), ledger.count);
    observeHealthy(&ledger, 0xFFF, 0, 0);
    try std.testing.expectEqual(@as(u64, 1), ledger.untracked_probes);
}

test "an unprobed ledger concludes nothing either way" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Binding.unprobed, ledger.worst());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "nothing here is known") != null);
}

test "every binding state explains itself and only bound is healthy" {
    inline for (.{
        Binding.unprobed,       Binding.bound,         Binding.thunk_not_a_stub,
        Binding.thunk_unmapped, Binding.slot_unmapped,
    }) |binding| {
        try std.testing.expect(binding.label().len > 0);
        try std.testing.expect(binding.meaning().len > 40);
    }
    try std.testing.expect(Binding.bound.healthy());
    try std.testing.expect(!Binding.thunk_not_a_stub.healthy());
    try std.testing.expect(!Binding.thunk_unmapped.healthy());
    try std.testing.expect(!Binding.slot_unmapped.healthy());
}
