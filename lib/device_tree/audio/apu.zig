//! The Xbox 360 audio processing unit.
//!
//! The APU decodes XMA in hardware and mixes into a 5.1 bed at 48 kHz. Like the
//! GPU part beside it, the numbers below are recorded because a consumer asks
//! for them, and the constraints are recorded because the runtime can be
//! checked against them.
//!
//! ## What the hardware actually fixes here
//!
//! Less than one might expect, and stating only the real constraints is the
//! point. The APU fixes its sample rates, its decode context count, and the
//! fact that decoded XMA is 16-bit while the mix bed is float. It does *not*
//! fix the host callback size, the buffer depth, or the latency — those are
//! choices Rosette makes, and a constraint claiming otherwise would refuse
//! configurations that are perfectly legal.
//!
//! The one constraint worth having is the deadline. A host callback that asks
//! for more samples than the mixer can produce in its period will underrun
//! forever, and the symptom — periodic clicking — is usually blamed on the
//! decoder rather than on a buffer size chosen once at startup.

const std = @import("std");
const constraint = @import("../constraint.zig");

pub const name = "Xenon APU";
pub const vendor = "Microsoft";

/// Hardware XMA decode contexts.
pub const decode_context_count: u32 = 320;

/// The two rates the APU clocks. A title asking for anything else is asking
/// for a rate the hardware never produced.
pub const sample_rate_hz: u32 = 48_000;
pub const half_sample_rate_hz: u32 = 24_000;

/// The surround bed.
pub const mix_channels: u32 = 6;

/// Decoded XMA is signed 16-bit. The mix is 32-bit float. These are different
/// widths on purpose, and a path that treats them as one loses either headroom
/// or precision depending on which way it collapses them.
pub const decoded_sample_bits: u32 = 16;
pub const mix_sample_bits: u32 = 32;

/// Whether the hardware clocks this rate.
pub fn clocksSampleRate(rate: u32) constraint.Check {
    if (rate == sample_rate_hz or rate == half_sample_rate_hz) {
        return constraint.permitted("apu-sample-rate");
    }
    return constraint.violation(
        "apu-sample-rate",
        "the APU clocks 48 kHz and 24 kHz; another rate resamples and shifts pitch",
    );
}

/// Whether a decode context index addresses real hardware.
pub fn addressesDecodeContext(index: u32) constraint.Check {
    if (index < decode_context_count) return constraint.permitted("apu-decode-context");
    return constraint.violation(
        "apu-decode-context",
        "no decode context at this index; the APU has 320",
    );
}

/// Whether a mixer producing `period_ns` per callback can meet a host callback
/// asking for `samples_per_channel` at `rate`.
///
/// The deadline constraint. A callback asking for fewer samples than the mixer
/// produces in a period underruns on every callback, and the periodic clicking
/// that results is usually blamed on the decoder.
pub fn meetsCallbackDeadline(
    samples_per_channel: u32,
    rate: u32,
    mixer_period_ns: u64,
) constraint.Check {
    if (rate == 0 or samples_per_channel == 0) {
        return constraint.violation("apu-callback-deadline", "a zero-length callback period");
    }
    const callback_period_ns =
        @as(u64, samples_per_channel) * 1_000_000_000 / @as(u64, rate);
    if (mixer_period_ns <= callback_period_ns) {
        return constraint.permitted("apu-callback-deadline");
    }
    return constraint.violation(
        "apu-callback-deadline",
        "the mixer's period exceeds the callback's, so every callback underruns",
    );
}

/// Buffer depth is not a hardware fact.
///
/// Stated explicitly as unconstrained rather than omitted, so a reader who
/// looks for it finds "the hardware does not fix this" rather than nothing —
/// which is the difference between a deliberate absence and an oversight.
pub fn bufferDepthRuling() constraint.Check {
    return constraint.unconstrained("apu-buffer-depth");
}

test "the APU clocks two rates and refuses the rest" {
    try std.testing.expect(clocksSampleRate(48_000).ruling == .permitted);
    try std.testing.expect(clocksSampleRate(24_000).ruling == .permitted);
    // 44.1 kHz is the rate most likely to be assumed, and it is not one.
    try std.testing.expect(clocksSampleRate(44_100).ruling == .violates_hardware);
    try std.testing.expect(!clocksSampleRate(44_100).ruling.allowed());
    try std.testing.expect(clocksSampleRate(0).ruling == .violates_hardware);
}

test "decode contexts are bounded at 320" {
    try std.testing.expect(addressesDecodeContext(0).ruling == .permitted);
    try std.testing.expect(addressesDecodeContext(319).ruling == .permitted);
    try std.testing.expect(addressesDecodeContext(320).ruling == .violates_hardware);
}

test "a callback shorter than the mixer's period is refused" {
    // 256 samples at 48 kHz is 5.33 ms. A mixer that needs 10 ms cannot meet
    // it, and the resulting periodic clicking is blamed on the decoder.
    const five_ms: u64 = 5_000_000;
    const ten_ms: u64 = 10_000_000;
    try std.testing.expect(meetsCallbackDeadline(256, 48_000, five_ms).ruling == .permitted);
    try std.testing.expect(meetsCallbackDeadline(256, 48_000, ten_ms).ruling == .violates_hardware);
    // A longer callback gives the mixer more room.
    try std.testing.expect(meetsCallbackDeadline(1024, 48_000, ten_ms).ruling == .permitted);
}

test "a degenerate callback is refused rather than dividing by zero" {
    try std.testing.expect(meetsCallbackDeadline(0, 48_000, 1).ruling == .violates_hardware);
    try std.testing.expect(meetsCallbackDeadline(256, 0, 1).ruling == .violates_hardware);
}

test "buffer depth is unconstrained, and that is not permission" {
    // The distinction the constraint module exists for: absence of a rule is
    // not approval, and a caller must not read it as one.
    const ruling = bufferDepthRuling();
    try std.testing.expect(ruling.ruling == .unconstrained);
    try std.testing.expect(ruling.ruling.allowed());
    try std.testing.expect(ruling.ruling != .permitted);
}

test "decoded and mixed samples are different widths" {
    try std.testing.expectEqual(@as(u32, 16), decoded_sample_bits);
    try std.testing.expectEqual(@as(u32, 32), mix_sample_bits);
    try std.testing.expect(decoded_sample_bits != mix_sample_bits);
}
