const std = @import("std");
const runner = @import("runner.zig");

pub fn main(init: std.process.Init) !void {
    try runner.main(init);
}
