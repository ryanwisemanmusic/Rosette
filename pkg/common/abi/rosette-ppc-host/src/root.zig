//! Static catalogue for Rosette's direct PowerPC host ABI.
//!
//! Xenia discovers this provider through `dlsym(RTLD_DEFAULT, ...)`. The
//! spelling of each symbol and whether the backend may proceed without it are
//! build-time contract facts; symbol lookup, guest thunk allocation and the
//! callbacks behind those thunks are live runtime behavior in `lib`.

const std = @import("std");

pub const abi_version: u32 = 2;

pub const Symbol = enum {
    host_available,
    host_identity,
    bind_context,
    release_context,
    set_recompiler_enabled,
    recompiler_stats,
    invalidate_range,
    execute,

    pub fn name(self: Symbol) []const u8 {
        return switch (self) {
            .host_available => "rosette_ppc_host_available",
            .host_identity => "rosette_ppc_host_identity",
            .bind_context => "rosette_ppc_bind_context",
            .release_context => "rosette_ppc_release_context",
            .set_recompiler_enabled => "rosette_ppc_set_recompiler_enabled",
            .recompiler_stats => "rosette_ppc_recompiler_stats",
            .invalidate_range => "rosette_ppc_invalidate_range",
            .execute => "rosette_ppc_execute",
        };
    }

    /// A direct PPC backend cannot initialize without these entry points.
    pub fn required(self: Symbol) bool {
        return switch (self) {
            .host_available, .bind_context, .release_context, .execute, .invalidate_range => true,
            .host_identity, .set_recompiler_enabled, .recompiler_stats => false,
        };
    }

    pub fn fromName(symbol: []const u8) ?Symbol {
        inline for (@typeInfo(Symbol).@"enum".fields) |field| {
            const candidate: Symbol = @enumFromInt(field.value);
            if (std.mem.eql(u8, symbol, candidate.name())) return candidate;
        }
        return null;
    }
};

pub const symbols = [_]Symbol{
    .host_available,
    .host_identity,
    .bind_context,
    .release_context,
    .set_recompiler_enabled,
    .recompiler_stats,
    .invalidate_range,
    .execute,
};

test "the direct PPC ABI catalogue is complete" {
    try std.testing.expectEqual(@as(usize, 8), symbols.len);
    try std.testing.expectEqual(Symbol.host_available, Symbol.fromName("rosette_ppc_host_available").?);
    try std.testing.expectEqual(Symbol.execute, Symbol.fromName("rosette_ppc_execute").?);
    try std.testing.expect(Symbol.host_available.required());
    try std.testing.expect(!Symbol.host_identity.required());
}

test "ABI version is explicit and stable" {
    try std.testing.expectEqual(@as(u32, 2), abi_version);
}
