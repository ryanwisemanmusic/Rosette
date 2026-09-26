//! Evidence for the Windows Vulkan surface proc lookup-to-call handoff.

const std = @import("std");
const log = std.log.scoped(.windows_guest_vulkan);

pub const SurfaceCalls = struct {
    proc_lookups: u64 = 0,
    proc_lookup_available: u64 = 0,
    proc_lookup_missing: u64 = 0,
    dispatch_attempts: u64 = 0,
    dispatch_refusals: u64 = 0,
    adapter_invocations: u64 = 0,
    vk_successes: u64 = 0,
    vk_failures: u64 = 0,
    name_remaps: u64 = 0,
    last_vk_result: i32 = 0,
    last_output_surface: u64 = 0,

    pub fn noteProcLookup(self: *SurfaceCalls, available: bool) void {
        self.proc_lookups +|= 1;
        if (available) {
            self.proc_lookup_available +|= 1;
        } else {
            self.proc_lookup_missing +|= 1;
        }
    }

    pub fn noteDispatchAttempt(self: *SurfaceCalls) void {
        self.dispatch_attempts +|= 1;
    }

    pub fn noteDispatchRefusal(self: *SurfaceCalls) void {
        self.dispatch_refusals +|= 1;
    }

    pub fn noteNameRemap(self: *SurfaceCalls) void {
        self.name_remaps +|= 1;
    }

    pub fn noteAdapterInvocation(self: *SurfaceCalls, result: i32, output_surface: u64) void {
        self.adapter_invocations +|= 1;
        self.last_vk_result = result;
        self.last_output_surface = output_surface;
        if (result == 0 and output_surface != 0) {
            self.vk_successes +|= 1;
        } else {
            self.vk_failures +|= 1;
        }
    }

    pub fn report(self: *const SurfaceCalls) void {
        log.info("Windows Vulkan surface path: proc_lookup(available/missing)={d}/{d} dispatch(attempts/refusals)={d}/{d} adapter_invocations={d} VkResult(success/failure)={d}/{d} name_remaps={d} last(VkResult/surface)={d}/0x{x}; lookup, guest thunk entry, adapter call, and surface publication are separate witnesses", .{
            self.proc_lookup_available,
            self.proc_lookup_missing,
            self.dispatch_attempts,
            self.dispatch_refusals,
            self.adapter_invocations,
            self.vk_successes,
            self.vk_failures,
            self.name_remaps,
            self.last_vk_result,
            self.last_output_surface,
        });
    }
};

test "surface path distinguishes lookup, refusal, Vulkan result, and publication" {
    var calls = SurfaceCalls{};
    calls.noteProcLookup(true);
    calls.noteDispatchAttempt();
    calls.noteNameRemap();
    calls.noteAdapterInvocation(0, 0x1234);
    calls.noteProcLookup(false);
    calls.noteDispatchRefusal();
    calls.noteAdapterInvocation(-7, 0);

    try std.testing.expectEqual(@as(u64, 2), calls.proc_lookups);
    try std.testing.expectEqual(@as(u64, 1), calls.proc_lookup_available);
    try std.testing.expectEqual(@as(u64, 1), calls.proc_lookup_missing);
    try std.testing.expectEqual(@as(u64, 1), calls.vk_successes);
    try std.testing.expectEqual(@as(u64, 1), calls.vk_failures);
    try std.testing.expectEqual(@as(u64, 0), calls.last_output_surface);
}
