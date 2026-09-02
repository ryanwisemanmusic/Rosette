//! The evidence ABI Rosette and Xenia share.
//!
//! Rosette and Xenia keep separate diagnostic vocabularies, and the cost is not
//! duplication — it is that two correct sentences about one fact cannot be
//! joined. This package is the small, versioned layer that makes them
//! joinable: fixed-width records, one schema version, and enums whose numeric
//! values mean the same thing in both processes.
//!
//! Human-readable log lines are projections of these records. Where a report
//! and a record disagree, the record is the fact and the report is the bug.

const std = @import("std");

pub const contract = @import("contract.zig");
pub const event = @import("event.zig");
pub const ring = @import("ring.zig");
pub const sync = @import("sync.zig");
pub const frame = @import("frame.zig");
pub const reconcile = @import("reconcile.zig");

pub const schema_version = contract.schema_version;
pub const Domain = contract.Domain;
pub const SourceClass = contract.SourceClass;
pub const ResultClass = contract.ResultClass;
pub const EventKind = contract.EventKind;
pub const Address = contract.Address;
pub const CodeLocation = contract.CodeLocation;
pub const RunIdentity = contract.RunIdentity;
pub const Feature = contract.Feature;
pub const FeatureSet = contract.FeatureSet;

test {
    // Rooted here so these run rather than merely compile. A `pub const` that
    // imports a file does not root its tests, and three modules in this tree
    // turned out to have tests that had never executed.
    _ = contract;
    _ = event;
    _ = ring;
    _ = sync;
    _ = frame;
    _ = reconcile;
}

test "one schema version governs every file in the package" {
    try std.testing.expectEqual(contract.schema_version, schema_version);
    try std.testing.expectEqual(contract.schema_version, (event.Record{}).schema);
    try std.testing.expectEqual(contract.schema_version, (contract.RunIdentity{}).schema);
}
