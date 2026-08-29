//! Frame identity, custody and presentation truth.
//!
//! A frame is credited once by `(run, source, generation, serial)`. Its pixels,
//! the decision to present them, and the native completion are separate facts.
//! This is the seam that permits a Cocoa/Metal fallback to display verified
//! guest pixels without turning that display into a fabricated VdSwap.

const std = @import("std");
const contract = @import("cocoa_graphics_control_contract");

pub const Domain = contract.Domain;
pub const FrameClass = contract.FrameClass;
pub const FrameTruth = contract.FrameTruth;

pub const PixelFormat = enum(u8) {
    unknown,
    rgba8_unorm,
    rgba8_srgb,
    bgra8_unorm,
    bgra8_srgb,

    pub fn label(self: PixelFormat) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .rgba8_unorm => "RGBA8_UNORM",
            .rgba8_srgb => "RGBA8_SRGB",
            .bgra8_unorm => "BGRA8_UNORM",
            .bgra8_srgb => "BGRA8_SRGB",
        };
    }

    pub fn bytesPerPixel(self: PixelFormat) ?u8 {
        return switch (self) {
            .rgba8_unorm, .rgba8_srgb, .bgra8_unorm, .bgra8_srgb => 4,
            .unknown => null,
        };
    }

    pub fn fromVulkan(value: u32) PixelFormat {
        return switch (value) {
            37 => .rgba8_unorm,
            43 => .rgba8_srgb,
            44 => .bgra8_unorm,
            50 => .bgra8_srgb,
            else => .unknown,
        };
    }
};

pub const Orientation = enum(u8) {
    top_down,
    bottom_up,

    pub fn label(self: Orientation) []const u8 {
        return switch (self) {
            .top_down => "top-down",
            .bottom_up => "bottom-up",
        };
    }
};

pub const Fit = enum(u8) {
    stretch,
    letterbox,
    center,
};

/// Where a frame's pixels come from.
///
/// The distinction is not cosmetic. A guest-memory frame can be validated
/// against a byte range, so it must be; a host-generated frame has no source
/// buffer at all, and requiring one of it was the reason Rosette's own
/// presentations never entered custody. Both take custody; only one of them can
/// ever carry guest pixels.
pub const Payload = enum(u8) {
    /// Pixels read out of guest-visible memory at `source_address`.
    guest_memory,
    /// Pixels the host drew on the window's own drawable. `source_address` is
    /// the sink identity that produced them — the layer, the swapchain — and
    /// there is no byte range to check.
    host_generated,

    pub fn label(self: Payload) []const u8 {
        return switch (self) {
            .guest_memory => "guest-memory",
            .host_generated => "host-generated",
        };
    }

    pub fn mayCarryGuestPixels(self: Payload) bool {
        return self == .guest_memory;
    }
};

pub const Identity = struct {
    run: u64 = 0,
    source: u64 = 0,
    generation: u64 = 0,
    serial: u64 = 0,

    pub fn valid(self: Identity) bool {
        return self.run != 0 and self.source != 0 and self.generation != 0 and self.serial != 0;
    }

    pub fn eql(self: Identity, other: Identity) bool {
        return self.run == other.run and self.source == other.source and
            self.generation == other.generation and self.serial == other.serial;
    }
};

pub const Descriptor = struct {
    identity: Identity = .{},
    payload: Payload = .guest_memory,
    source_address: u64 = 0,
    source_length: u64 = 0,
    width: u32 = 0,
    height: u32 = 0,
    row_pitch: u64 = 0,
    format: PixelFormat = .unknown,
    orientation: Orientation = .top_down,
    fit: Fit = .letterbox,
    producer: Domain = .unknown,
    /// Digest captured when the producer published this generation. Required
    /// for guest pixels so a reused address cannot silently change underneath
    /// one frame identity.
    content_digest: u64 = 0,
    guest_pixels: bool = false,
    guest_requested_present: bool = false,
    synthetic_guest_control: bool = false,
    /// How many presentations this one identity accounts for.
    ///
    /// Custody is fed on the checkpoint cadence and the presenter puts frames
    /// up between checkpoints, so one identity can legitimately stand for
    /// several presentations of the same picture. Stating the coverage is what
    /// makes "every frame the window showed is in custody" an exact claim
    /// instead of one that drifts by a frame per run.
    presentations_covered: u64 = 1,

    pub fn requiredBytes(self: Descriptor) ?u64 {
        const bpp = self.format.bytesPerPixel() orelse return null;
        if (self.width == 0 or self.height == 0) return null;
        const tight = std.math.mul(u64, self.width, bpp) catch return null;
        const pitch = if (self.row_pitch == 0) tight else self.row_pitch;
        if (pitch < tight) return null;
        return std.math.mul(u64, pitch, self.height) catch null;
    }

    pub fn valid(self: Descriptor) bool {
        if (!self.identity.valid() or self.source_address == 0) return false;
        if (self.guest_pixels and !self.payload.mayCarryGuestPixels()) return false;
        switch (self.payload) {
            .guest_memory => {
                if (self.source_length == 0) return false;
                const required = self.requiredBytes() orelse return false;
                if (self.source_length < required) return false;
            },
            .host_generated => {
                // Nothing is claimed about a buffer, so nothing about one may
                // be asserted here either.
                if (self.source_length != 0) return false;
                if (self.content_digest != 0) return false;
                if (self.guest_requested_present) return false;
                if (self.width == 0 or self.height == 0 or self.format == .unknown) return false;
            },
        }
        if (self.guest_pixels and self.content_digest == 0) return false;
        if (self.guest_pixels and self.producer != .guest_title and
            self.producer != .xenia_host and self.producer != .xenia_vulkan)
            return false;
        if (self.synthetic_guest_control and self.guest_requested_present) return false;
        return true;
    }

    pub fn samePayload(self: Descriptor, other: Descriptor) bool {
        return self.identity.eql(other.identity) and
            self.payload == other.payload and
            self.source_address == other.source_address and
            self.source_length == other.source_length and
            self.width == other.width and self.height == other.height and
            self.row_pitch == other.row_pitch and self.format == other.format and
            self.orientation == other.orientation and self.fit == other.fit and
            self.producer == other.producer and self.content_digest == other.content_digest and
            self.guest_pixels == other.guest_pixels and
            self.guest_requested_present == other.guest_requested_present and
            self.synthetic_guest_control == other.synthetic_guest_control and
            self.presentations_covered == other.presentations_covered;
    }
};

pub const State = enum(u8) {
    empty,
    offered,
    validated,
    acquired,
    submitted,
    presented,
    rejected,
    released,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .empty => "empty",
            .offered => "offered",
            .validated => "validated",
            .acquired => "acquired",
            .submitted => "submitted",
            .presented => "presented",
            .rejected => "rejected",
            .released => "released",
        };
    }
};

pub const Rejection = enum(u8) {
    none,
    malformed_identity,
    malformed_extent,
    unsupported_format,
    truncated_source,
    missing_content_digest,
    duplicate_identity_conflict,
    wrong_actor,
    invalid_transition,
    presentation_failed,

    pub fn label(self: Rejection) []const u8 {
        return switch (self) {
            .none => "none",
            .malformed_identity => "malformed-identity",
            .malformed_extent => "malformed-extent",
            .unsupported_format => "unsupported-format",
            .truncated_source => "truncated-source",
            .missing_content_digest => "missing-content-digest",
            .duplicate_identity_conflict => "duplicate-identity-conflict",
            .wrong_actor => "wrong-actor",
            .invalid_transition => "invalid-transition",
            .presentation_failed => "presentation-failed",
        };
    }
};

pub const Record = struct {
    descriptor: Descriptor = .{},
    state: State = .empty,
    rejection: Rejection = .none,
    custodian: Domain = .unknown,
    offered_step: u64 = 0,
    validated_step: u64 = 0,
    acquired_step: u64 = 0,
    submitted_step: u64 = 0,
    presented_step: u64 = 0,
    presentation_owner: Domain = .unknown,
    frame_class: FrameClass = .none,
    observations: u64 = 0,
};

pub const OfferResult = enum(u8) {
    accepted,
    duplicate,
    rejected,
    conflict,
    overflow,
};

pub const max_frames: usize = 64;

pub const Summary = struct {
    offered: u64 = 0,
    /// Presentations accounted for, which is what "every frame the window
    /// showed is in custody" is measured against — not the number of custody
    /// records, which can stand for more than one presentation each.
    presentations_covered: u64 = 0,
    duplicates: u64 = 0,
    rejected: u64 = 0,
    conflicts: u64 = 0,
    acquired: u64 = 0,
    submitted: u64 = 0,
    presented: u64 = 0,
    authentic_guest: u64 = 0,
    guest_pixels_host_cadence: u64 = 0,
    diagnostic: u64 = 0,
    synthetic_guest_control: u64 = 0,
    last_class: FrameClass = .none,
};

pub const Ledger = struct {
    records: [max_frames]Record = [_]Record{.{}} ** max_frames,
    count: usize = 0,
    next: usize = 0,
    offered: u64 = 0,
    duplicates: u64 = 0,
    rejected: u64 = 0,
    conflicts: u64 = 0,
    acquired: u64 = 0,
    submitted: u64 = 0,
    presented: u64 = 0,
    presentations_covered: u64 = 0,
    authentic_guest: u64 = 0,
    guest_pixels_host_cadence: u64 = 0,
    diagnostic: u64 = 0,
    synthetic_guest_control: u64 = 0,
    last_class: FrameClass = .none,

    pub fn offer(self: *Ledger, descriptor: Descriptor, step: u64) OfferResult {
        if (self.find(descriptor.identity)) |existing| {
            existing.observations +|= 1;
            if (existing.descriptor.samePayload(descriptor)) {
                self.duplicates +|= 1;
                return .duplicate;
            }
            existing.rejection = .duplicate_identity_conflict;
            self.conflicts +|= 1;
            return .conflict;
        }
        const rejection = validate(descriptor);
        if (rejection != .none) {
            self.rejected +|= 1;
            self.store(.{
                .descriptor = descriptor,
                .state = .rejected,
                .rejection = rejection,
                .custodian = descriptor.producer,
                .offered_step = step,
                .observations = 1,
            });
            return .rejected;
        }
        self.offered +|= 1;
        self.store(.{
            .descriptor = descriptor,
            .state = .offered,
            .custodian = descriptor.producer,
            .offered_step = step,
            .observations = 1,
        });
        return .accepted;
    }

    pub fn validateFrame(self: *Ledger, identity: Identity, actor: Domain, step: u64) bool {
        const record = self.find(identity) orelse return false;
        if (record.state != .offered) return self.rejectTransition(record, .invalid_transition);
        if (actor != .rosette_runtime and actor != record.descriptor.producer) return self.rejectTransition(record, .wrong_actor);
        record.state = .validated;
        record.validated_step = step;
        return true;
    }

    pub fn acquire(self: *Ledger, identity: Identity, actor: Domain, step: u64) bool {
        const record = self.find(identity) orelse return false;
        if (record.state != .validated) return self.rejectTransition(record, .invalid_transition);
        if (actor != .rosette_runtime and actor != .xenia_vulkan) return self.rejectTransition(record, .wrong_actor);
        record.state = .acquired;
        record.custodian = actor;
        record.acquired_step = step;
        self.acquired +|= 1;
        return true;
    }

    pub fn submit(self: *Ledger, identity: Identity, actor: Domain, step: u64) bool {
        const record = self.find(identity) orelse return false;
        if (record.state != .acquired) return self.rejectTransition(record, .invalid_transition);
        if (actor != record.custodian) return self.rejectTransition(record, .wrong_actor);
        record.state = .submitted;
        record.submitted_step = step;
        self.submitted +|= 1;
        return true;
    }

    pub fn present(
        self: *Ledger,
        identity: Identity,
        actor: Domain,
        native_completed: bool,
        step: u64,
    ) FrameClass {
        const record = self.find(identity) orelse return .none;
        if (record.state != .submitted or actor != record.custodian) {
            _ = self.rejectTransition(record, if (actor != record.custodian) .wrong_actor else .invalid_transition);
            return .none;
        }
        if (!native_completed) {
            record.state = .rejected;
            record.rejection = .presentation_failed;
            self.rejected +|= 1;
            return .none;
        }
        const truth = FrameTruth{
            .guest_pixels = record.descriptor.guest_pixels,
            .guest_requested_present = record.descriptor.guest_requested_present,
            .native_present_completed = true,
            .synthetic_guest_control = record.descriptor.synthetic_guest_control,
        };
        const class = truth.class();
        record.state = .presented;
        record.presentation_owner = actor;
        record.presented_step = step;
        record.frame_class = class;
        self.presented +|= 1;
        self.presentations_covered +|= @max(record.descriptor.presentations_covered, 1);
        self.last_class = class;
        switch (class) {
            .authentic_guest_present => self.authentic_guest +|= 1,
            .guest_pixels_host_cadence => self.guest_pixels_host_cadence +|= 1,
            .diagnostic_host => self.diagnostic +|= 1,
            .synthetic_guest_control => self.synthetic_guest_control +|= 1,
            else => {},
        }
        return class;
    }

    pub fn release(self: *Ledger, identity: Identity, actor: Domain) bool {
        const record = self.find(identity) orelse return false;
        if (record.state != .presented or record.custodian != actor) return false;
        record.state = .released;
        record.custodian = record.descriptor.producer;
        return true;
    }

    pub fn latestPending(self: *Ledger) ?*Record {
        var selected: ?*Record = null;
        for (self.records[0..self.count]) |*record| {
            if (record.state != .offered and record.state != .validated) continue;
            if (selected == null or record.descriptor.identity.serial > selected.?.descriptor.identity.serial)
                selected = record;
        }
        return selected;
    }

    /// Return the live custody entry for an already offered frame.  This is a
    /// lookup, not another observation: callers use it to advance the same
    /// identity without inflating the duplicate-observation counters.
    pub fn lookup(self: *Ledger, identity: Identity) ?*Record {
        return self.find(identity);
    }

    pub fn summary(self: *const Ledger) Summary {
        return .{
            .offered = self.offered,
            .presentations_covered = self.presentations_covered,
            .duplicates = self.duplicates,
            .rejected = self.rejected,
            .conflicts = self.conflicts,
            .acquired = self.acquired,
            .submitted = self.submitted,
            .presented = self.presented,
            .authentic_guest = self.authentic_guest,
            .guest_pixels_host_cadence = self.guest_pixels_host_cadence,
            .diagnostic = self.diagnostic,
            .synthetic_guest_control = self.synthetic_guest_control,
            .last_class = self.last_class,
        };
    }

    fn find(self: *Ledger, identity: Identity) ?*Record {
        if (!identity.valid()) return null;
        for (self.records[0..self.count]) |*record| {
            if (record.descriptor.identity.eql(identity)) return record;
        }
        return null;
    }

    fn store(self: *Ledger, record: Record) void {
        self.records[self.next] = record;
        self.next = (self.next + 1) % max_frames;
        if (self.count < max_frames) self.count += 1;
    }

    fn rejectTransition(self: *Ledger, record: *Record, reason: Rejection) bool {
        record.rejection = reason;
        self.rejected +|= 1;
        return false;
    }
};

pub fn validate(descriptor: Descriptor) Rejection {
    if (!descriptor.identity.valid() or descriptor.source_address == 0) return .malformed_identity;
    if (descriptor.payload == .guest_memory and descriptor.source_length == 0) return .malformed_identity;
    if (descriptor.width == 0 or descriptor.height == 0 or descriptor.row_pitch != 0 and descriptor.row_pitch < @as(u64, descriptor.width) * 4)
        return .malformed_extent;
    if (descriptor.format == .unknown) return .unsupported_format;
    if (descriptor.payload == .guest_memory) {
        const required = descriptor.requiredBytes() orelse return .malformed_extent;
        if (descriptor.source_length < required) return .truncated_source;
    }
    if (descriptor.guest_pixels and descriptor.content_digest == 0) return .missing_content_digest;
    if (!descriptor.valid()) return .wrong_actor;
    return .none;
}

fn guestDescriptor() Descriptor {
    return .{
        .identity = .{ .run = 1, .source = 0x1000, .generation = 2, .serial = 3 },
        .source_address = 0x2000,
        .source_length = 1280 * 720 * 4,
        .width = 1280,
        .height = 720,
        .row_pitch = 1280 * 4,
        .format = .bgra8_unorm,
        .producer = .xenia_host,
        .content_digest = 0xCAFE_BABE,
        .guest_pixels = true,
    };
}

test "host-cadenced guest pixels do not close guest swap" {
    var ledger = Ledger{};
    const descriptor = guestDescriptor();
    try std.testing.expectEqual(OfferResult.accepted, ledger.offer(descriptor, 10));
    try std.testing.expect(ledger.validateFrame(descriptor.identity, .rosette_runtime, 11));
    try std.testing.expect(ledger.acquire(descriptor.identity, .rosette_runtime, 12));
    try std.testing.expect(ledger.submit(descriptor.identity, .rosette_runtime, 13));
    const class = ledger.present(descriptor.identity, .rosette_runtime, true, 14);
    try std.testing.expectEqual(FrameClass.guest_pixels_host_cadence, class);
    try std.testing.expect(class.countsGuestPixels());
    try std.testing.expect(!class.closesAuthenticSwap());
}

test "guest requested presentation is credited independently" {
    var ledger = Ledger{};
    var descriptor = guestDescriptor();
    descriptor.guest_requested_present = true;
    _ = ledger.offer(descriptor, 10);
    try std.testing.expect(ledger.validateFrame(descriptor.identity, .rosette_runtime, 11));
    try std.testing.expect(ledger.acquire(descriptor.identity, .rosette_runtime, 12));
    try std.testing.expect(ledger.submit(descriptor.identity, .rosette_runtime, 13));
    try std.testing.expectEqual(FrameClass.authentic_guest_present, ledger.present(descriptor.identity, .rosette_runtime, true, 14));
}

test "one frame identity cannot describe two payloads" {
    var ledger = Ledger{};
    const descriptor = guestDescriptor();
    try std.testing.expectEqual(OfferResult.accepted, ledger.offer(descriptor, 1));
    try std.testing.expectEqual(OfferResult.duplicate, ledger.offer(descriptor, 2));
    var conflict = descriptor;
    conflict.width = 640;
    try std.testing.expectEqual(OfferResult.conflict, ledger.offer(conflict, 3));
    try std.testing.expectEqual(@as(u64, 1), ledger.conflicts);
}

test "one frame identity cannot hide a changed pixel generation" {
    var ledger = Ledger{};
    const descriptor = guestDescriptor();
    _ = ledger.offer(descriptor, 1);
    var changed = descriptor;
    changed.content_digest +|= 1;
    try std.testing.expectEqual(OfferResult.conflict, ledger.offer(changed, 2));
    try std.testing.expectEqual(Rejection.duplicate_identity_conflict, ledger.records[0].rejection);
}

test "truncated frames are refused before custody moves" {
    var ledger = Ledger{};
    var descriptor = guestDescriptor();
    descriptor.source_length = 16;
    try std.testing.expectEqual(OfferResult.rejected, ledger.offer(descriptor, 1));
    try std.testing.expectEqual(Rejection.truncated_source, ledger.records[0].rejection);
    try std.testing.expectEqual(@as(u64, 0), ledger.acquired);
}

test "guest pixels require a content generation rather than only an address" {
    var ledger = Ledger{};
    var descriptor = guestDescriptor();
    descriptor.content_digest = 0;
    try std.testing.expectEqual(OfferResult.rejected, ledger.offer(descriptor, 1));
    try std.testing.expectEqual(Rejection.missing_content_digest, ledger.records[0].rejection);
}

fn diagnosticDescriptor() Descriptor {
    return .{
        .identity = .{ .run = 1, .source = 0x4000, .generation = 1, .serial = 7 },
        .payload = .host_generated,
        .source_address = 0x4000,
        .source_length = 0,
        .width = 1280,
        .height = 720,
        .format = .bgra8_unorm,
        .producer = .rosette_runtime,
    };
}

test "a host clear takes custody without a source buffer" {
    var ledger = Ledger{};
    const descriptor = diagnosticDescriptor();
    try std.testing.expectEqual(Rejection.none, validate(descriptor));
    try std.testing.expectEqual(OfferResult.accepted, ledger.offer(descriptor, 10));
    try std.testing.expect(ledger.validateFrame(descriptor.identity, .rosette_runtime, 11));
    try std.testing.expect(ledger.acquire(descriptor.identity, .rosette_runtime, 12));
    try std.testing.expect(ledger.submit(descriptor.identity, .rosette_runtime, 13));
    const class = ledger.present(descriptor.identity, .rosette_runtime, true, 14);
    try std.testing.expectEqual(FrameClass.diagnostic_host, class);
    try std.testing.expect(!class.countsGuestPixels());
    try std.testing.expect(!class.closesAuthenticSwap());
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().diagnostic);
}

test "a host-generated frame may not claim guest pixels" {
    var descriptor = diagnosticDescriptor();
    descriptor.guest_pixels = true;
    descriptor.content_digest = 0xABCD;
    descriptor.producer = .xenia_host;
    try std.testing.expect(!descriptor.valid());
    try std.testing.expectEqual(Rejection.wrong_actor, validate(descriptor));
}

test "a host-generated frame may not describe a source range" {
    var descriptor = diagnosticDescriptor();
    descriptor.source_length = 1280 * 720 * 4;
    try std.testing.expect(!descriptor.valid());
}

test "a host-generated frame still needs an extent and a format" {
    var descriptor = diagnosticDescriptor();
    descriptor.format = .unknown;
    try std.testing.expectEqual(Rejection.unsupported_format, validate(descriptor));
    descriptor = diagnosticDescriptor();
    descriptor.height = 0;
    try std.testing.expectEqual(Rejection.malformed_extent, validate(descriptor));
}

test "guest-memory frames keep their byte-range check" {
    var descriptor = guestDescriptor();
    descriptor.source_length = 16;
    try std.testing.expectEqual(Rejection.truncated_source, validate(descriptor));
    descriptor = guestDescriptor();
    descriptor.source_length = 0;
    try std.testing.expectEqual(Rejection.malformed_identity, validate(descriptor));
}

test "one identity cannot describe a host clear and a guest buffer" {
    var ledger = Ledger{};
    const descriptor = diagnosticDescriptor();
    try std.testing.expectEqual(OfferResult.accepted, ledger.offer(descriptor, 1));
    var reinterpreted = descriptor;
    reinterpreted.payload = .guest_memory;
    reinterpreted.source_length = 1280 * 720 * 4;
    try std.testing.expectEqual(OfferResult.conflict, ledger.offer(reinterpreted, 2));
}

test "one custody record can account for several presentations" {
    var ledger = Ledger{};
    var descriptor = diagnosticDescriptor();
    descriptor.presentations_covered = 3;
    _ = ledger.offer(descriptor, 1);
    try std.testing.expect(ledger.validateFrame(descriptor.identity, .rosette_runtime, 2));
    try std.testing.expect(ledger.acquire(descriptor.identity, .rosette_runtime, 3));
    try std.testing.expect(ledger.submit(descriptor.identity, .rosette_runtime, 4));
    _ = ledger.present(descriptor.identity, .rosette_runtime, true, 5);
    const summary = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), summary.presented);
    try std.testing.expectEqual(@as(u64, 3), summary.presentations_covered);
}

test "coverage defaults to one and is never zero" {
    var ledger = Ledger{};
    var descriptor = diagnosticDescriptor();
    descriptor.presentations_covered = 0;
    _ = ledger.offer(descriptor, 1);
    _ = ledger.validateFrame(descriptor.identity, .rosette_runtime, 2);
    _ = ledger.acquire(descriptor.identity, .rosette_runtime, 3);
    _ = ledger.submit(descriptor.identity, .rosette_runtime, 4);
    _ = ledger.present(descriptor.identity, .rosette_runtime, true, 5);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().presentations_covered);
}

test "one identity cannot silently change how much it covers" {
    var ledger = Ledger{};
    const descriptor = diagnosticDescriptor();
    try std.testing.expectEqual(OfferResult.accepted, ledger.offer(descriptor, 1));
    var wider = descriptor;
    wider.presentations_covered = 4;
    try std.testing.expectEqual(OfferResult.conflict, ledger.offer(wider, 2));
}
