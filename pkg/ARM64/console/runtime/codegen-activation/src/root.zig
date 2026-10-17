//! ARM64-route readiness facts for Xenia's host-side runtime path.
//!
//! The label ledger and `rel32` reach describe the code Xenia's Xbyak backend
//! emits. The guest is an x86-64 Mach-O image on every route, so those facts do
//! not change with the host build; only the route identity does.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_codegen = "arm64-native-bridge";

pub const max_labels = 256;
pub const LabelId = u16;

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

test "package identity is the ARM64 native bridge route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("arm64-native-bridge", host_codegen);
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
