//! What the host can actually sample, and what the emulator settled for.
//!
//! Rosette owns a real `VkInstance` and a real `VkPhysicalDevice`, so it can
//! answer "can this host sample `A2B10G10R10_SNORM_PACK32`" authoritatively
//! instead of inferring it from the emulator's log line. That matters here
//! because the two questions the emulator's message runs together have
//! different answers:
//!
//!   * the preferred format is genuinely absent — Metal has no signed
//!     2_10_10_10, and that is a host fact Rosette confirms rather than
//!     disputes;
//!   * a *correct* substitution is present — `R16G16B16A16_SNORM` holds every
//!     value a 10-bit signed component can encode — and the emulator is not
//!     using it.
//!
//! What the emulator does instead is set the signed format's host format and
//! its load shader to the unsigned pair, which converts nothing. Every negative
//! component becomes a large positive one. The contract calls that a
//! reinterpretation and refuses it; this ledger records that it happened and
//! names the format that should have been used.

const std = @import("std");
const contract = @import("xenia_texture_format_contract");
const abi = @import("vulkan/abi.zig");

pub const TextureFormat = contract.TextureFormat;
pub const Signedness = contract.Signedness;
pub const LoaderMode = contract.LoaderMode;
pub const Fidelity = contract.Fidelity;
pub const Outcome = contract.Outcome;
pub const Plan = contract.Plan;
pub const format_count = contract.format_count;
pub const schema_version = contract.schema_version;

/// Every host format either ladder can name, so one query pass covers them all.
pub const probed_formats = [_]u32{
    contract.vk_format_a2b10g10r10_unorm_pack32,
    contract.vk_format_a2b10g10r10_snorm_pack32,
    contract.vk_format_r16g16b16a16_unorm,
    contract.vk_format_r16g16b16a16_snorm,
    contract.vk_format_r16g16b16a16_sfloat,
};

/// The support answer for one host format, and where it came from.
pub const Support = struct {
    format: u32 = 0,
    /// True when the driver reports the format sampleable with optimal tiling.
    sampled: bool = false,
    /// True once a driver was actually asked. Without it a `false` above is
    /// "nobody looked", which is a different fact and must not read as absence.
    probed: bool = false,
    /// `optimalTilingFeatures`. The field that decides textures and render
    /// targets, and the only one this ledger used to keep.
    features: u32 = 0,
    linear_features: u32 = 0,
    /// `bufferFeatures`. Retained because a format can be unusable as an image
    /// and native as a vertex attribute, and on this host exactly one format
    /// is: `A2B10G10R10_SNORM_PACK32` reports 0/0/VERTEX_BUFFER. Recording
    /// only the tiling half made the ledger say that format was absent, which
    /// is the difference between reinterpreting a signed vertex stream through
    /// an unsigned format and using the one the host already has.
    buffer_features: u32 = 0,

    /// Whether this format may be a vertex attribute.
    pub fn vertexBuffer(self: Support) bool {
        return self.probed and
            self.buffer_features & abi.FORMAT_FEATURE_VERTEX_BUFFER_BIT != 0;
    }

    /// Whether this format may be a colour attachment with optimal tiling.
    pub fn colorAttachment(self: Support) bool {
        return self.probed and
            self.features & abi.FORMAT_FEATURE_COLOR_ATTACHMENT_BIT != 0;
    }

    /// Why the format is not usable for the job that wanted it, stated as the
    /// driver's own answer rather than as an absence.
    ///
    /// A fallback that only says "substituted" leaves a reader unable to tell
    /// a hardware limit from a probe that never ran or a capability the run
    /// declined to ask for. Those need different work, and only the first is
    /// genuinely closed.
    pub fn unavailability(self: Support) []const u8 {
        if (!self.probed) return "no driver was asked; this is a gap in Rosette's probe, not a statement about the host";
        if (self.features == 0 and self.linear_features == 0 and self.buffer_features == 0) {
            return "the driver reports no feature at all for this format, in any tiling and for any buffer use. That is a hardware limit and no Rosette work reclaims it";
        }
        if (self.features == 0 and self.linear_features == 0) {
            return "the driver reports no image feature in either tiling and does report buffer features. The format exists on this host and cannot be an image, so a texture or render-target use must substitute while a vertex use must not";
        }
        if (!self.sampled) return "the format has image features but is not sampleable with optimal tiling";
        return "usable";
    }

    /// What this host will actually accept the format for, in a few words.
    /// A single `sampled=NO` reads as "absent" and, for a format that is
    /// image-incapable and vertex-capable, that is false.
    pub fn usage(self: Support) []const u8 {
        if (!self.probed) return "unprobed";
        const image = self.features != 0 or self.linear_features != 0;
        if (image and self.vertexBuffer()) return "image+vertex";
        if (image) return "image-only";
        if (self.vertexBuffer()) return "vertex-only";
        if (self.buffer_features != 0) return "buffer-only";
        return "unsupported";
    }
};

pub const Record = struct {
    plan: Plan = .{},
    /// The host format the emulator was observed to settle on, when it said so.
    /// Zero while it has not.
    emulator_chose: u32 = 0,
    /// The loader operation paired with the emulator's host-format choice.
    /// `unknown` is retained when the emulator did not publish a provenance
    /// marker; a substituted format with that state is not admitted as clean.
    emulator_loader: LoaderMode = .unknown,
    emulator_loader_verified: bool = false,
    emulator_reinterpreting: bool = false,
    observations: u64 = 0,
    first_step: u64 = 0,
};

pub const Summary = struct {
    probed: usize = 0,
    preferred: usize = 0,
    substituted: usize = 0,
    refused: usize = 0,
    /// Guest formats whose host/loader pairing violates the contract, either
    /// by reinterpreting the bits or by leaving a required conversion
    /// unverified.
    reinterpreted: usize = 0,
    /// Substitutions Rosette can supply that the emulator is not taking.
    available_but_unused: usize = 0,

    pub fn clean(self: Summary) bool {
        return self.reinterpreted == 0 and self.refused == 0;
    }

    pub fn verdict(self: Summary) []const u8 {
        if (self.probed == 0)
            return "no physical device has been asked yet; nothing here is a statement about the host";
        if (self.reinterpreted != 0)
            return "the emulator is serving a signed guest format through a host/loader pairing that Rosette cannot prove preserves signed values. An unsigned reinterpretation changes every negative component into a large positive one: the texture is not degraded, it is a different image; an unverified conversion is not admitted through the strict window";
        if (self.refused != 0)
            return "a guest format has no acceptable host format on this device; refusing it is correct, and the substitution ladder below says what was looked for";
        if (self.substituted != 0)
            return "every guest format has a host format that preserves its values, some by substitution; each substituted format needs its explicit conversion loader rather than a reinterpreting one";
        return "every guest format is served by the host format it maps to directly";
    }
};

pub const Ledger = struct {
    support: [probed_formats.len]Support = blk: {
        var initial: [probed_formats.len]Support = undefined;
        for (probed_formats, 0..) |format, index| initial[index] = .{ .format = format };
        break :blk initial;
    },
    /// One record per (format, signedness) pair.
    records: [format_count][2]Record = [_][2]Record{[_]Record{.{}} ** 2} ** format_count,
    probes: u64 = 0,
    resolved: bool = false,

    pub fn record(self: *const Ledger, format: TextureFormat, signedness: Signedness) Record {
        return self.records[@intFromEnum(format)][@intFromEnum(signedness)];
    }

    pub fn supportFor(self: *const Ledger, format: u32) Support {
        for (self.support) |entry| {
            if (entry.format == format) return entry;
        }
        return .{ .format = format };
    }

    /// Record one driver answer. `features` is `optimalTilingFeatures`.
    ///
    /// The image half only. Callers that have the whole `VkFormatProperties`
    /// should use `noteSupportProperties`: a format this one records as
    /// unsupported may still be a native vertex format.
    pub fn noteSupport(self: *Ledger, format: u32, features: u32) void {
        self.noteSupportProperties(format, 0, features, 0);
    }

    /// Record every field the driver reported for one format.
    pub fn noteSupportProperties(
        self: *Ledger,
        format: u32,
        linear: u32,
        optimal: u32,
        buffer: u32,
    ) void {
        for (&self.support) |*entry| {
            if (entry.format != format) continue;
            entry.probed = true;
            entry.features = optimal;
            entry.linear_features = linear;
            entry.buffer_features = buffer;
            entry.sampled = optimal & abi.FORMAT_FEATURE_SAMPLED_IMAGE_BIT != 0;
            self.probes +|= 1;
            return;
        }
    }

    /// Whether this host will accept `format` as a vertex attribute.
    pub fn vertexBufferCapable(self: *const Ledger, format: u32) bool {
        return self.supportFor(format).vertexBuffer();
    }

    fn sampleable(self: *const Ledger, format: u32) bool {
        const entry = self.supportFor(format);
        return entry.probed and entry.sampled;
    }

    /// Resolve every guest format against what the driver reported.
    ///
    /// Only meaningful once something has been probed: before that, every
    /// format reads unsupported and the ladder would refuse everything, which
    /// is an observation about the observer.
    pub fn resolveAll(self: *Ledger, step: u64) Summary {
        var summary = Summary{};
        for (self.support) |entry| {
            if (entry.probed) summary.probed += 1;
        }
        if (summary.probed == 0) return summary;
        self.resolved = true;

        var format_index: u8 = 0;
        while (format_index < format_count) : (format_index += 1) {
            const format: TextureFormat = @enumFromInt(format_index);
            for ([_]Signedness{ .unsigned, .signed }) |signedness| {
                const entry = &self.records[format_index][@intFromEnum(signedness)];
                entry.plan = contract.resolve(format, signedness, self, Ledger.sampleable);
                entry.observations +|= 1;
                if (entry.first_step == 0) entry.first_step = @max(step, 1);
                switch (entry.plan.outcome) {
                    .preferred => summary.preferred += 1,
                    .substituted => summary.substituted += 1,
                    .refused => summary.refused += 1,
                }
                if (entry.emulator_reinterpreting) {
                    summary.reinterpreted += 1;
                    // Rosette found a usable substitution the emulator is not
                    // taking. That is the actionable half of the finding.
                    if (entry.plan.outcome == .substituted) summary.available_but_unused += 1;
                }
            }
        }
        return summary;
    }

    /// State the host format the emulator settled on for a guest format.
    pub fn noteEmulatorChoice(
        self: *Ledger,
        format: TextureFormat,
        signedness: Signedness,
        chosen: u32,
        step: u64,
    ) void {
        self.noteEmulatorChoiceWithLoader(format, signedness, chosen, .unknown, step);
    }

    /// Record the emulator's host-format choice together with the loader
    /// provenance it published. A later, more complete breadcrumb may supply
    /// the loader marker after an earlier generic fallback line; verified
    /// evidence therefore replaces unknown evidence, but never the reverse.
    pub fn noteEmulatorChoiceWithLoader(
        self: *Ledger,
        format: TextureFormat,
        signedness: Signedness,
        chosen: u32,
        loader: LoaderMode,
        step: u64,
    ) void {
        const entry = &self.records[@intFromEnum(format)][@intFromEnum(signedness)];
        entry.emulator_chose = chosen;
        if (loader != .unknown or !entry.emulator_loader_verified) {
            entry.emulator_loader = loader;
            entry.emulator_loader_verified = loader.verified();
        }
        entry.emulator_reinterpreting =
            contract.isReinterpretation(format, signedness, chosen) or
            !contract.loaderAccepts(
                format,
                signedness,
                chosen,
                entry.emulator_loader,
            );
        if (entry.first_step == 0) entry.first_step = @max(step, 1);
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = 0x7EE7_5F0A_1234_ABCD;
        for (self.support) |entry| {
            hash = mix(hash, entry.format);
            hash = mix(hash, @intFromBool(entry.probed));
            hash = mix(hash, @intFromBool(entry.sampled));
        }
        for (self.records) |row| {
            for (row) |entry| {
                hash = mix(hash, entry.plan.host_format);
                hash = mix(hash, @intFromEnum(entry.plan.outcome));
                hash = mix(hash, entry.emulator_chose);
                hash = mix(hash, @intFromEnum(entry.emulator_loader));
                hash = mix(hash, @intFromBool(entry.emulator_loader_verified));
                hash = mix(hash, @intFromBool(entry.emulator_reinterpreting));
            }
        }
        return hash;
    }
};

fn mix(hash: u64, value: u64) u64 {
    var next = hash ^ (value +% 0x9E37_79B9_7F4A_7C15 +% (hash << 6) +% (hash >> 2));
    next ^= next >> 33;
    next = next *% 0xFF51_AFD7_ED55_8CCD;
    next ^= next >> 29;
    return next;
}

// ---------------------------------------------------------------------------

const sampled_bit: u32 = abi.FORMAT_FEATURE_SAMPLED_IMAGE_BIT;

/// What MoltenVK reports on Apple silicon: no signed 2_10_10_10, the rest
/// present.
fn probeAppleSilicon(ledger: *Ledger) void {
    for (probed_formats) |format| {
        const features: u32 = if (format == contract.vk_format_a2b10g10r10_snorm_pack32) 0 else sampled_bit;
        ledger.noteSupport(format, features);
    }
}

test "an unprobed ledger says nothing about the host" {
    var ledger = Ledger{};
    const summary = ledger.resolveAll(0);
    try std.testing.expectEqual(@as(usize, 0), summary.probed);
    try std.testing.expect(summary.clean());
    try std.testing.expect(!ledger.resolved);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "no physical device has been asked") != null);
}

test "an unprobed format is not the same as an absent one" {
    var ledger = Ledger{};
    const entry = ledger.supportFor(contract.vk_format_a2b10g10r10_snorm_pack32);
    try std.testing.expect(!entry.probed);
    try std.testing.expect(!entry.sampled);
    // Probing it and getting nothing back is the absence.
    ledger.noteSupport(contract.vk_format_a2b10g10r10_snorm_pack32, 0);
    const probed = ledger.supportFor(contract.vk_format_a2b10g10r10_snorm_pack32);
    try std.testing.expect(probed.probed);
    try std.testing.expect(!probed.sampled);
}

// The 2026-09-03 audit. The ledger kept only `optimalTilingFeatures`, so the
// report read `host-format 65 sampled=NO features=0x00000000` and a reader
// concluded the host could not do format 65 at all. The driver actually
// reports 0x0/0x0/0x40 for it: unusable as an image, and a native vertex
// attribute. Those are different answers and only one of them was printed.
test "a format can be image-incapable and still a native vertex format" {
    var ledger = Ledger{};
    // What this host really reports for A2B10G10R10_SNORM_PACK32.
    ledger.noteSupportProperties(
        contract.vk_format_a2b10g10r10_snorm_pack32,
        0,
        0,
        abi.FORMAT_FEATURE_VERTEX_BUFFER_BIT,
    );
    const signed_pack = ledger.supportFor(contract.vk_format_a2b10g10r10_snorm_pack32);
    try std.testing.expect(signed_pack.probed);
    // Still not sampleable, so the texture ladder must keep substituting.
    try std.testing.expect(!signed_pack.sampled);
    try std.testing.expect(!signed_pack.colorAttachment());
    // But the vertex path needs no substitution at all.
    try std.testing.expect(signed_pack.vertexBuffer());
    try std.testing.expect(ledger.vertexBufferCapable(contract.vk_format_a2b10g10r10_snorm_pack32));
    try std.testing.expectEqualStrings("vertex-only", signed_pack.usage());

    // And the fully-capable twin says so differently.
    ledger.noteSupportProperties(
        contract.vk_format_r16g16b16a16_snorm,
        0x8000d403,
        0x8000dd83,
        0x80000058,
    );
    const widened = ledger.supportFor(contract.vk_format_r16g16b16a16_snorm);
    try std.testing.expect(widened.sampled);
    try std.testing.expect(widened.colorAttachment());
    try std.testing.expect(widened.vertexBuffer());
    try std.testing.expectEqualStrings("image+vertex", widened.usage());

    // A format nobody asked about is unprobed, never "unsupported".
    try std.testing.expectEqualStrings(
        "unprobed",
        ledger.supportFor(contract.vk_format_r16g16b16a16_sfloat).usage(),
    );
}

// The image half alone is still the right question for a texture, and the
// old entry point has to keep answering exactly as it did.
test "the image-only probe still records what it always did" {
    var ledger = Ledger{};
    ledger.noteSupport(contract.vk_format_r16g16b16a16_snorm, 0x8000dd83);
    const entry = ledger.supportFor(contract.vk_format_r16g16b16a16_snorm);
    try std.testing.expect(entry.sampled);
    try std.testing.expect(entry.colorAttachment());
    // It never claimed to know about buffers, and must not pretend to.
    try std.testing.expect(!entry.vertexBuffer());
    try std.testing.expectEqualStrings("image-only", entry.usage());
}

test "Apple silicon substitutes the signed 2_10_10_10 paths losslessly" {
    var ledger = Ledger{};
    probeAppleSilicon(&ledger);
    const summary = ledger.resolveAll(1000);
    try std.testing.expectEqual(probed_formats.len, summary.probed);
    try std.testing.expectEqual(@as(usize, 0), summary.refused);
    // The two signed 2_10_10_10 paths are substituted; everything else is
    // served by its preferred format.
    try std.testing.expectEqual(@as(usize, 2), summary.substituted);
    for ([_]TextureFormat{ .k_2_10_10_10, .k_2_10_10_10_as_16_16_16_16 }) |format| {
        const entry = ledger.record(format, .signed);
        try std.testing.expectEqual(Outcome.substituted, entry.plan.outcome);
        try std.testing.expectEqual(contract.vk_format_r16g16b16a16_snorm, entry.plan.host_format);
        try std.testing.expectEqual(Fidelity.lossless_widening, entry.plan.fidelity);
        try std.testing.expect(entry.plan.requiresLoaderChange());
    }
    try std.testing.expect(summary.clean());
}

// The finding: Rosette confirms the preferred format is absent, finds a
// substitution that preserves the values, and records that the emulator took
// neither.
test "the emulator's reinterpreting fallback is detected alongside the fix" {
    var ledger = Ledger{};
    probeAppleSilicon(&ledger);
    ledger.noteEmulatorChoice(
        .k_2_10_10_10,
        .signed,
        contract.vk_format_a2b10g10r10_unorm_pack32,
        4200,
    );
    ledger.noteEmulatorChoice(
        .k_2_10_10_10_as_16_16_16_16,
        .signed,
        contract.vk_format_a2b10g10r10_unorm_pack32,
        4200,
    );
    const summary = ledger.resolveAll(4200);
    try std.testing.expect(!summary.clean());
    try std.testing.expectEqual(@as(usize, 2), summary.reinterpreted);
    // Both have a usable substitution Rosette can name.
    try std.testing.expectEqual(@as(usize, 2), summary.available_but_unused);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "different image") != null);
    const entry = ledger.record(.k_2_10_10_10, .signed);
    try std.testing.expect(entry.emulator_reinterpreting);
    try std.testing.expectEqual(contract.vk_format_r16g16b16a16_snorm, entry.plan.host_format);
}

test "an emulator choice that matches the substitution is not a finding" {
    var ledger = Ledger{};
    probeAppleSilicon(&ledger);
    ledger.noteEmulatorChoiceWithLoader(
        .k_2_10_10_10,
        .signed,
        contract.vk_format_r16g16b16a16_snorm,
        .signed_widening,
        10,
    );
    const summary = ledger.resolveAll(10);
    try std.testing.expectEqual(@as(usize, 0), summary.reinterpreted);
    try std.testing.expect(summary.clean());
}

test "a substituted format without loader provenance remains a strict violation" {
    var ledger = Ledger{};
    probeAppleSilicon(&ledger);
    ledger.noteEmulatorChoice(
        .k_2_10_10_10,
        .signed,
        contract.vk_format_r16g16b16a16_snorm,
        10,
    );
    const summary = ledger.resolveAll(10);
    try std.testing.expectEqual(@as(usize, 1), summary.reinterpreted);
    const entry = ledger.record(.k_2_10_10_10, .signed);
    try std.testing.expectEqual(LoaderMode.unknown, entry.emulator_loader);
    try std.testing.expect(!entry.emulator_loader_verified);
    try std.testing.expect(entry.emulator_reinterpreting);
}

test "the signed widening and float loader contracts are distinct" {
    try std.testing.expect(contract.loaderAccepts(
        .k_2_10_10_10,
        .signed,
        contract.vk_format_r16g16b16a16_snorm,
        .signed_widening,
    ));
    try std.testing.expect(contract.loaderAccepts(
        .k_2_10_10_10,
        .signed,
        contract.vk_format_r16g16b16a16_sfloat,
        .signed_float,
    ));
    try std.testing.expect(!contract.loaderAccepts(
        .k_2_10_10_10,
        .signed,
        contract.vk_format_r16g16b16a16_snorm,
        .signed_float,
    ));
    try std.testing.expect(!contract.loaderAccepts(
        .k_2_10_10_10,
        .signed,
        contract.vk_format_r16g16b16a16_snorm,
        .native_unsigned,
    ));
}

test "a host with neither the preferred format nor a substitution refuses" {
    var ledger = Ledger{};
    for (probed_formats) |format| {
        const features: u32 = if (format == contract.vk_format_a2b10g10r10_unorm_pack32) sampled_bit else 0;
        ledger.noteSupport(format, features);
    }
    const summary = ledger.resolveAll(10);
    try std.testing.expect(summary.refused != 0);
    try std.testing.expect(!summary.clean());
    try std.testing.expectEqual(Outcome.refused, ledger.record(.k_2_10_10_10, .signed).plan.outcome);
}

test "the package's format numbers match the runtime ABI table" {
    // The contract restates these so it can compile standalone; this is the
    // standing check that the two have not drifted.
    try std.testing.expectEqual(abi.FORMAT_UNDEFINED, contract.vk_format_undefined);
    try std.testing.expectEqual(abi.FORMAT_R8G8B8A8_UNORM, contract.vk_format_r8g8b8a8_unorm);
}

test "the fingerprint moves only when support or a plan changes" {
    var ledger = Ledger{};
    probeAppleSilicon(&ledger);
    _ = ledger.resolveAll(1);
    const first = ledger.fingerprint();
    _ = ledger.resolveAll(2);
    try std.testing.expectEqual(first, ledger.fingerprint());
    ledger.noteEmulatorChoice(.k_2_10_10_10, .signed, contract.vk_format_a2b10g10r10_unorm_pack32, 3);
    try std.testing.expect(ledger.fingerprint() != first);
}

// The exact lines the emulator emitted, parsed the way the guest-log observer
// parses them. Kept here rather than in the parser so a change to the ladder
// and a change to the parsing are checked against the same strings.
test "the emulator's own breadcrumbs name the format it fell back to" {
    const lines = [_]struct { text: []const u8, format: TextureFormat }{
        .{
            .text = "VulkanTextureCache: Format k_2_10_10_10 (signed) is supported via a fallback format (using the Vulkan format 64 instead of the preferred 65)",
            .format = .k_2_10_10_10,
        },
        .{
            .text = "VulkanTextureCache: Format k_2_10_10_10_AS_16_16_16_16 (signed) is supported via a fallback format (using the Vulkan format 64 instead of the preferred 65)",
            .format = .k_2_10_10_10_as_16_16_16_16,
        },
    };
    for (lines) |line| {
        try std.testing.expect(std.mem.indexOf(u8, line.text, "(signed)") != null);
        try std.testing.expect(std.mem.indexOf(u8, line.text, line.format.label()) != null);
        // The number the parser has to pick out, and the one it must not.
        const marker = "using the Vulkan format ";
        const start = std.mem.indexOf(u8, line.text, marker).? + marker.len;
        try std.testing.expectEqualStrings("64", line.text[start .. start + 2]);
    }
    // The shorter label is a prefix of the longer one, so a parser that
    // matches shortest-first attributes both lines to the same format.
    try std.testing.expect(std.mem.startsWith(
        u8,
        TextureFormat.k_2_10_10_10_as_16_16_16_16.label(),
        TextureFormat.k_2_10_10_10.label(),
    ));
}
