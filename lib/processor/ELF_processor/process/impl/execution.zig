const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_block_jit = @import("block_jit.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_instruction_decode = @import("instruction_decode.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_legacy_vector_ops = @import("legacy_vector_ops.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_run_reporting = @import("run_reporting.zig");
const process_impl_syscalls = @import("syscalls.zig");
const process_impl_windows_audio = @import("windows_audio.zig");
const process_impl_windows_sync = @import("windows_sync.zig");
const __process_BitScanKind = __ProcessInternals._BitScanKind;
const __process_Cond = __ProcessInternals._Cond;
const __process_DecodedInsn = __ProcessInternals._DecodedInsn;
const __process_GuestExecutionGate = __ProcessInternals._GuestExecutionGate;
const __process_Op = __ProcessInternals._Op;
const __process_RFL_AF = __ProcessInternals._RFL_AF;
const __process_RFL_CF = __ProcessInternals._RFL_CF;
const __process_RFL_DF = __ProcessInternals._RFL_DF;
const __process_RFL_OF = __ProcessInternals._RFL_OF;
const __process_RFL_PF = __ProcessInternals._RFL_PF;
const __process_RFL_SF = __ProcessInternals._RFL_SF;
const __process_RFL_ZF = __ProcessInternals._RFL_ZF;
const __process_RegId = __ProcessInternals._RegId;
const __process_Size = __ProcessInternals._Size;
const __process_TRACE_BUFFER_LEN = __ProcessInternals._TRACE_BUFFER_LEN;
const __process_WINDOWS_NULL_PAGE_LIMIT = __ProcessInternals._WINDOWS_NULL_PAGE_LIMIT;
const __process_WindowsGuestThread = __ProcessInternals._WindowsGuestThread;
const __process_X87Raw = __ProcessInternals._X87Raw;
const __process_XENIA_SHA1_FEED_MINIMUM = __ProcessInternals._XENIA_SHA1_FEED_MINIMUM;
const __process_block_jit = __ProcessInternals._block_jit;
const __process_cleoRouteFor = __ProcessInternals._cleoRouteFor;
const __process_cleo_routing = __ProcessInternals._cleo_routing;
const __process_concurrency = __ProcessInternals._concurrency;
const __process_decodeInsn = __ProcessInternals._decodeInsn;
const __process_evex = __ProcessInternals._evex;
const __process_exit_context = __ProcessInternals._exit_context;
const __process_exit_diagnostics = __ProcessInternals._exit_diagnostics;
const __process_guest_backtrace = __ProcessInternals._guest_backtrace;
const __process_guest_page_protection = __ProcessInternals._guest_page_protection;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_hostFdFromGuest = __ProcessInternals._hostFdFromGuest;
const __process_host_fp_control = __ProcessInternals._host_fp_control;
const __process_log = __ProcessInternals._log;
const __process_monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const __process_shouldTraceRip = __ProcessInternals._shouldTraceRip;
const __process_shuffleBytes = __ProcessInternals._shuffleBytes;
const __process_shufflePackedDoublesLane = __ProcessInternals._shufflePackedDoublesLane;
const __process_shufflePackedSinglesLane = __ProcessInternals._shufflePackedSinglesLane;
const __process_signExtendImm8 = __ProcessInternals._signExtendImm8;
const __process_std = __ProcessInternals._std;
const __process_syscallResult = __ProcessInternals._syscallResult;
const __process_terminal_event = __ProcessInternals._terminal_event;
const __process_testImmForSize = __ProcessInternals._testImmForSize;
const __process_tso_memory = __ProcessInternals._tso_memory;
const __process_tso_memory_policy = __ProcessInternals._tso_memory_policy;
const __process_vector_helpers = __ProcessInternals._vector_helpers;
const __process_windows_guest_abi = __ProcessInternals._windows_guest_abi;
const __process_x64_decoder = __ProcessInternals._x64_decoder;
const __process_x64_guest_abi = __ProcessInternals._x64_guest_abi;
const __process_x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const __process_x64_syscalls = __ProcessInternals._x64_syscalls;
const __process_xenia_accelerator = __ProcessInternals._xenia_accelerator;
const __process_xenia_event_audit = __ProcessInternals._xenia_event_audit;
const __process_xenia_sha1_kernel_feed_body = __ProcessInternals._xenia_sha1_kernel_feed_body;
const __state_ExitContextSource = __StateInternals._ExitContextSource;
const __state_OpBitset = __StateInternals._OpBitset;
const __state_evex_handled_bits = __StateInternals._evex_handled_bits;
const __state_vector_operation_bits = __StateInternals._vector_operation_bits;

pub fn runWithLimit(self: *ElfState, max_steps: u64) void {
    // PE launches use the coordinated parallel executor by default;
    // `ROSETTE_PE64_PARALLEL=0` keeps every guest thread on this host
    // thread (the cooperative executor), as an A/B switch for anything
    // that looks like a concurrency defect. Unit tests exercise the
    // serial scheduler deterministically unless they opt in.
    if (comptime !@import("builtin").is_test) {
        if (self.windows_runtime_enabled and !self.parallel_guest_execution and process_impl_block_jit.parallelGuestExecutionRequested()) {
            process_impl_block_jit.setParallelGuestExecution(self, true);
        }
    }
    self.exit_fault_regs = null;
    self.exit_fault_thread_slot = null;
    self.exit_fault_op = null;
    self.exit_fault_len = null;
    self.parallel_fault_snapshot.reset();
    self.windows_xmutant_release_compat_calls.store(0, .monotonic);
    self.windows_xmutant_stale_backing_deletes_skipped.store(0, .monotonic);
    if (self.parallel_guest_execution) {
        self.parallel_guest_termination.store(false, .release);
        self.parallel_owner_executed_steps.store(0, .release);
    }
    if (self.run_started_ns == 0) self.run_started_ns = __process_monotonicNanoseconds();
    // This host thread runs the process owner's guest thread. Name it for
    // the stall watchdog; on the main thread, serve AppKit requests from
    // inside every wait (see `installMainThreadParkService`).
    const owner_record_registered = __process_concurrency.watch.currentRecord() == null and
        __process_concurrency.watch.registerCurrentThread("PE owner guest thread") != null;
    defer if (owner_record_registered) __process_concurrency.watch.unregisterCurrentThread();
    const previous_park_service = process_impl_block_jit.installMainThreadParkService(self);
    defer _ = __process_concurrency.park.installService(previous_park_service);
    var stall_watchdog: ?__process_concurrency.Watchdog = null;
    if (self.parallel_guest_execution and self.windows_runtime_enabled) {
        stall_watchdog = .{
            .config = .{
                .threshold_ns = process_impl_block_jit.parallelStallThresholdNanoseconds(),
                .pulse_interval_ns = process_impl_block_jit.parallelThreadPulseNanoseconds(),
                .lock_hold_threshold_ns = process_impl_block_jit.parallelLockHoldThresholdNanoseconds(),
            },
            .context = @ptrCast(self),
            .report = process_impl_block_jit.reportConcurrencyStall,
            .progress = process_impl_block_jit.concurrencyProgress,
            .gate = &self.guest_execution_gate,
            .lock = &self.windows_runtime_mutex.inner,
            .pulse = process_impl_block_jit.reportConcurrencyPulse,
        };
        stall_watchdog.?.start() catch |err| {
            __process_log.info("PE64 CONCURRENCY: stall watchdog unavailable ({s}); a hang will be reported only by its absence of progress lines", .{@errorName(err)});
            stall_watchdog = null;
        };
    }
    defer if (stall_watchdog) |*watchdog| watchdog.stop();
    var steps: u64 = 0;
    const worker_steps_at_start = process_impl_lifecycle.windowsWorkerSteps(self);
    if (__process_std.c.getenv("ROSETTE_RUN_ID")) |raw_run_id| {
        const run_id = __process_std.mem.sliceTo(raw_run_id, 0);
        if (run_id.len != 0) {
            const build_identity = if (__process_std.c.getenv("ROSETTE_BUILD_IDENTITY_SHA256")) |raw_hash|
                __process_std.mem.sliceTo(raw_hash, 0)
            else
                "unavailable";
            __process_log.info("PE64 RUN CONTEXT: run_id={s} build_identity_sha256={s}; launcher manifest is the source of scenario, media, and settings metadata", .{ run_id, build_identity });
        }
    }
    const watch_progress = self.windows_runtime_enabled and self.windows_progress.enabled;
    if (watch_progress) self.windows_progress.next_sample_step = self.windows_progress.interval;
    const checkpoint_interval: u64 = 50_000_000;
    var next_checkpoint_step: u64 = 0;
    while (!process_impl_lifecycle.isTerminated(self) and (max_steps == 0 or process_impl_run_reporting.runBudgetSteps(steps, worker_steps_at_start, process_impl_lifecycle.windowsWorkerSteps(self)) < max_steps)) : (steps +|= process_impl_lifecycle.guestContextField(self, "step_retired").*) {
        self.executed_steps = steps;
        if (self.parallel_guest_execution) self.parallel_owner_executed_steps.store(steps, .release);
        const total_steps = process_impl_lifecycle.observedExecutionSteps(self);
        if (self.windows_runtime_enabled and total_steps >= self.run_next_heartbeat_instructions) {
            // Diagnostics read the runtime's tables: the runtime lock, not a
            // stop-the-world. Other threads' registers are read racily,
            // which a report can afford.
            var heartbeat_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
            defer if (heartbeat_guard) |*guard| guard.unlock();
            process_impl_run_reporting.logRunHeartbeat(self, total_steps);
        }
        if (watch_progress) {
            // Two comparisons per step is the whole per-instruction cost
            // of the watchdog; everything else happens once per sample
            // window.
            const rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
            if (rip < self.windows_progress.window_rip_low) self.windows_progress.window_rip_low = rip;
            if (rip > self.windows_progress.window_rip_high) self.windows_progress.window_rip_high = rip;
            if (total_steps >= self.windows_progress.next_sample_step) process_impl_run_reporting.checkWindowsProgress(self);
        }
        if (self.windows_main_wait_handle != 0) {
            // A waiting owner is the one time another thread may finish
            // its call for it; the tripwire re-arms at its next step.
            self.owner_register_tripwire.disarm();
            if (process_impl_windows_sync.windowsWaitObjectSignaled(self, self.windows_main_wait_handle)) {
                // Leave RIP at the import stub.  The next ordinary step
                // retries the wait and consumes the object's signal,
                // producing the real WAIT_OBJECT_0 return path.
                self.windows_main_wait_handle = 0;
            } else {
                const serviced = process_impl_windows_sync.serviceWindowsGuestThreads(self, process_impl_windows_sync.windowsGuestWaitServiceSlice(self));
                if (serviced != 0 and self.trace_windows_waits and
                    (self.windows_thread_service_calls <= 8 or self.windows_thread_service_calls % 1024 == 0))
                {
                    __process_log.info("PE64 main wait service: handle=0x{x} kind={s} steps={d} service_calls={d} yields={d} blocks={d} unblocks={d} completions={d} graphics_phase={s} vk_calls={d} submits={d} presents={d}", .{
                        self.windows_main_wait_handle,
                        process_impl_windows_sync.windowsWaitObjectKindName(self, self.windows_main_wait_handle),
                        serviced,
                        self.windows_thread_service_calls,
                        self.windows_thread_yields,
                        self.windows_thread_blocks,
                        self.windows_thread_unblocks,
                        self.windows_thread_completions,
                        @tagName(self.windows_graphics.phase),
                        self.windows_graphics.vulkan_calls,
                        self.windows_graphics.queue_submits,
                        self.windows_graphics.presents,
                    });
                }
                if (serviced == 0) {
                    // Park until a signal or a thread wake, at most a
                    // millisecond. A park - not a sleep - so the main
                    // thread keeps serving the AppKit requests guest
                    // workers dispatch to it while it waits; a raw sleep
                    // here is the other half of the 2026-09-25 deadlock.
                    const observed = self.parallel_guest_wake_hub.epoch();
                    if (!process_impl_windows_sync.windowsWaitObjectSignaled(self, self.windows_main_wait_handle)) {
                        _ = self.parallel_guest_wake_hub.event.waitChange(observed, __process_concurrency.monotonicNanoseconds() +| __process_std.time.ns_per_ms);
                    }
                }
                continue;
            }
        }
        if (total_steps >= next_checkpoint_step) {
            var checkpoint_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
            defer if (checkpoint_guard) |*guard| guard.unlock();
            next_checkpoint_step +|= checkpoint_interval;
            __process_log.info("step {d}: rip=0x{x}, rax=0x{x}, rbx=0x{x}, rcx=0x{x}, rsi=0x{x}, rdi=0x{x}", .{ total_steps, process_impl_lifecycle.guestContextField(self, "regs").*.rip, process_impl_lifecycle.guestContextField(self, "regs").*.rax, process_impl_lifecycle.guestContextField(self, "regs").*.rbx, process_impl_lifecycle.guestContextField(self, "regs").*.rcx, process_impl_lifecycle.guestContextField(self, "regs").*.rsi, process_impl_lifecycle.guestContextField(self, "regs").*.rdi });
            if (self.trace_graphics_progress and self.windows_runtime_enabled) process_impl_run_reporting.logGraphicsProgress(self, total_steps);
            // The presentation chain at the same cadence as everything
            // else: a black window with a healthy present count is the
            // one failure whose evidence is entirely outside the counters
            // printed above, and it has to be readable without waiting
            // for the run to end.
            process_impl_kernel_services.reportPresentChainCheckpoint(self);
            // Report a newly-degraded import at the checkpoint rather
            // than only at exit: a run that is killed while it is still
            // going would otherwise take that evidence with it.  A run
            // that degrades nothing new says nothing.
            if (self.windows_runtime_enabled) process_impl_kernel_services.reportWindowsImportFallbacks(self, false);
            // Same reasoning for the refusal ledger, and the same rule:
            // only when a name that has not been reported yet is in it.
            if (self.windows_runtime_enabled and self.windows_import_refusals.unreported_count != 0) {
                process_impl_kernel_services.reportWindowsImportRefusals(self);
                self.windows_import_refusals.markReported();
            }
            // This is the handoff immediately before Xenia's Vulkan
            // surface setup and title launch. Emit it at checkpoints so
            // a supervisor SIGTERM cannot erase the only evidence of a
            // posted, dropped, or undispatched WM_USER callback.
            if (self.windows_runtime_enabled) process_impl_guest_diagnostics.reportWindowsUiPipeline(self);
            // The chain reports at the checkpoint too, not only at exit.
            // Every Xenia run so far has ended on SIGTERM from the
            // operator's own timeout, which never reaches the exit path -
            // so the one block that names the earliest unmet precondition
            // was the one thing every run threw away. They are collapsed
            // to their verdicts, and only re-emitted when a verdict moves.
            if (self.windows_runtime_enabled) process_impl_guest_diagnostics.reportRunChainsIfChanged(self, total_steps);
            // Where the executor's own time went, at the same cadence, so
            // a run killed by a supervisor still says whether it was the
            // guest or the executor that was slow.
            if (self.parallel_guest_execution) {
                process_impl_block_jit.reportConcurrency(self);
                process_impl_block_jit.reportRuntimeLockHolds(self);
                process_impl_block_jit.reportWindowsFastImports(self, false);
            }
        }
        process_impl_windows_sync.maybeRunWindowsGuestScheduler(self);
        if (process_impl_lifecycle.isTerminated(self)) break;
        // Nothing between two of the owner's steps writes its registers;
        // in parallel mode, a difference here is another host thread
        // writing the owner's live file (`noteContextRace`).
        if (self.parallel_guest_execution) {
            const owner_regs = &self.regs; // guest_context: owner
            if (self.owner_register_tripwire.check(owner_regs.rip, owner_regs.rsp)) |finding| {
                process_impl_block_jit.noteContextRace(self, self.active_guest_thread, null, finding); // guest_context: owner
            }
        }
        if (!process_impl_block_jit.step(self)) break;
        if (self.parallel_guest_execution) {
            const owner_regs = &self.regs; // guest_context: owner
            self.owner_register_tripwire.arm(owner_regs.rip, owner_regs.rsp);
        }
    }
    if (self.parallel_guest_execution) {
        self.parallel_owner_executed_steps.store(steps, .release);
        const guest_fault_requested = self.parallel_guest_termination.load(.acquire);
        self.parallel_guest_termination.store(true, .release);
        process_impl_lifecycle.stopParallelGuestWorkers(self);
        if (guest_fault_requested) self.terminated = true;
        // The public PE run result reports the work from every executor.
        self.executed_steps = process_impl_lifecycle.observedExecutionSteps(self);
    }
    // A stopped/bounded run hands memory back to the loader, artifact
    // readers and diagnostics, which execute outside the guest TLS scope.
    process_impl_block_jit.flushAllGuestStoreBuffers(self, .shutdown);
    if (self.windows_runtime_enabled) {
        reportGuestStoreBuffers(self);
        process_impl_block_jit.reportConcurrency(self);
        process_impl_guest_memory.reportWindowsMemoryTrace(self);
        if (self.parallel_guest_execution) {
            process_impl_block_jit.reportRuntimeLockHolds(self);
            process_impl_block_jit.reportWindowsFastImports(self, true);
            process_impl_block_jit.reportParallelHazards(self);
        }
        const context_format = "PE64 CONTEXT INTEGRITY: owner_register_file_changes(slice/instruction)={d}/{d} step_audit={} containment=owner_snapshot_restored; a nonzero count is a Rosette defect, with before/after register values and owner/worker register addresses in the first-occurrence samples";
        const context_args = .{ self.owner_context_violations, self.owner_context_step_violations, self.owner_context_audit_steps };
        if (self.owner_context_violations + self.owner_context_step_violations != 0) __process_log.err(context_format, context_args) else __process_log.info(context_format, context_args);
        const callback_abi_format = "PE64 WINDOWS CALLBACK ABI: callbacks={d} clobber_calls={d} gpr_clobber_calls={d} xmm6_15_clobber_calls={d} repairs={d}; DispatchMessageW must preserve its caller's Windows x64 nonvolatile state across the guest WndProc";
        const callback_abi_args = .{
            self.windows_callback_abi_calls,
            self.windows_callback_abi_clobber_calls,
            self.windows_callback_abi_gpr_clobbers,
            self.windows_callback_abi_xmm_clobbers,
            self.windows_callback_abi_repairs,
        };
        if (self.windows_callback_abi_clobber_calls != 0) __process_log.err(callback_abi_format, callback_abi_args) else __process_log.info(callback_abi_format, callback_abi_args);
        const import_abi_format = "PE64 WINDOWS IMPORT ABI: calls={d} normal_returns={d} nonlocal_returns={d} clobber_calls={d} gpr_clobber_calls={d} xmm6_15_clobber_calls={d} repairs={d}; normal imports must preserve RBX/RBP/RSI/RDI/R12-R15 and low XMM6-XMM15, while nonlocal context changes are left untouched";
        const import_abi_args = .{
            self.windows_import_abi_calls,
            self.windows_import_abi_normal_returns,
            self.windows_import_abi_nonlocal_returns,
            self.windows_import_abi_clobber_calls,
            self.windows_import_abi_gpr_clobbers,
            self.windows_import_abi_xmm_clobbers,
            self.windows_import_abi_repairs,
        };
        if (self.windows_import_abi_clobber_calls != 0) __process_log.err(import_abi_format, import_abi_args) else __process_log.info(import_abi_format, import_abi_args);
        const vulkan_stub_format = "PE64 WINDOWS VULKAN STUB INTEGRITY: misaligned_calls={d} exact_repairs={d}; a repair is admitted only for the registered vkGetPhysicalDeviceSurfaceCapabilitiesKHR thunk at +2 from CreateSwapchainForVulkanSurface, with the original thunk byte verified as the import sentinel";
        const vulkan_stub_args = .{ self.windows_vulkan_misaligned_stub_calls, self.windows_vulkan_stub_repairs };
        if (self.windows_vulkan_misaligned_stub_calls != 0) __process_log.warn(vulkan_stub_format, vulkan_stub_args) else __process_log.info(vulkan_stub_format, vulkan_stub_args);
        if (self.windows_iat_mismatches_at_fault != 0) __process_log.err("PE64 WINDOWS IMPORT IAT AUDIT: {d} IAT slot(s) differed from their registered import stubs at the invalid control transfer", .{self.windows_iat_mismatches_at_fault});
        for (self.call_probes.probes[0..self.call_probes.count]) |*probe| {
            __process_log.info("PE64 CALL PROBE SUMMARY: {s} at 0x{x} calls={d} returns={d} logged={d}", .{ probe.name(), probe.address, probe.calls, probe.returns, probe.logged });
        }
    }
    const consumed_steps = process_impl_run_reporting.runBudgetSteps(steps, worker_steps_at_start, process_impl_lifecycle.windowsWorkerSteps(self));
    if (max_steps != 0 and consumed_steps >= max_steps) {
        __process_log.warn("reached max steps ({d}) total={d} owner={d} workers={d}; the bound includes cooperative worker execution", .{
            max_steps,
            consumed_steps,
            steps,
            process_impl_lifecycle.windowsWorkerSteps(self) -| worker_steps_at_start,
        });
        logRegs(self);
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 124;
        self.termination_reason = .max_steps_reached;
        process_impl_lifecycle.markTerminated(self);
        if (self.parallel_guest_execution) self.terminated = true;
    }
    if (self.windows_runtime_enabled) process_impl_guest_diagnostics.flushWindowsGuestOutput(self);
    // The first authentic guest frame can arrive between the last
    // periodic checkpoint and the run's natural/forced exit. ExitProcess
    // bypasses this epilogue, so the loader's atexit summary calls the same
    // idempotent helper as a second authority.
    process_impl_kernel_services.reportPresentChainFinal(self);
    if (self.trace_graphics_progress and self.windows_runtime_enabled) process_impl_run_reporting.logGraphicsStop(self);
    if (self.windows_runtime_enabled and !self.trace_graphics_progress) process_impl_guest_diagnostics.logWindowsGuestFailurePointSummary(self);
    if (self.windows_runtime_enabled) {
        process_impl_windows_audio.logWindowsAudioStop(self);
        // Always reported, including when nothing reached the wave
        // device: the zeroed counter line and the policy/query line make
        // an unstarted audio worker distinguishable from a silent device.
        process_impl_windows_audio.reportAudioChain(self);
        process_impl_kernel_services.reportWindowsImportFallbacks(self, true);
        process_impl_kernel_services.reportWindowsImportRefusals(self);
        const mutant_release_compat_calls = self.windows_xmutant_release_compat_calls.load(.monotonic);
        if (mutant_release_compat_calls != 0) {
            __process_log.warn("PE64 XENIA COMPAT SUMMARY: missing-native-mutant release calls handled={d}; each returned false and let Xenia produce X_STATUS_MUTANT_NOT_OWNED at its own call site", .{mutant_release_compat_calls});
        }
        const stale_mutant_deletes = self.windows_xmutant_stale_backing_deletes_skipped.load(.monotonic);
        if (stale_mutant_deletes != 0) {
            __process_log.warn("PE64 XENIA MUTANT LIFETIME SUMMARY: duplicate deleting-destructor dispatches skipped={d}; each matched the exact XMutant member/call/continuation, the abstract Win32Handle<Mutant> UD2, a 16-byte allocation, a null backing handle, and an intact heap guard; inactive records also had prior XMutant-dtor free provenance", .{stale_mutant_deletes});
        } else {
            __process_log.info("PE64 XENIA MUTANT LIFETIME SUMMARY: repeat deleting-destructor calls skipped=0; stale-backing guard did not alter execution", .{});
        }
        process_impl_kernel_services.reportWindowsCrtState(self);
        process_impl_kernel_services.reportWindowsUnexplainedZeros(self);
        process_impl_guest_diagnostics.reportGuestAddressSpace(self);
        process_impl_windows_sync.reportWindowsUtf8CountDiagnostics(self);
        process_impl_windows_sync.reportWindowsFmtProbeDiagnostics(self);
        process_impl_windows_sync.reportWindowsCxaThrowDiagnostics(self);
        process_impl_kernel_services.reportWindowsFileFailures(self);
        process_impl_guest_diagnostics.reportWindowsDynamicRefusals(self);
        process_impl_guest_diagnostics.reportFirstFrameChain(self);
        process_impl_guest_diagnostics.reportGuestOutputChain(self);
        process_impl_guest_diagnostics.reportGuestMilestones(self);
        process_impl_guest_diagnostics.reportGuestThreads(self);
        process_impl_guest_diagnostics.reportWindowsUiPipeline(self);
        // Keep the final report's wait graph complete even when the run
        // exits before a normal throughput report is requested.
        process_impl_guest_diagnostics.reportWindowsBlockedDiagnostics(self, self.windows_guest_threads.len);
        process_impl_guest_diagnostics.reportWindowsWaitCost(self);
        process_impl_guest_diagnostics.reportWindowsWaitFindings(self);
        process_impl_guest_diagnostics.reportWindowsUpstreamWaitPriority(self);
        process_impl_kernel_services.reportWindowsScreenValidity(self);
        process_impl_guest_memory.reportWindowsMemoryContract(self);
        process_impl_kernel_services.reportWindowsInputBridge(self);
        process_impl_guest_diagnostics.reportGpuDrawFailures(self);
        process_impl_instruction_decode.reportDecodeCacheMissSites(self);
    }
    if (self.faulted) logExitDiagnostics(self);
}

pub fn eventSite(self: *const ElfState, return_address: u64) __process_terminal_event.Site {
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
    return .{
        .step = process_impl_run_reporting.totalInterpretedSteps(self),
        .rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        .return_address = return_address,
        .thread_slot = if (slot) |index| @intCast(@min(index, __process_std.math.maxInt(u16))) else null,
        .thread_handle = process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
    };
}

pub fn reportGuestUd2(self: *ElfState) void {
    const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
    const rip = regs.rip;
    const slot_plus_one: u8 = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot|
        @intCast(@min(slot + 1, 255))
    else
        0;
    const thread = process_impl_guest_diagnostics.guestThreadLabel(self, slot_plus_one);
    const thread_handle = process_impl_lifecycle.guestContextField(self, "active_guest_thread").*;
    const return_address = if (regs.rsp >= 0x10000) process_impl_guest_memory.read64(self, regs.rsp) else 0;
    const object_words = [_]u64{
        if (regs.rcx != 0) process_impl_guest_memory.read64(self, regs.rcx) else 0,
        if (regs.rcx != 0) process_impl_guest_memory.read64(self, regs.rcx +| 8) else 0,
        if (regs.rcx != 0) process_impl_guest_memory.read64(self, regs.rcx +| 0x10) else 0,
        if (regs.rcx != 0) process_impl_guest_memory.read64(self, regs.rcx +| 0x18) else 0,
    };
    const candidate_vtable = object_words[0];
    // Itanium ABI address points start at the first virtual function:
    // slot 0 is the complete destructor, slot 1 the deleting destructor.
    // The old +0x18 read slot 3 and hid the exact match in Xenia's
    // Win32Handle<Mutant> deleting-destructor UD2.
    const candidate_dtor = if (candidate_vtable != 0) process_impl_guest_memory.read64(self, candidate_vtable +| 8) else 0;
    const stack_words = [_]u64{
        return_address,
        if (regs.rsp >= 0x10000) process_impl_guest_memory.read64(self, regs.rsp +| 8) else 0,
        if (regs.rsp >= 0x10000) process_impl_guest_memory.read64(self, regs.rsp +| 0x10) else 0,
        if (regs.rsp >= 0x10000) process_impl_guest_memory.read64(self, regs.rsp +| 0x18) else 0,
        if (regs.rsp >= 0x10000) process_impl_guest_memory.read64(self, regs.rsp +| 0x20) else 0,
        if (regs.rsp >= 0x10000) process_impl_guest_memory.read64(self, regs.rsp +| 0x28) else 0,
    };

    var rip_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var dtor_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var instruction: [16]u8 = undefined;
    const instruction_bytes = process_impl_instruction_decode.guestInstructionBytes(self, rip, &instruction);
    const rip_description = process_impl_kernel_services.describeGuestAddressOrUnnamed(self, rip, &rip_text);
    const caller_description = if (return_address == 0) "<no return address>" else process_impl_kernel_services.describeGuestAddressOrUnnamed(self, return_address, &caller_text);
    const dtor_description = if (candidate_dtor == 0) "<zero/unreadable>" else process_impl_kernel_services.describeGuestAddressOrUnnamed(self, candidate_dtor, &dtor_text);

    recordTerminalEvent(self, .guest_invalid_instruction, "ud2", return_address, "UD2 at 0x{x} ({s}) on '{s}'; return=0x{x} ({s}); rcx=0x{x} candidate_vtable=0x{x} deleting_dtor=0x{x} ({s}) matches_rip={}", .{
        rip,
        rip_description,
        thread,
        return_address,
        caller_description,
        regs.rcx,
        candidate_vtable,
        candidate_dtor,
        dtor_description,
        candidate_dtor == rip,
    });

    if (comptime @import("builtin").is_test) return;
    __process_log.err("PE64 INVALID OPCODE: op=UD2 rip=0x{x} at={s} thread={s} handle=0x{x} slot_plus_one={d} step={d} last_op={s} last_len={d} bytes={any} regs=[rax=0x{x},rbx=0x{x},rcx=0x{x},rdx=0x{x},rsi=0x{x},rdi=0x{x},rbp=0x{x},rsp=0x{x},r8=0x{x},r9=0x{x},r10=0x{x},r11=0x{x},r12=0x{x},r13=0x{x},r14=0x{x},r15=0x{x}]", .{
        rip,
        rip_description,
        thread,
        thread_handle,
        slot_plus_one,
        process_impl_lifecycle.observedExecutionSteps(self),
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
        instruction_bytes,
        regs.rax,
        regs.rbx,
        regs.rcx,
        regs.rdx,
        regs.rsi,
        regs.rdi,
        regs.rbp,
        regs.rsp,
        regs.r8,
        regs.r9,
        regs.r10,
        regs.r11,
        regs.r12,
        regs.r13,
        regs.r14,
        regs.r15,
    });
    __process_log.err("PE64 INVALID OPCODE CONTEXT: stack_return=0x{x} caller={s} stack_words={any}; rcx_object_candidate=0x{x} object_words={any} vtable_candidate=0x{x} deleting_dtor_candidate=0x{x} deleting_dtor_at={s} deleting_dtor_matches_ud2={}; a match means a virtual deleting-destructor dispatch reached this trap", .{
        return_address,
        caller_description,
        stack_words,
        regs.rcx,
        object_words,
        candidate_vtable,
        candidate_dtor,
        dtor_description,
        candidate_dtor == rip,
    });
}

pub fn recordTerminalEvent(self: *ElfState, kind: __process_terminal_event.Kind, label: []const u8, return_address: u64, comptime format: []const u8, args: anytype) void {
    var detail: [512]u8 = undefined;
    const text = __process_std.fmt.bufPrint(&detail, format, args) catch detail[0..];
    _ = self.terminal_event.record(kind, label, text, eventSite(self, return_address));
}

pub fn noteNotableEvent(self: *ElfState, kind: __process_terminal_event.NotableKind, return_address: u64, comptime format: []const u8, args: anytype) void {
    var text: [240]u8 = undefined;
    const formatted = __process_std.fmt.bufPrint(&text, format, args) catch text[0..];
    self.notable_events.push(kind, eventSite(self, return_address), formatted);
}

pub fn lastNotableEventText(self: *const ElfState, buffer: []u8) []const u8 {
    const count = self.notable_events.count();
    if (count == 0) return "none recorded";
    const event = self.notable_events.chronological(count - 1).?;
    return __process_std.fmt.bufPrint(buffer, "{s} at step {d} ({d} steps earlier): {s}", .{
        @tagName(event.kind),
        event.site.step,
        process_impl_run_reporting.totalInterpretedSteps(self) -| event.site.step,
        event.text(),
    }) catch event.text();
}

pub fn recordWindowsFatalRuntimeCall(self: *ElfState, name: []const u8, return_address: u64) void {
    const kind: __process_terminal_event.Kind = if (__process_std.mem.eql(u8, name, "abort"))
        .guest_abort
    else if (__process_std.mem.eql(u8, name, "terminate") or __process_std.mem.eql(u8, name, "__std_terminate") or __process_std.mem.eql(u8, name, "_purecall"))
        .guest_terminate
    else
        .runtime_invariant;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const caller = if (return_address == 0) "<caller not recorded>" else process_impl_kernel_services.describeGuestAddressOrUnnamed(self, return_address, &caller_text);
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
    const thread = process_impl_guest_diagnostics.guestThreadLabel(self, if (slot) |index| @intCast(@min(index + 1, 255)) else 0);
    var previous_text: [320]u8 = undefined;
    const previous = lastNotableEventText(self, &previous_text);
    recordTerminalEvent(self, kind, name, return_address, "{s} was called from 0x{x} ({s}) on thread '{s}'. The notable event just before it: {s}", .{ name, return_address, caller, thread, previous });
    noteNotableEvent(self, .fatal_runtime_call, return_address, "{s} from 0x{x} ({s})", .{ name, return_address, caller });
}

pub fn guestAddressIsCode(self: *const ElfState, address: u64) bool {
    for (self.windows_executable_ranges[0..self.windows_executable_range_count]) |range| {
        if (range.length != 0 and address >= range.guest_base and address - range.guest_base < range.length) return true;
    }
    if (self.image_high != 0 and address >= self.image_low and address < self.image_high) return true;
    return process_impl_guest_memory.windowsMappedCodeMemoryConst(self, address, 1) != null;
}

pub fn formatGuestBacktrace(self: *const ElfState, rsp: u64, max_frames: usize, buffer: []u8) []const u8 {
    const source = __state_ExitContextSource{ .state = self };
    var words: [512]u64 = undefined;
    var count: usize = 0;
    while (count < words.len) : (count += 1) {
        words[count] = source.stackWord(rsp +| @as(u64, @intCast(count * 8))) orelse break;
    }
    var frames: [8]__process_guest_backtrace.Frame = undefined;
    const found = __process_guest_backtrace.scan(source, rsp, words[0..count], frames[0..@min(max_frames, frames.len)]);
    if (found == 0) return "<no call frames found on the stack>";
    var used: usize = 0;
    for (frames[0..found], 0..) |frame, index| {
        var name: [__process_guest_symbol_text_bytes]u8 = undefined;
        const written = __process_std.fmt.bufPrint(buffer[used..], "{s}0x{x} ({s})", .{
            if (index == 0) "" else " <- ",
            frame.return_address,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, frame.return_address, &name),
        }) catch break;
        used += written.len;
    }
    return buffer[0..used];
}

pub fn reportGuestStoreBuffers(self: *const ElfState) void {
    const totals = self.guest_store_buffers.totals();
    __process_log.info("PE64 TSO STORE BUFFERS: enabled={} execution={s} executor_contexts={d} stores(enqueued/drained/pending_after_exit)={d}/{d}/{d} forwarded_loads={d} forward_scans={d} peak_depth={d}/{d} progress_drains(capacity/retire)={d}/{d}; interpreted stores queue per guest context and forward to that context's own loads, translated code and runtime calls write memory directly, and every tier boundary drains the queue (ROSETTE_TSO_STORE_BUFFERS=0 writes every store directly, for an A/B run)", .{
        self.guest_store_buffers.enabled,
        if (self.parallel_guest_execution) "coordinated" else "cooperative",
        totals.contexts_used,
        totals.enqueued,
        totals.drained,
        totals.pending,
        totals.forwarded_loads,
        totals.forward_scans,
        totals.peak_depth,
        __process_tso_memory.StoreBuffer.capacity,
        totals.capacity_drains,
        totals.retire_drains,
    });
    const ledger = __process_tso_memory.boundary_ledger.snapshot();
    var boundary_text: [512]u8 = undefined;
    const level_is_error = ledger.translated_entry_violations != 0;
    const format = "PE64 TSO BOUNDARIES: drains(flushes/stores) {s} translated_entry_violations={d} (stores={d} first_rip=0x{x} first_boundary={s}); a violation is translated code that started while its executor still held buffered stores - it would have read memory without them - so any value but zero names a missing tier-boundary drain in Rosette";
    const args = .{
        ledger.formatBoundaries(&boundary_text),
        ledger.translated_entry_violations,
        ledger.translated_entry_violation_entries,
        ledger.first_violation_rip,
        if (ledger.first_violation_boundary) |boundary| @tagName(boundary) else "none",
    };
    if (level_is_error) __process_log.err(format, args) else __process_log.info(format, args);
}

pub fn logExitDiagnostics(self: *const ElfState) void {
    const parallel_snapshot = self.parallel_fault_snapshot.read();
    const regs = if (parallel_snapshot) |snapshot|
        snapshot.regs
    else
        self.exit_fault_regs orelse process_impl_lifecycle.guestContextField(self, "regs").*;
    const fault_thread_slot = if (parallel_snapshot) |snapshot|
        snapshot.thread_slot
    else
        self.exit_fault_thread_slot;
    const fault_op = if (parallel_snapshot) |snapshot|
        snapshot.op
    else
        self.exit_fault_op orelse process_impl_lifecycle.guestContextField(self, "last_decoded_op").*;
    const fault_len = if (parallel_snapshot) |snapshot|
        snapshot.len
    else
        self.exit_fault_len orelse process_impl_lifecycle.guestContextField(self, "last_decoded_len").*;
    var detail_buffer: [256]u8 = undefined;
    const detail: []const u8 = if (fault_thread_slot) |slot|
        __process_std.fmt.bufPrint(&detail_buffer, "Rosette stopped while executing guest worker '{s}' (handle=0x{x}); the registers, stack and terminal instruction are that thread's at the fault, not the owner context restored after it.", .{
            process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255))),
            self.windows_guest_threads[slot].handle,
        }) catch "Rosette stopped while executing a guest worker thread."
    else
        "Rosette stopped while executing an x86-64 ELF program.";
    var terminal = __process_exit_diagnostics.TerminalInstruction{
        .address = regs.rip,
        .op = switch (self.termination_reason) {
            .invalid_instruction => "invalid",
            .decode_failed => "decode_failed",
            .invalid_control_flow_target => "invalid_control_flow_target",
            .unimplemented_instruction => @tagName(fault_op),
            else => "terminated",
        },
        .length = fault_len,
    };
    var instruction_bytes: [16]u8 = undefined;
    const fetched = process_impl_instruction_decode.guestInstructionBytes(self, regs.rip, &instruction_bytes);
    terminal.byte_count = @intCast(fetched.len);
    @memcpy(terminal.bytes[0..fetched.len], fetched);

    // Symbolized through the PE symbol table, which `nearestLocalSymbol`
    // (ELF only) cannot see: every stack word in a PE exit report used
    // to print bare. See `diagnostics/exit_context.zig`.
    var context: __process_exit_context.ExitContext = .{};
    context.build(__state_ExitContextSource{ .state = self }, regs.rip, regs.rsp, &self.terminal_event, &self.notable_events);

    if (self.parallel_guest_execution) self.trace_ring_mutex.lock();
    defer if (self.parallel_guest_execution) self.trace_ring_mutex.unlock();
    const trace_count = self.trace_ring.count();
    var trace: [__process_TRACE_BUFFER_LEN]__process_exit_diagnostics.TraceEntry = undefined;
    for (0..trace_count) |index| {
        const entry = self.trace_ring.chronological(index) orelse continue;
        trace[index] = .{
            .rip = entry.rip,
            .op = @tagName(entry.op),
            .len = entry.len,
            .rsp = entry.rsp,
            .rax = entry.rax,
            .rcx = entry.rcx,
            .rdx = entry.rdx,
        };
    }

    __process_exit_diagnostics.logExitReport(.{
        .exit_code = self.exit_code,
        .reason = self.termination_reason,
        .faulted = self.faulted,
        .rip = regs.rip,
        .regs = .{
            .rax = regs.rax,
            .rbx = regs.rbx,
            .rcx = regs.rcx,
            .rdx = regs.rdx,
            .rsi = regs.rsi,
            .rdi = regs.rdi,
            .rbp = regs.rbp,
            .rsp = regs.rsp,
            .r8 = regs.r8,
            .r9 = regs.r9,
            .r10 = regs.r10,
            .r11 = regs.r11,
            .r12 = regs.r12,
            .r13 = regs.r13,
            .r14 = regs.r14,
            .r15 = regs.r15,
        },
        .last_instructions = trace[0..trace_count],
        .terminal_instruction = terminal,
        .stack_entries = context.stackEntries(),
        .terminal_symbol = process_impl_kernel_services.nearestLocalSymbol(self, regs.rip),
        .terminal_description = context.terminal_description,
        .runtime_context = .{ .phase = "elf_execution", .steps = process_impl_lifecycle.observedExecutionSteps(self) },
        .detail = detail,
        .terminal_event = context.terminal,
        .preceding_events = context.precedingEvents(),
        .preceding_events_total = context.preceding_total,
        .guest_backtrace = context.backtrace(),
        .recent_log_lines = context.recentLines(),
        .recent_log_total = context.recent_total,
    });
}

pub fn logRegs(self: *ElfState) void {
    __process_log.info("  regs: rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rsp=0x{x} rbp=0x{x} rip=0x{x}", .{
        process_impl_lifecycle.guestContextField(self, "regs").*.rax, process_impl_lifecycle.guestContextField(self, "regs").*.rbx, process_impl_lifecycle.guestContextField(self, "regs").*.rcx, process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
        process_impl_lifecycle.guestContextField(self, "regs").*.rsi, process_impl_lifecycle.guestContextField(self, "regs").*.rdi, process_impl_lifecycle.guestContextField(self, "regs").*.rsp, process_impl_lifecycle.guestContextField(self, "regs").*.rbp,
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
    });
    __process_log.info("  flags: cf={d} zf={d} sf={d} of={d}", .{
        @as(u1, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rflags >> 0)),
        @as(u1, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rflags >> 6)),
        @as(u1, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rflags >> 7)),
        @as(u1, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rflags >> 11)),
    });
}

pub fn regVal(self: *const ElfState, id: __process_RegId, size: __process_Size) u64 {
    return __process_x64_decoder.regVal(&process_impl_lifecycle.guestContextField(self, "regs").*, id, size);
}

pub fn setReg(self: *ElfState, id: __process_RegId, size: __process_Size, val: u64) void {
    __process_x64_decoder.setReg(&process_impl_lifecycle.guestContextField(self, "regs").*, id, size, val);
}

pub fn decodedRegVal(self: *const ElfState, id: __process_RegId, high8: bool, size: __process_Size) u64 {
    return __process_x64_decoder.registerOperandValue(&process_impl_lifecycle.guestContextField(self, "regs").*, .{ .id = id, .high8 = high8 }, size);
}

pub fn setDecodedReg(self: *ElfState, id: __process_RegId, high8: bool, size: __process_Size, val: u64) void {
    __process_x64_decoder.setRegisterOperand(&process_impl_lifecycle.guestContextField(self, "regs").*, .{ .id = id, .high8 = high8 }, size, val);
}

pub fn noteGuestNullPageAccess(self: *ElfState, address: u64, size: __process_Size, is_write: bool) void {
    self.guest_null_page_accesses +|= 1;
    const occurrence = self.guest_null_page_accesses;
    if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) {
        if (comptime !@import("builtin").is_test) reportGuestNullPageAccess(self, address, size, is_write, occurrence);
        var at_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        noteNotableEvent(self, .null_page_access, 0, "{s} of 0x{x} ({s}) occurrence={d} at {s}", .{
            if (is_write) "write" else "read",
            address,
            @tagName(size),
            occurrence,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &at_text),
        });
    }
    if (!self.guest_null_page_fatal) return;
    if (occurrence == 1) self.windows_fatal_point_events +|= 1;
    process_impl_guest_diagnostics.terminateForWindowsFatalPointWith(self, "guest-null-page-access", .memory_access_violation, 139);
}

pub fn reportGuestNullPageAccess(self: *const ElfState, address: u64, size: __process_Size, is_write: bool, occurrence: u64) void {
    var at_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const slot_plus_one: u8 = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| @intCast(@min(slot + 1, 255)) else 0;
    var instruction_bytes: [16]u8 = undefined;
    const bytes: []const u8 = if (copyFromGuest(self, &instruction_bytes, process_impl_lifecycle.guestContextField(self, "regs").*.rip))
        instruction_bytes[0..]
    else
        &[_]u8{};
    __process_log.err("PE64 NULL-PAGE ACCESS: kind={s} helper_address=0x{x} size={s} occurrence={d} step={d} rip=0x{x} at={s} last_op={s} thread={s} saved_regs_may_be_stale=[rax=0x{x},rbx=0x{x},rcx=0x{x},rdx=0x{x},rsi=0x{x},rdi=0x{x},rbp=0x{x},rsp=0x{x},r8=0x{x},r9=0x{x},r10=0x{x},r11=0x{x},r12=0x{x},r13=0x{x},r14=0x{x},r15=0x{x}] bytes={any}; helper_address is the observed memory effective address, and the saved register file is corroborating evidence only", .{
        if (is_write) "write" else "read",
        address,
        @tagName(size),
        occurrence,
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &at_text),
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        process_impl_guest_diagnostics.guestThreadLabel(self, slot_plus_one),
        process_impl_lifecycle.guestContextField(self, "regs").*.rax,
        process_impl_lifecycle.guestContextField(self, "regs").*.rbx,
        process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
        process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
        process_impl_lifecycle.guestContextField(self, "regs").*.rsi,
        process_impl_lifecycle.guestContextField(self, "regs").*.rdi,
        process_impl_lifecycle.guestContextField(self, "regs").*.rbp,
        process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        process_impl_lifecycle.guestContextField(self, "regs").*.r8,
        process_impl_lifecycle.guestContextField(self, "regs").*.r9,
        process_impl_lifecycle.guestContextField(self, "regs").*.r10,
        process_impl_lifecycle.guestContextField(self, "regs").*.r11,
        process_impl_lifecycle.guestContextField(self, "regs").*.r12,
        process_impl_lifecycle.guestContextField(self, "regs").*.r13,
        process_impl_lifecycle.guestContextField(self, "regs").*.r14,
        process_impl_lifecycle.guestContextField(self, "regs").*.r15,
        bytes,
    });
    reportGuestNullPageAddressCheck(self, address);
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse return;
    const thread = &self.windows_guest_threads[slot];
    const creation_age_steps = process_impl_lifecycle.observedExecutionSteps(self) -| thread.created_step;
    var start_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var creator_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var creator_now_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const creator_now: u64 = if (thread.creator_slot == 0)
        thread.creator_rip
    else
        process_impl_guest_diagnostics.windowsGuestThreadRip(self, thread.creator_slot - 1);
    const kernel = self.guest_kernel_calls.slotAt(thread.last_kernel_slot);
    __process_log.err("PE64 NULL-PAGE ACCESS:   thread start={s} steps={d} created_step={d} creation_age_steps={d} creator={s} on {s}, which is now at {s}; last_kernel_call={s}!{s}; {s}", .{
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, thread.start_routine, &start_text),
        process_impl_lifecycle.windowsGuestThreadSteps(self, thread),
        thread.created_step,
        creation_age_steps,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, thread.creator_rip, &creator_text),
        process_impl_guest_diagnostics.guestThreadLabel(self, thread.creator_slot),
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, creator_now, &creator_now_text),
        if (kernel) |entry| entry.module.moduleName() else "<none>",
        if (kernel) |entry| entry.export_name else "<none>",
        if (creation_age_steps <= 4096) "fault is close to thread creation; publication ordering remains a candidate" else "thread creation was far earlier and does not establish a creation/publication race",
    });
    reportXeniaEventCall(self, thread);
}

pub fn reportXeniaEventCall(self: *const ElfState, thread: *const __process_WindowsGuestThread) void {
    const call = thread.last_xenia_event_call;
    if (call.operation == .none) return;
    const age = process_impl_lifecycle.observedExecutionSteps(self) -| call.step;
    if (call.header) |header| {
        __process_log.err("PE64 XENIA EVENT PROVENANCE: operation={s} age_steps={d} PPCContext=0x{x} membase=0x{x} guest_event=0x{x} host_event=0x{x} args=0x{x}/0x{x} header_type=0x{x} event_type_valid={} signal_state={d} flink=0x{x} blink=0x{x} has_xenia_signature={} signature_expected=0x{x}; Xenia's GetNativeObject treats flink==signature as initialized and blink as the stored object handle", .{
            @tagName(call.operation),
            age,
            call.context,
            call.membase,
            call.guest_event,
            call.host_event,
            call.argument2,
            call.argument3,
            header.object_type,
            header.isEventType(),
            header.signal_state,
            header.flink,
            header.blink,
            header.hasXeniaObjectSignature(),
            __process_xenia_event_audit.xenia_object_signature,
        });
    } else {
        __process_log.err("PE64 XENIA EVENT PROVENANCE: operation={s} age_steps={d} PPCContext=0x{x} membase=0x{x} guest_event=0x{x} host_event=0x{x} args=0x{x}/0x{x} header=unreadable; this is the last event export observed on the faulting executor", .{
            @tagName(call.operation),
            age,
            call.context,
            call.membase,
            call.guest_event,
            call.host_event,
            call.argument2,
            call.argument3,
        });
    }
}

pub fn reportGuestNullPageAddressCheck(self: *const ElfState, supplied_address: u64) void {
    const instruction_rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*;
    var instruction_bytes: [16]u8 = undefined;
    if (!copyFromGuest(self, &instruction_bytes, instruction_rip)) return;
    const bytes = instruction_bytes[0..];
    const decoded = __process_decodeInsn(bytes);
    const supported = switch (decoded.op) {
        .movzx_reg32_mem8, .mov_reg64_mem64, .call_mem64 => true,
        else => false,
    };
    if (!supported or decoded.is_reg_form or decoded.len == 0) return;

    const address_size: __process_Size = if (decoded.has_0x67) .bits32 else .bits64;
    const register_file_ea = __process_x64_decoder.resolveMemoryAddress(&process_impl_lifecycle.guestContextField(self, "regs").*, .{
        .displacement = decoded.addr,
        .has_index = decoded.sib_has_index,
        .index_reg = decoded.sib_index_reg,
        .scale = decoded.sib_scale,
        .has_base = decoded.sib_has_base,
        .base_reg = decoded.sib_base_reg,
        .rip_relative = decoded.rip_relative,
        .segment = decoded.segment,
    }, instruction_rip +% decoded.len, address_size, .long64, true);

    __process_log.err("PE64 NULL-PAGE ADDRESS CHECK: helper_address=0x{x} instruction_rip=0x{x} op={s} bytes={any} len={d} base={s}/present={} index={s}/present={} scale={d} displacement=0x{x} saved_register_ea=0x{x} matches_helper={}; a mismatch means translated registers were newer than the saved register file", .{
        supplied_address,
        instruction_rip,
        @tagName(decoded.op),
        bytes[0..decoded.len],
        decoded.len,
        @tagName(decoded.sib_base_reg),
        decoded.sib_has_base,
        @tagName(decoded.sib_index_reg),
        decoded.sib_has_index,
        decoded.sib_scale,
        decoded.addr,
        register_file_ea,
        supplied_address == register_file_ea,
    });
    if (supplied_address < __process_WINDOWS_NULL_PAGE_LIMIT) {
        reportNullPagePrecedingLoad(self, instruction_rip, decoded, supplied_address);
    }
}

pub fn reportNullPagePrecedingLoad(self: *const ElfState, instruction_rip: u64, decoded: __process_DecodedInsn, helper_address: u64) void {
    if (!decoded.sib_has_base or decoded.rip_relative) return;
    var distance: usize = 1;
    while (distance <= 15) : (distance += 1) {
        const previous_rip = instruction_rip -| distance;
        var previous_bytes: [16]u8 = undefined;
        if (!copyFromGuest(self, &previous_bytes, previous_rip)) continue;
        const previous = __process_decodeInsn(&previous_bytes);
        if (@as(usize, previous.len) != distance or previous.op != .mov_reg64_mem64 or previous.is_reg_form or previous.dst_reg != decoded.sib_base_reg) continue;

        const address_size: __process_Size = if (previous.has_0x67) .bits32 else .bits64;
        const source_address = __process_x64_decoder.resolveMemoryAddress(&process_impl_lifecycle.guestContextField(self, "regs").*, .{
            .displacement = previous.addr,
            .has_index = previous.sib_has_index,
            .index_reg = previous.sib_index_reg,
            .scale = previous.sib_scale,
            .has_base = previous.sib_has_base,
            .base_reg = previous.sib_base_reg,
            .rip_relative = previous.rip_relative,
            .segment = previous.segment,
        }, previous_rip +% previous.len, address_size, .long64, true);
        const source = guestMemorySourceConst(self, source_address, 8) orelse continue;
        const loaded_value = process_impl_guest_memory.loadGuestScalar(self, u64, source);
        if (loaded_value >= __process_WINDOWS_NULL_PAGE_LIMIT) continue;

        __process_log.err("PE64 NULL-PAGE PRIOR LOAD: fault_rip=0x{x} fault_op={s} helper_address=0x{x} previous_rip=0x{x} previous_op={s} previous_bytes={any} destination={s} source_ea=0x{x} replayed_value=0x{x}; the preceding memory load is the first observed source of this null-page pointer candidate", .{
            instruction_rip,
            @tagName(decoded.op),
            helper_address,
            previous_rip,
            @tagName(previous.op),
            previous_bytes[0..@as(usize, previous.len)],
            @tagName(previous.dst_reg),
            source_address,
            loaded_value,
        });
        return;
    }
}

pub fn readMemVal(self: *ElfState, addr: u64, size: __process_Size) u64 {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| {
        // The pass must not raise what a real access would: a fault is
        // a guest-visible event the discarded pass cannot take back.
        const width: u64 = bitWidth(size) / 8;
        if (addr < __process_WINDOWS_NULL_PAGE_LIMIT and self.windows_runtime_enabled and process_impl_guest_memory.addrToOffset(self, addr) == null) {
            journal.fail(.null_page, addr);
            return 0;
        }
        if (self.guest_page_protection.isActive() and self.guest_page_protection.faults(addr, @intCast(width), false)) {
            journal.fail(.protected_page, addr);
            return 0;
        }
    }
    if (addr < __process_WINDOWS_NULL_PAGE_LIMIT and self.windows_runtime_enabled and process_impl_guest_memory.addrToOffset(self, addr) == null) {
        noteGuestNullPageAccess(self, addr, size, false);
        return 0;
    }
    const value: u64 = switch (size) {
        .bits8 => process_impl_guest_memory.read8(self, addr),
        .bits16 => process_impl_guest_memory.read16(self, addr),
        .bits32 => process_impl_guest_memory.read32(self, addr),
        .bits64 => process_impl_guest_memory.read64(self, addr),
    };
    // The scalar read helpers use the same acquire or unaligned-barrier
    // policy as translated memory accesses.
    // One byte test when nothing is protected. A read still returns the
    // backing bytes: if no handler takes the fault the instruction has
    // already done exactly what Rosette always did, and if one does, it
    // overwrites the destination register from the CONTEXT it returns.
    if (self.guest_page_protection.isActive()) _ = process_impl_guest_memory.noteGuestOperandAccess(self, addr, size, false, value);
    if (self.spin_capture_threads.load(.monotonic) != 0) process_impl_lifecycle.noteSpinCaptureRead(self, addr, size, value);
    return value;
}

pub fn atomicMemoryOperand(self: *ElfState, address: u64, size: __process_Size) ?[]u8 {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| {
        journal.fail(.unsupported, address);
        return null;
    }
    const length: u64 = bitWidth(size) / 8;
    if (self.guest_page_protection.isActive() and
        self.guest_page_protection.faults(address, @intCast(length), true)) return null;
    if (process_impl_guest_memory.addrToOffset(self, address)) |offset| {
        const begin: usize = @intCast(offset);
        const count: usize = @intCast(length);
        if (begin > self.mem.len or count > self.mem.len - begin) return null;
        return self.mem[begin .. begin + count];
    }
    return process_impl_guest_memory.windowsMappedMemory(self, address, length);
}

pub fn beginSerializedAtomicFallback(self: *ElfState) ?__process_GuestExecutionGate.MutationGuard {
    if (!self.parallel_guest_execution) return null;
    const guard = self.guest_execution_gate.enterMutation();
    process_impl_block_jit.flushAllGuestStoreBuffers(self, .fence);
    return guard;
}

pub fn fallbackAtomicUpdate(
    self: *ElfState,
    address: u64,
    size: __process_Size,
    operation: __process_tso_memory.UpdateOp,
    operand: u64,
    carry_in: bool,
) __process_tso_memory.UpdateResult {
    const mask = maskForSize(size);
    const previous = readMemVal(self, address, size) & mask;
    const rhs = operand & mask;
    const carry: u64 = @intFromBool(carry_in);
    const value = (switch (operation) {
        .add => previous +% rhs,
        .sub => previous -% rhs,
        .neg => 0 -% previous,
        .adc => previous +% rhs +% carry,
        .sbb => previous -% rhs -% carry,
        .bit_and => previous & rhs,
        .bit_or, .bit_set => previous | rhs,
        .bit_xor, .bit_complement => previous ^ rhs,
        .bit_reset => previous & ~rhs,
    }) & mask;
    writeMemVal(self, address, size, value);
    __process_tso_memory.flushActiveStoreBufferFor(.fence);
    return .{ .previous = previous, .value = value };
}

pub fn noteAtomicMemoryWrite(self: *ElfState, address: u64, size: __process_Size, value: u64) void {
    const width: u8 = @intCast(bitWidth(size) / 8);
    process_impl_guest_memory.traceGuestWrite(self, address, width, value);
    process_impl_guest_memory.traceWindowsMappedWrite(self, address, width, value);
    if (process_impl_guest_memory.addrToOffset(self, address) != null) {
        process_impl_guest_memory.bumpWindowsImageCodeGeneration(self, address, width);
    } else {
        process_impl_guest_memory.bumpWindowsMappedCodeGeneration(self, address, width);
    }
}

pub fn noteAtomicMemoryWrite128(self: *ElfState, address: u64, value_low: u64) void {
    process_impl_guest_memory.traceGuestWrite(self, address, 16, value_low);
    process_impl_guest_memory.traceWindowsMappedWrite(self, address, 16, value_low);
    if (process_impl_guest_memory.addrToOffset(self, address) != null) {
        process_impl_guest_memory.bumpWindowsImageCodeGeneration(self, address, 16);
    } else {
        process_impl_guest_memory.bumpWindowsMappedCodeGeneration(self, address, 16);
    }
}

pub fn atomicMemoryUpdate(
    self: *ElfState,
    address: u64,
    size: __process_Size,
    operation: __process_tso_memory.UpdateOp,
    operand: u64,
    carry_in: bool,
) ?__process_tso_memory.UpdateResult {
    const bytes = atomicMemoryOperand(self, address, size) orelse {
        var fallback_guard = beginSerializedAtomicFallback(self);
        defer if (fallback_guard) |*guard| guard.unlock();
        if (!self.parallel_guest_execution) return null;
        return fallbackAtomicUpdate(self, address, size, operation, operand, carry_in);
    };
    const result: __process_tso_memory.UpdateResult = switch (size) {
        .bits8 => __process_tso_memory.updateAny(u8, bytes, operation, @truncate(operand), carry_in) orelse return null,
        .bits16 => __process_tso_memory.updateAny(u16, bytes, operation, @truncate(operand), carry_in) orelse return null,
        .bits32 => __process_tso_memory.updateAny(u32, bytes, operation, @truncate(operand), carry_in) orelse return null,
        .bits64 => __process_tso_memory.updateAny(u64, bytes, operation, operand, carry_in) orelse return null,
    };
    noteAtomicMemoryWrite(self, address, size, result.value);
    return result;
}

pub fn atomicMemoryExchange(self: *ElfState, address: u64, size: __process_Size, value: u64) ?u64 {
    const bytes = atomicMemoryOperand(self, address, size) orelse {
        var fallback_guard = beginSerializedAtomicFallback(self);
        defer if (fallback_guard) |*guard| guard.unlock();
        if (!self.parallel_guest_execution) return null;
        const previous = readMemVal(self, address, size);
        writeMemVal(self, address, size, value);
        __process_tso_memory.flushActiveStoreBufferFor(.fence);
        return previous;
    };
    const previous: u64 = switch (size) {
        .bits8 => __process_tso_memory.exchangeAny(u8, bytes, @truncate(value)) orelse return null,
        .bits16 => __process_tso_memory.exchangeAny(u16, bytes, @truncate(value)) orelse return null,
        .bits32 => __process_tso_memory.exchangeAny(u32, bytes, @truncate(value)) orelse return null,
        .bits64 => __process_tso_memory.exchangeAny(u64, bytes, value) orelse return null,
    };
    noteAtomicMemoryWrite(self, address, size, value & maskForSize(size));
    return previous;
}

pub fn atomicMemoryCompareExchange(
    self: *ElfState,
    address: u64,
    size: __process_Size,
    expected: u64,
    desired: u64,
) ?__process_tso_memory.CompareExchangeResult {
    const bytes = atomicMemoryOperand(self, address, size) orelse {
        var fallback_guard = beginSerializedAtomicFallback(self);
        defer if (fallback_guard) |*guard| guard.unlock();
        if (!self.parallel_guest_execution) return null;
        const previous = readMemVal(self, address, size) & maskForSize(size);
        const exchanged = previous == (expected & maskForSize(size));
        if (exchanged) writeMemVal(self, address, size, desired);
        __process_tso_memory.flushActiveStoreBufferFor(.fence);
        return .{ .previous = previous, .exchanged = exchanged };
    };
    const result: __process_tso_memory.CompareExchangeResult = switch (size) {
        .bits8 => __process_tso_memory.compareExchangeAny(u8, bytes, @truncate(expected), @truncate(desired)) orelse return null,
        .bits16 => __process_tso_memory.compareExchangeAny(u16, bytes, @truncate(expected), @truncate(desired)) orelse return null,
        .bits32 => __process_tso_memory.compareExchangeAny(u32, bytes, @truncate(expected), @truncate(desired)) orelse return null,
        .bits64 => __process_tso_memory.compareExchangeAny(u64, bytes, expected, desired) orelse return null,
    };
    if (result.exchanged) noteAtomicMemoryWrite(self, address, size, desired & maskForSize(size));
    return result;
}

pub fn atomicMemoryCompareExchange128(
    self: *ElfState,
    address: u64,
    expected: u128,
    desired: u128,
) ?__process_tso_memory.CompareExchange128Result {
    const bytes: ?[]u8 = if (self.guest_page_protection.isActive() and self.guest_page_protection.faults(address, 16, true)) null else if (process_impl_guest_memory.addrToOffset(self, address)) |offset| blk: {
        const begin: usize = @intCast(offset);
        if (begin > self.mem.len or 16 > self.mem.len - begin) break :blk null;
        break :blk self.mem[begin .. begin + 16];
    } else process_impl_guest_memory.windowsMappedMemory(self, address, 16);
    const operand = bytes orelse {
        var fallback_guard = beginSerializedAtomicFallback(self);
        defer if (fallback_guard) |*guard| guard.unlock();
        if (!self.parallel_guest_execution) return null;
        const previous_bytes = readMem128(self, address);
        const previous_low = __process_std.mem.readInt(u64, previous_bytes[0..8], .little);
        const previous_high = __process_std.mem.readInt(u64, previous_bytes[8..16], .little);
        const previous = (@as(u128, previous_high) << 64) | previous_low;
        const exchanged = previous == expected;
        if (exchanged) {
            var desired_bytes: [16]u8 = undefined;
            __process_std.mem.writeInt(u64, desired_bytes[0..8], @truncate(desired), .little);
            __process_std.mem.writeInt(u64, desired_bytes[8..16], @truncate(desired >> 64), .little);
            writeMem128(self, address, desired_bytes);
        }
        __process_tso_memory.flushActiveStoreBufferFor(.fence);
        return .{ .previous = previous, .exchanged = exchanged };
    };
    const result = __process_tso_memory.compareExchange128(operand, expected, desired) orelse {
        var fallback_guard = beginSerializedAtomicFallback(self);
        defer if (fallback_guard) |*guard| guard.unlock();
        if (!self.parallel_guest_execution) return null;
        const previous_bytes = readMem128(self, address);
        const previous_low = __process_std.mem.readInt(u64, previous_bytes[0..8], .little);
        const previous_high = __process_std.mem.readInt(u64, previous_bytes[8..16], .little);
        const previous = (@as(u128, previous_high) << 64) | previous_low;
        const exchanged = previous == expected;
        if (exchanged) {
            var desired_bytes: [16]u8 = undefined;
            __process_std.mem.writeInt(u64, desired_bytes[0..8], @truncate(desired), .little);
            __process_std.mem.writeInt(u64, desired_bytes[8..16], @truncate(desired >> 64), .little);
            writeMem128(self, address, desired_bytes);
        }
        __process_tso_memory.flushActiveStoreBufferFor(.fence);
        return .{ .previous = previous, .exchanged = exchanged };
    };
    if (result.exchanged) noteAtomicMemoryWrite128(self, address, @truncate(desired));
    return result;
}

pub fn atomicMemoryFetchAdd(self: *ElfState, address: u64, size: __process_Size, value: u64) ?u64 {
    const bytes = atomicMemoryOperand(self, address, size) orelse {
        var fallback_guard = beginSerializedAtomicFallback(self);
        defer if (fallback_guard) |*guard| guard.unlock();
        if (!self.parallel_guest_execution) return null;
        const previous = readMemVal(self, address, size) & maskForSize(size);
        writeMemVal(self, address, size, previous +% value);
        __process_tso_memory.flushActiveStoreBufferFor(.fence);
        return previous;
    };
    const previous: u64 = switch (size) {
        .bits8 => __process_tso_memory.fetchAddAny(u8, bytes, @truncate(value)) orelse return null,
        .bits16 => __process_tso_memory.fetchAddAny(u16, bytes, @truncate(value)) orelse return null,
        .bits32 => __process_tso_memory.fetchAddAny(u32, bytes, @truncate(value)) orelse return null,
        .bits64 => __process_tso_memory.fetchAddAny(u64, bytes, value) orelse return null,
    };
    noteAtomicMemoryWrite(self, address, size, (previous +% value) & maskForSize(size));
    return previous;
}

pub fn invalidAtomicAlignment(self: *ElfState, address: u64, alignment: u8, op: __process_Op) void {
    process_impl_lifecycle.markFaulted(self);
    process_impl_lifecycle.markTerminated(self);
    self.exit_code = 127;
    self.termination_reason = .memory_access_violation;
    __process_log.err("PE64 atomic operand alignment fault: rip=0x{x} op={s} address=0x{x} required_alignment={d}", .{
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        @tagName(op),
        address,
        alignment,
    });
}

pub fn executeCmpxchg8b(self: *ElfState, d: __process_DecodedInsn) void {
    // CMPXCHG8B permits an unaligned m64 operand unless architectural
    // alignment checking is enabled (which this PE execution mode does
    // not model). The locked helper uses the byte-safe striped route for
    // such an address; CMPXCHG16B retains its architectural 16-byte check.
    const expected = ((process_impl_lifecycle.guestContextField(self, "regs").*.rdx & 0xFFFF_FFFF) << 32) | (process_impl_lifecycle.guestContextField(self, "regs").*.rax & 0xFFFF_FFFF);
    const desired = ((process_impl_lifecycle.guestContextField(self, "regs").*.rcx & 0xFFFF_FFFF) << 32) | (process_impl_lifecycle.guestContextField(self, "regs").*.rbx & 0xFFFF_FFFF);
    if (d.lock) {
        if (atomicMemoryCompareExchange(self, d.addr, .bits64, expected, desired)) |result| {
            setFlag(self, __process_RFL_ZF, result.exchanged);
            if (!result.exchanged) {
                process_impl_lifecycle.guestContextField(self, "regs").*.rax = result.previous & 0xFFFF_FFFF;
                process_impl_lifecycle.guestContextField(self, "regs").*.rdx = result.previous >> 32;
            }
            return;
        }
    }
    const previous = readMemVal(self, d.addr, .bits64);
    if (previous == expected) {
        writeMemVal(self, d.addr, .bits64, desired);
        setFlag(self, __process_RFL_ZF, true);
    } else {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = previous & 0xFFFF_FFFF;
        process_impl_lifecycle.guestContextField(self, "regs").*.rdx = previous >> 32;
        setFlag(self, __process_RFL_ZF, false);
    }
}

pub fn executeCmpxchg16b(self: *ElfState, d: __process_DecodedInsn) void {
    if (d.addr & 15 != 0) {
        invalidAtomicAlignment(self, d.addr, 16, d.op);
        return;
    }
    const expected: u128 = (@as(u128, process_impl_lifecycle.guestContextField(self, "regs").*.rdx) << 64) | process_impl_lifecycle.guestContextField(self, "regs").*.rax;
    const desired: u128 = (@as(u128, process_impl_lifecycle.guestContextField(self, "regs").*.rcx) << 64) | process_impl_lifecycle.guestContextField(self, "regs").*.rbx;
    if (d.lock) {
        if (atomicMemoryCompareExchange128(self, d.addr, expected, desired)) |result| {
            setFlag(self, __process_RFL_ZF, result.exchanged);
            if (!result.exchanged) {
                process_impl_lifecycle.guestContextField(self, "regs").*.rax = @truncate(result.previous);
                process_impl_lifecycle.guestContextField(self, "regs").*.rdx = @truncate(result.previous >> 64);
            }
            return;
        }
    }
    const previous_bytes = readMem128(self, d.addr);
    const previous_low = __process_std.mem.readInt(u64, previous_bytes[0..8], .little);
    const previous_high = __process_std.mem.readInt(u64, previous_bytes[8..16], .little);
    if (previous_low == process_impl_lifecycle.guestContextField(self, "regs").*.rax and previous_high == process_impl_lifecycle.guestContextField(self, "regs").*.rdx) {
        var desired_bytes: [16]u8 = undefined;
        __process_std.mem.writeInt(u64, desired_bytes[0..8], process_impl_lifecycle.guestContextField(self, "regs").*.rbx, .little);
        __process_std.mem.writeInt(u64, desired_bytes[8..16], process_impl_lifecycle.guestContextField(self, "regs").*.rcx, .little);
        writeMem128(self, d.addr, desired_bytes);
        setFlag(self, __process_RFL_ZF, true);
    } else {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = previous_low;
        process_impl_lifecycle.guestContextField(self, "regs").*.rdx = previous_high;
        setFlag(self, __process_RFL_ZF, false);
    }
}

pub fn executeAtomicIncDec(self: *ElfState, d: __process_DecodedInsn, is_inc: bool) bool {
    if (!d.lock) return false;
    const op: __process_tso_memory.UpdateOp = if (is_inc) .add else .sub;
    if (atomicMemoryUpdate(self, d.addr, d.size, op, 1, false)) |result| {
        setFlagsIncDec(self, result.previous, result.value, d.size, is_inc);
        return true;
    }
    return false;
}

pub fn executeAtomicNeg(self: *ElfState, d: __process_DecodedInsn) bool {
    if (!d.lock) return false;
    if (atomicMemoryUpdate(self, d.addr, d.size, .neg, 0, false)) |result| {
        setFlagsSub(self, 0, result.previous, result.value, d.size);
        return true;
    }
    return false;
}

pub fn executeAtomicNot(self: *ElfState, d: __process_DecodedInsn) bool {
    if (!d.lock) return false;
    _ = atomicMemoryUpdate(self, d.addr, d.size, .bit_xor, maskForSize(d.size), false) orelse return false;
    return true;
}

pub fn writeMemVal(self: *ElfState, addr: u64, size: __process_Size, val: u64) void {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| {
        const width: u64 = bitWidth(size) / 8;
        if (addr < __process_WINDOWS_NULL_PAGE_LIMIT and self.windows_runtime_enabled and process_impl_guest_memory.addrToOffset(self, addr) == null) return journal.fail(.null_page, addr);
        if (self.guest_page_protection.isActive() and self.guest_page_protection.faults(addr, @intCast(width), true)) return journal.fail(.protected_page, addr);
        var bytes: [8]u8 = undefined;
        __process_std.mem.writeInt(u64, &bytes, val, .little);
        return journal.store(addr, bytes[0..@intCast(width)]);
    }
    if (addr < __process_WINDOWS_NULL_PAGE_LIMIT and self.windows_runtime_enabled and process_impl_guest_memory.addrToOffset(self, addr) == null) {
        noteGuestNullPageAccess(self, addr, size, true);
        return;
    }
    // A protected store is withheld until the fault is resolved: a
    // handler for a register page wants the value delivered to a device,
    // not left in plain memory, and one that declines gets it replayed.
    if (self.guest_page_protection.isActive() and process_impl_guest_memory.noteGuestOperandAccess(self, addr, size, true, val)) return;
    // The scalar write helpers use the same release or unaligned-barrier
    // policy as translated memory accesses.
    switch (size) {
        .bits8 => process_impl_guest_memory.write8(self, addr, @intCast(val & 0xFF)),
        .bits16 => process_impl_guest_memory.write16(self, addr, @intCast(val & 0xFFFF)),
        .bits32 => process_impl_guest_memory.write32(self, addr, @intCast(val & 0xFFFFFFFF)),
        .bits64 => process_impl_guest_memory.write64(self, addr, val),
    }
}

pub fn writeExtendedInt80(destination: []u8, value: i64) void {
    __process_std.debug.assert(destination.len >= 10);
    @memset(destination[0..10], 0);
    if (value == 0) return;

    const negative = value < 0;
    const raw: u64 = @bitCast(value);
    const magnitude = if (negative) (~raw +% 1) else raw;
    const leading: u6 = @intCast(@clz(magnitude));
    const msb_index: u6 = 63 - leading;
    const significand = magnitude << (63 - msb_index);
    const exponent: u16 = 16383 + @as(u16, msb_index);
    const sign_exponent: u16 = (if (negative) @as(u16, 0x8000) else 0) | exponent;
    __process_std.mem.writeInt(u64, destination[0..8], significand, .little);
    __process_std.mem.writeInt(u16, destination[8..10], sign_exponent, .little);
}

pub fn writeExtendedFloat80(destination: []u8, value: f64) void {
    __process_std.debug.assert(destination.len >= 10);
    @memset(destination[0..10], 0);
    const bits: u64 = @bitCast(value);
    const sign: u16 = if ((bits >> 63) != 0) 0x8000 else 0;
    const fraction = bits & 0x000F_FFFF_FFFF_FFFF;
    const exponent: u16 = @truncate((bits >> 52) & 0x7FF);
    if (exponent == 0 and fraction == 0) return;
    if (exponent == 0x7FF) {
        const significand: u64 = if (fraction == 0)
            0x8000_0000_0000_0000
        else
            0xC000_0000_0000_0000;
        __process_std.mem.writeInt(u64, destination[0..8], significand, .little);
        __process_std.mem.writeInt(u16, destination[8..10], sign | 0x7FFF, .little);
        return;
    }

    var significand: u64 = 0;
    var unbiased: i32 = 0;
    if (exponent == 0) {
        const shift: u6 = @intCast(@clz(fraction));
        significand = fraction << shift;
        unbiased = -1011 - @as(i32, shift);
    } else {
        significand = (fraction | (@as(u64, 1) << 52)) << 11;
        unbiased = @as(i32, exponent) - 1023;
    }
    __process_std.mem.writeInt(u64, destination[0..8], significand, .little);
    __process_std.mem.writeInt(u16, destination[8..10], sign | @as(u16, @intCast(unbiased + 16383)), .little);
}

pub fn readExtendedFloat80(source: []const u8) f64 {
    __process_std.debug.assert(source.len >= 10);
    const significand = __process_std.mem.readInt(u64, source[0..8], .little);
    const sign_exponent = __process_std.mem.readInt(u16, source[8..10], .little);
    const negative = (sign_exponent & 0x8000) != 0;
    const exponent = sign_exponent & 0x7FFF;
    const sign_bit: u64 = if (negative) @as(u64, 1) << 63 else 0;

    if (exponent == 0x7FFF) {
        const special_bits = if ((significand & 0x7FFF_FFFF_FFFF_FFFF) == 0)
            sign_bit | 0x7FF0_0000_0000_0000
        else
            sign_bit | 0x7FF8_0000_0000_0000;
        return @bitCast(special_bits);
    }
    if (significand == 0) return @bitCast(sign_bit);

    const unbiased: i32 = if (exponent == 0) -16382 else @as(i32, exponent) - 16383;
    if (unbiased > 1023) return @bitCast(sign_bit | 0x7FF0_0000_0000_0000);
    if (unbiased >= -1022) {
        const binary64_exponent: u64 = @intCast(unbiased + 1023);
        const fraction = (significand >> 11) & 0x000F_FFFF_FFFF_FFFF;
        return @bitCast(sign_bit | (binary64_exponent << 52) | fraction);
    }
    if (unbiased < -1074) return @bitCast(sign_bit);
    const subnormal_shift: u6 = @intCast(-1011 - unbiased);
    const fraction = significand >> subnormal_shift;
    return @bitCast(sign_bit | (fraction & 0x000F_FFFF_FFFF_FFFF));
}

pub fn x87RawFromInt(value: i64) __process_X87Raw {
    var raw: __process_X87Raw = [_]u8{0} ** 10;
    writeExtendedInt80(&raw, value);
    return raw;
}

pub fn x87RawFromFloat(value: f64) __process_X87Raw {
    var raw: __process_X87Raw = [_]u8{0} ** 10;
    writeExtendedFloat80(&raw, value);
    return raw;
}

pub fn x87Physical(self: *const ElfState, logical: u3) u3 {
    return @truncate(process_impl_lifecycle.guestContextField(self, "x87_top").* +% logical);
}

pub fn x87StackFault(self: *ElfState, overflow: bool) void {
    // Invalid-operation and stack-fault bits are sticky.  C1 indicates
    // overflow, and is cleared for underflow, matching the masked x87
    // exception behavior used by the native execution path.
    process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 0;
    process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 6;
    if (overflow) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 9;
    } else {
        process_impl_lifecycle.guestContextField(self, "x87_status").* &= ~@as(u16, 1 << 9);
    }
}

pub fn x87PushRaw(self: *ElfState, value: __process_X87Raw) bool {
    const next: u3 = @truncate(process_impl_lifecycle.guestContextField(self, "x87_top").* -% 1);
    if (process_impl_lifecycle.guestContextField(self, "x87_tags").*[next]) {
        x87StackFault(self, true);
        return false;
    }
    process_impl_lifecycle.guestContextField(self, "x87_top").* = next;
    process_impl_lifecycle.guestContextField(self, "x87_stack").*[next] = value;
    process_impl_lifecycle.guestContextField(self, "x87_tags").*[next] = true;
    return true;
}

pub fn x87GetRaw(self: *ElfState, logical: u3) ?__process_X87Raw {
    const physical = x87Physical(self, logical);
    if (!process_impl_lifecycle.guestContextField(self, "x87_tags").*[physical]) {
        x87StackFault(self, false);
        return null;
    }
    return process_impl_lifecycle.guestContextField(self, "x87_stack").*[physical];
}

pub fn x87SetRaw(self: *ElfState, logical: u3, value: __process_X87Raw) bool {
    const physical = x87Physical(self, logical);
    if (!process_impl_lifecycle.guestContextField(self, "x87_tags").*[physical]) {
        x87StackFault(self, false);
        return false;
    }
    process_impl_lifecycle.guestContextField(self, "x87_stack").*[physical] = value;
    return true;
}

pub fn x87PopRaw(self: *ElfState) ?__process_X87Raw {
    const physical = process_impl_lifecycle.guestContextField(self, "x87_top").*;
    if (!process_impl_lifecycle.guestContextField(self, "x87_tags").*[physical]) {
        x87StackFault(self, false);
        return null;
    }
    const value = process_impl_lifecycle.guestContextField(self, "x87_stack").*[physical];
    process_impl_lifecycle.guestContextField(self, "x87_tags").*[physical] = false;
    process_impl_lifecycle.guestContextField(self, "x87_top").* +%= 1;
    return value;
}

pub fn x87StatusWord(self: *const ElfState) u16 {
    return (process_impl_lifecycle.guestContextField(self, "x87_status").* & ~@as(u16, 0x3800)) | (@as(u16, process_impl_lifecycle.guestContextField(self, "x87_top").*) << 11);
}

pub fn x87Reset(self: *ElfState) void {
    process_impl_lifecycle.guestContextField(self, "x87_stack").* = [_]__process_X87Raw{[_]u8{0} ** 10} ** 8;
    process_impl_lifecycle.guestContextField(self, "x87_tags").* = [_]bool{false} ** 8;
    process_impl_lifecycle.guestContextField(self, "x87_top").* = 0;
    process_impl_lifecycle.guestContextField(self, "x87_status").* = 0;
    process_impl_lifecycle.guestContextField(self, "x87_control").* = 0x037F;
}

pub fn x87Exchange(self: *ElfState, logical: u3) void {
    const other = x87Physical(self, logical);
    if (!process_impl_lifecycle.guestContextField(self, "x87_tags").*[process_impl_lifecycle.guestContextField(self, "x87_top").*] or !process_impl_lifecycle.guestContextField(self, "x87_tags").*[other]) {
        x87StackFault(self, false);
        return;
    }
    __process_std.mem.swap(__process_X87Raw, &process_impl_lifecycle.guestContextField(self, "x87_stack").*[process_impl_lifecycle.guestContextField(self, "x87_top").*], &process_impl_lifecycle.guestContextField(self, "x87_stack").*[other]);
}

pub fn x87Free(self: *ElfState, logical: u3) void {
    process_impl_lifecycle.guestContextField(self, "x87_tags").*[x87Physical(self, logical)] = false;
}

pub fn x87Cos(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    const value = readExtendedFloat80(&raw);
    if (!__process_std.math.isFinite(value) or @abs(value) > 0x1p63) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 10;
        return;
    }
    process_impl_lifecycle.guestContextField(self, "x87_status").* &= ~@as(u16, (1 << 9) | (1 << 10));
    _ = x87SetRaw(self, 0, x87RawFromFloat(@cos(value)));
}

pub fn x87Sin(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    const value = readExtendedFloat80(&raw);
    if (!__process_std.math.isFinite(value) or @abs(value) > 0x1p63) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 10;
        return;
    }
    process_impl_lifecycle.guestContextField(self, "x87_status").* &= ~@as(u16, (1 << 9) | (1 << 10));
    _ = x87SetRaw(self, 0, x87RawFromFloat(@sin(value)));
}

pub fn x87Fchs(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    _ = x87SetRaw(self, 0, x87RawFromFloat(-readExtendedFloat80(&raw)));
}

pub fn x87Fabs(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    _ = x87SetRaw(self, 0, x87RawFromFloat(@abs(readExtendedFloat80(&raw))));
}

pub fn x87Test(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    const value = readExtendedFloat80(&raw);
    process_impl_lifecycle.guestContextField(self, "x87_status").* &= ~@as(u16, (1 << 8) | (1 << 10) | (1 << 14));
    if (__process_std.math.isNan(value)) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= (1 << 8) | (1 << 10) | (1 << 14);
    } else if (value == 0.0) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 14;
    } else if (value < 0.0) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 8;
    }
}

pub fn x87CompareStatus(self: *ElfState, lhs: f64, rhs: f64, pop_result: bool) void {
    process_impl_lifecycle.guestContextField(self, "x87_status").* &= ~@as(u16, (1 << 8) | (1 << 10) | (1 << 14));
    if (__process_std.math.isNan(lhs) or __process_std.math.isNan(rhs)) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= (1 << 8) | (1 << 10) | (1 << 14);
    } else if (lhs == rhs) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 14;
    } else if (lhs < rhs) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 8;
    }
    if (pop_result) _ = x87PopRaw(self);
}

pub fn x87F2xm1(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    const value = readExtendedFloat80(&raw);
    if (!__process_std.math.isFinite(value) or value < -1.0 or value > 1.0) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1;
        return;
    }
    _ = x87SetRaw(self, 0, x87RawFromFloat(__process_std.math.exp2(value) - 1.0));
}

pub fn x87Fyl2x(self: *ElfState, add_one: bool) void {
    const x_raw = x87GetRaw(self, 0) orelse return;
    const y_raw = x87GetRaw(self, 1) orelse return;
    const x = readExtendedFloat80(&x_raw);
    const y = readExtendedFloat80(&y_raw);
    const argument = if (add_one) x + 1.0 else x;
    if (!__process_std.math.isFinite(argument) or argument <= 0.0) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1;
        return;
    }
    _ = x87SetRaw(self, 1, x87RawFromFloat(y * __process_std.math.log2(argument)));
    _ = x87PopRaw(self);
}

pub fn x87Fptan(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    const value = readExtendedFloat80(&raw);
    if (!__process_std.math.isFinite(value)) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1;
        return;
    }
    _ = x87SetRaw(self, 0, x87RawFromFloat(@tan(value)));
    _ = x87PushRaw(self, x87RawFromFloat(1.0));
}

pub fn x87Fpatan(self: *ElfState) void {
    const x_raw = x87GetRaw(self, 0) orelse return;
    const y_raw = x87GetRaw(self, 1) orelse return;
    const x = readExtendedFloat80(&x_raw);
    const y = readExtendedFloat80(&y_raw);
    _ = x87SetRaw(self, 1, x87RawFromFloat(__process_std.math.atan2(y, x)));
    _ = x87PopRaw(self);
}

pub fn x87Fxtract(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    const value = readExtendedFloat80(&raw);
    const parts = __process_std.math.frexp(value);
    _ = x87SetRaw(self, 0, x87RawFromFloat(parts.significand * 2.0));
    _ = x87PushRaw(self, x87RawFromInt(parts.exponent - 1));
}

pub fn x87PartialRemainder(self: *ElfState, nearest: bool) void {
    const numerator_raw = x87GetRaw(self, 0) orelse return;
    const denominator_raw = x87GetRaw(self, 1) orelse return;
    const numerator = readExtendedFloat80(&numerator_raw);
    const denominator = readExtendedFloat80(&denominator_raw);
    if (!__process_std.math.isFinite(numerator) or !__process_std.math.isFinite(denominator) or denominator == 0.0) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 10;
        return;
    }

    const quotient = if (nearest) __process_std.math.round(numerator / denominator) else @trunc(numerator / denominator);
    const remainder = numerator - quotient * denominator;
    process_impl_lifecycle.guestContextField(self, "x87_status").* &= ~@as(u16, (1 << 8) | (1 << 9) | (1 << 10) | (1 << 14));
    const quotient_bits: u64 = @bitCast(@as(i64, @intFromFloat(quotient)));
    if ((quotient_bits & 0x4) != 0) process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 8;
    if ((quotient_bits & 0x2) != 0) process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 9;
    if ((quotient_bits & 0x1) != 0) process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 14;
    _ = x87SetRaw(self, 0, x87RawFromFloat(remainder));
}

pub fn x87PartialRemainderNearest(self: *ElfState) void {
    x87PartialRemainder(self, true);
}

pub fn x87PartialRemainderTrunc(self: *ElfState) void {
    x87PartialRemainder(self, false);
}

pub fn x87Fsincos(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    const value = readExtendedFloat80(&raw);
    if (!__process_std.math.isFinite(value)) {
        process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1;
        return;
    }
    _ = x87SetRaw(self, 0, x87RawFromFloat(@sin(value)));
    _ = x87PushRaw(self, x87RawFromFloat(@cos(value)));
}

pub fn x87Frndint(self: *ElfState) void {
    const raw = x87GetRaw(self, 0) orelse return;
    const value = readExtendedFloat80(&raw);
    const rounding = (process_impl_lifecycle.guestContextField(self, "x87_control").* >> 10) & 3;
    const rounded = switch (rounding) {
        0 => __process_std.math.round(value),
        1 => @floor(value),
        2 => @ceil(value),
        else => @trunc(value),
    };
    _ = x87SetRaw(self, 0, x87RawFromFloat(rounded));
}

pub fn x87Fscale(self: *ElfState) void {
    const value_raw = x87GetRaw(self, 0) orelse return;
    const scale_raw = x87GetRaw(self, 1) orelse return;
    const value = readExtendedFloat80(&value_raw);
    const scale = readExtendedFloat80(&scale_raw);
    if (!__process_std.math.isFinite(value) or !__process_std.math.isFinite(scale)) return;
    const exponent: i32 = if (scale >= 2147483647.0)
        __process_std.math.maxInt(i32)
    else if (scale <= -2147483648.0)
        __process_std.math.minInt(i32)
    else
        @intFromFloat(@trunc(scale));
    _ = x87SetRaw(self, 0, x87RawFromFloat(__process_std.math.ldexp(value, exponent)));
}

pub fn x87Fclex(self: *ElfState) void {
    process_impl_lifecycle.guestContextField(self, "x87_status").* &= ~@as(u16, 0x00BF);
}

pub fn x87WriteRawMemory(self: *ElfState, addr: u64, raw: __process_X87Raw) void {
    process_impl_guest_memory.traceGuestWrite(self, addr, 10, __process_std.mem.readInt(u64, raw[0..8], .little));
    _ = copyToGuest(self, addr, &raw);
}

pub fn x87Compare(self: *ElfState, source: u3, pop_result: bool) void {
    const lhs_raw = x87GetRaw(self, 0) orelse return;
    const rhs_raw = x87GetRaw(self, source) orelse return;
    const lhs = readExtendedFloat80(&lhs_raw);
    const rhs = readExtendedFloat80(&rhs_raw);
    process_impl_lifecycle.guestContextField(self, "regs").*.rflags &= ~(__process_RFL_ZF | __process_RFL_PF | __process_RFL_CF | __process_RFL_OF | __process_RFL_SF | __process_RFL_AF);
    if (__process_std.math.isNan(lhs) or __process_std.math.isNan(rhs)) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= __process_RFL_ZF | __process_RFL_PF | __process_RFL_CF;
    } else if (lhs < rhs) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= __process_RFL_CF;
    } else if (lhs == rhs) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= __process_RFL_ZF;
    }
    if (pop_result) _ = x87PopRaw(self);
}

pub fn x87Divide(numerator: f64, denominator: f64, status: *u16) f64 {
    if (denominator != 0.0) return numerator / denominator;
    if (numerator == 0.0 or __process_std.math.isNan(numerator)) return __process_std.math.nan(f64);
    status.* |= 1 << 2;
    const sign = (@as(u64, @bitCast(numerator)) ^ @as(u64, @bitCast(denominator))) & (@as(u64, 1) << 63);
    return @bitCast(sign | 0x7FF0_0000_0000_0000);
}

pub fn x87MemoryValue(self: *ElfState, d: __process_DecodedInsn, integer: bool) f64 {
    const bits = readMemVal(self, d.addr, d.size);
    if (integer) {
        return switch (d.size) {
            .bits16 => @floatFromInt(@as(i16, @bitCast(@as(u16, @truncate(bits))))),
            .bits32 => @floatFromInt(@as(i32, @bitCast(@as(u32, @truncate(bits))))),
            else => @floatFromInt(@as(i64, @bitCast(bits))),
        };
    }
    return switch (d.size) {
        .bits32 => @floatCast(@as(f32, @bitCast(@as(u32, @truncate(bits))))),
        .bits64 => @bitCast(bits),
        else => 0.0,
    };
}

pub fn x87Memory(self: *ElfState, d: __process_DecodedInsn) void {
    const lhs_raw = x87GetRaw(self, 0) orelse return;
    const lhs = readExtendedFloat80(&lhs_raw);
    const rhs = x87MemoryValue(self, d, (d.imm & (@as(u64, 1) << 3)) != 0);
    const operation: u3 = @truncate(d.imm & 7);
    if (operation == 6 or operation == 7) {
        x87CompareStatus(self, lhs, rhs, operation == 7);
        return;
    }
    const result = switch (operation) {
        0 => lhs + rhs,
        1 => lhs * rhs,
        2 => lhs - rhs,
        3 => rhs - lhs,
        4 => x87Divide(lhs, rhs, &process_impl_lifecycle.guestContextField(self, "x87_status").*),
        5 => x87Divide(rhs, lhs, &process_impl_lifecycle.guestContextField(self, "x87_status").*),
        else => unreachable,
    };
    _ = x87SetRaw(self, 0, x87RawFromFloat(result));
}

pub fn x87Binary(self: *ElfState, d: __process_DecodedInsn) void {
    const destination: u3 = @truncate((d.imm >> 3) & 7);
    const source: u3 = @truncate((d.imm >> 6) & 7);
    const operation: u3 = @truncate(d.imm & 7);
    const lhs_raw = x87GetRaw(self, destination) orelse return;
    const rhs_raw = x87GetRaw(self, source) orelse return;
    const lhs = readExtendedFloat80(&lhs_raw);
    const rhs = readExtendedFloat80(&rhs_raw);
    const result = switch (operation) {
        0 => lhs + rhs,
        1 => lhs * rhs,
        2 => lhs - rhs,
        3 => rhs - lhs,
        4 => x87Divide(lhs, rhs, &process_impl_lifecycle.guestContextField(self, "x87_status").*),
        5 => x87Divide(rhs, lhs, &process_impl_lifecycle.guestContextField(self, "x87_status").*),
        else => unreachable,
    };
    _ = x87SetRaw(self, destination, x87RawFromFloat(result));
    if ((d.imm & (1 << 9)) != 0) _ = x87PopRaw(self);
}

pub fn readMem128(self: *ElfState, addr: u64) [16]u8 {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| {
        if (self.guest_page_protection.isActive() and self.guest_page_protection.faults(addr, 16, false)) {
            journal.fail(.protected_page, addr);
            return @splat(0);
        }
    }
    var value = [_]u8{0} ** 16;
    const source = guestMemorySourceConst(self, addr, 16) orelse return value;
    // A vector snapshot is a bulk load, not a raw borrowed view. Keep
    // this executor's pending stores buffered and forward them through
    // the two scalar-width loads, just as ordinary scalar loads do.
    __process_tso_memory.loadFence();
    inline for (.{ 0, 8 }) |offset| {
        const lane = process_impl_guest_memory.loadGuestScalarAt(self, u64, addr +| offset, source[offset..]);
        __process_std.mem.writeInt(u64, value[offset..][0..8], lane, .little);
    }
    // Same contract as `readMemVal`: the backing bytes are returned and
    // a no-access page leaves a fault pending for the step boundary.
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| {
        journal.forward(addr, &value);
        return value;
    }
    if (self.guest_page_protection.isActive() and self.wide_access_watch_enabled) _ = process_impl_guest_memory.noteGuestWideAccess(self, addr, false, value);
    return value;
}

pub fn writeMem128(self: *ElfState, addr: u64, value: [16]u8) void {
    writeMem128WithPolicy(self, addr, value, false);
}

pub fn writeMem128NonTemporal(self: *ElfState, addr: u64, value: [16]u8) void {
    writeMem128WithPolicy(self, addr, value, true);
}

pub fn writeMem128WithPolicy(self: *ElfState, addr: u64, value: [16]u8, non_temporal: bool) void {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| {
        if (non_temporal) return journal.fail(.unsupported, addr);
        if (self.guest_page_protection.isActive() and self.guest_page_protection.faults(addr, 16, true)) return journal.fail(.protected_page, addr);
        return journal.store(addr, &value);
    }
    if (non_temporal) __process_tso_memory.flushActiveStoreBufferFor(.non_temporal_store);
    traceGuestVectorWrite(self, addr, value);
    // A protected store is withheld until the fault is resolved, as in
    // `writeMemVal`.
    if (self.guest_page_protection.isActive() and self.wide_access_watch_enabled and process_impl_guest_memory.noteGuestWideAccess(self, addr, true, value)) return;
    const destination = guestMemoryTsoWriteTarget(self, addr, 16) orelse return;
    // The vector value is local register state. Emit two width-preserving
    // guest stores even when the host address of `value` is only byte
    // aligned; routing through generic memcpy would then degrade to 16
    // byte stores and inflate the per-executor queue.
    inline for (.{ 0, 8 }) |offset| {
        process_impl_guest_memory.storeGuestScalarAt(
            self,
            u64,
            addr +| offset,
            destination[offset..],
            __process_std.mem.readInt(u64, value[offset..][0..8], .little),
            non_temporal,
        );
    }
    finishGuestMemoryTsoWrite(self, addr, 16);
}

pub fn traceGuestVectorWrite(self: *const ElfState, addr: u64, value: [16]u8) void {
    if (self.spin_watch.armed()) process_impl_lifecycle.noteSpinWatchWrite(self, addr, 16, __process_std.mem.readInt(u64, value[0..8], .little), "vector");
    const watch = self.trace_write_address orelse return;
    const write_end = addr +| 16;
    const watch_end = watch +| 8;
    if (addr >= watch_end or write_end <= watch) return;
    if (comptime @import("builtin").is_test) return;

    __process_log.info("trace guest vector write address=0x{x} bytes={any} watch=0x{x} rip=0x{x} op={s} len={d} rsp=0x{x} ret=0x{x}", .{
        addr,
        value,
        watch,
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
        process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
    });
}

pub fn guestMemory(self: *ElfState, addr: u64, count: u64) ?[]u8 {
    if (self.parallel_guest_execution and guestRangeMayHoldFetchedCode(self, addr, count)) {
        noteParallelCodeBorrowRefused(self, addr, count);
        return null;
    }
    if (count > __process_std.math.maxInt(usize)) return null;
    const count_usize: usize = @intCast(count);
    if (self.guest_page_protection.isActive()) process_impl_guest_memory.noteProtectedBulkBorrow(self, addr, count);
    if (process_impl_guest_memory.addrToOffset(self, addr)) |off| {
        const off_usize: usize = @intCast(off);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        // Serial callers may mutate this borrowed slice directly. The
        // code-generation bump can precede that mutation because no
        // other executor can decode until this synchronous runtime path
        // returns. A parallel borrow reaching here holds no code bytes.
        process_impl_guest_memory.bumpWindowsImageCodeGeneration(self, addr, count);
        __process_tso_memory.storeFence();
        return self.mem[off_usize .. off_usize + count_usize];
    }
    const bytes = process_impl_guest_memory.windowsMappedMemory(self, addr, count) orelse return null;
    process_impl_guest_memory.bumpWindowsMappedCodeGeneration(self, addr, count);
    __process_tso_memory.storeFence();
    return bytes;
}

pub fn guestRangeMayHoldFetchedCode(self: *const ElfState, addr: u64, count: u64) bool {
    if (count == 0) return false;
    if (process_impl_guest_memory.addrToOffset(self, addr) != null) return process_impl_guest_memory.windowsImageRangeOverlapsCode(self, addr, count);
    const range = self.windows_mapped_ranges.find(addr, count) orelse return false;
    return process_impl_block_jit.mappedRangeCodeFetched(self, range);
}

pub fn noteParallelCodeBorrowRefused(self: *ElfState, addr: u64, count: u64) void {
    const occurrence = self.parallel_code_borrow_refusals.fetchAdd(1, .monotonic) + 1;
    if (comptime @import("builtin").is_test) return;
    if (!process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) return;
    __process_log.warn("PE64 PARALLEL CODE BORROW REFUSED: address=0x{x} count={d} occurrence={d} rip=0x{x} thread=0x{x}; a runtime path asked for a mutable view of executable bytes while guest threads run in parallel; it has to write through copyToGuest or fillGuestMemory so the code generation moves after the bytes", .{
        addr,
        count,
        occurrence,
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
    });
}

pub fn guestMemoryTsoWriteTarget(self: *ElfState, addr: u64, count: u64) ?[]u8 {
    if (count > __process_std.math.maxInt(usize)) return null;
    const count_usize: usize = @intCast(count);
    if (self.guest_page_protection.isActive()) process_impl_guest_memory.noteProtectedBulkBorrow(self, addr, count);
    if (process_impl_guest_memory.addrToOffset(self, addr)) |off| {
        const off_usize: usize = @intCast(off);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
    }
    return process_impl_guest_memory.windowsMappedMemory(self, addr, count);
}

pub fn finishGuestMemoryTsoWrite(self: *ElfState, addr: u64, count: u64) void {
    if (process_impl_guest_memory.addrToOffset(self, addr) != null) {
        process_impl_guest_memory.bumpWindowsImageCodeGeneration(self, addr, count);
    } else {
        process_impl_guest_memory.bumpWindowsMappedCodeGeneration(self, addr, count);
    }
}

pub fn copyToGuest(self: *ElfState, addr: u64, source: []const u8) bool {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| {
        journal.fail(.unsupported, addr);
        return false;
    }
    const count: u64 = @intCast(source.len);
    const destination = guestMemoryTsoWriteTarget(self, addr, count) orelse return false;
    process_impl_guest_memory.copyGuestBackingForClass(
        self,
        destination,
        source,
        process_impl_guest_memory.guestMemoryRangeClass(self, addr, count, true),
    );
    finishGuestMemoryTsoWrite(self, addr, count);
    if (self.spin_watch.armed()) process_impl_lifecycle.noteSpinWatchBulkWrite(self, addr, count, "copy");
    return true;
}

pub fn copyGuestRange(self: *ElfState, destination_address: u64, source_address: u64, count: u64) bool {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| {
        journal.fail(.unsupported, destination_address);
        return false;
    }
    if (count == 0) return true;
    const destination = guestMemoryTsoWriteTarget(self, destination_address, count) orelse return false;
    const source = guestMemorySourceConst(self, source_address, count) orelse return false;
    if (destination_address == source_address) return true;

    const destination_class = process_impl_guest_memory.guestMemoryRangeClass(self, destination_address, count, true);
    const source_class = process_impl_guest_memory.guestMemoryRangeClass(self, source_address, count, false);
    const destination_bypasses_buffer = __process_tso_memory_policy.bypassStoreBuffer(destination_class);
    const source_bypasses_buffer = __process_tso_memory_policy.bypassStoreBuffer(source_class);
    const overlaps_backwards = destination_address > source_address and
        destination_address - source_address < count;

    if (destination_bypasses_buffer or source_bypasses_buffer) {
        const boundary = if (destination_bypasses_buffer)
            process_impl_guest_memory.memoryClassBoundary(destination_class)
        else
            process_impl_guest_memory.memoryClassBoundary(source_class);
        __process_tso_memory.flushActiveStoreBufferFor(boundary);
        const previous = __process_tso_memory.setActiveStoreBuffer(null);
        defer _ = __process_tso_memory.setActiveStoreBuffer(previous);
        __process_tso_memory.copyDirectionalCoordinated(destination, source, overlaps_backwards);
    } else if (self.parallel_guest_execution) {
        __process_tso_memory.copyDirectionalCoordinated(destination, source, overlaps_backwards);
    } else {
        __process_tso_memory.copyDirectional(destination, source, overlaps_backwards);
    }

    finishGuestMemoryTsoWrite(self, destination_address, count);
    if (self.spin_watch.armed()) process_impl_lifecycle.noteSpinWatchBulkWrite(self, destination_address, count, "memcpy");
    return true;
}

pub fn fillGuestMemory(self: *ElfState, addr: u64, count: u64, byte: u8) bool {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| {
        journal.fail(.unsupported, addr);
        return false;
    }
    const destination = guestMemoryTsoWriteTarget(self, addr, count) orelse return false;
    process_impl_guest_memory.fillGuestBackingForClass(
        self,
        destination,
        byte,
        process_impl_guest_memory.guestMemoryRangeClass(self, addr, count, true),
    );
    finishGuestMemoryTsoWrite(self, addr, count);
    if (self.spin_watch.armed()) process_impl_lifecycle.noteSpinWatchBulkWrite(self, addr, count, "fill");
    return true;
}

pub fn copyFromGuest(self: *const ElfState, destination: []u8, addr: u64) bool {
    const source = guestMemorySourceConst(self, addr, @intCast(destination.len)) orelse return false;
    const class = process_impl_guest_memory.guestMemoryRangeClass(self, addr, @intCast(destination.len), false);
    if (__process_tso_memory_policy.bypassStoreBuffer(class)) {
        __process_tso_memory.flushActiveStoreBufferFor(process_impl_guest_memory.memoryClassBoundary(class));
        __process_tso_memory.loadFence();
        __process_tso_memory.copyBackingCoordinated(destination, source);
    } else {
        __process_tso_memory.loadFence();
        process_impl_guest_memory.snapshotGuestBacking(self, destination, source);
    }
    return true;
}

pub fn flushGuestMemorySnapshotStores(self: *const ElfState) void {
    if (__process_tso_memory.activeStoreBuffer()) |buffer| {
        __process_tso_memory.boundary_ledger.noteFlush(.raw_view, buffer.drain());
        return;
    }
    if (!self.windows_runtime_enabled or !__process_tso_memory.StoreBuffer.anyBufferPending()) return;

    // Other executors' queued stores are theirs: on x86 a store sitting
    // in another core's buffer is not yet visible to this one, and the
    // guest's own synchronization (a locked instruction, a runtime call)
    // is what publishes it. This used to stop the world whenever any
    // executor had anything queued, which in parallel mode was nearly
    // every runtime read of guest memory.
    if (self.parallel_guest_execution) return;
    const mutable_self = @constCast(self);
    process_impl_block_jit.flushAllGuestStoreBuffers(mutable_self, .raw_view);
}

pub fn guestMemoryConst(self: *const ElfState, addr: u64, count: u64) ?[]const u8 {
    if (count > __process_std.math.maxInt(usize)) return null;
    // A returned slice cannot overlay this executor's buffered stores.
    // Publish them before handing out a direct view so runtime readers
    // observe the same bytes as scalar x86 loads.
    flushGuestMemorySnapshotStores(self);
    __process_tso_memory.loadFence();
    return guestMemorySourceConst(self, addr, count);
}

pub fn guestMemorySourceConst(self: *const ElfState, addr: u64, count: u64) ?[]const u8 {
    if (count > __process_std.math.maxInt(usize)) return null;
    const count_usize: usize = @intCast(count);
    if (process_impl_guest_memory.addrToOffset(self, addr)) |off| {
        const off_usize: usize = @intCast(off);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
    }
    return process_impl_guest_memory.windowsMappedMemoryConst(self, addr, count);
}

pub fn guestMemoryTailConst(self: *const ElfState, addr: u64, maximum: usize) ?[]const u8 {
    if (maximum == 0) return null;
    flushGuestMemorySnapshotStores(self);
    __process_tso_memory.loadFence();
    return guestMemorySourceTailConst(self, addr, maximum);
}

pub fn guestMemorySourceTailConst(self: *const ElfState, addr: u64, maximum: usize) ?[]const u8 {
    if (maximum == 0) return null;
    if (process_impl_guest_memory.nativeMemoryAlias(self, addr, 1) != null) {
        for (self.native_memory_aliases[0..self.native_memory_alias_count]) |alias| {
            const bytes = alias.bytes orelse continue;
            if (addr < alias.guest_base or addr >= alias.guest_base + bytes.len) continue;
            const offset: usize = @intCast(addr - alias.guest_base);
            return bytes[offset..@min(bytes.len, offset +| maximum)];
        }
    }
    if (process_impl_guest_memory.addrToOffset(self, addr)) |off| {
        const start: usize = @intCast(off);
        if (start >= self.mem.len) return null;
        return self.mem[start..@min(self.mem.len, start +| maximum)];
    }
    for (self.windows_memory_views[0..self.windows_memory_view_count]) |view| {
        if (view.length == 0 or addr < view.guest_base) continue;
        const view_end = __process_std.math.add(u64, view.guest_base, view.length) catch continue;
        if (addr >= view_end) continue;
        const mapping = self.windows_file_mappings[view.mapping_index];
        const backing = mapping.backing orelse continue;
        const backing_offset = __process_std.math.add(u64, view.backing_offset, addr - view.guest_base) catch return null;
        const offset = __process_std.math.cast(usize, backing_offset) orelse return null;
        if (offset >= backing.len) return null;
        const in_view = __process_std.math.cast(usize, view_end - addr) orelse __process_std.math.maxInt(usize);
        return backing[offset..@min(backing.len, offset +| @min(maximum, in_view))];
    }
    for (self.windows_virtual_allocations[0..self.windows_virtual_allocation_count]) |allocation| {
        if (allocation.length == 0 or addr < allocation.guest_base) continue;
        const allocation_end = __process_std.math.add(u64, allocation.guest_base, allocation.length) catch continue;
        if (addr >= allocation_end) continue;
        const backing = allocation.backing orelse continue;
        const offset = __process_std.math.cast(usize, addr - allocation.guest_base) orelse return null;
        if (offset >= backing.len) return null;
        return backing[offset..@min(backing.len, offset +| maximum)];
    }
    return null;
}

pub fn guestCStringConst(self: *const ElfState, addr: u64, maximum: usize) ?[]const u8 {
    if (addr == 0) return null;
    const tail = guestMemoryTailConst(self, addr, maximum) orelse return null;
    const length = __process_std.mem.indexOfScalar(u8, tail, 0) orelse return null;
    return tail[0..length];
}

pub fn copyGuestCString(self: *const ElfState, addr: u64, maximum: usize, destination: []u8) ?usize {
    if (addr == 0 or maximum == 0) return null;
    const source = guestMemorySourceTailConst(self, addr, maximum) orelse return null;
    const class = process_impl_guest_memory.guestMemoryRangeClass(self, addr, @intCast(source.len), false);
    if (__process_tso_memory_policy.bypassStoreBuffer(class)) {
        __process_tso_memory.flushActiveStoreBufferFor(process_impl_guest_memory.memoryClassBoundary(class));
    }
    __process_tso_memory.loadFence();
    const length = __process_tso_memory.findCStringEndCoordinated(source) orelse return null;
    if (length > destination.len) return null;
    if (length != 0) {
        if (__process_tso_memory_policy.bypassStoreBuffer(class)) {
            __process_tso_memory.copyBackingCoordinated(destination[0..length], source[0..length]);
        } else {
            process_impl_guest_memory.snapshotGuestBacking(self, destination[0..length], source[0..length]);
        }
    }
    return length;
}

pub fn writeHostFd(self: *ElfState, fd: u64, data: []const u8) u64 {
    _ = self;
    const host_fd = __process_hostFdFromGuest(fd) orelse return __process_x64_syscalls.errnoValue(.bad_file_descriptor);
    var written: usize = 0;
    while (written < data.len) {
        const n = __process_std.c.write(host_fd, data[written..].ptr, data.len - written);
        if (n <= 0) return __process_x64_syscalls.errnoValue(.io);
        written += @intCast(n);
    }
    return @intCast(data.len);
}

pub fn traceGuestIo(self: *const ElfState, operation: []const u8, fd: u64, addr: u64, count: u64, result: u64) void {
    if (!shouldTraceFd(self, fd)) return;
    __process_log.info("runtime io: {s}(fd={d}, buf=0x{x}, count={d}) -> {d}", .{
        operation,
        fd,
        addr,
        count,
        __process_syscallResult(result),
    });
    if (!self.trace_syscall_bytes) return;
    if (__process_syscallResult(result) <= 0) return;
    const available = @min(count, result);
    var preview: [96]u8 = undefined;
    const preview_length: usize = @intCast(@min(available, preview.len));
    if (preview_length != 0 and !copyFromGuest(self, preview[0..preview_length], addr)) return;
    traceDataPreview(self, operation, fd, preview[0..preview_length], available);
}

pub fn traceSyscall(self: *const ElfState, comptime fmt: []const u8, args: anytype) void {
    if (!self.trace_syscalls) return;
    if (self.trace_fd_filter != null) return;
    __process_log.info("syscall: " ++ fmt, args);
}

pub fn traceOpenResult(self: *const ElfState, path: []const u8, flags_raw: u64, mode_raw: u64, result: u64) void {
    if (!shouldTraceResultFd(self, result)) return;
    __process_log.info("syscall: open(\"{s}\", flags=0x{x}, mode=0o{o}) -> {d}", .{
        path,
        flags_raw,
        mode_raw & 0o7777,
        __process_syscallResult(result),
    });
}

pub fn traceCreatResult(self: *const ElfState, path: []const u8, mode_raw: u64, result: u64) void {
    if (!shouldTraceResultFd(self, result)) return;
    __process_log.info("syscall: creat(\"{s}\", mode=0o{o}) -> {d}", .{
        path,
        mode_raw & 0o7777,
        __process_syscallResult(result),
    });
}

pub fn shouldTraceFd(self: *const ElfState, fd: u64) bool {
    if (!self.trace_syscalls) return false;
    if (self.trace_fd_filter) |filter| return fd == filter;
    return true;
}

pub fn shouldTraceResultFd(self: *const ElfState, result: u64) bool {
    if (!self.trace_syscalls) return false;
    if (self.trace_fd_filter) |filter| {
        if (__process_syscallResult(result) < 0) return false;
        return result == filter;
    }
    return true;
}

pub fn traceDataPreview(self: *const ElfState, operation: []const u8, fd: u64, data: []const u8, total_length: u64) void {
    if (!self.trace_syscall_bytes) return;
    var preview: [96]u8 = undefined;
    const n = @min(preview.len, data.len);
    for (data[0..n], 0..) |byte, i| {
        preview[i] = switch (byte) {
            0x20...0x7e => byte,
            '\n' => '|',
            '\r', '\t' => ' ',
            else => '.',
        };
    }
    __process_log.info("runtime io bytes: {s}(fd={d}) {d} byte preview \"{s}\"", .{
        operation,
        fd,
        total_length,
        preview[0..n],
    });
}

pub fn abiTraceConfig(self: *const ElfState) __process_x64_guest_abi.TraceConfig {
    return .{
        .trace_calls = self.trace_calls,
        .diagnose = self.diagnose_abi,
    };
}

pub fn activeCallStack(self: *ElfState) *__process_x64_guest_abi.CallStack {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| {
        return &self.windows_guest_threads[slot].call_stack;
    }
    return &self.call_stack;
}

pub fn noteGuestCall(self: *ElfState, kind: __process_x64_guest_abi.CallKind, target: u64, return_rip: u64) void {
    if (!self.trace_calls) return;
    activeCallStack(self).enter(self.allocator, abiTraceConfig(self), .{
        .target = target,
        .return_rip = return_rip,
        .rsp_before_call = process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        .symbol = process_impl_kernel_services.localSymbolNameAt(self, target),
        .kind = kind,
    });
}

pub fn noteGuestReturn(self: *ElfState, return_rip: u64) void {
    if (!self.trace_calls) return;
    activeCallStack(self).leave(abiTraceConfig(self), return_rip, process_impl_lifecycle.guestContextField(self, "regs").*.rsp, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
}

pub fn setFlagsSub(self: *ElfState, a: u64, b: u64, result: u64, size: __process_Size) void {
    __process_x64_decoder.applySub(&process_impl_lifecycle.guestContextField(self, "regs").*.rflags, a, b, result, size);
}

pub fn setFlagsAdd(self: *ElfState, a: u64, b: u64, result: u64, size: __process_Size) void {
    __process_x64_decoder.applyAdd(&process_impl_lifecycle.guestContextField(self, "regs").*.rflags, a, b, result, size);
}

pub fn setFlagsIncDec(self: *ElfState, input: u64, result: u64, size: __process_Size, is_inc: bool) void {
    __process_x64_decoder.applyIncDec(&process_impl_lifecycle.guestContextField(self, "regs").*.rflags, input, result, size, is_inc);
}

pub fn setFlagsLogic(self: *ElfState, result: u64, size: __process_Size) void {
    __process_x64_decoder.applyLogic(&process_impl_lifecycle.guestContextField(self, "regs").*.rflags, result, size);
}

pub fn bmiSource(self: *ElfState, d: __process_DecodedInsn) u64 {
    return if (d.is_reg_form) regVal(self, d.src_reg, d.size) else readMemVal(self, d.addr, d.size);
}

pub fn executeBmi(self: *ElfState, d: __process_DecodedInsn) void {
    const mask = maskForSize(d.size);
    const width: u7 = if (d.size == .bits64) 64 else 32;

    switch (d.op) {
        .andn => {
            const source1 = regVal(self, d.src_reg2, d.size);
            const source2 = bmiSource(self, d);
            const result = (~source1 & source2) & mask;
            setReg(self, d.dst_reg, d.size, result);
            setFlagsLogic(self, result, d.size);
        },
        .bzhi => {
            const source = bmiSource(self, d) & mask;
            const index = regVal(self, d.src_reg2, d.size) & 0xFF;
            const result = if (index >= width)
                source
            else if (index == 0)
                0
            else
                source & ((@as(u64, 1) << @as(u6, @intCast(index))) - 1);
            setReg(self, d.dst_reg, d.size, result);
            setFlag(self, __process_RFL_CF, index >= width);
        },
        .mulx => {
            const multiplicand = regVal(self, .dl_dx_edx_rdx, d.size);
            const source = bmiSource(self, d);
            const product = @as(u128, multiplicand) * @as(u128, source);
            const low = @as(u64, @truncate(product)) & mask;
            const high = @as(u64, @truncate(product >> width)) & mask;
            setReg(self, d.dst_reg, d.size, high);
            setReg(self, d.dst_reg2, d.size, low);
        },
        .rorx => {
            const source = bmiSource(self, d) & mask;
            const count: u6 = @intCast(d.imm & (width - 1));
            const result = if (count == 0) blk: {
                break :blk source;
            } else blk: {
                const rotate_back: u6 = @intCast((width - count) & 63);
                break :blk ((source >> count) | (source << rotate_back)) & mask;
            };
            setReg(self, d.dst_reg, d.size, result);
        },
        .shlx => {
            const source = bmiSource(self, d) & mask;
            const count: u6 = @intCast(regVal(self, d.src_reg2, d.size) & (width - 1));
            setReg(self, d.dst_reg, d.size, (source << count) & mask);
        },
        .shrx => {
            const source = bmiSource(self, d) & mask;
            const count: u6 = @intCast(regVal(self, d.src_reg2, d.size) & (width - 1));
            setReg(self, d.dst_reg, d.size, source >> count);
        },
        .sarx => {
            const source = bmiSource(self, d) & mask;
            const count: u6 = @intCast(regVal(self, d.src_reg2, d.size) & (width - 1));
            const signed: i64 = if (d.size == .bits64)
                @bitCast(source)
            else
                @as(i32, @bitCast(@as(u32, @truncate(source))));
            setReg(self, d.dst_reg, d.size, @as(u64, @bitCast(signed >> count)) & mask);
        },
        else => unreachable,
    }
}

pub fn executeVectorTest(self: *ElfState, d: __process_DecodedInsn) void {
    const rhs_low = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2] else readMem128(self, d.addr);
    const low = __process_x64_decoder.vectorTestPredicates(d.op, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src], rhs_low);
    process_impl_lifecycle.guestContextField(self, "regs").*.rflags &= ~(__process_RFL_OF | __process_RFL_SF | __process_RFL_ZF | __process_RFL_AF | __process_RFL_PF | __process_RFL_CF);
    if (d.vector_256) {
        const rhs_high = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src2] else readMem128(self, d.addr + 16);
        const high = __process_x64_decoder.vectorTestPredicates(d.op, process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src], rhs_high);
        if (low.zf and high.zf) process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= __process_RFL_ZF;
        if (low.cf and high.cf) process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= __process_RFL_CF;
    } else {
        if (low.zf) process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= __process_RFL_ZF;
        if (low.cf) process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= __process_RFL_CF;
    }
}

pub fn executeVpshufd(self: *ElfState, d: __process_DecodedInsn) void {
    // VPSHUFD shuffles each independent 128-bit lane.  The VEX.128 form
    // also clears the destination's upper YMM half; legacy SSE callers
    // carry `legacy_sse` and must preserve that half.
    const source_low = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src] else readMem128(self, d.addr);
    var result_low = [_]u8{0} ** 16;
    for (0..4) |lane| {
        const selected: usize = @intCast((d.imm >> @intCast(lane * 2)) & 0x03);
        @memcpy(result_low[lane * 4 ..][0..4], source_low[selected * 4 ..][0..4]);
    }
    process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result_low;

    if (d.vector_256) {
        const source_high = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src] else readMem128(self, d.addr +% 16);
        var result_high = [_]u8{0} ** 16;
        for (0..4) |lane| {
            const selected: usize = @intCast((d.imm >> @intCast(lane * 2)) & 0x03);
            @memcpy(result_high[lane * 4 ..][0..4], source_high[selected * 4 ..][0..4]);
        }
        process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = result_high;
    } else if (!d.legacy_sse) {
        @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
    }
}

pub fn vpdpbusdBlock(accumulator: [16]u8, unsigned_source: [16]u8, signed_source: [16]u8) [16]u8 {
    var result = accumulator;
    for (0..4) |lane| {
        const offset = lane * 4;
        var total: i64 = @as(i64, @as(i32, @bitCast(__process_std.mem.readInt(u32, accumulator[offset..][0..4], .little))));
        for (0..4) |byte_index| {
            const unsigned_value: i64 = unsigned_source[offset + byte_index];
            const signed_value: i64 = @as(i8, @bitCast(signed_source[offset + byte_index]));
            total += unsigned_value * signed_value;
        }
        __process_std.mem.writeInt(u32, result[offset..][0..4], @truncate(@as(u64, @bitCast(total))), .little);
    }
    return result;
}

pub fn executeVpdpbusd(self: *ElfState, d: __process_DecodedInsn) void {
    const low_unsigned = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
    const low_signed = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2] else readMem128(self, d.addr);
    process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = vpdpbusdBlock(process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst], low_unsigned, low_signed);
    if (d.vector_256) {
        const high_unsigned = process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src];
        const high_signed = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src2] else readMem128(self, d.addr + 16);
        process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = vpdpbusdBlock(process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], high_unsigned, high_signed);
    } else {
        @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
    }
}

pub fn executeVexLane128(self: *ElfState, d: __process_DecodedInsn) void {
    if (d.op == .vextractf128) {
        const selected = if ((d.imm & 1) == 0) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src] else process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src];
        if (d.is_reg_form) {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = selected;
            @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
        } else {
            writeMem128(self, d.addr, selected);
        }
        return;
    }

    const source2 = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2] else readMem128(self, d.addr);
    const source1_low = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
    const source1_high = process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src];
    const low = if ((d.imm & 1) == 0) source2 else source1_low;
    const high = if ((d.imm & 1) == 0) source1_high else source2;
    process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = low;
    process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = high;
}

pub fn executeVexPermute2x128(self: *ElfState, d: __process_DecodedInsn) void {
    const source1_low = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
    const source1_high = process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src];
    const source2_low = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2] else readMem128(self, d.addr);
    const source2_high = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src2] else readMem128(self, d.addr + 16);
    const selected_low = switch (d.imm & 0x03) {
        0 => source1_low,
        1 => source1_high,
        2 => source2_low,
        3 => source2_high,
        else => unreachable,
    };
    const selected_high = switch ((d.imm >> 4) & 0x03) {
        0 => source1_low,
        1 => source1_high,
        2 => source2_low,
        3 => source2_high,
        else => unreachable,
    };
    var result_low = selected_low;
    var result_high = selected_high;
    if ((d.imm & 0x08) != 0) @memset(&result_low, 0);
    if ((d.imm & 0x80) != 0) @memset(&result_high, 0);
    process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result_low;
    process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = result_high;
}

pub fn executeVphminposuw(self: *ElfState, d: __process_DecodedInsn) void {
    const source = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src] else readMem128(self, d.addr);
    var minimum: u16 = __process_std.math.maxInt(u16);
    var minimum_index: u16 = 0;
    for (0..8) |lane| {
        const value = __process_std.mem.readInt(u16, source[lane * 2 ..][0..2], .little);
        if (value < minimum) {
            minimum = value;
            minimum_index = @intCast(lane);
        }
    }
    var result = [_]u8{0} ** 16;
    __process_std.mem.writeInt(u16, result[0..2], minimum, .little);
    __process_std.mem.writeInt(u16, result[2..4], minimum_index, .little);
    process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result;
    @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
}

pub fn executeVexExtractElement(self: *ElfState, d: __process_DecodedInsn) void {
    const element_bytes: usize = switch (d.op) {
        .vpextrb => 1,
        .vpextrw => 2,
        .vpextrd => 4,
        .vpextrq => 8,
        else => unreachable,
    };
    const source_lane = @as(usize, @intCast(d.imm)) & ((16 / element_bytes) - 1);
    const value: u64 = switch (element_bytes) {
        1 => process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][source_lane],
        2 => __process_std.mem.readInt(u16, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][source_lane * 2 ..][0..2], .little),
        4 => __process_std.mem.readInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][source_lane * 4 ..][0..4], .little),
        8 => __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][source_lane * 8 ..][0..8], .little),
        else => unreachable,
    };
    if (d.is_reg_form) {
        const destination_size: __process_Size = if (d.op == .vpextrq) .bits64 else .bits32;
        setReg(self, d.dst_reg, destination_size, value);
    } else {
        writeMemVal(self, d.addr, d.size, value);
    }
}

pub fn executeVinsertps(self: *ElfState, d: __process_DecodedInsn) void {
    var result = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
    const source_lane = @as(usize, @intCast((d.imm >> 6) & 0x03));
    const destination_lane = @as(usize, @intCast((d.imm >> 4) & 0x03));
    const scalar: u32 = if (d.is_reg_form)
        __process_std.mem.readInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2][source_lane * 4 ..][0..4], .little)
    else
        @truncate(readMemVal(self, d.addr, .bits32));
    __process_std.mem.writeInt(u32, result[destination_lane * 4 ..][0..4], scalar, .little);
    for (0..4) |lane| {
        if ((d.imm & (@as(u8, 1) << @intCast(lane))) != 0) {
            @memset(result[lane * 4 ..][0..4], 0);
        }
    }
    process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result;
    @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
}

pub fn executeVectorSpecial(self: *ElfState, d: __process_DecodedInsn) bool {
    if (process_impl_legacy_vector_ops.executePackedCompare(self, d)) return true;
    switch (d.op) {
        .vptest, .vtestps, .vtestpd => executeVectorTest(self, d),
        .vextractf128, .vinsertf128, .vinserti128 => executeVexLane128(self, d),
        .vperm2f128 => executeVexPermute2x128(self, d),
        .vphminposuw => executeVphminposuw(self, d),
        .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8, .vpinsrd, .vpinsrq, .vpinsrw => process_impl_legacy_vector_ops.executeInsertElement(self, d, regVal, readMemVal),
        .vpextrb, .vpextrw, .vpextrd, .vpextrq => executeVexExtractElement(self, d),
        .vinsertps => executeVinsertps(self, d),
        else => return false,
    }
    return true;
}

pub fn executeVectorRouted(self: *ElfState, d: __process_DecodedInsn) bool {
    if (d.is_evex or d.op == .movdir64b or evexHandles(d.op)) {
        // The EVEX register write clears everything above the operand,
        // which is the VEX rule. Legacy SSE forms routed here (PSHUFD,
        // SHUFPS/SHUFPD) must leave the destination's upper YMM lane as
        // it was, and a legacy instruction never changes it otherwise.
        const preserved_upper: ?[16]u8 = if (d.legacy_sse and !d.is_evex) process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] else null;
        __process_evex.execute(self, d);
        if (preserved_upper) |upper| process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = upper;
        advanceAfterHandled(self, d);
        return true;
    }

    // Keep vector moves and VEX.128 upper-lane clearing outside the
    // arithmetic router. These operations have architectural state
    // effects that a generic CLEO arithmetic call cannot express.
    if (executeCleoVectorMove(self, d)) {
        advanceAfterHandled(self, d);
        return true;
    }
    if (d.op == .vzeroupper) {
        for (&process_impl_lifecycle.guestContextField(self, "ymm_hi").*) |*upper| @memset(upper, 0);
        advanceAfterHandled(self, d);
        return true;
    }
    if (executeSharedVex(self, d)) {
        advanceAfterHandled(self, d);
        return true;
    }
    if (executeVectorSpecial(self, d)) {
        advanceAfterHandled(self, d);
        return true;
    }
    if (tryExecuteCleo(self, d)) {
        advanceAfterHandled(self, d);
        return true;
    }
    if (isVectorOperationRuntime(d.op) and !isLegacyVectorTransfer(d.op)) {
        process_impl_instruction_decode.terminateUnimplemented(self, d);
        return true;
    }
    return false;
}

pub fn opBitsetFrom(comptime predicate: fn (__process_Op) bool) __state_OpBitset {
    @setEvalBranchQuota(200_000);
    var bits: __state_OpBitset = @splat(0);
    for (@typeInfo(__process_Op).@"enum".fields) |field| {
        const op: __process_Op = @enumFromInt(field.value);
        if (predicate(op)) bits[field.value / 64] |= @as(u64, 1) << @intCast(field.value % 64);
    }
    return bits;
}

pub inline fn opBitsetHas(comptime bits: *const __state_OpBitset, op: __process_Op) bool {
    const index: usize = @intFromEnum(op);
    return (bits[index / 64] >> @intCast(index % 64)) & 1 != 0;
}

pub fn vectorOperationByName(op: __process_Op) bool {
    const name = @tagName(op);
    return (name.len != 0 and name[0] == 'v') or op == .pmovmskb;
}

pub fn isVectorOperationRuntime(op: __process_Op) bool {
    return opBitsetHas(&__state_vector_operation_bits, op);
}

pub fn evexHandles(op: __process_Op) bool {
    return opBitsetHas(&__state_evex_handled_bits, op);
}

pub fn isLegacyVectorTransfer(op: __process_Op) bool {
    return switch (op) {
        .vmovd_xmm_reg32,
        .vmovd_xmm_mem32,
        .vmovd_reg32_xmm,
        .vmovd_mem32_xmm,
        .vmovq_xmm_reg64,
        .vmovq_xmm_mem64,
        .vmovq_reg64_xmm,
        .vmovq_mem64_xmm,
        .vmovq_xmm_xmm,
        => true,
        else => false,
    };
}

pub fn cleoVectorFromSource(self: *ElfState, d: __process_DecodedInsn, index: u8, memory: bool, comptime bits: usize) __process_cleo_routing.wide.Wide(bits) {
    var result = __process_cleo_routing.wide.Wide(bits).zero();
    const low = if (memory) readMem128(self, d.addr) else process_impl_lifecycle.guestContextField(self, "xmm").*[index];
    @memcpy(result.bytes[0..16], low[0..]);
    if (comptime bits == 256) {
        const high = if (memory) readMem128(self, d.addr +% 16) else process_impl_lifecycle.guestContextField(self, "ymm_hi").*[index];
        @memcpy(result.bytes[16..32], high[0..]);
    }
    return result;
}

pub fn writeCleoVector(self: *ElfState, d: __process_DecodedInsn, comptime bits: usize, value: __process_cleo_routing.wide.Wide(bits)) void {
    @memcpy(process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..], value.bytes[0..16]);
    if (comptime bits == 256) {
        @memcpy(process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst][0..], value.bytes[16..32]);
    } else if (!d.legacy_sse) {
        // VEX.128 is a zeroing form. Legacy SSE leaves the architectural
        // upper YMM half untouched, which is why the decoder carries the
        // explicit legacy_sse bit.
        @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
    }
}

pub fn cleoIsFma(operation: __process_cleo_routing.types.Operation) bool {
    return switch (operation) {
        .fma_ps,
        .fma_pd,
        .fms_ps,
        .fms_pd,
        .fnma_ps,
        .fnma_pd,
        .fnms_ps,
        .fnms_pd,
        .fma_addsub_ps,
        .fma_addsub_pd,
        .fma_subadd_ps,
        .fma_subadd_pd,
        => true,
        else => false,
    };
}

pub fn cleoIsUnary(operation: __process_cleo_routing.types.Operation) bool {
    return switch (operation) {
        .sqrt_ps,
        .sqrt_pd,
        .cvt_pd2ps,
        .cvt_ps2pd,
        .cvt_dq2ps,
        .cvt_ps2dq,
        .cvtt_ps2dq,
        .pabs,
        .pnot,
        .compress_ps,
        .compress_pd,
        .expand_ps,
        .expand_pd,
        .cvt_pd2dq,
        .cvtt_pd2dq,
        .cvt_dq2pd,
        .cvt_ph2ps,
        .cvt_ps2ph,
        .cvt_bf16,
        => true,
        else => false,
    };
}

pub fn cleoIsImmediate(operation: __process_cleo_routing.types.Operation) bool {
    return switch (operation) {
        .cmp_ps,
        .cmp_pd,
        .blend_ps,
        .blend_pd,
        .shuf_ps,
        .shuf_pd,
        .dpps,
        .range_ps,
        .range_pd,
        .fixup_ps,
        .fixup_pd,
        .permil,
        .byte_shift_left,
        .byte_shift_right,
        .insert_block,
        .insert_element,
        .insert_ps,
        .rotate_left,
        .rotate_right,
        .ternary_logic,
        .gf2p8_affine,
        .gf2p8_affine_inv,
        .sha1_rnds4,
        => true,
        else => false,
    };
}

pub fn cleoIsBinary(operation: __process_cleo_routing.types.Operation) bool {
    return switch (operation) {
        .add_ps,
        .add_pd,
        .sub_ps,
        .sub_pd,
        .mul_ps,
        .mul_pd,
        .div_ps,
        .div_pd,
        .addsub_ps,
        .addsub_pd,
        .or_ps,
        .or_pd,
        .xor_ps,
        .xor_pd,
        .and_ps,
        .and_pd,
        .andn_ps,
        .andn_pd,
        .cmp_ps,
        .cmp_pd,
        .pmin_signed,
        .pmin_unsigned,
        .pmax_signed,
        .pmax_unsigned,
        .padd,
        .psub,
        .pcmpeq,
        .pcmpgt,
        .pmull,
        .psubs,
        .psubus,
        .psll,
        .psra,
        .psrl,
        .psign,
        .unpck_low,
        .unpck_high,
        .avg,
        .rotate_left_variable,
        .rotate_right_variable,
        .gf2p8_mul,
        .sha1_msg1,
        .sha1_msg2,
        .sha1_nexte,
        .sha256_msg1,
        .sha256_msg2,
        .sha256_rnds2,
        .scale_ps,
        .scale_pd,
        .permute_d,
        .permute_q,
        => true,
        else => false,
    };
}

pub fn executeCleoAtWidth(self: *ElfState, d: __process_DecodedInsn, meta: __process_cleo_routing.types.InstructionMeta, features: __process_cleo_routing.types.FeatureSet, comptime bits: usize) ?__process_cleo_routing.wide.Wide(bits) {
    if (cleoIsUnary(meta.operation)) {
        const source_is_memory = !d.is_reg_form;
        const source_index = if (d.legacy_sse) d.xmm_src2 else d.xmm_src;
        const source = cleoVectorFromSource(self, d, source_index, source_is_memory, bits);
        return __process_cleo_routing.ops.executeUnary(bits, meta, source, features) catch null;
    }

    const source1_index = if (d.legacy_sse) d.xmm_dst else d.xmm_src;
    const source1 = cleoVectorFromSource(self, d, source1_index, false, bits);
    const source2 = cleoVectorFromSource(self, d, d.xmm_src2, !d.is_reg_form, bits);

    if (cleoIsFma(meta.operation)) {
        const op_name = @tagName(d.op);
        const has_132 = __process_std.mem.indexOf(u8, op_name, "132") != null;
        const has_213 = __process_std.mem.indexOf(u8, op_name, "213") != null;
        const destination = cleoVectorFromSource(self, d, d.xmm_dst, false, bits);

        // VEX FMA operand roles are encoded by the mnemonic suffix:
        //   132: dst = (dst * src2) + src1
        //   213: dst = (src1 * dst) + src2
        //   231: dst = (src1 * src2) + dst
        // `source1` is VEX.vvvv and `source2` is ModRM.r/m here.  Keep
        // the role mapping explicit because the operations are not
        // commutative once subtraction/negation is involved.
        const accum = if (has_132) source1 else if (has_213) source2 else destination;
        const lhs = if (has_132) destination else source1;
        const rhs = if (has_213) destination else source2;
        return __process_cleo_routing.ops.executeAccumulate(bits, meta, accum, lhs, rhs, features) catch null;
    }

    if (d.uses_imm and cleoIsImmediate(meta.operation)) {
        return __process_cleo_routing.ops.executeBinaryImmediate(bits, meta, source1, source2, @truncate(d.imm), features) catch null;
    }
    if (cleoIsBinary(meta.operation)) {
        return __process_cleo_routing.ops.executeBinary(bits, meta, source1, source2, features) catch null;
    }
    return null;
}

pub fn executeCleoVectorMove(self: *ElfState, d: __process_DecodedInsn) bool {
    switch (d.op) {
        .vmovntps, .vmovntdq => {
            // A non-temporal store bypasses the ordinary temporal queue.
            // Publish earlier queued stores first; this is stronger than
            // x86's weak NT ordering but preserves a safe, explicit tier
            // boundary on the ARM host.
            writeMem128NonTemporal(self, d.addr, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src]);
            if (d.vector_256) writeMem128NonTemporal(self, d.addr +% 16, process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src]);
            return true;
        },
        .vpsadbw => {
            // Each quadword becomes the sum of |a - b| over its eight
            // unsigned bytes, as a word, with the rest of it zero.
            const lanes: usize = if (d.vector_256) 2 else 1;
            var result = [_]u8{0} ** 32;
            for (0..lanes) |lane| {
                const lhs = if (lane == 0) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src] else process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src];
                const rhs = if (!d.is_reg_form)
                    readMem128(self, d.addr +% lane * 16)
                else if (lane == 0)
                    process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2]
                else
                    process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src2];
                for (0..2) |quad| {
                    var sum: u16 = 0;
                    for (0..8) |index| {
                        const a: u16 = lhs[quad * 8 + index];
                        const b: u16 = rhs[quad * 8 + index];
                        sum += if (a > b) a - b else b - a;
                    }
                    __process_std.mem.writeInt(u16, result[lane * 16 + quad * 8 ..][0..2], sum, .little);
                }
            }
            @memcpy(&process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst], result[0..16]);
            if (!d.legacy_sse) @memcpy(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], result[16..32]);
            return true;
        },
        .vmovntdqa => {
            const low = readMem128(self, d.addr);
            process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = if (d.vector_256) readMem128(self, d.addr +% 16) else [_]u8{0} ** 16;
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = low;
            return true;
        },
        .vcvtdq2pd => {
            // Two dwords become two doubles (VEX.128); four, from an XMM
            // or m128 source, become four (VEX.256).
            const count: usize = if (d.vector_256) 4 else 2;
            var result = [_]u8{0} ** 32;
            for (0..count) |index| {
                const dword: u32 = if (d.is_reg_form)
                    __process_std.mem.readInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][index * 4 ..][0..4], .little)
                else
                    @truncate(readMemVal(self, d.addr +% index * 4, .bits32));
                const value: f64 = @floatFromInt(@as(i32, @bitCast(dword)));
                __process_std.mem.writeInt(u64, result[index * 8 ..][0..8], @bitCast(value), .little);
            }
            @memcpy(&process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst], result[0..16]);
            @memcpy(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], result[16..32]);
            return true;
        },
        .vcvttpd2dq => {
            const count: usize = if (d.vector_256) 4 else 2;
            var result = [_]u8{0} ** 16;
            for (0..count) |index| {
                const bits: u64 = if (!d.is_reg_form)
                    readMemVal(self, d.addr +% index * 8, .bits64)
                else if (index < 2)
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][index * 8 ..][0..8], .little)
                else
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src][(index - 2) * 8 ..][0..8], .little);
                const value: f64 = @bitCast(bits);
                const dword: i32 = if (__process_std.math.isNan(value) or value >= 0x1p31 or value < -0x1p31)
                    __process_std.math.minInt(i32)
                else
                    @intFromFloat(@trunc(value));
                __process_std.mem.writeInt(u32, result[index * 4 ..][0..4], @bitCast(dword), .little);
            }
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result;
            @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovss_xmm_xmm_xmm, .vmovsd_xmm_xmm_xmm => {
            // Low element from xmm_src2, the rest of the lane from
            // VEX.vvvv, upper YMM lane cleared. Both sources are read
            // before the store because the destination may be either.
            var merged = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            const width: usize = if (d.op == .vmovss_xmm_xmm_xmm) 4 else 8;
            @memcpy(merged[0..width], process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2][0..width]);
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = merged;
            @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovss_xmm_mem => {
            // MOVSS/VEX.MOVSS from memory clears the rest of XMM.  A
            // legacy SSE form leaves the architectural YMM upper half
            // alone, while VEX.128 also clears that upper half.
            @memset(&process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst], 0);
            __process_std.mem.writeInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..4], @truncate(readMemVal(self, d.addr, .bits32)), .little);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovsd_xmm_mem => {
            // The scalar double-precision memory form has the same
            // upper-lane rule, with an eight-byte low element.
            @memset(&process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst], 0);
            __process_std.mem.writeInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..8], readMemVal(self, d.addr, .bits64), .little);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovss_mem_xmm => {
            writeMemVal(self, d.addr, .bits32, __process_std.mem.readInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..4], .little));
            return true;
        },
        .vmovsd_mem_xmm => {
            writeMemVal(self, d.addr, .bits64, __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..8], .little));
            return true;
        },
        .vmovss_xmm_xmm => {
            const source = __process_std.mem.readInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..4], .little);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst], 0);
            __process_std.mem.writeInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..4], source, .little);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovsd_xmm_xmm => {
            const source = __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..8], .little);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst], 0);
            __process_std.mem.writeInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..8], source, .little);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovq_xmm_xmm => {
            var result = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            @memset(result[8..16], 0);
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result;
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovlps_xmm_xmm_mem64, .vmovlpd_xmm_xmm_mem64 => {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            __process_std.mem.writeInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..8], readMemVal(self, d.addr, .bits64), .little);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovlps_mem64_xmm, .vmovlpd_mem64_xmm => {
            writeMemVal(self, d.addr, .bits64, __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..8], .little));
            return true;
        },
        .vmovhps_xmm_xmm_mem64, .vmovhpd_xmm_xmm_mem64 => {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            __process_std.mem.writeInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][8..16], readMemVal(self, d.addr, .bits64), .little);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovhps_mem64_xmm, .vmovhpd_mem64_xmm => {
            writeMemVal(self, d.addr, .bits64, __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][8..16], .little));
            return true;
        },
        .vmovhlps => {
            if (d.legacy_sse) {
                // Legacy MOVHLPS is a two-operand merge: the source's
                // high quadword replaces the destination's low one and
                // the destination high quadword is preserved.
                @memcpy(process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..8], process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][8..16]);
            } else {
                // VEX VMOVHLPS is three-source.  The low quadword comes
                // from the high half of SRC2 (ModR/M.r/m), while the
                // high quadword comes from the high half of SRC1
                // (VEX.vvvv). Snapshot both sources before writing DST.
                const source1 = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
                const source2 = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2];
                var result = source1;
                @memcpy(result[0..8], source2[8..16]);
                process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result;
            }
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovlhps => {
            if (d.legacy_sse) {
                // Legacy MOVLHPS preserves the destination low quadword
                // and takes the source low quadword for the high half.
                @memcpy(process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][8..16], process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..8]);
            } else {
                // VEX VMOVLHPS takes the low half from SRC1
                // (VEX.vvvv) and the low half of SRC2 for the high half.
                const source1 = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
                const source2 = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2];
                var result = source1;
                @memcpy(result[8..16], source2[0..8]);
                process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result;
            }
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            return true;
        },
        .vmovddup => {
            process_impl_legacy_vector_ops.executeMovddup(self, d, readMemVal);
            return true;
        },
        else => {},
    }

    const is_load = switch (d.op) {
        .vmovdqu_xmm_mem,
        .vmovdqa_xmm_mem,
        .vmovups_xmm_mem,
        .vmovaps_xmm_mem,
        .vmovupd_xmm_mem,
        .vmovapd_xmm_mem,
        .vmovdqu_ymm_mem,
        .vmovdqa_ymm_mem,
        .vmovups_ymm_mem,
        .vmovaps_ymm_mem,
        .vmovupd_ymm_mem,
        .vmovapd_ymm_mem,
        => true,
        else => false,
    };
    const is_store = switch (d.op) {
        .vmovdqu_mem_xmm,
        .vmovdqa_mem_xmm,
        .vmovups_mem_xmm,
        .vmovaps_mem_xmm,
        .vmovupd_mem_xmm,
        .vmovapd_mem_xmm,
        .vmovdqu_mem_ymm,
        .vmovdqa_mem_ymm,
        .vmovups_mem_ymm,
        .vmovaps_mem_ymm,
        .vmovupd_mem_ymm,
        .vmovapd_mem_ymm,
        => true,
        else => false,
    };
    const is_register = switch (d.op) {
        .vmovdqu_xmm_xmm,
        .vmovdqa_xmm_xmm,
        .vmovups_xmm_xmm,
        .vmovaps_xmm_xmm,
        .vmovupd_xmm_xmm,
        .vmovapd_xmm_xmm,
        .vmovdqu_ymm_ymm,
        .vmovdqa_ymm_ymm,
        .vmovups_ymm_ymm,
        .vmovaps_ymm_ymm,
        .vmovupd_ymm_ymm,
        .vmovapd_ymm_ymm,
        => true,
        else => false,
    };
    if (!is_load and !is_store and !is_register) return false;

    if (is_load) {
        process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = readMem128(self, d.addr);
        if (d.vector_256) {
            process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = readMem128(self, d.addr +% 16);
        } else if (!d.legacy_sse) {
            @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
        }
    } else if (is_store) {
        writeMem128(self, d.addr, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src]);
        if (d.vector_256) writeMem128(self, d.addr +% 16, process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src]);
    } else {
        process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
        if (d.vector_256) process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src] else @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
    }
    return true;
}

pub fn tryExecuteCleo(self: *ElfState, d: __process_DecodedInsn) bool {
    // CLEO is an SIMD/VEX/EVEX fallback. Scalar instructions can never
    // route to its registry, so keep them out of this hot path. Legacy
    // scalar-vector move tags are handled by the explicit executor.
    if (!isVectorOperationRuntime(d.op)) return false;
    // The router matches the mnemonic against its registry by string.
    // Its answer depends only on the op and the operand width (the
    // feature set is a constant of this host), so it is asked once per
    // (op, width) and remembered.
    const route = __process_cleoRouteFor(d.op, d.vector_256, self.parallel_guest_execution);
    const meta = route.meta orelse return false;
    if (!route.can_route) return false;
    if (!cleoIsFma(meta.operation) and !cleoIsUnary(meta.operation) and
        !(d.uses_imm and cleoIsImmediate(meta.operation)) and !cleoIsBinary(meta.operation)) return false;

    if (d.vector_256) {
        if (executeCleoAtWidth(self, d, meta, route.features, 256)) |result| {
            writeCleoVector(self, d, 256, result);
            return true;
        }
    } else if (executeCleoAtWidth(self, d, meta, route.features, 128)) |result| {
        writeCleoVector(self, d, 128, result);
        return true;
    }
    return false;
}

pub fn vexArithmeticForOp(op: __process_Op) __process_vector_helpers.VexArithmetic {
    return switch (op) {
        .vaddss, .vaddsd, .vaddps, .vaddpd => .add,
        .vmulss, .vmulsd, .vmulps, .vmulpd => .multiply,
        .vsubss, .vsubsd, .vsubps, .vsubpd => .subtract,
        .vdivss, .vdivsd, .vdivps, .vdivpd => .divide,
        .vminss, .vminsd, .vminps, .vminpd => .minimum,
        .vmaxss, .vmaxsd, .vmaxps, .vmaxpd => .maximum,
        else => unreachable,
    };
}

pub fn vexBitwiseForOp(op: __process_Op) __process_vector_helpers.VexBitwise {
    return switch (op) {
        .vandps, .vandpd, .vpand => .@"and",
        .vandnps, .vandnpd, .vpandn => .and_not,
        .vorps, .vorpd, .vpor => .@"or",
        .vxorps, .vxorpd, .vpxor => .xor,
        else => unreachable,
    };
}

pub fn executeVexShufflePd(self: *ElfState, d: __process_DecodedInsn) void {
    // A control bit picks an element within a source, never a source:
    // element 0 is SRC1[bit 0], element 1 is SRC2[bit 1], and the upper
    // lane repeats that with bits 2 and 3. Treating the bit as the source
    // made libstdc++'s mt19937_64 twist and its u64-to-double conversion
    // wrong, and with them every std::uniform_real_distribution.
    const source1_low = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
    const source2_low = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2] else readMem128(self, d.addr);
    const result_low = __process_shufflePackedDoublesLane(source1_low, source2_low, @truncate(d.imm));

    if (d.vector_256) {
        const source1_high = process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src];
        const source2_high = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src2] else readMem128(self, d.addr +% 16);
        process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = __process_shufflePackedDoublesLane(source1_high, source2_high, @truncate(d.imm >> 2));
        process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result_low;
    } else {
        process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result_low;
        // All VEX.128 instructions zero the destination register's YMM
        // upper half, unlike legacy SSE encodings.
        if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
    }
}

pub fn executeSharedVex(self: *ElfState, d: __process_DecodedInsn) bool {
    switch (d.op) {
        .vcvtsi2ss_xmm_reg, .vcvtsi2ss_xmm_mem => {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            const integer: i64 = if (d.size == .bits64)
                @bitCast(if (d.op == .vcvtsi2ss_xmm_reg) regVal(self, d.src_reg, .bits64) else readMemVal(self, d.addr, .bits64))
            else
                @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2ss_xmm_reg) regVal(self, d.src_reg, .bits32) else readMemVal(self, d.addr, .bits32)))));
            __process_std.mem.writeInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..4], @bitCast(@as(f32, @floatFromInt(integer))), .little);
            return true;
        },
        .vcvtsi2sd_xmm_reg, .vcvtsi2sd_xmm_mem => {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            const integer: i64 = if (d.size == .bits64)
                @bitCast(if (d.op == .vcvtsi2sd_xmm_reg) regVal(self, d.src_reg, .bits64) else readMemVal(self, d.addr, .bits64))
            else
                @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2sd_xmm_reg) regVal(self, d.src_reg, .bits32) else readMemVal(self, d.addr, .bits32)))));
            __process_std.mem.writeInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..8], @bitCast(@as(f64, @floatFromInt(integer))), .little);
            return true;
        },
        .vcvtss2sd => {
            const source_bits: u32 = if (d.is_reg_form)
                __process_std.mem.readInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2][0..4], .little)
            else
                @truncate(readMemVal(self, d.addr, .bits32));
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            const converted: f64 = @floatCast(@as(f32, @bitCast(source_bits)));
            __process_std.mem.writeInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..8], @bitCast(converted), .little);
            return true;
        },
        .vcvtsd2ss => {
            const source_bits: u64 = if (d.is_reg_form)
                __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2][0..8], .little)
            else
                readMemVal(self, d.addr, .bits64);
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            const converted: f32 = @floatCast(@as(f64, @bitCast(source_bits)));
            __process_std.mem.writeInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..4], @bitCast(converted), .little);
            return true;
        },
        .vcvtps2pd => {
            __process_vector_helpers.executeVexConvertFloatPacked(self, d, .single_to_double);
            return true;
        },
        .vcvtpd2ps => {
            __process_vector_helpers.executeVexConvertFloatPacked(self, d, .double_to_single);
            return true;
        },
        .vaddss, .vmulss, .vsubss, .vdivss, .vminss, .vmaxss => {
            __process_vector_helpers.executeVexScalarF32(self, d, vexArithmeticForOp(d.op));
            return true;
        },
        .vaddsd, .vmulsd, .vsubsd, .vdivsd, .vminsd, .vmaxsd => {
            __process_vector_helpers.executeVexScalarF64(self, d, vexArithmeticForOp(d.op));
            return true;
        },
        .vaddps, .vmulps, .vsubps, .vdivps, .vminps, .vmaxps => {
            __process_vector_helpers.executeVexPackedF32(self, d, vexArithmeticForOp(d.op));
            return true;
        },
        .vaddpd, .vmulpd, .vsubpd, .vdivpd, .vminpd, .vmaxpd => {
            __process_vector_helpers.executeVexPackedF64(self, d, vexArithmeticForOp(d.op));
            return true;
        },
        .vpacksswb, .vpackuswb, .vpackssdw, .vpackusdw => {
            const operation: __process_vector_helpers.PackedPackOperation = switch (d.op) {
                .vpacksswb => .signed_words_to_bytes,
                .vpackuswb => .unsigned_words_to_bytes,
                .vpackssdw => .signed_dwords_to_words,
                .vpackusdw => .unsigned_dwords_to_words,
                else => unreachable,
            };
            __process_vector_helpers.executeVexPackedPack(self, d, operation);
            return true;
        },
        .vsqrtss => {
            __process_vector_helpers.executeVexSqrtScalarF32(self, d);
            return true;
        },
        .vsqrtsd => {
            __process_vector_helpers.executeVexSqrtScalarF64(self, d);
            return true;
        },
        .vsqrtps => {
            __process_vector_helpers.executeVexSqrtPackedF32(self, d);
            return true;
        },
        .vsqrtpd => {
            __process_vector_helpers.executeVexSqrtPackedF64(self, d);
            return true;
        },
        .vcmpps => {
            if (!__process_vector_helpers.executeVexComparePacked(self, d, false)) process_impl_instruction_decode.terminateUnimplemented(self, d);
            return true;
        },
        .vcmppd => {
            if (!__process_vector_helpers.executeVexComparePacked(self, d, true)) process_impl_instruction_decode.terminateUnimplemented(self, d);
            return true;
        },
        .vcmpss => {
            if (!__process_vector_helpers.executeVexCompareScalar(self, d, false)) process_impl_instruction_decode.terminateUnimplemented(self, d);
            return true;
        },
        .vcmpsd => {
            if (!__process_vector_helpers.executeVexCompareScalar(self, d, true)) process_impl_instruction_decode.terminateUnimplemented(self, d);
            return true;
        },
        .vshufpd => {
            executeVexShufflePd(self, d);
            return true;
        },
        .vunpcklps, .vunpckhps, .vunpcklpd, .vunpckhpd => {
            __process_vector_helpers.executeVexPackedUnpack(self, d);
            return true;
        },
        .vrcpps => {
            __process_vector_helpers.executeVexReciprocalPacked(self, d, false);
            return true;
        },
        .vrsqrtps => {
            __process_vector_helpers.executeVexReciprocalPacked(self, d, true);
            return true;
        },
        .vrcpss => {
            __process_vector_helpers.executeVexReciprocalScalar(self, d, false);
            return true;
        },
        .vrsqrtss => {
            __process_vector_helpers.executeVexReciprocalScalar(self, d, true);
            return true;
        },
        .vcvtdq2ps => {
            __process_vector_helpers.executeVexConvertPacked(self, d, .dword_to_float);
            return true;
        },
        .vcvtps2dq => {
            __process_vector_helpers.executeVexConvertPacked(self, d, .float_to_dword_round);
            return true;
        },
        .vcvttps2dq => {
            __process_vector_helpers.executeVexConvertPacked(self, d, .float_to_dword_truncate);
            return true;
        },
        .vucomiss => {
            const lhs: f32 = @bitCast(__process_std.mem.readInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..4], .little));
            const rhs_bits: u32 = if (d.is_reg_form)
                __process_std.mem.readInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2][0..4], .little)
            else
                @truncate(readMemVal(self, d.addr, .bits32));
            __process_vector_helpers.setVexComparisonFlags(self, lhs, @as(f32, @bitCast(rhs_bits)));
            return true;
        },
        .vucomisd => {
            const lhs: f64 = @bitCast(__process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..8], .little));
            const rhs_bits: u64 = if (d.is_reg_form)
                __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2][0..8], .little)
            else
                readMemVal(self, d.addr, .bits64);
            __process_vector_helpers.setVexComparisonFlags(self, lhs, @as(f64, @bitCast(rhs_bits)));
            return true;
        },
        .vandps, .vandpd, .vandnps, .vandnpd, .vorps, .vorpd, .vxorps, .vxorpd, .vpor, .vpand, .vpandn, .vpxor => {
            __process_vector_helpers.executeVexBitwise(self, d, vexBitwiseForOp(d.op));
            return true;
        },
        .vroundss => {
            __process_vector_helpers.executeVexRoundScalarF32(self, d);
            return true;
        },
        .vroundsd => {
            __process_vector_helpers.executeVexRoundScalarF64(self, d);
            return true;
        },
        .vroundps => {
            __process_vector_helpers.executeVexRoundPackedF32(self, d);
            return true;
        },
        .vroundpd => {
            __process_vector_helpers.executeVexRoundPackedF64(self, d);
            return true;
        },
        .vcvttss2si => {
            __process_vector_helpers.executeVexFloatToSigned(self, d, false, true);
            return true;
        },
        .vcvtss2si => {
            __process_vector_helpers.executeVexFloatToSigned(self, d, false, false);
            return true;
        },
        .vcvttsd2si => {
            __process_vector_helpers.executeVexFloatToSigned(self, d, true, true);
            return true;
        },
        .vcvtsd2si => {
            __process_vector_helpers.executeVexFloatToSigned(self, d, true, false);
            return true;
        },
        .pmovmskb, .vpmovmskb, .vpmovmskb_ymm, .vmovmskps, .vmovmskpd => {
            __process_vector_helpers.executeVexMoveMask(self, d);
            return true;
        },
        .vpmuludq => {
            __process_vector_helpers.executeVexMultiplyUnsignedEvenDwords(self, d);
            return true;
        },
        .vpblendw => {
            __process_vector_helpers.executeVexBlendWords(self, d);
            return true;
        },
        .vblendvps => {
            __process_vector_helpers.executeVexBlendVariable(self, d, 32);
            return true;
        },
        .vblendvpd => {
            __process_vector_helpers.executeVexBlendVariable(self, d, 64);
            return true;
        },
        .vpblendvb => {
            __process_vector_helpers.executeVexBlendVariable(self, d, 8);
            return true;
        },
        .vpsllw => {
            __process_vector_helpers.executeVexPackedShift(self, d, 16, true, false, false);
            return true;
        },
        .vpsrlw => {
            __process_vector_helpers.executeVexPackedShift(self, d, 16, false, false, false);
            return true;
        },
        .vpsraw => {
            __process_vector_helpers.executeVexPackedShift(self, d, 16, false, true, false);
            return true;
        },
        .vpslld => {
            __process_vector_helpers.executeVexPackedShift(self, d, 32, true, false, false);
            return true;
        },
        .vpsrld => {
            __process_vector_helpers.executeVexPackedShift(self, d, 32, false, false, false);
            return true;
        },
        .vpsrad => {
            __process_vector_helpers.executeVexPackedShift(self, d, 32, false, true, false);
            return true;
        },
        .vpsllq => {
            __process_vector_helpers.executeVexPackedShift(self, d, 64, true, false, false);
            return true;
        },
        .vpsrlq => {
            __process_vector_helpers.executeVexPackedShift(self, d, 64, false, false, false);
            return true;
        },
        .vpslldq => {
            __process_vector_helpers.executeVexPackedShift(self, d, 8, true, false, true);
            return true;
        },
        .vpsrldq => {
            __process_vector_helpers.executeVexPackedShift(self, d, 8, false, false, true);
            return true;
        },
        .vpmullw => {
            __process_vector_helpers.executeVexPackedInteger(self, d, 16, .mul_low);
            return true;
        },
        .vpmulld_38 => {
            __process_vector_helpers.executeVexPackedInteger(self, d, 32, .mul_low);
            return true;
        },
        .vpmulhw => {
            __process_vector_helpers.executeVexPackedMulHigh(self, d, true);
            return true;
        },
        .vpmulhuw => {
            __process_vector_helpers.executeVexPackedMulHigh(self, d, false);
            return true;
        },
        // Decoded but refused as unimplemented, or not decoded at all,
        // before the Xenia JIT corpus test named them.
        .vpaddsb => {
            __process_vector_helpers.executeVexPackedInteger(self, d, 8, .add_signed_saturate);
            return true;
        },
        .vpaddsw => {
            __process_vector_helpers.executeVexPackedInteger(self, d, 16, .add_signed_saturate);
            return true;
        },
        .vpaddusb => {
            __process_vector_helpers.executeVexPackedInteger(self, d, 8, .add_unsigned_saturate);
            return true;
        },
        .vpaddusw => {
            __process_vector_helpers.executeVexPackedInteger(self, d, 16, .add_unsigned_saturate);
            return true;
        },
        .vpsubusb => {
            __process_vector_helpers.executeVexPackedInteger(self, d, 8, .sub_unsigned_saturate);
            return true;
        },
        .vpavgb => {
            __process_vector_helpers.executeVexPackedInteger(self, d, 8, .average_unsigned);
            return true;
        },
        .vpavgw => {
            __process_vector_helpers.executeVexPackedInteger(self, d, 16, .average_unsigned);
            return true;
        },
        .vpminsw => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 16, .signed = true, .take_max = false });
            return true;
        },
        .vpmaxsw => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 16, .signed = true, .take_max = true });
            return true;
        },
        .vpminsb => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 8, .signed = true, .take_max = false });
            return true;
        },
        .vpminsd => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 32, .signed = true, .take_max = false });
            return true;
        },
        .vpminuw => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 16, .signed = false, .take_max = false });
            return true;
        },
        .vpminud => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 32, .signed = false, .take_max = false });
            return true;
        },
        .vpminub => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 8, .signed = false, .take_max = false });
            return true;
        },
        .vpmaxsb => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 8, .signed = true, .take_max = true });
            return true;
        },
        .vpmaxsd => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 32, .signed = true, .take_max = true });
            return true;
        },
        .vpmaxuw => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 16, .signed = false, .take_max = true });
            return true;
        },
        .vpmaxud => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 32, .signed = false, .take_max = true });
            return true;
        },
        .vpmaxub => {
            __process_vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 8, .signed = false, .take_max = true });
            return true;
        },
        else => return false,
    }
}

pub fn executeHighwayRegisterBinary(self: *ElfState, d: __process_DecodedInsn, op: __process_x64_decoder.highway.BinaryOp) void {
    const width: __process_x64_decoder.highway.Width = switch (d.size) {
        .bits8 => .bits8,
        .bits16 => .bits16,
        .bits32 => .bits32,
        .bits64 => .bits64,
    };
    const lhs = decodedRegVal(self, d.dst_reg, d.dst_high8, d.size);
    const rhs = decodedRegVal(self, d.src_reg, d.src_high8, d.size);
    const evaluated = __process_x64_decoder.highway.evaluate(op, width, lhs, rhs, process_impl_lifecycle.guestContextField(self, "regs").*.rflags);
    if (__process_shouldTraceRip(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip)) {
        __process_log.info("trace highway binary rip=0x{x} op={s} size={s} lhs=0x{x} rhs=0x{x} input_flags=0x{x} output_flags=0x{x} writeback={}", .{
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            @tagName(op),
            @tagName(width),
            lhs,
            rhs,
            process_impl_lifecycle.guestContextField(self, "regs").*.rflags,
            evaluated.rflags,
            evaluated.writeback,
        });
    }
    process_impl_lifecycle.guestContextField(self, "regs").*.rflags = evaluated.rflags;
    if (evaluated.writeback) setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, evaluated.value);
}

pub fn terminateForMemoryAccess(self: *ElfState, d: __process_DecodedInsn, check: __process_x64_decoder.highway.MemoryCheck) void {
    process_impl_lifecycle.markFaulted(self);
    process_impl_lifecycle.markTerminated(self);
    self.exit_code = 127;
    self.termination_reason = .memory_access_violation;
    const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
    var instruction_storage: [16]u8 = undefined;
    const instruction_bytes = process_impl_instruction_decode.guestInstructionBytes(self, regs.rip, &instruction_storage);
    const live_decode = __process_decodeInsn(instruction_bytes);
    var backing_bytes: []const u8 = &.{};
    if (process_impl_guest_memory.addrToOffset(self, regs.rip)) |offset| {
        if (offset < self.mem.len) {
            backing_bytes = self.mem[offset..][0..@min(self.mem.len - offset, 16)];
        }
    }
    const backing_decode = __process_decodeInsn(backing_bytes);
    __process_log.err(
        "PE64 memory access violation: rip=0x{x} executed_op={s} live_decode={s}/{d} live_bytes={any} backing_decode={s}/{d} backing_bytes={any} pending_stores={d} effective=0x{x} width={d} access={s} fault={s} d(addr=0x{x} imm=0x{x} size={s} reg_form={} dst={s} src={s}) guest_range=[0x{x},0x{x})",
        .{
            regs.rip,
            @tagName(d.op),
            @tagName(live_decode.op),
            live_decode.len,
            instruction_bytes,
            @tagName(backing_decode.op),
            backing_decode.len,
            backing_bytes,
            __process_tso_memory.activePendingStores(),
            check.address,
            check.bytes,
            @tagName(check.access),
            if (check.fault) |fault| @tagName(fault) else "none",
            d.addr,
            d.imm,
            @tagName(d.size),
            d.is_reg_form,
            @tagName(d.dst_reg),
            @tagName(d.src_reg),
            self.mem_base,
            self.mem_base +| self.mem.len,
        },
    );
    __process_log.err(
        "PE64 memory access context: thread=0x{x} slot={?d} last(rip=0x{x} op={s}/{d}) regs(rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rbp=0x{x} rsp=0x{x} r8=0x{x} r9=0x{x} r10=0x{x} r11=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x}) return=0x{x} parallel={} jit={}",
        .{
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*,
            process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
            @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
            process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
            regs.rax,
            regs.rbx,
            regs.rcx,
            regs.rdx,
            regs.rsi,
            regs.rdi,
            regs.rbp,
            regs.rsp,
            regs.r8,
            regs.r9,
            regs.r10,
            regs.r11,
            regs.r12,
            regs.r13,
            regs.r14,
            regs.r15,
            process_impl_guest_memory.read64(self, regs.rsp),
            self.parallel_guest_execution,
            self.block_jit_enabled and !self.block_jit_unavailable,
        },
    );
}

pub fn validateGuestMemoryRange(
    self: *const ElfState,
    address: u64,
    width: __process_x64_decoder.highway.Width,
    access: __process_x64_decoder.highway.MemoryAccess,
    permitted: bool,
) __process_x64_decoder.highway.MemoryCheck {
    const bytes: u8 = width.bits() / 8;
    if (process_impl_guest_memory.windowsGuestRangeContains(self, address, bytes)) {
        return .{
            .address = address,
            .bytes = bytes,
            .access = access,
            .fault = if (permitted) null else .permission_denied,
        };
    }
    return __process_x64_decoder.highway.validateRange(self.mem_base, self.mem.len, address, width, access, permitted);
}

pub fn executeHighwayMemoryBinary(
    self: *ElfState,
    d: __process_DecodedInsn,
    op: __process_x64_decoder.highway.BinaryOp,
    direction: __process_x64_decoder.highway.MemoryDirection,
) void {
    const width: __process_x64_decoder.highway.Width = switch (d.size) {
        .bits8 => .bits8,
        .bits16 => .bits16,
        .bits32 => .bits32,
        .bits64 => .bits64,
    };
    const access: __process_x64_decoder.highway.MemoryAccess = if (direction == .register_to_memory and op != .cmp and op != .test_bits) .write else .read;
    const check = validateGuestMemoryRange(self, d.addr, width, access, true);
    if (!check.allowed()) {
        terminateForMemoryAccess(self, d, check);
        return;
    }
    const reg = if (direction == .memory_to_register) d.dst_reg else d.src_reg;
    const high8 = if (direction == .memory_to_register) d.dst_high8 else d.src_high8;
    if (d.lock and direction == .register_to_memory) {
        const update_op: ?__process_tso_memory.UpdateOp = switch (op) {
            .add => .add,
            .adc => .adc,
            .sub => .sub,
            .sbb => .sbb,
            .bit_and => .bit_and,
            .bit_or => .bit_or,
            .bit_xor => .bit_xor,
            else => null,
        };
        if (update_op) |atomic_op| {
            const source = decodedRegVal(self, reg, high8, d.size);
            const carry_in = process_impl_lifecycle.guestContextField(self, "regs").*.rflags & __process_RFL_CF != 0;
            if (atomicMemoryUpdate(self, d.addr, d.size, atomic_op, source, carry_in)) |atomic_result| {
                const evaluated = __process_x64_decoder.highway.evaluateMemory(
                    op,
                    width,
                    source,
                    atomic_result.previous,
                    direction,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rflags,
                );
                process_impl_lifecycle.guestContextField(self, "regs").*.rflags = evaluated.rflags;
                return;
            }
        }
    }
    const evaluated = __process_x64_decoder.highway.evaluateMemory(op, width, decodedRegVal(self, reg, high8, d.size), readMemVal(self, d.addr, d.size), direction, process_impl_lifecycle.guestContextField(self, "regs").*.rflags);
    process_impl_lifecycle.guestContextField(self, "regs").*.rflags = evaluated.rflags;
    if (evaluated.write_register) setDecodedReg(self, reg, high8, d.size, evaluated.value);
    if (evaluated.write_memory) writeMemVal(self, d.addr, d.size, evaluated.value);
}

pub fn executeHighwayImmediate(self: *ElfState, d: __process_DecodedInsn, op: __process_x64_decoder.highway.BinaryOp, memory: bool, immediate: u64) void {
    const width: __process_x64_decoder.highway.Width = switch (d.size) {
        .bits8 => .bits8,
        .bits16 => .bits16,
        .bits32 => .bits32,
        .bits64 => .bits64,
    };
    if (memory) {
        const access: __process_x64_decoder.highway.MemoryAccess = if (op == .cmp or op == .test_bits) .read else .write;
        const check = validateGuestMemoryRange(self, d.addr, width, access, true);
        if (!check.allowed()) {
            terminateForMemoryAccess(self, d, check);
            return;
        }
    }
    if (memory and d.lock) {
        const update_op: ?__process_tso_memory.UpdateOp = switch (op) {
            .add => .add,
            .adc => .adc,
            .sub => .sub,
            .sbb => .sbb,
            .bit_and => .bit_and,
            .bit_or => .bit_or,
            .bit_xor => .bit_xor,
            else => null,
        };
        if (update_op) |atomic_op| {
            const carry_in = process_impl_lifecycle.guestContextField(self, "regs").*.rflags & __process_RFL_CF != 0;
            if (atomicMemoryUpdate(self, d.addr, d.size, atomic_op, immediate, carry_in)) |atomic_result| {
                const evaluated = __process_x64_decoder.highway.evaluate(
                    op,
                    width,
                    atomic_result.previous,
                    immediate,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rflags,
                );
                process_impl_lifecycle.guestContextField(self, "regs").*.rflags = evaluated.rflags;
                return;
            }
        }
    }
    const lhs = if (memory) readMemVal(self, d.addr, d.size) else decodedRegVal(self, d.dst_reg, d.dst_high8, d.size);
    const evaluated = __process_x64_decoder.highway.evaluate(op, width, lhs, immediate, process_impl_lifecycle.guestContextField(self, "regs").*.rflags);
    process_impl_lifecycle.guestContextField(self, "regs").*.rflags = evaluated.rflags;
    if (evaluated.writeback) {
        if (memory) writeMemVal(self, d.addr, d.size, evaluated.value) else setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, evaluated.value);
    }
}

pub fn executeAccumulatorImmediate(self: *ElfState, d: __process_DecodedInsn) void {
    const op: __process_x64_decoder.highway.BinaryOp = switch (d.op) {
        .add_accum_imm => .add,
        .or_accum_imm => .bit_or,
        .adc_accum_imm => .adc,
        .sbb_accum_imm => .sbb,
        .and_accum_imm => .bit_and,
        .sub_accum_imm => .sub,
        .xor_accum_imm => .bit_xor,
        .cmp_accum_imm => .cmp,
        else => unreachable,
    };
    executeHighwayImmediate(self, d, op, false, __process_testImmForSize(d.imm, d.size));
}

pub fn isAccumulatorImmediate(op: __process_Op) bool {
    return switch (op) {
        .add_accum_imm,
        .or_accum_imm,
        .adc_accum_imm,
        .sbb_accum_imm,
        .and_accum_imm,
        .sub_accum_imm,
        .xor_accum_imm,
        .cmp_accum_imm,
        => true,
        else => false,
    };
}

pub fn setFlag(self: *ElfState, flag: u32, enabled: bool) void {
    if (enabled) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= flag;
    } else {
        process_impl_lifecycle.guestContextField(self, "regs").*.rflags &= ~flag;
    }
}

pub fn executeBitTestRegister(
    self: *ElfState,
    d: __process_DecodedInsn,
    operation: __process_x64_decoder.BitTestOperation,
    immediate_index: bool,
) void {
    const value = regVal(self, d.dst_reg, d.size);
    const raw_index = if (immediate_index) d.imm else regVal(self, d.src_reg, d.size);
    const result = __process_x64_decoder.bitTestRegister(d.size, value, raw_index, operation);
    setFlag(self, __process_RFL_CF, result.carry);
    if (operation != .probe) setReg(self, d.dst_reg, d.size, result.value);
}

pub fn executeBitTestMemory(
    self: *ElfState,
    d: __process_DecodedInsn,
    operation: __process_x64_decoder.BitTestOperation,
    immediate_index: bool,
) void {
    const operand = if (immediate_index)
        __process_x64_decoder.bitTestMemoryOperandImmediate(d.size, d.addr, d.imm)
    else
        __process_x64_decoder.bitTestMemoryOperand(d.size, d.addr, regVal(self, d.src_reg, d.size));
    const resolved = operand orelse {
        process_impl_lifecycle.markFaulted(self);
        process_impl_lifecycle.markTerminated(self);
        self.exit_code = 127;
        self.termination_reason = .memory_access_violation;
        __process_log.err("PE64 bit-test memory operand overflow: rip=0x{x} op={s} address=0x{x} size={s} index=0x{x}", .{
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            @tagName(d.op),
            d.addr,
            @tagName(d.size),
            if (immediate_index) d.imm else regVal(self, d.src_reg, d.size),
        });
        return;
    };
    if (d.lock and operation != .probe) {
        const bit_mask = @as(u64, 1) << resolved.bit_index;
        const update_op: __process_tso_memory.UpdateOp = switch (operation) {
            .set => .bit_set,
            .reset => .bit_reset,
            .complement => .bit_complement,
            .probe => unreachable,
        };
        if (atomicMemoryUpdate(self, resolved.address, d.size, update_op, bit_mask, false)) |atomic_result| {
            setFlag(self, __process_RFL_CF, atomic_result.previous & bit_mask != 0);
            return;
        }
    }
    const value = readMemVal(self, resolved.address, d.size);
    const result = __process_x64_decoder.bitTestRegister(d.size, value, resolved.bit_index, operation);
    setFlag(self, __process_RFL_CF, result.carry);
    if (operation != .probe) writeMemVal(self, resolved.address, d.size, result.value);
}

pub fn bitWidth(size: __process_Size) u7 {
    return switch (size) {
        .bits8 => 8,
        .bits16 => 16,
        .bits32 => 32,
        .bits64 => 64,
    };
}

pub fn maskForSize(size: __process_Size) u64 {
    return switch (size) {
        .bits8 => 0xFF,
        .bits16 => 0xFFFF,
        .bits32 => 0xFFFF_FFFF,
        .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
    };
}

pub fn signBitForSize(size: __process_Size) u64 {
    return switch (size) {
        .bits8 => 0x80,
        .bits16 => 0x8000,
        .bits32 => 0x8000_0000,
        .bits64 => 0x8000_0000_0000_0000,
    };
}

pub fn signedInteger(value: u64, size: __process_Size) i128 {
    return switch (size) {
        .bits8 => @as(i128, @as(i8, @bitCast(@as(u8, @truncate(value))))),
        .bits16 => @as(i128, @as(i16, @bitCast(@as(u16, @truncate(value))))),
        .bits32 => @as(i128, @as(i32, @bitCast(@as(u32, @truncate(value))))),
        .bits64 => @as(i128, @as(i64, @bitCast(value))),
    };
}

pub fn imulImmediateSize(op: __process_Op) __process_Size {
    return switch (op) {
        .imul_reg16_mem16_imm8,
        .imul_reg16_reg16_imm8,
        .imul_reg16_mem16_imm16,
        .imul_reg16_reg16_imm16,
        => .bits16,
        .imul_reg32_mem32_imm8,
        .imul_reg32_reg32_imm8,
        .imul_reg32_mem32_imm32,
        .imul_reg32_reg32_imm32,
        => .bits32,
        .imul_reg64_mem64_imm8,
        .imul_reg64_reg64_imm8,
        .imul_reg64_mem64_imm32,
        .imul_reg64_reg64_imm32,
        => .bits64,
        else => unreachable,
    };
}

pub fn signedImulImmediate(instruction: __process_DecodedInsn) i128 {
    return switch (instruction.op) {
        .imul_reg16_mem16_imm8,
        .imul_reg16_reg16_imm8,
        .imul_reg32_mem32_imm8,
        .imul_reg32_reg32_imm8,
        .imul_reg64_mem64_imm8,
        .imul_reg64_reg64_imm8,
        => @as(i128, @as(i8, @bitCast(@as(u8, @truncate(instruction.imm))))),
        .imul_reg16_mem16_imm16,
        .imul_reg16_reg16_imm16,
        => @as(i128, @as(i16, @bitCast(@as(u16, @truncate(instruction.imm))))),
        .imul_reg32_mem32_imm32,
        .imul_reg32_reg32_imm32,
        .imul_reg64_mem64_imm32,
        .imul_reg64_reg64_imm32,
        => @as(i128, @as(i32, @bitCast(@as(u32, @truncate(instruction.imm))))),
        else => unreachable,
    };
}

pub fn writeImulNarrowResult(self: *ElfState, destination: __process_RegId, size: __process_Size, product: i128) void {
    const product_bits: u128 = @bitCast(product);
    const result: u64 = @truncate(product_bits);
    setReg(self, destination, size, result);

    // Two- and three-operand IMUL retain only the destination width. CF
    // and OF report whether the full signed product cannot be represented
    // by that width; the remaining arithmetic flags are unaffected.
    const overflow = product != signedInteger(result, size);
    setFlag(self, __process_RFL_CF, overflow);
    setFlag(self, __process_RFL_OF, overflow);
}

pub fn shlCount(self: *ElfState, size: __process_Size) u6 {
    const mask: u64 = if (size == .bits64) 0x3F else 0x1F;
    return @as(u6, @intCast(regVal(self, .cl_cx_ecx_rcx, .bits8) & mask));
}

pub fn shlValue(self: *ElfState, input: u64, size: __process_Size, count: u6) u64 {
    _ = self;
    const mask = maskForSize(size);
    const result = (input & mask) << count;
    return result & mask;
}

pub fn setFlagsShl(self: *ElfState, input: u64, result: u64, size: __process_Size, count: u6) void {
    if (count == 0) return;

    const width = bitWidth(size);
    const mask = maskForSize(size);
    const masked_input = input & mask;
    const masked_result = result & mask;

    if (count <= width) {
        const shift: u6 = @intCast(width - count);
        setFlag(self, __process_RFL_CF, ((masked_input >> shift) & 1) != 0);
    } else {
        setFlag(self, __process_RFL_CF, false);
    }

    if (count == 1) {
        const sign = signBitForSize(size);
        const msb_set = (masked_result & sign) != 0;
        const cf_set = (process_impl_lifecycle.guestContextField(self, "regs").*.rflags & __process_RFL_CF) != 0;
        setFlag(self, __process_RFL_OF, msb_set != cf_set);
    }

    setFlag(self, __process_RFL_SF, (masked_result & signBitForSize(size)) != 0);
    setFlag(self, __process_RFL_ZF, masked_result == 0);
}

pub fn immShiftCount(imm: u64, size: __process_Size) u6 {
    const mask: u64 = if (size == .bits64) 0x3F else 0x1F;
    return @as(u6, @intCast(imm & mask));
}

pub fn executeRotate(self: *ElfState, d: __process_DecodedInsn) void {
    const is_mem = switch (d.op) {
        .rol_mem_cl, .ror_mem_cl, .rol_mem_imm, .ror_mem_imm => true,
        else => false,
    };
    const rotate_left = switch (d.op) {
        .rol_reg_cl, .rol_mem_cl, .rol_reg_imm, .rol_mem_imm => true,
        else => false,
    };
    const uses_cl = switch (d.op) {
        .rol_reg_cl, .rol_mem_cl, .ror_reg_cl, .ror_mem_cl => true,
        else => false,
    };
    const raw_count = if (uses_cl) regVal(self, .cl_cx_ecx_rcx, .bits8) else d.imm;
    const width: u64 = bitWidth(d.size);
    const count: u6 = @intCast((raw_count & @as(u64, if (d.size == .bits64) 0x3F else 0x1F)) % width);
    if (count == 0) return;
    const mask = maskForSize(d.size);
    const old = (if (is_mem) readMemVal(self, d.addr, d.size) else decodedRegVal(self, d.dst_reg, d.dst_high8, d.size)) & mask;
    const inverse: u6 = @intCast(width - count);
    const result = if (rotate_left) ((old << count) | (old >> inverse)) & mask else ((old >> count) | (old << inverse)) & mask;
    if (is_mem) writeMemVal(self, d.addr, d.size, result) else setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, result);
    if (rotate_left) {
        const carry = (result & 1) != 0;
        setFlag(self, __process_RFL_CF, carry);
        if (count == 1) setFlag(self, __process_RFL_OF, ((result & signBitForSize(d.size)) != 0) != carry);
    } else {
        const carry = (result & signBitForSize(d.size)) != 0;
        setFlag(self, __process_RFL_CF, carry);
        if (count == 1) setFlag(self, __process_RFL_OF, carry != ((result & (signBitForSize(d.size) >> 1)) != 0));
    }
}

pub fn shrValue(self: *ElfState, input: u64, size: __process_Size, count: u6) u64 {
    _ = self;
    const mask = maskForSize(size);
    return (input & mask) >> count;
}

pub fn setFlagsShr(self: *ElfState, input: u64, result: u64, size: __process_Size, count: u6) void {
    if (count == 0) return;

    const masked_input = input & maskForSize(size);
    const masked_result = result & maskForSize(size);
    const shifted_out: u6 = @intCast(count - 1);
    setFlag(self, __process_RFL_CF, ((masked_input >> shifted_out) & 1) != 0);

    if (count == 1) {
        setFlag(self, __process_RFL_OF, (masked_input & signBitForSize(size)) != 0);
    }

    setFlag(self, __process_RFL_SF, (masked_result & signBitForSize(size)) != 0);
    setFlag(self, __process_RFL_ZF, masked_result == 0);
}

pub fn sarValue(self: *ElfState, input: u64, size: __process_Size, count: u6) u64 {
    _ = self;
    if (count == 0) return input & maskForSize(size);
    const sign_set = (input & signBitForSize(size)) != 0;
    if (count >= bitWidth(size)) return if (sign_set) maskForSize(size) else 0;
    return switch (size) {
        .bits8 => @as(u64, @as(u8, @bitCast(@as(i8, @bitCast(@as(u8, @truncate(input)))) >> @as(u3, @intCast(count))))),
        .bits16 => @as(u64, @as(u16, @bitCast(@as(i16, @bitCast(@as(u16, @truncate(input)))) >> @as(u4, @intCast(count))))),
        .bits32 => @as(u64, @as(u32, @bitCast(@as(i32, @bitCast(@as(u32, @truncate(input)))) >> @as(u5, @intCast(count))))),
        .bits64 => @as(u64, @bitCast(@as(i64, @bitCast(input)) >> count)),
    };
}

pub fn setFlagsSar(self: *ElfState, input: u64, result: u64, size: __process_Size, count: u6) void {
    if (count == 0) return;

    const masked_input = input & maskForSize(size);
    const masked_result = result & maskForSize(size);
    if (count <= bitWidth(size)) {
        const shifted_out: u6 = @intCast(count - 1);
        setFlag(self, __process_RFL_CF, ((masked_input >> shifted_out) & 1) != 0);
    }

    if (count == 1) setFlag(self, __process_RFL_OF, false);

    setFlag(self, __process_RFL_SF, (masked_result & signBitForSize(size)) != 0);
    setFlag(self, __process_RFL_ZF, masked_result == 0);
}

pub fn evalCond(rflags: u32, cond: __process_Cond) bool {
    return __process_x64_decoder.evalCond(rflags, cond);
}

pub fn executeBitScan(self: *ElfState, d: __process_DecodedInsn) void {
    const is_memory = switch (d.op) {
        .bsf_reg_mem, .bsr_reg_mem, .tzcnt_reg_mem, .lzcnt_reg_mem => true,
        else => false,
    };
    const kind: __process_BitScanKind = switch (d.op) {
        .bsf_reg_reg, .bsf_reg_mem => .bsf,
        .bsr_reg_reg, .bsr_reg_mem => .bsr,
        .tzcnt_reg_reg, .tzcnt_reg_mem => .tzcnt,
        .lzcnt_reg_reg, .lzcnt_reg_mem => .lzcnt,
        else => unreachable,
    };
    const source = if (is_memory) readMemVal(self, d.addr, d.size) else regVal(self, d.src_reg, d.size);
    const result = __process_x64_decoder.bitScan(d.size, kind, source);

    if (result.write_destination) setReg(self, d.dst_reg, d.size, result.value);
    setFlag(self, __process_RFL_ZF, result.zero_flag);
    if (result.carry_flag) |carry| setFlag(self, __process_RFL_CF, carry);
}

pub fn stringAddress(self: *const ElfState, index: __process_RegId, address_size: __process_Size, segment: __process_x64_decoder.Segment) u64 {
    return __process_x64_decoder.resolveMemoryAddress(&process_impl_lifecycle.guestContextField(self, "regs").*, .{
        .has_base = true,
        .base_reg = index,
        .segment = segment,
    }, 0, address_size, .long64, true);
}

pub fn executeStringOperation(self: *ElfState, d: __process_DecodedInsn) void {
    const address_size: __process_Size = if (d.has_0x67) .bits32 else .bits64;
    const stride: u64 = switch (d.size) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32 => 4,
        .bits64 => 8,
    };
    const backwards = (process_impl_lifecycle.guestContextField(self, "regs").*.rflags & __process_RFL_DF) != 0;
    const repeated = d.repeat != .none;
    var remaining: u64 = if (repeated)
        regVal(self, .cl_cx_ecx_rcx, address_size)
    else
        1;

    if (remaining == 0) return;

    while (remaining != 0) {
        switch (d.op) {
            .movs => {
                const source_address = stringAddress(self, .dh_si_esi_rsi, address_size, d.segment);
                const destination_address = stringAddress(self, .bh_di_edi_rdi, address_size, .es);
                const value = readMemVal(self, source_address, d.size);
                writeMemVal(self, destination_address, d.size, value);
                const next_source = if (backwards)
                    regVal(self, .dh_si_esi_rsi, address_size) -% stride
                else
                    regVal(self, .dh_si_esi_rsi, address_size) +% stride;
                const next_destination = if (backwards)
                    regVal(self, .bh_di_edi_rdi, address_size) -% stride
                else
                    regVal(self, .bh_di_edi_rdi, address_size) +% stride;
                setReg(self, .dh_si_esi_rsi, address_size, next_source);
                setReg(self, .bh_di_edi_rdi, address_size, next_destination);
            },
            .cmps => {
                const source_address = stringAddress(self, .dh_si_esi_rsi, address_size, d.segment);
                const destination_address = stringAddress(self, .bh_di_edi_rdi, address_size, .es);
                const source = readMemVal(self, source_address, d.size);
                const destination = readMemVal(self, destination_address, d.size);
                const result = source -% destination;
                setFlagsSub(self, source, destination, result, d.size);
                const next_source = if (backwards)
                    regVal(self, .dh_si_esi_rsi, address_size) -% stride
                else
                    regVal(self, .dh_si_esi_rsi, address_size) +% stride;
                const next_destination = if (backwards)
                    regVal(self, .bh_di_edi_rdi, address_size) -% stride
                else
                    regVal(self, .bh_di_edi_rdi, address_size) +% stride;
                setReg(self, .dh_si_esi_rsi, address_size, next_source);
                setReg(self, .bh_di_edi_rdi, address_size, next_destination);
            },
            .stos => {
                const destination_address = stringAddress(self, .bh_di_edi_rdi, address_size, .es);
                writeMemVal(self, destination_address, d.size, regVal(self, .al_ax_eax_rax, d.size));
                const next_destination = if (backwards)
                    regVal(self, .bh_di_edi_rdi, address_size) -% stride
                else
                    regVal(self, .bh_di_edi_rdi, address_size) +% stride;
                setReg(self, .bh_di_edi_rdi, address_size, next_destination);
            },
            .lods => {
                const source_address = stringAddress(self, .dh_si_esi_rsi, address_size, d.segment);
                setReg(self, .al_ax_eax_rax, d.size, readMemVal(self, source_address, d.size));
                const next_source = if (backwards)
                    regVal(self, .dh_si_esi_rsi, address_size) -% stride
                else
                    regVal(self, .dh_si_esi_rsi, address_size) +% stride;
                setReg(self, .dh_si_esi_rsi, address_size, next_source);
            },
            .scas => {
                const destination_address = stringAddress(self, .bh_di_edi_rdi, address_size, .es);
                const accumulator = regVal(self, .al_ax_eax_rax, d.size);
                const destination = readMemVal(self, destination_address, d.size);
                const result = accumulator -% destination;
                setFlagsSub(self, accumulator, destination, result, d.size);
                const next_destination = if (backwards)
                    regVal(self, .bh_di_edi_rdi, address_size) -% stride
                else
                    regVal(self, .bh_di_edi_rdi, address_size) +% stride;
                setReg(self, .bh_di_edi_rdi, address_size, next_destination);
            },
            else => unreachable,
        }

        if (!repeated) break;
        remaining -%= 1;
        setReg(self, .cl_cx_ecx_rcx, address_size, remaining);
        if ((d.op == .cmps or d.op == .scas) and remaining != 0) {
            const equal = (process_impl_lifecycle.guestContextField(self, "regs").*.rflags & __process_RFL_ZF) != 0;
            const continue_repeating = switch (d.repeat) {
                .rep => equal,
                .repne => !equal,
                .none => false,
            };
            if (!continue_repeating) break;
        }
    }
}

pub fn advanceAfterHandled(self: *ElfState, d: __process_DecodedInsn) void {
    if (!process_impl_lifecycle.isTerminated(self)) process_impl_lifecycle.guestContextField(self, "regs").*.rip += d.len;
}

pub fn discoverXeniaRijndaelTarget(self: *const ElfState) ?u64 {
    const image_begin = self.image_low -| self.mem_base;
    const image_end = @min(self.image_high -| self.mem_base, @as(u64, @intCast(self.mem.len)));
    if (image_begin >= image_end) return null;
    const begin: usize = @intCast(image_begin);
    const end: usize = @intCast(image_end);
    const signature = [_]u8{
        0x41, 0x57, 0x41, 0x56, 0x41, 0x55, 0x41, 0x54,
        0x56, 0x57, 0x55, 0x53, 0x48, 0x83, 0xEC, 0x38,
        0x4C, 0x89, 0x4C, 0x24, 0x20,
    };
    var offset = begin;
    while (offset + signature.len <= end) : (offset += 1) {
        if (!__process_std.mem.eql(u8, self.mem[offset .. offset + signature.len], &signature)) continue;
        // rijndaelEncrypt and rijndaelDecrypt share the entry prologue
        // and the initial block setup. Their first table load is the
        // stable discriminator: encryption loads Te1 through r13, while
        // decryption loads Td0 through r11. Ignore the RIP-relative
        // displacement that follows the opcode so a rebuilt PE remains
        // discoverable when its section layout changes.
        if (offset + 70 > end) continue;
        if (self.mem[offset + 67] != 0x4C or
            self.mem[offset + 68] != 0x8D or
            self.mem[offset + 69] != 0x1D)
        {
            continue;
        }
        return self.mem_base + offset;
    }
    return null;
}

pub fn discoverXeniaSha1Target(self: *const ElfState) ?u64 {
    const image_begin = self.image_low -| self.mem_base;
    const image_end = @min(self.image_high -| self.mem_base, @as(u64, @intCast(self.mem.len)));
    if (image_begin >= image_end) return null;
    const begin: usize = @intCast(image_begin);
    const end: usize = @intCast(image_end);

    // MinGW's TinySHA1 build has a stable entry prologue. The RIP
    // displacement of the byte-shuffle mask is intentionally excluded so
    // rebuilt Xenia binaries remain discoverable.
    const signature = [_]u8{
        0x41, 0x56, 0x56, 0x57, 0x55, 0x53,
        0x48, 0x81, 0xec, 0x40, 0x01, 0x00,
        0x00, 0xc5, 0xfa, 0x6f, 0x41, 0x1c,
    };
    var offset = begin;
    while (offset + signature.len <= end) : (offset += 1) {
        if (!__process_std.mem.eql(u8, self.mem[offset .. offset + signature.len], &signature)) continue;
        // The next instruction loads the byte-shuffle mask with vmovdqa;
        // this secondary check avoids treating an unrelated AVX function
        // with the same register-save prologue as SHA1.
        if (offset + 25 > end or
            self.mem[offset + 18] != 0xc5 or
            self.mem[offset + 19] != 0xf9 or
            self.mem[offset + 20] != 0x6f or
            self.mem[offset + 21] != 0x0d)
        {
            continue;
        }
        return self.mem_base + offset;
    }
    return null;
}

pub fn discoverXeniaTabulateTarget(self: *const ElfState) ?u64 {
    const image_begin = self.image_low -| self.mem_base;
    const image_end = @min(self.image_high -| self.mem_base, @as(u64, @intCast(self.mem.len)));
    if (image_begin >= image_end) return null;
    const begin: usize = @intCast(image_begin);
    const end: usize = @intCast(image_end);

    // tabulate::Table::str() in the MinGW Xenia build begins with the
    // saved-register/0x1b0-byte stack frame below. The symbol lookup is
    // preferred, but this exact entry signature keeps rebuilt capsules
    // discoverable without matching ordinary string helpers.
    const signature = [_]u8{
        0x56, 0x57, 0x53, 0x48, 0x81, 0xec, 0xb0, 0x01,
        0x00, 0x00, 0x48, 0x89, 0xd7, 0x48, 0x89, 0xce,
        0x48, 0x8d, 0x4c, 0x24, 0x28,
    };
    var offset = begin;
    while (offset + signature.len <= end) : (offset += 1) {
        if (!__process_std.mem.eql(u8, self.mem[offset .. offset + signature.len], &signature)) continue;
        // The first body call constructs a stringstream at rsp+0x28;
        // require the following relative-call opcode to avoid a generic
        // register-save false positive.
        if (offset + 25 > end or self.mem[offset + 21] != 0xe8) continue;
        return self.mem_base + offset;
    }
    return null;
}

pub fn resolveXeniaRijndaelTarget(self: *ElfState) void {
    if (self.xenia_rijndael_target_checked) return;
    self.xenia_rijndael_target_checked = true;
    self.xenia_rijndael_target = process_impl_kernel_services.localSymbolAddress(self, "_Z15rijndaelDecryptPKjiPKhPh") orelse
        process_impl_kernel_services.localSymbolAddress(self, "__Z15rijndaelDecryptPKjiPKhPh") orelse
        process_impl_kernel_services.localSymbolAddress(self, "rijndaelDecrypt") orelse
        discoverXeniaRijndaelTarget(self);
    if (self.xenia_rijndael_target) |resolved| {
        __process_log.info("PE64 Xenia Rijndael accelerator armed: target=0x{x} entry-signature-gated=true", .{resolved});
    } else {
        __process_log.warn("PE64 Xenia Rijndael accelerator requested but the rijndaelDecrypt symbol and entry signature were not found; execution remains guest-interpreted", .{});
    }
    noteXeniaAcceleratorTargetResolved(self);
}

pub fn tryXeniaRijndaelAccelerator(self: *ElfState, target: u64, return_rip: u64) bool {
    if (!self.xenia_rijndael_accelerator_enabled or !self.windows_runtime_enabled) return false;
    resolveXeniaRijndaelTarget(self);

    if (self.xenia_rijndael_target == null or self.xenia_rijndael_target.? != target) return false;
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer {
        if (runtime_guard) |*guard| guard.unlock();
    }

    if (!__process_xenia_accelerator.tryRijndaelDecrypt(self, process_impl_lifecycle.guestContextField(self, "regs").*.rcx, process_impl_lifecycle.guestContextField(self, "regs").*.rdx, process_impl_lifecycle.guestContextField(self, "regs").*.r8, process_impl_lifecycle.guestContextField(self, "regs").*.r9)) {
        self.xenia_rijndael_accelerator_failures +|= 1;
        if (self.xenia_rijndael_accelerator_failures == 1) {
            __process_log.warn("PE64 Xenia Rijndael accelerator declined a block: target=0x{x} rk=0x{x} nr={d} ciphertext=0x{x} plaintext=0x{x} step={d}; falling back to the guest implementation", .{
                target,
                process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
                process_impl_lifecycle.guestContextField(self, "regs").*.r8,
                process_impl_lifecycle.guestContextField(self, "regs").*.r9,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
        return false;
    }

    noteGuestCall(self, .direct, target, return_rip);
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = return_rip;
    noteGuestReturn(self, return_rip);
    self.xenia_rijndael_accelerated_calls +|= 1;
    if (self.xenia_rijndael_accelerated_calls == 1) {
        __process_log.info("PE64 Xenia Rijndael accelerator active: first 16-byte block completed at step={d} nr={d}", .{
            process_impl_lifecycle.observedExecutionSteps(self),
            process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
        });
    }
    return true;
}

pub fn resolveXeniaSha1Target(self: *ElfState) void {
    if (self.xenia_sha1_target_checked) return;
    self.xenia_sha1_target_checked = true;
    self.xenia_sha1_target = process_impl_kernel_services.localSymbolAddress(self, "_ZN4sha14SHA112processBlockEv") orelse
        process_impl_kernel_services.localSymbolAddress(self, "__ZN4sha14SHA112processBlockEv") orelse
        process_impl_kernel_services.localSymbolAddress(self, "sha1::SHA1::processBlock") orelse
        discoverXeniaSha1Target(self);
    if (self.xenia_sha1_target) |resolved| {
        __process_log.info("PE64 Xenia SHA1 accelerator armed: target=0x{x} entry-signature-gated=true", .{resolved});
    } else {
        __process_log.warn("PE64 Xenia SHA1 accelerator requested but SHA1::processBlock was not found; execution remains guest-interpreted", .{});
    }
    noteXeniaAcceleratorTargetResolved(self);
}

pub fn tryXeniaSha1Accelerator(self: *ElfState, target: u64, return_rip: u64) bool {
    if (!self.xenia_sha1_accelerator_enabled or !self.windows_runtime_enabled) return false;
    resolveXeniaSha1Target(self);

    if (self.xenia_sha1_target == null or self.xenia_sha1_target.? != target) return false;
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer {
        if (runtime_guard) |*guard| guard.unlock();
    }

    if (!__process_xenia_accelerator.trySha1ProcessBlock(self, process_impl_lifecycle.guestContextField(self, "regs").*.rcx)) {
        self.xenia_sha1_accelerator_failures +|= 1;
        if (self.xenia_sha1_accelerator_failures == 1) {
            __process_log.warn("PE64 Xenia SHA1 accelerator declined a block: target=0x{x} this=0x{x} step={d}; falling back to guest implementation", .{
                target,
                process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
        return false;
    }

    noteGuestCall(self, .direct, target, return_rip);
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = return_rip;
    noteGuestReturn(self, return_rip);
    self.xenia_sha1_accelerated_blocks +|= 1;
    if (self.xenia_sha1_accelerated_blocks == 1) {
        __process_log.info("PE64 Xenia SHA1 accelerator active: first 64-byte block completed at step={d}", .{process_impl_lifecycle.observedExecutionSteps(self)});
    }
    tryXeniaSha1FeedLoop(self, return_rip);
    return true;
}

pub fn tryXeniaSha1FeedLoop(self: *ElfState, return_rip: u64) void {
    if (!self.xenia_sha1_feed_enabled) return;
    // `jmp rel8` back to the loop's increment head.
    const tail = guestMemoryConst(self, return_rip, 2) orelse return;
    if (tail[0] != 0xEB) return;
    const back: i8 = @bitCast(tail[1]);
    if (back >= 0) return;
    const head = @as(u64, @bitCast(@as(i64, @bitCast(return_rip + 2)) + back));

    // inc %r15 ; cmp %r15,%rbx ; je rel32 ; ... ; movzbl (%r14,%r15,1),%eax
    const loop = guestMemoryConst(self, head, 17) orelse return;
    const precompile = __process_std.mem.eql(u8, loop[0..6], &[_]u8{ 0x49, 0xFF, 0xC7, 0x4C, 0x39, 0xFB }) and
        __process_std.mem.eql(u8, loop[6..8], &[_]u8{ 0x0F, 0x84 }) and
        __process_std.mem.eql(u8, loop[12..17], &[_]u8{ 0x43, 0x0F, 0xB6, 0x04, 0x3E });
    // XeCryptShaUpdate's compiler-inlined feed uses RBX as source and
    // R12 as limit, not Precompile's R14/RBX. Match its *whole* body,
    // including stack offsets and branch targets; a prefix alone cannot
    // prove that the skipped instructions only update this SHA1 object.
    const kernel_loop = guestMemoryConst(self, head, __process_xenia_sha1_kernel_feed_body.len + 4);
    const kernel_feed = !precompile and return_rip == head + __process_xenia_sha1_kernel_feed_body.len + 4 and
        (if (kernel_loop) |body| __process_std.mem.eql(u8, body[0..__process_xenia_sha1_kernel_feed_body.len], &__process_xenia_sha1_kernel_feed_body) else false);
    if (!precompile and !kernel_feed) return;
    if (kernel_feed) {
        const body = kernel_loop.?;
        const rel = __process_std.mem.readInt(i32, body[__process_xenia_sha1_kernel_feed_body.len..][0..4], .little);
        const call_target = return_rip +% @as(u64, @bitCast(@as(i64, rel)));
        if (self.xenia_sha1_target == null or call_target != self.xenia_sha1_target.?) return;
        // In this shape RDI is the stack object (digest +8, block +1C,
        // index +60, count +68). Prove that identity as well as RCX.
        if (process_impl_lifecycle.guestContextField(self, "regs").*.rdi != process_impl_lifecycle.guestContextField(self, "regs").*.rsp +| 0x20) return;
    }

    // The call site loaded the SHA1 object from `rdi`; if `rcx` no longer
    // agrees this is not the shape that was matched.
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rcx != process_impl_lifecycle.guestContextField(self, "regs").*.rdi) return;

    const cursor = process_impl_lifecycle.guestContextField(self, "regs").*.r15;
    const limit = if (kernel_feed) process_impl_lifecycle.guestContextField(self, "regs").*.r12 else process_impl_lifecycle.guestContextField(self, "regs").*.rbx;
    const base = if (kernel_feed) process_impl_lifecycle.guestContextField(self, "regs").*.rbx else process_impl_lifecycle.guestContextField(self, "regs").*.r14;
    if (limit <= cursor) return;
    // Leave the last two iterations to the guest: one feeds the final
    // byte, the next takes the branch out.
    const remaining = limit - cursor;
    if (remaining < __process_XENIA_SHA1_FEED_MINIMUM) return;
    // Bound one native turn so a large title hash cannot prevent event
    // pumping or other cooperative workers from getting a scheduling turn.
    const consume = @min(remaining - 2, 256 * 1024);
    const start = __process_std.math.add(u64, base, cursor + 1) catch return;

    if (!__process_xenia_accelerator.sha1ProcessBytes(self, process_impl_lifecycle.guestContextField(self, "regs").*.rdi, start, consume)) {
        self.xenia_sha1_feed_declines +|= 1;
        return;
    }
    process_impl_lifecycle.guestContextField(self, "regs").*.r15 = cursor + consume;
    self.xenia_sha1_feed_spans +|= 1;
    self.xenia_sha1_feed_bytes +|= consume;
    if (kernel_feed) {
        self.xenia_sha1_kernel_feed_spans +|= 1;
        self.xenia_sha1_kernel_feed_bytes +|= consume;
        if (self.xenia_sha1_kernel_feed_spans == 1) {
            __process_log.info("PE64 Xenia kernel SHA1 feed accelerator active: consumed={d} loop_head=0x{x} bounded_turn_bytes=262144 computation=unchanged continuation=guest_owned", .{ consume, head });
        }
    }
    if (self.xenia_sha1_feed_spans == 1) {
        __process_log.info("PE64 Xenia SHA1 feed accelerator active: consumed {d} byte(s) in one step at step={d} loop_head=0x{x}; the interpreted form of this loop costs about eleven instructions per byte", .{
            consume,
            process_impl_lifecycle.observedExecutionSteps(self),
            head,
        });
    }
}

pub fn resolveXeniaTabulateTarget(self: *ElfState) void {
    if (self.xenia_tabulate_target_checked) return;
    self.xenia_tabulate_target_checked = true;
    self.xenia_tabulate_target = process_impl_kernel_services.localSymbolAddress(self, "_ZN8tabulate5Table3strB5cxx11Ev") orelse
        process_impl_kernel_services.localSymbolAddress(self, "tabulate::Table::str[abi:cxx11]()") orelse
        discoverXeniaTabulateTarget(self);
    if (self.xenia_tabulate_target) |resolved| {
        __process_log.info("PE64 Xenia metadata table accelerator armed: target=0x{x} entry-signature-gated=true", .{resolved});
    } else {
        __process_log.warn("PE64 Xenia metadata table accelerator requested but tabulate::Table::str was not found; execution remains guest-interpreted", .{});
    }
    noteXeniaAcceleratorTargetResolved(self);
}

pub fn noteXeniaAcceleratorTargetResolved(self: *ElfState) void {
    // Parallel executors' translated code reads the filter while it runs;
    // it was built with the world stopped when parallel mode began, and a
    // target resolved after that only goes unaccelerated.
    if (self.parallel_guest_execution) return;
    if (self.block_jit != null and !self.block_jit_hook_filter_rebuilding) process_impl_block_jit.rebuildBlockJitHookFilter(self);
}

pub fn resolveXeniaAcceleratorTargets(self: *ElfState) void {
    if (!self.windows_runtime_enabled) return;
    if (self.xenia_sha1_accelerator_enabled) resolveXeniaSha1Target(self);
    if (self.xenia_rijndael_accelerator_enabled) resolveXeniaRijndaelTarget(self);
    if (self.xenia_tabulate_accelerator_enabled) resolveXeniaTabulateTarget(self);
}

pub fn tryXeniaTabulateAccelerator(self: *ElfState, target: u64, return_rip: u64) bool {
    if (!self.xenia_tabulate_accelerator_enabled or !self.windows_runtime_enabled) return false;
    resolveXeniaTabulateTarget(self);

    if (self.xenia_tabulate_target == null or self.xenia_tabulate_target.? != target) return false;
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer {
        if (runtime_guard) |*guard| guard.unlock();
    }

    // basic_string's non-trivial return uses the hidden RCX result
    // pointer; RDX is the tabulate::Table object.
    if (!__process_xenia_accelerator.tryXeniaTabulateString(self, process_impl_lifecycle.guestContextField(self, "regs").*.rcx, process_impl_lifecycle.guestContextField(self, "regs").*.rdx)) {
        self.xenia_tabulate_accelerator_failures +|= 1;
        if (self.xenia_tabulate_accelerator_failures == 1) {
            __process_log.warn("PE64 Xenia metadata table accelerator declined a string: target=0x{x} result=0x{x} table=0x{x} step={d}; falling back to tabulate", .{
                target,
                process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
        return false;
    }

    noteGuestCall(self, .direct, target, return_rip);
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = return_rip;
    noteGuestReturn(self, return_rip);
    self.xenia_tabulate_accelerated_strings +|= 1;
    if (self.xenia_tabulate_accelerated_strings == 1) {
        __process_log.info("PE64 Xenia metadata table accelerator active: first table string bypassed at step={d}", .{process_impl_lifecycle.observedExecutionSteps(self)});
    }
    return true;
}

pub fn execute(self: *ElfState, d: __process_DecodedInsn) void {
    // `step` establishes this for normal execution. Keep the public
    // interpreter entry safe as well: instruction-level tests and
    // embedders can call `execute` directly, and every scalar/locked
    // access in parallel mode must join the same byte coordinator.
    var execution_guard: ?__process_GuestExecutionGate.StepGuard = null;
    if (self.parallel_guest_execution) {
        if (self.guest_execution_gate.currentStepDepth() == 0) {
            execution_guard = self.guest_execution_gate.enterStep();
        }
    }
    defer {
        if (execution_guard) |*guard| guard.unlock();
    }
    const active_tso_buffer = process_impl_block_jit.activeGuestTsoStoreBuffer(self);
    const prior_tso_buffer = __process_tso_memory.setActiveStoreBuffer(active_tso_buffer);
    defer {
        // Public execute() calls outside step() are single-instruction
        // boundaries. Publish their stores before returning to callers
        // which may inspect the backing slice directly.
        if (prior_tso_buffer == null and active_tso_buffer != null) __process_tso_memory.flushActiveStoreBufferFor(.runtime_call);
        _ = __process_tso_memory.setActiveStoreBuffer(prior_tso_buffer);
    }
    const prior_coordinated_access = __process_tso_memory.setCoordinatedGuestAccess(self.parallel_guest_execution);
    defer _ = __process_tso_memory.setCoordinatedGuestAccess(prior_coordinated_access);
    // LOCK is only defined for a restricted set of read-modify-write
    // memory forms. Treat an invalid prefix as #UD before any vector or
    // scalar dispatch can execute the underlying operation without its
    // required atomicity.
    if (!__process_block_jit.lockPrefixAllowed(d)) {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .invalid_instruction;
        process_impl_lifecycle.markTerminated(self);
        if (comptime !@import("builtin").is_test) {
            __process_log.err("PE64 invalid LOCK prefix: rip=0x{x} op={s} memory_form={} size={s}", .{
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                @tagName(d.op),
                !d.is_reg_form,
                @tagName(d.size),
            });
        }
        return;
    }
    // The vector routing chain below is six dispatches deep, and every
    // op it can claim is either EVEX-encoded, `movdir64b`, or an op
    // `isVectorOperationRuntime` names (the lists in `evex.handles`,
    // `executeCleoVectorMove`, `executeSharedVex` and
    // `executeVectorSpecial` are all `v*` forms plus `pmovmskb`, which
    // that predicate includes). A scalar instruction therefore answers
    // one bit test here instead of walking the chain: on the 2026-09-17
    // profile the chain, including two `@tagName` lookups per
    // instruction, was a fifth of the interpreter.
    if (d.is_evex or d.op == .movdir64b or isVectorOperationRuntime(d.op)) {
        if (executeVectorRouted(self, d)) return;
    }

    // Accumulator-immediate forms are scalar Group-1 operations. Handle
    // them before the broad legacy fallback, whose compatibility list also
    // contains these Op tags for older vector dispatch coverage.
    if (isAccumulatorImmediate(d.op)) {
        executeAccumulatorImmediate(self, d);
        advanceAfterHandled(self, d);
        return;
    }

    switch (d.op) {
        .invalid => process_impl_instruction_decode.terminateUnimplemented(self, d),
        .nop => {},
        .cmc => process_impl_lifecycle.guestContextField(self, "regs").*.rflags ^= __process_RFL_CF,
        .clc => process_impl_lifecycle.guestContextField(self, "regs").*.rflags &= ~__process_RFL_CF,
        .stc => process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= __process_RFL_CF,
        // Direction flag. The string operations read it for their stride,
        // so without these the guest was subject to a flag it could not set.
        .cld => process_impl_lifecycle.guestContextField(self, "regs").*.rflags &= ~__process_RFL_DF,
        .std => process_impl_lifecycle.guestContextField(self, "regs").*.rflags |= __process_RFL_DF,
        .xchg_accum_reg => {
            const sz = d.size;
            const left = regVal(self, .al_ax_eax_rax, sz);
            const right = regVal(self, d.src_reg, sz);
            setReg(self, .al_ax_eax_rax, sz, right);
            setReg(self, d.src_reg, sz, left);
        },
        .loopne, .loope, .loop, .jrcxz => {
            const counter_size: __process_Size = if (d.has_0x67) .bits32 else .bits64;
            var taken = false;
            if (d.op == .jrcxz) {
                taken = regVal(self, .cl_cx_ecx_rcx, counter_size) == 0;
            } else {
                const next = regVal(self, .cl_cx_ecx_rcx, counter_size) -% 1;
                setReg(self, .cl_cx_ecx_rcx, counter_size, next);
                const zero = (process_impl_lifecycle.guestContextField(self, "regs").*.rflags & __process_RFL_ZF) != 0;
                taken = next != 0 and switch (d.op) {
                    .loope => zero,
                    .loopne => !zero,
                    else => true,
                };
            }
            if (taken) {
                process_impl_lifecycle.guestContextField(self, "regs").*.rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip +% d.len +% d.imm;
            } else {
                process_impl_lifecycle.guestContextField(self, "regs").*.rip +%= d.len;
            }
            return;
        },
        .xlat => {
            const table = regVal(self, .bl_bx_ebx_rbx, .bits64);
            const index = regVal(self, .al_ax_eax_rax, .bits8) & 0xFF;
            const value = readMemVal(self, table +% index, .bits8);
            setReg(self, .al_ax_eax_rax, .bits8, value & 0xFF);
        },
        .lahf => {
            const ah = @as(u64, __process_x64_decoder.statusByteForLahf(process_impl_lifecycle.guestContextField(self, "regs").*.rflags));
            process_impl_lifecycle.guestContextField(self, "regs").*.rax = (process_impl_lifecycle.guestContextField(self, "regs").*.rax & 0xFFFF_FFFF_FFFF_00FF) | (ah << 8);
        },
        .sahf => __process_x64_decoder.applySahf(&process_impl_lifecycle.guestContextField(self, "regs").*.rflags, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax >> 8)),

        // The D8-DF x87 arithmetic family (fadd/fmul/fsub/fsubr/fdiv/fdivr
        // with m32/m64, plus the fi* integer forms) is decoded by the shared
        // decoder into a single .x87_binary op with the operation packed in
        // x87.imm; the per-size members below are the only x87 ops the
        // shared Op enum exposes.
        .fild_mem16 => {
            const value = @as(i16, @bitCast(@as(u16, @truncate(readMemVal(self, d.addr, .bits16)))));
            _ = x87PushRaw(self, x87RawFromInt(value));
        },
        .fild_mem32 => {
            const value = @as(i32, @bitCast(@as(u32, @truncate(readMemVal(self, d.addr, .bits32)))));
            _ = x87PushRaw(self, x87RawFromInt(value));
        },
        .fild_mem64 => {
            const value = @as(i64, @bitCast(readMemVal(self, d.addr, .bits64)));
            _ = x87PushRaw(self, x87RawFromInt(value));
        },
        .fld_mem32 => {
            const value: f32 = @bitCast(@as(u32, @truncate(readMemVal(self, d.addr, .bits32))));
            _ = x87PushRaw(self, x87RawFromFloat(@floatCast(value)));
        },
        .fld_mem64 => {
            _ = x87PushRaw(self, x87RawFromFloat(@bitCast(readMemVal(self, d.addr, .bits64))));
        },
        .fld_mem80 => {
            var raw: __process_X87Raw = undefined;
            if (!copyFromGuest(self, &raw, d.addr)) return;
            _ = x87PushRaw(self, raw);
        },
        .fstp_mem80 => {
            if (x87PopRaw(self)) |raw| {
                process_impl_guest_memory.traceGuestWrite(self, d.addr, 10, __process_std.mem.readInt(u64, raw[0..8], .little));
                _ = copyToGuest(self, d.addr, &raw);
            } else {
                _ = fillGuestMemory(self, d.addr, 10, 0);
            }
        },
        .fstp_mem32 => {
            if (x87PopRaw(self)) |raw| {
                const value = readExtendedFloat80(&raw);
                writeMemVal(self, d.addr, .bits32, @as(u64, @as(u32, @bitCast(@as(f32, @floatCast(value))))));
            }
        },
        .fstp_mem64 => {
            if (x87PopRaw(self)) |raw| {
                writeMemVal(self, d.addr, .bits64, @as(u64, @bitCast(readExtendedFloat80(&raw))));
            }
        },
        .fisttp_mem32 => {
            if (guestMemoryConst(self, d.addr, 4) == null) return;
            const raw = x87GetRaw(self, 0) orelse return;
            const value = readExtendedFloat80(&raw);
            const invalid = __process_std.math.isNan(value) or !__process_std.math.isFinite(value) or
                value <= -0x1p31 - 1.0 or value >= 0x1p31;
            const integer: i32 = if (invalid) __process_std.math.minInt(i32) else @intFromFloat(value);
            if (invalid) process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 0;
            _ = x87PopRaw(self);
            writeMemVal(self, d.addr, .bits32, @as(u32, @bitCast(integer)));
        },
        .fisttp_mem64 => {
            if (guestMemoryConst(self, d.addr, 8) == null) return;
            const raw = x87GetRaw(self, 0) orelse return;
            const value = readExtendedFloat80(&raw);
            const min_i64 = -0x1p63;
            const invalid = __process_std.math.isNan(value) or
                !__process_std.math.isFinite(value) or
                value < min_i64 or
                value >= 0x1p63;
            const integer = if (invalid)
                __process_std.math.minInt(i64)
            else
                @as(i64, @intFromFloat(value));
            if (invalid) process_impl_lifecycle.guestContextField(self, "x87_status").* |= 1 << 0;
            _ = x87PopRaw(self);
            writeMemVal(self, d.addr, .bits64, @bitCast(integer));
        },
        .fld_st => {
            if (x87GetRaw(self, @truncate(d.imm))) |raw| _ = x87PushRaw(self, raw);
        },
        .fstp_st => {
            if (x87GetRaw(self, 0)) |raw| {
                if (x87SetRaw(self, @truncate(d.imm), raw)) _ = x87PopRaw(self);
            }
        },
        .fxch_st => x87Exchange(self, @truncate(d.imm)),
        .ffree_st => x87Free(self, @truncate(d.imm)),
        .fninit => x87Reset(self),
        .fchs => x87Fchs(self),
        .fabs => x87Fabs(self),
        .ftst => x87Test(self),
        .fxam => {},
        .f2xm1 => x87F2xm1(self),
        .fyl2x => x87Fyl2x(self, false),
        .fptan => x87Fptan(self),
        .fpatan => x87Fpatan(self),
        .fxtract => x87Fxtract(self),
        .fdecstp => process_impl_lifecycle.guestContextField(self, "x87_top").* -%= 1,
        .fincstp => process_impl_lifecycle.guestContextField(self, "x87_top").* +%= 1,
        .fsin => x87Sin(self),
        .fcos => x87Cos(self),
        .fprem1 => x87PartialRemainderNearest(self),
        .fprem => x87PartialRemainderTrunc(self),
        .fyl2xp1 => x87Fyl2x(self, true),
        .fsqrt => {
            const raw = x87GetRaw(self, 0) orelse return;
            _ = x87SetRaw(self, 0, x87RawFromFloat(@sqrt(readExtendedFloat80(&raw))));
        },
        .fsincos => x87Fsincos(self),
        .frndint => x87Frndint(self),
        .fscale => x87Fscale(self),
        .fnop => {},
        .fclex => x87Fclex(self),
        .fnstsw_ax => setReg(self, .al_ax_eax_rax, .bits16, x87StatusWord(self)),
        .fnstcw_mem16 => writeMemVal(self, d.addr, .bits16, process_impl_lifecycle.guestContextField(self, "x87_control").*),
        .fstenv_mem => {
            // The 28-byte protected-mode environment: control, status and
            // tag words, then instruction and data pointers this model does
            // not keep (stored as zero). FNSTENV then masks every exception.
            if (guestMemoryConst(self, d.addr, 28) == null) return;
            var output: [28]u8 = @splat(0);
            var tags: u16 = 0;
            for (process_impl_lifecycle.guestContextField(self, "x87_tags").*, 0..) |occupied, physical| {
                if (!occupied) tags |= @as(u16, 3) << @intCast(physical * 2);
            }
            __process_std.mem.writeInt(u16, output[0..2], process_impl_lifecycle.guestContextField(self, "x87_control").*, .little);
            __process_std.mem.writeInt(u16, output[4..6], x87StatusWord(self), .little);
            __process_std.mem.writeInt(u16, output[8..10], tags, .little);
            _ = copyToGuest(self, d.addr, &output);
            process_impl_lifecycle.guestContextField(self, "x87_control").* |= 0x3F;
        },
        .fldenv_mem => {
            // The register stack (TOP and the tag word) is this model's
            // own; the control word and the exception and condition bits
            // are what a caller restores.
            var input: [28]u8 = undefined;
            if (!copyFromGuest(self, &input, d.addr)) return;
            process_impl_lifecycle.guestContextField(self, "x87_control").* = __process_std.mem.readInt(u16, input[0..2], .little);
            const status = __process_std.mem.readInt(u16, input[4..6], .little);
            process_impl_lifecycle.guestContextField(self, "x87_status").* = (process_impl_lifecycle.guestContextField(self, "x87_status").* & 0x3800) | (status & ~@as(u16, 0x3800));
        },
        .fldcw_mem16 => process_impl_lifecycle.guestContextField(self, "x87_control").* = @truncate(readMemVal(self, d.addr, .bits16)),
        .x87_binary => x87Binary(self, d),
        .fldz => _ = x87PushRaw(self, x87RawFromFloat(0.0)),
        .fld1 => _ = x87PushRaw(self, x87RawFromFloat(1.0)),
        .fldl2t => _ = x87PushRaw(self, x87RawFromFloat(3.32192809488736234787)),
        .fldl2e => _ = x87PushRaw(self, x87RawFromFloat(1.44269504088896340736)),
        .fldpi => _ = x87PushRaw(self, x87RawFromFloat(3.14159265358979323846)),
        .fldlg2 => _ = x87PushRaw(self, x87RawFromFloat(0.30102999566398119521)),
        .fldln2 => _ = x87PushRaw(self, x87RawFromFloat(0.69314718055994530942)),
        .x87_memory => x87Memory(self, d),
        .fucomi_st => x87Compare(self, @truncate(d.imm), false),
        .fcomi_st => x87Compare(self, @truncate(d.imm), false),
        .fucomip_st => x87Compare(self, @truncate(d.imm), true),
        .fcomip_st => x87Compare(self, @truncate(d.imm), true),
        .fcmovb_st,
        .fcmove_st,
        .fcmovbe_st,
        .fcmovu_st,
        .fcmovnb_st,
        .fcmovne_st,
        .fcmovnbe_st,
        .fcmovnu_st,
        => {
            if (__process_x64_decoder.evalCond(process_impl_lifecycle.guestContextField(self, "regs").*.rflags, d.cond)) {
                if (x87GetRaw(self, @truncate(d.imm))) |raw| _ = x87SetRaw(self, 0, raw);
            }
        },

        // ── mov reg, mem ──
        .mov_reg8_mem8 => {
            const val = readMemVal(self, d.addr, .bits8);
            setDecodedReg(self, d.dst_reg, d.dst_high8, .bits8, val);
        },
        .mov_reg16_mem16 => {
            const val = readMemVal(self, d.addr, .bits16);
            setReg(self, d.dst_reg, .bits16, val);
        },
        .mov_reg32_mem32 => {
            const val = readMemVal(self, d.addr, .bits32);
            setReg(self, d.dst_reg, .bits32, val);
        },
        .mov_reg64_mem64 => {
            const val = readMemVal(self, d.addr, .bits64);
            setReg(self, d.dst_reg, .bits64, val);
        },

        // ── mov mem, reg ──
        .mov_mem8_reg8 => {
            const val = decodedRegVal(self, d.src_reg, d.src_high8, .bits8);
            writeMemVal(self, d.addr, .bits8, val);
        },
        .mov_mem16_reg16 => {
            const val = regVal(self, d.src_reg, .bits16);
            writeMemVal(self, d.addr, .bits16, val);
        },
        .mov_mem32_reg32 => {
            const val = regVal(self, d.src_reg, .bits32);
            writeMemVal(self, d.addr, .bits32, val);
        },
        .mov_mem64_reg64 => {
            const val = regVal(self, d.src_reg, .bits64);
            writeMemVal(self, d.addr, .bits64, val);
        },

        // ── mov reg, imm ──
        .mov_reg_imm => {
            setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, d.imm);
        },

        .movs, .cmps, .stos, .lods, .scas => executeStringOperation(self, d),

        // ── mov mem, imm ──
        .mov_mem8_imm8 => {
            writeMemVal(self, d.addr, .bits8, d.imm);
        },
        .mov_mem16_imm16 => {
            writeMemVal(self, d.addr, .bits16, d.imm);
        },
        .mov_mem32_imm32 => {
            writeMemVal(self, d.addr, .bits32, d.imm);
        },
        .mov_mem64_imm32 => {
            writeMemVal(self, d.addr, .bits64, d.imm);
        },

        // ── mov reg64, reg64 ──
        .mov_reg8_reg8 => {
            const val = decodedRegVal(self, d.src_reg, d.src_high8, .bits8);
            setDecodedReg(self, d.dst_reg, d.dst_high8, .bits8, val);
        },
        .mov_reg16_reg16 => {
            const val = regVal(self, d.src_reg, .bits16);
            setReg(self, d.dst_reg, .bits16, val);
        },
        .mov_reg32_reg32 => {
            const val = regVal(self, d.src_reg, .bits32);
            setReg(self, d.dst_reg, .bits32, val);
        },
        .mov_reg64_reg64 => {
            const val = regVal(self, d.src_reg, .bits64);
            setReg(self, d.dst_reg, .bits64, val);
        },

        // ── add reg, mem (d=1) ──
        .add_reg8_mem8, .add_reg16_mem16, .add_reg32_mem32, .add_reg64_mem64 => executeHighwayMemoryBinary(self, d, .add, .memory_to_register),

        // ── add r/m, reg (d=0) ──
        .add_mem8_reg8, .add_mem16_reg16, .add_mem32_reg32, .add_mem64_reg64 => executeHighwayMemoryBinary(self, d, .add, .register_to_memory),

        // ── add reg, reg ──
        .add_reg8_reg8, .add_reg16_reg16, .add_reg32_reg32, .add_reg64_reg64 => executeHighwayRegisterBinary(self, d, .add),
        .add_reg8_imm8, .add_reg16_imm8, .add_reg32_imm8, .add_reg64_imm8 => {
            const imm = if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm);
            executeHighwayImmediate(self, d, .add, false, imm);
        },
        .adc_reg8_imm8, .adc_reg16_imm8, .adc_reg32_imm8, .adc_reg64_imm8 => executeHighwayImmediate(self, d, .adc, false, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .adc_reg8_mem8, .adc_reg16_mem16, .adc_reg32_mem32, .adc_reg64_mem64 => executeHighwayMemoryBinary(self, d, .adc, .memory_to_register),
        .adc_mem8_reg8, .adc_mem16_reg16, .adc_mem32_reg32, .adc_mem64_reg64 => executeHighwayMemoryBinary(self, d, .adc, .register_to_memory),
        .adc_reg8_reg8, .adc_reg16_reg16, .adc_reg32_reg32, .adc_reg64_reg64 => executeHighwayRegisterBinary(self, d, .adc),
        .sbb_reg8_mem8, .sbb_reg16_mem16, .sbb_reg32_mem32, .sbb_reg64_mem64 => executeHighwayMemoryBinary(self, d, .sbb, .memory_to_register),
        .sbb_mem8_reg8, .sbb_mem16_reg16, .sbb_mem32_reg32, .sbb_mem64_reg64 => executeHighwayMemoryBinary(self, d, .sbb, .register_to_memory),
        .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32 => {
            const imm = __process_testImmForSize(d.imm, d.size);
            executeHighwayImmediate(self, d, .add, false, imm);
        },
        .or_reg16_imm32, .or_reg32_imm32, .or_reg64_imm32 => executeHighwayImmediate(self, d, .bit_or, false, __process_testImmForSize(d.imm, d.size)),
        .adc_reg16_imm32, .adc_reg32_imm32, .adc_reg64_imm32 => executeHighwayImmediate(self, d, .adc, false, __process_testImmForSize(d.imm, d.size)),
        .sbb_reg16_imm32, .sbb_reg32_imm32, .sbb_reg64_imm32 => executeHighwayImmediate(self, d, .sbb, false, __process_testImmForSize(d.imm, d.size)),
        .xor_reg16_imm32, .xor_reg32_imm32, .xor_reg64_imm32 => executeHighwayImmediate(self, d, .bit_xor, false, __process_testImmForSize(d.imm, d.size)),
        .add_mem8_imm8, .add_mem16_imm8, .add_mem32_imm8, .add_mem64_imm8 => executeHighwayImmediate(self, d, .add, true, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),

        // ── sub reg, mem ──
        .sub_reg8_mem8, .sub_reg16_mem16, .sub_reg32_mem32, .sub_reg64_mem64 => executeHighwayMemoryBinary(self, d, .sub, .memory_to_register),
        .sub_mem8_reg8, .sub_mem16_reg16, .sub_mem32_reg32, .sub_mem64_reg64 => executeHighwayMemoryBinary(self, d, .sub, .register_to_memory),

        // ── sub reg, reg ──
        .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64 => executeHighwayRegisterBinary(self, d, .sub),
        .sbb_reg8_reg8, .sbb_reg16_reg16, .sbb_reg32_reg32, .sbb_reg64_reg64 => executeHighwayRegisterBinary(self, d, .sbb),

        // ── sub r/m8, imm8 (0x80 /5) ──
        .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8 => executeHighwayImmediate(self, d, .sub, false, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .sbb_reg8_imm8 => executeHighwayImmediate(self, d, .sbb, false, d.imm & 0xFF),
        .sbb_reg16_imm8, .sbb_reg32_imm8, .sbb_reg64_imm8 => executeHighwayImmediate(self, d, .sbb, false, __process_signExtendImm8(d.imm)),
        .sub_mem8_imm8, .sub_mem16_imm8, .sub_mem32_imm8, .sub_mem64_imm8 => executeHighwayImmediate(self, d, .sub, true, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .sub_reg16_imm32, .sub_reg32_imm32, .sub_reg64_imm32 => executeHighwayImmediate(self, d, .sub, false, __process_testImmForSize(d.imm, d.size)),

        // ── logical register/imm operations ──
        .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64 => {
            executeHighwayRegisterBinary(self, d, .bit_and);
        },
        .and_reg8_mem8, .and_reg16_mem16, .and_reg32_mem32, .and_reg64_mem64 => {
            executeHighwayMemoryBinary(self, d, .bit_and, .memory_to_register);
        },
        .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64 => {
            executeHighwayMemoryBinary(self, d, .bit_and, .register_to_memory);
        },
        .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8 => {
            const imm = if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm);
            executeHighwayImmediate(self, d, .bit_and, false, imm);
        },
        .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32 => executeHighwayImmediate(self, d, .bit_and, false, __process_testImmForSize(d.imm, d.size)),
        .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64 => {
            executeHighwayRegisterBinary(self, d, .bit_or);
        },
        .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64 => {
            executeHighwayMemoryBinary(self, d, .bit_or, .memory_to_register);
        },
        .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64 => {
            executeHighwayMemoryBinary(self, d, .bit_or, .register_to_memory);
        },
        .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8 => executeHighwayImmediate(self, d, .bit_or, false, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .or_mem8_imm8, .or_mem16_imm8, .or_mem32_imm8, .or_mem64_imm8 => executeHighwayImmediate(self, d, .bit_or, true, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .or_mem16_imm32, .or_mem32_imm32, .or_mem64_imm32 => executeHighwayImmediate(self, d, .bit_or, true, __process_testImmForSize(d.imm, d.size)),
        // The remainder of group 1's memory matrix. `or` was the only
        // operation with every cell; the rest ranged from four to none,
        // and `adc qword ptr [rax+8], 0` decoded as invalid.
        .add_mem16_imm32, .add_mem32_imm32, .add_mem64_imm32 => executeHighwayImmediate(self, d, .add, true, __process_testImmForSize(d.imm, d.size)),
        .adc_mem8_imm8, .adc_mem16_imm8, .adc_mem32_imm8, .adc_mem64_imm8 => executeHighwayImmediate(self, d, .adc, true, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .adc_mem16_imm32, .adc_mem32_imm32, .adc_mem64_imm32 => executeHighwayImmediate(self, d, .adc, true, __process_testImmForSize(d.imm, d.size)),
        .sbb_mem8_imm8, .sbb_mem16_imm8, .sbb_mem32_imm8, .sbb_mem64_imm8 => executeHighwayImmediate(self, d, .sbb, true, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .sbb_mem16_imm32, .sbb_mem32_imm32, .sbb_mem64_imm32 => executeHighwayImmediate(self, d, .sbb, true, __process_testImmForSize(d.imm, d.size)),
        .and_mem8_imm8, .and_mem16_imm8, .and_mem32_imm8, .and_mem64_imm8 => executeHighwayImmediate(self, d, .bit_and, true, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .and_mem16_imm32, .and_mem32_imm32, .and_mem64_imm32 => executeHighwayImmediate(self, d, .bit_and, true, __process_testImmForSize(d.imm, d.size)),
        .sub_mem16_imm32, .sub_mem32_imm32, .sub_mem64_imm32 => executeHighwayImmediate(self, d, .sub, true, __process_testImmForSize(d.imm, d.size)),
        .xor_mem8_imm8, .xor_mem16_imm8, .xor_mem32_imm8, .xor_mem64_imm8 => executeHighwayImmediate(self, d, .bit_xor, true, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .xor_mem16_imm32, .xor_mem32_imm32, .xor_mem64_imm32 => executeHighwayImmediate(self, d, .bit_xor, true, __process_testImmForSize(d.imm, d.size)),
        .cmp_mem16_imm32, .cmp_mem32_imm32, .cmp_mem64_imm32 => executeHighwayImmediate(self, d, .cmp, true, __process_testImmForSize(d.imm, d.size)),
        .xor_reg8_mem8, .xor_reg16_mem16, .xor_reg32_mem32, .xor_reg64_mem64 => {
            executeHighwayMemoryBinary(self, d, .bit_xor, .memory_to_register);
        },
        .xor_mem8_reg8, .xor_mem16_reg16, .xor_mem32_reg32, .xor_mem64_reg64 => {
            executeHighwayMemoryBinary(self, d, .bit_xor, .register_to_memory);
        },
        .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64 => {
            executeHighwayRegisterBinary(self, d, .bit_xor);
        },
        .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8 => executeHighwayImmediate(self, d, .bit_xor, false, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .bsf_reg_reg,
        .bsf_reg_mem,
        .bsr_reg_reg,
        .bsr_reg_mem,
        .tzcnt_reg_reg,
        .tzcnt_reg_mem,
        .lzcnt_reg_reg,
        .lzcnt_reg_mem,
        => executeBitScan(self, d),
        .andn, .bzhi, .mulx, .rorx, .shlx, .shrx, .sarx => executeBmi(self, d),
        .popcnt_reg_reg, .popcnt_reg_mem => {
            const source = if (d.op == .popcnt_reg_mem)
                readMemVal(self, d.addr, d.size)
            else
                regVal(self, d.src_reg, d.size);
            const result = __process_x64_decoder.populationCount(d.size, source, process_impl_lifecycle.guestContextField(self, "regs").*.rflags);
            setReg(self, d.dst_reg, d.size, result.value);
            process_impl_lifecycle.guestContextField(self, "regs").*.rflags = result.rflags;
        },
        .bswap_reg => setReg(self, d.dst_reg, d.size, __process_x64_decoder.byteSwap(d.size, regVal(self, d.dst_reg, d.size))),
        .movbe_reg_mem => {
            const value = readMemVal(self, d.addr, d.size);
            setReg(self, d.dst_reg, d.size, __process_x64_decoder.byteSwap(d.size, value));
        },
        .movbe_mem_reg => {
            const value = __process_x64_decoder.byteSwap(d.size, regVal(self, d.src_reg, d.size));
            writeMemVal(self, d.addr, d.size, value);
        },
        .ldmxcsr_mem32 => {
            const mxcsr: u32 = @truncate(readMemVal(self, d.addr, .bits32));
            process_impl_lifecycle.guestContextField(self, "regs").*.mxcsr = mxcsr;
            // Flush and rounding take effect on the host FPCR, which is
            // what the native arithmetic below actually obeys.
            __process_host_fp_control.applyGuestMxcsr(mxcsr);
        },
        .stmxcsr_mem32 => {
            writeMemVal(self, d.addr, .bits32, process_impl_lifecycle.guestContextField(self, "regs").*.mxcsr);
        },
        .crc32_reg_reg, .crc32_reg_mem => {
            const source = if (d.op == .crc32_reg_mem)
                readMemVal(self, d.addr, d.size)
            else
                regVal(self, d.src_reg, d.size);
            const crc = __process_x64_decoder.crc32cAccumulator(@truncate(regVal(self, d.dst_reg, .bits32)), source, d.size);
            setReg(self, d.dst_reg, d.dst_size, crc);
        },
        .rol_reg_cl,
        .rol_mem_cl,
        .ror_reg_cl,
        .ror_mem_cl,
        .rol_reg_imm,
        .rol_mem_imm,
        .ror_reg_imm,
        .ror_mem_imm,
        => executeRotate(self, d),
        // SHLD/SHRD: the vacated end is filled from a second register.
        // Shared semantics with the Mach-O path via
        // `x64_decoder.doubleShift`, so the two processors cannot drift.
        .shld_reg_imm8,
        .shld_mem_imm8,
        .shld_reg_cl,
        .shld_mem_cl,
        .shrd_reg_imm8,
        .shrd_mem_imm8,
        .shrd_reg_cl,
        .shrd_mem_cl,
        => {
            const sz = d.size;
            const is_mem = switch (d.op) {
                .shld_mem_imm8, .shld_mem_cl, .shrd_mem_imm8, .shrd_mem_cl => true,
                else => false,
            };
            const from_cl = switch (d.op) {
                .shld_reg_cl, .shld_mem_cl, .shrd_reg_cl, .shrd_mem_cl => true,
                else => false,
            };
            const left = switch (d.op) {
                .shld_reg_imm8, .shld_mem_imm8, .shld_reg_cl, .shld_mem_cl => true,
                else => false,
            };
            const raw = if (from_cl) regVal(self, .cl_cx_ecx_rcx, .bits8) else d.imm;
            const count: u6 = @intCast(raw & @as(u64, if (sz == .bits64) 0x3F else 0x1F));
            if (count != 0) {
                const destination = if (is_mem) readMemVal(self, d.addr, sz) else regVal(self, d.dst_reg, sz);
                const source = regVal(self, d.src_reg, sz);
                const shifted = __process_x64_decoder.doubleShift(destination, source, count, sz, left);
                if (is_mem) writeMemVal(self, d.addr, sz, shifted.value) else setReg(self, d.dst_reg, sz, shifted.value);
                setFlagsLogic(self, shifted.value, sz);
                setFlag(self, __process_RFL_CF, shifted.carry);
                if (count == 1) setFlag(self, __process_RFL_OF, shifted.sign_changed);
            }
        },
        .shl_reg_cl => {
            const old = decodedRegVal(self, d.dst_reg, d.dst_high8, d.size);
            const count = shlCount(self, d.size);
            const r = shlValue(self, old, d.size, count);
            setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, r);
            setFlagsShl(self, old, r, d.size, count);
        },
        .shl_mem_cl => {
            const old = readMemVal(self, d.addr, d.size);
            const count = shlCount(self, d.size);
            const r = shlValue(self, old, d.size, count);
            writeMemVal(self, d.addr, d.size, r);
            setFlagsShl(self, old, r, d.size, count);
        },
        .shr_reg_cl => {
            const old = decodedRegVal(self, d.dst_reg, d.dst_high8, d.size);
            const count = shlCount(self, d.size);
            const r = shrValue(self, old, d.size, count);
            setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, r);
            setFlagsShr(self, old, r, d.size, count);
        },
        .shr_mem_cl => {
            const old = readMemVal(self, d.addr, d.size);
            const count = shlCount(self, d.size);
            const r = shrValue(self, old, d.size, count);
            writeMemVal(self, d.addr, d.size, r);
            setFlagsShr(self, old, r, d.size, count);
        },
        .sar_reg_cl => {
            const old = decodedRegVal(self, d.dst_reg, d.dst_high8, d.size);
            const count = shlCount(self, d.size);
            const r = sarValue(self, old, d.size, count);
            setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, r);
            setFlagsSar(self, old, r, d.size, count);
        },
        .sar_mem_cl => {
            const old = readMemVal(self, d.addr, d.size);
            const count = shlCount(self, d.size);
            const r = sarValue(self, old, d.size, count);
            writeMemVal(self, d.addr, d.size, r);
            setFlagsSar(self, old, r, d.size, count);
        },
        .shl_reg_imm => {
            const old = decodedRegVal(self, d.dst_reg, d.dst_high8, d.size);
            const count = immShiftCount(d.imm, d.size);
            const r = shlValue(self, old, d.size, count);
            setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, r);
            setFlagsShl(self, old, r, d.size, count);
        },
        .shl_mem_imm => {
            const old = readMemVal(self, d.addr, d.size);
            const count = immShiftCount(d.imm, d.size);
            const r = shlValue(self, old, d.size, count);
            writeMemVal(self, d.addr, d.size, r);
            setFlagsShl(self, old, r, d.size, count);
        },
        .shr_reg_imm => {
            const old = decodedRegVal(self, d.dst_reg, d.dst_high8, d.size);
            const count = immShiftCount(d.imm, d.size);
            const r = shrValue(self, old, d.size, count);
            setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, r);
            setFlagsShr(self, old, r, d.size, count);
        },
        .shr_mem_imm => {
            const old = readMemVal(self, d.addr, d.size);
            const count = immShiftCount(d.imm, d.size);
            const r = shrValue(self, old, d.size, count);
            writeMemVal(self, d.addr, d.size, r);
            setFlagsShr(self, old, r, d.size, count);
        },
        .sar_reg_imm => {
            const old = decodedRegVal(self, d.dst_reg, d.dst_high8, d.size);
            const count = immShiftCount(d.imm, d.size);
            const r = sarValue(self, old, d.size, count);
            setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, r);
            setFlagsSar(self, old, r, d.size, count);
        },
        .sar_mem_imm => {
            const old = readMemVal(self, d.addr, d.size);
            const count = immShiftCount(d.imm, d.size);
            const r = sarValue(self, old, d.size, count);
            writeMemVal(self, d.addr, d.size, r);
            setFlagsSar(self, old, r, d.size, count);
        },
        .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64 => {
            executeHighwayRegisterBinary(self, d, .test_bits);
        },
        .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64 => {
            executeHighwayMemoryBinary(self, d, .test_bits, .register_to_memory);
        },
        .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => executeHighwayImmediate(self, d, .test_bits, false, __process_testImmForSize(d.imm, d.size)),
        .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => executeHighwayImmediate(self, d, .test_bits, true, __process_testImmForSize(d.imm, d.size)),
        .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
            const a = decodedRegVal(self, d.dst_reg, d.dst_high8, d.size);
            const r = 0 -% a;
            setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, r);
            setFlagsSub(self, 0, a, r, d.size);
        },
        .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => {
            if (!executeAtomicNeg(self, d)) {
                const a = readMemVal(self, d.addr, d.size);
                const r = 0 -% a;
                writeMemVal(self, d.addr, d.size, r);
                setFlagsSub(self, 0, a, r, d.size);
            }
        },
        .not_reg8, .not_reg16, .not_reg32, .not_reg64 => {
            setDecodedReg(self, d.dst_reg, d.dst_high8, d.size, ~decodedRegVal(self, d.dst_reg, d.dst_high8, d.size));
        },
        .not_mem8, .not_mem16, .not_mem32, .not_mem64 => {
            if (!executeAtomicNot(self, d)) {
                writeMemVal(self, d.addr, d.size, ~readMemVal(self, d.addr, d.size));
            }
        },

        .bt_reg_reg => executeBitTestRegister(self, d, .probe, false),
        .bt_mem_reg => executeBitTestMemory(self, d, .probe, false),
        .bts_reg_reg => executeBitTestRegister(self, d, .set, false),
        .bts_mem_reg => executeBitTestMemory(self, d, .set, false),
        .btr_reg_reg => executeBitTestRegister(self, d, .reset, false),
        .btr_mem_reg => executeBitTestMemory(self, d, .reset, false),
        .btc_reg_reg => executeBitTestRegister(self, d, .complement, false),
        .btc_mem_reg => executeBitTestMemory(self, d, .complement, false),
        .bt_reg_imm => executeBitTestRegister(self, d, .probe, true),
        .bt_mem_imm => executeBitTestMemory(self, d, .probe, true),
        .bts_reg_imm => executeBitTestRegister(self, d, .set, true),
        .bts_mem_imm => executeBitTestMemory(self, d, .set, true),
        .btr_reg_imm => executeBitTestRegister(self, d, .reset, true),
        .btr_mem_imm => executeBitTestMemory(self, d, .reset, true),
        .btc_reg_imm => executeBitTestRegister(self, d, .complement, true),
        .btc_mem_imm => executeBitTestMemory(self, d, .complement, true),

        // ── cmp r/m, reg (opcode 0x39) ──
        .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64 => executeHighwayMemoryBinary(self, d, .cmp, .register_to_memory),

        // ── cmp reg, reg (opcode 0x39, mod=3) ──
        .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64 => executeHighwayRegisterBinary(self, d, .cmp),

        // ── cmp reg, r/m (0x3A/0x3B, d=1) ──
        .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64 => executeHighwayMemoryBinary(self, d, .cmp, .memory_to_register),

        // ── cmp r/m, imm8 (0x83 /7) ──
        .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8 => executeHighwayImmediate(self, d, .cmp, true, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => executeHighwayImmediate(self, d, .cmp, false, if (d.size == .bits8) d.imm & 0xFF else __process_signExtendImm8(d.imm)),
        .cmp_reg16_imm32, .cmp_reg32_imm32, .cmp_reg64_imm32 => executeHighwayImmediate(self, d, .cmp, false, __process_testImmForSize(d.imm, d.size)),

        // ── inc/dec memory ──
        .inc_mem8 => {
            if (!executeAtomicIncDec(self, d, true)) {
                const old = readMemVal(self, d.addr, .bits8);
                const r = old +% 1;
                writeMemVal(self, d.addr, .bits8, r);
                setFlagsIncDec(self, old, r, .bits8, true);
            }
        },
        .inc_mem16 => {
            if (!executeAtomicIncDec(self, d, true)) {
                const old = readMemVal(self, d.addr, .bits16);
                const r = old +% 1;
                writeMemVal(self, d.addr, .bits16, r);
                setFlagsIncDec(self, old, r, .bits16, true);
            }
        },
        .inc_mem32 => {
            if (!executeAtomicIncDec(self, d, true)) {
                const old = readMemVal(self, d.addr, .bits32);
                const r = old +% 1;
                writeMemVal(self, d.addr, .bits32, r);
                setFlagsIncDec(self, old, r, .bits32, true);
            }
        },
        .inc_mem64 => {
            if (!executeAtomicIncDec(self, d, true)) {
                const old = readMemVal(self, d.addr, .bits64);
                const r = old +% 1;
                writeMemVal(self, d.addr, .bits64, r);
                setFlagsIncDec(self, old, r, .bits64, true);
            }
        },
        .dec_mem8 => {
            if (!executeAtomicIncDec(self, d, false)) {
                const old = readMemVal(self, d.addr, .bits8);
                const r = old -% 1;
                writeMemVal(self, d.addr, .bits8, r);
                setFlagsIncDec(self, old, r, .bits8, false);
            }
        },
        .dec_mem16 => {
            if (!executeAtomicIncDec(self, d, false)) {
                const old = readMemVal(self, d.addr, .bits16);
                const r = old -% 1;
                writeMemVal(self, d.addr, .bits16, r);
                setFlagsIncDec(self, old, r, .bits16, false);
            }
        },
        .dec_mem32 => {
            if (!executeAtomicIncDec(self, d, false)) {
                const old = readMemVal(self, d.addr, .bits32);
                const r = old -% 1;
                writeMemVal(self, d.addr, .bits32, r);
                setFlagsIncDec(self, old, r, .bits32, false);
            }
        },
        .dec_mem64 => {
            if (!executeAtomicIncDec(self, d, false)) {
                const old = readMemVal(self, d.addr, .bits64);
                const r = old -% 1;
                writeMemVal(self, d.addr, .bits64, r);
                setFlagsIncDec(self, old, r, .bits64, false);
            }
        },

        // ── inc/dec register (0xFF /0, /1 with mod=3) ──
        .inc_reg8 => {
            const old = decodedRegVal(self, d.dst_reg, d.dst_high8, .bits8);
            const r = old +% 1;
            setDecodedReg(self, d.dst_reg, d.dst_high8, .bits8, r);
            setFlagsIncDec(self, old, r, .bits8, true);
        },
        .inc_reg16 => {
            const old = regVal(self, d.dst_reg, .bits16);
            const r = old +% 1;
            setReg(self, d.dst_reg, .bits16, r);
            setFlagsIncDec(self, old, r, .bits16, true);
        },
        .inc_reg32 => {
            const old = regVal(self, d.dst_reg, .bits32);
            const r = old +% 1;
            setReg(self, d.dst_reg, .bits32, r);
            setFlagsIncDec(self, old, r, .bits32, true);
        },
        .inc_reg64 => {
            const old = regVal(self, d.dst_reg, .bits64);
            const r = old +% 1;
            setReg(self, d.dst_reg, .bits64, r);
            setFlagsIncDec(self, old, r, .bits64, true);
        },
        .dec_reg8 => {
            const old = decodedRegVal(self, d.dst_reg, d.dst_high8, .bits8);
            const r = old -% 1;
            setDecodedReg(self, d.dst_reg, d.dst_high8, .bits8, r);
            setFlagsIncDec(self, old, r, .bits8, false);
        },
        .dec_reg16 => {
            const old = regVal(self, d.dst_reg, .bits16);
            const r = old -% 1;
            setReg(self, d.dst_reg, .bits16, r);
            setFlagsIncDec(self, old, r, .bits16, false);
        },
        .dec_reg32 => {
            const old = regVal(self, d.dst_reg, .bits32);
            const r = old -% 1;
            setReg(self, d.dst_reg, .bits32, r);
            setFlagsIncDec(self, old, r, .bits32, false);
        },
        .dec_reg64 => {
            const old = regVal(self, d.dst_reg, .bits64);
            const r = old -% 1;
            setReg(self, d.dst_reg, .bits64, r);
            setFlagsIncDec(self, old, r, .bits64, false);
        },

        // ── mul [mem] (unsigned, accumulator form) ──
        .mul_mem8 => {
            const b = readMemVal(self, d.addr, .bits8);
            const a = regVal(self, .al_ax_eax_rax, .bits8);
            const result = @as(u16, @intCast(a)) * @as(u16, @intCast(b));
            setReg(self, .al_ax_eax_rax, .bits16, result);
            const overflow = result > 0xFF;
            setFlag(self, __process_RFL_CF, overflow);
            setFlag(self, __process_RFL_OF, overflow);
        },
        .mul_mem16 => {
            const b: u16 = @intCast(readMemVal(self, d.addr, .bits16));
            const a: u16 = @intCast(regVal(self, .al_ax_eax_rax, .bits16));
            const result: u32 = @as(u32, a) * @as(u32, b);
            setReg(self, .al_ax_eax_rax, .bits16, @intCast(result & 0xFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits16, @intCast((result >> 16) & 0xFFFF));
        },
        .mul_mem32 => {
            const b = readMemVal(self, d.addr, .bits32);
            const a = regVal(self, .al_ax_eax_rax, .bits32);
            const result = @as(u64, a) * @as(u64, b);
            setReg(self, .al_ax_eax_rax, .bits32, @intCast(result & 0xFFFFFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits32, @intCast((result >> 32) & 0xFFFFFFFF));
        },
        .mul_mem64 => {
            const b = readMemVal(self, d.addr, .bits64);
            const a = regVal(self, .al_ax_eax_rax, .bits64);
            const result: u128 = @as(u128, a) * @as(u128, b);
            setReg(self, .al_ax_eax_rax, .bits64, @intCast(result & 0xFFFFFFFFFFFFFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits64, @intCast((result >> 64) & 0xFFFFFFFFFFFFFFFF));
        },

        // ── imul [mem] (signed, accumulator form) ──
        .imul_mem8 => {
            const a: i8 = @bitCast(@as(u8, @intCast(regVal(self, .al_ax_eax_rax, .bits8))));
            const b: i8 = @bitCast(@as(u8, @intCast(readMemVal(self, d.addr, .bits8))));
            const result: i16 = @as(i16, a) * @as(i16, b);
            setReg(self, .al_ax_eax_rax, .bits16, @as(u16, @bitCast(result)));
        },
        .imul_mem16 => {
            const a: i16 = @bitCast(@as(u16, @intCast(regVal(self, .al_ax_eax_rax, .bits16))));
            const b: i16 = @bitCast(@as(u16, @intCast(readMemVal(self, d.addr, .bits16))));
            const result: i32 = @as(i32, a) * @as(i32, b);
            const ru: u32 = @bitCast(result);
            const lo: u16 = @truncate(ru);
            const hi: u16 = @truncate(ru >> 16);
            setReg(self, .al_ax_eax_rax, .bits16, lo);
            setReg(self, .dl_dx_edx_rdx, .bits16, hi);
        },
        .imul_mem32 => {
            const a: i32 = @bitCast(@as(u32, @intCast(regVal(self, .al_ax_eax_rax, .bits32))));
            const b: i32 = @bitCast(@as(u32, @intCast(readMemVal(self, d.addr, .bits32))));
            const result: i64 = @as(i64, a) * @as(i64, b);
            const ru: u64 = @bitCast(result);
            const lo: u32 = @truncate(ru);
            const hi: u32 = @truncate(ru >> 32);
            setReg(self, .al_ax_eax_rax, .bits32, lo);
            setReg(self, .dl_dx_edx_rdx, .bits32, hi);
        },
        .imul_mem64 => {
            const a: i64 = @bitCast(regVal(self, .al_ax_eax_rax, .bits64));
            const b: i64 = @bitCast(readMemVal(self, d.addr, .bits64));
            const result: i128 = @as(i128, a) * @as(i128, b);
            const ru: u128 = @bitCast(result);
            const lo: u64 = @truncate(ru);
            const hi: u64 = @truncate(ru >> 64);
            setReg(self, .al_ax_eax_rax, .bits64, lo);
            setReg(self, .dl_dx_edx_rdx, .bits64, hi);
        },

        // ── div [mem] (unsigned) ──
        .div_mem8 => {
            const divisor = readMemVal(self, d.addr, .bits8);
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend = regVal(self, .al_ax_eax_rax, .bits16);
            const quot = dividend / @as(u16, @truncate(divisor));
            const rem = dividend % @as(u16, @truncate(divisor));
            // AL takes the quotient and AH the remainder; the remainder
            // used to land in DL, and a quotient AL cannot hold is #DE.
            if (quot > 0xFF) return process_impl_instruction_decode.raiseDivideError(self);
            setReg(self, .al_ax_eax_rax, .bits16, (rem << 8) | quot);
        },
        .div_mem16 => {
            const divisor = readMemVal(self, d.addr, .bits16);
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo = regVal(self, .al_ax_eax_rax, .bits16);
            const dividend_hi = regVal(self, .dl_dx_edx_rdx, .bits16);
            const dividend = (@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo));
            const quot = dividend / @as(u32, @truncate(divisor));
            const rem = dividend % @as(u32, @truncate(divisor));
            setReg(self, .al_ax_eax_rax, .bits16, @intCast(quot & 0xFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits16, @intCast(rem & 0xFFFF));
        },
        .div_mem32 => {
            const divisor = readMemVal(self, d.addr, .bits32);
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo = regVal(self, .al_ax_eax_rax, .bits32);
            const dividend_hi = regVal(self, .dl_dx_edx_rdx, .bits32);
            const dividend = (@as(u64, dividend_hi) << 32) | dividend_lo;
            const quot = dividend / @as(u64, divisor);
            const rem = dividend % @as(u64, divisor);
            setReg(self, .al_ax_eax_rax, .bits32, @intCast(quot & 0xFFFFFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits32, @intCast(rem & 0xFFFFFFFF));
        },
        .div_mem64 => {
            const divisor = readMemVal(self, d.addr, .bits64);
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo = regVal(self, .al_ax_eax_rax, .bits64);
            const dividend_hi = regVal(self, .dl_dx_edx_rdx, .bits64);
            const dividend = (@as(u128, dividend_hi) << 64) | dividend_lo;
            const quot = dividend / @as(u128, divisor);
            const rem = dividend % @as(u128, divisor);
            setReg(self, .al_ax_eax_rax, .bits64, @intCast(quot & 0xFFFFFFFFFFFFFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits64, @intCast(rem & 0xFFFFFFFFFFFFFFFF));
        },

        // ── idiv [mem] (signed) ──
        .idiv_mem8 => {
            const divisor: i8 = @bitCast(@as(u8, @intCast(readMemVal(self, d.addr, .bits8))));
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend: i16 = @bitCast(@as(u16, @intCast(regVal(self, .al_ax_eax_rax, .bits16))));
            // -32768 / -1 overflows i16 itself, before any AL check.
            if (divisor == -1 and dividend == __process_std.math.minInt(i16)) return process_impl_instruction_decode.raiseDivideError(self);
            const quot = @divTrunc(dividend, @as(i16, divisor));
            const rem = @rem(dividend, @as(i16, divisor));
            // AL takes the quotient and AH the remainder, as for DIV.
            if (quot < __process_std.math.minInt(i8) or quot > __process_std.math.maxInt(i8)) return process_impl_instruction_decode.raiseDivideError(self);
            const quotient_byte: u8 = @bitCast(@as(i8, @intCast(quot)));
            const remainder_byte: u8 = @bitCast(@as(i8, @intCast(rem)));
            setReg(self, .al_ax_eax_rax, .bits16, (@as(u16, remainder_byte) << 8) | quotient_byte);
        },
        .idiv_mem16 => {
            const divisor: i16 = @bitCast(@as(u16, @intCast(readMemVal(self, d.addr, .bits16))));
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo: u16 = @intCast(regVal(self, .al_ax_eax_rax, .bits16));
            const dividend_hi: u16 = @intCast(regVal(self, .dl_dx_edx_rdx, .bits16));
            const dividend: i32 = @bitCast((@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo)));
            const quot = @divTrunc(dividend, @as(i32, divisor));
            const rem = @rem(dividend, @as(i32, divisor));
            {
                const q: i16 = @truncate(quot);
                const r: i16 = @truncate(rem);
                setReg(self, .al_ax_eax_rax, .bits16, @as(u16, @bitCast(q)));
                setReg(self, .dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(r)));
            }
        },
        .idiv_mem32 => {
            const divisor: i32 = @bitCast(@as(u32, @intCast(readMemVal(self, d.addr, .bits32))));
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo: u32 = @intCast(regVal(self, .al_ax_eax_rax, .bits32));
            const dividend_hi: u32 = @intCast(regVal(self, .dl_dx_edx_rdx, .bits32));
            const dividend: i64 = @bitCast((@as(u64, dividend_hi) << 32) | @as(u64, dividend_lo));
            const quot = @divTrunc(dividend, @as(i64, divisor));
            const rem = @rem(dividend, @as(i64, divisor));
            setReg(self, .al_ax_eax_rax, .bits32, @as(u64, @bitCast(quot)));
            setReg(self, .dl_dx_edx_rdx, .bits32, @as(u64, @bitCast(rem)));
        },
        .idiv_mem64 => {
            const divisor: i64 = @bitCast(readMemVal(self, d.addr, .bits64));
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo = regVal(self, .al_ax_eax_rax, .bits64);
            const dividend_hi = regVal(self, .dl_dx_edx_rdx, .bits64);
            const dividend: i128 = @bitCast((@as(u128, dividend_hi) << 64) | dividend_lo);
            const quot = @divTrunc(dividend, @as(i128, divisor));
            const rem = @rem(dividend, @as(i128, divisor));
            const q64: u64 = @bitCast(@as(i64, @truncate(quot)));
            const r64: u64 = @bitCast(@as(i64, @truncate(rem)));
            setReg(self, .al_ax_eax_rax, .bits64, q64);
            setReg(self, .dl_dx_edx_rdx, .bits64, r64);
        },

        // ── mul reg (unsigned) ──
        .mul_reg8 => {
            const b = decodedRegVal(self, d.src_reg, d.src_high8, .bits8);
            const a = regVal(self, .al_ax_eax_rax, .bits8);
            const result = @as(u16, @intCast(a)) * @as(u16, @intCast(b));
            setReg(self, .al_ax_eax_rax, .bits16, result);
            const overflow = result > 0xFF;
            setFlag(self, __process_RFL_CF, overflow);
            setFlag(self, __process_RFL_OF, overflow);
        },
        .mul_reg16 => {
            const b: u16 = @intCast(regVal(self, d.src_reg, .bits16));
            const a: u16 = @intCast(regVal(self, .al_ax_eax_rax, .bits16));
            const result: u32 = @as(u32, a) * @as(u32, b);
            setReg(self, .al_ax_eax_rax, .bits16, @intCast(result & 0xFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits16, @intCast((result >> 16) & 0xFFFF));
        },
        .mul_reg32 => {
            const b = regVal(self, d.src_reg, .bits32);
            const a = regVal(self, .al_ax_eax_rax, .bits32);
            const result = @as(u64, a) * @as(u64, b);
            setReg(self, .al_ax_eax_rax, .bits32, @intCast(result & 0xFFFFFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits32, @intCast((result >> 32) & 0xFFFFFFFF));
        },
        .mul_reg64 => {
            const b = regVal(self, d.src_reg, .bits64);
            const a = regVal(self, .al_ax_eax_rax, .bits64);
            const result = @as(u128, a) * @as(u128, b);
            setReg(self, .al_ax_eax_rax, .bits64, @intCast(result & 0xFFFFFFFFFFFFFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits64, @intCast((result >> 64) & 0xFFFFFFFFFFFFFFFF));
        },

        // ── imul reg (signed) ──
        .imul_reg8 => {
            const a: i8 = @bitCast(@as(u8, @intCast(regVal(self, .al_ax_eax_rax, .bits8))));
            const b: i8 = @bitCast(@as(u8, @intCast(decodedRegVal(self, d.src_reg, d.src_high8, .bits8))));
            const result: i16 = @as(i16, a) * @as(i16, b);
            setReg(self, .al_ax_eax_rax, .bits16, @as(u16, @bitCast(result)));
        },
        .imul_reg16 => {
            const a: i16 = @bitCast(@as(u16, @intCast(regVal(self, .al_ax_eax_rax, .bits16))));
            const b: i16 = @bitCast(@as(u16, @intCast(regVal(self, d.src_reg, .bits16))));
            const result: i32 = @as(i32, a) * @as(i32, b);
            setReg(self, .al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @truncate(result)))));
            setReg(self, .dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(@as(i16, @truncate(result >> 16)))));
        },
        .imul_reg32 => {
            const raw_a: u32 = @intCast(regVal(self, .al_ax_eax_rax, .bits32));
            const raw_b: u32 = @intCast(regVal(self, d.src_reg, .bits32));
            const a: i32 = @bitCast(raw_a);
            const b: i32 = @bitCast(raw_b);
            const result: i64 = @as(i64, a) * @as(i64, b);
            const ru: u64 = @bitCast(result);
            setReg(self, .al_ax_eax_rax, .bits32, @truncate(ru));
            setReg(self, .dl_dx_edx_rdx, .bits32, @truncate(ru >> 32));
        },
        .imul_reg64 => {
            const a: i64 = @bitCast(regVal(self, .al_ax_eax_rax, .bits64));
            const b: i64 = @bitCast(regVal(self, d.src_reg, .bits64));
            const result: i128 = @as(i128, a) * @as(i128, b);
            const ru: u128 = @bitCast(result);
            setReg(self, .al_ax_eax_rax, .bits64, @truncate(ru));
            setReg(self, .dl_dx_edx_rdx, .bits64, @truncate(ru >> 64));
        },

        // ── div reg (unsigned) ──
        .div_reg8 => {
            const divisor = decodedRegVal(self, d.src_reg, d.src_high8, .bits8);
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend = regVal(self, .al_ax_eax_rax, .bits16);
            const quot = dividend / @as(u16, @truncate(divisor));
            const rem = dividend % @as(u16, @truncate(divisor));
            // AL takes the quotient and AH the remainder; the remainder
            // used to land in DL, and a quotient AL cannot hold is #DE.
            if (quot > 0xFF) return process_impl_instruction_decode.raiseDivideError(self);
            setReg(self, .al_ax_eax_rax, .bits16, (rem << 8) | quot);
        },
        .div_reg16 => {
            const divisor = regVal(self, d.src_reg, .bits16);
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo = regVal(self, .al_ax_eax_rax, .bits16);
            const dividend_hi = regVal(self, .dl_dx_edx_rdx, .bits16);
            const dividend = (@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo));
            const quot = dividend / @as(u32, @truncate(divisor));
            const rem = dividend % @as(u32, @truncate(divisor));
            setReg(self, .al_ax_eax_rax, .bits16, @intCast(quot & 0xFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits16, @intCast(rem & 0xFFFF));
        },
        .div_reg32 => {
            const divisor = regVal(self, d.src_reg, .bits32);
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo = regVal(self, .al_ax_eax_rax, .bits32);
            const dividend_hi = regVal(self, .dl_dx_edx_rdx, .bits32);
            const dividend = (@as(u64, dividend_hi) << 32) | dividend_lo;
            const quot = dividend / @as(u64, divisor);
            const rem = dividend % @as(u64, divisor);
            setReg(self, .al_ax_eax_rax, .bits32, @intCast(quot & 0xFFFFFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits32, @intCast(rem & 0xFFFFFFFF));
        },
        .div_reg64 => {
            const divisor = regVal(self, d.src_reg, .bits64);
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo = regVal(self, .al_ax_eax_rax, .bits64);
            const dividend_hi = regVal(self, .dl_dx_edx_rdx, .bits64);
            const dividend = (@as(u128, dividend_hi) << 64) | dividend_lo;
            const quot = dividend / @as(u128, divisor);
            const rem = dividend % @as(u128, divisor);
            setReg(self, .al_ax_eax_rax, .bits64, @intCast(quot & 0xFFFFFFFFFFFFFFFF));
            setReg(self, .dl_dx_edx_rdx, .bits64, @intCast(rem & 0xFFFFFFFFFFFFFFFF));
        },

        // ── idiv reg (signed) ──
        .idiv_reg8 => {
            const divisor: i8 = @bitCast(@as(u8, @intCast(decodedRegVal(self, d.src_reg, d.src_high8, .bits8))));
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend: i16 = @bitCast(@as(u16, @intCast(regVal(self, .al_ax_eax_rax, .bits16))));
            // -32768 / -1 overflows i16 itself, before any AL check.
            if (divisor == -1 and dividend == __process_std.math.minInt(i16)) return process_impl_instruction_decode.raiseDivideError(self);
            const quot = @divTrunc(dividend, @as(i16, divisor));
            const rem = @rem(dividend, @as(i16, divisor));
            // AL takes the quotient and AH the remainder, as for DIV.
            if (quot < __process_std.math.minInt(i8) or quot > __process_std.math.maxInt(i8)) return process_impl_instruction_decode.raiseDivideError(self);
            const quotient_byte: u8 = @bitCast(@as(i8, @intCast(quot)));
            const remainder_byte: u8 = @bitCast(@as(i8, @intCast(rem)));
            setReg(self, .al_ax_eax_rax, .bits16, (@as(u16, remainder_byte) << 8) | quotient_byte);
        },
        .idiv_reg16 => {
            const divisor: i16 = @bitCast(@as(u16, @intCast(regVal(self, d.src_reg, .bits16))));
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo: u16 = @intCast(regVal(self, .al_ax_eax_rax, .bits16));
            const dividend_hi: u16 = @intCast(regVal(self, .dl_dx_edx_rdx, .bits16));
            const dividend: i32 = @bitCast((@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo)));
            const quot = @divTrunc(dividend, @as(i32, divisor));
            const rem = @rem(dividend, @as(i32, divisor));
            {
                const q: i16 = @truncate(quot);
                const r: i16 = @truncate(rem);
                setReg(self, .al_ax_eax_rax, .bits16, @as(u16, @bitCast(q)));
                setReg(self, .dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(r)));
            }
        },
        .idiv_reg32 => {
            const divisor_raw: u32 = @intCast(regVal(self, d.src_reg, .bits32));
            const divisor: i32 = @bitCast(divisor_raw);
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo: u32 = @intCast(regVal(self, .al_ax_eax_rax, .bits32));
            const dividend_hi: u32 = @intCast(regVal(self, .dl_dx_edx_rdx, .bits32));
            const dividend: i64 = @bitCast((@as(u64, dividend_hi) << 32) | @as(u64, dividend_lo));
            const quot = @divTrunc(dividend, @as(i64, divisor));
            const rem = @rem(dividend, @as(i64, divisor));
            setReg(self, .al_ax_eax_rax, .bits32, @as(u64, @bitCast(quot)));
            setReg(self, .dl_dx_edx_rdx, .bits32, @as(u64, @bitCast(rem)));
        },
        .idiv_reg64 => {
            const divisor: i64 = @bitCast(regVal(self, d.src_reg, .bits64));
            if (divisor == 0) return process_impl_instruction_decode.raiseDivideError(self);
            const dividend_lo = regVal(self, .al_ax_eax_rax, .bits64);
            const dividend_hi = regVal(self, .dl_dx_edx_rdx, .bits64);
            const dividend: i128 = @bitCast((@as(u128, dividend_hi) << 64) | dividend_lo);
            const quot = @divTrunc(dividend, @as(i128, divisor));
            const rem = @rem(dividend, @as(i128, divisor));
            const q64b: u64 = @bitCast(@as(i64, @truncate(quot)));
            const r64b: u64 = @bitCast(@as(i64, @truncate(rem)));
            setReg(self, .al_ax_eax_rax, .bits64, q64b);
            setReg(self, .dl_dx_edx_rdx, .bits64, r64b);
        },

        // ── Sign extension ──
        .cbw => {
            // cbw: AL → AX (sign extend). With 0x66: AX → EAX. With REX.W: EAX → RAX (cdqe)
            const al = regVal(self, .al_ax_eax_rax, .bits8);
            const extended = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(al)))));
            setReg(self, .al_ax_eax_rax, .bits16, @as(u16, @bitCast(extended)));
        },
        .cwde => {
            const ax = regVal(self, .al_ax_eax_rax, .bits16);
            const extended = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(ax)))));
            setReg(self, .al_ax_eax_rax, .bits32, @as(u32, @bitCast(extended)));
        },
        .cdqe => {
            const eax = regVal(self, .al_ax_eax_rax, .bits32);
            const extended = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(eax)))));
            setReg(self, .al_ax_eax_rax, .bits64, @as(u64, @bitCast(extended)));
        },
        .cwd => {
            // cwd: AX → DX:AX. With 0x66: EAX → EDX:EAX (cdq). With REX.W: RAX → RDX:RAX (cqo)
            const ax = regVal(self, .al_ax_eax_rax, .bits16);
            const sign = if (ax & 0x8000 != 0) @as(u16, 0xFFFF) else 0;
            setReg(self, .dl_dx_edx_rdx, .bits16, sign);
        },
        .cdq => {
            // cdq: EAX → EDX:EAX (sign extend eax into edx)
            const eax32 = regVal(self, .al_ax_eax_rax, .bits32);
            const sign = if (eax32 & 0x80000000 != 0) @as(u32, 0xFFFFFFFF) else 0;
            setReg(self, .dl_dx_edx_rdx, .bits32, sign);
        },
        .cqo => {
            // cqo: RAX → RDX:RAX (sign extend rax into rdx)
            const rax = regVal(self, .al_ax_eax_rax, .bits64);
            const sign = if (rax & 0x8000000000000000 != 0) @as(u64, 0xFFFFFFFFFFFFFFFF) else 0;
            setReg(self, .dl_dx_edx_rdx, .bits64, sign);
        },

        // ── Zero/sign extend loads ──
        .movzx_reg32_mem8 => {
            const val = if (d.is_reg_form)
                decodedRegVal(self, d.src_reg, d.src_high8, .bits8)
            else
                readMemVal(self, d.addr, .bits8);
            setReg(self, d.dst_reg, d.size, val);
        },
        .movzx_reg32_mem16 => {
            const val = if (d.is_reg_form)
                decodedRegVal(self, d.src_reg, d.src_high8, .bits16)
            else
                readMemVal(self, d.addr, .bits16);
            setReg(self, d.dst_reg, d.size, val);
        },
        .movsx_reg32_mem8 => {
            const val = if (d.is_reg_form)
                @as(i64, @as(i8, @bitCast(@as(u8, @truncate(decodedRegVal(self, d.src_reg, d.src_high8, .bits8))))))
            else
                @as(i64, @as(i8, @bitCast(@as(u8, @truncate(readMemVal(self, d.addr, .bits8))))));
            const dst_size: __process_Size = if (d.size == .bits64) .bits64 else .bits32;
            setReg(self, d.dst_reg, dst_size, @as(u64, @bitCast(val)));
        },
        .movsx_reg32_mem16 => {
            const val = if (d.is_reg_form)
                @as(i64, @as(i16, @bitCast(@as(u16, @truncate(decodedRegVal(self, d.src_reg, d.src_high8, .bits16))))))
            else
                @as(i64, @as(i16, @bitCast(@as(u16, @truncate(readMemVal(self, d.addr, .bits16))))));
            const dst_size: __process_Size = if (d.size == .bits64) .bits64 else .bits32;
            setReg(self, d.dst_reg, dst_size, @as(u64, @bitCast(val)));
        },
        .movsxd_reg64_reg32 => {
            const val = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(regVal(self, d.src_reg, .bits32))))));
            setReg(self, d.dst_reg, .bits64, @as(u64, @bitCast(val)));
        },
        .movsxd_reg64_mem32 => {
            const raw = readMemVal(self, d.addr, .bits32);
            const val = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(raw)))));
            setReg(self, d.dst_reg, .bits64, @as(u64, @bitCast(val)));
        },
        .lea_reg_mem => {
            setReg(self, d.dst_reg, d.size, d.addr);
        },
        .cmovcc_reg_reg => {
            if (evalCond(process_impl_lifecycle.guestContextField(self, "regs").*.rflags, d.cond)) {
                setReg(self, d.dst_reg, d.size, regVal(self, d.src_reg, d.size));
            } else if (d.size == .bits32) {
                setReg(self, d.dst_reg, .bits64, regVal(self, d.dst_reg, .bits32));
            }
        },
        .cmovcc_reg_mem => {
            if (evalCond(process_impl_lifecycle.guestContextField(self, "regs").*.rflags, d.cond)) {
                setReg(self, d.dst_reg, d.size, readMemVal(self, d.addr, d.size));
            } else if (d.size == .bits32) {
                setReg(self, d.dst_reg, .bits64, regVal(self, d.dst_reg, .bits32));
            }
        },
        .setcc_reg8 => {
            setDecodedReg(
                self,
                d.dst_reg,
                d.dst_high8,
                .bits8,
                if (evalCond(process_impl_lifecycle.guestContextField(self, "regs").*.rflags, d.cond)) 1 else 0,
            );
        },
        .setcc_mem8 => {
            writeMemVal(self, d.addr, .bits8, if (evalCond(process_impl_lifecycle.guestContextField(self, "regs").*.rflags, d.cond)) 1 else 0);
        },
        .cmpxchg8b_mem => executeCmpxchg8b(self, d),
        .cmpxchg16b_mem => executeCmpxchg16b(self, d),
        .cmpxchg_mem8_reg8, .cmpxchg_mem16_reg16, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64, .cmpxchg_reg8_reg8, .cmpxchg_reg16_reg16, .cmpxchg_reg32_reg32, .cmpxchg_reg64_reg64 => {
            const size = d.size;
            const accum = regVal(self, .al_ax_eax_rax, size);
            const desired = decodedRegVal(self, d.src_reg, d.src_high8, size);
            const atomic_result = if (d.lock and !d.is_reg_form)
                atomicMemoryCompareExchange(self, d.addr, size, accum, desired)
            else
                null;
            if (atomic_result) |result| {
                setFlagsSub(self, accum, result.previous, accum -% result.previous, size);
                setFlag(self, __process_RFL_ZF, result.exchanged);
                if (!result.exchanged) setDecodedReg(self, .al_ax_eax_rax, false, size, result.previous);
            } else {
                const old = if (d.is_reg_form) regVal(self, d.dst_reg, size) else readMemVal(self, d.addr, size);
                setFlagsSub(self, accum, old, accum -% old, size);
                if ((accum & maskForSize(size)) == (old & maskForSize(size))) {
                    if (d.is_reg_form) {
                        setDecodedReg(self, d.dst_reg, d.dst_high8, size, desired);
                    } else {
                        writeMemVal(self, d.addr, size, desired);
                    }
                    setFlag(self, __process_RFL_ZF, true);
                } else {
                    setDecodedReg(self, .al_ax_eax_rax, false, size, old);
                    setFlag(self, __process_RFL_ZF, false);
                }
            }
        },
        .xchg_mem8_reg8, .xchg_mem32_reg32, .xchg_mem64_reg64, .xchg_reg8_reg8, .xchg_reg32_reg32, .xchg_reg64_reg64 => {
            const size = d.size;
            var stored_atomically = false;
            const old_mem = if (d.is_reg_form)
                decodedRegVal(self, d.dst_reg, d.dst_high8, size)
            else if (atomicMemoryExchange(self, d.addr, size, decodedRegVal(self, d.src_reg, d.src_high8, size))) |previous| blk: {
                stored_atomically = true;
                break :blk previous;
            } else readMemVal(self, d.addr, size);
            const old_reg = decodedRegVal(self, d.src_reg, d.src_high8, size);
            if (d.is_reg_form) {
                setDecodedReg(self, d.dst_reg, d.dst_high8, size, old_reg);
            } else if (!stored_atomically) {
                writeMemVal(self, d.addr, size, old_reg);
            }
            setDecodedReg(self, d.src_reg, d.src_high8, size, old_mem);
        },
        .xadd_mem8_reg8, .xadd_mem32_reg32, .xadd_mem64_reg64 => {
            const old_reg = decodedRegVal(self, d.src_reg, d.src_high8, d.size);
            var stored_atomically = false;
            const old_mem = if (d.lock)
                (if (atomicMemoryFetchAdd(self, d.addr, d.size, old_reg)) |previous| blk: {
                    stored_atomically = true;
                    break :blk previous;
                } else readMemVal(self, d.addr, d.size))
            else
                readMemVal(self, d.addr, d.size);
            const result = old_mem +% old_reg;
            if (!stored_atomically) writeMemVal(self, d.addr, d.size, result);
            setDecodedReg(self, d.src_reg, d.src_high8, d.size, old_mem);
            setFlagsAdd(self, old_mem, old_reg, result, d.size);
        },
        .xorps_xmm_xmm => {
            for (0..16) |i| {
                process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][i] ^= process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][i];
            }
        },
        .movups_xmm_xmm => {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
        },
        .movups_xmm_mem => {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = readMem128(self, d.addr);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
        },
        .movups_mem_xmm => {
            writeMem128(self, d.addr, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src]);
        },
        .movaps_xmm_xmm => {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
        },
        .movaps_xmm_mem => {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = readMem128(self, d.addr);
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
        },
        .movaps_mem_xmm => {
            writeMem128(self, d.addr, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src]);
        },

        // ── imul r64, r/m64 (0F AF) ──
        .imul_reg64_mem64 => {
            const a = regVal(self, d.dst_reg, .bits64);
            const b = readMemVal(self, d.addr, .bits64);
            writeImulNarrowResult(self, d.dst_reg, .bits64, signedInteger(a, .bits64) * signedInteger(b, .bits64));
        },
        .imul_reg64_reg64 => {
            const a = regVal(self, d.dst_reg, .bits64);
            const b = regVal(self, d.src_reg, .bits64);
            writeImulNarrowResult(self, d.dst_reg, .bits64, signedInteger(a, .bits64) * signedInteger(b, .bits64));
        },
        .imul_reg32_mem32 => {
            const a = regVal(self, d.dst_reg, .bits32);
            const b = readMemVal(self, d.addr, .bits32);
            writeImulNarrowResult(self, d.dst_reg, .bits32, signedInteger(a, .bits32) * signedInteger(b, .bits32));
        },
        .imul_reg32_reg32 => {
            const a = regVal(self, d.dst_reg, .bits32);
            const b = regVal(self, d.src_reg, .bits32);
            writeImulNarrowResult(self, d.dst_reg, .bits32, signedInteger(a, .bits32) * signedInteger(b, .bits32));
        },
        // IMUL r16, r/m16 writes only the low word of the destination.
        .imul_reg16_mem16 => {
            const a = regVal(self, d.dst_reg, .bits16);
            const b = readMemVal(self, d.addr, .bits16);
            writeImulNarrowResult(self, d.dst_reg, .bits16, signedInteger(a, .bits16) * signedInteger(b, .bits16));
        },
        .imul_reg16_reg16 => {
            const a = regVal(self, d.dst_reg, .bits16);
            const b = regVal(self, d.src_reg, .bits16);
            writeImulNarrowResult(self, d.dst_reg, .bits16, signedInteger(a, .bits16) * signedInteger(b, .bits16));
        },

        // ── imul r, r/m, imm8/imm16/imm32 (0x6B/0x69) ──
        .imul_reg16_mem16_imm8,
        .imul_reg16_reg16_imm8,
        .imul_reg16_mem16_imm16,
        .imul_reg16_reg16_imm16,
        .imul_reg32_mem32_imm8,
        .imul_reg32_reg32_imm8,
        .imul_reg32_mem32_imm32,
        .imul_reg32_reg32_imm32,
        .imul_reg64_mem64_imm8,
        .imul_reg64_reg64_imm8,
        .imul_reg64_mem64_imm32,
        .imul_reg64_reg64_imm32,
        => {
            const size = imulImmediateSize(d.op);
            const source = if (d.is_reg_form)
                regVal(self, d.src_reg, size)
            else
                readMemVal(self, d.addr, size);
            writeImulNarrowResult(self, d.dst_reg, size, signedInteger(source, size) * signedImulImmediate(d));
        },

        // ── Stack and calls ──
        .call_rel32 => {
            const rel = @as(i64, @bitCast(d.imm));
            const transfer = __process_x64_decoder.highway.relativeControl(.call, process_impl_lifecycle.guestContextField(self, "regs").*.rip, d.len, rel, true);
            const next_rip = transfer.return_address.?;
            const target_rip = transfer.target;
            if (process_impl_windows_sync.tryWindowsPthreadConditionShim(self, target_rip, next_rip)) return;
            if (tryXeniaTabulateAccelerator(self, target_rip, next_rip)) return;
            if (tryXeniaSha1Accelerator(self, target_rip, next_rip)) return;
            if (tryXeniaRijndaelAccelerator(self, target_rip, next_rip)) return;
            process_impl_guest_diagnostics.noteGuestMilestoneEntry(self, target_rip);
            process_impl_guest_diagnostics.noteXeniaEmulatorSetupCall(self, target_rip, next_rip);
            process_impl_kernel_services.noteGuestKernelCall(self, target_rip);
            if (process_impl_kernel_services.tryXeniaKeyboardInputShim(self, target_rip, next_rip)) return;
            process_impl_kernel_services.traceWindowsCallbackCall(self, "direct", target_rip, process_impl_lifecycle.guestContextField(self, "regs").*.rip, next_rip);
            if (self.trace_windows_threads and target_rip == 0x1405151af) {
                __process_log.info("Windows thread call target pthread_self: source_rip=0x{x} rsp_before=0x{x} return_rip=0x{x} stack_before=0x{x}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
                    next_rip,
                    process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
                });
            }
            if (__process_x64_linux_runtime.tryLocalFunctionShim(self, target_rip, next_rip)) {
                return;
            }
            noteGuestCall(self, .direct, target_rip, next_rip);
            if (self.call_probes.armed()) process_impl_guest_diagnostics.noteCallProbeEntry(self, target_rip, next_rip);
            process_impl_guest_memory.push(self, next_rip);
            process_impl_lifecycle.guestContextField(self, "regs").*.rip = target_rip;
            return;
        },
        .call_mem64, .call_reg64 => {
            const next_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip + d.len;
            if (d.op == .call_mem64 and process_impl_kernel_services.tryXeniaStaleMutantBackingDelete(self, d, next_rip)) return;
            // This exact Xenia call dereferences the null backing member
            // through [rax+0x18]. Recognize it before readMemVal so the
            // expected X_MUTANT::ReleaseMutant fallback does not enter
            // generic null-page handling first.
            if (d.op == .call_mem64 and process_impl_kernel_services.tryXeniaMissingNativeMutantRelease(self, d, next_rip)) return;
            if (d.op == .call_mem64) {
                if (process_impl_kernel_services.windowsImportStubForIat(self, d.addr)) |stub| {
                    // The direct call [IAT] path does not push a return
                    // address: the Windows runtime receives `next_rip`
                    // explicitly. Apply the same ABI containment as the
                    // synthetic-stub path, with an unchanged RSP.
                    const entry_regs = process_impl_lifecycle.guestContextField(self, "regs");
                    const entry_rsp = entry_regs.rsp;
                    const entry_slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
                    const saved = __process_windows_guest_abi.Snapshot.capture(entry_regs, process_impl_lifecycle.guestContextField(self, "xmm"));
                    process_impl_kernel_services.verifyWindowsImportIatAtDispatch(self, stub);
                    if (__process_x64_linux_runtime.tryDynamicFunctionShim(self, d.addr, next_rip)) {
                        process_impl_kernel_services.recordWindowsImportAbiReturn(self, stub, &saved, entry_regs, entry_rsp, next_rip, 0, entry_slot, entry_regs.rip);
                        return;
                    }
                } else if (__process_x64_linux_runtime.tryDynamicFunctionShim(self, d.addr, next_rip)) {
                    return;
                }
            }
            const target = if (d.op == .call_reg64)
                regVal(self, d.dst_reg, .bits64)
            else
                readMemVal(self, d.addr, .bits64);
            if (process_impl_windows_sync.tryWindowsPthreadConditionShim(self, target, next_rip)) return;
            process_impl_kernel_services.traceWindowsCallbackCall(self, if (d.op == .call_reg64) "indirect-register" else "indirect-memory", target, if (d.op == .call_reg64) regVal(self, d.dst_reg, .bits64) else d.addr, next_rip);
            if (__process_shouldTraceRip(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip)) {
                __process_log.info("trace indirect call target rip=0x{x} op={s} operand=0x{x} loaded_target=0x{x} bytes={any} next_rip=0x{x}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    @tagName(d.op),
                    if (d.op == .call_reg64) regVal(self, d.dst_reg, .bits64) else d.addr,
                    target,
                    if (d.op == .call_mem64) guestMemoryConst(self, d.addr, 8) orelse &[_]u8{} else &[_]u8{},
                    next_rip,
                });
            }
            if (target == 0 and d.op == .call_mem64 and __process_x64_linux_runtime.tryLibcStartMainTrampoline(self, d, next_rip)) {
                return;
            }
            if (target == 0) {
                const is_memory_call = d.op == .call_mem64;
                const operand = if (is_memory_call) d.addr else regVal(self, d.dst_reg, .bits64);
                const base_name = if (is_memory_call and d.sib_has_base) @tagName(d.sib_base_reg) else "<none>";
                const base_value = if (is_memory_call and d.sib_has_base)
                    regVal(self, d.sib_base_reg, .bits64)
                else
                    0;
                const index_name = if (is_memory_call and d.sib_has_index) @tagName(d.sib_index_reg) else "<none>";
                const index_value = if (is_memory_call and d.sib_has_index)
                    regVal(self, d.sib_index_reg, .bits64)
                else
                    0;
                var visible_storage: [16]u8 = undefined;
                const visible_bytes = process_impl_instruction_decode.guestInstructionBytes(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &visible_storage);
                var backing_storage: [16]u8 = undefined;
                var backing_bytes: []const u8 = &.{};
                if (visible_bytes.len != 0) {
                    if (guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, @intCast(visible_bytes.len))) |backing_source| {
                        const backing_len = @min(visible_bytes.len, backing_source.len);
                        if (backing_len != 0) {
                            __process_tso_memory.copyBackingCoordinated(backing_storage[0..backing_len], backing_source[0..backing_len]);
                            backing_bytes = backing_storage[0..backing_len];
                        }
                    }
                }
                const visible_decode = __process_decodeInsn(visible_bytes);
                const backing_decode = __process_decodeInsn(backing_bytes);
                __process_log.err("PE64 ZERO INDIRECT CALL BYTE AUDIT: rip=0x{x} executed={s}/{d} register={s} loaded_target=0x{x} visible_decode={s}/{d} visible_bytes={any} backing_decode={s}/{d} backing_bytes={any} pending_stores={d} parallel={} image_generation={d} executable_write_events={d}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    @tagName(d.op),
                    d.len,
                    if (is_memory_call) "<memory>" else @tagName(d.dst_reg),
                    target,
                    @tagName(visible_decode.op),
                    visible_decode.len,
                    visible_bytes,
                    @tagName(backing_decode.op),
                    backing_decode.len,
                    backing_bytes,
                    __process_tso_memory.activePendingStores(),
                    self.parallel_guest_execution,
                    self.windows_image_code_generation,
                    self.windows_executable_image_write_events.load(.acquire),
                });
                const instruction_bytes = guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, @as(usize, d.len)) orelse &[_]u8{};
                __process_log.err("unresolved indirect call at rip=0x{x} op={s} source={s} effective=0x{x} loaded_target=0x{x} base={s}:0x{x} index={s}:0x{x} scale={d} rip_relative={} rsp=0x{x} return=0x{x} step={d} last_rip=0x{x} regs=[rax=0x{x},rcx=0x{x},rdx=0x{x},r8=0x{x},r9=0x{x}] bytes={any}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    @tagName(d.op),
                    if (is_memory_call) "memory" else "register",
                    operand,
                    target,
                    base_name,
                    base_value,
                    index_name,
                    index_value,
                    d.sib_scale,
                    d.rip_relative,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
                    process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
                    process_impl_lifecycle.observedExecutionSteps(self),
                    process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rax,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
                    process_impl_lifecycle.guestContextField(self, "regs").*.r8,
                    process_impl_lifecycle.guestContextField(self, "regs").*.r9,
                    instruction_bytes,
                });
                process_impl_lifecycle.markFaulted(self);
                self.exit_code = 127;
                self.termination_reason = .invalid_control_flow_target;
                process_impl_lifecycle.markTerminated(self);
                return;
            }
            if (self.trace_windows_threads and target == 0x1405151af) {
                __process_log.info("Windows thread indirect call target pthread_self: source_rip=0x{x} rsp_before=0x{x} return_rip=0x{x} stack_before=0x{x}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
                    next_rip,
                    process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
                });
            }
            process_impl_guest_diagnostics.noteGuestMilestoneEntry(self, target);
            process_impl_guest_diagnostics.noteXeniaEmulatorSetupCall(self, target, next_rip);
            process_impl_kernel_services.noteGuestKernelCall(self, target);
            if (process_impl_kernel_services.tryXeniaKeyboardInputShim(self, target, next_rip)) return;
            noteGuestCall(self, .indirect, target, next_rip);
            if (self.call_probes.armed()) process_impl_guest_diagnostics.noteCallProbeEntry(self, target, next_rip);
            process_impl_guest_memory.push(self, next_rip);
            process_impl_lifecycle.guestContextField(self, "regs").*.rip = target;
            return;
        },
        .ret => {
            const return_rip = process_impl_guest_memory.pop(self);
            // C2 iw performs RET's normal eight-byte pop followed by an
            // unsigned 16-bit caller-argument cleanup. Use wrapping
            // arithmetic, as the architectural RSP update is 64-bit.
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp +%= (d.imm & 0xFFFF);
            if (self.guest_return_captures_armed != 0) process_impl_guest_diagnostics.completeGuestReturnCapture(self);
            process_impl_guest_diagnostics.noteXeniaEmulatorSetupReturn(self, return_rip);
            if (self.trace_string_memory and
                process_impl_lifecycle.guestContextField(self, "regs").*.rip >= 0x140134c80 and process_impl_lifecycle.guestContextField(self, "regs").*.rip < 0x140135400)
            {
                const string_object = process_impl_lifecycle.guestContextField(self, "regs").*.rax;
                const data_address = process_impl_guest_memory.read64(self, string_object);
                const string_length = process_impl_guest_memory.read64(self, string_object +| 8);
                const bytes = if (string_length <= 64)
                    guestMemoryConst(self, data_address, string_length) orelse &.{}
                else
                    &.{};
                __process_log.info("PE EscapeString return object=0x{x} data=0x{x} length={d} bytes={any}", .{
                    string_object,
                    data_address,
                    string_length,
                    bytes,
                });
            }
            if (return_rip == 0 and process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* != null) {
                // The cooperative worker service recognizes this exact
                // return boundary and completes the worker after the
                // instruction.  It is not an execution error unless a
                // non-worker reaches the same null return.
                __process_log.info("Windows guest ret produced the worker completion marker: thread=0x{x} source_rip=0x{x} rsp_after_return=0x{x} rbp=0x{x} stack_next=0x{x}", .{
                    process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
                    process_impl_lifecycle.guestContextField(self, "regs").*.rbp,
                    process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
                });
            }
            process_impl_lifecycle.guestContextField(self, "regs").*.rip = return_rip;
            noteGuestReturn(self, return_rip);
            return;
        },
        .push_reg => {
            process_impl_guest_memory.push(self, regVal(self, d.src_reg, .bits64));
        },
        .push_mem64 => {
            process_impl_guest_memory.push(self, readMemVal(self, d.addr, .bits64));
        },
        .push_imm => {
            process_impl_guest_memory.push(self, d.imm);
        },
        .pop_reg => {
            setReg(self, d.dst_reg, .bits64, process_impl_guest_memory.pop(self));
        },
        .pop_mem64 => {
            const val = process_impl_guest_memory.pop(self);
            writeMemVal(self, d.addr, .bits64, val);
        },
        .hlt => {
            const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
            // Synthetic HLT instructions are used as ordinary stop
            // sentinels throughout the interpreter/JIT tests. Preserve
            // their historical stop behavior and keep the production
            // PE64 diagnostic scoped to an instruction inside the
            // loaded image, where a privileged halt is abnormal.
            if (self.windows_runtime_enabled and self.image_low != 0 and
                regs.rip >= self.image_low and regs.rip < self.image_high)
            {
                const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
                const thread = process_impl_lifecycle.guestContextField(self, "active_guest_thread").*;
                var at_storage: [128]u8 = undefined;
                var instruction: [16]u8 = undefined;
                const instruction_bytes = process_impl_instruction_decode.guestInstructionBytes(self, regs.rip, &instruction);
                __process_log.err("PE64 HLT TERMINATION: privileged halt reached in guest user mode rip=0x{x} at={s} thread=0x{x} slot={?d} step={d} rax=0x{x} rsp=0x{x} stack_return=0x{x} bytes={any}; HLT is abnormal inside the loaded image, but this path retains the established non-faulting stop contract", .{
                    regs.rip,
                    process_impl_kernel_services.describeGuestAddressOrUnnamed(self, regs.rip, &at_storage),
                    thread,
                    slot,
                    process_impl_lifecycle.observedExecutionSteps(self),
                    regs.rax,
                    regs.rsp,
                    process_impl_guest_memory.read64(self, regs.rsp),
                    instruction_bytes,
                });
                self.termination_reason = .hlt;
            }
            self.exit_code = regs.rax;
            process_impl_lifecycle.markTerminated(self);
        },

        // ── Jump short rel8 ──
        .jmp_rel8 => {
            const target = __process_x64_decoder.highway.relativeControl(.jump, process_impl_lifecycle.guestContextField(self, "regs").*.rip, d.len, @bitCast(d.imm), true).target;
            // libstdc++'s condition_variable::wait is a tiny tail-call
            // wrapper around the PE-local pthread_cond_wait.  There is
            // no call-site return address to pass explicitly here; the
            // wrapper preserves its caller's address at [rsp].  Let the
            // Rosetta condition policy own this boundary before the
            // host-oriented image implementation can return spuriously.
            if (process_impl_windows_sync.tryWindowsPthreadConditionShim(self, target, null)) return;
            process_impl_lifecycle.guestContextField(self, "regs").*.rip = target;
            return;
        },
        .jmp_mem64, .jmp_reg64 => {
            // A thunk's `jmp [IAT]` into a lock-free import lane: its
            // caller's return address is on the stack. Without this the
            // lane never saw a thunked call, because the import path
            // below has no direct return address to give it.
            if (d.op == .jmp_mem64 and process_impl_kernel_services.tryImportSlotFastTransfer(self, d.addr, 0)) return;
            if (d.op == .jmp_mem64 and __process_x64_linux_runtime.tryDynamicFunctionShim(self, d.addr, null)) {
                return;
            }
            const target = if (d.op == .jmp_reg64)
                regVal(self, d.dst_reg, .bits64)
            else
                readMemVal(self, d.addr, .bits64);
            if (process_impl_windows_sync.tryWindowsPthreadConditionShim(self, target, null)) return;
            if (target == 0) {
                const operand = if (d.op == .jmp_reg64)
                    regVal(self, d.dst_reg, .bits64)
                else
                    d.addr;
                __process_log.err("unresolved indirect jump at rip=0x{x} operand=0x{x} source={s}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    operand,
                    if (d.op == .jmp_reg64) "register" else "memory",
                });
                process_impl_lifecycle.markFaulted(self);
                self.exit_code = 127;
                process_impl_lifecycle.markTerminated(self);
                return;
            }
            // A tail jump into a kernel export shim is the title asking
            // for something just as surely as a call is, and it is how a
            // translator's dispatch table usually reaches its handler.
            // The milestone hook deliberately skips jumps because a bit
            // test per jump would cost more than twenty-two counters are
            // worth; the census rejects an address outside its armed
            // range in two comparisons, and an indirect jump is rare
            // enough that the rest is free.
            process_impl_kernel_services.noteGuestKernelTailJump(self, target);
            process_impl_lifecycle.guestContextField(self, "regs").*.rip = target;
            return;
        },

        // ── Conditional jump rel8 ──
        .jcc_rel8 => {
            const taken = evalCond(process_impl_lifecycle.guestContextField(self, "regs").*.rflags, d.cond);
            if (__process_shouldTraceRip(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip)) __process_log.info("conditional branch rip=0x{x} cond={s} rflags=0x{x} zf={d} taken={}", .{
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                @tagName(d.cond),
                process_impl_lifecycle.guestContextField(self, "regs").*.rflags,
                @intFromBool((process_impl_lifecycle.guestContextField(self, "regs").*.rflags & __process_RFL_ZF) != 0),
                taken,
            });
            if (taken) {
                process_impl_lifecycle.guestContextField(self, "regs").*.rip = __process_x64_decoder.highway.relativeControl(.conditional_jump, process_impl_lifecycle.guestContextField(self, "regs").*.rip, d.len, @bitCast(d.addr), taken).target;
                return;
            }
        },
        .jcc_rel32 => {
            const taken = evalCond(process_impl_lifecycle.guestContextField(self, "regs").*.rflags, d.cond);
            if (__process_shouldTraceRip(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip)) __process_log.info("conditional branch rip=0x{x} cond={s} rflags=0x{x} zf={d} taken={}", .{
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                @tagName(d.cond),
                process_impl_lifecycle.guestContextField(self, "regs").*.rflags,
                @intFromBool((process_impl_lifecycle.guestContextField(self, "regs").*.rflags & __process_RFL_ZF) != 0),
                taken,
            });
            if (taken) {
                process_impl_lifecycle.guestContextField(self, "regs").*.rip = __process_x64_decoder.highway.relativeControl(.conditional_jump, process_impl_lifecycle.guestContextField(self, "regs").*.rip, d.len, @bitCast(d.addr), taken).target;
                return;
            }
        },

        // ── Syscall ──
        .syscall => {
            const syscall_number = process_impl_lifecycle.guestContextField(self, "regs").*.rax;
            const boundary = __process_x64_decoder.highway.systemBoundary(.elf64, .syscall, syscall_number, "");
            if (boundary.disposition != .forward) {
                process_impl_lifecycle.markFaulted(self);
                process_impl_lifecycle.markTerminated(self);
                self.exit_code = 126;
                return;
            }
            const syscall_fd = process_impl_lifecycle.guestContextField(self, "regs").*.rdi;
            const syscall_buf = process_impl_lifecycle.guestContextField(self, "regs").*.rsi;
            const syscall_count = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
            process_impl_syscalls.invokeLinuxSyscall(
                self,
                syscall_number,
                process_impl_lifecycle.guestContextField(self, "regs").*.rdi,
                process_impl_lifecycle.guestContextField(self, "regs").*.rsi,
                process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
                process_impl_lifecycle.guestContextField(self, "regs").*.r10,
                process_impl_lifecycle.guestContextField(self, "regs").*.r8,
                process_impl_lifecycle.guestContextField(self, "regs").*.r9,
            );
            __process_x64_guest_abi.diagnoseSyscall(self, syscall_number, syscall_fd, syscall_buf, syscall_count, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
        },
        .ud2 => {
            reportGuestUd2(self);
            process_impl_lifecycle.markFaulted(self);
            self.exit_code = 127;
            self.termination_reason = .invalid_instruction;
            process_impl_lifecycle.markTerminated(self);
            return;
        },
        .cpuid => {
            const result = __process_x64_decoder.emulatedCpuid(@truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax), @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rcx));
            setReg(self, .al_ax_eax_rax, .bits32, result.eax);
            setReg(self, .bl_bx_ebx_rbx, .bits32, result.ebx);
            setReg(self, .cl_cx_ecx_rcx, .bits32, result.ecx);
            setReg(self, .dl_dx_edx_rdx, .bits32, result.edx);
        },
        .xgetbv => {
            const value = if (@as(u32, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rcx)) == 0) __process_x64_decoder.emulatedXcr0() else 0;
            setReg(self, .al_ax_eax_rax, .bits32, @truncate(value));
            setReg(self, .dl_dx_edx_rdx, .bits32, @truncate(value >> 32));
        },
        .rdtsc, .rdtscp => {
            const ticks = process_impl_lifecycle.observedExecutionSteps(self);
            setReg(self, .al_ax_eax_rax, .bits32, @truncate(ticks));
            setReg(self, .dl_dx_edx_rdx, .bits32, @truncate(ticks >> 32));
            if (d.op == .rdtscp) setReg(self, .cl_cx_ecx_rcx, .bits32, 0);
        },
        .mfence => __process_tso_memory.memoryFence(),
        .lfence => __process_tso_memory.loadFence(),
        .sfence => __process_tso_memory.storeFence(),
        .emms, .wait => {},
        .kmovw, .kmovd, .kmovq => {
            const is_word = d.op == .kmovw;
            const register_size: __process_Size = if (d.op == .kmovq) .bits64 else .bits32;
            const memory_size: __process_Size = if (is_word) .bits16 else register_size;
            const mask: u64 = if (is_word) 0xFFFF else if (d.op == .kmovq) __process_std.math.maxInt(u64) else 0xFFFF_FFFF;
            if (d.mask_to_gpr) {
                const value = process_impl_lifecycle.guestContextField(self, "k").*[d.src_k] & mask;
                if (d.is_reg_form)
                    setReg(self, d.dst_reg, register_size, value)
                else
                    writeMemVal(self, d.addr, memory_size, value);
            } else {
                const value = if (d.is_reg_form)
                    regVal(self, d.src_reg, register_size)
                else
                    readMemVal(self, d.addr, memory_size);
                process_impl_lifecycle.guestContextField(self, "k").*[d.dst_k] = value & mask;
            }
        },
        .vmovd_xmm_reg32, .vmovd_xmm_mem32 => {
            const value: u32 = @truncate(if (d.op == .vmovd_xmm_reg32)
                regVal(self, d.src_reg, .bits32)
            else
                readMemVal(self, d.addr, .bits32));
            @memset(&process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst], 0);
            __process_std.mem.writeInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..4], value, .little);
        },
        .vmovd_reg32_xmm, .vmovd_mem32_xmm => {
            const value = __process_std.mem.readInt(u32, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..4], .little);
            if (d.op == .vmovd_reg32_xmm) {
                setReg(self, d.dst_reg, .bits32, value);
            } else {
                writeMemVal(self, d.addr, .bits32, value);
            }
        },
        .vmovq_xmm_reg64, .vmovq_xmm_mem64 => {
            const value = if (d.op == .vmovq_xmm_reg64)
                regVal(self, d.src_reg, .bits64)
            else
                readMemVal(self, d.addr, .bits64);
            @memset(&process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst], 0);
            __process_std.mem.writeInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][0..8], value, .little);
            // VEX.128 zeroes the destination's upper YMM half; legacy
            // MOVQ, which shares this op, leaves it alone. The block
            // translator already did this, so the two disagreed.
            if (!d.legacy_sse) @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
        },
        .vmovq_reg64_xmm, .vmovq_mem64_xmm => {
            const value = __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src][0..8], .little);
            if (d.op == .vmovq_reg64_xmm) {
                setReg(self, d.dst_reg, .bits64, value);
            } else {
                writeMemVal(self, d.addr, .bits64, value);
            }
        },
        .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8 => {
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            const value: u8 = @truncate(if (d.op == .vpinsrb_xmm_xmm_reg32)
                regVal(self, d.src_reg, .bits32)
            else
                readMemVal(self, d.addr, .bits8));
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst][@intCast(d.imm & 0x0F)] = value;
        },
        .vpshufb => {
            const source = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            const mask = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2] else readMem128(self, d.addr);
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = __process_shuffleBytes(source, mask);
        },
        .vpshufd => executeVpshufd(self, d),
        .vshufps => {
            // The upper lane applies the same control to the sources'
            // upper halves; VEX.128 clears it, legacy SHUFPS keeps it.
            const control: u8 = @truncate(d.imm);
            const lhs = process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
            const rhs = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_src2] else readMem128(self, d.addr);
            const result = __process_shufflePackedSinglesLane(lhs, rhs, control);
            if (d.vector_256) {
                const lhs_high = process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src];
                const rhs_high = if (d.is_reg_form) process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_src2] else readMem128(self, d.addr +% 16);
                process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst] = __process_shufflePackedSinglesLane(lhs_high, rhs_high, control);
            } else if (!d.legacy_sse) {
                @memset(&process_impl_lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
            }
            process_impl_lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result;
        },
        .vpmuludq, .vpblendw, .vpinsrd, .vpinsrq, .vpinsrw, .vpunpckhbw, .vpunpckhwd, .vpunpckhdq, .vpunpcklbw, .vpunpcklwd, .vpslld, .vpsllq, .vpsllw, .vpslldq, .vpsrld, .vpsrlq, .vpsrlw, .vpsrldq, .vpsraw, .vpsrad, .vpsubb, .vpsubd, .vpsubq, .vpsubw, .vpaddb, .vpaddd, .vpaddq, .vpaddw, .vpmullw, .add_accum_imm, .or_accum_imm, .adc_accum_imm, .sbb_accum_imm, .and_accum_imm, .sub_accum_imm, .xor_accum_imm, .cmp_accum_imm, .vmovdqu_xmm_xmm, .vmovdqu_xmm_mem, .vmovdqu_mem_xmm, .vmovdqa_xmm_xmm, .vmovdqa_xmm_mem, .vmovdqa_mem_xmm, .vmovups_xmm_xmm, .vmovups_xmm_mem, .vmovups_mem_xmm, .vmovaps_xmm_xmm, .vmovaps_xmm_mem, .vmovaps_mem_xmm, .vmovupd_xmm_xmm, .vmovupd_xmm_mem, .vmovupd_mem_xmm, .vmovapd_xmm_xmm, .vmovapd_xmm_mem, .vmovapd_mem_xmm, .vmovss_xmm_mem, .vmovss_mem_xmm, .vmovsd_xmm_mem, .vmovsd_mem_xmm, .vmovlps_xmm_xmm_mem64, .vmovlps_mem64_xmm, .vmovlpd_xmm_xmm_mem64, .vmovlpd_mem64_xmm, .vmovhps_xmm_xmm_mem64, .vmovhps_mem64_xmm, .vmovhpd_xmm_xmm_mem64, .vmovhpd_mem64_xmm, .vmovshdup, .vmovsldup, .vmovddup, .vmovdqu_ymm_ymm, .vmovdqu_ymm_mem, .vmovdqu_mem_ymm, .vmovdqa_ymm_ymm, .vmovdqa_ymm_mem, .vmovdqa_mem_ymm, .vmovups_ymm_ymm, .vmovups_ymm_mem, .vmovups_mem_ymm, .vmovaps_ymm_ymm, .vmovaps_ymm_mem, .vmovaps_mem_ymm, .vmovupd_ymm_ymm, .vmovupd_ymm_mem, .vmovupd_mem_ymm, .vmovapd_ymm_ymm, .vmovapd_ymm_mem, .vmovapd_mem_ymm, .vzeroupper, .pmovmskb, .vpmovmskb, .vpmovmskb_ymm, .vcvtsi2ss_xmm_reg, .vcvtsi2ss_xmm_mem, .vcvtsi2sd_xmm_reg, .vcvtsi2sd_xmm_mem, .vcvtss2sd, .vcvtsd2ss, .vaddss, .vaddsd, .vaddps, .vaddpd, .vmulss, .vmulsd, .vmulps, .vmulpd, .vsubss, .vsubsd, .vsubps, .vsubpd, .vdivss, .vdivsd, .vdivps, .vdivpd, .vucomiss, .vucomisd, .vroundss, .vroundsd, .vroundps, .vroundpd, .vcvttss2si, .vcvttsd2si, .vcvtss2si, .vcvtsd2si, .vandps, .vandpd, .vandnps, .vandnpd, .vorps, .vorpd, .vxorps, .vxorpd, .vpor, .vpand, .vpandn, .vpxor, .vpcmpeqb, .vpcmpeqw, .vpcmpeqd, .vpcmpeqq, .vpcmpgtb, .vpcmpgtw, .vpcmpgtd, .vpcmpgtq, .vpunpckldq, .vpunpcklqdq, .vpunpckhqdq, .vmovhlps, .vmovlhps, .vmovmskps, .vmovmskpd, .vsqrtps, .vsqrtpd, .vsqrtss, .vsqrtsd, .vunpcklps, .vunpckhps, .vunpcklpd, .vunpckhpd, .vcvtps2pd, .vcvtpd2ps, .vptest, .vtestps, .vtestpd => executeVectorTest(self, d),
        // Legacy scalar register moves are consumed by
        // executeCleoVectorMove above. Keep explicit cases here because
        // this exhaustive fallback switch must still name every Op;
        // reaching either case would mean the handler's contract changed.
        .vmovss_xmm_xmm, .vmovsd_xmm_xmm, .vmovss_xmm_xmm_xmm, .vmovsd_xmm_xmm_xmm => unreachable,
        .vmovq_xmm_xmm => unreachable,
        .vpdpbusd => executeVpdpbusd(self, d),
        .vextractf128, .vinsertf128, .vinserti128 => executeVexLane128(self, d),
        .vperm2f128 => executeVexPermute2x128(self, d),
        .vphminposuw => executeVphminposuw(self, d),
        .vpsadbw,
        .vpmaddubsw,
        .vpmaddwd,
        .vpcmpb,
        .vpmovqd,
        .vextracti32x4,
        .vextracti64x4,
        .movdir64b,
        .vpermilpd,
        // SSSE3/AVX2 integer 0x38 ops (not decoded for ELF)
        .vpsignb,
        .vpsignw,
        .vpsignd,
        .vpabsb,
        .vpabsw,
        .vpabsd,
        .vpsrlvw,
        .vpsravw,
        .vpsllvw,
        .vpmovsxbw,
        .vpmovsxbd,
        .vpmovsxbq,
        .vpmovsxwd,
        .vpmovsxwq,
        .vpmovsxdq,
        .vpmovzxbw,
        .vpmovzxbd,
        .vpmovzxbq,
        .vpmovzxwd,
        .vpmovzxwq,
        .vpmovzxdq,
        .vpmuldq,
        .vpacksswb,
        .vpackuswb,
        .vpackusdw,
        .vpermd,
        .vpextrb,
        .vpextrw,
        .vpextrd,
        .vpextrq,
        .vpminsb,
        .vpminsd,
        .vpminuw,
        .vpminud,
        .vpminub,
        .vpmaxsb,
        .vpmaxsd,
        .vpmaxuw,
        .vpmaxud,
        .vpmaxub,
        .vpsubsb,
        .vpsubsw,
        .vpsubusw,
        .vpaddusb,
        .vpaddusw,
        .vpsubusb,
        .vpavgb,
        .vpavgw,
        .vpminsw,
        .vpaddsb,
        .vpaddsw,
        .vpmulhw,
        .vpmulhuw,
        .vpmulld_38,
        .vphaddw,
        .vphaddd,
        .vphaddsw,
        .vphsubw,
        .vphsubd,
        .vphsubsw,
        .vfmadd132ps,
        .vfmadd132pd,
        .vfmadd213ps,
        .vfmadd213pd,
        .vfmadd231ps,
        .vfmadd231pd,
        .vfmsub132ps,
        .vfmsub132pd,
        .vfmsub213ps,
        .vfmsub213pd,
        .vfmsub231ps,
        .vfmsub231pd,
        .vfmaddsub132ps,
        .vfmaddsub132pd,
        .vfmaddsub213ps,
        .vfmaddsub213pd,
        .vfmaddsub231ps,
        .vfmaddsub231pd,
        .vfmsubadd132ps,
        .vfmsubadd132pd,
        .vfmsubadd213ps,
        .vfmsubadd213pd,
        .vfmsubadd231ps,
        .vfmsubadd231pd,
        .vpsrlvd,
        .vpsravd,
        .vpsllvd,
        .vblendvps,
        .vblendvpd,
        .vpblendvb,
        .vpalignr,
        .vmaskmovps_load,
        .vmaskmovps_store,
        .vmaskmovpd_load,
        .vmaskmovpd_store,
        .vpermps,
        .vinsertps,
        // AVX SIMD float min/max
        .vminps,
        .vminpd,
        .vminss,
        .vminsd,
        .vmaxps,
        .vmaxpd,
        .vmaxss,
        .vmaxsd,
        // AVX horizontal / reciprocal
        .vhaddps,
        .vhaddpd,
        .vhsubps,
        .vhsubpd,
        .vrcpps,
        .vrcpss,
        .vrsqrtps,
        .vrsqrtss,
        // AVX SIMD compare
        .vcmpps,
        .vcmppd,
        .vcmpss,
        .vcmpsd,
        // AVX512/AVX extensions (not yet decoded for ELF execution)
        .vscalefps,
        .vscalefpd,
        .vrangeps,
        .vrangepd,
        .vfixupimmps,
        .vfixupimmpd,
        .vcompressps,
        .vcompresspd,
        .vexpandps,
        .vexpandpd,
        .vbroadcastss,
        .vbroadcastsd,
        .vbroadcastf128,
        .vbroadcasti128,
        .vpermi2d,
        .vpermi2q,
        .vpermi2ps,
        .vpermi2pd,
        .vpermt2d,
        .vpermt2q,
        .vpermt2ps,
        .vpermt2pd,
        .vgatherdps,
        .vgatherdpd,
        .vgatherqps,
        .vgatherqpd,
        .vpgatherdd,
        .vpgatherdq,
        .vscatterdps,
        .vscatterdpd,
        .vscatterqps,
        .vscatterqpd,
        .vpscatterdd,
        .vpscatterdq,
        .vpternlogd,
        .vpternlogq,
        .vcvtps2ph,
        .vcvtph2ps,
        .vcvtne2ps2bf16,
        .vcvttps2dq,
        .vcvtps2dq,
        .vcvtdq2ps,
        .vshuff32x4,
        .vshuff64x2,
        .vshufi32x4,
        .vshufi64x2,
        .valignd,
        .valignq,
        .vpmovm2d,
        .vpmovd2m,
        .vpmultishiftqb,
        .vpconflictd,
        .vpconflictq,
        .vpackssdw,
        .vpshuflw,
        .vpshufhw,
        .vblendps,
        .vblendpd,
        .vshufpd,
        .vpermilps,
        .vpbroadcastw,
        .vpbroadcastd,
        .vpbroadcastq,
        .vextractps,
        .vmovntdq,
        .vmovntps,
        .vmovntdqa,
        .vpcmpistri,
        .vpmaxsw,
        .vcvtdq2pd,
        .vcvttpd2dq,
        => process_impl_instruction_decode.terminateUnimplemented(self, d),
    }

    if (!process_impl_lifecycle.isTerminated(self)) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rip += d.len;
    }
}
