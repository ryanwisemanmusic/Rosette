//! Single-producer, single-consumer sample ring.
//!
//! The mixer fills this from a guest-driven thread and the host audio callback
//! drains it on the device's own real-time thread. Those two never block each
//! other, which is not a performance nicety: the callback runs under a hard
//! deadline, and a lock it can wait on is a lock it will eventually miss the
//! deadline holding.
//!
//! ## What the counters are for
//!
//! Underrun and overrun are counted rather than logged at the point they
//! happen, because they happen on the real-time thread where formatting a
//! message is itself a deadline risk. They are also the only honest way to tell
//! two very different failures apart:
//!
//! * **Underruns** mean the producer is behind — the guest is not generating
//!   audio fast enough, or is not generating it at all. The stall is upstream.
//! * **Overruns** mean the consumer is behind, or absent. The host device never
//!   started, or the callback is not being dispatched.
//!
//! Both sound identical through a speaker (silence, or a stutter), and pointing
//! at the wrong one sends someone into the wrong subsystem entirely.
//!
//! An empty ring is not an error and is not counted as an underrun unless the
//! consumer actually asked for samples. A ring nobody has read from yet reads
//! as empty forever, and counting that as underrun would manufacture evidence
//! of a producer stall that has not happened.

const std = @import("std");

pub const Error = error{
    /// The backing storage was not a whole number of frames.
    UnalignedCapacity,
    /// A zero-length ring cannot buffer anything.
    EmptyCapacity,
};

/// A lock-free ring over caller-provided storage.
///
/// The caller owns the memory. This type never allocates, which keeps it usable
/// from the real-time side where an allocation is as bad as a lock.
pub const AudioRing = struct {
    storage: []f32,
    /// Total samples written since construction. Monotonic; wrapping is
    /// handled by the modulo at access time rather than by resetting, so the
    /// difference between the two cursors is always the true fill level.
    write_cursor: std.atomic.Value(u64) = .init(0),
    read_cursor: std.atomic.Value(u64) = .init(0),
    underruns: std.atomic.Value(u64) = .init(0),
    overruns: std.atomic.Value(u64) = .init(0),
    /// Samples dropped by overrun, and samples substituted by underrun. Kept
    /// separate from the event counts: one long stall and many short ones are
    /// different problems that produce the same event count.
    dropped_samples: std.atomic.Value(u64) = .init(0),
    silence_samples: std.atomic.Value(u64) = .init(0),

    pub fn init(storage: []f32) Error!AudioRing {
        if (storage.len == 0) return error.EmptyCapacity;
        return .{ .storage = storage };
    }

    /// A ring sized in whole frames, so a partial frame can never be produced.
    pub fn initFrames(storage: []f32, samples_per_frame: usize) Error!AudioRing {
        if (samples_per_frame == 0) return error.EmptyCapacity;
        if (storage.len == 0) return error.EmptyCapacity;
        if (storage.len % samples_per_frame != 0) return error.UnalignedCapacity;
        return .{ .storage = storage };
    }

    pub fn capacity(self: *const AudioRing) usize {
        return self.storage.len;
    }

    /// Samples available to read.
    pub fn filled(self: *const AudioRing) usize {
        const written = self.write_cursor.load(.acquire);
        const consumed = self.read_cursor.load(.acquire);
        return @intCast(written - consumed);
    }

    pub fn available(self: *const AudioRing) usize {
        return self.capacity() - self.filled();
    }

    pub fn isEmpty(self: *const AudioRing) bool {
        return self.filled() == 0;
    }

    /// Write samples, dropping the oldest if the consumer has fallen behind.
    ///
    /// Dropping the oldest rather than refusing the write is deliberate: audio
    /// is a real-time stream, and stale samples are worth less than current
    /// ones. Refusing would stall the producer against a consumer that may
    /// never run.
    ///
    /// Returns the number of samples written, which is always `samples.len`
    /// unless the input exceeds the whole ring.
    pub fn write(self: *AudioRing, samples: []const f32) usize {
        if (samples.len == 0) return 0;

        // An input larger than the ring can only ever leave its tail. That
        // truncation is itself a loss and is counted: a write that silently
        // discards its own front would make the ring look healthy while audio
        // went missing.
        var lost: usize = 0;
        const source = if (samples.len > self.capacity()) blk: {
            lost = samples.len - self.capacity();
            break :blk samples[samples.len - self.capacity() ..];
        } else samples;

        const free = self.available();
        if (source.len > free) {
            const overflow = source.len - free;
            lost += overflow;
            // Advance the reader past the samples about to be overwritten.
            _ = self.read_cursor.fetchAdd(overflow, .release);
        }
        if (lost > 0) {
            _ = self.overruns.fetchAdd(1, .monotonic);
            _ = self.dropped_samples.fetchAdd(lost, .monotonic);
        }

        const write_at = self.write_cursor.load(.monotonic);
        var index: usize = 0;
        while (index < source.len) : (index += 1) {
            const slot: usize = @intCast((write_at + index) % self.capacity());
            self.storage[slot] = source[index];
        }
        self.write_cursor.store(write_at + source.len, .release);
        return source.len;
    }

    /// Fill `out` from the ring, substituting silence for anything missing.
    ///
    /// Silence rather than a short read, because the host callback must return
    /// a full buffer: a short one is played as whatever was in the buffer
    /// before, which is a far louder artefact than a gap.
    ///
    /// Returns the number of real samples delivered.
    pub fn read(self: *AudioRing, out: []f32) usize {
        if (out.len == 0) return 0;

        const ready = @min(self.filled(), out.len);
        const read_at = self.read_cursor.load(.monotonic);
        var index: usize = 0;
        while (index < ready) : (index += 1) {
            const slot: usize = @intCast((read_at + index) % self.capacity());
            out[index] = self.storage[slot];
        }
        self.read_cursor.store(read_at + ready, .release);

        if (ready < out.len) {
            // Only now is this an underrun: the consumer asked and the
            // producer had nothing. An untouched ring is not underrunning.
            @memset(out[ready..], 0);
            _ = self.underruns.fetchAdd(1, .monotonic);
            _ = self.silence_samples.fetchAdd(out.len - ready, .monotonic);
        }
        return ready;
    }

    /// Discard everything buffered without counting it as a loss.
    ///
    /// A deliberate reset — a voice stopping, a seek — is not an overrun, and
    /// counting it as one would make the diagnostic counters lie about a
    /// producer that is behaving.
    pub fn clear(self: *AudioRing) void {
        self.read_cursor.store(self.write_cursor.load(.acquire), .release);
    }

    pub const Health = struct {
        filled: usize,
        capacity: usize,
        underruns: u64,
        overruns: u64,
        dropped_samples: u64,
        silence_samples: u64,

        /// Which side of the ring is behind, if either.
        ///
        /// The question the counters exist to answer. Both being non-zero is
        /// possible and means the stream is unstable rather than one-sided.
        pub fn verdict(self: Health) []const u8 {
            if (self.underruns > 0 and self.overruns > 0) {
                return "both: the stream is unstable, neither side keeps pace";
            }
            if (self.underruns > 0) {
                return "producer behind: the guest is not generating audio fast enough";
            }
            if (self.overruns > 0) {
                return "consumer behind: the host device is not draining the ring";
            }
            return "healthy: neither side has missed";
        }
    };

    pub fn health(self: *const AudioRing) Health {
        return .{
            .filled = self.filled(),
            .capacity = self.capacity(),
            .underruns = self.underruns.load(.monotonic),
            .overruns = self.overruns.load(.monotonic),
            .dropped_samples = self.dropped_samples.load(.monotonic),
            .silence_samples = self.silence_samples.load(.monotonic),
        };
    }
};

test "a fresh ring is empty and healthy" {
    var storage: [16]f32 = undefined;
    var ring = try AudioRing.init(&storage);
    try std.testing.expect(ring.isEmpty());
    try std.testing.expectEqual(@as(usize, 16), ring.available());
    // Not an underrun: nobody has asked for anything yet.
    try std.testing.expectEqual(@as(u64, 0), ring.health().underruns);
    try std.testing.expectEqualStrings("healthy: neither side has missed", ring.health().verdict());
}

test "a zero length ring is refused" {
    var empty: [0]f32 = undefined;
    try std.testing.expectError(error.EmptyCapacity, AudioRing.init(&empty));
}

test "frame sized construction rejects a partial frame" {
    var storage: [12]f32 = undefined;
    _ = try AudioRing.initFrames(&storage, 4);
    _ = try AudioRing.initFrames(&storage, 6);
    // 12 is not a whole number of 5-sample frames.
    try std.testing.expectError(error.UnalignedCapacity, AudioRing.initFrames(&storage, 5));
    try std.testing.expectError(error.EmptyCapacity, AudioRing.initFrames(&storage, 0));
}

test "samples come back in the order they went in" {
    var storage: [8]f32 = undefined;
    var ring = try AudioRing.init(&storage);
    try std.testing.expectEqual(@as(usize, 4), ring.write(&[_]f32{ 1, 2, 3, 4 }));
    try std.testing.expectEqual(@as(usize, 4), ring.filled());

    var out: [4]f32 = undefined;
    try std.testing.expectEqual(@as(usize, 4), ring.read(&out));
    try std.testing.expectEqualSlices(f32, &[_]f32{ 1, 2, 3, 4 }, &out);
    try std.testing.expect(ring.isEmpty());
}

test "reading more than is buffered pads with silence and counts one underrun" {
    var storage: [8]f32 = undefined;
    var ring = try AudioRing.init(&storage);
    _ = ring.write(&[_]f32{ 1, 2 });

    var out: [4]f32 = undefined;
    // Two real samples, two of silence.
    try std.testing.expectEqual(@as(usize, 2), ring.read(&out));
    try std.testing.expectEqualSlices(f32, &[_]f32{ 1, 2, 0, 0 }, &out);
    try std.testing.expectEqual(@as(u64, 1), ring.health().underruns);
    try std.testing.expectEqual(@as(u64, 2), ring.health().silence_samples);
    try std.testing.expectEqualStrings(
        "producer behind: the guest is not generating audio fast enough",
        ring.health().verdict(),
    );
}

test "the buffer is always filled, never left short" {
    // A short read would play whatever was in the host buffer before, which is
    // a much louder artefact than silence.
    var storage: [4]f32 = undefined;
    var ring = try AudioRing.init(&storage);
    var out = [_]f32{ 9, 9, 9, 9, 9, 9 };
    _ = ring.read(&out);
    for (out) |sample| try std.testing.expectEqual(@as(f32, 0), sample);
}

test "overrun drops the oldest samples and keeps the newest" {
    // Stale audio is worth less than current audio, so the ring drops the
    // front rather than refusing the write.
    var storage: [4]f32 = undefined;
    var ring = try AudioRing.init(&storage);
    _ = ring.write(&[_]f32{ 1, 2, 3, 4 });
    _ = ring.write(&[_]f32{ 5, 6 });

    try std.testing.expectEqual(@as(u64, 1), ring.health().overruns);
    try std.testing.expectEqual(@as(u64, 2), ring.health().dropped_samples);
    var out: [4]f32 = undefined;
    _ = ring.read(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 3, 4, 5, 6 }, &out);
    try std.testing.expectEqualStrings(
        "consumer behind: the host device is not draining the ring",
        ring.health().verdict(),
    );
}

test "a write larger than the ring keeps only its tail, and says so" {
    var storage: [4]f32 = undefined;
    var ring = try AudioRing.init(&storage);
    _ = ring.write(&[_]f32{ 1, 2, 3, 4, 5, 6, 7, 8 });
    var out: [4]f32 = undefined;
    _ = ring.read(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 5, 6, 7, 8 }, &out);
    // The four discarded samples are reported. Truncating quietly would let
    // the ring read as healthy while audio went missing.
    try std.testing.expectEqual(@as(u64, 1), ring.health().overruns);
    try std.testing.expectEqual(@as(u64, 4), ring.health().dropped_samples);
}

test "the cursors wrap without corrupting order" {
    // The modulo is the only wrap handling; the cursors themselves are
    // monotonic, so their difference is always the true fill level.
    var storage: [4]f32 = undefined;
    var ring = try AudioRing.init(&storage);
    var out: [2]f32 = undefined;
    var round: f32 = 0;
    while (round < 20) : (round += 2) {
        _ = ring.write(&[_]f32{ round, round + 1 });
        try std.testing.expectEqual(@as(usize, 2), ring.read(&out));
        try std.testing.expectEqualSlices(f32, &[_]f32{ round, round + 1 }, &out);
    }
    // Twenty samples through a four-sample ring, never overrunning because the
    // consumer kept pace.
    try std.testing.expectEqual(@as(u64, 0), ring.health().overruns);
    try std.testing.expectEqual(@as(u64, 0), ring.health().underruns);
}

test "clearing is not counted as a loss" {
    // A voice stopping is not an overrun. Counting it as one would make the
    // counters accuse a producer that is behaving.
    var storage: [8]f32 = undefined;
    var ring = try AudioRing.init(&storage);
    _ = ring.write(&[_]f32{ 1, 2, 3, 4 });
    ring.clear();
    try std.testing.expect(ring.isEmpty());
    try std.testing.expectEqual(@as(u64, 0), ring.health().overruns);
    try std.testing.expectEqual(@as(u64, 0), ring.health().dropped_samples);
}

test "an unstable stream is reported as both, not as one side" {
    var storage: [4]f32 = undefined;
    var ring = try AudioRing.init(&storage);
    _ = ring.write(&[_]f32{ 1, 2, 3, 4, 5 });
    var out: [8]f32 = undefined;
    _ = ring.read(&out);
    const report = ring.health();
    try std.testing.expect(report.underruns > 0);
    try std.testing.expect(report.overruns > 0);
    try std.testing.expectEqualStrings(
        "both: the stream is unstable, neither side keeps pace",
        report.verdict(),
    );
}
