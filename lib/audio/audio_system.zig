//! Voice mixing and master volume.
//!
//! The mixer sums submitted voices into one interleaved host frame. It is the
//! layer where "there is audio" and "audio reaches the device" become separable
//! questions, so its counters are structured around exactly that split.
//!
//! ## Clipping is counted, not hidden
//!
//! Summing voices can exceed the [-1, 1] range the device expects. Clamping is
//! correct — wrapping would turn a loud passage into a burst of noise — but a
//! clamp that happens silently means a mix that is systematically too hot is
//! indistinguishable from one that is merely loud. So clamped samples are
//! counted, and a mix that clips constantly is visible as a number rather than
//! as a vague complaint about distortion.

const std = @import("std");
const contract = @import("xenia_audio_contract");

pub const Error = error{
    /// The submitted voice does not match the mix frame's geometry.
    FrameSizeMismatch,
    /// More voices submitted than the console supports.
    TooManyVoices,
    /// A volume outside the representable range.
    InvalidVolume,
};

/// Sample values the host device accepts.
pub const sample_ceiling: f32 = 1.0;
pub const sample_floor: f32 = -1.0;

pub const Mixer = struct {
    /// The accumulating mix, interleaved, one host frame long.
    accumulator: []f32,
    channels: u32 = contract.host_frame_channels,
    master_volume: f32 = 1.0,

    voices_mixed: u64 = 0,
    frames_completed: u64 = 0,
    clamped_samples: u64 = 0,
    /// Frames where no voice was submitted at all. The counter that separates
    /// "the mixer is not running" from "the mixer runs and has nothing to mix".
    silent_frames: u64 = 0,
    voices_this_frame: u32 = 0,

    pub fn init(accumulator: []f32, channels: u32) Error!Mixer {
        if (channels == 0) return error.FrameSizeMismatch;
        if (accumulator.len == 0 or accumulator.len % channels != 0) {
            return error.FrameSizeMismatch;
        }
        var mixer = Mixer{ .accumulator = accumulator, .channels = channels };
        mixer.beginFrame();
        return mixer;
    }

    pub fn samplesPerChannel(self: *const Mixer) usize {
        return self.accumulator.len / self.channels;
    }

    /// Start a fresh frame. Zeroes the accumulator; without this the previous
    /// frame's content is summed into this one and the mix grows without
    /// bound, which sounds like escalating distortion rather than a bug.
    pub fn beginFrame(self: *Mixer) void {
        @memset(self.accumulator, 0);
        self.voices_this_frame = 0;
    }

    pub fn setMasterVolume(self: *Mixer, volume: f32) Error!void {
        if (!std.math.isFinite(volume) or volume < 0) return error.InvalidVolume;
        self.master_volume = volume;
    }

    /// Sum one voice into the current frame.
    ///
    /// `gain` is the voice's own level, applied before the master volume so
    /// that a per-voice fade is independent of the master.
    pub fn submitVoice(self: *Mixer, samples: []const f32, gain: f32) Error!void {
        if (samples.len != self.accumulator.len) return error.FrameSizeMismatch;
        if (self.voices_this_frame >= contract.max_voice_count) return error.TooManyVoices;
        if (!std.math.isFinite(gain)) return error.InvalidVolume;

        for (samples, 0..) |sample, index| {
            // Non-finite input from a decoder must not poison the whole mix:
            // one NaN summed in makes every later sample NaN, and the device
            // plays the entire frame as silence or a click.
            const clean = if (std.math.isFinite(sample)) sample else 0;
            self.accumulator[index] += clean * gain;
        }
        self.voices_this_frame += 1;
        self.voices_mixed +|= 1;
    }

    /// Apply master volume, clamp, and write the finished frame to `out`.
    pub fn finishFrame(self: *Mixer, out: []f32) Error!void {
        if (out.len != self.accumulator.len) return error.FrameSizeMismatch;

        for (self.accumulator, 0..) |sample, index| {
            const scaled = sample * self.master_volume;
            const clamped = std.math.clamp(scaled, sample_floor, sample_ceiling);
            if (clamped != scaled) self.clamped_samples +|= 1;
            out[index] = clamped;
        }
        self.frames_completed +|= 1;
        if (self.voices_this_frame == 0) self.silent_frames +|= 1;
        self.beginFrame();
    }

    pub const Health = struct {
        frames_completed: u64,
        voices_mixed: u64,
        clamped_samples: u64,
        silent_frames: u64,

        /// What the mixer's own numbers say about the audio path.
        pub fn verdict(self: Health) []const u8 {
            if (self.frames_completed == 0) {
                return "not running: the mixer has not completed a frame";
            }
            if (self.voices_mixed == 0) {
                return "running with no voices: the mixer works, nothing submits audio";
            }
            if (self.silent_frames == self.frames_completed) {
                return "every frame empty: voices exist but none reached a frame";
            }
            if (self.clamped_samples > 0) {
                return "mixing and clipping: the summed level exceeds the output range";
            }
            return "mixing: voices are reaching completed frames";
        }
    };

    pub fn health(self: *const Mixer) Health {
        return .{
            .frames_completed = self.frames_completed,
            .voices_mixed = self.voices_mixed,
            .clamped_samples = self.clamped_samples,
            .silent_frames = self.silent_frames,
        };
    }
};

test "a mixer must be frame shaped" {
    var storage: [12]f32 = undefined;
    _ = try Mixer.init(&storage, 6);
    _ = try Mixer.init(&storage, 2);
    // 12 is not a whole number of 5-channel frames.
    try std.testing.expectError(error.FrameSizeMismatch, Mixer.init(&storage, 5));
    try std.testing.expectError(error.FrameSizeMismatch, Mixer.init(&storage, 0));
}

test "a fresh mixer is not running" {
    var storage: [12]f32 = undefined;
    const mixer = try Mixer.init(&storage, 6);
    try std.testing.expectEqualStrings(
        "not running: the mixer has not completed a frame",
        mixer.health().verdict(),
    );
    try std.testing.expectEqual(@as(usize, 2), mixer.samplesPerChannel());
}

test "one voice passes through unchanged at unit gain" {
    var storage: [4]f32 = undefined;
    var out: [4]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    try mixer.submitVoice(&[_]f32{ 0.5, -0.5, 0.25, -0.25 }, 1.0);
    try mixer.finishFrame(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0.5, -0.5, 0.25, -0.25 }, &out);
    try std.testing.expectEqual(@as(u64, 0), mixer.health().clamped_samples);
}

test "voices sum" {
    var storage: [4]f32 = undefined;
    var out: [4]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    try mixer.submitVoice(&[_]f32{ 0.25, 0.25, 0, 0 }, 1.0);
    try mixer.submitVoice(&[_]f32{ 0.25, -0.25, 0.5, 0 }, 1.0);
    try mixer.finishFrame(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0.5, 0, 0.5, 0 }, &out);
}

test "a frame does not accumulate into the next one" {
    // Without the reset the mix grows every frame, which sounds like
    // escalating distortion rather than a bug in frame handling.
    var storage: [2]f32 = undefined;
    var out: [2]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    try mixer.submitVoice(&[_]f32{ 0.5, 0.5 }, 1.0);
    try mixer.finishFrame(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0.5, 0.5 }, &out);

    try mixer.submitVoice(&[_]f32{ 0.25, 0.25 }, 1.0);
    try mixer.finishFrame(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0.25, 0.25 }, &out);
}

test "clipping is clamped and counted" {
    // Clamping is right; wrapping would turn a loud passage into noise. But a
    // silent clamp makes a systematically hot mix look like ordinary loudness.
    var storage: [2]f32 = undefined;
    var out: [2]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    try mixer.submitVoice(&[_]f32{ 0.8, -0.8 }, 1.0);
    try mixer.submitVoice(&[_]f32{ 0.8, -0.8 }, 1.0);
    try mixer.finishFrame(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 1.0, -1.0 }, &out);
    try std.testing.expectEqual(@as(u64, 2), mixer.health().clamped_samples);
    try std.testing.expectEqualStrings(
        "mixing and clipping: the summed level exceeds the output range",
        mixer.health().verdict(),
    );
}

test "master volume applies after per-voice gain" {
    var storage: [2]f32 = undefined;
    var out: [2]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    try mixer.setMasterVolume(0.5);
    try mixer.submitVoice(&[_]f32{ 1.0, 1.0 }, 0.5);
    try mixer.finishFrame(&out);
    // 1.0 * 0.5 (voice) * 0.5 (master) = 0.25.
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0.25, 0.25 }, &out);
}

test "a NaN from a decoder does not poison the frame" {
    // One NaN summed in makes every later sample NaN, and the device plays
    // the whole frame as silence or a click — a total loss from one bad value.
    var storage: [4]f32 = undefined;
    var out: [4]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    const poisoned = [_]f32{ std.math.nan(f32), 0.5, std.math.inf(f32), 0.25 };
    try mixer.submitVoice(&poisoned, 1.0);
    try mixer.finishFrame(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0, 0.5, 0, 0.25 }, &out);
    for (out) |sample| try std.testing.expect(std.math.isFinite(sample));
}

test "an invalid volume or gain is refused" {
    var storage: [2]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    try std.testing.expectError(error.InvalidVolume, mixer.setMasterVolume(-1));
    try std.testing.expectError(error.InvalidVolume, mixer.setMasterVolume(std.math.nan(f32)));
    try std.testing.expectError(error.InvalidVolume, mixer.setMasterVolume(std.math.inf(f32)));
    try std.testing.expectError(error.InvalidVolume, mixer.submitVoice(&[_]f32{ 0, 0 }, std.math.nan(f32)));
    // Above unity is legitimate: a title may boost a quiet voice.
    try mixer.setMasterVolume(2.0);
}

test "a mismatched voice length is refused" {
    var storage: [4]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    try std.testing.expectError(error.FrameSizeMismatch, mixer.submitVoice(&[_]f32{ 0, 0 }, 1.0));
    var wrong: [8]f32 = undefined;
    try std.testing.expectError(error.FrameSizeMismatch, mixer.finishFrame(&wrong));
}

test "running with no voices is distinguishable from not running" {
    // The split the counters exist for: a mixer that completes frames but
    // never receives a voice is a working mixer with nothing upstream.
    var storage: [2]f32 = undefined;
    var out: [2]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    try mixer.finishFrame(&out);
    try std.testing.expectEqualStrings(
        "running with no voices: the mixer works, nothing submits audio",
        mixer.health().verdict(),
    );
    try std.testing.expectEqual(@as(u64, 1), mixer.health().silent_frames);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0, 0 }, &out);
}

test "the console voice ceiling is enforced" {
    var storage: [2]f32 = undefined;
    var mixer = try Mixer.init(&storage, 2);
    var index: u32 = 0;
    while (index < contract.max_voice_count) : (index += 1) {
        try mixer.submitVoice(&[_]f32{ 0, 0 }, 0);
    }
    try std.testing.expectError(error.TooManyVoices, mixer.submitVoice(&[_]f32{ 0, 0 }, 0));
}
