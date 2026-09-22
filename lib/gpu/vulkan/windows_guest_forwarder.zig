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
const gpu = @import("gpu");
const vulkan_contract = @import("dll_win32_catalogue").vulkan;
const dynamic_forwarder = @import("dyld").dynamic_library_forwarder;

const log = std.log.scoped(.windows_guest_vulkan);

pub const native_metal_layer_token: u64 = 0xCAFE_BABE_0000_0001;

const vulkan_library_path = "libvulkan.1.dylib";
const rtld_lazy: u64 = 0x1;
const rtld_local: u64 = 0x4;
const max_stack_arguments: usize = 16;
const scratch_stack_bytes: u64 = (max_stack_arguments + 1) * 8;
const scratch_stack_alignment: u64 = 16;
/// How many Microsoft-ABI Vulkan calls may be live at once before the bridge
/// stops reusing a cached scratch stack. A forwarded call runs to completion
/// without the interpreter scheduling another guest thread, so the depth is
/// one in every observed run; the remaining slots exist so that a driver that
/// calls back into guest code cannot make a nested dispatch share the outer
/// call's stack.
const scratch_stack_cache_depth: usize = 4;
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

const host_time_slots = 128;
const HostTimeEntry = struct {
    key: usize = 0,
    name: [48]u8 = @splat(0),
    name_len: u8 = 0,
    calls: u64 = 0,
    ns: u64 = 0,
    max_ns: u64 = 0,

    fn label(self: *const HostTimeEntry) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const Bridge = struct {
    forwarder: dynamic_forwarder.Forwarder = .{},
    library_token: u64 = 0,
    dispatch_attempts: u64 = 0,
    dispatches: u64 = 0,
    /// Wall time spent inside outermost Vulkan dispatches - the native
    /// Vulkan/MoltenVK work, and the marshalling around it, done on the one
    /// host thread every guest thread runs on. It is the measured ceiling on
    /// what moving host graphics work to a second host thread could return
    /// (the first multi-core step in the TSO note), before any guest memory
    /// model is involved.
    host_ns: u64 = 0,
    host_ns_max: u64 = 0,
    host_timed_calls: u64 = 0,
    /// The same wall time split by entry point, so the report names what
    /// the host thread was doing: pipeline compiles, fence waits or command
    /// recording. Keyed by the import name's address and length.
    host_time_entries: [host_time_slots]HostTimeEntry = @splat(.{}),
    host_time_overflow_ns: u64 = 0,
    dispatch_depth: u32 = 0,
    dispatch_failures: u64 = 0,
    surface_name_remaps: u64 = 0,
    boundary_trace_initialized: bool = false,
    boundary_trace_enabled: bool = false,
    boundary_trace_events: u64 = 0,
    boundary_failure_events: u64 = 0,
    scalar_width_normalizations: u64 = 0,
    scalar_width_normalized_calls: u64 = 0,
    scalar_width_last_reported: u64 = 0,
    /// The SysV stack this adapter hands the forwarded call.
    ///
    /// It used to be a fresh `guestAlloc` on every dispatch, and nothing ever
    /// freed it: 3,823,761 Vulkan calls walked the guest heap cursor into its
    /// limit, and the next `vkCmdDrawIndexed` was refused for want of 136
    /// bytes. The Vulkan route is right to treat that refusal as fatal rather
    /// than fall back to a synthetic command, so the leak presented as the
    /// run dying with exit 127 on a draw that was in no way unusual.
    ///
    /// The buffer's whole lifetime is one dispatch and every byte a callee can
    /// read is rewritten on entry, so one allocation serves every call.
    scratch_stacks: [scratch_stack_cache_depth]u64 = @splat(0),
    scratch_stack_depth: usize = 0,
    scratch_stack_allocations: u64 = 0,
    scratch_stack_reuses: u64 = 0,
    scratch_stack_overflow_allocations: u64 = 0,

    /// Hand out the scratch stack for the dispatch that is about to run, and
    /// leave it owned until `releaseScratchStack`.
    ///
    /// A nested dispatch takes the next slot rather than the live one. Past
    /// the cache's depth the bridge allocates rather than aliasing a stack a
    /// caller is still standing on; that path is counted so a driver that
    /// really does re-enter this deeply is visible instead of silently
    /// reintroducing the leak this cache removed.
    fn acquireScratchStack(self: *Bridge, state: anytype) ?u64 {
        const depth = self.scratch_stack_depth;
        if (depth >= self.scratch_stacks.len) {
            const fresh = state.guestAlloc(scratch_stack_bytes, scratch_stack_alignment) orelse return null;
            self.scratch_stack_overflow_allocations +|= 1;
            self.scratch_stack_depth += 1;
            return fresh;
        }
        if (self.scratch_stacks[depth] == 0) {
            self.scratch_stacks[depth] = state.guestAlloc(scratch_stack_bytes, scratch_stack_alignment) orelse return null;
            self.scratch_stack_allocations +|= 1;
        } else {
            self.scratch_stack_reuses +|= 1;
        }
        self.scratch_stack_depth += 1;
        return self.scratch_stacks[depth];
    }

    fn releaseScratchStack(self: *Bridge) void {
        if (self.scratch_stack_depth != 0) self.scratch_stack_depth -= 1;
    }

    fn normalizeMicrosoftArgument(self: *Bridge, name: []const u8, signature: vulkan_contract.argument_widths.Signature, index: usize, raw: u64) u64 {
        const normalized = signature.normalize(index, raw);
        if (normalized != raw) {
            self.scalar_width_normalizations +|= 1;
            const count = self.scalar_width_normalizations;
            if (count <= 4 or (count & (count - 1)) == 0) log.info(
                "Vulkan DWORD argument normalized: name={s} argument={d} raw=0x{x} value={d} (0x{x}) normalization={d}; upper slot bits are not part of the declared Vulkan scalar",
                .{ name, index + 1, raw, normalized, normalized, count },
            );
        }
        return normalized;
    }

    fn reportArgumentWidths(self: *Bridge, full: bool) void {
        if (!full and self.scalar_width_last_reported == self.scalar_width_normalizations) return;
        self.scalar_width_last_reported = self.scalar_width_normalizations;
        log.info("Vulkan ABI argument widths: normalized_calls={d} DWORD_upper_halves_discarded={d} contract=vendored_registry typed_scalars_only=true pointers_handles_sizes_timeouts_preserved=true", .{
            self.scalar_width_normalized_calls,
            self.scalar_width_normalizations,
        });
    }

    pub fn deinit(self: *Bridge) void {
        if (graphicsStateDumpEnabled() and self.forwarder.guest_proc_queries != 0) {
            self.forwarder.dumpVulkanStateSnapshot();
        }
        self.forwarder.deinit();
        self.* = .{};
    }

    /// Present a Xenos front buffer discovered by the PE/Xenia route. Raw
    /// enum values cross the C callback because the producer lives in the PE
    /// processor; validate them here before they become typed GPU facts.
    pub fn presentGuestFrontBuffer(
        self: *Bridge,
        state: anytype,
        source: u64,
        width: u32,
        height: u32,
        tiled: bool,
        endian_raw: u32,
        format_raw: u32,
        guest_swap_observed: bool,
    ) bool {
        if (endian_raw > std.math.maxInt(u3) or format_raw > std.math.maxInt(u8)) return false;
        const endian: gpu.xenos_texture.Endian = @enumFromInt(@as(u3, @intCast(endian_raw)));
        const format: gpu.xenos_texture.Format = @enumFromInt(@as(u8, @intCast(format_raw)));
        return self.forwarder.presentGuestFrontBuffer(
            state,
            source,
            width,
            height,
            tiled,
            endian,
            format,
            guest_swap_observed,
        );
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
            std.mem.eql(u8, name, "vkCmdBindDescriptorSets") or
            std.mem.eql(u8, name, "vkBeginCommandBuffer") or
            std.mem.eql(u8, name, "vkEndCommandBuffer") or
            std.mem.eql(u8, name, "vkQueueSubmit") or
            (std.mem.eql(u8, name, "vkQueueSubmit2") or std.mem.eql(u8, name, "vkQueueSubmit2KHR")) or
            std.mem.eql(u8, name, "vkQueuePresentKHR") or
            std.mem.eql(u8, name, "vkWaitForFences") or
            std.mem.eql(u8, name, "vkDeviceWaitIdle");
    }

    fn shouldTraceBoundary(self: *Bridge, name: []const u8) bool {
        if (!self.boundaryTraceEnabled() or !boundaryTraceCandidate(name)) return false;
        self.boundary_trace_events +|= 1;
        const event = self.boundary_trace_events;
        // Successful boundary traffic is sampled globally. A long-running
        // title can issue millions of map/unmap/submit calls, so a successful
        // call must never become one log line per call. Failures use their
        // own bounded path below and are still visible even when sampling is
        // disabled.
        return event <= 8 or (event & (event - 1)) == 0;
    }

    fn shouldLogBoundaryFailure(self: *Bridge) bool {
        self.boundary_failure_events +|= 1;
        const event = self.boundary_failure_events;
        return event <= 4 or (event & (event - 1)) == 0;
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
        log.info("Vulkan boundary exit: call={d} name={s} outcome={s} result=0x{x} step={d} thread=0x{x} next_rip=0x{x} args(rcx/rdx/r8/r9/rsp)=0x{x}/0x{x}/0x{x}/0x{x}/0x{x} dispatches={d} failures={d} forwarder_calls={d} native_device={} native_surface={}", .{
            call_id,
            name,
            outcome,
            state.regs.rax,
            stateStep(state),
            stateThread(state),
            state.regs.rip,
            state.regs.rcx,
            state.regs.rdx,
            state.regs.r8,
            state.regs.r9,
            state.regs.rsp,
            self.dispatches,
            self.dispatch_failures,
            self.forwarder.vulkan_call_count,
            self.forwarder.real_vulkan.hasDevice(),
            self.forwarder.real_vulkan.surface != 0,
        });
    }

    /// Describe the window-to-compositor chain. Called on the run's periodic
    /// checkpoint so a black window's evidence does not have to wait for the
    /// run to end.
    pub fn reportPresentChain(self: *Bridge) void {
        self.reportArgumentWidths(false);
        self.forwarder.reportPresentChain(false);
    }

    /// Force the complete window/Vulkan/pixel snapshot at run termination.
    /// Keeping this separate from the periodic callback prevents a healthy
    /// run from repeating the same topology at every step checkpoint.
    pub fn reportPresentChainFull(self: *Bridge) void {
        self.reportArgumentWidths(true);
        self.reportScratchStacks();
        self.reportHostTime();
        self.forwarder.reportPresentChain(true);
    }

    /// The guest-heap cost of the Microsoft-ABI boundary itself.
    ///
    /// `allocations` is the number of scratch stacks this bridge has ever
    /// taken from the guest heap; it is the nesting depth actually reached,
    /// not the call count. A run whose `allocations` tracks its `reuses` is
    /// the leak that exhausted the heap at 3.8M calls, back again.
    fn noteHostTime(self: *Bridge, name: []const u8, spent: u64) void {
        const key = @intFromPtr(name.ptr) ^ (name.len << 48);
        var slot = (key ^ (key >> 17)) % host_time_slots;
        var probes: usize = 0;
        while (probes < host_time_slots) : (probes += 1) {
            const entry = &self.host_time_entries[slot];
            if (entry.key == key) {
                entry.calls +|= 1;
                entry.ns +|= spent;
                entry.max_ns = @max(entry.max_ns, spent);
                return;
            }
            if (entry.key == 0) {
                entry.key = key;
                const len = @min(name.len, entry.name.len);
                @memcpy(entry.name[0..len], name[0..len]);
                entry.name_len = @intCast(len);
                entry.calls = 1;
                entry.ns = spent;
                entry.max_ns = spent;
                return;
            }
            slot = (slot + 1) % host_time_slots;
        }
        self.host_time_overflow_ns +|= spent;
    }

    /// The entry points that held the host thread longest, merged by name.
    pub fn hostTimeLeaders(self: *const Bridge, out: []HostTimeEntry) usize {
        var count: usize = 0;
        for (self.host_time_entries) |entry| {
            if (entry.key == 0) continue;
            var merged = false;
            for (out[0..count]) |*existing| {
                if (std.mem.eql(u8, existing.label(), entry.label())) {
                    existing.calls +|= entry.calls;
                    existing.ns +|= entry.ns;
                    existing.max_ns = @max(existing.max_ns, entry.max_ns);
                    merged = true;
                    break;
                }
            }
            if (merged) continue;
            if (count < out.len) {
                out[count] = entry;
                count += 1;
            } else {
                // Replace the smallest leader if this one outweighs it.
                var smallest: usize = 0;
                for (out[1..count], 1..) |existing, index| {
                    if (existing.ns < out[smallest].ns) smallest = index;
                }
                if (entry.ns > out[smallest].ns) out[smallest] = entry;
            }
        }
        std.mem.sort(HostTimeEntry, out[0..count], {}, struct {
            fn more(_: void, a: HostTimeEntry, b: HostTimeEntry) bool {
                return a.ns > b.ns;
            }
        }.more);
        return count;
    }

    fn reportHostTime(self: *const Bridge) void {
        var leaders: [12]HostTimeEntry = undefined;
        const count = self.hostTimeLeaders(&leaders);
        for (leaders[0..count], 1..) |entry, rank| {
            log.info("Vulkan host time by entry point: rank={d} name={s} calls={d} host_ms={d} mean_us={d} max_ms={d}", .{
                rank,
                entry.label(),
                entry.calls,
                entry.ns / 1_000_000,
                if (entry.calls == 0) 0 else entry.ns / entry.calls / 1_000,
                entry.max_ns / 1_000_000,
            });
        }
        log.info("Vulkan host time: calls={d} host_ms={d} mean_ns={d} max_ns={d}; native Vulkan work done on the one host thread every guest thread runs on, so this much wall time is what a second host thread could take off the guest before any memory model is needed", .{
            self.host_timed_calls,
            self.host_ns / 1_000_000,
            if (self.host_timed_calls == 0) 0 else self.host_ns / self.host_timed_calls,
            self.host_ns_max,
        });
    }

    fn reportScratchStacks(self: *const Bridge) void {
        log.info("Vulkan ABI scratch stacks: allocations={d} reuses={d} overflow_allocations={d} bytes_each={d} cache_depth={d} live_depth={d} guest_heap_bytes_held={d}; one stack per nesting level serves every call, because a dispatch owns it for exactly its own duration", .{
            self.scratch_stack_allocations,
            self.scratch_stack_reuses,
            self.scratch_stack_overflow_allocations,
            scratch_stack_bytes,
            scratch_stack_cache_depth,
            self.scratch_stack_depth,
            (self.scratch_stack_allocations +| self.scratch_stack_overflow_allocations) *| scratch_stack_bytes,
        });
    }

    pub fn updateGuestProgress(
        self: *Bridge,
        steps: u64,
        rip: u64,
        thread: u64,
        operation: []const u8,
        frontier_is_bounded: bool,
    ) void {
        self.forwarder.noteGuestExecutionProgress(steps, rip, thread, operation, frontier_is_bounded);
    }

    /// Dispatch a Windows Vulkan import through the real Rosette Vulkan
    /// forwarder. `false` means this adapter does not own the name, so the
    /// normal Windows runtime may apply its explicit modelled path.
    pub fn dispatch(self: *Bridge, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
        if (vulkan_contract.isProcLookup(name)) return self.lookupWindowsProc(state, direct_return_rip);
        if (!owns(name)) return false;
        self.dispatch_attempts +|= 1;
        const outermost = self.dispatch_depth == 0;
        self.dispatch_depth +|= 1;
        const started_ns: u64 = if (outermost) gpu.vulkan.transport_timing.nowNs() else 0;
        defer {
            self.dispatch_depth -|= 1;
            if (outermost and started_ns != 0) {
                const now = gpu.vulkan.transport_timing.nowNs();
                if (now >= started_ns) {
                    const spent = now - started_ns;
                    self.host_ns +|= spent;
                    self.host_ns_max = @max(self.host_ns_max, spent);
                    self.host_timed_calls +|= 1;
                    self.noteHostTime(name, spent);
                }
            }
        }
        const call_id = self.dispatch_attempts;
        const trace_boundary = self.shouldTraceBoundary(name);
        var trace_outcome: []const u8 = "not_completed";
        if (trace_boundary) {
            self.logBoundaryEnter(state, name, call_id, direct_return_rip);
        }
        defer {
            const failed = !std.mem.eql(u8, trace_outcome, "forwarded");
            if (trace_boundary or (failed and self.shouldLogBoundaryFailure())) {
                self.logBoundaryExit(state, name, call_id, trace_outcome);
            }
        }

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
        const signature = vulkan_contract.argument_widths.lookup(name) orelse {
            self.dispatch_failures +|= 1;
            trace_outcome = "argument_signature_missing";
            return false;
        };
        if (std.mem.eql(u8, name, "vkCreateWin32SurfaceKHR")) {
            if (!ensureWindow(state)) {
                self.dispatch_failures +|= 1;
                trace_outcome = "window_unavailable";
                return false;
            }
        }
        const scratch_stack = self.acquireScratchStack(state) orelse {
            self.dispatch_failures +|= 1;
            trace_outcome = "scratch_stack_unavailable";
            return false;
        };
        defer self.releaseScratchStack();
        // A first allocation arrives zeroed; a reused one still carries the
        // previous call's bytes. Every stack-argument slot is rewritten below
        // whether or not this signature declares it, so clearing the return
        // slot is all that reuse needs to be byte-identical to a fresh one.
        state.write64(scratch_stack, 0);

        // Read declared parameters, not entire untyped eight-byte values.
        // DWORD stack stores leave the upper half unspecified; forwarding
        // that half made count=2 become 0x1_00000002 and dropped every bind.
        // Normalize registers too, while preserving full 64-bit pointers,
        // handles, VkDeviceSize, size_t, device addresses and timeouts.
        const has_direct_return = direct_return_rip != null;
        var arguments: [6 + max_stack_arguments]u64 = @splat(0);
        std.debug.assert(signature.argument_count <= arguments.len);
        const normalization_before = self.scalar_width_normalizations;
        for (0..signature.argument_count) |index| {
            const raw = switch (index) {
                0 => original_regs.rcx,
                1 => original_regs.rdx,
                2 => original_regs.r8,
                3 => original_regs.r9,
                else => state.read64(original_regs.rsp +| microsoftStackArgumentOffset(index, has_direct_return)),
            };
            arguments[index] = self.normalizeMicrosoftArgument(name, signature, index, raw);
        }
        if (normalization_before != self.scalar_width_normalizations) self.scalar_width_normalized_calls +|= 1;
        for (0..max_stack_arguments) |index| {
            state.write64(scratch_stack +| 8 +| @as(u64, @intCast(index * 8)), arguments[index + 6]);
        }

        const mapped = mapMicrosoftToSysV(
            .{
                .rcx = arguments[0],
                .rdx = arguments[1],
                .r8 = arguments[2],
                .r9 = arguments[3],
            },
            arguments[4],
            arguments[5],
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

        const original_xmm = state.xmm;
        defer state.xmm = original_xmm;
        mapWindowsScalarFloats(&state.xmm, name);
        const command = std.mem.startsWith(u8, name, "vkCmd");
        const native_commands_before = self.forwarder.vulkan_real_command_calls;
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
        // Every void command has an actual native-call admission ledger.
        // Handling a thunk is not proof that its native marshaller accepted
        // the guest's pointers/handles. Never inflate the PE graphics chain
        // for a rejected command; leave the precise name/site in the ledger.
        const reached_native_command = !command or
            self.forwarder.vulkan_real_command_calls != native_commands_before;
        if (reached_native_command) {
            noteNativeForwarding(state, name, native_objects_ready);
            noteLogicalContract(state, name, result);
        }
        noteForwarderFrameEvidence(self, state);
        finishWindowsCall(state, direct_return_rip);
        trace_outcome = if (reached_native_command) "forwarded" else "handled_native_refused";
        return true;
    }

    /// Apply native capability gating before minting a Microsoft-ABI thunk.
    /// A native/SysV token must never escape into the Windows function table.
    fn lookupWindowsProc(self: *Bridge, state: anytype, direct_return_rip: ?u64) bool {
        const requested = state.guestCString(state.regs.rdx, 512) orelse {
            state.regs.rax = 0;
            finishWindowsCall(state, direct_return_rip);
            return true;
        };
        state.windows_graphics.noteProcAddressQuery(requested);
        const library = self.ensureLibrary() orelse {
            state.regs.rax = 0;
            finishWindowsCall(state, direct_return_rip);
            return true;
        };
        const native_name = if (std.mem.eql(u8, requested, "vkCreateWin32SurfaceKHR")) "vkCreateMetalSurfaceEXT" else requested;
        const available = self.forwarder.lookupVulkanProcGuest(library, native_name) != 0;
        state.regs.rax = if (available) state.registerWindowsImportStub("vulkan-1.dll", requested) orelse 0 else 0;
        finishWindowsCall(state, direct_return_rip);
        return true;
    }

    fn ensureLibrary(self: *Bridge) ?u64 {
        if (self.library_token != 0) return self.library_token;
        self.library_token = self.forwarder.openGuest(vulkan_library_path, rtld_lazy | rtld_local);
        return if (self.library_token != 0) self.library_token else null;
    }
};

fn mapWindowsScalarFloats(xmm: anytype, name: []const u8) void {
    const count = vulkan_contract.scalarFloatCount(name);
    for (0..count) |index| xmm[index] = xmm[index + 1];
}

fn owns(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "vk")) return false;
    // Proc lookup has its own path above: it returns Microsoft-ABI stubs
    // after consulting the same native capability gate as direct dispatch.
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
    // VkResult reserves negative values for failures; positive values such as
    // VK_SUBOPTIMAL_KHR, VK_TIMEOUT, and VK_NOT_READY are still valid driver
    // outcomes and must not inflate the native-failure ledger.
    const vk_result: i32 = @bitCast(@as(u32, @truncate(result)));
    const ok = vulkan_contract.completesOperation(name, vk_result);
    // Only these entry points return VkResult.  Void commands leave rax
    // unspecified, so treating its stale value as an error turns ordinary
    // command traffic into a false native-failure count.
    const result_bearing = std.mem.eql(u8, name, "vkCreateInstance") or
        std.mem.eql(u8, name, "vkCreateWin32SurfaceKHR") or
        std.mem.eql(u8, name, "vkCreateDevice") or
        std.mem.eql(u8, name, "vkCreateSwapchainKHR") or
        std.mem.eql(u8, name, "vkGetSwapchainImagesKHR") or
        vulkan_contract.isAcquire(name) or
        std.mem.eql(u8, name, "vkQueueSubmit") or
        (std.mem.eql(u8, name, "vkQueueSubmit2") or std.mem.eql(u8, name, "vkQueueSubmit2KHR")) or
        std.mem.eql(u8, name, "vkQueuePresentKHR");
    if (result_bearing) state.windows_graphics.noteNativeVulkanResult(name, vk_result >= 0);
    if (std.mem.eql(u8, name, "vkCreateInstance")) {
        _ = state.windows_graphics.noteCreateInstance(ok);
    } else if (std.mem.eql(u8, name, "vkCreateWin32SurfaceKHR")) {
        _ = state.windows_graphics.noteCreateSurface(ok);
    } else if (std.mem.eql(u8, name, "vkCreateDevice")) {
        _ = state.windows_graphics.noteCreateDevice(ok);
    } else if (std.mem.eql(u8, name, "vkGetDeviceQueue") or
        std.mem.eql(u8, name, "vkGetDeviceQueue2"))
    {
        _ = state.windows_graphics.noteGetQueue(true);
    } else if (std.mem.eql(u8, name, "vkCreateSwapchainKHR")) {
        _ = state.windows_graphics.noteCreateSwapchain(ok);
    } else if (std.mem.eql(u8, name, "vkGetSwapchainImagesKHR")) {
        _ = state.windows_graphics.noteSwapchainImages(ok);
    } else if (vulkan_contract.isAcquire(name)) {
        // Timeout/not-ready is neither a failure nor an acquired frame.
        if (ok) _ = state.windows_graphics.noteAcquire(true);
    } else if (std.mem.eql(u8, name, "vkQueueSubmit") or
        (std.mem.eql(u8, name, "vkQueueSubmit2") or std.mem.eql(u8, name, "vkQueueSubmit2KHR")))
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

fn noteForwarderFrameEvidence(self: *const Bridge, state: anytype) void {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "windows_graphics")) return;
    const evidence = self.forwarder.guestFrameEvidence();
    state.windows_graphics.noteForwarderFrameEvidence(
        evidence.presents_with_target,
        evidence.presents_with_content,
        evidence.presents_clear_only,
        evidence.presents_without_target,
        evidence.presents_without_write,
        evidence.native_present_requests,
        evidence.native_present_completions,
        evidence.native_queue_submits,
    );
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

test "Windows depth bias preserves all three scalar bit patterns" {
    var xmm: [16][16]u8 = @splat(@splat(0));
    const bits = [_]u32{ 0x3f800000, 0x80000000, 0xc0200000 };
    for (bits, 1..) |value, index| std.mem.writeInt(u32, xmm[index][0..4], value, .little);
    const saved = xmm;
    mapWindowsScalarFloats(&xmm, "vkCmdSetDepthBias");
    for (bits, 0..) |value, index| try std.testing.expectEqual(value, std.mem.readInt(u32, xmm[index][0..4], .little));
    xmm = saved;
    mapWindowsScalarFloats(&xmm, "vkCmdSetBlendConstants");
    try std.testing.expectEqualDeep(saved, xmm);
}

test "Xenia Windows GPU and UI entry points have a bridge dispatch contract" {
    for (vulkan_contract.xenia_entry_points) |name| {
        if (!owns(name) and !vulkan_contract.isProcLookup(name)) {
            std.debug.print("missing Windows Vulkan dispatch contract: {s}\n", .{name});
            return error.MissingVulkanDispatchContract;
        }
    }
}

test "Windows proc lookup keeps absent commands null and returns Windows thunks" {
    const State = struct {
        regs: struct { rax: u64 = 0, rdx: u64 = 0, rip: u64 = 0 } = .{},
        requested: []const u8 = "vkCmdUnknownRosetteCommand",
        registrations: u32 = 0,
        windows_graphics: struct {
            queries: u32 = 0,
            pub fn noteProcAddressQuery(self: *@This(), _: []const u8) void {
                self.queries += 1;
            }
        } = .{},
        pub fn guestCString(self: *@This(), _: u64, _: usize) ?[]const u8 {
            return self.requested;
        }
        pub fn registerWindowsImportStub(self: *@This(), _: []const u8, _: []const u8) ?u64 {
            self.registrations += 1;
            return 0x1234;
        }
        pub fn pop(_: *@This()) u64 {
            return 0x5678;
        }
    };
    var bridge = Bridge{};
    defer bridge.deinit();
    var state = State{};
    try std.testing.expect(bridge.lookupWindowsProc(&state, 0x9876));
    try std.testing.expectEqual(@as(u64, 0), state.regs.rax);
    try std.testing.expectEqual(@as(u32, 0), state.registrations);
    state.requested = "vkCreateWin32SurfaceKHR";
    try std.testing.expect(bridge.lookupWindowsProc(&state, null));
    try std.testing.expectEqual(@as(u64, 0x1234), state.regs.rax);
    try std.testing.expectEqual(@as(u64, 0x5678), state.regs.rip);
    bridge.forwarder.real_vulkan.device = @ptrFromInt(0x1000);
    bridge.forwarder.real_vulkan.fn_ptrs.resolved = true;
    state.requested = "vkCmdBeginConditionalRenderingEXT";
    try std.testing.expect(bridge.lookupWindowsProc(&state, null));
    try std.testing.expectEqual(@as(u64, 0), state.regs.rax);
    try std.testing.expectEqual(@as(u32, 1), state.registrations);
    // The device is a test sentinel, not an owned native object.
    bridge.forwarder.real_vulkan.device = null;
}

test "Windows Vulkan scratch stacks are reused rather than leaked per call" {
    // A bump allocator with the same failure shape as the guest heap: once the
    // cursor passes the limit it refuses, which is exactly what ended the
    // 3,823,761st Vulkan call of the Halo 3 run.
    // Successive aligned allocations advance by the padded stride, not by the
    // request, so size the arena for exactly three of them.
    const stride = (scratch_stack_bytes + scratch_stack_alignment - 1) & ~(scratch_stack_alignment - 1);
    const State = struct {
        next: u64 = 0x1000,
        limit: u64 = 0x1000 + 3 * ((scratch_stack_bytes + scratch_stack_alignment - 1) & ~(scratch_stack_alignment - 1)),
        allocations: u32 = 0,
        pub fn guestAlloc(self: *@This(), size: u64, alignment: u64) ?u64 {
            const mask = alignment - 1;
            const aligned = (self.next + mask) & ~mask;
            if (aligned + size > self.limit) return null;
            self.next = aligned + size;
            self.allocations += 1;
            return aligned;
        }
    };

    var bridge = Bridge{};
    defer bridge.deinit();
    var state = State{};

    // The leak this replaces took one allocation per call. A thousand
    // sequential calls must take exactly one, at one address.
    const first = bridge.acquireScratchStack(&state).?;
    bridge.releaseScratchStack();
    for (0..999) |_| {
        try std.testing.expectEqual(first, bridge.acquireScratchStack(&state).?);
        bridge.releaseScratchStack();
    }
    try std.testing.expectEqual(@as(u32, 1), state.allocations);
    try std.testing.expectEqual(@as(u64, 1), bridge.scratch_stack_allocations);
    try std.testing.expectEqual(@as(u64, 999), bridge.scratch_stack_reuses);
    try std.testing.expectEqual(@as(usize, 0), bridge.scratch_stack_depth);

    // A nested dispatch must never be handed the stack its caller is standing
    // on, so each depth owns a distinct address.
    const outer = bridge.acquireScratchStack(&state).?;
    const inner = bridge.acquireScratchStack(&state).?;
    try std.testing.expectEqual(first, outer);
    try std.testing.expectEqual(outer + stride, inner);
    try std.testing.expectEqual(@as(usize, 2), bridge.scratch_stack_depth);
    bridge.releaseScratchStack();
    bridge.releaseScratchStack();
    try std.testing.expectEqual(@as(usize, 0), bridge.scratch_stack_depth);
    try std.testing.expectEqual(@as(u64, 2), bridge.scratch_stack_allocations);

    // The allocator has one scratch stack left. Nesting past the cache falls
    // back to a fresh allocation and says so, rather than aliasing a live one.
    bridge.scratch_stack_depth = scratch_stack_cache_depth;
    const overflow = bridge.acquireScratchStack(&state).?;
    try std.testing.expect(overflow != outer and overflow != inner);
    try std.testing.expectEqual(@as(u64, 1), bridge.scratch_stack_overflow_allocations);
    bridge.releaseScratchStack();
    try std.testing.expectEqual(@as(usize, scratch_stack_cache_depth), bridge.scratch_stack_depth);

    // Exhausted: the refusal is reported, and it does not leave the bridge
    // believing a dispatch is live.
    bridge.scratch_stack_depth = scratch_stack_cache_depth;
    try std.testing.expect(bridge.acquireScratchStack(&state) == null);
    try std.testing.expectEqual(@as(usize, scratch_stack_cache_depth), bridge.scratch_stack_depth);
    bridge.scratch_stack_depth = 2;
    try std.testing.expect(bridge.acquireScratchStack(&state) == null);
    try std.testing.expectEqual(@as(usize, 2), bridge.scratch_stack_depth);
    try std.testing.expectEqual(@as(u32, 3), state.allocations);
}

test "Vulkan host time is split by entry point and ranked by wall time" {
    var bridge = Bridge{};
    defer bridge.deinit();
    const compile = "vkCreateGraphicsPipelines";
    const wait = "vkWaitForFences";
    const draw = "vkCmdDraw";
    bridge.noteHostTime(compile, 90_000_000);
    bridge.noteHostTime(compile, 10_000_000);
    bridge.noteHostTime(wait, 30_000_000);
    for (0..1000) |_| bridge.noteHostTime(draw, 1_000);
    var leaders: [2]HostTimeEntry = undefined;
    const count = bridge.hostTimeLeaders(&leaders);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings(compile, leaders[0].label());
    try std.testing.expectEqual(@as(u64, 2), leaders[0].calls);
    try std.testing.expectEqual(@as(u64, 100_000_000), leaders[0].ns);
    try std.testing.expectEqual(@as(u64, 90_000_000), leaders[0].max_ns);
    try std.testing.expectEqualStrings(wait, leaders[1].label());
}
