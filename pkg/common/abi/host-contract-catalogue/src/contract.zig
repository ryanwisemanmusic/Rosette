const std = @import("std");

pub const ContractKind = enum {
    objc_runtime,
    objc_messaging,
    objc_memory,
    cxx_string,
    cxx_locale,
    cxx_guard,
    cxx_exception,
    cxx_regex,
    cxx_mutex,
    cxx_condition,
    cxx_thread,
    cxx_chrono,
    cxx_ios,
    cxx_memory,
    cxx_type_info,
    cxx_algorithm,
    cxx_filesystem,
    posix_file_io,
    posix_memory,
    posix_thread,
    posix_time,
    posix_environment,
    posix_process,
    posix_user,
    libc_string,
    libc_stdio,
    libc_ctype,
    libc_stdlib,
    gtk_ui,
    generic_allocator,
    custom,
};

pub const ResolutionStrategy = enum {
    forward_to_host,
    synthesize,
    stub,
    terminate,
    custom_handler,
};

pub const MatchPattern = union(enum) {
    exact: []const u8,
    prefix: []const u8,
    suffix: []const u8,
    contains: []const u8,
    mangled_prefix: []const u8,

    pub fn matches(self: MatchPattern, symbol: []const u8) bool {
        return switch (self) {
            .exact => |e| std.mem.eql(u8, e, symbol),
            .prefix => |p| std.mem.startsWith(u8, symbol, p),
            .suffix => |s| std.mem.endsWith(u8, symbol, s),
            .contains => |c| std.mem.indexOf(u8, symbol, c) != null,
            .mangled_prefix => |p| std.mem.startsWith(u8, symbol, p),
        };
    }
};

pub const Parameter = struct {
    index: u5,
    is_ptr: bool = false,
    is_cstring: bool = false,
    label: []const u8 = "",
};

pub const ReturnPolicy = struct {
    fixed: ?u64 = null,
    result_is_ptr: bool = false,
    passthrough_arg: ?u5 = null,
};

pub const Contract = struct {
    name: []const u8,
    description: []const u8,
    kind: ContractKind,
    strategy: ResolutionStrategy,
    matches: []const MatchPattern,
    params: []const Parameter = &.{},
    returns: ReturnPolicy = .{},
    data: []const u8 = "",

    pub fn matchesSymbol(self: Contract, symbol: []const u8) bool {
        for (self.matches) |pattern| {
            if (pattern.matches(symbol)) return true;
        }
        return false;
    }
};

test "MatchPattern exact matches correctly" {
    const p = MatchPattern{ .exact = "_exit" };
    try std.testing.expect(p.matches("_exit"));
    try std.testing.expect(!p.matches("_exits"));
    try std.testing.expect(!p.matches("exit"));
}

test "MatchPattern prefix matches correctly" {
    const p = MatchPattern{ .prefix = "_objc_" };
    try std.testing.expect(p.matches("_objc_msgSend"));
    try std.testing.expect(p.matches("_objc_getClass"));
    try std.testing.expect(!p.matches("objc_msgSend"));
}

test "MatchPattern suffix matches correctly" {
    const p = MatchPattern{ .suffix = "_malloc" };
    try std.testing.expect(p.matches("_malloc"));
    try std.testing.expect(p.matches("__rust_alloc_malloc"));
    try std.testing.expect(!p.matches("malloc_"));
}

test "MatchPattern contains matches correctly" {
    const p = MatchPattern{ .contains = "basic_string" };
    try std.testing.expect(p.matches("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEPKcm"));
    try std.testing.expect(!p.matches("_strcpy"));
}

test "Contract matchesSymbol delegates to patterns" {
    const c = Contract{
        .name = "exit",
        .description = "Terminate the guest process",
        .kind = .posix_process,
        .strategy = .terminate,
        .matches = &.{
            MatchPattern{ .exact = "_exit" },
            MatchPattern{ .exact = "exit" },
        },
    };
    try std.testing.expect(c.matchesSymbol("_exit"));
    try std.testing.expect(c.matchesSymbol("exit"));
    try std.testing.expect(!c.matchesSymbol("_Exit"));
}

test "Contract with multiple match patterns" {
    const c = Contract{
        .name = "pthread_mutex",
        .description = "Pthread mutex operations",
        .kind = .posix_thread,
        .strategy = .stub,
        .matches = &.{
            MatchPattern{ .prefix = "_pthread_mutex" },
            MatchPattern{ .prefix = "_pthread_rwlock" },
        },
    };
    try std.testing.expect(c.matchesSymbol("_pthread_mutex_lock"));
    try std.testing.expect(c.matchesSymbol("_pthread_rwlock_rdlock"));
    try std.testing.expect(!c.matchesSymbol("_pthread_create"));
}
