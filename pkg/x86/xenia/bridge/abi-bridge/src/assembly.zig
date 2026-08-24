//! Representative machine-code facts for the three host backends.
//!
//! These checks intentionally stop at encoding and byte-order truth. They do
//! not claim that one NOP proves a complete assembler, register allocator, or
//! DBT. They prevent the cheaper and more dangerous mistake: treating host
//! instruction bytes as if all backends used the same word order.

const std = @import("std");
const contract = @import("contract.zig");
const target = @import("target.zig");

pub const InstructionFact = struct {
    architecture: target.Architecture,
    name: []const u8,
    bytes: []const u8,
    decoded_word: u32,
    width: u8,
};

pub const facts = [_]InstructionFact{
    .{
        .architecture = .x86_64,
        .name = "nop",
        .bytes = &[_]u8{0x90},
        .decoded_word = 0x00000090,
        .width = 1,
    },
    .{
        .architecture = .ppc64,
        .name = "nop",
        .bytes = &[_]u8{ 0x60, 0x00, 0x00, 0x00 },
        .decoded_word = 0x60000000,
        .width = 4,
    },
    .{
        .architecture = .arm64,
        .name = "nop",
        .bytes = &[_]u8{ 0x1f, 0x20, 0x03, 0xd5 },
        .decoded_word = 0xd503201f,
        .width = 4,
    },
};

pub fn fact(architecture: target.Architecture) InstructionFact {
    for (facts) |entry| {
        if (entry.architecture == architecture) return entry;
    }
    unreachable;
}

pub fn verify(entry: InstructionFact) bool {
    const profile = contract.profile(entry.architecture);
    if (entry.width != profile.host_nop_width) return false;
    if (!std.mem.eql(u8, entry.bytes, profile.host_nop_bytes)) return false;
    if (entry.width == 1) return entry.bytes[0] == 0x90 and entry.decoded_word == 0x90;
    return contract.readWord(entry.bytes, profile.host_endian) == entry.decoded_word;
}

test "representative host encodings preserve target byte order" {
    for (facts) |entry| try std.testing.expect(verify(entry));
}

test "the emulated PPC guest NOP remains distinct from host NOPs" {
    const guest_nop = [_]u8{ 0x60, 0x00, 0x00, 0x00 };
    try std.testing.expectEqual(@as(u32, 0x6000_0000), contract.readWord(&guest_nop, .big).?);
    try std.testing.expect(!std.mem.eql(u8, guest_nop[0..], fact(.x86_64).bytes));
}
