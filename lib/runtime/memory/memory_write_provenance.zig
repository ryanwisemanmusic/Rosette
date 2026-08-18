const std = @import("std");

pub const MAX_TRACKED_SLOTS: usize = 131_072;
pub const MAX_MUTATION_SLOTS: usize = 256;

pub const WriteKind = enum {
    scalar,
    partial_scalar,
    bulk_fill,
    bulk_copy,
    /// One 128-bit guest store. A compiler-inlined `memset`/copy never reaches
    /// the `memset`/`memcpy` import handlers, so this is the only kind that
    /// names the vector unit as the writer.
    vector_store,
    /// Written by Rosette itself while repairing a fault, not by the guest.
    ///
    /// Provenance records the *faulting guest RIP* as the writer, because that
    /// is what `regs.rip` holds when a recovery runs. Without this kind the
    /// ledger cannot distinguish a repair from guest behaviour, and every
    /// consumer — most visibly the near-null causality chain's
    /// `producer_last_writer` line — attributes Rosette's own write to a guest
    /// symbol. Any conclusion drawn from such an entry is about the emulator,
    /// not the program.
    host_repair,
};

/// True when the entry describes a write Rosette performed, so callers can
/// refuse to draw guest-side conclusions from it.
pub fn isHostAuthored(kind: WriteKind) bool {
    return kind == .host_repair;
}

pub const Entry = struct {
    address: u64,
    previous_value: u64,
    value: u64,
    instruction_address: u64,
    step: u64,
    thread: u64,
    kind: WriteKind,
};

pub const MutationSlot = struct {
    address: u64,
    value: u64,
};

/// A bounded before-image of the pointer-sized slots touched by a mutation.
/// Small writes capture every overlapping slot. Large writes capture every
/// already-tracked slot in the range, which is the useful set for explaining
/// a live-pointer casualty without scanning multi-megabyte buffers.
pub const MutationCapture = struct {
    address: u64,
    length: u64,
    slots: [MAX_MUTATION_SLOTS]MutationSlot = undefined,
    count: usize = 0,
    truncated: bool = false,
};

pub const Tracker = struct {
    entries: std.AutoHashMapUnmanaged(u64, Entry) = .empty,
    // Keep one displaced writer per slot. Near-null failures are commonly
    // discovered after a container or allocator has cleared a pointer, and a
    // single "last writer" record loses the initialization that the clear
    // replaced. Two generations are enough to distinguish an ordinary null
    // initialization from a live-pointer casualty without turning this into a
    // full write trace.
    previous_entries: std.AutoHashMapUnmanaged(u64, Entry) = .empty,
    dropped_slots: u64 = 0,
    range_mutations: u64 = 0,
    truncated_range_mutations: u64 = 0,

    pub fn deinit(self: *Tracker, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
        self.previous_entries.deinit(allocator);
    }

    pub fn record(
        self: *Tracker,
        allocator: std.mem.Allocator,
        address: u64,
        previous_value: u64,
        value: u64,
        instruction_address: u64,
        step: u64,
        thread: u64,
    ) void {
        self.recordKind(
            allocator,
            address,
            previous_value,
            value,
            instruction_address,
            step,
            thread,
            .scalar,
        );
    }

    pub fn recordKind(
        self: *Tracker,
        allocator: std.mem.Allocator,
        address: u64,
        previous_value: u64,
        value: u64,
        instruction_address: u64,
        step: u64,
        thread: u64,
        kind: WriteKind,
    ) void {
        if (address < 0x1000 or (address & 7) != 0) return;
        // Retain pointer-bearing transitions rather than every integer store.
        // A clear of a pointer is still retained because its previous value is
        // pointer-sized, while bulk initialization with zero stays cheap.
        if (previous_value < 0x1000 and value < 0x1000) return;

        const entry = Entry{
            .address = address,
            .previous_value = previous_value,
            .value = value,
            .instruction_address = instruction_address,
            .step = step,
            .thread = thread,
            .kind = kind,
        };
        if (self.entries.getPtr(address)) |existing| {
            self.previous_entries.put(allocator, address, existing.*) catch {
                self.dropped_slots +|= 1;
            };
            existing.* = entry;
            return;
        }
        if (self.entries.count() >= MAX_TRACKED_SLOTS) {
            self.dropped_slots +|= 1;
            return;
        }
        self.entries.put(allocator, address, entry) catch {
            self.dropped_slots +|= 1;
        };
    }

    pub fn captureMutation(
        self: *const Tracker,
        state: anytype,
        address: u64,
        length: u64,
    ) MutationCapture {
        var capture = MutationCapture{ .address = address, .length = length };
        if (length == 0) return capture;
        const end = std.math.add(u64, address, length) catch std.math.maxInt(u64);
        const first_slot = address & ~@as(u64, 7);
        const last_byte = end -| 1;
        const last_slot = last_byte & ~@as(u64, 7);
        const slot_count = ((last_slot -| first_slot) / 8) + 1;

        if (slot_count <= MAX_MUTATION_SLOTS) {
            var slot = first_slot;
            while (slot <= last_slot) : (slot +|= 8) {
                captureSlot(state, &capture, slot);
                if (slot == last_slot) break;
            }
            return capture;
        }

        // For a large buffer, retain before-images for the pointer slots that
        // already have causal history. This catches the important case where
        // memset/memcpy partially or wholly destroys a live pointer.
        var iterator = self.entries.iterator();
        while (iterator.next()) |tracked| {
            const slot = tracked.key_ptr.*;
            if (slot +| 8 <= address or slot >= end) continue;
            if (capture.count == MAX_MUTATION_SLOTS) {
                capture.truncated = true;
                break;
            }
            capture.slots[capture.count] = .{
                .address = slot,
                .value = readSlot(state, slot) orelse continue,
            };
            capture.count += 1;
        }
        return capture;
    }

    pub fn commitMutation(
        self: *Tracker,
        allocator: std.mem.Allocator,
        state: anytype,
        capture: MutationCapture,
        instruction_address: u64,
        step: u64,
        thread: u64,
        kind: WriteKind,
    ) void {
        if (capture.length == 0) return;
        self.range_mutations +|= 1;
        if (capture.truncated) self.truncated_range_mutations +|= 1;
        for (capture.slots[0..capture.count]) |slot| {
            const value = readSlot(state, slot.address) orelse continue;
            if (value == slot.value) continue;
            self.recordKind(
                allocator,
                slot.address,
                slot.value,
                value,
                instruction_address,
                step,
                thread,
                kind,
            );
        }
    }

    pub fn lookup(self: *const Tracker, address: u64) ?Entry {
        return self.entries.get(address);
    }

    pub fn lookupPrevious(self: *const Tracker, address: u64) ?Entry {
        return self.previous_entries.get(address);
    }

    pub fn forget(self: *Tracker, address: u64) void {
        _ = self.entries.remove(address);
        _ = self.previous_entries.remove(address);
    }

    /// Retires every pointer slot in an allocation when its storage is reused.
    /// Clearing only the base leaves member provenance (base+8, base+16, ...)
    /// attached to an unrelated object and makes a later null look like a
    /// collision casualty from the prior allocation.
    pub fn forgetRange(
        self: *Tracker,
        allocator: std.mem.Allocator,
        address: u64,
        length: u64,
    ) void {
        if (length == 0) return;
        const end = std.math.add(u64, address, length) catch std.math.maxInt(u64);
        const first_slot = address & ~@as(u64, 7);
        const last_slot = (end -| 1) & ~@as(u64, 7);
        const slot_count = ((last_slot -| first_slot) / 8) + 1;

        // Most forwarded allocations are small. Direct key removal avoids a
        // full tracker scan on their hot allocation path.
        if (slot_count <= 4096) {
            var slot = first_slot;
            while (slot <= last_slot) : (slot +|= 8) {
                self.forget(slot);
                if (slot == last_slot) break;
            }
            return;
        }

        // Huge allocations may cover millions of potential slots. Walk only
        // retained provenance and remove matching keys after iteration.
        var keys: std.ArrayListUnmanaged(u64) = .empty;
        defer keys.deinit(allocator);
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            const slot = entry.key_ptr.*;
            if (slot < first_slot or slot > last_slot) continue;
            keys.append(allocator, slot) catch {
                self.dropped_slots +|= 1;
                break;
            };
        }
        for (keys.items) |slot| self.forget(slot);
    }

    /// Returns the most recent non-null value associated with a tracked slot.
    /// If the last observed write cleared the slot, the value immediately
    /// preceding that clear is returned. Callers must independently validate
    /// that the value is meaningful for their domain before using it.
    pub fn lastNonNullValue(self: *const Tracker, address: u64) ?u64 {
        const entry = self.lookup(address) orelse return null;
        if (entry.value >= 0x1000) return entry.value;
        if (entry.previous_value >= 0x1000) return entry.previous_value;
        return null;
    }
};

fn readSlot(state: anytype, address: u64) ?u64 {
    const bytes = state.guestMemoryConst(address, 8) orelse return null;
    return std.mem.readInt(u64, bytes[0..8], .little);
}

fn captureSlot(state: anytype, capture: *MutationCapture, address: u64) void {
    if (capture.count == MAX_MUTATION_SLOTS) {
        capture.truncated = true;
        return;
    }
    const value = readSlot(state, address) orelse return;
    capture.slots[capture.count] = .{ .address = address, .value = value };
    capture.count += 1;
}

test "memory write provenance retains the last writer for a slot" {
    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);

    tracker.record(std.testing.allocator, 0x4000, 0x1234, 0, 0x2000, 77, 9);
    const entry = tracker.lookup(0x4000).?;
    try std.testing.expectEqual(@as(u64, 0x1234), entry.previous_value);
    try std.testing.expectEqual(@as(u64, 0), entry.value);
    try std.testing.expectEqual(@as(u64, 0x2000), entry.instruction_address);
    try std.testing.expectEqual(@as(u64, 77), entry.step);
    try std.testing.expectEqual(@as(u64, 9), entry.thread);
}

test "memory write provenance updates existing slots" {
    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);

    tracker.record(std.testing.allocator, 0x8000, 0, 0x2000, 3, 4, 5);
    tracker.record(std.testing.allocator, 0x8000, 0x2000, 0x6000, 7, 8, 9);
    try std.testing.expectEqual(@as(usize, 1), tracker.entries.count());
    try std.testing.expectEqual(@as(u64, 0x6000), tracker.lookup(0x8000).?.value);
    const previous = tracker.lookupPrevious(0x8000).?;
    try std.testing.expectEqual(@as(u64, 0x2000), previous.value);
    try std.testing.expectEqual(@as(u64, 3), previous.instruction_address);
}

test "forget retires both writer generations" {
    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);

    tracker.record(std.testing.allocator, 0xA000, 0, 0x2000, 1, 2, 3);
    tracker.record(std.testing.allocator, 0xA000, 0x2000, 0, 4, 5, 6);
    tracker.forget(0xA000);
    try std.testing.expect(tracker.lookup(0xA000) == null);
    try std.testing.expect(tracker.lookupPrevious(0xA000) == null);
}

test "forgetRange retires allocation member provenance" {
    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);

    tracker.record(std.testing.allocator, 0xA000, 0, 0x2000, 1, 2, 3);
    tracker.record(std.testing.allocator, 0xA008, 0, 0x3000, 4, 5, 6);
    tracker.record(std.testing.allocator, 0xA018, 0, 0x4000, 7, 8, 9);
    tracker.forgetRange(std.testing.allocator, 0xA000, 16);

    try std.testing.expect(tracker.lookup(0xA000) == null);
    try std.testing.expect(tracker.lookup(0xA008) == null);
    try std.testing.expect(tracker.lookup(0xA018) != null);
}

test "memory write provenance retains a non-null recovery candidate" {
    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);

    tracker.record(std.testing.allocator, 0x9000, 0x1234, 0, 7, 8, 9);
    try std.testing.expectEqual(@as(u64, 0x1234), tracker.lastNonNullValue(0x9000).?);

    tracker.record(std.testing.allocator, 0x9000, 0, 0x5678, 10, 11, 12);
    try std.testing.expectEqual(@as(u64, 0x5678), tracker.lastNonNullValue(0x9000).?);
}

test "partial mutation records the containing pointer slot" {
    const TestState = struct {
        memory: [16]u8 = [_]u8{0} ** 16,

        fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
            const offset: usize = @intCast(address - 0x4000);
            const count: usize = @intCast(length);
            if (offset + count > self.memory.len) return null;
            return self.memory[offset..][0..count];
        }
    };

    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);
    var state = TestState{};
    std.mem.writeInt(u64, state.memory[0..8], 0x1234, .little);

    const capture = tracker.captureMutation(&state, 0x4001, 1);
    state.memory[1] = 0;
    tracker.commitMutation(
        std.testing.allocator,
        &state,
        capture,
        0x2000,
        42,
        7,
        .partial_scalar,
    );

    const entry = tracker.lookup(0x4000).?;
    try std.testing.expectEqual(@as(u64, 0x1234), entry.previous_value);
    try std.testing.expectEqual(@as(u64, 0x34), entry.value);
    try std.testing.expectEqual(WriteKind.partial_scalar, entry.kind);
}

test "bulk clear records an existing pointer casualty" {
    const TestState = struct {
        memory: [32]u8 = [_]u8{0} ** 32,

        fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
            const offset: usize = @intCast(address - 0x8000);
            const count: usize = @intCast(length);
            if (offset + count > self.memory.len) return null;
            return self.memory[offset..][0..count];
        }
    };

    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);
    var state = TestState{};
    std.mem.writeInt(u64, state.memory[8..16], 0xA000, .little);
    tracker.record(std.testing.allocator, 0x8008, 0, 0xA000, 1, 2, 3);

    const capture = tracker.captureMutation(&state, 0x8000, 24);
    @memset(state.memory[0..24], 0);
    tracker.commitMutation(
        std.testing.allocator,
        &state,
        capture,
        4,
        5,
        6,
        .bulk_fill,
    );

    const entry = tracker.lookup(0x8008).?;
    try std.testing.expectEqual(@as(u64, 0xA000), entry.previous_value);
    try std.testing.expectEqual(@as(u64, 0), entry.value);
    try std.testing.expectEqual(WriteKind.bulk_fill, entry.kind);
}

// A compiler-inlined zero fill never calls `memset`, so the ledger only ever
// sees it as a run of sixteen-byte vector stores. Recording those under their
// own kind is what separates "the guest called memset on this object" from "the
// vector unit wrote over it", which are different bugs: the first names a
// length or a destination, the second names an inlined loop.
test "a vector store records the pointer casualties in its sixteen bytes" {
    const TestState = struct {
        memory: [32]u8 = [_]u8{0} ** 32,

        fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
            const offset: usize = @intCast(address - 0x8000);
            const count: usize = @intCast(length);
            if (offset + count > self.memory.len) return null;
            return self.memory[offset..][0..count];
        }
    };

    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);
    var state = TestState{};
    // A live object's vptr at +0x0 and the ownership pointer at +0x8 — the pair
    // the near-null casualty is made of.
    std.mem.writeInt(u64, state.memory[0..8], 0x1983888, .little);
    std.mem.writeInt(u64, state.memory[8..16], 0x17a47660, .little);
    tracker.record(std.testing.allocator, 0x8000, 0, 0x1983888, 1, 2, 3);
    tracker.record(std.testing.allocator, 0x8008, 0, 0x17a47660, 1, 2, 3);

    const capture = tracker.captureMutation(&state, 0x8000, 16);
    @memset(state.memory[0..16], 0);
    tracker.commitMutation(std.testing.allocator, &state, capture, 0x20fe9c, 1_891_981_829, 0x7fff20e0, .vector_store);

    const vptr = tracker.lookup(0x8000).?;
    try std.testing.expectEqual(@as(u64, 0x1983888), vptr.previous_value);
    try std.testing.expectEqual(@as(u64, 0), vptr.value);
    try std.testing.expectEqual(WriteKind.vector_store, vptr.kind);
    try std.testing.expectEqual(@as(u64, 0x20fe9c), vptr.instruction_address);

    // The field beside the vptr is the one the next member call dereferences,
    // so its before-image has to survive too or the rollback has nothing to
    // restore.
    const owner = tracker.lookup(0x8008).?;
    try std.testing.expectEqual(@as(u64, 0x17a47660), owner.previous_value);
    try std.testing.expectEqual(@as(u64, 0), owner.value);
    try std.testing.expectEqual(WriteKind.vector_store, owner.kind);

    // A vector store is guest behaviour, not a Rosette repair.
    try std.testing.expect(!isHostAuthored(vptr.kind));
}
