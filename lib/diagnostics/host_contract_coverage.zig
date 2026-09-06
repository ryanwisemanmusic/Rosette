//! How much of what the emulator needs from this host actually works.
//!
//! Every other diagnostic in this runtime is a microscope. They are good
//! microscopes — they found a spliced object identity, a codegen failure that
//! killed a run four thousand steps later, an ordering inversion no ladder
//! could see — and not one of them can answer the question that actually
//! matters after three weeks: *how far along is this?*
//!
//! That question has no answer today because nothing enumerates the surface. A
//! run reports the frontier of one ladder, the blocker of one subsystem, the
//! worst object in one table. Each is a statement about the thing that
//! subsystem happens to watch, and none of them is a statement about the whole.
//! So an operator fixes a blocker, the frontier moves one rung, and the next
//! blocker is somewhere nobody was looking — which feels exactly like a fishing
//! expedition because it is one.
//!
//! This is the other instrument. It enumerates the capability surface a
//! translated emulator needs from its host, scores each capability, and reports
//! a single number plus the weakest layer. The number is not precise and does
//! not need to be: its job is to say whether the next hour belongs to
//! threading, to the kernel surface or to presentation, and to say whether last
//! week's work moved anything.
//!
//! ## Why weights, and why they are coarse
//!
//! A missing presentation path and a missing locale query are both "one
//! unsatisfied capability" and they are not equally far from a frame. Weights
//! encode that, in three steps only — a capability is on the critical path, on
//! a supporting path, or a convenience. Finer weights would imply a precision
//! the model does not have and would invite tuning the number instead of the
//! system.
//!
//! ## Degraded is its own state
//!
//! The most dangerous capability is one that answers every call successfully
//! and does nothing. A modelled graphics queue accepts every submission and
//! returns success, and every counter above it reads healthy. `degraded` exists
//! so that surface is scored as what it is: present, callable, and not doing
//! the job. Counting it as satisfied is how a stack reports ninety percent
//! coverage and shows a blue screen.

const std = @import("std");
const observation_contract = @import("xenia_gpu_observation_contract");

pub const GuestOutputEvidence = observation_contract.GuestOutputEvidence;

/// The layer a capability belongs to. Reported separately because "the run is
/// at sixty percent" says nothing actionable and "threading is complete and
/// presentation is at ten percent" says where to go.
pub const Layer = enum(u8) {
    /// Memory mapping, protection, address-space translation.
    memory,
    /// Threads, scheduling, synchronisation primitives.
    threading,
    /// Files, devices, the content the title reads.
    storage,
    /// Kernel exports and the platform state a title reads before it runs.
    kernel_surface,
    /// The emulator's GPU bring-up: engines, ring, callbacks, command flow.
    gpu_bringup,
    /// Turning rendered output into pixels on a window.
    presentation,
    /// Everything else the host provides: locale, time, entropy.
    platform_services,

    pub fn label(self: Layer) []const u8 {
        return switch (self) {
            .memory => "memory",
            .threading => "threading",
            .storage => "storage",
            .kernel_surface => "kernel_surface",
            .gpu_bringup => "gpu_bringup",
            .presentation => "presentation",
            .platform_services => "platform_services",
        };
    }
};

pub const layer_count = @typeInfo(Layer).@"enum".fields.len;

/// How far a capability is from a frame. Three steps on purpose: finer weights
/// imply a precision this model does not have.
pub const Weight = enum(u8) {
    /// No frame is possible without it.
    critical = 5,
    /// A frame is possible and degraded, or the path is longer.
    supporting = 2,
    /// Absence is a nuisance.
    convenience = 1,

    pub fn value(self: Weight) u32 {
        return @intFromEnum(self);
    }

    pub fn label(self: Weight) []const u8 {
        return switch (self) {
            .critical => "critical",
            .supporting => "supporting",
            .convenience => "convenience",
        };
    }
};

pub const Status = enum(u8) {
    /// Nothing has exercised it, so nothing is known. Scored as zero and
    /// reported separately from a known failure — "we never tested this" and
    /// "this is broken" are different amounts of bad news.
    untested = 0,
    /// Exercised and does not work.
    unsatisfied = 1,
    /// Answers every call and does not do the job. The most dangerous state in
    /// the model, and the reason the model has more than a boolean.
    degraded = 2,
    /// Works.
    satisfied = 3,

    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .untested => "untested",
            .unsatisfied => "UNSATISFIED",
            .degraded => "DEGRADED",
            .satisfied => "satisfied",
        };
    }

    /// Fraction of a capability's weight this status earns, in hundredths.
    /// `degraded` earns a little because the surface exists and is callable —
    /// but only a little, because a surface that answers and does nothing is
    /// closer to absent than to working.
    pub fn creditPercent(self: Status) u32 {
        return switch (self) {
            .untested => 0,
            .unsatisfied => 0,
            .degraded => 25,
            .satisfied => 100,
        };
    }
};

/// The capability surface. Adding to this list is how the model learns; the
/// list being incomplete is the model's known weakness, and the report says so
/// rather than implying the enumeration is exhaustive.
pub const Capability = enum(u8) {
    guest_memory_mapping,
    memory_protection,
    address_space_translation,
    thread_creation,
    thread_scheduling,
    sync_primitives,
    wait_signal_handshake,
    file_read,
    disc_image,
    kernel_variable_surface,
    kernel_export_binding,
    gpu_engine_init,
    gpu_ring_buffer,
    gpu_interrupt_callback,
    gpu_command_flow,
    guest_swap_request,
    graphics_command_execution,
    frame_source,
    window_surface,
    frame_presentation,
    exception_unwinding,
    code_generation,
    locale_and_time,

    pub fn layer(self: Capability) Layer {
        return switch (self) {
            .guest_memory_mapping, .memory_protection, .address_space_translation => .memory,
            .thread_creation, .thread_scheduling, .sync_primitives, .wait_signal_handshake => .threading,
            .file_read, .disc_image => .storage,
            .kernel_variable_surface, .kernel_export_binding => .kernel_surface,
            .gpu_engine_init, .gpu_ring_buffer, .gpu_interrupt_callback, .gpu_command_flow, .guest_swap_request => .gpu_bringup,
            .graphics_command_execution, .frame_source, .window_surface, .frame_presentation => .presentation,
            .exception_unwinding, .code_generation, .locale_and_time => .platform_services,
        };
    }

    pub fn weight(self: Capability) Weight {
        return switch (self) {
            .guest_memory_mapping,
            .address_space_translation,
            .thread_creation,
            .sync_primitives,
            .file_read,
            .kernel_export_binding,
            .gpu_ring_buffer,
            .guest_swap_request,
            .graphics_command_execution,
            .frame_presentation,
            .code_generation,
            => .critical,

            .memory_protection,
            .thread_scheduling,
            .wait_signal_handshake,
            .disc_image,
            .kernel_variable_surface,
            .gpu_engine_init,
            .gpu_interrupt_callback,
            .gpu_command_flow,
            .frame_source,
            .window_surface,
            .exception_unwinding,
            => .supporting,

            .locale_and_time => .convenience,
        };
    }

    pub fn label(self: Capability) []const u8 {
        return switch (self) {
            .guest_memory_mapping => "guest memory mapping",
            .memory_protection => "memory protection and faults",
            .address_space_translation => "console address-space translation",
            .thread_creation => "thread creation",
            .thread_scheduling => "thread scheduling",
            .sync_primitives => "synchronisation primitives",
            .wait_signal_handshake => "wait/signal handshakes consume signals",
            .file_read => "file reads",
            .disc_image => "disc image access",
            .kernel_variable_surface => "kernel variable surface",
            .kernel_export_binding => "kernel export binding",
            .gpu_engine_init => "GPU engine initialisation",
            .gpu_ring_buffer => "GPU ring buffer",
            .gpu_interrupt_callback => "GPU interrupt callback",
            .gpu_command_flow => "GPU command flow (PM4 consumed)",
            .guest_swap_request => "title requests a swap",
            .graphics_command_execution => "graphics commands actually execute",
            .frame_source => "a frame source exists",
            .window_surface => "native window surface",
            .frame_presentation => "guest frames reach the window",
            .exception_unwinding => "C++ exception unwinding",
            .code_generation => "guest code generation",
            .locale_and_time => "locale and time queries",
        };
    }
};

pub const capability_count = @typeInfo(Capability).@"enum".fields.len;

/// Whether the guest has produced an output opportunity that can be judged
/// against the frame-source contract.
///
/// A native Vulkan present is intentionally not an input here. The native
/// presenter is also used for Rosette's diagnostic clears, and a successful
/// `vkQueuePresentKHR` only proves that a present request reached a driver. It
/// does not prove that Xenia's guest renderer produced an image. Requiring a
/// A target-backed live draw, a successful color resolve, a swap boundary, or
/// an encoded XE_SWAP keeps the supporting capability honest. Raw PM4 draw
/// syntax is retained for diagnostics but is not sufficient: a retained
/// observation can contain draws that never owned guest-visible effects, and a
/// draw with no target cannot produce a frame.
pub fn guestOutputOpportunity(evidence: GuestOutputEvidence) bool {
    return evidence.hasOutputOpportunity();
}

/// Judge VdSwap only after the guest has produced pixels or an explicit swap
/// boundary. General GPU bring-up and no-output startup draws are progress,
/// not proof that a presentation request was due.
pub fn guestSwapStatus(evidence: GuestOutputEvidence, swap_entered: bool) Status {
    if (swap_entered) return .satisfied;
    return if (guestOutputOpportunity(evidence)) .unsatisfied else .untested;
}

/// Judge the guest-to-window handoff from guest-authentic frames only.
/// Native/diagnostic presents prove the host sink separately through
/// `window_surface`; they never degrade this guest-owned capability.
pub fn guestPresentationStatus(
    evidence: GuestOutputEvidence,
    guest_source_available: bool,
    authentic_guest_frames_presented: u64,
) Status {
    if (authentic_guest_frames_presented != 0) return .satisfied;
    if (guest_source_available or guestOutputOpportunity(evidence)) return .unsatisfied;
    return .untested;
}

pub const Entry = struct {
    status: Status = .untested,
    /// One short line of evidence, so a status is never a bare assertion.
    note_storage: [96]u8 = [_]u8{0} ** 96,
    note_length: u8 = 0,

    pub fn note(self: *const Entry) []const u8 {
        return self.note_storage[0..self.note_length];
    }
};

pub const LayerScore = struct {
    layer: Layer,
    earned: u32 = 0,
    possible: u32 = 0,

    pub fn percent(self: LayerScore) u32 {
        if (self.possible == 0) return 0;
        return self.earned * 100 / self.possible;
    }
};

pub const Report = struct {
    earned: u32 = 0,
    possible: u32 = 0,
    satisfied: u32 = 0,
    degraded: u32 = 0,
    unsatisfied: u32 = 0,
    untested: u32 = 0,

    /// Aggregate counts are useful for progress, but they let healthy
    /// supporting capabilities hide an unproven GPU prerequisite. Keep the
    /// critical counts in the same report so the integrity gate and its log
    /// consume one snapshot rather than reconstructing a second truth.
    critical_total: u32 = 0,
    critical_satisfied: u32 = 0,
    critical_degraded: u32 = 0,
    critical_unsatisfied: u32 = 0,
    critical_untested: u32 = 0,

    pub fn percent(self: Report) u32 {
        if (self.possible == 0) return 0;
        return self.earned * 100 / self.possible;
    }
};

pub const Ledger = struct {
    entries: [capability_count]Entry = [_]Entry{.{}} ** capability_count,

    pub fn record(self: *Ledger, capability: Capability, value: Status, note: []const u8) void {
        const record_entry = &self.entries[@intFromEnum(capability)];
        record_entry.status = value;
        const length = @min(note.len, record_entry.note_storage.len);
        @memcpy(record_entry.note_storage[0..length], note[0..length]);
        record_entry.note_length = @intCast(length);
    }

    pub fn status(self: *const Ledger, capability: Capability) Status {
        return self.entries[@intFromEnum(capability)].status;
    }

    pub fn entry(self: *const Ledger, capability: Capability) Entry {
        return self.entries[@intFromEnum(capability)];
    }

    pub fn report(self: *const Ledger) Report {
        var result = Report{};
        inline for (@typeInfo(Capability).@"enum".fields) |field| {
            const capability: Capability = @enumFromInt(field.value);
            const entry_status = self.status(capability);
            const weight = capability.weight().value();
            result.possible += weight * 100;
            result.earned += weight * entry_status.creditPercent();
            const critical = capability.weight() == .critical;
            if (critical) result.critical_total += 1;
            switch (entry_status) {
                .satisfied => {
                    result.satisfied += 1;
                    if (critical) result.critical_satisfied += 1;
                },
                .degraded => {
                    result.degraded += 1;
                    if (critical) result.critical_degraded += 1;
                },
                .unsatisfied => {
                    result.unsatisfied += 1;
                    if (critical) result.critical_unsatisfied += 1;
                },
                .untested => {
                    result.untested += 1;
                    if (critical) result.critical_untested += 1;
                },
            }
        }
        return result;
    }

    pub fn layerScore(self: *const Ledger, layer: Layer) LayerScore {
        var score = LayerScore{ .layer = layer };
        inline for (@typeInfo(Capability).@"enum".fields) |field| {
            const capability: Capability = @enumFromInt(field.value);
            if (capability.layer() == layer) {
                const weight = capability.weight().value();
                score.possible += weight * 100;
                score.earned += weight * self.status(capability).creditPercent();
            }
        }
        return score;
    }

    /// The layer holding the run back the most: lowest score, ties broken by
    /// the heavier layer, because a weak heavy layer costs more than a weak
    /// light one.
    pub fn weakestLayer(self: *const Ledger) ?LayerScore {
        var chosen: ?LayerScore = null;
        inline for (@typeInfo(Layer).@"enum".fields) |field| {
            const layer: Layer = @enumFromInt(field.value);
            const score = self.layerScore(layer);
            if (score.possible != 0) {
                const better = chosen == null or score.percent() < chosen.?.percent() or
                    (score.percent() == chosen.?.percent() and score.possible > chosen.?.possible);
                if (better) chosen = score;
            }
        }
        return chosen;
    }

    /// Critical capabilities that are not satisfied, in declaration order.
    /// The shortest list that, if emptied, would produce a frame.
    pub fn criticalGaps(self: *const Ledger, out: []Capability) []Capability {
        var length: usize = 0;
        inline for (@typeInfo(Capability).@"enum".fields) |field| {
            const capability: Capability = @enumFromInt(field.value);
            if (length < out.len and capability.weight() == .critical and
                self.status(capability) != .satisfied)
            {
                out[length] = capability;
                length += 1;
            }
        }
        return out[0..length];
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        const result = self.report();
        if (result.untested == capability_count)
            return "no capability has been exercised yet, so this number is not a measurement of anything";
        if (result.degraded != 0 and result.unsatisfied == 0)
            return "nothing is outright broken and something is degraded: a surface that answers every call and does not do the job. That is the state that reports healthy counters and shows nothing on screen, so the degraded entries below are where the remaining distance is";
        if (result.unsatisfied != 0)
            return "at least one capability is exercised and does not work. The critical gaps below are the shortest list that, if emptied, would produce a frame";
        if (result.untested != 0)
            return "everything exercised so far works, and some of the surface has never been exercised. The untested entries are unknowns rather than good news";
        return "every modelled capability is satisfied. If there is still no frame, the model is missing a capability — which is its known weakness, not a claim that nothing is wrong";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "an unexercised ledger refuses to call its number a measurement" {
    const ledger = Ledger{};
    const result = ledger.report();
    try std.testing.expectEqual(@as(u32, 11), result.critical_total);
    try std.testing.expectEqual(@as(u32, 0), result.percent());
    try std.testing.expectEqual(@as(u32, capability_count), result.untested);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "not a measurement") != null);
}

// The most dangerous capability is one that answers every call and does
// nothing. Scoring it as satisfied is how a stack reports ninety percent and
// shows a blue screen.
test "a degraded capability earns a little and is never counted as working" {
    var ledger = Ledger{};
    ledger.record(.graphics_command_execution, .degraded, "modelled: every submit returns success and nothing executes");
    try std.testing.expectEqual(Status.degraded, ledger.status(.graphics_command_execution));
    try std.testing.expectEqual(@as(u32, 25), Status.degraded.creditPercent());

    // It still counts as a critical gap.
    var buffer: [capability_count]Capability = undefined;
    const gaps = ledger.criticalGaps(&buffer);
    var found = false;
    for (gaps) |gap| {
        if (gap == .graphics_command_execution) found = true;
    }
    try std.testing.expect(found);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "nothing on screen") != null);
}

test "untested and unsatisfied are different amounts of bad news" {
    var ledger = Ledger{};
    ledger.record(.file_read, .unsatisfied, "every read failed");
    const result = ledger.report();
    try std.testing.expectEqual(@as(u32, 1), result.unsatisfied);
    try std.testing.expectEqual(@as(u32, capability_count - 1), result.untested);
    // Both earn nothing, and the verdict distinguishes them.
    try std.testing.expectEqual(@as(u32, 0), Status.untested.creditPercent());
    try std.testing.expectEqual(@as(u32, 0), Status.unsatisfied.creditPercent());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "shortest list") != null);
}

test "the report keeps critical capability health separate from convenience coverage" {
    var ledger = Ledger{};
    ledger.record(.file_read, .satisfied, "critical capability works");
    ledger.record(.guest_swap_request, .unsatisfied, "the title never requested a swap");
    ledger.record(.graphics_command_execution, .degraded, "native submission has no proven guest draw");
    ledger.record(.frame_presentation, .untested, "no presentation boundary reached");
    ledger.record(.locale_and_time, .unsatisfied, "convenience capability failed");

    const result = ledger.report();
    try std.testing.expectEqual(@as(u32, 1), result.critical_satisfied);
    try std.testing.expectEqual(@as(u32, 1), result.critical_degraded);
    try std.testing.expectEqual(@as(u32, 1), result.critical_unsatisfied);
    try std.testing.expectEqual(@as(u32, 8), result.critical_untested);
    try std.testing.expectEqual(@as(u32, 2), result.unsatisfied);
}

// "The run is at sixty percent" says nothing actionable; "threading is complete
// and presentation is at ten percent" says where to go.
test "the weakest layer names where the next hour belongs" {
    var ledger = Ledger{};
    inline for (.{
        Capability.thread_creation, Capability.thread_scheduling,
        Capability.sync_primitives, Capability.wait_signal_handshake,
    }) |capability| ledger.record(capability, .satisfied, "works");

    try std.testing.expectEqual(@as(u32, 100), ledger.layerScore(.threading).percent());
    try std.testing.expectEqual(@as(u32, 0), ledger.layerScore(.presentation).percent());

    const weakest = ledger.weakestLayer().?;
    try std.testing.expectEqual(@as(u32, 0), weakest.percent());
    // Ties at zero break toward the heavier layer.
    try std.testing.expect(weakest.possible > 0);
}

test "weights are coarse and critical capabilities dominate the score" {
    var ledger = Ledger{};
    ledger.record(.locale_and_time, .satisfied, "convenience only");
    const with_convenience = ledger.report().percent();

    var heavier = Ledger{};
    heavier.record(.frame_presentation, .satisfied, "critical");
    try std.testing.expect(heavier.report().percent() > with_convenience);

    try std.testing.expectEqual(@as(u32, 5), Weight.critical.value());
    try std.testing.expectEqual(@as(u32, 1), Weight.convenience.value());
}

test "a note travels with every status so it is never a bare assertion" {
    var ledger = Ledger{};
    ledger.record(.gpu_ring_buffer, .satisfied, "rb_base=1FC9B000 size=0x8000, 25 dwords consumed");
    try std.testing.expectEqualStrings(
        "rb_base=1FC9B000 size=0x8000, 25 dwords consumed",
        ledger.entry(.gpu_ring_buffer).note(),
    );

    const long = "n" ** 300;
    ledger.record(.gpu_ring_buffer, .satisfied, long);
    try std.testing.expectEqual(@as(usize, 96), ledger.entry(.gpu_ring_buffer).note().len);
}

test "a fully satisfied ledger admits the model may be incomplete" {
    var ledger = Ledger{};
    inline for (@typeInfo(Capability).@"enum".fields) |field| {
        ledger.record(@enumFromInt(field.value), .satisfied, "works");
    }
    try std.testing.expectEqual(@as(u32, 100), ledger.report().percent());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "missing a capability") != null);
    var buffer: [capability_count]Capability = undefined;
    try std.testing.expectEqual(@as(usize, 0), ledger.criticalGaps(&buffer).len);
}

// The state the project is actually in, so the model is exercised against a
// real shape rather than a synthetic one.
test "the observed run scores low with presentation as the weakest layer" {
    var ledger = Ledger{};
    inline for (.{
        Capability.guest_memory_mapping,      Capability.memory_protection,
        Capability.address_space_translation, Capability.thread_creation,
        Capability.thread_scheduling,         Capability.sync_primitives,
        Capability.file_read,                 Capability.disc_image,
        Capability.kernel_variable_surface,   Capability.kernel_export_binding,
        Capability.gpu_engine_init,           Capability.gpu_ring_buffer,
        Capability.gpu_interrupt_callback,    Capability.gpu_command_flow,
        Capability.window_surface,            Capability.exception_unwinding,
        Capability.locale_and_time,
    }) |capability| ledger.record(capability, .satisfied, "observed working");

    ledger.record(.wait_signal_handshake, .degraded, "one object stalled with zero signals");
    ledger.record(.code_generation, .degraded, "one function left undefined by an Xbyak error");
    ledger.record(.guest_swap_request, .unsatisfied, "VdSwap never entered");
    ledger.record(.graphics_command_execution, .degraded, "modelled: submits succeed and nothing executes");
    ledger.record(.frame_source, .unsatisfied, "no guest image has ever held a picture");
    ledger.record(.frame_presentation, .degraded, "only diagnostic frames reach the window");

    const result = ledger.report();
    try std.testing.expect(result.percent() > 40);
    try std.testing.expect(result.percent() < 80);
    try std.testing.expectEqual(Layer.presentation, ledger.weakestLayer().?.layer);

    var buffer: [capability_count]Capability = undefined;
    const gaps = ledger.criticalGaps(&buffer);
    // Four, not three: a degraded critical capability is still a gap. Code
    // generation answers most calls and left one function undefined, which is
    // exactly the kind of "mostly working" that must not drop off this list.
    try std.testing.expectEqual(@as(usize, 4), gaps.len);
    try std.testing.expectEqual(Capability.guest_swap_request, gaps[0]);
    try std.testing.expectEqual(Capability.graphics_command_execution, gaps[1]);
    try std.testing.expectEqual(Capability.frame_presentation, gaps[2]);
    try std.testing.expectEqual(Capability.code_generation, gaps[3]);
}

test "every capability names a layer, a weight and itself" {
    inline for (@typeInfo(Capability).@"enum".fields) |field| {
        const capability: Capability = @enumFromInt(field.value);
        try std.testing.expect(capability.label().len > 0);
        try std.testing.expect(capability.weight().value() > 0);
        try std.testing.expect(capability.layer().label().len > 0);
    }
    inline for (.{ Status.untested, Status.unsatisfied, Status.degraded, Status.satisfied }) |st| {
        try std.testing.expect(st.label().len > 0);
    }
}

test "a native diagnostic present is not a guest output opportunity" {
    try std.testing.expect(!guestOutputOpportunity(.{}));
}

test "raw PM4 draws do not open the frame-source contract" {
    try std.testing.expect(!guestOutputOpportunity(.{ .raw_draws_consumed = 24 }));
}

test "guest render evidence opens the frame-source contract" {
    try std.testing.expect(guestOutputOpportunity(.{ .raw_draws_consumed = 24, .renderable_draws_observed = 1 }));
    try std.testing.expect(guestOutputOpportunity(.{ .color_resolve_observations = 1 }));
    try std.testing.expect(guestOutputOpportunity(.{ .guest_swap_boundaries = 1 }));
    try std.testing.expect(guestOutputOpportunity(.{ .guest_vdswap_packets_encoded = 1 }));
}

test "startup GPU traffic does not turn an unreached VdSwap into a failure" {
    const startup = GuestOutputEvidence{ .raw_draws_consumed = 24 };
    try std.testing.expectEqual(Status.untested, guestSwapStatus(startup, false));
    try std.testing.expectEqual(Status.satisfied, guestSwapStatus(startup, true));
    try std.testing.expectEqual(
        Status.unsatisfied,
        guestSwapStatus(.{ .renderable_draws_observed = 1 }, false),
    );
}

test "diagnostic native presents never degrade the guest frame capability" {
    const startup = GuestOutputEvidence{ .raw_draws_consumed = 24 };
    try std.testing.expectEqual(Status.untested, guestPresentationStatus(startup, false, 0));
    try std.testing.expectEqual(
        Status.unsatisfied,
        guestPresentationStatus(.{ .color_resolve_observations = 1 }, false, 0),
    );
    try std.testing.expectEqual(Status.unsatisfied, guestPresentationStatus(.{}, true, 0));
    try std.testing.expectEqual(Status.satisfied, guestPresentationStatus(.{}, true, 1));
}
