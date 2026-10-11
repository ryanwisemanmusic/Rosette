// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const contract = __ProcessInternals._contract;
const execution_tracepoints = __ProcessInternals._execution_tracepoints;
const exit_diagnostics = __ProcessInternals._exit_diagnostics;
const gpu = __ProcessInternals._gpu;
const initializers = __ProcessInternals._initializers;
const jit = __ProcessInternals._jit;
const log = __ProcessInternals._log;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const macho_log = __ProcessInternals._macho_log;
const main = __ProcessInternals._main;
const native_crash = __ProcessInternals._native_crash;
const ready_compiler = __ProcessInternals._ready_compiler;
const std = __ProcessInternals._std;
const read64 = __ProcessInternals._read64;
const boundaryLabel = MachOState.boundaryLabel;
const execute = MachOState.execute;
const legacyTracepointRole = MachOState.legacyTracepointRole;
const logReadyCompilerDiagnosis = MachOState.logReadyCompilerDiagnosis;
const logReadyCompilerSummary = MachOState.logReadyCompilerSummary;
const logTranslationEconomics = MachOState.logTranslationEconomics;
const run = MachOState.run;
const step = MachOState.step;

pub fn armGraphicsTracepoints(self: anytype) void {
    const bringup = gpu.bringup_gate;
    const Target = struct {
        fragment: []const u8,
        role: execution_tracepoints.Role,
        /// Additional substrings a candidate must also contain, for a
        /// fragment that names a class rather than a function.
        also: []const []const u8 = &.{},
        /// Substrings that make a candidate a different provenance
        /// boundary rather than this one.
        exclude: []const []const u8 = &.{},
        /// The graphics boundary this address stands for, or
        /// `unbound_boundary` for an address armed for a question the
        /// contract does not cover.
        boundary: u8 = execution_tracepoints.unbound_boundary,
    };
    // The armed set used to be nine fragments chosen around one question:
    // did `VdSwap` run? That set could not answer "did the title register
    // an interrupt callback", "is the vblank pump still running" or "did
    // the command processor ever write a register" — and a run that
    // submitted twenty-four draws and stopped needed all three. The whole
    // boundary surface is armed here instead, from the contract, so a zero
    // anywhere on it is an execution fact rather than an unasked question.
    //
    // Legacy roles are preserved exactly for the addresses that already
    // carried one. Every newly armed boundary takes `.other`, so no
    // existing predicate built on `roleEntered` changes meaning; the new
    // gate reads the boundary tag instead.
    var wanted: [bringup.boundary_count + 1]Target = undefined;
    for (bringup.contractBoundaries(), 0..) |boundary, index| {
        wanted[index] = .{
            .fragment = boundary.fragment(),
            .role = legacyTracepointRole(boundary),
            .also = boundary.alsoRequires(),
            .exclude = boundary.exclusions(),
            .boundary = @intFromEnum(boundary),
        };
    }
    // The host diagnostic swap probe is deliberately outside the contract:
    // it is a boundary Rosette can reach on its own, and a contract stage
    // the harness can satisfy is not evidence about the title.
    wanted[bringup.boundary_count] = .{
        .fragment = "DebugIssueSwapFromHost",
        .role = .diagnostic_swap,
    };
    // Every executable candidate is armed, but ranked before the cap
    // applies. Taking the first four in hash order armed only the standard
    // library's closure machinery for `IssueSwap` — the allocator, the
    // compressed pair, `unique_ptr::get`, `__alloc_func::destroy` — and
    // never `VulkanCommandProcessor::IssueSwap` itself, so the role
    // reported NEVER ENTERED for a function nothing was watching.
    //
    // Ranking by mangled-name length separates them reliably: a real
    // method's name is short, and a template instantiation that merely
    // mentions it carries the whole enclosing type. Keeping four still
    // covers a virtual and its overrides.
    const per_fragment: usize = 4;
    for (wanted) |target| {
        var best_name: [per_fragment][]const u8 = [_][]const u8{""} ** per_fragment;
        var best_address: [per_fragment]u64 = [_]u64{0} ** per_fragment;
        var matches: u32 = 0;
        var rejected_non_executable: u32 = 0;
        var iterator = self.metadata.definedSymbolIterator();
        while (iterator.next()) |symbol| {
            const name = symbol.key_ptr.*;
            if (std.mem.indexOf(u8, name, target.fragment) == null) continue;
            // A fragment that names a class matches every member of it, and
            // ranking by name length would then arm a destructor. Requiring
            // a second substring narrows it without splicing Itanium length
            // prefixes into the contract.
            var missing_required = false;
            for (target.also) |required| {
                if (std.mem.indexOf(u8, name, required) == null) missing_required = true;
            }
            if (missing_required) continue;
            // `DebugIssueSwapFromHost` contains `IssueSwap`, but it is a
            // different provenance boundary. Without this exclusion a
            // forced host probe is armed twice and can be misreported as
            // authentic guest progress.
            var excluded = false;
            for (target.exclude) |forbidden| {
                if (std.mem.indexOf(u8, name, forbidden) != null) excluded = true;
            }
            if (excluded) continue;
            const address = symbol.value_ptr.*;
            matches += 1;
            // A guard variable or a static inside the function carries the
            // same fragment and is never executed, so a tracepoint there
            // would report "never entered" forever.
            if (address < self.executable_min or address >= self.executable_max) {
                rejected_non_executable += 1;
                continue;
            }
            var candidate_name = name;
            var candidate_address = address;
            var slot: usize = 0;
            while (slot < per_fragment) : (slot += 1) {
                if (best_address[slot] == 0) {
                    best_name[slot] = candidate_name;
                    best_address[slot] = candidate_address;
                    break;
                }
                if (candidate_name.len >= best_name[slot].len) continue;
                const displaced_name = best_name[slot];
                const displaced_address = best_address[slot];
                best_name[slot] = candidate_name;
                best_address[slot] = candidate_address;
                candidate_name = displaced_name;
                candidate_address = displaced_address;
            }
        }
        var armed: usize = 0;
        for (best_name, best_address) |name, address| {
            if (address == 0) continue;
            if (self.execution_tracepoints.armBoundary(name, address, target.role, target.boundary)) {
                armed += 1;
                machoCapturePrint(
                    "macho-processor: graphics tracepoint armed: role={s} ({s}) boundary={s} address=0x{x} candidates={d} symbol={s}\n",
                    .{
                        @tagName(target.role),
                        target.role.label(),
                        boundaryLabel(target.boundary),
                        address,
                        matches,
                        name,
                    },
                );
            }
        }
        if (target.boundary != execution_tracepoints.unbound_boundary and armed != 0) {
            self.gpu_bringup_gate.arm(
                @enumFromInt(target.boundary),
                @intCast(armed),
            );
        }
        if (armed == 0) {
            self.execution_tracepoints.noteUnresolved();
            machoCapturePrint(
                "macho-processor: graphics tracepoint UNRESOLVED: fragment={s} role={s} boundary={s} name_matches={d} rejected_non_executable={d}; a zero hit count for this boundary will mean nothing was watching, NOT that it never ran\n",
                .{
                    target.fragment,
                    @tagName(target.role),
                    boundaryLabel(target.boundary),
                    matches,
                    rejected_non_executable,
                },
            );
        }
    }
    self.gpu_bringup_gate.seal();
    if (self.execution_tracepoints.saturated()) {
        machoCapturePrint(
            "macho-processor: graphics tracepoints SATURATED: the armed set reached its capacity of {d}, so at least one boundary the contract names has no observer and its zero is Rosette's. Raise execution_tracepoints.max_tracepoints\n",
            .{execution_tracepoints.max_tracepoints},
        );
    }
    self.execution_tracepoints.seal();
    if (self.execution_tracepoints.count != 0) {
        self.observeGpuEarlyBoundary(
            .tracepoint_armed,
            .startup,
            self.execution_tracepoints.count,
        );
    }
    machoCapturePrint(
        "macho-processor: graphics tracepoints sealed: armed={d} unresolved={d} range=0x{x}..0x{x} executable=0x{x}..0x{x}; whether VdSwap executes is now read from the instruction pointer rather than inferred from a log line\n",
        .{
            self.execution_tracepoints.count,
            self.execution_tracepoints.unresolved,
            self.execution_tracepoints.low,
            self.execution_tracepoints.high,
            self.executable_min,
            self.executable_max,
        },
    );
}

pub noinline fn noteExecutionTracepoint(self: anytype) void {
    // At a function's entry instruction the return address is still on top
    // of the stack, so the caller is knowable without unwinding.
    const caller = self.read64(self.regs.rsp);
    const hit = self.execution_tracepoints.observe(
        self.regs.rip,
        self.executed_steps,
        self.active_guest_thread,
        caller,
    ) orelse return;
    self.observeGpuEarlyTracepoint(hit.role, hit.address);
    self.ready.noteEntered(hit.address, self.executed_steps, self.active_guest_thread, caller);
    if (self.ready.enabled()) {
        machoCapturePrint(
            "macho-processor: READY COMPILER: function-enter role={s} name={s} address=0x{x} step={d} thread=0x{x} caller=0x{x}\n",
            .{ @tagName(hit.role), hit.name, hit.address, self.executed_steps, self.active_guest_thread, caller },
        );
    }
    const identity = self.event_stream.next(
        .execution_boundary,
        self.executed_steps,
        self.active_guest_thread,
        0,
        caller,
    ) orelse return;
    const caller_symbol = self.metadata.nearestSymbol(caller);
    machoCapturePrint(
        "macho-processor: EXECUTION BOUNDARY ENTERED: run=0x{x} seq={d} role={s} symbol={s} address=0x{x} step={d} guest_thread=0x{x} caller=0x{x} caller_symbol={s}+0x{x}\n",
        .{
            identity.run_id,
            identity.sequence,
            @tagName(hit.role),
            hit.name,
            hit.address,
            identity.guest_step,
            identity.guest_thread,
            caller,
            self.metadata.symbolLabelFor(caller_symbol, caller),
            if (caller_symbol) |resolved| resolved.offset else 0,
        },
    );
}

pub fn observeGpuEarlyTracepoint(self: anytype, role: execution_tracepoints.Role, address: u64) void {
    const boundary: ?gpu.GpuEarlyBoundary = switch (role) {
        .swap => .guest_vdswap_entered,
        .ring_setup => null,
        .ring_publication => .ring_publication,
        .command_processor => .command_processor_entered,
        .command_swap => .presenter_entered,
        .xe_swap_decode => .xe_swap_decoder_entered,
        .presenter => .presenter_entered,
        .diagnostic_swap, .other => null,
    };
    if (boundary) |which| self.observeGpuEarlyBoundary(which, .tracepoint, address);
    if (role == .command_swap) self.observeGpuEarlyBoundary(.issue_swap_entered, .tracepoint, address);
}

pub fn observeGpuEarlyBoundary(
    self: anytype,
    boundary: gpu.GpuEarlyBoundary,
    source: gpu.GpuEarlySource,
    value: u64,
) void {
    const was_observed = self.gpu_early_frontier.observed(boundary);
    self.gpu_early_frontier.observe(boundary, self.executed_steps, source, value);
    if (was_observed) return;
    const next_label = if (self.gpu_early_frontier.firstActionable()) |next| next.label() else "none";
    machoCapturePrint(
        "macho-processor: GPU EARLY EDGE: boundary={s} owner={s} source={s} value=0x{x} step={d} observed=0x{x:0>8} actionable=0x{x:0>8} next={s}\n",
        .{
            boundary.label(),
            boundary.owner().label(),
            source.label(),
            value,
            self.executed_steps,
            self.gpu_early_frontier.observed_mask,
            self.gpu_early_frontier.actionableMask(),
            next_label,
        },
    );
}

pub fn configureReadyCompiler(
    self: anytype,
    enabled: bool,
    enforce: bool,
    activation_budget_steps: u64,
    quiet_budget_steps: u64,
    decoder_ready: bool,
) void {
    if (!enabled or !self.has_xenia_compat) {
        self.ready.disable();
        machoCapturePrint(
            "macho-processor: READY COMPILER: disabled xenia_compat={} requested={}\n",
            .{ self.has_xenia_compat, enabled },
        );
        return;
    }

    var runtime_contract = ready_compiler.xenia.contract();
    if (activation_budget_steps != 0) runtime_contract.activation_budget_steps = activation_budget_steps;
    if (quiet_budget_steps != 0) runtime_contract.quiet_budget_steps = quiet_budget_steps;
    self.ready.configure(runtime_contract, enforce);
    self.ready.beginCompile(self.executed_steps);

    const image_ready = self.entry_point_vaddr != 0 and self.segments.len != 0;
    self.ready.noteCompileCheck(
        "mach-o-image",
        image_ready,
        if (image_ready) "mapped executable image has an entry point" else "image has no executable entry point",
    );
    machoCapturePrint(
        "macho-processor: READY COMPILER: compile-check name=mach-o-image passed={} detail={s}\n",
        .{ image_ready, if (image_ready) "mapped executable image has an entry point" else "image has no executable entry point" },
    );
    self.ready.noteCompileCheck(
        "decoder-audit",
        decoder_ready,
        if (decoder_ready) "baseline VEX decoder audit passed" else "baseline VEX decoder audit failed",
    );
    machoCapturePrint(
        "macho-processor: READY COMPILER: compile-check name=decoder-audit passed={} detail={s}\n",
        .{ decoder_ready, if (decoder_ready) "baseline VEX decoder audit passed" else "baseline VEX decoder audit failed" },
    );
    _ = self.ready.noteStage(
        @intFromEnum(ready_compiler.xenia.Stage.image_ready),
        self.executed_steps,
        "rosette:image_loaded",
    );
    machoCapturePrint(
        "macho-processor: READY COMPILER: configured contract={s} enforce={} activation_budget={d} activation_budget_mode={s} quiet_budget={d}; compile checks are now separate from activation evidence\n",
        .{ runtime_contract.name, enforce, runtime_contract.activation_budget_steps, self.ready.activationBudgetMode(), runtime_contract.quiet_budget_steps },
    );
}

pub fn sealReadyCompilerCompile(self: anytype) bool {
    if (!self.ready.enabled()) return true;
    self.ready.noteCompileCheck(
        "static-initializers",
        true,
        "pre-main initializer transaction completed",
    );
    machoCapturePrint(
        "macho-processor: READY COMPILER: compile-check name=static-initializers passed=true detail=pre-main initializer transaction completed\n",
        .{},
    );
    if (!self.ready.sealCompile(self.executed_steps)) {
        self.logReadyCompilerFailure();
        return false;
    }
    _ = self.ready.noteStage(
        @intFromEnum(ready_compiler.xenia.Stage.compile_ready),
        self.executed_steps,
        "rosette:compile_checks",
    );
    _ = self.ready.noteStage(
        @intFromEnum(ready_compiler.xenia.Stage.static_initializers_complete),
        self.executed_steps,
        "rosette:static_initializers",
    );
    machoCapturePrint(
        "macho-processor: READY COMPILER: compile phase GREEN; activation phase opened at step={d}; the guest application is not ready until authentic native presentation\n",
        .{self.executed_steps},
    );
    machoCapturePrint(
        "macho-processor: READY COMPILER: activation phase OPEN compile_checks={d} dropped={d}\n",
        .{ self.ready.compile_check_count, self.ready.compile_checks_dropped },
    );
    return true;
}

pub fn noteReadyCompilerPipelineStage(self: anytype, raw_stage: u8, at_step: u64) void {
    if (!self.ready.enabled()) return;
    const stage = ready_compiler.xenia.pipelineStage(raw_stage) orelse {
        machoCapturePrint(
            "macho-processor: READY COMPILER: invalid pipeline stage raw={d} step={d}; no contract stage can consume this evidence\n",
            .{ raw_stage, at_step },
        );
        return;
    };
    const accepted = self.ready.noteStage(@intFromEnum(stage), at_step, "xenia:pipeline");
    self.logReadyCompilerStage(stage, accepted, at_step, "xenia:pipeline");
    if (accepted and stage == .processor_ready) self.jit_health.arm(at_step);
}

pub fn noteReadyCompilerGpuPhase(self: anytype, raw_phase: u8, at_step: u64) void {
    if (!self.ready.enabled()) return;
    const stage = ready_compiler.xenia.handoffPhase(raw_phase) orelse {
        machoCapturePrint(
            "macho-processor: READY COMPILER: invalid GPU handoff phase raw={d} step={d}; no contract stage can consume this evidence\n",
            .{ raw_phase, at_step },
        );
        return;
    };
    const accepted = self.ready.noteStage(@intFromEnum(stage), at_step, "xenia:gpu_handoff");
    self.logReadyCompilerStage(stage, accepted, at_step, "xenia:gpu_handoff");
}

pub fn noteReadyCompilerWait(self: anytype, object: u64, signaled: bool, at_step: u64) void {
    if (!self.ready.enabled()) return;
    const was_pending = self.ready.pending_wait_object == object;
    self.ready.noteWait(object, signaled, at_step);
    if (!signaled or was_pending) {
        machoCapturePrint(
            "macho-processor: READY COMPILER: wait object=0x{x} signaled={} step={d} pending=0x{x} timeout_count={d} signal_count={d}\n",
            .{
                object,
                signaled,
                at_step,
                self.ready.pending_wait_object,
                self.ready.wait_timeout_count,
                self.ready.wait_signal_count,
            },
        );
    }
}

pub fn observeJitHealthText(self: anytype, line: []const u8) void {
    const observation = self.jit_health.observe(line, self.executed_steps);
    self.reportJitHealthObservation(observation);
}

pub fn reportJitHealthObservation(self: anytype, observation: jit.JitHealthObservation) void {
    const report = self.jit_health.summary();
    if (observation.finding != .none) {
        const count = report.diagnosticCount();
        if (observation.startup_suppressed or observation.fatal or count <= 8 or count % 256 == 0) {
            machoCapturePrint(
                "macho-processor: XENIA JIT HEALTH: finding={s} fatal={} startup_suppressed={} phase={s} armed={} step={d} rip=0x{x} thread=0x{x} count={d} text={s}\n",
                .{
                    observation.finding.label(),
                    observation.fatal,
                    observation.startup_suppressed,
                    observation.phase.label(),
                    report.armed,
                    self.executed_steps,
                    self.regs.rip,
                    self.active_guest_thread,
                    count,
                    if (observation.line.len != 0) observation.line else "<no physical line>",
                },
            );
        }
        if (observation.fatal) self.faultOnJitHealth(observation);
    } else if (observation.event == .translation_generation_regression and
        (report.generation_regressions <= 8 or report.generation_regressions % 256 == 0))
    {
        machoCapturePrint(
            "macho-processor: XENIA JIT HEALTH: translation-generation regression generation={d} highest={d} guest_function=0x{x} step={d}; a replay is tolerated, but a lower generation is retained as metadata-integrity evidence\n",
            .{
                observation.generation,
                report.highest_generation,
                observation.guest_function,
                self.executed_steps,
            },
        );
    }
}

pub fn faultOnJitHealth(self: anytype, observation: jit.JitHealthObservation) void {
    if (self.jit_health_faulted) return;
    self.jit_health_faulted = true;
    self.faulted = true;
    self.exit_code = 125;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.runtime_invariant_failure);
    self.terminated = true;
    self.audit_pause.noteTermination(.diagnostic_termination, self.executed_steps);
    machoCapturePrint(
        "macho-processor: XENIA JIT HEALTH FAULT: finding={s} phase={s} armed={} armed_step={d} step={d} rip=0x{x} thread=0x{x} text={s}\n",
        .{
            observation.finding.label(),
            observation.phase.label(),
            self.jit_health.isArmed(),
            self.jit_health.summary().armed_step,
            self.executed_steps,
            self.regs.rip,
            self.active_guest_thread,
            if (observation.line.len != 0) observation.line else "<no physical line>",
        },
    );
    machoCapturePrint(
        "macho-processor: XENIA JIT HEALTH FAULT: terminating before the failed compiler/code-cache/publication path can be used; the signal is intentional and the reports below are the preserved failure context\n",
        .{},
    );
    self.logJitHealth(true);
    self.logReadyCompilerSummary();
    self.backend_diagnostics.logSummary();
    self.logTranslationEconomics();
    macho_log.flushAsyncTransport();
    self.macho_log.flush();
    native_crash.recordPhase("xenia-jit-health-fault");
    _ = std.c.raise(std.c.SIG.SEGV);
    // The native crash handler normally restores the default disposition
    // and re-raises. If a platform/runtime oddity makes raise return, do
    // not let the failed JIT path continue as if it were healthy.
    std.c.abort();
}

pub fn faultOnReadyCompilerFailure(self: anytype) void {
    if (self.ready_compiler_faulted) return;
    self.ready_compiler_faulted = true;
    self.faulted = true;
    self.exit_code = 125;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.runtime_invariant_failure);
    self.terminated = true;
    self.audit_pause.noteTermination(.diagnostic_termination, self.executed_steps);
    const failure = self.ready.failure;
    machoCapturePrint(
        "macho-processor: READY COMPILER FAULT: kind={s} step={d} rip=0x{x} thread=0x{x} expected={s} observed={s} reason={s}; terminating before unproven generated code can execute\n",
        .{
            failure.kind.label(),
            failure.step,
            self.regs.rip,
            self.active_guest_thread,
            if (failure.expected.len != 0) failure.expected else "<none>",
            if (failure.observed.len != 0) failure.observed else "<none>",
            if (failure.reason.len != 0) failure.reason else "<none>",
        },
    );
    self.logReadyCompilerSummary();
    self.logJitHealth(true);
    self.backend_diagnostics.logSummary();
    self.logTranslationEconomics();
    macho_log.flushAsyncTransport();
    self.macho_log.flush();
    native_crash.recordPhase("ready-compiler-fault");
    _ = std.c.raise(std.c.SIG.SEGV);
    // The native handler normally re-raises SIGSEGV. If it returns, the
    // failed readiness path must still be unable to continue.
    std.c.abort();
}

pub fn noteJitHostMmapFailure(
    self: anytype,
    stage: []const u8,
    address: u64,
    length: u64,
    prot: u64,
    flags: u64,
    map_jit: bool,
) void {
    var line_buffer: [512]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buffer,
        "x64 backend {s} mmap failed: address=0x{x} length={d} prot=0x{x} flags=0x{x} map_jit={} host JIT storage is unavailable",
        .{ stage, address, length, prot, flags, map_jit },
    ) catch "x64 backend mmap failed: diagnostic formatting exhausted";
    const finding: jit.JitHealthFinding = if (map_jit) .jit_support_failure else .code_cache_failure;
    const observation = self.jit_health.observeHostFailure(finding, line, self.executed_steps);
    self.reportJitHealthObservation(observation);
}

pub fn noteJitHostMprotectFailure(
    self: anytype,
    route: []const u8,
    address: u64,
    length: u64,
    prot: u64,
) void {
    var line_buffer: [512]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buffer,
        "x64 backend {s} mprotect failed: address=0x{x} length={d} prot=0x{x} executable publication cannot be trusted",
        .{ route, address, length, prot },
    ) catch "x64 backend mprotect failed: diagnostic formatting exhausted";
    const observation = self.jit_health.observeHostFailure(
        .executable_publication_failure,
        line,
        self.executed_steps,
    );
    self.reportJitHealthObservation(observation);
}

pub fn logJitHealth(self: anytype, force: bool) void {
    const report = self.jit_health.summary();
    if (!force and report.observed_lines == 0) return;
    machoCapturePrint(
        "macho-processor: XENIA JIT HEALTH: verdict={s} phase={s} armed={} armed_step={d} lines(messages/physical)={d}/{d} startup_suppressed={d} translation(progress/generation/replays/regressions)={d}/{d}/{d}/{d} diagnostics(label/compile/code_cache/publication/jit_support)={d}/{d}/{d}/{d}/{d} mapping(observed/verified/violations)={d}/{d}/{d} map_jit(observed/verified)={d}/{d} last_event={s} last_event_step={d} first_finding={s} first_finding_step={d} last_finding={s} last_finding_step={d}; startup diagnostics are retained separately, and armed compiler/code-cache/publication failures or contradictory mapping metadata are terminal\n",
        .{
            report.verdict().label(),
            report.phase.label(),
            report.armed,
            report.armed_step,
            report.observed_lines,
            report.physical_lines,
            report.startup_suppressed_diagnostics,
            report.translation_progress_events,
            report.highest_generation,
            report.translation_replays,
            report.generation_regressions,
            report.label_failures,
            report.compile_failures,
            report.code_cache_failures,
            report.executable_publication_failures,
            report.jit_support_failures,
            report.mapping_contract_observations,
            report.mapping_contract_verified,
            report.mapping_contract_violations,
            report.map_jit_mappings,
            report.map_jit_verified,
            report.last_event.label(),
            report.last_event_step,
            report.first_finding.label(),
            report.first_finding_step,
            report.last_finding.label(),
            report.last_finding_step,
        },
    );
}

pub fn observeReadyCompilerText(self: anytype, line: []const u8) void {
    if (!self.ready.enabled()) return;
    // The guest log bridge may deliver a whole diagnostic/configuration
    // blob in one callback. Readiness owns physical compiler lines, just
    // like the JIT ledger; otherwise a harmless CONFIG DUMP header can be
    // retained as `observed=` and poison the compile check before the
    // actual compiler has had a chance to run.
    var lines = std.mem.splitScalar(u8, line, '\n');
    while (lines.next()) |raw_line| {
        const physical_line = if (raw_line.len != 0 and raw_line[raw_line.len - 1] == '\r')
            raw_line[0 .. raw_line.len - 1]
        else
            raw_line;
        if (physical_line.len == 0) continue;
        self.observeReadyCompilerPhysicalLine(physical_line);
    }
}

pub fn observeReadyCompilerPhysicalLine(self: anytype, line: []const u8) void {
    if (ready_compiler.xenia.translationProgressFromText(line)) |event| {
        if (self.ready.noteTranslationProgress(event.generation, self.executed_steps)) {
            machoCapturePrint(
                "macho-processor: READY COMPILER: translation-progress accepted generation={d} guest_function=0x{x} step={d}\n",
                .{ event.generation, event.guest_function, self.executed_steps },
            );
        }
    }
    // These boundaries are finer than the legacy Xenia pipeline stages.
    // Observe them before the generic guest-log observers consume the same
    // line so `user_module_ready` cannot hide the precompile return or make
    // a never-entered shader request look like a failed shader backend.
    if (ready_compiler.xenia.workUnitStage(line)) |stage| {
        const stage_bit = @as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage)));
        const already_reached = self.ready.reached_mask & stage_bit != 0;
        const accepted = self.ready.noteStage(@intFromEnum(stage), self.executed_steps, "xenia:work_unit");
        if (!already_reached) self.logReadyCompilerStage(stage, accepted, self.executed_steps, "xenia:work_unit");
        if (accepted and stage == .processor_ready) self.jit_health.arm(self.executed_steps);
    }
    if (ready_compiler.Runtime.compilerDiagnosticKind(line)) |kind| {
        machoCapturePrint(
            "macho-processor: READY COMPILER: compiler-diagnostic kind={s} step={d} rip=0x{x} thread=0x{x} text={s}\n",
            .{ kind.label(), self.executed_steps, self.regs.rip, self.active_guest_thread, line },
        );
    }
    self.ready.observeCompilerText(line, self.executed_steps, self.regs.rip, self.active_guest_thread);
}

pub fn logReadyCompilerStage(
    self: anytype,
    stage: ready_compiler.xenia.Stage,
    accepted: bool,
    at_step: u64,
    source: []const u8,
) void {
    const spec = self.ready.stage(@intFromEnum(stage)) orelse return;
    const missing_prerequisites = spec.prerequisites & ~self.ready.reached_mask;
    const next_missing = self.ready.firstMissingRequired();
    machoCapturePrint(
        "macho-processor: READY COMPILER: stage name={s} id={d} accepted={} required={} owner={s} step={d} elapsed_steps={d} prerequisites=0x{x} missing_prerequisites=0x{x} reached=0x{x} next={s} next_owner={s} source={s}\n",
        .{
            spec.name,
            spec.id,
            accepted,
            spec.required,
            if (spec.owner.len != 0) spec.owner else "<unattributed>",
            at_step,
            self.ready.stage_duration[@intCast(spec.id)],
            spec.prerequisites,
            missing_prerequisites,
            self.ready.reached_mask,
            if (next_missing) |next| next.name else "<complete>",
            if (next_missing) |next|
                (if (next.owner.len != 0) next.owner else "<unattributed>")
            else
                "<none>",
            source,
        },
    );
    self.logReadyCompilerProgress();
    if (!accepted and self.ready.failure.kind != .none) self.logReadyCompilerFailure();
}

pub fn logReadyCompilerProgress(self: anytype) void {
    if (!self.ready.enabled()) return;
    const progress = self.ready.contractProgress();
    const next = self.ready.firstMissingRequired();
    machoCapturePrint(
        "macho-processor: READY COMPILER: CONTRACT PROGRESS block={d}/{d} required={d}/{d} edges={d}/{d} next={s} next_owner={s} next_detail={s}\n",
        .{
            progress.current_block,
            progress.required_total,
            progress.required_reached,
            progress.required_total,
            progress.reached,
            progress.total,
            if (next) |spec| spec.name else "<complete>",
            if (next) |spec|
                (if (spec.owner.len != 0) spec.owner else "<unattributed>")
            else
                "<none>",
            if (next) |spec| spec.description else "every required edge reached",
        },
    );
}

pub noinline fn pollReadyCompiler(self: anytype, at_step: u64) void {
    if (!self.ready.enabled() or self.ready.phase == .ready) return;
    const wait_object = self.pthreads.worstWaitObject(at_step);
    self.ready.noteSchedulingEvidence(
        self.pthreads.activeCount(),
        self.pthreads.blocked_threads,
        if (wait_object) |object| object.address else 0,
        if (wait_object) |object| object.notifications else 0,
        if (wait_object) |object| object.first_wait_step else 0,
        if (wait_object) |object| object.last_notify_step else 0,
        at_step,
    );
    self.ready.noteProgress(at_step, self.regs.rip, self.active_guest_thread, "heartbeat");
    // A startup step that runs past one quiet budget while still reporting
    // named work is slow, not stuck. Saying so out loud keeps the long
    // stages visible without letting them end the run.
    if (self.ready.takeSlowProgressNotice(at_step)) {
        const symbol = self.metadata.nearestSymbol(self.regs.rip);
        machoCapturePrint(
            "macho-processor: READY COMPILER: SLOW BUT PROGRESSING stage={s} owner={s} last_named_work={s} work_owner={s} work_thread=0x{x} work_rip=0x{x} at_step={d} step={d} milestone_quiet_steps={d} quiet_budget={d} rip=0x{x} {s}+0x{x} notice={d}\n",
            .{
                if (self.ready.firstMissingRequired()) |spec| spec.name else "<none>",
                if (self.ready.firstMissingRequired()) |spec|
                    (if (spec.owner.len != 0) spec.owner else "<unattributed>")
                else
                    "<none>",
                self.ready.workUnitName(),
                if (self.ready.work_unit.ownerSlice().len != 0) self.ready.work_unit.ownerSlice() else "<unknown>",
                self.ready.work_unit.thread,
                self.ready.work_unit.rip,
                self.ready.work_unit.step,
                at_step,
                at_step -| self.ready.last_milestone_step,
                if (self.ready.contract) |active| active.quiet_budget_steps else 0,
                self.regs.rip,
                self.metadata.symbolLabelFor(symbol, self.regs.rip),
                if (symbol) |resolved| resolved.offset else 0,
                self.ready.slow_progress_reports,
            },
        );
    }
    const evaluation = self.ready.evaluate(at_step);
    if ((evaluation == .failed and self.ready.last_reported_phase == .failed) or
        (evaluation != .failed and self.ready.last_reported_phase == self.ready.phase)) return;
    self.ready.last_reported_phase = self.ready.phase;
    switch (evaluation) {
        .waiting => {},
        .ready => machoCapturePrint(
            "macho-processor: READY COMPILER: GREEN application-ready contract={s} step={d}; terminal=authentic_native_presented activation_polling=closed authentic native presentation is now proven\n",
            .{ self.ready.contract.?.name, at_step },
        ),
        .failed => {
            self.logReadyCompilerFailure();
            if (self.ready.enforce and !self.terminated) {
                self.faultOnReadyCompilerFailure();
            }
        },
    }
}

pub fn logReadyCompilerFailure(self: anytype) void {
    const failure = self.ready.failure;
    machoCapturePrint(
        "macho-processor: READY COMPILER: BLOCKED kind={s} stage={s} function={s} step={d} rip=0x{x} thread=0x{x} object=0x{x} missing_prerequisites=0x{x} compiler_diagnostics={d} waits(timeout/signaled)={d}/{d} expected={s} observed={s} reason={s}\n",
        .{
            failure.kind.label(),
            if (failure.stage.len != 0) failure.stage else "<none>",
            if (failure.function.len != 0) failure.function else "<none>",
            failure.step,
            failure.rip,
            failure.thread,
            failure.object,
            failure.missing_prerequisites,
            self.ready.compiler_diagnostic_count,
            self.ready.wait_timeout_count,
            self.ready.wait_signal_count,
            if (failure.expected.len != 0) failure.expected else "<none>",
            if (failure.observed.len != 0) failure.observed else "<none>",
            if (failure.reason.len != 0) failure.reason else "<none>",
        },
    );
    self.logReadyCompilerDiagnosis();
}
