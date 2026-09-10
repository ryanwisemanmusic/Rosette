//! Microsoft x64 to Rosetta's native Vulkan guest-call adapter.
//!
//! A Windows PE image uses the Microsoft x64 register convention while the
//! existing Vulkan guest forwarder is deliberately written in the SysV
//! convention used by translated Mach-O calls.  This adapter is the narrow
//! boundary between those two contracts.  It changes only the emulated
//! register view and a bounded copy of the guest stack; Vulkan pointers remain
//! guest addresses and are validated by the forwarder before a host driver is
//! called.

const std = @import("std");
const dynamic_forwarder = @import("dyld").dynamic_library_forwarder;

const log = std.log.scoped(.windows_guest_vulkan);

pub const native_metal_layer_token: u64 = 0xCAFE_BABE_0000_0001;

const vulkan_library_path = "libvulkan.1.dylib";
const rtld_lazy: u64 = 0x1;
const rtld_local: u64 = 0x4;
const max_stack_arguments: usize = 16;
const scratch_stack_bytes: u64 = (max_stack_arguments + 1) * 8;
const metal_surface_create_info_bytes: u64 = 32;

const MicrosoftRegisterArguments = struct {
    rcx: u64,
    rdx: u64,
    r8: u64,
    r9: u64,
};

const SysVRegisterArguments = struct {
    rdi: u64,
    rsi: u64,
    rdx: u64,
    rcx: u64,
    r8: u64,
    r9: u64,
};

fn mapMicrosoftToSysV(
    microsoft: MicrosoftRegisterArguments,
    stack_arg4: u64,
    stack_arg5: u64,
) SysVRegisterArguments {
    return .{
        .rdi = microsoft.rcx,
        .rsi = microsoft.rdx,
        .rdx = microsoft.r8,
        .rcx = microsoft.r9,
        .r8 = stack_arg4,
        .r9 = stack_arg5,
    };
}

fn microsoftStackArgumentOffset(index: usize, has_direct_return: bool) u64 {
    std.debug.assert(index >= 4);
    const stack_bias: u64 = if (has_direct_return) 32 else 40;
    return stack_bias + @as(u64, @intCast(index - 4)) * 8;
}

pub const Bridge = struct {
    forwarder: dynamic_forwarder.Forwarder = .{},
    library_token: u64 = 0,
    dispatch_attempts: u64 = 0,
    dispatches: u64 = 0,
    dispatch_failures: u64 = 0,
    surface_name_remaps: u64 = 0,
    boundary_trace_initialized: bool = false,
    boundary_trace_enabled: bool = false,
    boundary_trace_events: u64 = 0,

    pub fn deinit(self: *Bridge) void {
        if (graphicsStateDumpEnabled() and self.forwarder.guest_proc_queries != 0) {
            self.forwarder.dumpVulkanStateSnapshot();
        }
        self.forwarder.deinit();
        self.* = .{};
    }

    fn boundaryTraceEnabled(self: *Bridge) bool {
        if (!self.boundary_trace_initialized) {
            self.boundary_trace_initialized = true;
            if (std.c.getenv("ROSETTE_ELF_GRAPHICS_BOUNDARY_TRACE")) |raw| {
                const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
                self.boundary_trace_enabled = std.mem.eql(u8, value, "1") or
                    std.ascii.eqlIgnoreCase(value, "true") or
                    std.ascii.eqlIgnoreCase(value, "yes");
            }
        }
        return self.boundary_trace_enabled;
    }

    fn graphicsStateDumpEnabled() bool {
        const raw = std.c.getenv("ROSETTE_ELF_GRAPHICS_STATE_DUMP") orelse return false;
        const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
        return std.mem.eql(u8, value, "1") or
            std.ascii.eqlIgnoreCase(value, "true") or
            std.ascii.eqlIgnoreCase(value, "yes");
    }

    fn boundaryTraceCandidate(name: []const u8) bool {
        return std.mem.eql(u8, name, "vkAllocateMemory") or
            std.mem.eql(u8, name, "vkBindBufferMemory") or
            std.mem.eql(u8, name, "vkBindImageMemory") or
            std.mem.eql(u8, name, "vkMapMemory") or
            std.mem.eql(u8, name, "vkUnmapMemory") or
            std.mem.eql(u8, name, "vkFlushMappedMemoryRanges") or
            std.mem.eql(u8, name, "vkInvalidateMappedMemoryRanges") or
            std.mem.eql(u8, name, "vkCreateImage") or
            std.mem.eql(u8, name, "vkCreateBuffer") or
            std.mem.eql(u8, name, "vkCreateImageView") or
            std.mem.eql(u8, name, "vkUpdateDescriptorSets") or
            std.mem.eql(u8, name, "vkBeginCommandBuffer") or
            std.mem.eql(u8, name, "vkEndCommandBuffer") or
            std.mem.eql(u8, name, "vkQueueSubmit") or
            std.mem.eql(u8, name, "vkQueueSubmit2") or
            std.mem.eql(u8, name, "vkQueuePresentKHR") or
            std.mem.eql(u8, name, "vkWaitForFences") or
            std.mem.eql(u8, name, "vkDeviceWaitIdle");
    }

    fn shouldTraceBoundary(self: *Bridge, name: []const u8) bool {
        if (!self.boundaryTraceEnabled() or !boundaryTraceCandidate(name)) return false;
        // vkUnmapMemory is the boundary most likely to be mistaken for a
        // native hang because its loader lookup is often the last visible
        // line. Keep every unmap, while sampling repetitive resource setup.
        if (std.mem.eql(u8, name, "vkUnmapMemory")) return true;
        self.boundary_trace_events +|= 1;
        const event = self.boundary_trace_events;
        return event <= 16 or (event & (event - 1)) == 0;
    }

    fn stateStep(state: anytype) u64 {
        const State = @TypeOf(state.*);
        return if (comptime @hasField(State, "executed_steps")) state.executed_steps else 0;
    }

    fn stateThread(state: anytype) u64 {
        const State = @TypeOf(state.*);
        return if (comptime @hasField(State, "active_guest_thread")) state.active_guest_thread else 0;
    }

    fn logBoundaryEnter(self: *const Bridge, state: anytype, name: []const u8, call_id: u64, direct_return_rip: ?u64) void {
        log.info("Vulkan boundary enter: call={d} name={s} step={d} thread=0x{x} rip=0x{x} direct_return=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x} rsp=0x{x} forwarder_calls={d} native_device={} native_surface={}", .{
            call_id,
            name,
            stateStep(state),
            stateThread(state),
            state.regs.rip,
            direct_return_rip orelse 0,
            state.regs.rcx,
            state.regs.rdx,
            state.regs.r8,
            state.regs.r9,
            state.regs.rsp,
            self.forwarder.vulkan_call_count,
            self.forwarder.real_vulkan.hasDevice(),
            self.forwarder.real_vulkan.surface != 0,
        });
    }

    fn logBoundaryExit(self: *const Bridge, state: anytype, name: []const u8, call_id: u64, outcome: []const u8) void {
        log.info("Vulkan boundary exit: call={d} name={s} outcome={s} result=0x{x} step={d} thread=0x{x} next_rip=0x{x} dispatches={d} failures={d} forwarder_calls={d} native_device={} native_surface={}", .{
            call_id,
            name,
            outcome,
            state.regs.rax,
            stateStep(state),
            stateThread(state),
            state.regs.rip,
            self.dispatches,
            self.dispatch_failures,
            self.forwarder.vulkan_call_count,
            self.forwarder.real_vulkan.hasDevice(),
            self.forwarder.real_vulkan.surface != 0,
        });
    }

    /// Dispatch a Windows Vulkan import through the real Rosetta Vulkan
    /// forwarder.  `false` means this adapter does not own the name, so the
    /// normal Windows runtime may apply its explicit modelled path.
    pub fn dispatch(self: *Bridge, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
        if (!owns(name)) return false;
        self.dispatch_attempts +|= 1;
        const call_id = self.dispatch_attempts;
        const trace_boundary = self.shouldTraceBoundary(name);
        var trace_outcome: []const u8 = "not_completed";
        if (trace_boundary) {
            self.logBoundaryEnter(state, name, call_id, direct_return_rip);
        }
        defer if (trace_boundary) self.logBoundaryExit(state, name, call_id, trace_outcome);

        const library_token = self.ensureLibrary() orelse {
            self.dispatch_failures +|= 1;
            trace_outcome = "library_unavailable";
            return false;
        };
        const forward_name = if (std.mem.eql(u8, name, "vkCreateWin32SurfaceKHR"))
            "vkCreateMetalSurfaceEXT"
        else
            name;
        if (!dynamic_forwarder.isForwardableVulkanSymbol(forward_name)) {
            self.dispatch_failures +|= 1;
            trace_outcome = "symbol_not_forwardable";
            return false;
        }
        const symbol_token = self.forwarder.lookupGuest(library_token, forward_name);
        if (symbol_token == 0) {
            self.dispatch_failures +|= 1;
            trace_outcome = "symbol_lookup_failed";
            return false;
        }

        const original_regs = state.regs;
        if (std.mem.eql(u8, name, "vkCreateWin32SurfaceKHR")) {
            if (!ensureWindow(state)) {
                self.dispatch_failures +|= 1;
                trace_outcome = "window_unavailable";
                return false;
            }
        }
        const scratch_stack = state.guestAlloc(scratch_stack_bytes, 16) orelse {
            self.dispatch_failures +|= 1;
            trace_outcome = "scratch_stack_unavailable";
            return false;
        };

        // At a Microsoft x64 callee boundary, argument 6 starts at +0x38
        // when the call pushed a return address, or +0x30 for the direct
        // callback shortcut.  SysV argument 6 starts at [rsp+8].
        const has_direct_return = direct_return_rip != null;
        const windows_arg6_offset = microsoftStackArgumentOffset(6, has_direct_return);
        for (0..max_stack_arguments) |index| {
            const source = original_regs.rsp +| windows_arg6_offset +| @as(u64, @intCast(index * 8));
            state.write64(scratch_stack +| 8 +| @as(u64, @intCast(index * 8)), state.read64(source));
        }

        const mapped = mapMicrosoftToSysV(
            .{
                .rcx = original_regs.rcx,
                .rdx = original_regs.rdx,
                .r8 = original_regs.r8,
                .r9 = original_regs.r9,
            },
            state.read64(original_regs.rsp +| microsoftStackArgumentOffset(4, has_direct_return)),
            state.read64(original_regs.rsp +| microsoftStackArgumentOffset(5, has_direct_return)),
        );
        state.regs.rdi = mapped.rdi;
        state.regs.rsi = mapped.rsi;
        state.regs.rdx = mapped.rdx;
        state.regs.rcx = mapped.rcx;
        state.regs.r8 = mapped.r8;
        state.regs.r9 = mapped.r9;
        state.regs.rsp = scratch_stack;

        if (std.mem.eql(u8, name, "vkCreateWin32SurfaceKHR")) {
            const metal_info = state.guestAlloc(metal_surface_create_info_bytes, 8) orelse {
                state.regs = original_regs;
                self.dispatch_failures +|= 1;
                trace_outcome = "surface_info_unavailable";
                return false;
            };
            state.write32(metal_info, 1_000_217_000);
            state.write64(metal_info + 8, 0);
            state.write32(metal_info + 16, 0);
            state.write64(metal_info + 24, native_metal_layer_token);
            // SysV's second argument is pCreateInfo; the Windows allocator
            // remains SysV rdx and the output pointer remains SysV rcx.
            state.regs.rsi = metal_info;
            self.surface_name_remaps +|= 1;
        }

        const dispatched = self.forwarder.dispatchGuestSymbol(state, symbol_token);
        const result = state.regs.rax;
        const native_objects_ready = self.forwarder.guestVulkanInstanceReady() or
            self.forwarder.guestVulkanDeviceReady();
        state.regs = original_regs;
        if (!dispatched) {
            self.dispatch_failures +|= 1;
            trace_outcome = "forwarder_rejected";
            return false;
        }
        state.regs.rax = result;
        self.dispatches +|= 1;
        noteNativeForwarding(state, name, native_objects_ready);
        noteLogicalContract(state, name, result);
        finishWindowsCall(state, direct_return_rip);
        trace_outcome = "forwarded";
        return true;
    }

    fn ensureLibrary(self: *Bridge) ?u64 {
        if (self.library_token != 0) return self.library_token;
        self.library_token = self.forwarder.openGuest(vulkan_library_path, rtld_lazy | rtld_local);
        return if (self.library_token != 0) self.library_token else null;
    }
};

fn owns(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "vk")) return false;
    // These two functions are intentionally left with the Windows runtime.
    // They return Microsoft-ABI Rosetta stubs; calls through those stubs come
    // back here with the requested function's actual name.
    if (std.mem.eql(u8, name, "vkGetInstanceProcAddr") or
        std.mem.eql(u8, name, "vkGetDeviceProcAddr")) return false;
    if (std.mem.eql(u8, name, "vkCreateWin32SurfaceKHR")) return true;
    return dynamic_forwarder.isForwardableVulkanSymbol(name);
}

fn ensureWindow(state: anytype) bool {
    const State = @TypeOf(state.*);
    if (comptime @hasField(State, "windows_graphics")) {
        if (state.windows_graphics.window_ready) return true;
        return state.windows_graphics.ensureWindow(1280, 720, "Xenia Canary (Rosette)");
    }
    return false;
}

fn noteNativeForwarding(state: anytype, name: []const u8, host_objects_ready: bool) void {
    const State = @TypeOf(state.*);
    if (comptime @hasField(State, "windows_graphics")) {
        state.windows_graphics.noteNativeVulkanForwarded(name, host_objects_ready);
    }
}

fn noteLogicalContract(state: anytype, name: []const u8, result: u64) void {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "windows_graphics")) return;
    const ok = @as(u32, @truncate(result)) == 0;
    if (std.mem.eql(u8, name, "vkCreateInstance")) {
        _ = state.windows_graphics.noteCreateInstance(ok);
    } else if (std.mem.eql(u8, name, "vkCreateWin32SurfaceKHR")) {
        _ = state.windows_graphics.noteCreateSurface(ok);
    } else if (std.mem.eql(u8, name, "vkCreateDevice")) {
        _ = state.windows_graphics.noteCreateDevice(ok);
    } else if (std.mem.eql(u8, name, "vkGetDeviceQueue") or
        std.mem.eql(u8, name, "vkGetDeviceQueue2"))
    {
        _ = state.windows_graphics.noteGetQueue(ok);
    } else if (std.mem.eql(u8, name, "vkCreateSwapchainKHR")) {
        _ = state.windows_graphics.noteCreateSwapchain(ok);
    } else if (std.mem.eql(u8, name, "vkGetSwapchainImagesKHR")) {
        _ = state.windows_graphics.noteSwapchainImages(ok);
    } else if (std.mem.eql(u8, name, "vkAcquireNextImageKHR")) {
        _ = state.windows_graphics.noteAcquire(ok);
    } else if (std.mem.eql(u8, name, "vkQueueSubmit") or
        std.mem.eql(u8, name, "vkQueueSubmit2"))
    {
        _ = state.windows_graphics.noteQueueSubmit(ok);
    } else if (std.mem.eql(u8, name, "vkQueuePresentKHR")) {
        _ = state.windows_graphics.notePresent(ok);
    } else if (std.mem.startsWith(u8, name, "vkCmd")) {
        state.windows_graphics.noteCommand(name);
    } else {
        state.windows_graphics.noteObservedCall(name);
    }
}

fn finishWindowsCall(state: anytype, direct_return_rip: ?u64) void {
    if (direct_return_rip) |rip| {
        state.regs.rip = rip;
    } else {
        state.regs.rip = state.pop();
    }
}

test "Windows Vulkan adapter owns real forwarder names but not proc lookup" {
    try std.testing.expect(!owns("vkGetInstanceProcAddr"));
    try std.testing.expect(owns("vkCreateWin32SurfaceKHR"));
    try std.testing.expect(owns("vkCreateInstance"));
    try std.testing.expect(!owns("vkNameRosetteDoesNotImplement"));
}

test "Windows surface adapter exposes the stable Metal layer token" {
    try std.testing.expect(native_metal_layer_token != 0);
}

test "Windows Vulkan adapter maps Microsoft x64 arguments to SysV" {
    const mapped = mapMicrosoftToSysV(.{
        .rcx = 0x11,
        .rdx = 0x22,
        .r8 = 0x33,
        .r9 = 0x44,
    }, 0x55, 0x66);
    try std.testing.expectEqual(@as(u64, 0x11), mapped.rdi);
    try std.testing.expectEqual(@as(u64, 0x22), mapped.rsi);
    try std.testing.expectEqual(@as(u64, 0x33), mapped.rdx);
    try std.testing.expectEqual(@as(u64, 0x44), mapped.rcx);
    try std.testing.expectEqual(@as(u64, 0x55), mapped.r8);
    try std.testing.expectEqual(@as(u64, 0x66), mapped.r9);

    try std.testing.expectEqual(@as(u64, 32), microsoftStackArgumentOffset(4, true));
    try std.testing.expectEqual(@as(u64, 40), microsoftStackArgumentOffset(5, true));
    try std.testing.expectEqual(@as(u64, 48), microsoftStackArgumentOffset(6, true));
    try std.testing.expectEqual(@as(u64, 40), microsoftStackArgumentOffset(4, false));
    try std.testing.expectEqual(@as(u64, 48), microsoftStackArgumentOffset(5, false));
    try std.testing.expectEqual(@as(u64, 56), microsoftStackArgumentOffset(6, false));
}
