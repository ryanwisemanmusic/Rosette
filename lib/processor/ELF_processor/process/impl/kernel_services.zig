const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_block_jit = @import("block_jit.zig");
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_heap = @import("guest_heap.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_instruction_decode = @import("instruction_decode.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_run_reporting = @import("run_reporting.zig");
const process_impl_windows_sync = @import("windows_sync.zig");
const __process_DecodedInsn = __ProcessInternals._DecodedInsn;
const __process_ElfRegs = __ProcessInternals._ElfRegs;
const __process_GUEST_FILE_REQUEST_PREVIEW_BYTES = __ProcessInternals._GUEST_FILE_REQUEST_PREVIEW_BYTES;
const __process_GuestFileNameShape = __ProcessInternals._GuestFileNameShape;
const __process_GuestFileRequest = __ProcessInternals._GuestFileRequest;
const __process_GuestSymbol = __ProcessInternals._GuestSymbol;
const __process_GuestVfsResolve = __ProcessInternals._GuestVfsResolve;
const __process_PPC_CONTEXT_LINK_REGISTER = __ProcessInternals._PPC_CONTEXT_LINK_REGISTER;
const __process_PPC_CONTEXT_VIRTUAL_MEMBASE = __ProcessInternals._PPC_CONTEXT_VIRTUAL_MEMBASE;
const __process_WINDOWS_GUEST_THREAD_NAME_BYTES = __ProcessInternals._WINDOWS_GUEST_THREAD_NAME_BYTES;
const __process_WindowsGuestThread = __ProcessInternals._WindowsGuestThread;
const __process_WindowsHeapCallSite = __ProcessInternals._WindowsHeapCallSite;
const __process_WindowsHeapCodeSnapshot = __ProcessInternals._WindowsHeapCodeSnapshot;
const __process_WindowsHeapStackSnapshot = __ProcessInternals._WindowsHeapStackSnapshot;
const __process_WindowsImportCallsite = __ProcessInternals._WindowsImportCallsite;
const __process_WindowsImportStub = __ProcessInternals._WindowsImportStub;
const __process_WindowsImportStubInterior = __ProcessInternals._WindowsImportStubInterior;
const __process_WindowsInputState = __ProcessInternals._WindowsInputState;
const __process_block_jit = __ProcessInternals._block_jit;
const __process_concurrency = __ProcessInternals._concurrency;
const __process_decodeInsn = __ProcessInternals._decodeInsn;
const __process_elf_loader = __ProcessInternals._elf_loader;
const __process_exit_diagnostics = __ProcessInternals._exit_diagnostics;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_heap_guard = __ProcessInternals._heap_guard;
const __process_host_profile = __ProcessInternals._host_profile;
const __process_import_lock_requested_ns = __ProcessInternals._import_lock_requested_ns;
const __process_kernel_call_census = __ProcessInternals._kernel_call_census;
const __process_log = __ProcessInternals._log;
const __process_monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const __process_ppcContextGpr = __ProcessInternals._ppcContextGpr;
const __process_runtime_lock_released_ns = __ProcessInternals._runtime_lock_released_ns;
const __process_screen_validity = __ProcessInternals._screen_validity;
const __process_std = __ProcessInternals._std;
const __process_terminal_event = __ProcessInternals._terminal_event;
const __process_windowsFileErrorLabel = __ProcessInternals._windowsFileErrorLabel;
const __process_windows_guest_abi = __ProcessInternals._windows_guest_abi;
const __process_x64_decoder = __ProcessInternals._x64_decoder;
const __process_x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const __process_xbox_critical_section = __ProcessInternals._xbox_critical_section;
const __process_xenia_event_audit = __ProcessInternals._xenia_event_audit;
const __process_xenia_guest_frontier_map = __ProcessInternals._xenia_guest_frontier_map;
const __process_xenia_guest_milestone_map = __ProcessInternals._xenia_guest_milestone_map;
const __process_xmutant_release_compat = __ProcessInternals._xmutant_release_compat;
const __process_xmutant_teardown_compat = __ProcessInternals._xmutant_teardown_compat;
const __state_MilestoneReach = __StateInternals._MilestoneReach;

pub fn armGuestKernelShim(self: *ElfState, mangled: []const u8, address: u64) void {
    self.guest_kernel_symbols_offered +|= 1;
    _ = self.guest_kernel_calls.arm(self.allocator, mangled, address);
    // The Xbox critical-section bridge is keyed only by a registered
    // export trampoline. The `_entry` forwarder remains ordinary guest
    // code and is reached only when an export was not recognized here.
    if (self.guest_kernel_calls.exportAt(address)) |slot| {
        if (slot.kind == .trampoline) _ = self.xbox_critical_section_hooks.arm(slot.export_name, address);
    }
}

pub fn reportGuestKernelShimArming(self: *const ElfState) void {
    if (self.guest_kernel_symbols_offered == 0) {
        __process_log.info("PE64 GUEST KERNEL CALLS: not armed; nothing offered this run a symbol table, so every export reads zero for a reason that has nothing to do with the title", .{});
        return;
    }
    if (self.guest_kernel_calls.armed == 0) {
        __process_log.info("PE64 GUEST KERNEL CALLS: 0 export shims armed from {d} symbol(s); this image does not carry Xenia's `<Export>_entry` functions, so the title's kernel traffic cannot be observed", .{
            self.guest_kernel_symbols_offered,
        });
        return;
    }
    __process_log.info("PE64 GUEST KERNEL CALLS: armed {d} registered kernel export trampoline(s) and {d} `_entry` forwarder(s) from {d} image symbol(s) across xboxkrnl/xam/xbdm. The trampoline is what a title's import resolves to and nothing but the guest reaches it, so entry into one is the only event in the program that proves the title acted{s}", .{
        self.guest_kernel_calls.armed_trampolines,
        self.guest_kernel_calls.armed - self.guest_kernel_calls.armed_trampolines,
        self.guest_kernel_symbols_offered,
        if (self.guest_kernel_calls.overflowed != 0) " (SOME DID NOT FIT: the census is incomplete)" else "",
    });
    if (self.guest_kernel_calls.overflowed != 0) {
        __process_log.warn("PE64 GUEST KERNEL CALLS: {d} shim(s) did not fit the census table; raise kernel_call_census.slot_count", .{
            self.guest_kernel_calls.overflowed,
        });
    }
}

pub fn noteGuestKernelCall(self: *ElfState, target: u64) void {
    noteGuestKernelEntry(self, target, false);
}

pub fn noteGuestKernelTailJump(self: *ElfState, target: u64) void {
    noteGuestKernelEntry(self, target, true);
}

pub fn noteGuestKernelEntry(self: *ElfState, target: u64, via_jump: bool) void {
    if (!self.guest_kernel_calls.contains(target)) return;
    // Counting takes no lock (`Census.note` is atomic): every kernel call
    // of every title thread passes here. Only the two entries that touch
    // shared runtime state take the runtime lock.
    const accounting_step = process_impl_run_reporting.totalInterpretedSteps(self);
    const slot_index = self.guest_kernel_calls.note(target, accounting_step);
    if (slot_index == 0) return;
    if (self.guest_kernel_calls.saturationDue(slot_index)) decideGuestKernelSaturation(self, slot_index);
    if (via_jump) _ = @atomicRmw(u64, &self.guest_kernel_calls.tail_jump_entries, .Add, 1, .monotonic);
    if (self.guest_kernel_calls.slotAt(slot_index)) |slot| {
        const file_request = slot.kind == .trampoline and isGuestFileRequestExport(slot.export_name);
        const swap = slot.kind == .trampoline and __process_std.mem.eql(u8, slot.export_name, "VdSwap");
        if (file_request or swap) {
            var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
            defer if (runtime_guard) |*guard| guard.unlock();
            if (file_request) captureGuestFileRequest(self, slot_index);
            // VdSwap is the guest-owned presentation boundary. The ring
            // decoder may not have consumed the matching XE_SWAP yet, so
            // this first attempt is deliberately paired with retries from
            // the ring and checkpoint paths below.
            if (swap) _ = process_impl_guest_diagnostics.offerGuestFrontBufferToNativePresenter(self);
        }
    }
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| {
        const thread = &self.windows_guest_threads[slot];
        thread.last_kernel_slot = slot_index;
        thread.last_kernel_step = accounting_step;
        thread.kernel_calls +|= 1;
        if (self.guest_kernel_calls.slotAt(slot_index)) |entry| {
            if (entry.subsystem == .scheduling) {
                if (captureXeniaEventCall(self, entry, accounting_step)) |event_call| {
                    thread.last_xenia_event_call = event_call;
                }
            }
            if (entry.kind == .trampoline and __process_std.mem.eql(u8, entry.export_name, "RtlEnterCriticalSection")) {
                const context = process_impl_lifecycle.guestContextField(self, "regs").*.rcx;
                thread.critical_section_membase = readHostU64(self, context + __process_PPC_CONTEXT_VIRTUAL_MEMBASE) orelse 0;
                thread.critical_section = @truncate(readHostU64(self, context + __process_ppcContextGpr(3)) orelse 0);
            }
        }
    }
}

pub fn decideGuestKernelSaturation(self: *ElfState, slot_index: u32) void {
    const slot = self.guest_kernel_calls.slotAt(slot_index) orelse return;
    const pinned = guestKernelExportPinned(self, slot);
    if (!self.guest_kernel_calls.decideSaturation(slot_index, if (pinned) .pinned else .saturated)) return;
    if (pinned) return;
    process_impl_block_jit.publishBlockJitHookFilter(self);
    const saturated = @atomicRmw(u32, &self.guest_kernel_census_saturations, .Add, 1, .monotonic) + 1;
    if (saturated <= 16 or saturated & (saturated - 1) == 0) {
        __process_log.info("PE64 GUEST KERNEL CALLS: {s} saturated after {d} calls; translated calls to it no longer leave for the interpreter to be counted, so its count is a lower bound from here (saturated exports: {d})", .{
            slot.export_name,
            __process_kernel_call_census.saturation_calls,
            saturated,
        });
    }
}

pub fn guestKernelExportPinned(self: *const ElfState, slot: *const __process_kernel_call_census.Slot) bool {
    if (self.xbox_critical_section_hooks.at(slot.address) != null) return true;
    if (slot.kind != .trampoline) return false;
    const name = slot.export_name;
    if (__process_std.mem.eql(u8, name, "VdSwap") or isGuestFileRequestExport(name)) return true;
    inline for (.{ "XamInputGetState", "XamInputGetCapabilities", "XamInputGetCapabilitiesEx", "XamInputSetState" }) |input| {
        if (__process_std.mem.eql(u8, name, input)) return true;
    }
    return false;
}

pub fn isGuestFileRequestExport(export_name: []const u8) bool {
    return __process_std.mem.eql(u8, export_name, "NtCreateFile") or __process_std.mem.eql(u8, export_name, "NtOpenFile");
}

pub fn activeGuestFileRequest(self: *ElfState) *__process_GuestFileRequest {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| return &self.windows_guest_threads[slot].file_request;
    return &self.owner_file_request;
}

pub fn xeniaGuestBytes(self: *const ElfState, membase: u64, guest_address: u32, count: u64) ?[]const u8 {
    const adjust: u64 = if (guest_address >= 0xE000_0000) 0x1000 else 0;
    return process_impl_execution.guestMemoryConst(self, membase + guest_address + adjust, count);
}

pub fn xeniaGuestVirtualAddress(membase: u64, guest_address: u32) u64 {
    const adjust: u64 = if (guest_address >= 0xE000_0000) 0x1000 else 0;
    return membase + guest_address + adjust;
}

pub fn captureXeniaEventCall(self: *ElfState, slot: *const __process_kernel_call_census.Slot, accounting_step: u64) ?__process_xenia_event_audit.CallSnapshot {
    if (slot.kind != .trampoline or slot.module != .xboxkrnl or slot.subsystem != .scheduling) return null;
    const operation = __process_xenia_event_audit.Operation.forExport(slot.export_name) orelse return null;
    var snapshot: __process_xenia_event_audit.CallSnapshot = .{
        .operation = operation,
        .step = accounting_step,
        .context = process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
    };
    const context = snapshot.context;
    if (!process_impl_windows_sync.xboxHostBacked(self, context, __process_PPC_CONTEXT_VIRTUAL_MEMBASE + 8)) return snapshot;
    snapshot.membase = readHostU64(self, context + __process_PPC_CONTEXT_VIRTUAL_MEMBASE) orelse return snapshot;
    if (snapshot.membase == 0) return snapshot;

    snapshot.guest_event = @truncate(readHostU64(self, context + __process_ppcContextGpr(3)) orelse return snapshot);
    if (operation == .initialize or operation == .set or operation == .pulse) {
        snapshot.argument2 = @truncate(readHostU64(self, context + __process_ppcContextGpr(4)) orelse 0);
        snapshot.argument3 = @truncate(readHostU64(self, context + __process_ppcContextGpr(5)) orelse 0);
    }
    if (snapshot.guest_event == 0) return snapshot;
    snapshot.host_event = xeniaGuestVirtualAddress(snapshot.membase, snapshot.guest_event);
    if (xeniaGuestBytes(self, snapshot.membase, snapshot.guest_event, 16)) |bytes| {
        snapshot.header = __process_xenia_event_audit.parseHeader(bytes);
    }
    return snapshot;
}

pub fn readHostU64(self: *const ElfState, address: u64) ?u64 {
    // Scalar loads already forward this executor's store buffer and use
    // the acquire/stripe path in parallel mode. Returning a borrowed
    // view here would unnecessarily publish all of its queued stores.
    const bytes = process_impl_execution.guestMemorySourceConst(self, address, 8) orelse return null;
    return process_impl_guest_memory.loadGuestScalar(self, u64, bytes);
}

pub fn noteStackPointerCollapse(self: *ElfState, via: []const u8, rsp_before: u64, rip_before: u64, detail: []const u8) void {
    if (self.stack_collapse_reports >= 8) return;
    self.stack_collapse_reports += 1;
    const name = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot|
        (if (self.windows_guest_threads[slot].name_len != 0) self.windows_guest_threads[slot].nameText() else "<unnamed>")
    else
        "<owner>";
    var symbol_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    __process_log.err("PE64 STACK POINTER COLLAPSE: thread='{s}' via={s} rsp_before=0x{x} rsp_after=0x{x} rip_before=0x{x} ({s}) rip_after=0x{x} detail={s} exception_dispatches_in_flight={d}; no stack lives in the null page, so the code named here wrote rsp", .{
        name,
        via,
        rsp_before,
        process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        rip_before,
        describeGuestAddressOrUnnamed(self, rip_before, &symbol_text),
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        detail,
        self.guest_exception_dispatches_in_flight,
    });
}

pub fn noteStackPointerCollapseInBlocks(self: *ElfState, rsp_before: u64, rip_before: u64, last: *__process_block_jit.Block, completed: u32) void {
    if (self.stack_collapse_reports >= 8) return;
    noteStackPointerCollapse(self, "translated-blocks", rsp_before, rip_before, "see PE64 STACK POINTER COLLAPSE BLOCK");
    const previous: ?*const __process_block_jit.Block = process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.chain_previous;
    const Shown = struct { block: *const __process_block_jit.Block, retired: usize, position: []const u8 };
    var shown: [2]Shown = undefined;
    var count: usize = 0;
    if (previous) |before| {
        if (before != last) {
            shown[count] = .{ .block = before, .retired = before.insns.len, .position = "previous" };
            count += 1;
        }
    }
    shown[count] = .{ .block = last, .retired = @min(@as(usize, @max(completed, 1)), last.insns.len), .position = "last" };
    count += 1;
    for (shown[0..count]) |entry| {
        var ops: [640]u8 = undefined;
        var used: usize = 0;
        for (entry.block.insns[0..entry.retired]) |insn| {
            const text = __process_std.fmt.bufPrint(ops[used..], "0x{x}:{s} ", .{ insn.rip, @tagName(insn.decoded.op) }) catch break;
            used += text.len;
        }
        __process_log.err("PE64 STACK POINTER COLLAPSE BLOCK: position={s} start=0x{x} retired={d} ops={s}", .{ entry.position, entry.block.start_rip, entry.retired, ops[0..used] });
    }
}

pub fn logCriticalSectionWait(self: *const ElfState, thread: *const __process_WindowsGuestThread) void {
    const bytes = xeniaGuestBytes(self, thread.critical_section_membase, thread.critical_section, __process_xbox_critical_section.Offset.size) orelse {
        __process_log.info("PE64 CRITICAL SECTION WAIT: thread=0x{x} section=0x{x} unreadable", .{ thread.handle, thread.critical_section });
        return;
    };
    const snapshot = __process_xbox_critical_section.readSnapshot(bytes) orelse return;
    const verdict = if (!snapshot.initialized())
        "never initialized: RtlInitializeCriticalSection did not reach this structure, so a zero lock_count already reads as held and nobody will ever release it"
    else if (snapshot.strandedWaiter())
        "no owner, no pending wake, and waiters counted: the release that should have woken this thread was lost"
    else if (snapshot.owner != 0)
        "held: the owner KTHREAD has not left it; find which thread that is and what it waits on"
    else
        "free: the waiter should be runnable";
    var owner_text: [96]u8 = undefined;
    const owner_name = if (process_impl_windows_sync.windowsThreadForXboxKthread(self, snapshot.owner)) |owner|
        __process_std.fmt.bufPrint(&owner_text, "'{s}' {s}", .{ if (owner.name_len != 0) owner.nameText() else "<unnamed>", @tagName(owner.status) }) catch "?"
    else if (snapshot.owner == 0) "none" else "a KTHREAD no worker has reported";
    __process_log.info("PE64 CRITICAL SECTION WAIT: thread=0x{x} name='{s}' section=0x{x} header_type={d} owner_kthread=0x{x} ({s}) lock_count={d} recursion={d} header_signal={d}; {s}", .{
        thread.handle,
        if (thread.name_len != 0) thread.nameText() else "<unnamed>",
        thread.critical_section,
        snapshot.header_type,
        snapshot.owner,
        owner_name,
        snapshot.lock_count,
        snapshot.recursion,
        snapshot.signal_state,
        verdict,
    });
}

pub fn describeXboxCriticalSectionWait(self: *const ElfState, section: u64, buffer: []u8) []const u8 {
    const bytes = process_impl_execution.guestMemoryConst(self, section, __process_xbox_critical_section.Offset.size) orelse return " (xbox section unreadable)";
    const snapshot = __process_xbox_critical_section.readSnapshot(bytes) orelse return "";
    var name_text: [64]u8 = undefined;
    const owner_name = if (process_impl_windows_sync.windowsThreadForXboxKthread(self, snapshot.owner)) |owner|
        __process_std.fmt.bufPrint(&name_text, "'{s}' {s}", .{ if (owner.name_len != 0) owner.nameText() else "<unnamed>", @tagName(owner.status) }) catch "?"
    else if (snapshot.owner == 0) "none" else "unreported KTHREAD";
    return __process_std.fmt.bufPrint(buffer, " (xbox section owner_kthread=0x{x} {s} lock_count={d} recursion={d} signal={d})", .{
        snapshot.owner,
        owner_name,
        snapshot.lock_count,
        snapshot.recursion,
        snapshot.signal_state,
    }) catch "";
}

pub fn readWindowsInputState(self: *ElfState) ?__process_WindowsInputState {
    const callback = self.windows_input_hooks.read_controller_state orelse return null;
    var value: __process_WindowsInputState = .{};
    self.windows_input_polls +|= 1;
    if (callback(self.windows_input_hooks.context, &value) == 0 or value.connected == 0) {
        self.windows_input_invalid_polls +|= 1;
        if (__process_host_profile.active()) self.frame_input_activity.noteInvalidPoll();
        return null;
    }
    self.windows_input_bridged_polls +|= 1;
    self.windows_input_last_packet = value.packet_number;
    self.windows_input_last_buttons = value.buttons;
    self.windows_input_last_focused = value.focused != 0;
    self.windows_input_key_down_events = value.key_down_events;
    self.windows_input_key_up_events = value.key_up_events;
    self.windows_input_snapshot_reads = value.snapshot_reads;
    const nonzero = value.buttons != 0 or value.left_trigger != 0 or value.right_trigger != 0 or
        value.thumb_lx != 0 or value.thumb_ly != 0 or value.thumb_rx != 0 or value.thumb_ry != 0;
    if (__process_host_profile.active()) self.frame_input_activity.noteSuccessfulPoll(.{
        .key_down = value.key_down_events,
        .key_up = value.key_up_events,
        .focus_gains = value.focus_gain_events,
        .focus_losses = value.focus_loss_events,
        .rejected = value.rejected_key_events,
        .packet = value.packet_number,
        .buttons = value.buttons,
        .left_trigger = value.left_trigger,
        .right_trigger = value.right_trigger,
        .thumb_lx = value.thumb_lx,
        .thumb_ly = value.thumb_ly,
        .thumb_rx = value.thumb_rx,
        .thumb_ry = value.thumb_ry,
        .focused = value.focused != 0,
        .active = nonzero,
    });
    if (nonzero)
        self.windows_input_nonzero_samples +|= 1
    else if (value.focused != 0)
        self.windows_input_focused_zero_samples +|= 1;
    self.windows_input_focus_gains = value.focus_gain_events;
    self.windows_input_focus_losses = value.focus_loss_events;
    self.windows_input_rejected_events = value.rejected_key_events;
    self.windows_input_last_key_code = value.last_key_code;
    self.windows_input_contract_version = value.input_contract_version;
    self.windows_input_physical_connected = value.physical_controller_connected != 0;
    self.windows_input_physical_events = value.physical_controller_events;
    self.windows_input_physical_name = value.physical_controller_name;
    return value;
}

pub fn writeWindowsXInputState(self: *ElfState, output: u64) bool {
    const value = readWindowsInputState(self) orelse return false;
    if (output == 0 or process_impl_execution.guestMemoryConst(self, output, 16) == null) return false;
    process_impl_guest_memory.write32(self, output, value.packet_number);
    process_impl_guest_memory.write16(self, output + 4, value.buttons);
    process_impl_guest_memory.write8(self, output + 6, value.left_trigger);
    process_impl_guest_memory.write8(self, output + 7, value.right_trigger);
    process_impl_guest_memory.write16(self, output + 8, @bitCast(value.thumb_lx));
    process_impl_guest_memory.write16(self, output + 10, @bitCast(value.thumb_ly));
    process_impl_guest_memory.write16(self, output + 12, @bitCast(value.thumb_rx));
    process_impl_guest_memory.write16(self, output + 14, @bitCast(value.thumb_ry));
    self.windows_input_xinput_successes +|= 1;
    return true;
}

pub fn tryXeniaKeyboardInputShim(self: *ElfState, target: u64, next_rip: u64) bool {
    if (self.windows_input_hooks.read_controller_state == null) return false;
    const slot = self.guest_kernel_calls.exportAt(target) orelse return false;
    if (slot.kind != .trampoline) return false;
    const name = slot.export_name;
    const is_state = __process_std.mem.eql(u8, name, "XamInputGetState");
    const is_caps = __process_std.mem.eql(u8, name, "XamInputGetCapabilities");
    const is_caps_ex = __process_std.mem.eql(u8, name, "XamInputGetCapabilitiesEx");
    const is_set_state = __process_std.mem.eql(u8, name, "XamInputSetState");
    if (!is_state and !is_caps and !is_caps_ex and !is_set_state) return false;
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer {
        if (runtime_guard) |*guard| guard.unlock();
    }

    const context = process_impl_lifecycle.guestContextField(self, "regs").*.rcx;
    const membase = readHostU64(self, context + __process_PPC_CONTEXT_VIRTUAL_MEMBASE) orelse {
        self.windows_input_xam_refusals +|= 1;
        return false;
    };
    const user_index: u64 = if (is_caps_ex)
        readHostU64(self, context + __process_ppcContextGpr(4)) orelse {
            self.windows_input_xam_refusals +|= 1;
            return false;
        }
    else
        readHostU64(self, context + __process_ppcContextGpr(3)) orelse {
            self.windows_input_xam_refusals +|= 1;
            return false;
        };
    // The keyboard is one pad, in slot 0, as Xenia's own keyboard driver
    // places it (`keyboard_user_index` defaults to 0). Answering all four
    // slots told the title four identical controllers were plugged in and
    // pressing every button together. `XUSER_INDEX_ANY` resolves to slot 0.
    const keyboard_user = user_index == 0 or user_index == 0xFF;
    // Only the keyboard's own slot samples it, so the nonzero-sample
    // census counts what the title was actually handed.
    const state: __process_WindowsInputState = if (keyboard_user)
        readWindowsInputState(self) orelse return false
    else
        .{ .connected = 1 };
    const result: u32 = if (!keyboard_user) blk: {
        if (is_state) {
            // XInput clears the caller's state even for an empty slot.
            if (readHostU64(self, context + __process_ppcContextGpr(5))) |output| {
                if (output != 0) {
                    _ = process_impl_execution.fillGuestMemory(self, xeniaGuestVirtualAddress(membase, @truncate(output)), 16, 0);
                }
            }
        }
        break :blk 1167; // ERROR_DEVICE_NOT_CONNECTED
    } else if (is_set_state)
        0
    else if (is_state) blk: {
        const output = readHostU64(self, context + __process_ppcContextGpr(5)) orelse {
            self.windows_input_xam_refusals +|= 1;
            break :blk 87; // ERROR_INVALID_PARAMETER
        };
        if (output != 0) {
            if (xeniaGuestBytes(self, membase, @truncate(output), 16) == null) {
                self.windows_input_xam_refusals +|= 1;
                break :blk 87;
            }
            var bytes: [16]u8 = @splat(0);
            __process_std.mem.writeInt(u32, bytes[0..4], state.packet_number, .big);
            __process_std.mem.writeInt(u16, bytes[4..6], state.buttons, .big);
            bytes[6] = state.left_trigger;
            bytes[7] = state.right_trigger;
            __process_std.mem.writeInt(i16, bytes[8..10], state.thumb_lx, .big);
            __process_std.mem.writeInt(i16, bytes[10..12], state.thumb_ly, .big);
            __process_std.mem.writeInt(i16, bytes[12..14], state.thumb_rx, .big);
            __process_std.mem.writeInt(i16, bytes[14..16], state.thumb_ry, .big);
            if (!process_impl_execution.copyToGuest(self, xeniaGuestVirtualAddress(membase, @truncate(output)), &bytes)) {
                self.windows_input_xam_refusals +|= 1;
                break :blk 87;
            }
            if (state.thumb_lx != 0 or state.thumb_ly != 0) {
                self.windows_input_left_stick_deliveries +|= 1;
                self.windows_input_last_left_stick = .{ state.thumb_lx, state.thumb_ly };
                self.windows_input_last_left_stick_packet = state.packet_number;
            }
        }
        break :blk 0;
    } else blk: {
        const output_arg: u6 = if (is_caps_ex) 6 else 5;
        const output = readHostU64(self, context + __process_ppcContextGpr(output_arg)) orelse {
            self.windows_input_xam_refusals +|= 1;
            break :blk 87;
        };
        if (output == 0) break :blk 87;
        if (xeniaGuestBytes(self, membase, @truncate(output), 20) == null) {
            self.windows_input_xam_refusals +|= 1;
            break :blk 87;
        }
        var bytes: [20]u8 = @splat(0);
        bytes[0] = 1; // X_INPUT_CAPABILITIES_TYPE_GAMEPAD
        bytes[1] = 1; // X_INPUT_DEVSUBTYPE_GAMEPAD
        __process_std.mem.writeInt(u16, bytes[4..6], 0xffff, .big); // buttons
        bytes[6] = 0xff;
        bytes[7] = 0xff;
        __process_std.mem.writeInt(i16, bytes[8..10], __process_std.math.maxInt(i16), .big);
        __process_std.mem.writeInt(i16, bytes[10..12], __process_std.math.maxInt(i16), .big);
        __process_std.mem.writeInt(i16, bytes[12..14], __process_std.math.maxInt(i16), .big);
        __process_std.mem.writeInt(i16, bytes[14..16], __process_std.math.maxInt(i16), .big);
        _ = process_impl_execution.copyToGuest(self, xeniaGuestVirtualAddress(membase, @truncate(output)), &bytes);
        break :blk 0;
    };

    process_impl_guest_memory.write64(self, context + __process_ppcContextGpr(3), result);
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = result;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = next_rip;
    self.windows_input_xam_shims +|= 1;
    if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(self.windows_input_xam_shims)) {
        __process_log.info("PE64 INPUT BRIDGE: export={s} xam_shims={d} user_index={d} result={d} connected={} focused={} packet={d} buttons=0x{x} virtual_keyboard_pad=true user0_only=true; mapping=Space/Return:A Escape/C:B X:X Y:Y P:Start Backspace/Tab:Back arrows:dpad WASD:left-stick", .{
            name,
            self.windows_input_xam_shims,
            user_index,
            result,
            state.connected != 0,
            state.focused != 0,
            state.packet_number,
            state.buttons,
        });
    }
    return true;
}

pub fn captureGuestFileRequest(self: *ElfState, kernel_slot: u32) void {
    const context = process_impl_lifecycle.guestContextField(self, "regs").*.rcx;
    const request = activeGuestFileRequest(self);
    request.* = .{ .captured = true, .step = process_impl_lifecycle.observedExecutionSteps(self), .kernel_slot = kernel_slot, .context = context };
    self.guest_file_requests_captured +|= 1;
    captureGuestFileRequestFields(self, request, context) catch {
        request.unreadable = true;
        self.guest_file_requests_unreadable +|= 1;
    };
}

pub fn captureGuestFileRequestFields(self: *const ElfState, request: *__process_GuestFileRequest, context: u64) error{Unreadable}!void {
    const membase = readHostU64(self, context + __process_PPC_CONTEXT_VIRTUAL_MEMBASE) orelse return error.Unreadable;
    request.link_register = @truncate(readHostU64(self, context + __process_PPC_CONTEXT_LINK_REGISTER) orelse return error.Unreadable);
    request.desired_access = @truncate(readHostU64(self, context + __process_ppcContextGpr(4)) orelse return error.Unreadable);
    request.object_attributes = @truncate(readHostU64(self, context + __process_ppcContextGpr(5)) orelse return error.Unreadable);
    if (request.object_attributes == 0) return;
    const attributes = xeniaGuestBytes(self, membase, request.object_attributes, 12) orelse return error.Unreadable;
    request.depth = 1;
    request.root_directory = __process_std.mem.readInt(u32, attributes[0..4], .big);
    request.name_pointer = __process_std.mem.readInt(u32, attributes[4..8], .big);
    if (request.name_pointer == 0) return;
    const name = xeniaGuestBytes(self, membase, request.name_pointer, 8) orelse return error.Unreadable;
    request.depth = 2;
    request.name_length = __process_std.mem.readInt(u16, name[0..2], .big);
    request.name_maximum = __process_std.mem.readInt(u16, name[2..4], .big);
    request.name_buffer = __process_std.mem.readInt(u32, name[4..8], .big);
    if (request.name_buffer == 0) return;
    const buffer = xeniaGuestBytes(self, membase, request.name_buffer, __process_GUEST_FILE_REQUEST_PREVIEW_BYTES) orelse
        xeniaGuestBytes(self, membase, request.name_buffer, 1) orelse return error.Unreadable;
    request.depth = 3;
    var used: usize = 0;
    for (buffer) |byte| {
        if (byte == 0) break;
        request.preview[used] = if (byte >= 0x20 and byte < 0x7F and byte != '"') byte else '?';
        used += 1;
    }
    request.preview_len = @intCast(used);
}

pub fn classifyGuestFileRequestName(request: *const __process_GuestFileRequest) __process_GuestFileNameShape {
    if (!request.captured) return .unattributed;
    if (request.unreadable) return .unreadable;
    if (request.object_attributes == 0) return .no_object_attributes;
    if (request.name_pointer == 0) return .no_name;
    if (request.name_length == 0) return if (request.preview_len != 0) .zero_length_with_text else .zero_length_empty;
    // A non-zero length over bytes Rosette could not show still makes a
    // non-empty std::string in Xenia.
    if (request.preview_len == 0) return .named;
    for (request.previewText()[0..@min(request.preview_len, request.name_length)]) |byte| {
        if (!__process_std.ascii.isWhitespace(byte)) return .named;
    }
    return .blank_text;
}

pub fn faultGuestVfsEmptyName(self: *ElfState, resolve: *const __process_GuestVfsResolve) void {
    self.guest_vfs_empty_name_faults +|= 1;
    const occurrence = self.guest_vfs_empty_name_faults;
    if (occurrence == 1) self.windows_fatal_point_events +|= 1;
    if (comptime !@import("builtin").is_test) {
        if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) reportGuestVfsEmptyName(self, resolve, occurrence);
    }
    process_impl_guest_diagnostics.terminateForWindowsFatalPoint(self, "vfs-empty-object-name");
}

pub fn reportGuestVfsEmptyName(self: *ElfState, resolve: *const __process_GuestVfsResolve, occurrence: u64) void {
    const request = activeGuestFileRequest(self);
    const shape = classifyGuestFileRequestName(request);
    const kernel = self.guest_kernel_calls.slotAt(request.kernel_slot);
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const slot_plus_one: u8 = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| @intCast(@min(slot + 1, 255)) else 0;
    __process_log.err("PE64 FATAL POINT: guest-condition label=vfs-empty-object-name owner={s} occurrence={d} step={d} thread={s} resolve_caller={s} request={s}!{s} request_step={d} steps_since_request={d} title_lr=0x{x:0>8} desired_access=0x{x} object_attributes=0x{x:0>8} root_directory=0x{x} object_name=0x{x:0>8} length={d} maximum={d} buffer=0x{x:0>8} preview=\"{s}\" capture_depth={d} shape={s}; {s}", .{
        shape.owner(),
        occurrence,
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_guest_diagnostics.guestThreadLabel(self, slot_plus_one),
        describeGuestAddressOrUnnamed(self, resolve.caller_rip, &caller_text),
        if (kernel) |entry| entry.module.moduleName() else "<none>",
        if (kernel) |entry| entry.export_name else "<none>",
        request.step,
        process_impl_lifecycle.observedExecutionSteps(self) -| request.step,
        request.link_register,
        request.desired_access,
        request.object_attributes,
        request.root_directory,
        request.name_pointer,
        request.name_length,
        request.name_maximum,
        request.name_buffer,
        request.previewText(),
        request.depth,
        @tagName(shape),
        shape.meaning(),
    });
}

pub fn guestMilestoneHits(self: *const ElfState, index: usize) u64 {
    if (index >= self.guest_milestone_hits.len) return 0;
    return self.guest_milestone_hits[index];
}

pub fn guestMilestoneHitsNamed(self: *const ElfState, mangled: []const u8) u64 {
    const index = __process_xenia_guest_milestone_map.indexOf(mangled) orelse return 0;
    return self.guest_milestone_hits[index];
}

pub fn guestMilestoneAddresses(self: *const ElfState) []const u64 {
    return self.guest_milestone_addresses[0..];
}

pub fn noteGuestMilestoneCallSites(self: *ElfState, counts: []const u32) void {
    self.guest_milestone_call_sites_counted = true;
    for (counts, 0..) |sites, index| {
        if (index >= self.guest_milestone_call_sites.len) break;
        self.guest_milestone_call_sites[index] = sites;
    }
}

pub fn noteGuestMilestoneDataReferences(self: *ElfState, counts: []const u32) void {
    for (counts, 0..) |refs, index| {
        if (index >= self.guest_milestone_data_refs.len) break;
        self.guest_milestone_data_refs[index] = refs;
    }
}

pub fn guestMilestoneUnobservableReason(self: *const ElfState, mangled: []const u8) []const u8 {
    return switch (guestMilestoneReach(self, mangled)) {
        .unresolved => "this image does not name the symbol",
        .unreachable_inlined => "the symbol's body was inlined into its callers and nothing branches to the copy left behind, so it can never be entered",
        .uncounted => "the call-site census did not run on this route",
        .direct, .indirect => "observable",
    };
}

pub fn guestMilestoneReach(self: *const ElfState, mangled: []const u8) __state_MilestoneReach {
    const index = __process_xenia_guest_milestone_map.indexOf(mangled) orelse return .unresolved;
    if (self.guest_milestone_addresses[index] == 0) return .unresolved;
    if (!self.guest_milestone_call_sites_counted) return .uncounted;
    if (self.guest_milestone_call_sites[index] != 0) return .direct;
    if (self.guest_milestone_data_refs[index] != 0) return .indirect;
    // Entered at least once settles it whatever the scans found: the
    // guest reached an address the image analysis called unreachable, so
    // the analysis is what is wrong.
    if (self.guest_milestone_hits[index] != 0) return .indirect;
    return .unreachable_inlined;
}

pub fn guestMilestoneInlinedAway(self: *const ElfState, mangled: []const u8) bool {
    return guestMilestoneReach(self, mangled) == .unreachable_inlined;
}

pub fn guestMilestoneStageHits(self: *const ElfState, mangled: []const u8) u64 {
    const own = guestMilestoneHitsNamed(self, mangled);
    const proxy = __process_xenia_guest_milestone_map.inlineProxyOf(mangled);
    if (proxy.len == 0) return own;
    return @max(own, guestMilestoneHitsNamed(self, proxy));
}

pub fn guestMilestoneStageObservable(self: *const ElfState, mangled: []const u8) bool {
    const proxy = __process_xenia_guest_milestone_map.inlineProxyOf(mangled);
    if (proxy.len != 0 and guestMilestoneArmed(self, proxy) and !guestMilestoneInlinedAway(self, proxy)) return true;
    return guestMilestoneArmed(self, mangled) and !guestMilestoneInlinedAway(self, mangled);
}

pub fn guestMilestoneArmed(self: *const ElfState, mangled: []const u8) bool {
    const index = __process_xenia_guest_milestone_map.indexOf(mangled) orelse return false;
    return self.guest_milestone_addresses[index] != 0;
}

pub fn guestSymbolAt(self: *const ElfState, address: u64, buffer: []u8) ?__process_GuestSymbol {
    const resolver = self.guest_symbol_resolver orelse return null;
    return resolver.resolve(resolver.context, address, buffer);
}

pub fn tryXeniaMissingNativeMutantRelease(self: *ElfState, d: __process_DecodedInsn, next_rip: u64) bool {
    if (!self.windows_runtime_enabled or d.op != .call_mem64 or d.len != 3 or
        !d.sib_has_base or d.sib_base_reg != .al_ax_eax_rax or d.sib_has_index or d.rip_relative)
    {
        return false;
    }
    const regs = process_impl_lifecycle.guestContextField(self, "regs");
    const base_value = process_impl_execution.regVal(self, .al_ax_eax_rax, .bits64);
    if (base_value != 0 or d.addr != 0x18) return false;

    var symbol_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    const symbol = guestSymbolAt(self, regs.rip, &symbol_storage) orelse return false;
    var instruction_storage: [16]u8 = undefined;
    const instruction = process_impl_instruction_decode.guestInstructionBytes(self, regs.rip, &instruction_storage);
    if (!__process_xmutant_release_compat.shouldReturnNotOwned(
        symbol.name,
        symbol.offset,
        instruction,
        d.addr,
        true,
        base_value,
    )) return false;

    // A real call followed by RET leaves RSP unchanged. The next guest
    // instructions inspect AL and select X_STATUS_MUTANT_NOT_OWNED.
    regs.rax = 0;
    regs.rip = next_rip;
    const occurrence = self.windows_xmutant_release_compat_calls.fetchAdd(1, .monotonic) + 1;
    if (occurrence == 1) {
        __process_log.warn("PE64 XENIA COMPAT: XMutant::ReleaseMutant has no native backing object at its exact null virtual call; returned false so the guest code produces X_STATUS_MUTANT_NOT_OWNED (this=0x{x}, call_rip=0x{x}, return_rip=0x{x}, offset=0x{x}, opcode={any}, occurrence={d})", .{
            regs.rsi,
            regs.rip -| d.len,
            next_rip,
            symbol.offset,
            instruction[0..d.len],
            occurrence,
        });
    }
    return true;
}

pub fn tryXeniaStaleMutantBackingDelete(self: *ElfState, d: __process_DecodedInsn, next_rip: u64) bool {
    if (!self.windows_runtime_enabled or d.op != .call_mem64 or d.len != 3) return false;

    const regs = process_impl_lifecycle.guestContextField(self, "regs");
    var caller_name_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    const caller = guestSymbolAt(self, regs.rip, &caller_name_storage) orelse return false;
    var instruction_storage: [16]u8 = undefined;
    const instruction = process_impl_instruction_decode.guestInstructionBytes(self, regs.rip, &instruction_storage);
    var continuation_storage: [16]u8 = undefined;
    const continuation_instruction = process_impl_instruction_decode.guestInstructionBytes(self, next_rip, &continuation_storage);
    if (!__process_xmutant_teardown_compat.matchesDestructorCallsite(
        caller.name,
        caller.offset,
        instruction,
        continuation_instruction,
    )) return false;

    // Heap releases and exact-size block reuse use this same lock. Hold
    // it from the provenance lookup until RIP has advanced, so an
    // inactive record cannot be reused between our check and recovery.
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();

    const owner = regs.rsi;
    const backing = regs.rcx;
    const loaded_vtable = regs.rax;
    if (owner == 0 or backing == 0 or loaded_vtable == 0) return false;
    if (process_impl_guest_memory.read64(self, owner +| __process_xmutant_teardown_compat.backing_member_offset) != backing) return false;
    if (process_impl_guest_memory.read64(self, backing) != loaded_vtable) return false;

    const target = process_impl_guest_memory.read64(self, loaded_vtable +| 8);
    if (target == 0) return false;
    var target_name_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    const target_symbol = guestSymbolAt(self, target, &target_name_storage) orelse return false;
    var target_instruction_storage: [16]u8 = undefined;
    const target_instruction = process_impl_instruction_decode.guestInstructionBytes(self, target, &target_instruction_storage);

    var free_site_name_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    const allocation_index = process_impl_guest_heap.findGuestHeapAllocation(self, backing) orelse return false;
    const allocation = self.windows_heap_allocations[allocation_index];
    const prior_free_symbol = if (allocation.free_return != 0)
        guestSymbolAt(self, allocation.free_return, &free_site_name_storage)
    else
        null;
    const prior_free_name = if (prior_free_symbol) |symbol| symbol.name else "";
    const prior_free_offset = if (prior_free_symbol) |symbol| symbol.offset else 0;
    const backing_handle_is_null = process_impl_guest_memory.read64(self, backing +| 8) == 0;
    const allocation_guard_intact = if (process_impl_guest_heap.guestHeapGuardSlice(self, allocation)) |guard|
        allocation.guard_bytes != 0 and __process_heap_guard.check(guard) == null
    else
        false;

    const evidence = __process_xmutant_teardown_compat.Evidence{
        .callsite_symbol = caller.name,
        .callsite_offset = caller.offset,
        .call_instruction = instruction,
        .continuation_instruction = continuation_instruction,
        .owner_member_matches_backing = true,
        .object_vtable_matches_loaded_vtable = true,
        .target_symbol = target_symbol.name,
        .target_offset = target_symbol.offset,
        .target_instruction = target_instruction,
        .vtable_slot_matches_target = process_impl_guest_memory.read64(self, loaded_vtable +| 8) == target,
        .allocation_active = allocation.active,
        .allocation_length = allocation.length,
        .backing_handle_is_null = backing_handle_is_null,
        .allocation_guard_intact = allocation_guard_intact,
        .prior_free_symbol = prior_free_name,
        .prior_free_offset = prior_free_offset,
    };
    if (!__process_xmutant_teardown_compat.shouldSkipRepeatedBackingDelete(evidence)) return false;

    regs.rip = next_rip;
    if (runtime_guard) |*guard| {
        guard.unlock();
        runtime_guard = null;
    }

    // Copy allocation provenance before resuming guest execution. Heap
    // records are address ordered and retain freed tombstones. The lock
    // is released only after the decision and instruction advancement.
    const occurrence = self.windows_xmutant_stale_backing_deletes_skipped.fetchAdd(1, .monotonic) + 1;
    if (occurrence <= 8) {
        var allocation_site_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
        var prior_free_site_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
        var vtable_site_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
        const allocation_site = if (allocation.allocation_return != 0)
            describeGuestAddressOrUnnamed(self, allocation.allocation_return, &allocation_site_storage)
        else
            "<unknown>";
        const prior_free_site = if (allocation.free_return != 0)
            describeGuestAddressOrUnnamed(self, allocation.free_return, &prior_free_site_storage)
        else
            "<unknown>";
        const vtable_site = describeGuestAddressOrUnnamed(self, loaded_vtable, &vtable_site_storage);
        const lifetime_state = if (allocation.active) "base-destructor-in-progress" else "already-freed-by-XMutant-dtor";
        __process_log.warn("PE64 XENIA MUTANT LIFETIME: skipped duplicate deleting-destructor dispatch occurrence={d} state={s} owner=0x{x} backing=0x{x} allocation_bytes={d} allocation_active={} handle_is_null={} guard_intact={} allocated_by=0x{x} ({s}) allocation_step={d} prior_free=0x{x} ({s}) free_import={s} free_step={d} free_thread={s} vtable=0x{x} ({s}) deleting_dtor=0x{x} ({s}) call_rip=0x{x} return_rip=0x{x}; exact XMutant member and continuation verified; the intentional abstract-base UD2 was not executed", .{
            occurrence,
            lifetime_state,
            owner,
            backing,
            allocation.length,
            allocation.active,
            backing_handle_is_null,
            allocation_guard_intact,
            allocation.allocation_return,
            allocation_site,
            allocation.allocation_step,
            allocation.free_return,
            prior_free_site,
            if (allocation.free_import.len == 0) "<none>" else allocation.free_import,
            allocation.free_step,
            process_impl_guest_diagnostics.guestThreadLabel(self, allocation.free_thread_slot),
            loaded_vtable,
            vtable_site,
            target,
            describeGuestAddressOrUnnamed(self, target, &target_name_storage),
            regs.rip,
            next_rip,
        });
    }
    return true;
}

pub fn describeGuestAddress(self: *const ElfState, address: u64, buffer: []u8) []const u8 {
    var name_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    if (guestSymbolAt(self, address, &name_storage)) |symbol| {
        return __process_std.fmt.bufPrint(buffer, "{s}+0x{x}", .{ symbol.name, symbol.offset }) catch symbol.name[0..@min(symbol.name.len, buffer.len)];
    }
    // No symbol is not no answer. An address outside the image is still
    // somewhere: a thunk Rosette laid down, a block the guest allocated
    // executable, its heap, a stack. Saying which turns a bare hex number
    // into a fact about who owns the code running there.
    return self.guest_regions.describe(address, buffer);
}

pub fn describeGuestAddressOrUnnamed(self: *const ElfState, address: u64, buffer: []u8) []const u8 {
    const described = describeGuestAddress(self, address, buffer);
    // `<unmapped>` and `<unnamed>` are different findings. The first says
    // the address belongs to nothing Rosette has recorded, which for a
    // rip is a control-flow escape; the second used to be printed for
    // both, and hid the distinction.
    return if (described.len == 0) "<unmapped>" else described;
}

pub fn classifyGuestFrontier(self: *const ElfState, address: u64) __process_xenia_guest_frontier_map.Classification {
    var name_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    const symbol = guestSymbolAt(self, address, &name_storage) orelse
        return __process_xenia_guest_frontier_map.classify("");
    return __process_xenia_guest_frontier_map.classify(symbol.name);
}

pub fn guestFrontierIsBoundedComputation(self: *const ElfState) bool {
    return classifyGuestFrontier(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip).isBoundedComputation();
}

pub fn sampleGuestFrontier(self: *ElfState) void {
    const classification = classifyGuestFrontier(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip);
    self.guest_frontier_samples +|= 1;
    self.guest_frontier_workload_samples[@intFromEnum(classification.workload)] +|= 1;
}

pub fn frontierSamplesFor(self: *const ElfState, workload: __process_xenia_guest_frontier_map.Workload) u64 {
    return self.guest_frontier_workload_samples[@intFromEnum(workload)];
}

pub fn fontAtlasFrontierSamples(self: *const ElfState) u64 {
    return frontierSamplesFor(self, .font_rasterization) +|
        frontierSamplesFor(self, .font_atlas_packing) +|
        frontierSamplesFor(self, .font_atlas_build);
}

pub fn describeGuestFrontier(self: *const ElfState, address: u64, buffer: []u8) []const u8 {
    var symbol_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    const symbol = describeGuestAddressOrUnnamed(self, address, &symbol_storage);
    const classification = classifyGuestFrontier(self, address);
    return __process_std.fmt.bufPrint(buffer, "symbol={s} workload={s} owner={s} bounded={}", .{
        symbol,
        classification.workload.label(),
        classification.owner.label(),
        classification.isBoundedComputation(),
    }) catch symbol[0..@min(symbol.len, buffer.len)];
}

pub fn notePresentChainFailurePoint(self: *ElfState, steps: u64) void {
    const graphics = &self.windows_graphics;
    if (!graphics.swapchain_ready) {
        self.windows_present_no_work_checkpoints = 0;
        self.windows_present_no_submit_checkpoints = 0;
        return;
    }

    const guest_frame_never_started = graphics.image_acquires == 0 and
        graphics.command_calls == 0 and graphics.queue_submits == 0 and graphics.presents == 0;
    // A frontier inside a computation that terminates is a horizon, not a
    // stall. Counting a checkpoint there would eventually accuse the
    // presentation chain for a font atlas, a shader translation, or a XEX
    // decryption that was going to finish - which is what the 2026-09-11
    // run's `guest_never_reached_first_frame_frontier` verdict did while
    // the UI thread was rasterizing glyphs. The checkpoint is held rather
    // than reset: if the guest leaves the bounded work and still produces
    // nothing, the accusation resumes from where it was.
    const frontier = classifyGuestFrontier(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip);
    if (guest_frame_never_started and !frontier.isBoundedComputation()) {
        self.windows_present_no_work_checkpoints +|= 1;
    } else if (!guest_frame_never_started) {
        self.windows_present_no_work_checkpoints = 0;
    } else if (!self.windows_present_bounded_work_reported) {
        self.windows_present_bounded_work_reported = true;
        __process_log.info("PE64 present chain deferred: the guest frontier is inside {s} ({s}), which finishes on its own; no-presents cannot be a verdict until it does. steps={d} rip=0x{x} owner={s}", .{
            frontier.workload.label(),
            frontier.matched,
            steps,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            frontier.owner.label(),
        });
    }
    if (graphics.queue_submits != 0 and graphics.presents == 0) {
        self.windows_present_no_submit_checkpoints +|= 1;
    } else {
        self.windows_present_no_submit_checkpoints = 0;
    }

    if (self.windows_present_no_work_checkpoints >= 3 and !self.windows_present_no_work_reported) {
        self.windows_present_no_work_reported = true;
        self.windows_fatal_point_events +|= 1;
        var frontier_text: [320]u8 = undefined;
        __process_log.err("PE64 FATAL POINT: present-chain-no-presents verdict=no_presents stage={s} checkpoints={d} steps={d} rip=0x{x} {s} last_op={s} active_thread=0x{x} vk_calls={d} native_vk_calls={d} swapchain_ready={} acquires={d} command_calls={d} submits={d} presents={d} last_call={s} last_failure={s} diagnosis=guest_never_reached_first_frame_frontier", .{
            @tagName(graphics.phase),
            self.windows_present_no_work_checkpoints,
            steps,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            describeGuestFrontier(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &frontier_text),
            @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            graphics.vulkan_calls,
            graphics.native_vulkan_calls,
            graphics.swapchain_ready,
            graphics.image_acquires,
            graphics.command_calls,
            graphics.queue_submits,
            graphics.presents,
            __process_std.mem.sliceTo(&graphics.last_call, 0),
            __process_std.mem.sliceTo(&graphics.last_failure, 0),
        });
        process_impl_guest_diagnostics.terminateForWindowsFatalPoint(self, "present-chain-no-presents");
    }
    if (self.windows_present_no_submit_checkpoints >= 3 and !self.windows_present_no_submit_reported) {
        self.windows_present_no_submit_reported = true;
        self.windows_fatal_point_events +|= 1;
        __process_log.err("PE64 FATAL POINT: present-chain-no-present-after-submit verdict=no_presents stage={s} checkpoints={d} steps={d} rip=0x{x} last_op={s} active_thread=0x{x} acquires={d} command_calls={d} submits={d} presents={d} last_call={s} last_failure={s} diagnosis=guest_submitted_work_but_no_present_returned", .{
            @tagName(graphics.phase),
            self.windows_present_no_submit_checkpoints,
            steps,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            graphics.image_acquires,
            graphics.command_calls,
            graphics.queue_submits,
            graphics.presents,
            __process_std.mem.sliceTo(&graphics.last_call, 0),
            __process_std.mem.sliceTo(&graphics.last_failure, 0),
        });
        process_impl_guest_diagnostics.terminateForWindowsFatalPoint(self, "present-chain-no-present-after-submit");
    }
}

pub fn reportPresentChainCheckpoint(self: *ElfState) void {
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer {
        if (runtime_guard) |*guard| guard.unlock();
    }
    // VdSwap and ring decoding are separate guest edges. If the swap was
    // observed but its front-buffer packet became readable later, give the
    // host presenter one bounded retry before declaring the output mailbox
    // empty again.
    if (self.guest_kernel_calls.hitsFor("VdSwap") != 0) {
        _ = process_impl_guest_diagnostics.offerGuestFrontBufferToNativePresenter(self);
    }
    const progress_callback = self.windows_graphics.hooks.update_present_diagnostics;
    if (progress_callback) |callback| {
        // The forwarder's `guest_progress` line is the first thing a
        // reader looks at in a no-presents block, and an opcode name is
        // not enough to tell an expensive computation from a stall. Carry
        // the frontier's symbol and workload across the same seam rather
        // than widening the C-ABI hook.
        var composed: [256]u8 = undefined;
        var frontier_text: [192]u8 = undefined;
        const opcode = @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*);
        const operation = __process_std.fmt.bufPrint(&composed, "{s} in {s}", .{
            opcode,
            describeGuestFrontier(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &frontier_text),
        }) catch opcode;
        callback(
            self.windows_graphics.hooks.native_context,
            process_impl_lifecycle.observedExecutionSteps(self),
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            operation.ptr,
            operation.len,
            @intFromBool(classifyGuestFrontier(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip).isBoundedComputation()),
        );
    }
    notePresentChainFailurePoint(self, process_impl_lifecycle.observedExecutionSteps(self));
    if (self.windows_graphics.hooks.report_present_chain) |callback| {
        callback(self.windows_graphics.hooks.native_context);
    }
}

pub fn reportPresentChainFinal(self: *ElfState) void {
    if (!self.windows_runtime_enabled or self.windows_present_chain_final_reported) return;
    self.windows_present_chain_final_reported = true;
    if (self.windows_graphics.hooks.report_present_chain_full) |callback| {
        callback(self.windows_graphics.hooks.native_context);
    } else if (self.windows_graphics.hooks.report_present_chain) |callback| {
        callback(self.windows_graphics.hooks.native_context);
    }
}

pub fn windowsScreenValiditySnapshot(self: *const ElfState) __process_screen_validity.Snapshot {
    const graphics = &self.windows_graphics;
    const guest_presents = if (graphics.guest_present_observed) graphics.presents else 0;
    return .{
        .step = process_impl_run_reporting.totalInterpretedSteps(self),
        .guest_presents = guest_presents,
        .guest_acquires = graphics.image_acquires,
        .presents_with_target = graphics.guest_presents_with_target,
        .presents_with_content = graphics.guest_presents_with_content,
        .presents_clear_only = graphics.guest_presents_clear_only,
        .presents_without_target = graphics.guest_presents_without_target,
        .presents_without_write = graphics.guest_presents_without_write,
        .content_commands = graphics.guest_presents_with_content,
        .draw_commands = graphics.draw_commands,
        .dispatch_commands = graphics.dispatch_commands,
        .native_present_requests = if (graphics.native_vulkan_forwarding)
            graphics.native_present_requests_observed
        else
            graphics.native_diagnostic_attempts,
        .native_present_completions = if (graphics.native_vulkan_forwarding)
            graphics.native_present_completions_observed
        else
            graphics.native_diagnostic_frames,
        .native_queue_submits = if (graphics.native_vulkan_forwarding)
            graphics.native_queue_submits_observed
        else
            0,
        .expected_width = graphics.window_width,
        .expected_height = graphics.window_height,
        // The ELF state owns the logical extent, but it does not own a
        // private AppKit drawable readback. Keep this unknown rather than
        // promoting the requested window size into pixel evidence.
        .extent_observed = false,
        .drawable_owner = if (graphics.native_vulkan_forwarding and graphics.swapchain_ready)
            .guest_swapchain
        else if (graphics.native_presenter_ready)
            .native_presenter
        else
            .unknown,
        .pixel_probe_attempts = 0,
        .pixel_probe_successes = 0,
        .pixel_evidence = .unavailable,
        .window_available = graphics.native_window_ready,
        .window_chain_intact = graphics.native_window_ready and
            (graphics.native_vulkan_forwarding or graphics.native_presenter_ready),
        .window_user_visible = graphics.native_window_visible,
        .window_visible_fraction_percent = if (graphics.native_window_visible) 100 else 0,
    };
}

pub fn reportWindowsScreenValidity(self: *ElfState) void {
    const snapshot = windowsScreenValiditySnapshot(self);
    const evaluation = self.windows_screen_validity.observe(snapshot);
    const first_blocking = if (evaluation.first_blocking) |stage| stage.label() else "none";
    const content_class = if (snapshot.presents_with_content != 0)
        "guest_content_reached_acquired_image"
    else if (snapshot.presents_clear_only != 0)
        "clear_or_uniform_only"
    else if (self.windows_graphics.content_commands != 0)
        "commands_observed_but_not_presented_content"
    else
        "no_content_or_fill_commands";
    __process_log.info("PE64 SCREEN VALIDITY: verdict={s} first_blocking={s} screen_stage={s} content_class={s} guest_presents={d} acquires={d} presented_content={d} bridge_commands={d} fill_commands={d} native_forwarding={} native_present(requests/completions/queue_submits)={d}/{d}/{d} pixel_evidence={s} pixel_probe_successes={d} window_visible={} visible_fraction={d}% observations={d}; valid_on_screen is fail-closed until detailed pixel evidence and source provenance are observed", .{
        evaluation.verdict.label(),
        first_blocking,
        evaluation.record(.screen_valid).status.label(),
        content_class,
        snapshot.guest_presents,
        snapshot.guest_acquires,
        snapshot.content_commands,
        self.windows_graphics.content_commands,
        self.windows_graphics.fill_commands,
        self.windows_graphics.native_vulkan_forwarding,
        snapshot.native_present_requests,
        snapshot.native_present_completions,
        snapshot.native_queue_submits,
        snapshot.pixel_evidence.label(),
        snapshot.pixel_probe_successes,
        snapshot.window_user_visible,
        snapshot.window_visible_fraction_percent,
        self.windows_screen_validity.observations,
    });
    if (evaluation.first_blocking) |stage| {
        __process_log.info("PE64 SCREEN VALIDITY:   action={s} evidence={s} owner={s}; transport and content provenance remain separate contracts", .{
            evaluation.action(),
            evaluation.record(stage).evidence,
            evaluation.record(stage).owner.label(),
        });
    }
}

pub fn reportWindowsInputBridge(self: *const ElfState) void {
    const installed = self.windows_input_hooks.read_controller_state != null;
    __process_log.info("PE64 INPUT BRIDGE: installed={} contract_version={d} polls={d} bridged={d} invalid_or_disconnected={d} xinput_successes={d} xam_shims={d} xam_refusals={d} last_packet={d} last_buttons=0x{x} last_focused={} key_events(down/up)={d}/{d} snapshots={d} nonzero_samples={d} focused_zero_samples={d} focus_gains={d} focus_losses={d} rejected_key_events={d} last_key_code={d} mapping=Space/Return:A Escape/C:B X:X Y:Y P:Start Backspace/Tab:Back Home:Guide WASD:left-stick IJKL:right-stick arrows:dpad Q:LB R:RB Z:LT E:RT F:left-thumb V:right-thumb; keyboard state is zero when unfocused, physical gamepad remains active; compare key transitions, focus and host-gamepad diagnostics to guest polling", .{
        installed,
        self.windows_input_contract_version,
        self.windows_input_polls,
        self.windows_input_bridged_polls,
        self.windows_input_invalid_polls,
        self.windows_input_xinput_successes,
        self.windows_input_xam_shims,
        self.windows_input_xam_refusals,
        self.windows_input_last_packet,
        self.windows_input_last_buttons,
        self.windows_input_last_focused,
        self.windows_input_key_down_events,
        self.windows_input_key_up_events,
        self.windows_input_snapshot_reads,
        self.windows_input_nonzero_samples,
        self.windows_input_focused_zero_samples,
        self.windows_input_focus_gains,
        self.windows_input_focus_losses,
        self.windows_input_rejected_events,
        self.windows_input_last_key_code,
    });
    const physical_name = __process_std.mem.sliceTo(&self.windows_input_physical_name, 0);
    __process_log.info("PE64 HOST GAME CONTROLLER: connected={} name='{s}' value_events={d} user_index=0; state is sampled from GameController callbacks without a per-poll AppKit hop", .{
        self.windows_input_physical_connected,
        physical_name,
        self.windows_input_physical_events,
    });
    __process_log.info("PE64 MOVEMENT INPUT: nonzero_left_stick_deliveries={d} last_xy={d}/{d} last_packet={d}; counted only after XamInputGetState wrote slot 0's big-endian stick axes into the title's output buffer", .{
        self.windows_input_left_stick_deliveries,
        self.windows_input_last_left_stick[0],
        self.windows_input_last_left_stick[1],
        self.windows_input_last_left_stick_packet,
    });
}

pub fn noteWindowsFileFailure(self: *ElfState, error_code: u32) void {
    noteWindowsFileFailureDetail(self, error_code, "", 0);
}

pub fn noteWindowsFileFailureDetail(self: *ElfState, error_code: u32, subject: []const u8, caller: u64) void {
    const api = if (process_impl_lifecycle.guestContextField(self, "windows_current_import").*.len == 0) "<unattributed>" else process_impl_lifecycle.guestContextField(self, "windows_current_import").*;
    self.windows_file_failure_ledger.note(api, error_code, subject, caller);
}

pub fn reportWindowsFileFailures(self: *const ElfState) void {
    const ledger = &self.windows_file_failure_ledger;
    if (ledger.isEmpty()) return;
    var actionable_entries: usize = 0;
    var actionable_calls: u64 = 0;
    for (ledger.entries[0..ledger.count]) |*entry| {
        if (entry.class.expected()) continue;
        actionable_entries += 1;
        actionable_calls +|= entry.count;
    }
    if (actionable_entries == 0) {
        __process_log.info("WINDOWS FILE FAILURES: distinct={d} calls={d}, every one an expected answer (a pipe with no server, an enumeration's end or an optional-file probe); none is a path Rosette could not serve", .{ ledger.count, ledger.total });
    } else {
        __process_log.warn("WINDOWS FILE FAILURES: distinct={d} calls={d} actionable={d} in {d} call(s); a large not-found count against a lookup API is a guest probing for optional files, while a failure on an open or a write is a path Rosetta could not serve", .{ ledger.count, ledger.total, actionable_entries, actionable_calls });
    }
    for (ledger.entries[0..ledger.count]) |*entry| {
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        const caller = if (entry.first_caller == 0) "<not recorded>" else describeGuestAddressOrUnnamed(self, entry.first_caller, &caller_text);
        const subject = if (entry.subject_length == 0) "<none>" else entry.subject();
        if (entry.class.expected()) {
            __process_log.info("WINDOWS FILE FAILURE:   {s} x{d} error={d} ({s}) class={s} first_subject='{s}' first_caller={s}; {s}", .{ entry.name(), entry.count, entry.error_code, __process_windowsFileErrorLabel(entry.error_code), @tagName(entry.class), subject, caller, entry.class.meaning() });
        } else {
            __process_log.warn("WINDOWS FILE FAILURE:   {s} x{d} error={d} ({s}) class={s} first_subject='{s}' first_caller={s}; {s}", .{ entry.name(), entry.count, entry.error_code, __process_windowsFileErrorLabel(entry.error_code), @tagName(entry.class), subject, caller, entry.class.meaning() });
        }
    }
    if (ledger.overflow != 0) {
        __process_log.warn("WINDOWS FILE FAILURES:   {d} further failures did not fit the bounded ledger", .{ledger.overflow});
    }
}

pub fn noteWindowsImportFallback(
    self: *ElfState,
    dll_name: []const u8,
    name: []const u8,
    fallback: __process_x64_linux_runtime.ImportFallback,
) void {
    _ = self.windows_import_fallbacks.note(
        dll_name,
        name,
        fallback,
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
        process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
        process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
    );
}

pub fn noteWindowsImportAnswer(
    self: *ElfState,
    dll_name: []const u8,
    name: []const u8,
    value: u64,
    last_error_before: u32,
) void {
    noteWindowsThreadImport(self, name);
    // What this name's own package declared, or - for a library nobody
    // has written down - what the spelling suggests. The first can be
    // used to accuse someone; the second cannot.
    const judgement = self.windows_import_answer_cache.judge(dll_name, name);
    if (judgement.declared) self.windows_import_answers_declared +|= 1;
    const convention = judgement.convention;
    if (!judgement.valueIsRefusal(value)) {
        if (judgement.decisive) {
            self.windows_import_answers_classified +|= 1;
        } else {
            self.windows_import_answers_unjudged +|= 1;
        }
        return;
    }
    // A failing value under a judgement that can be trusted is a refusal
    // outright.
    if (judgement.decisive) {
        self.windows_import_answers_classified +|= 1;
        recordWindowsImportRefusal(self, &self.windows_import_refusals, dll_name, name, convention, value);
        self.windows_import_refusal_events +|= 1;
        return;
    }
    // Under an inferred convention a zero cannot be read from the value
    // alone - `WAIT_OBJECT_0` and `VK_SUCCESS` are both zero and both
    // success. Windows' own rule breaks the tie: a BOOL that fails sets
    // `GetLastError`. A call that set one during this dispatch meant the
    // zero; a call that set nothing is either an ordinary negative answer
    // or a handler refusing silently, and those go on the audit list.
    self.windows_import_answers_unjudged +|= 1;
    if (process_impl_lifecycle.guestContextField(self, "windows_last_error").* != last_error_before and process_impl_lifecycle.guestContextField(self, "windows_last_error").* != 0) {
        self.windows_import_refusal_events +|= 1;
        recordWindowsImportRefusal(self, &self.windows_import_refusals, dll_name, name, convention, value);
        return;
    }
    self.windows_import_unexplained_events +|= 1;
    recordWindowsImportRefusal(self, &self.windows_import_unexplained_zeros, dll_name, name, convention, value);
}

pub fn noteWindowsThreadImport(self: *ElfState, name: []const u8) void {
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse return;
    const thread = &self.windows_guest_threads[slot];
    thread.import_calls +|= 1;
    thread.last_import_step = process_impl_run_reporting.totalInterpretedSteps(self);
    const length = @min(name.len, __process_WINDOWS_GUEST_THREAD_NAME_BYTES);
    @memcpy(thread.last_import[0..length], name[0..length]);
    thread.last_import_len = @intCast(length);
}

pub fn recordWindowsImportRefusal(
    self: *ElfState,
    ledger: *__process_x64_linux_runtime.ImportFallbackLedger,
    dll_name: []const u8,
    name: []const u8,
    convention: __process_x64_linux_runtime.ImportReturnConvention,
    value: u64,
) void {
    _ = ledger.note(
        dll_name,
        name,
        .{
            .convention = convention,
            .outcome = .refused,
            .value = value,
            .last_error = null,
            .hazard = false,
        },
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
        process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
        process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
    );
}

pub fn reportWindowsImportRefusals(self: *const ElfState) void {
    const ledger = &self.windows_import_refusals;
    if (self.windows_import_answers_classified == 0) return;
    if (ledger.isEmpty()) {
        __process_log.info(
            "PE64 IMPORT REFUSALS: none; {d} answer(s) were judged against an explicit ABI rule and every one read as success ({d} further answer(s) use a convention the contract infers from the name, where zero is success as often as it is failure, and are not judged)",
            .{ self.windows_import_answers_classified, self.windows_import_answers_unjudged },
        );
        return;
    }
    __process_log.warn(
        "PE64 IMPORT REFUSALS: {d} name(s) in {d} call(s) of {d} judged answer(s), {d} of which had a declared ABI; every value Rosette returned that the guest's own ABI reads as failure, whichever handler produced it. A guest error message is explained by the row whose caller and step match it. {d} answer(s) are not judged: no package declares them and their convention is only inferred from the name, where a zero is success as often as failure",
        .{ ledger.count, self.windows_import_refusal_events, self.windows_import_answers_classified, self.windows_import_answers_declared, self.windows_import_answers_unjudged },
    );

    var order: [__process_x64_linux_runtime.ImportFallbackLedger.capacity]usize = undefined;
    const ranked = ledger.rankedInto(&order);
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    // Two passes so the refusals the guest branches on are read first.
    for ([_]bool{ true, false }) |hard_pass| {
        for (order[0..ranked]) |index| {
            const entry = &ledger.entries[index];
            if (!entry.used) continue;
            if (__process_x64_linux_runtime.importRefusalIsHard(entry.convention) != hard_pass) continue;
            __process_log.warn(
                "PE64 IMPORT REFUSAL:   {s} {s}!{s} [{s}] x{d} returned=0x{x} convention={s} first_step={d} first_caller={s} first_args=0x{x},0x{x}; {s}",
                .{
                    if (hard_pass) "hard  " else "soft  ",
                    entry.dll(),
                    entry.name(),
                    entry.subsystem.label(),
                    entry.calls,
                    entry.value,
                    @tagName(entry.convention),
                    entry.first_step,
                    describeGuestAddressOrUnnamed(self, entry.first_caller_rip, &caller_text),
                    entry.first_arg0,
                    entry.first_arg1,
                    if (windowsImportIsUnimplemented(self, entry.dll(), entry.name()))
                        "Rosette does not implement this name; the value is its ABI contract's refusal"
                    else
                        "a handler answered this deliberately; the value is what that handler decided, not a gap",
                },
            );
        }
    }
    if (ledger.overflow_names != 0) {
        __process_log.warn("PE64 IMPORT REFUSALS:   {d} further name(s) in {d} call(s) did not fit the bounded ledger", .{ ledger.overflow_names, ledger.overflow_calls });
    }
    __process_log.warn(
        "PE64 IMPORT REFUSALS:   a hard refusal is one the guest branches on (HRESULT/NTSTATUS/LSTATUS/WSA); a soft one is a FALSE or a NULL, which for a probe is the expected answer. Read the hard rows against the guest's own error lines before treating any of them as a defect",
        .{},
    );
    reportCapabilityGaps(self);
}

pub fn reportWindowsCrtState(self: *const ElfState) void {
    const globals = &self.windows_crt_globals;
    __process_log.info("PE64 CRT STATE: module_path_a=0x{x} module_path_w=0x{x} owner_errno=0x{x} normal_callbacks_remaining={d} quick_callbacks_remaining={d} thread_local_callback=0x{x} exit_mode={s} exit_running={} termination_complete={} registered={d} invoked={d} rejected={d} capability_gap_events={d} capability_gap_policy={s}", .{
        globals.module_path_a,
        globals.module_path_w,
        globals.owner_errno_storage,
        globals.normal_count,
        globals.quick_count,
        globals.thread_local_callback,
        @tagName(globals.exit_mode),
        globals.exit_running,
        globals.termination_complete,
        globals.callback_registrations,
        globals.callback_invocations,
        globals.callback_rejections,
        self.windows_capability_gap_events,
        if (self.windows_capability_gaps_fatal) "fatal" else "continue",
    });
}

pub fn reportCapabilityGaps(self: *const ElfState) void {
    const ledger = &self.windows_import_fallbacks;
    var reported: usize = 0;
    var unenumerated: usize = 0;
    for (ledger.entries[0..ledger.count]) |*entry| {
        if (!entry.used) continue;
        if (!__process_x64_linux_runtime.isCapabilityGap(entry.dll(), entry.name())) continue;
        // One inventory per library, not per name: the work is the
        // library, and printing it once per refused export would repeat
        // the same four paragraphs.
        var already = false;
        for (ledger.entries[0..ledger.count]) |*earlier| {
            if (earlier == entry) break;
            if (!earlier.used) continue;
            if (__process_std.ascii.eqlIgnoreCase(earlier.dll(), entry.dll())) already = true;
        }
        if (already) continue;
        const inventory = __process_x64_linux_runtime.importCapabilityGapFor(entry.dll()) orelse {
            unenumerated += 1;
            continue;
        };
        reported += 1;
        __process_log.warn("PE64 CAPABILITY GAP: {s} - {s}", .{ inventory.dll_name, inventory.summary });
        for (inventory.conditions) |condition| {
            __process_log.warn("PE64 CAPABILITY GAP:   needs: {s}", .{condition.requirement});
            __process_log.warn("PE64 CAPABILITY GAP:     blocked by: {s}", .{condition.blocked_by});
            __process_log.warn("PE64 CAPABILITY GAP:     without it: {s}{s}", .{
                condition.consequence,
                if (condition.blocks_first_frame) " [BLOCKS A FIRST FRAME]" else "",
            });
        }
        if (!inventory.blocksFirstFrame()) {
            __process_log.warn("PE64 CAPABILITY GAP:   none of {s}'s conditions block a first frame, so this is standing work rather than the thing to do next", .{inventory.dll_name});
        }
    }
    if (reported == 0 and unenumerated == 0) {
        __process_log.info(
            "PE64 CAPABILITY STATUS: no unresolved import capability gaps; every fallback was a modeled/policy answer or an explicitly audited dynamic refusal",
            .{},
        );
    } else if (unenumerated != 0) {
        // An absent inventory is not an empty one. Saying "nothing is
        // missing" about a library nobody has looked at would be the
        // same class of mistake as reading an inlined symbol's zero as
        // guest progress.
        __process_log.warn("PE64 CAPABILITY GAP: {d} refused librar(y/ies) have no written inventory. That is nobody having enumerated them, not nothing being missing; add one under pkg/dll/win32/capability-gap when a refusal turns out to matter", .{unenumerated});
    }
}

pub fn reportWindowsUnexplainedZeros(self: *const ElfState) void {
    const ledger = &self.windows_import_unexplained_zeros;
    if (ledger.isEmpty()) return;
    __process_log.info(
        "PE64 IMPORT ZERO AUDIT: {d} name(s) in {d} call(s) returned FALSE or NULL and set no error code. Windows sets one when a BOOL call fails, so each of these is either an honest negative answer or a handler refusing without saying so - the value cannot tell them apart, and this list is the one to read line by line",
        .{ ledger.count, self.windows_import_unexplained_events },
    );
    var order: [__process_x64_linux_runtime.ImportFallbackLedger.capacity]usize = undefined;
    const ranked = ledger.rankedInto(&order);
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    for (order[0..ranked]) |index| {
        const entry = &ledger.entries[index];
        if (!entry.used) continue;
        __process_log.info("PE64 IMPORT ZERO AUDIT:   {s}!{s} [{s}] x{d} convention={s} first_step={d} first_caller={s}", .{
            entry.dll(),
            entry.name(),
            entry.subsystem.label(),
            entry.calls,
            @tagName(entry.convention),
            entry.first_step,
            describeGuestAddressOrUnnamed(self, entry.first_caller_rip, &caller_text),
        });
    }
    if (ledger.overflow_names != 0) {
        __process_log.info("PE64 IMPORT ZERO AUDIT:   {d} further name(s) in {d} call(s) did not fit the bounded ledger", .{ ledger.overflow_names, ledger.overflow_calls });
    }
}

pub fn windowsImportIsUnimplemented(self: *const ElfState, dll_name: []const u8, name: []const u8) bool {
    const ledger = &self.windows_import_fallbacks;
    for (ledger.entries[0..ledger.count]) |*entry| {
        if (!entry.used) continue;
        if (!__process_std.mem.eql(u8, entry.name(), name)) continue;
        if (!__process_std.ascii.eqlIgnoreCase(entry.dll(), dll_name)) continue;
        return true;
    }
    return false;
}

pub fn reportWindowsImportFallbacks(self: *ElfState, full: bool) void {
    const ledger = &self.windows_import_fallbacks;
    if (ledger.isEmpty()) return;
    if (!full and ledger.unreported_count == 0) return;

    var order: [__process_x64_linux_runtime.ImportFallbackLedger.capacity]usize = undefined;
    const ranked = ledger.rankedInto(&order);
    const needsDetail = __process_x64_linux_runtime.ImportFallbackLedger.entryNeedsDetail;

    var detailed: usize = 0;
    var collapsed: usize = 0;
    for (order[0..ranked]) |index| {
        const entry = &ledger.entries[index];
        if (!full and !entry.unreported) continue;
        if (needsDetail(entry.*)) detailed += 1 else collapsed += 1;
    }
    if (detailed == 0 and collapsed == 0) return;

    const unearned = ledger.hazardCount();
    if (unearned == 0) {
        __process_log.warn(
            "IMPORT CONTRACT REFUSALS: names={d} refused={d} calls={d} new={d}; modeled Windows imports that returned an explicit ABI refusal because the optional host service is unavailable",
            .{ ledger.count, ledger.refusedCount(), ledger.total_calls, ledger.unreported_count },
        );
    } else {
        __process_log.warn(
            "IMPORT CONTRACT REFUSALS: names={d} refused={d} unearned_answers={d} calls={d} new={d}; modeled Windows imports that returned an explicit ABI refusal because the optional host service is unavailable",
            .{ ledger.count, ledger.refusedCount(), unearned, ledger.total_calls, ledger.unreported_count },
        );
    }
    for (order[0..ranked]) |index| {
        const entry = &ledger.entries[index];
        if (!full and !entry.unreported) continue;
        if (!needsDetail(entry.*)) continue;
        __process_log.warn(
            "IMPORT CONTRACT REFUSAL:   {s}!{s} [{s}{s}] calls={d} convention={s} returned=0x{x} first_step={d} first_caller=0x{x} first_args=0x{x},0x{x}; {s}",
            .{
                entry.dll(),
                entry.name(),
                entry.subsystem.label(),
                if (entry.subsystem.startupCritical()) ", startup-critical" else "",
                entry.calls,
                @tagName(entry.convention),
                entry.value,
                entry.first_step,
                entry.first_caller_rip,
                entry.first_arg0,
                entry.first_arg1,
                __process_x64_linux_runtime.importFallbackAdvice(.{
                    .convention = entry.convention,
                    .outcome = entry.outcome,
                    .value = entry.value,
                    .last_error = null,
                    .hazard = entry.hazard,
                }),
            },
        );
    }
    if (collapsed != 0) {
        // One line for everything with no observable result.  The names
        // are still here so nothing has to be guessed, but they do not
        // each get a verdict they do not need.
        var buffer: [512]u8 = undefined;
        var used: usize = 0;
        var listed: usize = 0;
        for (order[0..ranked]) |index| {
            const entry = &ledger.entries[index];
            if (!full and !entry.unreported) continue;
            if (needsDetail(entry.*)) continue;
            const written = __process_std.fmt.bufPrint(
                buffer[used..],
                "{s}{s} x{d}",
                .{ if (listed == 0) "" else ", ", entry.name(), entry.calls },
            ) catch break;
            used += written.len;
            listed += 1;
        }
        __process_log.warn(
            "IMPORT CONTRACT REFUSALS:   {d} with no observable result (explicitly modeled no-op/refusal): {s}{s}",
            .{ collapsed, buffer[0..used], if (listed < collapsed) ", ..." else "" },
        );
    }
    if (ledger.overflow_names > 0) {
        __process_log.warn(
            "IMPORT CONTRACT REFUSALS:   {d} further distinct names did not fit the bounded ledger; raise ImportFallbackLedger.capacity to see them",
            .{ledger.overflow_names},
        );
    }
    if (detailed != 0) {
        __process_log.warn(
            "IMPORT CONTRACT REFUSALS: add stateful behavior in the owning pkg/dll/win32/<dll> package and its Rosetta dispatcher when one of these refusals blocks the guest; the convention above is the value the guest is being told today",
            .{},
        );
    }
    ledger.markReported();
}

pub fn windowsImportCallsite(self: *ElfState, return_rip: u64, target: u64) ?__process_WindowsImportCallsite {
    return @import("import_callsite_cache.zig").find(self, return_rip, target);
}

pub fn tryImportSlotFastTransfer(self: *ElfState, slot: u64, call_return: u64) bool {
    if (!process_impl_lifecycle.windowsFastCrtImportMayBypassRuntimeLock(self)) return false;
    const stub = windowsImportStubForIat(self, slot) orelse return false;
    if (stub.is_dynamic or process_impl_guest_memory.read64(self, slot) != stub.address) return false;
    const regs = process_impl_lifecycle.guestContextField(self, "regs");
    const tail_jump = call_return == 0;
    const return_rip = if (tail_jump) process_impl_guest_memory.read64(self, regs.rsp) else call_return;
    if (return_rip == 0) return false;
    if (!__process_x64_linux_runtime.tryWindowsFastFunction(self, stub.dll_name, stub.function_name, return_rip)) return false;
    // The lane completed the call in its direct-return form; a thunk's
    // jump also retires the return address its caller pushed.
    if (tail_jump) regs.rsp +%= 8;
    _ = self.windows_import_slot_fast_transfers.fetchAdd(1, .monotonic);
    return true;
}

pub fn indexWindowsIatStubs(self: *ElfState) void {
    if (self.windows_iat_stub_index.len != 0) {
        self.allocator.free(self.windows_iat_stub_index);
        self.windows_iat_stub_index = &.{};
    }
    if (self.windows_iat_low == 0 or self.windows_iat_high <= self.windows_iat_low) return;
    const slots = __process_std.math.cast(usize, (self.windows_iat_high - self.windows_iat_low + 7) / 8) orelse return;
    if (slots > 1 << 20) return;
    const index = self.allocator.alloc(u32, slots) catch return;
    @memset(index, 0);
    const direct_count = @min(self.windows_direct_stub_count, self.windows_stub_count);
    for (self.windows_stub_storage[0..direct_count], 0..) |stub, position| {
        if (stub.address == 0 or stub.iat_address < self.windows_iat_low or stub.iat_address >= self.windows_iat_high) continue;
        const offset = stub.iat_address - self.windows_iat_low;
        if (offset % 8 != 0) continue;
        index[@intCast(offset / 8)] = @intCast(position + 1);
    }
    self.windows_iat_stub_index = index;
}

pub fn windowsImportStubForIat(self: *const ElfState, iat_address: u64) ?__process_WindowsImportStub {
    if (self.windows_iat_low == 0 or iat_address < self.windows_iat_low or iat_address >= self.windows_iat_high) return null;
    if (self.windows_iat_stub_index.len != 0) {
        const offset = iat_address - self.windows_iat_low;
        if (offset % 8 != 0) return null;
        const position = offset / 8;
        if (position >= self.windows_iat_stub_index.len) return null;
        const entry = self.windows_iat_stub_index[@intCast(position)];
        if (entry == 0) return null;
        const stub = self.windows_stub_storage[entry - 1];
        return if (stub.iat_address == iat_address and stub.address != 0) stub else null;
    }
    const direct_count = @min(self.windows_direct_stub_count, self.windows_stub_count);
    for (self.windows_stub_storage[0..direct_count]) |stub| {
        if (stub.iat_address == iat_address and stub.address != 0) return stub;
    }
    return null;
}

pub fn verifyWindowsImportIatAtDispatch(self: *ElfState, stub: __process_WindowsImportStub) void {
    if (stub.iat_address == 0 or stub.is_dynamic) return;
    const actual = process_impl_guest_memory.read64(self, stub.iat_address);
    if (actual == stub.address) return;
    self.windows_iat_mismatches_at_fault +|= 1;
    __process_log.err("PE64 IMPORT IAT MISMATCH: {s}!{s} slot=0x{x} expected_stub=0x{x} actual=0x{x} step={d} caller=0x{x}; direct IAT binding changed after image load", .{
        stub.dll_name,
        stub.function_name,
        stub.iat_address,
        stub.address,
        actual,
        process_impl_lifecycle.observedExecutionSteps(self),
        process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
    });
}

pub fn recordWindowsImportAbiReturn(
    self: *ElfState,
    stub: __process_WindowsImportStub,
    saved: *const __process_windows_guest_abi.Snapshot,
    entry_regs: *__process_ElfRegs,
    entry_rsp: u64,
    return_rip: u64,
    stack_pop_bytes: u64,
    entry_slot: ?usize,
    callsite_rip: u64,
) void {
    self.windows_import_abi_calls +|= 1;
    const regs = process_impl_lifecycle.guestContextField(self, "regs");
    const returned_normally = !process_impl_lifecycle.isTerminated(self) and
        @intFromPtr(regs) == @intFromPtr(entry_regs) and
        process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == entry_slot and
        regs.rip == return_rip and regs.rsp == entry_rsp +| stack_pop_bytes;
    if (!returned_normally) {
        self.windows_import_abi_nonlocal_returns +|= 1;
        return;
    }
    self.windows_import_abi_normal_returns +|= 1;
    const xmm = process_impl_lifecycle.guestContextField(self, "xmm");
    const difference = saved.difference(regs, xmm);
    if (!difference.any()) return;

    self.windows_import_abi_clobber_calls +|= 1;
    if (difference.gpr_mask != 0) self.windows_import_abi_gpr_clobbers +|= 1;
    if (difference.xmm_mask != 0) self.windows_import_abi_xmm_clobbers +|= 1;
    self.windows_import_abi_repairs +|= 1;
    if (comptime !@import("builtin").is_test) {
        const occurrences = self.windows_import_abi_clobber_calls;
        if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrences)) {
            __process_log.err("PE64 WINDOWS IMPORT ABI VIOLATION: {s}!{s} returned normally but changed callee-saved state gpr_mask=0x{x} xmm6_15_mask=0x{x} saved=[rbx=0x{x},rbp=0x{x},rsi=0x{x},rdi=0x{x},r12=0x{x},r13=0x{x},r14=0x{x},r15=0x{x}] returned=[rbx=0x{x},rbp=0x{x},rsi=0x{x},rdi=0x{x},r12=0x{x},r13=0x{x},r14=0x{x},r15=0x{x}] callsite=0x{x} return=0x{x} thread=0x{x} step={d} action=restored Windows x64 nonvolatile GPRs and XMM6-XMM15 before resuming guest code", .{
                stub.dll_name,
                stub.function_name,
                difference.gpr_mask,
                difference.xmm_mask,
                saved.rbx,
                saved.rbp,
                saved.rsi,
                saved.rdi,
                saved.r12,
                saved.r13,
                saved.r14,
                saved.r15,
                regs.rbx,
                regs.rbp,
                regs.rsi,
                regs.rdi,
                regs.r12,
                regs.r13,
                regs.r14,
                regs.r15,
                callsite_rip,
                return_rip,
                process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
    }
    saved.restore(regs, xmm);
}

pub fn windowsVulkanImportStubInterior(self: *const ElfState, address: u64) ?__process_WindowsImportStubInterior {
    const dynamic_start = @min(self.windows_dynamic_stub_start, self.windows_stub_count);
    for (self.windows_stub_storage[dynamic_start..self.windows_stub_count]) |registered| {
        if (!__process_std.mem.eql(u8, registered.dll_name, "vulkan-1.dll") or
            registered.iat_address != 0 or
            !__process_std.mem.startsWith(u8, registered.function_name, "vk")) continue;
        if (address <= registered.address) continue;
        const delta = address - registered.address;
        if (delta >= 16) continue;
        var stub = registered;
        stub.is_dynamic = true;
        return .{ .stub = stub, .offset = @intCast(delta) };
    }
    return null;
}

pub fn recoverMisalignedVulkanImportStub(
    self: *ElfState,
    address: u64,
    return_rip: u64,
) ?__process_WindowsImportStub {
    const interior = windowsVulkanImportStubInterior(self, address) orelse return null;
    self.windows_vulkan_misaligned_stub_calls +|= 1;
    const callsite = windowsImportCallsite(self, return_rip, address);
    const caller = if (callsite) |site| nearestLocalSymbol(self, site.rip) else null;
    const caller_matches = if (caller) |symbol|
        __process_std.mem.indexOf(u8, symbol.symbol, "CreateSwapchainForVulkanSurface") != null
    else
        false;
    const repairable = interior.offset == 2 and
        __process_std.mem.eql(u8, interior.stub.function_name, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR") and
        caller_matches and
        process_impl_guest_memory.read8(self, interior.stub.address) == 0xF4;
    if (!repairable) {
        __process_log.err("PE64 MISALIGNED VULKAN IMPORT STUB: target=0x{x} registered=0x{x} offset={d} import={s}!{s} callsite=0x{x} caller={s}; refusing to execute bytes from the middle of the registered thunk", .{
            address,
            interior.stub.address,
            interior.offset,
            interior.stub.dll_name,
            interior.stub.function_name,
            if (callsite) |site| site.rip else 0,
            if (caller) |symbol| symbol.symbol else "<unresolved>",
        });
        return null;
    }
    self.windows_vulkan_stub_repairs +|= 1;
    __process_log.warn("PE64 VULKAN IMPORT STUB REPAIR: target=0x{x} was offset={d} into registered thunk=0x{x} for {s}; caller={s}+0x{x} step={d}; routing this exact Vulkan surface-capabilities call through the validated Windows ABI thunk", .{
        address,
        interior.offset,
        interior.stub.address,
        interior.stub.function_name,
        caller.?.symbol,
        caller.?.symbol_offset,
        process_impl_lifecycle.observedExecutionSteps(self),
    });
    return interior.stub;
}

pub fn tryWindowsFastImportStub(self: *ElfState, stub_address: u64) bool {
    return @import("register_import.zig").tryStub(self, stub_address);
}

pub fn handleWindowsImportStub(self: *ElfState) bool {
    const entry_regs = process_impl_lifecycle.guestContextField(self, "regs");
    const stub_address = entry_regs.rip;
    const return_rip = process_impl_guest_memory.read64(self, entry_regs.rsp);
    const stub = process_impl_guest_heap.windowsImportStubAt(self, stub_address) orelse
        recoverMisalignedVulkanImportStub(self, stub_address, return_rip) orelse return false;
    // What this host thread is doing, for the watchdog's thread table
    // and a lock-held report, and - in parallel mode - how long this call
    // held the runtime lock and waited for it. The ledger is updated
    // before the caller's guard releases the lock.
    __process_concurrency.watch.beginActivity(stub.function_name);
    const timed = self.parallel_guest_execution;
    const entered_ns = if (timed) __process_concurrency.monotonicNanoseconds() else 0;
    const released_before = __ProcessInternals._runtime_lock_released_ns().*;
    const lock_requested_ns = __ProcessInternals._import_lock_requested_ns().*;
    __ProcessInternals._import_lock_requested_ns().* = 0;
    defer {
        __process_concurrency.watch.endActivity();
        if (timed) {
            const released = __ProcessInternals._runtime_lock_released_ns().* -% released_before;
            const held = (__process_concurrency.monotonicNanoseconds() -| entered_ns) -| released;
            const waited = if (lock_requested_ns != 0 and lock_requested_ns <= entered_ns) entered_ns - lock_requested_ns else 0;
            self.runtime_lock_ledger.note(stub.function_name, held, waited, released);
        }
    }
    const entry_rsp = entry_regs.rsp;
    const entry_slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
    const callsite = windowsImportCallsite(self, return_rip, stub_address);
    if (callsite) |site| {
        process_impl_lifecycle.guestContextField(self, "last_instruction_rip").* = site.rip;
        process_impl_lifecycle.guestContextField(self, "last_decoded_op").* = site.decoded.op;
        process_impl_lifecycle.guestContextField(self, "last_decoded_len").* = site.decoded.len;
    }
    const callsite_rip = if (callsite) |site| site.rip else process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*;
    const saved = __process_windows_guest_abi.Snapshot.capture(entry_regs, process_impl_lifecycle.guestContextField(self, "xmm"));
    verifyWindowsImportIatAtDispatch(self, stub);
    if (self.diagnose_abi) {
        __process_log.info("PE64 Windows import: {s}!{s} rip=0x{x} iat=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x} rsp=0x{x} return=0x{x} callsite=0x{x}", .{
            stub.dll_name,
            stub.function_name,
            stub_address,
            stub.iat_address,
            entry_regs.rcx,
            entry_regs.rdx,
            entry_regs.r8,
            entry_regs.r9,
            entry_rsp,
            return_rip,
            callsite_rip,
        });
    }
    if (process_impl_guest_heap.tryNativeWindowsVulkan(self, stub.function_name, null)) {
        recordWindowsImportAbiReturn(self, stub, &saved, entry_regs, entry_rsp, return_rip, 8, entry_slot, callsite_rip);
        return !process_impl_lifecycle.isTerminated(self);
    }
    if (__process_x64_linux_runtime.tryWindowsFunction(self, stub.dll_name, stub.function_name, null)) {
        recordWindowsImportAbiReturn(self, stub, &saved, entry_regs, entry_rsp, return_rip, 8, entry_slot, callsite_rip);
        return true;
    }
    if (!self.windows_unknown_imports_fatal) {
        // Diagnostic/non-strict mode is useful while inventorying a new
        // Windows image: keep the call boundary valid and make the
        // fallback visible through the degraded counter instead of
        // turning an intentionally permissive run into a host crash.
        const first_observation = process_impl_guest_diagnostics.recordUnresolvedWindowsImport(self, stub);
        self.windows_unknown_import_calls +|= 1;
        // An unresolved name has the same hazard as a recognized one:
        // a bare zero is `ERROR_SUCCESS`/`S_OK` for whole families of the
        // Win32 ABI.  The contract derives the refusal from the name's
        // shape, so an image Rosetta has never inventoried is refused
        // honestly rather than told its call worked.
        const fallback = __process_x64_linux_runtime.importFallbackFor(stub.dll_name, stub.function_name);
        if (first_observation) {
            __process_log.warn("unresolved Windows import continued with an ABI refusal: {s}!{s} dynamic={} convention={s} returned=0x{x} rip=0x{x} return=0x{x} caller=0x{x} step={d}", .{
                stub.dll_name,
                stub.function_name,
                stub.is_dynamic,
                @tagName(fallback.convention),
                fallback.value,
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
                process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
        self.windows_degraded_import_calls +|= 1;
        noteWindowsImportFallback(self, stub.dll_name, stub.function_name, fallback);
        if (fallback.last_error) |last_error| process_impl_lifecycle.guestContextField(self, "windows_last_error").* = last_error;
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = fallback.value;
        process_impl_lifecycle.guestContextField(self, "regs").*.rip = process_impl_guest_memory.pop(self);
        recordWindowsImportAbiReturn(self, stub, &saved, entry_regs, entry_rsp, return_rip, 8, entry_slot, callsite_rip);
        return true;
    }
    process_impl_guest_heap.terminateForUnresolvedWindowsImport(self, stub.dll_name, stub.function_name);
    return true;
}

pub fn localSymbolAddress(self: *const ElfState, name: []const u8) ?u64 {
    for (self.local_symbols) |symbol| {
        if (__process_std.mem.eql(u8, symbol.name, name)) return symbol.value;
    }
    return null;
}

pub fn localSymbolNameAt(self: *const ElfState, address: u64) ?[]const u8 {
    for (self.local_symbols) |symbol| {
        if (symbol.value == address) return symbol.name;
    }
    return null;
}

pub fn nearestLocalSymbol(self: *const ElfState, address: u64) ?__process_exit_diagnostics.SymbolizedAddress {
    if (address < self.image_low or address >= self.image_high) return null;
    var best: ?__process_elf_loader.Symbol = null;
    for (self.local_symbols) |symbol| {
        if (symbol.value == 0 or symbol.value > address) continue;
        if (best == null or symbol.value > best.?.value) best = symbol;
    }
    const symbol = best orelse return null;
    return .{ .address = symbol.value, .symbol = symbol.name, .symbol_offset = address - symbol.value };
}

pub fn windowsHeapCallSite(self: *ElfState) __process_WindowsHeapCallSite {
    const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
    const active_slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
    const import_return = process_impl_lifecycle.guestContextField(self, "windows_current_import_return").*;
    return .{
        .rip = regs.rip,
        .return_address = if (import_return != 0) import_return else process_impl_guest_memory.read64(self, regs.rsp),
        .step = process_impl_run_reporting.totalInterpretedSteps(self),
        .thread_slot = if (active_slot) |slot| @intCast(@min(slot + 1, 255)) else 0,
        .import = process_impl_lifecycle.guestContextField(self, "windows_current_import").*,
    };
}

pub fn windowsHeapStackSnapshot(self: *ElfState, rsp: u64) __process_WindowsHeapStackSnapshot {
    var snapshot = __process_WindowsHeapStackSnapshot{};
    inline for (0..6) |index| {
        const address = rsp +| (@as(u64, index) * 8);
        const readable = if (process_impl_guest_memory.addrToOffset(self, address)) |offset| blk: {
            const start: usize = @intCast(offset);
            break :blk start <= self.mem.len and 8 <= self.mem.len - start;
        } else process_impl_guest_memory.windowsMappedMemoryConst(self, address, 8) != null;
        if (readable) {
            snapshot.words[index] = process_impl_guest_memory.read64(self, address);
            snapshot.readable_mask |= @as(u8, 1) << @intCast(index);
        }
    }
    return snapshot;
}

pub fn windowsHeapCodeSnapshot(self: *ElfState, address: u64) __process_WindowsHeapCodeSnapshot {
    var snapshot = __process_WindowsHeapCodeSnapshot{};
    if (address == 0) return snapshot;
    const readable = if (process_impl_guest_memory.addrToOffset(self, address)) |offset| blk: {
        const start: usize = @intCast(offset);
        break :blk start <= self.mem.len and snapshot.bytes.len <= self.mem.len - start;
    } else process_impl_guest_memory.windowsMappedMemoryConst(self, address, snapshot.bytes.len) != null;
    if (!readable) return snapshot;
    for (&snapshot.bytes, 0..) |*byte, index| byte.* = process_impl_guest_memory.read8(self, address +| index);
    snapshot.readable = true;
    return snapshot;
}

pub fn logWindowsHeapFailureDetail(
    self: *ElfState,
    event: []const u8,
    address: u64,
    requested_size: u64,
    alignment: u64,
    record_index: ?usize,
) void {
    if (!self.windows_runtime_enabled) return;

    const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
    const site = windowsHeapCallSite(self);
    {
        const notable_kind: __process_terminal_event.NotableKind = if (__process_std.mem.eql(u8, event, "double-free"))
            .heap_double_free
        else if (__process_std.mem.eql(u8, event, "unknown-free"))
            .heap_unknown_free
        else
            .heap_refusal;
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        process_impl_execution.noteNotableEvent(self, notable_kind, site.return_address, "{s} address=0x{x} request={d} align={d} import={s} caller=0x{x} ({s})", .{
            event,
            address,
            requested_size,
            alignment,
            if (site.import.len == 0) "<none>" else site.import,
            site.return_address,
            if (site.return_address == 0) "<unknown>" else describeGuestAddressOrUnnamed(self, site.return_address, &caller_text),
        });
    }
    const stack = windowsHeapStackSnapshot(self, regs.rsp);
    const rip_code = windowsHeapCodeSnapshot(self, regs.rip);
    const return_code_start = site.return_address -| 16;
    const return_code = windowsHeapCodeSnapshot(self, return_code_start);
    const record = if (record_index) |index|
        if (index < self.windows_heap_allocation_count) &self.windows_heap_allocations[index] else null
    else
        null;

    var return_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var allocation_return_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var free_return_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const return_description = if (site.return_address == 0)
        "<unreadable return address>"
    else
        describeGuestAddressOrUnnamed(self, site.return_address, &return_text);
    const allocation_return_description = if (record) |found| blk: {
        if (found.allocation_return == 0) break :blk "<unreadable return address>";
        break :blk describeGuestAddressOrUnnamed(self, found.allocation_return, &allocation_return_text);
    } else "<no allocation record>";
    const free_return_description = if (record) |found| blk: {
        if (found.free_return == 0) break :blk "<unreadable return address>";
        break :blk describeGuestAddressOrUnnamed(self, found.free_return, &free_return_text);
    } else "<no allocation record>";

    __process_log.info("PE64 GUEST HEAP FAILURE CONTEXT: event={s} address=0x{x} request={d} align={d} record_index={any} current_import={s} current_thread_slot={d} step={d} rip=0x{x} op={s} len={d} rsp=0x{x} return=0x{x} ({s}) registers=[rax=0x{x},rbx=0x{x},rcx=0x{x},rdx=0x{x},rsi=0x{x},rdi=0x{x},rbp=0x{x},r8=0x{x},r9=0x{x},r10=0x{x},r11=0x{x},r12=0x{x},r13=0x{x},r14=0x{x},r15=0x{x}]", .{
        event,
        address,
        requested_size,
        alignment,
        record_index,
        if (site.import.len == 0) "<none>" else site.import,
        site.thread_slot,
        site.step,
        regs.rip,
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
        regs.rsp,
        site.return_address,
        return_description,
        regs.rax,
        regs.rbx,
        regs.rcx,
        regs.rdx,
        regs.rsi,
        regs.rdi,
        regs.rbp,
        regs.r8,
        regs.r9,
        regs.r10,
        regs.r11,
        regs.r12,
        regs.r13,
        regs.r14,
        regs.r15,
    });
    __process_log.info("PE64 GUEST HEAP FAILURE STACK: event={s} stack_readable_mask=0x{x} stack_words={any} rip_bytes_readable={} rip_bytes={any} return_bytes_start=0x{x} return_bytes_readable={} return_bytes={any}", .{
        event,
        stack.readable_mask,
        stack.words,
        rip_code.readable,
        rip_code.bytes,
        return_code_start,
        return_code.readable,
        return_code.bytes,
    });
    __process_log.info("PE64 GUEST HEAP FAILURE ALLOCATION: event={s} record_index={any} base=0x{x} length={d} active={} allocation_rip=0x{x} allocation_return=0x{x} ({s}) allocation_step={d} allocation_thread_slot={d} allocation_import={s}", .{
        event,
        record_index,
        if (record) |found| found.guest_base else 0,
        if (record) |found| found.length else 0,
        if (record) |found| found.active else false,
        if (record) |found| found.allocation_rip else 0,
        if (record) |found| found.allocation_return else 0,
        allocation_return_description,
        if (record) |found| found.allocation_step else 0,
        if (record) |found| found.allocation_thread_slot else 0,
        if (record) |found| (if (found.allocation_import.len == 0) "<none>" else found.allocation_import) else "<no allocation record>",
    });
    var chain_text: [1024]u8 = undefined;
    __process_log.info("PE64 GUEST HEAP FAILURE BACKTRACE: event={s} chain={s}; frames are return addresses found on the stack after real call instructions, nearest first", .{
        event,
        process_impl_execution.formatGuestBacktrace(self, regs.rsp, 6, &chain_text),
    });
    __process_log.info("PE64 GUEST HEAP FAILURE FIRST FREE: event={s} record_index={any} first_free_rip=0x{x} first_free_return=0x{x} ({s}) first_free_step={d} first_free_thread_slot={d} first_free_import={s}", .{
        event,
        record_index,
        if (record) |found| found.free_rip else 0,
        if (record) |found| found.free_return else 0,
        free_return_description,
        if (record) |found| found.free_step else 0,
        if (record) |found| found.free_thread_slot else 0,
        if (record) |found| (if (found.free_import.len == 0) "<none>" else found.free_import) else "<no allocation record>",
    });
}

pub fn recordTrace(self: *ElfState, decoded: __process_DecodedInsn) void {
    process_impl_lifecycle.guestContextField(self, "last_instruction_rip").* = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    if (self.windows_runtime_enabled and !self.trace_ring_enabled) return;
    if (self.parallel_guest_execution) self.trace_ring_mutex.lock();
    defer if (self.parallel_guest_execution) self.trace_ring_mutex.unlock();
    self.trace_ring.push(.{
        .rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        .op = decoded.op,
        .len = decoded.len,
        .rsp = process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        .rax = process_impl_lifecycle.guestContextField(self, "regs").*.rax,
        .rcx = process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
        .rdx = process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
    });
}

pub fn traceWindowsCallbackCall(self: *const ElfState, kind: []const u8, target: u64, operand: u64, next_rip: u64) void {
    if (!self.trace_windows_messages or process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frame_count").* == 0) return;
    __process_log.info("Windows callback call: kind={s} source_rip=0x{x} target=0x{x} symbol={s} operand=0x{x} next_rip=0x{x} rsp=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x} stack0=0x{x} stack1=0x{x}", .{
        kind,
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        target,
        localSymbolNameAt(self, target) orelse "",
        operand,
        next_rip,
        process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
        process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
        process_impl_lifecycle.guestContextField(self, "regs").*.r8,
        process_impl_lifecycle.guestContextField(self, "regs").*.r9,
        process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
        process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp +| 8),
    });
}
