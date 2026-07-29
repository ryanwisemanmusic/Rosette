const std = @import("std");
const builtin = @import("builtin");

/// Reference-only headers (upstream win32, thr, winsdk). Not part of the public API.
const reference_include = "../.rosette/include";

pub fn build(b: *std.Build) void {
    var target_query = b.standardTargetOptionsQueryOnly(.{});
    const host_os = target_query.os_tag orelse builtin.target.os.tag;
    const macos_sdk_root = b.graph.environ_map.get("SDKROOT") orelse
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
    if (host_os == .macos) {
        const deployment: std.SemanticVersion = .{ .major = 13, .minor = 0, .patch = 0 };
        target_query.os_tag = .macos;
        target_query.os_version_min = .{ .semver = deployment };
        target_query.os_version_max = .{ .semver = deployment };
        if (b.sysroot == null) {
            b.sysroot = macos_sdk_root;
        }
    }
    const target = b.resolveTargetQuery(target_query);
    const optimize = b.standardOptimizeOption(.{});

    const is_macos = target.result.os.tag == .macos;
    const root_header = if (is_macos)
        b.path("../include/shims/macos/win32/windows_base.h")
    else
        b.path("../include/shims/win32/win32/windows_base.h");

    const translate_windows_base = b.addTranslateC(.{
        .root_source_file = root_header,
        .target = target,
        .optimize = optimize,
    });
    if (is_macos) translate_windows_base.addIncludePath(b.path("../include/shims/macos"));
    translate_windows_base.addIncludePath(b.path("../include/shims/win32"));
    translate_windows_base.addIncludePath(b.path("../include"));

    const windows_base_module = b.addModule("windows_base", .{
        .root_source_file = translate_windows_base.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const translate_sysdefs = b.addTranslateC(.{
        .root_source_file = b.path("../include/win32/Zig/sys_defines_bridge.h"),
        .target = target,
        .optimize = optimize,
    });
    if (is_macos) translate_sysdefs.addIncludePath(b.path("../include/shims/macos"));
    translate_sysdefs.addIncludePath(b.path("../include/shims/win32"));
    translate_sysdefs.addIncludePath(b.path("../include"));
    translate_sysdefs.addIncludePath(b.path(reference_include));

    const sysdefs_module = b.addModule("win32_sysdefs", .{
        .root_source_file = translate_sysdefs.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const translate_win32 = b.addTranslateC(.{
        .root_source_file = b.path("../include/win32/Zig/win32_bridge.h"),
        .target = target,
        .optimize = optimize,
    });
    if (is_macos) translate_win32.addIncludePath(b.path("../include/shims/macos"));
    translate_win32.addIncludePath(b.path("../include/shims/win32"));
    translate_win32.addIncludePath(b.path("../include"));
    translate_win32.addIncludePath(b.path(reference_include));

    const win32_all_module = b.addModule("win32_all", .{
        .root_source_file = translate_win32.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const translate_behavior = b.addTranslateC(.{
        .root_source_file = b.path("../include/win32/Zig/behavior_bridge.h"),
        .target = target,
        .optimize = optimize,
    });
    if (is_macos) translate_behavior.addIncludePath(b.path("../include/shims/macos"));
    translate_behavior.addIncludePath(b.path("../include/shims/win32"));
    translate_behavior.addIncludePath(b.path("../include"));
    translate_behavior.addIncludePath(b.path(reference_include));

    const behavior_module = b.addModule("behavior_api", .{
        .root_source_file = translate_behavior.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const translate_mmsystem = b.addTranslateC(.{
        .root_source_file = b.path("../include/win32/Zig/mmsystem_bridge.h"),
        .target = target,
        .optimize = optimize,
    });
    if (is_macos) translate_mmsystem.addIncludePath(b.path("../include/shims/macos"));
    translate_mmsystem.addIncludePath(b.path("../include/shims/win32"));
    translate_mmsystem.addIncludePath(b.path("../include"));

    const mmsystem_module = b.addModule("win32_mmsystem", .{
        .root_source_file = translate_mmsystem.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const translate_shim_surface = b.addTranslateC(.{
        .root_source_file = b.path("../include/win32/Zig/shim_surface_bridge.h"),
        .target = target,
        .optimize = optimize,
    });
    if (is_macos) translate_shim_surface.addIncludePath(b.path("../include/shims/macos"));
    translate_shim_surface.addIncludePath(b.path("../include/shims/win32"));
    translate_shim_surface.addIncludePath(b.path("../include"));
    translate_shim_surface.addIncludePath(b.path(reference_include));

    const shim_surface_module = b.addModule("win32_shim_surface", .{
        .root_source_file = translate_shim_surface.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const zig_module = b.createModule(.{
        .root_source_file = b.path("../include/win32/Zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const win32_pending_module = b.createModule(.{
        .root_source_file = b.path("../include/win32/Zig/win32_pending_bridge.zig"),
        .target = target,
        .optimize = optimize,
    });
    win32_pending_module.addImport("windows_base", windows_base_module);

    const behavior_zig_module = b.createModule(.{
        .root_source_file = b.path("../include/win32/Zig/behavior.zig"),
        .target = target,
        .optimize = optimize,
    });
    behavior_zig_module.addImport("behavior_api", behavior_module);
    if (is_macos) behavior_zig_module.addIncludePath(b.path("../include/shims/macos"));
    behavior_zig_module.addIncludePath(b.path("../include/shims/win32"));
    behavior_zig_module.addIncludePath(b.path("../include"));

    const abort_trap_taxonomy_module = b.createModule(.{
        .root_source_file = b.path("../src/tooling/abort_trap_taxonomy/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_code_text_segment_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/code-text-segment/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_kernel_process_guard_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/kernel/process_guard.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const entrypoint_alignment_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/alignment/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exit_diagnostics_module = b.createModule(.{
        .root_source_file = b.path("../src/tooling/exit_diagnostics/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const x86_asm_module = b.createModule(.{
        .root_source_file = b.path("../src/x86-ASM/title_entries.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_text_grid_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/text-grid/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_pages_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/pages/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dyld_cache_tree_module = b.createModule(.{
        .root_source_file = b.path("../src/pseudo-kernel-space/dyld-cache-tree/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pseudo_kernel_cache_module = b.createModule(.{
        .root_source_file = b.path("../src/pseudo-kernel-space/cache/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pseudo_kernel_code_cache_table_module = b.createModule(.{
        .root_source_file = b.path("../src/pseudo-kernel-space/code-cache-table/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_data_init_common_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.data-initializer/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_bss_init_common_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.bss-initializer/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_data_init_x86_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.data-initializer/x86/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_data_init_neon_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.data-initializer/NEON/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_bss_init_x86_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.bss-initializer/x86/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_bss_init_neon_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.bss-initializer/NEON/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_bss_init_dos_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.bss-initializer/DOS/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_bss_init_x64_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.bss-initializer/x64/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_data_init_dos_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.data-initializer/DOS/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_data_init_x64_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/.data-initializer/x64/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_stack_placement_common_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_stack_placement_dos_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/DOS/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_stack_placement_neon_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/NEON/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_stack_placement_x86_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/x86/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_stack_placement_x64_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/x64/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_shadow_stack_common_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/shadow_stack_common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_shadow_stack_neon_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/NEON/shadow_stack.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_shadow_stack_x86_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/x86/shadow_stack.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_shadow_stack_x64_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/x64/shadow_stack.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_stack_alignment_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/alignment.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_shadow_stack_validation_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/shadow_stack_validation.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_stack_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/stack/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_array_preserve_common_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/array/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_array_preserve_dos_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/array/DOS/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_array_preserve_x86_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/array/x86/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_array_preserve_x64_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/array/x64/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_array_preserve_neon_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/array/NEON/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_array_preserve_root_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/array/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_map_preserve_common_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/map/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_map_preserve_dos_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/map/DOS/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_map_preserve_x86_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/map/x86/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_map_preserve_x64_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/map/x64/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_map_preserve_neon_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/map/NEON/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_map_preserve_root_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/map/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_module = b.createModule(.{
        .root_source_file = b.path("../src/entrypoint/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const runtime_abi_module = b.createModule(.{
        .root_source_file = b.path("../src/tooling/runtime-abi-handshake/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const isa_module = b.createModule(.{
        .root_source_file = b.path("../ISA/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const isa_highway_module = b.createModule(.{
        .root_source_file = b.path("../ISA/highway.zig"),
        .target = target,
        .optimize = optimize,
    });
    const svx_module = b.createModule(.{
        .root_source_file = b.path("../lib/SVX/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cleo_module = b.createModule(.{
        .root_source_file = b.path("../lib/CLEO/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    cleo_module.addImport("isa_highway", isa_highway_module);
    const contract_mod = b.createModule(.{
        .root_source_file = b.path("../lib/Contract/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const jit_mod = b.createModule(.{
        .root_source_file = b.path("../lib/compiler/JIT/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_register_trace_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/register-tracing/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_model_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/register-tracing/model.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_memory_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/memory/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_stack_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/stack/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_heap_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/heap/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_instruction_decoding_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/instruction-decoding/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_flags_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/flag-handling/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_string_ops_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/string-ops/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_exceptions_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/exceptions/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_dos_runtime_module = b.createModule(.{
        .root_source_file = b.path("../src/bridge/dos-runtime/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dll_translator_module = b.createModule(.{
        .root_source_file = b.path("../src/tooling/dll-translator/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dll_unpacker_module = b.createModule(.{
        .root_source_file = b.path("../src/tooling/dll-translator/unpack.zig"),
        .target = target,
        .optimize = optimize,
    });
    const arm64_exceptions_module = b.createModule(.{
        .root_source_file = b.path("../src/arm64/exceptions/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_abi_module.addImport("abort_trap_taxonomy", abort_trap_taxonomy_module);
    runtime_abi_module.addImport("entrypoint_code_text_segment", entrypoint_code_text_segment_module);
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
    bridge_dos_runtime_module.addImport("runtime_abi_handshake", runtime_abi_module);
    bridge_dos_runtime_module.addImport("bridge_model", bridge_model_module);
    arm64_exceptions_module.addImport("runtime_abi_handshake", runtime_abi_module);
    arm64_exceptions_module.addImport("bridge_exceptions", bridge_exceptions_module);
    dll_translator_module.addImport("runtime_abi_handshake", runtime_abi_module);
    dll_unpacker_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_data_init_common_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_bss_init_common_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_text_grid_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_pages_module.addImport("runtime_abi_handshake", runtime_abi_module);
    dyld_cache_tree_module.addImport("runtime_abi_handshake", runtime_abi_module);
    pseudo_kernel_cache_module.addImport("dyld_cache_tree", dyld_cache_tree_module);
    entrypoint_data_init_neon_module.addImport("entrypoint_data_init_common", entrypoint_data_init_common_module);
    entrypoint_bss_init_neon_module.addImport("entrypoint_bss_init_common", entrypoint_bss_init_common_module);
    entrypoint_data_init_x86_module.addImport("entrypoint_data_init_common", entrypoint_data_init_common_module);
    entrypoint_data_init_x86_module.addImport("entrypoint_data_init_neon", entrypoint_data_init_neon_module);
    entrypoint_bss_init_x86_module.addImport("entrypoint_bss_init_common", entrypoint_bss_init_common_module);
    entrypoint_bss_init_x86_module.addImport("entrypoint_bss_init_neon", entrypoint_bss_init_neon_module);
    entrypoint_bss_init_dos_module.addImport("entrypoint_bss_init_common", entrypoint_bss_init_common_module);
    entrypoint_bss_init_x64_module.addImport("entrypoint_bss_init_common", entrypoint_bss_init_common_module);
    entrypoint_data_init_dos_module.addImport("entrypoint_data_init_common", entrypoint_data_init_common_module);
    entrypoint_data_init_x64_module.addImport("entrypoint_data_init_common", entrypoint_data_init_common_module);
    entrypoint_stack_placement_common_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_stack_placement_dos_module.addImport("entrypoint_stack_placement_common", entrypoint_stack_placement_common_module);
    entrypoint_stack_placement_neon_module.addImport("entrypoint_stack_placement_common", entrypoint_stack_placement_common_module);
    entrypoint_stack_placement_x86_module.addImport("entrypoint_stack_placement_common", entrypoint_stack_placement_common_module);
    entrypoint_stack_placement_x86_module.addImport("entrypoint_stack_placement_neon", entrypoint_stack_placement_neon_module);
    entrypoint_stack_placement_x64_module.addImport("entrypoint_stack_placement_common", entrypoint_stack_placement_common_module);
    entrypoint_shadow_stack_common_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_shadow_stack_neon_module.addImport("entrypoint_shadow_stack_common", entrypoint_shadow_stack_common_module);
    entrypoint_shadow_stack_x86_module.addImport("entrypoint_shadow_stack_common", entrypoint_shadow_stack_common_module);
    entrypoint_shadow_stack_x86_module.addImport("entrypoint_shadow_stack_neon", entrypoint_shadow_stack_neon_module);
    entrypoint_shadow_stack_x64_module.addImport("entrypoint_shadow_stack_common", entrypoint_shadow_stack_common_module);
    entrypoint_shadow_stack_x64_module.addImport("entrypoint_shadow_stack_neon", entrypoint_shadow_stack_neon_module);
    entrypoint_stack_alignment_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_shadow_stack_validation_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_stack_module.addImport("entrypoint_stack_alignment", entrypoint_stack_alignment_module);
    entrypoint_stack_module.addImport("entrypoint_shadow_stack_validation", entrypoint_shadow_stack_validation_module);
    entrypoint_stack_module.addImport("entrypoint_stack_placement_common", entrypoint_stack_placement_common_module);
    entrypoint_stack_module.addImport("entrypoint_stack_placement_dos", entrypoint_stack_placement_dos_module);
    entrypoint_stack_module.addImport("entrypoint_stack_placement_x86", entrypoint_stack_placement_x86_module);
    entrypoint_stack_module.addImport("entrypoint_stack_placement_x64", entrypoint_stack_placement_x64_module);
    entrypoint_stack_module.addImport("entrypoint_stack_placement_neon", entrypoint_stack_placement_neon_module);
    entrypoint_stack_module.addImport("entrypoint_shadow_stack_common", entrypoint_shadow_stack_common_module);
    entrypoint_stack_module.addImport("entrypoint_shadow_stack_x86", entrypoint_shadow_stack_x86_module);
    entrypoint_stack_module.addImport("entrypoint_shadow_stack_x64", entrypoint_shadow_stack_x64_module);
    entrypoint_stack_module.addImport("entrypoint_shadow_stack_neon", entrypoint_shadow_stack_neon_module);
    entrypoint_array_preserve_common_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_array_preserve_dos_module.addImport("entrypoint_array_preserve_common", entrypoint_array_preserve_common_module);
    entrypoint_array_preserve_x86_module.addImport("entrypoint_array_preserve_common", entrypoint_array_preserve_common_module);
    entrypoint_array_preserve_x86_module.addImport("entrypoint_array_preserve_neon", entrypoint_array_preserve_neon_module);
    entrypoint_array_preserve_x64_module.addImport("entrypoint_array_preserve_common", entrypoint_array_preserve_common_module);
    entrypoint_array_preserve_neon_module.addImport("entrypoint_array_preserve_common", entrypoint_array_preserve_common_module);
    entrypoint_array_preserve_root_module.addImport("entrypoint_array_preserve_common", entrypoint_array_preserve_common_module);
    entrypoint_array_preserve_root_module.addImport("entrypoint_array_preserve_dos", entrypoint_array_preserve_dos_module);
    entrypoint_array_preserve_root_module.addImport("entrypoint_array_preserve_x86", entrypoint_array_preserve_x86_module);
    entrypoint_array_preserve_root_module.addImport("entrypoint_array_preserve_x64", entrypoint_array_preserve_x64_module);
    entrypoint_array_preserve_root_module.addImport("entrypoint_array_preserve_neon", entrypoint_array_preserve_neon_module);
    entrypoint_map_preserve_common_module.addImport("runtime_abi_handshake", runtime_abi_module);
    entrypoint_map_preserve_dos_module.addImport("entrypoint_map_preserve_common", entrypoint_map_preserve_common_module);
    entrypoint_map_preserve_x86_module.addImport("entrypoint_map_preserve_common", entrypoint_map_preserve_common_module);
    entrypoint_map_preserve_x86_module.addImport("entrypoint_map_preserve_neon", entrypoint_map_preserve_neon_module);
    entrypoint_map_preserve_x64_module.addImport("entrypoint_map_preserve_common", entrypoint_map_preserve_common_module);
    entrypoint_map_preserve_neon_module.addImport("entrypoint_map_preserve_common", entrypoint_map_preserve_common_module);
    entrypoint_map_preserve_root_module.addImport("entrypoint_map_preserve_common", entrypoint_map_preserve_common_module);
    entrypoint_map_preserve_root_module.addImport("entrypoint_map_preserve_dos", entrypoint_map_preserve_dos_module);
    entrypoint_map_preserve_root_module.addImport("entrypoint_map_preserve_x86", entrypoint_map_preserve_x86_module);
    entrypoint_map_preserve_root_module.addImport("entrypoint_map_preserve_x64", entrypoint_map_preserve_x64_module);
    entrypoint_map_preserve_root_module.addImport("entrypoint_map_preserve_neon", entrypoint_map_preserve_neon_module);
    entrypoint_module.addImport("entrypoint_bss_init_common", entrypoint_bss_init_common_module);
    entrypoint_module.addImport("entrypoint_bss_init_dos", entrypoint_bss_init_dos_module);
    entrypoint_module.addImport("entrypoint_bss_init_x86", entrypoint_bss_init_x86_module);
    entrypoint_module.addImport("entrypoint_bss_init_x64", entrypoint_bss_init_x64_module);
    entrypoint_module.addImport("entrypoint_bss_init_neon", entrypoint_bss_init_neon_module);
    entrypoint_module.addImport("entrypoint_data_init_common", entrypoint_data_init_common_module);
    entrypoint_module.addImport("entrypoint_data_init_dos", entrypoint_data_init_dos_module);
    entrypoint_module.addImport("entrypoint_data_init_x86", entrypoint_data_init_x86_module);
    entrypoint_module.addImport("entrypoint_data_init_x64", entrypoint_data_init_x64_module);
    entrypoint_module.addImport("entrypoint_data_init_neon", entrypoint_data_init_neon_module);
    entrypoint_module.addImport("entrypoint_array_preserve_root", entrypoint_array_preserve_root_module);
    entrypoint_module.addImport("entrypoint_map_preserve_root", entrypoint_map_preserve_root_module);
    entrypoint_module.addImport("entrypoint_code_text_segment", entrypoint_code_text_segment_module);
    entrypoint_module.addImport("entrypoint_text_grid", entrypoint_text_grid_module);
    entrypoint_module.addImport("entrypoint_pages", entrypoint_pages_module);
    entrypoint_module.addImport("entrypoint_stack", entrypoint_stack_module);
    zig_module.addImport("dll_translator", dll_translator_module);
    zig_module.addImport("runtime_abi_handshake", runtime_abi_module);
    zig_module.addImport("entrypoint_stack", entrypoint_stack_module);
    zig_module.addImport("entrypoint", entrypoint_module);
    isa_module.addImport("runtime_abi_handshake", runtime_abi_module);

    const dos_scene_module = b.createModule(.{
        .root_source_file = b.path("../src/DOS/graphics/scene.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dos_palette_module = b.createModule(.{
        .root_source_file = b.path("../src/DOS/graphics/palette.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dos_renderer_module = b.createModule(.{
        .root_source_file = b.path("../src/DOS/graphics/renderer.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dos_platform_module = b.createModule(.{
        .root_source_file = b.path("../src/DOS/platform.zig"),
        .target = target,
        .optimize = optimize,
    });

    x86_asm_module.addImport("dos_scene", dos_scene_module);
    x86_asm_module.addImport("dos_palette", dos_palette_module);
    x86_asm_module.addImport("dos_renderer", dos_renderer_module);
    x86_asm_module.addImport("dos_platform", dos_platform_module);
    x86_asm_module.addImport("runtime_abi_handshake", runtime_abi_module);
    x86_asm_module.addImport("abort_trap_taxonomy", abort_trap_taxonomy_module);
    x86_asm_module.addImport("isa_registry", isa_module);
    x86_asm_module.addImport("isa_highway", isa_highway_module);
    x86_asm_module.addImport("entrypoint_code_text_segment", entrypoint_code_text_segment_module);
    x86_asm_module.addImport("bridge_register_tracing", bridge_register_trace_module);
    x86_asm_module.addImport("bridge_memory", bridge_memory_module);
    x86_asm_module.addImport("bridge_stack", bridge_stack_module);
    x86_asm_module.addImport("bridge_heap", bridge_heap_module);
    x86_asm_module.addImport("bridge_instruction_decoding", bridge_instruction_decoding_module);
    x86_asm_module.addImport("bridge_flags", bridge_flags_module);
    x86_asm_module.addImport("bridge_string_ops", bridge_string_ops_module);
    x86_asm_module.addImport("bridge_exceptions", bridge_exceptions_module);
    x86_asm_module.addImport("bridge_dos_runtime", bridge_dos_runtime_module);
    x86_asm_module.addImport("entrypoint_data_init_x86", entrypoint_data_init_x86_module);
    x86_asm_module.addImport("entrypoint_bss_init_x86", entrypoint_bss_init_x86_module);
    x86_asm_module.addImport("entrypoint_text_grid", entrypoint_text_grid_module);
    x86_asm_module.addImport("entrypoint_stack_placement_x86", entrypoint_stack_placement_x86_module);
    x86_asm_module.addImport("entrypoint_shadow_stack_x86", entrypoint_shadow_stack_x86_module);
    x86_asm_module.addImport("entrypoint_stack", entrypoint_stack_module);
    x86_asm_module.addImport("entrypoint", entrypoint_module);
    x86_asm_module.addImport("cleo", cleo_module);
    dos_scene_module.addImport("runtime_abi_handshake", runtime_abi_module);
    dos_scene_module.addImport("entrypoint_text_grid", entrypoint_text_grid_module);

    if (is_macos) zig_module.addIncludePath(b.path("../include/shims/macos"));
    zig_module.addIncludePath(b.path("../include/shims/win32"));
    zig_module.addIncludePath(b.path("../include"));
    zig_module.addImport("windows_base", windows_base_module);
    zig_module.addImport("win32_sysdefs", sysdefs_module);
    zig_module.addImport("win32_all", win32_all_module);
    zig_module.addImport("win32_pending", win32_pending_module);
    zig_module.addImport("win32_mmsystem", mmsystem_module);
    zig_module.addImport("win32_shim_surface", shim_surface_module);
    zig_module.addImport("behavior_api", behavior_module);
    zig_module.addImport("behavior", behavior_zig_module);
    zig_module.addImport("x86_asm", x86_asm_module);
    zig_module.addImport("runtime_abi_handshake", runtime_abi_module);
    zig_module.addImport("svx", svx_module);
    zig_module.addImport("cleo", cleo_module);
    zig_module.addImport("contract", contract_mod);
    zig_module.addImport("dos_scene", dos_scene_module);
    zig_module.addImport("dos_palette", dos_palette_module);
    zig_module.addImport("dos_renderer", dos_renderer_module);
    zig_module.addImport("dos_platform", dos_platform_module);
    zig_module.addImport("pseudo_kernel_cache", pseudo_kernel_cache_module);

    const check_step = b.step("check", "Check Rosette Zig sources");
    const entrypoint_alignment_test = b.addTest(.{ .root_module = entrypoint_alignment_module });
    check_step.dependOn(&entrypoint_alignment_test.step);

    const zig_tests = b.addTest(.{
        .root_module = zig_module,
    });
    check_step.dependOn(&zig_tests.step);

    const third_party_test_files = [_][]const u8{
        "crypto/sha.zig",
        "crypto/des.zig",
        "crypto/rijndael.zig",
        "dxbc/dxbc_checksum.zig",
        "endianness/endianness.zig",
        "fxaa/fxaa.zig",
        "half/half.zig",
        "renderdoc/renderdoc.zig",
        "avx_to_neon/avx_to_neon.zig",
        "llvm/llvm.zig",
        "microprofile/microprofile.zig",
        "mspack/mspack.zig",
        "stb/stb.zig",
    };
    inline for (third_party_test_files) |rel_path| {
        const tp_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("../third_party/{s}", .{rel_path})),
            .target = target,
            .optimize = optimize,
        });
        if (is_macos) tp_mod.addIncludePath(b.path("../include/shims/macos"));
        tp_mod.addIncludePath(b.path("../include/shims/win32"));
        tp_mod.addIncludePath(b.path("../include"));
        const tp_test = b.addTest(.{ .root_module = tp_mod });
        check_step.dependOn(&tp_test.step);
    }

    // Graphics ABI validation tests
    {
        const gfx_abi_mod = b.createModule(.{
            .root_source_file = b.path("../src/x86-ASM/graphics/abi.zig"),
            .target = target,
            .optimize = optimize,
        });
        gfx_abi_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const gfx_abi_test = b.addTest(.{ .root_module = gfx_abi_mod });
        check_step.dependOn(&gfx_abi_test.step);
    }

    {
        const runtime_abi_test = b.addTest(.{ .root_module = runtime_abi_module });
        check_step.dependOn(&runtime_abi_test.step);
    }

    {
        const stack_alignment_test = b.addTest(.{ .root_module = entrypoint_stack_alignment_module });
        check_step.dependOn(&stack_alignment_test.step);
    }

    {
        const shadow_stack_validation_test = b.addTest(.{ .root_module = entrypoint_shadow_stack_validation_module });
        check_step.dependOn(&shadow_stack_validation_test.step);
    }

    {
        const isa_test = b.addTest(.{ .root_module = isa_module });
        check_step.dependOn(&isa_test.step);
    }

    {
        const svx_test = b.addTest(.{ .root_module = svx_module });
        check_step.dependOn(&svx_test.step);
    }

    {
        const cleo_test = b.addTest(.{ .root_module = cleo_module });
        check_step.dependOn(&cleo_test.step);
    }

    {
        const contract_test = b.addTest(.{ .root_module = contract_mod });
        check_step.dependOn(&contract_test.step);
    }

    {
        const jit_test = b.addTest(.{ .root_module = jit_mod });
        check_step.dependOn(&jit_test.step);
    }

    {
        const isa_math_test_mod = b.createModule(.{
            .root_source_file = b.path("../ISA/Math/test_root.zig"),
            .target = target,
            .optimize = optimize,
        });
        isa_math_test_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const isa_math_test = b.addTest(.{ .root_module = isa_math_test_mod });
        check_step.dependOn(&isa_math_test.step);
    }

    {
        const dos_exec_mod = b.createModule(.{
            .root_source_file = b.path("../src/DOS/runtime_root.zig"),
            .target = target,
            .optimize = optimize,
        });
        dos_exec_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        dos_exec_mod.addImport("bridge_register_tracing", bridge_register_trace_module);
        dos_exec_mod.addImport("bridge_memory", bridge_memory_module);
        dos_exec_mod.addImport("bridge_stack", bridge_stack_module);
        dos_exec_mod.addImport("bridge_heap", bridge_heap_module);
        dos_exec_mod.addImport("bridge_instruction_decoding", bridge_instruction_decoding_module);
        dos_exec_mod.addImport("bridge_flags", bridge_flags_module);
        dos_exec_mod.addImport("bridge_string_ops", bridge_string_ops_module);
        dos_exec_mod.addImport("bridge_exceptions", bridge_exceptions_module);
        dos_exec_mod.addImport("bridge_dos_runtime", bridge_dos_runtime_module);
        const dos_exec_test = b.addTest(.{ .root_module = dos_exec_mod });
        check_step.dependOn(&dos_exec_test.step);
    }

    {
        const x64_state_mod = b.createModule(.{
            .root_source_file = b.path("../src/x64-ASM/x64_state.zig"),
            .target = target,
            .optimize = optimize,
        });
        x64_state_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        x64_state_mod.addImport("bridge_register_tracing", bridge_register_trace_module);
        x64_state_mod.addImport("bridge_memory", bridge_memory_module);
        x64_state_mod.addImport("bridge_stack", bridge_stack_module);
        x64_state_mod.addImport("bridge_heap", bridge_heap_module);
        x64_state_mod.addImport("bridge_instruction_decoding", bridge_instruction_decoding_module);
        x64_state_mod.addImport("bridge_flags", bridge_flags_module);
        x64_state_mod.addImport("bridge_string_ops", bridge_string_ops_module);
        x64_state_mod.addImport("bridge_exceptions", bridge_exceptions_module);
        const x64_state_test = b.addTest(.{ .root_module = x64_state_mod });
        check_step.dependOn(&x64_state_test.step);
    }

    {
        const x64_addr_mod = b.createModule(.{
            .root_source_file = b.path("../src/x64-ASM/addressing64.zig"),
            .target = target,
            .optimize = optimize,
        });
        x64_addr_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        x64_addr_mod.addImport("bridge_register_tracing", bridge_register_trace_module);
        x64_addr_mod.addImport("bridge_memory", bridge_memory_module);
        x64_addr_mod.addImport("bridge_stack", bridge_stack_module);
        x64_addr_mod.addImport("bridge_heap", bridge_heap_module);
        x64_addr_mod.addImport("bridge_instruction_decoding", bridge_instruction_decoding_module);
        x64_addr_mod.addImport("bridge_flags", bridge_flags_module);
        x64_addr_mod.addImport("bridge_string_ops", bridge_string_ops_module);
        x64_addr_mod.addImport("bridge_exceptions", bridge_exceptions_module);
        const x64_addr_test = b.addTest(.{ .root_module = x64_addr_mod });
        check_step.dependOn(&x64_addr_test.step);
    }

    {
        const arm64_trace_mod = b.createModule(.{
            .root_source_file = b.path("../src/arm64/register-tracing/runtime.zig"),
            .target = target,
            .optimize = optimize,
        });
        arm64_trace_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        arm64_trace_mod.addImport("bridge_register_tracing", bridge_register_trace_module);
        arm64_trace_mod.addImport("bridge_memory", bridge_memory_module);
        arm64_trace_mod.addImport("bridge_stack", bridge_stack_module);
        arm64_trace_mod.addImport("bridge_heap", bridge_heap_module);
        arm64_trace_mod.addImport("bridge_instruction_decoding", bridge_instruction_decoding_module);
        arm64_trace_mod.addImport("bridge_flags", bridge_flags_module);
        arm64_trace_mod.addImport("bridge_string_ops", bridge_string_ops_module);
        arm64_trace_mod.addImport("bridge_exceptions", bridge_exceptions_module);
        arm64_trace_mod.addImport("arm64_exceptions", arm64_exceptions_module);
        const arm64_trace_test = b.addTest(.{ .root_module = arm64_trace_mod });
        check_step.dependOn(&arm64_trace_test.step);
    }

    // Standalone assembler Zig module tests
    {
        const fasm_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/FASM/Zig/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        fasm_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const fasm_test = b.addTest(.{ .root_module = fasm_mod });
        check_step.dependOn(&fasm_test.step);
    }

    {
        const nasm_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/NASM/Zig/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        nasm_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const nasm_test = b.addTest(.{ .root_module = nasm_mod });
        check_step.dependOn(&nasm_test.step);
    }

    {
        const yasm_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/YASM/Zig/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        yasm_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const yasm_test = b.addTest(.{ .root_module = yasm_mod });
        check_step.dependOn(&yasm_test.step);
    }

    {
        const jwasm_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/JWASM/Zig/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        jwasm_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const jwasm_test = b.addTest(.{ .root_module = jwasm_mod });
        check_step.dependOn(&jwasm_test.step);
    }

    // Assembler ABI handshake modules
    {
        const fasm_handshake_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/FASM/Zig/abi_handshake.zig"),
            .target = target,
            .optimize = optimize,
        });
        fasm_handshake_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const fasm_handshake_test = b.addTest(.{ .root_module = fasm_handshake_mod });
        check_step.dependOn(&fasm_handshake_test.step);
    }

    {
        const nasm_handshake_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/NASM/Zig/abi_handshake.zig"),
            .target = target,
            .optimize = optimize,
        });
        nasm_handshake_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const nasm_handshake_test = b.addTest(.{ .root_module = nasm_handshake_mod });
        check_step.dependOn(&nasm_handshake_test.step);
    }

    {
        const yasm_handshake_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/YASM/Zig/abi_handshake.zig"),
            .target = target,
            .optimize = optimize,
        });
        yasm_handshake_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const yasm_handshake_test = b.addTest(.{ .root_module = yasm_handshake_mod });
        check_step.dependOn(&yasm_handshake_test.step);
    }

    {
        const jwasm_handshake_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/JWASM/Zig/abi_handshake.zig"),
            .target = target,
            .optimize = optimize,
        });
        jwasm_handshake_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const jwasm_handshake_test = b.addTest(.{ .root_module = jwasm_handshake_mod });
        check_step.dependOn(&jwasm_handshake_test.step);
    }

    {
        const assembler_abi_suite_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/abi_suite.zig"),
            .target = target,
            .optimize = optimize,
        });
        assembler_abi_suite_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const assembler_abi_suite_test = b.addTest(.{ .root_module = assembler_abi_suite_mod });
        const assembler_abi_suite_run = b.addRunArtifact(assembler_abi_suite_test);
        check_step.dependOn(&assembler_abi_suite_run.step);
    }

    {
        const lib866d_mod = b.createModule(.{
            .root_source_file = b.path("../src/DOS/Real_Mode/lib866d/Zig/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const lib866d_test = b.addTest(.{ .root_module = lib866d_mod });
        check_step.dependOn(&lib866d_test.step);
    }

    {
        const compat_router_mod = b.createModule(.{
            .root_source_file = b.path("../src/compat/rosetta2/main.zig"),
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
            .root_source_file = b.path("../src/compat/rosetta2/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        compat_router_test_mod.addImport("entrypoint_kernel_process_guard", entrypoint_kernel_process_guard_module);
        compat_router_test_mod.addImport("exit_diagnostics", exit_diagnostics_module);
        const compat_router_test = b.addTest(.{ .root_module = compat_router_test_mod });
        check_step.dependOn(&compat_router_test.step);
    }

    {
        const dll_unpacker = b.addExecutable(.{
            .name = "rosette_dll_unpacker",
            .root_module = dll_unpacker_module,
        });
        b.installArtifact(dll_unpacker);
    }

    {
        const assembler_runner_mod = b.createModule(.{
            .root_source_file = b.path("../src/Assemblers/runner.zig"),
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

    // Shared x86-64 decoder/interpreter modules
    const x64_decoder_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/decoder.zig"),
        .target = target,
        .optimize = optimize,
    });
    x64_decoder_mod.addImport("isa_highway", isa_highway_module);
    x64_decoder_mod.addImport("isa_registry", isa_module);
    x64_decoder_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const x64_decoder_test_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/decoder_test_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    x64_decoder_test_mod.addImport("x64_decoder", x64_decoder_mod);
    const x64_decoder_test = b.addTest(.{ .root_module = x64_decoder_test_mod });
    const run_x64_decoder_test = b.addRunArtifact(x64_decoder_test);
    check_step.dependOn(&run_x64_decoder_test.step);
    const isa_highway_test = b.addTest(.{ .root_module = isa_highway_module });
    check_step.dependOn(&isa_highway_test.step);
    const x64_interpreter_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/interpreter.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Shared CLEO routing module (used by both ELF and Mach-O processors)
    const cleo_routing_mod = b.createModule(.{
        .root_source_file = b.path("../lib/CLEO/cleo_routing.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ELF processor (x86-64 ELF binary loader/emulator)
    {
        const x64_linux_runtime_mod = b.createModule(.{
            .root_source_file = b.path("../src/x64-ASM/linux_runtime.zig"),
            .target = target,
            .optimize = optimize,
        });
        const x64_syscalls_mod = b.createModule(.{
            .root_source_file = b.path("../src/x64-ASM/syscalls.zig"),
            .target = target,
            .optimize = optimize,
        });
        const x64_guest_abi_mod = b.createModule(.{
            .root_source_file = b.path("../src/x64-ASM/guest_abi.zig"),
            .target = target,
            .optimize = optimize,
        });
        x64_linux_runtime_mod.addImport("x64_syscalls", x64_syscalls_mod);
        const elf_processor_mod = b.createModule(.{
            .root_source_file = b.path("../lib/processor/ELF_processor/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        elf_processor_mod.addImport("x64_decoder", x64_decoder_mod);
        elf_processor_mod.addImport("x64_interpreter", x64_interpreter_mod);
        elf_processor_mod.addImport("x64_linux_runtime", x64_linux_runtime_mod);
        elf_processor_mod.addImport("x64_syscalls", x64_syscalls_mod);
        elf_processor_mod.addImport("x64_guest_abi", x64_guest_abi_mod);
        elf_processor_mod.addImport("exit_diagnostics", exit_diagnostics_module);
        elf_processor_mod.addImport("cleo_routing", cleo_routing_mod);
        const elf_processor = b.addExecutable(.{
            .name = "elf_processor",
            .root_module = elf_processor_mod,
        });
        b.installArtifact(elf_processor);

        const elf_processor_test_mod = b.createModule(.{
            .root_source_file = b.path("../lib/processor/ELF_processor/process.zig"),
            .target = target,
            .optimize = optimize,
        });
        elf_processor_test_mod.addImport("x64_decoder", x64_decoder_mod);
        elf_processor_test_mod.addImport("x64_interpreter", x64_interpreter_mod);
        elf_processor_test_mod.addImport("x64_linux_runtime", x64_linux_runtime_mod);
        elf_processor_test_mod.addImport("x64_syscalls", x64_syscalls_mod);
        elf_processor_test_mod.addImport("x64_guest_abi", x64_guest_abi_mod);
        elf_processor_test_mod.addImport("exit_diagnostics", exit_diagnostics_module);
        elf_processor_test_mod.addImport("cleo_routing", cleo_routing_mod);
        const elf_processor_test = b.addTest(.{ .root_module = elf_processor_test_mod });
        check_step.dependOn(&elf_processor_test.step);

        const x64_guest_abi_test = b.addTest(.{ .root_module = x64_guest_abi_mod });
        check_step.dependOn(&x64_guest_abi_test.step);
    }

    // TOML processor (patch file format parser)
    {
        const toml_processor_mod = b.createModule(.{
            .root_source_file = b.path("../lib/processor/TOML_processor/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const toml_processor_test = b.addTest(.{ .root_module = toml_processor_mod });
        check_step.dependOn(&toml_processor_test.step);

        const toml_exe_mod = b.createModule(.{
            .root_source_file = b.path("../lib/processor/TOML_processor/main.zig"),
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

    // Mach-O processor (x86_64 macOS binary loader/diagnostic backend)
    {
        const macho_compat_runtime_mod = b.createModule(.{
            .root_source_file = b.path("../lib/Mach-O/compat_runtime.zig"),
            .target = target,
            .optimize = optimize,
        });
        const macho_runtime_mod = b.createModule(.{
            .root_source_file = b.path("../src/x64-ASM/macho_runtime.zig"),
            .target = target,
            .optimize = optimize,
        });
        const primitive_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/primitive/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const vtable_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/vtable/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const guard_rollback_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/guard-rollback/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const dyld_mod = b.createModule(.{
            .root_source_file = b.path("../lib/linker/dyld/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        dyld_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        const scheduler_mod = b.createModule(.{
            .root_source_file = b.path("../lib/scheduler/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        dyld_mod.addImport("scheduler", scheduler_mod);
        const cxx_abi_mod = b.createModule(.{
            .root_source_file = b.path("../lib/abi/cxx-abi/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        cxx_abi_mod.addImport("dyld", dyld_mod);
        const init_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/init/root.zig"),
            .target = target,
            .optimize = optimize,
        });

        const event_log_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/event-log/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        dyld_mod.addImport("event_log", event_log_mod);
        const diagnostics_mod = b.createModule(.{
            .root_source_file = b.path("../lib/diagnostics/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        diagnostics_mod.addImport("event_log", event_log_mod);
        diagnostics_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        const memory_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/memory/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        memory_mod.addImport("dyld", dyld_mod);
        memory_mod.addImport("event_log", event_log_mod);
        const pthread_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/pthread/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        pthread_mod.addImport("scheduler", scheduler_mod);
        pthread_mod.addImport("event_log", event_log_mod);
        const guest_abi_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/guest-abi/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        guest_abi_mod.addImport("event_log", event_log_mod);

        const macho_core_mod = b.createModule(.{
            .root_source_file = b.path("../lib/Mach-O/shared_core.zig"),
            .target = target,
            .optimize = optimize,
        });
        macho_core_mod.addImport("x64_decoder", x64_decoder_mod);
        macho_core_mod.addImport("dyld", dyld_mod);
        macho_core_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        macho_core_mod.addImport("exit_diagnostics", exit_diagnostics_module);
        macho_core_mod.addImport("guest_abi", guest_abi_mod);
        const process_core_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/process-core/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        process_core_mod.addImport("macho_core", macho_core_mod);
        process_core_mod.addImport("x64_decoder", x64_decoder_mod);
        process_core_mod.addImport("dyld", dyld_mod);
        process_core_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        process_core_mod.addImport("exit_diagnostics", exit_diagnostics_module);
        process_core_mod.addImport("cxx_abi", cxx_abi_mod);
        process_core_mod.addImport("scheduler", scheduler_mod);
        process_core_mod.addImport("cleo_routing", cleo_routing_mod);
        process_core_mod.addImport("init", init_mod);
        process_core_mod.addImport("macho_runtime", macho_runtime_mod);
        process_core_mod.addImport("contract", contract_mod);
        process_core_mod.addImport("diagnostics", diagnostics_mod);
        process_core_mod.addImport("memory", memory_mod);
        process_core_mod.addImport("pthread", pthread_mod);
        process_core_mod.addImport("guest_abi", guest_abi_mod);
        process_core_mod.addImport("vtable", vtable_mod);
        const import_handler_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/import-handler/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        import_handler_mod.addImport("macho_core", macho_core_mod);
        import_handler_mod.addImport("x64_decoder", x64_decoder_mod);
        import_handler_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        import_handler_mod.addImport("contract", contract_mod);
        import_handler_mod.addImport("dyld", dyld_mod);
        import_handler_mod.addImport("exit_diagnostics", exit_diagnostics_module);
        import_handler_mod.addImport("guest_abi", guest_abi_mod);
        import_handler_mod.addImport("diagnostics", diagnostics_mod);
        import_handler_mod.addImport("scheduler", scheduler_mod);
        const macho_processor_mod = b.createModule(.{
            .root_source_file = b.path("../lib/Mach-O/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        macho_processor_mod.addImport("x64_decoder", x64_decoder_mod);
        macho_processor_mod.addImport("x64_interpreter", x64_interpreter_mod);
        macho_processor_mod.addImport("macho_runtime", macho_runtime_mod);
        macho_processor_mod.addImport("exit_diagnostics", exit_diagnostics_module);
        macho_processor_mod.addImport("contract", contract_mod);
        macho_processor_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        macho_processor_mod.addImport("primitive", primitive_mod);
        macho_processor_mod.addImport("vtable", vtable_mod);
        macho_processor_mod.addImport("guard_rollback", guard_rollback_mod);
        macho_processor_mod.addImport("dyld", dyld_mod);
        macho_processor_mod.addImport("cxx_abi", cxx_abi_mod);
        macho_processor_mod.addImport("init", init_mod);
        macho_processor_mod.addImport("cleo_routing", cleo_routing_mod);
        macho_processor_mod.addImport("scheduler", scheduler_mod);
        macho_processor_mod.addImport("jit", jit_mod);
        macho_processor_mod.addImport("macho_core", macho_core_mod);
        macho_processor_mod.addImport("process_core", process_core_mod);
        macho_processor_mod.addImport("import_handler", import_handler_mod);
        if (is_macos) {
            macho_processor_mod.addSystemFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{macos_sdk_root}) });
            macho_processor_mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{macos_sdk_root}) });
            macho_processor_mod.addCSourceFile(.{
                .file = b.path("../lib/Mach-O/native_window_bridge.m"),
                .flags = &.{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
            });
            macho_processor_mod.linkFramework("AppKit", .{});
            macho_processor_mod.linkFramework("QuartzCore", .{});
            macho_processor_mod.linkFramework("Metal", .{});
        }
        const macho_processor = b.addExecutable(.{
            .name = "macho_processor",
            .root_module = macho_processor_mod,
        });
        b.installArtifact(macho_processor);

        const macho_processor_test_mod = b.createModule(.{
            .root_source_file = b.path("../lib/Mach-O/process.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        macho_processor_test_mod.addImport("x64_decoder", x64_decoder_mod);
        macho_processor_test_mod.addImport("x64_interpreter", x64_interpreter_mod);
        macho_processor_test_mod.addImport("macho_runtime", macho_runtime_mod);
        macho_processor_test_mod.addImport("exit_diagnostics", exit_diagnostics_module);
        macho_processor_test_mod.addImport("contract", contract_mod);
        macho_processor_test_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        macho_processor_test_mod.addImport("primitive", primitive_mod);
        macho_processor_test_mod.addImport("vtable", vtable_mod);
        macho_processor_test_mod.addImport("guard_rollback", guard_rollback_mod);
        macho_processor_test_mod.addImport("dyld", dyld_mod);
        macho_processor_test_mod.addImport("cxx_abi", cxx_abi_mod);
        macho_processor_test_mod.addImport("init", init_mod);
        macho_processor_test_mod.addImport("cleo_routing", cleo_routing_mod);
        macho_processor_test_mod.addImport("scheduler", scheduler_mod);
        macho_processor_test_mod.addImport("jit", jit_mod);
        macho_processor_test_mod.addImport("macho_core", macho_core_mod);
        macho_processor_test_mod.addImport("process_core", process_core_mod);
        macho_processor_test_mod.addImport("import_handler", import_handler_mod);
        if (is_macos) {
            macho_processor_test_mod.addSystemFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{macos_sdk_root}) });
            macho_processor_test_mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{macos_sdk_root}) });
            macho_processor_test_mod.addCSourceFile(.{
                .file = b.path("../lib/Mach-O/native_window_bridge.m"),
                .flags = &.{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
            });
            macho_processor_test_mod.linkFramework("AppKit", .{});
            macho_processor_test_mod.linkFramework("QuartzCore", .{});
            macho_processor_test_mod.linkFramework("Metal", .{});
        }
        const macho_processor_test = b.addTest(.{ .root_module = macho_processor_test_mod });
        const macho_processor_check = b.step(
            "macho-processor-check",
            "Compile the focused Mach-O processor and decoder regression suite",
        );
        macho_processor_check.dependOn(&macho_processor_test.step);
        check_step.dependOn(&macho_processor_test.step);
    }

    // Aggregate Win32 ABI handshake suite
    {
        const abi_suite_mod = b.createModule(.{
            .root_source_file = b.path("../include/win32/Zig/abi_suite.zig"),
            .target = target,
            .optimize = optimize,
        });
        if (is_macos) abi_suite_mod.addIncludePath(b.path("../include/shims/macos"));
        abi_suite_mod.addIncludePath(b.path("../include/shims/win32"));
        abi_suite_mod.addIncludePath(b.path("../include"));
        abi_suite_mod.addImport("windows_base", windows_base_module);
        abi_suite_mod.addImport("win32_sysdefs", sysdefs_module);
        abi_suite_mod.addImport("win32_all", win32_all_module);
        abi_suite_mod.addImport("win32_pending", win32_pending_module);
        abi_suite_mod.addImport("win32_mmsystem", mmsystem_module);
        abi_suite_mod.addImport("win32_shim_surface", shim_surface_module);
        abi_suite_mod.addImport("behavior_api", behavior_module);
        abi_suite_mod.addImport("behavior", behavior_zig_module);
        abi_suite_mod.addImport("x86_asm", x86_asm_module);
        abi_suite_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        abi_suite_mod.addImport("dos_scene", dos_scene_module);
        abi_suite_mod.addImport("dos_palette", dos_palette_module);
        abi_suite_mod.addImport("dos_renderer", dos_renderer_module);
        abi_suite_mod.addImport("dos_platform", dos_platform_module);
        abi_suite_mod.addImport("dll_translator", dll_translator_module);
        const abi_suite_test = b.addTest(.{ .root_module = abi_suite_mod });
        check_step.dependOn(&abi_suite_test.step);
    }

    {
        const dll_test = b.addTest(.{ .root_module = dll_translator_module });
        check_step.dependOn(&dll_test.step);
    }

    {
        const dyld_cache_test = b.addTest(.{ .root_module = dyld_cache_tree_module });
        check_step.dependOn(&dyld_cache_test.step);
    }

    {
        const pseudo_kernel_cache_test = b.addTest(.{ .root_module = pseudo_kernel_cache_module });
        check_step.dependOn(&pseudo_kernel_cache_test.step);
    }

    {
        const pseudo_kernel_code_cache_table_test = b.addTest(.{ .root_module = pseudo_kernel_code_cache_table_module });
        check_step.dependOn(&pseudo_kernel_code_cache_table_test.step);
    }

    {
        const transpiler_mod = b.createModule(.{
            .root_source_file = b.path("../lib/transpiler/c_fix.zig"),
            .target = target,
            .optimize = optimize,
        });
        const transpiler_test = b.addTest(.{ .root_module = transpiler_mod });
        check_step.dependOn(&transpiler_test.step);

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

    const lib = b.addLibrary(.{
        .name = "rosette_zig",
        .linkage = .static,
        .root_module = zig_module,
    });
    b.installArtifact(lib);
}
