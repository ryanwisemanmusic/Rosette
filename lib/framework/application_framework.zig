//! Runtime side of Rosette's callable application framework.
//!
//! The framework is intentionally a bounded ledger and command mailbox.  It
//! gives an embedding application a meaningful seam into the translated
//! process without pretending that a log line, a pointer, or a function
//! address proves that the requested behavior actually happened.

const std = @import("std");
const contract = @import("application_framework_contract");
const xenia_launch_assist_contract = @import("xenia_launch_assist_contract");
const xenia_launch_assist = @import("xenia_launch_assist.zig");
const xenia_host_gpu_callback_contract = @import("xenia_host_gpu_callback_contract");
const xenia_host_gpu_callback = @import("xenia_host_gpu_callback.zig");

pub const schema = contract;
pub const max_events: usize = 1024;
pub const max_requests: usize = 128;
pub const max_adapters: usize = 8;

const PendingRequest = struct {
    request: contract.Request = .{},
    pending: bool = false,
    status: contract.RequestStatus = .invalid,
};

const Adapter = struct {
    name_hash: u64 = 0,
    capabilities: u64 = 0,
    registrations: u64 = 0,
};

/// The bridge is called from native Xenia threads as well as from the
/// translated-process frontier.  A fixed spin lock keeps the ledger
/// allocator-free and makes a callback a coherent transaction: readers never
/// observe a half-written event or a request whose ownership has only partly
/// changed.
const SpinLock = struct {
    held: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn lock(self: *SpinLock) void {
        while (self.held.swap(true, .acquire)) std.atomic.spinLoopHint();
    }

    fn unlock(self: *SpinLock) void {
        self.held.store(false, .release);
    }
};

pub const Framework = struct {
    lock: SpinLock = .{},
    trace_mask: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    config: contract.Config = .{},
    mode: contract.Mode = .disabled,
    enabled: bool = false,
    capabilities: u64 = 0,
    trace_control_flow: bool = false,
    trace_memory: bool = false,
    trace_graphics: bool = false,
    application_id: u64 = 0,

    events: [max_events]contract.Event = [_]contract.Event{.{}} ** max_events,
    event_count: usize = 0,
    event_cursor: usize = 0,
    events_total: u64 = 0,
    events_dropped: u64 = 0,
    sequence: u64 = 0,

    requests: [max_requests]PendingRequest = [_]PendingRequest{.{}} ** max_requests,
    requests_total: u64 = 0,
    requests_queued: u64 = 0,
    requests_applied: u64 = 0,
    requests_denied: u64 = 0,
    next_request_id: u64 = 1,

    /// Events whose master/subowner pair this contract does not permit. Rosette
    /// is the only master owner of the process; a hosted subsystem
    /// substantiates its own truth beneath it.
    ownership_violations: u64 = 0,
    equivalence_checks: u64 = 0,
    equivalence_matches: u64 = 0,
    equivalence_mismatches: u64 = 0,
    last_guest_step: u64 = 0,
    last_guest_rip: u64 = 0,

    adapters: [max_adapters]Adapter = [_]Adapter{.{}} ** max_adapters,
    adapter_count: usize = 0,

    /// Xenia may ask Rosette to substantiate a narrowly defined host-side
    /// startup operation. The policy predicate is package-owned; this audit
    /// state only records the request and whether the adapter's report was
    /// coherent with the response.
    xenia_launch_assist: xenia_launch_assist.Audit = .{},

    /// Host callback installation is a separate policy from observation.
    /// Xenia's Mach-O process route enables the provider by default so the
    /// bounded compatibility seam is discoverable; the process boundary can
    /// still disable it with ROSETTE_XENIA_HOST_GPU_CALLBACK=off. The package
    /// contract remains the final authority for every mutation.
    xenia_host_gpu_callback: xenia_host_gpu_callback.Audit = .{},
    xenia_host_gpu_callback_enabled: bool = false,

    /// Configure the framework at a process boundary. Invalid enum values
    /// fail closed instead of being reinterpreted as a newer command.
    pub fn configure(self: *Framework, raw: contract.Config) bool {
        self.lock.lock();
        defer self.lock.unlock();
        if (!configIsCompatible(raw)) {
            self.disableUnlocked();
            return false;
        }
        const mode = modeFromRaw(raw.mode) orelse {
            self.disableUnlocked();
            return false;
        };
        self.config = raw;
        self.config.size = @sizeOf(contract.Config);
        self.config.schema = contract.schema_version;
        self.mode = mode;
        self.enabled = mode != .disabled;
        self.xenia_host_gpu_callback_enabled = false;
        self.capabilities = if (self.enabled) raw.capabilities else 0;
        self.trace_control_flow = raw.trace_control_flow != 0;
        self.trace_memory = raw.trace_memory != 0;
        self.trace_graphics = raw.trace_graphics != 0;
        self.trace_mask.store(
            if (self.enabled) traceMask(self.trace_control_flow, self.trace_memory, self.trace_graphics) else 0,
            .release,
        );
        self.application_id = raw.application_id;
        return true;
    }

    pub fn configureForProcess(self: *Framework, enabled: bool, trace_control_flow: bool, trace_memory: bool, trace_graphics: bool) void {
        const config = contract.Config{
            .size = @sizeOf(contract.Config),
            .schema = contract.schema_version,
            .mode = @intFromEnum(if (enabled) contract.Mode.host_control else contract.Mode.disabled),
            .capabilities = contract.capabilityBit(.observe_events) |
                contract.capabilityBit(.inspect_control_flow) |
                contract.capabilityBit(.inspect_memory) |
                contract.capabilityBit(.inspect_graphics) |
                contract.capabilityBit(.inspect_backend) |
                contract.capabilityBit(.control_scheduler) |
                contract.capabilityBit(.control_host_presenter),
            .trace_control_flow = @intFromBool(trace_control_flow),
            .trace_memory = @intFromBool(trace_memory),
            .trace_graphics = @intFromBool(trace_graphics),
        };
        _ = self.configure(config);
    }

    /// Enable the host GPU callback provider independently of trace capture.
    /// Keeping this separate from framework activation prevents a generic
    /// framework enablement from silently granting the capability to a
    /// non-Xenia process; the Mach-O route supplies the Xenia-only policy.
    pub fn setXeniaHostGpuCallbackEnabled(self: *Framework, enabled: bool) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.xenia_host_gpu_callback_enabled = enabled and self.enabled;
    }

    pub fn disable(self: *Framework) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.disableUnlocked();
    }

    fn disableUnlocked(self: *Framework) void {
        self.mode = .disabled;
        self.enabled = false;
        self.capabilities = 0;
        self.trace_control_flow = false;
        self.trace_memory = false;
        self.trace_graphics = false;
        self.xenia_host_gpu_callback_enabled = false;
        self.trace_mask.store(0, .release);
        self.config = .{
            .size = @sizeOf(contract.Config),
            .schema = contract.schema_version,
            .mode = @intFromEnum(contract.Mode.disabled),
        };
    }

    pub fn enableTraceMask(self: *Framework, mask: u64) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (!self.enabled) return;
        self.trace_control_flow = self.trace_control_flow or mask & 0x01 != 0;
        self.trace_memory = self.trace_memory or mask & 0x02 != 0;
        self.trace_graphics = self.trace_graphics or mask & 0x04 != 0;
        self.trace_mask.store(traceMask(self.trace_control_flow, self.trace_memory, self.trace_graphics), .release);
        self.config.trace_control_flow = @intFromBool(self.trace_control_flow);
        self.config.trace_memory = @intFromBool(self.trace_memory);
        self.config.trace_graphics = @intFromBool(self.trace_graphics);
    }

    pub fn clearTraceFlags(self: *Framework) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.trace_control_flow = false;
        self.trace_memory = false;
        self.trace_graphics = false;
        self.trace_mask.store(0, .release);
        self.config.trace_control_flow = 0;
        self.config.trace_memory = 0;
        self.config.trace_graphics = 0;
    }

    pub fn isEnabled(self: *const Framework) bool {
        const mutable = @constCast(self);
        mutable.lock.lock();
        defer mutable.lock.unlock();
        return self.enabled;
    }

    pub fn currentSequence(self: *const Framework) u64 {
        const mutable = @constCast(self);
        mutable.lock.lock();
        defer mutable.lock.unlock();
        return self.sequence;
    }

    pub fn configuration(self: *const Framework) contract.Config {
        const mutable = @constCast(self);
        mutable.lock.lock();
        defer mutable.lock.unlock();
        return self.config;
    }

    /// Cheap lock-free gates for the instruction path.  The full observer
    /// methods still take the ledger lock, but a process can decide whether
    /// to enter that path without serializing every ordinary instruction.
    pub fn controlFlowTracingEnabled(self: *const Framework) bool {
        return self.trace_mask.load(.acquire) & 0x01 != 0;
    }

    pub fn memoryTracingEnabled(self: *const Framework) bool {
        return self.trace_mask.load(.acquire) & 0x02 != 0;
    }

    pub fn graphicsTracingEnabled(self: *const Framework) bool {
        return self.trace_mask.load(.acquire) & 0x04 != 0;
    }

    pub fn registerApplication(self: *Framework, name: []const u8, application_id: u64) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.application_id = if (application_id != 0) application_id else hashName(name);
        if (!self.enabled) return;
        self.emitNamedUnlocked(.{
            .kind = @intFromEnum(contract.EventKind.process),
            .truth = @intFromEnum(contract.Truth.observed),
            .owner = @intFromEnum(contract.attribute(contract.Owner.rosette).owner),
            .subowner = @intFromEnum(contract.attribute(contract.Owner.rosette).subowner),
            .domain = @intFromEnum(contract.Domain.process),
            .value_kind = @intFromEnum(contract.ValueKind.bytes_hash),
            .actual = self.application_id,
        }, name, "application registered");
    }

    pub fn registerAdapter(self: *Framework, name: []const u8, capabilities: u64) bool {
        self.lock.lock();
        defer self.lock.unlock();
        const name_hash = hashName(name);
        for (self.adapters[0..self.adapter_count]) |*adapter| {
            if (adapter.name_hash == name_hash) {
                adapter.capabilities = capabilities;
                adapter.registrations +|= 1;
                return true;
            }
        }
        if (self.adapter_count >= max_adapters) return false;
        self.adapters[self.adapter_count] = .{
            .name_hash = name_hash,
            .capabilities = capabilities,
            .registrations = 1,
        };
        self.adapter_count += 1;
        if (self.enabled) {
            self.emitNamedUnlocked(.{
                .kind = @intFromEnum(contract.EventKind.state_observation),
                .truth = @intFromEnum(contract.Truth.observed),
                .owner = @intFromEnum(contract.attribute(contract.Owner.external_adapter).owner),
                .subowner = @intFromEnum(contract.attribute(contract.Owner.external_adapter).subowner),
                .domain = @intFromEnum(contract.Domain.framework),
                .value_kind = @intFromEnum(contract.ValueKind.bytes_hash),
                .actual = capabilities,
            }, name, "adapter capabilities registered");
        }
        return true;
    }

    /// Add a value event to the bounded ring.  This is the common path for
    /// Xenia-facing adapters and for Rosette's own ledgers.
    pub fn emit(self: *Framework, event: contract.Event) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.emitUnlocked(event);
    }

    fn emitUnlocked(self: *Framework, event: contract.Event) void {
        if (!self.enabled) return;
        var stored = event;
        // Checked at the one place every event passes through rather than at
        // each of the ten that construct one. An event with two master owners
        // is how two accounts of the same fact drift apart while neither looks
        // wrong on its own, so it is counted rather than corrected: correcting
        // it here would hide the caller that produced it.
        if (!contract.ownershipIsWellFormed(
            @enumFromInt(stored.owner),
            @enumFromInt(stored.subowner),
        )) self.ownership_violations +|= 1;
        stored.size = @sizeOf(contract.Event);
        stored.schema = contract.schema_version;
        self.sequence +|= 1;
        stored.sequence = self.sequence;
        if (stored.guest_step != 0) self.last_guest_step = stored.guest_step;
        if (stored.guest_rip != 0) self.last_guest_rip = stored.guest_rip;

        const index = if (self.event_count < max_events) blk: {
            const result = self.event_count;
            self.event_count += 1;
            break :blk result;
        } else blk: {
            const result = self.event_cursor;
            self.event_cursor = (self.event_cursor + 1) % max_events;
            self.events_dropped +|= 1;
            break :blk result;
        };
        self.events[index] = stored;
        self.events_total +|= 1;
    }

    pub fn emitNamed(self: *Framework, event: contract.Event, name: []const u8, detail: []const u8) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.emitNamedUnlocked(event, name, detail);
    }

    fn emitNamedUnlocked(self: *Framework, event: contract.Event, name: []const u8, detail: []const u8) void {
        var named = event;
        named.name_hash = hashName(name);
        copyBytes(named.name.len, &named.name, name);
        copyBytes(named.detail.len, &named.detail, detail);
        self.emitUnlocked(named);
    }

    pub fn observeFunctionEnter(self: *Framework, owner: contract.Owner, domain: contract.Domain, name: []const u8, guest_step: u64, guest_rip: u64, thread_id: u64, host_pc: u64) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (!self.trace_control_flow) return;
        self.emitNamedUnlocked(.{
            .kind = @intFromEnum(contract.EventKind.function_enter),
            .truth = @intFromEnum(contract.Truth.observed),
            .owner = @intFromEnum(contract.attribute(owner).owner),
            .subowner = @intFromEnum(contract.attribute(owner).subowner),
            .domain = @intFromEnum(domain),
            .value_kind = @intFromEnum(contract.ValueKind.address),
            .guest_step = guest_step,
            .thread_id = thread_id,
            .guest_rip = guest_rip,
            .host_pc = host_pc,
        }, name, "function boundary entered");
    }

    pub fn observeFunctionExit(self: *Framework, owner: contract.Owner, domain: contract.Domain, name: []const u8, guest_step: u64, guest_rip: u64, thread_id: u64, result: u64) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (!self.trace_control_flow) return;
        self.emitNamedUnlocked(.{
            .kind = @intFromEnum(contract.EventKind.function_exit),
            .truth = @intFromEnum(contract.Truth.observed),
            .owner = @intFromEnum(contract.attribute(owner).owner),
            .subowner = @intFromEnum(contract.attribute(owner).subowner),
            .domain = @intFromEnum(domain),
            .value_kind = @intFromEnum(contract.ValueKind.scalar),
            .guest_step = guest_step,
            .thread_id = thread_id,
            .guest_rip = guest_rip,
            .actual = result,
        }, name, "function boundary exited");
    }

    pub fn observeControlTransfer(self: *Framework, owner: contract.Owner, source: u64, target: u64, guest_step: u64, thread_id: u64, taken: bool, name: []const u8) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (!self.trace_control_flow) return;
        self.emitNamedUnlocked(.{
            .kind = @intFromEnum(contract.EventKind.control_transfer),
            .truth = @intFromEnum(contract.Truth.observed),
            .owner = @intFromEnum(contract.attribute(owner).owner),
            .subowner = @intFromEnum(contract.attribute(owner).subowner),
            .domain = @intFromEnum(contract.Domain.control_flow),
            .value_kind = @intFromEnum(contract.ValueKind.address),
            .guest_step = guest_step,
            .thread_id = thread_id,
            .guest_rip = source,
            .subject = target,
            .actual = @intFromBool(taken),
        }, name, "control transfer observed");
    }

    pub fn observeValue(self: *Framework, owner: contract.Owner, domain: contract.Domain, subject: u64, actual: u64, guest_step: u64, guest_rip: u64, name: []const u8, detail: []const u8) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (!self.enabled) return;
        if (domain == .memory and !self.trace_memory) return;
        if ((domain == .pm4 or domain == .vd_swap or domain == .graphics_backend or domain == .presenter) and !self.trace_graphics) return;
        self.emitNamedUnlocked(.{
            .kind = @intFromEnum(contract.EventKind.state_observation),
            .truth = @intFromEnum(contract.Truth.observed),
            .owner = @intFromEnum(contract.attribute(owner).owner),
            .subowner = @intFromEnum(contract.attribute(owner).subowner),
            .domain = @intFromEnum(domain),
            .value_kind = @intFromEnum(contract.ValueKind.scalar),
            .guest_step = guest_step,
            .guest_rip = guest_rip,
            .subject = subject,
            .actual = actual,
        }, name, detail);
    }

    /// Compare what the guest/native boundary expected with what the other
    /// side actually supplied.  A matching call event never closes this check;
    /// only the value comparison does.
    pub fn compareValue(self: *Framework, owner: contract.Owner, domain: contract.Domain, subject: u64, expected: u64, actual: u64, mask: u64, guest_step: u64, guest_rip: u64, name: []const u8) contract.Equivalence {
        self.lock.lock();
        defer self.lock.unlock();
        const comparison_mask = if (mask == 0) std.math.maxInt(u64) else mask;
        const result: contract.Equivalence = if ((expected & comparison_mask) == (actual & comparison_mask))
            if (comparison_mask == std.math.maxInt(u64)) .match else .masked_match
        else
            .mismatch;
        self.equivalence_checks +|= 1;
        if (result.healthy()) self.equivalence_matches +|= 1 else self.equivalence_mismatches +|= 1;
        if (self.enabled) {
            self.emitNamedUnlocked(.{
                .kind = @intFromEnum(contract.EventKind.equivalence),
                .truth = @intFromEnum(contract.Truth.observed),
                .owner = @intFromEnum(contract.attribute(owner).owner),
                .subowner = @intFromEnum(contract.attribute(owner).subowner),
                .domain = @intFromEnum(domain),
                .value_kind = @intFromEnum(contract.ValueKind.scalar),
                .equivalence = @intFromEnum(result),
                .guest_step = guest_step,
                .guest_rip = guest_rip,
                .subject = subject,
                .expected = expected,
                .actual = actual,
                .mask = mask,
            }, name, if (result.healthy()) "boundary value matched" else "boundary value mismatch");
        }
        return result;
    }

    pub fn observeController(self: *Framework, phase: u8, action: u8, blocker: u8, guest_step: u64, detail: []const u8) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (!self.enabled) return;
        self.emitNamedUnlocked(.{
            .kind = @intFromEnum(contract.EventKind.scheduler),
            .truth = @intFromEnum(contract.Truth.observed),
            .owner = @intFromEnum(contract.attribute(contract.Owner.rosette).owner),
            .subowner = @intFromEnum(contract.attribute(contract.Owner.rosette).subowner),
            .domain = @intFromEnum(contract.Domain.scheduler),
            .value_kind = @intFromEnum(contract.ValueKind.enum_value),
            .guest_step = guest_step,
            .subject = phase,
            .actual = action,
            .auxiliary = blocker,
        }, "application-controller", detail);
    }

    pub fn queryXeniaLaunchAssist(
        self: *Framework,
        assist_request: xenia_launch_assist_contract.Request,
    ) xenia_launch_assist_contract.Response {
        self.lock.lock();
        defer self.lock.unlock();

        const host_control_enabled = self.enabled and
            (self.mode == .host_control or self.mode == .experimental_control);
        const response = self.xenia_launch_assist.query(assist_request, host_control_enabled);
        if (self.enabled) {
            const attribution = contract.attribute(.xenia_kernel);
            self.emitNamedUnlocked(.{
                .kind = @intFromEnum(contract.EventKind.state_observation),
                .truth = @intFromEnum(if (response.decision == @intFromEnum(xenia_launch_assist_contract.Decision.allow))
                    contract.Truth.requested
                else
                    contract.Truth.rejected),
                .owner = @intFromEnum(attribution.owner),
                .subowner = @intFromEnum(attribution.subowner),
                .domain = @intFromEnum(contract.Domain.kernel),
                .value_kind = @intFromEnum(contract.ValueKind.enum_value),
                .guest_step = assist_request.guest_step,
                .subject = assist_request.title_id,
                .expected = response.actions,
                .actual = response.decision,
                .mask = response.proof_mask,
                .auxiliary = response.reason,
            }, "xenia-launch-assist", "Rosette launch-assist policy query");
        }
        return response;
    }

    pub fn reportXeniaLaunchAssist(
        self: *Framework,
        assist_request: xenia_launch_assist_contract.Request,
        response: xenia_launch_assist_contract.Response,
        applied_actions: u32,
        status: xenia_launch_assist_contract.ApplyStatus,
    ) bool {
        self.lock.lock();
        defer self.lock.unlock();

        const coherent = self.xenia_launch_assist.report(
            assist_request,
            response,
            applied_actions,
            status,
        );
        if (self.enabled) {
            const attribution = contract.attribute(.xenia_kernel);
            self.emitNamedUnlocked(.{
                .kind = @intFromEnum(contract.EventKind.state_observation),
                .truth = @intFromEnum(if (coherent and status == .applied)
                    contract.Truth.applied
                else if (coherent)
                    contract.Truth.observed
                else
                    contract.Truth.rejected),
                .owner = @intFromEnum(attribution.owner),
                .subowner = @intFromEnum(attribution.subowner),
                .domain = @intFromEnum(contract.Domain.kernel),
                .value_kind = @intFromEnum(contract.ValueKind.enum_value),
                .guest_step = assist_request.guest_step,
                .subject = assist_request.title_id,
                .expected = response.actions,
                .actual = applied_actions,
                .mask = response.proof_mask,
                .auxiliary = @as(u64, @intFromEnum(status)) |
                    (@as(u64, @intFromBool(coherent)) << 8),
            }, "xenia-launch-assist", "Xenia launch-assist application report");
        }
        return coherent;
    }

    pub fn queryXeniaHostGpuCallback(
        self: *Framework,
        callback_request: xenia_host_gpu_callback_contract.Request,
    ) xenia_host_gpu_callback_contract.Response {
        self.lock.lock();
        defer self.lock.unlock();

        const host_control_enabled = self.enabled and
            (self.mode == .host_control or self.mode == .experimental_control);
        const response = self.xenia_host_gpu_callback.query(
            callback_request,
            host_control_enabled,
            self.xenia_host_gpu_callback_enabled,
        );
        if (self.enabled) {
            const attribution = contract.attribute(.xenia_gpu);
            self.emitNamedUnlocked(.{
                .kind = @intFromEnum(contract.EventKind.state_observation),
                .truth = @intFromEnum(if (response.decision == @intFromEnum(xenia_host_gpu_callback_contract.Decision.allow))
                    contract.Truth.requested
                else
                    contract.Truth.rejected),
                .owner = @intFromEnum(attribution.owner),
                .subowner = @intFromEnum(attribution.subowner),
                .domain = @intFromEnum(contract.Domain.graphics_backend),
                .value_kind = @intFromEnum(contract.ValueKind.enum_value),
                .guest_step = callback_request.guest_step,
                .guest_rip = callback_request.entry_point,
                .subject = callback_request.title_id,
                .expected = response.actions,
                .actual = response.decision,
                .mask = response.proof_mask,
                .auxiliary = response.reason,
            }, "xenia-host-gpu-callback", "Rosette host GPU callback policy query");
        }
        return response;
    }

    pub fn reportXeniaHostGpuCallback(
        self: *Framework,
        callback_request: xenia_host_gpu_callback_contract.Request,
        response: xenia_host_gpu_callback_contract.Response,
        applied_actions: u32,
        status: xenia_host_gpu_callback_contract.ApplyStatus,
    ) bool {
        self.lock.lock();
        defer self.lock.unlock();

        const coherent = self.xenia_host_gpu_callback.report(
            callback_request,
            response,
            applied_actions,
            status,
        );
        if (self.enabled) {
            const attribution = contract.attribute(.xenia_gpu);
            self.emitNamedUnlocked(.{
                .kind = @intFromEnum(contract.EventKind.state_observation),
                .truth = @intFromEnum(if (coherent and status == .applied)
                    contract.Truth.applied
                else if (coherent)
                    contract.Truth.observed
                else
                    contract.Truth.rejected),
                .owner = @intFromEnum(attribution.owner),
                .subowner = @intFromEnum(attribution.subowner),
                .domain = @intFromEnum(contract.Domain.graphics_backend),
                .value_kind = @intFromEnum(contract.ValueKind.enum_value),
                .guest_step = callback_request.guest_step,
                .guest_rip = callback_request.entry_point,
                .subject = callback_request.title_id,
                .expected = response.actions,
                .actual = applied_actions,
                .mask = response.proof_mask,
                .auxiliary = @as(u64, @intFromEnum(status)) |
                    (@as(u64, @intFromBool(coherent)) << 8),
            }, "xenia-host-gpu-callback", "Xenia host GPU callback application report");
        }
        return coherent;
    }

    pub fn xeniaHostGpuCallbackSnapshot(self: *const Framework) xenia_host_gpu_callback.Snapshot {
        const mutable = @constCast(self);
        mutable.lock.lock();
        defer mutable.lock.unlock();
        return self.xenia_host_gpu_callback.snapshot();
    }

    pub fn xeniaHostGpuCallbackEnabled(self: *const Framework) bool {
        const mutable = @constCast(self);
        mutable.lock.lock();
        defer mutable.lock.unlock();
        return self.xenia_host_gpu_callback_enabled;
    }

    pub fn request(self: *Framework, raw: contract.Request) contract.RequestResult {
        self.lock.lock();
        defer self.lock.unlock();
        self.requests_total +|= 1;
        var result = contract.RequestResult{
            .size = @sizeOf(contract.RequestResult),
            .schema = contract.schema_version,
            .request_id = raw.request_id,
        };
        const command = commandFromRaw(raw.command) orelse {
            result.status = @intFromEnum(contract.RequestStatus.invalid);
            self.requests_denied +|= 1;
            return result;
        };
        const request_id = if (raw.request_id != 0) raw.request_id else self.allocateRequestId();
        result.request_id = request_id;
        if (!self.enabled) {
            result.status = @intFromEnum(contract.RequestStatus.disabled);
            self.requests_denied +|= 1;
            return result;
        }
        if (command.isGuestMutation() and self.mode != .experimental_control) {
            result.status = @intFromEnum(contract.RequestStatus.denied);
            result.reason_code = 0x4755_4553_545f_4d55; // GUEST_MU
            self.requests_denied +|= 1;
            self.recordRequestEventUnlocked(raw, command, result.status);
            return result;
        }
        if (command.requiredCapability()) |required| {
            if (self.capabilities & contract.capabilityBit(required) == 0) {
                result.status = @intFromEnum(contract.RequestStatus.denied);
                result.reason_code = @intFromEnum(required);
                self.requests_denied +|= 1;
                self.recordRequestEventUnlocked(raw, command, result.status);
                return result;
            }
        }
        const index = self.findFreeRequest() orelse {
            result.status = @intFromEnum(contract.RequestStatus.not_ready);
            result.reason_code = 0x4d41_494c_424f_5846; // MAILBOXF
            self.requests_denied +|= 1;
            self.recordRequestEventUnlocked(raw, command, result.status);
            return result;
        };
        var queued = raw;
        queued.size = @sizeOf(contract.Request);
        queued.schema = contract.schema_version;
        queued.request_id = request_id;
        self.requests[index] = .{ .request = queued, .pending = true, .status = .queued };
        self.requests_queued +|= 1;
        result.status = @intFromEnum(contract.RequestStatus.queued);
        self.recordRequestEventUnlocked(queued, command, result.status);
        return result;
    }

    pub fn takePending(self: *Framework, out: *contract.Request) bool {
        self.lock.lock();
        defer self.lock.unlock();
        for (&self.requests) |*entry| {
            if (!entry.pending) continue;
            entry.pending = false;
            self.requests_queued -|= 1;
            out.* = entry.request;
            return true;
        }
        return false;
    }

    pub fn complete(self: *Framework, request_id: u64, status: contract.RequestStatus, reason_code: u64) bool {
        self.lock.lock();
        defer self.lock.unlock();
        for (&self.requests) |*entry| {
            if (entry.request.request_id != request_id or entry.status != .queued) continue;
            entry.status = status;
            if (status == .applied) self.requests_applied +|= 1;
            if (status == .denied or status == .unsupported or status == .not_ready) self.requests_denied +|= 1;
            if (self.enabled) {
                self.emitUnlocked(.{
                    .kind = @intFromEnum(contract.EventKind.command_result),
                    .truth = @intFromEnum(if (status == .applied) contract.Truth.applied else contract.Truth.rejected),
                    .owner = @intFromEnum(contract.attribute(contract.Owner.rosette).owner),
                    .subowner = @intFromEnum(contract.attribute(contract.Owner.rosette).subowner),
                    .domain = @intFromEnum(contract.Domain.framework),
                    .value_kind = @intFromEnum(contract.ValueKind.enum_value),
                    .actual = @intFromEnum(status),
                    .auxiliary = reason_code,
                    .subject = request_id,
                });
            }
            return true;
        }
        return false;
    }

    pub fn readEvent(self: *const Framework, ordinal: usize, out: *contract.Event) bool {
        const mutable = @constCast(self);
        mutable.lock.lock();
        defer mutable.lock.unlock();
        if (ordinal >= self.event_count) return false;
        const index = if (self.event_count < max_events)
            ordinal
        else
            (self.event_cursor + ordinal) % max_events;
        out.* = self.events[index];
        return true;
    }

    /// Events recorded with an ownership pair the contract does not permit.
    pub fn ownershipViolations(self: *const Framework) u64 {
        return self.ownership_violations;
    }

    pub fn snapshot(self: *const Framework) contract.Snapshot {
        const mutable = @constCast(self);
        mutable.lock.lock();
        defer mutable.lock.unlock();
        return .{
            .size = @sizeOf(contract.Snapshot),
            .schema = contract.schema_version,
            .mode = @intFromEnum(self.mode),
            .sequence = self.sequence,
            .events_retained = self.event_count,
            .events_total = self.events_total,
            .events_dropped = self.events_dropped,
            .requests_total = self.requests_total,
            .requests_queued = self.requests_queued,
            .requests_applied = self.requests_applied,
            .requests_denied = self.requests_denied,
            .equivalence_checks = self.equivalence_checks,
            .equivalence_matches = self.equivalence_matches,
            .equivalence_mismatches = self.equivalence_mismatches,
            .last_guest_step = self.last_guest_step,
            .last_guest_rip = self.last_guest_rip,
            .application_id = self.application_id,
        };
    }

    fn findFreeRequest(self: *const Framework) ?usize {
        for (self.requests, 0..) |entry, index| {
            if (entry.request.request_id == 0 or (!entry.pending and entry.status != .queued)) return index;
        }
        return null;
    }

    fn allocateRequestId(self: *Framework) u64 {
        const result = if (self.next_request_id == 0) 1 else self.next_request_id;
        self.next_request_id +|= 1;
        return result;
    }

    fn recordRequestEventUnlocked(self: *Framework, request_record: contract.Request, command: contract.Command, status_raw: u8) void {
        if (!self.enabled) return;
        self.emitUnlocked(.{
            .kind = @intFromEnum(contract.EventKind.command_request),
            .truth = @intFromEnum(if (status_raw == @intFromEnum(contract.RequestStatus.queued)) contract.Truth.requested else contract.Truth.rejected),
            .owner = @intFromEnum(contract.attribute(contract.Owner.external_adapter).owner),
            .subowner = @intFromEnum(contract.attribute(contract.Owner.external_adapter).subowner),
            .domain = @intFromEnum(if (command.isGuestMutation()) contract.Domain.kernel else contract.Domain.framework),
            .value_kind = @intFromEnum(contract.ValueKind.enum_value),
            .guest_step = request_record.guest_step,
            .subject = request_record.request_id,
            .actual = @intFromEnum(command),
            .auxiliary = status_raw,
            .name_hash = request_record.name_hash,
        });
    }
};

pub var default_framework: Framework = .{};
var active_framework: ?*Framework = null;

pub fn defaultHandle() *Framework {
    return active_framework orelse &default_framework;
}

/// Bind the process-owned framework to the exported ABI while a translated
/// application is running.  The fallback global remains available for tools
/// that use the API before a process has been loaded.
pub fn activateDefault(framework: *Framework) void {
    active_framework = framework;
}

pub fn deactivateDefault(framework: *Framework) void {
    if (active_framework) |active| {
        if (active == framework) active_framework = null;
    }
}

pub fn hashName(name: []const u8) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (name) |byte| {
        hash ^= byte;
        hash *%= 0x0000_0100_0000_01b3;
    }
    return hash;
}

fn copyBytes(comptime destination_size: usize, destination: *[destination_size]u8, source: []const u8) void {
    const count = @min(destination.len, source.len);
    @memset(destination[0..], 0);
    for (source[0..count], 0..) |byte, index| destination[index] = byte;
}

fn traceMask(control_flow: bool, memory: bool, graphics: bool) u8 {
    return @as(u8, @intFromBool(control_flow)) |
        (@as(u8, @intFromBool(memory)) << 1) |
        (@as(u8, @intFromBool(graphics)) << 2);
}

fn modeFromRaw(raw: u8) ?contract.Mode {
    if (raw > @intFromEnum(contract.Mode.experimental_control)) return null;
    return @enumFromInt(raw);
}

fn commandFromRaw(raw: u8) ?contract.Command {
    if (raw > @intFromEnum(contract.Command.write_host_state)) return null;
    return @enumFromInt(raw);
}

fn configIsCompatible(raw: contract.Config) bool {
    const schema_compatible = raw.schema == 0 or raw.schema == contract.schema_version;
    const size_compatible = raw.size == 0 or raw.size >= @sizeOf(contract.Config);
    return schema_compatible and size_compatible;
}

test "framework is fail-closed and records actual equivalence" {
    var framework = Framework{};
    framework.configureForProcess(true, true, true, true);
    const request = framework.request(.{
        .command = @intFromEnum(contract.Command.write_guest_memory),
        .argument0 = 0x1000,
    });
    try std.testing.expectEqual(contract.RequestStatus.denied, @as(contract.RequestStatus, @enumFromInt(request.status)));
    const result = framework.compareValue(.xenia_gpu, .vd_swap, 7, 11, 12, 0, 4, 0x1234, "frontbuffer");
    try std.testing.expectEqual(contract.Equivalence.mismatch, result);
    try std.testing.expectEqual(@as(u64, 1), framework.equivalence_mismatches);
    try std.testing.expect(framework.snapshot().events_total >= 1);
}

test "host request queues and can be completed" {
    var framework = Framework{};
    framework.configureForProcess(true, false, false, false);
    const result = framework.request(.{
        .command = @intFromEnum(contract.Command.refresh_output),
        .request_id = 77,
    });
    try std.testing.expectEqual(contract.RequestStatus.queued, @as(contract.RequestStatus, @enumFromInt(result.status)));
    var pending: contract.Request = .{};
    try std.testing.expect(framework.takePending(&pending));
    try std.testing.expectEqual(@as(u64, 77), pending.request_id);
    try std.testing.expect(framework.complete(77, .applied, 0));
    try std.testing.expectEqual(@as(u64, 1), framework.requests_applied);
}

test "trace gates publish dynamic requests without locking the instruction path" {
    var framework = Framework{};
    framework.configureForProcess(true, false, false, false);
    try std.testing.expect(!framework.controlFlowTracingEnabled());
    framework.enableTraceMask(0x07);
    try std.testing.expect(framework.controlFlowTracingEnabled());
    try std.testing.expect(framework.memoryTracingEnabled());
    try std.testing.expect(framework.graphicsTracingEnabled());
    framework.clearTraceFlags();
    try std.testing.expect(!framework.controlFlowTracingEnabled());
    try std.testing.expect(!framework.memoryTracingEnabled());
    try std.testing.expect(!framework.graphicsTracingEnabled());
}

test "incompatible configuration fails closed without retaining stale policy" {
    var framework = Framework{};
    framework.configureForProcess(true, true, true, true);
    var config = framework.configuration();
    config.schema = contract.schema_version + 1;
    try std.testing.expect(!framework.configure(config));
    try std.testing.expect(!framework.isEnabled());
    try std.testing.expectEqual(@intFromEnum(contract.Mode.disabled), framework.configuration().mode);
    try std.testing.expectEqual(@as(u64, 0), framework.configuration().capabilities);
    try std.testing.expect(!framework.controlFlowTracingEnabled());
}

test "bounded event ring reports drops rather than losing the fact" {
    var framework = Framework{};
    framework.configureForProcess(true, false, false, false);
    var i: usize = 0;
    while (i < max_events + 3) : (i += 1) {
        framework.emit(.{ .kind = @intFromEnum(contract.EventKind.state_observation), .actual = i });
    }
    try std.testing.expectEqual(@as(usize, max_events), framework.event_count);
    try std.testing.expectEqual(@as(u64, 3), framework.events_dropped);
    var event: contract.Event = .{};
    try std.testing.expect(framework.readEvent(0, &event));
    try std.testing.expectEqual(@as(u64, 3), event.actual);
}

test "every event the framework emits carries one master owner" {
    var framework = Framework{};
    framework.configureForProcess(true, true, true, true);
    framework.observeValue(.xenia_gpu, .pm4, 0x10, 0x20, 100, 0x200, "draw", "detail");
    framework.observeValue(.guest, .vd_swap, 0x11, 0x21, 101, 0x201, "swap", "detail");
    _ = framework.compareValue(.xenia_presenter, .presenter, 1, 2, 2, 0, 102, 0x202, "present");
    try std.testing.expectEqual(@as(u64, 0), framework.ownershipViolations());

    var index: usize = 0;
    var seen: usize = 0;
    while (index < framework.event_count) : (index += 1) {
        var event: contract.Event = .{};
        if (!framework.readEvent(index, &event)) continue;
        seen += 1;
        const owner: contract.Owner = @enumFromInt(event.owner);
        try std.testing.expect(owner.isMaster());
        try std.testing.expect(contract.ownershipIsWellFormed(owner, @enumFromInt(event.subowner)));
    }
    try std.testing.expect(seen != 0);
}

test "a hosted subsystem appears as the subowner, never as the owner" {
    var framework = Framework{};
    framework.configureForProcess(true, true, true, true);
    framework.observeValue(.xenia_gpu, .pm4, 0x10, 0x20, 100, 0x200, "draw", "detail");
    var event: contract.Event = .{};
    try std.testing.expect(framework.readEvent(framework.event_count - 1, &event));
    try std.testing.expectEqual(@intFromEnum(contract.Owner.rosette), event.owner);
    try std.testing.expectEqual(@intFromEnum(contract.Owner.xenia_gpu), event.subowner);
}

test "a malformed pair is counted rather than corrected" {
    var framework = Framework{};
    framework.configureForProcess(true, true, true, true);
    framework.emitUnlocked(.{
        .owner = @intFromEnum(contract.Owner.xenia_gpu),
        .subowner = @intFromEnum(contract.Owner.guest),
    });
    try std.testing.expectEqual(@as(u64, 1), framework.ownershipViolations());
}
