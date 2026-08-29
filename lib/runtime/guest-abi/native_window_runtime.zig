const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;
const admission = @import("cocoa_window_admission_contract");

pub const Facility = admission.Facility;
pub const Operation = admission.Operation;
pub const Actor = admission.Actor;

/// The window capability an incoming message names, and what it wants to do
/// with it.
///
/// Every path through `handleObjcMessage` produces one, including the paths
/// that do not know what the message means: an unknown selector addressed at an
/// identity Rosette owns is `unrecognized`, not "not ours". Rosette owns that
/// identity, so nobody else gets to answer for it, and the admission policy —
/// not a fallthrough — decides what happens next.
pub const Binding = struct {
    facility: Facility,
    operation: Operation,
};

pub const APPLICATION_TOKEN: u64 = 0xFFFF_F400_0000_0011;
pub const WINDOW_TOKEN: u64 = 0xFFFF_F400_0000_0021;
pub const VIEW_TOKEN: u64 = 0xFFFF_F400_0000_0031;
pub const METAL_LAYER_TOKEN: u64 = 0xFFFF_F400_0000_0041;

/// The Vulkan format equivalent of the `CAMetalLayer` Rosette creates, which
/// `native_window_bridge.m` fixes at `MTLPixelFormatBGRA8Unorm`.
///
/// Stated rather than assumed: frame custody has to describe every frame it
/// holds with a real format, including the host clears that never touch a
/// Vulkan swapchain, and a consumer guessing at this would be describing a
/// drawable nobody looked at.
pub const DRAWABLE_VULKAN_FORMAT: u32 = 44;

pub const Status = extern struct {
    application: usize,
    window: usize,
    view: usize,
    metal_layer: usize,
    metal_device: usize,
    width: u32,
    height: u32,
    events_pumped: u32,
    application_ready: u8,
    window_ready: u8,
    layer_attached: u8,
    visible: u8,
    on_main_thread: u8,
    reserved: [3]u8,
};

const NativeStatus = Status;

extern fn rosette_macho_native_application_ensure() c_int;
extern fn rosette_macho_native_window_ensure(width: u32, height: u32, title: [*:0]const u8) c_int;
extern fn rosette_macho_native_window_set_title(title: [*:0]const u8) c_int;
extern fn rosette_macho_native_window_set_size(width: u32, height: u32) c_int;
extern fn rosette_macho_native_window_show() c_int;
extern fn rosette_macho_native_window_hide() c_int;
extern fn rosette_macho_native_window_set_fullscreen(fullscreen: c_int) c_int;
extern fn rosette_macho_native_window_attach_metal_layer() c_int;
extern fn rosette_macho_native_window_present_diagnostic_frame(
    serial: u64,
    width: u32,
    height: u32,
    stage: u32,
) u64;
extern fn rosette_macho_native_window_present_frame(
    serial: u64,
    pixels: [*]const u8,
    source_length: u64,
    source_width: u32,
    source_height: u32,
    row_pitch: u64,
    format: u32,
    orientation: u8,
    fit: u8,
) u64;
extern fn rosette_macho_native_window_pump_events() u32;
extern fn rosette_macho_native_window_status() NativeStatus;
extern fn rosette_macho_native_window_shutdown() void;

pub const ObjcResult = struct {
    value: u64,
    action: []const u8,
    binding: Binding,
};

/// What an Objective-C message means to Rosette's window.
pub const ObjcOutcome = union(enum) {
    /// Not addressed to anything Rosette owns. Somebody else's message.
    foreign,
    /// A forwarding Rosette has semantics for, already performed.
    handled: ObjcResult,
    /// Addressed to a Rosette-owned identity, and Rosette has no semantics for
    /// it. Returned rather than answered: this is the case where a plausible
    /// reply puts something on the window nobody can account for.
    unrecognized: Binding,
};

pub const Runtime = struct {
    application_ensure_attempts: u64 = 0,
    window_ensure_attempts: u64 = 0,
    window_ensure_failures: u64 = 0,
    view_requests: u64 = 0,
    layer_requests: u64 = 0,
    layer_attachments: u64 = 0,
    layer_attachment_failures: u64 = 0,
    surface_bindings: u64 = 0,
    diagnostic_frame_attempts: u64 = 0,
    diagnostic_frames_presented: u64 = 0,
    diagnostic_frame_failures: u64 = 0,
    guest_frame_attempts: u64 = 0,
    guest_frames_presented: u64 = 0,
    guest_frame_failures: u64 = 0,
    event_pump_calls: u64 = 0,
    objc_messages: u64 = 0,
    window_ready_logged: bool = false,
    requested_width: u32 = 1280,
    requested_height: u32 = 720,
    title: [512:0]u8 = [_:0]u8{0} ** 512,

    pub fn snapshot(self: *const Runtime) Status {
        _ = self;
        return rosette_macho_native_window_status();
    }

    pub fn deinit(self: *Runtime) void {
        if (self.application_ensure_attempts != 0 or self.window_ensure_attempts != 0) {
            rosette_macho_native_window_shutdown();
        }
    }

    pub fn ensureApplication(self: *Runtime) bool {
        self.application_ensure_attempts +|= 1;
        const ok = rosette_macho_native_application_ensure() != 0;
        if (!ok) {
            machoCapturePrint(
                "macho-processor: native AppKit application creation failed: attempt={d}\n",
                .{self.application_ensure_attempts},
            );
        }
        return ok;
    }

    pub fn ensureWindow(self: *Runtime) bool {
        self.window_ensure_attempts +|= 1;
        const title = if (self.title[0] == 0) "Xenia Canary (Rosette)" else std.mem.sliceTo(&self.title, 0);
        var title_buffer: [512:0]u8 = [_:0]u8{0} ** 512;
        const copied = @min(title.len, title_buffer.len - 1);
        @memcpy(title_buffer[0..copied], title[0..copied]);
        const ok = rosette_macho_native_window_ensure(
            @max(self.requested_width, 1),
            @max(self.requested_height, 1),
            &title_buffer,
        ) != 0;
        if (!ok) {
            self.window_ensure_failures +|= 1;
            machoCapturePrint(
                "macho-processor: native AppKit window creation failed: attempt={d} failures={d} requested={d}x{d}\n",
                .{ self.window_ensure_attempts, self.window_ensure_failures, self.requested_width, self.requested_height },
            );
            return false;
        }
        const status = rosette_macho_native_window_status();
        if (!self.window_ready_logged) {
            self.window_ready_logged = true;
            machoCapturePrint(
                "macho-processor: native AppKit window ready: NSApplication=0x{x} NSWindow=0x{x} NSView=0x{x} CAMetalLayer=0x{x} MTLDevice=0x{x} drawable={d}x{d} main_thread={} attached={}\n",
                .{ status.application, status.window, status.view, status.metal_layer, status.metal_device, status.width, status.height, status.on_main_thread != 0, status.layer_attached != 0 },
            );
        }
        return status.application_ready != 0 and status.window_ready != 0 and
            status.view != 0 and status.metal_layer != 0 and status.metal_device != 0;
    }

    pub fn setTitle(self: *Runtime, value: []const u8) bool {
        @memset(&self.title, 0);
        const copied = @min(value.len, self.title.len - 1);
        @memcpy(self.title[0..copied], value[0..copied]);
        if (!self.ensureWindow()) return false;
        return rosette_macho_native_window_set_title(&self.title) != 0;
    }

    pub fn setSize(self: *Runtime, new_width: i64, new_height: i64) bool {
        if (new_width <= 0 or new_height <= 0) return false;
        self.requested_width = @intCast(@min(new_width, std.math.maxInt(u32)));
        self.requested_height = @intCast(@min(new_height, std.math.maxInt(u32)));
        if (!self.ensureWindow()) return false;
        return rosette_macho_native_window_set_size(self.requested_width, self.requested_height) != 0;
    }

    pub fn show(self: *Runtime) bool {
        if (!self.ensureWindow()) return false;
        const shown = rosette_macho_native_window_show() != 0;
        _ = self.pumpEvents();
        return shown;
    }

    pub fn hide(self: *Runtime) bool {
        if (!self.ensureWindow()) return false;
        const hidden = rosette_macho_native_window_hide() != 0;
        _ = self.pumpEvents();
        return hidden;
    }

    pub fn setFullscreen(self: *Runtime, fullscreen: bool) bool {
        if (!self.ensureWindow()) return false;
        return rosette_macho_native_window_set_fullscreen(@intFromBool(fullscreen)) != 0;
    }

    pub fn pumpEvents(self: *Runtime) u32 {
        if (!self.ensureApplication()) return 0;
        self.event_pump_calls +|= 1;
        return rosette_macho_native_window_pump_events();
    }

    pub fn viewToken(self: *Runtime) u64 {
        self.view_requests +|= 1;
        if (!self.ensureWindow()) return 0;
        if (self.view_requests == 1) {
            const status = rosette_macho_native_window_status();
            machoCapturePrint(
                "macho-processor: Quartz NSView exported to guest: token=0x{x} host_NSView=0x{x} NSWindow=0x{x} drawable={d}x{d}\n",
                .{ VIEW_TOKEN, status.view, status.window, status.width, status.height },
            );
        }
        return VIEW_TOKEN;
    }

    pub fn layerToken(self: *Runtime) u64 {
        self.layer_requests +|= 1;
        if (!self.ensureWindow()) return 0;
        if (self.layer_requests == 1) {
            const status = rosette_macho_native_window_status();
            machoCapturePrint(
                "macho-processor: CAMetalLayer exported to guest: token=0x{x} host_CAMetalLayer=0x{x} MTLDevice=0x{x} attached={}\n",
                .{ METAL_LAYER_TOKEN, status.metal_layer, status.metal_device, status.layer_attached != 0 },
            );
        }
        return METAL_LAYER_TOKEN;
    }

    pub fn attachLayer(self: *Runtime, token: u64) bool {
        if (token != METAL_LAYER_TOKEN or !self.ensureWindow()) {
            self.layer_attachment_failures +|= 1;
            return false;
        }
        const attached = rosette_macho_native_window_attach_metal_layer() != 0;
        if (attached) {
            self.layer_attachments +|= 1;
            const status = rosette_macho_native_window_status();
            machoCapturePrint(
                "macho-processor: native Metal layer attached: token=0x{x} NSView=0x{x} CAMetalLayer=0x{x} MTLDevice=0x{x} drawable={d}x{d}\n",
                .{ token, status.view, status.metal_layer, status.metal_device, status.width, status.height },
            );
        } else {
            self.layer_attachment_failures +|= 1;
        }
        return attached;
    }

    pub fn validateLayerToken(self: *Runtime, token: u64) bool {
        if (token != METAL_LAYER_TOKEN or !self.ensureWindow()) return false;
        const status = rosette_macho_native_window_status();
        return status.window_ready != 0 and status.layer_attached != 0 and
            status.view != 0 and status.metal_layer != 0 and status.metal_device != 0;
    }

    pub fn hostMetalLayer(self: *Runtime) usize {
        if (!self.validateLayerToken(METAL_LAYER_TOKEN)) return 0;
        return rosette_macho_native_window_status().metal_layer;
    }

    pub fn noteSurfaceBound(self: *Runtime, layer_token: u64, guest_surface: u64, host_surface: u64) void {
        self.surface_bindings +|= 1;
        const status = rosette_macho_native_window_status();
        machoCapturePrint(
            "macho-processor: native presenter surface bound: binding={d} layer_token=0x{x} CAMetalLayer=0x{x} host_VkSurfaceKHR=0x{x} guest_VkSurfaceKHR=0x{x} drawable={d}x{d}\n",
            .{ self.surface_bindings, layer_token, status.metal_layer, host_surface, guest_surface, status.width, status.height },
        );
    }

    /// A host Metal clear on the window's drawable. This is a liveness probe:
    /// it distinguishes a blank window from a dead Cocoa/Metal boundary, and it
    /// is the fallback for when Rosette's native Vulkan presenter could not be
    /// brought up. It involves no guest image, no Vulkan command buffer, no
    /// swapchain image and no guest swap, so its output is never guest output —
    /// the log line says so on every frame it reports rather than leaving the
    /// reader to infer it.
    pub fn presentDiagnosticFrame(
        self: *Runtime,
        serial: u64,
        drawable_width: u32,
        drawable_height: u32,
        stage: u32,
    ) bool {
        self.diagnostic_frame_attempts +|= 1;
        const frame = rosette_macho_native_window_present_diagnostic_frame(
            serial,
            drawable_width,
            drawable_height,
            stage,
        );
        if (frame == 0) {
            self.diagnostic_frame_failures +|= 1;
            machoCapturePrint(
                "macho-processor: diagnostic Metal frame failed: attempt={d} serial=0x{x} stage={d} drawable={d}x{d}\n",
                .{ self.diagnostic_frame_attempts, serial, stage, drawable_width, drawable_height },
            );
            return false;
        }
        self.diagnostic_frames_presented = frame;
        if (frame <= 8 or frame % 64 == 0) {
            machoCapturePrint(
                "macho-processor: diagnostic Metal frame presented: frame={d} serial=0x{x} stage={d} drawable={d}x{d} provenance=DIAGNOSTIC_ONLY source=host_clear native_swapchain=NO native_queue_submit=NO guest_output=NO\n",
                .{ frame, serial, stage, drawable_width, drawable_height },
            );
        }
        return true;
    }

    /// Present a complete, readable emulator frame directly through Metal.
    /// The caller must arrive through a semantic frame handoff; this routine
    /// accepts pixels and descriptor facts, never an x86 opcode or an opaque
    /// callback address. It is intentionally synchronous so a successful
    /// return proves command-buffer completion rather than queue admission.
    pub fn presentVerifiedFrame(
        self: *Runtime,
        serial: u64,
        pixels: []const u8,
        source_width: u32,
        source_height: u32,
        row_pitch: u64,
        format: u32,
        orientation: u8,
        fit: u8,
        guest_swap_observed: bool,
    ) bool {
        self.guest_frame_attempts +|= 1;
        const supported = format == 37 or format == 43 or format == 44 or format == 50;
        const tight_pitch = std.math.mul(u64, source_width, 4) catch 0;
        const effective_pitch = if (row_pitch == 0) tight_pitch else row_pitch;
        const required = std.math.mul(u64, effective_pitch, source_height) catch 0;
        if (serial == 0 or pixels.len == 0 or source_width == 0 or source_height == 0 or
            source_width > 8192 or source_height > 8192 or !supported or
            tight_pitch == 0 or effective_pitch < tight_pitch or required == 0 or
            required > @as(u64, @intCast(pixels.len)) or orientation > 1 or fit > 2)
        {
            self.guest_frame_failures +|= 1;
            return false;
        }
        const frame = rosette_macho_native_window_present_frame(
            serial,
            pixels.ptr,
            @as(u64, @intCast(pixels.len)),
            source_width,
            source_height,
            effective_pitch,
            format,
            orientation,
            fit,
        );
        if (frame == 0) {
            self.guest_frame_failures +|= 1;
            machoCapturePrint(
                "macho-processor: verified Cocoa/Metal guest frame failed: attempt={d} serial={d} source={d}x{d} pitch={d} format={d}\n",
                .{ self.guest_frame_attempts, serial, source_width, source_height, effective_pitch, format },
            );
            return false;
        }
        self.guest_frames_presented = frame;
        if (frame <= 8 or frame % 120 == 0) {
            machoCapturePrint(
                "macho-processor: verified Cocoa/Metal guest frame presented: frame={d} serial={d} source={d}x{d} pitch={d} format={d} orientation={d} fit={d} class={s} provenance=VERIFIED_FRAME_HANDOFF Vulkan_submit=NO raw_x86_dispatch=NO\n",
                .{
                    frame,
                    serial,
                    source_width,
                    source_height,
                    effective_pitch,
                    format,
                    orientation,
                    fit,
                    if (guest_swap_observed) "authentic-guest-present" else "guest-pixels-host-cadence",
                },
            );
        }
        return true;
    }

    pub fn width(self: *Runtime) u32 {
        const status = rosette_macho_native_window_status();
        return if (status.window_ready != 0) status.width else self.requested_width;
    }

    pub fn height(self: *Runtime) u32 {
        const status = rosette_macho_native_window_status();
        return if (status.window_ready != 0) status.height else self.requested_height;
    }

    pub fn handleObjcMessage(
        self: *Runtime,
        receiver_class: []const u8,
        receiver: u64,
        selector: []const u8,
        argument: u64,
    ) ObjcOutcome {
        if (std.mem.eql(u8, receiver_class, "NSApplication") and
            std.mem.eql(u8, selector, "sharedApplication"))
        {
            self.objc_messages +|= 1;
            return .{ .handled = .{
                .value = if (self.ensureApplication()) APPLICATION_TOKEN else 0,
                .action = "native NSApplication",
                // Acquisition, not creation. `sharedApplication` reads as a factory
                // in Objective-C and is nothing of the kind: it returns the fixed
                // token for the NSApplication Rosette stood up before the guest
                // ran. Classifying it as creation made the admission gate
                // terminate the run on the very call that hands the window over.
                .binding = .{ .facility = .application, .operation = .acquire },
            } };
        }
        if (std.mem.eql(u8, receiver_class, "CAMetalLayer") and
            std.mem.eql(u8, selector, "layer"))
        {
            self.objc_messages +|= 1;
            return .{ .handled = .{
                .value = self.layerToken(),
                .action = "native CAMetalLayer",
                // `+[CAMetalLayer layer]` reaches `layerToken`, which runs
                // `ensureWindow` and hands back a fixed token. Nothing new comes
                // into existence here either.
                .binding = .{ .facility = .layer, .operation = .acquire },
            } };
        }
        if (!isNativeToken(receiver)) return .foreign;
        self.objc_messages +|= 1;

        if (std.mem.eql(u8, selector, "retain") or std.mem.eql(u8, selector, "autorelease") or
            std.mem.eql(u8, selector, "init"))
        {
            return .{ .handled = .{
                .value = receiver,
                .action = "native identity lifetime",
                .binding = .{ .facility = .identity_lifetime, .operation = .query },
            } };
        }
        if (std.mem.eql(u8, selector, "release")) {
            return .{ .handled = .{
                .value = 0,
                .action = "native identity lifetime",
                .binding = .{ .facility = .identity_lifetime, .operation = .release },
            } };
        }
        if (receiver == APPLICATION_TOKEN) {
            if (std.mem.eql(u8, selector, "activateIgnoringOtherApps:") or
                std.mem.eql(u8, selector, "finishLaunching") or
                std.mem.eql(u8, selector, "setActivationPolicy:"))
            {
                _ = self.ensureApplication();
                return .{ .handled = .{
                    .value = if (std.mem.eql(u8, selector, "setActivationPolicy:")) 1 else 0,
                    .action = "native NSApplication state",
                    .binding = .{ .facility = .application, .operation = .mutate },
                } };
            }
        }
        if (receiver == WINDOW_TOKEN and std.mem.eql(u8, selector, "contentView")) {
            return .{ .handled = .{
                .value = self.viewToken(),
                .action = "native NSWindow contentView",
                .binding = .{ .facility = .content_view, .operation = .acquire },
            } };
        }
        if (receiver == WINDOW_TOKEN and std.mem.eql(u8, selector, "makeKeyAndOrderFront:")) {
            _ = self.show();
            return .{ .handled = .{
                .value = 0,
                .action = "native NSWindow show",
                .binding = .{ .facility = .visibility, .operation = .mutate },
            } };
        }
        if (receiver == VIEW_TOKEN and std.mem.eql(u8, selector, "window")) {
            return .{ .handled = .{
                .value = WINDOW_TOKEN,
                .action = "native NSView window",
                .binding = .{ .facility = .window, .operation = .acquire },
            } };
        }
        if (receiver == VIEW_TOKEN and std.mem.eql(u8, selector, "layer")) {
            return .{ .handled = .{
                .value = self.layerToken(),
                .action = "native NSView layer",
                .binding = .{ .facility = .layer, .operation = .acquire },
            } };
        }
        if (receiver == VIEW_TOKEN and std.mem.eql(u8, selector, "setWantsLayer:")) {
            const ok = argument != 0 and self.attachLayer(METAL_LAYER_TOKEN);
            return .{ .handled = .{
                .value = 0,
                .action = if (ok) "native NSView wantsLayer" else "native NSView wantsLayer failed",
                .binding = .{ .facility = .layer, .operation = .bind },
            } };
        }
        if (receiver == VIEW_TOKEN and std.mem.eql(u8, selector, "setLayer:")) {
            const ok = self.attachLayer(argument);
            return .{ .handled = .{
                .value = 0,
                .action = if (ok) "native NSView setLayer" else "native NSView setLayer rejected",
                .binding = .{ .facility = .layer, .operation = .bind },
            } };
        }
        if (std.mem.eql(u8, selector, "respondsToSelector:") or
            std.mem.eql(u8, selector, "isKindOfClass:") or
            std.mem.eql(u8, selector, "isEqual:"))
        {
            return .{ .handled = .{
                .value = 1,
                .action = "native identity query",
                .binding = .{ .facility = .identity_query, .operation = .query },
            } };
        }
        // Addressed to a window identity Rosette owns and meaning nothing
        // Rosette models. Refusing to answer is the point: the previous
        // fallthrough handed the message to the generic Objective-C model,
        // which answered for an object it does not own.
        return .{ .unrecognized = .{ .facility = .unrecognized, .operation = objcOperationHint(selector) } };
    }

    /// True when a message is addressed to something Rosette's window owns,
    /// whether or not it is understood. Callers use it to decide who is even
    /// allowed to answer.
    pub fn ownsObjcMessage(receiver_class: []const u8, receiver: u64, selector: []const u8) bool {
        if (isNativeToken(receiver)) return true;
        if (std.mem.eql(u8, receiver_class, "NSApplication") and std.mem.eql(u8, selector, "sharedApplication")) return true;
        if (std.mem.eql(u8, receiver_class, "CAMetalLayer") and std.mem.eql(u8, selector, "layer")) return true;
        return false;
    }

    pub fn logSummary(self: *const Runtime) void {
        if (self.application_ensure_attempts == 0 and self.window_ensure_attempts == 0) return;
        const status = rosette_macho_native_window_status();
        machoCapturePrint(
            "macho-processor: native window bridge: app_attempts={d} window_attempts={d} failures={d} objc={d} view_requests={d} layer(requests/attached/failures)={d}/{d}/{d} surface_bindings={d} diagnostic_metal_frames(attempts/presented/failures)={d}/{d}/{d} verified_guest_frames(attempts/presented/failures)={d}/{d}/{d} event_pumps={d} host(app/window/view/layer/device)=0x{x}/0x{x}/0x{x}/0x{x}/0x{x} drawable={d}x{d} ready(app/window/layer/visible/main)={}/{}/{}/{}/{} events={d}\n",
            .{ self.application_ensure_attempts, self.window_ensure_attempts, self.window_ensure_failures, self.objc_messages, self.view_requests, self.layer_requests, self.layer_attachments, self.layer_attachment_failures, self.surface_bindings, self.diagnostic_frame_attempts, self.diagnostic_frames_presented, self.diagnostic_frame_failures, self.guest_frame_attempts, self.guest_frames_presented, self.guest_frame_failures, self.event_pump_calls, status.application, status.window, status.view, status.metal_layer, status.metal_device, status.width, status.height, status.application_ready != 0, status.window_ready != 0, status.layer_attached != 0, status.visible != 0, status.on_main_thread != 0, status.events_pumped },
        );
    }
};

/// The shape of an unknown selector, so a refusal says whether the message was
/// asking a question or trying to change something. `set*`/`add*`/`remove*`
/// mutate by Cocoa convention; anything else is treated as a query, which is
/// the conservative reading.
pub fn objcOperationHint(selector: []const u8) Operation {
    if (std.mem.startsWith(u8, selector, "set") or
        std.mem.startsWith(u8, selector, "add") or
        std.mem.startsWith(u8, selector, "remove") or
        std.mem.startsWith(u8, selector, "insert") or
        std.mem.startsWith(u8, selector, "make") or
        std.mem.startsWith(u8, selector, "perform")) return .mutate;
    if (std.mem.startsWith(u8, selector, "dealloc") or
        std.mem.eql(u8, selector, "close") or
        std.mem.eql(u8, selector, "invalidate")) return .release;
    return .query;
}

pub fn isNativeToken(value: u64) bool {
    return value == APPLICATION_TOKEN or value == WINDOW_TOKEN or
        value == VIEW_TOKEN or value == METAL_LAYER_TOKEN;
}

test "native AppKit identities are opaque and disjoint" {
    try std.testing.expect(APPLICATION_TOKEN != WINDOW_TOKEN);
    try std.testing.expect(WINDOW_TOKEN != VIEW_TOKEN);
    try std.testing.expect(VIEW_TOKEN != METAL_LAYER_TOKEN);
    try std.testing.expect(isNativeToken(METAL_LAYER_TOKEN));
    try std.testing.expect(!isNativeToken(0));
}

test "an unknown selector on a Rosette identity is unrecognized rather than foreign" {
    var runtime = Runtime{};
    const outcome = runtime.handleObjcMessage("NSWindow", WINDOW_TOKEN, "setFrame:display:", 0);
    try std.testing.expectEqual(Facility.unrecognized, outcome.unrecognized.facility);
    try std.testing.expectEqual(Operation.mutate, outcome.unrecognized.operation);
    try std.testing.expect(Runtime.ownsObjcMessage("NSWindow", WINDOW_TOKEN, "setFrame:display:"));
}

test "a message to somebody else's object stays foreign" {
    var runtime = Runtime{};
    try std.testing.expectEqual(ObjcOutcome.foreign, runtime.handleObjcMessage("NSString", 0x1234, "length", 0));
    try std.testing.expect(!Runtime.ownsObjcMessage("NSString", 0x1234, "length"));
}

test "identity traffic on a window token is a lifetime binding" {
    var runtime = Runtime{};
    const retained = runtime.handleObjcMessage("NSView", VIEW_TOKEN, "retain", 0);
    try std.testing.expectEqual(Facility.identity_lifetime, retained.handled.binding.facility);
    try std.testing.expectEqual(Operation.query, retained.handled.binding.operation);
    try std.testing.expectEqual(VIEW_TOKEN, retained.handled.value);
    const released = runtime.handleObjcMessage("NSView", VIEW_TOKEN, "release", 0);
    try std.testing.expectEqual(Operation.release, released.handled.binding.operation);
}

test "selector shape is read conservatively" {
    try std.testing.expectEqual(Operation.mutate, objcOperationHint("setDelegate:"));
    try std.testing.expectEqual(Operation.mutate, objcOperationHint("makeFirstResponder:"));
    try std.testing.expectEqual(Operation.release, objcOperationHint("close"));
    try std.testing.expectEqual(Operation.query, objcOperationHint("frame"));
    try std.testing.expectEqual(Operation.query, objcOperationHint("backingScaleFactor"));
}

// Xenia's macOS startup opens with `[NSApplication sharedApplication]`, and the
// first run under the admission gate terminated on it: the message was
// classified as creating an NSApplication, creating an AppKit singleton was an
// ownership violation, and an ownership violation is fatal. Every message that
// hands back a token Rosette already owns is an acquisition.
test "handing back a Rosette-owned identity is an acquisition, never a creation" {
    var runtime = Runtime{};
    const cases = [_]struct { class: []const u8, receiver: u64, selector: []const u8, facility: Facility }{
        .{ .class = "NSApplication", .receiver = 0xFFFF_FE00_0000_0000, .selector = "sharedApplication", .facility = .application },
        .{ .class = "CAMetalLayer", .receiver = 0xFFFF_FE00_0000_0040, .selector = "layer", .facility = .layer },
        .{ .class = "NSWindow", .receiver = WINDOW_TOKEN, .selector = "contentView", .facility = .content_view },
        .{ .class = "NSView", .receiver = VIEW_TOKEN, .selector = "window", .facility = .window },
        .{ .class = "NSView", .receiver = VIEW_TOKEN, .selector = "layer", .facility = .layer },
    };
    for (cases) |case| {
        const outcome = runtime.handleObjcMessage(case.class, case.receiver, case.selector, 0);
        try std.testing.expectEqual(case.facility, outcome.handled.binding.facility);
        try std.testing.expectEqual(Operation.acquire, outcome.handled.binding.operation);
        // The whole point: an acquisition is admitted from any named domain
        // with nothing observed, so handing the window over cannot be fatal.
        try std.testing.expect(admission.mayForward(.xenia_host, case.facility, .acquire));
        try std.testing.expectEqual(
            @as(admission.ConditionMask, 0),
            admission.requirements(case.facility, .acquire),
        );
    }
}

// The complete Objective-C surface Xenia sends on macOS, taken from
// windowed_app_main_posix.cc, window_gtk.cc and gtk_sdl2_bridge_mac.cc. If any
// of these stops being handled, the gate turns it into a fault, so the list is
// checked rather than assumed.
test "every selector Xenia sends is one this window substantiates" {
    var runtime = Runtime{};
    const messages = [_]struct { class: []const u8, receiver: u64, selector: []const u8 }{
        .{ .class = "NSApplication", .receiver = 0xFFFF_FE00_0000_0000, .selector = "sharedApplication" },
        .{ .class = "<unknown-class>", .receiver = APPLICATION_TOKEN, .selector = "setActivationPolicy:" },
        .{ .class = "<unknown-class>", .receiver = APPLICATION_TOKEN, .selector = "activateIgnoringOtherApps:" },
        .{ .class = "<unknown-class>", .receiver = WINDOW_TOKEN, .selector = "contentView" },
        .{ .class = "CAMetalLayer", .receiver = 0xFFFF_FE00_0000_0040, .selector = "layer" },
        .{ .class = "<unknown-class>", .receiver = VIEW_TOKEN, .selector = "setWantsLayer:" },
        .{ .class = "<unknown-class>", .receiver = VIEW_TOKEN, .selector = "setLayer:" },
    };
    for (messages) |message| {
        const outcome = runtime.handleObjcMessage(message.class, message.receiver, message.selector, 1);
        switch (outcome) {
            .handled => |result| {
                try std.testing.expect(admission.mayForward(.xenia_host, result.binding.facility, result.binding.operation));
                try std.testing.expect(admission.supports(result.binding.facility, result.binding.operation));
            },
            .foreign, .unrecognized => {
                std.debug.print("unsubstantiated selector: {s}\n", .{message.selector});
                return error.SelectorNotSubstantiated;
            },
        }
    }
}
