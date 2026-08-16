const std = @import("std");
const api = @import("api.zig");
const backend = @import("backend.zig");
const handles = @import("handles.zig");
const hardware_description = @import("hardware_description.zig");
const device_tree = @import("device_tree");

pub const Error = backend.Error || handles.ValidationError || error{
    MissingCapability,
    InvalidDescription,
    SessionLimit,
};

pub const TraceKind = enum(u8) {
    handshake_created,
    handshake_closed,
    handshake_failed,
    backend_selected,
    adapter_created,
    device_created,
    queue_created,
    resource_created,
    resource_destroyed,
    guest_memory_mapped,
    command_buffer_created,
    command_submitted,
    synchronization,
    presented,
    hardware_description_updated,
    hardware_description_failed,
};

pub const TraceEvent = struct {
    sequence: u64 = 0,
    kind: TraceKind = .handshake_created,
    object: handles.Handle = .{},
    related: handles.Handle = .{},
    value: u64 = 0,
    backend_kind: api.BackendKind = .none,
};

/// Concise, backend-neutral health of the host execution boundary. This is an
/// observation only: it never changes guest/Xenos state and a degraded result
/// must not become a substitute for authentic guest GPU bootstrap.
pub const BridgeHealthStage = enum(u8) {
    unavailable,
    loader,
    instance,
    instance_and_surface,
    physical_adapter,
    logical_device,
    graphics_queue,
    resources,
    command_execution,
    presentation,
};

pub const BridgeHealth = struct {
    stage: BridgeHealthStage = .unavailable,
    first_missing_execution_capability: ?api.Capability = null,
    advisory_only: bool = true,
    authentic_submission_seen: bool = false,
    authentic_presentation_seen: bool = false,

    pub fn readyForHostExecution(self: BridgeHealth) bool {
        return self.first_missing_execution_capability == null;
    }

    pub fn fingerprint(self: BridgeHealth) u64 {
        const missing: u64 = if (self.first_missing_execution_capability) |capability|
            @as(u64, @intFromEnum(capability)) + 1
        else
            0;
        return @as(u64, @intFromEnum(self.stage)) |
            (missing << 8) |
            (@as(u64, @intFromBool(self.authentic_submission_seen)) << 24) |
            (@as(u64, @intFromBool(self.authentic_presentation_seen)) << 25);
    }
};

const max_sessions: usize = 16;
const max_trace_events: usize = 256;

const Session = struct {
    handle: handles.Handle = .{},
    adapter: handles.Handle = .{},
    device: handles.Handle = .{},
    graphics_queue: handles.Handle = .{},
    compute_queue: handles.Handle = .{},
    transfer_queue: handles.Handle = .{},
    sparse_queue: handles.Handle = .{},
    negotiated: api.CapabilitySet = .{},
};

const Resource = struct {
    handle: handles.Handle = .{},
    backend_token: u64 = 0,
    size: u64 = 0,
    guest_physical_address: u64 = 0,
    resource_offset: u64 = 0,
    related: handles.Handle = .{},
};

pub const Runtime = struct {
    adapter: backend.Adapter = backend.Adapter.none(),
    registry: handles.Registry = .{},
    sessions: [max_sessions]Session = [_]Session{.{}} ** max_sessions,
    resources: [handles.max_handles]Resource = [_]Resource{.{}} ** handles.max_handles,
    trace_events: [max_trace_events]TraceEvent = [_]TraceEvent{.{}} ** max_trace_events,
    trace_sequence: u64 = 0,
    handshake_attempts: u64 = 0,
    handshake_successes: u64 = 0,
    handshake_failures: u64 = 0,
    submissions: u64 = 0,
    presentations: u64 = 0,
    hardware_tree: device_tree.Tree = .{},
    hardware_tree_valid: bool = false,
    hardware_description_failures: u64 = 0,

    pub fn installBackend(self: *Runtime, adapter: backend.Adapter) void {
        for (0..self.sessions.len) |index| {
            const session = self.sessions[index].handle;
            if (session.isValid()) self.closeSession(session) catch {};
        }
        if (self.adapter.operations.shutdown) |shutdown| shutdown(self.adapter.context);
        self.adapter = adapter;
        self.record(.backend_selected, .{}, .{}, 0);
        self.refreshHardwareDescription();
    }

    pub fn deinit(self: *Runtime) void {
        for (0..self.sessions.len) |index| {
            const session = self.sessions[index].handle;
            if (session.isValid()) self.closeSession(session) catch {};
        }
        if (self.adapter.operations.shutdown) |shutdown| shutdown(self.adapter.context);
        self.* = .{};
    }

    pub fn installVulkanBoundary(self: *Runtime, boundary: backend.VulkanBoundary) void {
        self.installBackend(boundary.adapter(.{}, null));
    }

    /// Record native work performed by a Rosette-owned backend adapter outside
    /// the handle API itself. The Vulkan presenter predates the generic handle
    /// surface and owns its swapchain directly, but its real queue submissions
    /// and accepted presentation requests are still facts about this runtime's
    /// host execution boundary. Observing them here keeps bridge health honest
    /// without fabricating a guest frame or a guest GPU command.
    pub fn observeBackendProgress(self: *Runtime, submitted: bool, presented: bool) void {
        if (submitted) self.submissions +|= 1;
        if (presented) self.presentations +|= 1;
    }

    pub fn hardwareDescription(self: *const Runtime) ?*const device_tree.Tree {
        return if (self.hardware_tree_valid) &self.hardware_tree else null;
    }

    pub fn bridgeHealth(self: *const Runtime) BridgeHealth {
        const provided = self.adapter.description.provided;
        const execution_required = api.HandshakeRequest.xeniaHostExecution().required;
        const first_missing = execution_required.difference(provided).first();
        const stage: BridgeHealthStage = if (self.presentations != 0 and
            provided.contains(.presentation))
            .presentation
        else if (self.submissions != 0)
            .command_execution
        else if (provided.contains(.command_buffer) and
            provided.contains(.resource_barrier))
            .command_execution
        else if (provided.contains(.buffer) and provided.contains(.image_2d) and
            provided.contains(.guest_memory_mapping))
            .resources
        else if (provided.contains(.queue_graphics))
            .graphics_queue
        else if (provided.contains(.logical_device))
            .logical_device
        else if (provided.contains(.physical_adapter))
            .physical_adapter
        else if (provided.contains(.backend_instance) and provided.contains(.surface))
            .instance_and_surface
        else if (provided.contains(.backend_instance))
            .instance
        else if (self.adapter.description.kind != .none)
            .loader
        else
            .unavailable;
        return .{
            .stage = stage,
            .first_missing_execution_capability = first_missing,
            .authentic_submission_seen = self.submissions != 0,
            .authentic_presentation_seen = self.presentations != 0,
        };
    }

    pub fn negotiate(self: *Runtime, request: api.HandshakeRequest) api.HandshakeResponse {
        self.handshake_attempts +|= 1;
        var response = api.HandshakeResponse{};
        response.backend = @intFromEnum(self.adapter.description.kind);
        response.buffer_alignment = self.adapter.description.buffer_alignment;
        response.image_alignment = self.adapter.description.image_alignment;
        response.guest_mapping_alignment = self.adapter.description.guest_mapping_alignment;
        response.limits = .{
            .graphics_queue_count = self.adapter.description.graphics_queue_count,
            .compute_queue_count = self.adapter.description.compute_queue_count,
            .transfer_queue_count = self.adapter.description.transfer_queue_count,
            .sparse_queue_count = self.adapter.description.sparse_queue_count,
            .host_visible_heap_bytes = self.adapter.description.host_visible_heap_bytes,
            .device_local_heap_bytes = self.adapter.description.device_local_heap_bytes,
            .maximum_buffer_bytes = self.adapter.description.maximum_buffer_bytes,
            .maximum_image_dimension_2d = self.adapter.description.maximum_image_dimension_2d,
            .maximum_image_array_layers = self.adapter.description.maximum_image_array_layers,
            .maximum_push_constant_bytes = self.adapter.description.maximum_push_constant_bytes,
            .timestamp_period_picoseconds = self.adapter.description.timestamp_period_picoseconds,
            .sparse_buffer_block_bytes = self.adapter.description.sparse_buffer_block_bytes,
            .sparse_image_block_bytes = self.adapter.description.sparse_image_block_bytes,
            .maximum_timeline_value_difference = self.adapter.description.maximum_timeline_value_difference,
        };
        response.surface = self.adapter.description.surface;

        if (request.magic != api.abi_magic or request.struct_size < @sizeOf(api.HandshakeRequest)) {
            return self.failHandshake(&response, .invalid_request, null, "invalid Rosette GPU handshake header");
        }
        if (request.minimum_version > api.api_version or request.maximum_version < api.api_version) {
            return self.failHandshake(&response, .incompatible_version, null, "no mutually supported Rosette GPU API version");
        }
        response.version = api.api_version;

        var required = request.required;
        addQueueCapabilities(&required, request.required_queue_mask);
        var desired = request.desired;
        addQueueCapabilities(&desired, request.desired_queue_mask);
        response.missing_required = required.difference(self.adapter.description.provided);
        response.missing_desired = desired.difference(self.adapter.description.provided);
        response.negotiated = required.unionWith(desired).intersect(self.adapter.description.provided);
        if (response.missing_required.first()) |missing| {
            var message_buffer: [192]u8 = undefined;
            const message = std.fmt.bufPrint(&message_buffer, "missing required capability: {s}", .{api.capabilityName(missing)}) catch
                "missing required GPU capability";
            return self.failHandshake(&response, .missing_capability, missing, message);
        }

        const handle_count = requiredHandleCount(response.negotiated);
        if (self.registry.live_count + handle_count > handles.max_handles or self.freeSession() == null) {
            return self.failHandshake(&response, .resource_exhausted, null, "Rosette GPU handle/session capacity exhausted");
        }

        const session_slot = self.freeSession().?;
        const consumer_owner = request.consumer +% 1;
        const session_handle = self.registry.allocate(.session, consumer_owner) catch
            return self.failHandshake(&response, .resource_exhausted, null, "Rosette GPU session handle allocation failed");
        const child_owner: u32 = @intCast(session_handle.slot() + 1);
        var session = Session{ .handle = session_handle, .negotiated = response.negotiated };
        if (response.negotiated.contains(.physical_adapter)) {
            session.adapter = self.registry.allocate(.adapter, child_owner) catch unreachable;
            self.resources[session.adapter.slot()] = .{ .handle = session.adapter, .backend_token = self.adapter.adapter_token };
            self.record(.adapter_created, session.adapter, session_handle, 0);
        }
        if (response.negotiated.contains(.logical_device)) {
            session.device = self.registry.allocate(.device, child_owner) catch unreachable;
            self.resources[session.device.slot()] = .{ .handle = session.device, .backend_token = self.adapter.device_token };
            self.record(.device_created, session.device, session.adapter, 0);
        }
        if (response.negotiated.contains(.queue_graphics)) session.graphics_queue = self.allocateQueue(child_owner, session.device, .graphics, self.adapter.queue_tokens[0]);
        if (response.negotiated.contains(.queue_compute)) session.compute_queue = self.allocateQueue(child_owner, session.device, .compute, self.adapter.queue_tokens[1]);
        if (response.negotiated.contains(.queue_transfer)) session.transfer_queue = self.allocateQueue(child_owner, session.device, .transfer, self.adapter.queue_tokens[2]);
        if (response.negotiated.contains(.queue_sparse)) session.sparse_queue = self.allocateQueue(child_owner, session.device, .sparse, self.adapter.queue_tokens[3]);
        self.sessions[session_slot] = session;

        response.session = session.handle.raw;
        response.adapter = session.adapter.raw;
        response.device = session.device.raw;
        response.graphics_queue = session.graphics_queue.raw;
        response.compute_queue = session.compute_queue.raw;
        response.transfer_queue = session.transfer_queue.raw;
        response.sparse_queue = session.sparse_queue.raw;
        response.status = @intFromEnum(if (response.missing_desired.isEmpty()) api.Status.success else api.Status.degraded);
        if (response.statusValue() == .degraded) {
            if (response.missing_desired.first()) |missing| {
                var message_buffer: [192]u8 = undefined;
                const message = std.fmt.bufPrint(&message_buffer, "negotiated without desired capability: {s}", .{api.capabilityName(missing)}) catch
                    "negotiated with unavailable optional GPU capabilities";
                response.setReason(message);
                response.first_missing_capability = @intFromEnum(missing);
            }
        } else {
            response.setReason("Rosette GPU handshake negotiated successfully");
        }
        self.handshake_successes +|= 1;
        self.record(.handshake_created, session.handle, session.device, response.status);
        return response;
    }

    pub fn createBuffer(self: *Runtime, session_handle: handles.Handle, description: api.BufferDesc) Error!handles.Handle {
        if (description.size == 0) return error.InvalidDescription;
        const session = try self.sessionFor(session_handle);
        try require(session.negotiated, .buffer);
        const create = self.adapter.operations.create_buffer orelse return error.Unsupported;
        var backend_token: u64 = 0;
        try create(self.adapter.context, &description, &backend_token);
        const owner: u32 = @intCast(session_handle.slot() + 1);
        const handle = try self.registry.allocate(.buffer, owner);
        self.resources[handle.slot()] = .{
            .handle = handle,
            .backend_token = backend_token,
            .size = description.size,
        };
        self.record(.resource_created, handle, session_handle, description.size);
        return handle;
    }

    pub fn createImage(self: *Runtime, session_handle: handles.Handle, description: api.ImageDesc) Error!handles.Handle {
        if (description.width == 0 or description.height == 0 or description.depth == 0) return error.InvalidDescription;
        const session = try self.sessionFor(session_handle);
        try require(session.negotiated, .image_2d);
        const create = self.adapter.operations.create_image orelse return error.Unsupported;
        var backend_token: u64 = 0;
        try create(self.adapter.context, &description, &backend_token);
        const owner: u32 = @intCast(session_handle.slot() + 1);
        const handle = try self.registry.allocate(.image, owner);
        self.resources[handle.slot()] = .{
            .handle = handle,
            .backend_token = backend_token,
            .size = @as(u64, description.width) * description.height * description.depth,
        };
        self.record(.resource_created, handle, session_handle, self.resources[handle.slot()].size);
        return handle;
    }

    pub fn createSampler(self: *Runtime, session_handle: handles.Handle, description: api.SamplerDesc) Error!handles.Handle {
        const session = try self.sessionFor(session_handle);
        try require(session.negotiated, .sampler);
        const create = self.adapter.operations.create_sampler orelse return error.Unsupported;
        var backend_token: u64 = 0;
        try create(self.adapter.context, &description, &backend_token);
        return self.storeBackendResource(session_handle, .sampler, backend_token, 0, .{});
    }

    pub fn createSync(self: *Runtime, session_handle: handles.Handle, description: api.SyncDesc) Error!handles.Handle {
        const session = try self.sessionFor(session_handle);
        const sync_kind = std.meta.intToEnum(api.SyncKind, description.kind) catch return error.InvalidDescription;
        const capability: api.Capability = switch (sync_kind) {
            .fence => .fence,
            .binary_semaphore => .semaphore_binary,
            .timeline_semaphore => .semaphore_timeline,
        };
        try require(session.negotiated, capability);
        const create = self.adapter.operations.create_sync orelse return error.Unsupported;
        var backend_token: u64 = 0;
        try create(self.adapter.context, &description, &backend_token);
        const kind: handles.Kind = if (sync_kind == .fence) .fence else .semaphore;
        const handle = try self.storeBackendResource(session_handle, kind, backend_token, 0, .{});
        self.record(.synchronization, handle, session_handle, description.initial_value);
        return handle;
    }

    pub fn createSurface(self: *Runtime, session_handle: handles.Handle, description: api.SurfaceDesc) Error!handles.Handle {
        const session = try self.sessionFor(session_handle);
        try require(session.negotiated, .surface);
        const create = self.adapter.operations.create_surface orelse return error.Unsupported;
        var backend_token: u64 = 0;
        try create(self.adapter.context, &description, &backend_token);
        return self.storeBackendResource(session_handle, .surface, backend_token, 0, .{});
    }

    pub fn createSwapchain(self: *Runtime, session_handle: handles.Handle, description: api.SwapchainDesc) Error!handles.Handle {
        const session = try self.sessionFor(session_handle);
        try require(session.negotiated, .swapchain);
        const surface = handles.Handle{ .raw = description.surface };
        const owner: u32 = @intCast(session_handle.slot() + 1);
        try self.registry.validate(surface, .surface, owner);
        const create = self.adapter.operations.create_swapchain orelse return error.Unsupported;
        var backend_token: u64 = 0;
        try create(self.adapter.context, &description, &backend_token);
        return self.storeBackendResource(session_handle, .swapchain, backend_token, description.image_count, surface);
    }

    pub fn mapGuestMemory(self: *Runtime, session_handle: handles.Handle, description: api.GuestMemoryMappingDesc) Error!handles.Handle {
        if (description.length == 0) return error.InvalidDescription;
        const session = try self.sessionFor(session_handle);
        try require(session.negotiated, .guest_memory_mapping);
        const resource = handles.Handle{ .raw = description.resource };
        const owner: u32 = @intCast(session_handle.slot() + 1);
        const resource_owner = try self.registry.ownerOf(resource);
        if (resource_owner != owner) return error.WrongOwner;
        if (resource.kind() != .buffer and resource.kind() != .image) return error.WrongKind;
        if (description.resource_offset + description.length < description.resource_offset) return error.InvalidDescription;
        const resource_record = self.resources[resource.slot()];
        if (description.resource_offset + description.length > resource_record.size) return error.InvalidDescription;
        const mapping = try self.registry.allocate(.guest_mapping, owner);
        self.resources[mapping.slot()] = .{
            .handle = mapping,
            .size = description.length,
            .guest_physical_address = description.guest_physical_address,
            .resource_offset = description.resource_offset,
            .related = resource,
        };
        self.record(.guest_memory_mapped, mapping, resource, description.guest_physical_address);
        return mapping;
    }

    pub fn createCommandBuffer(self: *Runtime, session_handle: handles.Handle, queue_class: api.QueueClass) Error!handles.Handle {
        const session = try self.sessionFor(session_handle);
        try require(session.negotiated, .command_buffer);
        const queue = queueFor(session.*, queue_class);
        if (!queue.isValid()) return error.MissingCapability;
        const create = self.adapter.operations.create_command_buffer orelse return error.Unsupported;
        var backend_token: u64 = 0;
        try create(self.adapter.context, queue_class, &backend_token);
        const owner: u32 = @intCast(session_handle.slot() + 1);
        const command = try self.registry.allocate(.command_buffer, owner);
        self.resources[command.slot()] = .{ .handle = command, .backend_token = backend_token, .related = queue };
        self.record(.command_buffer_created, command, queue, 0);
        return command;
    }

    pub fn submit(self: *Runtime, session_handle: handles.Handle, queue: handles.Handle, command: handles.Handle, wait_value: u64, signal_value: u64) Error!void {
        const session = try self.sessionFor(session_handle);
        try require(session.negotiated, .command_buffer);
        const owner: u32 = @intCast(session_handle.slot() + 1);
        try self.registry.validate(queue, .queue, owner);
        try self.registry.validate(command, .command_buffer, owner);
        const submit_backend = self.adapter.operations.submit orelse return error.Unsupported;
        try submit_backend(
            self.adapter.context,
            self.resources[queue.slot()].backend_token,
            self.resources[command.slot()].backend_token,
            wait_value,
            signal_value,
        );
        self.submissions +|= 1;
        self.record(.command_submitted, command, queue, signal_value);
    }

    pub fn present(self: *Runtime, session_handle: handles.Handle, swapchain: handles.Handle, image_index: u32, wait_value: u64) Error!void {
        const session = try self.sessionFor(session_handle);
        try require(session.negotiated, .presentation);
        const owner: u32 = @intCast(session_handle.slot() + 1);
        try self.registry.validate(swapchain, .swapchain, owner);
        const present_backend = self.adapter.operations.present orelse return error.Unsupported;
        try present_backend(self.adapter.context, self.resources[swapchain.slot()].backend_token, image_index, wait_value);
        self.presentations +|= 1;
        self.record(.presented, swapchain, session_handle, image_index);
    }

    pub fn destroyResource(self: *Runtime, session_handle: handles.Handle, handle: handles.Handle) Error!void {
        _ = try self.sessionFor(session_handle);
        const owner: u32 = @intCast(session_handle.slot() + 1);
        const actual_owner = try self.registry.ownerOf(handle);
        if (actual_owner != owner) return error.WrongOwner;
        switch (handle.kind()) {
            .buffer, .image, .command_buffer, .sampler, .fence, .semaphore, .surface, .swapchain => {
                if (self.adapter.operations.destroy_resource) |destroy| {
                    destroy(self.adapter.context, self.resources[handle.slot()].backend_token);
                }
            },
            .guest_mapping => {},
            else => return error.WrongKind,
        }
        const kind = handle.kind();
        try self.registry.destroy(handle, kind, owner);
        self.resources[handle.slot()] = .{};
        self.record(.resource_destroyed, handle, session_handle, 0);
    }

    pub fn closeSession(self: *Runtime, session_handle: handles.Handle) Error!void {
        const consumer_owner = try self.registry.ownerOf(session_handle);
        try self.registry.validate(session_handle, .session, consumer_owner);
        const child_owner: u32 = @intCast(session_handle.slot() + 1);
        for (0..handles.max_handles) |index| {
            const handle = self.registry.handleAt(index) orelse continue;
            if (handle.raw == session_handle.raw) continue;
            if (handle.kind() == .session) continue;
            const owner = self.registry.ownerOf(handle) catch continue;
            if (owner != child_owner) continue;
            switch (handle.kind()) {
                .buffer, .image, .command_buffer, .sampler, .fence, .semaphore, .surface, .swapchain => {
                    if (self.adapter.operations.destroy_resource) |destroy| {
                        destroy(self.adapter.context, self.resources[index].backend_token);
                    }
                },
                else => {},
            }
            self.registry.destroy(handle, handle.kind(), child_owner) catch continue;
            self.resources[index] = .{};
        }
        for (&self.sessions) |*session| {
            if (session.handle.raw != session_handle.raw) continue;
            session.* = .{};
            break;
        }
        try self.registry.destroy(session_handle, .session, consumer_owner);
        self.record(.handshake_closed, session_handle, .{}, 0);
    }

    pub fn latestTrace(self: *const Runtime) ?TraceEvent {
        if (self.trace_sequence == 0) return null;
        return self.trace_events[@intCast((self.trace_sequence - 1) % max_trace_events)];
    }

    fn failHandshake(self: *Runtime, response: *api.HandshakeResponse, status: api.Status, missing: ?api.Capability, reason: []const u8) api.HandshakeResponse {
        response.status = @intFromEnum(status);
        response.first_missing_capability = if (missing) |capability| @intFromEnum(capability) else api.no_capability;
        response.setReason(reason);
        self.handshake_failures +|= 1;
        self.record(.handshake_failed, .{}, .{}, response.status);
        return response.*;
    }

    fn freeSession(self: *Runtime) ?usize {
        for (&self.sessions, 0..) |*session, index| {
            if (!session.handle.isValid()) return index;
        }
        return null;
    }

    fn sessionFor(self: *Runtime, handle: handles.Handle) Error!*Session {
        const consumer_owner = try self.registry.ownerOf(handle);
        try self.registry.validate(handle, .session, consumer_owner);
        for (&self.sessions) |*session| {
            if (session.handle.raw == handle.raw) return session;
        }
        return error.InvalidHandle;
    }

    fn allocateQueue(self: *Runtime, owner: u32, device: handles.Handle, class: api.QueueClass, backend_token: u64) handles.Handle {
        const queue = self.registry.allocate(.queue, owner) catch unreachable;
        self.resources[queue.slot()] = .{ .handle = queue, .backend_token = backend_token, .related = device };
        self.record(.queue_created, queue, device, @intFromEnum(class));
        return queue;
    }

    fn storeBackendResource(self: *Runtime, session_handle: handles.Handle, kind: handles.Kind, backend_token: u64, size: u64, related: handles.Handle) Error!handles.Handle {
        const owner: u32 = @intCast(session_handle.slot() + 1);
        const handle = try self.registry.allocate(kind, owner);
        self.resources[handle.slot()] = .{
            .handle = handle,
            .backend_token = backend_token,
            .size = size,
            .related = related,
        };
        self.record(.resource_created, handle, session_handle, size);
        return handle;
    }

    fn record(self: *Runtime, kind: TraceKind, object: handles.Handle, related: handles.Handle, value: u64) void {
        self.trace_sequence +|= 1;
        const index: usize = @intCast((self.trace_sequence - 1) % max_trace_events);
        self.trace_events[index] = .{
            .sequence = self.trace_sequence,
            .kind = kind,
            .object = object,
            .related = related,
            .value = value,
            .backend_kind = self.adapter.description.kind,
        };
    }

    fn refreshHardwareDescription(self: *Runtime) void {
        self.hardware_tree = hardware_description.fromBackend(&self.adapter.description) catch {
            self.hardware_tree_valid = false;
            self.hardware_description_failures +|= 1;
            self.record(.hardware_description_failed, .{}, .{}, self.hardware_description_failures);
            return;
        };
        self.hardware_tree_valid = true;
        self.record(.hardware_description_updated, .{}, .{}, self.hardware_tree.fingerprint());
    }
};

fn addQueueCapabilities(set: *api.CapabilitySet, mask: u32) void {
    if (mask & api.QueueMask.graphics != 0) set.insert(.queue_graphics);
    if (mask & api.QueueMask.compute != 0) set.insert(.queue_compute);
    if (mask & api.QueueMask.transfer != 0) set.insert(.queue_transfer);
    if (mask & api.QueueMask.sparse != 0) set.insert(.queue_sparse);
}

fn requiredHandleCount(capabilities: api.CapabilitySet) usize {
    var result: usize = 1;
    if (capabilities.contains(.physical_adapter)) result += 1;
    if (capabilities.contains(.logical_device)) result += 1;
    if (capabilities.contains(.queue_graphics)) result += 1;
    if (capabilities.contains(.queue_compute)) result += 1;
    if (capabilities.contains(.queue_transfer)) result += 1;
    if (capabilities.contains(.queue_sparse)) result += 1;
    return result;
}

fn queueFor(session: Session, class: api.QueueClass) handles.Handle {
    return switch (class) {
        .graphics => session.graphics_queue,
        .compute => session.compute_queue,
        .transfer => session.transfer_queue,
        .sparse => session.sparse_queue,
    };
}

fn require(capabilities: api.CapabilitySet, capability: api.Capability) Error!void {
    if (!capabilities.contains(capability)) return error.MissingCapability;
}

const FakeBackend = struct {
    next: u64 = 100,
    created: u64 = 0,
    destroyed: u64 = 0,
    submitted: u64 = 0,

    fn createBuffer(context: ?*anyopaque, description: *const api.BufferDesc, output: *u64) backend.Error!void {
        if (description.size == 0) return error.InvalidResource;
        const self: *FakeBackend = @ptrCast(@alignCast(context.?));
        self.next += 1;
        self.created += 1;
        output.* = self.next;
    }

    fn createImage(context: ?*anyopaque, description: *const api.ImageDesc, output: *u64) backend.Error!void {
        if (description.width == 0) return error.InvalidResource;
        const self: *FakeBackend = @ptrCast(@alignCast(context.?));
        self.next += 1;
        self.created += 1;
        output.* = self.next;
    }

    fn createCommandBuffer(context: ?*anyopaque, _: api.QueueClass, output: *u64) backend.Error!void {
        const self: *FakeBackend = @ptrCast(@alignCast(context.?));
        self.next += 1;
        self.created += 1;
        output.* = self.next;
    }

    fn destroy(context: ?*anyopaque, _: u64) void {
        const self: *FakeBackend = @ptrCast(@alignCast(context.?));
        self.destroyed += 1;
    }

    fn submit(context: ?*anyopaque, _: u64, _: u64, _: u64, _: u64) backend.Error!void {
        const self: *FakeBackend = @ptrCast(@alignCast(context.?));
        self.submitted += 1;
    }
};

fn fullTestAdapter(fake: *FakeBackend) backend.Adapter {
    var description = backend.Description{
        .kind = .vulkan,
        .provided = api.CapabilitySet.from(&.{
            .backend_instance,
            .physical_adapter,
            .logical_device,
            .queue_graphics,
            .queue_transfer,
            .memory_host_visible,
            .memory_device_local,
            .guest_memory_mapping,
            .buffer,
            .image_2d,
            .sampler,
            .render_target,
            .shader_vertex,
            .shader_fragment,
            .command_buffer,
            .resource_barrier,
            .fence,
            .semaphore_binary,
        }),
        .graphics_queue_count = 1,
        .transfer_queue_count = 1,
        .buffer_alignment = 256,
        .image_alignment = 256,
        .guest_mapping_alignment = 4096,
        .host_visible_heap_bytes = 512 * 1024 * 1024,
        .device_local_heap_bytes = 4 * 1024 * 1024 * 1024,
        .maximum_buffer_bytes = 256 * 1024 * 1024,
        .maximum_image_dimension_2d = 16384,
    };
    description.setAdapterName("Fake Vulkan adapter");
    return .{
        .context = fake,
        .description = description,
        .operations = .{
            .create_buffer = FakeBackend.createBuffer,
            .create_image = FakeBackend.createImage,
            .destroy_resource = FakeBackend.destroy,
            .create_command_buffer = FakeBackend.createCommandBuffer,
            .submit = FakeBackend.submit,
        },
        .adapter_token = 0xA001,
        .device_token = 0xD001,
        .queue_tokens = .{ 0xB001, 0, 0xB003, 0 },
    };
}

test "shadow Vulkan boundary reports the first real missing capability" {
    var runtime = Runtime{};
    runtime.installVulkanBoundary(.{ .instance_native = true, .surface_native = true });
    const hardware = runtime.hardwareDescription() orelse return error.MissingHardwareDescription;
    try std.testing.expect(hardware.property("/gpu/capabilities", "backend_instance").?.value.boolean);
    try std.testing.expect(!hardware.property("/gpu/capabilities", "logical_device").?.value.boolean);
    const observation = runtime.negotiate(api.HandshakeRequest.xeniaObservation());
    try std.testing.expectEqual(api.Status.degraded, observation.statusValue());
    try std.testing.expect(observation.negotiated.contains(.backend_instance));
    try std.testing.expect(observation.negotiated.contains(.surface));

    const execution = runtime.negotiate(api.HandshakeRequest.xeniaHostExecution());
    try std.testing.expectEqual(api.Status.missing_capability, execution.statusValue());
    try std.testing.expectEqual(@as(u32, @intFromEnum(api.Capability.physical_adapter)), execution.first_missing_capability);
    try std.testing.expectEqualStrings("missing required capability: physical_adapter", execution.reasonSlice());

    const health = runtime.bridgeHealth();
    try std.testing.expectEqual(BridgeHealthStage.instance_and_surface, health.stage);
    try std.testing.expectEqual(api.Capability.physical_adapter, health.first_missing_execution_capability.?);
    try std.testing.expect(!health.readyForHostExecution());
    try std.testing.expect(health.advisory_only);
}

test "native presenter progress advances bridge health without guest provenance" {
    var runtime = Runtime{};
    runtime.installVulkanBoundary(.{
        .instance_native = true,
        .surface_native = true,
        .physical_adapter_native = true,
        .logical_device_native = true,
        .graphics_queue_native = true,
        .host_visible_memory_native = true,
        .device_local_memory_native = true,
        .guest_mapping_native = true,
        .buffer_native = true,
        .image_native = true,
        .command_buffer_native = true,
        .barriers_native = true,
        .synchronization_native = true,
        .swapchain_native = true,
        .presentation_native = true,
    });

    runtime.observeBackendProgress(true, false);
    var health = runtime.bridgeHealth();
    try std.testing.expectEqual(BridgeHealthStage.command_execution, health.stage);
    try std.testing.expect(health.authentic_submission_seen);
    try std.testing.expect(!health.authentic_presentation_seen);

    runtime.observeBackendProgress(false, true);
    health = runtime.bridgeHealth();
    try std.testing.expectEqual(BridgeHealthStage.presentation, health.stage);
    try std.testing.expect(health.authentic_presentation_seen);
}

test "Rosette handles contain backend resources and reject stale use" {
    var fake = FakeBackend{};
    var runtime = Runtime{};
    runtime.installBackend(fullTestAdapter(&fake));
    const response = runtime.negotiate(api.HandshakeRequest.xeniaHostExecution());
    try std.testing.expectEqual(api.Status.degraded, response.statusValue());
    const session = handles.Handle{ .raw = response.session };
    const buffer = try runtime.createBuffer(session, .{
        .size = 8192,
        .usage = api.BufferUsage.storage,
        .memory_class = @intFromEnum(api.MemoryClass.device_local),
        .alignment = 256,
    });
    try std.testing.expectEqual(handles.Kind.buffer, buffer.kind());
    try std.testing.expectEqual(@as(u64, 1), fake.created);
    try runtime.destroyResource(session, buffer);
    try std.testing.expectEqual(@as(u64, 1), fake.destroyed);
    try std.testing.expectError(error.DeadHandle, runtime.destroyResource(session, buffer));
}

test "guest physical mappings remain distinct from host GPU ownership" {
    var fake = FakeBackend{};
    var runtime = Runtime{};
    runtime.installBackend(fullTestAdapter(&fake));
    const response = runtime.negotiate(api.HandshakeRequest.xeniaHostExecution());
    const session = handles.Handle{ .raw = response.session };
    const buffer = try runtime.createBuffer(session, .{
        .size = 16384,
        .usage = api.BufferUsage.transfer_source,
        .memory_class = @intFromEnum(api.MemoryClass.host_visible),
        .alignment = 4096,
    });
    const mapping = try runtime.mapGuestMemory(session, .{
        .guest_physical_address = 0x1000_0000,
        .length = 4096,
        .resource = buffer.raw,
    });
    try std.testing.expectEqual(handles.Kind.guest_mapping, mapping.kind());
    try std.testing.expectEqual(buffer.raw, runtime.resources[mapping.slot()].related.raw);
    try std.testing.expectEqual(@as(u64, 0x1000_0000), runtime.resources[mapping.slot()].guest_physical_address);
}

test "command submission crosses the adapter only after negotiation" {
    var fake = FakeBackend{};
    var runtime = Runtime{};
    runtime.installBackend(fullTestAdapter(&fake));
    const response = runtime.negotiate(api.HandshakeRequest.xeniaHostExecution());
    const session = handles.Handle{ .raw = response.session };
    const queue = handles.Handle{ .raw = response.graphics_queue };
    const command = try runtime.createCommandBuffer(session, .graphics);
    try runtime.submit(session, queue, command, 3, 4);
    try std.testing.expectEqual(@as(u64, 1), fake.submitted);
    try std.testing.expectEqual(@as(u64, 1), runtime.submissions);
    try std.testing.expectEqual(TraceKind.command_submitted, runtime.latestTrace().?.kind);
}

test "closing one handshake preserves another consumer session" {
    var fake = FakeBackend{};
    var runtime = Runtime{};
    runtime.installBackend(fullTestAdapter(&fake));
    const first_response = runtime.negotiate(api.HandshakeRequest.xeniaHostExecution());
    const second_response = runtime.negotiate(api.HandshakeRequest.xeniaHostExecution());
    const first = handles.Handle{ .raw = first_response.session };
    const second = handles.Handle{ .raw = second_response.session };
    try runtime.closeSession(first);
    const buffer = try runtime.createBuffer(second, .{
        .size = 4096,
        .usage = api.BufferUsage.storage,
        .memory_class = @intFromEnum(api.MemoryClass.device_local),
    });
    try std.testing.expect(buffer.isValid());
    try std.testing.expectError(error.DeadHandle, runtime.createBuffer(first, .{
        .size = 4096,
        .usage = api.BufferUsage.storage,
        .memory_class = @intFromEnum(api.MemoryClass.device_local),
    }));
}
