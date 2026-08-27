//! The contract a completed frame arrives under, and the arithmetic that puts
//! it on screen the right way up and the right shape.
//!
//! "The presenter needs a defined source, not an arbitrary `VkImage` creation
//! call." This is that definition. A frame is not a pointer: it is a pointer
//! plus the six facts that decide whether the picture is correct — extent, pixel
//! format, row pitch, which end of the buffer is the top, how a source that does
//! not match the window should be fitted into it, and who produced it.
//!
//! Every one of those has a wrong default that produces a picture rather than an
//! error. A source whose pitch is assumed tightly packed skews diagonally. A
//! bottom-up source presented top-down is upside down. A 1280×720 frame stretched
//! into a 2560×1440 window without preserving aspect is subtly wrong in a way
//! nobody reports as a bug. None of these return a failure code, so none of them
//! can be discovered later — they have to be stated by the producer.
//!
//! The `Inbox` exists for the other half of the problem: the producer and the
//! presenter run at different rates, and a producer that overwrites the buffer
//! the presenter is reading tears the frame. Double-buffering with an explicit
//! reading flag makes that impossible, and counts the frames it dropped instead
//! of hiding them — a drop rate is a fact about the pipeline, not an error.
//!
//! Deliberately holds no pixels. Descriptors carry a guest address and length;
//! resolving that to memory is the caller's job, because the caller is the only
//! thing that knows whether the address is still mapped.

const std = @import("std");
const provenance = @import("provenance.zig");

/// Which row of the buffer is the top of the picture. There is no safe default:
/// guessing produces an upside-down frame, which looks like a rendering bug
/// anywhere except here.
pub const Orientation = enum(u8) {
    /// Row zero is the top. The usual convention for a CPU framebuffer.
    top_down,
    /// Row zero is the bottom. Common for readbacks out of GL-style targets.
    bottom_up,
};

/// What to do when the source does not match the window.
pub const Fit = enum(u8) {
    /// Fill the window, ignoring aspect ratio. Fast and wrong for a 4:3 title
    /// in a 16:9 window.
    stretch,
    /// Scale to fit, preserving aspect ratio, and leave bars. The right default
    /// for an emulator: a 4:3 guest frame stays 4:3.
    letterbox,
    /// No scaling. Centre the source and leave whatever surrounds it.
    center,
};

pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,

    pub fn right(self: Rect) i32 {
        return self.x + @as(i32, @intCast(self.width));
    }

    pub fn bottom(self: Rect) i32 {
        return self.y + @as(i32, @intCast(self.height));
    }

    /// Whether the rect leaves any of the destination uncovered, which is what
    /// decides whether the frame needs a background clear before the copy.
    /// Without it the bars hold whatever the previous frame left there.
    pub fn covers(self: Rect, width: u32, height: u32) bool {
        return self.x <= 0 and self.y <= 0 and
            self.right() >= @as(i32, @intCast(width)) and
            self.bottom() >= @as(i32, @intCast(height));
    }
};

/// Where the source lands in the destination. Integer arithmetic throughout:
/// a rounded-up destination rect that exceeds the image by one pixel is a
/// validation error, not a cosmetic one.
pub fn computeFit(
    source_width: u32,
    source_height: u32,
    destination_width: u32,
    destination_height: u32,
    mode: Fit,
) ?Rect {
    if (source_width == 0 or source_height == 0) return null;
    if (destination_width == 0 or destination_height == 0) return null;
    switch (mode) {
        .stretch => return .{ .width = destination_width, .height = destination_height },
        .center => {
            const width = @min(source_width, destination_width);
            const height = @min(source_height, destination_height);
            return .{
                .x = @divTrunc(@as(i32, @intCast(destination_width)) - @as(i32, @intCast(width)), 2),
                .y = @divTrunc(@as(i32, @intCast(destination_height)) - @as(i32, @intCast(height)), 2),
                .width = width,
                .height = height,
            };
        },
        .letterbox => {
            // Compared as cross-products so the aspect ratio never passes
            // through a float, where 4:3 into 16:9 lands a pixel short.
            const source_wide = @as(u64, source_width) * destination_height >
                @as(u64, destination_width) * source_height;
            var width: u32 = undefined;
            var height: u32 = undefined;
            if (source_wide) {
                width = destination_width;
                height = @intCast(@max(
                    1,
                    @as(u64, destination_width) * source_height / source_width,
                ));
            } else {
                height = destination_height;
                width = @intCast(@max(
                    1,
                    @as(u64, destination_height) * source_width / source_height,
                ));
            }
            width = @min(width, destination_width);
            height = @min(height, destination_height);
            return .{
                .x = @divTrunc(@as(i32, @intCast(destination_width)) - @as(i32, @intCast(width)), 2),
                .y = @divTrunc(@as(i32, @intCast(destination_height)) - @as(i32, @intCast(height)), 2),
                .width = width,
                .height = height,
            };
        },
    }
}

/// One completed frame, described completely enough to present correctly.
pub const Descriptor = struct {
    /// Guest address of the first byte. Resolved by the caller, which is the
    /// only thing that knows whether it is still mapped.
    source_address: u64 = 0,
    source_length: u64 = 0,
    width: u32 = 0,
    height: u32 = 0,
    format: u32 = 0,
    /// Bytes per row as the producer laid them out. Zero means tightly packed —
    /// stated rather than assumed, because a padded row read as packed skews
    /// the picture diagonally instead of failing.
    row_pitch_bytes: u64 = 0,
    orientation: Orientation = .top_down,
    fit: Fit = .letterbox,
    producer: provenance.Producer = .xenia_host,
    /// Whether the guest performed the swap this frame belongs to. The single
    /// fact separating an authentic host frame from guest output, so it must
    /// come from an observed `VdSwap` and never from a frame having arrived.
    guest_swap_observed: bool = false,
    /// Monotonic, assigned by the inbox. Distinguishes a new frame from the
    /// same frame presented again, which is otherwise invisible.
    serial: u64 = 0,
    /// Digest of the complete readable payload at publication time. A pointer
    /// to a reused buffer is not a frame generation: content changing under
    /// the same pointer must create a generation, while an unchanged buffer
    /// observed on 148 heartbeats must remain one frame.
    content_digest: u64 = 0,

    pub fn valid(self: Descriptor) bool {
        return self.source_address != 0 and self.source_length != 0 and
            self.width != 0 and self.height != 0;
    }

    /// Bytes the producer must actually have written for the descriptor to
    /// describe a whole frame.
    pub fn requiredBytes(self: Descriptor, bytes_per_pixel: u32) u64 {
        const pitch = if (self.row_pitch_bytes == 0)
            @as(u64, self.width) * bytes_per_pixel
        else
            self.row_pitch_bytes;
        return pitch * self.height;
    }
};

pub const ContentObservation = struct {
    digest: u64,
    nonzero: bool,
};

/// Inspect a candidate once for frame-generation identity. Wyhash gives the
/// full byte payload a stable 64-bit identity; the explicit non-zero fact keeps
/// an allocated-but-unwritten image from being advertised as guest output.
pub fn inspectContent(bytes: []const u8) ContentObservation {
    var nonzero = false;
    for (bytes) |byte| {
        if (byte != 0) {
            nonzero = true;
            break;
        }
    }
    const raw = std.hash.Wyhash.hash(0x524F_5345_5454_4533, bytes);
    return .{ .digest = if (raw == 0) 1 else raw, .nonzero = nonzero };
}

pub const ContentStamp = struct {
    producer_source: u64 = 0,
    source_length: u64 = 0,
    width: u32 = 0,
    height: u32 = 0,
    format: u32 = 0,
    row_pitch_bytes: u64 = 0,
    orientation: Orientation = .top_down,
    fit: Fit = .letterbox,
    producer: provenance.Producer = .xenia_host,
    guest_swap_observed: bool = false,
    digest: u64 = 0,

    fn fromDescriptor(descriptor: Descriptor, producer_source: u64, digest: u64) ContentStamp {
        return .{
            .producer_source = producer_source,
            .source_length = descriptor.source_length,
            .width = descriptor.width,
            .height = descriptor.height,
            .format = descriptor.format,
            .row_pitch_bytes = descriptor.row_pitch_bytes,
            .orientation = descriptor.orientation,
            .fit = descriptor.fit,
            .producer = descriptor.producer,
            .guest_swap_observed = descriptor.guest_swap_observed,
            .digest = digest,
        };
    }

    fn sameSource(self: ContentStamp, other: ContentStamp) bool {
        return self.producer_source == other.producer_source and
            self.source_length == other.source_length and
            self.width == other.width and self.height == other.height and
            self.format == other.format and
            self.row_pitch_bytes == other.row_pitch_bytes and
            self.orientation == other.orientation and self.fit == other.fit and
            self.producer == other.producer and
            self.guest_swap_observed == other.guest_swap_observed;
    }

    fn eql(self: ContentStamp, other: ContentStamp) bool {
        return self.sameSource(other) and self.digest == other.digest;
    }
};

pub const PublicationDisposition = enum(u8) {
    published,
    unchanged,
    rejected,
};

pub const Publication = struct {
    disposition: PublicationDisposition,
    serial: u64 = 0,
};

/// Why the presenter had no frame to show. Each value is a different thing to
/// fix, and "no source" alone is the answer that sends a reader nowhere.
pub const Absence = enum(u8) {
    /// No producer has ever published. The handoff is not wired up.
    never_published,
    /// A frame was published and has already been shown. Normal at idle.
    already_consumed,
    /// The producer described a frame that is not internally consistent.
    malformed_descriptor,
    /// The described memory is not readable.
    source_unmapped,
    /// The producer published fewer bytes than the extent requires.
    source_truncated,
    /// The pixel format is not one the presenter can copy.
    format_unsupported,

    pub fn label(self: Absence) []const u8 {
        return switch (self) {
            .never_published => "no producer has ever published a frame; the Xenia output handoff is not connected",
            .already_consumed => "the most recent frame has already been presented; the producer has not published a newer one",
            .malformed_descriptor => "a frame was published with a zero extent, address or length",
            .source_unmapped => "the published frame's memory is not readable at the address given",
            .source_truncated => "the published frame is shorter than its extent and pitch require",
            .format_unsupported => "the published frame's pixel format is not one the presenter can copy",
        };
    }
};

/// Double-buffered handoff between a producer and the presenter.
///
/// The invariant: the slot the presenter is reading is never the slot the
/// producer writes. Without it a producer running ahead of the display tears
/// the frame in a way that looks like a rendering artefact.
pub const Inbox = struct {
    slots: [2]Descriptor = [_]Descriptor{.{}} ** 2,
    /// Slot the producer will write next.
    write_slot: u8 = 0,
    /// Slot the presenter currently holds, when it holds one.
    reading_slot: ?u8 = null,
    /// Newest published serial; zero means nothing has ever been published.
    latest_serial: u64 = 0,
    consumed_serial: u64 = 0,
    published: u64 = 0,
    consumed: u64 = 0,
    /// Frames overwritten before the presenter took them. Backpressure, not an
    /// error — but a rate worth knowing.
    dropped: u64 = 0,
    last_absence: ?Absence = .never_published,
    content_observations: u64 = 0,
    unchanged_observations: u64 = 0,
    content_changes: u64 = 0,
    source_changes: u64 = 0,
    last_content: ?ContentStamp = null,

    pub fn publish(self: *Inbox, descriptor: Descriptor) u64 {
        if (!descriptor.valid()) {
            self.last_absence = .malformed_descriptor;
            return 0;
        }
        // Never write the slot being read. With two slots and at most one
        // reader there is always exactly one free.
        if (self.reading_slot) |reading| {
            if (self.write_slot == reading) self.write_slot = 1 - reading;
        }
        const slot = self.write_slot;
        if (self.slots[slot].serial > self.consumed_serial and self.slots[slot].serial != 0) {
            self.dropped +|= 1;
        }
        self.latest_serial +|= 1;
        var stored = descriptor;
        stored.serial = self.latest_serial;
        self.slots[slot] = stored;
        self.write_slot = 1 - slot;
        self.published +|= 1;
        self.last_absence = null;
        return stored.serial;
    }

    /// Publish only a genuinely new source generation. This is the ingress
    /// equivalent of the GPU work-credit ledger: polling and heartbeat logs
    /// may observe a frame repeatedly, but only a descriptor or byte-content
    /// change earns a new serial.
    pub fn publishIfChanged(
        self: *Inbox,
        descriptor: Descriptor,
        producer_source: u64,
        content_digest: u64,
    ) Publication {
        self.content_observations +|= 1;
        if (!descriptor.valid() or producer_source == 0 or content_digest == 0) {
            self.last_absence = .malformed_descriptor;
            return .{ .disposition = .rejected };
        }

        const stamp = ContentStamp.fromDescriptor(descriptor, producer_source, content_digest);
        if (self.last_content) |previous| {
            if (previous.eql(stamp)) {
                self.unchanged_observations +|= 1;
                return .{ .disposition = .unchanged, .serial = self.latest_serial };
            }
            if (previous.sameSource(stamp))
                self.content_changes +|= 1
            else
                self.source_changes +|= 1;
        } else {
            self.source_changes +|= 1;
        }

        var stamped = descriptor;
        stamped.content_digest = content_digest;
        const serial = self.publish(stamped);
        if (serial == 0) return .{ .disposition = .rejected };
        self.last_content = stamp;
        return .{ .disposition = .published, .serial = serial };
    }

    /// Take the newest unconsumed frame, if there is one. The returned
    /// descriptor stays valid until `release`.
    pub fn acquire(self: *Inbox) ?Descriptor {
        var best: ?u8 = null;
        for (self.slots, 0..) |slot, index| {
            if (slot.serial == 0 or slot.serial <= self.consumed_serial) continue;
            if (best == null or slot.serial > self.slots[best.?].serial) best = @intCast(index);
        }
        const chosen = best orelse {
            self.last_absence = if (self.latest_serial == 0) .never_published else .already_consumed;
            return null;
        };
        self.reading_slot = chosen;
        return self.slots[chosen];
    }

    /// Release the held slot. `presented` marks the frame consumed; a frame the
    /// presenter could not use is released without consuming it, so a later
    /// attempt can retry the same frame rather than reporting it as shown.
    pub fn release(self: *Inbox, presented: bool) void {
        const reading = self.reading_slot orelse return;
        if (presented) {
            self.consumed_serial = @max(self.consumed_serial, self.slots[reading].serial);
            self.consumed +|= 1;
        }
        self.reading_slot = null;
    }

    pub fn absence(self: *const Inbox) Absence {
        return self.last_absence orelse .already_consumed;
    }

    /// Newest descriptor whether or not it has already been consumed. This is
    /// observation-only: ownership remains with `acquire`/`release`.
    pub fn latest(self: *const Inbox) ?Descriptor {
        var best: ?Descriptor = null;
        for (self.slots) |slot| {
            if (slot.serial == 0) continue;
            if (best == null or slot.serial > best.?.serial) best = slot;
        }
        return best;
    }

    pub fn noteUnusable(self: *Inbox, reason: Absence) void {
        self.last_absence = reason;
    }
};

test "letterbox preserves aspect ratio and centres the result" {
    // 4:3 into 16:9 leaves pillars, not a stretched picture.
    const fitted = computeFit(640, 480, 1920, 1080, .letterbox).?;
    try std.testing.expectEqual(@as(u32, 1440), fitted.width);
    try std.testing.expectEqual(@as(u32, 1080), fitted.height);
    try std.testing.expectEqual(@as(i32, 240), fitted.x);
    try std.testing.expectEqual(@as(i32, 0), fitted.y);
    try std.testing.expect(!fitted.covers(1920, 1080));
}

test "a source wider than the window leaves bars above and below" {
    const fitted = computeFit(2560, 1080, 1280, 1024, .letterbox).?;
    try std.testing.expectEqual(@as(u32, 1280), fitted.width);
    try std.testing.expectEqual(@as(u32, 540), fitted.height);
    try std.testing.expectEqual(@as(i32, 0), fitted.x);
    try std.testing.expectEqual(@as(i32, 242), fitted.y);
}

test "a matching aspect ratio fills the window exactly" {
    const fitted = computeFit(1280, 720, 2560, 1440, .letterbox).?;
    try std.testing.expectEqual(@as(u32, 2560), fitted.width);
    try std.testing.expectEqual(@as(u32, 1440), fitted.height);
    try std.testing.expect(fitted.covers(2560, 1440));
}

// Rounding a scaled rect outward puts the blit one pixel outside the image,
// which the driver rejects rather than clips.
test "a fitted rect never exceeds the destination" {
    const awkward = computeFit(1023, 767, 1280, 719, .letterbox).?;
    try std.testing.expect(awkward.width <= 1280);
    try std.testing.expect(awkward.height <= 719);
    try std.testing.expect(awkward.right() <= 1280);
    try std.testing.expect(awkward.bottom() <= 719);
}

test "stretch fills and centre neither scales nor overflows" {
    const stretched = computeFit(640, 480, 1920, 1080, .stretch).?;
    try std.testing.expectEqual(@as(u32, 1920), stretched.width);
    try std.testing.expect(stretched.covers(1920, 1080));

    const centred = computeFit(640, 480, 1920, 1080, .center).?;
    try std.testing.expectEqual(@as(u32, 640), centred.width);
    try std.testing.expectEqual(@as(i32, 640), centred.x);

    // A source larger than the window is clipped rather than scaled.
    const oversized = computeFit(4096, 4096, 100, 100, .center).?;
    try std.testing.expectEqual(@as(u32, 100), oversized.width);
}

test "a zero extent has no fit rather than an empty one" {
    try std.testing.expect(computeFit(0, 480, 100, 100, .letterbox) == null);
    try std.testing.expect(computeFit(640, 480, 0, 100, .letterbox) == null);
}

test "a padded row pitch is used rather than assumed packed" {
    const padded = Descriptor{
        .source_address = 0x1000,
        .source_length = 1,
        .width = 1280,
        .height = 720,
        .row_pitch_bytes = 5376,
    };
    try std.testing.expectEqual(@as(u64, 5376 * 720), padded.requiredBytes(4));

    const packed_rows = Descriptor{ .source_address = 0x1000, .source_length = 1, .width = 1280, .height = 720 };
    try std.testing.expectEqual(@as(u64, 1280 * 4 * 720), packed_rows.requiredBytes(4));
}

test "an inbox with nothing published says the handoff is not connected" {
    var inbox = Inbox{};
    try std.testing.expect(inbox.acquire() == null);
    try std.testing.expectEqual(Absence.never_published, inbox.absence());
    try std.testing.expect(std.mem.indexOf(u8, Absence.never_published.label(), "not connected") != null);
}

// The invariant the double buffer exists for.
test "the producer never overwrites the slot the presenter is reading" {
    var inbox = Inbox{};
    _ = inbox.publish(.{ .source_address = 0x1000, .source_length = 16, .width = 4, .height = 4 });
    const held = inbox.acquire().?;
    try std.testing.expectEqual(@as(u64, 1), held.serial);

    const reading = inbox.reading_slot.?;
    _ = inbox.publish(.{ .source_address = 0x2000, .source_length = 16, .width = 4, .height = 4 });
    // The held descriptor is untouched.
    try std.testing.expectEqual(@as(u64, 0x1000), inbox.slots[reading].source_address);
    try std.testing.expectEqual(@as(u64, 1), inbox.slots[reading].serial);
}

test "a released-but-unpresented frame is retried rather than counted as shown" {
    var inbox = Inbox{};
    _ = inbox.publish(.{ .source_address = 0x1000, .source_length = 16, .width = 4, .height = 4 });
    _ = inbox.acquire().?;
    inbox.release(false);
    try std.testing.expectEqual(@as(u64, 0), inbox.consumed);

    const again = inbox.acquire().?;
    try std.testing.expectEqual(@as(u64, 1), again.serial);
    inbox.release(true);
    try std.testing.expectEqual(@as(u64, 1), inbox.consumed);
    try std.testing.expect(inbox.acquire() == null);
    try std.testing.expectEqual(Absence.already_consumed, inbox.absence());
}

test "the newest frame wins and overwritten ones are counted, not hidden" {
    var inbox = Inbox{};
    _ = inbox.publish(.{ .source_address = 0x1000, .source_length = 16, .width = 4, .height = 4 });
    _ = inbox.publish(.{ .source_address = 0x2000, .source_length = 16, .width = 4, .height = 4 });
    _ = inbox.publish(.{ .source_address = 0x3000, .source_length = 16, .width = 4, .height = 4 });
    try std.testing.expectEqual(@as(u64, 3), inbox.published);
    try std.testing.expect(inbox.dropped >= 1);

    const newest = inbox.acquire().?;
    try std.testing.expectEqual(@as(u64, 3), newest.serial);
    try std.testing.expectEqual(@as(u64, 0x3000), newest.source_address);
    try std.testing.expectEqual(@as(u64, 3), inbox.latest().?.serial);
}

test "a malformed descriptor is refused and named" {
    var inbox = Inbox{};
    try std.testing.expectEqual(@as(u64, 0), inbox.publish(.{ .width = 4, .height = 4 }));
    try std.testing.expectEqual(Absence.malformed_descriptor, inbox.absence());
    try std.testing.expectEqual(@as(u64, 0), inbox.published);
}

test "retained pixels observed repeatedly earn one frame serial" {
    var inbox = Inbox{};
    const descriptor = Descriptor{
        .source_address = 0x2000,
        .source_length = 16,
        .width = 2,
        .height = 2,
        .format = 44,
        .row_pitch_bytes = 8,
    };
    const first = inbox.publishIfChanged(descriptor, 0x1000, 0xAAAA);
    try std.testing.expectEqual(PublicationDisposition.published, first.disposition);
    try std.testing.expectEqual(@as(u64, 1), first.serial);

    var heartbeat: usize = 0;
    while (heartbeat < 147) : (heartbeat += 1) {
        const repeated = inbox.publishIfChanged(descriptor, 0x1000, 0xAAAA);
        try std.testing.expectEqual(PublicationDisposition.unchanged, repeated.disposition);
        try std.testing.expectEqual(@as(u64, 1), repeated.serial);
    }
    try std.testing.expectEqual(@as(u64, 1), inbox.published);
    try std.testing.expectEqual(@as(u64, 147), inbox.unchanged_observations);
}

test "content and semantic presentation changes create new generations" {
    var inbox = Inbox{};
    var descriptor = Descriptor{
        .source_address = 0x2000,
        .source_length = 16,
        .width = 2,
        .height = 2,
        .format = 44,
        .row_pitch_bytes = 8,
    };
    _ = inbox.publishIfChanged(descriptor, 0x1000, 0xAAAA);
    const changed = inbox.publishIfChanged(descriptor, 0x1000, 0xBBBB);
    try std.testing.expectEqual(PublicationDisposition.published, changed.disposition);
    try std.testing.expectEqual(@as(u64, 1), inbox.content_changes);

    descriptor.guest_swap_observed = true;
    const requested = inbox.publishIfChanged(descriptor, 0x1000, 0xBBBB);
    try std.testing.expectEqual(PublicationDisposition.published, requested.disposition);
    try std.testing.expectEqual(@as(u64, 2), inbox.source_changes);
    try std.testing.expectEqual(@as(u64, 3), inbox.published);
}

test "content inspection distinguishes empty and written frames" {
    const empty = [_]u8{0} ** 64;
    var written = empty;
    written[31] = 1;
    const empty_result = inspectContent(&empty);
    const written_result = inspectContent(&written);
    try std.testing.expect(!empty_result.nonzero);
    try std.testing.expect(written_result.nonzero);
    try std.testing.expect(empty_result.digest != 0);
    try std.testing.expect(written_result.digest != empty_result.digest);
}

test "every absence names a different thing to fix" {
    inline for (@typeInfo(Absence).@"enum".fields) |field| {
        const absence: Absence = @enumFromInt(field.value);
        try std.testing.expect(absence.label().len > 0);
    }
}
