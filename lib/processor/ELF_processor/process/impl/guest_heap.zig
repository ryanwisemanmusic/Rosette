const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_run_reporting = @import("run_reporting.zig");
const heap_record_index = @import("../../windows_guest/heap_record_index.zig");
const __process_STACK_SIZE = __ProcessInternals._STACK_SIZE;
const __process_WINDOWS_GUEST_THREAD_MAX_STACK_SIZE = __ProcessInternals._WINDOWS_GUEST_THREAD_MAX_STACK_SIZE;
const __process_WINDOWS_GUEST_THREAD_STACK_GUARD = __ProcessInternals._WINDOWS_GUEST_THREAD_STACK_GUARD;
const __process_WINDOWS_HEAP_ANOMALY_LOG_LIMIT = __ProcessInternals._WINDOWS_HEAP_ANOMALY_LOG_LIMIT;
const __process_WINDOWS_HEAP_BIN_SCAN = __ProcessInternals._WINDOWS_HEAP_BIN_SCAN;
const __process_WindowsHeapAllocation = __ProcessInternals._WindowsHeapAllocation;
const __process_WindowsHeapBin = __ProcessInternals._WindowsHeapBin;
const __process_WindowsImportStub = __ProcessInternals._WindowsImportStub;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_heap_address_cache = __ProcessInternals._heap_address_cache;
const __process_heap_guard = __ProcessInternals._heap_guard;
const __process_log = __ProcessInternals._log;
const __process_std = __ProcessInternals._std;
const __process_tso_memory = __ProcessInternals._tso_memory;

pub fn guestAlloc(self: *ElfState, requested_size: u64, requested_alignment: u64) ?u64 {
    return guestAllocWithInitialization(self, requested_size, requested_alignment, true);
}

pub fn guestAllocUninitialized(self: *ElfState, requested_size: u64, requested_alignment: u64) ?u64 {
    return guestAllocWithInitialization(self, requested_size, requested_alignment, false);
}

pub fn guestAllocWithInitialization(self: *ElfState, requested_size: u64, requested_alignment: u64, zero_fill: bool) ?u64 {
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    const size = if (requested_size == 0) 1 else requested_size;
    if (size > __process_std.math.maxInt(usize)) {
        if (self.windows_runtime_enabled) __process_log.err("PE64 guest allocation rejected: size={d} exceeds host index width rip=0x{x} op={s} len={d} rsp=0x{x} return=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x}", .{
            size,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
            process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
            process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
            process_impl_lifecycle.guestContextField(self, "regs").*.r8,
            process_impl_lifecycle.guestContextField(self, "regs").*.r9,
        });
        process_impl_kernel_services.logWindowsHeapFailureDetail(self, "request-exceeds-host-index", 0, size, requested_alignment, null);
        return null;
    }

    var alignment = if (requested_alignment <= 1) @as(u64, 1) else requested_alignment;
    if ((alignment & (alignment - 1)) != 0) {
        var rounded: u64 = 1;
        while (rounded < alignment) {
            if (rounded > (__process_std.math.maxInt(u64) >> 1)) return null;
            rounded <<= 1;
        }
        alignment = rounded;
    }

    if (reuseGuestHeapAllocation(self, size, alignment, zero_fill)) |reused| {
        if (self.trace_allocations and !@import("builtin").is_test) {
            __process_log.info("PE64 guest allocation reused address=0x{x} requested={d} size={d} alignment={d} free={d} reused={d} rip=0x{x} op={s} len={d} rsp=0x{x} ret=0x{x}", .{
                reused,
                requested_size,
                size,
                alignment,
                self.windows_heap_free_count,
                self.windows_heap_reused_allocations,
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
                process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
                process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
                process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
            });
        }
        return reused;
    }

    const mask = alignment - 1;
    if (self.heap_next > __process_std.math.maxInt(u64) - mask) {
        if (self.windows_runtime_enabled) {
            __process_log.err("PE64 guest allocation rejected: heap cursor overflow heap_next=0x{x} alignment={d}", .{ self.heap_next, alignment });
            process_impl_kernel_services.logWindowsHeapFailureDetail(self, "heap-cursor-overflow", self.heap_next, size, alignment, null);
        }
        return null;
    }
    const aligned = (self.heap_next + mask) & ~mask;
    const heap_limit = if (self.guest_heap_limit != 0)
        self.guest_heap_limit
    else
        self.mem_base + self.mem_size - __process_STACK_SIZE;
    // The block's backing holds its guard past the logical end, unless
    // the block is page-aligned (see `heap_guard.guardBytesFor`).
    const guard_bytes = __process_heap_guard.guardBytesFor(self.windows_heap_guard_bytes, alignment);
    const reserved = size +| guard_bytes;
    if (aligned >= heap_limit or reserved > heap_limit - aligned) {
        if (self.windows_runtime_enabled) {
            __process_log.err("PE64 guest allocation rejected: request={d} align={d} heap_next=0x{x} aligned=0x{x} limit=0x{x} mem_base=0x{x} mem_size=0x{x} rip=0x{x} op={s} rsp=0x{x} return=0x{x}", .{
                size,
                alignment,
                self.heap_next,
                aligned,
                heap_limit,
                self.mem_base,
                self.mem_size,
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
                process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
                process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
            });
            process_impl_kernel_services.logWindowsHeapFailureDetail(self, "request-exceeds-guest-heap", aligned, size, alignment, null);
        }
        return null;
    }
    const off = process_impl_guest_memory.addrToOffset(self, aligned) orelse {
        if (self.windows_runtime_enabled) {
            __process_log.err("PE64 guest allocation rejected: aligned address outside guest range aligned=0x{x} mem_base=0x{x} mem_size=0x{x}", .{ aligned, self.mem_base, self.mem_size });
            process_impl_kernel_services.logWindowsHeapFailureDetail(self, "aligned-address-outside-guest-range", aligned, size, alignment, null);
        }
        return null;
    };
    const size_usize: usize = @intCast(size);
    const reserved_usize: usize = @intCast(reserved);
    if (off > self.mem.len or reserved_usize > self.mem.len - off) {
        if (self.windows_runtime_enabled) {
            __process_log.err("PE64 guest allocation rejected: offset={d} size={d} backing_bytes={d}", .{ off, size_usize, self.mem.len });
            process_impl_kernel_services.logWindowsHeapFailureDetail(self, "allocation-exceeds-backing-memory", aligned, size, alignment, null);
        }
        return null;
    }

    if (zero_fill) {
        if (self.parallel_guest_execution) {
            __process_tso_memory.fillCoordinated(self.mem[off..][0..size_usize], 0);
        } else {
            @memset(self.mem[off..][0..size_usize], 0);
        }
        self.windows_heap_zero_fill_bytes +|= size;
    } else {
        self.windows_heap_zero_fill_avoided_bytes +|= size;
    }
    __process_heap_guard.arm(self.mem[off + size_usize .. off + reserved_usize]);
    if (self.windows_heap_allocation_count == self.windows_heap_allocations.len) {
        if (!growGuestHeapProvenance(self)) {
            // The guest allocation itself is still valid.  Keep running
            // rather than converting a host bookkeeping OOM into a guest
            // allocation failure; the first failure is recorded once and
            // the final diagnostics expose how many records were missed.
            self.windows_heap_provenance_untracked_allocations +|= 1;
        }
    }
    if (self.windows_heap_allocation_count < self.windows_heap_allocations.len) {
        const site = process_impl_kernel_services.windowsHeapCallSite(self);
        self.windows_heap_allocations[self.windows_heap_allocation_count] = .{
            .guest_base = aligned,
            .length = size,
            .active = true,
            .guard_bytes = @intCast(@min(guard_bytes, __process_std.math.maxInt(u8))),
            .allocation_rip = site.rip,
            .allocation_return = site.return_address,
            .allocation_step = site.step,
            .allocation_thread_slot = site.thread_slot,
            .allocation_import = site.import,
        };
        self.windows_heap_allocation_count += 1;
        switch (heap_record_index.appendRecord(
            self.allocator,
            &self.windows_heap_address_index,
            &self.windows_heap_address_indexed_records,
            &self.windows_heap_address_index_disabled,
            self.windows_heap_allocations[0..self.windows_heap_allocation_count],
            self.windows_heap_allocation_count - 1,
        )) {
            .indexed, .disabled => {},
            .failed => self.windows_heap_address_index_failures +|= 1,
        }
        self.windows_heap_allocations_live += 1;
        noteGuestHeapBytes(self, size, true);
    }
    self.heap_next = aligned + reserved;
    if (self.trace_allocations and !@import("builtin").is_test) {
        __process_log.info("PE64 guest allocation address=0x{x} requested={d} alignment={d} next=0x{x} rip=0x{x} op={s} len={d} rsp=0x{x} ret=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x}", .{
            aligned,
            requested_size,
            alignment,
            self.heap_next,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
            process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
            process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
            process_impl_lifecycle.guestContextField(self, "regs").*.r8,
            process_impl_lifecycle.guestContextField(self, "regs").*.r9,
        });
    }
    return aligned;
}

pub fn reportGuestHeapUse(self: *const ElfState) void {
    if (!self.windows_runtime_enabled) return;
    const base = self.image_high;
    const used = self.heap_next -| base;
    const limit = self.guest_heap_limit -| base;
    const damaged_live = countDamagedLiveGuestHeapGuards(self);
    __process_log.info("PE64 GUEST HEAP: bytes(live/peak/cursor/limit)={d}/{d}/{d}/{d} zero_fill(zeroed/avoided)={d}/{d} quarantine(blocks/bytes)={d}/{d} binned={d} double_frees={d} unknown_frees={d} overruns(freed/live)={d}/{d} guard_bytes={d}; malloc-semantic allocations may retain unspecified bytes, while internal zeroed allocations and calloc clear storage; freed blocks remain quarantined before reuse", .{
        self.windows_heap_bytes_live,
        self.windows_heap_bytes_peak,
        used,
        limit,
        self.windows_heap_zero_fill_bytes,
        self.windows_heap_zero_fill_avoided_bytes,
        self.windows_heap_quarantine_len,
        self.windows_heap_quarantine_bytes,
        self.windows_heap_binned,
        self.windows_heap_double_frees,
        self.windows_heap_unknown_frees,
        self.windows_heap_overruns,
        damaged_live,
        self.windows_heap_guard_bytes,
    });
    __process_log.info("PE64 GUEST THREAD CONTRACTS: apcs(queued/delivered/woken/refused)={d}/{d}/{d}/{d} stack_overflows={d} stack_guard={d} max_stack={d}; an APC runs inside its thread's next alertable wait, and a worker stack has no-access pages beneath it so an overflow stops instead of writing the heap", .{
        self.windows_apcs_queued,
        self.windows_apcs_delivered,
        self.windows_apc_wakes,
        self.windows_apc_refusals,
        self.windows_stack_overflows,
        __process_WINDOWS_GUEST_THREAD_STACK_GUARD,
        __process_WINDOWS_GUEST_THREAD_MAX_STACK_SIZE,
    });
    __process_log.info("PE64 GUEST HEAP LOOKUP: exact_address_cache(hit/miss)={d}/{d}; hits still revalidate the append-only allocation record before using its index", .{
        self.windows_heap_address_cache_hits.load(.monotonic),
        self.windows_heap_address_cache_misses.load(.monotonic),
    });
    __process_log.info("PE64 GUEST HEAP ADDRESS INDEX: records={d}/{d} lookups={d} probes={d} binary_fallbacks={d} disabled={}; a full index handles exact bases by bounded open addressing, and any index allocation/consistency failure retains the ordered binary-search path", .{
        self.windows_heap_address_indexed_records,
        self.windows_heap_allocation_count,
        self.windows_heap_address_index_lookups.load(.monotonic),
        self.windows_heap_address_index_probes.load(.monotonic),
        self.windows_heap_address_index_fallbacks.load(.monotonic),
        self.windows_heap_address_index_disabled,
    });
}

pub fn noteGuestHeapBytes(self: *ElfState, length: u64, live: bool) void {
    if (live) {
        self.windows_heap_bytes_live +|= length;
        self.windows_heap_bytes_peak = @max(self.windows_heap_bytes_peak, self.windows_heap_bytes_live);
    } else {
        self.windows_heap_bytes_live -|= length;
    }
}

pub fn rememberGuestHeapFreeIndex(self: *ElfState, allocation_index: usize) void {
    const length = self.windows_heap_allocations[allocation_index].length;
    if (self.windows_heap_quarantine_limit_blocks == 0) {
        binGuestHeapBlock(self, allocation_index);
        return;
    }
    if (self.windows_heap_quarantine.len == 0) {
        self.windows_heap_quarantine = self.allocator.alloc(usize, self.windows_heap_quarantine_limit_blocks) catch {
            self.windows_heap_free_list_growth_failures +|= 1;
            binGuestHeapBlock(self, allocation_index);
            return;
        };
    }
    while (self.windows_heap_quarantine_len != 0 and
        (self.windows_heap_quarantine_len >= self.windows_heap_quarantine.len or
            self.windows_heap_quarantine_bytes +| length > self.windows_heap_quarantine_limit_bytes))
    {
        releaseOldestGuestHeapQuarantine(self);
    }
    const tail = (self.windows_heap_quarantine_head + self.windows_heap_quarantine_len) % self.windows_heap_quarantine.len;
    self.windows_heap_quarantine[tail] = allocation_index;
    self.windows_heap_quarantine_len += 1;
    self.windows_heap_quarantine_bytes +|= length;
    self.windows_heap_free_count += 1;
}

pub fn releaseOldestGuestHeapQuarantine(self: *ElfState) void {
    const index = self.windows_heap_quarantine[self.windows_heap_quarantine_head];
    self.windows_heap_quarantine_head = (self.windows_heap_quarantine_head + 1) % self.windows_heap_quarantine.len;
    self.windows_heap_quarantine_len -= 1;
    self.windows_heap_free_count -|= 1;
    if (index < self.windows_heap_allocation_count) {
        self.windows_heap_quarantine_bytes -|= self.windows_heap_allocations[index].length;
        if (!self.windows_heap_allocations[index].active) binGuestHeapBlock(self, index);
    }
}

pub fn binGuestHeapBlock(self: *ElfState, allocation_index: usize) void {
    const length = self.windows_heap_allocations[allocation_index].length;
    if (length == 0) return;
    const entry = self.windows_heap_bins.getOrPut(self.allocator, length) catch {
        self.windows_heap_free_list_growth_failures +|= 1;
        return;
    };
    if (!entry.found_existing) entry.value_ptr.* = .{};
    entry.value_ptr.indices.append(self.allocator, allocation_index) catch {
        self.windows_heap_free_list_growth_failures +|= 1;
        return;
    };
    self.windows_heap_binned += 1;
    self.windows_heap_free_count += 1;
}

pub fn reuseGuestHeapAllocation(self: *ElfState, size: u64, alignment: u64, zero_fill: bool) ?u64 {
    const mask = alignment - 1;
    const bin = self.windows_heap_bins.getPtr(size) orelse return null;
    var scanned: usize = 0;
    var position = bin.head;
    while (position < bin.indices.items.len and scanned < __process_WINDOWS_HEAP_BIN_SCAN) : (scanned += 1) {
        const allocation_index = bin.indices.items[position];
        const usable = allocation_index < self.windows_heap_allocation_count and
            !self.windows_heap_allocations[allocation_index].active and
            self.windows_heap_allocations[allocation_index].length == size;
        if (!usable) {
            // Stale: drop it from the front or swap it out of the middle.
            takeGuestHeapBinEntry(self, bin, position);
            continue;
        }
        const record = self.windows_heap_allocations[allocation_index];
        if ((record.guest_base & mask) != 0) {
            position += 1;
            continue;
        }
        const off = process_impl_guest_memory.addrToOffset(self, record.guest_base) orelse {
            takeGuestHeapBinEntry(self, bin, position);
            continue;
        };
        const size_usize: usize = @intCast(size);
        if (off > self.mem.len or size_usize > self.mem.len - off) {
            takeGuestHeapBinEntry(self, bin, position);
            continue;
        }
        takeGuestHeapBinEntry(self, bin, position);
        const site = process_impl_kernel_services.windowsHeapCallSite(self);
        self.windows_heap_allocations[allocation_index].active = true;
        self.windows_heap_allocations[allocation_index].allocation_rip = site.rip;
        self.windows_heap_allocations[allocation_index].allocation_return = site.return_address;
        self.windows_heap_allocations[allocation_index].allocation_step = site.step;
        self.windows_heap_allocations[allocation_index].allocation_thread_slot = site.thread_slot;
        self.windows_heap_allocations[allocation_index].allocation_import = site.import;
        self.windows_heap_allocations[allocation_index].free_rip = 0;
        self.windows_heap_allocations[allocation_index].free_return = 0;
        self.windows_heap_allocations[allocation_index].free_step = 0;
        self.windows_heap_allocations[allocation_index].free_thread_slot = 0;
        self.windows_heap_allocations[allocation_index].free_import = &.{};
        self.windows_heap_allocations_live += 1;
        self.windows_heap_reused_allocations +|= 1;
        noteGuestHeapBytes(self, size, true);
        if (zero_fill) {
            if (self.parallel_guest_execution) {
                __process_tso_memory.fillCoordinated(self.mem[off..][0..size_usize], 0);
            } else {
                @memset(self.mem[off..][0..size_usize], 0);
            }
            self.windows_heap_zero_fill_bytes +|= size;
        } else {
            self.windows_heap_zero_fill_avoided_bytes +|= size;
        }
        armGuestHeapGuard(self, self.windows_heap_allocations[allocation_index]);
        return record.guest_base;
    }
    return null;
}

pub fn takeGuestHeapBinEntry(self: *ElfState, bin: *__process_WindowsHeapBin, position: usize) void {
    if (position == bin.head) {
        bin.head += 1;
    } else {
        bin.indices.items[position] = bin.indices.items[bin.head];
        bin.head += 1;
    }
    self.windows_heap_binned -|= 1;
    self.windows_heap_free_count -|= 1;
    bin.compact();
}

pub fn noteGuestHeapFreeAnomaly(self: *ElfState, guest_base: u64, double_free: bool) void {
    const count = if (double_free) &self.windows_heap_double_frees else &self.windows_heap_unknown_frees;
    count.* +|= 1;
    if (!self.windows_runtime_enabled or count.* > __process_WINDOWS_HEAP_ANOMALY_LOG_LIMIT) return;
    const site = process_impl_kernel_services.windowsHeapCallSite(self);
    const caller = site.return_address;
    var caller_name: [256]u8 = undefined;
    const slot_plus_one = site.thread_slot;
    const record_index = findGuestHeapAllocation(self, guest_base);
    __process_log.warn("PE64 GUEST HEAP {s}: address=0x{x} occurrence={d} caller=0x{x} ({s}) thread={s} step={d}; {s}", .{
        if (double_free) "DOUBLE FREE" else "UNKNOWN FREE",
        guest_base,
        count.*,
        caller,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller, &caller_name),
        process_impl_guest_diagnostics.guestThreadLabel(self, slot_plus_one),
        process_impl_run_reporting.totalInterpretedSteps(self),
        if (double_free)
            "the block was already free; the second free is refused, so it cannot release whatever the block holds next"
        else
            "no allocation starts at this address; the free is ignored",
    });
    process_impl_kernel_services.logWindowsHeapFailureDetail(
        self,
        if (double_free) "double-free" else "unknown-free",
        guest_base,
        0,
        0,
        record_index,
    );
}

pub fn growGuestHeapProvenance(self: *ElfState) bool {
    const old_capacity = self.windows_heap_allocations.len;
    const base_capacity = @max(old_capacity, @as(usize, 1));
    const new_capacity = __process_std.math.mul(usize, base_capacity, 2) catch {
        self.windows_heap_provenance_growth_failures +|= 1;
        return false;
    };
    const grown = self.allocator.realloc(self.windows_heap_allocations, new_capacity) catch {
        self.windows_heap_provenance_growth_failures +|= 1;
        if (self.windows_runtime_enabled and self.windows_heap_provenance_growth_failures == 1) {
            __process_log.err("PE64 guest allocation provenance table growth failed: capacity={d}; guest allocations continue without records", .{old_capacity});
        }
        return false;
    };
    @memset(grown[old_capacity..], .{});
    self.windows_heap_allocations = grown;
    if (self.windows_runtime_enabled) {
        __process_log.info("PE64 guest allocation provenance table grew: capacity={d} records={d} live={d} free={d}; released records remain address-ordered tombstones while exact blocks are reusable", .{ new_capacity, self.windows_heap_allocation_count, self.windows_heap_allocations_live, self.windows_heap_free_count });
    }
    return true;
}

pub fn guestHeapGuardSlice(self: *const ElfState, record: __process_WindowsHeapAllocation) ?[]u8 {
    if (record.guard_bytes == 0) return null;
    const end = __process_std.math.add(u64, record.guest_base, record.length) catch return null;
    const off = process_impl_guest_memory.addrToOffset(self, end) orelse return null;
    const guard_usize: usize = record.guard_bytes;
    if (off > self.mem.len or guard_usize > self.mem.len - off) return null;
    return self.mem[off..][0..guard_usize];
}

pub fn armGuestHeapGuard(self: *ElfState, record: __process_WindowsHeapAllocation) void {
    if (guestHeapGuardSlice(self, record)) |guard| __process_heap_guard.arm(guard);
}

pub fn checkGuestHeapGuard(self: *ElfState, index: usize, when: []const u8) void {
    const record = self.windows_heap_allocations[index];
    const guard = guestHeapGuardSlice(self, record) orelse return;
    const damage = __process_heap_guard.check(guard) orelse return;
    self.windows_heap_overruns +|= 1;
    reportGuestHeapOverrun(self, record, damage, when, self.windows_heap_overruns);
}

pub fn reportGuestHeapOverrun(self: *ElfState, record: __process_WindowsHeapAllocation, damage: __process_heap_guard.Damage, when: []const u8, occurrence: u64) void {
    var allocated_by: [__process_guest_symbol_text_bytes]u8 = undefined;
    process_impl_execution.noteNotableEvent(self, .heap_overrun, record.allocation_return, "block 0x{x} length={d} overrun at +{d} (0x{x}, {d} guard byte(s) changed) found at {s}", .{
        record.guest_base,
        record.length,
        damage.first_offset,
        damage.first_value,
        damage.changed,
        when,
    });
    if (!process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) return;
    if (comptime @import("builtin").is_test) return;
    __process_log.err("PE64 GUEST HEAP OVERRUN: block=0x{x} length={d} end=0x{x} guard(first_offset/value/changed)=+{d}/0x{x}/{d} found_at={s} allocated_by={s} caller=0x{x} ({s}) allocation_step={d} allocation_thread={s} occurrence={d}; something wrote past this block's end into the next block - the guest, or Rosette executing it wrongly - and the neighbour is where it would have been noticed later", .{
        record.guest_base,
        record.length,
        record.guest_base +| record.length,
        damage.first_offset,
        damage.first_value,
        damage.changed,
        when,
        if (record.allocation_import.len == 0) "<none>" else record.allocation_import,
        record.allocation_return,
        if (record.allocation_return == 0) "<unknown>" else process_impl_kernel_services.describeGuestAddressOrUnnamed(self, record.allocation_return, &allocated_by),
        record.allocation_step,
        process_impl_guest_diagnostics.guestThreadLabel(self, record.allocation_thread_slot),
        occurrence,
    });
}

pub fn countDamagedLiveGuestHeapGuards(self: *const ElfState) u64 {
    var damaged: u64 = 0;
    for (self.windows_heap_allocations[0..self.windows_heap_allocation_count]) |record| {
        if (!record.active) continue;
        const guard = guestHeapGuardSlice(self, record) orelse continue;
        if (__process_heap_guard.check(guard) != null) damaged += 1;
    }
    return damaged;
}

pub fn findGuestHeapAllocation(self: *ElfState, guest_base: u64) ?usize {
    const owner: *anyopaque = @ptrCast(@constCast(self));
    const records = self.windows_heap_allocations[0..self.windows_heap_allocation_count];
    if (__process_heap_address_cache.lookup(owner, guest_base, records)) |cached| {
        _ = self.windows_heap_address_cache_hits.fetchAdd(1, .monotonic);
        return cached;
    }
    _ = self.windows_heap_address_cache_misses.fetchAdd(1, .monotonic);
    if (!self.windows_heap_address_index_disabled and
        self.windows_heap_address_indexed_records == self.windows_heap_allocation_count and
        self.windows_heap_address_index.len != 0)
    {
        const indexed = heap_record_index.lookup(
            self.windows_heap_address_index,
            records,
            guest_base,
        );
        _ = self.windows_heap_address_index_lookups.fetchAdd(1, .monotonic);
        _ = self.windows_heap_address_index_probes.fetchAdd(indexed.probes, .monotonic);
        if (indexed.index) |found| {
            __process_heap_address_cache.remember(owner, guest_base, found);
            return found;
        }
    }
    _ = self.windows_heap_address_index_fallbacks.fetchAdd(1, .monotonic);
    var lower: usize = 0;
    var upper = self.windows_heap_allocation_count;
    while (lower < upper) {
        const middle = lower + (upper - lower) / 2;
        const record = self.windows_heap_allocations[middle];
        if (record.guest_base < guest_base) {
            lower = middle + 1;
        } else {
            upper = middle;
        }
    }
    if (lower < self.windows_heap_allocation_count and self.windows_heap_allocations[lower].guest_base == guest_base) {
        __process_heap_address_cache.remember(owner, guest_base, lower);
        return lower;
    }
    return null;
}

pub fn releaseGuestAllocation(self: *ElfState, guest_base: u64) bool {
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    if (guest_base == 0) return true;
    const index = findGuestHeapAllocation(self, guest_base) orelse {
        noteGuestHeapFreeAnomaly(self, guest_base, false);
        return false;
    };
    if (!self.windows_heap_allocations[index].active) {
        noteGuestHeapFreeAnomaly(self, guest_base, true);
        return false;
    }
    checkGuestHeapGuard(self, index, "free");
    const site = process_impl_kernel_services.windowsHeapCallSite(self);
    self.windows_heap_allocations[index].free_rip = site.rip;
    self.windows_heap_allocations[index].free_return = site.return_address;
    self.windows_heap_allocations[index].free_step = site.step;
    self.windows_heap_allocations[index].free_thread_slot = site.thread_slot;
    self.windows_heap_allocations[index].free_import = site.import;
    self.windows_heap_allocations[index].active = false;
    if (self.windows_heap_allocations_live != 0) self.windows_heap_allocations_live -= 1;
    noteGuestHeapBytes(self, self.windows_heap_allocations[index].length, false);
    rememberGuestHeapFreeIndex(self, index);
    return true;
}

pub fn reallocateGuest(
    self: *ElfState,
    old_guest_base: u64,
    requested_size: u64,
    requested_alignment: u64,
) ?u64 {
    var runtime_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    defer if (runtime_guard) |*guard| guard.unlock();
    if (old_guest_base == 0) {
        if (requested_size == 0) return null;
        return guestAlloc(self, requested_size, requested_alignment);
    }
    if (requested_size == 0) {
        _ = releaseGuestAllocation(self, old_guest_base);
        return null;
    }

    const old_index = findGuestHeapAllocation(self, old_guest_base) orelse {
        if (self.windows_runtime_enabled) __process_log.err("PE64 realloc rejected unknown block: address=0x{x} requested={d} rip=0x{x}", .{ old_guest_base, requested_size, process_impl_lifecycle.guestContextField(self, "regs").*.rip });
        return null;
    };
    const old_record = self.windows_heap_allocations[old_index];
    if (!old_record.active or old_record.length == 0) {
        if (self.windows_runtime_enabled) __process_log.err("PE64 realloc rejected inactive block: address=0x{x} requested={d} rip=0x{x}", .{ old_guest_base, requested_size, process_impl_lifecycle.guestContextField(self, "regs").*.rip });
        return null;
    }
    if (requested_size <= old_record.length) {
        // The old guard must still be intact; the new one starts at the
        // new logical end, over bytes the guest no longer owns.
        checkGuestHeapGuard(self, old_index, "shrink");
        self.windows_heap_allocations[old_index].length = requested_size;
        armGuestHeapGuard(self, self.windows_heap_allocations[old_index]);
        return old_guest_base;
    }

    const new_guest_base = guestAlloc(self, requested_size, requested_alignment) orelse return null;
    const old_offset = process_impl_guest_memory.addrToOffset(self, old_guest_base) orelse {
        _ = releaseGuestAllocation(self, new_guest_base);
        return null;
    };
    const new_offset = process_impl_guest_memory.addrToOffset(self, new_guest_base) orelse {
        _ = releaseGuestAllocation(self, new_guest_base);
        return null;
    };
    const copy_length: usize = @intCast(@min(old_record.length, requested_size));
    if (self.parallel_guest_execution) {
        __process_tso_memory.copyCoordinated(self.mem[new_offset..][0..copy_length], self.mem[old_offset..][0..copy_length]);
    } else {
        @memcpy(self.mem[new_offset..][0..copy_length], self.mem[old_offset..][0..copy_length]);
    }
    _ = releaseGuestAllocation(self, old_guest_base);
    return new_guest_base;
}

pub fn registerWindowsImportStub(self: *ElfState, dll_name: []const u8, function_name: []const u8) ?u64 {
    for (self.windows_stub_storage[0..self.windows_stub_count]) |stub| {
        if (__process_std.mem.eql(u8, stub.dll_name, dll_name) and __process_std.mem.eql(u8, stub.function_name, function_name)) {
            return stub.address;
        }
    }
    const address = guestAlloc(self, 16, 16) orelse return null;
    return if (registerWindowsImportStubAt(self, address, dll_name, function_name)) address else null;
}

pub fn registerWindowsImportStubAt(self: *ElfState, address: u64, dll_name: []const u8, function_name: []const u8) bool {
    return registerWindowsImportStubAtIat(self, address, dll_name, function_name, 0);
}

pub fn registerWindowsImportStubAtIat(self: *ElfState, address: u64, dll_name: []const u8, function_name: []const u8, iat_address: u64) bool {
    if (address == 0 or function_name.len == 0) return false;
    for (self.windows_stub_storage[0..self.windows_stub_count]) |stub| {
        if (stub.address == address) {
            return __process_std.mem.eql(u8, stub.dll_name, dll_name) and
                __process_std.mem.eql(u8, stub.function_name, function_name) and
                (iat_address == 0 or stub.iat_address == iat_address);
        }
    }
    if (self.windows_stub_count >= self.windows_stub_storage.len) return false;
    // Callers may pass PE parser strings or a GetProcAddress snapshot
    // allocated from the import dispatch arena. A stub outlives both, so
    // keep its names in the Rosette state allocator.
    const owned_dll_name = self.allocator.dupe(u8, dll_name) catch return false;
    const owned_function_name = self.allocator.dupe(u8, function_name) catch {
        self.allocator.free(owned_dll_name);
        return false;
    };
    self.windows_stub_storage[self.windows_stub_count] = .{
        .address = address,
        .dll_name = owned_dll_name,
        .function_name = owned_function_name,
        .iat_address = iat_address,
    };
    self.windows_stub_owned_names[self.windows_stub_count] = true;
    self.windows_stub_count += 1;
    // The box `step` asks before `windowsImportStubAt`. This is the one
    // place a stub address is recorded, so widening here is complete.
    self.windows_stub_box.widen(address);
    // Keep the address decodable if a caller inspects the thunk outside
    // the fast dispatcher check. F4 is the PE route's explicit import
    // sentinel and is intercepted before normal instruction execution.
    process_impl_guest_memory.write8(self, address, 0xF4);
    return true;
}

pub fn windowsImportStubAt(self: *const ElfState, address: u64) ?__process_WindowsImportStub {
    if (self.windows_direct_stub_count != 0) {
        const direct_bytes = __process_std.math.mul(u64, @intCast(self.windows_direct_stub_count), 16) catch return null;
        const direct_end = __process_std.math.add(u64, self.windows_direct_stub_base, direct_bytes) catch return null;
        if (address >= self.windows_direct_stub_base and address < direct_end) {
            const delta = address - self.windows_direct_stub_base;
            if ((delta & 0xF) != 0) return null;
            const index: usize = @intCast(delta >> 4);
            if (index < self.windows_direct_stub_count) {
                const stub = self.windows_stub_storage[index];
                return if (stub.address == address) stub else null;
            }
            return null;
        }
        // Direct PE code lives below the thunk range, while dynamically
        // published proc-address stubs are allocated after that range.
        // This early return is what keeps normal instruction dispatch
        // independent of the total import count.
        if (address < self.windows_direct_stub_base or
            self.windows_stub_count <= self.windows_dynamic_stub_start or
            address < direct_end)
        {
            return null;
        }
    }

    const dynamic_start = @min(self.windows_dynamic_stub_start, self.windows_stub_count);
    for (self.windows_stub_storage[dynamic_start..self.windows_stub_count]) |stub| {
        if (stub.address == address) {
            var dynamic_stub = stub;
            dynamic_stub.is_dynamic = true;
            return dynamic_stub;
        }
    }
    return null;
}

pub fn registerSyntheticThunk(_: *ElfState, _: u64, _: u64, _: []const u8) void {}

pub fn terminateForUnresolvedWindowsImport(self: *ElfState, dll_name: []const u8, function_name: []const u8) void {
    // `tryFunction` can terminate before the import-stub dispatcher sees
    // the result. Make termination idempotent so that both routes record
    // one observation rather than inflating the inventory.
    if (process_impl_lifecycle.isTerminated(self) and self.termination_reason == .unresolved_import_result) return;
    const stub = __process_WindowsImportStub{
        .address = process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        .dll_name = dll_name,
        .function_name = function_name,
        .is_dynamic = windowsImportStubAt(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip) != null and
            windowsImportStubAt(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip).?.is_dynamic,
    };
    _ = process_impl_guest_diagnostics.recordUnresolvedWindowsImport(self, stub);
    self.windows_unknown_import_calls +|= 1;
    process_impl_lifecycle.markFaulted(self);
    self.exit_code = 127;
    self.termination_reason = .unresolved_import_result;
    process_impl_lifecycle.markTerminated(self);
    // Expected refusal tests inspect the recorded fault directly. Keep
    // the production error, without making a negative test fail solely
    // because Zig's test runner counts error-level messages as failures.
    if (comptime !@import("builtin").is_test) __process_log.err("unresolved Windows import: {s}!{s} dynamic={} at rip=0x{x} return=0x{x} caller=0x{x} step={d}", .{
        dll_name,
        function_name,
        stub.is_dynamic,
        process_impl_lifecycle.guestContextField(self, "regs").*.rip,
        process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
        process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
        process_impl_lifecycle.observedExecutionSteps(self),
    });
}

pub fn tryNativeWindowsVulkan(self: *ElfState, name: []const u8, direct_return_rip: ?u64) bool {
    const callback = self.windows_graphics.hooks.native_vulkan_dispatch orelse return false;
    if (name.len == 0) return false;
    if (callback(
        self.windows_graphics.hooks.native_context,
        @ptrCast(self),
        name.ptr,
        name.len,
        direct_return_rip orelse 0,
        if (direct_return_rip != null) 1 else 0,
    ) != 0) return true;
    if (!__process_std.mem.startsWith(u8, name, "vk")) return false;
    // Once a native bridge owns the route, falling back to synthetic
    // handles / successful no-op commands would corrupt the same session.
    if (comptime !@import("builtin").is_test) {
        __process_log.err("PE64 Vulkan native dispatch refused {s}; stopping before synthetic graphics fallback", .{name});
    }
    terminateForUnresolvedWindowsImport(self, "vulkan-1.dll", name);
    return true;
}

pub fn nativeMetalLayerHostPointer(self: *const ElfState) usize {
    const callback = self.windows_graphics.hooks.native_metal_layer_host_pointer orelse return 0;
    return callback(self.windows_graphics.hooks.native_context);
}

pub fn setNativeMetalDrawableOwner(self: *const ElfState, owned_by_swapchain: bool) bool {
    const callback = self.windows_graphics.hooks.native_metal_drawable_owner orelse return false;
    return callback(self.windows_graphics.hooks.native_context, @intFromBool(owned_by_swapchain)) != 0;
}

pub fn prepareNativeMetalDrawable(self: *const ElfState, width: u32, height: u32) bool {
    const callback = self.windows_graphics.hooks.native_metal_drawable_prepare orelse return false;
    return callback(self.windows_graphics.hooks.native_context, width, height) != 0;
}

pub fn validateNativeMetalLayerToken(_: *const ElfState, token: u64) bool {
    return token == 0xCAFE_BABE_0000_0001;
}

pub fn nativeWindowWidth(self: *const ElfState) u32 {
    return self.windows_graphics.window_width;
}

pub fn nativeWindowHeight(self: *const ElfState) u32 {
    return self.windows_graphics.window_height;
}

pub fn noteNativeVulkanSurfaceBound(self: *ElfState, _: u64, _: u64, _: u64) void {
    self.windows_graphics.native_vulkan_forwarding = true;
}
