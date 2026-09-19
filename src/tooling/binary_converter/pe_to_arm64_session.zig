const std = @import("std");
const parser = @import("../exe_parser/pe_parser.zig");
const fmt = @import("../exe_parser/pe_format.zig");
const mandatory_trace = @import("../exe_parser/mandatory_trace.zig");

pub const Session = struct {
    allocator: std.mem.Allocator,
    log_path_z: [:0]const u8,

    pub fn init(allocator: std.mem.Allocator, log_path_z: [:0]const u8) Session {
        return .{
            .allocator = allocator,
            .log_path_z = log_path_z,
        };
    }

    pub fn begin(self: Session, image_bytes: []const u8) !parser.Image {
        mandatory_trace.enable(self.log_path_z.ptr);
        errdefer mandatory_trace.disable();

        const image = try parser.parse(self.allocator, image_bytes);
        try self.validateMachine(image.machine);
        return image;
    }

    pub fn end(_: Session) void {
        mandatory_trace.disable();
    }

    fn validateMachine(_: Session, machine: u16) !void {
        switch (machine) {
            fmt.coff.machine_i386, fmt.coff.machine_amd64 => {},
            else => return error.UnsupportedMachine,
        }
    }
};

test "session enforces PE machine gate" {
    var bytes = [_]u8{0} ** 0x600;
    std.mem.writeInt(u16, bytes[0x00..0x02], fmt.dos.signature, .little);
    std.mem.writeInt(u32, bytes[0x3C..0x40], 0x80, .little);
    std.mem.writeInt(u32, bytes[0x80..0x84], fmt.coff.signature, .little);
    std.mem.writeInt(u16, bytes[0x84..0x86], fmt.coff.machine_i386, .little);
    std.mem.writeInt(u16, bytes[0x86..0x88], 0, .little);
    std.mem.writeInt(u16, bytes[0x94..0x96], 0xE0, .little);
    std.mem.writeInt(u16, bytes[0x98..0x9A], fmt.coff.optional_magic_pe32, .little);
    std.mem.writeInt(u32, bytes[0xB8..0xBC], 0x1000, .little);
    std.mem.writeInt(u32, bytes[0xBC..0xC0], 0x200, .little);
    std.mem.writeInt(u32, bytes[0xD0..0xD4], 0x1000, .little);
    std.mem.writeInt(u32, bytes[0xD4..0xD8], 0x400, .little);

    const session = Session.init(std.testing.allocator, "pe-session.log");
    const image = try session.begin(&bytes);
    defer std.testing.allocator.free(image.sections);
    session.end();
}
