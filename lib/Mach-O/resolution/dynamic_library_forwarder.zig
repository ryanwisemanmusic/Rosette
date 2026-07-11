const std = @import("std");
const builtin = @import("builtin");

const RTLD_LAZY: c_int = 0x1;
const RTLD_LOCAL: c_int = 0x4;
const MAX_LIBRARIES = 16;
const MAX_GUEST_LIBRARIES = 32;
const MAX_GUEST_SYMBOLS = 256;
const GUEST_LIBRARY_HANDLE_BASE: u64 = 0xFFFF_FC00_0000_0000;
const GUEST_SYMBOL_THUNK_BASE: u64 = 0xFFFF_FB00_0000_0000;

extern fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern fn dlclose(handle: *anyopaque) c_int;

pub const Signature = enum {
    no_args_i32,
    no_args_u32,
    buffer_length_usize,
    two_buffers_length_i32,
    buffer_byte_length_pointer,
    guest_memory_copy,
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
    .{ .symbol = "memcpy", .library = .libsystem, .signature = .guest_memory_copy },
    .{ .symbol = "_ZNSt3__18ios_base6xallocEv", .library = .libcxx, .signature = .no_args_i32 },
    .{ .symbol = "_ZNKSt3__18ios_base6getlocEv", .library = .libcxx, .signature = .libcxx_getloc },
    .{ .symbol = "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE6sentryC1ERS3_b", .library = .libcxx, .signature = .libcxx_istream_sentry_constructor },
};

const Library = struct {
    path: []const u8 = "",
    handle: ?*anyopaque = null,
};

const GuestLibrary = struct {
    token: u64 = 0,
    handle: ?*anyopaque = null,
};

const GuestSymbolKind = enum {
    get_instance_proc_addr,
    destroy_instance,
    @"opaque",
};

const GuestSymbol = struct {
    token: u64 = 0,
    library_token: u64 = 0,
    kind: GuestSymbolKind = .@"opaque",
};

pub const Forwarder = struct {
    libraries: [MAX_LIBRARIES]Library = [_]Library{.{}} ** MAX_LIBRARIES,
    library_count: usize = 0,
    guest_libraries: [MAX_GUEST_LIBRARIES]GuestLibrary = [_]GuestLibrary{.{}} ** MAX_GUEST_LIBRARIES,
    guest_symbols: [MAX_GUEST_SYMBOLS]GuestSymbol = [_]GuestSymbol{.{}} ** MAX_GUEST_SYMBOLS,
    guest_open_count: u64 = 0,
    guest_close_count: u64 = 0,
    guest_lookup_count: u64 = 0,
    guest_thunk_calls: u64 = 0,
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
        for (&self.guest_libraries) |*loaded_library| {
            if (loaded_library.handle) |handle| _ = dlclose(handle);
            loaded_library.* = .{};
        }
        self.* = .{};
    }

    pub fn lookupGuest(self: *Forwarder, library_token: u64, symbol: []const u8) u64 {
        const library = self.guestLibrary(library_token) orelse return 0;
        var symbol_buffer: [512]u8 = undefined;
        const symbol_z = nulTerminate(&symbol_buffer, symbol) orelse return 0;
        _ = dlsym(library, symbol_z) orelse return 0;
        const kind: GuestSymbolKind = if (std.mem.eql(u8, symbol, "vkGetInstanceProcAddr"))
            .get_instance_proc_addr
        else if (std.mem.eql(u8, symbol, "vkDestroyInstance"))
            .destroy_instance
        else
            .@"opaque";
        for (&self.guest_symbols, 0..) |*entry, index| {
            if (entry.token != 0) continue;
            const token = GUEST_SYMBOL_THUNK_BASE + @as(u64, @intCast(index)) * 16 + 1;
            entry.* = .{ .token = token, .library_token = library_token, .kind = kind };
            self.guest_lookup_count +|= 1;
            return token;
        }
        return 0;
    }

    pub fn dispatchGuestSymbol(self: *Forwarder, state: anytype, token: u64) bool {
        for (&self.guest_symbols) |*entry| {
            if (entry.token != token) continue;
            if (self.guestLibrary(entry.library_token) == null) return false;
            self.guest_thunk_calls +|= 1;
            switch (entry.kind) {
                .get_instance_proc_addr => {
                    const symbol = state.guestCString(state.regs.rsi, 512) orelse {
                        state.regs.rax = 0;
                        return true;
                    };
                    const result = self.lookupGuest(entry.library_token, symbol);
                    if (result != 0) state.registerSyntheticThunk(result, 1, symbol);
                    state.regs.rax = result;
                },
                .destroy_instance => state.regs.rax = 0,
                // A non-null lookup remains useful for capability discovery,
                // but calling an untyped ARM64 function through x86 registers
                // is unsafe. Keep it contained until its Vulkan ABI signature
                // has an explicit bridge.
                .@"opaque" => state.regs.rax = 0,
            }
            return true;
        }
        return false;
    }

    pub fn openGuest(self: *Forwarder, path: []const u8, mode: u64) u64 {
        var path_buffer: [1024]u8 = undefined;
        const path_z = nulTerminate(&path_buffer, path) orelse return 0;
        const host_mode: c_int = @bitCast(@as(u32, @truncate(mode)));
        const host_handle = dlopen(path_z, host_mode) orelse return 0;
        for (&self.guest_libraries, 0..) |*entry, index| {
            if (entry.token != 0) continue;
            const token = GUEST_LIBRARY_HANDLE_BASE + @as(u64, @intCast(index)) * 16 + 1;
            entry.* = .{ .token = token, .handle = host_handle };
            self.guest_open_count +|= 1;
            return token;
        }
        _ = dlclose(host_handle);
        return 0;
    }

    pub fn closeGuest(self: *Forwarder, token: u64) c_int {
        for (&self.guest_libraries) |*entry| {
            if (entry.token != token) continue;
            const result = if (entry.handle) |handle| dlclose(handle) else -1;
            entry.* = .{};
            for (&self.guest_symbols) |*symbol| {
                if (symbol.library_token == token) symbol.* = .{};
            }
            if (result == 0) self.guest_close_count +|= 1;
            return result;
        }
        return -1;
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
        if (spec.signature == .guest_memory_copy) {
            const length: usize = @intCast(state.regs.rdx);
            if (length != 0) {
                const destination = state.guestMemory(state.regs.rdi, state.regs.rdx) orelse {
                    self.rejected_guest_memory += 1;
                    return null;
                };
                const source = state.guestMemoryConst(state.regs.rsi, state.regs.rdx) orelse {
                    self.rejected_guest_memory += 1;
                    return null;
                };
                std.mem.copyForwards(u8, destination[0..length], source[0..length]);
            }
            self.forwarded += 1;
            return .{ .handled = state.regs.rdi };
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
            "macho-processor: dynamic library forwarding: considered={d} forwarded={d} guest_open={d} guest_close={d} guest_lookup={d} guest_thunk_calls={d} not_allowlisted={d} library_rejected={d} symbol_missing={d} guest_memory_rejected={d}\n",
            .{
                self.considered,
                self.forwarded,
                self.guest_open_count,
                self.guest_close_count,
                self.guest_lookup_count,
                self.guest_thunk_calls,
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

    fn guestLibrary(self: *Forwarder, token: u64) ?*anyopaque {
        for (&self.guest_libraries) |*entry| {
            if (entry.token == token) return entry.handle;
        }
        return null;
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
            .guest_memory_copy => blk: {
                const length: usize = @intCast(state.regs.rdx);
                if (length != 0) {
                    const destination = state.guestMemory(state.regs.rdi, state.regs.rdx) orelse return null;
                    const source = state.guestMemoryConst(state.regs.rsi, state.regs.rdx) orelse return null;
                    std.mem.copyForwards(u8, destination[0..length], source[0..length]);
                }
                break :blk .{ .handled = state.regs.rdi };
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

const TestState = struct {
    mem: [32]u8 = [_]u8{0} ** 32,
    regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0 } = .{},

    pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }

    fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }
};

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

test "forwarder copies guest memory for memcpy" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    var state = TestState{};
    @memcpy(state.mem[8..12], "----");
    @memcpy(state.mem[16..20], "copy");
    state.regs.rdi = 8;
    state.regs.rsi = 16;
    state.regs.rdx = 4;

    const outcome = forwarder.forward(&state, "/usr/lib/libSystem.B.dylib", "_memcpy") orelse return error.SymbolUnavailable;
    try std.testing.expectEqual(@as(u64, 8), outcome.handled);
    try std.testing.expectEqualStrings("copy", state.mem[8..12]);
    try std.testing.expectEqual(@as(u64, 1), forwarder.forwarded);
}

test "guest dynamic-library handles are opaque and close exactly once" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    const token = forwarder.openGuest("/usr/lib/libSystem.B.dylib", RTLD_LAZY | RTLD_LOCAL);
    try std.testing.expect(token >= GUEST_LIBRARY_HANDLE_BASE);
    try std.testing.expectEqual(@as(u64, 1), forwarder.guest_open_count);
    const symbol = forwarder.lookupGuest(token, "getpid");
    try std.testing.expect(symbol >= GUEST_SYMBOL_THUNK_BASE);
    try std.testing.expectEqual(@as(u64, 1), forwarder.guest_lookup_count);
    try std.testing.expectEqual(@as(c_int, 0), forwarder.closeGuest(token));
    try std.testing.expectEqual(@as(u64, 1), forwarder.guest_close_count);
    try std.testing.expectEqual(@as(c_int, -1), forwarder.closeGuest(token));
    try std.testing.expectEqual(@as(u64, 0), forwarder.lookupGuest(token, "getpid"));
}
