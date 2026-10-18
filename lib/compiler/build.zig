//! Folder-owned build registration. Paths use the master build root.
const std = @import("std");
const builtin = @import("builtin");

pub fn register0(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const fasm_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/FASM/Zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    fasm_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const fasm_test = b.addTest(.{ .root_module = fasm_mod });
    check_step.dependOn(&fasm_test.step);
}

pub fn register1(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const nasm_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/NASM/Zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    nasm_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const nasm_test = b.addTest(.{ .root_module = nasm_mod });
    check_step.dependOn(&nasm_test.step);
}

pub fn register2(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const yasm_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/YASM/Zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    yasm_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const yasm_test = b.addTest(.{ .root_module = yasm_mod });
    check_step.dependOn(&b.addRunArtifact(yasm_test).step);
}

pub fn register3(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const jwasm_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/JWASM/Zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    jwasm_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const jwasm_test = b.addTest(.{ .root_module = jwasm_mod });
    check_step.dependOn(&jwasm_test.step);
}

pub fn register4(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const fasm_handshake_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/FASM/Zig/abi_handshake.zig"),
        .target = target,
        .optimize = optimize,
    });
    fasm_handshake_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const fasm_handshake_test = b.addTest(.{ .root_module = fasm_handshake_mod });
    check_step.dependOn(&fasm_handshake_test.step);
}

pub fn register5(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const nasm_handshake_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/NASM/Zig/abi_handshake.zig"),
        .target = target,
        .optimize = optimize,
    });
    nasm_handshake_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const nasm_handshake_test = b.addTest(.{ .root_module = nasm_handshake_mod });
    check_step.dependOn(&nasm_handshake_test.step);
}

pub fn register6(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const yasm_handshake_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/YASM/Zig/abi_handshake.zig"),
        .target = target,
        .optimize = optimize,
    });
    yasm_handshake_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const yasm_handshake_test = b.addTest(.{ .root_module = yasm_handshake_mod });
    check_step.dependOn(&yasm_handshake_test.step);
}

pub fn register7(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const jwasm_handshake_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/JWASM/Zig/abi_handshake.zig"),
        .target = target,
        .optimize = optimize,
    });
    jwasm_handshake_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const jwasm_handshake_test = b.addTest(.{ .root_module = jwasm_handshake_mod });
    check_step.dependOn(&jwasm_handshake_test.step);
}

pub fn register8(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const assembler_abi_suite_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/abi_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    assembler_abi_suite_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const assembler_abi_suite_test = b.addTest(.{ .root_module = assembler_abi_suite_mod });
    const assembler_abi_suite_run = b.addRunArtifact(assembler_abi_suite_test);
    check_step.dependOn(&assembler_abi_suite_run.step);
}

pub fn register9(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const target = ctx.target;

    const lib866d_mod = b.createModule(.{
        .root_source_file = b.path("src/DOS/Real_Mode/lib866d/Zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib866d_test = b.addTest(.{ .root_module = lib866d_mod });
    check_step.dependOn(&b.addRunArtifact(lib866d_test).step);
}

pub fn register10(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const entrypoint_kernel_process_guard_module = ctx.entrypoint_kernel_process_guard_module;
    const exit_diagnostics_module = ctx.exit_diagnostics_module;
    const optimize = ctx.optimize;
    const target = ctx.target;

    const compat_router_mod = b.createModule(.{
        .root_source_file = b.path("src/compat/rosetta2/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    compat_router_mod.addImport("entrypoint_kernel_process_guard", entrypoint_kernel_process_guard_module);
    compat_router_mod.addImport("exit_diagnostics", exit_diagnostics_module);
    const compat_router = b.addExecutable(.{
        .name = "rosette-router",
        .root_module = compat_router_mod,
    });
    b.installArtifact(compat_router);

    const compat_router_test_mod = b.createModule(.{
        .root_source_file = b.path("src/compat/rosetta2/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    compat_router_test_mod.addImport("entrypoint_kernel_process_guard", entrypoint_kernel_process_guard_module);
    compat_router_test_mod.addImport("exit_diagnostics", exit_diagnostics_module);
    const compat_router_test = b.addTest(.{ .root_module = compat_router_test_mod });
    check_step.dependOn(&b.addRunArtifact(compat_router_test).step);
}

pub fn register11(b: *std.Build, ctx: anytype) void {
    const dll_unpacker_module = ctx.dll_unpacker_module;

    const dll_unpacker = b.addExecutable(.{
        .name = "rosette_dll_unpacker",
        .root_module = dll_unpacker_module,
    });
    b.installArtifact(dll_unpacker);
}

pub fn register12(b: *std.Build, ctx: anytype) void {
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const assembler_runner_mod = b.createModule(.{
        .root_source_file = b.path("src/Assemblers/runner.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    assembler_runner_mod.addImport("runtime_abi_handshake", runtime_abi_module);

    const assembler_runner = b.addExecutable(.{
        .name = "rosette_assembler_runner",
        .root_module = assembler_runner_mod,
    });
    b.installArtifact(assembler_runner);
}
