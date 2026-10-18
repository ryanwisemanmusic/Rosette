//! Folder-owned build registration. Paths use the master build root.
const std = @import("std");
const builtin = @import("builtin");

pub fn register0(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const target = ctx.target;
    const xenia_texture_format_contract_mod = ctx.xenia_texture_format_contract_mod;

    const Subsystem = struct {
        root: []const u8,
        contract_name: []const u8,
        contract_root: []const u8,
        needs_texture_format_contract: bool = false,
    };
    const subsystems = [_]Subsystem{
        .{
            .root = "lib/audio/root.zig",
            .contract_name = "xenia_audio_contract",
            .contract_root = "pkg/common/console/audio-contract/src/root.zig",
        },
        .{
            .root = "lib/hid/root.zig",
            .contract_name = "xenia_input_contract",
            .contract_root = "pkg/common/console/input-contract/src/root.zig",
        },
        .{
            .root = "lib/gpu/shader/root.zig",
            .contract_name = "xenia_shader_contract",
            .contract_root = "pkg/common/console/shader-contract/src/root.zig",
        },
        .{
            .root = "lib/gpu/render_target/root.zig",
            .contract_name = "xenia_render_target_contract",
            .contract_root = "pkg/common/console/render-target-contract/src/root.zig",
        },
        .{
            .root = "lib/gpu/texture_cache/root.zig",
            .contract_name = "xenia_texture_contract",
            .contract_root = "pkg/common/console/texture-contract/src/root.zig",
            .needs_texture_format_contract = true,
        },
    };
    inline for (subsystems) |subsystem| {
        const subsystem_mod = b.createModule(.{
            .root_source_file = b.path(subsystem.root),
            .target = target,
            .optimize = optimize,
        });
        subsystem_mod.addImport(subsystem.contract_name, b.createModule(.{
            .root_source_file = b.path(subsystem.contract_root),
            .target = target,
            .optimize = optimize,
        }));
        if (subsystem.needs_texture_format_contract) {
            // format_convert consumes the signed packed-format contract in
            // addition to the cache's existing tiling/format contract.
            // Keep both imports on the standalone subsystem test; the
            // aggregate GPU module already receives this import below.
            subsystem_mod.addImport("xenia_texture_format_contract", xenia_texture_format_contract_mod);
        }
        const subsystem_test = b.addTest(.{ .root_module = subsystem_mod });
        check_step.dependOn(&b.addRunArtifact(subsystem_test).step);
    }

    // Config needs both its schema and the existing TOML parser.
    const config_mod = b.createModule(.{
        .root_source_file = b.path("lib/config/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    config_mod.addImport("xenia_config_schema", b.createModule(.{
        .root_source_file = b.path("pkg/common/console/config-schema/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    config_mod.addImport("toml_processor", b.createModule(.{
        .root_source_file = b.path("lib/processor/TOML_processor/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const config_test = b.addTest(.{ .root_module = config_mod });
    check_step.dependOn(&b.addRunArtifact(config_test).step);
}

pub fn register1(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const target = ctx.target;

    const toml_processor_mod = b.createModule(.{
        .root_source_file = b.path("lib/processor/TOML_processor/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const toml_processor_test = b.addTest(.{ .root_module = toml_processor_mod });
    check_step.dependOn(&b.addRunArtifact(toml_processor_test).step);

    const toml_exe_mod = b.createModule(.{
        .root_source_file = b.path("lib/processor/TOML_processor/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    toml_exe_mod.addImport("root.zig", toml_processor_mod);
    const toml_exe = b.addExecutable(.{
        .name = "toml_processor",
        .root_module = toml_exe_mod,
    });
    b.installArtifact(toml_exe);
}

pub fn register2(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const target = ctx.target;

    const ps1_processor_mod = b.createModule(.{
        .root_source_file = b.path("lib/processor/ps1_processor/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ps1_processor_test = b.addTest(.{ .root_module = ps1_processor_mod });
    check_step.dependOn(&b.addRunArtifact(ps1_processor_test).step);

    const ps1_exe_mod = b.createModule(.{
        .root_source_file = b.path("lib/processor/ps1_processor/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    ps1_exe_mod.addImport("root.zig", ps1_processor_mod);
    const ps1_exe = b.addExecutable(.{
        .name = "ps1_processor",
        .root_module = ps1_exe_mod,
    });
    b.installArtifact(ps1_exe);
}
