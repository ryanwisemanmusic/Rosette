//! Fixed ABI and fail-closed policy for the Rosette/Xenia host GPU callback.
//!
//! This contract is deliberately narrower than a guest callback contract.  It
//! authorizes Xenia to install a callback in its own host graphics system when
//! the guest callback path is missing, but it can never claim that the guest
//! registered a callback or that a frame, ring write, PM4 packet, or swap
//! happened.  Those facts remain owned by their original domains.

const std = @import("std");

pub const schema_version: u16 = 1;
pub const abi_version: u32 = 0x0001_0000;

pub const StateFlag = enum(u5) {
    module_present,
    entry_resolved,
    load_idle,
    graphics_ready,
    command_processor_ready,
    guest_main_running,
    guest_callback_missing,
    host_callback_missing,
    ring_ready,
    ring_not_ready,
    bootstrap_activity_seen,
    bootstrap_activity_absent,
    cadence_ready,
    guest_main_not_running,
};

pub fn stateBit(flag: StateFlag) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(flag)));
}

pub const state_module_present = stateBit(.module_present);
pub const state_entry_resolved = stateBit(.entry_resolved);
pub const state_load_idle = stateBit(.load_idle);
pub const state_graphics_ready = stateBit(.graphics_ready);
pub const state_command_processor_ready = stateBit(.command_processor_ready);
pub const state_guest_main_running = stateBit(.guest_main_running);
pub const state_guest_callback_missing = stateBit(.guest_callback_missing);
pub const state_host_callback_missing = stateBit(.host_callback_missing);
pub const state_ring_ready = stateBit(.ring_ready);
pub const state_ring_not_ready = stateBit(.ring_not_ready);
pub const state_bootstrap_activity_seen = stateBit(.bootstrap_activity_seen);
pub const state_bootstrap_activity_absent = stateBit(.bootstrap_activity_absent);
pub const state_cadence_ready = stateBit(.cadence_ready);
pub const state_guest_main_not_running = stateBit(.guest_main_not_running);

pub const known_state_mask: u32 = state_module_present |
    state_entry_resolved | state_load_idle | state_graphics_ready |
    state_command_processor_ready | state_guest_main_running |
    state_guest_callback_missing | state_host_callback_missing | state_ring_ready |
    state_ring_not_ready | state_bootstrap_activity_seen |
    state_bootstrap_activity_absent | state_cadence_ready |
    state_guest_main_not_running;

pub const Action = enum(u5) {
    install_host_interrupt_callback,
};

pub fn actionBit(action: Action) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(action)));
}

pub const action_install_host_interrupt_callback =
    actionBit(.install_host_interrupt_callback);
pub const known_action_mask: u32 = action_install_host_interrupt_callback;

pub const Decision = enum(u8) {
    refuse,
    allow,
};

pub const Reason = enum(u16) {
    none,
    provider_disabled,
    host_control_required,
    malformed_request,
    module_missing,
    entry_unresolved,
    load_inflight,
    graphics_not_ready,
    command_processor_not_ready,
    guest_main_not_running,
    guest_callback_state_unknown,
    guest_callback_present,
    host_callback_state_unknown,
    host_callback_present,
    ring_state_unknown,
    bootstrap_activity_unknown,
    cadence_not_ready,
    no_actionable_callback,

    pub fn label(self: Reason) []const u8 {
        return switch (self) {
            .none => "none",
            .provider_disabled => "provider_disabled",
            .host_control_required => "host_control_required",
            .malformed_request => "malformed_request",
            .module_missing => "module_missing",
            .entry_unresolved => "entry_unresolved",
            .load_inflight => "load_inflight",
            .graphics_not_ready => "graphics_not_ready",
            .command_processor_not_ready => "command_processor_not_ready",
            .guest_main_not_running => "guest_main_not_running",
            .guest_callback_state_unknown => "guest_callback_state_unknown",
            .guest_callback_present => "guest_callback_present",
            .host_callback_state_unknown => "host_callback_state_unknown",
            .host_callback_present => "host_callback_present",
            .ring_state_unknown => "ring_state_unknown",
            .bootstrap_activity_unknown => "bootstrap_activity_unknown",
            .cadence_not_ready => "cadence_not_ready",
            .no_actionable_callback => "no_actionable_callback",
        };
    }
};

pub const ApplyStatus = enum(u8) {
    not_applied,
    applied,
    partially_applied,
    failed,
};

/// The callback addresses are opaque 32-bit Xenia callback tokens.  They are
/// deliberately not host function pointers.  Rosette never dereferences or
/// invokes them; Xenia remains responsible for its own callback trampoline.
pub const Request = extern struct {
    size: u16 = 0,
    schema: u16 = schema_version,
    title_id: u32 = 0,
    entry_point: u32 = 0,
    state_flags: u32 = 0,
    guest_callback_token: u32 = 0,
    host_callback_token: u32 = 0,
    reserved: u32 = 0,
    guest_step: u64 = 0,
    vblank_id: u64 = 0,
    since_first_vblank_ms: u64 = 0,

    pub fn init(
        title_id: u32,
        entry_point: u32,
        state_flags: u32,
        guest_callback_token: u32,
        host_callback_token: u32,
        guest_step: u64,
        vblank_id: u64,
        since_first_vblank_ms: u64,
    ) Request {
        return .{
            .size = @sizeOf(Request),
            .schema = schema_version,
            .title_id = title_id,
            .entry_point = entry_point,
            .state_flags = state_flags,
            .guest_callback_token = guest_callback_token,
            .host_callback_token = host_callback_token,
            .guest_step = guest_step,
            .vblank_id = vblank_id,
            .since_first_vblank_ms = since_first_vblank_ms,
        };
    }
};

pub const Response = extern struct {
    size: u16 = 0,
    schema: u16 = schema_version,
    decision: u8 = @intFromEnum(Decision.refuse),
    reserved0: u8 = 0,
    reason: u16 = @intFromEnum(Reason.none),
    actions: u32 = 0,
    proof_mask: u64 = 0,
    authorization_id: u64 = 0,

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

fn has(flags: u32, required: u32) bool {
    return flags & required == required;
}

pub fn requestIsCompatible(request: Request) bool {
    const flags = request.state_flags;
    return (request.size == 0 or request.size >= @sizeOf(Request)) and
        (request.schema == 0 or request.schema == schema_version) and
        request.reserved == 0 and
        flags & ~known_state_mask == 0 and
        !(has(flags, state_ring_ready) and has(flags, state_ring_not_ready)) and
        !(has(flags, state_bootstrap_activity_seen) and
            has(flags, state_bootstrap_activity_absent)) and
        !(has(flags, state_guest_main_running) and
            has(flags, state_guest_main_not_running)) and
        !(has(flags, state_guest_callback_missing) and
            request.guest_callback_token != 0) and
        !(has(flags, state_host_callback_missing) and
            request.host_callback_token != 0);
}

pub fn responseIsCompatible(response: Response) bool {
    if (!((response.size == 0 or response.size >= @sizeOf(Response)) and
        (response.schema == 0 or response.schema == schema_version))) return false;
    if (response.reserved0 != 0 or
        response.decision > @intFromEnum(Decision.allow) or
        response.reason > @intFromEnum(Reason.no_actionable_callback) or
        response.actions & ~known_action_mask != 0) return false;
    if (response.decision == @intFromEnum(Decision.refuse)) {
        return response.actions == 0 and response.authorization_id == 0;
    }
    return response.reason == @intFromEnum(Reason.none) and
        response.actions == action_install_host_interrupt_callback and
        response.authorization_id != 0 and
        response.proof_mask & ~@as(u64, known_state_mask) == 0;
}

/// Authorization is bound to the vblank observation that produced it. A
/// structurally valid response from an older observation is not reusable for a
/// later Xenia state.
pub fn responseIsCompatibleForRequest(
    request: Request,
    response: Response,
) bool {
    return responseIsCompatible(response) and
        (response.decision == @intFromEnum(Decision.refuse) or
            response.authorization_id == request.vblank_id);
}

/// The host callback is a break-glass seam, not an implicit compatibility
/// mode.  Both the application framework's host-control mode and a separate
/// explicit provider switch are required.  This keeps a discovered symbol or
/// a normal Xenia launch from silently changing GPU ownership.
pub fn decide(
    request: Request,
    host_control_enabled: bool,
    provider_enabled: bool,
) Response {
    if (!requestIsCompatible(request)) {
        return Response.refused(.malformed_request, 0);
    }
    if (!provider_enabled) {
        return Response.refused(.provider_disabled, 0);
    }
    if (!host_control_enabled) {
        return Response.refused(.host_control_required, 0);
    }

    const flags = request.state_flags;
    if (!has(flags, state_module_present)) {
        return Response.refused(.module_missing, flags);
    }
    if (request.entry_point == 0 or !has(flags, state_entry_resolved)) {
        return Response.refused(.entry_unresolved, flags);
    }
    if (!has(flags, state_load_idle)) {
        return Response.refused(.load_inflight, flags);
    }
    if (!has(flags, state_graphics_ready)) {
        return Response.refused(.graphics_not_ready, flags);
    }
    if (!has(flags, state_command_processor_ready)) {
        return Response.refused(.command_processor_not_ready, flags);
    }
    if (!has(flags, state_guest_main_running)) {
        return Response.refused(.guest_main_not_running, flags);
    }
    if (!has(flags, state_guest_callback_missing)) {
        return Response.refused(
            if (request.guest_callback_token != 0)
                .guest_callback_present
            else
                .guest_callback_state_unknown,
            flags,
        );
    }
    if (!has(flags, state_host_callback_missing)) {
        return Response.refused(
            if (request.host_callback_token != 0)
                .host_callback_present
            else
                .host_callback_state_unknown,
            flags,
        );
    }
    if (!has(flags, state_ring_ready) and !has(flags, state_ring_not_ready)) {
        return Response.refused(.ring_state_unknown, flags);
    }
    if (!has(flags, state_bootstrap_activity_seen) and
        !has(flags, state_bootstrap_activity_absent)) {
        return Response.refused(.bootstrap_activity_unknown, flags);
    }
    if (!has(flags, state_cadence_ready) or request.vblank_id == 0) {
        return Response.refused(.cadence_not_ready, flags);
    }

    return .{
        .size = @sizeOf(Response),
        .schema = schema_version,
        .decision = @intFromEnum(Decision.allow),
        .reason = @intFromEnum(Reason.none),
        .actions = action_install_host_interrupt_callback,
        .proof_mask = flags,
        // Xenia stops asking once it has installed the callback.  Binding the
        // report to this vblank prevents an old approval from being replayed
        // against a later startup state.
        .authorization_id = request.vblank_id,
    };
}

pub fn actionAllowed(response: Response, action: Action) bool {
    return response.decision == @intFromEnum(Decision.allow) and
        response.actions & actionBit(action) != 0;
}

pub fn fabricatesGuestCallback(_: Response) bool {
    return false;
}

pub fn contractIsWellFormed() bool {
    if (@sizeOf(Request) != 56 or @sizeOf(Response) != 32) return false;
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

fn readyFlags() u32 {
    return state_module_present | state_entry_resolved | state_load_idle |
        state_graphics_ready | state_command_processor_ready |
        state_guest_main_running | state_guest_callback_missing |
        state_host_callback_missing | state_ring_not_ready |
        state_bootstrap_activity_absent | state_cadence_ready;
}

test "host GPU callback contract has stable pointer-free layout" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(Request));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Response));
    try std.testing.expect(!fabricatesGuestCallback(.{}));
}

test "provider and host control are both required" {
    const request = Request.init(1, 2, readyFlags(), 0, 0, 3, 1, 16);
    const provider_refused = decide(request, true, false);
    try std.testing.expectEqual(
        Reason.provider_disabled,
        @as(Reason, @enumFromInt(provider_refused.reason)),
    );
    const control_refused = decide(request, false, true);
    try std.testing.expectEqual(
        Reason.host_control_required,
        @as(Reason, @enumFromInt(control_refused.reason)),
    );
}

test "missing bootstrap activity can authorize only the host callback" {
    const request = Request.init(0x4D5307E6, 0x82582A98, readyFlags(), 0, 0, 7, 32, 515);
    const response = decide(request, true, true);
    try std.testing.expectEqual(
        Decision.allow,
        @as(Decision, @enumFromInt(response.decision)),
    );
    try std.testing.expect(actionAllowed(response, .install_host_interrupt_callback));
    try std.testing.expectEqual(
        action_install_host_interrupt_callback,
        response.actions,
    );
    try std.testing.expect(responseIsCompatible(response));
}

test "guest callback presence never authorizes a host replacement" {
    const request = Request.init(
        1,
        2,
        readyFlags() & ~state_guest_callback_missing,
        0x1000,
        0,
        3,
        1,
        16,
    );
    const response = decide(request, true, true);
    try std.testing.expectEqual(
        Reason.guest_callback_present,
        @as(Reason, @enumFromInt(response.reason)),
    );
}

test "unknown ring or activity state refuses closed" {
    const request = Request.init(
        1,
        2,
        readyFlags() & ~state_ring_not_ready & ~state_bootstrap_activity_absent,
        0,
        0,
        3,
        1,
        16,
    );
    const response = decide(request, true, true);
    try std.testing.expectEqual(
        Reason.ring_state_unknown,
        @as(Reason, @enumFromInt(response.reason)),
    );
}

test "malformed response cannot smuggle an action" {
    var response = Response.refused(.provider_disabled, 0);
    response.actions = action_install_host_interrupt_callback;
    try std.testing.expect(!responseIsCompatible(response));
}
