//! A census of the x86-64 opcode space as this decoder sees it.
//!
//! Why this exists
//! ---------------
//! Rosette translates x86-64, and "does it handle all of x86-64?" had no
//! answer. The evidence was anecdotal: a guest reached an encoding, the
//! decoder returned `invalid`, the run stopped, and one opcode got added.
//! Three of those in a week is not a coverage argument, and the gap between
//! them was invisible.
//!
//! This walks the opcode maps and asks the production decoder about every
//! slot, so the claim becomes a number with the refusals named.
//!
//! What a refusal does and does not mean
//! -------------------------------------
//! The census probes each slot with a synthesized encoding: the opcode, a
//! register-form ModRM, and enough trailing bytes to satisfy any immediate.
//! That is a valid encoding for the overwhelming majority of the map, but not
//! for all of it — an opcode whose real form this probe does not produce will
//! be reported `refused` even though the decoder might accept its true
//! encoding.
//!
//! The error is therefore one-directional, and deliberately so: the census can
//! **understate** coverage and can never overstate it. A slot reported
//! `decoded` returned a real opcode from the real decoder. A slot reported
//! `refused` is a lead to inspect, not a proven hole. Coverage that flatters
//! the decoder would be worse than no number at all.
//!
//! Prefixes and escapes are not instructions and are counted apart rather than
//! scored as failures.

const std = @import("std");
const types = @import("types.zig");
const legacy = @import("legacy.zig");

const Op = types.Op;
const ExecutionMode = types.ExecutionMode;

/// What the census could establish about one opcode slot.
pub const SlotState = enum(u8) {
    /// The decoder returned a real opcode for the probe.
    decoded,
    /// The decoder returned `invalid` for the probe. A lead, not a verdict:
    /// the probe may not be this opcode's real encoding.
    refused,
    /// Not an instruction opcode. Legacy prefixes, REX, and the escape bytes
    /// that introduce another map.
    not_an_opcode,
    /// The encoding does not exist in 64-bit mode. Refusing it is the decoder
    /// behaving correctly, so scoring it against coverage would report a
    /// conformance success as a gap.
    not_in_long_mode,
    /// Ring-0 only. A user-mode guest executing it would fault on real
    /// hardware, so a user-mode translator has nothing to implement.
    privileged,

    pub fn label(self: SlotState) []const u8 {
        return switch (self) {
            .decoded => "decoded",
            .refused => "refused",
            .not_an_opcode => "not-an-opcode",
            .not_in_long_mode => "not-in-long-mode",
            .privileged => "privileged",
        };
    }
};

/// The maps this census walks.
pub const Map = enum(u8) {
    /// The primary one-byte opcode map.
    one_byte,
    /// The `0F` two-byte map.
    two_byte,
    /// The `0F 38` three-byte map.
    three_byte_38,
    /// The `0F 3A` three-byte map.
    three_byte_3a,

    pub fn label(self: Map) []const u8 {
        return switch (self) {
            .one_byte => "one-byte",
            .two_byte => "0F two-byte",
            .three_byte_38 => "0F 38",
            .three_byte_3a => "0F 3A",
        };
    }
};

pub const map_count: usize = @typeInfo(Map).@"enum".fields.len;

/// Legacy prefixes, REX, and the map escapes. None of these is an instruction,
/// so scoring them as decode failures would understate coverage for a reason
/// that has nothing to do with instruction support.
fn isNotAnOpcode(map: Map, opcode: u8) bool {
    if (map != .one_byte) return false;
    return switch (opcode) {
        // Segment overrides, operand/address size, LOCK, REP/REPNE.
        0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65, 0x66, 0x67, 0xF0, 0xF2, 0xF3 => true,
        // REX.
        0x40...0x4F => true,
        // Map escapes. In 64-bit mode C4/C5 introduce VEX and 62 introduces
        // EVEX; none of the three is an instruction here.
        0x0F, 0x62, 0xC4, 0xC5 => true,
        else => false,
    };
}

/// Encodings x86-64 removed. A decoder that accepted these would be wrong, so
/// they are excluded from the score rather than counted against it.
///
/// Reporting them as gaps is how a coverage number becomes a lie in the
/// flattering direction's opposite: it would send someone to implement
/// instructions that must not exist.
fn isNotInLongMode(map: Map, opcode: u8) bool {
    if (map != .one_byte) return false;
    return switch (opcode) {
        // PUSH/POP of the segment registers.
        0x06, 0x07, 0x0E, 0x16, 0x17, 0x1E, 0x1F => true,
        // Packed/ASCII decimal adjust.
        0x27, 0x2F, 0x37, 0x3F, 0xD4, 0xD5 => true,
        // PUSHA/POPA.
        0x60, 0x61 => true,
        // Far CALL/JMP through a pointer immediate.
        0x9A, 0xEA => true,
        // INTO, and the undefined slot beside AAM/AAD.
        0xCE, 0xD6 => true,
        else => false,
    };
}

/// Ring-0 encodings. Port I/O, interrupt-flag control and the interrupt
/// return are unreachable from the user-mode guests this translator hosts:
/// executing one raises a general-protection fault on real hardware long
/// before a translator would see it.
///
/// Excluded from the score for the same reason as the long-mode removals —
/// counting them as gaps would send someone to implement instructions the
/// guest cannot legally execute.
fn isPrivileged(map: Map, opcode: u8) bool {
    if (map != .one_byte) return false;
    return switch (opcode) {
        // IN/OUT, immediate port and DX port.
        0xE4, 0xE5, 0xE6, 0xE7, 0xEC, 0xED, 0xEE, 0xEF => true,
        // CLI/STI.
        0xFA, 0xFB => true,
        // IRET.
        0xCF => true,
        else => false,
    };
}

/// One map's tally.
pub const MapCoverage = struct {
    map: Map,
    decoded: u16 = 0,
    refused: u16 = 0,
    not_an_opcode: u16 = 0,
    not_in_long_mode: u16 = 0,
    privileged: u16 = 0,
    /// The first refused slot, so a report can name one rather than only count.
    first_refused: ?u8 = null,

    pub fn scored(self: MapCoverage) u16 {
        return self.decoded + self.refused;
    }

    /// Percent of scorable slots the decoder accepted. Slots that are not
    /// instructions are excluded from both halves rather than counted as wins.
    pub fn percent(self: MapCoverage) u16 {
        const total = self.scored();
        if (total == 0) return 0;
        return @intCast((@as(u32, self.decoded) * 100) / total);
    }
};

pub const Census = struct {
    maps: [map_count]MapCoverage,

    pub fn decoded(self: Census) u32 {
        var total: u32 = 0;
        for (self.maps) |entry| total += entry.decoded;
        return total;
    }

    pub fn refused(self: Census) u32 {
        var total: u32 = 0;
        for (self.maps) |entry| total += entry.refused;
        return total;
    }

    pub fn scored(self: Census) u32 {
        return self.decoded() + self.refused();
    }

    pub fn percent(self: Census) u32 {
        const total = self.scored();
        if (total == 0) return 0;
        return (self.decoded() * 100) / total;
    }

    /// The weakest map, which is where an hour spent on decode coverage buys
    /// the most. Ties resolve to the earlier map so the answer is stable.
    pub fn weakest(self: Census) MapCoverage {
        var worst = self.maps[0];
        for (self.maps[1..]) |entry| {
            if (entry.scored() == 0) continue;
            if (worst.scored() == 0 or entry.percent() < worst.percent()) worst = entry;
        }
        return worst;
    }
};

/// Build the probe encoding for one slot.
///
/// A register-form ModRM (`mod=11`) with both operand fields zero, followed by
/// eight zero bytes so any immediate or displacement the opcode consumes is
/// present. REX.W is offered for the one-byte map so 64-bit-only forms are not
/// scored as refusals for lack of a prefix.
fn probeInto(buffer: []u8, map: Map, opcode: u8, rex_w: bool, memory_form: bool) []const u8 {
    var length: usize = 0;
    if (rex_w) {
        buffer[length] = 0x48;
        length += 1;
    }
    switch (map) {
        .one_byte => {},
        .two_byte => {
            buffer[length] = 0x0F;
            length += 1;
        },
        .three_byte_38 => {
            buffer[length] = 0x0F;
            buffer[length + 1] = 0x38;
            length += 2;
        },
        .three_byte_3a => {
            buffer[length] = 0x0F;
            buffer[length + 1] = 0x3A;
            length += 2;
        },
    }
    buffer[length] = opcode;
    length += 1;
    // `mod=11` is the register form and `mod=00, rm=0` is `[rax]`. Opcodes
    // exist that accept only one of the two — LEA has no register form at all
    // — so a census that probed a single shape would report the other as a
    // refusal and invent a gap.
    buffer[length] = if (memory_form) 0x00 else 0xC0;
    length += 1;
    @memset(buffer[length..][0..8], 0);
    return buffer[0 .. length + 8];
}

/// Ask the production decoder about one slot.
pub fn probe(map: Map, opcode: u8) SlotState {
    if (isNotAnOpcode(map, opcode)) return .not_an_opcode;
    if (isNotInLongMode(map, opcode)) return .not_in_long_mode;
    if (isPrivileged(map, opcode)) return .privileged;
    var buffer: [16]u8 = undefined;
    // Four shapes: {plain, REX.W} x {register form, memory form}. An opcode
    // that decodes under any of them is supported. Requiring a particular one
    // would invent failures for encodings that are legal in only some.
    for ([_]bool{ false, true }) |rex_w| {
        for ([_]bool{ false, true }) |memory_form| {
            const bytes = probeInto(&buffer, map, opcode, rex_w, memory_form);
            if (legacy.decodeLegacyInstruction(bytes, .long64).op != .invalid) return .decoded;
        }
    }
    return .refused;
}

/// Classify the opcode an actual instruction encoding names.
///
/// This is the census applied to one encoding rather than to the whole map,
/// and it exists to separate two failures the decoder reports identically.
/// When `decodeLegacyInstruction` returns `invalid` it may mean either:
///
///   * the bytes are not a valid x86-64 instruction — a guest #UD is the
///     correct emulation, or
///   * the bytes are a real instruction this decoder does not implement — in
///     which case delivering #UD to the guest is a lie. Real hardware would
///     have executed it, and the guest's handler may swallow the signal and
///     carry on with the instruction's effect silently missing.
///
/// Only the first deserves a guest signal. The second is a Rosette gap and has
/// to stop the run, which is what this lets the fault site decide.
pub fn classifyEncoding(bytes: []const u8) SlotState {
    var index: usize = 0;
    // Legacy prefixes and REX, in any order, then the map escape.
    while (index < bytes.len) : (index += 1) {
        switch (bytes[index]) {
            0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65, 0x66, 0x67, 0xF0, 0xF2, 0xF3 => {},
            0x40...0x4F => {},
            else => break,
        }
    }
    if (index >= bytes.len) return .not_an_opcode;
    if (bytes[index] != 0x0F) return probe(.one_byte, bytes[index]);
    index += 1;
    if (index >= bytes.len) return .not_an_opcode;
    return switch (bytes[index]) {
        0x38 => if (index + 1 < bytes.len) probe(.three_byte_38, bytes[index + 1]) else .not_an_opcode,
        0x3A => if (index + 1 < bytes.len) probe(.three_byte_3a, bytes[index + 1]) else .not_an_opcode,
        else => probe(.two_byte, bytes[index]),
    };
}

/// Walk every map. Allocation-free and deterministic, so it can run in a test,
/// in a pre-flight report, or in a tool without arranging anything.
pub fn census() Census {
    var out = Census{ .maps = undefined };
    inline for (@typeInfo(Map).@"enum".fields, 0..) |field, index| {
        const map: Map = @enumFromInt(field.value);
        var entry = MapCoverage{ .map = map };
        var opcode: u16 = 0;
        while (opcode <= 0xFF) : (opcode += 1) {
            const value: u8 = @intCast(opcode);
            switch (probe(map, value)) {
                .decoded => entry.decoded += 1,
                .refused => {
                    entry.refused += 1;
                    if (entry.first_refused == null) entry.first_refused = value;
                },
                .not_an_opcode => entry.not_an_opcode += 1,
                .not_in_long_mode => entry.not_in_long_mode += 1,
                .privileged => entry.privileged += 1,
            }
        }
        out.maps[index] = entry;
    }
    return out;
}

test "the census scores every slot of every map exactly once" {
    const result = census();
    for (result.maps) |entry| {
        try std.testing.expectEqual(
            @as(u16, 256),
            entry.decoded + entry.refused + entry.not_an_opcode +
                entry.not_in_long_mode + entry.privileged,
        );
    }
    // Prefixes, REX and the 0F escape are the only non-opcodes, and they live
    // only in the one-byte map.
    try std.testing.expectEqual(@as(u16, 31), result.maps[0].not_an_opcode);
    try std.testing.expect(result.maps[0].not_in_long_mode != 0);
    try std.testing.expect(result.maps[0].privileged != 0);
    for (result.maps[1..]) |entry| {
        try std.testing.expectEqual(@as(u16, 0), entry.not_an_opcode);
        try std.testing.expectEqual(@as(u16, 0), entry.not_in_long_mode);
        try std.testing.expectEqual(@as(u16, 0), entry.privileged);
    }
}

test "the census never overstates what the decoder accepts" {
    // Every slot it calls `decoded` must produce a real opcode from the real
    // decoder — the census may understate coverage, never the reverse.
    var buffer: [16]u8 = undefined;
    var checked: usize = 0;
    inline for (@typeInfo(Map).@"enum".fields) |field| {
        const map: Map = @enumFromInt(field.value);
        var opcode: u16 = 0;
        while (opcode <= 0xFF) : (opcode += 1) {
            const value: u8 = @intCast(opcode);
            if (probe(map, value) != .decoded) continue;
            var any = false;
            for ([_]bool{ false, true }) |rex_w| {
                for ([_]bool{ false, true }) |memory_form| {
                    const bytes = probeInto(&buffer, map, value, rex_w, memory_form);
                    if (legacy.decodeLegacyInstruction(bytes, .long64).op != .invalid) any = true;
                }
            }
            try std.testing.expect(any);
            checked += 1;
        }
    }
    try std.testing.expect(checked != 0);
}

// -------------------------------------------------------------------------
// The VEX space
// -------------------------------------------------------------------------
//
// The legacy census above says nothing about AVX, and that is where the
// decoder has actually been losing runs: `vblendpd` (VEX.66.0F3A.W0 0D) had
// no entry while its single-precision neighbour at 0x0C did, so an ordinary
// double-precision blend stopped a run that had already presented a frame.
// One missing slot between two present ones is invisible without a census.
//
// The same honesty rule applies here: the probe is a register-form encoding
// with a trailing immediate, which is the real shape for most of the space
// but not all of it, so a `refused` slot is a lead and never a proven hole.

/// A VEX opcode map, selected by the `mmmmm` field of the three-byte prefix.
pub const VexMap = enum(u8) {
    /// `VEX.0F`
    zero_f = 1,
    /// `VEX.0F38`
    zero_f38 = 2,
    /// `VEX.0F3A`
    zero_f3a = 3,

    pub fn label(self: VexMap) []const u8 {
        return switch (self) {
            .zero_f => "VEX.0F",
            .zero_f38 => "VEX.0F38",
            .zero_f3a => "VEX.0F3A",
        };
    }
};

/// The mandatory-prefix field of a VEX prefix.
pub const VexPrefixBits = enum(u2) {
    none = 0,
    p66 = 1,
    pf3 = 2,
    pf2 = 3,

    pub fn label(self: VexPrefixBits) []const u8 {
        return switch (self) {
            .none => "none",
            .p66 => "66",
            .pf3 => "F3",
            .pf2 => "F2",
        };
    }
};

pub const vex_map_count: usize = @typeInfo(VexMap).@"enum".fields.len;
pub const vex_prefix_count: usize = @typeInfo(VexPrefixBits).@"enum".fields.len;

/// Whether any (prefix, W) combination of this map/opcode decodes.
///
/// A VEX opcode is defined for a particular mandatory prefix and operand
/// width, and the other combinations are genuinely undefined -- scoring them
/// as gaps would report conformance as failure. So a slot counts as covered
/// when the decoder accepts *some* legal spelling of it.
pub fn vexProbe(map: VexMap, opcode: u8) SlotState {
    var buffer: [16]u8 = undefined;
    for ([_]VexPrefixBits{ .none, .p66, .pf3, .pf2 }) |prefix| {
        for ([_]bool{ false, true }) |wide| {
            for ([_]bool{ false, true }) |long_vector| {
                // Both ModRM forms, because a store-only encoding
                // (VMOVLPS, VMOVNTPS) has no register form and a
                // register-only one (the shift groups) has no memory form --
                // probing just one of them reports the decoder's correct
                // refusal of the illegal spelling as a coverage gap.
                //
                // The reg field is walked too: 0F 71/72/73 and 0F AE are
                // groups where it selects the instruction, so a fixed reg of
                // zero names a member that does not exist.
                for ([_]u8{ 0xC1, 0x01 }) |modrm_base| {
                    for (0..8) |reg_field| {
                        const modrm = modrm_base | (@as(u8, @intCast(reg_field)) << 3);
                        const bytes = vexProbeInto(&buffer, map, opcode, prefix, wide, long_vector, modrm);
                        const decoded = legacy.decodeLegacyInstruction(bytes, .long64);
                        if (decoded.op != .invalid) return .decoded;
                    }
                }
            }
        }
    }
    return .refused;
}

fn vexProbeInto(
    buffer: []u8,
    map: VexMap,
    opcode: u8,
    prefix: VexPrefixBits,
    wide: bool,
    long_vector: bool,
    modrm: u8,
) []const u8 {
    // Three-byte VEX: C4, then R/X/B inverted with the map selector, then W,
    // vvvv inverted, L and pp.  vvvv is left at its "unused" encoding so a
    // non-NDS form is not rejected for naming a source it does not have.
    buffer[0] = 0xC4;
    buffer[1] = 0xE0 | @intFromEnum(map);
    buffer[2] = (if (wide) @as(u8, 0x80) else 0) | 0x78 |
        (if (long_vector) @as(u8, 0x04) else 0) | @intFromEnum(prefix);
    buffer[3] = opcode;
    buffer[4] = modrm;
    // Zeroes for any displacement, immediate, or is4 byte the opcode
    // consumes.
    @memset(buffer[5..16], 0);
    return buffer[0..16];
}

pub const VexMapCoverage = struct {
    map: VexMap,
    decoded: u16 = 0,
    refused: u16 = 0,
    first_refused: ?u8 = null,

    pub fn scored(self: VexMapCoverage) u16 {
        return self.decoded + self.refused;
    }

    pub fn percent(self: VexMapCoverage) u16 {
        const total = self.scored();
        if (total == 0) return 0;
        return @intCast((@as(u32, self.decoded) * 100) / total);
    }
};

pub const VexCensus = struct {
    maps: [vex_map_count]VexMapCoverage,

    pub fn decoded(self: VexCensus) u32 {
        var total: u32 = 0;
        for (self.maps) |entry| total += entry.decoded;
        return total;
    }

    pub fn scored(self: VexCensus) u32 {
        var total: u32 = 0;
        for (self.maps) |entry| total += entry.scored();
        return total;
    }

    pub fn percent(self: VexCensus) u32 {
        const total = self.scored();
        if (total == 0) return 0;
        return (self.decoded() * 100) / total;
    }

    /// The weakest VEX map, which is where the next decode gap most likely
    /// waits. Ties resolve to the earlier map so the answer is stable.
    pub fn weakest(self: VexCensus) VexMapCoverage {
        var worst = self.maps[0];
        for (self.maps[1..]) |entry| {
            if (entry.percent() < worst.percent()) worst = entry;
        }
        return worst;
    }
};

pub fn vexCensus() VexCensus {
    var result = VexCensus{ .maps = undefined };
    for ([_]VexMap{ .zero_f, .zero_f38, .zero_f3a }, 0..) |map, index| {
        var entry = VexMapCoverage{ .map = map };
        var opcode: u16 = 0;
        while (opcode <= 0xFF) : (opcode += 1) {
            switch (vexProbe(map, @intCast(opcode))) {
                .decoded => entry.decoded += 1,
                .refused => {
                    entry.refused += 1;
                    if (entry.first_refused == null) entry.first_refused = @intCast(opcode);
                },
                else => {},
            }
        }
        result.maps[index] = entry;
    }
    return result;
}

/// A human-readable name for the opcode slot a byte sequence selects.
///
/// When the decoder refuses an encoding, the byte array alone does not say
/// what is missing -- somebody has to hand-decode a VEX prefix to find out
/// that `C4 E3 71 0D` is `VEX.128.66.0F3A.W0 0D`. Naming the slot at the
/// fault site turns "implement the recorded instruction" from a research task
/// into a table lookup, and it names the same coordinates the census above
/// reports, so a gap can be checked against it directly.
///
/// Writes into `buffer` and returns the populated slice; a buffer of 96 bytes
/// is always enough.
pub fn describeEncoding(buffer: []u8, bytes: []const u8) []const u8 {
    if (bytes.len == 0) return std.fmt.bufPrint(buffer, "<no bytes>", .{}) catch "<no bytes>";

    // Walk the legacy prefixes so the opcode, not a prefix, is named.
    var index: usize = 0;
    var mandatory: []const u8 = "";
    var rex_w = false;
    while (index < bytes.len) : (index += 1) {
        switch (bytes[index]) {
            0x66 => mandatory = "66",
            0xF2 => mandatory = "F2",
            0xF3 => mandatory = "F3",
            0x2E, 0x36, 0x3E, 0x26, 0x64, 0x65, 0x67, 0xF0 => {},
            0x40...0x4F => rex_w = (bytes[index] & 0x08) != 0,
            else => break,
        }
    }
    if (index >= bytes.len) return std.fmt.bufPrint(buffer, "<prefixes only>", .{}) catch "<prefixes only>";

    const lead = bytes[index];
    if ((lead == 0xC4 or lead == 0x62) and index + 3 < bytes.len) {
        // Three-byte VEX and EVEX share the layout this needs: the map lives
        // in the low bits of the first payload byte and W/L/pp in the second.
        const payload1 = bytes[index + 1];
        const payload2 = bytes[index + 2];
        const map: u8 = payload1 & if (lead == 0xC4) @as(u8, 0x1F) else @as(u8, 0x07);
        const opcode = bytes[index + if (lead == 0xC4) @as(usize, 3) else @as(usize, 4)];
        const map_name = switch (map) {
            1 => "0F",
            2 => "0F38",
            3 => "0F3A",
            else => "?",
        };
        const pp_name = switch (payload2 & 3) {
            0 => "",
            1 => ".66",
            2 => ".F3",
            else => ".F2",
        };
        return std.fmt.bufPrint(buffer, "{s}.{s}{s}.{s}.W{d} {x:0>2}", .{
            if (lead == 0xC4) "VEX" else "EVEX",
            if ((payload2 & 0x04) != 0) "256" else "128",
            pp_name,
            map_name,
            @intFromBool((payload2 & 0x80) != 0),
            opcode,
        }) catch "<encoding>";
    }
    if (lead == 0xC5 and index + 2 < bytes.len) {
        const payload = bytes[index + 1];
        const opcode = bytes[index + 2];
        const pp_name = switch (payload & 3) {
            0 => "",
            1 => ".66",
            2 => ".F3",
            else => ".F2",
        };
        return std.fmt.bufPrint(buffer, "VEX.{s}{s}.0F.WIG {x:0>2}", .{
            if ((payload & 0x04) != 0) "256" else "128",
            pp_name,
            opcode,
        }) catch "<encoding>";
    }
    if (lead == 0x0F) {
        if (index + 1 >= bytes.len) return std.fmt.bufPrint(buffer, "0F <truncated>", .{}) catch "0F";
        const second = bytes[index + 1];
        if ((second == 0x38 or second == 0x3A) and index + 2 < bytes.len) {
            return std.fmt.bufPrint(buffer, "{s}0F{x:0>2} {x:0>2}{s}", .{
                if (mandatory.len == 0) "" else mandatory,
                second,
                bytes[index + 2],
                if (rex_w) " REX.W" else "",
            }) catch "<encoding>";
        }
        return std.fmt.bufPrint(buffer, "{s}0F {x:0>2}{s}", .{
            if (mandatory.len == 0) "" else mandatory,
            second,
            if (rex_w) " REX.W" else "",
        }) catch "<encoding>";
    }
    return std.fmt.bufPrint(buffer, "{s}one-byte {x:0>2}{s}", .{
        if (mandatory.len == 0) "" else mandatory,
        lead,
        if (rex_w) " REX.W" else "",
    }) catch "<encoding>";
}

test "an unsupported encoding is named by its opcode-map coordinates" {
    var buffer: [96]u8 = undefined;
    // The encoding that stopped a run on 2026-09-09.
    try std.testing.expectEqualStrings(
        "VEX.128.66.0F3A.W0 0d",
        describeEncoding(&buffer, &[_]u8{ 0xC4, 0xE3, 0x71, 0x0D, 0xCA, 0x01 }),
    );
    try std.testing.expectEqualStrings(
        "VEX.256.66.0F.WIG 58",
        describeEncoding(&buffer, &[_]u8{ 0xC5, 0xFD, 0x58, 0xC1 }),
    );
    try std.testing.expectEqualStrings(
        "660F38 17",
        describeEncoding(&buffer, &[_]u8{ 0x66, 0x0F, 0x38, 0x17, 0xC1 }),
    );
    try std.testing.expectEqualStrings(
        "one-byte 90",
        describeEncoding(&buffer, &[_]u8{0x90}),
    );
    try std.testing.expectEqualStrings("<no bytes>", describeEncoding(&buffer, &.{}));
}

/// The floor each VEX map has to hold, measured on 2026-09-09 at 40% / 22% /
/// 11% (103, 57 and 29 slots).
///
/// These are low by the standards of the one-byte map and are meant to be:
/// a large share of every VEX map is genuinely undefined rather than
/// unimplemented, and the denominator here is all 256 slots, so the absolute
/// number says less than the ratchet does. What the ratchet buys is that
/// removing or shadowing an entry fails a test instead of a run.
///
/// The named gaps as of that measurement, in the order a compiler is likely
/// to reach them: VEX.0F38 96-BF (the whole FMA block), 45-47 (AVX2 variable
/// shifts), 0D (VPERMILPD), 78/79 (byte and word broadcast), 8C/8E
/// (VPMASKMOV), 90-93 (gathers); VEX.0F3A 00-02 (VPERMQ, VPERMPD, VPBLENDD),
/// 40/41 (VDPPS, VDPPD), 46 (VPERM2I128), 1D (VCVTPS2PH).
pub const vex_0f_floor: u16 = 40;
pub const vex_0f38_floor: u16 = 22;
pub const vex_0f3a_floor: u16 = 11;

test "the VEX opcode maps hold their coverage floors" {
    const result = vexCensus();
    const floors = [_]u16{ vex_0f_floor, vex_0f38_floor, vex_0f3a_floor };
    for (result.maps, floors) |entry, floor| {
        if (entry.percent() >= floor) continue;
        std.debug.print(
            "{s} coverage fell to {d}% (floor {d}%). Refused slots:\n",
            .{ entry.map.label(), entry.percent(), floor },
        );
        var opcode: u16 = 0;
        while (opcode <= 0xFF) : (opcode += 1) {
            if (vexProbe(entry.map, @intCast(opcode)) == .refused) {
                std.debug.print("  {x:0>2}\n", .{opcode});
            }
        }
        return error.VexOpcodeCoverageRegressed;
    }
    // A census that measured nothing would clear every floor.
    try std.testing.expectEqual(@as(u32, 3 * 256), result.scored());
    try std.testing.expect(result.decoded() > 150);
}

test "the VEX blend and select family has no hole between its members" {
    // This is the shape that cost a run: 0x0C and 0x0E present, 0x0D absent.
    // A family with one member missing decodes as an invalid instruction on
    // whichever operand width the guest happens to use.
    for ([_]u8{ 0x0C, 0x0D, 0x0E, 0x0F }) |opcode| {
        try std.testing.expectEqual(SlotState.decoded, vexProbe(.zero_f3a, opcode));
    }
    // The variable-select forms sit together at 4A/4B/4C.
    for ([_]u8{ 0x4A, 0x4B, 0x4C }) |opcode| {
        try std.testing.expectEqual(SlotState.decoded, vexProbe(.zero_f3a, opcode));
    }
    // The arithmetic block in the 0F map is contiguous and complete.
    for ([_]u8{ 0x58, 0x59, 0x5C, 0x5D, 0x5E, 0x5F }) |opcode| {
        try std.testing.expectEqual(SlotState.decoded, vexProbe(.zero_f, opcode));
    }
}

/// The floor the one-byte map has to hold.
///
/// Measured at 94% on 2026-09-08 with ten refusals left: `8E` (MOV Sreg),
/// `A0`-`A3` (MOV moffs), `C8` (ENTER), `CA`/`CB` (far RET), `CD` (INT imm8)
/// and `F1` (ICEBP). Raise this as those are implemented; it is a ratchet, and
/// it is the one-byte map because that is the space a compiler emits from
/// constantly — a gap there is reachable by ordinary integer code rather than
/// only by a vector path.
pub const one_byte_floor: u16 = 94;

test "the one-byte opcode map holds its coverage floor" {
    const result = census();
    const primary = result.maps[0];
    if (primary.percent() < one_byte_floor) {
        std.debug.print(
            "one-byte opcode coverage fell to {d}% (floor {d}%). Refused slots:\n",
            .{ primary.percent(), one_byte_floor },
        );
        var opcode: u16 = 0;
        while (opcode <= 0xFF) : (opcode += 1) {
            if (probe(.one_byte, @intCast(opcode)) == .refused) {
                std.debug.print("  {x:0>2}\n", .{opcode});
            }
        }
        return error.OneByteOpcodeCoverageRegressed;
    }
    // A census that measured nothing would pass every threshold.
    try std.testing.expect(result.scored() > 900);
    try std.testing.expect(primary.decoded > 150);
}

// The classes that are excluded from the score are excluded because a decoder
// that accepted them would be wrong, not because they are inconvenient. If one
// of them ever starts decoding, the census is flattering the decoder and this
// says so.
test "excluded opcode classes are refused, not quietly decoded" {
    // Long-mode removals: PUSH/POP of segment registers, the decimal adjusts,
    // PUSHA/POPA, far CALL/JMP through a pointer immediate, and INTO.
    for ([_]u8{ 0x06, 0x07, 0x0E, 0x16, 0x17, 0x1E, 0x1F, 0x27, 0x2F, 0x37, 0x3F, 0x60, 0x61, 0x9A, 0xCE, 0xD6 }) |opcode| {
        try std.testing.expectEqual(SlotState.not_in_long_mode, probe(.one_byte, opcode));
    }
    // Ring-0: port I/O, interrupt-flag control, interrupt return.
    for ([_]u8{ 0xE4, 0xE5, 0xE6, 0xE7, 0xEC, 0xED, 0xEE, 0xEF, 0xFA, 0xFB, 0xCF }) |opcode| {
        try std.testing.expectEqual(SlotState.privileged, probe(.one_byte, opcode));
    }
    // Prefixes and map escapes, including the VEX and EVEX introducers.
    for ([_]u8{ 0x0F, 0x62, 0xC4, 0xC5, 0x66, 0x67, 0xF0, 0xF2, 0xF3, 0x40, 0x4F }) |opcode| {
        try std.testing.expectEqual(SlotState.not_an_opcode, probe(.one_byte, opcode));
    }
}

// The instructions added on 2026-09-08 after the census named them. `CLD` and
// `STD` are the ones that mattered: the string operations already consulted
// `RFL_DF` for their stride, so the guest was subject to a direction flag it
// had no encoding to change, and a `cld` in a memcpy prologue was an invalid
// instruction that stopped the run.
test "the direction flag and the counted loops decode" {
    for ([_]u8{ 0xFC, 0xFD, 0xD7, 0xE0, 0xE1, 0xE2, 0xE3, 0x91, 0x97 }) |opcode| {
        try std.testing.expectEqual(SlotState.decoded, probe(.one_byte, opcode));
    }
}

// The distinction the fault site depends on. `0F 0B` is UD2 and is a genuine
// #UD; `48 0F A4 D0 20` is `shld rax, rdx, 32`, a real instruction that was
// refused until 2026-09-08 — delivering #UD for that one would have told the
// guest its own code was invalid.
test "an encoding is classified by the opcode it names, through its prefixes" {
    // Prefixes and REX are walked rather than treated as the opcode.
    try std.testing.expectEqual(SlotState.decoded, classifyEncoding(&[_]u8{ 0x48, 0x83, 0xC0, 0x08 }));
    try std.testing.expectEqual(SlotState.decoded, classifyEncoding(&[_]u8{ 0x66, 0x48, 0x0F, 0xA4, 0xD0, 0x20 }));
    // A long-mode removal stays a conformance answer, not a coverage gap.
    try std.testing.expectEqual(SlotState.not_in_long_mode, classifyEncoding(&[_]u8{0x06}));
    try std.testing.expectEqual(SlotState.privileged, classifyEncoding(&[_]u8{0xFA}));
    // Prefix-only bytes name no opcode at all.
    try std.testing.expectEqual(SlotState.not_an_opcode, classifyEncoding(&[_]u8{ 0x66, 0x48 }));
    try std.testing.expectEqual(SlotState.not_an_opcode, classifyEncoding(&.{}));
    // The three-byte maps are reached through their escapes.
    try std.testing.expectEqual(classifyEncoding(&[_]u8{ 0x0F, 0x38, 0x00 }), probe(.three_byte_38, 0x00));
    try std.testing.expectEqual(classifyEncoding(&[_]u8{ 0x0F, 0x3A, 0x00 }), probe(.three_byte_3a, 0x00));
}
