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
};

pub fn resolve(backend: highway.Backend, request: highway.SimdRequest) Resolution {
    const provider = highway.simdProvider(backend, request);
    return .{
        .provider = provider,
        .instruction = if (provider == .cleo) registry.findByName(request.mnemonic) else null,
    };
}

test "SIMD highway resolves backend requests against the CLEO registry" {
    const request = highway.SimdRequest{ .mnemonic = "VADDPS", .vector_bits = 256, .element_bits = 32 };
    const macho = resolve(.macho64, request);
    try std.testing.expect(macho.executable());
    try std.testing.expectEqualStrings("VADDPS", macho.instruction.?.name);

    const missing = resolve(.pe32, .{ .mnemonic = "NOT_A_REAL_OPCODE", .vector_bits = 128, .element_bits = 32 });
    try std.testing.expect(!missing.executable());
}
