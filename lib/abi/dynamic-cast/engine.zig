//! Per-process state for `__dynamic_cast`: what the runtime has learned about
//! the guest's RTTI, what it has decided, and what it could not decide.
//!
//! The counters exist to make one distinction legible at exit — casts the
//! runtime *answered* versus casts it *could not answer*. A summary that lumps
//! them together reports a program doing correct type tests as a runtime in
//! trouble, and hides a runtime in trouble behind a program doing correct type
//! tests.

const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

const rtti = @import("type_info.zig");
const resolver = @import("resolver.zig");

pub const Strategy = resolver.Strategy;
pub const Resolution = resolver.Resolution;
pub const Undecided = resolver.Undecided;

const trace_capacity: usize = 16;
const failure_shape_capacity: usize = 32;

const TraceEntry = struct {
    source: u64 = 0,
    result: u64 = 0,
    source_type: u64 = 0,
    destination_type: u64 = 0,
    hint: i64 = 0,
    strategy: Strategy = .null_source,
    by_name: bool = false,
    verified: bool = true,
};

const FailureShape = struct {
    source_type: u64 = 0,
    destination_type: u64 = 0,
    hint: u64 = 0,
    occurrences: u64 = 0,
};

pub const FailureReportDecision = struct {
    emit: bool,
    occurrence: u64,
    suppressed_total: u64,
};

const UndecidedRecord = struct {
    source: u64 = 0,
    source_type: u64 = 0,
    destination_type: u64 = 0,
    hint: i64 = 0,
    reason: Undecided = .hierarchy_unreadable,
};

pub const Engine = struct {
    /// What the runtime has learned about this process's RTTI. Persistent on
    /// purpose: the RTTI vtable set converges after the first few casts, and
    /// every cast after that classifies records by set membership rather than
    /// by guessing at bytes.
    types: rtti.Reader = .{},

    attempts: u64 = 0,
    resolved: u64 = 0,
    null_sources: u64 = 0,
    same_type: u64 = 0,
    exact_dynamic: u64 = 0,
    /// Short-cut answers where the public path back to the source subobject
    /// could not be checked.
    exact_unverified: u64 = 0,
    hierarchy_resolved: u64 = 0,
    cross_casts: u64 = 0,
    hint_resolved: u64 = 0,
    /// Casts that needed the name-comparison pass. A non-zero count means this
    /// process's RTTI is not coalesced across images, which is worth knowing
    /// independently: the guest's own `type_info` pointer comparisons are
    /// failing for the same reason.
    by_name: u64 = 0,
    /// Casts answered null *correctly*: the graph was readable and the
    /// destination is not an unambiguous, publicly reachable base of the
    /// dynamic type.
    proven_negatives: u64 = 0,
    undecided: u64 = 0,
    negative_hints: u64 = 0,

    trace_buffer: [trace_capacity]TraceEntry = [_]TraceEntry{.{}} ** trace_capacity,
    trace_index: usize = 0,
    trace_filled: bool = false,

    /// The most recent cast the runtime could not decide. Only ever written by
    /// an undecided outcome, so a later success cannot leave a stale failure
    /// latched to be printed at exit as though it were that success's result.
    last_undecided: ?UndecidedRecord = null,

    failure_shapes: [failure_shape_capacity]FailureShape = [_]FailureShape{.{}} ** failure_shape_capacity,
    failure_shape_replace_index: usize = 0,
    failure_reports_emitted: u64 = 0,
    failure_reports_suppressed: u64 = 0,

    pub fn resolve(
        self: *Engine,
        state: anytype,
        source_object: u64,
        source_type: u64,
        destination_type: u64,
        offset_hint_raw: u64,
    ) ?Resolution {
        self.attempts +|= 1;
        const hint: i64 = @bitCast(offset_hint_raw);
        if (hint < 0) self.negative_hints +|= 1;

        const outcome = resolver.resolve(&self.types, state, .{
            .source_object = source_object,
            .source_type = source_type,
            .destination_type = destination_type,
            .hint = hint,
        });

        switch (outcome) {
            .resolved => |resolution| {
                self.resolved +|= 1;
                if (resolution.by_name) self.by_name +|= 1;
                switch (resolution.strategy) {
                    .null_source => self.null_sources +|= 1,
                    .same_type => self.same_type +|= 1,
                    .exact_dynamic_type => {
                        self.exact_dynamic +|= 1;
                        if (!resolution.verified) self.exact_unverified +|= 1;
                    },
                    .hierarchy => self.hierarchy_resolved +|= 1,
                    .cross_cast => self.cross_casts +|= 1,
                    .hint_offset => self.hint_resolved +|= 1,
                    .proven_negative => self.proven_negatives +|= 1,
                }
                if (resolution.strategy != .null_source and resolution.strategy != .same_type) {
                    self.trace(source_object, source_type, destination_type, hint, resolution);
                }
                return resolution;
            },
            .undecided => |reason| {
                self.undecided +|= 1;
                self.last_undecided = .{
                    .source = source_object,
                    .source_type = source_type,
                    .destination_type = destination_type,
                    .hint = hint,
                    .reason = reason,
                };
                return null;
            },
        }
    }

    pub fn undecidedReason(self: *const Engine) ?Undecided {
        const record = self.last_undecided orelse return null;
        return record.reason;
    }

    fn trace(
        self: *Engine,
        source: u64,
        source_type: u64,
        destination_type: u64,
        hint: i64,
        resolution: Resolution,
    ) void {
        self.trace_buffer[self.trace_index] = .{
            .source = source,
            .result = resolution.address,
            .source_type = source_type,
            .destination_type = destination_type,
            .hint = hint,
            .strategy = resolution.strategy,
            .by_name = resolution.by_name,
            .verified = resolution.verified,
        };
        self.trace_index = (self.trace_index + 1) % trace_capacity;
        if (self.trace_index == 0) self.trace_filled = true;
    }

    pub fn logSummary(self: *const Engine) void {
        if (self.attempts == 0) return;
        machoCapturePrint(
            "macho-processor: Itanium dynamic cast: attempts={d} resolved={d} undecided={d} | null_sources={d} same_type={d} exact={d} (unverified={d}) hierarchy={d} cross_casts={d} hint={d} proven_negatives={d} | by_name={d} negative_hints={d} rtti_vtables_learned={d} failure_reports(emitted/suppressed)={d}/{d}; a proven negative is a cast that correctly returned null because the destination is not an unambiguous public base of the dynamic type — the language's own answer, not a failure. Only `undecided` counts casts Rosette could not answer\n",
            .{
                self.attempts,
                self.resolved,
                self.undecided,
                self.null_sources,
                self.same_type,
                self.exact_dynamic,
                self.exact_unverified,
                self.hierarchy_resolved,
                self.cross_casts,
                self.hint_resolved,
                self.proven_negatives,
                self.by_name,
                self.negative_hints,
                self.types.count,
                self.failure_reports_emitted,
                self.failure_reports_suppressed,
            },
        );
    }

    /// Undecided casts can sit in a hot C++ type-test loop. Keep the first
    /// evidence and logarithmic progress rather than the same report on every
    /// iteration. The shape deliberately excludes the object address: different
    /// instances of one source/destination pair are the same ABI problem, not
    /// new evidence.
    pub fn metadataFailureReportDecision(
        self: *Engine,
        source_type: u64,
        destination_type: u64,
        hint: u64,
    ) FailureReportDecision {
        var slot: ?*FailureShape = null;
        var empty: ?*FailureShape = null;
        for (&self.failure_shapes) |*candidate| {
            if (candidate.occurrences == 0) {
                if (empty == null) empty = candidate;
                continue;
            }
            if (candidate.source_type == source_type and
                candidate.destination_type == destination_type and
                candidate.hint == hint)
            {
                slot = candidate;
                break;
            }
        }
        if (slot == null) {
            slot = empty orelse blk: {
                const replacement = &self.failure_shapes[self.failure_shape_replace_index];
                self.failure_shape_replace_index =
                    (self.failure_shape_replace_index + 1) % failure_shape_capacity;
                break :blk replacement;
            };
            slot.?.* = .{
                .source_type = source_type,
                .destination_type = destination_type,
                .hint = hint,
                .occurrences = 0,
            };
        }

        slot.?.occurrences +|= 1;
        const occurrence = slot.?.occurrences;
        const emit = occurrence <= 2 or std.math.isPowerOfTwo(occurrence);
        if (emit) {
            self.failure_reports_emitted +|= 1;
        } else {
            self.failure_reports_suppressed +|= 1;
        }
        return .{
            .emit = emit,
            .occurrence = occurrence,
            .suppressed_total = self.failure_reports_suppressed,
        };
    }

    pub fn dumpTraceBuffer(self: *const Engine, state: anytype) void {
        const count = if (self.trace_filled) trace_capacity else self.trace_index;
        const start = if (self.trace_filled) self.trace_index else 0;
        for (0..count) |offset| {
            const entry = self.trace_buffer[(start + offset) % trace_capacity];
            machoCapturePrint(
                "macho-processor: __dynamic_cast context: strategy={s} by_name={} verified={} source=0x{x} result=0x{x} hint={d} {s} -> {s}\n",
                .{
                    @tagName(entry.strategy),
                    entry.by_name,
                    entry.verified,
                    entry.source,
                    entry.result,
                    entry.hint,
                    rtti.typeName(state, entry.source_type) orelse "<unknown>",
                    rtti.typeName(state, entry.destination_type) orelse "<unknown>",
                },
            );
        }
        const record = self.last_undecided orelse return;
        machoCapturePrint(
            "macho-processor: __dynamic_cast UNDECIDED: source=0x{x} source_type={s} dest_type={s} hint={d} reason={s} ({s}). This is not a failed cast: a cast that correctly returns null resolves to a proven negative and is never reported here\n",
            .{
                record.source,
                rtti.typeName(state, record.source_type) orelse "<unknown>",
                rtti.typeName(state, record.destination_type) orelse "<unknown>",
                record.hint,
                @tagName(record.reason),
                record.reason.describe(),
            },
        );
    }
};

const testing = @import("testing.zig");

test "a resolved cast never latches a failure for a later one to inherit" {
    var state = testing.State{};
    state.writeTypeInfo(0x100, 0x400, 0x700, "7Derived");
    state.writeTypeInfo(0x140, 0x400, 0x730, "4Base");
    state.write64(0x100 + 16, 0x140);
    state.writeObject(0x1000, 0x900, 0, 0x100);

    var engine = Engine{};
    // An object whose vtable pointer is unreadable: undecided, and recorded.
    try std.testing.expect(engine.resolve(&state, 0x2000, 0x140, 0x100, 0) == null);
    try std.testing.expectEqual(@as(u64, 1), engine.undecided);
    try std.testing.expect(engine.undecidedReason() != null);

    const resolution = engine.resolve(&state, 0x1000, 0x140, 0x100, 0).?;
    try std.testing.expectEqual(Strategy.exact_dynamic_type, resolution.strategy);
    try std.testing.expectEqual(@as(u64, 1), engine.exact_dynamic);
    // The earlier failure is still the last *failure*, and still exactly one.
    try std.testing.expectEqual(@as(u64, 1), engine.undecided);
    try std.testing.expectEqual(@as(u64, 2), engine.attempts);
}

test "a proven negative is counted as an answer, not as a shortfall" {
    var state = testing.State{};
    state.writeTypeInfo(0x100, 0x400, 0x700, "7Derived");
    state.writeTypeInfo(0x140, 0x400, 0x730, "4Base");
    state.writeTypeInfo(0x180, 0x400, 0x760, "8Unrelate");
    state.write64(0x100 + 16, 0x140);
    state.writeObject(0x1000, 0x900, 0, 0x100);

    var engine = Engine{};
    const resolution = engine.resolve(&state, 0x1000, 0x140, 0x180, @bitCast(@as(i64, -1))).?;
    try std.testing.expectEqual(Strategy.proven_negative, resolution.strategy);
    try std.testing.expectEqual(@as(u64, 0), resolution.address);
    try std.testing.expectEqual(@as(u64, 1), engine.proven_negatives);
    try std.testing.expectEqual(@as(u64, 0), engine.undecided);
    try std.testing.expectEqual(@as(u64, 1), engine.negative_hints);
}

test "undecided reports keep first evidence and logarithmic progress" {
    var engine = Engine{};
    var emitted: u64 = 0;
    for (1..10) |occurrence| {
        const decision = engine.metadataFailureReportDecision(0x100, 0x200, 0);
        try std.testing.expectEqual(@as(u64, occurrence), decision.occurrence);
        if (decision.emit) emitted += 1;
    }
    // 1, 2, 4 and 8 are kept; the other five repeats are summarized.
    try std.testing.expectEqual(@as(u64, 4), emitted);
    try std.testing.expectEqual(@as(u64, 5), engine.failure_reports_suppressed);

    // A distinct pair is new evidence and is always emitted.
    const distinct = engine.metadataFailureReportDecision(0x100, 0x300, 0);
    try std.testing.expect(distinct.emit);
    try std.testing.expectEqual(@as(u64, 1), distinct.occurrence);
}

test "a null address alone cannot separate the two kinds of null" {
    const negative = Resolution{ .address = 0, .strategy = .proven_negative };
    const null_source = Resolution{ .address = 0, .strategy = .null_source };
    try std.testing.expectEqual(@as(u64, 0), negative.address);
    try std.testing.expectEqual(@as(u64, 0), null_source.address);
    try std.testing.expect(negative.strategy != null_source.strategy);
}
