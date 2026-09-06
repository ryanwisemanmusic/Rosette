//! Pass 10 closure contracts.
//!
//! The earlier diagnostic modules deliberately grew around individual
//! symptoms: a journal, a manifest, a coverage board, and a causal replay
//! ledger.  Pass 10 closes the gaps between them.  This file is the small,
//! dependency-free policy layer that every one of those pieces can use:
//! identity is content-based and sealed before guest work, evidence has one
//! owner and a quiescence barrier, producers are authenticated, concurrent
//! events can be reordered without losing their original orders, and an
//! authentic verdict is fail-closed.
//!
//! It does not perform filesystem or GPU I/O.  The native owners feed these
//! records from the exact operation they own.  Keeping the state machines
//! pure makes the negative vectors deterministic and means a passing unit test
//! cannot be mistaken for a live Xenia run.

const std = @import("std");

pub const schema_version: u16 = 1;
pub const Hash = u64;

pub fn hashBytes(bytes: []const u8) Hash {
    var value: Hash = 0xcbf2_9ce4_8422_2325;
    for (bytes) |byte| value = (value ^ byte) *% 0x0100_0000_01B3;
    return if (value == 0) 1 else value;
}

fn mix(value: Hash, next: Hash) Hash {
    return (value ^ next) *% 0x0100_0000_01B3;
}

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

/// Truth is intentionally not a bool.  An unsupported or unavailable owner
/// is useful diagnostic information, but neither is evidence that an event
/// happened.
pub const Truth = enum(u8) {
    observed,
    unsupported,
    unavailable,
    inferred,
    synthetic,
    unknown,

    pub fn label(self: Truth) []const u8 {
        return switch (self) {
            .observed => "observed",
            .unsupported => "unsupported",
            .unavailable => "unavailable",
            .inferred => "inferred",
            .synthetic => "synthetic",
            .unknown => "unknown",
        };
    }

    pub fn authentic(self: Truth) bool {
        return self == .observed;
    }
};

/// These are content identities, never path identities.  A caller that has a
/// path must hash its verified bytes before calling `set`; the path itself is
/// deliberately not representable in this record.
pub const IdentityField = enum(u8) {
    rosette_source_tree,
    rosette_generated_tree,
    xenia_source_tree,
    xenia_fork_tree,
    xenia_base_commit,
    title_xex,
    title_xiso,
    media,
    compiler,
    linker,
    translator,
    generator,
    shell_helper,
    build_graph,
    toolchain,
    backend,
    device,
    driver,
    moltenvk,
    metal,
    semantic_config,
    time_config,
    scheduler_config,
    observer_config,
    admission_config,
    budget_config,
    frontier_config,
    shader_assets,
    vendor_libraries,
    test_manifest,
    shell_update,
};

pub const identity_field_count: usize = @typeInfo(IdentityField).@"enum".fields.len;

pub const Identity = struct {
    values: [identity_field_count]Hash = [_]Hash{0} ** identity_field_count,

    pub fn set(self: *Identity, field: IdentityField, value: Hash) bool {
        if (value == 0) return false;
        self.values[@intFromEnum(field)] = value;
        return true;
    }

    pub fn setContent(self: *Identity, field: IdentityField, bytes: []const u8) bool {
        if (bytes.len == 0) return false;
        return self.set(field, hashBytes(bytes));
    }

    pub fn get(self: Identity, field: IdentityField) Hash {
        return self.values[@intFromEnum(field)];
    }

    pub fn complete(self: Identity) bool {
        for (self.values) |value| if (value == 0) return false;
        return true;
    }

    pub fn fingerprint(self: Identity) Hash {
        var result: Hash = 0xcbf2_9ce4_8422_2325;
        for (self.values, 0..) |value, index| {
            result = mix(result, @as(Hash, @intCast(index)));
            result = mix(result, value);
        }
        return if (result == 0) 1 else result;
    }
};

pub const AdmissionFailure = enum(u8) {
    none,
    run_id_missing,
    identity_incomplete,
    seal_missing,
    seal_tampered,
    profile_not_authentic,
    already_started,

    pub fn label(self: AdmissionFailure) []const u8 {
        return switch (self) {
            .none => "none",
            .run_id_missing => "run-id-missing",
            .identity_incomplete => "identity-incomplete",
            .seal_missing => "seal-missing",
            .seal_tampered => "seal-tampered",
            .profile_not_authentic => "profile-not-authentic",
            .already_started => "already-started",
        };
    }
};

pub const StartVerdict = enum(u8) {
    admitted,
    diagnostic_only,
    refused,

    pub fn label(self: StartVerdict) []const u8 {
        return switch (self) {
            .admitted => "admitted",
            .diagnostic_only => "diagnostic-only",
            .refused => "refused",
        };
    }
};

/// Admission is the first owner in the chain.  Direct field mutation after
/// sealing is detectable through `sealIntact`; mutator APIs also count an
/// attempted late change so a report cannot hide a race as a clean seal.
pub const Admission = struct {
    run_id: Hash = 0,
    profile: Profile = .authentic,
    identity: Identity = .{},
    sealed: bool = false,
    started: bool = false,
    seal_hash: Hash = 0,
    mutation_attempts: u64 = 0,

    pub fn init(run_id: Hash, profile: Profile, identity: Identity) Admission {
        return .{ .run_id = run_id, .profile = profile, .identity = identity };
    }

    pub fn replaceIdentity(self: *Admission, identity: Identity) bool {
        if (self.sealed or self.started) {
            self.mutation_attempts +|= 1;
            return false;
        }
        self.identity = identity;
        return true;
    }

    pub fn seal(self: *Admission) AdmissionFailure {
        if (self.sealed) return if (self.sealIntact()) .none else .seal_tampered;
        if (self.run_id == 0) return .run_id_missing;
        if (!self.identity.complete()) return .identity_incomplete;
        self.seal_hash = self.computeSeal();
        self.sealed = true;
        return .none;
    }

    pub fn sealIntact(self: *const Admission) bool {
        return self.sealed and self.seal_hash != 0 and self.seal_hash == self.computeSeal();
    }

    pub fn requestGuestStart(self: *Admission) StartVerdict {
        if (self.started) return .refused;
        if (self.profile != .authentic) {
            // Diagnostics may run with a deliberately incomplete identity, but
            // the caller receives a separate verdict and cannot feed the
            // authentic gate.
            self.started = true;
            return .diagnostic_only;
        }
        if (!self.sealIntact()) return .refused;
        self.started = true;
        return .admitted;
    }

    pub fn authenticReady(self: *const Admission) bool {
        return self.profile == .authentic and self.started and self.sealIntact();
    }

    fn computeSeal(self: *const Admission) Hash {
        var result = mix(self.run_id, @intFromEnum(self.profile));
        result = mix(result, self.identity.fingerprint());
        return result;
    }
};

pub const ArtifactPolicy = enum(u8) {
    create_exclusive,
    refuse_existing,
    append_existing,
};

pub const ArtifactResult = enum(u8) {
    reserved_new,
    refused_collision,
    reused_existing,
    invalid_identity,
};

/// The default is intentionally exclusive.  This is the policy boundary used
/// by the native artifact creator before it opens a journal.
pub fn reserveArtifact(run_id: Hash, ordinal: u32, exists: bool, policy: ArtifactPolicy) ArtifactResult {
    _ = ordinal;
    if (run_id == 0) return .invalid_identity;
    if (!exists) return .reserved_new;
    return switch (policy) {
        .create_exclusive, .refuse_existing => .refused_collision,
        .append_existing => .reused_existing,
    };
}

pub fn formatArtifactName(buffer: []u8, run_id: Hash, ordinal: u32) ?[]u8 {
    if (run_id == 0) return null;
    return std.fmt.bufPrint(buffer, "run-{x:0>16}-{d}.r3j", .{ run_id, ordinal }) catch null;
}

pub const OwnerState = enum(u8) {
    new,
    running,
    draining,
    committed,
    failed,

    pub fn label(self: OwnerState) []const u8 {
        return switch (self) {
            .new => "new",
            .running => "running",
            .draining => "draining",
            .committed => "committed",
            .failed => "failed",
        };
    }
};

pub const OwnerFailure = enum(u8) {
    none,
    sink_missing,
    producer_active,
    not_draining,
    footer_missing,
    not_durable,
    writer_error,
    partial_write,
    declared_drop,
    unknown_producer,
    duplicate_producer,
    producer_after_drain,

    pub fn label(self: OwnerFailure) []const u8 {
        return switch (self) {
            .none => "none",
            .sink_missing => "sink-missing",
            .producer_active => "producer-active",
            .not_draining => "not-draining",
            .footer_missing => "footer-missing",
            .not_durable => "not-durable",
            .writer_error => "writer-error",
            .partial_write => "partial-write",
            .declared_drop => "declared-drop",
            .unknown_producer => "unknown-producer",
            .duplicate_producer => "duplicate-producer",
            .producer_after_drain => "producer-after-drain",
        };
    }
};

pub const RecoveryState = enum(u8) {
    no_artifact,
    records_only,
    footer_valid,
    durable_footer,
    committed,
    rejected,
};

pub const OwnerRecovery = struct {
    state: RecoveryState = .no_artifact,
    records: u64 = 0,
    declared_drops: u64 = 0,
    writer_errors: u64 = 0,
    partial_writes: u64 = 0,
    active_producers: u32 = 0,
    clean_shutdown: bool = false,
    failure: OwnerFailure = .none,
};

pub const max_producers: usize = 64;

/// One owner serializes reservations and commits.  Producers can be on many
/// native threads, but the state they mutate is deliberately centralized; a
/// footer cannot be emitted while a producer is still inside the owner.
pub const EvidenceOwner = struct {
    run_id: Hash = 0,
    state: OwnerState = .new,
    sink_present: bool = false,
    footer_valid: bool = false,
    footer_durable: bool = false,
    clean_shutdown: bool = false,
    producers: [max_producers]Hash = [_]Hash{0} ** max_producers,
    producer_count: usize = 0,
    records: u64 = 0,
    declared_drops: u64 = 0,
    writer_errors: u64 = 0,
    partial_writes: u64 = 0,
    rejected_calls: u64 = 0,
    last_failure: OwnerFailure = .none,

    pub fn begin(self: *EvidenceOwner, run_id: Hash, sink_present: bool) bool {
        if (self.state != .new or run_id == 0 or !sink_present) {
            self.last_failure = if (!sink_present) .sink_missing else .producer_after_drain;
            return false;
        }
        self.* = .{ .run_id = run_id, .state = .running, .sink_present = true };
        return true;
    }

    pub fn registerProducer(self: *EvidenceOwner, producer_id: Hash) bool {
        if (self.state != .running) {
            self.rejected_calls +|= 1;
            self.last_failure = .producer_after_drain;
            return false;
        }
        if (producer_id == 0) return false;
        if (self.findProducer(producer_id) != null) {
            self.last_failure = .duplicate_producer;
            return false;
        }
        if (self.producer_count == self.producers.len) return false;
        self.producers[self.producer_count] = producer_id;
        self.producer_count += 1;
        return true;
    }

    pub fn unregisterProducer(self: *EvidenceOwner, producer_id: Hash) bool {
        const index = self.findProducer(producer_id) orelse {
            self.last_failure = .unknown_producer;
            return false;
        };
        self.producers[index] = self.producers[self.producer_count - 1];
        self.producers[self.producer_count - 1] = 0;
        self.producer_count -= 1;
        self.last_failure = .none;
        return true;
    }

    pub fn acceptRecord(self: *EvidenceOwner, producer_id: Hash) bool {
        if (self.state != .running) {
            self.rejected_calls +|= 1;
            self.last_failure = .producer_after_drain;
            return false;
        }
        if (self.findProducer(producer_id) == null) {
            self.rejected_calls +|= 1;
            self.last_failure = .unknown_producer;
            return false;
        }
        self.records +|= 1;
        return true;
    }

    pub fn noteDrop(self: *EvidenceOwner, count: u64) void {
        self.declared_drops +|= count;
        self.last_failure = .declared_drop;
    }

    pub fn noteWriterError(self: *EvidenceOwner) void {
        self.writer_errors +|= 1;
        self.last_failure = .writer_error;
    }

    pub fn notePartialWrite(self: *EvidenceOwner) void {
        self.partial_writes +|= 1;
        self.last_failure = .partial_write;
    }

    pub fn beginDrain(self: *EvidenceOwner) bool {
        if (self.state != .running) return false;
        if (self.producer_count != 0) {
            self.last_failure = .producer_active;
            return false;
        }
        self.state = .draining;
        self.last_failure = .none;
        return true;
    }

    pub fn noteFooter(self: *EvidenceOwner, valid: bool) bool {
        if (self.state != .draining) {
            self.last_failure = .not_draining;
            return false;
        }
        self.footer_valid = valid;
        self.last_failure = if (valid) .none else .footer_missing;
        return valid;
    }

    pub fn noteDurableFooter(self: *EvidenceOwner, durable: bool) bool {
        if (self.state != .draining or !self.footer_valid) {
            self.last_failure = .footer_missing;
            return false;
        }
        self.footer_durable = durable;
        self.last_failure = if (durable) .none else .not_durable;
        return durable;
    }

    pub fn commit(self: *EvidenceOwner) bool {
        if (self.state != .draining) {
            self.last_failure = .not_draining;
            return false;
        }
        if (self.producer_count != 0) self.last_failure = .producer_active;
        if (!self.footer_valid) self.last_failure = .footer_missing;
        if (!self.footer_durable) self.last_failure = .not_durable;
        if (self.writer_errors != 0) self.last_failure = .writer_error;
        if (self.partial_writes != 0) self.last_failure = .partial_write;
        if (self.declared_drops != 0) self.last_failure = .declared_drop;
        if (self.last_failure != .none) {
            self.state = .failed;
            return false;
        }
        self.clean_shutdown = true;
        self.state = .committed;
        return true;
    }

    pub fn recovery(self: *const EvidenceOwner) OwnerRecovery {
        const state: RecoveryState = if (self.state == .committed)
            .committed
        else if (self.footer_durable)
            .durable_footer
        else if (self.footer_valid)
            .footer_valid
        else if (self.records != 0)
            .records_only
        else
            .no_artifact;
        return .{
            .state = state,
            .records = self.records,
            .declared_drops = self.declared_drops,
            .writer_errors = self.writer_errors,
            .partial_writes = self.partial_writes,
            .active_producers = @intCast(self.producer_count),
            .clean_shutdown = self.clean_shutdown,
            .failure = self.last_failure,
        };
    }

    pub fn authenticReady(self: *const EvidenceOwner) bool {
        return self.state == .committed and self.clean_shutdown and
            self.footer_valid and self.footer_durable and self.declared_drops == 0 and
            self.writer_errors == 0 and self.partial_writes == 0;
    }

    fn findProducer(self: *const EvidenceOwner, producer_id: Hash) ?usize {
        for (self.producers[0..self.producer_count], 0..) |value, index| {
            if (value == producer_id) return index;
        }
        return null;
    }
};

pub const Producer = enum(u8) {
    guest,
    xenia,
    rosette_control,
    host,
    diagnostic,
    replay,
    unknown,

    pub fn authentic(self: Producer) bool {
        return self == .guest or self == .xenia;
    }
};

pub const Domain = enum(u8) {
    guest,
    kernel,
    command_processor,
    rosette,
    vulkan,
    presenter,
    scheduler,
    unknown,
};

pub const Event = struct {
    run_id: Hash = 0,
    identity_hash: Hash = 0,
    event_id: Hash = 0,
    producer_id: Hash = 0,
    producer_sequence: u64 = 0,
    domain_sequence: u64 = 0,
    parent_event_id: Hash = 0,
    correlation_id: Hash = 0,
    guest_step: u64 = 0,
    host_monotonic_ns: u64 = 0,
    guest_thread: u64 = 0,
    host_thread: u64 = 0,
    guest_pc: u64 = 0,
    host_rip: u64 = 0,
    expected: Hash = 0,
    actual: Hash = 0,
    payload_length: u32 = 0,
    payload_digest: Hash = 0,
    state_digest: Hash = 0,
    effect_digest: Hash = 0,
    producer_token: Hash = 0,
    producer: Producer = .unknown,
    domain: Domain = .unknown,
    truth: Truth = .unknown,
};

pub const EventInput = struct {
    domain: Domain = .unknown,
    /// Zero asks the authority to allocate the next domain sequence. A
    /// non-zero value is used by imported/native records and must be
    /// monotonic for that domain.
    domain_sequence: u64 = 0,
    parent_event_id: Hash = 0,
    correlation_id: Hash = 0,
    guest_step: u64 = 0,
    host_monotonic_ns: u64 = 0,
    guest_thread: u64 = 0,
    host_thread: u64 = 0,
    guest_pc: u64 = 0,
    host_rip: u64 = 0,
    expected: Hash = 0,
    actual: Hash = 0,
    state_digest: Hash = 0,
    effect_digest: Hash = 0,
    truth: Truth = .unknown,
};

pub const EmitFailure = enum(u8) {
    none,
    not_started,
    unknown_producer,
    bad_token,
    bad_domain_sequence,
    payload_too_large,
    sequence_overflow,
    capacity,

    pub fn label(self: EmitFailure) []const u8 {
        return switch (self) {
            .none => "none",
            .not_started => "not-started",
            .unknown_producer => "unknown-producer",
            .bad_token => "bad-token",
            .bad_domain_sequence => "bad-domain-sequence",
            .payload_too_large => "payload-too-large",
            .sequence_overflow => "sequence-overflow",
            .capacity => "capacity",
        };
    }
};

const RegisteredProducer = struct {
    id: Hash = 0,
    token: Hash = 0,
    kind: Producer = .unknown,
    last_sequence: u64 = 0,
};

pub const max_event_producers: usize = 32;
pub const EventAuthority = struct {
    run_id: Hash = 0,
    identity_hash: Hash = 0,
    next_event_id: Hash = 1,
    producer_count: usize = 0,
    producers: [max_event_producers]RegisteredProducer = [_]RegisteredProducer{.{}} ** max_event_producers,
    last_domain_sequence: [@typeInfo(Domain).@"enum".fields.len]u64 = [_]u64{0} ** @typeInfo(Domain).@"enum".fields.len,
    started: bool = false,

    pub fn init(run_id: Hash, identity_hash: Hash) EventAuthority {
        return .{ .run_id = run_id, .identity_hash = identity_hash, .started = run_id != 0 and identity_hash != 0 };
    }

    pub fn registerProducer(self: *EventAuthority, producer_id: Hash, kind: Producer) ?Hash {
        if (!self.started or producer_id == 0 or kind == .unknown or self.producer_count == self.producers.len) return null;
        if (self.find(producer_id) != null) return null;
        const token = producerToken(self.identity_hash, self.run_id, producer_id);
        self.producers[self.producer_count] = .{ .id = producer_id, .token = token, .kind = kind };
        self.producer_count += 1;
        return token;
    }

    pub fn emit(self: *EventAuthority, producer_id: Hash, token: Hash, input: EventInput, payload: []const u8) struct { event: ?Event, failure: EmitFailure } {
        const producer_index = self.find(producer_id) orelse return .{ .event = null, .failure = .unknown_producer };
        if (!self.started) return .{ .event = null, .failure = .not_started };
        const producer = &self.producers[producer_index];
        if (producer.token != token) return .{ .event = null, .failure = .bad_token };
        if (payload.len > std.math.maxInt(u32)) return .{ .event = null, .failure = .payload_too_large };
        if (input.domain == .unknown) return .{ .event = null, .failure = .bad_domain_sequence };
        const domain_index = @intFromEnum(input.domain);
        const previous_domain = self.last_domain_sequence[domain_index];
        if (previous_domain == std.math.maxInt(u64)) return .{ .event = null, .failure = .bad_domain_sequence };
        if (input.domain_sequence != 0 and previous_domain != 0 and input.domain_sequence <= previous_domain) return .{ .event = null, .failure = .bad_domain_sequence };
        if (producer.last_sequence == std.math.maxInt(u64) or self.next_event_id == std.math.maxInt(u64)) return .{ .event = null, .failure = .sequence_overflow };
        // Validate every imported sequence before consuming the producer's
        // sequence number. A forged/out-of-order record must not create a
        // second gap in the otherwise valid producer stream.
        producer.last_sequence += 1;
        const domain_sequence = if (input.domain_sequence == 0) previous_domain + 1 else input.domain_sequence;
        const event = Event{
            .run_id = self.run_id,
            .identity_hash = self.identity_hash,
            .event_id = self.next_event_id,
            .producer_id = producer_id,
            .producer_sequence = producer.last_sequence,
            .domain_sequence = domain_sequence,
            .parent_event_id = input.parent_event_id,
            .correlation_id = input.correlation_id,
            .guest_step = input.guest_step,
            .host_monotonic_ns = input.host_monotonic_ns,
            .guest_thread = input.guest_thread,
            .host_thread = input.host_thread,
            .guest_pc = input.guest_pc,
            .host_rip = input.host_rip,
            .expected = input.expected,
            .actual = input.actual,
            .payload_length = @intCast(payload.len),
            .payload_digest = if (payload.len == 0) 0 else hashBytes(payload),
            .state_digest = input.state_digest,
            .effect_digest = input.effect_digest,
            .producer_token = token,
            .producer = producer.kind,
            .domain = input.domain,
            .truth = input.truth,
        };
        self.next_event_id +|= 1;
        self.last_domain_sequence[domain_index] = domain_sequence;
        return .{ .event = event, .failure = .none };
    }

    fn find(self: *const EventAuthority, producer_id: Hash) ?usize {
        for (self.producers[0..self.producer_count], 0..) |producer, index| {
            if (producer.id == producer_id) return index;
        }
        return null;
    }
};

fn producerToken(identity_hash: Hash, run_id: Hash, producer_id: Hash) Hash {
    return mix(mix(identity_hash, run_id), producer_id);
}

pub const ReplayOutcome = enum(u8) {
    accepted,
    not_sealed,
    wrong_run,
    invalid_identity,
    duplicate,
    capacity,
    missing_dependency,
    cycle,
    declared_drop,

    pub fn label(self: ReplayOutcome) []const u8 {
        return switch (self) {
            .accepted => "accepted",
            .not_sealed => "not-sealed",
            .wrong_run => "wrong-run",
            .invalid_identity => "invalid-identity",
            .duplicate => "duplicate",
            .capacity => "capacity",
            .missing_dependency => "missing-dependency",
            .cycle => "cycle",
            .declared_drop => "declared-drop",
        };
    }
};

pub const ReplaySummary = struct {
    staged: u64 = 0,
    ordered: u64 = 0,
    rejected: u64 = 0,
    missing_dependencies: u64 = 0,
    cycles: u64 = 0,
    duplicates: u64 = 0,
    declared_drops: u64 = 0,
};

pub const replay_capacity: usize = 2048;

/// The replay buffer stages arrival order, then performs a stable causal
/// topological sort.  Parent-before-child is a property of the resulting
/// causal order, not a restriction on the order in which threads happened to
/// publish to the sink.
pub const ConcurrentReplay = struct {
    run_id: Hash = 0,
    identity_hash: Hash = 0,
    staged: [replay_capacity]Event = [_]Event{.{}} ** replay_capacity,
    count: usize = 0,
    ordered: [replay_capacity]Event = [_]Event{.{}} ** replay_capacity,
    ordered_count: usize = 0,
    summary_state: ReplaySummary = .{},
    sealed: bool = false,
    replayed: bool = false,

    pub fn init(run_id: Hash, identity_hash: Hash) ConcurrentReplay {
        return .{ .run_id = run_id, .identity_hash = identity_hash };
    }

    pub fn stage(self: *ConcurrentReplay, event: Event) ReplayOutcome {
        if (self.sealed or self.count == self.staged.len) {
            self.summary_state.rejected +|= 1;
            return .capacity;
        }
        if (event.run_id == 0 or event.run_id != self.run_id or
            (self.identity_hash != 0 and event.identity_hash != self.identity_hash) or
            event.event_id == 0 or event.producer_id == 0)
        {
            self.summary_state.rejected +|= 1;
            return if (event.run_id != self.run_id) .wrong_run else .invalid_identity;
        }
        if (self.findEvent(event.event_id) != null) {
            self.summary_state.rejected +|= 1;
            self.summary_state.duplicates +|= 1;
            return .duplicate;
        }
        self.staged[self.count] = event;
        self.count += 1;
        self.summary_state.staged += 1;
        return .accepted;
    }

    pub fn declareDrop(self: *ConcurrentReplay, count: u64) void {
        self.summary_state.declared_drops +|= count;
    }

    pub fn seal(self: *ConcurrentReplay) void {
        self.sealed = true;
    }

    pub fn replay(self: *ConcurrentReplay) ReplayOutcome {
        if (!self.sealed) return .not_sealed;
        self.ordered_count = 0;
        var used = [_]bool{false} ** replay_capacity;
        while (self.ordered_count < self.count) {
            var selected: ?usize = null;
            var index: usize = 0;
            while (index < self.count) : (index += 1) {
                if (used[index] or !self.ready(index, used)) continue;
                selected = index;
                break;
            }
            const chosen = selected orelse {
                var missing = false;
                var unresolved: usize = 0;
                while (unresolved < self.count) : (unresolved += 1) {
                    if (used[unresolved]) continue;
                    if (self.staged[unresolved].parent_event_id != 0 and self.findEvent(self.staged[unresolved].parent_event_id) == null) {
                        missing = true;
                        break;
                    }
                }
                if (missing) {
                    self.summary_state.missing_dependencies +|= 1;
                    self.summary_state.rejected +|= 1;
                    return .missing_dependency;
                }
                self.summary_state.cycles +|= 1;
                self.summary_state.rejected +|= 1;
                return .cycle;
            };
            used[chosen] = true;
            self.ordered[self.ordered_count] = self.staged[chosen];
            self.ordered_count += 1;
        }
        self.summary_state.ordered = self.ordered_count;
        self.replayed = true;
        if (self.summary_state.declared_drops != 0) {
            self.summary_state.rejected +|= 1;
            return .declared_drop;
        }
        return .accepted;
    }

    pub fn authenticReady(self: *const ConcurrentReplay) bool {
        if (!self.replayed or self.summary_state.rejected != 0 or self.summary_state.declared_drops != 0 or
            self.identity_hash == 0)
            return false;
        for (self.ordered[0..self.ordered_count]) |event| {
            if (event.identity_hash != self.identity_hash or !event.truth.authentic() or
                !event.producer.authentic() or event.producer_token == 0 or
                (event.payload_length != 0 and event.payload_digest == 0)) return false;
        }
        return true;
    }

    pub fn summary(self: *const ConcurrentReplay) ReplaySummary {
        return self.summary_state;
    }

    pub fn orderedEvent(self: *const ConcurrentReplay, index: usize) ?Event {
        if (index >= self.ordered_count) return null;
        return self.ordered[index];
    }

    fn findEvent(self: *const ConcurrentReplay, event_id: Hash) ?usize {
        for (self.staged[0..self.count], 0..) |event, index| {
            if (event.event_id == event_id) return index;
        }
        return null;
    }

    fn ready(self: *const ConcurrentReplay, index: usize, used: [replay_capacity]bool) bool {
        const event = self.staged[index];
        if (event.parent_event_id != 0) {
            const parent = self.findEvent(event.parent_event_id) orelse return false;
            if (!used[parent]) return false;
        }
        if (event.producer_sequence > 1) {
            var found = false;
            for (self.staged[0..self.count], 0..) |candidate, candidate_index| {
                if (candidate.producer_id == event.producer_id and
                    candidate.producer_sequence != std.math.maxInt(u64) and
                    candidate.producer_sequence + 1 == event.producer_sequence)
                {
                    found = used[candidate_index];
                    break;
                }
            }
            if (!found) return false;
        }
        if (event.domain_sequence > 1) {
            var found = false;
            for (self.staged[0..self.count], 0..) |candidate, candidate_index| {
                if (candidate.domain == event.domain and
                    candidate.domain_sequence != std.math.maxInt(u64) and
                    candidate.domain_sequence + 1 == event.domain_sequence)
                {
                    found = used[candidate_index];
                    break;
                }
            }
            if (!found) return false;
        }
        return true;
    }
};

pub const Coverage = struct {
    run_id: Hash = 0,
    producer_id: Hash = 0,
    started: bool = false,
    ended: bool = false,
    terminal_seal: bool = false,
    first_sequence: u64 = 0,
    last_sequence: u64 = 0,
    heartbeat_count: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    intervals: u64 = 0,
    open_interval: bool = false,
    drops: u64 = 0,
    parser_errors: u64 = 0,
    out_of_order: u64 = 0,

    pub fn begin(self: *Coverage, run_id: Hash, producer_id: Hash) bool {
        if (self.started or run_id == 0 or producer_id == 0) return false;
        self.* = .{ .run_id = run_id, .producer_id = producer_id, .started = true };
        return true;
    }

    pub fn beginInterval(self: *Coverage) bool {
        if (!self.started or self.ended or self.open_interval) return false;
        self.open_interval = true;
        self.intervals +|= 1;
        return true;
    }

    pub fn heartbeat(self: *Coverage, sequence: u64, guest_step: u64) bool {
        if (!self.started or self.ended or sequence == 0) return false;
        if (self.last_sequence != 0 and
            (self.last_sequence == std.math.maxInt(u64) or sequence != self.last_sequence + 1))
        {
            self.out_of_order +|= 1;
        }
        if (self.first_sequence == 0) self.first_sequence = sequence;
        if (self.first_step == 0) self.first_step = guest_step;
        self.last_sequence = @max(self.last_sequence, sequence);
        self.last_step = guest_step;
        self.heartbeat_count +|= 1;
        return self.out_of_order == 0;
    }

    pub fn endInterval(self: *Coverage) bool {
        if (!self.open_interval) return false;
        self.open_interval = false;
        return true;
    }

    pub fn noteDrop(self: *Coverage, count: u64) void {
        self.drops +|= count;
    }

    pub fn noteParserError(self: *Coverage) void {
        self.parser_errors +|= 1;
    }

    pub fn finish(self: *Coverage) bool {
        if (!self.started or self.ended or self.open_interval) return false;
        self.ended = true;
        return true;
    }

    pub fn seal(self: *Coverage) bool {
        if (!self.ended or self.terminal_seal) return false;
        self.terminal_seal = true;
        return true;
    }

    pub fn authenticReady(self: *const Coverage) bool {
        return self.started and self.ended and self.terminal_seal and
            self.first_sequence == 1 and self.last_sequence >= self.first_sequence and
            self.heartbeat_count >= 2 and self.intervals != 0 and self.drops == 0 and
            self.parser_errors == 0 and self.out_of_order == 0;
    }
};

pub const ClosureOwner = enum(u8) {
    rosette,
    guest,
    xenia_kernel,
    xenia_gpu,
    xenia_presenter,
    host_driver,
    release_gate,
    unknown,
};

pub const ClosureEdge = enum(u8) {
    identity,
    journal,
    test_manifest,
    substrate,
    callback_effect,
    wait_liveness,
    ring_publication,
    pm4_consensus,
    xenos_state,
    target_effect,
    swap_transaction,
    backend_submission,
    backend_custody,
};

pub const closure_edge_count: usize = @typeInfo(ClosureEdge).@"enum".fields.len;

pub const ClosureStatus = enum(u8) {
    unproven,
    passed,
    failed,
    unsupported,
    unavailable,
    inferred,
    synthetic,

    pub fn label(self: ClosureStatus) []const u8 {
        return switch (self) {
            .unproven => "unproven",
            .passed => "passed",
            .failed => "failed",
            .unsupported => "unsupported",
            .unavailable => "unavailable",
            .inferred => "inferred",
            .synthetic => "synthetic",
        };
    }

    pub fn permitsAuthentic(self: ClosureStatus) bool {
        return self == .passed;
    }
};

pub const ClosureRecord = struct {
    edge: ClosureEdge,
    status: ClosureStatus = .unproven,
    owner: ClosureOwner = .unknown,
    evidence_hash: Hash = 0,
    step: u64 = 0,
};

pub const ClosureBoard = struct {
    records: [closure_edge_count]ClosureRecord = blk: {
        var result: [closure_edge_count]ClosureRecord = undefined;
        for (&result, 0..) |*slot, index| slot.* = .{ .edge = @enumFromInt(index) };
        break :blk result;
    },
    sealed: bool = false,
    mutation_attempts: u64 = 0,

    pub fn note(self: *ClosureBoard, edge: ClosureEdge, status: ClosureStatus, owner: ClosureOwner, evidence_hash: Hash, step: u64) bool {
        if (self.sealed) {
            self.mutation_attempts +|= 1;
            return false;
        }
        self.records[@intFromEnum(edge)] = .{ .edge = edge, .status = status, .owner = owner, .evidence_hash = evidence_hash, .step = step };
        return true;
    }

    pub fn seal(self: *ClosureBoard) void {
        self.sealed = true;
    }

    pub fn authenticReady(self: *const ClosureBoard) bool {
        if (!self.sealed) return false;
        for (self.records) |record| {
            if (!record.status.permitsAuthentic() or record.evidence_hash == 0 or record.owner == .unknown) return false;
        }
        return true;
    }

    pub fn firstMissing(self: *const ClosureBoard) ?ClosureRecord {
        for (self.records) |record| {
            if (!record.status.permitsAuthentic() or record.evidence_hash == 0) return record;
        }
        return null;
    }

    pub fn fingerprint(self: *const ClosureBoard) Hash {
        var result: Hash = 0xcbf2_9ce4_8422_2325;
        for (self.records) |record| {
            result = mix(result, @intFromEnum(record.edge));
            result = mix(result, @intFromEnum(record.status));
            result = mix(result, @intFromEnum(record.owner));
            result = mix(result, record.evidence_hash);
        }
        return result;
    }
};

pub const Abi = enum(u8) { sysv, win64, unknown };
pub const ExceptionOwner = enum(u8) { rosette, xenia, guest, host, unknown };

pub const CpuSnapshot = struct {
    gpr: [16]u64 = [_]u64{0} ** 16,
    rip: u64 = 0,
    rsp: u64 = 0,
    rflags: u64 = 0,
    simd_digest: Hash = 0,
    mxcsr: u32 = 0,
    tls: Hash = 0,
    stack_alignment: u8 = 0,
    abi: Abi = .unknown,
    exception_owner: ExceptionOwner = .unknown,
    code_generation: u64 = 0,
    source_bytes_hash: Hash = 0,
    recovery_tainted: bool = false,
};

pub const CpuBoundaryIssue = enum(u8) {
    none,
    gpr,
    instruction_pointer,
    stack,
    flags,
    simd,
    mxcsr,
    tls,
    alignment,
    abi,
    exception_owner,
    source_identity,
    recovery_taint,
};

pub const CpuBoundaryResult = struct {
    issue: CpuBoundaryIssue = .none,
    authentic: bool = false,

    pub fn label(self: CpuBoundaryResult) []const u8 {
        return switch (self.issue) {
            .none => if (self.authentic) "authentic" else "unproven",
            .gpr => "gpr",
            .instruction_pointer => "rip",
            .stack => "rsp",
            .flags => "rflags",
            .simd => "simd",
            .mxcsr => "mxcsr",
            .tls => "tls",
            .alignment => "stack-alignment",
            .abi => "abi",
            .exception_owner => "exception-owner",
            .source_identity => "source-identity",
            .recovery_taint => "recovery-taint",
        };
    }
};

pub fn compareCpuBoundary(before: CpuSnapshot, after: CpuSnapshot) CpuBoundaryResult {
    if (!std.mem.eql(u64, before.gpr[0..], after.gpr[0..])) return .{ .issue = .gpr };
    if (before.rip != after.rip) return .{ .issue = .instruction_pointer };
    if (before.rsp != after.rsp) return .{ .issue = .stack };
    if (before.rflags != after.rflags) return .{ .issue = .flags };
    if (before.simd_digest != after.simd_digest) return .{ .issue = .simd };
    if (before.mxcsr != after.mxcsr) return .{ .issue = .mxcsr };
    if (before.tls != after.tls) return .{ .issue = .tls };
    if (before.stack_alignment != after.stack_alignment) return .{ .issue = .alignment };
    if (before.abi != after.abi) return .{ .issue = .abi };
    if (before.exception_owner != after.exception_owner) return .{ .issue = .exception_owner };
    if (before.code_generation != after.code_generation or before.source_bytes_hash != after.source_bytes_hash) return .{ .issue = .source_identity };
    if (before.recovery_tainted or after.recovery_tainted) return .{ .issue = .recovery_taint };
    return .{ .authentic = true };
}

pub const WaitState = enum(u8) {
    declared,
    waiting,
    signaled,
    delivered,
    timed_out,
    cancelled,
    completed,
    destroyed,
    failed,
};

pub const WaitCause = enum(u8) { callback, dpc, apc, timer, thread_exit, guest_signal, unknown };

pub const WaitTransaction = struct {
    object_address: Hash = 0,
    object_generation: u64 = 0,
    owner_thread: Hash = 0,
    waiter_thread: Hash = 0,
    deadline_guest_ms: u64 = 0,
    interruptible: bool = false,
    state: WaitState = .declared,
    cause: WaitCause = .unknown,
    effect_hash: Hash = 0,

    pub fn begin(self: *WaitTransaction, object_address: Hash, generation: u64, owner_thread: Hash, waiter_thread: Hash, deadline_guest_ms: u64, interruptible: bool) bool {
        if (object_address == 0 or generation == 0 or owner_thread == 0 or waiter_thread == 0) return false;
        self.* = .{ .object_address = object_address, .object_generation = generation, .owner_thread = owner_thread, .waiter_thread = waiter_thread, .deadline_guest_ms = deadline_guest_ms, .interruptible = interruptible, .state = .waiting };
        return true;
    }

    pub fn signal(self: *WaitTransaction, cause: WaitCause, effect_hash: Hash) bool {
        if (self.state != .waiting or cause == .unknown) return false;
        self.state = .signaled;
        self.cause = cause;
        self.effect_hash = effect_hash;
        return true;
    }

    pub fn deliver(self: *WaitTransaction) bool {
        if (self.state != .signaled or self.effect_hash == 0) return false;
        self.state = .delivered;
        return true;
    }

    pub fn complete(self: *WaitTransaction) bool {
        if (self.state != .delivered) return false;
        self.state = .completed;
        return true;
    }

    pub fn timeout(self: *WaitTransaction) bool {
        if (self.state != .waiting or self.deadline_guest_ms == 0) return false;
        self.state = .timed_out;
        self.cause = .timer;
        return true;
    }

    pub fn destroy(self: *WaitTransaction) bool {
        if (self.state == .completed or self.state == .destroyed) return false;
        self.state = .destroyed;
        return true;
    }

    pub fn authenticReady(self: *const WaitTransaction) bool {
        return self.state == .completed and self.cause != .unknown and self.effect_hash != 0;
    }
};

pub const ClockPlane = struct {
    guest_ms: u64 = 0,
    host_ns: u64 = 0,
    vblank_sequence: u64 = 0,
    all_guest_threads_blocked: bool = false,
    time_only_wakes: u64 = 0,
    discontinuities: u64 = 0,

    pub fn advance(self: *ClockPlane, guest_delta_ms: u64, host_delta_ns: u64) bool {
        if (host_delta_ns == 0 or (guest_delta_ms == 0 and !self.all_guest_threads_blocked)) return false;
        self.guest_ms +|= guest_delta_ms;
        self.host_ns +|= host_delta_ns;
        return true;
    }

    pub fn noteVblank(self: *ClockPlane, time_only: bool) bool {
        self.vblank_sequence +|= 1;
        if (time_only) self.time_only_wakes +|= 1;
        return self.vblank_sequence != 0;
    }

    pub fn noteDiscontinuity(self: *ClockPlane) void {
        self.discontinuities +|= 1;
    }

    pub fn authenticReady(self: *const ClockPlane) bool {
        return self.guest_ms != 0 and self.host_ns != 0 and self.vblank_sequence != 0 and self.discontinuities == 0;
    }
};

pub const BlackBoxStatus = enum(u8) { implemented, unsupported, unavailable, failed, diagnostic_fallback, inferred };

pub const BlackBoxContract = struct {
    name_hash: Hash = 0,
    version_hash: Hash = 0,
    precondition_observed: bool = false,
    postcondition_observed: bool = false,
    status: BlackBoxStatus = .unavailable,
    timeout_ms: u64 = 0,

    pub fn authenticReady(self: *const BlackBoxContract) bool {
        return self.name_hash != 0 and self.version_hash != 0 and
            self.precondition_observed and self.postcondition_observed and
            self.status == .implemented;
    }
};

pub const TestMode = enum(u8) { run, compile_only };
pub const TestStatus = enum(u8) { declared, executed, compiled, filtered, failed, stale };
pub const max_test_entries: usize = 4096;

pub const TestEntry = struct {
    declaration_hash: Hash = 0,
    source_root_hash: Hash = 0,
    module_hash: Hash = 0,
    artifact_hash: Hash = 0,
    binary_hash: Hash = 0,
    declarations: u64 = 0,
    mode: TestMode = .run,
    status: TestStatus = .declared,
};

pub const TestManifest = struct {
    entries: [max_test_entries]TestEntry = [_]TestEntry{.{}} ** max_test_entries,
    count: usize = 0,
    source_declarations: u64 = 0,
    assigned_declarations: u64 = 0,
    duplicate_entries: u64 = 0,
    unowned_declarations: u64 = 0,
    sealed: bool = false,
    binary_hash: Hash = 0,

    pub fn declareSource(self: *TestManifest, count: u64) bool {
        if (self.sealed) return false;
        self.source_declarations +|= count;
        return true;
    }

    pub fn add(self: *TestManifest, entry: TestEntry) bool {
        if (self.sealed or self.count == self.entries.len or entry.declaration_hash == 0 or entry.source_root_hash == 0 or entry.module_hash == 0 or entry.artifact_hash == 0) return false;
        for (self.entries[0..self.count]) |existing| {
            if (existing.declaration_hash == entry.declaration_hash) {
                self.duplicate_entries +|= 1;
                return false;
            }
        }
        self.entries[self.count] = entry;
        self.count += 1;
        self.assigned_declarations +|= entry.declarations;
        return true;
    }

    pub fn seal(self: *TestManifest, current_binary_hash: Hash) bool {
        if (self.sealed or current_binary_hash == 0) return false;
        self.binary_hash = current_binary_hash;
        self.unowned_declarations = if (self.source_declarations > self.assigned_declarations) self.source_declarations - self.assigned_declarations else 0;
        self.sealed = true;
        return true;
    }

    pub fn authenticReady(self: *const TestManifest) bool {
        if (!self.sealed or self.binary_hash == 0 or self.count == 0 or self.source_declarations == 0 or self.duplicate_entries != 0 or self.unowned_declarations != 0 or self.assigned_declarations != self.source_declarations) return false;
        for (self.entries[0..self.count]) |entry| {
            if (entry.declarations == 0 or entry.binary_hash != self.binary_hash) return false;
            if (entry.mode == .run and entry.status != .executed) return false;
            if (entry.mode == .compile_only and entry.status != .compiled) return false;
            if (entry.status == .failed or entry.status == .filtered or entry.status == .stale) return false;
        }
        return true;
    }
};

pub const PairResult = enum(u8) { comparable, identity_mismatch, frontier_mismatch, wait_order_mismatch, pm4_mismatch, output_mismatch, not_sealed };

pub const PairedRun = struct {
    base_identity: Hash = 0,
    input_identity: Hash = 0,
    instrumentation_identity: Hash = 0,
    frontier: Hash = 0,
    wait_order: Hash = 0,
    pm4_bytes: Hash = 0,
    output: Hash = 0,
    sealed: bool = false,

    pub fn seal(self: *PairedRun) bool {
        if (self.base_identity == 0 or self.input_identity == 0 or self.instrumentation_identity == 0) return false;
        self.sealed = true;
        return true;
    }

    pub fn compare(self: PairedRun, other: PairedRun) PairResult {
        if (!self.sealed or !other.sealed) return .not_sealed;
        if (self.base_identity != other.base_identity or self.input_identity != other.input_identity) return .identity_mismatch;
        if (self.frontier == 0 or other.frontier == 0 or self.frontier != other.frontier) return .frontier_mismatch;
        if (self.wait_order == 0 or self.wait_order != other.wait_order) return .wait_order_mismatch;
        if (self.pm4_bytes == 0 or self.pm4_bytes != other.pm4_bytes) return .pm4_mismatch;
        if (self.output == 0 or other.output == 0 or self.output != other.output) return .output_mismatch;
        return .comparable;
    }
};

test "content identity and admission are immutable before guest start" {
    var identity = Identity{};
    inline for (@typeInfo(IdentityField).@"enum".fields, 0..) |field, index| {
        try std.testing.expect(identity.set(@enumFromInt(field.value), @intCast(index + 1)));
    }
    var admission = Admission.init(7, .authentic, identity);
    try std.testing.expectEqual(AdmissionFailure.none, admission.seal());
    try std.testing.expectEqual(StartVerdict.admitted, admission.requestGuestStart());
    try std.testing.expect(!admission.replaceIdentity(identity));
    try std.testing.expect(admission.mutation_attempts != 0);
    try std.testing.expect(admission.authenticReady());
}

test "artifact reservation refuses a prior run by default" {
    try std.testing.expectEqual(ArtifactResult.reserved_new, reserveArtifact(1, 0, false, .create_exclusive));
    try std.testing.expectEqual(ArtifactResult.refused_collision, reserveArtifact(1, 0, true, .create_exclusive));
    try std.testing.expectEqual(ArtifactResult.reused_existing, reserveArtifact(1, 0, true, .append_existing));
    var name: [64]u8 = undefined;
    try std.testing.expect(std.mem.startsWith(u8, (formatArtifactName(&name, 1, 2)).?, "run-"));
}

test "the evidence owner waits for producer quiescence and durable footer" {
    var owner = EvidenceOwner{};
    try std.testing.expect(owner.begin(11, true));
    try std.testing.expect(owner.registerProducer(3));
    try std.testing.expect(owner.acceptRecord(3));
    try std.testing.expect(!owner.beginDrain());
    try std.testing.expect(owner.unregisterProducer(3));
    try std.testing.expect(owner.beginDrain());
    try std.testing.expect(owner.noteFooter(true));
    try std.testing.expect(!owner.authenticReady());
    try std.testing.expect(owner.noteDurableFooter(true));
    try std.testing.expect(owner.commit());
    try std.testing.expect(owner.authenticReady());
}

test "authenticated event production rejects a forged producer token" {
    var authority = EventAuthority.init(5, 9);
    const token = authority.registerProducer(12, .xenia).?;
    const forged = authority.emit(12, token + 1, .{ .domain = .kernel, .truth = .observed }, "payload");
    try std.testing.expectEqual(EmitFailure.bad_token, forged.failure);
    const valid = authority.emit(12, token, .{ .domain = .kernel, .truth = .observed }, "payload");
    try std.testing.expectEqual(EmitFailure.none, valid.failure);
    try std.testing.expectEqual(hashBytes("payload"), valid.event.?.payload_digest);
}

test "concurrent replay accepts a child that arrived before its parent" {
    var authority = EventAuthority.init(6, 10);
    const token = authority.registerProducer(13, .xenia).?;
    const parent = authority.emit(13, token, .{ .domain = .kernel, .truth = .observed }, "parent").event.?;
    const child = authority.emit(13, token, .{ .domain = .kernel, .parent_event_id = parent.event_id, .truth = .observed }, "child").event.?;
    var replay = ConcurrentReplay.init(6, 10);
    try std.testing.expectEqual(ReplayOutcome.accepted, replay.stage(child));
    try std.testing.expectEqual(ReplayOutcome.accepted, replay.stage(parent));
    replay.seal();
    try std.testing.expectEqual(ReplayOutcome.accepted, replay.replay());
    try std.testing.expectEqual(parent.event_id, replay.orderedEvent(0).?.event_id);
    try std.testing.expect(replay.authenticReady());
}

test "replay capacity and missing dependencies fail closed" {
    var replay = ConcurrentReplay.init(3, 4);
    var child = Event{ .run_id = 3, .identity_hash = 4, .event_id = 1, .producer_id = 2, .producer_sequence = 1, .domain_sequence = 1, .parent_event_id = 99, .producer_token = 4, .producer = .xenia, .domain = .kernel, .truth = .observed };
    try std.testing.expectEqual(ReplayOutcome.accepted, replay.stage(child));
    replay.seal();
    try std.testing.expectEqual(ReplayOutcome.missing_dependency, replay.replay());
    child.event_id = 2;
    try std.testing.expectEqual(ReplayOutcome.capacity, blk: {
        var full = ConcurrentReplay.init(4, 4);
        full.sealed = true;
        break :blk full.stage(child);
    });
}

test "coverage needs the whole interval and a terminal seal" {
    var coverage = Coverage{};
    try std.testing.expect(coverage.begin(1, 2));
    try std.testing.expect(coverage.beginInterval());
    try std.testing.expect(coverage.heartbeat(1, 10));
    try std.testing.expect(coverage.heartbeat(2, 20));
    try std.testing.expect(coverage.endInterval());
    try std.testing.expect(coverage.finish());
    try std.testing.expect(coverage.seal());
    try std.testing.expect(coverage.authenticReady());
}

test "closure board never treats unsupported or not reached as passed" {
    var board = ClosureBoard{};
    try std.testing.expect(board.note(.identity, .unsupported, .rosette, 1, 1));
    board.seal();
    try std.testing.expect(!board.authenticReady());
    try std.testing.expectEqual(ClosureEdge.identity, board.firstMissing().?.edge);
}

test "cpu boundary compares ABI state and preserves recovery taint" {
    var before = CpuSnapshot{ .abi = .win64, .exception_owner = .xenia, .code_generation = 1, .source_bytes_hash = 2 };
    const after = before;
    try std.testing.expect(compareCpuBoundary(before, after).authentic);
    before.recovery_tainted = true;
    try std.testing.expectEqual(CpuBoundaryIssue.recovery_taint, compareCpuBoundary(before, after).issue);
}

test "wait transaction requires an observed effect before completion" {
    var wait = WaitTransaction{};
    try std.testing.expect(wait.begin(1, 1, 2, 3, 50, true));
    try std.testing.expect(!wait.deliver());
    try std.testing.expect(wait.signal(.dpc, 9));
    try std.testing.expect(wait.deliver());
    try std.testing.expect(wait.complete());
    try std.testing.expect(wait.authenticReady());
}

test "paired runs compare semantics rather than speed" {
    var enabled = PairedRun{ .base_identity = 1, .input_identity = 2, .instrumentation_identity = 3, .frontier = 4, .wait_order = 5, .pm4_bytes = 6, .output = 7 };
    var disabled = enabled;
    disabled.instrumentation_identity = 8;
    try std.testing.expect(enabled.seal());
    try std.testing.expect(disabled.seal());
    try std.testing.expectEqual(PairResult.comparable, enabled.compare(disabled));
    disabled.pm4_bytes = 9;
    try std.testing.expectEqual(PairResult.pm4_mismatch, enabled.compare(disabled));
}
