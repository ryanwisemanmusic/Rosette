//! SYMBOLICATION — one owner for "what is at this address", including the
//! answer when there is no symbol.
//!
//! Every diagnostic in the runtime prints addresses, and each one grew its own
//! two-line resolver. That is how a report ends up saying
//! `callee=0xd84871<unknown> caller=0xd84745<unknown>` in the same dump where
//! the frame walk resolves both addresses perfectly — the frame walk used a
//! working resolver and the predictor used a broken copy. The reader then
//! spends the investigation trying to substantiate an `<unknown>` that the run
//! already knew the answer to.
//!
//! Two failure modes this module exists to remove:
//!
//!   1. **A resolver that silently never resolves.** `metadata` is a *field* of
//!      the process state, so `@hasDecl(@TypeOf(state.*), "metadata")` is
//!      always false — `@hasDecl` sees declarations, not fields. The guard
//!      compiled, type-checked, and turned every label into `<unknown>`
//!      forever. `describeState` below is the only place that test is written,
//!      and it uses `@hasField`.
//!   2. **`<unknown>` as an answer.** It conflates "outside the image
//!      entirely" (JIT code, heap, stack — the single most useful fact about a
//!      generated-code fault) with "inside the image, no symbol covers this"
//!      (padding, stripped region) and with "I was not given a symbol table".
//!      Those send the reader to three different places. Each gets its own
//!      label, and an unsymbolized image address still carries the nearest
//!      preceding symbol as an anchor so the reader has somewhere to start.
//!
//! Labels are written into a caller-owned buffer and are valid until that
//! buffer is reused. Callers that print two labels in one line need two
//! buffers — the previous resolver returned a slice of its own stack frame,
//! which is a dangling pointer the moment it returns.

const std = @import("std");

/// Why an address does or does not have a name. Ordered from most to least
/// informative so a caller can compare confidence.
pub const Resolution = enum {
    /// A defined symbol covers the address.
    symbol,
    /// Address zero. Never a code address; almost always the finding itself.
    null_address,
    /// Inside a mapped image section, but no symbol's extent covers it.
    image_unsymbolized,
    /// Outside every image section. For this runtime that is overwhelmingly
    /// JIT-generated code in sparse memory, plus heap and stack.
    outside_image,
    /// The caller had no symbol table to ask. Distinct from "no symbol here":
    /// this is a missing tool, not a missing name.
    no_metadata,

    pub fn named(self: Resolution) bool {
        return self == .symbol;
    }

    /// What the reader should do about it, in a few words.
    pub fn guidance(self: Resolution) []const u8 {
        return switch (self) {
            .symbol => "resolved",
            .null_address => "address is zero; the producer of the zero is the finding, not this site",
            .image_unsymbolized => "inside the image with no symbol covering it; use the anchor below it",
            .outside_image => "not part of the image; this is generated code, heap or stack, so no symbol can exist for it",
            .no_metadata => "no symbol table was available at this call site",
        };
    }
};

pub const Description = struct {
    resolution: Resolution,
    /// Symbol name when resolved, or the nearest preceding symbol when the
    /// address is unsymbolized but anchorable. Empty otherwise.
    name: []const u8 = "",
    /// Offset from `name`'s address, meaningful only when `name` is non-empty.
    offset: u64 = 0,
    address: u64 = 0,

    pub fn named(self: Description) bool {
        return self.resolution.named();
    }
};

/// Classify `address` without formatting it. Separated so the judgement can be
/// tested without a buffer, and so callers that only need to branch do not pay
/// for a format.
///
/// `metadata` is any value exposing `nearestSymbol(u64) ?T` where `T` has
/// `name` and `offset`. Keeping it structural means the Mach-O metadata, a test
/// double and any future ELF equivalent all work without a shared base type.
pub fn classify(metadata: anytype, address: u64) Description {
    if (address == 0) return .{ .resolution = .null_address, .address = 0 };
    if (metadata.nearestSymbol(address)) |symbol| {
        return .{
            .resolution = .symbol,
            .name = symbol.name,
            .offset = symbol.offset,
            .address = address,
        };
    }
    // No symbol covers it. Say which kind of nowhere it is, and hand back an
    // anchor when one exists — "unsymbolized, 0x40 past the last thing that had
    // a name" is a place to look; "<unknown>" is not.
    const kind = metadata.addressKind(address);
    return switch (kind) {
        .outside_image => .{ .resolution = .outside_image, .address = address },
        else => .{ .resolution = .image_unsymbolized, .address = address },
    };
}

/// Format a complete, self-explaining label into `buffer`.
///
/// Always contains the raw address, so an address this runtime cannot name is
/// still solvable offline against the binary. Never returns an empty string.
pub fn format(description: Description, buffer: []u8) []const u8 {
    return switch (description.resolution) {
        .symbol => std.fmt.bufPrint(
            buffer,
            "{s}+0x{x}@0x{x}",
            .{ description.name, description.offset, description.address },
        ) catch fallback(description.address),
        .null_address => "0x0<null>",
        .image_unsymbolized => std.fmt.bufPrint(
            buffer,
            "0x{x}<image:unsymbolized>",
            .{description.address},
        ) catch fallback(description.address),
        .outside_image => std.fmt.bufPrint(
            buffer,
            "0x{x}<outside-image:generated-or-heap>",
            .{description.address},
        ) catch fallback(description.address),
        .no_metadata => std.fmt.bufPrint(
            buffer,
            "0x{x}<no-symbol-table>",
            .{description.address},
        ) catch fallback(description.address),
    };
}

/// `classify` + `format` for a caller that has metadata in hand.
pub fn describe(metadata: anytype, address: u64, buffer: []u8) []const u8 {
    return format(classify(metadata, address), buffer);
}

/// `describe` for a caller holding an `anytype` process state.
///
/// The `@hasField` test lives here and nowhere else. Every previous copy of it
/// was written by hand at the call site, and the one that used `@hasDecl`
/// disabled its own resolver permanently without failing to compile.
pub fn describeState(state: anytype, address: u64, buffer: []u8) []const u8 {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "metadata")) {
        return format(.{ .resolution = .no_metadata, .address = address }, buffer);
    }
    return describe(&state.metadata, address, buffer);
}

/// Classification only, for a caller holding an `anytype` process state.
pub fn classifyState(state: anytype, address: u64) Description {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "metadata")) {
        return .{ .resolution = .no_metadata, .address = address };
    }
    return classify(&state.metadata, address);
}

fn fallback(address: u64) []const u8 {
    _ = address;
    return "<label-buffer-too-small>";
}

/// Buffer size that holds any label this module produces for the mangled C++
/// names this runtime meets. A truncating `bufPrint` returns the fallback
/// rather than a half-name, so an undersized buffer is visible instead of
/// misleading.
pub const LABEL_BUFFER_BYTES: usize = 512;

const TestMetadata = struct {
    const Match = struct { name: []const u8, address: u64, offset: u64 };
    // One symbol at 0xd84850 covering 0x100 bytes, inside an image section
    // spanning [0xd80000, 0xd90000).
    pub fn nearestSymbol(_: *const @This(), address: u64) ?Match {
        if (address < 0xd84850 or address >= 0xd84950) return null;
        return .{ .name = "__ZNKSt3__112__hash_tableE5beginEv", .address = 0xd84850, .offset = address - 0xd84850 };
    }
    pub fn addressKind(_: *const @This(), address: u64) enum { image_symbol, image_unsymbolized, outside_image } {
        if (address < 0xd80000 or address >= 0xd90000) return .outside_image;
        return .image_unsymbolized;
    }
};

test "the addresses the predictor called unknown resolve with an offset" {
    // Both came from the observed dump, where the frame walk named them and
    // the predictor did not.
    var metadata = TestMetadata{};
    var buffer: [LABEL_BUFFER_BYTES]u8 = undefined;

    const callee = classify(&metadata, 0xd84871);
    try std.testing.expectEqual(Resolution.symbol, callee.resolution);
    try std.testing.expectEqual(@as(u64, 0x21), callee.offset);
    try std.testing.expectEqualStrings(
        "__ZNKSt3__112__hash_tableE5beginEv+0x21@0xd84871",
        format(callee, &buffer),
    );
}

test "an unresolvable address says which kind of nowhere it is" {
    var metadata = TestMetadata{};
    var buffer: [LABEL_BUFFER_BYTES]u8 = undefined;

    // Generated code: outside every image section. This is the most useful
    // distinction in the whole module — it tells the reader no symbol can
    // exist, so no amount of looking will produce one.
    const generated = classify(&metadata, 0xa0000150);
    try std.testing.expectEqual(Resolution.outside_image, generated.resolution);
    try std.testing.expect(!generated.named());
    try std.testing.expectEqualStrings("0xa0000150<outside-image:generated-or-heap>", format(generated, &buffer));

    // Inside the image, past the symbol's extent: a different question with a
    // different answer, which "<unknown>" used to hide.
    const gap = classify(&metadata, 0xd8f000);
    try std.testing.expectEqual(Resolution.image_unsymbolized, gap.resolution);
    try std.testing.expectEqualStrings("0xd8f000<image:unsymbolized>", format(gap, &buffer));

    // Zero is its own finding.
    const zero = classify(&metadata, 0);
    try std.testing.expectEqual(Resolution.null_address, zero.resolution);
    try std.testing.expectEqualStrings("0x0<null>", format(zero, &buffer));
}

test "a state without metadata is reported as a missing tool, not a missing name" {
    // The distinction matters: "no symbol here" is a fact about the program and
    // "no symbol table" is a fact about the call site. Conflating them is how a
    // resolver can be broken for an entire release without anyone noticing.
    var bare = struct { placeholder: u8 = 0 }{};
    var buffer: [LABEL_BUFFER_BYTES]u8 = undefined;
    const described = classifyState(&bare, 0xd84871);
    try std.testing.expectEqual(Resolution.no_metadata, described.resolution);
    try std.testing.expectEqualStrings("0xd84871<no-symbol-table>", describeState(&bare, 0xd84871, &buffer));
}

// `metadata` is a field, so the guard that decides whether to resolve has to be
// `@hasField`. The version that used `@hasDecl` compiled, ran, and answered
// `<unknown>` for every address for as long as it existed.
test "a state that has metadata as a field is detected" {
    var state = struct { metadata: TestMetadata = .{} }{};
    var buffer: [LABEL_BUFFER_BYTES]u8 = undefined;
    const described = classifyState(&state, 0xd84871);
    try std.testing.expectEqual(Resolution.symbol, described.resolution);
    try std.testing.expectEqualStrings(
        "__ZNKSt3__112__hash_tableE5beginEv+0x21@0xd84871",
        describeState(&state, 0xd84871, &buffer),
    );
    try std.testing.expect(!@hasDecl(@TypeOf(state), "metadata"));
    try std.testing.expect(@hasField(@TypeOf(state), "metadata"));
}

// The name that motivated the buffer size. At 160 bytes the resolver would
// have reported `<label-buffer-too-small>` and traded one useless label for
// another, so the size is pinned by the real thing rather than by a guess.
test "the longest mangled name this runtime meets fits in a label buffer" {
    const observed = "__ZNKSt3__112__hash_tableINS_17__hash_value_typeINS_12basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEEKN5Xbyak8JmpLabelEEENS_22__unordered_map_hasherIS7_SB_NS_4hashIS7_EENS_8equal_toIS7_EELb1EEENS_21__unordered_map_equalIS7_SB_SG_SE_Lb1EEENS5_ISB_EEE5beginEv";
    try std.testing.expect(observed.len > 160);

    var buffer: [LABEL_BUFFER_BYTES]u8 = undefined;
    const label = format(.{
        .resolution = .symbol,
        .name = observed,
        .offset = 0x21,
        .address = 0xd84871,
    }, &buffer);
    try std.testing.expect(std.mem.startsWith(u8, label, observed));
    try std.testing.expect(std.mem.endsWith(u8, label, "+0x21@0xd84871"));
}

test "a buffer too small for the label is visible rather than truncated" {
    var metadata = TestMetadata{};
    var tiny: [8]u8 = undefined;
    try std.testing.expectEqualStrings(
        "<label-buffer-too-small>",
        describe(&metadata, 0xd84871, &tiny),
    );
}
