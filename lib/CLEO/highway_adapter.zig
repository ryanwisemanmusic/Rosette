const std = @import("std");
const highway = @import("isa_highway");
const registry = @import("registry.zig");
const types = @import("types.zig");

pub const Resolution = struct {
    provider: highway.SimdProvider,
    instruction: ?types.InstructionMeta,

    pub fn executable(self: Resolution) bool {
        return self.provider == .cleo and self.instruction != null;
    }

    /// Returns true if the resolved instruction can be handled by CLEO
    /// at the given width.  Checks both the provider match and width
    /// validation against the instruction meta.
    pub fn canExecuteAt(self: Resolution, comptime bits: usize) bool {
        if (!self.executable()) return false;
        const meta = self.instruction orelse return false;
        return bits <= meta.max_width_bits and bits >= types.VECTOR_BLOCK_BITS;
    }
};

/// Resolve an ISA SIMD request against the CLEO registry.
/// Returns the provider (cleo vs native) and the matching instruction meta,
/// or null if the instruction is not found in the CLEO registry.
pub fn resolve(backend: highway.Backend, request: highway.SimdRequest) Resolution {
    const provider = highway.simdProvider(backend, request);
    return .{
        .provider = provider,
        .instruction = if (provider == .cleo) registry.findByName(request.mnemonic) else null,
    };
}

/// Batch-resolve all instructions matching a family name.
/// Useful for the ISA bridge to discover all CLEO-supported instructions
/// in a particular family (e.g., "CONVERT", "PACK", "SHIFT").
pub fn resolveFamily(family: []const u8, allocator: std.mem.Allocator) []types.InstructionMeta {
    var result = std.ArrayList(types.InstructionMeta).init(allocator);
    for (registry.metas) |meta| {
        if (std.ascii.eqlIgnoreCase(meta.family, family)) {
            result.append(meta) catch {};
        }
    }
    return result.items;
}

test "SIMD highway resolves backend requests against the CLEO registry" {
    const request = highway.SimdRequest{ .mnemonic = "VADDPS", .vector_bits = 256, .element_bits = 32 };
    const macho = resolve(.macho64, request);
    try std.testing.expect(macho.executable());
    try std.testing.expectEqualStrings("VADDPS", macho.instruction.?.name);

    const missing = resolve(.pe32, .{ .mnemonic = "NOT_A_REAL_OPCODE", .vector_bits = 128, .element_bits = 32 });
    try std.testing.expect(!missing.executable());

    // Test canExecuteAt with a valid width
    try std.testing.expect(macho.canExecuteAt(256));
    try std.testing.expect(!macho.canExecuteAt(64)); // below min vector block

    // Test family resolution
    const convert_ops = resolveFamily("CONVERT", std.testing.allocator);
    defer std.testing.allocator.free(convert_ops);
    try std.testing.expect(convert_ops.len > 0);
    for (convert_ops) |op| {
        try std.testing.expect(std.ascii.eqlIgnoreCase(op.family, "CONVERT"));
    }
}
