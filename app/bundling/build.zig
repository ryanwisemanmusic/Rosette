const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const is_macos = target.result.os.tag == .macos;
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

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
    const arch_flags: []const []const u8 = if (is_macos)
        &[_][]const u8{ "-std=c11", "-include", "shims/macos/compiler_compat.h" }
    else
        &[_][]const u8{"-std=c11"};
    helper_mod.addObjectFile(compileCObject(
        b,
        target,
        optimize,
        b.path("../../src/graphics/common/debug_runtime.c"),
        "debug_runtime.o",
        arch_flags,
    ));
    helper_mod.addObjectFile(compileCObject(
        b,
        target,
        optimize,
        b.path("../../src/graphics/CLI/window_main.c"),
        "window_main_cli.o",
        arch_flags,
    ));
    if (is_macos) {
        // The Windows-target route still runs on the macOS host.  Give the
        // Rosetta runner the same native Cocoa/Metal ownership boundary as
        // the Mach-O processor so CreateWindowEx/ShowWindow can produce a
        // real host window without changing the inspected Windows tree.
        helper_mod.addObjectFile(compileCObject(
            b,
            target,
            optimize,
            b.path("../../lib/Mach-O/native_window_bridge.m"),
            "windows_route_native_window_bridge.o",
            &[_][]const u8{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
        ));
        helper_mod.addObjectFile(compileCObject(
            b,
            target,
            optimize,
            b.path("../../lib/Mach-O/native_audio_bridge.m"),
            "windows_route_native_audio_bridge.o",
            &[_][]const u8{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
        ));
        helper_mod.linkFramework("AppKit", .{});
        helper_mod.linkFramework("QuartzCore", .{});
        helper_mod.linkFramework("Metal", .{});
        helper_mod.linkFramework("AudioToolbox", .{});
    }
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
        .root_source_file = b.path("../../src/tooling/exe_parser/rosette_exe_runner.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const exe_runner_cli_mod = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/exe_parser/exe_runner_bridge.zig"),
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
    const entrypoint_alignment_module = b.createModule(.{
        .root_source_file = b.path("../../src/entrypoint/alignment/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const entrypoint_kernel_process_guard_module = b.createModule(.{
        .root_source_file = b.path("../../src/entrypoint/kernel/process_guard.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const phrase_filter_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/text/phrase-filter/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xenia_fatal_condition_map_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/xenia/fatal-condition-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    xenia_fatal_condition_map_module.addImport("phrase_filter", phrase_filter_module);
    // Whether a Xenia warning-level line is a finding at all.
    const xenia_warning_severity_map_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/xenia/warning-severity-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    xenia_warning_severity_map_module.addImport("phrase_filter", phrase_filter_module);
    // What a Xenia symbol name means, so a report can say what the guest is
    // doing at an address rather than only where it is.
    const xenia_guest_frontier_map_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/xenia/guest-frontier-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // What a Vulkan command can put into the image it targets, so a frame
    // built only from clears is never counted as a frame with a picture.
    const windows_frame_content_contract_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/rosette/frame-content-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The ELF processor's terminal screen verdict is shared with the native
    // graphics path; keep the app-bundling route on the same module identity.
    const windows_screen_validity_module = b.createModule(.{
        .root_source_file = b.path("../../lib/gpu/screen_validity.zig"),
        .target = target,
        .optimize = optimize,
    });
    // What a guest address is when no symbol names it.
    const windows_address_region_map_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/rosette/address-region-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // What a guest address is, independent of the route that reached it.
    const xenia_guest_address_map_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/xenia/guest-address-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The Xenia functions whose first entry answers a question no counter of
    // Rosette's own surface can: whether the title ever produced a frame.
    const xenia_guest_milestone_map_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/xenia/guest-milestone-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Xenia's kernel export shims, and the console's export tables they are
    // joined against. See pkg/common/xenia/kernel-shim-map.
    const xenia_kernel_shim_map_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/xenia/kernel-shim-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xenia_kernel_export_map_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/xenia/kernel-export-map/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const compat_source_include_module = b.createModule(.{
        .root_source_file = b.path("../../src/compat/source/include_compat.zig"),
        .target = target,
        .optimize = optimize,
    });
    const compat_third_party_include_module = b.createModule(.{
        .root_source_file = b.path("../../src/compat/third_party/include_compat.zig"),
        .target = target,
        .optimize = optimize,
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
    const isa_highway_module = b.createModule(.{
        .root_source_file = b.path("../../ISA/highway.zig"),
        .target = target,
        .optimize = optimize,
    });
    const isa_decode_module = b.createModule(.{
        .root_source_file = b.path("../../ISA/decode/root.zig"),
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
    const clr_runtime_module = b.createModule(.{
        .root_source_file = b.path("../../include/runtime_module.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cleo_module = b.createModule(.{
        .root_source_file = b.path("../../lib/CLEO/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    cleo_module.addImport("isa_highway", isa_highway_module);
    const x86_asm_module = b.createModule(.{
        .root_source_file = b.path("../../src/x86-ASM/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const x86_disasm_module = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/disasm_logger/x86_disasm.zig"),
        .target = target,
        .optimize = optimize,
    });
    const x86_trace_logger_module = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/disasm_logger/x86_trace_logger.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const decoder_flags_module = b.createModule(.{
        .root_source_file = b.path("../../src/x64-ASM/flags.zig"),
        .target = target,
        .optimize = optimize,
    });
    const decoder_cpu_state_module = b.createModule(.{
        .root_source_file = b.path("../../src/x64-ASM/cpu_state.zig"),
        .target = target,
        .optimize = optimize,
    });
    decoder_cpu_state_module.addImport("flags", decoder_flags_module);
    const decoder_bit_test_module = b.createModule(.{
        .root_source_file = b.path("../../src/x64-ASM/bit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    decoder_bit_test_module.addImport("flags", decoder_flags_module);
    const decoder_capabilities_module = b.createModule(.{
        .root_source_file = b.path("../../src/x64-ASM/capabilities.zig"),
        .target = target,
        .optimize = optimize,
    });
    const x64_decoder_module = b.createModule(.{
        .root_source_file = b.path("../../ISA/decoding/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    x64_decoder_module.addImport("isa_highway", isa_highway_module);
    x64_decoder_module.addImport("isa_decode", isa_decode_module);
    x64_decoder_module.addImport("isa_registry", isa_module);
    x64_decoder_module.addImport("runtime_abi_handshake", runtime_abi_module);
    x64_decoder_module.addImport("flags", decoder_flags_module);
    x64_decoder_module.addImport("cpu_state", decoder_cpu_state_module);
    x64_decoder_module.addImport("bit_test", decoder_bit_test_module);
    x64_decoder_module.addImport("capabilities", decoder_capabilities_module);
    const x64_interpreter_module = b.createModule(.{
        .root_source_file = b.path("../../src/x64-ASM/interpreter.zig"),
        .target = target,
        .optimize = optimize,
    });
    const scheduler_module = b.createModule(.{
        .root_source_file = b.path("../../lib/scheduler/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exit_diagnostics_module = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/exit_diagnostics/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pe_execution_history_module = b.createModule(.{
        .root_source_file = b.path("../../lib/runtime/execution-history/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pe_evex_runtime_module = b.createModule(.{
        .root_source_file = b.path("../../lib/runtime/process-core/evex.zig"),
        .target = target,
        .optimize = optimize,
    });
    pe_evex_runtime_module.addImport("x64_decoder", x64_decoder_module);
    pe_evex_runtime_module.addImport("exit_diagnostics", exit_diagnostics_module);
    const pe_x86_vector_helpers_module = b.createModule(.{
        .root_source_file = b.path("../../lib/Mach-O/execution_helpers.zig"),
        .target = target,
        .optimize = optimize,
    });
    pe_x86_vector_helpers_module.addImport("x64_decoder", x64_decoder_module);
    const native_windows_graphics_module = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/exe_parser/native_windows_graphics.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // The audible half of the guest's wave device. Separate from the
    // graphics companion because the two fail independently and a run has to
    // be able to say which one it lost.
    const native_windows_audio_module = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/exe_parser/native_windows_audio.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const pe_x64_syscalls_module = b.createModule(.{
        .root_source_file = b.path("../../src/x64-ASM/syscalls.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tso_memory_module = b.createModule(.{
        .root_source_file = b.path("../../lib/processor/ELF_processor/tso_memory.zig"),
        .target = target,
        .optimize = optimize,
    });
    const utf8_codec_module = b.createModule(.{
        .root_source_file = b.path("../../lib/text/utf8/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Host-thread parking, the stop-the-world gate and the stall watchdog.
    const concurrency_module = b.createModule(.{
        .root_source_file = b.path("../../lib/concurrency/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const parallelism_module = b.createModule(.{
        .root_source_file = b.path("../../lib/processor/ELF_processor/parallelism/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    parallelism_module.addImport("concurrency", concurrency_module);
    const windows_runtime_module = b.createModule(.{
        .root_source_file = b.path("../../src/x64-ASM/windows_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_runtime_module.addImport("tso_memory", tso_memory_module);
    windows_runtime_module.addImport("utf8_codec", utf8_codec_module);

    // The Windows import boundary's static facts live in pkg/dll/win32.
    const dll_win32_return_contract_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/dll/win32/return-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // What a declined Windows DLL would have to gain before Rosette could
    // serve it.
    const dll_win32_capability_gap_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/dll/win32/capability-gap/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The shape every per-DLL package uses to declare one export.
    const dll_win32_export_contract_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/dll/win32/export-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dll_win32_library_inventory_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/dll/win32/library-inventory/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dll_win32_catalogue_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/dll/win32/catalogue/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dll_win32_package_specs = [_]struct {
        import_name: []const u8,
        root_source_file: []const u8,
    }{
        .{ .import_name = "dll_win32_advapi32", .root_source_file = "../../pkg/dll/win32/advapi32/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_convert_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-convert-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_environment_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-environment-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_filesystem_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-filesystem-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_heap_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-heap-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_locale_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-locale-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_math_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-math-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_private_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-private-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_runtime_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-runtime-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_stdio_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-stdio-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_string_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-string-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_time_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-time-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_api_ms_win_crt_utility_l1_1_0", .root_source_file = "../../pkg/dll/win32/api-ms-win-crt-utility-l1-1-0/src/root.zig" },
        .{ .import_name = "dll_win32_bcrypt", .root_source_file = "../../pkg/dll/win32/bcrypt/src/root.zig" },
        .{ .import_name = "dll_win32_cfgmgr32", .root_source_file = "../../pkg/dll/win32/cfgmgr32/src/root.zig" },
        .{ .import_name = "dll_win32_dwmapi", .root_source_file = "../../pkg/dll/win32/dwmapi/src/root.zig" },
        .{ .import_name = "dll_win32_dxgi", .root_source_file = "../../pkg/dll/win32/dxgi/src/root.zig" },
        .{ .import_name = "dll_win32_vulkan_1", .root_source_file = "../../pkg/dll/win32/vulkan-1/src/root.zig" },
        .{ .import_name = "dll_win32_dynamic", .root_source_file = "../../pkg/dll/win32/dynamic/src/root.zig" },
        .{ .import_name = "dll_win32_gdi32", .root_source_file = "../../pkg/dll/win32/gdi32/src/root.zig" },
        .{ .import_name = "dll_win32_hid", .root_source_file = "../../pkg/dll/win32/hid/src/root.zig" },
        .{ .import_name = "dll_win32_imm32", .root_source_file = "../../pkg/dll/win32/imm32/src/root.zig" },
        .{ .import_name = "dll_win32_kernel32", .root_source_file = "../../pkg/dll/win32/kernel32/src/root.zig" },
        .{ .import_name = "dll_win32_libusbk", .root_source_file = "../../pkg/dll/win32/libusbk/src/root.zig" },
        .{ .import_name = "dll_win32_msvcrt", .root_source_file = "../../pkg/dll/win32/msvcrt/src/root.zig" },
        .{ .import_name = "dll_win32_ole32", .root_source_file = "../../pkg/dll/win32/ole32/src/root.zig" },
        .{ .import_name = "dll_win32_oleaut32", .root_source_file = "../../pkg/dll/win32/oleaut32/src/root.zig" },
        .{ .import_name = "dll_win32_setupapi", .root_source_file = "../../pkg/dll/win32/setupapi/src/root.zig" },
        .{ .import_name = "dll_win32_shcore", .root_source_file = "../../pkg/dll/win32/shcore/src/root.zig" },
        .{ .import_name = "dll_win32_shell32", .root_source_file = "../../pkg/dll/win32/shell32/src/root.zig" },
        .{ .import_name = "dll_win32_shlwapi", .root_source_file = "../../pkg/dll/win32/shlwapi/src/root.zig" },
        .{ .import_name = "dll_win32_user32", .root_source_file = "../../pkg/dll/win32/user32/src/root.zig" },
        .{ .import_name = "dll_win32_version", .root_source_file = "../../pkg/dll/win32/version/src/root.zig" },
        .{ .import_name = "dll_win32_winmm", .root_source_file = "../../pkg/dll/win32/winmm/src/root.zig" },
        .{ .import_name = "dll_win32_winusb", .root_source_file = "../../pkg/dll/win32/winusb/src/root.zig" },
        .{ .import_name = "dll_win32_wsock32", .root_source_file = "../../pkg/dll/win32/wsock32/src/root.zig" },
    };
    for (dll_win32_package_specs) |spec| {
        const package_mod = b.createModule(.{
            .root_source_file = b.path(spec.root_source_file),
            .target = target,
            .optimize = optimize,
        });
        package_mod.addImport("dll_win32_export_contract", dll_win32_export_contract_module);
        dll_win32_catalogue_module.addImport(spec.import_name, package_mod);
    }
    dll_win32_export_contract_module.addImport("dll_win32_return_contract", dll_win32_return_contract_module);
    dll_win32_catalogue_module.addImport("dll_win32_export_contract", dll_win32_export_contract_module);
    dll_win32_library_inventory_module.addImport("dll_win32_catalogue", dll_win32_catalogue_module);
    dll_win32_library_inventory_module.addImport("dll_win32_capability_gap", dll_win32_capability_gap_module);
    windows_runtime_module.addImport("dll_win32_return_contract", dll_win32_return_contract_module);
    windows_runtime_module.addImport("dll_win32_library_inventory", dll_win32_library_inventory_module);
    const pe_x64_linux_runtime_module = b.createModule(.{
        .root_source_file = b.path("../../src/x64-ASM/linux_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    pe_x64_linux_runtime_module.addImport("x64_syscalls", pe_x64_syscalls_module);
    pe_x64_linux_runtime_module.addImport("windows_runtime", windows_runtime_module);
    const pe_x64_guest_abi_module = b.createModule(.{
        .root_source_file = b.path("../../src/x64-ASM/guest_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pe_elf_state_module = b.createModule(.{
        .root_source_file = b.path("../../lib/processor/ELF_processor/process.zig"),
        .target = target,
        .optimize = optimize,
    });
    pe_elf_state_module.addImport("tso_memory", tso_memory_module);
    pe_elf_state_module.addImport("concurrency", concurrency_module);
    pe_elf_state_module.addImport("parallelism", parallelism_module);
    pe_elf_state_module.addImport("x64_decoder", x64_decoder_module);
    pe_elf_state_module.addImport("x64_interpreter", x64_interpreter_module);
    pe_elf_state_module.addImport("x64_linux_runtime", pe_x64_linux_runtime_module);
    pe_elf_state_module.addImport("x64_syscalls", pe_x64_syscalls_module);
    pe_elf_state_module.addImport("x64_guest_abi", pe_x64_guest_abi_module);
    pe_elf_state_module.addImport("exit_diagnostics", exit_diagnostics_module);
    // The full CLEO root exports the same routing surface used by the ELF
    // processor. Reuse it here so the runner has one owner for lib/CLEO files.
    pe_elf_state_module.addImport("cleo_routing", cleo_module);
    pe_elf_state_module.addImport("execution_history", pe_execution_history_module);
    pe_elf_state_module.addImport("evex_runtime", pe_evex_runtime_module);
    pe_elf_state_module.addImport("x86_vector_helpers", pe_x86_vector_helpers_module);
    pe_elf_state_module.addImport("xenia_fatal_condition_map", xenia_fatal_condition_map_module);
    pe_elf_state_module.addImport("xenia_guest_frontier_map", xenia_guest_frontier_map_module);
    pe_elf_state_module.addImport("xenia_warning_severity_map", xenia_warning_severity_map_module);
    pe_elf_state_module.addImport("xenia_guest_milestone_map", xenia_guest_milestone_map_module);
    pe_elf_state_module.addImport("xenia_kernel_shim_map", xenia_kernel_shim_map_module);
    pe_elf_state_module.addImport("xenia_kernel_export_map", xenia_kernel_export_map_module);
    pe_elf_state_module.addImport("xenia_guest_address_map", xenia_guest_address_map_module);
    pe_elf_state_module.addImport("frame_content_contract", windows_frame_content_contract_module);
    pe_elf_state_module.addImport("screen_validity", windows_screen_validity_module);
    pe_elf_state_module.addImport("address_region_map", windows_address_region_map_module);

    const pe64_runtime_test_module = b.createModule(.{
        .root_source_file = b.path("../../src/tooling/exe_parser/pe64_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    pe64_runtime_test_module.addImport("x64_decoder", x64_decoder_module);
    pe64_runtime_test_module.addImport("elf_processor_state", pe_elf_state_module);
    pe64_runtime_test_module.addImport("windows_runtime", windows_runtime_module);
    pe64_runtime_test_module.addImport("evex_runtime", pe_evex_runtime_module);
    pe64_runtime_test_module.addImport("cleo_routing", cleo_module);
    pe64_runtime_test_module.addImport("x86_vector_helpers", pe_x86_vector_helpers_module);

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
    x86_asm_module.addImport("clr_runtime", clr_runtime_module);
    x86_asm_module.addImport("cleo", cleo_module);
    x86_disasm_module.addImport("x86_asm", x86_asm_module);
    x86_trace_logger_module.addImport("x86_asm", x86_asm_module);

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
    exe_runner_mod.addImport("clr_runtime", clr_runtime_module);
    exe_runner_mod.addImport("x86_asm", x86_asm_module);
    exe_runner_mod.addImport("x86_disasm", x86_disasm_module);
    exe_runner_mod.addImport("x86_trace_logger", x86_trace_logger_module);
    exe_runner_mod.addImport("x64_decoder", x64_decoder_module);
    exe_runner_mod.addImport("elf_processor_state", pe_elf_state_module);
    exe_runner_mod.addImport("windows_runtime", windows_runtime_module);
    exe_runner_mod.addImport("evex_runtime", pe_evex_runtime_module);
    exe_runner_mod.addImport("cleo_routing", cleo_module);
    exe_runner_mod.addImport("x86_vector_helpers", pe_x86_vector_helpers_module);
    exe_runner_mod.addImport("native_windows_graphics", native_windows_graphics_module);
    exe_runner_mod.addImport("native_windows_audio", native_windows_audio_module);
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
    exe_runner_cli_mod.addImport("clr_runtime", clr_runtime_module);
    exe_runner_cli_mod.addImport("x86_asm", x86_asm_module);
    exe_runner_cli_mod.addImport("x86_disasm", x86_disasm_module);
    exe_runner_cli_mod.addImport("x86_trace_logger", x86_trace_logger_module);
    exe_runner_cli_mod.addImport("x64_decoder", x64_decoder_module);
    exe_runner_cli_mod.addImport("elf_processor_state", pe_elf_state_module);
    exe_runner_cli_mod.addImport("windows_runtime", windows_runtime_module);
    exe_runner_cli_mod.addImport("evex_runtime", pe_evex_runtime_module);
    exe_runner_cli_mod.addImport("cleo_routing", cleo_module);
    exe_runner_cli_mod.addImport("x86_vector_helpers", pe_x86_vector_helpers_module);
    exe_runner_cli_mod.addImport("native_windows_graphics", native_windows_graphics_module);
    exe_runner_cli_mod.addImport("native_windows_audio", native_windows_audio_module);
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
    shell_helper_mod.addImport("entrypoint_alignment", entrypoint_alignment_module);
    shell_helper_mod.addImport("compat_source_include_compat", compat_source_include_module);
    shell_helper_mod.addImport("compat_third_party_include_compat", compat_third_party_include_module);
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
    compat_router_mod.addImport("exit_diagnostics", exit_diagnostics_module);
    b.installArtifact(compat_router);

    const macho_compat_runtime_module = b.createModule(.{
        .root_source_file = b.path("../../lib/Mach-O/compat_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The Windows PE route reuses the real Vulkan guest forwarder that already
    // powers the Mach-O path. Keep this graph local to the app build: the PE
    // executor only sees the callback seam, while the host-side companion owns
    // the heavier dyld/GPU forwarding implementation.
    const windows_event_log_module = b.createModule(.{
        .root_source_file = b.path("../../lib/runtime/event-log/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_device_tree_module = b.createModule(.{
        .root_source_file = b.path("../../lib/device_tree/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Shared with the guest-ABI window runtime so the forwarder and the
    // runtime describe the same AppKit geometry layout.
    const windows_window_geometry_module = b.createModule(.{
        .root_source_file = b.path("../../lib/gpu/window_geometry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_gpu_module = b.createModule(.{
        .root_source_file = b.path("../../lib/gpu/windows_forwarder_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_gpu_module.addImport("device_tree", windows_device_tree_module);
    windows_gpu_module.addImport("window_geometry", windows_window_geometry_module);
    windows_gpu_module.addImport("frame_content_contract", windows_frame_content_contract_module);
    windows_gpu_module.addImport("screen_validity", windows_screen_validity_module);

    const windows_ppc_decode_module = b.createModule(.{
        .root_source_file = b.path("../../ISA/ppc/decode/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_arm64_encode_module = b.createModule(.{
        .root_source_file = b.path("../../lib/compiler/arm64/encode.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_ppc_routing_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/PPC/xenia/runtime/instruction-routing/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_ppc_runtime_module = b.createModule(.{
        .root_source_file = b.path("../../lib/runtime/ppc/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    windows_ppc_runtime_module.addImport("ppc_decode", windows_ppc_decode_module);
    windows_ppc_runtime_module.addImport("arm64_encode", windows_arm64_encode_module);
    windows_ppc_runtime_module.addImport("ppc_instruction_routing", windows_ppc_routing_module);
    // The PE64 route's x86-64 block translator emits through the same encoder
    // and maps its code memory through libc.
    windows_arm64_encode_module.link_libc = true;
    pe_elf_state_module.addImport("arm64_encode", windows_arm64_encode_module);

    const windows_ppc_host_abi_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/abi/rosette-ppc-host/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_heap_range_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/ARM64/xenia/memory/heap-range/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_application_framework_contract_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/application-framework-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_launch_assist_contract_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/xenia/launch-assist-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_host_gpu_callback_contract_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/xenia/host-gpu-callback-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_macos_host_contract_module = b.createModule(.{
        .root_source_file = b.path("../../pkg/common/rosette/macos-host-contract/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_application_framework_module = b.createModule(.{
        .root_source_file = b.path("../../lib/framework/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_application_framework_module.addImport("application_framework_contract", windows_application_framework_contract_module);
    windows_application_framework_module.addImport("xenia_launch_assist_contract", windows_launch_assist_contract_module);
    windows_application_framework_module.addImport("xenia_host_gpu_callback_contract", windows_host_gpu_callback_contract_module);

    // The executing guest thread's registers for code that runs on its
    // behalf; see lib/guest_context/README.md.
    const windows_guest_context_module = b.createModule(.{
        .root_source_file = b.path("../../lib/guest_context/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_dyld_module = b.createModule(.{
        .root_source_file = b.path("../../lib/linker/dyld/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_dyld_module.addImport("guest_context", windows_guest_context_module);
    windows_dyld_module.addImport("macho_compat_runtime", macho_compat_runtime_module);
    windows_dyld_module.addImport("gpu", windows_gpu_module);
    windows_dyld_module.addImport("event_log", windows_event_log_module);
    windows_dyld_module.addImport("scheduler", scheduler_module);
    windows_dyld_module.addImport("xenia_heap_range", windows_heap_range_module);
    windows_dyld_module.addImport("rosette_ppc_host_abi", windows_ppc_host_abi_module);
    windows_dyld_module.addImport("ppc_runtime", windows_ppc_runtime_module);
    windows_dyld_module.addImport("application_framework", windows_application_framework_module);
    windows_dyld_module.addImport("xenia_launch_assist_contract", windows_launch_assist_contract_module);
    windows_dyld_module.addImport("xenia_host_gpu_callback_contract", windows_host_gpu_callback_contract_module);
    windows_dyld_module.addImport("rosette_macos_host_contract", windows_macos_host_contract_module);

    const windows_guest_forwarder_module = b.createModule(.{
        .root_source_file = b.path("../../lib/gpu/vulkan/windows_guest_forwarder.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_guest_forwarder_module.addImport("gpu", windows_gpu_module);
    windows_guest_forwarder_module.addImport("dyld", windows_dyld_module);
    windows_guest_forwarder_module.addImport("guest_context", windows_guest_context_module);
    windows_guest_forwarder_module.addImport("dll_win32_catalogue", dll_win32_catalogue_module);
    native_windows_graphics_module.addImport("gpu", windows_gpu_module);
    native_windows_graphics_module.addImport("windows_guest_forwarder", windows_guest_forwarder_module);
    // The full Mach-O processor is assembled by build/build.zig. This app
    // build used to carry a second, incomplete dependency graph here; as the
    // processor gained its GPU/runtime modules that copy stopped compiling and
    // could also leave the app bundle with a different processor than the
    // shell-installed artifact. shell-helper-build (the Makefile prerequisite
    // for app-wrapper) builds the canonical binary before this install step.

    if (is_macos) {
        exe_runner_mod.addObjectFile(compileCObject(
            b,
            target,
            optimize,
            b.path("../../lib/Mach-O/native_window_bridge.m"),
            "standalone_windows_route_native_window_bridge.o",
            &[_][]const u8{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
        ));
        exe_runner_mod.addObjectFile(compileCObject(
            b,
            target,
            optimize,
            b.path("../../lib/Mach-O/native_audio_bridge.m"),
            "standalone_windows_route_native_audio_bridge.o",
            &[_][]const u8{ "-fobjc-arc", "-fno-modules", "-Wall", "-Wextra" },
        ));
        exe_runner_mod.linkFramework("AppKit", .{});
        exe_runner_mod.linkFramework("QuartzCore", .{});
        exe_runner_mod.linkFramework("Metal", .{});
        exe_runner_mod.linkFramework("AudioToolbox", .{});
    }

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
        const pe64_runtime_test = b.addTest(.{ .root_module = pe64_runtime_test_module });
        check_step.dependOn(&b.addRunArtifact(pe64_runtime_test).step);
    }

    // Native Cocoa shell launched by Finder.
    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    app_mod.addObjectFile(compileCObject(
        b,
        target,
        optimize,
        b.path("src/RosetteApp.m"),
        "RosetteApp.o",
        if (is_macos)
            &[_][]const u8{ "-fobjc-arc", "-Wall", "-Wextra", "-include", "shims/macos/compiler_compat.h" }
        else
            &[_][]const u8{ "-fobjc-arc", "-Wall", "-Wextra" },
    ));
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

    const macho_processor_install = b.addInstallFile(
        b.path("../../zig-out/bin/macho_processor"),
        b.fmt("{s}.app/Contents/MacOS/macho_processor", .{app_name}),
    );
    bundle_step.dependOn(&macho_processor_install.step);

    // These companions are built by shell-update's canonical runtime gate.
    // Give them real file inputs/install steps: old, unmanaged copies in an
    // existing .app must not survive an otherwise successful bundle refresh.
    const runtime_companions = [_]struct { source: []const u8, name: []const u8 }{
        .{ .source = "../../zig-out/bin/elf_processor", .name = "elf_processor" },
        .{ .source = "../../zig-out/lib/rosette-exec.dylib", .name = "rosette-exec.dylib" },
        .{ .source = "../../zig-out/lib/avx-shim.dylib", .name = "avx-shim.dylib" },
    };
    for (runtime_companions) |companion| {
        const install = b.addInstallFile(b.path(companion.source), b.fmt("{s}.app/Contents/MacOS/{s}", .{ app_name, companion.name }));
        bundle_step.dependOn(&install.step);
    }

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
        .{ .source = "../../include/assets", .destination = "assets" },
        .{ .source = "../../lib/processor/bat_processor", .destination = "bat_processor" },
        .{ .source = "../../include", .destination = "include" },
        .{ .source = "../../lib/processor/ps1_processor", .destination = "ps1_processor" },
        .{ .source = "../../include/scripts", .destination = "scripts" },
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
        .{ .source = "../../src/tooling/exe_parser/rosette_app_exe.zig", .destination = "rosette_app_exe.zig" },
        .{ .source = "../../src/tooling/exe_parser/rosette_exe_runner.zig", .destination = "rosette_exe_runner.zig" },
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
        \\  src/tooling/exe_parser/rosette_app_exe.zig
        \\  src/tooling/exe_parser/rosette_exe_runner.zig
        \\  src/compat/rosetta2
        \\permanent blacklist:
        \\  .rosette
        \\  app_testing
        \\  assets/exe_examples
        \\  include/assets/exe_examples
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

/// Compile one C/Objective-C source into an object the Zig link can take.
///
/// `zig cc` with no flags is `-O0` with UBSan instrumentation that *calls*
/// `__ubsan_handle_*`. A Debug Zig link happens to provide those symbols, so
/// the omission was invisible; a ReleaseFast link does not, and the runner
/// would not link at all. Both halves are decided here so the C side follows
/// the Zig side's optimize mode instead of silently staying at -O0.
fn compileCObject(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    source: std.Build.LazyPath,
    output_name: []const u8,
    flags: []const []const u8,
) std.Build.LazyPath {
    const compile = b.addSystemCommand(&.{ b.graph.zig_exe, "cc" });
    if (!target.query.isNative()) {
        compile.addArg("-target");
        compile.addArg(target.result.zigTriple(b.allocator) catch @panic("OOM"));
    }
    compile.addArg(switch (optimize) {
        .Debug => "-O0",
        .ReleaseSafe, .ReleaseFast => "-O2",
        .ReleaseSmall => "-Os",
    });
    // The Zig modules keep their own safety settings; these bridges are
    // AppKit and CoreAudio glue, and their UBSan calls are what break the
    // release link.
    compile.addArg("-fno-sanitize=undefined");
    compile.addArgs(flags);
    compile.addPrefixedDirectoryArg("-I", b.path("../../include"));
    compile.addArg("-c");
    compile.addFileArg(source);
    compile.addArg("-o");
    return compile.addOutputFileArg(output_name);
}
