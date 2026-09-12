//! Host audio companion for the Windows PE route.
//!
//! The guest's wave device lives in `src/x64-ASM/windows_runtime.zig` and is
//! deliberately independent of any host device: it accepts a buffer, marks it
//! done, and keeps the guest's pacing honest. That is the fallback, and it is
//! the right fallback, because a mixer running on a correct clock is worth
//! more than a mixer that stalls.
//!
//! This file is the audible path beside it. It owns nothing itself - the ring
//! and the CoreAudio queue are in `lib/Mach-O/native_audio_bridge.m` - and it
//! exists to give the PE state a C-ABI seam it can call without linking
//! AudioToolbox into every test binary.
//!
//! ## Reporting rule
//!
//! `sink()` never claims audible output it has not proved. A device that was
//! opened but whose callback has never run reports `clocked_null_sink`, the
//! same as no device at all, because from the guest's side those are
//! identical and only the callback count separates them.

const builtin = @import("builtin");
const std = @import("std");

pub const Status = extern struct {
    open: u32 = 0,
    sample_rate: u32 = 0,
    channels: u32 = 0,
    bits_per_sample: u32 = 0,
    is_float: u32 = 0,
    submitted_bytes: u64 = 0,
    played_bytes: u64 = 0,
    dropped_bytes: u64 = 0,
    underruns: u64 = 0,
    callbacks_served: u64 = 0,
    last_status: i32 = 0,
};

/// What is consuming the guest's frames. The names match `lib/audio`'s
/// `SinkKind` so a reader does not have to learn two vocabularies.
pub const Sink = enum {
    /// A real host device is consuming frames and has proved it by serving a
    /// callback.
    host_device,
    /// A device is open but has never been asked for a frame.
    opened_but_silent,
    /// Frames are consumed on a correct clock but are not made audible.
    clocked_null_sink,

    pub fn label(self: Sink) []const u8 {
        return switch (self) {
            .host_device => "host_device",
            .opened_but_silent => "opened_but_silent",
            .clocked_null_sink => "clocked_null_sink",
        };
    }
};

extern fn rosette_native_audio_open(sample_rate: u32, channels: u32, bits_per_sample: u32, is_float: u32) c_int;
extern fn rosette_native_audio_submit(data: ?*const anyopaque, length: u32) u32;
extern fn rosette_native_audio_close() void;
extern fn rosette_native_audio_status() Status;

pub const NativeWindowsAudio = struct {
    open_attempts: u64 = 0,
    open_failures: u64 = 0,
    submit_calls: u64 = 0,
    submit_bytes: u64 = 0,
    /// The format the guest asked for on the last successful open, kept so a
    /// report can say what was negotiated without calling into the bridge.
    negotiated_sample_rate: u32 = 0,
    negotiated_channels: u32 = 0,
    negotiated_bits: u32 = 0,
    negotiated_float: bool = false,
    is_open: bool = false,

    pub fn open(self: *NativeWindowsAudio, sample_rate: u32, channels: u32, bits_per_sample: u32, is_float: bool) bool {
        if (comptime builtin.target.os.tag != .macos) return false;
        self.open_attempts +|= 1;
        const opened = rosette_native_audio_open(
            sample_rate,
            channels,
            bits_per_sample,
            @intFromBool(is_float),
        ) != 0;
        if (!opened) {
            self.open_failures +|= 1;
            return false;
        }
        self.is_open = true;
        self.negotiated_sample_rate = sample_rate;
        self.negotiated_channels = channels;
        self.negotiated_bits = bits_per_sample;
        self.negotiated_float = is_float;
        return true;
    }

    /// Hand interleaved PCM to the device. Returns the bytes accepted; the
    /// caller must not treat a short accept as a failure, only as pressure.
    pub fn submit(self: *NativeWindowsAudio, samples: []const u8) u32 {
        if (comptime builtin.target.os.tag != .macos) return 0;
        if (!self.is_open or samples.len == 0) return 0;
        self.submit_calls +|= 1;
        const length: u32 = @intCast(@min(samples.len, std.math.maxInt(u32)));
        const accepted = rosette_native_audio_submit(samples.ptr, length);
        self.submit_bytes +|= accepted;
        return accepted;
    }

    pub fn close(self: *NativeWindowsAudio) void {
        if (comptime builtin.target.os.tag != .macos) return;
        if (!self.is_open) return;
        rosette_native_audio_close();
        self.is_open = false;
    }

    pub fn status(self: *const NativeWindowsAudio) Status {
        if (comptime builtin.target.os.tag != .macos) return .{};
        _ = self;
        return rosette_native_audio_status();
    }

    /// What is actually consuming frames right now.
    pub fn sink(self: *const NativeWindowsAudio) Sink {
        if (!self.is_open) return .clocked_null_sink;
        const snapshot = self.status();
        if (snapshot.open == 0) return .clocked_null_sink;
        // A queue that has never served a callback has not proved anything.
        return if (snapshot.callbacks_served != 0) .host_device else .opened_but_silent;
    }
};

test "an audio companion with no device reports the clocked null sink, never a host device" {
    var audio = NativeWindowsAudio{};
    try std.testing.expectEqual(Sink.clocked_null_sink, audio.sink());
    try std.testing.expectEqual(@as(u64, 0), audio.submit_calls);
    // Submitting to a closed companion is a no-op rather than a claim.
    try std.testing.expectEqual(@as(u32, 0), audio.submit(&[_]u8{ 1, 2, 3, 4 }));
}

test "the sink vocabulary separates opened from audible" {
    // These three states are the whole point of the type: two of them look
    // identical from the guest's side and only one of them is sound.
    try std.testing.expectEqualStrings("host_device", Sink.host_device.label());
    try std.testing.expectEqualStrings("opened_but_silent", Sink.opened_but_silent.label());
    try std.testing.expectEqualStrings("clocked_null_sink", Sink.clocked_null_sink.label());
}
