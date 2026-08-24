//! XMA bitstream navigation and the decode boundary.
//!
//! ## What is implemented here, and what is not
//!
//! This file implements everything about XMA that is *structural*: the packet
//! header, the bit cursor that walks frames across packet boundaries, frame
//! length extraction, and the buffer arithmetic a decode needs. That is the
//! part where a mistake is silent and cumulative, and it is the part Rosette
//! needs in order to say anything useful about a title's audio at all.
//!
//! It does **not** implement the codec core — the Huffman decode, the subband
//! reconstruction, and the inverse transform that turn frame bits into samples.
//! That is a substantial reverse-engineering effort, and a half-implemented
//! version of it is worse than none: it produces sample values, so every layer
//! above believes decoding succeeded, and the resulting noise gets attributed
//! to the mixer or the host device.
//!
//! So `decodeFrame` reports `UnimplementedCodec` and the caller substitutes
//! silence. That is a visible, attributable, countable state — `lib/audio`'s
//! health report names it — rather than a plausible wrong answer. When the
//! codec core lands it replaces exactly one function, and every test below
//! keeps its meaning.
//!
//! ## Why the bit cursor is the risky part
//!
//! XMA packets are 2048 bytes with a 33-bit header. Thirty-three is not a
//! multiple of eight, so a byte-oriented reader drifts by one bit per packet.
//! The drift is cumulative: the first second of audio decodes correctly and the
//! tenth is noise. That signature — works at first, degrades — reliably gets
//! misdiagnosed as a buffer or threading problem.

const std = @import("std");
const contract = @import("xenia_audio_contract");

pub const Error = error{
    /// The input did not contain a whole packet.
    ShortPacket,
    /// The bit cursor ran past the end of the data.
    OutOfBits,
    /// The frame's declared length is impossible.
    MalformedFrame,
    /// The output buffer cannot hold a decoded frame.
    OutputTooSmall,
    /// Structural navigation succeeded; the codec core is not implemented.
    ///
    /// Distinct from every error above: those mean the data is wrong, this
    /// means Rosette is incomplete. Collapsing them would make a missing
    /// feature look like a corrupt stream.
    UnimplementedCodec,
};

/// A most-significant-bit-first cursor over a byte slice.
///
/// MSB-first because that is the order the hardware consumes, and it is not
/// interchangeable with LSB-first: reading the same bytes the other way round
/// yields values that are plausible and wrong.
pub const BitCursor = struct {
    data: []const u8,
    /// Position in bits, not bytes. The whole point.
    bit_position: usize = 0,

    pub fn init(data: []const u8) BitCursor {
        return .{ .data = data };
    }

    pub fn bitsRemaining(self: *const BitCursor) usize {
        const total = self.data.len * 8;
        return if (self.bit_position >= total) 0 else total - self.bit_position;
    }

    /// Read `count` bits, most significant first.
    pub fn read(self: *BitCursor, count: u6) Error!u32 {
        if (count == 0) return 0;
        if (count > 32) return error.OutOfBits;
        if (self.bitsRemaining() < count) return error.OutOfBits;

        var value: u32 = 0;
        var taken: u6 = 0;
        while (taken < count) : (taken += 1) {
            const bit_index = self.bit_position + taken;
            const byte = self.data[bit_index / 8];
            const shift: u3 = @intCast(7 - (bit_index % 8));
            const bit = (byte >> shift) & 1;
            value = (value << 1) | bit;
        }
        self.bit_position += count;
        return value;
    }

    /// Look at the next bits without consuming them.
    pub fn peek(self: *const BitCursor, count: u6) Error!u32 {
        var copy = self.*;
        return copy.read(count);
    }

    pub fn skip(self: *BitCursor, count: usize) Error!void {
        if (self.bitsRemaining() < count) return error.OutOfBits;
        self.bit_position += count;
    }

    /// Move to an absolute bit offset.
    pub fn seekBits(self: *BitCursor, position: usize) Error!void {
        if (position > self.data.len * 8) return error.OutOfBits;
        self.bit_position = position;
    }

    pub fn isByteAligned(self: *const BitCursor) bool {
        return self.bit_position % 8 == 0;
    }
};

/// An XMA packet header.
///
/// The header is 32 bits of fields plus one further bit the hardware consumes,
/// which is where the 33 in the contract comes from. Getting that final bit
/// wrong is the drift described above.
pub const PacketHeader = struct {
    /// Frames beginning inside this packet.
    frame_count: u32,
    /// Bit offset of the first frame that *starts* here. A packet whose frames
    /// all continue from earlier has no start offset in range.
    first_frame_offset_bits: u32,
    /// Packets this stream's metadata spans.
    packet_metadata: u32,
    /// Packets that must be skipped to reach the next one for this stream.
    packet_skip: u32,

    /// Whether any frame begins in this packet.
    ///
    /// A packet that only carries the tail of a frame started earlier is
    /// normal, not an error. Treating it as one drops long frames.
    pub fn hasFrameStart(self: PacketHeader) bool {
        return self.frame_count > 0 and
            self.first_frame_offset_bits < contract.bits_per_packet;
    }
};

/// Parse the header at the front of a packet.
pub fn parsePacketHeader(packet: []const u8) Error!PacketHeader {
    if (packet.len < contract.bytes_per_packet) return error.ShortPacket;
    var cursor = BitCursor.init(packet);
    return .{
        .frame_count = try cursor.read(6),
        .first_frame_offset_bits = try cursor.read(15),
        .packet_metadata = try cursor.read(3),
        .packet_skip = try cursor.read(8),
    };
}

/// Bit position of the first frame in a packet, measured from the packet start.
///
/// The header is 32 bits of fields; the frame offset is relative to the end of
/// those 32 bits, and the extra header bit is part of the offset's own frame of
/// reference. Computed in one place so no caller has to reconstruct it.
pub fn firstFrameBitPosition(header: PacketHeader) u32 {
    return 32 + header.first_frame_offset_bits;
}

/// Bits in a frame's length prefix. The declared length includes these.
pub const frame_length_prefix_bits: u32 = 15;

/// A frame's declared length in bits, read at the cursor.
///
/// XMA frames carry a 15-bit length prefix. A length of zero or one that runs
/// past the buffer is malformed; both are refused rather than clamped, because
/// a clamped length decodes a frame that was never there.
pub fn readFrameLengthBits(cursor: *BitCursor) Error!u32 {
    const length = try cursor.read(@intCast(frame_length_prefix_bits));
    if (length == 0) return error.MalformedFrame;
    return length;
}

/// Decode one frame into `output`.
///
/// Structural checks run first and report real problems in the data. Only once
/// the frame is navigable does this report `UnimplementedCodec`, so a caller
/// can tell "this stream is broken" from "Rosette cannot decode this yet".
pub fn decodeFrame(
    cursor: *BitCursor,
    channels: u32,
    output: []f32,
) Error!void {
    if (channels == 0) return error.MalformedFrame;
    const needed = contract.samples_per_frame * channels;
    if (output.len < needed) return error.OutputTooSmall;

    const length_bits = try readFrameLengthBits(cursor);
    // An XMA frame's declared length counts from the start of its own length
    // field, so the payload still to come is 15 bits shorter. A frame shorter
    // than its own prefix is malformed rather than empty.
    if (length_bits <= frame_length_prefix_bits) return error.MalformedFrame;
    const payload_bits = length_bits - frame_length_prefix_bits;
    if (cursor.bitsRemaining() < payload_bits) return error.MalformedFrame;

    return error.UnimplementedCodec;
}

/// Samples one decoded frame yields for a channel count.
pub fn decodedFrameSamples(channels: u32) u32 {
    return contract.samples_per_frame * channels;
}

test "the bit cursor reads most significant first" {
    // LSB-first would yield plausible, wrong values from the same bytes.
    var cursor = BitCursor.init(&[_]u8{ 0b1010_0000, 0b0000_0000 });
    try std.testing.expectEqual(@as(u32, 0b101), try cursor.read(3));
    try std.testing.expectEqual(@as(usize, 3), cursor.bit_position);
    try std.testing.expectEqual(@as(u32, 0), try cursor.read(3));
}

test "the cursor crosses byte boundaries without realigning" {
    // A read that spans two bytes is the common case for a 15-bit field, and
    // a reader that silently realigns to the next byte drops bits.
    var cursor = BitCursor.init(&[_]u8{ 0xFF, 0x00 });
    try std.testing.expectEqual(@as(u32, 0b1111), try cursor.read(4));
    try std.testing.expectEqual(@as(u32, 0b1111_0000), try cursor.read(8));
    try std.testing.expectEqual(@as(usize, 12), cursor.bit_position);
    try std.testing.expect(!cursor.isByteAligned());
}

test "a 33 bit header leaves the cursor unaligned" {
    // The drift the contract warns about: after one header the cursor is one
    // bit past a byte boundary, and a byte-oriented reader would round it away.
    var cursor = BitCursor.init(&[_]u8{0} ** 8);
    try cursor.skip(contract.bits_per_packet_header);
    try std.testing.expectEqual(@as(usize, 33), cursor.bit_position);
    try std.testing.expect(!cursor.isByteAligned());
    // Rounding to 32 or 40 is exactly the mistake.
    try std.testing.expect(cursor.bit_position != 32);
    try std.testing.expect(cursor.bit_position != 40);
}

test "reading past the end is refused rather than returning zeros" {
    var cursor = BitCursor.init(&[_]u8{0xFF});
    try std.testing.expectEqual(@as(u32, 0xFF), try cursor.read(8));
    try std.testing.expectEqual(@as(usize, 0), cursor.bitsRemaining());
    try std.testing.expectError(error.OutOfBits, cursor.read(1));
    // Zeros here would decode as a valid silent frame.
    try std.testing.expectError(error.OutOfBits, cursor.skip(1));
}

test "peeking does not consume" {
    var cursor = BitCursor.init(&[_]u8{0b1100_0000});
    try std.testing.expectEqual(@as(u32, 0b11), try cursor.peek(2));
    try std.testing.expectEqual(@as(usize, 0), cursor.bit_position);
    try std.testing.expectEqual(@as(u32, 0b11), try cursor.read(2));
    try std.testing.expectEqual(@as(usize, 2), cursor.bit_position);
}

test "a short buffer is not a packet" {
    const runt = [_]u8{0} ** 100;
    try std.testing.expectError(error.ShortPacket, parsePacketHeader(&runt));
}

test "a packet header reports its frame count and offset" {
    var packet = [_]u8{0} ** contract.bytes_per_packet;
    // frame_count = 2 in the top six bits.
    packet[0] = 0b0000_1000;
    const header = try parsePacketHeader(&packet);
    try std.testing.expectEqual(@as(u32, 2), header.frame_count);
    try std.testing.expect(header.hasFrameStart());
}

test "a packet carrying only a continuation has no frame start" {
    // Normal, not an error. Refusing it would drop every frame long enough to
    // span a packet boundary.
    const packet = [_]u8{0} ** contract.bytes_per_packet;
    const header = try parsePacketHeader(&packet);
    try std.testing.expectEqual(@as(u32, 0), header.frame_count);
    try std.testing.expect(!header.hasFrameStart());
}

test "the first frame position accounts for the header fields" {
    const header = PacketHeader{
        .frame_count = 1,
        .first_frame_offset_bits = 1,
        .packet_metadata = 0,
        .packet_skip = 0,
    };
    try std.testing.expectEqual(@as(u32, 33), firstFrameBitPosition(header));
}

test "a zero length frame is malformed, not empty" {
    var cursor = BitCursor.init(&[_]u8{ 0, 0, 0, 0 });
    try std.testing.expectError(error.MalformedFrame, readFrameLengthBits(&cursor));
}

test "an undersized output buffer is refused before anything is read" {
    var cursor = BitCursor.init(&[_]u8{0xFF} ** 64);
    var output: [16]f32 = undefined;
    try std.testing.expectError(error.OutputTooSmall, decodeFrame(&cursor, 2, &output));
    // The cursor must not have moved: a refused decode cannot consume bits, or
    // a retry with a bigger buffer would start mid-frame.
    try std.testing.expectEqual(@as(usize, 0), cursor.bit_position);
}

test "zero channels is malformed" {
    var cursor = BitCursor.init(&[_]u8{0xFF} ** 64);
    var output: [4096]f32 = undefined;
    try std.testing.expectError(error.MalformedFrame, decodeFrame(&cursor, 0, &output));
}

test "a navigable frame reports the codec gap, not a data error" {
    // The distinction the caller needs: the stream is fine, Rosette is
    // incomplete. Reporting MalformedFrame here would send someone looking
    // for corruption that is not there.
    //
    // A 15-bit length prefix of 100, then payload. 100 as a 15-bit field is
    // 000000001100100, so byte 0 is 0x00 and byte 1 carries 1100100 in its
    // top seven bits.
    var data = [_]u8{0xFF} ** 512;
    data[0] = 0x00;
    data[1] = 0xC8;
    var cursor = BitCursor.init(&data);
    var output: [1024]f32 = undefined;
    try std.testing.expectError(error.UnimplementedCodec, decodeFrame(&cursor, 2, &output));
}

test "a frame declaring more bits than exist is malformed" {
    // 0x7FFF is the largest 15-bit length; a 64-byte buffer cannot hold it.
    // This must stay distinguishable from the codec gap above.
    var data = [_]u8{0xFF} ** 64;
    var cursor = BitCursor.init(&data);
    var output: [1024]f32 = undefined;
    try std.testing.expectError(error.MalformedFrame, decodeFrame(&cursor, 2, &output));
}

test "a frame shorter than its own length prefix is malformed" {
    // Length 10, which cannot even contain the 15-bit field that declared it.
    var data = [_]u8{0} ** 64;
    data[0] = 0x00;
    data[1] = 0x14; // 0000000 0001010 0 -> 10 in the 15-bit field
    var cursor = BitCursor.init(&data);
    var output: [1024]f32 = undefined;
    try std.testing.expectError(error.MalformedFrame, decodeFrame(&cursor, 2, &output));
}

test "frame sample counts follow the console contract" {
    try std.testing.expectEqual(@as(u32, 512), decodedFrameSamples(1));
    try std.testing.expectEqual(@as(u32, 1024), decodedFrameSamples(2));
    try std.testing.expectEqual(contract.samples_per_frame * 6, decodedFrameSamples(6));
}

test "seeking is bounded by the buffer" {
    var cursor = BitCursor.init(&[_]u8{ 0, 0 });
    try cursor.seekBits(16);
    try std.testing.expectEqual(@as(usize, 0), cursor.bitsRemaining());
    try std.testing.expectError(error.OutOfBits, cursor.seekBits(17));
}
