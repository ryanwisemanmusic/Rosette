//! Fixed ABI and pure admission policy for Rosette-hosted Xenia startup.
//!
//! This is deliberately a very small contract. Rosette may substantiate a
//! host operation Xenia has explicitly requested, but it never becomes the
//! owner of guest execution. A response from this package therefore cannot
//! create a guest thread, publish a GPU pointer, synthesize PM4/VdSwap, or
//! report a presentation event.

const std = @import("std");

pub const schema_version: u16 = 1;
pub const abi_version: u32 = 0x0001_0000;

pub const StateFlag = enum(u5) {
    module_present,
    entry_resolved,
    load_idle,
    graphics_ready,
    command_processor_ready,
    metadata_optional,
    guest_main_started,
    guest_gpu_activity,
    ring_ready,
    dispatch_worker_running,
    guest_main_not_started,
    guest_gpu_idle,
    ring_not_ready,
    dispatch_worker_not_running,
};

pub fn stateBit(flag: StateFlag) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(flag)));
}

pub const state_module_present = stateBit(.module_present);
pub const state_entry_resolved = stateBit(.entry_resolved);
pub const state_load_idle = stateBit(.load_idle);
pub const state_graphics_ready = stateBit(.graphics_ready);
pub const state_command_processor_ready = stateBit(.command_processor_ready);
pub const state_metadata_optional = stateBit(.metadata_optional);
pub const state_guest_main_started = stateBit(.guest_main_started);
pub const state_guest_gpu_activity = stateBit(.guest_gpu_activity);
pub const state_ring_ready = stateBit(.ring_ready);
pub const state_dispatch_worker_running = stateBit(.dispatch_worker_running);
pub const state_guest_main_not_started = stateBit(.guest_main_not_started);
pub const state_guest_gpu_idle = stateBit(.guest_gpu_idle);
pub const state_ring_not_ready = stateBit(.ring_not_ready);
pub const state_dispatch_worker_not_running = stateBit(.dispatch_worker_not_running);

pub const known_state_mask: u32 = state_module_present |
    state_entry_resolved | state_load_idle | state_graphics_ready |
    state_command_processor_ready | state_metadata_optional |
    state_guest_main_started | state_guest_gpu_activity | state_ring_ready |
    state_dispatch_worker_running | state_guest_main_not_started |
    state_guest_gpu_idle | state_ring_not_ready |
    state_dispatch_worker_not_running;

pub const Action = enum(u5) {
    defer_optional_title_metadata,
    start_deferred_dispatch_worker,
};

pub fn actionBit(action: Action) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(action)));
}

pub const action_defer_optional_title_metadata =
    actionBit(.defer_optional_title_metadata);
pub const action_start_deferred_dispatch_worker =
    actionBit(.start_deferred_dispatch_worker);

pub const known_action_mask: u32 = action_defer_optional_title_metadata |
    action_start_deferred_dispatch_worker;

pub const Decision = enum(u8) {
    refuse,
    allow,
};

pub const Reason = enum(u16) {
    none,
    provider_disabled,
    malformed_request,
    host_control_required,
    module_missing,
    entry_unresolved,
    load_inflight,
    graphics_not_ready,
    command_processor_not_ready,
    metadata_required,
    guest_already_started,
    guest_gpu_activity,
    ring_already_ready,
    guest_state_unknown,
    dispatch_worker_state_unknown,
    no_actionable_assist,

    pub fn label(self: Reason) []const u8 {
        return switch (self) {
            .none => "none",
            .provider_disabled => "provider_disabled",
            .malformed_request => "malformed_request",
            .host_control_required => "host_control_required",
            .module_missing => "module_missing",
            .entry_unresolved => "entry_unresolved",
            .load_inflight => "load_inflight",
            .graphics_not_ready => "graphics_not_ready",
            .command_processor_not_ready => "command_processor_not_ready",
            .metadata_required => "metadata_required",
            .guest_already_started => "guest_already_started",
            .guest_gpu_activity => "guest_gpu_activity",
            .ring_already_ready => "ring_already_ready",
            .guest_state_unknown => "guest_state_unknown",
            .dispatch_worker_state_unknown => "dispatch_worker_state_unknown",
            .no_actionable_assist => "no_actionable_assist",
        };
    }
};

pub const ApplyStatus = enum(u8) {
    not_applied,
    applied,
    partially_applied,
    failed,
};

/// The request is intentionally pointer-free and fixed-width. `size` and
/// `schema` are carried in-band so an older Rosette refuses a newer Xenia
/// record instead of reading a field at the wrong offset.
pub const Request = extern struct {
    size: u16 = 0,
    schema: u16 = schema_version,
    title_id: u32 = 0,
    entry_point: u32 = 0,
    state_flags: u32 = 0,
    reserved: u32 = 0,
    guest_step: u64 = 0,

    pub fn init(title_id: u32, entry_point: u32, state_flags: u32, guest_step: u64) Request {
        return .{
            .size = @sizeOf(Request),
            .schema = schema_version,
            .title_id = title_id,
            .entry_point = entry_point,
            .state_flags = state_flags,
            .guest_step = guest_step,
        };
    }
};

/// `proof_mask` is the state evidence Rosette actually accepted. It is not a
/// prediction of what Xenia will do after the call.
pub const Response = extern struct {
    size: u16 = 0,
    schema: u16 = schema_version,
    decision: u8 = @intFromEnum(Decision.refuse),
    reserved0: u8 = 0,
    reason: u16 = @intFromEnum(Reason.none),
    actions: u32 = 0,
    proof_mask: u64 = 0,

    pub fn refused(reason: Reason, proof_mask: u64) Response {
        return .{
            .size = @sizeOf(Response),
            .schema = schema_version,
            .decision = @intFromEnum(Decision.refuse),
            .reason = @intFromEnum(reason),
            .proof_mask = proof_mask,
        };
    }
};

pub fn requestIsCompatible(request: Request) bool {
    return (request.size == 0 or request.size >= @sizeOf(Request)) and
        (request.schema == 0 or request.schema == schema_version) and
        request.reserved == 0 and
        request.state_flags & ~known_state_mask == 0 and
        !(has(request.state_flags, state_guest_main_started) and
            has(request.state_flags, state_guest_main_not_started)) and
        !(has(request.state_flags, state_guest_gpu_activity) and
            has(request.state_flags, state_guest_gpu_idle)) and
        !(has(request.state_flags, state_ring_ready) and
            has(request.state_flags, state_ring_not_ready)) and
        !(has(request.state_flags, state_dispatch_worker_running) and
            has(request.state_flags, state_dispatch_worker_not_running));
}

pub fn responseIsCompatible(response: Response) bool {
    if (!((response.size == 0 or response.size >= @sizeOf(Response)) and
        (response.schema == 0 or response.schema == schema_version))) return false;
    if (response.reserved0 != 0 or response.decision > @intFromEnum(Decision.allow) or
        response.reason > @intFromEnum(Reason.no_actionable_assist) or
        response.actions & ~known_action_mask != 0) return false;
    if (response.decision == @intFromEnum(Decision.refuse)) {
        return response.actions == 0;
    }
    return response.reason == @intFromEnum(Reason.none) and
        response.actions != 0;
}

fn has(flags: u32, required: u32) bool {
    return flags & required == required;
}

fn moduleReady(request: Request) bool {
    return request.entry_point != 0 and has(
        request.state_flags,
        state_module_present | state_entry_resolved | state_load_idle,
    );
}

fn rememberReason(reason: *Reason, candidate: Reason) void {
    if (reason.* == .no_actionable_assist) reason.* = candidate;
}

/// Pure, fail-closed policy. `host_control_enabled` is supplied by the
/// mutable Rosette framework; the package does not assume that mere symbol
/// presence authorizes a host mutation.
pub fn decide(request: Request, host_control_enabled: bool) Response {
    if (!requestIsCompatible(request)) {
        return Response.refused(.malformed_request, 0);
    }
    if (!host_control_enabled) {
        return Response.refused(.provider_disabled, 0);
    }

    const flags = request.state_flags;
    const module_proof = state_module_present | state_entry_resolved | state_load_idle;
    if (!has(flags, state_module_present)) {
        return Response.refused(.module_missing, flags);
    }
    if (request.entry_point == 0 or !has(flags, state_entry_resolved)) {
        return Response.refused(.entry_unresolved, flags);
    }
    if (!has(flags, state_load_idle)) {
        return Response.refused(.load_inflight, flags);
    }

    var actions: u32 = 0;
    var proof: u64 = module_proof;
    var refusal_reason: Reason = .no_actionable_assist;

    // Metadata deferral and dispatch-worker startup are independent host
    // operations. An unknown dispatch state must not suppress a metadata
    // decision, and a missing graphics proof must not suppress the host-only
    // worker decision. This is important at the Xenia boundary: each action
    // gets only the evidence it actually consumes.
    const graphics_proof = state_graphics_ready | state_command_processor_ready;
    if (!has(flags, state_graphics_ready)) {
        rememberReason(&refusal_reason, .graphics_not_ready);
    } else if (!has(flags, state_command_processor_ready)) {
        rememberReason(&refusal_reason, .command_processor_not_ready);
    } else if (!has(flags, state_metadata_optional)) {
        rememberReason(&refusal_reason, .metadata_required);
    } else if (has(flags, state_guest_main_started)) {
        rememberReason(&refusal_reason, .guest_already_started);
    } else if (!has(flags, state_guest_main_not_started)) {
        rememberReason(&refusal_reason, .guest_state_unknown);
    } else if (has(flags, state_guest_gpu_activity) or
        !has(flags, state_guest_gpu_idle))
    {
        rememberReason(
            &refusal_reason,
            if (has(flags, state_guest_gpu_activity))
                .guest_gpu_activity
            else
                .guest_state_unknown,
        );
    } else if (has(flags, state_ring_ready) or !has(flags, state_ring_not_ready)) {
        rememberReason(
            &refusal_reason,
            if (has(flags, state_ring_ready)) .ring_already_ready else .guest_state_unknown,
        );
    } else if (moduleReady(request)) {
        actions |= action_defer_optional_title_metadata;
        proof |= graphics_proof | state_metadata_optional |
            state_guest_main_not_started | state_guest_gpu_idle |
            state_ring_not_ready;
    }

    // Starting a host-only dispatch worker does not write guest state, but it
    // still requires the executable's entry contract to be complete. Its
    // negative state is independently proven; no graphics or guest activity
    // claim is borrowed for this decision.
    if (has(flags, state_dispatch_worker_running)) {
        // Xenia has already fulfilled this host-only predecessor.
    } else if (has(flags, state_dispatch_worker_not_running)) {
        actions |= action_start_deferred_dispatch_worker;
        proof |= state_dispatch_worker_not_running;
    } else {
        rememberReason(&refusal_reason, .dispatch_worker_state_unknown);
    }

    if (actions == 0) {
        return Response.refused(refusal_reason, flags);
    }

    return .{
        .size = @sizeOf(Response),
        .schema = schema_version,
        .decision = @intFromEnum(Decision.allow),
        .reason = @intFromEnum(Reason.none),
        .actions = actions,
        .proof_mask = proof,
    };
}

pub fn actionAllowed(response: Response, action: Action) bool {
    return response.decision == @intFromEnum(Decision.allow) and
        response.actions & actionBit(action) != 0;
}

pub fn contractIsWellFormed() bool {
    if (@sizeOf(Request) != 32 or @sizeOf(Response) != 24) return false;
    if (known_state_mask == 0 or known_action_mask == 0) return false;
    inline for (@typeInfo(StateFlag).@"enum".fields) |field| {
        if (stateBit(@enumFromInt(field.value)) == 0) return false;
    }
    inline for (@typeInfo(Action).@"enum".fields) |field| {
        if (actionBit(@enumFromInt(field.value)) == 0) return false;
    }
    inline for (@typeInfo(Reason).@"enum".fields) |field| {
        if (@as(Reason, @enumFromInt(field.value)).label().len == 0) return false;
    }
    return true;
}

test "launch assist contract has stable fixed layout" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Request));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(Response));
}

test "missing proof refuses closed" {
    const request = Request.init(0x4D5307E6, 0x00582A98, state_module_present, 1);
    const response = decide(request, true);
    try std.testing.expectEqual(Decision.refuse, @as(Decision, @enumFromInt(response.decision)));
    try std.testing.expectEqual(Reason.entry_unresolved, @as(Reason, @enumFromInt(response.reason)));
}

test "graphics-first request permits only host actions" {
    const request = Request.init(
        0x4D5307E6,
        0x00582A98,
        state_module_present | state_entry_resolved | state_load_idle |
            state_graphics_ready | state_command_processor_ready |
            state_metadata_optional | state_guest_main_not_started |
            state_guest_gpu_idle | state_ring_not_ready |
            state_dispatch_worker_not_running,
        377_674_836,
    );
    const response = decide(request, true);
    try std.testing.expectEqual(Decision.allow, @as(Decision, @enumFromInt(response.decision)));
    try std.testing.expect(actionAllowed(response, .defer_optional_title_metadata));
    try std.testing.expect(actionAllowed(response, .start_deferred_dispatch_worker));
    try std.testing.expect((response.actions & ~(action_defer_optional_title_metadata | action_start_deferred_dispatch_worker)) == 0);
}

test "guest activity never authorizes metadata deferral" {
    const request = Request.init(
        1,
        2,
        state_module_present | state_entry_resolved | state_load_idle |
            state_graphics_ready | state_command_processor_ready |
            state_metadata_optional | state_guest_main_started |
            state_dispatch_worker_not_running,
        2,
    );
    const response = decide(request, true);
    try std.testing.expectEqual(Decision.allow, @as(Decision, @enumFromInt(response.decision)));
    try std.testing.expect(!actionAllowed(response, .defer_optional_title_metadata));
    try std.testing.expect(actionAllowed(response, .start_deferred_dispatch_worker));
}

test "disabled provider refuses every assist" {
    const request = Request.init(
        1,
        2,
        state_module_present | state_entry_resolved | state_load_idle |
            state_graphics_ready | state_command_processor_ready |
            state_metadata_optional | state_guest_main_not_started |
            state_guest_gpu_idle | state_ring_not_ready |
            state_dispatch_worker_not_running,
        3,
    );
    const response = decide(request, false);
    try std.testing.expectEqual(Decision.refuse, @as(Decision, @enumFromInt(response.decision)));
    try std.testing.expectEqual(Reason.provider_disabled, @as(Reason, @enumFromInt(response.reason)));
}

test "metadata assist does not depend on an unknown dispatch state" {
    const request = Request.init(
        1,
        2,
        state_module_present | state_entry_resolved | state_load_idle |
            state_graphics_ready | state_command_processor_ready |
            state_metadata_optional | state_guest_main_not_started |
            state_guest_gpu_idle | state_ring_not_ready,
        3,
    );
    const response = decide(request, true);
    try std.testing.expectEqual(Decision.allow, @as(Decision, @enumFromInt(response.decision)));
    try std.testing.expectEqual(action_defer_optional_title_metadata, response.actions);
}

test "contradictory or unknown state evidence refuses closed" {
    const contradictory = Request.init(
        1,
        2,
        state_module_present | state_entry_resolved | state_load_idle |
            state_guest_main_started | state_guest_main_not_started,
        3,
    );
    const unknown = Request.init(
        1,
        2,
        state_module_present | state_entry_resolved | state_load_idle | (1 << 31),
        3,
    );
    for ([_]Request{ contradictory, unknown }) |request| {
        const response = decide(request, true);
        try std.testing.expectEqual(Decision.refuse, @as(Decision, @enumFromInt(response.decision)));
        try std.testing.expectEqual(Reason.malformed_request, @as(Reason, @enumFromInt(response.reason)));
    }
}

test "response compatibility rejects invented actions" {
    var response = Response{
        .size = @sizeOf(Response),
        .schema = schema_version,
        .decision = @intFromEnum(Decision.allow),
        .reason = @intFromEnum(Reason.none),
        .actions = 1 << 31,
    };
    try std.testing.expect(!responseIsCompatible(response));
    response.actions = action_defer_optional_title_metadata;
    try std.testing.expect(responseIsCompatible(response));
}
