//! Observed ownership and known capability gaps in the live Metal shader path.
//!
//! Xenia submits SPIR-V through Vulkan. When MoltenVK is the Vulkan driver,
//! The active Vulkan driver's SPIRV-Cross path owns SPIR-V-to-MSL translation; an offline
//! Rosette `.metal`/`.air`/`.metallib` cache does not participate in those
//! live pipelines. This ledger records that boundary and concrete failures
//! observed by Rosette without guessing at unsupported features.

const std = @import("std");

pub const TranslationPath = enum {
    unknown,
    vulkan_driver_spirv_to_msl,
    rosette_native_msl,
};

pub const CapabilityGap = enum {
    rectangle_cull_distance_output,
    rectangle_shader_driver_rejection,
};

pub const Ledger = struct {
    live_translation_path: TranslationPath = .unknown,
    spirv_modules_forwarded: u64 = 0,
    native_msl_modules: u64 = 0,
    gap_observations: [std.enums.values(CapabilityGap).len]u64 = [_]u64{0} ** std.enums.values(CapabilityGap).len,

    pub fn noteSpirvModule(self: *Ledger) void {
        self.spirv_modules_forwarded +|= 1;
        if (self.live_translation_path == .unknown) self.live_translation_path = .vulkan_driver_spirv_to_msl;
    }

    pub fn noteNativeMslModule(self: *Ledger) void {
        self.native_msl_modules +|= 1;
        self.live_translation_path = .rosette_native_msl;
    }

    pub fn noteGap(self: *Ledger, gap: CapabilityGap) void {
        self.gap_observations[@intFromEnum(gap)] +|= 1;
    }

    pub fn gapCount(self: *const Ledger, gap: CapabilityGap) u64 {
        return self.gap_observations[@intFromEnum(gap)];
    }
};

test "Metal health records the live translator owner and only observed gaps" {
    var ledger: Ledger = .{};
    try std.testing.expectEqual(TranslationPath.unknown, ledger.live_translation_path);
    try std.testing.expectEqual(@as(u64, 0), ledger.gapCount(.rectangle_cull_distance_output));

    ledger.noteSpirvModule();
    ledger.noteGap(.rectangle_cull_distance_output);
    ledger.noteGap(.rectangle_shader_driver_rejection);
    try std.testing.expectEqual(TranslationPath.vulkan_driver_spirv_to_msl, ledger.live_translation_path);
    try std.testing.expectEqual(@as(u64, 1), ledger.spirv_modules_forwarded);
    try std.testing.expectEqual(@as(u64, 1), ledger.gapCount(.rectangle_cull_distance_output));
    try std.testing.expectEqual(@as(u64, 1), ledger.gapCount(.rectangle_shader_driver_rejection));

    ledger.noteNativeMslModule();
    try std.testing.expectEqual(TranslationPath.rosette_native_msl, ledger.live_translation_path);
    try std.testing.expectEqual(@as(u64, 1), ledger.native_msl_modules);
}
