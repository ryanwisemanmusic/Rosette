//! Reservations, reads and the guest memory map, with short answers refused
//! rather than tolerated.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run contains an occupied-range fallback in the Rosette heap
//! selector, sparse fixed-mmap recovery, short `pread` warnings, and ignored
//! file-allocation requests. Each may be a benign compatibility path. None of
//! them can be *assumed* benign while a graphics audit is reading the XISO,
//! the shader cache and the physical heap as if the bytes are what the title
//! asked for.
//!
//! A short read that silently becomes valid XEX, shader, texture or command
//! data does not fail loudly. It produces a plausible structure with wrong
//! contents, and every conclusion drawn downstream is about the wrong bytes.
//!
//! So a read returns the requested length or a named result. There is no
//! partial success: `short` is its own outcome, it is counted, and a run with
//! one on the graphics dependency chain cannot claim a clean baseline.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const Address = bridge.contract.Address;

/// What a range is reserved for. Fallbacks matter differently depending on
/// what the range carries.
pub const Purpose = enum(u8) {
    physical_heap = 0,
    ring = 1,
    command_buffer = 2,
    edram_model = 3,
    shader_storage = 4,
    texture_storage = 5,
    frontbuffer = 6,
    executable_image = 7,
    other = 255,

    pub fn label(self: Purpose) []const u8 {
        return switch (self) {
            .physical_heap => "physical-heap",
            .ring => "ring",
            .command_buffer => "command-buffer",
            .edram_model => "edram-model",
            .shader_storage => "shader-storage",
            .texture_storage => "texture-storage",
            .frontbuffer => "frontbuffer",
            .executable_image => "executable-image",
            .other => "other",
        };
    }

    /// Whether this range is on the path between a title's commands and a
    /// frame. A fallback here invalidates a graphics conclusion; one
    /// elsewhere does not.
    pub fn onGraphicsChain(self: Purpose) bool {
        return switch (self) {
            .physical_heap, .ring, .command_buffer, .edram_model, .shader_storage, .texture_storage, .frontbuffer, .executable_image => true,
            .other => false,
        };
    }
};

/// How a reservation turned out.
pub const ReservationOutcome = enum(u8) {
    /// Got exactly what it asked for.
    exact = 0,
    /// Got the size at a different address.
    relocated = 1,
    /// Got less than it asked for.
    truncated = 2,
    /// The requested range was occupied and a fallback was used.
    fallback = 3,
    /// Nothing was reserved.
    failed = 4,

    pub fn label(self: ReservationOutcome) []const u8 {
        return switch (self) {
            .exact => "exact",
            .relocated => "relocated",
            .truncated => "TRUNCATED",
            .fallback => "fallback",
            .failed => "FAILED",
        };
    }

    /// Whether the caller got a range that means what it asked for.
    pub fn honoured(self: ReservationOutcome) bool {
        return self == .exact or self == .relocated;
    }

    pub fn isDefect(self: ReservationOutcome) bool {
        return self == .truncated or self == .failed;
    }
};

pub const Reservation = struct {
    purpose: Purpose = .other,
    requested_address: u64 = 0,
    requested_bytes: u64 = 0,
    actual_address: u64 = 0,
    actual_bytes: u64 = 0,
    alignment: u32 = 0,
    outcome: ReservationOutcome = .exact,
    /// Why a fallback was taken, when one was.
    reason: []const u8 = "",
    generation: u64 = 0,
    step: u64 = 0,

    pub fn sizeHonoured(self: Reservation) bool {
        return self.actual_bytes >= self.requested_bytes;
    }
};

/// How a read turned out. There is no partial success.
pub const ReadOutcome = enum(u8) {
    /// Every requested byte was returned.
    complete = 0,
    /// The source ended before the request did, and the caller was told.
    end_of_file = 1,
    /// Fewer bytes than requested, with no end-of-file to explain it.
    short = 2,
    /// The read failed outright.
    failed = 3,

    pub fn label(self: ReadOutcome) []const u8 {
        return switch (self) {
            .complete => "complete",
            .end_of_file => "end-of-file",
            .short => "SHORT",
            .failed => "FAILED",
        };
    }

    pub fn describe(self: ReadOutcome) []const u8 {
        return switch (self) {
            .complete => "every requested byte was returned",
            .end_of_file => "the source ended before the request did, and the caller was told so. A caller that handles this is correct; one that does not gets a named result rather than silent short data",
            .short => "fewer bytes came back than were asked for and nothing explains why. A short read that silently becomes valid XEX, shader, texture or command data produces a plausible structure with wrong contents, and every conclusion drawn from it is about the wrong bytes",
            .failed => "the read failed. Nothing was produced and the caller knows it",
        };
    }

    pub fn usable(self: ReadOutcome) bool {
        return self == .complete;
    }

    pub fn isDefect(self: ReadOutcome) bool {
        return self == .short;
    }
};

pub const Read = struct {
    purpose: Purpose = .other,
    /// Source offset, and the sector when the source is an image.
    offset: u64 = 0,
    sector: u64 = 0,
    requested_bytes: u64 = 0,
    returned_bytes: u64 = 0,
    checksum: u64 = 0,
    retries: u32 = 0,
    outcome: ReadOutcome = .complete,
    step: u64 = 0,

    /// The outcome the byte counts imply, so a caller cannot label a short
    /// read complete.
    pub fn impliedOutcome(self: Read, at_end_of_source: bool) ReadOutcome {
        if (self.returned_bytes == self.requested_bytes) return .complete;
        if (self.returned_bytes == 0) return .failed;
        return if (at_end_of_source) .end_of_file else .short;
    }
};

pub const max_reservations: usize = 24;
pub const max_reads: usize = 24;

pub const Summary = struct {
    reservations: usize = 0,
    reservations_dropped: u64 = 0,
    fallbacks: u64 = 0,
    reservation_defects: u64 = 0,
    fallbacks_on_chain: u64 = 0,

    reads: usize = 0,
    reads_dropped: u64 = 0,
    total_reads: u64 = 0,
    short_reads: u64 = 0,
    failed_reads: u64 = 0,
    short_reads_on_chain: u64 = 0,
    bytes_requested: u64 = 0,
    bytes_returned: u64 = 0,

    /// The audit's G0 criterion: no unclassified storage short read,
    /// reservation fallback or import fallback on the graphics chain.
    pub fn baselineClean(self: Summary) bool {
        return self.short_reads_on_chain == 0 and
            self.failed_reads == 0 and
            self.reservation_defects == 0 and
            self.fallbacks_on_chain == 0;
    }
};

pub const Ledger = struct {
    reservations: [max_reservations]Reservation = [_]Reservation{.{}} ** max_reservations,
    reservation_count: usize = 0,
    reservations_dropped: u64 = 0,

    reads: [max_reads]Read = [_]Read{.{}} ** max_reads,
    read_count: usize = 0,
    read_write_index: usize = 0,
    reads_dropped: u64 = 0,

    total_reads: u64 = 0,
    short_reads: u64 = 0,
    failed_reads: u64 = 0,
    short_reads_on_chain: u64 = 0,
    bytes_requested: u64 = 0,
    bytes_returned: u64 = 0,
    next_generation: u64 = 1,

    pub fn reserve(self: *Ledger, reservation: Reservation) ?*Reservation {
        if (self.reservation_count >= max_reservations) {
            self.reservations_dropped +|= 1;
            return null;
        }
        const slot = &self.reservations[self.reservation_count];
        self.reservation_count += 1;
        slot.* = reservation;
        slot.generation = self.next_generation;
        self.next_generation += 1;
        return slot;
    }

    /// Record a read and classify it from its own byte counts. The caller does
    /// not get to say a short read was complete.
    pub fn read(self: *Ledger, entry: Read, at_end_of_source: bool) ReadOutcome {
        self.total_reads +|= 1;
        self.bytes_requested +|= entry.requested_bytes;
        self.bytes_returned +|= entry.returned_bytes;

        var stamped = entry;
        stamped.outcome = entry.impliedOutcome(at_end_of_source);
        switch (stamped.outcome) {
            .short => {
                self.short_reads +|= 1;
                if (stamped.purpose.onGraphicsChain()) self.short_reads_on_chain +|= 1;
            },
            .failed => self.failed_reads +|= 1,
            else => {},
        }

        if (self.read_count >= max_reads) self.reads_dropped +|= 1;
        self.reads[self.read_write_index] = stamped;
        self.read_write_index = (self.read_write_index + 1) % max_reads;
        if (self.read_count < max_reads) self.read_count += 1;
        return stamped.outcome;
    }

    pub fn retainedReservations(self: *const Ledger) []const Reservation {
        return self.reservations[0..self.reservation_count];
    }

    pub fn retainedReads(self: *const Ledger) []const Read {
        return self.reads[0..self.read_count];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{
            .reservations = self.reservation_count,
            .reservations_dropped = self.reservations_dropped,
            .reads = self.read_count,
            .reads_dropped = self.reads_dropped,
            .total_reads = self.total_reads,
            .short_reads = self.short_reads,
            .failed_reads = self.failed_reads,
            .short_reads_on_chain = self.short_reads_on_chain,
            .bytes_requested = self.bytes_requested,
            .bytes_returned = self.bytes_returned,
        };
        for (self.retainedReservations()) |reservation| {
            if (reservation.outcome == .fallback) {
                out.fallbacks +|= 1;
                if (reservation.purpose.onGraphicsChain()) out.fallbacks_on_chain +|= 1;
            }
            if (reservation.outcome.isDefect()) out.reservation_defects +|= 1;
        }
        return out;
    }

    /// The map a run should be able to print: every range the graphics chain
    /// depends on, with its owner and what it actually got.
    pub fn layoutComplete(self: *const Ledger) bool {
        var seen_ring = false;
        var seen_heap = false;
        for (self.retainedReservations()) |reservation| {
            if (!reservation.outcome.honoured()) continue;
            if (reservation.purpose == .ring) seen_ring = true;
            if (reservation.purpose == .physical_heap) seen_heap = true;
        }
        return seen_ring and seen_heap;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.reservations;
        hash = hash *% 31 +% totals.short_reads;
        hash = hash *% 31 +% totals.fallbacks;
        hash = hash *% 31 +% @intFromBool(totals.baselineClean());
        return hash;
    }
};

// The short-`pread` hazard: fewer bytes than asked for, no end of file, and a
// caller that would otherwise treat the buffer as valid.
test "a short read is its own outcome and is never usable" {
    var ledger = Ledger{};
    const outcome = ledger.read(.{
        .purpose = .executable_image,
        .offset = 0x1000,
        .requested_bytes = 2048,
        .returned_bytes = 1024,
    }, false);
    try std.testing.expectEqual(ReadOutcome.short, outcome);
    try std.testing.expect(!outcome.usable());
    try std.testing.expect(outcome.isDefect());
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().short_reads_on_chain);
    try std.testing.expect(!ledger.summary().baselineClean());
    try std.testing.expect(std.mem.indexOf(u8, outcome.describe(), "wrong bytes") != null);
}

test "the same byte counts at the end of a source are a named result" {
    var ledger = Ledger{};
    const outcome = ledger.read(.{
        .purpose = .executable_image,
        .requested_bytes = 2048,
        .returned_bytes = 1024,
    }, true);
    try std.testing.expectEqual(ReadOutcome.end_of_file, outcome);
    try std.testing.expect(!outcome.usable());
    try std.testing.expect(!outcome.isDefect());
    try std.testing.expect(ledger.summary().baselineClean());
}

test "a caller cannot label a short read complete" {
    const entry = Read{ .requested_bytes = 100, .returned_bytes = 50, .outcome = .complete };
    try std.testing.expectEqual(ReadOutcome.short, entry.impliedOutcome(false));
    try std.testing.expectEqual(ReadOutcome.failed, (Read{ .requested_bytes = 100 }).impliedOutcome(false));
    try std.testing.expectEqual(
        ReadOutcome.complete,
        (Read{ .requested_bytes = 100, .returned_bytes = 100 }).impliedOutcome(false),
    );
}

test "a fallback off the graphics chain does not spoil the baseline" {
    var ledger = Ledger{};
    _ = ledger.reserve(.{ .purpose = .other, .requested_bytes = 4096, .actual_bytes = 4096, .outcome = .fallback, .reason = "requested range occupied" }).?;
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), totals.fallbacks);
    try std.testing.expectEqual(@as(u64, 0), totals.fallbacks_on_chain);
    try std.testing.expect(totals.baselineClean());
}

// The occupied-range fallback in the heap selector, on a range the graphics
// chain depends on.
test "a fallback on the graphics chain blocks a clean baseline" {
    var ledger = Ledger{};
    _ = ledger.reserve(.{
        .purpose = .physical_heap,
        .requested_address = 0x1000_0000,
        .requested_bytes = 0x1000_0000,
        .actual_address = 0x2000_0000,
        .actual_bytes = 0x1000_0000,
        .outcome = .fallback,
        .reason = "requested range occupied",
    }).?;
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), totals.fallbacks_on_chain);
    try std.testing.expect(!totals.baselineClean());
}

test "a truncated reservation is a defect and a relocated one is not" {
    var ledger = Ledger{};
    _ = ledger.reserve(.{ .purpose = .ring, .requested_bytes = 0x8000, .actual_bytes = 0x8000, .outcome = .relocated }).?;
    try std.testing.expect(ReservationOutcome.relocated.honoured());
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().reservation_defects);

    _ = ledger.reserve(.{ .purpose = .ring, .requested_bytes = 0x8000, .actual_bytes = 0x4000, .outcome = .truncated }).?;
    try std.testing.expect(ReservationOutcome.truncated.isDefect());
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().reservation_defects);
    try std.testing.expect(!ledger.summary().baselineClean());
}

test "reservations carry a generation so two runs can be compared" {
    var ledger = Ledger{};
    const first = ledger.reserve(.{ .purpose = .ring, .requested_bytes = 1 }).?;
    const second = ledger.reserve(.{ .purpose = .physical_heap, .requested_bytes = 1 }).?;
    try std.testing.expectEqual(@as(u64, 1), first.generation);
    try std.testing.expectEqual(@as(u64, 2), second.generation);
    try std.testing.expect(ledger.layoutComplete());
}

test "the layout is incomplete until the ring and heap are both honoured" {
    var ledger = Ledger{};
    try std.testing.expect(!ledger.layoutComplete());
    _ = ledger.reserve(.{ .purpose = .ring, .requested_bytes = 1, .outcome = .failed }).?;
    _ = ledger.reserve(.{ .purpose = .physical_heap, .requested_bytes = 1 }).?;
    try std.testing.expect(!ledger.layoutComplete());
    _ = ledger.reserve(.{ .purpose = .ring, .requested_bytes = 1 }).?;
    try std.testing.expect(ledger.layoutComplete());
}

test "read totals survive the retained window and every outcome is named" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_reads + 3) : (index += 1) {
        _ = ledger.read(.{ .purpose = .texture_storage, .requested_bytes = 16, .returned_bytes = 16 }, false);
    }
    try std.testing.expectEqual(max_reads, ledger.retainedReads().len);
    try std.testing.expectEqual(@as(u64, 3), ledger.reads_dropped);
    try std.testing.expectEqual(@as(u64, max_reads + 3), ledger.summary().total_reads);

    inline for (@typeInfo(ReadOutcome).@"enum".fields) |field| {
        const which: ReadOutcome = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
    inline for (@typeInfo(Purpose).@"enum".fields) |field| {
        const which: Purpose = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
}
