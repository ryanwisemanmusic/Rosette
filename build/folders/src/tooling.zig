//! Folder-owned build registration. Paths use the master build root.
const std = @import("std");
const builtin = @import("builtin");

pub fn register0(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const target = ctx.target;

    const transpiler_mod = b.createModule(.{
        .root_source_file = b.path("../lib/transpiler/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const transpiler_test = b.addTest(.{ .root_module = transpiler_mod });
    check_step.dependOn(&b.addRunArtifact(transpiler_test).step);

    const transpiler_cli_mod = b.createModule(.{
        .root_source_file = b.path("../lib/transpiler/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const transpiler_cli = b.addExecutable(.{
        .name = "rosette-c-fix",
        .root_module = transpiler_cli_mod,
    });
    const install_transpiler_cli = b.addInstallArtifact(transpiler_cli, .{});
    b.getInstallStep().dependOn(&install_transpiler_cli.step);
    const c_fix_step = b.step("c-fix", "Build and install only the C source transpiler");
    c_fix_step.dependOn(&install_transpiler_cli.step);
}
