const std = @import("std");

/// Stub LLVM bitcode parser for platforms where the real LLVM parser
/// is unavailable or incompatible (e.g., macOS ARM64 with modern LLVM).
///
/// Provides the same interface as the upstream `LLVMBitcodeParser`
/// class used by Xenia / DXBC, but all parse methods return an error
/// indicating bitcode parsing is not available in compat mode.
///
/// This eliminates the need for `llvm_bitcode_parser_stub.cpp` — any
/// project using Rosette can import this module instead of compiling
/// the C++ stub, and any C/C++ code can use the extern C bridge below.
pub const Error = error{
    BitcodeParsingDisabled,
};

pub const Parser = struct {
    context: ?*anyopaque,
    module: ?*anyopaque,

    pub fn init() Parser {
        return .{ .context = null, .module = null };
    }

    pub fn deinit(_: *Parser) void {}

    pub fn parseImpl(_: *Parser, _: []const u8) Error!void {
        return error.BitcodeParsingDisabled;
    }

    pub fn parse(_: *Parser, _: []const u8) Error!void {
        return error.BitcodeParsingDisabled;
    }

    pub fn getModule(self: *const Parser) ?*anyopaque {
        return self.module;
    }

    pub fn getContext(self: *const Parser) ?*anyopaque {
        return self.context;
    }
};

/// C ABI bridge so that C/C++ translation units can call into the Zig
/// stub without recompiling.  Link these symbols instead of the original
/// C++ bitcode parser.
pub export fn rosette_bitcode_parser_create() ?*Parser {
    const allocator = std.heap.c_allocator;
    const parser = allocator.create(Parser) catch return null;
    parser.* = Parser.init();
    return parser;
}

pub export fn rosette_bitcode_parser_destroy(parser: ?*Parser) void {
    if (parser) |p| {
        p.deinit();
        std.heap.c_allocator.destroy(p);
    }
}

pub export fn rosette_bitcode_parser_parse(parser: ?*Parser, data: [*]const u8, len: usize) bool {
    const p = parser orelse return false;
    const slice = data[0..len];
    p.parse(slice) catch return false;
    return true;
}

pub export fn rosette_bitcode_parser_get_module(parser: ?*const Parser) ?*anyopaque {
    return if (parser) |p| p.getModule() else null;
}

pub export fn rosette_bitcode_parser_get_context(parser: ?*const Parser) ?*anyopaque {
    return if (parser) |p| p.getContext() else null;
}

test "stub parser construction and destruction" {
    var p = Parser.init();
    defer p.deinit();
    try std.testing.expect(p.getModule() == null);
    try std.testing.expect(p.getContext() == null);
}

test "stub parse always fails" {
    var p = Parser.init();
    defer p.deinit();
    try std.testing.expectError(error.BitcodeParsingDisabled, p.parseImpl("test data"));
    try std.testing.expectError(error.BitcodeParsingDisabled, p.parse("test data"));
}

test "C ABI bridge round-trips through null" {
    const p = rosette_bitcode_parser_create();
    try std.testing.expect(p != null);
    defer rosette_bitcode_parser_destroy(p);
    try std.testing.expect(rosette_bitcode_parser_get_module(p) == null);
    try std.testing.expect(rosette_bitcode_parser_get_context(p) == null);
}
