//! What the guest asked the host graphics API for, what it got, and whether
//! the difference can change a pixel.
//!
//! The defect this exists for
//! --------------------------
//! Every native Vulkan call in the 2026-08-31 run returned success. That
//! proves the host sink and the diagnostic path, and it proves nothing about
//! the path a guest frame will take, because a guest frame additionally
//! exercises image import, format and layout conversion, stride and swizzle,
//! host-visible versus device-local fallback, queue ownership, image lifetime
//! across the UI-thread handoff, and the feature and extension values the
//! emulator is told about.
//!
//! The absence of an optional host-visible memory path costs a copy today and
//! is not the missing frame. It is still worth measuring, because a copy or
//! ownership bug appears the moment `VdSwap` starts working and would then
//! look like a new regression rather than a pre-existing gap.
//!
//! The rule
//! --------
//! Advertising a feature the device does not have is worse than not having it:
//! the emulator will use it and the failure surfaces somewhere else entirely.
//! So `advertised` and `available` are separate fields and their disagreement
//! is its own finding.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;

/// The operations a guest frame's path uses.
pub const Operation = enum(u8) {
    create_image = 0,
    allocate_memory = 1,
    bind_memory = 2,
    map_memory = 3,
    copy_buffer_to_image = 4,
    transition_layout = 5,
    acquire_next_image = 6,
    queue_submit = 7,
    queue_present = 8,
    wait_fence = 9,
    signal_semaphore = 10,
    transfer_queue_ownership = 11,

    pub fn label(self: Operation) []const u8 {
        return switch (self) {
            .create_image => "create-image",
            .allocate_memory => "allocate-memory",
            .bind_memory => "bind-memory",
            .map_memory => "map-memory",
            .copy_buffer_to_image => "copy-buffer-to-image",
            .transition_layout => "transition-layout",
            .acquire_next_image => "acquire-next-image",
            .queue_submit => "queue-submit",
            .queue_present => "queue-present",
            .wait_fence => "wait-fence",
            .signal_semaphore => "signal-semaphore",
            .transfer_queue_ownership => "transfer-queue-ownership",
        };
    }

    /// Whether a guest frame needs it, as opposed to a diagnostic clear.
    /// Everything a diagnostic path exercises is also on the guest path; the
    /// reverse is not true, and this is the list that separates them.
    pub fn onlyOnGuestPath(self: Operation) bool {
        return switch (self) {
            .map_memory, .copy_buffer_to_image, .transfer_queue_ownership => true,
            else => false,
        };
    }
};

pub const operation_count: usize = @typeInfo(Operation).@"enum".fields.len;

/// What a fallback cost.
pub const Fallback = enum(u8) {
    /// The preferred path was taken.
    none = 0,
    /// A copy instead of a direct mapping. Costs time, changes no pixels.
    extra_copy = 1,
    /// A different memory type. Costs time, changes no pixels.
    memory_type_substitution = 2,
    /// A different image format. Can change pixels.
    format_substitution = 3,
    /// A different layout or swizzle. Can change pixels.
    layout_substitution = 4,
    /// The operation was skipped entirely.
    omitted = 5,

    pub fn label(self: Fallback) []const u8 {
        return switch (self) {
            .none => "none",
            .extra_copy => "extra-copy",
            .memory_type_substitution => "memory-type-substitution",
            .format_substitution => "format-substitution",
            .layout_substitution => "layout-substitution",
            .omitted => "omitted",
        };
    }

    /// Whether taking this fallback can change what ends up on screen. A
    /// fallback that only costs time is a performance note; one that can
    /// change pixels is a fidelity finding.
    pub fn canChangePixels(self: Fallback) bool {
        return switch (self) {
            .format_substitution, .layout_substitution, .omitted => true,
            .none, .extra_copy, .memory_type_substitution => false,
        };
    }
};

pub const fallback_count: usize = @typeInfo(Fallback).@"enum".fields.len;

/// One host capability, as advertised and as real.
pub const Capability = struct {
    name: []const u8 = "",
    /// What the emulator was told.
    advertised: bool = false,
    /// What the device actually has.
    available: bool = false,
    /// Whether the emulator used it.
    used: bool = false,

    /// Advertising something absent is the dangerous direction: the emulator
    /// will use it and the failure appears somewhere unrelated.
    pub fn overAdvertised(self: Capability) bool {
        return self.advertised and !self.available;
    }

    /// Not advertising something present costs a fallback and nothing else.
    pub fn underAdvertised(self: Capability) bool {
        return self.available and !self.advertised;
    }
};

/// One forwarded operation.
pub const Call = struct {
    operation: Operation = .create_image,
    /// The guest's request and the native result, kept apart so a translated
    /// success over a native failure is visible.
    guest_result: i32 = 0,
    native_result: i32 = 0,
    fallback: Fallback = .none,
    /// Bytes or pixels the operation moved, when it moves any.
    bytes: u64 = 0,
    /// Content checksums either side, for operations that transform data.
    checksum_before: u64 = 0,
    checksum_after: u64 = 0,
    checksum_sampled: bool = false,
    /// Which queue family owned the resource before and after.
    queue_before: u32 = 0,
    queue_after: u32 = 0,
    source: SourceClass = .unknown,
    step: u64 = 0,

    pub fn succeeded(self: Call) bool {
        return self.native_result == 0;
    }

    /// The guest was told it worked and the native call did not. This is the
    /// shape a silently-degraded frame takes.
    pub fn resultsDisagree(self: Call) bool {
        return (self.guest_result == 0) != (self.native_result == 0);
    }

    /// Whether the operation changed content it was supposed to change.
    pub fn transformedContent(self: Call) bool {
        return self.checksum_sampled and self.checksum_before != self.checksum_after;
    }
};

pub const max_capabilities: usize = 16;
pub const max_calls: usize = 32;

pub const Summary = struct {
    calls: u64 = 0,
    retained: usize = 0,
    dropped: u64 = 0,
    failures: u64 = 0,
    result_disagreements: u64 = 0,
    pixel_changing_fallbacks: u64 = 0,
    cost_only_fallbacks: u64 = 0,
    by_operation: [operation_count]u64 = [_]u64{0} ** operation_count,
    guest_path_operations: u64 = 0,
    capabilities: usize = 0,
    over_advertised: u64 = 0,
    under_advertised: u64 = 0,

    /// Whether anything beyond the diagnostic path has been exercised. A run
    /// that only ever cleared has not tested the guest frame's route.
    pub fn guestPathExercised(self: Summary) bool {
        return self.guest_path_operations != 0;
    }
};

pub const Verdict = enum(u8) {
    /// Nothing forwarded.
    unobserved,
    /// Only the diagnostic path has been exercised.
    sink_only,
    /// The guest path works with no pixel-changing fallback.
    faithful,
    /// The guest path works and something on it can change pixels.
    degraded,
    /// A native call failed.
    failing,
    /// The guest was told an operation succeeded that did not, or a capability
    /// was advertised that does not exist.
    misreported,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .sink_only => "sink-only",
            .faithful => "faithful",
            .degraded => "degraded",
            .failing => "FAILING",
            .misreported => "MISREPORTED",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "nothing has been forwarded. Neither the sink nor the guest path has been tested",
            .sink_only => "only the diagnostic path has been exercised. Native acquire, submit and present all succeeding proves the sink and says nothing about the route a guest frame takes — image import, format conversion, queue ownership and lifetime are all untested",
            .faithful => "the guest path has been exercised and no fallback on it can change pixels",
            .degraded => "the guest path works and something on it substitutes a format, a layout, or omits an operation. The frame will appear and it is not the frame the title asked for",
            .failing => "a native call failed. Whatever the guest was told, the host did not do it",
            .misreported => "the guest was told something succeeded that did not, or the emulator was told about a capability the device does not have. The second is the worse one: the emulator will use it and the failure will surface somewhere unrelated",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .failing or self == .misreported or self == .degraded;
    }
};

pub const Matrix = struct {
    capabilities: [max_capabilities]Capability = [_]Capability{.{}} ** max_capabilities,
    capability_count: usize = 0,
    capabilities_dropped: u64 = 0,

    calls: [max_calls]Call = [_]Call{.{}} ** max_calls,
    call_count: usize = 0,
    call_write_index: usize = 0,
    calls_dropped: u64 = 0,
    total_calls: u64 = 0,

    failures: u64 = 0,
    result_disagreements: u64 = 0,
    by_operation: [operation_count]u64 = [_]u64{0} ** operation_count,
    guest_path_operations: u64 = 0,
    pixel_changing_fallbacks: u64 = 0,
    cost_only_fallbacks: u64 = 0,

    pub fn declare(self: *Matrix, capability: Capability) bool {
        if (self.capability_count >= max_capabilities) {
            self.capabilities_dropped +|= 1;
            return false;
        }
        self.capabilities[self.capability_count] = capability;
        self.capability_count += 1;
        return true;
    }

    pub fn forward(self: *Matrix, call: Call) *Call {
        self.total_calls +|= 1;
        self.by_operation[@intFromEnum(call.operation)] +|= 1;
        if (call.operation.onlyOnGuestPath()) self.guest_path_operations +|= 1;
        if (!call.succeeded()) self.failures +|= 1;
        if (call.resultsDisagree()) self.result_disagreements +|= 1;
        if (call.fallback != .none) {
            if (call.fallback.canChangePixels()) {
                self.pixel_changing_fallbacks +|= 1;
            } else {
                self.cost_only_fallbacks +|= 1;
            }
        }
        if (self.call_count >= max_calls) self.calls_dropped +|= 1;
        const slot = &self.calls[self.call_write_index];
        self.call_write_index = (self.call_write_index + 1) % max_calls;
        if (self.call_count < max_calls) self.call_count += 1;
        slot.* = call;
        return slot;
    }

    pub fn retainedCalls(self: *const Matrix) []const Call {
        return self.calls[0..self.call_count];
    }

    pub fn retainedCapabilities(self: *const Matrix) []const Capability {
        return self.capabilities[0..self.capability_count];
    }

    pub fn summary(self: *const Matrix) Summary {
        var out = Summary{
            .calls = self.total_calls,
            .retained = self.call_count,
            .dropped = self.calls_dropped,
            .failures = self.failures,
            .result_disagreements = self.result_disagreements,
            .pixel_changing_fallbacks = self.pixel_changing_fallbacks,
            .cost_only_fallbacks = self.cost_only_fallbacks,
            .by_operation = self.by_operation,
            .guest_path_operations = self.guest_path_operations,
            .capabilities = self.capability_count,
        };
        for (self.retainedCapabilities()) |capability| {
            if (capability.overAdvertised()) out.over_advertised +|= 1;
            if (capability.underAdvertised()) out.under_advertised +|= 1;
        }
        return out;
    }

    pub fn verdict(self: *const Matrix) Verdict {
        const totals = self.summary();
        if (totals.calls == 0 and totals.capabilities == 0) return .unobserved;
        if (totals.over_advertised != 0 or totals.result_disagreements != 0) return .misreported;
        if (totals.failures != 0) return .failing;
        if (totals.calls == 0) return .unobserved;
        if (!totals.guestPathExercised()) return .sink_only;
        if (totals.pixel_changing_fallbacks != 0) return .degraded;
        return .faithful;
    }

    pub fn fingerprint(self: *const Matrix) u64 {
        const totals = self.summary();
        var hash: u64 = totals.calls;
        hash = hash *% 31 +% totals.failures;
        hash = hash *% 31 +% totals.pixel_changing_fallbacks;
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

fn okCall(operation: Operation) Call {
    return .{ .operation = operation, .guest_result = 0, .native_result = 0, .source = .guest_authentic };
}

// The 2026-08-31 presenter state: every native call succeeding, and none of
// them on the route a guest frame takes.
test "a working sink is not a tested guest path" {
    var matrix = Matrix{};
    _ = matrix.forward(okCall(.acquire_next_image));
    _ = matrix.forward(okCall(.queue_submit));
    _ = matrix.forward(okCall(.queue_present));
    const verdict = matrix.verdict();
    try std.testing.expectEqual(Verdict.sink_only, verdict);
    try std.testing.expect(!matrix.summary().guestPathExercised());
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "says nothing about") != null);

    _ = matrix.forward(okCall(.copy_buffer_to_image));
    try std.testing.expectEqual(Verdict.faithful, matrix.verdict());
    try std.testing.expect(matrix.summary().guestPathExercised());
}

test "an over-advertised capability outranks every other verdict" {
    var matrix = Matrix{};
    _ = matrix.declare(.{ .name = "hostVisibleDeviceLocal", .advertised = true, .available = false, .used = true });
    _ = matrix.forward(okCall(.copy_buffer_to_image));
    const verdict = matrix.verdict();
    try std.testing.expectEqual(Verdict.misreported, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expectEqual(@as(u64, 1), matrix.summary().over_advertised);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "somewhere unrelated") != null);
}

test "an under-advertised capability costs a fallback and is not a defect" {
    var matrix = Matrix{};
    _ = matrix.declare(.{ .name = "hostVisibleDeviceLocal", .advertised = false, .available = true });
    var call = okCall(.map_memory);
    call.fallback = .extra_copy;
    _ = matrix.forward(call);
    try std.testing.expectEqual(@as(u64, 1), matrix.summary().under_advertised);
    try std.testing.expectEqual(@as(u64, 1), matrix.summary().cost_only_fallbacks);
    try std.testing.expectEqual(Verdict.faithful, matrix.verdict());
    try std.testing.expect(!Fallback.extra_copy.canChangePixels());
}

test "a format substitution degrades the frame without failing anything" {
    var matrix = Matrix{};
    var call = okCall(.create_image);
    call.fallback = .format_substitution;
    _ = matrix.forward(call);
    _ = matrix.forward(okCall(.copy_buffer_to_image));
    const verdict = matrix.verdict();
    try std.testing.expectEqual(Verdict.degraded, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expect(Fallback.format_substitution.canChangePixels());
    try std.testing.expectEqual(@as(u64, 0), matrix.summary().failures);
}

test "a guest told success over a native failure is misreported" {
    var matrix = Matrix{};
    var call = okCall(.queue_present);
    call.native_result = -1;
    _ = matrix.forward(call);
    try std.testing.expect(!call.succeeded());
    try std.testing.expect(call.resultsDisagree());
    try std.testing.expectEqual(Verdict.misreported, matrix.verdict());
    try std.testing.expectEqual(@as(u64, 1), matrix.summary().result_disagreements);
}

test "a native failure the guest was also told about is failing rather than misreported" {
    var matrix = Matrix{};
    var call = okCall(.queue_present);
    call.native_result = -1;
    call.guest_result = -1;
    _ = matrix.forward(call);
    try std.testing.expect(!call.resultsDisagree());
    try std.testing.expectEqual(Verdict.failing, matrix.verdict());
}

test "a transform that changes no content is visible in the record" {
    var matrix = Matrix{};
    var call = okCall(.copy_buffer_to_image);
    call.checksum_sampled = true;
    call.checksum_before = 0x1234;
    call.checksum_after = 0x1234;
    const recorded = matrix.forward(call);
    try std.testing.expect(!recorded.transformedContent());
    recorded.checksum_after = 0x5678;
    try std.testing.expect(recorded.transformedContent());
}

test "nothing forwarded is unobserved and the call window is a ring" {
    var matrix = Matrix{};
    try std.testing.expectEqual(Verdict.unobserved, matrix.verdict());
    var index: u64 = 0;
    while (index < max_calls + 5) : (index += 1) {
        _ = matrix.forward(okCall(.queue_submit));
    }
    try std.testing.expectEqual(max_calls, matrix.retainedCalls().len);
    try std.testing.expectEqual(@as(u64, 5), matrix.calls_dropped);
    try std.testing.expectEqual(@as(u64, max_calls + 5), matrix.summary().calls);
}

test "every operation and fallback states its own vocabulary" {
    inline for (@typeInfo(Operation).@"enum".fields) |field| {
        const which: Operation = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(Fallback).@"enum".fields) |field| {
        const which: Fallback = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    try std.testing.expect(Operation.copy_buffer_to_image.onlyOnGuestPath());
    try std.testing.expect(!Operation.queue_present.onlyOnGuestPath());
    try std.testing.expectEqual(@as(usize, 12), operation_count);
    try std.testing.expectEqual(@as(usize, 6), fallback_count);
}
