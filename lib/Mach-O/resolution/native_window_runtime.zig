const std = @import("std");
const machoCapturePrint = @import("../event_log.zig").machoCapturePrint;

pub const APPLICATION_TOKEN: u64 = 0xFFFF_F400_0000_0011;
pub const WINDOW_TOKEN: u64 = 0xFFFF_F400_0000_0021;
pub const VIEW_TOKEN: u64 = 0xFFFF_F400_0000_0031;
pub const METAL_LAYER_TOKEN: u64 = 0xFFFF_F400_0000_0041;

const NativeStatus = extern struct {
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

extern fn rosette_macho_native_application_ensure() c_int;
extern fn rosette_macho_native_window_ensure(width: u32, height: u32, title: [*:0]const u8) c_int;
extern fn rosette_macho_native_window_set_title(title: [*:0]const u8) c_int;
extern fn rosette_macho_native_window_set_size(width: u32, height: u32) c_int;
extern fn rosette_macho_native_window_show() c_int;
extern fn rosette_macho_native_window_set_fullscreen(fullscreen: c_int) c_int;
extern fn rosette_macho_native_window_attach_metal_layer() c_int;
extern fn rosette_macho_native_window_pump_events() u32;
extern fn rosette_macho_native_window_status() NativeStatus;
extern fn rosette_macho_native_window_shutdown() void;

pub const ObjcResult = struct {
    value: u64,
    action: []const u8,
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
    event_pump_calls: u64 = 0,
    objc_messages: u64 = 0,
    window_ready_logged: bool = false,
    requested_width: u32 = 1280,
    requested_height: u32 = 720,
    title: [512:0]u8 = [_:0]u8{0} ** 512,

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
    ) ?ObjcResult {
        if (std.mem.eql(u8, receiver_class, "NSApplication") and
            std.mem.eql(u8, selector, "sharedApplication"))
        {
            self.objc_messages +|= 1;
            return .{ .value = if (self.ensureApplication()) APPLICATION_TOKEN else 0, .action = "native NSApplication" };
        }
        if (std.mem.eql(u8, receiver_class, "CAMetalLayer") and
            std.mem.eql(u8, selector, "layer"))
        {
            self.objc_messages +|= 1;
            return .{ .value = self.layerToken(), .action = "native CAMetalLayer" };
        }
        if (!isNativeToken(receiver)) return null;
        self.objc_messages +|= 1;

        if (std.mem.eql(u8, selector, "retain") or std.mem.eql(u8, selector, "autorelease") or
            std.mem.eql(u8, selector, "init"))
        {
            return .{ .value = receiver, .action = "native identity lifetime" };
        }
        if (std.mem.eql(u8, selector, "release")) {
            return .{ .value = 0, .action = "native identity lifetime" };
        }
        if (receiver == APPLICATION_TOKEN) {
            if (std.mem.eql(u8, selector, "activateIgnoringOtherApps:") or
                std.mem.eql(u8, selector, "finishLaunching") or
                std.mem.eql(u8, selector, "setActivationPolicy:"))
            {
                _ = self.ensureApplication();
                return .{ .value = if (std.mem.eql(u8, selector, "setActivationPolicy:")) 1 else 0, .action = "native NSApplication state" };
            }
        }
        if (receiver == WINDOW_TOKEN and std.mem.eql(u8, selector, "contentView")) {
            return .{ .value = self.viewToken(), .action = "native NSWindow contentView" };
        }
        if (receiver == WINDOW_TOKEN and std.mem.eql(u8, selector, "makeKeyAndOrderFront:")) {
            _ = self.show();
            return .{ .value = 0, .action = "native NSWindow show" };
        }
        if (receiver == VIEW_TOKEN and std.mem.eql(u8, selector, "window")) {
            return .{ .value = WINDOW_TOKEN, .action = "native NSView window" };
        }
        if (receiver == VIEW_TOKEN and std.mem.eql(u8, selector, "layer")) {
            return .{ .value = self.layerToken(), .action = "native NSView layer" };
        }
        if (receiver == VIEW_TOKEN and std.mem.eql(u8, selector, "setWantsLayer:")) {
            const ok = argument != 0 and self.attachLayer(METAL_LAYER_TOKEN);
            return .{ .value = 0, .action = if (ok) "native NSView wantsLayer" else "native NSView wantsLayer failed" };
        }
        if (receiver == VIEW_TOKEN and std.mem.eql(u8, selector, "setLayer:")) {
            const ok = self.attachLayer(argument);
            return .{ .value = 0, .action = if (ok) "native NSView setLayer" else "native NSView setLayer rejected" };
        }
        if (std.mem.eql(u8, selector, "respondsToSelector:") or
            std.mem.eql(u8, selector, "isKindOfClass:") or
            std.mem.eql(u8, selector, "isEqual:"))
        {
            return .{ .value = 1, .action = "native identity query" };
        }
        return null;
    }

    pub fn logSummary(self: *const Runtime) void {
        if (self.application_ensure_attempts == 0 and self.window_ensure_attempts == 0) return;
        const status = rosette_macho_native_window_status();
        machoCapturePrint(
            "macho-processor: native window bridge: app_attempts={d} window_attempts={d} failures={d} objc={d} view_requests={d} layer(requests/attached/failures)={d}/{d}/{d} surface_bindings={d} event_pumps={d} host(app/window/view/layer/device)=0x{x}/0x{x}/0x{x}/0x{x}/0x{x} drawable={d}x{d} ready(app/window/layer/visible/main)={}/{}/{}/{}/{} events={d}\n",
            .{ self.application_ensure_attempts, self.window_ensure_attempts, self.window_ensure_failures, self.objc_messages, self.view_requests, self.layer_requests, self.layer_attachments, self.layer_attachment_failures, self.surface_bindings, self.event_pump_calls, status.application, status.window, status.view, status.metal_layer, status.metal_device, status.width, status.height, status.application_ready != 0, status.window_ready != 0, status.layer_attached != 0, status.visible != 0, status.on_main_thread != 0, status.events_pumped },
        );
    }
};

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
