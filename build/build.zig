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
    const isa_decode_module = b.createModule(.{
        .root_source_file = b.path("../ISA/decode/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The direct PowerPC path: ISA/ppc/decode answers what an encoding is,
    // lib/runtime/ppc answers what it does. Neither goes through x86-64.
    const ppc_decode_module = b.createModule(.{
        .root_source_file = b.path("../ISA/ppc/decode/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The ARM64 instruction encoder the PowerPC recompiler emits through.
    const arm64_encode_module = b.createModule(.{
        .root_source_file = b.path("../lib/compiler/arm64/encode.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ppc_instruction_routing_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/PPC/xenia/runtime/instruction-routing/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ppc_runtime_module = b.createModule(.{
        .root_source_file = b.path("../lib/runtime/ppc/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ppc_runtime_module.addImport("ppc_decode", ppc_decode_module);
    ppc_runtime_module.addImport("arm64_encode", arm64_encode_module);
    ppc_runtime_module.addImport("ppc_instruction_routing", ppc_instruction_routing_mod);
    // The recompiler maps executable memory through libc.
    ppc_runtime_module.link_libc = true;
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
    // The reusable comptime rejection structure the phrase-matching packages
    // and the guest-log gate share. Declared first: several modules below
    // import it, directly or through a package.
    const phrase_filter_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/text/phrase-filter/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The host ABI contract catalogue and its comptime rejection filter. It
    // owns the contract type vocabulary too, so it must precede `contract_mod`.
    const host_contract_catalogue_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/abi/host-contract-catalogue/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // libc++'s __thread_struct is an ABI object with a one-pointer layout.
    // Keep that static fact in pkg; the guest-ABI runtime owns the
    // initialization action at the import boundary.
    const libcpp_thread_abi_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/abi/libcpp-thread-struct/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const contract_mod = b.createModule(.{
        .root_source_file = b.path("../lib/Contract/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_contract_catalogue_mod.addImport("phrase_filter", phrase_filter_mod);
    contract_mod.addImport("host_contract_catalogue", host_contract_catalogue_mod);
    const jit_mod = b.createModule(.{
        .root_source_file = b.path("../lib/compiler/JIT/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Runtime analogue of the build graph: keeps compilation evidence
    // separate from activation evidence and enforces application startup
    // ordering before a run is considered ready.
    const ready_compiler_mod = b.createModule(.{
        .root_source_file = b.path("../lib/ready-compiler/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xenia_ready_plan_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/ready-plan/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_ready_plan", xenia_ready_plan_mod);
    // The graphics handoff package is deliberately selected by the host ISA.
    // It contributes immutable ABI/ordering facts only; it cannot provide a
    // guest pointer, command buffer, or presentation event.
    const xenia_graphics_contract_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/graphics-contract/src/root.zig")
    else
        b.path("../pkg/x86/xenia/graphics-contract/src/root.zig");
    const xenia_graphics_contract_mod = b.createModule(.{
        .root_source_file = xenia_graphics_contract_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_graphics_contract", xenia_graphics_contract_mod);

    // Guest-endian facts are mirrored per host route and cross-checked below.
    // These are immutable source-derived values: the PPC guest word order is
    // identical on every route, while host codegen and host byte order remain
    // explicit route facts.
    const xenia_guest_endian_x86_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/x86/xenia/guest-endian/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xenia_guest_endian_arm64_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/ARM64/xenia/guest-endian/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xenia_guest_endian_ppc_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/PPC/xenia/guest-endian/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_guest_endian_x86", xenia_guest_endian_x86_mod);
    ready_compiler_mod.addImport("xenia_guest_endian_arm64", xenia_guest_endian_arm64_mod);
    ready_compiler_mod.addImport("xenia_guest_endian_ppc", xenia_guest_endian_ppc_mod);

    // Third-party endianness is a source mirror, not a runtime wrapper. Keep
    // one route-local implementation per host architecture and compare their
    // canonical guest vectors in the check graph.
    const endianness_x86_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/x86/third_party/endianness/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const endianness_arm64_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/ARM64/third_party/endianness/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const endianness_ppc_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/PPC/third_party/endianness/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("rosette_endianness_x86", endianness_x86_mod);
    ready_compiler_mod.addImport("rosette_endianness_arm64", endianness_arm64_mod);
    ready_compiler_mod.addImport("rosette_endianness_ppc", endianness_ppc_mod);

    const sha_x86_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/x86/third_party/crypto/sha/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sha_arm64_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/ARM64/third_party/crypto/sha/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sha_ppc_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/PPC/third_party/crypto/sha/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("rosette_sha_x86", sha_x86_mod);
    ready_compiler_mod.addImport("rosette_sha_arm64", sha_arm64_mod);
    ready_compiler_mod.addImport("rosette_sha_ppc", sha_ppc_mod);

    const dxbc_x86_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/x86/third_party/dxbc/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dxbc_arm64_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/ARM64/third_party/dxbc/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dxbc_ppc_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/PPC/third_party/dxbc/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("rosette_dxbc_x86", dxbc_x86_mod);
    ready_compiler_mod.addImport("rosette_dxbc_arm64", dxbc_arm64_mod);
    ready_compiler_mod.addImport("rosette_dxbc_ppc", dxbc_ppc_mod);

    const half_x86_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/x86/third_party/half/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const half_arm64_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/ARM64/third_party/half/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const half_ppc_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/PPC/third_party/half/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("rosette_half_x86", half_x86_mod);
    ready_compiler_mod.addImport("rosette_half_arm64", half_arm64_mod);
    ready_compiler_mod.addImport("rosette_half_ppc", half_ppc_mod);

    // The surface-path package separates Xenia's FBO render-target label from
    // the actual Vulkan-to-Metal WSI chain. It is compile-time evidence only;
    // native surface creation and presentation still require runtime events.
    const xenia_surface_path_contract_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/graphics/surface-path-contract/src/root.zig")
    else
        b.path("../pkg/x86/xenia/graphics/surface-path-contract/src/root.zig");
    const xenia_surface_path_contract_mod = b.createModule(.{
        .root_source_file = xenia_surface_path_contract_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_surface_path_contract", xenia_surface_path_contract_mod);
    // The shader-storage package records the Xenia macOS command-processor
    // handoff. It distinguishes explicit completion from the five-second
    // blocking-timeout continuation; it cannot synthesize either event.
    const xenia_shader_storage_contract_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/runtime/shader-storage-contract/src/root.zig")
    else
        b.path("../pkg/x86/xenia/runtime/shader-storage-contract/src/root.zig");
    const xenia_shader_storage_contract_mod = b.createModule(.{
        .root_source_file = xenia_shader_storage_contract_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_shader_storage_contract", xenia_shader_storage_contract_mod);
    // Which Xenia subsystem owns a Mach-O symbol is fixed when Xenia is
    // compiled, so the readiness gate looks it up instead of deriving it. The
    // package supplies only the mapping; deciding whether executing inside a
    // subsystem counts as progress stays in the runtime, which is the only
    // place that knows what else has happened.
    const xenia_launch_phase_map_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/runtime/launch-phase-map/src/root.zig")
    else
        b.path("../pkg/x86/xenia/runtime/launch-phase-map/src/root.zig");
    const xenia_launch_phase_map_mod = b.createModule(.{
        .root_source_file = xenia_launch_phase_map_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_launch_phase_map", xenia_launch_phase_map_mod);
    // Successful PPC translation is a stronger external-progress witness than
    // a host heartbeat: Xenia emits it only after a guest function assembled
    // into host code. The route package owns the text ABI and monotonicity
    // tests; the runtime decides whether the event keeps its quiet window open.
    const xenia_translation_progress_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/runtime/translation-progress/src/root.zig")
    else
        b.path("../pkg/x86/xenia/runtime/translation-progress/src/root.zig");
    const xenia_translation_progress_mod = b.createModule(.{
        .root_source_file = xenia_translation_progress_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_translation_progress", xenia_translation_progress_mod);
    // The page-range package is a real optional boundary provider, not a
    // readiness-only fact: its exported selector is included in the Mach-O
    // process image and Xenia may resolve it with dlsym at runtime. Xenia
    // retains the reference scan when the symbol is absent.
    const xenia_heap_range_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/memory/heap-range/src/root.zig")
    else
        b.path("../pkg/x86/xenia/memory/heap-range/src/root.zig");
    const xenia_heap_range_mod = b.createModule(.{
        .root_source_file = xenia_heap_range_root,
        .target = target,
        .optimize = optimize,
    });
    // The remaining five packages were on disk with tests and reached nothing
    // that ships. A package that is only in the test list is a claim nobody
    // can check against the binary, so each one is selected by the same host
    // ISA rule and imported by the module that consumes its facts.
    //
    // The guest is an x86-64 Mach-O image whose own guest is 32-bit big-endian
    // Xenon on *both* routes, so the ABI facts below do not change with the
    // host build. Only which host encoding and branch reach the route means
    // does.
    const xenia_abi_bridge_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/bridge/abi-bridge/src/root.zig")
    else
        b.path("../pkg/x86/xenia/bridge/abi-bridge/src/root.zig");
    const xenia_abi_bridge_mod = b.createModule(.{
        .root_source_file = xenia_abi_bridge_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_abi_bridge", xenia_abi_bridge_mod);
    // Host-side facts for the PPC guest bridge: guest words stay big-endian
    // and four-byte aligned whichever way the host reads them, and the host's
    // own branch reach is the route's, not the guest's.
    const xenia_guest_bridge_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/runtime/guest-bridge/src/root.zig")
    else
        b.path("../pkg/x86/xenia/runtime/guest-bridge/src/root.zig");
    const xenia_guest_bridge_mod = b.createModule(.{
        .root_source_file = xenia_guest_bridge_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_guest_bridge", xenia_guest_bridge_mod);
    // Xbyak label binding and the activation classifier. The label ledger
    // refuses to call a code buffer ready with an unbound label, which is the
    // exception the earlier evidence carried; the classifier separates
    // precompile progress from a silent graphics owner.
    const xenia_codegen_activation_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/runtime/codegen-activation/src/root.zig")
    else
        b.path("../pkg/x86/xenia/runtime/codegen-activation/src/root.zig");
    const xenia_codegen_activation_mod = b.createModule(.{
        .root_source_file = xenia_codegen_activation_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_codegen_activation", xenia_codegen_activation_mod);
    const jit_label_ledger_mod = b.createModule(.{
        .root_source_file = b.path("../lib/compiler/JIT/label_ledger.zig"),
        .target = target,
        .optimize = optimize,
    });
    jit_label_ledger_mod.addImport("xenia_codegen_activation", xenia_codegen_activation_mod);
    ready_compiler_mod.addImport("jit_label_ledger", jit_label_ledger_mod);
    // The wait boundary: a consuming wait cannot succeed without consuming a
    // pending signal. The package models the invariant; the live pthread and
    // kernel-event implementations stay in charge of behavior.
    const xenia_wait_contract_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/runtime/wait-contract/src/root.zig")
    else
        b.path("../pkg/x86/xenia/runtime/wait-contract/src/root.zig");
    const xenia_wait_contract_mod = b.createModule(.{
        .root_source_file = xenia_wait_contract_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_wait_contract", xenia_wait_contract_mod);
    const wait_runtime_mod = b.createModule(.{
        .root_source_file = b.path("../lib/runtime/pthread/wait_contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    wait_runtime_mod.addImport("xenia_wait_contract", xenia_wait_contract_mod);
    ready_compiler_mod.addImport("wait_runtime", wait_runtime_mod);
    // The activation report parser. Its stage vocabulary is the Ready
    // Compiler's, which is exactly why it is imported here: a stage renamed on
    // one side and not the other is a report that quietly stops matching, and
    // the comptime cross-check in `lib/ready-compiler/xenia.zig` fails the
    // build instead.
    const xenia_startup_evidence_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/diagnostics/startup-evidence/src/evidence.zig")
    else
        b.path("../pkg/x86/xenia/diagnostics/startup-evidence/src/evidence.zig");
    const xenia_startup_evidence_mod = b.createModule(.{
        .root_source_file = xenia_startup_evidence_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_startup_evidence", xenia_startup_evidence_mod);
    // The package contains immutable stage/vocabulary facts. Live report
    // accumulation belongs to lib, where it can observe process-owned log
    // streams without turning a package into a hidden runtime state holder.
    const startup_evidence_runtime_mod = b.createModule(.{
        .root_source_file = b.path("../lib/diagnostics/xenia_startup_evidence.zig"),
        .target = target,
        .optimize = optimize,
    });
    startup_evidence_runtime_mod.addImport("xenia_startup_evidence", xenia_startup_evidence_mod);
    ready_compiler_mod.addImport("startup_evidence_runtime", startup_evidence_runtime_mod);
    // Primitive dispatch is a Mach-O hot path. The package supplies only a
    // family lookup; the existing primitive handlers and fallback definitions
    // remain in charge of behavior.
    const xenia_primitive_contract_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/xenia/runtime/primitive-contract/src/root.zig")
    else
        b.path("../pkg/x86/xenia/runtime/primitive-contract/src/root.zig");
    const xenia_primitive_contract_mod = b.createModule(.{
        .root_source_file = xenia_primitive_contract_root,
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

    // Retained execution history: bounded-ring arithmetic and thread
    // partitioning, extracted from six owners. Declared at top level because
    // both processors and the process-core consume it.
    const execution_history_mod = b.createModule(.{
        .root_source_file = b.path("../lib/runtime/execution-history/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sha1_tracer_mod = b.createModule(.{
        .root_source_file = b.path("../lib/runtime/sha1-tracer/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const check_step = b.step("check", "Check Rosette Zig sources");
    const startup_evidence_runtime_test = b.addTest(.{ .root_module = startup_evidence_runtime_mod });
    check_step.dependOn(&b.addRunArtifact(startup_evidence_runtime_test).step);
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
        // llvm.zig reaches the host debug/runtime C symbols, which nothing
        // links into a bare test binary; the rest of third_party runs.
        if (comptime std.mem.eql(u8, rel_path, "llvm/llvm.zig")) {
            check_step.dependOn(&tp_test.step);
        } else {
            check_step.dependOn(&b.addRunArtifact(tp_test).step);
        }
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
        check_step.dependOn(&b.addRunArtifact(svx_test).step);
    }

    {
        const cleo_test = b.addTest(.{ .root_module = cleo_module });
        check_step.dependOn(&b.addRunArtifact(cleo_test).step);
    }

    {
        const contract_test = b.addTest(.{ .root_module = contract_mod });
        check_step.dependOn(&b.addRunArtifact(contract_test).step);
    }

    {
        const jit_test = b.addTest(.{ .root_module = jit_mod });
        check_step.dependOn(&b.addRunArtifact(jit_test).step);
    }

    {
        const ppc_decode_check = b.addTest(.{ .root_module = ppc_decode_module });
        check_step.dependOn(&b.addRunArtifact(ppc_decode_check).step);
    }

    {
        const ppc_runtime_check = b.addTest(.{ .root_module = ppc_runtime_module });
        check_step.dependOn(&b.addRunArtifact(ppc_runtime_check).step);
    }

    {
        const arm64_encode_check = b.addTest(.{ .root_module = arm64_encode_module });
        check_step.dependOn(&b.addRunArtifact(arm64_encode_check).step);
    }

    {
        // Xbox 360 XEX2 image reading, for running a title against the PowerPC
        // runtime without Xenia owning the module load.
        const xex_module = b.createModule(.{
            .root_source_file = b.path("../lib/linker/xex/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const xex_check = b.addTest(.{ .root_module = xex_module });
        check_step.dependOn(&b.addRunArtifact(xex_check).step);
    }

    {
        const isa_ppc_test_mod = b.createModule(.{
            .root_source_file = b.path("../ISA/ppc_test_root.zig"),
            .target = target,
            .optimize = optimize,
        });
        isa_ppc_test_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const isa_ppc_test = b.addTest(.{ .root_module = isa_ppc_test_mod });
        check_step.dependOn(&b.addRunArtifact(isa_ppc_test).step);
    }

    {
        const isa_math_test_mod = b.createModule(.{
            .root_source_file = b.path("../ISA/Math/test_root.zig"),
            .target = target,
            .optimize = optimize,
        });
        isa_math_test_mod.addImport("runtime_abi_handshake", runtime_abi_module);
        const isa_math_test = b.addTest(.{ .root_module = isa_math_test_mod });
        check_step.dependOn(&b.addRunArtifact(isa_math_test).step);
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
        check_step.dependOn(&b.addRunArtifact(yasm_test).step);
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
        check_step.dependOn(&b.addRunArtifact(lib866d_test).step);
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
        check_step.dependOn(&b.addRunArtifact(compat_router_test).step);
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
    //
    // Register state, flags, bit-test helpers and the emulated CPUID model are
    // wired as modules so the decoder families under ISA/decoding/ can reach
    // them by name (they live outside the decoder's module directory).
    const decoder_flags_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/flags.zig"),
        .target = target,
        .optimize = optimize,
    });
    const decoder_cpu_state_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/cpu_state.zig"),
        .target = target,
        .optimize = optimize,
    });
    decoder_cpu_state_mod.addImport("flags", decoder_flags_mod);
    const decoder_bit_test_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/bit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    decoder_bit_test_mod.addImport("flags", decoder_flags_mod);
    const decoder_capabilities_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/capabilities.zig"),
        .target = target,
        .optimize = optimize,
    });

    const x64_decoder_mod = b.createModule(.{
        .root_source_file = b.path("../ISA/decoding/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    x64_decoder_mod.addImport("isa_highway", isa_highway_module);
    x64_decoder_mod.addImport("isa_decode", isa_decode_module);
    x64_decoder_mod.addImport("isa_registry", isa_module);
    x64_decoder_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    x64_decoder_mod.addImport("flags", decoder_flags_mod);
    x64_decoder_mod.addImport("cpu_state", decoder_cpu_state_mod);
    x64_decoder_mod.addImport("bit_test", decoder_bit_test_mod);
    x64_decoder_mod.addImport("capabilities", decoder_capabilities_mod);
    const x64_decoder_test_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/decoder_test_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    x64_decoder_test_mod.addImport("x64_decoder", x64_decoder_mod);
    const x64_decoder_test = b.addTest(.{ .root_module = x64_decoder_test_mod });
    const run_x64_decoder_test = b.addRunArtifact(x64_decoder_test);
    check_step.dependOn(&run_x64_decoder_test.step);

    // The decoder families under ISA/decoding/ carry their own test blocks;
    // dependency modules' tests do not run under `zig test`, so aggregate them
    // behind a test root that imports every family file.
    const decoder_family_tests_mod = b.createModule(.{
        .root_source_file = b.path("../ISA/decoding/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    decoder_family_tests_mod.addImport("isa_highway", isa_highway_module);
    decoder_family_tests_mod.addImport("isa_decode", isa_decode_module);
    decoder_family_tests_mod.addImport("isa_registry", isa_module);
    decoder_family_tests_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    decoder_family_tests_mod.addImport("flags", decoder_flags_mod);
    decoder_family_tests_mod.addImport("cpu_state", decoder_cpu_state_mod);
    decoder_family_tests_mod.addImport("bit_test", decoder_bit_test_mod);
    decoder_family_tests_mod.addImport("capabilities", decoder_capabilities_mod);
    const decoder_family_tests = b.addTest(.{ .root_module = decoder_family_tests_mod });
    const run_decoder_family_tests = b.addRunArtifact(decoder_family_tests);
    check_step.dependOn(&run_decoder_family_tests.step);
    const setcc_stack_regression_test = b.addTest(.{
        .root_module = decoder_family_tests_mod,
        .filters = &.{"SETcc uses the ModRM r/m field for AH versus SPL"},
    });
    const run_setcc_stack_regression_test = b.addRunArtifact(setcc_stack_regression_test);
    const decoder_family_check_step = b.step(
        "decoder-family-check",
        "Run the focused SETcc stack-corruption decoder regression",
    );
    decoder_family_check_step.dependOn(&run_setcc_stack_regression_test.step);
    const isa_highway_test = b.addTest(.{ .root_module = isa_highway_module });
    check_step.dependOn(&b.addRunArtifact(isa_highway_test).step);
    const isa_decode_test = b.addTest(.{ .root_module = isa_decode_module });
    const run_isa_decode_test = b.addRunArtifact(isa_decode_test);
    check_step.dependOn(&run_isa_decode_test.step);
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
        elf_processor_mod.addImport("execution_history", execution_history_mod);
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
        elf_processor_test_mod.addImport("execution_history", execution_history_mod);
        const elf_processor_test = b.addTest(.{ .root_module = elf_processor_test_mod });
        check_step.dependOn(&b.addRunArtifact(elf_processor_test).step);

        const x64_guest_abi_test = b.addTest(.{ .root_module = x64_guest_abi_mod });
        check_step.dependOn(&b.addRunArtifact(x64_guest_abi_test).step);
    }

    // TOML processor (patch file format parser)
    {
        const toml_processor_mod = b.createModule(.{
            .root_source_file = b.path("../lib/processor/TOML_processor/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const toml_processor_test = b.addTest(.{ .root_module = toml_processor_mod });
        check_step.dependOn(&b.addRunArtifact(toml_processor_test).step);

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

    // PS1 processor (PowerShell .ps1 → POSIX shell/Makefile translator)
    {
        const ps1_processor_mod = b.createModule(.{
            .root_source_file = b.path("../lib/processor/ps1_processor/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const ps1_processor_test = b.addTest(.{ .root_module = ps1_processor_mod });
        check_step.dependOn(&b.addRunArtifact(ps1_processor_test).step);

        const ps1_exe_mod = b.createModule(.{
            .root_source_file = b.path("../lib/processor/ps1_processor/main.zig"),
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
        primitive_mod.addImport("xenia_primitive_contract", xenia_primitive_contract_mod);
        const vtable_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/vtable/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        // Rooted here so its rules are executed rather than merely compiled.
        // This module decides whether Rosette rewrites the dispatch pointer of
        // a live guest object; the conditions under which it says yes are
        // exactly the kind that must be tested, and as a dependency-only
        // module none of its tests had ever run.
        const vtable_test = b.addTest(.{ .root_module = vtable_mod });
        check_step.dependOn(&b.addRunArtifact(vtable_test).step);
        const guard_rollback_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/guard-rollback/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        // Versioned, typed hardware facts remain separate from the code that
        // consumes them. The GPU runtime publishes its negotiated backend into
        // this description; it cannot use the tree to actuate guest state.
        const device_tree_mod = b.createModule(.{
            .root_source_file = b.path("../lib/device_tree/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const device_tree_test = b.addTest(.{ .root_module = device_tree_mod });
        check_step.dependOn(&b.addRunArtifact(device_tree_test).step);

        // Backend-neutral host GPU ownership and the versioned consumer
        // handshake. Created before dyld because the Vulkan loader forwarder is
        // the first adapter feeding truthful native-boundary stages into it.
        const preflight_mod = b.createModule(.{
            .root_source_file = b.path("../lib/preflight/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const preflight_test = b.addTest(.{ .root_module = preflight_mod });
        check_step.dependOn(&b.addRunArtifact(preflight_test).step);

        const ready_compiler_test = b.addTest(.{ .root_module = ready_compiler_mod });
        check_step.dependOn(&b.addRunArtifact(ready_compiler_test).step);

        // The route packages under `pkg/` ship inside the processor, so their
        // own tests belong in the same gate as everything else that does.
        // Each package carries a `verify.sh`, but a check that only runs when
        // someone remembers to run it is not a check — a drifted package
        // reached the built binary and the suite stayed green.
        //
        // Both routes are tested regardless of which one this build selects.
        // The unselected one is the companion that a later ARM64 or x86 host
        // will link, and letting it rot until that host exists is how the
        // "preflight contract" packages stop matching the route they mirror.
        // Not a route package — one file, no mirror — but it ships inside the
        // processor and its tests belong in the same gate as everything else
        // that does.
        const common_package_roots = [_][]const u8{
            "../pkg/common/abi/receiver-classification/src/root.zig",
            "../pkg/common/xenos/register-map/src/root.zig",
            "../pkg/common/abi/near-null-shape/src/root.zig",
            "../pkg/common/xenia/log-phrase-map/src/root.zig",
            "../pkg/common/abi/host-contract-catalogue/src/root.zig",
            "../pkg/common/text/phrase-filter/src/root.zig",
            "../pkg/common/xenia/ready-plan/src/root.zig",
        };
        inline for (common_package_roots) |package_root| {
            const package_mod = b.createModule(.{
                .root_source_file = b.path(package_root),
                .target = target,
                .optimize = optimize,
            });
            // Two of these import the shared rejection filter. Supplying it to
            // every common package is harmless for the rest and keeps this loop
            // from needing a per-package dependency table that would drift.
            // A fresh module is used rather than `phrase_filter_mod`, which is
            // declared in the build-artifact scope above and not visible here.
            package_mod.addImport("phrase_filter", b.createModule(.{
                .root_source_file = b.path("../pkg/common/text/phrase-filter/src/root.zig"),
                .target = target,
                .optimize = optimize,
            }));
            const package_test = b.addTest(.{ .root_module = package_mod });
            check_step.dependOn(&b.addRunArtifact(package_test).step);
        }

        const route_package_roots = [_][]const u8{
            "../pkg/x86/xenia/graphics-contract/src/root.zig",
            "../pkg/x86/xenia/graphics/surface-path-contract/src/root.zig",
            "../pkg/x86/xenia/bridge/abi-bridge/src/root.zig",
            // This package's tests live beside the evidence table rather than
            // in a `root.zig`; `main.zig` is its executable half.
            "../pkg/x86/xenia/diagnostics/startup-evidence/src/evidence.zig",
            "../pkg/x86/xenia/runtime/codegen-activation/src/root.zig",
            "../pkg/x86/xenia/runtime/launch-phase-map/src/root.zig",
            "../pkg/x86/xenia/runtime/primitive-contract/src/root.zig",
            "../pkg/x86/xenia/runtime/guest-bridge/src/root.zig",
            "../pkg/x86/xenia/runtime/shader-storage-contract/src/root.zig",
            "../pkg/x86/xenia/runtime/wait-contract/src/root.zig",
            "../pkg/x86/xenia/memory/heap-range/src/root.zig",
            "../pkg/ARM64/xenia/graphics-contract/src/root.zig",
            "../pkg/ARM64/xenia/graphics/surface-path-contract/src/root.zig",
            "../pkg/ARM64/xenia/bridge/abi-bridge/src/root.zig",
            // Same split as the x86 copy: the tests live beside the evidence
            // table, and `main.zig` is the executable half.
            "../pkg/ARM64/xenia/diagnostics/startup-evidence/src/evidence.zig",
            "../pkg/ARM64/xenia/runtime/codegen-activation/src/root.zig",
            "../pkg/ARM64/xenia/runtime/guest-bridge/src/root.zig",
            "../pkg/ARM64/xenia/runtime/launch-phase-map/src/root.zig",
            "../pkg/ARM64/xenia/runtime/primitive-contract/src/root.zig",
            "../pkg/ARM64/xenia/runtime/shader-storage-contract/src/root.zig",
            "../pkg/ARM64/xenia/runtime/wait-contract/src/root.zig",
            "../pkg/ARM64/xenia/memory/heap-range/src/root.zig",
            "../pkg/x86/xenia/guest-endian/src/root.zig",
            "../pkg/ARM64/xenia/guest-endian/src/root.zig",
            "../pkg/PPC/xenia/guest-endian/src/root.zig",
            "../pkg/PPC/xenia/runtime/instruction-routing/src/root.zig",
            "../pkg/x86/third_party/endianness/src/root.zig",
            "../pkg/ARM64/third_party/endianness/src/root.zig",
            "../pkg/PPC/third_party/endianness/src/root.zig",
            "../pkg/x86/third_party/crypto/sha/src/root.zig",
            "../pkg/ARM64/third_party/crypto/sha/src/root.zig",
            "../pkg/PPC/third_party/crypto/sha/src/root.zig",
            "../pkg/x86/third_party/dxbc/src/root.zig",
            "../pkg/ARM64/third_party/dxbc/src/root.zig",
            "../pkg/PPC/third_party/dxbc/src/root.zig",
            "../pkg/x86/third_party/half/src/root.zig",
            "../pkg/ARM64/third_party/half/src/root.zig",
            "../pkg/PPC/third_party/half/src/root.zig",
        };
        inline for (route_package_roots) |package_root| {
            const package_mod = b.createModule(.{
                .root_source_file = b.path(package_root),
                .target = target,
                .optimize = optimize,
            });
            const package_test = b.addTest(.{ .root_module = package_mod });
            check_step.dependOn(&b.addRunArtifact(package_test).step);
        }

        const xenia_guest_endian_equivalence_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/xenia_guest_endian_equivalence.zig"),
            .target = target,
            .optimize = optimize,
        });
        xenia_guest_endian_equivalence_mod.addImport("x86_guest_endian", xenia_guest_endian_x86_mod);
        xenia_guest_endian_equivalence_mod.addImport("arm64_guest_endian", xenia_guest_endian_arm64_mod);
        xenia_guest_endian_equivalence_mod.addImport("ppc_guest_endian", xenia_guest_endian_ppc_mod);
        const xenia_guest_endian_equivalence_test = b.addTest(.{ .root_module = xenia_guest_endian_equivalence_mod });
        check_step.dependOn(&b.addRunArtifact(xenia_guest_endian_equivalence_test).step);

        const third_party_endianness_equivalence_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/third_party_endianness_equivalence.zig"),
            .target = target,
            .optimize = optimize,
        });
        third_party_endianness_equivalence_mod.addImport("x86_endianness", endianness_x86_mod);
        third_party_endianness_equivalence_mod.addImport("arm64_endianness", endianness_arm64_mod);
        third_party_endianness_equivalence_mod.addImport("ppc_endianness", endianness_ppc_mod);
        const third_party_endianness_equivalence_test = b.addTest(.{ .root_module = third_party_endianness_equivalence_mod });
        check_step.dependOn(&b.addRunArtifact(third_party_endianness_equivalence_test).step);

        const third_party_sha_equivalence_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/third_party_sha_equivalence.zig"),
            .target = target,
            .optimize = optimize,
        });
        third_party_sha_equivalence_mod.addImport("x86_sha", sha_x86_mod);
        third_party_sha_equivalence_mod.addImport("arm64_sha", sha_arm64_mod);
        third_party_sha_equivalence_mod.addImport("ppc_sha", sha_ppc_mod);
        const third_party_sha_equivalence_test = b.addTest(.{ .root_module = third_party_sha_equivalence_mod });
        check_step.dependOn(&b.addRunArtifact(third_party_sha_equivalence_test).step);

        const third_party_dxbc_equivalence_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/third_party_dxbc_equivalence.zig"),
            .target = target,
            .optimize = optimize,
        });
        third_party_dxbc_equivalence_mod.addImport("x86_dxbc", dxbc_x86_mod);
        third_party_dxbc_equivalence_mod.addImport("arm64_dxbc", dxbc_arm64_mod);
        third_party_dxbc_equivalence_mod.addImport("ppc_dxbc", dxbc_ppc_mod);
        const third_party_dxbc_equivalence_test = b.addTest(.{ .root_module = third_party_dxbc_equivalence_mod });
        check_step.dependOn(&b.addRunArtifact(third_party_dxbc_equivalence_test).step);

        const third_party_half_equivalence_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/third_party_half_equivalence.zig"),
            .target = target,
            .optimize = optimize,
        });
        third_party_half_equivalence_mod.addImport("x86_half", half_x86_mod);
        third_party_half_equivalence_mod.addImport("arm64_half", half_arm64_mod);
        third_party_half_equivalence_mod.addImport("ppc_half", half_ppc_mod);
        const third_party_half_equivalence_test = b.addTest(.{ .root_module = third_party_half_equivalence_mod });
        check_step.dependOn(&b.addRunArtifact(third_party_half_equivalence_test).step);

        // Compile-side companion to the readiness gate: the resolutions a
        // finished link set leaves undetermined produce no diagnostic from
        // either the compiler or the linker, and surface as runtime defects.
        const link_audit_mod = b.createModule(.{
            .root_source_file = b.path("../lib/link-audit/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const link_audit_test = b.addTest(.{ .root_module = link_audit_mod });
        check_step.dependOn(&b.addRunArtifact(link_audit_test).step);

        const link_audit_tool_mod = b.createModule(.{
            .root_source_file = b.path("../src/tooling/link-audit/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        link_audit_tool_mod.addImport("link_audit", link_audit_mod);
        const link_audit_tool_test = b.addTest(.{ .root_module = link_audit_tool_mod });
        check_step.dependOn(&b.addRunArtifact(link_audit_tool_test).step);

        // Xenos register numbers are console hardware, not host or emulator
        // build state, so there is one copy and no route selection.
        const xenos_register_map_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/common/xenos/register-map/src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const rosette_ppc_host_abi_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/common/abi/rosette-ppc-host/src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const gpu_mod = b.createModule(.{
            .root_source_file = b.path("../lib/gpu/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        gpu_mod.addImport("device_tree", device_tree_mod);
        gpu_mod.addImport("xenos_register_map", xenos_register_map_mod);
        const gpu_test = b.addTest(.{ .root_module = gpu_mod });
        check_step.dependOn(&b.addRunArtifact(gpu_test).step);
        const dyld_mod = b.createModule(.{
            .root_source_file = b.path("../lib/linker/dyld/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        dyld_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        dyld_mod.addImport("gpu", gpu_mod);
        dyld_mod.addImport("xenia_heap_range", xenia_heap_range_mod);
        dyld_mod.addImport("rosette_ppc_host_abi", rosette_ppc_host_abi_mod);
        dyld_mod.addImport("ppc_runtime", ppc_runtime_module);
        const scheduler_mod = b.createModule(.{
            .root_source_file = b.path("../lib/scheduler/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        // Rooted here so the scheduler's tests actually run rather than merely
        // compile as a dependency of something else: notifier-liveness and
        // wait-graph logic decides whether a stalled run is diagnosable, and an
        // untested version of it is worse than none.
        const scheduler_test = b.addTest(.{ .root_module = scheduler_mod });
        check_step.dependOn(&b.addRunArtifact(scheduler_test).step);
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
        init_mod.addImport("event_log", event_log_mod);

        // Rooted here rather than beside its creation because it needs
        // `event_log`, which the unwinder imports directly. That dependency was
        // invisible while the module was only ever built as someone else's
        // dependency — which is precisely what rooting a module as a test
        // surfaces.
        cxx_abi_mod.addImport("event_log", event_log_mod);

        // `__dynamic_cast` is its own library: reading a foreign process's
        // RTTI, walking a live object's subobject graph, and separating the
        // null C++ defines from the null that means Rosette could not decide.
        // Rooted here so its rules are executed, not merely compiled.
        const dynamic_cast_mod = b.createModule(.{
            .root_source_file = b.path("../lib/abi/dynamic-cast/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        dynamic_cast_mod.addImport("event_log", event_log_mod);
        const dynamic_cast_test = b.addTest(.{ .root_module = dynamic_cast_mod });
        check_step.dependOn(&b.addRunArtifact(dynamic_cast_test).step);
        cxx_abi_mod.addImport("dynamic_cast", dynamic_cast_mod);

        const cxx_abi_test = b.addTest(.{ .root_module = cxx_abi_mod });
        check_step.dependOn(&b.addRunArtifact(cxx_abi_test).step);
        dyld_mod.addImport("event_log", event_log_mod);
        // Rooted here, after the last addImport, so dyld's own tests execute
        // rather than only compile as somebody else's dependency. The Vulkan
        // loader bridge lives in this module, and its enumeration and
        // create-info offsets are exactly the kind of rule that is silent at
        // runtime and only visible as a guest failure many calls later.
        const dyld_test = b.addTest(.{ .root_module = dyld_mod });
        const run_dyld_test = b.addRunArtifact(dyld_test);
        const dyld_check = b.step("dyld-check", "Run the dynamic linker and Vulkan loader bridge tests");
        dyld_check.dependOn(&run_dyld_test.step);
        check_step.dependOn(&run_dyld_test.step);
        // Xenia's log phrases and the comptime rare-character filter over them.
        const xenia_log_phrase_map_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/common/xenia/log-phrase-map/src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const diagnostics_mod = b.createModule(.{
            .root_source_file = b.path("../lib/diagnostics/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        diagnostics_mod.addImport("event_log", event_log_mod);
        diagnostics_mod.addImport("xenia_shader_storage_contract", xenia_shader_storage_contract_mod);
        xenia_log_phrase_map_mod.addImport("phrase_filter", phrase_filter_mod);
        diagnostics_mod.addImport("xenia_log_phrase_map", xenia_log_phrase_map_mod);
        const diagnostics_test = b.addTest(.{ .root_module = diagnostics_mod });
        check_step.dependOn(&b.addRunArtifact(diagnostics_test).step);
        diagnostics_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        const memory_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/memory/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        memory_mod.addImport("dyld", dyld_mod);
        memory_mod.addImport("event_log", event_log_mod);
        // Guest memory placement and lifetime. `root.zig` already pulled every
        // submodule's tests into its `test` block, but nothing ever ran them:
        // the module was only ever a dependency, so the rules about which
        // mapping replaces which — the rules a MAP_FIXED request decides guest
        // state on — were compiled and never executed.
        const memory_test = b.addTest(.{ .root_module = memory_mod });
        check_step.dependOn(&b.addRunArtifact(memory_test).step);
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
        guest_abi_mod.addImport("libcpp_thread_abi", libcpp_thread_abi_mod);
        const io_mod = b.createModule(.{
            .root_source_file = b.path("../lib/io/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        io_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        io_mod.addImport("cxx_abi", cxx_abi_mod);
        io_mod.addImport("event_log", event_log_mod);
        // Rooted and run: thread-local placement is an ABI contract, and the
        // previous implementation was wrong in a way that produced no error —
        // only another thread's data appearing inside yours.
        const guest_abi_test = b.addTest(.{ .root_module = guest_abi_mod });
        check_step.dependOn(&b.addRunArtifact(guest_abi_test).step);
        const libcpp_thread_abi_test = b.addTest(.{ .root_module = libcpp_thread_abi_mod });
        check_step.dependOn(&b.addRunArtifact(libcpp_thread_abi_test).step);

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

        // Address-to-name, and the reason when there is no name. Rooted and run
        // because the defect this module replaces was a resolver that compiled,
        // type-checked and answered `<unknown>` for every address in the
        // program: nothing but an executed test can catch a guard that is
        // silently always false.
        const macho_symbolication_mod = b.createModule(.{
            .root_source_file = b.path("../lib/Mach-O/symbolication.zig"),
            .target = target,
            .optimize = optimize,
        });
        const macho_symbolication_test = b.addTest(.{ .root_module = macho_symbolication_mod });
        check_step.dependOn(&b.addRunArtifact(macho_symbolication_test).step);

        // `types.zig` owns `TraceEntry`, and `TraceEntry` now owns the mapping
        // from a decoder register id onto a snapshot field — the input to every
        // history-based causal walk in the runtime, and previously copied
        // byte-for-byte into three of them. Rooted and run so that mapping has
        // an executed test rather than one that merely compiles as part of the
        // aggregate suite.
        const macho_types_mod = b.createModule(.{
            .root_source_file = b.path("../lib/Mach-O/types.zig"),
            .target = target,
            .optimize = optimize,
        });
        macho_types_mod.addImport("x64_decoder", x64_decoder_mod);
        macho_types_mod.addImport("dyld", dyld_mod);
        macho_types_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
        macho_types_mod.addImport("exit_diagnostics", exit_diagnostics_module);
        macho_types_mod.addImport("guest_abi", guest_abi_mod);
        const macho_types_test = b.addTest(.{ .root_module = macho_types_mod });
        check_step.dependOn(&b.addRunArtifact(macho_types_test).step);

        // Ownership arbitration: single-owner selection, per-family ledgers,
        // and data authorship. Extracted because duplicated *authority* — not
        // duplicated work — is what made fixes in one subsystem surface as
        // regressions in another.
        const ownership_mod = b.createModule(.{
            .root_source_file = b.path("../lib/ownership/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        // The forwarder routes a release by owner, which is an ownership
        // question, so the memory module depends on this rather than
        // re-deriving provenance from address ranges.
        // Who refused a guest access, and whether the refusal is the runtime's
        // granularity leaking or the guest's own trap firing. Rooted and run.
        const guest_protection_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/guest-protection/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const guest_protection_test = b.addTest(.{ .root_module = guest_protection_mod });
        check_step.dependOn(&b.addRunArtifact(guest_protection_test).step);
        memory_mod.addImport("guest_protection", guest_protection_mod);
        memory_mod.addImport("ownership", ownership_mod);
        const ownership_test = b.addTest(.{ .root_module = ownership_mod });
        check_step.dependOn(&b.addRunArtifact(ownership_test).step);

        // Observed guest structure shape: which fields the translation reads
        // and writes, so a missing store is a measurement rather than a guess.
        const guest_structure_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/guest-structure/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const guest_structure_test = b.addTest(.{ .root_module = guest_structure_mod });
        check_step.dependOn(&b.addRunArtifact(guest_structure_test).step);

        // The guest address-space model: derived from observed mappings rather
        // than asserted from build-time constants.
        const guest_address_space_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/guest-address-space/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const guest_address_space_test = b.addTest(.{ .root_module = guest_address_space_mod });
        check_step.dependOn(&b.addRunArtifact(guest_address_space_test).step);

        // Whether `rdi` holds a receiver at a given callee is fixed by that
        // callee's declared signature, so the near-null predictor looks it up
        // instead of walking a string table on the dispatch path. This package
        // has no route mirror on purpose: it describes the *guest* x86-64 ABI,
        // which is the same whichever host Rosette was compiled for.
        // The address-space bound, the Itanium mangling rule and the libc++
        // layout arithmetic behind a near-null reading. Policy stays in lib.
        const near_null_shape_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/common/abi/near-null-shape/src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const common_receiver_classification_mod = b.createModule(.{
            .root_source_file = b.path("../pkg/common/abi/receiver-classification/src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const process_core_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/process-core/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        process_core_mod.addImport("common_receiver_classification", common_receiver_classification_mod);
        process_core_mod.addImport("near_null_shape", near_null_shape_mod);
        process_core_mod.addImport("phrase_filter", phrase_filter_mod);
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
        process_core_mod.addImport("execution_history", execution_history_mod);
        process_core_mod.addImport("ownership", ownership_mod);
        process_core_mod.addImport("guest_address_space", guest_address_space_mod);

        // Dispatch tables: what a zero entry means, decided from the entry's
        // neighbourhood rather than from the entry alone. Rooted and run —
        // "the target was null" is the same sentence for three different bugs,
        // and the tests are what pin which is which.
        const dispatch_table_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/dispatch-table/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const dispatch_table_test = b.addTest(.{ .root_module = dispatch_table_mod });
        check_step.dependOn(&b.addRunArtifact(dispatch_table_test).step);
        process_core_mod.addImport("dispatch_table", dispatch_table_mod);

        // Guest byte order. A missed big-endian conversion is the one
        // corruption that carries its own correction, so it can be counted —
        // and one reversed value versus several is the difference between a bad
        // instruction and a bad conversion path.
        const byte_order_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/byte-order/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const byte_order_test = b.addTest(.{ .root_module = byte_order_mod });
        check_step.dependOn(&b.addRunArtifact(byte_order_test).step);
        process_core_mod.addImport("byte_order", byte_order_mod);

        // The population of dispatch sites the bounded machine meets, split by
        // whether it got through. Rooted and run: "x traversed, y halted, of z
        // distinct sites" is the number that decides whether a halt is one gap
        // or the recogniser's coverage, and it has to be right.
        const dispatch_recovery_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/dispatch-recovery/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const dispatch_recovery_test = b.addTest(.{ .root_module = dispatch_recovery_mod });
        check_step.dependOn(&b.addRunArtifact(dispatch_recovery_test).step);
        process_core_mod.addImport("dispatch_recovery", dispatch_recovery_mod);

        // Guest bootstrap observation and the host execution API share one GPU
        // module so neither can mistake synthetic host progress for guest work.
        process_core_mod.addImport("gpu", gpu_mod);
        process_core_mod.addImport("device_tree", device_tree_mod);
        process_core_mod.addImport("preflight", preflight_mod);
        process_core_mod.addImport("ready_compiler", ready_compiler_mod);
        // Rooted so these run rather than merely compile. Until this target
        // existed the module's tests only ever type-checked as part of the
        // processor build, where they are never instantiated — two of them had
        // silently stopped compiling as a result.
        const process_core_test = b.addTest(.{ .root_module = process_core_mod });
        check_step.dependOn(&b.addRunArtifact(process_core_test).step);
        process_core_mod.addImport("guest_structure", guest_structure_mod);

        // The bounded dispatch transducer is a self-contained decision
        // procedure over supplied invariants, and its test blocks are the only
        // executable specification of which null-base dispatches may redirect.
        // As a dependency of process_core those blocks neither compile nor run
        // under `zig test`, so it is rooted directly and actually executed —
        // an unreachable redirect branch previously passed review because the
        // suite asserting it was never built.
        const bounded_dispatch_fst_mod = b.createModule(.{
            .root_source_file = b.path("../lib/runtime/process-core/bounded_dispatch_fst.zig"),
            .target = target,
            .optimize = optimize,
        });
        const bounded_dispatch_fst_test = b.addTest(.{ .root_module = bounded_dispatch_fst_mod });
        const run_bounded_dispatch_fst_test = b.addRunArtifact(bounded_dispatch_fst_test);
        const bounded_dispatch_check = b.step(
            "bounded-dispatch-check",
            "Run the bounded null-base dispatch transducer decision tests",
        );
        bounded_dispatch_check.dependOn(&run_bounded_dispatch_fst_test.step);
        check_step.dependOn(&run_bounded_dispatch_fst_test.step);

        // Its tests are the executable statement of what "the oldest retained
        // entry" and "this thread's window" mean, so they are rooted and run
        // rather than compiled.
        const execution_history_test = b.addTest(.{ .root_module = execution_history_mod });
        const run_execution_history_test = b.addRunArtifact(execution_history_test);
        check_step.dependOn(&run_execution_history_test.step);

        // Per-family recovery bookkeeping: counts, log throttles and loop
        // guards. Self-contained for the same reason, and rooted here so the
        // guarantees it makes about family isolation are actually executed.
        const recovery_ledger_mod = b.createModule(.{
            .root_source_file = b.path("../lib/ownership/ledger.zig"),
            .target = target,
            .optimize = optimize,
        });
        const recovery_ledger_test = b.addTest(.{ .root_module = recovery_ledger_mod });
        const run_recovery_ledger_test = b.addRunArtifact(recovery_ledger_test);
        bounded_dispatch_check.dependOn(&run_recovery_ledger_test.step);
        check_step.dependOn(&run_recovery_ledger_test.step);

        // Guest-range lifetime. The transducer's "this field was never written"
        // verdict is only a statement about the guest while the storage behind
        // the field is still the storage the guest wrote to, so this rides the
        // same check step as the transducer itself.
        const guest_lifetime_mod = b.createModule(.{
            .root_source_file = b.path("../lib/ownership/lifetime.zig"),
            .target = target,
            .optimize = optimize,
        });
        const guest_lifetime_test = b.addTest(.{ .root_module = guest_lifetime_mod });
        const run_guest_lifetime_test = b.addRunArtifact(guest_lifetime_test);
        bounded_dispatch_check.dependOn(&run_guest_lifetime_test.step);
        check_step.dependOn(&run_guest_lifetime_test.step);

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
        macho_processor_mod.addImport("dispatch_recovery", dispatch_recovery_mod);
        macho_processor_mod.addImport("gpu", gpu_mod);
        macho_processor_mod.addImport("device_tree", device_tree_mod);
        macho_processor_mod.addImport("preflight", preflight_mod);
        macho_processor_mod.addImport("ready_compiler", ready_compiler_mod);
        macho_processor_mod.addImport("xenia_heap_range", xenia_heap_range_mod);
        macho_processor_mod.addImport("ppc_runtime", ppc_runtime_module);
        macho_processor_mod.addImport("diagnostics", diagnostics_mod);
        macho_processor_mod.addImport("memory", memory_mod);
        macho_processor_mod.addImport("io", io_mod);
        macho_processor_mod.addImport("guest_abi", guest_abi_mod);
        macho_processor_mod.addImport("pthread", pthread_mod);
        macho_processor_mod.addImport("execution_history", execution_history_mod);
        macho_processor_mod.addImport("ownership", ownership_mod);
        macho_processor_mod.addImport("guest_address_space", guest_address_space_mod);
        macho_processor_mod.addImport("guest_structure", guest_structure_mod);
        macho_processor_mod.addImport("dispatch_table", dispatch_table_mod);
        macho_processor_mod.addImport("byte_order", byte_order_mod);
        macho_processor_mod.addImport("guest_protection", guest_protection_mod);
        macho_processor_mod.addImport("sha1_tracer", sha1_tracer_mod);
        macho_processor_mod.addImport("import_handler", import_handler_mod);
        if (is_macos) {
            macho_processor_mod.addSystemFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{macos_sdk_root}) });
            macho_processor_mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{macos_sdk_root}) });
            macho_processor_mod.addCSourceFile(.{
                .file = b.path("../lib/Mach-O/native_window_bridge.m"),
                .flags = &.{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
            });
            macho_processor_mod.addCSourceFile(.{
                .file = b.path("../lib/Mach-O/xenia_heap_exports_anchor.c"),
                .flags = &.{ "-Wall", "-Wextra" },
            });
            macho_processor_mod.addCSourceFile(.{
                .file = b.path("../lib/Mach-O/rosette_ppc_exports_anchor.c"),
                .flags = &.{ "-Wall", "-Wextra" },
            });
            macho_processor_mod.linkFramework("AppKit", .{});
            macho_processor_mod.linkFramework("QuartzCore", .{});
            macho_processor_mod.linkFramework("Metal", .{});
        }
        // The Mach-O runtime carries the full MachOState struct (hundreds of
        // diagnostics/ledger fields) as a stack local inside MachOState.init and
        // loadAndRun; the inlined frames need ~18MB combined, which overflowed
        // the 16MB default main stack with an EXC_BAD_ACCESS past the stack
        // guard (killed before any handler could run, so no crash point). Give
        // the main thread a stack that fits the actual frames with headroom.
        const macho_processor = b.addExecutable(.{
            .name = "macho_processor",
            .root_module = macho_processor_mod,
        });
        // The Mach-O runtime carries the full MachOState struct (hundreds of
        // diagnostics/ledger fields) as a stack local inside MachOState.init and
        // loadAndRun; the inlined frames need ~18MB combined, which overflowed
        // the 16MB default main stack with an EXC_BAD_ACCESS past the stack
        // guard (killed before any handler could run, so no crash point). Give
        // the main thread a stack that fits the actual frames with headroom.
        macho_processor.stack_size = 64 * 1024 * 1024;
        const macho_processor_install = b.addInstallArtifact(macho_processor, .{});
        b.getInstallStep().dependOn(&macho_processor_install.step);
        const macho_processor_step = b.step(
            "macho-processor",
            "Build and install the Mach-O processor with all runtime providers",
        );
        macho_processor_step.dependOn(&macho_processor_install.step);

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
        macho_processor_test_mod.addImport("dispatch_recovery", dispatch_recovery_mod);
        macho_processor_test_mod.addImport("gpu", gpu_mod);
        macho_processor_test_mod.addImport("device_tree", device_tree_mod);
        macho_processor_test_mod.addImport("preflight", preflight_mod);
        macho_processor_test_mod.addImport("ready_compiler", ready_compiler_mod);
        macho_processor_test_mod.addImport("xenia_heap_range", xenia_heap_range_mod);
        macho_processor_test_mod.addImport("diagnostics", diagnostics_mod);
        macho_processor_test_mod.addImport("memory", memory_mod);
        macho_processor_test_mod.addImport("io", io_mod);
        macho_processor_test_mod.addImport("guest_abi", guest_abi_mod);
        macho_processor_test_mod.addImport("pthread", pthread_mod);
        macho_processor_test_mod.addImport("execution_history", execution_history_mod);
        macho_processor_test_mod.addImport("ownership", ownership_mod);
        macho_processor_test_mod.addImport("guest_address_space", guest_address_space_mod);
        macho_processor_test_mod.addImport("guest_structure", guest_structure_mod);
        macho_processor_test_mod.addImport("dispatch_table", dispatch_table_mod);
        macho_processor_test_mod.addImport("byte_order", byte_order_mod);
        macho_processor_test_mod.addImport("guest_protection", guest_protection_mod);
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
        // Run them, not merely compile them. `check_step` depended on the
        // compile step, so the Mach-O processor's decoder and interpreter
        // regressions — the suite that guards exactly the hot-path changes most
        // likely to break something silently — had never executed under
        // `zig build check`.
        check_step.dependOn(&b.addRunArtifact(macho_processor_test).step);
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
        check_step.dependOn(&b.addRunArtifact(dll_test).step);
    }

    {
        const dyld_cache_test = b.addTest(.{ .root_module = dyld_cache_tree_module });
        check_step.dependOn(&b.addRunArtifact(dyld_cache_test).step);
    }

    {
        const pseudo_kernel_cache_test = b.addTest(.{ .root_module = pseudo_kernel_cache_module });
        check_step.dependOn(&b.addRunArtifact(pseudo_kernel_cache_test).step);
    }

    {
        const pseudo_kernel_code_cache_table_test = b.addTest(.{ .root_module = pseudo_kernel_code_cache_table_module });
        check_step.dependOn(&b.addRunArtifact(pseudo_kernel_code_cache_table_test).step);
    }

    {
        const transpiler_mod = b.createModule(.{
            .root_source_file = b.path("../lib/transpiler/c_fix.zig"),
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

    const lib = b.addLibrary(.{
        .name = "rosette_zig",
        .linkage = .static,
        .root_module = zig_module,
    });
    b.installArtifact(lib);
}
