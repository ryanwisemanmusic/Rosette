const std = @import("std");
const testing = std.testing;
const core = @import("core.zig");
const fixtures = @import("tests.zig");
const TestHarness = fixtures.TestHarness;
const TestState = fixtures.TestState;

test "pinned Xbox critical-section indirect transfers preserve call behavior" {
    var h = try TestHarness.init();
    defer h.deinit();
    const stack: u64 = 0x200;

    // The observer records call accounting but leaves stack ownership to the
    // ordinary translated call template and guest per-step hook.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0x1_4000_2000;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        state.image_targets_hooked = 0;
        state.xbox_critical_section_enter = 0x1_4000_2000;
        state.xbox_transfer_allowed = true;
        core.hookFilterAdd(&state.hook_filter, 0x1_4000_2000);
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u32, 0), state.hooked_transfer_calls);
        try testing.expectEqual(@as(u32, 1), state.xbox_transfer_calls);
        try testing.expectEqual(@as(u64, 0x1_4000_2000), state.xbox_transfer_target);
        try testing.expectEqual(@as(u64, 0xC002), state.xbox_transfer_return_rip);
        try testing.expectEqual(@as(u64, 0x1_4000_2000), state.regs.rip);
        try testing.expectEqual(stack - 8, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0xC002), std.mem.readInt(u64, state.memory[@intCast(stack - 8)..][0..8], .little));
    }

    // Differential mode keeps the unmodified interpreter transfer available.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0x1_4000_2000;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        state.image_targets_hooked = 0;
        state.xbox_critical_section_enter = 0x1_4000_2000;
        state.xbox_transfer_allowed = true;
        core.hookFilterAdd(&state.hook_filter, 0x1_4000_2000);
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.runWith(&state, .{ .xbox_critical_section_transfer_enabled = false });
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(@as(u32, 0), state.xbox_transfer_calls);
        try testing.expectEqual(stack, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0xC002), state.regs.rip);
    }

    // A declined leave observer hands the exact call to the interpreter.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0x1_4000_2000;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        state.image_targets_hooked = 0;
        state.xbox_critical_section_leave = 0x1_4000_2000;
        core.hookFilterAdd(&state.hook_filter, 0x1_4000_2000);
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.xbox_transfer_calls);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(stack, state.regs.rsp);
    }

    // An external pinned trampoline is recognized only on the cold code-cache
    // range-refusal edge, and still receives the standard call frame.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0x1_6000_2000;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        state.code_cache_low = 0xA000_0000;
        state.code_cache_high = 0xB000_0000;
        state.xbox_critical_section_leave = 0x1_6000_2000;
        state.xbox_transfer_allowed = true;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.xbox_transfer_calls);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u64, 0x1_6000_2000), state.regs.rip);
        try testing.expectEqual(stack - 8, state.regs.rsp);
    }
}
