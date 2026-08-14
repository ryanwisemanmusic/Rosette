//! Cooperative thread scheduling and cooperative idle callback dispatch.
//! Extracted from MachOState (process.zig) to reduce file size.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const scheduler = @import("scheduler");
const pthread_runtime = @import("pthread").pthread_runtime;

// Types referenced explicitly in parameter/return types or function bodies
const SuspendedGuestThread = @import("macho_core").types.SuspendedGuestThread;
const IdleQueueSnapshot = @import("macho_core").types.IdleQueueSnapshot;
const IdleDispatchBlock = @import("macho_core").types.IdleDispatchBlock;
const RunnableSuspendedSnapshot = @import("macho_core").types.RunnableSuspendedSnapshot;
const idleQueueSnapshotFor = @import("macho_core").types.idleQueueSnapshotFor;

// Constants used in function bodies
const DEFAULT_GUEST_THREAD_STACK_SIZE = @import("macho_core").constants.DEFAULT_GUEST_THREAD_STACK_SIZE;
const COOPERATIVE_THREAD_QUANTUM_STEPS = @import("macho_core").constants.COOPERATIVE_THREAD_QUANTUM_STEPS;
const COOPERATIVE_SCHEDULER_SCAN_INTERVAL = @import("macho_core").constants.COOPERATIVE_SCHEDULER_SCAN_INTERVAL;
const IDLE_STARVATION_STEPS = @import("macho_core").constants.IDLE_STARVATION_STEPS;
const GUEST_THREAD_RETURN_SENTINEL = @import("macho_core").constants.GUEST_THREAD_RETURN_SENTINEL;
const MAX_IDLE_CALLBACKS = @import("macho_core").types.MAX_IDLE_CALLBACKS;
const IDLE_CALLBACK_HANDLE_BASE = @import("macho_core").types.IDLE_CALLBACK_HANDLE_BASE;

// Utility functions
const alignDown = @import("macho_core").utils.alignDown;

pub fn beginCooperativeMainLoop(self: anytype) bool {
    if (self.cooperative_ui_context != null) return false;
    const deferred = self.pthreads.takeNewestDeferred() orelse return false;
    self.cooperative_ui_context = .{
        .regs = self.regs,
        .xmm = self.xmm,
        .ymm_hi = self.ymm_hi,
        .x87 = self.x87,
    };
    self.foreign_objects.main_loop_entries +|= 1;
    self.foreign_objects.main_loop_depth +|= 1;
    if (!self.startDeferredGuestThread(deferred)) {
        self.cooperative_ui_context = null;
        self.foreign_objects.main_loop_depth -|= 1;
        return false;
    }
    self.startup.enter(.gtk_init, self.executed_steps);
    self.startup.enter(.main_loop, self.executed_steps);
    machoCapturePrint(
        "macho-processor: GTK cooperative main loop entered: guest_thread=0x{x} start=0x{x} deferred_remaining={d}\n",
        .{ deferred.handle, deferred.start_routine, self.pthreads.deferred_threads },
    );
    self.logThreadTable("GTK main loop entered");
    return true;
}

pub fn startDeferredGuestThread(self: anytype, deferred: pthread_runtime.DeferredThread) bool {
    if (!self.isExecutableAddress(deferred.start_routine)) {
        machoCapturePrint("macho-processor: deferred guest thread rejected: start=0x{x} is not executable\n", .{deferred.start_routine});
        return false;
    }
    const requested_stack = if (deferred.stack_size == 0) DEFAULT_GUEST_THREAD_STACK_SIZE else deferred.stack_size;
    const stack_size = std.math.clamp(requested_stack, @as(u64, 64 * 1024), @as(u64, 32 * 1024 * 1024));
    const stack_base = self.guestAlloc(stack_size, 16) orelse return false;

    self.regs = .{};
    self.xmm = [_][16]u8{[_]u8{0} ** 16} ** 16;
    self.ymm_hi = [_][16]u8{[_]u8{0} ** 16} ** 16;
    self.x87 = .{};
    self.coop_bootstrap_active = true;
    self.coop_bootstrap_index = 0;
    self.regs.rip = deferred.start_routine;
    self.regs.rdi = deferred.argument;
    self.regs.rsp = alignDown(stack_base + stack_size, 16);
    self.push(GUEST_THREAD_RETURN_SENTINEL);
    self.active_guest_thread = deferred.handle;
    self.pthreads.markRunning(deferred.handle);
    self.cooperative_thread_switches +|= 1;

    if (self.ui_handoff.isActive()) {
        self.ui_handoff.workerStarted(deferred.handle, self.regs.rip, self.executed_steps);
        self.logThreadTable("UI handoff worker started");
    }

    return true;
}

pub fn saveActiveGuestThread(self: anytype, reason: []const u8) bool {
    if (self.active_guest_thread == 0) return false;
    if (self.suspended_guest_thread_count >= self.suspended_guest_threads.len) return false;

    self.suspended_guest_threads[self.suspended_guest_thread_count] = .{
        .handle = self.active_guest_thread,
        .suspended_step = self.executed_steps,
        .reason = reason,
        .regs = self.regs,
        .xmm = self.xmm,
        .ymm_hi = self.ymm_hi,
        .x87 = self.x87,
    };
    self.suspended_guest_thread_count += 1;
    self.pthreads.markContextSuspended(self.active_guest_thread);
    self.scheduler_log.emit(.{
        .kind = .thread_blocked,
        .step = self.executed_steps,
        .thread = self.active_guest_thread,
        .runnable = self.pthreads.activeCount(),
        .blocked = self.pthreads.blocked_threads,
        .reason = reason,
    });

    if (self.ui_handoff.ownsCallbackHandle(self.active_guest_thread)) {
        self.ui_handoff.callbackSuspended(self.executed_steps);
    }

    self.active_guest_thread = 0;
    return true;
}

pub fn resumeSuspendedGuestThread(self: anytype) bool {
    _ = self.guest_time.advanceForExecution(self.executed_steps);
    if (self.suspended_guest_thread_count == 0) return false;
    const completed_handoff_thread = self.ui_handoff.completionResumeHandle();
    var attempts = self.suspended_guest_thread_count;
    while (attempts > 0) : (attempts -= 1) {
        var selected_index: usize = 0;
        if (attempts == self.suspended_guest_thread_count) {
            if (completed_handoff_thread != 0) {
                for (self.suspended_guest_threads[0..self.suspended_guest_thread_count], 0..) |candidate, index| {
                    if (candidate.handle != completed_handoff_thread) continue;
                    selected_index = index;
                    machoCapturePrint(
                        "scheduler: UI handoff completion-affinity resume: generation={d} scheduling_thread=0x{x} skipped_fifo_entries={d} callback_completed_step={d} step={d}\n",
                        .{ self.ui_handoff.generation, candidate.handle, index, self.ui_handoff.completed_step, self.executed_steps },
                    );
                    break;
                }
            } else if (self.ui_handoff.shouldPreferCallback(self.executed_steps, COOPERATIVE_THREAD_QUANTUM_STEPS)) {
                for (self.suspended_guest_threads[0..self.suspended_guest_thread_count], 0..) |candidate, index| {
                    if (!self.ui_handoff.ownsCallbackHandle(candidate.handle)) continue;
                    selected_index = index;
                    const resume_ordinal = self.ui_handoff.callback_resumptions +| 1;
                    if (resume_ordinal <= 4) {
                        machoCapturePrint(
                            "scheduler: UI handoff priority resume: generation={d} callback_handle=0x{x} skipped_fifo_entries={d} step={d} resume={d}\n",
                            .{ self.ui_handoff.generation, candidate.handle, index, self.executed_steps, resume_ordinal },
                        );
                    }
                    break;
                }
            }
        }
        const context = self.suspended_guest_threads[selected_index];
        if (selected_index + 1 < self.suspended_guest_thread_count) {
            std.mem.copyForwards(
                SuspendedGuestThread,
                self.suspended_guest_threads[selected_index .. self.suspended_guest_thread_count - 1],
                self.suspended_guest_threads[selected_index + 1 .. self.suspended_guest_thread_count],
            );
        }
        self.suspended_guest_thread_count -= 1;
        self.suspended_guest_threads[self.suspended_guest_thread_count] = .{};

        const resume_decision = self.pthreads.resumeCooperativeContext(context.handle, self.guest_time.now());
        if (resume_decision == null) {
            self.suspended_guest_threads[self.suspended_guest_thread_count] = context;
            self.suspended_guest_thread_count += 1;
            continue;
        }

        self.regs = context.regs;
        self.xmm = context.xmm;
        self.ymm_hi = context.ymm_hi;
        self.x87 = context.x87;
        const saved_rax = self.regs.rax;
        self.regs.rax = resume_decision.?.restoredRax(saved_rax);
        if (resume_decision.?.cancel_deadline_sequence != 0) {
            _ = self.guest_time.cancel(resume_decision.?.cancel_deadline_sequence);
        }
        if (resume_decision.?.rax_override != null) {
            self.cooperative_wait_result_resumes +|= 1;
        } else {
            self.cooperative_preserved_register_resumes +|= 1;
        }
        self.active_guest_thread = context.handle;
        self.pthreads.markRunning(context.handle);
        self.cooperative_thread_switches +|= 1;
        self.scheduler_log.emit(.{
            .kind = .thread_resumed,
            .step = self.executed_steps,
            .thread = context.handle,
            .runnable = self.pthreads.activeCount(),
            .blocked = self.pthreads.blocked_threads,
            .reason = context.reason,
        });
        const resume_count = self.cooperative_preserved_register_resumes + self.cooperative_wait_result_resumes;
        if (resume_count <= 4) {
            machoCapturePrint(
                "scheduler: guest context resume #{d}: thread=0x{x} reason={s} suspended_step={d} rip=0x{x} rsp=0x{x} rax(saved/restored)=0x{x}/0x{x} policy={s}\n",
                .{ resume_count, context.handle, context.reason, context.suspended_step, self.regs.rip, self.regs.rsp, saved_rax, self.regs.rax, if (resume_decision.?.rax_override != null) "wait_result_override" else "preserve_all_registers" },
            );
        }
        if (context.handle == completed_handoff_thread and self.ui_handoff.completionResumed(context.handle, self.executed_steps)) {
            machoCapturePrint(
                "scheduler: UI handoff dependency resolved: resumed scheduling_thread=0x{x} after callback cleanup; FIFO fallback remains available for unrelated workers\n",
                .{context.handle},
            );
            self.logThreadTable("UI handoff scheduling thread resumed");
        } else if (self.ui_handoff.ownsCallbackHandle(context.handle)) {
            self.ui_handoff.callbackResumed(self.regs.rip, self.executed_steps);
            if (self.ui_handoff.callback_resumptions <= 4) {
                self.logThreadTable("UI callback resumed");
            }
        } else if (self.ui_handoff.isActive()) {
            self.ui_handoff.workerStarted(context.handle, self.regs.rip, self.executed_steps);
        }
        return true;
    }
    return false;
}

/// Converts a globally parked cooperative scheduler back into executable work.
/// This is shared by explicit waits and by the thread-return boundary so the
/// latter cannot mistake "nothing runnable at this instant" for "all threads
/// completed". Finite virtual deadlines take priority; only when none exists
/// do we use the POSIX-permitted, generation-bounded condvar spurious wake.
fn recoverQuiescentGuestThread(self: anytype, reason: []const u8, waiter: u64) bool {
    if (self.pthreads.earliestWaitDeadline()) |deadline| {
        _ = self.guest_time.advanceTo(deadline);
        var emitted_deadline = false;
        while (self.guest_time.popDue()) |timer| {
            emitted_deadline = true;
            self.scheduler_log.emit(.{
                .kind = .timer_due,
                .step = self.executed_steps,
                .thread = timer.thread,
                .object = timer.wait_object,
                .generation = timer.wait_generation,
                .deadline_ns = timer.deadline_ns,
                .blocked = self.pthreads.blocked_threads,
                .reason = "idle_advance_to_deadline",
            });
        }
        if (!emitted_deadline) {
            self.scheduler_log.emit(.{
                .kind = .timer_due,
                .step = self.executed_steps,
                .thread = waiter,
                .deadline_ns = deadline,
                .blocked = self.pthreads.blocked_threads,
                .reason = "unregistered_wait_deadline",
            });
        }
        return self.resumeSuspendedGuestThread();
    }

    const preferred = if (self.ui_handoff.isActive()) self.ui_handoff.scheduling_thread else 0;
    if (self.pthreads.wakeOldestCondvarForQuiescence(preferred, self.executed_steps)) |woken| {
        self.cooperative_quiescence_recoveries +|= 1;
        const advanced_now = self.guest_time.advanceForQuiescence();
        if (self.cooperative_quiescence_recoveries <= 8 or self.cooperative_quiescence_recoveries % 100 == 0) {
            machoCapturePrint(
                "scheduler: global quiescence recovery #{d}: POSIX spurious wake thread=0x{x} preferred=0x{x} blocked={d} virtual_now_ns={d} reason={s}; advanced one bounded idle tick because no runnable producer or finite deadline remained\n",
                .{ self.cooperative_quiescence_recoveries, woken, preferred, self.pthreads.blocked_threads, advanced_now, reason },
            );
        }
        return self.resumeSuspendedGuestThread();
    }

    self.scheduler_log.emit(.{
        .kind = .deadlock,
        .step = self.executed_steps,
        .thread = waiter,
        .runnable = 0,
        .blocked = self.pthreads.blocked_threads,
        .reason = reason,
    });
    return false;
}

pub fn yieldActiveGuestThreadForWait(self: anytype, reason: []const u8) bool {
    if (self.cooperative_ui_context == null or self.active_guest_thread == 0) return false;
    if (self.pthreads.deferred_threads == 0 and self.suspended_guest_thread_count == 0 and self.pendingIdleCallbackCount() == 0) return false;
    const waiter = self.active_guest_thread;
    if (!self.saveActiveGuestThread(reason)) return false;
    var worker: u64 = 0;
    if (self.active_idle_source == 0 and self.startNextIdleCallback(reason, true)) {
        worker = self.active_guest_thread;
    } else if (self.pthreads.takeNewestDeferred()) |next| {
        if (!self.startDeferredGuestThread(next)) {
            _ = self.resumeSuspendedGuestThread();
            return false;
        }
        worker = next.handle;
    } else {
        if (!self.resumeSuspendedGuestThread()) {
            if (!recoverQuiescentGuestThread(self, reason, waiter)) return false;
        }
        worker = self.active_guest_thread;
    }
    if (worker == waiter) {
        self.cooperative_self_resumes +|= 1;
        if (self.cooperative_self_resumes <= 4) {
            machoCapturePrint(
                "scheduler: cooperative yield resumed caller (no alternate runnable context; not blocked): thread=0x{x} reason={s} suspended={d} deferred={d} self_resumes={d}\n",
                .{ waiter, reason, self.suspended_guest_thread_count, self.pthreads.deferred_threads, self.cooperative_self_resumes },
            );
        }
        return false;
    }
    self.cooperative_wait_yields +|= 1;
    self.scheduler_log.emit(.{
        .kind = .context_switch,
        .step = self.executed_steps,
        .thread = waiter,
        .peer = worker,
        .runnable = self.pthreads.activeCount(),
        .blocked = self.pthreads.blocked_threads,
        .reason = reason,
    });
    if (self.cooperative_wait_yields <= 4) {
        machoCapturePrint(
            "macho-processor: cooperative wait yield #{d}: waiter=0x{x} -> worker=0x{x} reason={s} deferred_remaining={d} suspended={d} gtk_idle_pending={d}\n",
            .{ self.cooperative_wait_yields, waiter, worker, reason, self.pthreads.deferred_threads, self.suspended_guest_thread_count, self.pendingIdleCallbackCount() },
        );
    }
    if (self.cooperative_wait_yields <= 4) {
        self.logThreadTable(reason);
    }
    return true;
}

// GTK idle scheduling is a wake-up, not merely queue bookkeeping. Dispatch
// newly queued UI work at the first safe interpreter boundary even after
// every pthread worker has started. This is the path used by Xenia's
// CallInUIThread presenter creation handoff.
//
// Guest startup code may also wait by spinning on atomics before it reaches
// a pthread or libc++ condition-variable call. Give not-yet-started workers
// a bounded execution slice so one spinner cannot starve their producers.
pub fn maybeYieldActiveGuestThreadForQuantum(self: anytype) void {
    if (self.cooperative_ui_context == null or self.active_guest_thread == 0) return;

    // P0-1 (perf audit): the idle-callback table scan and the
    // every-suspended-thread scan previously ran on EVERY interpreted
    // instruction. They now run once per COOPERATIVE_THREAD_QUANTUM_STEPS
    // (10k) steps — quantum granularity. In between, cached counts from
    // incremental maintenance (idle) and version/deadline-keyed refresh
    // (suspended) are reused. Staleness is bounded to one quantum.
    const scan_due = self.cooperative_scheduler_scan_steps == 0;
    self.cooperative_scheduler_scan_steps +|= 1;
    if (self.cooperative_scheduler_scan_steps >= COOPERATIVE_THREAD_QUANTUM_STEPS) {
        self.cooperative_scheduler_scan_steps = 0;
    }
    if (scan_due) {
        // Deadlines must advance even while one runnable context stays in a
        // polling loop. `resumeSuspendedGuestThread` also advances execution
        // time, but reaching that function is gated by the runnable cache
        // below. Without this scheduler-boundary update the cache can keep
        // observing a frozen clock forever: a sleeper's deadline never becomes
        // runnable, so no resume is attempted, so the clock never advances.
        //
        // Keep the update on the existing bounded scan cadence rather than on
        // every interpreted instruction. GuestTimeService uses an execution
        // watermark, so the elapsed instruction count is still accounted for
        // exactly once.
        const clock_before = self.guest_time.now();
        const deadline_before = self.guest_time.nextDeadline();
        const clock_after = self.guest_time.advanceForExecution(self.executed_steps);
        if (deadline_before) |deadline| {
            if (clock_before < deadline and clock_after >= deadline) {
                self.scheduler_execution_deadline_crossings +|= 1;
                if (self.scheduler_execution_deadline_crossings <= 4) {
                    machoCapturePrint(
                        "scheduler: active execution crossed virtual deadline #{d}: thread=0x{x} rip=0x{x} step={d} clock_before_ns={d} clock_after_ns={d} deadline_ns={d} lateness_ns={d} cached_runnable={d}\n",
                        .{ self.scheduler_execution_deadline_crossings, self.active_guest_thread, self.regs.rip, self.executed_steps, clock_before, clock_after, deadline, clock_after - deadline, self.cached_suspended_runnable },
                    );
                }
            }
        }
        self.cached_suspended_runnable = self.refreshSuspendedRunnableCache();
        // SDL audio is a callback producer, not an import return-value shim.
        // Keep its deadline check on the existing bounded scheduler cadence
        // so audio support adds no work to the per-instruction hot path.
        if (self.sdl.dispatchDueAudioCallback(self, GUEST_THREAD_RETURN_SENTINEL)) return;
    }
    const pending_idle = self.cached_pending_idle;
    const suspended_runnable = self.cached_suspended_runnable;
    const idle_callback_inflight = self.active_idle_source != 0;
    const idle_callback_running = idle_callback_inflight and
        self.isIdleCallbackHandle(self.active_guest_thread);

    if (idle_callback_running) {
        self.cooperative_quantum_steps +|= 1;
        if (self.cooperative_quantum_steps >= COOPERATIVE_THREAD_QUANTUM_STEPS) {
            self.cooperative_quantum_steps = 0;
            // Refresh the cached suspended count at the quantum boundary and
            // use it directly here, so the rendezvous decision reads a count
            // no more than one scan interval old exactly where it matters
            // (runs at most once per 10k steps). The refresh itself is
            // version/deadline-keyed, so it is a no-op unless pthread state
            // or virtual time moved since the last computation.
            self.cached_suspended_runnable = self.refreshSuspendedRunnableCache();
            const boundary_suspended_runnable = self.cached_suspended_runnable;
            const tracker_owns_callback = self.ui_handoff.ownsCallbackHandle(self.active_guest_thread);
            if (tracker_owns_callback) {
                self.ui_handoff.registerProgress(self.executed_steps);
            }

            const producer_eligible = self.pthreads.deferred_threads != 0 or boundary_suspended_runnable != 0;
            const should_rendezvous = if (tracker_owns_callback)
                self.ui_handoff.callbackQuantumAction(self.pthreads.deferred_threads, boundary_suspended_runnable) == .rendezvous_worker
            else
                producer_eligible;
            if (should_rendezvous) {
                self.ui_callback_retained_quanta +|= 1;
                const callback = self.active_guest_thread;
                if (self.yieldActiveGuestThreadForWait("UI callback worker rendezvous")) {
                    self.cooperative_quantum_yields +|= 1;
                    if (self.ui_callback_retained_quanta <= 4) {
                        machoCapturePrint(
                            "scheduler: UI callback rendezvous: quantum={d} callback=0x{x} -> worker=0x{x} deferred={d} runnable_suspended={d}; callback ownership retained\n",
                            .{ self.ui_callback_retained_quanta, callback, self.active_guest_thread, self.pthreads.deferred_threads, boundary_suspended_runnable },
                        );
                    }
                } else if (self.ui_callback_retained_quanta <= 4) {
                    machoCapturePrint(
                        "scheduler: retained active UI callback: quantum={d} callback_handle=0x{x} rip=0x{x} deferred_workers={d} runnable_suspended={d}; no eligible rendezvous target\n",
                        .{ self.ui_callback_retained_quanta, self.active_guest_thread, self.regs.rip, self.pthreads.deferred_threads, boundary_suspended_runnable },
                    );
                }
            }
        }
        return;
    }

    const work = scheduler.chooseCooperativeWork(.{
        .pending_idle = pending_idle,
        .callback_inflight = idle_callback_inflight,
        .idle_callback_running = idle_callback_running,
        .deferred_threads = self.pthreads.deferred_threads,
        .suspended_threads = suspended_runnable,
    });
    if (work == .gtk_idle) {
        const scheduling_thread = self.active_guest_thread;
        self.cooperative_quantum_steps = 0;
        if (!self.yieldActiveGuestThreadForWait("GTK idle wake")) {
            self.idle_dispatch_failures +|= 1;
            const block = self.gtkIdleDispatchBlock();
            if (self.idle_dispatch_failures <= 8 or self.idle_dispatch_failures % 100 == 0) {
                machoCapturePrint(
                    "macho-processor: GTK idle wake blocked: failure={d} reason={s} active=0x{x} pending={d} suspended={d}/{d}\n",
                    .{ self.idle_dispatch_failures, @tagName(block), scheduling_thread, pending_idle, self.suspended_guest_thread_count, self.suspended_guest_threads.len },
                );
            }
            return;
        }
        self.idle_wakeups +|= 1;
        machoCapturePrint(
            "macho-processor: GTK idle wake dispatched: wake={d} from_thread=0x{x} source={d} pending={d}\n",
            .{ self.idle_wakeups, scheduling_thread, self.active_idle_source, self.pendingIdleCallbackCount() },
        );
        return;
    }
    if (work != .deferred_thread and work != .suspended_thread) return;
    self.cooperative_quantum_steps +|= 1;
    if (self.cooperative_quantum_steps < COOPERATIVE_THREAD_QUANTUM_STEPS) return;
    self.cooperative_quantum_steps = 0;
    const previous_thread = self.active_guest_thread;
    const reason = if (work == .suspended_thread) "runnable rotation quantum" else "deferred thread quantum";
    self.scheduler_log.emit(.{
        .kind = .quantum_expired,
        .step = self.executed_steps,
        .thread = previous_thread,
        .runnable = self.pthreads.activeCount(),
        .blocked = self.pthreads.blocked_threads,
        .reason = reason,
    });
    if (!self.yieldActiveGuestThreadForWait(reason)) return;
    self.cooperative_quantum_yields +|= 1;
    if (work == .suspended_thread) self.cooperative_rotation_yields +|= 1;
    if (self.cooperative_quantum_yields <= 4) {
        machoCapturePrint(
            "macho-processor: cooperative quantum yield #{d}: work={s} from=0x{x} to=0x{x} deferred={d} suspended={d} runnable_rotations={d}\n",
            .{ self.cooperative_quantum_yields, @tagName(work), previous_thread, self.active_guest_thread, self.pthreads.deferred_threads, self.suspended_guest_thread_count, self.cooperative_rotation_yields },
        );
    }
}

pub fn finishActiveGuestThread(self: anytype) void {
    if (self.active_guest_thread != 0) {
        if (self.sdl.finishAudioCallback(self.active_guest_thread)) {
            self.cooperative_thread_returns +|= 1;
            self.active_guest_thread = 0;
        } else if (self.isIdleCallbackHandle(self.active_guest_thread)) {
            const source = self.active_idle_source;
            const callback = self.active_idle_callback;
            const duration = self.executed_steps -| self.active_idle_started_step;
            self.idle_completed +|= 1;
            self.ui_handoff.completed(self.executed_steps);
            machoCapturePrint(
                "macho-processor: GTK idle callback completed: source={d} callback=0x{x} duration_steps={d} completed={d} pending={d}\n",
                .{ source, callback, duration, self.idle_completed, self.pendingIdleCallbackCount() },
            );
            self.logThreadTable("GTK idle callback completed");
            self.active_guest_thread = 0;
            self.active_idle_source = 0;
            self.active_idle_callback = 0;
            self.active_idle_started_step = 0;
        } else {
            self.pthreads.markCompleted(self.active_guest_thread);
            self.cooperative_thread_returns +|= 1;
            machoCapturePrint("macho-processor: cooperative guest thread returned: handle=0x{x}\n", .{self.active_guest_thread});
            self.active_guest_thread = 0;
        }
    }
    if (self.startNextIdleCallback("idle-return", false)) return;
    if (self.pthreads.takeNewestDeferred()) |next| {
        if (self.startDeferredGuestThread(next)) return;
    }
    if (self.resumeSuspendedGuestThread()) return;

    // A returned worker is not proof that the application is done. Parked
    // condvar and timer contexts still represent live application work and
    // must be made runnable before GTK's intercepted caller can be restored.
    if (self.suspended_guest_thread_count != 0 or self.pthreads.blocked_threads != 0) {
        if (recoverQuiescentGuestThread(
            self,
            "thread return with parked cooperative contexts",
            0,
        )) return;

        // Preserve the main-loop ownership invariant. Leaving RIP at the
        // return sentinel retries recovery at the next scheduler boundary;
        // restoring the caller here would make Xenia run OnDestroy and exit
        // while live workers still exist.
        self.cooperative_starvation_warnings +|= 1;
        if (self.cooperative_starvation_warnings <= 8 or self.cooperative_starvation_warnings % 1000 == 0) {
            machoCapturePrint(
                "scheduler: refusing GTK main-loop exit with parked work: suspended={d} blocked={d} deferred={d} idle_pending={d} warning={d}\n",
                .{ self.suspended_guest_thread_count, self.pthreads.blocked_threads, self.pthreads.deferred_threads, self.pendingIdleCallbackCount(), self.cooperative_starvation_warnings },
            );
        }
        return;
    }
    self.restoreMainLoopCaller("all cooperative guest threads returned");
}

pub fn scheduleIdleCallback(self: anytype, function: u64, data: u64, tag: []const u8) u64 {
    if (function == 0 or !self.isExecutableAddress(function)) {
        machoCapturePrint(
            "macho-processor: GTK idle rejected: callback=0x{x} executable={} tag={s}\n",
            .{ function, self.isExecutableAddress(function), tag },
        );
        return 0;
    }
    for (&self.idle_callbacks) |*entry| {
        if (entry.active) continue;
        const source = self.gtk_idle_next_source;
        self.gtk_idle_next_source +|= 1;
        entry.* = .{
            .source_id = source,
            .function = function,
            .data = data,
            .active = true,
            .tag = tag,
            .scheduled_step = self.executed_steps,
            .scheduling_thread = self.active_guest_thread,
            .scheduling_rip = self.regs.rip,
        };
        self.idle_scheduled +|= 1;
        updateCachedPendingIdle(self, 1);
        _ = self.ui_handoff.queueIfIdle(source, function, self.active_guest_thread, self.regs.rip, self.executed_steps);
        machoCapturePrint(
            "macho-processor: GTK idle scheduled: source={d} callback=0x{x} data=0x{x} tag={s} step={d} scheduling_thread=0x{x} scheduling_rip=0x{x} ui_context={} pending={d}\n",
            .{ source, function, data, tag, self.executed_steps, self.active_guest_thread, self.regs.rip, self.cooperative_ui_context != null, self.cached_pending_idle },
        );
        self.logThreadTable("GTK idle scheduled");
        return source;
    }
    machoCapturePrint(
        "macho-processor: GTK idle rejected: queue full callback=0x{x} data=0x{x} tag={s}\n",
        .{ function, data, tag },
    );
    return 0;
}

/// Incrementally maintain the cached idle callback count.
/// Call with +1 when a callback is scheduled, -1 when removed/completed.
pub fn updateCachedPendingIdle(self: anytype, delta: i32) void {
    if (delta > 0) {
        self.cached_pending_idle += 1;
    } else {
        if (self.cached_pending_idle > 0) {
            self.cached_pending_idle -= 1;
        }
    }
}

pub fn pendingIdleCallbackCount(self: anytype) usize {
    var count: usize = 0;
    for (&self.idle_callbacks) |*entry| {
        if (entry.active) count += 1;
    }
    return count;
}

pub fn idleQueueSnapshot(self: anytype) IdleQueueSnapshot {
    return idleQueueSnapshotFor(&self.idle_callbacks);
}

pub fn idleDispatchBlock(self: anytype) IdleDispatchBlock {
    if (self.cooperative_ui_context == null) return .no_ui_context;
    if (self.active_guest_thread == 0) return .no_active_guest_thread;
    if (self.active_idle_source != 0) return .callback_already_running;
    if (self.suspended_guest_thread_count >= self.suspended_guest_threads.len) return .suspended_queue_full;
    return .ready;
}

pub fn removeIdleSource(self: anytype, source: u64) bool {
    for (&self.idle_callbacks) |*entry| {
        if (!entry.active or entry.source_id != source) continue;
        entry.* = .{};
        self.idle_removed +|= 1;
        updateCachedPendingIdle(self, -1);
        machoCapturePrint("macho-processor: GTK idle removed: source={d} pending={d}\n", .{ source, self.cached_pending_idle });
        return true;
    }
    return false;
}

pub fn startNextIdleCallback(self: anytype, reason: []const u8, active_already_saved: bool) bool {
    self.pumpNativeWindowEvents();
    const context = self.cooperative_ui_context orelse return false;
    for (&self.idle_callbacks) |*entry| {
        if (!entry.active) continue;
        if (!self.isExecutableAddress(entry.function)) {
            machoCapturePrint(
                "macho-processor: GTK idle dropped non-executable callback: source={d} callback=0x{x} tag={s}\n",
                .{ entry.source_id, entry.function, entry.tag },
            );
            entry.* = .{};
            updateCachedPendingIdle(self, -1);
            continue;
        }
        if (!active_already_saved and self.active_guest_thread != 0 and !self.saveActiveGuestThread("GTK idle dispatch")) return false;
        const source = entry.source_id;
        const function = entry.function;
        const data = entry.data;
        const tag = entry.tag;
        const scheduled_step = entry.scheduled_step;
        const scheduling_thread = entry.scheduling_thread;
        const scheduling_rip = entry.scheduling_rip;
        entry.* = .{};
        updateCachedPendingIdle(self, -1);
        self.regs = context.regs;
        self.xmm = context.xmm;
        self.ymm_hi = context.ymm_hi;
        self.x87 = context.x87;
        self.regs.rip = function;
        self.regs.rdi = data;
        self.regs.rsp = alignDown(context.regs.rsp, 16);
        self.push(GUEST_THREAD_RETURN_SENTINEL);
        self.active_guest_thread = IDLE_CALLBACK_HANDLE_BASE + source;
        self.active_idle_source = source;
        self.active_idle_callback = function;
        self.active_idle_started_step = self.executed_steps;
        self.idle_started +|= 1;
        self.ui_handoff.beginDispatch(
            source,
            function,
            scheduling_thread,
            scheduling_rip,
            scheduled_step,
            self.active_guest_thread,
            self.regs.rip,
            self.executed_steps,
        );
        self.cooperative_thread_switches +|= 1;
        machoCapturePrint(
            "macho-processor: GTK idle dispatch start: source={d} callback=0x{x} data=0x{x} tag={s} reason={s} queue_age_steps={d} scheduling_thread=0x{x} scheduling_rip=0x{x} pending={d}\n",
            .{ source, function, data, tag, reason, self.executed_steps -| scheduled_step, scheduling_thread, scheduling_rip, self.pendingIdleCallbackCount() },
        );
        self.logThreadTable("GTK idle callback started");
        return true;
    }
    return false;
}

pub fn isSyntheticCallbackHandle(self: anytype, handle: u64) bool {
    return self.isIdleCallbackHandle(handle) or self.sdl.isAudioCallbackHandle(handle);
}

pub fn isIdleCallbackHandle(self: anytype, handle: u64) bool {
    _ = self;
    return handle >= IDLE_CALLBACK_HANDLE_BASE and handle < IDLE_CALLBACK_HANDLE_BASE + MAX_IDLE_CALLBACKS + 1024;
}

pub fn currentCooperativeThreadHandle(self: anytype) u64 {
    if (self.active_guest_thread == 0 or self.isIdleCallbackHandle(self.active_guest_thread)) {
        return self.pthreads.main_thread_handle;
    }
    return self.active_guest_thread;
}

pub fn threadNumericId(self: anytype, handle: u64) u64 {
    if (handle == 0 or handle == self.pthreads.main_thread_handle or self.isSyntheticCallbackHandle(handle)) return 1;
    if (self.pthreads.snapshotForHandle(handle)) |snapshot| return snapshot.numeric_id;
    return 0;
}

pub fn threadRole(self: anytype, handle: u64, address: u64) []const u8 {
    if (self.isIdleCallbackHandle(handle)) return "ui_callback";
    if (self.sdl.isAudioCallbackHandle(handle)) return "sdl_audio";
    if (handle == self.pthreads.main_thread_handle) return "main_ui";
    const symbol = self.metadata.nearestSymbol(address) orelse return "worker";
    if (std.mem.indexOf(u8, symbol.name, "WindowedAppContext") != null or
        std.mem.indexOf(u8, symbol.name, "CallInUIThread") != null or
        std.mem.indexOf(u8, symbol.name, "gtk") != null or
        std.mem.indexOf(u8, symbol.name, "GTK") != null)
    {
        return "ui_worker";
    }
    if (std.mem.indexOf(u8, symbol.name, "Timer") != null or std.mem.indexOf(u8, symbol.name, "timer") != null) return "timer";
    if (std.mem.indexOf(u8, symbol.name, "logging") != null or std.mem.indexOf(u8, symbol.name, "Logger") != null) return "logging";
    if (std.mem.indexOf(u8, symbol.name, "io") != null or std.mem.indexOf(u8, symbol.name, "IO") != null) return "io";
    return "worker";
}

pub fn contextContainsHandle(self: anytype, handle: u64) bool {
    if (self.active_guest_thread == handle) return true;
    for (self.suspended_guest_threads[0..self.suspended_guest_thread_count]) |context| {
        if (context.handle == handle) return true;
    }
    return false;
}

pub fn runnableSuspendedSnapshot(self: anytype) RunnableSuspendedSnapshot {
    var result = RunnableSuspendedSnapshot{};
    for (self.suspended_guest_threads[0..self.suspended_guest_thread_count]) |context| {
        const thread = self.pthreads.snapshotForHandle(context.handle);
        const runnable = if (thread) |snapshot| switch (snapshot.state) {
            .runnable => true,
            .waiting_condvar => snapshot.spurious_wake_pending or
                snapshot.notified_generation > snapshot.wait_generation or
                (snapshot.wait_deadline_nanoseconds != 0 and snapshot.wait_deadline_nanoseconds <= self.guest_time.now()),
            .sleeping_until_deadline => snapshot.wait_deadline_nanoseconds != 0 and snapshot.wait_deadline_nanoseconds <= self.guest_time.now(),
            else => false,
        } else true;
        if (!runnable) {
            result.blocked += 1;
            continue;
        }
        result.runnable += 1;
        if (result.oldest_handle != 0 and context.suspended_step >= result.oldest_step) continue;
        result.oldest_handle = context.handle;
        result.oldest_rip = context.regs.rip;
        result.oldest_step = context.suspended_step;
        result.oldest_reason = context.reason;
    }
    return result;
}

/// P0-1 (event-driven scheduler): returns an authoritative count of runnable
/// suspended contexts without paying for the full scan unless runnability
/// could actually have changed since the last computation.
///
/// The full scan (`runnableSuspendedSnapshot`) is O(suspended × threads)
/// because every context is resolved back through the pthread thread table.
/// It is only required after (a) a pthread state transition that can alter
/// whether a suspended context is accepted by `resumeCooperativeContext`, or
/// (b) virtual time reaching the earliest finite deadline (an O(1) heap-top
/// read) — the one way runnability changes without an explicit transition.
///
/// Callers must still attempt the authoritative `resumeCooperativeContext`
/// before resuming anything; this only decides whether the attempt is worth
/// scanning for.
pub fn refreshSuspendedRunnableCache(self: anytype) usize {
    const version = self.pthreads.state_version;
    const cached_next = self.cached_suspended_next_deadline;
    if (version == self.cached_suspended_version and
        (cached_next == null or self.guest_time.now() < cached_next.?))
    {
        return self.cached_suspended_runnable;
    }
    self.cached_suspended_runnable = self.runnableSuspendedSnapshot().runnable;
    self.cached_suspended_version = version;
    self.cached_suspended_next_deadline = self.guest_time.nextDeadline();
    return self.cached_suspended_runnable;
}

pub fn logThreadTable(self: anytype, reason: []const u8) void {
    machoCapturePrint(
        "scheduler: THREAD TABLE BEGIN reason={s} step={d} active=0x{x} contexts(active/suspended)={d}/{d} pthread_entries={d} deferred={d} ui_phase={s}\n",
        .{ reason, self.executed_steps, self.active_guest_thread, @intFromBool(self.active_guest_thread != 0), self.suspended_guest_thread_count, self.pthreads.created_threads, self.pthreads.deferred_threads, @tagName(self.ui_handoff.phase) },
    );
    machoCapturePrint("scheduler: CTX  slot handle             tid role         state      age_steps rip                symbol/reason\n", .{});
    if (self.active_guest_thread != 0) {
        const symbol = self.metadata.nearestSymbol(self.regs.rip);
        machoCapturePrint(
            "scheduler: CTX  run  0x{x:0>16} {d: >3} {s: <12} running    {d: >9} 0x{x:0>16} {s}\n",
            .{ self.active_guest_thread, self.threadNumericId(self.active_guest_thread), self.threadRole(self.active_guest_thread, self.regs.rip), 0, self.regs.rip, if (symbol) |resolved| resolved.name else "<unknown>" },
        );
    }
    for (self.suspended_guest_threads[0..self.suspended_guest_thread_count], 0..) |context, index| {
        const symbol = self.metadata.nearestSymbol(context.regs.rip);
        machoCapturePrint(
            "scheduler: CTX  q{d:0>2}  0x{x:0>16} {d: >3} {s: <12} suspended  {d: >9} 0x{x:0>16} {s} | {s}\n",
            .{ index, context.handle, self.threadNumericId(context.handle), self.threadRole(context.handle, context.regs.rip), self.executed_steps -| context.suspended_step, context.regs.rip, if (symbol) |resolved| resolved.name else "<unknown>", context.reason },
        );
    }
    machoCapturePrint("scheduler: REG  slot handle             tid role         pthread_state context stored start              blocked_for wait\n", .{});
    for (0..self.pthreads.tableCapacity()) |slot| {
        const snapshot = self.pthreads.snapshotAt(slot) orelse continue;
        const start_symbol = self.metadata.nearestSymbol(snapshot.start_routine);
        machoCapturePrint(
            "scheduler: REG  {d:0>2}   0x{x:0>16} {d: >3} {s: <12} {s: <13} {s: <7} {s: <6} 0x{x:0>16} {d: >11} {s}\n",
            .{
                slot,
                snapshot.handle,
                snapshot.numeric_id,
                self.threadRole(snapshot.handle, snapshot.start_routine),
                @tagName(snapshot.state),
                if (snapshot.handle == self.active_guest_thread) "active" else if (self.contextContainsHandle(snapshot.handle)) "queue" else "none",
                if (snapshot.started) "yes" else "no",
                snapshot.start_routine,
                if (snapshot.state == .runnable or snapshot.blocked_since_step == 0) 0 else self.executed_steps -| snapshot.blocked_since_step,
                if (snapshot.blocked_reason.len != 0) snapshot.blocked_reason else if (start_symbol) |resolved| resolved.name else "<unknown>",
            },
        );
    }
    machoCapturePrint("scheduler: THREAD TABLE END reason={s}\n", .{reason});
}

pub fn restoreMainLoopCaller(self: anytype, reason: []const u8) void {
    const context = self.cooperative_ui_context orelse return;
    self.regs = context.regs;
    self.xmm = context.xmm;
    self.ymm_hi = context.ymm_hi;
    self.x87 = context.x87;
    self.cooperative_ui_context = null;
    self.active_guest_thread = 0;
    self.active_idle_source = 0;
    self.active_idle_callback = 0;
    self.active_idle_started_step = 0;
    self.ui_handoff.reset();
    self.foreign_objects.main_loop_depth -|= 1;
    const return_address = self.pop();
    if (return_address == 0 or !self.isExecutableAddress(return_address)) {
        self.terminateForInvalidControlTransfer(.{
            .kind = "gtk_main cooperative return",
            .instruction_address = self.regs.rip,
            .target_address = return_address,
        });
        return;
    }
    self.regs.rip = return_address;
    machoCapturePrint("macho-processor: GTK cooperative main loop exited: {s}\n", .{reason});
}

pub fn logCooperativeSchedulerSummary(self: anytype) void {
    if (self.cooperative_thread_switches == 0 and self.cooperative_wait_yields == 0) return;
    machoCapturePrint(
        "macho-processor: cooperative scheduler: switches={d} returns={d} wait_yields={d} sleep_yields={d} quantum_yields={d} runnable_rotations={d} resumes(preserved/wait_override)={d}/{d} self_resumes={d} clock(execution_ticks/execution_ns/quiescence_recoveries/quiescence_ticks/quiescence_ns)={d}/{d}/{d}/{d}/{d} runnable_starvation_warnings={d} suspended={d} active=0x{x} gtk_idle(scheduled/started/completed/removed/pending/wakeups/dispatch_failures/starvation_warnings)={d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}\n",
        .{ self.cooperative_thread_switches, self.cooperative_thread_returns, self.cooperative_wait_yields, self.cooperative_sleep_yields, self.cooperative_quantum_yields, self.cooperative_rotation_yields, self.cooperative_preserved_register_resumes, self.cooperative_wait_result_resumes, self.cooperative_self_resumes, self.guest_time.execution_advances, self.guest_time.execution_advanced_ns, self.cooperative_quiescence_recoveries, self.guest_time.quiescence_advances, self.guest_time.quiescence_advanced_ns, self.cooperative_starvation_warnings, self.suspended_guest_thread_count, self.active_guest_thread, self.idle_scheduled, self.idle_started, self.idle_completed, self.idle_removed, self.pendingIdleCallbackCount(), self.idle_wakeups, self.idle_dispatch_failures, self.idle_starvation_warnings },
    );
}

pub fn logCooperativeHeartbeat(self: anytype) void {
    if (self.cooperative_ui_context == null) return;
    const idle = self.gtkIdleQueueSnapshot();
    const idle_age = if (idle.pending != 0) self.executed_steps -| idle.oldest_scheduled_step else 0;
    const suspended = self.runnableSuspendedSnapshot();
    const suspended_age = if (suspended.oldest_handle != 0) self.executed_steps -| suspended.oldest_step else 0;
    const dispatch_block = self.gtkIdleDispatchBlock();
    {
        const idx = self.coop_heartbeat_index;
        self.coop_heartbeat_entries[idx] = .{
            .step = self.executed_steps,
            .rip = self.regs.rip,
            .thread = self.active_guest_thread,
            .deferred = self.pthreads.deferred_threads,
            .suspended_total = self.suspended_guest_thread_count,
            .suspended_runnable = suspended.runnable,
            .suspended_blocked = suspended.blocked,
            .switches = self.cooperative_thread_switches,
            .wait_yields = self.cooperative_wait_yields,
            .quantum_yields = self.cooperative_quantum_yields,
            .rotation_yields = self.cooperative_rotation_yields,
            .idle_pending = idle.pending,
            .active_idle_source = self.active_idle_source,
            .active_idle_callback = self.active_idle_callback,
            .dispatch_block = dispatch_block,
        };
        self.coop_heartbeat_index +|= 1;
        if (self.coop_heartbeat_index >= 5) {
            self.coop_heartbeat_index = 0;
            self.coop_heartbeat_filled = true;
        }
    }
    if (self.ui_handoff.isActive()) {
        const idx = self.ui_handoff_index;
        self.ui_handoff_entries[idx] = .{
            .step = self.executed_steps,
            .rip = self.regs.rip,
            .generation = self.ui_handoff.generation,
            .phase = self.ui_handoff.phase,
            .source_id = self.ui_handoff.source_id,
            .callback_handle = self.ui_handoff.callback_handle,
            .callback_rip = self.ui_handoff.callback_rip,
            .worker_handle = self.ui_handoff.worker_handle,
            .worker_rip = self.ui_handoff.worker_rip,
            .no_progress = self.executed_steps -| self.ui_handoff.last_progress_step,
            .suspensions = self.ui_handoff.callback_suspensions,
            .resumes = self.ui_handoff.callback_resumptions,
            .worker_slices = self.ui_handoff.worker_slices,
        };
        self.ui_handoff_index +|= 1;
        if (self.ui_handoff_index >= 5) {
            self.ui_handoff_index = 0;
            self.ui_handoff_filled = true;
        }
    }
    if (suspended.runnable != 0 and suspended_age >= IDLE_STARVATION_STEPS and
        self.executed_steps -| self.last_cooperative_starvation_step >= IDLE_STARVATION_STEPS)
    {
        self.last_cooperative_starvation_step = self.executed_steps;
        self.cooperative_starvation_warnings +|= 1;
        const oldest_symbol = self.metadata.nearestSymbol(suspended.oldest_rip);
        machoCapturePrint(
            "scheduler: RUNNABLE CONTEXT STARVATION: warning={d} handle=0x{x} rip=0x{x} {s}+0x{x} age={d} reason={s} active=0x{x} runnable/blocked={d}/{d}; round-robin quantum rotation should cap this near {d} steps\n",
            .{ self.cooperative_starvation_warnings, suspended.oldest_handle, suspended.oldest_rip, if (oldest_symbol) |resolved| resolved.name else "<unknown>", if (oldest_symbol) |resolved| resolved.offset else 0, suspended_age, suspended.oldest_reason, self.active_guest_thread, suspended.runnable, suspended.blocked, COOPERATIVE_THREAD_QUANTUM_STEPS * @as(u64, @intCast(suspended.runnable + 1)) },
        );
        self.logThreadTable("runnable context starvation");
    }
    if (idle.pending != 0 and idle_age >= IDLE_STARVATION_STEPS and dispatch_block != .callback_already_running) {
        self.idle_starvation_warnings +|= 1;
        machoCapturePrint(
            "macho-processor: IDLE STARVATION: warning={d} source={d} callback=0x{x} tag={s} queued_for={d} steps scheduling_thread=0x{x} scheduling_rip=0x{x} active=0x{x} block={s} suspended={d}/{d}\n",
            .{ self.idle_starvation_warnings, idle.oldest_source, idle.oldest_callback, idle.oldest_tag, idle_age, idle.oldest_scheduling_thread, idle.oldest_scheduling_rip, self.active_guest_thread, @tagName(dispatch_block), self.suspended_guest_thread_count, self.suspended_guest_threads.len },
        );
    }
    self.ui_handoff.diagnose(self.executed_steps, IDLE_STARVATION_STEPS, self.active_guest_thread, self.regs.rip, self.suspended_guest_thread_count);
}

pub fn dumpCoopHeartbeatTrace(self: anytype) void {
    if (!self.coop_heartbeat_filled and self.coop_heartbeat_index == 0) return;
    const count: usize = if (self.coop_heartbeat_filled) 5 else self.coop_heartbeat_index;
    const start: usize = if (self.coop_heartbeat_filled) self.coop_heartbeat_index else 0;
    machoCapturePrint(
        "macho-processor: cooperative heartbeat (most recent {d} entries):\n",
        .{count},
    );
    for (0..count) |i| {
        const idx = (start + i) % 5;
        const e = &self.coop_heartbeat_entries[idx];
        const symbol = self.metadata.nearestSymbol(e.rip);
        machoCapturePrint(
            "  [{d}] step={d} rip=0x{x} {s}+0x{x} thread=0x{x} deferred={d} suspended={d}/{d}/{d} switches={d} yields(wait/quantum/rot)={d}/{d}/{d} idle={d} dispatch={s}\n",
            .{
                i,                                       e.step,                          e.rip,
                if (symbol) |s| s.name else "<unknown>", if (symbol) |s| s.offset else 0, e.thread,
                e.deferred,                              e.suspended_total,               e.suspended_runnable,
                e.suspended_blocked,                     e.switches,                      e.wait_yields,
                e.quantum_yields,                        e.rotation_yields,               e.idle_pending,
                @tagName(e.dispatch_block),
            },
        );
    }
}

pub fn dumpUiHandoffTrace(self: anytype) void {
    if (!self.ui_handoff_filled and self.ui_handoff_index == 0) return;
    const count: usize = if (self.ui_handoff_filled) 5 else self.ui_handoff_index;
    const start: usize = if (self.ui_handoff_filled) self.ui_handoff_index else 0;
    machoCapturePrint(
        "scheduler: UI handoff heartbeat (most recent {d} entries):\n",
        .{count},
    );
    for (0..count) |i| {
        const idx = (start + i) % 5;
        const e = &self.ui_handoff_entries[idx];
        machoCapturePrint(
            "  [{d}] step={d} rip=0x{x} generation={d} phase={s} source={d} callback=0x{x}/0x{x} worker=0x{x}/0x{x} no_progress={d} suspend/resume/slices={d}/{d}/{d}\n",
            .{
                i,                 e.step,            e.rip,
                e.generation,      @tagName(e.phase), e.source_id,
                e.callback_handle, e.callback_rip,    e.worker_handle,
                e.worker_rip,      e.no_progress,     e.suspensions,
                e.resumes,         e.worker_slices,
            },
        );
    }
}

// Once the Xenia PageEntry tables have been allocated, setup can spend a
// long time in memory-manager code without crossing another import
// boundary. Keep a compact, high-frequency checkpoint so a stalled
// backing-map or heap pass is observable in the next external run.
pub fn logMemoryInitializationProgress(self: anytype, steps: u64) void {
    if (!self.mem_init_started) {
        self.mem_init_started = true;
        machoCapturePrint(
            "macho-processor: memory initialization started: step={d} rip=0x{x}\n",
            .{ steps, self.regs.rip },
        );
    }
    const idx = self.mem_init_index;
    self.mem_init_entries[idx] = .{
        .step = steps,
        .rip = self.regs.rip,
        .heap = self.heap_next,
        .sparse_mappings = self.sparse_memory.mappings.items.len,
        .sparse_activations = self.sparse_memory.activations.items.len,
        .deferred_count = self.pthreads.deferred_threads,
        .suspended_count = self.suspended_guest_thread_count,
    };
    self.mem_init_index +|= 1;
    if (self.mem_init_index == 8) {
        self.mem_init_index = 0;
        self.mem_init_filled = true;
    }
}
