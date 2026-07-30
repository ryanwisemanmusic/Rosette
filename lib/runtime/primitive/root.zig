const std = @import("std");

pub const types = @import("types.zig");
pub const table = @import("table.zig");
pub const registry = @import("registry.zig");
pub const handlers = @import("handlers.zig");
pub const printf_compat = @import("printf_compat.zig");
pub const memory_compat = @import("memory_compat.zig");
pub const darwin_compat = @import("darwin_compat.zig");

pub const PrimitiveTable = table.PrimitiveTable;
pub const SlotIndex = types.SlotIndex;
pub const Handler = types.Handler;
pub const Result = types.Result;
pub const PrimitiveContext = types.PrimitiveContext;
pub const PrimitiveRegistry = registry.PrimitiveRegistry;
pub const PrimitiveDef = registry.PrimitiveDef;
pub const builtin = registry.builtin;

test {
    _ = types;
    _ = table;
    _ = registry;
    _ = handlers;
    _ = printf_compat;
    _ = memory_compat;
    _ = darwin_compat;
}
