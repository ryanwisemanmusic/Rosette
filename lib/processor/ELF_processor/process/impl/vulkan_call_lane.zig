//! A translated `call` into a vulkan-1.dll proc thunk, completed in place.
//!
//! Xenia records every draw through function pointers `vkGetDeviceProcAddr`
//! handed out: `call [table+offset]` to a Rosette thunk. Each such call used
//! to leave translated code at the call, run it in the interpreter (push the
//! return address, jump to the thunk), take a second step at the thunk to
//! look the import up and dispatch it, then pop the return address and enter
//! translated code again at the return. Halo 3's GPU Commands thread made
//! about 45 million of these calls in the 2026-10-20 campaign run, at about
//! 1.6 microseconds each.
//!
//! Here the translated call asks first (`block_jit/core.zig`, the
//! out-of-code-cache edge of `emitHookedTargetCheck`): when the target is a
//! dynamic vulkan-1.dll thunk for a command-recording entry point, the same
//! adapter the thunk's step runs (`tryNativeWindowsVulkan`) runs here, under
//! the same runtime lock, in its direct-return form - the arguments are read
//! where the caller left them, nothing is pushed or popped, and RIP becomes
//! the return address. The block then goes on at the return address through
//! its ordinary exit. Anything else declines before changing anything and
//! takes the interpreter's path exactly as before.
//!
//! Only `vkCmd*` and `vkUpdateDescriptorSets`: they record into command
//! buffers and descriptor sets, never wait on the GPU, map memory, create
//! objects or give the runtime lock back. The thunk's step also compares the
//! callee-saved registers before and after and repairs them; the adapter
//! restores every register but RAX and every vector register itself, so that
//! check has nothing to find on this route and is not repeated.
const std = @import("std");
const process = @import("../../process.zig");
const ElfState = process.ElfState;
const I = process.__ProcessInternals;
const lifecycle = @import("lifecycle.zig");
const guest_heap = @import("guest_heap.zig");

/// Offline control: false leaves every Vulkan call on the interpreter's path.
pub var enabled: bool = true;

/// Calls completed in place, and calls that ended the run while doing so.
var completed = std.atomic.Value(u64).init(0);
var terminated = std.atomic.Value(u64).init(0);

pub fn completedCalls() u64 {
    return completed.load(.monotonic);
}

/// The entry points this route takes: command recording only.
pub fn recordsCommands(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "vkCmd") or std.mem.eql(u8, name, "vkUpdateDescriptorSets");
}

/// 2 when the call ran here and goes on at `return_rip`; 0 with nothing
/// changed when the interpreter's path should run it. The caller has
/// already ruled out tracing and probes.
pub fn transfer(self: *ElfState, target: u64, return_rip: u64) u32 {
    if (!enabled or return_rip == 0 or self.diagnose_abi or self.windowsMemoryTraceLive()) return 0;
    if (!self.windows_stub_box.contains(target)) return 0;
    const stub = guest_heap.windowsImportStubAt(self, target) orelse return 0;
    if (!stub.is_dynamic or !recordsCommands(stub.function_name)) return 0;
    // The adapter registers its thunks as "vulkan-1.dll" exactly.
    if (!std.mem.eql(u8, stub.dll_name, "vulkan-1.dll") and !std.ascii.eqlIgnoreCase(stub.dll_name, "vulkan-1.dll")) return 0;
    // The adapter reads the descriptors and argument blocks this thread's
    // own translated stores have just written.
    I._tso_memory.flushActiveStoreBufferFor(.jit_fallback);
    var guard = lifecycle.lockWindowsRuntimeForDispatch(self);
    defer guard.unlock();
    I._concurrency.watch.beginActivity(stub.function_name);
    defer I._concurrency.watch.endActivity();
    // True also when a refused name ended the run, as the thunk's step
    // would have: the block then stops at its next exit check.
    if (!guest_heap.tryNativeWindowsVulkan(self, stub.function_name, return_rip)) return 0;
    _ = completed.fetchAdd(1, .monotonic);
    if (lifecycle.isTerminated(self)) {
        _ = terminated.fetchAdd(1, .monotonic);
        lifecycle.guestContextField(self, "block_jit_scratch").chain_break = 1;
    }
    return 2;
}

pub fn report(state: anytype) void {
    _ = state;
    const count = completed.load(.monotonic);
    if (count == 0) return;
    std.log.info("PE64 VULKAN CALL LANE: completed={d} ended_run={d}; translated calls into vulkan-1.dll command-recording thunks completed in place through the same adapter and runtime lock, direct return; other targets and every traced run keep the interpreter's path", .{ count, terminated.load(.monotonic) });
}

test "the Vulkan call lane takes command recording and descriptor updates only" {
    try std.testing.expect(recordsCommands("vkCmdDrawIndexed"));
    try std.testing.expect(recordsCommands("vkCmdBindDescriptorSets"));
    try std.testing.expect(recordsCommands("vkUpdateDescriptorSets"));
    try std.testing.expect(!recordsCommands("vkQueueSubmit"));
    try std.testing.expect(!recordsCommands("vkWaitForFences"));
    try std.testing.expect(!recordsCommands("vkCreateGraphicsPipelines"));
    try std.testing.expect(!recordsCommands("vkMapMemory"));
    try std.testing.expect(!recordsCommands("vkUpdateDescriptorSetWithTemplate"));
}
