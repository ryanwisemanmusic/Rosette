//! Establish whether a disc image is *usable* before anything reads it whole.
//!
//! The defect this exists for
//! --------------------------
//! The only thing that reads a title image end to end is the launch-input
//! content hash, so a damaged image used to announce itself as a digest that
//! stopped at a percentage — minutes in, with an offset for a verdict. Nothing
//! before that point had looked at the image at all, so an image that could
//! never have mounted cost the same two minutes as one that was merely
//! unhashable, and neither said which it was.
//!
//! Being *whole* and being *usable* are different questions with wildly
//! different prices. Whole costs six gigabytes of reads. Usable costs the
//! volume descriptor and the root directory table — a few kilobytes at offsets
//! the container format fixes in advance. This runs the cheap question first.
//!
//! Host access is confined to `inspectFile`. The inspection itself drives an
//! injected reader, so its decisions are testable without a damaged volume to
//! hand — which is not a thing that can be manufactured on demand.

const std = @import("std");
const xiso = @import("xenia_xiso_format");

/// A refusal is a refusal whatever produced it: the pre-flight cares that the
/// bytes did not arrive, not which layer said no.
pub const ReadOutcome = union(enum) {
    read: usize,
    refused: []const u8,
};

/// Positional reads over something image-shaped.
pub const ImageReader = struct {
    context: *anyopaque,
    size: u64,
    readAt: *const fn (context: *anyopaque, offset: u64, buffer: []u8) ReadOutcome,
};

pub const Outcome = enum {
    /// The image could not be opened or measured.
    unavailable,
    /// No known partition base carries the magic. Whatever this file is, it is
    /// not a disc image — a separate problem from a damaged one.
    not_an_image,
    /// The magic is there but a read the image cannot be mounted without was
    /// refused.
    structure_unreadable,
    /// Structure is intact and a content sample was refused. The image will
    /// mount; something inside it is gone.
    content_suspect,
    /// Everything probed read cleanly. This is not a claim that the image is
    /// whole — only the content hash establishes that.
    structure_intact,

    pub fn text(self: Outcome) []const u8 {
        return switch (self) {
            .unavailable => "unavailable",
            .not_an_image => "not-an-image",
            .structure_unreadable => "structure-unreadable",
            .content_suspect => "content-suspect",
            .structure_intact => "structure-intact",
        };
    }

    /// Whether this outcome means the image cannot be used at all.
    pub fn blocksUse(self: Outcome) bool {
        return switch (self) {
            .not_an_image, .structure_unreadable => true,
            .unavailable, .content_suspect, .structure_intact => false,
        };
    }
};

pub const Finding = struct {
    outcome: Outcome = .unavailable,
    image_bytes: u64 = 0,
    volume: ?xiso.VolumeDescriptor = null,
    probes: u32 = 0,
    refusals: u32 = 0,
    refused_offset: ?u64 = null,
    refused_kind: ?xiso.ProbeKind = null,
    refused_error: []const u8 = "",
    samples_planned: u32 = 0,
    samples_read: u32 = 0,
    elapsed_ns: u64 = 0,

    /// What the refusal that stopped the pre-flight costs, when the image was
    /// identified well enough to say.
    pub fn impact(self: Finding) ?xiso.DamageImpact {
        const volume = self.volume orelse return null;
        const offset = self.refused_offset orelse return null;
        return xiso.impactOfDamage(volume, self.image_bytes, offset, offset + 1);
    }
};

pub const Options = struct {
    content_samples: usize = xiso.default_content_samples,
    /// How long the content net may take.
    ///
    /// The samples are spread across the whole image on purpose, so every one
    /// of them is a seek. On a slow external volume that is around eighty
    /// milliseconds each, and a fixed count that is free on an internal disk
    /// becomes seconds added to every launch. A budget adapts instead of
    /// picking a constant that is wrong for one of them: a fast volume answers
    /// the whole net, a slow one answers as much of it as it can afford, and
    /// the difference is visible as `samples_read` short of `samples_planned`.
    sample_budget_ns: u64 = 1_500 * std.time.ns_per_ms,
};

fn monotonicNanoseconds() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}

/// Read a whole span through a scratch buffer, reporting only whether every
/// byte of it arrived.
fn spanArrives(
    reader: ImageReader,
    finding: *Finding,
    offset: u64,
    length: u64,
    scratch: []u8,
) bool {
    var position: u64 = 0;
    while (position < length) {
        const remaining = length - position;
        const want: usize = @intCast(@min(remaining, @as(u64, scratch.len)));
        finding.probes += 1;
        switch (reader.readAt(reader.context, offset + position, scratch[0..want])) {
            .refused => |name| {
                finding.refusals += 1;
                if (finding.refused_offset == null) {
                    finding.refused_offset = offset + position;
                    finding.refused_error = name;
                }
                return false;
            },
            .read => |count| {
                if (count == 0) return false;
                position += count;
            },
        }
    }
    return true;
}

/// Identify, then establish structure, then sample content.
///
/// Content sampling stops at the first refusal on purpose. One refusal already
/// settles the question the samples were asked, and on failing storage every
/// further refusal costs the device's whole internal retry budget for evidence
/// that changes no decision.
pub fn inspect(reader: ImageReader, options: Options) Finding {
    const started_ns = monotonicNanoseconds();
    var finding = Finding{ .outcome = .not_an_image, .image_bytes = reader.size };
    defer {}

    var scratch: [64 * 1024]u8 = undefined;

    // Identification: twenty bytes per candidate base.
    var identification: [xiso.identification_step_count]xiso.ProbeStep = undefined;
    const identification_count = xiso.identificationPlan(reader.size, &identification);
    var game_offset: ?u64 = null;
    for (identification[0..identification_count]) |step| {
        const want: usize = @intCast(step.length);
        finding.probes += 1;
        switch (reader.readAt(reader.context, step.offset, scratch[0..want])) {
            .refused => |name| {
                finding.refusals += 1;
                if (finding.refused_offset == null) {
                    finding.refused_offset = step.offset;
                    finding.refused_kind = step.kind;
                    finding.refused_error = name;
                }
            },
            .read => |count| {
                if (count < want) continue;
                if (std.mem.eql(u8, scratch[0..xiso.magic.len], xiso.magic)) {
                    game_offset = step.offset - xiso.volume_descriptor_sector * xiso.sector_bytes;
                    break;
                }
            },
        }
    }

    const base = game_offset orelse {
        // A file with no magic anywhere is not a disc image. A file whose
        // candidate offsets were refused is a different claim, and the
        // difference decides whether the operator repackages or recopies.
        if (finding.refusals != 0) finding.outcome = .structure_unreadable;
        finding.elapsed_ns = elapsedSince(started_ns);
        return finding;
    };

    // Structure: the descriptor and the root directory table.
    const descriptor_offset = xiso.volumeDescriptorOffset(base);
    finding.probes += 1;
    switch (reader.readAt(reader.context, descriptor_offset, scratch[0..@intCast(xiso.sector_bytes)])) {
        .refused => |name| {
            finding.refusals += 1;
            finding.outcome = .structure_unreadable;
            if (finding.refused_offset == null) finding.refused_error = name;
            finding.refused_offset = descriptor_offset;
            finding.refused_kind = .volume_descriptor;
            finding.elapsed_ns = elapsedSince(started_ns);
            return finding;
        },
        .read => |count| {
            const volume = xiso.readVolumeDescriptor(base, scratch[0..count]) orelse {
                // The magic was there and the descriptor around it is not
                // believable. That is a damaged descriptor, not a file that
                // happens not to be an image.
                finding.outcome = .structure_unreadable;
                finding.refused_offset = descriptor_offset;
                finding.refused_kind = .volume_descriptor;
                finding.refused_error = "ImplausibleVolumeDescriptor";
                finding.elapsed_ns = elapsedSince(started_ns);
                return finding;
            };
            finding.volume = volume;
        },
    }

    const volume = finding.volume.?;
    if (!spanArrives(reader, &finding, volume.rootOffset(), volume.root_size, &scratch)) {
        finding.outcome = .structure_unreadable;
        if (finding.refused_kind == null) finding.refused_kind = .directory_table;
        finding.elapsed_ns = elapsedSince(started_ns);
        return finding;
    }

    // Content: a bounded net, not a proof.
    var samples: [xiso.default_content_samples]xiso.ProbeStep = undefined;
    const wanted = @min(options.content_samples, samples.len);
    const sample_count = xiso.contentSamplePlan(volume, reader.size, wanted, &samples);
    finding.samples_planned = @intCast(sample_count);
    finding.outcome = .structure_intact;
    const sampling_started_ns = monotonicNanoseconds();
    for (samples[0..sample_count]) |step| {
        if (options.sample_budget_ns != 0 and
            elapsedSince(sampling_started_ns) >= options.sample_budget_ns) break;
        const want: usize = @intCast(step.length);
        finding.probes += 1;
        switch (reader.readAt(reader.context, step.offset, scratch[0..want])) {
            .refused => |name| {
                finding.refusals += 1;
                finding.outcome = .content_suspect;
                if (finding.refused_offset == null) finding.refused_error = name;
                finding.refused_offset = step.offset;
                finding.refused_kind = .content_sample;
                break;
            },
            .read => finding.samples_read += 1,
        }
    }

    finding.elapsed_ns = elapsedSince(started_ns);
    return finding;
}

fn elapsedSince(started_ns: u64) u64 {
    const now = monotonicNanoseconds();
    return if (now > started_ns) now - started_ns else 0;
}

const FileContext = struct {
    io: std.Io,
    file: std.Io.File,

    fn readAt(context: *anyopaque, offset: u64, buffer: []u8) ReadOutcome {
        const self: *FileContext = @ptrCast(@alignCast(context));
        const count = self.file.readPositional(self.io, &.{buffer}, offset) catch |err| {
            return .{ .refused = @errorName(err) };
        };
        return .{ .read = count };
    }
};

/// Inspect a disc image on the host. The only function here that touches one.
pub fn inspectFile(io: std.Io, path: []const u8, options: Options) Finding {
    const file = openImage(io, path) catch return .{ .outcome = .unavailable };
    defer file.close(io);

    var size: u64 = 0;
    if (file.stat(io)) |stat| {
        if (stat.kind != .file) return .{ .outcome = .unavailable };
        size = stat.size;
    } else |_| return .{ .outcome = .unavailable };

    var context = FileContext{ .io = io, .file = file };
    return inspect(.{
        .context = @ptrCast(&context),
        .size = size,
        .readAt = FileContext.readAt,
    }, options);
}

fn openImage(io: std.Io, path: []const u8) !std.Io.File {
    return if (std.fs.path.isAbsolute(path))
        std.Io.Dir.openFileAbsolute(io, path, .{})
    else
        std.Io.Dir.cwd().openFile(io, path, .{});
}

// ---------------------------------------------------------------------------
// Tests
//
// The reader is injected precisely so these can exist: a volume with a hole in
// a chosen place is not something that can be produced on demand.
// ---------------------------------------------------------------------------

const TestImage = struct {
    bytes: []u8,
    /// Half-open range that refuses every read overlapping it.
    hole_start: u64 = 0,
    hole_end: u64 = 0,

    fn readAt(context: *anyopaque, offset: u64, buffer: []u8) ReadOutcome {
        const self: *TestImage = @ptrCast(@alignCast(context));
        if (offset >= self.bytes.len) return .{ .read = 0 };
        const available = self.bytes.len - offset;
        const count = @min(buffer.len, available);
        if (self.hole_end > self.hole_start and
            offset < self.hole_end and self.hole_start < offset + count)
        {
            return .{ .refused = "InputOutput" };
        }
        @memcpy(buffer[0..count], self.bytes[@intCast(offset)..][0..count]);
        return .{ .read = count };
    }

    fn reader(self: *TestImage) ImageReader {
        return .{ .context = @ptrCast(self), .size = self.bytes.len, .readAt = TestImage.readAt };
    }
};

fn buildTestImage(allocator: std.mem.Allocator, total: usize, root_sector: u32, root_size: u32) ![]u8 {
    const bytes = try allocator.alloc(u8, total);
    @memset(bytes, 0);
    const descriptor: usize = @intCast(xiso.volumeDescriptorOffset(0));
    @memcpy(bytes[descriptor..][0..xiso.magic.len], xiso.magic);
    std.mem.writeInt(u32, bytes[descriptor + xiso.root_sector_field_offset ..][0..4], root_sector, .little);
    std.mem.writeInt(u32, bytes[descriptor + xiso.root_size_field_offset ..][0..4], root_size, .little);
    return bytes;
}

test "a healthy image is identified and its structure established" {
    const allocator = std.testing.allocator;
    const bytes = try buildTestImage(allocator, 4 * 1024 * 1024, 64, 2048);
    defer allocator.free(bytes);
    var image = TestImage{ .bytes = bytes };

    const finding = inspect(image.reader(), .{ .content_samples = 8 });
    try std.testing.expectEqual(Outcome.structure_intact, finding.outcome);
    try std.testing.expect(!finding.outcome.blocksUse());
    try std.testing.expectEqual(@as(u32, 0), finding.refusals);
    try std.testing.expectEqual(@as(u64, 0), finding.volume.?.game_offset);
    try std.testing.expectEqual(@as(u32, 64), finding.volume.?.root_sector);
    try std.testing.expectEqual(@as(u32, 8), finding.samples_read);
}

test "a file with no magic anywhere is not an image, which is not the same as damaged" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(bytes);
    @memset(bytes, 0xAB);
    var image = TestImage{ .bytes = bytes };

    const finding = inspect(image.reader(), .{});
    try std.testing.expectEqual(Outcome.not_an_image, finding.outcome);
    try std.testing.expectEqual(@as(u32, 0), finding.refusals);
    try std.testing.expect(finding.volume == null);
}

test "a hole over the volume descriptor is refused before anything is hashed" {
    const allocator = std.testing.allocator;
    const bytes = try buildTestImage(allocator, 4 * 1024 * 1024, 64, 2048);
    defer allocator.free(bytes);
    var image = TestImage{
        .bytes = bytes,
        .hole_start = xiso.volumeDescriptorOffset(0),
        .hole_end = xiso.volumeDescriptorOffset(0) + 4096,
    };

    const finding = inspect(image.reader(), .{});
    try std.testing.expectEqual(Outcome.structure_unreadable, finding.outcome);
    try std.testing.expect(finding.outcome.blocksUse());
    try std.testing.expect(finding.refusals > 0);
}

test "a hole over the directory table blocks use and is named as structure" {
    const allocator = std.testing.allocator;
    const bytes = try buildTestImage(allocator, 4 * 1024 * 1024, 64, 4096);
    defer allocator.free(bytes);
    const root_offset = xiso.sectorOffset(0, 64);
    var image = TestImage{ .bytes = bytes, .hole_start = root_offset, .hole_end = root_offset + 2048 };

    const finding = inspect(image.reader(), .{});
    try std.testing.expectEqual(Outcome.structure_unreadable, finding.outcome);
    try std.testing.expectEqual(xiso.ProbeKind.directory_table, finding.refused_kind.?);
    try std.testing.expectEqual(xiso.DamageImpact.directory_damaged, finding.impact().?);
}

test "a hole in content leaves the image mountable and says so" {
    const allocator = std.testing.allocator;
    const total: usize = 4 * 1024 * 1024;
    const bytes = try buildTestImage(allocator, total, 64, 2048);
    defer allocator.free(bytes);
    // Wide enough that an eight-sample net cannot step over it.
    var image = TestImage{ .bytes = bytes, .hole_start = 1024 * 1024, .hole_end = 3 * 1024 * 1024 };

    const finding = inspect(image.reader(), .{ .content_samples = 8 });
    try std.testing.expectEqual(Outcome.content_suspect, finding.outcome);
    try std.testing.expect(!finding.outcome.blocksUse());
    try std.testing.expectEqual(xiso.ProbeKind.content_sample, finding.refused_kind.?);
    try std.testing.expectEqual(xiso.DamageImpact.content_damaged, finding.impact().?);
}

test "content sampling stops at the first refusal rather than paying for every one" {
    const allocator = std.testing.allocator;
    const bytes = try buildTestImage(allocator, 4 * 1024 * 1024, 64, 2048);
    defer allocator.free(bytes);
    // Start the hole clear of the directory table: a hole that covers it is a
    // structural failure, which is a different verdict and a different test.
    var image = TestImage{ .bytes = bytes, .hole_start = 256 * 1024, .hole_end = 4 * 1024 * 1024 };

    const finding = inspect(image.reader(), .{ .content_samples = 32 });
    try std.testing.expectEqual(Outcome.content_suspect, finding.outcome);
    // Exactly one refusal is paid for, however many samples remained.
    try std.testing.expectEqual(@as(u32, 1), finding.refusals);
    try std.testing.expect(finding.samples_read < finding.samples_planned);
}

test "a descriptor that cannot be believed is damage, not a missing image" {
    const allocator = std.testing.allocator;
    const bytes = try buildTestImage(allocator, 4 * 1024 * 1024, 64, 2048);
    defer allocator.free(bytes);
    // The magic survives; the table size does not.
    const descriptor: usize = @intCast(xiso.volumeDescriptorOffset(0));
    std.mem.writeInt(u32, bytes[descriptor + xiso.root_size_field_offset ..][0..4], 0, .little);
    var image = TestImage{ .bytes = bytes };

    const finding = inspect(image.reader(), .{});
    try std.testing.expectEqual(Outcome.structure_unreadable, finding.outcome);
    try std.testing.expectEqualStrings("ImplausibleVolumeDescriptor", finding.refused_error);
}

test "a slow volume answers as much of the net as it can afford" {
    const allocator = std.testing.allocator;
    const bytes = try buildTestImage(allocator, 4 * 1024 * 1024, 64, 2048);
    defer allocator.free(bytes);
    var image = TestImage{ .bytes = bytes };

    // A budget of zero nanoseconds is not "no budget" — that is what disables
    // it — so the smallest real budget still lets the first sample through and
    // then stops, which is what a slow volume looks like.
    const finding = inspect(image.reader(), .{ .content_samples = 32, .sample_budget_ns = 1 });
    try std.testing.expectEqual(Outcome.structure_intact, finding.outcome);
    try std.testing.expectEqual(@as(u32, 32), finding.samples_planned);
    try std.testing.expect(finding.samples_read < finding.samples_planned);
    // Structure was still fully established; only the net was cut short.
    try std.testing.expect(finding.volume != null);
    try std.testing.expectEqual(@as(u32, 0), finding.refusals);
}

test "structure is established in kilobytes, not in the size of the image" {
    const allocator = std.testing.allocator;
    const bytes = try buildTestImage(allocator, 8 * 1024 * 1024, 64, 2048);
    defer allocator.free(bytes);
    var image = TestImage{ .bytes = bytes };

    const finding = inspect(image.reader(), .{ .content_samples = 64 });
    try std.testing.expectEqual(Outcome.structure_intact, finding.outcome);
    // Identification, the descriptor, the table and the samples: bounded by a
    // small constant, never by the image's length.
    try std.testing.expect(finding.probes <= xiso.identification_step_count + 2 + 64);
}

test "every outcome states its own vocabulary" {
    try std.testing.expectEqualStrings("structure-intact", Outcome.structure_intact.text());
    try std.testing.expectEqualStrings("not-an-image", Outcome.not_an_image.text());
    try std.testing.expectEqualStrings("structure-unreadable", Outcome.structure_unreadable.text());
    try std.testing.expectEqualStrings("content-suspect", Outcome.content_suspect.text());
}
