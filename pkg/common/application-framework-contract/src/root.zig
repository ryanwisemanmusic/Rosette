//! Stable, C-compatible schema for the Rosette application framework.
//!
//! This package owns vocabulary and wire layout only.  It deliberately does
//! not know how a guest thread, Xenia, Vulkan, or Cocoa is implemented.  The
//! runtime ledger in `lib/framework` owns mutable evidence and policy.

const std = @import("std");

pub const schema_version: u16 = 1;
pub const abi_version: u32 = 0x0001_0000;
pub const max_name_bytes: usize = 48;
pub const max_detail_bytes: usize = 96;

pub const Mode = enum(u8) {
    disabled,
    observe_only,
    host_control,
    experimental_control,

    pub fn label(self: Mode) []const u8 {
        return switch (self) {
            .disabled => "disabled",
            .observe_only => "observe_only",
            .host_control => "host_control",
            .experimental_control => "experimental_control",
        };
    }
};

pub const Capability = enum(u8) {
    observe_events,
    inspect_control_flow,
    inspect_memory,
    inspect_graphics,
    inspect_backend,
    control_scheduler,
    control_host_presenter,
    invoke_guest_api,
    mutate_guest_memory,
    mutate_host_state,

    pub fn label(self: Capability) []const u8 {
        return switch (self) {
            .observe_events => "observe_events",
            .inspect_control_flow => "inspect_control_flow",
            .inspect_memory => "inspect_memory",
            .inspect_graphics => "inspect_graphics",
            .inspect_backend => "inspect_backend",
            .control_scheduler => "control_scheduler",
            .control_host_presenter => "control_host_presenter",
            .invoke_guest_api => "invoke_guest_api",
            .mutate_guest_memory => "mutate_guest_memory",
            .mutate_host_state => "mutate_host_state",
        };
    }
};

pub fn capabilityBit(capability: Capability) u64 {
    return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(capability)));
}

pub const Owner = enum(u8) {
    unknown,
    rosette,
    guest,
    xenia_kernel,
    xenia_gpu,
    xenia_presenter,
    host_framework,
    external_adapter,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .rosette => "rosette",
            .guest => "guest",
            .xenia_kernel => "xenia:kernel",
            .xenia_gpu => "xenia:gpu",
            .xenia_presenter => "xenia:presenter",
            .host_framework => "rosette:framework",
            .external_adapter => "external:adapter",
        };
    }
};

pub const Domain = enum(u8) {
    unknown,
    process,
    control_flow,
    scheduler,
    memory,
    kernel,
    pm4,
    vd_swap,
    graphics_backend,
    presenter,
    equivalence,
    framework,

    pub fn label(self: Domain) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .process => "process",
            .control_flow => "control-flow",
            .scheduler => "scheduler",
            .memory => "memory",
            .kernel => "kernel",
            .pm4 => "pm4",
            .vd_swap => "vd-swap",
            .graphics_backend => "graphics-backend",
            .presenter => "presenter",
            .equivalence => "equivalence",
            .framework => "framework",
        };
    }
};

pub const EventKind = enum(u8) {
    process,
    function_enter,
    function_exit,
    control_transfer,
    branch,
    state_observation,
    state_write,
    scheduler,
    wait,
    signal,
    memory,
    pm4_packet,
    vd_swap,
    backend_call,
    presentation,
    equivalence,
    command_request,
    command_result,
    fault,

    pub fn label(self: EventKind) []const u8 {
        return switch (self) {
            .process => "process",
            .function_enter => "function-enter",
            .function_exit => "function-exit",
            .control_transfer => "control-transfer",
            .branch => "branch",
            .state_observation => "state-observation",
            .state_write => "state-write",
            .scheduler => "scheduler",
            .wait => "wait",
            .signal => "signal",
            .memory => "memory",
            .pm4_packet => "pm4-packet",
            .vd_swap => "vd-swap",
            .backend_call => "backend-call",
            .presentation => "presentation",
            .equivalence => "equivalence",
            .command_request => "command-request",
            .command_result => "command-result",
            .fault => "fault",
        };
    }
};

pub const Truth = enum(u8) {
    observed,
    requested,
    applied,
    rejected,
    inferred,

    pub fn label(self: Truth) []const u8 {
        return switch (self) {
            .observed => "observed",
            .requested => "requested",
            .applied => "applied",
            .rejected => "rejected",
            .inferred => "inferred",
        };
    }
};

pub const ValueKind = enum(u8) {
    none,
    scalar,
    boolean,
    pointer,
    address,
    count,
    enum_value,
    bytes_hash,

    pub fn label(self: ValueKind) []const u8 {
        return switch (self) {
            .none => "none",
            .scalar => "scalar",
            .boolean => "boolean",
            .pointer => "pointer",
            .address => "address",
            .count => "count",
            .enum_value => "enum",
            .bytes_hash => "bytes-hash",
        };
    }
};

pub const Equivalence = enum(u8) {
    not_checked,
    match,
    masked_match,
    tolerance_match,
    mismatch,
    unavailable,

    pub fn label(self: Equivalence) []const u8 {
        return switch (self) {
            .not_checked => "not-checked",
            .match => "match",
            .masked_match => "masked-match",
            .tolerance_match => "tolerance-match",
            .mismatch => "mismatch",
            .unavailable => "unavailable",
        };
    }

    pub fn healthy(self: Equivalence) bool {
        return switch (self) {
            .match, .masked_match, .tolerance_match => true,
            else => false,
        };
    }
};

pub const Command = enum(u8) {
    snapshot,
    enable_trace,
    disable_trace,
    pause_guest,
    resume_guest,
    drain_gpu_interrupts,
    refresh_output,
    set_breakpoint,
    inspect_guest_memory,
    invoke_guest_api,
    write_guest_memory,
    write_host_state,

    pub fn label(self: Command) []const u8 {
        return switch (self) {
            .snapshot => "snapshot",
            .enable_trace => "enable-trace",
            .disable_trace => "disable-trace",
            .pause_guest => "pause-guest",
            .resume_guest => "resume-guest",
            .drain_gpu_interrupts => "drain-gpu-interrupts",
            .refresh_output => "refresh-output",
            .set_breakpoint => "set-breakpoint",
            .inspect_guest_memory => "inspect-guest-memory",
            .invoke_guest_api => "invoke-guest-api",
            .write_guest_memory => "write-guest-memory",
            .write_host_state => "write-host-state",
        };
    }

    pub fn requiredCapability(self: Command) ?Capability {
        return switch (self) {
            .snapshot, .enable_trace, .disable_trace => .observe_events,
            .pause_guest, .resume_guest, .set_breakpoint => .control_scheduler,
            .drain_gpu_interrupts => .control_scheduler,
            .refresh_output => .control_host_presenter,
            .inspect_guest_memory => .inspect_memory,
            .invoke_guest_api => .invoke_guest_api,
            .write_guest_memory => .mutate_guest_memory,
            .write_host_state => .mutate_host_state,
        };
    }

    pub fn isGuestMutation(self: Command) bool {
        return switch (self) {
            .invoke_guest_api, .write_guest_memory => true,
            else => false,
        };
    }
};

pub const RequestStatus = enum(u8) {
    invalid,
    disabled,
    queued,
    applied,
    denied,
    unsupported,
    not_ready,

    pub fn label(self: RequestStatus) []const u8 {
        return switch (self) {
            .invalid => "invalid",
            .disabled => "disabled",
            .queued => "queued",
            .applied => "applied",
            .denied => "denied",
            .unsupported => "unsupported",
            .not_ready => "not-ready",
        };
    }
};

/// Fixed-layout configuration used across the optional Xenia adapter.
pub const Config = extern struct {
    size: u16 = 0,
    schema: u16 = schema_version,
    mode: u8 = @intFromEnum(Mode.disabled),
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    capabilities: u64 = 0,
    application_id: u64 = 0,
    trace_control_flow: u8 = 0,
    trace_memory: u8 = 0,
    trace_graphics: u8 = 0,
    reserved2: u8 = 0,
    max_events: u32 = 0,
};

/// A request contains no pointers.  The adapter may safely construct it in a
/// different language, different library, or a future Xenia process.
pub const Request = extern struct {
    size: u16 = 0,
    schema: u16 = schema_version,
    command: u8 = @intFromEnum(Command.snapshot),
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    request_id: u64 = 0,
    guest_step: u64 = 0,
    subject: u64 = 0,
    argument0: u64 = 0,
    argument1: u64 = 0,
    argument2: u64 = 0,
    name_hash: u64 = 0,
};

pub const RequestResult = extern struct {
    size: u16 = 0,
    schema: u16 = schema_version,
    status: u8 = @intFromEnum(RequestStatus.invalid),
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    request_id: u64 = 0,
    reason_code: u64 = 0,
};

/// The event is intentionally value-only.  It can be copied over a C ABI,
/// retained in a bounded ring, and compared after translation without keeping
/// a pointer into Xenia or the guest.
pub const Event = extern struct {
    size: u16 = 0,
    schema: u16 = schema_version,
    kind: u8 = @intFromEnum(EventKind.process),
    truth: u8 = @intFromEnum(Truth.observed),
    owner: u8 = @intFromEnum(Owner.unknown),
    domain: u8 = @intFromEnum(Domain.unknown),
    value_kind: u8 = @intFromEnum(ValueKind.none),
    equivalence: u8 = @intFromEnum(Equivalence.not_checked),
    reserved0: u16 = 0,
    sequence: u64 = 0,
    guest_step: u64 = 0,
    thread_id: u64 = 0,
    guest_rip: u64 = 0,
    host_pc: u64 = 0,
    subject: u64 = 0,
    expected: u64 = 0,
    actual: u64 = 0,
    mask: u64 = 0,
    auxiliary: u64 = 0,
    name_hash: u64 = 0,
    name: [max_name_bytes]u8 = [_]u8{0} ** max_name_bytes,
    detail: [max_detail_bytes]u8 = [_]u8{0} ** max_detail_bytes,
};

pub const Snapshot = extern struct {
    size: u16 = 0,
    schema: u16 = schema_version,
    mode: u8 = @intFromEnum(Mode.disabled),
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    sequence: u64 = 0,
    events_retained: u64 = 0,
    events_total: u64 = 0,
    events_dropped: u64 = 0,
    requests_total: u64 = 0,
    requests_queued: u64 = 0,
    requests_applied: u64 = 0,
    requests_denied: u64 = 0,
    equivalence_checks: u64 = 0,
    equivalence_matches: u64 = 0,
    equivalence_mismatches: u64 = 0,
    last_guest_step: u64 = 0,
    last_guest_rip: u64 = 0,
    application_id: u64 = 0,
};

pub fn contractIsWellFormed() bool {
    if (schema_version == 0 or abi_version == 0) return false;
    if (max_name_bytes == 0 or max_detail_bytes == 0) return false;
    inline for (@typeInfo(Mode).@"enum".fields) |field| {
        if (@as(Mode, @enumFromInt(field.value)).label().len == 0) return false;
    }
    inline for (@typeInfo(Capability).@"enum".fields) |field| {
        if (@as(Capability, @enumFromInt(field.value)).label().len == 0) return false;
    }
    inline for (@typeInfo(EventKind).@"enum".fields) |field| {
        if (@as(EventKind, @enumFromInt(field.value)).label().len == 0) return false;
    }
    inline for (@typeInfo(Command).@"enum".fields) |field| {
        const command: Command = @enumFromInt(field.value);
        if (command.label().len == 0) return false;
        if (command.isGuestMutation() and command.requiredCapability() == null) return false;
    }
    if (@sizeOf(Event) < @sizeOf(Request)) return false;
    return true;
}

test "application framework contract is complete" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expectEqual(@as(u16, 1), schema_version);
    try std.testing.expect(capabilityBit(.inspect_graphics) != capabilityBit(.inspect_memory));
    try std.testing.expect(Command.write_guest_memory.isGuestMutation());
    try std.testing.expect(!Command.refresh_output.isGuestMutation());
}

test "C ABI records remain pointer-free and fixed size" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Config));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(Request));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(RequestResult));
    try std.testing.expectEqual(@as(usize, 248), @sizeOf(Event));
    try std.testing.expectEqual(@as(usize, 120), @sizeOf(Snapshot));
    try std.testing.expect(@offsetOf(Event, "name") < @offsetOf(Event, "detail"));
}
