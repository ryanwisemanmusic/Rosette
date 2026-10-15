const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_block_jit = @import("block_jit.zig");
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_heap = @import("guest_heap.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_run_reporting = @import("run_reporting.zig");
const process_impl_windows_sync = @import("windows_sync.zig");
const __process_CODE_PAGE_GENERATION_BITS = __ProcessInternals._CODE_PAGE_GENERATION_BITS;
const __process_CODE_PAGE_GENERATION_SLOTS = __ProcessInternals._CODE_PAGE_GENERATION_SLOTS;
const __process_CODE_PAGE_SHIFT = __ProcessInternals._CODE_PAGE_SHIFT;
const __process_GuestAccessViolation = __ProcessInternals._GuestAccessViolation;
const __process_GuestAccessViolationSite = __ProcessInternals._GuestAccessViolationSite;
const __process_HookBox = __ProcessInternals._HookBox;
const __process_MAX_WINDOWS_INITTERM_ENTRIES = __ProcessInternals._MAX_WINDOWS_INITTERM_ENTRIES;
const __process_MAX_WINDOWS_BSEARCH_ELEMENTS = __ProcessInternals._MAX_WINDOWS_BSEARCH_ELEMENTS;
const __process_MAX_WINDOWS_QSORT_ELEMENTS = __ProcessInternals._MAX_WINDOWS_QSORT_ELEMENTS;
const __process_MAX_WINDOWS_QSORT_ELEMENT_BYTES = __ProcessInternals._MAX_WINDOWS_QSORT_ELEMENT_BYTES;
const __process_STACK_COLLAPSE_FLOOR = __ProcessInternals._STACK_COLLAPSE_FLOOR;
const __process_SYNTHETIC_WINDOWS_CRT_EXIT_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_CRT_EXIT_RETURN;
const __process_SYNTHETIC_WINDOWS_EXCEPTION_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_EXCEPTION_RETURN;
const __process_Size = __ProcessInternals._Size;
const __process_WINDOWS_GUEST_CLOCK_HZ = __ProcessInternals._WINDOWS_GUEST_CLOCK_HZ;
const __process_WindowsAllocationDisposition = __ProcessInternals._WindowsAllocationDisposition;
const __process_WindowsAllocationRefusalReason = __ProcessInternals._WindowsAllocationRefusalReason;
const __process_WindowsExecutableRange = __ProcessInternals._WindowsExecutableRange;
const __process_WindowsMappedCodeSlice = __ProcessInternals._WindowsMappedCodeSlice;
const __process_block_jit = __ProcessInternals._block_jit;
const __process_envFlag = __ProcessInternals._envFlag;
const __process_guest_clock = __ProcessInternals._guest_clock;
const __process_guest_page_protection = __ProcessInternals._guest_page_protection;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_import_histogram = __ProcessInternals._import_histogram;
const __process_kuser_shared = __ProcessInternals._kuser_shared;
const __process_log = __ProcessInternals._log;
const __process_mapped_ranges = __ProcessInternals._mapped_ranges;
const __process_native_alias_address_base = __ProcessInternals._native_alias_address_base;
const __process_native_alias_address_limit = __ProcessInternals._native_alias_address_limit;
const __process_native_alias_alignment = __ProcessInternals._native_alias_alignment;
const __process_std = __ProcessInternals._std;
const __process_tso_memory = __ProcessInternals._tso_memory;
const __process_tso_memory_policy = __ProcessInternals._tso_memory_policy;
const __process_x64_decoder = __ProcessInternals._x64_decoder;
const __process_x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const __process_xenia_guest_address_map = __ProcessInternals._xenia_guest_address_map;
const __state_windows_context_bytes = __StateInternals._windows_context_bytes;
const __state_windows_exception_continue_execution = __StateInternals._windows_exception_continue_execution;
const __state_windows_exception_frame_magic = __StateInternals._windows_exception_frame_magic;
const __state_windows_exception_header_bytes = __StateInternals._windows_exception_header_bytes;
const __state_windows_exception_nesting_limit = __StateInternals._windows_exception_nesting_limit;
const __state_windows_exception_record_bytes = __StateInternals._windows_exception_record_bytes;
const __state_windows_memory_trace_budget = __StateInternals._windows_memory_trace_budget;
const __state_windows_memory_trace_floor = __StateInternals._windows_memory_trace_floor;
const __state_windows_memory_trace_step_budget = __StateInternals._windows_memory_trace_step_budget;
const __state_windows_status_access_violation = __StateInternals._windows_status_access_violation;

pub fn noteGuestPageProtection(
    self: *ElfState,
    address: u64,
    length: u64,
    protect: u32,
    api: []const u8,
    caller_rip: u64,
) void {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    const protection = __process_guest_page_protection.fromWindows(protect) orelse {
        if ((protect & 0x100) != 0) {
            self.guest_page_protection_guard_requests +|= 1;
        } else if (protect != 0) {
            self.guest_page_protection_unmodelled_values +|= 1;
        }
        return;
    };
    const outcome = self.guest_page_protection.set(self.allocator, address, length, protection);
    // Repeating an identical VirtualProtect is common in runtime setup
    // loops. The protection table reports exact page changes; only a
    // changed decision can make an admitted TLB access stale - and only
    // for what the new protection forbids. A read-only page keeps its
    // read entries; a page made accessible has nothing admitted that is
    // now wrong, only refusals to forget. Xenia's GPU write watch makes
    // pages read-only and accessible again every frame: on 2026-10-01
    // that was 22,513 invalidations retiring both tables in ~40
    // executors, and every hot page the guest only read was filled
    // again after each.
    if (outcome.pages_changed != 0) {
        process_impl_block_jit.invalidateAllBlockJitTlbTables(self, address, length, protection == .no_access, protection != .accessible);
        if (self.block_jit) |jit| process_impl_block_jit.bumpTlbCounter(self, &jit.tlb_invalidations);
    }
    if (outcome.allocation_failed) {
        __process_log.warn("PE64 GUEST PAGE PROTECTION: could not allocate a protection page for [0x{x},+0x{x}) from {s}; accesses to it will not fault", .{ address, length, api });
    }
    // An accessible request has no fault semantics to enforce. Xenia's
    // context allocator makes one such request at a high candidate
    // address; reporting it as an unenforced protection warning obscures
    // the meaningful case, where PAGE_NOACCESS or PAGE_READONLY would
    // escape the table. Keep counting the request in the table for
    // diagnostics, but only emit the warning for a restriction that was
    // actually lost.
    if (outcome.outside_window and protection != .accessible and self.guest_page_protection.stats().requests_outside_window == 1) {
        __process_log.warn("PE64 GUEST PAGE PROTECTION: {s} asked for {s} at 0x{x}, above the 0x{x} window the table models; it is counted and not enforced", .{
            api,
            protection.label(),
            address,
            __process_guest_page_protection.window_end,
        });
    }
    if (protection != .accessible and outcome.pages_changed != 0 and self.guest_page_protection_restrict_events < 16) {
        self.guest_page_protection_restrict_events += 1;
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        __process_log.info("PE64 GUEST PAGE PROTECTION: {s} made [0x{x},0x{x}) {s} ({d} page(s)) caller=0x{x} ({s}); an interpreted access that violates it now raises an access violation through the guest's vectored exception handler", .{
            api,
            address,
            address +| length,
            protection.label(),
            outcome.pages_changed,
            caller_rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_rip, &caller_text),
        });
    }
}

pub fn clearGuestPageProtection(self: *ElfState, address: u64, length: u64) void {
    _ = clearGuestPageProtectionAndReportInvalidation(self, address, length);
}

pub fn clearGuestPageProtectionAndReportInvalidation(self: *ElfState, address: u64, length: u64) bool {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    const outcome = self.guest_page_protection.set(self.allocator, address, length, .accessible);
    if (outcome.pages_changed == 0) return false;
    process_impl_block_jit.blockJitTlbInvalidate(self, address, length);
    return true;
}

pub fn guestPageProtectionFlags(self: *const ElfState, address: u64) u32 {
    return self.guest_page_protection.get(address).toWindows();
}

pub fn noteGuestOperandAccess(self: *ElfState, address: u64, size: __process_Size, is_write: bool, value: u64) bool {
    const width: u8 = switch (size) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32 => 4,
        .bits64 => 8,
    };
    if (!self.guest_page_protection.faults(address, width, is_write)) return false;
    if (process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").*) return is_write;
    process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").* = true;
    process_impl_lifecycle.guestContextField(self, "guest_access_violation").* = .{
        .address = address,
        .instruction_rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
        .value = value,
        .width = width,
        .is_write = is_write,
        .protection = self.guest_page_protection.get(address),
    };
    return is_write;
}

pub fn noteProtectedBulkBorrow(self: *ElfState, addr: u64, count: u64) void {
    const page_size = __process_guest_page_protection.page_size;
    var page = addr & ~(page_size - 1);
    const end = addr +| count;
    var scanned: u32 = 0;
    while (page < end and scanned < 1024) : ({
        page +|= page_size;
        scanned += 1;
    }) {
        const protection = self.guest_page_protection.get(page);
        if (protection == .accessible) continue;
        self.guest_protected_bulk_borrows +|= 1;
        self.guest_protected_bulk_borrow_bytes +|= count;
        if (self.guest_protected_bulk_borrow_reports < 8) {
            self.guest_protected_bulk_borrow_reports += 1;
            var rip_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            __process_log.info("PE64 GUEST ACCESS VIOLATIONS: a host-side borrow of {d} byte(s) at 0x{x} overlaps a {s} page at 0x{x} (rip=0x{x} {s} op={s}); Windows would have faulted inside the shim and let the vectored handler see the write, Rosette wrote without a fault, so a write watch on that page did not fire", .{
                count,
                addr,
                protection.label(),
                page,
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &rip_text),
                @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
            });
        }
        return;
    }
}

pub fn guestAccessViolationSite(self: *ElfState, page: u64) ?*__process_GuestAccessViolationSite {
    for (self.guest_access_violation_sites[0..self.guest_access_violation_site_count]) |*site| {
        if (site.page == page) return site;
    }
    if (self.guest_access_violation_site_count >= self.guest_access_violation_sites.len) {
        self.guest_access_violation_site_overflow +|= 1;
        return null;
    }
    const site = &self.guest_access_violation_sites[self.guest_access_violation_site_count];
    self.guest_access_violation_site_count += 1;
    site.* = .{ .page = page, .first_step = process_impl_lifecycle.observedExecutionSteps(self) };
    return site;
}

pub fn raiseGuestAccessViolation(self: *ElfState) void {
    const fault = process_impl_lifecycle.guestContextField(self, "guest_access_violation").*;
    process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").* = false;
    if (process_impl_windows_sync.windowsStackGuardOwner(self, fault.address)) |slot| {
        // Windows raises STATUS_STACK_OVERFLOW here and the process
        // dies; performing the access instead would write the next heap
        // object below the stack, which is how this used to fail.
        const thread = self.windows_guest_threads[slot];
        var rip_name: [256]u8 = undefined;
        self.windows_stack_overflows +|= 1;
        if (comptime !@import("builtin").is_test) __process_log.err("PE64 GUEST STACK OVERFLOW: thread={s} {s} at 0x{x} rsp=0x{x} rip=0x{x} ({s}) stack=[0x{x},0x{x}) size={d}; the thread used more stack than it was created with, and the guard below it stopped the write before it reached the heap", .{
            process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255))),
            if (fault.is_write) "write" else "read",
            fault.address,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            fault.instruction_rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, fault.instruction_rip, &rip_name),
            thread.stack_base,
            thread.stack_base +| thread.stack_size,
            thread.stack_size,
        });
        process_impl_execution.recordTerminalEvent(self, .guest_stack_overflow, "stack-guard", 0, "thread '{s}' {s} 0x{x} inside its stack guard; stack=[0x{x},0x{x}) size={d} rsp=0x{x}", .{
            process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255))),
            if (fault.is_write) "wrote" else "read",
            fault.address,
            thread.stack_base,
            thread.stack_base +| thread.stack_size,
            thread.stack_size,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        });
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        return;
    }
    self.guest_access_violations_raised +|= 1;
    if (fault.is_write) {
        self.guest_access_violation_writes +|= 1;
    } else {
        self.guest_access_violation_reads +|= 1;
    }
    const page = fault.address & ~(__process_guest_page_protection.page_size - 1);
    if (guestAccessViolationSite(self, page)) |site| {
        site.protection = fault.protection;
        if (fault.is_write) site.writes +|= 1 else site.reads +|= 1;
        site.last_rip = fault.instruction_rip;
        site.last_offset = fault.address - page;
        site.last_value = fault.value;
    }
    process_impl_guest_diagnostics.noteApuRegisterFault(self, fault);
    if (self.windows_vectored_exception_handler == 0) {
        self.guest_access_violations_without_handler +|= 1;
        completeSuppressedGuestAccess(self, fault.address, fault.width, fault.is_write, fault.value, fault.wide_value);
        return;
    }
    if (self.guest_exception_dispatches_in_flight >= __state_windows_exception_nesting_limit) {
        self.guest_access_violations_nesting_refused +|= 1;
        completeSuppressedGuestAccess(self, fault.address, fault.width, fault.is_write, fault.value, fault.wide_value);
        return;
    }
    if (!enterWindowsExceptionDispatch(self, fault)) {
        self.guest_access_violations_frame_refused +|= 1;
        completeSuppressedGuestAccess(self, fault.address, fault.width, fault.is_write, fault.value, fault.wide_value);
        return;
    }
    self.guest_access_violations_dispatched +|= 1;
}

pub fn completeSuppressedGuestAccess(self: *ElfState, address: u64, width: u8, is_write: bool, value: u64, wide_value: [16]u8) void {
    if (!is_write) return;
    switch (width) {
        1 => write8(self, address, @truncate(value)),
        2 => write16(self, address, @truncate(value)),
        4 => write32(self, address, @truncate(value)),
        16 => {
            process_impl_execution.traceGuestVectorWrite(self, address, wide_value);
            _ = process_impl_execution.copyToGuest(self, address, wide_value[0..]);
        },
        else => write64(self, address, value),
    }
}

pub fn noteGuestWideAccess(self: *ElfState, address: u64, is_write: bool, value: [16]u8) bool {
    if (!self.guest_page_protection.faults(address, 16, is_write)) return false;
    if (process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").*) return is_write;
    process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").* = true;
    process_impl_lifecycle.guestContextField(self, "guest_access_violation").* = .{
        .address = address,
        .instruction_rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
        .value = __process_std.mem.readInt(u64, value[0..8], .little),
        .wide_value = value,
        .width = 16,
        .is_write = is_write,
        .protection = self.guest_page_protection.get(address),
    };
    return is_write;
}

pub fn enterWindowsExceptionDispatch(self: *ElfState, fault: __process_GuestAccessViolation) bool {
    const post_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rsp < 0x10000) return false;
    const call_rsp = ((process_impl_lifecycle.guestContextField(self, "regs").*.rsp - 0x800) & ~@as(u64, 0xF)) - 8;
    const header = call_rsp + 0x28;
    const pointers = header + __state_windows_exception_header_bytes;
    const record = pointers + 0x10;
    const context = record + __state_windows_exception_record_bytes;
    const top = context + __state_windows_context_bytes;
    if (process_impl_execution.guestMemoryConst(self, call_rsp, top - call_rsp) == null) return false;
    if (!process_impl_execution.fillGuestMemory(self, call_rsp, top - call_rsp, 0)) return false;

    write64(self, header, __state_windows_exception_frame_magic);
    write64(self, header + 8, fault.address);
    write64(self, header + 16, post_rip);
    write64(self, header + 24, fault.value);
    write64(self, header + 32, @as(u64, fault.width) | (@as(u64, @intFromBool(fault.is_write)) << 8));
    write64(self, header + 40, __process_std.mem.readInt(u64, fault.wide_value[0..8], .little));
    write64(self, header + 48, __process_std.mem.readInt(u64, fault.wide_value[8..16], .little));
    // The faulting instruction's own rip, so the return path can tell a
    // retry (the handler left rip where it was, the write-watch protocol)
    // from a skip (the handler emulated the access and stepped over it,
    // the MMIO protocol). The header has room; nothing else uses +56.
    write64(self, header + 56, fault.instruction_rip);

    write32(self, record, __state_windows_status_access_violation);
    write64(self, record + 16, fault.instruction_rip); // ExceptionAddress
    write32(self, record + 24, 2); // NumberParameters
    write64(self, record + 32, @intFromBool(fault.is_write)); // 0 read, 1 write
    write64(self, record + 40, fault.address);

    writeGuestExceptionContext(self, context, fault.instruction_rip);

    write64(self, pointers, record);
    write64(self, pointers + 8, context);

    write64(self, call_rsp, __process_SYNTHETIC_WINDOWS_EXCEPTION_RETURN);
    process_impl_lifecycle.guestContextField(self, "regs").*.rcx = pointers;
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = call_rsp;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = self.windows_vectored_exception_handler;
    self.guest_exception_dispatches_in_flight +|= 1;
    return true;
}

pub fn writeGuestExceptionContext(self: *ElfState, context: u64, rip: u64) void {
    write32(self, context + 0x30, 0x0010_001F); // CONTEXT_ALL (AMD64)
    write32(self, context + 0x34, process_impl_lifecycle.guestContextField(self, "regs").*.mxcsr);
    write16(self, context + 0x38, 0x33); // CS
    write16(self, context + 0x3a, 0x2b); // DS
    write16(self, context + 0x3c, 0x2b); // ES
    write16(self, context + 0x3e, 0x53); // FS
    write16(self, context + 0x40, 0x2b); // GS
    write16(self, context + 0x42, 0x2b); // SS
    write32(self, context + 0x44, process_impl_lifecycle.guestContextField(self, "regs").*.rflags);
    write64(self, context + 0x78, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
    write64(self, context + 0x80, process_impl_lifecycle.guestContextField(self, "regs").*.rcx);
    write64(self, context + 0x88, process_impl_lifecycle.guestContextField(self, "regs").*.rdx);
    write64(self, context + 0x90, process_impl_lifecycle.guestContextField(self, "regs").*.rbx);
    write64(self, context + 0x98, process_impl_lifecycle.guestContextField(self, "regs").*.rsp);
    write64(self, context + 0xa0, process_impl_lifecycle.guestContextField(self, "regs").*.rbp);
    write64(self, context + 0xa8, process_impl_lifecycle.guestContextField(self, "regs").*.rsi);
    write64(self, context + 0xb0, process_impl_lifecycle.guestContextField(self, "regs").*.rdi);
    write64(self, context + 0xb8, process_impl_lifecycle.guestContextField(self, "regs").*.r8);
    write64(self, context + 0xc0, process_impl_lifecycle.guestContextField(self, "regs").*.r9);
    write64(self, context + 0xc8, process_impl_lifecycle.guestContextField(self, "regs").*.r10);
    write64(self, context + 0xd0, process_impl_lifecycle.guestContextField(self, "regs").*.r11);
    write64(self, context + 0xd8, process_impl_lifecycle.guestContextField(self, "regs").*.r12);
    write64(self, context + 0xe0, process_impl_lifecycle.guestContextField(self, "regs").*.r13);
    write64(self, context + 0xe8, process_impl_lifecycle.guestContextField(self, "regs").*.r14);
    write64(self, context + 0xf0, process_impl_lifecycle.guestContextField(self, "regs").*.r15);
    write64(self, context + 0xf8, rip);
    write32(self, context + 0x118, process_impl_lifecycle.guestContextField(self, "regs").*.mxcsr); // FltSave.MxCsr
    for (0..16) |index| {
        _ = process_impl_execution.copyToGuest(self, context + 0x1a0 + index * 16, &process_impl_lifecycle.guestContextField(self, "xmm").*[index]);
    }
}

pub fn finishWindowsExceptionDispatch(self: *ElfState) void {
    const header = process_impl_lifecycle.guestContextField(self, "regs").*.rsp +% 0x20;
    if (process_impl_execution.guestMemoryConst(self, header, __state_windows_exception_header_bytes) == null or
        read64(self, header) != __state_windows_exception_frame_magic)
    {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        __process_log.err("PE64 GUEST ACCESS VIOLATION: a return reached the exception dispatch marker without Rosette's frame above it rsp=0x{x}; the handler did not return through the frame it was called with", .{process_impl_lifecycle.guestContextField(self, "regs").*.rsp});
        return;
    }
    const context = header + __state_windows_exception_header_bytes + 0x10 + __state_windows_exception_record_bytes;
    const verdict: u32 = @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax);
    const fault_address = read64(self, header + 8);
    const post_rip = read64(self, header + 16);
    const value = read64(self, header + 24);
    const shape = read64(self, header + 32);
    var wide_value: [16]u8 = @splat(0);
    __process_std.mem.writeInt(u64, wide_value[0..8], read64(self, header + 40), .little);
    __process_std.mem.writeInt(u64, wide_value[8..16], read64(self, header + 48), .little);
    const width: u8 = @truncate(shape);
    const is_write = ((shape >> 8) & 1) != 0;
    const faulting_rip = read64(self, header + 56);

    process_impl_lifecycle.guestContextField(self, "regs").*.rax = read64(self, context + 0x78);
    process_impl_lifecycle.guestContextField(self, "regs").*.rcx = read64(self, context + 0x80);
    process_impl_lifecycle.guestContextField(self, "regs").*.rdx = read64(self, context + 0x88);
    process_impl_lifecycle.guestContextField(self, "regs").*.rbx = read64(self, context + 0x90);
    const rsp_before_restore = process_impl_lifecycle.guestContextField(self, "regs").*.rsp;
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = read64(self, context + 0x98);
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rsp < __process_STACK_COLLAPSE_FLOOR) {
        process_impl_kernel_services.noteStackPointerCollapse(self, "exception-context-restore", rsp_before_restore, read64(self, context + 0xf8), "CONTEXT.Rsp");
    }
    process_impl_lifecycle.guestContextField(self, "regs").*.rbp = read64(self, context + 0xa0);
    process_impl_lifecycle.guestContextField(self, "regs").*.rsi = read64(self, context + 0xa8);
    process_impl_lifecycle.guestContextField(self, "regs").*.rdi = read64(self, context + 0xb0);
    process_impl_lifecycle.guestContextField(self, "regs").*.r8 = read64(self, context + 0xb8);
    process_impl_lifecycle.guestContextField(self, "regs").*.r9 = read64(self, context + 0xc0);
    process_impl_lifecycle.guestContextField(self, "regs").*.r10 = read64(self, context + 0xc8);
    process_impl_lifecycle.guestContextField(self, "regs").*.r11 = read64(self, context + 0xd0);
    process_impl_lifecycle.guestContextField(self, "regs").*.r12 = read64(self, context + 0xd8);
    process_impl_lifecycle.guestContextField(self, "regs").*.r13 = read64(self, context + 0xe0);
    process_impl_lifecycle.guestContextField(self, "regs").*.r14 = read64(self, context + 0xe8);
    process_impl_lifecycle.guestContextField(self, "regs").*.r15 = read64(self, context + 0xf0);
    process_impl_lifecycle.guestContextField(self, "regs").*.rflags = read32(self, context + 0x44);
    for (0..16) |index| {
        _ = process_impl_execution.copyFromGuest(self, &process_impl_lifecycle.guestContextField(self, "xmm").*[index], context + 0x1a0 + index * 16);
    }
    self.guest_exception_dispatches_in_flight -|= 1;

    const page = fault_address & ~(__process_guest_page_protection.page_size - 1);
    var site: ?*__process_GuestAccessViolationSite = null;
    for (self.guest_access_violation_sites[0..self.guest_access_violation_site_count]) |*candidate| {
        if (candidate.page == page) site = candidate;
    }
    if (verdict == __state_windows_exception_continue_execution) {
        const resume_rip = read64(self, context + 0xf8);
        // A handler that leaves rip on the faulting instruction is asking
        // for the access to be retried, which is the write-watch protocol:
        // it has cleared the protection, so the retry lands. If the
        // protection is still there the retry faults again, on the same
        // instruction, forever - and nothing in the run would say so,
        // because a fault loop retires instructions and so reads as
        // progress to every liveness gate. Perform the access once and
        // report it instead of hanging. The MMIO protocol is untouched:
        // that handler emulates the access and moves rip past it.
        if (resume_rip == faulting_rip and
            self.guest_page_protection.faults(fault_address, @max(width, 1), is_write))
        {
            self.guest_access_violation_unresolved_retries +|= 1;
            if (self.guest_access_violation_unresolved_retries == 1) {
                __process_log.warn("PE64 GUEST ACCESS VIOLATION: the handler asked for a retry at rip=0x{x} but left [0x{x},+{d}) {s}; a retry would fault forever, so Rosette performed the access. Xenia's page flags and Rosette's protection table disagree about this page", .{
                    faulting_rip,
                    fault_address,
                    width,
                    self.guest_page_protection.get(fault_address).label(),
                });
            }
            process_impl_lifecycle.guestContextField(self, "regs").*.rip = post_rip;
            completeSuppressedGuestAccess(self, fault_address, width, is_write, value, wide_value);
            self.guest_access_violations_handled +|= 1;
            if (site) |record| record.handled +|= 1;
            return;
        }
        process_impl_lifecycle.guestContextField(self, "regs").*.rip = resume_rip;
        self.guest_access_violations_handled +|= 1;
        if (site) |record| record.handled +|= 1;
        return;
    }
    // EXCEPTION_CONTINUE_SEARCH. Windows would try frame handlers and
    // then end the process. Rosette performs the access it withheld and
    // continues after the instruction, which is the behaviour every run
    // before this one had - reported, so it is never mistaken for a
    // delivered fault.
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = post_rip;
    completeSuppressedGuestAccess(self, fault_address, width, is_write, value, wide_value);
    self.guest_access_violations_unhandled +|= 1;
    if (site) |record| {
        record.unhandled +|= 1;
        if (record.unhandled == 1) {
            __process_log.warn("PE64 GUEST ACCESS VIOLATION: the vectored handler declined a {s} at 0x{x}; Windows would have terminated the process, Rosette performed the access and continued", .{
                if (is_write) "write" else "read",
                fault_address,
            });
        }
    }
}

pub fn addrToOffset(self: *const ElfState, vaddr: u64) ?u64 {
    if (vaddr < self.mem_base) return null;
    const off = vaddr - self.mem_base;
    if (off >= self.mem_size) return null;
    return off;
}

pub fn noteWindowsAllocationDisposition(
    self: *ElfState,
    requested_base: u64,
    length: u64,
    reserve_requested: bool,
    commit_requested: bool,
    served: bool,
    caller_rip: u64,
) __process_WindowsAllocationDisposition {
    const span = @max(length, @as(u64, 1));
    const disposition: __process_WindowsAllocationDisposition = blk: {
        if (!served) break :blk .refused;
        if (requested_base == 0) break :blk .reserved_new;
        if (reserve_requested and !commit_requested) {
            break :blk if (windowsVirtualAllocationContains(self, requested_base, span))
                .reserve_over_existing
            else
                .reserved_new;
        }
        if (!commit_requested) break :blk .reserved_new;
        // Commit. Which backing covers it decides everything.
        if (addrToOffset(self, requested_base) != null) break :blk .committed_in_image;
        if (windowsMappedRangeContains(self, requested_base, span)) break :blk .committed_in_mapped_view;
        if (windowsVirtualAllocationContains(self, requested_base, span)) break :blk .committed_in_reservation;
        break :blk .committed_unbacked;
    };
    self.windows_allocation_dispositions[@intFromEnum(disposition)] +|= 1;
    if (disposition == .committed_unbacked) {
        noteWindowsUnbackedCommit(self, requested_base, span, caller_rip);
    } else if (disposition == .refused) {
        noteWindowsAllocationRefusal(
            self,
            requested_base,
            span,
            reserve_requested,
            commit_requested,
            caller_rip,
        );
    }
    return disposition;
}

pub fn relocateWindowsThreadContextAllocation(
    self: *ElfState,
    requested_base: u64,
    length: u64,
    caller_rip: u64,
) ?u64 {
    if (!__process_xenia_guest_address_map.isContextCandidate(requested_base)) return null;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const caller = process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_rip, &caller_text);
    if (__process_std.mem.indexOf(u8, caller, "xe::cpu::ThreadState") == null) return null;

    var candidate = requested_base;
    while (__process_xenia_guest_address_map.nextContextCandidate(candidate)) |next| {
        candidate = next;
        if (windowsGuestRangeContains(self, candidate, length)) continue;
        if (createWindowsVirtualAllocation(self, candidate, length)) return candidate;
    }
    return null;
}

pub fn noteWindowsAllocationRelocation(
    self: *ElfState,
    requested_base: u64,
    actual_base: u64,
    length: u64,
    caller_rip: u64,
) __process_WindowsAllocationDisposition {
    self.windows_allocation_dispositions[@intFromEnum(__process_WindowsAllocationDisposition.relocated)] +|= 1;
    const accounting_step = process_impl_run_reporting.totalInterpretedSteps(self);
    for (self.windows_allocation_relocations[0..self.windows_allocation_relocation_count]) |*record| {
        if (record.requested_base == requested_base and record.actual_base == actual_base and record.caller_rip == caller_rip) {
            record.occurrences +|= 1;
            record.last_step = accounting_step;
            return .relocated;
        }
    }
    if (self.windows_allocation_relocation_count >= self.windows_allocation_relocations.len) {
        for (self.windows_allocation_relocation_overflow_records[0..self.windows_allocation_relocation_overflow_record_count]) |*record| {
            if (record.requested_base == requested_base and record.actual_base == actual_base and record.caller_rip == caller_rip) {
                record.occurrences +|= 1;
                record.last_step = accounting_step;
                self.windows_allocation_relocation_overflow +|= 1;
                return .relocated;
            }
        }
        if (self.windows_allocation_relocation_overflow_record_count < self.windows_allocation_relocation_overflow_records.len) {
            const overflow_record = &self.windows_allocation_relocation_overflow_records[self.windows_allocation_relocation_overflow_record_count];
            overflow_record.* = .{
                .requested_base = requested_base,
                .actual_base = actual_base,
                .length = length,
                .caller_rip = caller_rip,
                .step = accounting_step,
                .last_step = accounting_step,
                .occurrences = 1,
            };
            self.windows_allocation_relocation_overflow_record_count += 1;
        }
        self.windows_allocation_relocation_overflow +|= 1;
        return .relocated;
    }
    const record = &self.windows_allocation_relocations[self.windows_allocation_relocation_count];
    record.* = .{
        .requested_base = requested_base,
        .actual_base = actual_base,
        .length = length,
        .caller_rip = caller_rip,
        .step = accounting_step,
        .last_step = accounting_step,
        .occurrences = 1,
    };
    self.windows_allocation_relocation_count += 1;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    __process_log.info("PE64 Windows memory contract: fixed allocation relocated requested=0x{x} actual=0x{x} length={d} step={d} caller=0x{x} ({s}); the Xenia context allocator received the next unique candidate", .{
        requested_base,
        actual_base,
        length,
        accounting_step,
        caller_rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_rip, &caller_text),
    });
    return .relocated;
}

pub fn noteWindowsUnbackedCommit(self: *ElfState, base: u64, length: u64, caller_rip: u64) void {
    for (self.windows_unbacked_commits[0..self.windows_unbacked_commit_count]) |*record| {
        if (record.caller_rip == caller_rip) {
            record.occurrences +|= 1;
            return;
        }
    }
    if (self.windows_unbacked_commit_count >= self.windows_unbacked_commits.len) {
        self.windows_unbacked_commit_overflow +|= 1;
        return;
    }
    const record = &self.windows_unbacked_commits[self.windows_unbacked_commit_count];
    record.* = .{
        .base = base,
        .length = length,
        .caller_rip = caller_rip,
        .step = process_impl_lifecycle.observedExecutionSteps(self),
        .occurrences = 1,
    };
    self.windows_unbacked_commit_count += 1;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    __process_log.info("PE64 Windows memory contract: commit on unreserved address base=0x{x} length={d} step={d} caller=0x{x} ({s}); Windows would have failed this with ERROR_INVALID_ADDRESS, Rosette serves it and records the divergence rather than ending the run over bookkeeping the guest has already lost", .{
        base,
        length,
        process_impl_lifecycle.observedExecutionSteps(self),
        caller_rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_rip, &caller_text),
    });
}

pub fn noteWindowsAllocationRefusal(
    self: *ElfState,
    requested_base: u64,
    length: u64,
    reserve_requested: bool,
    commit_requested: bool,
    caller_rip: u64,
) void {
    const reason: __process_WindowsAllocationRefusalReason = if (requested_base != 0 and reserve_requested and
        windowsVirtualAllocationContains(self, requested_base, length))
        .reserve_over_existing
    else
        .allocation_backend_refused;
    for (self.windows_allocation_refusals[0..self.windows_allocation_refusal_count]) |*record| {
        if (record.caller_rip == caller_rip and record.reason == reason) {
            record.occurrences +|= 1;
            return;
        }
    }
    if (self.windows_allocation_refusal_count >= self.windows_allocation_refusals.len) {
        self.windows_allocation_refusal_overflow +|= 1;
        return;
    }
    const record = &self.windows_allocation_refusals[self.windows_allocation_refusal_count];
    record.* = .{
        .base = requested_base,
        .length = length,
        .caller_rip = caller_rip,
        .step = process_impl_lifecycle.observedExecutionSteps(self),
        .occurrences = 1,
        .reason = reason,
        .reserve_requested = reserve_requested,
        .commit_requested = commit_requested,
    };
    self.windows_allocation_refusal_count += 1;
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    __process_log.info("PE64 Windows memory contract: allocation refusal: reason={s} base=0x{x} length={d} reserve={} commit={} step={d} caller=0x{x} ({s}); this request was not served and remains distinct from a commit Rosette promoted", .{
        reason.label(),
        requested_base,
        length,
        reserve_requested,
        commit_requested,
        process_impl_lifecycle.observedExecutionSteps(self),
        caller_rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_rip, &caller_text),
    });
}

pub fn reportWindowsMemoryContract(self: *const ElfState) void {
    var total: u64 = 0;
    for (self.windows_allocation_dispositions) |count| total +|= count;
    if (total == 0) return;
    __process_log.info("PE64 MEMORY CONTRACT: {d} fixed allocation request(s); a commit is only sound when something already backs its address", .{total});
    inline for (@typeInfo(__process_WindowsAllocationDisposition).@"enum".fields) |field| {
        const disposition: __process_WindowsAllocationDisposition = @enumFromInt(field.value);
        const count = self.windows_allocation_dispositions[field.value];
        if (count != 0) {
            __process_log.info("PE64 MEMORY CONTRACT:   {s:<26} {d}{s}", .{
                disposition.label(),
                count,
                if (disposition.divergesFromWindows()) "  <- Windows would have failed these" else "",
            });
        }
    }
    for (self.windows_allocation_refusals[0..self.windows_allocation_refusal_count]) |*record| {
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        __process_log.info("PE64 MEMORY CONTRACT:   refusal x{d} reason={s} base=0x{x} length={d} reserve={} commit={} first_step={d} caller={s}", .{
            record.occurrences,
            record.reason.label(),
            record.base,
            record.length,
            record.reserve_requested,
            record.commit_requested,
            record.step,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, record.caller_rip, &caller_text),
        });
    }
    for (self.windows_allocation_relocations[0..self.windows_allocation_relocation_count]) |*record| {
        var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        __process_log.info("PE64 MEMORY CONTRACT:   relocated x{d} requested=0x{x} actual=0x{x} length={d} first_step={d} last_step={d} caller={s}", .{
            record.occurrences,
            record.requested_base,
            record.actual_base,
            record.length,
            record.step,
            record.last_step,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, record.caller_rip, &caller_text),
        });
    }
    if (self.windows_allocation_relocation_overflow != 0) {
        __process_log.info("PE64 MEMORY CONTRACT:   {d} further relocation request(s) exceeded the primary bounded table; retained_overflow_sites={d} digest_capacity={d}", .{
            self.windows_allocation_relocation_overflow,
            self.windows_allocation_relocation_overflow_record_count,
            self.windows_allocation_relocation_overflow_records.len,
        });
        for (self.windows_allocation_relocation_overflow_records[0..self.windows_allocation_relocation_overflow_record_count]) |*record| {
            var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            __process_log.info("PE64 MEMORY CONTRACT:     overflow_digest x{d} requested=0x{x} actual=0x{x} length={d} first_step={d} last_step={d} caller={s}", .{
                record.occurrences,
                record.requested_base,
                record.actual_base,
                record.length,
                record.step,
                record.last_step,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, record.caller_rip, &caller_text),
            });
        }
    }
    if (self.windows_allocation_refusal_overflow != 0) {
        __process_log.info("PE64 MEMORY CONTRACT:   {d} further refusal site(s) did not fit the bounded table", .{self.windows_allocation_refusal_overflow});
    }
    // A generic refusal is still a real finding. Xenia's
    // `AllocateContext` is handled above by giving it the next candidate
    // in its own `pos32` sequence, so a remaining reserve conflict now
    // identifies a caller Rosetta has not yet safely mapped.
    var reserve_conflicts: u64 = 0;
    var other_refusals: u64 = 0;
    for (self.windows_allocation_refusals[0..self.windows_allocation_refusal_count]) |*record| {
        if (record.reason == .reserve_over_existing) {
            reserve_conflicts +|= record.occurrences;
        } else {
            other_refusals +|= record.occurrences;
        }
    }
    if (reserve_conflicts != 0) {
        __process_log.info("PE64 MEMORY CONTRACT:   {d} reserve-over-existing request(s) remain after known Xenia context relocation; these are unresolved fixed-address callers and require a new mapping policy", .{reserve_conflicts});
    }
    if (other_refusals != 0) {
        __process_log.info("PE64 MEMORY CONTRACT:   {d} refusal(s) were NOT an occupancy conflict - Rosette could not back the range at all, which is a finding", .{other_refusals});
    }
    if (self.windows_unbacked_commit_count == 0) {
        __process_log.info("PE64 MEMORY CONTRACT:   verdict: every commit landed inside something that already backed it", .{});
        return;
    }
    var caller_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    for (self.windows_unbacked_commits[0..self.windows_unbacked_commit_count]) |*record| {
        __process_log.info("PE64 MEMORY CONTRACT:   unbacked commit x{d} base=0x{x} length={d} first_step={d} caller={s}", .{
            record.occurrences,
            record.base,
            record.length,
            record.step,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, record.caller_rip, &caller_text),
        });
    }
    if (self.windows_unbacked_commit_overflow != 0) {
        __process_log.info("PE64 MEMORY CONTRACT:   {d} further unbacked commit site(s) did not fit the bounded table", .{self.windows_unbacked_commit_overflow});
    }
    __process_log.info("PE64 MEMORY CONTRACT:   verdict: {d} commit site(s) had no reservation behind them. Xenia's own BaseHeap prints `attempting commit on unreserved page` for the same condition and then promotes the request; the two ledgers now agree on which addresses those are", .{self.windows_unbacked_commit_count});
}

pub fn trimWindowsFileMappingCount(self: *ElfState) void {
    while (self.windows_file_mapping_count != 0 and
        self.windows_file_mappings[self.windows_file_mapping_count - 1].backing == null)
    {
        self.windows_file_mapping_count -= 1;
    }
}

pub fn trimWindowsMemoryViewCount(self: *ElfState) void {
    while (self.windows_memory_view_count != 0 and
        self.windows_memory_views[self.windows_memory_view_count - 1].length == 0)
    {
        self.windows_memory_view_count -= 1;
    }
}

pub fn trimWindowsVirtualAllocationCount(self: *ElfState) void {
    while (self.windows_virtual_allocation_count != 0 and
        self.windows_virtual_allocations[self.windows_virtual_allocation_count - 1].backing == null)
    {
        self.windows_virtual_allocation_count -= 1;
    }
}

pub fn configureWindowsTraceRing(self: *ElfState) void {
    self.trace_ring_enabled = __process_envFlag("ROSETTE_ELF_TRACE_RING");
}

pub fn configureWindowsExecutableRanges(
    self: *ElfState,
    ranges: []const __process_WindowsExecutableRange,
) void {
    self.windows_executable_range_count = @min(ranges.len, self.windows_executable_ranges.len);
    var box: __process_HookBox = .{};
    for (self.windows_executable_ranges[0..self.windows_executable_range_count], 0..) |*destination, index| {
        destination.* = ranges[index];
        box.widenRange(ranges[index].guest_base, ranges[index].length);
    }
    for (self.windows_executable_ranges[self.windows_executable_range_count..]) |*destination| {
        destination.* = .{};
    }
    self.windows_executable_box = box;
    self.windows_executable_range_hint.store(0, .monotonic);
    // Pages admitted for writing before a range became executable would
    // skip the image code-generation bump.
    process_impl_block_jit.blockJitTlbFlush(self, false, true);
}

pub fn windowsVirtualAllocationContains(self: *const ElfState, address: u64, count: u64) bool {
    const end = __process_std.math.add(u64, address, count) catch return false;
    for (self.windows_virtual_allocations[0..self.windows_virtual_allocation_count]) |allocation| {
        if (allocation.length == 0 or allocation.backing == null or address < allocation.guest_base) continue;
        const allocation_end = __process_std.math.add(u64, allocation.guest_base, allocation.length) catch continue;
        if (end <= allocation_end) return true;
    }
    return false;
}

pub fn windowsMappedRangeContains(self: *const ElfState, address: u64, count: u64) bool {
    const end = __process_std.math.add(u64, address, count) catch return false;
    for (self.windows_memory_views[0..self.windows_memory_view_count]) |view| {
        if (view.length == 0 or address < view.guest_base) continue;
        const view_end = __process_std.math.add(u64, view.guest_base, view.length) catch continue;
        if (end <= view_end) return true;
    }
    return false;
}

pub fn windowsGuestRangeContains(self: *const ElfState, address: u64, count: u64) bool {
    if (count == 0) return true;
    if (addrToOffset(self, address)) |offset| {
        const count_usize = __process_std.math.cast(usize, count) orelse return false;
        const offset_usize = __process_std.math.cast(usize, offset) orelse return false;
        return offset_usize <= self.mem.len and count_usize <= self.mem.len - offset_usize;
    }
    if (windowsMappedRangeContains(self, address, count)) return true;
    if (windowsVirtualAllocationContains(self, address, count)) return true;
    if (nativeMemoryAlias(self, address, count) != null) return true;
    return false;
}

pub fn nativeMemoryAlias(self: *const ElfState, address: u64, count: u64) ?[]u8 {
    if (address < __process_native_alias_address_base or address >= __process_native_alias_address_limit) return null;
    const length = __process_std.math.cast(usize, count) orelse return null;
    for (self.native_memory_aliases[0..self.native_memory_alias_count]) |alias| {
        const bytes = alias.bytes orelse continue;
        if (address < alias.guest_base) continue;
        const offset = __process_std.math.cast(usize, address - alias.guest_base) orelse continue;
        if (offset <= bytes.len and length <= bytes.len - offset) return bytes[offset..][0..length];
    }
    return null;
}

pub fn borrowNativeMemory(self: *ElfState, bytes: []u8) ?u64 {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    if (bytes.len == 0 or bytes.len > 64 * 1024 * 1024) return null;
    // Preserve the native pointer's low 32 bits. Therefore guest_pointer
    // minus map offset retains every native alignment up to 4 GiB. These
    // are address-space slots only: no multi-gigabyte backing is allocated.
    const native_low = @intFromPtr(bytes.ptr) & (__process_native_alias_alignment - 1);
    const span = __process_std.mem.alignForward(u64, @as(u64, @intCast(bytes.len)) + native_low, __process_native_alias_alignment);
    for (&self.native_memory_aliases, 0..) |*alias, index| {
        if (alias.bytes != null or alias.reserved_span < span or !windowsViewRangeIsFree(self, alias.slot_base, span)) continue;
        alias.guest_base = alias.slot_base + native_low;
        alias.bytes = bytes;
        self.native_memory_alias_count = @max(self.native_memory_alias_count, index + 1);
        // The free slot may retain a direct-TLB translation from an
        // earlier lifetime. Retire it before publishing the new backing
        // so every owner/worker resolves the alias to this slice.
        process_impl_block_jit.blockJitTlbInvalidate(self, alias.guest_base, bytes.len);
        return alias.guest_base;
    }
    var candidate = self.native_memory_alias_next;
    // Bounded address search. Guest mappings can legitimately occupy a
    // candidate; never overlap them or silently change their ownership.
    for (0..256) |_| {
        const next = __process_std.math.add(u64, candidate, span + __process_native_alias_alignment) catch return null;
        if (next > __process_native_alias_address_limit) return null;
        if (windowsViewRangeIsFree(self, candidate, span)) {
            for (&self.native_memory_aliases, 0..) |*alias, index| {
                if (alias.bytes != null) continue;
                alias.* = .{ .guest_base = candidate + native_low, .bytes = bytes, .reserved_span = span, .slot_base = candidate };
                self.native_memory_alias_count = @max(self.native_memory_alias_count, index + 1);
                self.native_memory_alias_next = next;
                process_impl_block_jit.blockJitTlbInvalidate(self, alias.guest_base, bytes.len);
                return alias.guest_base;
            }
            return null;
        }
        candidate = next;
    }
    return null;
}

pub fn releaseNativeMemory(self: *ElfState, guest_base: u64) void {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    for (self.native_memory_aliases[0..self.native_memory_alias_count]) |*alias| {
        if (alias.guest_base == guest_base) {
            if (alias.bytes) |bytes| process_impl_block_jit.blockJitTlbInvalidate(self, alias.guest_base, bytes.len);
            alias.bytes = null;
        }
    }
    while (self.native_memory_alias_count != 0 and self.native_memory_aliases[self.native_memory_alias_count - 1].bytes == null) self.native_memory_alias_count -= 1;
}

pub fn windowsMappingIndex(self: *const ElfState, handle: u64) ?usize {
    if (handle == 0) return null;
    for (self.windows_file_mappings[0..self.windows_file_mapping_count], 0..) |mapping, index| {
        if (mapping.guest_handle == handle and mapping.backing != null) return index;
    }
    return null;
}

pub fn windowsViewRangeIsFree(self: *const ElfState, guest_base: u64, length: u64) bool {
    const end = __process_std.math.add(u64, guest_base, length) catch return false;
    const ordinary_end = __process_std.math.add(u64, self.mem_base, self.mem_size) catch __process_std.math.maxInt(u64);
    if (guest_base < ordinary_end and end > self.mem_base) return false;
    for (self.native_memory_aliases[0..self.native_memory_alias_count]) |alias| {
        const bytes = alias.bytes orelse continue;
        if (guest_base < alias.guest_base + bytes.len and end > alias.guest_base) return false;
    }
    for (self.windows_memory_views[0..self.windows_memory_view_count]) |view| {
        if (view.length == 0) continue;
        const view_end = __process_std.math.add(u64, view.guest_base, view.length) catch __process_std.math.maxInt(u64);
        if (guest_base < view_end and end > view.guest_base) return false;
    }
    for (self.windows_virtual_allocations[0..self.windows_virtual_allocation_count]) |allocation| {
        if (allocation.length == 0) continue;
        const allocation_end = __process_std.math.add(u64, allocation.guest_base, allocation.length) catch __process_std.math.maxInt(u64);
        if (guest_base < allocation_end and end > allocation.guest_base) return false;
    }
    return true;
}

pub fn windowsMappingHasViews(self: *const ElfState, mapping_index: usize) bool {
    for (self.windows_memory_views[0..self.windows_memory_view_count]) |view| {
        if (view.length != 0 and view.mapping_index == mapping_index) return true;
    }
    return false;
}

pub fn releaseClosedWindowsMapping(self: *ElfState, mapping_index: usize) void {
    const mapping = &self.windows_file_mappings[mapping_index];
    if (!mapping.closed or windowsMappingHasViews(self, mapping_index)) return;
    if (mapping.backing) |backing| __process_std.posix.munmap(backing);
    mapping.* = .{};
    trimWindowsFileMappingCount(self);
}

pub fn createWindowsMemoryMapping(
    self: *ElfState,
    handle: u64,
    requested_length: u64,
    source_handle: u64,
) bool {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    if (handle == 0 or requested_length == __process_std.math.maxInt(u64)) return false;

    var host_fd: __process_std.posix.fd_t = -1;
    var file_size: ?u64 = null;
    var media_authorized = false;
    if (source_handle != __process_std.math.maxInt(u64)) {
        const io = self.windows_host_io orelse return false;
        for (self.windows_files) |slot| {
            if (slot.file == null or slot.guest_handle != source_handle) continue;
            if (!slot.readable) return false;
            const stat = slot.file.?.stat(io) catch return false;
            host_fd = slot.file.?.handle;
            file_size = stat.size;
            media_authorized = slot.media_authorized;
            break;
        }
        if (host_fd < 0) return false;
    }

    var effective_length = requested_length;
    if (file_size) |size| {
        if (effective_length == 0) effective_length = size;
        if (effective_length > size) return false;
    }
    if (effective_length == 0) return false;

    const inclusive_length = __process_std.math.add(u64, effective_length, 1) catch return false;
    const page_size: u64 = @intCast(__process_std.heap.page_size_min);
    const rounded_length = __process_std.math.add(u64, inclusive_length, page_size - 1) catch return false;
    const mapping_length = rounded_length & ~(page_size - 1);
    const length: usize = __process_std.math.cast(usize, mapping_length) orelse return false;
    const prot: __process_std.posix.PROT = if (file_size != null)
        @bitCast(@as(u32, 0x1))
    else
        @bitCast(@as(u32, 0x1 | 0x2));
    const flags: __process_std.posix.MAP = if (file_size != null)
        @bitCast(@as(u32, 0x2))
    else
        @bitCast(@as(u32, 0x1000 | 0x2));
    const backing = __process_std.posix.mmap(null, length, prot, flags, host_fd, 0) catch |err| {
        __process_log.err("PE64 Windows CreateFileMapping failed: handle=0x{x} requested_length={d} mapped_length={d} reason={s}", .{
            handle,
            effective_length,
            mapping_length,
            @errorName(err),
        });
        return false;
    };

    for (&self.windows_file_mappings, 0..) |*mapping, mapping_index| {
        if (mapping.backing == null) {
            mapping.* = .{
                .guest_handle = handle,
                .length = mapping_length,
                .backing = backing,
                .media_authorized = media_authorized,
            };
            if (mapping_index >= self.windows_file_mapping_count) {
                self.windows_file_mapping_count = mapping_index + 1;
            }
            if (media_authorized and self.windows_media_mapping_trace_events < 8) {
                self.windows_media_mapping_trace_events += 1;
                __process_log.info("PE64 Windows media mapping: handle=0x{x} source_handle=0x{x} requested_length={d} mapped_length={d} backing=0x{x}", .{
                    handle,
                    source_handle,
                    effective_length,
                    mapping_length,
                    @intFromPtr(backing.ptr),
                });
            }
            if (self.diagnose_abi) {
                __process_log.info("PE64 Windows CreateFileMapping: handle=0x{x} source_handle=0x{x} file_backed={} requested_length={d} mapped_length={d} backing=0x{x}", .{
                    handle,
                    source_handle,
                    file_size != null,
                    effective_length,
                    mapping_length,
                    @intFromPtr(backing.ptr),
                });
            }
            if (self.trace_windows_mappings and self.windows_mapping_trace_events < 16) {
                self.windows_mapping_trace_events += 1;
                __process_log.info("PE64 Windows mapping trace: create index={d} handle=0x{x} source_handle=0x{x} length={d} backing=0x{x} file_backed={}", .{
                    mapping_index,
                    handle,
                    source_handle,
                    mapping_length,
                    @intFromPtr(backing.ptr),
                    file_size != null,
                });
            }
            return true;
        }
    }
    __process_std.posix.munmap(backing);
    process_impl_windows_sync.noteWindowsFileMappingTableFull(self, handle);
    return false;
}

pub fn createWindowsVirtualAllocation(self: *ElfState, guest_base: u64, requested_length: u64) bool {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    if (guest_base == 0 or requested_length == 0) return false;
    // A driver-owned Vulkan alias is not a VirtualAlloc reservation.
    if (nativeMemoryAlias(self, guest_base, 1) != null) return false;
    const page_size: u64 = @intCast(__process_std.heap.page_size_min);
    if (guest_base % page_size != 0) return false;
    const rounded_length = __process_std.math.add(u64, requested_length, page_size - 1) catch return false;
    const allocation_length = rounded_length & ~(page_size - 1);
    if (windowsGuestRangeContains(self, guest_base, allocation_length)) return true;
    if (!windowsViewRangeIsFree(self, guest_base, allocation_length)) return false;
    const length = __process_std.math.cast(usize, allocation_length) orelse return false;
    const prot: __process_std.posix.PROT = @bitCast(@as(u32, 0x1 | 0x2));
    const flags: __process_std.posix.MAP = @bitCast(@as(u32, 0x1000 | 0x2));
    const backing = __process_std.posix.mmap(null, length, prot, flags, -1, 0) catch |err| {
        __process_log.err("PE64 Windows VirtualAlloc fixed mapping failed: guest_base=0x{x} requested_length={d} mapped_length={d} reason={s}", .{
            guest_base,
            requested_length,
            allocation_length,
            @errorName(err),
        });
        return false;
    };

    for (&self.windows_virtual_allocations, 0..) |*allocation, allocation_index| {
        if (allocation.backing == null) {
            if (!indexWindowsMappedRange(self, .{
                .base = guest_base,
                .length = allocation_length,
                .kind = .virtual_allocation,
                .slot = allocation_index,
            })) {
                __process_std.posix.munmap(backing);
                return false;
            }
            allocation.* = .{
                .guest_base = guest_base,
                .length = allocation_length,
                .backing = backing,
            };
            if (allocation_index >= self.windows_virtual_allocation_count) {
                self.windows_virtual_allocation_count = allocation_index + 1;
            }
            if (self.diagnose_abi) {
                __process_log.info("PE64 Windows VirtualAlloc fixed: guest_base=0x{x} requested_length={d} mapped_length={d} backing=0x{x}", .{
                    guest_base,
                    requested_length,
                    allocation_length,
                    @intFromPtr(backing.ptr),
                });
            }
            return true;
        }
    }
    __process_std.posix.munmap(backing);
    __process_log.err("PE64 Windows VirtualAlloc rejected: allocation table exhausted guest_base=0x{x} length={d}", .{ guest_base, allocation_length });
    return false;
}

pub fn releaseWindowsVirtualAllocation(self: *ElfState, guest_base: u64, requested_length: u64, allocation_type: u64) bool {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    const release_type: u64 = 0x8000; // MEM_RELEASE
    if ((allocation_type & release_type) == 0) return windowsGuestRangeContains(self, guest_base, requested_length);
    // `VirtualAlloc(NULL, ...)` is served from the guest heap, so its
    // MEM_RELEASE has to reach the heap too. It used to fail here with
    // ERROR_INVALID_ADDRESS and every such block stayed live for the run:
    // the 1 GiB heap ran out during Halo 3's campaign load.
    if (requested_length == 0) {
        if (process_impl_guest_heap.findGuestHeapAllocation(self, guest_base)) |index| {
            const record = self.windows_heap_allocations[index];
            if (record.active) {
                if (!clearGuestPageProtectionAndReportInvalidation(self, guest_base, record.length)) {
                    process_impl_block_jit.blockJitTlbInvalidate(self, guest_base, record.length);
                }
                return process_impl_guest_heap.releaseGuestAllocation(self, guest_base);
            }
        }
    }
    for (self.windows_virtual_allocations[0..self.windows_virtual_allocation_count], 0..) |*allocation, allocation_index| {
        if (allocation.backing == null or allocation.guest_base != guest_base) continue;
        const expected_length = if (requested_length == 0) allocation.length else requested_length;
        if (requested_length != 0 and expected_length > allocation.length) return false;
        self.windows_mapped_ranges.remove(.virtual_allocation, allocation_index);
        process_impl_block_jit.blockJitTlbInvalidate(self, allocation.guest_base, allocation.length);
        process_impl_block_jit.blockJitDropMappedSource(self, .virtual_allocation, allocation_index);
        invalidateMappedDecodeCache(self);
        if (allocation.backing) |backing| __process_std.posix.munmap(backing);
        allocation.* = .{};
        trimWindowsVirtualAllocationCount(self);
        if (self.diagnose_abi) __process_log.info("PE64 Windows VirtualFree release: guest_base=0x{x} length={d}", .{ guest_base, expected_length });
        return true;
    }
    return false;
}

pub fn mapWindowsMemoryView(
    self: *ElfState,
    handle: u64,
    requested_base: u64,
    requested_length: u64,
    backing_offset: u64,
) ?u64 {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    const mapping_index = windowsMappingIndex(self, handle) orelse return null;
    const mapping = self.windows_file_mappings[mapping_index];
    if (backing_offset % @as(u64, @intCast(__process_std.heap.page_size_min)) != 0) return null;
    if (backing_offset >= mapping.length) return null;
    const length = if (requested_length == 0)
        mapping.length - backing_offset
    else
        requested_length;
    if (length == 0) return null;
    const end_offset = __process_std.math.add(u64, backing_offset, length) catch return null;
    if (end_offset > mapping.length) return null;

    var guest_base = requested_base;
    if (guest_base == 0) {
        const alignment: u64 = 0x1_0000;
        guest_base = (self.windows_next_memory_view_base + alignment - 1) & ~(alignment - 1);
        while (!windowsViewRangeIsFree(self, guest_base, length)) {
            guest_base = __process_std.math.add(u64, guest_base, alignment) catch return null;
        }
        self.windows_next_memory_view_base = __process_std.math.add(u64, guest_base, length) catch return null;
    } else if (guest_base % @as(u64, @intCast(__process_std.heap.page_size_min)) != 0) {
        return null;
    }
    if (!windowsViewRangeIsFree(self, guest_base, length)) return null;

    for (&self.windows_memory_views, 0..) |*view, view_index| {
        if (view.length == 0) {
            if (!indexWindowsMappedRange(self, .{
                .base = guest_base,
                .length = length,
                .kind = .memory_view,
                .slot = view_index,
            })) return null;
            view.* = .{
                .guest_base = guest_base,
                .length = length,
                .mapping_index = mapping_index,
                .backing_offset = backing_offset,
            };
            if (view_index >= self.windows_memory_view_count) {
                self.windows_memory_view_count = view_index + 1;
            }
            if (guest_base == 0xA000_0000 and backing_offset == 0 and
                length >= 0x0FFF_F000)
            {
                self.windows_code_cache_view = view_index;
                self.block_jit_code_cache_guest_low = guest_base;
                self.block_jit_code_cache_guest_high = guest_base + length;
            }
            const media_mapping = self.windows_file_mappings[mapping_index];
            if (media_mapping.media_authorized and self.windows_media_mapping_trace_events < 8) {
                self.windows_media_mapping_trace_events += 1;
                __process_log.info("PE64 Windows media view: mapping=0x{x} guest_base=0x{x} length={d} backing_offset=0x{x}", .{
                    handle,
                    guest_base,
                    length,
                    backing_offset,
                });
            }
            if (self.diagnose_abi) {
                __process_log.info("PE64 Windows MapViewOfFile: handle=0x{x} guest_base=0x{x} length={d} backing_offset=0x{x}", .{
                    handle,
                    guest_base,
                    length,
                    backing_offset,
                });
            }
            if (self.trace_windows_mappings and self.windows_mapping_trace_events < 16) {
                self.windows_mapping_trace_events += 1;
                __process_log.info("PE64 Windows mapping trace: view event={d} mapping_index={d} handle=0x{x} guest_base=0x{x} length={d} backing_offset=0x{x} backing=0x{x}", .{
                    self.windows_mapping_trace_events,
                    mapping_index,
                    handle,
                    guest_base,
                    length,
                    backing_offset,
                    @intFromPtr(mapping.backing.?.ptr),
                });
            }
            return guest_base;
        }
    }
    __process_log.err("PE64 Windows MapViewOfFile rejected: view table exhausted handle=0x{x} guest_base=0x{x} length={d}", .{ handle, guest_base, length });
    return null;
}

pub fn unmapWindowsMemoryView(self: *ElfState, guest_base: u64) bool {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    for (self.windows_memory_views[0..self.windows_memory_view_count], 0..) |*view, view_index| {
        if (view.length == 0 or view.guest_base != guest_base) continue;
        const mapping_index = view.mapping_index;
        self.windows_mapped_ranges.remove(.memory_view, view_index);
        process_impl_block_jit.blockJitTlbInvalidate(self, view.guest_base, view.length);
        process_impl_block_jit.blockJitDropMappedSource(self, .memory_view, mapping_index);
        invalidateMappedDecodeCache(self);
        if (self.windows_code_cache_view == view_index) {
            self.windows_code_cache_view = null;
            self.block_jit_code_cache_guest_low = 0;
            self.block_jit_code_cache_guest_high = 0;
        }
        view.* = .{};
        trimWindowsMemoryViewCount(self);
        releaseClosedWindowsMapping(self, mapping_index);
        if (self.diagnose_abi) __process_log.info("PE64 Windows UnmapViewOfFile: guest_base=0x{x}", .{guest_base});
        return true;
    }
    return false;
}

pub fn closeWindowsMemoryMapping(self: *ElfState, handle: u64) bool {
    var runtime_guard = process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    const mapping_index = windowsMappingIndex(self, handle) orelse return false;
    self.windows_file_mappings[mapping_index].closed = true;
    releaseClosedWindowsMapping(self, mapping_index);
    if (self.diagnose_abi) __process_log.info("PE64 Windows CloseHandle mapping: handle=0x{x} views_remaining={}", .{ handle, windowsMappingHasViews(self, mapping_index) });
    return true;
}

pub fn windowsMappedMemoryConst(self: *const ElfState, address: u64, count: u64) ?[]const u8 {
    if (nativeMemoryAlias(self, address, count)) |bytes| return bytes;
    if (windowsIndexedMemory(self, address, count)) |slice| return slice.bytes;
    if (count > __process_std.math.maxInt(usize)) return null;
    const end = __process_std.math.add(u64, address, count) catch return null;
    const count_usize: usize = @intCast(count);
    for (self.windows_memory_views[0..self.windows_memory_view_count]) |view| {
        if (view.length == 0 or address < view.guest_base) continue;
        const view_end = __process_std.math.add(u64, view.guest_base, view.length) catch continue;
        if (end > view_end) continue;
        const mapping = self.windows_file_mappings[view.mapping_index];
        const backing = mapping.backing orelse continue;
        const backing_offset = __process_std.math.add(u64, view.backing_offset, address - view.guest_base) catch return null;
        const offset: usize = __process_std.math.cast(usize, backing_offset) orelse return null;
        if (offset > backing.len or count_usize > backing.len - offset) return null;
        return backing[offset..][0..count_usize];
    }
    for (self.windows_virtual_allocations[0..self.windows_virtual_allocation_count]) |allocation| {
        if (allocation.length == 0 or address < allocation.guest_base) continue;
        const allocation_end = __process_std.math.add(u64, allocation.guest_base, allocation.length) catch continue;
        if (end > allocation_end) continue;
        const backing = allocation.backing orelse continue;
        const offset = __process_std.math.cast(usize, address - allocation.guest_base) orelse return null;
        if (offset > backing.len or count_usize > backing.len - offset) return null;
        return backing[offset..][0..count_usize];
    }
    return null;
}

pub fn windowsMappedCodeMemoryConst(self: *const ElfState, address: u64, count: u64) ?__process_WindowsMappedCodeSlice {
    if (count > __process_std.math.maxInt(usize)) return null;
    const end = __process_std.math.add(u64, address, count) catch return null;
    const count_usize: usize = @intCast(count);
    if (self.windows_code_cache_view) |index| {
        const view = self.windows_memory_views[index];
        const view_end = __process_std.math.add(u64, view.guest_base, view.length) catch 0;
        if (view.length != 0 and address >= view.guest_base and end <= view_end) {
            const mapping = self.windows_file_mappings[view.mapping_index];
            const backing = mapping.backing orelse return null;
            const backing_offset = __process_std.math.add(u64, view.backing_offset, address - view.guest_base) catch return null;
            const offset: usize = __process_std.math.cast(usize, backing_offset) orelse return null;
            if (offset > backing.len or count_usize > backing.len - offset) return null;
            return .{
                .bytes = backing[offset..][0..count_usize],
                .guest_base = view.guest_base,
                .length = view.length,
                .kind = .memory_view,
                .source_index = view.mapping_index,
                .generation = if (self.parallel_guest_execution) loadCodeGeneration(&mapping.code_generation) else mapping.code_generation,
                .backing_offset = backing_offset,
            };
        }
    }
    if (windowsIndexedMemory(self, address, count)) |slice| return slice;
    for (self.windows_memory_views[0..self.windows_memory_view_count]) |view| {
        if (view.length == 0 or address < view.guest_base) continue;
        const view_end = __process_std.math.add(u64, view.guest_base, view.length) catch continue;
        if (end > view_end) continue;
        const mapping = self.windows_file_mappings[view.mapping_index];
        const backing = mapping.backing orelse continue;
        const backing_offset = __process_std.math.add(u64, view.backing_offset, address - view.guest_base) catch return null;
        const offset: usize = __process_std.math.cast(usize, backing_offset) orelse return null;
        if (offset > backing.len or count_usize > backing.len - offset) return null;
        return .{
            .bytes = backing[offset..][0..count_usize],
            .guest_base = view.guest_base,
            .length = view.length,
            .kind = .memory_view,
            .source_index = view.mapping_index,
            .generation = if (self.parallel_guest_execution) loadCodeGeneration(&mapping.code_generation) else mapping.code_generation,
            .backing_offset = backing_offset,
        };
    }
    for (self.windows_virtual_allocations[0..self.windows_virtual_allocation_count], 0..) |allocation, allocation_index| {
        if (allocation.length == 0 or address < allocation.guest_base) continue;
        const allocation_end = __process_std.math.add(u64, allocation.guest_base, allocation.length) catch continue;
        if (end > allocation_end) continue;
        const backing = allocation.backing orelse continue;
        const offset = __process_std.math.cast(usize, address - allocation.guest_base) orelse return null;
        if (offset > backing.len or count_usize > backing.len - offset) return null;
        return .{
            .bytes = backing[offset..][0..count_usize],
            .guest_base = allocation.guest_base,
            .length = allocation.length,
            .kind = .virtual_allocation,
            .source_index = allocation_index,
            .generation = if (self.parallel_guest_execution) loadCodeGeneration(&allocation.code_generation) else allocation.code_generation,
            .backing_offset = offset,
        };
    }
    return null;
}

pub fn windowsMappedMemory(self: *ElfState, address: u64, count: u64) ?[]u8 {
    if (nativeMemoryAlias(self, address, count)) |bytes| return bytes;
    if (windowsIndexedMemory(self, address, count)) |slice| return @constCast(slice.bytes);
    if (count > __process_std.math.maxInt(usize)) return null;
    const end = __process_std.math.add(u64, address, count) catch return null;
    const count_usize: usize = @intCast(count);
    for (self.windows_memory_views[0..self.windows_memory_view_count]) |view| {
        if (view.length == 0 or address < view.guest_base) continue;
        const view_end = __process_std.math.add(u64, view.guest_base, view.length) catch continue;
        if (end > view_end) continue;
        const mapping = self.windows_file_mappings[view.mapping_index];
        const backing = mapping.backing orelse continue;
        const backing_offset = __process_std.math.add(u64, view.backing_offset, address - view.guest_base) catch return null;
        const offset: usize = __process_std.math.cast(usize, backing_offset) orelse return null;
        if (offset > backing.len or count_usize > backing.len - offset) return null;
        return backing[offset..][0..count_usize];
    }
    for (self.windows_virtual_allocations[0..self.windows_virtual_allocation_count]) |allocation| {
        if (allocation.length == 0 or address < allocation.guest_base) continue;
        const allocation_end = __process_std.math.add(u64, allocation.guest_base, allocation.length) catch continue;
        if (end > allocation_end) continue;
        const backing = allocation.backing orelse continue;
        const offset = __process_std.math.cast(usize, address - allocation.guest_base) orelse return null;
        if (offset > backing.len or count_usize > backing.len - offset) return null;
        return backing[offset..][0..count_usize];
    }
    return null;
}

pub fn bumpWindowsMappedCodeGeneration(self: *ElfState, address: u64, count: u64) void {
    if (count == 0) return;
    // Mapped generated code is decoded from its backing slice. A queued
    // self-modifying write must reach that slice before the generation
    // advances or the next decode could refill from stale bytes.
    __process_tso_memory.flushActiveStoreBufferFor(.code_write);
    if (self.windows_mapped_ranges.find(address, count)) |range| {
        const generation = switch (range.kind) {
            .memory_view => &self.windows_file_mappings[self.windows_memory_views[range.slot].mapping_index].code_generation,
            .virtual_allocation => &self.windows_virtual_allocations[range.slot].code_generation,
        };
        switch (range.kind) {
            .memory_view => {
                const view = self.windows_memory_views[range.slot];
                bumpCodePageGenerations(self, .memory_view, view.mapping_index, view.backing_offset +% (address - range.base), count);
            },
            .virtual_allocation => bumpCodePageGenerations(self, .virtual_allocation, range.slot, address - range.base, count),
        }
        if (self.parallel_guest_execution) {
            bumpCodeGenerationShared(self, generation);
            return;
        }
        if (generation.* == __process_std.math.maxInt(u64)) {
            invalidateMappedDecodeCache(self);
            process_impl_block_jit.blockJitDropAllMapped(self);
            generation.* = 1;
        } else generation.* += 1;
        return;
    }
    const end = __process_std.math.add(u64, address, count) catch return;
    for (self.windows_memory_views[0..self.windows_memory_view_count]) |view| {
        if (view.length == 0 or address < view.guest_base) continue;
        const view_end = __process_std.math.add(u64, view.guest_base, view.length) catch continue;
        if (end > view_end) continue;
        bumpCodePageGenerations(self, .memory_view, view.mapping_index, view.backing_offset +% (address - view.guest_base), count);
        if (self.parallel_guest_execution) {
            bumpCodeGenerationShared(self, &self.windows_file_mappings[view.mapping_index].code_generation);
        } else {
            self.windows_file_mappings[view.mapping_index].code_generation +|= 1;
        }
        return;
    }
    for (self.windows_virtual_allocations[0..self.windows_virtual_allocation_count], 0..) |*allocation, allocation_index| {
        if (allocation.length == 0 or address < allocation.guest_base) continue;
        const allocation_end = __process_std.math.add(u64, allocation.guest_base, allocation.length) catch continue;
        if (end > allocation_end) continue;
        bumpCodePageGenerations(self, .virtual_allocation, allocation_index, address - allocation.guest_base, count);
        if (self.parallel_guest_execution) {
            bumpCodeGenerationShared(self, &allocation.code_generation);
        } else {
            allocation.code_generation +|= 1;
        }
        return;
    }
}

pub fn codePageGenerationSlot(kind: __process_mapped_ranges.Kind, source_index: usize, page: u64) usize {
    const source: u64 = (@as(u64, @intCast(source_index)) << 1) | @intFromEnum(kind);
    const scatter: u6 = comptime @intCast(64 - @as(u32, __process_CODE_PAGE_GENERATION_BITS));
    const start = (source +% 1) *% 0x9E37_79B9_7F4A_7C15 >> scatter;
    return @intCast((start +% page) & (__process_CODE_PAGE_GENERATION_SLOTS - 1));
}

pub fn codePageGenerationWord(self: *ElfState, kind: __process_mapped_ranges.Kind, source_index: usize, backing_offset: u64) ?*u64 {
    if (self.code_page_generations.len == 0) return null;
    return &self.code_page_generations[codePageGenerationSlot(kind, source_index, backing_offset >> __process_CODE_PAGE_SHIFT)];
}

pub fn configureBlockJitMemoryVerify(self: *ElfState) void {
    self.block_jit_verify_memory = __process_envFlag("ROSETTE_BLOCK_JIT_VERIFY_MEMORY");
}

pub fn ensureImportHistogram(self: *ElfState) void {
    if (self.windows_import_histogram != null or self.parallel_guest_execution) return;
    const histogram = self.allocator.create(__process_import_histogram.Histogram) catch return;
    histogram.* = .{};
    self.windows_import_histogram = histogram;
}

pub fn reportImportHistogram(self: *const ElfState) void {
    const histogram = self.windows_import_histogram orelse return;
    const total = histogram.totalCalls();
    if (total == 0) return;
    __process_log.info("PE64 IMPORT HISTOGRAM: calls={d} overflow={d}; every Windows import reaching the import dispatcher, by name, busiest first; mean_ns is one call in {d} timed and includes any wait the import made", .{
        total,
        histogram.overflow.load(.monotonic),
        __process_import_histogram.sample_period,
    });
    var storage: [24]*const __process_import_histogram.Entry = undefined;
    for (histogram.top(&storage), 1..) |entry, rank| {
        const calls = entry.calls.load(.monotonic);
        const mean = entry.meanNs();
        __process_log.info("PE64 IMPORT HISTOGRAM:   rank={d} import={s}!{s} calls={d} share={d}% mean_ns={d} estimated_ms={d} samples={d} sampled_max_ns={d}", .{
            rank,
            entry.dll(),
            entry.name(),
            calls,
            calls *| 100 / total,
            mean,
            calls *| mean / __process_std.time.ns_per_ms,
            entry.samples.load(.monotonic),
            entry.sampled_max_ns.load(.monotonic),
        });
    }
    for (&histogram.entries) |*entry| {
        const calls = entry.calls.load(.monotonic);
        if (calls == 0) continue;
        __process_log.info("PE64 IMPORT TIMING: import={s}!{s} calls={d} samples={d} sampled_ns={d} sampled_max_ns={d} sample_period={d}; elapsed includes waits; maximum covers timed samples only", .{
            entry.dll(), entry.name(), calls, entry.samples.load(.monotonic), entry.sampled_ns.load(.monotonic), entry.sampled_max_ns.load(.monotonic), __process_import_histogram.sample_period,
        });
    }
}

pub fn ensureCodePageGenerations(self: *ElfState) void {
    if (self.code_page_generations.len != 0 or self.parallel_guest_execution) return;
    const table = self.allocator.alloc(u64, __process_CODE_PAGE_GENERATION_SLOTS) catch return;
    @memset(table, 0);
    self.code_page_generations = table;
}

pub fn bumpCodePageGenerations(self: *ElfState, kind: __process_mapped_ranges.Kind, source_index: usize, backing_offset: u64, count: u64) void {
    const table = self.code_page_generations;
    if (table.len == 0 or count == 0) return;
    const first = (backing_offset >> __process_CODE_PAGE_SHIFT) -| 1;
    const last = (backing_offset +| (count - 1)) >> __process_CODE_PAGE_SHIFT;
    if (last - first >= table.len) {
        // A write wider than the table touches every word anyway.
        for (table) |*word| bumpCodePageWord(self, word);
        return;
    }
    var page = first;
    while (page <= last) : (page += 1) bumpCodePageWord(self, &table[codePageGenerationSlot(kind, source_index, page)]);
}

pub fn bumpCodePageWord(self: *const ElfState, word: *u64) void {
    if (self.parallel_guest_execution) {
        _ = @atomicRmw(u64, word, .Add, 1, .release);
    } else {
        word.* +%= 1;
    }
}

pub fn bumpCodeGenerationShared(self: *const ElfState, generation: *u64) void {
    _ = self;
    _ = @atomicRmw(u64, generation, .Add, 1, .release);
}

pub fn loadCodeGeneration(generation: *const u64) u64 {
    return @atomicLoad(u64, generation, .acquire);
}

pub fn invalidateMappedDecodeCache(self: *ElfState) void {
    if (self.parallel_guest_execution) return;
    for (self.decode_cache) |*entry| if (entry.mapped_source) {
        entry.valid = false;
        entry.last_used = 0;
    };
    for (self.decode_cache_victims) |*entry| if (entry.mapped_source) {
        entry.valid = false;
    };
}

pub fn indexWindowsMappedRange(self: *ElfState, range: __process_mapped_ranges.Range) bool {
    if (!self.windows_mapped_ranges.insert(range)) {
        __process_log.err("PE64 mapped range index refused: base=0x{x} length={d} kind={s} slot={d}; no backing was published", .{ range.base, range.length, @tagName(range.kind), range.slot });
        return false;
    }
    return true;
}

pub fn windowsIndexedMemory(self: *const ElfState, address: u64, count: u64) ?__process_WindowsMappedCodeSlice {
    const range = self.windows_mapped_ranges.find(address, count) orelse return null;
    switch (range.kind) {
        .memory_view => {
            const view = self.windows_memory_views[range.slot];
            if (view.guest_base != range.base or view.length != range.length) return null;
            const mapping = self.windows_file_mappings[view.mapping_index];
            const backing = mapping.backing orelse return null;
            const offset = __process_std.math.add(u64, view.backing_offset, address - range.base) catch return null;
            if (offset > backing.len or count > backing.len - offset) return null;
            return .{ .bytes = backing[@intCast(offset)..][0..@intCast(count)], .guest_base = range.base, .length = range.length, .kind = .memory_view, .source_index = view.mapping_index, .generation = if (self.parallel_guest_execution) 0 else mapping.code_generation, .backing_offset = offset };
        },
        .virtual_allocation => {
            const allocation = self.windows_virtual_allocations[range.slot];
            if (allocation.guest_base != range.base or allocation.length != range.length) return null;
            const backing = allocation.backing orelse return null;
            const offset = address - range.base;
            if (offset > backing.len or count > backing.len - offset) return null;
            return .{ .bytes = backing[@intCast(offset)..][0..@intCast(count)], .guest_base = range.base, .length = range.length, .kind = .virtual_allocation, .source_index = range.slot, .generation = if (self.parallel_guest_execution) 0 else allocation.code_generation, .backing_offset = offset };
        },
    }
}

pub fn bumpWindowsImageCodeGeneration(self: *ElfState, address: u64, count: u64) void {
    // The bounding box can span non-executable gaps (including the
    // import table). Publish and trace only a write that overlaps an
    // actual executable PE range; otherwise ordinary IAT/data updates
    // would be mislabeled as code writes and needlessly flush a pending
    // store buffer.
    if (!windowsImageRangeOverlapsCode(self, address, count)) return;
    __process_tso_memory.flushActiveStoreBufferFor(.code_write);
    traceWindowsExecutableImageWrite(self, address, count);
    if (self.parallel_guest_execution) {
        bumpCodeGenerationShared(self, &self.windows_image_code_generation);
        return;
    }
    // Saturation would make a later write indistinguishable from the
    // previous one.  This is practically unreachable, but clearing
    // the tiny cache makes the invariant explicit even in a fuzzed
    // or very long-lived PE session.
    if (self.windows_image_code_generation == __process_std.math.maxInt(u64)) {
        self.windows_image_code_generation = 1;
        for (self.decode_cache) |*entry| {
            entry.valid = false;
            entry.last_used = 0;
        }
        process_impl_block_jit.blockJitDropAll(self);
    } else {
        self.windows_image_code_generation += 1;
    }
}

pub inline fn windowsImageRangeOverlapsCode(self: *const ElfState, address: u64, count: u64) bool {
    if (count == 0 or self.windows_executable_range_count == 0) return false;
    if (!self.windows_executable_box.overlaps(address, count)) return false;
    const end = __process_std.math.add(u64, address, count) catch return false;
    for (self.windows_executable_ranges[0..self.windows_executable_range_count]) |range| {
        if (range.length == 0) continue;
        const range_end = __process_std.math.add(u64, range.guest_base, range.length) catch continue;
        if (address < range_end and end > range.guest_base) return true;
    }
    return false;
}

pub fn traceWindowsExecutableImageWrite(self: *ElfState, address: u64, count: u64) void {
    if (comptime @import("builtin").is_test) return;
    const event = self.windows_executable_image_write_events.fetchAdd(1, .monotonic);
    if (event >= 16) return;

    var bytes: [16]u8 = @splat(0);
    var captured: usize = 0;
    if (addrToOffset(self, address)) |offset| {
        if (offset < self.mem.len) {
            const remaining: u64 = @intCast(self.mem.len - offset);
            captured = @intCast(@min(@as(u64, bytes.len), @min(count, remaining)));
            if (captured != 0) __process_tso_memory.copyBackingCoordinated(bytes[0..captured], self.mem[offset..][0..captured]);
        }
    }
    __process_log.warn("PE64 EXECUTABLE IMAGE WRITE TRACE: event={d} address=0x{x} width={d} writer_rip=0x{x} writer_op={s}/{d} thread=0x{x} thread_id=0x{x} slot={?d} steps={d} image_generation={d} pending_stores={d} phase=after_code_write_flush_or_before_mutable_borrow bytes={any}", .{
        event + 1,
        address,
        count,
        process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
        process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
        process_impl_lifecycle.currentWindowsThreadId(self),
        process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*,
        process_impl_lifecycle.observedExecutionSteps(self),
        self.windows_image_code_generation,
        __process_tso_memory.activePendingStores(),
        bytes[0..captured],
    });
}

pub fn windowsImageCodeGenerationFor(self: *ElfState, address: u64, count: usize) ?u64 {
    if (!self.windows_runtime_enabled or self.windows_executable_range_count == 0) return null;
    const end = __process_std.math.add(u64, address, @as(u64, @intCast(count))) catch return null;
    // Straight-line code stays inside one section, so the range that
    // answered the previous fetch answers this one almost always.
    const hint = self.windows_executable_range_hint.load(.monotonic);
    if (hint < self.windows_executable_range_count) {
        const range = self.windows_executable_ranges[hint];
        if (range.length != 0 and address >= range.guest_base) {
            if (__process_std.math.add(u64, range.guest_base, range.length)) |range_end| {
                if (end <= range_end) return loadCodeGeneration(&self.windows_image_code_generation);
            } else |_| {}
        }
    }
    for (self.windows_executable_ranges[0..self.windows_executable_range_count], 0..) |range, index| {
        if (range.length == 0 or address < range.guest_base) continue;
        const range_end = __process_std.math.add(u64, range.guest_base, range.length) catch continue;
        if (end <= range_end) {
            // A hint: several executors may race to write it, and any
            // value it holds is re-checked before use.
            self.windows_executable_range_hint.store(index, .monotonic);
            return loadCodeGeneration(&self.windows_image_code_generation);
        }
    }
    return null;
}

pub fn loadGuestScalar(self: *const ElfState, comptime T: type, bytes: []const u8) T {
    return if (self.parallel_guest_execution)
        __process_tso_memory.loadCoordinated(T, bytes)
    else
        __process_tso_memory.load(T, bytes);
}

pub fn storeGuestScalar(self: *const ElfState, comptime T: type, bytes: []u8, value: T) void {
    if (self.parallel_guest_execution) {
        __process_tso_memory.storeCoordinated(T, bytes, value);
    } else {
        __process_tso_memory.store(T, bytes, value);
    }
}

pub fn guestMemoryClass(self: *const ElfState, address: u64, width: u8, is_write: bool) __process_tso_memory_policy.MemoryClass {
    const fault_routed = self.guest_page_protection.isActive() and
        self.guest_page_protection.faults(address, width, is_write);
    const device_backed = nativeMemoryAlias(self, address, width) != null;
    return __process_tso_memory_policy.classify(device_backed, fault_routed);
}

pub fn guestMemoryRangeClass(self: *const ElfState, address: u64, count: u64, is_write: bool) __process_tso_memory_policy.MemoryClass {
    if (count == 0) return .ordinary_ram;
    const end = __process_std.math.add(u64, address, count) catch return .fault_routed;
    if (self.guest_page_protection.isActive()) {
        var page = address & ~(__process_guest_page_protection.page_size - 1);
        while (page < end) {
            if (self.guest_page_protection.faults(page, 1, is_write)) return .fault_routed;
            page = __process_std.math.add(u64, page, __process_guest_page_protection.page_size) catch return .fault_routed;
        }
    }
    if (nativeMemoryAlias(self, address, count) != null) return .device_backed;
    return .ordinary_ram;
}

pub fn memoryClassBoundary(class: __process_tso_memory_policy.MemoryClass) __process_tso_memory.Boundary {
    return switch (class) {
        .ordinary_ram => .unattributed,
        .device_backed => .device_access,
        .fault_routed => .fault_routed_access,
    };
}

pub fn loadGuestScalarAt(self: *const ElfState, comptime T: type, address: u64, bytes: []const u8) T {
    const class = guestMemoryClass(self, address, @sizeOf(T), false);
    if (!__process_tso_memory_policy.bypassStoreBuffer(class)) return loadGuestScalar(self, T, bytes);
    return __process_tso_memory.loadUnbuffered(
        T,
        bytes,
        __process_tso_memory_policy.requiresCoordinator(class, self.parallel_guest_execution),
        memoryClassBoundary(class),
    );
}

pub fn storeGuestScalarAt(self: *const ElfState, comptime T: type, address: u64, bytes: []u8, value: T, non_temporal: bool) void {
    const class = guestMemoryClass(self, address, @sizeOf(T), true);
    if (!__process_tso_memory_policy.bypassStoreBufferForStore(class, non_temporal)) {
        storeGuestScalar(self, T, bytes, value);
        return;
    }
    const boundary = if (__process_tso_memory_policy.bypassStoreBuffer(class))
        memoryClassBoundary(class)
    else
        .non_temporal_store;
    __process_tso_memory.storeUnbuffered(
        T,
        bytes,
        value,
        __process_tso_memory_policy.requiresCoordinator(class, self.parallel_guest_execution),
        boundary,
    );
}

pub fn fillGuestBacking(self: *const ElfState, destination: []u8, byte: u8) void {
    if (self.parallel_guest_execution) {
        __process_tso_memory.fillCoordinated(destination, byte);
    } else {
        __process_tso_memory.fill(destination, byte);
    }
}

pub fn copyGuestBacking(self: *const ElfState, destination: []u8, source: []const u8) void {
    if (self.parallel_guest_execution) {
        __process_tso_memory.copyCoordinated(destination, source);
    } else {
        __process_tso_memory.copy(destination, source);
    }
}

pub fn copyGuestBackingForClass(
    self: *const ElfState,
    destination: []u8,
    source: []const u8,
    class: __process_tso_memory_policy.MemoryClass,
) void {
    if (!__process_tso_memory_policy.bypassStoreBuffer(class)) {
        copyGuestBacking(self, destination, source);
        return;
    }
    __process_tso_memory.flushActiveStoreBufferFor(memoryClassBoundary(class));
    const previous = __process_tso_memory.setActiveStoreBuffer(null);
    defer _ = __process_tso_memory.setActiveStoreBuffer(previous);
    __process_tso_memory.copyCoordinated(destination, source);
}

pub fn fillGuestBackingForClass(
    self: *const ElfState,
    destination: []u8,
    byte: u8,
    class: __process_tso_memory_policy.MemoryClass,
) void {
    if (!__process_tso_memory_policy.bypassStoreBuffer(class)) {
        fillGuestBacking(self, destination, byte);
        return;
    }
    __process_tso_memory.flushActiveStoreBufferFor(memoryClassBoundary(class));
    const previous = __process_tso_memory.setActiveStoreBuffer(null);
    defer _ = __process_tso_memory.setActiveStoreBuffer(previous);
    __process_tso_memory.fillCoordinated(destination, byte);
}

pub fn snapshotGuestBacking(self: *const ElfState, destination: []u8, source: []const u8) void {
    if (self.parallel_guest_execution) {
        __process_tso_memory.copyInCoordinated(destination, source);
    } else {
        __process_tso_memory.copyIn(destination, source);
    }
}

pub fn read8(self: *const ElfState, vaddr: u64) u8 {
    const value = read8Backing(self, vaddr);
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| return journal.forwardScalar(u8, vaddr, value);
    return value;
}

pub fn read8Backing(self: *const ElfState, vaddr: u64) u8 {
    if (addrToOffset(self, vaddr)) |off| return loadGuestScalarAt(self, u8, vaddr, self.mem[off..]);
    if (windowsMappedMemoryConst(self, vaddr, 1)) |bytes| return loadGuestScalarAt(self, u8, vaddr, bytes);
    return unmappedGuestRead(self, u8, vaddr);
}

pub fn unmappedGuestRead(self: *const ElfState, comptime T: type, vaddr: u64) T {
    if (!self.windows_runtime_enabled) return 0;
    if (!__process_kuser_shared.contains(vaddr) or !__process_kuser_shared.contains(vaddr +% (@sizeOf(T) - 1))) {
        @constCast(&self.unmapped_read_census).note(vaddr, process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*);
        return 0;
    }
    _ = @constCast(&self.kuser_shared_reads).fetchAdd(1, .monotonic);
    return __process_kuser_shared.readScalar(T, vaddr, kuserClock(self));
}

pub fn kuserClock(self: *const ElfState) __process_kuser_shared.Clock {
    const ticks = if (self.guest_clock.source == .retired_instructions)
        process_impl_lifecycle.windowsGuestClockTicks(self)
    else
        self.guest_clock_published_ticks.load();
    return .{
        .interrupt_100ns = ticks *% (10_000_000 / __process_WINDOWS_GUEST_CLOCK_HZ),
        .system_filetime = process_impl_lifecycle.windowsGuestPublishedFileTime(self),
        .tick_ms = ticks / (__process_WINDOWS_GUEST_CLOCK_HZ / 1000),
        .qpc_hz = __process_WINDOWS_GUEST_CLOCK_HZ,
    };
}

pub fn read16(self: *const ElfState, vaddr: u64) u16 {
    const value = read16Backing(self, vaddr);
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| return journal.forwardScalar(u16, vaddr, value);
    return value;
}

pub fn read16Backing(self: *const ElfState, vaddr: u64) u16 {
    if (addrToOffset(self, vaddr)) |off| {
        if (off + 2 <= self.mem.len) return loadGuestScalarAt(self, u16, vaddr, self.mem[off..]);
    } else if (windowsMappedMemoryConst(self, vaddr, 2)) |bytes| {
        return loadGuestScalarAt(self, u16, vaddr, bytes);
    }
    return unmappedGuestRead(self, u16, vaddr);
}

pub fn read32(self: *const ElfState, vaddr: u64) u32 {
    const value = read32Backing(self, vaddr);
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| return journal.forwardScalar(u32, vaddr, value);
    return value;
}

pub fn read32Backing(self: *const ElfState, vaddr: u64) u32 {
    if (addrToOffset(self, vaddr)) |off| {
        if (off + 4 <= self.mem.len) return loadGuestScalarAt(self, u32, vaddr, self.mem[off..]);
    } else if (windowsMappedMemoryConst(self, vaddr, 4)) |bytes| {
        return loadGuestScalarAt(self, u32, vaddr, bytes);
    }
    return unmappedGuestRead(self, u32, vaddr);
}

pub fn read64(self: *const ElfState, vaddr: u64) u64 {
    const value = read64Backing(self, vaddr);
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| return journal.forwardScalar(u64, vaddr, value);
    return value;
}

pub fn read64Backing(self: *const ElfState, vaddr: u64) u64 {
    if (addrToOffset(self, vaddr)) |off| {
        if (off + 8 <= self.mem.len) return loadGuestScalarAt(self, u64, vaddr, self.mem[off..]);
    } else if (windowsMappedMemoryConst(self, vaddr, 8)) |bytes| {
        return loadGuestScalarAt(self, u64, vaddr, bytes);
    }
    return unmappedGuestRead(self, u64, vaddr);
}

pub fn write8(self: *ElfState, vaddr: u64, val: u8) void {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| return journal.storeScalar(u8, vaddr, val);
    traceGuestWrite(self, vaddr, 1, val);
    if (addrToOffset(self, vaddr)) |off| {
        if (off < self.mem.len) {
            storeGuestScalarAt(self, u8, vaddr, self.mem[off..], val, false);
            bumpWindowsImageCodeGeneration(self, vaddr, 1);
        }
    } else if (windowsMappedMemory(self, vaddr, 1)) |bytes| {
        storeGuestScalarAt(self, u8, vaddr, bytes, val, false);
        bumpWindowsMappedCodeGeneration(self, vaddr, 1);
    }
}

pub fn write16(self: *ElfState, vaddr: u64, val: u16) void {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| return journal.storeScalar(u16, vaddr, val);
    traceGuestWrite(self, vaddr, 2, val);
    if (addrToOffset(self, vaddr)) |off| {
        if (off + 2 <= self.mem.len) {
            storeGuestScalarAt(self, u16, vaddr, self.mem[off..], val, false);
            bumpWindowsImageCodeGeneration(self, vaddr, 2);
        }
    } else if (windowsMappedMemory(self, vaddr, 2)) |bytes| {
        storeGuestScalarAt(self, u16, vaddr, bytes, val, false);
        bumpWindowsMappedCodeGeneration(self, vaddr, 2);
    }
}

pub fn write32(self: *ElfState, vaddr: u64, val: u32) void {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| return journal.storeScalar(u32, vaddr, val);
    traceGuestWrite(self, vaddr, 4, val);
    traceWindowsMappedWrite(self, vaddr, 4, val);
    if (addrToOffset(self, vaddr)) |off| {
        if (off + 4 <= self.mem.len) {
            storeGuestScalarAt(self, u32, vaddr, self.mem[off..], val, false);
            bumpWindowsImageCodeGeneration(self, vaddr, 4);
        }
    } else if (windowsMappedMemory(self, vaddr, 4)) |bytes| {
        storeGuestScalarAt(self, u32, vaddr, bytes, val, false);
        bumpWindowsMappedCodeGeneration(self, vaddr, 4);
    }
}

pub fn write64(self: *ElfState, vaddr: u64, val: u64) void {
    if (process_impl_block_jit.activeVerifyJournal(self)) |journal| return journal.storeScalar(u64, vaddr, val);
    traceGuestWrite(self, vaddr, 8, val);
    traceWindowsMappedWrite(self, vaddr, 8, val);
    if (addrToOffset(self, vaddr)) |off| {
        if (off + 8 <= self.mem.len) {
            storeGuestScalarAt(self, u64, vaddr, self.mem[off..], val, false);
            bumpWindowsImageCodeGeneration(self, vaddr, 8);
        }
    } else if (windowsMappedMemory(self, vaddr, 8)) |bytes| {
        storeGuestScalarAt(self, u64, vaddr, bytes, val, false);
        bumpWindowsMappedCodeGeneration(self, vaddr, 8);
    }
}

pub inline fn traceWindowsMappedWrite(self: *ElfState, address: u64, width: u8, value: u64) void {
    if (!self.trace_windows_memory) return;
    traceWindowsMappedWriteEnabled(self, address, width, value);
}

pub fn windowsMemoryTraceLive(self: *ElfState) bool {
    if (!self.trace_windows_memory or
        self.windows_memory_trace_events.load(.monotonic) >= __state_windows_memory_trace_budget or
        self.windows_memory_trace_step_closed.load(.monotonic)) return false;
    if (process_impl_lifecycle.observedExecutionSteps(self) >= __state_windows_memory_trace_step_budget) {
        self.windows_memory_trace_step_closed.store(true, .monotonic);
        return false;
    }
    return true;
}

pub fn claimWindowsMemoryTraceEvent(self: *ElfState) bool {
    var observed = self.windows_memory_trace_events.load(.monotonic);
    while (observed < __state_windows_memory_trace_budget) {
        if (self.windows_memory_trace_events.cmpxchgWeak(observed, observed + 1, .monotonic, .monotonic)) |actual| {
            observed = actual;
        } else {
            return true;
        }
    }
    return false;
}

pub fn traceWindowsMappedWriteEnabled(self: *ElfState, address: u64, width: u8, value: u64) void {
    if (self.windows_memory_trace_step_closed.load(.monotonic)) return;
    if (address < __state_windows_memory_trace_floor or addrToOffset(self, address) != null) return;
    if (!self.trace_windows_memory or
        self.windows_memory_trace_events.load(.monotonic) >= __state_windows_memory_trace_budget or
        self.windows_memory_trace_step_closed.load(.monotonic)) return;
    const observed_step = process_impl_lifecycle.observedExecutionSteps(self);
    if (observed_step >= __state_windows_memory_trace_step_budget) {
        self.windows_memory_trace_step_closed.store(true, .monotonic);
        return;
    }
    if (!claimWindowsMemoryTraceEvent(self)) return;
    const mapped = windowsMappedMemoryConst(self, address, width) != null;
    __process_log.info("PE64 Windows mapped write: address=0x{x} width={d} value=0x{x} mapped={} guest_range={} rip=0x{x} op={s} step={d}", .{
        address,
        width,
        value,
        mapped,
        windowsGuestRangeContains(self, address, width),
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        observed_step,
    });
}

pub fn reportWindowsMemoryTrace(self: *ElfState) void {
    const events = self.windows_memory_trace_events.load(.monotonic);
    const steps = process_impl_lifecycle.observedExecutionSteps(self);
    const state: []const u8 = if (!self.trace_windows_memory)
        "disabled"
    else if (events >= __state_windows_memory_trace_budget)
        "event_budget"
    else if (steps >= __state_windows_memory_trace_step_budget or self.windows_memory_trace_step_closed.load(.monotonic))
        "step_budget"
    else
        "live_at_exit";
    __process_log.info("PE64 WINDOWS MAPPED WRITE TRACE: enabled={} events={d}/{d} guest_steps={d}/{d} state={s}; trace is bounded by eligible write count and early-run guest progress", .{
        self.trace_windows_memory,
        events,
        __state_windows_memory_trace_budget,
        steps,
        __state_windows_memory_trace_step_budget,
        state,
    });
}

pub inline fn traceGuestWrite(self: *const ElfState, vaddr: u64, width: u8, value: u64) void {
    if (self.trace_write_address == null and !self.spin_watch.armed()) return;
    traceGuestWriteWatched(self, vaddr, width, value);
}

pub fn traceGuestWriteWatched(self: *const ElfState, vaddr: u64, width: u8, value: u64) void {
    if (self.spin_watch.armed()) process_impl_lifecycle.noteSpinWatchWrite(self, vaddr, width, value, "store");
    const watch = self.trace_write_address orelse return;
    const write_end = vaddr +| @as(u64, width);
    const watch_end = watch +| 8;
    if (vaddr >= watch_end or write_end <= watch) return;
    if (comptime @import("builtin").is_test) return;

    __process_log.info("trace guest write address=0x{x} width={d} value=0x{x} watch=0x{x} rip=0x{x} op={s} len={d} rsp=0x{x} ret=0x{x}", .{
        vaddr,
        width,
        value,
        watch,
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
        process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
        read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
    });
}

pub fn push(self: *ElfState, val: u64) void {
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp -|= 8;
    const address = process_impl_lifecycle.guestContextField(self, "regs").*.rsp +% __process_x64_decoder.segmentBase(&process_impl_lifecycle.guestContextField(self, "regs").*, .ss, .long64);
    write64(self, address, val);
}

pub fn pop(self: *ElfState) u64 {
    const address = process_impl_lifecycle.guestContextField(self, "regs").*.rsp +% __process_x64_decoder.segmentBase(&process_impl_lifecycle.guestContextField(self, "regs").*, .ss, .long64);
    const val = read64(self, address);
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp +|= 8;
    return val;
}

pub fn completeWindowsQsortWithoutFrame(self: *ElfState, direct_return_rip: ?u64) void {
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = if (direct_return_rip) |rip| rip else pop(self);
}

pub fn failWindowsQsort(self: *ElfState, direct_return_rip: ?u64, detail: []const u8) void {
    if (comptime !@import("builtin").is_test) {
        __process_log.warn("Windows qsort refused: {s} base=0x{x} nmemb={d} size={d} comparator=0x{x} rip=0x{x}", .{
            detail,
            process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
            process_impl_lifecycle.guestContextField(self, "regs").*.r8,
            process_impl_lifecycle.guestContextField(self, "regs").*.r9,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        });
    }
    completeWindowsQsortWithoutFrame(self, direct_return_rip);
}

pub fn finishWindowsQsort(self: *ElfState) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_qsort_frame_count").* == 0) {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        __process_log.err("Windows qsort callback completed without an active sort frame rip=0x{x}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rip});
        return;
    }
    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_qsort_frame_count").* - 1;
    const frame = process_impl_lifecycle.guestContextField(self, "windows_qsort_frames").*[frame_index];
    process_impl_lifecycle.guestContextField(self, "windows_qsort_frame_count").* = frame_index;
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = if (frame.return_is_direct) frame.return_rip else pop(self);
    if (self.diagnose_abi) {
        __process_log.info("Windows qsort complete elements={d} element_size={d} comparisons={d} continuation=0x{x}", .{
            frame.nmemb,
            frame.element_size,
            frame.callback_count,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        });
    }
}

pub fn continueWindowsQsort(self: *ElfState) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_qsort_frame_count").* == 0) {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        __process_log.err("Windows qsort continuation has no active sort frame rip=0x{x}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rip});
        return;
    }

    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_qsort_frame_count").* - 1;
    const frame = &process_impl_lifecycle.guestContextField(self, "windows_qsort_frames").*[frame_index];
    if (frame.awaiting_comparison) {
        frame.awaiting_comparison = false;
        const comparison: i32 = @bitCast(@as(u32, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax)));
        if (comparison < 0) {
            const current_address = frame.base + frame.j * frame.element_size;
            const previous_address = frame.base + (frame.j - 1) * frame.element_size;
            const current = process_impl_execution.guestMemoryConst(self, current_address, frame.element_size) orelse {
                process_impl_lifecycle.markFaulted(self);
                self.exit_code = 127;
                self.termination_reason = .runtime_invariant_failure;
                process_impl_lifecycle.markTerminated(self);
                __process_log.err("Windows qsort comparator produced an invalid current element address=0x{x}", .{current_address});
                return;
            };
            const previous = process_impl_execution.guestMemoryConst(self, previous_address, frame.element_size) orelse {
                process_impl_lifecycle.markFaulted(self);
                self.exit_code = 127;
                self.termination_reason = .runtime_invariant_failure;
                process_impl_lifecycle.markTerminated(self);
                __process_log.err("Windows qsort comparator produced an invalid previous element address=0x{x}", .{previous_address});
                return;
            };
            const element_size: usize = @intCast(frame.element_size);
            snapshotGuestBacking(self, frame.scratch[0..element_size], current);
            const current_target = process_impl_execution.guestMemoryTsoWriteTarget(self, current_address, frame.element_size) orelse {
                failWindowsQsort(self, null, "current element became unmapped");
                return;
            };
            const previous_target = process_impl_execution.guestMemoryTsoWriteTarget(self, previous_address, frame.element_size) orelse {
                failWindowsQsort(self, null, "previous element became unmapped");
                return;
            };
            copyGuestBacking(self, current_target, previous);
            process_impl_execution.finishGuestMemoryTsoWrite(self, current_address, frame.element_size);
            copyGuestBacking(self, previous_target, frame.scratch[0..element_size]);
            process_impl_execution.finishGuestMemoryTsoWrite(self, previous_address, frame.element_size);
            if (frame.j > 1) {
                frame.j -= 1;
            } else {
                frame.i += 1;
                frame.j = frame.i;
            }
        } else {
            frame.i += 1;
            frame.j = frame.i;
        }
    }

    if (frame.i >= frame.nmemb) {
        finishWindowsQsort(self);
        return;
    }

    const left_address = frame.base + frame.j * frame.element_size;
    const right_address = frame.base + (frame.j - 1) * frame.element_size;
    frame.callback_count +|= 1;
    frame.awaiting_comparison = true;
    push(self, __process_x64_linux_runtime.SYNTHETIC_QSORT_RETURN);
    process_impl_lifecycle.guestContextField(self, "regs").*.rcx = left_address;
    process_impl_lifecycle.guestContextField(self, "regs").*.rdx = right_address;
    process_impl_lifecycle.guestContextField(self, "regs").*.r8 = 0;
    process_impl_lifecycle.guestContextField(self, "regs").*.r9 = 0;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = frame.comparator;
}

pub fn beginWindowsQsort(
    self: *ElfState,
    base: u64,
    nmemb: u64,
    element_size: u64,
    comparator: u64,
    direct_return_rip: ?u64,
) bool {
    if (nmemb <= 1) {
        completeWindowsQsortWithoutFrame(self, direct_return_rip);
        return true;
    }
    if (base == 0 or comparator == 0) {
        failWindowsQsort(self, direct_return_rip, "null base or comparator");
        return true;
    }
    if (element_size == 0 or element_size > __process_MAX_WINDOWS_QSORT_ELEMENT_BYTES) {
        failWindowsQsort(self, direct_return_rip, "element size exceeds bounded guest scratch storage");
        return true;
    }
    if (nmemb > __process_MAX_WINDOWS_QSORT_ELEMENTS) {
        failWindowsQsort(self, direct_return_rip, "element count exceeds bounded callback work");
        return true;
    }
    const byte_count = __process_std.math.mul(u64, nmemb, element_size) catch {
        failWindowsQsort(self, direct_return_rip, "element range overflows guest address width");
        return true;
    };
    _ = __process_std.math.add(u64, base, byte_count) catch {
        failWindowsQsort(self, direct_return_rip, "element range overflows guest address width");
        return true;
    };
    if (process_impl_execution.guestMemoryConst(self, base, byte_count) == null) {
        failWindowsQsort(self, direct_return_rip, "element range is outside guest memory");
        return true;
    }
    if (addrToOffset(self, comparator) == null) {
        failWindowsQsort(self, direct_return_rip, "comparator is outside the guest image");
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "windows_qsort_frame_count").* >= process_impl_lifecycle.guestContextField(self, "windows_qsort_frames").*.len) {
        failWindowsQsort(self, direct_return_rip, "nested qsort frame capacity exhausted");
        return true;
    }
    if (direct_return_rip == null and read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp) == 0) {
        failWindowsQsort(self, direct_return_rip, "caller continuation is null");
        return true;
    }

    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_qsort_frame_count").*;
    process_impl_lifecycle.guestContextField(self, "windows_qsort_frames").*[frame_index] = .{
        .base = base,
        .nmemb = nmemb,
        .element_size = element_size,
        .comparator = comparator,
        .return_rip = direct_return_rip orelse 0,
        .return_is_direct = direct_return_rip != null,
    };
    process_impl_lifecycle.guestContextField(self, "windows_qsort_frame_count").* += 1;
    continueWindowsQsort(self);
    return true;
}

fn completeWindowsBsearch(self: *ElfState, direct_return_rip: ?u64, result: u64) void {
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = result;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = if (direct_return_rip) |rip| rip else pop(self);
}

fn failWindowsBsearch(
    self: *ElfState,
    direct_return_rip: ?u64,
    key: u64,
    base: u64,
    nmemb: u64,
    element_size: u64,
    comparator: u64,
    detail: []const u8,
) void {
    if (comptime !@import("builtin").is_test) {
        __process_log.warn("Windows bsearch returned NULL: {s} key=0x{x} base=0x{x} nmemb={d} size={d} comparator=0x{x} rip=0x{x}", .{
            detail,
            key,
            base,
            nmemb,
            element_size,
            comparator,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        });
    }
    completeWindowsBsearch(self, direct_return_rip, 0);
}

fn finishWindowsBsearch(self: *ElfState, result: u64) void {
    const frame_count = process_impl_lifecycle.guestContextField(self, "windows_bsearch_frame_count");
    if (frame_count.* == 0) {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        __process_log.err("Windows bsearch callback completed without an active search frame rip=0x{x}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rip});
        return;
    }
    const frame_index = frame_count.* - 1;
    const frame = process_impl_lifecycle.guestContextField(self, "windows_bsearch_frames").*[frame_index];
    frame_count.* = frame_index;
    // The comparator's synthetic call used 32 bytes of Windows shadow space
    // plus its return address. Restore the import's exact entry stack before
    // returning to its caller (or before continuing a nested search).
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = frame.return_rsp;
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = result;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = if (frame.return_is_direct) frame.return_rip else pop(self);
    if (self.diagnose_abi) {
        __process_log.info("Windows bsearch complete elements={d} comparisons={d} result=0x{x} continuation=0x{x}", .{
            frame.nmemb,
            frame.callback_count,
            result,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        });
    }
}

fn failActiveWindowsBsearch(self: *ElfState, detail: []const u8) void {
    const frame_count = process_impl_lifecycle.guestContextField(self, "windows_bsearch_frame_count");
    if (frame_count.* == 0) {
        finishWindowsBsearch(self, 0);
        return;
    }
    const frame = process_impl_lifecycle.guestContextField(self, "windows_bsearch_frames").*[frame_count.* - 1];
    if (comptime !@import("builtin").is_test) {
        __process_log.warn("Windows bsearch returned NULL: {s} key=0x{x} base=0x{x} nmemb={d} size={d} comparator=0x{x} rip=0x{x}", .{
            detail,
            frame.key,
            frame.base,
            frame.nmemb,
            frame.element_size,
            frame.comparator,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        });
    }
    finishWindowsBsearch(self, 0);
}

pub fn continueWindowsBsearch(self: *ElfState) void {
    const frame_count = process_impl_lifecycle.guestContextField(self, "windows_bsearch_frame_count");
    if (frame_count.* == 0) {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        __process_log.err("Windows bsearch continuation has no active search frame rip=0x{x}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rip});
        return;
    }

    const frame_index = frame_count.* - 1;
    const frame = &process_impl_lifecycle.guestContextField(self, "windows_bsearch_frames").*[frame_index];
    // A guest `ret` from the comparator has consumed only its synthetic
    // return address. Restore the search's original import-entry stack before
    // probing again, so repeated and nested callbacks use the same shadow
    // space and the original caller return remains untouched.
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = frame.return_rsp;
    if (frame.awaiting_comparison) {
        frame.awaiting_comparison = false;
        // A guest comparator returns an int. The low 32 bits carry its signed
        // result regardless of how the guest code extended RAX.
        const comparison: i32 = @bitCast(@as(u32, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.rax)));
        if (comparison < 0) {
            frame.high = frame.pending_index;
        } else if (comparison > 0) {
            frame.low = frame.pending_index + 1;
        } else {
            const result = frame.base + frame.pending_index * frame.element_size;
            finishWindowsBsearch(self, result);
            return;
        }
    }

    if (frame.low >= frame.high) {
        finishWindowsBsearch(self, 0);
        return;
    }

    const middle = frame.low + (frame.high - frame.low) / 2;
    const element = frame.base + middle * frame.element_size;
    if (process_impl_execution.guestMemoryConst(self, element, frame.element_size) == null) {
        failActiveWindowsBsearch(self, "candidate element became unreadable");
        return;
    }
    frame.pending_index = middle;
    frame.callback_count +|= 1;
    frame.awaiting_comparison = true;

    // Model a Windows x64 call: the comparator receives a return address,
    // 32 bytes of caller-owned shadow space, and an aligned entry stack. A
    // direct-IAT import has no original call return pushed, so its saved RSP
    // is already the caller's call-site RSP; ordinary imports enter with the
    // original return address on the stack. Preserve the right alignment in
    // both cases and restore the bsearch frame's exact import stack after the
    // callback returns.
    const regs = process_impl_lifecycle.guestContextField(self, "regs");
    regs.*.rsp -|= if (frame.return_is_direct) 0x20 else 0x28;
    push(self, __process_x64_linux_runtime.SYNTHETIC_BSEARCH_RETURN);
    regs.*.rcx = frame.key;
    regs.*.rdx = element;
    regs.*.r8 = 0;
    regs.*.r9 = 0;
    regs.*.rip = frame.comparator;
}

pub fn handleWindowsBsearchSyntheticRip(self: *ElfState) bool {
    if (process_impl_lifecycle.guestContextField(self, "regs").*.rip != __process_x64_linux_runtime.SYNTHETIC_BSEARCH_RETURN) return false;
    continueWindowsBsearch(self);
    return true;
}

pub fn copyUnresolvedImportName(destination: []u8, source: []const u8) usize {
    @memset(destination, 0);
    const count = @min(destination.len, source.len);
    if (count != 0) @memcpy(destination[0..count], source[0..count]);
    return count;
}

pub fn beginWindowsBsearch(
    self: *ElfState,
    key: u64,
    base: u64,
    nmemb: u64,
    element_size: u64,
    comparator: u64,
    direct_return_rip: ?u64,
) bool {
    if (nmemb == 0) {
        completeWindowsBsearch(self, direct_return_rip, 0);
        return true;
    }
    if (key == 0 or base == 0 or comparator == 0) {
        failWindowsBsearch(self, direct_return_rip, key, base, nmemb, element_size, comparator, "null key, base, or comparator");
        return true;
    }
    if (element_size == 0) {
        failWindowsBsearch(self, direct_return_rip, key, base, nmemb, element_size, comparator, "zero element size");
        return true;
    }
    if (nmemb > __process_MAX_WINDOWS_BSEARCH_ELEMENTS) {
        failWindowsBsearch(self, direct_return_rip, key, base, nmemb, element_size, comparator, "element count exceeds bounded search limit");
        return true;
    }
    const byte_count = __process_std.math.mul(u64, nmemb, element_size) catch {
        failWindowsBsearch(self, direct_return_rip, key, base, nmemb, element_size, comparator, "element range overflows guest address width");
        return true;
    };
    _ = __process_std.math.add(u64, base, byte_count) catch {
        failWindowsBsearch(self, direct_return_rip, key, base, nmemb, element_size, comparator, "element range overflows guest address width");
        return true;
    };
    if (process_impl_execution.guestMemoryConst(self, key, 1) == null or
        process_impl_execution.guestMemoryConst(self, base, byte_count) == null)
    {
        failWindowsBsearch(self, direct_return_rip, key, base, nmemb, element_size, comparator, "key or element range is outside readable guest memory");
        return true;
    }
    if (addrToOffset(self, comparator) == null) {
        failWindowsBsearch(self, direct_return_rip, key, base, nmemb, element_size, comparator, "comparator is outside guest memory");
        return true;
    }
    const frame_count = process_impl_lifecycle.guestContextField(self, "windows_bsearch_frame_count");
    const frames = process_impl_lifecycle.guestContextField(self, "windows_bsearch_frames");
    if (frame_count.* >= frames.len) {
        failWindowsBsearch(self, direct_return_rip, key, base, nmemb, element_size, comparator, "nested search frame capacity exhausted");
        return true;
    }
    if (direct_return_rip == null and read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp) == 0) {
        failWindowsBsearch(self, direct_return_rip, key, base, nmemb, element_size, comparator, "caller continuation is null");
        return true;
    }

    const frame_index = frame_count.*;
    frames.*[frame_index] = .{
        .key = key,
        .base = base,
        .nmemb = nmemb,
        .element_size = element_size,
        .comparator = comparator,
        .low = 0,
        .high = nmemb,
        .return_rip = direct_return_rip orelse 0,
        .return_is_direct = direct_return_rip != null,
        .return_rsp = process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
    };
    frame_count.* += 1;
    continueWindowsBsearch(self);
    return true;
}

pub fn registerWindowsCrtAtexit(self: *ElfState, function: u64, quick: bool, is_thread_local: bool) bool {
    const globals = &self.windows_crt_globals;
    var rejected = false;
    var rejection_reason: []const u8 = "";
    if (globals.termination_complete or function == 0 or process_impl_execution.guestMemoryConst(self, function, 1) == null) {
        rejected = true;
        rejection_reason = if (globals.termination_complete)
            "termination-already-complete"
        else if (function == 0)
            "null-callback"
        else
            "callback-outside-guest-memory";
    } else if (is_thread_local) {
        if (globals.thread_local_callback != 0) {
            rejected = true;
            rejection_reason = "thread-local-slot-occupied";
        } else {
            globals.thread_local_callback = function;
        }
    } else if (quick) {
        if (globals.quick_count >= globals.quick_callbacks.len) {
            rejected = true;
            rejection_reason = "quick-exit-table-full";
        } else {
            globals.quick_callbacks[globals.quick_count] = .{ .function = function };
            globals.quick_count += 1;
        }
    } else if (globals.normal_count >= globals.normal_callbacks.len) {
        rejected = true;
        rejection_reason = "normal-exit-table-full";
    } else {
        globals.normal_callbacks[globals.normal_count] = .{ .function = function };
        globals.normal_count += 1;
    }

    if (rejected) {
        globals.callback_rejections +|= 1;
        __process_log.warn("PE64 CRT callback registration rejected: callback=0x{x} quick={} thread_local={} reason={s} normal_count={d}/{d} quick_count={d}/{d} termination_complete={} step={d}", .{
            function,
            quick,
            is_thread_local,
            rejection_reason,
            globals.normal_count,
            globals.normal_callbacks.len,
            globals.quick_count,
            globals.quick_callbacks.len,
            globals.termination_complete,
            process_impl_lifecycle.observedExecutionSteps(self),
        });
        return false;
    }
    globals.callback_registrations +|= 1;
    if (self.diagnose_abi) {
        __process_log.info("PE64 CRT callback registered: callback=0x{x} quick={} thread_local={} normal={d} quick_count={d} thread_local_callback=0x{x}", .{
            function,
            quick,
            is_thread_local,
            globals.normal_count,
            globals.quick_count,
            globals.thread_local_callback,
        });
    }
    return true;
}

pub fn returnFromWindowsCrtImport(self: *ElfState, direct_return_rip: ?u64) void {
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = if (direct_return_rip) |return_rip| return_rip else pop(self);
}

pub fn failWindowsCrtExit(self: *ElfState, detail: []const u8) void {
    const globals = &self.windows_crt_globals;
    globals.exit_running = false;
    globals.exit_mode = .none;
    globals.thread_local_pending = false;
    globals.termination_complete = true;
    process_impl_lifecycle.markFaulted(self);
    self.exit_code = 127;
    self.termination_reason = .runtime_invariant_failure;
    process_impl_lifecycle.markTerminated(self);
    __process_log.err("PE64 CRT exit protocol failure: {s} rip=0x{x} step={d}", .{ detail, process_impl_lifecycle.guestContextField(self, "regs").*.rip, process_impl_lifecycle.observedExecutionSteps(self) });
}

pub fn finishWindowsCrtExit(self: *ElfState) void {
    const globals = &self.windows_crt_globals;
    const code = globals.pending_exit_code;
    const return_to_caller = globals.exit_return_to_caller;
    const return_is_direct = globals.exit_return_is_direct;
    const return_rip = globals.exit_return_rip;
    const return_rsp = globals.exit_return_rsp;

    globals.exit_running = false;
    globals.exit_mode = .none;
    globals.thread_local_pending = false;
    globals.normal_count = 0;
    globals.quick_count = 0;
    globals.thread_local_callback = 0;
    globals.termination_complete = true;

    if (return_to_caller) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
        process_impl_lifecycle.guestContextField(self, "regs").*.rsp = return_rsp;
        returnFromWindowsCrtImport(self, if (return_is_direct) return_rip else null);
        if (self.diagnose_abi) {
            __process_log.info("PE64 CRT exit complete: returning cexit-style call code=0x{x} continuation=0x{x}", .{ code, process_impl_lifecycle.guestContextField(self, "regs").*.rip });
        }
        return;
    }

    self.exit_code = code;
    self.termination_reason = .exit_syscall;
    process_impl_lifecycle.markTerminated(self);
    __process_log.info("PE64 CRT exit complete: code=0x{x} callbacks={d} step={d}", .{
        code,
        globals.callback_invocations,
        process_impl_lifecycle.observedExecutionSteps(self),
    });
}

pub fn continueWindowsCrtExit(self: *ElfState) void {
    const globals = &self.windows_crt_globals;
    if (!globals.exit_running) {
        failWindowsCrtExit(self, "completion without an active exit");
        return;
    }

    // Every callback starts from the original import frame. A callback's
    // ordinary RET consumes the synthetic marker and leaves RSP eight
    // bytes below this point; resetting it here prevents nested callbacks
    // from accumulating stack drift.
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = globals.exit_return_rsp;
    while (true) {
        var callback: u64 = 0;
        var thread_local_callback = false;
        switch (globals.exit_mode) {
            .normal => {
                if (globals.normal_count != 0) {
                    globals.normal_count -= 1;
                    callback = globals.normal_callbacks[globals.normal_count].function;
                    globals.normal_callbacks[globals.normal_count] = .{};
                } else if (globals.thread_local_pending) {
                    globals.thread_local_pending = false;
                    callback = globals.thread_local_callback;
                    globals.thread_local_callback = 0;
                    thread_local_callback = true;
                }
            },
            .quick => {
                if (globals.quick_count != 0) {
                    globals.quick_count -= 1;
                    callback = globals.quick_callbacks[globals.quick_count].function;
                    globals.quick_callbacks[globals.quick_count] = .{};
                }
            },
            .none => {},
        }

        if (callback == 0) {
            finishWindowsCrtExit(self);
            return;
        }
        if (process_impl_execution.guestMemoryConst(self, callback, 1) == null) {
            globals.callback_rejections +|= 1;
            failWindowsCrtExit(self, "callback became invalid before invocation");
            return;
        }

        const return_rsp = globals.exit_return_rsp;
        if (return_rsp < 40) {
            failWindowsCrtExit(self, "callback frame would underflow the guest stack");
            return;
        }
        const callback_rsp = return_rsp - 40;
        if (process_impl_execution.guestMemoryConst(self, callback_rsp, 40) == null) {
            failWindowsCrtExit(self, "callback frame is outside guest memory");
            return;
        }
        process_impl_lifecycle.guestContextField(self, "regs").*.rsp = callback_rsp;
        write64(self, callback_rsp, __process_SYNTHETIC_WINDOWS_CRT_EXIT_RETURN);
        _ = process_impl_execution.fillGuestMemory(self, callback_rsp + 8, 32, 0);
        process_impl_lifecycle.guestContextField(self, "regs").*.rcx = 0;
        process_impl_lifecycle.guestContextField(self, "regs").*.rdx = 0; // DLL_PROCESS_DETACH for the TLS callback.
        process_impl_lifecycle.guestContextField(self, "regs").*.r8 = 0;
        process_impl_lifecycle.guestContextField(self, "regs").*.r9 = 0;
        process_impl_lifecycle.guestContextField(self, "regs").*.rip = callback;
        globals.callback_invocations +|= 1;
        if (self.diagnose_abi) {
            __process_log.info("PE64 CRT callback invoke: callback=0x{x} quick={} thread_local={} remaining_normal={d} remaining_quick={d} step={d}", .{
                callback,
                globals.exit_mode == .quick,
                thread_local_callback,
                globals.normal_count,
                globals.quick_count,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
        return;
    }
}

pub fn beginWindowsCrtExit(
    self: *ElfState,
    code: u64,
    quick: bool,
    run_callbacks: bool,
    return_to_caller: bool,
    direct_return_rip: ?u64,
) bool {
    const globals = &self.windows_crt_globals;
    if (globals.exit_running) {
        if (return_to_caller) {
            process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
            returnFromWindowsCrtImport(self, direct_return_rip);
            return true;
        }
        globals.pending_exit_code = code;
        globals.exit_running = false;
        globals.exit_mode = .none;
        globals.termination_complete = true;
        self.exit_code = code;
        self.termination_reason = .exit_syscall;
        process_impl_lifecycle.markTerminated(self);
        __process_log.info("PE64 CRT nested non-returning exit: code=0x{x} step={d}", .{ code, process_impl_lifecycle.observedExecutionSteps(self) });
        return true;
    }
    if (globals.termination_complete) {
        if (return_to_caller) {
            process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
            returnFromWindowsCrtImport(self, direct_return_rip);
        } else {
            self.exit_code = code;
            self.termination_reason = .exit_syscall;
            process_impl_lifecycle.markTerminated(self);
        }
        return true;
    }

    globals.pending_exit_code = code;
    globals.exit_mode = if (!run_callbacks) .none else if (quick) .quick else .normal;
    globals.exit_running = true;
    globals.exit_return_to_caller = return_to_caller;
    globals.exit_return_is_direct = direct_return_rip != null;
    globals.exit_return_rip = direct_return_rip orelse 0;
    globals.exit_return_rsp = process_impl_lifecycle.guestContextField(self, "regs").*.rsp;
    globals.thread_local_pending = globals.exit_mode == .normal and globals.thread_local_callback != 0;

    if (!run_callbacks) {
        finishWindowsCrtExit(self);
        return true;
    }
    continueWindowsCrtExit(self);
    return true;
}

pub fn failWindowsInitTerm(self: *ElfState, begin: u64, end: u64, detail: []const u8) void {
    process_impl_lifecycle.markFaulted(self);
    self.exit_code = 127;
    self.termination_reason = .runtime_invariant_failure;
    process_impl_lifecycle.markTerminated(self);
    if (comptime !@import("builtin").is_test) {
        __process_log.err("invalid Windows CRT initializer table at rip=0x{x}: range=0x{x}..0x{x} {s}", .{ process_impl_lifecycle.guestContextField(self, "regs").*.rip, begin, end, detail });
    }
}

pub fn finishWindowsInitTerm(self: *ElfState, result: u64) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_initterm_frame_count").* == 0) {
        failWindowsInitTerm(self, 0, 0, "completion without an active frame");
        return;
    }
    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_initterm_frame_count").* - 1;
    const frame = process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index];
    process_impl_lifecycle.guestContextField(self, "windows_initterm_frame_count").* = frame_index;
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = result;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = if (frame.return_is_direct) frame.return_rip else pop(self);
    if (self.diagnose_abi) {
        __process_log.info("Windows CRT initializer table complete callbacks={d} result=0x{x} continuation=0x{x}", .{
            frame.callback_count,
            result,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        });
    }
}

pub fn continueWindowsInitTerm(self: *ElfState) void {
    if (process_impl_lifecycle.guestContextField(self, "windows_initterm_frame_count").* == 0) {
        failWindowsInitTerm(self, 0, 0, "completion without an active frame");
        return;
    }

    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_initterm_frame_count").* - 1;
    // `_initterm_e` stops when an initializer reports a nonzero result.
    // The normal `_initterm` callbacks are void and their RAX value is not
    // part of the contract.
    if (process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].returns_error and process_impl_lifecycle.guestContextField(self, "regs").*.rax != 0) {
        finishWindowsInitTerm(self, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
        return;
    }

    while (process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].begin < process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].end) {
        const target_slot = process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].begin;
        process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].begin = target_slot + 8;
        const target = read64(self, target_slot);
        if (target == 0) continue;

        if (addrToOffset(self, target) == null) {
            failWindowsInitTerm(
                self,
                target_slot,
                process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].end,
                "initializer target is outside the guest image",
            );
            return;
        }

        process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].callback_count +|= 1;
        push(self, __process_x64_linux_runtime.SYNTHETIC_INITTERM_RETURN);
        process_impl_lifecycle.guestContextField(self, "regs").*.rip = target;
        if (self.diagnose_abi) {
            __process_log.info("Windows CRT initializer callback {d} target=0x{x} next_slot=0x{x} end=0x{x}", .{
                process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].callback_count,
                target,
                process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].begin,
                process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index].end,
            });
        }
        return;
    }

    finishWindowsInitTerm(self, 0);
}

pub fn beginWindowsInitTerm(
    self: *ElfState,
    begin: u64,
    end: u64,
    direct_return_rip: ?u64,
    returns_error: bool,
) bool {
    if (begin > end or (begin & 7) != 0 or (end & 7) != 0) {
        failWindowsInitTerm(self, begin, end, "unaligned or reversed range");
        return true;
    }
    const byte_count = end - begin;
    if (byte_count > __process_MAX_WINDOWS_INITTERM_ENTRIES * 8) {
        failWindowsInitTerm(self, begin, end, "initializer table exceeds bounded entry count");
        return true;
    }
    if (byte_count != 0 and process_impl_execution.guestMemoryConst(self, begin, byte_count) == null) {
        failWindowsInitTerm(self, begin, end, "initializer table is outside guest memory");
        return true;
    }
    if (process_impl_lifecycle.guestContextField(self, "windows_initterm_frame_count").* >= process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*.len) {
        failWindowsInitTerm(self, begin, end, "initializer nesting exceeds bounded frame count");
        return true;
    }

    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_initterm_frame_count").*;
    process_impl_lifecycle.guestContextField(self, "windows_initterm_frames").*[frame_index] = .{
        .begin = begin,
        .end = end,
        .return_rip = direct_return_rip orelse 0,
        .return_is_direct = direct_return_rip != null,
        .returns_error = returns_error,
    };
    process_impl_lifecycle.guestContextField(self, "windows_initterm_frame_count").* += 1;
    continueWindowsInitTerm(self);
    return true;
}
