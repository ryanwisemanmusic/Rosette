//! x86-64-specific readiness facts for Xenia's host-side runtime path.
//!
//! The label ledger and `rel32` reach describe the code Xenia's Xbyak backend
//! emits. The guest is an x86-64 Mach-O image on every route, so those facts do
//! not change with the host build; only the route identity does.

const std = @import("std");

pub const host_architecture = "x86_64";
pub const host_codegen = "xbyak-x86_64";

pub const max_labels = 256;
pub const LabelId = u16;

pub const LabelState = struct {
    defined: bool = false,
    references: u32 = 0,
    address: u64 = 0,
};

pub const CodegenStatus = enum {
    ready,
    undefined_label,
    duplicate_label,
    invalid_reference,
};

pub const LabelLedger = struct {
    labels: [max_labels]LabelState = [_]LabelState{.{}} ** max_labels,
    label_count: u16 = 0,
    duplicate: bool = false,
    invalid: bool = false,

    pub fn reference(self: *LabelLedger, id: LabelId) bool {
        if (id >= max_labels) {
            self.invalid = true;
            return false;
        }
        self.labels[id].references +|= 1;
        self.label_count = @max(self.label_count, id + 1);
        return true;
    }

    pub fn define(self: *LabelLedger, id: LabelId, address: u64) bool {
        if (id >= max_labels) {
            self.invalid = true;
            return false;
        }
        if (self.labels[id].defined) {
            self.duplicate = true;
            return false;
        }
        self.labels[id].defined = true;
        self.labels[id].address = address;
        self.label_count = @max(self.label_count, id + 1);
        return true;
    }

    pub fn validate(self: *const LabelLedger) CodegenStatus {
        if (self.invalid) return .invalid_reference;
        if (self.duplicate) return .duplicate_label;
        for (self.labels[0..self.label_count]) |label| {
            if (label.references != 0 and !label.defined) return .undefined_label;
        }
        return .ready;
    }
};

pub fn rel32Displacement(from_end: u64, target: u64) ?i64 {
    if (target >= from_end) {
        const distance = target - from_end;
        if (distance > 0x7fff_ffff) return null;
        return @intCast(distance);
    }

    const distance = from_end - target;
    if (distance > 0x8000_0000) return null;
    return -@as(i64, @intCast(distance));
}

pub fn fitsRel32(from_end: u64, target: u64) bool {
    return rel32Displacement(from_end, target) != null;
}

pub const Frontier = enum {
    precompile_requested,
    shader_storage_requested,
    guest_main_ready,
    authentic_present,
};

pub const ActivationSample = struct {
    compile_green: bool,
    frontier: Frontier,
    current_step: u64,
    last_milestone_step: u64,
    precompile_cost_steps: u64,
    runnable_threads: u32,
    parked_threads: u32,
    wait_notifications: u64,
    gpu_aperture_writes: u64,
    ring_writes: u64,
};

pub const ActivationVerdict = enum {
    compile_not_green,
    precompile_progress,
    graphics_owner_silent,
    wait_notification_gap,
    gpu_producer_unreached,
    activation_ready,
};

pub fn classifyActivation(sample: ActivationSample) ActivationVerdict {
    if (!sample.compile_green) return .compile_not_green;
    if (sample.frontier == .authentic_present) return .activation_ready;
    if (sample.frontier == .precompile_requested and
        sample.current_step > sample.last_milestone_step)
    {
        return .precompile_progress;
    }
    if (sample.frontier == .shader_storage_requested and
        sample.gpu_aperture_writes == 0 and sample.ring_writes == 0)
    {
        if (sample.wait_notifications == 0 and sample.parked_threads != 0) return .wait_notification_gap;
        return .graphics_owner_silent;
    }
    if (sample.gpu_aperture_writes == 0 and sample.ring_writes == 0) return .gpu_producer_unreached;
    return .activation_ready;
}

test "package identity is the x86 Xbyak route" {
    try std.testing.expectEqualStrings("x86_64", host_architecture);
    try std.testing.expectEqualStrings("xbyak-x86_64", host_codegen);
}

test "the ledger rejects the undefined-label shape reported by Xbyak" {
    var ledger = LabelLedger{};
    try std.testing.expect(ledger.reference(11));
    try std.testing.expectEqual(CodegenStatus.undefined_label, ledger.validate());
    try std.testing.expect(ledger.define(11, 0x1000));
    try std.testing.expectEqual(CodegenStatus.ready, ledger.validate());
}

test "duplicate and out-of-range labels are never ready" {
    var ledger = LabelLedger{};
    try std.testing.expect(ledger.define(3, 0x2000));
    try std.testing.expect(!ledger.define(3, 0x3000));
    try std.testing.expectEqual(CodegenStatus.duplicate_label, ledger.validate());

    var invalid = LabelLedger{};
    try std.testing.expect(!invalid.reference(max_labels));
    try std.testing.expectEqual(CodegenStatus.invalid_reference, invalid.validate());
}

test "rel32 range uses the signed x86 displacement limits" {
    try std.testing.expectEqual(@as(i64, 0), rel32Displacement(0x1004, 0x1004).?);
    try std.testing.expectEqual(@as(i64, 0x7fff_ffff), rel32Displacement(0x1000, 0x8000_0fff).?);
    try std.testing.expectEqual(@as(i64, -0x8000_0000), rel32Displacement(0x8000_1000, 0x0000_1000).?);
    try std.testing.expect(!fitsRel32(0, 0x8000_0000));
}

test "the current x86 evidence is an activation owner gap, not a present" {
    const sample = ActivationSample{
        .compile_green = true,
        .frontier = .shader_storage_requested,
        .current_step = 500_000_000,
        .last_milestone_step = 368_560_915,
        .precompile_cost_steps = 227_509_982,
        .runnable_threads = 1,
        .parked_threads = 7,
        .wait_notifications = 0,
        .gpu_aperture_writes = 0,
        .ring_writes = 0,
    };
    try std.testing.expectEqual(ActivationVerdict.wait_notification_gap, classifyActivation(sample));
}
