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
    const console_fatal_condition_map_mod = ctx.console_fatal_condition_map_mod;
    const xenia_guest_address_map_mod = ctx.xenia_guest_address_map_mod;
    const console_guest_frontier_map_mod = ctx.console_guest_frontier_map_mod;
    const console_guest_milestone_map_mod = ctx.console_guest_milestone_map_mod;
    const console_kernel_export_map_mod = ctx.console_kernel_export_map_mod;
    const console_kernel_shim_map_mod = ctx.console_kernel_shim_map_mod;
    const console_warning_severity_map_mod = ctx.console_warning_severity_map_mod;

    const x64_linux_runtime_mod = b.createModule(.{
        .root_source_file = b.path("src/x64-ASM/linux_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const x64_syscalls_mod = b.createModule(.{
        .root_source_file = b.path("src/x64-ASM/syscalls.zig"),
        .target = target,
        .optimize = optimize,
    });
    const x64_guest_abi_mod = b.createModule(.{
        .root_source_file = b.path("src/x64-ASM/guest_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    x64_linux_runtime_mod.addImport("x64_syscalls", x64_syscalls_mod);
    x64_linux_runtime_mod.addImport("windows_runtime", windows_runtime_mod);
    const elf_processor_mod = b.createModule(.{
        .root_source_file = b.path("lib/processor/ELF_processor/main.zig"),
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
    elf_processor_mod.addImport("console_fatal_condition_map", console_fatal_condition_map_mod);
    elf_processor_mod.addImport("console_guest_frontier_map", console_guest_frontier_map_mod);
    elf_processor_mod.addImport("console_warning_severity_map", console_warning_severity_map_mod);
    elf_processor_mod.addImport("console_guest_milestone_map", console_guest_milestone_map_mod);
    elf_processor_mod.addImport("console_kernel_shim_map", console_kernel_shim_map_mod);
    elf_processor_mod.addImport("console_kernel_export_map", console_kernel_export_map_mod);
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
        .root_source_file = b.path("lib/processor/ELF_processor/process.zig"),
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
    elf_processor_test_mod.addImport("console_fatal_condition_map", console_fatal_condition_map_mod);
    elf_processor_test_mod.addImport("console_guest_frontier_map", console_guest_frontier_map_mod);
    elf_processor_test_mod.addImport("console_warning_severity_map", console_warning_severity_map_mod);
    elf_processor_test_mod.addImport("console_guest_milestone_map", console_guest_milestone_map_mod);
    elf_processor_test_mod.addImport("console_kernel_shim_map", console_kernel_shim_map_mod);
    elf_processor_test_mod.addImport("console_kernel_export_map", console_kernel_export_map_mod);
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
        .root_source_file = b.path("lib/processor/ELF_processor/block_jit.zig"),
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
    const console_guest_frontier_map_test = b.addTest(.{ .root_module = console_guest_frontier_map_mod });
    check_step.dependOn(&b.addRunArtifact(console_guest_frontier_map_test).step);
    const console_warning_severity_map_test = b.addTest(.{ .root_module = console_warning_severity_map_mod });
    check_step.dependOn(&b.addRunArtifact(console_warning_severity_map_test).step);
    const console_guest_milestone_map_test = b.addTest(.{ .root_module = console_guest_milestone_map_mod });
    check_step.dependOn(&b.addRunArtifact(console_guest_milestone_map_test).step);
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
    // Xenia's GPU command processor register-write path, replayed from
    // the shipped bytes: the critical thread of Halo 3's heavy scenes.
    const command_replay_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{"Xenia command replay"} });
    // Timing: ROSETTE_COMMAND_REPLAY_BENCH=1 zig build xenia-command-replay-check -Doptimize=ReleaseFast
    b.step("xenia-command-replay-check", "Replay Xenia's command-processor register writes interpreted and translated").dependOn(&b.addRunArtifact(command_replay_test).step);
    // Translated-code working set: per-block cost as the number of distinct
    // hot blocks grows. Timing: ROSETTE_CODE_WORKING_SET_BENCH=1 zig build
    // code-working-set-check -Doptimize=ReleaseFast
    const stdio_flush_test = b.addTest(.{ .root_module = windows_runtime_mod, .filters = &.{ "stdio flush", "CRT file", "wide mode", "standard stream", "file", "descriptor", "media" } });
    b.step("stdio-flush-check", "Check CRT flush commit modes, file contents and complete handler costs offline").dependOn(&b.addRunArtifact(stdio_flush_test).step);
    const far_link_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "far links", "branch islands", "direct links:", "chain recycling", "native hops", "native first successor", "abort", "TSO" } });
    b.step("far-links-check", "Check distant native branch veneers and data-bearing shuffled translator loops offline").dependOn(&b.addRunArtifact(far_link_test).step);
    const working_set_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "code working set", "chain recycling", "direct links", "native hops", "native first successor", "internal edge", "chain", "a call keeps its link" } });
    b.step("code-working-set-check", "Check split code layout and block-named chain links, and measure block cost against distinct hot blocks").dependOn(&b.addRunArtifact(working_set_test).step);
    // Win32 mutex ownership in the wait model, the semantics Xenia's
    // XMutant hands every Xbox 360 mutant to. Run 20261012T000703Z stopped
    // on a recursive acquisition the model could not express.
    const windows_mutex_check = b.step("windows-mutex-check", "Run the Win32 mutex ownership, recursion and hand-over regressions");
    const windows_mutex_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{ "a mutex's owner", "released mutex belongs", "initially owned mutex", "wait takes a mutex", "exits owning a mutex", "ERROR_NOT_OWNER", "custom-game stall", "contract: " },
    });
    windows_mutex_check.dependOn(&b.addRunArtifact(windows_mutex_test).step);
    const expansion_check = b.step("vector-expansion-check", "Check compact permutation and native YMM unpack production loops");
    const expansion_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "vector expansion", "compact permutation", "YMM unpack", "worker runtime pulse", "VPERMILPS with a control", "SSE oracle" } });
    expansion_check.dependOn(&b.addRunArtifact(expansion_test).step);
    const math_check = b.step("windows-math-check", "Check exact pure-math imports and translated IAT transfers offline");
    const math_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "fast math", "native vector extraction" } });
    math_check.dependOn(&b.addRunArtifact(math_test).step);
    const yield_check = b.step("windows-yield-check", "Check zero-delay NT imports and bounded PAUSE scheduling offline");
    const yield_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "NT zero-delay", "PAUSE", "parallel pause", "an NT delay", "NtDelayExecution", "back-off", "Sleep(0)", "worker yield backoff", "native shader compile", "frame cost" } });
    yield_check.dependOn(&b.addRunArtifact(yield_test).step);
    const pause_check = b.step("pause-cpu-check", "Check translated PAUSE boundaries and CPU backoff offline");
    const pause_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "translated PAUSE", "PAUSE", "spin watch", "chain", "native hop" } });
    pause_check.dependOn(&b.addRunArtifact(pause_test).step);
    const critical_cpu_check = b.step("critical-cpu-check", "Check transient PAUSE admission and scalar floating residency offline");
    const critical_cpu_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "PAUSE policy recheck", "scalar residency", "translated PAUSE", "scalar float", "scalar arithmetic" } });
    critical_cpu_check.dependOn(&b.addRunArtifact(critical_cpu_test).step);
    const frame_work_check = b.step("frame-work-check", "Check ordinary import metadata and fence host CPU offline");
    const frame_work_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "import metadata", "worker host CPU", "native Vulkan refusal", "Windows import ABI", "registered import tail" } });
    frame_work_check.dependOn(&b.addRunArtifact(frame_work_test).step);
    const routing_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "wait lookup", "worker host CPU", "NT event", "NT wait", "wait object", "mutex ownership" } });
    b.step("import-routing-check", "Check cached wait-object lookup with ordinary NT semantics").dependOn(&b.addRunArtifact(routing_test).step);
    const operand_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "register operands", "native first successor", "direct scalar paths", "flags", "fused", "shift", "rotate", "carry", "borrow", "memory operands", "MOVBE", "locked", "TSO" } });
    b.step("register-operands-check", "Check native cached variable shifts, conversions and multiply offline").dependOn(&b.addRunArtifact(operand_test).step);
    const chain_layout_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "native first successor", "direct scalar paths", "flags", "fused", "carry", "borrow", "shift", "rotate", "register arithmetic", "cached register", "native hops", "emitted code writes", "arithmetic throughput", "natural scalar lanes", "locked", "exchange", "TSO", "internal edge" } });
    b.step("native-chain-layout-check", "Check native chain branch layout and ordinary state publication offline").dependOn(&b.addRunArtifact(chain_layout_test).step);
    const arithmetic_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "arithmetic throughput", "natural scalar lanes", "TLB unaligned lanes", "register arithmetic", "flags", "fused", "carry", "borrow", "internal edge", "native hops", "locked", "exchange", "TSO" } });
    b.step("arithmetic-throughput-check", "Check exact eager arithmetic flags and native CPU throughput").dependOn(&b.addRunArtifact(arithmetic_test).step);
    const cpu_throughput_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "CPU throughput", "fast math", "rearrangement residency", "protection", "wait cost" } });
    b.step("cpu-throughput-check", "Check packed protection updates, signal indexing, math and vector residency offline").dependOn(&b.addRunArtifact(cpu_throughput_test).step);
    const completion_check = b.step("native-completion-check", "Check native scalar/vector completion and sampled timing maxima offline");
    const completion_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "native completion", "sampled timing maximum", "histogram counts", "ordered vector TLB", "vector loads and stores", "legacy MOVUPS", "divides", "division", "guarded divide" } });
    completion_check.dependOn(&b.addRunArtifact(completion_test).step);
    const atomic_check = b.step("atomic-cpu-check", "Check exact native atomic templates and ordering offline");
    const atomic_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "atomic update", "atomic compare", "atomic failed compare", "locked", "cmpxchg", "native atomic", "atomic store", "TSO", "worker host CPU" } });
    atomic_check.dependOn(&b.addRunArtifact(atomic_test).step);
    const register_check = b.step("register-import-check", "Check fused registered import tail jumps offline");
    const register_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "registered import tail", "fast math", "NT zero-delay" } });
    register_check.dependOn(&b.addRunArtifact(register_test).step);
    const worker_yield_mod = b.createModule(.{
        .root_source_file = b.path("lib/processor/ELF_processor/process/impl/worker_yield_bench.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    worker_yield_mod.addImport("parallelism", parallelism_mod);
    worker_yield_mod.addImport("concurrency", concurrency_mod);
    const worker_yield_check = b.step("worker-yield-check", "Check and measure bounded explicit worker-yield backoff offline");
    const worker_yield_test = b.addTest(.{ .root_module = worker_yield_mod });
    worker_yield_check.dependOn(&b.addRunArtifact(worker_yield_test).step);
    check_step.dependOn(&b.addRunArtifact(worker_yield_test).step);
    const retirement_check = b.step("retirement-flush-check", "Check indexed FSI recycling and TLB invalidation filters without GPU work");
    for ([_][]const u8{ "lib/gpu/retirement_tests.zig", "lib/processor/ELF_processor/block_jit/tlb_invalidation_tests.zig" }, 0..) |path, index| {
        const module = b.createModule(.{ .root_source_file = b.path(path), .target = target, .optimize = optimize, .link_libc = true });
        const run = b.addRunArtifact(b.addTest(.{ .root_module = module }));
        const focused = b.step(if (index == 0) "recycling-check" else "tlb-flush-check", if (index == 0) "Check FSI continuation recycling and recording retirement offline" else "Check cross-executor TLB invalidation and fill costs offline");
        focused.dependOn(&run.step);
        retirement_check.dependOn(focused);
        check_step.dependOn(&run.step);
    }
    const flush_cpu_check = b.step("flush-cpu-check", "Check native TLB probes, protection, alias lifetimes, write watch and parallel ordering");
    const flush_cpu_test = b.addTest(.{ .root_module = elf_processor_test_mod, .filters = &.{ "TLB", "TLBs", "tlb", "mapped alias", "page protection", "parallel mapped", "ordered vector", "a spin watch", "native pipeline", "native shader compile" } });
    flush_cpu_check.dependOn(&b.addRunArtifact(flush_cpu_test).step);
    const windows_bsearch_check = b.step("windows-bsearch-check", "Run the Windows CRT bsearch callback and import-routing regressions");
    const windows_bsearch_test = b.addTest(.{
        .root_module = elf_processor_test_mod,
        .filters = &.{"Windows bsearch"},
    });
    windows_bsearch_check.dependOn(&b.addRunArtifact(windows_bsearch_test).step);
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
        .root_source_file = b.path("lib/processor/ELF_processor/windows_graphics.zig"),
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
        .root_source_file = b.path("src/tooling/exe_parser/pe64_runtime.zig"),
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
