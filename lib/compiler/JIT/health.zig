//! Bounded health accounting for Xenia's guest-visible JIT diagnostics.
//!
//! This module deliberately consumes text at the existing guest-log boundary.
//! It does not inspect every translated instruction and it does not allocate.
//! Successful translation progress, generation-order contradictions, and
//! unambiguous compiler/code-cache publication failures are kept as separate
//! facts so a slow compiler is not confused with a broken one.

const std = @import("std");

pub const schema_version: u64 = 1;
pub const translation_progress_marker = "READY COMPILER: translation-progress";
pub const mapping_success_marker = "sparse anywhere mmap succeeded";
const guest_address_space_end: u64 = 0x1_0000_0000;

/// The compiler's startup chatter is not the same evidence as a compiler
/// failure.  In particular, Xenia can print diagnostics while it is still
/// creating MAP_JIT-compatible trampoline and code-cache storage.  The ledger
/// keeps that settling interval explicit so a configuration dump cannot poison
/// the verdict, while a real failure in the host-support path remains fatal
/// immediately.
pub const Phase = enum(u8) {
    startup,
    infrastructure_ready,
    translation_active,
    faulted,

    pub fn label(self: Phase) []const u8 {
        return switch (self) {
            .startup => "startup",
            .infrastructure_ready => "infrastructure_ready",
            .translation_active => "translation_active",
            .faulted => "faulted",
        };
    }
};

pub const Finding = enum(u8) {
    none,
    label_reference,
    compile_failure,
    code_cache_failure,
    executable_publication_failure,
    jit_support_failure,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .none => "NONE",
            .label_reference => "LABEL_REFERENCE",
            .compile_failure => "COMPILE_FAILURE",
            .code_cache_failure => "CODE_CACHE_FAILURE",
            .executable_publication_failure => "EXECUTABLE_PUBLICATION_FAILURE",
            .jit_support_failure => "JIT_SUPPORT_FAILURE",
        };
    }

    pub fn fatal(self: Finding) bool {
        return self != .none;
    }

    /// Failures in the host-support layer are actionable before Xenia has
    /// reached its normal ready boundary.  A generic compiler diagnostic during
    /// that interval is retained separately because Xenia emits setup chatter
    /// before MAP_JIT/code-cache support has settled.
    pub fn fatalBeforeReady(self: Finding) bool {
        return switch (self) {
            .none, .compile_failure => false,
            .label_reference, .code_cache_failure, .executable_publication_failure, .jit_support_failure => true,
        };
    }
};

pub const EventKind = enum(u8) {
    none,
    translation_progress,
    translation_replay,
    translation_generation_regression,
    compiler_diagnostic,

    pub fn label(self: EventKind) []const u8 {
        return switch (self) {
            .none => "NONE",
            .translation_progress => "TRANSLATION_PROGRESS",
            .translation_replay => "TRANSLATION_REPLAY",
            .translation_generation_regression => "TRANSLATION_GENERATION_REGRESSION",
            .compiler_diagnostic => "COMPILER_DIAGNOSTIC",
        };
    }
};

pub const Verdict = enum(u8) {
    unobserved,
    healthy,
    degraded,
    faulted,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .healthy => "healthy",
            .degraded => "degraded",
            .faulted => "faulted",
        };
    }
};

pub const TranslationProgress = struct {
    schema: u64,
    generation: u64,
    guest_function: u64,

    pub fn valid(self: TranslationProgress) bool {
        return self.schema == schema_version and
            self.generation != 0 and
            self.guest_function != 0 and
            self.guest_function & 3 == 0;
    }
};

pub const Observation = struct {
    event: EventKind = .none,
    finding: Finding = .none,
    generation: u64 = 0,
    guest_function: u64 = 0,
    /// The exact physical line that produced the observation.  Guest log
    /// messages may contain a complete multi-line config dump; returning this
    /// slice prevents the diagnostic from pointing at the dump header instead
    /// of the offending compiler line.
    line: []const u8 = "",
    fatal: bool = false,
    startup_suppressed: bool = false,
    phase: Phase = .startup,
};

pub const Summary = struct {
    observed_lines: u64 = 0,
    translation_progress_events: u64 = 0,
    highest_generation: u64 = 0,
    translation_replays: u64 = 0,
    generation_regressions: u64 = 0,
    label_failures: u64 = 0,
    compile_failures: u64 = 0,
    code_cache_failures: u64 = 0,
    executable_publication_failures: u64 = 0,
    jit_support_failures: u64 = 0,
    mapping_contract_observations: u64 = 0,
    mapping_contract_verified: u64 = 0,
    mapping_contract_violations: u64 = 0,
    map_jit_mappings: u64 = 0,
    map_jit_verified: u64 = 0,
    startup_suppressed_diagnostics: u64 = 0,
    physical_lines: u64 = 0,
    phase: Phase = .startup,
    armed: bool = false,
    armed_step: u64 = 0,
    last_event: EventKind = .none,
    last_event_step: u64 = 0,
    first_finding: Finding = .none,
    first_finding_step: u64 = 0,
    last_finding: Finding = .none,
    last_finding_step: u64 = 0,

    pub fn diagnosticCount(self: Summary) u64 {
        return self.label_failures +|
            self.compile_failures +|
            self.code_cache_failures +|
            self.executable_publication_failures +|
            self.jit_support_failures;
    }

    pub fn verdict(self: Summary) Verdict {
        if (self.diagnosticCount() != 0) return .faulted;
        if (self.generation_regressions != 0 or self.translation_replays != 0) return .degraded;
        if (self.translation_progress_events != 0) return .healthy;
        return .unobserved;
    }

    pub fn hasFatalFinding(self: Summary) bool {
        return self.first_finding.fatal();
    }
};

pub const Ledger = struct {
    observed_lines: u64 = 0,
    translation_progress_events: u64 = 0,
    highest_generation: u64 = 0,
    translation_replays: u64 = 0,
    generation_regressions: u64 = 0,
    label_failures: u64 = 0,
    compile_failures: u64 = 0,
    code_cache_failures: u64 = 0,
    executable_publication_failures: u64 = 0,
    jit_support_failures: u64 = 0,
    mapping_contract_observations: u64 = 0,
    mapping_contract_verified: u64 = 0,
    mapping_contract_violations: u64 = 0,
    map_jit_mappings: u64 = 0,
    map_jit_verified: u64 = 0,
    startup_suppressed_diagnostics: u64 = 0,
    physical_lines: u64 = 0,
    phase: Phase = .startup,
    armed: bool = false,
    armed_step: u64 = 0,
    first_startup_suppressed_step: u64 = 0,
    last_startup_suppressed_step: u64 = 0,
    last_event: EventKind = .none,
    last_event_step: u64 = 0,
    first_finding: Finding = .none,
    first_finding_step: u64 = 0,
    last_finding: Finding = .none,
    last_finding_step: u64 = 0,

    /// Mark the point at which Xenia's host JIT contract is usable.  This is
    /// monotone: once translation is active, a later informational line cannot
    /// reopen the startup window.
    pub fn arm(self: *Ledger, step: u64) void {
        if (self.phase == .faulted) return;
        if (!self.armed) {
            self.armed = true;
            self.armed_step = step;
            self.phase = .infrastructure_ready;
        }
    }

    pub fn isArmed(self: *const Ledger) bool {
        return self.armed;
    }

    /// Observe one guest-log message.  Xenia's config dump and a few compiler
    /// reports are emitted as one message containing many physical lines, so
    /// classification must happen per line rather than over the whole blob.
    pub fn observe(self: *Ledger, line: []const u8, step: u64) Observation {
        self.observed_lines +|= 1;
        var observation: Observation = .{ .phase = self.phase };
        var cursor: usize = 0;
        while (true) {
            const end = std.mem.indexOfScalarPos(u8, line, cursor, '\n') orelse line.len;
            var physical = line[cursor..end];
            if (physical.len != 0 and physical[physical.len - 1] == '\r') {
                physical = physical[0 .. physical.len - 1];
            }
            if (physical.len != 0) {
                self.physical_lines +|= 1;
                const one = self.observeLine(physical, step);
                if (one.finding != .none) {
                    // A finding is more important than a progress marker in a
                    // message that happened to contain both.  Preserve a
                    // fatal finding over later startup-suppressed chatter: a
                    // multiline host diagnostic must never be downgraded by
                    // the config text that follows it.
                    // A structural JIT-support violation is stronger than a
                    // later generic compiler label as well: its physical line
                    // contains the exact contradictory mapping claim that
                    // caused termination.
                    const existing_structural_fault = observation.fatal and observation.finding == .jit_support_failure;
                    if (!existing_structural_fault and (one.fatal or observation.finding == .none)) {
                        observation = one;
                    }
                } else if (observation.finding == .none and one.event != .none) {
                    observation = one;
                }
            }
            if (end == line.len) break;
            cursor = end + 1;
        }
        observation.phase = self.phase;
        return observation;
    }

    /// Feed a host-side failure that never crosses the guest log boundary,
    /// such as Rosette's sparse MAP_JIT emulation or an mprotect failure.  It
    /// uses the same ledger and fatal path as an explicit Xenia diagnostic.
    pub fn observeHostFailure(
        self: *Ledger,
        finding: Finding,
        line: []const u8,
        step: u64,
    ) Observation {
        var observation = Observation{
            .finding = finding,
            .line = line,
            .fatal = finding.fatalBeforeReady() or self.armed,
            .phase = self.phase,
        };
        if (observation.fatal) {
            self.recordFinding(finding, step);
            observation.event = .compiler_diagnostic;
            self.last_event = .compiler_diagnostic;
            self.last_event_step = step;
        } else {
            self.recordStartupSuppressed(step);
            observation.startup_suppressed = true;
        }
        observation.phase = self.phase;
        return observation;
    }

    fn observeLine(self: *Ledger, line: []const u8, step: u64) Observation {
        var observation: Observation = .{ .phase = self.phase };

        if (isInfrastructureReadyLine(line)) self.arm(step);

        if (parseTranslationProgress(line)) |progress| {
            // A valid translation-progress record is stronger than a startup
            // banner: it proves the compiler produced a usable translation.
            self.arm(step);
            if (self.phase != .faulted) self.phase = .translation_active;
            observation.generation = progress.generation;
            observation.guest_function = progress.guest_function;
            if (self.highest_generation == 0 or progress.generation > self.highest_generation) {
                self.highest_generation = progress.generation;
                self.translation_progress_events +|= 1;
                observation.event = .translation_progress;
            } else if (progress.generation == self.highest_generation) {
                self.translation_replays +|= 1;
                observation.event = .translation_replay;
            } else {
                self.generation_regressions +|= 1;
                observation.event = .translation_generation_regression;
            }
            self.last_event = observation.event;
            self.last_event_step = step;
        }

        const mapping_violation = self.observeMappingContract(line, step);
        if (mapping_violation) {
            observation = .{
                .event = .compiler_diagnostic,
                .finding = .jit_support_failure,
                .line = line,
                .fatal = true,
                .phase = self.phase,
            };
        }

        if (classifyFinding(line)) |finding| {
            var classified = Observation{
                .event = .compiler_diagnostic,
                .finding = finding,
                .line = line,
                .fatal = finding.fatalBeforeReady() or self.armed,
                .phase = self.phase,
            };
            if (classified.fatal) {
                self.recordFinding(finding, step);
                self.last_event = .compiler_diagnostic;
                self.last_event_step = step;
                classified.phase = self.phase;
            } else {
                self.recordStartupSuppressed(step);
                classified.startup_suppressed = true;
            }
            // A structurally invalid successful mapping is the stronger fact
            // on a line that also happens to contain generic compiler words.
            // Never downgrade it to the text classifier's less-specific kind.
            if (!mapping_violation and (observation.finding == .none or classified.fatal)) observation = classified;
        }
        observation.phase = self.phase;
        return observation;
    }

    pub fn summary(self: *const Ledger) Summary {
        return .{
            .observed_lines = self.observed_lines,
            .translation_progress_events = self.translation_progress_events,
            .highest_generation = self.highest_generation,
            .translation_replays = self.translation_replays,
            .generation_regressions = self.generation_regressions,
            .label_failures = self.label_failures,
            .compile_failures = self.compile_failures,
            .code_cache_failures = self.code_cache_failures,
            .executable_publication_failures = self.executable_publication_failures,
            .jit_support_failures = self.jit_support_failures,
            .mapping_contract_observations = self.mapping_contract_observations,
            .mapping_contract_verified = self.mapping_contract_verified,
            .mapping_contract_violations = self.mapping_contract_violations,
            .map_jit_mappings = self.map_jit_mappings,
            .map_jit_verified = self.map_jit_verified,
            .startup_suppressed_diagnostics = self.startup_suppressed_diagnostics,
            .physical_lines = self.physical_lines,
            .phase = self.phase,
            .armed = self.armed,
            .armed_step = self.armed_step,
            .last_event = self.last_event,
            .last_event_step = self.last_event_step,
            .first_finding = self.first_finding,
            .first_finding_step = self.first_finding_step,
            .last_finding = self.last_finding,
            .last_finding_step = self.last_finding_step,
        };
    }

    fn recordFinding(self: *Ledger, finding: Finding, step: u64) void {
        switch (finding) {
            .none => unreachable,
            .label_reference => self.label_failures +|= 1,
            .compile_failure => self.compile_failures +|= 1,
            .code_cache_failure => self.code_cache_failures +|= 1,
            .executable_publication_failure => self.executable_publication_failures +|= 1,
            .jit_support_failure => self.jit_support_failures +|= 1,
        }
        self.phase = .faulted;
        if (self.first_finding == .none) {
            self.first_finding = finding;
            self.first_finding_step = step;
        }
        self.last_finding = finding;
        self.last_finding_step = step;
    }

    fn recordStartupSuppressed(self: *Ledger, step: u64) void {
        self.startup_suppressed_diagnostics +|= 1;
        if (self.first_startup_suppressed_step == 0) self.first_startup_suppressed_step = step;
        self.last_startup_suppressed_step = step;
    }

    /// Validate the metadata Rosette emits after a sparse guest mapping.  A
    /// successful host call is not enough for the x86 JIT contract: the guest
    /// address window, alias, flags, and protection model must describe the
    /// same mapping that the interpreter will later consume.  Returning false
    /// means the line was either not a mapping breadcrumb or was coherent;
    /// returning true means a typed JIT support fault was recorded.
    fn observeMappingContract(self: *Ledger, line: []const u8, step: u64) bool {
        if (!contains(line, mapping_success_marker)) return false;
        self.mapping_contract_observations +|= 1;

        const guest_base = field(line, "guest_base=") orelse return self.recordMappingViolation(step);
        const guest_end = field(line, "guest_end=") orelse return self.recordMappingViolation(step);
        const host_base = field(line, "host_base=") orelse return self.recordMappingViolation(step);
        const requested_length = field(line, "requested_length=") orelse return self.recordMappingViolation(step);
        const effective_length = field(line, "effective_length=") orelse return self.recordMappingViolation(step);
        const guest_prot = field(line, "guest_prot=") orelse return self.recordMappingViolation(step);
        const host_prot = field(line, "host_prot=") orelse return self.recordMappingViolation(step);
        const guest_flags = field(line, "guest_flags=") orelse return self.recordMappingViolation(step);
        const guest_address_contract_honored = boolField(line, "guest_address_contract_honored=") orelse return self.recordMappingViolation(step);
        const guest_host_alias = boolField(line, "guest_host_alias=") orelse return self.recordMappingViolation(step);
        const low_window_required = boolField(line, "low_window_required=") orelse return self.recordMappingViolation(step);
        const map_jit_emulated = boolField(line, "map_jit_emulated=") orelse return self.recordMappingViolation(step);
        const host_execute = boolField(line, "host_execute=") orelse return self.recordMappingViolation(step);

        if (map_jit_emulated) self.map_jit_mappings +|= 1;

        const end_matches_length = guest_end == guest_base +| effective_length;
        const length_is_sufficient = effective_length >= requested_length;
        const host_alias_exists = host_base != 0;
        const guest_window_is_low = guest_base < guest_address_space_end and
            guest_end <= guest_address_space_end and
            guest_end > guest_base;
        const low_window_is_faithful = !low_window_required or
            (guest_address_contract_honored and guest_host_alias and guest_window_is_low);
        const map_jit_is_faithful = !map_jit_emulated or
            (guest_address_contract_honored and
                low_window_required and
                guest_host_alias and
                guest_prot & 4 != 0 and
                guest_flags & 0x800 != 0 and
                host_prot & 4 == 0);

        // Rosette interprets the x86 code cache. If the mapping claims that
        // the host will execute it, the contract has crossed into native x86
        // execution and the run must stop before that code is called.
        if (!end_matches_length or
            !length_is_sufficient or
            !host_alias_exists or
            !low_window_is_faithful or
            !map_jit_is_faithful or
            host_execute)
        {
            return self.recordMappingViolation(step);
        }

        self.mapping_contract_verified +|= 1;
        if (map_jit_emulated) self.map_jit_verified +|= 1;
        return false;
    }

    fn recordMappingViolation(self: *Ledger, step: u64) bool {
        self.mapping_contract_violations +|= 1;
        self.recordFinding(.jit_support_failure, step);
        self.last_event = .compiler_diagnostic;
        self.last_event_step = step;
        return true;
    }
};

pub fn parseTranslationProgress(line: []const u8) ?TranslationProgress {
    if (std.ascii.indexOfIgnoreCase(line, translation_progress_marker) == null) return null;
    const progress = TranslationProgress{
        .schema = field(line, "schema=") orelse return null,
        .generation = field(line, "generation=") orelse return null,
        .guest_function = field(line, "guest_function=") orelse return null,
    };
    return if (progress.valid()) progress else null;
}

fn classifyFinding(line: []const u8) ?Finding {
    const has_label_failure = contains(line, "undefined label") or
        contains(line, "label is not found") or
        contains(line, "label reference is invalid");
    if (has_label_failure) return .label_reference;

    const has_code_cache = contains(line, "code cache") or
        contains(line, "code-cache") or
        contains(line, "codecache") or
        contains(line, "commit executable range");
    const has_executable_publication = contains(line, "executable range") or
        contains(line, "executable memory") or
        contains(line, "publish executable") or
        contains(line, "publish code") or
        contains(line, "protect code cache");
    const has_map_jit = contains(line, "map_jit") or
        (contains(line, "writable") and contains(line, "executable") and contains(line, "memory"));
    const has_jit_context = contains(line, "xbyak") or
        contains(line, "codegen") or
        contains(line, "jit") or
        contains(line, "translation") or
        contains(line, "compile");
    const has_failure = contains(line, "failed") or
        contains(line, "failure") or
        contains(line, "fatal") or
        contains(line, "error") or
        contains(line, "assert") or
        contains(line, "out of memory") or
        contains(line, "could not") or
        contains(line, "cannot") or
        contains(line, "unable") or
        contains(line, "unavailable") or
        contains(line, "unsupported") or
        contains(line, "not supported") or
        contains(line, "permission denied") or
        contains(line, "operation not permitted") or
        contains(line, "overflow");

    if (has_map_jit and has_failure) return .jit_support_failure;
    if (has_executable_publication and has_failure) return .executable_publication_failure;
    if (has_code_cache and has_failure) return .code_cache_failure;
    if (has_jit_context and has_failure) return .compile_failure;
    if (contains(line, "function left undefined")) return .compile_failure;
    return null;
}

fn isInfrastructureReadyLine(line: []const u8) bool {
    return contains(line, "JIT Infrastructure initialized successfully") or
        contains(line, "code cache initialized successfully") or
        contains(line, "code cache available") or
        contains(line, "Processor::Setup() completed successfully");
}

fn contains(line: []const u8, needle: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(line, needle) != null;
}

fn field(line: []const u8, key: []const u8) ?u64 {
    var search: usize = 0;
    while (search < line.len) {
        const relative = std.ascii.indexOfIgnoreCase(line[search..], key) orelse return null;
        const found = search + relative;
        search = found + key.len;
        if (found != 0 and line[found - 1] > ' ') continue;
        const start = found + key.len;
        var end = start;
        while (end < line.len and line[end] > ' ') end += 1;
        if (end == start) return null;
        const value = line[start..end];
        if (value.len > 2 and value[0] == '0' and
            (value[1] == 'x' or value[1] == 'X'))
        {
            return std.fmt.parseInt(u64, value[2..], 16) catch return null;
        }
        return std.fmt.parseInt(u64, value, 10) catch return null;
    }
    return null;
}

fn boolField(line: []const u8, key: []const u8) ?bool {
    var search: usize = 0;
    while (search < line.len) {
        const relative = std.ascii.indexOfIgnoreCase(line[search..], key) orelse return null;
        const found = search + relative;
        search = found + key.len;
        if (found != 0 and line[found - 1] > ' ') continue;
        const value = line[found + key.len ..];
        if (value.len >= 4 and std.ascii.eqlIgnoreCase(value[0..4], "true")) return true;
        if (value.len >= 5 and std.ascii.eqlIgnoreCase(value[0..5], "false")) return false;
        return null;
    }
    return null;
}

test "JIT health recognizes valid translation progress" {
    const event = parseTranslationProgress(
        "[xenia] i> READY COMPILER: translation-progress schema=1 generation=8 guest_function=0x82582cc8\n",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 8), event.generation);
    try std.testing.expectEqual(@as(u64, 0x8258_2cc8), event.guest_function);
}

test "JIT health rejects malformed progress" {
    try std.testing.expect(parseTranslationProgress("translation-progress schema=1 generation=0 guest_function=0x1000") == null);
    try std.testing.expect(parseTranslationProgress("translation-progress schema=2 generation=1 guest_function=0x1000") == null);
    try std.testing.expect(parseTranslationProgress("translation-progress schema=1 generation=1 guest_function=0x1001") == null);
    try std.testing.expect(parseTranslationProgress("translation-progress schema=1 generation=1") == null);
}

test "JIT health tracks monotonic progress and metadata contradictions" {
    var ledger = Ledger{};
    try std.testing.expectEqual(
        EventKind.translation_progress,
        ledger.observe("READY COMPILER: translation-progress schema=1 generation=8 guest_function=0x1000", 10).event,
    );
    try std.testing.expectEqual(
        EventKind.translation_replay,
        ledger.observe("READY COMPILER: translation-progress schema=1 generation=8 guest_function=0x1000", 20).event,
    );
    try std.testing.expectEqual(
        EventKind.translation_generation_regression,
        ledger.observe("READY COMPILER: translation-progress schema=1 generation=7 guest_function=0x1000", 30).event,
    );
    try std.testing.expectEqual(
        EventKind.translation_progress,
        ledger.observe("READY COMPILER: translation-progress schema=1 generation=9 guest_function=0x1004", 40).event,
    );
    const report = ledger.summary();
    try std.testing.expectEqual(@as(u64, 2), report.translation_progress_events);
    try std.testing.expectEqual(@as(u64, 1), report.translation_replays);
    try std.testing.expectEqual(@as(u64, 1), report.generation_regressions);
    try std.testing.expectEqual(Verdict.degraded, report.verdict());
    try std.testing.expect(!report.hasFatalFinding());
}

test "JIT health only marks unambiguous compiler and publication failures" {
    var ledger = Ledger{};
    ledger.arm(0);
    try std.testing.expectEqual(
        Finding.label_reference,
        ledger.observe("Xbyak error: label is not found", 1).finding,
    );
    try std.testing.expectEqual(
        Finding.code_cache_failure,
        ledger.observe("JIT code cache allocation failed", 2).finding,
    );
    try std.testing.expectEqual(
        Finding.executable_publication_failure,
        ledger.observe("failed to publish executable range", 3).finding,
    );
    try std.testing.expectEqual(
        Finding.compile_failure,
        ledger.observe("Xbyak codegen failed for function", 4).finding,
    );
    try std.testing.expectEqual(
        EventKind.none,
        ledger.observe("Xbyak emitter initialized; translation completed", 5).event,
    );
    const report = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), report.label_failures);
    try std.testing.expectEqual(@as(u64, 1), report.compile_failures);
    try std.testing.expectEqual(@as(u64, 1), report.code_cache_failures);
    try std.testing.expectEqual(@as(u64, 1), report.executable_publication_failures);
    try std.testing.expectEqual(Verdict.faulted, report.verdict());
    try std.testing.expect(report.hasFatalFinding());
}

test "JIT health does not classify a multiline config dump" {
    var ledger = Ledger{};
    const observation = ledger.observe(
        "----------- CONFIG DUMP -----------\n[CPU]\nbreak_on_unimplemented_instructions = true\n----------- END OF CONFIG DUMP ----",
        3284716,
    );
    try std.testing.expectEqual(Finding.none, observation.finding);
    try std.testing.expect(!observation.fatal);
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().diagnosticCount());
    try std.testing.expectEqual(@as(u64, 4), ledger.summary().physical_lines);
}

test "JIT health suppresses generic startup compiler chatter until ready" {
    var ledger = Ledger{};
    const startup = ledger.observe("Xbyak compile failed while bootstrap diagnostics are settling", 10);
    try std.testing.expectEqual(Finding.compile_failure, startup.finding);
    try std.testing.expect(startup.startup_suppressed);
    try std.testing.expect(!startup.fatal);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().startup_suppressed_diagnostics);
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().diagnosticCount());

    ledger.arm(20);
    const active = ledger.observe("Xbyak compile failed for guest function", 21);
    try std.testing.expect(active.fatal);
    try std.testing.expect(!active.startup_suppressed);
    try std.testing.expectEqual(Verdict.faulted, ledger.summary().verdict());
}

test "JIT host support failures are fatal before compiler readiness" {
    var ledger = Ledger{};
    const observation = ledger.observe("MAP_JIT allocation failed: operation not permitted", 7);
    try std.testing.expectEqual(Finding.jit_support_failure, observation.finding);
    try std.testing.expect(observation.fatal);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().jit_support_failures);
    try std.testing.expectEqual(Verdict.faulted, ledger.summary().verdict());
}

test "JIT mapping contract accepts Rosette's low-window alias" {
    var ledger = Ledger{};
    const observation = ledger.observe(
        "macho-processor: sparse anywhere mmap succeeded: guest_base=0xa0000000 guest_end=0xb0000000 host_base=0x158000000 requested_length=268435455 effective_length=268435456 guest_address_contract_honored=true guest_host_alias=true low_window_required=true guest_prot=0x7 host_prot=0x3 guest_flags=0x1802 map_jit_emulated=true host_execute=false",
        20,
    );
    try std.testing.expectEqual(Finding.none, observation.finding);
    try std.testing.expect(!observation.fatal);
    const report = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), report.mapping_contract_observations);
    try std.testing.expectEqual(@as(u64, 1), report.mapping_contract_verified);
    try std.testing.expectEqual(@as(u64, 1), report.map_jit_mappings);
    try std.testing.expectEqual(@as(u64, 1), report.map_jit_verified);
}

test "JIT mapping contract rejects native execution claims" {
    var ledger = Ledger{};
    const observation = ledger.observe(
        "macho-processor: sparse anywhere mmap succeeded: guest_base=0xa0000000 guest_end=0xb0000000 host_base=0x158000000 requested_length=268435455 effective_length=268435456 guest_address_contract_honored=true guest_host_alias=true low_window_required=true guest_prot=0x7 host_prot=0x3 guest_flags=0x1802 map_jit_emulated=true host_execute=true",
        21,
    );
    try std.testing.expectEqual(Finding.jit_support_failure, observation.finding);
    try std.testing.expect(observation.fatal);
    const report = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), report.mapping_contract_observations);
    try std.testing.expectEqual(@as(u64, 1), report.mapping_contract_violations);
    try std.testing.expectEqual(Verdict.faulted, report.verdict());
}

test "JIT fatal finding survives later startup-suppressed multiline chatter" {
    var ledger = Ledger{};
    const observation = ledger.observe(
        "MAP_JIT allocation failed: operation not permitted\nXbyak compile failed while bootstrap diagnostics are settling",
        7,
    );
    try std.testing.expectEqual(Finding.jit_support_failure, observation.finding);
    try std.testing.expect(observation.fatal);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().jit_support_failures);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().startup_suppressed_diagnostics);
}

test "JIT mapping violation retains precedence over generic compiler text" {
    var ledger = Ledger{};
    const observation = ledger.observe(
        "macho-processor: sparse anywhere mmap succeeded: guest_base=0xa0000000 guest_end=0xb0000000 host_base=0x158000000 requested_length=268435455 effective_length=268435456 guest_address_contract_honored=true guest_host_alias=true low_window_required=true guest_prot=0x7 host_prot=0x3 guest_flags=0x1802 map_jit_emulated=true host_execute=true Xbyak error: codegen failed",
        22,
    );
    try std.testing.expectEqual(Finding.jit_support_failure, observation.finding);
    try std.testing.expect(observation.fatal);
    try std.testing.expect(std.mem.indexOf(u8, observation.line, "host_execute=true") != null);
}
