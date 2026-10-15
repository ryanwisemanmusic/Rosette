//! Fallback elapsed samples; maxima cover sampled calls only, not all calls.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const __process_std = I._std;
const __process_log = I._log;
const __process_block_jit = I._block_jit;
const __process_BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD = I._BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD;
const ElfState = process.ElfState;
const __state_BlockJitFallbackView = View;
pub const View = struct {
    /// "" for the owner's translator, "WORKER " for the workers' sum.
    label: []const u8,
    calls: u64,
    ops: *const [ElfState.op_value_limit]u64,
    samples: *const [ElfState.op_value_limit]u64,
    maxima: *const [ElfState.op_value_limit]u64,
    nanos: *const [ElfState.op_value_limit]u64,
    reasons: *const [@typeInfo(I._block_jit.FallbackReason).@"enum".fields.len]u64,
};

const __state_op_names = process.ElfState.__StateInternals._op_names;
pub fn reportBlockJitFallbackView(view: __state_BlockJitFallbackView) void {
    if (view.calls == 0) {
        __process_log.info("PE64 BLOCK JIT {s}FALLBACK OPS: none", .{view.label});
        __process_log.info("PE64 BLOCK JIT {s}FALLBACK LEDGER: calls=0 reasons(missing_native_template/native_slow_path/hook_observation/vector_policy_disabled)=0/0/0/0 samples=0 sampled_host_ns=0 estimated_interpreter_ns=0 per_op_sample_period={d}", .{ view.label, __process_BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD });
        return;
    }
    var ranked: [12]usize = undefined;
    var ranked_count: usize = 0;
    for (view.ops, 0..) |count, op_index| {
        if (count == 0) continue;
        var position = ranked_count;
        while (position > 0 and view.ops[ranked[position - 1]] < count) : (position -= 1) {}
        if (position >= ranked.len) continue;
        var cursor = @min(ranked_count, ranked.len - 1);
        while (cursor > position) : (cursor -= 1) ranked[cursor] = ranked[cursor - 1];
        ranked[position] = op_index;
        if (ranked_count < ranked.len) ranked_count += 1;
    }
    var buffer: [2048]u8 = undefined;
    var written: usize = 0;
    for (ranked[0..ranked_count]) |op_index| {
        const name = __state_op_names[op_index] orelse continue;
        const count = view.ops[op_index];
        const percent = @divTrunc(count *| 100, view.calls);
        const samples = view.samples[op_index];
        const sampled_ns = view.nanos[op_index];
        const estimated_ns: u64 = if (samples == 0) 0 else @intCast(@min(
            (@as(u128, sampled_ns) * @as(u128, count)) / @as(u128, samples),
            @as(u128, __process_std.math.maxInt(u64)),
        ));
        const piece = __process_std.fmt.bufPrint(buffer[written..], " {s}={d}({d}%,estimated_ns={d},samples={d})", .{ name, count, percent, estimated_ns, samples }) catch break;
        written += piece.len;
    }
    __process_log.info("PE64 BLOCK JIT {s}FALLBACK OPS:{s}; each is an instruction the translator hands to the interpreter one at a time; estimated_ns is a per-operation sampled host-time estimate, not guest time", .{ view.label, buffer[0..written] });
    for (view.ops, 0..) |count, op_index| {
        if (count == 0) continue;
        const name = __state_op_names[op_index] orelse continue;
        __process_log.info("PE64 FALLBACK TIMING: scope='{s}' op={s} calls={d} samples={d} sampled_ns={d} sampled_max_ns={d}; elapsed samples include waits; maximum covers samples only", .{
            view.label, name, count, view.samples[op_index], view.nanos[op_index], view.maxima[op_index],
        });
    }
    var sampled_calls: u64 = 0;
    var sampled_nanos: u64 = 0;
    var estimated_total: u64 = 0;
    for (view.ops, 0..) |count, op_index| {
        const samples = view.samples[op_index];
        if (samples == 0) continue;
        sampled_calls +|= samples;
        sampled_nanos +|= view.nanos[op_index];
        const estimate = (@as(u128, view.nanos[op_index]) * @as(u128, count)) / @as(u128, samples);
        estimated_total +|= @intCast(@min(estimate, @as(u128, __process_std.math.maxInt(u64))));
    }
    __process_log.info("PE64 BLOCK JIT {s}FALLBACK LEDGER: calls={d} reasons(missing_native_template/native_slow_path/hook_observation/vector_policy_disabled)={d}/{d}/{d}/{d} samples={d} sampled_host_ns={d} estimated_interpreter_ns={d} per_op_sample_period={d}; native_slow_path counts translated templates that escaped through a runtime guard, while hook and vector-policy reasons preserve explicit interpreter boundaries; estimated time is an in-run count-weighted sample, not guest time", .{
        view.label,
        view.calls,
        view.reasons[@intFromEnum(__process_block_jit.FallbackReason.missing_native_template)],
        view.reasons[@intFromEnum(__process_block_jit.FallbackReason.native_slow_path)],
        view.reasons[@intFromEnum(__process_block_jit.FallbackReason.hook_observation)],
        view.reasons[@intFromEnum(__process_block_jit.FallbackReason.vector_policy_disabled)],
        sampled_calls,
        sampled_nanos,
        estimated_total,
        __process_BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD,
    });
}
