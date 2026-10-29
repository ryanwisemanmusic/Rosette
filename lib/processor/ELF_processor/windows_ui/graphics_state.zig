//! Host-neutral graphics state and ordering ledger. The processor and
//! native adapters share these value types; no guest executor is imported.
const std = @import("std");
const testing = std.testing;
const frame_content_contract = @import("frame_content_contract");
const WindowsGraphicsHooks = @import("../windows_guest/host_interfaces.zig").WindowsGraphicsHooks;
const monotonicNanoseconds = @import("../diagnostics/monotonic_clock.zig").monotonicNanoseconds;
/// Guest-step ceiling paired with a host-time deadline so busy loops cannot
/// synchronously dispatch AppKit thousands of times per second.
pub const WINDOWS_EVENT_PUMP_STRIDE: u64 = 100_000_000;
pub const WINDOWS_EVENT_PUMP_INTERVAL_NS: u64 = 8 * std.time.ns_per_ms;
const GUEST_FRAME_RATE_SAMPLE_NS: u64 = 250 * std.time.ns_per_ms;

pub const WindowsGraphicsPhase = enum(u8) {
    cold,
    window_ready,
    instance_ready,
    surface_ready,
    device_ready,
    queue_ready,
    swapchain_ready,
    frame_resources_ready,
    present_ready,
    failed,
};

/// Win32 uses this value for position and size arguments that the window
/// manager should choose. It is not a usable Cocoa width or height. Keep the
/// policy in the guest graphics ledger so every Windows entry path agrees on
/// what can cross into the native window bridge.
pub const WINDOWS_CW_USEDEFAULT: u64 = 0x8000_0000;
pub const WINDOWS_DEFAULT_WIDTH: u32 = 1280;
pub const WINDOWS_DEFAULT_HEIGHT: u32 = 720;
pub const WINDOWS_MAX_DIMENSION: u64 = 16 * 1024;

fn normalizeWindowsWindowDimension(value: u64, fallback: u32) u32 {
    if (value == 0 or value == WINDOWS_CW_USEDEFAULT or value > WINDOWS_MAX_DIMENSION) {
        return fallback;
    }
    return @intCast(value);
}

/// A value-only report returned from a PE run.  It distinguishes a native
/// window from a real Vulkan frame: the current Rosetta Windows bridge owns a
/// native Cocoa/Metal window, but Vulkan calls are still logical guest calls
/// until a native Vulkan forwarding backend is installed.
pub const WindowsGraphicsSnapshot = struct {
    phase: WindowsGraphicsPhase = .cold,
    application_ready: bool = false,
    window_ready: bool = false,
    native_window_ready: bool = false,
    native_window_visible: bool = false,
    instance_ready: bool = false,
    surface_ready: bool = false,
    device_ready: bool = false,
    queue_ready: bool = false,
    swapchain_ready: bool = false,
    frame_resources_ready: bool = false,
    guest_present_observed: bool = false,
    native_vulkan_forwarding: bool = false,
    native_vulkan_calls: u64 = 0,
    /// Calls that arrived before Rosette had a native instance/device.  This
    /// is a readiness timeline, not a driver failure, and must not be folded
    /// into the error count.
    native_vulkan_pre_ready_calls: u64 = 0,
    native_vulkan_failures: u64 = 0,
    native_presenter_started: bool = false,
    native_presenter_ready: bool = false,
    native_presenter_stage: u32 = 0,
    native_presenter_attempts: u64 = 0,
    native_presenter_failures: u64 = 0,
    native_diagnostic_attempts: u64 = 0,
    native_diagnostic_frames: u64 = 0,
    native_diagnostic_failures: u64 = 0,
    window_create_attempts: u64 = 0,
    window_create_failures: u64 = 0,
    application_attempts: u64 = 0,
    show_attempts: u64 = 0,
    event_pump_calls: u64 = 0,
    /// Wall time inside the host event pump, which the interpreter is not
    /// running during.
    event_pump_nanos: u64 = 0,
    /// Pump requests the stride declined. Reported so the throttle is
    /// visible rather than an invisible change in behaviour.
    event_pump_skips: u64 = 0,
    next_event_pump_step: u64 = 0,
    vulkan_calls: u64 = 0,
    proc_queries: u64 = 0,
    instance_creations: u64 = 0,
    surface_creations: u64 = 0,
    device_creations: u64 = 0,
    queue_acquisitions: u64 = 0,
    swapchain_creations: u64 = 0,
    swapchain_image_queries: u64 = 0,
    image_acquires: u64 = 0,
    command_calls: u64 = 0,
    draw_commands: u64 = 0,
    dispatch_commands: u64 = 0,
    transfer_commands: u64 = 0,
    /// Commands whose output can depend on data the title supplied - a draw,
    /// a dispatch, a copy, a blit, a resolve. Counted apart from
    /// `command_calls` because a run can record commands and still put
    /// nothing but a colour on the screen, which is what the 2026-09-12 run
    /// did with `command_calls=2` and a verdict of healthy.
    content_commands: u64 = 0,
    /// Commands that can only write a constant: the clears.
    fill_commands: u64 = 0,
    queue_submits: u64 = 0,
    presents: u64 = 0,
    guest_presents_with_target: u64 = 0,
    guest_presents_with_content: u64 = 0,
    guest_presents_clear_only: u64 = 0,
    guest_presents_without_target: u64 = 0,
    guest_presents_without_write: u64 = 0,
    native_present_requests_observed: u64 = 0,
    native_present_completions_observed: u64 = 0,
    native_queue_submits_observed: u64 = 0,
    ordering_violations: u64 = 0,
    unmodeled_calls: u64 = 0,
    window_width: u32 = 1280,
    window_height: u32 = 720,
    last_call: [64:0]u8 = [_:0]u8{0} ** 64,
    last_failure: [96:0]u8 = [_:0]u8{0} ** 96,

    pub fn contractReady(self: *const WindowsGraphicsSnapshot) bool {
        return self.window_ready and self.instance_ready and self.surface_ready and
            self.device_ready and self.queue_ready and self.swapchain_ready and
            self.frame_resources_ready and self.ordering_violations == 0;
    }

    pub fn nativeWindowReady(self: *const WindowsGraphicsSnapshot) bool {
        return self.native_window_ready and self.native_window_visible;
    }

    pub fn nativePresenterReady(self: *const WindowsGraphicsSnapshot) bool {
        return self.native_presenter_ready;
    }
};

/// State machine for the Windows UI/Vulkan contract.
///
/// Previous Windows imports returned success independently of one another, so
/// a PE could appear to have initialized graphics while no window, surface,
/// queue, or swapchain had ever been established.  This ledger makes every
/// transition observable and rejects impossible Vulkan ordering at the guest
/// ABI boundary.  It is intentionally backend-neutral; only the window
/// callbacks are host-facing in this pass.
pub const WindowsGraphicsState = struct {
    hooks: WindowsGraphicsHooks = .{},
    phase: WindowsGraphicsPhase = .cold,
    application_ready: bool = false,
    window_ready: bool = false,
    native_window_ready: bool = false,
    native_window_visible: bool = false,
    instance_ready: bool = false,
    surface_ready: bool = false,
    device_ready: bool = false,
    queue_ready: bool = false,
    swapchain_ready: bool = false,
    frame_resources_ready: bool = false,
    guest_present_observed: bool = false,
    native_vulkan_forwarding: bool = false,
    native_vulkan_calls: u64 = 0,
    native_vulkan_pre_ready_calls: u64 = 0,
    native_vulkan_failures: u64 = 0,
    native_presenter_started: bool = false,
    native_presenter_ready: bool = false,
    native_presenter_stage: u32 = 0,
    native_presenter_attempts: u64 = 0,
    native_presenter_failures: u64 = 0,
    native_diagnostic_attempts: u64 = 0,
    native_diagnostic_frames: u64 = 0,
    native_diagnostic_failures: u64 = 0,
    window_create_attempts: u64 = 0,
    window_create_failures: u64 = 0,
    application_attempts: u64 = 0,
    show_attempts: u64 = 0,
    event_pump_calls: u64 = 0,
    /// Wall time inside the host event pump, which the interpreter is not
    /// running during.
    event_pump_nanos: u64 = 0,
    /// Pump requests the stride declined. Reported so the throttle is
    /// visible rather than an invisible change in behaviour.
    event_pump_skips: u64 = 0,
    next_event_pump_step: u64 = 0,
    next_event_pump_nanos: u64 = 0,
    guest_frame_count: u64 = 0,
    guest_frame_rate_sample_count: u64 = 0,
    guest_frame_rate_sample_ns: u64 = 0,
    guest_frame_rate_started: bool = false,
    vulkan_calls: u64 = 0,
    proc_queries: u64 = 0,
    instance_creations: u64 = 0,
    surface_creations: u64 = 0,
    device_creations: u64 = 0,
    queue_acquisitions: u64 = 0,
    swapchain_creations: u64 = 0,
    swapchain_image_queries: u64 = 0,
    image_acquires: u64 = 0,
    command_calls: u64 = 0,
    draw_commands: u64 = 0,
    dispatch_commands: u64 = 0,
    transfer_commands: u64 = 0,
    /// Commands whose output can depend on data the title supplied - a draw,
    /// a dispatch, a copy, a blit, a resolve. Counted apart from
    /// `command_calls` because a run can record commands and still put
    /// nothing but a colour on the screen, which is what the 2026-09-12 run
    /// did with `command_calls=2` and a verdict of healthy.
    content_commands: u64 = 0,
    /// Commands that can only write a constant: the clears.
    fill_commands: u64 = 0,
    queue_submits: u64 = 0,
    presents: u64 = 0,
    guest_presents_with_target: u64 = 0,
    guest_presents_with_content: u64 = 0,
    guest_presents_clear_only: u64 = 0,
    guest_presents_without_target: u64 = 0,
    guest_presents_without_write: u64 = 0,
    native_present_requests_observed: u64 = 0,
    native_present_completions_observed: u64 = 0,
    native_queue_submits_observed: u64 = 0,
    ordering_violations: u64 = 0,
    unmodeled_calls: u64 = 0,
    window_width: u32 = 1280,
    window_height: u32 = 720,
    last_call: [64:0]u8 = [_:0]u8{0} ** 64,
    last_failure: [96:0]u8 = [_:0]u8{0} ** 96,

    fn copyLabel(destination: []u8, source: []const u8) void {
        @memset(destination, 0);
        const count = @min(source.len, destination.len - 1);
        @memcpy(destination[0..count], source[0..count]);
    }

    fn noteCall(self: *WindowsGraphicsState, name: []const u8) void {
        self.vulkan_calls +|= 1;
        copyLabel(&self.last_call, name);
    }

    fn advance(self: *WindowsGraphicsState, phase: WindowsGraphicsPhase) void {
        if (self.phase == .failed) return;
        if (@intFromEnum(phase) > @intFromEnum(self.phase)) self.phase = phase;
    }

    fn violation(self: *WindowsGraphicsState, name: []const u8, reason: []const u8) void {
        self.ordering_violations +|= 1;
        self.phase = .failed;
        var label_buf: [96]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{s}: {s}", .{ name, reason }) catch reason;
        copyLabel(&self.last_failure, label);
    }

    pub fn ensureApplication(self: *WindowsGraphicsState) bool {
        self.application_attempts +|= 1;
        if (self.application_ready) return true;
        if (self.hooks.ensure_application) |callback| {
            self.native_window_ready = callback(self.hooks.context) != 0;
            if (!self.native_window_ready) return false;
        }
        self.application_ready = true;
        return true;
    }

    pub fn ensureWindow(self: *WindowsGraphicsState, width: u64, height: u64, title: []const u8) bool {
        self.window_create_attempts +|= 1;
        const requested_width = normalizeWindowsWindowDimension(width, WINDOWS_DEFAULT_WIDTH);
        const requested_height = normalizeWindowsWindowDimension(height, WINDOWS_DEFAULT_HEIGHT);
        // Surface creation asks the host window adapter to ensure its HWND is
        // ready as well. Once the window contract has succeeded, repeating the
        // native callback from a Vulkan worker can synchronously marshal back
        // to AppKit's main queue while the guest UI continuation is parked.
        // Reuse the established window for the same extent instead of issuing
        // another cross-thread AppKit request.
        if (self.window_ready and self.window_width == requested_width and
            self.window_height == requested_height)
        {
            return true;
        }
        self.window_width = requested_width;
        self.window_height = requested_height;
        if (!self.ensureApplication()) {
            self.window_create_failures +|= 1;
            return false;
        }

        var title_buffer: [256:0]u8 = [_:0]u8{0} ** 256;
        copyLabel(&title_buffer, title);
        var ok = true;
        if (self.hooks.ensure_window) |callback| {
            ok = callback(self.hooks.context, self.window_width, self.window_height, &title_buffer) != 0;
            self.native_window_ready = ok;
        }
        if (!ok) {
            self.window_create_failures +|= 1;
            return false;
        }
        self.window_ready = true;
        self.advance(.window_ready);
        return true;
    }

    pub fn showWindow(self: *WindowsGraphicsState) bool {
        self.show_attempts +|= 1;
        if (!self.window_ready) {
            self.violation("ShowWindow", "window was not created");
            return false;
        }
        var ok = true;
        if (self.hooks.show_window) |callback| {
            ok = callback(self.hooks.context) != 0;
            self.native_window_visible = ok;
        }
        if (!ok) return false;
        if (self.hooks.show_window == null) self.native_window_visible = false;
        return true;
    }

    /// Drain the host event queue at a bounded guest-step and host-time rate.
    ///
    /// Xenia's `RunMainMessageLoop` calls `GetMessage` in a tight loop, and
    /// Rosette pumped AppKit on every one of them: 12.7 million dispatches to
    /// the main thread in the 2026-09-12 run, one per ~18 guest instructions.
    /// A window's event queue does not have events at that rate. The dual
    /// cadence prevents a fast guest from flooding AppKit and also keeps
    /// input responsive when a guest is running slowly.
    ///
    /// `force` is for the callers that must not be throttled - a paint is
    /// pending, or the guest is about to block - where a missed pump is a
    /// missed frame rather than a missed millisecond.
    pub fn pumpEventsAtStep(self: *WindowsGraphicsState, step: u64, force: bool) u32 {
        return self.pumpEventsAtStepAtTime(step, force, monotonicNanoseconds());
    }

    fn pumpEventsAtStepAtTime(self: *WindowsGraphicsState, step: u64, force: bool, now_ns: u64) u32 {
        const step_deadline_reached = step >= self.next_event_pump_step;
        const time_deadline_reached = self.next_event_pump_nanos == 0 or now_ns >= self.next_event_pump_nanos;
        if (!force and !step_deadline_reached and !time_deadline_reached) {
            self.event_pump_skips +|= 1;
            return 0;
        }
        self.next_event_pump_step = step +| WINDOWS_EVENT_PUMP_STRIDE;
        self.next_event_pump_nanos = now_ns +| WINDOWS_EVENT_PUMP_INTERVAL_NS;
        return self.pumpEvents();
    }

    /// Count completed non-Vulkan guest frames and publish their recent rate
    /// to the native HUD. Vulkan applications update the same HUD in their
    /// forwarder; SDL-rendered PE games use this boundary instead.
    pub fn noteGuestFramePresented(self: *WindowsGraphicsState) void {
        self.noteGuestFramePresentedAt(monotonicNanoseconds());
    }

    fn noteGuestFramePresentedAt(self: *WindowsGraphicsState, now_ns: u64) void {
        self.guest_frame_count +|= 1;
        if (!self.guest_frame_rate_started) {
            self.guest_frame_rate_started = true;
            self.guest_frame_rate_sample_count = self.guest_frame_count;
            self.guest_frame_rate_sample_ns = now_ns;
            return;
        }
        if (now_ns < self.guest_frame_rate_sample_ns or
            now_ns - self.guest_frame_rate_sample_ns < GUEST_FRAME_RATE_SAMPLE_NS) return;

        const elapsed_ns = now_ns - self.guest_frame_rate_sample_ns;
        const completed_frames = self.guest_frame_count -| self.guest_frame_rate_sample_count;
        const fps_milli: u64 = if (completed_frames == 0 or elapsed_ns == 0)
            0
        else
            @intCast(@min(
                @as(u128, completed_frames) * 1_000_000_000_000 / elapsed_ns,
                std.math.maxInt(u64),
            ));
        self.guest_frame_rate_sample_count = self.guest_frame_count;
        self.guest_frame_rate_sample_ns = now_ns;
        if (self.hooks.set_frame_counter) |callback| {
            callback(self.hooks.native_context, self.guest_frame_count, fps_milli);
        }
    }

    pub fn pumpEvents(self: *WindowsGraphicsState) u32 {
        self.event_pump_calls +|= 1;
        const callback = self.hooks.pump_events orelse return 0;
        // The guest's message loop calls this on every GetMessage, and on
        // this host the callback is a dispatch onto the AppKit main thread
        // that drains the event queue, updates the windows and touches the
        // Metal drawable. That is host time the interpreter is not running
        // in, and a run that spends most of its wall clock here looks
        // identical to a slow interpreter from every other counter.
        const started = monotonicNanoseconds();
        const events = callback(self.hooks.context);
        const finished = monotonicNanoseconds();
        if (started != 0 and finished > started) self.event_pump_nanos +|= finished - started;
        return events;
    }

    pub fn noteProcAddressQuery(self: *WindowsGraphicsState, name: []const u8) void {
        self.proc_queries +|= 1;
        self.noteCall(name);
    }

    pub fn noteObservedCall(self: *WindowsGraphicsState, name: []const u8) void {
        self.noteCall(name);
    }

    /// Record that a Vulkan entry crossed the Rosetta-owned native adapter.
    /// `host_objects_ready` is deliberately separate from dispatch count:
    /// reaching a bridge callback proves the adapter was selected, while a
    /// real instance/device proves the host driver accepted the ownership
    /// boundary.
    pub fn noteNativeVulkanForwarded(self: *WindowsGraphicsState, name: []const u8, host_objects_ready: bool) void {
        self.native_vulkan_calls +|= 1;
        self.noteCall(name);
        if (host_objects_ready) {
            self.native_vulkan_forwarding = true;
        } else {
            self.native_vulkan_pre_ready_calls +|= 1;
        }
    }

    /// Record an actual result-bearing Vulkan failure.  A callback crossing
    /// before native objects exist is expected during loader/instance bring-up
    /// and is tracked separately by `noteNativeVulkanForwarded`.
    pub fn noteNativeVulkanResult(self: *WindowsGraphicsState, name: []const u8, ok: bool) void {
        if (ok) return;
        self.native_vulkan_failures +|= 1;
        copyLabel(&self.last_failure, name);
    }

    pub fn noteUnmodeledCall(self: *WindowsGraphicsState, name: []const u8) void {
        self.unmodeled_calls +|= 1;
        self.noteCall(name);
    }

    pub fn noteCreateInstance(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkCreateInstance");
        self.instance_creations +|= 1;
        if (!ok) return false;
        self.instance_ready = true;
        self.advance(.instance_ready);
        return true;
    }

    pub fn noteCreateSurface(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkCreateWin32SurfaceKHR");
        self.surface_creations +|= 1;
        if (!self.instance_ready) {
            self.violation("vkCreateWin32SurfaceKHR", "Vulkan instance is not ready");
            return false;
        }
        if (!self.window_ready) {
            self.violation("vkCreateWin32SurfaceKHR", "Win32 window is not ready");
            return false;
        }
        if (!ok) return false;
        self.surface_ready = true;
        self.advance(.surface_ready);
        // A native guest Vulkan forwarder already owns the guest instance,
        // surface, device, and queue on this route. Starting the diagnostic
        // presenter as well would create a second Vulkan object graph against
        // the same CAMetalLayer and could make a healthy guest submission look
        // like a presenter failure. Keep the diagnostic presenter as the
        // explicit fallback for the modelled/synthetic route only.
        if (!self.native_vulkan_forwarding) self.startNativePresenter();
        return true;
    }

    /// Start the host presenter only after the guest has established the
    /// logical Win32 surface.  Failure is deliberately degraded rather than
    /// turned into a logical Vulkan success: the snapshot carries both facts
    /// so callers can distinguish "guest asked for a surface" from "native
    /// Vulkan can actually present".
    fn startNativePresenter(self: *WindowsGraphicsState) void {
        if (self.native_presenter_started) return;
        const callback = self.hooks.native_presenter_start orelse return;
        self.native_presenter_started = true;
        self.native_presenter_attempts +|= 1;
        const ok = callback(
            self.hooks.native_context,
            self.window_width,
            self.window_height,
        ) != 0;
        self.native_presenter_ready = ok;
        if (!ok) self.native_presenter_failures +|= 1;
        self.updateNativePresenterStage();
    }

    fn updateNativePresenterStage(self: *WindowsGraphicsState) void {
        if (self.hooks.native_presenter_stage) |callback| {
            self.native_presenter_stage = callback(self.hooks.native_context);
        }
        if (self.hooks.native_presenter_is_ready) |callback| {
            self.native_presenter_ready = callback(self.hooks.native_context) != 0;
        }
    }

    pub fn noteCreateDevice(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkCreateDevice");
        self.device_creations +|= 1;
        if (!self.instance_ready) {
            self.violation("vkCreateDevice", "Vulkan instance is not ready");
            return false;
        }
        if (!ok) return false;
        self.device_ready = true;
        self.advance(.device_ready);
        return true;
    }

    pub fn noteGetQueue(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkGetDeviceQueue");
        self.queue_acquisitions +|= 1;
        if (!self.device_ready) {
            self.violation("vkGetDeviceQueue", "logical device is not ready");
            return false;
        }
        if (!ok) return false;
        self.queue_ready = true;
        self.advance(.queue_ready);
        return true;
    }

    pub fn noteCreateSwapchain(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkCreateSwapchainKHR");
        self.swapchain_creations +|= 1;
        if (!self.device_ready or !self.surface_ready) {
            self.violation("vkCreateSwapchainKHR", "device and surface are both required");
            return false;
        }
        if (!ok) return false;
        self.swapchain_ready = true;
        self.advance(.swapchain_ready);
        return true;
    }

    pub fn noteSwapchainImages(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkGetSwapchainImagesKHR");
        self.swapchain_image_queries +|= 1;
        if (!self.swapchain_ready) {
            self.violation("vkGetSwapchainImagesKHR", "swapchain is not ready");
            return false;
        }
        if (!ok) return false;
        self.frame_resources_ready = true;
        self.advance(.frame_resources_ready);
        return true;
    }

    pub fn noteAcquire(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkAcquireNextImageKHR");
        self.image_acquires +|= 1;
        if (!self.swapchain_ready) {
            self.violation("vkAcquireNextImageKHR", "swapchain is not ready");
            return false;
        }
        return ok;
    }

    pub fn noteCommand(self: *WindowsGraphicsState, name: []const u8) void {
        self.command_calls +|= 1;
        if (std.mem.startsWith(u8, name, "vkCmdDraw")) {
            self.draw_commands +|= 1;
        } else if (std.mem.startsWith(u8, name, "vkCmdDispatch")) {
            self.dispatch_commands +|= 1;
        } else if (std.mem.startsWith(u8, name, "vkCmdCopy") or
            std.mem.startsWith(u8, name, "vkCmdBlit") or
            std.mem.startsWith(u8, name, "vkCmdResolve"))
        {
            self.transfer_commands +|= 1;
        }
        // A command count alone cannot separate a frame with a picture in it
        // from a frame that was cleared and presented. The contract package
        // draws that line once, and both this state and the Vulkan forwarder
        // read it from there.
        switch (frame_content_contract.classify(name)) {
            .content => self.content_commands +|= 1,
            .uniform_fill => self.fill_commands +|= 1,
            .none => {},
        }
        self.noteCall(name);
    }

    /// Copy the forwarder's guest-owned frame attribution into the PE-side
    /// ledger. The Windows adapter sees Vulkan entry points, but only the
    /// native forwarder knows whether a command actually touched the acquired
    /// guest swapchain image and whether MoltenVK completed the present.
    pub fn noteForwarderFrameEvidence(
        self: *WindowsGraphicsState,
        guest_presents_with_target: u64,
        guest_presents_with_content: u64,
        guest_presents_clear_only: u64,
        guest_presents_without_target: u64,
        guest_presents_without_write: u64,
        native_present_requests: u64,
        native_present_completions: u64,
        native_queue_submits: u64,
    ) void {
        self.guest_presents_with_target = @max(self.guest_presents_with_target, guest_presents_with_target);
        self.guest_presents_with_content = @max(self.guest_presents_with_content, guest_presents_with_content);
        self.guest_presents_clear_only = @max(self.guest_presents_clear_only, guest_presents_clear_only);
        self.guest_presents_without_target = @max(self.guest_presents_without_target, guest_presents_without_target);
        self.guest_presents_without_write = @max(self.guest_presents_without_write, guest_presents_without_write);
        self.native_present_requests_observed = @max(self.native_present_requests_observed, native_present_requests);
        self.native_present_completions_observed = @max(self.native_present_completions_observed, native_present_completions);
        self.native_queue_submits_observed = @max(self.native_queue_submits_observed, native_queue_submits);
    }

    pub fn noteQueueSubmit(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkQueueSubmit");
        self.queue_submits +|= 1;
        if (!self.queue_ready) {
            self.violation("vkQueueSubmit", "graphics queue is not ready");
            return false;
        }
        return ok;
    }

    pub fn notePresent(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkQueuePresentKHR");
        self.presents +|= 1;
        if (!self.queue_ready or !self.swapchain_ready or !self.frame_resources_ready) {
            self.violation("vkQueuePresentKHR", "queue, swapchain, and frame resources are required");
            return false;
        }
        if (!ok) return false;
        self.guest_present_observed = true;
        self.advance(.present_ready);
        // A real guest queue-present is already the evidence we want. The
        // host-generated clear is reserved for the synthetic fallback and is
        // never emitted alongside native guest forwarding.
        if (!self.native_vulkan_forwarding) self.noteNativeDiagnostic();
        return true;
    }

    /// Ask the native presenter for one host-generated liveness frame after a
    /// logical guest present.  This is not guest output and never toggles the
    /// native forwarding bit; it proves only that the host Vulkan/Metal
    /// presentation chain is alive at the time the guest reached present.
    fn noteNativeDiagnostic(self: *WindowsGraphicsState) void {
        if (!self.native_presenter_ready) return;
        const callback = self.hooks.native_presenter_present_diagnostic orelse return;
        self.native_diagnostic_attempts +|= 1;
        const before = self.native_diagnostic_frames;
        const reported = callback(
            self.hooks.native_context,
            self.presents,
            self.window_width,
            self.window_height,
            @intFromEnum(self.phase),
        );
        if (reported > before) {
            self.native_diagnostic_frames = reported;
        } else {
            self.native_diagnostic_failures +|= 1;
        }
        self.updateNativePresenterStage();
    }

    pub fn snapshot(self: *const WindowsGraphicsState) WindowsGraphicsSnapshot {
        return .{
            .phase = self.phase,
            .application_ready = self.application_ready,
            .window_ready = self.window_ready,
            .native_window_ready = self.native_window_ready,
            .native_window_visible = self.native_window_visible,
            .instance_ready = self.instance_ready,
            .surface_ready = self.surface_ready,
            .device_ready = self.device_ready,
            .queue_ready = self.queue_ready,
            .swapchain_ready = self.swapchain_ready,
            .frame_resources_ready = self.frame_resources_ready,
            .guest_present_observed = self.guest_present_observed,
            .native_vulkan_forwarding = self.native_vulkan_forwarding,
            .native_vulkan_calls = self.native_vulkan_calls,
            .native_vulkan_pre_ready_calls = self.native_vulkan_pre_ready_calls,
            .native_vulkan_failures = self.native_vulkan_failures,
            .native_presenter_started = self.native_presenter_started,
            .native_presenter_ready = self.native_presenter_ready,
            .native_presenter_stage = self.native_presenter_stage,
            .native_presenter_attempts = self.native_presenter_attempts,
            .native_presenter_failures = self.native_presenter_failures,
            .native_diagnostic_attempts = self.native_diagnostic_attempts,
            .native_diagnostic_frames = self.native_diagnostic_frames,
            .native_diagnostic_failures = self.native_diagnostic_failures,
            .window_create_attempts = self.window_create_attempts,
            .window_create_failures = self.window_create_failures,
            .application_attempts = self.application_attempts,
            .show_attempts = self.show_attempts,
            .event_pump_calls = self.event_pump_calls,
            .event_pump_nanos = self.event_pump_nanos,
            .event_pump_skips = self.event_pump_skips,
            .vulkan_calls = self.vulkan_calls,
            .proc_queries = self.proc_queries,
            .instance_creations = self.instance_creations,
            .surface_creations = self.surface_creations,
            .device_creations = self.device_creations,
            .queue_acquisitions = self.queue_acquisitions,
            .swapchain_creations = self.swapchain_creations,
            .swapchain_image_queries = self.swapchain_image_queries,
            .image_acquires = self.image_acquires,
            .command_calls = self.command_calls,
            .draw_commands = self.draw_commands,
            .dispatch_commands = self.dispatch_commands,
            .transfer_commands = self.transfer_commands,
            .content_commands = self.content_commands,
            .fill_commands = self.fill_commands,
            .queue_submits = self.queue_submits,
            .presents = self.presents,
            .guest_presents_with_target = self.guest_presents_with_target,
            .guest_presents_with_content = self.guest_presents_with_content,
            .guest_presents_clear_only = self.guest_presents_clear_only,
            .guest_presents_without_target = self.guest_presents_without_target,
            .guest_presents_without_write = self.guest_presents_without_write,
            .native_present_requests_observed = self.native_present_requests_observed,
            .native_present_completions_observed = self.native_present_completions_observed,
            .native_queue_submits_observed = self.native_queue_submits_observed,
            .ordering_violations = self.ordering_violations,
            .unmodeled_calls = self.unmodeled_calls,
            .window_width = self.window_width,
            .window_height = self.window_height,
            .last_call = self.last_call,
            .last_failure = self.last_failure,
        };
    }
};

const NativeGraphicsTestHarness = struct {
    starts: u64 = 0,
    stage: u32 = 10,
    frames: u64 = 0,
    event_pumps: u64 = 0,
    frame_counter_updates: u64 = 0,
    last_frame: u64 = 0,
    last_fps_milli: u64 = 0,
    present_chain_reports: u64 = 0,
    present_chain_full_reports: u64 = 0,
    application_ensures: u64 = 0,
    window_ensures: u64 = 0,
};

fn testPumpEvents(context: ?*anyopaque) callconv(.c) u32 {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.event_pumps +|= 1;
    return 0;
}

fn testSetFrameCounter(context: ?*anyopaque, frame: u64, fps_milli: u64) callconv(.c) void {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.frame_counter_updates +|= 1;
    harness.last_frame = frame;
    harness.last_fps_milli = fps_milli;
}

fn testNativeWindowEnsureApplication(context: ?*anyopaque) callconv(.c) c_int {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.application_ensures +|= 1;
    return 1;
}

fn testNativeWindowEnsure(context: ?*anyopaque, _: u32, _: u32, _: [*:0]const u8) callconv(.c) c_int {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.window_ensures +|= 1;
    return 1;
}

fn testPresentChainReport(context: ?*anyopaque) callconv(.c) void {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.present_chain_reports +|= 1;
}

fn testPresentChainFullReport(context: ?*anyopaque) callconv(.c) void {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.present_chain_full_reports +|= 1;
}

fn testNativePresenterStart(context: ?*anyopaque, _: u32, _: u32) callconv(.c) c_int {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.starts +|= 1;
    return 1;
}

fn testNativePresenterStage(context: ?*anyopaque) callconv(.c) u32 {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    return harness.stage;
}

fn testNativePresenterReady(_: ?*anyopaque) callconv(.c) c_int {
    return 1;
}

fn testNativePresenterDiagnostic(context: ?*anyopaque, _: u64, _: u32, _: u32, _: u32) callconv(.c) u64 {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.frames +|= 1;
    return harness.frames;
}

test "Windows graphics ledger proves the complete logical frame path" {
    var graphics = WindowsGraphicsState{};
    try testing.expect(graphics.ensureWindow(1920, 1080, "Xenia Canary"));
    try testing.expect(graphics.showWindow());
    try testing.expect(graphics.noteCreateInstance(true));
    try testing.expect(graphics.noteCreateSurface(true));
    try testing.expect(graphics.noteCreateDevice(true));
    try testing.expect(graphics.noteGetQueue(true));
    try testing.expect(graphics.noteCreateSwapchain(true));
    try testing.expect(graphics.noteSwapchainImages(true));
    try testing.expect(graphics.noteAcquire(true));
    graphics.noteCommand("vkCmdClearColorImage");
    try testing.expect(graphics.noteQueueSubmit(true));
    try testing.expect(graphics.notePresent(true));

    const snapshot = graphics.snapshot();
    try testing.expect(snapshot.contractReady());
    try testing.expect(snapshot.guest_present_observed);
    try testing.expect(!snapshot.nativeWindowReady());
    try testing.expectEqual(WindowsGraphicsPhase.present_ready, snapshot.phase);
    try testing.expectEqual(@as(u64, 0), snapshot.ordering_violations);
}

test "Windows graphics ledger rejects a present before its prerequisites" {
    var graphics = WindowsGraphicsState{};
    try testing.expect(!graphics.notePresent(true));
    const snapshot = graphics.snapshot();
    try testing.expectEqual(WindowsGraphicsPhase.failed, snapshot.phase);
    try testing.expectEqual(@as(u64, 1), snapshot.ordering_violations);
    try testing.expect(!snapshot.contractReady());
    try testing.expectEqualStrings("vkQueuePresentKHR: queue, swapchain, and frame resources are required", std.mem.sliceTo(&snapshot.last_failure, 0));
}

test "Windows graphics ledger never forwards Win32 default dimensions to the host" {
    var graphics = WindowsGraphicsState{};
    try testing.expect(graphics.ensureWindow(WINDOWS_CW_USEDEFAULT, WINDOWS_CW_USEDEFAULT, "message-safe fallback"));
    try testing.expectEqual(WINDOWS_DEFAULT_WIDTH, graphics.window_width);
    try testing.expectEqual(WINDOWS_DEFAULT_HEIGHT, graphics.window_height);

    try testing.expect(graphics.ensureWindow(WINDOWS_MAX_DIMENSION + 1, 0, "bounded fallback"));
    try testing.expectEqual(WINDOWS_DEFAULT_WIDTH, graphics.window_width);
    try testing.expectEqual(WINDOWS_DEFAULT_HEIGHT, graphics.window_height);
}

test "re-ensuring a ready native window does not remarshal AppKit" {
    var harness = NativeGraphicsTestHarness{};
    var graphics = WindowsGraphicsState{
        .hooks = .{
            .context = &harness,
            .ensure_application = testNativeWindowEnsureApplication,
            .ensure_window = testNativeWindowEnsure,
        },
    };

    try testing.expect(graphics.ensureWindow(1280, 720, "Xenia Canary (Rosette)"));
    try testing.expect(graphics.ensureWindow(1280, 720, "Xenia Canary (Rosette)"));
    try testing.expectEqual(@as(u64, 2), graphics.window_create_attempts);
    try testing.expectEqual(@as(u64, 1), harness.application_ensures);
    try testing.expectEqual(@as(u64, 1), harness.window_ensures);
    try testing.expectEqual(@as(u64, 0), graphics.window_create_failures);
}

test "Windows graphics ledger keeps native diagnostics separate from guest output" {
    var harness = NativeGraphicsTestHarness{};
    var graphics = WindowsGraphicsState{
        .hooks = .{
            .native_context = &harness,
            .native_presenter_start = testNativePresenterStart,
            .native_presenter_stage = testNativePresenterStage,
            .native_presenter_is_ready = testNativePresenterReady,
            .native_presenter_present_diagnostic = testNativePresenterDiagnostic,
        },
    };
    try testing.expect(graphics.ensureWindow(1280, 720, "native diagnostic"));
    try testing.expect(graphics.noteCreateInstance(true));
    try testing.expect(graphics.noteCreateSurface(true));
    try testing.expectEqual(@as(u64, 1), harness.starts);
    try testing.expect(graphics.noteCreateDevice(true));
    try testing.expect(graphics.noteGetQueue(true));
    try testing.expect(graphics.noteCreateSwapchain(true));
    try testing.expect(graphics.noteSwapchainImages(true));
    try testing.expect(graphics.noteAcquire(true));
    try testing.expect(graphics.noteQueueSubmit(true));
    try testing.expect(graphics.notePresent(true));
    try testing.expect(graphics.notePresent(true));

    const snapshot = graphics.snapshot();
    try testing.expect(snapshot.contractReady());
    try testing.expect(snapshot.nativePresenterReady());
    try testing.expectEqual(@as(u64, 2), harness.frames);
    try testing.expectEqual(@as(u64, 2), snapshot.native_diagnostic_attempts);
    try testing.expectEqual(@as(u64, 2), snapshot.native_diagnostic_frames);
    try testing.expectEqual(@as(u64, 0), snapshot.native_diagnostic_failures);
    try testing.expect(!snapshot.native_vulkan_forwarding);
}

test "host event pump obeys guest-step and host-time deadlines" {
    var harness = NativeGraphicsTestHarness{};
    var graphics = WindowsGraphicsState{
        .hooks = .{ .context = &harness, .pump_events = testPumpEvents },
    };

    _ = graphics.pumpEventsAtStepAtTime(0, false, 0);
    try testing.expectEqual(@as(u64, 1), harness.event_pumps);

    _ = graphics.pumpEventsAtStepAtTime(1, false, 1);
    try testing.expectEqual(@as(u64, 1), harness.event_pumps);
    try testing.expectEqual(@as(u64, 1), graphics.event_pump_skips);

    _ = graphics.pumpEventsAtStepAtTime(1, false, WINDOWS_EVENT_PUMP_INTERVAL_NS);
    try testing.expectEqual(@as(u64, 2), harness.event_pumps);

    // At extremely high guest throughput the instruction ceiling is an
    // additional guard, and explicit pending-paint requests still bypass it.
    _ = graphics.pumpEventsAtStepAtTime(WINDOWS_EVENT_PUMP_STRIDE + 1, false, WINDOWS_EVENT_PUMP_INTERVAL_NS + 1);
    _ = graphics.pumpEventsAtStepAtTime(WINDOWS_EVENT_PUMP_STRIDE + 2, true, WINDOWS_EVENT_PUMP_INTERVAL_NS + 2);
    try testing.expectEqual(@as(u64, 4), harness.event_pumps);
}

test "completed SDL guest frames publish sampled FPS to the native HUD" {
    var harness = NativeGraphicsTestHarness{};
    var graphics = WindowsGraphicsState{
        .hooks = .{ .native_context = &harness, .set_frame_counter = testSetFrameCounter },
    };

    graphics.noteGuestFramePresentedAt(0);
    graphics.noteGuestFramePresentedAt(100 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u64, 0), harness.frame_counter_updates);
    graphics.noteGuestFramePresentedAt(250 * std.time.ns_per_ms);

    try testing.expectEqual(@as(u64, 3), graphics.guest_frame_count);
    try testing.expectEqual(@as(u64, 1), harness.frame_counter_updates);
    try testing.expectEqual(@as(u64, 3), harness.last_frame);
    try testing.expectEqual(@as(u64, 8_000), harness.last_fps_milli);
}

test "native guest forwarding does not start a duplicate diagnostic presenter" {
    var harness = NativeGraphicsTestHarness{};
    var graphics = WindowsGraphicsState{
        .hooks = .{
            .native_context = &harness,
            .native_presenter_start = testNativePresenterStart,
            .native_presenter_stage = testNativePresenterStage,
            .native_presenter_is_ready = testNativePresenterReady,
            .native_presenter_present_diagnostic = testNativePresenterDiagnostic,
        },
    };
    try testing.expect(graphics.ensureWindow(1280, 720, "native guest"));
    graphics.native_vulkan_forwarding = true;
    try testing.expect(graphics.noteCreateInstance(true));
    try testing.expect(graphics.noteCreateSurface(true));
    try testing.expectEqual(@as(u64, 0), harness.starts);
    try testing.expect(graphics.noteCreateDevice(true));
    try testing.expect(graphics.noteGetQueue(true));
    try testing.expect(graphics.noteCreateSwapchain(true));
    try testing.expect(graphics.noteSwapchainImages(true));
    try testing.expect(graphics.noteAcquire(true));
    try testing.expect(graphics.noteQueueSubmit(true));
    try testing.expect(graphics.notePresent(true));
    try testing.expectEqual(@as(u64, 0), harness.frames);
}
