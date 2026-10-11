//! CPU-only FSI frequency adaptation. Separate from the saved ISO compiler profile.
const std = @import("std");
const sampling = @import("sampling");
pub fn main(init: std.process.Init) !void {
    const alloc = std.heap.c_allocator;
    const args = try init.minimal.args.toSlice(alloc);
    if (args.len != 3) return error.ExpectedInputAndOutputDirectories;
    var input = try std.Io.Dir.cwd().openDir(init.io, args[1], .{ .iterate = true });
    defer input.close(init.io);
    var output = try std.Io.Dir.cwd().createDirPathOpen(init.io, args[2], .{});
    defer output.close(init.io);
    var iter = input.iterate();
    while (try iter.next(init.io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".spv")) continue;
        const bytes = try input.readFileAllocOptions(init.io, entry.name, alloc, .limited(32 << 20), .of(u32), null);
        defer alloc.free(bytes);
        const original = std.mem.bytesAsSlice(u32, bytes);
        const result = try sampling.centerCoordinates(alloc, original);
        defer alloc.free(result.words);
        const words = if (result.words.len != 0) result.words else original;
        try output.writeFile(init.io, .{ .sub_path = entry.name, .data = std.mem.sliceAsBytes(words) });
        std.debug.print("{s}: coordinates={s} centered_loads={d} removed={d}\n", .{ entry.name, @tagName(result.reason), result.centered_loads, result.removed });
    }
}
