//! Exact zero-delay NT calls only. Timed/alertable delays and Xenia global
//! lock owners retain the scheduler-aware, locked dispatcher.
const std = @import("std");

pub fn tryFunction(comptime host: type, state: anytype, dll: []const u8, name: []const u8, return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "windows_fast_nt_yield") or !@hasDecl(State, "windowsFastSleepZeroImportAllowed")) return false;
    const index: usize = if (std.mem.eql(u8, name, "NtDelayExecution")) 0 else if (std.mem.eql(u8, name, "NtYieldExecution")) 1 else return false;
    if (!std.ascii.eqlIgnoreCase(dll, "ntdll.dll") or !state.windows_fast_nt_yield.enabled or
        !state.parallel_guest_execution or !state.windows_runtime_enabled or state.diagnose_abi or return_rip == null or
        state.guest_clock.source != .host_monotonic) return false;
    if (!state.windowsFastCrtImportMayBypassRuntimeLock()) return false;
    if (state.windowsMemoryTraceLive() or state.trace_write_address != null) return false;
    const scope = host.begin(state);
    defer host.end(state, scope);
    if (!state.windowsFastSleepZeroImportAllowed()) return false;
    const regs = state.windowsGuestContextField("regs");
    if (index == 0) {
        // Invalid/nonzero intervals and alertable calls retain ordinary dispatch.
        if (regs.rcx != 0 or regs.rdx == 0 or state.guestMemoryConst(regs.rdx, 8) == null or state.read64(regs.rdx) != 0) return false;
    }
    regs.rax = 0;
    _ = state.windows_fast_nt_yield.calls[index].fetchAdd(1, .monotonic);
    state.windowsGuestContextField("windows_current_import").* = if (index == 0) "NtDelayExecution" else "NtYieldExecution";
    host.completeCall(state, return_rip);
    state.windowsGuestContextField("windows_slice_nt_zero_yield").* = true;
    state.requestWindowsGuestSliceYield();
    return true;
}
