//! Frame source, custody chain, and the states a presenter has to keep apart.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run presented 43 frames and rendered none of Halo. Every
//! native call succeeded: acquire, submit, present. The presenter was correct
//! — with no guest source it drew diagnostic clears — but "43 frames
//! presented" is a sentence that survives being read out of context, and the
//! next reader concludes the pipeline works.
//!
//! So a frame carries its source class with it, from discovery to present, and
//! the presenter reports five distinct outcomes rather than one success
//! counter. `guest_frame_unchanged` and `no_guest_frame` are different facts;
//! collapsing them is how a stale image becomes a working renderer.
//!
//! The chain has no implicit substitution. Each edge names where its content
//! came from, and a diagnostic frame can keep the window alive forever without
//! ever being able to satisfy the title contract.

const std = @import("std");
const contract = @import("contract.zig");

pub const SourceClass = contract.SourceClass;
pub const Address = contract.Address;

/// The edges a frame crosses between guest memory and the screen. Each is
/// observed on its own; reaching one never implies the one before it.
pub const Edge = enum(u8) {
    /// The guest wrote into a render target.
    guest_render_target = 0,
    /// A resolve or frontbuffer write produced guest-visible bytes.
    guest_resolve_output = 1,
    /// Those bytes have a generation and a checksum.
    content_generation = 2,
    /// The emulator found and validated the source.
    emulator_discovery = 3,
    /// The content was imported or copied into a host image.
    host_image_import = 4,
    /// The presenter took custody.
    presenter_handoff = 5,
    /// The native driver acquired, submitted and presented it.
    native_present = 6,

    pub fn label(self: Edge) []const u8 {
        return switch (self) {
            .guest_render_target => "guest render target",
            .guest_resolve_output => "guest resolve/frontbuffer output",
            .content_generation => "content generation/checksum",
            .emulator_discovery => "emulator discovery and validation",
            .host_image_import => "host image import/copy",
            .presenter_handoff => "presenter handoff",
            .native_present => "native acquire/submit/present",
        };
    }

    pub fn owner(self: Edge) []const u8 {
        return switch (self) {
            .guest_render_target, .guest_resolve_output => "guest:title",
            .content_generation => "emulator:gpu",
            .emulator_discovery, .host_image_import => "xenia:vulkan",
            .presenter_handoff => "xenia:presenter",
            .native_present => "rosette:presenter",
        };
    }

    /// What a gap here means for the reader.
    pub fn gapMeans(self: Edge) []const u8 {
        return switch (self) {
            .guest_render_target => "no draw has reached a render target, so there is no image for anything downstream to carry. Every zero below this is a consequence and not an independent failure",
            .guest_resolve_output => "a render target exists and nothing has resolved it into guest-visible memory. The picture is in EDRAM or a host target and the guest cannot hand it to anyone",
            .content_generation => "resolved bytes exist and nothing has taken a generation or checksum of them. Without one, a stale buffer and a new frame are indistinguishable",
            .emulator_discovery => "the guest produced output and the emulator has not found it. This is a discovery or address-translation defect, not a title one",
            .host_image_import => "the emulator found the source and could not import or copy it. Look at format, layout, stride, memory type and queue ownership",
            .presenter_handoff => "a host image exists and the presenter never took custody of it. The frame is being produced and dropped between the two",
            .native_present => "the presenter had custody and the native driver never presented it. This is the only edge where the host sink is implicated",
        };
    }
};

pub const edge_count: usize = @typeInfo(Edge).@"enum".fields.len;

/// What the presenter did, as five different facts rather than one counter.
pub const PresentOutcome = enum(u8) {
    /// No guest source exists. The window may still be showing something and
    /// that something is the harness's.
    no_guest_frame = 0,
    /// A guest source exists and its content did not change.
    guest_frame_unchanged = 1,
    /// A guest source exists and could not be read.
    guest_frame_unreadable = 2,
    /// A guest source was read and the copy or import failed.
    guest_frame_copy_failed = 3,
    /// A guest frame reached the screen.
    guest_frame_presented = 4,

    pub fn label(self: PresentOutcome) []const u8 {
        return switch (self) {
            .no_guest_frame => "no-guest-frame",
            .guest_frame_unchanged => "guest-frame-unchanged",
            .guest_frame_unreadable => "GUEST-FRAME-UNREADABLE",
            .guest_frame_copy_failed => "GUEST-FRAME-COPY-FAILED",
            .guest_frame_presented => "guest-frame-presented",
        };
    }

    pub fn describe(self: PresentOutcome) []const u8 {
        return switch (self) {
            .no_guest_frame => "no guest source has been discovered. Whatever the window is showing is the harness's own, and it is not evidence about the title",
            .guest_frame_unchanged => "a guest source exists and its content is byte-identical to the last one presented. That is a real state — a paused title repeats frames — and it is not new output",
            .guest_frame_unreadable => "a guest source was discovered and its memory could not be read. This is an address, alias or protection defect and it is the emulator's",
            .guest_frame_copy_failed => "guest content was read and the host import failed. Format, layout, stride, memory type or queue ownership; the frame existed and did not survive the crossing",
            .guest_frame_presented => "a guest frame reached the screen",
        };
    }

    /// Whether this outcome may be counted as the title rendering.
    pub fn countsAsGuestOutput(self: PresentOutcome) bool {
        return self == .guest_frame_presented;
    }

    /// Whether this outcome is a defect someone owns, as opposed to a
    /// description of a title that has not produced anything.
    pub fn isDefect(self: PresentOutcome) bool {
        return self == .guest_frame_unreadable or self == .guest_frame_copy_failed;
    }
};

/// One frame's immutable provenance record.
pub const SourceRecord = extern struct {
    /// Monotonic per run. A frame with a generation not greater than the last
    /// presented one is a repeat, whatever its content says.
    generation: u64 = 0,
    address: Address = .{},
    width: u16 = 0,
    height: u16 = 0,
    /// Guest format code, kept raw so a reader can compare it to the register.
    format: u32 = 0,
    content_checksum: u64 = 0,
    /// `SourceClass`.
    source_class: u8 = @intFromEnum(SourceClass.unknown),
    /// Set when the producer explicitly states this frame repeats the previous
    /// one on purpose. Without it, an unchanged checksum is not new output.
    repeat_declared: u8 = 0,
    reserved: u16 = 0,
    discovered_step: u64 = 0,

    pub fn sourceOf(self: SourceRecord) SourceClass {
        return contract.decode(SourceClass, self.source_class, .unknown);
    }

    pub fn readable(self: SourceRecord) bool {
        return self.address.any() and self.width != 0 and self.height != 0;
    }
};

/// The chain, tracked edge by edge for one candidate frame.
pub const Custody = struct {
    source: SourceRecord = .{},
    reached: [edge_count]bool = [_]bool{false} ** edge_count,
    step: [edge_count]u64 = [_]u64{0} ** edge_count,

    pub fn note(self: *Custody, edge: Edge, step: u64) void {
        const index = @intFromEnum(edge);
        if (!self.reached[index]) self.step[index] = step;
        self.reached[index] = true;
    }

    pub fn has(self: Custody, edge: Edge) bool {
        return self.reached[@intFromEnum(edge)];
    }

    pub fn firstGap(self: Custody) ?Edge {
        var index: usize = 0;
        while (index < edge_count) : (index += 1) {
            if (!self.reached[index]) return @enumFromInt(index);
        }
        return null;
    }

    /// Whether the title contract may be satisfied by this frame. Every edge
    /// crossed *and* a guest-authentic source: a diagnostic frame that
    /// happened to cross every edge is still the harness's picture.
    pub fn satisfiesTitleContract(self: Custody) bool {
        return self.firstGap() == null and self.source.sourceOf().satisfiesTitleContract();
    }
};

/// Decide the presenter's outcome for one candidate.
///
/// `previous_checksum` is the last checksum actually presented, and
/// `previous_generation` the generation it carried. Both are needed: a title
/// that renders the same image twice produces an unchanged checksum with a new
/// generation, and a stale buffer produces both unchanged.
pub fn outcome(
    custody: Custody,
    previous_generation: u64,
    previous_checksum: u64,
) PresentOutcome {
    const source_class = custody.source.sourceOf();
    if (source_class != .guest_authentic and source_class != .unknown) {
        // Diagnostics and synthetic/replay surfaces are host-side candidates.
        // They have no guest address, generation or checksum by construction.
        // Judge only the host custody edges, then let Tally keep the source
        // class out of the authentic count forever.
        if (!custody.has(.emulator_discovery)) return .no_guest_frame;
        if (!custody.has(.host_image_import) or
            !custody.has(.presenter_handoff) or
            !custody.has(.native_present)) return .no_guest_frame;
        return .guest_frame_presented;
    }
    if (!custody.has(.emulator_discovery) or !custody.source.readable()) {
        // Nothing was found, or what was found has no usable geometry. The
        // difference is whether discovery ran at all.
        return if (custody.has(.emulator_discovery)) .guest_frame_unreadable else .no_guest_frame;
    }
    if (custody.source.generation <= previous_generation) return .guest_frame_unchanged;
    if (custody.source.content_checksum == previous_checksum and custody.source.repeat_declared == 0) {
        return .guest_frame_unchanged;
    }
    if (!custody.has(.host_image_import)) return .guest_frame_copy_failed;
    if (!custody.has(.presenter_handoff) or !custody.has(.native_present)) {
        return .guest_frame_copy_failed;
    }
    return .guest_frame_presented;
}

/// Counters a presenter keeps, split so a diagnostic frame can never be added
/// into a guest total by accident.
pub const Tally = struct {
    guest_presented: u64 = 0,
    guest_unchanged: u64 = 0,
    guest_unreadable: u64 = 0,
    guest_copy_failed: u64 = 0,
    no_guest_source: u64 = 0,
    diagnostic_presented: u64 = 0,
    host_forwarded_presented: u64 = 0,
    synthetic_presented: u64 = 0,

    pub fn note(self: *Tally, result: PresentOutcome, class: SourceClass) void {
        switch (result) {
            .guest_frame_presented => switch (class) {
                .guest_authentic => self.guest_presented +|= 1,
                .diagnostic => self.diagnostic_presented +|= 1,
                .host_forwarded => self.host_forwarded_presented +|= 1,
                .synthetic, .replay => self.synthetic_presented +|= 1,
                else => self.diagnostic_presented +|= 1,
            },
            .guest_frame_unchanged => self.guest_unchanged +|= 1,
            .guest_frame_unreadable => self.guest_unreadable +|= 1,
            .guest_frame_copy_failed => self.guest_copy_failed +|= 1,
            .no_guest_frame => self.no_guest_source +|= 1,
        }
    }

    /// The only number that may be quoted as "the title rendered".
    pub fn authenticFrames(self: Tally) u64 {
        return self.guest_presented;
    }

    pub fn totalPresented(self: Tally) u64 {
        return self.guest_presented +| self.diagnostic_presented +| self.synthetic_presented +| self.host_forwarded_presented;
    }

    pub fn anyDefect(self: Tally) bool {
        return self.guest_unreadable != 0 or self.guest_copy_failed != 0;
    }
};

test "a diagnostic frame that crosses every edge still fails the title contract" {
    var custody = Custody{ .source = .{
        .generation = 1,
        .address = .{ .guest_physical = 0x1FC0_0000 },
        .width = 1280,
        .height = 720,
        .content_checksum = 0xABCD,
        .source_class = @intFromEnum(SourceClass.diagnostic),
    } };
    inline for (@typeInfo(Edge).@"enum".fields) |field| {
        custody.note(@enumFromInt(field.value), 100 + field.value);
    }
    try std.testing.expect(custody.firstGap() == null);
    try std.testing.expect(!custody.satisfiesTitleContract());

    custody.source.source_class = @intFromEnum(SourceClass.guest_authentic);
    try std.testing.expect(custody.satisfiesTitleContract());
}

test "a host diagnostic present needs no fictional guest address" {
    var custody = Custody{ .source = .{
        .generation = 1,
        .width = 1280,
        .height = 720,
        .source_class = @intFromEnum(SourceClass.diagnostic),
    } };
    custody.note(.emulator_discovery, 10);
    custody.note(.host_image_import, 11);
    custody.note(.presenter_handoff, 12);
    custody.note(.native_present, 13);
    try std.testing.expectEqual(PresentOutcome.guest_frame_presented, outcome(custody, 0, 0));

    var tally = Tally{};
    tally.note(outcome(custody, 0, 0), custody.source.sourceOf());
    try std.testing.expectEqual(@as(u64, 1), tally.diagnostic_presented);
    try std.testing.expectEqual(@as(u64, 0), tally.authenticFrames());
    try std.testing.expect(!tally.anyDefect());
}

// The 2026-08-31 presenter state: 43 native presents, zero guest frames. The
// counter that must not be quotable as output.
test "no guest source is distinguished from a guest frame that did not change" {
    const nothing = Custody{};
    try std.testing.expectEqual(PresentOutcome.no_guest_frame, outcome(nothing, 0, 0));
    try std.testing.expect(!PresentOutcome.no_guest_frame.countsAsGuestOutput());
    try std.testing.expect(!PresentOutcome.no_guest_frame.isDefect());

    var found = Custody{ .source = .{
        .generation = 5,
        .address = .{ .guest_physical = 0x1FC0_0000 },
        .width = 1280,
        .height = 720,
        .content_checksum = 0xFEED,
        .source_class = @intFromEnum(SourceClass.guest_authentic),
    } };
    found.note(.emulator_discovery, 10);
    // Same checksum as the last presented frame and no explicit repeat: this
    // is a stale buffer, not new output.
    try std.testing.expectEqual(PresentOutcome.guest_frame_unchanged, outcome(found, 4, 0xFEED));
    // With the repeat declared, it is a title that rendered the same picture.
    found.source.repeat_declared = 1;
    found.note(.host_image_import, 11);
    found.note(.presenter_handoff, 12);
    found.note(.native_present, 13);
    try std.testing.expectEqual(PresentOutcome.guest_frame_presented, outcome(found, 4, 0xFEED));
}

test "a discovered source with no geometry is unreadable rather than absent" {
    var custody = Custody{ .source = .{ .generation = 1, .address = .{ .guest_physical = 0x1FC0_0000 } } };
    custody.note(.emulator_discovery, 10);
    const result = outcome(custody, 0, 0);
    try std.testing.expectEqual(PresentOutcome.guest_frame_unreadable, result);
    try std.testing.expect(result.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, result.describe(), "it is the emulator's") != null);
}

test "a frame that reaches the presenter and not the driver is a copy failure" {
    var custody = Custody{ .source = .{
        .generation = 2,
        .address = .{ .guest_physical = 0x1FC0_0000 },
        .width = 1280,
        .height = 720,
        .content_checksum = 1,
        .source_class = @intFromEnum(SourceClass.guest_authentic),
    } };
    custody.note(.emulator_discovery, 10);
    custody.note(.host_image_import, 11);
    try std.testing.expectEqual(PresentOutcome.guest_frame_copy_failed, outcome(custody, 1, 0));
}

test "the tally keeps diagnostic frames out of the authentic count forever" {
    var tally = Tally{};
    var index: u32 = 0;
    while (index < 43) : (index += 1) {
        tally.note(.guest_frame_presented, .diagnostic);
    }
    try std.testing.expectEqual(@as(u64, 0), tally.authenticFrames());
    try std.testing.expectEqual(@as(u64, 43), tally.totalPresented());
    try std.testing.expect(!tally.anyDefect());

    tally.note(.guest_frame_presented, .guest_authentic);
    try std.testing.expectEqual(@as(u64, 1), tally.authenticFrames());

    tally.note(.guest_frame_unreadable, .guest_authentic);
    try std.testing.expect(tally.anyDefect());
}

test "the first gap in the chain names the owner to ask" {
    var custody = Custody{};
    custody.note(.guest_render_target, 100);
    try std.testing.expectEqual(Edge.guest_resolve_output, custody.firstGap().?);
    try std.testing.expectEqualStrings("guest:title", Edge.guest_resolve_output.owner());
    try std.testing.expect(std.mem.indexOf(u8, Edge.guest_render_target.gapMeans(), "consequence") != null);

    inline for (@typeInfo(Edge).@"enum".fields) |field| {
        const edge: Edge = @enumFromInt(field.value);
        try std.testing.expect(edge.label().len != 0);
        try std.testing.expect(edge.owner().len != 0);
        try std.testing.expect(edge.gapMeans().len != 0);
    }
}
