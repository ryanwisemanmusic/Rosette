//! Where a displayed frame came from, recorded so that no counter can be
//! mistaken for evidence of rendering.
//!
//! A window showing a solid colour and a window showing a game both increment
//! "frames presented". The runtime has, at various times, produced the first
//! while every log line described the second: a host-generated Metal clear
//! reached the drawable, a present counter went up, and nothing in the record
//! distinguished that from the guest's own output. The screenshot then became
//! the evidence, and the evidence was wrong.
//!
//! So a frame is not counted by whoever presented it. It arrives with a claim —
//! who produced it, and which links of the chain from source to presentation
//! were genuinely native — and this classifies it into the strongest class the
//! claim actually supports. An over-claiming caller is demoted, not believed,
//! and the demotion is itself recorded: a runtime that quietly rounds its own
//! fidelity upward is worse than one that renders nothing, because the second
//! is obvious.
//!
//! The counters are deliberately separate and never summed. A diagnostic frame
//! can only ever move `diagnostic_frames_presented`; reaching
//! `guest_output_frames_presented` requires the whole chain, including a guest
//! swap the guest actually performed. That is the one number a screenshot is
//! allowed to be read against.

const std = @import("std");

/// Who made the pixels. Not who presented them — the presenter is the same
/// object in all three cases, which is exactly why it cannot be the label.
pub const Producer = enum(u8) {
    /// Rosette's own liveness probe. Proves the window and the presentation
    /// path are alive; proves nothing whatsoever about the guest.
    diagnostic,
    /// Xenia's host renderer produced a completed image from guest GPU
    /// semantics. Real emulator output, but not yet tied to a guest swap.
    xenia_host,
    /// Derived from work the guest submitted and swapped.
    guest,

    pub fn label(self: Producer) []const u8 {
        return switch (self) {
            .diagnostic => "diagnostic",
            .xenia_host => "xenia_host",
            .guest => "guest",
        };
    }
};

/// One link in the chain between a source image and a presented pixel. Ordered
/// so the first missing one is the next thing to build.
pub const Link = enum(u8) {
    source_ready,
    native_command_recording,
    native_submission,
    native_presentation,
    present_accepted,
    /// A host fence or command-buffer status proved that the submitted GPU
    /// work completed.  A present request is only an enqueue operation; it is
    /// not this link.
    hardware_completed,
    guest_swap_observed,

    pub fn label(self: Link) []const u8 {
        return switch (self) {
            .source_ready => "a completed source image",
            .native_command_recording => "commands recorded into a native command buffer",
            .native_submission => "a native vkQueueSubmit",
            .native_presentation => "a native vkQueuePresentKHR",
            .present_accepted => "a presentation request the engine accepted",
            .hardware_completed => "host GPU work completed on a fence",
            .guest_swap_observed => "a VdSwap the guest actually performed",
        };
    }
};

/// What a caller claims about one frame. Every field is a fact the caller must
/// have observed; none may be inferred from another.
pub const Evidence = struct {
    producer: Producer = .diagnostic,
    /// A completed image existed before the frame was recorded.
    source_ready: bool = false,
    /// Commands were recorded into a command buffer the host driver owns.
    native_command_recording: bool = false,
    /// The commands were submitted to a host driver queue.
    native_submission: bool = false,
    /// Presentation went through the host driver rather than a host-side
    /// compositor call the guest never reached.
    native_presentation: bool = false,
    /// The presentation engine accepted the request. Acceptance, not sight.
    present_accepted: bool = false,
    /// A host synchronization primitive proved that the submitted GPU work
    /// completed. This is deliberately separate from `present_accepted`:
    /// Vulkan can accept a present while its preceding submission is still in
    /// flight.
    hardware_completed: bool = false,
    /// The guest performed a swap for this frame.
    guest_swap_observed: bool = false,

    /// The first link that is missing, which is both why the frame is not guest
    /// output and the next thing to implement.
    pub fn firstMissingLink(self: Evidence) ?Link {
        if (!self.source_ready) return .source_ready;
        if (!self.native_command_recording) return .native_command_recording;
        if (!self.native_submission) return .native_submission;
        if (!self.native_presentation) return .native_presentation;
        if (!self.present_accepted) return .present_accepted;
        if (!self.hardware_completed) return .hardware_completed;
        if (!self.guest_swap_observed) return .guest_swap_observed;
        return null;
    }

    /// Every link except the guest's own swap. This is what an authentic
    /// Xenia-produced host frame satisfies.
    pub fn nativeChainComplete(self: Evidence) bool {
        return self.source_ready and self.native_command_recording and
            self.native_submission and self.native_presentation and self.present_accepted and
            self.hardware_completed;
    }
};

/// The strongest class the evidence supports. Never the class the caller hoped
/// for.
pub const Classification = enum(u8) {
    /// Nothing reached the display. Not a frame.
    rejected,
    /// The host accepted a presentation request, but no host synchronization
    /// edge has proved that the submitted GPU work completed. It is not safe
    /// to call this diagnostic, host, or guest output.
    incomplete_frame,
    /// A host-generated liveness frame. Says the window works.
    diagnostic_frame,
    /// Xenia's host renderer reached the display through the native driver.
    host_frame,
    /// Guest-derived pixels, with the whole chain proven.
    guest_output_frame,

    pub fn label(self: Classification) []const u8 {
        return switch (self) {
            .rejected => "rejected",
            .incomplete_frame => "incomplete_frame",
            .diagnostic_frame => "diagnostic_frame",
            .host_frame => "host_frame",
            .guest_output_frame => "guest_output_frame",
        };
    }

    /// The single question a screenshot may be read against.
    pub fn isGuestOutput(self: Classification) bool {
        return self == .guest_output_frame;
    }
};

pub fn classify(evidence: Evidence) Classification {
    if (!evidence.present_accepted) return .rejected;
    if (!evidence.hardware_completed) return .incomplete_frame;
    if (evidence.producer == .guest and evidence.nativeChainComplete() and evidence.guest_swap_observed) {
        return .guest_output_frame;
    }
    if (evidence.producer != .diagnostic and evidence.nativeChainComplete()) return .host_frame;
    return .diagnostic_frame;
}

/// Counters that must never be added together or substituted for one another.
/// Each answers a different question, and the whole point of keeping them apart
/// is that the answers differ.
pub const Ledger = struct {
    /// Vulkan entry points the guest called, however they were answered.
    guest_vulkan_calls_seen: u64 = 0,
    /// Calls Rosette made into the host driver.
    native_driver_calls: u64 = 0,
    /// `vkQueueSubmit` calls that reached the host driver.
    native_submissions: u64 = 0,
    /// `vkQueuePresentKHR` calls that reached the host driver.
    native_present_requests: u64 = 0,
    /// Authentic PM4 packets the guest published.
    guest_ring_packets: u64 = 0,

    diagnostic_frames_presented: u64 = 0,
    host_frames_presented: u64 = 0,
    guest_output_frames_presented: u64 = 0,
    /// Frames whose presentation request was never accepted.
    frames_rejected: u64 = 0,
    /// Requests accepted by the presentation engine before a host fence proved
    /// that the submitted GPU work completed. These are neither rejected nor
    /// presented frames.
    frames_incomplete: u64 = 0,
    /// Frames classified below what the caller claimed. A non-zero value here
    /// means some part of the runtime believes it is more native than it is.
    claims_demoted: u64 = 0,

    /// The first missing link of the most recent frame, kept so a summary can
    /// say what to build next without re-deriving it.
    last_missing_link: ?Link = null,
    last_classification: Classification = .rejected,

    pub fn noteGuestVulkanCall(self: *Ledger) void {
        self.guest_vulkan_calls_seen +|= 1;
    }

    pub fn noteNativeDriverCall(self: *Ledger) void {
        self.native_driver_calls +|= 1;
    }

    pub fn noteNativeSubmission(self: *Ledger) void {
        self.native_submissions +|= 1;
        self.native_driver_calls +|= 1;
    }

    pub fn noteNativePresentRequest(self: *Ledger) void {
        self.native_present_requests +|= 1;
        self.native_driver_calls +|= 1;
    }

    pub fn noteGuestRingPacket(self: *Ledger) void {
        self.guest_ring_packets +|= 1;
    }

    /// Record one frame and return what it actually was.
    pub fn record(self: *Ledger, evidence: Evidence) Classification {
        const actual = classify(evidence);
        const claimed: Classification = switch (evidence.producer) {
            .diagnostic => .diagnostic_frame,
            .xenia_host => .host_frame,
            .guest => .guest_output_frame,
        };
        if (@intFromEnum(actual) < @intFromEnum(claimed)) self.claims_demoted +|= 1;
        switch (actual) {
            .rejected => self.frames_rejected +|= 1,
            .incomplete_frame => self.frames_incomplete +|= 1,
            .diagnostic_frame => self.diagnostic_frames_presented +|= 1,
            .host_frame => self.host_frames_presented +|= 1,
            .guest_output_frame => self.guest_output_frames_presented +|= 1,
        }
        self.last_missing_link = evidence.firstMissingLink();
        self.last_classification = actual;
        return actual;
    }

    /// What the runtime should say about anything currently on screen.
    pub fn displayNote(self: *const Ledger) []const u8 {
        if (self.guest_output_frames_presented != 0) {
            return "guest-derived pixels have reached the display through the host driver";
        }
        if (self.host_frames_presented != 0) {
            return "Xenia host-rendered frames have reached the display; no frame is yet tied to a guest swap";
        }
        if (self.diagnostic_frames_presented != 0) {
            return "everything displayed so far is a Rosette diagnostic frame. It proves the window and the presentation path are alive and says NOTHING about the guest's rendering";
        }
        if (self.frames_incomplete != 0) {
            return "the presentation engine accepted work, but no host fence has proved GPU completion; no frame is counted until that edge exists";
        }
        return "nothing has reached the display";
    }
};

test "a present the engine never accepted is not a frame" {
    var ledger = Ledger{};
    const result = ledger.record(.{ .producer = .guest, .source_ready = true });
    try std.testing.expectEqual(Classification.rejected, result);
    try std.testing.expectEqual(@as(u64, 1), ledger.frames_rejected);
    try std.testing.expectEqual(@as(u64, 0), ledger.guest_output_frames_presented);
}

// The exact confusion this file exists to prevent: a host clear reaching a real
// drawable, counted as if the guest had rendered it.
test "a diagnostic clear cannot move the guest-output counter" {
    var ledger = Ledger{};
    const result = ledger.record(.{
        .producer = .diagnostic,
        .source_ready = true,
        .present_accepted = true,
        .hardware_completed = true,
    });
    try std.testing.expectEqual(Classification.diagnostic_frame, result);
    try std.testing.expectEqual(@as(u64, 1), ledger.diagnostic_frames_presented);
    try std.testing.expectEqual(@as(u64, 0), ledger.host_frames_presented);
    try std.testing.expectEqual(@as(u64, 0), ledger.guest_output_frames_presented);
    try std.testing.expect(std.mem.indexOf(u8, ledger.displayNote(), "NOTHING about the guest") != null);
}

// Claiming guest output does not produce it. The claim is demoted and the
// demotion is recorded, because a runtime that overstates itself is the harder
// failure to notice.
test "an over-claimed frame is demoted and the demotion is counted" {
    var ledger = Ledger{};
    const result = ledger.record(.{
        .producer = .guest,
        .source_ready = true,
        .native_command_recording = true,
        .native_submission = true,
        .native_presentation = true,
        .present_accepted = true,
        .hardware_completed = true,
        // The guest never swapped.
        .guest_swap_observed = false,
    });
    try std.testing.expectEqual(Classification.host_frame, result);
    try std.testing.expectEqual(@as(u64, 1), ledger.claims_demoted);
    try std.testing.expectEqual(@as(u64, 0), ledger.guest_output_frames_presented);
    try std.testing.expectEqual(Link.guest_swap_observed, ledger.last_missing_link.?);
}

test "a full chain with a guest swap is the only route to guest output" {
    var ledger = Ledger{};
    const evidence = Evidence{
        .producer = .guest,
        .source_ready = true,
        .native_command_recording = true,
        .native_submission = true,
        .native_presentation = true,
        .present_accepted = true,
        .hardware_completed = true,
        .guest_swap_observed = true,
    };
    try std.testing.expectEqual(Classification.guest_output_frame, ledger.record(evidence));
    try std.testing.expectEqual(@as(u64, 1), ledger.guest_output_frames_presented);
    try std.testing.expectEqual(@as(u64, 0), ledger.claims_demoted);
    try std.testing.expect(ledger.last_missing_link == null);
    try std.testing.expect(ledger.last_classification.isGuestOutput());
}

// Xenia rendering through the host backend is real output and deserves its own
// class: calling it diagnostic understates it, calling it guest output claims a
// swap that has not happened.
test "an authentic host-rendered frame is neither diagnostic nor guest output" {
    var ledger = Ledger{};
    const result = ledger.record(.{
        .producer = .xenia_host,
        .source_ready = true,
        .native_command_recording = true,
        .native_submission = true,
        .native_presentation = true,
        .present_accepted = true,
        .hardware_completed = true,
    });
    try std.testing.expectEqual(Classification.host_frame, result);
    try std.testing.expectEqual(@as(u64, 1), ledger.host_frames_presented);
    try std.testing.expectEqual(@as(u64, 0), ledger.diagnostic_frames_presented);
    try std.testing.expectEqual(@as(u64, 0), ledger.guest_output_frames_presented);
}

// An accepted host request without a completion edge cannot be called a frame
// at all: strict provenance requires hardware completion before even the
// weaker diagnostic/host classifications are available.
test "presentation without host completion stays incomplete" {
    var ledger = Ledger{};
    const result = ledger.record(.{
        .producer = .xenia_host,
        .source_ready = true,
        .native_command_recording = true,
        .native_submission = true,
        .native_presentation = true,
        .present_accepted = true,
    });
    try std.testing.expectEqual(Classification.incomplete_frame, result);
    try std.testing.expectEqual(Link.hardware_completed, ledger.last_missing_link.?);
    try std.testing.expectEqual(@as(u64, 1), ledger.claims_demoted);
    try std.testing.expectEqual(@as(u64, 1), ledger.frames_incomplete);
}

test "an accepted request without a host completion edge is not a frame" {
    var ledger = Ledger{};
    const result = ledger.record(.{
        .producer = .diagnostic,
        .source_ready = true,
        .native_command_recording = true,
        .native_submission = true,
        .native_presentation = true,
        .present_accepted = true,
    });
    try std.testing.expectEqual(Classification.incomplete_frame, result);
    try std.testing.expectEqual(@as(u64, 1), ledger.frames_incomplete);
    try std.testing.expectEqual(Link.hardware_completed, ledger.last_missing_link.?);
    try std.testing.expectEqual(@as(u64, 0), ledger.diagnostic_frames_presented);
}

test "the first missing link names the next thing to build" {
    const nothing = Evidence{};
    try std.testing.expectEqual(Link.source_ready, nothing.firstMissingLink().?);

    const recorded = Evidence{ .source_ready = true };
    try std.testing.expectEqual(Link.native_command_recording, recorded.firstMissingLink().?);

    const submitted = Evidence{
        .source_ready = true,
        .native_command_recording = true,
        .native_submission = true,
    };
    try std.testing.expectEqual(Link.native_presentation, submitted.firstMissingLink().?);
}

test "call counters stay separate from frame counters" {
    var ledger = Ledger{};
    ledger.noteGuestVulkanCall();
    ledger.noteGuestVulkanCall();
    ledger.noteNativeSubmission();
    ledger.noteNativePresentRequest();
    ledger.noteGuestRingPacket();

    try std.testing.expectEqual(@as(u64, 2), ledger.guest_vulkan_calls_seen);
    try std.testing.expectEqual(@as(u64, 1), ledger.native_submissions);
    try std.testing.expectEqual(@as(u64, 1), ledger.native_present_requests);
    // Submissions and presents are both driver calls; guest calls are not.
    try std.testing.expectEqual(@as(u64, 2), ledger.native_driver_calls);
    try std.testing.expectEqual(@as(u64, 1), ledger.guest_ring_packets);
    // None of that is a frame.
    try std.testing.expectEqual(@as(u64, 0), ledger.diagnostic_frames_presented);
    try std.testing.expectEqual(@as(u64, 0), ledger.guest_output_frames_presented);
    try std.testing.expectEqualStrings("nothing has reached the display", ledger.displayNote());
}

test "every producer and link explains itself" {
    inline for (@typeInfo(Producer).@"enum".fields) |field| {
        const producer: Producer = @enumFromInt(field.value);
        try std.testing.expect(producer.label().len > 0);
    }
    inline for (@typeInfo(Link).@"enum".fields) |field| {
        const link: Link = @enumFromInt(field.value);
        try std.testing.expect(link.label().len > 0);
    }
}
