const std = @import("std");
const types = @import("types.zig");

const GuestAddress = types.GuestAddress;
const HostAddress = types.HostAddress;
const GuestFunction = types.GuestFunction;
const CompileStats = types.CompileStats;

pub const Profiler = struct {
    allocator: std.mem.Allocator,
    functions: std.AutoArrayHashMapUnmanaged(GuestAddress, GuestFunction) = .{},
    compile_stats: CompileStats = .{},

    pub fn init(allocator: std.mem.Allocator) Profiler {
        return Profiler{ .allocator = allocator };
    }

    pub fn deinit(self: *Profiler) void {
        self.functions.deinit(self.allocator);
    }

    pub fn recordCompilation(self: *Profiler, guest_addr: GuestAddress, host_addr: HostAddress, size: usize, elapsed_ns: u64) !void {
        const gop = try self.functions.getOrPut(self.allocator, guest_addr);
        if (!gop.found_existing) {
            gop.value_ptr.* = GuestFunction{
                .guest_addr = guest_addr,
                .host_addr = host_addr,
                .size = size,
                .compile_time_ns = elapsed_ns,
                .call_count = 0,
            };
        }
        self.compile_stats.recordCompilation(elapsed_ns, size);
    }

    pub fn recordExecution(self: *Profiler, guest_addr: GuestAddress, elapsed_ns: u64) void {
        if (self.functions.getPtr(guest_addr)) |func| {
            func.call_count += 1;
            func.total_exec_time_ns += elapsed_ns;
            func.last_exec_time_ns = elapsed_ns;
        }
    }

    pub fn getFunction(self: *const Profiler, guest_addr: GuestAddress) ?GuestFunction {
        return self.functions.get(guest_addr);
    }

    pub fn totalFunctions(self: *const Profiler) usize {
        return self.functions.count();
    }

    pub fn getHotFunctions(self: *const Profiler, top_n: usize, allocator: std.mem.Allocator) ![]GuestFunction {
        var all: std.ArrayListUnmanaged(GuestFunction) = .empty;
        defer all.deinit(allocator);
        var iter = self.functions.iterator();
        while (iter.next()) |entry| {
            try all.append(allocator, entry.value_ptr.*);
        }
        std.mem.sort(GuestFunction, all.items, {}, struct {
            fn lessThan(_: void, a: GuestFunction, b: GuestFunction) bool {
                return a.call_count > b.call_count;
            }
        }.lessThan);
        const count = @min(all.items.len, top_n);
        return try allocator.dupe(GuestFunction, all.items[0..count]);
    }

    pub fn getFunctionsByModule(self: *const Profiler, module_name: []const u8, allocator: std.mem.Allocator) ![]GuestFunction {
        var result: std.ArrayListUnmanaged(GuestFunction) = .empty;
        defer result.deinit(allocator);
        var iter = self.functions.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.module_name, module_name)) {
                try result.append(allocator, entry.value_ptr.*);
            }
        }
        return result.toOwnedSlice(allocator);
    }

    pub fn totalCallCount(self: *const Profiler) u64 {
        var total: u64 = 0;
        var iter = self.functions.iterator();
        while (iter.next()) |entry| {
            total += entry.value_ptr.call_count;
        }
        return total;
    }

    pub fn totalExecTimeNs(self: *const Profiler) u64 {
        var total: u64 = 0;
        var iter = self.functions.iterator();
        while (iter.next()) |entry| {
            total += entry.value_ptr.total_exec_time_ns;
        }
        return total;
    }

    pub fn resetCounts(self: *Profiler) void {
        var iter = self.functions.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.call_count = 0;
            entry.value_ptr.total_exec_time_ns = 0;
            entry.value_ptr.last_exec_time_ns = 0;
        }
    }
};

test "Profiler records compilations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.recordCompilation(0x82000000, 0x10000, 4096, 1_000_000);
    try profiler.recordCompilation(0x82001000, 0x11000, 2048, 500_000);

    try std.testing.expectEqual(@as(usize, 2), profiler.totalFunctions());
    try std.testing.expectEqual(@as(u64, 2), profiler.compile_stats.total_functions_compiled);
    try std.testing.expectEqual(@as(u64, 1_500_000), profiler.compile_stats.total_compile_time_ns);
}

test "Profiler records executions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.recordCompilation(0x82000000, 0x10000, 4096, 1_000_000);
    profiler.recordExecution(0x82000000, 1000);
    profiler.recordExecution(0x82000000, 500);
    profiler.recordExecution(0x82000000, 2000);

    const func = profiler.getFunction(0x82000000) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 3), func.call_count);
    try std.testing.expectEqual(@as(u64, 3500), func.total_exec_time_ns);
    try std.testing.expectEqual(@as(u64, 2000), func.last_exec_time_ns);
}

test "Profiler hot functions sorted by call count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.recordCompilation(0x82000000, 0x10000, 4096, 0);
    try profiler.recordCompilation(0x82001000, 0x11000, 2048, 0);
    try profiler.recordCompilation(0x82002000, 0x12000, 1024, 0);

    profiler.recordExecution(0x82002000, 0);
    profiler.recordExecution(0x82002000, 0);
    profiler.recordExecution(0x82002000, 0);
    profiler.recordExecution(0x82001000, 0);

    const hot = try profiler.getHotFunctions(2, allocator);
    defer allocator.free(hot);

    try std.testing.expectEqual(@as(usize, 2), hot.len);
    try std.testing.expectEqual(@as(GuestAddress, 0x82002000), hot[0].guest_addr);
    try std.testing.expectEqual(@as(GuestAddress, 0x82001000), hot[1].guest_addr);
}

test "Profiler reset clears execution counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.recordCompilation(0x82000000, 0x10000, 4096, 0);
    profiler.recordExecution(0x82000000, 1000);

    try std.testing.expectEqual(@as(u64, 1), profiler.totalCallCount());

    profiler.resetCounts();
    try std.testing.expectEqual(@as(u64, 0), profiler.totalCallCount());
    try std.testing.expectEqual(@as(u64, 0), profiler.totalExecTimeNs());
}
