//! PM4 — the Xenos command language, encoded and decoded as data.
//!
//! Everything a title tells its GPU travels through one ring buffer as a
//! sequence of PM4 packets. The command processor reads them, and the presenter
//! only ever runs because one particular packet arrived. So a harness that
//! wants to answer "did the frame get submitted?" — or to supply the packet a
//! stalled title never wrote — needs to speak this language rather than infer
//! it from counters.
//!
//! ## Why this is a library and not a few constants
//!
//! The temptation is to hardcode the five dwords of a swap packet at the call
//! site. That produces a value that is correct exactly once: the header packs a
//! type, a count and an opcode into overlapping bit ranges, the count is stored
//! biased by one, and the ring stores dwords big-endian because the guest is
//! PowerPC while the host is not. Each of those is a silent corruption rather
//! than an error — a count off by one makes the command processor read the next
//! packet's header as payload, and a byte order mistake makes a valid packet
//! decode as an unknown opcode. None of them return a failure code.
//!
//! Encoding and decoding therefore live together and are tested against each
//! other. A packet this module writes is a packet it can read back, and the
//! round trip is the only cheap proof that the bit packing is right.
//!
//! ## What a swap actually is
//!
//! `VdSwap` does not present. It *writes*: the title reserves 64 dwords of its
//! own ring, calls `VdSwap`, and the kernel fills those dwords with a texture
//! fetch constant describing the front buffer followed by an `XE_SWAP` packet
//! carrying the front buffer's physical address and extent. The title then
//! advances the write pointer, and the command processor — running on its own
//! thread, at its own pace — decodes the packet and issues the swap.
//!
//! That split is the whole reason a harness can help here. The packet is
//! *data*, deposited in memory the harness can already read and write, and
//! everything downstream of it is the emulator's own authentic code path. A
//! harness that writes this packet is not pretending to be the command
//! processor, the presenter, or the driver: it is supplying sixty-four dwords
//! and letting the real implementation do the rest.
//!
//! Nothing here reads or writes memory. It is arithmetic over dwords, so it can
//! be tested exhaustively without a guest, and the code that does own guest
//! memory stays in one place (`ring_injection.zig`).

const std = @import("std");

/// The two bits at the top of every packet header. The command processor
/// switches on this before anything else, so a packet whose type is wrong is
/// not a malformed packet — it is a different packet.
pub const PacketType = enum(u2) {
    /// A run of register writes starting at a base index.
    type0 = 0,
    /// Two register writes packed into one dword. Rare; the Xenos scarcely
    /// uses it, and the command processor treats it as legacy.
    type1 = 1,
    /// A no-op filler. The ring is pre-filled with these so that a partially
    /// written span decodes as "nothing here" rather than as garbage.
    type2 = 2,
    /// An opcode-dispatched command. Draws, event writes and the swap.
    type3 = 3,
};

/// Type-3 opcodes this module knows by name.
///
/// Deliberately not the full table: an opcode the harness never encodes and
/// never has to recognise adds a name that can drift out of step with the
/// emulator's own list. `XE_SWAP` is here because it is the entire point, and
/// the others because a decoder that cannot name what it found reports every
/// packet as unknown and hides a real mismatch.
pub const Type3Opcode = enum(u7) {
    me_init = 0x48,
    nop = 0x10,
    indirect_buffer = 0x3F,
    indirect_buffer_pfd = 0x37,
    wait_for_idle = 0x26,
    wait_reg_mem = 0x3C,
    wait_reg_eq = 0x52,
    wait_reg_gte = 0x53,
    reg_rmw = 0x21,
    reg_to_mem = 0x3E,
    mem_write = 0x3D,
    mem_write_cntr = 0x4F,
    cond_write = 0x45,
    event_write = 0x46,
    event_write_shd = 0x58,
    event_write_cfl = 0x59,
    event_write_ext = 0x5A,
    event_write_zpd = 0x5B,
    cond_exec = 0x44,
    draw_indx = 0x22,
    draw_indx_bin = 0x34,
    draw_indx_2_bin = 0x35,
    draw_indx_2 = 0x36,
    viz_query = 0x23,
    set_state = 0x25,
    set_constant = 0x2D,
    set_constant2 = 0x55,
    load_alu_constant = 0x2F,
    set_shader_constants = 0x56,
    im_load = 0x27,
    im_load_immediate = 0x2B,
    invalidate_state = 0x3B,
    set_shader_bases = 0x4A,
    set_bin_base_offset = 0x4B,
    im_store = 0x2C,
    load_constant_context = 0x2E,
    wait_until_read = 0x5C,
    wait_ib_pfd_complete = 0x5D,
    interrupt = 0x54,
    set_bin_mask = 0x50,
    set_bin_select = 0x51,
    context_update = 0x5E,
    set_bin_mask_lo = 0x60,
    set_bin_mask_hi = 0x61,
    set_bin_select_lo = 0x62,
    set_bin_select_hi = 0x63,
    /// Emulator-specific. The Xbox 360 kernel's `VdSwap` posts this to tell the
    /// command processor to present, and no real Xenos ever saw it. That is why
    /// a harness may write it: it is a message between two halves of the
    /// emulator, not a hardware command.
    xe_swap = 0x64,
    _,

    pub fn label(self: Type3Opcode) []const u8 {
        return switch (self) {
            .me_init => "ME_INIT",
            .nop => "NOP",
            .indirect_buffer => "INDIRECT_BUFFER",
            .indirect_buffer_pfd => "INDIRECT_BUFFER_PFD",
            .wait_for_idle => "WAIT_FOR_IDLE",
            .wait_reg_mem => "WAIT_REG_MEM",
            .wait_reg_eq => "WAIT_REG_EQ",
            .wait_reg_gte => "WAIT_REG_GTE",
            .reg_rmw => "REG_RMW",
            .reg_to_mem => "REG_TO_MEM",
            .mem_write => "MEM_WRITE",
            .mem_write_cntr => "MEM_WRITE_CNTR",
            .cond_write => "COND_WRITE",
            .event_write => "EVENT_WRITE",
            .event_write_shd => "EVENT_WRITE_SHD",
            .event_write_cfl => "EVENT_WRITE_CFL",
            .event_write_ext => "EVENT_WRITE_EXT",
            .event_write_zpd => "EVENT_WRITE_ZPD",
            .cond_exec => "COND_EXEC",
            .draw_indx => "DRAW_INDX",
            .draw_indx_bin => "DRAW_INDX_BIN",
            .draw_indx_2_bin => "DRAW_INDX_2_BIN",
            .draw_indx_2 => "DRAW_INDX_2",
            .viz_query => "VIZ_QUERY",
            .set_state => "SET_STATE",
            .set_constant => "SET_CONSTANT",
            .set_constant2 => "SET_CONSTANT2",
            .load_alu_constant => "LOAD_ALU_CONSTANT",
            .set_shader_constants => "SET_SHADER_CONSTANTS",
            .im_load => "IM_LOAD",
            .im_load_immediate => "IM_LOAD_IMMEDIATE",
            .invalidate_state => "INVALIDATE_STATE",
            .set_shader_bases => "SET_SHADER_BASES",
            .set_bin_base_offset => "SET_BIN_BASE_OFFSET",
            .im_store => "IM_STORE",
            .load_constant_context => "LOAD_CONSTANT_CONTEXT",
            .wait_until_read => "WAIT_UNTIL_READ",
            .wait_ib_pfd_complete => "WAIT_IB_PFD_COMPLETE",
            .interrupt => "INTERRUPT",
            .set_bin_mask => "SET_BIN_MASK",
            .set_bin_select => "SET_BIN_SELECT",
            .context_update => "CONTEXT_UPDATE",
            .set_bin_mask_lo => "SET_BIN_MASK_LO",
            .set_bin_mask_hi => "SET_BIN_MASK_HI",
            .set_bin_select_lo => "SET_BIN_SELECT_LO",
            .set_bin_select_hi => "SET_BIN_SELECT_HI",
            .xe_swap => "XE_SWAP",
            _ => "unnamed",
        };
    }

    /// Whether this opcode is one a title issues to make pixels. Used to
    /// distinguish "the guest submitted setup" from "the guest submitted a
    /// frame", which read identically in a packet count.
    pub fn isDraw(self: Type3Opcode) bool {
        return switch (self) {
            .draw_indx, .draw_indx_2 => true,
            else => false,
        };
    }
};

/// The register index a front buffer's texture fetch constant is written to.
/// A swap is preceded by a type-0 write of six dwords here, because the
/// command processor needs the front buffer's format and tiling and the swap
/// packet itself carries only an address and an extent.
pub const shader_constant_fetch_00_0: u16 = 0x4800;

/// `'SWAP'` big-endian. The command processor asserts on it before reading the
/// rest of the packet, which makes it the cheapest possible check that a span
/// of ring memory really is a swap and not a coincidence.
pub const swap_signature: u32 = 0x53574150;

/// Dwords `VdSwap` is given to work with. The title reserves this much of its
/// own ring before calling, so a harness writing the same packet must not
/// exceed it: the dwords past the end belong to whatever the title queued next.
pub const swap_reservation_dwords: u32 = 64;

/// A type-0 header: `tt cccccccccccccc o iiiiiiiiiiiiiii`.
///
/// `count` is the number of dwords that follow, stored biased by one. Passing
/// zero is a caller error rather than an empty packet, so it is rejected rather
/// than encoded as a count of 0x4000.
pub fn packetType0(index: u16, count: u16, one_register: bool) ?u32 {
    if (count == 0 or count > 0x4000) return null;
    if (index > 0x7FFF) return null;
    const biased: u32 = @as(u32, count - 1) & 0x3FFF;
    const one_bit: u32 = if (one_register) 1 << 15 else 0;
    return (biased << 16) | one_bit | (@as(u32, index) & 0x7FFF);
}

/// A type-2 filler. The ring is padded with these so a reader that runs past
/// the written span finds no-ops instead of stale dwords from a previous frame.
pub fn packetType2() u32 {
    return @as(u32, 2) << 30;
}

/// A type-1 header carries two register indices in the header and two values
/// in its payload.  Keeping the packing here prevents the executor from
/// treating the first payload value as a register number.
pub fn packetType1(register_one: u16, register_two: u16) ?u32 {
    if (register_one > 0x7FF or register_two > 0x7FF) return null;
    return (@as(u32, 1) << 30) |
        (@as(u32, register_two) << 11) |
        @as(u32, register_one);
}

/// A type-3 header: `tt cccccccccccccc ? ooooooo ??????? p`.
pub fn packetType3(opcode: Type3Opcode, count: u16, predicated: bool) ?u32 {
    if (count == 0 or count > 0x4000) return null;
    const biased: u32 = @as(u32, count - 1) & 0x3FFF;
    const op: u32 = (@as(u32, @intFromEnum(opcode)) & 0x7F) << 8;
    return (@as(u32, 3) << 30) | (biased << 16) | op | @as(u32, @intFromBool(predicated));
}

/// What one header dword says about itself, without reading the payload.
pub const Header = struct {
    raw: u32,
    kind: PacketType,
    /// Dwords following the header. Always the unbiased count.
    count: u16,
    /// Type-0 only: the first register index written.
    register_index: u16 = 0,
    /// Type-1 only: the second register index written.
    register_index_2: u16 = 0,
    /// Type-0 only: whether every dword targets the same register.
    one_register: bool = false,
    /// Type-3 only.
    opcode: Type3Opcode = @enumFromInt(0),
    predicated: bool = false,

    /// Total dwords the packet occupies, header included. This is what a reader
    /// advances by, and getting it from the same place that decoded the header
    /// is what stops a caller re-deriving the bias and getting it wrong.
    pub fn totalDwords(self: Header) u32 {
        return switch (self.kind) {
            .type2 => 1,
            else => 1 + @as(u32, self.count),
        };
    }
};

pub fn decodeHeader(raw: u32) Header {
    const kind: PacketType = @enumFromInt(@as(u2, @truncate(raw >> 30)));
    const count: u16 = @intCast(((raw >> 16) & 0x3FFF) + 1);
    return switch (kind) {
        .type0 => .{
            .raw = raw,
            .kind = kind,
            .count = count,
            .register_index = @intCast(raw & 0x7FFF),
            .one_register = (raw & (1 << 15)) != 0,
        },
        .type1 => .{
            .raw = raw,
            .kind = kind,
            .count = 2,
            .register_index = @intCast(raw & 0x7FF),
            .register_index_2 = @intCast((raw >> 11) & 0x7FF),
        },
        // A type-2 dword carries no count at all. Reporting the bits that
        // happen to sit in the count field would make a filler dword look like
        // a 1..0x4000-dword packet to anything that did not switch on the type
        // first.
        .type2 => .{ .raw = raw, .kind = kind, .count = 0 },
        .type3 => .{
            .raw = raw,
            .kind = kind,
            .count = count,
            .opcode = @enumFromInt(@as(u7, @truncate(raw >> 8))),
            .predicated = (raw & 1) != 0,
        },
    };
}

/// The front buffer a swap names. Everything the presenter needs and nothing
/// it does not: the command processor resolves format and tiling from the
/// fetch constant that precedes the packet, not from here.
pub const SwapDescription = struct {
    /// Physical address of the front buffer. Physical, not virtual: `VdSwap`
    /// translates before writing because the GPU has no MMU.
    frontbuffer_physical_address: u32,
    width: u32,
    height: u32,

    /// Whether the extent is one a display could plausibly have produced.
    /// Guards the substitution path: writing a swap for a 0x0 or 30000x2 front
    /// buffer would make the command processor assert rather than present, and
    /// an assert inside the emulator is much harder to attribute than a refusal
    /// here.
    pub fn plausible(self: SwapDescription) bool {
        if (self.frontbuffer_physical_address == 0) return false;
        if (self.width < 64 or self.height < 64) return false;
        if (self.width > 4096 or self.height > 4096) return false;
        return true;
    }
};

/// A Xenos texture fetch constant, as six dwords.
///
/// The field placement is transcribed from the hardware's own bitfields, not
/// guessed. Two of them sit where a reader would not expect: the base address
/// is in the *second* dword rather than the first, and the tiled flag is the
/// top bit of the first. Reading the base out of dword 0 yields a plausible
/// page-aligned address made of clamp modes and sign bits, and the front buffer
/// it names is real memory holding something else entirely — an image, not an
/// error.
///
/// Only the fields a front buffer description needs are modelled. The rest is
/// sampler state a swap never reads.
pub const FetchConstant = struct {
    dwords: [6]u32 = [_]u32{0} ** 6,

    /// Physical address of the surface. Stored as a 4 KiB page index in the top
    /// twenty bits of dword 1.
    pub fn baseAddress(self: FetchConstant) u32 {
        return self.dwords[1] & 0xFFFF_F000;
    }

    pub fn setBaseAddress(self: *FetchConstant, address: u32) void {
        self.dwords[1] = (self.dwords[1] & 0x0000_0FFF) | (address & 0xFFFF_F000);
    }

    /// Whether the surface is stored in the 32x32-block swizzle rather than in
    /// scanline order. Top bit of dword 0.
    pub fn tiled(self: FetchConstant) bool {
        return (self.dwords[0] & (1 << 31)) != 0;
    }

    pub fn setTiled(self: *FetchConstant, value: bool) void {
        if (value) {
            self.dwords[0] |= @as(u32, 1) << 31;
        } else {
            self.dwords[0] &= ~(@as(u32, 1) << 31);
        }
    }

    /// Row pitch in 32-texel units, dword 0 bits 22..30. Zero means the pitch
    /// is the aligned width.
    pub fn pitchTexels(self: FetchConstant) u32 {
        return ((self.dwords[0] >> 22) & 0x1FF) * 32;
    }

    /// The byte-order swizzle the GPU applies when reading, dword 1 bits 6..7.
    /// Returned as the raw two bits so the presentation layer owns the meaning.
    pub fn endianness(self: FetchConstant) u2 {
        return @truncate(self.dwords[1] >> 6);
    }

    pub fn setEndianness(self: *FetchConstant, value: u2) void {
        self.dwords[1] = (self.dwords[1] & ~@as(u32, 0xC0)) | (@as(u32, value) << 6);
    }

    /// Pixel format, dword 1 bits 0..5.
    pub fn format(self: FetchConstant) u6 {
        return @truncate(self.dwords[1]);
    }

    pub fn setFormat(self: *FetchConstant, value: u6) void {
        self.dwords[1] = (self.dwords[1] & ~@as(u32, 0x3F)) | value;
    }

    /// Dword 2 holds a 2D size as two 13-bit fields, each stored one less than
    /// the real extent.
    pub fn size2d(self: FetchConstant) struct { width: u32, height: u32 } {
        return .{
            .width = (self.dwords[2] & 0x1FFF) + 1,
            .height = ((self.dwords[2] >> 13) & 0x1FFF) + 1,
        };
    }

    pub fn setSize2d(self: *FetchConstant, width: u32, height: u32) void {
        const w: u32 = (@min(@max(width, 1), 0x2000) - 1) & 0x1FFF;
        const h: u32 = (@min(@max(height, 1), 0x2000) - 1) & 0x1FFF;
        self.dwords[2] = (self.dwords[2] & ~@as(u32, 0x03FF_FFFF)) | w | (h << 13);
    }
};

/// The dwords `VdSwap` would have written, in ring order.
///
/// Returns the number of dwords used. The caller supplies the buffer so this
/// stays allocation-free and so the same routine can write into a scratch array
/// for a test and into mapped guest memory in a run.
///
/// The trailing fill matters as much as the packet: the title reserved 64
/// dwords and the command processor will read all of them, so anything left
/// from a previous frame would decode as commands. `VdSwap` zeroes and then
/// no-op fills, and this does the same for the same reason.
pub fn encodeSwapSequence(
    out: []u32,
    fetch: FetchConstant,
    swap: SwapDescription,
    fill_dwords: u32,
) ?u32 {
    const fetch_header = packetType0(shader_constant_fetch_00_0, 6, false) orelse return null;
    const swap_header = packetType3(.xe_swap, 4, false) orelse return null;
    const required: u32 = @max(fill_dwords, 12);
    if (out.len < required) return null;

    var at: u32 = 0;
    out[at] = fetch_header;
    at += 1;
    for (fetch.dwords) |dword| {
        out[at] = dword;
        at += 1;
    }
    out[at] = swap_header;
    at += 1;
    out[at] = swap_signature;
    at += 1;
    out[at] = swap.frontbuffer_physical_address;
    at += 1;
    out[at] = swap.width;
    at += 1;
    out[at] = swap.height;
    at += 1;

    const filler = packetType2();
    while (at < required) : (at += 1) out[at] = filler;
    return required;
}

/// Read a swap back out of a dword span, if one is there.
///
/// Used two ways, and the second is why it exists: to confirm the harness wrote
/// what it meant to, and to recognise an *authentic* swap the title wrote so
/// the substitution path can stand down. A harness that cannot recognise the
/// real thing will keep substituting after the title recovers, and every frame
/// after that would be mislabelled.
pub fn decodeSwapSequence(dwords: []const u32) ?SwapDescription {
    var index: usize = 0;
    while (index < dwords.len) {
        const header = decodeHeader(dwords[index]);
        if (header.kind == .type3 and header.opcode == .xe_swap) {
            // Signature, address, width, height.
            if (header.count < 4) return null;
            if (index + 5 > dwords.len) return null;
            if (dwords[index + 1] != swap_signature) return null;
            return .{
                .frontbuffer_physical_address = dwords[index + 2],
                .width = dwords[index + 3],
                .height = dwords[index + 4],
            };
        }
        const advance = header.totalDwords();
        // A count that overruns the span means the reader has lost sync; say
        // so by stopping rather than walking off the end reinterpreting data.
        if (advance == 0 or index + advance > dwords.len) return null;
        index += advance;
    }
    return null;
}

/// Whether a dword span contains a draw. Answers "did the guest submit a
/// frame" separately from "did the guest submit anything", which a dword count
/// cannot.
pub fn containsDraw(dwords: []const u32) bool {
    var index: usize = 0;
    while (index < dwords.len) {
        const header = decodeHeader(dwords[index]);
        if (header.kind == .type3 and header.opcode.isDraw()) return true;
        const advance = header.totalDwords();
        if (advance == 0 or index + advance > dwords.len) return false;
        index += advance;
    }
    return false;
}

test "a type-3 header round-trips through its own decoder" {
    const raw = packetType3(.xe_swap, 4, false).?;
    const header = decodeHeader(raw);
    try std.testing.expectEqual(PacketType.type3, header.kind);
    try std.testing.expectEqual(Type3Opcode.xe_swap, header.opcode);
    try std.testing.expectEqual(@as(u16, 4), header.count);
    try std.testing.expect(!header.predicated);
    // Header plus its four payload dwords.
    try std.testing.expectEqual(@as(u32, 5), header.totalDwords());
}

// The bias is stored, not the count, and the two differ by exactly the amount
// that makes a reader consume the following packet's header as payload.
test "the packet count is stored biased by one and decoded unbiased" {
    const raw = packetType3(.draw_indx, 1, false).?;
    try std.testing.expectEqual(@as(u32, 0), (raw >> 16) & 0x3FFF);
    try std.testing.expectEqual(@as(u16, 1), decodeHeader(raw).count);

    const big = packetType3(.nop, 0x4000, false).?;
    try std.testing.expectEqual(@as(u16, 0x4000), decodeHeader(big).count);
}

test "a zero or oversized count is refused rather than wrapped" {
    try std.testing.expect(packetType3(.nop, 0, false) == null);
    try std.testing.expect(packetType3(.nop, 0x4001, false) == null);
    try std.testing.expect(packetType0(0x4800, 0, false) == null);
    try std.testing.expect(packetType0(0x8000, 1, false) == null);
}

test "a type-0 header carries its register index and run length" {
    const raw = packetType0(shader_constant_fetch_00_0, 6, false).?;
    const header = decodeHeader(raw);
    try std.testing.expectEqual(PacketType.type0, header.kind);
    try std.testing.expectEqual(@as(u16, shader_constant_fetch_00_0), header.register_index);
    try std.testing.expectEqual(@as(u16, 6), header.count);
    try std.testing.expect(!header.one_register);
    try std.testing.expectEqual(@as(u32, 7), header.totalDwords());
}

// A filler dword has no count field. Reporting one would make a padded ring
// look like a packet stream to any reader that did not switch on the type.
test "a type-2 filler occupies exactly one dword and claims no payload" {
    const header = decodeHeader(packetType2());
    try std.testing.expectEqual(PacketType.type2, header.kind);
    try std.testing.expectEqual(@as(u16, 0), header.count);
    try std.testing.expectEqual(@as(u32, 1), header.totalDwords());
}

test "an encoded swap sequence decodes back to the description it was given" {
    var buffer: [swap_reservation_dwords]u32 = undefined;
    var fetch = FetchConstant{};
    fetch.setBaseAddress(0x1F00_0000);
    fetch.setSize2d(1280, 720);

    const written = encodeSwapSequence(&buffer, fetch, .{
        .frontbuffer_physical_address = 0x1F00_0000,
        .width = 1280,
        .height = 720,
    }, swap_reservation_dwords).?;
    try std.testing.expectEqual(swap_reservation_dwords, written);

    const decoded = decodeSwapSequence(buffer[0..written]).?;
    try std.testing.expectEqual(@as(u32, 0x1F00_0000), decoded.frontbuffer_physical_address);
    try std.testing.expectEqual(@as(u32, 1280), decoded.width);
    try std.testing.expectEqual(@as(u32, 720), decoded.height);
}

// The reservation is the title's, and the dwords past the packet are whatever
// was there before. Leaving them would hand the command processor stale
// commands at exactly the moment the harness claimed to be helping.
test "the reservation past the swap packet is filled with no-ops" {
    var buffer = [_]u32{0xDEAD_BEEF} ** swap_reservation_dwords;
    const written = encodeSwapSequence(&buffer, .{}, .{
        .frontbuffer_physical_address = 0x1000_0000,
        .width = 640,
        .height = 480,
    }, swap_reservation_dwords).?;
    var index: usize = 12;
    while (index < written) : (index += 1) {
        try std.testing.expectEqual(PacketType.type2, decodeHeader(buffer[index]).kind);
    }
}

test "a buffer too small for the sequence is refused rather than truncated" {
    var buffer: [8]u32 = undefined;
    try std.testing.expect(encodeSwapSequence(&buffer, .{}, .{
        .frontbuffer_physical_address = 1,
        .width = 64,
        .height = 64,
    }, swap_reservation_dwords) == null);
}

test "a swap without its signature is not a swap" {
    var buffer: [16]u32 = undefined;
    const written = encodeSwapSequence(&buffer, .{}, .{
        .frontbuffer_physical_address = 0x2000,
        .width = 640,
        .height = 480,
    }, 16).?;
    _ = written;
    buffer[8] = 0x4E4F5045;
    try std.testing.expect(decodeSwapSequence(&buffer) == null);
}

test "a fetch constant stores a page-aligned base and a size biased by one" {
    var fetch = FetchConstant{};
    fetch.setBaseAddress(0x1F23_4000);
    try std.testing.expectEqual(@as(u32, 0x1F23_4000), fetch.baseAddress());

    fetch.setSize2d(1280, 720);
    const size = fetch.size2d();
    try std.testing.expectEqual(@as(u32, 1280), size.width);
    try std.testing.expectEqual(@as(u32, 720), size.height);
    // Stored one less, which is the encoding a reader will undo.
    try std.testing.expectEqual(@as(u32, 1279), fetch.dwords[2] & 0x1FFF);

    // Setting the size must not disturb the base, and vice versa.
    fetch.setBaseAddress(0x1F23_4000);
    try std.testing.expectEqual(@as(u32, 1280), fetch.size2d().width);
}

// Both of these live where a reader would not expect, and reading the base out
// of dword 0 produces a plausible page-aligned address assembled from clamp
// modes and sign bits — which names real memory holding something else.
test "the base address is in the second dword and the tiled flag in the first" {
    var fetch = FetchConstant{};
    fetch.setBaseAddress(0x1FC0_0000);
    try std.testing.expectEqual(@as(u32, 0), fetch.dwords[0]);
    try std.testing.expectEqual(@as(u32, 0x1FC0_0000), fetch.dwords[1]);

    fetch.setTiled(true);
    try std.testing.expect(fetch.tiled());
    try std.testing.expectEqual(@as(u32, 0x8000_0000), fetch.dwords[0]);
    // The tiled flag must not have moved the address.
    try std.testing.expectEqual(@as(u32, 0x1FC0_0000), fetch.baseAddress());

    fetch.setTiled(false);
    try std.testing.expect(!fetch.tiled());
    try std.testing.expectEqual(@as(u32, 0x1FC0_0000), fetch.baseAddress());
}

// Format, endianness and base share dword 1, so each setter has to mask.
test "format and endianness coexist with the base address in one dword" {
    var fetch = FetchConstant{};
    fetch.setBaseAddress(0x1FC0_0000);
    fetch.setFormat(6);
    fetch.setEndianness(2);

    try std.testing.expectEqual(@as(u32, 0x1FC0_0000), fetch.baseAddress());
    try std.testing.expectEqual(@as(u6, 6), fetch.format());
    try std.testing.expectEqual(@as(u2, 2), fetch.endianness());

    // Rewriting the base leaves the other two alone.
    fetch.setBaseAddress(0x1F80_0000);
    try std.testing.expectEqual(@as(u6, 6), fetch.format());
    try std.testing.expectEqual(@as(u2, 2), fetch.endianness());
}

test "a pitch is reported in texels rather than in its stored 32-texel units" {
    var fetch = FetchConstant{};
    fetch.dwords[0] = 40 << 22;
    try std.testing.expectEqual(@as(u32, 1280), fetch.pitchTexels());
    fetch.dwords[0] = 0;
    try std.testing.expectEqual(@as(u32, 0), fetch.pitchTexels());
}

test "an implausible extent is refused before the command processor asserts on it" {
    try std.testing.expect(!(SwapDescription{ .frontbuffer_physical_address = 0, .width = 640, .height = 480 }).plausible());
    try std.testing.expect(!(SwapDescription{ .frontbuffer_physical_address = 0x1000, .width = 0, .height = 480 }).plausible());
    try std.testing.expect(!(SwapDescription{ .frontbuffer_physical_address = 0x1000, .width = 8192, .height = 480 }).plausible());
    try std.testing.expect((SwapDescription{ .frontbuffer_physical_address = 0x1000, .width = 1280, .height = 720 }).plausible());
}

test "a draw is found among other packets and its absence is not a parse failure" {
    var stream: [8]u32 = undefined;
    stream[0] = packetType3(.invalidate_state, 1, false).?;
    stream[1] = 0;
    stream[2] = packetType2();
    stream[3] = packetType3(.draw_indx_2, 2, false).?;
    stream[4] = 0;
    stream[5] = 0;
    stream[6] = packetType2();
    stream[7] = packetType2();
    try std.testing.expect(containsDraw(&stream));

    stream[3] = packetType3(.set_constant, 2, false).?;
    try std.testing.expect(!containsDraw(&stream));
}

// A malformed count would otherwise walk the reader off the end of the span
// and reinterpret unrelated memory as packets.
test "a packet claiming more dwords than the span holds stops the walk" {
    var stream: [4]u32 = undefined;
    stream[0] = packetType3(.set_constant, 0x100, false).?;
    stream[1] = 0;
    stream[2] = 0;
    stream[3] = 0;
    try std.testing.expect(decodeSwapSequence(&stream) == null);
    try std.testing.expect(!containsDraw(&stream));
}

test "every named opcode has a label and draws are separated from state" {
    try std.testing.expect(Type3Opcode.draw_indx.isDraw());
    try std.testing.expect(Type3Opcode.draw_indx_2.isDraw());
    try std.testing.expect(!Type3Opcode.xe_swap.isDraw());
    try std.testing.expect(!Type3Opcode.set_constant.isDraw());
    try std.testing.expectEqualStrings("XE_SWAP", Type3Opcode.xe_swap.label());
    try std.testing.expectEqualStrings("unnamed", (@as(Type3Opcode, @enumFromInt(0x7F))).label());
}

// The signature is four ASCII bytes read as one big-endian dword. Writing it
// with the bytes the other way round produces a packet the command processor
// asserts on, and an assert inside the emulator is far harder to attribute
// than a wrong constant here.
test "the swap signature is the fourcc the command processor asserts on" {
    try std.testing.expectEqual(@as(u32, 0x53574150), swap_signature);
    const bytes: [4]u8 = @bitCast(std.mem.nativeToBig(u32, swap_signature));
    try std.testing.expectEqualStrings("SWAP", &bytes);
}
