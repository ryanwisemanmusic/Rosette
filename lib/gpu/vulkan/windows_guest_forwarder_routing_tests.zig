//! Full Windows/SysV routing with CPU callbacks only.
const std = @import("std");
const P = @import("elf_processor_state");
const State = P.ElfState;
const Bridge = @import("windows_guest_forwarder").Bridge;
const route = @import("windows_guest_forwarder").route_memo;
const t = std.testing;
fn cpu() u64 {
    var value: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &value) == 0);
    return @as(u64, @intCast(value.sec)) * std.time.ns_per_s + @as(u64, @intCast(value.nsec));
}
fn create() !*State {
    const s = try t.allocator.create(State);
    s.* = State.init(t.allocator);
    s.windows_runtime_enabled = true;
    s.setParallelGuestExecution(true);
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    return s;
}
fn destroy(s: *State) void {
    s.setParallelGuestExecution(false);
    s.deinit();
    t.allocator.destroy(s);
}
test "PE Vulkan immutable route comparison through full adapter (ROSETTE_VULKAN_ROUTE_BENCH=1)" {
    const abi = @import("gpu").vulkan.abi;
    const Driver = struct {
        var calls: u64 = 0;
        fn draw(_: abi.CommandBuffer, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {
            calls += 1;
        }
        fn update(_: abi.Device, writes: u32, _: ?[*]const abi.WriteDescriptorSet, copies: u32, _: ?[*]const abi.CopyDescriptorSet) callconv(.c) void {
            std.debug.assert(writes == 0 and copies == 0);
            calls += 1;
        }
    };
    const bench = std.c.getenv("ROSETTE_VULKAN_ROUTE_BENCH") != null;
    const old = route.enabled;
    defer route.enabled = old;
    for ([_]bool{ false, true }) |update| {
        const s = try create();
        defer destroy(s);
        var bridge: Bridge = .{};
        defer bridge.deinit();
        bridge.library_token = 1;
        bridge.forwarder.guest_libraries[0] = .{ .token = 1, .virtual_vulkan = true };
        bridge.forwarder.real_vulkan.device = @ptrFromInt(0x100);
        bridge.forwarder.real_vulkan.command_buffer_map[0] = .{ .synthetic = 0x111, .real = 0x222 };
        bridge.forwarder.real_vulkan.fn_ptrs.cmd_draw = Driver.draw;
        bridge.forwarder.real_vulkan.fn_ptrs.update_descriptor_sets = Driver.update;
        const stack = s.guestAlloc(128, 16).?;
        s.write64(stack + 32, 0);
        const name = if (update) "vkUpdateDescriptorSets" else "vkCmdDraw";
        for (0..if (bench) @as(usize, 7) else 1) |pair| for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
            route.enabled = enabled;
            s.regs = .{ .rcx = if (update) 0x100 else 0x111, .rdx = if (update) 0 else 13, .r8 = if (update) 0 else 1, .r9 = 0, .rsp = stack, .r12 = 0xFADE, .rflags = 0xA47 };
            for (0..64) |_| try t.expect(bridge.dispatch(s, name, 0x9876));
            Driver.calls = 0;
            bridge.route_facts = .{};
            const n: u64 = if (bench) 100000 else 32;
            const start = cpu();
            for (0..n) |_| try t.expect(bridge.dispatch(s, name, 0x9876));
            const ns = cpu() - start;
            try t.expectEqual(n, Driver.calls);
            try t.expectEqual(@as(u64, 0xFADE), s.regs.r12);
            try t.expectEqual(stack, s.regs.rsp);
            try t.expectEqual(@as(u64, 0xA47), s.regs.rflags);
            try t.expectEqual(@as(u64, 0x9876), s.regs.rip);
            // Commands too: every name derives its route once (`route_memo.zig`).
            try t.expectEqual(if (enabled) n else 0, bridge.route_facts.hits);
            if (bench) std.debug.print("routing kind=route_{s} pair={d} enabled={} operations={d} cpu_ns={d} hits={d}\n", .{ if (update) "update" else "draw", pair, enabled, n, ns, bridge.route_facts.hits });
        };
    }
}
