const std = @import("std");

pub const GuestAddress = u32;
pub const HostAddress = u64;

pub const AllocationType = enum {
    reserve,
    commit,
    reserve_and_commit,
};

pub const ThunkType = enum {
    host_to_guest,
    guest_to_host,
};

pub const JitEventKind = enum {
    function_compiled,
    function_executed,
    function_elided,
    code_cache_allocated,
    code_cache_freed,
    thunk_generated,
    guest_to_host_trampoline,
    host_to_guest_call,
    unknown,
};

pub const CodeCacheRegion = struct {
    base_host_addr: HostAddress,
    size: usize,
    allocation_type: AllocationType,
    is_executable: bool,
    is_jit_code: bool,
};

pub const GuestFunction = struct {
    guest_addr: GuestAddress,
    host_addr: HostAddress,
    size: usize,
    module_name: []const u8 = "",
    symbol_name: []const u8 = "",
    compile_time_ns: u64 = 0,
    call_count: u64 = 0,
    total_exec_time_ns: u64 = 0,
    last_exec_time_ns: u64 = 0,
    is_hle: bool = false,
};

pub const JitEvent = struct {
    kind: JitEventKind,
    timestamp_ns: u64,
    thread_id: u64 = 0,
    guest_addr: GuestAddress = 0,
    host_addr: HostAddress = 0,
    size: usize = 0,
    elapsed_ns: u64 = 0,
    module_name: []const u8 = "",
    symbol_name: []const u8 = "",
};

pub const ModuleInfo = struct {
    name: []const u8,
    base_address: GuestAddress,
    size: usize,
    entry_point: GuestAddress,
    function_count: u32,
    is_executable: bool,
};

pub const CompileStats = struct {
    total_functions_compiled: u64 = 0,
    total_compile_time_ns: u64 = 0,
    total_code_cache_bytes: u64 = 0,
    unique_guest_addresses: u64 = 0,
    thunk_count: u64 = 0,
    avg_compile_time_ns: u64 = 0,

    pub fn recordCompilation(self: *CompileStats, elapsed_ns: u64, code_size: usize) void {
        self.total_functions_compiled += 1;
        self.total_compile_time_ns += elapsed_ns;
        self.total_code_cache_bytes += code_size;
        self.avg_compile_time_ns = if (self.total_functions_compiled > 0)
            self.total_compile_time_ns / self.total_functions_compiled
        else
            0;
    }

    pub fn recordThunk(self: *CompileStats) void {
        self.thunk_count += 1;
    }
};

test "CompileStats records compilation correctly" {
    var stats = CompileStats{};
    try std.testing.expectEqual(@as(u64, 0), stats.total_functions_compiled);

    stats.recordCompilation(1_000_000, 4096);
    try std.testing.expectEqual(@as(u64, 1), stats.total_functions_compiled);
    try std.testing.expectEqual(@as(u64, 1_000_000), stats.total_compile_time_ns);
    try std.testing.expectEqual(@as(u64, 4096), stats.total_code_cache_bytes);

    stats.recordCompilation(500_000, 2048);
    try std.testing.expectEqual(@as(u64, 2), stats.total_functions_compiled);
    try std.testing.expectEqual(@as(u64, 750_000), stats.avg_compile_time_ns);
}

test "GuestFunction tracks execution time correctly" {
    var func = GuestFunction{
        .guest_addr = 0x82000000,
        .host_addr = 0x10000,
        .size = 4096,
    };
    try std.testing.expectEqual(@as(u64, 0), func.call_count);

    func.call_count = 5;
    func.total_exec_time_ns = 50_000;
    func.last_exec_time_ns = 10_000;
    try std.testing.expectEqual(@as(u64, 5), func.call_count);
    try std.testing.expectEqual(@as(u64, 50_000), func.total_exec_time_ns);
}
