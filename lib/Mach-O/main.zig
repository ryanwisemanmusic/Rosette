const std = @import("std");
const process = @import("process.zig");

pub fn main(init: std.process.Init) !void {
    try process.main(init);
}
