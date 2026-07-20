const std = @import("std");
const types = @import("types.zig");

pub const CpuReport = struct {
    host: types.FeatureSet,
    cleo_emulated: types.FeatureSet,

    pub fn canHostRunNeon(self: CpuReport) bool {
        return self.host.contains(.neon);
    }

    pub fn canEmulate(self: CpuReport, feature: types.Feature) bool {
        return self.cleo_emulated.contains(feature);
    }
};

pub fn detect() CpuReport {
    return .{
        .host = types.FeatureSet.host(),
        .cleo_emulated = types.FeatureSet.cleoEmulated(),
    };
}

pub fn hostFeatureMask() u64 {
    return detect().host.mask();
}

pub fn emulatedFeatureMask() u64 {
    return detect().cleo_emulated.mask();
}

test "CLEO CPU report exposes host and emulated masks" {
    const report = detect();
    try std.testing.expect(report.canEmulate(.sse));
    try std.testing.expect(report.canEmulate(.sse2));
    try std.testing.expect(report.cleo_emulated.mask() != 0);
}
