//! What a guest critical section actually contains, when the guest says it is
//! contended and names nobody.
//!
//! A contention report with `owner=00000000` is self-contradictory: a lock is
//! contended because another thread holds it, and no thread has thread id zero.
//! The waiter is therefore waiting for a release that cannot come, and the run
//! ends with a thread parked forever on a lock nobody owns. That is not a
//! scheduling problem and no amount of scheduler tracing finds it.
//!
//! The reason it goes unfound is that the log describes the guest's *belief*
//! rather than the memory. `lock=0->1` says the guest incremented the lock
//! count from zero — and on this ABI a free lock holds **-1**, so a lock that
//! reads zero is not free-and-being-taken, it is already-held-by-nobody. The
//! two look identical in a transition log and are completely different faults:
//! one is a race, the other is a structure that was never initialised, or an
//! initialisation that landed somewhere the guest is not reading.
//!
//! So this decodes the bytes and says which. It reports the structure exactly
//! as it sits in guest memory, names the state, and — when the state is
//! impossible — says what to look at next. It never repairs anything: writing
//! -1 into a lock the guest believes it holds would trade a visible hang for a
//! silent double-entry, and the hang is the honest symptom.

const std = @import("std");

/// `X_RTL_CRITICAL_SECTION` as Xenia lays it out: a 16-byte dispatcher header
/// followed by the lock triple. Most multi-byte guest fields are big-endian,
/// but Xenia deliberately keeps `lock_count` as a native `int32_t` because its
/// host atomics operate on it directly. On the translated x86-64 build that
/// one member is little-endian. `-1` looks the same in both orders, which is
/// why the mixed layout survived earlier diagnostics.
pub const size_bytes: usize = 28;

pub const header_offset: usize = 0;
pub const lock_count_offset: usize = 16;
pub const recursion_count_offset: usize = 20;
pub const owning_thread_offset: usize = 24;

/// A free lock holds -1, not 0. Every conclusion below rests on this.
pub const free_lock_count: i32 = -1;

pub const Fields = struct {
    type_flags: u32 = 0,
    signal_state: u32 = 0,
    wait_list_flink: u32 = 0,
    wait_list_blink: u32 = 0,
    lock_count: i32 = 0,
    recursion_count: i32 = 0,
    owning_thread: u32 = 0,

    /// All twenty-eight bytes zero. Distinct from "free": a free lock is not
    /// blank, it holds -1, so a blank structure is one nothing ever wrote.
    pub fn blank(self: Fields) bool {
        return self.type_flags == 0 and self.signal_state == 0 and
            self.wait_list_flink == 0 and self.wait_list_blink == 0 and
            self.lock_count == 0 and self.recursion_count == 0 and
            self.owning_thread == 0;
    }
};

pub fn decode(bytes: []const u8) ?Fields {
    if (bytes.len < size_bytes) return null;
    return .{
        .type_flags = std.mem.readInt(u32, bytes[0..4], .big),
        .signal_state = std.mem.readInt(u32, bytes[4..8], .big),
        .wait_list_flink = std.mem.readInt(u32, bytes[8..12], .big),
        .wait_list_blink = std.mem.readInt(u32, bytes[12..16], .big),
        .lock_count = std.mem.readInt(i32, bytes[16..20], .little),
        .recursion_count = std.mem.readInt(i32, bytes[20..24], .big),
        .owning_thread = std.mem.readInt(u32, bytes[24..28], .big),
    };
}

/// What the memory says the lock is. Ordered from "fine" to "cannot happen".
pub const State = enum(u8) {
    /// `lock_count == -1`: nobody holds it and the next entry succeeds.
    free,
    /// Held, with an owning thread. Ordinary contention.
    held,
    /// Held recursively by its owner.
    held_recursive,
    /// Every byte is zero. Nothing ever initialised this structure, so its
    /// lock count reads as "held" and its owner reads as "nobody".
    never_initialised,
    /// Not blank, but claims to be held while naming no owner. The bytes were
    /// written by something; the owner field was not maintained.
    held_by_nobody,

    pub fn impossible(self: State) bool {
        return self == .never_initialised or self == .held_by_nobody;
    }

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .free => "free (lock_count == -1)",
            .held => "held by a named thread",
            .held_recursive => "held recursively by its owner",
            .never_initialised => "NEVER INITIALISED: all 28 bytes are zero",
            .held_by_nobody => "IMPOSSIBLE: claims to be held while naming no owner",
        };
    }
};

pub fn classify(fields: Fields) State {
    if (fields.blank()) return .never_initialised;
    if (fields.lock_count == free_lock_count) return .free;
    if (fields.owning_thread == 0) return .held_by_nobody;
    if (fields.recursion_count > 1) return .held_recursive;
    return .held;
}

/// What to look at, given the state and whether anything ever wrote the page.
///
/// The two impossible states have different causes and the write evidence is
/// what separates them: a structure nothing ever wrote was never initialised,
/// and a structure something wrote that still reads blank means the write and
/// the read are not looking at the same memory.
pub fn guidance(state: State, page_ever_written: bool) []const u8 {
    return switch (state) {
        .free => "the lock is free; a waiter parked on it is waiting for a wake that has already been earned, so look at the wait/signal bridge rather than the lock",
        .held, .held_recursive => "the lock is genuinely held; find the owning thread and why it has not released",
        .never_initialised => if (page_ever_written)
            "every byte reads zero AND a write to this page was observed, so the initialisation is landing somewhere the guest does not read it back from. Compare the address the initialiser wrote with the address the waiter reads, including any physical alias of the same page"
        else
            "every byte reads zero and NO write to this page was ever observed, so the initialising call never reached guest memory. Find the initialiser for this lock and confirm it ran and targeted this address; a free lock must hold -1, and zeroed memory reads as held-by-nobody",
        .held_by_nobody => "the structure was written but its owner field is zero, so a release cleared the owner without clearing the lock count, or two writers disagree about the layout. Compare the release path's field offsets with the entry path's",
    };
}

test "a zeroed structure is never-initialised rather than free" {
    const blank = [_]u8{0} ** size_bytes;
    const fields = decode(&blank).?;
    try std.testing.expect(fields.blank());
    try std.testing.expectEqual(State.never_initialised, classify(fields));
    try std.testing.expect(classify(fields).impossible());
}

// The distinction the whole file exists for: zero is not free.
test "a free lock holds minus one, so zero is not free" {
    var bytes = [_]u8{0} ** size_bytes;
    std.mem.writeInt(i32, bytes[lock_count_offset..][0..4], -1, .little);
    const fields = decode(&bytes).?;
    try std.testing.expectEqual(@as(i32, -1), fields.lock_count);
    try std.testing.expectEqual(State.free, classify(fields));
    try std.testing.expect(!classify(fields).impossible());
}

test "a held lock names its owner" {
    var bytes = [_]u8{0} ** size_bytes;
    std.mem.writeInt(i32, bytes[lock_count_offset..][0..4], 0, .little);
    std.mem.writeInt(i32, bytes[recursion_count_offset..][0..4], 1, .big);
    std.mem.writeInt(u32, bytes[owning_thread_offset..][0..4], 0x3002A018, .big);
    const fields = decode(&bytes).?;
    try std.testing.expectEqual(State.held, classify(fields));
    try std.testing.expectEqual(@as(u32, 0x3002A018), fields.owning_thread);

    std.mem.writeInt(i32, bytes[recursion_count_offset..][0..4], 3, .big);
    try std.testing.expectEqual(State.held_recursive, classify(decode(&bytes).?));
}

test "a written structure with no owner is impossible rather than merely held" {
    var bytes = [_]u8{0} ** size_bytes;
    std.mem.writeInt(u32, bytes[0..4], 0x00000100, .big);
    std.mem.writeInt(i32, bytes[lock_count_offset..][0..4], 1, .little);
    const fields = decode(&bytes).?;
    try std.testing.expect(!fields.blank());
    try std.testing.expectEqual(State.held_by_nobody, classify(fields));
    try std.testing.expect(classify(fields).impossible());
}

// Big-endian matters and is easy to get wrong precisely because -1 hides it.
test "guest fields are big-endian while the host-atomic lock is little-endian" {
    var bytes = [_]u8{0} ** size_bytes;
    std.mem.writeInt(u32, bytes[owning_thread_offset..][0..4], 0x12345678, .big);
    std.mem.writeInt(i32, bytes[lock_count_offset..][0..4], 0x01020304, .little);
    try std.testing.expectEqual(@as(u32, 0x12345678), decode(&bytes).?.owning_thread);
    try std.testing.expectEqual(@as(i32, 0x01020304), decode(&bytes).?.lock_count);
    // Read the other way round it would be 0x78563412, which is a plausible
    // thread id and would not look wrong.
    try std.testing.expect(decode(&bytes).?.owning_thread != 0x78563412);
}

// The write evidence is what turns "never initialised" into an address to look
// at, and the two answers send a reader to different subsystems.
test "write evidence separates a missing initialiser from a misdirected one" {
    const never_written = guidance(.never_initialised, false);
    try std.testing.expect(std.mem.indexOf(u8, never_written, "never reached guest memory") != null);

    const written = guidance(.never_initialised, true);
    try std.testing.expect(std.mem.indexOf(u8, written, "physical alias") != null);
    try std.testing.expect(!std.mem.eql(u8, never_written, written));
}

test "a free lock under a parked waiter points away from the lock" {
    try std.testing.expect(std.mem.indexOf(u8, guidance(.free, false), "wait/signal bridge") != null);
}

test "a short read yields nothing rather than a partial structure" {
    const truncated = [_]u8{0} ** (size_bytes - 1);
    try std.testing.expect(decode(&truncated) == null);
}

test "every state explains itself" {
    inline for (@typeInfo(State).@"enum".fields) |field| {
        const state: State = @enumFromInt(field.value);
        try std.testing.expect(state.label().len > 0);
        try std.testing.expect(guidance(state, false).len > 0);
    }
}
