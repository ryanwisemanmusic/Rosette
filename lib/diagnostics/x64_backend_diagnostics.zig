const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

pub const Phase = enum {
    not_seen,
    exports,
    jit_infrastructure_ready,
    processor_setup,
    backend_initializing,
    code_cache_creating,
    code_cache_initializing,
    code_cache_degraded,
    code_cache_ready,
    transition_thunks_ready,
    backend_ready,
    processor_ready,
    patcher,
};

pub const Event = enum {
    exports_started,
    jit_infrastructure_ready,
    processor_setup_started,
    backend_initialize_started,
    code_cache_create_started,
    code_cache_initialize_started,
    indirection_table_failed,
    code_cache_initialize_succeeded,
    transition_thunks_succeeded,
    backend_initialize_succeeded,
    processor_setup_succeeded,
    patcher_started,
};

pub const Observation = struct {
    sequence: u64,
    event: Event,
    previous_phase: Phase,
    phase: Phase,
    step: u64,
    delta_steps: u64,
};

pub const AssertionBinding = enum {
    none,
    x64_backend_capstone,
    x64_backend_low32_thunk,
    x64_backend_other,
};

pub const MappingAttempt = struct {
    valid: bool = false,
    route: []const u8 = "",
    address: u64 = 0,
    length: u64 = 0,
    prot: u64 = 0,
    flags: u64 = 0,
    fixed: bool = false,
    anonymous: bool = false,
    step: u64 = 0,
    result_known: bool = false,
    succeeded: bool = false,
    result: u64 = 0,
    stage: []const u8 = "",
};

pub const Engine = struct {
    phase: Phase = .not_seen,
    event_sequence: u64 = 0,
    last_event_step: u64 = 0,
    assertions: u64 = 0,
    backend_assertions: u64 = 0,
    capstone_assertions: u64 = 0,
    low32_thunk_assertions: u64 = 0,
    correlated_signal_deliveries: u64 = 0,
    correlated_signal_returns: u64 = 0,
    indirection_table_failures: u64 = 0,
    code_cache_successes: u64 = 0,
    backend_successes: u64 = 0,
    processor_successes: u64 = 0,
    mmap_attempts_during_backend: u64 = 0,
    mprotect_attempts_during_backend: u64 = 0,
    last_backend_assertion_step: u64 = 0,
    last_backend_assertion_rip: u64 = 0,
    last_backend_assertion_binding: AssertionBinding = .none,
    last_mapping: MappingAttempt = .{},

    pub fn observeLine(self: *Engine, line: []const u8, step: u64) ?Observation {
        const classified = classifyLine(line) orelse return null;
        const previous = self.phase;
        self.phase = classified.phase;
        self.event_sequence +|= 1;
        const delta = if (self.last_event_step == 0) 0 else step -| self.last_event_step;
        self.last_event_step = step;
        switch (classified.event) {
            .indirection_table_failed => self.indirection_table_failures +|= 1,
            .code_cache_initialize_succeeded => self.code_cache_successes +|= 1,
            .backend_initialize_succeeded => self.backend_successes +|= 1,
            .processor_setup_succeeded => self.processor_successes +|= 1,
            else => {},
        }
        return .{
            .sequence = self.event_sequence,
            .event = classified.event,
            .previous_phase = previous,
            .phase = self.phase,
            .step = step,
            .delta_steps = delta,
        };
    }

    pub fn classifyAssertion(file: []const u8, line: u64, function: []const u8) AssertionBinding {
        const backend_file = std.mem.indexOf(u8, file, "x64_backend") != null;
        const backend_function = std.mem.indexOf(u8, function, "X64Backend") != null;
        const assembler_file = std.mem.endsWith(u8, file, "x64_assembler.cc");
        const assembler_function = std.mem.indexOf(u8, function, "X64Assembler") != null;
        if (!backend_file and !backend_function and !assembler_file and !assembler_function) return .none;
        if (std.mem.endsWith(u8, file, "x64_backend_mac.cc") and line == 139) {
            return .x64_backend_capstone;
        }
        // Older macOS-port builds asserted directly on cs_open in the
        // assembler constructor. Keep a small line window because local
        // diagnostic edits shift this site without changing its meaning.
        if (assembler_file and assembler_function and line >= 38 and line <= 55) {
            return .x64_backend_capstone;
        }
        if (std.mem.endsWith(u8, file, "x64_backend_mac.cc") and line == 438) {
            return .x64_backend_low32_thunk;
        }
        return .x64_backend_other;
    }

    pub fn noteAssertion(self: *Engine, binding: AssertionBinding, step: u64, rip: u64) void {
        self.assertions +|= 1;
        if (binding == .none) return;
        self.backend_assertions +|= 1;
        if (binding == .x64_backend_capstone) self.capstone_assertions +|= 1;
        if (binding == .x64_backend_low32_thunk) self.low32_thunk_assertions +|= 1;
        self.last_backend_assertion_step = step;
        self.last_backend_assertion_rip = rip;
        self.last_backend_assertion_binding = binding;
    }

    pub fn signalCorrelates(self: *const Engine, step: u64, fault_rip: u64) bool {
        if (self.last_backend_assertion_binding == .none) return false;
        if (step -| self.last_backend_assertion_step > 4096) return false;
        return self.signalFaultMatches(fault_rip);
    }

    pub fn signalReturnCorrelates(self: *const Engine, fault_rip: u64) bool {
        if (self.correlated_signal_deliveries <= self.correlated_signal_returns) return false;
        return self.signalFaultMatches(fault_rip);
    }

    fn signalFaultMatches(self: *const Engine, fault_rip: u64) bool {
        const distance = if (fault_rip >= self.last_backend_assertion_rip)
            fault_rip - self.last_backend_assertion_rip
        else
            self.last_backend_assertion_rip - fault_rip;
        return distance <= 64;
    }

    pub fn noteSignalDelivery(self: *Engine) void {
        self.correlated_signal_deliveries +|= 1;
    }

    pub fn noteSignalReturn(self: *Engine) void {
        self.correlated_signal_returns +|= 1;
    }

    pub fn mappingWindowActive(self: *const Engine) bool {
        return switch (self.phase) {
            .backend_initializing, .code_cache_creating, .code_cache_initializing, .code_cache_degraded, .code_cache_ready, .transition_thunks_ready => true,
            else => false,
        };
    }

    pub fn noteMmapAttempt(
        self: *Engine,
        route: []const u8,
        address: u64,
        length: u64,
        prot: u64,
        flags: u64,
        fixed: bool,
        anonymous: bool,
        step: u64,
    ) bool {
        const code_cache_hint = address >= 0x8000_0000 and address < 0xA000_0000;
        if (!self.mappingWindowActive() and !code_cache_hint) return false;
        self.mmap_attempts_during_backend +|= 1;
        self.last_mapping = .{
            .valid = true,
            .route = route,
            .address = address,
            .length = length,
            .prot = prot,
            .flags = flags,
            .fixed = fixed,
            .anonymous = anonymous,
            .step = step,
        };
        return true;
    }

    pub fn noteMmapResult(self: *Engine, succeeded: bool, result: u64, stage: []const u8) void {
        if (!self.last_mapping.valid) return;
        self.last_mapping.result_known = true;
        self.last_mapping.succeeded = succeeded;
        self.last_mapping.result = result;
        self.last_mapping.stage = stage;
    }

    pub fn noteMprotectAttempt(self: *Engine) bool {
        if (!self.mappingWindowActive()) return false;
        self.mprotect_attempts_during_backend +|= 1;
        return true;
    }

    pub fn verdict(self: *const Engine) []const u8 {
        if (self.processor_successes != 0 and self.indirection_table_failures != 0) {
            return "backend initialized; indirection table unavailable; processor continued in degraded configuration";
        }
        if (self.backend_successes != 0) return "x64 backend initialized successfully";
        if (self.backend_assertions != 0) return "x64 backend assertion observed before readiness was proven";
        return "x64 backend readiness not observed";
    }

    pub fn logSummary(self: *const Engine) void {
        if (self.phase == .not_seen and self.assertions == 0) return;
        machoCapturePrint(
            "macho-processor: x64 backend diagnostics summary: phase={s} events={d} assertions(total/backend/capstone/low32_thunk)={d}/{d}/{d}/{d} signal(delivered/returned)={d}/{d} code_cache(indirection_failures/successes)={d}/{d} backend_successes={d} processor_successes={d} memory_ops(mmap/mprotect)={d}/{d} verdict={s}\n",
            .{
                @tagName(self.phase),
                self.event_sequence,
                self.assertions,
                self.backend_assertions,
                self.capstone_assertions,
                self.low32_thunk_assertions,
                self.correlated_signal_deliveries,
                self.correlated_signal_returns,
                self.indirection_table_failures,
                self.code_cache_successes,
                self.backend_successes,
                self.processor_successes,
                self.mmap_attempts_during_backend,
                self.mprotect_attempts_during_backend,
                self.verdict(),
            },
        );
        if (self.last_mapping.valid) {
            machoCapturePrint(
                "macho-processor: x64 backend last mmap: route={s} step={d} address=0x{x} length={d} prot=0x{x} flags=0x{x} fixed={} anonymous={} result_known={} succeeded={} result=0x{x} stage={s}\n",
                .{
                    self.last_mapping.route,
                    self.last_mapping.step,
                    self.last_mapping.address,
                    self.last_mapping.length,
                    self.last_mapping.prot,
                    self.last_mapping.flags,
                    self.last_mapping.fixed,
                    self.last_mapping.anonymous,
                    self.last_mapping.result_known,
                    self.last_mapping.succeeded,
                    self.last_mapping.result,
                    if (self.last_mapping.stage.len != 0) self.last_mapping.stage else "<pending>",
                },
            );
        }
    }
};

const ClassifiedLine = struct {
    event: Event,
    phase: Phase,
};

fn classifyLine(line: []const u8) ?ClassifiedLine {
    if (contains(line, "Setup: Initializing Exports")) return .{ .event = .exports_started, .phase = .exports };
    if (contains(line, "JIT Infrastructure initialized successfully")) return .{ .event = .jit_infrastructure_ready, .phase = .jit_infrastructure_ready };
    if (contains(line, "Processor::Setup() starting")) return .{ .event = .processor_setup_started, .phase = .processor_setup };
    if (contains(line, "X64Backend::Initialize() starting")) return .{ .event = .backend_initialize_started, .phase = .backend_initializing };
    if (contains(line, "X64Backend::Initialize() creating code cache")) return .{ .event = .code_cache_create_started, .phase = .code_cache_creating };
    if (contains(line, "X64Backend::Initialize() initializing code cache")) return .{ .event = .code_cache_initialize_started, .phase = .code_cache_initializing };
    if (contains(line, "Unable to allocate code cache indirection table")) return .{ .event = .indirection_table_failed, .phase = .code_cache_degraded };
    if (contains(line, "X64Backend::Initialize() code cache initialized successfully")) return .{ .event = .code_cache_initialize_succeeded, .phase = .code_cache_ready };
    if (contains(line, "transition thunks generated successfully")) return .{ .event = .transition_thunks_succeeded, .phase = .transition_thunks_ready };
    if (contains(line, "X64Backend::Initialize() completed successfully")) return .{ .event = .backend_initialize_succeeded, .phase = .backend_ready };
    if (contains(line, "Processor::Setup() completed successfully")) return .{ .event = .processor_setup_succeeded, .phase = .processor_ready };
    if (contains(line, "Setup: Creating patcher")) return .{ .event = .patcher_started, .phase = .patcher };
    return null;
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "backend timeline distinguishes degraded code cache from missing backend" {
    var engine = Engine{};
    _ = engine.observeLine("X64Backend::Initialize() starting...", 100).?;
    _ = engine.observeLine("X64Backend::Initialize() initializing code cache...", 200).?;
    try std.testing.expect(engine.noteMmapAttempt("import", 0, 512 * 1024 * 1024, 3, 0x1002, false, true, 220));
    engine.noteMmapResult(false, 0, "guest_heap_allocate");
    _ = engine.observeLine("Unable to allocate code cache indirection table", 250).?;
    _ = engine.observeLine("X64Backend::Initialize() code cache initialized successfully", 300).?;
    _ = engine.observeLine("X64Backend::Initialize() completed successfully!", 400).?;
    _ = engine.observeLine("Processor::Setup() completed successfully!", 500).?;

    try std.testing.expectEqual(@as(u64, 1), engine.indirection_table_failures);
    try std.testing.expectEqual(@as(u64, 1), engine.code_cache_successes);
    try std.testing.expectEqual(Phase.processor_ready, engine.phase);
    try std.testing.expect(std.mem.indexOf(u8, engine.verdict(), "degraded") != null);
}

test "mac backend line 139 binds to capstone initialization" {
    try std.testing.expectEqual(
        AssertionBinding.x64_backend_capstone,
        Engine.classifyAssertion("x64_backend_mac.cc", 139, "X64Backend"),
    );
    try std.testing.expectEqual(
        AssertionBinding.none,
        Engine.classifyAssertion("patch_db.cc", 86, "ReadPatchFile"),
    );

    var engine = Engine{};
    engine.noteAssertion(.x64_backend_capstone, 100, 0xDA80E1);
    try std.testing.expect(engine.signalCorrelates(120, 0xDA80DF));
    engine.noteSignalDelivery();
    try std.testing.expect(engine.signalReturnCorrelates(0xDA80DF));
    engine.noteSignalReturn();
    try std.testing.expect(!engine.signalReturnCorrelates(0xDA80DF));
}

test "x64 assembler constructor assertion binds to capstone initialization" {
    try std.testing.expectEqual(
        AssertionBinding.x64_backend_capstone,
        Engine.classifyAssertion("x64_assembler.cc", 42, "X64Assembler"),
    );
    try std.testing.expectEqual(
        AssertionBinding.x64_backend_capstone,
        Engine.classifyAssertion("/src/xenia/cpu/backend/x64/x64_assembler.cc", 48, "X64Assembler"),
    );
}

test "mac backend line 438 binds to low 32-bit thunk placement" {
    try std.testing.expectEqual(
        AssertionBinding.x64_backend_low32_thunk,
        Engine.classifyAssertion("x64_backend_mac.cc", 438, "Initialize"),
    );
}
