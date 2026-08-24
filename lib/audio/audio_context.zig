//! XMA decode context state machine.
//!
//! A context is one hardware decoder. The title programs its buffers, enables
//! it, and the APU produces PCM until the input runs out. Rosette models the
//! lifecycle so that "no audio" can be attributed: a context that was never
//! enabled, one enabled with no input, and one enabled and starved are three
//! different failures with the same symptom.
//!
//! ## Why the transitions are guarded
//!
//! The failure this exists to prevent is a context that is *implicitly* valid.
//! If enabling a context with no buffers programmed simply produces silence,
//! then a title with a buffer-programming bug sounds exactly like a title whose
//! audio Rosette failed to forward. Refusing the enable makes the distinction
//! at the moment it can still be attributed.

const std = @import("std");
const contract = @import("xenia_audio_contract");

pub const Error = error{
    /// Enabling a context whose buffers are not both programmed.
    BuffersNotProgrammed,
    /// A context index outside the decode hardware.
    InvalidContextIndex,
    /// A channel count or sample rate the APU does not clock.
    UnsupportedFormat,
    /// A transition the state machine does not allow from here.
    InvalidTransition,
};

pub const Context = struct {
    index: u32,
    descriptor: contract.XmaContext = .{},
    state: contract.VoiceState = .idle,
    /// Bytes of input consumed and PCM produced. Progress axes: a context that
    /// is enabled and playing but has consumed nothing is starved, which is a
    /// different report from one that is idle.
    input_bytes_consumed: u64 = 0,
    output_samples_produced: u64 = 0,
    /// Frames the decoder could not produce because the codec core is absent.
    /// Counted rather than logged so a run can report the gap once, with a
    /// number, instead of per frame.
    frames_undecodable: u64 = 0,

    pub fn init(index: u32) Error!Context {
        if (!contract.isContextIndex(index)) return error.InvalidContextIndex;
        return .{ .index = index };
    }

    /// Program the context's buffers and format.
    ///
    /// Allowed from any non-playing state: a title may reprogram a paused or
    /// stopped context, but changing the buffers under a running decode would
    /// tear the output.
    pub fn program(self: *Context, descriptor: contract.XmaContext) Error!void {
        if (self.state == .playing) return error.InvalidTransition;
        if (!contract.isSupportedSampleRate(descriptor.sample_rate)) {
            return error.UnsupportedFormat;
        }
        if (descriptor.channels == 0) return error.UnsupportedFormat;
        self.descriptor = descriptor;
    }

    /// Whether the context could decode if enabled.
    pub fn isProgrammed(self: *const Context) bool {
        return self.descriptor.hasWellFormedBuffers() and
            contract.isSupportedSampleRate(self.descriptor.sample_rate);
    }

    /// Begin decoding.
    ///
    /// Refuses an unprogrammed context rather than producing silence, so a
    /// title's buffer bug cannot be mistaken for a Rosette forwarding failure.
    pub fn enable(self: *Context) Error!void {
        if (!self.isProgrammed()) return error.BuffersNotProgrammed;
        self.state = .playing;
    }

    pub fn pause(self: *Context) Error!void {
        if (self.state != .playing) return error.InvalidTransition;
        self.state = .paused;
    }

    pub fn @"resume"(self: *Context) Error!void {
        if (self.state != .paused) return error.InvalidTransition;
        self.state = .playing;
    }

    /// Stop and release. Legal from anywhere: a title may stop a context it
    /// never started, and refusing that would be stricter than the hardware.
    pub fn stop(self: *Context) void {
        self.state = .stopped;
    }

    /// Whether this context should be serviced this period.
    pub fn wantsService(self: *const Context) bool {
        return self.state.consumesInput() and self.isProgrammed();
    }

    /// Record that a decode period ran.
    pub fn noteDecoded(self: *Context, input_bytes: u64, output_samples: u64) void {
        self.input_bytes_consumed +|= input_bytes;
        self.output_samples_produced +|= output_samples;
    }

    pub fn noteUndecodable(self: *Context) void {
        self.frames_undecodable +|= 1;
    }

    /// Why this context is producing nothing, in the words a reader needs.
    ///
    /// Ordered most-specific first. A context that is idle *and* unprogrammed
    /// should be reported as never enabled, because that is the earlier and
    /// more actionable fact.
    pub fn silenceReason(self: *const Context) ?[]const u8 {
        if (self.output_samples_produced > 0) return null;
        return switch (self.state) {
            .idle => "never enabled: the title has not started this voice",
            .stopped => "stopped: the title released this voice",
            .paused => "paused: the title suspended this voice",
            .playing => if (!self.isProgrammed())
                "playing with unusable buffers: the descriptor is malformed"
            else if (self.frames_undecodable > 0)
                "decoder gap: frames arrived but Rosette has no XMA codec core"
            else
                "starved: enabled and programmed, but no input has arrived",
        };
    }
};

test "a context index is bounded by the decode hardware" {
    _ = try Context.init(0);
    _ = try Context.init(contract.max_context_count - 1);
    try std.testing.expectError(error.InvalidContextIndex, Context.init(contract.max_context_count));
}

fn wellFormed() contract.XmaContext {
    return .{
        .input_buffer_phys = 0xA000_0000,
        .input_buffer_size = contract.bytes_per_packet,
        .output_buffer_phys = 0xA001_0000,
        .output_buffer_size = contract.decodedFrameBytes(2),
        .channels = 2,
        .sample_rate = 48000,
        .bits_per_sample = 16,
    };
}

test "an unprogrammed context refuses to start" {
    // The distinction that matters: refusing here separates a title's buffer
    // bug from a Rosette forwarding failure. Producing silence would merge
    // them into one indistinguishable symptom.
    var context = try Context.init(0);
    try std.testing.expect(!context.isProgrammed());
    try std.testing.expectError(error.BuffersNotProgrammed, context.enable());
    try std.testing.expectEqual(contract.VoiceState.idle, context.state);
}

test "a programmed context starts and wants service" {
    var context = try Context.init(0);
    try context.program(wellFormed());
    try std.testing.expect(context.isProgrammed());
    try context.enable();
    try std.testing.expectEqual(contract.VoiceState.playing, context.state);
    try std.testing.expect(context.wantsService());
}

test "an unsupported rate or channel count is refused at programming time" {
    var context = try Context.init(0);
    var descriptor = wellFormed();
    descriptor.sample_rate = 44100;
    try std.testing.expectError(error.UnsupportedFormat, context.program(descriptor));

    descriptor = wellFormed();
    descriptor.channels = 0;
    try std.testing.expectError(error.UnsupportedFormat, context.program(descriptor));

    // 24 kHz is the other rate the APU clocks.
    descriptor = wellFormed();
    descriptor.sample_rate = 24000;
    descriptor.output_buffer_size = contract.decodedFrameBytes(2);
    try context.program(descriptor);
}

test "buffers cannot be swapped under a running decode" {
    // Reprogramming a playing context would tear its output mid-frame.
    var context = try Context.init(0);
    try context.program(wellFormed());
    try context.enable();
    try std.testing.expectError(error.InvalidTransition, context.program(wellFormed()));

    // Pausing first makes it legal.
    try context.pause();
    try context.program(wellFormed());
}

test "pause and resume are symmetric and refuse bad orders" {
    var context = try Context.init(0);
    try context.program(wellFormed());
    try std.testing.expectError(error.InvalidTransition, context.pause());

    try context.enable();
    try context.pause();
    try std.testing.expectEqual(contract.VoiceState.paused, context.state);
    try std.testing.expect(!context.wantsService());

    try std.testing.expectError(error.InvalidTransition, context.pause());
    try context.@"resume"();
    try std.testing.expect(context.wantsService());
    try std.testing.expectError(error.InvalidTransition, context.@"resume"());
}

test "stopping is legal from anywhere" {
    // A title may stop a voice it never started; refusing would be stricter
    // than the hardware and would fail a legitimate cleanup path.
    var context = try Context.init(0);
    context.stop();
    try std.testing.expectEqual(contract.VoiceState.stopped, context.state);
    try std.testing.expect(!context.wantsService());
}

test "silence is attributed to the earliest actionable cause" {
    var context = try Context.init(0);
    try std.testing.expectEqualStrings(
        "never enabled: the title has not started this voice",
        context.silenceReason().?,
    );

    try context.program(wellFormed());
    try context.enable();
    try std.testing.expectEqualStrings(
        "starved: enabled and programmed, but no input has arrived",
        context.silenceReason().?,
    );

    context.noteUndecodable();
    try std.testing.expectEqualStrings(
        "decoder gap: frames arrived but Rosette has no XMA codec core",
        context.silenceReason().?,
    );
}

test "a context that produced samples has no silence reason" {
    var context = try Context.init(0);
    try context.program(wellFormed());
    try context.enable();
    context.noteDecoded(2048, 1024);
    try std.testing.expect(context.silenceReason() == null);
    try std.testing.expectEqual(@as(u64, 1024), context.output_samples_produced);
}

test "paused and stopped are distinguishable in the silence report" {
    var context = try Context.init(0);
    try context.program(wellFormed());
    try context.enable();
    try context.pause();
    try std.testing.expectEqualStrings(
        "paused: the title suspended this voice",
        context.silenceReason().?,
    );
    context.stop();
    try std.testing.expectEqualStrings(
        "stopped: the title released this voice",
        context.silenceReason().?,
    );
}

test "progress counters saturate rather than wrapping" {
    var context = try Context.init(0);
    context.noteDecoded(std.math.maxInt(u64), std.math.maxInt(u64));
    context.noteDecoded(1, 1);
    try std.testing.expectEqual(std.math.maxInt(u64), context.input_bytes_consumed);
    try std.testing.expectEqual(std.math.maxInt(u64), context.output_samples_produced);
}
