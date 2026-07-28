const std = @import("std");
const process = @import("process.zig");
const _ = @import("sha1_tracer");
const _constants = @import("macho_core").constants;
const _types = @import("macho_core").types;
const _decoder = @import("macho_core").decoder;
const _core = @import("process_core");

pub fn main(init: std.process.Init) !void {
    try process.main(init);
}
