//! Immutable Cocoa graphics ownership, handoff and routing rules.
//!
//! Cocoa is the rendezvous point, not a second emulator. It owns the native
//! application/window/layer/drawable identities. Vulkan, MoltenVK, SDL, Xenia
//! and Rosette may create resources that borrow that sink, but none of them may
//! silently become the owner merely because it printed a handle or completed a
//! diagnostic clear.

const std = @import("std");

pub const schema_version: u16 = 1;

pub const Domain = enum(u8) {
    unknown,
    guest_title,
    xenia_powerpc,
    xenia_host,
    xenia_vulkan,
    sdl,
    rosette_runtime,
    cocoa_appkit,
    moltenvk,
    vulkan_driver,
    metal_driver,

    pub fn label(self: Domain) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .guest_title => "guest:title",
            .xenia_powerpc => "xenia:powerpc",
            .xenia_host => "xenia:host",
            .xenia_vulkan => "xenia:vulkan",
            .sdl => "sdl",
            .rosette_runtime => "rosette:runtime",
            .cocoa_appkit => "cocoa:appkit",
            .moltenvk => "moltenvk",
            .vulkan_driver => "vulkan:driver",
            .metal_driver => "metal:driver",
        };
    }
};

pub fn domainBit(domain: Domain) u16 {
    return @as(u16, 1) << @as(u4, @intCast(@intFromEnum(domain)));
}

/// Identities whose ownership or use must never be inferred from a similarly
/// named counter in another subsystem.
pub const Resource = enum(u8) {
    appkit_application,
    appkit_window,
    appkit_content_view,
    metal_layer,
    metal_device,
    metal_drawable,
    sdl_event_loop,
    sdl_window_binding,
    rosette_vulkan_instance,
    rosette_vulkan_surface,
    rosette_vulkan_device,
    rosette_vulkan_queue,
    rosette_vulkan_swapchain,
    xenia_vulkan_instance,
    xenia_vulkan_surface,
    xenia_vulkan_device,
    xenia_vulkan_queue,
    xenia_vulkan_swapchain,
    xenos_ring,
    xenos_command_stream,
    xenos_render_target,
    xenos_front_buffer,
    powerpc_interrupt_callback,
    translated_x86_callback,
    guest_frame,
    xenia_host_frame,
    diagnostic_frame,
    presentation_sink,

    pub fn label(self: Resource) []const u8 {
        return switch (self) {
            .appkit_application => "NSApplication",
            .appkit_window => "NSWindow",
            .appkit_content_view => "NSView",
            .metal_layer => "CAMetalLayer",
            .metal_device => "MTLDevice",
            .metal_drawable => "CAMetalDrawable",
            .sdl_event_loop => "SDL event loop",
            .sdl_window_binding => "SDL Cocoa window binding",
            .rosette_vulkan_instance => "Rosette VkInstance",
            .rosette_vulkan_surface => "Rosette VkSurfaceKHR",
            .rosette_vulkan_device => "Rosette VkDevice",
            .rosette_vulkan_queue => "Rosette VkQueue",
            .rosette_vulkan_swapchain => "Rosette VkSwapchainKHR",
            .xenia_vulkan_instance => "Xenia VkInstance",
            .xenia_vulkan_surface => "Xenia VkSurfaceKHR",
            .xenia_vulkan_device => "Xenia VkDevice",
            .xenia_vulkan_queue => "Xenia VkQueue",
            .xenia_vulkan_swapchain => "Xenia VkSwapchainKHR",
            .xenos_ring => "Xenos ring",
            .xenos_command_stream => "Xenos command stream",
            .xenos_render_target => "Xenos render target",
            .xenos_front_buffer => "Xenos front buffer",
            .powerpc_interrupt_callback => "PowerPC graphics callback",
            .translated_x86_callback => "translated x86 callback",
            .guest_frame => "guest-produced frame",
            .xenia_host_frame => "Xenia host-rendered frame",
            .diagnostic_frame => "Rosette diagnostic frame",
            .presentation_sink => "Cocoa presentation sink",
        };
    }

    pub fn expectedOwner(self: Resource) Domain {
        return switch (self) {
            .appkit_application,
            .appkit_window,
            .appkit_content_view,
            .metal_layer,
            .presentation_sink,
            => .cocoa_appkit,
            .metal_device, .metal_drawable => .metal_driver,
            .sdl_event_loop, .sdl_window_binding => .sdl,
            .rosette_vulkan_instance,
            .rosette_vulkan_surface,
            .rosette_vulkan_device,
            .rosette_vulkan_queue,
            .rosette_vulkan_swapchain,
            .diagnostic_frame,
            => .rosette_runtime,
            .xenia_vulkan_instance,
            .xenia_vulkan_surface,
            .xenia_vulkan_device,
            .xenia_vulkan_queue,
            .xenia_vulkan_swapchain,
            => .xenia_vulkan,
            .xenos_ring, .xenos_front_buffer, .guest_frame => .guest_title,
            .xenos_command_stream, .xenos_render_target, .xenia_host_frame => .xenia_host,
            .powerpc_interrupt_callback => .xenia_powerpc,
            .translated_x86_callback => .rosette_runtime,
        };
    }

    pub fn singleton(self: Resource) bool {
        return switch (self) {
            .appkit_application,
            .appkit_window,
            .appkit_content_view,
            .metal_layer,
            .metal_device,
            .sdl_event_loop,
            .sdl_window_binding,
            .rosette_vulkan_instance,
            .rosette_vulkan_surface,
            .rosette_vulkan_device,
            .rosette_vulkan_queue,
            .rosette_vulkan_swapchain,
            .xenia_vulkan_instance,
            .xenia_vulkan_surface,
            .xenia_vulkan_device,
            .xenia_vulkan_queue,
            .xenia_vulkan_swapchain,
            .xenos_ring,
            .xenos_front_buffer,
            .powerpc_interrupt_callback,
            .translated_x86_callback,
            .presentation_sink,
            => true,
            .metal_drawable,
            .xenos_command_stream,
            .xenos_render_target,
            .guest_frame,
            .xenia_host_frame,
            .diagnostic_frame,
            => false,
        };
    }

    /// Resources are normally owned permanently and borrowed. Frames and
    /// drawables are the exceptions: their custody moves for each transaction.
    pub fn transferable(self: Resource) bool {
        return switch (self) {
            .metal_drawable, .guest_frame, .xenia_host_frame, .diagnostic_frame => true,
            else => false,
        };
    }
};

pub const Authority = enum(u8) {
    observer,
    borrower,
    provider,
    canonical_owner,
    diagnostic_substitute,

    pub fn label(self: Authority) []const u8 {
        return switch (self) {
            .observer => "observer",
            .borrower => "borrower",
            .provider => "provider",
            .canonical_owner => "canonical-owner",
            .diagnostic_substitute => "diagnostic-substitute",
        };
    }
};

pub const Evidence = enum(u8) {
    none,
    inference,
    log_claim,
    observed_state,
    intercepted_call,
    completed_call,
    /// A host synchronization primitive (for example a Metal command-buffer
    /// status or a Vulkan fence) proved that submitted GPU work completed.
    /// This is stronger and more specific than an API returning successfully.
    hardware_completed,

    pub fn label(self: Evidence) []const u8 {
        return switch (self) {
            .none => "none",
            .inference => "inference",
            .log_claim => "log-claim",
            .observed_state => "observed-state",
            .intercepted_call => "intercepted-call",
            .completed_call => "completed-call",
            .hardware_completed => "hardware-completed",
        };
    }

    pub fn provesIdentity(self: Evidence) bool {
        return @intFromEnum(self) >= @intFromEnum(Evidence.observed_state);
    }

    pub fn provesEffect(self: Evidence) bool {
        return self == .completed_call or self == .hardware_completed;
    }
};

/// The common semantic names exposed to Cocoa-facing adapters. These are API
/// operations, never CPU opcodes.
pub const Operation = enum(u8) {
    ensure_application,
    ensure_window,
    attach_metal_layer,
    bind_sdl_window,
    pump_events,
    create_vulkan_surface,
    create_swapchain,
    acquire_drawable,
    publish_ring,
    consume_pm4,
    program_render_target,
    submit_draw,
    signal_completion,
    dispatch_completion,
    vd_swap,
    xe_swap,
    issue_swap,
    offer_guest_frame,
    present_guest_frame,
    present_diagnostic_frame,

    pub fn label(self: Operation) []const u8 {
        return switch (self) {
            .ensure_application => "cocoa.ensure_application",
            .ensure_window => "cocoa.ensure_window",
            .attach_metal_layer => "cocoa.attach_metal_layer",
            .bind_sdl_window => "cocoa.bind_sdl_window",
            .pump_events => "cocoa.pump_events",
            .create_vulkan_surface => "vulkan.create_metal_surface",
            .create_swapchain => "vulkan.create_swapchain",
            .acquire_drawable => "cocoa.acquire_drawable",
            .publish_ring => "xenos.publish_ring",
            .consume_pm4 => "xenos.consume_pm4",
            .program_render_target => "xenos.program_render_target",
            .submit_draw => "xenos.submit_draw",
            .signal_completion => "xenos.signal_completion",
            .dispatch_completion => "xenos.dispatch_completion",
            .vd_swap => "xenos.vd_swap",
            .xe_swap => "xenos.xe_swap",
            .issue_swap => "xenia.issue_swap",
            .offer_guest_frame => "cocoa.offer_guest_frame",
            .present_guest_frame => "cocoa.present_guest_frame",
            .present_diagnostic_frame => "cocoa.present_diagnostic_frame",
        };
    }
};

pub const Stage = enum(u8) {
    application_ready,
    window_ready,
    content_view_ready,
    metal_layer_ready,
    metal_device_ready,
    sdl_ready,
    sdl_window_bound,
    rosette_vulkan_instance_ready,
    rosette_vulkan_surface_ready,
    rosette_vulkan_device_ready,
    rosette_vulkan_queue_ready,
    rosette_vulkan_swapchain_ready,
    xenia_vulkan_instance_ready,
    xenia_vulkan_surface_ready,
    xenia_vulkan_device_ready,
    xenia_vulkan_queue_ready,
    xenia_vulkan_swapchain_ready,
    xenia_vulkan_submission_seen,
    xenia_vulkan_present_seen,
    /// A present request was followed by an explicit host synchronization edge.
    /// The request stage above intentionally remains weaker: it can be true
    /// while the queue still has work in flight.
    xenia_vulkan_present_completed,
    xenos_ring_ready,
    xenos_render_target_ready,
    powerpc_callback_registered,
    powerpc_callback_returned,
    guest_vdswap_entered,
    guest_xe_swap_encoded,
    authentic_xe_swap_consumed,
    issue_swap_entered,
    guest_frame_offered,
    xenia_host_frame_offered,
    guest_frame_presented_vulkan,
    guest_frame_presented_metal,
    diagnostic_frame_presented,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .application_ready => "NSApplication ready",
            .window_ready => "NSWindow ready",
            .content_view_ready => "NSView ready",
            .metal_layer_ready => "CAMetalLayer ready",
            .metal_device_ready => "MTLDevice ready",
            .sdl_ready => "SDL initialized",
            .sdl_window_bound => "SDL window bound to Cocoa",
            .rosette_vulkan_instance_ready => "Rosette Vulkan instance ready",
            .rosette_vulkan_surface_ready => "Rosette Vulkan surface ready",
            .rosette_vulkan_device_ready => "Rosette Vulkan device ready",
            .rosette_vulkan_queue_ready => "Rosette Vulkan queue ready",
            .rosette_vulkan_swapchain_ready => "Rosette Vulkan swapchain ready",
            .xenia_vulkan_instance_ready => "Xenia Vulkan instance ready",
            .xenia_vulkan_surface_ready => "Xenia Vulkan surface ready",
            .xenia_vulkan_device_ready => "Xenia Vulkan device ready",
            .xenia_vulkan_queue_ready => "Xenia Vulkan queue ready",
            .xenia_vulkan_swapchain_ready => "Xenia Vulkan swapchain ready",
            .xenia_vulkan_submission_seen => "Xenia Vulkan submission observed",
            .xenia_vulkan_present_seen => "Xenia Vulkan present observed",
            .xenia_vulkan_present_completed => "Xenia Vulkan present GPU work completed",
            .xenos_ring_ready => "Xenos ring ready",
            .xenos_render_target_ready => "Xenos render target ready",
            .powerpc_callback_registered => "PowerPC interrupt callback registered",
            .powerpc_callback_returned => "PowerPC interrupt callback returned",
            .guest_vdswap_entered => "guest VdSwap entered",
            .guest_xe_swap_encoded => "guest XE_SWAP encoded",
            .authentic_xe_swap_consumed => "authentic XE_SWAP consumed",
            .issue_swap_entered => "IssueSwap entered",
            .guest_frame_offered => "guest frame offered",
            .xenia_host_frame_offered => "Xenia host-rendered frame offered",
            .guest_frame_presented_vulkan => "guest frame presented through Vulkan",
            .guest_frame_presented_metal => "guest frame presented through Cocoa/Metal fallback",
            .diagnostic_frame_presented => "diagnostic frame presented",
        };
    }

    pub fn expectedOwner(self: Stage) Domain {
        return switch (self) {
            .application_ready, .window_ready, .content_view_ready, .metal_layer_ready => .cocoa_appkit,
            .metal_device_ready => .metal_driver,
            .sdl_ready, .sdl_window_bound => .sdl,
            .rosette_vulkan_instance_ready,
            .rosette_vulkan_surface_ready,
            .rosette_vulkan_device_ready,
            .rosette_vulkan_queue_ready,
            .rosette_vulkan_swapchain_ready,
            .guest_frame_presented_vulkan,
            .guest_frame_presented_metal,
            .diagnostic_frame_presented,
            => .rosette_runtime,
            .xenia_vulkan_instance_ready,
            .xenia_vulkan_surface_ready,
            .xenia_vulkan_device_ready,
            .xenia_vulkan_queue_ready,
            .xenia_vulkan_swapchain_ready,
            .xenia_vulkan_submission_seen,
            .xenia_vulkan_present_seen,
            .xenia_vulkan_present_completed,
            .issue_swap_entered,
            => .xenia_vulkan,
            .xenos_ring_ready, .guest_vdswap_entered, .guest_xe_swap_encoded => .guest_title,
            .xenos_render_target_ready => .xenia_host,
            .powerpc_callback_registered, .powerpc_callback_returned => .xenia_powerpc,
            .authentic_xe_swap_consumed => .xenia_host,
            .guest_frame_offered => .guest_title,
            .xenia_host_frame_offered => .xenia_host,
        };
    }
};

pub const stage_count: usize = @typeInfo(Stage).@"enum".fields.len;

pub const AddressSpace = enum(u8) {
    none,
    host_native,
    translated_x86,
    xenia_powerpc,
    xbox_physical,
    cocoa_object,
    vulkan_handle,
    metal_object,

    pub fn label(self: AddressSpace) []const u8 {
        return switch (self) {
            .none => "none",
            .host_native => "host-native",
            .translated_x86 => "translated-x86",
            .xenia_powerpc => "xenia-powerpc",
            .xbox_physical => "xbox-physical",
            .cocoa_object => "cocoa-object",
            .vulkan_handle => "vulkan-handle",
            .metal_object => "metal-object",
        };
    }
};

pub const Executor = enum(u8) {
    native_host,
    translated_x86,
    xenia_powerpc,

    pub fn addressSpace(self: Executor) AddressSpace {
        return switch (self) {
            .native_host => .host_native,
            .translated_x86 => .translated_x86,
            .xenia_powerpc => .xenia_powerpc,
        };
    }
};

pub const CallbackEndpoint = struct {
    address: u64 = 0,
    space: AddressSpace = .none,
    owner: Domain = .unknown,
    evidence: Evidence = .none,

    pub fn known(self: CallbackEndpoint) bool {
        return self.address != 0 and self.space != .none and self.owner != .unknown;
    }
};

/// A callable address is not portable between Xenia's PowerPC guest and the
/// translated x86 Mach-O executor. Equal integers in those spaces are still
/// different endpoints.
pub fn canInvoke(executor: Executor, endpoint: CallbackEndpoint) bool {
    return endpoint.known() and endpoint.evidence.provesIdentity() and
        executor.addressSpace() == endpoint.space;
}

/// Frame truth is deliberately orthogonal. A host-cadenced presentation may
/// contain real guest pixels while still proving no guest swap.
pub const FrameTruth = struct {
    guest_pixels: bool = false,
    guest_requested_present: bool = false,
    native_present_completed: bool = false,
    synthetic_guest_control: bool = false,

    pub fn class(self: FrameTruth) FrameClass {
        if (self.synthetic_guest_control) return .synthetic_guest_control;
        if (!self.guest_pixels) return if (self.native_present_completed) .diagnostic_host else .none;
        if (self.guest_requested_present and self.native_present_completed) return .authentic_guest_present;
        if (self.native_present_completed) return .guest_pixels_host_cadence;
        return .guest_pixels_unpresented;
    }
};

pub const FrameClass = enum(u8) {
    none,
    diagnostic_host,
    guest_pixels_unpresented,
    guest_pixels_host_cadence,
    authentic_guest_present,
    synthetic_guest_control,

    pub fn label(self: FrameClass) []const u8 {
        return switch (self) {
            .none => "none",
            .diagnostic_host => "diagnostic-host",
            .guest_pixels_unpresented => "guest-pixels-unpresented",
            .guest_pixels_host_cadence => "guest-pixels-host-cadence",
            .authentic_guest_present => "authentic-guest-present",
            .synthetic_guest_control => "synthetic-guest-control",
        };
    }

    pub fn countsGuestPixels(self: FrameClass) bool {
        return switch (self) {
            .guest_pixels_unpresented, .guest_pixels_host_cadence, .authentic_guest_present => true,
            else => false,
        };
    }

    pub fn closesAuthenticSwap(self: FrameClass) bool {
        return self == .authentic_guest_present;
    }
};

pub const RoutePolicy = enum(u8) {
    observe_only,
    diagnostic_only,
    verified_guest_fallback,

    pub fn label(self: RoutePolicy) []const u8 {
        return switch (self) {
            .observe_only => "observe-only",
            .diagnostic_only => "diagnostic-only",
            .verified_guest_fallback => "verified-guest-fallback",
        };
    }
};

pub const Route = enum(u8) {
    wait,
    xenia_native,
    rosette_vulkan_guest_copy,
    cocoa_metal_guest_copy,
    cocoa_diagnostic,
    quarantine_conflict,

    pub fn label(self: Route) []const u8 {
        return switch (self) {
            .wait => "wait",
            .xenia_native => "xenia-native",
            .rosette_vulkan_guest_copy => "rosette-vulkan-guest-copy",
            .cocoa_metal_guest_copy => "cocoa-metal-guest-copy",
            .cocoa_diagnostic => "cocoa-diagnostic",
            .quarantine_conflict => "quarantine-conflict",
        };
    }
};

pub const RouteInput = struct {
    policy: RoutePolicy = .observe_only,
    ownership_conflict: bool = false,
    cocoa_ready: bool = false,
    rosette_vulkan_ready: bool = false,
    xenia_presenter_ready: bool = false,
    xenia_present_seen: bool = false,
    verified_guest_frame: bool = false,
    guest_frame_format_supported: bool = false,
    metal_guest_copy_ready: bool = false,
    diagnostic_requested: bool = false,
};

/// Choose the least substitutive route. No route fabricates a VdSwap or an
/// XE_SWAP; a verified guest buffer can be shown on host cadence while those
/// guest-owned boundaries remain open.
pub fn decideRoute(input: RouteInput) Route {
    if (input.ownership_conflict) return .quarantine_conflict;
    if (input.xenia_presenter_ready and input.xenia_present_seen) return .xenia_native;
    if (input.verified_guest_frame and input.guest_frame_format_supported) {
        if (input.rosette_vulkan_ready) return .rosette_vulkan_guest_copy;
        if (input.policy == .verified_guest_fallback and input.cocoa_ready and input.metal_guest_copy_ready)
            return .cocoa_metal_guest_copy;
    }
    if (input.diagnostic_requested and input.policy != .observe_only and input.cocoa_ready)
        return .cocoa_diagnostic;
    return .wait;
}

pub fn mayBorrow(resource: Resource, borrower: Domain) bool {
    return switch (resource) {
        .appkit_window, .appkit_content_view => borrower == .sdl or borrower == .xenia_host or borrower == .rosette_runtime,
        .metal_layer, .presentation_sink => borrower == .xenia_vulkan or borrower == .rosette_runtime or borrower == .moltenvk or borrower == .vulkan_driver,
        .metal_device => borrower == .rosette_runtime or borrower == .moltenvk or borrower == .vulkan_driver,
        .guest_frame => borrower == .xenia_host or borrower == .xenia_vulkan or borrower == .rosette_runtime,
        .xenia_host_frame => borrower == .xenia_vulkan or borrower == .rosette_runtime,
        .xenos_front_buffer => borrower == .xenia_host or borrower == .rosette_runtime,
        .powerpc_interrupt_callback => borrower == .xenia_host,
        else => borrower == resource.expectedOwner(),
    };
}

pub fn contractIsWellFormed() bool {
    if (schema_version == 0 or stage_count == 0 or stage_count > 64) return false;
    inline for (@typeInfo(Domain).@"enum".fields) |field| {
        if (@as(Domain, @enumFromInt(field.value)).label().len == 0) return false;
    }
    inline for (@typeInfo(Resource).@"enum".fields) |field| {
        const resource: Resource = @enumFromInt(field.value);
        if (resource.label().len == 0 or resource.expectedOwner() == .unknown) return false;
    }
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        if (stage.label().len == 0 or stage.expectedOwner() == .unknown) return false;
    }
    inline for (@typeInfo(Operation).@"enum".fields) |field| {
        if (@as(Operation, @enumFromInt(field.value)).label().len == 0) return false;
    }
    if (canInvoke(.translated_x86, .{
        .address = 0x8219_51F8,
        .space = .xenia_powerpc,
        .owner = .xenia_powerpc,
        .evidence = .completed_call,
    })) return false;
    if (!FrameClass.guest_pixels_host_cadence.countsGuestPixels()) return false;
    if (FrameClass.guest_pixels_host_cadence.closesAuthenticSwap()) return false;
    return true;
}

test "PowerPC callback addresses cannot be entered by the x86 executor" {
    const ppc = CallbackEndpoint{
        .address = 0x8219_51F8,
        .space = .xenia_powerpc,
        .owner = .xenia_powerpc,
        .evidence = .completed_call,
    };
    try std.testing.expect(!canInvoke(.translated_x86, ppc));
    try std.testing.expect(canInvoke(.xenia_powerpc, ppc));
}

test "diagnostic presentation and guest pixels remain different truths" {
    try std.testing.expectEqual(FrameClass.diagnostic_host, (FrameTruth{
        .native_present_completed = true,
    }).class());
    try std.testing.expectEqual(FrameClass.guest_pixels_host_cadence, (FrameTruth{
        .guest_pixels = true,
        .native_present_completed = true,
    }).class());
    try std.testing.expectEqual(FrameClass.authentic_guest_present, (FrameTruth{
        .guest_pixels = true,
        .guest_requested_present = true,
        .native_present_completed = true,
    }).class());
}

test "routing chooses the least substitutive viable path" {
    try std.testing.expectEqual(Route.xenia_native, decideRoute(.{
        .policy = .verified_guest_fallback,
        .xenia_presenter_ready = true,
        .xenia_present_seen = true,
        .rosette_vulkan_ready = true,
        .verified_guest_frame = true,
        .guest_frame_format_supported = true,
    }));
    try std.testing.expectEqual(Route.rosette_vulkan_guest_copy, decideRoute(.{
        .policy = .verified_guest_fallback,
        .rosette_vulkan_ready = true,
        .verified_guest_frame = true,
        .guest_frame_format_supported = true,
    }));
    try std.testing.expectEqual(Route.cocoa_metal_guest_copy, decideRoute(.{
        .policy = .verified_guest_fallback,
        .cocoa_ready = true,
        .metal_guest_copy_ready = true,
        .verified_guest_frame = true,
        .guest_frame_format_supported = true,
    }));
}

test "an ownership conflict quarantines every fallback" {
    try std.testing.expectEqual(Route.quarantine_conflict, decideRoute(.{
        .policy = .verified_guest_fallback,
        .ownership_conflict = true,
        .cocoa_ready = true,
        .metal_guest_copy_ready = true,
        .verified_guest_frame = true,
        .guest_frame_format_supported = true,
    }));
}

test "Cocoa resources are borrowed rather than reassigned" {
    try std.testing.expectEqual(Domain.cocoa_appkit, Resource.metal_layer.expectedOwner());
    try std.testing.expect(mayBorrow(.metal_layer, .xenia_vulkan));
    try std.testing.expect(mayBorrow(.metal_layer, .rosette_runtime));
    try std.testing.expect(!Resource.metal_layer.transferable());
    try std.testing.expect(Resource.guest_frame.transferable());
}

test "contract is internally complete" {
    try std.testing.expect(contractIsWellFormed());
}
