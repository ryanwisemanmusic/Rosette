const std = @import("std");

pub const mode = @import("mode.zig");
pub const ExecutionMode = mode.ExecutionMode;

test {
    std.testing.refAllDecls(@This());
}
