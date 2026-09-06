//! Host-backend custody and Vulkan/Metal semantic comparison.
//!
//! Vulkan and Metal may have different API call sequences. They must still
//! receive the same Xenos transaction, retain the same guest input/effect
//! digests, and report distinct completion edges. Host object tokens are
//! generation-qualified so a recreated layer, drawable, queue, or swapchain
//! cannot satisfy an older frame.

const std = @import("std");

pub const max_objects: usize = 256;
pub const max_frames: usize = 128;

pub const Backend = enum(u8) {
    vulkan,
    metal,
    cocoa,
    d3d,
    unknown,

    pub fn label(self: Backend) []const u8 {
        return switch (self) {
            .vulkan => "vulkan",
            .metal => "metal",
            .cocoa => "cocoa",
            .d3d => "d3d",
            .unknown => "unknown",
        };
    }
};

pub const ObjectKind = enum(u8) {
    application,
    window,
    layer,
    device,
    queue,
    swapchain,
    image,
    drawable,
    command_buffer,
    fence,
    unknown,
};

pub const ObjectIdentity = struct {
    backend: Backend = .unknown,
    kind: ObjectKind = .unknown,
    token: u64 = 0,
    generation: u64 = 0,

    pub fn valid(self: ObjectIdentity) bool {
        return self.backend != .unknown and self.kind != .unknown and
            self.token != 0 and self.generation != 0;
    }

    pub fn eql(self: ObjectIdentity, other: ObjectIdentity) bool {
        return self.backend == other.backend and self.kind == other.kind and
            self.token == other.token and self.generation == other.generation;
    }
};

pub const ObjectRecord = struct {
    identity: ObjectIdentity = .{},
    parent: ObjectIdentity = .{},
    alive: bool = false,
    created_step: u64 = 0,
    released_step: u64 = 0,
};

pub const ObjectLedger = struct {
    records: [max_objects]ObjectRecord = [_]ObjectRecord{.{}} ** max_objects,
    count: usize = 0,
    next_generation: [max_objects]u64 = [_]u64{0} ** max_objects,
    rejected: u64 = 0,

    pub fn create(self: *ObjectLedger, backend: Backend, kind: ObjectKind, token: u64, parent: ObjectIdentity, step: u64) ?ObjectIdentity {
        if (backend == .unknown or kind == .unknown or token == 0 or self.count >= max_objects) {
            self.rejected +|= 1;
            return null;
        }
        const slot = token % max_objects;
        self.next_generation[slot] +|= 1;
        if (self.next_generation[slot] == 0) self.next_generation[slot] = 1;
        const identity = ObjectIdentity{ .backend = backend, .kind = kind, .token = token, .generation = self.next_generation[slot] };
        self.records[self.count] = .{ .identity = identity, .parent = parent, .alive = true, .created_step = step };
        self.count += 1;
        return identity;
    }

    pub fn lookup(self: *ObjectLedger, identity: ObjectIdentity) ?*ObjectRecord {
        for (self.records[0..self.count]) |*record| {
            if (record.identity.eql(identity)) return record;
        }
        return null;
    }

    pub fn release(self: *ObjectLedger, identity: ObjectIdentity, step: u64) bool {
        const record = self.lookup(identity) orelse {
            self.rejected +|= 1;
            return false;
        };
        if (!record.alive) {
            self.rejected +|= 1;
            return false;
        }
        record.alive = false;
        record.released_step = step;
        return true;
    }

    pub fn alive(self: *ObjectLedger, identity: ObjectIdentity) bool {
        return if (self.lookup(identity)) |record| record.alive else false;
    }
};

pub const CompletionStage = enum(u8) {
    acquired,
    recorded,
    submitted,
    queue_completed,
    gpu_completed,
    present_requested,
    drawable_released,
    compositor_observed,
    display_observed,

    pub fn label(self: CompletionStage) []const u8 {
        return switch (self) {
            .acquired => "acquired",
            .recorded => "recorded",
            .submitted => "submitted",
            .queue_completed => "queue-completed",
            .gpu_completed => "gpu-completed",
            .present_requested => "present-requested",
            .drawable_released => "drawable-released",
            .compositor_observed => "compositor-observed",
            .display_observed => "display-observed",
        };
    }
};

pub const ComparisonOutcome = enum(u8) {
    semantic_equivalent_backend_difference,
    semantic_mismatch,
    synchronization_mismatch,
    resource_ownership_mismatch,
    format_or_coordinate_mismatch,
    completion_unobserved,
    incomparable,

    pub fn label(self: ComparisonOutcome) []const u8 {
        return switch (self) {
            .semantic_equivalent_backend_difference => "semantic-equivalent-backend-difference",
            .semantic_mismatch => "semantic-mismatch",
            .synchronization_mismatch => "synchronization-mismatch",
            .resource_ownership_mismatch => "resource-ownership-mismatch",
            .format_or_coordinate_mismatch => "format-or-coordinate-mismatch",
            .completion_unobserved => "completion-unobserved",
            .incomparable => "incomparable",
        };
    }
};

pub const FrameEvidence = struct {
    run_id: u64 = 0,
    frame_serial: u64 = 0,
    backend: Backend = .unknown,
    semantic_digest: u64 = 0,
    input_digest: u64 = 0,
    effect_digest: u64 = 0,
    target_digest: u64 = 0,
    shader_digest: u64 = 0,
    resolve_digest: u64 = 0,
    format_coordinate_digest: u64 = 0,
    layer: ObjectIdentity = .{},
    device: ObjectIdentity = .{},
    queue: ObjectIdentity = .{},
    image_or_drawable: ObjectIdentity = .{},
    stage_mask: u64 = 0,
    submission_id: u64 = 0,
    present_id: u64 = 0,
    has_error: bool = false,

    pub fn valid(self: FrameEvidence) bool {
        return self.run_id != 0 and self.frame_serial != 0 and self.backend != .unknown and
            self.semantic_digest != 0 and self.input_digest != 0 and self.effect_digest != 0 and
            self.layer.valid() and self.device.valid() and self.queue.valid() and
            self.image_or_drawable.valid();
    }

    pub fn has(self: FrameEvidence, stage: CompletionStage) bool {
        return (self.stage_mask & (@as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage))))) != 0;
    }

    pub fn note(self: *FrameEvidence, stage: CompletionStage) bool {
        if (self.has(stage)) return false;
        self.stage_mask |= @as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage)));
        return true;
    }
};

pub const Ledger = struct {
    frames: [max_frames]FrameEvidence = [_]FrameEvidence{.{}} ** max_frames,
    count: usize = 0,
    rejected: u64 = 0,

    pub fn append(self: *Ledger, evidence: FrameEvidence) bool {
        if (!evidence.valid() or self.count >= max_frames) {
            self.rejected +|= 1;
            return false;
        }
        for (self.frames[0..self.count]) |existing| {
            if (existing.run_id == evidence.run_id and existing.frame_serial == evidence.frame_serial and existing.backend == evidence.backend) {
                self.rejected +|= 1;
                return false;
            }
        }
        self.frames[self.count] = evidence;
        self.count += 1;
        return true;
    }

    pub fn find(self: *Ledger, run_id: u64, frame_serial: u64, backend: Backend) ?*FrameEvidence {
        for (self.frames[0..self.count]) |*candidate| {
            if (candidate.run_id == run_id and candidate.frame_serial == frame_serial and candidate.backend == backend) return candidate;
        }
        return null;
    }
};

pub fn compare(left: FrameEvidence, right: FrameEvidence) ComparisonOutcome {
    if (!left.valid() or !right.valid() or left.run_id != right.run_id or left.frame_serial != right.frame_serial) return .incomparable;
    if (left.input_digest != right.input_digest or left.semantic_digest != right.semantic_digest or left.effect_digest != right.effect_digest or left.target_digest != right.target_digest or left.shader_digest != right.shader_digest or left.resolve_digest != right.resolve_digest) return .semantic_mismatch;
    if (left.format_coordinate_digest != right.format_coordinate_digest) return .format_or_coordinate_mismatch;
    if (!sameObjectGeneration(left.layer, right.layer) or !sameObjectGeneration(left.device, right.device) or !sameObjectGeneration(left.queue, right.queue) or !sameObjectGeneration(left.image_or_drawable, right.image_or_drawable)) return .resource_ownership_mismatch;
    if (!left.has(.submitted) or !right.has(.submitted) or left.submission_id == 0 or right.submission_id == 0) return .synchronization_mismatch;
    if (!left.has(.gpu_completed) or !right.has(.gpu_completed) or !left.has(.present_requested) or !right.has(.present_requested)) return .completion_unobserved;
    return .semantic_equivalent_backend_difference;
}

fn sameObjectGeneration(left: ObjectIdentity, right: ObjectIdentity) bool {
    // Tokens belong to the backend's namespace: a Vulkan VkImage handle and a
    // Metal MTLTexture pointer are expected to differ. The normalized
    // evidence contract compares the object role and lifecycle generation;
    // semantic/input/format digests carry the cross-backend identity.
    return left.kind == right.kind and left.generation == right.generation;
}

fn object(backend: Backend, kind: ObjectKind, token: u64, generation: u64) ObjectIdentity {
    return .{ .backend = backend, .kind = kind, .token = token, .generation = generation };
}

fn makeFrame(backend: Backend) FrameEvidence {
    return .{
        .run_id = 1,
        .frame_serial = 2,
        .backend = backend,
        .semantic_digest = 3,
        .input_digest = 4,
        .effect_digest = 5,
        .target_digest = 6,
        .shader_digest = 7,
        .resolve_digest = 8,
        .format_coordinate_digest = 9,
        .layer = object(backend, .layer, 10, 1),
        .device = object(backend, .device, 11, 1),
        .queue = object(backend, .queue, 12, 1),
        .image_or_drawable = object(backend, .drawable, 13, 1),
        .stage_mask = (@as(u64, 1) << @intFromEnum(CompletionStage.submitted)) |
            (@as(u64, 1) << @intFromEnum(CompletionStage.gpu_completed)) |
            (@as(u64, 1) << @intFromEnum(CompletionStage.present_requested)),
        .submission_id = 20,
        .present_id = 21,
    };
}

test "object generations reject a stale drawable after recreation" {
    var ledger = ObjectLedger{};
    const first = ledger.create(.metal, .drawable, 7, .{}, 1).?;
    try std.testing.expect(ledger.release(first, 2));
    const second = ledger.create(.metal, .drawable, 7, .{}, 3).?;
    try std.testing.expect(second.generation != first.generation);
    try std.testing.expect(!ledger.alive(first));
    try std.testing.expect(ledger.alive(second));
    try std.testing.expect(!ledger.release(first, 4));
}

test "Vulkan and Metal may differ in API identity while sharing semantics" {
    const left = makeFrame(.vulkan);
    var right = makeFrame(.metal);
    right.layer.token = 101;
    right.device.token = 102;
    right.queue.token = 103;
    right.image_or_drawable.token = 104;
    try std.testing.expectEqual(ComparisonOutcome.semantic_equivalent_backend_difference, compare(left, right));
}

test "different semantic inputs are a mismatch, not a backend difference" {
    const left = makeFrame(.vulkan);
    var right = makeFrame(.metal);
    right.effect_digest = 99;
    try std.testing.expectEqual(ComparisonOutcome.semantic_mismatch, compare(left, right));
}

test "a missing GPU completion remains unobserved" {
    const left = makeFrame(.vulkan);
    var right = makeFrame(.metal);
    right.stage_mask &= ~(@as(u64, 1) << @intFromEnum(CompletionStage.gpu_completed));
    try std.testing.expectEqual(ComparisonOutcome.completion_unobserved, compare(left, right));
}

test "format and coordinate changes are separately classified" {
    const left = makeFrame(.vulkan);
    var right = makeFrame(.metal);
    right.format_coordinate_digest = 10;
    try std.testing.expectEqual(ComparisonOutcome.format_or_coordinate_mismatch, compare(left, right));
}

test "frame ledger rejects invalid or duplicate frame identities" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.append(makeFrame(.vulkan)));
    try std.testing.expect(!ledger.append(makeFrame(.vulkan)));
    var invalid = makeFrame(.metal);
    invalid.semantic_digest = 0;
    try std.testing.expect(!ledger.append(invalid));
}
