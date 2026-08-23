//! Public types for Rosette's runtime readiness gate.
//!
//! The gate intentionally has two different vocabularies:
//!
//! * compilation evidence says that an artifact was generated and installed;
//! * activation evidence says that the installed artifact was actually entered
//!   and carried the application through its required startup contract.
//!
//! A successful compiler call is therefore never allowed to imply a successful
//! launch.  All storage is bounded and the types borrow names from static
//! contracts or the loaded image; the runtime does not allocate on the hot
//! execution path.

pub const max_stages: usize = 64;
pub const max_functions: usize = 128;
pub const max_compile_checks: usize = 32;
/// Instruction-pointer sample table used to attribute a quiet window. The
/// table is direct-mapped so sampling stays O(1); only report generation is
/// allowed to walk it.
pub const max_stall_sites: usize = 32;
/// Work-unit names arrive as borrowed guest text whose lifetime is shorter
/// than the gate's, so they are copied into a bounded inline buffer.
pub const max_work_unit_name: usize = 96;
/// The owner is the stable producer token before `stage=`/`phase=` in a
/// breadcrumb (for example `XexModule::Precompile`). Keeping it separately
/// makes reports useful even when the full breadcrumb is truncated.
pub const max_work_unit_owner: usize = 64;
/// How many recent breadcrumbs the report keeps. The trail is what makes a
/// stall legible: the last name is a coordinate, the sequence is a route.
pub const work_unit_history_len: usize = 8;
/// How many threads a quiet window is attributed across. Startup only has a
/// handful of interesting threads, and the table is scanned linearly.
pub const max_stall_threads: usize = 8;
/// How many sample sites the report prints, hottest first. Printing every
/// occupied slot buries the one that matters under single-sample noise.
pub const reported_stall_sites: usize = 8;

pub const Phase = enum(u8) {
    disabled,
    compile,
    activation,
    ready,
    failed,
};

pub const CompileState = enum(u8) {
    undeclared,
    declared,
    compiling,
    compiled,
    installed,
    entered,
    failed,
};

pub const FailureKind = enum(u8) {
    none,
    compile_check_failed,
    compile_evidence_missing,
    label_reference_unbound,
    compiled_but_never_entered,
    entered_but_no_progress,
    /// Stronger than `entered_but_no_progress`: the quiet window expired and
    /// execution never left a single instruction-pointer site, so this is a
    /// spin rather than a long-running startup step.
    stalled_in_place,
    /// The quiet window expired while named sub-milestone work was still
    /// advancing. Reported so a slow startup step is never silently
    /// reclassified as a hang.
    slow_named_progress,
    wait_unsignaled,
    missing_milestone,
    ordering_violation,
    activation_budget_exhausted,
    unexpected_exit,

    pub fn label(self: FailureKind) []const u8 {
        return switch (self) {
            .none => "NONE",
            .compile_check_failed => "COMPILE_CHECK_FAILED",
            .compile_evidence_missing => "COMPILE_EVIDENCE_MISSING",
            .label_reference_unbound => "LABEL_REFERENCE_UNBOUND",
            .compiled_but_never_entered => "COMPILED_BUT_NEVER_ENTERED",
            .entered_but_no_progress => "ENTERED_BUT_NO_PROGRESS",
            .stalled_in_place => "STALLED_IN_PLACE",
            .slow_named_progress => "SLOW_NAMED_PROGRESS",
            .wait_unsignaled => "WAITING_ON_UNSIGNALED_OBJECT",
            .missing_milestone => "MISSING_MILESTONE",
            .ordering_violation => "ORDERING_VIOLATION",
            .activation_budget_exhausted => "ACTIVATION_BUDGET_EXHAUSTED",
            .unexpected_exit => "UNEXPECTED_EXIT",
        };
    }
};

/// One required or optional activation edge. `prerequisites` is a bit mask of
/// other stage ids, so the contract is a graph rather than a list of strings.
pub const StageSpec = struct {
    id: u8,
    name: []const u8,
    required: bool = true,
    prerequisites: u64 = 0,
    description: []const u8 = "",
    /// Who owes this edge. A blocked report that names the owner tells the
    /// reader whether the missing evidence is Rosette's to produce or the
    /// guest's, which is the difference between a host bug and a guest bug.
    owner: []const u8 = "",
};

pub const Contract = struct {
    name: []const u8,
    stages: []const StageSpec,
    /// Zero means no total activation limit. A finite value is retained for
    /// explicit diagnostic contracts, but the Xenia gameplay contract uses
    /// zero so a slow guest-owned startup edge is not mistaken for failure.
    activation_budget_steps: u64 = 0,
    /// Zero disables the quiet-window check. This is measured from the last
    /// semantic milestone, not from the last interpreter heartbeat.
    quiet_budget_steps: u64 = 0,
};

pub const CompileCheck = struct {
    name: []const u8 = "",
    passed: bool = false,
    detail: []const u8 = "",
};

pub const FunctionRecord = struct {
    address: u64 = 0,
    module: []const u8 = "",
    name: []const u8 = "",
    state: CompileState = .undeclared,
    compile_started_step: u64 = 0,
    compiled_step: u64 = 0,
    installed_step: u64 = 0,
    entered_step: u64 = 0,
    last_progress_step: u64 = 0,
    entry_thread: u64 = 0,
    caller: u64 = 0,
};

/// First failure wins. Later failures are normally consequences of the first
/// broken edge, and replacing it would make the report point downstream.
pub const Failure = struct {
    kind: FailureKind = .none,
    stage: []const u8 = "",
    function: []const u8 = "",
    reason: []const u8 = "",
    expected: []const u8 = "",
    observed: []const u8 = "",
    object: u64 = 0,
    step: u64 = 0,
    rip: u64 = 0,
    thread: u64 = 0,
    missing_prerequisites: u64 = 0,
};

pub const Evaluation = enum(u8) {
    waiting,
    ready,
    failed,
};

/// Why a required stage has not been reached. `missing_prerequisites == 0` on
/// a blocked stage is ambiguous on its own: it can mean the graph is satisfied
/// and the owner simply never reported. Naming that case is the difference
/// between "look upstream" and "look inside the owner".
pub const BlockageClass = enum(u8) {
    none,
    /// An upstream required edge has not been reached, so this stage could not
    /// legitimately have run yet. Investigate the upstream stage instead.
    prerequisites_unmet,
    /// Every prerequisite is satisfied. The subsystem that owes this edge was
    /// therefore entered and did not report, so the defect is inside it.
    owner_silent,

    pub fn label(self: BlockageClass) []const u8 {
        return switch (self) {
            .none => "NONE",
            .prerequisites_unmet => "PREREQUISITES_UNMET",
            .owner_silent => "OWNER_SILENT",
        };
    }
};

/// The gate watches three independent axes. Collapsing them is what makes a
/// slow-but-healthy startup step indistinguishable from a hang, so each is
/// classified separately and the strongest available evidence wins.
pub const ProgressClass = enum(u8) {
    /// Nothing has been observed yet.
    unknown,
    /// A contract edge advanced inside the quiet window: fully healthy.
    milestone_advancing,
    /// No contract edge, but named sub-milestone work advanced. The startup
    /// step is long, not stuck.
    work_advancing,
    /// Instructions retired across many sites with no named work at all. The
    /// guest is running; the gate simply cannot see what it is doing.
    executing_only,
    /// Instructions retired but never left one site. This is a spin.
    spinning,
    /// No execution witness advanced at all.
    frozen,

    pub fn label(self: ProgressClass) []const u8 {
        return switch (self) {
            .unknown => "UNKNOWN",
            .milestone_advancing => "MILESTONE_ADVANCING",
            .work_advancing => "WORK_ADVANCING",
            .executing_only => "EXECUTING_ONLY",
            .spinning => "SPINNING",
            .frozen => "FROZEN",
        };
    }

    /// Only a spin or a freeze is evidence of a defect. The other classes are
    /// forward motion and must never be reported as a hang.
    pub fn isStalled(self: ProgressClass) bool {
        return self == .spinning or self == .frozen;
    }
};

/// A concentrated instruction-pointer sample is not by itself a scheduling
/// defect. This classification requires the scheduler and wait graph to agree
/// that no producer can currently make progress and that the observed wait
/// predicate has remained unchanged for the whole quiet window.
pub const SpinVerdict = enum(u8) {
    not_concentrated,
    runnable_producer_present,
    predicate_unobserved,
    predicate_recently_changed,
    scheduling_starvation,

    pub fn label(self: SpinVerdict) []const u8 {
        return switch (self) {
            .not_concentrated => "NOT_CONCENTRATED",
            .runnable_producer_present => "UNPROVEN_RUNNABLE_PRODUCER",
            .predicate_unobserved => "UNPROVEN_NO_PREDICATE",
            .predicate_recently_changed => "UNPROVEN_PREDICATE_CHANGED",
            .scheduling_starvation => "CONFIRMED_SCHEDULING_STARVATION",
        };
    }
};

/// One instruction-pointer site observed during a quiet window. The sample
/// count is the finding: a single site holding every sample is a spin, while a
/// wide spread is ordinary forward execution.
pub const StallSite = struct {
    rip: u64 = 0,
    thread: u64 = 0,
    samples: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
};

/// A named sub-milestone breadcrumb: evidence that lives between two contract
/// edges. Without this axis the gate can only see contract edges, and a
/// startup step that legitimately takes hundreds of millions of instructions
/// looks exactly like a hang.
pub const WorkUnit = struct {
    name: [max_work_unit_name]u8 = [_]u8{0} ** max_work_unit_name,
    len: usize = 0,
    owner: [max_work_unit_owner]u8 = [_]u8{0} ** max_work_unit_owner,
    owner_len: usize = 0,
    step: u64 = 0,
    thread: u64 = 0,
    rip: u64 = 0,

    pub fn slice(self: *const WorkUnit) []const u8 {
        return self.name[0..self.len];
    }

    pub fn ownerSlice(self: *const WorkUnit) []const u8 {
        return self.owner[0..self.owner_len];
    }

    pub fn set(self: *WorkUnit, text: []const u8, step: u64) void {
        self.setAt(text, step, 0, 0);
    }

    pub fn setAt(self: *WorkUnit, text: []const u8, step: u64, thread: u64, rip: u64) void {
        const copied = @min(text.len, self.name.len);
        @memcpy(self.name[0..copied], text[0..copied]);
        self.len = copied;
        const owner_end = ownerEnd(text);
        const owner_copied = @min(owner_end, self.owner.len);
        @memcpy(self.owner[0..owner_copied], text[0..owner_copied]);
        self.owner_len = owner_copied;
        self.step = step;
        self.thread = thread;
        self.rip = rip;
    }

    pub fn matches(self: *const WorkUnit, text: []const u8) bool {
        const copied = @min(text.len, self.name.len);
        return self.len == copied and eql(self.name[0..self.len], text[0..copied]);
    }

    fn eql(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        for (a, b) |left, right| {
            if (left != right) return false;
        }
        return true;
    }

    fn ownerEnd(text: []const u8) usize {
        var index: usize = 0;
        while (index < text.len and text[index] > ' ') : (index += 1) {}
        return index;
    }
};

/// Everything the reporter needs to explain a blocked run in one place, so the
/// log line and the summary cannot drift apart.
pub const Diagnosis = struct {
    progress: ProgressClass = .unknown,
    blockage: BlockageClass = .none,
    /// The next required stage that has not been reached.
    missing_stage: []const u8 = "",
    missing_owner: []const u8 = "",
    missing_description: []const u8 = "",
    /// The last required stage that was reached, and when.
    frontier_stage: []const u8 = "",
    frontier_step: u64 = 0,
    /// Named sub-milestone evidence observed since that frontier.
    last_work_unit: []const u8 = "",
    last_work_unit_owner: []const u8 = "",
    last_work_unit_step: u64 = 0,
    last_work_unit_thread: u64 = 0,
    last_work_unit_rip: u64 = 0,
    work_units_since_milestone: u64 = 0,
    /// How long the gate has been without any named progress.
    quiet_steps: u64 = 0,
    quiet_budget_steps: u64 = 0,
    activation_steps: u64 = 0,
    activation_budget_steps: u64 = 0,
    /// Where the guest spent the quiet window.
    hot_site: StallSite = .{},
    distinct_sites: usize = 0,
    stall_samples: u64 = 0,
    spin_verdict: SpinVerdict = .not_concentrated,
    /// Whether the stalled thread is the one that produced the frontier.
    milestone_thread: u64 = 0,
    current_thread: u64 = 0,
    thread_changed: bool = false,
    /// The verdict this evidence belongs to. Guidance that ignores it can end
    /// up telling the reader no investigation is required on a run that was
    /// just stopped, which is worse than saying nothing.
    failure: FailureKind = .none,
    /// The stage that consumed the most steps, and how many. When a total
    /// budget runs out, the stage that ate it is the only actionable fact in
    /// the report.
    costliest_stage: []const u8 = "",
    costliest_stage_steps: u64 = 0,
    /// Fraction of the total activation budget that stage consumed, in
    /// percent. Zero when there is no finite budget to compare against.
    costliest_stage_percent: u64 = 0,
    /// How much of the sample table was lost to collisions. A high rate means
    /// the site attribution below is a sketch, not a measurement, and saying so
    /// is better than letting the reader over-trust it.
    stall_evictions: u64 = 0,

    /// The single sentence a reader needs to know where to look next.
    ///
    /// A terminal verdict outranks the progress class: inside a quiet grace
    /// period is a true statement about the window and a useless one about a
    /// run that has already been stopped.
    pub fn guidance(self: Diagnosis) []const u8 {
        switch (self.failure) {
            .activation_budget_exhausted, .slow_named_progress => return "the total activation budget ran out before the contract completed; the costliest stage below is where it went, so raise activation_budget_steps past that cost or make that stage cheaper before reading this as a guest defect",
            .compiled_but_never_entered => return "code was generated and installed but nothing ever entered it; look at the dispatch that should have called it, not at the generated code",
            .wait_unsignaled => return "activation is parked on an object nothing has signalled; find the code that should signal it and confirm that code ran",
            .ordering_violation => return "a stage arrived before its prerequisite, so the contract and the runtime disagree about startup order; fix whichever of the two is wrong before trusting any later stage",
            .label_reference_unbound, .compile_check_failed, .compile_evidence_missing => return "a compile-side prerequisite failed, so no activation evidence below is meaningful; fix the compiler diagnostic first",
            .stalled_in_place => return "execution stayed inside a handful of addresses for the whole quiet window, so the hot site is the loop that is not terminating",
            .missing_milestone => return "an event named a stage this contract does not declare; the observer and the contract are out of sync",
            .entered_but_no_progress, .unexpected_exit, .none => {},
        }
        return switch (self.progress) {
            .milestone_advancing => "a contract edge landed inside the quiet window, so nothing here accuses the guest",
            .work_advancing => "the owning subsystem is still reporting named work, so this is a slow startup step and not a hang; raise the quiet budget rather than treating it as a defect",
            .executing_only => "the guest is executing across many sites without emitting named progress; add a work-unit breadcrumb inside the owning subsystem so the gate can see what it is doing",
            .spinning => "execution never left one site during the quiet window, so the hot site is the loop that is not terminating",
            .frozen => "no execution witness advanced; look for a wait that will never be signalled rather than for slow code",
            .unknown => "no activation evidence has been recorded yet",
        };
    }
};

/// Per-thread view of a quiet window.
///
/// One instruction-pointer table cannot describe several threads doing
/// unrelated things: a starved consumer parked on one address and a busy
/// producer walking thousands average out into a shape that matches neither.
/// `rip_changes` against `samples` is the discriminator — near zero is parked,
/// near one is moving — and it costs one comparison per sample.
pub const ThreadSample = struct {
    thread: u64 = 0,
    samples: u64 = 0,
    rip_changes: u64 = 0,
    last_rip: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,

    /// Percent of samples that observed a different address than the previous
    /// one. Zero means the thread never moved.
    pub fn mobilityPercent(self: ThreadSample) u64 {
        if (self.samples <= 1) return 0;
        return (self.rip_changes *| 100) / (self.samples - 1);
    }

    /// A thread that never moved across a meaningful number of samples is
    /// parked, whatever the aggregate table says.
    pub fn parked(self: ThreadSample) bool {
        return self.samples >= 4 and self.rip_changes == 0;
    }
};
