//! Host audio output boundary.
//!
//! The device-facing half of `lib/audio`. It owns the negotiated stream format,
//! the callback's view of the ring, and the counters that say whether the host
//! ever asked for audio at all.
//!
//! ## Why "was the callback ever called" is the first question
//!
//! When a title is silent there are two entirely separate possibilities, and
//! they live on opposite sides of this file: either the guest produced nothing,
//! or the host never asked. A driver that opened successfully but whose
//! callback is never dispatched looks — from every counter upstream — exactly
//! like a guest that never produced a sample. `callbacks_served` is the one
//! number that separates them, which is why it is a field and not a log line.
//!
//! The existing SDL path in `lib/runtime/guest-abi/sdl_runtime.zig` reaches the
//! same conclusion from the guest side: it describes its backend as a
//! `clocked_null_sink`, where guest timing and ownership are real but audible
//! output is not. This file is the host-side counterpart, and it is explicit
//! about the same boundary rather than implying a device exists.

const std = @import("std");
const contract = @import("xenia_audio_contract");
const audio_ring = @import("audio_ring.zig");

pub const Error = error{
    /// A format the console does not produce.
    UnsupportedFormat,
    /// The device is already open.
    AlreadyOpen,
    /// An operation that requires an open device.
    NotOpen,
    /// The callback buffer does not match the negotiated frame.
    FrameSizeMismatch,
};

/// The stream format a host device is asked for.
pub const StreamFormat = struct {
    sample_rate: u32 = contract.sample_rate_48k,
    channels: u32 = contract.host_frame_channels,
    samples_per_channel: u32 = contract.host_frame_samples_per_channel,

    pub fn frameSamples(self: StreamFormat) u32 {
        return self.channels * self.samples_per_channel;
    }

    pub fn frameBytes(self: StreamFormat) u32 {
        return self.frameSamples() * contract.bytes_per_host_sample;
    }

    /// One callback period in nanoseconds.
    pub fn periodNanoseconds(self: StreamFormat) u64 {
        if (self.sample_rate == 0) return 0;
        return @as(u64, self.samples_per_channel) * 1_000_000_000 / @as(u64, self.sample_rate);
    }

    pub fn isSupported(self: StreamFormat) bool {
        if (!contract.isSupportedSampleRate(self.sample_rate)) return false;
        if (self.channels == 0 or self.channels > contract.host_frame_channels) return false;
        return self.samples_per_channel != 0;
    }
};

/// What kind of sink the audio is actually reaching.
///
/// Named rather than implied. A runtime that reports "audio open" while writing
/// into nothing has stated something true and useless; naming the sink makes
/// the limitation part of every report that mentions it.
pub const SinkKind = enum {
    /// A real host device is consuming frames.
    host_device,
    /// Frames are consumed on a correct clock but not made audible. Guest
    /// timing and ownership are real; the speaker is not.
    clocked_null_sink,
    /// Nothing is consuming frames.
    disconnected,

    pub fn isAudible(self: SinkKind) bool {
        return self == .host_device;
    }
};

pub const Driver = struct {
    format: StreamFormat = .{},
    sink: SinkKind = .disconnected,
    is_open: bool = false,

    callbacks_served: u64 = 0,
    frames_delivered: u64 = 0,
    real_samples_delivered: u64 = 0,
    silence_samples_delivered: u64 = 0,

    pub fn open(self: *Driver, format: StreamFormat, sink: SinkKind) Error!void {
        if (self.is_open) return error.AlreadyOpen;
        if (!format.isSupported()) return error.UnsupportedFormat;
        self.format = format;
        self.sink = sink;
        self.is_open = true;
    }

    pub fn close(self: *Driver) void {
        self.is_open = false;
        self.sink = .disconnected;
    }

    /// Serve one host callback from the ring.
    ///
    /// The buffer is always filled: the ring substitutes silence for anything
    /// missing, because a short buffer is played as whatever was there before.
    pub fn serveCallback(self: *Driver, ring: *audio_ring.AudioRing, out: []f32) Error!void {
        if (!self.is_open) return error.NotOpen;
        if (out.len != self.format.frameSamples()) return error.FrameSizeMismatch;

        const real = ring.read(out);
        self.callbacks_served +|= 1;
        self.frames_delivered +|= 1;
        self.real_samples_delivered +|= real;
        self.silence_samples_delivered +|= out.len - real;
    }

    pub const Health = struct {
        is_open: bool,
        sink: SinkKind,
        callbacks_served: u64,
        real_samples_delivered: u64,
        silence_samples_delivered: u64,

        /// The first question: did the host ever ask for audio?
        ///
        /// Ordered so the answer names the earliest stage that failed. A
        /// device that never called back is not the guest's fault, and saying
        /// so stops the search happening in the wrong subsystem.
        pub fn verdict(self: Health) []const u8 {
            if (!self.is_open) return "closed: no host device has been opened";
            if (self.callbacks_served == 0) {
                return "opened but never called: the host has not asked for audio, so guest-side silence is not the cause";
            }
            if (self.real_samples_delivered == 0) {
                return "called but always starved: the host is asking and the guest has produced nothing";
            }
            if (!self.sink.isAudible()) {
                return "delivering to a non-audible sink: timing and ownership are real, output is not";
            }
            if (self.silence_samples_delivered > 0) {
                return "delivering with gaps: the guest is not keeping pace with the device";
            }
            return "delivering: real samples are reaching an audible sink";
        }
    };

    pub fn health(self: *const Driver) Health {
        return .{
            .is_open = self.is_open,
            .sink = self.sink,
            .callbacks_served = self.callbacks_served,
            .real_samples_delivered = self.real_samples_delivered,
            .silence_samples_delivered = self.silence_samples_delivered,
        };
    }
};

test "the default format matches the console frame" {
    const format = StreamFormat{};
    try std.testing.expect(format.isSupported());
    try std.testing.expectEqual(@as(u32, 1536), format.frameSamples());
    try std.testing.expectEqual(@as(u32, 6144), format.frameBytes());
    // The same 6144 the SDL path negotiates from the guest side.
    try std.testing.expectEqual(contract.bytes_per_host_frame, format.frameBytes());
}

test "the callback period is derived from the negotiated rate" {
    try std.testing.expectEqual(@as(u64, 5_333_333), (StreamFormat{}).periodNanoseconds());
    const half = StreamFormat{ .sample_rate = contract.sample_rate_24k };
    try std.testing.expectEqual(@as(u64, 10_666_666), half.periodNanoseconds());
}

test "an unsupported format is refused at open" {
    var driver = Driver{};
    try std.testing.expectError(error.UnsupportedFormat, driver.open(.{ .sample_rate = 44100 }, .host_device));
    try std.testing.expectError(error.UnsupportedFormat, driver.open(.{ .channels = 0 }, .host_device));
    try std.testing.expectError(error.UnsupportedFormat, driver.open(.{ .channels = 8 }, .host_device));
    try std.testing.expectError(error.UnsupportedFormat, driver.open(.{ .samples_per_channel = 0 }, .host_device));
    try std.testing.expect(!driver.is_open);
}

test "a closed driver says so before anything else" {
    const driver = Driver{};
    try std.testing.expectEqualStrings(
        "closed: no host device has been opened",
        driver.health().verdict(),
    );
}

test "an open device that never calls back exonerates the guest" {
    // The single most valuable distinction in the audio path. Without it,
    // this state is indistinguishable from a guest that produced nothing, and
    // the search happens in the wrong subsystem.
    var driver = Driver{};
    try driver.open(.{}, .host_device);
    try std.testing.expectEqualStrings(
        "opened but never called: the host has not asked for audio, so guest-side silence is not the cause",
        driver.health().verdict(),
    );
}

test "opening twice is refused" {
    var driver = Driver{};
    try driver.open(.{}, .host_device);
    try std.testing.expectError(error.AlreadyOpen, driver.open(.{}, .host_device));
    driver.close();
    try driver.open(.{}, .host_device);
}

test "serving requires an open device and a matching buffer" {
    var storage: [64]f32 = undefined;
    var ring = try audio_ring.AudioRing.init(&storage);
    var out: [1536]f32 = undefined;

    var driver = Driver{};
    try std.testing.expectError(error.NotOpen, driver.serveCallback(&ring, &out));

    try driver.open(.{}, .host_device);
    var wrong: [16]f32 = undefined;
    try std.testing.expectError(error.FrameSizeMismatch, driver.serveCallback(&ring, &wrong));
}

test "a starved callback is reported as the host asking and the guest not producing" {
    var storage: [64]f32 = undefined;
    var ring = try audio_ring.AudioRing.init(&storage);
    var out: [1536]f32 = undefined;
    var driver = Driver{};
    try driver.open(.{}, .host_device);
    try driver.serveCallback(&ring, &out);

    try std.testing.expectEqual(@as(u64, 1), driver.health().callbacks_served);
    try std.testing.expectEqual(@as(u64, 0), driver.health().real_samples_delivered);
    try std.testing.expectEqualStrings(
        "called but always starved: the host is asking and the guest has produced nothing",
        driver.health().verdict(),
    );
    // The buffer is still fully written.
    for (out) |sample| try std.testing.expectEqual(@as(f32, 0), sample);
}

test "a non-audible sink is named rather than implied" {
    // Reporting "delivering" into a null sink would be true and useless.
    var storage: [4096]f32 = undefined;
    var ring = try audio_ring.AudioRing.init(&storage);
    var frame = [_]f32{0.5} ** 1536;
    _ = ring.write(&frame);

    var out: [1536]f32 = undefined;
    var driver = Driver{};
    try driver.open(.{}, .clocked_null_sink);
    try driver.serveCallback(&ring, &out);
    try std.testing.expectEqualStrings(
        "delivering to a non-audible sink: timing and ownership are real, output is not",
        driver.health().verdict(),
    );
    try std.testing.expect(!driver.sink.isAudible());
}

test "a fully served audible device reports delivering" {
    var storage: [4096]f32 = undefined;
    var ring = try audio_ring.AudioRing.init(&storage);
    var frame = [_]f32{0.5} ** 1536;
    _ = ring.write(&frame);

    var out: [1536]f32 = undefined;
    var driver = Driver{};
    try driver.open(.{}, .host_device);
    try driver.serveCallback(&ring, &out);
    try std.testing.expectEqual(@as(u64, 1536), driver.health().real_samples_delivered);
    try std.testing.expectEqual(@as(u64, 0), driver.health().silence_samples_delivered);
    try std.testing.expectEqualStrings(
        "delivering: real samples are reaching an audible sink",
        driver.health().verdict(),
    );
}

test "a partially served device reports gaps rather than success" {
    var storage: [4096]f32 = undefined;
    var ring = try audio_ring.AudioRing.init(&storage);
    var partial = [_]f32{0.5} ** 512;
    _ = ring.write(&partial);

    var out: [1536]f32 = undefined;
    var driver = Driver{};
    try driver.open(.{}, .host_device);
    try driver.serveCallback(&ring, &out);
    try std.testing.expectEqual(@as(u64, 512), driver.health().real_samples_delivered);
    try std.testing.expectEqual(@as(u64, 1024), driver.health().silence_samples_delivered);
    try std.testing.expectEqualStrings(
        "delivering with gaps: the guest is not keeping pace with the device",
        driver.health().verdict(),
    );
}

test "closing disconnects the sink" {
    var driver = Driver{};
    try driver.open(.{}, .host_device);
    driver.close();
    try std.testing.expectEqual(SinkKind.disconnected, driver.sink);
    try std.testing.expect(!driver.sink.isAudible());
}
