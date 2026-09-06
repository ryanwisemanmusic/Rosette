//! The process-wide ownership envelope for a Rosette-hosted application.
//!
//! A hosted application can have many legitimate internal authorities: Xenia
//! owns its Vulkan objects, the title owns its guest-visible state, and SDL or
//! AppKit own the objects they created. Those are subordinate truths while the
//! process is inside Rosette. Keeping the envelope separate from each
//! subsystem's semantic owner prevents a log field named `owner` from silently
//! changing meaning between reports.

const std = @import("std");

pub const schema_version: u16 = 1;
pub const root_owner: []const u8 = "rosette";
pub const unknown_subowner: []const u8 = "unknown";

/// The authority that controls admission of the hosted process and its native
/// window. There is intentionally one value: a process cannot have two master
/// owners merely because it has several internal domains.
pub const Owner = enum(u8) {
    rosette,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .rosette => root_owner,
        };
    }
};

/// A subordinate domain's claim as seen through the Rosette hosting boundary.
/// The label is intentionally a string rather than a closed enum: Xenia and
/// future hosted applications may introduce internal domains without changing
/// the root ownership ABI. Subsystems should still use their own typed enums
/// for semantic decisions.
pub const Scope = struct {
    owner: Owner = .rosette,
    subowner: []const u8 = unknown_subowner,

    pub fn ownerLabel(self: Scope) []const u8 {
        return self.owner.label();
    }

    pub fn wellFormed(self: Scope) bool {
        return self.owner == .rosette and validToken(self.subowner) and
            !std.mem.eql(u8, self.subowner, root_owner);
    }

    pub fn known(self: Scope) bool {
        return self.wellFormed() and !std.mem.eql(u8, self.subowner, unknown_subowner);
    }
};

/// Build a scope for an existing subsystem/domain label. Empty labels become
/// an explicit `unknown` value instead of producing an unparseable empty
/// field. That makes missing attribution visible without pretending to know
/// which subordinate domain was involved.
pub fn forSubowner(label: []const u8) Scope {
    return .{ .subowner = if (label.len == 0) unknown_subowner else label };
}

pub fn rootScope() Scope {
    return forSubowner(unknown_subowner);
}

pub fn validToken(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| {
        switch (byte) {
            'a'...'z', 'A'...'Z', '0'...'9', ':', '-', '_', '.', '/' => {},
            else => return false,
        }
    }
    return true;
}

pub fn contractIsWellFormed() bool {
    return schema_version != 0 and
        std.mem.eql(u8, root_owner, "rosette") and
        validToken(root_owner) and
        validToken(unknown_subowner) and
        !std.mem.eql(u8, root_owner, unknown_subowner) and
        rootScope().wellFormed() and
        !rootScope().known();
}

test "the ownership envelope has one root owner" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expectEqualStrings("rosette", Owner.rosette.label());
    try std.testing.expectEqual(Owner.rosette, (Scope{}).owner);
}

test "subowners are explicit and parseable" {
    const xenia = forSubowner("xenia:vulkan");
    try std.testing.expect(xenia.wellFormed());
    try std.testing.expect(xenia.known());
    try std.testing.expectEqualStrings("rosette", xenia.ownerLabel());
    try std.testing.expectEqualStrings("xenia:vulkan", xenia.subowner);
}

test "empty and whitespace-bearing labels cannot become ownership claims" {
    const empty = forSubowner("");
    try std.testing.expect(empty.wellFormed());
    try std.testing.expect(!empty.known());
    try std.testing.expect(!validToken("xenia vulkan"));
    try std.testing.expect(!validToken("xenia=vulkan"));
}

test "the root cannot be relabeled as its own subowner" {
    try std.testing.expect(!(@as(Scope, .{ .subowner = root_owner })).wellFormed());
    try std.testing.expect(forSubowner("rosette:runtime").wellFormed());
}
