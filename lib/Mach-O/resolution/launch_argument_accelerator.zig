const std = @import("std");

pub const MAX_REQUESTED_OPTIONS: usize = 64;

pub const Filter = struct {
    requested: [MAX_REQUESTED_OPTIONS][]const u8 = [_][]const u8{""} ** MAX_REQUESTED_OPTIONS,
    requested_count: usize = 0,
    registrations_seen: u64 = 0,
    registrations_kept: u64 = 0,
    registrations_skipped: u64 = 0,

    pub fn configure(self: *Filter, args: []const []const u8) void {
        self.requested_count = 0;
        for (args) |arg| {
            if (!std.mem.startsWith(u8, arg, "--") or arg.len <= 2) continue;
            var name = arg[2..];
            if (std.mem.indexOfScalar(u8, name, '=')) |equals| name = name[0..equals];
            if (std.mem.startsWith(u8, name, "no-") and name.len > 3) name = name[3..];
            self.appendUnique(name);
        }
        self.appendUnique("help");
    }

    pub fn shouldRegister(self: *Filter, name: []const u8) bool {
        self.registrations_seen +|= 1;
        for (self.requested[0..self.requested_count]) |requested| {
            if (std.mem.eql(u8, requested, name)) {
                self.registrations_kept +|= 1;
                return true;
            }
        }
        self.registrations_skipped +|= 1;
        return false;
    }

    pub fn request(self: *Filter, name: []const u8) void {
        if (name.len != 0) self.appendUnique(name);
    }

    pub fn logSummary(self: *const Filter) void {
        std.debug.print(
            "macho-processor: launch option acceleration: requested={d} seen={d} kept={d} skipped={d}\n",
            .{ self.requested_count, self.registrations_seen, self.registrations_kept, self.registrations_skipped },
        );
    }

    pub fn logConfiguration(self: *const Filter, target_count: usize) void {
        std.debug.print("macho-processor: launch option acceleration armed: targets={d} requested=", .{target_count});
        for (self.requested[0..self.requested_count], 0..) |name, index| {
            if (index != 0) std.debug.print(",", .{});
            std.debug.print("{s}", .{name});
        }
        std.debug.print("\n", .{});
    }

    fn appendUnique(self: *Filter, name: []const u8) void {
        for (self.requested[0..self.requested_count]) |existing| {
            if (std.mem.eql(u8, existing, name)) return;
        }
        if (self.requested_count == self.requested.len) return;
        self.requested[self.requested_count] = name;
        self.requested_count += 1;
    }
};

test "filter keeps only options present on the command line" {
    var filter = Filter{};
    const args = [_][]const u8{ "program", "--gpu=vulkan", "--log_to_stdout", "false", "game.iso" };
    filter.configure(&args);

    try std.testing.expect(filter.shouldRegister("gpu"));
    try std.testing.expect(filter.shouldRegister("log_to_stdout"));
    try std.testing.expect(filter.shouldRegister("help"));
    try std.testing.expect(!filter.shouldRegister("unused_option"));
    try std.testing.expectEqual(@as(u64, 3), filter.registrations_kept);
    try std.testing.expectEqual(@as(u64, 1), filter.registrations_skipped);
}

test "negative boolean spelling selects the underlying option" {
    var filter = Filter{};
    const args = [_][]const u8{ "program", "--no-vsync" };
    filter.configure(&args);
    try std.testing.expect(filter.shouldRegister("vsync"));
}

test "positional options can be requested after argv configuration" {
    var filter = Filter{};
    const args = [_][]const u8{ "program", "game.iso" };
    filter.configure(&args);
    filter.request("target");
    try std.testing.expect(filter.shouldRegister("target"));
}
