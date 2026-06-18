const std = @import("std");
const fmt = @import("../pe_format.zig");
const pkg = @import("../rosette_package.zig");

fn alignForward(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(alignment - 1);
}

fn writeU16(buffer: []u8, offset: usize, value: u16) void {
    buffer[offset] = @truncate(value);
    buffer[offset + 1] = @truncate(value >> 8);
}

fn writeU32(buffer: []u8, offset: usize, value: u32) void {
    buffer[offset] = @truncate(value);
    buffer[offset + 1] = @truncate(value >> 8);
    buffer[offset + 2] = @truncate(value >> 16);
    buffer[offset + 3] = @truncate(value >> 24);
}

fn writeSectionHeader(
    buffer: []u8,
    offset: usize,
    name: []const u8,
    virtual_size: u32,
    virtual_address: u32,
    raw_size: u32,
    raw_offset: u32,
    characteristics: u32,
) void {
    @memset(buffer[offset .. offset + 40], 0);
    @memcpy(buffer[offset .. offset + @min(name.len, 8)], name[0..@min(name.len, 8)]);
    writeU32(buffer, offset + 8, virtual_size);
    writeU32(buffer, offset + 12, virtual_address);
    writeU32(buffer, offset + 16, raw_size);
    writeU32(buffer, offset + 20, raw_offset);
    writeU32(buffer, offset + 36, characteristics);
}

fn makeRelative(allocator: std.mem.Allocator, base_dir: []const u8, target: []const u8) ![]const u8 {
    const trimFn = struct {
        fn trim(p: []const u8) []const u8 {
            var end = p.len;
            while (end > 0 and (p[end - 1] == '/' or p[end - 1] == '\\')) end -= 1;
            return p[0..end];
        }
        fn countParts(p: []const u8) usize {
            var n: usize = 0;
            var i: usize = 0;
            while (i < p.len) {
                while (i < p.len and p[i] == '/') i += 1;
                if (i < p.len) {
                    n += 1;
                    while (i < p.len and p[i] != '/') i += 1;
                }
            }
            return n;
        }
    };
    const base = trimFn.trim(base_dir);
    const tgt = trimFn.trim(target);

    const base_count = trimFn.countParts(base);
    const tgt_count = trimFn.countParts(tgt);

    const base_parts = try allocator.alloc([]const u8, base_count);
    defer allocator.free(base_parts);
    const tgt_parts = try allocator.alloc([]const u8, tgt_count);
    defer allocator.free(tgt_parts);

    {
        var i: usize = 0;
        var pos: usize = 0;
        while (pos < base.len) {
            while (pos < base.len and base[pos] == '/') pos += 1;
            if (pos < base.len) {
                const start = pos;
                while (pos < base.len and base[pos] != '/') pos += 1;
                base_parts[i] = base[start..pos];
                i += 1;
            }
        }
    }
    {
        var i: usize = 0;
        var pos: usize = 0;
        while (pos < tgt.len) {
            while (pos < tgt.len and tgt[pos] == '/') pos += 1;
            if (pos < tgt.len) {
                const start = pos;
                while (pos < tgt.len and tgt[pos] != '/') pos += 1;
                tgt_parts[i] = tgt[start..pos];
                i += 1;
            }
        }
    }

    var common: usize = 0;
    while (common < base_count and common < tgt_count and
        std.mem.eql(u8, base_parts[common], tgt_parts[common]))
    {
        common += 1;
    }

    var result_len: usize = 0;
    for (common..base_count) |_| result_len += 3;
    for (common..tgt_count) |i| {
        if (i > common) result_len += 1;
        result_len += tgt_parts[i].len;
    }
    if (result_len == 0) return allocator.dupe(u8, ".");

    const result = try allocator.alloc(u8, result_len);
    var pos: usize = 0;
    for (common..base_count) |_| {
        @memcpy(result[pos..][0..3], "../");
        pos += 3;
    }
    for (common..tgt_count) |i| {
        if (i > common) {
            result[pos] = '/';
            pos += 1;
        }
        @memcpy(result[pos..][0..tgt_parts[i].len], tgt_parts[i]);
        pos += tgt_parts[i].len;
    }
    return result;
}

fn resolvePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const resolved = try std.fs.path.resolve(allocator, &.{path});
    if (std.fs.path.isAbsolute(resolved)) return resolved;

    const cwd_buf = try allocator.alloc(u8, std.posix.PATH_MAX);
    defer allocator.free(cwd_buf);
    const cwd = std.c.realpath(".", cwd_buf.ptr) orelse return error.CwdResolveFailed;
    return try std.fs.path.resolve(allocator, &.{ std.mem.sliceTo(cwd, 0), resolved });
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 5) {
        std.debug.print("usage: {s} <suite-name> <launch-binary> <working-dir> <output.exe>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const suite_name = args[1];
    const launch_binary = args[2];
    const working_dir = args[3];
    const output_exe = args[4];

    const raw_output_dir = std.fs.path.dirname(output_exe) orelse ".";
    const output_dir = try resolvePath(allocator, raw_output_dir);
    const launch_abs = try resolvePath(allocator, launch_binary);
    const working_dir_abs = try resolvePath(allocator, working_dir);

    const launch_rel = try makeRelative(allocator, output_dir, launch_abs);
    const cwd_rel = try makeRelative(allocator, output_dir, working_dir_abs);

    {
        const host_basename = std.fs.path.basename(launch_abs);
        const dest_host = try std.fs.path.join(allocator, &.{ output_dir, host_basename });
        if (!std.mem.eql(u8, launch_abs, dest_host)) {
            const host_data = try std.Io.Dir.cwd().readFileAlloc(init.io, launch_abs, allocator, .unlimited);
            defer allocator.free(host_data);
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = dest_host, .data = host_data });
        }
    }

    const metadata = try pkg.encodeMetadata(allocator, .{
        .suite = suite_name,
        .launch = launch_rel,
        .cwd = cwd_rel,
        .interactive = true,
    });

    const file_alignment: usize = 0x200;
    const section_alignment: usize = 0x1000;
    const pe_offset: usize = 0x80;
    const size_of_optional_header: usize = 0xE0;
    const section_count: usize = 2;
    const headers_size: usize = file_alignment;

    const text_raw_size: usize = file_alignment;
    const meta_raw_size: usize = alignForward(metadata.len, file_alignment);
    const text_raw_offset: usize = headers_size;
    const meta_raw_offset: usize = text_raw_offset + text_raw_size;
    const total_size: usize = meta_raw_offset + meta_raw_size;

    var bytes = try allocator.alloc(u8, total_size);
    @memset(bytes, 0);

    writeU16(bytes, 0x00, fmt.dos.signature);
    writeU32(bytes, 0x3C, @intCast(pe_offset));

    writeU32(bytes, pe_offset + 0, fmt.coff.signature);
    writeU16(bytes, pe_offset + 4, fmt.coff.machine_i386);
    writeU16(bytes, pe_offset + 6, @intCast(section_count));
    writeU16(bytes, pe_offset + 20, @intCast(size_of_optional_header));
    writeU16(bytes, pe_offset + 22, 0x0102);

    const optional = pe_offset + 24;
    writeU16(bytes, optional + 0, fmt.coff.optional_magic_pe32);
    bytes[optional + 2] = 0;
    bytes[optional + 3] = 0;
    writeU32(bytes, optional + 4, @intCast(text_raw_size));
    writeU32(bytes, optional + 8, @intCast(meta_raw_size));
    writeU32(bytes, optional + 16, 0x1000);
    writeU32(bytes, optional + 20, 0x1000);
    writeU32(bytes, optional + 24, 0x2000);
    writeU32(bytes, optional + 28, 0x400000);
    writeU32(bytes, optional + 32, @intCast(section_alignment));
    writeU32(bytes, optional + 36, @intCast(file_alignment));
    writeU32(bytes, optional + 56, 0x3000);
    writeU32(bytes, optional + 60, @intCast(headers_size));
    writeU16(bytes, optional + 68, 2);
    writeU16(bytes, optional + 76, 5);
    writeU32(bytes, optional + 84, 0x3000);
    writeU32(bytes, optional + 88, @intCast(headers_size));
    writeU16(bytes, optional + 96, 3);
    writeU32(bytes, optional + 100, 0x100000);
    writeU32(bytes, optional + 104, 0x1000);
    writeU32(bytes, optional + 108, 0x100000);
    writeU32(bytes, optional + 112, 0x1000);
    writeU32(bytes, optional + 120, 16);

    const section_table = optional + size_of_optional_header;
    writeSectionHeader(bytes, section_table, ".text", 1, 0x1000, @intCast(text_raw_size), @intCast(text_raw_offset), 0x60000020);
    writeSectionHeader(bytes, section_table + 40, pkg.PackageSectionName, @intCast(metadata.len), 0x2000, @intCast(meta_raw_size), @intCast(meta_raw_offset), 0x40000040);

    bytes[text_raw_offset] = 0xC3;
    @memcpy(bytes[meta_raw_offset .. meta_raw_offset + metadata.len], metadata);

    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = output_exe,
        .data = bytes,
    });
}
