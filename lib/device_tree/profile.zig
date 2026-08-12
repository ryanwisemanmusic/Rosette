const std = @import("std");
const schema = @import("schema.zig");
const format = @import("format.zig");

/// Conservative Xenia integration profile. The file contains ownership and
/// format facts only; runtime adapter/device capabilities are overlaid from the
/// backend's observed description and remain read-only.
pub fn xeniaSafe(allocator: std.mem.Allocator) !schema.Tree {
    return format.loadJson(allocator, @embedFile("profiles/xenia-safe.device-tree.json"));
}

test "safe Xenia profile cannot synthesize guest GPU startup" {
    const tree = try xeniaSafe(std.testing.allocator);
    const gate = tree.property("/consumer/xenia/gpu", "allow-synthetic-bootstrap") orelse
        return error.MissingSafetyGate;
    try std.testing.expect(!gate.value.boolean);
    try std.testing.expectEqual(schema.Mutability.read_only, gate.mutability);

    const publication_owner = tree.property(
        "/consumer/xenia/gpu",
        "submission-publication-owner",
    ) orelse return error.MissingPublicationOwner;
    try std.testing.expectEqualStrings(
        "authentic-guest",
        publication_owner.value.text.slice(),
    );

    const implication = tree.property(
        "/consumer/xenia/gpu",
        "prepared-payload-implies-published-write-pointer",
    ) orelse return error.MissingPublicationInvariant;
    try std.testing.expect(!implication.value.boolean);
    try std.testing.expectEqual(schema.Mutability.read_only, implication.mutability);
}
