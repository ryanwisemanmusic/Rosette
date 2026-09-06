//! Backend-neutral Xenos frame transaction and semantic completion state.
//!
//! PM4 consumption, draw classification, host submission, EDRAM/resolve
//! effects, guest visibility, and display completion are different facts. This
//! transaction records them against one immutable batch identity so a host
//! present cannot be mistaken for a guest frame, and a consumed packet cannot
//! be mistaken for a submitted draw.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;
pub const max_transactions: usize = 64;

pub const Stage = enum(u8) {
    packet_consumed,
    draw_entry,
    draw_classified,
    draw_submitted,
    edram_written,
    resolve_completed,
    guest_visible,
    present_requested,
    gpu_completed,
    display_observed,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .packet_consumed => "packet-consumed",
            .draw_entry => "draw-entry",
            .draw_classified => "draw-classified",
            .draw_submitted => "draw-submitted",
            .edram_written => "edram-written",
            .resolve_completed => "resolve-completed",
            .guest_visible => "guest-visible",
            .present_requested => "present-requested",
            .gpu_completed => "gpu-completed",
            .display_observed => "display-observed",
        };
    }
};

pub const DrawClass = enum(u8) {
    target_backed,
    memory_export,
    resolve_only,
    intentional_no_output,
    emulator_dropped,
    unclassified,

    pub fn label(self: DrawClass) []const u8 {
        return switch (self) {
            .target_backed => "target-backed",
            .memory_export => "memory-export",
            .resolve_only => "resolve-only",
            .intentional_no_output => "intentional-no-output",
            .emulator_dropped => "emulator-dropped",
            .unclassified => "unclassified",
        };
    }

    pub fn candidateOutput(self: DrawClass) bool {
        return switch (self) {
            .target_backed, .memory_export, .resolve_only => true,
            .intentional_no_output, .emulator_dropped, .unclassified => false,
        };
    }

    pub fn defect(self: DrawClass) bool {
        return self == .emulator_dropped or self == .unclassified;
    }
};

pub const TransitionOutcome = enum(u8) {
    accepted,
    invalid_identity,
    duplicate,
    missing_prerequisite,
    wrong_source,
    incomplete_entry,
    incomplete_exit,
    full,

    pub fn label(self: TransitionOutcome) []const u8 {
        return switch (self) {
            .accepted => "accepted",
            .invalid_identity => "invalid-identity",
            .duplicate => "duplicate",
            .missing_prerequisite => "missing-prerequisite",
            .wrong_source => "wrong-source",
            .incomplete_entry => "incomplete-entry",
            .incomplete_exit => "incomplete-exit",
            .full => "full",
        };
    }
};

pub const Identity = struct {
    run_id: u64 = 0,
    frame_serial: u64 = 0,
    stream_epoch: u64 = 0,
    ring_generation: u64 = 0,
    batch_digest: u64 = 0,

    pub fn valid(self: Identity) bool {
        return self.run_id != 0 and self.frame_serial != 0 and
            self.stream_epoch != 0 and self.ring_generation != 0 and
            self.batch_digest != 0;
    }

    pub fn eql(self: Identity, other: Identity) bool {
        return self.run_id == other.run_id and self.frame_serial == other.frame_serial and
            self.stream_epoch == other.stream_epoch and self.ring_generation == other.ring_generation and
            self.batch_digest == other.batch_digest;
    }
};

/// Immutable semantic state captured before `IssueDraw` or an equivalent
/// reference-model draw classification. The hashes are owned by the register,
/// shader, texture, and memory domains; zero means that domain did not provide
/// a witness and is not silently filled in here.
pub const EntrySnapshot = struct {
    identity: Identity = .{},
    source: SourceClass = .unknown,
    packet_offset: u32 = 0,
    opcode: u16 = 0,
    predicated: bool = false,
    predicate_taken: bool = true,
    state_generation: u64 = 0,
    register_hash: u64 = 0,
    target_hash: u64 = 0,
    raster_hash: u64 = 0,
    shader_hash: u64 = 0,
    texture_hash: u64 = 0,
    vertex_hash: u64 = 0,
    index_hash: u64 = 0,
    memexport_hash: u64 = 0,
    input_digest: u64 = 0,

    pub fn valid(self: EntrySnapshot) bool {
        return self.identity.valid() and self.source != .unknown and
            self.state_generation != 0 and self.register_hash != 0 and
            self.input_digest != 0;
    }
};

/// Immutable post-classification facts. `packet_consumed` and
/// `draw_submitted` are deliberately independent fields.
pub const ExitSnapshot = struct {
    packet_consumed: bool = false,
    semantic_complete: bool = false,
    host_submitted: bool = false,
    visual_effect: bool = false,
    backend_id: u64 = 0,
    output_digest: u64 = 0,
    edram_digest: u64 = 0,
    resolve_digest: u64 = 0,
    guest_memory_digest: u64 = 0,
    visibility_barrier: u64 = 0,
    effect_mask: u64 = 0,
    effect_hash: u64 = 0,

    pub fn valid(self: ExitSnapshot) bool {
        if (!self.packet_consumed or !self.semantic_complete) return false;
        if (self.host_submitted and self.backend_id == 0) return false;
        if (self.visual_effect and self.output_digest == 0 and self.guest_memory_digest == 0) return false;
        return true;
    }
};

pub const Transaction = struct {
    identity: Identity = .{},
    entry: EntrySnapshot = .{},
    exit: ExitSnapshot = .{},
    draw_class: DrawClass = .unclassified,
    source: SourceClass = .unknown,
    stage_mask: u64 = 0,
    last_stage: ?Stage = null,
    tainted: bool = false,
    defect_count: u32 = 0,
    rejected_transitions: u32 = 0,
    completion_digest: u64 = 0,

    pub fn hasStage(self: Transaction, stage: Stage) bool {
        return (self.stage_mask & stageBit(stage)) != 0;
    }

    pub fn advance(self: *Transaction, stage: Stage, source: SourceClass, digest: u64) TransitionOutcome {
        if (!self.identity.valid()) return .invalid_identity;
        if (self.hasStage(stage)) {
            self.rejected_transitions +|= 1;
            return .duplicate;
        }
        if (source == .unknown) {
            self.rejected_transitions +|= 1;
            return .wrong_source;
        }
        if (!prerequisiteSatisfied(self.*, stage)) {
            self.rejected_transitions +|= 1;
            return .missing_prerequisite;
        }
        if (source != self.source) self.tainted = true;
        if (source == .synthetic or source == .replay or source == .diagnostic) self.tainted = true;
        self.stage_mask |= stageBit(stage);
        self.last_stage = stage;
        if (digest != 0) self.completion_digest = digest;
        return .accepted;
    }

    pub fn classify(self: *Transaction, class: DrawClass, exit: ExitSnapshot) TransitionOutcome {
        if (!self.hasStage(.draw_entry)) return .missing_prerequisite;
        if (self.hasStage(.draw_classified)) return .duplicate;
        if (!exit.valid()) {
            self.defect_count +|= 1;
            self.rejected_transitions +|= 1;
            return .incomplete_exit;
        }
        self.exit = exit;
        self.draw_class = class;
        if (class.defect()) self.defect_count +|= 1;
        return self.advance(.draw_classified, self.source, exit.effect_hash);
    }

    pub fn authenticReady(self: Transaction) bool {
        return self.identity.valid() and self.source == .guest_authentic and
            !self.tainted and self.defect_count == 0 and
            self.draw_class.candidateOutput() and self.exit.visual_effect and
            self.exit.visibility_barrier != 0 and self.hasStage(.guest_visible) and
            self.hasStage(.present_requested) and self.hasStage(.gpu_completed);
    }

    pub fn outputCandidate(self: Transaction) bool {
        return self.draw_class.candidateOutput() and self.hasStage(.draw_classified);
    }
};

pub const Ledger = struct {
    records: [max_transactions]Transaction = [_]Transaction{.{}} ** max_transactions,
    count: usize = 0,
    rejected: u64 = 0,

    pub fn begin(self: *Ledger, entry: EntrySnapshot) TransitionOutcome {
        if (!entry.valid()) {
            self.rejected +|= 1;
            return .incomplete_entry;
        }
        if (self.count >= max_transactions) {
            self.rejected +|= 1;
            return .full;
        }
        if (self.find(entry.identity) != null) {
            self.rejected +|= 1;
            return .duplicate;
        }
        self.records[self.count] = .{ .identity = entry.identity, .entry = entry, .source = entry.source };
        self.count += 1;
        return .accepted;
    }

    pub fn find(self: *Ledger, identity: Identity) ?*Transaction {
        for (self.records[0..self.count]) |*record| if (record.identity.eql(identity)) return record;
        return null;
    }

    pub fn authenticReadyCount(self: *const Ledger) usize {
        var total: usize = 0;
        for (self.records[0..self.count]) |record| {
            if (record.authenticReady()) total += 1;
        }
        return total;
    }
};

fn stageBit(stage: Stage) u64 {
    return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage)));
}

fn prerequisiteSatisfied(transaction: Transaction, stage: Stage) bool {
    return switch (stage) {
        .packet_consumed => true,
        .draw_entry => transaction.hasStage(.packet_consumed),
        .draw_classified => transaction.hasStage(.draw_entry),
        .draw_submitted => transaction.hasStage(.draw_classified) and
            transaction.exit.host_submitted and transaction.draw_class.candidateOutput(),
        .edram_written => transaction.hasStage(.draw_submitted) and transaction.exit.edram_digest != 0,
        .resolve_completed => (transaction.hasStage(.edram_written) or transaction.hasStage(.draw_submitted)) and transaction.exit.resolve_digest != 0,
        .guest_visible => (transaction.hasStage(.resolve_completed) or transaction.hasStage(.edram_written) or transaction.hasStage(.draw_classified)) and
            transaction.exit.visibility_barrier != 0 and (transaction.exit.output_digest != 0 or transaction.exit.guest_memory_digest != 0),
        .present_requested => transaction.hasStage(.guest_visible),
        .gpu_completed => transaction.hasStage(.present_requested),
        .display_observed => transaction.hasStage(.gpu_completed),
    };
}

fn makeEntry(identity: Identity, source: SourceClass) EntrySnapshot {
    return .{
        .identity = identity,
        .source = source,
        .state_generation = 1,
        .register_hash = 2,
        .input_digest = 3,
    };
}

test "a target-backed transaction requires semantic completion and visibility" {
    var ledger = Ledger{};
    const id = Identity{ .run_id = 1, .frame_serial = 2, .stream_epoch = 3, .ring_generation = 4, .batch_digest = 5 };
    try std.testing.expectEqual(TransitionOutcome.accepted, ledger.begin(makeEntry(id, .guest_authentic)));
    const transaction = ledger.find(id).?;
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.packet_consumed, .guest_authentic, 11));
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.draw_entry, .guest_authentic, 12));
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.classify(.target_backed, .{ .packet_consumed = true, .semantic_complete = true, .host_submitted = true, .visual_effect = true, .backend_id = 9, .output_digest = 10, .edram_digest = 11, .resolve_digest = 12, .guest_memory_digest = 13, .visibility_barrier = 14, .effect_hash = 15 }));
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.draw_submitted, .guest_authentic, 16));
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.edram_written, .guest_authentic, 17));
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.resolve_completed, .guest_authentic, 18));
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.guest_visible, .guest_authentic, 19));
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.present_requested, .guest_authentic, 20));
    try std.testing.expect(!transaction.authenticReady());
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.gpu_completed, .guest_authentic, 21));
    try std.testing.expect(transaction.authenticReady());
}

test "a consumed but dropped draw never earns output credit" {
    var transaction = Transaction{ .identity = .{ .run_id = 1, .frame_serial = 1, .stream_epoch = 1, .ring_generation = 1, .batch_digest = 1 }, .source = .guest_authentic };
    transaction.entry = makeEntry(transaction.identity, .guest_authentic);
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.packet_consumed, .guest_authentic, 1));
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.draw_entry, .guest_authentic, 2));
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.classify(.emulator_dropped, .{ .packet_consumed = true, .semantic_complete = true }));
    try std.testing.expect(!transaction.outputCandidate());
    try std.testing.expect(!transaction.authenticReady());
}

test "unknown draw classification is an explicit defect" {
    var transaction = Transaction{ .identity = .{ .run_id = 1, .frame_serial = 1, .stream_epoch = 1, .ring_generation = 1, .batch_digest = 1 }, .source = .guest_authentic };
    transaction.entry = makeEntry(transaction.identity, .guest_authentic);
    _ = transaction.advance(.packet_consumed, .guest_authentic, 1);
    _ = transaction.advance(.draw_entry, .guest_authentic, 2);
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.classify(.unclassified, .{ .packet_consumed = true, .semantic_complete = true }));
    try std.testing.expectEqual(@as(u32, 1), transaction.defect_count);
}

test "out-of-order semantic stages fail closed" {
    var transaction = Transaction{ .identity = .{ .run_id = 1, .frame_serial = 1, .stream_epoch = 1, .ring_generation = 1, .batch_digest = 1 }, .source = .guest_authentic };
    try std.testing.expectEqual(TransitionOutcome.missing_prerequisite, transaction.advance(.guest_visible, .guest_authentic, 1));
    try std.testing.expectEqual(TransitionOutcome.wrong_source, transaction.advance(.packet_consumed, .unknown, 1));
}

test "diagnostic or synthetic stage provenance taints a transaction" {
    var transaction = Transaction{ .identity = .{ .run_id = 1, .frame_serial = 1, .stream_epoch = 1, .ring_generation = 1, .batch_digest = 1 }, .source = .guest_authentic };
    try std.testing.expectEqual(TransitionOutcome.accepted, transaction.advance(.packet_consumed, .diagnostic, 1));
    try std.testing.expect(transaction.tainted);
}

test "entry and exit snapshots do not accept incomplete evidence" {
    try std.testing.expect(!(EntrySnapshot{ .identity = .{ .run_id = 1 } }).valid());
    try std.testing.expect(!(ExitSnapshot{ .packet_consumed = true, .semantic_complete = false }).valid());
    var ledger = Ledger{};
    try std.testing.expectEqual(TransitionOutcome.incomplete_entry, ledger.begin(.{ .identity = .{ .run_id = 1 } }));
}

// The backend-neutral custody contract lives with the Xenos frame transaction
// because both records describe one graphics publication chain.  The Xenos
// transaction above covers packet/draw semantics; these records cover the
// backend route, immutable PM4 views, native lifecycle, and capability state.
// Keeping both vocabularies in this module avoids a pass-specific contract
// file while retaining their deliberately different refusal rules.

pub const Truth = enum(u8) {
    observed,
    unsupported,
    unavailable,
    inferred,
    synthetic,
    unknown,

    pub fn authentic(self: Truth) bool {
        return self == .observed;
    }

    pub fn label(self: Truth) []const u8 {
        return switch (self) {
            .observed => "observed",
            .unsupported => "unsupported",
            .unavailable => "unavailable",
            .inferred => "inferred",
            .synthetic => "synthetic",
            .unknown => "unknown",
        };
    }
};

pub const Route = enum(u8) {
    vulkan,
    cocoa_metal,
    windows_d3d,
    unknown,

    pub fn label(self: Route) []const u8 {
        return switch (self) {
            .vulkan => "vulkan",
            .cocoa_metal => "cocoa-metal",
            .windows_d3d => "windows-d3d",
            .unknown => "unknown",
        };
    }
};

pub const Milestone = enum(u8) {
    guest_frame_intent,
    xenos_state,
    target_mutation,
    resolve_output,
    guest_swap_request,
    backend_submission,
    gpu_completion,
    vulkan_custody,
    drawable_custody,
    compositor_custody,
    display_custody,
    d3d_custody,
};

pub const milestone_count: usize = @typeInfo(Milestone).@"enum".fields.len;

fn required(milestone: Milestone, route: Route) bool {
    return switch (milestone) {
        .guest_frame_intent,
        .xenos_state,
        .target_mutation,
        .resolve_output,
        .guest_swap_request,
        .backend_submission,
        .gpu_completion,
        => route != .unknown,
        .vulkan_custody => route == .vulkan,
        .drawable_custody, .compositor_custody, .display_custody => route == .cocoa_metal,
        .d3d_custody => route == .windows_d3d,
    };
}

pub const FrameTransaction = struct {
    run_id: u64 = 0,
    frame_id: u64 = 0,
    route: Route = .unknown,
    source: SourceClass = .unknown,
    truths: [milestone_count]Truth = [_]Truth{.unknown} ** milestone_count,
    digests: [milestone_count]u64 = [_]u64{0} ** milestone_count,
    sealed: bool = false,

    pub fn init(run_id: u64, frame_id: u64, route: Route, source: SourceClass) FrameTransaction {
        return .{ .run_id = run_id, .frame_id = frame_id, .route = route, .source = source };
    }

    pub fn note(self: *FrameTransaction, milestone: Milestone, truth: Truth, digest: u64) bool {
        if (self.sealed or self.run_id == 0 or self.frame_id == 0 or self.route == .unknown) return false;
        self.truths[@intFromEnum(milestone)] = truth;
        self.digests[@intFromEnum(milestone)] = digest;
        return true;
    }

    pub fn seal(self: *FrameTransaction) bool {
        if (self.sealed) return false;
        self.sealed = true;
        return true;
    }

    pub fn firstMissing(self: *const FrameTransaction) ?Milestone {
        inline for (@typeInfo(Milestone).@"enum".fields) |field| {
            const milestone: Milestone = @enumFromInt(field.value);
            if (required(milestone, self.route)) {
                if (!self.truths[@intFromEnum(milestone)].authentic() or self.digests[@intFromEnum(milestone)] == 0) return milestone;
            }
        }
        return null;
    }

    pub fn authenticReady(self: *const FrameTransaction) bool {
        return self.sealed and self.source == .guest_authentic and self.firstMissing() == null;
    }

    pub fn semanticFingerprint(self: *const FrameTransaction) u64 {
        var fingerprint: u64 = 0xcbf2_9ce4_8422_2325;
        fingerprint = (fingerprint ^ self.run_id) *% 0x0100_0000_01B3;
        fingerprint = (fingerprint ^ self.frame_id) *% 0x0100_0000_01B3;
        fingerprint = (fingerprint ^ @intFromEnum(self.route)) *% 0x0100_0000_01B3;
        fingerprint = (fingerprint ^ @intFromEnum(self.source)) *% 0x0100_0000_01B3;
        for (self.truths, 0..) |truth, index| {
            fingerprint = (fingerprint ^ @intFromEnum(truth)) *% 0x0100_0000_01B3;
            fingerprint = (fingerprint ^ self.digests[index]) *% 0x0100_0000_01B3;
        }
        return if (fingerprint == 0) 1 else fingerprint;
    }
};

pub const BatchCapture = struct {
    pub const max_bytes: usize = 16 * 1024;
    run_id: u64 = 0,
    guest_start: u32 = 0,
    guest_end: u32 = 0,
    bytes: [max_bytes]u8 = [_]u8{0} ** max_bytes,
    length: usize = 0,
    digest: u64 = 0,
    generation: u64 = 0,
    sealed: bool = false,

    pub fn capture(self: *BatchCapture, run_id: u64, guest_start: u32, generation: u64, payload: []const u8) bool {
        if (self.sealed or run_id == 0 or generation == 0 or payload.len == 0 or payload.len > self.bytes.len) return false;
        self.* = .{ .run_id = run_id, .guest_start = guest_start, .guest_end = guest_start +| @as(u32, @intCast(payload.len)), .length = payload.len, .digest = hash(payload), .generation = generation };
        @memcpy(self.bytes[0..payload.len], payload);
        return true;
    }

    pub fn seal(self: *BatchCapture) bool {
        if (self.length == 0 or self.sealed) return false;
        self.sealed = true;
        return true;
    }

    pub fn exactBytes(self: *const BatchCapture) []const u8 {
        return self.bytes[0..self.length];
    }

    pub fn sameBytes(self: *const BatchCapture, other: *const BatchCapture) bool {
        return self.sealed and other.sealed and self.run_id == other.run_id and self.guest_start == other.guest_start and self.guest_end == other.guest_end and self.length == other.length and self.digest == other.digest and std.mem.eql(u8, self.exactBytes(), other.exactBytes());
    }
};

pub fn hash(bytes: []const u8) u64 {
    var value: u64 = 0xcbf2_9ce4_8422_2325;
    for (bytes) |byte| value = (value ^ byte) *% 0x0100_0000_01B3;
    return if (value == 0) 1 else value;
}

pub const BatchView = struct {
    structural: Truth = .unknown,
    supported: Truth = .unknown,
    stateful: Truth = .unknown,
    state_mutation: Truth = .unknown,
    draw_inputs: Truth = .unknown,
    host_work: Truth = .unknown,
    target_effect: Truth = .unknown,
    resolve_effect: Truth = .unknown,
    output_digest_before: u64 = 0,
    output_digest_after: u64 = 0,

    pub fn authenticReady(self: *const BatchView) bool {
        return self.structural.authentic() and self.supported.authentic() and self.stateful.authentic() and self.state_mutation.authentic() and self.draw_inputs.authentic() and self.host_work.authentic() and self.target_effect.authentic() and self.resolve_effect.authentic() and self.output_digest_before != 0 and self.output_digest_after != 0 and self.output_digest_before != self.output_digest_after;
    }
};

pub const max_batches: usize = 64;
pub const BatchLedger = struct {
    captures: [max_batches]BatchCapture = [_]BatchCapture{.{}} ** max_batches,
    views: [max_batches]BatchView = [_]BatchView{.{}} ** max_batches,
    count: usize = 0,
    rejected: u64 = 0,

    pub fn capture(self: *BatchLedger, run_id: u64, guest_start: u32, generation: u64, payload: []const u8) ?usize {
        if (self.count == self.captures.len) {
            self.rejected +|= 1;
            return null;
        }
        if (!self.captures[self.count].capture(run_id, guest_start, generation, payload)) {
            self.rejected +|= 1;
            return null;
        }
        const index = self.count;
        self.count += 1;
        return index;
    }

    pub fn sealCapture(self: *BatchLedger, index: usize) bool {
        if (index >= self.count) return false;
        return self.captures[index].seal();
    }

    pub fn noteView(self: *BatchLedger, index: usize, view: BatchView) bool {
        if (index >= self.count or !self.captures[index].sealed) return false;
        self.views[index] = view;
        return true;
    }

    pub fn appendCaptured(self: *BatchLedger, captured: BatchCapture) ?usize {
        if (self.count == self.captures.len or !captured.sealed or captured.run_id == 0 or captured.digest == 0) {
            self.rejected +|= 1;
            return null;
        }
        self.captures[self.count] = captured;
        self.count += 1;
        return self.count - 1;
    }

    pub fn consensusReady(self: *const BatchLedger, index: usize) bool {
        return index < self.count and self.captures[index].sealed and self.views[index].authenticReady();
    }
};

pub const DeviceState = enum(u8) { new, device_ready, queue_ready, frame_open, submitted, completed, failed };

pub const DeviceVerifier = struct {
    route: Route = .unknown,
    run_id: u64 = 0,
    device_id: u64 = 0,
    queue_id: u64 = 0,
    frame_id: u64 = 0,
    pipeline_id: u64 = 0,
    swapchain_id: u64 = 0,
    synchronization_id: u64 = 0,
    state: DeviceState = .new,
    unknown_failures: u64 = 0,

    pub fn beginDevice(self: *DeviceVerifier, run_id: u64, route: Route, device_id: u64) bool {
        if (self.state != .new or run_id == 0 or route == .unknown or device_id == 0) return false;
        self.* = .{ .route = route, .run_id = run_id, .device_id = device_id, .state = .device_ready };
        return true;
    }

    pub fn beginQueue(self: *DeviceVerifier, queue_id: u64) bool {
        if (self.state != .device_ready or queue_id == 0) return false;
        self.queue_id = queue_id;
        self.state = .queue_ready;
        return true;
    }

    pub fn beginFrame(self: *DeviceVerifier, frame_id: u64, pipeline_id: u64, swapchain_id: u64, synchronization_id: u64) bool {
        if (self.state != .queue_ready or frame_id == 0 or pipeline_id == 0 or synchronization_id == 0) return false;
        self.frame_id = frame_id;
        self.pipeline_id = pipeline_id;
        self.swapchain_id = swapchain_id;
        self.synchronization_id = synchronization_id;
        self.state = .frame_open;
        return true;
    }

    pub fn submit(self: *DeviceVerifier) bool {
        if (self.state != .frame_open or self.pipeline_id == 0 or self.synchronization_id == 0) return false;
        if (self.route == .vulkan and self.swapchain_id == 0) return false;
        self.state = .submitted;
        return true;
    }

    pub fn complete(self: *DeviceVerifier) bool {
        if (self.state != .submitted) return false;
        self.state = .completed;
        return true;
    }

    pub fn authenticReady(self: *const DeviceVerifier) bool {
        return self.state == .completed and self.route != .unknown and self.device_id != 0 and self.queue_id != 0 and self.frame_id != 0;
    }
};

pub const WindowState = enum(u8) { new, created, active, tearing_down, stopped, failed };

pub const NativeLifecycle = struct {
    state: WindowState = .new,
    run_generation: u64 = 0,
    window_generation: u64 = 0,
    main_thread: u64 = 0,
    queue_id: u64 = 0,
    drawable_id: u64 = 0,
    compositor_id: u64 = 0,
    display_id: u64 = 0,
    reentrancy: u64 = 0,
    off_main_calls: u64 = 0,

    pub fn begin(self: *NativeLifecycle, run_generation: u64, main_thread: u64, queue_id: u64) bool {
        if (self.state != .new or run_generation == 0 or main_thread == 0 or queue_id == 0) return false;
        self.* = .{ .state = .created, .run_generation = run_generation, .window_generation = 1, .main_thread = main_thread, .queue_id = queue_id };
        return true;
    }

    pub fn activate(self: *NativeLifecycle, drawable_id: u64) bool {
        if (self.state != .created or drawable_id == 0) return false;
        self.drawable_id = drawable_id;
        self.state = .active;
        return true;
    }

    pub fn noteCompositor(self: *NativeLifecycle, compositor_id: u64) bool {
        if (self.state != .active or compositor_id == 0) return false;
        self.compositor_id = compositor_id;
        return true;
    }

    pub fn noteDisplay(self: *NativeLifecycle, display_id: u64) bool {
        if (self.state != .active or self.compositor_id == 0 or display_id == 0) return false;
        self.display_id = display_id;
        return true;
    }

    pub fn beginTeardown(self: *NativeLifecycle) bool {
        if (self.state != .active and self.state != .created) return false;
        self.state = .tearing_down;
        return true;
    }

    pub fn finishTeardown(self: *NativeLifecycle) bool {
        if (self.state != .tearing_down) return false;
        self.state = .stopped;
        self.run_generation +|= 1;
        self.window_generation +|= 1;
        self.drawable_id = 0;
        self.compositor_id = 0;
        self.display_id = 0;
        return true;
    }

    pub fn authenticReady(self: *const NativeLifecycle) bool {
        return self.state == .active and self.drawable_id != 0 and self.compositor_id != 0 and self.display_id != 0 and self.off_main_calls == 0 and self.reentrancy == 0;
    }
};

pub const CapabilityStatus = enum(u8) { implemented_exercised, implemented_not_reached, semantic_incomplete, unsupported_blocked, unavailable_host, synthetic_only, unknown };

pub const Capability = struct {
    id: u64 = 0,
    owner: u64 = 0,
    backend: Route = .unknown,
    title_dependency: u64 = 0,
    test_vector: u64 = 0,
    evidence_domain: u64 = 0,
    status: CapabilityStatus = .unknown,
    required: bool = false,
};

pub const max_capabilities: usize = 256;
pub const CapabilityMatrix = struct {
    entries: [max_capabilities]Capability = [_]Capability{.{}} ** max_capabilities,
    count: usize = 0,
    duplicate_ids: u64 = 0,
    missing_vectors: u64 = 0,

    pub fn add(self: *CapabilityMatrix, capability: Capability) bool {
        if (self.count == self.entries.len or capability.id == 0) return false;
        for (self.entries[0..self.count]) |entry| {
            if (entry.id == capability.id) {
                self.duplicate_ids +|= 1;
                return false;
            }
        }
        self.entries[self.count] = capability;
        self.count += 1;
        if (capability.test_vector == 0) self.missing_vectors +|= 1;
        return true;
    }

    pub fn authenticReady(self: *const CapabilityMatrix) bool {
        if (self.count == 0 or self.duplicate_ids != 0 or self.missing_vectors != 0) return false;
        for (self.entries[0..self.count]) |entry| {
            if (entry.required and entry.status != .implemented_exercised and entry.status != .unsupported_blocked) return false;
            if (entry.status == .unknown) return false;
        }
        return true;
    }
};

test "Vulkan custody does not require Cocoa custody" {
    var transaction = FrameTransaction.init(1, 2, .vulkan, .guest_authentic);
    inline for (@typeInfo(Milestone).@"enum".fields) |field| {
        const milestone: Milestone = @enumFromInt(field.value);
        if (required(milestone, .vulkan)) {
            try std.testing.expect(transaction.note(milestone, .observed, @intFromEnum(milestone) + 1));
        }
    }
    try std.testing.expect(transaction.seal());
    try std.testing.expect(transaction.authenticReady());
    try std.testing.expect(transaction.firstMissing() == null);
}

test "diagnostic clear and incomplete Cocoa custody cannot earn frame credit" {
    var transaction = FrameTransaction.init(1, 2, .cocoa_metal, .diagnostic);
    try std.testing.expect(transaction.note(.guest_frame_intent, .synthetic, 1));
    try std.testing.expect(transaction.seal());
    try std.testing.expect(!transaction.authenticReady());
    try std.testing.expectEqual(Milestone.guest_frame_intent, transaction.firstMissing().?);
}

test "PM4 capture is immutable and independently comparable" {
    var first = BatchCapture{};
    var second = BatchCapture{};
    try std.testing.expect(first.capture(1, 0x1000, 1, "pm4 bytes"));
    try std.testing.expect(second.capture(1, 0x1000, 1, "pm4 bytes"));
    try std.testing.expect(first.seal());
    try std.testing.expect(second.seal());
    try std.testing.expect(first.sameBytes(&second));
    try std.testing.expect(!first.capture(1, 0x1000, 2, "changed"));
}

test "a PM4 view needs semantic output, not a draw counter" {
    var ledger = BatchLedger{};
    const index = ledger.capture(1, 0x2000, 1, "batch").?;
    try std.testing.expect(ledger.sealCapture(index));
    try std.testing.expect(!ledger.consensusReady(index));
    try std.testing.expect(ledger.noteView(index, .{ .structural = .observed, .supported = .observed, .stateful = .observed, .state_mutation = .observed, .draw_inputs = .observed, .host_work = .observed, .target_effect = .observed, .resolve_effect = .observed, .output_digest_before = 1, .output_digest_after = 2 }));
    try std.testing.expect(ledger.consensusReady(index));
}

test "device verification is per queue and per frame" {
    var verifier = DeviceVerifier{};
    try std.testing.expect(verifier.beginDevice(1, .vulkan, 10));
    try std.testing.expect(verifier.beginQueue(11));
    try std.testing.expect(verifier.beginFrame(12, 13, 14, 15));
    try std.testing.expect(verifier.submit());
    try std.testing.expect(verifier.complete());
    try std.testing.expect(verifier.authenticReady());
}

test "native lifecycle requires compositor and display custody and resets generations" {
    var lifecycle = NativeLifecycle{};
    try std.testing.expect(lifecycle.begin(1, 2, 3));
    try std.testing.expect(lifecycle.activate(4));
    try std.testing.expect(!lifecycle.authenticReady());
    try std.testing.expect(lifecycle.noteCompositor(5));
    try std.testing.expect(lifecycle.noteDisplay(6));
    try std.testing.expect(lifecycle.authenticReady());
    try std.testing.expect(lifecycle.beginTeardown());
    try std.testing.expect(lifecycle.finishTeardown());
    try std.testing.expectEqual(@as(u64, 2), lifecycle.run_generation);
}

test "capability matrix distinguishes blocked support from unknown" {
    var matrix = CapabilityMatrix{};
    try std.testing.expect(matrix.add(.{ .id = 1, .owner = 2, .backend = .vulkan, .title_dependency = 3, .test_vector = 4, .evidence_domain = 5, .status = .unsupported_blocked, .required = true }));
    try std.testing.expect(matrix.authenticReady());
    try std.testing.expect(!matrix.add(.{ .id = 1 }));
    try std.testing.expectEqual(@as(u64, 1), matrix.duplicate_ids);
}
