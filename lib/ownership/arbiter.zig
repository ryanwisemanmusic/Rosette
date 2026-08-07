//! Single-owner arbitration.
//!
//! The recurring failure in this codebase is not that two subsystems do the
//! same work. It is that two subsystems each believe they own an input, decide
//! independently, and act — so the *order they were written in* becomes the
//! tie-break. The `67 8B 03` fault had five owners; retained execution history
//! had seven; "is this rbp frame usable" had three, with three different
//! answers.
//!
//! An arbiter makes the tie-break explicit. Candidate owners register a claim
//! predicate; `decide` evaluates all of them, and it is an *error* — a reported
//! one, not a silent precedence — for two claims to match the same input.
//! Overlap is the bug, so overlap is what this detects.
//!
//! Deliberately not a framework for the owners themselves. What they do once
//! selected differs in what they prove and what they mutate, and forcing a
//! shared shape on that would hide exactly the differences that matter. This
//! owns the *selection*, and nothing else.

const std = @import("std");

pub fn Outcome(comptime Owner: type) type {
    return struct {
        const Self = @This();

        /// The selected owner, or null when nothing claimed the input.
        owner: ?Owner = null,
        /// Two or more owners claimed it. `owner` holds the first; `conflict`
        /// holds the next. Acting on an ambiguous claim is how ordering becomes
        /// a hidden dependency, so callers should treat this as a defect.
        conflict: ?Owner = null,
        /// Total claims that matched.
        claim_count: usize = 0,

        pub fn decided(self: Self) bool {
            return self.owner != null and self.conflict == null;
        }

        pub fn ambiguous(self: Self) bool {
            return self.conflict != null;
        }

        pub fn unclaimed(self: Self) bool {
            return self.owner == null;
        }
    };
}

/// Build an arbiter over an owner enum and an input type.
///
/// `claims` is evaluated in full on every decision — not short-circuited —
/// because the point is to notice when more than one matches. The cost is a
/// handful of predicate calls on a fault path that is already printing
/// diagnostics.
pub fn Arbiter(comptime Owner: type, comptime Input: type) type {
    return struct {
        const Self = @This();

        pub const Claim = struct {
            owner: Owner,
            matches: *const fn (Input) bool,
        };

        claims: []const Claim,
        /// Decisions that found more than one claimant. Non-zero means two
        /// owners overlap and the codebase has a real ambiguity.
        conflicts: u64 = 0,
        decisions: u64 = 0,
        unclaimed: u64 = 0,

        pub fn init(claims: []const Claim) Self {
            return .{ .claims = claims };
        }

        pub fn decide(self: *Self, input: Input) Outcome(Owner) {
            self.decisions +|= 1;
            var result = Outcome(Owner){};
            for (self.claims) |claim| {
                if (!claim.matches(input)) continue;
                result.claim_count += 1;
                if (result.owner == null) {
                    result.owner = claim.owner;
                } else if (result.conflict == null) {
                    result.conflict = claim.owner;
                }
            }
            if (result.conflict != null) self.conflicts +|= 1;
            if (result.owner == null) self.unclaimed +|= 1;
            return result;
        }

        /// True when every decision so far had at most one claimant. A run that
        /// ends with this false has an ownership defect regardless of whether
        /// anything visibly broke.
        pub fn disjoint(self: Self) bool {
            return self.conflicts == 0;
        }
    };
}

const TestOwner = enum { endian, null_dispatch, null_scalar };
const TestInput = struct { base: u64, address: u64, has_override: bool };

fn claimsEndian(input: TestInput) bool {
    return input.has_override and input.base != 0 and input.base == input.address;
}
fn claimsNullDispatch(input: TestInput) bool {
    return input.has_override and input.base == 0 and input.address == 0;
}
fn claimsNullScalar(input: TestInput) bool {
    return !input.has_override and input.base == 0 and input.address == 0;
}

const TestArbiter = Arbiter(TestOwner, TestInput);
const test_claims = [_]TestArbiter.Claim{
    .{ .owner = .endian, .matches = claimsEndian },
    .{ .owner = .null_dispatch, .matches = claimsNullDispatch },
    .{ .owner = .null_scalar, .matches = claimsNullScalar },
};

test "exactly one owner is selected for a well-formed input" {
    var arbiter = TestArbiter.init(&test_claims);
    const out = arbiter.decide(.{ .base = 0xd42a5882, .address = 0xd42a5882, .has_override = true });
    try std.testing.expect(out.decided());
    try std.testing.expectEqual(TestOwner.endian, out.owner.?);
    try std.testing.expect(arbiter.disjoint());
}

test "an unclaimed input is reported, not defaulted to the first owner" {
    var arbiter = TestArbiter.init(&test_claims);
    const out = arbiter.decide(.{ .base = 0x1000, .address = 0x2000, .has_override = false });
    try std.testing.expect(out.unclaimed());
    try std.testing.expect(!out.decided());
    try std.testing.expectEqual(@as(u64, 1), arbiter.unclaimed);
}

test "overlapping claims are detected instead of resolved by declaration order" {
    // This is the real defect that shipped: the endian gate required
    // `base == address`, which is satisfied when both are zero — so a plain
    // null-base load matched the endian owner *and* the dispatch owner, and the
    // `if` chain silently gave it to whichever was written first.
    fn_overlap: {
        break :fn_overlap;
    }
    const overlapping = [_]TestArbiter.Claim{
        .{ .owner = .endian, .matches = struct {
            fn f(input: TestInput) bool {
                return input.has_override and input.base == input.address;
            }
        }.f },
        .{ .owner = .null_dispatch, .matches = claimsNullDispatch },
    };
    var arbiter = TestArbiter.init(&overlapping);
    const out = arbiter.decide(.{ .base = 0, .address = 0, .has_override = true });
    try std.testing.expect(out.ambiguous());
    try std.testing.expectEqual(@as(usize, 2), out.claim_count);
    try std.testing.expectEqual(TestOwner.endian, out.owner.?);
    try std.testing.expectEqual(TestOwner.null_dispatch, out.conflict.?);
    try std.testing.expect(!arbiter.disjoint());
}

test "disjointness is a property of the whole run, not one decision" {
    var arbiter = TestArbiter.init(&test_claims);
    _ = arbiter.decide(.{ .base = 0, .address = 0, .has_override = true });
    _ = arbiter.decide(.{ .base = 0, .address = 0, .has_override = false });
    try std.testing.expect(arbiter.disjoint());
    try std.testing.expectEqual(@as(u64, 2), arbiter.decisions);
}
