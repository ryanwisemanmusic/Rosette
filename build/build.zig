const std = @import("std");
const builtin = @import("builtin");

/// Reference-only headers (upstream win32, thr, winsdk). Not part of the public API.
const reference_include = "../.rosette/include";

pub fn build(b: *std.Build) void {
    var target_query = b.standardTargetOptionsQueryOnly(.{});
    const host_os = target_query.os_tag orelse builtin.target.os.tag;
    if (host_os == .macos) {
        const deployment_text = b.graph.environ_map.get("MACOSX_DEPLOYMENT_TARGET") orelse "13.0";
        var normalized_deployment = deployment_text;
        var deployment_buffer: [64]u8 = undefined;
        if (std.mem.count(u8, deployment_text, ".") == 1) {
            normalized_deployment = std.fmt.bufPrint(&deployment_buffer, "{s}.0", .{deployment_text}) catch
                @panic("MACOSX_DEPLOYMENT_TARGET is too long");
        }
        const deployment = std.SemanticVersion.parse(normalized_deployment) catch
            @panic("MACOSX_DEPLOYMENT_TARGET must be a semantic version such as 13.0");
        target_query.os_tag = .macos;
        target_query.os_version_min = .{ .semver = deployment };
        target_query.os_version_max = .{ .semver = deployment };
    }
    const target = b.resolveTargetQuery(target_query);
    if (host_os == .macos and b.sysroot == null) {
        // Prefer the caller's selected SDK. Otherwise ask Xcode's active
        // developer-directory selection, so Xcode installed outside
        // /Applications works without editing the build definition.
        if (b.graph.environ_map.get("SDKROOT")) |sdk_root| {
            b.sysroot = sdk_root;
        } else if (std.zig.system.darwin.getSdk(b.allocator, b.graph.io, &target.result)) |sdk_root| {
            b.sysroot = sdk_root;
        }
    }
    const macos_sdk_root = b.sysroot orelse "";
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
    const x86_trace_asm_module = b.createModule(.{
        .root_source_file = b.path("../src/x86-ASM/trace_test_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const trace_logger_module = b.createModule(.{
        .root_source_file = b.path("../src/tooling/disasm_logger/x86_trace_logger.zig"),
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
    // The shared code memory maps MAP_JIT pages through libc.
    arm64_encode_module.link_libc = true;
    const ppc_instruction_routing_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/PPC/console/runtime/instruction-routing/src/root.zig"),
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
    // The AppKit window geometry the Vulkan forwarder and the guest-ABI window
    // runtime both describe. One module so the two cannot drift on layout.
    const window_geometry_mod = b.createModule(.{
        .root_source_file = b.path("../lib/gpu/window_geometry.zig"),
        .target = target,
        .optimize = optimize,
    });
    // What a Vulkan command can put into the image it targets. The
    // presentation chain asks this before it calls a presented frame content,
    // so a frame built only from clears cannot read as a frame with a
    // picture in it.
    const frame_content_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/frame-content-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Final screen validity is a pure, fail-closed evaluation over the
    // forwarder's bounded snapshot. Keep it as a named module so the PE
    // processor and the native graphics path share the same verdict table.
    const screen_validity_mod = b.createModule(.{
        .root_source_file = b.path("../lib/gpu/screen_validity.zig"),
        .target = target,
        .optimize = optimize,
    });
    // What a guest address is when no symbol names it: the image the loader
    // mapped, a thunk Rosette synthesised, a block the guest allocated
    // executable and jumped into.
    const address_region_map_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/address-region-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
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
        .root_source_file = b.path("../pkg/common/console/ready-plan/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_ready_plan", xenia_ready_plan_mod);
    // The graphics handoff package is deliberately selected by the host ISA.
    // It contributes immutable ABI/ordering facts only; it cannot provide a
    // guest pointer, command buffer, or presentation event.
    const xenia_graphics_contract_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/console/graphics-contract/src/root.zig")
    else
        b.path("../pkg/x86/console/graphics-contract/src/root.zig");
    const xenia_graphics_contract_mod = b.createModule(.{
        .root_source_file = xenia_graphics_contract_root,
        .target = target,
        .optimize = optimize,
    });
    ready_compiler_mod.addImport("xenia_graphics_contract", xenia_graphics_contract_mod);

    // VdSwap/PM4 handoff facts are route-independent.  The live ledger is in
    // lib/gpu; this package owns only the immutable stage vocabulary, packet
    // shape and provenance rules shared by every host route.
    const xenia_vd_swap_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/vd-swap-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The disc image container's layout, and what a damaged region of one
    // costs. An offset alone cannot say whether a hole is fatal or merely
    // unfortunate; this is what tells them apart.
    const xenia_xiso_format_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/xiso-format/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Which subsystems an emulator image must contain for a run to be worth
    // starting. Read before the first guest instruction, so a build that could
    // never reach a frame is refused in milliseconds instead of minutes.
    const xenia_prelaunch_audit_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/prelaunch-audit-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Log lines whose presence means the run's outcome is already decided.
    const xenia_fatal_condition_map_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/fatal-condition-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    xenia_fatal_condition_map_mod.addImport("phrase_filter", phrase_filter_mod);

    // What a Xenia symbol name means, so a report can say what the guest is
    // doing at an address rather than only where it is.
    const xenia_guest_frontier_map_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/guest-frontier-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The Xenia functions whose first entry answers a question no counter of
    // Rosette's own surface can: whether the title ever produced a frame,
    // ever asked for a swap, ever registered an audio client.
    const xenia_guest_milestone_map_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/guest-milestone-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Xenia's own kernel export shims: `xe::kernel::xboxkrnl::VdSwap_entry`
    // and its 691 siblings. Entry into one is the translated PowerPC asking
    // the emulated kernel for something, which is the only event in the whole
    // program that proves the title acted.
    const xenia_kernel_shim_map_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/kernel-shim-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The console's own export ordinal tables, joined against the shims above
    // to say what this Xenia build does not implement.
    const xenia_kernel_export_map_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/kernel-export-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Fixed-address allocations used by Xenia's CPU thread contexts have a
    // documented candidate sequence. This package owns that address policy;
    // the ELF runtime owns the live backing and collision ledger.
    const xenia_guest_address_map_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/guest-address-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Whether a Xenia warning-level line is a finding at all.
    const xenia_warning_severity_map_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/warning-severity-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    xenia_warning_severity_map_mod.addImport("phrase_filter", phrase_filter_mod);

    // The host operations the emulator's behaviour rests on, and the
    // cross-subsystem orderings that break under translation. Both are
    // route-independent: they describe what a machine must do and what must
    // happen before what, neither of which changes with the host Rosette is
    // compiled for.
    const rosette_host_capability_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/host-capability-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Rosette owns the macOS/x86 host layout policy that Xenia used to keep
    // in x86brew-specific scripts. It is vocabulary only; probing and shell
    // setup remain at their respective edges.
    const rosette_macos_host_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/macos-host-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // What must be shown to work before the guest depends on it. Route-
    // independent: it names components and proof obligations, neither of which
    // changes with the host Rosette is compiled for.
    const rosette_component_readiness_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/component-readiness-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const rosette_mandatory_order_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/mandatory-order-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Which of several counters of the same increasing fact a report may
    // quote. Route-independent: it describes carriers and what each one can
    // be short of, neither of which changes with the host Rosette is compiled
    // for.
    const rosette_monotone_witness_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/monotone-witness-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The evidence ABI Rosette and Xenia both write and both read: fixed-width
    // records, one schema version, and enums whose numeric values mean the same
    // thing in both processes. Route-independent — it describes a wire format,
    // and a wire format that changed with the compiling host would defeat its
    // own purpose.
    const rosette_graphics_bridge_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/rosette-graphics-bridge/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The full graphics boundary surface: every function entry between a title
    // asking the kernel for a display and a frame reaching a host surface, with
    // its owner, its prerequisite and what an absence licenses a reader to
    // conclude. Route-independent — it describes the console and the emulator's
    // own symbol names, neither of which changes with the host Rosette is
    // compiled for.
    const xenia_gpu_bringup_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/gpu-bringup-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The GPU observation envelope is build-time data consumed by both the
    // earliest Rosette root and the live PM4 runtime. Keeping it as one module
    // prevents the ring limits and causal-boundary vocabulary from drifting
    // between diagnostics and execution.
    const xenia_gpu_observation_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/gpu-observation-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The common PM4 package already owns packet arithmetic/classification.
    // Make the GPU executor consume that same build-time table instead of
    // growing a second semantic vocabulary in lib.
    const xenia_pm4_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/pm4-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The complete graphics health schema is route-independent.  It owns the
    // immutable stage vocabulary and the alternative host/Vulkan/Xenos/VdSwap
    // paths; the mutable evidence ledger remains in lib/diagnostics.
    const xenia_graphics_health_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/graphics-health-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Application-control policy is also immutable and route-independent.  It
    // defines safe host directives and explicit no-fabrication invariants; the
    // runtime state machine lives in lib/diagnostics.
    const xenia_application_controller_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/application-controller-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Cocoa owns the native application/window/layer identities while SDL,
    // Vulkan, Xenia and Rosette borrow or transfer explicitly named resources.
    // Keeping this vocabulary route-independent prevents a successful host
    // diagnostic clear from being mistaken for a guest VdSwap.
    const cocoa_graphics_control_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/cocoa/graphics-control-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Rosette stands the window up before the guest runs, so a forwarding into
    // it is either one Rosette has semantics for or one nobody can account for.
    // Keeping the admission rule in a package means the fault policy is decided
    // by a pure function that can be tested without a window.
    const cocoa_window_admission_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/cocoa/window-admission-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The standards a run has to meet to be allowed to continue. Kept in a
    // package because the judgement has to be a pure function of stated
    // measurements: an invariant decided from live ledgers cannot be replayed,
    // and every one of these has to be reproducible without a window, a guest
    // or an emulator.
    const rosette_run_integrity_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/run-integrity-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Translation-cache ownership, geometry, mapping, and fail-fast cause
    // policy are one route-independent contract. Keeping it outside Mach-O
    // prevents lookup, invalidation, diagnostics, and future processor routes
    // from growing subtly different hash or refusal rules.
    const rosette_translation_cache_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/translation-cache-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Which side can answer for a boundary, and whether the two agree. An
    // armed tracepoint the application never reached is only a defect where
    // Rosette also has nothing to say about the same question.
    const rosette_substantiation_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/substantiation-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Every hosted process has one Rosette authority. Subsystem-specific
    // owners remain useful internal truths, but they are subordinate labels
    // in the hosting boundary and must be logged as `subowner` rather than
    // being mistaken for a second process owner.
    const rosette_ownership_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/rosette/ownership-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // What a Xenos texture format may be served by on a host that lacks it,
    // and what each substitution costs. Metal has no signed 2_10_10_10; the
    // question this answers is whether the emulator's fallback preserves the
    // values or reinterprets them.
    const xenia_texture_format_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/texture-format-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // rosette_root is the earliest framework seam: it exposes immutable GPU
    // facts before Mach-O state or a Xenia adapter is constructed. The roots
    // remain one-way (package -> root -> lib) so runtime state cannot leak back
    // into build-time assumptions.
    const rosette_gpu_root_mod = b.createModule(.{
        .root_source_file = b.path("../rosette_root/kernel/drivers/gpu/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    rosette_gpu_root_mod.addImport("xenia_gpu_observation_contract", xenia_gpu_observation_contract_mod);
    const rosette_root_mod = b.createModule(.{
        .root_source_file = b.path("../rosette_root/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    rosette_root_mod.addImport("rosette_gpu_root", rosette_gpu_root_mod);
    ready_compiler_mod.addImport("rosette_root", rosette_root_mod);

    // The application framework is deliberately application-generic rather
    // than Xenia-specific. Its package owns only the fixed C ABI/schema; the
    // bounded mutable ledger lives in lib/framework and is bound to the live
    // Mach-O process when an image runs.
    const application_framework_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/application-framework-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xenia_launch_assist_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/launch-assist-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xenia_host_gpu_callback_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/host-gpu-callback-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const application_framework_mod = b.createModule(.{
        .root_source_file = b.path("../lib/framework/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    application_framework_mod.addImport("application_framework_contract", application_framework_contract_mod);
    application_framework_mod.addImport("xenia_launch_assist_contract", xenia_launch_assist_contract_mod);
    application_framework_mod.addImport("xenia_host_gpu_callback_contract", xenia_host_gpu_callback_contract_mod);

    // Who owns a piece of console platform state, when they took it, and
    // whether the handoff between the harness and the emulator held. Console
    // facts, so route-independent like the contracts above.
    const xenia_provisioning_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/provisioning-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Which of several disagreeing statements about the same fact is current.
    // The emulator states the same facts from many code paths and never
    // retracts a snapshot, so the loudest claim in the log is not the truest.
    const xenia_claim_reconciliation_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/claim-reconciliation-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Xenia's PowerPC graphics callback and Rosette's model callback are
    // separate execution domains. This contract names the registration ->
    // dispatch -> return transaction without comparing their counters.
    const xenia_interrupt_callback_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/interrupt-callback-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // What a diagnostic transport may do to the program it observes. Not a
    // console fact, but a route-independent policy both the ring and any
    // offline analysis have to agree on.
    const diagnostics_async_log_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/diagnostics/async-log-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Whether translating a guest is a cost that ends or one that repeats.
    // Route-independent: the classifier is arithmetic over decode counts, not
    // a fact about any particular host.
    const abi_translation_economics_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/abi/translation-economics-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    abi_translation_economics_contract_mod.addImport(
        "rosette_translation_cache_contract",
        rosette_translation_cache_contract_mod,
    );

    // Delivering a queued GPU completion to a guest callback, and knowing how
    // much was assumed to do it. Console/ownership facts, route independent.
    const xenia_draw_dispatch_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/draw-dispatch-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Who waits on what, who signals it, and whether the handshake between
    // them is going anywhere. Console/ownership facts, route independent.
    const xenia_wait_graph_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/wait-graph-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Runtime wait results have several deliberately non-interchangeable
    // meanings. Keep the action policy in a package so the Mach-O scheduler,
    // wait graph, and future application routes cannot each invent a different
    // answer for timeouts, handshakes, or synthetic wakeups.
    const xenia_wait_handshake_policy_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/console/wait-handshake-policy/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Guest-endian facts are mirrored per host route and cross-checked below.
    // These are immutable source-derived values: the PPC guest word order is
    // identical on every route, while host codegen and host byte order remain
    // explicit route facts.
    const xenia_guest_endian_x86_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/x86/console/guest-endian/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xenia_guest_endian_arm64_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/ARM64/console/guest-endian/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xenia_guest_endian_ppc_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/PPC/console/guest-endian/src/root.zig"),
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
        b.path("../pkg/ARM64/console/graphics/surface-path-contract/src/root.zig")
    else
        b.path("../pkg/x86/console/graphics/surface-path-contract/src/root.zig");
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
        b.path("../pkg/ARM64/console/runtime/shader-storage-contract/src/root.zig")
    else
        b.path("../pkg/x86/console/runtime/shader-storage-contract/src/root.zig");
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
        b.path("../pkg/ARM64/console/runtime/launch-phase-map/src/root.zig")
    else
        b.path("../pkg/x86/console/runtime/launch-phase-map/src/root.zig");
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
        b.path("../pkg/ARM64/console/runtime/translation-progress/src/root.zig")
    else
        b.path("../pkg/x86/console/runtime/translation-progress/src/root.zig");
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
        b.path("../pkg/ARM64/console/memory/heap-range/src/root.zig")
    else
        b.path("../pkg/x86/console/memory/heap-range/src/root.zig");
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
        b.path("../pkg/ARM64/console/bridge/abi-bridge/src/root.zig")
    else
        b.path("../pkg/x86/console/bridge/abi-bridge/src/root.zig");
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
        b.path("../pkg/ARM64/console/runtime/guest-bridge/src/root.zig")
    else
        b.path("../pkg/x86/console/runtime/guest-bridge/src/root.zig");
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
        b.path("../pkg/ARM64/console/runtime/codegen-activation/src/root.zig")
    else
        b.path("../pkg/x86/console/runtime/codegen-activation/src/root.zig");
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
        b.path("../pkg/ARM64/console/runtime/wait-contract/src/root.zig")
    else
        b.path("../pkg/x86/console/runtime/wait-contract/src/root.zig");
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
    // the comptime cross-check in `lib/ready-compiler/guest.zig` fails the
    // build instead.
    const xenia_startup_evidence_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/console/diagnostics/startup-evidence/src/evidence.zig")
    else
        b.path("../pkg/x86/console/diagnostics/startup-evidence/src/evidence.zig");
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
        .root_source_file = b.path("../lib/diagnostics/guest_startup_evidence.zig"),
        .target = target,
        .optimize = optimize,
    });
    startup_evidence_runtime_mod.addImport("xenia_startup_evidence", xenia_startup_evidence_mod);
    ready_compiler_mod.addImport("startup_evidence_runtime", startup_evidence_runtime_mod);
    // Primitive dispatch is a Mach-O hot path. The package supplies only a
    // family lookup; the existing primitive handlers and fallback definitions
    // remain in charge of behavior.
    const xenia_primitive_contract_root = if (target.result.cpu.arch == .aarch64)
        b.path("../pkg/ARM64/console/runtime/primitive-contract/src/root.zig")
    else
        b.path("../pkg/x86/console/runtime/primitive-contract/src/root.zig");
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
    x86_trace_asm_module.addImport("runtime_abi_handshake", runtime_abi_module);
    x86_trace_asm_module.addImport("isa_registry", isa_module);
    x86_trace_asm_module.addImport("isa_highway", isa_highway_module);
    x86_trace_asm_module.addImport("entrypoint_code_text_segment", entrypoint_code_text_segment_module);
    x86_trace_asm_module.addImport("bridge_register_tracing", bridge_register_trace_module);
    x86_trace_asm_module.addImport("bridge_flags", bridge_flags_module);
    x86_trace_asm_module.addImport("bridge_string_ops", bridge_string_ops_module);
    x86_trace_asm_module.addImport("bridge_exceptions", bridge_exceptions_module);
    x86_trace_asm_module.addImport("cleo", cleo_module);
    trace_logger_module.addImport("x86_asm", x86_trace_asm_module);
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
    const source_budget = b.addSystemCommand(&.{ "python3", "tools/audit_source_size.py" });
    source_budget.setCwd(b.path(".."));
    check_step.dependOn(&source_budget.step);
    const startup_evidence_runtime_test = b.addTest(.{ .root_module = startup_evidence_runtime_mod });
    check_step.dependOn(&b.addRunArtifact(startup_evidence_runtime_test).step);
    const entrypoint_alignment_test = b.addTest(.{ .root_module = entrypoint_alignment_module });
    check_step.dependOn(&entrypoint_alignment_test.step);

    const zig_tests = b.addTest(.{
        .root_module = zig_module,
    });
    check_step.dependOn(&zig_tests.step);
    const application_framework_test = b.addTest(.{ .root_module = application_framework_mod });
    check_step.dependOn(&b.addRunArtifact(application_framework_test).step);
    const xenia_host_gpu_callback_contract_test = b.addTest(.{ .root_module = xenia_host_gpu_callback_contract_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_host_gpu_callback_contract_test).step);
    // The boundary surface is a `pub const` import inside lib/gpu, and a
    // `pub const @import` does not root a module's tests. Without its own test
    // target the contract's fifteen tests would compile and never run.
    const xenia_gpu_bringup_contract_test = b.addTest(.{ .root_module = xenia_gpu_bringup_contract_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_gpu_bringup_contract_test).step);
    const rosette_host_capability_contract_test = b.addTest(.{ .root_module = rosette_host_capability_contract_mod });
    check_step.dependOn(&b.addRunArtifact(rosette_host_capability_contract_test).step);
    const rosette_macos_host_contract_test = b.addTest(.{ .root_module = rosette_macos_host_contract_mod });
    check_step.dependOn(&b.addRunArtifact(rosette_macos_host_contract_test).step);
    const rosette_mandatory_order_contract_test = b.addTest(.{ .root_module = rosette_mandatory_order_contract_mod });
    check_step.dependOn(&b.addRunArtifact(rosette_mandatory_order_contract_test).step);
    const rosette_monotone_witness_contract_test = b.addTest(.{ .root_module = rosette_monotone_witness_contract_mod });
    check_step.dependOn(&b.addRunArtifact(rosette_monotone_witness_contract_test).step);
    const xenia_xiso_format_test = b.addTest(.{ .root_module = xenia_xiso_format_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_xiso_format_test).step);
    const xenia_prelaunch_audit_contract_test = b.addTest(.{ .root_module = xenia_prelaunch_audit_contract_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_prelaunch_audit_contract_test).step);
    const xenia_fatal_condition_map_test = b.addTest(.{ .root_module = xenia_fatal_condition_map_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_fatal_condition_map_test).step);
    const xenia_guest_address_map_test = b.addTest(.{ .root_module = xenia_guest_address_map_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_guest_address_map_test).step);
    const rosette_graphics_bridge_test = b.addTest(.{ .root_module = rosette_graphics_bridge_mod });
    check_step.dependOn(&b.addRunArtifact(rosette_graphics_bridge_test).step);
    const rosette_component_readiness_contract_test = b.addTest(.{ .root_module = rosette_component_readiness_contract_mod });
    check_step.dependOn(&b.addRunArtifact(rosette_component_readiness_contract_test).step);
    const xenia_host_gpu_callback_runtime_mod = b.createModule(.{
        .root_source_file = b.path("../lib/framework/guest_host_gpu_callback.zig"),
        .target = target,
        .optimize = optimize,
    });
    xenia_host_gpu_callback_runtime_mod.addImport("xenia_host_gpu_callback_contract", xenia_host_gpu_callback_contract_mod);
    const xenia_host_gpu_callback_runtime_test = b.addTest(.{ .root_module = xenia_host_gpu_callback_runtime_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_host_gpu_callback_runtime_test).step);

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
    @import("folders/include/abi.zig").register0(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/include/abi.zig").register1(b, .{
        .check_step = check_step,
        .runtime_abi_module = runtime_abi_module,
    });

    @import("folders/include/abi.zig").register2(b, .{
        .check_step = check_step,
        .entrypoint_stack_alignment_module = entrypoint_stack_alignment_module,
    });

    @import("folders/include/abi.zig").register3(b, .{
        .check_step = check_step,
        .entrypoint_shadow_stack_validation_module = entrypoint_shadow_stack_validation_module,
    });

    @import("folders/include/abi.zig").register4(b, .{
        .check_step = check_step,
        .isa_module = isa_module,
    });

    @import("folders/include/abi.zig").register5(b, .{
        .check_step = check_step,
        .svx_module = svx_module,
    });

    @import("folders/include/abi.zig").register6(b, .{
        .check_step = check_step,
        .cleo_module = cleo_module,
    });

    @import("folders/include/abi.zig").register7(b, .{
        .check_step = check_step,
        .contract_mod = contract_mod,
    });

    @import("folders/include/abi.zig").register8(b, .{
        .check_step = check_step,
        .jit_mod = jit_mod,
    });

    @import("folders/include/abi.zig").register9(b, .{
        .check_step = check_step,
        .ppc_decode_module = ppc_decode_module,
    });

    @import("folders/include/abi.zig").register10(b, .{
        .check_step = check_step,
        .ppc_runtime_module = ppc_runtime_module,
    });

    @import("folders/include/abi.zig").register11(b, .{
        .arm64_encode_module = arm64_encode_module,
        .check_step = check_step,
    });

    @import("folders/include/abi.zig").register12(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .target = target,
    });

    @import("folders/include/abi.zig").register13(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .ppc_decode_module = ppc_decode_module,
        .target = target,
    });

    @import("folders/include/abi.zig").register14(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/include/abi.zig").register15(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/include/abi.zig").register16(b, .{
        .bridge_dos_runtime_module = bridge_dos_runtime_module,
        .bridge_exceptions_module = bridge_exceptions_module,
        .bridge_flags_module = bridge_flags_module,
        .bridge_heap_module = bridge_heap_module,
        .bridge_instruction_decoding_module = bridge_instruction_decoding_module,
        .bridge_memory_module = bridge_memory_module,
        .bridge_register_trace_module = bridge_register_trace_module,
        .bridge_stack_module = bridge_stack_module,
        .bridge_string_ops_module = bridge_string_ops_module,
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/include/abi.zig").register17(b, .{
        .bridge_exceptions_module = bridge_exceptions_module,
        .bridge_flags_module = bridge_flags_module,
        .bridge_heap_module = bridge_heap_module,
        .bridge_instruction_decoding_module = bridge_instruction_decoding_module,
        .bridge_memory_module = bridge_memory_module,
        .bridge_register_trace_module = bridge_register_trace_module,
        .bridge_stack_module = bridge_stack_module,
        .bridge_string_ops_module = bridge_string_ops_module,
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/include/abi.zig").register18(b, .{
        .bridge_exceptions_module = bridge_exceptions_module,
        .bridge_flags_module = bridge_flags_module,
        .bridge_heap_module = bridge_heap_module,
        .bridge_instruction_decoding_module = bridge_instruction_decoding_module,
        .bridge_memory_module = bridge_memory_module,
        .bridge_register_trace_module = bridge_register_trace_module,
        .bridge_stack_module = bridge_stack_module,
        .bridge_string_ops_module = bridge_string_ops_module,
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/include/abi.zig").register19(b, .{
        .arm64_exceptions_module = arm64_exceptions_module,
        .bridge_exceptions_module = bridge_exceptions_module,
        .bridge_flags_module = bridge_flags_module,
        .bridge_heap_module = bridge_heap_module,
        .bridge_instruction_decoding_module = bridge_instruction_decoding_module,
        .bridge_memory_module = bridge_memory_module,
        .bridge_register_trace_module = bridge_register_trace_module,
        .bridge_stack_module = bridge_stack_module,
        .bridge_string_ops_module = bridge_string_ops_module,
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    // Standalone assembler Zig module tests
    @import("folders/lib/assembler.zig").register0(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register1(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register2(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register3(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    // Assembler ABI handshake modules
    @import("folders/lib/assembler.zig").register4(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register5(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register6(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register7(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register8(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register9(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register10(b, .{
        .check_step = check_step,
        .entrypoint_kernel_process_guard_module = entrypoint_kernel_process_guard_module,
        .exit_diagnostics_module = exit_diagnostics_module,
        .optimize = optimize,
        .target = target,
    });

    @import("folders/lib/assembler.zig").register11(b, .{
        .dll_unpacker_module = dll_unpacker_module,
    });

    @import("folders/lib/assembler.zig").register12(b, .{
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .target = target,
    });

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
        .filters = &.{ "SETcc uses the ModRM r/m field for AH versus SPL", "LOCK prefix survives" },
    });
    const run_setcc_stack_regression_test = b.addRunArtifact(setcc_stack_regression_test);
    const decoder_family_check_step = b.step(
        "decoder-family-check",
        "Run the focused stack and reference-count decoder regressions",
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

    // EVEX execution is shared by the Mach-O and ELF interpreters. Keep it as
    // a small standalone module so the ELF processor does not reach outside
    // its module root with a relative import.
    const evex_runtime_mod = b.createModule(.{
        .root_source_file = b.path("../lib/runtime/process-core/evex.zig"),
        .target = target,
        .optimize = optimize,
    });
    evex_runtime_mod.addImport("x64_decoder", x64_decoder_mod);
    evex_runtime_mod.addImport("exit_diagnostics", exit_diagnostics_module);

    // Shared scalar/packed VEX helpers are backend-agnostic and are also
    // used by the PE64/ELF executor. Keeping this as a separate module avoids
    // making the Windows path depend on the Mach-O processor itself.
    const x86_vector_helpers_mod = b.createModule(.{
        .root_source_file = b.path("../lib/Mach-O/execution_helpers.zig"),
        .target = target,
        .optimize = optimize,
    });
    x86_vector_helpers_mod.addImport("x64_decoder", x64_decoder_mod);

    // The Windows import boundary's static facts. The return contract says
    // what a name's ABI defines for a refusal; the library inventory says
    // which DLLs are the Windows surface; and one package per DLL owns the
    // degraded names. The catalogue only links those facts for the runtime.
    // What a declined Windows DLL would have to gain before Rosette could
    // serve it, and what the guest loses meanwhile.
    const dll_win32_capability_gap_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/dll/win32/capability-gap/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The shape every per-DLL package uses to declare one export: its arity,
    // the convention its return value follows, and what Rosette does about it.
    const dll_win32_export_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/dll/win32/export-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dll_win32_catalogue_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/dll/win32/catalogue/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dll_win32_package_specs = [_]struct {
        import_name: []const u8,
        root_source_file: []const u8,
    }{
        .{ .import_name = "dll_win32_advapi32", .root_source_file = "../pkg/dll/win32/advapi32/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_convert_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-convert-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_environment_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-environment-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_filesystem_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-filesystem-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_heap_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-heap-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_locale_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-locale-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_math_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-math-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_private_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-private-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_runtime_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-runtime-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_stdio_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-stdio-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_string_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-string-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_time_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-time-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_utility_l1_1_0", .root_source_file = "../pkg/dll/win32/api-ms-win-crt-utility-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_bcrypt", .root_source_file = "../pkg/dll/win32/bcrypt/src/root.zig" },
        .{ .import_name = "dll_win32_cfgmgr32", .root_source_file = "../pkg/dll/win32/cfgmgr32/src/root.zig" },
        .{ .import_name = "dll_win32_dwmapi", .root_source_file = "../pkg/dll/win32/dwmapi/src/root.zig" },
        .{ .import_name = "dll_win32_dxgi", .root_source_file = "../pkg/dll/win32/dxgi/src/root.zig" },
        .{ .import_name = "dll_win32_vulkan_1", .root_source_file = "../pkg/dll/win32/vulkan-1/src/root.zig" },
        .{ .import_name = "dll_win32_dynamic", .root_source_file = "../pkg/dll/win32/dynamic/src/root.zig" },
        .{ .import_name = "dll_win32_gdi32", .root_source_file = "../pkg/dll/win32/gdi32/src/root.zig" },
        .{ .import_name = "dll_win32_hid", .root_source_file = "../pkg/dll/win32/hid/src/root.zig" },
        .{ .import_name = "dll_win32_imm32", .root_source_file = "../pkg/dll/win32/imm32/src/root.zig" },
        .{ .import_name = "dll_win32_libusbk", .root_source_file = "../pkg/dll/win32/libusbk/src/root.zig" },
        .{ .import_name = "dll_win32_kernel32", .root_source_file = "../pkg/dll/win32/kernel32/src/root.zig" },
        .{ .import_name = "dll_win32_msvcrt", .root_source_file = "../pkg/dll/win32/msvcrt/src/root.zig" },
        .{ .import_name = "dll_win32_ole32", .root_source_file = "../pkg/dll/win32/ole32/src/root.zig" },
        .{ .import_name = "dll_win32_oleaut32", .root_source_file = "../pkg/dll/win32/oleaut32/src/root.zig" },
        .{ .import_name = "dll_win32_setupapi", .root_source_file = "../pkg/dll/win32/setupapi/src/root.zig" },
        .{ .import_name = "dll_win32_shcore", .root_source_file = "../pkg/dll/win32/shcore/src/root.zig" },
        .{ .import_name = "dll_win32_shell32", .root_source_file = "../pkg/dll/win32/shell32/src/root.zig" },
        .{ .import_name = "dll_win32_shlwapi", .root_source_file = "../pkg/dll/win32/shlwapi/src/root.zig" },
        .{ .import_name = "dll_win32_user32", .root_source_file = "../pkg/dll/win32/user32/src/root.zig" },
        .{ .import_name = "dll_win32_version", .root_source_file = "../pkg/dll/win32/version/src/root.zig" },
        .{ .import_name = "dll_win32_winmm", .root_source_file = "../pkg/dll/win32/winmm/src/root.zig" },
        .{ .import_name = "dll_win32_winusb", .root_source_file = "../pkg/dll/win32/winusb/src/root.zig" },
        .{ .import_name = "dll_win32_wsock32", .root_source_file = "../pkg/dll/win32/wsock32/src/root.zig" },
    };
    for (dll_win32_package_specs) |spec| {
        const package_mod = b.createModule(.{
            .root_source_file = b.path(spec.root_source_file),
            .target = target,
            .optimize = optimize,
        });
        package_mod.addImport("dll_win32_export_contract", dll_win32_export_contract_mod);
        dll_win32_catalogue_mod.addImport(spec.import_name, package_mod);
        const package_test = b.addTest(.{ .root_module = package_mod });
        check_step.dependOn(&b.addRunArtifact(package_test).step);
    }
    const dll_win32_catalogue_test = b.addTest(.{ .root_module = dll_win32_catalogue_mod });
    check_step.dependOn(&b.addRunArtifact(dll_win32_catalogue_test).step);

    const dll_win32_return_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/dll/win32/return-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dll_win32_library_inventory_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/dll/win32/library-inventory/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    dll_win32_catalogue_mod.addImport("dll_win32_export_contract", dll_win32_export_contract_mod);
    dll_win32_library_inventory_mod.addImport("dll_win32_catalogue", dll_win32_catalogue_mod);
    dll_win32_library_inventory_mod.addImport("dll_win32_capability_gap", dll_win32_capability_gap_mod);
    const dll_win32_capability_gap_test = b.addTest(.{ .root_module = dll_win32_capability_gap_mod });
    check_step.dependOn(&b.addRunArtifact(dll_win32_capability_gap_test).step);
    const dll_win32_export_contract_test = b.addTest(.{ .root_module = dll_win32_export_contract_mod });
    check_step.dependOn(&b.addRunArtifact(dll_win32_export_contract_test).step);
    // The export contract borrows the return contract's convention vocabulary
    // rather than declaring a second one, so the two halves of a refusal - the
    // value chosen and the value judged - can never disagree.
    dll_win32_export_contract_mod.addImport("dll_win32_return_contract", dll_win32_return_contract_mod);
    const dll_win32_return_contract_test = b.addTest(.{ .root_module = dll_win32_return_contract_mod });
    check_step.dependOn(&b.addRunArtifact(dll_win32_return_contract_test).step);
    const dll_win32_library_inventory_test = b.addTest(.{ .root_module = dll_win32_library_inventory_mod });
    check_step.dependOn(&b.addRunArtifact(dll_win32_library_inventory_test).step);

    const tso_memory_mod = b.createModule(.{
        .root_source_file = b.path("../lib/processor/ELF_processor/tso_memory.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The guest memory model's own suite: the store buffer, the stripe
    // coordinator and the boundary ledger. It was wired only as an import,
    // so none of its tests ever ran.
    const tso_memory_test = b.addTest(.{ .root_module = tso_memory_mod });
    check_step.dependOn(&b.addRunArtifact(tso_memory_test).step);
    // Parallel TSO litmus/stress suite. Keeping the runner separate allows
    // the tests to exercise the public memory API without creating an import
    // cycle from tso_memory.zig back into its own test module.
    const tso_litmus_mod = b.createModule(.{
        .root_source_file = b.path("../lib/processor/ELF_processor/tso/litmus.zig"),
        .target = target,
        .optimize = optimize,
    });
    tso_litmus_mod.addImport("tso_memory", tso_memory_mod);
    const tso_litmus_test = b.addTest(.{ .root_module = tso_litmus_mod });
    check_step.dependOn(&b.addRunArtifact(tso_litmus_test).step);
    // Host-thread concurrency: futex parking, the stop-the-world gate, the
    // main-thread service hook and the stall watchdog the PE executor's
    // guest threads coordinate through.
    const concurrency_mod = b.createModule(.{
        .root_source_file = b.path("../lib/concurrency/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const concurrency_test = b.addTest(.{ .root_module = concurrency_mod });
    check_step.dependOn(&b.addRunArtifact(concurrency_test).step);
    // Parallel guest execution is a processor-level package layered on top
    // of host synchronization. Its executor, guest gate, message handoff,
    // and atomic metrics are compiled and tested as one boundary.
    const parallelism_mod = b.createModule(.{
        .root_source_file = b.path("../lib/processor/ELF_processor/parallelism/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    parallelism_mod.addImport("concurrency", concurrency_mod);
    const parallelism_test = b.addTest(.{ .root_module = parallelism_mod });
    check_step.dependOn(&b.addRunArtifact(parallelism_test).step);
    const utf8_codec_mod = b.createModule(.{
        .root_source_file = b.path("../lib/text/utf8/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const utf8_codec_test = b.addTest(.{ .root_module = utf8_codec_mod });
    check_step.dependOn(&b.addRunArtifact(utf8_codec_test).step);
    const windows_runtime_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/windows_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_bsearch_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/windows_bsearch.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_runtime_mod.addImport("windows_bsearch", windows_bsearch_mod);
    windows_runtime_mod.addImport("tso_memory", tso_memory_mod);
    windows_runtime_mod.addImport("utf8_codec", utf8_codec_mod);
    windows_runtime_mod.addImport("dll_win32_return_contract", dll_win32_return_contract_mod);
    windows_runtime_mod.addImport("dll_win32_library_inventory", dll_win32_library_inventory_mod);
    // The Win32 ABI surface owns the import classification and the fallback
    // return contract.  It was previously only compiled as a dependency of
    // other modules, so its own tests never ran and a wrong classification
    // could reach a run unchallenged.
    const windows_runtime_test = b.addTest(.{ .root_module = windows_runtime_mod });
    check_step.dependOn(&b.addRunArtifact(windows_runtime_test).step);
    const crt_math_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/windows_runtime/crt_math.zig"),
        .target = target,
        .optimize = optimize,
    });
    const crt_math_test = b.addTest(.{ .root_module = crt_math_mod });
    check_step.dependOn(&b.addRunArtifact(crt_math_test).step);
    const crt_time_mod = b.createModule(.{
        .root_source_file = b.path("../src/x64-ASM/windows_runtime/crt_time.zig"),
        .target = target,
        .optimize = optimize,
    });
    const crt_time_test = b.addTest(.{ .root_module = crt_time_mod });
    check_step.dependOn(&b.addRunArtifact(crt_time_test).step);

    var windows_graphics_state_test_mod: *std.Build.Module = undefined;
    // ELF processor (x86-64 ELF binary loader/emulator)
    @import("folders/lib/processor.zig").register0(b, .{
        .address_region_map_mod = address_region_map_mod,
        .arm64_encode_module = arm64_encode_module,
        .check_step = check_step,
        .cleo_routing_mod = cleo_routing_mod,
        .concurrency_mod = concurrency_mod,
        .concurrency_test = concurrency_test,
        .evex_runtime_mod = evex_runtime_mod,
        .execution_history_mod = execution_history_mod,
        .exit_diagnostics_module = exit_diagnostics_module,
        .frame_content_contract_mod = frame_content_contract_mod,
        .optimize = optimize,
        .parallelism_mod = parallelism_mod,
        .run_setcc_stack_regression_test = run_setcc_stack_regression_test,
        .screen_validity_mod = screen_validity_mod,
        .target = target,
        .tso_memory_mod = tso_memory_mod,
        .tso_memory_test = tso_memory_test,
        .windows_graphics_state_test_mod = &windows_graphics_state_test_mod,
        .windows_runtime_mod = windows_runtime_mod,
        .windows_runtime_test = windows_runtime_test,
        .x64_decoder_mod = x64_decoder_mod,
        .x64_interpreter_mod = x64_interpreter_mod,
        .x86_vector_helpers_mod = x86_vector_helpers_mod,
        .xenia_fatal_condition_map_mod = xenia_fatal_condition_map_mod,
        .xenia_guest_address_map_mod = xenia_guest_address_map_mod,
        .xenia_guest_frontier_map_mod = xenia_guest_frontier_map_mod,
        .xenia_guest_milestone_map_mod = xenia_guest_milestone_map_mod,
        .xenia_kernel_export_map_mod = xenia_kernel_export_map_mod,
        .xenia_kernel_shim_map_mod = xenia_kernel_shim_map_mod,
        .xenia_warning_severity_map_mod = xenia_warning_severity_map_mod,
    });

    // Console subsystem libraries: audio, HID, config, and the three GPU
    // subdirectories. Each satisfies a pkg contract and is tested against it
    // here, so a contract edit that the implementation does not follow fails
    // the gate rather than surfacing as silence, a dead controller, or a
    // wrong-looking frame.
    @import("folders/lib/graphics.zig").register0(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .target = target,
        .xenia_texture_format_contract_mod = xenia_texture_format_contract_mod,
    });

    // TOML processor (patch file format parser)
    @import("folders/lib/graphics.zig").register1(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .target = target,
    });

    // PS1 processor (PowerShell .ps1 → POSIX shell/Makefile translator)
    @import("folders/lib/graphics.zig").register2(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .target = target,
    });

    // Mach-O processor (x86_64 macOS binary loader/diagnostic backend)
    @import("folders/lib/runtime.zig").register0(b, .{
        .abi_translation_economics_contract_mod = abi_translation_economics_contract_mod,
        .address_region_map_mod = address_region_map_mod,
        .application_framework_contract_mod = application_framework_contract_mod,
        .application_framework_mod = application_framework_mod,
        .bridge_dos_runtime_module = bridge_dos_runtime_module,
        .bridge_exceptions_module = bridge_exceptions_module,
        .bridge_memory_module = bridge_memory_module,
        .bridge_register_trace_module = bridge_register_trace_module,
        .bridge_stack_module = bridge_stack_module,
        .check_step = check_step,
        .cleo_routing_mod = cleo_routing_mod,
        .cocoa_graphics_control_contract_mod = cocoa_graphics_control_contract_mod,
        .cocoa_window_admission_contract_mod = cocoa_window_admission_contract_mod,
        .contract_mod = contract_mod,
        .diagnostics_async_log_contract_mod = diagnostics_async_log_contract_mod,
        .dll_win32_catalogue_mod = dll_win32_catalogue_mod,
        .dxbc_arm64_mod = dxbc_arm64_mod,
        .dxbc_ppc_mod = dxbc_ppc_mod,
        .dxbc_x86_mod = dxbc_x86_mod,
        .endianness_arm64_mod = endianness_arm64_mod,
        .endianness_ppc_mod = endianness_ppc_mod,
        .endianness_x86_mod = endianness_x86_mod,
        .entrypoint_alignment_module = entrypoint_alignment_module,
        .entrypoint_kernel_process_guard_module = entrypoint_kernel_process_guard_module,
        .evex_runtime_mod = evex_runtime_mod,
        .execution_history_mod = execution_history_mod,
        .exit_diagnostics_module = exit_diagnostics_module,
        .frame_content_contract_mod = frame_content_contract_mod,
        .half_arm64_mod = half_arm64_mod,
        .half_ppc_mod = half_ppc_mod,
        .half_x86_mod = half_x86_mod,
        .is_macos = is_macos,
        .jit_mod = jit_mod,
        .libcpp_thread_abi_mod = libcpp_thread_abi_mod,
        .macos_sdk_root = macos_sdk_root,
        .optimize = optimize,
        .phrase_filter_mod = phrase_filter_mod,
        .ppc_runtime_module = ppc_runtime_module,
        .ready_compiler_mod = ready_compiler_mod,
        .rosette_component_readiness_contract_mod = rosette_component_readiness_contract_mod,
        .rosette_graphics_bridge_mod = rosette_graphics_bridge_mod,
        .rosette_host_capability_contract_mod = rosette_host_capability_contract_mod,
        .rosette_macos_host_contract_mod = rosette_macos_host_contract_mod,
        .rosette_mandatory_order_contract_mod = rosette_mandatory_order_contract_mod,
        .rosette_monotone_witness_contract_mod = rosette_monotone_witness_contract_mod,
        .rosette_ownership_contract_mod = rosette_ownership_contract_mod,
        .rosette_root_mod = rosette_root_mod,
        .rosette_run_integrity_contract_mod = rosette_run_integrity_contract_mod,
        .rosette_substantiation_contract_mod = rosette_substantiation_contract_mod,
        .rosette_translation_cache_contract_mod = rosette_translation_cache_contract_mod,
        .runtime_abi_module = runtime_abi_module,
        .screen_validity_mod = screen_validity_mod,
        .sha1_tracer_mod = sha1_tracer_mod,
        .sha_arm64_mod = sha_arm64_mod,
        .sha_ppc_mod = sha_ppc_mod,
        .sha_x86_mod = sha_x86_mod,
        .target = target,
        .trace_logger_module = trace_logger_module,
        .window_geometry_mod = window_geometry_mod,
        .windows_graphics_state_test_mod = windows_graphics_state_test_mod,
        .x64_decoder_mod = x64_decoder_mod,
        .x64_interpreter_mod = x64_interpreter_mod,
        .x86_asm_module = x86_asm_module,
        .x86_trace_asm_module = x86_trace_asm_module,
        .xenia_application_controller_contract_mod = xenia_application_controller_contract_mod,
        .xenia_claim_reconciliation_contract_mod = xenia_claim_reconciliation_contract_mod,
        .xenia_draw_dispatch_contract_mod = xenia_draw_dispatch_contract_mod,
        .xenia_fatal_condition_map_mod = xenia_fatal_condition_map_mod,
        .xenia_gpu_bringup_contract_mod = xenia_gpu_bringup_contract_mod,
        .xenia_gpu_observation_contract_mod = xenia_gpu_observation_contract_mod,
        .xenia_graphics_contract_mod = xenia_graphics_contract_mod,
        .xenia_graphics_health_contract_mod = xenia_graphics_health_contract_mod,
        .xenia_guest_endian_arm64_mod = xenia_guest_endian_arm64_mod,
        .xenia_guest_endian_ppc_mod = xenia_guest_endian_ppc_mod,
        .xenia_guest_endian_x86_mod = xenia_guest_endian_x86_mod,
        .xenia_heap_range_mod = xenia_heap_range_mod,
        .xenia_host_gpu_callback_contract_mod = xenia_host_gpu_callback_contract_mod,
        .xenia_interrupt_callback_contract_mod = xenia_interrupt_callback_contract_mod,
        .xenia_kernel_export_map_mod = xenia_kernel_export_map_mod,
        .xenia_launch_assist_contract_mod = xenia_launch_assist_contract_mod,
        .xenia_pm4_contract_mod = xenia_pm4_contract_mod,
        .xenia_prelaunch_audit_contract_mod = xenia_prelaunch_audit_contract_mod,
        .xenia_primitive_contract_mod = xenia_primitive_contract_mod,
        .xenia_provisioning_contract_mod = xenia_provisioning_contract_mod,
        .xenia_shader_storage_contract_mod = xenia_shader_storage_contract_mod,
        .xenia_surface_path_contract_mod = xenia_surface_path_contract_mod,
        .xenia_texture_format_contract_mod = xenia_texture_format_contract_mod,
        .xenia_vd_swap_contract_mod = xenia_vd_swap_contract_mod,
        .xenia_wait_graph_contract_mod = xenia_wait_graph_contract_mod,
        .xenia_wait_handshake_policy_mod = xenia_wait_handshake_policy_mod,
        .xenia_xiso_format_mod = xenia_xiso_format_mod,
    });

    // Aggregate Win32 ABI handshake suite
    @import("folders/include/abi.zig").register20(b, .{
        .behavior_module = behavior_module,
        .behavior_zig_module = behavior_zig_module,
        .check_step = check_step,
        .dll_translator_module = dll_translator_module,
        .dos_palette_module = dos_palette_module,
        .dos_platform_module = dos_platform_module,
        .dos_renderer_module = dos_renderer_module,
        .dos_scene_module = dos_scene_module,
        .is_macos = is_macos,
        .mmsystem_module = mmsystem_module,
        .optimize = optimize,
        .runtime_abi_module = runtime_abi_module,
        .shim_surface_module = shim_surface_module,
        .sysdefs_module = sysdefs_module,
        .target = target,
        .win32_all_module = win32_all_module,
        .win32_pending_module = win32_pending_module,
        .windows_base_module = windows_base_module,
        .x86_asm_module = x86_asm_module,
    });

    @import("folders/lib/runtime.zig").register1(b, .{
        .check_step = check_step,
        .dll_translator_module = dll_translator_module,
    });

    @import("folders/lib/runtime.zig").register2(b, .{
        .check_step = check_step,
        .dyld_cache_tree_module = dyld_cache_tree_module,
    });

    @import("folders/lib/runtime.zig").register3(b, .{
        .check_step = check_step,
        .pseudo_kernel_cache_module = pseudo_kernel_cache_module,
    });

    @import("folders/lib/runtime.zig").register4(b, .{
        .check_step = check_step,
        .pseudo_kernel_code_cache_table_module = pseudo_kernel_code_cache_table_module,
    });

    @import("folders/src/tooling.zig").register0(b, .{
        .check_step = check_step,
        .optimize = optimize,
        .target = target,
    });

    const lib = b.addLibrary(.{
        .name = "rosette_zig",
        .linkage = .static,
        .root_module = zig_module,
    });
    b.installArtifact(lib);
}
