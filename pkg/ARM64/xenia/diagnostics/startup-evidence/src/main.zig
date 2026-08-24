const std = @import("std");
const evidence = @import("evidence.zig");

const usage =
    \\usage: xenia-arm64-startup-evidence <ready-compiler.log> <runtime.log>
    \\
    \\Reads route-local evidence and prints the activation frontier. It never
    \\changes the log or modifies runtime state.
    \\
;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (args.len != 3 or std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        try stdout.writeAll(usage);
        try stdout.flush();
        return;
    }

    var report = evidence.Report{};
    for (args[1..]) |path| {
        const text = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(512 * 1024 * 1024));
        report.ingest(text);
    }

    try stdout.print(
        "package_hit={} package_store={} compile_green={} unknown={d} lines={d}\n",
        .{ report.package_hit, report.package_store, report.compile_green, report.compile_unknown, report.lines_seen },
    );
    try stdout.print(
        "frontier={s} blocked_kind={s} blocked_step={d}\n",
        .{
            if (report.frontier()) |stage| stage.label() else "<complete>",
            if (report.blocked_kind.len != 0) report.blocked_kind else "<none>",
            report.blocked_step,
        },
    );
    try stdout.print(
        "blocks={d}/{d} edges={d}/{d} activation_budget={d} activation_budget_mode={s} last_progress={d} precompile_cost={d}\n",
        .{
            report.contract_blocks_reached,
            report.contract_blocks_total,
            report.contract_edges_reached,
            report.contract_blocks_total + 1,
            report.activation_budget_steps,
            if (report.activation_budget_unlimited) "unlimited" else "finite",
            report.last_progress_step,
            report.precompile_cost_steps,
        },
    );
    try stdout.print(
        "tracepoints={d}/{d} swap_tracepoints={d} swap_hits={d}\n",
        .{ report.tracepoints_armed, report.tracepoints_unresolved, report.swap_tracepoints, report.swap_hits },
    );
    try stdout.print(
        "preinit={d}/{d} kernel_variables={d}/{d} kernel_writes={d}\n",
        .{ report.preinit_established, report.preinit_total, report.kernel_variables_imported, report.kernel_variables_usable, report.kernel_variable_writes },
    );
    try stdout.print(
        "vulkan_calls={d} native_submissions={d} native_present_requests={d} guest_output_frames={d} tier_consistent={}\n",
        .{ report.guest_vulkan_calls, report.native_submissions, report.native_present_requests, report.guest_output_frames, report.vulkan_tier_consistent },
    );
    try stdout.print(
        "threads_active={d} threads_parked={d} ring_writes={d} ring_advances={d}\n",
        .{ report.active_threads, report.parked_threads, report.ring_writes, report.ring_advances },
    );
    try stdout.print(
        "scheduler={d}/{d} wait_notifications={d} wait_consumption_warning={} gpu_aperture={d}/{d}\n",
        .{
            report.scheduler_runnable,
            report.scheduler_parked,
            report.wait_notifications,
            report.wait_consumption_warning,
            report.gpu_aperture_reads,
            report.gpu_aperture_writes,
        },
    );
    try stdout.print("verdict={s}\n", .{report.verdict().label()});
    try stdout.flush();
}
