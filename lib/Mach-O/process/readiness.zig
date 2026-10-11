// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const application_controller = __ProcessInternals._application_controller;
const contract = __ProcessInternals._contract;
const device_tree = __ProcessInternals._device_tree;
const execution_tracepoints = __ProcessInternals._execution_tracepoints;
const exit_diagnostics = __ProcessInternals._exit_diagnostics;
const gpu = __ProcessInternals._gpu;
const graphics_health_contract = __ProcessInternals._graphics_health_contract;
const guest_log = __ProcessInternals._guest_log;
const guest_wait_liveness = __ProcessInternals._guest_wait_liveness;
const host_contract_coverage = __ProcessInternals._host_contract_coverage;
const interrupt_callback_transaction = __ProcessInternals._interrupt_callback_transaction;
const log = __ProcessInternals._log;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const macho_log = __ProcessInternals._macho_log;
const native_crash = __ProcessInternals._native_crash;
const native_window = __ProcessInternals._native_window;
const native_window_runtime = __ProcessInternals._native_window_runtime;
const near_null_predictor = __ProcessInternals._near_null_predictor;
const notifier_liveness = __ProcessInternals._notifier_liveness;
const ownership_contract = __ProcessInternals._ownership_contract;
const ready_compiler = __ProcessInternals._ready_compiler;
const run_budget = __ProcessInternals._run_budget;
const run_integrity = __ProcessInternals._run_integrity;
const scheduler = __ProcessInternals._scheduler;
const scheduling = __ProcessInternals._scheduling;
const std = __ProcessInternals._std;
const types = __ProcessInternals._types;
const wait_graph = __ProcessInternals._wait_graph;
const xenia_gpu_causal_trace = __ProcessInternals._xenia_gpu_causal_trace;
const xenia_memory_views = __ProcessInternals._xenia_memory_views;
const PresentationFacts = __ProcessInternals._PresentationFacts;
const ReadyPlanContext = __ProcessInternals._ReadyPlanContext;
const guestMemoryConst = __ProcessInternals._guestMemoryConst;
const cocoaGraphicsPolicyFromEnvironment = MachOState.cocoaGraphicsPolicyFromEnvironment;
const deliverGpuInterrupt = MachOState.deliverGpuInterrupt;
const logReadyCompilerFailure = MachOState.logReadyCompilerFailure;
const logReadyCompilerProgress = MachOState.logReadyCompilerProgress;
const logWindowAdmission = MachOState.logWindowAdmission;
const noteStallReleaseGranted = MachOState.noteStallReleaseGranted;
const observeGpuEarlyBoundary = MachOState.observeGpuEarlyBoundary;
const offerGuestFrontBuffer = MachOState.offerGuestFrontBuffer;
const refreshVdSwapContract = MachOState.refreshVdSwapContract;
const run = MachOState.run;
const step = MachOState.step;

pub fn logReadyCompilerDiagnosis(self: anytype) void {
    if (!self.ready.enabled()) return;
    const diagnosis = self.ready.diagnose(self.executed_steps);
    machoCapturePrint(
        "macho-processor: READY COMPILER: DIAGNOSIS progress={s} blockage={s} missing={s} owner={s} description={s} frontier={s}@{d} stall_steps={d} quiet_budget={d} activation_steps={d}/{d} activation_budget_mode={s}\n",
        .{
            diagnosis.progress.label(),
            diagnosis.blockage.label(),
            if (diagnosis.missing_stage.len != 0) diagnosis.missing_stage else "<none>",
            if (diagnosis.missing_owner.len != 0) diagnosis.missing_owner else "<unattributed>",
            if (diagnosis.missing_description.len != 0) diagnosis.missing_description else "<none>",
            if (diagnosis.frontier_stage.len != 0) diagnosis.frontier_stage else "<none>",
            diagnosis.frontier_step,
            diagnosis.quiet_steps,
            diagnosis.quiet_budget_steps,
            diagnosis.activation_steps,
            diagnosis.activation_budget_steps,
            self.ready.activationBudgetMode(),
        },
    );
    // The axis that answers "was the guest obtaining anything" separately
    // from "was the guest executing". A reader who sees advances still
    // climbing next to a stall verdict is looking at a gate that went blind,
    // not at a guest that stopped.
    machoCapturePrint(
        "macho-processor: READY COMPILER: DIAGNOSIS external_progress advances={d} last_step={d} translation_generation={d} heap_high_water=0x{x} heap_live={d} threads_created={d}; translation_generation rises only after PPC guest code is assembled, while the other counters rise only when the guest needs more than it has ever held\n",
        .{
            diagnosis.external_progress_advances,
            diagnosis.external_progress_step,
            diagnosis.external_translation_generation,
            self.ready.external_progress.heap_high_water,
            self.ready.external_progress.heap_live,
            self.ready.external_progress.threads_created,
        },
    );
    machoCapturePrint(
        "macho-processor: READY COMPILER: DIAGNOSIS last_named_work={s} work_owner={s} work_thread=0x{x} work_rip=0x{x} at_step={d} work_units_since_milestone={d} total_work_units={d} slow_progress_notices={d}\n",
        .{
            if (diagnosis.last_work_unit.len != 0) diagnosis.last_work_unit else "<none reported by the stage owner>",
            if (diagnosis.last_work_unit_owner.len != 0) diagnosis.last_work_unit_owner else "<unknown>",
            diagnosis.last_work_unit_thread,
            diagnosis.last_work_unit_rip,
            diagnosis.last_work_unit_step,
            diagnosis.work_units_since_milestone,
            self.ready.work_unit_count,
            self.ready.slow_progress_reports,
        },
    );
    // Who was observed running, next to who owes the next edge. When these
    // disagree the blocked line above is naming a subsystem the launch had
    // not reached yet, and chasing that owner is chasing the wrong code.
    machoCapturePrint(
        "macho-processor: READY COMPILER: DIAGNOSIS attributed_phase={s} attributed_owner={s} attributed_last_phase={s} attributed_last_owner={s} attributed_sites={d}/{d} attributed_credits={d} rejected(off_path_thread/stage_unreached/evidence_spent)={d}/{d}/{d}; attribution says which subsystem was executing, not that it was progressing\n",
        .{
            if (diagnosis.attributed_phase.len != 0) diagnosis.attributed_phase else "<unattributed>",
            if (diagnosis.attributed_owner.len != 0) diagnosis.attributed_owner else "<unattributed>",
            if (diagnosis.attributed_last_phase.len != 0) diagnosis.attributed_last_phase else "<none>",
            if (diagnosis.attributed_last_owner.len != 0) diagnosis.attributed_last_owner else "<none>",
            diagnosis.attributed_symbols,
            ready_compiler.types.max_attributed_symbols,
            diagnosis.attributed_credits,
            self.ready.attributed_rejected_thread,
            self.ready.attributed_rejected_stage,
            self.ready.attributed_symbols_dropped,
        },
    );
    // When a total budget runs out, the contract did not fail: one stage
    // ate the allowance. Naming it and its share is the only actionable
    // fact in the report.
    machoCapturePrint(
        "macho-processor: READY COMPILER: DIAGNOSIS costliest_stage={s} cost_steps={d} cost_percent_of_budget={d}%\n",
        .{
            if (diagnosis.costliest_stage.len != 0) diagnosis.costliest_stage else "<none>",
            diagnosis.costliest_stage_steps,
            diagnosis.costliest_stage_percent,
        },
    );
    const hot_symbol = self.metadata.nearestSymbol(diagnosis.hot_site.rip);
    // A high eviction rate means the sample table could not hold the
    // working set, so the spread below is a sketch. Saying so is better
    // than letting the reader over-trust it.
    const attribution_confidence: []const u8 = if (diagnosis.stall_samples == 0)
        "none"
    else if (diagnosis.stall_evictions *| 2 > diagnosis.stall_samples)
        "low (sample table saturated)"
    else
        "good";
    machoCapturePrint(
        "macho-processor: READY COMPILER: DIAGNOSIS hot_site=0x{x} {s}+0x{x} samples={d}/{d} distinct_sites={d} evictions={d} confidence={s} longest_same_site_run={d} steps=[{d}..{d}]\n",
        .{
            diagnosis.hot_site.rip,
            self.metadata.symbolLabelFor(hot_symbol, diagnosis.hot_site.rip),
            if (hot_symbol) |resolved| resolved.offset else 0,
            diagnosis.hot_site.samples,
            diagnosis.stall_samples,
            diagnosis.distinct_sites,
            diagnosis.stall_evictions,
            attribution_confidence,
            self.ready.longest_same_site_run,
            diagnosis.hot_site.first_step,
            diagnosis.hot_site.last_step,
        },
    );
    machoCapturePrint(
        "macho-processor: READY COMPILER: DIAGNOSIS spin_verdict={s} scheduler(runnable/parked)={d}/{d} wait_object=0x{x} wait_notifications={d} wait_stable_since={d} evidence_step={d}; a concentrated site is not classified as scheduling starvation without all three witnesses\n",
        .{
            diagnosis.spin_verdict.label(),
            self.ready.runnable_threads,
            self.ready.parked_threads,
            self.ready.wait_object,
            self.ready.wait_notifications,
            if (self.ready.wait_notifications == 0)
                self.ready.wait_first_step
            else
                self.ready.wait_last_change_step,
            self.ready.scheduling_evidence_step,
        },
    );
    // One aggregate table averages a parked consumer and a busy producer
    // into a shape that describes neither. Per thread, a mobility of zero
    // is a thread that never moved.
    for (self.ready.stall_threads[0..self.ready.stall_thread_count]) |entry| {
        const thread_symbol = self.metadata.nearestSymbol(entry.last_rip);
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS thread=0x{x} samples={d} mobility={d}% parked={} last_rip=0x{x} {s}+0x{x} steps=[{d}..{d}]\n",
            .{
                entry.thread,
                entry.samples,
                entry.mobilityPercent(),
                entry.parked(),
                entry.last_rip,
                self.metadata.symbolLabelFor(thread_symbol, entry.last_rip),
                if (thread_symbol) |resolved| resolved.offset else 0,
                entry.first_step,
                entry.last_step,
            },
        );
    }
    const parked = self.ready.mostParkedThread();
    if (parked.samples != 0) {
        const parked_symbol = self.metadata.nearestSymbol(parked.last_rip);
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS parked_thread=0x{x} samples={d} rip=0x{x} {s}+0x{x}; this thread never changed its instruction pointer during the window, so it is waiting rather than working\n",
            .{
                parked.thread,
                parked.samples,
                parked.last_rip,
                self.metadata.symbolLabelFor(parked_symbol, parked.last_rip),
                if (parked_symbol) |resolved| resolved.offset else 0,
            },
        );
    }
    machoCapturePrint(
        "macho-processor: READY COMPILER: DIAGNOSIS milestone_thread=0x{x} current_thread=0x{x} thread_changed={} waits(timeout/signaled)={d}/{d} pending_wait=0x{x}\n",
        .{
            diagnosis.milestone_thread,
            diagnosis.current_thread,
            diagnosis.thread_changed,
            self.ready.wait_timeout_count,
            self.ready.wait_signal_count,
            self.ready.pending_wait_object,
        },
    );
    machoCapturePrint(
        "macho-processor: READY COMPILER: GUIDANCE {s}\n",
        .{diagnosis.guidance()},
    );
}

pub fn logReadyCompilerSummary(self: anytype) void {
    if (!self.ready.enabled()) return;
    const missing = self.ready.firstMissingRequired();
    var passed_compile_checks: usize = 0;
    for (self.ready.compile_checks[0..self.ready.compile_check_count]) |check| {
        if (check.passed) passed_compile_checks += 1;
    }
    machoCapturePrint(
        "macho-processor: READY COMPILER SUMMARY: phase={s} enforce={} progress={s} activation_budget={d} activation_budget_mode={s} terminal={} compile_checks={d}/{d} checks_dropped={d} functions={d} functions_dropped={d} compiler_diagnostics={d} waits(timeout/signaled)={d}/{d} milestones={d}/{d} work_units={d} slow_notices={d} activation_start={d} last_milestone={d} last_named_work={d} last_progress={d} missing={s} missing_owner={s} failure={s}\n",
        .{
            @tagName(self.ready.phase),
            self.ready.enforce,
            self.ready.classifyProgress(self.executed_steps).label(),
            if (self.ready.contract) |active_contract| active_contract.activation_budget_steps else 0,
            self.ready.activationBudgetMode(),
            self.ready.terminal(),
            passed_compile_checks,
            self.ready.compile_check_count,
            self.ready.compile_checks_dropped,
            self.ready.function_count,
            self.ready.functions_dropped,
            self.ready.compiler_diagnostic_count,
            self.ready.wait_timeout_count,
            self.ready.wait_signal_count,
            @popCount(self.ready.reached_mask),
            if (self.ready.contract) |active_contract| active_contract.stages.len else 0,
            self.ready.work_unit_count,
            self.ready.slow_progress_reports,
            self.ready.activation_start_step,
            self.ready.last_milestone_step,
            self.ready.lastNamedProgressStep(),
            self.ready.last_progress_step,
            if (missing) |stage| stage.name else "<none>",
            if (missing) |stage|
                (if (stage.owner.len != 0) stage.owner else "<unattributed>")
            else
                "<none>",
            self.ready.failure.kind.label(),
        },
    );
    self.logReadyCompilerProgress();
    // A failure emits its own evidence below, next to the blocked line.
    // Without one, the summary is the only place the evidence can appear,
    // so a run that stopped short without a typed failure still explains
    // where startup actually got to.
    if (self.ready.failure.kind == .none) self.logReadyCompilerDiagnosis();
    for (self.ready.compile_checks[0..self.ready.compile_check_count]) |check| {
        machoCapturePrint(
            "macho-processor: READY COMPILER: report compile-check name={s} passed={} detail={s}\n",
            .{ check.name, check.passed, check.detail },
        );
    }
    if (self.ready.contract) |active_contract| {
        for (active_contract.stages) |spec| {
            const stage_bit = @as(u64, 1) << @as(u6, @intCast(spec.id));
            const reached = self.ready.reached_mask & stage_bit != 0;
            machoCapturePrint(
                "macho-processor: READY COMPILER: report stage id={d} name={s} required={} reached={} owner={s} first_step={d} elapsed_steps={d} prerequisites=0x{x} missing_prerequisites=0x{x} blockage={s} description={s}\n",
                .{
                    spec.id,
                    spec.name,
                    spec.required,
                    reached,
                    if (spec.owner.len != 0) spec.owner else "<unattributed>",
                    self.ready.first_stage_step[@intCast(spec.id)],
                    self.ready.stage_duration[@intCast(spec.id)],
                    spec.prerequisites,
                    spec.prerequisites & ~self.ready.reached_mask,
                    // Naming the blockage per stage separates "could not
                    // have run yet" from "ran and stayed silent" without
                    // making the reader decode the prerequisite mask.
                    if (reached)
                        "NONE"
                    else if (spec.prerequisites & ~self.ready.reached_mask != 0)
                        "PREREQUISITES_UNMET"
                    else
                        "OWNER_SILENT",
                    spec.description,
                },
            );
        }
    }
    for (self.ready.functions[0..self.ready.function_count]) |function| {
        machoCapturePrint(
            "macho-processor: READY COMPILER: report function address=0x{x} state={s} module={s} name={s} compile_started={d} compiled={d} installed={d} entered={d} last_progress={d} entry_thread=0x{x} caller=0x{x}\n",
            .{
                function.address,
                @tagName(function.state),
                if (function.module.len != 0) function.module else "<unknown>",
                if (function.name.len != 0) function.name else "<unknown>",
                function.compile_started_step,
                function.compiled_step,
                function.installed_step,
                function.entered_step,
                function.last_progress_step,
                function.entry_thread,
                function.caller,
            },
        );
    }
    // The approach to the frontier, oldest first. The last breadcrumb says
    // where startup stopped; the trail says how it got there, which is what
    // separates a subsystem that never started from one that got most of
    // the way through and stopped on a specific step.
    var trail_position: usize = 0;
    while (trail_position < ready_compiler.types.work_unit_history_len) : (trail_position += 1) {
        const entry = self.ready.workUnitHistoryAt(trail_position);
        if (entry.len == 0) continue;
        machoCapturePrint(
            "macho-processor: READY COMPILER: report work-unit [{d}] step={d} owner={s} thread=0x{x} rip=0x{x} name={s}\n",
            .{ trail_position, entry.step, if (entry.ownerSlice().len != 0) entry.ownerSlice() else "<unknown>", entry.thread, entry.rip, entry.slice() },
        );
    }
    // Where the guest spent the window that never reached the next edge.
    // The shape of this table is the finding: one site holding nearly every
    // sample is a loop, while a wide spread is ordinary forward execution
    // that simply has no breadcrumb naming it.
    // Hottest first, and only the top few: dumping every occupied slot in
    // hash order buries the site that matters under single-sample noise.
    var site_rank: usize = 0;
    while (site_rank < ready_compiler.types.reported_stall_sites) : (site_rank += 1) {
        const site = self.ready.siteByRank(site_rank);
        if (site.samples == 0) break;
        const symbol = self.metadata.nearestSymbol(site.rip);
        machoCapturePrint(
            "macho-processor: READY COMPILER: report site [{d}] rip=0x{x} {s}+0x{x} samples={d}/{d} thread=0x{x} steps=[{d}..{d}]\n",
            .{
                site_rank,
                site.rip,
                self.metadata.symbolLabelFor(symbol, site.rip),
                if (symbol) |resolved| resolved.offset else 0,
                site.samples,
                self.ready.stall_samples,
                site.thread,
                site.first_step,
                site.last_step,
            },
        );
    }
    if (self.ready.distinctSites() > site_rank) {
        machoCapturePrint(
            "macho-processor: READY COMPILER: report site ... {d} colder sites omitted of {d} occupied\n",
            .{ self.ready.distinctSites() - site_rank, self.ready.distinctSites() },
        );
    }
    if (self.ready.pending_wait_object != 0) {
        machoCapturePrint(
            "macho-processor: READY COMPILER: report pending-wait object=0x{x} since_step={d}\n",
            .{ self.ready.pending_wait_object, self.ready.pending_wait_step },
        );
    }
    if (self.ready.failure.kind != .none) self.logReadyCompilerFailure();
}

pub fn emitReadyPlanUnit(context: *anyopaque, progress: ready_compiler.plan.Progress) void {
    _ = context;
    switch (progress.outcome) {
        .ok => machoCapturePrint(
            "macho-processor: READY COMPILER: [{d}/{d}] Checking {s} object {s}\n",
            .{ progress.index, progress.total, progress.unit.category.label(), progress.unit.name },
        ),
        .failed => machoCapturePrint(
            "macho-processor: READY COMPILER: [{d}/{d}] FAILED {s} object {s}: {s} (needed for: {s})\n",
            .{
                progress.index,
                progress.total,
                progress.unit.category.label(),
                progress.unit.name,
                progress.detail,
                progress.unit.purpose,
            },
        ),
        .indeterminate => machoCapturePrint(
            "macho-processor: READY COMPILER: [{d}/{d}] UNKNOWN {s} object {s}: {s}\n",
            .{
                progress.index,
                progress.total,
                progress.unit.category.label(),
                progress.unit.name,
                progress.detail,
            },
        ),
        .skipped, .pending => {},
    }
}

pub fn readyPlanAssetKind(path: []const u8) ?ready_compiler.plan.AssetKind {
    if (std.mem.endsWith(u8, path, ".iso")) return .disc_image;
    if (std.mem.endsWith(u8, path, ".xex")) return .xex;
    if (std.mem.endsWith(u8, path, ".toml")) return .toml;
    if (std.mem.endsWith(u8, path, ".spv")) return .spirv;
    if (std.mem.endsWith(u8, path, ".dylib")) return .dylib;
    if (std.mem.endsWith(u8, path, ".zar") or
        std.mem.endsWith(u8, path, ".zip") or
        std.mem.endsWith(u8, path, ".xcp") or
        std.mem.endsWith(u8, path, ".bin")) return .any_file;
    return null;
}

pub fn readyPlanCachePath() ?[]const u8 {
    if (std.c.getenv("ROSETTE_READY_COMPILER_CACHE")) |raw| {
        const value = std.mem.span(raw);
        if (value.len == 0 or std.ascii.eqlIgnoreCase(value, "off")) return null;
        return value;
    }
    // The event logger creates .rosette before this plan runs.  Keeping
    // the cache beside the two diagnostic logs makes it route-local and
    // avoids putting generated artifacts in the source tree.
    return ".rosette/ready-compiler.plan.cache";
}

pub fn readyPackagePath() ?[]const u8 {
    if (std.c.getenv("ROSETTE_READY_COMPILER_PACKAGE")) |raw| {
        const value = std.mem.span(raw);
        if (value.len == 0 or std.ascii.eqlIgnoreCase(value, "off")) return null;
        return value;
    }
    return ".rosette/packages/xenia-halo3-ready.r3pkg";
}

pub fn runReadyCompilerPlan(
    self: anytype,
    io: std.Io,
    image_path: []const u8,
    args: []const []const u8,
    vex_ready: bool,
) bool {
    if (!self.ready.enabled()) return true;

    var assets_storage: [16]ready_compiler.xenia_plan.AssetUnit = undefined;
    var asset_count: usize = 0;
    // The files this run will actually touch are the ones it was pointed
    // at. Declaring a fixed list would check paths this launch does not
    // use and miss the one it does.
    for (args) |argument| {
        if (asset_count >= assets_storage.len) break;
        if (argument.len == 0 or argument[0] == '-') continue;
        const kind = readyPlanAssetKind(argument) orelse continue;
        assets_storage[asset_count] = .{
            .path = argument,
            .kind = kind,
            .purpose = "a file this launch was pointed at",
        };
        asset_count += 1;
    }

    var plan_storage = ready_compiler.plan.Plan{};
    ready_compiler.xenia_plan.build(&plan_storage, assets_storage[0..asset_count]);

    var context = ReadyPlanContext{
        .state = self,
        .io = io,
        .image_path = image_path,
        .vex_ready = vex_ready,
    };
    for (ready_compiler.xenia_plan.contract_units) |unit| context.addTarget(unit.fragment);
    for (ready_compiler.xenia_plan.symbol_units) |unit| context.addTarget(unit.fragment);
    const cache_path = readyPlanCachePath();
    const package_path = readyPackagePath();
    context.image_fingerprint = context.executableFingerprint() orelse 0;
    context.target_fingerprint = context.targetFingerprint();

    var restored_cache = false;
    if (package_path) |path| {
        if (context.image_fingerprint != 0) {
            if (ready_compiler.package.load(path, self.allocator)) |manifest| {
                if (manifest.matchesStaticPlan(
                    context.image_fingerprint,
                    ready_compiler.xenia_plan.fingerprint(),
                    context.target_fingerprint,
                    context.target_count,
                )) {
                    context.restoreCachedReferences(.{
                        .image_fingerprint = manifest.image_fingerprint,
                        .contract_fingerprint = manifest.contract_fingerprint,
                        .target_fingerprint = manifest.static_plan_target_fingerprint,
                        .target_count = manifest.static_plan_target_count,
                        .referenced_mask = manifest.static_plan_referenced_mask,
                        .scanned_bytes = manifest.static_plan_scanned_bytes,
                        .direct_call_sites = manifest.static_plan_direct_call_sites,
                    });
                    restored_cache = true;
                    machoCapturePrint(
                        "macho-processor: READY COMPILER: package HIT path={s} image=0x{x} targets={d} scanned_bytes={d} direct_call_sites={d}\n",
                        .{ path, context.image_fingerprint, context.target_count, context.scanned_bytes, context.direct_call_sites },
                    );
                }
            }
        }
    }
    if (!restored_cache) if (cache_path) |path| {
        if (context.image_fingerprint != 0) {
            if (ready_compiler.cache.load(path, self.allocator)) |snapshot| {
                if (ready_compiler.cache.matches(
                    snapshot,
                    context.image_fingerprint,
                    ready_compiler.xenia_plan.fingerprint(),
                    context.target_fingerprint,
                    context.target_count,
                )) {
                    context.restoreCachedReferences(snapshot);
                    restored_cache = true;
                    machoCapturePrint(
                        "macho-processor: READY COMPILER: static plan cache HIT path={s} image=0x{x} targets={d} scanned_bytes={d} direct_call_sites={d}\n",
                        .{ path, context.image_fingerprint, context.target_count, context.scanned_bytes, context.direct_call_sites },
                    );
                }
            }
        }
    };
    if (!restored_cache) {
        context.scanReferences();
        if (cache_path) |path| {
            if (context.image_fingerprint == 0) {
                machoCapturePrint(
                    "macho-processor: READY COMPILER: static plan cache skipped because executable fingerprinting was unavailable\n",
                    .{},
                );
            } else {
                if (ready_compiler.cache.store(path, self.allocator, context.snapshot())) {
                    machoCapturePrint(
                        "macho-processor: READY COMPILER: static plan cache STORE path={s} image=0x{x} targets={d} scanned_bytes={d} direct_call_sites={d}\n",
                        .{ path, context.image_fingerprint, context.target_count, context.scanned_bytes, context.direct_call_sites },
                    );
                } else {
                    machoCapturePrint(
                        "macho-processor: READY COMPILER: static plan cache unavailable path={s}; continuing with in-memory evidence\n",
                        .{path},
                    );
                }
            }
        }
    }

    machoCapturePrint(
        "macho-processor: READY COMPILER: compile plan OPEN units={d} assets={d} reference_targets={d} scanned_bytes={d} direct_call_sites={d}\n",
        .{
            plan_storage.count,
            asset_count,
            context.target_count,
            context.scanned_bytes,
            context.direct_call_sites,
        },
    );

    const emitter = ready_compiler.plan.Emitter{
        .context = &context,
        .emit = emitReadyPlanUnit,
    };
    const summary = plan_storage.run(context.probe(), emitter);

    const static_snapshot = context.snapshot();
    if (summary.halted_at == 0 and package_path != null and static_snapshot.image_fingerprint != 0) {
        const manifest = ready_compiler.xenia_plan.packageManifest(static_snapshot);
        if (ready_compiler.package.store(package_path.?, self.allocator, manifest)) {
            machoCapturePrint(
                "macho-processor: READY COMPILER: package STORE path={s} kind=xenia-halo3-startup artifacts={d} image=0x{x} target_fingerprint=0x{x}\n",
                .{ package_path.?, manifest.artifact_count, manifest.image_fingerprint, manifest.static_plan_target_fingerprint },
            );
        } else {
            machoCapturePrint(
                "macho-processor: READY COMPILER: package unavailable path={s}; static evidence remains in memory/cache\n",
                .{package_path.?},
            );
        }
    }

    machoCapturePrint(
        "macho-processor: READY COMPILER: compile plan {s} units={d}/{d} ok={d} failed={d} unknown={d} skipped={d}\n",
        .{
            if (summary.halted_at != 0) "RED" else if (summary.failed != 0) "AMBER" else "GREEN",
            summary.ok,
            summary.total,
            summary.ok,
            summary.failed,
            summary.indeterminate,
            summary.skipped,
        },
    );
    if (summary.halted_at != 0) {
        machoCapturePrint(
            "macho-processor: READY COMPILER: compile plan RED at [{d}/{d}] {s} object {s}; halting before the guest executes because every later verdict would be a consequence of this\n",
            .{
                summary.halted_at,
                summary.total,
                summary.halted_unit.category.label(),
                summary.halted_unit.name,
            },
        );
        self.ready.noteCompileCheck(
            "startup-plan",
            false,
            "a required startup precondition is missing; see the compile plan units above",
        );
        return false;
    }
    // Advisory units that failed are reported and do not stop the run.
    // Most of them are reachability, where a missing direct call site is
    // evidence about the scan's reach as much as about the guest, and
    // refusing to launch over that would be failing on the gate's own
    // blind spot.
    if (summary.failed != 0 or summary.indeterminate != 0) {
        machoCapturePrint(
            "macho-processor: READY COMPILER: compile plan AMBER advisory_failures={d} unknown={d}; every required precondition resolved, so the run continues\n",
            .{ summary.failed, summary.indeterminate },
        );
    }
    self.ready.noteCompileCheck(
        "startup-plan",
        true,
        "every required startup precondition resolved before execution",
    );
    return true;
}

pub fn logNotifierLiveness(self: anytype) void {
    const object = self.pthreads.worstWaitObject(self.executed_steps) orelse return;
    const progress = notifier_liveness.classify(
        object,
        self.executed_steps,
        notifier_liveness.default_stall_steps,
    );
    const notifier_symbol = self.metadata.nearestSymbol(object.last_notify_pc);
    const waiter_symbol = self.metadata.nearestSymbol(object.last_waiter_pc);
    // The parked PC is frequently inside an inlined condition-variable
    // wait with no symbol of its own, which leaves the report naming an
    // address nobody can act on. The thread's start routine is the same
    // thread's identity and does carry a symbol, and it is the fact that
    // separates an intentionally idle worker from a missing producer.
    const waiter_origin = self.pthreads.startRoutineFor(object.last_waiter_thread);
    const origin_symbol = self.metadata.nearestSymbol(waiter_origin);
    // A granted repair that ended in a re-park is a stronger statement
    // than "nobody ever signalled it": the waiter's predicate was checked
    // and found false, so this is a guest-side deadlock, not a lost wake.
    const repaired = object.repair_attempts != 0;
    machoCapturePrint(
        "macho-processor: NOTIFIER LIVENESS: object=0x{x} state={s} waiters={d} distinct_notifiers={d} notifications={d} repairs={d} steps_since_notify={d} waiting_since_step={d} last_notify(step={d} thread=0x{x} pc=0x{x} symbol={s}+0x{x}) waiter(thread=0x{x} pc=0x{x} symbol={s}+0x{x})\n",
        .{
            object.address,
            progress.label(),
            object.waiterCount(),
            object.notifierCount(),
            object.notifications,
            object.repair_attempts,
            self.executed_steps -| object.last_notify_step,
            object.first_wait_step,
            object.last_notify_step,
            object.last_notify_thread,
            object.last_notify_pc,
            self.metadata.symbolLabelFor(notifier_symbol, object.last_notify_pc),
            if (notifier_symbol) |resolved| resolved.offset else 0,
            object.last_waiter_thread,
            object.last_waiter_pc,
            self.metadata.symbolLabelFor(waiter_symbol, object.last_waiter_pc),
            if (waiter_symbol) |resolved| resolved.offset else 0,
        },
    );
    machoCapturePrint(
        "macho-processor: NOTIFIER LIVENESS WAITER ORIGIN: thread=0x{x} start_routine=0x{x} symbol={s}+0x{x}; the parked program counter is often inside an inlined wait with no symbol of its own, so the routine the thread was started on is what names which subsystem is waiting — and therefore whether this is a worker with nothing to do or a producer that never arrived\n",
        .{
            object.last_waiter_thread,
            waiter_origin,
            self.metadata.symbolLabelFor(origin_symbol, waiter_origin),
            if (origin_symbol) |resolved| resolved.offset else 0,
        },
    );
    if (repaired) {
        machoCapturePrint(
            "macho-processor: NOTIFIER LIVENESS GUIDANCE: a bounded spurious wake was already granted {d} time(s) and the waiter re-parked — the predicate is genuinely unsatisfied. The creator never published the state it waits on; find the code that should have published it and confirm it ran. The once-per-generation guard stops further wakes, so this cannot become a synthetic busy loop\n",
            .{object.repair_attempts},
        );
    } else {
        machoCapturePrint("macho-processor: NOTIFIER LIVENESS GUIDANCE: {s}\n", .{progress.guidance()});
    }
    // The repair is per-class, not per-report: an `observed_notifiers_parked`
    // object can outrank a never-notified one for the report, but only
    // never-notified waiters have the lost-wakeup repair, and the selector
    // inside `wakeNeverNotifiedWaiter` already applies the stall gate. The
    // quiescence repair cannot reach these waiters: the rest of the run is
    // alive, so "nothing runnable" never became true.
    //
    // Do not mutate a potentially healthy host worker merely because its
    // condition variable has never been signalled. If this is a confirmed
    // guest lost-wakeup, the old bounded experiment remains available via
    // ROSETTE_MACHO_NEVER_NOTIFIED_REPAIR=1.
    if (self.never_notified_repair_enabled) {
        if (self.pthreads.wakeNeverNotifiedWaiter(self.executed_steps)) |repair| {
            const woken_symbol = self.metadata.nearestSymbol(repair.thread);
            machoCapturePrint(
                "macho-processor: NOTIFIER LIVENESS REPAIR: granted one generation-bounded POSIX spurious wake thread=0x{x} object=0x{x} waited_steps={d} symbol={s}; the guest predicate loop re-checks its own condition on return\n",
                .{
                    repair.thread,
                    repair.object,
                    repair.waited_steps,
                    self.metadata.symbolLabelFor(woken_symbol, repair.thread),
                },
            );
            // The wake happened here; what it proved is judged elsewhere.
            // A release nobody reads the outcome of is a workaround, and
            // one whose outcome is recorded is an experiment that settles
            // which codebase the defect is in.
            self.noteStallReleaseGranted(repair.object, repair.thread, repair.waited_steps);
        }
    } else if (progress == .never_notified) {
        machoCapturePrint(
            "macho-processor: NOTIFIER LIVENESS REPAIR: disabled by default for never-notified waits; this may be an intentional idle worker. Set ROSETTE_MACHO_NEVER_NOTIFIED_REPAIR=1 only after identifying a guest lost-wakeup\n",
            .{},
        );
    }
}

pub fn logRegisterApertureTraffic(self: anytype) void {
    const observer = &self.gpu_register_aperture;
    const ring = observer.ringSetupWrites();
    machoCapturePrint(
        "  gpu register aperture: base=0x{x} size=0x{x} reads={d} writes={d} delivered={d} undelivered={d} ring_setup_writes={d} (delivered={d}) registers_touched={d} untracked={d} misaligned={d} verdict={s}; {s}\n",
        .{
            device_tree.gpu.xenos.register_aperture_base,
            device_tree.gpu.xenos.register_aperture_size,
            observer.total_reads,
            observer.total_writes,
            observer.total_delivered,
            observer.total_undelivered,
            ring.writes,
            ring.delivered,
            observer.count,
            observer.untracked_accesses,
            observer.misaligned,
            @tagName(observer.verdict()),
            observer.verdict().describe(),
        },
    );
    for (observer.registers[0..observer.count]) |entry| {
        machoCapturePrint(
            "    register index=0x{x} {s} reads={d} writes={d} delivered={d} undelivered={d} last_value=0x{x} nonzero_write={} first_step={d} first_rip=0x{x} first_thread=0x{x}\n",
            .{
                entry.index,
                entry.name(),
                entry.reads,
                entry.writes,
                entry.delivered,
                entry.undelivered,
                entry.last_value,
                entry.saw_nonzero_write,
                entry.first_step,
                entry.first_rip,
                entry.first_thread,
            },
        );
    }
}

pub fn logAnomalyLedger(self: anytype) void {
    const ledger = &self.anomalies;
    if (ledger.count == 0) return;
    machoCapturePrint(
        "macho-processor: ANOMALY LEDGER: distinct={d} unclassified={d} implicated={d} overflow={d} signoff_clean={s}; {s}\n",
        .{
            ledger.count,
            ledger.unclassified(),
            ledger.implicated(),
            ledger.overflow,
            if (ledger.signoffClean()) "YES" else "NO",
            ledger.verdict(),
        },
    );
    for (ledger.records[0..ledger.count]) |record| {
        machoCapturePrint(
            "  anomaly kind={s} occurrences={d} disposition={s} first_step={d} thread=0x{x} caller=0x{x} detail={s}\n",
            .{
                record.kind.label(),
                record.occurrences,
                record.disposition.label(),
                record.step,
                record.guest_thread,
                record.caller_pc,
                record.detailSlice(),
            },
        );
    }
}

pub fn refreshGraphicsContract(self: anytype) void {
    const ledger = &self.graphics_contract;
    const tracepoints = &self.execution_tracepoints;
    const at = self.executed_steps;

    // Harness-owned platform surface. Rosette supplies these, so they are
    // recorded through `satisfy` — which the ledger permits only because
    // Rosette owns them. On Windows the equivalent state exists before the
    // title runs; here it exists because the harness made it.
    if (self.native_window.layer_attachments != 0) {
        _ = ledger.satisfy(.native_window_surface, at);
    }
    if (self.native_window.surface_bindings != 0) {
        _ = ledger.satisfy(.native_presenter_bound, at);
        // A bound surface is the evidence the backend instance and the
        // adapter were negotiated: neither a VkSurfaceKHR nor a CAMetalLayer
        // can be produced without them.
        _ = ledger.satisfy(.backend_instance_negotiated, at);
        _ = ledger.satisfy(.physical_adapter_negotiated, at);
    }
    // Either presentation path proves the capability. Keying this on the
    // Metal diagnostic counter alone made a run whose presenter came up
    // through Vulkan report presentation as outstanding harness work while
    // frames were on the window — the report then sent a reader to write
    // code that already existed, which is worse than reporting nothing.
    if (self.native_window.diagnostic_frames_presented != 0 or
        self.dynamic_forwarder.nativePresenterFramesPresented() != 0 or
        self.dynamic_forwarder.nativePresenterStage().isReady())
    {
        _ = ledger.satisfy(.presentation_capability_negotiated, at);
    }
    // Only typed wait evidence satisfies this boundary. A success result
    // by itself cannot distinguish ready-on-entry from block-and-release.
    if (self.guest_wait_liveness.provesSignalConsumption()) {
        _ = ledger.satisfy(.wait_primitives_consume_signals, at);
    }

    // Emulator-owned bring-up, observed only.
    if (self.gpu_bootstrap.seen(.initialize_engines)) ledger.observe(.gpu_engines_initialised, at);
    if (self.gpu_bootstrap.seen(.graphics_interrupt_callback)) ledger.observe(.interrupt_callback_registered, at);
    // The bootstrap ladder learns this from the emulator's log lines. The
    // tracepoint at `EmulateCPInterruptDPC` learns it from the instruction
    // pointer, and on the 2026-08-31 run it had fired a hundred and fifty
    // times while this clause still read "registered but never fired". A
    // clause a stronger observer has already satisfied must not stay unmet.
    if (self.gpu_bootstrap.seen(.graphics_interrupt_dispatch) or
        self.gpu_bringup_gate.recordFor(.emulate_cp_interrupt_dpc).crossed())
    {
        ledger.observe(.interrupt_callback_dispatched, at);
    }
    if (self.gpu_bootstrap.seen(.ring_buffer)) ledger.observe(.ring_buffer_initialised, at);

    // Title-owned behaviour, observed only. `satisfy` would refuse these
    // anyway; observing is the only way they can ever be met.
    const publication = &self.gpu_ring_publication;
    if (publication.published()) ledger.observe(.guest_ring_payload_published, at);
    if (publication.advances != 0) ledger.observe(.guest_write_pointer_advanced, at);
    if (self.gpu_bootstrap.seen(.pm4_packet_consumed)) ledger.observe(.guest_pm4_consumed, at);
    if (tracepoints.roleEntered(.swap)) ledger.observe(.guest_swap_entered, at);
    if (self.guest_vdswap_packet_encoded) ledger.observe(.swap_packet_encoded, at);
    if (self.gpu_vd_swap_contract.authentic_consumptions != 0) ledger.observe(.swap_consumed_by_command_processor, at);
    if (tracepoints.roleEntered(.presenter)) ledger.observe(.presenter_output_refreshed, at);

    self.refreshVdSwapContract();
}

pub fn recordGraphicsHealth(
    self: anytype,
    stage: graphics_health_contract.Stage,
    state: graphics_health_contract.State,
    source: graphics_health_contract.Source,
    count: u64,
    note: []const u8,
) void {
    self.graphics_health.record(stage, state, self.executed_steps, source, count, note);
}

pub fn guestOutputFramesPresented(self: anytype) u64 {
    const ledger = &self.dynamic_forwarder.native_presenter.ledger;
    return gpu.presentation_provenance.guestFrameCount(
        ledger.guest_output_frames_presented,
        self.native_window.guest_frames_presented,
    );
}

pub fn syncPresentationProvenance(self: anytype) void {
    const native = &self.dynamic_forwarder.native_presenter.ledger;
    const paint = self.gpu_bringup_gate.recordFor(.host_paint);
    _ = self.presentation_provenance.observe(.{
        .step = self.executed_steps,
        .native_presenter_ready = self.dynamic_forwarder.nativePresenterStage().isReady(),
        .guest_source_available = self.dynamic_forwarder.guestFrontBufferAvailable() or self.gpu_frontbuffer != null,
        .host_source_available = native.host_frames_presented != 0 or self.dynamic_forwarder.guestVulkanPresentRequests() != 0,
        .guest_frames_presented = self.guestOutputFramesPresented(),
        .host_frames_presented = native.host_frames_presented,
        .diagnostic_frames_presented = native.diagnostic_frames_presented +| self.native_window.diagnostic_frames_presented,
        .guest_swap_observed = self.execution_tracepoints.roleEntered(.swap) or
            self.guest_vdswap_packet_encoded or
            self.gpu_vd_swap_contract.authentic_consumptions != 0,
        .presenter_paint_crossed = paint.crossed(),
        .presenter_paint_last_step = paint.last_step,
    });
    self.gpu_bringup_gate.setRepeatingLivenessEligible(
        .host_paint,
        self.presentation_provenance.livenessEligible(),
    );
}

pub fn logPresentationProvenance(self: anytype, force: bool) void {
    self.syncPresentationProvenance();
    const ledger = &self.presentation_provenance;
    const fingerprint = ledger.fingerprint();
    if (!force and fingerprint == self.presentation_provenance_last_fingerprint) return;
    self.presentation_provenance_last_fingerprint = fingerprint;
    const snapshot = ledger.last;
    const verdict = ledger.current();
    const missing = ledger.missingBoundary();
    machoCapturePrint(
        "macho-processor: GPU PRESENTATION PROVENANCE: verdict={s} missing={s} native_ready={s} guest_source={s} host_source={s} guest_frames={d} host_frames={d} diagnostic_frames={d} guest_swap={s} presenter_paint={s} paint_liveness={s} transitions={d} first_source_step={d} first_guest_frame_step={d} first_host_frame_step={d} step={d}; {s}; diagnostic-only paint is sink evidence, never guest-output evidence\n",
        .{
            verdict.label(),
            missing.label(),
            if (snapshot.native_presenter_ready) "YES" else "NO",
            if (snapshot.guest_source_available) "YES" else "NO",
            if (snapshot.host_source_available) "YES" else "NO",
            snapshot.guest_frames_presented,
            snapshot.host_frames_presented,
            snapshot.diagnostic_frames_presented,
            if (snapshot.guest_swap_observed) "YES" else "NO",
            if (snapshot.presenter_paint_crossed) "YES" else "NO",
            if (ledger.livenessEligible()) "YES" else "NO",
            ledger.transitions,
            ledger.first_source_step,
            ledger.first_guest_frame_step,
            ledger.first_host_frame_step,
            self.executed_steps,
            verdict.describe(),
        },
    );
    self.logGuestOutputMailbox(snapshot.guest_swap_observed);
}

pub fn logGuestOutputMailbox(self: anytype, swap_observed: bool) void {
    const ledger = &self.gpu_guest_output_mailbox;
    if (ledger.observations == 0) return;
    const verdict = ledger.verdict(swap_observed);
    const latest = ledger.latest;
    machoCapturePrint(
        "macho-processor: GUEST OUTPUT MAILBOX: verdict={s} owner={s} reason={s} mailbox={d} frontbuffer=0x{x} refresh(attempts/successes)={d}/{d} peak(attempts/successes)={d}/{d} force_clear_frames={d} rosette_swap_observed={s} observations={d} first_step={d} last_step={d} step={d}; {s}\n",
        .{
            verdict.label(),
            verdict.owner(),
            latest.reason.label(),
            latest.mailbox_index,
            latest.frontbuffer,
            latest.refresh_attempts,
            latest.refresh_successes,
            ledger.peak_refresh_attempts,
            ledger.peak_refresh_successes,
            ledger.force_clear_frames,
            if (swap_observed) "YES" else "NO",
            ledger.observations,
            ledger.first_step,
            ledger.last_step,
            self.executed_steps,
            verdict.describe(),
        },
    );
}

pub fn logNearNullDispatchStatus(self: anytype, force: bool) void {
    const predictor = &self.near_null_predictor;
    const fingerprint = predictor.statusFingerprint();
    if (!force and fingerprint == self.near_null_status_last_fingerprint) return;
    self.near_null_status_last_fingerprint = fingerprint;
    const status = predictor.status();
    machoCapturePrint(
        "macho-processor: NEAR NULL DISPATCH CONTRACT: verdict={s} observed=YES import_receiver_events={d} native_receiver_events={d} object_header_clobbers={d} benign_skipped={d} signatures={d} emissions={d} step={d}; {s}; absence of a retained event is bounded observer evidence, not proof that every pointer is valid\n",
        .{
            status.label(),
            predictor.near_null_dispatches -| predictor.benign_skipped,
            predictor.native_receiver_events,
            predictor.clobber_events,
            predictor.benign_skipped,
            predictor.distinct_signatures,
            predictor.emissions,
            self.executed_steps,
            status.describe(),
        },
    );
}

pub fn recordNativePresenterPrerequisites(self: anytype, state: graphics_health_contract.State, note: []const u8) void {
    self.recordGraphicsHealth(.vulkan_loader_resolved, state, .native_presenter, 1, note);
    self.recordGraphicsHealth(.vulkan_instance_ready, state, .native_presenter, 1, note);
    self.recordGraphicsHealth(.vulkan_surface_ready, state, .native_presenter, 1, note);
    self.recordGraphicsHealth(.physical_adapter_ready, state, .native_presenter, 1, note);
    self.recordGraphicsHealth(.logical_device_ready, state, .native_presenter, 1, note);
    self.recordGraphicsHealth(.graphics_queue_ready, state, .native_presenter, 1, note);
    self.recordGraphicsHealth(.swapchain_ready, state, .native_presenter, 1, note);
    self.recordGraphicsHealth(.frame_resources_ready, state, .native_presenter, 1, note);
}

pub fn refreshNativePresenterHealth(self: anytype) void {
    const stage = self.dynamic_forwarder.nativePresenterStage();
    if (self.dynamic_forwarder.native_presenter_attempts == 0) return;

    switch (stage) {
        .unstarted => {},
        .loader_unavailable => self.recordGraphicsHealth(.vulkan_loader_resolved, .blocked, .native_presenter, 1, stage.label()),
        .instance_extensions_missing, .instance_failed => {
            self.recordGraphicsHealth(.vulkan_loader_resolved, .satisfied, .native_presenter, 1, "vkGetInstanceProcAddr resolved");
            self.recordGraphicsHealth(.vulkan_instance_ready, .blocked, .native_presenter, 1, stage.label());
        },
        .surface_failed => {
            self.recordGraphicsHealth(.vulkan_loader_resolved, .satisfied, .native_presenter, 1, "Vulkan loader resolved");
            self.recordGraphicsHealth(.vulkan_instance_ready, .satisfied, .native_presenter, 1, "native instance created");
            self.recordGraphicsHealth(.vulkan_surface_ready, .blocked, .native_presenter, 1, stage.label());
        },
        .no_supported_physical_device => {
            self.recordGraphicsHealth(.vulkan_loader_resolved, .satisfied, .native_presenter, 1, "Vulkan loader resolved");
            self.recordGraphicsHealth(.vulkan_instance_ready, .satisfied, .native_presenter, 1, "native instance created");
            self.recordGraphicsHealth(.vulkan_surface_ready, .satisfied, .native_presenter, 1, "Metal surface created");
            self.recordGraphicsHealth(.physical_adapter_ready, .blocked, .native_presenter, 1, stage.label());
        },
        .device_failed => {
            self.recordNativePresenterPrerequisites(.satisfied, "native loader, instance, surface and adapter reached");
            self.recordGraphicsHealth(.logical_device_ready, .blocked, .native_presenter, 1, stage.label());
        },
        .frame_resources_failed => {
            self.recordNativePresenterPrerequisites(.satisfied, "native device and graphics queue reached");
            self.recordGraphicsHealth(.frame_resources_ready, .blocked, .native_presenter, 1, stage.label());
        },
        .swapchain_failed => {
            self.recordNativePresenterPrerequisites(.satisfied, "native frame prerequisites reached");
            self.recordGraphicsHealth(.swapchain_ready, .blocked, .native_presenter, 1, stage.label());
        },
        .surface_not_presentable => {
            self.recordNativePresenterPrerequisites(.satisfied, "native presenter exists; surface is temporarily unavailable");
            self.recordGraphicsHealth(.swapchain_ready, .degraded, .native_presenter, 1, stage.label());
        },
        .ready => {
            self.recordNativePresenterPrerequisites(.satisfied, "native presenter instance/surface/device/queue/swapchain are live");
        },
        .device_lost => {
            self.recordGraphicsHealth(.vulkan_loader_resolved, .satisfied, .native_presenter, 1, "Vulkan loader resolved before device loss");
            self.recordGraphicsHealth(.vulkan_instance_ready, .satisfied, .native_presenter, 1, "native instance existed before device loss");
            self.recordGraphicsHealth(.vulkan_surface_ready, .satisfied, .native_presenter, 1, "native surface existed before device loss");
            self.recordGraphicsHealth(.physical_adapter_ready, .satisfied, .native_presenter, 1, "physical adapter existed before device loss");
            self.recordGraphicsHealth(.logical_device_ready, .blocked, .native_presenter, 1, stage.label());
            self.recordGraphicsHealth(.graphics_queue_ready, .blocked, .native_presenter, 1, stage.label());
            self.recordGraphicsHealth(.swapchain_ready, .blocked, .native_presenter, 1, stage.label());
            self.recordGraphicsHealth(.frame_resources_ready, .blocked, .native_presenter, 1, stage.label());
        },
    }
}

pub fn refreshGraphicsHealthContract(self: anytype) void {
    const at = self.executed_steps;
    self.syncPresentationProvenance();

    if (self.event_stream.run_id != 0 or at != 0)
        self.recordGraphicsHealth(.application_started, .satisfied, .process, 1, "event stream has a run identity");
    if (at != 0)
        self.recordGraphicsHealth(.guest_image_mapped, .satisfied, .process, at, "translated guest instructions executed");
    if (self.pthreads.created_threads != 0)
        self.recordGraphicsHealth(.guest_scheduler_running, .satisfied, .scheduler, self.pthreads.created_threads, "guest threads have been created and rotated");

    const exports = self.gpu_kernel_surface.finding();
    if (exports.imported_count != 0) {
        self.recordGraphicsHealth(
            .kernel_graphics_exports_resolved,
            if (exports.blocking == null) .satisfied else .blocked,
            .kernel_surface,
            exports.usable_count,
            if (exports.blocking) |which| which.guidance() else "imported graphics exports are bound and usable",
        );
    }
    const variables = self.gpu_kernel_variables.finding();
    if (variables.imported_count != 0) {
        self.recordGraphicsHealth(
            .kernel_graphics_variables_populated,
            if (variables.blocking == null) .satisfied else .blocked,
            .kernel_surface,
            variables.usable_count,
            if (variables.blocking) |which| which.meaning() else "imported graphics variables resolve through slot and storage",
        );
    }

    const native_window_state = &self.native_window;
    if (native_window_state.application_ensure_attempts != 0)
        self.recordGraphicsHealth(
            .native_application_ready,
            if (native_window_state.window_ready_logged or native_window_state.layer_attachments != 0) .satisfied else .degraded,
            .native_window,
            native_window_state.application_ensure_attempts,
            if (native_window_state.window_ready_logged) "NSApplication and its window status were observed" else "application ensure was attempted; native status is not yet complete",
        );
    if (native_window_state.window_ready_logged or native_window_state.surface_bindings != 0) {
        self.recordGraphicsHealth(.native_window_ready, .satisfied, .native_window, native_window_state.window_ensure_attempts, "NSWindow/NSView status was observed");
    } else if (native_window_state.window_ensure_attempts != 0) {
        self.recordGraphicsHealth(.native_window_ready, if (native_window_state.window_ensure_failures != 0) .blocked else .degraded, .native_window, native_window_state.window_ensure_attempts, "window ensure has not produced a ready status");
    }
    if (native_window_state.layer_attachments != 0) {
        self.recordGraphicsHealth(.native_layer_attached, .satisfied, .native_window, native_window_state.layer_attachments, "CAMetalLayer attachment succeeded");
    } else if (native_window_state.layer_requests != 0) {
        self.recordGraphicsHealth(.native_layer_attached, if (native_window_state.layer_attachment_failures != 0) .blocked else .degraded, .native_window, native_window_state.layer_requests, "CAMetalLayer was requested but attachment is not proven");
    }

    if (self.dynamic_forwarder.native_vulkan_loader_attempts != 0)
        self.recordGraphicsHealth(
            .vulkan_loader_resolved,
            if (self.dynamic_forwarder.native_vulkan_loader_successes != 0) .satisfied else .blocked,
            .vulkan_forwarder,
            self.dynamic_forwarder.native_vulkan_loader_attempts,
            if (self.dynamic_forwarder.native_vulkan_loader_successes != 0) "native Vulkan loader resolved after candidate search" else "native Vulkan loader resolution failed",
        );
    self.refreshNativePresenterHealth();

    const observed_commands = self.dynamic_forwarder.guestVulkanObservedCommands();
    const real_commands = self.dynamic_forwarder.guestVulkanCommandsForwarded();
    const real_submits = self.dynamic_forwarder.guestVulkanQueueSubmits();
    const real_presents = self.dynamic_forwarder.guestVulkanPresents();
    if (self.dynamic_forwarder.native_presenter.stage == .ready) {
        self.observeGpuEarlyBoundary(.native_presenter_ready, .presenter, 1);
    }
    if (observed_commands != 0 or real_submits != 0 or real_presents != 0) {
        self.observeGpuEarlyBoundary(
            .guest_vulkan_activity,
            .presenter,
            observed_commands +| real_submits +| real_presents,
        );
    }
    if (observed_commands != 0 or real_submits != 0 or real_presents != 0)
        self.recordGraphicsHealth(.guest_vulkan_activity_observed, .satisfied, .vulkan_forwarder, observed_commands +| real_submits +| real_presents, "guest Vulkan calls reached the forwarding surface");
    if (real_commands != 0) {
        self.recordGraphicsHealth(.guest_vulkan_commands_forwarded, .satisfied, .vulkan_forwarder, real_commands, "guest Vulkan command calls reached native forwarding");
    } else if (observed_commands != 0) {
        self.recordGraphicsHealth(.guest_vulkan_commands_forwarded, .degraded, .vulkan_forwarder, observed_commands, "guest Vulkan commands were observed without native command forwarding");
    }
    if (real_submits != 0) {
        self.recordGraphicsHealth(.guest_vulkan_submission_forwarded, .satisfied, .vulkan_forwarder, real_submits, "guest queue submissions reached the native driver");
    } else if (observed_commands != 0) {
        self.recordGraphicsHealth(.guest_vulkan_submission_forwarded, .degraded, .vulkan_forwarder, observed_commands, "guest command activity has no native queue submission");
    }

    if (self.gpu_bootstrap.seen(.initialize_engines))
        self.recordGraphicsHealth(.xenos_engines_initialized, .satisfied, .xenos_runtime, 1, "VdInitializeEngines was observed");
    if (self.gpu_interrupt_callback != 0) {
        self.recordGraphicsHealth(.xenos_interrupt_callback_registered, .satisfied, .kernel_surface, self.gpu_interrupt_callback_registrations, "VdSetGraphicsInterruptCallback installed a guest callback");
    } else if (self.interrupt_callback_transaction.registrations != 0) {
        self.recordGraphicsHealth(
            .xenos_interrupt_callback_registered,
            .satisfied,
            .causal_trace,
            self.interrupt_callback_transaction.registrations,
            "Xenia registered its PowerPC graphics callback; this is healthy in its own executor domain and is not a translated-x86 callback",
        );
    }
    if (self.gpu_bootstrap.seen(.ring_buffer) or self.gpu_ring_watch_base != 0)
        self.recordGraphicsHealth(.xenos_ring_initialized, .satisfied, .ring_publication, 1, "ring base/size state is available");
    if (self.gpu_ring_publication.published())
        self.recordGraphicsHealth(.ring_publication_observed, .satisfied, .ring_publication, self.gpu_ring_publication.advances, "guest publication is latched by a pointer change or non-empty span");
    if (self.gpu_ring_publication.geometry != null)
        self.recordGraphicsHealth(.ring_geometry_observed, .satisfied, .ring_publication, 1, "ring read/write geometry was captured");
    if (self.gpu_ring_publication.published()) {
        self.observeGpuEarlyBoundary(.ring_publication, .ring, self.gpu_ring_publication.advances);
        self.observeGpuEarlyBoundary(.guest_producer_progressed, .ring, self.gpu_ring_publication.advances);
    }

    const vd = &self.gpu_vd_swap_contract;
    const runtime = &self.gpu_xenos_runtime;
    const target = runtime.renderTargetEvidence();
    if (self.guest_wait_liveness.total_waits != 0) {
        self.observeGpuEarlyBoundary(.guest_wait_progressed, .scheduler, self.guest_wait_liveness.total_waits);
    }
    const pm4_observed = runtime.batches != 0 or vd.observed(.pm4_stream_observed);
    if (pm4_observed)
        self.recordGraphicsHealth(.pm4_stream_observed, .satisfied, if (runtime.batches != 0) .xenos_runtime else .vd_swap_contract, runtime.batches, "PM4 dwords/packets were observed");
    if (vd.observed(.pm4_stream_validated))
        self.recordGraphicsHealth(.pm4_stream_validated, .satisfied, .vd_swap_contract, 1, "PM4 framing passed the bounded validator");
    if (pm4_observed) {
        const indirect_bad = runtime.indirect_unreadable +| runtime.indirect_truncated +| runtime.indirect_invalid +| runtime.indirect_depth_limited +| runtime.indirect_budget_limited;
        if (runtime.indirect_buffers == 0 or indirect_bad == 0) {
            self.recordGraphicsHealth(.pm4_indirects_resolved, .satisfied, .xenos_runtime, runtime.indirect_buffers, if (runtime.indirect_buffers == 0) "no indirect buffers were required" else "all observed indirect buffers were readable and bounded");
        } else {
            self.recordGraphicsHealth(.pm4_indirects_resolved, .blocked, .xenos_runtime, indirect_bad, "one or more indirect buffers were unreadable, truncated or over budget");
        }
    }
    if (vd.observed(.pm4_state_programmed) or runtime.executor.register_file.write_count != 0)
        self.recordGraphicsHealth(.pm4_state_programmed, .satisfied, .xenos_runtime, runtime.executor.register_file.write_count, "Xenos register state was programmed");
    if (runtime.draw_count != 0 or vd.observed(.draw_submitted))
        self.recordGraphicsHealth(.draw_submitted, .satisfied, .xenos_runtime, runtime.draw_count, "draw packets were submitted to the stateful runtime");
    if (runtime.draw_count != 0 or vd.observed(.draw_consumed) or self.gpu_ring_publication.consumerSawBatch())
        self.recordGraphicsHealth(.draw_consumed, .satisfied, .xenos_runtime, runtime.draw_count, "the command processor consumed draw work");
    if (target.state_observed)
        self.recordGraphicsHealth(.render_target_state_observed, if (target.plausible) .satisfied else .degraded, .xenos_runtime, 1, "RB_COLOR_INFO/RB_DEPTH_INFO/RB_SURFACE_INFO state was observed");
    if (runtime.color_resolve_observations != 0)
        self.recordGraphicsHealth(.render_target_memory_observed, .satisfied, .xenos_runtime, runtime.color_resolve_observations, "EDRAM color resolve produced readable output");
    if (runtime.draw_completion_signals != 0)
        self.recordGraphicsHealth(.draw_completion_signaled, .satisfied, .xenos_runtime, runtime.draw_completion_signals, "draw completion events were queued");
    if (runtime.draw_completion_signals != 0) {
        const dispatch_state: graphics_health_contract.State = if (self.gpu_draw_completion_dispatches != 0)
            .satisfied
        else if (self.interrupt_callback_transaction.callback_returns != 0)
            .degraded
        else
            .blocked;
        const dispatch_count = if (self.gpu_draw_completion_dispatches != 0)
            self.gpu_draw_completion_dispatches
        else
            self.interrupt_callback_transaction.callback_returns;
        self.recordGraphicsHealth(
            .draw_completion_dispatched,
            dispatch_state,
            .scheduler,
            dispatch_count,
            if (self.gpu_draw_completion_dispatches != 0)
                "model draw completion reached the translated-x86 callback scheduler"
            else if (self.interrupt_callback_transaction.callback_returns != 0)
                "Xenia's PowerPC callback returned, but model completion signals belong to the translated-x86 route and cannot be summed with it"
            else
                "draw completion is queued but no callback dispatch is proven in either executor domain",
        );
    }

    const waits = self.guest_wait_liveness.aggregateVerdict();
    if (self.guest_wait_liveness.provesSignalConsumption()) {
        self.recordGraphicsHealth(.guest_wait_progressed, .satisfied, .guest_log, self.guest_wait_liveness.total_waits, waits.label());
    } else if (waits.isDefect()) {
        self.recordGraphicsHealth(.guest_wait_progressed, .degraded, .guest_log, self.guest_wait_liveness.total_waits, waits.label());
    }
    if (self.gpu_ring_publication.advances != 0) {
        const quiet = self.gpu_ring_publication.stalledSteps(at) orelse 0;
        self.recordGraphicsHealth(
            .guest_producer_progressed,
            if (quiet < application_controller.ring_quiet_threshold_steps) .satisfied else .blocked,
            .ring_publication,
            self.gpu_ring_publication.advances,
            if (quiet < application_controller.ring_quiet_threshold_steps) "ring producer advanced within the controller window" else "ring producer is quiet beyond the controller window",
        );
    }
    if (self.execution_tracepoints.roleEntered(.swap))
        self.recordGraphicsHealth(.guest_vdswap_entered, .satisfied, .causal_trace, 1, "execution tracepoint reached the guest VdSwap role");
    if (self.guest_vdswap_packet_encoded)
        self.recordGraphicsHealth(.guest_swap_encoded, .satisfied, .vd_swap_contract, 1, "guest-origin XE_SWAP encoding was observed");
    if (vd.authentic_consumptions != 0)
        self.recordGraphicsHealth(.authentic_swap_consumed, .satisfied, .vd_swap_contract, vd.authentic_consumptions, "authentic XE_SWAP reached the command processor");
    if (vd.observed(.issue_swap_entered))
        self.recordGraphicsHealth(.issue_swap_entered, .satisfied, .vd_swap_contract, 1, "Xenia presenter IssueSwap boundary was observed");

    const guest_output_frames = self.guestOutputFramesPresented();
    if (self.guest_vdswap_packet_encoded) {
        self.observeGpuEarlyBoundary(.guest_swap_encoded, .tracepoint, @intFromBool(self.guest_vdswap_packet_encoded));
    }
    if (vd.authentic_consumptions != 0) {
        self.observeGpuEarlyBoundary(.authentic_xe_swap_consumed, .pm4, vd.authentic_consumptions);
    }
    if (vd.observed(.issue_swap_entered)) {
        self.observeGpuEarlyBoundary(.issue_swap_entered, .tracepoint, 1);
    }
    if (guest_output_frames != 0) {
        self.observeGpuEarlyBoundary(.guest_output_refreshed, .presenter, guest_output_frames);
        self.recordGraphicsHealth(.guest_output_refreshed, .satisfied, .native_presenter, guest_output_frames, "guest-produced pixels reached the presenter source");
    } else if (self.dynamic_forwarder.guestFrontBufferAvailable()) {
        self.recordGraphicsHealth(.guest_output_refreshed, .degraded, .native_presenter, 1, "a guest output source was discovered, but no guest-produced frame has been refreshed");
    }
    const rendered_frames = guest_output_frames;
    if (rendered_frames != 0) {
        self.observeGpuEarlyBoundary(.native_present_completed, .presenter, rendered_frames);
        self.recordGraphicsHealth(.native_present_completed, .satisfied, .native_presenter, rendered_frames, "Xenia/guest pixels completed a native presentation; diagnostic clears are counted separately");
    }
}

pub fn refreshApplicationController(self: anytype) application_controller.Decision {
    const guest_output_frames = self.guestOutputFramesPresented();
    // The pthread predictor observes Rosette's host/cooperative scheduler,
    // including idle worker condvars. It must remain visible in host
    // diagnostics, but it is not evidence that the guest is deadlocked.
    // Feed the controller only the guest wait graph; otherwise an
    // unnotified host worker can make the application controller claim a
    // guest wait deadlock and select the wrong owner for the next action.
    const guest_wait_verdict = self.wait_graph.summary().verdict();
    const guest_wait_deadlocked = switch (guest_wait_verdict) {
        .orphan_wait, .handshake_without_progress, .wait_cycle => true,
        .idle, .healthy, .orphan_signal, .timeout_without_signal => false,
    };
    return self.application_controller.observe(.{
        .step = self.executed_steps,
        .guest_progress_step = if (self.xenia_gpu_causal_trace.last_progress_step != 0) self.xenia_gpu_causal_trace.last_progress_step else null,
        .ring_progress_step = if (self.gpu_ring_publication.last_advance_step != 0) self.gpu_ring_publication.last_advance_step else null,
        .pm4_progress_step = if (self.gpu_ring_publication.last_consumed_step != 0) self.gpu_ring_publication.last_consumed_step else null,
        .guest_vdswap_entered = self.execution_tracepoints.roleEntered(.swap),
        .guest_swap_encoded = self.guest_vdswap_packet_encoded,
        .authentic_swap_consumed = self.gpu_vd_swap_contract.authentic_consumptions != 0,
        .guest_output_available = guest_output_frames != 0 or self.dynamic_forwarder.guestFrontBufferAvailable(),
        .native_present_completed = guest_output_frames != 0,
        .ring_published = self.gpu_ring_publication.published(),
        .pm4_stream_observed = self.gpu_xenos_runtime.batches != 0 or self.gpu_vd_swap_contract.observed(.pm4_stream_observed),
        .pm4_stream_consumed = self.gpu_xenos_runtime.draw_count != 0 or self.gpu_ring_publication.consumerSawBatch(),
        .render_target_state_observed = self.gpu_xenos_runtime.renderTargetEvidence().state_observed,
        .render_target_memory_observed = self.gpu_xenos_runtime.color_resolve_observations != 0,
        .draw_completion_signaled = self.gpu_xenos_runtime.draw_completion_signals,
        .draw_completion_dispatched = self.gpu_draw_completion_dispatches,
        .pending_gpu_interrupts = self.gpu_xenos_runtime.interrupts.pending_count,
        .interrupt_callback_registered = self.gpu_interrupt_callback != 0,
        .powerpc_callback_registered = self.interrupt_callback_transaction.registrations != 0,
        .powerpc_callback_returned = self.interrupt_callback_transaction.callback_returns != 0,
        .presenter_ready = self.dynamic_forwarder.nativePresenterStage().isReady(),
        .presenter_device_lost = self.dynamic_forwarder.nativePresenterStage() == .device_lost,
        .guest_wait_deadlocked = guest_wait_deadlocked,
        .guest_waiting = self.pthreads.blocked_threads != 0,
        .guest_runnable = self.pthreads.activeCount() != 0,
    });
}

pub fn applyApplicationController(self: anytype, decision: application_controller.Decision) void {
    // Validate the exact decision against the sample that produced it
    // before allowing any host mutation.  The integrity checkpoint will
    // terminate the run and retain the violating pair; this guard keeps a
    // malformed authorized decision from reaching the presenter or GPU
    // callback even for the small interval before that checkpoint runs.
    if (decision.contractViolation(self.application_controller.last_sample) != null) return;
    switch (decision.action) {
        .drain_gpu_interrupts => {
            // The decision ledger is authoritative for whether this host
            // mutation was authorized. A future policy regression must not
            // be able to drain a guest callback merely by selecting the
            // action with the authorization bit cleared.
            if (!decision.host_action_authorized) return;
            if (self.gpu_interrupt_callback == 0 or self.gpu_xenos_runtime.interrupts.pending_count == 0) return;
            const delivered = self.gpu_xenos_runtime.drainInterrupts(deliverGpuInterrupt, self, 32);
            if (delivered != 0) self.application_controller_host_drains +|= delivered;
        },
        .refresh_discovered_output => {
            if (!decision.host_action_authorized) return;
            if (self.dynamic_forwarder.attemptScheduledRefresh(self)) self.application_controller_host_refreshes +|= 1;
        },
        else => {},
    }
}

pub fn refreshCocoaGraphicsControl(self: anytype) gpu.CocoaGraphicsOutcome {
    if (!self.cocoa_graphics.configured) {
        const policy = cocoaGraphicsPolicyFromEnvironment();
        self.cocoa_graphics.configure(policy);
        machoCapturePrint(
            "macho-processor: COCOA GRAPHICS CONTROL: schema={d} owner={s} subowner={s} policy={s} (verified-guest-fallback is default; ROSETTE_COCOA_GRAPHICS_CONTROL=observe disables active fallback); raw-machine-code-to-Cocoa=REFUSED, semantic-boundaries-only=YES. The control plane may classify and route an already verified frame, but cannot fabricate VdSwap, XE_SWAP, render-target state or a callback transition\n",
            .{ gpu.cocoa_runtime.schema_version, ownership_contract.root_owner, "rosette:graphics-control", policy.label() },
        );
    }

    if (self.cocoa_graphics.control.policy == .verified_guest_fallback and
        !self.dynamic_forwarder.nativePresenterStage().isReady())
    {
        self.dynamic_forwarder.refreshCocoaFallbackSource(self);
    }

    const native = self.native_window.snapshot();
    const ownership = self.dynamic_forwarder.graphicsOwnershipSnapshot();
    const target = self.gpu_xenos_runtime.renderTargetEvidence();
    const run_identity = if (self.event_stream.run_id == 0) @as(u64, 1) else self.event_stream.run_id;
    const ring_generation = @max(self.gpu_ring_publication.advances, 1);
    const command_generation = @max(self.gpu_xenos_last_payload_epoch, 1);
    const vdswap_entries = if (self.execution_tracepoints.byRole(.swap)) |entry| entry.hits else 0;
    const issue_swap_entries: u64 = @intFromBool(self.gpu_vd_swap_contract.observed(.issue_swap_entered));

    var target_identity: u64 = 0;
    if (target.state_observed) {
        target_identity = (@as(u64, target.raw_color_info) << 32) ^
            (@as(u64, target.raw_depth_info) << 1) ^
            @as(u64, target.raw_surface_info);
        if (target_identity == 0) target_identity = 1;
    }
    const command_stream_identity = if (self.gpu_xenos_runtime.batches != 0 or
        self.gpu_ring_publication.consumerSawBatch())
        (if (self.gpu_ring_watch_base != 0) self.gpu_ring_watch_base else @as(u64, 1))
    else
        0;
    const front_buffer_identity: u64 = if (self.gpu_frontbuffer) |front|
        front.frontbuffer_physical_address
    else if (self.gpu_vd_swap_contract.active_frontbuffer) |front|
        front.frontbuffer_physical_address
    else
        0;

    var xenia_generation = ownership.xenia_instance ^
        std.math.rotl(u64, ownership.xenia_surface, 7) ^
        std.math.rotl(u64, ownership.xenia_device, 17) ^
        std.math.rotl(u64, ownership.xenia_swapchain, 29);
    if (xenia_generation == 0) xenia_generation = 1;

    var latest_frame: ?gpu.cocoa_runtime.FrameSnapshot = null;
    if (ownership.latest_frame) |frame| {
        latest_frame = .{
            .source_address = frame.source_address,
            .source_length = frame.source_length,
            .width = frame.width,
            .height = frame.height,
            .row_pitch = frame.row_pitch_bytes,
            .format = gpu.cocoa_runtime.PixelFormat.fromVulkan(frame.format),
            .orientation = switch (frame.orientation) {
                .top_down => .top_down,
                .bottom_up => .bottom_up,
            },
            .fit = switch (frame.fit) {
                .stretch => .stretch,
                .letterbox => .letterbox,
                .center => .center,
            },
            .origin = switch (frame.producer) {
                .diagnostic => .diagnostic,
                .xenia_host => .xenia_host,
                .guest => .guest_title,
            },
            .generation = ownership.rosette_generation,
            .serial = frame.serial,
            .content_digest = frame.content_digest,
            .guest_swap_observed = frame.guest_swap_observed,
            .consumed = ownership.latest_frame_consumed,
        };
    }

    const sdl_graphics = self.sdl.graphicsSnapshot();
    const sdl_native_tokens_match = sdl_graphics.native_window_token == native_window_runtime.WINDOW_TOKEN and
        sdl_graphics.native_view_token == native_window_runtime.VIEW_TOKEN;
    const sdl_window_bound = sdl_graphics.window_bound and sdl_native_tokens_match and
        native.window != 0 and native.view != 0;
    const snapshot = gpu.CocoaGraphicsSnapshot{
        .run = run_identity,
        .step = self.executed_steps,
        .native = .{
            .application = native.application,
            .window = native.window,
            .content_view = native.view,
            .metal_layer = native.metal_layer,
            .metal_device = native.metal_device,
            .application_ready = native.application_ready != 0,
            .window_ready = native.window_ready != 0,
            .layer_attached = native.layer_attached != 0,
            .diagnostic_frames = self.native_window.diagnostic_frames_presented,
            .guest_frames = self.native_window.guest_frames_presented,
            // Whichever presenter drew the frame, it landed on this
            // drawable. The presenter's negotiated format wins when it came
            // up; otherwise the layer's own fixed format is the fact.
            .drawable_width = if (ownership.rosette_extent_width != 0)
                ownership.rosette_extent_width
            else
                native.width,
            .drawable_height = if (ownership.rosette_extent_height != 0)
                ownership.rosette_extent_height
            else
                native.height,
            .drawable_format = if (ownership.rosette_surface_format != 0)
                ownership.rosette_surface_format
            else
                native_window_runtime.DRAWABLE_VULKAN_FORMAT,
        },
        .sdl = .{
            .event_loop = if (self.sdl.calls != 0 or self.sdl.initialized_mask != 0 or self.sdl.event_pumps != 0)
                @intFromPtr(&self.sdl)
            else
                0,
            .window_binding = sdl_graphics.window_token,
            .binding_generation = sdl_graphics.generation,
            .cocoa_window = if (sdl_window_bound) native.window else 0,
            .cocoa_content_view = if (sdl_window_bound) native.view else 0,
            .initialized = sdl_graphics.initialized,
            .window_bound = sdl_window_bound,
        },
        .rosette_vulkan = .{
            .metal_layer = ownership.rosette_metal_layer,
            .instance = ownership.rosette_instance,
            .surface = ownership.rosette_surface,
            .device = ownership.rosette_device,
            .queue = ownership.rosette_queue,
            .swapchain = ownership.rosette_swapchain,
            .generation = ownership.rosette_generation,
            .ready = ownership.rosette_presenter_ready,
            .diagnostic_frames = ownership.rosette_diagnostic_frames,
            .host_frames = ownership.rosette_host_frames,
            .guest_output_frames = ownership.rosette_guest_output_frames,
        },
        .xenia_vulkan = .{
            .instance = ownership.xenia_instance,
            .surface = ownership.xenia_surface,
            .device = ownership.xenia_device,
            .queue = ownership.xenia_queue,
            .swapchain = ownership.xenia_swapchain,
            .generation = xenia_generation,
            .ready = self.dynamic_forwarder.guestVulkanDeviceReady(),
            .submissions = ownership.xenia_submissions,
            .presents = ownership.xenia_presents,
            .completed_presents = ownership.xenia_present_completions,
        },
        .xenos = .{
            .ring = self.gpu_ring_watch_base,
            .ring_generation = ring_generation,
            .ring_publications = self.gpu_ring_publication.advances,
            .command_stream = command_stream_identity,
            .command_generation = command_generation,
            .batches = self.gpu_xenos_runtime.batches,
            .packets = self.gpu_xenos_runtime.executor.packet_count,
            .draws = self.gpu_xenos_runtime.draw_count,
            .completion_signals = self.gpu_xenos_runtime.draw_completion_signals,
            .render_target = target_identity,
            .render_target_state = target.state_observed,
            .render_target_memory = self.gpu_xenos_runtime.color_resolve_observations != 0,
            .front_buffer = front_buffer_identity,
            .guest_vdswap_entries = vdswap_entries,
            .guest_xe_swap_encoded = self.guest_vdswap_packet_encoded,
            .authentic_xe_swap_consumed = self.gpu_vd_swap_contract.authentic_consumptions,
            .issue_swap_entries = issue_swap_entries,
        },
        .callbacks = .{
            .powerpc_address = self.interrupt_callback_transaction.callback_address,
            .powerpc_registrations = self.interrupt_callback_transaction.registrations,
            .powerpc_returns = self.interrupt_callback_transaction.callback_returns,
            .translated_x86_address = self.gpu_interrupt_callback,
            .translated_x86_registrations = self.gpu_interrupt_callback_registrations,
            .translated_x86_dispatches = self.gpu_draw_completion_dispatches,
        },
        .latest_frame = latest_frame,
        .diagnostic_requested = self.native_window.diagnostic_frame_attempts != 0,
        .metal_guest_copy_ready = native.window_ready != 0 and
            native.layer_attached != 0 and native.metal_layer != 0 and
            native.metal_device != 0,
    };
    const outcome = self.cocoa_graphics.reconcile(snapshot);
    self.cocoa_graphics_last_outcome = outcome;
    return outcome;
}

pub fn observeSdlGraphicsImport(self: anytype, symbol: []const u8) void {
    const name = if (symbol.len != 0 and symbol[0] == '_') symbol[1..] else symbol;
    const function: gpu.graphics_intent.Import = if (std.mem.eql(u8, name, "SDL_CreateWindow"))
        .sdl_create_window
    else if (std.mem.eql(u8, name, "SDL_PumpEvents") or std.mem.eql(u8, name, "SDL_PollEvent"))
        .sdl_pump_events
    else
        return;
    const sequence = switch (function) {
        .sdl_create_window => self.sdl.window_create_attempts,
        .sdl_pump_events => self.sdl.event_pumps,
        else => unreachable,
    };
    if (sequence == 0) return;
    var source_identity = std.hash.Wyhash.hash(0x5344_4C32, name);
    if (source_identity == 0) source_identity = 1;
    const run_identity = if (self.event_stream.run_id == 0) @as(u64, 1) else self.event_stream.run_id;
    _ = self.cocoa_graphics.observeIntent(.{
        .run = run_identity,
        .boundary = .{ .intercepted_import = .{
            .function = function,
            .address = self.regs.rip,
            .space = .translated_x86,
        } },
        .producer = .sdl,
        .evidence = .completed_call,
        .source_identity = source_identity,
        .generation = @max(@as(u64, self.sdl.window_generation), 1),
        .sequence = sequence,
    });
}

pub fn windowAdmissionPolicyFromEnvironment() gpu.WindowAdmissionPolicy {
    const raw = std.c.getenv("ROSETTE_WINDOW_ADMISSION") orelse return .fault;
    return gpu.window_admission.policyFromText(std.mem.span(raw), .fault);
}

pub fn ensureWindowAdmission(self: anytype) void {
    if (self.window_admission_configured) return;
    self.window_admission_configured = true;
    const policy = windowAdmissionPolicyFromEnvironment();
    self.window_admission.configure(policy);
    machoCapturePrint(
        "macho-processor: WINDOW ADMISSION: schema={d} policy={s} (ROSETTE_WINDOW_ADMISSION=fault|refuse|observe; fault is the default). Rosette stands the window up before the first guest instruction, so a forwarding it has no semantics for is unaccountable rather than early. Ordering refusals — a legitimate request whose preconditions have not been observed yet — are never fatal under any policy\n",
        .{ gpu.window_admission.schema_version, policy.label() },
    );
}

pub fn windowConditions(self: anytype, status: native_window_runtime.Status) gpu.window_admission.ConditionMask {
    const W = gpu.window_admission;
    var mask: W.ConditionMask = 0;
    if (status.application_ready != 0) mask |= W.conditionBit(.application_ready);
    if (status.window_ready != 0) mask |= W.conditionBit(.window_ready);
    if (status.view != 0) mask |= W.conditionBit(.view_ready);
    if (status.layer_attached != 0 and status.metal_layer != 0) mask |= W.conditionBit(.layer_attached);
    if (status.metal_device != 0) mask |= W.conditionBit(.device_ready);
    if (status.on_main_thread != 0) mask |= W.conditionBit(.main_thread);
    if (self.native_window.surface_bindings != 0) mask |= W.conditionBit(.surface_bound);
    // Either presenter satisfies this. The Cocoa/Metal copy route exists
    // precisely for the case where the Vulkan presenter did not come up, so
    // reading `presenter_ready` off the Vulkan presenter alone would make
    // the gate refuse the fallback in exactly the situation the fallback
    // was written for.
    if (self.dynamic_forwarder.nativePresenterStage().isReady() or
        (status.layer_attached != 0 and status.metal_layer != 0 and status.metal_device != 0))
        mask |= W.conditionBit(.presenter_ready);
    // Custody is available whenever the ledger can still take an offer.
    mask |= W.conditionBit(.custody_available);
    return mask;
}

pub fn admitWindowForwarding(
    self: anytype,
    actor: gpu.WindowActor,
    facility: gpu.WindowFacility,
    operation: gpu.WindowOperation,
    origin: []const u8,
) gpu.WindowAdmissionOutcome {
    return self.admitWindowForwardingWith(actor, facility, operation, 0, origin);
}

pub fn admitWindowForwardingWith(
    self: anytype,
    actor: gpu.WindowActor,
    facility: gpu.WindowFacility,
    operation: gpu.WindowOperation,
    extra: gpu.window_admission.ConditionMask,
    origin: []const u8,
) gpu.WindowAdmissionOutcome {
    self.ensureWindowAdmission();
    // One bridge read per decision. Two would be two different instants,
    // and a decision assembled from two instants is the same defect as one
    // assembled from a stale snapshot.
    const status = self.native_window.snapshot();
    return self.window_admission.admit(.{
        .actor = actor,
        .facility = facility,
        .operation = operation,
        .observed = self.windowConditions(status) | extra,
        .facility_present = self.windowFacilityPresent(status, facility),
    }, origin, self.executed_steps);
}

pub fn admitWindowPresentation(
    self: anytype,
    actor: gpu.WindowActor,
    facility: gpu.WindowFacility,
    facts: PresentationFacts,
    origin: []const u8,
) gpu.WindowAdmissionOutcome {
    return self.admitWindowForwardingWith(actor, facility, .present, facts.mask(), origin);
}

pub fn windowFacilityPresent(
    self: anytype,
    status: native_window_runtime.Status,
    facility: gpu.WindowFacility,
) bool {
    return switch (facility) {
        .application => status.application != 0,
        .window => status.window != 0,
        .content_view => status.view != 0,
        .layer => status.metal_layer != 0,
        .device => status.metal_device != 0,
        .title, .geometry, .visibility, .fullscreen, .event_pump => status.window != 0,
        .diagnostic_present => status.metal_layer != 0 or
            self.dynamic_forwarder.nativePresenterStage().isReady(),
        else => true,
    };
}

pub fn faultOnGraphicsExtentContract(
    self: anytype,
    requested_width: u32,
    requested_height: u32,
    observed_width: u32,
    observed_height: u32,
    reason: []const u8,
) void {
    if (self.graphics_extent_contract_faulted) return;
    self.graphics_extent_contract_faulted = true;
    self.graphics_preflight_window_allowed = false;
    self.faulted = true;
    self.terminated = true;
    self.exit_code = 125;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.runtime_invariant_failure);
    self.audit_pause.noteTermination(.diagnostic_termination, self.executed_steps);

    const status = self.native_window.snapshot();
    const presenter = &self.dynamic_forwarder.native_presenter.report;
    machoCapturePrint(
        "macho-processor: GRAPHICS EXTENT CONTRACT FAULT: reason={s} required={d}x{d} observed={d}x{d} step={d} rip=0x{x} thread=0x{x} native_stage={s} drawable_owner={s}\n",
        .{
            reason,
            requested_width,
            requested_height,
            observed_width,
            observed_height,
            self.executed_steps,
            self.regs.rip,
            self.active_guest_thread,
            @tagName(self.dynamic_forwarder.native_presenter.stage),
            @tagName(self.dynamic_forwarder.drawable_owner),
        },
    );
    machoCapturePrint(
        "macho-processor: GRAPHICS EXTENT CONTRACT FAULT: bridge_status={d}x{d} host(app/window/view/layer/device)=0x{x}/0x{x}/0x{x}/0x{x}/0x{x} presenter(requested/selected)={d}x{d}/{d}x{d} rejection={s} VkResult={d}; the layer and swapchain must agree before either can own presentation\n",
        .{
            status.width,
            status.height,
            status.application,
            status.window,
            status.view,
            status.metal_layer,
            status.metal_device,
            presenter.requested_extent_width,
            presenter.requested_extent_height,
            presenter.extent_width,
            presenter.extent_height,
            presenter.rejectionLabel(),
            presenter.last_result,
        },
    );
    machoCapturePrint(
        "macho-processor: GRAPHICS EXTENT CONTRACT FAULT: termination=NON_BYPASSABLE; refusing to continue into vkCreateSwapchainKHR, drawable ownership handoff, guest execution, or retry logic. This is the required 1280x720 phase, not an advisory diagnostic\n",
        .{},
    );
    macho_log.flushAsyncTransport();
    self.macho_log.flush();
    native_crash.recordPhase("graphics-extent-contract-fault");
    _ = std.c.raise(std.c.SIG.SEGV);
    // The native crash handler normally restores the default disposition
    // and re-raises. If it returns, keep the failed path terminal anyway.
    std.c.abort();
}

pub fn faultOnWindowAdmission(self: anytype, outcome: gpu.WindowAdmissionOutcome) void {
    const detail = outcome.detail;
    machoCapturePrint(
        "macho-processor: WINDOW ADMISSION FAULT: owner={s} subowner={s} actor={s} facility={s} operation={s} verdict={s} origin={s} step={d} rip=0x{x} thread=0x{x}\n",
        .{
            ownership_contract.root_owner,
            detail.actor.label(),
            detail.actor.label(),
            detail.facility.label(),
            detail.operation.label(),
            detail.verdict.label(),
            detail.originName(),
            detail.step,
            self.regs.rip,
            self.active_guest_thread,
        },
    );
    machoCapturePrint(
        "macho-processor: WINDOW ADMISSION FAULT: {s}\n",
        .{detail.verdict.explanation()},
    );
    self.logWindowAdmission(true);
    machoCapturePrint(
        "macho-processor: WINDOW ADMISSION FAULT: raising SIGSEGV so the crash report names this forwarding. Set ROSETTE_WINDOW_ADMISSION=refuse to continue past it, or observe to answer it as before\n",
        .{},
    );
    macho_log.flushAsyncTransport();
    // The async ring drain only hands bytes to `write(2)`.  Before an
    // intentional integrity fault, synchronize every diagnostic file as
    // well so the crash report cannot outrun the evidence that selected
    // the fault (including the filtered Ready Compiler stream).
    self.macho_log.flush();
    native_crash.recordPhase("window-admission-fault");
    _ = std.c.raise(std.c.SIG.SEGV);
}

pub fn refreshWindowSwapAdmission(self: anytype) void {
    const ledger = &self.gpu_vd_swap_contract;
    const at = self.executed_steps;
    self.ensureWindowAdmission();

    // The surface a swap would present from. A named one always wins; the
    // harness surface is a fallback that is tagged as such all the way
    // through, so a frame from it can never be counted as guest output.
    const supplied = self.gpu_draw_dispatch.suppliedSurface();
    const named: ?gpu.Pm4SwapDescription = if (self.gpu_frontbuffer) |front|
        front
    else if (ledger.active_frontbuffer) |front|
        front
    else
        null;
    const description: ?gpu.Pm4SwapDescription = if (named) |front|
        front
    else if (supplied) |surface|
        surface.description
    else
        null;
    const harness_supplied = named == null and supplied != null;

    var readable = false;
    var extent_valid = false;
    if (description) |swap| {
        extent_valid = swap.plausible();
        if (extent_valid) {
            // The address a swap carries is a console *physical* address,
            // and the emulator projects console physical memory into its
            // own space at a base discovered at startup. Reading it without
            // that translation would test a completely unrelated page and
            // report whatever that page happened to be.
            if (self.xenia_memory_views.physicalHostAddress(swap.frontbuffer_physical_address)) |projected| {
                const bytes = @as(u64, swap.width) * @as(u64, swap.height) * 4;
                readable = self.guestMemoryConst(projected, bytes) != null;
            }
        }
    }

    // The destination format is the drawable's, and the source conversion
    // is the one that gets to say it cannot handle a surface. Both are read
    // rather than assumed.
    const ownership = self.dynamic_forwarder.graphicsOwnershipSnapshot();
    const drawable_format = if (ownership.rosette_surface_format != 0)
        ownership.rosette_surface_format
    else
        native_window_runtime.DRAWABLE_VULKAN_FORMAT;
    const format_supported = gpu.cocoa_runtime.PixelFormat.fromVulkan(drawable_format) != .unknown and
        !self.dynamic_forwarder.guestFrontBufferFormatRefused();

    const epoch_matched = self.gpu_xenos_last_payload_epoch == self.gpu_ring_publication.advances;
    const lease = self.cocoa_graphics.control.presenter;
    const lease_compatible = !lease.active or lease.conflicts == 0;
    const custody_available = !self.cocoa_graphics_last_outcome.ownership_conflict and
        self.cocoa_graphics.frames.conflicts == 0;

    const boundaries = [_]struct { boundary: gpu.WindowSwapBoundary, reached: bool, source_mask: u32 }{
        .{
            .boundary = .vd_swap_entry,
            .reached = self.execution_tracepoints.roleEntered(.swap) or ledger.observed(.guest_vdswap_entered),
            .source_mask = ledger.observation(.guest_vdswap_entered).source_mask,
        },
        .{
            .boundary = .vd_swap_arguments,
            .reached = ledger.observed(.vdswap_arguments_captured),
            .source_mask = ledger.observation(.vdswap_arguments_captured).source_mask,
        },
        .{
            .boundary = .xe_swap_encoded,
            .reached = self.guest_vdswap_packet_encoded or ledger.observed(.guest_xe_swap_encoded),
            .source_mask = ledger.observation(.guest_xe_swap_encoded).source_mask,
        },
        .{
            .boundary = .xe_swap_consumed,
            .reached = ledger.authentic_consumptions != 0,
            .source_mask = ledger.observation(.authentic_xe_swap_consumed).source_mask,
        },
        .{
            .boundary = .issue_swap,
            .reached = self.execution_tracepoints.roleEntered(.command_swap) or ledger.observed(.issue_swap_entered),
            .source_mask = ledger.observation(.issue_swap_entered).source_mask,
        },
    };

    var admitted_harness = false;
    var reached: u64 = 0;
    for (boundaries) |candidate| {
        if (!candidate.reached) continue;
        reached += 1;
        const facility = candidate.boundary.facility();
        // The window's own admission is a precondition of the swap gate, so
        // it is asked first and its answer is carried in as evidence rather
        // than assumed.
        const facility_outcome = self.admitWindowPresentation(
            candidate.boundary.owner(),
            facility,
            .{
                .frame_verified = readable and extent_valid and format_supported,
                .frontbuffer_named = description != null,
                .swap_boundary_observed = true,
            },
            candidate.boundary.label(),
        );
        if (facility_outcome.disposition == .fault) self.faultOnWindowAdmission(facility_outcome);
        const verdict = self.window_admission.admitSwap(candidate.boundary, .{
            .provenance = swapProvenanceFor(candidate.source_mask),
            .facility_admitted = facility_outcome.decision.verdict.admittedOk(),
            .frontbuffer_named = named != null,
            .frontbuffer_harness_supplied = harness_supplied,
            .frontbuffer_readable = readable,
            .extent_valid = extent_valid,
            .format_supported = format_supported,
            .epoch_matched = epoch_matched,
            .custody_available = custody_available,
            .lease_compatible = lease_compatible,
        }, at);
        if (verdict == .admitted_harness_surface) admitted_harness = true;
    }
    // Counted from the boundary evidence rather than from the gate's own
    // ledger, so the integrity invariant compares two independently sourced
    // numbers. A boundary the emulator reached that this loop never offered
    // means the two sides ran past each other.
    self.swap_boundaries_reached = @max(self.swap_boundaries_reached, reached);

    // A surface Rosette supplied reaches the window only after a real swap
    // boundary passed every other condition of the gate. Without that it
    // stays unread: the whole point of supplying it was to let the
    // substitution ladder take its lowest rung without inventing a swap,
    // and putting its bytes on screen with no boundary behind them would be
    // inventing one after all. It is published as `diagnostic`, so even
    // here it is never counted as guest output.
    if (admitted_harness and harness_supplied) {
        if (description) |swap| {
            if (!self.window_harness_surface_offered) {
                self.window_harness_surface_offered = true;
                machoCapturePrint(
                    "macho-processor: WINDOW SWAP ADMISSION: routing the harness front buffer at 0x{x:0>8} {d}x{d} to the window: a real swap boundary was admitted and every other condition held. The frame is published as diagnostic and is never guest output; a surface a source names displaces this one immediately\n",
                    .{ swap.frontbuffer_physical_address, swap.width, swap.height },
                );
            }
            self.offerGuestFrontBuffer(swap, self.gpu_xenos_runtime.frontBufferFetch(), true);
        }
    }
}

pub fn swapProvenanceFor(source_mask: u32) gpu.window_admission.SwapProvenance {
    const V = gpu.vd_swap_contract;
    const intercepted = V.sourceBit(.guest_tracepoint) |
        V.sourceBit(.command_processor_tracepoint) |
        V.sourceBit(.issue_swap_tracepoint) |
        V.sourceBit(.output_refresh_tracepoint) |
        V.sourceBit(.native_present_tracepoint) |
        V.sourceBit(.vdswap_argument_capture);
    const read = V.sourceBit(.ring_memory_scan) |
        V.sourceBit(.nested_pm4_walk) |
        V.sourceBit(.stateful_pm4_executor) |
        V.sourceBit(.guest_publication) |
        V.sourceBit(.memory_mapping) |
        V.sourceBit(.xenos_runtime);
    if (source_mask & intercepted != 0) return .intercepted_execution;
    if (source_mask & read != 0) return .guest_memory_read;
    if (source_mask != 0) return .emulator_log_claim;
    return .none;
}

pub fn ensureRunIntegrity(self: anytype) void {
    if (self.run_integrity_configured) return;
    self.run_integrity_configured = true;
    const policy_raw = std.c.getenv("ROSETTE_RUN_INTEGRITY");
    const policy = run_integrity.policyFromText(
        if (policy_raw) |raw| std.mem.span(raw) else null,
        .fault,
    );
    const allow_raw = std.c.getenv("ROSETTE_RUN_INTEGRITY_ALLOW");
    const allow: []const u8 = if (allow_raw) |raw| std.mem.span(raw) else "";
    self.run_integrity.configure(policy, allow);
    // `observe` is the explicit non-invasive mode. Both `fault` and
    // `warn` select the evidence-first predicates; `fault` additionally
    // lets the fill hook raise SIGSEGV at the first miss the cache could
    // have avoided, while `warn` retains that same miss as a
    // non-terminating violation. Neither arms the compulsory first touch:
    // the cache is empty at step zero, so that would stop every run on its
    // first guest instruction.
    self.run_integrity_strict = policy != .observe;
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY: schema={d} policy={s} strict_fail_fast={} invariants={d} allow=[{s}] (ROSETTE_RUN_INTEGRITY=fault|warn|observe, ROSETTE_RUN_INTEGRITY_ALLOW=<labels>). Each invariant states what arms it, so an unarmed one is unobserved rather than passing; the first armed violation stops the run and names its owner\n",
        .{
            run_integrity.schema_version,
            policy.label(),
            self.run_integrity_strict,
            run_integrity.invariant_count,
            if (allow.len != 0) allow else "<none>",
        },
    );
}

pub fn guestOutputEvidence(self: anytype) host_contract_coverage.GuestOutputEvidence {
    return .{
        .raw_draws_consumed = self.gpu_xenos_runtime.draw_count,
        .renderable_draws_observed = self.gpu_xenos_runtime.renderable_draw_observations,
        .color_resolve_observations = self.gpu_xenos_runtime.color_resolve_observations,
        .guest_swap_boundaries = if (self.execution_tracepoints.roleEntered(.swap)) 1 else 0,
        .guest_vdswap_packets_encoded = if (self.guest_vdswap_packet_encoded) 1 else 0,
    };
}

pub fn runBudgetGuestWindowSummary(self: anytype) run_budget.Summary {
    return self.audit_budget_guest_window.summary(self.audit_budget.summary());
}

pub fn runBudgetGuestWindowObserved(self: anytype, totals: run_budget.Summary) bool {
    return self.audit_budget_guest_window.started and
        totals.host_ns >= run_integrity.budget_observation_host_seconds * std.time.ns_per_s;
}

pub fn runBudgetGuestWindowVerdict(
    self: anytype,
    totals: run_budget.Summary,
) run_budget.Verdict {
    if (!self.runBudgetGuestWindowObserved(totals)) return .unobserved;
    // Emulated guest time can remain flat while Xenia is translating the
    // next guest functions. That is not an idle guest: the ready-compiler
    // contract has an independent, monotonic external-progress witness
    // for exactly this phase. Defer only the below-budget result while
    // that witness is fresh; the raw budget still convicts once the same
    // bounded quiet window expires.
    return self.audit_budget.verdictForWithProgress(
        totals,
        self.ready.hasRecentExternalProgress(self.executed_steps),
    );
}
