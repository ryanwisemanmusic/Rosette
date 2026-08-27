//! Mutable Cocoa graphics ownership and handoff ledger.
//!
//! The compile-time contract says who may own or borrow each resource. This
//! runtime ledger gives those rules identity and time: the same CAMetalLayer
//! observed by Cocoa and borrowed by Vulkan is healthy, while two different
//! layers both called "the surface" are a conflict that quarantines fallback
//! presentation instead of selecting whichever report ran last.

const std = @import("std");
const contract = @import("cocoa_graphics_control_contract");

pub const Domain = contract.Domain;
pub const Resource = contract.Resource;
pub const Authority = contract.Authority;
pub const Evidence = contract.Evidence;
pub const Stage = contract.Stage;
pub const Route = contract.Route;
pub const RoutePolicy = contract.RoutePolicy;

pub const ResourceState = enum(u8) {
    unseen,
    observed,
    ready,
    failed,
    revoked,
    contested,

    pub fn label(self: ResourceState) []const u8 {
        return switch (self) {
            .unseen => "unseen",
            .observed => "observed",
            .ready => "ready",
            .failed => "failed",
            .revoked => "revoked",
            .contested => "CONTESTED",
        };
    }

    pub fn usable(self: ResourceState) bool {
        return self == .ready;
    }
};

pub const ResourceRecord = struct {
    resource: Resource,
    state: ResourceState = .unseen,
    identity: u64 = 0,
    generation: u64 = 0,
    canonical_owner: Domain,
    custodian: Domain,
    evidence: Evidence = .none,
    providers: u16 = 0,
    borrowers: u16 = 0,
    observers: u16 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    observations: u64 = 0,
    conflicts: u64 = 0,

    fn init(resource: Resource) ResourceRecord {
        const owner = resource.expectedOwner();
        return .{
            .resource = resource,
            .canonical_owner = owner,
            .custodian = owner,
        };
    }

    pub fn borrowedBy(self: ResourceRecord, domain: Domain) bool {
        return self.borrowers & contract.domainBit(domain) != 0;
    }
};

pub const Observation = struct {
    resource: Resource,
    identity: u64,
    generation: u64 = 0,
    actor: Domain,
    authority: Authority,
    evidence: Evidence,
    ready: bool = true,
    step: u64 = 0,
};

pub const ObservationResult = enum(u8) {
    accepted,
    accumulated,
    borrowed,
    provider_registered,
    observed_only,
    ignored_weaker,
    rejected_zero_identity,
    rejected_owner,
    rejected_borrower,
    identity_conflict,

    pub fn label(self: ObservationResult) []const u8 {
        return switch (self) {
            .accepted => "accepted",
            .accumulated => "accumulated",
            .borrowed => "borrowed",
            .provider_registered => "provider-registered",
            .observed_only => "observed-only",
            .ignored_weaker => "ignored-weaker",
            .rejected_zero_identity => "rejected-zero-identity",
            .rejected_owner => "rejected-owner",
            .rejected_borrower => "rejected-borrower",
            .identity_conflict => "IDENTITY-CONFLICT",
        };
    }
};

pub const StageState = enum(u8) {
    untested,
    observed,
    ready,
    failed,
    revoked,

    pub fn label(self: StageState) []const u8 {
        return switch (self) {
            .untested => "untested",
            .observed => "observed",
            .ready => "ready",
            .failed => "failed",
            .revoked => "revoked",
        };
    }
};

pub const StageRecord = struct {
    state: StageState = .untested,
    owner: Domain = .unknown,
    evidence: Evidence = .none,
    identity: u64 = 0,
    generation: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    observations: u64 = 0,
    owner_conflicts: u64 = 0,
};

pub const ConflictKind = enum(u8) {
    resource_identity,
    wrong_owner,
    invalid_borrower,
    illegal_transfer,
    handoff_identity,
    presenter_lease,
    stage_owner,

    pub fn label(self: ConflictKind) []const u8 {
        return switch (self) {
            .resource_identity => "resource-identity",
            .wrong_owner => "wrong-owner",
            .invalid_borrower => "invalid-borrower",
            .illegal_transfer => "illegal-transfer",
            .handoff_identity => "handoff-identity",
            .presenter_lease => "presenter-lease",
            .stage_owner => "stage-owner",
        };
    }
};

pub const Conflict = struct {
    sequence: u64 = 0,
    kind: ConflictKind = .resource_identity,
    resource: Resource = .appkit_application,
    expected_owner: Domain = .unknown,
    actor: Domain = .unknown,
    expected_identity: u64 = 0,
    observed_identity: u64 = 0,
    generation: u64 = 0,
    step: u64 = 0,
};

pub const max_conflicts: usize = 32;
pub const max_handoffs: usize = 32;

pub const HandoffState = enum(u8) {
    empty,
    offered,
    accepted,
    completed,
    refused,
    expired,

    pub fn label(self: HandoffState) []const u8 {
        return switch (self) {
            .empty => "empty",
            .offered => "offered",
            .accepted => "accepted",
            .completed => "completed",
            .refused => "refused",
            .expired => "expired",
        };
    }
};

pub const Handoff = struct {
    token: u64 = 0,
    resource: Resource = .guest_frame,
    identity: u64 = 0,
    generation: u64 = 0,
    from: Domain = .unknown,
    to: Domain = .unknown,
    state: HandoffState = .empty,
    offered_step: u64 = 0,
    accepted_step: u64 = 0,
    completed_step: u64 = 0,
};

pub const PresenterLease = struct {
    active: bool = false,
    holder: Domain = .unknown,
    generation: u64 = 0,
    acquired_step: u64 = 0,
    renewed_step: u64 = 0,
    acquisitions: u64 = 0,
    renewals: u64 = 0,
    releases: u64 = 0,
    conflicts: u64 = 0,
};

pub const Summary = struct {
    ready_resources: usize = 0,
    contested_resources: usize = 0,
    ready_stages: usize = 0,
    failed_stages: usize = 0,
    ownership_conflicts: u64 = 0,
    handoffs_offered: u64 = 0,
    handoffs_completed: u64 = 0,
    handoffs_refused: u64 = 0,
    lease_holder: Domain = .unknown,
    route: Route = .wait,
};

pub const ControlPlane = struct {
    resources: [@typeInfo(Resource).@"enum".fields.len]ResourceRecord = initResources(),
    stages: [contract.stage_count]StageRecord = [_]StageRecord{.{}} ** contract.stage_count,
    conflicts: [max_conflicts]Conflict = [_]Conflict{.{}} ** max_conflicts,
    conflict_count: usize = 0,
    conflict_next: usize = 0,
    conflicts_total: u64 = 0,
    handoffs: [max_handoffs]Handoff = [_]Handoff{.{}} ** max_handoffs,
    handoff_count: usize = 0,
    handoff_next: usize = 0,
    handoffs_total: u64 = 0,
    handoffs_completed: u64 = 0,
    handoffs_refused: u64 = 0,
    next_token: u64 = 1,
    presenter: PresenterLease = .{},
    policy: RoutePolicy = .observe_only,
    last_route: Route = .wait,
    route_observations: u64 = 0,

    pub fn observeResource(self: *ControlPlane, observation: Observation) ObservationResult {
        const record = &self.resources[@intFromEnum(observation.resource)];
        record.observations +|= 1;
        if (record.first_step == 0 and observation.step != 0) record.first_step = observation.step;
        if (observation.step > record.last_step) record.last_step = observation.step;

        if (observation.identity == 0 and observation.authority != .observer) {
            return .rejected_zero_identity;
        }

        switch (observation.authority) {
            .observer => {
                record.observers |= contract.domainBit(observation.actor);
                return .observed_only;
            },
            .borrower => {
                if (!contract.mayBorrow(observation.resource, observation.actor)) {
                    self.recordConflict(.invalid_borrower, observation, record.identity);
                    return .rejected_borrower;
                }
                if (record.identity != 0 and record.identity != observation.identity and record.resource.singleton()) {
                    record.state = .contested;
                    record.conflicts +|= 1;
                    self.recordConflict(.resource_identity, observation, record.identity);
                    return .identity_conflict;
                }
                record.borrowers |= contract.domainBit(observation.actor);
                if ((record.identity == 0 or !record.resource.singleton() and observation.generation >= record.generation) and
                    observation.evidence.provesIdentity())
                {
                    record.identity = observation.identity;
                    record.generation = observation.generation;
                    record.evidence = observation.evidence;
                    record.state = if (observation.ready) .observed else .failed;
                }
                return .borrowed;
            },
            .provider => {
                record.providers |= contract.domainBit(observation.actor);
                if (record.identity != 0 and record.identity != observation.identity and record.resource.singleton()) {
                    record.state = .contested;
                    record.conflicts +|= 1;
                    self.recordConflict(.resource_identity, observation, record.identity);
                    return .identity_conflict;
                }
                if ((record.identity == 0 or !record.resource.singleton() and observation.generation >= record.generation) and
                    observation.evidence.provesIdentity())
                {
                    record.identity = observation.identity;
                    record.generation = observation.generation;
                    record.evidence = observation.evidence;
                    record.state = if (observation.ready) .ready else .failed;
                }
                return .provider_registered;
            },
            .canonical_owner => {
                if (observation.actor != record.canonical_owner) {
                    self.recordConflict(.wrong_owner, observation, record.identity);
                    return .rejected_owner;
                }
            },
            .diagnostic_substitute => {
                if (observation.actor != .rosette_runtime or observation.resource != .diagnostic_frame) {
                    self.recordConflict(.wrong_owner, observation, record.identity);
                    return .rejected_owner;
                }
            },
        }

        if (record.identity != 0 and record.identity != observation.identity and record.resource.singleton()) {
            record.state = .contested;
            record.conflicts +|= 1;
            self.recordConflict(.resource_identity, observation, record.identity);
            return .identity_conflict;
        }
        if (@intFromEnum(observation.evidence) < @intFromEnum(record.evidence)) return .ignored_weaker;
        const was_known = record.identity != 0;
        record.identity = observation.identity;
        record.generation = observation.generation;
        record.evidence = observation.evidence;
        record.state = if (observation.ready) .ready else .failed;
        record.custodian = observation.actor;
        return if (was_known) .accumulated else .accepted;
    }

    pub fn recordStage(
        self: *ControlPlane,
        stage: Stage,
        state: StageState,
        actor: Domain,
        evidence: Evidence,
        identity: u64,
        generation: u64,
        step: u64,
    ) bool {
        if (state == .untested) return false;
        const entry = &self.stages[@intFromEnum(stage)];
        entry.observations +|= 1;
        if (entry.first_step == 0 and step != 0) entry.first_step = step;
        if (step > entry.last_step) entry.last_step = step;
        const expected = stage.expectedOwner();
        if (actor != expected) {
            entry.owner_conflicts +|= 1;
            self.recordStageConflict(stage, actor, identity, generation, step);
            return false;
        }
        if (@intFromEnum(evidence) < @intFromEnum(entry.evidence) and entry.state == .ready) return false;
        entry.state = state;
        entry.owner = actor;
        entry.evidence = evidence;
        entry.identity = identity;
        entry.generation = generation;
        return true;
    }

    pub fn stageReady(self: *const ControlPlane, stage: Stage) bool {
        return self.stages[@intFromEnum(stage)].state == .ready;
    }

    pub fn resource(self: *const ControlPlane, which: Resource) *const ResourceRecord {
        return &self.resources[@intFromEnum(which)];
    }

    pub fn cocoaReady(self: *const ControlPlane) bool {
        return self.stageReady(.application_ready) and
            self.stageReady(.window_ready) and
            self.stageReady(.content_view_ready) and
            self.stageReady(.metal_layer_ready) and
            self.stageReady(.metal_device_ready);
    }

    pub fn rosetteVulkanReady(self: *const ControlPlane) bool {
        return self.stageReady(.rosette_vulkan_instance_ready) and
            self.stageReady(.rosette_vulkan_surface_ready) and
            self.stageReady(.rosette_vulkan_device_ready) and
            self.stageReady(.rosette_vulkan_queue_ready) and
            self.stageReady(.rosette_vulkan_swapchain_ready);
    }

    pub fn hasConflict(self: *const ControlPlane) bool {
        if (self.conflicts_total != 0 or self.presenter.conflicts != 0) return true;
        for (self.resources) |record| if (record.state == .contested) return true;
        return false;
    }

    pub fn beginHandoff(
        self: *ControlPlane,
        resource_value: Resource,
        identity: u64,
        generation: u64,
        from: Domain,
        to: Domain,
        step: u64,
    ) ?u64 {
        const record = &self.resources[@intFromEnum(resource_value)];
        if (!resource_value.transferable()) {
            self.recordTransferConflict(.illegal_transfer, resource_value, from, identity, record.identity, generation, step);
            self.handoffs_refused +|= 1;
            return null;
        }
        if (identity == 0 or record.identity != 0 and record.identity != identity or record.custodian != from) {
            self.recordTransferConflict(.handoff_identity, resource_value, from, identity, record.identity, generation, step);
            self.handoffs_refused +|= 1;
            return null;
        }
        for (self.handoffs[0..self.handoff_count]) |handoff| {
            if (handoff.resource == resource_value and handoff.identity == identity and
                (handoff.state == .offered or handoff.state == .accepted))
                return null;
        }
        const token = self.next_token;
        self.next_token +|= 1;
        if (self.next_token == 0) self.next_token = 1;
        self.storeHandoff(.{
            .token = token,
            .resource = resource_value,
            .identity = identity,
            .generation = generation,
            .from = from,
            .to = to,
            .state = .offered,
            .offered_step = step,
        });
        self.handoffs_total +|= 1;
        return token;
    }

    pub fn acceptHandoff(self: *ControlPlane, token: u64, actor: Domain, step: u64) bool {
        const handoff = self.findHandoff(token) orelse return false;
        if (handoff.state != .offered or handoff.to != actor) {
            self.handoffs_refused +|= 1;
            return false;
        }
        handoff.state = .accepted;
        handoff.accepted_step = step;
        return true;
    }

    pub fn completeHandoff(self: *ControlPlane, token: u64, actor: Domain, step: u64) bool {
        const handoff = self.findHandoff(token) orelse return false;
        if (handoff.state != .accepted or handoff.to != actor) {
            self.handoffs_refused +|= 1;
            return false;
        }
        const record = &self.resources[@intFromEnum(handoff.resource)];
        if (record.identity != 0 and record.identity != handoff.identity) {
            handoff.state = .refused;
            self.handoffs_refused +|= 1;
            return false;
        }
        record.identity = handoff.identity;
        record.generation = handoff.generation;
        record.custodian = actor;
        record.state = .ready;
        handoff.state = .completed;
        handoff.completed_step = step;
        self.handoffs_completed +|= 1;
        return true;
    }

    pub fn acquirePresenter(self: *ControlPlane, holder: Domain, generation: u64, step: u64) bool {
        if (holder != .xenia_vulkan and holder != .rosette_runtime) return false;
        if (!self.presenter.active) {
            self.presenter.active = true;
            self.presenter.holder = holder;
            self.presenter.generation = generation;
            self.presenter.acquired_step = step;
            self.presenter.renewed_step = step;
            self.presenter.acquisitions +|= 1;
            return true;
        }
        if (self.presenter.holder == holder and self.presenter.generation == generation) {
            self.presenter.renewed_step = step;
            self.presenter.renewals +|= 1;
            return true;
        }
        self.presenter.conflicts +|= 1;
        self.recordTransferConflict(
            .presenter_lease,
            .presentation_sink,
            holder,
            generation,
            self.presenter.generation,
            generation,
            step,
        );
        return false;
    }

    pub fn releasePresenter(self: *ControlPlane, holder: Domain, generation: u64) bool {
        if (!self.presenter.active or self.presenter.holder != holder or self.presenter.generation != generation) return false;
        self.presenter.active = false;
        self.presenter.holder = .unknown;
        self.presenter.releases +|= 1;
        return true;
    }

    pub fn chooseRoute(self: *ControlPlane, input: contract.RouteInput) Route {
        var effective = input;
        effective.policy = self.policy;
        effective.ownership_conflict = effective.ownership_conflict or self.hasConflict();
        effective.cocoa_ready = effective.cocoa_ready or self.cocoaReady();
        effective.rosette_vulkan_ready = effective.rosette_vulkan_ready or self.rosetteVulkanReady();
        const route = contract.decideRoute(effective);
        self.last_route = route;
        self.route_observations +|= 1;
        return route;
    }

    pub fn summary(self: *const ControlPlane) Summary {
        var result = Summary{
            .ownership_conflicts = self.conflicts_total +| self.presenter.conflicts,
            .handoffs_offered = self.handoffs_total,
            .handoffs_completed = self.handoffs_completed,
            .handoffs_refused = self.handoffs_refused,
            .lease_holder = if (self.presenter.active) self.presenter.holder else .unknown,
            .route = self.last_route,
        };
        for (self.resources) |record| {
            if (record.state == .ready) result.ready_resources += 1;
            if (record.state == .contested) result.contested_resources += 1;
        }
        for (self.stages) |stage| switch (stage.state) {
            .ready => result.ready_stages += 1,
            .failed, .revoked => result.failed_stages += 1,
            else => {},
        };
        return result;
    }

    pub fn fingerprint(self: *const ControlPlane) u64 {
        var hash: u64 = 14_695_981_039_346_656_037;
        for (self.resources) |record| {
            hash ^= @intFromEnum(record.state);
            hash *%= 1_099_511_628_211;
            hash ^= record.identity;
            hash *%= 1_099_511_628_211;
            hash ^= record.generation;
            hash *%= 1_099_511_628_211;
            hash ^= record.borrowers;
            hash *%= 1_099_511_628_211;
        }
        for (self.stages) |stage| {
            hash ^= @intFromEnum(stage.state);
            hash *%= 1_099_511_628_211;
        }
        hash ^= self.conflicts_total;
        hash *%= 1_099_511_628_211;
        hash ^= @intFromEnum(self.last_route);
        return hash;
    }

    fn recordConflict(self: *ControlPlane, kind: ConflictKind, observation: Observation, expected_identity: u64) void {
        self.storeConflict(.{
            .kind = kind,
            .resource = observation.resource,
            .expected_owner = observation.resource.expectedOwner(),
            .actor = observation.actor,
            .expected_identity = expected_identity,
            .observed_identity = observation.identity,
            .generation = observation.generation,
            .step = observation.step,
        });
    }

    fn recordStageConflict(self: *ControlPlane, stage: Stage, actor: Domain, identity: u64, generation: u64, step: u64) void {
        self.storeConflict(.{
            .kind = .stage_owner,
            .resource = .presentation_sink,
            .expected_owner = stage.expectedOwner(),
            .actor = actor,
            .observed_identity = identity,
            .generation = generation,
            .step = step,
        });
    }

    fn recordTransferConflict(
        self: *ControlPlane,
        kind: ConflictKind,
        resource_value: Resource,
        actor: Domain,
        observed_identity: u64,
        expected_identity: u64,
        generation: u64,
        step: u64,
    ) void {
        self.storeConflict(.{
            .kind = kind,
            .resource = resource_value,
            .expected_owner = resource_value.expectedOwner(),
            .actor = actor,
            .expected_identity = expected_identity,
            .observed_identity = observed_identity,
            .generation = generation,
            .step = step,
        });
    }

    fn storeConflict(self: *ControlPlane, conflict_value: Conflict) void {
        var stored = conflict_value;
        self.conflicts_total +|= 1;
        stored.sequence = self.conflicts_total;
        self.conflicts[self.conflict_next] = stored;
        self.conflict_next = (self.conflict_next + 1) % max_conflicts;
        if (self.conflict_count < max_conflicts) self.conflict_count += 1;
    }

    fn storeHandoff(self: *ControlPlane, handoff: Handoff) void {
        self.handoffs[self.handoff_next] = handoff;
        self.handoff_next = (self.handoff_next + 1) % max_handoffs;
        if (self.handoff_count < max_handoffs) self.handoff_count += 1;
    }

    fn findHandoff(self: *ControlPlane, token: u64) ?*Handoff {
        for (self.handoffs[0..self.handoff_count]) |*handoff| {
            if (handoff.token == token) return handoff;
        }
        return null;
    }
};

fn initResources() [@typeInfo(Resource).@"enum".fields.len]ResourceRecord {
    var result: [@typeInfo(Resource).@"enum".fields.len]ResourceRecord = undefined;
    inline for (@typeInfo(Resource).@"enum".fields) |field| {
        const resource: Resource = @enumFromInt(field.value);
        result[field.value] = ResourceRecord.init(resource);
    }
    return result;
}

test "Cocoa owns one layer and Vulkan borrows that same identity" {
    var plane = ControlPlane{};
    try std.testing.expectEqual(ObservationResult.accepted, plane.observeResource(.{
        .resource = .metal_layer,
        .identity = 0xCAFE,
        .generation = 1,
        .actor = .cocoa_appkit,
        .authority = .canonical_owner,
        .evidence = .observed_state,
        .step = 10,
    }));
    try std.testing.expectEqual(ObservationResult.borrowed, plane.observeResource(.{
        .resource = .metal_layer,
        .identity = 0xCAFE,
        .generation = 1,
        .actor = .xenia_vulkan,
        .authority = .borrower,
        .evidence = .intercepted_call,
        .step = 20,
    }));
    try std.testing.expect(plane.resource(.metal_layer).borrowedBy(.xenia_vulkan));
    try std.testing.expect(!plane.hasConflict());
}

test "a second layer identity is quarantined rather than selected by recency" {
    var plane = ControlPlane{};
    _ = plane.observeResource(.{
        .resource = .metal_layer,
        .identity = 0x1111,
        .actor = .cocoa_appkit,
        .authority = .canonical_owner,
        .evidence = .observed_state,
    });
    try std.testing.expectEqual(ObservationResult.identity_conflict, plane.observeResource(.{
        .resource = .metal_layer,
        .identity = 0x2222,
        .actor = .rosette_runtime,
        .authority = .borrower,
        .evidence = .completed_call,
    }));
    try std.testing.expect(plane.hasConflict());
    try std.testing.expectEqual(ResourceState.contested, plane.resource(.metal_layer).state);
}

test "successive frame identities advance without contesting the singleton sink" {
    var plane = ControlPlane{};
    try std.testing.expectEqual(ObservationResult.accepted, plane.observeResource(.{
        .resource = .diagnostic_frame,
        .identity = 1,
        .generation = 1,
        .actor = .rosette_runtime,
        .authority = .diagnostic_substitute,
        .evidence = .completed_call,
    }));
    try std.testing.expectEqual(ObservationResult.accumulated, plane.observeResource(.{
        .resource = .diagnostic_frame,
        .identity = 2,
        .generation = 2,
        .actor = .rosette_runtime,
        .authority = .diagnostic_substitute,
        .evidence = .completed_call,
    }));
    try std.testing.expectEqual(@as(u64, 2), plane.resource(.diagnostic_frame).identity);
    try std.testing.expect(!plane.hasConflict());
}

test "non-transferable Cocoa resources cannot be handed off" {
    var plane = ControlPlane{};
    _ = plane.observeResource(.{
        .resource = .metal_layer,
        .identity = 0x100,
        .actor = .cocoa_appkit,
        .authority = .canonical_owner,
        .evidence = .observed_state,
    });
    try std.testing.expect(plane.beginHandoff(.metal_layer, 0x100, 1, .cocoa_appkit, .xenia_vulkan, 10) == null);
    try std.testing.expectEqual(@as(u64, 1), plane.handoffs_refused);
}

test "guest frame custody moves only after explicit acceptance" {
    var plane = ControlPlane{};
    _ = plane.observeResource(.{
        .resource = .guest_frame,
        .identity = 77,
        .generation = 4,
        .actor = .guest_title,
        .authority = .canonical_owner,
        .evidence = .completed_call,
    });
    const token = plane.beginHandoff(.guest_frame, 77, 4, .guest_title, .rosette_runtime, 20).?;
    try std.testing.expectEqual(Domain.guest_title, plane.resource(.guest_frame).custodian);
    try std.testing.expect(plane.acceptHandoff(token, .rosette_runtime, 21));
    try std.testing.expect(plane.completeHandoff(token, .rosette_runtime, 22));
    try std.testing.expectEqual(Domain.rosette_runtime, plane.resource(.guest_frame).custodian);
}

test "one presentation sink cannot have two live holders" {
    var plane = ControlPlane{};
    try std.testing.expect(plane.acquirePresenter(.xenia_vulkan, 3, 100));
    try std.testing.expect(!plane.acquirePresenter(.rosette_runtime, 4, 101));
    try std.testing.expect(plane.hasConflict());
    try std.testing.expectEqual(Domain.xenia_vulkan, plane.presenter.holder);
}

test "stage ownership cannot drift" {
    var plane = ControlPlane{};
    try std.testing.expect(!plane.recordStage(
        .powerpc_callback_returned,
        .ready,
        .rosette_runtime,
        .log_claim,
        0x8219_51F8,
        1,
        10,
    ));
    try std.testing.expectEqual(@as(u64, 1), plane.conflicts_total);
}
