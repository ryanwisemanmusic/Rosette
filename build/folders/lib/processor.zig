//! Folder-owned build registration. Paths use the master build root.
const std = @import("std");
const builtin = @import("builtin");

pub fn register0(b: *std.Build, ctx: anytype) void {
    const address_region_map_mod = ctx.address_region_map_mod;
    const arm64_encode_module = ctx.arm64_encode_module;
    const check_step = ctx.check_step;
    const cleo_routing_mod = ctx.cleo_routing_mod;
    const concurrency_mod = ctx.concurrency_mod;
    const concurrency_test = ctx.concurrency_test;
    const evex_runtime_mod = ctx.evex_runtime_mod;
    const execution_history_mod = ctx.execution_history_mod;
    const exit_diagnostics_module = ctx.exit_diagnostics_module;
    const frame_content_contract_mod = ctx.frame_content_contract_mod;
    const optimize = ctx.optimize;
    const parallelism_mod = ctx.parallelism_mod;
    const run_setcc_stack_regression_test = ctx.run_setcc_stack_regression_test;
    const screen_validity_mod = ctx.screen_validity_mod;
    const target = ctx.target;
    const tso_memory_mod = ctx.tso_memory_mod;
    const tso_memory_test = ctx.tso_memory_test;
    const windows_runtime_mod = ctx.windows_runtime_mod;
    const windows_runtime_test = ctx.windows_runtime_test;
    const x64_decoder_mod = ctx.x64_decoder_mod;
    const x64_interpreter_mod = ctx.x64_interpreter_mod;
    const x86_vector_helpers_mod = ctx.x86_vector_helpers_mod;
    const xenia_fatal_condition_map_mod = ctx.xenia_fatal_condition_map_mod;
    const xenia_guest_address_map_mod = ctx.xenia_guest_address_map_mod;
    const xenia_guest_frontier_map_mod = ctx.xenia_guest_frontier_map_mod;
    const xenia_guest_milestone_map_mod = ctx.xenia_guest_milestone_map_mod;
    const xenia_kernel_export_map_mod = ctx.xenia_kernel_export_map_mod;
    const xenia_kernel_shim_map_mod = ctx.xenia_kernel_shim_map_mod;
    const xenia_warning_severity_map_mod = ctx.xenia_warning_severity_map_mod;

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
    x64_linux_runtime_mod.addImport("windows_runtime", windows_runtime_mod);
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
    elf_processor_mod.addImport("evex_runtime", evex_runtime_mod);
    elf_processor_mod.addImport("x86_vector_helpers", x86_vector_helpers_mod);
    elf_processor_mod.addImport("xenia_fatal_condition_map", xenia_fatal_condition_map_mod);
    elf_processor_mod.addImport("xenia_guest_frontier_map", xenia_guest_frontier_map_mod);
    elf_processor_mod.addImport("xenia_warning_severity_map", xenia_warning_severity_map_mod);
    elf_processor_mod.addImport("xenia_guest_milestone_map", xenia_guest_milestone_map_mod);
    elf_processor_mod.addImport("xenia_kernel_shim_map", xenia_kernel_shim_map_mod);
    elf_processor_mod.addImport("xenia_kernel_export_map", xenia_kernel_export_map_mod);
    elf_processor_mod.addImport("xenia_guest_address_map", xenia_guest_address_map_mod);
    elf_processor_mod.addImport("frame_content_contract", frame_content_contract_mod);
    elf_processor_mod.addImport("screen_validity", screen_validity_mod);
    elf_processor_mod.addImport("address_region_map", address_region_map_mod);
    elf_processor_mod.addImport("arm64_encode", arm64_encode_module);
    elf_processor_mod.addImport("tso_memory", tso_memory_mod);
    elf_processor_mod.addImport("concurrency", concurrency_mod);
    elf_processor_mod.addImport("parallelism", parallelism_mod);
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
    elf_processor_test_mod.addImport("evex_runtime", evex_runtime_mod);
    elf_processor_test_mod.addImport("x86_vector_helpers", x86_vector_helpers_mod);
    elf_processor_test_mod.addImport("xenia_fatal_condition_map", xenia_fatal_condition_map_mod);
    elf_processor_test_mod.addImport("xenia_guest_frontier_map", xenia_guest_frontier_map_mod);
    elf_processor_test_mod.addImport("xenia_warning_severity_map", xenia_warning_severity_map_mod);
    elf_processor_test_mod.addImport("xenia_guest_milestone_map", xenia_guest_milestone_map_mod);
    elf_processor_test_mod.addImport("xenia_kernel_shim_map", xenia_kernel_shim_map_mod);
    elf_processor_test_mod.addImport("xenia_kernel_export_map", xenia_kernel_export_map_mod);
    elf_processor_test_mod.addImport("xenia_guest_address_map", xenia_guest_address_map_mod);
    elf_processor_test_mod.addImport("frame_content_contract", frame_content_contract_mod);
    elf_processor_test_mod.addImport("screen_validity", screen_validity_mod);
    elf_processor_test_mod.addImport("address_region_map", address_region_map_mod);
    elf_processor_test_mod.addImport("arm64_encode", arm64_encode_module);
    elf_processor_test_mod.addImport("tso_memory", tso_memory_mod);
    elf_processor_test_mod.addImport("concurrency", concurrency_mod);
    elf_processor_test_mod.addImport("parallelism", parallelism_mod);
    // The ARM64 translator has an independent focused check. Its tests
    // share the production implementation module but do not need to compile
    // the full PE process graph when only block-jit files change.
    const block_jit_test_mod = b.createModule(.{
        .root_source_file = b.path("../lib/processor/ELF_processor/block_jit.zig"),
        .target = target,
        .optimize = optimize,
    });
    block_jit_test_mod.addImport("arm64_encode", arm64_encode_module);
    block_jit_test_mod.addImport("x64_decoder", x64_decoder_mod);
    const block_jit_test = b.addTest(.{ .root_module = block_jit_test_mod });
    const block_jit_check = b.step("block-jit-check", "Run the ARM64 block translator's focused regression suite");
    block_jit_check.dependOn(&b.addRunArtifact(block_jit_test).step);
    // Rooted so the frontier classification rules execute rather than
    // only compile as the ELF processor's dependency. A shadowed rule is
    // invisible at runtime and only shows up as a workload nobody names.
    const xenia_guest_frontier_map_test = b.addTest(.{ .root_module = xenia_guest_frontier_map_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_guest_frontier_map_test).step);
    const xenia_warning_severity_map_test = b.addTest(.{ .root_module = xenia_warning_severity_map_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_warning_severity_map_test).step);
    const xenia_guest_milestone_map_test = b.addTest(.{ .root_module = xenia_guest_milestone_map_mod });
    check_step.dependOn(&b.addRunArtifact(xenia_guest_milestone_map_test).step);
    ctx.windows_graphics_state_test_mod.* = elf_processor_test_mod;
    const windows_graphics_contract_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{ "title worker code-cache", "native Vulkan refusal", "first-frame chain" },
    });
    const windows_graphics_contract_check = b.step("windows-graphics-check", "Run PE graphics evidence and native routing regression tests");
    windows_graphics_contract_check.dependOn(&b.addRunArtifact(windows_graphics_contract_test).step);
    const elf_processor_test = b.addTest(.{ .root_module = elf_processor_test_mod });
    const render_cpu_check = b.step("render-cpu-check", "Run vector memory and vector-test regressions without the full check suite");
    const render_cpu_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{ "ordered vector TLB", "VTEST sign", "vptest reduces", "vector loads and stores", "plain [base+disp]", "non-temporal vector stores", "legacy MOVUPS", "parallel PAUSE batches", "PAUSE fast dispatch", "SRW import lane", "SRW owner stack", "SRW acquire and release", "an SRW release hands", "Vulkan queue waits", "MXCSR flush", "Xenia's hot vector and MXCSR" },
    });
    // The image-corpus executor sweeps run thousands of interpreted and
    // translated programs; `check` skips them and this step turns them on.
    const render_cpu_run = b.addRunArtifact(render_cpu_test);
    render_cpu_run.setEnvironmentVariable("ROSETTE_EXECUTOR_SWEEP", "1");
    render_cpu_check.dependOn(&render_cpu_run.step);
    // Replays of Xenia's own compiled code for Halo 3's clear path, quick
    // to rerun while chasing a CPU defect the GPU only shows as a colour.
    const halo3_clear_check = b.step("halo3-clear-check", "Replay Xenia's compiled Halo 3 clear-colour code and check every VEX form's operand sources");
    const halo3_clear_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{ "Halo 3's clear-colour", "operand sources", "SSE oracle", "shifts by an xmm count" },
    });
    halo3_clear_check.dependOn(&b.addRunArtifact(halo3_clear_test).step);
    // Win32 mutex ownership in the wait model, the semantics Xenia's
    // XMutant hands every Xbox 360 mutant to. Run 20261012T000703Z stopped
    // on a recursive acquisition the model could not express.
    const windows_mutex_check = b.step("windows-mutex-check", "Run the Win32 mutex ownership, recursion and hand-over regressions");
    const windows_mutex_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{ "a mutex's owner", "released mutex belongs", "initially owned mutex", "wait takes a mutex", "exits owning a mutex", "ERROR_NOT_OWNER", "custom-game stall", "contract: " },
    });
    windows_mutex_check.dependOn(&b.addRunArtifact(windows_mutex_test).step);
    const sse_oracle_check = b.step("sse-oracle-check", "Compare every VEX.128 register form Xenia's JIT emits with native SSE results");
    const sse_oracle_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{"SSE oracle"},
    });
    sse_oracle_check.dependOn(&b.addRunArtifact(sse_oracle_test).step);
    const reference_count_check = b.step("reference-count-check", "Run grouped LOCK decoding and concurrent Xenia object lifetime regressions");
    const reference_count_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{ "Xenia reference-count", "Xenia XObject release" },
    });
    reference_count_check.dependOn(&b.addRunArtifact(reference_count_test).step);
    reference_count_check.dependOn(&run_setcc_stack_regression_test.step);
    check_step.dependOn(&b.addRunArtifact(elf_processor_test).step);
    // The PE execution core on its own: the processor, the guest memory
    // model and the Win32 runtime, without the rest of `check`.
    const elf_check = b.step("elf-check", "Run the ELF/PE processor, TSO memory-model and Win32 runtime tests");
    elf_check.dependOn(&b.addRunArtifact(elf_processor_test).step);
    elf_check.dependOn(&b.addRunArtifact(tso_memory_test).step);
    elf_check.dependOn(&b.addRunArtifact(concurrency_test).step);
    elf_check.dependOn(&b.addRunArtifact(windows_runtime_test).step);
    // The translator's own costs - a native hop, a relink through the
    // glue, a guest memory access - on fixed x86-64 programs. Run it
    // with `ROSETTE_BLOCK_JIT_BENCH=1 zig build block-jit-bench
    // -Doptimize=ReleaseFast`; without the variable the test skips.
    const block_jit_bench_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{"block jit benchmark"},
    });
    const block_jit_bench = b.step("block-jit-bench", "Measure the block translator on fixed programs (ROSETTE_BLOCK_JIT_BENCH=1, -Doptimize=ReleaseFast)");
    block_jit_bench.dependOn(&b.addRunArtifact(block_jit_bench_test).step);
    const throughput_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{ "hoist", "upper clear", "256-bit", "vector moves", "legacy scalar", "TLB", "chain", "cached", "constructor", "memory operands reach", "vector loads and stores", "non-temporal vector stores", "Halo 3's clear-colour", "SSE oracle", "native hop", "busy guest registers", "emitted code writes", "graphics ledger", "native guest forwarding", "host event pump", "ready native window", "native Vulkan refusal", "shader advisory", "virtual controller" },
    });
    const stall_watch_check = b.step("stall-watch-check", "Check bounded automatic write-watch leases and restored fast admission");
    const stall_watch_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{"spin watch"} });
    stall_watch_check.dependOn(&b.addRunArtifact(stall_watch_test).step);
    const throughput_check = b.step("throughput-check", "Check page hoists, ordered memory, block chaining and Halo clear semantics without the full suite");
    throughput_check.dependOn(&b.addRunArtifact(throughput_test).step);
    const graphics_ledger_mod = b.createModule(.{
        .root_source_file = b.path("../lib/processor/ELF_processor/windows_graphics.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    graphics_ledger_mod.addImport("frame_content_contract", frame_content_contract_mod);
    const graphics_ledger_check = b.step("graphics-ledger-check", "Check the host graphics contract independently of the ELF/PE executor");
    const graphics_ledger_test = b.addTest(.{ .root_module = graphics_ledger_mod });
    const run_graphics_ledger_test = b.addRunArtifact(graphics_ledger_test);
    graphics_ledger_check.dependOn(&run_graphics_ledger_test.step);
    check_step.dependOn(&run_graphics_ledger_test.step);
    const pe64_runtime_test_mod = b.createModule(.{
        .root_source_file = b.path("../src/tooling/exe_parser/pe64_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    pe64_runtime_test_mod.addImport("x64_decoder", x64_decoder_mod);
    pe64_runtime_test_mod.addImport("elf_processor_state", elf_processor_test_mod);
    pe64_runtime_test_mod.addImport("windows_runtime", windows_runtime_mod);
    pe64_runtime_test_mod.addImport("evex_runtime", evex_runtime_mod);
    pe64_runtime_test_mod.addImport("cleo_routing", cleo_routing_mod);
    pe64_runtime_test_mod.addImport("x86_vector_helpers", x86_vector_helpers_mod);
    const pe64_runtime_test = b.addTest(.{ .root_module = pe64_runtime_test_mod });
    check_step.dependOn(&b.addRunArtifact(pe64_runtime_test).step);

    const x64_guest_abi_test = b.addTest(.{ .root_module = x64_guest_abi_mod });
    check_step.dependOn(&b.addRunArtifact(x64_guest_abi_test).step);
}
