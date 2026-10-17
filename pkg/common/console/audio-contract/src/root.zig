//! Route-independent: the Xbox 360 audio hardware's fixed decode and mixing
//! geometry.
//!
//! Every number here is a property of the console's APU or of the XMA bitstream
//! format, both frozen in 2005. None of them is a property of the Mac Rosette
//! runs on, so there is one copy and no route mirror — same reasoning as
//! `pkg/common/xenos/register-map`.
//!
//! ## Why these are worth stating separately from the mixer
//!
//! The audio path has an unusual failure mode: nearly every wrong constant
//! still produces sound. A frame size that is too small underruns into a click,
//! a channel count that is too low silently folds the surround bed away, and a
//! sample rate that is off by a factor plays the title at the wrong pitch. None
//! of those raise an error anywhere; a person has to *listen* and know what it
//! should have sounded like. Making the geometry a compile-time fact means the
//! mismatch is a build failure instead of an audible artifact nobody attributes
//! to the right layer.
//!
//! ## What this package is not
//!
//! * It is not a decoder. It holds no bitstream state and cannot say a frame
//!   was decoded; `lib/audio/xma_decoder.zig` owns the decode and every buffer
//!   it touches.
//! * It is not a voice table. `MaxVoiceCount` is a bound, not an allocation,
//!   and this package cannot report that any voice is playing.
//! * It does not open a device. The host driver, its callback, and its clock
//!   are `lib/audio/` and stay there.
//!
//! ## Where the numbers come from, and where the plan sketch was wrong
//!
//! The abstraction plan that requested this package sketched
//! `XmaFrameSize = 2048` as "XMA blocks are 2048 samples" and `MaxContextCount
//! = 6`. Both are off, and in the direction that produces plausible-sounding
//! garbage rather than an obvious failure:
//!
//! * 2048 is the packet size in **bytes**, not samples. An XMA frame carries
//!   512 samples per channel.
//! * 6 is the surround **channel** count, not the decode context count. The
//!   APU exposes 320 XMA contexts.
//!
//! The values below are the hardware's. `bytes_per_host_frame` is
//! cross-checkable against a completely independent part of the tree:
//! `lib/runtime/guest-abi/sdl_runtime.zig` negotiates a 48 kHz / 6-channel /
//! 256-sample float buffer and asserts the obtained size is 6144 bytes. Two
//! layers that were written apart agreeing on one number is the only real
//! evidence a constant is right.

const std = @import("std");

// ---------------------------------------------------------------------------
// XMA bitstream geometry
// ---------------------------------------------------------------------------

/// An XMA packet on the wire. Fixed: the hardware DMAs whole packets, so a
/// reader that advances by anything else desynchronises the bit cursor and
/// every later frame decodes to noise.
pub const bytes_per_packet: u32 = 2048;
pub const bits_per_packet: u32 = bytes_per_packet * 8;

/// The packet header consumed before the first frame's bits. 33 bits, not 32 —
/// the odd bit is why a byte-aligned reader silently drifts.
pub const bits_per_packet_header: u32 = 33;

/// Decoded PCM is signed 16-bit at the XMA layer. The float conversion happens
/// later, in the mixer, and is not part of the codec's contract.
pub const bytes_per_sample: u32 = 2;

/// One frame, one channel. A frame is four subframes.
pub const samples_per_frame: u32 = 512;
pub const samples_per_subframe: u32 = 128;
pub const subframes_per_frame: u32 = samples_per_frame / samples_per_subframe;

pub const bytes_per_frame_channel: u32 = samples_per_frame * bytes_per_sample;
pub const bytes_per_subframe_channel: u32 = samples_per_subframe * bytes_per_sample;

// ---------------------------------------------------------------------------
// APU resources
// ---------------------------------------------------------------------------

/// Hardware XMA decode contexts. Not the channel count, and not the voice
/// count: a context is a decoder, and several voices can be fed from one.
pub const max_context_count: u32 = 320;

/// Mixer voices the title may address.
pub const max_voice_count: u32 = 256;

/// Registered audio clients the APU will service. Xenia's audio system caps
/// this; a title that opens more is a bug in the title, not a missing feature.
pub const max_client_count: u32 = 8;

// ---------------------------------------------------------------------------
// Host frame geometry
// ---------------------------------------------------------------------------

pub const sample_rate_48k: u32 = 48000;
pub const sample_rate_24k: u32 = 24000;

/// The surround bed the console mixes into.
pub const host_frame_channels: u32 = 6;
/// Samples per channel in one host callback period.
pub const host_frame_samples_per_channel: u32 = 256;
pub const host_frame_samples: u32 = host_frame_channels * host_frame_samples_per_channel;
/// The host mixer works in 32-bit float, unlike the codec's 16-bit output.
pub const bytes_per_host_sample: u32 = 4;
/// 6144 bytes. The number `sdl_runtime.zig` independently asserts.
pub const bytes_per_host_frame: u32 = host_frame_samples * bytes_per_host_sample;

/// One callback period in nanoseconds at 48 kHz: 256 / 48000 s.
///
/// Stated as an exact integer-arithmetic expression rather than a literal so
/// it cannot drift from the two constants it depends on.
pub const host_frame_period_ns: u64 =
    @as(u64, host_frame_samples_per_channel) * 1_000_000_000 / @as(u64, sample_rate_48k);

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub const AudioFormat = enum(u8) {
    pcm_s16le,
    pcm_f32le,
    xma1,
    xma2,

    /// Whether this format needs the XMA decoder rather than a straight copy.
    pub fn requiresDecode(self: AudioFormat) bool {
        return switch (self) {
            .xma1, .xma2 => true,
            .pcm_s16le, .pcm_f32le => false,
        };
    }
};

pub const VoiceState = enum(u8) {
    idle,
    playing,
    paused,
    stopped,

    /// Whether a voice in this state should consume input data this period.
    ///
    /// `paused` and `stopped` differ on the mixer's side, not here: both stop
    /// consuming, but only `stopped` may release the context.
    pub fn consumesInput(self: VoiceState) bool {
        return self == .playing;
    }
};

/// The guest-visible XMA context block.
///
/// `extern` and explicitly ordered because the guest writes this structure in
/// its own memory and the decoder reads it back; a Zig-reordered layout would
/// read the fields in the wrong places. Physical addresses are `u32` because
/// the console's address space is 32-bit, and widening them here would let a
/// host pointer be assigned to one by mistake.
pub const XmaContext = extern struct {
    input_buffer_phys: u32 = 0,
    input_buffer_size: u32 = 0,
    output_buffer_phys: u32 = 0,
    output_buffer_size: u32 = 0,
    sample_rate: u16 = 0,
    channels: u8 = 0,
    bits_per_sample: u8 = 0,
    state: u8 = @intFromEnum(VoiceState.idle),
    format: u8 = @intFromEnum(AudioFormat.xma2),
    reserved: u16 = 0,

    /// Whether the buffers this context names could hold a whole frame.
    ///
    /// Bounds only. A true answer means the sizes are self-consistent, never
    /// that the guest actually mapped anything at those addresses — this
    /// package cannot look at guest memory and must not appear to.
    pub fn hasWellFormedBuffers(self: XmaContext) bool {
        if (self.channels == 0) return false;
        if (self.input_buffer_size < bytes_per_packet) return false;
        const needed = bytes_per_frame_channel * @as(u32, self.channels);
        return self.output_buffer_size >= needed;
    }
};

/// Whether a sample rate is one the APU actually clocks.
pub fn isSupportedSampleRate(rate: u32) bool {
    return rate == sample_rate_48k or rate == sample_rate_24k;
}

/// Bytes of decoded PCM one frame produces for a given channel count.
pub fn decodedFrameBytes(channels: u32) u32 {
    return bytes_per_frame_channel * channels;
}

/// Whether a context index addresses real decode hardware.
pub fn isContextIndex(index: u32) bool {
    return index < max_context_count;
}

/// The internal consistency this package is allowed to assert about itself.
///
/// Checked by the tests below and available to a consumer that wants to fail
/// its own build if the contract is ever edited into an impossible shape.
pub fn contractIsWellFormed() bool {
    if (samples_per_frame % samples_per_subframe != 0) return false;
    if (subframes_per_frame != 4) return false;
    if (bytes_per_packet * 8 != bits_per_packet) return false;
    if (bytes_per_host_frame != 6144) return false;
    if (max_voice_count > max_context_count) return false;
    if (!isSupportedSampleRate(sample_rate_48k)) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "a frame is four subframes, not a packet" {
    // The plan sketch read 2048 as a sample count. Packets are bytes and
    // frames are samples; conflating them makes the decoder advance the bit
    // cursor by a factor of four and every frame after the first is noise.
    try std.testing.expectEqual(@as(u32, 4), subframes_per_frame);
    try std.testing.expectEqual(@as(u32, 512), samples_per_frame);
    try std.testing.expectEqual(@as(u32, 2048), bytes_per_packet);
    try std.testing.expect(samples_per_frame != bytes_per_packet);
}

test "the packet header is not byte aligned" {
    // 33 bits. A reader that rounds this to 32 or 40 drifts one bit per packet
    // and the drift is cumulative, so early audio sounds fine and late audio
    // does not — the worst possible signature to debug from.
    try std.testing.expectEqual(@as(u32, 33), bits_per_packet_header);
    try std.testing.expect(bits_per_packet_header % 8 != 0);
}

test "the host frame matches the size SDL negotiates elsewhere" {
    // lib/runtime/guest-abi/sdl_runtime.zig asserts 6144 from the other side
    // of the tree. If either moves without the other, one of these two tests
    // fails and names the disagreement.
    try std.testing.expectEqual(@as(u32, 6144), bytes_per_host_frame);
    try std.testing.expectEqual(@as(u32, 6), host_frame_channels);
    try std.testing.expectEqual(@as(u32, 256), host_frame_samples_per_channel);
    try std.testing.expectEqual(@as(u32, 48000), sample_rate_48k);
}

test "the callback period is derived, not guessed" {
    // 256 samples at 48 kHz is 5.333... ms. Integer division truncates toward
    // 5333333 ns; a driver that budgets more than this per callback underruns.
    try std.testing.expectEqual(@as(u64, 5_333_333), host_frame_period_ns);
}

test "context indices are bounded by decode hardware, not by voices" {
    try std.testing.expect(isContextIndex(0));
    try std.testing.expect(isContextIndex(max_context_count - 1));
    try std.testing.expect(!isContextIndex(max_context_count));
    // 320 contexts, 256 voices. The plan's "6 contexts" was the channel count.
    try std.testing.expect(max_context_count > max_voice_count);
    try std.testing.expect(max_context_count != host_frame_channels);
}

test "buffer wellformedness is arithmetic, never a claim about guest memory" {
    var context = XmaContext{
        .input_buffer_phys = 0xA000_0000,
        .input_buffer_size = bytes_per_packet,
        .output_buffer_phys = 0xA001_0000,
        .output_buffer_size = decodedFrameBytes(2),
        .channels = 2,
        .sample_rate = 48000,
        .bits_per_sample = 16,
    };
    try std.testing.expect(context.hasWellFormedBuffers());

    // One byte short of a frame is not a frame.
    context.output_buffer_size -= 1;
    try std.testing.expect(!context.hasWellFormedBuffers());

    // A zero-channel context cannot be sized at all.
    context.output_buffer_size = decodedFrameBytes(2);
    context.channels = 0;
    try std.testing.expect(!context.hasWellFormedBuffers());
}

test "only playing voices consume input" {
    try std.testing.expect(VoiceState.playing.consumesInput());
    try std.testing.expect(!VoiceState.paused.consumesInput());
    try std.testing.expect(!VoiceState.stopped.consumesInput());
    try std.testing.expect(!VoiceState.idle.consumesInput());
}

test "formats split on whether the decoder is needed" {
    try std.testing.expect(AudioFormat.xma1.requiresDecode());
    try std.testing.expect(AudioFormat.xma2.requiresDecode());
    try std.testing.expect(!AudioFormat.pcm_s16le.requiresDecode());
    try std.testing.expect(!AudioFormat.pcm_f32le.requiresDecode());
}

test "the guest context block keeps the layout the guest wrote" {
    // extern layout: the guest fills this in its own memory. Field order and
    // offsets are the ABI, so they are asserted rather than assumed.
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(XmaContext, "input_buffer_phys"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(XmaContext, "input_buffer_size"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(XmaContext, "output_buffer_phys"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(XmaContext, "output_buffer_size"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(XmaContext, "sample_rate"));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(XmaContext));
    // Guest physical addresses stay 32-bit so a host pointer cannot be stored.
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(@FieldType(XmaContext, "input_buffer_phys")));
}
