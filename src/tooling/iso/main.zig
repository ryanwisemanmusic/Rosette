const std = @import("std");
const iso = @import("root.zig");

const IsoReader = iso.IsoReader;
const DirectoryEntry = iso.DirectoryEntry;

fn usage(exe_name: []const u8) void {
    std.debug.print(
        \\Rosette ISO 9660 file inspector
        \\
        \\Usage:
        \\  {s} <path/to/image.iso>                  Parse and list root directory
        \\  {s} <path/to/image.iso> --list           List all files recursively
        \\  {s} <path/to/image.iso> --info           Show volume descriptor info
        \\  {s} <path/to/image.iso> --window         Launch a Cocoa overview window (placeholder)
        \\
    , .{ exe_name, exe_name, exe_name, exe_name });
}

fn printVolumeInfo(info: iso.VolumeInfo) void {
    const vol_id = std.mem.sliceTo(@as(*const [32]u8, &info.volume_identifier), 0);
    std.debug.print("Volume identifier: {s}\n", .{vol_id});
    std.debug.print("Total sectors:     {d} ({d} MB)\n", .{ info.total_sectors, @as(u64, info.total_sectors) * iso.sector_size / (1024 * 1024) });
    std.debug.print("Block size:        {d} bytes\n", .{info.logical_block_size});
    std.debug.print("Root directory:    sector {d}, {d} bytes\n", .{ info.root_extent, info.root_length });
    std.debug.print("L-path table:      sector {d}\n", .{info.l_path_table_location});
    std.debug.print("M-path table:      sector {d}\n", .{info.m_path_table_location});

    const app_id = std.mem.sliceTo(@as(*const [128]u8, &info.application_identifier), 0);
    if (app_id.len > 0) {
        std.debug.print("Application:       {s}\n", .{app_id});
    }
    const pub_id = std.mem.sliceTo(@as(*const [128]u8, &info.publisher_identifier), 0);
    if (pub_id.len > 0) {
        std.debug.print("Publisher:         {s}\n", .{pub_id});
    }
    const prep_id = std.mem.sliceTo(@as(*const [128]u8, &info.data_preparer_identifier), 0);
    if (prep_id.len > 0) {
        std.debug.print("Data preparer:     {s}\n", .{prep_id});
    }

    const date_str = info.creation_date.format();
    std.debug.print("Creation date:     {s}\n", .{date_str});
}

fn formatSize(dl: u32, buf: []u8) []u8 {
    const one_mb = @as(u32, 1048576);
    const one_kb = @as(u32, 1024);
    if (dl >= 1048576) {
        return std.fmt.bufPrint(buf, "{} MB", .{dl / one_mb}) catch unreachable;
    }
    if (dl >= 1024) {
        return std.fmt.bufPrint(buf, "{} KB", .{dl / one_kb}) catch unreachable;
    }
    return std.fmt.bufPrint(buf, "{} B", .{dl}) catch unreachable;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        usage(if (args.len > 0) args[0] else "rosette-iso");
        std.process.exit(1);
    }

    const iso_path = args[1];
    var mode_list = false;
    var mode_info = false;
    var mode_window = false;

    for (args[2..]) |arg| {
        if (std.mem.eql(u8, arg, "--list")) {
            mode_list = true;
        } else if (std.mem.eql(u8, arg, "--info")) {
            mode_info = true;
        } else if (std.mem.eql(u8, arg, "--window")) {
            mode_window = true;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            usage(args[0]);
            std.process.exit(1);
        }
    }

    // Default: show info + list root if no mode specified
    if (!mode_list and !mode_info and !mode_window) {
        mode_info = true;
        mode_list = true;
    }

    // Read the ISO file
    const iso_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, iso_path, allocator, .unlimited);
    var reader = try IsoReader.open(allocator, iso_bytes);

    if (mode_info) {
        std.debug.print("\n=== ISO 9660 Volume Info ===\n", .{});
        printVolumeInfo(reader.volume);
    }

    if (mode_list) {
        std.debug.print("\n=== Root Directory ===\n", .{});
        const entries = try reader.listRoot();
        defer allocator.free(entries);

        for (entries) |entry| {
            const name = if (entry.name.len == 0)
                "(root)"
            else if (entry.name.len == 1 and entry.name[0] == 0)
                "."
            else if (entry.name.len == 1 and entry.name[0] == 1)
                ".."
            else
                entry.name;

            var size_buf: [16]u8 = undefined;
            const size_str = formatSize(entry.data_length, &size_buf);

            std.debug.print("  {c} {s:<30} {s:>10}  sector {d}\n", .{
                @as(u8, if (entry.is_directory) 'D' else ' '),
                name,
                size_str,
                entry.extent_location,
            });
        }
    }

    if (mode_window) {
        // Placeholder: Cocoa window forwarding is not yet implemented.
        // Future: launch a native window that displays the ISO volume info
        // and file contents in a structured format.
        std.debug.print("\n  --window mode: Cocoa overview window (not yet implemented)\n", .{});
        std.debug.print("  Volume info:\n", .{});
        printVolumeInfo(reader.volume);
    }
}