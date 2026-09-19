//! The final Rosette-owned contract for a frame that is actually on screen.
//!
//! The presentation chain answers whether Vulkan accepted a frame and whether
//! the host window can carry a drawable. That is necessary, but it is not
//! sufficient: a command can be attributed to an acquired image while the
//! image still contains one flat colour. This ledger is the last mile after
//! the presentation chain. It deliberately keeps transport, provenance,
//! readback and visibility as different facts so a successful API call never
//! becomes a false claim about pixels.
//!
//! This module has no Vulkan or AppKit dependency. The forwarder supplies a
//! snapshot, and this file evaluates it. Keeping the decision table pure
//! makes the hard boundary testable without a host window, driver, or guest.

const std = @import("std");

pub const stage_count: usize = 15;

/// A window with only a sliver on screen is technically visible to AppKit but
/// is not a useful presentation target. The native bridge repairs placement
/// to 100%; this lower bound keeps the pure contract honest if a user moves
/// the window between observations or the repair cannot complete immediately.
pub const minimum_visible_fraction_percent: u32 = 75;

pub const Status = enum(u8) {
    unknown,
    met,
    inferred,
    unmet,

    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .met => "met",
            .inferred => "inferred",
            .unmet => "unmet",
        };
    }

    pub fn satisfied(self: Status) bool {
        return self == .met or self == .inferred;
    }
};

/// The stage order is intentional. The first unmet stage is the repair
/// target; later stages are symptoms until it is fixed.
pub const Stage = enum(u8) {
    guest_present,
    acquired_image,
    render_target,
    content_write,
    content_provenance,
    drawable_extent,
    drawable_owner,
    gpu_submission,
    gpu_completion,
    present_acceptance,
    pixel_readback,
    pixel_detail,
    window_visibility,
    compositor_delivery,
    screen_valid,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .guest_present => "guest_present",
            .acquired_image => "acquired_image",
            .render_target => "render_target",
            .content_write => "content_write",
            .content_provenance => "content_provenance",
            .drawable_extent => "drawable_extent",
            .drawable_owner => "drawable_owner",
            .gpu_submission => "gpu_submission",
            .gpu_completion => "gpu_completion",
            .present_acceptance => "present_acceptance",
            .pixel_readback => "pixel_readback",
            .pixel_detail => "pixel_detail",
            .window_visibility => "window_visibility",
            .compositor_delivery => "compositor_delivery",
            .screen_valid => "screen_valid",
        };
    }

    pub fn owner(self: Stage) Owner {
        return switch (self) {
            .guest_present => .guest_title,
            .acquired_image, .render_target, .content_write, .content_provenance => .rosette_vulkan_bridge,
            .drawable_extent, .drawable_owner, .window_visibility => .rosette_window,
            .gpu_submission, .gpu_completion, .present_acceptance, .pixel_readback, .pixel_detail => .rosette_gpu,
            .compositor_delivery, .screen_valid => .rosette_compositor,
        };
    }

    pub fn action(self: Stage) []const u8 {
        return switch (self) {
            .guest_present => "wait for the guest to request a present; a missing request is upstream of the host window",
            .acquired_image => "trace acquire and present as a pair; a present without an acquired image cannot carry guest pixels",
            .render_target => "map the submitted command's image to the acquired swapchain image; offscreen or unknown targets are not proof",
            .content_write => "inspect command recording and image layout transitions; the acquired image was presented without a content write",
            .content_provenance => "resolve the sampled image, transfer source, or buffer upload that feeds the acquired image; direct command evidence is only an inference",
            .drawable_extent => "make the swapchain extent, CAMetalLayer drawableSize, and layer bounds agree before creating or using the swapchain",
            .drawable_owner => "leave one owner in charge of the CAMetalLayer drawable pool and retire any competing swapchain",
            .gpu_submission => "verify the guest command reaches a real queue submission; a modeled command is not GPU work",
            .gpu_completion => "correlate every accepted present with a real queue completion; investigate the oldest outstanding request",
            .present_acceptance => "inspect the real vkQueuePresentKHR result and the refusal ledger; an accepted guest present must reach the native WSI",
            .pixel_readback => "enable the bounded swapchain readback and repair its staging/layout path if it cannot complete",
            .pixel_detail => "the acquired image read back as a fill or uniform colour; inspect shader output, descriptor/image provenance, and layout before blaming AppKit",
            .window_visibility => "repair the first host-window link named by HOST WINDOW BREAK, or move the visible window onto a screen",
            .compositor_delivery => "compare drawable ownership and completion with the visible window; a completed frame still needs one compositor path",
            .screen_valid => "repair the first unmet stage above; screen_valid is a summary, not an independent cause",
        };
    }
};

pub const Owner = enum(u8) {
    guest_title,
    xenia_gpu_thread,
    rosette_vulkan_bridge,
    rosette_window,
    rosette_gpu,
    rosette_compositor,
    unknown,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .guest_title => "guest-title",
            .xenia_gpu_thread => "xenia:gpu-thread",
            .rosette_vulkan_bridge => "rosette:vulkan-bridge",
            .rosette_window => "rosette:window",
            .rosette_gpu => "rosette:gpu",
            .rosette_compositor => "rosette:compositor",
            .unknown => "unknown",
        };
    }
};

pub const DrawableOwner = enum(u8) {
    unknown,
    window_bridge,
    native_presenter,
    guest_swapchain,

    pub fn label(self: DrawableOwner) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .window_bridge => "window_bridge",
            .native_presenter => "native_presenter",
            .guest_swapchain => "guest_swapchain",
        };
    }
};

pub const PixelEvidence = enum(u8) {
    unknown,
    unavailable,
    solid_clear,
    uniform_colour,
    nonzero_static,
    changing,

    pub fn label(self: PixelEvidence) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .unavailable => "unavailable",
            .solid_clear => "solid_clear",
            .uniform_colour => "uniform_colour",
            .nonzero_static => "nonzero_static",
            .changing => "changing",
        };
    }

    pub fn showsDetail(self: PixelEvidence) bool {
        return self == .nonzero_static or self == .changing;
    }

    pub fn isUniform(self: PixelEvidence) bool {
        return self == .solid_clear or self == .uniform_colour;
    }
};

/// One observation copied from Rosette's bounded Vulkan and AppKit ledgers.
/// All counters are intentionally monotonic for the lifetime of a run.
pub const Snapshot = struct {
    step: u64 = 0,

    guest_presents: u64 = 0,
    guest_acquires: u64 = 0,
    guest_present_failures: u64 = 0,
    presents_with_target: u64 = 0,
    presents_with_content: u64 = 0,
    presents_clear_only: u64 = 0,
    presents_without_target: u64 = 0,
    presents_without_write: u64 = 0,
    presents_with_sampled_source: u64 = 0,
    presents_with_propagated_transfer: u64 = 0,
    presents_with_buffer_upload: u64 = 0,
    presents_with_unresolved_source: u64 = 0,

    content_commands: u64 = 0,
    draw_commands: u64 = 0,
    dispatch_commands: u64 = 0,
    target_resolved: u64 = 0,
    target_offscreen: u64 = 0,
    target_unknown: u64 = 0,
    target_overflow: u64 = 0,

    descriptor_image_infos: u64 = 0,
    descriptor_sampled_images: u64 = 0,
    descriptor_unknown_image_views: u64 = 0,
    descriptor_sets_unknown: u64 = 0,
    resource_transfer_events: u64 = 0,
    resource_buffer_to_image: u64 = 0,
    resource_transfer_sources_resolved: u64 = 0,
    resource_transfer_sources_unresolved: u64 = 0,
    resource_graph_overflow: u64 = 0,

    native_present_requests: u64 = 0,
    native_present_completions: u64 = 0,
    native_queue_submits: u64 = 0,

    expected_width: u32 = 0,
    expected_height: u32 = 0,
    drawable_width: u32 = 0,
    drawable_height: u32 = 0,
    layer_width: u32 = 0,
    layer_height: u32 = 0,
    extent_observed: bool = false,
    extent_contract_failed: bool = false,

    drawable_owner: DrawableOwner = .unknown,
    live_swapchains: u32 = 0,
    contested_layer: bool = false,

    pixel_probe_attempts: u64 = 0,
    pixel_probe_successes: u64 = 0,
    pixel_probe_failures: u64 = 0,
    pixel_evidence: PixelEvidence = .unknown,
    pixel_uniform_value: u32 = 0,
    pixel_hash: u64 = 0,
    /// Identity of the probe selected for the screen verdict. When content
    /// has been observed, the forwarder prefers the newest content-backed
    /// sample over a newer clear-only sample.
    pixel_sample_frame: u64 = 0,
    pixel_sample_image: u64 = 0,
    pixel_sample_was_content: bool = false,

    window_available: bool = false,
    window_chain_intact: bool = false,
    window_user_visible: bool = false,
    window_visible_fraction_percent: u32 = 0,
    window_break_reason: []const u8 = "",
};

pub const StageRecord = struct {
    stage: Stage = .guest_present,
    status: Status = .unknown,
    owner: Owner = .unknown,
    evidence: []const u8 = "not observed",
    action: []const u8 = "collect more evidence",
};

pub const Verdict = enum(u8) {
    not_started,
    transport_only,
    uniform_pixels,
    blocked,
    inconclusive,
    valid_on_screen,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .not_started => "not_started",
            .transport_only => "transport_only",
            .uniform_pixels => "uniform_pixels",
            .blocked => "blocked",
            .inconclusive => "inconclusive",
            .valid_on_screen => "valid_on_screen",
        };
    }

    pub fn action(self: Verdict) []const u8 {
        return switch (self) {
            .not_started => "the screen contract is waiting for a guest frame; do not diagnose the compositor before a present exists",
            .transport_only => "transport completed without usable pixel detail; keep the readback and provenance evidence enabled",
            .uniform_pixels => "transport completed but the readback is uniform; repair the first pixel/provenance stage rather than the window geometry",
            .blocked => "repair the first unmet stage; later stages cannot become valid until that boundary is satisfied",
            .inconclusive => "collect another complete snapshot; the available counters do not yet establish a transport or pixel verdict",
            .valid_on_screen => "all Rosette-owned screen stages are satisfied, including detailed pixel readback and visible-window delivery",
        };
    }
};

pub const Evaluation = struct {
    records: [stage_count]StageRecord = [_]StageRecord{.{}} ** stage_count,
    verdict: Verdict = .not_started,
    first_blocking: ?Stage = null,

    pub fn record(self: Evaluation, stage: Stage) StageRecord {
        return self.records[@intFromEnum(stage)];
    }

    pub fn satisfiedCount(self: Evaluation) usize {
        var count: usize = 0;
        for (self.records) |entry| {
            if (entry.status.satisfied()) count += 1;
        }
        return count;
    }

    pub fn metCount(self: Evaluation) usize {
        var count: usize = 0;
        for (self.records) |entry| {
            if (entry.status == .met) count += 1;
        }
        return count;
    }

    pub fn inferredCount(self: Evaluation) usize {
        var count: usize = 0;
        for (self.records) |entry| {
            if (entry.status == .inferred) count += 1;
        }
        return count;
    }

    pub fn unmetCount(self: Evaluation) usize {
        var count: usize = 0;
        for (self.records) |entry| {
            if (entry.status == .unmet) count += 1;
        }
        return count;
    }

    pub fn unknownCount(self: Evaluation) usize {
        var count: usize = 0;
        for (self.records) |entry| {
            if (entry.status == .unknown) count += 1;
        }
        return count;
    }

    pub fn action(self: Evaluation) []const u8 {
        if (self.first_blocking) |stage| return self.record(stage).action;
        return self.verdict.action();
    }
};

fn put(records: *[stage_count]StageRecord, stage: Stage, status: Status, evidence: []const u8) void {
    records[@intFromEnum(stage)] = .{
        .stage = stage,
        .status = status,
        .owner = stage.owner(),
        .evidence = evidence,
        .action = stage.action(),
    };
}

fn outputSeen(snapshot: Snapshot) bool {
    return snapshot.guest_presents != 0 or
        snapshot.native_present_requests != 0 or
        snapshot.pixel_probe_successes != 0;
}

fn extentMatches(snapshot: Snapshot) bool {
    if (!snapshot.extent_observed) return false;
    if (snapshot.expected_width == 0 or snapshot.expected_height == 0) return false;
    return snapshot.expected_width == snapshot.drawable_width and
        snapshot.expected_height == snapshot.drawable_height and
        snapshot.expected_width == snapshot.layer_width and
        snapshot.expected_height == snapshot.layer_height;
}

pub fn evaluate(snapshot: Snapshot) Evaluation {
    var result = Evaluation{};
    const output = outputSeen(snapshot);
    const accepted = snapshot.native_present_requests != 0;
    const completed = accepted and snapshot.native_present_completions >= snapshot.native_present_requests;
    const explicit_source_presents = snapshot.presents_with_sampled_source +|
        snapshot.presents_with_propagated_transfer +|
        snapshot.presents_with_buffer_upload;

    put(&result.records, .guest_present, if (snapshot.guest_presents != 0) .met else .unknown, if (snapshot.guest_presents != 0) "a guest present was observed" else "no guest present has been observed");
    put(&result.records, .acquired_image, if (snapshot.guest_acquires != 0) .met else if (snapshot.guest_presents != 0) .unmet else .unknown, if (snapshot.guest_acquires != 0) "a guest swapchain image was acquired" else "present traffic has no corresponding acquire");
    put(&result.records, .render_target, if (snapshot.presents_with_target != 0) .met else if (output) .unmet else .unknown, if (snapshot.presents_with_target != 0) "the acquired image was targeted before present" else "no presented acquired image has a resolved target");
    put(&result.records, .content_write, if (snapshot.presents_with_content != 0) .met else if (output) .unmet else .unknown, if (snapshot.presents_with_content != 0) "a content write reached an acquired image" else "no content write reached an acquired presented image");

    const provenance_status: Status = if (snapshot.presents_with_content == 0)
        .unknown
    else if (explicit_source_presents != 0)
        .met
    else if (snapshot.content_commands != 0)
        .inferred
    else if (snapshot.presents_with_unresolved_source != 0)
        .unmet
    else
        .unknown;
    put(&result.records, .content_provenance, provenance_status, switch (provenance_status) {
        .met => "a sampled image, propagated image, or buffer upload was attached to a presented frame",
        .inferred => "content commands reached the acquired image, but no explicit source route was resolved",
        .unmet => "the only recorded source route is unresolved",
        .unknown => "no presented content source route is observable",
    });

    const extent_status: Status = if (snapshot.extent_contract_failed)
        .unmet
    else if (extentMatches(snapshot))
        .met
    else if (snapshot.expected_width != 0 and snapshot.expected_height != 0 and snapshot.extent_observed)
        .unmet
    else
        .unknown;
    put(&result.records, .drawable_extent, extent_status, switch (extent_status) {
        .met => "swapchain, drawable, and layer dimensions agree",
        .unmet => "the required extent contract failed or dimensions disagree",
        .unknown => "the expected and observed drawable extents are incomplete",
        .inferred => "extent was inferred",
    });

    const owner_status: Status = if (!output)
        .unknown
    else if (snapshot.contested_layer)
        .unmet
    else if (snapshot.drawable_owner == .guest_swapchain)
        .met
    else
        .unmet;
    put(&result.records, .drawable_owner, owner_status, switch (owner_status) {
        .met => "the guest swapchain owns the drawable pool",
        .unmet => "the drawable is contested or owned by another Rosette path",
        .unknown => "no presented drawable owner is observable",
        .inferred => "drawable ownership was inferred",
    });

    put(&result.records, .gpu_submission, if (snapshot.native_queue_submits != 0) .met else if (output) .unmet else .unknown, if (snapshot.native_queue_submits != 0) "real queue submission traffic was observed" else "no real queue submission is observable");
    const completion_status: Status = if (!accepted)
        if (output) .unmet else .unknown
    else if (completed)
        .met
    else
        .unmet;
    put(&result.records, .gpu_completion, completion_status, switch (completion_status) {
        .met => "every observed native present request has a queue completion",
        .unmet => "a native present request has no matching queue completion",
        .unknown => "no native present completion is observable",
        .inferred => "completion was inferred",
    });
    put(&result.records, .present_acceptance, if (accepted) .met else if (output) .unmet else .unknown, if (accepted) "the native WSI accepted a present request" else "no native present request is observable");

    const readback_status: Status = if (snapshot.pixel_probe_successes != 0)
        .met
    else if (snapshot.pixel_probe_attempts != 0)
        .unmet
    else
        .unknown;
    put(&result.records, .pixel_readback, readback_status, switch (readback_status) {
        .met => "a bounded swapchain readback completed",
        .unmet => "readback attempts occurred without a successful sample",
        .unknown => "no pixel readback has completed",
        .inferred => "readback was inferred",
    });
    const detail_status: Status = switch (snapshot.pixel_evidence) {
        .nonzero_static, .changing => .met,
        .solid_clear, .uniform_colour => if (snapshot.pixel_sample_was_content)
            .unmet
        else if (snapshot.presents_with_content != 0)
            .unknown
        else
            .unmet,
        .unknown, .unavailable => .unknown,
    };
    put(&result.records, .pixel_detail, detail_status, switch (detail_status) {
        .met => "readback contains more than one colour",
        .unmet => "the content-backed acquired image read back as a solid clear or uniform colour",
        .unknown => if (snapshot.pixel_evidence.isUniform() and snapshot.presents_with_content != 0 and !snapshot.pixel_sample_was_content)
            "the latest uniform sample predates the content-backed present; a content-frame readback is required"
        else
            "readback does not establish pixel detail",
        .inferred => "pixel detail was inferred",
    });

    const window_status: Status = if (!snapshot.window_available)
        .unknown
    else if (snapshot.window_chain_intact and snapshot.window_user_visible and snapshot.window_visible_fraction_percent >= minimum_visible_fraction_percent)
        .met
    else
        .unmet;
    put(&result.records, .window_visibility, window_status, switch (window_status) {
        .met => "AppKit reports an intact, visible, on-screen window chain",
        .unmet => if (snapshot.window_break_reason.len != 0)
            snapshot.window_break_reason
        else if (snapshot.window_visible_fraction_percent < minimum_visible_fraction_percent)
            "the window is visible but less than 75% of its frame is inside the screen's visible area"
        else
            "the window is not user-visible",
        .unknown => "host window facts are unavailable",
        .inferred => "window visibility was inferred",
    });

    const window_intact = result.record(.window_visibility).status.satisfied();
    const compositor_status: Status = if (accepted and completed and window_intact)
        .inferred
    else if (accepted and completed and snapshot.window_available)
        .unmet
    else
        .unknown;
    put(&result.records, .compositor_delivery, compositor_status, switch (compositor_status) {
        .inferred => "native completion and an intact visible window imply compositor delivery; no private compositor API is required",
        .unmet => "GPU completion exists, but the visible window chain cannot receive it",
        .unknown => "compositor delivery cannot be inferred yet",
        .met => "compositor delivery was directly observed",
    });

    var all_prior_satisfied = true;
    var any_prior_unmet = false;
    for (result.records[0..@intFromEnum(Stage.screen_valid)]) |entry| {
        all_prior_satisfied = all_prior_satisfied and entry.status.satisfied();
        any_prior_unmet = any_prior_unmet or entry.status == .unmet;
    }
    const screen_status: Status = if (all_prior_satisfied) .met else if (any_prior_unmet) .unmet else .unknown;
    put(&result.records, .screen_valid, screen_status, switch (screen_status) {
        .met => "all Rosette-owned transport, pixel, extent, ownership, and visibility stages are satisfied",
        .unmet => "one or more earlier screen stages is unmet",
        .unknown => "one or more earlier screen stages is not observable",
        .inferred => "screen validity was inferred",
    });

    for (result.records[0..@intFromEnum(Stage.screen_valid)]) |entry| {
        if (entry.status == .unmet) {
            result.first_blocking = entry.stage;
            break;
        }
    }
    if (result.first_blocking == null) {
        for (result.records[0..@intFromEnum(Stage.screen_valid)]) |entry| {
            if (entry.status == .unknown) {
                result.first_blocking = entry.stage;
                break;
            }
        }
    }

    result.verdict = if (!output)
        .not_started
    else if (screen_status.satisfied())
        .valid_on_screen
    else if (snapshot.pixel_evidence.isUniform() and
        (snapshot.pixel_sample_was_content or snapshot.presents_with_content == 0))
        .uniform_pixels
    else if (result.unmetCount() != 0)
        .blocked
    else if (accepted or snapshot.guest_presents != 0)
        .transport_only
    else
        .inconclusive;
    return result;
}

/// A small change-aware wrapper around the pure evaluation. It does not
/// retain a history or allocate: it only remembers the last snapshot and the
/// last report boundary, which is enough to keep a periodic run log useful.
pub const Ledger = struct {
    current: Evaluation = .{},
    last_snapshot: Snapshot = .{},
    observed: bool = false,
    changed_since_report: bool = false,
    /// Pixel/sample identity is progress, not a changed platform contract.
    /// Keep it available to verbose consumers without making every readback
    /// repeat the complete stage inventory in a normal run.
    semantic_changed_since_report: bool = false,
    observations: u64 = 0,
    transitions: u64 = 0,

    pub fn observe(self: *Ledger, observation: Snapshot) Evaluation {
        const next = evaluate(observation);
        var changed = !self.observed;
        var semantic_changed = !self.observed;
        if (self.observed) {
            if (next.verdict != self.current.verdict or next.first_blocking != self.current.first_blocking) semantic_changed = true;
            for (next.records, self.current.records) |new_record, old_record| {
                if (new_record.status != old_record.status or new_record.owner != old_record.owner) {
                    semantic_changed = true;
                    self.transitions +|= 1;
                }
            }
            if ((observation.pixel_evidence != self.last_snapshot.pixel_evidence and
                !(observation.pixel_evidence.showsDetail() and self.last_snapshot.pixel_evidence.showsDetail())) or
                observation.pixel_sample_was_content != self.last_snapshot.pixel_sample_was_content or
                observation.drawable_owner != self.last_snapshot.drawable_owner or
                observation.contested_layer != self.last_snapshot.contested_layer or
                observation.expected_width != self.last_snapshot.expected_width or
                observation.expected_height != self.last_snapshot.expected_height or
                observation.drawable_width != self.last_snapshot.drawable_width or
                observation.drawable_height != self.last_snapshot.drawable_height or
                observation.window_user_visible != self.last_snapshot.window_user_visible or
                observation.window_visible_fraction_percent != self.last_snapshot.window_visible_fraction_percent)
            {
                semantic_changed = true;
            }
            changed = observation.pixel_evidence != self.last_snapshot.pixel_evidence or
                observation.pixel_hash != self.last_snapshot.pixel_hash or
                observation.pixel_sample_frame != self.last_snapshot.pixel_sample_frame or
                observation.pixel_sample_image != self.last_snapshot.pixel_sample_image;
        } else {
            self.transitions = 0;
        }
        self.current = next;
        self.last_snapshot = observation;
        self.observed = true;
        self.changed_since_report = self.changed_since_report or changed or semantic_changed;
        self.semantic_changed_since_report = self.semantic_changed_since_report or semantic_changed;
        self.observations +|= 1;
        return next;
    }

    pub fn changedSinceReport(self: *const Ledger) bool {
        return self.changed_since_report;
    }

    pub fn markReported(self: *Ledger) void {
        self.changed_since_report = false;
        self.semantic_changed_since_report = false;
    }

    pub fn semanticChangedSinceReport(self: *const Ledger) bool {
        return self.semantic_changed_since_report;
    }

    pub fn wasObserved(self: *const Ledger) bool {
        return self.observed;
    }

    pub fn evaluation(self: *const Ledger) Evaluation {
        return self.current;
    }

    pub fn snapshot(self: *const Ledger) Snapshot {
        return self.last_snapshot;
    }
};

test "screen validity separates a uniform frame from a valid detailed frame" {
    const base = Snapshot{
        .guest_presents = 6,
        .guest_acquires = 6,
        .presents_with_target = 6,
        .presents_with_content = 1,
        .content_commands = 586,
        .native_present_requests = 5,
        .native_present_completions = 5,
        .native_queue_submits = 11,
        .expected_width = 1280,
        .expected_height = 720,
        .drawable_width = 1280,
        .drawable_height = 720,
        .layer_width = 1280,
        .layer_height = 720,
        .extent_observed = true,
        .drawable_owner = .guest_swapchain,
        .pixel_probe_attempts = 4,
        .pixel_probe_successes = 4,
        .pixel_evidence = .uniform_colour,
        .pixel_sample_frame = 6,
        .pixel_sample_was_content = true,
        .window_available = true,
        .window_chain_intact = true,
        .window_user_visible = true,
        .window_visible_fraction_percent = 100,
    };
    const uniform = evaluate(base);
    try std.testing.expectEqual(Verdict.uniform_pixels, uniform.verdict);
    try std.testing.expectEqual(Stage.pixel_detail, uniform.first_blocking.?);
    try std.testing.expectEqual(Status.unmet, uniform.record(.pixel_detail).status);
    try std.testing.expectEqual(Status.inferred, uniform.record(.content_provenance).status);

    var stale = base;
    stale.pixel_sample_was_content = false;
    const stale_eval = evaluate(stale);
    try std.testing.expectEqual(Verdict.transport_only, stale_eval.verdict);
    try std.testing.expectEqual(Status.unknown, stale_eval.record(.pixel_detail).status);
    try std.testing.expectEqual(Stage.pixel_detail, stale_eval.first_blocking.?);

    var detailed_snapshot = base;
    detailed_snapshot.pixel_evidence = .changing;
    const detailed = evaluate(detailed_snapshot);
    try std.testing.expectEqual(Verdict.valid_on_screen, detailed.verdict);
    try std.testing.expectEqual(Status.met, detailed.record(.screen_valid).status);
    try std.testing.expectEqual(@as(usize, stage_count), detailed.satisfiedCount());
}

test "the first hard boundary is the extent or provenance gap" {
    var extent = Snapshot{
        .guest_presents = 1,
        .guest_acquires = 1,
        .presents_with_target = 1,
        .presents_with_content = 1,
        .content_commands = 1,
        .native_present_requests = 1,
        .native_present_completions = 1,
        .native_queue_submits = 1,
        .expected_width = 1280,
        .expected_height = 720,
        .drawable_width = 2560,
        .drawable_height = 1440,
        .layer_width = 2560,
        .layer_height = 1440,
        .extent_observed = true,
        .drawable_owner = .guest_swapchain,
        .pixel_probe_successes = 1,
        .pixel_probe_attempts = 1,
        .pixel_evidence = .changing,
        .window_available = true,
        .window_chain_intact = true,
        .window_user_visible = true,
        .window_visible_fraction_percent = 100,
    };
    const extent_eval = evaluate(extent);
    try std.testing.expectEqual(Stage.drawable_extent, extent_eval.first_blocking.?);

    extent.drawable_width = 1280;
    extent.drawable_height = 720;
    extent.layer_width = 1280;
    extent.layer_height = 720;
    extent.content_commands = 0;
    extent.presents_with_unresolved_source = 1;
    const provenance_eval = evaluate(extent);
    try std.testing.expectEqual(Stage.content_provenance, provenance_eval.first_blocking.?);
    try std.testing.expectEqual(Status.unmet, provenance_eval.record(.content_provenance).status);
}

test "a mostly off-screen window is not screen-valid even when its chain is intact" {
    const detailed = Snapshot{
        .guest_presents = 1,
        .guest_acquires = 1,
        .presents_with_target = 1,
        .presents_with_content = 1,
        .content_commands = 1,
        .native_present_requests = 1,
        .native_present_completions = 1,
        .native_queue_submits = 1,
        .expected_width = 1280,
        .expected_height = 720,
        .drawable_width = 1280,
        .drawable_height = 720,
        .layer_width = 1280,
        .layer_height = 720,
        .extent_observed = true,
        .drawable_owner = .guest_swapchain,
        .pixel_probe_attempts = 1,
        .pixel_probe_successes = 1,
        .pixel_evidence = .changing,
        .pixel_sample_frame = 1,
        .pixel_sample_was_content = true,
        .window_available = true,
        .window_chain_intact = true,
        .window_user_visible = true,
        .window_visible_fraction_percent = 14,
    };
    const evaluation = evaluate(detailed);
    try std.testing.expectEqual(Status.unmet, evaluation.record(.window_visibility).status);
    try std.testing.expectEqual(Stage.window_visibility, evaluation.first_blocking.?);
    try std.testing.expectEqual(Verdict.blocked, evaluation.verdict);
}

test "the ledger only reports meaningful state changes" {
    var ledger = Ledger{};
    const first = Snapshot{ .guest_presents = 1, .guest_acquires = 1 };
    _ = ledger.observe(first);
    try std.testing.expect(ledger.changedSinceReport());
    ledger.markReported();
    try std.testing.expect(!ledger.changedSinceReport());

    _ = ledger.observe(first);
    try std.testing.expect(!ledger.changedSinceReport());

    var second = first;
    second.pixel_evidence = .uniform_colour;
    _ = ledger.observe(second);
    try std.testing.expect(ledger.changedSinceReport());
    try std.testing.expect(ledger.observations == 3);
}

test "new frame hashes and acquired images do not repeat the screen contract" {
    var ledger = Ledger{};
    var sample = Snapshot{ .guest_presents = 1, .guest_acquires = 1, .pixel_evidence = .uniform_colour };
    _ = ledger.observe(sample);
    ledger.markReported();
    for (2..514) |frame| {
        sample.guest_presents = frame;
        sample.guest_acquires = frame;
        sample.pixel_hash = frame;
        sample.pixel_sample_frame = frame;
        sample.pixel_sample_image = frame % 3;
        _ = ledger.observe(sample);
        try std.testing.expect(ledger.changedSinceReport());
        try std.testing.expect(!ledger.semanticChangedSinceReport());
        ledger.markReported();
    }
    sample.pixel_evidence = .changing;
    _ = ledger.observe(sample);
    try std.testing.expect(ledger.semanticChangedSinceReport());
    ledger.markReported();
    sample.window_user_visible = true;
    _ = ledger.observe(sample);
    try std.testing.expect(ledger.semanticChangedSinceReport());
}

test "static versus changing detailed pixels is progress, not a new health verdict" {
    var ledger = Ledger{};
    var sample = Snapshot{ .pixel_evidence = .nonzero_static };
    _ = ledger.observe(sample);
    ledger.markReported();
    sample.pixel_evidence = .changing;
    _ = ledger.observe(sample);
    try std.testing.expect(!ledger.semanticChangedSinceReport());
    sample.pixel_evidence = .unavailable;
    _ = ledger.observe(sample);
    try std.testing.expect(ledger.semanticChangedSinceReport());
}

comptime {
    if (@typeInfo(Stage).@"enum".fields.len != stage_count) {
        @compileError("screen validity stage_count must match Stage");
    }
}
