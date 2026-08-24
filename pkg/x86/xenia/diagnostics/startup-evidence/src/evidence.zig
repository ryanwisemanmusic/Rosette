//! A bounded parser for the Xenia Ready Compiler and graphics evidence logs.
//!
//! This package deliberately consumes evidence instead of changing it. A
//! parsed frontier is a finding; it is never an instruction to force the
//! missing stage or fabricate a presentation event.
//!
//! The stage vocabulary and the parse rules are the same on every route,
//! because they describe the Ready Compiler's contract rather than the host
//! that runs it. Only the route identity below differs, and a route must be
//! fed its own logs: an x86 verdict is not an ARM64 result.

const std = @import("std");

pub const host_architecture = "x86_64";
pub const host_codegen = "xbyak-x86_64";

pub const Stage = enum(u8) {
    image_ready,
    compile_ready,
    static_initializers_complete,
    emulator_setup_started,
    memory_ready,
    processor_ready,
    patch_database_ready,
    kernel_globals_started,
    kernel_globals_ready,
    kernel_modules_ready,
    graphics_setup_started,
    command_processor_ready,
    graphics_ready,
    emulator_setup_ready,
    launch_path_started,
    disc_mounted,
    complete_launch_started,
    user_module_loaded,
    precompile_requested,
    precompile_completed,
    user_module_ready,
    shader_storage_requested,
    shader_storage_ready,
    guest_main_ready,
    complete_launch_ready,
    ring_buffer_ready,
    surface_ready,
    guest_output_ready,
    first_present,
    guest_vdswap_entered,
    guest_swap_packet_encoded,
    guest_vdswap_completed,
    guest_swap_published,
    authentic_swap_consumed,
    authentic_refresh_succeeded,
    authentic_native_presented,

    pub fn label(self: Stage) []const u8 {
        return @tagName(self);
    }
};

const ordered_stages = [_]Stage{
    .image_ready,
    .compile_ready,
    .static_initializers_complete,
    .emulator_setup_started,
    .memory_ready,
    .processor_ready,
    .patch_database_ready,
    .kernel_globals_started,
    .kernel_globals_ready,
    .kernel_modules_ready,
    .graphics_setup_started,
    .command_processor_ready,
    .graphics_ready,
    .emulator_setup_ready,
    .launch_path_started,
    .disc_mounted,
    .complete_launch_started,
    .user_module_loaded,
    .precompile_requested,
    .precompile_completed,
    .user_module_ready,
    .shader_storage_requested,
    .shader_storage_ready,
    .guest_main_ready,
    .complete_launch_ready,
    .ring_buffer_ready,
    .surface_ready,
    .guest_output_ready,
    .guest_vdswap_entered,
    .guest_swap_packet_encoded,
    .guest_vdswap_completed,
    .guest_swap_published,
    .authentic_swap_consumed,
    .authentic_refresh_succeeded,
    .authentic_native_presented,
};

pub const required_stage_count: u8 = @intCast(ordered_stages.len);

fn bit(stage: Stage) u64 {
    return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage)));
}

pub fn stageFromName(name: []const u8) ?Stage {
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

pub const Verdict = enum {
    compile_not_green,
    before_user_module,
    graphics_owner_silent,
    no_guest_swap,
    not_presented,
    authentic_frame,

    pub fn label(self: Verdict) []const u8 {
        return @tagName(self);
    }
};

pub const Report = struct {
    reached_mask: u64 = 0,
    accepted_stage_events: u32 = 0,
    package_hit: bool = false,
    package_store: bool = false,
    compile_green: bool = false,
    compile_unknown: u32 = 0,
    contract_blocks_reached: u8 = 0,
    contract_blocks_total: u8 = required_stage_count,
    contract_edges_reached: u8 = 0,
    blocked_kind: []const u8 = "",
    blocked_owner: []const u8 = "",
    blocked_stage: ?Stage = null,
    blocked_step: u64 = 0,
    activation_budget_steps: u64 = 0,
    activation_budget_unlimited: bool = false,
    last_progress_step: u64 = 0,
    precompile_cost_steps: u64 = 0,
    slow_progress_notices: u32 = 0,
    spin_verdict: []const u8 = "",
    scheduler_runnable: u32 = 0,
    scheduler_parked: u32 = 0,
    wait_notifications: u64 = 0,
    wait_consumption_warning: bool = false,
    tracepoints_armed: u32 = 0,
    tracepoints_unresolved: u32 = 0,
    swap_tracepoints: u32 = 0,
    swap_hits: u64 = 0,
    preinit_established: u32 = 0,
    preinit_total: u32 = 0,
    kernel_variables_imported: u32 = 0,
    kernel_variables_usable: u32 = 0,
    kernel_variable_writes: u32 = 0,
    guest_vulkan_calls: u64 = 0,
    native_submissions: u64 = 0,
    native_present_requests: u64 = 0,
    guest_output_frames: u64 = 0,
    gpu_aperture_reads: u64 = 0,
    gpu_aperture_writes: u64 = 0,
    vulkan_tier_consistent: bool = false,
    active_threads: u32 = 0,
    parked_threads: u32 = 0,
    ring_writes: u64 = 0,
    ring_advances: u64 = 0,
    lines_seen: u64 = 0,

    pub fn observeLine(self: *Report, line: []const u8) void {
        self.lines_seen +|= 1;

        if (std.mem.indexOf(u8, line, "READY COMPILER: package HIT") != null) self.package_hit = true;
        if (std.mem.indexOf(u8, line, "READY COMPILER: package STORE") != null) self.package_store = true;
        if (std.mem.indexOf(u8, line, "READY COMPILER: compile plan GREEN") != null) self.compile_green = true;

        if (token(line, "stage name=")) |name| {
            if (std.mem.indexOf(u8, line, "accepted=true") != null) self.observeStage(name);
        }
        if (std.mem.indexOf(u8, line, "READY COMPILER: report stage ") != null and
            std.mem.indexOf(u8, line, "reached=true") != null)
        {
            if (token(line, "name=")) |name| self.observeStage(name);
        }

        if (std.mem.indexOf(u8, line, "READY COMPILER: BLOCKED") != null) {
            self.blocked_kind = token(line, "kind=") orelse self.blocked_kind;
            if (token(line, "stage=")) |name| self.blocked_stage = stageFromName(name);
            if (token(line, "step=")) |value| self.blocked_step = parseUnsigned(value) orelse self.blocked_step;
        }

        if (std.mem.indexOf(u8, line, "DIAGNOSIS progress=") != null) {
            if (std.mem.indexOf(u8, line, "blockage=OWNER_SILENT") != null) {
                self.blocked_owner = token(line, "owner=") orelse self.blocked_owner;
            }
            if (token(line, "last_progress_step=")) |value| {
                self.last_progress_step = @max(self.last_progress_step, parseUnsigned(value) orelse self.last_progress_step);
            }
            if (token(line, "stall_steps=")) |value| {
                const stall = parseUnsigned(value) orelse 0;
                if (self.last_progress_step == 0 and self.blocked_step >= stall) {
                    self.last_progress_step = self.blocked_step - stall;
                }
            }
        }

        if (std.mem.indexOf(u8, line, "SLOW BUT PROGRESSING") != null) {
            self.slow_progress_notices +|= 1;
            if (token(line, "step=")) |value| {
                self.last_progress_step = @max(self.last_progress_step, parseUnsigned(value) orelse self.last_progress_step);
            }
        }

        if (token(line, "activation_budget=")) |value| {
            self.activation_budget_steps = parseUnsigned(value) orelse self.activation_budget_steps;
        }
        if (token(line, "activation_budget_mode=")) |value| {
            self.activation_budget_unlimited = std.mem.eql(u8, value, "unlimited");
        }
        if (token(line, "activation_steps=")) |value| {
            if (parsePair(value)) |pair| self.activation_budget_steps = @max(self.activation_budget_steps, pair[1]);
        }
        if (token(line, "last_progress=")) |value| {
            self.last_progress_step = @max(self.last_progress_step, parseUnsigned(value) orelse self.last_progress_step);
        }
        if (token(line, "cost_steps=")) |value| {
            self.precompile_cost_steps = @max(self.precompile_cost_steps, parseUnsigned(value) orelse self.precompile_cost_steps);
        }
        if (token(line, "slow_notices=")) |value| {
            self.slow_progress_notices = @max(
                self.slow_progress_notices,
                @as(u32, @intCast(parseUnsigned(value) orelse self.slow_progress_notices)),
            );
        }
        if (token(line, "spin_verdict=")) |value| self.spin_verdict = value;
        if (token(line, "scheduler(runnable/parked)=")) |value| {
            if (parsePair(value)) |pair| {
                self.scheduler_runnable = @intCast(pair[0]);
                self.scheduler_parked = @intCast(pair[1]);
            }
        }
        if (token(line, "wait_notifications=")) |value| {
            self.wait_notifications = parseUnsigned(value) orelse self.wait_notifications;
        }
        if (std.mem.indexOf(u8, line, "guest waits consume the signals they wait on") != null) {
            self.wait_consumption_warning = true;
        }

        if (std.mem.indexOf(u8, line, "CONTRACT PROGRESS block=") != null) {
            if (token(line, "block=")) |value| {
                if (parsePair(value)) |pair| {
                    self.contract_blocks_reached = @intCast(pair[0]);
                    self.contract_blocks_total = @intCast(pair[1]);
                }
            }
            if (token(line, "required=")) |value| {
                if (parsePair(value)) |pair| self.contract_blocks_reached = @intCast(pair[0]);
            }
            if (token(line, "edges=")) |value| {
                if (parsePair(value)) |pair| self.contract_edges_reached = @intCast(pair[0]);
            }
        }

        if (std.mem.indexOf(u8, line, "compile plan AMBER") != null) {
            if (token(line, "unknown=")) |value| self.compile_unknown = @intCast(parseUnsigned(value) orelse self.compile_unknown);
        }

        if (std.mem.indexOf(u8, line, "graphics tracepoints sealed:") != null) {
            if (token(line, "armed=")) |value| self.tracepoints_armed = @intCast(parseUnsigned(value) orelse self.tracepoints_armed);
            if (token(line, "unresolved=")) |value| self.tracepoints_unresolved = @intCast(parseUnsigned(value) orelse self.tracepoints_unresolved);
        }

        if (std.mem.indexOf(u8, line, "tracepoint role=swap") != null) {
            self.swap_tracepoints +|= 1;
            if (token(line, "hits=")) |value| {
                const hits = parseUnsigned(value) orelse 0;
                self.swap_hits = @max(self.swap_hits, hits);
            }
        }

        if (std.mem.indexOf(u8, line, "GPU PRE-INITIALIZATION: established=") != null) {
            if (token(line, "established=")) |value| parseFraction(value, &self.preinit_established, &self.preinit_total);
        }

        if (std.mem.indexOf(u8, line, "KERNEL VARIABLES: imported=") != null) {
            if (token(line, "imported=")) |value| self.kernel_variables_imported = @intCast(parseUnsigned(value) orelse self.kernel_variables_imported);
            if (token(line, "usable=")) |value| self.kernel_variables_usable = @intCast(parseUnsigned(value) orelse self.kernel_variables_usable);
            if (token(line, "harness_writes=")) |value| self.kernel_variable_writes = @intCast(parseUnsigned(value) orelse self.kernel_variable_writes);
        }

        if (std.mem.indexOf(u8, line, "PRESENTATION PROVENANCE:") != null) {
            if (token(line, "guest_vulkan_calls_seen=")) |value| self.guest_vulkan_calls = parseUnsigned(value) orelse self.guest_vulkan_calls;
            if (token(line, "native_submissions=")) |value| self.native_submissions = parseUnsigned(value) orelse self.native_submissions;
            if (token(line, "native_present_requests=")) |value| self.native_present_requests = parseUnsigned(value) orelse self.native_present_requests;
            if (token(line, "guest_output_frames=")) |value| self.guest_output_frames = parseUnsigned(value) orelse self.guest_output_frames;
        }

        if (std.mem.indexOf(u8, line, "gpu register aperture:") != null) {
            if (token(line, "reads=")) |value| self.gpu_aperture_reads = parseUnsigned(value) orelse self.gpu_aperture_reads;
            if (token(line, "writes=")) |value| self.gpu_aperture_writes = parseUnsigned(value) orelse self.gpu_aperture_writes;
        }

        if (std.mem.indexOf(u8, line, "VULKAN TIER CONSISTENCY: finding=consistent") != null) self.vulkan_tier_consistent = true;

        if (std.mem.indexOf(u8, line, "THREAD CENSUS:") != null) {
            if (token(line, "active=")) |value| self.active_threads = @intCast(parseUnsigned(value) orelse self.active_threads);
            if (token(line, "parked=")) |value| self.parked_threads = @intCast(parseUnsigned(value) orelse self.parked_threads);
        }

        if (token(line, "wptr(writes/advances/repeats)=")) |value| {
            if (parseTriple(value)) |triple| {
                self.ring_writes = @max(self.ring_writes, triple[0]);
                self.ring_advances = @max(self.ring_advances, triple[1]);
            }
        }
    }

    pub fn ingest(self: *Report, text: []const u8) void {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| self.observeLine(line);
    }

    pub fn reached(self: *const Report, stage: Stage) bool {
        return self.reached_mask & bit(stage) != 0;
    }

    fn observeStage(self: *Report, name: []const u8) void {
        if (stageFromName(name)) |stage| {
            const was_reached = self.reached(stage);
            self.reached_mask |= bit(stage);
            if (!was_reached) self.accepted_stage_events +|= 1;
        }
    }

    pub fn frontier(self: *const Report) ?Stage {
        for (ordered_stages) |stage| {
            if (!self.reached(stage)) return stage;
        }
        return null;
    }

    pub fn verdict(self: *const Report) Verdict {
        if (!self.compile_green) return .compile_not_green;
        if (!self.reached(.user_module_loaded) or !self.reached(.user_module_ready)) return .before_user_module;
        if (!self.reached(.shader_storage_requested)) return .graphics_owner_silent;
        if (!self.reached(.guest_vdswap_entered) or self.swap_hits == 0) return .no_guest_swap;
        if (!self.reached(.authentic_native_presented)) return .not_presented;
        return .authentic_frame;
    }
};

fn token(line: []const u8, key: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, key) orelse return null;
    const value_start = start + key.len;
    var end = value_start;
    while (end < line.len and
        line[end] != ' ' and
        line[end] != '\t' and
        line[end] != '\r' and
        line[end] != ';' and
        line[end] != ',') : (end += 1)
    {}
    if (end == value_start) return null;
    return line[value_start..end];
}

fn digitValue(character: u8) ?u8 {
    return switch (character) {
        '0'...'9' => character - '0',
        'a'...'f' => character - 'a' + 10,
        'A'...'F' => character - 'A' + 10,
        else => null,
    };
}

fn parseUnsigned(text: []const u8) ?u64 {
    if (text.len == 0) return null;
    var index: usize = 0;
    var base: u64 = 10;
    if (text.len >= 2 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X')) {
        base = 16;
        index = 2;
    }
    if (index == text.len) return null;
    var result: u64 = 0;
    while (index < text.len) : (index += 1) {
        const digit = digitValue(text[index]) orelse return null;
        if (digit >= base) return null;
        result = result * base + digit;
    }
    return result;
}

fn parseFraction(text: []const u8, numerator: *u32, denominator: *u32) void {
    const slash = std.mem.indexOfScalar(u8, text, '/') orelse return;
    numerator.* = @intCast(parseUnsigned(text[0..slash]) orelse numerator.*);
    denominator.* = @intCast(parseUnsigned(text[slash + 1 ..]) orelse denominator.*);
}

fn parsePair(text: []const u8) ?[2]u64 {
    const slash = std.mem.indexOfScalar(u8, text, '/') orelse return null;
    return .{
        parseUnsigned(text[0..slash]) orelse return null,
        parseUnsigned(text[slash + 1 ..]) orelse return null,
    };
}

fn parseTriple(text: []const u8) ?[3]u64 {
    var parts = std.mem.splitScalar(u8, text, '/');
    var result: [3]u64 = undefined;
    var index: usize = 0;
    while (parts.next()) |part| : (index += 1) {
        if (index >= result.len) return null;
        result[index] = parseUnsigned(part) orelse return null;
    }
    if (index != result.len) return null;
    return result;
}

test "package identity is the x86 Xbyak route" {
    try std.testing.expectEqualStrings("x86_64", host_architecture);
    try std.testing.expectEqualStrings("xbyak-x86_64", host_codegen);
}

test "the supplied x86 frontier is classified without forcing it" {
    var report = Report{};
    report.ingest(
        "READY COMPILER: package HIT path=.rosette/packages/xenia-halo3-ready.r3pkg\n" ++
            "READY COMPILER: package STORE path=.rosette/packages/xenia-halo3-ready.r3pkg\n" ++
            "READY COMPILER: compile plan GREEN units=39/42 ok=39 failed=0 unknown=3 skipped=0\n" ++
            "READY COMPILER: report stage id=0 name=image_ready reached=true\n" ++
            "READY COMPILER: report stage id=1 name=compile_ready reached=true\n" ++
            "READY COMPILER: report stage id=2 name=static_initializers_complete reached=true\n" ++
            "READY COMPILER: stage name=emulator_setup_started id=3 accepted=true\n" ++
            "READY COMPILER: stage name=memory_ready id=4 accepted=true\n" ++
            "READY COMPILER: stage name=processor_ready id=5 accepted=true\n" ++
            "READY COMPILER: stage name=patch_database_ready id=6 accepted=true\n" ++
            "READY COMPILER: stage name=kernel_globals_started id=7 accepted=true\n" ++
            "READY COMPILER: stage name=kernel_globals_ready id=8 accepted=true\n" ++
            "READY COMPILER: stage name=kernel_modules_ready id=9 accepted=true\n" ++
            "READY COMPILER: stage name=graphics_setup_started id=10 accepted=true\n" ++
            "READY COMPILER: stage name=command_processor_ready id=11 accepted=true\n" ++
            "READY COMPILER: stage name=graphics_ready id=12 accepted=true\n" ++
            "READY COMPILER: stage name=emulator_setup_ready id=13 accepted=true\n" ++
            "READY COMPILER: stage name=launch_path_started id=14 accepted=true\n" ++
            "READY COMPILER: stage name=disc_mounted id=15 accepted=true\n" ++
            "READY COMPILER: stage name=complete_launch_started id=16 accepted=true\n" ++
            "READY COMPILER: stage name=user_module_loaded id=17 accepted=true\n" ++
            "READY COMPILER: stage name=precompile_requested id=18 accepted=true\n" ++
            "READY COMPILER: stage name=precompile_completed id=19 accepted=true\n" ++
            "READY COMPILER: stage name=user_module_ready id=20 accepted=true\n" ++
            "READY COMPILER: BLOCKED kind=ACTIVATION_BUDGET_EXHAUSTED stage=shader_storage_requested step=500000000\n" ++
            "READY COMPILER: CONTRACT PROGRESS block=21/35 required=21/35 edges=21/36\n" ++
            "READY COMPILER: DIAGNOSIS progress=MILESTONE_ADVANCING blockage=OWNER_SILENT missing=shader_storage_requested owner=xenia:graphics stall_steps=131439085\n" ++
            "READY COMPILER: DIAGNOSIS spin_verdict=NOT_CONCENTRATED scheduler(runnable/parked)=1/7 wait_notifications=0\n" ++
            "GRAPHICS CONTRACT: harness work outstanding: guest waits consume the signals they wait on\n" ++
            "graphics tracepoints sealed: armed=22 unresolved=0\n" ++
            "tracepoint role=swap hits=0\n" ++
            "GPU PRE-INITIALIZATION: established=5/13\n" ++
            "PRESENTATION PROVENANCE: guest_vulkan_calls_seen=460 native_submissions=0 native_present_requests=0 guest_output_frames=0\n" ++
            "VULKAN TIER CONSISTENCY: finding=consistent real=12 modelled=0 of 19\n" ++
            "gpu register aperture: base=0x7fc80000 size=0x10000 reads=0 writes=0\n" ++
            "THREAD CENSUS: active=13 parked=7\n",
    );

    try std.testing.expect(report.package_hit);
    try std.testing.expect(report.package_store);
    try std.testing.expect(report.compile_green);
    try std.testing.expectEqual(Stage.shader_storage_requested, report.frontier().?);
    try std.testing.expectEqual(@as(u8, 21), report.contract_blocks_reached);
    try std.testing.expectEqual(@as(u8, 35), report.contract_blocks_total);
    try std.testing.expectEqual(@as(u8, 21), report.contract_edges_reached);
    try std.testing.expectEqual(Verdict.graphics_owner_silent, report.verdict());
    try std.testing.expectEqual(@as(u32, 22), report.tracepoints_armed);
    try std.testing.expectEqual(@as(u32, 0), report.tracepoints_unresolved);
    try std.testing.expectEqual(@as(u64, 0), report.swap_hits);
    try std.testing.expect(report.vulkan_tier_consistent);
    try std.testing.expect(report.wait_consumption_warning);
    try std.testing.expectEqual(@as(u32, 1), report.scheduler_runnable);
    try std.testing.expectEqual(@as(u32, 7), report.scheduler_parked);
    try std.testing.expectEqual(@as(u64, 0), report.gpu_aperture_writes);
    try std.testing.expectEqual(@as(u32, 13), report.active_threads);
    try std.testing.expectEqual(@as(u32, 7), report.parked_threads);
}

test "a completed authentic frame is distinct from a diagnostic present" {
    var report = Report{ .compile_green = true };
    report.ingest(
        "READY COMPILER: stage name=user_module_loaded accepted=true\n" ++
            "READY COMPILER: stage name=user_module_ready accepted=true\n" ++
            "READY COMPILER: stage name=shader_storage_requested accepted=true\n" ++
            "READY COMPILER: stage name=guest_vdswap_entered accepted=true\n" ++
            "tracepoint role=swap hits=1\n" ++
            "READY COMPILER: stage name=authentic_native_presented accepted=true\n",
    );
    try std.testing.expectEqual(Verdict.authentic_frame, report.verdict());
}

test "number parsing handles decimal and hexadecimal diagnostic values" {
    try std.testing.expectEqual(@as(u64, 500_000_000), parseUnsigned("500000000").?);
    try std.testing.expectEqual(@as(u64, 0x1a9db7), parseUnsigned("0x1a9db7").?);
    try std.testing.expectEqual(@as(u64, 0), parseUnsigned("0").?);
    try std.testing.expect(parseUnsigned("not-a-number") == null);
}

test "unlimited activation is represented separately from a finite cap" {
    var report = Report{};
    report.ingest(
        "READY COMPILER: configured activation_budget=0 activation_budget_mode=unlimited quiet_budget=150000000\n" ++
            "READY COMPILER: DIAGNOSIS activation_steps=900000000/0 activation_budget_mode=unlimited\n",
    );
    try std.testing.expectEqual(@as(u64, 0), report.activation_budget_steps);
    try std.testing.expect(report.activation_budget_unlimited);
}
