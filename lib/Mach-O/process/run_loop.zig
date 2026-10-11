// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const CONCISE_PROGRESS_INTERVAL = __ProcessInternals._CONCISE_PROGRESS_INTERVAL;
const Cond = __ProcessInternals._Cond;
const DecodedInsn = __ProcessInternals._DecodedInsn;
const GUEST_ATEXIT_RETURN_SENTINEL = __ProcessInternals._GUEST_ATEXIT_RETURN_SENTINEL;
const GUEST_SIGNAL_RETURN_SENTINEL = __ProcessInternals._GUEST_SIGNAL_RETURN_SENTINEL;
const GUEST_THREAD_RETURN_SENTINEL = __ProcessInternals._GUEST_THREAD_RETURN_SENTINEL;
const HEARTBEAT_INTERVAL = __ProcessInternals._HEARTBEAT_INTERVAL;
const IdleDispatchBlock = __ProcessInternals._IdleDispatchBlock;
const IdleQueueSnapshot = __ProcessInternals._IdleQueueSnapshot;
const PAGE_SIZE = __ProcessInternals._PAGE_SIZE;
const PROGRESS_REPORT_INTERVAL = __ProcessInternals._PROGRESS_REPORT_INTERVAL;
const RunnableSuspendedSnapshot = __ProcessInternals._RunnableSuspendedSnapshot;
const Size = __ProcessInternals._Size;
const VexArithmetic = __ProcessInternals._VexArithmetic;
const VexBitwise = __ProcessInternals._VexBitwise;
const builtin = __ProcessInternals._builtin;
const contract = __ProcessInternals._contract;
const diagnostics_execution_profile = __ProcessInternals._diagnostics_execution_profile;
const execute_impl = __ProcessInternals._execute_impl;
const execution_helpers = __ProcessInternals._execution_helpers;
const execution_history = __ProcessInternals._execution_history;
const execution_tracepoints = __ProcessInternals._execution_tracepoints;
const exit_diagnostics = __ProcessInternals._exit_diagnostics;
const host_termination = __ProcessInternals._host_termination;
const import_resolution = __ProcessInternals._import_resolution;
const log = __ProcessInternals._log;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const macho_log = __ProcessInternals._macho_log;
const macho_runtime = __ProcessInternals._macho_runtime;
const mappedOffset = __ProcessInternals._mappedOffset;
const native_crash = __ProcessInternals._native_crash;
const proc_diag = __ProcessInternals._proc_diag;
const pthread_runtime = __ProcessInternals._pthread_runtime;
const ready_compiler = __ProcessInternals._ready_compiler;
const scheduler = __ProcessInternals._scheduler;
const scheduling = __ProcessInternals._scheduling;
const startup_observer = __ProcessInternals._startup_observer;
const std = __ProcessInternals._std;
const stepBudgetAllows = __ProcessInternals._stepBudgetAllows;
const thunk_handler = __ProcessInternals._thunk_handler;
const x64_interpreter = __ProcessInternals._x64_interpreter;
const xenia_pipeline = __ProcessInternals._xenia_pipeline;
const Sha1Tracer = __ProcessInternals._Sha1Tracer;
const guestAlloc = __ProcessInternals._guestAlloc;
const guestCString = __ProcessInternals._guestCString;
const guestMapBackendWithBacking = __ProcessInternals._guestMapBackendWithBacking;
const guestMapFile = __ProcessInternals._guestMapFile;
const guestMemory = __ProcessInternals._guestMemory;
const guestMemoryConst = __ProcessInternals._guestMemoryConst;
const guestProtectSparseMemory = __ProcessInternals._guestProtectSparseMemory;
const guestReserveAddressSpaceWithBacking = __ProcessInternals._guestReserveAddressSpaceWithBacking;
const guestUnmapFile = __ProcessInternals._guestUnmapFile;
const isExecutableAddress = __ProcessInternals._isExecutableAddress;
const setPagePermissions = __ProcessInternals._setPagePermissions;
const backendMemoryDiagnosticsActive = MachOState.backendMemoryDiagnosticsActive;
const continueGuestExit = MachOState.continueGuestExit;
const decodeFastPlain = MachOState.decodeFastPlain;
const decodeWithLiveOperands = MachOState.decodeWithLiveOperands;
const emitRuntimeSummaryHeartbeat = MachOState.emitRuntimeSummaryHeartbeat;
const emitTargetTrace = MachOState.emitTargetTrace;
const executeHighwayImmediate = MachOState.executeHighwayImmediate;
const executionFingerprint = MachOState.executionFingerprint;
const finishGuestSignalReturn = MachOState.finishGuestSignalReturn;
const handleInternalCompatibility = MachOState.handleInternalCompatibility;
const handlePatchDbEmptyPatchArray = MachOState.handlePatchDbEmptyPatchArray;
const handleStubHelperTransition = MachOState.handleStubHelperTransition;
const handleTomlAsciiFastPath = MachOState.handleTomlAsciiFastPath;
const handleTomlReadNextIntegrity = MachOState.handleTomlReadNextIntegrity;
const hostFd = MachOState.hostFd;
const hostWriteFdAll = MachOState.hostWriteFdAll;
const logGraphicsFrontier = MachOState.logGraphicsFrontier;
const logJitHealth = MachOState.logJitHealth;
const logStalledInstructionDetails = MachOState.logStalledInstructionDetails;
const noteBackendMmapAttempt = MachOState.noteBackendMmapAttempt;
const noteBackendMmapResult = MachOState.noteBackendMmapResult;
const noteBackendMprotect = MachOState.noteBackendMprotect;
const noteExecutionTracepoint = MachOState.noteExecutionTracepoint;
const noteGuestFieldAccess = MachOState.noteGuestFieldAccess;
const observeApplicationControlTransfer = MachOState.observeApplicationControlTransfer;
const observeProfileAccountFlow = MachOState.observeProfileAccountFlow;
const pollReadyCompiler = MachOState.pollReadyCompiler;
const pumpNativeWindowEvents = MachOState.pumpNativeWindowEvents;
const recordTrace = MachOState.recordTrace;
const recoverNonExecutableRip = MachOState.recoverNonExecutableRip;
const reportCoopBootstrapComplete = MachOState.reportCoopBootstrapComplete;
const reportDecodeFailure = MachOState.reportDecodeFailure;
const reportInvalidInstruction = MachOState.reportInvalidInstruction;
const seedProvenanceWatch = MachOState.seedProvenanceWatch;
const shouldTraceRIP = MachOState.shouldTraceRIP;
const specialRipPossible = MachOState.specialRipPossible;

pub fn step(self: anytype) bool {
    if (@import("builtin").mode != .ReleaseFast) self.observeProfileAccountFlow();
    if (self.regs.rip == GUEST_ATEXIT_RETURN_SENTINEL) {
        return self.continueGuestExit();
    }
    if (self.regs.rip == GUEST_SIGNAL_RETURN_SENTINEL) {
        return self.finishGuestSignalReturn() and !self.terminated;
    }
    if (self.regs.rip == GUEST_THREAD_RETURN_SENTINEL) {
        self.finishActiveGuestThread();
        return !self.terminated;
    }
    // R2 (N3): the 9 special-RIP handlers below used to run (and pay
    // ~65 compares + a function call) on every instruction even when all
    // inert. specialRipPossible is one binary search over the
    // load-time-resolved table plus O(1) range/state probes; the chain
    // runs only when rip could actually match a target, with identical
    // short-circuit semantics.
    //
    // F18 (throughput audit): the chain and the executability probe are
    // still recomputed per instruction even when every fact they verify
    // is invariant for a given RIP. A decode-cache hit whose entry was
    // filled with the chain declined and the address verified executable
    // (`fast_plain`) makes both redundant: the entry survives only while
    // the bytes and permissions it was validated under still hold, and
    // every condition the chain tests is monotone after the fill. One
    // probe replaces the binary search, the range/state probes and the
    // sparse executability probe on the hot path; everything here still
    // runs on misses, on entries filled without the gates, during config
    // parsing, and whenever the special-RIP table fallback is active.
    self.pending_control_transfer = null;
    var decoded: DecodedInsn = undefined;
    var gates_free = false;
    if (self.decodeFastPlain()) |fast| {
        // The fast entry was validated (executable, not a special target)
        // at fill time and survives only while the bytes and permissions
        // it was validated under still hold. Its fill-time host-image
        // classification is exact for this RIP, so the execution-history
        // filter below reads one field instead of re-running the range
        // compare on every step.
        self.step_host_image = fast.host_image;
        decoded = fast.decoded;
    } else {
        gates_free = !self.specialRipPossible();
        if (!gates_free) {
            if (self.handleInternalCompatibility()) return !self.terminated;
            if (self.handleTlvBootstrap()) return !self.terminated;
            if (self.handleBoundImportThunk()) return !self.terminated;
            if (self.handleSyntheticRuntimeThunk()) return !self.terminated;
            if (self.handleDynamicLibraryThunk()) return !self.terminated;
            if (self.handleStubHelperTransition()) {
                return !self.terminated;
            }
            self.handleTomlReadNextIntegrity();
            if (self.handleTomlAsciiFastPath()) return !self.terminated;
            if (self.handlePatchDbEmptyPatchArray()) return !self.terminated;
        }
        if (!self.isExecutableAddress(self.regs.rip)) return self.recoverNonExecutableRip();
        self.step_host_image = self.regs.rip >= self.executable_min and
            self.regs.rip < self.executable_max;
        decoded = self.decodeWithLiveOperands(gates_free) orelse return self.reportDecodeFailure();
    }
    if (decoded.op == .invalid) return self.reportInvalidInstruction();
    // Instruction history, gated behaviourally rather than by a flag.
    //
    // The predecessor of this line was `if (self.trace_ring_enabled)`, and
    // `trace_ring_enabled` was never assigned anywhere in the tree — so the
    // ring was empty for the entire life of the code and every recognizer
    // built on it reported "no retained evidence", which reads as a fact
    // about the guest and was a fact about an unset boolean.
    //
    // Generated code is the only region these recognizers ask about, and it
    // is a small fraction of executed steps (Xenia's own JIT compiler
    // dominates), so recording exactly there makes the tape both affordable
    // and deep where it is consulted. The host/generated split is classified
    // upstream (`step_host_image`) — from the decode entry on the fast path
    // and the range compare on the slow path — so this block does one load,
    // no page lookup.
    switch (self.execution_history.policy) {
        .disabled => {},
        .all => {
            self.execution_history_filter_active = false;
            self.recordTrace(decoded);
        },
        .generated_code_only => {
            // Classified upstream: the decode-cache fast path read the
            // entry's fill-time classification, the slow path computed the
            // same range compare this block used to run. One load replaces
            // the two range compares per step.
            if (self.step_host_image) {
                // One increment per contiguous omitted native interval,
                // not per instruction. Besides keeping the counter stable,
                // this makes the hot host-code path a predictable branch.
                if (!self.execution_history_filter_active) {
                    self.execution_history_epoch +|= 1;
                    self.execution_history_filter_active = true;
                }
                self.execution_history.noteFiltered();
            } else {
                self.execution_history_filter_active = false;
                self.recordTrace(decoded);
                self.seedProvenanceWatch(decoded);
                self.noteGuestFieldAccess(decoded);
            }
        },
    }
    if (self.coop_bootstrap_active and self.coop_bootstrap_index < 24) {
        const idx = self.coop_bootstrap_index;
        self.coop_bootstrap_entries[idx] = .{
            .rip = self.regs.rip,
            .thread = self.active_guest_thread,
            .op = @intFromEnum(decoded.op),
            .len = decoded.len,
        };
        self.coop_bootstrap_index = idx + 1;
        if (self.coop_bootstrap_index == 24) self.reportCoopBootstrapComplete();
    }
    // F19 (throughput audit): these gates are diagnostics that are off in
    // the steady state — the verbose trace and the SHA1 tracer are
    // env-gated off by default and the trace range is unset unless set by
    // hand — and each used to pay a load and a branch per instruction just
    // to be asked. `step_tracing_active` is computed once at startup from
    // the three immutable switches, so the cluster below costs one load
    // and one not-taken branch on the hot path; each gate still
    // self-checks inside so the aggregate can never over-fire.
    if (self.step_tracing_active) {
        if (self.verbose_trace) log.debug("rip=0x{x} op={s} len={d}", .{ self.regs.rip, @tagName(decoded.op), decoded.len });
        // Observe the resolved function entry itself rather than relying
        // on the preceding call target. Lazy-import stubs may transfer
        // here via a jump after Rosette has already handled the original
        // call.
        if (self.sha1_tracer.enabled and
            !self.sha1_tracer.active and
            self.internal_targets.sha1_process_bytes != 0 and
            self.regs.rip == self.internal_targets.sha1_process_bytes)
        {
            self.sha1_tracer.onProcessBytesEntry(self);
        }
        if (self.shouldTraceRIP(self.regs.rip)) self.emitTargetTrace(decoded);
    }
    const old_rip = self.regs.rip;
    x64_interpreter.execute(self, decoded);
    if (!self.terminated and self.regs.rip == old_rip) {
        self.regs.rip +%= decoded.len;
    }
    self.observeApplicationControlTransfer(decoded, old_rip);
    if (!self.terminated and
        self.step_tracing_active and
        self.sha1_tracer.enabled and
        self.sha1_tracer.isActiveThread(self))
    {
        self.sha1_tracer.instruction_count += 1;
        if (self.sha1_tracer.instruction_count == Sha1Tracer.HOT_THRESHOLD and !self.sha1_tracer.initial_report_done) {
            self.sha1_tracer.hot_function_rip = self.sha1_tracer.entry_rip;
            self.sha1_tracer.detected_at_step = self.executed_steps;
            self.sha1_tracer.initial_report_done = true;
        }
        if (self.sha1_tracer.initial_report_done and self.sha1_tracer.depth == 0) {
            self.sha1_tracer.progress_log_counter += 1;
            if (self.sha1_tracer.progress_log_counter >= Sha1Tracer.PROGRESS_LOG_INTERVAL) {
                self.sha1_tracer.progress_log_counter = 0;
                self.sha1_tracer.logSha1Progress(self);
            }
        }
    }
    return !self.terminated;
}

pub fn beginCooperativeMainLoop(self: anytype) bool {
    return scheduling.beginCooperativeMainLoop(self);
}

pub fn startDeferredGuestThread(self: anytype, deferred: pthread_runtime.DeferredThread) bool {
    return scheduling.startDeferredGuestThread(self, deferred);
}

pub fn saveActiveGuestThread(self: anytype, reason: []const u8) bool {
    return scheduling.saveActiveGuestThread(self, reason);
}

pub fn resumeSuspendedGuestThread(self: anytype) bool {
    return scheduling.resumeSuspendedGuestThread(self);
}

pub fn yieldActiveGuestThreadForWait(self: anytype, reason: []const u8) bool {
    return scheduling.yieldActiveGuestThreadForWait(self, reason);
}

pub fn maybeYieldActiveGuestThreadForQuantum(self: anytype) void {
    scheduling.maybeYieldActiveGuestThreadForQuantum(self);
}

pub fn refreshSuspendedRunnableCache(self: anytype) usize {
    return scheduling.refreshSuspendedRunnableCache(self);
}

pub noinline fn finishActiveGuestThread(self: anytype) void {
    scheduling.finishActiveGuestThread(self);
}

pub fn scheduleSignalCallback(self: anytype, function: u64, arg0: u64, arg1: u64, arg2: u64, tag: []const u8) u64 {
    return scheduling.scheduleSignalCallback(self, function, arg0, arg1, arg2, tag);
}

pub fn scheduleIdleCallback(self: anytype, function: u64, data: u64, tag: []const u8) u64 {
    return scheduling.scheduleIdleCallback(self, function, data, tag);
}

pub fn scheduleRendezvousIdleCallback(self: anytype, function: u64, data: u64, tag: []const u8) u64 {
    return scheduling.scheduleRendezvousIdleCallback(self, function, data, tag);
}

pub fn isIdleCallbackPending(self: anytype, source: u64) bool {
    return scheduling.isIdleCallbackPending(self, source);
}

pub fn pendingIdleCallbackCount(self: anytype) usize {
    return scheduling.pendingIdleCallbackCount(self);
}

pub fn gtkIdleQueueSnapshot(self: anytype) IdleQueueSnapshot {
    return scheduling.idleQueueSnapshot(self);
}

pub fn gtkIdleDispatchBlock(self: anytype) IdleDispatchBlock {
    return scheduling.idleDispatchBlock(self);
}

pub fn removeIdleSource(self: anytype, source: u64) bool {
    return scheduling.removeIdleSource(self, source);
}

pub fn startNextIdleCallback(self: anytype, reason: []const u8, active_already_saved: bool) bool {
    return scheduling.startNextIdleCallback(self, reason, active_already_saved);
}

pub fn isSyntheticCallbackHandle(self: anytype, handle: u64) bool {
    return scheduling.isSyntheticCallbackHandle(self, handle);
}

pub fn syntheticCallbackStackBusy(self: anytype) bool {
    return scheduling.syntheticCallbackStackBusy(self);
}

pub fn syntheticCallbackStackOwner(self: anytype) u64 {
    return scheduling.syntheticCallbackStackOwner(self);
}

pub fn noteSyntheticStackEntry(self: anytype, handle: u64) void {
    scheduling.noteSyntheticStackEntry(self, handle);
}

pub fn isIdleCallbackHandle(self: anytype, handle: u64) bool {
    return scheduling.isIdleCallbackHandle(self, handle);
}

pub fn currentCooperativeThreadHandle(self: anytype) u64 {
    if (self.active_guest_thread == 0 or self.isIdleCallbackHandle(self.active_guest_thread)) {
        return self.pthreads.main_thread_handle;
    }
    return self.active_guest_thread;
}

pub fn threadNumericId(self: anytype, handle: u64) u64 {
    return scheduling.threadNumericId(self, handle);
}

pub fn threadRole(self: anytype, handle: u64, address: u64) []const u8 {
    return scheduling.threadRole(self, handle, address);
}

pub fn contextContainsHandle(self: anytype, handle: u64) bool {
    return scheduling.contextContainsHandle(self, handle);
}

pub fn logAudioCallbackSchedulerState(self: anytype) void {
    scheduling.logAudioCallbackSchedulerState(self);
}

pub fn runnableSuspendedSnapshot(self: anytype) RunnableSuspendedSnapshot {
    return scheduling.runnableSuspendedSnapshot(self);
}

pub fn logThreadTable(self: anytype, reason: []const u8) void {
    scheduling.logThreadTable(self, reason);
}

pub fn restoreMainLoopCaller(self: anytype, reason: []const u8) void {
    scheduling.restoreMainLoopCaller(self, reason);
}

pub fn logCooperativeSchedulerSummary(self: anytype) void {
    scheduling.logCooperativeSchedulerSummary(self);
}

pub fn logCooperativeHeartbeat(self: anytype) void {
    scheduling.logCooperativeHeartbeat(self);
}

pub fn dumpCoopHeartbeatTrace(self: anytype) void {
    scheduling.dumpCoopHeartbeatTrace(self);
}

pub fn dumpUiHandoffTrace(self: anytype) void {
    scheduling.dumpUiHandoffTrace(self);
}

pub fn logMemoryInitializationProgress(self: anytype, steps: u64) void {
    scheduling.logMemoryInitializationProgress(self, steps);
}

pub noinline fn handleSyntheticRuntimeThunk(self: anytype) bool {
    return thunk_handler.handleSyntheticRuntimeThunk(self);
}

pub noinline fn handleTlvBootstrap(self: anytype) bool {
    return thunk_handler.handleTlvBootstrap(self);
}

pub noinline fn handleBoundImportThunk(self: anytype) bool {
    return thunk_handler.handleBoundImportThunk(self);
}

pub noinline fn handleDynamicLibraryThunk(self: anytype) bool {
    return thunk_handler.handleDynamicLibraryThunk(self);
}

pub noinline fn reportProgressCheckpoint(self: anytype, steps: u64) void {
    // Attribute the readiness gate's quiet window at this cadence rather
    // than at the heartbeat. A whole run only produces a handful of
    // heartbeats, and a handful of samples cannot tell a loop from forward
    // motion; the sample itself is O(1), so the finer rate is affordable.
    self.ready.noteExecutionSample(steps, self.regs.rip, self.active_guest_thread);
    // The symbol axis saturates against an emulator. Rosette resolves
    // *host* symbols, so a guest that JITs its own guest forever revisits
    // the same few translator functions: the axis goes quiet while the
    // work it measures is at full speed. These counters do not saturate,
    // because each advance is a request this process actually serviced.
    //
    // The failing run made the case: the gate declared no progress at step
    // 900M while guest heap allocations were still climbing by tens of
    // megabytes per hundred million steps.
    self.ready.noteExternalProgress(.{
        .heap_high_water = self.heap_next,
        .heap_live = self.memory_forwarder.summary().live_allocations,
        .threads_created = self.pthreads.created_threads,
    }, steps);
    const symbol = self.metadata.nearestSymbol(self.regs.rip);
    // The gate's blind spots are the stretches where Xenia logs nothing:
    // the per-title config and XDBF block above the shader-storage
    // request runs for hundreds of millions of instructions in silence,
    // and used to end the run with the graphics owner blamed for work that
    // had not been reached yet. The instruction pointer was never silent —
    // it was only unnamed, and the symbol above already resolved it. The
    // route package turns that symbol into a subsystem for free, because
    // the mapping is fixed when Xenia is compiled.
    if (symbol) |resolved| {
        const direct = ready_compiler.xenia.launchPhaseFor(resolved.name);
        const attribution = if (direct) |candidate| blk: {
            // A generic carrier has no owner of its own. During the one
            // source-ordered silent CompleteLaunch interval, the package
            // can safely use the current frontier to recover that owner.
            if (candidate.carrier) {
                break :blk ready_compiler.xenia.launchPhaseFallback(
                    self.ready.frontierStageName(),
                    resolved.name,
                ) orelse candidate;
            }
            break :blk candidate;
        } else ready_compiler.xenia.launchPhaseFallback(
            self.ready.frontierStageName(),
            resolved.name,
        );
        if (attribution) |attribution_value| {
            _ = self.ready.noteAttributedSite(
                .{
                    .phase_id = @intFromEnum(attribution_value.phase),
                    .label = attribution_value.label,
                    .owner = attribution_value.owner,
                    .after_stage = ready_compiler.xenia.launchPhaseAfterStage(attribution_value.phase),
                    // Whose code is running and whose progress it proves
                    // are different questions once the guest is executing:
                    // Xenia's translator runs because the title reached
                    // new code, so the blocked owner is reachable through
                    // the emulator's own symbols.
                    .proxy_owner = ready_compiler.xenia.launchPhaseProxyOwner(attribution_value.phase),
                    .proxy_after_stage = ready_compiler.xenia.launchPhaseProxyAfterStage(attribution_value.phase),
                    .carrier = attribution_value.carrier,
                },
                resolved.name,
                steps,
                self.regs.rip,
                self.active_guest_thread,
            );
        }
    }
    const heap_summary = self.memory_forwarder.summary();
    const snapshot: startup_observer.Snapshot = .{
        .step = steps,
        .rip = self.regs.rip,
        .symbol = self.metadata.symbolLabelFor(symbol, self.regs.rip),
        .symbol_offset = if (symbol) |resolved| resolved.offset else 0,
        .heap_next = self.heap_next,
        .import_calls = self.import_resolver.total_calls,
        .fs_open = self.fs_forwarder.open_count,
        .fs_read = self.fs_forwarder.read_count,
        .fs_write = self.fs_forwarder.write_count,
        .heap_allocations = heap_summary.allocations,
        .heap_live = heap_summary.live_allocations,
        .options_seen = self.launch_options.registrations_seen,
        .options_kept = self.launch_options.registrations_kept,
        .options_skipped = self.launch_options.registrations_skipped,
        .logging_lines = self.logging.emitted_lines,
        .pthread_created = self.pthreads.created_threads,
        .pthread_waits_collapsed = self.pthreads.collapsed_waits,
        .diagnostic_text_runs = self.diagnostic_text.accelerations,
        .diagnostic_text_lines = self.diagnostic_text.lines_retained,
        .pthread_blocked = self.pthreads.blocked_threads,
        .thread_id = self.active_guest_thread,
    };
    if (self.startup.enabled) {
        self.startup.checkpoint(snapshot);
    } else {
        // Feed the native crash handler: if the emulator's own host code
        // faults a moment from now, the crash report says exactly where the
        // guest was (step, rip, thread, symbol) rather than "the run was
        // somewhere". The symbol is copied, not borrowed, because guest image
        // memory is exactly what may have faulted.
        native_crash.recordGuestProgress(
            steps,
            self.regs.rip,
            self.active_guest_thread,
            if (symbol) |resolved| resolved.name else "",
        );

        const entry = &self.step_trace_entries[self.step_trace_index];
        entry.step = steps;
        entry.rip = self.regs.rip;
        self.step_trace_index +|= 1;
        if (self.step_trace_index == 5) {
            self.step_trace_index = 0;
            self.step_trace_filled = true;
        }
    }
}

pub fn executionProfileOrigin(
    self: anytype,
    address: u64,
) diagnostics_execution_profile.Origin {
    const address_kind = self.metadata.addressKind(address);
    if (address_kind == .image_unsymbolized and
        self.metadata.isExecutableImageAddress(address)) return .image_executable_unsymbolized;
    if (address_kind != .outside_image) return .image;
    // A program counter is in executable memory by construction, so this
    // asks the page state rather than assuming it: the distinction matters
    // the day a runaway branch puts a PC somewhere it cannot execute.
    if (self.sparse_memory.isExecutable(address, 1)) return .generated_code;
    return .outside_image_data;
}

pub noinline fn reportHeartbeat(self: anytype, steps: u64) void {
    // Emitted here rather than only at exit: a run killed by the
    // harness timeout still has to say where the graphics frontier
    // stopped, and the exit path never runs in that case.
    self.logGraphicsFrontier(false);
    const hb_symbol = self.metadata.nearestSymbol(self.regs.rip);
    const hb_symbol_label = self.metadata.symbolLabel(self.regs.rip);
    native_crash.recordGuestProgress(
        steps,
        self.regs.rip,
        self.active_guest_thread,
        hb_symbol_label,
    );
    const heartbeat_snapshot: startup_observer.Snapshot = .{
        .step = steps,
        .rip = self.regs.rip,
        .symbol = hb_symbol_label,
        .symbol_offset = if (hb_symbol) |resolved| resolved.offset else 0,
        .symbol_origin = self.executionProfileOrigin(self.regs.rip),
        .heap_next = self.heap_next,
        .import_calls = self.import_resolver.total_calls,
        .fs_open = self.fs_forwarder.open_count,
        .fs_read = self.fs_forwarder.read_count,
        .fs_write = self.fs_forwarder.write_count,
        .heap_allocations = 0,
        .heap_live = 0,
        .options_seen = self.launch_options.registrations_seen,
        .options_kept = self.launch_options.registrations_kept,
        .options_skipped = self.launch_options.registrations_skipped,
        .logging_lines = self.logging.emitted_lines,
        .pthread_created = self.pthreads.created_threads,
        .pthread_waits_collapsed = self.pthreads.collapsed_waits,
        .pthread_blocked = self.pthreads.blocked_threads,
        .thread_id = self.active_guest_thread,
        .execution_fingerprint = self.executionFingerprint(),
    };
    self.startup.heartbeat(heartbeat_snapshot);
    self.logPerformanceHeartbeat();
    self.emitRuntimeSummaryHeartbeat(heartbeat_snapshot);
    if (self.startup.takeStallDiagnostic()) self.logStalledInstructionDetails();
    self.pthreads.diagnoseStuck(steps, self.regs.rip, self.guest_time.now());
    self.pumpNativeWindowEvents();
    self.logCooperativeHeartbeat();
    self.pthreads.profileThreadStates(&self.wait_profiler, steps, self.guest_time.now());
    if (hb_symbol) |resolved| {
        if (std.mem.indexOf(u8, resolved.name, "CommitExecutableRange") != null) {
            self.jit_commit_count +|= 1;
            self.jit_log.emit(.{
                .kind = .code_cache_allocated,
                .step = steps,
                .guest_addr = @intCast(self.regs.rip & 0xFFFFFFFF),
                .host_addr = self.regs.rip,
                .size = 4096,
                .total_functions = @intCast(self.import_resolver.total_calls),
                .unique_ordinals = @intCast(self.import_resolver.total_calls),
                .call_count = self.jit_commit_count,
                .thread_id = self.active_guest_thread,
                .reason = "commit",
            });
        }
        if (std.mem.indexOf(u8, resolved.name, "GetProcAddressByOrdinal") != null) {
            self.jit_export_count +|= 1;
            if (self.jit_export_count % 100 == 0) {
                self.macho_log.emit(.{
                    .kind = .import_resolution,
                    .step = steps,
                    .thread_id = self.active_guest_thread,
                    .import_calls = self.import_resolver.total_calls,
                    .reason = "GetProcAddressByOrdinal",
                });
            }
            if (self.jit_export_count % 10 == 0) {
                self.jit_log.emit(.{
                    .kind = .host_to_guest_call,
                    .step = steps,
                    .guest_addr = @intCast(self.regs.rip & 0xFFFFFFFF),
                    .call_count = self.jit_export_count,
                    .total_functions = @intCast(self.import_resolver.total_calls),
                    .unique_ordinals = @intCast(self.import_resolver.total_calls),
                    .thread_id = self.active_guest_thread,
                    .reason = "export_resolution",
                });
            }
        }
    }
    if (self.graphics_preflight_enabled and
        self.guest_exit_observed and
        self.guest_exit_code == 0 and
        self.xenia_pipeline.hasReached(.graphics_setup_started) and
        !self.xenia_pipeline.hasReached(.emulator_setup_ready))
    {
        machoCapturePrint(
            "macho-processor: EARLY GUEST EXIT: exit_code=0 reason=exit_syscall step={d} xenia_frontier={s} setup did not reach emulator_setup_ready; this is a controlled guest/UI termination after setup refusal, not a native Rosette crash\n",
            .{
                self.guest_exit_step,
                if (self.xenia_pipeline.frontier) |stage| @tagName(stage) else "none",
            },
        );
    }
    self.jit_log.emit(.{
        .kind = .monitor_snapshot,
        .step = steps,
        .total_functions = @intCast(self.import_resolver.total_calls),
        .unique_ordinals = @intCast(self.import_resolver.total_calls),
        .code_cache_bytes = @intCast(self.memory_forwarder.summary().allocations *| 4096),
        .call_count = self.jit_commit_count,
        .thread_id = self.active_guest_thread,
        .reason = "heartbeat",
    });
    self.macho_log.emit(.{
        .kind = .heartbeat,
        .step = steps,
        .thread_id = self.active_guest_thread,
        .guest_addr = self.regs.rip,
        .runnable = @intCast(self.pthreads.activeCount()),
        .blocked = @intCast(self.pthreads.blocked_threads),
        .condvar_waits = self.pthreads.collapsed_waits,
        .import_calls = self.import_resolver.total_calls,
        .reason = "heartbeat",
        .symbol = hb_symbol_label,
    });
    self.logJitHealth(false);
    self.pollReadyCompiler(steps);
}

pub noinline fn recoverZeroActiveGuestThread(self: anytype) bool {
    const started_idle = self.pendingIdleCallbackCount() != 0 and
        self.startNextIdleCallback("zero-active run guard", true);
    if (started_idle) return true;

    // A failed context publication must not strand a newly-created
    // runnable worker merely because the deferred counter was already
    // decremented. `takeNewestDeferred` also scans the table directly, so
    // this repairs a stale counter as well as the ordinary deferred path.
    if (self.pthreads.takeNewestDeferred()) |next| {
        if (self.startDeferredGuestThread(next)) return true;
        self.pthreads.requeueDeferred(next.handle);
    }
    if (self.resumeSuspendedGuestThread()) return true;

    self.logThreadTable("zero-active run guard");
    var orphaned_runnable: u32 = 0;
    for (0..self.pthreads.tableCapacity()) |slot| {
        const snapshot = self.pthreads.snapshotAt(slot) orelse continue;
        if (snapshot.state != .runnable or self.contextContainsHandle(snapshot.handle)) continue;
        orphaned_runnable += 1;
        machoCapturePrint(
            "macho-processor: scheduler orphaned runnable thread: handle=0x{x} numeric_id={d} started={} start=0x{x} no active or suspended context owns this runnable entry\n",
            .{ snapshot.handle, snapshot.numeric_id, snapshot.started, snapshot.start_routine },
        );
    }
    self.scheduler_log.emit(.{
        .kind = .deadlock,
        .step = self.executed_steps,
        .thread = 0,
        .runnable = self.pthreads.activeCount(),
        .blocked = self.pthreads.blocked_threads,
        .reason = "zero_active_guest_thread",
    });
    machoCapturePrint(
        "macho-processor: runtime invariant failure: no resumable guest context; refusing stale-register execution rip=0x{x} suspended={d} modeled_runnable={d} orphaned_runnable={d} deferred={d} blocked={d} pending_gtk={d}\n",
        .{ self.regs.rip, self.suspended_guest_thread_count, self.pthreads.activeCount(), orphaned_runnable, self.pthreads.deferred_threads, self.pthreads.blocked_threads, self.pendingIdleCallbackCount() },
    );
    self.faulted = true;
    self.exit_code = 125;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.runtime_invariant_failure);
    self.terminated = true;
    return false;
}

pub noinline fn reportConciseProgress(self: anytype, steps: u64) void {
    var progress_buffer: [256]u8 = undefined;
    const progress = std.fmt.bufPrint(
        &progress_buffer,
        "Translated instructions: {d} (activity only, not application progress; runnable={d} blocked={d} condvar_waits={d} quiescence_recoveries={d})\n",
        .{
            steps,
            self.pthreads.activeCount(),
            self.pthreads.blocked_threads,
            self.pthreads.collapsed_waits,
            self.cooperative_quiescence_recoveries,
        },
    ) catch "";
    _ = hostWriteFdAll(1, progress);
    self.scheduler_log.emit(.{
        .kind = .runnable_count,
        .step = steps,
        .thread = self.active_guest_thread,
        .runnable = self.pthreads.activeCount(),
        .blocked = self.pthreads.blocked_threads,
        .reason = "progress_checkpoint",
    });
}

pub fn run(self: anytype) void {
    native_crash.recordPhase("run");
    var steps: u64 = 0;
    // N5 (perf audit): replace the four per-instruction `steps % X`
    // modulo operations below with down-counters. Each counter decrements
    // once per iteration and fires (then resets) at exactly the step the
    // old modulo would have matched — including the step-0 heartbeat
    // (`0 % HEARTBEAT_INTERVAL == 0` fires on the first iteration) and
    // excluding 0 for the `steps != 0`-guarded reports. The concise
    // progress report instead uses a boundary comparison (steps >= next
    // boundary) so checkpoints land on exact multiples of
    // CONCISE_PROGRESS_INTERVAL — a decrement-then-fire counter would fire
    // at steps == N*interval - 1.
    var next_progress_report: u64 = PROGRESS_REPORT_INTERVAL;
    var next_heartbeat: u64 = 0;
    var next_concise_report: u64 = CONCISE_PROGRESS_INTERVAL;
    var next_memory_init_report: u64 = 1_000_000;
    machoCapturePrint(
        "macho-processor: CMPXCHG contract active — 0F B0 executes at byte width, flags use ACC-DEST, and assertion-triggered CAS repair paths are absent.\n",
        .{},
    );
    while (!self.terminated and stepBudgetAllows(self.max_steps, steps)) : (steps +|= 1) {
        self.executed_steps = steps;

        // Two comparisons and a bit test on the overwhelmingly common
        // path. This is what turns "no log line said VdSwap(" into "the
        // instruction pointer did or did not reach VdSwap".
        if (self.execution_tracepoints.mightMatch(self.regs.rip)) {
            self.noteExecutionTracepoint();
        }

        // Never interpret the register file after the cooperative
        // scheduler has parked its owner. A zero active handle means the
        // registers are merely the last saved context, not executable
        // work. Try real queued work once, then stop with a precise
        // invariant failure instead of manufacturing millions of steps.
        if (self.cooperative_ui_context != null and self.active_guest_thread == 0) {
            if (!self.recoverZeroActiveGuestThread()) break;
        }

        // Update scheduler step
        // self.thread_scheduler.updateStep(steps);

        // Update scheduler with current context
        // self.thread_scheduler.setUIContext(self.cooperative_ui_context != null);
        // self.thread_scheduler.updatePendingIdle(self.pendingIdleCallbackCount());
        // self.thread_scheduler.updateDeferredThreads(self.pthreads.deferred_threads);
        next_progress_report -|= 1;
        if (next_progress_report == 0) {
            next_progress_report = PROGRESS_REPORT_INTERVAL;
            self.reportProgressCheckpoint(steps);
            if (self.consumeHostTerminationRequest()) break;
        }
        next_heartbeat -|= 1;
        if (next_heartbeat == 0) {
            next_heartbeat = HEARTBEAT_INTERVAL;
            self.reportHeartbeat(steps);
        }
        if (self.concise_output and steps >= next_concise_report) {
            next_concise_report +%= CONCISE_PROGRESS_INTERVAL;
            self.reportConciseProgress(steps);
        }
        if (!self.step()) break;
        self.maybeYieldActiveGuestThreadForQuantum();
        next_memory_init_report -|= 1;
        if (self.page_entry_bulk_initializations != 0 and next_memory_init_report == 0) {
            next_memory_init_report = 1_000_000;
            self.logMemoryInitializationProgress(steps);
        }
    }
    self.finishRun(steps);
}

pub noinline fn finishRun(self: anytype, steps: u64) void {
    if (self.mem_init_started and !self.faulted) {
        machoCapturePrint(
            "macho-processor: memory initialization completed: step={d} page_entry(runs/bytes)={d}/{d} heap=0x{x}\n",
            .{ steps, self.page_entry_bulk_initializations, self.page_entry_bulk_bytes, self.heap_next },
        );
        self.mem_init_started = false;
    }
    if (self.max_steps != 0 and steps >= self.max_steps) {
        log.warn("reached max steps ({d})", .{self.max_steps});
        self.faulted = true;
        self.exit_code = 124;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.max_steps_reached);
        self.terminated = true;
    }
    if (self.unresolved_import_count != 0) {
        const current_reason = exit_diagnostics.reasonFromValue(self.termination_reason);
        if (current_reason == .unknown or current_reason == .ret_stack_empty or current_reason == .exit_syscall) {
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
        }
    }
    const recorded_reason = exit_diagnostics.reasonFromValue(self.termination_reason);
    const inferred_reason = exit_diagnostics.inferReason(recorded_reason, .{
        .faulted = self.faulted,
        .memory_access_failure = self.terminal_memory_failure != null,
        .control_transfer_failure = self.terminal_control_transfer != null,
    });
    const normalized_reason = exit_diagnostics.normalizeReason(inferred_reason, self.unresolved_import_count);
    if (normalized_reason != recorded_reason) {
        machoCapturePrint(
            "macho-processor: diagnostics invariant repaired: reason={s} faulted={} reclassified={s}\n",
            .{ @tagName(recorded_reason), self.faulted, @tagName(normalized_reason) },
        );
        self.termination_reason = @intFromEnum(normalized_reason);
    }
    if (self.termination_reason == @intFromEnum(exit_diagnostics.TerminationReason.host_termination_signal)) {
        self.logHostTerminationSnapshot(steps);
    } else if (self.terminated and (self.exit_code != 0 or self.unresolved_import_count != 0)) {
        self.logExitDiagnostics();
    }
    self.jit_log.emit(.{
        .kind = .process_exit,
        .step = steps,
        .total_functions = @intCast(self.import_resolver.total_calls),
        .unique_ordinals = @intCast(self.import_resolver.total_calls),
        .code_cache_bytes = @intCast(self.memory_forwarder.summary().allocations *| 4096),
        .thread_id = self.active_guest_thread,
        .exit_code = @as(i32, @intCast(self.exit_code & 0xFFFFFFFF)),
        .reason = @tagName(recorded_reason),
    });
    self.macho_log.emit(.{
        .kind = .process_exit,
        .step = steps,
        .thread_id = self.active_guest_thread,
        .runnable = @intCast(self.pthreads.activeCount()),
        .blocked = @intCast(self.pthreads.blocked_threads),
        .condvar_waits = self.pthreads.collapsed_waits,
        .import_calls = self.import_resolver.total_calls,
        .exit_code = @as(i32, @intCast(self.exit_code & 0xFFFFFFFF)),
        .reason = @tagName(recorded_reason),
    });
}

pub fn consumeHostTerminationRequest(self: anytype) bool {
    const request = host_termination.take() orelse return false;
    const supervisor = host_termination.supervisorContext();
    self.host_termination_signal = request.number;
    self.exit_code = request.exitCode();
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.host_termination_signal);
    self.terminated = true;
    self.faulted = false;
    machoCapturePrint(
        "macho-processor: HOST TERMINATION REQUEST signal={d}({s}) owner={s} configured_timeout_seconds={d} step={d} rip=0x{x}; guest execution was live and no decoder, memory, control-flow, or GPU fault caused this stop\n",
        .{
            request.number,
            request.name(),
            if (supervisor.name.len != 0) supervisor.name else "unidentified host/user",
            supervisor.timeout_seconds,
            self.executed_steps,
            self.regs.rip,
        },
    );
    return true;
}

pub noinline fn logHostTerminationSnapshot(self: anytype, steps: u64) void {
    const request = host_termination.Request{ .number = self.host_termination_signal };
    const supervisor = host_termination.supervisorContext();
    machoCapturePrint(
        "macho-processor: HOST TERMINATION SNAPSHOT signal={d}({s}) owner={s} configured_timeout_seconds={d} step={d} phase={s} rip=0x{x} active_thread=0x{x} blocked_threads={d} suspended_contexts={d} faulted={} terminal_memory_failure={} terminal_control_transfer={}; classification=INTENTIONAL_OR_EXTERNAL_STOP_NOT_CRASH\n",
        .{
            request.number,
            request.name(),
            if (supervisor.name.len != 0) supervisor.name else "unidentified host/user",
            supervisor.timeout_seconds,
            steps,
            @tagName(self.startup.phase),
            self.regs.rip,
            self.active_guest_thread,
            self.pthreads.blocked_threads,
            self.suspended_guest_thread_count,
            self.faulted,
            self.terminal_memory_failure != null,
            self.terminal_control_transfer != null,
        },
    );
    macho_log.checkPointSync();
}

pub fn logDecodeCacheSummary(self: anytype) void {
    proc_diag.logDecodeCacheSummary(self);
}

pub fn logPerformanceHeartbeat(self: anytype) void {
    proc_diag.logPerformanceHeartbeat(self);
}

pub fn logPerformanceAccelerationSummary(self: anytype) void {
    proc_diag.logPerformanceAccelerationSummary(self);
}

pub fn logSharedControlBlockSummary(self: anytype) void {
    proc_diag.logSharedControlBlockSummary(self);
}

pub fn logExitDiagnostics(self: anytype) void {
    proc_diag.logExitDiagnostics(self);
}

pub fn releaseBarrier() void {
    proc_diag.releaseBarrier();
}

pub fn logAtomicDiagnostic(self: anytype, matched: bool, size: Size, addr: u64, expected: u64, actual: u64, replacement: u64, is_locked: bool, rax_before: u64, rflags_before: u32) void {
    proc_diag.logAtomicDiagnostic(self, matched, size, addr, expected, actual, replacement, is_locked, rax_before, rflags_before);
}

pub fn execute(self: anytype, initial_d: DecodedInsn) void {
    return execute_impl.execute(self, initial_d);
}

pub fn executeFucomip(self: anytype, source: u3) void {
    execution_helpers.executeFucomip(self, source);
}

pub fn executeFucomi(self: anytype, source: u3) void {
    execution_helpers.executeFucomi(self, source);
}

pub fn executeFcomi(self: anytype, source: u3) void {
    execution_helpers.executeFcomi(self, source);
}

pub fn executeFcomip(self: anytype, source: u3) void {
    execution_helpers.executeFcomip(self, source);
}

pub fn executeFcmov(self: anytype, source: u3, condition: Cond) void {
    execution_helpers.executeFcmov(self, source, condition);
}

pub fn executeBitScan(self: anytype, d: DecodedInsn) void {
    execution_helpers.executeBitScan(self, d);
}

pub fn executeRotate(self: anytype, d: DecodedInsn) void {
    execution_helpers.executeRotate(self, d);
}

pub fn executeVexScalarF32(self: anytype, d: DecodedInsn, operation: VexArithmetic) void {
    execution_helpers.executeVexScalarF32(self, d, operation);
}

pub fn executeVexScalarF64(self: anytype, d: DecodedInsn, operation: VexArithmetic) void {
    execution_helpers.executeVexScalarF64(self, d, operation);
}

pub fn executeVexPackedF32(self: anytype, d: DecodedInsn, operation: VexArithmetic) void {
    execution_helpers.executeVexPackedF32(self, d, operation);
}

pub fn executeVexPackedF64(self: anytype, d: DecodedInsn, operation: VexArithmetic) void {
    execution_helpers.executeVexPackedF64(self, d, operation);
}

pub fn executeVexSqrtScalarF32(self: anytype, d: DecodedInsn) void {
    execution_helpers.executeVexSqrtScalarF32(self, d);
}

pub fn executeVexSqrtScalarF64(self: anytype, d: DecodedInsn) void {
    execution_helpers.executeVexSqrtScalarF64(self, d);
}

pub fn reportUnsupportedComparePredicate(self: anytype, d: DecodedInsn, executed: bool) void {
    if (executed) return;
    machoCapturePrint(
        "macho-processor: unsupported SIMD compare predicate: op={s} imm=0x{x} rip=0x{x}; the comparison was not performed rather than performed with a guessed relation\n",
        .{ @tagName(d.op), d.imm, self.regs.rip },
    );
    self.faulted = true;
    self.exit_code = 127;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unimplemented_instruction);
    self.terminated = true;
}

pub fn executeVexReciprocalPacked(self: anytype, d: DecodedInsn, comptime square_root: bool) void {
    execution_helpers.executeVexReciprocalPacked(self, d, square_root);
}

pub fn executeVexReciprocalScalar(self: anytype, d: DecodedInsn, comptime square_root: bool) void {
    execution_helpers.executeVexReciprocalScalar(self, d, square_root);
}

pub fn executeVexConvertPacked(
    self: anytype,
    d: DecodedInsn,
    comptime direction: @TypeOf(.enum_literal),
) void {
    execution_helpers.executeVexConvertPacked(self, d, direction);
}

pub fn executeVexComparePacked(self: anytype, d: DecodedInsn, comptime double: bool) bool {
    return execution_helpers.executeVexComparePacked(self, d, double);
}

pub fn executeVexCompareScalar(self: anytype, d: DecodedInsn, comptime double: bool) bool {
    return execution_helpers.executeVexCompareScalar(self, d, double);
}

pub fn executeVexSqrtPackedF32(self: anytype, d: DecodedInsn) void {
    execution_helpers.executeVexSqrtPackedF32(self, d);
}

pub fn executeVexSqrtPackedF64(self: anytype, d: DecodedInsn) void {
    execution_helpers.executeVexSqrtPackedF64(self, d);
}

pub fn setVexComparisonFlags(self: anytype, lhs: anytype, rhs: @TypeOf(lhs)) void {
    execution_helpers.setVexComparisonFlags(self, lhs, rhs);
}

pub fn executeVexBitwise(self: anytype, d: DecodedInsn, operation: VexBitwise) void {
    execution_helpers.executeVexBitwise(self, d, operation);
}

pub fn executeAddRegImm(self: anytype, d: DecodedInsn, sz: Size) void {
    self.executeHighwayImmediate(d, .add, sz, false);
}

pub fn raiseDivideError(self: anytype) void {
    self.faulted = true;
    self.terminated = true;
    self.exit_code = 136;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.divide_by_zero);
}

pub fn executeSubRegImm(self: anytype, d: DecodedInsn, sz: Size) void {
    self.executeHighwayImmediate(d, .sub, sz, false);
}

pub fn executeAndRegImm(self: anytype, d: DecodedInsn) void {
    self.executeHighwayImmediate(d, .bit_and, d.size, false);
}

pub fn resolveSyscallFd(self: anytype, guest_fd: u64) i32 {
    if (guest_fd < self.guest_fds.len) {
        const host = self.guest_fds[@as(usize, @intCast(guest_fd))];
        if (host >= 0) return host;
    }
    if (self.fs_forwarder.fd_manager.hostFd(guest_fd)) |host| return host;
    return -1;
}

pub fn dispatchMacOSSyscall(self: anytype, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
    const number = self.regs.rax;
    log.info("syscall: number=0x{x} ({s}) args=({d}, {d}, {d}, {d}, {d}, {d})", .{
        number, macho_runtime.syscallName(number),
        arg1,   arg2,
        arg3,   arg4,
        arg5,   arg6,
    });

    switch (number) {
        @intFromEnum(macho_runtime.Syscall.exit) => {
            const exit_code = arg1;
            log.info("exit({d})", .{exit_code});
            self.guest_exit_observed = true;
            self.guest_exit_code = exit_code;
            self.guest_exit_step = self.executed_steps;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
            self.terminated = true;
            self.exit_code = exit_code;
        },
        @intFromEnum(macho_runtime.Syscall.open) => {
            const path = self.guestCString(arg1, 4096) orelse {
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            };
            var temp_buf: [4096]u8 = undefined;
            var translated_path = path;
            if (self.fs_forwarder.resolveHostPath(path, &temp_buf)) |t| {
                translated_path = t;
            }
            var path_buf: [4096]u8 = undefined;
            const plen = @min(translated_path.len, path_buf.len - 1);
            @memcpy(path_buf[0..plen], translated_path[0..plen]);
            path_buf[plen] = 0;
            const oflags: std.c.O = @bitCast(@as(u32, @truncate(arg2)));
            const mode: std.c.mode_t = @intCast(arg3 & 0xFFFF);
            var host_fd = std.c.open(@as([*:0]const u8, @ptrCast(&path_buf)), oflags, mode);
            if (host_fd < 0) {
                const err = std.c.errno(host_fd);
                if (err == .NOENT) {
                    if (self.fs_forwarder.tryOpenFallback(translated_path, oflags, @as(u32, @intCast(arg3)), err)) |fallback_fd| {
                        host_fd = fallback_fd;
                    }
                }
                if (host_fd < 0) {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                }
            }
            const guest_fd = self.fs_forwarder.fd_manager.register(host_fd, .file) orelse {
                _ = std.c.close(host_fd);
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            };
            if (guest_fd < self.guest_fds.len) {
                self.guest_fds[@as(usize, @intCast(guest_fd))] = host_fd;
            }
            self.regs.rax = guest_fd;
        },
        @intFromEnum(macho_runtime.Syscall.close) => {
            const close_guest_fd = arg1;
            if (close_guest_fd < self.guest_fds.len) {
                self.guest_fds[@as(usize, @intCast(close_guest_fd))] = -1;
            }
            const rc = self.fs_forwarder.fd_manager.close(close_guest_fd);
            self.regs.rax = if (rc < 0) std.math.maxInt(u64) else 0;
        },
        @intFromEnum(macho_runtime.Syscall.write) => {
            const fd = arg1;
            const buf = arg2;
            const count = arg3;
            const data = self.guestMemoryConst(buf, count) orelse {
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                return;
            };
            const host_fd = self.resolveSyscallFd(fd);
            var written: usize = 0;
            if (host_fd >= 0) {
                while (written < data.len) {
                    const n = std.c.write(host_fd, data[written..].ptr, data.len - written);
                    if (n <= 0) {
                        self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                        return;
                    }
                    written += @as(usize, @intCast(n));
                }
            }
            self.regs.rax = @intCast(written);
        },
        @intFromEnum(macho_runtime.Syscall.read) => {
            const fd = arg1;
            const buf = arg2;
            const count = arg3;
            const data = self.guestMemory(buf, count) orelse {
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                return;
            };
            const host_fd = self.resolveSyscallFd(fd);
            if (host_fd >= 0) {
                const n = std.c.read(host_fd, data.ptr, data.len);
                if (n < 0) {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                }
                self.regs.rax = @intCast(@as(usize, @intCast(n)));
            } else {
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
            }
        },
        @intFromEnum(macho_runtime.Syscall.mmap) => {
            const addr = arg1;
            const length = arg2;
            const prot = arg3;
            const raw_flags: u32 = @truncate(arg4);
            const map_flags: std.c.MAP = @bitCast(raw_flags);
            const offset: i64 = @bitCast(arg6);
            self.noteBackendMmapAttempt("syscall", addr, length, prot, raw_flags, map_flags.FIXED, map_flags.ANONYMOUS);

            const alignment = PAGE_SIZE;
            const aligned_length = ((length + alignment - 1) / alignment) * alignment;

            if (self.backendMemoryDiagnosticsActive() and addr == 0 and map_flags.ANONYMOUS and length >= 64 * 1024 * 1024) {
                const mapped = self.guestMapBackendWithBacking(length, @truncate(prot), raw_flags, -1, @bitCast(offset)) orelse {
                    machoCapturePrint(
                        "macho-processor: x64 backend sparse mmap FAILED: route=syscall address=0x0 length={d} prot=0x{x} flags=0x{x}\n",
                        .{ length, prot, raw_flags },
                    );
                    self.noteBackendMmapResult(false, 0, "syscall_backend_sparse_anywhere");
                    self.regs.rax = std.math.maxInt(u64);
                    return;
                };
                machoCapturePrint(
                    "macho-processor: x64 backend sparse mmap succeeded: route=syscall guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} heap_bypassed=true\n",
                    .{ mapped, length, prot, raw_flags },
                );
                self.noteBackendMmapResult(true, mapped, "syscall_backend_sparse_anywhere");
                self.regs.rax = mapped;
                return;
            }

            if (length >= 1024 * 1024 * 1024) {
                machoCapturePrint(
                    "macho-processor: large mmap entry: route=syscall addr=0x{x} length={d} aligned_length={d} prot=0x{x} flags=0x{x} fixed={} anonymous={} guest_fd=0x{x} offset={d}\n",
                    .{ addr, length, aligned_length, prot, raw_flags, map_flags.FIXED, map_flags.ANONYMOUS, arg5, offset },
                );
            }

            if (addr == 0 and prot == 0 and length >= 1024 * 1024 * 1024) {
                const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                    -1
                else
                    self.fs_forwarder.fd_manager.hostFd(arg5) orelse {
                        machoCapturePrint("macho-processor: large mmap FAILED: route=syscall stage=fd_translation guest_fd=0x{x}\n", .{arg5});
                        self.noteBackendMmapResult(false, 0, "syscall_large_fd_translation");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    };
                const reserved = self.guestReserveAddressSpaceWithBacking(aligned_length, raw_flags, host_fd, @bitCast(offset)) orelse {
                    machoCapturePrint("macho-processor: large mmap FAILED: route=syscall stage=sparse_reserve\n", .{});
                    self.noteBackendMmapResult(false, 0, "syscall_sparse_reserve");
                    self.regs.rax = std.math.maxInt(u64);
                    return;
                };
                machoCapturePrint("macho-processor: large mmap succeeded: route=syscall guest_base=0x{x} length={d}\n", .{ reserved, aligned_length });
                self.noteBackendMmapResult(true, reserved, "syscall_sparse_reserve");
                self.regs.rax = reserved;
                return;
            }

            if (addr != 0 and map_flags.FIXED) {
                const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                    -1
                else
                    self.fs_forwarder.fd_manager.hostFd(arg5) orelse {
                        machoCapturePrint("macho-processor: fixed mmap FAILED: route=syscall stage=fd_translation guest_fd=0x{x}\n", .{arg5});
                        self.noteBackendMmapResult(false, 0, "syscall_fixed_fd_translation");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    };
                if (!self.guestMapFile(addr, aligned_length, @truncate(prot), raw_flags, host_fd, @bitCast(offset))) {
                    machoCapturePrint("macho-processor: fixed mmap FAILED: route=syscall stage=sparse_map addr=0x{x} length={d}\n", .{ addr, aligned_length });
                    self.noteBackendMmapResult(false, 0, "syscall_fixed_sparse_map");
                    self.regs.rax = std.math.maxInt(u64);
                    return;
                }
                self.noteBackendMmapResult(true, addr, "syscall_fixed_sparse_map");
                self.regs.rax = addr;
                return;
            }

            const mapped = if (addr != 0) addr else self.guestAlloc(aligned_length, alignment) orelse {
                machoCapturePrint("macho-processor: mmap FAILED: route=syscall stage=guest_heap length={d} alignment={d}\n", .{ aligned_length, alignment });
                self.noteBackendMmapResult(false, 0, "syscall_guest_heap_allocate");
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            };
            const off = mappedOffset(self.mem_base, self.mem_size, self.mapped_min, mapped) orelse {
                self.noteBackendMmapResult(false, 0, "syscall_address_translation");
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            };
            if (off + aligned_length > self.mem_size) {
                self.noteBackendMmapResult(false, 0, "syscall_backing_bounds");
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            }
            @memset(self.mem[off..][0..@as(usize, @intCast(aligned_length))], 0);
            self.setPagePermissions(mapped, aligned_length, @truncate(prot & 0x07));
            _ = self.memory_regions.register(mapped, aligned_length, .{
                .read = prot & 0x01 != 0,
                .write = prot & 0x02 != 0,
                .execute = prot & 0x04 != 0,
            }, .guest_mmap, "guest mmap", self.regs.rip);
            self.noteBackendMmapResult(true, mapped, "syscall_guest_mapping");
            self.regs.rax = mapped;
        },
        @intFromEnum(macho_runtime.Syscall.mprotect) => {
            const address = arg1;
            const length = ((arg2 + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE;
            const prot = arg3;
            if (self.guestProtectSparseMemory(address, length, @truncate(prot))) {
                machoCapturePrint("macho-processor: sparse mprotect succeeded: route=syscall address=0x{x} length={d} prot=0x{x}\n", .{ address, length, prot });
                self.noteBackendMprotect("syscall", address, length, prot, true);
                self.regs.rax = 0;
                return;
            }
            if (mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) == null) {
                machoCapturePrint("macho-processor: mprotect FAILED: route=syscall reason=address_not_mapped address=0x{x} length={d} prot=0x{x}\n", .{ address, length, prot });
                self.noteBackendMprotect("syscall", address, length, prot, false);
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            }
            self.setPagePermissions(address, length, @truncate(prot & 0x07));
            _ = self.memory_regions.register(address, length, .{
                .read = prot & 0x01 != 0,
                .write = prot & 0x02 != 0,
                .execute = prot & 0x04 != 0,
            }, .guest_mmap, "guest mprotect", self.regs.rip);
            self.noteBackendMprotect("syscall", address, length, prot, true);
            self.regs.rax = 0;
        },
        @intFromEnum(macho_runtime.Syscall.munmap) => {
            const address = arg1;
            const length = ((arg2 + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE;
            if (self.guestUnmapFile(address, length)) {
                machoCapturePrint("macho-processor: sparse munmap succeeded: route=syscall address=0x{x} length={d}\n", .{ address, length });
                self.regs.rax = 0;
                return;
            }
            self.setPagePermissions(address, length, 0);
            _ = self.memory_regions.register(address, length, .{ .read = false, .write = false }, .guest_unmapped, "guest munmap", self.regs.rip);
            self.regs.rax = 0;
        },
        @intFromEnum(macho_runtime.Syscall.getpid) => {
            self.regs.rax = 42;
        },
        @intFromEnum(macho_runtime.Syscall.issetugid) => {
            self.regs.rax = 0;
        },
        0x2000072 => {
            self.regs.rax = 1;
        },
        else => {
            log.warn("unimplemented syscall: 0x{x}", .{number});
            self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
        },
    }
}
