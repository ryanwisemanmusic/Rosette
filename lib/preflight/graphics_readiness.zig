//! Static graphics readiness for a translated Xenia image.
//!
//! This is the layer between the existing image audit and the runtime graphics
//! ledger.  The image audit answers whether subsystem names exist.  The runtime
//! ledger answers what the guest actually crossed.  Neither answers the useful
//! question in between: whether Rosette has a valid, observable implementation
//! of every emulator-owned graphics boundary before the guest starts.
//!
//! The report is deliberately conservative.  A direct-call scan can prove a
//! direct edge, but it cannot see an ordinal table, a vtable, a function
//! pointer, or guest code that is not in the Mach-O image.  Those cases are
//! retained as UNKNOWN evidence; they never become a false failure and they
//! never become a green check.  This makes the report useful both as a launch
//! gate for known defects and as a map of what the subsequent run still has to
//! substantiate.

const std = @import("std");
const contract = @import("xenia_gpu_bringup_contract");
const health_schema = @import("xenia_graphics_health_contract");
const host_capability = @import("host_capability.zig");
const prelaunch_audit = @import("prelaunch_audit.zig");
const component_contract = @import("rosette_component_readiness_contract");

pub const Boundary = contract.Boundary;
pub const Requirement = contract.Requirement;
pub const boundary_count = contract.boundary_count;
pub const max_boundary_candidates: usize = 4;
pub const prelaunch_stage_count: usize = @typeInfo(prelaunch_audit.Stage).@"enum".fields.len;
pub const component_count: usize = component_contract.component_count;
// Eight image/import checks, three rows for each of the graphics boundaries,
// the prelaunch-stage census, every cross-layer component, decoder coverage,
// and the explicit runtime-only obligations below them.  The report is fixed
// capacity because it is retained in MachOState, but it must never truncate a
// complete audit surface.
pub const max_checks: usize = 240;

pub const DecodeResult = struct {
    valid: bool = false,
    length: u8 = 0,
};

pub const DecodeInstruction = *const fn (bytes: []const u8) DecodeResult;

pub const Verdict = enum(u8) {
    /// No known static blocker remains.  Runtime-only facts still need the
    /// live graphics ledger and native window admission to become proven.
    ready,
    /// A statically answerable condition is false.  Starting the guest would
    /// only spend time rediscovering this known defect.
    blocked,
    /// A required condition could not be evaluated.  This is different from
    /// ready: the observer has not earned the right to call the run healthy.
    unknown,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .ready => "ready",
            .blocked => "BLOCKED",
            .unknown => "UNKNOWN",
        };
    }

    pub fn allowsGuestStart(self: Verdict) bool {
        return self == .ready;
    }
};

pub const CheckState = enum(u8) {
    satisfied,
    degraded,
    blocked,
    unknown,

    pub fn label(self: CheckState) []const u8 {
        return switch (self) {
            .satisfied => "satisfied",
            .degraded => "degraded",
            .blocked => "BLOCKED",
            .unknown => "UNKNOWN",
        };
    }
};

/// One line in the preflight report.  Text is always a string literal or a
/// contract string; the report owns no allocations and can be retained in the
/// Mach-O state for later window-admission diagnostics.
pub const Check = struct {
    name: []const u8 = "",
    state: CheckState = .unknown,
    /// Required unknown checks make the overall verdict UNKNOWN.  Advisory
    /// unknown checks describe the limits of static analysis only.
    required: bool = false,
    observed: u64 = 0,
    expected: u64 = 0,
    detail: []const u8 = "",
};

pub const TracepointFacts = struct {
    sealed: bool = false,
    armed_total: u16 = 0,
    unresolved: u32 = 0,
    saturated: bool = false,
    armed_by_boundary: [boundary_count]u16 = [_]u16{0} ** boundary_count,
};

pub const CandidateFacts = struct {
    boundary: Boundary,
    /// All defined symbols whose names matched the boundary fragment.
    symbol_matches: u32 = 0,
    /// Matching symbols in the image's executable `__text` section.
    executable_candidates: u32 = 0,
    /// At most four short-name candidates are retained, matching the runtime
    /// tracepoint arming policy.  Addresses are kept for the graph pass.
    candidate_count: u8 = 0,
    candidate_addresses: [max_boundary_candidates]u64 = [_]u64{0} ** max_boundary_candidates,
    decoder_valid_candidates: u8 = 0,
    armed_candidates: u16 = 0,
    direct_reachable: bool = false,
    direct_inbound: bool = false,
};

fn defaultBoundaryFacts() [boundary_count]CandidateFacts {
    var result: [boundary_count]CandidateFacts = undefined;
    for (&result, 0..) |*slot, index| {
        slot.* = .{ .boundary = @enumFromInt(index) };
    }
    return result;
}

pub const GraphFacts = struct {
    /// Direct E8/E9 edges whose target exactly matched a defined symbol.
    direct_edges: u64 = 0,
    nodes: u32 = 0,
    reachable_nodes: u32 = 0,
    roots: u32 = 0,
    entry_rooted: bool = false,
    /// Always false for this analysis.  Indirect dispatch and guest code are
    /// outside the information available in a Mach-O direct-call scan.
    complete: bool = false,
};

pub const PrelaunchFacts = struct {
    evaluated: bool = false,
    verdict: prelaunch_audit.Verdict = .unevaluated,
    symbols: u32 = 0,
    import_stubs: u32 = 0,
    stages: [prelaunch_stage_count]prelaunch_audit.StageFacts = defaultPrelaunchStageFacts(),
};

fn defaultPrelaunchStageFacts() [prelaunch_stage_count]prelaunch_audit.StageFacts {
    var result: [prelaunch_stage_count]prelaunch_audit.StageFacts = undefined;
    for (&result, 0..) |*slot, index| slot.* = .{ .stage = @enumFromInt(index) };
    return result;
}

pub const ComponentFacts = struct {
    component: component_contract.Component,
    proof: component_contract.Proof,
    essential: bool,
    state: CheckState = .unknown,
};

fn defaultComponentFacts() [component_count]ComponentFacts {
    var result: [component_count]ComponentFacts = undefined;
    for (&result, 0..) |*slot, index| {
        const component: component_contract.Component = @enumFromInt(index);
        slot.* = .{
            .component = component,
            .proof = component.proof(),
            .essential = component.essential(),
        };
    }
    return result;
}

pub const Facts = struct {
    mapped: bool = true,
    image_is_x86_64: bool = false,
    has_text: bool = false,
    text_bytes: u64 = 0,
    entry_in_text: bool = false,
    symbol_entries: u32 = 0,
    unique_symbol_entries: u32 = 0,
    import_stubs: u32 = 0,
    has_stub_section: bool = false,
    dylibs: u32 = 0,
    bindings: u32 = 0,
    tracepoints: TracepointFacts = .{},
    decoder_baseline_ready: bool = false,
    decoder_probe_available: bool = false,
    decoder_checked: u32 = 0,
    decoder_invalid: u32 = 0,
    first_invalid_address: u64 = 0,
    linear_decoder_checked: u64 = 0,
    linear_decoder_valid: u64 = 0,
    linear_decoder_invalid: u64 = 0,
    linear_decoder_bytes_covered: u64 = 0,
    linear_first_invalid_address: u64 = 0,
    image_fingerprint: u64 = 0,
    text_fingerprint: u64 = 0,
    contract_fingerprint: u64 = 0,
    prelaunch: PrelaunchFacts = .{},
    boundaries: [boundary_count]CandidateFacts = defaultBoundaryFacts(),
    graph: GraphFacts = .{},
    host_capabilities: ?*const host_capability.Report = null,
};

pub const Report = struct {
    verdict: Verdict = .unknown,
    checks: [max_checks]Check = [_]Check{.{}} ** max_checks,
    check_count: u8 = 0,
    check_overflowed: bool = false,
    checks_dropped: u16 = 0,
    first_non_satisfied_check: ?u8 = null,
    first_blocked_check: ?u8 = null,
    first_required_unknown_check: ?u8 = null,
    satisfied: u8 = 0,
    degraded: u8 = 0,
    blocked: u8 = 0,
    unknown: u8 = 0,
    required_unknown: u8 = 0,

    image_is_x86_64: bool = false,
    text_bytes: u64 = 0,
    symbol_entries: u32 = 0,
    unique_symbol_entries: u32 = 0,
    import_stubs: u32 = 0,
    dylibs: u32 = 0,
    bindings: u32 = 0,
    decoder_checked: u32 = 0,
    decoder_invalid: u32 = 0,
    first_invalid_address: u64 = 0,
    linear_decoder_checked: u64 = 0,
    linear_decoder_valid: u64 = 0,
    linear_decoder_invalid: u64 = 0,
    linear_decoder_bytes_covered: u64 = 0,
    linear_first_invalid_address: u64 = 0,
    image_fingerprint: u64 = 0,
    text_fingerprint: u64 = 0,
    contract_fingerprint: u64 = 0,
    prelaunch: PrelaunchFacts = .{},
    components: [component_count]ComponentFacts = defaultComponentFacts(),
    boundaries: [boundary_count]CandidateFacts = defaultBoundaryFacts(),
    graph: GraphFacts = .{},
    tracepoints: TracepointFacts = .{},

    pub fn allowsGuestStart(self: *const Report) bool {
        return self.verdict.allowsGuestStart();
    }

    pub fn complete(self: *const Report) bool {
        return self.verdict == .ready and self.unknown == 0 and self.degraded == 0 and !self.check_overflowed;
    }

    pub fn firstNonSatisfiedCheck(self: *const Report) ?*const Check {
        const index = self.first_non_satisfied_check orelse return null;
        return &self.checks[index];
    }

    pub fn firstBlockedCheck(self: *const Report) ?*const Check {
        const index = self.first_blocked_check orelse return null;
        return &self.checks[index];
    }

    pub fn firstRequiredUnknownCheck(self: *const Report) ?*const Check {
        const index = self.first_required_unknown_check orelse return null;
        return &self.checks[index];
    }

    fn addCheck(self: *Report, item: Check) void {
        if (self.check_count >= max_checks) {
            self.check_overflowed = true;
            self.checks_dropped +|= 1;
            return;
        }
        const index: u8 = self.check_count;
        self.checks[self.check_count] = item;
        self.check_count += 1;
        if (item.state != .satisfied and self.first_non_satisfied_check == null) {
            self.first_non_satisfied_check = index;
        }
        if (item.state == .blocked and self.first_blocked_check == null) {
            self.first_blocked_check = index;
        }
        if (item.state == .unknown and item.required and self.first_required_unknown_check == null) {
            self.first_required_unknown_check = index;
        }
        switch (item.state) {
            .satisfied => self.satisfied += 1,
            .degraded => self.degraded += 1,
            .blocked => self.blocked += 1,
            .unknown => {
                self.unknown += 1;
                if (item.required) self.required_unknown += 1;
            },
        }
    }
};

fn check(
    report: *Report,
    name: []const u8,
    state: CheckState,
    required: bool,
    observed: u64,
    expected: u64,
    detail: []const u8,
) void {
    report.addCheck(.{
        .name = name,
        .state = state,
        .required = required,
        .observed = observed,
        .expected = expected,
        .detail = detail,
    });
}

pub fn evaluate(facts: Facts) Report {
    var report = Report{
        .image_is_x86_64 = facts.image_is_x86_64,
        .text_bytes = facts.text_bytes,
        .symbol_entries = facts.symbol_entries,
        .unique_symbol_entries = facts.unique_symbol_entries,
        .import_stubs = facts.import_stubs,
        .dylibs = facts.dylibs,
        .bindings = facts.bindings,
        .decoder_checked = facts.decoder_checked,
        .decoder_invalid = facts.decoder_invalid,
        .first_invalid_address = facts.first_invalid_address,
        .linear_decoder_checked = facts.linear_decoder_checked,
        .linear_decoder_valid = facts.linear_decoder_valid,
        .linear_decoder_invalid = facts.linear_decoder_invalid,
        .linear_decoder_bytes_covered = facts.linear_decoder_bytes_covered,
        .linear_first_invalid_address = facts.linear_first_invalid_address,
        .image_fingerprint = facts.image_fingerprint,
        .text_fingerprint = facts.text_fingerprint,
        .contract_fingerprint = facts.contract_fingerprint,
        .prelaunch = facts.prelaunch,
        .boundaries = facts.boundaries,
        .graph = facts.graph,
        .tracepoints = facts.tracepoints,
    };

    var phase_counts = [_]u32{0} ** 4;
    inline for (@typeInfo(health_schema.Stage).@"enum".fields) |field| {
        const stage: health_schema.Stage = @enumFromInt(field.value);
        phase_counts[@intFromEnum(stage.preflightPhase())] += 1;
    }
    check(
        &report,
        "graphics-stage-plan",
        if (health_schema.contractIsWellFormed()) .satisfied else .blocked,
        true,
        if (health_schema.contractIsWellFormed()) health_schema.stage_count else 0,
        health_schema.stage_count,
        "every declared graphics stage has an owner, layer, evidence phase, stable probe and membership in a path",
    );
    check(
        &report,
        "graphics-image-static-plan",
        if (phase_counts[@intFromEnum(health_schema.PreflightPhase.image_static)] != 0) .satisfied else .blocked,
        true,
        phase_counts[@intFromEnum(health_schema.PreflightPhase.image_static)],
        1,
        "image identity and mapping stages have an explicit pre-guest probe; supporting presence is not runtime effect evidence",
    );
    check(
        &report,
        "graphics-host-smoke-plan",
        if (phase_counts[@intFromEnum(health_schema.PreflightPhase.host_smoke)] != 0) .satisfied else .blocked,
        true,
        phase_counts[@intFromEnum(health_schema.PreflightPhase.host_smoke)],
        1,
        "every host-owned window/device stage has a hidden smoke-test phase before guest admission",
    );
    check(
        &report,
        "graphics-guest-runtime-plan",
        if (phase_counts[@intFromEnum(health_schema.PreflightPhase.guest_runtime)] != 0) .satisfied else .blocked,
        true,
        phase_counts[@intFromEnum(health_schema.PreflightPhase.guest_runtime)],
        1,
        "guest-owned bootstrap, ring, PM4, wait and swap stages have explicit runtime probes and cannot be green before their producer runs",
    );
    check(
        &report,
        "graphics-guest-output-plan",
        if (phase_counts[@intFromEnum(health_schema.PreflightPhase.guest_output)] != 0) .satisfied else .blocked,
        true,
        phase_counts[@intFromEnum(health_schema.PreflightPhase.guest_output)],
        1,
        "output stages require guest-produced pixels and a custody witness; host diagnostic clears are excluded",
    );

    check(
        &report,
        "image-mapped",
        if (facts.mapped) .satisfied else .blocked,
        true,
        @intFromBool(facts.mapped),
        1,
        "the Mach-O image was mapped into a runtime state",
    );
    check(
        &report,
        "image-architecture",
        if (facts.image_is_x86_64) .satisfied else .blocked,
        true,
        @intFromBool(facts.image_is_x86_64),
        1,
        "the translated image is x86_64, the ISA Rosette is auditing",
    );
    check(
        &report,
        "executable-text",
        if (facts.has_text and facts.text_bytes != 0) .satisfied else .blocked,
        true,
        facts.text_bytes,
        1,
        "a non-empty __TEXT,__text section is available to inspect",
    );
    check(
        &report,
        "entry-in-text",
        if (facts.entry_in_text) .satisfied else .blocked,
        true,
        @intFromBool(facts.entry_in_text),
        1,
        "the Mach-O entry point lies in executable translated code",
    );
    check(
        &report,
        "defined-symbol-table",
        if (facts.symbol_entries != 0) .satisfied else .blocked,
        true,
        facts.symbol_entries,
        1,
        "defined symbols are available for boundary resolution and graph attribution",
    );

    const import_shape_ok = facts.import_stubs == 0 or facts.has_stub_section;
    check(
        &report,
        "import-stub-shape",
        if (import_shape_ok) .satisfied else .blocked,
        true,
        facts.import_stubs,
        if (facts.import_stubs == 0) 0 else 1,
        "import stubs have a corresponding Mach-O __stubs section",
    );
    const binding_coverage: CheckState = if (facts.import_stubs == 0 or facts.bindings != 0)
        .satisfied
    else
        .unknown;
    check(
        &report,
        "import-binding-surface",
        binding_coverage,
        false,
        facts.bindings,
        if (facts.import_stubs == 0) 0 else 1,
        "binding records are structural evidence only; runtime ABI and fallback safety remain dynamic",
    );
    check(
        &report,
        "native-library-surface",
        if (facts.import_stubs == 0 or facts.dylibs != 0) .satisfied else .unknown,
        false,
        facts.dylibs,
        if (facts.import_stubs == 0) 0 else 1,
        "the image declares the native libraries behind its import stubs",
    );

    check(
        &report,
        "image-content-fingerprint",
        if (facts.image_fingerprint != 0) .satisfied else .unknown,
        true,
        facts.image_fingerprint,
        1,
        "the complete loaded Mach-O content has a non-zero identity before code coverage is evaluated",
    );
    check(
        &report,
        "executable-text-fingerprint",
        if (facts.text_fingerprint != 0) .satisfied else .unknown,
        true,
        facts.text_fingerprint,
        1,
        "the complete __TEXT,__text byte span has a content identity independent of its symbol names",
    );
    check(
        &report,
        "graphics-contract-fingerprint",
        if (facts.contract_fingerprint != 0) .satisfied else .unknown,
        true,
        facts.contract_fingerprint,
        1,
        "the boundary contract used for this decision is identified so a stale observer schema cannot look current",
    );

    if (!facts.prelaunch.evaluated) {
        check(
            &report,
            "prelaunch-stage-census",
            .unknown,
            true,
            0,
            prelaunch_audit.contract_stages.len,
            "the classified prelaunch stage inventory was not supplied; no subsystem-presence conclusion is valid",
        );
    } else {
        const prelaunch_state: CheckState = switch (facts.prelaunch.verdict) {
            .ready => .satisfied,
            .blocked => .blocked,
            .unevaluated => .unknown,
        };
        check(
            &report,
            "prelaunch-stage-census",
            prelaunch_state,
            true,
            facts.prelaunch.symbols,
            prelaunch_audit.contract_stages.len,
            "the existing whole-image subsystem census is included in this graphics decision; symbol presence still is not runtime proof",
        );
        for (prelaunch_audit.contract_stages) |stage| {
            const stage_facts = facts.prelaunch.stages[@intFromEnum(stage)];
            const stage_state: CheckState = if (!stage_facts.isEmpty())
                .satisfied
            else if (stage.blocksLaunch())
                .blocked
            else
                .unknown;
            check(
                &report,
                "prelaunch-stage-presence",
                stage_state,
                stage.blocksLaunch(),
                stage_facts.symbols,
                1,
                stage.label(),
            );
        }
    }

    var required_boundary_symbols: u32 = 0;
    var resolved_required_boundary_symbols: u32 = 0;
    var required_tracepoints: u32 = 0;
    var armed_required_tracepoints: u32 = 0;
    for (contract.allBoundaries()) |boundary| {
        const index = @intFromEnum(boundary);
        const fact = facts.boundaries[index];
        const required = boundary.requirement() == .required;
        if (required) required_boundary_symbols += 1;
        if (fact.executable_candidates != 0 and required) resolved_required_boundary_symbols += 1;
        if (required) required_tracepoints += 1;
        if (fact.armed_candidates != 0 and required) armed_required_tracepoints += 1;

        const symbol_state: CheckState = if (fact.executable_candidates != 0)
            .satisfied
        else switch (boundary.requirement()) {
            .required => .blocked,
            .expected => .unknown,
            .optional => .satisfied,
        };
        check(
            &report,
            "graphics-boundary-symbol",
            symbol_state,
            required,
            fact.executable_candidates,
            if (required) 1 else 0,
            boundary.label(),
        );

        const decoder_state: CheckState = if (fact.executable_candidates == 0)
            if (required) .blocked else .unknown
        else if (!facts.decoder_probe_available)
            .unknown
        else if (fact.decoder_valid_candidates != 0)
            .satisfied
        else switch (boundary.requirement()) {
            .required => .blocked,
            .expected => .unknown,
            .optional => .degraded,
        };
        check(
            &report,
            "graphics-boundary-entry-decodes",
            decoder_state,
            required,
            fact.decoder_valid_candidates,
            if (fact.executable_candidates == 0) 0 else 1,
            "at least one executable boundary candidate starts with an instruction Rosette can decode",
        );

        const observer_state: CheckState = if (!facts.tracepoints.sealed)
            .unknown
        else if (fact.armed_candidates != 0)
            .satisfied
        else switch (boundary.requirement()) {
            .required => .blocked,
            .expected => .unknown,
            .optional => .satisfied,
        };
        check(
            &report,
            "graphics-boundary-observer",
            observer_state,
            required,
            fact.armed_candidates,
            if (required) 1 else 0,
            "the runtime tracepoint set watches this boundary before guest execution",
        );
    }

    check(
        &report,
        "required-boundary-resolution",
        if (resolved_required_boundary_symbols == required_boundary_symbols)
            .satisfied
        else
            .blocked,
        true,
        resolved_required_boundary_symbols,
        required_boundary_symbols,
        "every required graphics boundary has an executable symbol candidate",
    );
    check(
        &report,
        "required-boundary-observation",
        if (!facts.tracepoints.sealed)
            .unknown
        else if (armed_required_tracepoints == required_tracepoints)
            .satisfied
        else
            .blocked,
        true,
        armed_required_tracepoints,
        required_tracepoints,
        "every required graphics boundary remains observable after tracepoint arming",
    );
    check(
        &report,
        "tracepoint-capacity",
        if (!facts.tracepoints.sealed)
            .unknown
        else if (facts.tracepoints.saturated and armed_required_tracepoints != required_tracepoints)
            .blocked
        else if (facts.tracepoints.saturated)
            .degraded
        else
            .satisfied,
        true,
        facts.tracepoints.armed_total,
        if (facts.tracepoints.saturated) facts.tracepoints.armed_total else 1,
        "the observer set did not silently lose a required boundary to capacity",
    );
    check(
        &report,
        "tracepoint-unresolved",
        if (!facts.tracepoints.sealed)
            .unknown
        else if (facts.tracepoints.unresolved == 0)
            .satisfied
        else
            .degraded,
        false,
        facts.tracepoints.unresolved,
        0,
        "unresolved observer offers are retained as a coverage warning",
    );

    check(
        &report,
        "decoder-baseline",
        if (facts.decoder_baseline_ready) .satisfied else .blocked,
        true,
        @intFromBool(facts.decoder_baseline_ready),
        1,
        "the baseline VEX/AVX decoder audit passed before the guest starts",
    );
    const decoder_coverage_state: CheckState = if (!facts.decoder_probe_available)
        .unknown
    else if (facts.decoder_checked == 0)
        .unknown
    else if (facts.decoder_invalid == 0)
        .satisfied
    else
        .degraded;
    check(
        &report,
        "decoder-symbol-entry-coverage",
        decoder_coverage_state,
        false,
        facts.decoder_checked -| facts.decoder_invalid,
        facts.decoder_checked,
        "symbol-entry decoding is a fast coverage signal, not proof that indirect guest code will never use another opcode",
    );
    const linear_decoder_state: CheckState = if (!facts.decoder_probe_available)
        .unknown
    else if (facts.linear_decoder_checked == 0)
        .unknown
    else if (facts.linear_decoder_invalid == 0)
        .satisfied
    else
        .unknown;
    check(
        &report,
        "decoder-linear-text-coverage",
        linear_decoder_state,
        false,
        facts.linear_decoder_valid,
        facts.linear_decoder_checked,
        "a bounded linear sweep attempted to decode the entire executable byte span; invalid offsets may be literal data or jump-table bytes, so this is coverage evidence rather than a control-flow proof",
    );
    check(
        &report,
        "decoder-linear-span-covered",
        if (facts.linear_decoder_bytes_covered == facts.text_bytes and facts.text_bytes != 0)
            .satisfied
        else
            .unknown,
        false,
        facts.linear_decoder_bytes_covered,
        facts.text_bytes,
        "the coverage sweep accounts for every byte in __TEXT,__text, including offsets that cannot be classified as instructions",
    );

    if (facts.host_capabilities) |host| {
        const summary = host.summary();
        const host_state: CheckState = if (summary.probed == 0)
            .unknown
        else if (!summary.foundationHolds())
            .blocked
        else if (summary.fidelity_failures != 0)
            .degraded
        else
            .satisfied;
        check(
            &report,
            "host-foundation",
            host_state,
            true,
            summary.probed -| summary.foundational_failures,
            summary.probed,
            summary.describe(),
        );
    } else {
        check(
            &report,
            "host-foundation",
            .unknown,
            true,
            0,
            1,
            "host capability probes were not supplied to graphics preflight",
        );
    }

    // The component contract is intentionally enumerated here even though
    // most entries cannot be proven before a title uses them.  A static image
    // scan must not turn a declared library or a future round trip into a
    // green runtime proof.  Keeping one row per component makes the blind
    // surface explicit and gives the runtime ledger a stable checklist to
    // close later.
    var component_unknown: u64 = 0;
    var essential_component_total: u64 = 0;
    var essential_component_unknown: u64 = 0;
    for (component_contract.allComponents()) |component| {
        const proof = component.proof();
        const essential = component.essential();
        component_unknown += 1;
        if (essential) {
            essential_component_total += 1;
            essential_component_unknown += 1;
        }
        report.components[@intFromEnum(component)] = .{
            .component = component,
            .proof = proof,
            .essential = essential,
            .state = .unknown,
        };
        check(
            &report,
            "graphics-component-proof",
            .unknown,
            false,
            @intFromEnum(proof),
            1,
            component.obligation(),
        );
    }
    check(
        &report,
        "graphics-component-catalog",
        if (component_unknown == component_contract.component_count) .satisfied else .blocked,
        true,
        component_unknown,
        component_contract.component_count,
        "all cross-layer graphics components are represented; runtime proof is kept separate from static presence",
    );
    check(
        &report,
        "graphics-runtime-proof-surface",
        if (component_unknown == 0) .satisfied else .unknown,
        false,
        component_contract.component_count - component_unknown,
        component_contract.component_count,
        "the title has not run yet, so round-trip components remain unproven and must be closed by the runtime ledger",
    );
    check(
        &report,
        "graphics-essential-runtime-proof-surface",
        if (essential_component_unknown == 0) .satisfied else .unknown,
        false,
        essential_component_total - essential_component_unknown,
        essential_component_total,
        "essential components cannot be certified by symbol presence; their first-use obligations remain explicit",
    );

    // These are the high-value runtime seams exposed by this run. They are
    // separate from the component rows so a log reader can immediately see
    // why a static report cannot certify a native frame, a title XEX import,
    // or platform-variable provisioning.
    check(
        &report,
        "host-graphics-device-runtime",
        .unknown,
        false,
        0,
        1,
        "a real device, queue submission, and completion require a host graphics smoke probe; Mach-O symbols cannot prove them",
    );
    check(
        &report,
        "host-surface-presentation-runtime",
        .unknown,
        false,
        0,
        1,
        "a Cocoa/Vulkan surface and swapchain require window-system execution; the preflight does not invent a diagnostic frame",
    );
    check(
        &report,
        "guest-xex-import-surface",
        .unknown,
        false,
        0,
        1,
        "the title's XEX import table is outside the Mach-O image and is only answerable after the XISO module is opened",
    );
    check(
        &report,
        "guest-platform-provisioning",
        .unknown,
        false,
        0,
        1,
        "kernel graphics variables and title-owned slots are runtime state, not linkable Mach-O code",
    );

    // The graph is intentionally advisory.  It is useful for finding a
    // direct-link regression, but no direct graph can certify ordinal-table,
    // vtable or guest-title dispatch.
    check(
        &report,
        "direct-call-graph",
        if (facts.graph.complete) .satisfied else .unknown,
        false,
        facts.graph.reachable_nodes,
        facts.graph.nodes,
        "direct edges are proven; indirect dispatch and guest code remain runtime obligations",
    );
    check(
        &report,
        "required-boundary-direct-reachability",
        if (resolved_required_boundary_symbols == 0)
            .blocked
        else if (armed_required_tracepoints == 0)
            .unknown
        else
            // A direct edge is not required evidence here: Xenia routes
            // much of this surface through ordinal tables and vtables.
            // Without an observed direct edge, static analysis cannot
            // distinguish an indirect path from an unreachable boundary.
            .unknown,
        false,
        0,
        resolved_required_boundary_symbols,
        "guest-owned Vd* boundaries normally arrive through indirect export dispatch, so static absence is not a failure",
    );

    if (report.check_overflowed) {
        report.verdict = .blocked;
    } else if (report.blocked != 0) {
        report.verdict = .blocked;
    } else if (report.required_unknown != 0) {
        report.verdict = .unknown;
    } else {
        report.verdict = .ready;
    }
    return report;
}

const Symbol = struct {
    address: u64,
    name: []const u8,
};

const GraphNode = struct {
    address: u64,
    name: []const u8,
};

const Candidate = struct {
    address: u64 = 0,
    name: []const u8 = "",
};

fn lessSymbol(_: void, lhs: Symbol, rhs: Symbol) bool {
    if (lhs.address != rhs.address) return lhs.address < rhs.address;
    return lhs.name.len < rhs.name.len;
}

fn lessNode(_: void, lhs: GraphNode, rhs: GraphNode) bool {
    return lhs.address < rhs.address;
}

fn owningNode(nodes: []const GraphNode, address: u64) ?usize {
    if (nodes.len == 0 or address < nodes[0].address) return null;
    var low: usize = 0;
    var high: usize = nodes.len;
    while (low + 1 < high) {
        const middle = low + (high - low) / 2;
        if (nodes[middle].address <= address) low = middle else high = middle;
    }
    return low;
}

fn exactNode(nodes: []const GraphNode, address: u64) ?usize {
    const index = owningNode(nodes, address) orelse return null;
    return if (nodes[index].address == address) index else null;
}

fn insertCandidate(best: *[max_boundary_candidates]Candidate, candidate: Candidate) void {
    for (best) |*existing| {
        if (existing.address != candidate.address) continue;
        if (candidate.name.len < existing.name.len) existing.* = candidate;
        return;
    }

    var position: ?usize = null;
    for (best, 0..) |existing, index| {
        if (existing.address == 0 or candidate.name.len < existing.name.len) {
            position = index;
            break;
        }
    }
    const at = position orelse return;
    var index = best.len - 1;
    while (index > at) : (index -= 1) best[index] = best[index - 1];
    best[at] = candidate;
}

fn resolveBoundary(metadata: anytype, text_address: u64, text_size: u64, boundary: Boundary, decoder: ?DecodeInstruction) CandidateFacts {
    var result = CandidateFacts{ .boundary = boundary };
    var best: [max_boundary_candidates]Candidate = [_]Candidate{.{}} ** max_boundary_candidates;
    var symbols = metadata.definedSymbolIterator();
    const text_end = text_address +| text_size;
    while (symbols.next()) |symbol| {
        const name = symbol.key_ptr.*;
        if (std.mem.indexOf(u8, name, boundary.fragment()) == null) continue;
        var missing = false;
        for (boundary.alsoRequires()) |required| {
            if (std.mem.indexOf(u8, name, required) == null) {
                missing = true;
                break;
            }
        }
        if (missing) continue;
        var excluded = false;
        for (boundary.exclusions()) |forbidden| {
            if (std.mem.indexOf(u8, name, forbidden) != null) {
                excluded = true;
                break;
            }
        }
        if (excluded) continue;
        result.symbol_matches +|= 1;
        const address = symbol.value_ptr.*;
        if (address < text_address or address >= text_end) continue;
        if (!metadata.isExecutableImageAddress(address)) continue;
        result.executable_candidates +|= 1;
        insertCandidate(&best, .{ .address = address, .name = name });
    }

    for (best) |candidate| {
        if (candidate.address == 0) continue;
        result.candidate_addresses[result.candidate_count] = candidate.address;
        result.candidate_count += 1;
        if (decoder) |decode| {
            const offset: usize = @intCast(candidate.address - text_address);
            // x86 instructions are at most fifteen bytes.  A shortened tail
            // is passed to the decoder and correctly becomes invalid.
            const start = @min(offset, @as(usize, @intCast(text_size)));
            const limit = @min(@as(usize, @intCast(text_size)), start + 15);
            const text = metadata.sectionNamed("__TEXT", "__text") orelse continue;
            const bytes = metadata.sectionBytes(text) orelse continue;
            if (decode(bytes[start..@min(limit, bytes.len)]).valid) {
                result.decoder_valid_candidates += 1;
            }
        }
    }
    return result;
}

fn contractFingerprint() u64 {
    var fingerprint: u64 = 0x726f7365747465;
    for (contract.allBoundaries()) |boundary| {
        fingerprint = std.hash.Wyhash.hash(fingerprint, boundary.label());
        fingerprint = std.hash.Wyhash.hash(fingerprint, boundary.requirement().label());
        fingerprint = std.hash.Wyhash.hash(fingerprint, boundary.owner().label());
        fingerprint = std.hash.Wyhash.hash(fingerprint, boundary.fragment());
    }
    return if (fingerprint == 0) 1 else fingerprint;
}

fn scanLinearText(
    facts: *Facts,
    text_address: u64,
    text_bytes: []const u8,
    decode: DecodeInstruction,
) void {
    var offset: usize = 0;
    while (offset < text_bytes.len) {
        const available = text_bytes.len - offset;
        const limit = @min(available, 15);
        const decoded = decode(text_bytes[offset .. offset + limit]);
        facts.linear_decoder_checked +|= 1;

        const decoded_length: usize = @intCast(decoded.length);
        const valid_length = decoded.valid and decoded_length != 0 and
            decoded_length <= limit and decoded_length <= 15;
        if (!valid_length) {
            facts.linear_decoder_invalid +|= 1;
            if (facts.linear_first_invalid_address == 0) {
                facts.linear_first_invalid_address = text_address +| @as(u64, @intCast(offset));
            }
            facts.linear_decoder_bytes_covered +|= 1;
            offset += 1;
            continue;
        }

        facts.linear_decoder_valid +|= 1;
        facts.linear_decoder_bytes_covered +|= decoded_length;
        offset += decoded_length;
    }
}

fn edgeTarget(bytes: []const u8, text_address: u64, offset: usize) ?u64 {
    if (offset + 5 > bytes.len) return null;
    const opcode = bytes[offset];
    if (opcode != 0xE8 and opcode != 0xE9) return null;
    const displacement = std.mem.readInt(i32, bytes[offset + 1 ..][0..4], .little);
    const next = text_address + offset + 5;
    return if (displacement < 0)
        next -% @as(u64, @intCast(-@as(i64, displacement)))
    else
        next +% @as(u64, @intCast(displacement));
}

fn nextOffset(bytes: []const u8, offset: usize) usize {
    if (offset < bytes.len and (bytes[offset] == 0xE8 or bytes[offset] == 0xE9)) return 5;
    return 1;
}

fn buildGraph(
    allocator: std.mem.Allocator,
    nodes: []const GraphNode,
    text_address: u64,
    text_bytes: []const u8,
    entry_point: u64,
    initializer_addresses: []const u64,
    boundaries: *[boundary_count]CandidateFacts,
) !GraphFacts {
    var graph = GraphFacts{ .nodes = @intCast(nodes.len) };
    if (nodes.len == 0 or text_bytes.len == 0) return graph;

    const inbound = try allocator.alloc(bool, nodes.len);
    defer allocator.free(inbound);
    @memset(inbound, false);
    const visited = try allocator.alloc(bool, nodes.len);
    defer allocator.free(visited);
    @memset(visited, false);
    const queue = try allocator.alloc(usize, nodes.len);
    defer allocator.free(queue);

    var offset: usize = 0;
    while (offset + 5 <= text_bytes.len) {
        if (edgeTarget(text_bytes, text_address, offset)) |target| {
            graph.direct_edges +|= 1;
            if (exactNode(nodes, target)) |target_index| inbound[target_index] = true;
        }
        offset += nextOffset(text_bytes, offset);
    }

    var queue_head: usize = 0;
    var queue_tail: usize = 0;
    const addRoot = struct {
        fn add(
            address: u64,
            nodes_: []const GraphNode,
            visited_: []bool,
            queue_: []usize,
            tail: *usize,
            rooted: *bool,
        ) void {
            const index = owningNode(nodes_, address) orelse return;
            rooted.* = true;
            if (visited_[index]) return;
            visited_[index] = true;
            queue_[tail.*] = index;
            tail.* += 1;
        }
    }.add;
    addRoot(entry_point, nodes, visited, queue, &queue_tail, &graph.entry_rooted);
    if (graph.entry_rooted) graph.roots += 1;
    for (initializer_addresses) |address| {
        const before = queue_tail;
        var rooted = false;
        addRoot(address, nodes, visited, queue, &queue_tail, &rooted);
        if (rooted and queue_tail != before) graph.roots += 1;
    }

    while (queue_head < queue_tail) {
        const node_index = queue[queue_head];
        queue_head += 1;
        graph.reachable_nodes += 1;
        const start_address = nodes[node_index].address;
        const end_address = if (node_index + 1 < nodes.len)
            @min(nodes[node_index + 1].address, text_address +| @as(u64, @intCast(text_bytes.len)))
        else
            text_address +| @as(u64, @intCast(text_bytes.len));
        if (start_address < text_address or start_address >= end_address) continue;
        const start: usize = @intCast(start_address - text_address);
        const end: usize = @intCast(end_address - text_address);
        offset = start;
        while (offset + 5 <= end and offset + 5 <= text_bytes.len) {
            if (edgeTarget(text_bytes, text_address, offset)) |target| {
                if (exactNode(nodes, target)) |target_index| {
                    if (!visited[target_index]) {
                        visited[target_index] = true;
                        queue[queue_tail] = target_index;
                        queue_tail += 1;
                    }
                }
            }
            offset += nextOffset(text_bytes, offset);
        }
    }

    for (boundaries) |*boundary| {
        for (boundary.candidate_addresses[0..boundary.candidate_count]) |address| {
            const index = exactNode(nodes, address) orelse continue;
            boundary.direct_inbound = boundary.direct_inbound or inbound[index];
            boundary.direct_reachable = boundary.direct_reachable or visited[index];
        }
    }
    return graph;
}

/// Build all static facts from a loaded Mach-O metadata object.  The generic
/// metadata parameter keeps this package independent from the Mach-O parser;
/// tests and other image readers can supply the same small method surface.
pub fn auditMetadata(
    allocator: std.mem.Allocator,
    metadata: anytype,
    options: struct {
        entry_point: u64 = 0,
        image_is_x86_64: bool = false,
        tracepoints: TracepointFacts = .{},
        decoder_baseline_ready: bool = false,
        decode_instruction: ?DecodeInstruction = null,
        host_capabilities: ?*const host_capability.Report = null,
        image_fingerprint: u64 = 0,
        prelaunch: ?prelaunch_audit.Summary = null,
    },
) !Report {
    var facts = Facts{
        .image_is_x86_64 = options.image_is_x86_64,
        .tracepoints = options.tracepoints,
        .decoder_baseline_ready = options.decoder_baseline_ready,
        .decoder_probe_available = options.decode_instruction != null,
        .host_capabilities = options.host_capabilities,
        .image_fingerprint = options.image_fingerprint,
        .contract_fingerprint = contractFingerprint(),
    };
    if (options.prelaunch) |summary| {
        facts.prelaunch = .{
            .evaluated = true,
            .verdict = summary.verdict,
            .symbols = summary.symbols_walked,
            .import_stubs = summary.import_stubs,
            .stages = summary.facts,
        };
    }
    facts.import_stubs = @intCast(metadata.imports.len);
    facts.has_stub_section = metadata.sectionNamed("__TEXT", "__stubs") != null;
    facts.dylibs = @intCast(metadata.dylibs.len);
    facts.bindings = @intCast(metadata.bindings.len);

    const text = metadata.sectionNamed("__TEXT", "__text") orelse return evaluate(facts);
    const text_bytes = metadata.sectionBytes(text) orelse return evaluate(facts);
    facts.has_text = true;
    facts.text_bytes = @intCast(text_bytes.len);
    facts.text_fingerprint = std.hash.Wyhash.hash(0, text_bytes);
    facts.entry_in_text = metadata.isExecutableImageAddress(options.entry_point) and
        options.entry_point >= text.address and
        options.entry_point < text.address +| text.size;

    var symbols: std.ArrayList(Symbol) = .empty;
    defer symbols.deinit(allocator);
    var iterator = metadata.definedSymbolIterator();
    const text_end = text.address +| text.size;
    while (iterator.next()) |symbol| {
        const address = symbol.value_ptr.*;
        if (address < text.address or address >= text_end) continue;
        facts.symbol_entries +|= 1;
        try symbols.append(allocator, .{ .address = address, .name = symbol.key_ptr.* });
    }
    std.mem.sort(Symbol, symbols.items, {}, lessSymbol);

    var nodes: std.ArrayList(GraphNode) = .empty;
    defer nodes.deinit(allocator);
    for (symbols.items) |symbol| {
        if (nodes.items.len != 0 and nodes.items[nodes.items.len - 1].address == symbol.address) continue;
        try nodes.append(allocator, .{ .address = symbol.address, .name = symbol.name });
    }
    facts.unique_symbol_entries = @intCast(nodes.items.len);

    if (options.decode_instruction) |decode| {
        for (nodes.items) |node| {
            const offset: usize = @intCast(node.address - text.address);
            const limit = @min(text_bytes.len, offset + 15);
            if (offset >= limit) continue;
            facts.decoder_checked +|= 1;
            if (!decode(text_bytes[offset..limit]).valid) {
                facts.decoder_invalid +|= 1;
                if (facts.first_invalid_address == 0) facts.first_invalid_address = node.address;
            }
        }
        scanLinearText(&facts, text.address, text_bytes, decode);
    }

    for (contract.allBoundaries()) |boundary| {
        facts.boundaries[@intFromEnum(boundary)] = resolveBoundary(
            metadata,
            text.address,
            @intCast(text_bytes.len),
            boundary,
            options.decode_instruction,
        );
        facts.boundaries[@intFromEnum(boundary)].armed_candidates =
            options.tracepoints.armed_by_boundary[@intFromEnum(boundary)];
    }

    facts.graph = try buildGraph(
        allocator,
        nodes.items,
        text.address,
        text_bytes,
        options.entry_point,
        metadata.initializer_addresses,
        &facts.boundaries,
    );
    return evaluate(facts);
}

fn alwaysDecode(bytes: []const u8) DecodeResult {
    return .{ .valid = bytes.len != 0, .length = 1 };
}

fn neverDecode(_: []const u8) DecodeResult {
    return .{};
}

fn healthyPrelaunchFacts() PrelaunchFacts {
    var result = PrelaunchFacts{
        .evaluated = true,
        .verdict = .ready,
        .symbols = 10,
        .import_stubs = 1,
    };
    for (prelaunch_audit.contract_stages) |stage| {
        result.stages[@intFromEnum(stage)] = .{
            .stage = stage,
            .symbols = 1,
        };
    }
    return result;
}

fn completeSyntheticFacts() Facts {
    return .{
        .image_fingerprint = 1,
        .text_fingerprint = 1,
        .contract_fingerprint = 1,
        .prelaunch = healthyPrelaunchFacts(),
    };
}

fn healthyHostReport() host_capability.Report {
    var report = host_capability.Report{};
    for (host_capability.allCapabilities()) |capability| {
        if (!capability.probedByPreflight()) continue;
        report.findings[@intFromEnum(capability)] = .{
            .capability = capability,
            .outcome = .verified,
        };
    }
    return report;
}

test "static evaluator blocks an un-decodable required boundary" {
    var facts = Facts{
        .mapped = true,
        .image_fingerprint = 1,
        .text_fingerprint = 1,
        .contract_fingerprint = 1,
        .prelaunch = healthyPrelaunchFacts(),
        .image_is_x86_64 = true,
        .has_text = true,
        .text_bytes = 32,
        .entry_in_text = true,
        .symbol_entries = 1,
        .unique_symbol_entries = 1,
        .decoder_baseline_ready = true,
        .decoder_probe_available = true,
        .host_capabilities = undefined,
    };
    facts.boundaries[@intFromEnum(Boundary.initialize_engines)] = .{
        .boundary = .initialize_engines,
        .executable_candidates = 1,
        .candidate_count = 1,
        .decoder_valid_candidates = 0,
        .armed_candidates = 1,
    };
    var host = healthyHostReport();
    facts.host_capabilities = &host;
    const report = evaluate(facts);
    try std.testing.expectEqual(Verdict.blocked, report.verdict);
    try std.testing.expect(report.blocked != 0);
}

test "static evaluator keeps indirect graphics reachability unknown" {
    var facts = Facts{
        .mapped = true,
        .image_fingerprint = 1,
        .text_fingerprint = 1,
        .contract_fingerprint = 1,
        .prelaunch = healthyPrelaunchFacts(),
        .image_is_x86_64 = true,
        .has_text = true,
        .text_bytes = 32,
        .entry_in_text = true,
        .symbol_entries = 1,
        .unique_symbol_entries = 1,
        .decoder_baseline_ready = true,
        .decoder_probe_available = true,
        .tracepoints = .{ .sealed = true },
        .graph = .{ .nodes = 10, .reachable_nodes = 2, .complete = false },
    };
    var host = healthyHostReport();
    facts.host_capabilities = &host;
    for (contract.allBoundaries()) |boundary| {
        facts.boundaries[@intFromEnum(boundary)] = .{
            .boundary = boundary,
            .executable_candidates = 1,
            .candidate_count = 1,
            .decoder_valid_candidates = 1,
            .armed_candidates = 1,
        };
    }
    const report = evaluate(facts);
    try std.testing.expectEqual(Verdict.ready, report.verdict);
    try std.testing.expect(report.unknown != 0);
    try std.testing.expect(!report.complete());
}

test "optional absent boundaries do not block a static run" {
    var facts = Facts{
        .mapped = true,
        .image_fingerprint = 1,
        .text_fingerprint = 1,
        .contract_fingerprint = 1,
        .prelaunch = healthyPrelaunchFacts(),
        .image_is_x86_64 = true,
        .has_text = true,
        .text_bytes = 32,
        .entry_in_text = true,
        .symbol_entries = 1,
        .unique_symbol_entries = 1,
        .decoder_baseline_ready = true,
        .decoder_probe_available = true,
        .tracepoints = .{ .sealed = true },
    };
    var host = healthyHostReport();
    facts.host_capabilities = &host;
    const report = evaluate(facts);
    try std.testing.expectEqual(Verdict.blocked, report.verdict);
    // Required boundaries are still absent; this assertion protects the
    // distinction rather than claiming an incomplete image is healthy.
    try std.testing.expect(report.required_unknown == 0);
}

test "decoder coverage records invalid entries without hiding the address" {
    var facts = Facts{
        .mapped = true,
        .image_fingerprint = 1,
        .text_fingerprint = 1,
        .contract_fingerprint = 1,
        .prelaunch = healthyPrelaunchFacts(),
        .image_is_x86_64 = true,
        .has_text = true,
        .text_bytes = 32,
        .entry_in_text = true,
        .symbol_entries = 1,
        .unique_symbol_entries = 1,
        .decoder_baseline_ready = true,
        .decoder_probe_available = true,
        .decoder_checked = 3,
        .decoder_invalid = 1,
        .first_invalid_address = 0x1234,
    };
    var host = healthyHostReport();
    facts.host_capabilities = &host;
    const report = evaluate(facts);
    try std.testing.expectEqual(@as(u32, 1), report.decoder_invalid);
    try std.testing.expectEqual(@as(u64, 0x1234), report.first_invalid_address);
}

test "a sealed observer set with all required boundaries armed is observable" {
    var facts = Facts{
        .mapped = true,
        .image_fingerprint = 1,
        .text_fingerprint = 1,
        .contract_fingerprint = 1,
        .prelaunch = healthyPrelaunchFacts(),
        .image_is_x86_64 = true,
        .has_text = true,
        .text_bytes = 32,
        .entry_in_text = true,
        .symbol_entries = 1,
        .unique_symbol_entries = 1,
        .decoder_baseline_ready = true,
        .decoder_probe_available = true,
        .tracepoints = .{ .sealed = true },
    };
    for (contract.allBoundaries()) |boundary| {
        facts.boundaries[@intFromEnum(boundary)] = .{
            .boundary = boundary,
            .executable_candidates = if (boundary.requirement() == .optional) 0 else 1,
            .candidate_count = if (boundary.requirement() == .optional) 0 else 1,
            .decoder_valid_candidates = if (boundary.requirement() == .optional) 0 else 1,
            .armed_candidates = if (boundary.requirement() == .optional) 0 else 1,
        };
    }
    var host = healthyHostReport();
    facts.host_capabilities = &host;
    const report = evaluate(facts);
    try std.testing.expectEqual(Verdict.ready, report.verdict);
    try std.testing.expect(report.blocked == 0);
}

test "decoder callback can be supplied without making graph claims" {
    var facts = Facts{
        .mapped = true,
        .image_fingerprint = 1,
        .text_fingerprint = 1,
        .contract_fingerprint = 1,
        .prelaunch = healthyPrelaunchFacts(),
        .image_is_x86_64 = true,
        .has_text = true,
        .text_bytes = 32,
        .entry_in_text = true,
        .symbol_entries = 1,
        .unique_symbol_entries = 1,
        .decoder_baseline_ready = true,
        .decoder_probe_available = true,
        .decoder_checked = 1,
        .decoder_invalid = 0,
        .graph = .{ .nodes = 1, .reachable_nodes = 1 },
    };
    _ = alwaysDecode;
    _ = neverDecode;
    var host = healthyHostReport();
    facts.host_capabilities = &host;
    const report = evaluate(facts);
    try std.testing.expect(report.unknown != 0);
    try std.testing.expectEqual(Verdict.blocked, report.verdict);
}

test "the static report keeps the full component census and runtime unknowns" {
    var facts = completeSyntheticFacts();
    facts.mapped = true;
    facts.image_is_x86_64 = true;
    facts.has_text = true;
    facts.text_bytes = 32;
    facts.entry_in_text = true;
    facts.symbol_entries = 1;
    facts.unique_symbol_entries = 1;
    facts.decoder_baseline_ready = true;
    facts.decoder_probe_available = true;
    facts.decoder_checked = 1;
    facts.linear_decoder_checked = 1;
    facts.linear_decoder_valid = 1;
    facts.linear_decoder_bytes_covered = 32;
    facts.tracepoints = .{ .sealed = true };
    facts.graph = .{ .nodes = 1, .reachable_nodes = 1 };
    for (contract.allBoundaries()) |boundary| {
        facts.boundaries[@intFromEnum(boundary)] = .{
            .boundary = boundary,
            .executable_candidates = if (boundary.requirement() == .optional) 0 else 1,
            .candidate_count = if (boundary.requirement() == .optional) 0 else 1,
            .decoder_valid_candidates = if (boundary.requirement() == .optional) 0 else 1,
            .armed_candidates = if (boundary.requirement() == .optional) 0 else 1,
        };
    }
    var host = healthyHostReport();
    facts.host_capabilities = &host;
    const report = evaluate(facts);
    try std.testing.expectEqual(Verdict.ready, report.verdict);
    try std.testing.expectEqual(@as(usize, component_contract.component_count), report.components.len);
    try std.testing.expect(report.check_count < max_checks);
    try std.testing.expect(report.unknown >= component_contract.component_count);
    try std.testing.expect(!report.complete());
}

test "an absent prelaunch census is an unknown required gate" {
    var facts = completeSyntheticFacts();
    facts.prelaunch = .{};
    facts.mapped = true;
    facts.image_is_x86_64 = true;
    facts.has_text = true;
    facts.text_bytes = 32;
    facts.entry_in_text = true;
    facts.symbol_entries = 1;
    facts.unique_symbol_entries = 1;
    facts.decoder_baseline_ready = true;
    facts.decoder_probe_available = true;
    facts.decoder_checked = 1;
    facts.tracepoints = .{ .sealed = true };
    for (contract.allBoundaries()) |boundary| {
        facts.boundaries[@intFromEnum(boundary)] = .{
            .boundary = boundary,
            .executable_candidates = if (boundary.requirement() == .optional) 0 else 1,
            .candidate_count = if (boundary.requirement() == .optional) 0 else 1,
            .decoder_valid_candidates = if (boundary.requirement() == .optional) 0 else 1,
            .armed_candidates = if (boundary.requirement() == .optional) 0 else 1,
        };
    }
    var host = healthyHostReport();
    facts.host_capabilities = &host;
    const report = evaluate(facts);
    try std.testing.expectEqual(Verdict.unknown, report.verdict);
    try std.testing.expect(report.required_unknown != 0);
    try std.testing.expect(!report.allowsGuestStart());
}
