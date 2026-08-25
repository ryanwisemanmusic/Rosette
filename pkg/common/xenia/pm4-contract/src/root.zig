//! Route-independent: PM4 command packet encoding and the Type-3 opcode table.
//!
//! PM4 is the command language the Xenos command processor reads out of the
//! ring. A packet's first dword carries its type and, for Type-3, an opcode and
//! a body length; everything after depends on getting that first dword right.
//!
//! ## Length is stored biased, and that is where a walker desynchronises
//!
//! The count field holds **body length minus one**. A walker that advances by
//! the raw count lands one dword short of the next packet header, reads a body
//! dword as a header, and from that point every packet it reports is fiction.
//! The failure is not local: the first few packets parse correctly, so a log
//! shows a plausible command stream that diverges from reality partway
//! through, and the divergence is usually attributed to the producer.
//!
//! `advanceFor` exists so no caller has to remember the bias.
//!
//! ## Type 2 has no body at all
//!
//! A Type-2 packet is a single dword filler. Treating it as though it had a
//! count field consumes whatever followed it. This is the second most common
//! way a ring walk goes wrong, and it only happens on rings that have wrapped —
//! so it appears after minutes of correct operation.
//!
//! ## `PM4_XE_SWAP` is not console hardware
//!
//! Opcode 0x64 is Xenia's own invention: `VdSwap` encodes it to trigger a
//! present. Recorded here because Rosette's whole presentation frontier is
//! defined in terms of it, and because a reader should know it will never
//! appear in a capture from real hardware.
//!
//! ## What this package is not
//!
//! * It is not a parser. It holds no ring, no cursor and no packet state;
//!   `lib/gpu/pm4.zig` and `pm4_executor.zig` own execution.
//! * It does not execute. Knowing an opcode's name says nothing about whether
//!   Rosette implements it.
//! * It reads no memory. Every function here takes a dword it was handed.

const std = @import("std");

/// Packet type, from the top two bits of the header dword.
pub const PacketType = enum(u2) {
    /// Register write with an implicit incrementing base.
    type0 = 0,
    /// Two-register write. Rare.
    type1 = 1,
    /// A one-dword filler with no body. The trap.
    type2 = 2,
    /// Opcode plus body. Everything interesting.
    type3 = 3,
};

pub const type_shift: u5 = 30;
/// Both Type-0 and Type-3 keep their body length in bits 16..29.
pub const count_shift: u5 = 16;
pub const count_mask: u32 = 0x3FFF;
/// Type-3 opcode occupies bits 8..14.
pub const opcode_shift: u5 = 8;
pub const opcode_mask: u32 = 0x7F;

pub fn typeOf(header: u32) PacketType {
    return @enumFromInt(@as(u2, @truncate(header >> type_shift)));
}

/// The packet's body length in dwords.
///
/// The count field is biased by one, so a stored 0 means a one-dword body. A
/// Type-2 packet has no body and no count field, and reporting one for it is
/// how a walker consumes the dword that followed.
pub fn bodyDwords(header: u32) u32 {
    return switch (typeOf(header)) {
        .type2 => 0,
        .type0, .type1, .type3 => ((header >> count_shift) & count_mask) + 1,
    };
}

/// Total dwords to advance past this packet, header included.
pub fn advanceFor(header: u32) u32 {
    return 1 + bodyDwords(header);
}

pub fn opcodeOf(header: u32) u8 {
    return @truncate((header >> opcode_shift) & opcode_mask);
}

/// The base register index a Type-0 packet writes from.
pub fn type0BaseRegister(header: u32) u16 {
    return @truncate(header & 0x7FFF);
}

/// Type-3 opcodes.
///
/// Non-exhaustive: the command processor's opcode space is wider than the set
/// Xenia names, and a title emitting an unnamed one must be reported rather
/// than trapped on.
pub const Type3Opcode = enum(u8) {
    me_init = 0x48,
    nop = 0x10,
    indirect_buffer = 0x3F,
    indirect_buffer_pfd = 0x37,
    wait_for_idle = 0x26,
    wait_reg_mem = 0x3C,
    wait_reg_eq = 0x52,
    wait_reg_gte = 0x53,
    wait_until_read = 0x5C,
    wait_ib_pfd_complete = 0x5D,
    reg_rmw = 0x21,
    reg_to_mem = 0x3E,
    mem_write = 0x3D,
    mem_write_cntr = 0x4F,
    cond_exec = 0x44,
    cond_write = 0x45,
    event_write = 0x46,
    event_write_shd = 0x58,
    event_write_cfl = 0x59,
    event_write_ext = 0x5A,
    event_write_zpd = 0x5B,
    draw_indx = 0x22,
    draw_indx_2 = 0x36,
    draw_indx_bin = 0x34,
    draw_indx_2_bin = 0x35,
    viz_query = 0x23,
    set_state = 0x25,
    set_constant = 0x2D,
    set_constant2 = 0x55,
    set_shader_constants = 0x56,
    load_alu_constant = 0x2F,
    im_load = 0x27,
    im_load_immediate = 0x2B,
    im_store = 0x2C,
    load_constant_context = 0x2E,
    invalidate_state = 0x3B,
    set_shader_bases = 0x4A,
    set_bin_base_offset = 0x4B,
    set_bin_mask = 0x50,
    set_bin_select = 0x51,
    set_bin_mask_lo = 0x60,
    set_bin_mask_hi = 0x61,
    set_bin_select_lo = 0x62,
    set_bin_select_hi = 0x63,
    context_update = 0x5E,
    interrupt = 0x54,
    /// Xenia's own opcode. Never appears in a capture from real hardware.
    xe_swap = 0x64,
    _,

    /// Whether this packet submits geometry.
    ///
    /// The question behind "did the title draw anything". Counting a
    /// `set_constant` as a draw makes a title that only uploaded state look
    /// like one that rendered.
    pub fn isDraw(self: Type3Opcode) bool {
        return switch (self) {
            .draw_indx, .draw_indx_2, .draw_indx_bin, .draw_indx_2_bin => true,
            else => false,
        };
    }

    /// Whether this packet can block the command processor.
    ///
    /// A ring that stops draining is usually parked on one of these, waiting
    /// for a value the guest has not written.
    pub fn isBlocking(self: Type3Opcode) bool {
        return switch (self) {
            .wait_for_idle,
            .wait_reg_mem,
            .wait_reg_eq,
            .wait_reg_gte,
            .wait_until_read,
            .wait_ib_pfd_complete,
            => true,
            else => false,
        };
    }

    /// Whether this opcode is Xenia's rather than the console's.
    pub fn isEmulatorExtension(self: Type3Opcode) bool {
        return self == .xe_swap;
    }

    /// Whether the packet redirects the command processor elsewhere.
    pub fn isIndirect(self: Type3Opcode) bool {
        return self == .indirect_buffer or self == .indirect_buffer_pfd;
    }
};

/// A decoded packet header.
pub const Packet = struct {
    packet_type: PacketType,
    /// Meaningful for Type-3 only.
    opcode: u8,
    body_dwords: u32,

    pub fn advance(self: Packet) u32 {
        return 1 + self.body_dwords;
    }

    pub fn type3Opcode(self: Packet) ?Type3Opcode {
        if (self.packet_type != .type3) return null;
        return @enumFromInt(self.opcode);
    }
};

pub fn decode(header: u32) Packet {
    return .{
        .packet_type = typeOf(header),
        .opcode = opcodeOf(header),
        .body_dwords = bodyDwords(header),
    };
}

/// Whether a header could begin a real packet.
///
/// A ring that has never been written reads as all zeroes, which decodes as a
/// Type-0 packet writing one dword to register 0. That is a valid encoding and
/// a meaningless packet, so a walker needs to tell "empty ring" from "packet".
pub fn isLikelyEmptyRing(header: u32) bool {
    return header == 0 or header == 0xFFFF_FFFF;
}

pub fn contractIsWellFormed() bool {
    if (bodyDwords(0xC0000000) != 1) return false;
    if (bodyDwords(0x80000000) != 0) return false;
    if (@intFromEnum(Type3Opcode.xe_swap) != 0x64) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the type comes from the top two bits" {
    try std.testing.expectEqual(PacketType.type0, typeOf(0x0000_0000));
    try std.testing.expectEqual(PacketType.type1, typeOf(0x4000_0000));
    try std.testing.expectEqual(PacketType.type2, typeOf(0x8000_0000));
    try std.testing.expectEqual(PacketType.type3, typeOf(0xC000_0000));
}

test "the count field is biased by one" {
    // A walker that advances by the raw count lands one dword short of the
    // next header, reads a body dword as a header, and every packet it reports
    // after that is fiction — but the first few parsed correctly, so the log
    // looks plausible right up to the divergence.
    const one_dword_body: u32 = 0xC000_0000;
    try std.testing.expectEqual(@as(u32, 1), bodyDwords(one_dword_body));
    try std.testing.expectEqual(@as(u32, 2), advanceFor(one_dword_body));

    const four_dword_body: u32 = 0xC000_0000 | (3 << count_shift);
    try std.testing.expectEqual(@as(u32, 4), bodyDwords(four_dword_body));
    try std.testing.expectEqual(@as(u32, 5), advanceFor(four_dword_body));
}

test "a type 2 packet has no body and advances by one" {
    // The second most common ring-walk failure, and it only bites on a ring
    // that has wrapped — so it appears after minutes of correct operation.
    const filler: u32 = 0x8000_0000;
    try std.testing.expectEqual(PacketType.type2, typeOf(filler));
    try std.testing.expectEqual(@as(u32, 0), bodyDwords(filler));
    try std.testing.expectEqual(@as(u32, 1), advanceFor(filler));

    // Even with count bits set, a Type-2 has no body: the field is not one.
    const filler_with_bits: u32 = 0x8000_0000 | (0x3FFF << count_shift);
    try std.testing.expectEqual(@as(u32, 0), bodyDwords(filler_with_bits));
    try std.testing.expectEqual(@as(u32, 1), advanceFor(filler_with_bits));
}

test "the opcode occupies bits eight through fourteen" {
    const swap: u32 = 0xC000_0000 | (@as(u32, 0x64) << opcode_shift);
    try std.testing.expectEqual(@as(u8, 0x64), opcodeOf(swap));
    try std.testing.expectEqual(Type3Opcode.xe_swap, decode(swap).type3Opcode().?);

    const draw: u32 = 0xC000_0000 | (@as(u32, 0x22) << opcode_shift);
    try std.testing.expectEqual(Type3Opcode.draw_indx, decode(draw).type3Opcode().?);
}

test "an opcode is only meaningful for type 3" {
    // A Type-0 header has a register index where Type-3 keeps its opcode, so
    // reading one as an opcode names a packet that is not there.
    const type0: u32 = 0x0000_2200;
    try std.testing.expect(decode(type0).type3Opcode() == null);
    try std.testing.expectEqual(PacketType.type0, decode(type0).packet_type);
}

test "the type 0 base register is the low fifteen bits" {
    const write: u32 = 0x0000_0000 | 0x21F9;
    try std.testing.expectEqual(@as(u16, 0x21F9), type0BaseRegister(write));
}

test "only draw opcodes are draws" {
    // Counting a set_constant as a draw makes a title that only uploaded
    // state look like one that rendered.
    try std.testing.expect(Type3Opcode.draw_indx.isDraw());
    try std.testing.expect(Type3Opcode.draw_indx_2.isDraw());
    try std.testing.expect(Type3Opcode.draw_indx_bin.isDraw());
    try std.testing.expect(Type3Opcode.draw_indx_2_bin.isDraw());
    try std.testing.expect(!Type3Opcode.set_constant.isDraw());
    try std.testing.expect(!Type3Opcode.nop.isDraw());
    try std.testing.expect(!Type3Opcode.xe_swap.isDraw());
    try std.testing.expect(!Type3Opcode.event_write.isDraw());
}

test "waits are the packets that can park the command processor" {
    // A ring that stops draining is usually parked on one of these, waiting
    // for a value the guest has not written.
    try std.testing.expect(Type3Opcode.wait_reg_mem.isBlocking());
    try std.testing.expect(Type3Opcode.wait_for_idle.isBlocking());
    try std.testing.expect(Type3Opcode.wait_reg_eq.isBlocking());
    try std.testing.expect(Type3Opcode.wait_until_read.isBlocking());
    try std.testing.expect(!Type3Opcode.draw_indx.isBlocking());
    try std.testing.expect(!Type3Opcode.nop.isBlocking());
}

test "XE_SWAP is an emulator extension, not console hardware" {
    // Rosette's whole presentation frontier is defined in terms of this
    // opcode, and it will never appear in a capture from real hardware.
    try std.testing.expect(Type3Opcode.xe_swap.isEmulatorExtension());
    try std.testing.expect(!Type3Opcode.draw_indx.isEmulatorExtension());
    try std.testing.expect(!Type3Opcode.me_init.isEmulatorExtension());
    try std.testing.expectEqual(@as(u8, 0x64), @intFromEnum(Type3Opcode.xe_swap));
}

test "indirect buffers redirect the parser" {
    try std.testing.expect(Type3Opcode.indirect_buffer.isIndirect());
    try std.testing.expect(Type3Opcode.indirect_buffer_pfd.isIndirect());
    try std.testing.expect(!Type3Opcode.nop.isIndirect());
}

test "an unnamed opcode is carried rather than trapped on" {
    // The opcode space is wider than the set Xenia names. A checked cast would
    // trap on a title that emits one, turning an unknown packet into a crash.
    const unnamed: Type3Opcode = @enumFromInt(0x7F);
    try std.testing.expectEqual(@as(u8, 0x7F), @intFromEnum(unnamed));
    try std.testing.expect(!unnamed.isDraw());
    try std.testing.expect(!unnamed.isBlocking());
}

test "an unwritten ring is distinguishable from a packet" {
    // All-zero decodes as a valid Type-0 writing one dword to register 0. A
    // walker that does not check this reports packets from an empty ring.
    try std.testing.expect(isLikelyEmptyRing(0));
    try std.testing.expect(isLikelyEmptyRing(0xFFFF_FFFF));
    try std.testing.expect(!isLikelyEmptyRing(0xC000_0000 | (0x64 << opcode_shift)));
    // And it does decode as something, which is the problem.
    try std.testing.expectEqual(PacketType.type0, typeOf(0));
    try std.testing.expectEqual(@as(u32, 1), bodyDwords(0));
}

test "the maximum body length is fourteen bits, biased" {
    const largest: u32 = 0xC000_0000 | (count_mask << count_shift);
    try std.testing.expectEqual(@as(u32, 0x4000), bodyDwords(largest));
    try std.testing.expectEqual(@as(u32, 0x4001), advanceFor(largest));
}

test "decode agrees with the individual field readers" {
    const header: u32 = 0xC000_0000 | (5 << count_shift) | (0x22 << opcode_shift);
    const packet = decode(header);
    try std.testing.expectEqual(typeOf(header), packet.packet_type);
    try std.testing.expectEqual(opcodeOf(header), packet.opcode);
    try std.testing.expectEqual(bodyDwords(header), packet.body_dwords);
    try std.testing.expectEqual(advanceFor(header), packet.advance());
}
