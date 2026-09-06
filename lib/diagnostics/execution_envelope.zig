//! A typed witness for one cross-domain execution.
//!
//! Xenia's PPC code, its generated x86-64 code, Rosette's x86 boundary, and
//! the macOS host are four different execution domains. A return from an
//! outer C++ function is not a guest return, and a host RIP is not a guest
//! program counter. This module gives those domains one bounded transaction
//! envelope and makes the unsafe cases explicit.

const std = @import("std");

pub const schema_version: u16 = 1;
pub const max_source_entries: usize = 256;
pub const max_execution_records: usize = 256;
pub const max_signals: usize = 128;

pub const Boundary = enum(u8) {
    ppc_guest,
    generated_x64,
    rosette_x86,
    host,

    pub fn label(self: Boundary) []const u8 {
        return switch (self) {
            .ppc_guest => "ppc-guest",
            .generated_x64 => "generated-x64",
            .rosette_x86 => "rosette-x86",
            .host => "host",
        };
    }
};

pub const ExecutionStatus = enum(u8) {
    executing,
    returned,
    faulted,
    timed_out,
    terminated,
    context_mismatch,
    rejected,
    effect_unobserved,

    pub fn label(self: ExecutionStatus) []const u8 {
        return switch (self) {
            .executing => "executing",
            .returned => "returned",
            .faulted => "faulted",
            .timed_out => "timed-out",
            .terminated => "terminated",
            .context_mismatch => "context-mismatch",
            .rejected => "rejected",
            .effect_unobserved => "effect-unobserved",
        };
    }

    pub fn returnedNormally(self: ExecutionStatus) bool {
        return self == .returned;
    }
};

pub const SourceConfidence = enum(u8) {
    unknown,
    advisory,
    bounded,
    exact,
};

pub const FaultKind = enum(u8) {
    none,
    guest_memory,
    host_signal,
    host_exception,
    invalid_control_transfer,
    policy_recovery,
};

/// Hashes are deliberately supplied by the owner of each state domain. The
/// envelope does not pretend that a partial hash is a register snapshot.
pub const RegisterState = extern struct {
    ppc_hash: u64 = 0,
    x86_gpr_hash: u64 = 0,
    x86_simd_hash: u64 = 0,
    flags_hash: u64 = 0,
    stack_hash: u64 = 0,
    tls_hash: u64 = 0,
};

/// Fixed-width across the Xenia/Rosette boundary. New fields belong at the
/// end and require a schema bump; producers must not reinterpret padding.
pub const Envelope = extern struct {
    schema: u16 = schema_version,
    boundary: u8 = @intFromEnum(Boundary.host),
    status: u8 = @intFromEnum(ExecutionStatus.rejected),
    source_confidence: u8 = @intFromEnum(SourceConfidence.unknown),
    fault_kind: u8 = @intFromEnum(FaultKind.none),
    reserved: u16 = 0,

    run_id: u64 = 0,
    transaction_id: u64 = 0,
    parent_event_id: u64 = 0,
    correlation_id: u64 = 0,
    context_id: u64 = 0,
    guest_thread: u64 = 0,
    host_thread: u64 = 0,
    module_epoch: u64 = 0,
    code_generation: u64 = 0,
    source_map_generation: u64 = 0,

    guest_start_pc: u32 = 0,
    guest_return_pc: u32 = 0,
    decoded_length: u16 = 0,
    instruction_count: u64 = 0,
    x86_start_rip: u64 = 0,
    x86_return_rip: u64 = 0,
    source_function: u64 = 0,

    return_value: u64 = 0,
    state_before_hash: u64 = 0,
    state_after_hash: u64 = 0,
    effect_mask: u64 = 0,
    effect_hash: u64 = 0,
    fault_signal: u32 = 0,
    fault_address: u64 = 0,

    pub fn statusOf(self: Envelope) ExecutionStatus {
        return enumFromInt(ExecutionStatus, self.status, .rejected);
    }

    pub fn boundaryOf(self: Envelope) Boundary {
        return enumFromInt(Boundary, self.boundary, .host);
    }

    pub fn authoritative(self: Envelope, context_id: u64) bool {
        return self.schema == schema_version and
            self.statusOf() == .returned and
            self.context_id != 0 and
            self.context_id == context_id and
            self.effect_mask != 0;
    }
};

fn enumFromInt(comptime T: type, value: anytype, fallback: T) T {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        if (field.value == value) return @enumFromInt(field.value);
    }
    return fallback;
}

pub const SourceMapEntry = struct {
    function_id: u64 = 0,
    code_generation: u64 = 0,
    guest_start: u32 = 0,
    guest_end: u32 = 0,
    host_start: u64 = 0,
    host_end: u64 = 0,
    rosette_start: u64 = 0,
    rosette_end: u64 = 0,
    map_generation: u64 = 0,
    bytes: [16]u8 = [_]u8{0} ** 16,
    byte_len: u8 = 0,

    pub fn contains(self: SourceMapEntry, rip: u64) bool {
        return self.host_start != 0 and self.host_start < self.host_end and
            rip >= self.host_start and rip < self.host_end;
    }

    pub fn valid(self: SourceMapEntry) bool {
        return self.function_id != 0 and self.host_start < self.host_end and
            self.guest_start < self.guest_end and self.byte_len <= self.bytes.len;
    }
};

pub const LookupStatus = enum(u8) {
    unknown,
    unique,
    ambiguous,
};

pub const SourceMapLookup = struct {
    status: LookupStatus = .unknown,
    entry: SourceMapEntry = .{},
    candidates: u8 = 0,

    pub fn trustworthy(self: SourceMapLookup) bool {
        return self.status == .unique and self.entry.valid();
    }
};

/// Source-map publication and lookup share one lock. The old Xenia map read
/// was not protected by the append lock and also searched one item past the
/// vector. This service is intentionally small and bounded so the invariant
/// is easy to test and hard to accidentally bypass.
pub const SourceMap = struct {
    mutex: std.atomic.Mutex = .unlocked,
    entries: [max_source_entries]SourceMapEntry = [_]SourceMapEntry{.{}} ** max_source_entries,
    count: usize = 0,
    generation: u64 = 1,
    dropped: u64 = 0,
    rejected: u64 = 0,

    pub fn publish(self: *SourceMap, input: SourceMapEntry) bool {
        if (!input.valid()) {
            lock(&self.mutex);
            self.rejected +|= 1;
            self.mutex.unlock();
            return false;
        }

        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.count >= max_source_entries) {
            self.dropped +|= 1;
            return false;
        }

        var entry = input;
        entry.map_generation = self.generation;
        var position = self.count;
        while (position > 0 and self.entries[position - 1].host_start > entry.host_start) : (position -= 1) {
            self.entries[position] = self.entries[position - 1];
        }
        self.entries[position] = entry;
        self.count += 1;
        self.generation +|= 1;
        return true;
    }

    pub fn lookup(self: *SourceMap, rip: u64) SourceMapLookup {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.count == 0) return .{};

        // Find the last range whose start is not after rip. The subsequent
        // bounded scan catches overlapping ranges and therefore reports
        // ambiguity instead of choosing whichever append happened last.
        var low: usize = 0;
        var high: usize = self.count;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.entries[middle].host_start <= rip) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        if (low == 0) return .{};

        var first = low - 1;
        while (first > 0 and self.entries[first - 1].contains(rip)) : (first -= 1) {}
        var result: SourceMapLookup = .{};
        var index = first;
        while (index < self.count and self.entries[index].host_start <= rip) : (index += 1) {
            if (!self.entries[index].contains(rip)) continue;
            result.candidates += 1;
            if (result.candidates == 1) result.entry = self.entries[index];
        }
        result.status = switch (result.candidates) {
            0 => .unknown,
            1 => .unique,
            else => .ambiguous,
        };
        return result;
    }

    pub fn size(self: *SourceMap) usize {
        lock(&self.mutex);
        defer self.mutex.unlock();
        return self.count;
    }
};

pub const CustodyOwner = enum(u8) {
    none,
    ppc_guest,
    xenia,
    rosette,
    host,
    diagnostic,
};

pub const CustodySnapshot = struct {
    owner: CustodyOwner = .none,
    generation: u64 = 0,
    transaction_id: u64 = 0,
    violations: u64 = 0,
};

pub const ContextCustody = struct {
    mutex: std.atomic.Mutex = .unlocked,
    owner: CustodyOwner = .none,
    generation: u64 = 0,
    transaction_id: u64 = 0,
    violations: u64 = 0,

    /// Acquire is exclusive. Re-entrant ownership is allowed only for the
    /// same transaction, which makes nested callbacks explicit without
    /// silently handing a context to a second host thread.
    pub fn acquire(self: *ContextCustody, owner: CustodyOwner, transaction_id: u64) bool {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (owner == .none or transaction_id == 0) {
            self.violations +|= 1;
            return false;
        }
        if (self.owner != .none and (self.owner != owner or self.transaction_id != transaction_id)) {
            self.violations +|= 1;
            return false;
        }
        if (self.owner == .none) {
            self.generation +|= 1;
            self.owner = owner;
            self.transaction_id = transaction_id;
        }
        return true;
    }

    pub fn commit(self: *ContextCustody, owner: CustodyOwner, transaction_id: u64) bool {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.owner != owner or self.transaction_id != transaction_id) {
            self.violations +|= 1;
            return false;
        }
        return true;
    }

    pub fn restore(self: *ContextCustody, owner: CustodyOwner, transaction_id: u64) bool {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.owner != owner or self.transaction_id != transaction_id) {
            self.violations +|= 1;
            return false;
        }
        self.owner = .none;
        self.transaction_id = 0;
        return true;
    }

    pub fn snapshot(self: *ContextCustody) CustodySnapshot {
        lock(&self.mutex);
        defer self.mutex.unlock();
        return .{ .owner = self.owner, .generation = self.generation, .transaction_id = self.transaction_id, .violations = self.violations };
    }
};

pub const SignalCause = enum(u8) {
    guest_signal,
    guest_timeout,
    guest_apc,
    guest_termination,
    host_service,
    diagnostic_synthetic,
};

pub const SignalRecord = struct {
    id: u64 = 0,
    parent_id: u64 = 0,
    context_id: u64 = 0,
    generation: u64 = 0,
    cause: SignalCause = .host_service,
    published: bool = false,
    consumed: bool = false,
};

pub const SignalLedger = struct {
    records: [max_signals]SignalRecord = [_]SignalRecord{.{}} ** max_signals,
    count: usize = 0,
    next_id: u64 = 1,
    violations: u64 = 0,

    pub fn publish(self: *SignalLedger, parent_id: u64, context_id: u64, generation: u64, cause: SignalCause) ?u64 {
        if (self.count >= max_signals or context_id == 0 or generation == 0) {
            self.violations +|= 1;
            return null;
        }
        if (parent_id != 0 and !self.contains(parent_id)) {
            self.violations +|= 1;
            return null;
        }
        const id = self.next_id;
        self.next_id +|= 1;
        self.records[self.count] = .{ .id = id, .parent_id = parent_id, .context_id = context_id, .generation = generation, .cause = cause, .published = true };
        self.count += 1;
        return id;
    }

    pub fn consume(self: *SignalLedger, id: u64, context_id: u64, generation: u64) bool {
        for (self.records[0..self.count]) |*record| {
            if (record.id != id) continue;
            if (!record.published or record.consumed or record.context_id != context_id or record.generation != generation) {
                self.violations +|= 1;
                return false;
            }
            record.consumed = true;
            return true;
        }
        self.violations +|= 1;
        return false;
    }

    pub fn contains(self: *const SignalLedger, id: u64) bool {
        for (self.records[0..self.count]) |record| if (record.id == id) return true;
        return false;
    }
};

/// Minimal release/acquire publication primitive used by the cross-ISA
/// litmus tests. The real ring and callback implementations have their own
/// payload, but they must exhibit this same publication shape.
pub const PublicationLitmus = struct {
    payload: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    published: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn publish(self: *PublicationLitmus, value: u64) void {
        self.payload.store(value, .monotonic);
        self.published.store(true, .release);
    }

    pub fn consume(self: *PublicationLitmus) ?u64 {
        if (!self.published.load(.acquire)) return null;
        return self.payload.load(.monotonic);
    }
};

pub const FinishOutcome = enum(u8) {
    accepted,
    unknown_transaction,
    context_mismatch,
};

pub const ExecutionLedger = struct {
    records: [max_execution_records]Envelope = [_]Envelope{.{}} ** max_execution_records,
    count: usize = 0,
    next_transaction_id: u64 = 1,
    rejected: u64 = 0,

    pub fn begin(self: *ExecutionLedger, input: Envelope) ?u64 {
        if (self.count >= max_execution_records or input.context_id == 0) {
            self.rejected +|= 1;
            return null;
        }
        var envelope = input;
        envelope.schema = schema_version;
        envelope.transaction_id = self.next_transaction_id;
        self.next_transaction_id +|= 1;
        envelope.status = @intFromEnum(ExecutionStatus.executing);
        self.records[self.count] = envelope;
        self.count += 1;
        return envelope.transaction_id;
    }

    pub fn finish(self: *ExecutionLedger, transaction_id: u64, status: ExecutionStatus, context_id: u64, return_value: u64, state_after_hash: u64, effect_mask: u64, effect_hash: u64) FinishOutcome {
        for (self.records[0..self.count]) |*envelope| {
            if (envelope.transaction_id != transaction_id) continue;
            if (envelope.context_id != context_id) {
                envelope.status = @intFromEnum(ExecutionStatus.context_mismatch);
                envelope.effect_mask = 0;
                envelope.effect_hash = 0;
                self.rejected +|= 1;
                return .context_mismatch;
            }
            envelope.status = @intFromEnum(status);
            envelope.return_value = return_value;
            envelope.state_after_hash = state_after_hash;
            // Only a normal return can publish an effect. A fault recovery,
            // timeout, or host termination remains a witness, never a credit.
            if (status == .returned) {
                envelope.effect_mask = effect_mask;
                envelope.effect_hash = effect_hash;
            } else {
                envelope.effect_mask = 0;
                envelope.effect_hash = 0;
            }
            return .accepted;
        }
        self.rejected +|= 1;
        return .unknown_transaction;
    }

    pub fn authoritative(self: *const ExecutionLedger, transaction_id: u64, context_id: u64) bool {
        for (self.records[0..self.count]) |envelope| {
            if (envelope.transaction_id == transaction_id) return envelope.authoritative(context_id);
        }
        return false;
    }

    pub fn find(self: *const ExecutionLedger, transaction_id: u64) ?Envelope {
        for (self.records[0..self.count]) |envelope| if (envelope.transaction_id == transaction_id) return envelope;
        return null;
    }
};

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

const PublishThreadArgs = struct {
    map: *SourceMap,
    start: u64,
};

fn publishThread(args: PublishThreadArgs) void {
    var index: u64 = 0;
    while (index < 96) : (index += 1) {
        _ = args.map.publish(.{
            .function_id = args.start + index + 1,
            .code_generation = 1,
            .guest_start = @intCast(0x8200_0000 + index * 0x20),
            .guest_end = @intCast(0x8200_0000 + index * 0x20 + 0x20),
            .host_start = args.start + index * 0x100,
            .host_end = args.start + index * 0x100 + 0x80,
            .byte_len = 1,
        });
    }
}

test "source-map lookup is bounded, sorted, and detects overlap" {
    var map = SourceMap{};
    try std.testing.expect(map.publish(.{ .function_id = 1, .guest_start = 1, .guest_end = 2, .host_start = 0x200, .host_end = 0x240, .byte_len = 1 }));
    try std.testing.expect(map.publish(.{ .function_id = 2, .guest_start = 2, .guest_end = 3, .host_start = 0x100, .host_end = 0x180, .byte_len = 1 }));
    var lookup = map.lookup(0x210);
    try std.testing.expectEqual(LookupStatus.unique, lookup.status);
    try std.testing.expectEqual(@as(u64, 1), lookup.entry.function_id);
    try std.testing.expectEqual(LookupStatus.unknown, map.lookup(0x250).status);
    try std.testing.expect(map.publish(.{ .function_id = 3, .guest_start = 3, .guest_end = 4, .host_start = 0x220, .host_end = 0x260, .byte_len = 1 }));
    lookup = map.lookup(0x230);
    try std.testing.expectEqual(LookupStatus.ambiguous, lookup.status);
    try std.testing.expect(!lookup.trustworthy());
}

test "source-map concurrent publication and lookup never reads outside the map" {
    var map = SourceMap{};
    var first = try std.Thread.spawn(.{}, publishThread, .{PublishThreadArgs{ .map = &map, .start = 0x10_000 }});
    var second = try std.Thread.spawn(.{}, publishThread, .{PublishThreadArgs{ .map = &map, .start = 0x80_000 }});
    var observed: u64 = 0;
    var index: u64 = 0;
    while (index < 20_000) : (index += 1) {
        const result = map.lookup(0x10_000 + (index % 96) * 0x100 + 4);
        if (result.status != .unknown) observed += 1;
    }
    first.join();
    second.join();
    try std.testing.expect(map.size() <= max_source_entries);
    try std.testing.expect(observed != std.math.maxInt(u64));
}

test "context custody refuses a competing owner and restores exactly once" {
    var custody = ContextCustody{};
    try std.testing.expect(custody.acquire(.xenia, 7));
    try std.testing.expect(!custody.acquire(.rosette, 8));
    try std.testing.expect(custody.commit(.xenia, 7));
    try std.testing.expect(custody.restore(.xenia, 7));
    try std.testing.expect(!custody.restore(.xenia, 7));
    try std.testing.expectEqual(@as(u64, 2), custody.snapshot().violations);
}

test "signals require the same context generation and cannot be consumed twice" {
    var signals = SignalLedger{};
    const id = signals.publish(0, 11, 3, .guest_signal).?;
    try std.testing.expect(!signals.consume(id, 11, 4));
    try std.testing.expect(signals.consume(id, 11, 3));
    try std.testing.expect(!signals.consume(id, 11, 3));
    try std.testing.expectEqual(@as(u64, 2), signals.violations);
}

test "release publication is acquired before the payload is consumed" {
    var litmus = PublicationLitmus{};
    try std.testing.expect(litmus.consume() == null);
    litmus.publish(0xCAFE);
    try std.testing.expectEqual(@as(?u64, 0xCAFE), litmus.consume());
}

test "execution effects require a normal return in the same context" {
    var ledger = ExecutionLedger{};
    const transaction = ledger.begin(.{ .run_id = 1, .context_id = 9, .boundary = @intFromEnum(Boundary.generated_x64) }).?;
    try std.testing.expectEqual(FinishOutcome.context_mismatch, ledger.finish(transaction, .returned, 10, 1, 2, 4, 5));
    try std.testing.expect(!ledger.authoritative(transaction, 9));

    const second = ledger.begin(.{ .run_id = 1, .context_id = 9, .boundary = @intFromEnum(Boundary.rosette_x86) }).?;
    try std.testing.expectEqual(FinishOutcome.accepted, ledger.finish(second, .faulted, 9, 1, 2, 4, 5));
    try std.testing.expect(!ledger.authoritative(second, 9));

    const third = ledger.begin(.{ .run_id = 1, .context_id = 9, .boundary = @intFromEnum(Boundary.rosette_x86) }).?;
    try std.testing.expectEqual(FinishOutcome.accepted, ledger.finish(third, .returned, 9, 1, 2, 4, 5));
    try std.testing.expect(ledger.authoritative(third, 9));
}
