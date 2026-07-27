const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

pub const Status = enum {
    running,
    completed,
    recovered,
    degraded,
    deferred,
    invalid_target,
    transaction_failed,
    step_limit,
    terminated,
};

pub const DeferralReason = enum {
    none,
    assertion,
    runtime_dependency,
    step_limit,
};

pub const AbiSnapshot = struct {
    rsp: u64,
    rbx: u64,
    rbp: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
};

const ABI_RSP: u8 = 1 << 0;
const ABI_RBX: u8 = 1 << 1;
const ABI_RBP: u8 = 1 << 2;
const ABI_R12: u8 = 1 << 3;
const ABI_R13: u8 = 1 << 4;
const ABI_R14: u8 = 1 << 5;
const ABI_R15: u8 = 1 << 6;

pub const Record = struct {
    index: usize,
    address: u64,
    symbol: []const u8,
    status: Status = .running,
    steps: u64 = 0,
    expected_abi: AbiSnapshot,
    final_abi: AbiSnapshot,
    abi_mismatch: u8 = 0,
    unresolved_before: u64,
    unresolved_after: u64 = 0,
    assertions_before: u64,
    assertions_after: u64 = 0,
    unresolved_observed: u64 = 0,
    assertions_observed: u64 = 0,
    attempts: u8 = 1,
    last_deferral_reason: DeferralReason = .none,
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    expected_count: usize,
    records: std.ArrayList(Record) = .empty,
    current_record: ?usize = null,
    healthy: usize = 0,
    recovered: usize = 0,
    degraded: usize = 0,
    deferred: usize = 0,
    failed: usize = 0,
    total_steps: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, expected_count: usize) Engine {
        return .{ .allocator = allocator, .expected_count = expected_count };
    }

    pub fn deinit(self: *Engine) void {
        self.records.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn begin(
        self: *Engine,
        index: usize,
        address: u64,
        symbol: []const u8,
        expected_abi: AbiSnapshot,
        unresolved_imports: u64,
        assertions: u64,
    ) bool {
        self.records.append(self.allocator, .{
            .index = index,
            .address = address,
            .symbol = symbol,
            .expected_abi = expected_abi,
            .final_abi = expected_abi,
            .unresolved_before = unresolved_imports,
            .assertions_before = assertions,
        }) catch {
            self.current_record = null;
            return false;
        };
        self.current_record = self.records.items.len - 1;
        return true;
    }

    pub fn finish(
        self: *Engine,
        steps: u64,
        final_abi: AbiSnapshot,
        unresolved_imports: u64,
        assertions: u64,
    ) void {
        const record_index = self.current_record orelse return;
        const record = &self.records.items[record_index];
        if (record.attempts == 1) record.steps = steps else record.steps += steps;
        record.final_abi = final_abi;
        record.abi_mismatch = abiMismatch(record.expected_abi, final_abi);
        record.unresolved_after = unresolved_imports;
        record.assertions_after = assertions;
        record.unresolved_observed += unresolved_imports -| record.unresolved_before;
        record.assertions_observed += assertions -| record.assertions_before;
        const healthy = record.abi_mismatch == 0 and
            unresolved_imports == record.unresolved_before and assertions == record.assertions_before;
        if (healthy) {
            if (record.attempts == 1) {
                record.status = .completed;
                self.healthy += 1;
            } else {
                record.status = .recovered;
                self.recovered += 1;
            }
        } else {
            record.status = .degraded;
            self.degraded += 1;
        }
        self.total_steps += steps;
        self.current_record = null;
    }

    pub fn deferCurrent(
        self: *Engine,
        steps: u64,
        final_abi: AbiSnapshot,
        unresolved_imports: u64,
        assertions: u64,
        reason: DeferralReason,
    ) void {
        const record_index = self.current_record orelse return;
        const record = &self.records.items[record_index];
        record.status = .deferred;
        record.steps += steps;
        record.final_abi = final_abi;
        record.abi_mismatch |= abiMismatch(record.expected_abi, final_abi);
        record.unresolved_after = unresolved_imports;
        record.assertions_after = assertions;
        record.unresolved_observed += unresolved_imports -| record.unresolved_before;
        record.assertions_observed += assertions -| record.assertions_before;
        record.last_deferral_reason = reason;
        self.deferred += 1;
        self.total_steps += steps;
        self.current_record = null;
    }

    pub fn retry(
        self: *Engine,
        index: usize,
        expected_abi: AbiSnapshot,
        unresolved_imports: u64,
        assertions: u64,
    ) bool {
        for (self.records.items, 0..) |*record, record_index| {
            if (record.index != index or record.status != .deferred) continue;
            record.status = .running;
            record.expected_abi = expected_abi;
            record.final_abi = expected_abi;
            record.abi_mismatch = 0;
            record.unresolved_before = unresolved_imports;
            record.unresolved_after = unresolved_imports;
            record.assertions_before = assertions;
            record.assertions_after = assertions;
            record.attempts +|= 1;
            self.deferred -= 1;
            self.current_record = record_index;
            return true;
        }
        return false;
    }

    pub fn fail(
        self: *Engine,
        status: Status,
        steps: u64,
        final_abi: AbiSnapshot,
        unresolved_imports: u64,
        assertions: u64,
    ) void {
        const record_index = self.current_record orelse return;
        const record = &self.records.items[record_index];
        record.status = status;
        if (record.attempts == 1) record.steps = steps else record.steps += steps;
        record.final_abi = final_abi;
        record.abi_mismatch = abiMismatch(record.expected_abi, final_abi);
        record.unresolved_after = unresolved_imports;
        record.assertions_after = assertions;
        record.unresolved_observed += unresolved_imports -| record.unresolved_before;
        record.assertions_observed += assertions -| record.assertions_before;
        self.failed += 1;
        self.total_steps += steps;
        self.current_record = null;
    }

    pub fn current(self: *const Engine) ?Record {
        const record_index = self.current_record orelse return null;
        return self.records.items[record_index];
    }

    pub fn hasDegraded(self: *const Engine) bool {
        return self.degraded != 0 or self.deferred != 0 or self.failed != 0;
    }

    pub fn logSummary(self: *const Engine) void {
        machoCapturePrint(
            "macho-processor: initialization resolution summary: expected={d} healthy={d} recovered={d} degraded={d} deferred={d} failed={d} steps={d}\n",
            .{ self.expected_count, self.healthy, self.recovered, self.degraded, self.deferred, self.failed, self.total_steps },
        );
        for (self.records.items) |record| {
            if (record.status == .completed) continue;
            machoCapturePrint(
                "  initializer [{d}/{d}] {s} status={s} attempts={d} steps={d} rsp=0x{x}/0x{x} unresolved_observed={d} assertions_observed={d} abi_mismatch=0x{x} last_deferral={s}\n",
                .{
                    record.index + 1,
                    self.expected_count,
                    record.symbol,
                    @tagName(record.status),
                    record.attempts,
                    record.steps,
                    record.final_abi.rsp,
                    record.expected_abi.rsp,
                    record.unresolved_observed,
                    record.assertions_observed,
                    record.abi_mismatch,
                    @tagName(record.last_deferral_reason),
                },
            );
        }
    }
};

fn abiMismatch(expected: AbiSnapshot, actual: AbiSnapshot) u8 {
    var mismatch: u8 = 0;
    if (actual.rsp != expected.rsp) mismatch |= ABI_RSP;
    if (actual.rbx != expected.rbx) mismatch |= ABI_RBX;
    if (actual.rbp != expected.rbp) mismatch |= ABI_RBP;
    if (actual.r12 != expected.r12) mismatch |= ABI_R12;
    if (actual.r13 != expected.r13) mismatch |= ABI_R13;
    if (actual.r14 != expected.r14) mismatch |= ABI_R14;
    if (actual.r15 != expected.r15) mismatch |= ABI_R15;
    return mismatch;
}

test "initializer engine marks assertion and ABI changes as degraded" {
    var engine = Engine.init(std.testing.allocator, 2);
    defer engine.deinit();
    const initial = AbiSnapshot{ .rsp = 0x2000, .rbx = 1, .rbp = 2, .r12 = 3, .r13 = 4, .r14 = 5, .r15 = 6 };
    try std.testing.expect(engine.begin(0, 0x1000, "first", initial, 0, 0));
    engine.finish(10, initial, 0, 0);
    try std.testing.expect(engine.begin(1, 0x1100, "second", initial, 0, 0));
    var changed = initial;
    changed.rsp = 0x1FF8;
    engine.finish(20, changed, 0, 1);
    try std.testing.expectEqual(@as(usize, 1), engine.healthy);
    try std.testing.expectEqual(@as(usize, 1), engine.degraded);
    try std.testing.expect(engine.hasDegraded());
}

test "initializer engine records terminal failures" {
    var engine = Engine.init(std.testing.allocator, 1);
    defer engine.deinit();
    const initial = AbiSnapshot{ .rsp = 0x2000, .rbx = 1, .rbp = 2, .r12 = 3, .r13 = 4, .r14 = 5, .r15 = 6 };
    try std.testing.expect(engine.begin(0, 0x1000, "failed", initial, 0, 0));
    engine.fail(.terminated, 7, initial, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), engine.failed);
    try std.testing.expectEqual(Status.terminated, engine.records.items[0].status);
}

test "initializer engine records a clean deferred retry as recovered" {
    var engine = Engine.init(std.testing.allocator, 1);
    defer engine.deinit();
    const initial = AbiSnapshot{ .rsp = 0x2000, .rbx = 1, .rbp = 2, .r12 = 3, .r13 = 4, .r14 = 5, .r15 = 6 };
    try std.testing.expect(engine.begin(0, 0x1000, "deferred", initial, 0, 0));
    engine.deferCurrent(7, initial, 0, 1, .assertion);
    try std.testing.expectEqual(@as(usize, 1), engine.deferred);
    try std.testing.expect(engine.retry(0, initial, 0, 1));
    engine.finish(5, initial, 0, 1);
    try std.testing.expectEqual(@as(usize, 0), engine.deferred);
    try std.testing.expectEqual(@as(usize, 1), engine.recovered);
    try std.testing.expectEqual(Status.recovered, engine.records.items[0].status);
    try std.testing.expectEqual(@as(u64, 1), engine.records.items[0].assertions_observed);
    try std.testing.expectEqual(DeferralReason.assertion, engine.records.items[0].last_deferral_reason);
}
