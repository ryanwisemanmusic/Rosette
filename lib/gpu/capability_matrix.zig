//! Explicit capability and export policy matrix.
//!
//! A source label such as `kStub` or a successful host return is not a
//! capability contract. This matrix gives each export/feature a reachability
//! state, behavior class, owner, failure policy, and evidence requirement. It
//! is intentionally fixed-size so a malformed producer cannot grow the audit
//! surface without being counted.

const std = @import("std");
const admission = @import("feature_admission.zig");

pub const Profile = admission.Profile;
pub const capacity: usize = 256;

pub const Reachability = enum(u8) {
    declared,
    imported,
    resolved,
    called,
    conditional_path,
    unreachable_path,
    unobservable_path,

    pub fn label(self: Reachability) []const u8 {
        return switch (self) {
            .declared => "declared",
            .imported => "imported",
            .resolved => "resolved",
            .called => "called",
            .conditional_path => "conditional",
            .unreachable_path => "unreachable",
            .unobservable_path => "unobservable",
        };
    }
};

pub const Behavior = enum(u8) {
    real,
    modeled,
    diagnostic_only,
    synthetic,
    unimplemented,
    forbidden,

    pub fn label(self: Behavior) []const u8 {
        return switch (self) {
            .real => "real",
            .modeled => "modeled",
            .diagnostic_only => "diagnostic-only",
            .synthetic => "synthetic",
            .unimplemented => "unimplemented",
            .forbidden => "forbidden",
        };
    }

    pub fn blocksAuthentic(self: Behavior) bool {
        return self == .diagnostic_only or self == .synthetic or self == .unimplemented or self == .forbidden;
    }
};

pub const Authority = enum(u8) {
    guest_kernel,
    xenos_reference,
    xenia_translator,
    host_api,
    observer,
    unknown,

    pub fn label(self: Authority) []const u8 {
        return switch (self) {
            .guest_kernel => "guest-kernel",
            .xenos_reference => "xenos-reference",
            .xenia_translator => "xenia-translator",
            .host_api => "host-api",
            .observer => "observer",
            .unknown => "unknown",
        };
    }
};

pub const Failure = enum(u8) {
    none,
    unsupported,
    pending,
    fault,
    timeout,
    refused,
    unobserved,

    pub fn label(self: Failure) []const u8 {
        return switch (self) {
            .none => "none",
            .unsupported => "unsupported",
            .pending => "pending",
            .fault => "fault",
            .timeout => "timeout",
            .refused => "refused",
            .unobserved => "unobserved",
        };
    }
};

pub const TestMask = packed struct(u8) {
    unit: bool = false,
    negative: bool = false,
    replay: bool = false,
    contention: bool = false,
    backend: bool = false,
    lifecycle: bool = false,
    reserved: u2 = 0,
};

pub const Entry = struct {
    id: u64 = 0,
    name: []const u8 = "",
    abi_hash: u64 = 0,
    reachability: Reachability = .declared,
    behavior: Behavior = .unimplemented,
    authority: Authority = .unknown,
    failure: Failure = .unobserved,
    required_for_authentic: bool = false,
    evidence_count: u64 = 0,
    effect_before_hash: u64 = 0,
    effect_after_hash: u64 = 0,
    completion_id: u64 = 0,
    dependency_mask: u64 = 0,
    tests: TestMask = .{},
    tainted: bool = false,

    pub fn valid(self: Entry) bool {
        return self.id != 0 and self.name.len != 0 and self.abi_hash != 0 and self.authority != .unknown;
    }

    pub fn evidenceComplete(self: Entry) bool {
        return self.evidence_count != 0 and self.effect_before_hash != 0 and self.effect_after_hash != 0 and self.completion_id != 0;
    }

    pub fn authenticAllowed(self: Entry) bool {
        if (!self.valid() or self.tainted) return false;
        if (!self.required_for_authentic) return true;
        if (self.behavior.blocksAuthentic()) return false;
        if (self.reachability == .unobservable_path) return false;
        return self.evidenceComplete() or self.reachability == .unreachable_path;
    }
};

pub const Matrix = struct {
    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,
    next_id: u64 = 1,
    rejected: u64 = 0,

    pub fn declare(self: *Matrix, name: []const u8, abi_hash: u64, behavior: Behavior, authority: Authority, required: bool) ?u64 {
        if (name.len == 0 or abi_hash == 0 or authority == .unknown or self.count >= capacity) {
            self.rejected +|= 1;
            return null;
        }
        const id = self.next_id;
        self.next_id +|= 1;
        self.entries[self.count] = .{ .id = id, .name = name, .abi_hash = abi_hash, .behavior = behavior, .authority = authority, .required_for_authentic = required };
        self.count += 1;
        return id;
    }

    pub fn find(self: *Matrix, id: u64) ?*Entry {
        for (self.entries[0..self.count]) |*entry| if (entry.id == id) return entry;
        return null;
    }

    pub fn setReachability(self: *Matrix, id: u64, reachability: Reachability) bool {
        const entry = self.find(id) orelse return false;
        entry.reachability = reachability;
        return true;
    }

    pub fn setFailure(self: *Matrix, id: u64, failure: Failure) bool {
        const entry = self.find(id) orelse return false;
        entry.failure = failure;
        return true;
    }

    pub fn noteEvidence(self: *Matrix, id: u64, before_hash: u64, after_hash: u64, completion_id: u64) bool {
        const entry = self.find(id) orelse return false;
        if (before_hash == 0 or after_hash == 0 or completion_id == 0) {
            entry.tainted = true;
            return false;
        }
        entry.evidence_count +|= 1;
        entry.effect_before_hash = before_hash;
        entry.effect_after_hash = after_hash;
        entry.completion_id = completion_id;
        entry.reachability = .called;
        return true;
    }

    pub fn noteTest(self: *Matrix, id: u64, tests: TestMask) bool {
        const entry = self.find(id) orelse return false;
        entry.tests = tests;
        return true;
    }

    pub fn taint(self: *Matrix, id: u64) bool {
        const entry = self.find(id) orelse return false;
        entry.tainted = true;
        return true;
    }

    pub fn authenticReady(self: *const Matrix, profile: Profile) bool {
        if (profile != .authentic or self.rejected != 0) return false;
        for (self.entries[0..self.count]) |entry| if (!entry.authenticAllowed()) return false;
        return true;
    }

    pub fn blockedRequired(self: *const Matrix) usize {
        var total: usize = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.required_for_authentic and !entry.authenticAllowed()) total += 1;
        }
        return total;
    }
};

test "capability rows distinguish called real work from an unimplemented export" {
    var matrix = Matrix{};
    const real = matrix.declare("VdSwap", 1, .real, .guest_kernel, true).?;
    const stub = matrix.declare("VdGetSystemCommandBuffer", 2, .unimplemented, .guest_kernel, true).?;
    try std.testing.expect(matrix.setReachability(real, .called));
    try std.testing.expect(matrix.noteEvidence(real, 3, 4, 5));
    try std.testing.expect(matrix.setReachability(stub, .unreachable_path));
    try std.testing.expectEqual(@as(usize, 1), matrix.blockedRequired());
    try std.testing.expect(!matrix.authenticReady(.authentic));
}

test "an optional unsupported host path is explicit and does not hide an observer gap" {
    var matrix = Matrix{};
    const optional = matrix.declare("optional-rhi", 1, .unimplemented, .host_api, false).?;
    try std.testing.expect(matrix.setFailure(optional, .unsupported));
    try std.testing.expect(matrix.authenticReady(.authentic));
    const required = matrix.declare("actual-presenter", 2, .real, .host_api, true).?;
    try std.testing.expect(matrix.setReachability(required, .unobservable_path));
    try std.testing.expect(!matrix.authenticReady(.authentic));
}

test "evidence requires before and after effects and a completion edge" {
    var matrix = Matrix{};
    const id = matrix.declare("callback", 1, .modeled, .xenia_translator, true).?;
    try std.testing.expect(!matrix.noteEvidence(id, 1, 2, 0));
    try std.testing.expect(matrix.entries[0].tainted);
    try std.testing.expect(matrix.noteEvidence(id, 3, 4, 5));
    // Once an incomplete attempt taints the row, a later clean-looking
    // attempt cannot erase the earlier evidence failure.
    try std.testing.expect(!matrix.entries[0].authenticAllowed());
}

test "diagnostic and synthetic rows can never earn authentic admission" {
    var matrix = Matrix{};
    const diagnostic = matrix.declare("host-refresh", 1, .diagnostic_only, .observer, true).?;
    const synthetic = matrix.declare("forced-swap", 2, .synthetic, .observer, true).?;
    try std.testing.expect(matrix.setReachability(diagnostic, .called));
    try std.testing.expect(matrix.setReachability(synthetic, .called));
    try std.testing.expect(!matrix.authenticReady(.authentic));
    try std.testing.expect(matrix.authenticReady(.diagnostic) == false);
}

test "the matrix is bounded and counts rejected declarations" {
    var matrix = Matrix{};
    try std.testing.expect(matrix.declare("", 1, .real, .host_api, false) == null);
    try std.testing.expect(matrix.declare("bad", 0, .real, .host_api, false) == null);
    try std.testing.expectEqual(@as(u64, 2), matrix.rejected);
}
