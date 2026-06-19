const std = @import("std");
const cpu = @import("../../src/DOS/execution/cpu_state.zig");
const mem = @import("../../src/DOS/execution/segmented_memory.zig");
const interrupts = @import("../../src/DOS/execution/interrupt_services.zig");
const session = @import("../../src/DOS/execution/session.zig");
const bridge = @import("../../src/tooling/binary_converter/dos16_loader_bridge.zig");
const exporter = @import("../../src/tooling/binary_exporter/dos_mz_exporter.zig");
const host_mod = @import("../../src/DOS/execution/host_services.zig");

test "dos execution integration compiles bridge and exporter" {
    _ = cpu.CpuState{};
    _ = interrupts.InterruptServices;

    var host_state = host_mod.NoopHostState{};
    defer host_state.deinit(std.testing.allocator);

    const loader_bridge = bridge.Bridge.init(std.testing.allocator, host_state.adapter());
    var dos_session = try loader_bridge.loadCom("RET");
    defer dos_session.deinit();

    const image = try exporter.exportTinyMz(std.testing.allocator, "BODY");
    defer std.testing.allocator.free(image.bytes);

    try std.testing.expectEqual(@as(u16, 0x1000), dos_session.cpu.cs);
    try std.testing.expectEqual(@as(u8, 'M'), image.bytes[0]);
    try std.testing.expectEqual(@as(u8, 'Z'), image.bytes[1]);

    _ = mem.RealModeMemory;
    _ = session.Session;
}
