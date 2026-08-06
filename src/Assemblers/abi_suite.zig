const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");

const jwasm_assembler = @import("JWASM/Zig/assembler.zig");
const jwasm_handshake_mod = @import("JWASM/Zig/abi_handshake.zig");
const fasm_assembler = @import("FASM/Zig/assembler.zig");
const fasm_handshake_mod = @import("FASM/Zig/abi_handshake.zig");
const nasm_assembler = @import("NASM/Zig/assembler.zig");
const nasm_handshake_mod = @import("NASM/Zig/abi_handshake.zig");
const yasm_assembler = @import("YASM/Zig/assembler.zig");
const yasm_output = @import("YASM/Zig/output.zig");
const yasm_handshake_mod = @import("YASM/Zig/abi_handshake.zig");

const log_path = "/tmp/rosette-assembler-abi-suite.log";

pub export fn rosette_debug_enabled() c_int {
    return 1;
}

pub export fn rosette_debug_log_path() [*:0]const u8 {
    return log_path;
}

pub export fn rosette_runtime_abi_fail_fast_enabled() c_int {
    return 0;
}

test "JWasm assembler strict ABI suite" {
    runtime_abi.common.acquire();
    defer runtime_abi.common.release();

    const alloc = std.testing.allocator;
    const bytes = try jwasm_assembler.assembleJWASM(".model small\n", alloc);
    defer alloc.free(bytes);

    var handshake = jwasm_handshake_mod.JwasmAbiHandshake.init(alloc);
    defer handshake.deinit();
    try handshake.onEvent(.assembly_start, .instruction_encoding, 0, "jwasm start");
    handshake.validateOutput(&[_]u8{0x90});
}

test "FASM assembler strict ABI suite" {
    runtime_abi.common.acquire();
    defer runtime_abi.common.release();

    const alloc = std.testing.allocator;
    const bytes = try fasm_assembler.assemble("format binary\nuse32\ndb 0x90\n", alloc);
    defer alloc.free(bytes);

    var handshake = fasm_handshake_mod.FasmAbiHandshake.init(alloc);
    defer handshake.deinit();
    try handshake.onEvent(.assembly_start, .instruction_encoding, 0, "fasm start");
    handshake.validateOutput(bytes);
}

test "NASM assembler strict ABI suite" {
    runtime_abi.common.acquire();
    defer runtime_abi.common.release();

    var nasm_state = nasm_assembler.Assembler.init(std.testing.allocator);
    defer nasm_state.deinit();
    try nasm_state.setBits(32);
    _ = try nasm_state.beginSection(".text", 16);
    try nasm_state.defineSymbol("entry", .normal, 0, 0, 4);

    var handshake = nasm_handshake_mod.NasmAbiHandshake.init(std.testing.allocator);
    defer handshake.deinit();
    try handshake.onEvent(.assembly_start, .instruction_encoding, 0, "nasm start");
    handshake.validateOutput(&[_]u8{0x90});
}

test "YASM assembler strict ABI suite" {
    runtime_abi.common.acquire();
    defer runtime_abi.common.release();

    const alloc = std.testing.allocator;
    var yasm_state = yasm_assembler.Assembler.init(alloc);
    defer yasm_state.deinit();
    const argv = [_][]const u8{ "-g", "dwarf2", "-f", "elf64", "ast01.asm", "-l", "ast01.lst" };
    try yasm_state.configureFromArgs(&argv);
    const summary = try yasm_state.analyzeSource(
        \\; Assignment #1
        \\section .text
        \\global _start
        \\_start:
        \\  mov rax, SYS_exit
        \\  syscall
    );
    const bytes = try yasm_output.emitPlaceholderObject(alloc, .elf64);
    defer alloc.free(bytes);

    var handshake = yasm_handshake_mod.YasmAbiHandshake.init(alloc);
    defer handshake.deinit();
    try handshake.onEvent(.assembly_start, .source_profile, 0, "yasm start");
    handshake.validateCommand(yasm_state.options);
    handshake.validateSourceProfile(summary.profile);
    handshake.validateArtifact(.elf64, bytes);
    try std.testing.expectEqual(@as(u32, 0), handshake.validator.error_count);
}

// The suite must not write to stderr. `zig build`'s runner prints a step's
// captured stderr "no matter the result", and that printer also emits the
// pre-armed `result_failed_command` string — which `Step.Run` sets before
// spawning and never clears on success. A passing run that writes one byte to
// stderr therefore reports `failed command: …/test --listen=-` while the build
// still succeeds. Assert the handshake state instead of announcing it.
test "Assembler ABI Validation checks all passed" {
    runtime_abi.common.acquire();
    defer runtime_abi.common.release();
    try std.testing.expectEqual(@as(usize, 0), runtime_abi.common.violationCount());
}
