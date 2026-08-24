const std = @import("std");
const types = @import("types.zig");
const table = @import("table.zig");
const handlers = @import("handlers.zig");
const xenia_primitive_contract = @import("xenia_primitive_contract");

const Handler = types.Handler;

pub const PrimitiveDef = struct {
    name_pattern: []const u8,
    handler: Handler,
    match_kind: MatchKind = .contains,
};

pub const MatchKind = enum {
    contains,
    exact,
};

pub const PrimitiveRegistry = struct {
    defs: []const PrimitiveDef,
    package_fast_path: bool = false,

    pub fn init(defs: []const PrimitiveDef) PrimitiveRegistry {
        return .{ .defs = defs };
    }

    pub fn matchSymbol(self: *const PrimitiveRegistry, symbol_name: []const u8) ?Handler {
        // The package is only a route-selection index. Every returned handler
        // is one of the existing definitions below, and the general scan stays
        // authoritative for symbols outside the package's narrow families.
        if (self.package_fast_path) {
            if (xenia_primitive_contract.lookup(symbol_name)) |family| {
                return switch (family) {
                    .strlen => handlers.strlen,
                    .memcmp => handlers.memcmp,
                    .memcpy => handlers.memcpy,
                    .strcmp => handlers.strcmp,
                    .cxa_guard_acquire => handlers.cxaGuardAcquire,
                    .cxa_guard_release => handlers.cxaGuardRelease,
                    .cxa_guard_abort => handlers.cxaGuardAbort,
                    .string_compare => handlers.stringCompare,
                    .string_rfind => handlers.stringRFind,
                };
            }
        }
        for (self.defs) |def| {
            const matches = switch (def.match_kind) {
                .contains => std.mem.indexOf(u8, symbol_name, def.name_pattern) != null,
                .exact => std.mem.eql(u8, symbol_name, def.name_pattern),
            };
            if (matches) {
                return def.handler;
            }
        }
        return null;
    }

    pub fn populateTable(self: *const PrimitiveRegistry, pt: *table.PrimitiveTable, symbol_names: []const []const u8) usize {
        var registered: usize = 0;
        for (symbol_names, 0..) |name, slot| {
            if (slot >= pt.slot_count) break;
            if (pt.handlers[slot] != null) continue;
            if (self.matchSymbol(name)) |handler| {
                pt.handlers[slot] = handler;
                registered += 1;
            }
        }
        return registered;
    }
};

const builtin_primitives = [_]PrimitiveDef{
    .{ .name_pattern = "_vsnprintf", .handler = @import("printf_compat.zig").vsnprintf, .match_kind = .exact },
    .{ .name_pattern = "___memmove_chk", .handler = @import("memory_compat.zig").memmoveChk, .match_kind = .exact },
    .{ .name_pattern = "_sysctl", .handler = @import("darwin_compat.zig").sysctl, .match_kind = .exact },
    .{ .name_pattern = "_raise", .handler = @import("handlers.zig").raiseSignal, .match_kind = .exact },
    .{ .name_pattern = "llabs", .handler = @import("handlers.zig").llabs },
    .{ .name_pattern = "strlen", .handler = @import("handlers.zig").strlen },
    .{ .name_pattern = "memcmp", .handler = @import("handlers.zig").memcmp },
    .{ .name_pattern = "memcpy", .handler = @import("handlers.zig").memcpy },
    .{ .name_pattern = "strcmp", .handler = @import("handlers.zig").strcmp },
    .{ .name_pattern = "strncmp", .handler = @import("handlers.zig").strncmp },
    .{ .name_pattern = "__cxa_guard_acquire", .handler = @import("handlers.zig").cxaGuardAcquire },
    .{ .name_pattern = "__cxa_guard_release", .handler = @import("handlers.zig").cxaGuardRelease },
    .{ .name_pattern = "__cxa_guard_abort", .handler = @import("handlers.zig").cxaGuardAbort },
    .{ .name_pattern = "to_string", .handler = @import("handlers.zig").to_string },
    .{ .name_pattern = "5writeEPKc", .handler = @import("handlers.zig").ostreamWrite },
    .{ .name_pattern = "3putEc", .handler = @import("handlers.zig").ostreamPut },
    .{ .name_pattern = "terminatev", .handler = @import("handlers.zig").stdTerminate },
    .{ .name_pattern = "qsort", .handler = @import("handlers.zig").qsort },
    .{ .name_pattern = "_bsearch", .handler = @import("handlers.zig").bsearch, .match_kind = .exact },
    .{ .name_pattern = "pthread_mach_thread_np", .handler = @import("handlers.zig").pthreadMachThreadNp },
    .{ .name_pattern = "dladdr", .handler = @import("handlers.zig").dladdr },
    .{ .name_pattern = "thread_get_state", .handler = @import("handlers.zig").threadGetState },
    .{ .name_pattern = "strncpy", .handler = @import("handlers.zig").strncpy },
    .{ .name_pattern = "strtol", .handler = @import("handlers.zig").strtol },
    .{ .name_pattern = "_abs", .handler = @import("handlers.zig").absInt },
    .{ .name_pattern = "compareEmmPKc", .handler = @import("handlers.zig").stringCompare },
    // basic_string<char>::rfind(char, size_t) const — the trailing `Ecm` pins
    // it to the char overload (rfind(const char*, size_t, size_t) and the
    // string_view overload have different encodings), and the `allocatorIcEEE`
    // prefix pins it to basic_string rather than basic_string_view, whose
    // layout is a bare {data, size} and must not be read as an SSO object.
    // The `B7v160006` spelling is the version-tagged export.
    .{ .name_pattern = "allocatorIcEEE5rfindEcm", .handler = @import("handlers.zig").stringRFind },
    .{ .name_pattern = "allocatorIcEEE5rfindB7v160006Ecm", .handler = @import("handlers.zig").stringRFind },
    .{ .name_pattern = "sentryC1ERS3_", .handler = @import("handlers.zig").sentryC1 },
    // basic_ostream::sentry::~sentry() — D0 (deleting), D1 (complete object)
    // and D2 (base object) destructors. Pattern stops at `sentryD` so the
    // version-tagged spelling (`...6sentryD1B7v160006Ev`) also matches; the
    // handler is a no-op that never dereferences the guest stack sentry.
    .{ .name_pattern = "sentryD1", .handler = @import("handlers.zig").sentryD1 },
    .{ .name_pattern = "sentryD2", .handler = @import("handlers.zig").sentryD1 },
    .{ .name_pattern = "sentryD0", .handler = @import("handlers.zig").sentryD1 },
    .{ .name_pattern = "random_deviceC1E", .handler = @import("handlers.zig").randomDeviceC1 },
    .{ .name_pattern = "random_deviceclEv", .handler = @import("handlers.zig").randomDeviceCl },
    .{ .name_pattern = "random_deviceD1Ev", .handler = @import("handlers.zig").randomDeviceD1 },
};

pub fn builtin() PrimitiveRegistry {
    return .{ .defs = &builtin_primitives, .package_fast_path = true };
}

test "registry: match symbol by pattern" {
    const reg = builtin();
    try std.testing.expect(reg.matchSymbol("_strlen") != null);
    try std.testing.expect(reg.matchSymbol("__cxa_guard_acquire") != null);
    try std.testing.expect(reg.matchSymbol("_vsnprintf") != null);
    try std.testing.expect(reg.matchSymbol("_sysctl") != null);
    try std.testing.expect(reg.matchSymbol("_raise") != null);
    // libc++ basic_ostream::sentry destructor family resolves through the
    // primitive library so stream writes never fall into the unresolved-import
    // path. D1 (complete object) is the observed spelling; D0/D2 and the
    // version-tagged variant share the no-op handler.
    try std.testing.expect(reg.matchSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE6sentryD1Ev") != null);
    try std.testing.expect(reg.matchSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE6sentryD2Ev") != null);
    try std.testing.expect(reg.matchSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE6sentryD0Ev") != null);
    try std.testing.expect(reg.matchSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE6sentryD1B7v160006Ev") != null);
    try std.testing.expect(reg.matchSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE6sentryC1ERS3_") != null);
    // basic_string<char>::rfind(char, size_t) — both the plain and
    // version-tagged spellings resolve through the primitive library, and the
    // basic_string_view overload (whose layout is a bare {data, size} and must
    // not be read as an SSO object) stays unmatched.
    try std.testing.expect(reg.matchSymbol("__ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE5rfindEcm") != null);
    try std.testing.expect(reg.matchSymbol("__ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE5rfindB7v160006Ecm") != null);
    try std.testing.expect(reg.matchSymbol("__ZNKSt3__117basic_string_viewIcNSt11char_traitsIcEEE5rfindEcm") == null);
    try std.testing.expect(reg.matchSymbol("_sysctlbyname") == null);
    try std.testing.expect(reg.matchSymbol("_unknown_function") == null);
}

test "registry: populate table from symbol names" {
    var storage: [5]?Handler = .{null} ** 5;
    var pt = table.PrimitiveTable.init(&storage);

    const symbols = [_][]const u8{
        "_strlen",
        "_memcmp",
        "__cxa_guard_acquire",
        "__cxa_guard_release",
        "strncmp",
    };

    const reg = builtin();
    const count = reg.populateTable(&pt, &symbols);
    try std.testing.expectEqual(@as(usize, 5), count);
    try std.testing.expect(pt.handlers[0] != null);
    try std.testing.expect(pt.handlers[1] != null);
    try std.testing.expect(pt.handlers[2] != null);
    try std.testing.expect(pt.handlers[3] != null);
    try std.testing.expect(pt.handlers[4] != null);
}

test "registry: out of bounds slots do not register" {
    var storage: [1]?Handler = .{null} ** 1;
    var pt = table.PrimitiveTable.init(&storage);

    const symbols = [_][]const u8{ "_strlen", "__cxa_guard_acquire" };
    const reg = builtin();
    const count = reg.populateTable(&pt, &symbols);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "registry: empty defs list matches nothing" {
    const reg = PrimitiveRegistry.init(&.{});
    try std.testing.expect(reg.matchSymbol("_strlen") == null);
}

test "registry: package fast families retain the existing handler route" {
    const reg = builtin();
    try std.testing.expect(xenia_primitive_contract.contractIsWellFormed());
    try std.testing.expect(reg.matchSymbol("_strlen") != null);
    try std.testing.expect(reg.matchSymbol("_memcmp") != null);
    try std.testing.expect(reg.matchSymbol("_memcpy") != null);
    try std.testing.expect(reg.matchSymbol("_strcmp") != null);
    try std.testing.expect(reg.matchSymbol("___cxa_guard_abort") != null);
    try std.testing.expect(reg.matchSymbol("__ZNKSt3__117basic_string_viewIcNSt11char_traitsIcEEE5rfindEcm") == null);
}
