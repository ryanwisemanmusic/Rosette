const std = @import("std");
const process = @import("process.zig");

pub const RunOptions = process.ElfRunOptions;

pub fn loadAndRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8) !u64 {
    return process.loadAndRunElf(allocator, elf_bytes);
}

pub fn main(init: std.process.Init) !void {
    try process.main(init);
}
