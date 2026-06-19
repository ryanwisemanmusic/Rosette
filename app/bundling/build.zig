const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bundle_step = b.step("bundle", "Build Rosette.app bundle");
    const check_step = b.step("check", "Check Rosette app sources");

    const app_name = "Rosette";

    // Zig helper for command-line work from the Cocoa app.
    const helper_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    helper_mod.addIncludePath(b.path("../../include"));
    helper_mod.addCSourceFile(.{
        .file = b.path("../../src/graphics/common/debug_runtime.c"),
        .flags = &.{"-std=c11"},
    });
    helper_mod.addCSourceFile(.{
        .file = b.path("../../src/graphics/CLI/window_main.c"),
        .flags = &.{"-std=c11"},
    });
    const app_bundle_parser_mod = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/app_parser/bundle_parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_macho_parser_mod = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/app_parser/macho_parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    helper_mod.addImport("app_bundle_parser", app_bundle_parser_mod);
    helper_mod.addImport("app_macho_parser", app_macho_parser_mod);

    const exe_runner_mod = b.createModule(.{
        .root_source_file = b.path("../../rosette_exe_runner.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const exe_runner_cli_mod = b.createModule(.{
        .root_source_file = b.path("../../exe_runner_bridge.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const abort_trap_taxonomy_module = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/abort_trap_taxonomy/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_code_text_segment_module = b.createModule(.{
        .root_source_file = b.path("../../src/entrypoint/code-text-segment/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_kernel_process_guard_module = b.createModule(.{
        .root_source_file = b.path("../../src/entrypoint/kernel/process_guard.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const runtime_abi_module = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/runtime-abi-handshake/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const isa_module = b.createModule(.{
        .root_source_file = b.path("../../ISA/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_model_module = b.createModule(.{
        .root_source_file = b.path("../../src/bridge/register-tracing/model.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_register_trace_module = b.createModule(.{
        .root_source_file = b.path("../../src/bridge/register-tracing/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_memory_module = b.createModule(.{
        .root_source_file = b.path("../../src/bridge/memory/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_stack_module = b.createModule(.{
        .root_source_file = b.path("../../src/bridge/stack/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_heap_module = b.createModule(.{
        .root_source_file = b.path("../../src/bridge/heap/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_instruction_decoding_module = b.createModule(.{
        .root_source_file = b.path("../../src/bridge/instruction-decoding/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_flags_module = b.createModule(.{
        .root_source_file = b.path("../../src/bridge/flag-handling/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_string_ops_module = b.createModule(.{
        .root_source_file = b.path("../../src/bridge/string-ops/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_exceptions_module = b.createModule(.{
        .root_source_file = b.path("../../src/bridge/exceptions/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });

    runtime_abi_module.addImport("abort_trap_taxonomy", abort_trap_taxonomy_module);
    runtime_abi_module.addImport("entrypoint_code_text_segment", entrypoint_code_text_segment_module);

    isa_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_register_trace_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_register_trace_module.addImport("bridge_model", bridge_model_module);
    bridge_memory_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_memory_module.addImport("bridge_model", bridge_model_module);
    bridge_stack_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_stack_module.addImport("bridge_model", bridge_model_module);
    bridge_heap_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_heap_module.addImport("bridge_model", bridge_model_module);
    bridge_instruction_decoding_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_instruction_decoding_module.addImport("bridge_model", bridge_model_module);
    bridge_flags_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_flags_module.addImport("bridge_model", bridge_model_module);
    bridge_string_ops_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_string_ops_module.addImport("bridge_model", bridge_model_module);
    bridge_exceptions_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_exceptions_module.addImport("bridge_model", bridge_model_module);

    exe_runner_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    exe_runner_mod.addImport("abort_trap_taxonomy", abort_trap_taxonomy_module);
    exe_runner_mod.addImport("entrypoint_code_text_segment", entrypoint_code_text_segment_module);
    exe_runner_mod.addImport("entrypoint_kernel_process_guard", entrypoint_kernel_process_guard_module);
    exe_runner_mod.addImport("isa_registry", isa_module);
    exe_runner_mod.addImport("bridge_register_tracing", bridge_register_trace_module);
    exe_runner_mod.addImport("bridge_memory", bridge_memory_module);
    exe_runner_mod.addImport("bridge_stack", bridge_stack_module);
    exe_runner_mod.addImport("bridge_heap", bridge_heap_module);
    exe_runner_mod.addImport("bridge_instruction_decoding", bridge_instruction_decoding_module);
    exe_runner_mod.addImport("bridge_flags", bridge_flags_module);
    exe_runner_mod.addImport("bridge_string_ops", bridge_string_ops_module);
    exe_runner_mod.addImport("bridge_exceptions", bridge_exceptions_module);
    exe_runner_cli_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    exe_runner_cli_mod.addImport("abort_trap_taxonomy", abort_trap_taxonomy_module);
    exe_runner_cli_mod.addImport("entrypoint_code_text_segment", entrypoint_code_text_segment_module);
    exe_runner_cli_mod.addImport("entrypoint_kernel_process_guard", entrypoint_kernel_process_guard_module);
    exe_runner_cli_mod.addImport("isa_registry", isa_module);
    exe_runner_cli_mod.addImport("bridge_register_tracing", bridge_register_trace_module);
    exe_runner_cli_mod.addImport("bridge_memory", bridge_memory_module);
    exe_runner_cli_mod.addImport("bridge_stack", bridge_stack_module);
    exe_runner_cli_mod.addImport("bridge_heap", bridge_heap_module);
    exe_runner_cli_mod.addImport("bridge_instruction_decoding", bridge_instruction_decoding_module);
    exe_runner_cli_mod.addImport("bridge_flags", bridge_flags_module);
    exe_runner_cli_mod.addImport("bridge_string_ops", bridge_string_ops_module);
    exe_runner_cli_mod.addImport("bridge_exceptions", bridge_exceptions_module);
    helper_mod.addImport("exe_runner", exe_runner_cli_mod);

    const helper = b.addExecutable(.{
        .name = "rosette-cli",
        .root_module = helper_mod,
    });
    b.installArtifact(helper);

    const shell_helper_mod = b.createModule(.{
        .root_source_file = b.path("../../src/shell/global_config/rosette_shell.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const shell_helper = b.addExecutable(.{
        .name = "rosette-shell",
        .root_module = shell_helper_mod,
    });
    shell_helper_mod.addImport("entrypoint_kernel_process_guard", entrypoint_kernel_process_guard_module);
    b.installArtifact(shell_helper);

    const assembler_runner_mod = b.createModule(.{
        .root_source_file = b.path("../../src/Assemblers/runner.zig"),
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

    const compat_router_mod = b.createModule(.{
        .root_source_file = b.path("../../src/compat/rosetta2/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const compat_router = b.addExecutable(.{
        .name = "rosette-router",
        .root_module = compat_router_mod,
    });
    compat_router_mod.addImport("entrypoint_kernel_process_guard", entrypoint_kernel_process_guard_module);
    b.installArtifact(compat_router);

    const macho_processor_mod = b.createModule(.{
        .root_source_file = b.path("../../lib/Mach-O/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const macho_processor = b.addExecutable(.{
        .name = "macho_processor",
        .root_module = macho_processor_mod,
    });
    b.installArtifact(macho_processor);

    // Add WinForms native Cocoa bridge to the exe runner module
    // Temporarily disabled to debug hang
    // exe_runner_mod.addCSourceFile(.{
    //     .file = b.path("../../include/winforms/winforms_native.m"),
    //     .flags = &.{ "-fobjc-arc", "-Wall", "-Wextra" },
    // });
    // exe_runner_mod.linkFramework("Cocoa", .{});
    // exe_runner_mod.linkFramework("Foundation", .{});

    const standalone_runner = b.addExecutable(.{
        .name = "rosette_exe_runner",
        .root_module = exe_runner_mod,
    });
    const standalone_runner_install = b.addInstallFileWithDir(
        standalone_runner.getEmittedBin(),
        .bin,
        "rosette_exe_runner",
    );
    standalone_runner_install.step.dependOn(&standalone_runner.step);
    const exe_runner_step = b.step("exe-runner", "Build standalone Rosette EXE runner");
    exe_runner_step.dependOn(&standalone_runner_install.step);

    {
        const helper_test = b.addTest(.{ .root_module = helper_mod });
        check_step.dependOn(&helper_test.step);
    }

    // Native Cocoa shell launched by Finder.
    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    app_mod.addCSourceFile(.{
        .file = b.path("src/RosetteApp.m"),
        .flags = &.{ "-fobjc-arc", "-Wall", "-Wextra" },
    });
    app_mod.linkFramework("Cocoa", .{});

    const app_exe = b.addExecutable(.{
        .name = "rosette",
        .root_module = app_mod,
    });
    b.installArtifact(app_exe);

    // Info.plist
    const plist_install = b.addInstallFile(
        b.path("Info.plist"),
        b.fmt("{s}.app/Contents/Info.plist", .{app_name}),
    );
    bundle_step.dependOn(&plist_install.step);

    const icon_install = b.addInstallFile(
        b.path("app_image/rosette_app_icon.icns"),
        b.fmt("{s}.app/Contents/Resources/rosette_app_icon.icns", .{app_name}),
    );
    bundle_step.dependOn(&icon_install.step);

    // Binary inside the bundle
    const bin_install = b.addInstallFileWithDir(
        app_exe.getEmittedBin(),
        .{ .custom = b.fmt("{s}.app/Contents/MacOS", .{app_name}) },
        "rosette",
    );
    bin_install.step.dependOn(&app_exe.step);
    bundle_step.dependOn(&bin_install.step);

    const helper_install = b.addInstallFileWithDir(
        helper.getEmittedBin(),
        .{ .custom = b.fmt("{s}.app/Contents/MacOS", .{app_name}) },
        "rosette-cli",
    );
    helper_install.step.dependOn(&helper.step);
    bundle_step.dependOn(&helper_install.step);

    const shell_helper_install = b.addInstallFileWithDir(
        shell_helper.getEmittedBin(),
        .{ .custom = b.fmt("{s}.app/Contents/MacOS", .{app_name}) },
        "rosette-shell",
    );
    shell_helper_install.step.dependOn(&shell_helper.step);
    bundle_step.dependOn(&shell_helper_install.step);

    const assembler_runner_install = b.addInstallFileWithDir(
        assembler_runner.getEmittedBin(),
        .{ .custom = b.fmt("{s}.app/Contents/MacOS", .{app_name}) },
        "rosette_assembler_runner",
    );
    assembler_runner_install.step.dependOn(&assembler_runner.step);
    bundle_step.dependOn(&assembler_runner_install.step);

    const compat_router_install = b.addInstallFileWithDir(
        compat_router.getEmittedBin(),
        .{ .custom = b.fmt("{s}.app/Contents/MacOS", .{app_name}) },
        "rosette-router",
    );
    compat_router_install.step.dependOn(&compat_router.step);
    bundle_step.dependOn(&compat_router_install.step);

    const macho_processor_install = b.addInstallFileWithDir(
        macho_processor.getEmittedBin(),
        .{ .custom = b.fmt("{s}.app/Contents/MacOS", .{app_name}) },
        "macho_processor",
    );
    macho_processor_install.step.dependOn(&macho_processor.step);
    bundle_step.dependOn(&macho_processor_install.step);

    const exe_runner_install = b.addInstallFileWithDir(
        standalone_runner.getEmittedBin(),
        .{ .custom = b.fmt("{s}.app/Contents/MacOS", .{app_name}) },
        "rosette_exe_runner",
    );
    exe_runner_install.step.dependOn(&standalone_runner.step);
    bundle_step.dependOn(&exe_runner_install.step);

    const runtime_resource_dir = b.fmt("{s}.app/Contents/Resources/rosette-runtime", .{app_name});
    const RuntimeDir = struct {
        source: []const u8,
        destination: []const u8,
    };
    const runtime_dirs = [_]RuntimeDir{
        .{ .source = "../../lib/Assemblers", .destination = "Assemblers" },
        .{ .source = "../../lib/processor/ELF_processor", .destination = "ELF_processor" },
        .{ .source = "../../ISA", .destination = "ISA" },
        .{ .source = "../../app_testing/basic_snake", .destination = "app_testing/basic_snake" },
        .{ .source = "../../app_testing/Console-Tetris", .destination = "app_testing/Console-Tetris" },
        .{ .source = "../../app_testing/minesweeper", .destination = "app_testing/minesweeper" },
        .{ .source = "../../app_testing/PACMAN-x86", .destination = "app_testing/PACMAN-x86" },
        .{ .source = "../../app_testing/Rocket-Shooting", .destination = "app_testing/Rocket-Shooting" },
        .{ .source = "../../app_testing/snax86_windowed", .destination = "app_testing/snax86_windowed" },
        .{ .source = "../../app_testing/snax86", .destination = "app_testing/snax86" },
        .{ .source = "../../app_testing/tetrisx86_win32_windowed", .destination = "app_testing/tetrisx86_win32_windowed" },
        .{ .source = "../../app_testing/tetrisx86_win32", .destination = "app_testing/tetrisx86_win32" },
        .{ .source = "../../app_testing/tetrisx86_windowed", .destination = "app_testing/tetrisx86_windowed" },
        .{ .source = "../../app_testing/tetrisx86", .destination = "app_testing/tetrisx86" },
        .{ .source = "../../assets", .destination = "assets" },
        .{ .source = "../../lib/processor/bat_processor", .destination = "bat_processor" },
        .{ .source = "../../include", .destination = "include" },
        .{ .source = "../../lib/processor/ps1_processor", .destination = "ps1_processor" },
        .{ .source = "../../scripts", .destination = "scripts" },
        .{ .source = "../../src", .destination = "src" },
        .{ .source = "../../test", .destination = "test" },
        .{ .source = "../../third_party", .destination = "third_party" },
        .{ .source = "../../tools", .destination = "tools" },
        .{ .source = "app_image", .destination = "app/bundling/app_image" },
        .{ .source = "src", .destination = "app/bundling/src" },
        .{ .source = "../dmg/installer/src", .destination = "app/dmg/installer/src" },
        .{ .source = "../dmg/uninstaller/src", .destination = "app/dmg/uninstaller/src" },
    };
    for (runtime_dirs) |dir| {
        const runtime_install = b.addInstallDirectory(.{
            .source_dir = b.path(dir.source),
            .install_dir = .prefix,
            .install_subdir = b.fmt("{s}/{s}", .{ runtime_resource_dir, dir.destination }),
        });
        bundle_step.dependOn(&runtime_install.step);
    }

    const RuntimeFile = struct {
        source: []const u8,
        destination: []const u8,
    };
    const runtime_files = [_]RuntimeFile{
        .{ .source = "../../GNUmakefile", .destination = "GNUmakefile" },
        .{ .source = "../../LICENSE", .destination = "LICENSE" },
        .{ .source = "../../README.md", .destination = "README.md" },
        .{ .source = "../../rosette_app_exe.zig", .destination = "rosette_app_exe.zig" },
        .{ .source = "../../rosette_exe_runner.zig", .destination = "rosette_exe_runner.zig" },
        .{ .source = "build.zig", .destination = "app/bundling/build.zig" },
        .{ .source = "Info.plist", .destination = "app/bundling/Info.plist" },
        .{ .source = "../dmg/installer/build.zig", .destination = "app/dmg/installer/build.zig" },
        .{ .source = "../dmg/installer/Info.plist", .destination = "app/dmg/installer/Info.plist" },
        .{ .source = "../dmg/uninstaller/build.zig", .destination = "app/dmg/uninstaller/build.zig" },
        .{ .source = "../dmg/uninstaller/Info.plist", .destination = "app/dmg/uninstaller/Info.plist" },
    };
    for (runtime_files) |file| {
        const runtime_file_install = b.addInstallFile(
            b.path(file.source),
            b.fmt("{s}/{s}", .{ runtime_resource_dir, file.destination }),
        );
        bundle_step.dependOn(&runtime_file_install.step);
    }

    const write_manifest = b.addWriteFiles();
    const manifest_file = write_manifest.add("bundle-manifest.txt",
        \\Rosette bundle manifest
        \\included directories:
        \\  Assemblers
        \\  ELF_processor
        \\  ISA
        \\  app_testing (excl. Text-Wrangler, xenia)
        \\  assets
        \\  bat_processor
        \\  include
        \\  ps1_processor
        \\  scripts
        \\  src
        \\  test
        \\  third_party
        \\  tools
        \\  app/bundling/app_image
        \\  app/bundling/src
        \\  app/dmg/installer/src
        \\  app/dmg/uninstaller/src
        \\included root files:
        \\  GNUmakefile
        \\  LICENSE
        \\  README.md
        \\  rosette_app_exe.zig
        \\  rosette_exe_runner.zig
        \\  src/compat/rosetta2
        \\  app_testing/basic_snake
        \\  app_testing/Console-Tetris
        \\  app_testing/minesweeper
        \\  app_testing/PACMAN-x86
        \\  app_testing/Rocket-Shooting
        \\  app_testing/snax86
        \\  app_testing/snax86_windowed
        \\  app_testing/tetrisx86
        \\  app_testing/tetrisx86_windowed
        \\  app_testing/tetrisx86_win32
        \\  app_testing/tetrisx86_win32_windowed
        \\permanent blacklist:
        \\  .rosette
        \\  app_testing/Text-Wrangler
        \\  app_testing/xenia
        \\  docs
        \\
    );
    const manifest_install = b.addInstallFile(
        manifest_file,
        b.fmt("{s}/bundle-manifest.txt", .{runtime_resource_dir}),
    );
    bundle_step.dependOn(&manifest_install.step);

    // PkgInfo (required by macOS for .app bundles)
    const pkg_info_content = "APPL????";
    const write_pkg_info = b.addWriteFiles();
    _ = write_pkg_info.add("PkgInfo", pkg_info_content);
    const pkg_info_install = b.addInstallFileWithDir(
        write_pkg_info.getDirectory(),
        .{ .custom = b.fmt("{s}.app/Contents", .{app_name}) },
        "PkgInfo",
    );
    bundle_step.dependOn(&pkg_info_install.step);
}
