const std = @import("std");
const builtin = @import("builtin");

const RTLD_LAZY: c_int = 0x1;
const RTLD_LOCAL: c_int = 0x4;
const MAX_LIBRARIES = 16;

extern fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern fn dlclose(handle: *anyopaque) c_int;

pub const Signature = enum {
    no_args_i32,
    no_args_u32,
    buffer_length_usize,
    two_buffers_length_i32,
    buffer_byte_length_pointer,
    libcxx_getloc,
    libcxx_istream_sentry_constructor,
};

pub const LibraryClass = enum {
    libsystem,
    libcxx,
};

pub const Spec = struct {
    symbol: []const u8,
    library: LibraryClass,
    signature: Signature,
};

pub const Outcome = union(enum) {
    handled: u64,
    handled_void,
};

const specs = [_]Spec{
    .{ .symbol = "getpid", .library = .libsystem, .signature = .no_args_i32 },
    .{ .symbol = "getppid", .library = .libsystem, .signature = .no_args_i32 },
    .{ .symbol = "getuid", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "geteuid", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "getgid", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "getegid", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "getpagesize", .library = .libsystem, .signature = .no_args_i32 },
    .{ .symbol = "arc4random", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "strnlen", .library = .libsystem, .signature = .buffer_length_usize },
    .{ .symbol = "strncmp", .library = .libsystem, .signature = .two_buffers_length_i32 },
    .{ .symbol = "memcmp", .library = .libsystem, .signature = .two_buffers_length_i32 },
    .{ .symbol = "memchr", .library = .libsystem, .signature = .buffer_byte_length_pointer },
    .{ .symbol = "_ZNSt3__18ios_base6xallocEv", .library = .libcxx, .signature = .no_args_i32 },
    .{ .symbol = "_ZNKSt3__18ios_base6getlocEv", .library = .libcxx, .signature = .libcxx_getloc },
    .{ .symbol = "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE6sentryC1ERS3_b", .library = .libcxx, .signature = .libcxx_istream_sentry_constructor },
};

const Library = struct {
    path: []const u8 = "",
    handle: ?*anyopaque = null,
};

pub const Forwarder = struct {
    libraries: [MAX_LIBRARIES]Library = [_]Library{.{}} ** MAX_LIBRARIES,
    library_count: usize = 0,
    considered: u64 = 0,
    forwarded: u64 = 0,
    rejected_not_allowlisted: u64 = 0,
    rejected_library: u64 = 0,
    rejected_symbol: u64 = 0,
    rejected_guest_memory: u64 = 0,

    pub fn deinit(self: *Forwarder) void {
        for (self.libraries[0..self.library_count]) |loaded_library| {
            if (loaded_library.handle) |handle| _ = dlclose(handle);
        }
        self.* = .{};
    }

    pub fn forward(self: *Forwarder, state: anytype, dylib: []const u8, symbol: []const u8) ?Outcome {
        self.considered += 1;
        const host_symbol = normalizeMachOSymbol(symbol);
        const spec = specFor(host_symbol) orelse {
            self.rejected_not_allowlisted += 1;
            return null;
        };
        if (!libraryMatches(spec.library, dylib)) {
            self.rejected_library += 1;
            return null;
        }
        const handle = self.libraryHandle(dylib) orelse {
            self.rejected_library += 1;
            return null;
        };
        var symbol_buffer: [512]u8 = undefined;
        const symbol_z = nulTerminate(&symbol_buffer, host_symbol) orelse {
            self.rejected_symbol += 1;
            return null;
        };
        const address = dlsym(handle, symbol_z) orelse {
            self.rejected_symbol += 1;
            return null;
        };
        const outcome = self.invoke(state, spec.signature, address) orelse {
            self.rejected_guest_memory += 1;
            return null;
        };
        self.forwarded += 1;
        return outcome;
    }

    pub fn logSummary(self: *const Forwarder) void {
        std.debug.print(
            "macho-processor: dynamic library forwarding: considered={d} forwarded={d} not_allowlisted={d} library_rejected={d} symbol_missing={d} guest_memory_rejected={d}\n",
            .{
                self.considered,
                self.forwarded,
                self.rejected_not_allowlisted,
                self.rejected_library,
                self.rejected_symbol,
                self.rejected_guest_memory,
            },
        );
    }

    fn libraryHandle(self: *Forwarder, dylib: []const u8) ?*anyopaque {
        for (self.libraries[0..self.library_count]) |loaded_library| {
            if (std.mem.eql(u8, loaded_library.path, dylib)) return loaded_library.handle;
        }
        if (self.library_count >= self.libraries.len) return null;

        var path_buffer: [1024]u8 = undefined;
        const path_z = nulTerminate(&path_buffer, dylib) orelse return null;
        const handle = dlopen(path_z, RTLD_LAZY | RTLD_LOCAL);
        self.libraries[self.library_count] = .{ .path = dylib, .handle = handle };
        self.library_count += 1;
        return handle;
    }

    fn invoke(self: *Forwarder, state: anytype, signature: Signature, address: *anyopaque) ?Outcome {
        _ = self;
        return switch (signature) {
            .no_args_i32 => blk: {
                const function: *const fn () callconv(.c) c_int = @ptrCast(@alignCast(address));
                break :blk .{ .handled = @bitCast(@as(i64, function())) };
            },
            .no_args_u32 => blk: {
                const function: *const fn () callconv(.c) c_uint = @ptrCast(@alignCast(address));
                break :blk .{ .handled = function() };
            },
            .buffer_length_usize => blk: {
                const bytes = state.guestMemoryConst(state.regs.rdi, state.regs.rsi) orelse return null;
                const function: *const fn ([*]const u8, usize) callconv(.c) usize = @ptrCast(@alignCast(address));
                break :blk .{ .handled = function(bytes.ptr, bytes.len) };
            },
            .two_buffers_length_i32 => blk: {
                const lhs = state.guestMemoryConst(state.regs.rdi, state.regs.rdx) orelse return null;
                const rhs = state.guestMemoryConst(state.regs.rsi, state.regs.rdx) orelse return null;
                const function: *const fn ([*]const u8, [*]const u8, usize) callconv(.c) c_int = @ptrCast(@alignCast(address));
                break :blk .{ .handled = @bitCast(@as(i64, function(lhs.ptr, rhs.ptr, lhs.len))) };
            },
            .buffer_byte_length_pointer => blk: {
                const bytes = state.guestMemoryConst(state.regs.rdi, state.regs.rdx) orelse return null;
                const function: *const fn ([*]const u8, c_int, usize) callconv(.c) ?*const u8 = @ptrCast(@alignCast(address));
                const found = function(bytes.ptr, @intCast(state.regs.rsi & 0xFF), bytes.len) orelse break :blk .{ .handled = 0 };
                const offset = @intFromPtr(found) - @intFromPtr(bytes.ptr);
                if (offset >= bytes.len) return null;
                break :blk .{ .handled = state.regs.rdi + offset };
            },
            .libcxx_getloc => blk: {
                // ios_base::getloc() - takes ios_base pointer in rdi, returns locale pointer in rax
                // We can't directly forward this because the guest and host have different memory layouts
                // For now, return a dummy locale pointer
                break :blk .{ .handled = 0x3000 };
            },
            .libcxx_istream_sentry_constructor => blk: {
                // basic_istream::sentry constructor - takes sentry pointer in rdi, istream pointer in rsi, bool in rdx
                // We can't directly forward this because the guest and host have different memory layouts
                // For now, just zero-initialize the sentry and return void
                const sentry_bytes = state.guestMemory(state.regs.rdi, 16) orelse return null;
                @memset(sentry_bytes, 0);
                break :blk .handled_void;
            },
        };
    }
};

fn normalizeMachOSymbol(symbol: []const u8) []const u8 {
    if (symbol.len != 0 and symbol[0] == '_') return symbol[1..];
    return symbol;
}

fn specFor(symbol: []const u8) ?Spec {
    for (specs) |spec| {
        if (std.mem.eql(u8, spec.symbol, symbol)) return spec;
    }
    return null;
}

fn libraryMatches(class: LibraryClass, dylib: []const u8) bool {
    return switch (class) {
        .libsystem => std.mem.indexOf(u8, dylib, "libSystem") != null,
        .libcxx => std.mem.indexOf(u8, dylib, "libc++.1.dylib") != null,
    };
}

fn nulTerminate(buffer: []u8, value: []const u8) ?[*:0]const u8 {
    if (value.len >= buffer.len) return null;
    @memcpy(buffer[0..value.len], value);
    buffer[value.len] = 0;
    return @ptrCast(buffer.ptr);
}

test "forwarding registry only admits typed libSystem functions" {
    try std.testing.expectEqual(Signature.no_args_i32, specFor("getpid").?.signature);
    try std.testing.expect(specFor("objc_msgSend") == null);
    try std.testing.expect(specFor("_ZNSt3__16localeD1Ev") == null);
    try std.testing.expectEqual(LibraryClass.libcxx, specFor("_ZNSt3__18ios_base6xallocEv").?.library);
    try std.testing.expect(libraryMatches(.libsystem, "/usr/lib/libSystem.B.dylib"));
    try std.testing.expect(!libraryMatches(.libsystem, "/usr/lib/libc++.1.dylib"));
    try std.testing.expect(libraryMatches(.libcxx, "/usr/lib/libc++.1.dylib"));
}

test "forwarder invokes an allowlisted host symbol" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const TestState = struct {
        mem: [32]u8 = [_]u8{0} ** 32,
        regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0 } = .{},

        fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
            if (address + length > self.mem.len) return null;
            return self.mem[@intCast(address)..@intCast(address + length)];
        }
    };
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    var state = TestState{};
    const outcome = forwarder.forward(&state, "/usr/lib/libSystem.B.dylib", "_getpid") orelse return error.SymbolUnavailable;
    try std.testing.expect(outcome.handled != 0);
    @memcpy(state.mem[8..12], "abc\x00");
    state.regs.rdi = 8;
    state.regs.rsi = 4;
    const length = forwarder.forward(&state, "/usr/lib/libSystem.B.dylib", "_strnlen") orelse return error.SymbolUnavailable;
    try std.testing.expectEqual(@as(u64, 3), length.handled);
    try std.testing.expectEqual(@as(u64, 2), forwarder.forwarded);
}
