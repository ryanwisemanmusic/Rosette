const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_block_jit = @import("block_jit.zig");
const process_impl_execution = @import("execution.zig");
const process_impl_guest_heap = @import("guest_heap.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_run_reporting = @import("run_reporting.zig");
const process_impl_windows_audio = @import("windows_audio.zig");
const process_impl_windows_sync = @import("windows_sync.zig");
const process_impl_windows_ui = @import("windows_ui.zig");
const __process_ChainStage = __ProcessInternals._ChainStage;
const __process_FIRST_FRAME_STAGE_COUNT = __ProcessInternals._FIRST_FRAME_STAGE_COUNT;
const __process_GPU_INDIRECT_BUFFER_CAPACITY = __ProcessInternals._GPU_INDIRECT_BUFFER_CAPACITY;
const __process_GPU_REGISTER_TRAFFIC_CAPACITY = __ProcessInternals._GPU_REGISTER_TRAFFIC_CAPACITY;
const __process_GPU_RING_WINDOW_ALIAS_CHECKS = __ProcessInternals._GPU_RING_WINDOW_ALIAS_CHECKS;
const __process_GPU_RING_WINDOW_CAPACITY = __ProcessInternals._GPU_RING_WINDOW_CAPACITY;
const __process_GPU_RING_WINDOW_DECODE_LIMIT = __ProcessInternals._GPU_RING_WINDOW_DECODE_LIMIT;
const __process_GPU_RING_WINDOW_FIRST_DWORDS = __ProcessInternals._GPU_RING_WINDOW_FIRST_DWORDS;
const __process_GPU_RING_WINDOW_INDIRECT_BUFFERS = __ProcessInternals._GPU_RING_WINDOW_INDIRECT_BUFFERS;
const __process_GPU_RING_WINDOW_OPCODES = __ProcessInternals._GPU_RING_WINDOW_OPCODES;
const __process_GUEST_MILESTONE_COUNT = __ProcessInternals._GUEST_MILESTONE_COUNT;
const __process_GUEST_MILESTONE_TRANSLATOR_SATURATION = __ProcessInternals._GUEST_MILESTONE_TRANSLATOR_SATURATION;
const __process_GUEST_MODULE_LOOKUP_CAPACITY = __ProcessInternals._GUEST_MODULE_LOOKUP_CAPACITY;
const __process_GUEST_MODULE_NAME_BYTES = __ProcessInternals._GUEST_MODULE_NAME_BYTES;
const __process_GUEST_OUTPUT_STAGE_COUNT = __ProcessInternals._GUEST_OUTPUT_STAGE_COUNT;
const __process_GUEST_VFS_PATH_BYTES = __ProcessInternals._GUEST_VFS_PATH_BYTES;
const __process_GUEST_VFS_RESOLVE_CAPACITY = __ProcessInternals._GUEST_VFS_RESOLVE_CAPACITY;
const __process_GpuDrawFailure = __ProcessInternals._GpuDrawFailure;
const __process_GpuDrawTuple = __ProcessInternals._GpuDrawTuple;
const __process_GpuRingWindow = __ProcessInternals._GpuRingWindow;
const __process_GuestAccessViolation = __ProcessInternals._GuestAccessViolation;
const __process_GuestFrameCost = __ProcessInternals._GuestFrameCost;
const __process_GuestFrontBuffer = __ProcessInternals._GuestFrontBuffer;
const __process_GuestMilestoneActivity = __ProcessInternals._GuestMilestoneActivity;
const __process_GuestReturnCapture = __ProcessInternals._GuestReturnCapture;
const __process_GuestReturnCaptureKind = __ProcessInternals._GuestReturnCaptureKind;
const __process_GuestSymbolResolver = __ProcessInternals._GuestSymbolResolver;
const __process_GuestVfsResolveSummary = __ProcessInternals._GuestVfsResolveSummary;
const __process_GuestXmaRegisterCensus = __ProcessInternals._GuestXmaRegisterCensus;
const __process_MAX_WINDOWS_GUEST_THREADS = __ProcessInternals._MAX_WINDOWS_GUEST_THREADS;
const __process_STACK_SIZE = __ProcessInternals._STACK_SIZE;
const __process_SYNTHETIC_INIT_RETURN = __ProcessInternals._SYNTHETIC_INIT_RETURN;
const __process_SYNTHETIC_MAIN_RETURN = __ProcessInternals._SYNTHETIC_MAIN_RETURN;
const __process_SYNTHETIC_WINDOWS_APC_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_APC_RETURN;
const __process_SYNTHETIC_WINDOWS_AUDIO_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_AUDIO_RETURN;
const __process_SYNTHETIC_WINDOWS_CRT_EXIT_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_CRT_EXIT_RETURN;
const __process_SYNTHETIC_WINDOWS_EXCEPTION_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_EXCEPTION_RETURN;
const __process_SYNTHETIC_WINDOWS_MESSAGE_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_MESSAGE_RETURN;
const __process_SYNTHETIC_WINDOWS_THREAD_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_THREAD_RETURN;
const __process_WINDOWS_GUEST_THREAD_NAME_BYTES = __ProcessInternals._WINDOWS_GUEST_THREAD_NAME_BYTES;
const __process_WINDOWS_WAIT_ESCALATION_MIN_AGE_STEPS = __ProcessInternals._WINDOWS_WAIT_ESCALATION_MIN_AGE_STEPS;
const __process_WINDOWS_WAIT_ESCALATION_MIN_AGE_TICKS = __ProcessInternals._WINDOWS_WAIT_ESCALATION_MIN_AGE_TICKS;
const __process_WINDOWS_WAVE_OUT_PACING_LEAD_NS = __ProcessInternals._WINDOWS_WAVE_OUT_PACING_LEAD_NS;
const __process_WindowsDynamicRefusal = __ProcessInternals._WindowsDynamicRefusal;
const __process_WindowsGuestFailurePoint = __ProcessInternals._WindowsGuestFailurePoint;
const __process_WindowsGuestThread = __ProcessInternals._WindowsGuestThread;
const __process_WindowsImportStub = __ProcessInternals._WindowsImportStub;
const __process_WindowsSrwLock = __ProcessInternals._WindowsSrwLock;
const __process_WindowsWaveOutDevice = __ProcessInternals._WindowsWaveOutDevice;
const __process_XENIA_GLOBAL_MUTEX_SYMBOL = __ProcessInternals._XENIA_GLOBAL_MUTEX_SYMBOL;
const __process_block_jit = __ProcessInternals._block_jit;
const __process_call_probe = __ProcessInternals._call_probe;
const __process_copyBoundedName = __ProcessInternals._copyBoundedName;
const __process_elf_loader = __ProcessInternals._elf_loader;
const __process_envU64 = __ProcessInternals._envU64;
const __process_exit_diagnostics = __ProcessInternals._exit_diagnostics;
const __process_frame_attribution = __ProcessInternals._frame_attribution;
const __process_gpuPrimitiveFinding = __ProcessInternals._gpuPrimitiveFinding;
const __process_guestMilestoneFilterBit = __ProcessInternals._guestMilestoneFilterBit;
const __process_guestMilestoneSaturable = __ProcessInternals._guestMilestoneSaturable;
const __process_guest_address_space = __ProcessInternals._guest_address_space;
const __process_guest_output_governor = __ProcessInternals._guest_output_governor;
const __process_guest_page_protection = __ProcessInternals._guest_page_protection;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_host_profile = __ProcessInternals._host_profile;
const __process_instructionRate = __ProcessInternals._instructionRate;
const __process_isLiveWindowsGuestThread = __ProcessInternals._isLiveWindowsGuestThread;
const __process_kernel_call_census = __ProcessInternals._kernel_call_census;
const __process_log = __ProcessInternals._log;
const __process_milestone_slot_collision = __ProcessInternals._milestone_slot_collision;
const __process_monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const __process_parallel_metrics = __ProcessInternals._parallel_metrics;
const __process_pthread_set_qos_class_self_np = __ProcessInternals._pthread_set_qos_class_self_np;
const __process_spin_anatomy = __ProcessInternals._spin_anatomy;
const __process_std = __ProcessInternals._std;
const __process_tso_memory = __ProcessInternals._tso_memory;
const __process_ui_draw_evidence = __ProcessInternals._ui_draw_evidence;
const __process_wait_cost = __ProcessInternals._wait_cost;
const __process_windows_message_queue = __ProcessInternals._windows_message_queue;
const __process_windows_registry_model = __ProcessInternals._windows_registry_model;
const __process_windows_srw_owner_stack_depth = __ProcessInternals._windows_srw_owner_stack_depth;
const __process_x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const __process_xbox_critical_section = __ProcessInternals._xbox_critical_section;
const __process_xenia_clock_probe = __ProcessInternals._xenia_clock_probe;
const __process_xenia_fatal_condition_map = __ProcessInternals._xenia_fatal_condition_map;
const __process_xenia_guest_frontier_map = __ProcessInternals._xenia_guest_frontier_map;
const __process_xenia_guest_milestone_map = __ProcessInternals._xenia_guest_milestone_map;
const __process_xenia_kernel_shim_map = __ProcessInternals._xenia_kernel_shim_map;
const __process_xenia_presenter_attach_milestones = __ProcessInternals._xenia_presenter_attach_milestones;
const __process_xenia_warning_severity_map = __ProcessInternals._xenia_warning_severity_map;
const __state_GpuRingSource = __StateInternals._GpuRingSource;
const __state_GuestOutputHostSink = __StateInternals._GuestOutputHostSink;
const __state_HostQos = __StateInternals._HostQos;
const __state_WindowsBlockedCause = __StateInternals._WindowsBlockedCause;
const __state_WindowsBlockedFinding = __StateInternals._WindowsBlockedFinding;

pub fn loadElf(self: *ElfState, elf_bytes: []const u8) !void {
    const plan = try __process_elf_loader.planExecutableLoad(self.mem.len, elf_bytes, __process_STACK_SIZE);
    self.mem_base = plan.mem_base;
    self.image_low = plan.image_low;
    self.image_high = plan.image_high;
    self.heap_next = plan.heap_start;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = try __process_elf_loader.loadExecutableSegments(self.mem_base, self.mem, elf_bytes);
    __process_log.info("load plan: guest_base=0x{x} image=[0x{x}, 0x{x}) heap=0x{x} entry=0x{x}", .{
        plan.mem_base,
        plan.image_low,
        plan.image_high,
        plan.heap_start,
        plan.entry,
    });
}

pub fn startLibcMain(self: *ElfState, main_addr: u64, argc: u64, argv: u64) void {
    self.pending_main_addr = main_addr;
    self.pending_argc = argc;
    self.pending_argv = argv;
    self.init_index = 0;
    self.libc_start_main_trampolined = true;
    scheduleNextInitOrMain(self);
}

pub fn scheduleNextInitOrMain(self: *ElfState) void {
    while (self.init_index < self.init_functions.len) {
        const target = self.init_functions[self.init_index];
        self.init_index += 1;
        if (target == 0 or process_impl_guest_memory.addrToOffset(self, target) == null) continue;
        process_impl_lifecycle.guestContextField(self, "regs").*.rdi = self.pending_argc;
        process_impl_lifecycle.guestContextField(self, "regs").*.rsi = self.pending_argv;
        process_impl_lifecycle.guestContextField(self, "regs").*.rdx = 0;
        process_impl_guest_memory.push(self, __process_SYNTHETIC_INIT_RETURN);
        process_impl_lifecycle.guestContextField(self, "regs").*.rip = target;
        __process_log.info("running ELF init function {d}/{d} at 0x{x}", .{
            self.init_index,
            self.init_functions.len,
            target,
        });
        return;
    }
    startMainAfterInit(self);
}

pub fn startMainAfterInit(self: *ElfState) void {
    process_impl_lifecycle.guestContextField(self, "regs").*.rdi = self.pending_argc;
    process_impl_lifecycle.guestContextField(self, "regs").*.rsi = self.pending_argv;
    process_impl_lifecycle.guestContextField(self, "regs").*.rdx = 0;
    process_impl_guest_memory.push(self, __process_SYNTHETIC_MAIN_RETURN);
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = self.pending_main_addr;
}

pub fn handleSyntheticRip(self: *ElfState) bool {
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_SYNTHETIC_WINDOWS_APC_RETURN) {
        process_impl_windows_sync.continueWindowsApcDelivery(self);
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_SYNTHETIC_WINDOWS_THREAD_RETURN) {
        process_impl_windows_sync.finishWindowsGuestThread(self);
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_SYNTHETIC_WINDOWS_MESSAGE_RETURN) {
        _ = process_impl_windows_ui.finishWindowsMessageDispatch(self);
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_SYNTHETIC_WINDOWS_AUDIO_RETURN) {
        _ = process_impl_windows_ui.finishWindowsAudioCallback(self);
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_SYNTHETIC_WINDOWS_EXCEPTION_RETURN) {
        process_impl_guest_memory.finishWindowsExceptionDispatch(self);
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_SYNTHETIC_WINDOWS_CRT_EXIT_RETURN) {
        process_impl_guest_memory.continueWindowsCrtExit(self);
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_x64_linux_runtime.SYNTHETIC_PTHREAD_ONCE_RETURN) {
        const once_control = process_impl_guest_memory.pop(self);
        if (once_control != 0) process_impl_guest_memory.write32(self, once_control, 1);
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
        // The word below the once-control is either the original return
        // address of an import stub or the direct continuation saved by
        // the dynamic-call shortcut. Both paths therefore share the same
        // guest-only completion protocol.
        process_impl_lifecycle.guestContextField(self, "regs").*.rip = process_impl_guest_memory.pop(self);
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_x64_linux_runtime.SYNTHETIC_INITTERM_RETURN) {
        process_impl_guest_memory.continueWindowsInitTerm(self);
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_x64_linux_runtime.SYNTHETIC_QSORT_RETURN) {
        process_impl_guest_memory.continueWindowsQsort(self);
        return true;
    }
    if (process_impl_guest_memory.handleWindowsBsearchSyntheticRip(self)) return true;
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_SYNTHETIC_INIT_RETURN) {
        scheduleNextInitOrMain(self);
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == __process_SYNTHETIC_MAIN_RETURN) {
        self.exit_code = process_impl_lifecycle.guestContextField(self, "regs").*.rax;
        self.termination_reason = .exit_syscall;
        process_impl_lifecycle.markTerminated(self);
        return true;
    }
    return false;
}

pub fn shouldReportWindowsPointOccurrence(occurrences: u64) bool {
    return occurrences <= 2 or (occurrences & (occurrences - 1)) == 0;
}

pub fn terminateForWindowsFatalPoint(self: *ElfState, label: []const u8) void {
    terminateForWindowsFatalPointWith(self, label, .runtime_invariant_failure, 125);
}

pub fn terminateForWindowsFatalPointWith(
    self: *ElfState,
    label: []const u8,
    reason: __process_exit_diagnostics.TerminationReason,
    exit_code: u64,
) void {
    if (process_impl_lifecycle.isTerminated(self)) return;
    if (windowsFatalPointAllowed(self, label)) {
        self.windows_fatal_point_allowed_events +|= 1;
        const allowed = self.windows_fatal_point_allowed_events;
        if (shouldReportWindowsPointOccurrence(allowed)) {
            __process_log.warn("PE64 FATAL POINT ALLOWED: label={s} step={d} rip=0x{x} allowed_events={d}; ROSETTE_XENIA_FATAL_POINT_ALLOW names this label, so the run steps past it and everything after this line is gathered on top of a known failure", .{
                label,
                process_impl_lifecycle.observedExecutionSteps(self),
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                allowed,
            });
        }
        return;
    }
    if (!self.windows_fatal_point_terminate) return;
    process_impl_lifecycle.markFaulted(self);
    self.exit_code = exit_code;
    self.termination_reason = reason;
    process_impl_lifecycle.markTerminated(self);
    process_impl_execution.recordTerminalEvent(self, .fatal_point, label, 0, "the fatal-point policy stopped the run at '{s}' (ROSETTE_XENIA_FATAL_POINT_ALLOW={s} steps past it; ROSETTE_XENIA_FATAL_POINT_TERMINATE=0 records fatal points without stopping)", .{ label, label });
    process_impl_execution.noteNotableEvent(self, .fatal_point, 0, "fatal point '{s}' stopped the run", .{label});
    if (comptime !@import("builtin").is_test) {
        var at_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        const slot_plus_one: u8 = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| @intCast(@min(slot + 1, 255)) else 0;
        __process_log.err("PE64 FATAL POINT TERMINATION: label={s} step={d} rip=0x{x} at={s} thread={s}; the run stops where this was decided. ROSETTE_XENIA_FATAL_POINT_ALLOW={s} steps past this label to reach the next one, and ROSETTE_XENIA_FATAL_POINT_TERMINATE=0 records every fatal point without stopping", .{
            label,
            process_impl_lifecycle.observedExecutionSteps(self),
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &at_text),
            guestThreadLabel(self, slot_plus_one),
            label,
        });
    }
}

pub fn configureWindowsFatalPointAllow(self: *ElfState, text: ?[]const u8) void {
    const value = text orelse "";
    const count = @min(value.len, self.windows_fatal_point_allow.len);
    @memcpy(self.windows_fatal_point_allow[0..count], value[0..count]);
    self.windows_fatal_point_allow_len = count;
}

pub fn windowsFatalPointAllowed(self: *const ElfState, label: []const u8) bool {
    var labels = __process_std.mem.tokenizeAny(u8, self.windows_fatal_point_allow[0..self.windows_fatal_point_allow_len], ", ;");
    while (labels.next()) |candidate| {
        if (__process_std.mem.eql(u8, candidate, label)) return true;
    }
    return false;
}

pub fn terminateForWindowsCapabilityGap(self: *ElfState, dll_name: []const u8, function_name: []const u8) bool {
    if (process_impl_lifecycle.isTerminated(self)) return true;
    self.windows_capability_gap_events +|= 1;
    if (!self.windows_capability_gaps_fatal) {
        __process_log.warn("PE64 CAPABILITY GAP CONTINUED: dll={s} export={s} step={d} rip=0x{x}; compatibility override is active", .{
            dll_name,
            function_name,
            process_impl_lifecycle.observedExecutionSteps(self),
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        });
        return false;
    }
    process_impl_lifecycle.markFaulted(self);
    self.exit_code = 127;
    self.termination_reason = .runtime_invariant_failure;
    process_impl_lifecycle.markTerminated(self);
    if (comptime !@import("builtin").is_test) {
        __process_log.err("PE64 CAPABILITY GAP FATAL: dll={s} export={s} step={d} rip=0x{x}; the emulated guest was terminated before an unimplemented ABI answer could corrupt state", .{
            dll_name,
            function_name,
            process_impl_lifecycle.observedExecutionSteps(self),
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        });
    }
    return true;
}

pub fn noteWindowsGuestCondition(self: *ElfState, condition: __process_xenia_fatal_condition_map.Condition, line: []const u8) void {
    var entry: ?*__process_WindowsGuestFailurePoint = null;
    for (self.windows_guest_failure_points[0..self.windows_guest_failure_point_count]) |*candidate| {
        if (__process_std.mem.eql(u8, candidate.labelText(), condition.label)) {
            entry = candidate;
            break;
        }
    }
    if (entry == null) {
        if (self.windows_guest_failure_point_count >= self.windows_guest_failure_points.len) {
            self.windows_guest_failure_point_overflow +|= 1;
            __process_log.err("PE64 FATAL POINT: guest-condition-ledger-overflow label={s} step={d} rip=0x{x}", .{
                condition.label,
                process_impl_lifecycle.observedExecutionSteps(self),
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            });
            return;
        }
        entry = &self.windows_guest_failure_points[self.windows_guest_failure_point_count];
        entry.?.* = .{};
        entry.?.label_len = process_impl_guest_memory.copyUnresolvedImportName(&entry.?.label, condition.label);
        entry.?.owner_len = process_impl_guest_memory.copyUnresolvedImportName(&entry.?.owner, condition.owner.label());
        entry.?.line_len = process_impl_guest_memory.copyUnresolvedImportName(&entry.?.line, line);
        entry.?.first_step = process_impl_lifecycle.observedExecutionSteps(self);
        entry.?.first_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
        self.windows_guest_failure_point_count += 1;
    }

    const record = entry.?;
    record.occurrences +|= 1;
    record.last_step = process_impl_lifecycle.observedExecutionSteps(self);
    record.last_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    // A condition below its declared threshold is the design it names
    // (Xenia's XamState commits three unreserved pages on every start);
    // it is reported, and only the occurrence that makes it decisive is
    // a fatal point.
    const decisive = record.occurrences >= condition.repeats;
    if (shouldReportWindowsPointOccurrence(record.occurrences) or record.occurrences == condition.repeats) {
        if (decisive) {
            __process_log.err("PE64 FATAL POINT: guest-condition label={s} owner={s} occurrence={d} of {d} step={d} rip=0x{x} line={s} remedy={s}", .{
                record.labelText(),
                record.ownerText(),
                record.occurrences,
                condition.repeats,
                process_impl_lifecycle.observedExecutionSteps(self),
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                record.lineText(),
                condition.remedy,
            });
        } else {
            __process_log.info("PE64 emulator design event: label={s} owner={s} occurrence={d} below the {d} that make it decisive step={d} rip=0x{x} line={s}; at this count the line is the emulator's own documented behaviour, not a fault, and only the decisive occurrence is a fatal point. remedy={s}", .{
                record.labelText(),
                record.ownerText(),
                record.occurrences,
                condition.repeats,
                process_impl_lifecycle.observedExecutionSteps(self),
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                record.lineText(),
                condition.remedy,
            });
        }
    }
    if (decisive) {
        // Counted once, at the occurrence that makes it decisive: a
        // condition below its threshold is the design it names and is
        // not a fatal point the run met.
        if (record.occurrences == condition.repeats) self.windows_fatal_point_events +|= 1;
        terminateForWindowsFatalPoint(self, record.labelText());
    }
}

pub fn substantiateGuestAdvisory(self: *const ElfState, line: []const u8) void {
    switch (__process_xenia_warning_severity_map.evidenceFor(line)) {
        .none => {},
        .dxgi_factory => substantiateFromImportLedger(
            self,
            "dxgi.dll",
            "CreateDXGIFactory",
            "dxgi.dll has no host backend on macOS, so Rosette answers the factory call with an HRESULT refusal rather than a null pointer the guest would dereference. Xenia uses the factory for one thing: the DXGI UI tick thread in Presenter, which paces UI-thread repaints against a monitor's vertical blank. Without an IDXGIOutput, Presenter::AreDXGIUITicksWaitable is false, so Presenter::WaitForUITickFromUIThread returns immediately and UI painting is unpaced rather than blocked. It is not on the path to GraphicsSystem::MarkVblank, which the GPU frame limiter drives from a Clock::QueryGuestTickCount delta with no DXGI involvement",
        ),
        .vulkan_shader_creation => substantiateVulkanShaderCreation(self),
        .guest_font_policy => __process_log.warn(
            "PE64 guest advisory substantiation: Rosette's own font policy decided this. CJK font granted={}; the decision is Rosette's, not a missing host font, and ROSETTE_XENIA_GUEST_CJK_FONT selects it",
            .{self.windows_cjk_font_granted},
        ),
        .guest_heap_commit => __process_log.warn(
            "PE64 guest advisory substantiation: see PE64 MEMORY CONTRACT for how Rosette classified this commit against what already backed the address; a commit Rosette relocated is listed there with its requested and actual addresses",
            .{},
        ),
        .vulkan_device_selection => __process_log.info(
            "PE64 guest advisory substantiation: the adapter the guest is choosing between is the one Rosette's Vulkan bridge enumerated; see the macho-processor Vulkan milestone lines for the device and the features verified against the host",
            .{},
        ),
    }
}

pub fn substantiateFromImportLedger(
    self: *const ElfState,
    dll_name: []const u8,
    name_prefix: []const u8,
    consequence: []const u8,
) void {
    // The observed-refusal ledger, not the contract-fallback one: the
    // second holds only names Rosette has no handler for, and a refusal
    // from a handler it does have is exactly as load-bearing to the guest.
    const ledger = &self.windows_import_refusals;
    var matched: usize = 0;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    for (ledger.entries[0..ledger.count]) |*entry| {
        if (!entry.used) continue;
        if (!__process_std.ascii.eqlIgnoreCase(entry.dll(), dll_name)) continue;
        if (!__process_std.mem.startsWith(u8, entry.name(), name_prefix)) continue;
        matched += 1;
        __process_log.warn(
            "PE64 guest advisory substantiation: Rosette answered {s}!{s} x{d} with 0x{x} ({s}, convention={s}); first at step {d} from {s} (rip=0x{x}), args=0x{x},0x{x}",
            .{
                entry.dll(),
                entry.name(),
                entry.calls,
                entry.value,
                @tagName(entry.outcome),
                @tagName(entry.convention),
                entry.first_step,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, entry.first_caller_rip, &caller_text),
                entry.first_caller_rip,
                entry.first_arg0,
                entry.first_arg1,
            },
        );
    }
    if (matched == 0) {
        // The guest reported a failure Rosette has no record of causing.
        // That is a finding of its own: the decision was made inside the
        // guest, or on a path that answers without recording.
        __process_log.warn(
            "PE64 guest advisory substantiation: Rosette has no ledger entry for {s}!{s}*. Either the guest decided this without calling out, or the call was served on a path that does not record - and the second is a hole in this instrument, not evidence about the guest",
            .{ dll_name, name_prefix },
        );
        return;
    }
    __process_log.warn("PE64 guest advisory substantiation: consequence: {s}", .{consequence});
}

pub fn substantiateVulkanShaderCreation(self: *const ElfState) void {
    const graphics = &self.windows_graphics;
    __process_log.warn(
        "PE64 guest advisory substantiation: Rosette's Vulkan bridge observed vk_calls={d} native_vk_calls={d} with native_vk_failures={d}, ordering_violations={d} and unmodeled={d}. Zero aggregate failures do NOT prove every shader creation reached the driver or that the guest consumed its published handle. Read the positive per-entry create ledger below; reconcile attempts, publications, bridge refusals and driver results against the guest warning",
        .{
            graphics.vulkan_calls,
            graphics.native_vulkan_calls,
            graphics.native_vulkan_failures,
            graphics.ordering_violations,
            graphics.unmodeled_calls,
        },
    );
    if (graphics.hooks.report_present_chain_full) |callback| {
        callback(graphics.hooks.native_context);
    } else {
        __process_log.warn("PE64 guest advisory substantiation: native create-ledger reporting hook is unavailable; aggregate counters cannot locate this shader failure", .{});
    }
}

pub fn guestLogLineThreadToken(line: []const u8) ?[]const u8 {
    const markers = [_][]const u8{ "!> ", "w> ", "x> ", "i> ", "d> " };
    for (markers) |marker| {
        const at = __process_std.mem.indexOf(u8, line, marker) orelse continue;
        const start = at + marker.len;
        if (line.len < start + 8) continue;
        const token = line[start .. start + 8];
        var hex = true;
        for (token) |byte| {
            if (!__process_std.ascii.isHex(byte)) hex = false;
        }
        if (hex) return token;
    }
    return null;
}

pub fn describeGuestLogLineOrigin(self: *const ElfState, line: []const u8, buffer: []u8) []const u8 {
    const token = guestLogLineThreadToken(line) orelse return "";
    for (self.windows_guest_threads) |*thread| {
        if (thread.status == .vacant or thread.name_len == 0) continue;
        const name = thread.nameText();
        const at = __process_std.mem.indexOf(u8, name, token) orelse continue;
        if (at == 0 or name[at - 1] != '(') continue;
        if (at + token.len >= name.len or name[at + token.len] != ')') continue;
        const slot = self.guest_kernel_calls.slotAt(thread.last_kernel_slot);
        return __process_std.fmt.bufPrint(buffer, " emitted_by='{s}' last_kernel_call={s}!{s} at_step={d}", .{
            name,
            if (slot) |entry| entry.module.moduleName() else "<none>",
            if (slot) |entry| entry.export_name else "<none>",
            thread.last_kernel_step,
        }) catch "";
    }
    return "";
}

pub fn isConfirmedEmptyResolvePathProbe(line: []const u8, origin: []const u8) bool {
    if (!__process_xenia_warning_severity_map.isEmptyResolvePath(line)) return false;
    return __process_std.mem.indexOf(u8, origin, "last_kernel_call=xboxkrnl.exe!NtCreateFile") != null or
        __process_std.mem.indexOf(u8, origin, "last_kernel_call=xboxkrnl.exe!RtlNtStatusToDosError") != null or
        __process_std.mem.indexOf(u8, origin, "last_kernel_call=xboxkrnl.exe!RtlImageXexHeaderField") != null;
}

pub fn parsePm4DrawFailure(line: []const u8) ?__process_GpuDrawTuple {
    const marker = "PM4_DRAW_INDX(";
    const marker_start = __process_std.mem.indexOf(u8, line, marker) orelse return null;
    var cursor = marker_start + marker.len;
    var values: [3]u32 = undefined;
    for (&values, 0..) |*value, index| {
        while (cursor < line.len and (line[cursor] == ' ' or line[cursor] == '\t')) cursor += 1;
        const start = cursor;
        while (cursor < line.len and __process_std.ascii.isDigit(line[cursor])) cursor += 1;
        if (start == cursor) return null;
        value.* = __process_std.fmt.parseInt(u32, line[start..cursor], 10) catch return null;
        while (cursor < line.len and (line[cursor] == ' ' or line[cursor] == '\t')) cursor += 1;
        if (index != values.len - 1) {
            if (cursor >= line.len or line[cursor] != ',') return null;
            cursor += 1;
        }
    }
    while (cursor < line.len and (line[cursor] == ' ' or line[cursor] == '\t')) cursor += 1;
    if (cursor >= line.len or line[cursor] != ')') return null;
    return .{
        .index_count = values[0],
        .primitive_type = values[1],
        .source_select = values[2],
    };
}

pub fn noteGpuDrawFailure(self: *ElfState, tuple: __process_GpuDrawTuple) void {
    var entry: ?*__process_GpuDrawFailure = null;
    for (self.gpu_draw_failures[0..self.gpu_draw_failure_count]) |*candidate| {
        if (candidate.index_count == tuple.index_count and
            candidate.primitive_type == tuple.primitive_type and
            candidate.source_select == tuple.source_select)
        {
            entry = candidate;
            break;
        }
    }
    if (entry == null and self.gpu_draw_failure_count < self.gpu_draw_failures.len) {
        entry = &self.gpu_draw_failures[self.gpu_draw_failure_count];
        self.gpu_draw_failure_count += 1;
        entry.?.* = .{
            .index_count = tuple.index_count,
            .primitive_type = tuple.primitive_type,
            .source_select = tuple.source_select,
            .first_step = process_impl_lifecycle.observedExecutionSteps(self),
            .first_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        };
    } else if (entry == null) {
        self.gpu_draw_failure_overflow +|= 1;
        return;
    }

    const record = entry.?;
    record.occurrences +|= 1;
    record.last_step = process_impl_lifecycle.observedExecutionSteps(self);
    record.last_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    if (!shouldReportWindowsPointOccurrence(record.occurrences)) return;

    const stream_mapping_complete = self.gpu_ring_initialized and
        self.gpu_ring_unreadable_updates == 0 and
        self.gpu_ring_alias_mismatches == 0 and
        self.gpu_indirect_buffers_unreadable == 0;
    const primitive = __process_gpuPrimitiveFinding(tuple.primitive_type);
    __process_log.warn("PE64 GPU DRAW FINDING: tuple=({d},{d},{d}) primitive={s} occurrence={d} step={d} rip=0x{x} classification={s} command_stream_mapping={s} ring_updates={d} indirect_buffers={d} action={s}", .{
        tuple.index_count,
        tuple.primitive_type,
        tuple.source_select,
        primitive.name,
        record.occurrences,
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        primitive.classification,
        if (stream_mapping_complete) "readable-and-alias-consistent" else "incomplete-or-conflicted",
        self.gpu_ring_updates,
        self.gpu_indirect_buffers_seen,
        if (stream_mapping_complete)
            primitive.action
        else
            "first repair command-stream mapping evidence, then capture the active pipeline, index/vertex bindings, and guest resource addresses",
    });
}

pub fn reportGpuDrawFailures(self: *const ElfState) void {
    if (self.gpu_draw_failure_count == 0 and self.gpu_draw_failure_overflow == 0) return;
    const stream_mapping_complete = self.gpu_ring_initialized and
        self.gpu_ring_unreadable_updates == 0 and
        self.gpu_ring_alias_mismatches == 0 and
        self.gpu_indirect_buffers_unreadable == 0;
    __process_log.info("PE64 GPU DRAW FINDINGS: distinct={d} overflow={d} command_stream_mapping={s} ring_updates={d} alias_mismatches={d} unreadable_updates={d} indirect_unreadable={d}; this ledger classifies backend refusals without pretending command-memory proof covers per-draw resources", .{
        self.gpu_draw_failure_count,
        self.gpu_draw_failure_overflow,
        if (stream_mapping_complete) "readable-and-alias-consistent" else "incomplete-or-conflicted",
        self.gpu_ring_updates,
        self.gpu_ring_alias_mismatches,
        self.gpu_ring_unreadable_updates,
        self.gpu_indirect_buffers_unreadable,
    });
    for (self.gpu_draw_failures[0..self.gpu_draw_failure_count]) |record| {
        const primitive = __process_gpuPrimitiveFinding(record.primitive_type);
        __process_log.info("PE64 GPU DRAW FINDING: tuple=({d},{d},{d}) primitive={s} occurrences={d} first_step={d} last_step={d} first_rip=0x{x} last_rip=0x{x} classification={s} action={s}", .{
            record.index_count,
            record.primitive_type,
            record.source_select,
            primitive.name,
            record.occurrences,
            record.first_step,
            record.last_step,
            record.first_rip,
            record.last_rip,
            primitive.classification,
            primitive.action,
        });
    }
}

pub fn noteWindowsGuestWarning(self: *ElfState, line: []const u8) void {
    if (parsePm4DrawFailure(line)) |tuple| noteGpuDrawFailure(self, tuple);
    self.windows_guest_warning_lines +|= 1;
    // Xenia prints its adapter list, its chosen device and its capability
    // narration at warning level. Recording those as fatal points with
    // `log.err` trains a reader to skim the block that also holds the real
    // ones, so an informational line is noted once, quietly, and never
    // enters the failure-point ledger.
    if (__process_xenia_warning_severity_map.isUnresolvedImport(line)) self.windows_guest_unresolved_import_lines +|= 1;
    var origin_text: [192]u8 = undefined;
    // An empty path is joined to the VFS ledger first: that record was
    // taken synchronously inside the call that asked, while the thread's
    // last kernel call is only what it had reached by the time Xenia's
    // asynchronous logger printed the line.
    var ledger_text: [384]u8 = undefined;
    const ledger_origin = if (__process_xenia_warning_severity_map.isEmptyResolvePath(line))
        describeVfsResolveFor(self, "", &ledger_text)
    else
        "";
    const origin = if (ledger_origin.len != 0) ledger_origin else describeGuestLogLineOrigin(self, line, &origin_text);
    const empty_path_probe = isConfirmedEmptyResolvePathProbe(line, origin) or ledger_origin.len != 0;
    const severity = if (empty_path_probe) .advisory else __process_xenia_warning_severity_map.classify(line);
    if (severity == .informational) {
        self.windows_guest_informational_lines +|= 1;
        if (__process_xenia_warning_severity_map.bareModuleLookupName(line)) |module| {
            const occurrence = noteGuestModuleLookupLine(self, module);
            if (shouldReportWindowsPointOccurrence(occurrence)) {
                var resolve_text: [384]u8 = undefined;
                __process_log.info("PE64 guest module lookup: module={s} occurrence={d} unresolved_imports_so_far={d}{s}; {s}", .{
                    module,
                    occurrence,
                    self.windows_guest_unresolved_import_lines,
                    describeVfsResolveFor(self, module, &resolve_text),
                    if (occurrence == 1) __process_xenia_warning_severity_map.bare_module_lookup_reason else "PE64 GUEST MODULE LOOKUPS at exit carries the total",
                });
            }
        } else {
            __process_log.info("PE64 guest narration: {s}", .{line});
        }
        return;
    }
    const advisory = severity == .advisory;
    const reason: []const u8 = if (empty_path_probe)
        "the asynchronous echo of the synchronous vfs-empty-object-name fatal point, which stopped the run or was stepped past by ROSETTE_XENIA_FATAL_POINT_ALLOW; that line carries the NtCreateFile request behind the empty name"
    else if (__process_xenia_warning_severity_map.entryFor(line)) |entry|
        entry.reason
    else
        "";

    for (self.windows_guest_warning_points[0..self.windows_guest_warning_point_count]) |*entry| {
        if (!__process_std.mem.eql(u8, entry.lineText(), line)) continue;
        entry.occurrences +|= 1;
        entry.last_step = process_impl_lifecycle.observedExecutionSteps(self);
        if (shouldReportWindowsPointOccurrence(entry.occurrences)) {
            if (advisory) {
                __process_log.warn("PE64 guest advisory: occurrence={d} step={d} rip=0x{x} line={s}", .{
                    entry.occurrences,
                    process_impl_lifecycle.observedExecutionSteps(self),
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    entry.lineText(),
                });
            } else {
                __process_log.err("PE64 FATAL POINT: guest-warning label={s} occurrence={d} step={d} rip=0x{x} line={s}{s}{s}{s}", .{
                    __process_xenia_warning_severity_map.labelFor(line),
                    entry.occurrences,
                    process_impl_lifecycle.observedExecutionSteps(self),
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    entry.lineText(),
                    if (reason.len != 0) " classification=" else "",
                    reason,
                    origin,
                });
            }
        }
        return;
    }
    if (self.windows_guest_warning_point_count >= self.windows_guest_warning_points.len) {
        self.windows_guest_warning_point_overflow +|= 1;
        return;
    }
    var entry = &self.windows_guest_warning_points[self.windows_guest_warning_point_count];
    entry.* = .{};
    entry.line_len = process_impl_guest_memory.copyUnresolvedImportName(&entry.line, line);
    entry.first_step = process_impl_lifecycle.observedExecutionSteps(self);
    entry.last_step = process_impl_lifecycle.observedExecutionSteps(self);
    entry.occurrences = 1;
    entry.advisory = advisory;
    self.windows_guest_warning_point_count += 1;
    if (advisory) {
        self.windows_guest_advisory_lines +|= 1;
        // An advisory is a real degradation, so it is retained and
        // reported - but it is not a fatal point, and counting it as one
        // is what made the summary's `unique=` number unreadable.
        __process_log.warn("PE64 guest advisory: step={d} rip=0x{x} line={s} classification={s}{s}", .{
            process_impl_lifecycle.observedExecutionSteps(self),
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            entry.lineText(),
            reason,
            origin,
        });
        substantiateGuestAdvisory(self, line);
        // An empty resolve already had its synchronous fatal point; its
        // echo is not a second one.
        const echoed = empty_path_probe and self.guest_vfs_empty_name_faults != 0;
        if (!echoed and !__process_xenia_warning_severity_map.continuationFor(line).continues()) {
            const label = __process_xenia_warning_severity_map.labelFor(line);
            self.windows_fatal_point_events +|= 1;
            if (comptime !@import("builtin").is_test) {
                __process_log.err("PE64 FATAL POINT: guest-advisory label={s} step={d} rip=0x{x} line={s}; a degradation is survivable only on a named ground - a Rosette policy decision or the emulator's documented design - and this row has neither, so the run treats it as the error it probably is{s}", .{
                    label,
                    process_impl_lifecycle.observedExecutionSteps(self),
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    entry.lineText(),
                    origin,
                });
            }
            terminateForWindowsFatalPoint(self, label);
        }
        return;
    }
    self.windows_fatal_point_events +|= 1;
    const label = __process_xenia_warning_severity_map.labelFor(line);
    __process_log.err("PE64 FATAL POINT: guest-warning label={s} occurrence=1 step={d} rip=0x{x} line={s}{s}{s}{s}", .{
        label,
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        entry.lineText(),
        if (reason.len != 0) " classification=" else "",
        reason,
        origin,
    });
    terminateForWindowsFatalPoint(self, label);
}

pub fn writeWindowsGuestStandardOutput(self: *ElfState, host_fd: __process_std.posix.fd_t, stream_fd: u64, bytes: []const u8) usize {
    const sink = __state_GuestOutputHostSink{ .fd = host_fd, .failures = &self.windows_guest_output_host_write_failures };
    const governors = self.windows_guest_output_governors orelse blk: {
        const created = self.allocator.create([2]__process_guest_output_governor.Governor) catch {
            sink.emit(bytes);
            return bytes.len;
        };
        created.* = .{ .{}, .{} };
        self.windows_guest_output_governors = created;
        break :blk created;
    };
    const index: usize = if (stream_fd == 2) 1 else 0;
    self.windows_guest_output_host_fds[index] = host_fd;
    governors[index].feed(bytes, sink);
    return bytes.len;
}

pub fn flushWindowsGuestOutputGovernors(self: *ElfState) void {
    const governors = self.windows_guest_output_governors orelse return;
    for (governors, 0..) |*governor, index| {
        const fd = self.windows_guest_output_host_fds[index];
        if (fd < 0) continue;
        governor.flush(__state_GuestOutputHostSink{ .fd = fd, .failures = &self.windows_guest_output_host_write_failures });
    }
}

pub fn reportWindowsGuestOutputGovernor(self: *ElfState) void {
    flushWindowsGuestOutputGovernors(self);
    const governors = self.windows_guest_output_governors orelse {
        __process_log.info("PE64 GUEST OUTPUT GOVERNOR: the guest wrote nothing to stdout or stderr", .{});
        return;
    };
    const labels = [_][]const u8{ "stdout", "stderr" };
    for (governors, 0..) |*governor, index| {
        if (governor.lines == 0) continue;
        __process_log.info("PE64 GUEST OUTPUT GOVERNOR: {s} lines={d} written={d} ({d} bytes) withheld_repeats={d} withheld_over_budget={d} ({d} bytes) notices={d} distinct_tracked={d} untracked={d} host_write_failures={d}; every exact line reaches this log {d} times and then only at powers of two, and at most {d} MiB of guest output is written", .{
            labels[index],
            governor.lines,
            governor.passed_lines,
            governor.passed_bytes,
            governor.withheld_repeat_lines,
            governor.withheld_budget_lines,
            governor.withheld_bytes,
            governor.notices,
            governor.distinct_tracked,
            governor.untracked_lines,
            self.windows_guest_output_host_write_failures,
            __process_guest_output_governor.repeat_allowance,
            governor.byte_budget / (1024 * 1024),
        });
        for (&governor.examples) |*example| {
            if (example.count == 0) continue;
            __process_log.info("PE64 GUEST OUTPUT GOVERNOR:   x{d} {s}", .{ example.count, example.textSlice() });
        }
    }
}

pub fn noteGuestModuleLookupLine(self: *ElfState, module: []const u8) u64 {
    self.windows_guest_module_lookup_lines +|= 1;
    const name = module[0..@min(module.len, __process_GUEST_MODULE_NAME_BYTES)];
    for (self.windows_guest_module_lookups[0..self.windows_guest_module_lookup_count]) |*entry| {
        if (!__process_std.mem.eql(u8, entry.nameText(), name)) continue;
        entry.lines +|= 1;
        return entry.lines;
    }
    if (self.windows_guest_module_lookup_count == __process_GUEST_MODULE_LOOKUP_CAPACITY) {
        self.windows_guest_module_lookup_overflow +|= 1;
        return self.windows_guest_module_lookup_lines;
    }
    const entry = &self.windows_guest_module_lookups[self.windows_guest_module_lookup_count];
    self.windows_guest_module_lookup_count += 1;
    entry.* = .{ .lines = 1, .first_step = process_impl_lifecycle.observedExecutionSteps(self), .name_len = @intCast(name.len) };
    @memcpy(entry.name[0..name.len], name);
    return 1;
}

pub fn reportGuestModuleLookups(self: *const ElfState) void {
    if (self.windows_guest_module_lookup_count == 0 and self.windows_guest_unresolved_import_lines == 0) return;
    __process_log.info("PE64 GUEST MODULE LOOKUPS: {d} device-not-found line(s) for {d} bare module name(s); unresolved_imports={d}", .{
        self.windows_guest_module_lookup_lines,
        self.windows_guest_module_lookup_count,
        self.windows_guest_unresolved_import_lines,
    });
    for (self.windows_guest_module_lookups[0..self.windows_guest_module_lookup_count]) |*entry| {
        var resolve_text: [384]u8 = undefined;
        const matched_device_path = guestVfsMatchedDevicePath(self, entry.nameText());
        __process_log.info("PE64 GUEST MODULE LOOKUPS:   module={s} lines={d} first_step={d} matched_device_path={s}{s}", .{
            entry.nameText(),
            entry.lines,
            entry.first_step,
            if (matched_device_path.len == 0) "<none>" else matched_device_path,
            describeVfsResolveFor(self, entry.nameText(), &resolve_text),
        });
    }
    const verdict: []const u8 = if (self.windows_guest_unresolved_import_lines == 0)
        "no import went unbound. Each line is Xenia's GetModule or UserModule::Dump trying a bare module name as a path before matching loaded modules by name; the VFS cannot find a device for a name with no device prefix, and the lookup continues. Where the VFS ledger reports a found game:-device DLL with the same stem, that is the loaded-module evidence. A module that were really missing would be followed by Xenia's 'an import variable was not resolved' warning, and there was none"
    else
        "Xenia reported unbound imports: a title module imports an ordinal nothing loaded exports. The FATAL POINT lines carrying 'an import variable was not resolved' name the library and ordinal, and the module named above is the one to look for on the disc";
    __process_log.info("PE64 GUEST MODULE LOOKUPS:   verdict: {s}", .{verdict});
}

pub fn processWindowsGuestOutputLine(self: *ElfState, line: []const u8, truncated: bool) void {
    if (line.len == 0) return;
    if (__process_xenia_fatal_condition_map.match(line)) |condition| {
        noteWindowsGuestCondition(self, condition, line);
        if (truncated) self.windows_guest_output_truncated_lines +|= 1;
        return;
    }
    const is_warning = __process_std.mem.indexOf(u8, line, "w> ") != null or
        __process_std.mem.indexOf(u8, line, "!> ") != null or
        __process_std.mem.indexOf(u8, line, "x> ") != null;
    if (is_warning) noteWindowsGuestWarning(self, line);
    if (truncated) self.windows_guest_output_truncated_lines +|= 1;
}

pub fn noteWindowsGuestOutput(self: *ElfState, bytes: []const u8) void {
    for (bytes) |byte| {
        if (byte == '\r') continue;
        if (byte == '\n') {
            processWindowsGuestOutputLine(
                self,
                self.windows_guest_output_line[0..self.windows_guest_output_line_len],
                self.windows_guest_output_line_truncated,
            );
            self.windows_guest_output_line_len = 0;
            self.windows_guest_output_line_truncated = false;
            continue;
        }
        if (self.windows_guest_output_line_len < self.windows_guest_output_line.len) {
            self.windows_guest_output_line[self.windows_guest_output_line_len] = byte;
            self.windows_guest_output_line_len += 1;
        } else {
            self.windows_guest_output_line_truncated = true;
        }
    }
}

pub fn flushWindowsGuestOutput(self: *ElfState) void {
    flushWindowsGuestOutputGovernors(self);
    if (self.windows_guest_output_line_len == 0) return;
    processWindowsGuestOutputLine(
        self,
        self.windows_guest_output_line[0..self.windows_guest_output_line_len],
        self.windows_guest_output_line_truncated,
    );
    self.windows_guest_output_line_len = 0;
    self.windows_guest_output_line_truncated = false;
}

pub fn logWindowsGuestFailurePointSummary(self: *const ElfState) void {
    reportGuestModuleLookups(self);
    // Below its threshold a condition is the design it names. XamState
    // commits three pages at 0x80D00000/10000/20000 without reserving
    // them on every start (src/xenia/kernel/xam/xam_state.cc), and
    // BaseHeap::AllocFixed says so once each; listing that as a FATAL
    // POINT SUMMARY ENTRY made Xenia's documented behaviour read as the
    // run's defect.
    for (self.windows_guest_failure_points[0..self.windows_guest_failure_point_count]) |entry| {
        const repeats: u64 = if (__process_xenia_fatal_condition_map.conditionForLabel(entry.labelText())) |condition| condition.repeats else 1;
        if (entry.occurrences >= repeats) continue;
        __process_log.info("PE64 EMULATOR DESIGN EVENTS: label={s} owner={s} occurrences={d} of the {d} that would make it a fatal point first_step={d} last_step={d} line={s}; below its threshold this is the emulator's documented behaviour, so it is reported here and not counted as a fatal point", .{
            entry.labelText(),
            entry.ownerText(),
            entry.occurrences,
            repeats,
            entry.first_step,
            entry.last_step,
            entry.lineText(),
        });
    }
    if (self.windows_fatal_point_events == 0 and self.windows_guest_output_truncated_lines == 0) return;
    __process_log.err("PE64 FATAL POINT SUMMARY: unique={d} known={d} warning_lines={d} informational={d} advisory={d} known_overflow={d} generic_overflow={d} truncated_lines={d} terminate_policy={} allowed={d} allow=[{s}] null_page_accesses={d} vfs_empty_name_faults={d}", .{
        self.windows_fatal_point_events,
        self.windows_guest_failure_point_count,
        self.windows_guest_warning_lines,
        self.windows_guest_informational_lines,
        self.windows_guest_advisory_lines,
        self.windows_guest_failure_point_overflow,
        self.windows_guest_warning_point_overflow,
        self.windows_guest_output_truncated_lines,
        self.windows_fatal_point_terminate,
        self.windows_fatal_point_allowed_events,
        self.windows_fatal_point_allow[0..self.windows_fatal_point_allow_len],
        self.guest_null_page_accesses,
        self.guest_vfs_empty_name_faults,
    });
    for (self.windows_guest_failure_points[0..self.windows_guest_failure_point_count]) |entry| {
        const entry_repeats: u64 = if (__process_xenia_fatal_condition_map.conditionForLabel(entry.labelText())) |condition| condition.repeats else 1;
        if (entry.occurrences < entry_repeats) continue;
        __process_log.err("PE64 FATAL POINT SUMMARY ENTRY: label={s} owner={s} occurrences={d} first_step={d} last_step={d} first_rip=0x{x} last_rip=0x{x} line={s}", .{
            entry.labelText(),
            entry.ownerText(),
            entry.occurrences,
            entry.first_step,
            entry.last_step,
            entry.first_rip,
            entry.last_rip,
            entry.lineText(),
        });
    }
    for (self.windows_guest_warning_points[0..self.windows_guest_warning_point_count]) |entry| {
        if (entry.advisory) {
            __process_log.warn("PE64 GUEST ADVISORY SUMMARY: occurrences={d} first_step={d} last_step={d} line={s}", .{
                entry.occurrences,
                entry.first_step,
                entry.last_step,
                entry.lineText(),
            });
        } else {
            __process_log.err("PE64 FATAL POINT SUMMARY WARNING: occurrences={d} first_step={d} last_step={d} line={s}", .{
                entry.occurrences,
                entry.first_step,
                entry.last_step,
                entry.lineText(),
            });
        }
    }
}

pub fn recordUnresolvedWindowsImport(self: *ElfState, stub: __process_WindowsImportStub) bool {
    const return_rip = process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp);
    const caller_rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*;
    for (self.windows_unresolved_imports[0..self.windows_unresolved_import_count]) |*record| {
        if (record.is_dynamic == stub.is_dynamic and
            __process_std.mem.eql(u8, record.dllName(), stub.dll_name) and
            __process_std.mem.eql(u8, record.functionName(), stub.function_name))
        {
            record.occurrences +|= 1;
            record.last_return_rip = return_rip;
            record.last_caller_rip = caller_rip;
            record.last_step = process_impl_lifecycle.observedExecutionSteps(self);
            return false;
        }
    }

    if (self.windows_unresolved_import_count >= self.windows_unresolved_imports.len) return false;
    var record = &self.windows_unresolved_imports[self.windows_unresolved_import_count];
    record.* = .{
        .is_dynamic = stub.is_dynamic,
        .stub_address = process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        .first_return_rip = return_rip,
        .first_caller_rip = caller_rip,
        .first_step = process_impl_lifecycle.observedExecutionSteps(self),
        .first_rsp = process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        .first_rcx = process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
        .first_rdx = process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
        .first_r8 = process_impl_lifecycle.guestContextField(self, "regs").*.r8,
        .first_r9 = process_impl_lifecycle.guestContextField(self, "regs").*.r9,
        .last_return_rip = return_rip,
        .last_caller_rip = caller_rip,
        .last_step = process_impl_lifecycle.observedExecutionSteps(self),
        .occurrences = 1,
    };
    // The whole-record assignment above intentionally clears the fixed
    // buffers as well. Copy the names afterwards; assigning the lengths
    // inside that literal would be overwritten by the zeroed arrays and
    // make every later occurrence look like a new symbol.
    record.dll_name_len = process_impl_guest_memory.copyUnresolvedImportName(&record.dll_name, stub.dll_name);
    record.function_name_len = process_impl_guest_memory.copyUnresolvedImportName(&record.function_name, stub.function_name);
    self.windows_unresolved_import_count += 1;
    return true;
}

pub fn noteWindowsLoadedModule(self: *ElfState, handle: u64, module_name: []const u8) void {
    if (handle == 0 or module_name.len == 0) return;
    for (self.windows_loaded_modules[0..self.windows_loaded_module_count]) |*entry| {
        if (entry.handle == handle) return;
    }
    if (self.windows_loaded_module_count >= self.windows_loaded_modules.len) {
        self.windows_loaded_module_overflow +|= 1;
        return;
    }
    var entry = &self.windows_loaded_modules[self.windows_loaded_module_count];
    entry.handle = handle;
    entry.name_len = __process_copyBoundedName(&entry.name, module_name);
    self.windows_loaded_module_count += 1;
}

pub fn windowsLoadedModuleName(self: *const ElfState, handle: u64) []const u8 {
    if (handle == 0) return "";
    for (self.windows_loaded_modules[0..self.windows_loaded_module_count]) |*entry| {
        if (entry.handle == handle) return entry.moduleName();
    }
    return "";
}

pub fn recordDynamicRefusal(
    records: []__process_WindowsDynamicRefusal,
    count: *u32,
    scope: []const u8,
    name: []const u8,
    is_gap: bool,
    caller_rip: u64,
) bool {
    for (records[0..count.*]) |*record| {
        if (__process_std.mem.eql(u8, record.nameText(), name) and __process_std.mem.eql(u8, record.scopeText(), scope)) {
            record.occurrences +|= 1;
            return false;
        }
    }
    if (count.* >= records.len) return false;
    var record = &records[count.*];
    record.scope_len = __process_copyBoundedName(&record.scope, scope);
    record.name_len = __process_copyBoundedName(&record.name, name);
    record.occurrences = 1;
    record.is_gap = is_gap;
    record.first_caller_rip = caller_rip;
    count.* += 1;
    return true;
}

pub fn noteWindowsModuleRefusal(
    self: *ElfState,
    api: []const u8,
    module_path: []const u8,
    reason: []const u8,
    is_gap: bool,
    fallback: []const u8,
    caller_rip: u64,
) void {
    self.windows_module_refusal_events +|= 1;
    if (is_gap) self.windows_module_refusal_gaps +|= 1;
    if (recordDynamicRefusal(
        &self.windows_module_refusals,
        &self.windows_module_refusal_count,
        api,
        module_path,
        is_gap,
        caller_rip,
    )) {
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        __process_log.info("PE64 Windows module refused: api={s} module='{s}' result=absent classification={s} reason={s} fallback={s} caller=0x{x} ({s})", .{
            api,
            module_path,
            if (is_gap) "GAP-no-package-models-this-library" else "deliberate-Rosette-policy",
            reason,
            fallback,
            caller_rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_rip, &caller_text),
        });
    }
}

pub fn noteWindowsProcAddressRefusal(
    self: *ElfState,
    dll_name: []const u8,
    function_name: []const u8,
    caller_rip: u64,
) void {
    self.windows_proc_refusal_events +|= 1;
    if (recordDynamicRefusal(
        &self.windows_proc_refusals,
        &self.windows_proc_refusal_count,
        dll_name,
        function_name,
        true,
        caller_rip,
    )) {
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        __process_log.info("PE64 Windows export refused: module='{s}' name={s} result=NULL classification=GAP-name-not-in-Rosette's-import-inventory caller=0x{x} ({s}); a stub here would have promised behaviour the call cannot deliver", .{
            if (dll_name.len == 0) "<unattributed>" else dll_name,
            function_name,
            caller_rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_rip, &caller_text),
        });
    }
}

pub fn noteWindowsProcAddressPolicyRefusal(
    self: *ElfState,
    dll_name: []const u8,
    function_name: []const u8,
    caller_rip: u64,
    fallback: []const u8,
    api_set_host: []const u8,
) void {
    self.windows_proc_refusal_events +|= 1;
    if (recordDynamicRefusal(
        &self.windows_proc_refusals,
        &self.windows_proc_refusal_count,
        dll_name,
        function_name,
        false,
        caller_rip,
    )) {
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        __process_log.info("PE64 Windows export refused: module='{s}'{s}{s} name={s} result=NULL classification=deliberate-Rosette-policy fallback={s} caller=0x{x} ({s}); the caller asked through GetProcAddress because the export is optional, and NULL sends it down the path named here", .{
            if (dll_name.len == 0) "<unattributed>" else dll_name,
            if (api_set_host.len != 0) " (official API-set contract, forwards to " else "",
            if (api_set_host.len != 0) api_set_host else "",
            function_name,
            fallback,
            caller_rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_rip, &caller_text),
        });
    }
}

pub fn noteWindowsCrtUnreadable(self: *ElfState, address: u64, length: u64) void {
    noteWindowsCrtUnreadableFrom(self, address, length, 0);
}

pub fn noteWindowsCrtUnreadableFrom(self: *ElfState, address: u64, length: u64, return_rip: u64) void {
    self.windows_crt_unreadable_pointers +|= 1;
    const occurrence = self.windows_crt_unreadable_pointers;
    if (occurrence == 1) self.windows_fatal_point_events +|= 1;
    // No address space holds a region this long, so the pointer was never
    // the question: the length was wrong before the call was made.
    const impossible_length = length > (@as(u64, 1) << 47);
    if (comptime !@import("builtin").is_test) {
        if (shouldReportWindowsPointOccurrence(occurrence)) {
            var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            var return_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            const slot_plus_one: u8 = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| @intCast(@min(slot + 1, 255)) else 0;
            __process_log.err("PE64 FATAL POINT: guest-condition label=crt-pointer-unreadable owner={s} occurrence={d} import={s} address=0x{x} length={d} (0x{x}) step={d} caller={s} return={s} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x} thread={s}; {s}", .{
                if (address == 0) "guest:caller" else if (impossible_length) "unknown:length-not-a-size" else "rosette:memory-model",
                occurrence,
                if (process_impl_lifecycle.guestContextField(self, "windows_current_import").*.len == 0) "<unattributed>" else process_impl_lifecycle.guestContextField(self, "windows_current_import").*,
                address,
                length,
                length,
                process_impl_lifecycle.observedExecutionSteps(self),
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*, &caller_text),
                if (return_rip == 0) "<unknown>" else process_impl_kernel_services.describeGuestAddressOrUnnamed(self, return_rip, &return_text),
                process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
                process_impl_lifecycle.guestContextField(self, "regs").*.r8,
                process_impl_lifecycle.guestContextField(self, "regs").*.r9,
                guestThreadLabel(self, slot_plus_one),
                if (address == 0)
                    "the caller passed NULL to a function that dereferences it, which is a crash on Windows; the caller is the defect"
                else if (impossible_length)
                    "no address space holds a region this long, so the length was wrong before the call was made. Disassemble the function at return= and follow how it built the length register: if every input to that arithmetic is ordinary guest state, Rosette executed the arithmetic wrongly; if one came back from an import, that import's answer is the defect"
                else
                    "Windows would read this address, so Rosette serving no region for it is the defect: find which allocation or file-mapping view should cover it in PE64 MEMORY CONTRACT and the view table",
            });
        }
    }
    terminateForWindowsFatalPoint(self, "crt-pointer-unreadable");
}

pub fn noteGetMessageIdleTurn(self: *ElfState, steps: u64) void {
    self.windows_get_message_idle_turns +|= 1;
    self.windows_get_message_idle_steps +|= steps;
}

pub fn noteWindowsUnreadableModuleName(
    self: *ElfState,
    api: []const u8,
    raw: []const u8,
    pointer: u64,
    caller_rip: u64,
) void {
    self.windows_unreadable_module_names +|= 1;
    if (self.windows_unreadable_module_names > 8) return;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var escaped: [64]u8 = undefined;
    var written: usize = 0;
    for (raw) |byte| {
        if (written + 4 > escaped.len) break;
        if (byte >= 0x20 and byte <= 0x7E) {
            escaped[written] = byte;
            written += 1;
        } else {
            _ = __process_std.fmt.bufPrint(escaped[written..], "\\x{x:0>2}", .{byte}) catch break;
            written += 4;
        }
    }
    __process_log.warn("PE64 Windows module name unreadable: api={s} pointer=0x{x} bytes='{s}' caller=0x{x} ({s}); the load is allowed rather than refused, because a refusal decided from bytes that are not a name would report a loadable library as absent", .{
        api,
        pointer,
        escaped[0..written],
        caller_rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_rip, &caller_text),
    });
}

pub fn firstFrameChainStages(self: *const ElfState) [__process_FIRST_FRAME_STAGE_COUNT]__process_ChainStage {
    const graphics = &self.windows_graphics;
    // A checkpoint outside a builder (or no checkpoint at all) is not
    // completion. Readiness requires the real CPU atlas outputs on return.
    // Normal text layout cannot revoke it; a later invalid return can.
    const font_observable = self.ui_evidence.font_returns != 0 or
        process_impl_kernel_services.guestMilestoneStageObservable(self, __process_ui_draw_evidence.font_rgba_symbol);
    // Samples that prove the title's own code has run at all, as opposed
    // to Xenia still preparing to run it.
    const title_running_samples = process_impl_kernel_services.frontierSamplesFor(self, .cpu_execution) +|
        process_impl_kernel_services.frontierSamplesFor(self, .kernel_services) +|
        process_impl_kernel_services.frontierSamplesFor(self, .gpu_command_processing) +|
        process_impl_kernel_services.frontierSamplesFor(self, .presentation);

    const stages = [__process_FIRST_FRAME_STAGE_COUNT]__process_ChainStage{
        .{
            .name = "host_window",
            .owner = "rosette:appkit-bridge",
            .met = graphics.window_ready,
            .evidence = "window_create_attempts",
            .value = graphics.window_create_attempts,
        },
        .{
            .name = "vulkan_instance",
            .owner = "rosette:vulkan-bridge",
            .met = graphics.instance_ready,
            .evidence = "instance_creations",
            .value = graphics.instance_creations,
        },
        .{
            .name = "vulkan_device",
            .owner = "rosette:vulkan-bridge",
            .met = graphics.device_ready,
            .evidence = "device_creations",
            .value = graphics.device_creations,
        },
        .{
            .name = "graphics_queue",
            .owner = "rosette:vulkan-bridge",
            .met = graphics.queue_ready,
            .evidence = "queue_acquisitions",
            .value = graphics.queue_acquisitions,
        },
        .{
            .name = "guest_surface",
            .owner = "xenia:ui-thread",
            .met = graphics.surface_ready,
            .evidence = "surface_creations",
            .value = graphics.surface_creations,
        },
        .{
            .name = "guest_swapchain",
            .owner = "xenia:ui-thread",
            .met = graphics.swapchain_ready,
            .evidence = "swapchain_creations",
            .value = graphics.swapchain_creations,
        },
        .{
            .name = "ui_font_atlas",
            .owner = "xenia:ui-thread",
            .met = self.ui_evidence.font_last_valid,
            .observable = font_observable,
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, __process_ui_draw_evidence.font_rgba_symbol),
            .evidence = "valid_cpu_RGBA_atlas_returns_not_GPU_upload",
            .value = self.ui_evidence.font_valid_returns,
        },
        .{
            // Include worker-local code-cache execution. A UI-thread
            // checkpoint alone misses the title even while it is running.
            .name = "title_code_running",
            .owner = "xenia:emulator-thread",
            .met = self.windows_title_code_fetches != 0 or title_running_samples != 0,
            .evidence = if (self.windows_title_code_fetches != 0) "title_worker_code_cache_fetches" else "frontier_samples_in_guest_code",
            .value = if (self.windows_title_code_fetches != 0) self.windows_title_code_fetches else title_running_samples,
        },
        .{
            .name = "window_paint_requested",
            .owner = "xenia:ui-thread",
            .met = self.windows_paint_requests != 0,
            .evidence = "paint_requests",
            .value = self.windows_paint_requests,
        },
        .{
            .name = "window_paint_delivered",
            .owner = "rosette:message-pump",
            .met = self.windows_paint_deliveries != 0,
            .evidence = "paint_deliveries",
            .value = self.windows_paint_deliveries,
        },
        .{
            .name = "command_recording",
            .owner = "xenia:ui-thread",
            .met = graphics.command_calls != 0,
            .evidence = "command_calls",
            .value = graphics.command_calls,
        },
        .{
            .name = "image_acquire",
            .owner = "xenia:ui-thread",
            .met = graphics.image_acquires != 0,
            .evidence = "image_acquires",
            .value = graphics.image_acquires,
        },
        .{
            .name = "queue_submit",
            .owner = "xenia:ui-thread",
            .met = graphics.queue_submits != 0,
            .evidence = "queue_submits",
            .value = graphics.queue_submits,
        },
        .{
            .name = "present",
            .owner = "xenia:ui-thread",
            .met = graphics.presents != 0,
            .evidence = "presents",
            .value = graphics.presents,
        },
    };

    return stages;
}

pub fn firstFrameWall(self: *const ElfState) ?__process_ChainStage {
    for (firstFrameChainStages(self)) |stage| {
        if (!stage.observable) continue;
        if (!stage.met) return stage;
    }
    return null;
}

pub fn reportFirstFrameChain(self: *const ElfState) void {
    const stages = firstFrameChainStages(self);
    var met_count: usize = 0;
    var observable_count: usize = 0;
    var first_unmet: ?usize = null;
    for (stages, 0..) |stage, index| {
        if (!stage.observable) continue;
        observable_count += 1;
        if (stage.met) {
            met_count += 1;
        } else if (first_unmet == null) {
            first_unmet = index;
        }
    }

    __process_log.info("PE64 FIRST FRAME CHAIN: {d}/{d} observable preconditions met ({d} unobservable); stages are ordered by dependency, so only the first unmet one is a finding. This chain measures transport and CPU readiness only: every stage of it can be met by a window showing one colour, and PE64 GUEST OUTPUT CHAIN is the one that asks whether a picture exists", .{
        met_count,
        observable_count,
        stages.len - observable_count,
    });
    for (stages, 0..) |stage, index| {
        var unobservable_text: [224]u8 = undefined;
        const marker: []const u8 = if (!stage.observable)
            __process_std.fmt.bufPrint(&unobservable_text, "unobservable ({s})", .{stage.unobservable_reason}) catch "unobservable"
        else if (stage.met)
            "met"
        else if (first_unmet != null and index == first_unmet.?)
            "UNMET <- the wall"
        else
            "unmet (downstream of the wall)";
        __process_log.info("PE64 FIRST FRAME CHAIN:   {s:<24} owner={s:<24} {s} ({s}={d})", .{
            stage.name,
            stage.owner,
            marker,
            stage.evidence,
            stage.value,
        });
    }

    var frontier_text: [320]u8 = undefined;
    __process_log.info("PE64 FIRST FRAME CHAIN:   guest frontier at exit: rip=0x{x} {s}", .{
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        process_impl_kernel_services.describeGuestFrontier(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &frontier_text),
    });
    if (self.guest_frontier_samples != 0) {
        __process_log.info("PE64 FIRST FRAME CHAIN:   frontier histogram over {d} checkpoint sample(s):", .{self.guest_frontier_samples});
        inline for (@typeInfo(__process_xenia_guest_frontier_map.Workload).@"enum".fields) |field| {
            const workload: __process_xenia_guest_frontier_map.Workload = @enumFromInt(field.value);
            const samples = process_impl_kernel_services.frontierSamplesFor(self, workload);
            if (samples != 0) {
                __process_log.info("PE64 FIRST FRAME CHAIN:     {s:<26} {d} sample(s) ({d}%) bounded={}", .{
                    workload.label(),
                    samples,
                    samples * 100 / self.guest_frontier_samples,
                    workload.isBoundedComputation(),
                });
            }
        }
    }
    if (first_unmet) |index| {
        __process_log.info("PE64 FIRST FRAME CHAIN:   verdict: '{s}' is the earliest unmet precondition and it belongs to {s}", .{
            stages[index].name,
            stages[index].owner,
        });
    } else {
        __process_log.info("PE64 FIRST FRAME CHAIN:   verdict: every observable precondition for a first frame was met; unobservable stages are not completion proof", .{});
    }
    reportUiDrawEvidence(self);
}

pub fn reportUiDrawEvidence(self: *const ElfState) void {
    const e = &self.ui_evidence;
    __process_log.info("PE64 UI DRAW EVIDENCE: CPU atlas returns(valid/invalid/unreadable)={d}/{d}/{d} latest_valid={} pixels=0x{x} extent={d}x{d}; current text drawing is not atlas rebuilding and these bytes are not GPU-upload proof", .{
        e.font_valid_returns, e.font_invalid_returns, e.font_unreadable_returns,
        e.font_last_valid,    e.font_pixels,          e.font_width,
        e.font_height,
    });
    __process_log.info("PE64 UI DRAW EVIDENCE: lists(entries/empty/invalid/unreadable)={d}/{d}/{d}/{d} latest(valid/lists/vertices/indices)={}/{d}/{d}/{d} display_pos={d},{d} display_size={d}x{d} framebuffer_scale={d},{d} owner_viewport=0x{x}", .{
        e.lists_entries,        e.lists_empty,          e.lists_invalid,   e.lists_unreadable,
        e.draw_data_valid,      e.list_count,           e.vertex_count,    e.index_count,
        e.display_pos[0],       e.display_pos[1],       e.display_size[0], e.display_size[1],
        e.framebuffer_scale[0], e.framebuffer_scale[1], e.owner_viewport,
    });
    __process_log.info("PE64 UI DRAW EVIDENCE: raw(first_list/cmd/vertex/readable)=(0x{x}/0x{x}/0x{x}/{}) raw(counts/cmd/vertex)={d}/{d} raw_clip={d},{d},{d},{d} raw_vertex={d},{d}", .{
        e.first_list,      e.first_cmd,        e.first_vertex,        e.raw_buffers_readable,
        e.raw_cmd_count,   e.raw_vertex_count, e.raw_cmd_clip[0],     e.raw_cmd_clip[1],
        e.raw_cmd_clip[2], e.raw_cmd_clip[3],  e.raw_first_vertex[0], e.raw_first_vertex[1],
    });
    __process_log.info("PE64 UI DRAW EVIDENCE: raw-internals(readable/list_flags/shared_data/clip_stack_size)={}/0x{x}/0x{x}/{d} cmd_header_clip={d},{d},{d},{d} shared_fullscreen_clip={d},{d},{d},{d}; this separates bad ImGui state from a bridge-side scissor mutation", .{
        e.raw_list_internals_readable,
        e.raw_list_flags,
        e.raw_shared_data,
        e.raw_clip_stack_size,
        e.raw_cmd_header_clip[0],
        e.raw_cmd_header_clip[1],
        e.raw_cmd_header_clip[2],
        e.raw_cmd_header_clip[3],
        e.raw_shared_clip[0],
        e.raw_shared_clip[1],
        e.raw_shared_clip[2],
        e.raw_shared_clip[3],
    });
    __process_log.info("PE64 UI DRAW EVIDENCE: clip-stack(data/readable/first)=(0x{x}/{}) {d},{d},{d},{d}; compare this guest-owned push with the command header", .{
        e.raw_clip_stack_data,
        e.raw_clip_stack_first_readable,
        e.raw_clip_stack_first[0],
        e.raw_clip_stack_first[1],
        e.raw_clip_stack_first[2],
        e.raw_clip_stack_first[3],
    });
    __process_log.info("PE64 UI DRAW EVIDENCE: draw(entries/empty/invalid_clip/unreadable)={d}/{d}/{d}/{d} latest(primitive/count/texture/scissor)={d}/{d}/0x{x}/{} clip={d},{d},{d},{d}", .{
        e.draw_entries, e.draw_empty, e.draw_invalid_clip, e.draw_unreadable,
        e.primitive,    e.draw_count, e.texture,           e.scissor_enabled,
        e.clip[0],      e.clip[1],    e.clip[2],           e.clip[3],
    });
    __process_log.info("PE64 UI DRAW EVIDENCE: pipeline returns(true/false)={d}/{d} scissor returns(true/false/unreadable_outputs)={d}/{d}/{d} latest_valid_rect={d},{d},{d},{d}; zero entries may be unresolved or inlined, see qualified PE64 GUEST MILESTONES; no Vulkan draw means an upstream exit, not a bridge rejection", .{
        e.pipeline_true,   e.pipeline_false,  e.scissor_true,    e.scissor_false,   e.scissor_unreadable,
        e.scissor_rect[0], e.scissor_rect[1], e.scissor_rect[2], e.scissor_rect[3],
    });
}

pub fn witnessLabel(comptime milestone: []const u8) []const u8 {
    return comptime blk: {
        var label: []const u8 = "";
        for (__process_xenia_kernel_shim_map.witnesses) |witness| {
            if (!__process_std.mem.eql(u8, witness.milestone, milestone)) continue;
            label = if (label.len == 0)
                witness.export_name
            else
                label ++ "+" ++ witness.export_name;
        }
        break :blk label;
    };
}

pub fn guestStageMet(self: *const ElfState, comptime milestone: []const u8) bool {
    if (process_impl_kernel_services.guestMilestoneStageHits(self, milestone) != 0) return true;
    return self.guest_kernel_calls.witnessHitsFor(milestone) != 0;
}

pub fn guestMilestoneStageHitsAny(
    self: *const ElfState,
    comptime primary: []const u8,
    comptime alternate: []const u8,
) u64 {
    return process_impl_kernel_services.guestMilestoneStageHits(self, primary) +| process_impl_kernel_services.guestMilestoneStageHits(self, alternate);
}

pub fn guestStageMetAny(
    self: *const ElfState,
    comptime primary: []const u8,
    comptime alternate: []const u8,
) bool {
    if (guestMilestoneStageHitsAny(self, primary, alternate) != 0) return true;
    return self.guest_kernel_calls.witnessHitsFor(primary) != 0 or
        self.guest_kernel_calls.witnessHitsFor(alternate) != 0;
}

pub fn guestMilestoneStageObservableAny(
    self: *const ElfState,
    comptime primary: []const u8,
    comptime alternate: []const u8,
) bool {
    return process_impl_kernel_services.guestMilestoneStageObservable(self, primary) or
        process_impl_kernel_services.guestMilestoneStageObservable(self, alternate);
}

pub fn guestMilestoneStageUnobservableReasonAny(
    self: *const ElfState,
    comptime primary: []const u8,
    comptime alternate: []const u8,
) []const u8 {
    if (guestMilestoneStageObservableAny(self, primary, alternate)) return "observable";
    if (!process_impl_kernel_services.guestMilestoneArmed(self, primary) and !process_impl_kernel_services.guestMilestoneArmed(self, alternate)) {
        return "this image does not name the base or Vulkan virtual-override symbol";
    }
    if (!process_impl_kernel_services.guestMilestoneArmed(self, primary)) return process_impl_kernel_services.guestMilestoneUnobservableReason(self, alternate);
    return process_impl_kernel_services.guestMilestoneUnobservableReason(self, primary);
}

pub fn guestOutputChainStages(self: *const ElfState) [__process_GUEST_OUTPUT_STAGE_COUNT]__process_ChainStage {
    const graphics = &self.windows_graphics;
    const m = struct {
        const launch = "_ZN2xe8Emulator14CompleteLaunchERKNSt10filesystem7__cxx114pathESt17basic_string_viewIcSt11char_traitsIcEE";
        const thread = "_ZN2xe6kernel7XThread7ExecuteEv";
        const backend = "_ZN2xe3gpu6vulkan20VulkanGraphicsSystem5SetupEPNS_3cpu9ProcessorEPNS_6kernel11KernelStateEPNS_2ui18WindowedAppContextEb";
        const vblank = "_ZN2xe3gpu14GraphicsSystem10MarkVblankEv";
        const cp_init = "_ZN2xe3gpu16CommandProcessor10InitializeEv";
        const cp_thread = "_ZN2xe3gpu16CommandProcessor16WorkerThreadMainEv";
        const video_mode = "_ZN2xe6kernel8xboxkrnl16VdQueryVideoModeEPNS0_12X_VIDEO_MODEEb";
        const interrupt = "_ZN2xe3gpu14GraphicsSystem20SetInterruptCallbackEjj";
        const ring = "_ZN2xe3gpu14GraphicsSystem20InitializeRingBufferEjj";
        const read_thunk = "_ZN2xe3gpu14GraphicsSystem17ReadRegisterThunkEPvPS1_j";
        const write_thunk = "_ZN2xe3gpu14GraphicsSystem18WriteRegisterThunkEPvPS1_jj";
        const write_pointer = "_ZN2xe3gpu16CommandProcessor18UpdateWritePointerEj";
        const primary = "_ZN2xe3gpu16CommandProcessor20ExecutePrimaryBufferEjj";
        const packet = "_ZN2xe3gpu16CommandProcessor18ExecutePacketType3Ej";
        const primary_vulkan = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor20ExecutePrimaryBufferEjj";
        const packet_vulkan = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType3Ej";
        const swap = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor9IssueSwapEjjj";
        const refresh = "_ZN2xe2ui9Presenter18RefreshGuestOutputEjjjjSt8functionIFbRNS1_25GuestOutputRefreshContextEEE";
        const paint = "_ZN2xe2ui9Presenter17PaintFromUIThreadEb";
    };
    const ring_when_unmet: []const u8 = if (process_impl_kernel_services.guestMilestoneHitsNamed(self, m.write_pointer) != 0)
        "the title handed Xenia a ring and direct MMIO reached UpdateWritePointer, but the GPU worker never entered ExecutePrimaryBuffer (base or Vulkan override). No interpreted access violation was needed; inspect the write-pointer wake path (NtSetEventBoostPriority) and PE64 GUEST THREADS for the GPU Commands wait"
    else if (process_impl_kernel_services.guestMilestoneHitsNamed(self, m.write_thunk) != 0 or process_impl_kernel_services.guestMilestoneHitsNamed(self, m.read_thunk) != 0)
        "the title reached Xenia's graphics register callbacks but no UpdateWritePointer was observed. Compare the direct MMIO milestone counts with PE64 GUEST ACCESS VIOLATIONS to find the missing register handoff"
    else
        "the ring exists but ExecutePrimaryBuffer has not run. Check whether UpdateWritePointer was observed through direct MMIO callbacks or through the protected-page fault chain; the first zero in PE64 GUEST ACCESS VIOLATIONS identifies the missing handoff";

    const packet_headers = process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3gpu6vulkan22VulkanCommandProcessor13ExecutePacketEv");
    const register_packets = process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType0Ej") +|
        process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType1Ej");
    const type3_handler_entries = gpuType3HandlerEntries(self);
    const swap_when_unmet: []const u8 = if (self.gpu_indirect_buffers_seen != 0 and
        self.gpu_indirect_draw_packets == 0 and self.gpu_ring_draw_packets == 0)
        "the title has not asked for its front buffer to be shown, and PE64 GPU RING says why that is expected: the indirect buffers it submitted carry no DRAW_INDX and no XE_SWAP, so it has initialised the device and set state but has not drawn. VdSwap in PE64 GUEST KERNEL CALLS is the independent witness and it cannot be inlined away"
    else
        "the title has drawn, if it has drawn, but never asked for its front buffer to be shown. A black window is still the expected outcome from here; VdSwap in PE64 GUEST KERNEL CALLS is the independent witness and it cannot be inlined away";
    const ring_pm4_when_unmet: []const u8 = if (self.gpu_ring_alias_mismatches != 0)
        "the title's virtual view of its ring and Xenia's physical view of the same pages disagree, so the GPU reads a different page from the one the title writes. That is Rosette's file-mapping aliasing; PE64 GPU RING shows the windows"
    else if (self.gpu_ring_type3_packets != 0)
        "Rosette's decode of the ring windows found type 3 packets and neither Xenia's type 3 dispatcher nor any of its opcode handlers ran; PE64 GPU RING lists them, and the disagreement is about where the command processor's reader starts"
    else if (self.gpu_ring_dwords_decoded != 0 and self.gpu_ring_zero_dwords == self.gpu_ring_dwords_decoded)
        "every dword the write pointer covered is zero, and Xenia skips a zero header without calling any executor. The title moved the write pointer over memory that holds no commands; PE64 GPU RING shows the windows and the alias checks that clear the mapping"
    else if (register_packets != 0 or self.gpu_ring_type0_packets != 0)
        "the ring carried register writes (type 0/1) and no type 3 command. The title is configuring the GPU without yet asking it to do anything; PE64 GPU RING shows the windows"
    else if (packet_headers != 0)
        "the command processor read packet headers and none reached an executor, so every header was 0, 0x0BADF00D or 0xCDCDCDCD; PE64 GPU RING shows the dwords"
    else
        "the ring advanced but no packet executor ran. PE64 GPU RING decodes the dwords each write-pointer update covered, and its Xenia executed line says which kind of header Xenia read";

    return [__process_GUEST_OUTPUT_STAGE_COUNT]__process_ChainStage{
        .{
            .name = "vulkan_backend_chosen",
            .owner = "xenia:emulator",
            .met = guestStageMet(self, m.backend),
            .evidence = "VulkanGraphicsSystem_Setup_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.backend),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.backend),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.backend),
            .witness = witnessLabel(m.backend),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.backend),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.backend),
            .when_unmet = "Xenia never built a Vulkan graphics system. Either --gpu selected another backend, or Setup threw before its first instruction. Read the launcher's argument line and PE64 DYNAMIC REFUSALS: a refused D3D12.dll is expected and harmless, a refused vulkan-1.dll is not",
        },
        .{
            .name = "gpu_command_processor_up",
            .owner = "xenia:emulator",
            .met = guestStageMet(self, m.cp_init),
            .evidence = "CommandProcessor_Initialize_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.cp_init),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.cp_init),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.cp_init),
            .witness = witnessLabel(m.cp_init),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.cp_init),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.cp_init),
            .when_unmet = "the graphics system exists but its command processor did not come up, so there is nothing on the other end of the ring. This is Xenia's own bring-up and no title action can affect it; read the Vulkan device and queue rows of the first-frame chain, because Initialize creates its command pools from them",
        },
        .{
            .name = "gpu_thread_reading",
            .owner = "xenia:gpu-thread",
            .met = guestStageMet(self, m.cp_thread),
            .evidence = "CommandProcessor_WorkerThreadMain_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.cp_thread),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.cp_thread),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.cp_thread),
            .witness = witnessLabel(m.cp_thread),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.cp_thread),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.cp_thread),
            .when_unmet = "the command processor was built but its worker thread never entered the read loop. That is a thread that did not start or a wait that did not return; PE64 GUEST THREADS names it and says what it is blocked on",
        },
        .{
            // A title that waits for vertical blank before drawing makes
            // no progress at all while this is zero, and the run looks
            // like a GPU fault instead of a stopped clock.
            .name = "display_clock_ticking",
            .owner = "xenia:emulator",
            .met = guestStageMet(self, m.vblank),
            // Which of the two witnesses the count came from, because
            // `MarkVblank_entries=0` alongside a met stage would read as
            // a contradiction rather than as an inlined body.
            .evidence = if (process_impl_kernel_services.guestMilestoneInlinedAway(self, m.vblank))
                "EmulateCPInterruptDPC_entries (MarkVblank was inlined away)"
            else
                "MarkVblank_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.vblank),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.vblank),
            .unobservable_reason = if (process_impl_kernel_services.guestMilestoneInlinedAway(self, m.vblank))
                "MarkVblank was inlined into its callers and KernelState::EmulateCPInterruptDPC, its witness, is not in this image either"
            else
                process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.vblank),
            .when_unmet = "the emulated display clock is stopped. Read PE64 STEP BUDGET's guest_clock= first: a guest millisecond that costs far more than a real one starves the frame limiter, and that is what this looked like before the clock moved to the host monotonic source",
        },
        .{
            .name = "emulator_launched",
            .owner = "xenia:emulator",
            .met = guestStageMet(self, m.launch),
            .evidence = "CompleteLaunch_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.launch),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.launch),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.launch),
            .witness = witnessLabel(m.launch),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.launch),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.launch),
            .when_unmet = "the module was never accepted, so no title thread was ever created. This is a loading failure and not a graphics one; read PE64 AUDIT INPUTS and the XEX/ISO lines, because a title that cannot be read cannot be launched",
        },
        .{
            .name = "title_thread_started",
            .owner = "guest-title",
            .met = guestStageMet(self, m.thread),
            .evidence = "XThread_Execute_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.thread),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.thread),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.thread),
            .witness = witnessLabel(m.thread),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.thread),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.thread),
            .when_unmet = "no guest thread ever began running translated PowerPC. Everything below this line is unreachable by definition; the investigation is in the loader, not in graphics",
        },
        .{
            .name = "title_queried_video_mode",
            .owner = "guest-title",
            .met = guestStageMet(self, m.video_mode),
            .evidence = "VdQueryVideoMode_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.video_mode),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.video_mode),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.video_mode),
            .witness = witnessLabel(m.video_mode),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.video_mode),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.video_mode),
            .when_unmet = "the title is running but has not asked the kernel about the display. Read PE64 GUEST KERNEL CALLS: it names every export the title HAS called, in order, and the boot phase they place it in. A title with thousands of calls and no Vd* is stuck before D3D device creation, and the last export it called says where",
        },
        .{
            .name = "title_took_gpu_interrupt",
            .owner = "guest-title",
            .met = guestStageMet(self, m.interrupt),
            .evidence = "SetInterruptCallback_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.interrupt),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.interrupt),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.interrupt),
            .witness = witnessLabel(m.interrupt),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.interrupt),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.interrupt),
            .when_unmet = "the title has not registered a GPU interrupt handler, so every vertical blank the emulator raises is delivered to nobody. A title that waits on vblank before its first draw cannot leave this state on its own",
        },
        .{
            .name = "title_gave_gpu_a_ring",
            .owner = "guest-title",
            .met = guestStageMet(self, m.ring),
            .evidence = "InitializeRingBuffer_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.ring),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.ring),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.ring),
            .witness = witnessLabel(m.ring),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.ring),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.ring),
            .when_unmet = "the title has not handed Xenia a command ring. Nothing the command processor does can produce a frame until it does; the ring's address comes from the title's own physical allocation, so a memory failure upstream presents exactly like this",
        },
        .{
            .name = "ring_carried_work",
            .owner = "xenia:gpu-thread",
            .met = guestStageMetAny(self, m.primary, m.primary_vulkan),
            .evidence = "ExecutePrimaryBuffer_entries (base/Vulkan override)",
            .value = guestMilestoneStageHitsAny(self, m.primary, m.primary_vulkan),
            .observable = guestMilestoneStageObservableAny(self, m.primary, m.primary_vulkan),
            .unobservable_reason = guestMilestoneStageUnobservableReasonAny(self, m.primary, m.primary_vulkan),
            .witness = witnessLabel(m.primary),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.primary) +| self.guest_kernel_calls.witnessHitsFor(m.primary_vulkan),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.primary) or self.guest_kernel_calls.witnessArmedFor(m.primary_vulkan),
            .when_unmet = ring_when_unmet,
        },
        .{
            .name = "ring_carried_pm4",
            .owner = "xenia:gpu-thread",
            // The dispatcher is inlined into ExecutePacket in this build;
            // a handler only a type 3 packet reaches is the same fact.
            .met = guestStageMetAny(self, m.packet, m.packet_vulkan) or type3_handler_entries != 0,
            .evidence = "ExecutePacketType3_entries (base/Vulkan override) + type 3 opcode handler entries",
            .value = guestMilestoneStageHitsAny(self, m.packet, m.packet_vulkan) +| type3_handler_entries,
            .observable = guestMilestoneStageObservableAny(self, m.packet, m.packet_vulkan) or type3_handler_entries != 0,
            .unobservable_reason = guestMilestoneStageUnobservableReasonAny(self, m.packet, m.packet_vulkan),
            .witness = witnessLabel(m.packet),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.packet) +| self.guest_kernel_calls.witnessHitsFor(m.packet_vulkan),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.packet) or self.guest_kernel_calls.witnessArmedFor(m.packet_vulkan),
            .when_unmet = ring_pm4_when_unmet,
        },
        .{
            .name = "title_requested_swap",
            .owner = "guest-title",
            .met = guestStageMet(self, m.swap),
            .evidence = "IssueSwap_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.swap),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.swap),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.swap),
            .witness = witnessLabel(m.swap),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.swap),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.swap),
            .when_unmet = swap_when_unmet,
        },
        .{
            .name = "guest_output_published",
            .owner = "xenia:gpu-thread",
            .met = guestStageMet(self, m.refresh),
            .evidence = "RefreshGuestOutput_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.refresh),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.refresh),
            .unobservable_reason = process_impl_kernel_services.guestMilestoneUnobservableReason(self, m.refresh),
            .witness = witnessLabel(m.refresh),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.refresh),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.refresh),
            .when_unmet = "a swap was requested but no finished frame reached the presenter's mailbox. This is the one stage between the title's request and Rosette's window, and it is Xenia's; read the mailbox line below for which end is waiting",
        },
        .{
            // Rosette's own evidence again from here. A draw, a dispatch
            // or a copy is the only Vulkan traffic that can carry a
            // picture; a render pass that clears and ends carries a
            // colour.
            .name = "guest_present_carried_content",
            .owner = "rosette:vulkan-bridge",
            .met = graphics.guest_presents_with_content != 0,
            .evidence = "guest_swapchain_presents_with_content",
            .value = graphics.guest_presents_with_content,
            .when_unmet = "frames reached Rosette's bridge but none of them carried a draw, a dispatch or a copy. A render pass that clears and ends is a colour, not a picture; this is the stage that separates the two and it is the only one that can",
        },
        .{
            // One paint is what Xenia does when nothing asks for a
            // second. After the first frame the presenter repaints only
            // when guest output is refreshed or a UI drawer asks, so a
            // count of one here is not a stall - it is the honest number
            // of frames the title requested.
            .name = "paints_are_repeating",
            .owner = "xenia:ui-thread",
            .met = process_impl_kernel_services.guestMilestoneStageHits(self, m.paint) > 1,
            .evidence = "PaintFromUIThread_entries",
            .value = process_impl_kernel_services.guestMilestoneStageHits(self, m.paint),
            .observable = process_impl_kernel_services.guestMilestoneStageObservable(self, m.paint),
            .when_unmet = "the window painted at most once. After the first frame Xenia paints only when guest output is refreshed or a UI drawer asks, so this is a consequence of the stages above and never a finding of its own",
        },
    };
}

pub fn guestOutputWall(self: *const ElfState) ?__process_ChainStage {
    for (guestOutputChainStages(self)) |stage| {
        if (!stage.observable) continue;
        if (!stage.met) return stage;
    }
    return null;
}

pub fn reportGuestOutputChain(self: *const ElfState) void {
    const stages = guestOutputChainStages(self);
    var met_count: usize = 0;
    var observable_count: usize = 0;
    var first_unmet: ?usize = null;
    for (stages, 0..) |stage, index| {
        if (!stage.observable) continue;
        observable_count += 1;
        if (stage.met) {
            met_count += 1;
        } else if (first_unmet == null) {
            first_unmet = index;
        }
    }
    if (observable_count == 0) {
        __process_log.info("PE64 GUEST OUTPUT CHAIN: not observable in this run: {d} of {d} milestone symbols resolved against the image, so every stage would read unmet whether or not the guest reached it", .{
            self.guest_milestones_resolved,
            __process_GUEST_MILESTONE_COUNT,
        });
        return;
    }
    __process_log.info("PE64 GUEST OUTPUT CHAIN: {d}/{d} observable stages met ({d} not observable in this image); this chain asks whether the title's picture exists, which the first-frame chain cannot: every stage of that one is met by a window showing a single colour", .{
        met_count,
        observable_count,
        stages.len - observable_count,
    });
    for (stages, 0..) |stage, index| {
        const marker: []const u8 = if (!stage.observable)
            "unobservable (this image does not name the symbol)"
        else if (stage.met)
            "met"
        else if (first_unmet != null and index == first_unmet.?)
            "UNMET <- the wall"
        else
            "unmet (downstream of the wall)";
        __process_log.info("PE64 GUEST OUTPUT CHAIN:   {s:<24} owner={s:<22} {s} ({s}={d})", .{
            stage.name,
            stage.owner,
            marker,
            stage.evidence,
            stage.value,
        });
        if (__process_std.mem.eql(u8, stage.name, "guest_present_carried_content")) {
            __process_log.info("PE64 GUEST OUTPUT CHAIN:     forwarder attribution: guest_acquired_target={d} guest_content={d} guest_clear_only={d} guest_without_target={d} guest_without_write={d} command_shape(draw/dispatch/transfer/other)={d}/{d}/{d}/{d}; offscreen transfers never satisfy this stage", .{
                self.windows_graphics.guest_presents_with_target,
                self.windows_graphics.guest_presents_with_content,
                self.windows_graphics.guest_presents_clear_only,
                self.windows_graphics.guest_presents_without_target,
                self.windows_graphics.guest_presents_without_write,
                self.windows_graphics.draw_commands,
                self.windows_graphics.dispatch_commands,
                self.windows_graphics.transfer_commands,
                self.windows_graphics.command_calls -| self.windows_graphics.draw_commands -| self.windows_graphics.dispatch_commands -| self.windows_graphics.transfer_commands,
            });
        }
        // The second witness, from the guest side of the boundary. It is
        // printed for every stage that has one, met or not, because the
        // interesting cases are the ones where the two disagree.
        if (stage.witness.len != 0) {
            if (!stage.witness_armed) {
                __process_log.info("PE64 GUEST OUTPUT CHAIN:     witness {s}: NOT ARMED - this image does not name the export shim, so nothing here can see whether the title called it", .{
                    stage.witness,
                });
            } else if (stage.witness_value != 0 and stage.value == 0) {
                __process_log.info("PE64 GUEST OUTPUT CHAIN:     witness {s}={d} while its Xenia-side implementation reads 0: the title DID call this, and the call between the shim and the implementation was inlined. The implementation's zero measures the build, not the run", .{
                    stage.witness,
                    stage.witness_value,
                });
            } else if (stage.witness_value == 0 and stage.value != 0) {
                __process_log.info("PE64 GUEST OUTPUT CHAIN:     witness {s}=0 while the implementation reads {d}: Xenia reached this on its own and the title never asked for it, so the count is not evidence of the title's progress", .{
                    stage.witness,
                    stage.value,
                });
            } else {
                __process_log.info("PE64 GUEST OUTPUT CHAIN:     witness {s}={d} (the guest-side export shim; nothing inside the image branches to it, so its count is the title's own act)", .{
                    stage.witness,
                    stage.witness_value,
                });
            }
        }
        // What to do about it. Printed for every unmet stage rather than
        // only the wall: a reader who has already fixed the wall wants to
        // know what the next one will ask of them, and `unmet (downstream
        // of the wall)` has said nothing for five runs.
        if (stage.observable and !stage.met and stage.when_unmet.len != 0) {
            __process_log.info("PE64 GUEST OUTPUT CHAIN:     -> {s}", .{stage.when_unmet});
        }
    }
    // The mailbox has two ends and they fail differently. A painter that
    // polls an empty mailbox is waiting for the title; a producer that
    // fills one nobody reads is a dropped frame. `ConsumeGuestOutput` is
    // entered on every paint whether or not a frame was there, so its
    // entry count is a poll count and never belonged in the chain as a
    // stage - it read `met` on the 2026-09-12 run while the producer had
    // run zero times.
    const polls = process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe2ui9Presenter18ConsumeGuestOutputERjPNS1_21GuestOutputPropertiesEPNS1_22GuestOutputPaintConfigE");
    const publishes = process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe2ui9Presenter18RefreshGuestOutputEjjjjSt8functionIFbRNS1_25GuestOutputRefreshContextEEE");
    if (polls != 0 or publishes != 0) {
        __process_log.info("PE64 GUEST OUTPUT CHAIN:   guest output mailbox: the painter polled it {d} time(s), the GPU thread filled it {d} time(s); a poll is not a frame, and more polls than fills is the painter waiting on the title rather than a frame being dropped", .{
            polls,
            publishes,
        });
    }
    reportFrontBuffer(self);
    reportFrameCost(self);
    if (first_unmet) |index| {
        __process_log.info("PE64 GUEST OUTPUT CHAIN:   verdict: '{s}' is the earliest stage the title has not reached and it belongs to {s}", .{
            stages[index].name,
            stages[index].owner,
        });
        // A wall the title owns used to end the report. It is the case
        // that needs the most saying, because "the title has not done X"
        // is not a diagnosis until something says what it did instead -
        // and the kernel census is the only thing in Rosette that can.
        if (__process_std.mem.eql(u8, stages[index].owner, "guest-title")) {
            const census = &self.guest_kernel_calls;
            if (census.armed == 0) {
                __process_log.info("PE64 GUEST OUTPUT CHAIN:   the wall belongs to the title and no kernel export shim is armed, so nothing in this run can say what the title did instead. That is the gap to close before this verdict can be acted on", .{});
            } else if (census.distinct_entered == 0) {
                __process_log.info("PE64 GUEST OUTPUT CHAIN:   the wall belongs to the title, and the title has not made one kernel call out of {d} armed export(s). It is running translated code that has never reached an import thunk; read PE64 GUEST CODE PROGRESS for whether that code is advancing", .{
                    census.armed,
                });
            } else {
                __process_log.info("PE64 GUEST OUTPUT CHAIN:   the wall belongs to the title, which has made {d} call(s) across {d} distinct kernel export(s) and reached boot phase '{s}'. PE64 GUEST KERNEL CALLS below lists them in the order it first made them; the last row of that list is where it stopped asking for new things", .{
                    census.total_calls,
                    census.distinct_entered,
                    census.furthest_phase.label(),
                });
                if (census.slotAt(census.last_slot)) |latest| {
                    __process_log.info("PE64 GUEST OUTPUT CHAIN:   its most recent kernel call of any kind was {s} at step {d}", .{
                        latest.export_name,
                        census.last_step,
                    });
                }
            }
            reportGuestTitleThreadForWall(self);
        }
    } else {
        __process_log.info("PE64 GUEST OUTPUT CHAIN:   verdict: the title produced output and the window is repainting it", .{});
    }
}

pub fn vblankWitnessName(self: *const ElfState) []const u8 {
    const vblank = "_ZN2xe3gpu14GraphicsSystem10MarkVblankEv";
    if (!process_impl_kernel_services.guestMilestoneArmed(self, vblank)) return "no witness: this image names neither symbol";
    if (!process_impl_kernel_services.guestMilestoneInlinedAway(self, vblank)) return "GraphicsSystem::MarkVblank";
    const proxy = __process_xenia_guest_milestone_map.inlineProxyOf(vblank);
    if (proxy.len != 0 and process_impl_kernel_services.guestMilestoneArmed(self, proxy)) {
        return "KernelState::EmulateCPInterruptDPC, because MarkVblank was inlined into the frame limiter";
    }
    return "no witness: MarkVblank was inlined away and its stand-in is not in this image";
}

pub fn describeWindowsWaitTarget(self: *const ElfState, handle: u64, buffer: []u8) []const u8 {
    if (handle == 0) return "";
    const interpreted = process_impl_run_reporting.totalInterpretedSteps(self);
    for (self.windows_guest_threads) |*candidate| {
        if (candidate.status == .vacant) continue;
        if (candidate.handle != handle) continue;
        const share = if (interpreted == 0) 0 else @divTrunc(process_impl_lifecycle.windowsGuestThreadSteps(self, candidate) *| 100, interpreted);
        return __process_std.fmt.bufPrint(buffer, " (thread '{s}' {s}, {d}% of the run)", .{
            if (candidate.name_len != 0) candidate.nameText() else "unnamed by the guest",
            @tagName(candidate.status),
            share,
        }) catch "";
    }
    return "";
}

pub fn windowsJoinVerdict(self: *const ElfState, handle: u64) []const u8 {
    if (handle == 0) return "not_thread_join";
    var current = handle;
    var seen: [8]u64 = [_]u64{0} ** 8;
    var depth: usize = 0;
    while (depth < seen.len) : (depth += 1) {
        for (seen[0..depth]) |previous| {
            if (previous == current) return "join_cycle";
        }
        seen[depth] = current;
        const index = process_impl_windows_sync.windowsGuestThreadIndex(self, current) orelse return if (depth == 0) "not_thread_join" else "chain_to_non_thread";
        const thread = &self.windows_guest_threads[index];
        switch (thread.status) {
            .completed, .failed => return if (depth == 0) "target_completed" else "chain_reaches_completed",
            .pending, .runnable, .running => return if (depth == 0) "active_target" else "chain_reaches_active_target",
            .blocked => {
                if (thread.blocked_wait_handle == 0) return if (depth == 0) "target_blocked" else "chain_reaches_blocked_target";
                current = thread.blocked_wait_handle;
            },
            .vacant => return "not_thread_join",
        }
    }
    return "join_chain_too_deep";
}

pub fn readGuestCodeForSpin(context: *const anyopaque, address: u64, out: []u8) usize {
    const self: *const ElfState = @ptrCast(@alignCast(context));
    if (process_impl_guest_memory.addrToOffset(self, address)) |offset| {
        if (offset >= self.mem.len) return 0;
        const available = @min(out.len, self.mem.len - offset);
        process_impl_block_jit.copyGuestCode(self, out[0..available], self.mem[offset..][0..available]);
        return available;
    }
    // Ask for the whole window, halving until the mapping can supply it.
    // This asked for one byte, so every instruction in Xenia's code cache
    // reached the decoder as a single byte and a JIT spin decoded as
    // nothing: "0 instruction(s) decoded" on the 2026-09-13 run.
    var wanted: usize = out.len;
    while (wanted != 0) : (wanted /= 2) {
        if (process_impl_guest_memory.windowsMappedCodeMemoryConst(self, address, wanted)) |generated| {
            const available = @min(wanted, generated.bytes.len);
            process_impl_block_jit.copyGuestCode(self, out[0..available], generated.bytes[0..available]);
            return available;
        }
    }
    return 0;
}

pub fn describeXeniaGuestAddress(self: *const ElfState, address: u64, buffer: []u8) []const u8 {
    const membase = xeniaVirtualMembase(self) orelse return "";
    if (address < membase) return "";
    const offset = address - membase;
    if (offset >= 0x1_0000_0000) {
        if (offset < 0x1_2000_0000) return __process_std.fmt.bufPrint(buffer, " xenia_physical=0x{x}", .{offset - 0x1_0000_0000}) catch "";
        return "";
    }
    if (offset >= 0x7FC8_0000 and offset < 0x7FD0_0000) {
        const index: u16 = @truncate((offset & 0xFFFF) / 4);
        return __process_std.fmt.bufPrint(buffer, " xenia_guest=0x{x} gpu_register=0x{x:0>4} {s}", .{ offset, index, xenosRegisterName(index) }) catch "";
    }
    if (offset >= 0x7FEA_0000 and offset < 0x7FEB_0000) {
        return __process_std.fmt.bufPrint(buffer, " xenia_guest=0x{x} apu_register=0x{x:0>4}", .{ offset, (offset & 0xFFFF) / 4 }) catch "";
    }
    return __process_std.fmt.bufPrint(buffer, " xenia_guest=0x{x}", .{offset}) catch "";
}

pub fn reportGuestThreadSpin(self: *const ElfState, index: usize) void {
    const thread = &self.windows_guest_threads[index];
    const bounds = thread.code.recentBounds() orelse return;
    const registers = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == index)
        &process_impl_lifecycle.guestContextField(self, "regs").*
    else
        &thread.context.regs;
    const listing = __process_spin_anatomy.disassemble(
        .{ .context = self, .read = readGuestCodeForSpin },
        registers,
        bounds.low,
        bounds.high,
    );
    var where: [__process_guest_symbol_text_bytes]u8 = undefined;
    const loop_evidence = __process_spin_anatomy.loopEvidence(&listing);
    __process_log.info("PE64 SPIN ANATOMY: thread 0x{x} '{s}' repeated sampled RIPs in [0x{x},0x{x}) (sampled_span={d} byte(s), {s}); evidence={s} backward_branch_observed={}; decoded_instructions={d}{s}", .{
        thread.handle,
        if (thread.name_len != 0) thread.nameText() else "unnamed by the guest",
        bounds.low,
        bounds.high + 1,
        bounds.high - bounds.low + 1,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, bounds.low, &where),
        @tagName(loop_evidence),
        listing.hasBackwardBranch(),
        listing.count,
        if (listing.truncated) " (window longer than the instrument reads; this is a prefix)" else "",
    });
    if (listing.undecodable_at) |address| {
        // A window that will not decode is a finding in itself: the
        // thread is not executing what this instrument thinks it is.
        __process_log.info("PE64 SPIN ANATOMY:   decoding stopped at 0x{x}: either the bytes are not instructions or the address is not mapped, and both mean the sampled window is not the loop", .{address});
    }
    for (listing.slice()) |instruction| {
        if (instruction.memory) |address| {
            var target: [__process_guest_symbol_text_bytes]u8 = undefined;
            var xenia_text: [96]u8 = undefined;
            const address_label = process_impl_kernel_services.describeGuestAddress(self, address, &target);
            const guest_readable = process_impl_execution.guestMemoryConst(self, address, 8) != null;
            const region_registered = self.guest_regions.find(address) != null;
            const backing = __process_spin_anatomy.classifyMemoryBacking(guest_readable, region_registered);
            __process_log.info("PE64 SPIN ANATOMY:     0x{x}: {s:<28} operand=0x{x} address_label={s} backing={s} guest_readable_8={} region_registered={} xenia={s} base={s} displacement=0x{x} len={d}", .{
                instruction.address,
                @tagName(instruction.op),
                address,
                if (address_label.len == 0) "<no-region-or-symbol>" else address_label,
                @tagName(backing),
                guest_readable,
                region_registered,
                describeXeniaGuestAddress(self, address, &xenia_text),
                if (instruction.base_reg) |reg| @tagName(reg) else "<none>",
                instruction.displacement,
                instruction.length,
            });
        } else {
            __process_log.info("PE64 SPIN ANATOMY:     0x{x}: {s}", .{ instruction.address, @tagName(instruction.op) });
        }
    }
    // Snapshot memory operands separately from control-flow evidence. A
    // load at a repeated RIP does not by itself prove that the guest is
    // polling this value, and readable memory need not have a descriptive
    // guest-region entry.
    var touched: [8]u64 = undefined;
    const touched_count = listing.touchedAddresses(&touched);
    for (touched[0..touched_count]) |address| {
        var target: [__process_guest_symbol_text_bytes]u8 = undefined;
        var xenia_text: [96]u8 = undefined;
        const address_label = process_impl_kernel_services.describeGuestAddress(self, address, &target);
        const value_bytes = process_impl_execution.guestMemoryConst(self, address, 8);
        const guest_readable = value_bytes != null;
        const region_registered = self.guest_regions.find(address) != null;
        const backing = __process_spin_anatomy.classifyMemoryBacking(guest_readable, region_registered);
        __process_log.info("PE64 SPIN ANATOMY:   observed operand=0x{x} address_label={s} backing={s} guest_readable_8={} region_registered={} xenia={s} snapshot_value={s}; repeated RIP does not prove this is a wait condition or the worker-visible value", .{
            address,
            if (address_label.len == 0) "<no-region-or-symbol>" else address_label,
            @tagName(backing),
            guest_readable,
            region_registered,
            describeXeniaGuestAddress(self, address, &xenia_text),
            if (value_bytes != null) "available" else "unavailable",
        });
        if (value_bytes != null) {
            __process_log.info("PE64 SPIN ANATOMY:     snapshot value at 0x{x} = 0x{x}", .{ address, process_impl_guest_memory.read64(self, address) });
        }
    }
    if (touched_count == 0) {
        __process_log.info("PE64 SPIN ANATOMY:   the sampled instruction window reads no memory; repeated RIP alone does not identify a wait condition", .{});
    }
    if (thread.last_import_len != 0) {
        __process_log.info("PE64 SPIN ANATOMY:   the last boundary this thread crossed was {s} at step {d}, {d} import call(s) into its life. That is what it was in the middle of when it stopped getting anywhere", .{
            thread.lastImportText(),
            thread.last_import_step,
            thread.import_calls,
        });
    } else {
        __process_log.info("PE64 SPIN ANATOMY:   this thread has never called a Windows import, so nothing it does crosses a boundary Rosette can name. Its whole life is inside code the guest generated", .{});
    }
    if (thread.last_milestone != 0) {
        const milestone = __process_xenia_guest_milestone_map.milestones[thread.last_milestone - 1];
        __process_log.info("PE64 SPIN ANATOMY:   the last named guest function it entered was {s} at step {d}", .{ milestone.readable, thread.last_milestone_step });
    }
    __process_log.info("PE64 SPIN ANATOMY:   registers: rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rbp=0x{x} rsp=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x}", .{
        registers.rax, registers.rbx, registers.rcx, registers.rdx,
        registers.rsi, registers.rdi, registers.rbp, registers.rsp,
        registers.r12, registers.r13, registers.r14, registers.r15,
    });
}

pub fn noteGuestRegion(
    self: *ElfState,
    address: u64,
    length: u64,
    kind: __process_guest_address_space.RegionKind,
    label: []const u8,
) void {
    _ = self.guest_regions.insert(address, length, kind, label);
}

pub fn noteGuestExecutableAllocation(self: *ElfState, address: u64, length: u64, protection: u32) void {
    noteGuestExecutableAllocationFrom(self, address, length, protection, 0);
}

pub fn noteGuestExecutableAllocationFrom(
    self: *ElfState,
    address: u64,
    length: u64,
    protection: u32,
    caller_rip: u64,
) void {
    if (!__process_guest_address_space.protectionAllowsExecute(protection)) return;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const label = if (caller_rip == 0)
        "guest-allocated executable memory"
    else blk: {
        const described = process_impl_kernel_services.describeGuestAddress(self, caller_rip, &caller_text);
        break :blk if (described.len == 0) "guest-allocated executable memory" else described;
    };
    var covered: u64 = 0;
    while (covered < length) : (covered +|= __process_guest_address_space.discovered_code_granule) {
        if (!self.guest_regions.extend(
            address +| covered,
            __process_guest_address_space.discovered_code_granule,
            .generated_code,
            label,
        )) return;
    }
}

pub fn reportGuestAddressSpace(self: *const ElfState) void {
    const map = &self.guest_regions;
    if (map.count == 0) return;
    __process_log.info("PE64 ADDRESS SPACE: {d} region(s) recorded; {d} lookup(s) landed in none of them. A guest address with no symbol still has an owner, and this is the table that names it", .{
        map.count,
        map.unmapped_lookups,
    });
    for (map.regions[0..map.count]) |*region| {
        __process_log.info("PE64 ADDRESS SPACE:   [0x{x},0x{x}) {d} bytes {s:<20} executable={} lookups={d} {s}", .{
            region.start,
            region.end,
            region.length(),
            region.kind.label(),
            region.kind.isCode(),
            region.lookups,
            region.label(),
        });
    }
    if (map.overflow != 0) {
        __process_log.info("PE64 ADDRESS SPACE:   {d} region(s) did not fit the bounded table", .{map.overflow});
    }
}

pub fn windowsTimezoneGlobal(self: *ElfState, name: []const u8) u64 {
    if (self.windows_timezone_block == 0) {
        //  +0  int   daylight
        //  +8  long  timezone
        // +16  char *tzname[2]
        // +32  "UTC\0" the two names share
        const block = process_impl_guest_heap.guestAlloc(self, 64, 16) orelse return 0;
        self.windows_timezone_block = block;
        process_impl_guest_memory.write32(self, block + 0, 0);
        process_impl_guest_memory.write64(self, block + 8, 0);
        const text = block + 32;
        _ = process_impl_execution.copyToGuest(self, text, "UTC\x00");
        process_impl_guest_memory.write64(self, block + 16, text);
        process_impl_guest_memory.write64(self, block + 24, text);
    }
    const block = self.windows_timezone_block;
    if (__process_std.mem.eql(u8, name, "__daylight")) return block + 0;
    if (__process_std.mem.eql(u8, name, "__timezone")) return block + 8;
    return block + 16; // __tzname
}

pub fn windowsStaticTmBuffer(self: *ElfState) u64 {
    if (self.windows_static_tm == 0) {
        self.windows_static_tm = process_impl_guest_heap.guestAlloc(self, 64, 16) orelse 0;
    }
    return self.windows_static_tm;
}

pub fn noteWindowsDebugString(self: *ElfState, text: []const u8) void {
    self.windows_debug_strings +|= 1;
    if (text.len == 0) return;
    if (self.windows_debug_strings <= 32) {
        __process_log.info("PE64 guest debug string #{d}: {s}", .{ self.windows_debug_strings, text });
    } else if (self.windows_debug_strings == 33) {
        __process_log.info("PE64 guest debug string: further OutputDebugString calls are counted rather than printed", .{});
    }
}

pub fn setWindowsGuestThreadName(self: *ElfState, handle: u64, name: []const u8) bool {
    if (name.len == 0) return false;
    const slot = windowsGuestThreadSlotForName(self, handle) orelse return false;
    const thread = &self.windows_guest_threads[slot];
    const length = @min(name.len, __process_WINDOWS_GUEST_THREAD_NAME_BYTES);
    // Printable ASCII only: the name goes straight into a log line, and a
    // guest is free to put anything in the string it hands the API.
    var written: usize = 0;
    for (name[0..length]) |byte| {
        thread.name[written] = if (byte >= 0x20 and byte < 0x7F) byte else '?';
        written += 1;
    }
    thread.name_len = @intCast(written);
    _ = @atomicRmw(u32, &thread.name_generation, .Add, 1, .release);
    return true;
}

pub fn windowsGuestThreadSlotForName(self: *const ElfState, handle: u64) ?usize {
    // The `GetCurrentThread` pseudo-handle names the caller, which under
    // a cooperative scheduler is the worker holding the slice.
    if (handle == 0 or handle == __process_std.math.maxInt(u64) - 1) return process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (thread.status == .vacant) continue;
        if (thread.handle == handle) return index;
    }
    return process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
}

pub fn windowsGuestThreadRip(self: *const ElfState, index: usize) u64 {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |active| {
        if (active == index) return process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    }
    return self.windows_guest_threads[index].context.regs.rip;
}

pub fn busiestWindowsGuestThread(self: *const ElfState) ?usize {
    var best: ?usize = null;
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (!__process_isLiveWindowsGuestThread(thread.status)) continue;
        if (process_impl_lifecycle.windowsGuestThreadSteps(self, thread) == 0) continue;
        if (best == null or process_impl_lifecycle.windowsGuestThreadSteps(self, thread) > process_impl_lifecycle.windowsGuestThreadSteps(self, &self.windows_guest_threads[best.?])) {
            best = index;
        }
    }
    return best;
}

pub fn rollGuestThreadCodeWindows(self: *ElfState) void {
    for (self.windows_guest_threads) |*thread| {
        if (thread.status == .vacant) continue;
        thread.code.roll();
    }
}

pub fn logGuestThreadShare(self: *const ElfState) void {
    const index = busiestWindowsGuestThread(self) orelse return;
    const thread = &self.windows_guest_threads[index];
    const interpreted = process_impl_run_reporting.totalInterpretedSteps(self);
    if (interpreted == 0) return;
    var live: usize = 0;
    var created: usize = 0;
    var completed: usize = 0;
    var failed: usize = 0;
    for (self.windows_guest_threads) |*candidate| {
        switch (candidate.status) {
            .vacant => {},
            .completed => {
                created += 1;
                completed += 1;
            },
            .failed => {
                created += 1;
                failed += 1;
            },
            else => {
                created += 1;
                if (__process_isLiveWindowsGuestThread(candidate.status)) live += 1;
            },
        }
    }
    var where: [__process_guest_symbol_text_bytes]u8 = undefined;
    var start: [__process_guest_symbol_text_bytes]u8 = undefined;
    __process_log.info("PE64 THREAD SHARE: {d} live worker(s), {d} created ({d} completed, {d} failed); busiest handle=0x{x}{s}{s}{s} status={s} steps={d} ({d}% of the run) at={s} rip=0x{x} pages~{d} start={s}", .{
        live,
        created,
        completed,
        failed,
        thread.handle,
        if (thread.name_len != 0) " name='" else "",
        thread.nameText(),
        if (thread.name_len != 0) "'" else "",
        @tagName(thread.status),
        process_impl_lifecycle.windowsGuestThreadSteps(self, thread),
        @divTrunc(process_impl_lifecycle.windowsGuestThreadSteps(self, thread) *| 100, interpreted),
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, windowsGuestThreadRip(self, index), &where),
        windowsGuestThreadRip(self, index),
        thread.codePages(),
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, thread.start_routine, &start),
    });
}

pub fn reportWindowsUiPipeline(self: *const ElfState) void {
    const ui = &self.windows_ui_pipeline;
    const queue = self.windows_message_queue.snapshot();
    var post_caller_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    const post_caller = process_impl_kernel_services.describeGuestAddressOrUnnamed(self, ui.last_pending_post_return_rip, &post_caller_storage);
    __process_log.info("PE64 WINDOWS UI HANDOFF: class_registrations={d} windows(created/message_only)={d}/{d} pending_hwnd=0x{x} wndproc=0x{x} user_data=0x{x} messages(posted/dequeued/dropped/queued)={d}/{d}/{d}/{d} Xenia_WM_USER(posted/dropped/dequeued/dispatch/wndproc_missing/frame_refused/returned)={d}/{d}/{d}/{d}/{d}/{d}/{d} last_post(hwnd/message)=0x{x}/0x{x} last_pending_post(wparam/lparam/thread)=0x{x}/0x{x}/0x{x} last_pending_dequeue(wparam/lparam/thread)=0x{x}/0x{x}/0x{x} last_dispatch(hwnd/message/wndproc)=0x{x}/0x{x}/0x{x} last_pending_dispatch(wparam/lparam/thread)=0x{x}/0x{x}/0x{x}; see POST PROVENANCE for the caller and step", .{
        ui.class_registrations,
        ui.windows_created,
        ui.message_windows_created,
        ui.message_window_handle,
        ui.message_window_wndproc,
        ui.message_window_user_data,
        ui.posted,
        ui.dequeued,
        ui.post_drops,
        queue.count,
        ui.pending_function_posts,
        ui.pending_function_post_drops,
        ui.pending_function_dequeues,
        ui.pending_function_dispatches,
        ui.pending_function_dispatch_without_wndproc,
        ui.pending_function_frame_refusals,
        ui.pending_function_returns,
        ui.last_post_hwnd,
        ui.last_post_message,
        ui.last_pending_post_wparam,
        ui.last_pending_post_lparam,
        ui.last_pending_post_thread,
        ui.last_pending_dequeue_wparam,
        ui.last_pending_dequeue_lparam,
        ui.last_pending_dequeue_thread,
        ui.last_dispatch_hwnd,
        ui.last_dispatch_message,
        ui.last_dispatch_wndproc,
        ui.last_pending_dispatch_wparam,
        ui.last_pending_dispatch_lparam,
        ui.last_pending_dispatch_thread,
    });
    const in_progress_ms: u64 = if (ui.pending_function_in_progress_since_ns != 0)
        (__process_monotonicNanoseconds() -| ui.pending_function_in_progress_since_ns) / __process_std.time.ns_per_ms
    else
        0;
    __process_log.info("PE64 WINDOWS UI HANDOFF TIMING: queued_ms(total/max/last)={d}/{d}/{d} ran_ms(total/max/last)={d}/{d}/{d} awaiting_dequeue={d} running_now={} running_for_ms={d} affinity_skips={d}; queued is post to dequeue (the UI thread was not in GetMessage, or did not wake), ran is the pending function itself on the UI thread (Xenia's presenter is created in one). A handoff that never returns is running_now=true with a growing running_for_ms. affinity_skips counts messages a thread passed over because another thread created their window", .{
        ui.queued_ns_total / __process_std.time.ns_per_ms,
        ui.queued_ns_max / __process_std.time.ns_per_ms,
        ui.last_queued_ns / __process_std.time.ns_per_ms,
        ui.ran_ns_total / __process_std.time.ns_per_ms,
        ui.ran_ns_max / __process_std.time.ns_per_ms,
        ui.last_ran_ns / __process_std.time.ns_per_ms,
        ui.post_time_count,
        ui.pending_function_in_progress_since_ns != 0,
        in_progress_ms,
        queue.affinity_skips,
    });
    __process_log.info("PE64 WINDOWS UI QUEUE: depth/high_water={d}/{d} last_post(by/owner)=0x{x}/0x{x} last_dequeue(by/owner)=0x{x}/0x{x} last_affinity_skip(by/owner)=0x{x}/0x{x}; message ownership is captured from the target window's creator thread", .{
        queue.count,
        queue.high_water,
        queue.last_posted_by_thread_id,
        queue.last_post_owner_thread_id,
        queue.last_delivery_by_thread_id,
        queue.last_delivery_owner_thread_id,
        queue.last_affinity_skip_by_thread_id,
        queue.last_affinity_skip_owner_thread_id,
    });
    __process_log.info("PE64 WINDOWS UI POST PROVENANCE: last_pending_post(return_rip=0x{x} caller={s} step={d}) deferred_entries/returns/accepted={d}/{d}/{}; the return RIP is the caller site of the PostMessageW import, not a guessed window-proc target", .{
        ui.last_pending_post_return_rip,
        post_caller,
        ui.last_pending_post_step,
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.call_in_ui_thread_deferred],
        self.xenia_ui_deferred_returns,
        self.xenia_ui_deferred_last_accepted,
    });
    const trace = self.xenia_setup_trace;
    const setup_end_step = if (trace.pending) process_impl_run_reporting.totalInterpretedSteps(self) else trace.last_return_step;
    const setup_steps = if (trace.entry_step != 0) setup_end_step -| trace.entry_step else 0;
    __process_log.info("PE64 XENIA BOOTSTRAP HANDOFF: emulator_thread={d} emulator_setup(entry/return/pending/last_status)= {d}/{d}/{}/0x{x} setup_steps={d} setup_thread=0x{x} setup_return_rip=0x{x} ui_queue(call/deferred_entries/deferred_returns/posts/drops/last_accepted)= {d}/{d}/{d}/{d}/{d}/{}; deferred return reports the acceptance bool; no presenter callback before successful setup is an incomplete bootstrap, not a surface failure", .{
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.emulator_thread],
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.emulator_setup],
        trace.returns,
        trace.pending,
        trace.last_status,
        setup_steps,
        trace.thread,
        trace.return_rip,
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.call_in_ui_thread],
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.call_in_ui_thread_deferred],
        self.xenia_ui_deferred_returns,
        ui.pending_function_posts,
        ui.pending_function_post_drops,
        self.xenia_ui_deferred_last_accepted,
    });
    __process_log.info("PE64 XENIA PRESENTER ATTACH: entries(setup/get_presenter/set_presenter/create_surface/surface_attach/vulkan_connect)={d}/{d}/{d}/{d}/{d}/{d}; zero marks the last Xenia boundary not reached; compare surface_attach with the Vulkan surface-dispatch ledger", .{
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.setup],
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.get_presenter],
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.set_presenter],
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.create_surface],
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.attach_surface],
        self.guest_milestone_hits[__process_xenia_presenter_attach_milestones.vulkan_connect],
    });
}

pub fn reportGuestThreads(self: *const ElfState) void {
    const interpreted = process_impl_run_reporting.totalInterpretedSteps(self);
    var created: usize = 0;
    var live: usize = 0;
    var completed: usize = 0;
    var failed: usize = 0;
    var vacant: usize = 0;
    for (self.windows_guest_threads) |*thread| {
        switch (thread.status) {
            .vacant => vacant += 1,
            .completed => {
                created += 1;
                completed += 1;
            },
            .failed => {
                created += 1;
                failed += 1;
            },
            else => {
                created += 1;
                if (__process_isLiveWindowsGuestThread(thread.status)) live += 1;
            },
        }
    }
    const worker_steps = process_impl_lifecycle.windowsWorkerSteps(self);
    if (created == 0) {
        __process_log.info("PE64 GUEST THREADS: no guest worker threads were created", .{});
        return;
    }
    // Keep lifecycle counts explicit. A completed one-shot worker is a
    // valid Windows outcome and is not evidence that a requested thread
    // failed to start; only a failed status or a refused creation is a
    // lifecycle defect.
    __process_log.info("PE64 GUEST THREADS: created={d} live={d} completed={d} failed={d} vacant={d} capacity={d}; completed workers are normal one-shot exits, while failed={d} or refused={d} identify lifecycle loss", .{
        created,
        live,
        completed,
        failed,
        vacant,
        self.windows_guest_threads.len,
        failed,
        self.windows_thread_table_full,
    });
    if (self.windows_thread_suspended_creations != 0 or self.windows_thread_suspend_calls != 0 or self.windows_thread_resume_calls != 0) {
        __process_log.info("PE64 GUEST THREADS: suspension created_suspended={d} suspend_calls={d} resume_calls={d}; a thread whose suspend count is not zero is never scheduled, as CREATE_SUSPENDED and SuspendThread promise", .{
            self.windows_thread_suspended_creations,
            self.windows_thread_suspend_calls,
            self.windows_thread_resume_calls,
        });
    }
    __process_log.info("PE64 GUEST THREADS: {d} live (active statuses pending/runnable/running/blocked; table holds {d} slots and gives a finished thread's slot to a new one when it is full; {d} reused, {d} refused); workers ran {d} of {d} interpreted instruction(s) ({d}%), the owner ran {d}", .{
        live,
        self.windows_guest_threads.len,
        self.windows_thread_slots_recycled,
        self.windows_thread_table_full,
        worker_steps,
        interpreted,
        if (interpreted == 0) 0 else @divTrunc(worker_steps *| 100, interpreted),
        process_impl_lifecycle.ownerExecutedSteps(self),
    });
    var spinning_threads: usize = 0;
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (!__process_isLiveWindowsGuestThread(thread.status)) continue;
        var where: [__process_guest_symbol_text_bytes]u8 = undefined;
        var start: [__process_guest_symbol_text_bytes]u8 = undefined;
        const share = if (interpreted == 0) 0 else @divTrunc(process_impl_lifecycle.windowsGuestThreadSteps(self, thread) *| 100, interpreted);
        // The raw rip is printed beside the symbol because the two
        // answer different questions: a thread whose rip lies outside the
        // image has no symbol by construction - it is running in a JIT
        // buffer or a Rosette thunk - and `<unnamed>` alone cannot say
        // which of those it is.
        __process_log.info("PE64 GUEST THREADS:   handle=0x{x} {s:<9} steps={d} ({d}%) name='{s}' at={s} rip=0x{x} code_span={d}B pages~{d} start={s}{s} pause_hints={d} pause_host_yields={d}", .{
            thread.handle,
            @tagName(thread.status),
            process_impl_lifecycle.windowsGuestThreadSteps(self, thread),
            share,
            if (thread.name_len != 0) thread.nameText() else "<unnamed by the guest>",
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, windowsGuestThreadRip(self, index), &where),
            windowsGuestThreadRip(self, index),
            thread.codeSpan(),
            thread.codePages(),
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, thread.start_routine, &start),
            if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == index) " <- executing now" else "",
            __process_parallel_metrics.load(u64, &thread.pause_hints),
            __process_parallel_metrics.load(u64, &thread.pause_host_yields),
        });
        if (thread.suspend_count != 0) {
            __process_log.info("PE64 GUEST THREADS:     suspended suspend_count={d}: created suspended or suspended since, and not resumed; the scheduler will not run it until ResumeThread brings the count to zero", .{thread.suspend_count});
        }
        // A busy thread inside a handful of pages is spinning; the same
        // thread across dozens is working. Only said where it can be
        // wrong to guess: a thread with a real share of the run.
        if (share >= 5 and thread.code.samples != 0) {
            if (thread.code.isSpin()) {
                __process_log.info("PE64 GUEST THREADS:     this thread spent {d}% of the run going round [0x{x},0x{x}] - {d} byte(s), {d} page(s). That is a spin, not progress; PE64 SPIN ANATOMY says what it reads", .{
                    share,
                    thread.code.recentBounds().?.low,
                    thread.code.recentBounds().?.high,
                    thread.code.recentSpan(),
                    thread.codePages(),
                });
                spinning_threads += 1;
            } else {
                // Both ends named. `code_span` is a subtraction across
                // whatever regions the thread has touched, so a thread
                // that runs in Xenia's JIT cache and calls into the image
                // reports gigabytes and reads as chaos; the two region
                // names say what it actually straddles, which for the
                // title's own thread is the whole shape of what it does.
                var low_text: [__process_guest_symbol_text_bytes]u8 = undefined;
                var high_text: [__process_guest_symbol_text_bytes]u8 = undefined;
                __process_log.info("PE64 GUEST THREADS:     {d}% of the run across {d} page(s), lifetime code=[0x{x},0x{x}]: broad execution footprint, NOT proof of progress or absence of a multi-function polling loop. Those ends are {s} and {s}", .{
                    share,
                    thread.codePages(),
                    thread.code.low,
                    thread.code.high,
                    process_impl_kernel_services.describeGuestAddressOrUnnamed(self, thread.code.low, &low_text),
                    process_impl_kernel_services.describeGuestAddressOrUnnamed(self, thread.code.high, &high_text),
                });
            }
        }
        if (share >= 5) {
            for (thread.code.heat.top(), 0..) |candidate, rank| {
                if (candidate.count == 0) continue;
                var hotspot_text: [__process_guest_symbol_text_bytes]u8 = undefined;
                __process_log.info("PE64 CPU HOTSPOT: thread=0x{x} name='{s}' rank={d} region=0x{x} at={s} samples={d} count_lower/upper={d}/{d}; 256-byte lifetime candidate, one sample per ~1024 worker instructions; not a wall-time or spin verdict", .{ thread.handle, if (thread.name_len != 0) thread.nameText() else "<unnamed>", rank + 1, candidate.address, process_impl_kernel_services.describeGuestAddressOrUnnamed(self, candidate.address, &hotspot_text), thread.code.heat.samples, candidate.count - candidate.error_bound, candidate.count });
                // The top three: on 2026-09-21 RENDER's first two regions
                // were one function 0xB00 apart, and one region alone
                // could not show where its loop closed.
                if (rank < 3) process_impl_block_jit.logHotspotBytes(self, thread.handle, candidate.address);
            }
        }
        // What this thread last asked the emulated kernel for. For every
        // thread but the title's this is a curiosity; for the title's it
        // is the only narrative there is, because everything it runs in
        // between is translated PowerPC with no name.
        if (thread.kernel_calls != 0) {
            const last_call = self.guest_kernel_calls.slotAt(thread.last_kernel_slot);
            __process_log.info("PE64 GUEST THREADS:     kernel calls={d}; the last was {s}!{s} at step {d}", .{
                thread.kernel_calls,
                if (last_call) |slot| slot.module.moduleName() else "<unknown>",
                if (last_call) |slot| slot.export_name else "<none recorded>",
                thread.last_kernel_step,
            });
            if (thread.status == .blocked and thread.critical_section != 0 and last_call != null and
                __process_std.mem.eql(u8, last_call.?.export_name, "RtlEnterCriticalSection"))
            {
                process_impl_kernel_services.logCriticalSectionWait(self, thread);
            }
        } else if (thread.entered_xenia_title) {
            __process_log.info("PE64 GUEST THREADS:     this thread runs the title and has made no kernel call at all; it is executing translated PowerPC that never reaches an import thunk, which PE64 GUEST CODE PROGRESS can say is new code or a loop", .{});
        }
        if (thread.status == .blocked) {
            // When the object being waited on is another guest thread,
            // name it. A wait graph printed as bare handles has to be
            // reassembled by hand from the handle column above it, and
            // the whole question a reader has is "who is it waiting for,
            // and is that one making progress?".
            var target_text: [96]u8 = undefined;
            const target = describeWindowsWaitTarget(self, thread.blocked_wait_handle, &target_text);
            const join = windowsJoinVerdict(self, thread.blocked_wait_handle);
            const blocked_age_steps = if (thread.blocked_since_total_steps == 0)
                0
            else
                process_impl_run_reporting.totalInterpretedSteps(self) -| thread.blocked_since_total_steps;
            const blocked_age_ticks = if (thread.blocked_since_guest_ticks == 0)
                0
            else
                process_impl_lifecycle.windowsGuestClockTicks(self) -| thread.blocked_since_guest_ticks;
            var owner_text: [160]u8 = undefined;
            const lock_owner: []const u8 = blk: {
                if (thread.blocked_srw_lock == 0) break :blk "";
                if (thread.xbox_cs_wait == thread.blocked_srw_lock) {
                    break :blk process_impl_kernel_services.describeXboxCriticalSectionWait(self, thread.xbox_cs_wait, &owner_text);
                }
                const lock = if (process_impl_windows_sync.windowsSrwLockIndex(self, thread.blocked_srw_lock)) |lock_index|
                    self.windows_srw_locks[lock_index]
                else if (process_impl_windows_sync.windowsCriticalSectionIndex(self, thread.blocked_srw_lock)) |section_index|
                    self.windows_critical_sections[section_index]
                else
                    break :blk " (no lock record)";
                var name_text: [96]u8 = undefined;
                break :blk __process_std.fmt.bufPrint(&owner_text, " (held by {s}, {d} waiting)", .{
                    process_impl_windows_sync.describeWindowsSrwOwner(self, lock.owner_thread_id, &name_text),
                    process_impl_windows_sync.windowsSrwWaiterCount(self, lock),
                }) catch "";
            };
            __process_log.info("PE64 GUEST THREADS:     blocked_on wait=0x{x}{s} join={s} age_steps={d} age_ticks={d} lock=0x{x}{s} condition=0x{x} timeout={d} deadline={d}", .{
                thread.blocked_wait_handle,
                target,
                join,
                blocked_age_steps,
                blocked_age_ticks,
                thread.blocked_srw_lock,
                lock_owner,
                thread.blocked_condition,
                thread.blocked_wait_timeout,
                thread.blocked_wait_deadline,
            });
        }
    }
    if (spinning_threads != 0) {
        for (self.windows_guest_threads, 0..) |*thread, index| {
            if (!__process_isLiveWindowsGuestThread(thread.status)) continue;
            const share = if (interpreted == 0) 0 else @divTrunc(process_impl_lifecycle.windowsGuestThreadSteps(self, thread) *| 100, interpreted);
            if (share < 5 or !thread.code.isSpin()) continue;
            reportGuestThreadSpin(self, index);
        }
    }
    if (busiestWindowsGuestThread(self)) |index| {
        const thread = &self.windows_guest_threads[index];
        const share = if (interpreted == 0) 0 else @divTrunc(process_impl_lifecycle.windowsGuestThreadSteps(self, thread) *| 100, interpreted);
        var where: [__process_guest_symbol_text_bytes]u8 = undefined;
        const described = process_impl_kernel_services.describeGuestAddressOrUnnamed(self, windowsGuestThreadRip(self, index), &where);
        const named = if (thread.name_len != 0) thread.nameText() else "unnamed by the guest";
        if (share >= 50) {
            __process_log.info("PE64 GUEST THREADS:   verdict: one worker holds {d}% of the run ('{s}') and it is sitting in {s}. A cooperative scheduler cannot make progress the busiest thread is not making, so read that symbol before anything downstream of it", .{ share, named, described });
        } else {
            __process_log.info("PE64 GUEST THREADS:   verdict: the busiest worker holds {d}% of the run ('{s}'), in {s}; no single thread is monopolising the interpreter", .{ share, named, described });
        }
    }
}

pub fn classifyWindowsBlockedThread(thread: *const __process_WindowsGuestThread) __state_WindowsBlockedCause {
    if (thread.blocked_condition != 0) {
        return if (thread.timed_wait_site != 0 or thread.timed_wait_milliseconds != 0)
            .timed_condition
        else
            .condition;
    }
    if (thread.blocked_srw_lock != 0) return .srw_lock;
    if (thread.blocked_wait_handle != 0) {
        return if (thread.blocked_wait_deadline != 0) .finite_handle else .infinite_handle;
    }
    if (thread.blocked_wait_deadline != 0) return .deadline;
    return .unknown;
}

pub fn windowsWaitCostSiteForThread(self: *const ElfState, thread: *const __process_WindowsGuestThread) ?*const __process_wait_cost.Site {
    if (thread.wait_cost_site != 0) {
        const index = @as(usize, thread.wait_cost_site) - 1;
        if (index < self.windows_wait_cost.count) return &self.windows_wait_cost.sites[index];
    }
    const cause = classifyWindowsBlockedThread(thread);
    const kind: __process_wait_cost.WaitKind = switch (cause) {
        .timed_condition => .timed_condition,
        .condition => .condition,
        .finite_handle => .finite_handle,
        .infinite_handle => .infinite_handle,
        .srw_lock => .srw_lock,
        .deadline => .deadline,
        .unknown => return null,
    };
    const key = switch (cause) {
        .timed_condition, .condition => thread.blocked_condition,
        .finite_handle, .infinite_handle => thread.blocked_wait_handle,
        .srw_lock => thread.blocked_srw_lock,
        .deadline => 0,
        .unknown => 0,
    };
    return __process_wait_cost.siteAt(&self.windows_wait_cost, key, kind);
}

pub fn windowsWaiterSlotForSite(self: *const ElfState, site_index: usize, site: __process_wait_cost.Site) ?usize {
    var selected: ?usize = null;
    var selected_start: u64 = __process_std.math.maxInt(u64);
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (thread.status != .blocked) continue;
        var matches = false;
        if (thread.wait_cost_site != 0) {
            const accounted_index = @as(usize, thread.wait_cost_site) - 1;
            matches = accounted_index == site_index;
        } else {
            matches = switch (site.kind) {
                .condition, .timed_condition => thread.blocked_condition == site.key,
                .finite_handle, .infinite_handle, .multiple => thread.waitsOnHandle(site.key),
                .srw_lock => thread.blocked_srw_lock == site.key,
                .deadline => false,
            };
        }
        if (!matches) continue;
        const start = if (thread.blocked_since_total_steps == 0)
            __process_std.math.maxInt(u64)
        else
            thread.blocked_since_total_steps;
        if (selected == null or start < selected_start) {
            selected = index;
            selected_start = start;
        }
    }
    return selected;
}

pub fn reportWindowsWaitEscalation(
    self: *ElfState,
    site_index: usize,
    site: *const __process_wait_cost.Site,
    classification: __process_wait_cost.Classification,
) void {
    const waiter_slot = windowsWaiterSlotForSite(self, site_index, site.*);
    var waiter_handle: u64 = 0;
    var waiter_thread_id: u64 = 0;
    var waiter_name: []const u8 = "<no current blocked waiter>";
    var waiter_age_steps: u64 = 0;
    var waiter_age_ticks: u64 = 0;
    var waiter_condition: u64 = 0;
    var waiter_mutex: u64 = 0;
    var waiter_wait_handle: u64 = 0;
    var waiter_last_import: []const u8 = "<not retained>";
    var waiter_last_import_step: u64 = 0;
    var waiter_rip: u64 = 0;
    var waiter_kernel_step: u64 = 0;
    var waiter_slot_text: ?usize = null;
    var kernel_module: []const u8 = "<none>";
    var kernel_export: []const u8 = "<none>";

    if (waiter_slot) |slot| {
        const thread = &self.windows_guest_threads[slot];
        waiter_slot_text = slot;
        waiter_handle = thread.handle;
        waiter_thread_id = thread.thread_id;
        waiter_name = if (thread.name_len != 0) thread.nameText() else "<unnamed>";
        waiter_age_steps = if (thread.blocked_since_total_steps == 0)
            0
        else
            process_impl_run_reporting.totalInterpretedSteps(self) -| thread.blocked_since_total_steps;
        waiter_age_ticks = if (thread.blocked_since_guest_ticks == 0)
            0
        else
            process_impl_lifecycle.windowsGuestClockTicks(self) -| thread.blocked_since_guest_ticks;
        waiter_condition = thread.blocked_condition;
        waiter_mutex = thread.blocked_condition_mutex;
        waiter_wait_handle = thread.blocked_wait_handle;
        waiter_last_import = if (thread.last_import_len != 0) thread.lastImportText() else "<none>";
        waiter_last_import_step = thread.last_import_step;
        waiter_rip = windowsGuestThreadRip(self, slot);
        waiter_kernel_step = thread.last_kernel_step;
        if (self.guest_kernel_calls.slotAt(thread.last_kernel_slot)) |entry| {
            kernel_module = entry.module.moduleName();
            kernel_export = entry.export_name;
        }
    }

    const site_age_steps = if (site.first_step == 0)
        0
    else
        process_impl_run_reporting.totalInterpretedSteps(self) -| site.first_step;
    const site_age_ticks = if (site.first_ticks == 0)
        0
    else
        process_impl_lifecycle.windowsGuestClockTicks(self) -| site.first_ticks;
    const age_steps = if (waiter_slot != null) waiter_age_steps else site_age_steps;
    const age_ticks = if (waiter_slot != null) waiter_age_ticks else site_age_ticks;
    const site_handle = if (site.kind == .finite_handle or site.kind == .infinite_handle or site.kind == .multiple)
        site.key
    else
        waiter_wait_handle;

    var rip_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const rip_description = if (waiter_slot != null)
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, waiter_rip, &rip_text)
    else
        "<not available>";
    var signal_rip_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const signal_rip_description = if (site.last_signal_rip != 0)
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, site.last_signal_rip, &signal_rip_text)
    else
        "<none>";

    var mutex_state: u32 = 0;
    var mutex_owner_thread_id: u64 = 0;
    var mutex_model: []const u8 = "not_observed";
    var mutex_owner_text_buffer: [128]u8 = undefined;
    var mutex_owner_text: []const u8 = "not_observed";
    if (waiter_mutex != 0) {
        if (process_impl_windows_sync.windowsPthreadMutexImpl(self, waiter_mutex)) |impl| {
            mutex_state = process_impl_guest_memory.read32(self, impl);
            mutex_owner_thread_id = @as(u64, process_impl_guest_memory.read32(self, impl + 0x14));
            mutex_model = if (mutex_state == 0) "unlocked" else "owned_or_contended";
            mutex_owner_text = process_impl_windows_sync.describeWindowsSrwOwner(self, mutex_owner_thread_id, &mutex_owner_text_buffer);
        } else {
            mutex_model = "unreadable";
            mutex_owner_text = "unreadable";
        }
    }

    var object_kind: []const u8 = "none";
    var readiness: []const u8 = "not_applicable";
    if (site_handle != 0) {
        object_kind = process_impl_windows_sync.windowsWaitObjectKindName(self, site_handle);
        readiness = if (process_impl_windows_sync.windowsWaitObjectReady(self, site_handle)) |ready|
            if (ready) "ready" else "not_ready"
        else
            "unmodeled";
    }

    const pending_workers = process_impl_run_reporting.countWindowsWorkers(self, .pending);
    const runnable_workers = process_impl_run_reporting.countWindowsWorkers(self, .runnable);
    const running_workers = process_impl_run_reporting.countWindowsWorkers(self, .running);
    const blocked_workers = process_impl_run_reporting.countWindowsWorkers(self, .blocked);
    const timeout_percent = if (site.waits == 0)
        0
    else
        @min(@as(u64, 100), (site.timed_out *| 100) / site.waits);
    const timeout_tick_percent = if (site.total_ticks == 0)
        0
    else
        @min(@as(u64, 100), (site.timed_out_ticks *| 100) / site.total_ticks);

    if (classification == .unsignalled_condition) {
        __process_log.warn("PE64 WAIT ESCALATION: class=unsignalled_condition severity=critical trigger=sustained_absence_of_notification site={d} key=0x{x} kind={s} waiter_slot={?d} waiter_thread=0x{x} thread_id={d} name='{s}' age_steps={d} age_ticks={d} wait_started_step={d} wait_last_step={d} wait_started_ticks={d} wait_last_ticks={d} condition=0x{x} mutex=0x{x} mutex_model={s} mutex_state={d} mutex_owner_thread_id={d} mutex_owner={s}", .{
            site_index,
            site.key,
            site.kind.label(),
            waiter_slot_text,
            waiter_handle,
            waiter_thread_id,
            waiter_name,
            age_steps,
            age_ticks,
            site.first_step,
            site.last_step,
            site.first_ticks,
            site.last_ticks,
            waiter_condition,
            waiter_mutex,
            mutex_model,
            mutex_state,
            mutex_owner_thread_id,
            mutex_owner_text,
        });
        __process_log.warn("PE64 WAIT ESCALATION:   context=unsignalled_condition last_import={s} last_import_step={d} rip=0x{x} at={s} last_kernel={s}!{s} last_kernel_step={d} total_steps={d} guest_ticks={d} workers(pending/runnable/running/blocked)={d}/{d}/{d}/{d} condition_signal_calls={d} condition_broadcast_calls={d} matching_notifications={d} last_signal_step={d} action=capture_the_predicate_writer_and_signal_or_broadcast_owner; Rosetta_keeps_the_waiter_blocked_until_real_notification", .{
            waiter_last_import,
            waiter_last_import_step,
            waiter_rip,
            rip_description,
            kernel_module,
            kernel_export,
            waiter_kernel_step,
            process_impl_run_reporting.totalInterpretedSteps(self),
            process_impl_lifecycle.windowsGuestClockTicks(self),
            pending_workers,
            runnable_workers,
            running_workers,
            blocked_workers,
            self.windows_condition_signal_calls,
            self.windows_condition_broadcast_calls,
            site.signals,
            site.last_signal_step,
        });
        return;
    }

    __process_log.warn("PE64 WAIT ESCALATION: class=timeout_hotspot severity=high trigger=timeout_cost_threshold site={d} key=0x{x} kind={s} handle=0x{x} object_kind={s} readiness={s} waiter_slot={?d} waiter_thread=0x{x} thread_id={d} name='{s}' age_steps={d} age_ticks={d} last_import={s} last_import_step={d} rip=0x{x} at={s} timeout_ms={d} waits={d} active={d} signaled={d} timeouts={d} ({d}%)", .{
        site_index,
        site.key,
        site.kind.label(),
        site_handle,
        object_kind,
        readiness,
        waiter_slot_text,
        waiter_handle,
        waiter_thread_id,
        waiter_name,
        age_steps,
        age_ticks,
        waiter_last_import,
        waiter_last_import_step,
        waiter_rip,
        rip_description,
        site.last_timeout_milliseconds,
        site.waits,
        site.active,
        site.signaled,
        site.timed_out,
        timeout_percent,
    });
    __process_log.warn("PE64 WAIT ESCALATION:   context=timeout_hotspot signals={d} total_guest_ticks={d} timeout_guest_ticks={d} ({d}%) max_wait_ticks={d} max_timeout_overshoot_ticks={d} first_step={d} last_step={d} last_timeout_step={d} last_signal_step={d} last_signal_thread=0x{x} last_signal_rip=0x{x} last_signal_at={s} workers(pending/runnable/running/blocked)={d}/{d}/{d}/{d} producer_evidence={s} action=inspect_the_producer_and_decide_polling_vs_missing_work; Rosetta_does_not_convert_expiry_into_success", .{
        site.signals,
        site.total_ticks,
        site.timed_out_ticks,
        timeout_tick_percent,
        site.max_ticks,
        site.max_timeout_overshoot_ticks,
        site.first_step,
        site.last_step,
        site.last_timeout_step,
        site.last_signal_step,
        site.last_signal_thread_handle,
        site.last_signal_rip,
        signal_rip_description,
        pending_workers,
        runnable_workers,
        running_workers,
        blocked_workers,
        if (waiter_slot == null) "no_current_waiter_at_capture" else "current_waiter_recorded",
    });
}

pub fn reportWindowsWaitEscalations(self: *ElfState) void {
    const total_steps = process_impl_run_reporting.totalInterpretedSteps(self);
    for (self.windows_wait_cost.sites[0..self.windows_wait_cost.count], 0..) |*site, index| {
        const classification = __process_wait_cost.classify(site.*);
        switch (classification) {
            .unsignalled_condition => {
                if (site.active == 0) continue;
                const age_steps = if (site.first_step == 0) 0 else total_steps -| site.first_step;
                const age_ticks = if (site.first_ticks == 0) 0 else process_impl_lifecycle.windowsGuestClockTicks(self) -| site.first_ticks;
                if (age_steps < __process_WINDOWS_WAIT_ESCALATION_MIN_AGE_STEPS and
                    age_ticks < __process_WINDOWS_WAIT_ESCALATION_MIN_AGE_TICKS)
                {
                    continue;
                }
                if (!site.claimUnsignalledEscalation()) continue;
                self.windows_wait_unsignalled_escalations +|= 1;
                reportWindowsWaitEscalation(self, index, site, classification);
            },
            .timeout_hotspot => {
                if (!site.claimTimeoutHotspotEscalation()) continue;
                self.windows_wait_timeout_hotspot_escalations +|= 1;
                reportWindowsWaitEscalation(self, index, site, classification);
            },
            else => {},
        }
    }
}

pub fn classifyWindowsBlockedFinding(self: *const ElfState, thread: *const __process_WindowsGuestThread) __state_WindowsBlockedFinding {
    const cause = classifyWindowsBlockedThread(thread);
    switch (cause) {
        .unknown => return .missing_wait_model,
        .deadline => return .expected_deadline,
        .srw_lock => return .lock_owner_pending,
        .timed_condition, .condition => {
            if (windowsWaitCostSiteForThread(self, thread)) |site| {
                return switch (__process_wait_cost.classify(site.*)) {
                    .periodic_timeout_poll => .periodic_timeout_poll,
                    .lost_wakeup_candidate => .unsignalled_condition,
                    .unsignalled_condition => .unsignalled_condition,
                    .mixed_timeout_signal => .condition_producer_pending,
                    .pending_producer => .condition_producer_pending,
                    else => if (cause == .timed_condition) .periodic_timeout_poll else .condition_producer_pending,
                };
            }
            return if (cause == .timed_condition) .periodic_timeout_poll else .unsignalled_condition;
        },
        .finite_handle => {
            if (windowsWaitCostSiteForThread(self, thread)) |site| {
                if (__process_wait_cost.classify(site.*) == .timeout_hotspot) return .timeout_hotspot;
            }
            return .producer_not_ready;
        },
        .infinite_handle => {
            if (process_impl_windows_sync.windowsWaitObjectReady(self, thread.blocked_wait_handle)) |ready| {
                if (ready) return .ready_but_blocked;
            }
            const join = windowsJoinVerdict(self, thread.blocked_wait_handle);
            if (__process_std.mem.eql(u8, join, "active_target") or
                __process_std.mem.eql(u8, join, "chain_reaches_active_target"))
            {
                return .active_join_chain;
            }
            if (__process_std.mem.eql(u8, join, "join_cycle") or
                __process_std.mem.eql(u8, join, "join_chain_too_deep"))
            {
                return .join_cycle;
            }
            if (!__process_std.mem.eql(u8, join, "not_thread_join")) return .join_target_not_ready;
            // A semaphore/event can remain actively waited on while its
            // producer continues to signal it. That is a live background
            // service, not the same finding as a handle that has never
            // produced a completion. Preserve it as context so the
            // upstream report does not inflate liveness debt with healthy
            // history (ASYNC_IO in the long run is the concrete case).
            if (windowsWaitCostSiteForThread(self, thread)) |site| {
                if (__process_wait_cost.classify(site.*) == .healthy) return .active_wait_with_history;
            }
            return .producer_not_ready;
        },
    }
}

pub fn reportWindowsBlockedDiagnostics(self: *const ElfState, limit: usize) void {
    var blocked: usize = 0;
    var timed_conditions: usize = 0;
    var conditions: usize = 0;
    var finite_handles: usize = 0;
    var infinite_handles: usize = 0;
    var srw_locks: usize = 0;
    var deadlines: usize = 0;
    var unknown: usize = 0;
    for (self.windows_guest_threads) |*thread| {
        if (thread.status != .blocked) continue;
        blocked += 1;
        switch (classifyWindowsBlockedThread(thread)) {
            .timed_condition => timed_conditions += 1,
            .condition => conditions += 1,
            .finite_handle => finite_handles += 1,
            .infinite_handle => infinite_handles += 1,
            .srw_lock => srw_locks += 1,
            .deadline => deadlines += 1,
            .unknown => unknown += 1,
        }
    }
    if (blocked == 0) return;
    __process_log.info("PE64 BLOCKED WAIT DIAGNOSTICS: blocked={d} timed_condition={d} condition={d} finite_handle={d} infinite_handle={d} srw_lock={d} deadline={d} unknown={d}; waits remain cooperative and only a real signal, completion, or guest-clock deadline may make a blocked thread runnable", .{
        blocked,
        timed_conditions,
        conditions,
        finite_handles,
        infinite_handles,
        srw_locks,
        deadlines,
        unknown,
    });

    var shown: usize = 0;
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (thread.status != .blocked or shown == limit) continue;
        shown += 1;
        const cause = classifyWindowsBlockedThread(thread);
        const finding = classifyWindowsBlockedFinding(self, thread);
        const wait_site = windowsWaitCostSiteForThread(self, thread);
        var target_text: [128]u8 = undefined;
        const target = describeWindowsWaitTarget(self, thread.blocked_wait_handle, &target_text);
        const join = windowsJoinVerdict(self, thread.blocked_wait_handle);
        const blocked_age_steps = if (thread.blocked_since_total_steps == 0)
            0
        else
            process_impl_run_reporting.totalInterpretedSteps(self) -| thread.blocked_since_total_steps;
        const blocked_age_ticks = if (thread.blocked_since_guest_ticks == 0)
            0
        else
            process_impl_lifecycle.windowsGuestClockTicks(self) -| thread.blocked_since_guest_ticks;
        const object_kind = if (thread.blocked_wait_handle != 0)
            process_impl_windows_sync.windowsWaitObjectKindName(self, thread.blocked_wait_handle)
        else
            "none";
        const readiness = if (thread.blocked_wait_handle == 0)
            "not_applicable"
        else if (process_impl_windows_sync.windowsWaitObjectReady(self, thread.blocked_wait_handle)) |ready|
            if (ready) "ready" else "not_ready"
        else
            "unmodeled";
        const last_import = if (thread.last_import_len != 0) thread.lastImportText() else "<none>";
        const site_classification = if (wait_site) |site| __process_wait_cost.classify(site.*) else .no_data;
        const site_key = if (wait_site) |site| site.key else 0;
        const site_waits = if (wait_site) |site| site.waits else 0;
        const site_signals = if (wait_site) |site| site.signals else 0;
        const site_timeouts = if (wait_site) |site| site.timed_out else 0;
        __process_log.info("PE64 BLOCKED WAIT DIAGNOSTICS:   slot={d} thread=0x{x} name='{s}' cause={s} finding={s} priority={d} wait_handle=0x{x} kind={s} readiness={s}{s} join={s} age_steps={d} age_ticks={d} condition=0x{x} mutex=0x{x} lock=0x{x} timeout_ms={d} deadline_ticks={d} last_import={s} last_import_step={d} thread_steps={d} wait_site=0x{x} site_classification={s} site_waits={d} site_signals={d} site_timeouts={d} action={s} finding_action={s}", .{
            index,
            thread.handle,
            if (thread.name_len != 0) thread.nameText() else "<unnamed>",
            cause.label(),
            finding.label(),
            finding.priority(),
            thread.blocked_wait_handle,
            object_kind,
            readiness,
            target,
            join,
            blocked_age_steps,
            blocked_age_ticks,
            thread.blocked_condition,
            thread.blocked_condition_mutex,
            thread.blocked_srw_lock,
            thread.blocked_wait_timeout,
            thread.blocked_wait_deadline,
            last_import,
            thread.last_import_step,
            process_impl_lifecycle.windowsGuestThreadSteps(self, thread),
            site_key,
            site_classification.label(),
            site_waits,
            site_signals,
            site_timeouts,
            cause.action(),
            finding.action(),
        });
    }
    if (shown != blocked) {
        __process_log.info("PE64 BLOCKED WAIT DIAGNOSTICS:   {d} blocked thread(s) omitted after bounded sample of {d}; aggregate counts above remain complete", .{ blocked - shown, limit });
    }
}

pub fn reportWindowsWaitFindings(self: *ElfState) void {
    var blocked: usize = 0;
    var liveness_blocks: usize = 0;
    var cost_blocks: usize = 0;
    var expected_blocks: usize = 0;
    var expected_deadlines: usize = 0;
    var periodic_polls: usize = 0;
    var active_join_chains: usize = 0;
    var join_targets_not_ready: usize = 0;
    var join_cycles: usize = 0;
    var conditions_without_signal: usize = 0;
    var condition_producers_pending: usize = 0;
    var timeout_hotspots: usize = 0;
    var producers_not_ready: usize = 0;
    var active_wait_contexts: usize = 0;
    var locks_pending: usize = 0;
    var ready_but_blocked: usize = 0;
    var missing_models: usize = 0;

    for (self.windows_guest_threads) |*thread| {
        if (thread.status != .blocked) continue;
        blocked += 1;
        const finding = classifyWindowsBlockedFinding(self, thread);
        if (finding.isLivenessFinding()) liveness_blocks += 1;
        if (finding == .timeout_hotspot or finding == .periodic_timeout_poll) cost_blocks += 1;
        if (finding.isExpected()) expected_blocks += 1;
        switch (finding) {
            .expected_deadline => expected_deadlines += 1,
            .periodic_timeout_poll => periodic_polls += 1,
            .active_join_chain => active_join_chains += 1,
            .join_target_not_ready => join_targets_not_ready += 1,
            .join_cycle => join_cycles += 1,
            .unsignalled_condition => conditions_without_signal += 1,
            .condition_producer_pending => condition_producers_pending += 1,
            .timeout_hotspot => timeout_hotspots += 1,
            .producer_not_ready => producers_not_ready += 1,
            .active_wait_with_history => active_wait_contexts += 1,
            .lock_owner_pending => locks_pending += 1,
            .ready_but_blocked => ready_but_blocked += 1,
            .missing_wait_model => missing_models += 1,
        }
    }

    var site_liveness: usize = 0;
    var site_cost: usize = 0;
    var site_expected: usize = 0;
    var site_healthy: usize = 0;
    for (self.windows_wait_cost.sites[0..self.windows_wait_cost.count]) |site| {
        const classification = __process_wait_cost.classify(site);
        if (classification.isActionable()) site_liveness += 1;
        if (classification.isCostHotspot()) site_cost += 1;
        if (classification == .expected_deadline) site_expected += 1;
        if (classification == .healthy) site_healthy += 1;
    }

    if (blocked == 0 and self.windows_wait_cost.count == 0) return;
    reportWindowsWaitEscalations(self);
    __process_log.info("PE64 WAIT FINDINGS: blocked={d} liveness_blocks={d} cost_blocks={d} expected_blocks={d} wait_sites={d} site_liveness={d} site_cost={d} site_expected={d} site_healthy={d}; liveness findings can stop progress, cost findings explain slowdown, expected findings are not defects", .{
        blocked,
        liveness_blocks,
        cost_blocks,
        expected_blocks,
        self.windows_wait_cost.count,
        site_liveness,
        site_cost,
        site_expected,
        site_healthy,
    });
    if (self.windows_wait_unsignalled_escalations != 0 or self.windows_wait_timeout_hotspot_escalations != 0) {
        __process_log.info("PE64 WAIT ESCALATIONS: unsignalled_condition={d} timeout_hotspot={d}; each count is a bounded forensic trigger, not a synthetic wake or success result", .{
            self.windows_wait_unsignalled_escalations,
            self.windows_wait_timeout_hotspot_escalations,
        });
    }
    __process_log.info("PE64 WAIT FINDINGS: blocked_by_class expected_deadline={d} periodic_poll={d} active_join_chain={d} join_target_not_ready={d} join_cycle={d} unsignalled_condition={d} condition_producer_pending={d} timeout_hotspot={d} producer_not_ready={d} active_wait_with_history={d} lock_owner_pending={d} ready_but_blocked={d} missing_wait_model={d}; ranked entries below include the exact waiter, object, last import, and next action", .{
        expected_deadlines,
        periodic_polls,
        active_join_chains,
        join_targets_not_ready,
        join_cycles,
        conditions_without_signal,
        condition_producers_pending,
        timeout_hotspots,
        producers_not_ready,
        active_wait_contexts,
        locks_pending,
        ready_but_blocked,
        missing_models,
    });

    var selected_threads = [_]bool{false} ** __process_MAX_WINDOWS_GUEST_THREADS;
    var shown_threads: usize = 0;
    while (shown_threads < 8) : (shown_threads += 1) {
        var best_index: ?usize = null;
        var best_priority: u8 = 0;
        var best_age: u64 = 0;
        for (self.windows_guest_threads, 0..) |*thread, index| {
            if (thread.status != .blocked or selected_threads[index]) continue;
            const finding = classifyWindowsBlockedFinding(self, thread);
            const age = if (thread.blocked_since_total_steps == 0)
                0
            else
                process_impl_run_reporting.totalInterpretedSteps(self) -| thread.blocked_since_total_steps;
            if (best_index == null or finding.priority() > best_priority or
                (finding.priority() == best_priority and age > best_age))
            {
                best_index = index;
                best_priority = finding.priority();
                best_age = age;
            }
        }
        const index = best_index orelse break;
        selected_threads[index] = true;
        const thread = &self.windows_guest_threads[index];
        const finding = classifyWindowsBlockedFinding(self, thread);
        var target_text: [128]u8 = undefined;
        const target = describeWindowsWaitTarget(self, thread.blocked_wait_handle, &target_text);
        const join = windowsJoinVerdict(self, thread.blocked_wait_handle);
        const object_kind = if (thread.blocked_wait_handle != 0)
            process_impl_windows_sync.windowsWaitObjectKindName(self, thread.blocked_wait_handle)
        else
            "none";
        const readiness = if (thread.blocked_wait_handle == 0)
            "not_applicable"
        else if (process_impl_windows_sync.windowsWaitObjectReady(self, thread.blocked_wait_handle)) |ready|
            if (ready) "ready" else "not_ready"
        else
            "unmodeled";
        const last_import = if (thread.last_import_len != 0) thread.lastImportText() else "<none>";
        __process_log.info("PE64 WAIT FINDINGS:   blocked_rank={d} slot={d} class={s} priority={d} thread=0x{x} name='{s}' age_steps={d} wait_handle=0x{x} kind={s} readiness={s}{s} join={s} condition=0x{x} lock=0x{x} timeout_ms={d} deadline_ticks={d} last_import={s} last_import_step={d} thread_steps={d} action={s}", .{
            shown_threads + 1,
            index,
            finding.label(),
            finding.priority(),
            thread.handle,
            if (thread.name_len != 0) thread.nameText() else "<unnamed>",
            best_age,
            thread.blocked_wait_handle,
            object_kind,
            readiness,
            target,
            join,
            thread.blocked_condition,
            thread.blocked_srw_lock,
            thread.blocked_wait_timeout,
            thread.blocked_wait_deadline,
            last_import,
            thread.last_import_step,
            process_impl_lifecycle.windowsGuestThreadSteps(self, thread),
            finding.action(),
        });
        if (process_impl_windows_sync.windowsWaitObjectIndex(self, thread.blocked_wait_handle)) |object_index| {
            const object = &self.windows_wait_objects[object_index];
            var creator_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            var signal_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            __process_log.info("PE64 WAIT OBJECT PROVENANCE: waiter=0x{x} wait_handle=0x{x} wait_import={s} wait_step={d} object_kind={s} signaled={} manual_reset={} creator_thread=0x{x} creator_rip=0x{x} creator_at={s} created_step={d} signal_count={d} last_signal_thread=0x{x} last_signal_rip=0x{x} last_signal_at={s} last_signal_step={d}", .{
                thread.handle,
                object.handle,
                last_import,
                thread.last_import_step,
                @tagName(object.kind),
                object.signaled,
                object.manual_reset,
                object.creator_thread,
                object.creator_rip,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, object.creator_rip, &creator_text),
                object.created_step,
                object.signal_count,
                object.last_signal_thread,
                object.last_signal_rip,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, object.last_signal_rip, &signal_text),
                object.last_signal_step,
            });
        }
    }

    var selected_sites = [_]bool{false} ** __process_wait_cost.Ledger.capacity;
    var shown_sites: usize = 0;
    while (shown_sites < 8) : (shown_sites += 1) {
        var best_index: ?usize = null;
        var best_priority: u8 = 0;
        var best_timeout_ticks: u64 = 0;
        var best_waits: u64 = 0;
        for (self.windows_wait_cost.sites[0..self.windows_wait_cost.count], 0..) |site, index| {
            if (selected_sites[index]) continue;
            const classification = __process_wait_cost.classify(site);
            if (best_index == null or classification.priority() > best_priority or
                (classification.priority() == best_priority and site.timed_out_ticks > best_timeout_ticks) or
                (classification.priority() == best_priority and site.timed_out_ticks == best_timeout_ticks and site.waits > best_waits))
            {
                best_index = index;
                best_priority = classification.priority();
                best_timeout_ticks = site.timed_out_ticks;
                best_waits = site.waits;
            }
        }
        const index = best_index orelse break;
        selected_sites[index] = true;
        const site = self.windows_wait_cost.sites[index];
        const classification = __process_wait_cost.classify(site);
        const timeout_percent = if (site.waits == 0)
            0
        else
            @min(@as(u64, 100), (site.timed_out *| 100) / site.waits);
        const timeout_tick_percent = if (site.total_ticks == 0)
            0
        else
            @min(@as(u64, 100), (site.timed_out_ticks *| 100) / site.total_ticks);
        __process_log.info("PE64 WAIT FINDINGS:   site_rank={d} key=0x{x} kind={s} class={s} priority={d} waits={d} active={d} signaled={d} timeouts={d} ({d}%) timeout_ticks={d} ({d}%) signals={d} timeout_ms={d} max_ticks={d} max_overshoot_ticks={d} first_step={d} last_step={d} first_ticks={d} last_ticks={d} last_signal_step={d} last_signal_thread=0x{x} last_signal_rip=0x{x} action={s}", .{
            shown_sites + 1,
            site.key,
            site.kind.label(),
            classification.label(),
            classification.priority(),
            site.waits,
            site.active,
            site.signaled,
            site.timed_out,
            timeout_percent,
            site.timed_out_ticks,
            timeout_tick_percent,
            site.signals,
            site.last_timeout_milliseconds,
            site.max_ticks,
            site.max_timeout_overshoot_ticks,
            site.first_step,
            site.last_step,
            site.first_ticks,
            site.last_ticks,
            site.last_signal_step,
            site.last_signal_thread_handle,
            site.last_signal_rip,
            classification.action(),
        });
    }
}

pub fn reportWindowsUpstreamWaitPriority(self: *const ElfState) void {
    var blocked: usize = 0;
    var actionable: usize = 0;
    var unknown: usize = 0;
    var conditions: usize = 0;
    var srw_locks: usize = 0;
    var finite_handles: usize = 0;
    var finite_pending: usize = 0;
    var timeout_hotspots: usize = 0;
    var periodic_polls: usize = 0;
    var producer_handles_pending: usize = 0;
    var unready_joins: usize = 0;
    var join_cycles: usize = 0;
    var active_join_chains: usize = 0;
    var active_wait_contexts: usize = 0;
    var ready_but_blocked: usize = 0;
    var deadlines: usize = 0;
    var oldest_age_steps: u64 = 0;
    var oldest_thread: u64 = 0;

    for (self.windows_guest_threads) |*thread| {
        if (thread.status != .blocked) continue;
        blocked += 1;
        const finding = classifyWindowsBlockedFinding(self, thread);
        if (finding.isLivenessFinding()) actionable += 1;
        if (finding == .timeout_hotspot) timeout_hotspots += 1;
        if (finding == .periodic_timeout_poll) periodic_polls += 1;
        const cause = classifyWindowsBlockedThread(thread);
        switch (cause) {
            .unknown => unknown += 1,
            .condition, .timed_condition => conditions += @intFromBool(cause == .condition),
            .srw_lock => srw_locks += 1,
            .finite_handle => {
                finite_handles += 1;
                if (finding == .producer_not_ready) finite_pending += 1;
            },
            .deadline => deadlines += 1,
            .infinite_handle => {},
        }

        const age_steps = if (thread.blocked_since_total_steps == 0)
            0
        else
            process_impl_run_reporting.totalInterpretedSteps(self) -| thread.blocked_since_total_steps;
        if (age_steps > oldest_age_steps) {
            oldest_age_steps = age_steps;
            oldest_thread = thread.handle;
        }

        if (cause == .infinite_handle) {
            const join = windowsJoinVerdict(self, thread.blocked_wait_handle);
            const active_chain = __process_std.mem.eql(u8, join, "active_target") or
                __process_std.mem.eql(u8, join, "chain_reaches_active_target");
            if (active_chain) {
                active_join_chains += 1;
            } else if (__process_std.mem.eql(u8, join, "join_cycle") or
                __process_std.mem.eql(u8, join, "join_chain_too_deep"))
            {
                join_cycles += 1;
            } else if (!__process_std.mem.eql(u8, join, "not_thread_join")) {
                // Only a thread object is a join. Other kernel handles
                // must not inflate the join count merely because their
                // current state is not ready.
                if (process_impl_windows_sync.windowsWaitObjectReady(self, thread.blocked_wait_handle)) |ready| {
                    if (!ready) unready_joins += 1;
                } else {
                    unready_joins += 1;
                }
            } else switch (finding) {
                .producer_not_ready => producer_handles_pending += 1,
                .active_wait_with_history => active_wait_contexts += 1,
                .ready_but_blocked => ready_but_blocked += 1,
                else => {},
            }
        }
    }

    var timed_waits: u64 = 0;
    var timed_timeouts: u64 = 0;
    var timed_ticks: u64 = 0;
    var timed_total_ticks: u64 = 0;
    for (self.windows_wait_cost.sites[0..self.windows_wait_cost.count]) |site| {
        if (site.kind != .timed_condition) continue;
        timed_waits +|= site.waits;
        timed_timeouts +|= site.timed_out;
        timed_ticks +|= site.timed_out_ticks;
        timed_total_ticks +|= site.total_ticks;
    }
    const timeout_percent = if (timed_waits == 0)
        0
    else
        @min(@as(u64, 100), (timed_timeouts *| 100) / timed_waits);
    const timeout_tick_percent = if (timed_total_ticks == 0)
        0
    else
        @min(@as(u64, 100), (timed_ticks *| 100) / timed_total_ticks);
    if (blocked == 0 and timed_waits == 0) return;

    const verdict = if (unknown != 0)
        "missing_wait_model"
    else if (ready_but_blocked != 0)
        "ready_but_blocked"
    else if (join_cycles != 0)
        "join_cycle_or_depth"
    else if (unready_joins != 0)
        "join_target_not_ready"
    else if (conditions != 0 or srw_locks != 0)
        "unsignalled_condition_or_lock"
    else if (producer_handles_pending != 0 or finite_pending != 0)
        "producer_or_handle_pending"
    else
        "no_unresolved_upstream_wait";
    __process_log.info("PE64 UPSTREAM WAIT PRIORITY: verdict={s} blocked={d} actionable={d} unknown={d} condition={d} srw_lock={d} finite_handle={d} finite_pending={d} timeout_hotspots={d} periodic_polls={d} infinite_handle_pending={d} infinite_join_unready={d} join_cycles={d} active_join_chains={d} active_wait_contexts={d} ready_but_blocked={d} expected_deadlines={d} oldest_blocked_steps={d} oldest_thread=0x{x} timed_condition_timeouts={d}/{d} ({d}%) timeout_guest_ticks={d}/{d} ({d}%); screen validity is downstream of these waits, so resolve this verdict before interpreting SCREEN VALIDITY CHAIN", .{
        verdict,
        blocked,
        actionable,
        unknown,
        conditions,
        srw_locks,
        finite_handles,
        finite_pending,
        timeout_hotspots,
        periodic_polls,
        producer_handles_pending,
        unready_joins,
        join_cycles,
        active_join_chains,
        active_wait_contexts,
        ready_but_blocked,
        deadlines,
        oldest_age_steps,
        oldest_thread,
        timed_timeouts,
        timed_waits,
        timeout_percent,
        timed_ticks,
        timed_total_ticks,
        timeout_tick_percent,
    });
}

pub fn reportWindowsWaitCost(self: *const ElfState) void {
    const ledger = &self.windows_wait_cost;
    if (ledger.count == 0 and ledger.dropped_sites == 0 and ledger.unmatched_signals == 0) return;
    var waits: u64 = 0;
    var active: u64 = 0;
    var signals: u64 = 0;
    var signaled: u64 = 0;
    var timeouts: u64 = 0;
    var timeout_ticks: u64 = 0;
    var total_ticks: u64 = 0;
    var max_ticks: u64 = 0;
    var max_overshoot: u64 = 0;
    var site_liveness: u64 = 0;
    var site_cost: u64 = 0;
    var site_expected: u64 = 0;
    for (ledger.sites[0..ledger.count]) |site| {
        waits +|= site.waits;
        active +|= site.active;
        signals +|= site.signals;
        signaled +|= site.signaled;
        timeouts +|= site.timed_out;
        timeout_ticks +|= site.timed_out_ticks;
        total_ticks +|= site.total_ticks;
        max_ticks = @max(max_ticks, site.max_ticks);
        max_overshoot = @max(max_overshoot, site.max_timeout_overshoot_ticks);
        const classification = __process_wait_cost.classify(site);
        if (classification.isActionable()) site_liveness +|= 1;
        if (classification.isCostHotspot()) site_cost +|= 1;
        if (classification == .expected_deadline) site_expected +|= 1;
    }
    const timeout_percent = if (waits == 0) 0 else @min(@as(u64, 100), (timeouts *| 100) / waits);
    const timeout_tick_percent = if (total_ticks == 0) 0 else @min(@as(u64, 100), (timeout_ticks *| 100) / total_ticks);
    __process_log.info("PE64 WAIT COST: sites={d} waits={d} active={d} signaled={d} timeouts={d} ({d}%) signals={d} unmatched_signals={d} total_guest_ticks={d} timeout_guest_ticks={d} ({d}%) max_wait_ticks={d} max_timeout_overshoot_ticks={d} classified(liveness/cost/expected)={d}/{d}/{d} dropped_sites={d} dropped_events={d}; timeout share is the direct poll/blocked-wait cost, not a liveness verdict", .{
        ledger.count,
        waits,
        active,
        signaled,
        timeouts,
        timeout_percent,
        signals,
        ledger.unmatched_signals,
        total_ticks,
        timeout_ticks,
        timeout_tick_percent,
        max_ticks,
        max_overshoot,
        site_liveness,
        site_cost,
        site_expected,
        ledger.dropped_sites,
        ledger.dropped_events,
    });
    for (ledger.sites[0..ledger.count]) |site| {
        if (site.waits == 0 and site.signals == 0 and site.active == 0) continue;
        const site_timeout_percent = if (site.waits == 0) 0 else @min(@as(u64, 100), (site.timed_out *| 100) / site.waits);
        const site_timeout_tick_percent = if (site.total_ticks == 0)
            0
        else
            @min(@as(u64, 100), (site.timed_out_ticks *| 100) / site.total_ticks);
        const classification = __process_wait_cost.classify(site);
        __process_log.info("PE64 WAIT COST:   key=0x{x} kind={s} waits={d} active={d} signaled={d} timeouts={d} ({d}%) signals={d} total_ticks={d} timeout_ticks={d} ({d}%) max_ticks={d} max_overshoot_ticks={d} first_step={d} last_step={d} last_signal_step={d} last_timeout_step={d} timeout_ms={d} classification={s} action={s}", .{
            site.key,
            site.kind.label(),
            site.waits,
            site.active,
            site.signaled,
            site.timed_out,
            site_timeout_percent,
            site.signals,
            site.total_ticks,
            site.timed_out_ticks,
            site_timeout_tick_percent,
            site.max_ticks,
            site.max_timeout_overshoot_ticks,
            site.first_step,
            site.last_step,
            site.last_signal_step,
            site.last_timeout_step,
            site.last_timeout_milliseconds,
            classification.label(),
            classification.action(),
        });
    }
}

pub fn reportGuestTitleThreadForWall(self: *const ElfState) void {
    const interpreted = process_impl_run_reporting.totalInterpretedSteps(self);
    var found = false;
    for (self.windows_guest_threads, 0..) |*thread, index| {
        if (thread.status == .vacant or !thread.entered_xenia_title) continue;
        found = true;
        var where: [__process_guest_symbol_text_bytes]u8 = undefined;
        const share = if (interpreted == 0) 0 else @divTrunc(process_impl_lifecycle.windowsGuestThreadSteps(self, thread) *| 100, interpreted);
        __process_log.info("PE64 GUEST OUTPUT CHAIN:   the title runs on thread '{s}' (handle=0x{x}), which is {s}, holds {d}% of the run, and is at {s} rip=0x{x}", .{
            if (thread.name_len != 0) thread.nameText() else "<unnamed by the guest>",
            thread.handle,
            @tagName(thread.status),
            share,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, windowsGuestThreadRip(self, index), &where),
            windowsGuestThreadRip(self, index),
        });
        if (thread.code.isSpin()) {
            const bounds = thread.code.recentBounds().?;
            __process_log.info("PE64 GUEST OUTPUT CHAIN:   and it is spinning inside [0x{x},0x{x}]; PE64 SPIN ANATOMY names the address it polls, and that address - not the stage below - is the thing to make change", .{
                bounds.low,
                bounds.high,
            });
        } else if (thread.status == .blocked) {
            __process_log.info("PE64 GUEST OUTPUT CHAIN:   and it is blocked on wait=0x{x} with timeout={d}; a title parked on a wait cannot reach the stage above it, and whoever owns that object is the finding", .{
                thread.blocked_wait_handle,
                thread.blocked_wait_timeout,
            });
        }
    }
    if (!found) {
        __process_log.info("PE64 GUEST OUTPUT CHAIN:   no thread has entered XThread::Execute, so no thread is running translated PowerPC and the wall's owner has not started", .{});
    }
}

pub fn guestMilestoneActivity(self: *const ElfState, mangled: []const u8) __process_GuestMilestoneActivity {
    const index = __process_xenia_guest_milestone_map.indexOf(mangled) orelse
        return .{ .hits = 0, .last_step = 0, .armed = false };
    return .{
        .hits = self.guest_milestone_hits[index],
        .last_step = self.guest_milestone_last_step[index],
        .armed = self.guest_milestone_addresses[index] != 0,
    };
}

pub fn guestMilestoneActivityAny(
    self: *const ElfState,
    comptime primary: []const u8,
    comptime alternate: []const u8,
) struct { hits: u64, last_step: u64, armed: bool } {
    const first = guestMilestoneActivity(self, primary);
    const second = guestMilestoneActivity(self, alternate);
    return .{
        .hits = first.hits +| second.hits,
        .last_step = @max(first.last_step, second.last_step),
        .armed = first.armed or second.armed,
    };
}

pub fn reportGuestCodeProgress(self: *const ElfState) void {
    const defined = guestMilestoneActivity(self, "_ZN2xe3cpu3ppc11PPCFrontend14DefineFunctionEPNS0_13GuestFunctionEj");
    const resolved = guestMilestoneActivity(self, "_ZN2xe3cpu9Processor15ResolveFunctionEj");
    const trapped = guestMilestoneActivity(self, "_ZN2xe3cpu7backend3x6414TrapDebugBreakEPvy");
    const bad_pm4 = guestMilestoneActivity(self, "_ZN2xe3gpu16CommandProcessor22HitUnimplementedOpcodeEjj");
    if (!defined.armed and !resolved.armed and !trapped.armed) {
        __process_log.info("PE64 GUEST CODE PROGRESS: not observable; this image names none of Xenia's PowerPC translation entry points, so nothing here can say whether the title is reaching new code", .{});
        return;
    }
    __process_log.info("PE64 GUEST CODE PROGRESS: guest functions translated={d} guest addresses resolved={d}; a translation is the title reaching code it has never run, so this count is a progress axis a spin cannot advance", .{
        defined.hits,
        resolved.hits,
    });
    if (defined.hits == 0) {
        __process_log.info("PE64 GUEST CODE PROGRESS:   not one guest function was translated. Either no title code has run at all, or this build translates ahead of time and the axis does not apply here; check XThread_Execute in the chain above before reading this as a stall", .{});
    } else {
        const interpreted = process_impl_run_reporting.totalInterpretedSteps(self);
        const quiet = interpreted -| defined.last_step;
        const share = if (interpreted == 0) @as(u64, 0) else quiet * 100 / interpreted;
        if (share >= 25) {
            __process_log.info("PE64 GUEST CODE PROGRESS:   the last translation was at step {d}, {d} step(s) and {d}% of the run ago. The title has been executing code it already had for that whole span: it is looping, not advancing, and the loop is the finding rather than whatever it last asked the kernel for", .{
                defined.last_step,
                quiet,
                share,
            });
        } else {
            __process_log.info("PE64 GUEST CODE PROGRESS:   the last translation was at step {d}, {d} step(s) ago ({d}% of the run). The title is still reaching code it has not run before, so it is advancing through its own program and a stage that reads unmet is one it has not got to yet", .{
                defined.last_step,
                quiet,
                share,
            });
        }
    }
    // A guest trap is the title reporting a failure of its own, and it is
    // the only witness in the table whose zero is the good outcome.
    if (trapped.armed) {
        if (trapped.hits == 0) {
            __process_log.info("PE64 GUEST CODE PROGRESS:   guest traps=0; the title has not executed a PowerPC trap instruction, so it has not hit an assertion of its own", .{});
        } else {
            __process_log.warn("PE64 GUEST CODE PROGRESS:   guest traps={d}, last at step {d}. A PowerPC trap is what the title's own assertions compile to: it has decided something is wrong. Whatever it checked is upstream of every unmet stage below it", .{
                trapped.hits,
                trapped.last_step,
            });
        }
    }
    if (bad_pm4.armed and bad_pm4.hits != 0) {
        __process_log.warn("PE64 GUEST CODE PROGRESS:   the command processor hit {d} PM4 opcode(s) it cannot decode, last at step {d}; that is a gap in this Xenia build, not in the title", .{
            bad_pm4.hits,
            bad_pm4.last_step,
        });
    }
}

pub fn reportGuestAccessViolations(self: *const ElfState) void {
    const table = self.guest_page_protection.stats();
    var handler_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    __process_log.info("PE64 GUEST ACCESS VIOLATIONS: protected pages no_access={d} read_only={d} from {d} request(s) (guard={d} unmodelled_values={d} outside_window={d}); vectored handler={s}", .{
        table.no_access_pages,
        table.read_only_pages,
        table.requests,
        self.guest_page_protection_guard_requests,
        self.guest_page_protection_unmodelled_values,
        table.requests_outside_window,
        if (self.windows_vectored_exception_handler == 0)
            "none registered"
        else
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, self.windows_vectored_exception_handler, &handler_text),
    });
    // The one-number test for Xenia's GPU write watch. It protects
    // physical-heap pages PAGE_READONLY so a title's store to a texture
    // or a vertex buffer faults and `TriggerCallbacks` re-uploads it.
    // Every such request arrives through ntdll's
    // `NtProtectVirtualMemory`, never `VirtualProtect`, because Xenia
    // builds with `XE_USE_NTDLL_FUNCTIONS`. While that name returned
    // STATUS_SUCCESS and recorded nothing, this counter read zero for
    // the whole project's history and the GPU drew from stale memory.
    __process_log.info("PE64 GPU WRITE WATCH: read_only_pages={d} write_faults={d} unresolved_retries={d} state={s}; Xenia protects physical-heap pages read-only to learn what the guest rewrote, and it asks through ntdll's NtProtectVirtualMemory. Zero read-only pages means no store can fault, so the GPU keeps drawing from the copy of guest memory it uploaded first - the shape of banded, stale geometry. unresolved_retries counts faults the handler asked to retry without clearing the protection, each of which would have been an unbreakable loop", .{
        table.read_only_pages,
        self.guest_access_violation_writes,
        self.guest_access_violation_unresolved_retries,
        if (table.read_only_pages != 0 or self.guest_access_violation_writes > 1024)
            "armed"
        else if (self.wide_access_watch_enabled)
            "never armed (no read-only page was ever recorded)"
        else
            "never armed, and wide accesses are unwatched (ROSETTE_X64_WIDE_ACCESS_WATCH=0)",
    });
    __process_log.info("PE64 GUEST ACCESS VIOLATIONS:   raised={d} (reads={d} writes={d}) dispatched={d} handled={d} unhandled={d} no_handler={d} frame_refused={d} nesting_refused={d} host_side_borrows_of_protected_pages={d} (bytes={d}); the last pair counts import shims, CRT copies and file reads writing into pages the guest protected without a fault, which a write watch on those pages never sees", .{
        self.guest_access_violations_raised,
        self.guest_access_violation_reads,
        self.guest_access_violation_writes,
        self.guest_access_violations_dispatched,
        self.guest_access_violations_handled,
        self.guest_access_violations_unhandled,
        self.guest_access_violations_without_handler,
        self.guest_access_violations_frame_refused,
        self.guest_access_violations_nesting_refused,
        self.guest_protected_bulk_borrows,
        self.guest_protected_bulk_borrow_bytes,
    });
    for (self.guest_access_violation_sites[0..self.guest_access_violation_site_count]) |*site| {
        var rip_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        __process_log.info("PE64 GUEST ACCESS VIOLATIONS:   page=0x{x} {s} reads={d} writes={d} handled={d} unhandled={d} first_step={d} last_offset=0x{x} last_value=0x{x} last_rip=0x{x} ({s})", .{
            site.page,
            site.protection.label(),
            site.reads,
            site.writes,
            site.handled,
            site.unhandled,
            site.first_step,
            site.last_offset,
            site.last_value,
            site.last_rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, site.last_rip, &rip_text),
        });
    }
    if (self.guest_access_violation_site_overflow != 0) {
        __process_log.info("PE64 GUEST ACCESS VIOLATIONS:   {d} fault(s) on further pages were counted but not itemised", .{self.guest_access_violation_site_overflow});
    }

    const vectored = guestMilestoneActivity(self, "_ZN2xe24ExceptionHandlerCallbackEP19_EXCEPTION_POINTERS");
    const mmio = guestMilestoneActivity(self, "_ZN2xe3cpu11MMIOHandler17ExceptionCallbackEPNS_9ExceptionE");
    const write_thunk = guestMilestoneActivity(self, "_ZN2xe3gpu14GraphicsSystem18WriteRegisterThunkEPvPS1_jj");
    const read_thunk = guestMilestoneActivity(self, "_ZN2xe3gpu14GraphicsSystem17ReadRegisterThunkEPvPS1_j");
    const write_pointer = guestMilestoneActivity(self, "_ZN2xe3gpu16CommandProcessor18UpdateWritePointerEj");
    const primary = guestMilestoneActivityAny(
        self,
        "_ZN2xe3gpu16CommandProcessor20ExecutePrimaryBufferEjj",
        "_ZN2xe3gpu6vulkan22VulkanCommandProcessor20ExecutePrimaryBufferEjj",
    );
    if (!(mmio.armed or write_thunk.armed or read_thunk.armed or write_pointer.armed or primary.armed)) return;
    __process_log.info("PE64 GUEST ACCESS VIOLATIONS:   register delivery: faults_raised={d} -> dispatched={d} -> ExceptionHandlerCallback={d} -> MMIOHandler::ExceptionCallback={d} -> WriteRegisterThunk={d} (ReadRegisterThunk={d}) -> UpdateWritePointer={d} -> ExecutePrimaryBuffer(base/Vulkan)={d}", .{
        self.guest_access_violations_raised,
        self.guest_access_violations_dispatched,
        vectored.hits,
        mmio.hits,
        write_thunk.hits,
        read_thunk.hits,
        write_pointer.hits,
        primary.hits,
    });
    const direct_mmio = write_thunk.hits != 0 or read_thunk.hits != 0;
    const verdict: []const u8 = if (primary.hits != 0)
        "the register callback and command-processor path reached ExecutePrimaryBuffer (base or Vulkan override)"
    else if (write_pointer.hits != 0 and self.guest_access_violations_raised == 0)
        "direct MMIO callbacks reached UpdateWritePointer while ExecutePrimaryBuffer (base and Vulkan override) remained at zero; no interpreted access violation was needed, so the remaining wall is the GPU worker's write-pointer wake path"
    else if (direct_mmio and self.guest_access_violations_raised == 0)
        "direct MMIO callbacks handled register traffic without an interpreted access violation; page-protection fault counters are not this run's delivery path, and no write-pointer update was observed"
    else if (table.no_access_pages == 0)
        "no page was ever made no-access, so a register access cannot fault and cannot reach the register callbacks. Either the register block was never protected or its protection request was not recorded; the PAGE PROTECTION lines at start-up say which"
    else if (self.guest_access_violations_raised == 0)
        "register pages are protected and no interpreted access touched them: the title has not yet read or written a GPU register"
    else if (self.guest_access_violations_dispatched == 0)
        "protected accesses faulted but none was dispatched; no_handler, frame_refused and nesting_refused above say why"
    else if (vectored.armed and vectored.hits == 0)
        "faults were dispatched but not into ExceptionHandlerCallback, so the handler Rosette called is not the one that owns the register pages"
    else if (mmio.armed and mmio.hits == 0)
        "the vectored handler ran and never offered a fault to the MMIO handler"
    else if (write_thunk.hits == 0 and read_thunk.hits == 0)
        "the MMIO handler saw the faults and reached no register callback: the faulting instruction was not a load or store it can decode, or the address fell outside its ranges"
    else if (write_pointer.hits == 0)
        "register accesses reach the graphics system, and none of them moved the ring write pointer: the title has not yet asked the GPU to run anything"
    else if (primary.hits == 0)
        "the write pointer moved and the command processor did not execute the ring; from here the wall is Xenia's GPU thread"
    else
        "a register write travelled the whole path into the ring";
    __process_log.info("PE64 GUEST ACCESS VIOLATIONS:   verdict: {s}", .{verdict});
}

pub fn reportGuestLockContention(self: *const ElfState) void {
    var xbox_armed: usize = 0;
    var xbox_handled: u64 = 0;
    var xbox_fallbacks: u64 = 0;
    var xbox_jit_direct: u64 = 0;
    inline for (@typeInfo(__process_xbox_critical_section.Export).@"enum".fields) |field| {
        const api: __process_xbox_critical_section.Export = @enumFromInt(field.value);
        const index = @intFromEnum(api);
        if (self.xbox_critical_section_hooks.addresses[index] != 0) xbox_armed += 1;
        xbox_handled +|= self.xbox_critical_section_hooks.calls[index];
        xbox_fallbacks +|= self.xbox_critical_section_hooks.fallbacks[index];
        xbox_jit_direct +|= self.xbox_critical_section_hooks.jit_direct_calls[index];
        if (self.xbox_critical_section_hooks.addresses[index] != 0) {
            __process_log.info("PE64 XBOX CRITICAL SECTION BRIDGE: export={s} trampoline=0x{x} handled={d} native_fallbacks={d} jit_direct_observations={d}", .{
                api.name(),
                self.xbox_critical_section_hooks.addresses[index],
                self.xbox_critical_section_hooks.calls[index],
                self.xbox_critical_section_hooks.fallbacks[index],
                self.xbox_critical_section_hooks.jit_direct_calls[index],
            });
        }
    }
    const xbox = &self.xbox_critical_section_stats;
    const read = __process_xbox_critical_section.Stats.read;
    __process_log.info("PE64 XBOX CRITICAL SECTION BRIDGE: armed={d}/5 handled={d} native_fallbacks={d} jit_direct_observations={d} initialized={d} enters(acquired/recursed/counted)={d}/{d}/{d} waits(parked/granted/signalled/consumed)={d}/{d}/{d}/{d} try_failures={d} leave_mismatches={d} null_sections={d} synthetic_owners={d}; Xenia's lock protocol on the guest structure, decoded from each call's PPCContext (section=r3, result=r3): uncontended calls take no lock, a counted waiter parks in the scheduler, and a release hands the section to the longest parked waiter or leaves the embedded event set for one that has not parked yet", .{
        xbox_armed,
        xbox_handled,
        xbox_fallbacks,
        xbox_jit_direct,
        read(&xbox.initializations),
        read(&xbox.acquired),
        read(&xbox.recursed),
        read(&xbox.counted),
        read(&xbox.parks),
        read(&xbox.grants),
        read(&xbox.signals),
        read(&xbox.signals_consumed),
        read(&xbox.try_failures),
        read(&xbox.leave_mismatches),
        read(&xbox.null_sections),
        read(&xbox.synthetic_owners),
    });
    if (xbox_fallbacks != 0 and xbox_handled != 0) {
        __process_log.info("PE64 XBOX CRITICAL SECTION BRIDGE: {d} call(s) went to Xenia because their PPCContext or section had no host backing; Xenia faults on those exactly as it would without the bridge, so no section is shared between the two implementations", .{xbox_fallbacks});
    }
    var tracked: usize = 0;
    var contended: usize = 0;
    for (self.windows_srw_locks) |lock| {
        if (lock.address == 0) continue;
        tracked += 1;
        if (lock.contentions != 0) contended += 1;
    }
    __process_log.info("PE64 LOCK CONTENTION: srw_locks={d} contended={d} contentions={d} handoffs={d} directed={d}; a release hands an SRW lock to its longest waiter and schedules that waiter next, because under one cooperative interpreter a waiter woken to race for it loses to whichever thread is already running, and one left for the circular scan holds the lock while it waits its turn", .{
        tracked,
        contended,
        self.windows_srw_lock_contentions,
        self.windows_srw_handoffs,
        self.windows_srw_directed_handoffs,
    });
    var sections_held: usize = 0;
    for (self.windows_critical_sections) |section| {
        if (section.address != 0) sections_held += 1;
    }
    __process_log.info("PE64 CRITICAL SECTIONS: win32(enters/contentions/handoffs/untracked/release_mismatches)={d}/{d}/{d}/{d}/{d} xbox(acquired/recursed/counted/granted/leave_mismatches)={d}/{d}/{d}/{d}/{d} held_or_contended_now={d} high_water={d}/{d} native_conditions(waits/resumes/timeouts/unmodelled)={d}/{d}/{d}/{d}; Win32 sections keep a record while held or contended, Xbox sections keep their state in the guest structure", .{
        self.windows_critical_section_enters,
        self.windows_critical_section_contentions,
        self.windows_critical_section_handoffs,
        self.windows_critical_section_untracked,
        self.windows_critical_section_release_mismatches,
        read(&xbox.acquired),
        read(&xbox.recursed),
        read(&xbox.counted),
        read(&xbox.grants),
        read(&xbox.leave_mismatches),
        sections_held,
        self.windows_critical_section_high_water,
        self.windows_critical_sections.len,
        self.windows_native_condition_waits,
        self.windows_native_condition_resumes,
        self.windows_native_condition_timeouts,
        self.windows_native_condition_unmodelled,
    });
    var shown_sections: usize = 0;
    for (self.windows_critical_sections) |section| {
        if (shown_sections == 8) break;
        if (section.address == 0) continue;
        shown_sections += 1;
        var section_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        var owner_text: [96]u8 = undefined;
        __process_log.info("PE64 CRITICAL SECTIONS:   section=0x{x} ({s}) layout={s} owner={s} recursion={d} waiters={d} contentions={d} handoffs={d}", .{
            section.address,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, section.address, &section_text),
            if (section.critical_section_layout) |layout| @tagName(layout) else "unknown",
            process_impl_windows_sync.describeWindowsSrwOwner(self, section.owner_thread_id, &owner_text),
            section.recursion,
            process_impl_windows_sync.windowsSrwWaiterCount(self, section),
            section.contentions,
            section.handoffs,
        });
    }
    var shown: usize = 0;
    for (self.windows_srw_locks) |lock| {
        if (shown == 8) break;
        if (lock.address == 0) continue;
        const waiters = process_impl_windows_sync.windowsSrwWaiterCount(self, lock);
        if (lock.contentions == 0 and waiters == 0) continue;
        shown += 1;
        var lock_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        var owner_text: [96]u8 = undefined;
        const lock_name = process_impl_kernel_services.describeGuestAddressOrUnnamed(self, lock.address, &lock_text);
        __process_log.info("PE64 LOCK CONTENTION:   lock=0x{x} ({s}) owner={s} waiters={d} contentions={d} handoffs={d} acquire/release/mismatch={d}/{d}/{d} owner_since_step={d} last_acquire(thread/step)=0x{x}/{d} last_release(thread/step)=0x{x}/{d}", .{
            lock.address,
            lock_name,
            process_impl_windows_sync.describeWindowsSrwOwner(self, lock.owner_thread_id, &owner_text),
            waiters,
            lock.contentions,
            lock.handoffs,
            lock.acquire_calls,
            lock.release_calls,
            lock.release_mismatches,
            lock.owner_acquired_step,
            lock.last_acquire_thread_id,
            lock.last_acquire_step,
            lock.last_release_thread_id,
            lock.last_release_step,
        });
        if (__process_std.mem.startsWith(u8, lock_name, "_ZZN2xe22global_critical_region5mutexEvE12global_mutex") and
            process_impl_execution.guestMemoryConst(self, lock.address, 16) != null)
        {
            const xenia_owner = process_impl_guest_memory.read32(self, lock.address + 8);
            const xenia_recursion = process_impl_guest_memory.read32(self, lock.address + 12);
            __process_log.warn("PE64 XENIA GLOBAL MUTEX: srw_word=0x{x} bridge_owner_thread=0x{x} xenia_owner_thread=0x{x} xenia_recursion={d} waiters={d}; owner=0 and recursion=0 with a nonzero bridge owner means Rosetta missed the release, while nonzero Xenia fields mean its recursive unlock has not completed", .{
                process_impl_guest_memory.read64(self, lock.address),
                lock.owner_thread_id,
                xenia_owner,
                xenia_recursion,
                waiters,
            });
        }
        reportWindowsSrwOwnerStacks(self, lock);
        for (self.windows_guest_threads) |thread| {
            if (thread.thread_id == 0 or thread.thread_id != lock.owner_thread_id) continue;
            if (thread.status != .completed and thread.status != .failed) continue;
            __process_log.warn("PE64 LOCK CONTENTION:     held by a thread that has exited. Windows never releases an SRW lock for a dead owner, so every waiter on it is blocked for good; the owner's last kernel call and import say what it was doing when it left", .{});
        }
    }
}

pub fn reportWindowsSrwOwnerStacks(self: *const ElfState, lock: __process_WindowsSrwLock) void {
    if (lock.owner_thread_id == 0) return;
    if (!lock.owner_stack_sampled) __process_log.info("PE64 LOCK CONTENTION:     owner_stack lock=0x{x} at_acquire=not_sampled; current stack follows; ROSETTE_SRW_STACK_CAPTURE=all records every acquisition", .{lock.address});
    var current: [__process_windows_srw_owner_stack_depth]u64 = @splat(0);
    for (self.windows_guest_threads) |*thread| {
        if (thread.thread_id != lock.owner_thread_id) continue;
        if (thread.status == .completed or thread.status == .failed) break;
        process_impl_windows_sync.windowsGuestStackCodeAddresses(self, thread.context.regs.rsp, &current);
        break;
    }
    inline for (.{ "at_acquire", "now" }, 0..) |label, which| {
        const frames = if (which == 0) &lock.owner_stack else &current;
        for (frames, 0..) |address, depth| {
            if (address == 0) break;
            var text: [__process_guest_symbol_text_bytes]u8 = undefined;
            __process_log.info("PE64 LOCK CONTENTION:     owner_stack lock=0x{x} {s} depth={d} return=0x{x} at={s}", .{
                lock.address,
                label,
                depth,
                address,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, address, &text),
            });
        }
    }
}

pub fn reportGuestKernelCalls(self: *const ElfState) void {
    const census = &self.guest_kernel_calls;
    if (census.armed == 0) {
        __process_log.info("PE64 GUEST KERNEL CALLS: no export shim was armed this run, so the title's kernel traffic is unobservable; the arming line at start-up says why", .{});
        return;
    }
    const phase = census.furthest_phase;
    __process_log.info("PE64 GUEST KERNEL CALLS: {d} distinct export(s) entered out of {d} this build serves, {d} call(s) total; boot phase reached: {s}", .{
        census.distinct_entered,
        census.armed_trampolines,
        census.total_calls,
        phase.label(),
    });
    if (census.distinct_entered == 0) {
        __process_log.info("PE64 GUEST KERNEL CALLS:   the title has not made one kernel call. {s}", .{
            __process_xenia_kernel_shim_map.BootPhase.no_kernel_contact.advice(),
        });
        // The one way this whole census could be silently wrong, said out
        // loud so the next run settles it rather than inheriting it.
        __process_log.info("PE64 GUEST KERNEL CALLS:   this counts entry by call and by tail jump, at the registered trampoline's exact address. A translator that reaches its handler some third way - a computed dispatch that lands past the prologue, say - would read zero here while the title called constantly; the guest-code progress line above is the independent check on that", .{});
        if (census.forwarder_calls != 0) {
            __process_log.warn("PE64 GUEST KERNEL CALLS:   but {d} `_entry` forwarder call(s) were seen with no trampoline entry at all, which is impossible if the trampolines are what the guest reaches. The census is watching the wrong address and every zero above is unreliable", .{
                census.forwarder_calls,
            });
        }
    } else {
        // The two symbols answer the same question and are counted
        // apart, so their disagreement is readable rather than lost.
        if (census.forwarder_calls == 0) {
            __process_log.info("PE64 GUEST KERNEL CALLS:   no `_entry` forwarder was entered, so this build inlined every one of them into its trampolines; a census armed on the forwarders would have read zero for all {d} of these calls", .{
                census.total_calls,
            });
        } else if (census.forwarder_calls < census.total_calls) {
            const ratio_hundredths = @divTrunc(census.forwarder_calls *| 10_000, census.total_calls);
            __process_log.info("PE64 GUEST KERNEL CALLS:   {d} of {d} title call(s) crossed a retained out-of-line `_entry` body ({d}.{d}%); these are implementation-layout crossings, not failed exports or additional guest calls, and the remaining calls were inlined into their trampolines", .{
                census.forwarder_calls,
                census.total_calls,
                ratio_hundredths / 100,
                ratio_hundredths % 100,
            });
        }
        if (census.forwarder_calls != 0) {
            var top_forwarders: [8]?*const __process_kernel_call_census.Slot = [_]?*const __process_kernel_call_census.Slot{null} ** 8;
            const top_count = census.topForwarders(&top_forwarders);
            __process_log.info("PE64 GUEST KERNEL CALLS:   retained `_entry` body census (top {d}; a body is counted only for the calls that actually crossed it):", .{top_count});
            for (top_forwarders[0..top_count]) |entry| {
                const trampoline = census.findExportOfKind(entry.?.export_name, .trampoline);
                __process_log.info("PE64 GUEST KERNEL CALLS:     forwarder={s}!{s} crossings={d} trampoline_calls={d} subsystem={s}", .{
                    entry.?.module.moduleName(),
                    entry.?.export_name,
                    entry.?.hits,
                    if (trampoline) |slot| slot.hits else 0,
                    entry.?.subsystem.label(),
                });
            }
            if (top_count == 0) {
                __process_log.info("PE64 GUEST KERNEL CALLS:     no retained forwarder body has a nonzero hit count; the aggregate is from a stale/partial report and should be treated as inconsistent", .{});
            }
        }
        if (census.tail_jump_entries != 0) {
            __process_log.info("PE64 GUEST KERNEL CALLS:   {d} of {d} entries arrived by tail jump rather than call; that is the translator's dispatch, not the title's behaviour, and it is reported so a count that moves between builds has an explanation", .{
                census.tail_jump_entries,
                census.total_calls,
            });
        }
        __process_log.info("PE64 GUEST KERNEL CALLS:   {s}", .{phase.advice()});
        if (__process_xenia_kernel_shim_map.nextPhase(phase)) |next| {
            const progress = census.phaseProgress(next);
            __process_log.info("PE64 GUEST KERNEL CALLS:   the next phase is '{s}' and the title has called {d} of its {d} marker export(s) ({d} of them armed in this image); that phase is the one to make happen", .{
                next.label(),
                progress.called,
                progress.declared,
                progress.armed,
            });
        }
    }

    // Where the calls went. A reader looking for graphics wants to know
    // in one line whether any of the traffic was graphics at all.
    __process_log.info("PE64 GUEST KERNEL CALLS:   step accounting total_interpreted_steps={d} owner_steps={d} worker_steps={d}; every first_step/last_step uses the combined denominator", .{
        process_impl_run_reporting.totalInterpretedSteps(self),
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.windowsWorkerSteps(self),
    });
    const synchronization_exports = [_][]const u8{
        "RtlEnterCriticalSection",
        "RtlLeaveCriticalSection",
        "KeWaitForSingleObject",
        "KeWaitForMultipleObjects",
        "NtWaitForSingleObject",
        "NtWaitForMultipleObjects",
        "NtDelayExecution",
        "WaitForSingleObject",
        "WaitForMultipleObjects",
    };
    for (synchronization_exports) |export_name| {
        if (census.findExport(export_name)) |slot| {
            if (slot.hits != 0) {
                __process_log.info("PE64 GUEST SYNCHRONIZATION COST: export={s} calls={d} first_step={d} last_step={d} subsystem={s}; this is guest synchronization overhead, separate from Rosetta's blocked-wait ledger", .{
                    export_name,
                    slot.hits,
                    slot.first_step,
                    slot.last_step,
                    slot.subsystem.label(),
                });
            }
        }
    }
    const totals = census.subsystemTotals();
    inline for (@typeInfo(__process_xenia_kernel_shim_map.Subsystem).@"enum".fields) |field| {
        const subsystem: __process_xenia_kernel_shim_map.Subsystem = @enumFromInt(field.value);
        const total = totals[field.value];
        // A subsystem with nothing armed is not a fact about the title,
        // and one with no calls is only worth a row when the chain
        // depends on it - a zero there is the finding.
        if (total.armed != 0 and (total.calls != 0 or subsystem.feedsGuestOutput())) {
            __process_log.info("PE64 GUEST KERNEL CALLS:   {s:<15} armed={d:<4} entered={d:<4} calls={d}{s}", .{
                subsystem.label(),
                total.armed,
                total.distinct,
                total.calls,
                if (subsystem.feedsGuestOutput() and total.calls == 0)
                    "  <- the guest output chain is built entirely out of this subsystem and the title has not touched it"
                else
                    "",
            });
        }
    }

    // Every graphics export, called or not. This is the list a reader
    // needs when the wall belongs to the title: the ones with a count are
    // what it did ask for, and the zeros are what it has not asked for
    // yet.
    var video_armed: u32 = 0;
    for (census.slots) |slot| {
        if (slot.address == 0 or slot.subsystem != .video or slot.kind != .trampoline) continue;
        video_armed += 1;
    }
    if (video_armed != 0) {
        __process_log.info("PE64 GUEST KERNEL CALLS:   the {d} graphics export(s) this build serves, and what the title has asked of each:", .{video_armed});
        for (census.slots) |slot| {
            if (slot.address == 0 or slot.subsystem != .video or slot.kind != .trampoline) continue;
            if (slot.hits == 0) continue;
            __process_log.info("PE64 GUEST KERNEL CALLS:     {s:<46} calls={d} first_step={d} last_step={d}", .{
                slot.export_name,
                slot.hits,
                slot.first_step,
                slot.last_step,
            });
        }
        var uncalled: u32 = 0;
        for (census.slots) |slot| {
            if (slot.address == 0 or slot.subsystem != .video or slot.kind != .trampoline or slot.hits != 0) continue;
            uncalled += 1;
        }
        if (uncalled != 0) {
            __process_log.info("PE64 GUEST KERNEL CALLS:     never called ({d}):", .{uncalled});
            var line: [512]u8 = undefined;
            var used: usize = 0;
            var shutdown_only: u32 = 0;
            var optional_display_queries: u32 = 0;
            for (census.slots) |slot| {
                if (slot.address == 0 or slot.subsystem != .video or slot.kind != .trampoline or slot.hits != 0) continue;
                if (__process_std.mem.eql(u8, slot.export_name, "VdShutdownEngines")) {
                    shutdown_only += 1;
                } else if (__process_std.mem.eql(u8, slot.export_name, "VdSetDisplayModeOverride") or
                    __process_std.mem.eql(u8, slot.export_name, "VdQueryRealVideoMode") or
                    __process_std.mem.eql(u8, slot.export_name, "VdQueryVideoFlags") or
                    __process_std.mem.eql(u8, slot.export_name, "VdEnableDisableClockGating") or
                    __process_std.mem.eql(u8, slot.export_name, "VdGetGraphicsAsicID"))
                {
                    optional_display_queries += 1;
                }
                if (slot.export_name.len + 1 > line.len) continue;
                const needed = slot.export_name.len + @as(usize, if (used == 0) 0 else 1);
                if (used + needed > line.len) {
                    __process_log.info("PE64 GUEST KERNEL CALLS:       {s}", .{line[0..used]});
                    used = 0;
                }
                if (used != 0) {
                    line[used] = ' ';
                    used += 1;
                }
                @memcpy(line[used .. used + slot.export_name.len], slot.export_name);
                used += slot.export_name.len;
            }
            if (used != 0) __process_log.info("PE64 GUEST KERNEL CALLS:       {s}", .{line[0..used]});
            if (shutdown_only != 0) {
                __process_log.info("PE64 GUEST KERNEL CALLS:       {d} never-called graphics export(s) are shutdown-only (VdShutdownEngines); their zero is expected until the title tears the device down, not a live rendering gap", .{shutdown_only});
            }
            if (optional_display_queries != 0) {
                __process_log.info("PE64 GUEST KERNEL CALLS:       {d} never-called graphics export(s) are optional display/policy queries (mode override, physical mode, video flags, clock gating, ASIC identity); their zero does not block output when the run already crossed VdQueryVideoMode/VdSetDisplayMode/VdGetCurrentDisplayInformation/VdSwap", .{optional_display_queries});
            }
        }
    }

    // The narrative tail. What the title reached for last is where it
    // stopped, and for a guest whose own instructions Rosette cannot name
    // this is the only account of its progress that exists.
    if (census.distinct_entered != 0) {
        const shown = @min(@as(usize, 12), census.distinct_entered);
        __process_log.info("PE64 GUEST KERNEL CALLS:   the last {d} export(s) the title reached for, newest first; the top row is where it stopped making new kinds of request:", .{shown});
        var index: usize = 0;
        while (index < shown) : (index += 1) {
            const slot = census.nthLatestFirstEntry(index) orelse break;
            __process_log.info("PE64 GUEST KERNEL CALLS:     first_step={d:<12} last_step={d:<12} {s}!{s} [{s}] calls={d}", .{
                slot.first_step,
                slot.last_step,
                slot.module.moduleName(),
                slot.export_name,
                slot.subsystem.label(),
                slot.hits,
            });
        }
        if (census.busiest()) |busy| {
            __process_log.info("PE64 GUEST KERNEL CALLS:   busiest: {s} with {d} call(s); a kernel export entered far more than its neighbours is usually a poll, and a poll that never ends is the shape of a title waiting for something Rosette has not delivered", .{
                busy.export_name,
                busy.hits,
            });
        }
        const saturated_exports = census.saturatedCount();
        if (saturated_exports != 0) {
            __process_log.info("PE64 GUEST KERNEL CALLS:   {d} export(s) saturated after {d} calls each and left the translator's hook filter; their counts, the thread totals and the busiest row are lower bounds from that call on, while the Xbox critical-section, Xam input, VdSwap and file-request exports stay hooked", .{
                saturated_exports,
                __process_kernel_call_census.saturation_calls,
            });
        }
        if (census.slotAt(census.last_slot)) |latest| {
            const total_steps = process_impl_run_reporting.totalInterpretedSteps(self);
            const quiet = total_steps -| census.last_step;
            __process_log.info("PE64 GUEST KERNEL CALLS:   the most recent call of any kind was {s} at step {d}, which is {d} step(s) before the run ended; a title that has been silent for most of the run is not making requests Rosette could be failing", .{
                latest.export_name,
                census.last_step,
                quiet,
            });
        }
    }

    // Who did the asking, in one line. The per-thread detail belongs in
    // PE64 GUEST THREADS, where a thread's status and share are beside
    // it; printing the whole list twice under two headings is how a
    // reader stops trusting either one.
    var busiest_caller: ?*const __process_WindowsGuestThread = null;
    var attributed: u64 = 0;
    for (self.windows_guest_threads) |*thread| {
        if (thread.status == .vacant or thread.kernel_calls == 0) continue;
        attributed +|= thread.kernel_calls;
        if (busiest_caller == null or thread.kernel_calls > busiest_caller.?.kernel_calls) {
            busiest_caller = thread;
        }
    }
    if (busiest_caller) |thread| {
        __process_log.info("PE64 GUEST KERNEL CALLS:   the thread that asked most was '{s}' with {d} call(s); PE64 GUEST THREADS carries the rest, each beside its status and share", .{
            if (thread.name_len != 0) thread.nameText() else "<unnamed by the guest>",
            thread.kernel_calls,
        });
    }
    if (attributed != census.total_calls) {
        __process_log.info("PE64 GUEST KERNEL CALLS:   {d} of {d} call(s) were made while Rosette's active-thread slot was unset and are counted but unattributed; that is a gap in the attribution, not in the census", .{
            census.total_calls -| attributed,
            census.total_calls,
        });
    }

    reportGuestKernelCoverage(self);
}

pub fn reportGuestKernelCoverage(self: *const ElfState) void {
    const census = &self.guest_kernel_calls;
    var published_total: u32 = 0;
    var implemented_total: u32 = 0;
    inline for (__process_xenia_kernel_shim_map.modules) |module| {
        const row = __process_kernel_call_census.coverageForModule(census, module);
        published_total += row.published;
        implemented_total += row.implemented;
    }
    __process_log.info("PE64 KERNEL EXPORT COVERAGE: this Xenia build implements {d} of the {d} export(s) the console publishes across xboxkrnl/xam/xbdm ({d}%); a title that calls one of the other {d} reaches Xenia's unimplemented-export path", .{
        implemented_total,
        published_total,
        if (published_total == 0) @as(u32, 0) else implemented_total * 100 / published_total,
        published_total - implemented_total,
    });
    // Only the subsystems a chain depends on get a row of their own. The
    // rest are in the total above and a reader looking for a picture does
    // not need to walk them.
    inline for ([_]__process_xenia_kernel_shim_map.Subsystem{ .video, .audio, .memory, .scheduling }) |subsystem| {
        const row = __process_kernel_call_census.coverageFor(census, .xboxkrnl, subsystem);
        if (row.published != 0) {
            __process_log.info("PE64 KERNEL EXPORT COVERAGE:   xboxkrnl {s:<12} published={d:<4} implemented={d:<4} missing={d}", .{
                subsystem.label(),
                row.published,
                row.implemented,
                row.published - row.implemented,
            });
        }
    }
    // Name the graphics ones. They are the shortest list that can change
    // a verdict: an unimplemented `Vd*` the title calls stops the guest
    // output chain dead and presents exactly like a title that never
    // asked.
    var buffer: [24][]const u8 = undefined;
    const missing = __process_kernel_call_census.missingExports(census, .xboxkrnl, .video, &buffer);
    if (missing.len != 0) {
        __process_log.info("PE64 KERNEL EXPORT COVERAGE:   graphics exports the console publishes and this build does not serve (first {d}):", .{missing.len});
        var line: [512]u8 = undefined;
        var used: usize = 0;
        for (missing) |name| {
            if (name.len + 1 > line.len) continue;
            if (used + name.len + 1 > line.len) {
                __process_log.info("PE64 KERNEL EXPORT COVERAGE:     {s}", .{line[0..used]});
                used = 0;
            }
            if (used != 0) {
                line[used] = ' ';
                used += 1;
            }
            @memcpy(line[used .. used + name.len], name);
            used += name.len;
        }
        if (used != 0) __process_log.info("PE64 KERNEL EXPORT COVERAGE:     {s}", .{line[0..used]});
        __process_log.info("PE64 KERNEL EXPORT COVERAGE:   an unimplemented graphics export is not automatically a fault: most of these are HDCP, closed captioning and WSS, which no title needs to draw. It becomes one the moment PE64 GUEST KERNEL CALLS shows the title stalled in display-query", .{});
    }
}

pub fn reportGuestMilestones(self: *const ElfState) void {
    __process_log.info("PE64 GUEST MILESTONES: {d} of {d} symbols armed; filter_misses={d}", .{
        self.guest_milestones_resolved,
        __process_GUEST_MILESTONE_COUNT,
        self.guest_milestone_filter_misses,
    });
    var inlined_away: usize = 0;
    inline for (__process_xenia_guest_milestone_map.milestones, 0..) |milestone, index| {
        if (self.guest_milestone_addresses[index] == 0) {
            __process_log.info("PE64 GUEST MILESTONES:   {s:<40} unresolved (this image does not contain the symbol; its stage cannot be observed)", .{milestone.readable});
        } else {
            // An armed address with no entries and no direct branch to it
            // anywhere in the image is an out-of-line body the compiler
            // inlined into its callers. Printing that zero unqualified is
            // what let one build decision read as a stopped emulator.
            const reach = process_impl_kernel_services.guestMilestoneReach(self, milestone.mangled);
            if (reach == .unreachable_inlined) inlined_away += 1;
            __process_log.info("PE64 GUEST MILESTONES:   {s:<40} entries={d} reach={s} call_sites={d} vtable_refs={d} first_step={d} entry=0x{x} owner={s}{s}{s}{s}", .{
                milestone.readable,
                self.guest_milestone_hits[index],
                reach.label(),
                self.guest_milestone_call_sites[index],
                self.guest_milestone_data_refs[index],
                self.guest_milestone_first_step[index],
                self.guest_milestone_addresses[index],
                milestone.owner.label(),
                if (milestone.proxy_only) " role=witness" else "",
                if (reach == .unreachable_inlined) " INLINED-AWAY: nothing branches here and nothing stores this address, so this zero measures the build and not the run" else "",
                if (reach == .unreachable_inlined and milestone.inline_proxy.len != 0) " (read its witness row instead)" else "",
            });
            reportGuestMilestoneCallers(self, index);
        }
    }
    if (!self.guest_milestone_call_sites_counted) {
        __process_log.info("PE64 GUEST MILESTONES:   call-site census did not run on this route, so a zero entry count cannot be separated from an inlined body", .{});
    } else if (inlined_away != 0) {
        __process_log.info("PE64 GUEST MILESTONES:   {d} armed symbol(s) are unreachable in this image: nothing branches to them and nothing stores their address. A tracepoint counts calls, and an optimizer that inlines a body leaves the out-of-line copy in the symbol table with nothing reaching it; read those rows through the witness they name, never as guest progress. reach=indirect is the opposite case - a virtual function has no call site either, and its zero is the guest", .{inlined_away});
    }
}

pub fn reportGuestMilestoneCallers(self: *const ElfState, index: usize) void {
    var distinct: usize = 0;
    for (self.guest_milestone_callers[index]) |caller| {
        if (caller != 0) distinct += 1;
    }
    if (distinct <= 1 and self.guest_milestone_caller_overflow[index] == 0) return;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    for (self.guest_milestone_callers[index], self.guest_milestone_caller_hits[index]) |caller, hits| {
        if (caller == 0) continue;
        __process_log.info("PE64 GUEST MILESTONES:       from {s} (0x{x}) x{d}", .{
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller, &caller_text),
            caller,
            hits,
        });
    }
    if (self.guest_milestone_caller_overflow[index] != 0) {
        __process_log.info("PE64 GUEST MILESTONES:       and {d} entr(y/ies) from further call sites that did not fit the split", .{self.guest_milestone_caller_overflow[index]});
    }
}

pub fn reportRunChainsIfChanged(self: *ElfState, steps: u64) void {
    const frame_wall = firstFrameWall(self);
    const audio_wall = process_impl_windows_audio.audioChainWall(self);
    const output_wall = guestOutputWall(self);
    const frame_name = if (frame_wall) |stage| stage.name else "<none>";
    const audio_name = if (audio_wall) |stage| stage.name else "<none>";
    const output_name = if (output_wall) |stage| stage.name else "<none>";

    const frame_moved = !__process_std.mem.eql(u8, frame_name, self.reported_first_frame_wall);
    const audio_moved = !__process_std.mem.eql(u8, audio_name, self.reported_audio_wall);
    const output_moved = !__process_std.mem.eql(u8, output_name, self.reported_guest_output_wall);
    const refusals_moved = self.windows_module_refusal_events != self.reported_refusal_events or
        self.windows_proc_refusal_events != self.reported_proc_refusal_events;
    if (!frame_moved and !audio_moved and !output_moved and !refusals_moved and self.run_chains_reported) return;

    if (frame_moved and self.run_chains_reported) {
        __process_log.info("PE64 FIRST FRAME CHAIN: the wall moved at step {d}: '{s}' -> '{s}'", .{
            steps,
            self.reported_first_frame_wall,
            frame_name,
        });
    }
    if (audio_moved and self.run_chains_reported) {
        __process_log.info("PE64 AUDIO CHAIN: the wall moved at step {d}: '{s}' -> '{s}'", .{
            steps,
            self.reported_audio_wall,
            audio_name,
        });
    }
    if (output_moved and self.run_chains_reported) {
        __process_log.info("PE64 GUEST OUTPUT CHAIN: the wall moved at step {d}: '{s}' -> '{s}'", .{
            steps,
            self.reported_guest_output_wall,
            output_name,
        });
    }
    self.reported_first_frame_wall = frame_name;
    self.reported_audio_wall = audio_name;
    self.reported_guest_output_wall = output_name;
    self.reported_refusal_events = self.windows_module_refusal_events;
    self.reported_proc_refusal_events = self.windows_proc_refusal_events;
    self.run_chains_reported = true;

    if (frame_moved) reportFirstFrameChain(self);
    if (output_moved) {
        reportGuestOutputChain(self);
        // A process can be stopped externally before the normal exit
        // epilogue (for example while diagnosing a black Xenia window).
        // Snapshot the ring at each bounded output-wall transition so
        // the packet and indirect-buffer contents survive that stop.
        if (self.gpu_ring_initialized) reportGpuRing(self);
    }
    if (audio_moved) process_impl_windows_audio.reportAudioChain(self);
    if (refusals_moved) reportWindowsDynamicRefusals(self);
    process_impl_guest_memory.reportWindowsMemoryContract(self);
}

pub fn reportWindowsDynamicRefusals(self: *const ElfState) void {
    if (self.windows_module_refusal_events == 0 and
        self.windows_proc_refusal_events == 0 and
        self.windows_unreadable_module_names == 0) return;

    var module_gaps: u32 = 0;
    for (self.windows_module_refusals[0..self.windows_module_refusal_count]) |*record| {
        if (record.is_gap) module_gaps += 1;
    }
    __process_log.info("PE64 DYNAMIC REFUSALS: modules={d} ({d} gap, {d} deliberate) in {d} call(s), exports={d} in {d} call(s), unreadable_names={d}", .{
        self.windows_module_refusal_count,
        module_gaps,
        self.windows_module_refusal_count - module_gaps,
        self.windows_module_refusal_events,
        self.windows_proc_refusal_count,
        self.windows_proc_refusal_events,
        self.windows_unreadable_module_names,
    });
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    for (self.windows_module_refusals[0..self.windows_module_refusal_count]) |*record| {
        __process_log.info("PE64 DYNAMIC REFUSALS:   {s} module '{s}' via {s} x{d} fallback={s} first_caller={s}", .{
            if (record.is_gap) "GAP     " else "policy  ",
            record.nameText(),
            record.scopeText(),
            record.occurrences,
            __process_x64_linux_runtime.windowsModuleFallback(record.nameText()),
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, record.first_caller_rip, &caller_text),
        });
    }
    var export_gaps: usize = 0;
    for (self.windows_proc_refusals[0..self.windows_proc_refusal_count]) |*record| {
        // A name Rosette declines on purpose is a decision, not a to-do.
        // Printing both as `GAP` put `WinUsb_ReadIsochPipeAsap` on the
        // work list, when answering it NULL is the whole reason libusb
        // never asks for the four isochronous entry points behind it.
        const deliberate = __process_x64_linux_runtime.isDeliberateExportRefusal(record.scopeText(), record.nameText());
        if (!deliberate) export_gaps += 1;
        __process_log.info("PE64 DYNAMIC REFUSALS:   {s} export {s} from '{s}' x{d} first_caller={s}", .{
            if (deliberate) "policy  " else "GAP     ",
            record.nameText(),
            if (record.scopeText().len == 0) "<unattributed>" else record.scopeText(),
            record.occurrences,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, record.first_caller_rip, &caller_text),
        });
    }
    if (module_gaps == 0 and export_gaps == 0) {
        __process_log.info("PE64 DYNAMIC REFUSALS:   verdict: every refusal was a Rosette policy decision; no library or export is missing", .{});
    } else {
        __process_log.info("PE64 DYNAMIC REFUSALS:   verdict: {d} module gap(s) and {d} export gap(s) name work Rosette has not done; each one is a per-DLL package under pkg/dll/win32/", .{
            module_gaps,
            export_gaps,
        });
    }
}

pub fn noteGuestCjkFontDecision(self: *ElfState, granted: bool, detail: []const u8) void {
    if (self.windows_cjk_font_decision_reported) return;
    self.windows_cjk_font_decision_reported = true;
    self.windows_cjk_font_granted = granted;
    if (granted) {
        __process_log.info("PE64 guest font policy: CJK font granted (host='{s}'). Xenia will merge the Japanese glyph ranges into its ImGui atlas and build that atlas twice, on the UI thread, before the window can paint. Expect several hundred million guest steps inside stb_truetype first; set ROSETTE_XENIA_GUEST_CJK_FONT=0 to skip it.", .{detail});
    } else {
        __process_log.info("PE64 guest font policy: CJK font withheld (reason: {s}). Xenia takes its documented fallback and Japanese characters render as boxes; the ImGui atlas stays ASCII-sized so the first frame is not behind a full glyph rasterization. Set ROSETTE_XENIA_GUEST_CJK_FONT=1 to grant it.", .{
            if (detail.len == 0) "not requested by policy" else detail,
        });
    }
}

pub fn installGuestSymbolResolver(
    self: *ElfState,
    resolver: __process_GuestSymbolResolver,
    symbol_count: u32,
    coverage_percent: u32,
) void {
    self.guest_symbol_resolver = resolver;
    self.guest_symbol_count = symbol_count;
    self.guest_symbol_coverage_percent = coverage_percent;
    self.xenia_clock = .{ .symbols = __process_xenia_clock_probe.Symbols.discover(resolver) };
    if (resolver.address_of) |address_of| self.xenia_global_mutex_address = address_of(resolver.context, __process_XENIA_GLOBAL_MUTEX_SYMBOL);
    armGuestMilestones(self);
    armCallProbes(self);
}

pub fn armCallProbes(self: *ElfState) void {
    const raw = __process_std.c.getenv("ROSETTE_PE64_CALL_PROBE") orelse return;
    const text = __process_std.mem.sliceTo(raw, 0);
    if (__process_envU64("ROSETTE_PE64_CALL_PROBE_BUDGET")) |budget| self.call_probes.budget = @intCast(@min(budget, __process_std.math.maxInt(u32)));
    const resolver = self.guest_symbol_resolver;
    var it = __process_call_probe.requests(text);
    while (it.next()) |request| {
        const address = __process_call_probe.parseAddress(request) orelse blk: {
            const lookup = resolver orelse break :blk null;
            const address_of = lookup.address_of orelse break :blk null;
            break :blk address_of(lookup.context, request);
        };
        if (address) |found| {
            if (self.call_probes.add(found, request)) continue;
        }
        self.call_probes.unresolved +|= 1;
        __process_log.warn("PE64 CALL PROBE unresolved: '{s}' names no symbol in this image (or the probe table is full at {d}); use the mangled name a backtrace prints, or 0x<address>", .{ request, __process_call_probe.max_probes });
    }
    for (self.call_probes.probes[0..self.call_probes.count]) |*probe| {
        __process_log.info("PE64 CALL PROBE armed: {s} at 0x{x}; the first {d} calls log their arguments and results", .{ probe.name(), probe.address, self.call_probes.budget });
    }
}

pub fn noteCallProbeEntry(self: *ElfState, target: u64, return_rip: u64) void {
    const index = self.call_probes.indexOf(target) orelse return;
    const call = self.call_probes.noteCall(index);
    const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
    if (call.log) {
        const xmm = process_impl_lifecycle.guestContextField(self, "xmm");
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
        __process_log.info("PE64 CALL PROBE: {s} call=#{d} thread='{s}' caller=0x{x} ({s}) rsp=0x{x} args(rcx/rdx/r8/r9)=0x{x}/0x{x}/0x{x}/0x{x} stack_args(5..8)=0x{x}/0x{x}/0x{x}/0x{x} xmm0..3(low)=0x{x}/0x{x}/0x{x}/0x{x} step={d}", .{
            self.call_probes.probes[index].name(),
            call.number,
            guestThreadLabel(self, if (slot) |s| @intCast(@min(s + 1, 255)) else 0),
            return_rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, return_rip, &caller_text),
            regs.rsp,
            regs.rcx,
            regs.rdx,
            regs.r8,
            regs.r9,
            process_impl_guest_memory.read64(self, regs.rsp +| 0x20),
            process_impl_guest_memory.read64(self, regs.rsp +| 0x28),
            process_impl_guest_memory.read64(self, regs.rsp +| 0x30),
            process_impl_guest_memory.read64(self, regs.rsp +| 0x38),
            __process_std.mem.readInt(u64, xmm[0][0..8], .little),
            __process_std.mem.readInt(u64, xmm[1][0..8], .little),
            __process_std.mem.readInt(u64, xmm[2][0..8], .little),
            __process_std.mem.readInt(u64, xmm[3][0..8], .little),
            process_impl_run_reporting.totalInterpretedSteps(self),
        });
    }
    armGuestReturnCapture(self, .call_probe, index);
    const capture = activeReturnCapture(self);
    capture.outputs[0] = call.number;
    capture.outputs[1] = process_impl_run_reporting.totalInterpretedSteps(self);
}

pub fn armGuestMilestones(self: *ElfState) void {
    self.guest_milestones_armed = true;
    const resolver = self.guest_symbol_resolver orelse return;
    const address_of = resolver.address_of orelse return;
    var resolved: u32 = 0;
    inline for (__process_xenia_guest_milestone_map.milestones, 0..) |milestone, index| {
        if (address_of(resolver.context, milestone.mangled)) |address| {
            self.guest_milestone_addresses[index] = address;
            const bit = __process_guestMilestoneFilterBit(address);
            self.guest_milestone_slot[bit] = if (self.guest_milestone_slot[bit] == 0)
                @intCast(index + 1)
            else
                __process_milestone_slot_collision;
            resolved += 1;
        }
    }
    self.guest_milestone_filter_populated = resolved != 0;
    self.guest_milestones_resolved = resolved;
}

pub fn guestMilestoneIndexOf(self: *const ElfState, target: u64) ?usize {
    const slot = self.guest_milestone_slot[__process_guestMilestoneFilterBit(target)];
    if (slot == 0) return null;
    if (slot != __process_milestone_slot_collision) {
        const index = @as(usize, slot) - 1;
        return if (self.guest_milestone_addresses[index] == target) index else null;
    }
    for (self.guest_milestone_addresses, 0..) |address, index| {
        if (address == target) return index;
    }
    return null;
}

pub fn isGuestMilestoneAddress(self: *const ElfState, target: u64) bool {
    const slot = self.guest_milestone_slot[__process_guestMilestoneFilterBit(target)];
    if (slot == 0) return false;
    if (slot != __process_milestone_slot_collision) return self.guest_milestone_addresses[@as(usize, slot) - 1] == target;
    for (self.guest_milestone_addresses) |address| {
        if (address == target) return true;
    }
    return false;
}

pub fn noteGuestMilestoneEntry(self: *ElfState, target: u64) void {
    if (self.guest_milestone_slot[__process_guestMilestoneFilterBit(target)] == 0) return;
    // The filter and the addresses are written once, at load
    // (`armGuestMilestones`), so the exact match needs no lock; only
    // recording an entry does. Locking first charged every filter
    // collision the runtime lock - 17,090 of them on 2026-09-30, from
    // 60 milestones sharing 256 bits with every hot call target.
    const index = guestMilestoneIndexOf(self, target) orelse {
        _ = @atomicRmw(u64, &self.guest_milestone_filter_misses, .Add, 1, .monotonic);
        return;
    };
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer {
        if (runtime_guard) |*guard| guard.unlock();
    }
    recordGuestMilestone(self, index, target);
}

pub fn noteXeniaEmulatorSetupCall(self: *ElfState, target: u64, return_rip: u64) void {
    const setup_address = self.guest_milestone_addresses[__process_xenia_presenter_attach_milestones.emulator_setup];
    if (setup_address == 0 or target != setup_address) return;
    const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
    self.xenia_setup_trace = .{
        .pending = true,
        .thread = process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
        .return_rip = return_rip,
        .entry_step = process_impl_run_reporting.totalInterpretedSteps(self),
        .emulator = regs.rcx,
        .window = regs.rdx,
        .imgui_drawer = regs.r8,
        .returns = self.xenia_setup_trace.returns,
        .last_status = self.xenia_setup_trace.last_status,
        .last_return_step = self.xenia_setup_trace.last_return_step,
    };
}

pub fn noteXeniaEmulatorSetupReturn(self: *ElfState, return_rip: u64) void {
    const trace = &self.xenia_setup_trace;
    if (!trace.pending or
        trace.thread != process_impl_lifecycle.guestContextField(self, "active_guest_thread").* or
        trace.return_rip != return_rip)
    {
        return;
    }
    trace.pending = false;
    trace.returns +|= 1;
    trace.last_status = @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax);
    trace.last_return_step = process_impl_run_reporting.totalInterpretedSteps(self);
    __process_log.info("PE64 XENIA BOOTSTRAP: stage=emulator_setup_return status=0x{x} success={} emulator=0x{x} window=0x{x} imgui_drawer=0x{x} thread=0x{x} return_rip=0x{x} elapsed_steps={d} step={d}", .{
        trace.last_status,
        trace.last_status == 0,
        trace.emulator,
        trace.window,
        trace.imgui_drawer,
        trace.thread,
        trace.return_rip,
        trace.last_return_step -| trace.entry_step,
        trace.last_return_step,
    });
}

pub fn repairXeniaGpuWritePointerWake(self: *ElfState) void {
    const command_processor = process_impl_lifecycle.guestContextField(self, "regs").*.rcx;
    const write_pointer: u32 = @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rdx);
    if (command_processor != 0) self.xenia_command_processor_seen.store(command_processor, .release);
    if (command_processor == 0 or
        process_impl_execution.guestMemoryConst(self, command_processor +| 0x260, 8) == null or
        process_impl_execution.guestMemoryConst(self, command_processor +| 0x268, 4) == null)
    {
        self.windows_gpu_write_pointer_wake_repair_misses +|= 1;
        __process_log.warn("PE64 GPU write-pointer wake repair miss: reason=command_processor_unmapped this=0x{x} write_ptr=0x{x} step={d} misses={d}", .{
            command_processor,
            write_pointer,
            process_impl_lifecycle.observedExecutionSteps(self),
            self.windows_gpu_write_pointer_wake_repair_misses,
        });
        return;
    }
    const event_object = process_impl_guest_memory.read64(self, command_processor +| 0x260);
    if (event_object == 0 or process_impl_execution.guestMemoryConst(self, event_object +| 8, 8) == null) {
        self.windows_gpu_write_pointer_wake_repair_misses +|= 1;
        __process_log.warn("PE64 GPU write-pointer wake repair miss: reason=event_object_unmapped this=0x{x} event=0x{x} write_ptr=0x{x} step={d} misses={d}", .{
            command_processor,
            event_object,
            write_pointer,
            process_impl_lifecycle.observedExecutionSteps(self),
            self.windows_gpu_write_pointer_wake_repair_misses,
        });
        return;
    }
    const handle = process_impl_guest_memory.read64(self, event_object +| 8);
    if (process_impl_windows_sync.windowsWaitObjectIndex(self, handle) == null) {
        self.windows_gpu_write_pointer_wake_repair_misses +|= 1;
        __process_log.warn("PE64 GPU write-pointer wake repair miss: reason=unregistered_event_handle this=0x{x} event=0x{x} handle=0x{x} write_ptr=0x{x} step={d} misses={d}", .{
            command_processor,
            event_object,
            handle,
            write_pointer,
            process_impl_lifecycle.observedExecutionSteps(self),
            self.windows_gpu_write_pointer_wake_repair_misses,
        });
        return;
    }
    // The milestone is observed on entry, before Xenia's `xchgl
    // 0x268(%this), edx`. Mirror that one proven side effect before
    // waking the auto-reset event. The function body immediately repeats
    // the same exchange, so this preserves its contract and only restores
    // the ordering the worker relies on.
    process_impl_guest_memory.write32(self, command_processor +| 0x268, write_pointer);
    const woken = process_impl_windows_sync.signalWindowsWaitObject(self, handle, false);
    self.windows_gpu_write_pointer_wake_repairs +|= 1;
    // This fires on every ring publication, so it is a per-frame event
    // for the whole run: 4180 lines on 2026-09-19. Report the first
    // eight and then only at powers of two, the same governor the guest
    // output log uses. The count itself is carried on the summary line,
    // so nothing is lost but the volume.
    const repairs = self.windows_gpu_write_pointer_wake_repairs;
    if (repairs <= 8 or (repairs & (repairs - 1)) == 0)
        __process_log.info("PE64 GPU write-pointer wake repair: this=0x{x} event=0x{x} handle=0x{x} write_ptr=0x{x} woken={d} signaled_after={} step={d} repairs={d} misses={d}", .{
            command_processor,
            event_object,
            handle,
            write_pointer,
            woken,
            process_impl_windows_sync.windowsWaitObjectSignaled(self, handle),
            process_impl_lifecycle.observedExecutionSteps(self),
            self.windows_gpu_write_pointer_wake_repairs,
            self.windows_gpu_write_pointer_wake_repair_misses,
        });
}

pub fn recordGuestMilestone(self: *ElfState, index: usize, target: u64) void {
    // Which call site this entry came from. Four comparisons on a path
    // taken a few hundred thousand times in a run, against a witness row
    // whose total is otherwise unreadable.
    const caller = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*;
    const accounting_step = process_impl_run_reporting.totalInterpretedSteps(self);
    var placed = false;
    for (&self.guest_milestone_callers[index], 0..) |*slot, slot_index| {
        if (slot.* == caller) {
            self.guest_milestone_caller_hits[index][slot_index] +|= 1;
            placed = true;
            break;
        }
        if (slot.* == 0) {
            slot.* = caller;
            self.guest_milestone_caller_hits[index][slot_index] = 1;
            placed = true;
            break;
        }
    }
    if (!placed) self.guest_milestone_caller_overflow[index] +|= 1;
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| {
        if (index == comptime __process_xenia_guest_milestone_map.indexOf("_ZN2xe6kernel7XThread7ExecuteEv").?) {
            self.windows_guest_threads[slot].entered_xenia_title = true;
        }
        self.windows_guest_threads[slot].last_milestone = @intCast(index + 1);
        self.windows_guest_threads[slot].last_milestone_step = accounting_step;
    }
    if (self.guest_milestone_hits[index] == 0) {
        self.guest_milestone_first_step[index] = accounting_step;
        const milestone = __process_xenia_guest_milestone_map.milestones[index];
        // Which guest thread got here and when, by the wall clock: with
        // every guest thread on its own host thread, the milestones are
        // a cross-thread timeline only if each says whose it was.
        const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
        const thread_label = if (slot) |index_in_table| guestThreadLabel(self, @intCast(@min(index_in_table + 1, 255))) else "owner (UI thread)";
        __process_log.info("PE64 GUEST MILESTONE: {s} reached for the first time at step {d} rip=0x{x} owner={s} chain={s} thread=0x{x} thread_name='{s}' t_ms={d}; {s}", .{
            milestone.readable,
            accounting_step,
            target,
            milestone.owner.label(),
            milestone.chain.label(),
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            thread_label,
            process_impl_lifecycle.runElapsedMilliseconds(self),
            milestone.proves,
        });
    }
    self.guest_milestone_hits[index] +|= 1;
    self.guest_milestone_last_step[index] = accounting_step;
    if (self.guest_milestone_hits[index] == __process_GUEST_MILESTONE_TRANSLATOR_SATURATION and
        self.guest_milestone_saturated[index] == 0 and __process_guestMilestoneSaturable(index))
    {
        self.guest_milestone_saturated[index] = 1;
        __process_log.info("PE64 GUEST MILESTONE: {s} saturated after {d} recorded entries; translated direct calls now only count it (hits stay exact, caller/step fields freeze here)", .{
            __process_xenia_guest_milestone_map.milestones[index].readable,
            __process_GUEST_MILESTONE_TRANSLATOR_SATURATION,
        });
    }
    if (index == comptime __process_xenia_guest_milestone_map.indexOf("_ZN2xe3gpu6vulkan22VulkanCommandProcessor9IssueSwapEjjj").?) {
        noteFrameCostSwap(self, accounting_step);
    }
    // Arguments first: the wake repair below signals objects and must not
    // be what a ring decode reads its write pointer from.
    if (self.windows_runtime_enabled) noteGuestMilestoneArguments(self, index);
    if (self.windows_runtime_enabled and
        index == comptime __process_xenia_guest_milestone_map.indexOf("_ZN2xe3gpu16CommandProcessor18UpdateWritePointerEj").?)
    {
        repairXeniaGpuWritePointerWake(self);
    }
}

pub fn noteGuestMilestoneArguments(self: *ElfState, index: usize) void {
    const map = __process_xenia_guest_milestone_map;
    if (index == comptime map.indexOf("_ZN2xe3gpu14GraphicsSystem18WriteRegisterThunkEPvPS1_jj").?) {
        // WriteRegisterThunk(ppc_context, graphics_system, addr, value)
        _ = noteGpuRegisterAccess(self, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.r8), true, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.r9));
    } else if (index == comptime map.indexOf("_ZN2xe3gpu14GraphicsSystem17ReadRegisterThunkEPvPS1_j").?) {
        // ReadRegisterThunk(ppc_context, graphics_system, addr) -> value
        if (noteGpuRegisterAccess(self, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.r8), false, 0)) |slot| {
            armGuestReturnCapture(self, .gpu_register_read, @intCast(slot));
        }
    } else if (index == comptime map.indexOf("_ZN2xe3gpu14GraphicsSystem20InitializeRingBufferEjj").?) {
        // InitializeRingBuffer(this, ptr, size_log2)
        self.gpu_ring_base = @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rdx);
        self.gpu_ring_size_log2 = @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.r8);
        self.gpu_ring_initialized = true;
        self.gpu_ring_last_write_index = 0;
    } else if (index == comptime map.indexOf("_ZN2xe3gpu14GraphicsSystem26EnableReadPointerWriteBackEjj").?) {
        self.gpu_ring_rptr_writeback = @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rdx);
    } else if (index == comptime map.indexOf("_ZN2xe3gpu16CommandProcessor18UpdateWritePointerEj").?) {
        // UpdateWritePointer(this, value)
        noteGpuRingWritePointer(self, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rdx));
    } else if (index == comptime map.indexOf("_ZN2xe3vfs17VirtualFileSystem11ResolvePathESt17basic_string_viewIcSt11char_traitsIcEE").?) {
        noteGuestVfsResolveEntry(self);
    } else if (index == comptime map.indexOf("_ZN2xe3apu11AudioSystem11SubmitFrameEyPf").?) {
        // SubmitFrame(this, index, samples)
        noteAudioTitleFrame(self, process_impl_lifecycle.guestContextField(self, "regs").*.r8);
    } else if (index == __process_xenia_presenter_attach_milestones.font_rgba) {
        armGuestReturnCapture(self, .ui_font_rgba, 0);
        activeReturnCapture(self).outputs = .{ process_impl_lifecycle.guestContextField(self, "regs").*.rdx, process_impl_lifecycle.guestContextField(self, "regs").*.r8, process_impl_lifecycle.guestContextField(self, "regs").*.r9, 0 };
    } else if (index == __process_xenia_presenter_attach_milestones.lists) {
        var snapshot: [64]u8 = undefined;
        const readable = process_impl_execution.copyFromGuest(self, &snapshot, process_impl_lifecycle.guestContextField(self, "regs").*.rdx);
        self.ui_evidence.noteLists(if (readable) snapshot[0..] else null);
        noteUiDrawDataBuffers(self, process_impl_lifecycle.guestContextField(self, "regs").*.rdx);
    } else if (index == __process_xenia_presenter_attach_milestones.draw) {
        var snapshot: [44]u8 = undefined;
        const readable = process_impl_execution.copyFromGuest(self, &snapshot, process_impl_lifecycle.guestContextField(self, "regs").*.rdx);
        self.ui_evidence.noteDraw(if (readable) snapshot[0..] else null);
    } else if (index == __process_xenia_presenter_attach_milestones.scissor) {
        // Before CALL pushes the return: fifth/sixth args follow the
        // caller's 32-byte Windows x64 shadow space.
        var stack_args: [16]u8 = undefined;
        const stack_args_readable = process_impl_execution.copyFromGuest(self, &stack_args, process_impl_lifecycle.guestContextField(self, "regs").*.rsp +| 32);
        armGuestReturnCapture(self, .ui_scissor, 0);
        activeReturnCapture(self).outputs = .{
            process_impl_lifecycle.guestContextField(self, "regs").*.r8,                               process_impl_lifecycle.guestContextField(self, "regs").*.r9,
            if (stack_args_readable) __process_std.mem.readInt(u64, stack_args[0..8], .little) else 0, if (stack_args_readable) __process_std.mem.readInt(u64, stack_args[8..16], .little) else 0,
        };
    } else if (index == __process_xenia_presenter_attach_milestones.pipelines) {
        armGuestReturnCapture(self, .ui_pipelines, 0);
    }
    noteXeniaPresenterAttachArguments(self, index);
}

pub fn noteXeniaPresenterAttachArguments(self: *ElfState, index: usize) void {
    const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
    const hits = self.guest_milestone_hits[index];
    const milestone_step = process_impl_run_reporting.totalInterpretedSteps(self);

    if (index == __process_xenia_presenter_attach_milestones.emulator_setup) {
        if (hits <= 4) __process_log.info("PE64 XENIA BOOTSTRAP: stage=emulator_setup_enter emulator=0x{x} window=0x{x} imgui_drawer=0x{x} require_cpu_backend={} step={d}", .{
            regs.rcx,
            regs.rdx,
            regs.r8,
            regs.r9 != 0,
            milestone_step,
        });
    } else if (index == __process_xenia_presenter_attach_milestones.call_in_ui_thread) {
        if (hits <= 8) __process_log.info("PE64 XENIA BOOTSTRAP: stage=call_in_ui_thread_enter context=0x{x} callback_storage=0x{x} thread=0x{x} step={d}", .{
            regs.rcx,
            regs.rdx,
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            milestone_step,
        });
    } else if (index == __process_xenia_presenter_attach_milestones.call_in_ui_thread_deferred) {
        if (hits <= 8) __process_log.info("PE64 XENIA BOOTSTRAP: stage=call_in_ui_thread_deferred_enter context=0x{x} callback_storage=0x{x} thread=0x{x} step={d}", .{
            regs.rcx,
            regs.rdx,
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            milestone_step,
        });
        armGuestReturnCapture(self, .xenia_ui_deferred, 0);
        activeReturnCapture(self).outputs = .{ regs.rcx, regs.rdx, milestone_step, 0 };
    } else if (index == __process_xenia_presenter_attach_milestones.setup) {
        if (hits <= 4) __process_log.info("PE64 XENIA PRESENTER ATTACH: stage=setup_enter emulator_window=0x{x} step={d}", .{ regs.rcx, milestone_step });
    } else if (index == __process_xenia_presenter_attach_milestones.get_presenter) {
        if (hits <= 4) {
            __process_log.info("PE64 XENIA PRESENTER ATTACH: stage=get_presenter_enter emulator_window=0x{x} call={d} step={d}", .{ regs.rcx, hits, milestone_step });
            armGuestReturnCapture(self, .xenia_presenter_getter, 0);
            activeReturnCapture(self).outputs[0] = regs.rcx;
        }
    } else if (index == __process_xenia_presenter_attach_milestones.set_presenter) {
        if (hits <= 8) __process_log.info("PE64 XENIA PRESENTER ATTACH: stage=set_presenter window=0x{x} presenter=0x{x} call={d} step={d}", .{ regs.rcx, regs.rdx, hits, milestone_step });
    } else if (index == __process_xenia_presenter_attach_milestones.create_surface) {
        if (hits <= 4) __process_log.info("PE64 XENIA PRESENTER ATTACH: stage=create_native_surface window=0x{x} allowed_surface_types=0x{x} step={d}", .{ regs.rcx, regs.rdx, milestone_step });
    } else if (index == __process_xenia_presenter_attach_milestones.attach_surface) {
        if (hits <= 8) __process_log.info("PE64 XENIA PRESENTER ATTACH: stage=attach_surface presenter=0x{x} window=0x{x} surface=0x{x} call={d} step={d}", .{ regs.rcx, regs.rdx, regs.r8, hits, milestone_step });
    } else if (index == __process_xenia_presenter_attach_milestones.vulkan_connect) {
        if (hits <= 4) __process_log.info("PE64 XENIA PRESENTER ATTACH: stage=vulkan_connect presenter=0x{x} surface=0x{x} width={d} height={d} step={d}", .{ regs.rcx, regs.rdx, regs.r8, regs.r9, milestone_step });
    }
}

pub fn noteUiDrawDataBuffers(self: *ElfState, draw_data: u64) void {
    var draw_data_bytes: [64]u8 = undefined;
    if (!process_impl_execution.copyFromGuest(self, &draw_data_bytes, draw_data)) return;
    // ImDrawData::CmdLists is an ImVector at +16. Xenia's ImVector is
    // laid out as { Size: i32, Capacity: i32, Data: pointer }; the
    // pointer is therefore at +24, not +16. Following the size as a
    // pointer turns a valid list into an unrelated guest address and
    // makes the diagnostic itself report fabricated counts.
    const command_lists = __process_std.mem.readInt(u64, draw_data_bytes[24..32], .little);
    if (command_lists == 0) return;
    var first_list_bytes: [8]u8 = undefined;
    if (!process_impl_execution.copyFromGuest(self, &first_list_bytes, command_lists)) return;
    const first_list = __process_std.mem.readInt(u64, first_list_bytes[0..8], .little);
    if (first_list == 0) return;
    var list_bytes: [168]u8 = undefined;
    if (!process_impl_execution.copyFromGuest(self, &list_bytes, first_list)) return;
    // ImDrawList stores three ImVector values before Flags. Each vector
    // is { Size: i32, Capacity: i32, Data: pointer } on this 64-bit
    // build: CmdBuffer at +0 (Data +8), IdxBuffer at +16 (Data +24),
    // and VtxBuffer at +32 (Data +40).
    const command_count = __process_std.mem.readInt(u32, list_bytes[0..4], .little);
    const command_data = __process_std.mem.readInt(u64, list_bytes[8..16], .little);
    const vertex_count = __process_std.mem.readInt(u32, list_bytes[32..36], .little);
    const vertex_data = __process_std.mem.readInt(u64, list_bytes[40..48], .little);
    const shared_data = __process_std.mem.readInt(u64, list_bytes[56..64], .little);
    var command_bytes: [16]u8 = undefined;
    const command_bytes_readable = command_data != 0 and command_count != 0 and
        process_impl_execution.copyFromGuest(self, &command_bytes, command_data);
    var vertex_bytes: [8]u8 = undefined;
    const vertex_bytes_readable = vertex_data != 0 and vertex_count != 0 and
        process_impl_execution.copyFromGuest(self, &vertex_bytes, vertex_data);
    var shared_bytes: [16]u8 = undefined;
    const shared_bytes_readable = shared_data != 0 and
        process_impl_execution.copyFromGuest(self, &shared_bytes, shared_data +| 48);
    var clip_bytes: [16]u8 = undefined;
    const clip_address = __process_std.mem.readInt(u64, list_bytes[160..168], .little);
    const clip_bytes_readable = __process_std.mem.readInt(i32, list_bytes[152..156], .little) > 0 and
        clip_address != 0 and process_impl_execution.copyFromGuest(self, &clip_bytes, clip_address);
    self.ui_evidence.noteRawBuffers(
        first_list,
        command_data,
        vertex_data,
        command_count,
        vertex_count,
        if (command_bytes_readable) command_bytes[0..] else null,
        if (vertex_bytes_readable) vertex_bytes[0..] else null,
    );
    self.ui_evidence.noteRawListInternals(
        list_bytes[0..],
        if (shared_bytes_readable) shared_bytes[0..] else null,
        if (clip_bytes_readable) clip_bytes[0..] else null,
    );
}

pub fn activeReturnCapture(self: *ElfState) *__process_GuestReturnCapture {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| return &self.windows_guest_threads[slot].return_capture;
    return &self.owner_return_capture;
}

pub fn armGuestReturnCapture(self: *ElfState, kind: __process_GuestReturnCaptureKind, tag: u32) void {
    const capture = activeReturnCapture(self);
    if (capture.kind != .none) {
        // A capture this thread never returned from - an unwind, a
        // longjmp - is replaced rather than leaked.
        self.guest_return_captures_replaced +|= 1;
    } else {
        self.guest_return_captures_armed +|= 1;
    }
    capture.* = .{ .kind = kind, .return_rsp = process_impl_lifecycle.guestContextField(self, "regs").*.rsp, .tag = tag };
    // This thread's translated `ret` hands the return to the
    // interpreter's arm from now on, in the block it is in too.
    process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.ret_guard = 1;
}

pub fn refreshBlockJitGuards(self: *ElfState, record: *__process_block_jit.Scratch) void {
    const traced = self.trace_calls or self.block_jit_transfer_traced;
    record.call_guard = @intFromBool(traced);
    record.jmp_guard = @intFromBool(self.block_jit_transfer_traced);
    const captured = self.guest_return_captures_armed != 0 and activeReturnCapture(self).kind != .none;
    record.ret_guard = @intFromBool(self.trace_calls or captured);
    record.direct_non_temporal = @intFromBool(self.block_jit_streaming_stores_enabled and process_impl_block_jit.parallelDirectTlbActive(self) and __process_tso_memory.activeStoreBuffer() == null);
}

pub fn noteCallProbeReturn(self: *ElfState, capture: __process_GuestReturnCapture) void {
    if (capture.tag >= self.call_probes.count) return;
    const probe = &self.call_probes.probes[capture.tag];
    probe.returns +|= 1;
    if (capture.outputs[0] > self.call_probes.budget) return;
    const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
    const xmm0 = process_impl_lifecycle.guestContextField(self, "xmm")[0];
    __process_log.info("PE64 CALL PROBE RETURN: {s} call=#{d} rax=0x{x} rdx=0x{x} xmm0=0x{x}/0x{x} returned_to=0x{x} steps_inside={d}", .{
        probe.name(),
        capture.outputs[0],
        regs.rax,
        regs.rdx,
        __process_std.mem.readInt(u64, xmm0[0..8], .little),
        __process_std.mem.readInt(u64, xmm0[8..16], .little),
        regs.rip,
        process_impl_run_reporting.totalInterpretedSteps(self) -| capture.outputs[1],
    });
}

pub fn completeGuestReturnCapture(self: *ElfState) void {
    const capture = activeReturnCapture(self);
    if (capture.kind == .none or capture.return_rsp != process_impl_lifecycle.guestContextField(self, "regs").*.rsp) return;
    const finished = capture.*;
    capture.* = .{};
    self.guest_return_captures_armed -|= 1;
    self.guest_return_captures_completed +|= 1;
    process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.ret_guard = @intFromBool(self.trace_calls);
    switch (finished.kind) {
        .none => {},
        .call_probe => noteCallProbeReturn(self, finished),
        .ui_font_rgba => {
            var pixel_pointer_bytes: [8]u8 = undefined;
            var width_bytes: [4]u8 = undefined;
            var height_bytes: [4]u8 = undefined;
            if (!process_impl_execution.copyFromGuest(self, &pixel_pointer_bytes, finished.outputs[0]) or
                !process_impl_execution.copyFromGuest(self, &width_bytes, finished.outputs[1]) or
                !process_impl_execution.copyFromGuest(self, &height_bytes, finished.outputs[2]))
            {
                self.ui_evidence.font_returns +|= 1;
                self.ui_evidence.font_unreadable_returns +|= 1;
                self.ui_evidence.font_last_valid = false;
                return;
            }
            const pixels = __process_std.mem.readInt(u64, pixel_pointer_bytes[0..8], .little);
            const width = __process_std.mem.readInt(i32, width_bytes[0..4], .little);
            const height = __process_std.mem.readInt(i32, height_bytes[0..4], .little);
            const readable = if (__process_ui_draw_evidence.Evidence.atlasByteCount(width, height)) |n|
                process_impl_execution.guestMemoryConst(self, pixels, n) != null
            else
                false;
            self.ui_evidence.noteFontReturn(pixels, width, height, readable);
        },
        .ui_scissor => {
            const accepted = @as(u8, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax)) != 0;
            var rect: [4]u32 = undefined;
            var readable = accepted;
            var bytes: [4][4]u8 = undefined;
            if (accepted) for (finished.outputs, 0..) |address, index| {
                if (process_impl_execution.copyFromGuest(self, bytes[index][0..], address)) {
                    rect[index] = __process_std.mem.readInt(u32, bytes[index][0..4], .little);
                } else readable = false;
            };
            self.ui_evidence.noteScissorReturn(accepted, if (readable) rect else null);
        },
        .ui_pipelines => {
            if (@as(u8, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax)) != 0) self.ui_evidence.pipeline_true +|= 1 else self.ui_evidence.pipeline_false +|= 1;
        },
        .xenia_presenter_getter => __process_log.info("PE64 XENIA PRESENTER ATTACH: stage=get_presenter_return emulator_window=0x{x} presenter=0x{x} step={d}", .{
            finished.outputs[0],
            process_impl_lifecycle.guestContextField(self, "regs").*.rax,
            process_impl_run_reporting.totalInterpretedSteps(self),
        }),
        .xenia_ui_deferred => {
            self.xenia_ui_deferred_returns +|= 1;
            self.xenia_ui_deferred_last_accepted = @as(u8, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax)) != 0;
            __process_log.info("PE64 XENIA BOOTSTRAP: stage=call_in_ui_thread_deferred_return accepted={} context=0x{x} callback_storage=0x{x} posted/dropped={d}/{d} step={d} elapsed_steps={d}", .{
                self.xenia_ui_deferred_last_accepted,
                finished.outputs[0],
                finished.outputs[1],
                self.windows_ui_pipeline.pending_function_posts,
                self.windows_ui_pipeline.pending_function_post_drops,
                process_impl_run_reporting.totalInterpretedSteps(self),
                process_impl_run_reporting.totalInterpretedSteps(self) -| finished.outputs[2],
            });
        },
        .gpu_register_read => {
            if (finished.tag >= self.gpu_register_traffic_count) return;
            const entry = &self.gpu_register_traffic[finished.tag];
            const value: u32 = @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax);
            if (entry.read_returns != 0 and value != entry.last_read_value) entry.read_value_changes +|= 1;
            entry.read_returns +|= 1;
            entry.last_read_value = value;
        },
        .vfs_resolve => {
            if (finished.tag >= self.guest_vfs_resolve_count) return;
            const entry = &self.guest_vfs_resolves[finished.tag];
            if (process_impl_lifecycle.guestContextField(self, "regs").*.rax == 0) {
                entry.not_found +|= 1;
                self.guest_vfs_resolve_not_found +|= 1;
                // An empty name has no device to be missing from. The
                // line Xenia prints for it arrives later through an
                // asynchronous logger; this is the synchronous moment,
                // with the request that produced it still in hand.
                if (entry.path_len == 0 and !entry.truncated) process_impl_kernel_services.faultGuestVfsEmptyName(self, entry);
            } else {
                entry.found +|= 1;
            }
        },
    }
}

pub fn noteGpuRegisterAccess(self: *ElfState, address: u32, is_write: bool, value: u32) ?usize {
    const register: u16 = @truncate((address & 0xFFFF) / 4);
    if (is_write) self.gpu_register_writes +|= 1 else self.gpu_register_reads +|= 1;
    const count = self.gpu_register_traffic_count;
    const slot = blk: {
        // A poll reads one register over and over; check the last hit
        // before scanning.
        if (self.gpu_register_last_slot < count and self.gpu_register_traffic[self.gpu_register_last_slot].index == register) {
            break :blk self.gpu_register_last_slot;
        }
        for (self.gpu_register_traffic[0..count], 0..) |*entry, entry_index| {
            if (entry.index == register) break :blk entry_index;
        }
        if (count == __process_GPU_REGISTER_TRAFFIC_CAPACITY) {
            self.gpu_register_traffic_overflow +|= 1;
            return null;
        }
        self.gpu_register_traffic[count] = .{ .index = register, .first_step = process_impl_lifecycle.observedExecutionSteps(self) };
        self.gpu_register_traffic_count += 1;
        break :blk count;
    };
    self.gpu_register_last_slot = slot;
    const entry = &self.gpu_register_traffic[slot];
    if (is_write) {
        entry.writes +|= 1;
        entry.last_write_value = value;
    } else {
        entry.reads +|= 1;
    }
    entry.last_step = process_impl_lifecycle.observedExecutionSteps(self);
    entry.last_thread_slot = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |thread| @intCast(@min(thread + 1, 255)) else 0;
    return slot;
}

pub fn xeniaVirtualMembase(self: *const ElfState) ?u64 {
    for (self.windows_memory_views[0..self.windows_memory_view_count]) |view| {
        if (view.length < 0x4000_0000 or view.backing_offset != 0) continue;
        const physical = __process_std.math.add(u64, view.guest_base, 0x1_0000_0000) catch continue;
        for (self.windows_memory_views[0..self.windows_memory_view_count]) |candidate| {
            if (candidate.length == 0 or candidate.mapping_index != view.mapping_index) continue;
            if (candidate.guest_base == physical and candidate.backing_offset == 0x1_0000_0000) return view.guest_base;
        }
    }
    return null;
}

pub fn offerGuestFrontBufferToNativePresenter(self: *ElfState) bool {
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer {
        if (runtime_guard) |*guard| guard.unlock();
    }
    const callback = self.windows_graphics.hooks.native_present_guest_frontbuffer orelse return false;
    const front = &self.gpu_front_buffer;
    if (front.swaps == 0 or front.width == 0 or front.height == 0) return false;

    const attempt_step = process_impl_lifecycle.observedExecutionSteps(self);
    const new_swap = front.swaps != self.guest_frontbuffer_last_handoff_attempt_swap;
    if (front.swaps == self.guest_frontbuffer_last_handoff_swap) return true;
    if (self.guest_frontbuffer_last_handoff_attempt_swap == front.swaps and
        attempt_step -| self.guest_frontbuffer_last_handoff_attempt_step < 1_000_000)
    {
        return false;
    }
    self.guest_frontbuffer_last_handoff_attempt_swap = front.swaps;
    self.guest_frontbuffer_last_handoff_attempt_step = attempt_step;
    self.guest_frontbuffer_handoff_attempts +|= 1;

    const membase = xeniaVirtualMembase(self) orelse {
        self.guest_frontbuffer_handoff_failures +|= 1;
        return false;
    };
    // XE_SWAP names the physical surface explicitly. The fetch base is a
    // useful fallback for a partially decoded packet, and both values are
    // retained in the final PE64 FRONT BUFFER report for diagnosis.
    const physical_address = if (front.frontbuffer != 0)
        front.frontbuffer
    else
        front.baseAddress();
    if (physical_address == 0) {
        self.guest_frontbuffer_handoff_failures +|= 1;
        return false;
    }
    const physical_view_address = __process_std.math.add(
        u64,
        0x1_0000_0000,
        @as(u64, physical_address & 0x1FFF_FFFF),
    ) catch {
        self.guest_frontbuffer_handoff_failures +|= 1;
        return false;
    };
    const source = __process_std.math.add(u64, membase, physical_view_address) catch {
        self.guest_frontbuffer_handoff_failures +|= 1;
        return false;
    };
    const accepted = callback(
        self.windows_graphics.hooks.native_context,
        @ptrCast(self),
        source,
        front.width,
        front.height,
        @intFromBool(front.tiled()),
        @as(u32, front.endianness()),
        @as(u32, front.format()),
        @intFromBool(new_swap),
    ) != 0;
    if (accepted) {
        self.guest_frontbuffer_last_handoff_swap = front.swaps;
        self.guest_frontbuffer_handoff_successes +|= 1;
    } else {
        self.guest_frontbuffer_handoff_failures +|= 1;
    }
    const count = self.guest_frontbuffer_handoff_attempts;
    if (count <= 4 or (count & (count - 1)) == 0) {
        __process_log.info("PE64 GUEST FRONT BUFFER HANDOFF: attempt={d} accepted={} swaps={d} source=0x{x} physical=0x{x} extent={d}x{d} format={d} endian={d} tiled={} success={d} failures={d}; {s}", .{
            count,
            accepted,
            front.swaps,
            source,
            physical_address,
            front.width,
            front.height,
            front.format(),
            front.endianness(),
            front.tiled(),
            self.guest_frontbuffer_handoff_successes,
            self.guest_frontbuffer_handoff_failures,
            if (accepted) "the host presenter accepted the console surface" else "the host presenter declined it; the next readable checkpoint may retry",
        });
    }
    return accepted;
}

pub fn decodeGpuRingWindow(source: anytype, window: *__process_GpuRingWindow, from: u64, span: u64, ring_dwords: u64) void {
    var cursor: u64 = 0;
    var payload: u64 = 0;
    const limit = @min(span, __process_GPU_RING_WINDOW_DECODE_LIMIT);
    while (cursor < limit) : (cursor += 1) {
        const ring_index = (from + cursor) % ring_dwords;
        const dword = source.readDword(ring_index) orelse break;
        window.readable = true;
        window.decoded += 1;
        if (window.first_dword_count < __process_GPU_RING_WINDOW_FIRST_DWORDS) {
            window.first_dwords[window.first_dword_count] = dword;
            window.first_dword_count += 1;
        }
        if (dword == 0) window.zero_dwords += 1;
        if (cursor < __process_GPU_RING_WINDOW_ALIAS_CHECKS) {
            const alias = source.aliasCheck(ring_index, dword);
            window.alias_checks +|= alias.checked;
            window.alias_mismatches +|= alias.mismatched;
        }
        if (payload != 0) {
            payload -= 1;
            continue;
        }
        if (dword == 0 or dword == 0x0BAD_F00D or dword == 0xCDCD_CDCD) {
            if (dword != 0) window.marker_dwords += 1;
            continue;
        }
        switch (dword >> 30) {
            0 => {
                window.type0 += 1;
                payload = ((dword >> 16) & 0x3FFF) + 1;
                const base_register: u32 = dword & 0x7FFF;
                if (base_register == 0x4800 and payload == 6) {
                    var fetch: [6]u32 = @splat(0);
                    var complete = true;
                    for (&fetch, 1..) |*slot, offset| {
                        slot.* = source.readDword((from + cursor + offset) % ring_dwords) orelse {
                            complete = false;
                            break;
                        };
                    }
                    if (complete) {
                        // 0x4800 is a reused shader-fetch slot, not a
                        // front-buffer-only register. Do not publish the
                        // value until an immediately following XE_SWAP
                        // proves that this write describes the display
                        // surface.
                        window.pending_swap_fetch = fetch;
                        window.pending_swap_fetch_valid = true;
                    } else {
                        window.pending_swap_fetch_valid = false;
                    }
                } else {
                    window.pending_swap_fetch_valid = false;
                }
                if (base_register <= __process_GuestFrontBuffer.dc_lut_last and base_register + payload > __process_GuestFrontBuffer.dc_lut_first) {
                    window.dc_lut_type0_writes += 1;
                }
            },
            1 => {
                window.type1 += 1;
                window.pending_swap_fetch_valid = false;
                payload = 2;
            },
            2 => {
                window.type2 += 1;
                window.pending_swap_fetch_valid = false;
            },
            else => {
                window.type3 += 1;
                const opcode: u8 = @truncate((dword >> 8) & 0x7F);
                if (window.type3_opcode_count < __process_GPU_RING_WINDOW_OPCODES) {
                    window.type3_opcodes[window.type3_opcode_count] = opcode;
                    window.type3_opcode_count += 1;
                }
                switch (opcode) {
                    0x22, 0x34, 0x35, 0x36 => window.draw_packets += 1,
                    0x58 => {
                        // EVENT_WRITE_SHD is Xenia's native fence write.
                        // Retain the final four packets of each submitted
                        // buffer, including their raw endian selector and
                        // counter-vs-immediate initiator bit.
                        if (source.readDword((from + cursor + 1) % ring_dwords)) |initiator| {
                            if (source.readDword((from + cursor + 2) % ring_dwords)) |address| {
                                if (source.readDword((from + cursor + 3) % ring_dwords)) |value| {
                                    const index = window.event_write_count % window.last_event_writes.len;
                                    window.last_event_writes[index] = .{ .initiator = initiator, .address = address, .value = value };
                                    window.event_write_count +|= 1;
                                }
                            }
                        }
                    },
                    0x64 => {
                        window.swap_packets += 1;
                        // Pair the front-buffer description with the
                        // swap that consumes it. A later ordinary texture
                        // fetch must never replace it in this window.
                        window.swap_fetch_seen = window.pending_swap_fetch_valid;
                        if (window.pending_swap_fetch_valid) {
                            window.swap_fetch = window.pending_swap_fetch;
                        }
                        // XE_SWAP payload: signature, front buffer
                        // physical address, width, height.
                        if (source.readDword((from + cursor + 2) % ring_dwords)) |frontbuffer| window.swap_frontbuffer = frontbuffer;
                        if (source.readDword((from + cursor + 3) % ring_dwords)) |width| window.swap_width = width;
                        if (source.readDword((from + cursor + 4) % ring_dwords)) |height| window.swap_height = height;
                        window.pending_swap_fetch_valid = false;
                    },
                    0x37, 0x3F => if (window.indirect_buffers < __process_GPU_RING_WINDOW_INDIRECT_BUFFERS) {
                        // ExecutePacketType3_INDIRECT_BUFFER reads the
                        // list pointer and its length as the next two
                        // dwords.
                        if (source.readDword((from + cursor + 1) % ring_dwords)) |address| {
                            if (source.readDword((from + cursor + 2) % ring_dwords)) |length| {
                                window.indirect_addresses[window.indirect_buffers] = address & 0x1FFF_FFFF;
                                window.indirect_dwords[window.indirect_buffers] = length & 0xF_FFFF;
                                window.indirect_buffers += 1;
                            }
                        }
                    },
                    else => {},
                }
                if (opcode != 0x64) window.pending_swap_fetch_valid = false;
                payload = ((dword >> 16) & 0x3FFF) + 1;
            },
        }
    }
}

pub fn noteGpuRingWritePointer(self: *ElfState, write_index: u32) void {
    self.gpu_ring_updates +|= 1;
    const from = self.gpu_ring_last_write_index;
    self.gpu_ring_last_write_index = write_index;
    if (!self.gpu_ring_initialized or self.gpu_ring_size_log2 >= 29) return;
    // Xenia: primary_buffer_size_ = 1 << (size_log2 + 3) bytes.
    const ring_dwords: u64 = (@as(u64, 1) << @intCast(self.gpu_ring_size_log2 + 3)) / 4;
    if (ring_dwords == 0) return;
    const to = @as(u64, write_index) % ring_dwords;
    const start = @as(u64, from) % ring_dwords;
    const span = if (to >= start) to - start else ring_dwords - start + to;
    var window = __process_GpuRingWindow{
        .step = process_impl_lifecycle.observedExecutionSteps(self),
        .from_index = from,
        .to_index = write_index,
        .dwords = @intCast(@min(span, __process_std.math.maxInt(u32))),
    };
    if (xeniaVirtualMembase(self)) |membase| {
        const source = __state_GpuRingSource{ .state = self, .membase = membase, .base = self.gpu_ring_base };
        decodeGpuRingWindow(source, &window, start, span, ring_dwords);
        for (window.indirect_addresses[0..window.indirect_buffers], window.indirect_dwords[0..window.indirect_buffers]) |address, dwords| {
            decodeGpuIndirectBuffer(self, membase, address, dwords);
        }
    }
    if (!window.readable and span != 0) self.gpu_ring_unreadable_updates +|= 1;
    self.gpu_ring_dwords_decoded +|= window.decoded;
    self.gpu_ring_zero_dwords +|= window.zero_dwords;
    self.gpu_ring_type0_packets +|= window.type0;
    self.gpu_ring_type3_packets +|= window.type3;
    self.gpu_ring_alias_mismatches +|= window.alias_mismatches;
    self.gpu_ring_draw_packets +|= window.draw_packets;
    self.gpu_ring_swap_packets +|= window.swap_packets;
    self.gpu_front_buffer.note(&window);
    if (self.guest_kernel_calls.hitsFor("VdSwap") != 0) {
        _ = offerGuestFrontBufferToNativePresenter(self);
    }
    // Keep the first windows, and let the last slot track the newest.
    const slot = @min(self.gpu_ring_window_count, __process_GPU_RING_WINDOW_CAPACITY - 1);
    self.gpu_ring_windows[slot] = window;
    if (self.gpu_ring_window_count < __process_GPU_RING_WINDOW_CAPACITY) self.gpu_ring_window_count += 1;
}

pub fn decodeGpuIndirectBuffer(self: *ElfState, membase: u64, address: u32, dwords: u32) void {
    self.gpu_indirect_buffers_seen +|= 1;
    var window = __process_GpuRingWindow{ .step = process_impl_lifecycle.observedExecutionSteps(self), .from_index = address, .to_index = dwords, .dwords = dwords };
    if (dwords != 0) {
        const source = __state_GpuRingSource{ .state = self, .membase = membase, .base = address };
        decodeGpuRingWindow(source, &window, 0, dwords, dwords);
        if (!window.readable) self.gpu_indirect_buffers_unreadable +|= 1;
    }
    self.gpu_indirect_type3_packets +|= window.type3;
    self.gpu_indirect_draw_packets +|= window.draw_packets;
    self.gpu_indirect_swap_packets +|= window.swap_packets;
    self.gpu_front_buffer.note(&window);
    if (self.guest_kernel_calls.hitsFor("VdSwap") != 0) {
        _ = offerGuestFrontBufferToNativePresenter(self);
    }
    const slot = @min(self.gpu_indirect_buffer_count, __process_GPU_INDIRECT_BUFFER_CAPACITY - 1);
    self.gpu_indirect_buffers[slot] = window;
    if (self.gpu_indirect_buffer_count < __process_GPU_INDIRECT_BUFFER_CAPACITY) self.gpu_indirect_buffer_count += 1;
}

pub fn noteGuestVfsResolveEntry(self: *ElfState) void {
    self.guest_vfs_resolve_calls +|= 1;
    const view_address = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
    var view_bytes: [16]u8 = undefined;
    if (!process_impl_execution.copyFromGuest(self, &view_bytes, view_address)) {
        self.guest_vfs_resolve_unreadable +|= 1;
        return;
    }
    const length = __process_std.mem.readInt(u64, view_bytes[0..8], .little);
    const data = __process_std.mem.readInt(u64, view_bytes[8..16], .little);
    if (length > 4096) {
        self.guest_vfs_resolve_unreadable +|= 1;
        return;
    }
    const shown = @min(length, __process_GUEST_VFS_PATH_BYTES);
    var path_storage: [__process_GUEST_VFS_PATH_BYTES]u8 = undefined;
    const shown_len: usize = @intCast(shown);
    if (shown_len != 0) {
        if (!process_impl_execution.copyFromGuest(self, path_storage[0..shown_len], data)) {
            self.guest_vfs_resolve_unreadable +|= 1;
            return;
        }
    }
    const path = path_storage[0..shown_len];
    const slot = blk: {
        for (self.guest_vfs_resolves[0..self.guest_vfs_resolve_count], 0..) |*entry, entry_index| {
            if (__process_std.mem.eql(u8, entry.pathText(), path)) break :blk entry_index;
        }
        if (self.guest_vfs_resolve_count == __process_GUEST_VFS_RESOLVE_CAPACITY) {
            self.guest_vfs_resolve_overflow +|= 1;
            return;
        }
        const entry_index = self.guest_vfs_resolve_count;
        self.guest_vfs_resolve_count += 1;
        const entry = &self.guest_vfs_resolves[entry_index];
        entry.* = .{ .first_step = process_impl_lifecycle.observedExecutionSteps(self), .path_len = @intCast(path.len), .truncated = length > shown };
        @memcpy(entry.path[0..path.len], path);
        break :blk entry_index;
    };
    const entry = &self.guest_vfs_resolves[slot];
    entry.calls +|= 1;
    entry.last_step = process_impl_lifecycle.observedExecutionSteps(self);
    entry.caller_rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*;
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |thread_slot| {
        entry.thread_slot = @intCast(@min(thread_slot + 1, 255));
        entry.kernel_slot = self.windows_guest_threads[thread_slot].last_kernel_slot;
    } else {
        entry.thread_slot = 0;
        entry.kernel_slot = 0;
    }
    armGuestReturnCapture(self, .vfs_resolve, @intCast(slot));
}

pub fn guestVfsPathIsBareModuleName(path: []const u8) bool {
    return path.len != 0 and
        __process_std.mem.indexOfScalar(u8, path, ':') == null and
        __process_std.mem.indexOfScalar(u8, path, '\\') == null and
        __process_std.mem.indexOfScalar(u8, path, '/') == null;
}

pub fn guestVfsPathBasename(path: []const u8) []const u8 {
    var start: usize = 0;
    for (path, 0..) |character, index| {
        if (character == ':' or character == '\\' or character == '/') start = index + 1;
    }
    return path[start..];
}

pub fn guestVfsModuleStem(path: []const u8) []const u8 {
    const basename = guestVfsPathBasename(path);
    if (basename.len >= 4 and __process_std.ascii.eqlIgnoreCase(basename[basename.len - 4 ..], ".dll")) {
        return basename[0 .. basename.len - 4];
    }
    return basename;
}

pub fn guestVfsModuleNamesEqual(lhs: []const u8, rhs: []const u8) bool {
    const lhs_stem = guestVfsModuleStem(lhs);
    const rhs_stem = guestVfsModuleStem(rhs);
    return lhs_stem.len != 0 and rhs_stem.len != 0 and __process_std.ascii.eqlIgnoreCase(lhs_stem, rhs_stem);
}

pub fn guestVfsMatchedDevicePath(self: *const ElfState, module_name: []const u8) []const u8 {
    if (!guestVfsPathIsBareModuleName(module_name)) return "";
    for (self.guest_vfs_resolves[0..self.guest_vfs_resolve_count]) |*candidate| {
        const path = candidate.pathText();
        const basename = guestVfsPathBasename(path);
        if (candidate.found == 0 or path.len == 0 or guestVfsPathIsBareModuleName(path)) continue;
        if (basename.len < 4 or !__process_std.ascii.eqlIgnoreCase(basename[basename.len - 4 ..], ".dll")) continue;
        if (guestVfsModuleNamesEqual(module_name, path)) return path;
    }
    return "";
}

pub fn classifyGuestVfsResolves(self: *const ElfState) __process_GuestVfsResolveSummary {
    var summary: __process_GuestVfsResolveSummary = .{};
    for (self.guest_vfs_resolves[0..self.guest_vfs_resolve_count]) |*entry| {
        const path = entry.pathText();
        if (path.len == 0) {
            summary.empty_path_not_found +|= entry.not_found;
            continue;
        }
        if (guestVfsPathIsBareModuleName(path)) {
            summary.bare_module_calls +|= entry.calls;
            summary.bare_module_not_found +|= entry.not_found;
            summary.bare_module_paths +|= 1;
            if (guestVfsMatchedDevicePath(self, path).len != 0) {
                summary.bare_module_paths_reconciled +|= 1;
            } else {
                summary.bare_module_unmatched_not_found +|= entry.not_found;
            }
            continue;
        }
        summary.device_path_not_found +|= entry.not_found;
    }
    return summary;
}

pub fn describeVfsResolveFor(self: *const ElfState, path: []const u8, buffer: []u8) []const u8 {
    for (self.guest_vfs_resolves[0..self.guest_vfs_resolve_count]) |*entry| {
        if (!__process_std.mem.eql(u8, entry.pathText(), path)) continue;
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        const kernel = self.guest_kernel_calls.slotAt(entry.kernel_slot);
        const matched_device_path = guestVfsMatchedDevicePath(self, path);
        return __process_std.fmt.bufPrint(buffer, " vfs_ledger=[calls={d} found={d} not_found={d} matched_device_path={s} caller={s} during={s}!{s} thread={s} first_step={d}]", .{
            entry.calls,
            entry.found,
            entry.not_found,
            if (matched_device_path.len == 0) "<none>" else matched_device_path,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, entry.caller_rip, &caller_text),
            if (kernel) |slot| slot.module.moduleName() else "<none>",
            if (kernel) |slot| slot.export_name else "<none>",
            guestThreadLabel(self, entry.thread_slot),
            entry.first_step,
        }) catch "";
    }
    return "";
}

pub fn guestThreadLabel(self: *const ElfState, slot_plus_one: u8) []const u8 {
    if (slot_plus_one == 0) return "owner-context";
    const thread = &self.windows_guest_threads[slot_plus_one - 1];
    if (thread.status == .vacant) return "<exited>";
    return if (thread.name_len != 0) thread.nameText() else "<unnamed by the guest>";
}

pub fn noteApuRegisterFault(self: *ElfState, fault: __process_GuestAccessViolation) void {
    const membase = xeniaVirtualMembase(self) orelse return;
    if (fault.address < membase) return;
    const offset = fault.address - membase;
    if (offset < 0x7FEA_0000 or offset >= 0x7FEB_0000) return;
    self.xma_registers.note(@truncate((offset & 0xFFFF) / 4), fault.is_write, @truncate(fault.value), process_impl_run_reporting.totalInterpretedSteps(self));
}

pub fn reportXmaRegisters(self: *const ElfState) void {
    const census = &self.xma_registers;
    if (census.faults == 0) {
        __process_log.info("PE64 XMA REGISTERS: no title access to the XMA aperture at guest 0x7FEA0000 has faulted; the title has not addressed the audio decoder, so there is no compressed audio for it to be decoding", .{});
        return;
    }
    __process_log.info("PE64 XMA REGISTERS: faults={d} kick_writes={d} contexts_kicked={d} lock_writes={d} clear_writes={d} context_array_address=0x{x} registers={d} overflow={d}; read from Rosette's own fault delivery, so independent of whether XmaDecoder::WriteRegister was inlined into its MMIO thunk", .{
        census.faults,
        census.kicks,
        census.kicked_contexts,
        census.locks,
        census.clears,
        census.context_array_address,
        census.count,
        census.overflow,
    });
    for (census.entries[0..census.count]) |entry| {
        __process_log.info("PE64 XMA REGISTERS:   reg=0x{x:0>4} {s:<20} writes={d} reads={d} last_value=0x{x:0>8} bits_union=0x{x:0>8} first_step={d} last_step={d}", .{
            entry.index,
            __process_GuestXmaRegisterCensus.registerName(entry.index),
            entry.writes,
            entry.reads,
            entry.last_value,
            entry.value_union,
            entry.first_step,
            entry.last_step,
        });
    }
    if (census.kicks == 0) {
        __process_log.info("PE64 XMA REGISTERS:   verdict: the title has cleared and locked contexts but never kicked one, so the decoder has been asked for no work and the mixer has no decoded source; silence at this phase is the title's own state, not a lost Rosette signal", .{});
    } else {
        __process_log.info("PE64 XMA REGISTERS:   verdict: the title kicked {d} context(s); if XmaContext::Work stays at zero the request reached the register and the decoder did not run it, which is Xenia's decoder thread or its work event", .{census.kicked_contexts});
    }
}

pub fn noteFrameCostSwap(self: *ElfState, swap_step: u64) void {
    const profile_active = self.host_profile_started and __process_host_profile.active();
    const closed_host_epoch = if (profile_active) __process_host_profile.noteFrameBoundary() else 0;
    const cost = &self.frame_cost;
    @atomicStore(u64, &cost.swaps, @atomicLoad(u64, &cost.swaps, .monotonic) +| 1, .monotonic);
    self.spin_watch.retire();
    const audio_frames = process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3apu11AudioSystem11SubmitFrameEyPf");
    if (cost.swaps == 1) {
        cost.first_swap_step = swap_step;
    } else {
        cost.noteInterval(swap_step -| cost.last_swap_step);
        cost.owner_since_first_swap +|= process_impl_lifecycle.observedExecutionSteps(self) -| cost.owner_snapshot;
        cost.audio_frames_since_first_swap +|= audio_frames -| cost.audio_frames_snapshot;
    }
    cost.last_swap_step = swap_step;
    cost.owner_snapshot = process_impl_lifecycle.observedExecutionSteps(self);
    cost.audio_frames_snapshot = audio_frames;
    for (self.windows_guest_threads, &cost.threads) |*thread, *sample| {
        if (!__process_isLiveWindowsGuestThread(thread.status)) continue;
        if (sample.handle != thread.handle) {
            // A slot reused by a new thread starts from its own zero.
            sample.* = .{ .handle = thread.handle, .snapshot = process_impl_lifecycle.windowsGuestThreadSteps(self, thread) };
            continue;
        }
        if (cost.swaps != 1) sample.since_first_swap +|= process_impl_lifecycle.windowsGuestThreadSteps(self, thread) -| sample.snapshot;
        sample.snapshot = process_impl_lifecycle.windowsGuestThreadSteps(self, thread);
    }
    if (profile_active) {
        var snapshots: [__process_frame_attribution.max_threads]__process_frame_attribution.ThreadSnapshot = @splat(.{});
        for (self.windows_guest_threads[0..@min(self.windows_guest_threads.len, __process_frame_attribution.max_threads)], 0..) |*thread, slot| {
            if (thread.handle == 0) continue;
            snapshots[slot] = .{
                .handle = thread.handle,
                .instructions = process_impl_lifecycle.windowsGuestThreadSteps(self, thread),
                .name = if (thread.name_len == 0) "" else thread.nameText(),
            };
        }
        self.frame_attribution_ledger.noteBoundary(
            cost.swaps,
            closed_host_epoch,
            __process_monotonicNanoseconds(),
            process_impl_lifecycle.observedExecutionSteps(self),
            process_impl_lifecycle.ownerExecutedSteps(self),
            &snapshots,
            self.frame_input_activity.snapshot(),
        );
    }
}

pub fn hostQosForGuestThread(name: []const u8) __state_HostQos {
    const role = frameCostRole(name);
    if (__process_std.mem.eql(u8, role, "title main thread") or
        __process_std.mem.eql(u8, role, "title render thread") or
        __process_std.mem.eql(u8, role, "xenia GPU command processor")) return .user_interactive;
    if (__process_std.mem.startsWith(u8, name, "xe::threading::TimerQueue") or __process_std.mem.startsWith(u8, name, "Logging Writer")) return .utility;
    return .default;
}

pub fn applyParallelWorkerQos(self: *ElfState, thread: *const __process_WindowsGuestThread) void {
    if (comptime @import("builtin").os.tag != .macos) return;
    if (!self.host_thread_qos_enabled) return;
    const qos = hostQosForGuestThread(thread.nameText());
    if (__process_pthread_set_qos_class_self_np(@intFromEnum(qos), 0) != 0) return;
    if (qos == .default) return;
    const applied = @atomicRmw(u32, &self.host_thread_qos_applied, .Add, 1, .monotonic) + 1;
    if (applied <= 32) __process_log.info("PE64 HOST THREAD QOS: guest thread '{s}' runs at {s}; the frame's threads stay on performance cores and pollers yield them (ROSETTE_PE64_THREAD_QOS=0 keeps the default)", .{ thread.nameText(), qos.label() });
}

pub fn frameCostRole(name: []const u8) []const u8 {
    if (__process_std.mem.startsWith(u8, name, "Audio Worker")) return "xenia audio pump running the title's mixer callback";
    if (__process_std.mem.startsWith(u8, name, "GPU Commands")) return "xenia GPU command processor";
    if (__process_std.mem.startsWith(u8, name, "GPU Frame limiter")) return "xenia vblank pacing";
    if (__process_std.mem.startsWith(u8, name, "MAIN_THREAD")) return "title main thread";
    if (__process_std.mem.startsWith(u8, name, "RENDER")) return "title render thread";
    if (__process_std.mem.startsWith(u8, name, "AUDIO")) return "title audio thread";
    if (__process_std.mem.startsWith(u8, name, "XThread")) return "title thread";
    if (__process_std.mem.startsWith(u8, name, "xe::threading::TimerQueue") or __process_std.mem.startsWith(u8, name, "Logging Writer") or __process_std.mem.startsWith(u8, name, "XMA Decoder")) return "xenia service thread";
    return "other";
}

pub fn reportFrontBuffer(self: *const ElfState) void {
    const front = &self.gpu_front_buffer;
    if (front.swaps == 0) return;
    var dc_lut_mmio_writes: u64 = 0;
    var dc_lut_mmio_registers: u32 = 0;
    for (self.gpu_register_traffic[0..self.gpu_register_traffic_count]) |entry| {
        if (entry.index >= __process_GuestFrontBuffer.dc_lut_first and entry.index <= __process_GuestFrontBuffer.dc_lut_last and entry.writes != 0) {
            dc_lut_mmio_writes +|= entry.writes;
            dc_lut_mmio_registers += 1;
        }
    }
    const format = front.format();
    __process_log.info("PE64 FRONT BUFFER: swaps_described={d} format={s} (raw {d}) endianness={d} tiled={} pitch={d} base=0x{x} fetch_size={d}x{d} xe_swap(frontbuffer=0x{x} {d}x{d}) formats_seen=0x{x} fetch=[{x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8}]; the title's own description of what it asks Xenia to show, read from the type-0 SHADER_CONSTANT_FETCH_00_0 write VdSwap places before XE_SWAP", .{
        front.swaps,
        __process_GuestFrontBuffer.formatName(format),
        @as(u32, format),
        @as(u32, front.endianness()),
        front.tiled(),
        front.pitch(),
        front.baseAddress(),
        front.fetchWidth(),
        front.fetchHeight(),
        front.frontbuffer,
        front.width,
        front.height,
        front.formats_seen,
        front.fetch[0],
        front.fetch[1],
        front.fetch[2],
        front.fetch[3],
        front.fetch[4],
        front.fetch[5],
    });
    __process_log.info("PE64 FRONT BUFFER:   gamma ramp path={s}; DC_LUT writes: type0_in_ring={d} (applied by CommandProcessor::HandleSpecialRegisterWrite) mmio_aperture={d} across {d} register(s) (stored by GraphicsSystem::WriteRegister and never applied to the ramp)", .{
        if (__process_GuestFrontBuffer.usesPwlRamp(format)) "piecewise-linear (10-bit front buffer)" else "256-entry table (8-bit front buffer)",
        front.dc_lut_type0_writes,
        dc_lut_mmio_writes,
        dc_lut_mmio_registers,
    });
    if (__process_GuestFrontBuffer.usesPwlRamp(format) and front.dc_lut_type0_writes == 0) {
        if (dc_lut_mmio_writes != 0) {
            __process_log.info("PE64 FRONT BUFFER:   verdict: the title programmed its gamma ramp through the MMIO aperture ({d} write(s)) and Xenia applies DC_LUT only from PM4 type-0 packets, so the swap runs with Xenia's seeded linear PWL ramp. A title that resolves 7e3 floating-point data into a 10-bit front buffer displays its bit patterns as fixed point through that ramp: white (0x180) shows as 37% grey and everything below 0.25 at half brightness. This is an emulator-side gap; TEXEL CUSTODY's ramp_shape and the BRIGHTNESS LADDER say whether it is the loss on screen", .{dc_lut_mmio_writes});
        } else {
            __process_log.info("PE64 FRONT BUFFER:   verdict: a 10-bit front buffer with no DC_LUT programming observed on either path, so the swap runs with Xenia's seeded linear PWL ramp; if the title renders 7e3 floating point into this buffer its picture is displayed as fixed-point bit patterns (white at 37% grey). Read TEXEL CUSTODY ramp_shape and the BRIGHTNESS LADDER before concluding", .{});
        }
    }
}

pub fn reportFrameCost(self: *const ElfState) void {
    const cost = &self.frame_cost;
    if (cost.swaps < 2) return;
    const mean = cost.meanRecentInterval();
    const total = cost.totalSinceFirstSwap();
    const intervals = cost.swaps - 1;
    const now = __process_monotonicNanoseconds();
    const elapsed_nanos = if (now == 0 or self.run_first_checkpoint_nanos == 0) 0 else now -| self.run_first_checkpoint_nanos;
    const rate = if (elapsed_nanos == 0) 0 else __process_instructionRate(process_impl_run_reporting.totalInterpretedSteps(self), elapsed_nanos);
    // Swaps per second at this rate, in thousandths, and the rate 30 of
    // them would take. Both are integer so the line cannot round a
    // hundredfold shortfall into a plausible one.
    const swaps_per_second_milli: u64 = if (mean == 0) 0 else @intCast(@min(@as(u128, rate) * 1000 / mean, __process_std.math.maxInt(u64)));
    const needed_rate: u64 = mean *| 30;
    const shortfall: u64 = if (rate == 0) 0 else needed_rate / rate;
    __process_log.info("PE64 FRAME COST: swaps={d} instructions_per_swap(mean_last_{d}/min/max/lifetime_mean)={d}/{d}/{d}/{d} interpreter_rate={d} instructions/s -> {d}.{d:0>3} swaps/s possible; 30 swaps/s needs {d} instructions/s ({d}x this run). audio_frames_per_swap={d} (a console mixes about 6 per 30 Hz frame); the frame rate is this cost divided by the rate, and neither the ramp nor the present can change it", .{
        cost.swaps,
        __process_GuestFrameCost.window,
        mean,
        if (cost.min_interval == __process_std.math.maxInt(u64)) 0 else cost.min_interval,
        cost.max_interval,
        total / intervals,
        rate,
        swaps_per_second_milli / 1000,
        swaps_per_second_milli % 1000,
        needed_rate,
        shortfall,
        cost.audio_frames_since_first_swap / intervals,
    });
    // Top spenders since the first swap, largest first, bounded.
    var order: [__process_MAX_WINDOWS_GUEST_THREADS]usize = undefined;
    var order_count: usize = 0;
    for (cost.threads, 0..) |sample, slot| {
        if (sample.since_first_swap == 0) continue;
        order[order_count] = slot;
        order_count += 1;
    }
    var sorted: usize = 0;
    while (sorted < order_count) : (sorted += 1) {
        var best = sorted;
        var candidate = sorted + 1;
        while (candidate < order_count) : (candidate += 1) {
            if (cost.threads[order[candidate]].since_first_swap > cost.threads[order[best]].since_first_swap) best = candidate;
        }
        if (best != sorted) __process_std.mem.swap(usize, &order[sorted], &order[best]);
    }
    const denominator = if (total == 0) 1 else total;
    var printed: usize = 0;
    for (order[0..order_count]) |slot| {
        if (printed == 6) break;
        printed += 1;
        const sample = cost.threads[slot];
        const thread = &self.windows_guest_threads[slot];
        const name = if (thread.handle == sample.handle and thread.name_len != 0) thread.nameText() else "<exited or unnamed>";
        __process_log.info("PE64 FRAME COST:   thread='{s}' role={s} instructions_since_first_swap={d} share={d}% per_swap={d}", .{
            name,
            frameCostRole(name),
            sample.since_first_swap,
            @divTrunc(sample.since_first_swap *| 100, denominator),
            sample.since_first_swap / intervals,
        });
    }
    if (cost.owner_since_first_swap != 0) {
        __process_log.info("PE64 FRAME COST:   owner loop instructions_since_first_swap={d} share={d}%", .{ cost.owner_since_first_swap, @divTrunc(cost.owner_since_first_swap *| 100, denominator) });
    }
}

pub fn noteAudioTitleFrame(self: *ElfState, samples: u64) void {
    self.audio_title_frames_seen +|= 1;
    const seen = self.audio_title_frames_seen;
    if (seen > 4096 and seen % 16 != 0) return;
    var snapshot: [6 * 256 * 4]u8 = undefined;
    if (!process_impl_execution.copyFromGuest(self, &snapshot, samples)) return;
    self.audio_title_frames_checked +|= 1;
    for (snapshot) |byte| {
        if (byte == 0) continue;
        self.audio_title_frames_nonzero +|= 1;
        if (self.audio_title_first_nonzero_step == 0) self.audio_title_first_nonzero_step = process_impl_lifecycle.observedExecutionSteps(self);
        return;
    }
}

pub fn xeniaConstantRegisterRead(index: u16) ?u32 {
    return switch (index) {
        0x0F00 => 0x0810_0748, // RB_EDRAM_TIMING
        0x0F01 => 0x0000_200E, // RB_BC_CONTROL
        0x1951 => 0x0000_0001, // interrupt status: vblank
        0x1961 => 0x0500_02D0, // AVIVO_D1MODE_VIEWPORT_SIZE: 1280x720
        else => null,
    };
}

pub fn pm4OpcodeLabel(opcode: u8) []const u8 {
    return switch (opcode) {
        0x10 => "NOP",
        0x21 => "REG_RMW",
        0x22 => "DRAW_INDX",
        0x23 => "VIZ_QUERY",
        0x25 => "SET_STATE",
        0x26 => "WAIT_FOR_IDLE",
        0x27 => "IM_LOAD",
        0x2B => "IM_LOAD_IMMEDIATE",
        0x2C => "IM_STORE",
        0x2D => "SET_CONSTANT",
        0x2E => "LOAD_CONSTANT_CONTEXT",
        0x2F => "LOAD_ALU_CONSTANT",
        0x34 => "DRAW_INDX_BIN",
        0x35 => "DRAW_INDX_2_BIN",
        0x36 => "DRAW_INDX_2",
        0x37 => "INDIRECT_BUFFER_PFD",
        0x3B => "INVALIDATE_STATE",
        0x3C => "WAIT_REG_MEM",
        0x3D => "MEM_WRITE",
        0x3E => "REG_TO_MEM",
        0x3F => "INDIRECT_BUFFER",
        0x44 => "COND_EXEC",
        0x45 => "COND_WRITE",
        0x46 => "EVENT_WRITE",
        0x48 => "ME_INIT",
        0x4A => "SET_SHADER_BASES",
        0x4B => "SET_BIN_BASE_OFFSET",
        0x4F => "MEM_WRITE_CNTR",
        0x50 => "SET_BIN_MASK",
        0x51 => "SET_BIN_SELECT",
        0x52 => "WAIT_REG_EQ",
        0x53 => "WAIT_REG_GTE",
        0x54 => "INTERRUPT",
        0x55 => "SET_CONSTANT2",
        0x56 => "SET_SHADER_CONSTANTS",
        0x58 => "EVENT_WRITE_SHD",
        0x59 => "EVENT_WRITE_CFL",
        0x5A => "EVENT_WRITE_EXT",
        0x5B => "EVENT_WRITE_ZPD",
        0x5C => "WAIT_UNTIL_READ",
        0x5D => "WAIT_IB_PFD_COMPLETE",
        0x5E => "CONTEXT_UPDATE",
        0x60 => "SET_BIN_MASK_LO",
        0x61 => "SET_BIN_MASK_HI",
        0x62 => "SET_BIN_SELECT_LO",
        0x63 => "SET_BIN_SELECT_HI",
        0x64 => "XE_SWAP",
        else => "unnamed",
    };
}

pub fn gpuType3HandlerEntries(self: *const ElfState) u64 {
    return process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3gpu6vulkan22VulkanCommandProcessor26ExecutePacketType3_ME_INITEjj") +|
        process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3gpu6vulkan22VulkanCommandProcessor34ExecutePacketType3_INDIRECT_BUFFEREjj") +|
        process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3gpu6vulkan22VulkanCommandProcessor21ExecuteIndirectBufferEjj") +|
        process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3gpu6vulkan22VulkanCommandProcessor31ExecutePacketType3_WAIT_REG_MEMEjj") +|
        process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3gpu6vulkan22VulkanCommandProcessor28ExecutePacketType3_INTERRUPTEjj");
}

pub fn xenosRegisterName(index: u16) []const u8 {
    return switch (index) {
        0x01C0 => "CP_RB_BASE",
        0x01C1 => "CP_RB_CNTL",
        0x01C3 => "CP_RB_RPTR_ADDR",
        0x01C4 => "CP_RB_RPTR",
        0x01C5 => "CP_RB_WPTR",
        0x01C6 => "CP_RB_WPTR_DELAY",
        0x01CC => "CP_IB1_BASE",
        0x01CD => "CP_IB1_BUFSZ",
        0x01CE => "CP_IB2_BASE",
        0x01CF => "CP_IB2_BUFSZ",
        0x01DD => "SCRATCH_ADDR",
        0x01DC => "SCRATCH_UMSK",
        0x0F00 => "RB_EDRAM_TIMING",
        0x0F01 => "RB_BC_CONTROL",
        0x1844 => "AVIVO_D1GRPH_PRIMARY_SURFACE_ADDRESS",
        0x194C => "D1MODE_V_COUNTER",
        0x1951 => "D1MODE_INTERRUPT_STATUS",
        0x1961 => "AVIVO_D1MODE_VIEWPORT_SIZE",
        else => "",
    };
}

pub fn reportGpuRegisterTraffic(self: *const ElfState) void {
    if (self.gpu_register_reads == 0 and self.gpu_register_writes == 0) {
        __process_log.info("PE64 GPU REGISTER TRAFFIC: the title has not reached GraphicsSystem's register callbacks; nothing it did touched the GPU's registers", .{});
        return;
    }
    __process_log.info("PE64 GPU REGISTER TRAFFIC: reads={d} writes={d} registers={d} overflow={d} read_values_captured={d}; captured at GraphicsSystem::ReadRegisterThunk/WriteRegisterThunk, with each read's value taken at its return", .{
        self.gpu_register_reads,
        self.gpu_register_writes,
        self.gpu_register_traffic_count,
        self.gpu_register_traffic_overflow,
        self.guest_return_captures_completed,
    });
    var order: [__process_GPU_REGISTER_TRAFFIC_CAPACITY]usize = undefined;
    const count = self.gpu_register_traffic_count;
    for (0..count) |index| order[index] = index;
    // Busiest first; a poll is the row a reader needs.
    __process_std.mem.sort(usize, order[0..count], self, struct {
        fn busier(state: *const ElfState, left: usize, right: usize) bool {
            const a = state.gpu_register_traffic[left];
            const b = state.gpu_register_traffic[right];
            return a.reads +| a.writes > b.reads +| b.writes;
        }
    }.busier);
    var polled_unchanging: ?usize = null;
    var constant_polled: ?usize = null;
    for (order[0..@min(count, 16)]) |index| {
        const entry = &self.gpu_register_traffic[index];
        __process_log.info("PE64 GPU REGISTER TRAFFIC:   reg=0x{x:0>4} {s:<36} reads={d} writes={d} last_read=0x{x} read_value_changes={d} last_write=0x{x} first_step={d} last_step={d} last_thread={s}", .{
            entry.index,
            xenosRegisterName(entry.index),
            entry.reads,
            entry.writes,
            entry.last_read_value,
            entry.read_value_changes,
            entry.last_write_value,
            entry.first_step,
            entry.last_step,
            guestThreadLabel(self, entry.last_thread_slot),
        });
        if (entry.read_returns >= 1000 and entry.read_value_changes == 0) {
            if (xeniaConstantRegisterRead(entry.index) != null) {
                if (constant_polled == null) constant_polled = index;
            } else if (polled_unchanging == null) {
                polled_unchanging = index;
            }
        }
    }
    if (polled_unchanging) |index| {
        const entry = &self.gpu_register_traffic[index];
        __process_log.info("PE64 GPU REGISTER TRAFFIC:   verdict: the title read reg 0x{x:0>4} {s} {d} times and it returned 0x{x} every time. A title reads one register that often only when it is waiting for it to change, so the writer of that register is the thing it is waiting on", .{
            entry.index,
            xenosRegisterName(entry.index),
            entry.read_returns,
            entry.last_read_value,
        });
    } else {
        __process_log.info("PE64 GPU REGISTER TRAFFIC:   verdict: no register was polled a thousand times without changing", .{});
    }
    if (constant_polled) |index| {
        const entry = &self.gpu_register_traffic[index];
        __process_log.info("PE64 GPU REGISTER TRAFFIC:   reg 0x{x:0>4} {s} was read {d} times and returned 0x{x} every time, and it cannot do otherwise: GraphicsSystem::ReadRegister answers it with the constant 0x{x} without consulting the register file, so no writer exists to wait on. Beside {d} vblank interrupt dispatch(es), it is the title's interrupt handler reading its cause once per interrupt, not a poll", .{
            entry.index,
            xenosRegisterName(entry.index),
            entry.read_returns,
            entry.last_read_value,
            xeniaConstantRegisterRead(entry.index).?,
            process_impl_kernel_services.guestMilestoneStageHits(self, "_ZN2xe3gpu14GraphicsSystem10MarkVblankEv"),
        });
    }
}

pub fn reportGpuEventWrites(window: *const __process_GpuRingWindow, source: []const u8) void {
    const retained = @min(window.event_write_count, window.last_event_writes.len);
    for (0..retained) |offset| {
        const index = (window.event_write_count - retained + @as(u32, @intCast(offset))) % window.last_event_writes.len;
        const event = window.last_event_writes[index];
        __process_log.info("PE64 GPU FENCE PACKET: source={s} step={d} event={d}/{d} initiator=0x{x} address=0x{x} physical=0x{x} endian={d} value=0x{x} counter_source={}; this records what the title submitted, independently of the writeback value the CPU observes", .{
            source,
            window.step,
            window.event_write_count - retained + @as(u32, @intCast(offset)) + 1,
            window.event_write_count,
            event.initiator,
            event.address,
            event.address & ~@as(u32, 3),
            event.address & 3,
            event.value,
            event.initiator & 0x8000_0000 != 0,
        });
    }
}

pub fn reportGpuRing(self: *const ElfState) void {
    if (!self.gpu_ring_initialized) {
        __process_log.info("PE64 GPU RING: the title has not called VdInitializeRingBuffer, so there is no ring to decode", .{});
        return;
    }
    const membase = xeniaVirtualMembase(self);
    const ring_dwords: u64 = if (self.gpu_ring_size_log2 < 29) (@as(u64, 1) << @intCast(self.gpu_ring_size_log2 + 3)) / 4 else 0;
    __process_log.info("PE64 GPU RING: base=0x{x} size_log2={d} ({d} dwords) rptr_writeback=0x{x} write_pointer_updates={d} decoded_dwords={d} zero_dwords={d} type0_packets={d} type3_packets={d} alias_mismatches={d} unreadable_updates={d} membase=0x{x} indirect_buffers={d} indirect_unreadable={d} indirect_type3={d} draws={d} swaps={d}", .{
        self.gpu_ring_base,
        self.gpu_ring_size_log2,
        ring_dwords,
        self.gpu_ring_rptr_writeback,
        self.gpu_ring_updates,
        self.gpu_ring_dwords_decoded,
        self.gpu_ring_zero_dwords,
        self.gpu_ring_type0_packets,
        self.gpu_ring_type3_packets,
        self.gpu_ring_alias_mismatches,
        self.gpu_ring_unreadable_updates,
        membase orelse 0,
        self.gpu_indirect_buffers_seen,
        self.gpu_indirect_buffers_unreadable,
        self.gpu_indirect_type3_packets,
        self.gpu_ring_draw_packets +| self.gpu_indirect_draw_packets,
        self.gpu_ring_swap_packets +| self.gpu_indirect_swap_packets,
    });
    for (self.gpu_ring_windows[0..self.gpu_ring_window_count]) |*window| {
        var opcode_text: [256]u8 = undefined;
        var opcode_used: usize = 0;
        for (window.type3_opcodes[0..window.type3_opcode_count]) |opcode| {
            const piece = __process_std.fmt.bufPrint(opcode_text[opcode_used..], "{s}0x{x:0>2}:{s}", .{ if (opcode_used == 0) "" else ",", opcode, pm4OpcodeLabel(opcode) }) catch break;
            opcode_used += piece.len;
        }
        var dword_text: [96]u8 = undefined;
        var dword_used: usize = 0;
        for (window.first_dwords[0..window.first_dword_count]) |dword| {
            const piece = __process_std.fmt.bufPrint(dword_text[dword_used..], "{s}{x:0>8}", .{ if (dword_used == 0) "" else " ", dword }) catch break;
            dword_used += piece.len;
        }
        __process_log.info("PE64 GPU RING:   step={d} write_index 0x{x}->0x{x} ({d} dwords, {d} decoded{s}) zero={d} markers={d} type0={d} type1={d} type2={d} type3={d} opcodes=[{s}] alias_checks={d} alias_mismatches={d} first=[{s}]", .{
            window.step,
            window.from_index,
            window.to_index,
            window.dwords,
            window.decoded,
            if (window.readable) "" else ", unreadable",
            window.zero_dwords,
            window.marker_dwords,
            window.type0,
            window.type1,
            window.type2,
            window.type3,
            opcode_text[0..opcode_used],
            window.alias_checks,
            window.alias_mismatches,
            dword_text[0..dword_used],
        });
        reportGpuEventWrites(window, "ring");
    }
    for (self.gpu_indirect_buffers[0..self.gpu_indirect_buffer_count]) |*buffer| {
        var opcode_text: [256]u8 = undefined;
        var opcode_used: usize = 0;
        for (buffer.type3_opcodes[0..buffer.type3_opcode_count]) |opcode| {
            const piece = __process_std.fmt.bufPrint(opcode_text[opcode_used..], "{s}0x{x:0>2}:{s}", .{ if (opcode_used == 0) "" else ",", opcode, pm4OpcodeLabel(opcode) }) catch break;
            opcode_used += piece.len;
        }
        var dword_text: [96]u8 = undefined;
        var dword_used: usize = 0;
        for (buffer.first_dwords[0..buffer.first_dword_count]) |dword| {
            const piece = __process_std.fmt.bufPrint(dword_text[dword_used..], "{s}{x:0>8}", .{ if (dword_used == 0) "" else " ", dword }) catch break;
            dword_used += piece.len;
        }
        __process_log.info("PE64 GPU RING:   indirect buffer step={d} address=0x{x:0>8} dwords={d} ({d} decoded{s}) zero={d} type0={d} type1={d} type3={d} draws={d} swaps={d} nested_indirect_buffers={d} opcodes=[{s}] first=[{s}]", .{
            buffer.step,
            buffer.from_index,
            buffer.dwords,
            buffer.decoded,
            if (buffer.readable or buffer.dwords == 0) "" else ", unreadable",
            buffer.zero_dwords,
            buffer.type0,
            buffer.type1,
            buffer.type3,
            buffer.draw_packets,
            buffer.swap_packets,
            buffer.indirect_buffers,
            opcode_text[0..opcode_used],
            dword_text[0..dword_used],
        });
        reportGpuEventWrites(buffer, "indirect");
    }
    const map_name = struct {
        const packet = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor13ExecutePacketEv";
        const type0 = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType0Ej";
        const type1 = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType1Ej";
        const type3 = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType3Ej";
        const me_init = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor26ExecutePacketType3_ME_INITEjj";
        const indirect = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor34ExecutePacketType3_INDIRECT_BUFFEREjj";
        const walk = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor21ExecuteIndirectBufferEjj";
        const wait = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor31ExecutePacketType3_WAIT_REG_MEMEjj";
        const interrupt = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor28ExecutePacketType3_INTERRUPTEjj";
    };
    __process_log.info("PE64 GPU RING:   Xenia executed: ExecutePacket={d} Type0={d} Type1={d} Type3={d} ME_INIT={d} INDIRECT_BUFFER={d} ExecuteIndirectBuffer={d} WAIT_REG_MEM={d} INTERRUPT={d}", .{
        process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.packet),
        process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.type0),
        process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.type1),
        process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.type3),
        process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.me_init),
        process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.indirect),
        process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.walk),
        process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.wait),
        process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.interrupt),
    });
    const handler_entries = gpuType3HandlerEntries(self);
    const dispatcher_entries = process_impl_kernel_services.guestMilestoneHitsNamed(self, map_name.type3);
    const draws = self.gpu_ring_draw_packets +| self.gpu_indirect_draw_packets;
    const swaps = self.gpu_ring_swap_packets +| self.gpu_indirect_swap_packets;
    var verdict_buffer: [640]u8 = undefined;
    const verdict: []const u8 = if (self.gpu_ring_updates == 0)
        "the title initialised a ring and has not moved its write pointer"
    else if (membase == null)
        "Rosette could not find Xenia's physical view among the mapped views, so the ring was not decoded; the view table at start-up says why"
    else if (self.gpu_ring_alias_mismatches != 0)
        "Xenia's physical view of the ring and the title's virtual alias of the same pages disagree. The GPU thread reads a different page from the one the title writes, which is a defect in Rosette's file-mapping aliasing, not the title"
    else if (self.gpu_ring_dwords_decoded != 0 and self.gpu_ring_zero_dwords == self.gpu_ring_dwords_decoded)
        "every dword the write pointer covered is zero, through the physical view and the title's aliases alike. Xenia skips a zero header without calling an executor, so the ring advanced over memory that holds no commands: the title moved the pointer before writing, or wrote somewhere this base does not point"
    else if (self.gpu_ring_type3_packets != 0 and dispatcher_entries == 0 and handler_entries == 0)
        "the ring windows hold type 3 packets and neither Xenia's type 3 dispatcher nor any of its opcode handlers ran, so Xenia's reader and this decode disagree about where the window starts"
    else if (draws != 0 or swaps != 0)
        __process_std.fmt.bufPrint(&verdict_buffer, "the title's command stream carries {d} draw packet(s) and {d} XE_SWAP packet(s); the ring is doing its job, and a missing picture is downstream of it", .{ draws, swaps }) catch "the title's command stream carries draw or swap packets"
    else if (handler_entries != 0 or dispatcher_entries != 0)
        __process_std.fmt.bufPrint(&verdict_buffer, "Xenia executed the ring's type 3 packets (opcode handler entries={d}, ExecutePacketType3 row={d}: the dispatcher is inlined into ExecutePacket, so its own row reads zero and the handler rows are the witness). The {d} indirect buffer(s) decoded above carry no DRAW_INDX and no XE_SWAP: the title has initialised its device and set state and has not drawn or presented, so the next wall is the title's, not the ring's", .{ handler_entries, dispatcher_entries, self.gpu_indirect_buffers_seen }) catch "Xenia executed the ring's type 3 packets and no draw or swap has been submitted yet"
    else if (self.gpu_ring_type3_packets == 0 and self.gpu_ring_type0_packets != 0)
        "the ring carried register writes (type 0) and no type 3 command yet: the title is configuring the GPU and has not asked it to do anything"
    else
        "the ring windows decoded as shown; compare them with what Xenia executed above";
    __process_log.info("PE64 GPU RING:   verdict: {s}", .{verdict});
}

pub fn reportGuestVfsResolves(self: *const ElfState) void {
    if (!process_impl_kernel_services.guestMilestoneArmed(self, "_ZN2xe3vfs17VirtualFileSystem11ResolvePathESt17basic_string_viewIcSt11char_traitsIcEE")) {
        __process_log.info("PE64 GUEST VFS RESOLVES: VirtualFileSystem::ResolvePath is not named in this image, so path lookups are unobservable", .{});
        return;
    }
    __process_log.info("PE64 GUEST VFS RESOLVES: file requests captured={d} unreadable={d} empty_name_faults={d}; each NtCreateFile/NtOpenFile object name is read at the export trampoline, so an empty resolve names the request that produced it", .{
        self.guest_file_requests_captured,
        self.guest_file_requests_unreadable,
        self.guest_vfs_empty_name_faults,
    });
    const summary = classifyGuestVfsResolves(self);
    __process_log.info("PE64 GUEST VFS RESOLVES: calls={d} distinct_paths={d} not_found={d} bare_module_calls={d} bare_module_not_found={d} bare_module_paths_reconciled={d}/{d} unmatched_bare_module_not_found={d} empty_path_not_found={d} device_path_not_found={d} unreadable_arguments={d} overflow={d}; a bare-module miss is expected when Xenia probes a name before matching its loaded module, while device_path_not_found is the real missing-device count", .{
        self.guest_vfs_resolve_calls,
        self.guest_vfs_resolve_count,
        self.guest_vfs_resolve_not_found,
        summary.bare_module_calls,
        summary.bare_module_not_found,
        summary.bare_module_paths_reconciled,
        summary.bare_module_paths,
        summary.bare_module_unmatched_not_found,
        summary.empty_path_not_found,
        summary.device_path_not_found,
        self.guest_vfs_resolve_unreadable,
        self.guest_vfs_resolve_overflow,
    });
    if (summary.device_path_not_found == 0 and summary.bare_module_unmatched_not_found == 0) {
        __process_log.info("PE64 GUEST VFS ROUTING: verified all observed device-prefixed paths resolved; bare-module probes reconciled={d}/{d}, unmatched_bare_module_not_found=0. Repeated bare-name warnings are module-name probes, not missing mounted devices", .{
            summary.bare_module_paths_reconciled,
            summary.bare_module_paths,
        });
    }
    var order: [__process_GUEST_VFS_RESOLVE_CAPACITY]usize = undefined;
    const count = self.guest_vfs_resolve_count;
    for (0..count) |index| order[index] = index;
    __process_std.mem.sort(usize, order[0..count], self, struct {
        fn busier(state: *const ElfState, left: usize, right: usize) bool {
            return state.guest_vfs_resolves[left].calls > state.guest_vfs_resolves[right].calls;
        }
    }.busier);
    for (order[0..@min(count, 16)]) |index| {
        const entry = &self.guest_vfs_resolves[index];
        const path = entry.pathText();
        const bare_module_name = guestVfsPathIsBareModuleName(path);
        const matched_device_path = if (bare_module_name) guestVfsMatchedDevicePath(self, path) else "";
        const kind: []const u8 = if (path.len == 0)
            "empty path"
        else if (bare_module_name)
            "bare name: no device prefix, so a module lookup continues by name"
        else
            "device path";
        const classification: []const u8 = if (path.len == 0)
            "empty-path-probe"
        else if (matched_device_path.len != 0)
            "expected-module-name-probe"
        else if (bare_module_name)
            "unmatched-module-name-probe"
        else
            "device-path-resolution";
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        const kernel = self.guest_kernel_calls.slotAt(entry.kernel_slot);
        __process_log.info("PE64 GUEST VFS RESOLVES:   path='{s}'{s} calls={d} found={d} not_found={d} matched_device_path={s} classification={s} caller={s} during={s}!{s} thread={s} first_step={d} kind={s}", .{
            path,
            if (entry.truncated) "..." else "",
            entry.calls,
            entry.found,
            entry.not_found,
            if (matched_device_path.len == 0) "<none>" else matched_device_path,
            classification,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, entry.caller_rip, &caller_text),
            if (kernel) |slot| slot.module.moduleName() else "<none>",
            if (kernel) |slot| slot.export_name else "<none>",
            guestThreadLabel(self, entry.thread_slot),
            entry.first_step,
            kind,
        });
    }
}

pub fn paceWindowsWaveOutWrite(self: *ElfState, device: *__process_WindowsWaveOutDevice, length: u32) u64 {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null or length == 0) return 0;
    const bytes_per_second = @as(u64, device.sample_rate) * @as(u64, device.block_align);
    if (bytes_per_second == 0) return 0;
    const now = __process_monotonicNanoseconds();
    if (now == 0) return 0;
    if (device.paced_until_ns < now) device.paced_until_ns = now;
    const lead = device.paced_until_ns - now;
    if (lead > __process_WINDOWS_WAVE_OUT_PACING_LEAD_NS) {
        const excess = lead - __process_WINDOWS_WAVE_OUT_PACING_LEAD_NS;
        const wait_ms = @max(@as(u64, 1), (excess + __process_std.time.ns_per_ms - 1) / __process_std.time.ns_per_ms);
        device.pacing_waits +|= 1;
        self.windows_audio_pacing_waits +|= 1;
        self.windows_audio_pacing_wait_ms +|= wait_ms;
        return wait_ms;
    }
    const duration = (@as(u128, length) * __process_std.time.ns_per_s) / bytes_per_second;
    device.paced_until_ns +|= @intCast(@min(duration, __process_std.math.maxInt(u64)));
    return 0;
}

pub fn windowsRegistryOpen(self: *ElfState, parent: u64, subkey: []const u8, create: bool) __process_windows_registry_model.OpenResult {
    return self.windows_registry.openKey(self.allocator, parent, subkey, create);
}

pub fn windowsRegistryClose(self: *ElfState, handle: u64) u32 {
    return self.windows_registry.closeKey(handle);
}

pub fn windowsRegistryIsHandle(self: *const ElfState, handle: u64) bool {
    return self.windows_registry.isKnownHandle(handle);
}

pub fn windowsRegistrySet(self: *ElfState, handle: u64, name: []const u8, value_type: u32, data: []const u8) u32 {
    return self.windows_registry.setValue(self.allocator, handle, name, value_type, data);
}

pub fn windowsRegistryQuery(self: *ElfState, handle: u64, name: []const u8) __process_windows_registry_model.QueryResult {
    return self.windows_registry.queryValue(handle, name);
}

pub fn windowsRegistryGet(self: *ElfState, handle: u64, subkey: []const u8, name: []const u8) __process_windows_registry_model.QueryResult {
    return self.windows_registry.getValue(handle, subkey, name);
}

pub fn windowsRegistryDeleteValue(self: *ElfState, handle: u64, name: []const u8) u32 {
    return self.windows_registry.deleteValue(self.allocator, handle, name);
}

pub fn windowsRegistryFit(value_size: usize, has_buffer: bool, has_size: bool, capacity: u32) __process_windows_registry_model.Fit {
    return __process_windows_registry_model.fitValue(value_size, has_buffer, has_size, capacity);
}

pub fn windowsRegistryTypeAllowed(value_type: u32, flags: u32) bool {
    return __process_windows_registry_model.typeAllowed(value_type, flags);
}

pub fn reportWindowsRegistry(self: *const ElfState) void {
    const registry = &self.windows_registry;
    if (registry.opens == 0 and registry.queries == 0 and registry.values_written == 0) return;
    __process_log.info("PE64 GUEST REGISTRY: keys={d} values={d} value_bytes={d} opens={d} opens_missing={d} keys_created={d} values_written={d} queries={d} queries_found={d} capacity_refusals={d} invalid_handles={d}; the registry the guest owns, rooted in this run: a key it did not create reads ERROR_FILE_NOT_FOUND, as on a Windows machine without it", .{
        registry.keyCount(),
        registry.valueCount(),
        registry.value_bytes,
        registry.opens,
        registry.opens_missing,
        registry.keys_created,
        registry.values_written,
        registry.queries,
        registry.queries_found,
        registry.capacity_refusals,
        registry.invalid_handles,
    });
}
