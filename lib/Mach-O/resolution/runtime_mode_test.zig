const std = @import("std");
const runtime_mode = @import("runtime_mode.zig");

test "runtime mode basic operations" {
    const allocator = std.testing.allocator;
    var config = runtime_mode.RuntimeModeConfig.init(allocator);
    defer config.deinit();
    
    // Test strict mode
    config.setMode(.strict);
    try std.testing.expect(!config.allowRepair("timer_cas"));
    
    // Test diagnostic mode
    config.setMode(.diagnostic);
    try std.testing.expect(config.allowRepair("timer_cas"));
    try config.recordRepair("timer_cas");
    try std.testing.expectEqual(@as(u64, 1), config.getRepairCount("timer_cas"));
    
    // Test repair limit
    try std.testing.expect(!config.allowRepair("timer_cas")); // Already at limit
    
    // Test compatibility mode
    config.setMode(.compatibility);
    config.apply_workarounds = true;
    try std.testing.expect(config.allowRepair("xbdm_assertion"));
}