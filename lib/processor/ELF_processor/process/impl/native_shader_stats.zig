//! Runtime lock availability during native shader module creation.
const std = @import("std");
pub fn report(state: anytype) void {
    if (state.runtime_lock_native_shader_yields == 0 and state.runtime_lock_native_shader_refusals == 0) return;
    std.log.info("PE64 NATIVE SHADER LOCK ROUTE: calls={d} released_ms={d} pinned_refusals={d}; native module creation with owned input; all transforms and bookkeeping remain serialized; driver elapsed time unchanged", .{ state.runtime_lock_native_shader_yields, state.runtime_lock_native_shader_ns / std.time.ns_per_ms, state.runtime_lock_native_shader_refusals });
}
