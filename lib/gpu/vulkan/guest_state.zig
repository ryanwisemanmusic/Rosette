//! Backend-independent Vulkan guest state.
//!
//! The dynamic-loader bridge has to deal with two different questions at once:
//! whether a guest object is alive, and whether a host driver object has been
//! created for it.  Keeping the guest lifecycle in a small, allocation-free
//! state machine makes that distinction explicit and gives the PM4/presentation
//! code a safe place to record work even when a host Vulkan loader is absent.
//!
//! This is deliberately not a second Vulkan implementation.  It is the guest
//! contract: handles, dependencies, command-buffer recording, synchronization,
//! and the ordering rules that the host bridge must preserve.

const std = @import("std");

pub const Handle = u64;

pub const Failure = enum(u8) {
    no_instance,
    no_device,
    no_surface,
    no_swapchain,
    invalid_handle,
    already_exists,
    wrong_state,
    out_of_slots,
    invalid_extent,
    invalid_count,
    command_buffer_not_recording,
    command_buffer_not_executable,
    wait_not_satisfied,
    device_lost,

    pub fn label(self: Failure) []const u8 {
        return switch (self) {
            .no_instance => "no_instance",
            .no_device => "no_device",
            .no_surface => "no_surface",
            .no_swapchain => "no_swapchain",
            .invalid_handle => "invalid_handle",
            .already_exists => "already_exists",
            .wrong_state => "wrong_state",
            .out_of_slots => "out_of_slots",
            .invalid_extent => "invalid_extent",
            .invalid_count => "invalid_count",
            .command_buffer_not_recording => "command_buffer_not_recording",
            .command_buffer_not_executable => "command_buffer_not_executable",
            .wait_not_satisfied => "wait_not_satisfied",
            .device_lost => "device_lost",
        };
    }
};

pub const Error = error{
    no_instance,
    no_device,
    no_surface,
    no_swapchain,
    invalid_handle,
    already_exists,
    wrong_state,
    out_of_slots,
    invalid_extent,
    invalid_count,
    command_buffer_not_recording,
    command_buffer_not_executable,
    wait_not_satisfied,
    device_lost,
};

pub const DeviceState = enum(u8) {
    cold,
    instance_ready,
    device_ready,
    surface_ready,
    swapchain_ready,
    lost,
};

pub const ObjectKind = enum(u8) {
    buffer,
    image,
    image_view,
    sampler,
    shader_module,
    render_pass,
    framebuffer,
    pipeline,
    pipeline_layout,
    descriptor_set_layout,
    descriptor_pool,
    descriptor_set,
    command_pool,
    command_buffer,
    semaphore,
    fence,
    device_memory,
};

pub const Resource = struct {
    handle: Handle = 0,
    kind: ObjectKind = .buffer,
    size_bytes: u64 = 0,
    width: u32 = 0,
    height: u32 = 0,
    depth: u32 = 1,
    format: u32 = 0,
    usage: u32 = 0,
    memory: Handle = 0,
    memory_offset: u64 = 0,
    alive: bool = false,
};

pub const CommandOp = enum(u8) {
    begin_render_pass,
    end_render_pass,
    next_subpass,
    bind_graphics_pipeline,
    bind_compute_pipeline,
    bind_vertex_buffers,
    bind_index_buffer,
    bind_descriptor_sets,
    set_viewport,
    set_scissor,
    set_blend_constants,
    set_depth_bias,
    set_stencil_reference,
    push_constants,
    draw,
    draw_indexed,
    draw_indirect,
    draw_indexed_indirect,
    dispatch,
    dispatch_indirect,
    copy_buffer,
    copy_image,
    copy_buffer_to_image,
    copy_image_to_buffer,
    blit_image,
    resolve_image,
    fill_buffer,
    update_buffer,
    clear_color_image,
    clear_depth_stencil_image,
    pipeline_barrier,
    wait_events,
    set_event,
    reset_event,
};

pub const Command = struct {
    op: CommandOp,
    a: Handle = 0,
    b: Handle = 0,
    c: Handle = 0,
    x: u32 = 0,
    y: u32 = 0,
    z: u32 = 0,
    w: u32 = 0,
};

const max_commands_per_buffer = 512;
const max_resources = 1024;
const max_command_buffers = 256;
const max_semaphores = 256;
const max_fences = 256;
const max_swapchain_images = 8;

const CommandBuffer = struct {
    handle: Handle = 0,
    pool: Handle = 0,
    secondary: bool = false,
    recording: bool = false,
    executable: bool = false,
    submitted: bool = false,
    command_count: u16 = 0,
    commands: [max_commands_per_buffer]Command = undefined,

    fn clear(self: *CommandBuffer) void {
        self.* = .{};
    }
};

const SemaphoreState = struct {
    handle: Handle = 0,
    signaled: bool = false,
    timeline: bool = false,
    value: u64 = 0,
};

const FenceState = struct {
    handle: Handle = 0,
    signaled: bool = false,
};

pub const Swapchain = struct {
    handle: Handle = 0,
    width: u32 = 0,
    height: u32 = 0,
    image_count: u32 = 0,
    next_image: u32 = 0,
    present_mode: u32 = 0,
    format: u32 = 0,
    images: [max_swapchain_images]Handle = [_]Handle{0} ** max_swapchain_images,
};

pub const Snapshot = struct {
    state: DeviceState,
    instance: Handle,
    device: Handle,
    surface: Handle,
    swapchain: Handle,
    live_resources: u32,
    executable_command_buffers: u32,
    submissions: u64,
    presents: u64,
    draws: u64,
    dispatches: u64,
};

pub const State = struct {
    next_handle: Handle = 0xFFFF_F400_0000_0001,
    state: DeviceState = .cold,
    instance: Handle = 0,
    physical_device: Handle = 0,
    device: Handle = 0,
    surface: Handle = 0,
    swapchain: Swapchain = .{},
    resources: [max_resources]Resource = [_]Resource{.{}} ** max_resources,
    command_buffers: [max_command_buffers]CommandBuffer = [_]CommandBuffer{.{}} ** max_command_buffers,
    semaphores: [max_semaphores]SemaphoreState = [_]SemaphoreState{.{}} ** max_semaphores,
    fences: [max_fences]FenceState = [_]FenceState{.{}} ** max_fences,
    submissions: u64 = 0,
    presents: u64 = 0,
    draws: u64 = 0,
    dispatches: u64 = 0,
    last_error: ?Failure = null,

    pub fn newHandle(self: *State) Handle {
        const handle = self.next_handle;
        self.next_handle +%= 0x10;
        return handle;
    }

    fn fail(self: *State, err: Failure) Error {
        self.last_error = err;
        return switch (err) {
            .no_instance => error.no_instance,
            .no_device => error.no_device,
            .no_surface => error.no_surface,
            .no_swapchain => error.no_swapchain,
            .invalid_handle => error.invalid_handle,
            .already_exists => error.already_exists,
            .wrong_state => error.wrong_state,
            .out_of_slots => error.out_of_slots,
            .invalid_extent => error.invalid_extent,
            .invalid_count => error.invalid_count,
            .command_buffer_not_recording => error.command_buffer_not_recording,
            .command_buffer_not_executable => error.command_buffer_not_executable,
            .wait_not_satisfied => error.wait_not_satisfied,
            .device_lost => error.device_lost,
        };
    }

    pub fn createInstance(self: *State) Error!Handle {
        if (self.instance != 0) return self.fail(.already_exists);
        self.instance = self.newHandle();
        self.physical_device = self.newHandle();
        self.state = .instance_ready;
        self.last_error = null;
        return self.instance;
    }

    pub fn destroyInstance(self: *State) void {
        self.destroyDevice();
        self.instance = 0;
        self.physical_device = 0;
        self.surface = 0;
        self.swapchain = .{};
        self.state = .cold;
        self.last_error = null;
    }

    pub fn createDevice(self: *State) Error!Handle {
        if (self.instance == 0) return self.fail(.no_instance);
        if (self.device != 0) return self.fail(.already_exists);
        self.device = self.newHandle();
        self.state = .device_ready;
        self.last_error = null;
        return self.device;
    }

    pub fn destroyDevice(self: *State) void {
        if (self.device == 0) return;
        self.device = 0;
        self.surface = 0;
        self.swapchain = .{};
        for (&self.command_buffers) |*buffer| buffer.clear();
        for (&self.resources) |*resource| resource.* = .{};
        for (&self.semaphores) |*semaphore| semaphore.* = .{};
        for (&self.fences) |*fence| fence.* = .{};
        self.state = if (self.instance != 0) .instance_ready else .cold;
    }

    pub fn createSurface(self: *State) Error!Handle {
        if (self.device == 0) return self.fail(.no_device);
        if (self.surface != 0) return self.fail(.already_exists);
        self.surface = self.newHandle();
        self.state = .surface_ready;
        self.last_error = null;
        return self.surface;
    }

    pub fn createSwapchain(
        self: *State,
        surface: Handle,
        width: u32,
        height: u32,
        image_count: u32,
        format: u32,
        present_mode: u32,
    ) Error!Handle {
        if (self.device == 0) return self.fail(.no_device);
        if (self.surface == 0) return self.fail(.no_surface);
        if (surface != self.surface) return self.fail(.invalid_handle);
        if (width == 0 or height == 0) return self.fail(.invalid_extent);
        if (image_count == 0 or image_count > max_swapchain_images) return self.fail(.invalid_count);
        if (self.swapchain.handle != 0) return self.fail(.already_exists);
        self.swapchain = .{
            .handle = self.newHandle(),
            .width = width,
            .height = height,
            .image_count = image_count,
            .present_mode = present_mode,
            .format = format,
        };
        for (self.swapchain.images[0..image_count]) |*image| image.* = self.newHandle();
        self.state = .swapchain_ready;
        self.last_error = null;
        return self.swapchain.handle;
    }

    pub fn acquireNextImage(self: *State, swapchain: Handle, signal_semaphore: Handle, signal_fence: Handle) Error!u32 {
        if (self.swapchain.handle == 0 or self.state != .swapchain_ready) return self.fail(.no_swapchain);
        if (swapchain != self.swapchain.handle) return self.fail(.invalid_handle);
        const index = self.swapchain.next_image;
        self.swapchain.next_image = (index + 1) % self.swapchain.image_count;
        if (signal_semaphore != 0) {
            const semaphore = self.findSemaphore(signal_semaphore) orelse return self.fail(.invalid_handle);
            semaphore.signaled = true;
            if (semaphore.timeline) semaphore.value +%= 1;
        }
        if (signal_fence != 0) {
            const fence = self.findFence(signal_fence) orelse return self.fail(.invalid_handle);
            fence.signaled = true;
        }
        self.last_error = null;
        return index;
    }

    pub fn allocateCommandBuffer(self: *State, pool: Handle, secondary: bool) Error!Handle {
        if (self.device == 0) return self.fail(.no_device);
        if (pool == 0) return self.fail(.invalid_handle);
        for (&self.command_buffers) |*buffer| {
            if (buffer.handle != 0) continue;
            buffer.* = .{ .handle = self.newHandle(), .pool = pool, .secondary = secondary };
            self.last_error = null;
            return buffer.handle;
        }
        return self.fail(.out_of_slots);
    }

    pub fn beginCommandBuffer(self: *State, handle: Handle) Error!void {
        const buffer = self.findCommandBuffer(handle) orelse return self.fail(.invalid_handle);
        if (buffer.recording) return self.fail(.wrong_state);
        buffer.recording = true;
        buffer.executable = false;
        buffer.submitted = false;
        buffer.command_count = 0;
        self.last_error = null;
    }

    pub fn endCommandBuffer(self: *State, handle: Handle) Error!void {
        const buffer = self.findCommandBuffer(handle) orelse return self.fail(.invalid_handle);
        if (!buffer.recording) return self.fail(.command_buffer_not_recording);
        buffer.recording = false;
        buffer.executable = true;
        self.last_error = null;
    }

    pub fn resetCommandBuffer(self: *State, handle: Handle) Error!void {
        const buffer = self.findCommandBuffer(handle) orelse return self.fail(.invalid_handle);
        buffer.recording = false;
        buffer.executable = false;
        buffer.submitted = false;
        buffer.command_count = 0;
        self.last_error = null;
    }

    pub fn record(self: *State, handle: Handle, command: Command) Error!void {
        const buffer = self.findCommandBuffer(handle) orelse return self.fail(.invalid_handle);
        if (!buffer.recording) return self.fail(.command_buffer_not_recording);
        if (buffer.command_count == max_commands_per_buffer) return self.fail(.out_of_slots);
        buffer.commands[buffer.command_count] = command;
        buffer.command_count += 1;
        switch (command.op) {
            .draw, .draw_indexed, .draw_indirect, .draw_indexed_indirect => self.draws +%= 1,
            .dispatch, .dispatch_indirect => self.dispatches +%= 1,
            else => {},
        }
        self.last_error = null;
    }

    pub fn submit(self: *State, command_buffers: []const Handle, wait_semaphores: []const Handle, signal_semaphores: []const Handle, fence: Handle) Error!void {
        if (self.device == 0) return self.fail(.no_device);
        if (command_buffers.len == 0) return self.fail(.invalid_count);
        for (wait_semaphores) |handle| {
            const semaphore = self.findSemaphore(handle) orelse return self.fail(.invalid_handle);
            if (!semaphore.signaled) return self.fail(.wait_not_satisfied);
            if (!semaphore.timeline) semaphore.signaled = false;
        }
        for (command_buffers) |handle| {
            const buffer = self.findCommandBuffer(handle) orelse return self.fail(.invalid_handle);
            if (!buffer.executable) return self.fail(.command_buffer_not_executable);
            buffer.submitted = true;
        }
        for (signal_semaphores) |handle| {
            const semaphore = self.findSemaphore(handle) orelse return self.fail(.invalid_handle);
            semaphore.signaled = true;
            if (semaphore.timeline) semaphore.value +%= 1;
        }
        if (fence != 0) {
            const target = self.findFence(fence) orelse return self.fail(.invalid_handle);
            target.signaled = true;
        }
        self.submissions +%= 1;
        self.last_error = null;
    }

    pub fn present(self: *State, swapchain: Handle, wait_semaphores: []const Handle) Error!u32 {
        if (self.swapchain.handle == 0) return self.fail(.no_swapchain);
        if (swapchain != self.swapchain.handle) return self.fail(.invalid_handle);
        for (wait_semaphores) |handle| {
            const semaphore = self.findSemaphore(handle) orelse return self.fail(.invalid_handle);
            if (!semaphore.signaled) return self.fail(.wait_not_satisfied);
            if (!semaphore.timeline) semaphore.signaled = false;
        }
        self.presents +%= 1;
        self.last_error = null;
        return self.swapchain.next_image;
    }

    pub fn createResource(self: *State, kind: ObjectKind, size_bytes: u64, width: u32, height: u32, depth: u32, format: u32, usage: u32) Error!Handle {
        if (self.device == 0) return self.fail(.no_device);
        for (&self.resources) |*resource| {
            if (resource.alive) continue;
            const handle = self.newHandle();
            resource.* = .{
                .handle = handle,
                .kind = kind,
                .size_bytes = size_bytes,
                .width = width,
                .height = height,
                .depth = @max(depth, 1),
                .format = format,
                .usage = usage,
                .alive = true,
            };
            self.last_error = null;
            return handle;
        }
        return self.fail(.out_of_slots);
    }

    pub fn bindResource(self: *State, resource: Handle, memory: Handle, offset: u64) Error!void {
        const target = self.findResource(resource) orelse return self.fail(.invalid_handle);
        if (memory == 0 or offset > memory) return self.fail(.invalid_handle);
        target.memory = memory;
        target.memory_offset = offset;
        self.last_error = null;
    }

    pub fn createSemaphore(self: *State, timeline: bool, initial_value: u64) Error!Handle {
        if (self.device == 0) return self.fail(.no_device);
        for (&self.semaphores) |*semaphore| {
            if (semaphore.handle != 0) continue;
            semaphore.* = .{ .handle = self.newHandle(), .timeline = timeline, .value = initial_value, .signaled = timeline and initial_value != 0 };
            self.last_error = null;
            return semaphore.handle;
        }
        return self.fail(.out_of_slots);
    }

    pub fn createFence(self: *State, signaled: bool) Error!Handle {
        if (self.device == 0) return self.fail(.no_device);
        for (&self.fences) |*fence| {
            if (fence.handle != 0) continue;
            fence.* = .{ .handle = self.newHandle(), .signaled = signaled };
            self.last_error = null;
            return fence.handle;
        }
        return self.fail(.out_of_slots);
    }

    pub fn waitFence(self: *State, handle: Handle) Error!void {
        const fence = self.findFence(handle) orelse return self.fail(.invalid_handle);
        if (!fence.signaled) return self.fail(.wait_not_satisfied);
        self.last_error = null;
    }

    pub fn resetFence(self: *State, handle: Handle) Error!void {
        const fence = self.findFence(handle) orelse return self.fail(.invalid_handle);
        fence.signaled = false;
        self.last_error = null;
    }

    pub fn snapshot(self: *const State) Snapshot {
        var resources: u32 = 0;
        for (self.resources) |resource| {
            if (resource.alive) resources += 1;
        }
        var executable: u32 = 0;
        for (self.command_buffers) |buffer| {
            if (buffer.executable) executable += 1;
        }
        return .{
            .state = self.state,
            .instance = self.instance,
            .device = self.device,
            .surface = self.surface,
            .swapchain = self.swapchain.handle,
            .live_resources = resources,
            .executable_command_buffers = executable,
            .submissions = self.submissions,
            .presents = self.presents,
            .draws = self.draws,
            .dispatches = self.dispatches,
        };
    }

    fn findCommandBuffer(self: *State, handle: Handle) ?*CommandBuffer {
        for (&self.command_buffers) |*buffer| if (buffer.handle == handle) return buffer;
        return null;
    }

    fn findSemaphore(self: *State, handle: Handle) ?*SemaphoreState {
        for (&self.semaphores) |*semaphore| if (semaphore.handle == handle) return semaphore;
        return null;
    }

    fn findFence(self: *State, handle: Handle) ?*FenceState {
        for (&self.fences) |*fence| if (fence.handle == handle) return fence;
        return null;
    }

    fn findResource(self: *State, handle: Handle) ?*Resource {
        for (&self.resources) |*resource| if (resource.alive and resource.handle == handle) return resource;
        return null;
    }
};

test "guest Vulkan state enforces the rendering lifecycle" {
    var state: State = .{};
    try std.testing.expectError(Error.no_instance, state.createDevice());
    const instance = try state.createInstance();
    try std.testing.expect(instance != 0);
    const device = try state.createDevice();
    try std.testing.expect(device != 0);
    const surface = try state.createSurface();
    const swapchain = try state.createSwapchain(surface, 1280, 720, 3, 44, 2);
    try std.testing.expect(swapchain != 0);
    const semaphore = try state.createSemaphore(false, 0);
    const fence = try state.createFence(false);
    const pool = try state.createResource(.command_pool, 0, 0, 0, 1, 0, 0);
    const command_buffer = try state.allocateCommandBuffer(pool, false);
    try state.beginCommandBuffer(command_buffer);
    try state.record(command_buffer, .{ .op = .draw, .x = 3, .y = 1 });
    try state.endCommandBuffer(command_buffer);
    try state.submit(&.{command_buffer}, &.{}, &.{semaphore}, fence);
    _ = try state.acquireNextImage(swapchain, 0, 0);
    _ = try state.present(swapchain, &.{semaphore});
    const snapshot = state.snapshot();
    try std.testing.expectEqual(DeviceState.swapchain_ready, snapshot.state);
    try std.testing.expectEqual(@as(u64, 1), snapshot.submissions);
    try std.testing.expectEqual(@as(u64, 1), snapshot.presents);
    try std.testing.expectEqual(@as(u64, 1), snapshot.draws);
}

test "command buffers reject recording and submission order mistakes" {
    var state: State = .{};
    _ = try state.createInstance();
    _ = try state.createDevice();
    const pool = try state.createResource(.command_pool, 0, 0, 0, 1, 0, 0);
    const buffer = try state.allocateCommandBuffer(pool, false);
    try std.testing.expectError(Error.command_buffer_not_recording, state.record(buffer, .{ .op = .draw }));
    try std.testing.expectError(Error.command_buffer_not_executable, state.submit(&.{buffer}, &.{}, &.{}, 0));
}
