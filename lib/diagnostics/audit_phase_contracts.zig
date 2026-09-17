//! Cross-boundary contracts for the six-phase Rosette/Xenia audit.
//!
//! The individual runtime modules answer local questions well: the manifest
//! knows whether a build is comparable, the wait graph knows who is blocked,
//! and the presentation ledger knows whether a queue accepted a present.  The
//! failure exposed by the 2026-09-15 run is the gap between those answers.
//! This module is the small, dependency-free contract that joins them.
//!
//! It is deliberately a ledger, not a collection of permissive booleans:
//! identities are generation-aware, event sources are named, bounded loss is
//! visible, capabilities carry their refusal semantics, and every authentic
//! frame has to carry one token from guest swap through pixel evidence.

const std = @import("std");

pub const schema_version: u16 = 1;
pub const Hash = u64;

pub fn hashBytes(bytes: []const u8) Hash {
    var value: Hash = 0xcbf2_9ce4_8422_2325;
    for (bytes) |byte| value = (value ^ byte) *% 0x0100_0000_01b3;
    return if (value == 0) 1 else value;
}

pub fn hashTagged(tag: []const u8, value: []const u8) Hash {
    var result = hashBytes(tag);
    result = (result ^ 0) *% 0x0100_0000_01b3;
    result = (result ^ hashBytes(value)) *% 0x0100_0000_01b3;
    return if (result == 0) 1 else result;
}

pub const Phase = enum(u8) {
    contract_evidence,
    runtime_liveness,
    graphics_semantics,
    media_ui_services,
    performance_observer,
    release_profiles,

    pub fn label(self: Phase) []const u8 {
        return switch (self) {
            .contract_evidence => "phase-0-contract-evidence",
            .runtime_liveness => "phase-1-runtime-liveness",
            .graphics_semantics => "phase-2-graphics-semantics",
            .media_ui_services => "phase-3-media-ui-services",
            .performance_observer => "phase-4-performance-observer",
            .release_profiles => "phase-5-release-profiles",
        };
    }

    pub fn owner(self: Phase) []const u8 {
        return switch (self) {
            .contract_evidence => "rosette:admission-and-diagnostics",
            .runtime_liveness => "rosette:loader-kernel-memory",
            .graphics_semantics => "rosette:xenia-gpu-bridge",
            .media_ui_services => "rosette:windows-services-and-window",
            .performance_observer => "rosette:runtime-observer",
            .release_profiles => "rosette:release-admission",
        };
    }

    pub fn acceptance(self: Phase) []const u8 {
        return switch (self) {
            .contract_evidence => "one sealed identity, one event authority, common generation-aware IDs, and machine-readable capability rows",
            .runtime_liveness => "object, wait, callback, module, ABI, memory, and protection evidence retains its causal owner",
            .graphics_semantics => "one frame token proves target, attachment, shader, descriptor, layout, resolve, submit, readback, and paint",
            .media_ui_services => "audio, input, assets, registry, COM, sockets, DLL, and window routes have explicit profile outcomes",
            .performance_observer => "phase budgets and observer overhead are bounded, attributable, and comparable",
            .release_profiles => "every supported profile has fixtures, artifact identity, and an explicit admit/refuse result",
        };
    }
};

pub const phase_count: usize = @typeInfo(Phase).@"enum".fields.len;

pub const PhaseDescriptor = struct {
    phase: Phase,
    label: []const u8,
    owner: []const u8,
    acceptance: []const u8,
};

pub const phase_descriptors = [_]PhaseDescriptor{
    .{ .phase = .contract_evidence, .label = Phase.contract_evidence.label(), .owner = Phase.contract_evidence.owner(), .acceptance = Phase.contract_evidence.acceptance() },
    .{ .phase = .runtime_liveness, .label = Phase.runtime_liveness.label(), .owner = Phase.runtime_liveness.owner(), .acceptance = Phase.runtime_liveness.acceptance() },
    .{ .phase = .graphics_semantics, .label = Phase.graphics_semantics.label(), .owner = Phase.graphics_semantics.owner(), .acceptance = Phase.graphics_semantics.acceptance() },
    .{ .phase = .media_ui_services, .label = Phase.media_ui_services.label(), .owner = Phase.media_ui_services.owner(), .acceptance = Phase.media_ui_services.acceptance() },
    .{ .phase = .performance_observer, .label = Phase.performance_observer.label(), .owner = Phase.performance_observer.owner(), .acceptance = Phase.performance_observer.acceptance() },
    .{ .phase = .release_profiles, .label = Phase.release_profiles.label(), .owner = Phase.release_profiles.owner(), .acceptance = Phase.release_profiles.acceptance() },
};

pub const Profile = enum(u8) {
    authentic,
    diagnostic,
    synthetic,
    replay,

    pub fn label(self: Profile) []const u8 {
        return switch (self) {
            .authentic => "authentic",
            .diagnostic => "diagnostic",
            .synthetic => "synthetic",
            .replay => "replay",
        };
    }

    pub fn permitsAuthentic(self: Profile) bool {
        return self == .authentic;
    }
};

/// Content identity has no path field on purpose.  A path can describe where
/// an input was found; only a digest can establish that it is the same input.
pub const IdentityField = enum(u8) {
    rosette_source,
    rosette_generated,
    xenia_source,
    executable,
    media,
    build,
    config,
    toolchain,
    tests,
    phase_coverage,
};

pub const identity_field_count: usize = @typeInfo(IdentityField).@"enum".fields.len;

pub const Identity = struct {
    run_id: Hash = 0,
    profile: Profile = .authentic,
    fields: [identity_field_count]Hash = [_]Hash{0} ** identity_field_count,
    sealed: bool = false,
    seal_hash: Hash = 0,
    late_mutations: u64 = 0,

    pub fn init(run_id: Hash, profile: Profile) Identity {
        return .{ .run_id = run_id, .profile = profile };
    }

    pub fn set(self: *Identity, field: IdentityField, value: Hash) bool {
        if (value == 0 or self.sealed) {
            if (self.sealed) self.late_mutations +|= 1;
            return false;
        }
        self.fields[@intFromEnum(field)] = value;
        return true;
    }

    pub fn setContent(self: *Identity, field: IdentityField, bytes: []const u8) bool {
        if (bytes.len == 0) return false;
        return self.set(field, hashTagged(@tagName(field), bytes));
    }

    pub fn complete(self: Identity) bool {
        if (self.run_id == 0) return false;
        for (self.fields) |value| if (value == 0) return false;
        return true;
    }

    pub fn fingerprint(self: Identity) Hash {
        var value = self.run_id ^ @as(Hash, @intFromEnum(self.profile));
        for (self.fields, 0..) |field, index| {
            value = (value ^ @as(Hash, @intCast(index + 1))) *% 0x0100_0000_01b3;
            value = (value ^ field) *% 0x0100_0000_01b3;
        }
        return if (value == 0) 1 else value;
    }

    pub fn seal(self: *Identity) bool {
        if (self.sealed) return self.intact();
        if (!self.complete()) return false;
        self.seal_hash = self.fingerprint();
        self.sealed = true;
        return true;
    }

    pub fn intact(self: Identity) bool {
        return self.sealed and self.seal_hash != 0 and self.seal_hash == self.fingerprint();
    }
};

pub const EntityKind = enum(u8) {
    run,
    thread,
    wait,
    kernel_object,
    memory,
    module,
    gpu_object,
    frame,
    swapchain,
    command_buffer,
    shader,
    window,
    service,

    pub fn label(self: EntityKind) []const u8 {
        return switch (self) {
            .run => "run",
            .thread => "thread",
            .wait => "wait",
            .kernel_object => "kernel-object",
            .memory => "memory",
            .module => "module",
            .gpu_object => "gpu-object",
            .frame => "frame",
            .swapchain => "swapchain",
            .command_buffer => "command-buffer",
            .shader => "shader",
            .window => "window",
            .service => "service",
        };
    }
};

/// A value without a generation is not an identity.  Handles, Vulkan objects,
/// windows, and frame image slots are all reusable, so a late use must not be
/// allowed to resolve to the next object's name.
pub const EntityId = struct {
    kind: EntityKind = .run,
    value: u64 = 0,
    generation: u32 = 0,

    pub fn valid(self: EntityId) bool {
        return self.value != 0 and self.generation != 0;
    }

    pub fn eql(self: EntityId, other: EntityId) bool {
        return self.kind == other.kind and self.value == other.value and self.generation == other.generation;
    }

    pub fn digest(self: EntityId) Hash {
        var value = @as(Hash, @intFromEnum(self.kind) + 1);
        value = (value ^ self.value) *% 0x0100_0000_01b3;
        value = (value ^ self.generation) *% 0x0100_0000_01b3;
        return if (value == 0) 1 else value;
    }
};

pub const Authority = enum(u8) {
    direct,
    @"inline",
    override,
    witness,
    derived,
    synthetic,
    replay,

    pub fn label(self: Authority) []const u8 {
        return switch (self) {
            .direct => "direct",
            .@"inline" => "inlined",
            .override => "override",
            .witness => "witness",
            .derived => "derived",
            .synthetic => "synthetic",
            .replay => "replay",
        };
    }

    pub fn authentic(self: Authority) bool {
        return self == .direct or self == .@"inline" or self == .override or self == .witness;
    }
};

pub const EventKind = enum(u8) {
    run_open,
    capability,
    object_create,
    object_use,
    object_retire,
    wait_begin,
    wait_signal,
    wait_timeout,
    wait_resume,
    module_load,
    memory_map,
    memory_protect,
    callback_register,
    callback_delivery,
    frame_begin,
    frame_stage,
    frame_pixel,
    service,
    budget,
    profile_admission,

    pub fn label(self: EventKind) []const u8 {
        return switch (self) {
            .run_open => "run-open",
            .capability => "capability",
            .object_create => "object-create",
            .object_use => "object-use",
            .object_retire => "object-retire",
            .wait_begin => "wait-begin",
            .wait_signal => "wait-signal",
            .wait_timeout => "wait-timeout",
            .wait_resume => "wait-resume",
            .module_load => "module-load",
            .memory_map => "memory-map",
            .memory_protect => "memory-protect",
            .callback_register => "callback-register",
            .callback_delivery => "callback-delivery",
            .frame_begin => "frame-begin",
            .frame_stage => "frame-stage",
            .frame_pixel => "frame-pixel",
            .service => "service",
            .budget => "budget",
            .profile_admission => "profile-admission",
        };
    }
};

pub const EventInput = struct {
    phase: Phase,
    kind: EventKind,
    authority: Authority,
    entity: EntityId = .{},
    parent_event: Hash = 0,
    sequence: u64 = 0,
    guest_step: u64 = 0,
};

pub const Event = struct {
    id: Hash = 0,
    phase: Phase = .contract_evidence,
    kind: EventKind = .run_open,
    authority: Authority = .derived,
    entity: EntityId = .{},
    parent_event: Hash = 0,
    sequence: u64 = 0,
    guest_step: u64 = 0,
};

pub const EventLedger = struct {
    pub const capacity: usize = 2048;

    run_id: Hash = 0,
    next_id: Hash = 1,
    events: [capacity]Event = [_]Event{.{}} ** capacity,
    count: usize = 0,
    dropped: u64 = 0,
    dropped_digest: Hash = 0,
    last_sequence: [@typeInfo(Authority).@"enum".fields.len]u64 = [_]u64{0} ** @typeInfo(Authority).@"enum".fields.len,

    pub fn open(self: *EventLedger, run_id: Hash) void {
        self.* = .{ .run_id = run_id };
    }

    pub fn append(self: *EventLedger, input: EventInput) ?Hash {
        if (self.run_id == 0 or self.count == self.events.len) {
            self.noteDrop(input.kind, input.entity);
            return null;
        }
        const authority_index = @intFromEnum(input.authority);
        const prior = self.last_sequence[authority_index];
        if (input.sequence != 0 and input.sequence <= prior) {
            self.noteDrop(input.kind, input.entity);
            return null;
        }
        if (input.parent_event != 0 and !self.contains(input.parent_event)) {
            self.noteDrop(input.kind, input.entity);
            return null;
        }
        const sequence = if (input.sequence == 0) prior + 1 else input.sequence;
        const event = Event{
            .id = self.next_id,
            .phase = input.phase,
            .kind = input.kind,
            .authority = input.authority,
            .entity = input.entity,
            .parent_event = input.parent_event,
            .sequence = sequence,
            .guest_step = input.guest_step,
        };
        self.events[self.count] = event;
        self.count += 1;
        self.next_id +|= 1;
        self.last_sequence[authority_index] = sequence;
        return event.id;
    }

    pub fn retained(self: *const EventLedger) []const Event {
        return self.events[0..self.count];
    }

    pub fn lossless(self: EventLedger) bool {
        return self.dropped == 0;
    }

    fn contains(self: *const EventLedger, id: Hash) bool {
        for (self.retained()) |event| if (event.id == id) return true;
        return false;
    }

    fn noteDrop(self: *EventLedger, kind: EventKind, entity: EntityId) void {
        self.dropped +|= 1;
        self.dropped_digest = (self.dropped_digest ^ @intFromEnum(kind) + 1) *% 0x0100_0000_01b3;
        self.dropped_digest = (self.dropped_digest ^ entity.digest()) *% 0x0100_0000_01b3;
        if (self.dropped_digest == 0) self.dropped_digest = 1;
    }
};

pub const Owner = enum(u8) {
    guest,
    xenia,
    rosette_loader,
    rosette_kernel,
    rosette_memory,
    rosette_gpu,
    rosette_audio,
    rosette_window,
    rosette_services,
    rosette_observer,
    host,
    unknown,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .guest => "guest",
            .xenia => "xenia",
            .rosette_loader => "rosette:loader",
            .rosette_kernel => "rosette:kernel",
            .rosette_memory => "rosette:memory",
            .rosette_gpu => "rosette:gpu",
            .rosette_audio => "rosette:audio",
            .rosette_window => "rosette:window",
            .rosette_services => "rosette:services",
            .rosette_observer => "rosette:observer",
            .host => "host",
            .unknown => "unknown",
        };
    }
};

pub const Lifetime = enum(u8) {
    live,
    retired,
    destroyed,

    pub fn usable(self: Lifetime) bool {
        return self == .live;
    }
};

pub const EntityRecord = struct {
    id: EntityId = .{},
    owner: Owner = .unknown,
    lifetime: Lifetime = .live,
    create_event: Hash = 0,
    last_event: Hash = 0,
    uses: u64 = 0,
    invalid_uses: u64 = 0,
};

pub const EntityLedger = struct {
    pub const capacity: usize = 512;

    records: [capacity]EntityRecord = [_]EntityRecord{.{}} ** capacity,
    count: usize = 0,
    invalid_operations: u64 = 0,

    pub fn create(self: *EntityLedger, id: EntityId, owner: Owner, event: Hash) bool {
        if (!id.valid() or self.find(id) != null or self.count == self.records.len) {
            self.invalid_operations +|= 1;
            return false;
        }
        self.records[self.count] = .{ .id = id, .owner = owner, .create_event = event, .last_event = event };
        self.count += 1;
        return true;
    }

    pub fn use(self: *EntityLedger, id: EntityId, event: Hash) bool {
        const record = self.find(id) orelse {
            self.invalid_operations +|= 1;
            return false;
        };
        record.last_event = event;
        if (!record.lifetime.usable()) {
            record.invalid_uses +|= 1;
            self.invalid_operations +|= 1;
            return false;
        }
        record.uses +|= 1;
        return true;
    }

    pub fn retire(self: *EntityLedger, id: EntityId, event: Hash) bool {
        const record = self.find(id) orelse {
            self.invalid_operations +|= 1;
            return false;
        };
        if (record.lifetime != .live) {
            self.invalid_operations +|= 1;
            return false;
        }
        record.lifetime = .retired;
        record.last_event = event;
        return true;
    }

    pub fn destroy(self: *EntityLedger, id: EntityId, event: Hash) bool {
        const record = self.find(id) orelse {
            self.invalid_operations +|= 1;
            return false;
        };
        if (record.lifetime == .destroyed) {
            self.invalid_operations +|= 1;
            return false;
        }
        record.lifetime = .destroyed;
        record.last_event = event;
        return true;
    }

    pub fn find(self: *EntityLedger, id: EntityId) ?*EntityRecord {
        for (self.records[0..self.count]) |*record| if (record.id.eql(id)) return record;
        return null;
    }

    pub fn liveCount(self: *const EntityLedger) usize {
        var total: usize = 0;
        for (self.records[0..self.count]) |record| {
            if (record.lifetime == .live) total += 1;
        }
        return total;
    }
};

pub const CapabilityState = enum(u8) {
    unknown,
    available,
    fallback,
    refused,
    unsupported,
    unavailable,

    pub fn usable(self: CapabilityState) bool {
        return self == .available or self == .fallback;
    }
};

pub const Requirement = enum(u8) {
    required,
    optional,
};

pub const CapabilityRecord = struct {
    id: u16 = 0,
    name: []const u8 = "",
    owner: Owner = .unknown,
    requirement: Requirement = .optional,
    state: CapabilityState = .unknown,
    fallback: []const u8 = "",
    evidence_event: Hash = 0,
    return_code: i64 = 0,
    out_parameters_written: bool = false,
    retryable: bool = false,

    pub fn valid(self: CapabilityRecord) bool {
        if (self.id == 0 or self.name.len == 0 or self.state == .unknown) return false;
        if (self.state == .fallback and self.fallback.len == 0) return false;
        if (self.state == .refused and self.return_code == 0 and self.fallback.len == 0) return false;
        return true;
    }
};

pub const CapabilityLedger = struct {
    pub const capacity: usize = 256;

    records: [capacity]CapabilityRecord = [_]CapabilityRecord{.{}} ** capacity,
    count: usize = 0,
    malformed: u64 = 0,

    pub fn record(self: *CapabilityLedger, value: CapabilityRecord) bool {
        if (!value.valid()) {
            self.malformed +|= 1;
            return false;
        }
        for (self.records[0..self.count]) |*existing| {
            if (existing.id != value.id) continue;
            existing.* = value;
            return true;
        }
        if (self.count == self.records.len) {
            self.malformed +|= 1;
            return false;
        }
        self.records[self.count] = value;
        self.count += 1;
        return true;
    }

    pub fn requiredReady(self: *const CapabilityLedger) bool {
        if (self.malformed != 0) return false;
        for (self.records[0..self.count]) |entry| {
            if (entry.requirement == .required and !entry.state.usable()) return false;
        }
        return true;
    }

    pub fn find(self: *const CapabilityLedger, id: u16) ?CapabilityRecord {
        for (self.records[0..self.count]) |entry| if (entry.id == id) return entry;
        return null;
    }
};

pub const WaitVerdict = enum(u8) {
    blocked,
    completed,
    optional_poll_timeout,
    missing_producer,
    signaled_not_resumed,

    pub fn label(self: WaitVerdict) []const u8 {
        return switch (self) {
            .blocked => "blocked",
            .completed => "completed",
            .optional_poll_timeout => "optional-poll-timeout",
            .missing_producer => "missing-producer",
            .signaled_not_resumed => "signaled-not-resumed",
        };
    }
};

pub const WaitRecord = struct {
    id: EntityId = .{},
    waiter: EntityId = .{},
    object: EntityId = .{},
    expected_producer: EntityId = .{},
    deadline_ticks: u64 = 0,
    begin_event: Hash = 0,
    signal_event: Hash = 0,
    resume_event: Hash = 0,
    timeout_event: Hash = 0,
    optional_poll: bool = false,
    signal_count: u32 = 0,

    pub fn verdict(self: WaitRecord) WaitVerdict {
        if (self.resume_event != 0) return .completed;
        if (self.timeout_event != 0 and self.optional_poll) return .optional_poll_timeout;
        if (!self.expected_producer.valid()) return .missing_producer;
        if (self.signal_event != 0) return .signaled_not_resumed;
        return .blocked;
    }
};

pub const WaitLedger = struct {
    pub const capacity: usize = 512;

    records: [capacity]WaitRecord = [_]WaitRecord{.{}} ** capacity,
    count: usize = 0,
    cycles: u64 = 0,
    invalid_operations: u64 = 0,

    pub fn begin(
        self: *WaitLedger,
        id: EntityId,
        waiter: EntityId,
        object: EntityId,
        producer: EntityId,
        deadline_ticks: u64,
        optional_poll: bool,
        event: Hash,
    ) bool {
        if (!id.valid() or !waiter.valid() or !object.valid() or self.find(id) != null or self.count == self.records.len) {
            self.invalid_operations +|= 1;
            return false;
        }
        self.records[self.count] = .{
            .id = id,
            .waiter = waiter,
            .object = object,
            .expected_producer = producer,
            .deadline_ticks = deadline_ticks,
            .begin_event = event,
            .optional_poll = optional_poll,
        };
        self.count += 1;
        return true;
    }

    pub fn signal(self: *WaitLedger, id: EntityId, producer: EntityId, event: Hash) bool {
        const record = self.find(id) orelse {
            self.invalid_operations +|= 1;
            return false;
        };
        if (record.expected_producer.valid() and !record.expected_producer.eql(producer)) {
            self.invalid_operations +|= 1;
            return false;
        }
        record.signal_event = event;
        record.signal_count +|= 1;
        return true;
    }

    pub fn timeout(self: *WaitLedger, id: EntityId, event: Hash) bool {
        const record = self.find(id) orelse {
            self.invalid_operations +|= 1;
            return false;
        };
        record.timeout_event = event;
        return true;
    }

    pub fn @"resume"(self: *WaitLedger, id: EntityId, event: Hash) bool {
        const record = self.find(id) orelse {
            self.invalid_operations +|= 1;
            return false;
        };
        if (record.signal_event == 0 and record.timeout_event == 0) {
            self.invalid_operations +|= 1;
            return false;
        }
        record.resume_event = event;
        return true;
    }

    pub fn find(self: *WaitLedger, id: EntityId) ?*WaitRecord {
        for (self.records[0..self.count]) |*record| if (record.id.eql(id)) return record;
        return null;
    }

    pub fn unresolved(self: *const WaitLedger) u64 {
        var total: u64 = 0;
        for (self.records[0..self.count]) |record| {
            switch (record.verdict()) {
                .blocked, .missing_producer, .signaled_not_resumed => total += 1,
                .completed, .optional_poll_timeout => {},
            }
        }
        return total;
    }
};

pub const AddressSpace = enum(u8) {
    guest,
    host,
    synthetic,
    unknown,
};

pub const MemoryState = enum(u8) {
    reserved,
    committed,
    protected,
    retired,
};

pub const MemoryRegion = struct {
    id: EntityId = .{},
    address_space: AddressSpace = .unknown,
    base: u64 = 0,
    size: u64 = 0,
    state: MemoryState = .reserved,
    owner: Owner = .unknown,
    writes: u64 = 0,
    faults: u64 = 0,

    pub fn contains(self: MemoryRegion, address: u64) bool {
        return self.size != 0 and address >= self.base and address - self.base < self.size;
    }
};

pub const Relocation = struct {
    site: u64 = 0,
    target: u64 = 0,
    generation: u32 = 0,
};

pub const MemoryLedger = struct {
    pub const region_capacity: usize = 512;
    pub const relocation_capacity: usize = 4096;

    regions: [region_capacity]MemoryRegion = [_]MemoryRegion{.{}} ** region_capacity,
    region_count: usize = 0,
    relocations: [relocation_capacity]Relocation = [_]Relocation{.{}} ** relocation_capacity,
    relocation_count: usize = 0,
    relocation_overflow: u64 = 0,
    relocation_overflow_digest: Hash = 0,
    invalid_accesses: u64 = 0,

    pub fn map(self: *MemoryLedger, region: MemoryRegion) bool {
        if (!region.id.valid() or region.base == 0 or region.size == 0 or self.region_count == self.regions.len) {
            self.invalid_accesses +|= 1;
            return false;
        }
        if (self.find(region.id) != null) {
            self.invalid_accesses +|= 1;
            return false;
        }
        self.regions[self.region_count] = region;
        self.region_count += 1;
        return true;
    }

    pub fn protect(self: *MemoryLedger, id: EntityId, state: MemoryState) bool {
        const region = self.find(id) orelse {
            self.invalid_accesses +|= 1;
            return false;
        };
        if (region.state == .retired) {
            self.invalid_accesses +|= 1;
            return false;
        }
        region.state = state;
        return true;
    }

    pub fn access(self: *MemoryLedger, address: u64, write: bool) bool {
        for (self.regions[0..self.region_count]) |*region| {
            if (!region.contains(address)) continue;
            if (region.state == .retired) {
                self.invalid_accesses +|= 1;
                return false;
            }
            if (write) region.writes +|= 1;
            return true;
        }
        self.invalid_accesses +|= 1;
        return false;
    }

    pub fn fault(self: *MemoryLedger, id: EntityId) bool {
        const region = self.find(id) orelse {
            self.invalid_accesses +|= 1;
            return false;
        };
        region.faults +|= 1;
        return true;
    }

    pub fn addRelocation(self: *MemoryLedger, value: Relocation) bool {
        if (value.site == 0 or value.target == 0 or value.generation == 0) {
            self.invalid_accesses +|= 1;
            return false;
        }
        if (self.relocation_count == self.relocations.len) {
            self.relocation_overflow +|= 1;
            self.relocation_overflow_digest = (self.relocation_overflow_digest ^ value.site) *% 0x0100_0000_01b3;
            self.relocation_overflow_digest = (self.relocation_overflow_digest ^ value.target) *% 0x0100_0000_01b3;
            if (self.relocation_overflow_digest == 0) self.relocation_overflow_digest = 1;
            return false;
        }
        self.relocations[self.relocation_count] = value;
        self.relocation_count += 1;
        return true;
    }

    pub fn lossless(self: MemoryLedger) bool {
        return self.relocation_overflow == 0 and self.invalid_accesses == 0;
    }

    pub fn find(self: *MemoryLedger, id: EntityId) ?*MemoryRegion {
        for (self.regions[0..self.region_count]) |*region| if (region.id.eql(id)) return region;
        return null;
    }

    pub fn classify(self: *const MemoryLedger, address: u64) AddressSpace {
        for (self.regions[0..self.region_count]) |region| {
            if (region.contains(address)) return region.address_space;
        }
        return .unknown;
    }
};

pub const ModuleState = enum(u8) {
    declared,
    loaded,
    refused,
    missing,
    retired,
};

pub const ModuleRecord = struct {
    id: EntityId = .{},
    name: []const u8 = "",
    content_hash: Hash = 0,
    state: ModuleState = .declared,
    imports: u32 = 0,
    exports: u32 = 0,
    tls_slot: u32 = 0,
    attached_threads: u32 = 0,
    loader_lock_depth: u32 = 0,

    pub fn identityValid(self: ModuleRecord) bool {
        return self.id.valid() and self.name.len != 0 and self.content_hash != 0;
    }
};

pub const ModuleLedger = struct {
    pub const capacity: usize = 256;

    records: [capacity]ModuleRecord = [_]ModuleRecord{.{}} ** capacity,
    count: usize = 0,
    missing_dependencies: u64 = 0,
    abi_failures: u64 = 0,

    pub fn declare(self: *ModuleLedger, module: ModuleRecord) bool {
        if (!module.identityValid() or self.find(module.id) != null or self.count == self.records.len) {
            self.abi_failures +|= 1;
            return false;
        }
        self.records[self.count] = module;
        self.count += 1;
        return true;
    }

    pub fn load(self: *ModuleLedger, id: EntityId) bool {
        const module = self.find(id) orelse {
            self.missing_dependencies +|= 1;
            return false;
        };
        if (module.state == .missing or module.state == .refused) {
            self.abi_failures +|= 1;
            return false;
        }
        module.state = .loaded;
        return true;
    }

    pub fn noteTlsAttach(self: *ModuleLedger, id: EntityId, slot: u32) bool {
        const module = self.find(id) orelse {
            self.abi_failures +|= 1;
            return false;
        };
        if (module.state != .loaded or slot == 0) {
            self.abi_failures +|= 1;
            return false;
        }
        module.tls_slot = slot;
        module.attached_threads +|= 1;
        return true;
    }

    pub fn find(self: *ModuleLedger, id: EntityId) ?*ModuleRecord {
        for (self.records[0..self.count]) |*record| if (record.id.eql(id)) return record;
        return null;
    }

    pub fn ready(self: *const ModuleLedger) bool {
        return self.missing_dependencies == 0 and self.abi_failures == 0;
    }
};

pub const FrameStage = enum(u8) {
    guest_swap,
    acquired_image,
    command_recorded,
    attachment_bound,
    store_or_resolve,
    layout_visible,
    shader_output,
    descriptors_resolved,
    submitted,
    gpu_complete,
    readback,
    present,
    paint,
    compositor,

    pub fn label(self: FrameStage) []const u8 {
        return switch (self) {
            .guest_swap => "guest-swap",
            .acquired_image => "acquired-image",
            .command_recorded => "command-recorded",
            .attachment_bound => "attachment-bound",
            .store_or_resolve => "store-or-resolve",
            .layout_visible => "layout-visible",
            .shader_output => "shader-output",
            .descriptors_resolved => "descriptors-resolved",
            .submitted => "submitted",
            .gpu_complete => "gpu-complete",
            .readback => "readback",
            .present => "present",
            .paint => "paint",
            .compositor => "compositor",
        };
    }
};

pub const frame_stage_count: usize = @typeInfo(FrameStage).@"enum".fields.len;

pub const FrameSource = enum(u8) {
    unknown,
    clear,
    draw,
    sampled_image,
    image_transfer,
    buffer_upload,
    edram_resolve,

    pub fn contentBearing(self: FrameSource) bool {
        return self != .unknown and self != .clear;
    }
};

pub const PixelResult = enum(u8) {
    unavailable,
    uniform_black,
    uniform_colour,
    nonzero_static,
    changing,

    pub fn detailed(self: PixelResult) bool {
        return self == .nonzero_static or self == .changing;
    }
};

pub const FrameVerdict = enum(u8) {
    incomplete,
    transport_only,
    wrong_target,
    missing_resolve,
    missing_shader_output,
    missing_descriptor_source,
    layout_failure,
    title_black,
    readback_failure,
    valid_content,

    pub fn label(self: FrameVerdict) []const u8 {
        return switch (self) {
            .incomplete => "incomplete",
            .transport_only => "transport-only",
            .wrong_target => "wrong-target",
            .missing_resolve => "missing-resolve",
            .missing_shader_output => "missing-shader-output",
            .missing_descriptor_source => "missing-descriptor-source",
            .layout_failure => "layout-failure",
            .title_black => "title-black",
            .readback_failure => "readback-failure",
            .valid_content => "valid-content",
        };
    }
};

pub const FrameToken = struct {
    run_id: Hash = 0,
    frame_id: u64 = 0,
    swapchain_generation: u32 = 0,
    image_id: u64 = 0,

    pub fn valid(self: FrameToken) bool {
        return self.run_id != 0 and self.frame_id != 0 and self.swapchain_generation != 0 and self.image_id != 0;
    }

    pub fn eql(self: FrameToken, other: FrameToken) bool {
        return self.run_id == other.run_id and self.frame_id == other.frame_id and
            self.swapchain_generation == other.swapchain_generation and self.image_id == other.image_id;
    }
};

pub const FrameRecord = struct {
    token: FrameToken = .{},
    stage_mask: u32 = 0,
    target_image: u64 = 0,
    attachment_image: u64 = 0,
    shader_id: u64 = 0,
    source: FrameSource = .unknown,
    pixel: PixelResult = .unavailable,
    pixel_hash: Hash = 0,
    target_matches_image: bool = false,
    shader_produced_output: bool = false,
    descriptors_resolved: bool = false,
    layout_visible_to_readback: bool = false,
    stage_rejections: u32 = 0,
    last_event: Hash = 0,

    pub fn has(self: FrameRecord, stage: FrameStage) bool {
        return self.stage_mask & stageBit(stage) != 0;
    }

    pub fn completeTransport(self: FrameRecord) bool {
        return self.has(.guest_swap) and self.has(.acquired_image) and
            self.has(.submitted) and self.has(.gpu_complete) and
            self.has(.present) and self.has(.paint);
    }

    pub fn authenticReady(self: FrameRecord) bool {
        return self.completeTransport() and self.has(.compositor) and
            self.source.contentBearing() and self.target_matches_image and
            self.shader_produced_output and self.descriptors_resolved and
            self.layout_visible_to_readback and self.pixel.detailed();
    }

    pub fn verdict(self: FrameRecord) FrameVerdict {
        if (!self.token.valid() or !self.has(.guest_swap) or !self.has(.acquired_image) or
            !self.has(.command_recorded) or !self.has(.attachment_bound))
        {
            return .incomplete;
        }
        if (!self.target_matches_image) return .wrong_target;
        if (!self.has(.store_or_resolve)) return .missing_resolve;
        if (!self.has(.shader_output) or !self.shader_produced_output) return .missing_shader_output;
        if (self.source == .sampled_image and (!self.has(.descriptors_resolved) or !self.descriptors_resolved)) {
            return .missing_descriptor_source;
        }
        if (!self.has(.layout_visible) or !self.layout_visible_to_readback) return .layout_failure;
        if (!self.has(.submitted) or !self.has(.gpu_complete) or !self.has(.present) or !self.has(.paint)) {
            return .transport_only;
        }
        if (!self.has(.readback) or self.pixel == .unavailable) return .readback_failure;
        if (self.pixel == .uniform_black and self.source == .clear) return .title_black;
        if (!self.pixel.detailed()) return .transport_only;
        return .valid_content;
    }
};

pub const FrameLedger = struct {
    pub const capacity: usize = 128;

    records: [capacity]FrameRecord = [_]FrameRecord{.{}} ** capacity,
    count: usize = 0,
    rejected: u64 = 0,

    pub fn begin(self: *FrameLedger, token: FrameToken, event: Hash) bool {
        if (!token.valid() or self.find(token) != null or self.count == self.records.len) {
            self.rejected +|= 1;
            return false;
        }
        self.records[self.count] = .{ .token = token, .last_event = event };
        self.count += 1;
        return true;
    }

    pub fn stage(self: *FrameLedger, token: FrameToken, next_stage: FrameStage, event: Hash) bool {
        const record = self.find(token) orelse {
            self.rejected +|= 1;
            return false;
        };
        if (!stagePrerequisite(record.*, next_stage) or record.has(next_stage)) {
            record.stage_rejections +|= 1;
            self.rejected +|= 1;
            return false;
        }
        record.stage_mask |= stageBit(next_stage);
        record.last_event = event;
        return true;
    }

    pub fn noteTarget(self: *FrameLedger, token: FrameToken, target: u64, attachment: u64) bool {
        const record = self.find(token) orelse return false;
        if (target == 0 or attachment == 0) return false;
        record.target_image = target;
        record.attachment_image = attachment;
        record.target_matches_image = target == token.image_id;
        return true;
    }

    pub fn noteSource(self: *FrameLedger, token: FrameToken, source: FrameSource) bool {
        const record = self.find(token) orelse return false;
        if (source == .unknown) return false;
        record.source = source;
        return true;
    }

    pub fn noteShader(self: *FrameLedger, token: FrameToken, shader_id: u64, produced_output: bool) bool {
        const record = self.find(token) orelse return false;
        if (shader_id == 0) return false;
        record.shader_id = shader_id;
        record.shader_produced_output = produced_output;
        return true;
    }

    pub fn noteDescriptors(self: *FrameLedger, token: FrameToken, resolved: bool) bool {
        const record = self.find(token) orelse return false;
        record.descriptors_resolved = resolved;
        return true;
    }

    pub fn noteLayout(self: *FrameLedger, token: FrameToken, visible: bool) bool {
        const record = self.find(token) orelse return false;
        record.layout_visible_to_readback = visible;
        return true;
    }

    pub fn notePixel(self: *FrameLedger, token: FrameToken, pixel: PixelResult, pixel_hash: Hash) bool {
        const record = self.find(token) orelse return false;
        record.pixel = pixel;
        record.pixel_hash = pixel_hash;
        return true;
    }

    pub fn find(self: *FrameLedger, token: FrameToken) ?*FrameRecord {
        for (self.records[0..self.count]) |*record| if (record.token.eql(token)) return record;
        return null;
    }

    pub fn validContentCount(self: *const FrameLedger) usize {
        var total: usize = 0;
        for (self.records[0..self.count]) |record| {
            if (record.verdict() == .valid_content) total += 1;
        }
        return total;
    }
};

fn stageBit(stage: FrameStage) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(stage)));
}

fn stagePrerequisite(record: FrameRecord, stage: FrameStage) bool {
    return switch (stage) {
        .guest_swap => true,
        .acquired_image => record.has(.guest_swap),
        .command_recorded => record.has(.acquired_image),
        .attachment_bound => record.has(.command_recorded),
        .store_or_resolve => record.has(.attachment_bound),
        .layout_visible => record.has(.store_or_resolve),
        .shader_output, .descriptors_resolved => record.has(.command_recorded),
        .submitted => record.has(.layout_visible) and record.has(.shader_output),
        .gpu_complete => record.has(.submitted),
        .readback => record.has(.gpu_complete) and record.has(.layout_visible),
        .present => record.has(.readback),
        .paint => record.has(.present),
        .compositor => record.has(.paint),
    };
}

pub const ServiceKind = enum(u8) {
    audio_transport,
    xma_codec,
    input,
    font_assets,
    registry_profile,
    com,
    sockets,
    dynamic_dll,
    child_process,
    window,

    pub fn label(self: ServiceKind) []const u8 {
        return switch (self) {
            .audio_transport => "audio-transport",
            .xma_codec => "xma-codec",
            .input => "input",
            .font_assets => "font-assets",
            .registry_profile => "registry-profile",
            .com => "com",
            .sockets => "sockets",
            .dynamic_dll => "dynamic-dll",
            .child_process => "child-process",
            .window => "window",
        };
    }
};

pub const ServiceState = enum(u8) {
    unknown,
    observed,
    fallback,
    refused,
    unsupported,
    unavailable,

    pub fn usable(self: ServiceState) bool {
        return self == .observed or self == .fallback;
    }
};

pub const ServiceRecord = struct {
    kind: ServiceKind,
    state: ServiceState = .unknown,
    required: bool = false,
    evidence_event: Hash = 0,
    reason: []const u8 = "",
};

pub const ServiceLedger = struct {
    pub const capacity: usize = 32;

    records: [capacity]ServiceRecord = undefined,
    count: usize = 0,
    malformed: u64 = 0,

    pub fn note(self: *ServiceLedger, record: ServiceRecord) bool {
        if (record.state == .unknown or (record.state == .refused and record.reason.len == 0)) {
            self.malformed +|= 1;
            return false;
        }
        for (self.records[0..self.count]) |*existing| {
            if (existing.kind != record.kind) continue;
            existing.* = record;
            return true;
        }
        if (self.count == self.records.len) {
            self.malformed +|= 1;
            return false;
        }
        self.records[self.count] = record;
        self.count += 1;
        return true;
    }

    pub fn requiredReady(self: *const ServiceLedger) bool {
        if (self.malformed != 0) return false;
        for (self.records[0..self.count]) |record| {
            if (record.required and !record.state.usable()) return false;
        }
        return true;
    }

    pub fn find(self: *const ServiceLedger, kind: ServiceKind) ?ServiceRecord {
        for (self.records[0..self.count]) |record| if (record.kind == kind) return record;
        return null;
    }
};

pub const AudioVerdict = enum(u8) {
    no_title_submission,
    title_silence,
    decoder_gap,
    device_gap,
    audible,

    pub fn label(self: AudioVerdict) []const u8 {
        return switch (self) {
            .no_title_submission => "no-title-submission",
            .title_silence => "title-silence",
            .decoder_gap => "decoder-gap",
            .device_gap => "device-gap",
            .audible => "audible",
        };
    }
};

pub const AudioLedger = struct {
    submitted_frames: u64 = 0,
    nonzero_frames: u64 = 0,
    xma_programmed: u64 = 0,
    xma_decoded: u64 = 0,
    decoder_refusals: u64 = 0,
    device_callbacks: u64 = 0,
    delivered_bytes: u64 = 0,

    pub fn verdict(self: AudioLedger) AudioVerdict {
        if (self.submitted_frames == 0) return .no_title_submission;
        if (self.nonzero_frames == 0 and self.xma_programmed == 0) return .title_silence;
        if (self.xma_programmed != 0 and self.xma_decoded == 0) return .decoder_gap;
        if (self.nonzero_frames != 0 and (self.device_callbacks == 0 or self.delivered_bytes == 0)) return .device_gap;
        return .audible;
    }
};

pub const WindowOwner = enum(u8) {
    none,
    rosette_startup,
    guest,
    appkit,
    external,

    pub fn label(self: WindowOwner) []const u8 {
        return switch (self) {
            .none => "none",
            .rosette_startup => "rosette-startup",
            .guest => "guest",
            .appkit => "appkit",
            .external => "external",
        };
    }
};

pub const WindowAuthority = struct {
    owner: WindowOwner = .none,
    generation: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    visible_fraction_percent: u8 = 0,
    repairs: u32 = 0,
    contested: bool = false,
    stabilized: bool = false,

    pub fn observe(self: *WindowAuthority, owner: WindowOwner, width: u32, height: u32, visible: u8) bool {
        if (owner == .none or width == 0 or height == 0) return false;
        if (self.owner != .none and self.owner != owner) self.contested = true;
        if (self.width != 0 and (self.width != width or self.height != height)) {
            self.generation +|= 1;
            self.stabilized = false;
        }
        if (self.owner != .none and self.owner != owner) self.stabilized = false;
        if (self.generation == 0) self.generation = 1;
        self.owner = owner;
        self.width = width;
        self.height = height;
        self.visible_fraction_percent = visible;
        return true;
    }

    pub fn noteRepair(self: *WindowAuthority) void {
        self.repairs +|= 1;
        self.stabilized = false;
    }

    pub fn stabilize(self: *WindowAuthority) bool {
        if (self.owner == .none or self.width == 0 or self.height == 0 or self.contested) return false;
        self.stabilized = true;
        return true;
    }

    pub fn validFor(self: WindowAuthority, width: u32, height: u32) bool {
        return self.stabilized and !self.contested and self.width == width and self.height == height;
    }
};

pub const PerfPhase = enum(u8) {
    pe_preflight,
    decompression,
    hashing,
    translation,
    scheduler,
    event_pump,
    lock,
    shader_compile,
    pipeline_compile,
    guest_execution,
    queue_submit,
    present,
    ui_repair,
    observer,

    pub fn label(self: PerfPhase) []const u8 {
        return switch (self) {
            .pe_preflight => "pe-preflight",
            .decompression => "decompression",
            .hashing => "hashing",
            .translation => "translation",
            .scheduler => "scheduler",
            .event_pump => "event-pump",
            .lock => "lock",
            .shader_compile => "shader-compile",
            .pipeline_compile => "pipeline-compile",
            .guest_execution => "guest-execution",
            .queue_submit => "queue-submit",
            .present => "present",
            .ui_repair => "ui-repair",
            .observer => "observer",
        };
    }
};

pub const perf_phase_count: usize = @typeInfo(PerfPhase).@"enum".fields.len;

pub const PerformanceLedger = struct {
    spent_ns: [perf_phase_count]u64 = [_]u64{0} ** perf_phase_count,
    budget_ns: [perf_phase_count]u64 = [_]u64{0} ** perf_phase_count,
    observer_ns: u64 = 0,
    observer_events: u64 = 0,
    budget_breaches: u64 = 0,

    pub fn setBudget(self: *PerformanceLedger, phase: PerfPhase, budget: u64) void {
        self.budget_ns[@intFromEnum(phase)] = budget;
    }

    pub fn spend(self: *PerformanceLedger, phase: PerfPhase, duration_ns: u64) void {
        self.spent_ns[@intFromEnum(phase)] +|= duration_ns;
        if (phase == .observer) {
            self.observer_ns +|= duration_ns;
            self.observer_events +|= 1;
        }
        const budget = self.budget_ns[@intFromEnum(phase)];
        if (budget != 0 and self.spent_ns[@intFromEnum(phase)] > budget) self.budget_breaches +|= 1;
    }

    pub fn observerPercent(self: PerformanceLedger) u64 {
        var total: u64 = 0;
        for (self.spent_ns) |duration| total +|= duration;
        if (total == 0) return 0;
        return (self.observer_ns *| 100) / total;
    }

    pub fn dominant(self: PerformanceLedger) ?PerfPhase {
        var best: ?PerfPhase = null;
        var best_ns: u64 = 0;
        for (self.spent_ns, 0..) |duration, index| {
            if (duration <= best_ns) continue;
            best_ns = duration;
            best = @enumFromInt(index);
        }
        return best;
    }

    pub fn withinBudget(self: PerformanceLedger) bool {
        return self.budget_breaches == 0;
    }
};

pub const ApplicationProfile = enum(u8) {
    xenia_guest,
    generic_pe_console,
    native_d3d,
    native_vulkan,
    unsupported_protected,

    pub fn label(self: ApplicationProfile) []const u8 {
        return switch (self) {
            .xenia_guest => "xenia-guest",
            .generic_pe_console => "generic-pe-console",
            .native_d3d => "native-d3d",
            .native_vulkan => "native-vulkan",
            .unsupported_protected => "unsupported-protected",
        };
    }
};

pub const AdmissionVerdict = enum(u8) {
    admitted,
    needs_fixture,
    refused_capability,
    refused_profile,
    identity_mismatch,

    pub fn label(self: AdmissionVerdict) []const u8 {
        return switch (self) {
            .admitted => "admitted",
            .needs_fixture => "needs-fixture",
            .refused_capability => "refused-capability",
            .refused_profile => "refused-profile",
            .identity_mismatch => "identity-mismatch",
        };
    }
};

pub const FixtureKind = enum(u8) {
    known_color_clear,
    known_color_draw,
    descriptor_sample,
    buffer_upload,
    offscreen_resolve,
    swapchain_recreate,
    uniform_black,
    nonzero_pcm,
    intentional_silence,
    xma_unsupported,
    loader_search,
    tls_callback,
    wait_timeout,
    abi_callback,
    registry_profile,
    com_apartment,
    socket_offline,
    window_resize,

    pub fn label(self: FixtureKind) []const u8 {
        return switch (self) {
            .known_color_clear => "known-color-clear",
            .known_color_draw => "known-color-draw",
            .descriptor_sample => "descriptor-sample",
            .buffer_upload => "buffer-upload",
            .offscreen_resolve => "offscreen-resolve",
            .swapchain_recreate => "swapchain-recreate",
            .uniform_black => "uniform-black",
            .nonzero_pcm => "nonzero-pcm",
            .intentional_silence => "intentional-silence",
            .xma_unsupported => "xma-unsupported",
            .loader_search => "loader-search",
            .tls_callback => "tls-callback",
            .wait_timeout => "wait-timeout",
            .abi_callback => "abi-callback",
            .registry_profile => "registry-profile",
            .com_apartment => "com-apartment",
            .socket_offline => "socket-offline",
            .window_resize => "window-resize",
        };
    }
};

pub const profile_count: usize = @typeInfo(ApplicationProfile).@"enum".fields.len;
pub const fixture_count: usize = @typeInfo(FixtureKind).@"enum".fields.len;

pub const ProfileRow = struct {
    profile: ApplicationProfile = .xenia_guest,
    graphics_supported: bool = false,
    audio_supported: bool = false,
    fixtures: u64 = 0,
    required_fixtures: u64 = 0,
    refusal: []const u8 = "",

    pub fn ready(self: ProfileRow) bool {
        return self.graphics_supported and
            (self.required_fixtures & ~self.fixtures) == 0;
    }
};

pub const ReleaseMatrix = struct {
    profiles: [profile_count]ProfileRow = [_]ProfileRow{.{}} ** profile_count,
    profile_initialized: [profile_count]bool = [_]bool{false} ** profile_count,
    artifacts_expected: u32 = 0,
    artifacts_present: u32 = 0,
    artifacts_mismatched: u32 = 0,

    pub fn init(self: *ReleaseMatrix) void {
        for (&self.profiles, 0..) |*row, index| row.* = .{ .profile = @enumFromInt(index) };
        self.profile_initialized = [_]bool{true} ** profile_count;
    }

    pub fn requireFixture(self: *ReleaseMatrix, profile: ApplicationProfile, fixture: FixtureKind) void {
        self.profiles[@intFromEnum(profile)].required_fixtures |= fixtureBit(fixture);
    }

    pub fn recordFixture(self: *ReleaseMatrix, profile: ApplicationProfile, fixture: FixtureKind) void {
        self.profiles[@intFromEnum(profile)].fixtures |= fixtureBit(fixture);
    }

    pub fn configure(
        self: *ReleaseMatrix,
        profile: ApplicationProfile,
        graphics_supported: bool,
        audio_supported: bool,
        refusal: []const u8,
    ) void {
        self.profiles[@intFromEnum(profile)].graphics_supported = graphics_supported;
        self.profiles[@intFromEnum(profile)].audio_supported = audio_supported;
        self.profiles[@intFromEnum(profile)].refusal = refusal;
    }

    pub fn admit(self: *const ReleaseMatrix, profile: ApplicationProfile) AdmissionVerdict {
        const row = self.profiles[@intFromEnum(profile)];
        if (!self.profile_initialized[@intFromEnum(profile)]) return .identity_mismatch;
        if (profile == .unsupported_protected) return .refused_profile;
        if (!row.graphics_supported) return .refused_capability;
        if (!row.ready()) return .needs_fixture;
        return .admitted;
    }

    pub fn artifactsReady(self: ReleaseMatrix) bool {
        return self.artifacts_expected == self.artifacts_present and self.artifacts_mismatched == 0;
    }
};

fn fixtureBit(fixture: FixtureKind) u64 {
    return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(fixture)));
}

pub const PhaseStatus = enum(u8) {
    unverified,
    verified,
    blocked,
    profiled,

    pub fn label(self: PhaseStatus) []const u8 {
        return switch (self) {
            .unverified => "unverified",
            .verified => "verified",
            .blocked => "blocked",
            .profiled => "profiled",
        };
    }
};

/// The aggregate is intentionally usable in synthetic/replay tests without
/// touching a host window, Xenia, Vulkan, or a filesystem.
pub const Audit = struct {
    identity: Identity = .{},
    events: EventLedger = .{},
    entities: EntityLedger = .{},
    capabilities: CapabilityLedger = .{},
    waits: WaitLedger = .{},
    memory: MemoryLedger = .{},
    modules: ModuleLedger = .{},
    frames: FrameLedger = .{},
    services: ServiceLedger = .{},
    audio: AudioLedger = .{},
    window: WindowAuthority = .{},
    performance: PerformanceLedger = .{},
    release: ReleaseMatrix = .{},

    pub fn phaseStatus(self: *const Audit, phase: Phase) PhaseStatus {
        return switch (phase) {
            .contract_evidence => if (!self.identity.intact() or !self.events.lossless() or !self.capabilities.requiredReady()) .blocked else .verified,
            .runtime_liveness => if (self.entities.invalid_operations != 0 or self.waits.invalid_operations != 0 or self.memory.invalid_accesses != 0 or !self.memory.lossless() or !self.modules.ready()) .blocked else .verified,
            .graphics_semantics => if (self.frames.count == 0) .unverified else if (self.frames.validContentCount() != 0) .verified else .blocked,
            .media_ui_services => if (!self.services.requiredReady()) .blocked else if (self.audio.verdict() == .decoder_gap or self.audio.verdict() == .device_gap) .profiled else .verified,
            .performance_observer => if (!self.performance.withinBudget()) .blocked else .verified,
            .release_profiles => if (!self.release.artifactsReady()) .unverified else if (self.release.admit(.xenia_guest) == .admitted) .verified else .profiled,
        };
    }

    pub fn authenticReady(self: *const Audit) bool {
        inline for ([_]Phase{
            .contract_evidence,
            .runtime_liveness,
            .graphics_semantics,
            .performance_observer,
        }) |phase| {
            if (self.phaseStatus(phase) != .verified) return false;
        }
        return self.identity.profile == .authentic and self.identity.intact();
    }
};

test "phase descriptors cover all six implementation phases" {
    try std.testing.expectEqual(phase_count, phase_descriptors.len);
    for (phase_descriptors, 0..) |descriptor, index| {
        try std.testing.expectEqual(@as(Phase, @enumFromInt(index)), descriptor.phase);
        try std.testing.expect(descriptor.label.len != 0);
        try std.testing.expect(descriptor.owner.len != 0);
        try std.testing.expect(descriptor.acceptance.len != 0);
    }
}

test "identity seals content fields and rejects late mutation" {
    var identity = Identity.init(1, .authentic);
    for (@typeInfo(IdentityField).@"enum".fields, 0..) |_, index| {
        try std.testing.expect(identity.set(@enumFromInt(index), @as(Hash, @intCast(index + 10))));
    }
    try std.testing.expect(identity.seal());
    const before = identity.seal_hash;
    try std.testing.expect(!identity.set(.media, 99));
    try std.testing.expectEqual(before, identity.seal_hash);
    try std.testing.expectEqual(@as(u64, 1), identity.late_mutations);
    try std.testing.expect(identity.intact());
}

test "event authority retains parent identity and reports bounded loss" {
    var ledger = EventLedger{};
    ledger.open(9);
    const entity = EntityId{ .kind = .frame, .value = 1, .generation = 1 };
    const parent = ledger.append(.{ .phase = .contract_evidence, .kind = .run_open, .authority = .direct, .entity = entity }).?;
    const child = ledger.append(.{ .phase = .graphics_semantics, .kind = .frame_begin, .authority = .witness, .entity = entity, .parent_event = parent }).?;
    try std.testing.expectEqual(@as(Hash, parent + 1), child);
    try std.testing.expect(ledger.append(.{ .phase = .graphics_semantics, .kind = .frame_stage, .authority = .direct, .parent_event = 999 }) == null);
    try std.testing.expectEqual(@as(u64, 1), ledger.dropped);
    try std.testing.expect(!ledger.lossless());
}

test "entity generations prevent late use after destruction" {
    var ledger = EntityLedger{};
    const old = EntityId{ .kind = .gpu_object, .value = 7, .generation = 1 };
    const next = EntityId{ .kind = .gpu_object, .value = 7, .generation = 2 };
    try std.testing.expect(ledger.create(old, .rosette_gpu, 1));
    try std.testing.expect(ledger.use(old, 2));
    try std.testing.expect(ledger.destroy(old, 3));
    try std.testing.expect(!ledger.use(old, 4));
    try std.testing.expect(ledger.create(next, .rosette_gpu, 5));
    try std.testing.expect(ledger.use(next, 6));
    try std.testing.expectEqual(@as(u64, 1), ledger.invalid_operations);
}

test "required capability refusals are not silently healthy" {
    var ledger = CapabilityLedger{};
    try std.testing.expect(ledger.record(.{
        .id = 1,
        .name = "vulkan-loader",
        .owner = .rosette_gpu,
        .requirement = .required,
        .state = .available,
        .evidence_event = 1,
    }));
    try std.testing.expect(ledger.requiredReady());
    try std.testing.expect(ledger.record(.{
        .id = 1,
        .name = "vulkan-loader",
        .owner = .rosette_gpu,
        .requirement = .required,
        .state = .refused,
        .fallback = "diagnostic-only",
        .return_code = -1,
    }));
    try std.testing.expect(!ledger.requiredReady());
}

test "wait evidence distinguishes optional polling from a missing producer" {
    var waits = WaitLedger{};
    const waiter = EntityId{ .kind = .thread, .value = 1, .generation = 1 };
    const object = EntityId{ .kind = .wait, .value = 2, .generation = 1 };
    const wait_id = EntityId{ .kind = .wait, .value = 3, .generation = 1 };
    try std.testing.expect(waits.begin(wait_id, waiter, object, .{}, 100, true, 1));
    try std.testing.expect(waits.timeout(wait_id, 2));
    try std.testing.expectEqual(WaitVerdict.optional_poll_timeout, waits.find(wait_id).?.verdict());
    const blocked_id = EntityId{ .kind = .wait, .value = 4, .generation = 1 };
    const producer = EntityId{ .kind = .service, .value = 5, .generation = 1 };
    try std.testing.expect(waits.begin(blocked_id, waiter, object, producer, 200, false, 3));
    try std.testing.expectEqual(WaitVerdict.blocked, waits.find(blocked_id).?.verdict());
    try std.testing.expect(waits.signal(blocked_id, producer, 4));
    try std.testing.expectEqual(WaitVerdict.signaled_not_resumed, waits.find(blocked_id).?.verdict());
    try std.testing.expect(waits.@"resume"(blocked_id, 5));
    try std.testing.expectEqual(WaitVerdict.completed, waits.find(blocked_id).?.verdict());
}

test "memory relocation overflow is visible and never looks lossless" {
    var memory = MemoryLedger{};
    const id = EntityId{ .kind = .memory, .value = 1, .generation = 1 };
    try std.testing.expect(memory.map(.{ .id = id, .address_space = .guest, .base = 0x1000, .size = 0x1000, .owner = .guest }));
    try std.testing.expect(memory.access(0x1001, true));
    try std.testing.expectEqual(AddressSpace.guest, memory.classify(0x1001));
    var index: usize = 0;
    while (index < MemoryLedger.relocation_capacity) : (index += 1) {
        try std.testing.expect(memory.addRelocation(.{ .site = index + 1, .target = index + 2, .generation = 1 }));
    }
    try std.testing.expect(!memory.addRelocation(.{ .site = 9, .target = 10, .generation = 1 }));
    try std.testing.expect(memory.relocation_overflow != 0);
    try std.testing.expect(!memory.lossless());
}

test "module load and TLS attach have an ordering contract" {
    var modules = ModuleLedger{};
    const id = EntityId{ .kind = .module, .value = 1, .generation = 1 };
    try std.testing.expect(modules.declare(.{ .id = id, .name = "game.exe", .content_hash = 9 }));
    try std.testing.expect(!modules.noteTlsAttach(id, 1));
    try std.testing.expect(!modules.ready());
    modules = ModuleLedger{};
    try std.testing.expect(modules.declare(.{ .id = id, .name = "game.exe", .content_hash = 9 }));
    try std.testing.expect(modules.load(id));
    try std.testing.expect(modules.noteTlsAttach(id, 1));
    try std.testing.expect(modules.ready());
}

test "frame provenance classifies the black sample at its first missing edge" {
    var frames = FrameLedger{};
    const token = FrameToken{ .run_id = 1, .frame_id = 1, .swapchain_generation = 1, .image_id = 9 };
    try std.testing.expect(frames.begin(token, 1));
    try std.testing.expect(frames.stage(token, .guest_swap, 2));
    try std.testing.expect(frames.stage(token, .acquired_image, 3));
    try std.testing.expect(frames.stage(token, .command_recorded, 4));
    try std.testing.expect(frames.stage(token, .attachment_bound, 5));
    try std.testing.expect(frames.noteTarget(token, 9, 10));
    try std.testing.expect(frames.noteSource(token, .clear));
    try std.testing.expect(frames.stage(token, .store_or_resolve, 6));
    try std.testing.expect(frames.noteShader(token, 11, true));
    try std.testing.expect(frames.stage(token, .shader_output, 7));
    try std.testing.expect(frames.stage(token, .layout_visible, 8));
    try std.testing.expect(frames.noteLayout(token, true));
    try std.testing.expect(frames.stage(token, .submitted, 9));
    try std.testing.expect(frames.stage(token, .gpu_complete, 10));
    try std.testing.expect(frames.stage(token, .readback, 11));
    try std.testing.expect(frames.notePixel(token, .uniform_black, 12));
    try std.testing.expect(frames.stage(token, .present, 13));
    try std.testing.expect(frames.stage(token, .paint, 14));
    try std.testing.expectEqual(FrameVerdict.title_black, frames.find(token).?.verdict());
}

test "frame with a wrong target cannot earn content validity" {
    var frames = FrameLedger{};
    const token = FrameToken{ .run_id = 1, .frame_id = 2, .swapchain_generation = 1, .image_id = 9 };
    try std.testing.expect(frames.begin(token, 1));
    try std.testing.expect(frames.stage(token, .guest_swap, 2));
    try std.testing.expect(frames.stage(token, .acquired_image, 3));
    try std.testing.expect(frames.stage(token, .command_recorded, 4));
    try std.testing.expect(frames.stage(token, .attachment_bound, 5));
    try std.testing.expect(frames.noteTarget(token, 8, 10));
    try std.testing.expectEqual(FrameVerdict.wrong_target, frames.find(token).?.verdict());
}

test "audio ledger separates title silence from XMA decoder absence" {
    var audio = AudioLedger{};
    try std.testing.expectEqual(AudioVerdict.no_title_submission, audio.verdict());
    audio.submitted_frames = 4;
    try std.testing.expectEqual(AudioVerdict.title_silence, audio.verdict());
    audio.xma_programmed = 1;
    try std.testing.expectEqual(AudioVerdict.decoder_gap, audio.verdict());
    audio.xma_decoded = 1;
    audio.nonzero_frames = 1;
    audio.device_callbacks = 1;
    audio.delivered_bytes = 8;
    try std.testing.expectEqual(AudioVerdict.audible, audio.verdict());
}

test "window authority tracks generations and contested owners" {
    var window = WindowAuthority{};
    try std.testing.expect(window.observe(.rosette_startup, 1280, 720, 100));
    try std.testing.expect(window.stabilize());
    try std.testing.expect(window.validFor(1280, 720));
    try std.testing.expect(window.observe(.guest, 1280, 720, 100));
    try std.testing.expect(!window.stabilized);
    try std.testing.expect(window.contested);
    try std.testing.expect(!window.stabilize());
}

test "performance ledger exposes observer budget breaches and dominant phase" {
    var performance = PerformanceLedger{};
    performance.setBudget(.observer, 10);
    performance.spend(.translation, 100);
    performance.spend(.observer, 11);
    try std.testing.expect(!performance.withinBudget());
    try std.testing.expectEqual(@as(u64, 9), performance.observerPercent());
    try std.testing.expectEqual(PerfPhase.translation, performance.dominant().?);
}

test "release matrix admits only a profiled and fixture-complete route" {
    var release = ReleaseMatrix{};
    release.init();
    release.configure(.xenia_guest, true, true, "");
    release.requireFixture(.xenia_guest, .known_color_draw);
    release.requireFixture(.xenia_guest, .offscreen_resolve);
    try std.testing.expectEqual(AdmissionVerdict.needs_fixture, release.admit(.xenia_guest));
    release.recordFixture(.xenia_guest, .known_color_draw);
    release.recordFixture(.xenia_guest, .offscreen_resolve);
    release.artifacts_expected = 2;
    release.artifacts_present = 2;
    try std.testing.expectEqual(AdmissionVerdict.admitted, release.admit(.xenia_guest));
    try std.testing.expectEqual(AdmissionVerdict.refused_profile, release.admit(.unsupported_protected));
}

test "aggregate authentic readiness remains fail closed on black or missing evidence" {
    var audit = Audit{};
    audit.identity = Identity.init(1, .authentic);
    for (@typeInfo(IdentityField).@"enum".fields, 0..) |_, index| {
        _ = audit.identity.set(@enumFromInt(index), @as(Hash, @intCast(index + 1)));
    }
    try std.testing.expect(audit.identity.seal());
    audit.events.open(1);
    _ = audit.events.append(.{ .phase = .contract_evidence, .kind = .run_open, .authority = .direct });
    try std.testing.expect(!audit.authenticReady());
    try std.testing.expectEqual(PhaseStatus.unverified, audit.phaseStatus(.graphics_semantics));
}
