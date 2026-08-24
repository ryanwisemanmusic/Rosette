//! Runtime half of the ready compiler.
//!
//! This is not a second compiler and it does not pretend that precompiling a
//! function proves anything about its future execution. It is the small state
//! machine around compilation and activation that makes that distinction
//! observable and enforceable.

const std = @import("std");
const types = @import("types.zig");

pub const Runtime = struct {
    contract: ?types.Contract = null,
    phase: types.Phase = .disabled,
    enforce: bool = false,
    compile_checks: [types.max_compile_checks]types.CompileCheck = [_]types.CompileCheck{.{}} ** types.max_compile_checks,
    compile_check_count: usize = 0,
    compile_checks_dropped: usize = 0,
    functions: [types.max_functions]types.FunctionRecord = [_]types.FunctionRecord{.{}} ** types.max_functions,
    function_count: usize = 0,
    functions_dropped: usize = 0,
    reached_mask: u64 = 0,
    first_stage_step: [types.max_stages]u64 = [_]u64{0} ** types.max_stages,
    last_milestone_step: u64 = 0,
    activation_start_step: u64 = 0,
    last_progress_step: u64 = 0,
    last_rip: u64 = 0,
    last_thread: u64 = 0,
    last_source: []const u8 = "",
    pending_wait_object: u64 = 0,
    pending_wait_step: u64 = 0,
    wait_timeout_count: u64 = 0,
    wait_signal_count: u64 = 0,
    compiler_diagnostic_count: u64 = 0,
    failure: types.Failure = .{},
    last_reported_phase: types.Phase = .disabled,

    // --- Named sub-milestone progress -------------------------------------
    // A contract edge is a coarse event. Between two edges a healthy guest can
    // legitimately retire hundreds of millions of instructions, and without a
    // finer axis that is indistinguishable from a hang. These fields record
    // the intermediate work the owner reported, so "slow" and "stuck" stop
    // producing the same verdict.
    work_unit: types.WorkUnit = .{},
    work_unit_count: u64 = 0,
    work_units_at_last_milestone: u64 = 0,
    /// The last few breadcrumbs, oldest first once wrapped. One name says
    /// where the guest stopped; the trail says how it got there, which is the
    /// difference between a coordinate and a route.
    work_unit_history: [types.work_unit_history_len]types.WorkUnit =
        [_]types.WorkUnit{.{}} ** types.work_unit_history_len,
    work_unit_history_index: usize = 0,
    /// Steps between the previous reached stage and this one, so a stage that
    /// is merely slow is visible without cross-referencing the whole log.
    stage_duration: [types.max_stages]u64 = [_]u64{0} ** types.max_stages,
    /// The last required stage actually reached, and who reported it.
    frontier_stage_id: u8 = 0,
    frontier_reached: bool = false,
    milestone_thread: u64 = 0,

    // --- Quiet-window attribution -----------------------------------------
    // Sampling is direct-mapped so the execution witness stays O(1); the table
    // is only walked when a report is generated.
    stall_sites: [types.max_stall_sites]types.StallSite = [_]types.StallSite{.{}} ** types.max_stall_sites,
    stall_samples: u64 = 0,
    stall_site_evictions: u64 = 0,
    /// Count of consecutive samples that observed the same instruction pointer.
    /// A run that never breaks is the signature of a spin.
    same_site_run: u64 = 0,
    longest_same_site_run: u64 = 0,
    slow_progress_reports: u64 = 0,
    slow_progress_notified_at: u64 = 0,
    /// Per-thread view of the same window. One aggregate table averages a
    /// parked consumer and a busy producer into a shape that describes
    /// neither, which is how a starved ring reads as ordinary execution.
    stall_threads: [types.max_stall_threads]types.ThreadSample =
        [_]types.ThreadSample{.{}} ** types.max_stall_threads,
    stall_thread_count: usize = 0,
    stall_threads_dropped: u64 = 0,

    // --- Symbol-attributed progress ---------------------------------------
    // Some subsystems run for hundreds of millions of instructions without
    // logging anything. Their code still has a name, and a route package can
    // say which subsystem a symbol belongs to; that is a build-time fact, so
    // the host resolves it once per progress checkpoint and hands the answer
    // down here.
    //
    // Attribution is evidence, not permission. Three rules keep it from
    // holding a dead run open: the credit must come from a thread that is on
    // the launch path, its phase's prerequisite stage must already have been
    // reached, and the symbol must be one this phase has not already seen.
    // Revisiting known code retires instructions without reaching anything,
    // which is what a hang looks like from the outside and what it must keep
    // looking like from in here.
    attributed_phase_id: u8 = 0,
    attributed_phase_active: bool = false,
    attributed_phase_label: []const u8 = "",
    attributed_owner: []const u8 = "",
    attributed_after_stage: []const u8 = "",
    // Carried alongside the owner so a carrier joining this phase is judged by
    // the same proxy claim the phase itself was admitted under.
    attributed_proxy_owner: []const u8 = "",
    attributed_proxy_after_stage: []const u8 = "",
    attributed_last_phase_label: []const u8 = "",
    attributed_last_owner: []const u8 = "",
    attributed_symbol_hashes: [types.max_attributed_symbols]u64 =
        [_]u64{0} ** types.max_attributed_symbols,
    attributed_symbol_count: usize = 0,
    attributed_symbols_dropped: u64 = 0,
    attributed_credits: u64 = 0,
    attributed_rejected_thread: u64 = 0,
    attributed_rejected_stage: u64 = 0,

    // --- Independent progress evidence -----------------------------------
    // Counters the host services on the guest's behalf. They are the answer to
    // the symbol axis saturating: an emulator translating its guest's code
    // forever revisits the same translator functions, so "no new symbol" stops
    // meaning "no progress" long before the work stops.
    external_progress: types.ExternalProgress = .{},
    external_progress_step: u64 = 0,
    external_progress_advances: u64 = 0,
    external_progress_seen: bool = false,

    // --- Scheduler/wait evidence -----------------------------------------
    // A hot `yield_processor` site is only actionable when the scheduler says
    // no producer can run and the wait graph says the predicate has stayed
    // unchanged. The fields are supplied on heartbeat cadence by the Mach-O
    // host; they are intentionally not guessed from instruction samples.
    runnable_threads: u64 = 0,
    parked_threads: u64 = 0,
    wait_object: u64 = 0,
    wait_notifications: u64 = 0,
    wait_first_step: u64 = 0,
    wait_last_change_step: u64 = 0,
    scheduling_evidence_step: u64 = 0,

    pub fn configure(self: *Runtime, contract: types.Contract, enforce: bool) void {
        self.* = .{
            .contract = contract,
            .phase = .compile,
            .enforce = enforce,
            .last_reported_phase = .compile,
        };
    }

    pub fn disable(self: *Runtime) void {
        self.* = .{};
    }

    pub fn enabled(self: *const Runtime) bool {
        return self.phase != .disabled;
    }

    /// A zero total budget is intentional for the Xenia gameplay contract.
    /// Quiet-window diagnostics and typed compile/ordering failures remain
    /// active; this only answers whether the aggregate activation counter can
    /// stop the run.
    pub fn activationBudgetUnlimited(self: *const Runtime) bool {
        const contract = self.contract orelse return true;
        return contract.activation_budget_steps == 0;
    }

    pub fn activationBudgetMode(self: *const Runtime) []const u8 {
        return if (self.activationBudgetUnlimited()) "unlimited" else "finite";
    }

    /// The readiness gate is terminal once authentic native presentation has
    /// been proven. The application may continue running gameplay, but this
    /// startup compiler must not keep selecting activation work after that
    /// point.
    pub fn terminal(self: *const Runtime) bool {
        return self.phase == .ready or self.phase == .failed;
    }

    pub fn beginCompile(self: *Runtime, step: u64) void {
        if (!self.enabled()) return;
        self.phase = .compile;
        self.activation_start_step = step;
        self.last_milestone_step = step;
    }

    /// Record one build-style precondition. These are deliberately explicit:
    /// the caller must name what was checked and what the evidence said.
    pub fn noteCompileCheck(self: *Runtime, name: []const u8, passed: bool, detail: []const u8) void {
        if (!self.enabled()) return;
        if (self.compile_check_count >= self.compile_checks.len) {
            self.compile_checks_dropped +|= 1;
            if (self.failure.kind == .none) {
                self.fail(.{
                    .kind = .compile_evidence_missing,
                    .reason = "the ready compiler dropped a compile check before it could be recorded",
                    .expected = "every compile/runtime prerequisite retained",
                    .observed = name,
                });
            }
            return;
        }
        self.compile_checks[self.compile_check_count] = .{
            .name = name,
            .passed = passed,
            .detail = detail,
        };
        self.compile_check_count += 1;
        if (!passed and self.failure.kind == .none) {
            self.fail(.{
                .kind = .compile_check_failed,
                .function = name,
                .reason = detail,
                .expected = "compile/runtime prerequisite satisfied",
                .observed = "failed",
            });
        }
    }

    /// Close the build phase and permit activation only when the build checks
    /// were actually supplied and all of them passed.
    pub fn sealCompile(self: *Runtime, step: u64) bool {
        if (!self.enabled()) return true;
        if (self.phase == .failed) return false;
        if (self.compile_checks_dropped != 0 or self.compile_check_count == 0) {
            self.fail(.{
                .kind = .compile_evidence_missing,
                .reason = "the ready compiler was sealed without a complete compile-check set",
                .expected = "at least one retained, passing compile check",
                .observed = if (self.compile_check_count == 0) "no checks" else "compile-check capacity overflowed",
                .step = step,
            });
            return false;
        }
        for (self.compile_checks[0..self.compile_check_count]) |check| {
            if (check.passed) continue;
            self.fail(.{
                .kind = .compile_check_failed,
                .function = check.name,
                .reason = check.detail,
                .expected = "compile/runtime prerequisite satisfied",
                .observed = "failed",
                .step = step,
            });
            return false;
        }
        self.phase = .activation;
        self.activation_start_step = step;
        self.last_milestone_step = step;
        self.last_progress_step = step;
        return true;
    }

    /// Register a runtime-compiled function. A later `noteEntered` can then
    /// distinguish an installed function that was never activated from one
    /// that actually ran.
    pub fn declareFunction(self: *Runtime, address: u64, module: []const u8, name: []const u8) ?usize {
        if (!self.enabled()) return null;
        if (self.findFunction(address)) |index| return index;
        if (self.function_count >= self.functions.len) {
            self.functions_dropped +|= 1;
            return null;
        }
        self.functions[self.function_count] = .{
            .address = address,
            .module = module,
            .name = name,
            .state = .declared,
        };
        self.function_count += 1;
        return self.function_count - 1;
    }

    pub fn noteCompileStarted(self: *Runtime, address: u64, step: u64) void {
        const index = self.declareFunction(address, "", "") orelse return;
        const function = &self.functions[index];
        function.state = .compiling;
        function.compile_started_step = step;
    }

    pub fn noteCompiled(self: *Runtime, address: u64, step: u64) void {
        const index = self.declareFunction(address, "", "") orelse return;
        const function = &self.functions[index];
        function.state = .compiled;
        function.compiled_step = step;
    }

    pub fn noteInstalled(self: *Runtime, address: u64, step: u64) void {
        const index = self.declareFunction(address, "", "") orelse return;
        const function = &self.functions[index];
        function.state = .installed;
        function.installed_step = step;
    }

    pub fn noteCompileFailure(
        self: *Runtime,
        address: u64,
        kind: types.FailureKind,
        reason: []const u8,
        step: u64,
        rip: u64,
        thread: u64,
    ) void {
        const index = self.declareFunction(address, "", "") orelse null;
        if (index) |function_index| self.functions[function_index].state = .failed;
        self.fail(.{
            .kind = kind,
            .function = if (index) |function_index| self.functions[function_index].name else "",
            .reason = reason,
            .expected = "generated code has no unresolved compiler references",
            .observed = reason,
            .step = step,
            .rip = rip,
            .thread = thread,
        });
    }

    pub fn noteEntered(self: *Runtime, address: u64, step: u64, thread: u64, caller: u64) void {
        if (!self.enabled()) return;
        const index = self.declareFunction(address, "", "") orelse return;
        const function = &self.functions[index];
        if (function.entered_step == 0) function.entered_step = step;
        function.last_progress_step = step;
        function.entry_thread = thread;
        function.caller = caller;
        function.state = .entered;
        self.last_progress_step = step;
        self.last_rip = address;
        self.last_thread = thread;
    }

    /// Record the host-serviced counters at this checkpoint.
    ///
    /// O(1) and called on the progress-checkpoint cadence, not per instruction.
    /// The first call establishes a baseline and never counts as progress: the
    /// counters arrive already non-zero, and treating that as an advance would
    /// hand every run one free window it did not earn.
    pub fn noteExternalProgress(
        self: *Runtime,
        counters: types.ExternalProgress,
        step: u64,
    ) void {
        if (!self.enabled() or self.phase == .failed or self.phase == .ready) return;
        if (!self.external_progress_seen) {
            self.external_progress_seen = true;
            self.external_progress = counters;
            self.external_progress_step = step;
            return;
        }
        // Translation progress is reported asynchronously through the guest
        // log. Preserve it when the periodic heap/thread snapshot arrives,
        // whose literal does not carry that event's generation.
        const merged = types.ExternalProgress{
            .heap_high_water = counters.heap_high_water,
            .heap_live = counters.heap_live,
            .threads_created = counters.threads_created,
            .translation_generation = @max(
                counters.translation_generation,
                self.external_progress.translation_generation,
            ),
        };
        if (!merged.advancedFrom(self.external_progress)) return;
        self.external_progress = merged;
        self.external_progress_step = step;
        self.external_progress_advances +|= 1;
    }

    /// Record a successful PPC guest-function translation reported by Xenia.
    ///
    /// The generation is assigned by Xenia after assembly succeeds, not by
    /// this observer. Strict monotonicity rejects replayed or out-of-order log
    /// lines, so a noisy logger cannot buy repeated quiet windows.
    pub fn noteTranslationProgress(self: *Runtime, generation: u64, step: u64) bool {
        if (!self.enabled() or self.phase != .activation) return false;
        if (generation == 0 or generation <= self.external_progress.translation_generation) return false;
        self.external_progress.translation_generation = generation;
        self.external_progress_seen = true;
        self.external_progress_step = step;
        self.external_progress_advances +|= 1;
        return true;
    }

    pub fn translationProgressGeneration(self: *const Runtime) u64 {
        return self.external_progress.translation_generation;
    }

    /// The most recent step at which a host-serviced counter advanced.
    pub fn externalProgressStep(self: *const Runtime) u64 {
        return if (self.external_progress_seen) self.external_progress_step else 0;
    }

    /// Record an interpreter heartbeat or another trusted execution witness.
    /// This is intentionally separate from a semantic milestone: a loop can
    /// execute billions of instructions without completing startup.
    pub fn noteProgress(self: *Runtime, step: u64, rip: u64, thread: u64, source: []const u8) void {
        if (!self.enabled() or self.phase == .failed or self.phase == .ready) return;
        self.noteExecutionSample(step, rip, thread);
        self.last_source = source;
    }

    /// The cheap execution witness.
    ///
    /// Separate from `noteProgress` because the two run at different
    /// cadences: the contract is only evaluated at the coarse heartbeat, but
    /// attributing a quiet window needs far denser sampling than that, and a
    /// handful of samples per run cannot tell a loop from forward motion.
    /// Everything here is O(1) so the finer cadence stays affordable.
    pub fn noteExecutionSample(self: *Runtime, step: u64, rip: u64, thread: u64) void {
        if (!self.enabled() or self.phase == .failed or self.phase == .ready) return;
        if (step >= self.last_progress_step) self.last_progress_step = step;
        // Track whether the witness is moving before overwriting it. A step
        // count alone cannot separate a spin from forward execution, because
        // both retire instructions.
        if (rip == self.last_rip and self.stall_samples != 0) {
            self.same_site_run +|= 1;
        } else {
            self.same_site_run = 1;
        }
        if (self.same_site_run > self.longest_same_site_run) {
            self.longest_same_site_run = self.same_site_run;
        }
        self.last_rip = rip;
        self.last_thread = thread;
        self.sampleSite(rip, thread, step);
        self.sampleThread(rip, thread, step);
    }

    /// Attribute one sample to its thread. The table is capped at a handful of
    /// entries and scanned linearly: startup only has a few interesting
    /// threads, and a bounded scan of that size costs less than the hash it
    /// would replace.
    fn sampleThread(self: *Runtime, rip: u64, thread: u64, step: u64) void {
        for (self.stall_threads[0..self.stall_thread_count]) |*entry| {
            if (entry.thread != thread) continue;
            if (rip != entry.last_rip) entry.rip_changes +|= 1;
            entry.last_rip = rip;
            entry.samples +|= 1;
            entry.last_step = step;
            return;
        }
        if (self.stall_thread_count >= self.stall_threads.len) {
            self.stall_threads_dropped +|= 1;
            return;
        }
        self.stall_threads[self.stall_thread_count] = .{
            .thread = thread,
            .samples = 1,
            .last_rip = rip,
            .first_step = step,
            .last_step = step,
        };
        self.stall_thread_count += 1;
    }

    /// The thread that moved least during the window. A thread that never
    /// changed its instruction pointer is parked, whatever the aggregate site
    /// spread says about the process as a whole.
    pub fn mostParkedThread(self: *const Runtime) types.ThreadSample {
        var best: types.ThreadSample = .{};
        for (self.stall_threads[0..self.stall_thread_count]) |entry| {
            if (!entry.parked()) continue;
            if (entry.samples > best.samples) best = entry;
        }
        return best;
    }

    /// The stage that consumed the most steps.
    ///
    /// When a total budget runs out this is the only actionable fact in the
    /// report: the contract did not fail, one stage ate the allowance.
    pub fn costliestStage(self: *const Runtime) ?types.StageSpec {
        const contract = self.contract orelse return null;
        var best: ?types.StageSpec = null;
        var best_steps: u64 = 0;
        for (contract.stages) |spec| {
            const duration = self.stage_duration[@intCast(spec.id)];
            if (duration <= best_steps) continue;
            best_steps = duration;
            best = spec;
        }
        return best;
    }

    pub fn stageDuration(self: *const Runtime, id: u8) u64 {
        if (id >= self.stage_duration.len) return 0;
        return self.stage_duration[@intCast(id)];
    }

    /// Record one named sub-milestone breadcrumb.
    ///
    /// This is the axis that makes a long startup step legible. The gate's
    /// quiet window is measured from the most recent *named* progress, so a
    /// subsystem that reports what it is doing can take as long as it needs
    /// without being reported as a hang, while one that goes genuinely silent
    /// still trips the window.
    pub fn noteWorkUnit(self: *Runtime, name: []const u8, step: u64) void {
        self.noteWorkUnitAt(name, step, 0, 0);
    }

    /// Record the producer context alongside the breadcrumb. A text line is
    /// useful as a coordinate, but the thread and guest RIP answer the harder
    /// question: did the owner make this progress, or did another worker merely
    /// emit a log while the owner remained parked?
    pub fn noteWorkUnitAt(self: *Runtime, name: []const u8, step: u64, thread: u64, rip: u64) void {
        if (!self.enabled() or self.phase == .failed or self.phase == .ready) return;
        if (name.len == 0) return;
        // A repeated identical breadcrumb is a loop, not progress. Requiring
        // the name to change keeps a chatty retry loop from holding the quiet
        // window open forever.
        if (self.work_unit.matches(name)) return;
        self.work_unit.setAt(name, step, thread, rip);
        self.work_unit_history[self.work_unit_history_index].setAt(name, step, thread, rip);
        self.work_unit_history_index = (self.work_unit_history_index + 1) %
            self.work_unit_history.len;
        self.work_unit_count +|= 1;
        // The sample table must describe the same window the quiet budget
        // measures, and that window restarts here. Letting samples accumulate
        // across named progress would make the table and the verdict disagree
        // about which period they describe, and would hide a spin that starts
        // after a long healthy stage behind that stage's own wide spread.
        self.resetSiteSamples();
    }

    pub fn workUnitName(self: *const Runtime) []const u8 {
        return self.work_unit.slice();
    }

    /// Name of the most recently reached required contract edge.
    ///
    /// Route-specific attribution may use this as a bounded context signal
    /// when the current instruction resolves only to a generic host helper.
    /// It is deliberately read-only: the route package cannot advance the
    /// readiness graph by asking for its name.
    pub fn frontierStageName(self: *const Runtime) []const u8 {
        if (!self.frontier_reached) return "";
        return (self.stage(self.frontier_stage_id) orelse return "").name;
    }

    /// Whether the observed thread is allowed to speak for startup progress.
    ///
    /// Two threads can legitimately be doing startup work: the one that
    /// reached the last milestone, and the one the last milestone just handed
    /// off to. Startup is full of those handoffs — the launch thread posts
    /// shader storage to the command-processor thread and blocks, then starts
    /// guest main and stops being the actor entirely — so a rule that only
    /// ever trusts the milestone thread goes blind at exactly the moments the
    /// contract is moving fastest.
    ///
    /// The handoff is recognised without guessing: a phase declares the stage
    /// it cannot precede, and a phase whose stage is the *most recent* one
    /// reached is by definition the work that stage just enabled. A thread
    /// running some other subsystem's phase from five milestones ago is not on
    /// the launch path — it is a worker that happens to be busy, and a busy
    /// worker is what a hung launch looks like from the outside.
    ///
    /// Frontier equality alone is not enough, and assuming it was cost a run.
    /// The last few startup edges land in quick succession and then the
    /// contract sits waiting on one owner for a long time. Every phase that
    /// owner runs declares an *earlier* prerequisite — it has to, since its
    /// prerequisite is what enabled it — so once the frontier moves past that
    /// edge, frontier equality rejects the blocked owner's own evidence. The
    /// gate then reports silence it created itself, and fails the run for it.
    ///
    /// So a phase may also speak when it belongs to the subsystem that owes
    /// the missing edge. That is not a relaxation: it is the same question
    /// asked about the right stage. Frontier equality asks "did the last edge
    /// enable this work"; owner match asks "is this the work the *next* edge is
    /// waiting for". Both are on the launch path. A busy worker owned by
    /// neither is still refused, which is the property worth keeping.
    fn attributionThreadAllowed(
        self: *const Runtime,
        thread: u64,
        after_stage: []const u8,
        owner: []const u8,
        proxy_owner: []const u8,
        proxy_after_stage: []const u8,
    ) bool {
        if (self.milestone_thread == 0) return true;
        if (thread == self.milestone_thread) return true;
        if (self.ownsMissingEdge(owner)) return true;
        // A proxy owner speaks only after its own stage has landed. Before
        // that the phase is doing the same work on its own initiative and has
        // no claim on anybody else's progress.
        if (proxy_owner.len != 0 and
            self.attributionStageReached(proxy_after_stage) and
            self.ownsMissingEdge(proxy_owner)) return true;
        if (after_stage.len == 0 or !self.frontier_reached) return false;
        const frontier = self.stage(self.frontier_stage_id) orelse return false;
        return std.mem.eql(u8, frontier.name, after_stage);
    }

    /// Whether this subsystem is the one that owes the edge the contract is
    /// currently waiting for.
    ///
    /// An empty owner never matches. A phase that names nobody cannot be the
    /// blocked owner, and treating "unknown" as "whoever we are waiting for"
    /// would hand every carrier a permanent pass.
    fn ownsMissingEdge(self: *const Runtime, owner: []const u8) bool {
        if (owner.len == 0) return false;
        const missing = self.firstMissingRequired() orelse return false;
        if (missing.owner.len == 0) return false;
        return std.mem.eql(u8, missing.owner, owner);
    }

    /// Whether a phase's declared prerequisite stage has actually been reached.
    ///
    /// A route package says which contract edge a phase cannot precede; the
    /// gate is the only side that knows which edges have landed. An unknown
    /// stage name passes rather than fails — the compile-time cross-check in
    /// the contract is what catches a name that does not exist, and failing
    /// here as well would turn one clear build error into a silent runtime
    /// behaviour change.
    fn attributionStageReached(self: *const Runtime, stage_name: []const u8) bool {
        if (stage_name.len == 0) return true;
        const contract = self.contract orelse return true;
        for (contract.stages) |spec| {
            if (!std.mem.eql(u8, spec.name, stage_name)) continue;
            const bit = stageBit(spec.id) orelse return true;
            return self.reached_mask & bit != 0;
        }
        return true;
    }

    fn resetAttribution(self: *Runtime) void {
        self.attributed_phase_active = false;
        self.attributed_phase_id = 0;
        self.attributed_phase_label = "";
        self.attributed_owner = "";
        self.attributed_after_stage = "";
        self.attributed_proxy_owner = "";
        self.attributed_proxy_after_stage = "";
        self.attributed_symbol_count = 0;
        self.attributed_symbols_dropped = 0;
    }

    /// Whether this phase has reached this symbol before in the current window.
    ///
    /// The set is keyed by phase *and* symbol but is shared across phases and
    /// reset only at a contract edge. Per-phase sets would look tidier and
    /// would be wrong: a loop that alternates between two subsystems — reading
    /// a cvar and touching the game database, say — would clear the set on
    /// every switch and credit progress forever. The budget belongs to the
    /// window the quiet timer measures, not to whichever phase is current.
    fn attributionSymbolIsNew(self: *Runtime, phase_id: u8, symbol: []const u8) bool {
        if (symbol.len == 0) return false;
        var hash = std.hash.Wyhash.hash(0, symbol);
        hash = std.hash.Wyhash.hash(hash, &[_]u8{phase_id});
        for (self.attributed_symbol_hashes[0..self.attributed_symbol_count]) |seen| {
            if (seen == hash) return false;
        }
        if (self.attributed_symbol_count >= self.attributed_symbol_hashes.len) {
            // The phase has spent its evidence. Further symbols are real, but
            // the gate has already been told everything this axis can tell it,
            // and continuing to credit would turn a bounded signal into an
            // unbounded reprieve.
            self.attributed_symbols_dropped +|= 1;
            return false;
        }
        self.attributed_symbol_hashes[self.attributed_symbol_count] = hash;
        self.attributed_symbol_count += 1;
        return true;
    }

    /// Record that the guest was observed executing inside a named startup
    /// region, and return whether that counted as progress.
    ///
    /// `phase_id`, `label` and `owner` come from the route package; `symbol` is
    /// the resolved Mach-O symbol the sample landed in. A `carrier` symbol
    /// (libc++, libc, UTF-8 — code with no subsystem of its own) names no
    /// phase and instead joins whichever phase last identified itself, which
    /// is how a byte-at-a-time container copy inside a parser gets attributed
    /// to the parser rather than to nothing.
    ///
    /// Returns false far more often than true, and that is the design. A
    /// return of true means one thing only: this thread reached code inside
    /// this phase that it had not reached before.
    pub fn noteAttributedSite(
        self: *Runtime,
        attribution: types.SiteAttribution,
        symbol: []const u8,
        step: u64,
        rip: u64,
        thread: u64,
    ) bool {
        if (!self.enabled() or self.phase != .activation) return false;
        // A carrier is judged by the phase it would join, not by its own empty
        // one: it is the same thread continuing the same work.
        const gate_stage = if (attribution.carrier)
            (if (self.attributed_phase_active) self.attributed_after_stage else "")
        else
            attribution.after_stage;
        // A carrier inherits the whole identity of the phase it joins, owner
        // and proxy included. Judging it by its own empty owner would refuse
        // the libc++ helper that a blocked subsystem is calling from inside
        // its own code — the single most common shape of a real sample.
        const gate_owner = if (attribution.carrier)
            (if (self.attributed_phase_active) self.attributed_owner else "")
        else
            attribution.owner;
        const gate_proxy_owner = if (attribution.carrier)
            (if (self.attributed_phase_active) self.attributed_proxy_owner else "")
        else
            attribution.proxy_owner;
        const gate_proxy_stage = if (attribution.carrier)
            (if (self.attributed_phase_active) self.attributed_proxy_after_stage else "")
        else
            attribution.proxy_after_stage;
        if (!self.attributionThreadAllowed(
            thread,
            gate_stage,
            gate_owner,
            gate_proxy_owner,
            gate_proxy_stage,
        )) {
            self.attributed_rejected_thread +|= 1;
            return false;
        }
        if (attribution.carrier) {
            // A carrier before any phase has been established is a sample with
            // nothing behind it. Guessing an owner here is how a report ends up
            // confidently naming the wrong subsystem.
            if (!self.attributed_phase_active) return false;
        } else if (!self.attributed_phase_active or self.attributed_phase_id != attribution.phase_id) {
            if (!self.attributionStageReached(attribution.after_stage)) {
                self.attributed_rejected_stage +|= 1;
                return false;
            }
            self.attributed_phase_active = true;
            self.attributed_phase_id = attribution.phase_id;
            self.attributed_phase_label = attribution.label;
            self.attributed_owner = attribution.owner;
            self.attributed_after_stage = attribution.after_stage;
            self.attributed_proxy_owner = attribution.proxy_owner;
            self.attributed_proxy_after_stage = attribution.proxy_after_stage;
            self.attributed_last_phase_label = attribution.label;
            self.attributed_last_owner = attribution.owner;
        }
        if (!self.attributionSymbolIsNew(attribution.phase_id, symbol)) return false;
        self.attributed_credits +|= 1;

        // The breadcrumb has to change on every credit or `noteWorkUnitAt`
        // treats it as a repeated name and discards it, which is exactly the
        // behaviour a spinning producer needs and exactly the wrong behaviour
        // for a parser walking new code. The distinct-site count is the thing
        // that changed, so it is the thing that goes in the name; it counts
        // the whole window rather than the current phase, which is also what
        // bounds how long attribution can keep a window open.
        var buffer: [types.max_work_unit_name]u8 = undefined;
        const rendered = std.fmt.bufPrint(
            buffer[0..],
            "{s} sites={d}",
            .{ self.attributed_phase_label, self.attributed_symbol_count },
        ) catch self.attributed_phase_label;
        self.noteWorkUnitAt(rendered, step, thread, rip);
        return true;
    }

    /// The startup region the guest was last attributed to, or empty.
    pub fn attributedPhaseLabel(self: *const Runtime) []const u8 {
        if (!self.attributed_phase_active) return "";
        return self.attributed_phase_label;
    }

    pub fn attributedOwner(self: *const Runtime) []const u8 {
        if (!self.attributed_phase_active) return "";
        return self.attributed_owner;
    }

    pub fn attributedLastPhaseLabel(self: *const Runtime) []const u8 {
        return self.attributed_last_phase_label;
    }

    pub fn attributedLastOwner(self: *const Runtime) []const u8 {
        return self.attributed_last_owner;
    }

    /// The retained trail in chronological order, oldest first. An entry of
    /// zero length was never filled.
    pub fn workUnitHistoryAt(self: *const Runtime, position: usize) types.WorkUnit {
        if (position >= self.work_unit_history.len) return .{};
        // Once the ring has wrapped, the write cursor points at the oldest
        // retained entry rather than at the start of the array.
        const oldest = if (self.work_unit_count >= self.work_unit_history.len)
            self.work_unit_history_index
        else
            0;
        return self.work_unit_history[(oldest + position) % self.work_unit_history.len];
    }

    /// Named work observed since the last contract edge. Zero means the owner
    /// of the missing edge has reported nothing at all.
    pub fn workUnitsSinceMilestone(self: *const Runtime) u64 {
        return self.work_unit_count -| self.work_units_at_last_milestone;
    }

    /// The most recent step at which *any* named progress was observed. The
    /// quiet window is measured from here rather than from the last contract
    /// edge, which is what stops a slow startup step from reading as a stall.
    pub fn lastNamedProgressStep(self: *const Runtime) u64 {
        const named = @max(self.last_milestone_step, self.work_unit.step);
        // A host-serviced counter is unnamed but not silent: it says the guest
        // obtained something, which no amount of spinning can do. Folding it in
        // here rather than only into the classification means the quiet timer
        // itself stops running, so a long legitimate stretch of work does not
        // have to out-run a clock it was never actually failing.
        if (self.external_progress_advances == 0) return named;
        return @max(named, self.external_progress_step);
    }

    /// Direct-mapped sample insert. Bounded and O(1): the interpreter's
    /// heartbeat must never pay for a scan.
    fn sampleSite(self: *Runtime, rip: u64, thread: u64, step: u64) void {
        self.stall_samples +|= 1;
        const slot = &self.stall_sites[siteIndex(rip)];
        if (slot.samples != 0 and slot.rip != rip) {
            // A collision replaces the colder occupant. The eviction count is
            // reported so a saturated table is never mistaken for a narrow
            // spread of execution sites.
            self.stall_site_evictions +|= 1;
            if (slot.samples > 1) {
                slot.samples -= 1;
                return;
            }
            slot.* = .{};
        }
        if (slot.samples == 0) {
            slot.rip = rip;
            slot.thread = thread;
            slot.first_step = step;
        }
        slot.samples +|= 1;
        slot.thread = thread;
        slot.last_step = step;
    }

    fn siteIndex(rip: u64) usize {
        // Multiplicative hash: instruction pointers are dense and low-entropy
        // in their low bits, so the raw address is a poor index.
        const mixed = (rip *% 0x9E3779B97F4A7C15) >> 56;
        return @intCast(mixed % types.max_stall_sites);
    }

    /// The site that held the most samples. Report-time only.
    pub fn hottestSite(self: *const Runtime) types.StallSite {
        var best: types.StallSite = .{};
        for (self.stall_sites) |site| {
            if (site.samples > best.samples) best = site;
        }
        return best;
    }

    /// The `rank`-th hottest site, rank zero being the hottest, ordered by
    /// samples descending and address ascending so the order is stable.
    ///
    /// Repeated selection rather than a sort: the table is small and fixed,
    /// and sorting in place would reorder live state while a report walks it.
    /// Returns an empty site once the ranks are exhausted.
    pub fn siteByRank(self: *const Runtime, rank: usize) types.StallSite {
        var previous_samples: u64 = ~@as(u64, 0);
        var previous_rip: u64 = 0;
        var position: usize = 0;
        var chosen: types.StallSite = .{};
        while (position <= rank) : (position += 1) {
            chosen = .{};
            for (self.stall_sites) |site| {
                if (site.samples == 0) continue;
                const after_previous = site.samples < previous_samples or
                    (site.samples == previous_samples and site.rip > previous_rip);
                if (!after_previous) continue;
                const better = chosen.samples == 0 or site.samples > chosen.samples or
                    (site.samples == chosen.samples and site.rip < chosen.rip);
                if (better) chosen = site;
            }
            if (chosen.samples == 0) return .{};
            previous_samples = chosen.samples;
            previous_rip = chosen.rip;
        }
        return chosen;
    }

    pub fn distinctSites(self: *const Runtime) usize {
        var count: usize = 0;
        for (self.stall_sites) |site| {
            if (site.samples != 0) count += 1;
        }
        return count;
    }

    pub fn noteSchedulingEvidence(
        self: *Runtime,
        runnable_threads: u64,
        parked_threads: u64,
        wait_object: u64,
        wait_notifications: u64,
        wait_first_step: u64,
        wait_last_change_step: u64,
        step: u64,
    ) void {
        if (!self.enabled() or self.phase == .ready) return;
        self.runnable_threads = runnable_threads;
        self.parked_threads = parked_threads;
        self.wait_object = wait_object;
        self.wait_notifications = wait_notifications;
        self.wait_first_step = wait_first_step;
        self.wait_last_change_step = wait_last_change_step;
        self.scheduling_evidence_step = step;
    }

    pub fn spinVerdict(self: *const Runtime, step: u64) types.SpinVerdict {
        if (!self.spinning()) return .not_concentrated;
        if (self.runnable_threads != 0) return .runnable_producer_present;
        if (self.wait_object == 0) return .predicate_unobserved;
        const contract = self.contract orelse return .predicate_recently_changed;
        const stable_since = if (self.wait_notifications == 0)
            self.wait_first_step
        else
            self.wait_last_change_step;
        if (stable_since == 0 or step -| stable_since < contract.quiet_budget_steps) {
            return .predicate_recently_changed;
        }
        return .scheduling_starvation;
    }

    /// Clear the quiet-window evidence. Called when a contract edge is
    /// reached, so the next window describes the next stage rather than
    /// accumulating every site seen since activation opened.
    fn resetSiteSamples(self: *Runtime) void {
        self.stall_sites = [_]types.StallSite{.{}} ** types.max_stall_sites;
        self.stall_samples = 0;
        self.stall_site_evictions = 0;
        self.same_site_run = 0;
        self.longest_same_site_run = 0;
        self.stall_threads = [_]types.ThreadSample{.{}} ** types.max_stall_threads;
        self.stall_thread_count = 0;
        self.stall_threads_dropped = 0;
    }

    /// Observe a contract edge. Missing prerequisites are failures for required
    /// edges, not merely statistics, because the purpose of this layer is to
    /// stop an invalid startup order before downstream symptoms bury it.
    /// Optional edges are advisory evidence: a host diagnostic present can
    /// legitimately occur before the guest has produced its first frame. It
    /// is retained for reporting but must not terminate the application or
    /// reset the quiet window for the required guest-owned frontier.
    pub fn noteStage(self: *Runtime, id: u8, step: u64, source: []const u8) bool {
        if (!self.enabled() or self.phase == .failed or self.phase == .ready) return false;
        const spec = self.stage(id) orelse {
            self.fail(.{
                .kind = .missing_milestone,
                .reason = "an event named a stage outside the active readiness contract",
                .expected = "stage id present in the contract",
                .observed = "unknown stage id",
                .step = step,
                .rip = self.last_rip,
                .thread = self.last_thread,
            });
            return false;
        };
        const bit = stageBit(id) orelse return false;
        if ((self.reached_mask & bit) != 0) return true;
        const missing_prerequisites = spec.prerequisites & ~self.reached_mask;
        if (missing_prerequisites != 0) {
            self.reached_mask |= bit;
            self.first_stage_step[@intCast(id)] = step;
            if (!spec.required) {
                self.last_source = source;
                return true;
            }
            self.fail(.{
                .kind = .ordering_violation,
                .stage = spec.name,
                .reason = "a startup stage arrived before one of its prerequisites",
                .expected = "all declared prerequisite stages reached first",
                .observed = source,
                .step = step,
                .rip = self.last_rip,
                .thread = self.last_thread,
                .missing_prerequisites = missing_prerequisites,
            });
            return false;
        }
        self.reached_mask |= bit;
        self.first_stage_step[@intCast(id)] = step;
        // How long this edge took, measured from the previous edge. A stage
        // that is simply slow is otherwise invisible until it trips a budget.
        self.stage_duration[@intCast(id)] = step -| self.last_milestone_step;
        self.last_milestone_step = step;
        self.last_source = source;
        if (spec.required) {
            self.frontier_stage_id = id;
            self.frontier_reached = true;
        }
        self.milestone_thread = self.last_thread;
        self.work_units_at_last_milestone = self.work_unit_count;
        // The next quiet window must describe the next stage, not every site
        // observed since activation opened.
        self.resetSiteSamples();
        // Symbols already seen become new evidence again past a contract edge:
        // the same parser running before and after a milestone is doing
        // different work, and the credit budget belongs to the window rather
        // than to the run.
        self.resetAttribution();
        return true;
    }

    pub fn noteWait(self: *Runtime, object: u64, signaled: bool, step: u64) void {
        if (!self.enabled() or self.phase == .ready) return;
        if (signaled) {
            self.wait_signal_count +|= 1;
            if (self.pending_wait_object == object) self.pending_wait_object = 0;
            return;
        }
        self.wait_timeout_count +|= 1;
        self.pending_wait_object = object;
        self.pending_wait_step = step;
    }

    /// A timeout result is evidence that a wait returned, not proof that the
    /// thread is still parked on that object.  The log bridge can observe a
    /// timeout from one Xenia worker and then observe another worker (or the
    /// same worker) making named progress before the next readiness poll.  In
    /// that shape, retaining the old object as a live blocker would let one
    /// stale line override the execution and host-progress witnesses.
    ///
    /// Keep the observation available for diagnostics, but only let it drive a
    /// terminal wait verdict while it is at least as recent as every other
    /// progress witness.  A genuinely parked wait still has no later named or
    /// host-serviced progress and therefore remains eligible for the existing
    /// wait test.
    fn pendingWaitIsCurrent(self: *const Runtime) bool {
        if (self.pending_wait_object == 0) return false;
        return self.pending_wait_step >= self.lastNamedProgressStep();
    }

    /// Classify text that can explain a runtime compiler failure. The caller
    /// may continue recording the text after the first typed failure; first
    /// failure wins for control flow, but later evidence must remain visible
    /// in the diagnostic log.
    pub fn compilerDiagnosticKind(line: []const u8) ?types.FailureKind {
        if (std.mem.indexOf(u8, line, "undefined label") != null or
            std.mem.indexOf(u8, line, "label is not found") != null)
        {
            return .label_reference_unbound;
        }
        if (std.mem.indexOf(u8, line, "Xbyak") != null or
            std.mem.indexOf(u8, line, "codegen failed") != null or
            std.mem.indexOf(u8, line, "function left undefined") != null)
        {
            return .compile_check_failed;
        }
        return null;
    }

    /// Keys that introduce a structured progress breadcrumb. The convention is
    /// what is recognized, never one guest's vocabulary, so any producer that
    /// reports `stage=`/`step=`/`phase=` feeds the work-unit axis.
    const work_unit_keys = [_][]const u8{ "stage=", "step=", "phase=" };

    /// Extract a named sub-milestone breadcrumb from guest text.
    ///
    /// The returned slice borrows from `line`; callers copy it. A value that
    /// is purely numeric is rejected, because `step=83489913` is a counter
    /// rather than a name and would otherwise make every heartbeat look like
    /// fresh progress.
    pub fn workUnitFromText(line: []const u8) ?[]const u8 {
        for (work_unit_keys) |key| {
            var search: usize = 0;
            while (std.mem.indexOfPos(u8, line, search, key)) |found| {
                search = found + key.len;
                // The key must start a token, or `first_step=` would match
                // `step=`.
                if (found != 0 and !isBoundary(line[found - 1])) continue;
                const value_start = found + key.len;
                var value_end = value_start;
                // Any whitespace ends the value. A breadcrumb whose value is
                // the last token on the line would otherwise capture the
                // trailing newline and break the log line it is printed into.
                while (value_end < line.len and !isBoundary(line[value_end])) value_end += 1;
                if (value_end == value_start) continue;
                if (!hasLetter(line[value_start..value_end])) continue;
                // Include the token in front of the key: a bare
                // `stage=LoadContinue.end` does not say who reported it, and
                // the owner is half of the finding.
                var name_start = found;
                if (found >= 2) {
                    var scan = found - 1;
                    while (scan > 0 and !isBoundary(line[scan - 1])) scan -= 1;
                    name_start = scan;
                }
                return line[name_start..value_end];
            }
        }
        return null;
    }

    /// Whitespace and control bytes both end a token. Guest text arrives with
    /// its own line terminator attached, so a newline is a boundary too.
    fn isBoundary(character: u8) bool {
        return character <= ' ';
    }

    fn hasLetter(text: []const u8) bool {
        for (text) |character| {
            if ((character >= 'a' and character <= 'z') or
                (character >= 'A' and character <= 'Z')) return true;
        }
        return false;
    }

    /// Compiler diagnostics can arrive through a text boundary when the
    /// underlying compiler is outside Rosette. Keeping this recognizer here
    /// makes an Xbyak label failure a typed readiness failure instead of an
    /// eventual null-function crash.
    ///
    /// The same text carries the guest's own progress breadcrumbs, so this is
    /// also where the work-unit axis is fed.
    pub fn observeCompilerText(self: *Runtime, line: []const u8, step: u64, rip: u64, thread: u64) void {
        if (!self.enabled() or self.phase == .ready) return;
        if (workUnitFromText(line)) |name| self.noteWorkUnitAt(name, step, thread, rip);
        const kind = compilerDiagnosticKind(line) orelse return;
        self.compiler_diagnostic_count +|= 1;
        // The state machine deliberately keeps the first failure as the
        // control-flow verdict. The caller still logs every later diagnostic,
        // so a second Xbyak failure cannot disappear behind the first one.
        if (self.phase != .failed) self.noteCompileFailure(0, kind, line, step, rip, thread);
    }

    /// Samples needed before the concentration evidence may carry a verdict.
    /// Below this the witness is too sparse to distinguish a loop from a
    /// coincidence, and a wrong hang verdict is worse than none.
    pub const min_spin_samples: u64 = 16;
    /// How many distinct sites a loop is allowed to occupy. Above this the
    /// guest is executing broadly whatever else is true, so requiring a single
    /// address would only ever match a one-instruction loop.
    pub const max_spin_sites: usize = 4;

    /// A spin is execution confined to a handful of addresses.
    ///
    /// Two independent signals must agree. Concentration alone can be produced
    /// by an unlucky run of hash collisions, so the eviction rate has to be low
    /// as well: a broad execution front churns the direct-mapped table, and a
    /// loop that revisits the same few addresses does not.
    pub fn spinning(self: *const Runtime) bool {
        if (self.stall_samples < min_spin_samples) return false;
        const distinct = self.distinctSites();
        if (distinct == 0 or distinct > max_spin_sites) return false;
        return self.stall_site_evictions *| 4 <= self.stall_samples;
    }

    /// Which of the three evidence axes is actually moving.
    pub fn classifyProgress(self: *const Runtime, step: u64) types.ProgressClass {
        const contract = self.contract orelse return .unknown;
        const quiet = contract.quiet_budget_steps;
        // Without a quiet budget there is no window to be silent in, so the
        // only answerable question is whether any edge was ever reached.
        if (quiet == 0) {
            return if (self.reached_mask == 0) .unknown else .milestone_advancing;
        }
        if (step -| self.last_milestone_step < quiet) return .milestone_advancing;
        if (self.workUnitsSinceMilestone() != 0 and
            step -| self.work_unit.step < quiet) return .work_advancing;
        // Ranked below named work and above bare execution, which is exactly
        // its strength: it is weaker evidence than a subsystem saying what it
        // is doing, and far stronger than instructions retiring, because a
        // spin loop produces the latter and cannot produce this.
        if (self.external_progress_advances != 0 and
            step -| self.external_progress_step < quiet) return .external_advancing;
        if (self.last_progress_step <= self.last_milestone_step) return .frozen;
        if (self.spinning()) return .spinning;
        return .executing_only;
    }

    /// Collect every piece of evidence behind the current verdict, so the
    /// blocked line and the end-of-run summary cannot disagree.
    pub fn diagnose(self: *const Runtime, step: u64) types.Diagnosis {
        var result = types.Diagnosis{};
        const contract = self.contract orelse return result;
        result.progress = self.classifyProgress(step);
        if (self.firstMissingRequired()) |spec| {
            result.missing_stage = spec.name;
            result.missing_owner = spec.owner;
            result.missing_description = spec.description;
            // The distinction the raw prerequisite mask cannot make on its own.
            result.blockage = if (spec.prerequisites & ~self.reached_mask != 0)
                .prerequisites_unmet
            else
                .owner_silent;
        }
        if (self.frontier_reached) {
            if (self.stage(self.frontier_stage_id)) |spec| result.frontier_stage = spec.name;
            result.frontier_step = self.first_stage_step[@intCast(self.frontier_stage_id)];
        }
        result.last_work_unit = self.workUnitName();
        result.last_work_unit_owner = self.work_unit.ownerSlice();
        result.last_work_unit_step = self.work_unit.step;
        result.last_work_unit_thread = self.work_unit.thread;
        result.last_work_unit_rip = self.work_unit.rip;
        result.work_units_since_milestone = self.workUnitsSinceMilestone();
        result.quiet_steps = step -| self.lastNamedProgressStep();
        result.quiet_budget_steps = contract.quiet_budget_steps;
        result.external_progress_advances = self.external_progress_advances;
        result.external_progress_step = self.externalProgressStep();
        result.external_translation_generation = self.external_progress.translation_generation;
        result.activation_steps = step -| self.activation_start_step;
        result.activation_budget_steps = contract.activation_budget_steps;
        result.hot_site = self.hottestSite();
        result.distinct_sites = self.distinctSites();
        result.stall_samples = self.stall_samples;
        result.spin_verdict = self.spinVerdict(step);
        result.stall_evictions = self.stall_site_evictions;
        result.attributed_phase = self.attributedPhaseLabel();
        result.attributed_owner = self.attributedOwner();
        result.attributed_last_phase = self.attributedLastPhaseLabel();
        result.attributed_last_owner = self.attributedLastOwner();
        result.attributed_symbols = self.attributed_symbol_count;
        result.attributed_credits = self.attributed_credits;
        result.milestone_thread = self.milestone_thread;
        result.current_thread = self.last_thread;
        result.thread_changed = self.milestone_thread != 0 and
            self.milestone_thread != self.last_thread;
        result.failure = self.failure.kind;
        if (self.costliestStage()) |spec| {
            result.costliest_stage = spec.name;
            result.costliest_stage_steps = self.stageDuration(spec.id);
            if (contract.activation_budget_steps != 0) {
                result.costliest_stage_percent =
                    (result.costliest_stage_steps *| 100) / contract.activation_budget_steps;
            }
        }
        return result;
    }

    /// True once when a contract edge has been quiet past its budget while
    /// named work is still advancing.
    ///
    /// This is a notice, not a verdict. The run must continue: the previous
    /// behaviour stopped healthy startups whose only fault was taking longer
    /// than one budget between two coarse milestones. The notice is
    /// rate-limited to one per work-unit advance so a long stage leaves a
    /// readable trail instead of a heartbeat-rate flood.
    pub fn takeSlowProgressNotice(self: *Runtime, step: u64) bool {
        const contract = self.contract orelse return false;
        if (self.phase != .activation) return false;
        if (contract.quiet_budget_steps == 0) return false;
        if (step -| self.last_milestone_step < contract.quiet_budget_steps) return false;
        if (self.classifyProgress(step) != .work_advancing) return false;
        if (self.slow_progress_notified_at == self.work_unit_count) return false;
        self.slow_progress_notified_at = self.work_unit_count;
        self.slow_progress_reports +|= 1;
        return true;
    }

    pub fn evaluate(self: *Runtime, step: u64) types.Evaluation {
        if (!self.enabled()) return .ready;
        if (self.phase == .failed) return .failed;
        if (self.phase == .ready) return .ready;
        if (self.phase == .compile) return .waiting;

        if (self.requiredStagesReached()) {
            self.phase = .ready;
            return .ready;
        }

        const contract = self.contract orelse return .waiting;
        const missing = self.firstMissingRequired();
        if (contract.activation_budget_steps != 0 and
            step -| self.activation_start_step >= contract.activation_budget_steps)
        {
            if (self.classifyProgress(step) == .work_advancing) {
                // The total budget is a hard stop, so this still fails. The
                // kind matters: named work was advancing right up to the
                // limit, which accuses the budget rather than the guest.
                self.fail(.{
                    .kind = .slow_named_progress,
                    .stage = if (missing) |spec| spec.name else "",
                    .reason = "activation exhausted its total instruction budget while named startup work was still advancing; raise the budget rather than reading this as a hang",
                    .expected = if (missing) |spec| spec.name else "all required stages",
                    .observed = self.workUnitName(),
                    .step = step,
                    .rip = self.last_rip,
                    .thread = self.last_thread,
                });
            } else if (self.function_count != 0 and !self.anyFunctionEntered()) {
                self.fail(.{
                    .kind = .compiled_but_never_entered,
                    .stage = if (missing) |spec| spec.name else "",
                    .reason = "runtime compilation evidence exists, but no compiled function reached an activation boundary",
                    .expected = "at least one installed function entered during activation",
                    .observed = "no function entry",
                    .step = step,
                    .rip = self.last_rip,
                    .thread = self.last_thread,
                });
            } else {
                self.fail(.{
                    .kind = .activation_budget_exhausted,
                    .stage = if (missing) |spec| spec.name else "",
                    .reason = "activation did not reach the complete startup contract within its instruction budget",
                    .expected = if (missing) |spec| spec.name else "all required stages",
                    .observed = if (self.last_source.len != 0) self.last_source else "no later milestone",
                    .step = step,
                    .rip = self.last_rip,
                    .thread = self.last_thread,
                });
            }
            return .failed;
        }

        // The quiet window is measured from the most recent *named* progress,
        // not from the last contract edge.
        //
        // A subsystem that keeps reporting what it is doing is making progress
        // by definition. Measuring from the coarse edge alone is what made a
        // long-but-healthy startup step — a module load, an import table walk,
        // an image hash — indistinguishable from a hang, and stopped runs that
        // were still moving forward.
        if (contract.quiet_budget_steps != 0 and
            step -| self.lastNamedProgressStep() >= contract.quiet_budget_steps)
        {
            if (self.pendingWaitIsCurrent()) {
                self.fail(.{
                    .kind = .wait_unsignaled,
                    .stage = if (missing) |spec| spec.name else "",
                    .reason = "activation is waiting on an object that has not been signaled",
                    .expected = "wait object signaled or startup milestone reached",
                    .observed = "unsignaled wait",
                    .object = self.pending_wait_object,
                    .step = self.pending_wait_step,
                    .rip = self.last_rip,
                    .thread = self.last_thread,
                });
            } else switch (self.classifyProgress(step)) {
                // Execution never left one site. The hot instruction pointer
                // is the non-terminating loop, which is a far stronger lead
                // than "something did not finish".
                .spinning => self.fail(.{
                    .kind = .stalled_in_place,
                    .stage = if (missing) |spec| spec.name else "",
                    .reason = "execution retired instructions without ever leaving one instruction-pointer site",
                    .expected = if (missing) |spec| spec.name else "next required milestone",
                    .observed = "single-site spin",
                    .step = step,
                    .rip = self.hottestSite().rip,
                    .thread = self.last_thread,
                }),
                .frozen => self.fail(.{
                    .kind = .entered_but_no_progress,
                    .stage = if (missing) |spec| spec.name else "",
                    .reason = "no execution witness advanced after the last startup milestone",
                    .expected = if (missing) |spec| spec.name else "next required milestone",
                    .observed = "no execution witness",
                    .step = step,
                    .rip = self.last_rip,
                    .thread = self.last_thread,
                }),
                // Instructions retired across many sites, but nothing named
                // them. The gate is blind here rather than the guest stuck, and
                // the report says so instead of asserting a hang.
                .executing_only => self.fail(.{
                    .kind = .entered_but_no_progress,
                    .stage = if (missing) |spec| spec.name else "",
                    .reason = "instructions continued across many sites after the last startup milestone with no named work reported by the stage owner",
                    .expected = if (missing) |spec| spec.name else "next required milestone",
                    .observed = if (self.last_source.len != 0) self.last_source else "unnamed execution",
                    .step = step,
                    .rip = self.last_rip,
                    .thread = self.last_thread,
                }),
                // Named work is still advancing, so the window has not really
                // gone quiet and there is nothing to report here.
                //
                // `external_advancing` joins them and is in practice
                // unreachable: `lastNamedProgressStep` folds the same axis into
                // the guard above, so a fresh host-serviced counter keeps the
                // window open before the classification is ever consulted. It
                // is listed rather than merged into an `else` so that adding a
                // class later is a build error here instead of a silent pass.
                .milestone_advancing, .work_advancing, .external_advancing, .unknown => {},
            }
            return if (self.phase == .failed) .failed else .waiting;
        }
        return .waiting;
    }

    /// The contract read as an ordered block sequence, the way a build graph
    /// reads as "module N of M". Counting required and optional edges apart
    /// matters: an optional edge that never arrives is not a shortfall, and
    /// folding the two together would understate how far startup actually got.
    pub const Progress = struct {
        reached: usize = 0,
        total: usize = 0,
        required_reached: usize = 0,
        required_total: usize = 0,
        /// Position of the next required block in contract order, or
        /// `required_total` once every required block is reached.
        current_block: usize = 0,
    };

    pub fn contractProgress(self: *const Runtime) Progress {
        var result = Progress{};
        const contract = self.contract orelse return result;
        var found_current = false;
        for (contract.stages) |spec| {
            result.total += 1;
            const reached = if (stageBit(spec.id)) |bit| self.reached_mask & bit != 0 else false;
            if (reached) result.reached += 1;
            if (!spec.required) continue;
            result.required_total += 1;
            if (reached) {
                result.required_reached += 1;
                // A block reached after a gap still counts as done, but it does
                // not advance the frontier: the current block stays the first
                // one that is missing.
                if (!found_current) result.current_block += 1;
            } else if (!found_current) {
                found_current = true;
            }
        }
        return result;
    }

    pub fn requiredStagesReached(self: *const Runtime) bool {
        const contract = self.contract orelse return false;
        for (contract.stages) |spec| {
            if (!spec.required) continue;
            const bit = stageBit(spec.id) orelse return false;
            if (self.reached_mask & bit == 0) return false;
        }
        return true;
    }

    pub fn firstMissingRequired(self: *const Runtime) ?types.StageSpec {
        const contract = self.contract orelse return null;
        for (contract.stages) |spec| {
            if (!spec.required) continue;
            const bit = stageBit(spec.id) orelse continue;
            if (self.reached_mask & bit == 0) return spec;
        }
        return null;
    }

    pub fn anyFunctionEntered(self: *const Runtime) bool {
        for (self.functions[0..self.function_count]) |function| {
            if (function.entered_step != 0) return true;
        }
        return false;
    }

    pub fn stage(self: *const Runtime, id: u8) ?types.StageSpec {
        const contract = self.contract orelse return null;
        for (contract.stages) |spec| {
            if (spec.id == id) return spec;
        }
        return null;
    }

    pub fn findFunction(self: *const Runtime, address: u64) ?usize {
        for (self.functions[0..self.function_count], 0..) |function, index| {
            if (function.address == address) return index;
        }
        return null;
    }

    fn fail(self: *Runtime, failure: types.Failure) void {
        if (self.failure.kind != .none) return;
        self.failure = failure;
        self.phase = .failed;
    }

    fn stageBit(id: u8) ?u64 {
        if (id >= 64) return null;
        return @as(u64, 1) << @as(u6, @intCast(id));
    }
};

test "compile evidence does not imply activation readiness" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry", .description = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1), .description = "frame" },
    };
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages, .activation_budget_steps = 10 }, true);
    runtime.noteCompileCheck("decoder", true, "decoder audit passed");
    try std.testing.expect(runtime.sealCompile(1));
    try std.testing.expectEqual(types.Phase.activation, runtime.phase);
    try std.testing.expectEqual(types.Evaluation.waiting, runtime.evaluate(5));
    try std.testing.expectEqual(types.FailureKind.none, runtime.failure.kind);
}

test "ordering violation becomes the first typed failure" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages }, true);
    runtime.noteCompileCheck("image", true, "mapped");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(!runtime.noteStage(1, 2, "frame observed"));
    try std.testing.expectEqual(types.FailureKind.ordering_violation, runtime.failure.kind);
    try std.testing.expectEqualStrings("frame", runtime.failure.stage);
}

test "compiled functions distinguish never entered from an activation timeout" {
    const stages = [_]types.StageSpec{.{ .id = 0, .name = "entry" }};
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages, .activation_budget_steps = 4 }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    runtime.noteCompiled(0x1000, 1);
    runtime.noteInstalled(0x1000, 2);
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(4));
    try std.testing.expectEqual(types.FailureKind.compiled_but_never_entered, runtime.failure.kind);
}

test "label failures are promoted to a compiler failure" {
    const stages = [_]types.StageSpec{.{ .id = 0, .name = "entry" }};
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages }, true);
    runtime.observeCompilerText("undefined label:11", 7, 0x2000, 3);
    try std.testing.expectEqual(types.FailureKind.label_reference_unbound, runtime.failure.kind);
    try std.testing.expectEqualStrings("undefined label:11", runtime.failure.reason);
}

test "compiler evidence continues to be counted after the first failure" {
    const stages = [_]types.StageSpec{.{ .id = 0, .name = "entry" }};
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages }, true);
    runtime.observeCompilerText("undefined label:11", 7, 0x2000, 3);
    runtime.observeCompilerText("Xbyak error code=9: label is redefined", 8, 0x2001, 3);
    try std.testing.expectEqual(@as(u64, 2), runtime.compiler_diagnostic_count);
    try std.testing.expectEqual(types.FailureKind.label_reference_unbound, runtime.failure.kind);
    try std.testing.expectEqualStrings("undefined label:11", runtime.failure.reason);
}

test "quiet activation timeout identifies an unsignaled wait" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages, .activation_budget_steps = 100, .quiet_budget_steps = 4 }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    runtime.noteWait(0x88, false, 2);
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(5));
    try std.testing.expectEqual(types.FailureKind.wait_unsignaled, runtime.failure.kind);
    try std.testing.expectEqual(@as(u64, 0x88), runtime.failure.object);
}

test "a timeout is stale after later startup progress" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages, .activation_budget_steps = 1000, .quiet_budget_steps = 4 }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // The timeout returned at step 2. A later worker then made named progress;
    // the old result must remain diagnostic evidence without becoming the
    // reason the gate stops that worker's startup.
    runtime.noteWait(0x88, false, 2);
    runtime.noteWorkUnit("worker stage=translation", 20);
    runtime.noteExecutionSample(30, 0x1000, 0x11);
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(30));
    try std.testing.expectEqual(types.FailureKind.entered_but_no_progress, runtime.failure.kind);
    try std.testing.expectEqual(@as(u64, 0), runtime.failure.object);
}

test "named work keeps a slow startup step from being reported as a hang" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 1000,
        .quiet_budget_steps = 10,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // Without the work-unit axis this window is silent and the run dies.
    runtime.noteWorkUnit("Loader stage=ImportTable.begin", 15);
    try std.testing.expectEqual(types.Evaluation.waiting, runtime.evaluate(20));
    try std.testing.expectEqual(types.FailureKind.none, runtime.failure.kind);
    try std.testing.expectEqual(types.ProgressClass.work_advancing, runtime.classifyProgress(20));

    // The notice fires once per work-unit advance, not once per heartbeat.
    try std.testing.expect(runtime.takeSlowProgressNotice(20));
    try std.testing.expect(!runtime.takeSlowProgressNotice(21));
    runtime.noteWorkUnit("Loader stage=ImportTable.end", 22);
    try std.testing.expect(runtime.takeSlowProgressNotice(23));
    try std.testing.expectEqual(@as(u64, 2), runtime.slow_progress_reports);
}

test "a repeated breadcrumb is a loop and does not hold the quiet window open" {
    const stages = [_]types.StageSpec{.{ .id = 0, .name = "entry" }};
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 1000,
        .quiet_budget_steps = 10,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    runtime.noteWorkUnit("Retry stage=Attempt.begin", 5);
    // The same name arriving forever is a retry loop, not progress, so the
    // watermark must stay where it was.
    runtime.noteWorkUnit("Retry stage=Attempt.begin", 40);
    try std.testing.expectEqual(@as(u64, 5), runtime.work_unit.step);
    try std.testing.expectEqual(@as(u64, 1), runtime.work_unit_count);
}

test "a single-site spin is reported as a spin and names the hot site" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 1000,
        .quiet_budget_steps = 10,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    // A real loop covers a few addresses, not one, so the detector must not
    // require a single instruction pointer.
    const loop_body = [_]u64{ 0x4000, 0x4008, 0x400c };
    var sample: u64 = 0;
    while (sample < 30) : (sample += 1) {
        runtime.noteExecutionSample(2 + sample, loop_body[@intCast(sample % loop_body.len)], 0x11);
    }
    try std.testing.expect(runtime.spinning());
    try std.testing.expect(runtime.distinctSites() <= Runtime.max_spin_sites);
    try std.testing.expectEqual(types.ProgressClass.spinning, runtime.classifyProgress(200));
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(200));
    try std.testing.expectEqual(types.FailureKind.stalled_in_place, runtime.failure.kind);
}

test "broad execution without named work is not called a spin" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 1000,
        .quiet_budget_steps = 10,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    var sample: u64 = 0;
    while (sample < 60) : (sample += 1) {
        runtime.noteExecutionSample(2 + sample, 0x5000 + sample * 0x40, 0x11);
    }
    try std.testing.expect(!runtime.spinning());
    try std.testing.expectEqual(types.ProgressClass.executing_only, runtime.classifyProgress(200));
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(200));
    try std.testing.expectEqual(types.FailureKind.entered_but_no_progress, runtime.failure.kind);
    try std.testing.expect(runtime.distinctSites() > Runtime.max_spin_sites);
}

test "a stage reached with no execution witness at all is frozen" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 1000,
        .quiet_budget_steps = 10,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    try std.testing.expectEqual(types.ProgressClass.frozen, runtime.classifyProgress(20));
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(20));
    try std.testing.expectEqual(types.FailureKind.entered_but_no_progress, runtime.failure.kind);
    try std.testing.expectEqualStrings("no execution witness", runtime.failure.observed);
}

test "blockage separates an unmet prerequisite from a silent owner" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry", .owner = "rosette:loader" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1), .owner = "guest:title" },
    };
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages, .quiet_budget_steps = 10 }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // Every prerequisite of `frame` is satisfied, so the owner was entered and
    // did not report: the defect is inside it, not upstream.
    const silent = runtime.diagnose(20);
    try std.testing.expectEqual(types.BlockageClass.owner_silent, silent.blockage);
    try std.testing.expectEqualStrings("frame", silent.missing_stage);
    try std.testing.expectEqualStrings("guest:title", silent.missing_owner);
    try std.testing.expectEqualStrings("entry", silent.frontier_stage);
    try std.testing.expectEqual(@as(u64, 1), silent.frontier_step);

    const unmet_stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "optional", .required = false },
        .{ .id = 2, .name = "final", .prerequisites = @as(u64, 2), .owner = "xenia:kernel" },
    };
    var unmet = Runtime{};
    unmet.configure(.{ .name = "test", .stages = &unmet_stages, .quiet_budget_steps = 10 }, true);
    unmet.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(unmet.sealCompile(0));
    try std.testing.expect(unmet.noteStage(0, 1, "entry observed"));
    const blocked = unmet.diagnose(20);
    try std.testing.expectEqual(types.BlockageClass.prerequisites_unmet, blocked.blockage);
    try std.testing.expectEqualStrings("final", blocked.missing_stage);
}

test "optional evidence may arrive before its prerequisite without stopping" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "guest_output", .prerequisites = @as(u64, 1) },
        .{ .id = 2, .name = "host_present", .required = false, .prerequisites = @as(u64, 2) },
    };
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));

    // A diagnostic clear can be presented while the guest output edge is still
    // absent. It is useful evidence, but it is not an invalid application
    // order and must not become the first failure.
    try std.testing.expect(runtime.noteStage(2, 1, "host diagnostic present"));
    try std.testing.expectEqual(types.FailureKind.none, runtime.failure.kind);
    try std.testing.expectEqual(@as(u64, 0), runtime.last_milestone_step);

    try std.testing.expect(runtime.noteStage(0, 2, "entry observed"));
    try std.testing.expect(runtime.noteStage(1, 3, "guest output observed"));
    try std.testing.expectEqual(@as(u64, 3), runtime.last_milestone_step);
}

test "work units are recognized by shape, not by one guest's vocabulary" {
    try std.testing.expectEqualStrings(
        "XexModule::LoadContinue stage=ScanCodeRanges.end",
        Runtime.workUnitFromText(
            "[xenia] i> [DEBUG] XexModule::LoadContinue stage=ScanCodeRanges.end descriptors=298",
        ) orelse return error.TestUnexpectedResult,
    );
    try std.testing.expectEqualStrings(
        "KernelState::SetExecutableModule step=TLS.begin",
        Runtime.workUnitFromText("[xenia] i> KernelState::SetExecutableModule step=TLS.begin") orelse
            return error.TestUnexpectedResult,
    );
    // A counter is not a name; accepting it would make every heartbeat look
    // like fresh progress and disarm the quiet window entirely.
    // Guest text arrives with its terminator attached; the name must stop at
    // it rather than folding a newline into a log line.
    try std.testing.expectEqualStrings(
        "KernelState::SetExecutableModule step=TLS.end",
        Runtime.workUnitFromText("[xenia] i> KernelState::SetExecutableModule step=TLS.end\n") orelse
            return error.TestUnexpectedResult,
    );
    try std.testing.expect(Runtime.workUnitFromText("milestone step=83489913 rip=0x1") == null);
    // A key must start a token, or `first_step=` matches `step=`.
    try std.testing.expect(Runtime.workUnitFromText("report first_step=alpha") == null);
    try std.testing.expect(Runtime.workUnitFromText("section=1/12 nothing here") == null);
}

test "guest text feeds the work-unit axis through the existing boundary" {
    const stages = [_]types.StageSpec{.{ .id = 0, .name = "entry" }};
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 1000,
        .quiet_budget_steps = 10,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    runtime.observeCompilerText(
        "[xenia] i> [DEBUG] XexModule::LoadContinue stage=ImportTable.end libraries=2",
        30,
        0x1000,
        0x11,
    );
    try std.testing.expectEqual(@as(u64, 1), runtime.work_unit_count);
    try std.testing.expectEqual(@as(u64, 30), runtime.work_unit.step);
    try std.testing.expectEqualStrings(
        "XexModule::LoadContinue stage=ImportTable.end",
        runtime.workUnitName(),
    );
    // The compiler recognizer must still see the same text.
    try std.testing.expectEqual(types.FailureKind.none, runtime.failure.kind);
}

test "exhausting the total budget while work advances accuses the budget" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 50,
        .quiet_budget_steps = 10,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    runtime.noteWorkUnit("Loader stage=Hash.begin", 45);
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(50));
    try std.testing.expectEqual(types.FailureKind.slow_named_progress, runtime.failure.kind);
    try std.testing.expectEqualStrings("Loader stage=Hash.begin", runtime.failure.observed);
}

test "an unlimited activation waits for the terminal contract instead of a step cap" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "authentic_native_presented", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 0,
        .quiet_budget_steps = 0,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    try std.testing.expect(runtime.activationBudgetUnlimited());
    try std.testing.expectEqualStrings("unlimited", runtime.activationBudgetMode());
    try std.testing.expectEqual(types.Evaluation.waiting, runtime.evaluate(50_000_000_000));
    try std.testing.expectEqual(types.FailureKind.none, runtime.failure.kind);

    try std.testing.expect(runtime.noteStage(1, 50_000_000_001, "authentic native presentation"));
    try std.testing.expectEqual(types.Evaluation.ready, runtime.evaluate(50_000_000_001));
    try std.testing.expect(runtime.terminal());
    try std.testing.expect(!runtime.noteStage(0, 50_000_000_002, "post-terminal duplicate"));
}

test "stage durations expose a stage that is merely slow" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 10, "entry observed"));
    try std.testing.expect(runtime.noteStage(1, 400, "frame observed"));
    try std.testing.expectEqual(@as(u64, 10), runtime.stage_duration[0]);
    try std.testing.expectEqual(@as(u64, 390), runtime.stage_duration[1]);
}

test "reaching a stage clears the previous window's site evidence" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages, .quiet_budget_steps = 10 }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    var sample: u64 = 0;
    while (sample < 30) : (sample += 1) {
        runtime.noteExecutionSample(2 + sample, 0x4000, 0x11);
    }
    try std.testing.expect(runtime.spinning());
    // The next window must describe the next stage, not inherit this one's.
    try std.testing.expect(runtime.noteStage(1, 40, "frame observed"));
    try std.testing.expect(!runtime.spinning());
    try std.testing.expectEqual(@as(usize, 0), runtime.distinctSites());

    // Named progress restarts the quiet budget, so it must restart the sample
    // table too, or a spin beginning after a long healthy stage would hide
    // behind that stage's own wide spread of sites.
    sample = 0;
    while (sample < 30) : (sample += 1) {
        runtime.noteExecutionSample(41 + sample, 0x8000, 0x11);
    }
    try std.testing.expect(runtime.spinning());
    runtime.noteWorkUnit("owner stage=Next.begin", 80);
    try std.testing.expect(!runtime.spinning());
    try std.testing.expectEqual(@as(usize, 0), runtime.distinctSites());
}

test "the work-unit trail keeps the approach, not only the last step" {
    const stages = [_]types.StageSpec{.{ .id = 0, .name = "entry" }};
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));

    var index: u64 = 0;
    while (index < 3) : (index += 1) {
        var name_buffer: [16]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buffer, "s stage=w{d}", .{index}) catch unreachable;
        runtime.noteWorkUnit(name, 10 + index);
    }
    try std.testing.expectEqualStrings("s stage=w0", runtime.workUnitHistoryAt(0).slice());
    try std.testing.expectEqualStrings("s stage=w2", runtime.workUnitHistoryAt(2).slice());
    try std.testing.expectEqual(@as(usize, 0), runtime.workUnitHistoryAt(3).len);

    // Once the ring wraps, position zero must be the oldest retained entry,
    // not the start of the array.
    while (index < types.work_unit_history_len + 2) : (index += 1) {
        var name_buffer: [16]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buffer, "s stage=w{d}", .{index}) catch unreachable;
        runtime.noteWorkUnit(name, 10 + index);
    }
    try std.testing.expectEqualStrings("s stage=w2", runtime.workUnitHistoryAt(0).slice());
    try std.testing.expectEqualStrings(
        "s stage=w9",
        runtime.workUnitHistoryAt(types.work_unit_history_len - 1).slice(),
    );
}

test "contract progress reads as an ordered block sequence" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "a" },
        .{ .id = 1, .name = "b", .prerequisites = @as(u64, 1) },
        .{ .id = 2, .name = "advisory", .required = false },
        .{ .id = 3, .name = "c", .prerequisites = @as(u64, 2) },
    };
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "a"));
    try std.testing.expect(runtime.noteStage(1, 2, "b"));

    const progress = runtime.contractProgress();
    // The advisory edge is not a shortfall, so it is counted apart.
    try std.testing.expectEqual(@as(usize, 3), progress.required_total);
    try std.testing.expectEqual(@as(usize, 2), progress.required_reached);
    try std.testing.expectEqual(@as(usize, 4), progress.total);
    try std.testing.expectEqual(@as(usize, 2), progress.reached);
    try std.testing.expectEqual(@as(usize, 2), progress.current_block);

    try std.testing.expect(runtime.noteStage(3, 3, "c"));
    const complete = runtime.contractProgress();
    try std.testing.expectEqual(@as(usize, 3), complete.required_reached);
    try std.testing.expectEqual(@as(usize, 3), complete.current_block);
}

test "guidance never tells a stopped run that nothing needs investigation" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 100,
        .quiet_budget_steps = 90,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 20, "entry observed"));

    // Inside the quiet grace period, but the total budget is gone. The old
    // guidance keyed only on the progress class and answered "no investigation
    // is required" on a run that had just been stopped.
    try std.testing.expectEqual(types.ProgressClass.milestone_advancing, runtime.classifyProgress(100));
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(100));
    try std.testing.expectEqual(types.FailureKind.activation_budget_exhausted, runtime.failure.kind);

    const diagnosis = runtime.diagnose(100);
    try std.testing.expectEqual(types.FailureKind.activation_budget_exhausted, diagnosis.failure);
    try std.testing.expect(std.mem.indexOf(u8, diagnosis.guidance(), "no investigation") == null);
    try std.testing.expect(std.mem.indexOf(u8, diagnosis.guidance(), "activation_budget_steps") != null);
}

test "an exhausted budget names the stage that consumed it" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "cheap" },
        .{ .id = 1, .name = "expensive", .prerequisites = @as(u64, 1) },
        .{ .id = 2, .name = "final", .prerequisites = @as(u64, 2) },
    };
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 1000,
        .quiet_budget_steps = 900,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 50, "cheap"));
    try std.testing.expect(runtime.noteStage(1, 650, "expensive"));

    const diagnosis = runtime.diagnose(1000);
    try std.testing.expectEqualStrings("expensive", diagnosis.costliest_stage);
    try std.testing.expectEqual(@as(u64, 600), diagnosis.costliest_stage_steps);
    // Sixty percent of the whole allowance went to one stage: that, not the
    // missing edge, is what the reader has to act on.
    try std.testing.expectEqual(@as(u64, 60), diagnosis.costliest_stage_percent);
}

test "a parked consumer is separated from a busy producer" {
    const stages = [_]types.StageSpec{
        .{ .id = 0, .name = "entry" },
        .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1) },
    };
    var runtime = Runtime{};
    runtime.configure(.{
        .name = "test",
        .stages = &stages,
        .activation_budget_steps = 100_000,
        .quiet_budget_steps = 10,
    }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // One thread parked on a single address, one walking new code. The
    // aggregate table sees a wide spread and calls the process healthy; only
    // the per-thread view shows the parked consumer.
    var sample: u64 = 0;
    while (sample < 40) : (sample += 1) {
        runtime.noteExecutionSample(2 + sample * 2, 0xa000, 0x7fff2000);
        runtime.noteExecutionSample(3 + sample * 2, 0xb000 + sample * 0x30, 0xfffff900);
    }
    try std.testing.expect(!runtime.spinning());

    const parked = runtime.mostParkedThread();
    try std.testing.expectEqual(@as(u64, 0x7fff2000), parked.thread);
    try std.testing.expectEqual(@as(u64, 40), parked.samples);
    try std.testing.expectEqual(@as(u64, 0), parked.mobilityPercent());
    try std.testing.expect(parked.parked());

    for (runtime.stall_threads[0..runtime.stall_thread_count]) |entry| {
        if (entry.thread != 0xfffff900) continue;
        try std.testing.expect(!entry.parked());
        try std.testing.expect(entry.mobilityPercent() > 90);
    }
    try std.testing.expectEqual(@as(usize, 2), runtime.stall_thread_count);
}

test "sites are rankable so a report can lead with the one that matters" {
    const stages = [_]types.StageSpec{.{ .id = 0, .name = "entry" }};
    var runtime = Runtime{};
    runtime.configure(.{ .name = "test", .stages = &stages, .quiet_budget_steps = 1000 }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    try std.testing.expect(runtime.sealCompile(0));

    // One address sampled repeatedly, two sampled once each.
    var sample: u64 = 0;
    while (sample < 10) : (sample += 1) runtime.noteExecutionSample(10 + sample, 0xc000, 0x11);
    runtime.noteExecutionSample(30, 0xd000, 0x11);
    runtime.noteExecutionSample(31, 0xe000, 0x11);

    try std.testing.expectEqual(@as(u64, 0xc000), runtime.siteByRank(0).rip);
    try std.testing.expect(runtime.siteByRank(0).samples > runtime.siteByRank(1).samples);
    // Ranks past the occupied slots must terminate rather than repeat.
    try std.testing.expectEqual(@as(u64, 0), runtime.siteByRank(64).samples);
}

// --- Symbol-attributed progress ------------------------------------------
//
// The behaviour under test is the one that decides whether a long silent
// startup step reads as slow or as stuck, so each case below is a specific
// wrong answer the design has to keep giving correctly.

/// Contract shaped like the failing Xenia window: an edge is reached, the next
/// edge belongs to a subsystem that has not been entered yet, and the guest
/// keeps executing in between.
fn attributionFixture(runtime: *Runtime, stages: []const types.StageSpec) void {
    runtime.configure(.{ .name = "test", .stages = stages, .quiet_budget_steps = 100 }, true);
    runtime.noteCompileCheck("codegen", true, "installed");
    _ = runtime.sealCompile(0);
}

const attribution_stages = [_]types.StageSpec{
    .{ .id = 0, .name = "entry", .owner = "rosette:loader" },
    .{ .id = 1, .name = "frame", .prerequisites = @as(u64, 1), .owner = "guest:title" },
};

test "reaching new code inside a silent subsystem is progress" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // Without attribution this window is exactly the failing run: instructions
    // retire across many sites and no owner reports anything.
    var sample: u64 = 0;
    while (sample < 40) : (sample += 1) {
        runtime.noteExecutionSample(2 + sample, 0x5000 + sample * 0x40, 0x11);
    }
    try std.testing.expectEqual(types.ProgressClass.executing_only, runtime.classifyProgress(500));

    // One attributed symbol from the milestone thread is enough to name it.
    try std.testing.expect(runtime.noteAttributedSite(
        .{
            .phase_id = 7,
            .label = "xe::kernel::util::GameInfoDatabase phase=title-metadata",
            .owner = "xenia:xam",
            .after_stage = "entry",
        },
        "__ZN2xe6kernel4util16GameInfoDatabase12GetTitleNameE",
        520,
        0x5000,
        0x11,
    ));
    try std.testing.expectEqual(types.ProgressClass.work_advancing, runtime.classifyProgress(560));
    try std.testing.expectEqual(types.Evaluation.waiting, runtime.evaluate(560));
    try std.testing.expectEqualStrings("xenia:xam", runtime.attributedOwner());
    const named = runtime.diagnose(560);
    try std.testing.expectEqualStrings("xenia:xam", named.attributed_owner);
    // The owner that owes the edge and the owner that was running are
    // different facts, and the report has to keep them apart.
    try std.testing.expectEqualStrings("guest:title", named.missing_owner);
}

// The shape of the run that motivated the owner arm of the thread gate: a
// burst of startup edges lands, the contract then waits a long time on one
// owner, and that owner does its work on a thread no milestone ever came from.
const blocked_owner_stages = [_]types.StageSpec{
    .{ .id = 0, .name = "entry", .owner = "rosette:loader" },
    .{ .id = 1, .name = "processor_ready", .prerequisites = @as(u64, 1) << 0, .owner = "xenia:cpu" },
    .{ .id = 2, .name = "user_module_ready", .prerequisites = @as(u64, 1) << 1, .owner = "xenia:kernel_state" },
    .{ .id = 3, .name = "guest_main_ready", .prerequisites = @as(u64, 1) << 2, .owner = "xenia:kernel_state" },
    .{ .id = 4, .name = "surface_ready", .prerequisites = @as(u64, 1) << 3, .owner = "xenia:presenter" },
    .{ .id = 5, .name = "ring_buffer_ready", .prerequisites = @as(u64, 1) << 4, .owner = "guest:title" },
};

/// Drive the fixture to the exact state the failing run reported: the last
/// milestone came from the launch thread, and the frontier is `surface_ready`
/// while the contract waits on `guest:title`.
fn blockedOwnerFixture(runtime: *Runtime) !void {
    attributionFixture(runtime, &blocked_owner_stages);
    runtime.noteExecutionSample(1, 0x1000, 0xAA);
    try std.testing.expect(runtime.noteStage(0, 2, "entry"));
    try std.testing.expect(runtime.noteStage(1, 3, "processor ready"));
    try std.testing.expect(runtime.noteStage(2, 4, "user module ready"));
    try std.testing.expect(runtime.noteStage(3, 5, "guest main running"));
    try std.testing.expect(runtime.noteStage(4, 6, "surface acquired"));
    try std.testing.expectEqual(@as(u64, 0xAA), runtime.milestone_thread);
    try std.testing.expectEqualStrings("surface_ready", runtime.frontierStageName());
    try std.testing.expectEqualStrings("guest:title", (runtime.firstMissingRequired() orelse unreachable).owner);
}

/// The same contract stopped before guest main, with the frontier deliberately
/// past `processor_ready` so the frontier-equality arm cannot admit a
/// translation sample and the proxy arm is the only thing under test.
fn preGuestMainFixture(runtime: *Runtime) !void {
    attributionFixture(runtime, &blocked_owner_stages);
    runtime.noteExecutionSample(1, 0x1000, 0xAA);
    try std.testing.expect(runtime.noteStage(0, 2, "entry"));
    try std.testing.expect(runtime.noteStage(1, 3, "processor ready"));
    try std.testing.expect(runtime.noteStage(2, 4, "user module ready"));
    try std.testing.expectEqualStrings("user_module_ready", runtime.frontierStageName());
}

test "the blocked owner may report from a thread no milestone came from" {
    var runtime = Runtime{};
    try blockedOwnerFixture(&runtime);

    // A phase owned by the subsystem that owes the missing edge. Its own
    // prerequisite is two stages behind the frontier, which is the normal
    // case — a phase's prerequisite is what enabled it, not what follows it.
    const guest_export = types.SiteAttribution{
        .phase_id = 14,
        .label = "guest::title kernel-export phase=guest-execution",
        .owner = "guest:title",
        .after_stage = "guest_main_ready",
    };
    try std.testing.expect(runtime.noteAttributedSite(
        guest_export,
        "__ZN2xe6kernel8xboxkrnl17KeTlsAlloc_entryEv",
        50,
        0x7000,
        0xBB,
    ));
    try std.testing.expectEqual(@as(u64, 0), runtime.attributed_rejected_thread);
    try std.testing.expectEqualStrings("guest:title", runtime.attributedOwner());
}

test "a background subsystem still cannot speak for a blocked contract" {
    var runtime = Runtime{};
    try blockedOwnerFixture(&runtime);

    // Same off-milestone thread, same stale prerequisite — but owned by a
    // subsystem the contract is not waiting on. This is the busy worker the
    // gate exists to refuse, and relaxing the rule must not have admitted it.
    const metadata = types.SiteAttribution{
        .phase_id = 7,
        .label = "xe::kernel::util::GameInfoDatabase phase=title-metadata",
        .owner = "xenia:xam",
        .after_stage = "guest_main_ready",
    };
    try std.testing.expect(!runtime.noteAttributedSite(
        metadata,
        "__ZN2xe6kernel4util16GameInfoDatabase12GetTitleNameE",
        50,
        0x7000,
        0xBB,
    ));
    try std.testing.expectEqual(@as(u64, 1), runtime.attributed_rejected_thread);
    try std.testing.expectEqual(@as(u64, 0), runtime.attributed_credits);
}

test "a proxy owner speaks only after its own stage has landed" {
    // The translator's symbols are `xenia:cpu`, and after guest main starts the
    // only thing that makes them run is the title reaching new code. Before
    // guest main the same symbols are the emulator precompiling on its own
    // initiative and carry no claim on the title's progress.
    const translation = types.SiteAttribution{
        .phase_id = 13,
        .label = "xe::cpu::ppc::PPCTranslator phase=guest-translation",
        .owner = "xenia:cpu",
        .after_stage = "processor_ready",
        .proxy_owner = "guest:title",
        .proxy_after_stage = "guest_main_ready",
    };

    var early = Runtime{};
    try preGuestMainFixture(&early);
    // `guest_main_ready` has not landed, so the proxy is not yet a claim, and
    // `xenia:cpu` is neither the blocked owner nor the frontier's phase.
    try std.testing.expect(!early.noteAttributedSite(
        translation,
        "__ZN2xe5Arena5AllocEmm",
        10,
        0x8000,
        0xBB,
    ));
    try std.testing.expectEqual(@as(u64, 1), early.attributed_rejected_thread);

    var late = Runtime{};
    try blockedOwnerFixture(&late);
    try std.testing.expect(late.noteAttributedSite(
        translation,
        "__ZN2xe5Arena5AllocEmm",
        50,
        0x8000,
        0xBB,
    ));
    try std.testing.expectEqual(@as(u64, 1), late.attributed_credits);
}

test "a carrier inherits the proxy of the phase it joins" {
    var runtime = Runtime{};
    try blockedOwnerFixture(&runtime);
    const translation = types.SiteAttribution{
        .phase_id = 13,
        .label = "xe::cpu::ppc::PPCTranslator phase=guest-translation",
        .owner = "xenia:cpu",
        .after_stage = "processor_ready",
        .proxy_owner = "guest:title",
        .proxy_after_stage = "guest_main_ready",
    };
    try std.testing.expect(runtime.noteAttributedSite(translation, "__ZN2xe5Arena5AllocEmm", 50, 0x8000, 0xBB));

    // A libc++ helper called from inside that phase, on the same off-milestone
    // thread. Judged by its own empty owner it would be refused, and it is the
    // most common shape a real sample takes.
    const carrier = types.SiteAttribution{ .phase_id = 16, .label = "host::runtime phase=carrier", .carrier = true };
    try std.testing.expect(runtime.noteAttributedSite(
        carrier,
        "__ZNSt3__16vectorIhNS_9allocatorIhEEE6resizeEm",
        60,
        0x8100,
        0xBB,
    ));
    try std.testing.expectEqual(@as(u64, 2), runtime.attributed_credits);
}

test "the evidence budget still bounds a blocked owner" {
    // The owner arm removes a refusal, so the cap has to be the thing that
    // still ends a genuinely stuck run. A blocked owner that keeps reaching
    // new symbols gets exactly `max_attributed_symbols` credits and no more.
    var runtime = Runtime{};
    try blockedOwnerFixture(&runtime);
    const guest_export = types.SiteAttribution{
        .phase_id = 14,
        .label = "guest::title kernel-export phase=guest-execution",
        .owner = "guest:title",
        .after_stage = "guest_main_ready",
    };
    var index: usize = 0;
    while (index < types.max_attributed_symbols + 8) : (index += 1) {
        var name_buffer: [64]u8 = undefined;
        const symbol = std.fmt.bufPrint(name_buffer[0..], "__ZN2xe6kernel8xboxkrnl{d}_entryEv", .{index}) catch unreachable;
        _ = runtime.noteAttributedSite(guest_export, symbol, 50 + index, 0x8000 + index * 0x10, 0xBB);
    }
    try std.testing.expectEqual(@as(u64, types.max_attributed_symbols), runtime.attributed_credits);
    try std.testing.expect(runtime.attributed_symbols_dropped != 0);
}

test "a host-serviced counter keeps a silent but working guest alive" {
    // The failing run in one fixture: the contract stops reaching edges, no
    // subsystem narrates anything, and the guest keeps allocating. The gate
    // used to call that a stall while heap growth was still climbing.
    var runtime = Runtime{};
    try blockedOwnerFixture(&runtime);
    var counters = types.ExternalProgress{ .heap_high_water = 1000, .heap_live = 500 };
    runtime.noteExternalProgress(counters, 10);
    // The first sight of the counters is a baseline, never an advance.
    try std.testing.expectEqual(@as(u64, 0), runtime.external_progress_advances);

    var step: u64 = 20;
    while (step < 1000) : (step += 20) {
        counters.heap_high_water += 7;
        runtime.noteExternalProgress(counters, step);
        try std.testing.expectEqual(types.Evaluation.waiting, runtime.evaluate(step));
    }
    try std.testing.expect(runtime.external_progress_advances != 0);
    try std.testing.expectEqual(types.ProgressClass.external_advancing, runtime.classifyProgress(1000));
    try std.testing.expect(runtime.phase != .failed);
}

test "successful guest translation is monotonic external progress" {
    var runtime = Runtime{};
    try blockedOwnerFixture(&runtime);
    try std.testing.expect(runtime.noteTranslationProgress(8, 20));
    try std.testing.expectEqual(@as(u64, 1), runtime.external_progress_advances);
    try std.testing.expectEqual(@as(u64, 8), runtime.translationProgressGeneration());
    try std.testing.expect(!runtime.noteTranslationProgress(8, 30));
    try std.testing.expect(!runtime.noteTranslationProgress(7, 40));
    try std.testing.expect(runtime.noteTranslationProgress(16, 110));
    try std.testing.expectEqual(@as(u64, 2), runtime.external_progress_advances);
    try std.testing.expectEqual(types.ProgressClass.external_advancing, runtime.classifyProgress(110));

    // A later periodic snapshot must not erase the asynchronous generation.
    runtime.noteExternalProgress(.{ .heap_high_water = 100 }, 120);
    try std.testing.expectEqual(@as(u64, 16), runtime.translationProgressGeneration());
}

test "a guest that obtains nothing still fails on schedule" {
    // The property the axis must not destroy. Counters that stop advancing put
    // the quiet timer back in charge, and the run ends.
    var runtime = Runtime{};
    try blockedOwnerFixture(&runtime);
    const counters = types.ExternalProgress{ .heap_high_water = 1000 };
    runtime.noteExternalProgress(counters, 10);
    runtime.noteExternalProgress(.{ .heap_high_water = 1001 }, 20);
    try std.testing.expectEqual(@as(u64, 1), runtime.external_progress_advances);

    // Repeating the same values is not progress, however many times it arrives.
    var step: u64 = 30;
    while (step < 400) : (step += 10) {
        runtime.noteExternalProgress(.{ .heap_high_water = 1001 }, step);
        runtime.noteExecutionSample(step, 0x9000 + step, 0xBB);
    }
    try std.testing.expectEqual(@as(u64, 1), runtime.external_progress_advances);
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(400));
}

test "a counter that goes backwards is a reset, not progress" {
    var runtime = Runtime{};
    try blockedOwnerFixture(&runtime);
    runtime.noteExternalProgress(.{ .heap_high_water = 1000, .heap_live = 900 }, 10);
    runtime.noteExternalProgress(.{ .heap_high_water = 4, .heap_live = 2 }, 20);
    try std.testing.expectEqual(@as(u64, 0), runtime.external_progress_advances);
    // A single rising member is enough, even beside a falling one.
    runtime.noteExternalProgress(.{ .heap_high_water = 4, .heap_live = 5000 }, 30);
    try std.testing.expectEqual(@as(u64, 1), runtime.external_progress_advances);
}

test "revisiting known code is not progress" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    const symbol = "__ZN2xe6kernel3xam10XdbfHeaderC1Ev";
    const title = types.SiteAttribution{ .phase_id = 7, .label = "phase=title-metadata", .owner = "xenia:xam" };
    try std.testing.expect(runtime.noteAttributedSite(title, symbol, 10, 0x5000, 0x11));
    // The same function again is a loop, whatever the instruction pointer does
    // inside it. This is the property that keeps a genuinely stuck subsystem
    // from holding the quiet window open forever.
    try std.testing.expect(!runtime.noteAttributedSite(title, symbol, 200, 0x5004, 0x11));
    try std.testing.expectEqual(@as(u64, 1), runtime.attributed_credits);
}

test "a stuck subsystem exhausts its evidence and fails on schedule" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // Spend the whole credit budget on distinct symbols, then keep executing.
    var index: usize = 0;
    while (index < types.max_attributed_symbols + 8) : (index += 1) {
        var name_buffer: [32]u8 = undefined;
        const name = std.fmt.bufPrint(name_buffer[0..], "__ZN2xe6kernel3xamFn{d}Ev", .{index}) catch unreachable;
        _ = runtime.noteAttributedSite(
            .{ .phase_id = 7, .label = "phase=title-metadata", .owner = "xenia:xam" },
            name,
            10 + index,
            0x5000,
            0x11,
        );
    }
    try std.testing.expectEqual(@as(u64, types.max_attributed_symbols), runtime.attributed_credits);
    try std.testing.expect(runtime.attributed_symbols_dropped != 0);

    // Past the budget the window is quiet again and the gate stops the run,
    // which is the whole point: attribution buys evidence, not immunity.
    const quiet_step = runtime.lastNamedProgressStep() + 1000;
    runtime.noteExecutionSample(quiet_step, 0x9000, 0x11);
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(quiet_step));
    try std.testing.expectEqual(types.FailureKind.entered_but_no_progress, runtime.failure.kind);
}

test "a busy worker running old work cannot speak for the launch thread" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    // The milestone was reached on thread 0x11; 0x22 is a worker.
    runtime.noteExecutionSample(1, 0x4000, 0x11);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // Its phase depends on a stage from before the frontier, so it is work the
    // last milestone did not enable. A worker that has been busy all along is
    // exactly what a hung launch looks like from the outside.
    try std.testing.expect(!runtime.noteAttributedSite(
        .{
            .phase_id = 14,
            .label = "xe::ui::Presenter phase=presentation",
            .owner = "xenia:presenter",
            .after_stage = "",
        },
        "__ZN2xe2ui9Presenter18RefreshGuestOutputE",
        50,
        0x7000,
        0x22,
    ));
    try std.testing.expectEqual(@as(u64, 0), runtime.attributed_credits);
    try std.testing.expectEqual(@as(u64, 1), runtime.attributed_rejected_thread);
    try std.testing.expectEqualStrings("", runtime.attributedPhaseLabel());
}

test "the thread a milestone handed off to may speak for it" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    runtime.noteExecutionSample(1, 0x4000, 0x11);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // Startup hands work across threads constantly: shader storage is posted
    // to the command-processor thread, and guest main takes over entirely.
    // A phase whose prerequisite is the frontier itself is the work that
    // frontier just enabled, whichever thread picked it up.
    const handoff = types.SiteAttribution{
        .phase_id = 12,
        .label = "guest::title kernel-export phase=guest-execution",
        .owner = "guest:title",
        .after_stage = "entry",
    };
    try std.testing.expect(runtime.noteAttributedSite(handoff, "__ZN2xe6kernel8xboxkrnl12VdSwap_entryE", 50, 0x7000, 0x22));
    try std.testing.expectEqualStrings("guest:title", runtime.attributedOwner());
    try std.testing.expectEqual(@as(u64, 0), runtime.attributed_rejected_thread);

    // A carrier on that same thread continues the handed-off work rather than
    // being judged against a phase of its own.
    try std.testing.expect(runtime.noteAttributedSite(
        .{ .phase_id = 15, .label = "host::runtime phase=carrier", .carrier = true },
        "__ZNSt3__112__to_addressB7v160006IhEEPT_S2_",
        60,
        0x7004,
        0x22,
    ));
    try std.testing.expectEqual(@as(u64, 2), runtime.attributed_credits);
}

test "a carrier before any phase names nothing" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    // libc++ with no phase behind it. Guessing an owner here is how a report
    // ends up confidently accusing the wrong subsystem.
    try std.testing.expect(!runtime.noteAttributedSite(
        .{ .phase_id = 15, .label = "host::runtime phase=carrier", .carrier = true },
        "__ZNSt3__112__to_addressB7v160006IhEEPT_S2_",
        10,
        0x5000,
        0x11,
    ));
    try std.testing.expectEqualStrings("", runtime.attributedPhaseLabel());

    // With a phase established, the same carrier joins it and keeps its owner.
    try std.testing.expect(runtime.noteAttributedSite(
        .{
            .phase_id = 7,
            .label = "xe::kernel::util::GameInfoDatabase phase=title-metadata",
            .owner = "xenia:xam",
        },
        "__ZN2xe6kernel4util16GameInfoDatabase7GetIconEv",
        20,
        0x5000,
        0x11,
    ));
    try std.testing.expect(runtime.noteAttributedSite(
        .{ .phase_id = 15, .label = "host::runtime phase=carrier", .carrier = true },
        "__ZNSt3__112__to_addressB7v160006IhEEPT_S2_",
        30,
        0x5000,
        0x11,
    ));
    try std.testing.expectEqualStrings("xenia:xam", runtime.attributedOwner());
    try std.testing.expectEqual(@as(u64, 2), runtime.attributed_credits);
}

test "a contract edge restores the credit budget" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    const symbol = "__ZN2xe6kernel3xam11UserTracker20AddTitleToPlayedListEv";
    const profile = types.SiteAttribution{ .phase_id = 8, .label = "phase=user-profile", .owner = "xenia:xam" };
    try std.testing.expect(runtime.noteAttributedSite(profile, symbol, 10, 0x5000, 0x11));
    try std.testing.expect(!runtime.noteAttributedSite(profile, symbol, 20, 0x5000, 0x11));

    // The same parser either side of a milestone is doing different work, so
    // the window's evidence starts over rather than the run's.
    try std.testing.expect(runtime.noteStage(1, 30, "frame observed"));
    try std.testing.expectEqualStrings("", runtime.attributedPhaseLabel());
    try std.testing.expect(runtime.noteAttributedSite(profile, symbol, 40, 0x5000, 0x11));
    try std.testing.expectEqual(@as(u64, 2), runtime.attributed_credits);
}

test "a phase cannot be doing work its own prerequisite has not enabled" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    runtime.noteExecutionSample(1, 0x4000, 0x11);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // `frame` has not landed, so nothing that depends on it can be running.
    // Recording it anyway would let a live worker thread read as launch
    // progress, which is the mistake this rule exists to prevent.
    const premature = types.SiteAttribution{
        .phase_id = 11,
        .label = "phase=module-launch",
        .owner = "guest:title",
        .after_stage = "frame",
    };
    try std.testing.expect(!runtime.noteAttributedSite(premature, "__ZN2xe6kernel11KernelState12LaunchModuleE", 50, 0x5000, 0x11));
    try std.testing.expectEqual(@as(u64, 1), runtime.attributed_rejected_stage);
    try std.testing.expectEqualStrings("", runtime.attributedPhaseLabel());

    // Once the edge lands, the same evidence is admissible.
    try std.testing.expect(runtime.noteStage(1, 60, "frame observed"));
    try std.testing.expect(runtime.noteAttributedSite(premature, "__ZN2xe6kernel11KernelState12LaunchModuleE", 70, 0x5000, 0x11));
    try std.testing.expectEqualStrings("guest:title", runtime.attributedOwner());

    // A stage name the contract does not declare is a build-time problem, not
    // a runtime one; refusing it here as well would hide the build error.
    const unknown_stage = types.SiteAttribution{
        .phase_id = 12,
        .label = "phase=elsewhere",
        .owner = "guest:title",
        .after_stage = "no_such_stage",
    };
    try std.testing.expect(runtime.noteAttributedSite(unknown_stage, "__ZN2xe6kernel7ElsewhereEv", 80, 0x5000, 0x11));
}

test "phase churn cannot refill the evidence budget" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));

    // A loop that touches two subsystems in turn — reading a cvar and then the
    // game database — switches phase on every sample. If the switch reset the
    // evidence, this loop would credit progress forever and the gate could
    // never stop a run that had genuinely stopped.
    const config = types.SiteAttribution{ .phase_id = 6, .label = "phase=game-config", .owner = "xenia:config" };
    const database = types.SiteAttribution{ .phase_id = 7, .label = "phase=title-metadata", .owner = "xenia:xam" };
    var index: usize = 0;
    while (index < 200) : (index += 1) {
        _ = runtime.noteAttributedSite(config, "__ZN4cvar9ConfigVar9LoadValueEv", 10 + index * 2, 0x5000, 0x11);
        _ = runtime.noteAttributedSite(database, "__ZN2xe6kernel4util16GameInfoDatabase7GetIconEv", 11 + index * 2, 0x5004, 0x11);
    }
    // Two distinct (phase, symbol) pairs, so two credits from four hundred
    // samples.
    try std.testing.expectEqual(@as(u64, 2), runtime.attributed_credits);

    const quiet_step = runtime.lastNamedProgressStep() + 1000;
    runtime.noteExecutionSample(quiet_step, 0x9000, 0x11);
    try std.testing.expectEqual(types.Evaluation.failed, runtime.evaluate(quiet_step));
}

test "the same symbol in two phases is two pieces of evidence" {
    var runtime = Runtime{};
    attributionFixture(&runtime, &attribution_stages);
    try std.testing.expect(runtime.noteStage(0, 1, "entry observed"));
    // Reaching a shared helper from a second subsystem is new information
    // about that subsystem, so the set is keyed by both.
    const shared = "__ZN2xe11load_and_swapIjEET_PKv";
    try std.testing.expect(runtime.noteAttributedSite(
        .{ .phase_id = 6, .label = "phase=game-config", .owner = "xenia:config" },
        shared,
        10,
        0x5000,
        0x11,
    ));
    try std.testing.expect(runtime.noteAttributedSite(
        .{ .phase_id = 7, .label = "phase=title-metadata", .owner = "xenia:xam" },
        shared,
        20,
        0x5000,
        0x11,
    ));
    try std.testing.expectEqual(@as(u64, 2), runtime.attributed_credits);
}
