//! Folder-owned build registration. Paths use the master build root.
const std = @import("std");
const builtin = @import("builtin");

pub fn register0(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const gfx_abi_mod = b.createModule(.{
        .root_source_file = b.path("src/x86-ASM/graphics/abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    gfx_abi_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const gfx_abi_test = b.addTest(.{ .root_module = gfx_abi_mod });
    check_step.dependOn(&gfx_abi_test.step);
}

pub fn register1(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const runtime_abi_module = ctx.runtime_abi_module;

    const runtime_abi_test = b.addTest(.{ .root_module = runtime_abi_module });
    check_step.dependOn(&runtime_abi_test.step);
}

pub fn register2(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const entrypoint_stack_alignment_module = ctx.entrypoint_stack_alignment_module;

    const stack_alignment_test = b.addTest(.{ .root_module = entrypoint_stack_alignment_module });
    check_step.dependOn(&stack_alignment_test.step);
}

pub fn register3(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const entrypoint_shadow_stack_validation_module = ctx.entrypoint_shadow_stack_validation_module;

    const shadow_stack_validation_test = b.addTest(.{ .root_module = entrypoint_shadow_stack_validation_module });
    check_step.dependOn(&shadow_stack_validation_test.step);
}

pub fn register4(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const isa_module = ctx.isa_module;

    const isa_test = b.addTest(.{ .root_module = isa_module });
    check_step.dependOn(&isa_test.step);
}

pub fn register5(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const svx_module = ctx.svx_module;

    const svx_test = b.addTest(.{ .root_module = svx_module });
    check_step.dependOn(&b.addRunArtifact(svx_test).step);
}

pub fn register6(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const cleo_module = ctx.cleo_module;

    const cleo_test = b.addTest(.{ .root_module = cleo_module });
    check_step.dependOn(&b.addRunArtifact(cleo_test).step);
}

pub fn register7(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const contract_mod = ctx.contract_mod;

    const contract_test = b.addTest(.{ .root_module = contract_mod });
    check_step.dependOn(&b.addRunArtifact(contract_test).step);
}

pub fn register8(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const jit_mod = ctx.jit_mod;

    const jit_test = b.addTest(.{ .root_module = jit_mod });
    check_step.dependOn(&b.addRunArtifact(jit_test).step);
}

pub fn register9(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const ppc_decode_module = ctx.ppc_decode_module;

    const ppc_decode_check = b.addTest(.{ .root_module = ppc_decode_module });
    check_step.dependOn(&b.addRunArtifact(ppc_decode_check).step);
}

pub fn register10(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const ppc_runtime_module = ctx.ppc_runtime_module;

    const ppc_runtime_check = b.addTest(.{ .root_module = ppc_runtime_module });
    check_step.dependOn(&b.addRunArtifact(ppc_runtime_check).step);
}

pub fn register11(b: *std.Build, ctx: anytype) void {
    const arm64_encode_module = ctx.arm64_encode_module;
    const check_step = ctx.check_step;

    const arm64_encode_check = b.addTest(.{ .root_module = arm64_encode_module });
    check_step.dependOn(&b.addRunArtifact(arm64_encode_check).step);
}

pub fn register12(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const target = ctx.target;

    // Xbox 360 XEX2 image reading, for running a title against the PowerPC
    // runtime without Xenia owning the module load.
    const xex_module = b.createModule(.{
        .root_source_file = b.path("lib/linker/xex/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xex_check = b.addTest(.{ .root_module = xex_module });
    check_step.dependOn(&b.addRunArtifact(xex_check).step);
}

pub fn register13(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const ppc_decode_module = ctx.ppc_decode_module;
    const target = ctx.target;

    // The PowerPC encoder, and the exhaustive round trip that is its
    // specification. The decoder could already recognise every opcode;
    // until this existed nothing could produce one, which is the half of
    // the ISA layer that was actually missing.
    const ppc_encode_mod = b.createModule(.{
        .root_source_file = b.path("ISA/ppc/encode/encoder.zig"),
        .target = target,
        .optimize = optimize,
    });
    ppc_encode_mod.addImport("ppc_decode", ppc_decode_module);
    const ppc_encode_test = b.addTest(.{ .root_module = ppc_encode_mod });
    check_step.dependOn(&b.addRunArtifact(ppc_encode_test).step);
}

pub fn register14(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const isa_ppc_test_mod = b.createModule(.{
        .root_source_file = b.path("ISA/ppc_test_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    isa_ppc_test_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const isa_ppc_test = b.addTest(.{ .root_module = isa_ppc_test_mod });
    check_step.dependOn(&b.addRunArtifact(isa_ppc_test).step);
}

pub fn register15(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const isa_math_test_mod = b.createModule(.{
        .root_source_file = b.path("ISA/Math/test_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    isa_math_test_mod.addImport("runtime_abi_handshake", runtime_abi_module);
    const isa_math_test = b.addTest(.{ .root_module = isa_math_test_mod });
    check_step.dependOn(&b.addRunArtifact(isa_math_test).step);
}

pub fn register16(b: *std.Build, ctx: anytype) void {
    const bridge_dos_runtime_module = ctx.bridge_dos_runtime_module;
    const bridge_exceptions_module = ctx.bridge_exceptions_module;
    const bridge_flags_module = ctx.bridge_flags_module;
    const bridge_heap_module = ctx.bridge_heap_module;
    const bridge_instruction_decoding_module = ctx.bridge_instruction_decoding_module;
    const bridge_memory_module = ctx.bridge_memory_module;
    const bridge_register_trace_module = ctx.bridge_register_trace_module;
    const bridge_stack_module = ctx.bridge_stack_module;
    const bridge_string_ops_module = ctx.bridge_string_ops_module;
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const dos_exec_mod = b.createModule(.{
        .root_source_file = b.path("src/DOS/runtime_root.zig"),
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

pub fn register17(b: *std.Build, ctx: anytype) void {
    const bridge_exceptions_module = ctx.bridge_exceptions_module;
    const bridge_flags_module = ctx.bridge_flags_module;
    const bridge_heap_module = ctx.bridge_heap_module;
    const bridge_instruction_decoding_module = ctx.bridge_instruction_decoding_module;
    const bridge_memory_module = ctx.bridge_memory_module;
    const bridge_register_trace_module = ctx.bridge_register_trace_module;
    const bridge_stack_module = ctx.bridge_stack_module;
    const bridge_string_ops_module = ctx.bridge_string_ops_module;
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const x64_state_mod = b.createModule(.{
        .root_source_file = b.path("src/x64-ASM/x64_state.zig"),
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

pub fn register18(b: *std.Build, ctx: anytype) void {
    const bridge_exceptions_module = ctx.bridge_exceptions_module;
    const bridge_flags_module = ctx.bridge_flags_module;
    const bridge_heap_module = ctx.bridge_heap_module;
    const bridge_instruction_decoding_module = ctx.bridge_instruction_decoding_module;
    const bridge_memory_module = ctx.bridge_memory_module;
    const bridge_register_trace_module = ctx.bridge_register_trace_module;
    const bridge_stack_module = ctx.bridge_stack_module;
    const bridge_string_ops_module = ctx.bridge_string_ops_module;
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const x64_addr_mod = b.createModule(.{
        .root_source_file = b.path("src/x64-ASM/addressing64.zig"),
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

pub fn register19(b: *std.Build, ctx: anytype) void {
    const arm64_exceptions_module = ctx.arm64_exceptions_module;
    const bridge_exceptions_module = ctx.bridge_exceptions_module;
    const bridge_flags_module = ctx.bridge_flags_module;
    const bridge_heap_module = ctx.bridge_heap_module;
    const bridge_instruction_decoding_module = ctx.bridge_instruction_decoding_module;
    const bridge_memory_module = ctx.bridge_memory_module;
    const bridge_register_trace_module = ctx.bridge_register_trace_module;
    const bridge_stack_module = ctx.bridge_stack_module;
    const bridge_string_ops_module = ctx.bridge_string_ops_module;
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const target = ctx.target;

    const arm64_trace_mod = b.createModule(.{
        .root_source_file = b.path("src/arm64/register-tracing/runtime.zig"),
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

pub fn register20(b: *std.Build, ctx: anytype) void {
    const behavior_module = ctx.behavior_module;
    const behavior_zig_module = ctx.behavior_zig_module;
    const check_step = ctx.check_step;
    const dll_translator_module = ctx.dll_translator_module;
    const dos_palette_module = ctx.dos_palette_module;
    const dos_platform_module = ctx.dos_platform_module;
    const dos_renderer_module = ctx.dos_renderer_module;
    const dos_scene_module = ctx.dos_scene_module;
    const is_macos = ctx.is_macos;
    const mmsystem_module = ctx.mmsystem_module;
    const optimize = ctx.optimize;
    const runtime_abi_module = ctx.runtime_abi_module;
    const shim_surface_module = ctx.shim_surface_module;
    const sysdefs_module = ctx.sysdefs_module;
    const target = ctx.target;
    const win32_all_module = ctx.win32_all_module;
    const win32_pending_module = ctx.win32_pending_module;
    const windows_base_module = ctx.windows_base_module;
    const x86_asm_module = ctx.x86_asm_module;

    const abi_suite_mod = b.createModule(.{
        .root_source_file = b.path("include/win32/Zig/abi_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (is_macos) abi_suite_mod.addIncludePath(b.path("include/shims/macos"));
    abi_suite_mod.addIncludePath(b.path("include/shims/win32"));
    abi_suite_mod.addIncludePath(b.path("include"));
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
