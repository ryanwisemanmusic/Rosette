//! What a Xenos texture format may be served by on a host that lacks it, and
//! what each substitution costs.
//!
//! The defect this was written against, from the emulator's own log:
//!
//! ```text
//! VulkanTextureCache: A2B10G10R10_SNORM not supported - falling back to
//!   unsigned format for signed 2_10_10_10 textures
//! ```
//!
//! Metal has no signed 2_10_10_10 format, so `A2B10G10R10_SNORM_PACK32` really
//! is absent and no amount of host negotiation will produce it. That part is a
//! fact. What follows it is not: the emulator sets the *signed* format's host
//! format **and its load shader** to the unsigned pair, which does not convert
//! anything. Every negative component is then read as a large positive one. The
//! texture is not degraded, it is wrong, and nothing downstream says so.
//!
//! So this contract separates two questions that the phrase "falling back" runs
//! together:
//!
//!   * is there a host format that can *hold* these values, and
//!   * does the substitution *preserve* them.
//!
//! A substitution that answers the first and fails the second is a
//! reinterpretation, and this contract refuses it. There is a correct answer
//! available here — a 10-bit signed component fits exactly in a 16-bit signed
//! one — and the emulator's own source carries a TODO saying so.

const std = @import("std");

/// Version 2 adds loader provenance to the host-format decision. A format
/// number without the operation that decoded it is no longer sufficient
/// evidence for a substituted signed texture.
pub const schema_version: u16 = 2;

/// Vulkan format numbers, restated rather than imported so the package stays
/// standalone. Checked against the runtime's own table by a test on that side.
pub const vk_format_undefined: u32 = 0;
pub const vk_format_r8g8b8a8_unorm: u32 = 37;
pub const vk_format_r8g8b8a8_snorm: u32 = 38;
pub const vk_format_a2b10g10r10_unorm_pack32: u32 = 64;
pub const vk_format_a2b10g10r10_snorm_pack32: u32 = 65;
pub const vk_format_r16g16b16a16_unorm: u32 = 91;
pub const vk_format_r16g16b16a16_snorm: u32 = 92;
pub const vk_format_r16g16b16a16_sfloat: u32 = 97;

/// The Xenos texture formats whose signed variant needs a host format the
/// emulator has been observed unable to obtain. Deliberately not the whole
/// Xenos format list: this contract is about the substitution rule, and a
/// format nobody has had to substitute has nothing to say here.
pub const TextureFormat = enum(u8) {
    k_2_10_10_10,
    k_2_10_10_10_as_16_16_16_16,
    k_16_16_16_16,

    pub fn label(self: TextureFormat) []const u8 {
        return switch (self) {
            .k_2_10_10_10 => "k_2_10_10_10",
            .k_2_10_10_10_as_16_16_16_16 => "k_2_10_10_10_AS_16_16_16_16",
            .k_16_16_16_16 => "k_16_16_16_16",
        };
    }

    /// Bits per component in the guest's own encoding. The number that decides
    /// whether a wider host format can hold every value exactly.
    pub fn componentBits(self: TextureFormat) u8 {
        return switch (self) {
            .k_2_10_10_10, .k_2_10_10_10_as_16_16_16_16 => 10,
            .k_16_16_16_16 => 16,
        };
    }
};

pub const format_count: usize = @typeInfo(TextureFormat).@"enum".fields.len;

pub const Signedness = enum(u8) {
    unsigned,
    signed,

    pub fn label(self: Signedness) []const u8 {
        return switch (self) {
            .unsigned => "unsigned",
            .signed => "signed",
        };
    }
};

/// The decoding operation paired with the host format.
///
/// A host format number is not enough evidence for a substitution. The same
/// bytes are valid input to both a signed and an unsigned Vulkan format, but
/// they represent different values. `unknown` is intentionally a real state:
/// Rosette must not infer that a loader converted the values merely because a
/// compatible host format exists.
pub const LoaderMode = enum(u8) {
    unknown,
    native_unsigned,
    native_signed,
    signed_widening,
    signed_float,

    pub fn label(self: LoaderMode) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .native_unsigned => "native-unsigned",
            .native_signed => "native-signed",
            .signed_widening => "signed-widening",
            .signed_float => "signed-float",
        };
    }

    pub fn verified(self: LoaderMode) bool {
        return self != .unknown;
    }
};

/// What a substitution does to the values.
///
/// Ordered best to worst, and the ordering is the selection rule: a resolver
/// takes the first acceptable one.
pub const Fidelity = enum(u8) {
    /// The host format the guest format maps to directly.
    exact,
    /// A wider host format of the same signedness. Every guest value has one
    /// representation, so the conversion is exact in both directions.
    lossless_widening,
    /// A host format that holds the range but not every value. Visible as
    /// banding or filtering differences, never as a sign flip.
    lossy_precision,
    /// The bits are handed to a host format that reads them as something else.
    /// This is not a substitution; it is a different image.
    reinterpretation,

    pub fn label(self: Fidelity) []const u8 {
        return switch (self) {
            .exact => "exact",
            .lossless_widening => "lossless-widening",
            .lossy_precision => "lossy-precision",
            .reinterpretation => "reinterpretation",
        };
    }

    /// Whether a substitution of this fidelity may be used.
    ///
    /// A reinterpretation never may. It is the only one that can change a value
    /// into a different value rather than into a nearby one, and it does so
    /// silently — which is what makes it worse than refusing to draw at all.
    pub fn acceptable(self: Fidelity) bool {
        return self != .reinterpretation;
    }

    /// Whether the conversion needs the loader to do work. `exact` does not;
    /// everything else does, and a substitution whose loader was not changed
    /// alongside it is a reinterpretation wearing another name.
    pub fn requiresConversion(self: Fidelity) bool {
        return self != .exact;
    }
};

pub const Candidate = struct {
    host_format: u32,
    fidelity: Fidelity,
    /// Why this one is offered, for the report line.
    note: []const u8,
};

/// The substitution ladder for one guest format and signedness, best first.
///
/// The unsigned paths are single-entry: the host formats exist everywhere and
/// there has never been anything to substitute. The signed 2_10_10_10 paths are
/// the reason this file exists.
pub fn candidates(format: TextureFormat, signedness: Signedness) []const Candidate {
    return switch (format) {
        .k_2_10_10_10, .k_2_10_10_10_as_16_16_16_16 => switch (signedness) {
            .unsigned => &.{
                .{
                    .host_format = vk_format_a2b10g10r10_unorm_pack32,
                    .fidelity = .exact,
                    .note = "the host format this guest format maps to directly",
                },
            },
            .signed => &.{
                .{
                    .host_format = vk_format_a2b10g10r10_snorm_pack32,
                    .fidelity = .exact,
                    .note = "the host format this guest format maps to directly; absent on Metal, which has no signed 2_10_10_10",
                },
                .{
                    .host_format = vk_format_r16g16b16a16_snorm,
                    .fidelity = .lossless_widening,
                    .note = "a 10-bit signed component has exactly one 16-bit signed representation, so this holds every value the guest can encode; the loader must widen rather than reinterpret",
                },
                .{
                    .host_format = vk_format_r16g16b16a16_sfloat,
                    .fidelity = .lossy_precision,
                    .note = "half float holds the full signed range with 11 bits of mantissa, so sign and magnitude survive and only the low bits move; filterable where the SNORM path is not",
                },
                .{
                    .host_format = vk_format_a2b10g10r10_unorm_pack32,
                    .fidelity = .reinterpretation,
                    .note = "REFUSED: the unsigned host format with the unsigned loader, which is what the emulator falls back to today. Every negative component is read as a large positive one",
                },
            },
        },
        .k_16_16_16_16 => switch (signedness) {
            .unsigned => &.{
                .{
                    .host_format = vk_format_r16g16b16a16_unorm,
                    .fidelity = .exact,
                    .note = "the host format this guest format maps to directly",
                },
            },
            .signed => &.{
                .{
                    .host_format = vk_format_r16g16b16a16_snorm,
                    .fidelity = .exact,
                    .note = "the host format this guest format maps to directly",
                },
                .{
                    .host_format = vk_format_r16g16b16a16_sfloat,
                    .fidelity = .lossy_precision,
                    .note = "half float holds the range; the low mantissa bits of a full 16-bit signed value do not survive",
                },
            },
        },
    };
}

pub const Outcome = enum(u8) {
    /// The preferred host format is available.
    preferred,
    /// The preferred format is absent and an acceptable substitution exists.
    substituted,
    /// Nothing acceptable is available. The correct response is to refuse the
    /// texture, not to hand the bits to a format that reads them differently.
    refused,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .preferred => "preferred",
            .substituted => "substituted",
            .refused => "refused",
        };
    }

    pub fn usable(self: Outcome) bool {
        return self != .refused;
    }
};

pub const Plan = struct {
    outcome: Outcome = .refused,
    host_format: u32 = vk_format_undefined,
    fidelity: Fidelity = .reinterpretation,
    note: []const u8 = "no host format can hold these values without changing them",
    /// The format the guest asked for, so a report can say what was given up.
    preferred_format: u32 = vk_format_undefined,

    pub fn requiresLoaderChange(self: Plan) bool {
        return self.outcome == .substituted and self.fidelity.requiresConversion();
    }
};

/// Choose the best acceptable host format, given a predicate that answers
/// whether the host can sample a given Vulkan format.
///
/// The predicate is passed in rather than queried here because this package
/// holds no state and talks to no driver: the same decision has to be
/// reproducible in a test with no Vulkan at all.
pub fn resolve(
    format: TextureFormat,
    signedness: Signedness,
    context: anytype,
    comptime supported: fn (@TypeOf(context), u32) bool,
) Plan {
    const ladder = candidates(format, signedness);
    const preferred = if (ladder.len != 0) ladder[0].host_format else vk_format_undefined;
    for (ladder, 0..) |candidate, index| {
        if (!candidate.fidelity.acceptable()) continue;
        if (!supported(context, candidate.host_format)) continue;
        return .{
            .outcome = if (index == 0) .preferred else .substituted,
            .host_format = candidate.host_format,
            .fidelity = candidate.fidelity,
            .note = candidate.note,
            .preferred_format = preferred,
        };
    }
    return .{
        .outcome = .refused,
        .host_format = vk_format_undefined,
        .fidelity = .reinterpretation,
        .note = "every acceptable host format for this guest format is absent; a reinterpreting fallback would change the values rather than approximate them",
        .preferred_format = preferred,
    };
}

/// Whether a host format the emulator actually chose is a reinterpretation of
/// this guest format.
///
/// This is the detector, not the resolver: it answers "is what the emulator
/// settled on one of the substitutions this contract refuses", which is a
/// different question from "what should it have used".
pub fn isReinterpretation(format: TextureFormat, signedness: Signedness, chosen: u32) bool {
    for (candidates(format, signedness)) |candidate| {
        if (candidate.host_format != chosen) continue;
        return !candidate.fidelity.acceptable();
    }
    return false;
}

/// Check the semantic pairing between a chosen host format and its loader.
///
/// Exact mappings may be observed without a loader marker because no
/// conversion is required. Every substituted mapping must name its conversion
/// explicitly. In particular, a signed 2_10_10_10 texture on a device without
/// signed packed-10 support is valid only when the loader widens it to signed
/// 16-bit values (or deliberately converts it to float16); selecting format 64
/// or leaving the loader unknown is never a valid signed path.
pub fn loaderAccepts(
    format: TextureFormat,
    signedness: Signedness,
    chosen: u32,
    loader: LoaderMode,
) bool {
    var selected: ?Candidate = null;
    for (candidates(format, signedness)) |candidate| {
        if (candidate.host_format == chosen) {
            selected = candidate;
            break;
        }
    }
    const candidate = selected orelse return false;
    return switch (loader) {
        // Unknown is acceptable only when the host mapping is exact, because
        // exact mappings do not need an additional decode operation.
        .unknown => candidate.fidelity == .exact,
        .native_unsigned => signedness == .unsigned and candidate.fidelity == .exact,
        .native_signed => signedness == .signed and candidate.fidelity == .exact,
        .signed_widening => signedness == .signed and candidate.fidelity == .lossless_widening,
        .signed_float => signedness == .signed and candidate.fidelity == .lossy_precision,
    };
}

/// Convert one signed normalized component from the Xenos packed encoding to
/// the signed 16-bit representation used by the widening texture loader.
///
/// The 10-bit path mirrors Xenia's shader-side `XeSNorm10To16`, including the
/// Xenos convention that the most-negative code is the same normalized value
/// as the next code up. The 2-bit alpha path follows the same convention. The
/// `comptime` width keeps this package's supported encodings explicit: adding
/// a new packed signed format must add a reviewed conversion rather than
/// silently falling through to a guessed scale.
pub fn signedNormalizedTo16(raw: u32, comptime bits: u5) i16 {
    const mask: u32 = (@as(u32, 1) << bits) - 1;
    const sign_bit: u32 = @as(u32, 1) << (bits - 1);
    var value = raw & mask;
    const negative = value & sign_bit != 0;

    // The most-negative code and -1.0 have the same normalized value. Avoid
    // overflowing the signed 16-bit representation while expanding it.
    if (value == sign_bit) value += 1;

    const magnitude = if (negative) (value ^ mask) + 1 else value;
    const scaled: u32 = switch (bits) {
        // Expand the 9-bit magnitude to the 15-bit SNORM magnitude exactly as
        // the Xenia shader does for packed 10-bit components.
        10 => (magnitude << 6) | (magnitude >> 3),
        // A 2-bit signed normalized component has a one-bit magnitude.
        2 => magnitude * 0x7FFF,
        else => @compileError("unsupported packed signed-normalized width"),
    };
    const encoded: u32 = if (negative) (scaled ^ 0xFFFF) + 1 else scaled;
    return @bitCast(@as(u16, @truncate(encoded)));
}

/// Unpack an `A2B10G10R10` Xenos word into RGBA signed 16-bit normalized
/// components. This is the host-independent semantic core shared by the
/// package contract and Rosette's runtime conversion layer.
pub fn unpackSigned2_10_10_10(word: u32) [4]i16 {
    return .{
        signedNormalizedTo16(word, 10),
        signedNormalizedTo16(word >> 10, 10),
        signedNormalizedTo16(word >> 20, 10),
        signedNormalizedTo16(word >> 30, 2),
    };
}

/// Every ladder is ordered best-first, starts with an exact entry, and never
/// offers a reinterpretation before an acceptable substitution. The ordering is
/// the selection rule, so it is checked rather than trusted.
pub fn contractIsWellFormed() bool {
    var format_index: u8 = 0;
    while (format_index < format_count) : (format_index += 1) {
        const format: TextureFormat = @enumFromInt(format_index);
        for ([_]Signedness{ .unsigned, .signed }) |signedness| {
            const ladder = candidates(format, signedness);
            if (ladder.len == 0) return false;
            if (ladder[0].fidelity != .exact) return false;
            var previous: u8 = 0;
            var seen_unacceptable = false;
            for (ladder) |candidate| {
                const rank = @intFromEnum(candidate.fidelity);
                if (rank < previous) return false;
                previous = rank;
                if (!candidate.fidelity.acceptable()) {
                    seen_unacceptable = true;
                } else if (seen_unacceptable) {
                    // An acceptable entry after a refused one would make the
                    // ladder's order stop meaning "best first".
                    return false;
                }
                if (candidate.note.len == 0) return false;
            }
        }
    }
    return true;
}

// ---------------------------------------------------------------------------

const MetalHost = struct {
    /// What MoltenVK on Apple silicon actually reports: no signed 2_10_10_10,
    /// everything else in these ladders present.
    fn supports(_: MetalHost, host_format: u32) bool {
        return host_format != vk_format_a2b10g10r10_snorm_pack32;
    }
};

const CompleteHost = struct {
    fn supports(_: CompleteHost, _: u32) bool {
        return true;
    }
};

const BareHost = struct {
    fn supports(_: BareHost, host_format: u32) bool {
        // Only the unsigned packed format, which is the shape that produced the
        // emulator's reinterpreting fallback.
        return host_format == vk_format_a2b10g10r10_unorm_pack32;
    }
};

test "the contract is well formed" {
    try std.testing.expect(contractIsWellFormed());
}

test "a host with the preferred format uses it" {
    const plan = resolve(.k_2_10_10_10, .signed, CompleteHost{}, CompleteHost.supports);
    try std.testing.expectEqual(Outcome.preferred, plan.outcome);
    try std.testing.expectEqual(vk_format_a2b10g10r10_snorm_pack32, plan.host_format);
    try std.testing.expectEqual(Fidelity.exact, plan.fidelity);
    try std.testing.expect(!plan.requiresLoaderChange());
}

// The case from the log: Metal has no signed 2_10_10_10, and there is a correct
// answer that the emulator does not take.
test "Metal substitutes losslessly rather than reinterpreting" {
    for ([_]TextureFormat{ .k_2_10_10_10, .k_2_10_10_10_as_16_16_16_16 }) |format| {
        const plan = resolve(format, .signed, MetalHost{}, MetalHost.supports);
        try std.testing.expectEqual(Outcome.substituted, plan.outcome);
        try std.testing.expectEqual(vk_format_r16g16b16a16_snorm, plan.host_format);
        try std.testing.expectEqual(Fidelity.lossless_widening, plan.fidelity);
        try std.testing.expect(plan.outcome.usable());
        // The loader has to widen. A substitution whose loader was left alone
        // is the reinterpretation this contract refuses.
        try std.testing.expect(plan.requiresLoaderChange());
        try std.testing.expectEqual(vk_format_a2b10g10r10_snorm_pack32, plan.preferred_format);
    }
}

test "a 10-bit signed component fits exactly in a 16-bit signed one" {
    // The claim the lossless_widening classification rests on, stated as
    // arithmetic rather than as prose.
    try std.testing.expect(TextureFormat.k_2_10_10_10.componentBits() < 16);
    var value: i32 = -512;
    while (value <= 511) : (value += 1) {
        const widened: i16 = @intCast(value);
        try std.testing.expectEqual(value, @as(i32, widened));
    }
}

test "a host with only the unsigned format refuses rather than reinterpreting" {
    const plan = resolve(.k_2_10_10_10, .signed, BareHost{}, BareHost.supports);
    try std.testing.expectEqual(Outcome.refused, plan.outcome);
    try std.testing.expect(!plan.outcome.usable());
    try std.testing.expectEqual(vk_format_undefined, plan.host_format);
}

test "the emulator's macOS fallback is the substitution this contract refuses" {
    // `host_format.format_signed.format = host_format.format_unsigned.format`
    // with the unsigned load shader, from vulkan_texture_cache.cc.
    try std.testing.expect(isReinterpretation(
        .k_2_10_10_10,
        .signed,
        vk_format_a2b10g10r10_unorm_pack32,
    ));
    try std.testing.expect(isReinterpretation(
        .k_2_10_10_10_as_16_16_16_16,
        .signed,
        vk_format_a2b10g10r10_unorm_pack32,
    ));
    // The correct substitution is not.
    try std.testing.expect(!isReinterpretation(
        .k_2_10_10_10,
        .signed,
        vk_format_r16g16b16a16_snorm,
    ));
    // And the unsigned path using the unsigned format is simply correct.
    try std.testing.expect(!isReinterpretation(
        .k_2_10_10_10,
        .unsigned,
        vk_format_a2b10g10r10_unorm_pack32,
    ));
}

test "a format the ladder does not mention is not called a reinterpretation" {
    // Absence of evidence: this contract only speaks for the substitutions it
    // lists, and answering for one it does not know would be a guess.
    try std.testing.expect(!isReinterpretation(.k_2_10_10_10, .signed, vk_format_r8g8b8a8_snorm));
}

test "unsigned paths never need a substitution" {
    for ([_]TextureFormat{ .k_2_10_10_10, .k_2_10_10_10_as_16_16_16_16, .k_16_16_16_16 }) |format| {
        const plan = resolve(format, .unsigned, MetalHost{}, MetalHost.supports);
        try std.testing.expectEqual(Outcome.preferred, plan.outcome);
        try std.testing.expect(!plan.requiresLoaderChange());
    }
}

test "a reinterpretation is never acceptable and every other fidelity is" {
    try std.testing.expect(!Fidelity.reinterpretation.acceptable());
    try std.testing.expect(Fidelity.exact.acceptable());
    try std.testing.expect(Fidelity.lossless_widening.acceptable());
    try std.testing.expect(Fidelity.lossy_precision.acceptable());
    try std.testing.expect(!Fidelity.exact.requiresConversion());
    try std.testing.expect(Fidelity.lossless_widening.requiresConversion());
}

test "packed signed normalized expansion matches the shader contract" {
    try std.testing.expectEqual(@as(i16, 0), signedNormalizedTo16(0, 10));
    try std.testing.expectEqual(@as(i16, 32767), signedNormalizedTo16(0x1FF, 10));
    try std.testing.expectEqual(@as(i16, -32767), signedNormalizedTo16(0x200, 10));
    try std.testing.expectEqual(@as(i16, -32767), signedNormalizedTo16(0x201, 10));
    try std.testing.expectEqual(@as(i16, -64), signedNormalizedTo16(0x3FF, 10));

    // Alpha has two bits: 0, +1, -2/-1 (both normalized to -1.0).
    try std.testing.expectEqual(@as(i16, 0), signedNormalizedTo16(0, 2));
    try std.testing.expectEqual(@as(i16, 32767), signedNormalizedTo16(1, 2));
    try std.testing.expectEqual(@as(i16, -32767), signedNormalizedTo16(2, 2));
    try std.testing.expectEqual(@as(i16, -32767), signedNormalizedTo16(3, 2));
}

test "packed A2B10G10R10 is unpacked in RGBA order" {
    const word = (@as(u32, 0x1FF) << 0) |
        (@as(u32, 0x200) << 10) |
        (@as(u32, 0x201) << 20) |
        (@as(u32, 0x3) << 30);
    const rgba = unpackSigned2_10_10_10(word);
    try std.testing.expectEqual(@as(i16, 32767), rgba[0]);
    try std.testing.expectEqual(@as(i16, -32767), rgba[1]);
    try std.testing.expectEqual(@as(i16, -32767), rgba[2]);
    try std.testing.expectEqual(@as(i16, -32767), rgba[3]);
}
