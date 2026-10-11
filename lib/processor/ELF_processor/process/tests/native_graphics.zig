const process = @import("../../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const GpuRingWindow = __ProcessInternals._GpuRingWindow;
const GuestFileNameShape = __ProcessInternals._GuestFileNameShape;
const GuestVfsResolve = __ProcessInternals._GuestVfsResolve;
const INITIAL_WINDOWS_HEAP_ALLOCATIONS = __ProcessInternals._INITIAL_WINDOWS_HEAP_ALLOCATIONS;
const MEM_BASE = __ProcessInternals._MEM_BASE;
const Op = process.Op;
const PPC_CONTEXT_LINK_REGISTER = __ProcessInternals._PPC_CONTEXT_LINK_REGISTER;
const PPC_CONTEXT_VIRTUAL_MEMBASE = __ProcessInternals._PPC_CONTEXT_VIRTUAL_MEMBASE;
const RegId = process.RegId;
const SYNTHETIC_WINDOWS_APC_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_APC_RETURN;
const SYNTHETIC_WINDOWS_AUDIO_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_AUDIO_RETURN;
const SYNTHETIC_WINDOWS_CRT_EXIT_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_CRT_EXIT_RETURN;
const SYNTHETIC_WINDOWS_MESSAGE_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_MESSAGE_RETURN;
const WINDOWS_GUEST_CLOCK_HZ = process.WINDOWS_GUEST_CLOCK_HZ;
const WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND = process.WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
const WINDOWS_GUEST_THREAD_STACK_GUARD = __ProcessInternals._WINDOWS_GUEST_THREAD_STACK_GUARD;
const WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD = __ProcessInternals._WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD;
const WINDOWS_WAIT_IO_COMPLETION = __ProcessInternals._WINDOWS_WAIT_IO_COMPLETION;
const WINDOWS_WM_PAINT = __ProcessInternals._WINDOWS_WM_PAINT;
const WindowsExecutableRange = process.WindowsExecutableRange;
const WindowsFileFailureLedger = __ProcessInternals._WindowsFileFailureLedger;
const WindowsGuestThreadStatus = __ProcessInternals._WindowsGuestThreadStatus;
const WindowsMultiWaitResult = __ProcessInternals._WindowsMultiWaitResult;
const WindowsWaveOutDevice = __ProcessInternals._WindowsWaveOutDevice;
const exit_diagnostics = __ProcessInternals._exit_diagnostics;
const guest_clock = __ProcessInternals._guest_clock;
const log = __ProcessInternals._log;
const ppcContextGpr = __ProcessInternals._ppcContextGpr;
const std = __ProcessInternals._std;
const testing = std.testing;
const tso_memory = __ProcessInternals._tso_memory;
const windowsFileErrorLabel = __ProcessInternals._windowsFileErrorLabel;
const windows_guest_abi = __ProcessInternals._windows_guest_abi;
const x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const xenia_guest_milestone_map = __ProcessInternals._xenia_guest_milestone_map;
const ElfState = process.ElfState;

const NativeGraphicsTestHarness = struct {
    starts: u64 = 0,
    stage: u32 = 10,
    frames: u64 = 0,
    present_chain_reports: u64 = 0,
    present_chain_full_reports: u64 = 0,
    application_ensures: u64 = 0,
    window_ensures: u64 = 0,
};

fn testNativeWindowEnsureApplication(context: ?*anyopaque) callconv(.c) c_int {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.application_ensures +|= 1;
    return 1;
}

fn testNativeWindowEnsure(context: ?*anyopaque, _: u32, _: u32, _: [*:0]const u8) callconv(.c) c_int {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.window_ensures +|= 1;
    return 1;
}

fn testPresentChainReport(context: ?*anyopaque) callconv(.c) void {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.present_chain_reports +|= 1;
}

fn testPresentChainFullReport(context: ?*anyopaque) callconv(.c) void {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.present_chain_full_reports +|= 1;
}

fn testNativePresenterStart(context: ?*anyopaque, _: u32, _: u32) callconv(.c) c_int {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.starts +|= 1;
    return 1;
}

fn testNativePresenterStage(context: ?*anyopaque) callconv(.c) u32 {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    return harness.stage;
}

fn testNativePresenterReady(_: ?*anyopaque) callconv(.c) c_int {
    return 1;
}

fn testNativePresenterDiagnostic(context: ?*anyopaque, _: u64, _: u32, _: u32, _: u32) callconv(.c) u64 {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.frames +|= 1;
    return harness.frames;
}

test "the terminal present-chain snapshot is full and idempotent" {
    var harness = NativeGraphicsTestHarness{};
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_graphics.hooks = .{
        .native_context = &harness,
        .report_present_chain = testPresentChainReport,
        .report_present_chain_full = testPresentChainFullReport,
    };

    state.reportPresentChainFinal();
    state.reportPresentChainFinal();
    try testing.expect(state.windows_present_chain_final_reported);
    try testing.expectEqual(@as(u64, 1), harness.present_chain_full_reports);
    try testing.expectEqual(@as(u64, 0), harness.present_chain_reports);
}

test "shader advisory requests positive native creation evidence without ending reporting" {
    var harness = NativeGraphicsTestHarness{};
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_graphics.hooks = .{
        .native_context = &harness,
        .report_present_chain_full = testPresentChainFullReport,
    };
    state.substantiateVulkanShaderCreation();
    try testing.expectEqual(@as(u64, 1), harness.present_chain_full_reports);
    try testing.expect(!state.windows_present_chain_final_reported);
    state.reportPresentChainFinal();
    try testing.expectEqual(@as(u64, 2), harness.present_chain_full_reports);
}

test "Windows imports preserve stateful contracts and ABI refusal values" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x500;

    // Xenia's command processor publishes its ring write pointer and then
    // calls the one-argument NT boost-priority event API. It must wake a
    // parked GPU worker just like SetEvent; a generic successful return would
    // leave the worker asleep forever.
    const gpu_ring_event = 0xFFFF_F000_0000_0F68;
    state.registerWindowsEvent(gpu_ring_event, false, false);
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0xF068 };
    state.windows_active_guest_thread_slot = 0;
    try testing.expectEqual(
        ElfState.WindowsWaitResult.blocked,
        state.waitWindowsGuestObject(gpu_ring_event, std.math.maxInt(u32)),
    );
    state.regs = .{};
    state.regs.rcx = gpu_ring_event;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ntdll.dll", "NtSetEventBoostPriority", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[0].status);
    // It is an auto-reset event, and the signal was consumed by the waiter it
    // woke. The next wait must not observe a phantom second signal.
    try testing.expect(!state.windowsWaitObjectSignaled(gpu_ring_event));
    try testing.expectEqual(@as(u64, 1), state.windows_thread_unblocks);

    // The CRT's volume metadata probe is backed by Rosetta's one confined
    // guest mount. It must receive a usable guest name and handle, not the
    // old empty-provider placeholder that made every follow-up call look
    // like an invalid-handle failure.
    const volume_name = MEM_BASE + 0xC00;
    state.regs = .{};
    state.regs.rcx = volume_name;
    state.regs.rdx = 128;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "FindFirstVolumeW", return_rip));
    const volume_handle = state.regs.rax;
    try testing.expect(volume_handle != std.math.maxInt(u64));
    try testing.expect(volume_handle >= 0xFFFF_F000_0000_0001);
    try testing.expectEqual(@as(u32, 0), state.windows_last_error); // ERROR_SUCCESS
    try testing.expectEqual(@as(u16, '\\'), state.read16(volume_name));
    try testing.expectEqual(@as(u16, '\\'), state.read16(volume_name + 2));
    try testing.expectEqual(@as(u16, '?'), state.read16(volume_name + 4));
    state.regs = .{};
    state.regs.rcx = volume_handle;
    state.regs.rdx = volume_name;
    state.regs.r8 = 128;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "FindNextVolumeW", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u32, 18), state.windows_last_error); // ERROR_NO_MORE_FILES
    state.regs = .{};
    state.regs.rcx = volume_handle;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "FindVolumeClose", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u32, 0), state.windows_last_error); // ERROR_SUCCESS
    state.regs = .{};
    state.regs.rcx = volume_handle;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "FindVolumeClose", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u32, 6), state.windows_last_error); // ERROR_INVALID_HANDLE

    // A registry lookup used to return zero, which is ERROR_SUCCESS: the
    // guest was told the key opened and then read an HKEY that was never
    // written.  The explicit contract reports absence and writes the output.
    // A key the guest never created is absent; a null subkey would name the
    // root itself, which does exist.
    const registry_output = MEM_BASE + 0xD80;
    const registry_subkey = MEM_BASE + 0xD00;
    const absent_subkey = "Software\\NeverCreated";
    @memcpy(state.guestMemory(registry_subkey, absent_subkey.len).?, absent_subkey);
    state.write8(registry_subkey + absent_subkey.len, 0);
    state.regs = .{};
    state.regs.rcx = 0xFFFF_FFFF_8000_0001; // HKEY_CURRENT_USER
    state.regs.rdx = registry_subkey;
    state.regs.r8 = registry_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ADVAPI32.dll", "RegOpenKeyA", return_rip));
    try testing.expectEqual(@as(u64, 2), state.regs.rax); // ERROR_FILE_NOT_FOUND
    try testing.expectEqual(@as(u64, 0), state.read64(registry_output));

    // A COM/WinRT/DXGI creation is an HRESULT, where zero is S_OK.  DXGI now
    // has a guest-only factory model, while the optional WinRT path retains
    // its explicit E_NOINTERFACE refusal.
    state.regs = .{};
    const factory_output = MEM_BASE + 0xD88;
    state.regs.rdx = factory_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "dxgi.dll", "CreateDXGIFactory1", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax); // S_OK
    try testing.expect(state.read64(factory_output) != 0);
    state.regs = .{};
    state.regs.r8 = factory_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-core-winrt-l1-1-0.dll", "RoGetActivationFactory", return_rip));
    try testing.expectEqual(@as(u64, 0x8000_4002), state.regs.rax);

    // A BOOL-returning call with no handler keeps the zero that already meant
    // FALSE, so the contract cannot alter a path that was already honest.
    // `GetFileVersionInfoA` rather than `BitBlt`: GDI is now modelled, and a
    // test that demonstrates the fallback has to use a name that still
    // reaches it.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "VERSION.dll", "GetFileVersionInfoA", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u32, 120), state.windows_last_error); // ERROR_CALL_NOT_IMPLEMENTED

    // The generic GDI fallback is recorded, while the registry and DXGI paths
    // complete through explicit contracts and stay out.
    //
    // `CreateDXGIFactory1` now publishes the guest-only COM object graph, so it
    // must not appear in the fallback ledger. A refusal the run cannot account
    // for is the defect, not an explicit, tested refusal.
    const ledger = &state.windows_import_fallbacks;
    try testing.expectEqual(@as(usize, 1), ledger.count);
    try testing.expectEqual(@as(u64, 1), ledger.total_calls);
    try testing.expectEqual(@as(usize, 1), ledger.refusedCount());

    var saw_blit = false;
    for (ledger.entries[0..ledger.count]) |*entry| {
        if (std.mem.eql(u8, entry.name(), "GetFileVersionInfoA")) {
            saw_blit = true;
            try testing.expectEqualStrings("VERSION.dll", entry.dll());
        }
    }
    try testing.expect(saw_blit);

    // An explicit contract is not a degraded fallback and does not reappear
    // in the ledger when the guest probes the same key again.
    state.regs = .{};
    state.regs.rcx = 0xFFFF_FFFF_8000_0001;
    state.regs.rdx = registry_subkey;
    state.regs.r8 = registry_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ADVAPI32.dll", "RegOpenKeyA", return_rip));
    try testing.expectEqual(@as(usize, 1), ledger.count);
    try testing.expectEqual(@as(u64, 1), ledger.total_calls);
}

test "ntdll GetModuleHandle and GetProcAddress preserve the event import context" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.trace_windows_waits = true;
    const return_rip = MEM_BASE + 0x560;

    const module_name = state.guestAlloc(16, 1).?;
    for ("ntdll.dll\x00", 0..) |character, index| {
        state.write8(module_name + @as(u64, @intCast(index)), character);
    }
    state.regs.rcx = module_name;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "GetModuleHandleA", return_rip));
    const ntdll_handle = state.regs.rax;
    try testing.expect(ntdll_handle != 0);
    try testing.expectEqualStrings("ntdll.dll", state.windowsLoadedModuleName(ntdll_handle));

    const export_name = state.guestAlloc(32, 1).?;
    for ("NtSetEventBoostPriority\x00", 0..) |character, index| {
        state.write8(export_name + @as(u64, @intCast(index)), character);
    }
    state.regs = .{};
    state.regs.rcx = ntdll_handle;
    state.regs.rdx = export_name;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "GetProcAddress", return_rip));
    const stub_address = state.regs.rax;
    try testing.expect(stub_address != 0);
    const stub = state.windowsImportStubAt(stub_address).?;
    try testing.expectEqualStrings("ntdll.dll", stub.dll_name);
    try testing.expectEqualStrings("NtSetEventBoostPriority", stub.function_name);
}

test "Xenia write-pointer wake repair follows the command-processor event" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const command_processor = state.guestAlloc(0x270, 8).?;
    const event_object = state.guestAlloc(16, 8).?;
    const gpu_ring_event = 0xFFFF_F000_0000_0F68;
    state.write64(command_processor + 0x260, event_object);
    state.write64(event_object + 8, gpu_ring_event);
    state.registerWindowsEvent(gpu_ring_event, false, false);
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0xF068 };
    state.windows_active_guest_thread_slot = 0;
    try testing.expectEqual(
        ElfState.WindowsWaitResult.blocked,
        state.waitWindowsGuestObject(gpu_ring_event, std.math.maxInt(u32)),
    );

    state.regs.rcx = command_processor;
    state.regs.rdx = 0x1234;
    state.repairXeniaGpuWritePointerWake();

    try testing.expectEqual(@as(u64, 1), state.windows_gpu_write_pointer_wake_repairs);
    try testing.expectEqual(@as(u64, 0), state.windows_gpu_write_pointer_wake_repair_misses);
    try testing.expectEqual(@as(u32, 0x1234), state.read32(command_processor + 0x268));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[0].status);
    try testing.expect(!state.windowsWaitObjectSignaled(gpu_ring_event));

    // A malformed command-processor pointer is a repair miss, not a broad
    // wake of an unrelated synthetic event.
    state.regs.rcx = 0;
    state.repairXeniaGpuWritePointerWake();
    try testing.expectEqual(@as(u64, 1), state.windows_gpu_write_pointer_wake_repair_misses);
}

test "empty Xenia VFS warnings require a matching kernel origin" {
    const line = "!> F8000014 ResolvePath() failed - device not found";
    try testing.expect(ElfState.isConfirmedEmptyResolvePathProbe(
        line,
        " emitted_by=' (F8000014)' last_kernel_call=xboxkrnl.exe!NtCreateFile at_step=12",
    ));
    try testing.expect(ElfState.isConfirmedEmptyResolvePathProbe(
        line,
        " emitted_by=' (F8000054)' last_kernel_call=xboxkrnl.exe!RtlNtStatusToDosError at_step=13",
    ));
    try testing.expect(ElfState.isConfirmedEmptyResolvePathProbe(
        line,
        " emitted_by=' (F8000014)' last_kernel_call=xboxkrnl.exe!RtlImageXexHeaderField at_step=14",
    ));
    try testing.expect(!ElfState.isConfirmedEmptyResolvePathProbe(line, " emitted_by='unknown' last_kernel_call=<none>"));
    try testing.expect(!ElfState.isConfirmedEmptyResolvePathProbe(
        "!> F8000014 ResolvePath(WavesLibDLL) failed - device not found",
        " last_kernel_call=xboxkrnl.exe!NtCreateFile",
    ));
}

test "bare module lookups are counted by name and never become fatal points" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.noteWindowsGuestOutput(
        "!> F8000014 ResolvePath(WavesLibDLL.dll) failed - device not found\n" ++
            "!> F8000014 ResolvePath(WavesLibDLL) failed - device not found\n" ++
            "!> F8000014 ResolvePath(WavesLibDLL) failed - device not found\n",
    );

    try testing.expectEqual(@as(u64, 3), state.windows_guest_warning_lines);
    try testing.expectEqual(@as(u64, 3), state.windows_guest_informational_lines);
    try testing.expectEqual(@as(u64, 3), state.windows_guest_module_lookup_lines);
    try testing.expectEqual(@as(usize, 2), state.windows_guest_module_lookup_count);
    try testing.expectEqualStrings("WavesLibDLL", state.windows_guest_module_lookups[1].nameText());
    try testing.expectEqual(@as(u64, 2), state.windows_guest_module_lookups[1].lines);
    try testing.expectEqual(@as(u64, 0), state.windows_guest_advisory_lines);
    try testing.expectEqual(@as(u64, 0), state.windows_fatal_point_events);
    try testing.expectEqual(@as(usize, 0), state.windows_guest_warning_point_count);
    // The unbound-import line that would make these a failure stays a fault;
    // `warning-severity-map` pins that, since a fault is written with log.err.
    try testing.expectEqual(@as(u64, 0), state.windows_guest_unresolved_import_lines);
}

test "VFS accounting separates reconciled module probes from device misses" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const bare_name = "WavesLibDLL";
    const bare_name_with_suffix = "WavesLibDLL.dll";
    const device_path = "game:\\WavesLibDLL.dll";
    const missing_device_path = "game:\\missing.dat";

    state.guest_vfs_resolve_count = 5;
    state.guest_vfs_resolves[0] = .{
        .path_len = @intCast(bare_name.len),
        .calls = 3,
        .not_found = 3,
    };
    @memcpy(state.guest_vfs_resolves[0].path[0..bare_name.len], bare_name);
    state.guest_vfs_resolves[1] = .{
        .path_len = @intCast(bare_name_with_suffix.len),
        .calls = 2,
        .not_found = 2,
    };
    @memcpy(state.guest_vfs_resolves[1].path[0..bare_name_with_suffix.len], bare_name_with_suffix);
    state.guest_vfs_resolves[2] = .{
        .path_len = @intCast(device_path.len),
        .calls = 1,
        .found = 1,
    };
    @memcpy(state.guest_vfs_resolves[2].path[0..device_path.len], device_path);
    state.guest_vfs_resolves[3] = .{
        .path_len = @intCast(missing_device_path.len),
        .calls = 2,
        .not_found = 2,
    };
    @memcpy(state.guest_vfs_resolves[3].path[0..missing_device_path.len], missing_device_path);
    state.guest_vfs_resolves[4] = .{ .calls = 1, .not_found = 1 };

    const summary = state.classifyGuestVfsResolves();
    try testing.expectEqual(@as(u64, 5), summary.bare_module_calls);
    try testing.expectEqual(@as(u64, 5), summary.bare_module_not_found);
    try testing.expectEqual(@as(u64, 2), summary.bare_module_paths);
    try testing.expectEqual(@as(u64, 2), summary.bare_module_paths_reconciled);
    try testing.expectEqual(@as(u64, 0), summary.bare_module_unmatched_not_found);
    try testing.expectEqual(@as(u64, 1), summary.empty_path_not_found);
    try testing.expectEqual(@as(u64, 2), summary.device_path_not_found);
    try testing.expectEqualStrings(device_path, state.guestVfsMatchedDevicePath(bare_name));
    try testing.expectEqualStrings(device_path, state.guestVfsMatchedDevicePath(bare_name_with_suffix));
    try testing.expectEqualStrings("", state.guestVfsMatchedDevicePath("missing.dll"));
}

test "a VFS resolve is recorded at entry and its result at return" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const view = MEM_BASE + 0x3000;
    const text = MEM_BASE + 0x3100;
    const name = "WavesLibDLL";
    @memcpy(state.guestMemory(text, name.len).?, name);
    state.write64(view, name.len);
    state.write64(view + 8, text);
    state.regs.rdx = view;
    state.regs.rsp = MEM_BASE + 0x8000;
    state.executed_steps = 77;
    state.noteGuestVfsResolveEntry();
    try testing.expectEqual(@as(u32, 1), state.guest_return_captures_armed);

    // A nested call's `ret` at a deeper stack pointer is not this call's.
    state.regs.rsp = MEM_BASE + 0x7F00;
    state.regs.rax = 0x1234;
    state.completeGuestReturnCapture();
    try testing.expectEqual(@as(u32, 1), state.guest_return_captures_armed);

    // The call's own `ret` returns null: device not found.
    state.regs.rsp = MEM_BASE + 0x8000;
    state.regs.rax = 0;
    state.completeGuestReturnCapture();
    try testing.expectEqual(@as(u32, 0), state.guest_return_captures_armed);
    const entry = state.guest_vfs_resolves[0];
    try testing.expectEqualStrings("WavesLibDLL", entry.pathText());
    try testing.expectEqual(@as(u64, 1), entry.not_found);
    var buffer: [384]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, state.describeVfsResolveFor("WavesLibDLL", &buffer), "not_found=1") != null);
    try testing.expectEqualStrings("", state.describeVfsResolveFor("Q10.dll", &buffer));
}

test "GPU register reads are counted by index with the value each returned" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const read_index = comptime xenia_guest_milestone_map.indexOf("_ZN2xe3gpu14GraphicsSystem17ReadRegisterThunkEPvPS1_j").?;
    const write_index = comptime xenia_guest_milestone_map.indexOf("_ZN2xe3gpu14GraphicsSystem18WriteRegisterThunkEPvPS1_jj").?;

    for (0..3) |_| {
        state.regs.r8 = 0x7FC8_0710; // CP_RB_RPTR, index 0x01C4
        state.regs.rsp = MEM_BASE + 0x8000;
        state.noteGuestMilestoneArguments(read_index);
        state.regs.rax = 0x20;
        state.completeGuestReturnCapture();
    }
    state.regs.r8 = 0x7FC8_0714; // CP_RB_WPTR, index 0x01C5
    state.regs.r9 = 0x40;
    state.noteGuestMilestoneArguments(write_index);

    try testing.expectEqual(@as(usize, 2), state.gpu_register_traffic_count);
    const rptr = state.gpu_register_traffic[0];
    try testing.expectEqual(@as(u16, 0x01C4), rptr.index);
    try testing.expectEqual(@as(u64, 3), rptr.reads);
    try testing.expectEqual(@as(u64, 3), rptr.read_returns);
    try testing.expectEqual(@as(u64, 0), rptr.read_value_changes);
    try testing.expectEqual(@as(u32, 0x20), rptr.last_read_value);
    try testing.expectEqual(@as(u32, 0x40), state.gpu_register_traffic[1].last_write_value);
    try testing.expectEqualStrings("CP_RB_WPTR", ElfState.xenosRegisterName(0x01C5));
}

test "strlen reads a string that lives in a Windows allocation, not only in the image" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = state.mem_base + 0x1000;
    const base = 0x40DFFF0000;
    state.regs.rcx = base;
    state.regs.rdx = 0x10000;
    state.regs.r8 = 0x2000 | 0x1000;
    state.regs.r9 = 0x04;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "VirtualAlloc", return_rip));
    try testing.expectEqual(@as(u64, base), state.regs.rax);
    try testing.expect(state.addrToOffset(base) == null);

    // The 2026-09-13 names: Xenia's RtlInitAnsiString called strlen on
    // exactly these, in guest memory outside the image, and got 0.
    const name = base + 0x2340;
    for ("cache0:\\preferences.dat", 0..) |byte, index| state.write8(name + @as(u64, @intCast(index)), byte);
    state.write8(name + 23, 0);
    state.regs.rcx = name;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "strlen", return_rip));
    try testing.expectEqual(@as(u64, 23), state.regs.rax);

    state.regs.rcx = name;
    state.regs.rdx = 6;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "strnlen", return_rip));
    try testing.expectEqual(@as(u64, 6), state.regs.rax);
    try testing.expectEqual(@as(u64, 0), state.windows_crt_unreadable_pointers);

    // A string running off the end of its region is unterminated, not short.
    const last = base + 0x10000 - 2;
    state.write8(last, 'a');
    state.write8(last + 1, 'b');
    try testing.expect(state.guestCStringConst(last, 64) == null);
}

test "Windows guest scalar accesses use the default per-context TSO store buffer" {
    var state = ElfState.initWithMemory(testing.allocator, 0x10000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    try testing.expect(!state.parallel_guest_execution);

    const buffer = state.activeGuestTsoStoreBuffer() orelse return error.MissingStoreBuffer;
    const prior_buffer = tso_memory.setActiveStoreBuffer(buffer);
    defer _ = tso_memory.setActiveStoreBuffer(prior_buffer);
    const prior_mode = tso_memory.setCoordinatedGuestAccess(false);
    defer _ = tso_memory.setCoordinatedGuestAccess(prior_mode);

    const address = state.mem_base + 0x200;
    state.write32(address, 0xA1B2_C3D4);
    try testing.expectEqual(@as(usize, 1), buffer.pendingCount());
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, state.mem[0x200..][0..4], .little));
    try testing.expectEqual(@as(u32, 0xA1B2_C3D4), state.read32(address));

    const borrowed = state.guestMemoryConst(address, 4) orelse return error.MissingGuestMemory;
    try testing.expectEqual(@as(usize, 0), buffer.pendingCount());
    try testing.expectEqual(@as(u32, 0xA1B2_C3D4), std.mem.readInt(u32, borrowed[0..4], .little));
}

test "guest bulk helpers snapshot and publish memory in coordinated TSO mode" {
    var state = ElfState.initWithMemory(testing.allocator, 0x10000);
    defer state.deinit();

    const source = state.mem_base + 0x100;
    const destination = state.mem_base + 0x200;
    for ("coordinated guest string", 0..) |byte, index| {
        state.write8(source + @as(u64, @intCast(index)), byte);
    }
    state.write8(source + 24, 0);

    state.parallel_guest_execution = true;
    var string_storage: [64]u8 = undefined;
    const string_length = state.copyGuestCString(source, string_storage.len + 1, string_storage[0..]) orelse return error.MissingTerminator;
    try testing.expectEqualStrings("coordinated guest string", string_storage[0..string_length]);

    try testing.expect(state.copyToGuest(destination, string_storage[0..string_length]));
    var snapshot: [24]u8 = undefined;
    try testing.expect(state.copyFromGuest(snapshot[0..], destination));
    try testing.expectEqualSlices(u8, string_storage[0..string_length], snapshot[0..]);
    try testing.expect(state.fillGuestMemory(destination, snapshot.len, 0x5A));
    try testing.expectEqual(@as(u8, 0x5A), state.read8(destination + 23));
}

test "parallel CRT memcpy memmove and memset use coordinated guest memory routes" {
    var state = ElfState.initWithMemory(testing.allocator, 0x10000);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const source = state.mem_base + 0x100;
    const destination = state.mem_base + 0x200;
    // Executable bytes are the one range a parallel raw view is refused
    // for, so marking the buffers executable proves that every route below
    // writes through the ordered API rather than a borrowed slice.
    state.configureWindowsExecutableRanges(&[_]WindowsExecutableRange{
        .{ .guest_base = source, .length = 0x200 },
    });
    const initial = "abcdefgh";
    try testing.expect(state.copyToGuest(source, initial));
    state.parallel_guest_execution = true;
    try testing.expect(state.guestMemory(source, initial.len) == null);

    const return_rip = state.mem_base + 0x1000;
    state.regs.rcx = destination;
    state.regs.rdx = source;
    state.regs.r8 = initial.len;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memcpy", return_rip));
    try testing.expectEqual(destination, state.regs.rax);

    var copied: [8]u8 = undefined;
    try testing.expect(state.copyFromGuest(&copied, destination));
    try testing.expectEqualSlices(u8, initial, &copied);

    // memmove must use guest virtual-address overlap direction even though
    // the guest backing is only available through coordinated access.
    state.regs.rcx = source + 2;
    state.regs.rdx = source;
    state.regs.r8 = 6;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memmove", return_rip));
    var moved: [8]u8 = undefined;
    try testing.expect(state.copyFromGuest(&moved, source));
    try testing.expectEqualSlices(u8, "ababcdef", &moved);

    state.regs.rcx = destination;
    state.regs.rdx = 0x5A;
    state.regs.r8 = 8;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memset", return_rip));
    var filled: [8]u8 = undefined;
    try testing.expect(state.copyFromGuest(&filled, destination));
    try testing.expectEqualSlices(u8, &.{ 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A }, &filled);

    // std::regex's classic locale calls strxfrm. Its terminator must also
    // use the coordinated writer; checking only guestMemory would silently
    // leave a stale byte here because these executable bytes refuse a
    // parallel mutable borrow.
    const collation_source = source + 0x40;
    const collation_destination = destination + 0x40;
    try testing.expect(state.copyToGuest(collation_source, "regex"));
    try testing.expect(state.fillGuestMemory(collation_destination, 6, 0xAA));
    state.regs.rcx = collation_destination;
    state.regs.rdx = collation_source;
    state.regs.r8 = 6;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "strxfrm", return_rip));
    try testing.expectEqual(@as(u64, 5), state.regs.rax);
    var transformed: [6]u8 = undefined;
    try testing.expect(state.copyFromGuest(&transformed, collation_destination));
    try testing.expectEqualSlices(u8, "regex\x00", &transformed);
    try testing.expectEqual(@as(u64, 0), state.windows_crt_unreadable_pointers);
}

test "a C runtime import handed an unreadable pointer stops the run, and a zero-byte copy does not" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_fatal_point_terminate = true;
    const return_rip = state.mem_base + 0x1000;

    state.regs.rcx = 0x7777_0000_0000;
    state.regs.rdx = 0x7777_0000_1000;
    state.regs.r8 = 0;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memcpy", return_rip));
    try testing.expectEqual(@as(u64, 0x7777_0000_0000), state.regs.rax);
    try testing.expect(!state.terminated);

    state.regs.rcx = 0x7777_0000_0000;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "strlen", return_rip));
    try testing.expect(state.terminated);
    try testing.expectEqual(@as(u64, 1), state.windows_crt_unreadable_pointers);
}

test "WaitForMultipleObjects parks a worker until one of its handles is signalled" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const event: u64 = 0xFFFF_F000_0000_0A01;
    const semaphore: u64 = 0xFFFF_F000_0000_0A02;
    state.registerWindowsEvent(event, false, false);
    state.registerWindowsSemaphore(semaphore, 0, 4);
    state.windows_guest_threads[4] = .{ .status = .running, .handle = 0xE0 };
    state.windows_active_guest_thread_slot = 4;

    // winpthreads' shape: its semaphore and the thread's cancel event.
    const handles = [_]u64{ event, semaphore };
    try testing.expectEqual(WindowsMultiWaitResult.blocked, state.waitWindowsGuestObjects(&handles, false, std.math.maxInt(u32)));
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[4].status);

    // The second handle wakes it and hands its count over as it does.
    try testing.expect(state.releaseWindowsSemaphore(semaphore, 1));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[4].status);
    try testing.expectEqual(@as(u32, 0), state.windowsWaitObjectSemaphoreCount(semaphore).?);

    // The retried call answers WAIT_OBJECT_0 + 1.
    state.windows_guest_threads[4].status = .running;
    const resumed = state.waitWindowsGuestObjects(&handles, false, std.math.maxInt(u32));
    try testing.expectEqual(@as(u32, 1), resumed.signaled);

    // A ready object is taken at once, and an auto-reset event with it.
    _ = state.signalWindowsWaitObject(event, false);
    try testing.expectEqual(@as(u32, 0), state.waitWindowsGuestObjects(&handles, false, 500).signaled);
    try testing.expectEqual(@as(?bool, false), state.windowsWaitObjectReady(event));

    // Nothing ready and no time to wait is a timeout, not a success.
    try testing.expectEqual(WindowsMultiWaitResult.timeout, state.waitWindowsGuestObjects(&handles, false, 0));

    // A handle with no object behind it is reported as such.
    const bogus = [_]u64{ event, 0xFFFF_F000_0000_0BAD };
    try testing.expectEqual(@as(u64, 0xFFFF_F000_0000_0BAD), state.waitWindowsGuestObjects(&bogus, false, 0).unknown);
}

test "a timed multi-object wait times out on the guest clock" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_clock.source = .retired_instructions;
    const event: u64 = 0xFFFF_F000_0000_0A11;
    const cancel: u64 = 0xFFFF_F000_0000_0A12;
    state.registerWindowsEvent(event, false, false);
    state.registerWindowsEvent(cancel, true, false);
    state.windows_guest_threads[2] = .{ .status = .running, .handle = 0xC2 };
    state.windows_active_guest_thread_slot = 2;
    const handles = [_]u64{ event, cancel };

    state.guest_clock.ticks = 1_000;
    try testing.expectEqual(WindowsMultiWaitResult.blocked, state.waitWindowsGuestObjects(&handles, false, 500));
    state.windows_active_guest_thread_slot = null;
    state.guest_clock.ticks = 1_000 + 499 * WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
    try testing.expectEqual(@as(u64, 0), state.wakeExpiredWindowsGuestWaits());
    state.guest_clock.ticks = 1_000 + 500 * WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
    try testing.expectEqual(@as(u64, 1), state.wakeExpiredWindowsGuestWaits());

    state.windows_active_guest_thread_slot = 2;
    state.windows_guest_threads[2].status = .running;
    try testing.expectEqual(WindowsMultiWaitResult.timeout, state.waitWindowsGuestObjects(&handles, false, 500));
    try testing.expectEqual(@as(u8, 0), state.windows_guest_threads[2].blocked_wait_handle_count);
}

test "a wait-all takes every object together or none of them" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const first: u64 = 0xFFFF_F000_0000_0A21;
    const second: u64 = 0xFFFF_F000_0000_0A22;
    state.registerWindowsEvent(first, false, true);
    state.registerWindowsSemaphore(second, 0, 1);
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0xC1 };
    state.windows_active_guest_thread_slot = 1;
    const handles = [_]u64{ first, second };

    try testing.expectEqual(WindowsMultiWaitResult.blocked, state.waitWindowsGuestObjects(&handles, true, std.math.maxInt(u32)));
    // The ready event was not taken while the semaphore was not.
    try testing.expectEqual(@as(?bool, true), state.windowsWaitObjectReady(first));

    // The release wakes it to look again without handing the count over.
    try testing.expect(state.releaseWindowsSemaphore(second, 1));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[1].status);
    try testing.expectEqual(@as(u32, 1), state.windowsWaitObjectSemaphoreCount(second).?);

    state.windows_guest_threads[1].status = .running;
    try testing.expectEqual(@as(u32, 0), state.waitWindowsGuestObjects(&handles, true, std.math.maxInt(u32)).signaled);
    try testing.expectEqual(@as(?bool, false), state.windowsWaitObjectReady(first));
    try testing.expectEqual(@as(u32, 0), state.windowsWaitObjectSemaphoreCount(second).?);
}

test "a deliberate export refusal is recorded as policy with the path the caller takes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.noteWindowsProcAddressPolicyRefusal("api-ms-win-core-synch-l1-2-0.dll", "WaitOnAddress", 0x140ff323a, "kernel-semaphore-path", "KERNELBASE.dll");
    try testing.expectEqual(@as(u32, 1), state.windows_proc_refusal_count);
    try testing.expect(!state.windows_proc_refusals[0].is_gap);
}

test "a thread created suspended is not scheduled until ResumeThread releases it" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_process_peb = MEM_BASE;

    const entry = MEM_BASE + 0x1A00;
    state.write8(entry, 0x58); // pop rax: consume the synthetic return marker
    state.write8(entry + 1, 0xC3);
    const handle = 0xFFFF_F000_0000_0911;
    try testing.expect(state.enqueueWindowsGuestThread(handle, entry, 0, 0, false));
    state.suspendWindowsGuestThreadAtCreation(handle);

    // Held: nothing runs, whatever the scheduler is asked.
    try testing.expectEqual(@as(u64, 0), state.serviceWindowsGuestThreads(16));
    try testing.expectEqual(WindowsGuestThreadStatus.pending, state.windows_guest_threads[0].status);

    // Suspensions stack, and each call answers the count it found.
    try testing.expectEqual(@as(u64, 1), state.changeWindowsGuestThreadSuspension(handle, true));
    try testing.expectEqual(@as(u64, 2), state.changeWindowsGuestThreadSuspension(handle, false));
    try testing.expectEqual(@as(u64, 0), state.serviceWindowsGuestThreads(16));
    try testing.expectEqual(@as(u64, 1), state.changeWindowsGuestThreadSuspension(handle, false));

    _ = state.serviceWindowsGuestThreads(16);
    try testing.expectEqual(WindowsGuestThreadStatus.completed, state.windows_guest_threads[0].status);

    try testing.expectEqual(@as(u64, std.math.maxInt(u32)), state.changeWindowsGuestThreadSuspension(0xFFFF_F000_0000_0999, false));
    try testing.expectEqual(@as(u32, 6), state.windows_last_error);
}

test "CreateThread honours CREATE_SUSPENDED and writes the thread id" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_process_peb = MEM_BASE;

    const entry = MEM_BASE + 0x1A00;
    state.write8(entry, 0x58);
    state.write8(entry + 1, 0xC3);
    const stack = state.guestAlloc(0x100, 16).?;
    const thread_id_out = state.guestAlloc(8, 8).?;
    state.write64(stack + 32, 0x4); // dwCreationFlags = CREATE_SUSPENDED
    state.write64(stack + 40, thread_id_out);
    state.regs.rsp = stack;
    state.regs.rcx = 0;
    state.regs.rdx = 0;
    state.regs.r8 = entry;
    state.regs.r9 = 0;
    const return_rip = MEM_BASE + 0x880;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "CreateThread", return_rip));
    const handle = state.regs.rax;
    const index = state.windowsGuestThreadIndex(handle) orelse return error.ThreadNotQueued;
    try testing.expectEqual(@as(u32, 1), state.windows_guest_threads[index].suspend_count);
    try testing.expectEqual(@as(u32, @truncate(state.windows_guest_threads[index].thread_id)), state.read32(thread_id_out));
    try testing.expectEqual(@as(u64, 0), state.serviceWindowsGuestThreads(16));

    state.regs.rcx = handle;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "ResumeThread", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u32, 0), state.windows_guest_threads[index].suspend_count);
}

test "an interpreted access to the null page stops the run instead of answering zero" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_fatal_point_terminate = true;
    state.guest_null_page_fatal = true;

    try testing.expectEqual(@as(u64, 0), state.readMemVal(0x20, .bits64));
    try testing.expect(state.terminated);
    try testing.expect(state.faulted);
    try testing.expectEqual(exit_diagnostics.TerminationReason.memory_access_violation, state.termination_reason);
    try testing.expectEqual(@as(u64, 1), state.guest_null_page_accesses);

    // Allowed by label, the access is still counted and the run continues.
    var allowed = ElfState.init(testing.allocator);
    defer allowed.deinit();
    allowed.windows_runtime_enabled = true;
    allowed.windows_fatal_point_terminate = true;
    allowed.guest_null_page_fatal = true;
    allowed.configureWindowsFatalPointAllow("guest-null-page-access");
    allowed.writeMemVal(0x8, .bits32, 1);
    try testing.expect(!allowed.terminated);
    try testing.expectEqual(@as(u64, 1), allowed.guest_null_page_accesses);
    try testing.expectEqual(@as(u64, 1), allowed.windows_fatal_point_allowed_events);
}

test "a fatal point named in the allow-list is stepped past and any other stops the run" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_fatal_point_terminate = true;
    state.configureWindowsFatalPointAllow("vulkan-tessellation-unavailable, vfs-empty-object-name");
    state.terminateForWindowsFatalPoint("vfs-empty-object-name");
    try testing.expect(!state.terminated);
    try testing.expectEqual(@as(u64, 1), state.windows_fatal_point_allowed_events);
    // A prefix of an allowed label is a different label.
    state.terminateForWindowsFatalPoint("vulkan-tessellation");
    try testing.expect(state.terminated);
    try testing.expectEqual(@as(u64, 125), state.exit_code);
}

test "a degradation with no named ground stops the run and a policy decision does not" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_fatal_point_terminate = true;
    state.noteWindowsGuestWarning("w> 00000001 Unable to load Japanese font; JP characters will be boxes");
    try testing.expect(!state.terminated);
    state.noteWindowsGuestWarning("w> 0100000C VulkanPipelineCache: Failed to create one or more tessellation shaders - tessellation will not be available");
    try testing.expect(state.terminated);
}

test "known Xenia cleanup and allocation fallbacks do not become fatal points" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_fatal_point_terminate = true;
    state.noteWindowsGuestWarning("!> F8000014 undefined extern call to 8270D7E4 IoDismountVolumeByFileHandle");
    state.noteWindowsGuestWarning("!> F8000054 undefined extern call to 8270D6E4 IoDismountVolume");
    state.noteWindowsGuestWarning("w> F8000054 Game is attempting to allocate devkit debug memory (base: 00000000, size: 000FF000). Ignoring debug flag and using normal allocation.");
    state.noteWindowsGuestWarning("w> F8000064 NtSetInformationFile ignoring alloc");
    try testing.expect(!state.terminated);
    try testing.expectEqual(@as(u64, 4), state.windows_guest_warning_lines);
    try testing.expectEqual(@as(u64, 4), state.windows_guest_advisory_lines);
    try testing.expectEqual(@as(u64, 0), state.windows_fatal_point_events);
    try testing.expectEqual(@as(usize, 4), state.windows_guest_warning_point_count);
}

test "an empty resolve is traced to the object name the title passed" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    // A PPC context and a guest address space, laid out the way the export
    // trampoline sees them.
    const context = state.guestAlloc(0xB00, 16).?;
    const membase = state.guestAlloc(0x200, 16).?;
    state.write64(context + PPC_CONTEXT_VIRTUAL_MEMBASE, membase);
    state.write64(context + PPC_CONTEXT_LINK_REGISTER, 0x8200_1234);
    state.write64(context + ppcContextGpr(4), 0x8010_0000);
    state.write64(context + ppcContextGpr(5), 0x100);
    state.write32(membase + 0x100, 0); // root_directory
    state.write32(membase + 0x104, @byteSwap(@as(u32, 0x110))); // name_ptr
    state.write16(membase + 0x110, 0); // length
    state.write16(membase + 0x112, @byteSwap(@as(u16, 64))); // maximum_length
    state.write32(membase + 0x114, @byteSwap(@as(u32, 0x120))); // pointer
    const path = "game:\\media\\a.bin";
    for (path, 0..) |byte, index| state.write8(membase + 0x120 + @as(u64, @intCast(index)), byte);

    state.regs.rcx = context;
    state.captureGuestFileRequest(1);
    const request = &state.owner_file_request;
    try testing.expect(request.captured);
    try testing.expect(!request.unreadable);
    try testing.expectEqual(@as(u32, 0x8200_1234), request.link_register);
    try testing.expectEqual(@as(u32, 0x110), request.name_pointer);
    try testing.expectEqual(@as(u16, 64), request.name_maximum);
    try testing.expectEqualStrings(path, request.previewText());
    try testing.expectEqual(GuestFileNameShape.zero_length_with_text, ElfState.classifyGuestFileRequestName(request));

    state.write16(membase + 0x110, @byteSwap(@as(u16, @intCast(path.len))));
    state.captureGuestFileRequest(1);
    try testing.expectEqual(GuestFileNameShape.named, ElfState.classifyGuestFileRequestName(&state.owner_file_request));

    state.write8(membase + 0x120, 0);
    state.write16(membase + 0x110, 0);
    state.captureGuestFileRequest(1);
    try testing.expectEqual(GuestFileNameShape.zero_length_empty, ElfState.classifyGuestFileRequestName(&state.owner_file_request));

    // And the failed resolve that follows stops the run under its own label.
    state.windows_fatal_point_terminate = true;
    const resolve = GuestVfsResolve{};
    state.faultGuestVfsEmptyName(&resolve);
    try testing.expect(state.terminated);
    try testing.expectEqual(@as(u64, 1), state.guest_vfs_empty_name_faults);
}

test "an indirect buffer the ring names is decoded for the draws and swaps it carries" {
    const ArraySource = struct {
        dwords: []const u32,

        pub fn readDword(self: @This(), index: u64) ?u32 {
            if (index >= self.dwords.len) return null;
            return self.dwords[@intCast(index)];
        }

        pub fn aliasCheck(self: @This(), index: u64, value: u32) struct { checked: u16, mismatched: u16 } {
            _ = self;
            _ = index;
            _ = value;
            return .{ .checked = 0, .mismatched = 0 };
        }
    };
    // The 2026-09-13 ring's second window: INDIRECT_BUFFER to 0x050F0000.
    const ring = [_]u32{ 0xC001_3F00, 0x050F_0000, 0x0000_0040 };
    var ring_window = GpuRingWindow{};
    ElfState.decodeGpuRingWindow(ArraySource{ .dwords = &ring }, &ring_window, 0, ring.len, ring.len);
    try testing.expectEqual(@as(u32, 1), ring_window.type3);
    try testing.expectEqual(@as(u8, 1), ring_window.indirect_buffers);
    try testing.expectEqual(@as(u32, 0x050F_0000), ring_window.indirect_addresses[0]);
    try testing.expectEqual(@as(u32, 0x40), ring_window.indirect_dwords[0]);
    try testing.expectEqual(@as(u32, 0), ring_window.draw_packets);

    const buffer = [_]u32{ 0xC000_2200, 0x0000_0000, 0xC000_6400, 0x0000_0000 };
    var buffer_window = GpuRingWindow{};
    ElfState.decodeGpuRingWindow(ArraySource{ .dwords = &buffer }, &buffer_window, 0, buffer.len, buffer.len);
    try testing.expectEqual(@as(u32, 2), buffer_window.type3);
    try testing.expectEqual(@as(u32, 1), buffer_window.draw_packets);
    try testing.expectEqual(@as(u32, 1), buffer_window.swap_packets);
    try testing.expectEqualStrings("XE_SWAP", ElfState.pm4OpcodeLabel(0x64));
}

test "the ring carried type 3 work when its opcode handlers ran with the dispatcher inlined" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const me_init = xenia_guest_milestone_map.indexOf("_ZN2xe3gpu6vulkan22VulkanCommandProcessor26ExecutePacketType3_ME_INITEjj") orelse return error.MissingMilestone;
    state.guest_milestone_hits[me_init] = 1;
    try testing.expectEqual(@as(u64, 1), state.gpuType3HandlerEntries());
    var found = false;
    for (state.guestOutputChainStages()) |stage| {
        if (!std.mem.eql(u8, stage.name, "ring_carried_pm4")) continue;
        found = true;
        try testing.expect(stage.met);
        try testing.expect(stage.observable);
        try testing.expectEqual(@as(u64, 1), stage.value);
    }
    try testing.expect(found);
}

test "GPU ring decoding retains the submitted native fence write packet" {
    const Source = struct {
        dwords: []const u32,
        pub fn readDword(self: @This(), index: u64) ?u32 {
            if (index >= self.dwords.len) return null;
            return self.dwords[index];
        }
        pub fn aliasCheck(_: @This(), _: u64, _: u32) struct { checked: u16, mismatched: u16 } {
            return .{ .checked = 0, .mismatched = 0 };
        }
    };
    const words = [_]u32{ 0xC002_5800, 3, 0x1FC9_F000, 3445 };
    var window = GpuRingWindow{};
    ElfState.decodeGpuRingWindow(Source{ .dwords = &words }, &window, 0, words.len, words.len);
    try testing.expectEqual(@as(u32, 1), window.event_write_count);
    try testing.expectEqual(@as(u32, 0x1FC9_F000), window.last_event_writes[0].address);
    try testing.expectEqual(@as(u32, 3445), window.last_event_writes[0].value);
}

test "a register Xenia answers with a constant is not a poll waiting on a writer" {
    try testing.expectEqual(@as(?u32, 1), ElfState.xeniaConstantRegisterRead(0x1951));
    try testing.expectEqual(@as(?u32, null), ElfState.xeniaConstantRegisterRead(0x01C5));
}

test "a ring window is decoded the way Xenia's ExecutePacket walks it" {
    const Source = struct {
        dwords: []const u32,
        alias_differs_at: ?u64 = null,

        pub fn readDword(self: @This(), ring_index: u64) ?u32 {
            if (ring_index >= self.dwords.len) return null;
            return self.dwords[ring_index];
        }

        pub fn aliasCheck(self: @This(), ring_index: u64, value: u32) struct { checked: u16, mismatched: u16 } {
            _ = value;
            const differs = self.alias_differs_at != null and self.alias_differs_at.? == ring_index;
            return .{ .checked = 2, .mismatched = if (differs) 1 else 0 };
        }
    };
    // ME_INIT (type 3, opcode 0x48, 2 payload dwords), a type 0 write of one
    // register, a zero pad, and the marker Xenia also skips.
    const ring = [_]u32{ 0xC001_4800, 0x1111_1111, 0x2222_2222, 0x0000_0100, 0x3333_3333, 0, 0x0BAD_F00D, 0 };
    var window = GpuRingWindow{};
    ElfState.decodeGpuRingWindow(Source{ .dwords = &ring }, &window, 0, ring.len, 16);
    try testing.expect(window.readable);
    try testing.expectEqual(@as(u32, 8), window.decoded);
    try testing.expectEqual(@as(u32, 1), window.type3);
    try testing.expectEqual(@as(u8, 0x48), window.type3_opcodes[0]);
    try testing.expectEqual(@as(u32, 1), window.type0);
    try testing.expectEqual(@as(u32, 2), window.zero_dwords);
    try testing.expectEqual(@as(u32, 1), window.marker_dwords);
    try testing.expectEqual(@as(u16, 16), window.alias_checks);

    // A ring of nothing but zeros decodes as no packets at all, and a view
    // disagreement is counted.
    const empty = [_]u32{ 0, 0, 0, 0 };
    var zero_window = GpuRingWindow{};
    ElfState.decodeGpuRingWindow(Source{ .dwords = &empty, .alias_differs_at = 1 }, &zero_window, 0, empty.len, 16);
    try testing.expectEqual(@as(u32, 4), zero_window.zero_dwords);
    try testing.expectEqual(@as(u32, 0), zero_window.type0 + zero_window.type3);
    try testing.expectEqual(@as(u16, 1), zero_window.alias_mismatches);
}

test "Xenia's membase is the view whose mapping also holds the physical view" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    try testing.expectEqual(@as(?u64, null), state.xeniaVirtualMembase());
    // A media file mapped whole is 1 GiB and offset 0, and is not it.
    state.windows_memory_views[0] = .{ .guest_base = 0x4000_0000_0000, .length = 0x1_6000_0000, .mapping_index = 3, .backing_offset = 0 };
    state.windows_memory_views[1] = .{ .guest_base = 0x2_0000_0000, .length = 0x4000_0000, .mapping_index = 1, .backing_offset = 0 };
    state.windows_memory_view_count = 2;
    try testing.expectEqual(@as(?u64, null), state.xeniaVirtualMembase());
    state.windows_memory_views[2] = .{ .guest_base = 0x3_0000_0000, .length = 0x2000_0000, .mapping_index = 1, .backing_offset = 0x1_0000_0000 };
    state.windows_memory_view_count = 3;
    try testing.expectEqual(@as(?u64, 0x2_0000_0000), state.xeniaVirtualMembase());
    var buffer: [96]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, state.describeXeniaGuestAddress(0x2_7FC8_0714, &buffer), "gpu_register=0x01c5 CP_RB_WPTR") != null);
}

test "a WinMM writer ahead of the host clock is told to wait, and one behind it is not" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    var device = WindowsWaveOutDevice{ .sample_rate = 48_000, .block_align = 8, .opened = true };
    // The owner context cannot park, so it is never paced.
    try testing.expectEqual(@as(u64, 0), state.paceWindowsWaveOutWrite(&device, 2048));
    state.windows_active_guest_thread_slot = 0;
    var waited: u64 = 0;
    // 2048 bytes is 256 stereo float frames: 5.3 ms each. Sixty buffers is
    // 320 ms of audio, far past the lead, written in no time at all.
    for (0..60) |_| {
        const wait_ms = state.paceWindowsWaveOutWrite(&device, 2048);
        if (wait_ms != 0) {
            waited = wait_ms;
            break;
        }
    }
    try testing.expect(waited >= 1);
    try testing.expectEqual(@as(u64, 1), state.windows_audio_pacing_waits);
}

test "a guest output flood reaches the host bounded and the guest is told it all went" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    var output_flags: std.c.O = .{};
    output_flags.ACCMODE = .WRONLY;
    const sink_fd = std.c.open("/dev/null", output_flags, @as(std.c.mode_t, 0));
    try testing.expect(sink_fd >= 0);
    defer _ = std.c.close(sink_fd);
    const line = "!> F8000014 ResolvePath(WavesLibDLL) failed - device not found\n";
    for (0..200) |_| {
        try testing.expectEqual(line.len, state.writeWindowsGuestStandardOutput(sink_fd, 1, line));
    }
    const governor = &state.windows_guest_output_governors.?[0];
    try testing.expectEqual(@as(u64, 200), governor.lines);
    try testing.expectEqual(@as(u64, 16), governor.passed_lines);
    try testing.expectEqual(@as(u64, 184), governor.withheld_repeat_lines);
    try testing.expectEqual(@as(u64, 0), state.windows_guest_output_host_write_failures);
}

test "an SRW handoff schedules the new owner next" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const lock_address = MEM_BASE + 0x2200;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .runnable, .handle = 0x11, .thread_id = 6 };
    state.windows_guest_threads[5] = .{ .status = .running, .handle = 0x15, .thread_id = 9 };

    state.windows_active_guest_thread_slot = 0;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(lock_address));
    state.windows_active_guest_thread_slot = 5;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.acquireWindowsSrwLock(lock_address));
    try testing.expect(state.blockWindowsGuestThreadOnSrwLock(lock_address));

    state.windows_active_guest_thread_slot = 0;
    state.windows_last_serviced_guest_thread_slot = 0;
    state.releaseWindowsSrwLock(lock_address);
    try testing.expectEqual(@as(u64, 1), state.windows_srw_directed_handoffs);
    try testing.expect(state.windows_guest_slice_yield_requested);
    // The circular scan from slot 0 would pick slot 1; the new owner in slot
    // 5 goes first.
    state.windows_active_guest_thread_slot = null;
    try testing.expectEqual(@as(?usize, 5), state.nextWindowsGuestThread());
}

test "WinMM waveOut completes guest buffers and callback frames" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x900;
    const format = MEM_BASE + 0x1000;
    const output_handle = MEM_BASE + 0x1040;
    const header = MEM_BASE + 0x1100;
    const data = MEM_BASE + 0x1200;
    const callback = MEM_BASE + 0x1300;
    const callback_stack = MEM_BASE + 0x2000;

    state.write16(format + 0, 3); // WAVE_FORMAT_IEEE_FLOAT
    state.write16(format + 2, 2); // stereo
    state.write32(format + 4, 48_000);
    state.write32(format + 8, 384_000);
    state.write16(format + 12, 8);
    state.write16(format + 14, 32);
    state.write16(format + 16, 0);

    state.regs = .{};
    state.regs.r8 = format;
    state.regs.rsp = callback_stack;
    state.write64(callback_stack + 40, 1); // WAVE_FORMAT_QUERY
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "WINMM.dll", "waveOutOpen", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);

    state.regs = .{};
    state.regs.rcx = output_handle;
    state.regs.rdx = 0xFFFF_FFFF;
    state.regs.r8 = format;
    state.regs.r9 = callback;
    state.regs.rsp = callback_stack;
    state.write64(callback_stack, return_rip);
    state.write64(callback_stack + 8, 0);
    state.write64(callback_stack + 40, 0x0003_0000); // CALLBACK_FUNCTION
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "WINMM.dll", "waveOutOpen", return_rip));
    const handle = state.read64(output_handle);
    try testing.expect(handle != 0);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);

    state.write64(header + 0, data);
    state.write32(header + 8, 16);
    state.write32(data + 0, 0x3f80_0000);
    state.write32(data + 4, 0xbf80_0000);
    state.regs = .{};
    state.regs.rcx = handle;
    state.regs.rdx = header;
    state.regs.r8 = 48;
    state.regs.rsp = callback_stack;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "WINMM.dll", "waveOutPrepareHeader", return_rip));

    state.regs = .{};
    state.regs.rcx = handle;
    state.regs.rdx = header;
    state.regs.r8 = 48;
    state.regs.rsp = callback_stack;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "WINMM.dll", "waveOutWrite", return_rip));
    try testing.expectEqual(SYNTHETIC_WINDOWS_AUDIO_RETURN, state.read64(state.regs.rsp));
    try testing.expectEqual(callback, state.regs.rip);
    try testing.expectEqual(@as(usize, 1), state.windows_audio_callback_frame_count);
    try testing.expect((state.read32(header + 24) & 0x3) == 0x3);

    state.regs.rsp += 8; // The callback's ordinary `ret` consumes the marker.
    state.regs.rip = SYNTHETIC_WINDOWS_AUDIO_RETURN;
    try testing.expect(state.handleSyntheticRip());
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(@as(usize, 0), state.windows_audio_callback_frame_count);
    try testing.expectEqual(@as(u64, 1), state.windows_audio_nonzero_buffers);
    try testing.expectEqual(@as(u64, 16), state.windows_audio_bytes_submitted);
}

test "fixed VirtualAlloc reservations do not alias Xenia thread contexts" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x5A0;
    const context_pre: u64 = 0x40DFFF0000;
    const context_allocation_size: u64 = 0x11000;

    state.regs = .{};
    state.regs.rcx = context_pre;
    state.regs.rdx = context_allocation_size;
    state.regs.r8 = 0x3000; // MEM_RESERVE | MEM_COMMIT
    state.regs.r9 = 0x04; // PAGE_READWRITE
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "VirtualAlloc", return_rip));
    try testing.expectEqual(context_pre, state.regs.rax);

    // A second reserve/commit at the same fixed address must fail. Xenia's
    // AllocateContext loop relies on this result to advance to the next
    // 0x..E0000000 context slot instead of aliasing the first one.
    state.regs = .{};
    state.regs.rcx = context_pre;
    state.regs.rdx = context_allocation_size;
    state.regs.r8 = 0x3000;
    state.regs.r9 = 0x04;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "VirtualAlloc", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);

    // The next fixed slot remains available and receives its own backing.
    const next_context_pre = context_pre + 0x1_0000_0000;
    state.regs = .{};
    state.regs.rcx = next_context_pre;
    state.regs.rdx = context_allocation_size;
    state.regs.r8 = 0x3000;
    state.regs.r9 = 0x04;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "VirtualAlloc", return_rip));
    try testing.expectEqual(next_context_pre, state.regs.rax);
}

test "a CRT comparison or search is answered, not stubbed, and the ledger separates the two" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x680;
    const left = MEM_BASE + 0xD00;
    const right = MEM_BASE + 0xD40;

    // "Alpha" vs "ALPHA" must compare equal, and "Alpha" vs "Beta" must not.
    // A zero-returning stub says both are equal, which silently makes every
    // case-insensitive lookup match whatever the guest tried first.
    for ("Alpha\x00", 0..) |ch, index| state.write8(left + @as(u64, @intCast(index)), ch);
    for ("ALPHA\x00", 0..) |ch, index| state.write8(right + @as(u64, @intCast(index)), ch);
    state.regs = .{};
    state.regs.rcx = left;
    state.regs.rdx = right;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-string-l1-1-0.dll", "_stricmp", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);

    for ("Beta\x00", 0..) |ch, index| state.write8(right + @as(u64, @intCast(index)), ch);
    state.regs = .{};
    state.regs.rcx = left;
    state.regs.rdx = right;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-string-l1-1-0.dll", "_stricmp", return_rip));
    try testing.expect(@as(i64, @bitCast(state.regs.rax)) < 0);

    // memchr must find a byte that is present, and report a miss honestly.
    state.regs = .{};
    state.regs.rcx = left;
    state.regs.rdx = 'p';
    state.regs.r8 = 5;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-string-l1-1-0.dll", "memchr", return_rip));
    try testing.expectEqual(left + 2, state.regs.rax);
    state.regs = .{};
    state.regs.rcx = left;
    state.regs.rdx = 'z';
    state.regs.r8 = 5;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-string-l1-1-0.dll", "memchr", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);

    // None of that went through the fallback, so the ledger stays empty --
    // an implemented import must never show up as degraded.
    try testing.expect(state.windows_import_fallbacks.isEmpty());

    // A stub whose zero would have been a real answer is retained with its
    // operands and is never collapsed into the "nothing to implement" line.
    const hazard = x64_linux_runtime.importFallbackFor("api-ms-win-crt-stdio-l1-1-0.dll", "__acrt_iob_func");
    try testing.expect(hazard.hazard);
    state.regs.rcx = 1;
    state.regs.rdx = 2;
    state.noteWindowsImportFallback("api-ms-win-crt-stdio-l1-1-0.dll", "__acrt_iob_func", hazard);
    const inert = x64_linux_runtime.importFallbackFor("api-ms-win-crt-runtime-l1-1-0.dll", "_crt_atexit");
    try testing.expect(!inert.hazard);
    state.noteWindowsImportFallback("api-ms-win-crt-runtime-l1-1-0.dll", "_crt_atexit", inert);

    const ledger = &state.windows_import_fallbacks;
    try testing.expectEqual(@as(usize, 2), ledger.count);
    try testing.expectEqual(@as(usize, 1), ledger.hazardCount());
    try testing.expectEqual(@as(u64, 1), ledger.entries[0].first_arg0);
    try testing.expectEqual(@as(u64, 2), ledger.entries[0].first_arg1);
    try testing.expect(x64_linux_runtime.ImportFallbackLedger.entryNeedsDetail(ledger.entries[0]));
    try testing.expect(!x64_linux_runtime.ImportFallbackLedger.entryNeedsDetail(ledger.entries[1]));
}

test "a file failure is attributed to the import that raised it" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x900;

    // A run that ends with a bare `file_failures=5004` says something went
    // wrong five thousand times without saying what. The count on its own
    // cannot separate a guest probing for optional files from a path Rosetta
    // could not serve, so a failure has to name the API that raised it.
    const path = MEM_BASE + 0xE00;
    for ("Z:\\nonexistent\\file.bin\x00", 0..) |ch, index| {
        state.write8(path + @as(u64, @intCast(index)), ch);
    }
    state.regs = .{};
    state.regs.rcx = path;
    _ = x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetFileAttributesA", return_rip);

    const ledger = &state.windows_file_failure_ledger;
    if (!ledger.isEmpty()) {
        try testing.expect(ledger.entries[0].name().len != 0);
        try testing.expect(!std.mem.eql(u8, ledger.entries[0].name(), "<unattributed>"));
        try testing.expect(ledger.total >= 1);
    }

    // Repeated identical failures collapse onto one entry rather than
    // filling the bounded table, and the same API with a different error
    // stays a separate fact.
    var direct = WindowsFileFailureLedger{};
    direct.note("CreateFileW", 2, "", 0);
    direct.note("CreateFileW", 2, "", 0);
    direct.note("CreateFileW", 3, "", 0);
    direct.note("FindFirstFileW", 2, "", 0);
    try testing.expectEqual(@as(usize, 3), direct.count);
    try testing.expectEqual(@as(u64, 4), direct.total);
    try testing.expectEqual(@as(u64, 2), direct.entries[0].count);
    try testing.expectEqual(@as(u32, 3), direct.entries[1].error_code);
    try testing.expectEqualStrings("ERROR_FILE_NOT_FOUND", windowsFileErrorLabel(2));
    try testing.expectEqualStrings("ERROR_ACCESS_DENIED", windowsFileErrorLabel(5));
    try testing.expectEqualStrings("unnamed", windowsFileErrorLabel(60001));
}

test "the window's monitor handle is stable and DXGI publishes a guest display object" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x600;

    // Win32 returns the same HMONITOR for the same display.  A fresh handle
    // per call makes a guest that caches "the monitor my window is on" see a
    // display change on every query.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "MonitorFromWindow", return_rip));
    const first = state.regs.rax;
    try testing.expect(first != 0);
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "MonitorFromWindow", return_rip));
    try testing.expectEqual(first, state.regs.rax);
    // MonitorFromPoint names the same single virtual display.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "MonitorFromPoint", return_rip));
    try testing.expectEqual(first, state.regs.rax);

    // The graphics import class covers whole DLLs, not just `vk` names.
    // Zero is VK_SUCCESS for a Vulkan entry and S_OK for the guest-only DXGI
    // factory model.
    state.regs = .{};
    const factory_output = MEM_BASE + 0xD90;
    state.regs.rdx = factory_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "dxgi.dll", "CreateDXGIFactory1", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax); // S_OK
    try testing.expect(state.read64(factory_output) != 0);
}

test "the progress watchdog only fires when every observable axis is frozen" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_progress.interval = 10;
    state.windows_progress.threshold = 3;

    // A run that is doing nothing at all: repeated samples are identical.
    var step: u64 = 0;
    while (step < 10 * 6) : (step += 10) {
        state.executed_steps = step;
        state.windows_progress.next_sample_step = step;
        state.checkWindowsProgress();
    }
    try testing.expect(state.windows_progress.reported);
    try testing.expectEqual(@as(u64, 1), state.windows_progress.episodes);

    // One import call is enough to prove the guest is still crossing a
    // boundary Rosetta owns, and the episode ends.
    state.windows_import_calls += 1;
    state.executed_steps += 10;
    state.windows_progress.next_sample_step = state.executed_steps;
    state.checkWindowsProgress();
    try testing.expect(!state.windows_progress.reported);
    try testing.expectEqual(@as(u32, 0), state.windows_progress.frozen_samples);

    // ...and so is a worker starting, which moves no counter of its own.
    state.windows_guest_threads[0] = .{ .status = .pending, .handle = 1, .start_routine = MEM_BASE };
    state.executed_steps += 10;
    state.windows_progress.next_sample_step = state.executed_steps;
    state.checkWindowsProgress();
    try testing.expectEqual(@as(u32, 0), state.windows_progress.frozen_samples);

    // A guest that paints but never presents is invisible to the freeze
    // detector -- its message loop keeps every axis moving -- so it has its
    // own claim, and that claim waits until there are enough paints to make
    // it.  A startup that has not presented yet must stay silent.
    state.windows_paint_deliveries = WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD - 1;
    state.checkWindowsPaintReachesScreen();
    try testing.expectEqual(@as(u64, 0), state.windows_progress.paint_without_present_reported_at);
    state.windows_paint_deliveries = WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD;
    state.checkWindowsPaintReachesScreen();
    try testing.expectEqual(
        WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD,
        state.windows_progress.paint_without_present_reported_at,
    );
    // It then escalates rather than repeating on every sample.
    state.windows_paint_deliveries += 1;
    state.checkWindowsPaintReachesScreen();
    try testing.expectEqual(
        WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD,
        state.windows_progress.paint_without_present_reported_at,
    );
    // One present is enough to retire the claim entirely.
    state.windows_graphics.presents = 1;
    state.windows_paint_deliveries *= 8;
    state.checkWindowsPaintReachesScreen();
    try testing.expectEqual(
        WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD,
        state.windows_progress.paint_without_present_reported_at,
    );

    // A disabled watchdog samples nothing at all.
    state.windows_progress.enabled = false;
    state.executed_steps += 10;
    state.windows_progress.next_sample_step = state.executed_steps;
    state.checkWindowsProgress();
    try testing.expectEqual(state.executed_steps, state.windows_progress.next_sample_step);
}

test "an invalidated window is painted through the message pump until it is validated" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    // A window with no WndProc cannot receive WM_PAINT, so the class has to
    // be registered first; otherwise the pump would spin on a paint nobody
    // can consume.
    const class_name = MEM_BASE + 0x900;
    const class_info = MEM_BASE + 0x940;
    const wnd_proc = MEM_BASE + 0x200;
    state.write8(class_name, 'X');
    state.write8(class_name + 1, 0);
    state.write64(class_info + 8, wnd_proc);
    state.write64(class_info + 64, class_name);
    try testing.expect(state.registerWindowsWindowClass(class_info, false) != 0);

    const hwnd: u64 = 0xFFFF_0000_0000_0010;
    try testing.expect(state.createWindowsWindow(hwnd, class_name, 0, false, 0, 0, false));

    // A freshly created window has an empty update region, so no paint is
    // owed and the pump must stay quiet.
    try testing.expectEqual(@as(usize, 0), state.windowsPendingPaintCount());
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) == null);

    try testing.expect(state.invalidateWindowsWindow(hwnd));
    try testing.expectEqual(@as(usize, 1), state.windowsPendingPaintCount());

    // WM_PAINT is generated, not dequeued: observing it must not consume it,
    // which is what lets a guest peek before it paints.
    const first = state.pendingWindowsPaintMessage(0, 0, 0).?;
    try testing.expectEqual(hwnd, first.hwnd);
    try testing.expectEqual(WINDOWS_WM_PAINT, first.message);
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) != null);

    // The guest's WndProc validates the region; only then does the paint stop.
    try testing.expect(state.validateWindowsWindow(hwnd));
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) == null);
    try testing.expectEqual(@as(u64, 1), state.windows_paint_requests);
    try testing.expect(state.windows_paint_deliveries >= 2);

    // A null HWND invalidates every drawable window, matching Win32.
    try testing.expect(state.invalidateWindowsWindow(0));
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) != null);

    // A pump filtered to a message range that excludes WM_PAINT, or to a
    // different window, must not observe the paint.
    try testing.expect(state.pendingWindowsPaintMessage(0, 0x0100, 0x0200) == null);
    try testing.expect(state.pendingWindowsPaintMessage(hwnd +| 1, 0, 0) == null);
}

test "the Win32 pump turns a guest paint request into a WM_PAINT the guest can dispatch" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const class_name = MEM_BASE + 0xA00;
    const class_info = MEM_BASE + 0xA40;
    const wnd_proc = MEM_BASE + 0x300;
    const message_buffer = MEM_BASE + 0xB00;
    const return_rip = MEM_BASE + 0x400;
    state.write8(class_name, 'W');
    state.write8(class_name + 1, 0);
    state.write64(class_info + 8, wnd_proc);
    state.write64(class_info + 64, class_name);
    try testing.expect(state.registerWindowsWindowClass(class_info, false) != 0);

    const hwnd: u64 = 0xFFFF_0000_0000_0040;
    try testing.expect(state.createWindowsWindow(hwnd, class_name, 0, false, 0, 0, false));

    // With no update region the pump has nothing to paint: GetMessage still
    // returns so the guest loop keeps running, but the message is WM_NULL.
    state.regs = .{};
    state.regs.rcx = message_buffer;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "GetMessageW", return_rip));
    try testing.expectEqual(@as(u32, 0), state.read32(message_buffer + 8));

    // The guest asks for a repaint the way an ordinary Win32 window does.
    state.regs = .{};
    state.regs.rcx = hwnd;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "InvalidateRect", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);

    state.regs = .{};
    state.regs.rcx = message_buffer;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "GetMessageW", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(hwnd, state.read64(message_buffer));
    try testing.expectEqual(WINDOWS_WM_PAINT, state.read32(message_buffer + 8));

    // Xenia's WndProc answers WM_PAINT with ValidateRect + its own painter.
    // After the region is validated the pump goes quiet again, which is what
    // keeps a healthy run from spinning on repaints nobody asked for.
    state.regs = .{};
    state.regs.rcx = hwnd;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "ValidateRect", return_rip));

    state.regs = .{};
    state.regs.rcx = message_buffer;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "GetMessageW", return_rip));
    try testing.expectEqual(@as(u32, 0), state.read32(message_buffer + 8));

    // BeginPaint is the other half of the Win32 contract and must also end
    // the pending paint, or a guest that uses it would repaint forever.
    state.regs = .{};
    state.regs.rcx = hwnd;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "InvalidateRect", return_rip));
    const paint_struct = MEM_BASE + 0xC00;
    state.regs = .{};
    state.regs.rcx = hwnd;
    state.regs.rdx = paint_struct;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "BeginPaint", return_rip));
    try testing.expect(state.regs.rax != 0);
    try testing.expectEqual(state.regs.rax, state.read64(paint_struct));
    try testing.expectEqual(@as(usize, 0), state.windowsPendingPaintCount());
}

test "a window with no WndProc never produces a paint the pump cannot deliver" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const hwnd: u64 = 0xFFFF_0000_0000_0020;
    try testing.expect(state.createWindowsWindow(hwnd, 0, 0, false, 0, 0, false));
    try testing.expect(state.invalidateWindowsWindow(hwnd));
    // The request is recorded -- that is the evidence a stall report needs --
    // but nothing is handed to a pump that has no WndProc to run.
    try testing.expectEqual(@as(usize, 1), state.windowsPendingPaintCount());
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) == null);

    // A message-only window is not drawable and must never be invalidated.
    const message_only: u64 = 0xFFFF_0000_0000_0030;
    try testing.expect(state.createWindowsWindow(message_only, 0, 0, true, 0, 0, false));
    try testing.expect(!state.invalidateWindowsWindow(message_only));

    // An unknown handle is a rejected request, not a silent success.
    try testing.expect(!state.invalidateWindowsWindow(0xDEAD));
    try testing.expect(!state.validateWindowsWindow(0xDEAD));
}

test "PE IAT targets are routed through the Windows import dispatcher" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const address = MEM_BASE + 0x700;
    const iat_address = MEM_BASE + 0x900;
    try testing.expect(state.registerWindowsImportStubAtIat(address, "kernel32.dll", "GetLastError", iat_address));
    const stub = state.windowsImportStubAt(address).?;
    try testing.expectEqualStrings("kernel32.dll", stub.dll_name);
    try testing.expectEqualStrings("GetLastError", stub.function_name);
    try testing.expectEqual(iat_address, stub.iat_address);
    try testing.expectEqual(@as(u8, 0xF4), state.read8(address));
    state.windows_direct_stub_count = 1;
    state.windows_iat_low = iat_address;
    state.windows_iat_high = iat_address + 8;
    try testing.expectEqual(address, state.windowsImportStubForIat(iat_address).?.address);

    // A second registration at the same IAT address is idempotent only when
    // it describes the original import; silently rebinding it would make a
    // stale PE thunk call a different Windows API.
    try testing.expect(state.registerWindowsImportStubAt(address, "kernel32.dll", "GetLastError"));
    try testing.expect(!state.registerWindowsImportStubAt(address, "kernel32.dll", "VirtualAlloc"));
}

test "precise time imports bypass the runtime mutex for verified direct static IAT stubs" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const stub_address = MEM_BASE + 0x700;
    const iat_address = MEM_BASE + 0x900;
    const stack = MEM_BASE + 0x1000;
    const output = MEM_BASE + 0x1100;
    const return_rip = MEM_BASE + 0x1200;
    try testing.expect(state.registerWindowsImportStubAtIat(
        stub_address,
        "kernel32.dll",
        "GetSystemTimePreciseAsFileTime",
        iat_address,
    ));
    state.windows_direct_stub_base = stub_address;
    state.windows_direct_stub_count = 1;
    state.write64(iat_address, stub_address);
    state.write64(stack, return_rip);
    state.guest_clock_published_ticks.publish(9_876_543);
    state.regs = .{ .rip = stub_address, .rsp = stack, .rcx = output, .rbx = 0xBADC_0FFE };
    state.xmm[7][3] = 0xA5;

    try testing.expect(state.tryWindowsFastImportStub(stub_address));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(stack + 8, state.regs.rsp);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u64, 0xBADC_0FFE), state.regs.rbx);
    try testing.expectEqual(@as(u8, 0xA5), state.xmm[7][3]);
    try testing.expectEqual(state.windowsGuestPublishedFileTime(), state.read64(output));
    try testing.expectEqual(@as(u64, 1), state.windows_fast_time_import_calls.load(.acquire));
    try testing.expectEqual(@as(u64, 0), state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic));

    // A caller already inside a runtime dispatch must not claim a lock
    // bypass. The ordinary import route retains responsibility there.
    state.regs = .{ .rip = stub_address, .rsp = stack, .rcx = output };
    var guard = state.lockWindowsRuntimeForDispatch();
    try testing.expect(!state.tryWindowsFastImportStub(stub_address));
    guard.unlock();
    try testing.expectEqual(@as(u64, 1), state.windows_fast_time_import_calls.load(.acquire));
}

test "QPC and QPF import stubs read the published guest clock on the lock-free path" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    state.guest_clock.source = .host_monotonic;

    const qpc_stub = MEM_BASE + 0x700;
    const qpf_stub = MEM_BASE + 0x710;
    const qpc_iat = MEM_BASE + 0x900;
    const qpf_iat = MEM_BASE + 0x908;
    const stack = MEM_BASE + 0x1000;
    const output = MEM_BASE + 0x1100;
    const return_rip = MEM_BASE + 0x1200;

    try testing.expect(state.registerWindowsImportStubAtIat(
        qpc_stub,
        "kernel32.dll",
        "QueryPerformanceCounter",
        qpc_iat,
    ));
    try testing.expect(state.registerWindowsImportStubAtIat(
        qpf_stub,
        "kernel32.dll",
        "QueryPerformanceFrequency",
        qpf_iat,
    ));
    state.windows_direct_stub_base = qpc_stub;
    state.windows_direct_stub_count = 2;
    state.write64(qpc_iat, qpc_stub);
    state.write64(qpf_iat, qpf_stub);
    state.guest_clock_published_ticks.publish(9_876_543);
    state.write64(stack, return_rip);

    state.regs = .{ .rip = qpc_stub, .rsp = stack, .rcx = output };
    try testing.expect(state.tryWindowsFastImportStub(qpc_stub));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(stack + 8, state.regs.rsp);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u64, 9_876_543), state.read64(output));
    try testing.expectEqual(@as(u64, 1), state.windows_fast_counter_import_calls[0].load(.acquire));
    try testing.expectEqual(@as(u64, 0), state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic));

    state.write64(stack, return_rip + 8);
    state.regs = .{ .rip = qpf_stub, .rsp = stack, .rcx = output };
    try testing.expect(state.tryWindowsFastImportStub(qpf_stub));
    try testing.expectEqual(return_rip + 8, state.regs.rip);
    try testing.expectEqual(@as(u64, WINDOWS_GUEST_CLOCK_HZ), state.read64(output));
    try testing.expectEqual(@as(u64, 1), state.windows_fast_counter_import_calls[1].load(.acquire));
    try testing.expectEqual(@as(u64, 0), state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic));

    // A counter call already inside a runtime dispatch stays on the ordinary
    // route; the fast lane must not claim a mutex it does not own.
    state.write64(stack, return_rip + 16);
    state.regs = .{ .rip = qpc_stub, .rsp = stack, .rcx = output };
    var guard = state.lockWindowsRuntimeForDispatch();
    try testing.expect(!state.tryWindowsFastImportStub(qpc_stub));
    guard.unlock();
    try testing.expectEqual(@as(u64, 1), state.windows_fast_counter_import_calls[0].load(.acquire));
}

test "C runtime memcpy and memset bypass the runtime mutex through verified IAT stubs" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const copy_stub = MEM_BASE + 0x700;
    const fill_stub = MEM_BASE + 0x710; // direct stubs sit on a 16-byte stride
    const copy_iat = MEM_BASE + 0x900;
    const fill_iat = MEM_BASE + 0x908;
    const stack = MEM_BASE + 0x1000;
    const source = MEM_BASE + 0x1100;
    const destination = MEM_BASE + 0x1200;
    const return_rip = MEM_BASE + 0x1300;
    try testing.expect(state.registerWindowsImportStubAtIat(copy_stub, "api-ms-win-crt-private-l1-1-0.dll", "memcpy", copy_iat));
    try testing.expect(state.registerWindowsImportStubAtIat(fill_stub, "api-ms-win-crt-string-l1-1-0.dll", "memset", fill_iat));
    state.windows_direct_stub_base = copy_stub;
    state.windows_direct_stub_count = 2;
    state.write64(copy_iat, copy_stub);
    state.write64(fill_iat, fill_stub);
    state.write64(stack, return_rip);
    try testing.expect(state.copyToGuest(source, "Rosette!"));

    state.regs = .{ .rip = copy_stub, .rsp = stack, .rcx = destination, .rdx = source, .r8 = 8, .rbx = 0xBADC_0FFE };
    try testing.expect(state.tryWindowsFastImportStub(copy_stub));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(stack + 8, state.regs.rsp);
    try testing.expectEqual(destination, state.regs.rax);
    try testing.expectEqual(@as(u64, 0xBADC_0FFE), state.regs.rbx);
    var copied: [8]u8 = undefined;
    try testing.expect(state.copyFromGuest(&copied, destination));
    try testing.expectEqualStrings("Rosette!", &copied);

    state.write64(stack, return_rip);
    state.regs = .{ .rip = fill_stub, .rsp = stack, .rcx = destination, .rdx = 0x2A, .r8 = 4 };
    try testing.expect(state.tryWindowsFastImportStub(fill_stub));
    try testing.expectEqual(destination, state.regs.rax);
    try testing.expectEqual(@as(u32, 0x2A2A_2A2A), state.read32(destination));
    try testing.expectEqual(@as(u64, 2), state.windowsFastCrtImportCalls());
    try testing.expectEqual(@as(u64, 0), state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic));

    // An unmapped destination returns to the ordinary handler untouched: it
    // is the one that reports the unreadable pointer.
    state.write64(stack, return_rip);
    state.regs = .{ .rip = copy_stub, .rsp = stack, .rcx = 0x7777_0000_0000, .rdx = source, .r8 = 8 };
    try testing.expect(!state.tryWindowsFastImportStub(copy_stub));
    try testing.expectEqual(copy_stub, state.regs.rip);
    try testing.expectEqual(stack, state.regs.rsp);
    try testing.expectEqual(@as(u64, 2), state.windowsFastCrtImportCalls());

    // So does a caller already inside a runtime dispatch.
    state.regs = .{ .rip = copy_stub, .rsp = stack, .rcx = destination, .rdx = source, .r8 = 8 };
    var guard = state.lockWindowsRuntimeForDispatch();
    try testing.expect(!state.tryWindowsFastImportStub(copy_stub));
    guard.unlock();
    try testing.expectEqual(@as(u64, 2), state.windowsFastCrtImportCalls());
}

test "a memset reached through its IAT slot is answered on the lock-free lane, called or tail-jumped" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const fill_stub = MEM_BASE + 0x700;
    const other_stub = MEM_BASE + 0x710;
    const fill_iat = MEM_BASE + 0x900;
    const other_iat = MEM_BASE + 0x908;
    const stack = MEM_BASE + 0x1000;
    const destination = MEM_BASE + 0x1200;
    const caller_return = MEM_BASE + 0x1300;
    try testing.expect(state.registerWindowsImportStubAtIat(fill_stub, "msvcrt.dll", "memset", fill_iat));
    try testing.expect(state.registerWindowsImportStubAtIat(other_stub, "KERNEL32.dll", "CloseHandle", other_iat));
    state.windows_direct_stub_base = fill_stub;
    state.windows_direct_stub_count = 2;
    state.windows_iat_low = fill_iat;
    state.windows_iat_high = other_iat + 8;
    state.write64(fill_iat, fill_stub);
    state.write64(other_iat, other_stub);
    state.indexWindowsIatStubs();

    // `call [memset@IAT]`: the call has pushed nothing, and returns to its
    // next instruction.
    state.regs = .{ .rip = MEM_BASE + 0x1400, .rsp = stack, .rcx = destination, .rdx = 0x5A, .r8 = 4 };
    try testing.expect(state.tryImportSlotFastTransfer(fill_iat, MEM_BASE + 0x1406));
    try testing.expectEqual(MEM_BASE + 0x1406, state.regs.rip);
    try testing.expectEqual(stack, state.regs.rsp);
    try testing.expectEqual(destination, state.regs.rax);
    try testing.expectEqual(@as(u32, 0x5A5A_5A5A), state.read32(destination));

    // The memset thunk's `jmp [memset@IAT]`: its caller's return address is
    // on the stack and is popped.
    state.write64(stack, caller_return);
    state.regs = .{ .rip = MEM_BASE + 0x1500, .rsp = stack, .rcx = destination, .rdx = 0x11, .r8 = 4 };
    try testing.expect(state.tryImportSlotFastTransfer(fill_iat, 0));
    try testing.expectEqual(caller_return, state.regs.rip);
    try testing.expectEqual(stack + 8, state.regs.rsp);
    try testing.expectEqual(@as(u32, 0x1111_1111), state.read32(destination));
    try testing.expectEqual(@as(u64, 2), state.windows_import_slot_fast_transfers.load(.monotonic));
    try testing.expectEqual(@as(u64, 0), state.windows_runtime_mutex.inner.stats.acquisitions.load(.monotonic));

    // An import no lane serves, a slot outside the table and a slot whose
    // binding moved all decline with every register untouched.
    state.regs = .{ .rip = MEM_BASE + 0x1500, .rsp = stack, .rcx = 1 };
    try testing.expect(!state.tryImportSlotFastTransfer(other_iat, 0));
    try testing.expect(!state.tryImportSlotFastTransfer(other_iat + 8, 0));
    state.write64(fill_iat, other_stub);
    try testing.expect(!state.tryImportSlotFastTransfer(fill_iat, 0));
    try testing.expectEqual(MEM_BASE + 0x1500, state.regs.rip);
    try testing.expectEqual(stack, state.regs.rsp);
    try testing.expectEqual(@as(u64, 2), state.windows_import_slot_fast_transfers.load(.monotonic));
}

test "precise time fast path accepts exact dynamic proc stubs but rejects other dynamic imports" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const direct_stub = MEM_BASE + 0x700;
    const direct_iat = MEM_BASE + 0x900;
    const dynamic_time_stub = MEM_BASE + 0x720;
    const dynamic_other_stub = MEM_BASE + 0x740;
    const stack = MEM_BASE + 0x1000;
    const output = MEM_BASE + 0x1100;
    const return_rip = MEM_BASE + 0x1200;

    try testing.expect(state.registerWindowsImportStubAtIat(
        direct_stub,
        "kernel32.dll",
        "GetLastError",
        direct_iat,
    ));
    state.windows_direct_stub_base = direct_stub;
    state.windows_direct_stub_count = 1;
    state.write64(direct_iat, direct_stub);
    state.windows_dynamic_stub_start = state.windows_stub_count;
    try testing.expect(state.registerWindowsImportStubAt(
        dynamic_time_stub,
        "kernel32.dll",
        "GetSystemTimePreciseAsFileTime",
    ));
    try testing.expect(state.registerWindowsImportStubAt(
        dynamic_other_stub,
        "kernel32.dll",
        "GetSystemTimeAsFileTime",
    ));
    try testing.expect(state.windowsImportStubAt(dynamic_time_stub).?.is_dynamic);
    try testing.expect(state.windowsImportStubAt(dynamic_other_stub).?.is_dynamic);

    state.write64(stack, return_rip);
    state.guest_clock_published_ticks.publish(123_456);
    state.regs = .{ .rip = dynamic_time_stub, .rsp = stack, .rcx = output };
    try testing.expect(state.tryWindowsFastImportStub(dynamic_time_stub));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(stack + 8, state.regs.rsp);
    try testing.expectEqual(state.windowsGuestPublishedFileTime(), state.read64(output));
    try testing.expectEqual(@as(u64, 1), state.windows_fast_time_import_calls.load(.acquire));

    state.write64(stack, return_rip + 8);
    state.regs = .{ .rip = dynamic_other_stub, .rsp = stack, .rcx = output };
    try testing.expect(!state.tryWindowsFastImportStub(dynamic_other_stub));
    try testing.expectEqual(@as(u64, 1), state.windows_fast_time_import_calls.load(.acquire));
}

test "unverified non-IAT static precise-time stub retains the locked dispatcher" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const stub_address = MEM_BASE + 0x700;
    const stack = MEM_BASE + 0x1000;
    try testing.expect(state.registerWindowsImportStubAt(
        stub_address,
        "kernel32.dll",
        "GetSystemTimePreciseAsFileTime",
    ));
    state.windows_direct_stub_base = stub_address;
    state.windows_direct_stub_count = 1;
    state.windows_dynamic_stub_start = 1;
    state.write64(stack, MEM_BASE + 0x1200);
    state.regs = .{ .rip = stub_address, .rsp = stack, .rcx = MEM_BASE + 0x1100 };

    try testing.expect(!state.windowsImportStubAt(stub_address).?.is_dynamic);
    try testing.expect(!state.tryWindowsFastImportStub(stub_address));
    try testing.expectEqual(@as(u64, 0), state.windows_fast_time_import_calls.load(.acquire));
}

test "a spent mapped-write trace stops withholding the lock-free time import" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    state.trace_windows_memory = true;

    const stub = MEM_BASE + 0x720;
    const stack = MEM_BASE + 0x1000;
    const output = MEM_BASE + 0x1100;
    const return_rip = MEM_BASE + 0x1200;
    state.windows_dynamic_stub_start = state.windows_stub_count;
    try testing.expect(state.registerWindowsImportStubAt(stub, "kernel32.dll", "GetSystemTimePreciseAsFileTime"));

    // Budget left: the trace may still record this call's store, so the
    // call keeps the locked path.
    state.write64(stack, return_rip);
    state.regs = .{ .rip = stub, .rsp = stack, .rcx = output };
    try testing.expect(state.windowsMemoryTraceLive());
    try testing.expect(!state.tryWindowsFastImportStub(stub));

    // Spent: the launcher's default trace no longer puts every time query
    // on the runtime lock.
    state.windows_memory_trace_events.store(ElfState.windows_memory_trace_budget, .monotonic);
    try testing.expect(!state.windowsMemoryTraceLive());
    try testing.expect(state.tryWindowsFastImportStub(stub));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(@as(u64, 1), state.windows_fast_time_import_calls.load(.acquire));
}

test "a normal Windows import return repairs a clobbered nonvolatile register" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const stub_address = MEM_BASE + 0x700;
    try testing.expect(state.registerWindowsImportStubAt(stub_address, "user32.dll", "GetMessageW"));
    const stub = state.windowsImportStubAt(stub_address).?;
    const return_rip = MEM_BASE + 0x900;
    const entry_rsp = MEM_BASE + 0x1000;
    state.regs.rsp = entry_rsp;
    state.regs.r14 = stub_address;
    state.xmm[7][3] = 0xA7;
    const entry_regs = &state.regs;
    const saved = windows_guest_abi.Snapshot.capture(entry_regs, &state.xmm);

    state.regs.rax = 1; // Keep the API result.
    state.regs.r14 = 0x12004fa18;
    state.xmm[7][3] = 0x5C;
    state.regs.rip = return_rip;
    state.regs.rsp = entry_rsp + 8;
    state.recordWindowsImportAbiReturn(stub, &saved, entry_regs, entry_rsp, return_rip, 8, null, return_rip - 3);

    try testing.expectEqual(stub_address, state.regs.r14);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u8, 0xA7), state.xmm[7][3]);
    try testing.expectEqual(@as(u64, 1), state.windows_import_abi_clobber_calls);
    try testing.expectEqual(@as(u64, 1), state.windows_import_abi_repairs);
}

test "DispatchMessage callback return preserves the caller ABI and its result" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.mem_base = MEM_BASE;
    state.mem_size = state.mem.len;

    const message_address = MEM_BASE + 0x800;
    const hwnd: u64 = 0xFFFF_F000_0000_0020;
    state.write64(message_address, hwnd);
    state.write32(message_address + 8, 0x0400);
    state.write64(message_address + 16, 0x1234);
    state.write64(message_address + 24, 0x5678);

    const return_rip = MEM_BASE + 0x1800;
    const entry_rsp = MEM_BASE + 0x3000;
    state.regs.rcx = message_address;
    state.regs.rsp = entry_rsp;
    state.regs.rbx = 0xB001;
    state.regs.rbp = 0xB002;
    state.regs.rsi = 0xB003;
    state.regs.rdi = 0xB004;
    state.regs.r12 = 0xB012;
    state.regs.r13 = 0xB013;
    state.regs.r14 = 0xB014;
    state.regs.r15 = 0xB015;
    state.xmm[7][3] = 0xA7;
    try testing.expect(state.beginWindowsMessageDispatchWithKind(return_rip, false, true));

    // A WndProc's result is volatile, but the enclosing DispatchMessageW
    // call must return with the original nonvolatile register file intact.
    state.regs.rax = 0x55AA;
    state.regs.rbx = 1;
    state.regs.rbp = 2;
    state.regs.rsi = 3;
    state.regs.rdi = 4;
    state.regs.r12 = 12;
    state.regs.r13 = 13;
    state.regs.r14 = 14;
    state.regs.r15 = 15;
    state.xmm[7][3] = 0x5C;
    state.regs.rsp = entry_rsp - 32; // WndProc's RET consumed its synthetic slot.
    state.regs.rip = SYNTHETIC_WINDOWS_MESSAGE_RETURN;
    try testing.expect(state.finishWindowsMessageDispatch());

    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(entry_rsp + 8, state.regs.rsp);
    try testing.expectEqual(@as(u64, 0x55AA), state.regs.rax);
    try testing.expectEqual(@as(u64, 0xB001), state.regs.rbx);
    try testing.expectEqual(@as(u64, 0xB002), state.regs.rbp);
    try testing.expectEqual(@as(u64, 0xB003), state.regs.rsi);
    try testing.expectEqual(@as(u64, 0xB004), state.regs.rdi);
    try testing.expectEqual(@as(u64, 0xB012), state.regs.r12);
    try testing.expectEqual(@as(u64, 0xB013), state.regs.r13);
    try testing.expectEqual(@as(u64, 0xB014), state.regs.r14);
    try testing.expectEqual(@as(u64, 0xB015), state.regs.r15);
    try testing.expectEqual(@as(u8, 0xA7), state.xmm[7][3]);
    try testing.expectEqual(@as(u64, 1), state.windows_callback_abi_calls);
    try testing.expectEqual(@as(u64, 1), state.windows_callback_abi_clobber_calls);
    try testing.expectEqual(@as(u64, 1), state.windows_callback_abi_repairs);
}

test "Windows import caller attribution follows the return address through translated call sites" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.mem_base = MEM_BASE;
    state.mem_size = state.mem.len;

    const stub_address = MEM_BASE + 0x700;
    const callsite = MEM_BASE + 0x900;
    try testing.expect(state.registerWindowsImportStubAt(stub_address, "user32.dll", "GetMessageW"));
    state.write8(callsite, 0x41); // REX.B
    state.write8(callsite + 1, 0xFF); // indirect group-5 transfer
    state.write8(callsite + 2, 0xD6); // CALL R14
    state.regs.r14 = stub_address;

    const site = state.windowsImportCallsite(callsite + 3, stub_address).?;
    try testing.expectEqual(callsite, site.rip);
    try testing.expectEqual(Op.call_reg64, site.decoded.op);
    try testing.expectEqual(RegId.r14b_r14w_r14d_r14, site.decoded.dst_reg);
}

test "invalid indirect native handle reports the source register and overwritten IAT" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.mem_base = MEM_BASE;
    state.mem_size = state.mem.len;
    state.image_low = MEM_BASE;
    state.image_high = MEM_BASE + state.mem.len;

    const target: u64 = 0x12004fa18;
    const callsite = MEM_BASE + 0x1800;
    const expected_stub = MEM_BASE + 0x3000;
    const iat_address = MEM_BASE + 0x4000;
    state.write8(callsite, 0x41);
    state.write8(callsite + 1, 0xFF);
    state.write8(callsite + 2, 0xD6);
    try testing.expect(state.registerWindowsImportStubAtIat(expected_stub, "user32.dll", "GetMessageW", iat_address));
    state.windows_direct_stub_count = 1;
    state.regs.rip = target;
    state.regs.rsp = MEM_BASE + 0x2000;
    state.regs.r14 = target;
    state.last_instruction_rip = callsite;
    state.last_decoded_op = .call_reg64;
    state.last_decoded_len = 3;
    state.write64(iat_address, target);

    try testing.expect(state.reportInvalidWindowsControlTarget(target));
    try testing.expect(state.decode_failure_is_invalid_control_target);
    try testing.expectEqual(@as(u64, 1), state.windows_iat_mismatches_at_fault);
}

test "QueueUserAPC runs inside the next alertable wait and the wait answers WAIT_IO_COMPLETION" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const routine = MEM_BASE + 0x1C00;
    const continuation = MEM_BASE + 0x780;
    const pseudo_current_thread = std.math.maxInt(u64) - 1;
    state.regs.rsp = MEM_BASE + 0x8008;
    state.regs.rcx = routine;
    state.regs.rdx = pseudo_current_thread;
    state.regs.r8 = 0x1234;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "QueueUserAPC", continuation));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.windows_apcs_queued);

    // A non-alertable sleep leaves the APC queued.
    state.regs.rcx = 0;
    state.regs.rdx = 0;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "SleepEx", continuation));
    try testing.expectEqual(@as(u64, 0), state.windows_apcs_delivered);

    // SleepEx(0, TRUE): the routine runs on this thread's stack, entered at
    // 8 mod 16 with room for its home area, and returns into Rosette.
    const wait_rsp = state.regs.rsp;
    state.regs.rcx = 0;
    state.regs.rdx = 1;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "SleepEx", continuation));
    try testing.expectEqual(routine, state.regs.rip);
    try testing.expectEqual(@as(u64, 0x1234), state.regs.rcx);
    try testing.expectEqual(@as(u64, 8), state.regs.rsp % 16);
    try testing.expect(state.regs.rsp + 0x28 <= wait_rsp);
    try testing.expectEqual(SYNTHETIC_WINDOWS_APC_RETURN, state.read64(state.regs.rsp));
    // The routine returns.
    state.regs.rip = state.pop();
    try testing.expect(state.handleSyntheticRip());
    try testing.expectEqual(continuation, state.regs.rip);
    try testing.expectEqual(wait_rsp, state.regs.rsp);
    try testing.expectEqual(WINDOWS_WAIT_IO_COMPLETION, state.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.windows_apcs_delivered);
    // A thread handle nobody owns is refused.
    state.regs.rcx = routine;
    state.regs.rdx = 0xFFFF_F000_0000_9999;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "QueueUserAPC", continuation));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
}

test "an APC queued to a thread blocked in an alertable wait makes it runnable to run it" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_guest_threads[2] = .{ .status = .blocked, .handle = 0xFFFF_F000_0000_0A01, .thread_id = 7, .blocked_wait_handle = 0xFFFF_F000_0000_0A02, .blocked_wait_timeout = 0xFFFF_FFFF, .blocked_alertable = true };
    state.windows_guest_threads[3] = .{ .status = .blocked, .handle = 0xFFFF_F000_0000_0A03, .thread_id = 8, .blocked_wait_handle = 0xFFFF_F000_0000_0A02, .blocked_wait_timeout = 0xFFFF_FFFF };
    try testing.expect(state.queueWindowsApc(0xFFFF_F000_0000_0A01, MEM_BASE + 0x1C00, 5));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[2].status);
    try testing.expectEqual(@as(u64, 0), state.windows_guest_threads[2].blocked_wait_handle);
    try testing.expectEqual(@as(u8, 1), state.windows_guest_threads[2].apc.count);
    // A non-alertable waiter keeps waiting; its APC waits with it.
    try testing.expect(state.queueWindowsApc(0xFFFF_F000_0000_0A03, MEM_BASE + 0x1C00, 6));
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[3].status);
    try testing.expectEqual(@as(u64, 1), state.windows_apc_wakes);
}

test "Windows CRT realloc preserves guest bytes and zeroes grown recalloc tails" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x780;
    const original = state.guestAlloc(32, 16).?;
    for (0..32) |index| state.write8(original + @as(u64, @intCast(index)), @intCast(index + 1));

    state.regs.rcx = original;
    state.regs.rdx = 64;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-heap-l1-1-0.dll", "realloc", return_rip));
    const grown = state.regs.rax;
    try testing.expect(grown != 0);
    try testing.expect(grown != original);
    for (0..32) |index| try testing.expectEqual(@as(u8, @intCast(index + 1)), state.read8(grown + @as(u64, @intCast(index))));
    for (32..64) |index| try testing.expectEqual(@as(u8, 0), state.read8(grown + @as(u64, @intCast(index))));

    state.regs.rcx = grown;
    state.regs.rdx = 32;
    state.regs.r8 = 4;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-heap-l1-1-0.dll", "_recalloc", return_rip));
    const recalloced = state.regs.rax;
    try testing.expect(recalloced != 0);
    try testing.expect(recalloced != grown);
    for (0..32) |index| try testing.expectEqual(@as(u8, @intCast(index + 1)), state.read8(recalloced + @as(u64, @intCast(index))));
    for (32..128) |index| try testing.expectEqual(@as(u8, 0), state.read8(recalloced + @as(u64, @intCast(index))));

    state.regs.rcx = recalloced;
    state.regs.rdx = 8;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-heap-l1-1-0.dll", "realloc", return_rip));
    try testing.expectEqual(recalloced, state.regs.rax);
    try testing.expectEqual(@as(u8, 1), state.read8(recalloced));

    state.regs.rcx = recalloced;
    state.regs.rdx = 0;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-heap-l1-1-0.dll", "realloc", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expect(!state.releaseGuestAllocation(recalloced));
}

test "PE heap provenance grows beyond the initial table capacity" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    var last: u64 = 0;
    for (0..INITIAL_WINDOWS_HEAP_ALLOCATIONS + 1) |_| {
        last = state.guestAlloc(1, 1).?;
    }

    try testing.expectEqual(
        INITIAL_WINDOWS_HEAP_ALLOCATIONS + 1,
        state.windows_heap_allocation_count,
    );
    try testing.expect(state.windows_heap_allocations.len > INITIAL_WINDOWS_HEAP_ALLOCATIONS);
    try testing.expectEqual(@as(u64, 0), state.windows_heap_provenance_growth_failures);
    try testing.expectEqual(@as(u64, 0), state.windows_heap_provenance_untracked_allocations);
    try testing.expect(state.releaseGuestAllocation(last));
}

test "PE heap reuses an exact released block without growing provenance" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_heap_quarantine_limit_blocks = 0;

    const first = state.guestAlloc(24, 16).?;
    for (0..24) |index| state.write8(first + @as(u64, @intCast(index)), 0xA5);
    const records = state.windows_heap_allocation_count;
    try testing.expect(state.releaseGuestAllocation(first));
    try testing.expectEqual(@as(usize, 1), state.windows_heap_free_count);

    const reused = state.guestAlloc(24, 16).?;
    try testing.expectEqual(first, reused);
    try testing.expectEqual(records, state.windows_heap_allocation_count);
    try testing.expectEqual(@as(usize, 0), state.windows_heap_free_count);
    try testing.expectEqual(@as(usize, 1), state.windows_heap_allocations_live);
    try testing.expectEqual(@as(u64, 1), state.windows_heap_reused_allocations);
    for (0..24) |index| try testing.expectEqual(@as(u8, 0), state.read8(reused + @as(u64, @intCast(index))));
}

test "malloc-semantic guest allocations skip fresh and reuse clearing while zeroed allocations keep it" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_heap_quarantine_limit_blocks = 0;

    const first = state.guestAlloc(24, 16).?;
    for (0..24) |index| state.write8(first + @as(u64, @intCast(index)), 0xA5);
    try testing.expect(state.releaseGuestAllocation(first));

    const malloc_block = state.guestAllocUninitialized(24, 16).?;
    try testing.expectEqual(first, malloc_block);
    for (0..24) |index| try testing.expectEqual(@as(u8, 0xA5), state.read8(malloc_block + @as(u64, @intCast(index))));
    try testing.expectEqual(@as(u64, 24), state.windows_heap_zero_fill_avoided_bytes);

    try testing.expect(state.releaseGuestAllocation(malloc_block));
    const calloc_block = state.guestAlloc(24, 16).?;
    try testing.expectEqual(first, calloc_block);
    for (0..24) |index| try testing.expectEqual(@as(u8, 0), state.read8(calloc_block + @as(u64, @intCast(index))));
    try testing.expectEqual(@as(u64, 48), state.windows_heap_zero_fill_bytes);
    try testing.expectEqual(@as(u64, 24), state.windows_heap_zero_fill_avoided_bytes);
}

test "PE heap quarantines a freed block, refuses its second free and reuses it oldest first" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_heap_quarantine_limit_blocks = 2;

    const a = state.guestAlloc(48, 16).?;
    const b = state.guestAlloc(48, 16).?;
    const c = state.guestAlloc(48, 16).?;
    state.write8(a, 0x5A);
    try testing.expect(state.releaseGuestAllocation(a));
    // A late read of the freed block still finds its old contents.
    try testing.expectEqual(@as(u8, 0x5A), state.read8(a));
    // A second free is refused rather than releasing a later owner's block.
    try testing.expect(!state.releaseGuestAllocation(a));
    try testing.expectEqual(@as(u64, 1), state.windows_heap_double_frees);
    // Quarantined, so a same-size request is a fresh block.
    const d = state.guestAlloc(48, 16).?;
    try testing.expect(d != a);
    try testing.expect(state.releaseGuestAllocation(b));
    try testing.expect(state.releaseGuestAllocation(c));
    // Two quarantine slots: releasing a third pushes the oldest (a) out.
    try testing.expectEqual(@as(usize, 1), state.windows_heap_binned);
    try testing.expectEqual(a, state.guestAlloc(48, 16).?);
    try testing.expectEqual(@as(u8, 0), state.read8(a));
    try testing.expect(!state.releaseGuestAllocation(0x1234));
    try testing.expectEqual(@as(u64, 1), state.windows_heap_unknown_frees);
    try testing.expect(state.releaseGuestAllocation(d));
}

test "PE heap retains allocation and first-free callsites for double-free diagnostics" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    state.guestContextField("windows_current_import").* = "malloc";
    state.guestContextField("regs").*.rip = 0x140001000;
    const allocation = state.guestAlloc(32, 16).?;
    try testing.expectEqual(@as(u64, 0x140001000), state.windows_heap_allocations[0].allocation_rip);
    try testing.expectEqualStrings("malloc", state.windows_heap_allocations[0].allocation_import);

    state.guestContextField("windows_current_import").* = "free";
    state.guestContextField("regs").*.rip = 0x140002000;
    try testing.expect(state.releaseGuestAllocation(allocation));
    try testing.expectEqual(@as(u64, 0x140002000), state.windows_heap_allocations[0].free_rip);
    try testing.expectEqualStrings("free", state.windows_heap_allocations[0].free_import);

    state.guestContextField("windows_current_import").* = "_free_base";
    state.guestContextField("regs").*.rip = 0x140003000;
    try testing.expect(!state.releaseGuestAllocation(allocation));
    try testing.expectEqual(@as(u64, 0x140002000), state.windows_heap_allocations[0].free_rip);
    try testing.expectEqualStrings("free", state.windows_heap_allocations[0].free_import);
}

test "PE heap reuse takes a fitting block from the size bin without scanning others" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_heap_quarantine_limit_blocks = 0;
    var blocks: [64]u64 = undefined;
    for (&blocks, 0..) |*block, index| block.* = state.guestAlloc(16 + @as(u64, @intCast(index)) * 16, 16).?;
    for (blocks) |block| try testing.expect(state.releaseGuestAllocation(block));
    try testing.expectEqual(@as(usize, 64), state.windows_heap_free_count);
    // Each size has its own bin: the 40th size comes straight back.
    try testing.expectEqual(blocks[40], state.guestAlloc(16 + 40 * 16, 16).?);
    try testing.expectEqual(@as(usize, 63), state.windows_heap_free_count);
    // A 4 KiB-aligned request does not take a 16-byte-aligned block.
    const page_aligned = state.guestAlloc(16 + 3 * 16, 0x1000).?;
    try testing.expect(page_aligned & 0xFFF == 0);
}

test "a worker that runs past its stack stops as a stack overflow instead of writing the heap below" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_process_peb = MEM_BASE;

    // lea rax, [rsp - 0x100000] ; mov [rax], rax ; ret
    const entry = MEM_BASE + 0x1A00;
    const code = [_]u8{ 0x48, 0x8D, 0x84, 0x24, 0x00, 0x00, 0xF0, 0xFF, 0x48, 0x89, 0x00, 0xC3 };
    for (code, 0..) |byte, index| state.write8(entry + index, byte);
    try testing.expect(state.enqueueWindowsGuestThread(0xFFFF_F000_0000_0902, entry, 0, 0, false));
    _ = state.serviceWindowsGuestThreads(16);

    const thread = state.windows_guest_threads[0];
    try testing.expect(thread.stack_guard_base != 0);
    try testing.expectEqual(thread.stack_guard_base + WINDOWS_GUEST_THREAD_STACK_GUARD, thread.stack_base);
    try testing.expect(state.terminated);
    try testing.expect(state.faulted);
    try testing.expectEqual(@as(u64, 1), state.windows_stack_overflows);
    // The write never reached the guard's bytes.
    for (0..WINDOWS_GUEST_THREAD_STACK_GUARD / 8) |slot| {
        try testing.expectEqual(@as(u64, 0), state.read64(thread.stack_guard_base + slot * 8));
    }
}

test "a finished worker's stack goes back to the heap with its guard unprotected" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_process_peb = MEM_BASE;

    const entry = MEM_BASE + 0x1A00;
    state.write8(entry, 0x58); // pop rax
    state.write8(entry + 1, 0xC3); // ret
    try testing.expect(state.enqueueWindowsGuestThread(0xFFFF_F000_0000_0903, entry, 0, 0, false));
    _ = state.serviceWindowsGuestThreads(16);
    try testing.expectEqual(WindowsGuestThreadStatus.completed, state.windows_guest_threads[0].status);
    try testing.expectEqual(@as(u64, 0), state.windows_guest_threads[0].stack_base);
    try testing.expectEqual(@as(u64, 1), state.windows_thread_stacks_released);
    try testing.expectEqual(@as(u64, 0), state.windows_heap_unknown_frees);
}

test "a Windows worker return to a null slot completes locally" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_process_peb = MEM_BASE;

    const entry = MEM_BASE + 0x1A00;
    state.write8(entry, 0x58); // pop rax: consume the synthetic return marker
    state.write8(entry + 1, 0xC3); // ret: the fresh stack slot contains zero
    const worker_handle = 0xFFFF_F000_0000_0901;
    try testing.expect(state.enqueueWindowsGuestThread(worker_handle, entry, 0, 0, false));

    _ = state.serviceWindowsGuestThreads(16);

    try testing.expectEqual(WindowsGuestThreadStatus.completed, state.windows_guest_threads[0].status);
    try testing.expect(!state.terminated);
    try testing.expect(!state.faulted);
    try testing.expectEqual(@as(u64, 1), state.windows_thread_completions);
    try testing.expectEqual(@as(?usize, null), state.windows_active_guest_thread_slot);
}

test "Windows CRT memmove preserves overlapping guest bytes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x880;
    const buffer = state.guestAlloc(16, 1).?;
    for ("abcdef", 0..) |character, index| state.write8(buffer + @as(u64, @intCast(index)), character);
    state.regs.rcx = buffer + 1;
    state.regs.rdx = buffer;
    state.regs.r8 = 5;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memmove", return_rip));
    try testing.expectEqualStrings("aabcde", state.mem[@intCast(state.addrToOffset(buffer).?)..][0..6]);

    for ("abcdef", 0..) |character, index| state.write8(buffer + @as(u64, @intCast(index)), character);
    state.regs.rcx = buffer;
    state.regs.rdx = buffer + 1;
    state.regs.r8 = 5;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memmove", return_rip));
    try testing.expectEqualStrings("bcdef", state.mem[@intCast(state.addrToOffset(buffer).?)..][0..5]);
}

test "Windows bootstrap materializes command line and UTF-16 conversion" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x900;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetCommandLineW", return_rip));
    const command_line = state.regs.rax;
    try testing.expect(command_line != 0);
    try testing.expectEqual(@as(u16, 'x'), state.read16(command_line));
    try testing.expectEqual(@as(u16, 0), state.read16(command_line + 16 * 2));
    try testing.expectEqual(return_rip, state.regs.rip);

    const wide_source = state.guestAlloc(14, 2).?;
    for ([_]u16{ 'H', 'a', 'l', 'o', ' ', '3', 0 }, 0..) |unit, index| {
        state.write16(wide_source + @as(u64, @intCast(index * 2)), unit);
    }
    const narrow_destination = state.guestAlloc(16, 1).?;
    state.regs.rcx = 65001; // CP_UTF8
    state.regs.rdx = 0;
    state.regs.r8 = wide_source;
    state.regs.r9 = std.math.maxInt(u32); // -1: include the terminator
    state.regs.rsp = MEM_BASE + 0x1000;
    state.write64(state.regs.rsp + 32, narrow_destination);
    state.write64(state.regs.rsp + 40, 16);
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "WideCharToMultiByte", return_rip));
    try testing.expectEqual(@as(u64, 7), state.regs.rax);
    const narrow_offset: usize = @intCast(state.addrToOffset(narrow_destination).?);
    try testing.expectEqualStrings("Halo 3", state.mem[narrow_offset..][0..6]);
    try testing.expectEqual(@as(u8, 0), state.read8(narrow_destination + 6));
}

test "Windows CRT owns callback tables and drains normal exit callbacks" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x980;
    const callback_one = MEM_BASE + 0x200;
    const callback_two = MEM_BASE + 0x240;
    const thread_local_callback = MEM_BASE + 0x280;
    for ([_]u64{ callback_one, callback_two, thread_local_callback }) |callback| {
        state.write8(callback, 0xC3); // a guest `ret`; execution is simulated below
    }

    state.regs = .{};
    state.regs.rcx = callback_one;
    state.regs.rsp = MEM_BASE + 0x2000;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "_crt_atexit", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(usize, 1), state.windows_crt_globals.normal_count);

    state.regs = .{};
    state.regs.rcx = callback_two;
    state.regs.rsp = MEM_BASE + 0x2000;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "_crt_at_quick_exit", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(usize, 1), state.windows_crt_globals.quick_count);

    state.regs = .{};
    state.regs.rcx = thread_local_callback;
    state.regs.rsp = MEM_BASE + 0x2000;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "_register_thread_local_exe_atexit_callback", return_rip));
    try testing.expectEqual(thread_local_callback, state.windows_crt_globals.thread_local_callback);
    try testing.expectEqual(@as(u64, 3), state.windows_crt_globals.callback_registrations);

    // An indirect exit has its original return address at [RSP]. The normal
    // table is LIFO, followed by the TLS detach callback, and the quick table
    // is discarded when full normal cleanup completes.
    state.regs = .{};
    state.regs.rsp = MEM_BASE + 0x2000;
    state.write64(state.regs.rsp, return_rip);
    try testing.expect(state.beginWindowsCrtExit(7, false, true, false, null));
    try testing.expectEqual(callback_one, state.regs.rip);
    try testing.expectEqual(SYNTHETIC_WINDOWS_CRT_EXIT_RETURN, state.read64(state.regs.rsp));

    state.regs.rsp += 8; // callback's ordinary RET consumes the marker
    state.regs.rip = SYNTHETIC_WINDOWS_CRT_EXIT_RETURN;
    try testing.expect(state.handleSyntheticRip());
    try testing.expectEqual(thread_local_callback, state.regs.rip);
    try testing.expectEqual(@as(u64, 2), state.windows_crt_globals.callback_invocations);

    state.regs.rsp += 8;
    state.regs.rip = SYNTHETIC_WINDOWS_CRT_EXIT_RETURN;
    try testing.expect(state.handleSyntheticRip());
    try testing.expect(state.terminated);
    try testing.expectEqual(@as(u64, 7), state.exit_code);
    try testing.expectEqual(@as(u64, 2), state.windows_crt_globals.callback_invocations);
    try testing.expect(state.windows_crt_globals.termination_complete);
    try testing.expectEqual(@as(usize, 0), state.windows_crt_globals.normal_count);
    try testing.expectEqual(@as(usize, 0), state.windows_crt_globals.quick_count);
    try testing.expectEqual(@as(u64, 0), state.windows_crt_globals.thread_local_callback);
}

test "Windows CRT accepts the PE's large static destructor set" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    // The Xenia PE registers 746 normal callbacks during startup. Keep that
    // observed shape in the contract test so a small fixed table cannot turn
    // valid callbacks into a warning storm again.
    for (0..746) |index| {
        const callback = MEM_BASE + 0x1000 + @as(u64, @intCast(index * 8));
        state.write8(callback, 0xC3); // a guest RET; invocation is not needed here
        try testing.expect(state.registerWindowsCrtAtexit(callback, false, false));
    }
    try testing.expectEqual(@as(usize, 746), state.windows_crt_globals.normal_count);
    try testing.expectEqual(@as(u64, 746), state.windows_crt_globals.callback_registrations);
    try testing.expectEqual(@as(u64, 0), state.windows_crt_globals.callback_rejections);
}

test "Windows CRT cexit returns and capability gaps fail closed in the guest" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0xA80;
    state.regs.rsp = MEM_BASE + 0x2000;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "_cexit", return_rip));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expect(!state.terminated);
    try testing.expect(state.windows_crt_globals.termination_complete);

    state.windows_capability_gaps_fatal = false;
    try testing.expect(!state.terminateForWindowsCapabilityGap("third_party.dll", "MissingExport"));
    try testing.expect(!state.terminated);
    try testing.expectEqual(@as(u64, 1), state.windows_capability_gap_events);

    var fatal = ElfState.init(testing.allocator);
    defer fatal.deinit();
    try testing.expect(fatal.terminateForWindowsCapabilityGap("third_party.dll", "MissingExport"));
    try testing.expect(fatal.terminated);
    try testing.expect(fatal.faulted);
    try testing.expectEqual(@as(u64, 127), fatal.exit_code);
    try testing.expectEqual(@as(u64, 1), fatal.windows_capability_gap_events);
}
