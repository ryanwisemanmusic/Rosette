const std = @import("std");
pub const types = @import("types.zig");
pub const registry = @import("registry.zig");
pub const ops = @import("ops.zig");
pub const wide = @import("wide.zig");

/// Routing decision returned by the universal decoder pipeline.
pub const RoutingDecision = struct {
    /// Whether CLEO can handle this instruction
    can_route: bool,
    /// The matching InstructionMeta from the registry (if found)
    meta: ?types.InstructionMeta,
    /// The feature set required for execution
    features: types.FeatureSet,
};

/// Shared integration point for routing decoded instructions to CLEO.
/// Both the Mach-O decoder and ELF processor should import and use this
/// module to determine if a decoded instruction can be executed via CLEO.
pub const CleoRouter = struct {
    /// Lookup an instruction by name in the CLEO registry.
    /// Returns the InstructionMeta if found, or null if not registered.
    pub fn findInstruction(name: []const u8) ?types.InstructionMeta {
        return registry.findByName(name);
    }

    /// Check if a given operation is supported by CLEO for the given
    /// features.  Returns true if the meta is found and the instruction
    /// can be executed with the available features.
    pub fn isInstructionSupported(meta: types.InstructionMeta, features: types.FeatureSet) bool {
        return types.safetyReport(meta, features).ok();
    }

    /// Route a decoded instruction to CLEO.  Returns a RoutingDecision
    /// that the caller can use to dispatch execution.
    ///
    /// `op_width_bits` is the decoded operand width (128, 256, 512, etc.).
    /// CLEO handles all widths that match the instruction meta's
    /// `max_width_bits`.  Pass 0 to skip the width check.
    pub fn route(name: []const u8, features: types.FeatureSet, op_width_bits: usize) RoutingDecision {
        const meta = registry.findByName(name) orelse {
            return RoutingDecision{
                .can_route = false,
                .meta = null,
                .features = features,
            };
        };
        if (op_width_bits > 0 and op_width_bits > meta.max_width_bits) {
            // Instruction width exceeds CLEO's max width for this meta
            return RoutingDecision{
                .can_route = false,
                .meta = meta,
                .features = features,
            };
        }
        if (!isInstructionSupported(meta, features)) {
            return RoutingDecision{
                .can_route = false,
                .meta = meta,
                .features = features,
            };
        }
        return RoutingDecision{
            .can_route = true,
            .meta = meta,
            .features = features,
        };
    }

    /// Count the number of registered metas that are available with
    /// the given feature set.  Useful for progress reporting.
    pub fn availableCount(features: types.FeatureSet) usize {
        return registry.completedCount(features);
    }

    /// Total number of metas in the registry.
    pub fn totalCount() usize {
        return registry.tableCount();
    }
};

test "CleoRouter basic lookup" {
    // VADDPS should be found (registered as ADDPS in AVX)
    const meta = CleoRouter.findInstruction("ADDPS");
    try std.testing.expect(meta != null);
    if (meta) |m| {
        try std.testing.expectEqualStrings("ADDPS", m.name);
    }

    // Non-existent instruction
    try std.testing.expect(CleoRouter.findInstruction("NONEXISTENT") == null);
}

test "CleoRouter feature-aware routing" {
    const all_features = types.FeatureSet.all();
    const count = CleoRouter.availableCount(all_features);
    try std.testing.expectEqual(CleoRouter.totalCount(), count);
    try std.testing.expect(count > 0);
}
