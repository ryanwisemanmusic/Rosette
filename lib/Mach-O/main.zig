const std = @import("std");
const process = @import("process.zig");
const _ = @import("sha1_tracer");

pub fn main(init: std.process.Init) !void {
    try process.main(init);
}
