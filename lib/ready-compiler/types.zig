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
/// How many recent breadcrumbs the report keeps. The trail is what makes a
/// stall legible: the last name is a coordinate, the sequence is a route.
pub const work_unit_history_len: usize = 8;

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
    /// Zero means no instruction budget. A strict caller should normally set a
    /// finite value so a missing startup edge cannot consume the whole run.
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
    step: u64 = 0,

    pub fn slice(self: *const WorkUnit) []const u8 {
        return self.name[0..self.len];
    }

    pub fn set(self: *WorkUnit, text: []const u8, step: u64) void {
        const copied = @min(text.len, self.name.len);
        @memcpy(self.name[0..copied], text[0..copied]);
        self.len = copied;
        self.step = step;
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
    last_work_unit_step: u64 = 0,
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
    /// Whether the stalled thread is the one that produced the frontier.
    milestone_thread: u64 = 0,
    current_thread: u64 = 0,
    thread_changed: bool = false,

    /// The single sentence a reader needs to know where to look next. Derived
    /// only from recorded evidence, never from a guess about the guest.
    pub fn guidance(self: Diagnosis) []const u8 {
        return switch (self.progress) {
            .milestone_advancing => "startup is advancing; no investigation is required",
            .work_advancing => "the owning subsystem is still reporting named work, so this is a slow startup step and not a hang; raise the quiet budget rather than treating it as a defect",
            .executing_only => "the guest is executing across many sites without emitting named progress; add a work-unit breadcrumb inside the owning subsystem so the gate can see what it is doing",
            .spinning => "execution never left one site during the quiet window, so the hot site is the loop that is not terminating",
            .frozen => "no execution witness advanced; look for a wait that will never be signalled rather than for slow code",
            .unknown => "no activation evidence has been recorded yet",
        };
    }
};
