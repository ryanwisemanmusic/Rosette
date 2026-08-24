const std = @import("std");
const contract = @import("contract.zig");
const catalogue = @import("host_contract_catalogue");

const MatchPattern = contract.MatchPattern;
const ContractKind = contract.ContractKind;
const ResolutionStrategy = contract.ResolutionStrategy;
const Contract = contract.Contract;

pub const ContractRegistry = struct {
    allocator: std.mem.Allocator,
    contracts: []const Contract = &.{},

    pub fn init(allocator: std.mem.Allocator) ContractRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ContractRegistry) void {
        if (self.contracts.len != 0) self.allocator.free(self.contracts);
    }

    pub fn register(self: *ContractRegistry, c: Contract) !void {
        const slice = try self.allocator.alloc(Contract, self.contracts.len + 1);
        @memcpy(slice[0..self.contracts.len], self.contracts);
        slice[self.contracts.len] = c;
        if (self.contracts.len != 0) self.allocator.free(self.contracts);
        self.contracts = slice;
    }

    pub fn registerMany(self: *ContractRegistry, contracts: []const Contract) !void {
        for (contracts) |c| try self.register(c);
    }

    pub fn lookup(self: *const ContractRegistry, name: []const u8) ?Contract {
        for (self.contracts) |c| {
            if (std.mem.eql(u8, c.name, name)) return c;
        }
        return null;
    }

    pub fn resolve(self: *const ContractRegistry, symbol: []const u8) ?Contract {
        var best: ?Contract = null;
        var best_preference: usize = 0;

        for (self.contracts) |c| {
            if (!c.matchesSymbol(symbol)) continue;
            const preference = matchPreference(c, symbol);
            if (best == null or preference > best_preference) {
                best = c;
                best_preference = preference;
            }
        }
        return best;
    }
};

fn matchPreference(c: Contract, symbol: []const u8) usize {
    for (c.matches, 0..) |pattern, idx| {
        if (!pattern.matches(symbol)) continue;
        return switch (pattern) {
            .exact => 100,
            .mangled_prefix => 80 - idx,
            .prefix => 60 - idx,
            .suffix => 40 - idx,
            .contains => 20 - idx,
        };
    }
    return 0;
}

pub const DispatchOutcome = union(enum) {
    handled: u64,
    terminated: u64,
};

pub fn dispatchContract(registry: *const ContractRegistry, symbol: []const u8, rdi: u64) ?DispatchOutcome {
    const c = registry.resolve(symbol) orelse return null;
    return dispatchSingle(c, rdi);
}

fn dispatchSingle(c: Contract, rdi: u64) ?DispatchOutcome {
    return switch (c.strategy) {
        .stub => DispatchOutcome{ .handled = 0 },
        .synthesize => if (c.returns.fixed) |val| DispatchOutcome{ .handled = val } else null,
        .terminate => DispatchOutcome{ .terminated = rdi & 0xFF },
        else => null,
    };
}

/// Resolve a symbol to its contract, or null.
///
/// Delegated: the package walks the same families in the same order and returns
/// the same answer, but rejects most non-matching symbols with a single bit
/// test instead of a substring search per pattern. This runs on the import slow
/// path, which took roughly 150,000 of 514,000 dispatches in a recorded run.
pub fn resolveFromAllFamilies(name: []const u8) ?Contract {
    return catalogue.resolve(name);
}

pub fn dispatchFromAllFamilies(name: []const u8, rdi: u64) ?DispatchOutcome {
    const c = resolveFromAllFamilies(name) orelse return null;
    return dispatchSingle(c, rdi);
}

// The eight contract families moved to
// `pkg/common/abi/host-contract-catalogue`. They are a description of the
// host ABI Rosette was built against, so they are resolved at build time,
// and the package also precomputes the rejection filter that makes
// `resolveFromAllFamilies` cheap on the import slow path. Everything that
// needs the running process — match ranking, dispatch, the registry — stays
// here.
pub const PosixContracts = catalogue.PosixContracts;
pub const PosixExtendedContracts = catalogue.PosixExtendedContracts;
pub const TimeContracts = catalogue.TimeContracts;
pub const FileIoContracts = catalogue.FileIoContracts;
pub const StdioContracts = catalogue.StdioContracts;
pub const MiscContracts = catalogue.MiscContracts;
pub const CxxContracts = catalogue.CxxContracts;
pub const ObjcContracts = catalogue.ObjcContracts;

test "dispatchContract handles stub strategy" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "test_stub",
        .description = "",
        .kind = .posix_thread,
        .strategy = .stub,
        .matches = &.{MatchPattern{ .exact = "_pthread_join" }},
    });
    const result = dispatchContract(&registry, "_pthread_join", 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 0), result.?.handled);
}

test "dispatchContract handles synthesize with fixed value" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "test_synthesize",
        .description = "",
        .kind = .posix_user,
        .strategy = .synthesize,
        .matches = &.{MatchPattern{ .exact = "_getuid" }},
        .returns = .{ .fixed = 501 },
    });
    const result = dispatchContract(&registry, "_getuid", 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 501), result.?.handled);
}

test "dispatchContract handles terminate strategy" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "test_terminate",
        .description = "",
        .kind = .posix_process,
        .strategy = .terminate,
        .matches = &.{MatchPattern{ .exact = "exit" }},
    });
    const result = dispatchContract(&registry, "exit", 42);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 42), result.?.terminated);
}

test "dispatchContract returns null for forward_to_host" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "test_forward",
        .description = "",
        .kind = .posix_file_io,
        .strategy = .forward_to_host,
        .matches = &.{MatchPattern{ .exact = "_open" }},
    });
    const result = dispatchContract(&registry, "_open", 0);
    try std.testing.expect(result == null);
}

test "__cxa_throw is reserved for the stateful exception handler" {
    const resolved = resolveFromAllFamilies("___cxa_throw");
    try std.testing.expect(resolved != null);
    try std.testing.expectEqual(ResolutionStrategy.custom_handler, resolved.?.strategy);
    try std.testing.expect(dispatchFromAllFamilies("___cxa_throw", 0x47c9560) == null);
}

test "dispatchContract returns null for unknown symbol" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    const result = dispatchContract(&registry, "_nonexistent", 0);
    try std.testing.expect(result == null);
}

test "ContractRegistry resolves exact match" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());

    const result = registry.resolve("_exit");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ContractKind.posix_process, result.?.kind);
    try std.testing.expectEqual(ResolutionStrategy.terminate, result.?.strategy);
}

test "ContractRegistry resolves suffix match" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());

    const result = registry.resolve("_memcpy");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ContractKind.libc_string, result.?.kind);
}

test "ContractRegistry resolves prefix match" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(ObjcContracts.all());

    const result = registry.resolve("_objc_msgSend");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ContractKind.objc_messaging, result.?.kind);
}

test "ContractRegistry resolves contains match" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(CxxContracts.all());

    const result = registry.resolve("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEPKcm");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ContractKind.cxx_string, result.?.kind);
}

test "ContractRegistry resolve prefers exact over prefix" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "exit_generic",
        .description = "Generic exit with prefix match",
        .kind = .posix_process,
        .strategy = .stub,
        .matches = &.{MatchPattern{ .prefix = "_exit" }},
    });
    try registry.register(Contract{
        .name = "exit",
        .description = "Exact exit match",
        .kind = .posix_process,
        .strategy = .terminate,
        .matches = &.{MatchPattern{ .exact = "_exit" }},
    });

    const result = registry.resolve("_exit");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("exit", result.?.name);
    try std.testing.expectEqual(ResolutionStrategy.terminate, result.?.strategy);
}

test "ContractRegistry returns null for unknown symbol" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());

    const result = registry.resolve("_nonexistent_function");
    try std.testing.expect(result == null);
}

test "ContractRegistry lookup by name" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());

    const c = registry.lookup("getenv");
    try std.testing.expect(c != null);
    try std.testing.expectEqualStrings("_getenv", c.?.matches[0].exact);
}

test "Contracts from all families resolve known symbols" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());
    try registry.registerMany(PosixExtendedContracts.all());
    try registry.registerMany(TimeContracts.all());
    try registry.registerMany(FileIoContracts.all());
    try registry.registerMany(StdioContracts.all());
    try registry.registerMany(MiscContracts.all());
    try registry.registerMany(CxxContracts.all());
    try registry.registerMany(ObjcContracts.all());

    try std.testing.expect(registry.resolve("_exit") != null);
    try std.testing.expect(registry.resolve("_objc_getClass") != null);
    try std.testing.expect(registry.resolve("___cxa_throw") != null);
    try std.testing.expect(registry.resolve("_gtk_init_check") != null);
    try std.testing.expect(registry.resolve("_strcmp") != null);
    try std.testing.expect(registry.resolve("_pthread_create") != null);
    try std.testing.expect(registry.resolve("_pthread_main_np") != null);
    try std.testing.expect(registry.resolve("_pthread_join") != null);
    try std.testing.expect(registry.resolve("_open") != null);
    try std.testing.expect(registry.resolve("_fopen") != null);
    try std.testing.expect(registry.resolve("_clock_gettime") != null);
    try std.testing.expect(registry.resolve("_localtime") != null);
    try std.testing.expect(registry.resolve("_gtk_dialog_run") != null);
    try std.testing.expect(registry.resolve("_objc_autoreleasePoolPop") != null);
    try std.testing.expect(registry.resolve("____chkstk_darwin") != null);
    try std.testing.expect(registry.resolve("__ZNSt20bad_array_new_lengthC1Ev") != null);
    try std.testing.expect(registry.resolve("__shared_weak_count14__release_weakEv") != null);
    try std.testing.expect(registry.resolve("__ZNSt3__16threadD1Ev") != null);
    try std.testing.expect(registry.resolve("__ZNSt3__15mutex4lockEv") != null);
    try std.testing.expect(registry.resolve("recursive_mutex4lockEv") != null);
    try std.testing.expect(registry.resolve("recursive_mutex8try_lockEv") != null);
}

test "dispatchContract handles all trivially-dispatchable contracts" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());
    try registry.registerMany(PosixExtendedContracts.all());
    try registry.registerMany(MiscContracts.all());
    try registry.registerMany(CxxContracts.all());

    const stubs = [_][]const u8{
        "_pthread_attr_setstacksize",
        "_pthread_attr_destroy",
        "_pthread_join",
        "_pthread_detach",
        "_objc_autoreleasePoolPop",
        "__shared_weak_count14__release_weakEv",
        "__ZNSt3__16threadD1Ev",
        "__ZNSt3__15mutex4lockEv",
        "__ZNSt3__15mutex6unlockEv",
        "recursive_mutex4lockEv",
        "recursive_mutex6unlockEv",
        "_gtk_dialog_run",
        "_gtk_widget_destroy",
        "_localtime",
    };
    for (stubs) |name| {
        const result = dispatchContract(&registry, name, 0);
        try std.testing.expect(result != null);
        try std.testing.expectEqual(@as(u64, 0), result.?.handled);
    }

    const synthesized = [_]struct { name: []const u8, expected: u64 }{
        .{ .name = "_pthread_main_np", .expected = 1 },
        .{ .name = "_getuid", .expected = 501 },
        .{ .name = "_gtk_init_check", .expected = 1 },
        .{ .name = "_gtk_message_dialog_new", .expected = 1 },
        .{ .name = "_gtk_dialog_get_type", .expected = 1 },
        .{ .name = "recursive_mutex8try_lockEv", .expected = 1 },
    };
    for (synthesized) |pair| {
        const result = dispatchContract(&registry, pair.name, 0);
        if (result == null) {
            std.debug.print("FAIL: {s} not dispatched\n", .{pair.name});
            return error.TestUnexpectedResult;
        }
        try std.testing.expectEqual(pair.expected, result.?.handled);
    }
}

test "resolveFromAllFamilies finds known symbols without registry allocation" {
    try std.testing.expect(resolveFromAllFamilies("_exit") != null);
    try std.testing.expect(resolveFromAllFamilies("_pthread_main_np") != null);
    try std.testing.expect(resolveFromAllFamilies("_gtk_dialog_run") != null);
    try std.testing.expect(resolveFromAllFamilies("__ZNSt3__15mutex4lockEv") != null);
    try std.testing.expect(resolveFromAllFamilies("_nonexistent_sym_12345") == null);
}

test "dispatchFromAllFamilies dispatches stub and synthesize contracts" {
    const stub_result = dispatchFromAllFamilies("_pthread_attr_destroy", 0);
    try std.testing.expect(stub_result != null);
    try std.testing.expectEqual(@as(u64, 0), stub_result.?.handled);

    const synth_result = dispatchFromAllFamilies("_pthread_main_np", 0);
    try std.testing.expect(synth_result != null);
    try std.testing.expectEqual(@as(u64, 1), synth_result.?.handled);

    const term_result = dispatchFromAllFamilies("_exit", 42);
    try std.testing.expect(term_result != null);
    try std.testing.expectEqual(@as(u64, 42), term_result.?.terminated);
}

test "dispatchFromAllFamilies returns null for forward_to_host contracts" {
    const result = dispatchFromAllFamilies("_open", 0);
    try std.testing.expect(result == null);
}

test "dispatchFromAllFamilies returns null for unknown symbols" {
    const result = dispatchFromAllFamilies("_nonexistent_function", 0);
    try std.testing.expect(result == null);
}
