//! Folder-owned build registration. Paths use the master build root.
const std = @import("std");
const builtin = @import("builtin");

pub fn register0(b: *std.Build, ctx: anytype) void {
    const abi_translation_economics_contract_mod = ctx.abi_translation_economics_contract_mod;
    const address_region_map_mod = ctx.address_region_map_mod;
    const application_framework_contract_mod = ctx.application_framework_contract_mod;
    const application_framework_mod = ctx.application_framework_mod;
    const bridge_dos_runtime_module = ctx.bridge_dos_runtime_module;
    const bridge_exceptions_module = ctx.bridge_exceptions_module;
    const bridge_memory_module = ctx.bridge_memory_module;
    const bridge_register_trace_module = ctx.bridge_register_trace_module;
    const bridge_stack_module = ctx.bridge_stack_module;
    const check_step = ctx.check_step;
    const cleo_routing_mod = ctx.cleo_routing_mod;
    const cocoa_graphics_control_contract_mod = ctx.cocoa_graphics_control_contract_mod;
    const cocoa_window_admission_contract_mod = ctx.cocoa_window_admission_contract_mod;
    const contract_mod = ctx.contract_mod;
    const diagnostics_async_log_contract_mod = ctx.diagnostics_async_log_contract_mod;
    const dll_win32_catalogue_mod = ctx.dll_win32_catalogue_mod;
    const dxbc_arm64_mod = ctx.dxbc_arm64_mod;
    const dxbc_ppc_mod = ctx.dxbc_ppc_mod;
    const dxbc_x86_mod = ctx.dxbc_x86_mod;
    const endianness_arm64_mod = ctx.endianness_arm64_mod;
    const endianness_ppc_mod = ctx.endianness_ppc_mod;
    const endianness_x86_mod = ctx.endianness_x86_mod;
    const entrypoint_alignment_module = ctx.entrypoint_alignment_module;
    const entrypoint_kernel_process_guard_module = ctx.entrypoint_kernel_process_guard_module;
    const evex_runtime_mod = ctx.evex_runtime_mod;
    const execution_history_mod = ctx.execution_history_mod;
    const exit_diagnostics_module = ctx.exit_diagnostics_module;
    const frame_content_contract_mod = ctx.frame_content_contract_mod;
    const half_arm64_mod = ctx.half_arm64_mod;
    const half_ppc_mod = ctx.half_ppc_mod;
    const half_x86_mod = ctx.half_x86_mod;
    const is_macos = ctx.is_macos;
    const jit_mod = ctx.jit_mod;
    const libcpp_thread_abi_mod = ctx.libcpp_thread_abi_mod;
    const macos_sdk_root = ctx.macos_sdk_root;
    const optimize = ctx.optimize;
    const phrase_filter_mod = ctx.phrase_filter_mod;
    const ppc_runtime_module = ctx.ppc_runtime_module;
    const ready_compiler_mod = ctx.ready_compiler_mod;
    const rosette_component_readiness_contract_mod = ctx.rosette_component_readiness_contract_mod;
    const rosette_graphics_bridge_mod = ctx.rosette_graphics_bridge_mod;
    const rosette_host_capability_contract_mod = ctx.rosette_host_capability_contract_mod;
    const rosette_macos_host_contract_mod = ctx.rosette_macos_host_contract_mod;
    const rosette_mandatory_order_contract_mod = ctx.rosette_mandatory_order_contract_mod;
    const rosette_monotone_witness_contract_mod = ctx.rosette_monotone_witness_contract_mod;
    const rosette_ownership_contract_mod = ctx.rosette_ownership_contract_mod;
    const rosette_root_mod = ctx.rosette_root_mod;
    const rosette_run_integrity_contract_mod = ctx.rosette_run_integrity_contract_mod;
    const rosette_substantiation_contract_mod = ctx.rosette_substantiation_contract_mod;
    const rosette_translation_cache_contract_mod = ctx.rosette_translation_cache_contract_mod;
    const runtime_abi_module = ctx.runtime_abi_module;
    const screen_validity_mod = ctx.screen_validity_mod;
    const sha1_tracer_mod = ctx.sha1_tracer_mod;
    const sha_arm64_mod = ctx.sha_arm64_mod;
    const sha_ppc_mod = ctx.sha_ppc_mod;
    const sha_x86_mod = ctx.sha_x86_mod;
    const target = ctx.target;
    const trace_logger_module = ctx.trace_logger_module;
    const window_geometry_mod = ctx.window_geometry_mod;
    const windows_graphics_state_test_mod = ctx.windows_graphics_state_test_mod;
    const x64_decoder_mod = ctx.x64_decoder_mod;
    const x64_interpreter_mod = ctx.x64_interpreter_mod;
    const x86_asm_module = ctx.x86_asm_module;
    const x86_trace_asm_module = ctx.x86_trace_asm_module;
    const xenia_application_controller_contract_mod = ctx.xenia_application_controller_contract_mod;
    const xenia_claim_reconciliation_contract_mod = ctx.xenia_claim_reconciliation_contract_mod;
    const xenia_draw_dispatch_contract_mod = ctx.xenia_draw_dispatch_contract_mod;
    const xenia_fatal_condition_map_mod = ctx.xenia_fatal_condition_map_mod;
    const xenia_gpu_bringup_contract_mod = ctx.xenia_gpu_bringup_contract_mod;
    const xenia_gpu_observation_contract_mod = ctx.xenia_gpu_observation_contract_mod;
    const xenia_graphics_contract_mod = ctx.xenia_graphics_contract_mod;
    const xenia_graphics_health_contract_mod = ctx.xenia_graphics_health_contract_mod;
    const xenia_guest_endian_arm64_mod = ctx.xenia_guest_endian_arm64_mod;
    const xenia_guest_endian_ppc_mod = ctx.xenia_guest_endian_ppc_mod;
    const xenia_guest_endian_x86_mod = ctx.xenia_guest_endian_x86_mod;
    const xenia_heap_range_mod = ctx.xenia_heap_range_mod;
    const xenia_host_gpu_callback_contract_mod = ctx.xenia_host_gpu_callback_contract_mod;
    const xenia_interrupt_callback_contract_mod = ctx.xenia_interrupt_callback_contract_mod;
    const xenia_kernel_export_map_mod = ctx.xenia_kernel_export_map_mod;
    const xenia_launch_assist_contract_mod = ctx.xenia_launch_assist_contract_mod;
    const xenia_pm4_contract_mod = ctx.xenia_pm4_contract_mod;
    const xenia_prelaunch_audit_contract_mod = ctx.xenia_prelaunch_audit_contract_mod;
    const xenia_primitive_contract_mod = ctx.xenia_primitive_contract_mod;
    const xenia_provisioning_contract_mod = ctx.xenia_provisioning_contract_mod;
    const xenia_shader_storage_contract_mod = ctx.xenia_shader_storage_contract_mod;
    const xenia_surface_path_contract_mod = ctx.xenia_surface_path_contract_mod;
    const xenia_texture_format_contract_mod = ctx.xenia_texture_format_contract_mod;
    const xenia_vd_swap_contract_mod = ctx.xenia_vd_swap_contract_mod;
    const xenia_wait_graph_contract_mod = ctx.xenia_wait_graph_contract_mod;
    const xenia_wait_handshake_policy_mod = ctx.xenia_wait_handshake_policy_mod;
    const xenia_xiso_format_mod = ctx.xenia_xiso_format_mod;

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
        // The host-capability probes call mmap, mprotect, nanosleep and
        // pthread directly. They have to: the question they answer is what
        // the kernel does, and anything that went through a portable
        // wrapper would be measuring the wrapper.
        .link_libc = true,
    });
    preflight_mod.addImport("xenia_prelaunch_audit_contract", xenia_prelaunch_audit_contract_mod);
    preflight_mod.addImport("xenia_gpu_bringup_contract", xenia_gpu_bringup_contract_mod);
    preflight_mod.addImport("xenia_graphics_health_contract", xenia_graphics_health_contract_mod);
    preflight_mod.addImport("rosette_host_capability_contract", rosette_host_capability_contract_mod);
    preflight_mod.addImport("rosette_component_readiness_contract", rosette_component_readiness_contract_mod);
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
        // Console-hardware and kernel-ABI contracts. Route-independent for
        // the same reason register-map is: they describe the Xbox 360 and
        // its kernel, not the host Rosette was compiled for.
        "../pkg/common/xenia/audio-contract/src/root.zig",
        "../pkg/common/xenia/input-contract/src/root.zig",
        "../pkg/common/xenia/user-contract/src/root.zig",
        "../pkg/common/xenia/config-schema/src/root.zig",
        "../pkg/common/xenia/shader-contract/src/root.zig",
        "../pkg/common/xenia/render-target-contract/src/root.zig",
        "../pkg/common/xenia/texture-contract/src/root.zig",
        "../pkg/common/xenia/io-completion-contract/src/root.zig",
        "../pkg/common/xenia/timer-contract/src/root.zig",
        "../pkg/common/xenia/ob-contract/src/root.zig",
        "../pkg/common/xenia/mount-contract/src/root.zig",
        "../pkg/common/xenia/kernel-object-contract/src/root.zig",
        // Facts transcribed from Xenia's own tables and headers. They
        // describe the console and its kernel, so they are route
        // independent like the rest of this list.
        "../pkg/common/xenia/kernel-export-map/src/root.zig",
        "../pkg/common/xenia/kernel-shim-map/src/root.zig",
        "../pkg/common/xenia/vd-ring-contract/src/root.zig",
        "../pkg/common/xenia/vd-swap-contract/src/root.zig",
        "../pkg/common/xenia/provisioning-contract/src/root.zig",
        "../pkg/common/xenia/claim-reconciliation-contract/src/root.zig",
        "../pkg/common/diagnostics/async-log-contract/src/root.zig",
        "../pkg/common/abi/translation-economics-contract/src/root.zig",
        "../pkg/common/rosette/translation-cache-contract/src/root.zig",
        "../pkg/common/xenia/draw-dispatch-contract/src/root.zig",
        "../pkg/common/xenia/wait-graph-contract/src/root.zig",
        "../pkg/common/xenia/wait-handshake-policy/src/root.zig",
        "../pkg/common/xenia/pm4-contract/src/root.zig",
        "../pkg/common/xenia/xex-format/src/root.zig",
        "../pkg/common/xenia/notification-contract/src/root.zig",
        "../pkg/common/xenia/log-ring-contract/src/root.zig",
        "../pkg/common/xenia/xthread-contract/src/root.zig",
        "../pkg/common/xenia/vfs-device-contract/src/root.zig",
        "../pkg/common/xenia/launch-assist-contract/src/root.zig",
        "../pkg/common/rosette/ownership-contract/src/root.zig",
        "../pkg/common/rosette/source-architecture-contract/src/root.zig",
        "../pkg/common/xenia/rosette-script-contract/src/root.zig",
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
        package_mod.addImport("rosette_translation_cache_contract", rosette_translation_cache_contract_mod);
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
        "../pkg/x86/xenia/audio-driver/src/root.zig",
        "../pkg/x86/xenia/input-driver/src/root.zig",
        "../pkg/x86/xenia/simd-shim-map/src/root.zig",
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
        "../pkg/ARM64/xenia/audio-driver/src/root.zig",
        "../pkg/ARM64/xenia/input-driver/src/root.zig",
        "../pkg/ARM64/xenia/simd-shim-map/src/root.zig",
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
    gpu_mod.addImport("window_geometry", window_geometry_mod);
    gpu_mod.addAnonymousImport("rosette_live_metal_source", .{
        .root_source_file = b.path("../lib/metal/textures/live_source.zig"),
    });
    gpu_mod.addImport("frame_content_contract", frame_content_contract_mod);
    gpu_mod.addImport("screen_validity", screen_validity_mod);
    const window_geometry_test = b.addTest(.{ .root_module = window_geometry_mod });
    check_step.dependOn(&b.addRunArtifact(window_geometry_test).step);
    const frame_content_contract_test = b.addTest(.{ .root_module = frame_content_contract_mod });
    check_step.dependOn(&b.addRunArtifact(frame_content_contract_test).step);
    const screen_validity_test = b.addTest(.{ .root_module = screen_validity_mod });
    check_step.dependOn(&b.addRunArtifact(screen_validity_test).step);
    const address_region_map_test = b.addTest(.{ .root_module = address_region_map_mod });
    check_step.dependOn(&b.addRunArtifact(address_region_map_test).step);
    gpu_mod.addImport("device_tree", device_tree_mod);
    gpu_mod.addImport("xenos_register_map", xenos_register_map_mod);
    gpu_mod.addImport("xenia_vd_swap_contract", xenia_vd_swap_contract_mod);
    gpu_mod.addImport("xenia_gpu_bringup_contract", xenia_gpu_bringup_contract_mod);
    gpu_mod.addImport("xenia_gpu_observation_contract", xenia_gpu_observation_contract_mod);
    gpu_mod.addImport("xenia_pm4_contract", xenia_pm4_contract_mod);
    gpu_mod.addImport("rosette_root", rosette_root_mod);
    gpu_mod.addImport("xenia_provisioning_contract", xenia_provisioning_contract_mod);
    gpu_mod.addImport("xenia_draw_dispatch_contract", xenia_draw_dispatch_contract_mod);
    gpu_mod.addImport("cocoa_graphics_control_contract", cocoa_graphics_control_contract_mod);
    gpu_mod.addImport("cocoa_window_admission_contract", cocoa_window_admission_contract_mod);
    gpu_mod.addImport("rosette_ownership_contract", rosette_ownership_contract_mod);
    gpu_mod.addImport("xenia_texture_format_contract", xenia_texture_format_contract_mod);
    gpu_mod.addImport("rosette_graphics_bridge", rosette_graphics_bridge_mod);
    // The full kernel export table, so lib/gpu/kernel_surface.zig can name
    // any ordinal a title imports rather than only the sixteen video ones
    // it models. Declared once and shared: two copies of 2913 entries in
    // one binary would be a pointless size cost.
    gpu_mod.addImport("xenia_kernel_export_map", xenia_kernel_export_map_mod);
    const gpu_test = b.addTest(.{ .root_module = gpu_mod });
    check_step.dependOn(&b.addRunArtifact(gpu_test).step);
    // The executing guest thread's registers for code that runs on its
    // behalf. The dyld forwarder and the Windows Vulkan adapter run on
    // whichever host thread made the call; see lib/guest_context/README.md.
    const guest_context_mod = b.createModule(.{
        .root_source_file = b.path("../lib/guest_context/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const guest_context_test = b.addTest(.{ .root_module = guest_context_mod });
    check_step.dependOn(&b.addRunArtifact(guest_context_test).step);
    const dyld_mod = b.createModule(.{
        .root_source_file = b.path("../lib/linker/dyld/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    dyld_mod.addImport("guest_context", guest_context_mod);
    dyld_mod.addImport("macho_compat_runtime", macho_compat_runtime_mod);
    dyld_mod.addImport("gpu", gpu_mod);
    dyld_mod.addImport("xenia_heap_range", xenia_heap_range_mod);
    dyld_mod.addImport("rosette_ppc_host_abi", rosette_ppc_host_abi_mod);
    dyld_mod.addImport("ppc_runtime", ppc_runtime_module);
    dyld_mod.addImport("application_framework", application_framework_mod);
    dyld_mod.addImport("xenia_launch_assist_contract", xenia_launch_assist_contract_mod);
    dyld_mod.addImport("xenia_host_gpu_callback_contract", xenia_host_gpu_callback_contract_mod);
    dyld_mod.addImport("rosette_macos_host_contract", rosette_macos_host_contract_mod);
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
    // The native worker backend has its own lifecycle stress cases. Keep
    // it as an explicit test root so its tests run even if the scheduler
    // root's import graph does not retain dependency test declarations.
    const native_thread_backend_test_mod = b.createModule(.{
        .root_source_file = b.path("../lib/scheduler/native_thread_backend.zig"),
        .target = target,
        .optimize = optimize,
    });
    const native_thread_backend_test = b.addTest(.{ .root_module = native_thread_backend_test_mod });
    check_step.dependOn(&b.addRunArtifact(native_thread_backend_test).step);
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
    // The initializer pipeline was only ever built as someone else's
    // dependency, so it had no test artifact and its tests had never run
    // once — including the ABI-mismatch case, on the very engine that
    // reports a failed pre-main initializer. Rooted so its rules are
    // executed rather than merely compiled.
    const init_test = b.addTest(.{ .root_module = init_mod });
    check_step.dependOn(&b.addRunArtifact(init_test).step);

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
    const windows_vulkan_adapter_mod = b.createModule(.{
        .root_source_file = b.path("../lib/gpu/vulkan/windows_guest_forwarder.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_vulkan_adapter_mod.addImport("gpu", gpu_mod);
    windows_vulkan_adapter_mod.addImport("dyld", dyld_mod);
    windows_vulkan_adapter_mod.addImport("guest_context", guest_context_mod);
    windows_vulkan_adapter_mod.addImport("dll_win32_catalogue", dll_win32_catalogue_mod);
    const windows_vulkan_adapter_test = b.addTest(.{ .root_module = windows_vulkan_adapter_mod });
    const windows_vulkan_adapter_check = b.step("windows-vulkan-check", "Run Windows Vulkan ABI adapter tests");
    const run_windows_vulkan_adapter_test = b.addRunArtifact(windows_vulkan_adapter_test);
    windows_vulkan_adapter_check.dependOn(&run_windows_vulkan_adapter_test.step);
    const windows_vulkan_integration_mod = b.createModule(.{
        .root_source_file = b.path("../lib/gpu/vulkan/windows_guest_forwarder_integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_vulkan_integration_mod.addImport("windows_guest_forwarder", windows_vulkan_adapter_mod);
    windows_vulkan_integration_mod.addImport("gpu", gpu_mod);
    windows_vulkan_integration_mod.addImport("elf_processor_state", windows_graphics_state_test_mod);
    const windows_vulkan_integration_test = b.addTest(.{ .root_module = windows_vulkan_integration_mod });
    const run_windows_vulkan_integration_test = b.addRunArtifact(windows_vulkan_integration_test);
    windows_vulkan_adapter_check.dependOn(&run_windows_vulkan_integration_test.step);
    check_step.dependOn(&run_windows_vulkan_integration_test.step);
    check_step.dependOn(&run_windows_vulkan_adapter_test.step);
    const dyld_test = b.addTest(.{ .root_module = dyld_mod });
    const run_dyld_test = b.addRunArtifact(dyld_test);
    const dyld_check = b.step("dyld-check", "Run the dynamic linker and Vulkan loader bridge tests");
    dyld_check.dependOn(&run_dyld_test.step);
    check_step.dependOn(&run_dyld_test.step);
    // A small gate for the FSI bridge that avoids the full CPU/OS suite.
    // The full check still includes these tests through gpu_test/dyld_test.
    const fsi_check = b.step("fsi-check", "Run the FSI support and forwarder regression tests");
    const fsi_gpu_test = b.addTest(.{ .root_module = gpu_mod, .filters = &.{ "FSI", "Fsi", "fsi", "presentation ceiling" } });
    const fsi_dyld_test = b.addTest(.{ .root_module = dyld_mod, .filters = &.{ "FSI", "Fsi", "fsi", "presentation ceiling" } });
    fsi_check.dependOn(&b.addRunArtifact(fsi_gpu_test).step);
    fsi_check.dependOn(&b.addRunArtifact(fsi_dyld_test).step);
    const metal_live_check = b.step("metal-live-check", "Run native Metal live texture routing regression tests");
    const metal_live_gpu_test = b.addTest(.{ .root_module = gpu_mod, .filters = &.{"native Metal live texture"} });
    const metal_live_dyld_test = b.addTest(.{ .root_module = dyld_mod, .filters = &.{"native Metal live texture"} });
    metal_live_check.dependOn(&b.addRunArtifact(metal_live_gpu_test).step);
    metal_live_check.dependOn(&b.addRunArtifact(metal_live_dyld_test).step);
    // Xenia's log phrases and the comptime rare-character filter over them.
    const xenia_log_phrase_map_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/log-phrase-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const vendor_library_contract_mod = b.createModule(.{
        .root_source_file = b.path("../pkg/vendor/src/root.zig"),
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
    diagnostics_mod.addImport("rosette_run_integrity_contract", rosette_run_integrity_contract_mod);
    diagnostics_mod.addImport("rosette_substantiation_contract", rosette_substantiation_contract_mod);
    diagnostics_mod.addImport("vendor_library_contract", vendor_library_contract_mod);
    diagnostics_mod.addImport("xenia_gpu_observation_contract", xenia_gpu_observation_contract_mod);
    // Package contract checks: rosette_pkg_log calls contractIsWellFormed()
    // on each at startup and writes results to .rosette/rosette-pkg.log.
    diagnostics_mod.addImport("xenia_mount_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/mount-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_kernel_object_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/kernel-object-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_texture_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/texture-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_io_completion_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/io-completion-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_user_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/user-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_shader_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/shader-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_render_target_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/render-target-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_audio_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/audio-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_input_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/input-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_timer_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/timer-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_kernel_export_map", xenia_kernel_export_map_mod);
    diagnostics_mod.addImport("xenia_vd_ring_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/vd-ring-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_pm4_contract", xenia_pm4_contract_mod);
    diagnostics_mod.addImport("rosette_mandatory_order_contract", rosette_mandatory_order_contract_mod);
    diagnostics_mod.addImport("rosette_monotone_witness_contract", rosette_monotone_witness_contract_mod);
    diagnostics_mod.addImport("rosette_graphics_bridge", rosette_graphics_bridge_mod);
    diagnostics_mod.addImport("xenia_vd_swap_contract", xenia_vd_swap_contract_mod);
    diagnostics_mod.addImport("xenia_xiso_format", xenia_xiso_format_mod);
    diagnostics_mod.addImport("xenia_fatal_condition_map", xenia_fatal_condition_map_mod);
    diagnostics_mod.addImport("xenia_claim_reconciliation_contract", xenia_claim_reconciliation_contract_mod);
    diagnostics_mod.addImport("xenia_interrupt_callback_contract", xenia_interrupt_callback_contract_mod);
    diagnostics_mod.addImport("xenia_host_gpu_callback_contract", xenia_host_gpu_callback_contract_mod);
    diagnostics_mod.addImport("diagnostics_async_log_contract", diagnostics_async_log_contract_mod);
    diagnostics_mod.addImport("abi_translation_economics_contract", abi_translation_economics_contract_mod);
    diagnostics_mod.addImport("xenia_wait_graph_contract", xenia_wait_graph_contract_mod);
    diagnostics_mod.addImport("xenia_wait_handshake_policy", xenia_wait_handshake_policy_mod);
    diagnostics_mod.addImport("xenia_graphics_health_contract", xenia_graphics_health_contract_mod);
    diagnostics_mod.addImport("xenia_application_controller_contract", xenia_application_controller_contract_mod);
    diagnostics_mod.addImport("application_framework_contract", application_framework_contract_mod);
    diagnostics_mod.addImport("xenia_xex_format", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/xex-format/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_notification_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/notification-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_log_ring_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/log-ring-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_xthread_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/xthread-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_vfs_device_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/vfs-device-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_ob_contract", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/ob-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenia_config_schema", b.createModule(.{
        .root_source_file = b.path("../pkg/common/xenia/config-schema/src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    diagnostics_mod.addImport("xenos_register_map", xenos_register_map_mod);
    diagnostics_mod.addImport("xenia_graphics_contract", xenia_graphics_contract_mod);
    diagnostics_mod.addImport("xenia_surface_path_contract", xenia_surface_path_contract_mod);
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
    pthread_mod.addImport("xenia_wait_handshake_policy", xenia_wait_handshake_policy_mod);
    // Rooted so these run rather than merely exist: the module's
    // twenty-five tests had never been built by the gate, and two of them
    // no longer compiled against the code they cover.
    const pthread_test = b.addTest(.{ .root_module = pthread_mod });
    check_step.dependOn(&b.addRunArtifact(pthread_test).step);
    const guest_abi_mod = b.createModule(.{
        .root_source_file = b.path("../lib/runtime/guest-abi/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    guest_abi_mod.addImport("event_log", event_log_mod);
    // The window-to-compositor chain type is shared with the Vulkan
    // forwarder, so both describe the same layout rather than each
    // declaring its own copy of the AppKit geometry struct.
    guest_abi_mod.addImport("window_geometry", window_geometry_mod);
    guest_abi_mod.addImport("libcpp_thread_abi", libcpp_thread_abi_mod);
    // The native window runtime is the surface Xenia forwards into, so it
    // is the layer that has to be able to say which forwardings Rosette has
    // semantics for. The rule itself stays in the package.
    guest_abi_mod.addImport("cocoa_window_admission_contract", cocoa_window_admission_contract_mod);
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
    // A separate module for the tests rather than the shipped one: the
    // native window runtime's Objective-C bridge has to be linked for its
    // admission tests to run, and compiling that bridge into the module the
    // processor already links it into would be a duplicate symbol.
    const guest_abi_test_mod = b.createModule(.{
        .root_source_file = b.path("../lib/runtime/guest-abi/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    guest_abi_test_mod.addImport("event_log", event_log_mod);
    guest_abi_test_mod.addImport("libcpp_thread_abi", libcpp_thread_abi_mod);
    guest_abi_test_mod.addImport("cocoa_window_admission_contract", cocoa_window_admission_contract_mod);
    if (is_macos) {
        guest_abi_test_mod.addSystemFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{macos_sdk_root}) });
        guest_abi_test_mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{macos_sdk_root}) });
        guest_abi_test_mod.addCSourceFile(.{
            .file = b.path("../lib/Mach-O/native_window_bridge.m"),
            .flags = &.{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
        });
        guest_abi_test_mod.addCSourceFile(.{
            .file = b.path("../lib/Mach-O/input_controller_bridge.m"),
            .flags = &.{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
        });
        guest_abi_test_mod.linkFramework("AppKit", .{});
        guest_abi_test_mod.linkFramework("QuartzCore", .{});
        guest_abi_test_mod.linkFramework("Metal", .{});
        guest_abi_test_mod.linkFramework("GameController", .{});
    }
    const guest_abi_test = b.addTest(.{ .root_module = guest_abi_test_mod });
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
    macho_core_mod.addImport("rosette_translation_cache_contract", rosette_translation_cache_contract_mod);

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
    macho_types_mod.addImport("rosette_translation_cache_contract", rosette_translation_cache_contract_mod);
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
    process_core_mod.addImport("evex_runtime", evex_runtime_mod);
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
    // Rooted for the same reason process_core is: as a dependency of the
    // processor build these test blocks only ever type-check, and a test
    // that cannot fail is not a test. The guest environment lookup lives
    // here, and it is the channel Rosette uses to hand the emulator its own
    // run identity — the one place where a silently wrong answer is read as
    // a graphics-system failure thousands of lines away.
    const import_handler_test = b.addTest(.{ .root_module = import_handler_mod });
    check_step.dependOn(&b.addRunArtifact(import_handler_test).step);

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
    macho_processor_mod.addImport("xenos_register_map", xenos_register_map_mod);
    macho_processor_mod.addImport("device_tree", device_tree_mod);
    macho_processor_mod.addImport("preflight", preflight_mod);
    macho_processor_mod.addImport("rosette_macos_host_contract", rosette_macos_host_contract_mod);
    macho_processor_mod.addImport("ready_compiler", ready_compiler_mod);
    macho_processor_mod.addImport("xenia_heap_range", xenia_heap_range_mod);
    macho_processor_mod.addImport("ppc_runtime", ppc_runtime_module);
    macho_processor_mod.addImport("application_framework", application_framework_mod);
    macho_processor_mod.addImport("xenia_launch_assist_contract", xenia_launch_assist_contract_mod);
    macho_processor_mod.addImport("xenia_host_gpu_callback_contract", xenia_host_gpu_callback_contract_mod);
    macho_processor_mod.addImport("diagnostics", diagnostics_mod);
    macho_processor_mod.addImport("xenia_xiso_format", xenia_xiso_format_mod);
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
            .file = b.path("../lib/Mach-O/input_controller_bridge.m"),
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
        macho_processor_mod.addCSourceFile(.{
            .file = b.path("../lib/Mach-O/application_framework_exports_anchor.c"),
            .flags = &.{ "-Wall", "-Wextra" },
        });
        macho_processor_mod.addCSourceFile(.{
            .file = b.path("../lib/Mach-O/xenia_launch_assist_exports_anchor.c"),
            .flags = &.{ "-Wall", "-Wextra" },
        });
        macho_processor_mod.addCSourceFile(.{
            .file = b.path("../lib/Mach-O/xenia_host_gpu_callback_exports_anchor.c"),
            .flags = &.{ "-Wall", "-Wextra" },
        });
        macho_processor_mod.linkFramework("AppKit", .{});
        macho_processor_mod.linkFramework("QuartzCore", .{});
        macho_processor_mod.linkFramework("Metal", .{});
        macho_processor_mod.linkFramework("GameController", .{});
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
    // Xenia hosts its optional Rosette framework provider in this
    // executable and resolves the ABI with dlsym(RTLD_DEFAULT). `pub
    // export` keeps the provider live, but it does not by itself place
    // the executable's symbols in the process-wide dynamic lookup table.
    // Make the host boundary discoverable without changing the provider's
    // contract: the callback still has to pass Rosette's runtime gates
    // before it can authorize any host mutation.
    macho_processor.rdynamic = true;
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
    macho_processor_test_mod.addImport("xenos_register_map", xenos_register_map_mod);
    macho_processor_test_mod.addImport("device_tree", device_tree_mod);
    macho_processor_test_mod.addImport("preflight", preflight_mod);
    macho_processor_test_mod.addImport("rosette_macos_host_contract", rosette_macos_host_contract_mod);
    macho_processor_test_mod.addImport("ready_compiler", ready_compiler_mod);
    macho_processor_test_mod.addImport("xenia_heap_range", xenia_heap_range_mod);
    macho_processor_test_mod.addImport("application_framework", application_framework_mod);
    macho_processor_test_mod.addImport("xenia_host_gpu_callback_contract", xenia_host_gpu_callback_contract_mod);
    macho_processor_test_mod.addImport("diagnostics", diagnostics_mod);
    macho_processor_test_mod.addImport("xenia_xiso_format", xenia_xiso_format_mod);
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
        macho_processor_test_mod.addCSourceFile(.{
            .file = b.path("../lib/Mach-O/input_controller_bridge.m"),
            .flags = &.{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
        });
        macho_processor_test_mod.linkFramework("AppKit", .{});
        macho_processor_test_mod.linkFramework("QuartzCore", .{});
        macho_processor_test_mod.linkFramework("Metal", .{});
        macho_processor_test_mod.linkFramework("GameController", .{});
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

    // Keep the release census honest for the small source roots that are
    // shipped by Rosette but were previously only compiled indirectly (or
    // not at all) by a processor test. Each entry is a real run artifact,
    // so named and anonymous declarations in these roots are not confused
    // with compile-only imports. This block is deliberately independent
    // of Xenia and never launches an emulator.
    const source_test_specs = [_][]const u8{
        "../lib/processor/bat_processor/root.zig",
        "../lib/runtime/mode/root.zig",
        "../lib/runtime/mode/runtime_mode_test.zig",
        "../src/compat/source/bitcode_stub.zig",
        "../src/compat/source/force_types.zig",
        "../src/compat/source/include_compat.zig",
        "../src/compat/source/narrow.zig",
        "../src/memory/safety.zig",
        "../src/tooling/app_parser/root.zig",
        "../src/source_test_root.zig",
        "../src/tooling/binary_exporter/dos_mz_exporter.zig",
        "../src/tooling/disasm_logger/x86_trace_logger.zig",
        "../src/tooling/exe_parser/launch_config.zig",
        "../src/tooling/exe_parser/pe_parser.zig",
        "../src/tooling/exe_parser/rosette_exe_runner.zig",
        "../src/tooling/exe_parser/rosette_package.zig",
        "../src/tooling/iso/root.zig",
    };
    inline for (source_test_specs) |source| {
        const source_test_mod = b.createModule(.{
            .root_source_file = b.path(source),
            .target = target,
            .optimize = optimize,
            .link_libc = std.mem.eql(u8, source, "../src/shell/global_config/rosette_shell.zig"),
        });
        if (std.mem.eql(u8, source, "../lib/runtime/mode/root.zig") or
            std.mem.eql(u8, source, "../lib/runtime/mode/runtime_mode_test.zig"))
        {
            source_test_mod.addImport("event_log", event_log_mod);
        }
        if (std.mem.eql(u8, source, "../src/shell/global_config/rosette_shell.zig")) {
            source_test_mod.addImport("entrypoint_alignment", entrypoint_alignment_module);
            source_test_mod.addImport("entrypoint_kernel_process_guard", entrypoint_kernel_process_guard_module);
            source_test_mod.addImport("compat_source_include_compat", b.createModule(.{
                .root_source_file = b.path("../src/compat/source/include_compat.zig"),
                .target = target,
                .optimize = optimize,
            }));
        }
        if (std.mem.eql(u8, source, "../src/tooling/disasm_logger/x86_trace_logger.zig")) {
            source_test_mod.addImport("x86_asm", x86_trace_asm_module);
        }
        if (std.mem.eql(u8, source, "../src/source_test_root.zig")) {
            source_test_mod.addImport("runtime_abi_handshake", runtime_abi_module);
            source_test_mod.addImport("bridge_register_tracing", bridge_register_trace_module);
            source_test_mod.addImport("bridge_exceptions", bridge_exceptions_module);
            source_test_mod.addImport("bridge_memory", bridge_memory_module);
            source_test_mod.addImport("bridge_stack", bridge_stack_module);
            source_test_mod.addImport("bridge_dos_runtime", bridge_dos_runtime_module);
            source_test_mod.addImport("x86_asm", x86_asm_module);
            source_test_mod.addImport("x86_trace_logger", trace_logger_module);
        }
        const source_test = b.addTest(.{ .root_module = source_test_mod });
        check_step.dependOn(&b.addRunArtifact(source_test).step);
    }
}

pub fn register1(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const dll_translator_module = ctx.dll_translator_module;

    const dll_test = b.addTest(.{ .root_module = dll_translator_module });
    check_step.dependOn(&b.addRunArtifact(dll_test).step);
}

pub fn register2(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const dyld_cache_tree_module = ctx.dyld_cache_tree_module;

    const dyld_cache_test = b.addTest(.{ .root_module = dyld_cache_tree_module });
    check_step.dependOn(&b.addRunArtifact(dyld_cache_test).step);
}

pub fn register3(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const pseudo_kernel_cache_module = ctx.pseudo_kernel_cache_module;

    const pseudo_kernel_cache_test = b.addTest(.{ .root_module = pseudo_kernel_cache_module });
    check_step.dependOn(&b.addRunArtifact(pseudo_kernel_cache_test).step);
}

pub fn register4(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const pseudo_kernel_code_cache_table_module = ctx.pseudo_kernel_code_cache_table_module;

    const pseudo_kernel_code_cache_table_test = b.addTest(.{ .root_module = pseudo_kernel_code_cache_table_module });
    check_step.dependOn(&b.addRunArtifact(pseudo_kernel_code_cache_table_test).step);
}
