//! Xbox kernel critical sections: the guest-visible 28-byte structure, the
//! five kernel exports that operate on it, and the lock protocol Rosette runs
//! for them in parallel mode.
//!
//! ## The call
//!
//! Xenia reaches a kernel export through `Trampoline(PPCContext*)`
//! (`kernel/util/shim_utils.h`):
//! - `rcx` is the calling XThread's PowerPC context;
//! - the section is that context's r3, a guest address translated through the
//!   context's virtual membase;
//! - the spin count is r4;
//! - a result goes back in r3 (`Result::Store`), never in rax.
//!
//! The bridge that shipped on 2026-09-26 read `rcx` as the section itself. It
//! initialized, entered and left bytes 0x00-0x1B of the caller's PPCContext,
//! and it skipped Xenia's real initialization, so the title's section stayed
//! zero-filled. A zero lock_count means "held", so the first contended Enter
//! on that section waited forever. Halo 3's Main XThread parked on
//! 0x40000610 fifteen seconds into that run, and no frame came in ten
//! minutes.
//!
//! ## The protocol
//!
//! This is exactly `xboxkrnl_rtl.cc`, run on the guest structure itself:
//! - lock_count (little-endian) is -1 when free; otherwise it counts the
//!   owner's recursion plus every waiter;
//! - recursion and owner are big-endian;
//! - the owner is the caller's X_KTHREAD (`XThread::guest_object()`), which
//!   Xenia keeps at PCR+0x100, and r13 holds the PCR.
//!
//! Only the embedded event differs. Xenia waits on a host XEvent that it
//! builds inside the dispatch header. Rosette parks the waiter in its
//! scheduler instead, and keeps the one pending wake of that auto-reset event
//! in the header's signal_state, which nothing else reads for a critical
//! section.
//!
//! Each section has one authority. Once the bridge is armed, every valid call
//! goes through it. The only fallbacks are a context or section Rosette cannot
//! read, where Xenia's own code faults the same way. A section is therefore
//! never entered by one implementation and released by the other.
//!
//! Uncontended Enter, Leave and TryEnter never take the runtime lock; they are
//! the same atomic operations Xenia performs. Only a counted waiter, and a
//! release that finds one, take it.

const std = @import("std");

pub const Layout = enum(u8) {
    windows,
    xbox360,
};

pub const Fields = struct {
    size: u8,
    lock_count: u8,
    recursion: u8,
    owner: u8,
    owner_bytes: u8,
};

pub fn fields(layout: Layout) Fields {
    return switch (layout) {
        .windows => .{ .size = 24, .lock_count = 8, .recursion = 12, .owner = 16, .owner_bytes = 8 },
        .xbox360 => .{ .size = 28, .lock_count = 16, .recursion = 20, .owner = 24, .owner_bytes = 4 },
    };
}

/// Byte offsets of `X_RTL_CRITICAL_SECTION` (`#pragma pack(1)`, 28 bytes).
pub const Offset = struct {
    /// `X_DISPATCH_HEADER.type`: 1, EventSynchronizationObject.
    pub const header_type: u8 = 0;
    /// `X_DISPATCH_HEADER.absolute`: the spin count divided by 256.
    pub const spin_div_256: u8 = 1;
    /// `X_DISPATCH_HEADER.signal_state`, big-endian: the embedded event.
    pub const signal_state: u8 = 4;
    pub const lock_count: u8 = 16;
    pub const recursion: u8 = 20;
    pub const owner: u8 = 24;
    pub const size: u8 = 28;
};

pub const event_synchronization_object: u8 = 1;
/// `lock_count` of a section nobody holds or waits for.
pub const free_lock_count: i32 = -1;
/// `X_KPCR.prcb_data.current_thread`, from the PCR in r13.
pub const pcr_current_thread: u32 = 0x100;
/// A title-chosen spin count can be 255*256; spinning past this many polls
/// only burns a core the owner may need. Parking is cheap once it is real.
pub const max_spin_polls: u32 = 4096;

/// What `enter` did. A counted caller has added itself to lock_count and must
/// wait for the embedded event before it owns the section.
pub const Entry = enum { acquired, recursed, counted };

/// What `leave` did. `waiters`: the section is free and lock_count still
/// counts at least one waiter, so the embedded event must be set.
pub const Release = enum { held, released, waiters };

pub const LeaveResult = struct {
    release: Release,
    /// False when the caller did not own the section with a positive
    /// recursion. Xenia only asserts this, and so does Rosette.
    owner_matched: bool,
};

/// `RtlInitializeCriticalSection` and `...AndSpinCount`, byte for byte.
/// Nothing else in the header changes, and the wait-list words are left
/// alone, exactly as Xenia leaves them.
pub fn initialize(access: anytype, spin_count: u32) void {
    access.fence();
    const spin_div_256: u8 = @intCast(@min(@as(u32, 255), (spin_count +% 255) >> 8));
    access.storeByte(Offset.header_type, event_synchronization_object);
    access.storeByte(Offset.spin_div_256, spin_div_256);
    access.storeBig(Offset.signal_state, 0);
    access.storeLock(free_lock_count);
    access.storeBig(Offset.recursion, 0);
    access.storeBig(Offset.owner, 0);
    access.fence();
}

/// `RtlEnterCriticalSection` up to, not including, its event wait.
///
/// Xenia first checks for recursion. It then spins spin_count times trying
/// to claim a free section without counting itself. Only then does it add
/// itself to lock_count, and it owns the section if that makes the count
/// zero. The spin here polls with plain loads before each claim, and it is
/// capped: a poll is cheap, and each claim is a locked operation.
pub fn enter(access: anytype, me: u32) Entry {
    access.fence();
    if (access.loadBig(Offset.owner) == me) {
        _ = access.lockFetchAdd(1);
        access.storeBig(Offset.recursion, access.loadBig(Offset.recursion) +% 1);
        access.fence();
        return .recursed;
    }
    var polls = @min(@as(u32, access.loadByte(Offset.spin_div_256)) * 256, max_spin_polls);
    while (polls != 0) : (polls -= 1) {
        if (access.loadLock() == free_lock_count and access.lockCompareExchange(free_lock_count, 0)) {
            take(access, me);
            return .acquired;
        }
        std.atomic.spinLoopHint();
    }
    if (access.lockFetchAdd(1) +% 1 == 0) {
        take(access, me);
        return .acquired;
    }
    return .counted;
}

/// `RtlTryEnterCriticalSection`: claim a free section or recurse; never count.
pub fn tryEnter(access: anytype, me: u32) bool {
    access.fence();
    if (access.lockCompareExchange(free_lock_count, 0)) {
        take(access, me);
        return true;
    }
    if (access.loadBig(Offset.owner) == me) {
        _ = access.lockFetchAdd(1);
        access.storeBig(Offset.recursion, access.loadBig(Offset.recursion) +% 1);
        access.fence();
        return true;
    }
    return false;
}

/// Ownership after an acquire, and after a counted waiter's wake.
pub fn take(access: anytype, me: u32) void {
    access.storeBig(Offset.owner, me);
    access.storeBig(Offset.recursion, 1);
    access.fence();
}

/// `RtlLeaveCriticalSection`. The protected stores are published before the
/// lock word moves, because the release is what other executors order
/// against.
pub fn leave(access: anytype, me: u32) LeaveResult {
    access.fence();
    const recursion_before: i32 = @bitCast(access.loadBig(Offset.recursion));
    const owner_matched = access.loadBig(Offset.owner) == me and recursion_before > 0;
    const recursion = recursion_before -% 1;
    access.storeBig(Offset.recursion, @bitCast(recursion));
    if (recursion != 0) {
        _ = access.lockFetchAdd(-1);
        access.fence();
        return .{ .release = .held, .owner_matched = owner_matched };
    }
    access.storeBig(Offset.owner, 0);
    const remaining = access.lockFetchAdd(-1) -% 1;
    access.fence();
    return .{ .release = if (remaining != free_lock_count) .waiters else .released, .owner_matched = owner_matched };
}

/// Take the embedded event's pending wake, if a release left one. The
/// caller holds the runtime lock; every set and consume happens under it.
pub fn consumeSignal(access: anytype) bool {
    if (access.loadBig(Offset.signal_state) == 0) return false;
    access.storeBig(Offset.signal_state, 0);
    return true;
}

/// Leave the embedded event set for a waiter that has counted itself but has
/// not parked yet: the auto-reset event holds exactly one wake.
pub fn setSignal(access: anytype) void {
    access.storeBig(Offset.signal_state, 1);
}

/// What one section's structure says, for a report.
pub const Snapshot = struct {
    header_type: u8,
    signal_state: i32,
    lock_count: i32,
    recursion: i32,
    owner: u32,

    /// The lock state Xenia's own implementation can never leave behind: a
    /// count of holders or waiters with no holder, no pending wake, and no
    /// release in flight. A section that was never initialized (all zero)
    /// reads this way, which is how the 2026-09-26 stall looked.
    pub fn strandedWaiter(self: Snapshot) bool {
        return self.owner == 0 and self.recursion == 0 and self.lock_count >= 0 and self.signal_state == 0;
    }

    pub fn initialized(self: Snapshot) bool {
        return self.header_type == event_synchronization_object;
    }
};

pub fn readSnapshot(bytes: []const u8) ?Snapshot {
    if (bytes.len < Offset.size) return null;
    return .{
        .header_type = bytes[Offset.header_type],
        .signal_state = std.mem.readInt(i32, bytes[Offset.signal_state..][0..4], .big),
        .lock_count = std.mem.readInt(i32, bytes[Offset.lock_count..][0..4], .little),
        .recursion = std.mem.readInt(i32, bytes[Offset.recursion..][0..4], .big),
        .owner = std.mem.readInt(u32, bytes[Offset.owner..][0..4], .big),
    };
}

/// Counters shared by every executor. The fast paths run without the
/// runtime lock, so each bump is atomic.
pub const Stats = struct {
    acquired: u64 = 0,
    recursed: u64 = 0,
    counted: u64 = 0,
    parks: u64 = 0,
    grants: u64 = 0,
    signals: u64 = 0,
    signals_consumed: u64 = 0,
    try_failures: u64 = 0,
    leave_mismatches: u64 = 0,
    null_sections: u64 = 0,
    synthetic_owners: u64 = 0,
    initializations: u64 = 0,

    pub fn bump(counter: *u64) void {
        _ = @atomicRmw(u64, counter, .Add, 1, .monotonic);
    }

    pub fn read(counter: *const u64) u64 {
        return @atomicLoad(u64, counter, .monotonic);
    }
};

pub const Export = enum(u8) {
    initialize,
    initialize_and_spin_count,
    enter,
    try_enter,
    leave,

    pub const count = @typeInfo(Export).@"enum".fields.len;

    pub fn name(self: Export) []const u8 {
        return switch (self) {
            .initialize => "RtlInitializeCriticalSection",
            .initialize_and_spin_count => "RtlInitializeCriticalSectionAndSpinCount",
            .enter => "RtlEnterCriticalSection",
            .try_enter => "RtlTryEnterCriticalSection",
            .leave => "RtlLeaveCriticalSection",
        };
    }

    pub fn fromName(name_text: []const u8) ?Export {
        inline for (@typeInfo(Export).@"enum".fields) |field| {
            const api: Export = @enumFromInt(field.value);
            if (std.mem.eql(u8, name_text, api.name())) return api;
        }
        return null;
    }
};

/// Fixed-address dispatch table populated while Rosetta arms Xenia's PE
/// kernel-export census. The hot step path checks only these five addresses.
pub const Hooks = struct {
    addresses: [Export.count]u64 = @splat(0),
    calls: [Export.count]u64 = @splat(0),
    fallbacks: [Export.count]u64 = @splat(0),

    pub fn arm(self: *Hooks, export_name: []const u8, address: u64) bool {
        const api = Export.fromName(export_name) orelse return false;
        if (address == 0) return false;
        self.addresses[@intFromEnum(api)] = address;
        return true;
    }

    pub fn at(self: *const Hooks, address: u64) ?Export {
        if (address == 0) return null;
        inline for (@typeInfo(Export).@"enum".fields) |field| {
            const api: Export = @enumFromInt(field.value);
            if (self.addresses[@intFromEnum(api)] == address) return api;
        }
        return null;
    }

    pub fn noteHandled(self: *Hooks, api: Export) void {
        Stats.bump(&self.calls[@intFromEnum(api)]);
    }

    pub fn noteFallback(self: *Hooks, api: Export) void {
        Stats.bump(&self.fallbacks[@intFromEnum(api)]);
    }
};

/// A 28-byte section in plain memory, for the protocol's tests.
const TestSection = struct {
    bytes: [Offset.size]u8 = @splat(0),

    const Access = struct {
        section: *TestSection,

        pub fn fence(_: Access) void {}
        pub fn loadByte(self: Access, offset: u8) u8 {
            return self.section.bytes[offset];
        }
        pub fn storeByte(self: Access, offset: u8, value: u8) void {
            self.section.bytes[offset] = value;
        }
        pub fn loadBig(self: Access, offset: u8) u32 {
            return std.mem.readInt(u32, self.section.bytes[offset..][0..4], .big);
        }
        pub fn storeBig(self: Access, offset: u8, value: u32) void {
            std.mem.writeInt(u32, self.section.bytes[offset..][0..4], value, .big);
        }
        pub fn loadLock(self: Access) i32 {
            return std.mem.readInt(i32, self.section.bytes[Offset.lock_count..][0..4], .little);
        }
        pub fn storeLock(self: Access, value: i32) void {
            std.mem.writeInt(i32, self.section.bytes[Offset.lock_count..][0..4], value, .little);
        }
        pub fn lockFetchAdd(self: Access, delta: i32) i32 {
            const previous = self.loadLock();
            self.storeLock(previous +% delta);
            return previous;
        }
        pub fn lockCompareExchange(self: Access, expected: i32, desired: i32) bool {
            if (self.loadLock() != expected) return false;
            self.storeLock(desired);
            return true;
        }
    };

    fn access(self: *TestSection) Access {
        return .{ .section = self };
    }

    fn snapshot(self: *const TestSection) Snapshot {
        return readSnapshot(&self.bytes).?;
    }
};

test "Xbox critical section layout matches its packed 28-byte contract" {
    const xbox = fields(.xbox360);
    try std.testing.expectEqual(@as(u8, 28), xbox.size);
    try std.testing.expectEqual(Offset.lock_count, xbox.lock_count);
    try std.testing.expectEqual(Offset.recursion, xbox.recursion);
    try std.testing.expectEqual(Offset.owner, xbox.owner);
    try std.testing.expectEqual(@as(u8, 4), xbox.owner_bytes);
}

test "initialize writes Xenia's header and a free lock, and packs the spin count" {
    var section: TestSection = .{};
    @memset(&section.bytes, 0xAA);
    initialize(section.access(), 4000);
    const state = section.snapshot();
    try std.testing.expect(state.initialized());
    try std.testing.expectEqual(@as(u8, 16), section.bytes[Offset.spin_div_256]);
    try std.testing.expectEqual(@as(i32, 0), state.signal_state);
    try std.testing.expectEqual(free_lock_count, state.lock_count);
    try std.testing.expectEqual(@as(i32, 0), state.recursion);
    try std.testing.expectEqual(@as(u32, 0), state.owner);
    // The wait-list words are Xenia's to keep.
    try std.testing.expectEqual(@as(u8, 0xAA), section.bytes[8]);
    initialize(section.access(), 0xFFFF_FFFF);
    try std.testing.expectEqual(@as(u8, 0), section.bytes[Offset.spin_div_256]);
    initialize(section.access(), 0x0100_0000);
    try std.testing.expectEqual(@as(u8, 255), section.bytes[Offset.spin_div_256]);
}

test "enter, recurse and leave follow Xenia's lock_count arithmetic" {
    var section: TestSection = .{};
    initialize(section.access(), 0);
    const me: u32 = 0x7000_0100;
    try std.testing.expectEqual(Entry.acquired, enter(section.access(), me));
    try std.testing.expectEqual(@as(i32, 0), section.snapshot().lock_count);
    try std.testing.expectEqual(Entry.recursed, enter(section.access(), me));
    try std.testing.expectEqual(@as(i32, 1), section.snapshot().lock_count);
    try std.testing.expectEqual(@as(i32, 2), section.snapshot().recursion);
    try std.testing.expect(tryEnter(section.access(), me));
    try std.testing.expectEqual(@as(i32, 3), section.snapshot().recursion);

    var result = leave(section.access(), me);
    try std.testing.expectEqual(Release.held, result.release);
    try std.testing.expect(result.owner_matched);
    result = leave(section.access(), me);
    try std.testing.expectEqual(Release.held, result.release);
    result = leave(section.access(), me);
    try std.testing.expectEqual(Release.released, result.release);
    const state = section.snapshot();
    try std.testing.expectEqual(free_lock_count, state.lock_count);
    try std.testing.expectEqual(@as(u32, 0), state.owner);
    try std.testing.expectEqual(@as(i32, 0), state.recursion);
}

test "a contended enter counts itself and the release reports the waiter" {
    var section: TestSection = .{};
    initialize(section.access(), 0);
    const holder: u32 = 0x7000_0100;
    const waiter: u32 = 0x7000_0200;
    try std.testing.expectEqual(Entry.acquired, enter(section.access(), holder));
    try std.testing.expect(!tryEnter(section.access(), waiter));
    try std.testing.expectEqual(Entry.counted, enter(section.access(), waiter));
    try std.testing.expectEqual(@as(i32, 1), section.snapshot().lock_count);

    const result = leave(section.access(), holder);
    try std.testing.expectEqual(Release.waiters, result.release);
    // Free, with the waiter still counted: a claim cannot jump the queue.
    try std.testing.expectEqual(@as(u32, 0), section.snapshot().owner);
    try std.testing.expect(!tryEnter(section.access(), 0x7000_0300));

    // The release sets the event; the waiter consumes it exactly once.
    setSignal(section.access());
    try std.testing.expect(!section.snapshot().strandedWaiter());
    try std.testing.expect(consumeSignal(section.access()));
    try std.testing.expect(!consumeSignal(section.access()));
    take(section.access(), waiter);
    try std.testing.expectEqual(waiter, section.snapshot().owner);
    try std.testing.expectEqual(@as(i32, 0), section.snapshot().lock_count);
    try std.testing.expectEqual(Release.released, leave(section.access(), waiter).release);
    try std.testing.expectEqual(free_lock_count, section.snapshot().lock_count);
}

test "a zero-filled section reads as a stranded waiter once entered" {
    // What the misread trampoline left behind: Xenia's initialization was
    // skipped, so lock_count 0 already means "held" and the first Enter
    // counts itself behind nobody.
    var section: TestSection = .{};
    try std.testing.expect(!section.snapshot().initialized());
    try std.testing.expectEqual(Entry.counted, enter(section.access(), 0x7000_0100));
    try std.testing.expect(section.snapshot().strandedWaiter());
}

test "a leave by a thread that does not own the section is reported" {
    var section: TestSection = .{};
    initialize(section.access(), 0);
    try std.testing.expectEqual(Entry.acquired, enter(section.access(), 0x7000_0100));
    const result = leave(section.access(), 0x7000_0200);
    try std.testing.expect(!result.owner_matched);
    try std.testing.expectEqual(Release.released, result.release);
}

test "the spin claims a section freed without counting the spinner" {
    var section: TestSection = .{};
    initialize(section.access(), 256);
    try std.testing.expectEqual(Entry.acquired, enter(section.access(), 0x7000_0100));
    _ = leave(section.access(), 0x7000_0100);
    try std.testing.expectEqual(Entry.acquired, enter(section.access(), 0x7000_0200));
    try std.testing.expectEqual(@as(i32, 0), section.snapshot().lock_count);
}

test "only the armed Xbox critical section export entry points are hooked" {
    var hooks: Hooks = .{};
    try std.testing.expect(hooks.arm("RtlEnterCriticalSection", 0x1400_1000));
    try std.testing.expect(!hooks.arm("KeWaitForSingleObject", 0x1400_2000));
    try std.testing.expectEqual(Export.enter, hooks.at(0x1400_1000).?);
    try std.testing.expect(hooks.at(0x1400_1001) == null);
    hooks.noteHandled(.enter);
    hooks.noteFallback(.enter);
    try std.testing.expectEqual(@as(u64, 1), Stats.read(&hooks.calls[@intFromEnum(Export.enter)]));
    try std.testing.expectEqual(@as(u64, 1), Stats.read(&hooks.fallbacks[@intFromEnum(Export.enter)]));
}
