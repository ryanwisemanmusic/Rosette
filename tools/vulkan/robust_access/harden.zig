//! Applies Rosette's robust-access transform (`lib/gpu/vulkan/robust_access.zig`)
//! to SPIR-V files, exactly as the Vulkan bridge does at vkCreateShaderModule.
//!
//!   harden IN.spv OUT.spv          write the hardened module (or a copy)
//!   harden --dir IN_DIR OUT_DIR    every *.spv in IN_DIR, with a total
//!
//! Prints one line per module: what was clamped and whether anything dynamic
//! was left alone. Exit status 1 when a module is refused or keeps an
//! unclamped dynamic index.
const std = @import("std");
const robust = @import("robust");

const Totals = struct {
    modules: u32 = 0,
    hardened: u32 = 0,
    refused: u32 = 0,
    stats: robust.Stats = .{},
};

fn hardenOne(io: std.Io, allocator: std.mem.Allocator, in_dir: std.Io.Dir, name: []const u8, out_dir: std.Io.Dir, out_name: []const u8, totals: *Totals) !void {
    const bytes = try in_dir.readFileAllocOptions(io, name, allocator, .limited(256 << 20), .of(u32), null);
    defer allocator.free(bytes);
    const words: []const u32 = std.mem.bytesAsSlice(u32, bytes);
    const result = try robust.harden(allocator, words);
    defer allocator.free(result.words);
    totals.modules += 1;
    totals.stats.add(result.stats);
    if (result.refusal != .none) totals.refused += 1;
    if (result.changed()) totals.hardened += 1;
    const output: []const u32 = if (result.changed()) result.words else words;
    try out_dir.writeFile(io, .{ .sub_path = out_name, .data = std.mem.sliceAsBytes(output) });
    std.debug.print(
        "{s}: refusal={s} changed={} access_chains={d} runtime={d} fixed={d} component={d} hoisted={d} unclamped={d} interface={d} uniform_zero={d}\n",
        .{ name, result.refusal.label(), result.changed(), result.stats.access_chains, result.stats.runtime_array_clamps, result.stats.fixed_array_clamps, result.stats.component_clamps, result.stats.hoisted_lengths, result.stats.unclamped_dynamic_indices, result.stats.interface_indices, result.stats.uniform_zero_loads },
    );
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.c_allocator;
    const io = init.io;
    const args = try init.minimal.args.toSlice(allocator);
    var totals = Totals{};
    const cwd = std.Io.Dir.cwd();
    if (args.len == 4 and std.mem.eql(u8, args[1], "--dir")) {
        var in_dir = try cwd.openDir(io, args[2], .{ .iterate = true });
        defer in_dir.close(io);
        var out_dir = try cwd.createDirPathOpen(io, args[3], .{});
        defer out_dir.close(io);
        var walker = in_dir.iterate();
        while (try walker.next(io)) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".spv")) continue;
            try hardenOne(io, allocator, in_dir, entry.name, out_dir, entry.name, &totals);
        }
    } else if (args.len == 3) {
        try hardenOne(io, allocator, cwd, args[1], cwd, args[2], &totals);
    } else {
        std.debug.print("usage: harden IN.spv OUT.spv | harden --dir IN_DIR OUT_DIR\n", .{});
        std.process.exit(2);
    }
    std.debug.print(
        "TOTAL modules={d} hardened={d} refused={d} access_chains={d} runtime={d} fixed={d} component={d} hoisted={d} unclamped={d} interface={d} uniform_zero={d}\n",
        .{ totals.modules, totals.hardened, totals.refused, totals.stats.access_chains, totals.stats.runtime_array_clamps, totals.stats.fixed_array_clamps, totals.stats.component_clamps, totals.stats.hoisted_lengths, totals.stats.unclamped_dynamic_indices, totals.stats.interface_indices, totals.stats.uniform_zero_loads },
    );
    if (totals.refused != 0 or totals.stats.unclamped_dynamic_indices != 0) std.process.exit(1);
}
