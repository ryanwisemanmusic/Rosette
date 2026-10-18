const process = @import("../../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const BlockJitCallRefusal = __ProcessInternals._BlockJitCallRefusal;
const ChainStage = process.ChainStage;
const GUEST_MILESTONE_COUNT = process.GUEST_MILESTONE_COUNT;
const GUEST_OUTPUT_STAGE_COUNT = process.GUEST_OUTPUT_STAGE_COUNT;
const GuestSymbol = process.GuestSymbol;
const GuestSymbolResolver = process.GuestSymbolResolver;
const MEM_BASE = __ProcessInternals._MEM_BASE;
const WindowsAllocationDisposition = process.WindowsAllocationDisposition;
const WindowsAllocationRefusalReason = process.WindowsAllocationRefusalReason;
const block_jit = __ProcessInternals._block_jit;
const guest_address_space = __ProcessInternals._guest_address_space;
const isLiveWindowsGuestThread = __ProcessInternals._isLiveWindowsGuestThread;
const kernel_call_census = __ProcessInternals._kernel_call_census;
const log = __ProcessInternals._log;
const spin_anatomy = __ProcessInternals._spin_anatomy;
const std = __ProcessInternals._std;
const testing = std.testing;
const ui_draw_evidence = __ProcessInternals._ui_draw_evidence;
const x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const xenia_accelerator = __ProcessInternals._xenia_accelerator;
const xenia_clock_probe = __ProcessInternals._xenia_clock_probe;
const console_guest_milestone_map = __ProcessInternals._console_guest_milestone_map;
const console_kernel_shim_map = __ProcessInternals._console_kernel_shim_map;
const xenia_sha1_kernel_feed_body = __ProcessInternals._xenia_sha1_kernel_feed_body;
const ElfState = process.ElfState;

pub const TestSymbolTable = struct {
    const Entry = struct { address: u64, name: []const u8 };
    entries: []const Entry,

    fn resolve(context: *const anyopaque, address: u64, buffer: []u8) ?GuestSymbol {
        const self: *const TestSymbolTable = @ptrCast(@alignCast(context));
        var best: ?Entry = null;
        for (self.entries) |entry| {
            if (entry.address > address) continue;
            if (best == null or entry.address > best.?.address) best = entry;
        }
        const chosen = best orelse return null;
        const copied = @min(chosen.name.len, buffer.len);
        @memcpy(buffer[0..copied], chosen.name[0..copied]);
        return .{ .name = buffer[0..copied], .offset = address - chosen.address };
    }

    fn addressOf(context: *const anyopaque, name: []const u8) ?u64 {
        const self: *const TestSymbolTable = @ptrCast(@alignCast(context));
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.address;
        }
        return null;
    }

    pub fn resolver(self: *const TestSymbolTable) GuestSymbolResolver {
        return .{ .context = @ptrCast(self), .resolve = resolve };
    }

    /// A resolver that can also be asked for an address, which is what
    /// arming a milestone tracepoint needs.
    pub fn addressableResolver(self: *const TestSymbolTable) GuestSymbolResolver {
        return .{ .context = @ptrCast(self), .resolve = resolve, .address_of = addressOf };
    }
};

pub const MILESTONE_REFRESH = "_ZN2xe2ui9Presenter18RefreshGuestOutputEjjjjSt8functionIFbRNS1_25GuestOutputRefreshContextEEE";
pub const MILESTONE_SWAP = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor9IssueSwapEjjj";
const MILESTONE_PAINT = "_ZN2xe2ui9Presenter17PaintFromUIThreadEb";
const MILESTONE_REGISTER_AUDIO = "_ZN2xe3apu11AudioSystem14RegisterClientEjjPy";

test "Xenia clock witnesses resolve data symbols and observe mapped bytes without mutation" {
    var state = ElfState.initWithMemory(testing.allocator, 0x10000);
    defer state.deinit();
    const base: u64 = 0x6000_0000;
    try testing.expect(state.createWindowsVirtualAllocation(base, 0x1000));
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = base, .name = "_ZN2xe21guest_tick_frequency_E" },
        .{ .address = base + 8, .name = "_ZN2xe22last_guest_tick_count_E" },
        .{ .address = base + 16, .name = "_ZN2xe21last_host_tick_count_E" },
        .{ .address = base + 24, .name = "_ZN2xe17guest_tick_ratio_E" },
        .{ .address = base + 40, .name = "_ZN2xe18guest_time_scalar_E" },
        .{ .address = base + 48, .name = "_ZN5cvars16clock_no_scalingE" },
        .{ .address = base + 49, .name = "_ZN5cvars16clock_source_rawE" },
    } };
    state.installGuestSymbolResolver(table.addressableResolver(), 7, 100);
    state.write64(base, 50_000_000);
    state.write64(base + 8, 100_000_000);
    state.write64(base + 16, 2_000_000);
    state.write64(base + 24, 50);
    state.write64(base + 32, 1);
    state.write64(base + 40, @bitCast(@as(f64, 1)));
    state.write8(base + 48, 0);
    state.write8(base + 49, 1);
    const bytes_before = state.readMem128(base);
    const generation_before = state.windows_virtual_allocations[0].code_generation;
    const snapshot = xenia_clock_probe.Snapshot.read(&state, state.xenia_clock.symbols).?;
    try testing.expectEqual(@as(u64, 100_000_000), snapshot.guest_ticks);
    try testing.expectEqual(@as(u64, 50), snapshot.ratio_num);
    try testing.expect(snapshot.raw_source);
    try testing.expectEqual(.baseline, state.xenia_clock.observe(snapshot, 1).status);
    try testing.expectEqual(.stalled, state.xenia_clock.observe(snapshot, 1_000_000_001).status);
    try testing.expectEqual(generation_before, state.windows_virtual_allocations[0].code_generation);
    try testing.expectEqualSlices(u8, &bytes_before, &state.readMem128(base));
    state.write8(base + 48, 1);
    const bypassed = xenia_clock_probe.Snapshot.read(&state, state.xenia_clock.symbols).?;
    try testing.expectEqual(.bypassed, state.xenia_clock.observe(bypassed, 2_000_000_001).status);
    state.write8(base + 48, 2); // Invalid C++ bool is not a healthy default.
    try testing.expect(xenia_clock_probe.Snapshot.read(&state, state.xenia_clock.symbols) == null);
    var missing = state.xenia_clock.symbols;
    missing.frequency = null;
    try testing.expect(xenia_clock_probe.Snapshot.read(&state, missing) == null);
    missing.frequency = std.math.maxInt(u64) - 2;
    try testing.expect(xenia_clock_probe.Snapshot.read(&state, missing) == null);
}

const DrawableOwnerProbe = struct {
    var calls: u32 = 0;
    var owned: bool = false;

    fn hook(_: ?*anyopaque, owned_by_swapchain: c_int) callconv(.c) c_int {
        calls += 1;
        const requested = owned_by_swapchain != 0;
        const changed = requested != owned;
        owned = requested;
        return @intFromBool(changed);
    }
};

test "the CAMetalLayer drawable is handed over once, and only when a hook exists" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // No AppKit bridge in this binary: the call is a no-op that reports no
    // change, rather than a claim that the handover happened.
    try testing.expect(!state.setNativeMetalDrawableOwner(true));

    DrawableOwnerProbe.calls = 0;
    DrawableOwnerProbe.owned = false;
    state.windows_graphics.hooks.native_metal_drawable_owner = DrawableOwnerProbe.hook;

    // The first swapchain moves the ownership; every later one finds it
    // already moved, so a caller can log the transition once instead of on
    // every create.
    try testing.expect(state.setNativeMetalDrawableOwner(true));
    try testing.expect(!state.setNativeMetalDrawableOwner(true));
    try testing.expectEqual(@as(u32, 2), DrawableOwnerProbe.calls);
    try testing.expect(DrawableOwnerProbe.owned);
}

test "a resolver with no address lookup arms no milestones and says so" {
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = MILESTONE_REFRESH },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // The old resolver shape: names addresses, cannot be asked for one.
    state.installGuestSymbolResolver(table.resolver(), 1, 99);

    try testing.expectEqual(@as(u32, 0), state.guest_milestones_resolved);
    try testing.expect(!state.guestMilestoneArmed(MILESTONE_REFRESH));

    // Unarmed stages must not become the wall: an image Rosette cannot see
    // into is not a title that failed to start. What survives is the part of
    // the chain that reads Rosette's own counters, and that is where the
    // wall has to land.
    var observable: usize = 0;
    for (state.guestOutputChainStages()) |stage| {
        if (stage.observable) observable += 1;
    }
    try testing.expectEqual(@as(usize, 1), observable);
    const wall = state.guestOutputWall() orelse return error.ExpectedWall;
    try testing.expectEqualStrings("guest_present_carried_content", wall.name);
    try testing.expectEqualStrings("rosette:vulkan-bridge", wall.owner);
}

test "a milestone is counted when the guest calls its entry point" {
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = MILESTONE_REFRESH },
        .{ .address = 0x140002000, .name = MILESTONE_SWAP },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 2, 99);

    try testing.expectEqual(@as(u32, 2), state.guest_milestones_resolved);
    try testing.expect(state.guestMilestoneArmed(MILESTONE_REFRESH));
    try testing.expect(state.guestMilestoneArmed(MILESTONE_SWAP));
    // A symbol this image does not carry stays unarmed rather than reading
    // as a stage the guest never reached.
    try testing.expect(!state.guestMilestoneArmed(MILESTONE_PAINT));

    try testing.expectEqual(@as(u64, 0), state.guestMilestoneHitsNamed(MILESTONE_REFRESH));
    state.executed_steps = 1234;
    state.noteGuestMilestoneEntry(0x140001000);
    state.noteGuestMilestoneEntry(0x140001000);
    try testing.expectEqual(@as(u64, 2), state.guestMilestoneHitsNamed(MILESTONE_REFRESH));
    try testing.expectEqual(@as(u64, 1234), state.guest_milestone_first_step[
        console_guest_milestone_map.indexOf(MILESTONE_REFRESH).?
    ]);

    // The middle of a function is not its entry: a milestone counts calls,
    // not time spent.
    state.noteGuestMilestoneEntry(0x140001004);
    try testing.expectEqual(@as(u64, 2), state.guestMilestoneHitsNamed(MILESTONE_REFRESH));
    // An address nowhere near an armed one costs a filter test and nothing
    // else.
    state.noteGuestMilestoneEntry(0x140900000);
    try testing.expectEqual(@as(u64, 0), state.guestMilestoneHitsNamed(MILESTONE_SWAP));
}

const MILESTONE_VIDEO_MODE = "_ZN2xe6kernel8xboxkrnl16VdQueryVideoModeEPNS0_12X_VIDEO_MODEEb";
// The registered trampolines, which is what a title's kernel import resolves
// to. Arming `<Export>_entry` instead arms the forwarder the trampoline calls,
// and this build inlines those.
const SHIM_VIDEO_MODE = "_ZZN2xe6kernel4shim21ExportRegistrerHelperILNS1_14KernelModuleIdE0ELt458EvJEE14RegisterExportIXadL_ZNS0_8xboxkrnl22VdQueryVideoMode_entryEvEELj1EEEPNS_3cpu6ExportEPKcEN1X10TrampolineEPNSC_3ppc12PPCContext_sE";
const SHIM_SWAP = "_ZZN2xe6kernel4shim21ExportRegistrerHelperILNS1_14KernelModuleIdE0ELt444EvJEE14RegisterExportIXadL_ZNS0_8xboxkrnl12VdSwap_entryEvEELj1EEEPNS_3cpu6ExportEPKcEN1X10TrampolineEPNSC_3ppc12PPCContext_sE";
const SHIM_READ_FILE = "_ZZN2xe6kernel4shim21ExportRegistrerHelperILNS1_14KernelModuleIdE0ELt219EvJEE14RegisterExportIXadL_ZNS0_8xboxkrnl16NtReadFile_entryEvEELj1EEEPNS_3cpu6ExportEPKcEN1X10TrampolineEPNSC_3ppc12PPCContext_sE";

test "a busy diagnostic-only kernel export leaves the hook filter, and VdSwap keeps its hook" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.image_low = 0x1400_00000;
    state.image_high = 0x1430_00000;
    state.armGuestKernelShim(SHIM_VIDEO_MODE, 0x1409cb000);
    state.armGuestKernelShim(SHIM_SWAP, 0x1409cc000);
    state.publishBlockJitHookFilter();
    try testing.expect(block_jit.hookFilterHas(&state.block_jit_hook_filter, 0x1409cb000));
    try testing.expect(block_jit.hookFilterHas(&state.block_jit_hook_filter, 0x1409cc000));
    try testing.expectEqual(@as(?BlockJitCallRefusal, .kernel_census), state.blockJitCallRefusal(0x1409cb000));

    // One call short of the threshold, then the call that reaches it.
    for ([_]u64{ 0x1409cb000, 0x1409cc000 }) |address| {
        const slot = state.guest_kernel_calls.exportAt(address).?;
        @atomicStore(u64, &@constCast(slot).hits, kernel_call_census.saturation_calls - 1, .monotonic);
        state.noteGuestKernelCall(address);
    }
    // The video-mode query only ever counted: its hook is gone, so a
    // translated call stays translated and a direct one compiles natively.
    try testing.expect(state.guest_kernel_calls.saturatedAt(0x1409cb000));
    try testing.expect(!block_jit.hookFilterHas(&state.block_jit_hook_filter, 0x1409cb000) or
        block_jit.hookFilterBit(0x1409cb000) == block_jit.hookFilterBit(0x1409cc000));
    try testing.expectEqual(@as(?BlockJitCallRefusal, null), state.blockJitCallRefusal(0x1409cb000));
    // VdSwap is the presenter's boundary: pinned, still hooked.
    try testing.expect(!state.guest_kernel_calls.saturatedAt(0x1409cc000));
    try testing.expect(block_jit.hookFilterHas(&state.block_jit_hook_filter, 0x1409cc000));
    try testing.expectEqual(@as(?BlockJitCallRefusal, .kernel_census), state.blockJitCallRefusal(0x1409cc000));
    try testing.expectEqual(@as(u32, 1), state.guest_kernel_census_saturations);
}

test "a tail jump into a shim is the title asking, and is counted apart from a call" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.armGuestKernelShim(SHIM_SWAP, 0x1409cc000);
    state.executed_steps = 10;
    state.noteGuestKernelCall(0x1409cc000);
    state.executed_steps = 20;
    state.noteGuestKernelTailJump(0x1409cc000);

    try testing.expectEqual(@as(u64, 2), state.guest_kernel_calls.total_calls);
    // Which instruction reached the handler is the translator's business, so
    // it is reported separately rather than folded into the title's count.
    try testing.expectEqual(@as(u64, 1), state.guest_kernel_calls.tail_jump_entries);
    try testing.expectEqual(@as(u64, 2), state.guest_kernel_calls.hitsFor("VdSwap"));
    // A jump to something unarmed costs the range check and nothing more.
    state.noteGuestKernelTailJump(0x7fff00000000);
    try testing.expectEqual(@as(u64, 2), state.guest_kernel_calls.total_calls);
    try testing.expectEqual(@as(u64, 1), state.guest_kernel_calls.tail_jump_entries);
}

test "the kernel census counts what the title asked the kernel for, and nothing else" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // The loader offers the whole symbol table; recognising a shim is this
    // module's job and nothing upstream filters for it.
    state.armGuestKernelShim(SHIM_VIDEO_MODE, 0x1409cb000);
    state.armGuestKernelShim(SHIM_READ_FILE, 0x1409ce000);
    state.armGuestKernelShim(MILESTONE_VIDEO_MODE, 0x1409caf00);
    state.armGuestKernelShim("_ZN2xe3gpu16CommandProcessor10InitializeEv", 0x1401c7e30);
    try testing.expectEqual(@as(u32, 2), state.guest_kernel_calls.armed);
    try testing.expectEqual(@as(u64, 4), state.guest_kernel_symbols_offered);

    // The implementation is armed as a milestone, never as a kernel call:
    // Xenia reaches it on its own and counting that as the title's act is
    // exactly the confusion this census exists to remove.
    try testing.expect(!state.guest_kernel_calls.isArmed("VdQueryVideoMode_entry"));
    try testing.expect(state.guest_kernel_calls.isArmed("VdQueryVideoMode"));
    try testing.expectEqual(@as(u32, 2), state.guest_kernel_calls.armed_trampolines);

    state.windows_guest_threads[0] = .{ .status = .runnable, .handle = 0x1d0 };
    state.windows_active_guest_thread_slot = 0;
    state.executed_steps = 5000;
    state.noteGuestKernelCall(0x1409caf00); // the implementation: not a shim
    try testing.expectEqual(@as(u64, 0), state.guest_kernel_calls.total_calls);
    state.noteGuestKernelCall(0x1409cb000);
    state.executed_steps = 6000;
    state.noteGuestKernelCall(0x1409cb000);

    try testing.expectEqual(@as(u64, 2), state.guest_kernel_calls.total_calls);
    try testing.expectEqual(@as(u32, 1), state.guest_kernel_calls.distinct_entered);
    try testing.expectEqual(@as(u64, 2), state.windows_guest_threads[0].kernel_calls);
    try testing.expectEqual(@as(u64, 6000), state.windows_guest_threads[0].last_kernel_step);
    const last = state.guest_kernel_calls.slotAt(state.windows_guest_threads[0].last_kernel_slot).?;
    try testing.expectEqualStrings("VdQueryVideoMode", last.export_name);
    // One graphics call places the title in display-query and no further.
    try testing.expectEqual(
        console_kernel_shim_map.BootPhase.display_query,
        state.guest_kernel_calls.furthest_phase,
    );
}

test "a stage is met by its shim witness when the implementation was inlined away" {
    // The exact shape of the 2026-09-12 wall. `VdQueryVideoMode` the
    // implementation is armed and reads zero; `VdQueryVideoMode_entry` the
    // shim is what the title calls. If the one call between them is inlined,
    // reading only the implementation reports a title that never asked.
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x1409caf00, .name = MILESTONE_VIDEO_MODE },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 1, 99);
    state.armGuestKernelShim(SHIM_VIDEO_MODE, 0x1409cb000);

    const before = state.guestOutputChainStages()[6];
    try testing.expectEqualStrings("title_queried_video_mode", before.name);
    try testing.expect(!before.met);
    try testing.expect(before.witness_armed);
    try testing.expectEqual(@as(u64, 0), before.witness_value);
    // The guidance is what replaced `unmet (downstream of the wall)`, and a
    // stage with none of it is a stage a reader cannot act on.
    try testing.expect(before.when_unmet.len != 0);

    state.executed_steps = 900;
    state.noteGuestKernelCall(0x1409cb000);
    const after = state.guestOutputChainStages()[6];
    try testing.expect(after.met);
    try testing.expectEqual(@as(u64, 1), after.witness_value);
    // The implementation still reads zero, and that disagreement is the
    // finding rather than a contradiction to hide.
    try testing.expectEqual(@as(u64, 0), after.value);
    try testing.expect(std.mem.indexOf(u8, after.witness, "VdQueryVideoMode") != null);
}

test "an unarmed shim witness is never read as a title that did not call" {
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x1409caf00, .name = MILESTONE_VIDEO_MODE },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 1, 99);
    // Nothing armed: an image without the shim cannot say whether the title
    // called it, and a zero from it is a fact about the image.
    const stage = state.guestOutputChainStages()[6];
    try testing.expect(!stage.witness_armed);
    try testing.expectEqual(@as(u64, 0), stage.witness_value);
    // The stage is still observable, because its primary witness is armed.
    try testing.expect(stage.observable);
    try testing.expect(!stage.met);
}

test "the guest code progress axis separates a title advancing from one looping" {
    const define = "_ZN2xe3cpu3ppc11PPCFrontend14DefineFunctionEPNS0_13GuestFunctionEj";
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140300000, .name = define },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 1, 99);
    try testing.expect(state.guestMilestoneArmed(define));

    state.executed_steps = 1000;
    state.noteGuestMilestoneEntry(0x140300000);
    state.executed_steps = 1100;
    state.noteGuestMilestoneEntry(0x140300000);

    const activity = state.guestMilestoneActivity(define);
    try testing.expectEqual(@as(u64, 2), activity.hits);
    // Last step, not first: a count that has stopped rising and a count that
    // is still rising are the opposite conclusions, and only the last step
    // separates them.
    try testing.expectEqual(@as(u64, 1100), activity.last_step);
    try testing.expect(activity.armed);

    // A translation is a stage a spin cannot advance, which is the whole
    // reason it is the title's progress axis.
    state.executed_steps = 1_000_000;
    try testing.expectEqual(@as(u64, 1100), state.guestMilestoneActivity(define).last_step);

    const unarmed = state.guestMilestoneActivity("_ZN2xe3cpu9Processor15ResolveFunctionEj");
    try testing.expect(!unarmed.armed);
    try testing.expectEqual(@as(u64, 0), unarmed.hits);
}

test "the guest output chain resolves GPU bring-up on both sides of the ring" {
    // The 2026-09-12 chain jumped from "a title thread started" straight to
    // "the title gave the GPU a ring", so a title that had not yet asked the
    // kernel about its display and a title stuck halfway through bring-up
    // produced the same verdict. These stages are the steps in between, and
    // they are ordered: Xenia's consumer first, then the title's own acts.
    const order = [_][]const u8{
        "vulkan_backend_chosen",
        "gpu_command_processor_up",
        "gpu_thread_reading",
        "display_clock_ticking",
        "emulator_launched",
        "title_thread_started",
        "title_queried_video_mode",
        "title_took_gpu_interrupt",
        "title_gave_gpu_a_ring",
        "ring_carried_work",
        "ring_carried_pm4",
        "title_requested_swap",
        "guest_output_published",
        "guest_present_carried_content",
        "paints_are_repeating",
    };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const stages = state.guestOutputChainStages();
    try testing.expectEqual(order.len, stages.len);
    for (stages, order) |stage, expected| {
        try testing.expectEqualStrings(expected, stage.name);
    }

    // The two Xenia-side stages belong to Xenia; the four title-side ones to
    // the title. An owner is what decides where a reader looks next, so a row
    // filed under the wrong one sends them to the wrong code.
    for (stages) |stage| {
        if (std.mem.eql(u8, stage.name, "gpu_command_processor_up")) {
            try testing.expectEqualStrings("xenia:emulator", stage.owner);
        }
        if (std.mem.eql(u8, stage.name, "gpu_thread_reading")) {
            try testing.expectEqualStrings("xenia:gpu-thread", stage.owner);
        }
        if (std.mem.eql(u8, stage.name, "title_queried_video_mode") or
            std.mem.eql(u8, stage.name, "title_took_gpu_interrupt"))
        {
            try testing.expectEqualStrings("guest-title", stage.owner);
        }
    }
}

test "a thread's code window separates a spin from progress" {
    // `Main XThread` held a fifth of the 2026-09-12 run at one JIT address
    // and nothing in the report could say whether the title was working or
    // spinning - which is the only question left once the wall belongs to it.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const spinning = &state.windows_guest_threads[1];
    spinning.* = .{ .status = .runnable, .handle = 0x10 };
    const working = &state.windows_guest_threads[2];
    working.* = .{ .status = .runnable, .handle = 0x11 };

    // A tight loop: every sample lands in the same 4 KiB page.
    for (0..spin_anatomy.minimum_samples * 2) |step| {
        spinning.code.sample(0xA0026000 + (step % 24) * 4);
    }
    try testing.expectEqual(@as(u32, 1), spinning.codePages());
    try testing.expect(spinning.codeSpan() < 4096);
    try testing.expect(spinning.code.isSpin());

    // Work in progress: samples spread across many pages.
    for (0..spin_anatomy.minimum_samples * 2) |step| {
        working.code.sample(0xA0100000 + step * 0x1000);
    }
    try testing.expect(working.codePages() > 8);
    try testing.expect(working.codeSpan() > 4096 * 8);
    try testing.expect(!working.code.isSpin());

    // Rolling the window keeps the previous one, so a thread that has just
    // been resumed is not reported as stuck on the strength of two samples.
    const before = working.codePages();
    state.rollGuestThreadCodeWindows();
    try testing.expectEqual(@as(u64, 0), working.code.recent_samples);
    try testing.expectEqual(before, working.codePages());

    // A thread that has never been sampled claims nothing.
    const untouched = &state.windows_guest_threads[3];
    untouched.* = .{ .status = .runnable, .handle = 0x12 };
    try testing.expectEqual(@as(u64, 0), untouched.codeSpan());
    try testing.expectEqual(@as(u32, 0), untouched.codePages());
    try testing.expect(!untouched.code.isSpin());
}

test "an inlined-away milestone is unobservable, not unmet" {
    // The 2026-09-12 image inlined `GraphicsSystem::MarkVblank` into the
    // frame limiter lambda in `GraphicsSystem::Setup`. Its out-of-line body
    // at 0x1401b7380 is byte-for-byte the inlined sequence and nothing in
    // 18 MB of .text branches to it, so the armed tracepoint counted zero
    // for 4.6 billion instructions. The chain called that "the display clock
    // is stopped", made it the wall of the entire guest-output chain, and
    // attributed eight downstream stages to a cause that did not exist.
    const vblank = "_ZN2xe3gpu14GraphicsSystem10MarkVblankEv";
    const dpc = "_ZN2xe6kernel11KernelState21EmulateCPInterruptDPCEjjjj";
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = "_ZN2xe8Emulator14CompleteLaunchERKNSt10filesystem7__cxx114pathESt17basic_string_viewIcSt11char_traitsIcEE" },
        .{ .address = 0x140002000, .name = "_ZN2xe6kernel7XThread7ExecuteEv" },
        .{ .address = 0x1401b7380, .name = vblank },
        .{ .address = 0x1400f9330, .name = dpc },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 4, 99);

    // Before the census has run, nothing may be called inlined: an all-zero
    // column is indistinguishable from a route that never counted.
    try testing.expect(!state.guestMilestoneInlinedAway(vblank));

    var counts = [_]u32{0} ** GUEST_MILESTONE_COUNT;
    // The witness is called; the vblank body is not.
    counts[console_guest_milestone_map.indexOf(dpc).?] = 2;
    state.noteGuestMilestoneCallSites(&counts);

    try testing.expect(state.guestMilestoneInlinedAway(vblank));
    try testing.expect(!state.guestMilestoneInlinedAway(dpc));
    try testing.expectEqual(ElfState.MilestoneReach.unreachable_inlined, state.guestMilestoneReach(vblank));
    try testing.expectEqual(ElfState.MilestoneReach.direct, state.guestMilestoneReach(dpc));

    // With neither entered yet the stage is still observable - through the
    // witness - and simply unmet.
    try testing.expect(state.guestMilestoneStageObservable(vblank));
    try testing.expectEqual(@as(u64, 0), state.guestMilestoneStageHits(vblank));

    state.noteGuestMilestoneEntry(0x140001000);
    state.noteGuestMilestoneEntry(0x140002000);
    // The frame limiter raises a CP interrupt on each vertical blank. The
    // inlined copy calls the same function the out-of-line one would.
    state.noteGuestMilestoneEntry(0x1400f9330);
    state.noteGuestMilestoneEntry(0x1400f9330);
    state.noteGuestMilestoneEntry(0x1400f9330);

    try testing.expectEqual(@as(u64, 0), state.guestMilestoneHitsNamed(vblank));
    try testing.expectEqual(@as(u64, 3), state.guestMilestoneStageHits(vblank));

    var display_clock: ?ChainStage = null;
    for (state.guestOutputChainStages()) |stage| {
        if (std.mem.eql(u8, stage.name, "display_clock_ticking")) display_clock = stage;
    }
    const stage = display_clock orelse return error.ExpectedStage;
    try testing.expect(stage.met);
    try testing.expectEqual(@as(u64, 3), stage.value);
    // The report has to say which witness supplied the count, or a met stage
    // beside `MarkVblank_entries=0` reads as a contradiction.
    try testing.expect(std.mem.indexOf(u8, stage.evidence, "EmulateCPInterruptDPC") != null);

    // And the wall moves off `display_clock_ticking`, which is the whole
    // point: with the display clock proven to be ticking, the earliest thing
    // the run has not shown is downstream of it and belongs to someone else.
    const wall = state.guestOutputWall() orelse return error.ExpectedWall;
    try testing.expect(!std.mem.eql(u8, wall.name, "display_clock_ticking"));
    try testing.expect(!std.mem.eql(u8, wall.owner, "xenia:emulator"));
}

test "a virtual function has no call site either, and its zero is the guest" {
    // The 2026-09-12 census reported `GraphicsSystem::InitializeRingBuffer`,
    // `CommandProcessor::ExecutePrimaryBuffer` and `SDLAudioDriver::Initialize`
    // as inlined away. All three are `virtual`; their addresses sit in
    // `.rdata` vtables (4, 2 and 1 references in that image) and none of them
    // had been called. Two guest-output stages went from a finding to
    // `unobservable` because a missing call site was read as unreachable.
    const ring = "_ZN2xe3gpu14GraphicsSystem20InitializeRingBufferEjj";
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = "_ZN2xe8Emulator14CompleteLaunchERKNSt10filesystem7__cxx114pathESt17basic_string_viewIcSt11char_traitsIcEE" },
        .{ .address = 0x1401b72c0, .name = ring },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 2, 99);

    var call_sites = [_]u32{0} ** GUEST_MILESTONE_COUNT;
    state.noteGuestMilestoneCallSites(&call_sites);
    // With only the call-site column, it looks deleted.
    try testing.expectEqual(ElfState.MilestoneReach.unreachable_inlined, state.guestMilestoneReach(ring));

    var data_refs = [_]u32{0} ** GUEST_MILESTONE_COUNT;
    data_refs[console_guest_milestone_map.indexOf(ring).?] = 4;
    state.noteGuestMilestoneDataReferences(&data_refs);

    // With the vtable column it is an indirect target that was never called,
    // which is a fact about the title.
    try testing.expectEqual(ElfState.MilestoneReach.indirect, state.guestMilestoneReach(ring));
    try testing.expect(!state.guestMilestoneInlinedAway(ring));
    try testing.expect(state.guestMilestoneStageObservable(ring));

    var found = false;
    for (state.guestOutputChainStages()) |stage| {
        if (!std.mem.eql(u8, stage.name, "title_gave_gpu_a_ring")) continue;
        found = true;
        try testing.expect(stage.observable);
        try testing.expect(!stage.met);
    }
    try testing.expect(found);

    // And an entry recorded against an address both scans called unreachable
    // settles it in favour of the run: the guest got there, so the analysis
    // is what is wrong.
    var none = [_]u32{0} ** GUEST_MILESTONE_COUNT;
    state.noteGuestMilestoneDataReferences(&none);
    try testing.expectEqual(ElfState.MilestoneReach.unreachable_inlined, state.guestMilestoneReach(ring));
    state.noteGuestMilestoneEntry(0x1401b72c0);
    try testing.expectEqual(ElfState.MilestoneReach.indirect, state.guestMilestoneReach(ring));
}

test "the guest-output chain counts Vulkan command-processor overrides" {
    const primary = "_ZN2xe3gpu16CommandProcessor20ExecutePrimaryBufferEjj";
    const primary_vulkan = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor20ExecutePrimaryBufferEjj";
    const packet = "_ZN2xe3gpu16CommandProcessor18ExecutePacketType3Ej";
    const packet_vulkan = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType3Ej";
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140a453b0, .name = primary_vulkan },
        .{ .address = 0x140a438d0, .name = packet_vulkan },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 2, 99);

    // The virtual call in WorkerThreadMain selects the Vulkan overrides; the
    // base rows remain at zero even though the GPU did consume work.
    state.executed_steps = 100;
    state.noteGuestMilestoneEntry(0x140a453b0);
    state.executed_steps = 200;
    state.noteGuestMilestoneEntry(0x140a438d0);
    try testing.expectEqual(@as(u64, 0), state.guestMilestoneHitsNamed(primary));
    try testing.expectEqual(@as(u64, 1), state.guestMilestoneHitsNamed(primary_vulkan));
    try testing.expectEqual(@as(u64, 0), state.guestMilestoneHitsNamed(packet));
    try testing.expectEqual(@as(u64, 1), state.guestMilestoneHitsNamed(packet_vulkan));

    const stages = state.guestOutputChainStages();
    for (stages) |stage| {
        if (std.mem.eql(u8, stage.name, "ring_carried_work")) {
            try testing.expect(stage.met);
            try testing.expect(stage.observable);
            try testing.expectEqual(@as(u64, 1), stage.value);
        }
        if (std.mem.eql(u8, stage.name, "ring_carried_pm4")) {
            try testing.expect(stage.met);
            try testing.expect(stage.observable);
            try testing.expectEqual(@as(u64, 1), stage.value);
        }
    }
}

test "an inlined milestone with no witness is skipped by the wall search" {
    // Same shape, but the image does not contain the witness either. The
    // stage is then genuinely unobservable and must be stepped over rather
    // than blamed: an unreachable symbol reads zero whatever the guest does.
    const vblank = "_ZN2xe3gpu14GraphicsSystem10MarkVblankEv";
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = "_ZN2xe8Emulator14CompleteLaunchERKNSt10filesystem7__cxx114pathESt17basic_string_viewIcSt11char_traitsIcEE" },
        .{ .address = 0x1401b7380, .name = vblank },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 2, 99);
    var counts = [_]u32{0} ** GUEST_MILESTONE_COUNT;
    state.noteGuestMilestoneCallSites(&counts);

    try testing.expect(!state.guestMilestoneStageObservable(vblank));
    for (state.guestOutputChainStages()) |stage| {
        if (!std.mem.eql(u8, stage.name, "display_clock_ticking")) continue;
        try testing.expect(!stage.observable);
        try testing.expect(std.mem.indexOf(u8, stage.unobservable_reason, "inlined") != null);
    }
    const wall = state.guestOutputWall() orelse return error.ExpectedWall;
    try testing.expect(!std.mem.eql(u8, wall.name, "display_clock_ticking"));
}

test "every import answer is judged, not only the ones a handler remembered to record" {
    // The 2026-09-12 run answered roughly ninety thousand imports and its
    // refusal ledger held one line - the single name that had been wired by
    // hand. A refusal is a property of the value against the convention, so
    // classifying the value catches every handler, including ones written
    // after the classifier.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x500;

    // A hand-written handler: the COM completeness path answers this one
    // itself and never touched the ledger before.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ole32.dll", "CoCreateInstance", return_rip));
    try testing.expectEqual(@as(u64, 0x8000_4002), state.regs.rax);

    const ledger = &state.windows_import_refusals;
    try testing.expectEqual(@as(usize, 1), ledger.count);
    try testing.expectEqualStrings("CoCreateInstance", ledger.entries[0].name());
    try testing.expectEqual(@as(u64, 0x8000_4002), ledger.entries[0].value);
    try testing.expect(state.windows_import_refusal_events >= 1);

    // A registry probe that legitimately reports absence is a refusal too:
    // ERROR_FILE_NOT_FOUND is what the guest branches on.
    const absent_key = "Software\\Absent";
    @memcpy(state.guestMemory(MEM_BASE + 0xD00, absent_key.len + 1).?[0..absent_key.len], absent_key);
    state.write8(MEM_BASE + 0xD00 + absent_key.len, 0);
    state.regs = .{};
    state.regs.rcx = 0xFFFF_FFFF_8000_0001;
    state.regs.rdx = MEM_BASE + 0xD00;
    state.regs.r8 = MEM_BASE + 0xD80;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ADVAPI32.dll", "RegOpenKeyA", return_rip));
    try testing.expectEqual(@as(usize, 2), ledger.count);

    // And the calls whose convention is only a guess are counted but never
    // judged. A wait that succeeds returns WAIT_OBJECT_0, which is zero;
    // reporting that as a refusal would drown the two rows above.
    const unjudged_before = state.windows_import_answers_unjudged;
    state.regs = .{};
    state.regs.rcx = 0;
    state.regs.rdx = 0;
    _ = x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "WaitForSingleObject", return_rip);
    try testing.expect(state.windows_import_answers_unjudged > unjudged_before);
    try testing.expectEqual(@as(usize, 2), ledger.count);
}

test "a spinning thread's last boundary and its code's producer are both recorded" {
    // The two questions that follow "this thread is spinning": what was it in
    // the middle of, and whose code is it running. Neither had an answer on
    // the 2026-09-12 run - `Main XThread` reported a bare `at=<unnamed>`.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_guest_threads[1] = .{ .status = .runnable, .handle = 0x1d0 };
    state.windows_active_guest_thread_slot = 1;
    const thread = &state.windows_guest_threads[1];
    try testing.expectEqualStrings("", thread.lastImportText());

    state.executed_steps = 4242;
    state.noteWindowsThreadImport("NtWaitForSingleObject");
    try testing.expectEqualStrings("NtWaitForSingleObject", thread.lastImportText());
    try testing.expectEqual(@as(u64, 4242), thread.last_import_step);
    try testing.expectEqual(@as(u64, 1), thread.import_calls);

    // The code it is running is labelled by whoever allocated it, because a
    // translator's first page holds its dispatch thunks and a thread going
    // round inside those is not running the title's code at all.
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140f00000, .name = "_ZN2xe3cpu7backend3x6412X64CodeCache12AllocateCodeEv" },
    } };
    state.installGuestSymbolResolver(table.addressableResolver(), 1, 99);
    state.noteGuestExecutableAllocationFrom(0xa0000000, 0x10000, 0x40, 0x140f00010);
    var buffer: [160]u8 = undefined;
    const described = state.describeGuestAddressOrUnnamed(0xa000044b, &buffer);
    try testing.expect(std.mem.startsWith(u8, described, "generated-code:"));
    try testing.expect(std.mem.indexOf(u8, described, "X64CodeCache") != null);

    // A data allocation is still refused a region, whatever asked for it: a
    // rip in one is a control-flow escape, and labelling it generated code
    // would bury exactly that. Asserted against the map rather than the
    // rendered text, because the test's symbol table answers for every
    // address above its one entry.
    state.noteGuestExecutableAllocationFrom(0x280d00000, 0x10000, 0x04, 0x140f00010);
    try testing.expect(state.guest_regions.find(0x280d00000) == null);
    try testing.expect(!state.guest_regions.isExecutable(0x280d00000));
}

test "a witness milestone's entries are split by the call site they came from" {
    // `EmulateCPInterruptDPC` stands in for the inlined `MarkVblank` and is
    // reached from four places in the image, so its total is a superset of
    // the vblank count. Reading the total as the display rate made a limiter
    // written for 60 Hz appear to tick at 95.
    const dpc = "_ZN2xe6kernel11KernelState21EmulateCPInterruptDPCEjjjj";
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x1400f9330, .name = dpc },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 1, 99);
    const index = console_guest_milestone_map.indexOf(dpc).?;

    // The frame limiter's inlined vblank.
    state.last_instruction_rip = 0x1401b82e4;
    for (0..60) |_| state.noteGuestMilestoneEntry(0x1400f9330);
    // And a different producer.
    state.last_instruction_rip = 0x1401b73a7;
    for (0..5) |_| state.noteGuestMilestoneEntry(0x1400f9330);

    try testing.expectEqual(@as(u64, 65), state.guestMilestoneHitsNamed(dpc));
    try testing.expectEqual(@as(u64, 0x1401b82e4), state.guest_milestone_callers[index][0]);
    try testing.expectEqual(@as(u64, 60), state.guest_milestone_caller_hits[index][0]);
    try testing.expectEqual(@as(u64, 0x1401b73a7), state.guest_milestone_callers[index][1]);
    try testing.expectEqual(@as(u64, 5), state.guest_milestone_caller_hits[index][1]);
    try testing.expectEqual(@as(u64, 0), state.guest_milestone_caller_overflow[index]);

    // More producers than slots is reported rather than silently folded into
    // whichever four arrived first.
    for (0..4) |extra| {
        state.last_instruction_rip = 0x1409cb000 + extra * 0x10;
        state.noteGuestMilestoneEntry(0x1400f9330);
    }
    try testing.expect(state.guest_milestone_caller_overflow[index] != 0);
}

test "the guest gets to name its own threads" {
    // Fifteen live workers, four of them holding four fifths of the run, and
    // every line in the report was a handle and a mangled symbol. Xenia calls
    // `SetThreadDescription` for each one; Rosette answered S_OK and dropped
    // the string, so identifying the GPU frame limiter meant disassembling
    // the image.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_guest_threads[3] = .{ .status = .runnable, .handle = 0x1d0 };
    state.windows_guest_threads[4] = .{ .status = .runnable, .handle = 0x22 };

    try testing.expect(state.setWindowsGuestThreadName(0x1d0, "GPU Frame limiter"));
    try testing.expectEqualStrings("GPU Frame limiter", state.windows_guest_threads[3].nameText());
    try testing.expectEqualStrings("", state.windows_guest_threads[4].nameText());

    // A control byte in the name would land straight in a log line.
    const noisy = [_]u8{ 'A', 'u', 'd', 'i', 'o', 0x07, 'W', 'o', 'r', 'k', 'e', 'r' };
    try testing.expect(state.setWindowsGuestThreadName(0x22, &noisy));
    try testing.expectEqualStrings("Audio?Worker", state.windows_guest_threads[4].nameText());

    // An empty name is not a name, and a handle nothing owns falls back to
    // whichever worker is executing - which is what the GetCurrentThread
    // pseudo-handle means under a cooperative scheduler.
    try testing.expect(!state.setWindowsGuestThreadName(0x1d0, ""));
    state.windows_active_guest_thread_slot = null;
    try testing.expect(!state.setWindowsGuestThreadName(std.math.maxInt(u64) - 1, "Main"));
    state.windows_active_guest_thread_slot = 4;
    try testing.expect(state.setWindowsGuestThreadName(std.math.maxInt(u64) - 1, "Main"));
    try testing.expectEqualStrings("Main", state.windows_guest_threads[4].nameText());

    // A wait on another thread's handle is annotated with that thread's own
    // name and status, so a wait graph reads as names rather than as handles
    // a reader has to cross-reference by hand.
    state.windows_active_guest_thread_slot = null;
    var buffer: [96]u8 = undefined;
    const described = state.describeWindowsWaitTarget(0x1d0, &buffer);
    try testing.expect(std.mem.indexOf(u8, described, "GPU Frame limiter") != null);
    try testing.expect(std.mem.indexOf(u8, described, "runnable") != null);
    // A handle that is not a thread is left alone rather than guessed at.
    try testing.expectEqualStrings("", state.describeWindowsWaitTarget(0x4242, &buffer));
    try testing.expectEqualStrings("", state.describeWindowsWaitTarget(0, &buffer));
}

test "the guest output chain names the title, not the bridge, when nothing was drawn" {
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = "_ZN2xe8Emulator14CompleteLaunchERKNSt10filesystem7__cxx114pathESt17basic_string_viewIcSt11char_traitsIcEE" },
        .{ .address = 0x140002000, .name = "_ZN2xe6kernel7XThread7ExecuteEv" },
        .{ .address = 0x140003000, .name = MILESTONE_SWAP },
        .{ .address = 0x140004000, .name = MILESTONE_REFRESH },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 4, 99);

    state.noteGuestMilestoneEntry(0x140001000);
    state.noteGuestMilestoneEntry(0x140002000);

    // The 2026-09-12 shape: the emulator launched, a title thread ran, and
    // the title never asked for a swap. The wall has to land on the title.
    const wall = state.guestOutputWall() orelse return error.ExpectedWall;
    try testing.expectEqualStrings("title_requested_swap", wall.name);
    try testing.expectEqualStrings("guest-title", wall.owner);

    // Once the title swaps and publishes output, the wall moves past it.
    state.noteGuestMilestoneEntry(0x140003000);
    state.noteGuestMilestoneEntry(0x140004000);
    const next = state.guestOutputWall() orelse return error.ExpectedWall;
    try testing.expectEqualStrings("guest_present_carried_content", next.name);
}

test "polling the guest-output mailbox is never a chain stage" {
    // The 2026-09-12 run: PaintFromUIThread ran once, so ConsumeGuestOutput
    // ran once against a mailbox RefreshGuestOutput had never filled. As a
    // stage that read `met`, in the middle of a chain whose producer was
    // zero.
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140007000, .name = "_ZN2xe2ui9Presenter18ConsumeGuestOutputERjPNS1_21GuestOutputPropertiesEPNS1_22GuestOutputPaintConfigE" },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 1, 99);
    state.noteGuestMilestoneEntry(0x140007000);

    try testing.expectEqual(@as(u64, 1), state.guestMilestoneHitsNamed(
        "_ZN2xe2ui9Presenter18ConsumeGuestOutputERjPNS1_21GuestOutputPropertiesEPNS1_22GuestOutputPaintConfigE",
    ));
    for (state.guestOutputChainStages()) |stage| {
        try testing.expect(!std.mem.eql(u8, stage.evidence, "ConsumeGuestOutput_entries"));
    }
    try testing.expectEqual(GUEST_OUTPUT_STAGE_COUNT, state.guestOutputChainStages().len);
}

test "run step deadline includes worker work and resets its worker baseline" {
    try testing.expectEqual(@as(u64, 100), ElfState.runBudgetSteps(40, 10, 70));
    try testing.expectEqual(@as(u64, 40), ElfState.runBudgetSteps(40, 70, 10));
    try testing.expect(ElfState.runBudgetSteps(40, 10, 70) >= 100);
    try testing.expect(ElfState.runBudgetSteps(40, 10, 70) < 101);
}

test "the busiest worker is named, because the frontier only ever sees the owner" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // No workers: nothing to name, and no claim that there is.
    try testing.expectEqual(@as(?usize, null), state.busiestWindowsGuestThread());

    state.windows_guest_threads[3] = .{ .status = .runnable, .handle = 0xAA, .executed_steps = 900 };
    state.windows_guest_threads[7] = .{ .status = .blocked, .handle = 0xBB, .executed_steps = 100 };
    state.executed_steps = 1000;
    // Owner steps and worker steps are different budgets: the checkpoint's
    // step counter is the owner's alone, and reading it as the run's work is
    // what made a working scheduler look like an eighteenfold collapse.
    state.windows_worker_executed_steps = 1000;
    try testing.expectEqual(@as(u64, 2000), state.totalInterpretedSteps());

    const busiest = state.busiestWindowsGuestThread() orelse return error.ExpectedThread;
    try testing.expectEqual(@as(usize, 3), busiest);
    try testing.expectEqual(@as(u64, 0xAA), state.windows_guest_threads[busiest].handle);
}

test "completed guest workers are not reported as live" {
    try testing.expect(isLiveWindowsGuestThread(.pending));
    try testing.expect(isLiveWindowsGuestThread(.runnable));
    try testing.expect(isLiveWindowsGuestThread(.running));
    try testing.expect(isLiveWindowsGuestThread(.blocked));
    try testing.expect(!isLiveWindowsGuestThread(.completed));
    try testing.expect(!isLiveWindowsGuestThread(.failed));
    try testing.expect(!isLiveWindowsGuestThread(.vacant));

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_guest_threads[0] = .{ .status = .completed, .handle = 0xCC, .executed_steps = 10_000 };
    state.windows_guest_threads[1] = .{ .status = .failed, .handle = 0xDD, .executed_steps = 20_000 };
    state.executed_steps = 30_000;
    state.windows_worker_executed_steps = 30_000;

    try testing.expectEqual(@as(?usize, null), state.busiestWindowsGuestThread());
}

test "a clear does not count as a drawn frame in the graphics state" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.windows_graphics.noteCommand("vkCmdBeginRenderPass");
    state.windows_graphics.noteCommand("vkCmdClearAttachments");
    state.windows_graphics.noteCommand("vkCmdEndRenderPass");
    try testing.expectEqual(@as(u64, 3), state.windows_graphics.command_calls);
    try testing.expectEqual(@as(u64, 1), state.windows_graphics.fill_commands);
    try testing.expectEqual(@as(u64, 0), state.windows_graphics.content_commands);

    state.windows_graphics.noteCommand("vkCmdDrawIndexed");
    try testing.expectEqual(@as(u64, 1), state.windows_graphics.content_commands);
}

test "the audio chain blames the title, not the apu factory, before a client exists" {
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140005000, .name = "_ZN2xe3apu11AudioSystem5SetupEPNS_6kernel11KernelStateE" },
        .{ .address = 0x140006000, .name = MILESTONE_REGISTER_AUDIO },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 2, 99);
    state.noteGuestMilestoneEntry(0x140005000);

    // Xenia calls no host audio API until the guest registers a client, so a
    // run with zero WinMM traffic is the title's progress. The chain used to
    // report `backend_reached_rosette` and blame xenia:apu-factory for it.
    const wall = state.audioChainWall() orelse return error.ExpectedWall;
    try testing.expectEqualStrings("title_registered_audio_client", wall.name);
    try testing.expectEqualStrings("guest-title", wall.owner);
}

test "an address with no resolver and no region is unmapped, not guessed" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    var buffer: [128]u8 = undefined;
    try testing.expectEqualStrings("", state.describeGuestAddress(0x140001000, &buffer));
    // `<unmapped>` rather than `<unnamed>`: the two are different findings.
    // A rip Rosette has no record of is a control-flow escape; a rip in a
    // region with no symbol is ordinary, and printing both the same way is
    // what hid three of the 2026-09-12 report's most interesting threads.
    try testing.expectEqualStrings("<unmapped>", state.describeGuestAddressOrUnnamed(0x140001000, &buffer));
    // An unnamed frontier must never suppress a predictor: `unnamed` and
    // `unclassified` are both non-bounded on purpose.
    try testing.expect(!state.guestFrontierIsBoundedComputation());
}

test "an address no symbol covers is still named by its region" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    var buffer: [128]u8 = undefined;

    // The three addresses the 2026-09-12 report printed as `<unnamed>`. Two
    // are Rosette's own import thunks, five hundred bytes past the end of the
    // image it had itself mapped; one is inside a block the guest allocated
    // executable and then jumped into.
    state.noteGuestRegion(0x1430b2000, 0x200000, .import_thunk, "win32-import-stubs");
    try testing.expectEqualStrings(
        "import-thunk:win32-import-stubs+0x5b0",
        state.describeGuestAddressOrUnnamed(0x1430b25b0, &buffer),
    );

    state.noteGuestExecutableAllocation(0xa0000000, 0x100000, guest_address_space.page_execute_readwrite);
    const jit = state.describeGuestAddressOrUnnamed(0xa000044b, &buffer);
    try testing.expect(std.mem.startsWith(u8, jit, "generated-code:"));

    // A data allocation is not code. A rip there is an escape, and labelling
    // it as generated code would bury exactly that.
    state.noteGuestExecutableAllocation(0x280d00000, 0x10000, 0x04);
    try testing.expectEqualStrings("<unmapped>", state.describeGuestAddressOrUnnamed(0x280d00000, &buffer));
}

test "a named frontier carries its workload and its owner" {
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = "stbtt__run_charstring" },
        .{ .address = 0x140002000, .name = "xe::threading::Wait" },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.resolver(), 2, 99);

    var buffer: [256]u8 = undefined;
    try testing.expectEqualStrings(
        "stbtt__run_charstring+0x140",
        state.describeGuestAddress(0x140001140, &buffer),
    );

    // The 2026-09-11 frontier: bounded work, so a downstream no-progress
    // verdict has to hold rather than accuse the presentation chain.
    state.regs.rip = 0x140001140;
    try testing.expect(state.guestFrontierIsBoundedComputation());

    // A wait is not bounded work, and the predictor stays armed there.
    state.regs.rip = 0x140002004;
    try testing.expect(!state.guestFrontierIsBoundedComputation());
}

test "the frontier histogram counts what the run spent its checkpoints doing" {
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = "stbtt__run_charstring" },
        .{ .address = 0x140002000, .name = "xe::gpu::vulkan::VulkanCommandProcessor::IssueDraw" },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.resolver(), 2, 99);

    state.regs.rip = 0x140001010;
    state.sampleGuestFrontier();
    state.sampleGuestFrontier();
    state.regs.rip = 0x140002010;
    state.sampleGuestFrontier();

    try testing.expectEqual(@as(u64, 3), state.guest_frontier_samples);
    try testing.expectEqual(@as(u64, 2), state.fontAtlasFrontierSamples());
    try testing.expectEqual(
        @as(u64, 1),
        state.frontierSamplesFor(.gpu_command_processing),
    );
}

test "a module handle remembers the library it named, and an unknown handle names nothing" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.noteWindowsLoadedModule(0x1000, "vulkan-1.dll");
    state.noteWindowsLoadedModule(0x2000, "xinput1_4.dll");
    // A repeat of the same handle is not a second record.
    state.noteWindowsLoadedModule(0x1000, "vulkan-1.dll");

    try testing.expectEqual(@as(u32, 2), state.windows_loaded_module_count);
    try testing.expectEqualStrings("vulkan-1.dll", state.windowsLoadedModuleName(0x1000));
    try testing.expectEqualStrings("xinput1_4.dll", state.windowsLoadedModuleName(0x2000));
    // Not "kernel32": an unattributed lookup has to stay unattributed, or the
    // return contract answers it against the wrong library.
    try testing.expectEqualStrings("", state.windowsLoadedModuleName(0x3000));
    try testing.expectEqualStrings("", state.windowsLoadedModuleName(0));
}

test "dynamic refusals are folded per name and counted per call" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.noteWindowsModuleRefusal("LoadLibraryW", "XAudio2_8.dll", "outside-the-modelled-Win32-surface", true, "none-outside-modelled-surface", 0x140001000);
    state.noteWindowsModuleRefusal("LoadLibraryW", "XAudio2_8.dll", "outside-the-modelled-Win32-surface", true, "none-outside-modelled-surface", 0x140001000);
    state.noteWindowsProcAddressRefusal("hid.dll", "HidP_SomethingUnmapped", 0x140002000);

    try testing.expectEqual(@as(u32, 1), state.windows_module_refusal_count);
    try testing.expectEqual(@as(u64, 2), state.windows_module_refusal_events);
    try testing.expectEqual(@as(u32, 1), state.windows_proc_refusal_count);
    try testing.expectEqual(@as(u64, 1), state.windows_proc_refusal_events);
    try testing.expectEqualStrings("XAudio2_8.dll", state.windows_module_refusals[0].nameText());
    try testing.expectEqual(@as(u64, 2), state.windows_module_refusals[0].occurrences);
    // A gap and a policy decision are counted apart: the first names work to
    // do, the second is the policy working.
    try testing.expect(state.windows_module_refusals[0].is_gap);
    try testing.expectEqual(@as(u64, 2), state.windows_module_refusal_gaps);
    state.noteWindowsModuleRefusal("LoadLibraryW", "D3D12.dll", "no-backend-behind-a-modelled-name", false, "vulkan-graphics-path", 0x140003000);
    try testing.expectEqual(@as(u64, 2), state.windows_module_refusal_gaps);
    try testing.expect(!state.windows_module_refusals[1].is_gap);
}

test "GetSystemDirectory takes its buffer first and GetCurrentDirectory takes its size first" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const buffer = state.mem_base + 0x4000;
    const return_rip = state.mem_base + 0x1000;

    // GetSystemDirectoryA(LPSTR buffer, UINT size): buffer in rcx, size in rdx.
    // Reading these the other way round wrote nothing and still returned a
    // plausible length, which is what made libusb's `load_system_library`
    // append a filename at that offset into an unwritten buffer and hand the
    // result to LoadLibraryA.
    for (0..64) |index| state.write8(buffer + @as(u64, @intCast(index)), 0xAA);
    state.regs.rcx = buffer;
    state.regs.rdx = 64;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetSystemDirectoryA", return_rip));
    const system_directory = "C:\\Windows\\System32";
    try testing.expectEqual(@as(u64, system_directory.len), state.regs.rax);
    for (system_directory, 0..) |byte, index| {
        try testing.expectEqual(byte, state.read8(buffer + @as(u64, @intCast(index))));
    }
    try testing.expectEqual(@as(u8, 0), state.read8(buffer + system_directory.len));

    // GetCurrentDirectoryA(DWORD size, LPSTR buffer): the opposite order.
    for (0..64) |index| state.write8(buffer + @as(u64, @intCast(index)), 0xAA);
    state.regs.rcx = 64;
    state.regs.rdx = buffer;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetCurrentDirectoryA", return_rip));
    try testing.expect(state.regs.rax != 0);
    try testing.expectEqual(@as(u8, 'C'), state.read8(buffer));
}

test "a module name Rosetta could not read is never turned into a refusal" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // The 2026-09-11 run printed `module='0'D'` for a LoadLibraryA. Those
    // bytes are not a module name in any spelling, so the read failed - and
    // concluding "this library is absent" from them would report a loadable
    // library as missing.
    try testing.expect(!x64_linux_runtime.windowsModuleNameLooksReadable("0'D"));
    try testing.expect(!x64_linux_runtime.windowsModuleNameLooksReadable(""));
    try testing.expect(!x64_linux_runtime.windowsModuleNameLooksReadable("\x01\x02\x03"));
    try testing.expect(x64_linux_runtime.windowsModuleNameLooksReadable("hid.dll"));
    try testing.expect(x64_linux_runtime.windowsModuleNameLooksReadable("XAudio2_8.dll"));
    try testing.expect(x64_linux_runtime.windowsModuleNameLooksReadable("C:\\Windows\\System32\\vulkan-1.dll"));

    state.noteWindowsUnreadableModuleName("LoadLibraryA", "0'D", 0x1234, 0x140001000);
    try testing.expectEqual(@as(u64, 1), state.windows_unreadable_module_names);
    // It is not recorded as a refusal, because it is not one.
    try testing.expectEqual(@as(u32, 0), state.windows_module_refusal_count);
}

test "the host audio sink is only claimed once the device has served a callback" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // No hooks at all: the guest's wave device still works, on the null sink.
    try testing.expectEqualStrings("clocked_null_sink", state.windowsAudioSinkLabel());
    try testing.expect(!state.openWindowsHostAudio(48000, 2, 32, true));

    const Hooks = struct {
        var served: u64 = 0;
        var opened: bool = false;
        fn open(_: ?*anyopaque, _: u32, _: u32, _: u32, _: c_int) callconv(.c) c_int {
            opened = true;
            return 1;
        }
        fn callbacks(_: ?*anyopaque) callconv(.c) u64 {
            return served;
        }
    };
    Hooks.served = 0;
    Hooks.opened = false;
    state.windows_audio_hooks = .{ .open = Hooks.open, .callbacks_served = Hooks.callbacks };

    try testing.expect(state.openWindowsHostAudio(48000, 2, 32, true));
    try testing.expect(Hooks.opened);
    // Open is not audible. A device that has never been asked for a frame is
    // indistinguishable from the null sink from the guest's side, and saying
    // otherwise is how silence gets blamed on the wrong layer.
    try testing.expectEqualStrings("opened_but_silent", state.windowsAudioSinkLabel());

    Hooks.served = 1;
    try testing.expectEqualStrings("host_device", state.windowsAudioSinkLabel());
}

test "the first-frame chain names the earliest unmet precondition and its owner" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // Nothing has happened: the very first stage is the wall, and it belongs
    // to Rosette.
    const cold = state.firstFrameWall().?;
    try testing.expectEqualStrings("host_window", cold.name);
    try testing.expectEqualStrings("rosette:appkit-bridge", cold.owner);

    // Bring the graphics ledger up to the state of the 2026-09-11 run: every
    // host and guest Vulkan object exists, and no frame has been produced.
    const graphics = &state.windows_graphics;
    graphics.window_ready = true;
    graphics.window_create_attempts = 1;
    graphics.instance_ready = true;
    graphics.device_ready = true;
    graphics.queue_ready = true;
    graphics.surface_ready = true;
    graphics.swapchain_ready = true;

    // A callable atlas-output witness is present. No samples (including
    // cold zero samples) can stand in for its returned bytes.
    const font_index = comptime console_guest_milestone_map.indexOf(ui_draw_evidence.font_rgba_symbol).?;
    var table = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = "stbtt__run_charstring" },
    } };
    state.installGuestSymbolResolver(table.resolver(), 1, 99);
    state.guest_milestone_addresses[font_index] = 0x140009000;
    state.regs.rip = 0x140001010;
    state.sampleGuestFrontier();

    const atlas = state.firstFrameWall().?;
    try testing.expectEqualStrings("ui_font_atlas", atlas.name);
    try testing.expectEqualStrings("xenia:ui-thread", atlas.owner);

    // Leaving the sampled builder does NOT prove completion. A valid
    // returned atlas advances the wall and subsequent text drawing keeps it.
    state.regs.rip = 0x0;
    try testing.expectEqualStrings("ui_font_atlas", state.firstFrameWall().?.name);
    state.ui_evidence.noteFontReturn(MEM_BASE + 0x4000, 8, 8, true);
    const after_atlas = state.firstFrameWall().?;
    try testing.expectEqualStrings("title_code_running", after_atlas.name);
    try testing.expectEqualStrings("xenia:emulator-thread", after_atlas.owner);

    // Observe the guest running its own code once.
    var running = TestSymbolTable{ .entries = &.{
        .{ .address = 0x140005000, .name = "xe::kernel::XThread::Execute" },
    } };
    state.installGuestSymbolResolver(running.resolver(), 1, 99);
    state.regs.rip = 0x140005010;
    state.sampleGuestFrontier();
    state.regs.rip = 0x0;
    try testing.expectEqualStrings("window_paint_requested", state.firstFrameWall().?.name);

    state.windows_paint_requests = 1;
    state.windows_paint_deliveries = 1;
    graphics.command_calls = 1;
    graphics.image_acquires = 1;
    graphics.queue_submits = 1;
    try testing.expectEqualStrings("present", state.firstFrameWall().?.name);
    graphics.presents = 1;
    try testing.expect(state.firstFrameWall() == null);
}

test "UI return evidence follows the actual return and keeps pending pointers thread-local" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const outputs = MEM_BASE + 0x2000;
    const pixels = MEM_BASE + 0x4000;
    state.regs.rsp = MEM_BASE + 0x30000;
    state.regs.rdx = outputs;
    state.regs.r8 = outputs + 8;
    state.regs.r9 = outputs + 12;
    state.noteGuestMilestoneArguments(comptime console_guest_milestone_map.indexOf(ui_draw_evidence.font_rgba_symbol).?);
    state.write64(outputs, pixels);
    state.write32(outputs + 8, 8);
    state.write32(outputs + 12, 8);
    // A nested return must not complete the outer function.
    state.regs.rsp -= 8;
    state.completeGuestReturnCapture();
    try testing.expectEqual(@as(u64, 0), state.ui_evidence.font_returns);
    // Another cooperative thread captures its own pipeline result.
    state.windows_active_guest_thread_slot = 0;
    state.regs.rsp = MEM_BASE + 0x31000;
    state.noteGuestMilestoneArguments(comptime console_guest_milestone_map.indexOf(ui_draw_evidence.pipelines_symbol).?);
    state.regs.rax = 0x100; // only AL holds a C++ bool result
    state.completeGuestReturnCapture();
    try testing.expectEqual(@as(u64, 1), state.ui_evidence.pipeline_false);
    try testing.expectEqual(@as(u64, 0), state.ui_evidence.font_returns);
    state.windows_active_guest_thread_slot = null;
    state.regs.rsp = MEM_BASE + 0x30000;
    state.completeGuestReturnCapture();
    try testing.expect(state.ui_evidence.font_last_valid);
    try testing.expectEqual(@as(u64, 1), state.ui_evidence.font_valid_returns);
    try testing.expectEqual(@as(u32, 0), state.guest_return_captures_armed);

    // Scissor fifth/sixth reference arguments live after caller shadow space.
    state.regs.r8 = outputs;
    state.regs.r9 = outputs + 4;
    state.write64(state.regs.rsp + 32, outputs + 8);
    state.write64(state.regs.rsp + 40, outputs + 12);
    inline for (0..4) |i| state.write32(outputs + i * 4, 10 + i);
    state.noteGuestMilestoneArguments(comptime console_guest_milestone_map.indexOf(ui_draw_evidence.scissor_symbol).?);
    state.regs.rax = 1;
    state.completeGuestReturnCapture();
    try testing.expectEqual([4]u32{ 10, 11, 12, 13 }, state.ui_evidence.scissor_rect);
    state.regs.rdx = 0xffff_ffff_ffff_f000; // inaccessible, not fabricated zero geometry
    state.noteGuestMilestoneArguments(comptime console_guest_milestone_map.indexOf(ui_draw_evidence.lists_symbol).?);
    try testing.expectEqual(@as(u64, 1), state.ui_evidence.lists_unreadable);
    try testing.expect(!state.faulted);
}

test "the SHA1 feed loop is recognized by its own bytes and stops one byte short" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // Lay out the loop exactly as the compiler inlines TinySHA1's
    // processBytes: an increment head, the exit branch, and the byte load.
    const head = state.mem_base + 0x2000;
    const loop = [_]u8{
        0x49, 0xFF, 0xC7, // inc  %r15
        0x4C, 0x39, 0xFB, // cmp  %r15,%rbx
        0x0F, 0x84, 0x00, 0x01, 0x00, 0x00, // je   +0x100
        0x43, 0x0F, 0xB6, 0x04, 0x3E, // movzbl (%r14,%r15,1),%eax
    };
    for (loop, 0..) |byte, index| state.write8(head + @as(u64, @intCast(index)), byte);

    // The `jmp` back to the head that follows the call to processBlock.
    const return_rip = head + 0x40;
    state.write8(return_rip, 0xEB);
    state.write8(return_rip + 1, @bitCast(@as(i8, -0x42)));

    const object = state.mem_base + 0x3000;
    const source = state.mem_base + 0x8000;
    const total: u64 = 0x4000;
    for (0..total) |index| {
        state.write8(source + @as(u64, @intCast(index)), @truncate(index * 7 + 3));
    }
    // A fresh TinySHA1 object: standard initial digest, empty block.
    const initial = [_]u32{ 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0 };
    for (initial, 0..) |word, index| state.write32(object + 0x08 + @as(u64, @intCast(index * 4)), word);
    state.write64(object + 0x60, 0);
    state.write64(object + 0x68, 0);

    state.regs.rdi = object;
    state.regs.rcx = object;
    state.regs.r14 = source;
    state.regs.r15 = 0;
    state.regs.rbx = total;

    state.tryXeniaSha1FeedLoop(return_rip);

    try testing.expectEqual(@as(u64, 1), state.xenia_sha1_feed_spans);
    // Bytes 1 .. total-2 were consumed: the guest keeps the final iteration
    // and the branch, so every register the loop writes ends up holding what
    // the guest's own code would have left there.
    try testing.expectEqual(total - 2, state.xenia_sha1_feed_bytes);
    try testing.expectEqual(total - 2, state.regs.r15);
    try testing.expectEqual(total - 2, state.read64(object + 0x68));
    try testing.expectEqual((total - 2) % 64, state.read64(object + 0x60));
}

pub fn seedKernelSha1FeedFixture(state: *ElfState, length: u64) void {
    const head = state.mem_base + 0x2000;
    const object = state.mem_base + 0x6020;
    const source = state.mem_base + 0x10000;
    const target = state.mem_base + 0x7000;
    @memcpy(state.guestMemory(head, xenia_sha1_kernel_feed_body.len).?, &xenia_sha1_kernel_feed_body);
    const return_rip = head + xenia_sha1_kernel_feed_body.len + 4;
    state.write32(head + xenia_sha1_kernel_feed_body.len, @bitCast(@as(i32, @intCast(@as(i64, @intCast(target)) - @as(i64, @intCast(return_rip))))));
    state.write8(return_rip, 0xeb);
    state.write8(return_rip + 1, @bitCast(@as(i8, -78)));
    for (0..@intCast(length)) |offset| state.write8(source + offset, @truncate(offset * 7 + 3));
    const initial = [_]u32{ 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0 };
    for (initial, 0..) |word, index| state.write32(object + 8 + index * 4, word);
    state.write64(object + 0x60, 0);
    state.write64(object + 0x68, 0);
    // Begin just after the first compression call, at the same boundary the
    // real executor uses. Reference and fast executions share that boundary.
    std.debug.assert(xenia_accelerator.sha1ProcessBytes(state, object, source, 64));
    state.windows_runtime_enabled = true;
    state.xenia_sha1_accelerator_enabled = true;
    state.xenia_sha1_target_checked = true;
    state.xenia_sha1_target = target;
    state.regs.rip = return_rip;
    state.regs.rsp = object - 0x20;
    state.regs.rdi = object;
    state.regs.rcx = object;
    state.regs.rbx = source;
    state.regs.r12 = length;
    state.regs.r15 = 63;
}

test "kernel SHA1 feed fast path preserves the interpreted digest tail and live registers" {
    const fast = try testing.allocator.create(ElfState);
    defer testing.allocator.destroy(fast);
    fast.* = ElfState.init(testing.allocator);
    defer fast.deinit();
    const reference = try testing.allocator.create(ElfState);
    defer testing.allocator.destroy(reference);
    reference.* = ElfState.init(testing.allocator);
    defer reference.deinit();
    const length = 0x4001; // Deliberately includes a partial-block tail.
    seedKernelSha1FeedFixture(fast, length);
    seedKernelSha1FeedFixture(reference, length);
    reference.xenia_sha1_feed_enabled = false;
    // This measures the accelerator against the interpreter proper; the block
    // translator has its own lockstep test over the same loop.
    reference.block_jit_enabled = false;
    fast.tryXeniaSha1FeedLoop(fast.regs.rip);
    const stop = fast.mem_base + 0x2000 + 78;
    var fast_steps: usize = 0;
    while (fast.regs.rip != stop and fast_steps < 200_000) : (fast_steps += 1) try testing.expect(fast.step());
    var reference_steps: usize = 0;
    while (reference.regs.rip != stop and reference_steps < 200_000) : (reference_steps += 1) try testing.expect(reference.step());
    try testing.expect(fast.regs.rip == stop and reference.regs.rip == stop);
    try testing.expectEqualSlices(u8, reference.guestMemoryConst(reference.regs.rdi, 0x70).?, fast.guestMemoryConst(fast.regs.rdi, 0x70).?);
    try testing.expectEqualDeep(reference.regs, fast.regs);
    try testing.expectEqualDeep(reference.xmm, fast.xmm);
    try testing.expectEqual(@as(u64, length), fast.read64(fast.regs.rdi + 0x68));
    try testing.expectEqual(@as(u64, 1), fast.xenia_sha1_kernel_feed_spans);
    try testing.expectEqual(@as(u64, length - 65), fast.xenia_sha1_kernel_feed_bytes);
    try testing.expect(fast_steps < 32 and reference_steps > 170_000);
    // Finalize an independent standard-library hash to verify the message's
    // complete blocks, not merely equality between two copies of our helper.
    var expected: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(fast.guestMemoryConst(fast.regs.rbx, length).?, &expected, .{});
    const padded = fast.guestMemory(fast.regs.rbx + length, 63).?;
    @memset(padded, 0);
    padded[0] = 0x80;
    std.mem.writeInt(u64, padded[55..][0..8], length * 8, .big);
    try testing.expect(xenia_accelerator.sha1ProcessBytes(fast, fast.regs.rdi, fast.regs.rbx + length, 63));
    for (0..5) |word| try testing.expectEqual(std.mem.readInt(u32, expected[word * 4 ..][0..4], .big), fast.read32(fast.regs.rdi + 8 + word * 4));
}

test "kernel SHA1 feed checks every body byte target object and aliases before mutating" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    seedKernelSha1FeedFixture(&state, 0x4001);
    const head = state.mem_base + 0x2000;
    const return_rip = state.regs.rip;
    const saved = state.regs;
    for (xenia_sha1_kernel_feed_body, 0..) |byte, offset| {
        state.write8(head + offset, byte ^ 1);
        state.tryXeniaSha1FeedLoop(return_rip);
        try testing.expectEqual(@as(u64, 0), state.xenia_sha1_kernel_feed_spans);
        try testing.expectEqualDeep(saved, state.regs);
        state.write8(head + offset, byte);
    }
    state.xenia_sha1_target = state.xenia_sha1_target.? + 1;
    state.tryXeniaSha1FeedLoop(return_rip);
    try testing.expectEqual(@as(u64, 0), state.xenia_sha1_kernel_feed_spans);
    state.xenia_sha1_target = state.xenia_sha1_target.? - 1;
    state.regs.rsp += 8;
    state.tryXeniaSha1FeedLoop(return_rip);
    try testing.expectEqual(@as(u64, 0), state.xenia_sha1_kernel_feed_spans);
    state.regs = saved;
    try testing.expect(!xenia_accelerator.sha1ProcessBytes(&state, state.regs.rdi, state.regs.rdi + 8, 64));
    try testing.expectEqual(@as(u64, 64), state.read64(state.regs.rdi + 0x68));
}

test "kernel SHA1 feed bounds one native turn and leaves oversized input to later turns" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    seedKernelSha1FeedFixture(&state, 1024 * 1024);
    state.tryXeniaSha1FeedLoop(state.regs.rip);
    try testing.expectEqual(@as(u64, 262144), state.xenia_sha1_kernel_feed_bytes);
    try testing.expectEqual(@as(u64, 63 + 262144), state.regs.r15);
    try testing.expectEqual(@as(u64, 64 + 262144), state.read64(state.regs.rdi + 0x68));
}

test "the SHA1 feed accelerator declines anything that is not the loop it matched" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const head = state.mem_base + 0x2000;
    // A plausible-looking but different loop head: the exit branch is a
    // near jump rather than a conditional, so the shape does not match.
    const loop = [_]u8{
        0x49, 0xFF, 0xC7,
        0x4C, 0x39, 0xFB,
        0xE9, 0x00, 0x01,
        0x00, 0x00, 0x90,
        0x43, 0x0F, 0xB6,
        0x04, 0x3E,
    };
    for (loop, 0..) |byte, index| state.write8(head + @as(u64, @intCast(index)), byte);
    const return_rip = head + 0x40;
    state.write8(return_rip, 0xEB);
    state.write8(return_rip + 1, @bitCast(@as(i8, -0x42)));
    state.regs.rdi = state.mem_base + 0x3000;
    state.regs.rcx = state.regs.rdi;
    state.regs.r14 = state.mem_base + 0x8000;
    state.regs.r15 = 0;
    state.regs.rbx = 0x4000;
    state.tryXeniaSha1FeedLoop(return_rip);
    try testing.expectEqual(@as(u64, 0), state.xenia_sha1_feed_spans);

    // The shape matches but the span is small: intercepting it would be pure
    // risk for a loop the guest finishes in microseconds.
    for (loop, 0..) |_, index| {
        const fixed = [_]u8{ 0x49, 0xFF, 0xC7, 0x4C, 0x39, 0xFB, 0x0F, 0x84, 0, 1, 0, 0, 0x43, 0x0F, 0xB6, 0x04, 0x3E };
        state.write8(head + @as(u64, @intCast(index)), fixed[index]);
    }
    state.regs.rbx = 64;
    state.tryXeniaSha1FeedLoop(return_rip);
    try testing.expectEqual(@as(u64, 0), state.xenia_sha1_feed_spans);

    // The shape matches and the span is large, but `rcx` no longer names the
    // object the call site loaded from `rdi`.
    state.regs.rbx = 0x4000;
    state.regs.rcx = state.regs.rdi + 8;
    state.tryXeniaSha1FeedLoop(return_rip);
    try testing.expectEqual(@as(u64, 0), state.xenia_sha1_feed_spans);
}

test "a reserve over occupied address space is refused, because a success there aliases two contexts" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = state.mem_base + 0x1000;
    // Xenia's AllocateContext asks for ((0x40 << 32) | 0xE0000000) - 0x10000
    // with MEM_RESERVE|MEM_COMMIT, then walks pos32 upward until one is
    // granted. It relies on the refusal to advance; a granted second reserve
    // would give two guest threads the same PPC context.
    const first = 0x40DFFF0000;
    const length: u64 = 0x10AC0;
    const reserve_commit: u64 = 0x2000 | 0x1000;

    state.regs.rcx = first;
    state.regs.rdx = length;
    state.regs.r8 = reserve_commit;
    state.regs.r9 = 0x04;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "VirtualAlloc", return_rip));
    try testing.expectEqual(first, state.regs.rax);

    // The same range again must fail.
    state.regs.rcx = first;
    state.regs.rdx = length;
    state.regs.r8 = reserve_commit;
    state.regs.r9 = 0x04;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "VirtualAlloc", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expect(state.windows_allocation_refusal_count != 0);
    try testing.expectEqual(
        WindowsAllocationRefusalReason.reserve_over_existing,
        state.windows_allocation_refusals[0].reason,
    );

    // The caller's next candidate is a different address and must succeed.
    const second = 0x41DFFF0000;
    state.regs.rcx = second;
    state.regs.rdx = length;
    state.regs.r8 = reserve_commit;
    state.regs.r9 = 0x04;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "VirtualAlloc", return_rip));
    try testing.expectEqual(second, state.regs.rax);
}

test "a commit is classified by what actually backs its address" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // Inside the loaded image: a commit here is backed by the image itself.
    const in_image = state.mem_base + 0x1000;
    try testing.expectEqual(
        WindowsAllocationDisposition.committed_in_image,
        state.noteWindowsAllocationDisposition(in_image, 0x1000, false, true, true, 0x140001000),
    );

    // Far outside anything this run reserved or mapped. Windows fails this
    // with ERROR_INVALID_ADDRESS; Rosette serves it and records that it did,
    // which is the reservation-versus-commit distinction the
    // `guest-heap-commit-unreserved` failure point exists to keep.
    const unbacked = 0x0000_2800_d100_0000;
    try testing.expectEqual(
        WindowsAllocationDisposition.committed_unbacked,
        state.noteWindowsAllocationDisposition(unbacked, 0x10000, false, true, true, 0x140002000),
    );
    try testing.expectEqual(@as(u32, 1), state.windows_unbacked_commit_count);
    try testing.expect(WindowsAllocationDisposition.committed_unbacked.divergesFromWindows());
    try testing.expect(!WindowsAllocationDisposition.committed_in_image.divergesFromWindows());

    // A second commit from the same caller folds into the same record rather
    // than filling the bounded table with one loop's worth of noise.
    _ = state.noteWindowsAllocationDisposition(unbacked, 0x10000, false, true, true, 0x140002000);
    try testing.expectEqual(@as(u32, 1), state.windows_unbacked_commit_count);
    try testing.expectEqual(@as(u64, 2), state.windows_unbacked_commits[0].occurrences);

    // A request Rosette could not serve is neither a reserve nor a commit.
    try testing.expectEqual(
        WindowsAllocationDisposition.refused,
        state.noteWindowsAllocationDisposition(unbacked, 0x10000, true, true, false, 0x140003000),
    );

    // A reservation with no address is a new one, whatever else is mapped.
    try testing.expectEqual(
        WindowsAllocationDisposition.reserved_new,
        state.noteWindowsAllocationDisposition(0, 0x1000, true, true, true, 0x140004000),
    );
}

test "the audio chain blames the backend before it blames the device" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // The 2026-09-11 shape: not one audio import arrived, because Xenia's
    // factory chose XAudio2 and never reached WinMM. Blaming CoreAudio for
    // that would send a reader to the wrong side of the boundary entirely.
    const cold = state.audioChainWall().?;
    try testing.expectEqualStrings("backend_reached_rosette", cold.name);
    try testing.expectEqualStrings("xenia:apu-factory", cold.owner);

    state.windows_audio_import_calls = 4;
    try testing.expectEqualStrings("guest_wave_device_open", state.audioChainWall().?.name);

    state.windows_audio_open_successes = 1;
    const host_stage = state.audioChainWall().?;
    try testing.expectEqualStrings("host_device_open", host_stage.name);
    try testing.expectEqualStrings("rosette:coreaudio", host_stage.owner);

    state.windows_audio_host_connected = true;
    try testing.expectEqualStrings("guest_wrote_frames", state.audioChainWall().?.name);

    state.windows_audio_write_calls = 10;
    // Silence that is genuinely the title's is attributed to the title.
    const signal_stage = state.audioChainWall().?;
    try testing.expectEqualStrings("frames_carry_signal", signal_stage.name);
    try testing.expectEqualStrings("guest-title", signal_stage.owner);
}
