//! Canonical Xbox guest time and dispatcher-facing wait semantics.
//!
//! Xenia and Rosette previously had independently advancing clocks and
//! independently modelled waits. This module owns the guest units and the
//! typed transitions shared by both adapters. Host time may drive an explicit
//! service event, but a diagnostic observation can never manufacture guest
//! time or a wake.

const std = @import("std");

pub const xbox_ticks_per_second: u64 = 50_000_000;
pub const filetime_units_per_second: u64 = 10_000_000;
pub const nanoseconds_per_second: u64 = 1_000_000_000;
pub const xbox_ticks_per_filetime: u64 = xbox_ticks_per_second / filetime_units_per_second;

pub const AdvancementSource = enum(u8) {
    guest_execution,
    guest_timer,
    host_wait_service,
    diagnostic_probe,

    pub fn label(self: AdvancementSource) []const u8 {
        return switch (self) {
            .guest_execution => "guest-execution",
            .guest_timer => "guest-timer",
            .host_wait_service => "host-wait-service",
            .diagnostic_probe => "diagnostic-probe",
        };
    }

    pub fn mayAdvanceGuest(self: AdvancementSource) bool {
        return self != .diagnostic_probe;
    }
};

pub const Scalar = struct {
    /// Guest ticks produced per host nanosecond, represented as a rational
    /// multiplier. One-to-one Xbox wall-time is 1/20, because a guest tick is
    /// twenty nanoseconds.
    numerator: u64 = 1,
    denominator: u64 = 20,

    pub fn valid(self: Scalar) bool {
        return self.numerator != 0 and self.denominator != 0;
    }

    pub fn guestTicksForHostNanoseconds(self: Scalar, host_ns: u64) u64 {
        if (!self.valid()) return 0;
        const value = @as(u128, host_ns) * self.numerator;
        return saturatingU64(value / self.denominator);
    }
};

pub const Clock = struct {
    ticks: u64 = 0,
    /// FILETIME at guest tick zero. Keeping the epoch explicit makes absolute
    /// timeout conversion testable and prevents adapters from inventing one.
    filetime_epoch: u64 = 0,
    scalar: Scalar = .{},
    advancement_events: u64 = 0,
    rejected_advances: u64 = 0,
    by_source: [source_count]u64 = [_]u64{0} ** source_count,

    pub fn nowTicks(self: Clock) u64 {
        return self.ticks;
    }

    pub fn nowFileTime(self: Clock) u64 {
        return self.filetime_epoch +| ticksToFileTime(self.ticks);
    }

    pub fn advance(self: *Clock, delta_ticks: u64, source: AdvancementSource) bool {
        if (!source.mayAdvanceGuest()) {
            self.rejected_advances +|= 1;
            return false;
        }
        self.ticks +|= delta_ticks;
        self.advancement_events +|= 1;
        self.by_source[@intFromEnum(source)] +|= 1;
        return true;
    }

    pub fn advanceHost(self: *Clock, host_ns: u64, source: AdvancementSource) bool {
        return self.advance(self.scalar.guestTicksForHostNanoseconds(host_ns), source);
    }

    pub fn advanceTo(self: *Clock, target_ticks: u64, source: AdvancementSource) bool {
        if (target_ticks <= self.ticks) return true;
        return self.advance(target_ticks - self.ticks, source);
    }
};

pub const source_count: usize = @typeInfo(AdvancementSource).@"enum".fields.len;

pub fn ticksToNanoseconds(ticks: u64) u64 {
    return saturatingU64(@as(u128, ticks) * nanoseconds_per_second / xbox_ticks_per_second);
}

pub fn ticksToFileTime(ticks: u64) u64 {
    return saturatingU64(@as(u128, ticks) * filetime_units_per_second / xbox_ticks_per_second);
}

pub fn fileTimeToTicks(filetime: u64) u64 {
    return saturatingU64(@as(u128, filetime) * xbox_ticks_per_second / filetime_units_per_second);
}

fn saturatingU64(value: u128) u64 {
    return if (value > std.math.maxInt(u64)) std.math.maxInt(u64) else @intCast(value);
}

pub const TimeoutInput = union(enum) {
    infinite,
    value: i64,
};

pub const TimeoutKind = enum(u8) {
    infinite,
    zero_poll,
    relative_100ns,
    absolute_filetime,
    invalid,

    pub fn label(self: TimeoutKind) []const u8 {
        return switch (self) {
            .infinite => "infinite",
            .zero_poll => "zero-poll",
            .relative_100ns => "relative-100ns",
            .absolute_filetime => "absolute-filetime",
            .invalid => "invalid",
        };
    }
};

pub const Deadline = struct {
    kind: TimeoutKind = .invalid,
    original: TimeoutInput = .infinite,
    entered_ticks: u64 = 0,
    deadline_ticks: ?u64 = null,

    pub fn finite(self: Deadline) bool {
        return self.deadline_ticks != null;
    }
};

pub fn decodeTimeout(clock: Clock, input: TimeoutInput) Deadline {
    switch (input) {
        .infinite => return .{ .kind = .infinite, .original = input, .entered_ticks = clock.ticks },
        .value => |raw| {
            if (raw == 0) {
                return .{ .kind = .zero_poll, .original = input, .entered_ticks = clock.ticks, .deadline_ticks = clock.ticks };
            }
            if (raw < 0) {
                const magnitude = @as(u64, @intCast(-(raw + 1))) + 1;
                const delta = saturatingU64(@as(u128, magnitude) * xbox_ticks_per_filetime);
                return .{ .kind = .relative_100ns, .original = input, .entered_ticks = clock.ticks, .deadline_ticks = clock.ticks +| delta };
            }
            const absolute_filetime: u64 = @intCast(raw);
            const absolute_guest_ticks = fileTimeToTicks(absolute_filetime -| clock.filetime_epoch);
            return .{ .kind = .absolute_filetime, .original = input, .entered_ticks = clock.ticks, .deadline_ticks = absolute_guest_ticks };
        },
    }
}

pub const WaitState = enum(u8) {
    pending,
    ready_on_entry,
    signaled,
    timeout,
    user_apc,
    alerted,
    abandoned,
    failed,
    cancelled,
    non_waitable,

    pub fn terminal(self: WaitState) bool {
        return switch (self) {
            .pending, .ready_on_entry => false,
            else => true,
        };
    }
};

pub const WakeCause = enum(u8) {
    none,
    guest_signal,
    guest_timeout,
    guest_apc,
    guest_termination,
    host_service,
    diagnostic_synthetic,
};

pub const WaitRequest = struct {
    object_id: u64 = 0,
    object_generation: u64 = 0,
    thread_id: u64 = 0,
    timeout: TimeoutInput = .infinite,
    alertable: bool = false,
    wait_all: bool = false,
    wait_index: u32 = 0,
    waitable: bool = true,
};

pub const WaitRecord = struct {
    request: WaitRequest = .{},
    deadline: Deadline = .{},
    state: WaitState = .pending,
    cause: WakeCause = .none,
    signal_id: u64 = 0,
    spurious_wakes: u64 = 0,
    completed_ticks: u64 = 0,

    pub fn begin(request: WaitRequest, clock: Clock, ready_on_entry: bool) WaitRecord {
        var result = WaitRecord{ .request = request, .deadline = decodeTimeout(clock, request.timeout) };
        if (!request.waitable) {
            result.state = .non_waitable;
            result.cause = .none;
        } else if (ready_on_entry) {
            result.state = .ready_on_entry;
            result.cause = .guest_signal;
            result.completed_ticks = clock.ticks;
        } else if (result.deadline.kind == .zero_poll) {
            result.state = .timeout;
            result.cause = .guest_timeout;
            result.completed_ticks = clock.ticks;
        }
        return result;
    }

    pub fn signal(self: *WaitRecord, signal_id: u64, object_generation: u64, clock: Clock) bool {
        if (self.state.terminal()) return false;
        if (object_generation != self.request.object_generation) return false;
        self.state = .signaled;
        self.cause = .guest_signal;
        self.signal_id = signal_id;
        self.completed_ticks = clock.ticks;
        return true;
    }

    pub fn timeoutIfDue(self: *WaitRecord, clock: Clock) bool {
        if (self.state.terminal()) return false;
        const deadline = self.deadline.deadline_ticks orelse return false;
        if (clock.ticks < deadline) return false;
        self.state = .timeout;
        self.cause = .guest_timeout;
        self.completed_ticks = clock.ticks;
        return true;
    }

    pub fn apc(self: *WaitRecord, clock: Clock) bool {
        if (self.state.terminal() or !self.request.alertable) return false;
        self.state = .user_apc;
        self.cause = .guest_apc;
        self.completed_ticks = clock.ticks;
        return true;
    }

    pub fn terminate(self: *WaitRecord, clock: Clock) bool {
        if (self.state.terminal()) return false;
        self.state = .abandoned;
        self.cause = .guest_termination;
        self.completed_ticks = clock.ticks;
        return true;
    }

    pub fn cancel(self: *WaitRecord, clock: Clock) bool {
        if (self.state.terminal()) return false;
        self.state = .cancelled;
        self.cause = .host_service;
        self.completed_ticks = clock.ticks;
        return true;
    }

    /// A POSIX condition-variable wake is not a guest signal. A predicate
    /// loop may inspect its condition again, but the wait remains pending.
    pub fn spuriousWake(self: *WaitRecord) void {
        if (!self.state.terminal()) self.spurious_wakes +|= 1;
    }
};

pub const ObjectType = enum(u8) {
    event,
    semaphore,
    mutex,
    thread,
    timer,
    unknown,
};

pub const Object = struct {
    guest_address: u64 = 0,
    handle: u32 = 0,
    native_handle: u64 = 0,
    generation: u64 = 0,
    owner_process: u64 = 0,
    object_type: ObjectType = .unknown,
    waitable: bool = true,
    alive: bool = false,
    signaled: bool = false,
};

pub const max_objects: usize = 128;

pub const ObjectLedger = struct {
    objects: [max_objects]Object = [_]Object{.{}} ** max_objects,
    count: usize = 0,
    next_generation: u64 = 1,
    violations: u64 = 0,

    pub fn create(self: *ObjectLedger, guest_address: u64, handle: u32, native_handle: u64, object_type: ObjectType, owner_process: u64, waitable: bool) ?*Object {
        if (guest_address == 0 or self.count >= max_objects) {
            self.violations +|= 1;
            return null;
        }
        var object = self.find(guest_address);
        if (object != null and object.?.alive) {
            self.violations +|= 1;
            return null;
        }
        if (object == null) {
            object = &self.objects[self.count];
            self.count += 1;
        }
        object.?.* = .{
            .guest_address = guest_address,
            .handle = handle,
            .native_handle = native_handle,
            .generation = self.next_generation,
            .owner_process = owner_process,
            .object_type = object_type,
            .waitable = waitable,
            .alive = true,
        };
        self.next_generation +|= 1;
        return object;
    }

    pub fn destroy(self: *ObjectLedger, guest_address: u64, generation: u64) bool {
        const object = self.find(guest_address) orelse return false;
        if (!object.alive or object.generation != generation) {
            self.violations +|= 1;
            return false;
        }
        object.alive = false;
        object.signaled = false;
        return true;
    }

    pub fn signal(self: *ObjectLedger, guest_address: u64, generation: u64) bool {
        const object = self.find(guest_address) orelse return false;
        if (!object.alive or object.generation != generation or !object.waitable) {
            self.violations +|= 1;
            return false;
        }
        object.signaled = true;
        return true;
    }

    pub fn reset(self: *ObjectLedger, guest_address: u64, generation: u64) bool {
        const object = self.find(guest_address) orelse return false;
        if (!object.alive or object.generation != generation) {
            self.violations +|= 1;
            return false;
        }
        object.signaled = false;
        return true;
    }

    pub fn find(self: *ObjectLedger, guest_address: u64) ?*Object {
        for (self.objects[0..self.count]) |*object| {
            if (object.guest_address == guest_address) return object;
        }
        return null;
    }
};

pub const SchedulerBinding = struct {
    guest_thread: u64 = 0,
    xenia_thread: u64 = 0,
    xenia_thread_state: u64 = 0,
    ppc_context: u64 = 0,
    rosette_context: u64 = 0,
    host_thread: u64 = 0,
    owner_generation: u64 = 0,
};

pub const SchedulerBridge = struct {
    bindings: [64]SchedulerBinding = [_]SchedulerBinding{.{}} ** 64,
    count: usize = 0,
    violations: u64 = 0,

    pub fn bind(self: *SchedulerBridge, binding: SchedulerBinding) bool {
        if (binding.guest_thread == 0 or binding.ppc_context == 0 or binding.rosette_context == 0) {
            self.violations +|= 1;
            return false;
        }
        for (self.bindings[0..self.count]) |existing| {
            if (existing.guest_thread == binding.guest_thread and existing.rosette_context != binding.rosette_context) {
                self.violations +|= 1;
                return false;
            }
        }
        if (self.count >= self.bindings.len) {
            self.violations +|= 1;
            return false;
        }
        self.bindings[self.count] = binding;
        self.count += 1;
        return true;
    }

    pub fn bindingFor(self: *const SchedulerBridge, guest_thread: u64) ?SchedulerBinding {
        for (self.bindings[0..self.count]) |binding| if (binding.guest_thread == guest_thread) return binding;
        return null;
    }
};

pub const ReplayKind = enum(u8) {
    wait_enter,
    signal,
    timeout,
    completion,
    spurious_wake,
};

pub const ReplayEvent = struct {
    sequence: u64 = 0,
    kind: ReplayKind = .wait_enter,
    object_id: u64 = 0,
    generation: u64 = 0,
    thread_id: u64 = 0,
    state: WaitState = .pending,
    cause: WakeCause = .none,
    guest_ticks: u64 = 0,
};

pub const max_replay_events: usize = 512;

pub const WaitReplay = struct {
    events: [max_replay_events]ReplayEvent = [_]ReplayEvent{.{}} ** max_replay_events,
    count: usize = 0,
    next_sequence: u64 = 1,
    dropped: u64 = 0,

    pub fn append(self: *WaitReplay, event: ReplayEvent) bool {
        if (self.count >= max_replay_events) {
            self.dropped +|= 1;
            return false;
        }
        var stored = event;
        stored.sequence = self.next_sequence;
        self.next_sequence +|= 1;
        self.events[self.count] = stored;
        self.count += 1;
        return true;
    }

    pub fn complete(self: *const WaitReplay) bool {
        return self.count != 0 and self.dropped == 0;
    }

    pub fn digest(self: *const WaitReplay) u64 {
        var hash: u64 = 0xcbf2_9ce4_8422_2325;
        for (self.events[0..self.count]) |event| {
            hash = (hash ^ event.sequence) *% 0x100_0000_01b3;
            hash = (hash ^ event.object_id) *% 0x100_0000_01b3;
            hash = (hash ^ event.generation) *% 0x100_0000_01b3;
            hash = (hash ^ @intFromEnum(event.kind)) *% 0x100_0000_01b3;
            hash = (hash ^ @intFromEnum(event.state)) *% 0x100_0000_01b3;
        }
        return hash;
    }
};

pub const ProgressClass = enum(u8) {
    no_progress,
    guest_progress,
    host_progress,
    diagnostic_only,
    livelock,
    deadlock,
};

pub const ProgressSample = struct {
    guest_steps: u64 = 0,
    guest_time_ticks: u64 = 0,
    pipeline_stage: u64 = 0,
    ring_publications: u64 = 0,
    callbacks: u64 = 0,
    frames: u64 = 0,
    active_host_threads: u64 = 0,
    pending_waits: u64 = 0,
    finite_deadlines: u64 = 0,
    last_signal_id: u64 = 0,
};

pub fn classifyProgress(previous: ProgressSample, current: ProgressSample) ProgressClass {
    const guest_moved = current.guest_time_ticks > previous.guest_time_ticks or current.pipeline_stage > previous.pipeline_stage or current.ring_publications > previous.ring_publications or current.callbacks > previous.callbacks or current.frames > previous.frames;
    const host_moved = current.active_host_threads != 0 and current.active_host_threads != previous.active_host_threads;
    const steps_moved = current.guest_steps > previous.guest_steps;
    if (guest_moved) return .guest_progress;
    if (host_moved) return .host_progress;
    if (steps_moved and current.pending_waits != 0) return .livelock;
    if (current.pending_waits != 0 and current.finite_deadlines == 0 and current.active_host_threads == 0) return .deadlock;
    if (steps_moved) return .diagnostic_only;
    return .no_progress;
}

test "Xbox units convert exactly" {
    try std.testing.expectEqual(@as(u64, 20), ticksToNanoseconds(1));
    try std.testing.expectEqual(@as(u64, 10_000_000), ticksToFileTime(xbox_ticks_per_second));
    try std.testing.expectEqual(@as(u64, xbox_ticks_per_second), fileTimeToTicks(filetime_units_per_second));
}

test "diagnostics cannot advance canonical guest time" {
    var clock = Clock{};
    try std.testing.expect(!clock.advance(10, .diagnostic_probe));
    try std.testing.expectEqual(@as(u64, 0), clock.ticks);
    try std.testing.expect(clock.advanceHost(1_000, .host_wait_service));
    try std.testing.expectEqual(@as(u64, 50), clock.ticks);
}

test "timeout decoder preserves infinite zero relative and absolute forms" {
    const clock = Clock{ .ticks = 100, .filetime_epoch = 1_000 };
    try std.testing.expectEqual(TimeoutKind.infinite, decodeTimeout(clock, .infinite).kind);
    try std.testing.expectEqual(TimeoutKind.zero_poll, decodeTimeout(clock, .{ .value = 0 }).kind);
    const relative = decodeTimeout(clock, .{ .value = -2 });
    try std.testing.expectEqual(TimeoutKind.relative_100ns, relative.kind);
    try std.testing.expectEqual(@as(u64, 110), relative.deadline_ticks.?);
    const absolute = decodeTimeout(clock, .{ .value = 1_002 });
    try std.testing.expectEqual(TimeoutKind.absolute_filetime, absolute.kind);
    try std.testing.expectEqual(@as(u64, 10), absolute.deadline_ticks.?);
}

test "zero poll never parks and spurious wake never signals" {
    const clock = Clock{};
    const poll = WaitRecord.begin(.{ .object_id = 1, .object_generation = 1, .thread_id = 2, .timeout = .{ .value = 0 } }, clock, false);
    try std.testing.expectEqual(WaitState.timeout, poll.state);
    var pending = WaitRecord.begin(.{ .object_id = 1, .object_generation = 1, .thread_id = 2 }, clock, false);
    pending.spuriousWake();
    try std.testing.expectEqual(WaitState.pending, pending.state);
    try std.testing.expectEqual(@as(u64, 1), pending.spurious_wakes);
}

test "wait completion requires object generation" {
    const clock = Clock{};
    var wait = WaitRecord.begin(.{ .object_id = 4, .object_generation = 8, .thread_id = 9 }, clock, false);
    try std.testing.expect(!wait.signal(2, 7, clock));
    try std.testing.expect(wait.signal(2, 8, clock));
    try std.testing.expectEqual(WaitState.signaled, wait.state);
    try std.testing.expect(!wait.timeoutIfDue(clock));
}

test "reused object address gets a new generation" {
    var objects = ObjectLedger{};
    const first = objects.create(0x4000, 1, 2, .event, 3, true).?;
    const generation = first.generation;
    try std.testing.expect(objects.destroy(0x4000, generation));
    const second = objects.create(0x4000, 1, 2, .event, 3, true).?;
    try std.testing.expect(second.generation != generation);
    try std.testing.expect(!objects.signal(0x4000, generation));
    try std.testing.expect(objects.signal(0x4000, second.generation));
}

test "scheduler bridge rejects a context alias" {
    var bridge = SchedulerBridge{};
    try std.testing.expect(bridge.bind(.{ .guest_thread = 1, .ppc_context = 2, .rosette_context = 3 }));
    try std.testing.expect(!bridge.bind(.{ .guest_thread = 1, .ppc_context = 2, .rosette_context = 4 }));
    try std.testing.expectEqual(@as(u64, 1), bridge.violations);
}

test "wait replay is ordered and bounded" {
    var replay = WaitReplay{};
    try std.testing.expect(replay.append(.{ .kind = .wait_enter, .object_id = 1, .generation = 2 }));
    try std.testing.expect(replay.append(.{ .kind = .signal, .object_id = 1, .generation = 2, .state = .signaled, .cause = .guest_signal }));
    try std.testing.expect(replay.complete());
    try std.testing.expect(replay.digest() != 0);
}

test "progress classifier separates a guest pump from a livelock" {
    const before = ProgressSample{ .guest_steps = 10, .pending_waits = 1 };
    const guest = ProgressSample{ .guest_steps = 20, .guest_time_ticks = 1, .pending_waits = 1 };
    try std.testing.expectEqual(ProgressClass.guest_progress, classifyProgress(before, guest));
    const spinning = ProgressSample{ .guest_steps = 20, .pending_waits = 1 };
    try std.testing.expectEqual(ProgressClass.livelock, classifyProgress(before, spinning));
}
