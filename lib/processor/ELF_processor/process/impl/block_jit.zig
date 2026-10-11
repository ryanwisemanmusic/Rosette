const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_instruction_decode = @import("instruction_decode.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_run_reporting = @import("run_reporting.zig");
const process_impl_windows_sync = @import("windows_sync.zig");
const process_impl_windows_ui = @import("windows_ui.zig");
const __process_BLOCK_JIT_CHAIN_BLOCKS = __ProcessInternals._BLOCK_JIT_CHAIN_BLOCKS;
const __process_BLOCK_JIT_CHAIN_INSTRUCTIONS = __ProcessInternals._BLOCK_JIT_CHAIN_INSTRUCTIONS;
const __process_BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD = __ProcessInternals._BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD;
const __process_BLOCK_JIT_HOOK_FILTER_BYTES = __ProcessInternals._BLOCK_JIT_HOOK_FILTER_BYTES;
const __process_BLOCK_JIT_MAX_CONDITIONALS = __ProcessInternals._BLOCK_JIT_MAX_CONDITIONALS;
const __process_BLOCK_JIT_MAX_INSTRUCTIONS = __ProcessInternals._BLOCK_JIT_MAX_INSTRUCTIONS;
const __process_BLOCK_JIT_PARALLEL_CHAIN_BLOCKS = __ProcessInternals._BLOCK_JIT_PARALLEL_CHAIN_BLOCKS;
const __process_BLOCK_JIT_PARALLEL_CHAIN_INSTRUCTIONS = __ProcessInternals._BLOCK_JIT_PARALLEL_CHAIN_INSTRUCTIONS;
const __process_BLOCK_JIT_WAYS = __ProcessInternals._BLOCK_JIT_WAYS;
const __process_BLOCK_JIT_WORKER_CODE_BYTES = __ProcessInternals._BLOCK_JIT_WORKER_CODE_BYTES;
const __process_BLOCK_JIT_WORKER_MAX_TABLE_ENTRIES = __ProcessInternals._BLOCK_JIT_WORKER_MAX_TABLE_ENTRIES;
const __process_BLOCK_JIT_WORKER_TABLE_ENTRIES = __ProcessInternals._BLOCK_JIT_WORKER_TABLE_ENTRIES;
const __process_BlockHotness = __ProcessInternals._BlockHotness;
const __process_BlockJitCallRefusal = __ProcessInternals._BlockJitCallRefusal;
const __process_BlockJitState = __ProcessInternals._BlockJitState;
const __process_ElfRegs = __ProcessInternals._ElfRegs;
const __process_GuestContextRef = __ProcessInternals._GuestContextRef;
const __process_GuestExecutionGate = __ProcessInternals._GuestExecutionGate;
const __process_GuestSymbol = __ProcessInternals._GuestSymbol;
const __process_PE_MAX_INSTRUCTION_LENGTH = __ProcessInternals._PE_MAX_INSTRUCTION_LENGTH;
const __process_RegId = __ProcessInternals._RegId;
const __process_STACK_COLLAPSE_FLOOR = __ProcessInternals._STACK_COLLAPSE_FLOOR;
const __process_SYNTHETIC_RIP_FLOOR = __ProcessInternals._SYNTHETIC_RIP_FLOOR;
const __process_Size = __ProcessInternals._Size;
const __process_WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE = __ProcessInternals._WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE;
const __process_WINDOWS_GUEST_THREAD_SERVICE_SLICE = __ProcessInternals._WINDOWS_GUEST_THREAD_SERVICE_SLICE;
const __process_WINDOWS_NULL_PAGE_LIMIT = __ProcessInternals._WINDOWS_NULL_PAGE_LIMIT;
const __process_WindowsGuestThreadStatus = __ProcessInternals._WindowsGuestThreadStatus;
const __process_WindowsMappedCodeSlice = __ProcessInternals._WindowsMappedCodeSlice;
const __process_blockJitFlags = __ProcessInternals._blockJitFlags;
const __process_blockJitHookedTransfer = __ProcessInternals._blockJitHookedTransfer;
const __process_blockJitImportTransfer = __ProcessInternals._blockJitImportTransfer;
const __process_blockJitInterpret = __ProcessInternals._blockJitInterpret;
const __process_blockJitMappedTransferAllowed = __ProcessInternals._blockJitMappedTransferAllowed;
const __process_blockJitRead = __ProcessInternals._blockJitRead;
const __process_blockJitRead128 = __ProcessInternals._blockJitRead128;
const __process_blockJitWrite = __ProcessInternals._blockJitWrite;
const __process_blockJitWrite128 = __ProcessInternals._blockJitWrite128;
const __process_blockJitWrite128NonTemporal = __ProcessInternals._blockJitWrite128NonTemporal;
const __process_blockJitX87Memory = __ProcessInternals._blockJitX87Memory;
const __process_blockJitX87RawTransfer = __ProcessInternals._blockJitX87RawTransfer;
const __process_block_jit = __ProcessInternals._block_jit;
const __process_block_jit_refusal_retry_base = __ProcessInternals._block_jit_refusal_retry_base;
const __process_block_jit_refusal_retry_limit = __ProcessInternals._block_jit_refusal_retry_limit;
const __process_block_verify = __ProcessInternals._block_verify;
const __process_concurrency = __ProcessInternals._concurrency;
const __process_coordinated_decode_cache_mutex = __ProcessInternals._coordinated_decode_cache_mutex;
const __process_decodeInsn = __ProcessInternals._decodeInsn;
const __process_envU64 = __ProcessInternals._envU64;
const __process_guestMilestoneSaturable = __ProcessInternals._guestMilestoneSaturable;
const __process_guest_page_protection = __ProcessInternals._guest_page_protection;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_host_fp_control = __ProcessInternals._host_fp_control;
const __process_import_lock_requested_ns = __ProcessInternals._import_lock_requested_ns;
const __process_isHostMainThread = __ProcessInternals._isHostMainThread;
const __process_isLiveWindowsGuestThread = __ProcessInternals._isLiveWindowsGuestThread;
const __process_kernel_call_census = __ProcessInternals._kernel_call_census;
const __process_log = __ProcessInternals._log;
const __process_mapped_ranges = __ProcessInternals._mapped_ranges;
const __process_monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const __process_parallel_diagnostics = __ProcessInternals._parallel_diagnostics;
const __process_shouldTraceRip = __ProcessInternals._shouldTraceRip;
const __process_std = __ProcessInternals._std;
const __process_tlb_diagnostics = __ProcessInternals._tlb_diagnostics;
const __process_tso_memory = __ProcessInternals._tso_memory;
const __process_windows_guest_execution_binding = __ProcessInternals._windows_guest_execution_binding;
const __process_x64_decoder = __ProcessInternals._x64_decoder;
const __process_x64_interpreter = __ProcessInternals._x64_interpreter;
const __process_x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const __state_BlockJitFallbackView = __StateInternals._BlockJitFallbackView;
const __state_FoundBlock = __StateInternals._FoundBlock;
const __state_InstructionSource = __StateInternals._InstructionSource;
const __state_RuntimeLockHolder = __StateInternals._RuntimeLockHolder;
const __state_block_jit_layout = __StateInternals._block_jit_layout;
const __state_op_names = __StateInternals._op_names;
const __state_op_value_limit = __StateInternals._op_value_limit;
const __state_windows_memory_trace_floor = __StateInternals._windows_memory_trace_floor;

pub fn refreshBlockJitTransferTraced(self: *ElfState) void {
    self.block_jit_transfer_traced = self.trace_windows_messages or self.trace_windows_threads;
}

pub fn blockJitTracingActive(self: *const ElfState) bool {
    return self.trace_rip_start != null or self.trace_ring_enabled or self.trace_string_memory or
        self.trace_formatter or self.trace_vector or self.trace_utf8;
}

pub fn parallelWorkerSlot(self: *ElfState) ?usize {
    if (!self.parallel_guest_execution) return null;
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* orelse return null;
    return if (slot < self.windows_guest_threads.len) slot else null;
}

pub fn currentBlockJit(self: *ElfState) ?*__process_BlockJitState {
    if (parallelWorkerSlot(self)) |slot| return self.windows_guest_threads[slot].parallel_block_jit;
    return self.block_jit;
}

pub fn forEachBlockJitState(self: *ElfState, context: anytype, comptime visit: fn (@TypeOf(context), *ElfState, *__process_BlockJitState) void) void {
    if (self.block_jit) |jit| visit(context, self, jit);
    for (self.windows_guest_threads) |*thread| {
        if (thread.parallel_block_jit) |jit| visit(context, self, jit);
    }
}

pub fn blockJitActive(self: *ElfState) ?*__process_BlockJitState {
    if (parallelWorkerSlot(self)) |slot| return parallelWorkerBlockJit(self, slot);
    // The SaveConfig formatter probe must see every register and memory
    // transition between fmt::vformat entry and return. Keep only that
    // short, explicitly armed call on the interpreter path.
    const rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    if (self.windows_fmt_probe_active or self.windows_fmt_vformat_entry == rip or
        self.windows_fmt_vformat_to_entry == rip or self.windows_fmt_vformat_return == rip or
        self.windows_fmt_vformat_to_return == rip) return null;
    if (self.block_jit) |jit| return jit;
    if (!self.block_jit_enabled or self.block_jit_unavailable) return null;
    if (blockJitTracingActive(self)) {
        self.block_jit_unavailable = true;
        self.block_jit_disabled_reason = "per-instruction tracing is on";
        return null;
    }
    const jit = __process_BlockJitState.create(self.allocator) orelse {
        self.block_jit_unavailable = true;
        self.block_jit_disabled_reason = "executable memory could not be mapped (MAP_JIT refused or out of memory)";
        __process_log.info("PE64 BLOCK JIT: disabled, {s}; the interpreter runs everything", .{self.block_jit_disabled_reason});
        return null;
    };
    jit.hot_threshold = self.block_jit_hot_threshold;
    self.block_jit = jit;
    // Parallel mode built the filter under its stop-the-world; rebuilding
    // it here would rewrite a table other threads' translated code reads.
    if (!self.parallel_guest_execution) rebuildBlockJitHookFilter(self);
    return jit;
}

pub fn parallelWorkerBlockJit(self: *ElfState, slot: usize) ?*__process_BlockJitState {
    const thread = &self.windows_guest_threads[slot];
    const rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    if (self.windows_fmt_probe_active or self.windows_fmt_vformat_entry == rip or
        self.windows_fmt_vformat_to_entry == rip or self.windows_fmt_vformat_return == rip or
        self.windows_fmt_vformat_to_return == rip) return null;
    if (thread.parallel_block_jit) |jit| return jit;
    if (!self.block_jit_enabled or self.block_jit_unavailable or thread.parallel_block_jit_refused) return null;
    if (blockJitTracingActive(self)) return null;
    const jit = __process_BlockJitState.createSized(self.allocator, __process_BLOCK_JIT_WORKER_TABLE_ENTRIES, __process_BLOCK_JIT_WORKER_CODE_BYTES) orelse {
        thread.parallel_block_jit_refused = true;
        __process_log.info("PE64 BLOCK JIT: guest thread slot {d} stays interpreted: its translation cache could not be mapped", .{slot});
        return null;
    };
    jit.hot_threshold = self.block_jit_hot_threshold;
    jit.max_entries = __process_BLOCK_JIT_WORKER_MAX_TABLE_ENTRIES;
    thread.parallel_block_jit = jit;
    return jit;
}

pub fn rebuildBlockJitHookFilter(self: *ElfState) void {
    self.block_jit_hook_filter_rebuilding = true;
    defer self.block_jit_hook_filter_rebuilding = false;
    process_impl_execution.resolveXeniaAcceleratorTargets(self);
    publishBlockJitHookFilter(self);
    // An accelerator acts only on the Windows runtime, where the
    // resolution above has just run; one that cannot act hooks nothing.
    const unresolved_accelerator = self.windows_runtime_enabled and
        ((self.xenia_sha1_accelerator_enabled and !self.xenia_sha1_target_checked) or
            (self.xenia_rijndael_accelerator_enabled and !self.xenia_rijndael_target_checked) or
            (self.xenia_tabulate_accelerator_enabled and !self.xenia_tabulate_target_checked));
    self.block_jit_image_targets_hooked = @intFromBool(self.local_symbols.len != 0 or unresolved_accelerator or self.trace_windows_threads);
}

pub fn publishBlockJitHookFilter(self: *ElfState) void {
    self.block_jit_hook_filter_mutex.lock();
    defer self.block_jit_hook_filter_mutex.unlock();
    var filter: [__process_BLOCK_JIT_HOOK_FILTER_BYTES]u8 = @splat(0);
    for (self.guest_kernel_calls.slots) |*slot| {
        if (slot.address == 0) continue;
        if (@atomicLoad(__process_kernel_call_census.Saturation, &slot.saturation, .acquire) == .saturated) continue;
        __process_block_jit.hookFilterAdd(&filter, slot.address);
    }
    for (self.guest_milestone_addresses) |address| {
        if (address != 0) __process_block_jit.hookFilterAdd(&filter, address);
    }
    for (self.call_probes.probes[0..self.call_probes.count]) |probe| {
        __process_block_jit.hookFilterAdd(&filter, probe.address);
    }
    inline for (.{
        "windows_pthread_cond_wait_entry",
        "windows_pthread_cond_signal_entry",
        "windows_pthread_cond_broadcast_entry",
        "windows_pthread_cond_timedwait_entry",
        "windows_utf8_find_any_of_entry",
        "windows_codecvt_in_entry",
        "windows_utf8_count_entry",
        "windows_cxa_throw_entry",
        "windows_fmt_vformat_entry",
        "windows_fmt_vformat_to_entry",
        "windows_fmt_vformat_return",
        "windows_fmt_vformat_to_return",
        "xenia_sha1_target",
        "xenia_rijndael_target",
        "xenia_tabulate_target",
    }) |field| {
        if (@field(self, field)) |address| __process_block_jit.hookFilterAdd(&filter, address);
    }
    for (&self.block_jit_hook_filter, filter) |*byte, value| {
        if (@atomicLoad(u8, byte, .monotonic) != value) @atomicStore(u8, byte, value, .release);
    }
}

pub fn blockJitRequestAbort(self: *ElfState) void {
    const scratch = process_impl_lifecycle.guestContextField(self, "block_jit_scratch");
    scratch.abort = 1;
    // The native chain checks only `chain_break` between blocks.
    scratch.chain_break = 1;
    if (currentBlockJit(self)) |jit| jit.aborts +|= 1;
}

pub fn blockJitNameCurrentInstruction(self: *ElfState) void {
    const block = process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.block orelse return;
    const index = process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.index;
    if (index >= block.insns.len) return;
    const insn = block.insns[index];
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = insn.rip;
    process_impl_lifecycle.guestContextField(self, "last_instruction_rip").* = insn.rip;
    process_impl_lifecycle.guestContextField(self, "last_decoded_op").* = insn.decoded.op;
    process_impl_lifecycle.guestContextField(self, "last_decoded_len").* = insn.len;
}

pub fn blockJitExecuteInsn(self: *ElfState, block: *const __process_block_jit.Block, index: u32) void {
    const insn = block.insns[index];
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = insn.rip;
    var d = insn.decoded;
    d.segment = insn.segment;
    const addr_size: __process_Size = if (d.has_0x67) .bits32 else .bits64;
    const relative_control = switch (d.op) {
        .call_rel32, .jmp_rel8, .jcc_rel8, .jcc_rel32 => true,
        else => false,
    };
    if (!relative_control and !d.is_reg_form) {
        d.addr = __process_x64_decoder.resolveMemoryAddress(&process_impl_lifecycle.guestContextField(self, "regs").*, .{
            .displacement = d.addr,
            .has_index = d.sib_has_index,
            .index_reg = d.sib_index_reg,
            .scale = d.sib_scale,
            .has_base = d.sib_has_base,
            .base_reg = d.sib_base_reg,
            .rip_relative = d.rip_relative,
            .segment = d.segment,
        }, process_impl_lifecycle.guestContextField(self, "regs").*.rip +% d.len, addr_size, .long64, d.op != .lea_reg_mem);
    }
    process_impl_lifecycle.guestContextField(self, "last_decoded_op").* = d.op;
    process_impl_lifecycle.guestContextField(self, "last_decoded_len").* = d.len;
    process_impl_lifecycle.guestContextField(self, "last_instruction_rip").* = insn.rip;
    __process_x64_interpreter.execute(self, d);
}

pub fn fetchInstructionSource(self: *ElfState, address: u64) ?__state_InstructionSource {
    if (process_impl_guest_memory.addrToOffset(self, address)) |off| {
        const offset: usize = @intCast(off);
        if (offset >= self.mem.len) return null;
        const count = @min(self.mem.len - offset, __process_PE_MAX_INSTRUCTION_LENGTH);
        var source: __state_InstructionSource = .{ .len = count, .mapped = null };
        process_impl_guest_memory.snapshotGuestBacking(self, source.storage[0..count], self.mem[offset..][0..count]);
        return source;
    }
    if (process_impl_guest_memory.windowsMappedCodeMemoryConst(self, address, __process_PE_MAX_INSTRUCTION_LENGTH)) |generated| {
        noteMappedCodeFetched(self, generated);
        const count = @min(generated.bytes.len, __process_PE_MAX_INSTRUCTION_LENGTH);
        var source: __state_InstructionSource = .{ .len = count, .mapped = generated };
        process_impl_guest_memory.snapshotGuestBacking(self, source.storage[0..count], generated.bytes[0..count]);
        return source;
    }
    return null;
}

pub fn fetchCodeRange(self: *const ElfState, address: u64, count: usize) ?[]const u8 {
    if (process_impl_guest_memory.addrToOffset(self, address)) |off| {
        const offset: usize = @intCast(off);
        if (offset >= self.mem.len or count > self.mem.len - offset) return null;
        return self.mem[offset..][0..count];
    }
    return process_impl_guest_memory.windowsMappedMemoryConst(self, address, count);
}

pub fn copyGuestCode(self: *const ElfState, destination: []u8, source: []const u8) void {
    if (self.parallel_guest_execution) {
        __process_tso_memory.copyInCoordinated(destination, source);
    } else {
        @memcpy(destination, source[0..destination.len]);
    }
}

pub fn guestCodeRangeMatches(self: *const ElfState, address: u64, expected: []const u8) bool {
    const source = fetchCodeRange(self, address, expected.len) orelse return false;
    if (!self.parallel_guest_execution) return __process_std.mem.eql(u8, source, expected);

    var snapshot: [64]u8 = undefined;
    var copied: usize = 0;
    while (copied < expected.len) {
        const count = @min(snapshot.len, expected.len - copied);
        copyGuestCode(self, snapshot[0..count], source[copied..][0..count]);
        if (!__process_std.mem.eql(u8, snapshot[0..count], expected[copied..][0..count])) return false;
        copied += count;
    }
    return true;
}

pub fn blockJitTargetHooked(self: *const ElfState, target: u64) bool {
    if (target >= __process_SYNTHETIC_RIP_FLOOR) return true;
    if (self.call_probes.indexOf(target) != null) return true;
    if (self.windows_stub_box.contains(target) or self.windows_compat_hook_points.contains(target)) return true;
    // All four condition entries, not only the timed wait. libstdc++'s
    // `condition_variable::wait` and `notify_one` are tail jumps into
    // winpthreads, and the interpreter's jump arm is where the condition
    // shim takes them. A translated jump went straight into the real
    // winpthreads body instead, so one side of a condition ran in
    // Rosette's model and the other in winpthreads' semaphores: on
    // 2026-09-21 the Shader Storage Writer never saw
    // `ShutdownShaderStorage`'s notify, the GPU thread's join on it
    // never returned, and Halo 3 stopped swapping between the Bungie
    // logo and the title screen.
    inline for (.{
        "windows_pthread_cond_wait_entry",
        "windows_pthread_cond_signal_entry",
        "windows_pthread_cond_broadcast_entry",
        "windows_pthread_cond_timedwait_entry",
    }) |field| {
        if (@field(self, field)) |entry| {
            if (target == entry) return true;
        }
    }
    return false;
}

pub fn blockJitIndirectTargetHooked(self: *const ElfState, target: u64) bool {
    if (blockJitTargetHooked(self, target) or process_impl_guest_diagnostics.isGuestMilestoneAddress(self, target)) return true;
    if (self.guest_kernel_calls.exportAt(target)) |slot| {
        if (@atomicLoad(__process_kernel_call_census.Saturation, &slot.saturation, .acquire) != .saturated) return true;
    }
    inline for (.{
        "windows_utf8_find_any_of_entry",
        "windows_codecvt_in_entry",
        "windows_utf8_count_entry",
        "windows_cxa_throw_entry",
        "windows_fmt_vformat_entry",
        "windows_fmt_vformat_to_entry",
        "windows_fmt_vformat_return",
        "windows_fmt_vformat_to_return",
        "xenia_sha1_target",
        "xenia_rijndael_target",
        "xenia_tabulate_target",
    }) |field| {
        if (@field(self, field)) |address| {
            if (address == target) return true;
        }
    }
    return false;
}

pub fn blockJitGenerationPointer(self: *ElfState, mapped: bool, kind: u8, index: usize) ?*const u64 {
    if (!mapped) return &self.windows_image_code_generation;
    return switch (@as(__process_mapped_ranges.Kind, @enumFromInt(kind))) {
        .memory_view => if (index < self.windows_file_mappings.len) &self.windows_file_mappings[index].code_generation else null,
        .virtual_allocation => if (index < self.windows_virtual_allocations.len) &self.windows_virtual_allocations[index].code_generation else null,
    };
}

pub fn blockJitSourceGeneration(self: *ElfState, block: *const __process_block_jit.Block) ?u64 {
    if (!block.source_mapped) return process_impl_guest_memory.windowsImageCodeGenerationFor(self, block.start_rip, block.bytes.len);
    // The word of the page the block starts on, or the mapping's own
    // when the page table did not exist yet.
    return process_impl_guest_memory.loadCodeGeneration(block.generation_ptr orelse return null);
}

pub fn blockJitContinuationChanged(self: *ElfState) bool {
    const block = process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.block orelse return false;
    const index = process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.index;
    if (index + 1 >= block.insns.len) return false;
    const current = blockJitSourceGeneration(self, block);
    if (current != null and block.source_generation != null and current.? == block.source_generation.?) return false;
    const next = block.insns[index + 1].rip;
    const offset: usize = @intCast(next - block.start_rip);
    const changed = !guestCodeRangeMatches(self, next, block.bytes[offset..]);
    if (changed) if (currentBlockJit(self)) |jit| {
        jit.continuation_write_aborts +|= 1;
    };
    return changed;
}

pub fn blockJitValidate(self: *ElfState, jit: *__process_BlockJitState, block: *__process_block_jit.Block) bool {
    const current = blockJitSourceGeneration(self, block);
    if (block.source_generation != null and current != null and block.source_generation.? == current.?) return true;
    if (!guestCodeRangeMatches(self, block.start_rip, block.bytes)) return false;
    block.source_generation = current;
    // Hops prove the generation the bytes were just proven at.
    blockJitArmChain(block);
    jit.revalidations +|= 1;
    return true;
}

pub fn dropBlockJitSlot(self: *ElfState, jit: *__process_BlockJitState, index: usize) void {
    if (jit.blocks[index]) |block| {
        jit.blocks[index] = null;
        jit.invalidations +|= 1;
        jit.lifetime.retire(self.allocator, block);
    }
}

pub fn leaveBlockJitExecution(self: *ElfState, jit: *__process_BlockJitState) void {
    if (jit.lifetime.leave(self.allocator)) resetBlockJit(self, jit);
}

pub fn blockJitFind(self: *ElfState, rip: u64) ?*__process_block_jit.Block {
    const jit = currentBlockJit(self) orelse return null;
    const base = jit.firstSlot(rip);
    for (jit.blocks[base .. base + __process_BLOCK_JIT_WAYS]) |slot| {
        if (slot) |block| if (block.start_rip == rip) return block;
    }
    return null;
}

pub fn blockJitHotness(jit: *__process_BlockJitState, rip: u64) *__process_BlockHotness {
    const base = jit.firstSlot(rip);
    var coldest = base;
    for (base..base + __process_BLOCK_JIT_WAYS) |slot| {
        const entry = &jit.hotness[slot];
        if (entry.rip == rip) return entry;
        if (entry.rip == 0) {
            coldest = slot;
            break;
        }
        if (entry.count < jit.hotness[coldest].count) coldest = slot;
    }
    // Taking a counting entry from another address is the thrash that
    // keeps both on the interpreter; one still warming up is pressure.
    const replaced = jit.hotness[coldest];
    if (replaced.rip != 0 and replaced.count != 0 and !replaced.refused) {
        jit.hotness_replacements +|= 1;
        if (replaced.count < jit.hot_threshold) jit.pressure +|= 1;
    }
    jit.hotness[coldest] = .{ .rip = rip, .count = 0 };
    return &jit.hotness[coldest];
}

pub fn blockJitRefuse(jit: *__process_BlockJitState, rip: u64) void {
    const hot = blockJitHotness(jit, rip);
    hot.* = .{ .rip = rip, .count = 0, .refused = true, .retries = __process_block_jit_refusal_retry_limit };
}

pub fn reportBlockJitRefusals(self: *const ElfState, slot: usize, jit: *const __process_BlockJitState) void {
    if (jit.compile_refusals == 0) return;
    var sites: [768]u8 = undefined;
    var used: usize = 0;
    for (jit.refusal_sites[0..jit.refusal_site_count]) |site| {
        var name_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        const piece = __process_std.fmt.bufPrint(sites[used..], " 0x{x}({s}):{s}:{s}:retries={d}", .{
            site.rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, site.rip, &name_text),
            @tagName(site.reason),
            @tagName(site.op),
            site.retries,
        }) catch break;
        used += piece.len;
    }
    const reasons = jit.refusal_reasons;
    __process_log.info("PE64 BLOCK JIT WORKER THREAD:   slot={d} refusals={d} reasons(empty_fetch/decode_failed/ends_before/page_identity/nothing_to_compile/compile_error/allocation)={d}/{d}/{d}/{d}/{d}/{d}/{d} retries={d} first:{s}; a refused address is interpreted at every execution until a retry compiles it", .{
        slot,
        jit.compile_refusals,
        reasons[0],
        reasons[1],
        reasons[2],
        reasons[3],
        reasons[4],
        reasons[5],
        reasons[6],
        jit.refusal_retries,
        sites[0..used],
    });
}

pub fn noteBlockJitRefusal(jit: *__process_BlockJitState, rip: u64, retries: u8) void {
    jit.refusal_reasons[@intFromEnum(jit.last_refusal)] +|= 1;
    if (jit.refusal_site_count >= jit.refusal_sites.len) return;
    for (jit.refusal_sites[0..jit.refusal_site_count]) |*site| {
        if (site.rip == rip) {
            site.retries = retries;
            site.reason = jit.last_refusal;
            return;
        }
    }
    jit.refusal_sites[jit.refusal_site_count] = .{ .rip = rip, .reason = jit.last_refusal, .op = jit.last_refusal_op, .retries = retries };
    jit.refusal_site_count += 1;
}

pub fn resetBlockJit(self: *ElfState, jit: *__process_BlockJitState) void {
    // Code an outer block is still running lives in this memory; the
    // outermost execution's return runs the reset instead.
    if (!jit.lifetime.requestReset()) return;
    for (jit.blocks, 0..) |slot, index| {
        if (slot != null) {
            dropBlockJitSlot(self, jit, index);
            jit.dropped_reset +|= 1;
        }
    }
    jit.memory.reset();
    jit.resets +|= 1;
}

pub fn blockJitDropMappedSource(self: *ElfState, kind: __process_mapped_ranges.Kind, source_index: usize) void {
    const Source = struct { kind: __process_mapped_ranges.Kind, index: usize };
    forEachBlockJitState(self, Source{ .kind = kind, .index = source_index }, struct {
        fn visit(source: Source, state: *ElfState, jit: *__process_BlockJitState) void {
            for (jit.blocks, 0..) |slot, index| {
                if (slot) |block| {
                    if (block.source_mapped and block.source_kind == @intFromEnum(source.kind) and block.source_index == source.index) {
                        dropBlockJitSlot(state, jit, index);
                        jit.dropped_unmapped +|= 1;
                    }
                }
            }
        }
    }.visit);
}

pub fn blockJitDropAllMapped(self: *ElfState) void {
    forEachBlockJitState(self, {}, struct {
        fn visit(_: void, state: *ElfState, jit: *__process_BlockJitState) void {
            for (jit.blocks, 0..) |slot, index| {
                if (slot) |block| if (block.source_mapped) {
                    dropBlockJitSlot(state, jit, index);
                    jit.dropped_unmapped +|= 1;
                };
            }
        }
    }.visit);
}

pub fn blockJitDropAll(self: *ElfState) void {
    forEachBlockJitState(self, {}, struct {
        fn visit(_: void, state: *ElfState, jit: *__process_BlockJitState) void {
            for (jit.blocks, 0..) |slot, index| {
                if (slot != null) {
                    dropBlockJitSlot(state, jit, index);
                    jit.dropped_reset +|= 1;
                }
            }
        }
    }.visit);
}

pub fn traceWithholdsWriteTlb(self: *ElfState, page: u64) bool {
    const page_bytes = __process_block_jit.Tlb.page_bytes;
    if (self.spin_watch.pageWatched(page, page_bytes)) return true;
    // A watched address has no budget: it must see stores all run long.
    if (self.trace_write_address) |watch| {
        if (watch < page +| page_bytes and watch +| 8 > page) return true;
    }
    if (!self.trace_windows_memory or self.windows_memory_trace_step_closed.load(.monotonic)) return false;
    if (page +| page_bytes <= __state_windows_memory_trace_floor or process_impl_guest_memory.addrToOffset(self, page) != null) return false;
    return process_impl_guest_memory.windowsMemoryTraceLive(self);
}

pub fn noteBlockJitTlbRefusal(
    jit: *__process_BlockJitState,
    reason: __process_tlb_diagnostics.RefusalReason,
    page: u64,
    is_write: bool,
    epoch: u64,
    cacheable: bool,
) void {
    jit.tlb_fill_refusals +|= 1;
    jit.tlb_refusal_stats.record(reason, page);
    if (cacheable) jit.tlb_refusal_cache.record(page, is_write, epoch, reason);
}

pub fn blockJitTlbConsider(self: *ElfState, address: u64, width: u8, is_write: bool) void {
    const parallel = self.parallel_guest_execution;
    if (parallel and !parallelDirectTlbActive(self)) return;
    // A parallel fill is judged against this instant's protection and
    // mapping state. An invalidation landing after the judgement moves
    // the epoch before it retires anything, and the fill below retires
    // its own entry when it sees the epoch moved.
    const epoch = if (parallel) self.block_jit_tlb_epoch.load(.seq_cst) else 0;
    if (!parallel) self.block_jit_tlb_considers +|= 1;
    const jit = tlbFillBlockJit(self) orelse return;
    if (!self.block_jit_tlb_enabled) return;
    // Both store traces are *store* traces, so neither has any claim on
    // the read TLB, and the mapped-write one spends a fixed budget in the
    // first moments of a run and is inert for the rest of it. This guard
    // used to refuse every page for either trace, for the whole run: the
    // Xenia script exports ROSETTE_ELF_TRACE_WINDOWS_MEMORY=1 by default,
    // so on 2026-09-19 all 35,716,669,305 admissions were refused here and
    // every load and store inside translated code took the helper.
    const page_bytes = __process_block_jit.Tlb.page_bytes;
    const page = address & ~(page_bytes - 1);
    if (is_write and traceWithholdsWriteTlb(self, page)) {
        bumpTlbCounter(self, &self.block_jit_tlb_bail_traced);
        return;
    }
    if ((address & (page_bytes - 1)) + width > page_bytes) {
        bumpTlbCounter(self, &self.block_jit_tlb_bail_straddle);
        return;
    }
    if (self.windows_runtime_enabled and page < __process_WINDOWS_NULL_PAGE_LIMIT) {
        bumpTlbCounter(self, &self.block_jit_tlb_bail_null_page);
        return;
    }
    // Repeated helper misses revisit a small set of pages. Remember only
    // stable refusals per executor so it need not repeat mapping proofs on
    // every access. Complete aligned native-map pages can pass the alias
    // proof below in parallel direct mode; partial or otherwise refused
    // mappings remain on the ordered, class-aware helper path.
    if (parallel) {
        if (jit.tlb_refusal_cache.lookup(page, is_write, epoch)) |reason| {
            noteBlockJitTlbRefusal(jit, reason, page, is_write, epoch, false);
            return;
        }
    }
    if (self.guest_page_protection.isActive()) {
        const protection = self.guest_page_protection.get(page);
        if (protection == .no_access) {
            noteBlockJitTlbRefusal(jit, .guest_no_access, page, is_write, epoch, parallel);
            return;
        }
        if (is_write and protection != .accessible) {
            noteBlockJitTlbRefusal(jit, .guest_write_protected, page, is_write, epoch, parallel);
            return;
        }
    }
    const host: [*]u8 = blk: {
        // A real Vulkan vkMapMemory result is already the CPU-visible
        // backing for this guest range. In the parallel direct-TLB mode
        // every executor has no guest store queue (see
        // activeGuestTsoStoreBuffer), and emitted scalar/vector lanes use
        // acquire/release operations. That preserves the synchronous
        // device-access ordering without taking a stripe and crossing
        // the helper on every access. Vulkan's explicit flush/invalidate,
        // queue, and fence calls still go through the forwarding layer.
        // Require a whole backed page: a partial first/last map page must
        // not expose bytes outside Vulkan's valid mapped interval.
        if (process_impl_guest_memory.nativeMemoryAlias(self, page, page_bytes)) |alias_page| {
            const host_page_mask: usize = @intCast(page_bytes - 1);
            if (!parallelDirectTlbActive(self) or @intFromPtr(alias_page.ptr) & host_page_mask != 0) {
                noteBlockJitTlbRefusal(jit, .native_device_alias, page, is_write, epoch, parallel);
                return;
            }
            break :blk alias_page.ptr;
        }
        if (process_impl_guest_memory.addrToOffset(self, page)) |off| {
            const offset: usize = @intCast(off);
            if (offset + page_bytes > self.mem.len) {
                noteBlockJitTlbRefusal(jit, .process_backing_bounds, page, is_write, epoch, parallel);
                return;
            }
            // The exact executable ranges, not their bounding box: the
            // box runs from .text to .cold across .rdata and .data, so
            // it refused every write to Xenia's globals - its global
            // critical region's mutex among them, taken 1.65 million
            // times on 2026-09-30 - and sent each through the helper.
            if (is_write and process_impl_guest_memory.windowsImageRangeOverlapsCode(self, page, page_bytes)) {
                noteBlockJitTlbRefusal(jit, .executable_image_write, page, is_write, epoch, parallel);
                return;
            }
            break :blk self.mem.ptr + offset;
        }
        if (self.windows_mapped_ranges.find(page, page_bytes)) |range| {
            if (is_write and mappedRangeCodeFetched(self, range)) {
                noteBlockJitTlbRefusal(jit, .mapped_code_write, page, is_write, epoch, parallel);
                return;
            }
            const slice = process_impl_guest_memory.windowsIndexedMemory(self, page, page_bytes) orelse {
                noteBlockJitTlbRefusal(jit, .mapped_range_unbacked, page, is_write, epoch, parallel);
                return;
            };
            break :blk @constCast(slice.bytes.ptr);
        }
        noteBlockJitTlbRefusal(jit, .unmapped_page, page, is_write, epoch, parallel);
        return;
    };
    const tlb = activeBlockJitTlb(self);
    if (parallel) {
        tlb.fillOrdered(is_write, page, host);
        if (self.block_jit_tlb_epoch.load(.seq_cst) != epoch) {
            tlb.retireOrdered(is_write, page);
            _ = self.parallel_tlb_raced_fills.fetchAdd(1, .monotonic);
            return;
        }
    } else {
        tlb.fill(is_write, page, host);
    }
    jit.tlb_fills +|= 1;
}

pub fn activeBlockJitTlb(self: *ElfState) *__process_block_jit.Tlb {
    const owner: *anyopaque = @ptrCast(self);
    if (__ProcessInternals._windows_guest_execution_binding().*) |binding| {
        if (binding.owner == owner) {
            if (binding.context.block_jit_tlb) |tlb| return tlb;
        }
    }
    return self.block_jit_tlb_active orelse ownerBlockJitTlb(self);
}

pub fn ownerBlockJitTlb(self: *ElfState) *__process_block_jit.Tlb {
    return self.block_jit_tlb orelse unreachable;
}

pub fn guestProcessorMask() u64 {
    const requested: ?u64 = blk: {
        const raw = __process_std.c.getenv("ROSETTE_PE64_GUEST_CPUS") orelse break :blk null;
        const value = __process_std.fmt.parseUnsigned(u64, __process_std.mem.sliceTo(raw, 0), 10) catch break :blk null;
        break :blk if (value == 0) null else value;
    };
    const host: u64 = @intCast(__process_std.Thread.getCpuCount() catch 1);
    const count = @min(requested orelse host, 64);
    return if (count >= 64) __process_std.math.maxInt(u64) else (@as(u64, 1) << @intCast(count)) - 1;
}

pub fn parallelGuestExecutionRequested() bool {
    const raw = __process_std.c.getenv("ROSETTE_PE64_PARALLEL") orelse return true;
    const text = __process_std.mem.sliceTo(raw, 0);
    return !(__process_std.mem.eql(u8, text, "0") or __process_std.ascii.eqlIgnoreCase(text, "false") or __process_std.ascii.eqlIgnoreCase(text, "off"));
}

pub fn parallelStallThresholdNanoseconds() u64 {
    const seconds = __process_envU64("ROSETTE_PE64_STALL_SECONDS") orelse 10;
    if (seconds == 0) return __process_std.math.maxInt(u64);
    return seconds *| __process_std.time.ns_per_s;
}

pub fn parallelThreadPulseNanoseconds() u64 {
    const seconds = __process_envU64("ROSETTE_PE64_THREAD_PULSE_SECONDS") orelse 5;
    return seconds *| __process_std.time.ns_per_s;
}

pub fn parallelLockHoldThresholdNanoseconds() u64 {
    const seconds = __process_envU64("ROSETTE_PE64_LOCK_HOLD_SECONDS") orelse 3;
    if (seconds == 0) return __process_std.math.maxInt(u64);
    return seconds *| __process_std.time.ns_per_s;
}

pub fn installMainThreadParkService(self: *ElfState) ?__process_concurrency.Service {
    const previous = __process_concurrency.park.currentService();
    if (self.windows_graphics.hooks.service_main_thread == null or !__process_isHostMainThread()) return previous;
    _ = __process_concurrency.park.installService(.{ .context = @ptrCast(self), .run = serviceMainThreadFromPark });
    return previous;
}

pub fn serviceMainThreadFromPark(context: ?*anyopaque) void {
    const self: *ElfState = @ptrCast(@alignCast(context orelse return));
    const service = self.windows_graphics.hooks.service_main_thread orelse return;
    _ = service(self.windows_graphics.hooks.context);
}

pub fn concurrencyProgress(context: ?*anyopaque) u64 {
    const self: *const ElfState = @ptrCast(@alignCast(context orelse return 0));
    return process_impl_lifecycle.observedExecutionSteps(self);
}

pub fn reportConcurrencyStall(context: ?*anyopaque, finding: *const __process_concurrency.stall.Report) void {
    if (comptime @import("builtin").is_test) return;
    const self: *ElfState = @ptrCast(@alignCast(context orelse return));
    const gate = finding.gate orelse self.guest_execution_gate.snapshot();
    const holder_id = self.windows_runtime_mutex.inner.holder.load(.monotonic);
    var holder_buffer: [96]u8 = undefined;
    const holder = runtimeLockHolderDescription(holder_id, &holder_buffer);
    __process_log.err("PE64 CONCURRENCY STALL: kind={s} guest_progress_unchanged_ms={d} instructions={d} stop_the_world(active/holder/held_ms/waiting_for)={}/0x{x}/{d}/0x{x} host_threads(registered/inside)={d}/{d} runtime_mutex_holder=0x{x} ('{s}' in '{s}', held_without_release_ms={d}); every watched thread's state follows. A thread waiting on the main thread while the main thread waits on a lock that thread holds is a deadlock; the main thread's park service exists to make that impossible. runtime_lock_held means one call has kept the runtime lock that long: every other thread's next import is queued behind it", .{
        @tagName(finding.kind),
        finding.stalled_ns / __process_std.time.ns_per_ms,
        finding.progress,
        gate.stopping,
        gate.holder,
        gate.held_for_ns / __process_std.time.ns_per_ms,
        gate.waiting_for,
        gate.executors,
        gate.inside_now,
        holder_id,
        holder.name,
        holder.activity,
        finding.lock_held_ns / __process_std.time.ns_per_ms,
    });
    var main_waiters: u32 = 0;
    for (__process_concurrency.watch.allRecords()) |*record| {
        if (record.currentState() == .vacant) continue;
        const waiting_on = record.label();
        if (record.currentState() == .parked and __process_std.mem.startsWith(u8, waiting_on, "AppKit request")) main_waiters += 1;
        var activity_buffer: [96]u8 = undefined;
        const activity = record.activity(&activity_buffer);
        __process_log.err("PE64 CONCURRENCY STALL:   thread '{s}' id=0x{x} state={s} doing='{s}' doing_ms={d} waiting_on='{s}' for_ms={d} progress={d} parks={d} parked_ms={d}", .{
            record.name(),
            record.thread_id.load(.monotonic),
            @tagName(record.currentState()),
            activity.name,
            if (activity.since_ns != 0) (finding.now_ns -| activity.since_ns) / __process_std.time.ns_per_ms else 0,
            if (record.currentState() == .parked) waiting_on else "",
            record.parkedFor(finding.now_ns) / __process_std.time.ns_per_ms,
            record.progress.load(.monotonic),
            record.parks.load(.monotonic),
            record.parked_ns.load(.monotonic) / __process_std.time.ns_per_ms,
        });
    }
    if (main_waiters != 0) {
        __process_log.err("PE64 CONCURRENCY STALL:   {d} thread(s) are waiting for the main thread to run an AppKit request; if the main thread is parked above, its park service is not draining the main queue (no service_main_thread hook, or the owner is not on the main thread)", .{main_waiters});
    }
}

pub fn runtimeLockHolderDescription(holder_id: u64, activity_buffer: []u8) __state_RuntimeLockHolder {
    if (holder_id == 0) return .{};
    const record = __process_parallel_diagnostics.thread_pulse.recordForThread(holder_id) orelse return .{ .name = "an unwatched thread" };
    return .{ .name = record.name(), .activity = record.activity(activity_buffer).name };
}

pub fn reportConcurrencyPulse(context: ?*anyopaque, pulse: *const __process_concurrency.stall.Pulse) void {
    if (comptime @import("builtin").is_test) return;
    const self: *ElfState = @ptrCast(@alignCast(context orelse return));
    if (!self.thread_pulse_policy.shouldPrint(pulse.elapsed_ns)) return;
    if (self.spin_watch.armed()) process_impl_lifecycle.reportSpinWatchSummary(self);
    process_impl_lifecycle.reportGuestTimeSources(self, pulse.elapsed_ns);
    process_impl_lifecycle.reportUnmappedReads(self);
    process_impl_lifecycle.reportXeniaGuestCode(self);
    var holder_buffer: [96]u8 = undefined;
    const holder = runtimeLockHolderDescription(pulse.lock_holder, &holder_buffer);
    const tenths = pulse.elapsed_ns / (__process_std.time.ns_per_s / 10);
    __process_log.info("PE64 THREAD PULSE: t={d}.{d}s pulse={d} instructions={d} runtime_lock(holder='{s}' doing='{s}' held_without_release_ms={d}) context_races={d} get_message(blocks/unreleasable)={d}/{d} owner_waiting_on(handle/pthread_condition/native_condition)=0x{x}/0x{x}/0x{x}; one line per host thread follows - what it is doing or waiting on, and how far it got since the previous pulse line. A running thread with calls+=0 has been inside one call the whole interval", .{
        tenths / 10,
        tenths % 10,
        pulse.sequence,
        pulse.progress,
        holder.name,
        holder.activity,
        pulse.lock_held_ns / __process_std.time.ns_per_ms,
        self.context_race_findings.load(.monotonic),
        @atomicLoad(u64, &self.windows_get_message_blocks, .monotonic),
        @atomicLoad(u64, &self.windows_get_message_unreleasable, .monotonic),
        @atomicLoad(u64, &self.owner_wait_handle, .monotonic),
        @atomicLoad(u64, &self.owner_pthread_condition, .monotonic),
        @atomicLoad(u64, &self.owner_native_condition, .monotonic),
    });
    for (__process_concurrency.watch.allRecords(), 0..) |*record, index| {
        if (record.currentState() == .vacant) continue;
        var activity_buffer: [96]u8 = undefined;
        const line = __process_parallel_diagnostics.thread_pulse.row(&self.thread_pulse_memory, index, record, pulse.now_ns, &activity_buffer);
        self.thread_pulse_lines +|= 1;
        __process_log.info("PE64 THREAD PULSE:   '{s}' state={s} doing='{s}' doing_ms={d} waiting_on='{s}' parked_for_ms={d} progress+={d} calls+={d} parks+={d} parked_ms+={d}", .{
            line.name,
            @tagName(line.state),
            line.activity,
            line.activity_ms,
            line.waiting_on,
            line.parked_for_ms,
            line.progress_delta,
            line.activities_delta,
            line.parks_delta,
            line.parked_ms_delta,
        });
    }
    // The guest side of the same threads: what each is blocked on, in
    // the guest's own terms. Read without the runtime lock - a blocked
    // holder must not silence the pulse - so a field can be one update
    // stale; the table itself is allocated once for the whole run.
    for (self.windows_guest_threads, 0..) |*thread, slot| {
        const status = @atomicLoad(__process_WindowsGuestThreadStatus, &thread.status, .monotonic);
        if (!__process_isLiveWindowsGuestThread(status)) continue;
        const steps = @atomicLoad(u64, &thread.executed_steps, .monotonic);
        const previous = if (slot < self.thread_pulse_guest_steps.len) self.thread_pulse_guest_steps[slot] else steps;
        if (slot < self.thread_pulse_guest_steps.len) self.thread_pulse_guest_steps[slot] = steps;
        __process_log.info("PE64 THREAD PULSE:   guest slot={d} handle=0x{x} name='{s}' status={s} last_import='{s}' blocked_on(handle/condition/srw_lock/deadline_ticks)=0x{x}/0x{x}/0x{x}/{d} steps+={d}", .{
            slot,
            @atomicLoad(u64, &thread.handle, .monotonic),
            thread.nameText(),
            @tagName(status),
            thread.lastImportText(),
            @atomicLoad(u64, &thread.blocked_wait_handle, .monotonic),
            @atomicLoad(u64, &thread.blocked_condition, .monotonic),
            @atomicLoad(u64, &thread.blocked_srw_lock, .monotonic),
            @atomicLoad(u64, &thread.blocked_wait_deadline, .monotonic),
            steps -% previous,
        });
    }
}

pub fn noteContextRace(self: *ElfState, thread: u64, slot: ?usize, finding: __process_parallel_diagnostics.register_tripwire.Finding) void {
    const total = self.context_race_findings.fetchAdd(1, .monotonic) + 1;
    const holder_id = self.windows_runtime_mutex.inner.holder.load(.monotonic);
    if (total == 1) {
        self.context_race_first_thread = thread;
        self.context_race_first_expected_rip = finding.expected.rip;
        self.context_race_first_found_rip = finding.found.rip;
        self.context_race_first_holder = holder_id;
    }
    if (total > 8 and (total & (total - 1)) != 0) return;
    var holder_buffer: [96]u8 = undefined;
    const holder = runtimeLockHolderDescription(holder_id, &holder_buffer);
    // The image's symbol table is read-only after load; the region map is
    // not, and this runs outside the runtime lock.
    var symbol_storage: [__process_guest_symbol_text_bytes]u8 = undefined;
    const found_symbol = process_impl_kernel_services.guestSymbolAt(self, finding.found.rip, &symbol_storage) orelse __process_GuestSymbol{ .name = "<unnamed>", .offset = 0 };
    if (comptime !@import("builtin").is_test) __process_log.err("PE64 CONTEXT RACE: guest thread 0x{x} (slot {?d}) found its registers changed between two of its own steps: rip 0x{x} -> 0x{x} ({s}+0x{x}) rsp 0x{x} -> 0x{x}, finding {d} of the run. Only a thread's own executor may write its registers; the runtime lock was held by '{s}' in '{s}' at the time, the first place to look. Shared code reached for the process owner's register file instead of the calling thread's (lib/guest_context/README.md)", .{
        thread,
        slot,
        finding.expected.rip,
        finding.found.rip,
        found_symbol.name,
        found_symbol.offset,
        finding.expected.rsp,
        finding.found.rsp,
        total,
        holder.name,
        holder.activity,
    });
    // The notable ring has no lock of its own; record only when the
    // runtime lock is free to take without waiting on whoever wrote.
    if (self.windows_runtime_mutex.inner.tryLock()) {
        defer self.windows_runtime_mutex.inner.unlock();
        process_impl_execution.noteNotableEvent(self, .context_violation, finding.found.rip, "context race on thread 0x{x}: rip 0x{x} -> 0x{x} while '{s}' held the runtime lock in '{s}'", .{
            thread,
            finding.expected.rip,
            finding.found.rip,
            holder.name,
            holder.activity,
        });
    }
}

pub fn reportParallelHazards(self: *ElfState) void {
    const races = self.context_race_findings.load(.monotonic);
    const lost_wakeups = self.parallel_guest_wake_hub.lost_wakeups.load(.monotonic);
    const longest_hold_ms: u64 = if (self.runtime_lock_ledger.longestSingleHold()) |entry| entry.max_held_ns / __process_std.time.ns_per_ms else 0;
    const code_borrow_refusals = self.parallel_code_borrow_refusals.load(.monotonic);
    const verdict: []const u8 = if (races != 0)
        "DEFECT: another host thread wrote a guest thread's registers; read PE64 CONTEXT RACE for the thread, the values and who held the runtime lock"
    else if (lost_wakeups != 0)
        "DEFECT: a parked worker was made runnable without being woken; read PE64 CONCURRENCY worker_wakes"
    else if (code_borrow_refusals != 0)
        "DEFECT: a runtime path asked for a raw view of executable bytes and was refused; PE64 PARALLEL CODE BORROW REFUSED names the address and caller"
    else if (self.windows_get_message_unreleasable != 0)
        "COST: GetMessage could not release the runtime lock and returned WM_NULL instead of sleeping; its first_depth/first_pinned in PE64 CONCURRENCY WAITS name the lock level that pinned it"
    else if (longest_hold_ms >= 1000)
        "COST: one call held the runtime lock for a second or more; PE64 RUNTIME LOCK HOLDS names it"
    else
        "clean: no context race, no lost wakeup, GetMessage slept, no call held the runtime lock for a second";
    const format = "PE64 PARALLEL HAZARDS: context_races={d} first(thread/expected_rip/found_rip/lock_holder)=0x{x}/0x{x}/0x{x}/0x{x} lost_wakeups={d} code_borrow_refusals={d} get_message_unreleasable={d} longest_runtime_lock_hold_ms={d} thread_pulse_lines={d} verdict={s}";
    const args = .{
        races,
        self.context_race_first_thread,
        self.context_race_first_expected_rip,
        self.context_race_first_found_rip,
        self.context_race_first_holder,
        lost_wakeups,
        code_borrow_refusals,
        self.windows_get_message_unreleasable,
        longest_hold_ms,
        self.thread_pulse_lines,
        verdict,
    };
    if (races != 0 or lost_wakeups != 0 or code_borrow_refusals != 0) {
        if (comptime !@import("builtin").is_test) __process_log.err(format, args);
    } else {
        __process_log.info(format, args);
    }
}

pub fn reportRuntimeLockHolds(self: *ElfState) void {
    const ledger = &self.runtime_lock_ledger;
    if (self.runtime_lock_native_pipeline_yields != 0 or self.runtime_lock_native_pipeline_yield_refusals != 0) {
        __process_log.info("PE64 NATIVE PIPELINE LOCK YIELDS: yielded={d} released_ms={d} pinned_refusals={d}; pipeline create-info was copied to host scratch before yielding; the Vulkan driver call itself ran without the shared Windows runtime mutex, which was reacquired before forwarding resumed", .{
            self.runtime_lock_native_pipeline_yields,
            self.runtime_lock_native_pipeline_yield_ns / __process_std.time.ns_per_ms,
            self.runtime_lock_native_pipeline_yield_refusals,
        });
    }
    if (self.runtime_lock_gpu_fence_wait_yields != 0 or self.runtime_lock_gpu_fence_wait_yield_refusals != 0) {
        __process_log.info("PE64 GPU FENCE WAIT LOCK YIELDS: yielded={d} released_ms={d} pinned_refusals={d}; vkWaitForFences received a host-owned fence array and ran without the shared Windows runtime mutex, which was reacquired before guest bookkeeping", .{
            self.runtime_lock_gpu_fence_wait_yields,
            self.runtime_lock_gpu_fence_wait_yield_ns / __process_std.time.ns_per_ms,
            self.runtime_lock_gpu_fence_wait_yield_refusals,
        });
    }
    if (self.runtime_lock_gpu_queue_wait_yields != 0 or self.runtime_lock_gpu_queue_wait_yield_refusals != 0) {
        __process_log.info("PE64 GPU QUEUE WAIT LOCK YIELDS: yielded={d} released_ms={d} pinned_refusals={d}; queue-gate and FSI in-flight-room waits used only host-owned synchronization state while the shared Windows runtime mutex was released", .{
            self.runtime_lock_gpu_queue_wait_yields,
            self.runtime_lock_gpu_queue_wait_yield_ns / __process_std.time.ns_per_ms,
            self.runtime_lock_gpu_queue_wait_yield_refusals,
        });
    }
    if (ledger.calls == 0) return;
    __process_log.info("PE64 RUNTIME LOCK HOLDS: calls={d} held_ms={d} waited_ms={d} distinct_calls={d} unnamed(overflow)_calls={d}; runtime-table imports take the shared lock, so a call that holds it long queues every other thread's next serialized import behind it. Eligible precise-time imports are reported separately. held excludes time a call gave the lock back to wait (released)", .{
        ledger.calls,
        ledger.held_ns / __process_std.time.ns_per_ms,
        ledger.waited_ns / __process_std.time.ns_per_ms,
        ledger.used,
        ledger.overflow_calls,
    });
    var ranked: [12]__process_parallel_diagnostics.lock_holds.Entry = undefined;
    for (ledger.top(&ranked), 0..) |entry, index| {
        __process_log.info("PE64 RUNTIME LOCK HOLDS:   rank={d} call={s} calls={d} held_ms={d} longest_hold_us={d} waited_ms={d} longest_wait_us={d} released_ms={d}", .{
            index + 1,
            entry.name,
            entry.calls,
            entry.held_ns / __process_std.time.ns_per_ms,
            entry.max_held_ns / __process_std.time.ns_per_us,
            entry.waited_ns / __process_std.time.ns_per_ms,
            entry.max_waited_ns / __process_std.time.ns_per_us,
            entry.released_ns / __process_std.time.ns_per_ms,
        });
    }
    if (ledger.longestSingleHold()) |entry| {
        if (entry.max_held_ns >= 100 * __process_std.time.ns_per_ms) {
            __process_log.info("PE64 RUNTIME LOCK HOLDS:   longest single hold: {s} held the runtime lock for {d} ms in one call; nothing else could import meanwhile", .{ entry.name, entry.max_held_ns / __process_std.time.ns_per_ms });
        }
    }
}

pub fn reportWindowsFastImports(self: *ElfState, final: bool) void {
    const total = process_impl_lifecycle.windowsFastImportCalls(self);
    const newly_observed = total -| self.windows_fast_time_imports_reported;
    if (newly_observed == 0 and !final) return;
    self.windows_fast_time_imports_reported = total;
    if (total == 0) return;
    __process_log.info("PE64 WINDOWS FAST IMPORTS: GetSystemTimePreciseAsFileTime calls={d} QueryPerformanceCounter={d} QueryPerformanceFrequency={d} new_since_report={d} import_slot_transfers={d} shared_runtime_lock_bypassed=true clock_snapshot=atomic guest_output_store=coordinated; exact dynamic proc-address stubs and direct imports with verified IAT bindings are eligible, while diagnostics use the ordinary locked path; import_slot_transfers counts call [IAT] and thunk jmp [IAT] answered without a step", .{
        self.windows_fast_time_import_calls.load(.acquire),
        self.windows_fast_counter_import_calls[0].load(.acquire),
        self.windows_fast_counter_import_calls[1].load(.acquire),
        newly_observed,
        self.windows_import_slot_fast_transfers.load(.monotonic),
    });
    if (self.windows_fast_identity_imports.load(.monotonic) != 0) __process_log.info("PE64 WINDOWS FAST IMPORTS: identity={d}; GetCurrentThreadId/GetCurrentThread/GetCurrentProcess(Id) answered from the calling context without the runtime lock", .{self.windows_fast_identity_imports.load(.monotonic)});
    if (process_impl_lifecycle.windowsFastCrtImportCalls(self) != 0) __process_log.info("PE64 WINDOWS FAST IMPORTS: crt memcpy={d} memmove={d} memset={d} shared_runtime_lock_bypassed=true; each ran through copyGuestRange/fillGuestMemory, and a range either refused went back to the ordinary locked handler", .{
        self.windows_fast_crt_import_calls[0].load(.acquire),
        self.windows_fast_crt_import_calls[1].load(.acquire),
        self.windows_fast_crt_import_calls[2].load(.acquire),
    });
    if (self.windows_fast_crt_string_import_calls[0].load(.acquire) != 0 or
        self.windows_fast_crt_string_import_calls[1].load(.acquire) != 0 or
        self.windows_fast_crt_string_import_calls[2].load(.acquire) != 0 or
        self.windows_fast_crt_string_import_calls[3].load(.acquire) != 0)
    {
        __process_log.info("PE64 WINDOWS FAST IMPORTS: CRT memcmp={d} strlen={d} strcmp={d} C-locale strxfrm={d}; reads use coordinated guest snapshots, strxfrm stages up to 512 source bytes and writes through the coordinated TSO path; invalid/unterminated ranges and active write/string traces retain the ordinary handler", .{
            self.windows_fast_crt_string_import_calls[0].load(.acquire),
            self.windows_fast_crt_string_import_calls[1].load(.acquire),
            self.windows_fast_crt_string_import_calls[2].load(.acquire),
            self.windows_fast_crt_string_import_calls[3].load(.acquire),
        });
    }
    if (self.windows_fast_heap_import_calls[0].load(.acquire) != 0 or self.windows_fast_heap_import_calls[1].load(.acquire) != 0 or self.windows_fast_heap_import_calls[2].load(.acquire) != 0) __process_log.info("PE64 WINDOWS FAST IMPORTS: CRT heap malloc/uninitialized={d} calloc/zeroed={d} free={d}; generic DLL/name dispatch avoided, while heap metadata remains serialized by its correctness lock; malloc storage is unspecified and calloc stays zero-filled", .{
        self.windows_fast_heap_import_calls[0].load(.acquire),
        self.windows_fast_heap_import_calls[1].load(.acquire),
        self.windows_fast_heap_import_calls[2].load(.acquire),
    });
    if (self.windows_fast_affinity_import_calls.load(.acquire) != 0 or self.windows_fast_sleep_zero_import_calls.load(.acquire) != 0) {
        __process_log.info("PE64 WINDOWS FAST IMPORTS: GetProcessAffinityMask={d} Sleep(0)={d}; affinity masks use acquire-loaded published snapshots, Sleep(0) is restricted to active workers that do not own Xenia's global mutex; both preserve the runtime-call TSO boundary and bypass the shared runtime lock", .{
            self.windows_fast_affinity_import_calls.load(.acquire),
            self.windows_fast_sleep_zero_import_calls.load(.acquire),
        });
    }
}

pub fn reportConcurrency(self: *ElfState) void {
    if (!self.windows_runtime_enabled) return;
    const gate = self.guest_execution_gate.snapshot();
    const parks = __process_concurrency.park.stats();
    const runtime_mutex = &self.windows_runtime_mutex.inner.stats;
    const hub = &self.parallel_guest_wake_hub;
    __process_log.info("PE64 CONCURRENCY: executor={s} host_threads(registered/inside)={d}/{d} stop_the_world(count/quiesce_ms/longest_quiesce_us/held_ms/longest_held_us)={d}/{d}/{d}/{d}/{d} steps_held_by_a_stop={d} safe_regions={d} runtime_mutex(acquired/contended/parks/wait_ms/longest_wait_us)={d}/{d}/{d}/{d}/{d} parks(count/ms/longest_ms)={d}/{d}/{d} main_thread_service(runs/requests)={d}/{d} worker_wakes(notifies/kernel_wakes/safety_net_timeouts/own_deadlines/lost_wakeups)={d}/{d}/{d}/{d}/{d}; address-space changes stop the world, runtime-table imports take the mutex, eligible precise-time imports bypass it, and lost_wakeups must read zero", .{
        if (self.parallel_guest_execution) "parallel" else "cooperative",
        gate.executors,
        gate.inside_now,
        gate.stops,
        gate.quiesce_ns / __process_std.time.ns_per_ms,
        gate.longest_quiesce_ns / __process_std.time.ns_per_us,
        gate.hold_ns / __process_std.time.ns_per_ms,
        gate.longest_hold_ns / __process_std.time.ns_per_us,
        gate.resume_waits,
        gate.safe_regions,
        runtime_mutex.acquisitions.load(.monotonic),
        runtime_mutex.contended.load(.monotonic),
        runtime_mutex.parks.load(.monotonic),
        runtime_mutex.wait_ns.load(.monotonic) / __process_std.time.ns_per_ms,
        runtime_mutex.longest_wait_ns.load(.monotonic) / __process_std.time.ns_per_us,
        parks.parks,
        parks.parked_ns / __process_std.time.ns_per_ms,
        parks.longest_park_ns / __process_std.time.ns_per_ms,
        parks.service_runs,
        parks.service_requests,
        hub.event.notifies.load(.monotonic),
        hub.event.wakes.load(.monotonic),
        hub.timeouts.load(.monotonic),
        hub.deadline_expiries.load(.monotonic),
        hub.lost_wakeups.load(.monotonic),
    });
    __process_log.info("PE64 CONCURRENCY WAITS: get_message(blocks/blocked_ms/event_wakes/host_polls/unreleasable/first_depth/first_pinned)={d}/{d}/{d}/{d}/{d}/{d}/{d} guest_wait_sleeps(count/ms/refused)={d}/{d}/{d} owner_waits(count/slices/ms/longest_ms/sleeps)={d}/{d}/{d}/{d}/{d} message_affinity_skips={d}; a healthy parallel GetMessage stays parked until a deliverable message and polls native host events at a bounded cadence. An unreleasable GetMessage is a WM_NULL lap, and a refused guest sleep retried under a pinned lock", .{
        self.windows_get_message_blocks,
        self.windows_get_message_block_ns / __process_std.time.ns_per_ms,
        self.windows_get_message_event_wakes,
        self.windows_get_message_host_polls,
        self.windows_get_message_unreleasable,
        self.windows_get_message_unreleasable_depth,
        self.windows_get_message_unreleasable_pinned,
        self.windows_guest_wait_parks,
        self.windows_guest_wait_park_ns / __process_std.time.ns_per_ms,
        self.windows_guest_wait_park_refusals,
        self.windows_owner_waits,
        self.windows_owner_wait_retries,
        self.windows_owner_wait_ns / __process_std.time.ns_per_ms,
        self.windows_owner_wait_longest_ns / __process_std.time.ns_per_ms,
        self.windows_owner_sleeps,
        process_impl_windows_ui.windowsMessageAffinitySkipCount(self),
    });
}

pub fn setParallelGuestExecution(self: *ElfState, enabled: bool) void {
    var gate_guard = self.guest_execution_gate.enterMutation();
    defer gate_guard.unlock();
    flushAllGuestStoreBuffers(self, .mode_change);
    if (self.parallel_guest_execution == enabled) return;
    // Accelerator discovery mutates image-wide dispatch metadata. Finish
    // it while the process is quiescent so concurrent transfer handlers
    // only perform immutable target comparisons. The translators' hooked-
    // target filter is built here for the same reason: every executor's
    // translated code reads it, so it is never rebuilt while they run.
    if (enabled) {
        process_impl_execution.resolveXeniaAcceleratorTargets(self);
        rebuildBlockJitHookFilter(self);
        // A mask the guest set for itself is its own; only the
        // cooperative default grows to the host's processors.
        if (self.windows_process_affinity_mask == 1 and self.windows_system_affinity_mask == 1) {
            const mask = guestProcessorMask();
            self.windows_process_affinity_mask = mask;
            self.windows_system_affinity_mask = mask;
            self.windows_process_affinity_published.store(mask, .release);
            self.windows_system_affinity_published.store(mask, .release);
        }
    }
    // This transition is a stop-the-world boundary. Decode entries
    // populated under generation tracking cannot be reused by the
    // parallel byte-checked path, nor can byte-checked entries safely
    // re-enter the serial generation fast path without a fresh fill.
    __ProcessInternals._coordinated_decode_cache_mutex().*.lock();
    // Entering parallel mode flushes while serial invalidation is still
    // active; from then on each executor fills only its own table and
    // invalidations retire tags under the epoch (`Tlb.*Ordered`).
    // Leaving it first closes the parallel route at the caller's join
    // barrier, then starts with clean tables before serial admission
    // resumes.
    if (enabled) {
        flushAllBlockJitTlbs(self, true, true);
        // The owner probes and fills its own table from here on. A
        // cooperative switch may have left this pointing at a worker's
        // table, which that worker now fills from its own host thread;
        // two fillers of one table could pair a tag with the other
        // thread's delta.
        self.block_jit_tlb_active = ownerBlockJitTlb(self);
        // Workers read and bump its words; this is the last moment it
        // can be allocated.
        process_impl_guest_memory.ensureCodePageGenerations(self);
    }
    process_impl_lifecycle.guestContextField(self, "guest_clock_sample_steps").* = 0;
    for (self.windows_guest_threads) |*thread| thread.context.guest_clock_sample_steps = 0;
    self.parallel_guest_termination.store(false, .release);
    self.parallel_owner_executed_steps.store(process_impl_lifecycle.observedExecutionSteps(self), .release);
    self.parallel_guest_execution = enabled;
    for (self.decode_cache) |*entry| entry.* = .{};
    for (self.decode_cache_victims) |*entry| entry.* = .{};
    if (!enabled) flushAllBlockJitTlbs(self, true, true);
    __ProcessInternals._coordinated_decode_cache_mutex().*.unlock();
}

pub fn activeGuestTsoStoreBuffer(self: *ElfState) ?*__process_tso_memory.StoreBuffer {
    // The hybrid TSO store queue is part of every cooperative Windows
    // guest run.
    if (!self.windows_runtime_enabled) return null;
    // With the parallel TLB live, translated code reads and writes guest
    // memory directly, so a store queued here would be invisible to
    // this thread's own next translated load. Stores go straight to
    // memory with release ordering instead: a legal x86-TSO machine (a
    // queue only adds the store-to-load reordering TSO permits, never
    // one it requires).
    if (parallelDirectTlbActive(self)) return null;
    return self.guest_store_buffers.forContext(process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*);
}

pub fn parallelDirectTlbActive(self: *const ElfState) bool {
    return self.parallel_guest_execution and self.parallel_direct_tlb and self.block_jit_tlb_enabled;
}

pub fn tlbFillBlockJit(self: *ElfState) ?*__process_BlockJitState {
    if (self.parallel_guest_execution) {
        if (parallelWorkerSlot(self)) |slot| return self.windows_guest_threads[slot].parallel_block_jit;
    }
    return self.block_jit;
}

pub fn bumpTlbCounter(self: *const ElfState, counter: *u64) void {
    if (self.parallel_guest_execution) {
        _ = @atomicRmw(u64, counter, .Add, 1, .monotonic);
    } else {
        counter.* +|= 1;
    }
}

pub fn flushAllGuestStoreBuffers(self: *ElfState, boundary: __process_tso_memory.Boundary) void {
    self.guest_store_buffers.flushAll(boundary);
}

pub fn ensureWindowsGuestThreadTlb(self: *ElfState, index: usize) ?*__process_block_jit.Tlb {
    const thread = &self.windows_guest_threads[index];
    const tlb_slot = &self.windows_guest_thread_tlbs[index];
    const existing = if (self.parallel_guest_execution)
        @atomicLoad(?*__process_block_jit.Tlb, tlb_slot, .acquire)
    else
        tlb_slot.*;
    if (existing == null) {
        const tlb = self.allocator.create(__process_block_jit.Tlb) catch return null;
        tlb.* = __process_block_jit.Tlb.empty;
        if (self.parallel_guest_execution) {
            // Invalidators read this table from other host threads. The
            // release publication makes the initialized empty TLB
            // visible before an acquire load can retire its tags.
            @atomicStore(?*__process_block_jit.Tlb, tlb_slot, tlb, .release);
        } else {
            tlb_slot.* = tlb;
        }
    }
    const tlb = if (existing) |value|
        value
    else if (self.parallel_guest_execution)
        @atomicLoad(?*__process_block_jit.Tlb, tlb_slot, .acquire) orelse return null
    else
        tlb_slot.* orelse return null;
    thread.context.block_jit_tlb = tlb;
    return tlb;
}

pub fn invalidateAllBlockJitTlbs(self: *ElfState, base: u64, length: u64) void {
    invalidateAllBlockJitTlbTables(self, base, length, true, true);
}

pub fn invalidateAllBlockJitTlbTables(self: *ElfState, base: u64, length: u64, reads: bool, writes: bool) void {
    if (self.parallel_guest_execution) {
        // Every executor may be probing its own table right now: move
        // the epoch, then retire tags only (`Tlb.invalidateRangeOrdered`).
        // Without the direct route no table was ever filled.
        if (!self.parallel_direct_tlb) return;
        _ = self.block_jit_tlb_epoch.fetchAdd(1, .seq_cst);
        if (!(reads or writes)) return;
        const owner_tlb = ownerBlockJitTlb(self);
        owner_tlb.invalidateRangeOrderedTables(base, length, reads, writes);
        var table_count: u64 = 1;
        for (&self.windows_guest_thread_tlbs) |*tlb_slot| {
            if (@atomicLoad(?*__process_block_jit.Tlb, tlb_slot, .acquire)) |tlb| {
                if (tlb != owner_tlb) {
                    tlb.invalidateRangeOrderedTables(base, length, reads, writes);
                    table_count +|= 1;
                }
            }
        }
        const pages = if (length == 0) 0 else ((base +| (length - 1)) >> __process_block_jit.Tlb.page_shift) - (base >> __process_block_jit.Tlb.page_shift) + 1;
        self.parallel_tlb_invalidation_work.noteRange(
            pages,
            table_count,
            __process_block_jit.Tlb.entries,
            __process_block_jit.Tlb.invalidate_scan_limit,
        );
        _ = self.parallel_tlb_cross_invalidations.fetchAdd(1, .monotonic);
        return;
    }
    const owner_tlb = ownerBlockJitTlb(self);
    owner_tlb.invalidateRangeTables(base, length, reads, writes);
    for (&self.windows_guest_thread_tlbs) |*tlb_slot| {
        if (tlb_slot.*) |tlb| {
            if (tlb != owner_tlb) tlb.invalidateRangeTables(base, length, reads, writes);
        }
    }
}

pub fn flushAllBlockJitTlbs(self: *ElfState, reads: bool, writes: bool) void {
    if (self.parallel_guest_execution) {
        if (!self.parallel_direct_tlb) return;
        _ = self.block_jit_tlb_epoch.fetchAdd(1, .seq_cst);
        const owner_tlb = ownerBlockJitTlb(self);
        owner_tlb.flushOrdered(reads, writes);
        var table_count: u64 = 1;
        for (&self.windows_guest_thread_tlbs) |*tlb_slot| {
            if (@atomicLoad(?*__process_block_jit.Tlb, tlb_slot, .acquire)) |tlb| {
                if (tlb != owner_tlb) {
                    tlb.flushOrdered(reads, writes);
                    table_count +|= 1;
                }
            }
        }
        self.parallel_tlb_invalidation_work.noteFlush(reads, writes, table_count, __process_block_jit.Tlb.entries);
        _ = self.parallel_tlb_cross_invalidations.fetchAdd(1, .monotonic);
        return;
    }
    const owner_tlb = ownerBlockJitTlb(self);
    owner_tlb.flush(reads, writes);
    for (&self.windows_guest_thread_tlbs) |*tlb_slot| {
        if (tlb_slot.*) |tlb| {
            if (tlb != owner_tlb) tlb.flush(reads, writes);
        }
    }
}

pub fn blockJitTlbInvalidate(self: *ElfState, base: u64, length: u64) void {
    invalidateAllBlockJitTlbs(self, base, length);
    if (self.block_jit) |jit| bumpTlbCounter(self, &jit.tlb_invalidations);
}

pub fn blockJitTlbFlush(self: *ElfState, reads: bool, writes: bool) void {
    flushAllBlockJitTlbs(self, reads, writes);
    if (self.block_jit) |jit| bumpTlbCounter(self, &jit.tlb_flushes);
}

pub fn noteMappedCodeFetched(self: *ElfState, slice: __process_WindowsMappedCodeSlice) void {
    const flag: *bool = switch (slice.kind) {
        .memory_view => if (slice.source_index < self.windows_file_mappings.len) &self.windows_file_mappings[slice.source_index].code_fetched else return,
        .virtual_allocation => if (slice.source_index < self.windows_virtual_allocations.len) &self.windows_virtual_allocations[slice.source_index].code_fetched else return,
    };
    // Only the executor that changes false -> true needs to retire write
    // translations. A release publication pairs with
    // `mappedRangeCodeFetched` on every other worker before it admits a
    // write page; that worker's epoch check also retires a fill that
    // started just before this flush.
    if (self.parallel_guest_execution) {
        if (@cmpxchgStrong(bool, flag, false, true, .acq_rel, .acquire) != null) return;
    } else {
        if (flag.*) return;
        flag.* = true;
    }
    blockJitTlbFlush(self, false, true);
}

pub fn mappedCodeWasFetched(self: *const ElfState, flag: *const bool) bool {
    return if (self.parallel_guest_execution)
        @atomicLoad(bool, flag, .acquire)
    else
        flag.*;
}

pub fn mappedRangeCodeFetched(self: *const ElfState, range: __process_mapped_ranges.Range) bool {
    return switch (range.kind) {
        .memory_view => blk: {
            if (range.slot >= self.windows_memory_views.len) break :blk true;
            const mapping_index = self.windows_memory_views[range.slot].mapping_index;
            break :blk mapping_index >= self.windows_file_mappings.len or mappedCodeWasFetched(self, &self.windows_file_mappings[mapping_index].code_fetched);
        },
        .virtual_allocation => range.slot >= self.windows_virtual_allocations.len or mappedCodeWasFetched(self, &self.windows_virtual_allocations[range.slot].code_fetched),
    };
}

pub fn blockJitCallTargetPlain(self: *ElfState, target: u64) bool {
    if (process_impl_guest_diagnostics.isGuestMilestoneAddress(self, target)) return false;
    return blockJitCallTargetPlainIgnoringMilestones(self, target);
}

pub fn blockJitCallTargetPlainIgnoringMilestones(self: *ElfState, target: u64) bool {
    return blockJitCallRefusal(self, target) == null;
}

pub fn blockJitCallRefusal(self: *ElfState, target: u64) ?__process_BlockJitCallRefusal {
    if (blockJitTargetHooked(self, target)) return .hooked_target;
    if (self.image_high == 0) return .no_image_bounds;
    // Inside the image, the one hook not keyed on an exact address
    // below is the local-function shim, which names its target through
    // `localSymbolNameAt` - and that table is the ELF loader's, empty on
    // the PE route. The call traces are the other thing the arm does.
    // 2026-09-21: refusing the whole image left 397 million `call_rel32`
    // fallbacks, half of all of them, on Xenia calling its own code.
    if (target >= self.image_low and target < self.image_high) {
        if (self.local_symbols.len != 0) return .image_local_symbols;
        if (self.trace_calls) return .call_trace;
        if (self.block_jit_transfer_traced) return .transfer_trace;
    }
    if (self.guest_kernel_calls.exportAt(target)) |slot| {
        if (@atomicLoad(__process_kernel_call_census.Saturation, &slot.saturation, .acquire) != .saturated) return .kernel_census;
    }
    // The accelerators resolve their target on the first call that
    // reaches the arm. One that has not resolved yet cannot be compared
    // against, so nothing is admitted until it has.
    if (self.xenia_sha1_accelerator_enabled and !self.xenia_sha1_target_checked) return .accelerator_unresolved;
    if (self.xenia_rijndael_accelerator_enabled and !self.xenia_rijndael_target_checked) return .accelerator_unresolved;
    if (self.xenia_tabulate_accelerator_enabled and !self.xenia_tabulate_target_checked) return .accelerator_unresolved;
    inline for (.{ "xenia_sha1_target", "xenia_rijndael_target", "xenia_tabulate_target" }) |field| {
        if (@field(self, field)) |resolved| {
            if (resolved == target) return .accelerator_target;
        }
    }
    inline for (.{
        "windows_pthread_cond_wait_entry",
        "windows_pthread_cond_signal_entry",
        "windows_pthread_cond_broadcast_entry",
        "windows_pthread_cond_timedwait_entry",
    }) |field| {
        if (@field(self, field)) |entry| {
            if (entry == target) return .pthread_condition_entry;
        }
    }
    return null;
}

pub fn noteBlockJitCallRefusal(self: *ElfState, site: u64, target: u64, refusal: __process_BlockJitCallRefusal) void {
    const count = @atomicRmw(u64, &self.block_jit_call_refusals[@intFromEnum(refusal)], .Add, 1, .monotonic) + 1;
    if (comptime @import("builtin").is_test) return;
    if (count > 4) return;
    var site_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var target_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    __process_log.info("PE64 BLOCK JIT CALL REFUSAL: reason={s} site=0x{x} ({s}) target=0x{x} ({s}) occurrence={d}; this call is compiled as an interpreter fallback for the life of its block", .{
        @tagName(refusal),
        site,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, site, &site_text),
        target,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, target, &target_text),
        count,
    });
}

pub fn compileBlockJit(self: *ElfState, jit: *__process_BlockJitState, rip: u64) ?*__process_block_jit.Block {
    var insns: __process_std.ArrayList(__process_block_jit.Insn) = .empty;
    defer insns.deinit(self.allocator);
    var bytes: __process_std.ArrayList(u8) = .empty;
    defer bytes.deinit(self.allocator);

    var address = rip;
    var conditionals_followed: u32 = 0;
    var source_mapped = false;
    var source_kind: u8 = 0;
    var source_index: usize = 0;
    var source_generation: ?u64 = null;
    // Mapped code is validated by the word of the page it starts on,
    // read before the first byte is fetched: a store that lands after
    // the fetch then shows as a moved word, never as a block that
    // matches bytes it did not see.
    var page_word: ?*u64 = null;
    var page_generation: u64 = 0;
    var first_backing: u64 = 0;
    if (process_impl_guest_memory.addrToOffset(self, rip) == null) {
        if (process_impl_guest_memory.windowsMappedCodeMemoryConst(self, rip, 1)) |probe| {
            process_impl_guest_memory.ensureCodePageGenerations(self);
            if (process_impl_guest_memory.codePageGenerationWord(self, probe.kind, probe.source_index, probe.backing_offset)) |word| {
                page_word = word;
                page_generation = process_impl_guest_memory.loadCodeGeneration(word);
                first_backing = probe.backing_offset;
            }
        }
    }
    jit.last_refusal = .empty_fetch;
    jit.last_refusal_op = .invalid;
    while (insns.items.len < __process_BLOCK_JIT_MAX_INSTRUCTIONS) {
        const fetch = fetchInstructionSource(self, address) orelse break;
        const fetch_bytes = fetch.contents();
        const mapped = fetch.mapped != null;
        const kind: u8 = if (fetch.mapped) |generated| @intFromEnum(generated.kind) else 0;
        const index: usize = if (fetch.mapped) |generated| generated.source_index else 0;
        if (insns.items.len == 0) {
            source_mapped = mapped;
            source_kind = kind;
            source_index = index;
            source_generation = if (fetch.mapped) |generated| generated.generation else process_impl_guest_memory.windowsImageCodeGenerationFor(self, address, 1);
            if (page_word != null) {
                // The mapping the probe named, or one that replaced it
                // in between: compile nothing rather than guess.
                jit.last_refusal = .page_identity;
                const generated = fetch.mapped orelse return null;
                if (generated.backing_offset != first_backing) return null;
                source_generation = page_generation;
            }
        } else if (mapped != source_mapped or kind != source_kind or index != source_index) {
            break;
        } else if (page_word != null and fetch.mapped.?.backing_offset != first_backing +% (address - rip)) {
            // Two views of one mapping side by side: the bytes past the
            // seam are another part of the backing, which this block's
            // page word does not cover.
            break;
        }
        const d = __process_decodeInsn(fetch_bytes);
        const decoded_len: usize = d.len;
        if (decoded_len == 0 or decoded_len > fetch_bytes.len or decoded_len > __process_PE_MAX_INSTRUCTION_LENGTH) {
            jit.last_refusal = .decode_failed;
            jit.last_refusal_op = d.op;
            break;
        }
        if (__process_block_jit.endsBlockBefore(d)) {
            jit.last_refusal = .ends_before;
            jit.last_refusal_op = d.op;
            break;
        }
        const prefixes = __process_x64_decoder.decodeLegacyPrefixes(fetch_bytes);
        const base: ?__process_RegId = if (d.sib_has_base) d.sib_base_reg else null;
        var insn = __process_block_jit.Insn{
            .rip = address,
            .len = d.len,
            .decoded = d,
            .segment = __process_x64_decoder.selectSegment(.explicit_data, base, prefixes.segment_override),
        };
        if (d.op == .jmp_rel8) {
            const target = address +% d.len +% d.imm;
            if (blockJitTargetHooked(self, target)) {
                insn.force_fallback = true;
                insn.fallback_reason = .hook_observation;
            }
        }
        if (d.op == .call_rel32) {
            const target = address +% d.len +% @as(u64, @bitCast(d.imm));
            const milestone = process_impl_guest_diagnostics.guestMilestoneIndexOf(self, target);
            const refusal = blockJitCallRefusal(self, target);
            if (milestone == null and refusal == null) {
                jit.call_targets_plain +|= 1;
            } else if (milestone != null and __process_guestMilestoneSaturable(milestone.?) and refusal == null) {
                insn.milestone_gate = @intCast(milestone.?);
                jit.call_targets_plain +|= 1;
            } else {
                insn.force_fallback = true;
                insn.fallback_reason = .hook_observation;
                jit.call_targets_hooked +|= 1;
                noteBlockJitCallRefusal(self, address, target, refusal orelse .milestone);
            }
        }
        if (!self.block_jit_vectors_enabled and __process_block_jit.isVectorNative(d)) {
            insn.force_fallback = true;
            insn.fallback_reason = .vector_policy_disabled;
        }
        insns.append(self.allocator, insn) catch {
            jit.last_refusal = .allocation;
            return null;
        };
        bytes.appendSlice(self.allocator, fetch_bytes[0..decoded_len]) catch {
            jit.last_refusal = .allocation;
            return null;
        };
        address +%= d.len;
        // A control transfer ends the block, with one exception: a
        // conditional branch the translator compiles itself. Its
        // not-taken edge is the next byte, so the trace can continue
        // across it and still be one contiguous range. That is what
        // raises `mean_block_len` past the length of a basic block, and
        // every per-block cost is paid per block, not per basic block.
        if (__process_block_jit.isTerminator(d.op) or __process_block_jit.isFallbackTerminator(d.op)) {
            if (!__process_block_jit.isConditionalBranch(d.op) or insn.force_fallback or
                conditionals_followed >= __process_BLOCK_JIT_MAX_CONDITIONALS) break;
            conditionals_followed += 1;
            jit.conditionals_followed +|= 1;
        }
    }
    if (insns.items.len == 0) return null;
    // The image generation covers the whole block only if every byte of
    // it lies in executable ranges; otherwise the bytes decide.
    if (!source_mapped) source_generation = process_impl_guest_memory.windowsImageCodeGenerationFor(self, rip, bytes.items.len);

    const options: __process_block_jit.Options = .{
        .ledger = blockJitLedger(self, source_mapped, rip),
        // The Windows x64 calling convention passes no flag through a
        // call or a return.
        .flags_dead_at_calls = self.windows_runtime_enabled,
        .internal_edges = self.block_jit_internal_edges_enabled,
    };
    jit.last_refusal = .compile_error;
    jit.last_refusal_op = insns.items[0].decoded.op;
    var compiled = __process_block_jit.compileWith(self.allocator, &jit.memory, __state_block_jit_layout, insns.items, address, options) catch |err| switch (err) {
        error.NothingToCompile => {
            jit.last_refusal = .nothing_to_compile;
            return null;
        },
        error.OutOfCodeSpace => blk: {
            resetBlockJit(self, jit);
            // Deferred under a live execution: nothing may be written
            // into the memory until it is reset.
            if (jit.lifetime.reset_pending) return null;
            break :blk __process_block_jit.compileWith(self.allocator, &jit.memory, __state_block_jit_layout, insns.items, address, options) catch {
                jit.compile_failures +|= 1;
                return null;
            };
        },
        else => {
            jit.compile_failures +|= 1;
            return null;
        },
    };
    jit.last_refusal = .allocation;
    const block = self.allocator.create(__process_block_jit.Block) catch return null;
    const owned_insns = insns.toOwnedSlice(self.allocator) catch {
        self.allocator.destroy(block);
        return null;
    };
    const owned_bytes = bytes.toOwnedSlice(self.allocator) catch {
        self.allocator.free(owned_insns);
        self.allocator.destroy(block);
        return null;
    };
    block.* = .{
        .helpers = .{
            .read = __process_blockJitRead,
            .write = __process_blockJitWrite,
            .read128 = __process_blockJitRead128,
            .write128 = __process_blockJitWrite128,
            .write128_non_temporal = __process_blockJitWrite128NonTemporal,
            .mapped_transfer = __process_blockJitMappedTransferAllowed,
            .hooked_transfer = __process_blockJitHookedTransfer,
            .import_transfer = __process_blockJitImportTransfer,
            .x87_raw_transfer = __process_blockJitX87RawTransfer,
            .x87_memory = __process_blockJitX87Memory,
            .interpret = __process_blockJitInterpret,
            .block = block,
            .flags = __process_blockJitFlags,
        },
        .start_rip = rip,
        .end_rip = address,
        .insns = owned_insns,
        .bytes = owned_bytes,
        .code = compiled.code,
        .native_count = compiled.native_count,
        .fallback_count = compiled.fallback_count,
        .register_only = compiled.register_only,
        .internal_edges = compiled.internal_edges != 0,
        .internal_sources = compiled.internal_sources,
        .needs_verify = self.block_jit_verify_memory and !compiled.register_only,
        .touches_vectors = compiled.touches_vectors,
        .touches_x87 = compiled.touches_x87,
        .source_mapped = source_mapped,
        .source_kind = source_kind,
        .source_index = source_index,
        .source_generation = source_generation,
        .chain_entry = compiled.chain_entry,
        .generation_ptr = if (page_word) |word| word else blockJitGenerationPointer(self, source_mapped, source_kind, source_index),
    };
    blockJitArmChain(block);
    compiled.code = &.{};
    jit.compiled +|= 1;
    jit.native_instructions_compiled +|= block.native_count;
    jit.fallback_instructions_compiled +|= block.fallback_count;
    jit.flags_elided +|= compiled.flags_elided;
    jit.flags_narrowed +|= compiled.flags_narrowed;
    if (compiled.return_flags != 0) jit.returns_owing_flags +|= 1;
    jit.fused_branches +|= compiled.fused_branches;
    jit.fused_runs +|= compiled.fused_runs;
    jit.cached_registers +|= compiled.cached_registers;
    jit.hoisted_accesses +|= compiled.hoisted_accesses;
    return block;
}

pub fn accountBlockJit(self: *ElfState, jit: *__process_BlockJitState, block: *__process_block_jit.Block, completed: u32) u32 {
    return accountBlockJitIn(self, process_impl_lifecycle.guestContextRef(self), jit, block, completed);
}

pub fn accountBlockJitIn(self: *ElfState, ctx: __process_GuestContextRef, jit: *__process_BlockJitState, block: *__process_block_jit.Block, completed: u32) u32 {
    const retired: u32 = @max(completed, 1);
    jit.executions +|= 1;
    jit.instructions_retired +|= retired;
    block.executions +|= 1;
    block.instructions_retired +|= retired;
    // By reference. `Insn` carries a whole `DecodedInsn`, so taking it by
    // value copies about eighty bytes to read three scalars - forty-one
    // billion times on 2026-09-20. This is the same shape as the view
    // copy in `noteWindowsTitleCodeFetches` directly below.
    const last = &block.insns[@min(retired, @as(u32, @intCast(block.insns.len))) - 1];
    ctx.field("last_instruction_rip").* = last.rip;
    ctx.field("last_decoded_op").* = last.decoded.op;
    ctx.field("last_decoded_len").* = last.len;
    if (block.source_mapped) {
        self.windows_generated_code_fetches +|= retired;
        process_impl_instruction_decode.noteWindowsTitleCodeFetchesIn(self, ctx, block.start_rip, retired);
    }
    return retired;
}

pub fn accountBlockJitRun(self: *ElfState, ctx: __process_GuestContextRef, jit: *__process_BlockJitState, first: *__process_block_jit.Block, last: *__process_block_jit.Block, completed: u32, record: *const __process_block_jit.Scratch) u32 {
    const count = record.chain_count;
    const blocks = count & __process_block_jit.chain_count_blocks_mask;
    const retired_total: u64 = count >> __process_block_jit.chain_count_shift;
    const image = @min(record.chain_retired_image, retired_total);
    const other_mapped = @min(record.chain_retired_other_mapped, retired_total - image);
    jit.executions +|= blocks;
    jit.instructions_retired +|= retired_total;
    first.executions +|= 1;
    if (last != first) last.executions +|= 1;
    last.instructions_retired +|= @max(completed, 1);
    self.windows_generated_code_fetches +|= retired_total - image;
    // `noteWindowsTitleCodeFetches`, once for the chain: the thread and
    // the code-cache view cannot change while it runs, and a block's
    // ledger was decided against that view when it was compiled.
    if (ctx.field("windows_active_guest_thread_slot").*) |slot| {
        if (self.windows_guest_threads[slot].entered_xenia_title and self.windows_code_cache_view != null) {
            self.windows_title_code_fetches +|= retired_total - image - other_mapped;
        }
    }
    const final = &last.insns[@min(@max(completed, 1), @as(u32, @intCast(last.insns.len))) - 1];
    ctx.field("last_instruction_rip").* = final.rip;
    ctx.field("last_decoded_op").* = final.decoded.op;
    ctx.field("last_decoded_len").* = final.len;
    return @intCast(@min(@max(retired_total, 1), __process_std.math.maxInt(u32)));
}

pub fn blockJitLedger(self: *const ElfState, source_mapped: bool, rip: u64) __process_block_jit.Ledger {
    if (!source_mapped) return .image;
    const index = self.windows_code_cache_view orelse return .other_mapped;
    const view = &self.windows_memory_views[index];
    return if (rip >= view.guest_base and rip - view.guest_base < view.length) .code_cache else .other_mapped;
}

pub fn blockJitArmChain(block: *__process_block_jit.Block) void {
    const word = block.generation_ptr orelse return block.disarmChain();
    if ((block.register_only or block.needs_verify) and !block.verified) return block.disarmChain();
    block.armChain(word, block.source_generation orelse process_impl_guest_memory.loadCodeGeneration(word));
}

pub fn blockJitFindValidSlot(self: *ElfState, jit: *__process_BlockJitState, rip: u64) ?__state_FoundBlock {
    const base = jit.firstSlot(rip);
    for (base..base + __process_BLOCK_JIT_WAYS) |slot_index| {
        const block = jit.blocks[slot_index] orelse continue;
        if (block.start_rip != rip) continue;
        if (blockJitValidate(self, jit, block)) return .{ .block = block, .slot = slot_index };
        dropBlockJitSlot(self, jit, slot_index);
        jit.dropped_stale +|= 1;
        return null;
    }
    return null;
}

pub fn blockJitLink(self: *ElfState, jit: *__process_BlockJitState, from: *__process_block_jit.Block, rip: u64, to: *__process_block_jit.Block, slot: usize) void {
    if (!self.block_jit_chain_enabled) return;
    if (to.generation_ptr == null) return;
    const link: __process_block_jit.Link = .{ .rip = rip, .slot = @intFromPtr(&jit.blocks[slot]) };
    // The thread's jump cache too: a `ret` to more callers than `from`
    // has ways, or an indirect call through a table, finds its
    // successor there instead of coming back here.
    if (jit.jump_cache.len != 0) jit.jump_cache[__process_block_jit.jumpCacheIndex(rip)] = link;
    // Re-arm the way that already names this address; otherwise take
    // the round-robin victim.
    var way: usize = from.link_victim;
    for (from.links, 0..) |existing, index| {
        if (existing.rip == rip) {
            way = index;
            break;
        }
    } else from.link_victim = @intCast((way + 1) % __process_block_jit.link_ways);
    from.links[way] = link;
    jit.links_armed +|= 1;
}

pub fn logHotspotBytes(self: *const ElfState, handle: u64, address: u64) void {
    // One region and the one after it: a loop that starts near the end
    // of its 256-byte region closes in the next.
    var snapshot: [512]u8 = undefined;
    const count: usize = if (process_impl_execution.copyFromGuest(self, snapshot[0..], address)) 512 else blk: {
        if (!process_impl_execution.copyFromGuest(self, snapshot[0..256], address)) return;
        break :blk 256;
    };
    // Keep one explicit byte count for both the snapshot and hex output.
    var hex: [1024]u8 = undefined;
    const digits = "0123456789abcdef";
    for (snapshot[0..count], 0..) |byte, i| {
        hex[i * 2] = digits[byte >> 4];
        hex[i * 2 + 1] = digits[byte & 0xF];
    }
    __process_log.info("PE64 CPU HOTSPOT BYTES: thread=0x{x} region=0x{x} count={d} bytes={s}; x86-64, load at the region address to disassemble", .{ handle, address, count, hex[0 .. count * 2] });
}

pub fn blockJitFindValid(self: *ElfState, jit: *__process_BlockJitState, rip: u64) ?*__process_block_jit.Block {
    const base = jit.firstSlot(rip);
    for (base..base + __process_BLOCK_JIT_WAYS) |slot_index| {
        const block = jit.blocks[slot_index] orelse continue;
        if (block.start_rip != rip) continue;
        if (blockJitValidate(self, jit, block)) return block;
        dropBlockJitSlot(self, jit, slot_index);
        jit.dropped_stale +|= 1;
        return null;
    }
    return null;
}

pub fn bindBlockJitRegisterFile(self: *ElfState) *__process_block_jit.Scratch {
    const scratch = process_impl_lifecycle.guestContextField(self, "block_jit_scratch");
    scratch.regs_file = @intFromPtr(process_impl_lifecycle.guestContextField(self, "regs"));
    scratch.xmm_file = @intFromPtr(process_impl_lifecycle.guestContextField(self, "xmm"));
    scratch.ymm_hi_file = @intFromPtr(process_impl_lifecycle.guestContextField(self, "ymm_hi"));
    scratch.zmm_hi_file = @intFromPtr(process_impl_lifecycle.guestContextField(self, "zmm_hi"));
    scratch.tlb_file = @intFromPtr(activeBlockJitTlb(self));
    return scratch;
}

pub fn logTranslatedEntryViolation(self: *ElfState, block: *const __process_block_jit.Block, pending: usize, route: []const u8) void {
    var symbol_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var previous_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    const previous_rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*;
    __process_log.err("PE64 TSO INVARIANT: translated block 0x{x} ({s}) was entered by {s} with {d} buffered store(s) still queued; last instruction 0x{x} ({s}) op={s} thread_slot={?d} step={d}. Translated code reads and writes guest memory directly, so it would have read memory without those stores and had its own stores overwritten when they drained. They were drained here; the boundary that should have drained them is missing (read PE64 TSO STORE BUFFERS at exit)", .{
        block.start_rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, block.start_rip, &symbol_text),
        route,
        pending,
        previous_rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, previous_rip, &previous_text),
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
        process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*,
        process_impl_run_reporting.totalInterpretedSteps(self),
    });
    process_impl_execution.noteNotableEvent(self, .tso_violation, 0, "translated block 0x{x} entered by {s} with {d} buffered store(s); last op {s}", .{
        block.start_rip,
        route,
        pending,
        @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
    });
}

pub fn executeBlockJit(self: *ElfState, jit: *__process_BlockJitState, first: *__process_block_jit.Block, first_slot: usize) bool {
    // Translated arithmetic obeys the host FPCR. MXCSR reaches it on every
    // load, but a context restored from a snapshot or another slice on
    // this thread can leave the two apart; one register read settles it.
    const guest_mxcsr = process_impl_lifecycle.guestContextField(self, "regs").*.mxcsr;
    if (!__process_host_fp_control.matchesGuestMxcsr(guest_mxcsr)) __process_host_fp_control.applyGuestMxcsr(guest_mxcsr);
    if (first.register_only and !first.verified) {
        if (blockVerifyReachesHook(self, first)) {
            // Never interpret a shim for a check: trust the block and
            // run it as usual.
            first.verified = true;
            blockJitArmChain(first);
            jit.verify_skipped_hooked +|= 1;
        } else {
            // The cross-check runs the block itself (once) and accounts
            // it; whichever way it went, this step is done.
            _ = verifyBlockJit(self, jit, first, first_slot);
            return !process_impl_lifecycle.isTerminated(self);
        }
    }
    if (first.needs_verify and !first.verified) {
        // Checked against a journaled interpreter pass; a block the
        // journal cannot model is trusted unchecked and runs below.
        if (verifyMemoryBlockJit(self, jit, first, first_slot)) return !process_impl_lifecycle.isTerminated(self);
    }
    var block = first;
    var total_retired: u32 = 0;
    var chained: u32 = 0;
    // The binding lives in this context's own scratch record, so a helper
    // that runs a nested slice of another guest thread - a wait import
    // servicing workers - binds that thread's record, not this one's.
    const scratch = bindBlockJitRegisterFile(self);
    scratch.jump_cache = if (jit.jump_cache.len != 0) jit.jump_cache.ptr else null;
    // Every block this loop runs, and every block its helpers' nested
    // slices run, stays allocated until the outermost execution returns.
    jit.lifetime.enter();
    defer leaveBlockJitExecution(self, jit);
    var ctx = process_impl_lifecycle.guestContextRef(self);
    jit.dispatch_entries +|= 1;
    const chain_block_limit: u32 = if (self.parallel_guest_execution) __process_BLOCK_JIT_PARALLEL_CHAIN_BLOCKS else __process_BLOCK_JIT_CHAIN_BLOCKS;
    const chain_instruction_limit: u32 = if (self.parallel_guest_execution) __process_BLOCK_JIT_PARALLEL_CHAIN_INSTRUCTIONS else __process_BLOCK_JIT_CHAIN_INSTRUCTIONS;
    while (true) {
        const slot_before = ctx.field("windows_active_guest_thread_slot").*;
        // Only the fields a block can observe before writing them.
        // Assigning the whole record also zeroed `index` and the
        // sixteen-byte vector slot, and the state escapes into the
        // helpers, so those stores could not be optimised away. Emitted
        // code writes `index` before every helper call that reads it and
        // fills the vector slot before every helper that reads that, so
        // neither is ever read stale.
        const scratch_record = ctx.field("block_jit_scratch");
        scratch_record.abort = 0;
        scratch_record.chain_break = 0;
        scratch_record.chain_count = 0;
        // The chain runs until the step's instruction budget is spent,
        // as this loop does.
        const budget_instructions: u64 = chain_instruction_limit -| total_retired;
        scratch_record.chain_budget = budget_instructions << __process_block_jit.chain_count_shift;
        scratch_record.chain_retired_image = 0;
        scratch_record.chain_retired_other_mapped = 0;
        scratch_record.chain_previous = null;
        scratch_record.block = block;
        process_impl_guest_diagnostics.refreshBlockJitGuards(self, scratch_record);
        const rsp_in = ctx.field("regs").*.rsp;
        const rip_in = ctx.field("regs").*.rip;
        const tso_entry = __process_tso_memory.enterTranslatedCode(.jit_entry, block.start_rip);
        if (tso_entry.first) logTranslatedEntryViolation(self, block, tso_entry.pending, "chain");
        const completed = block.entry()(self, &block.helpers, scratch);
        // A helper may have run a nested slice of another guest thread;
        // whatever it bound, it has unbound, but read it again.
        ctx = process_impl_lifecycle.guestContextRef(self);
        const record = ctx.field("block_jit_scratch");
        jit.fpcr_writes +|= record.fpcr_writes;
        record.fpcr_writes = 0;
        // The block the chain left from: every hop records its successor.
        const last: *__process_block_jit.Block = if (record.block) |ran| @constCast(ran) else block;
        record.block = null;
        if (ctx.field("regs").*.rsp < __process_STACK_COLLAPSE_FLOOR and rsp_in >= __process_STACK_COLLAPSE_FLOOR) {
            process_impl_kernel_services.noteStackPointerCollapseInBlocks(self, rsp_in, rip_in, last, completed);
        }
        // The call may have run a whole chain of blocks without coming
        // back here once. Account all of them exactly as if each had
        // returned: `last_instruction_rip`, the totals and the title's
        // code-fetch ledger all read the same afterwards.
        const blocks_run = record.chain_count & __process_block_jit.chain_count_blocks_mask;
        if ((record.chain_count >> __process_block_jit.chain_count_shift) >= budget_instructions) {
            jit.chain_exits_budget +|= 1;
        } else if (record.chain_break != 0) {
            jit.chain_exits_break +|= 1;
        } else {
            jit.chain_exits_miss +|= 1;
        }
        if (blocks_run == 0) {
            total_retired +|= accountBlockJitIn(self, ctx, jit, block, completed);
        } else {
            total_retired +|= accountBlockJitRun(self, ctx, jit, block, last, completed, record);
            block = last;
            const hops: u64 = blocks_run - 1;
            jit.chained +|= hops;
            jit.native_chain_hops +|= hops;
        }
        if (ctx.field("guest_access_violation_pending").* or process_impl_lifecycle.isTerminated(self)) break;
        if (ctx.field("windows_guest_slice_yield_requested").* or
            ctx.field("windows_guest_handoff_requested").* or
            ctx.field("windows_active_guest_thread_slot").* != slot_before) break;
        if (slot_before) |slot| {
            if (self.windows_guest_threads[slot].status != .running) break;
        }
        if (!self.block_jit_chain_enabled) break;
        if (chained >= chain_block_limit or total_retired >= chain_instruction_limit) break;
        const next_rip = ctx.field("regs").*.rip;
        if (blockJitTargetHooked(self, next_rip)) break;
        const found = blockJitFindValidSlot(self, jit, next_rip) orelse break;
        if ((found.block.register_only or found.block.needs_verify) and !found.block.verified) break;
        // Remember the hop so the next execution of this block takes it
        // in translated code instead of coming back here for it.
        blockJitLink(self, jit, block, next_rip, found.block, found.slot);
        block = found.block;
        chained += 1;
        jit.chained +|= 1;
        jit.dispatch_relinks +|= 1;
    }
    // `step` advanced the clock once for this call; the chain retired
    // the rest.
    ctx.field("step_retired").* = @max(total_retired, 1);
    process_impl_instruction_decode.advanceWindowsGuestClockBy(self, ctx.field("step_retired").* - 1);
    if (process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").*) {
        // Exception dispatch reads the process-wide handler tables and
        // writes a CONTEXT/exception frame on this thread's own stack:
        // runtime tables, so the runtime lock, which also publishes this
        // thread's queued stores. It used to stop the world.
        var fault_guard = process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
        defer if (fault_guard) |*guard| guard.unlock();
        process_impl_guest_memory.raiseGuestAccessViolation(self);
    }
    return !process_impl_lifecycle.isTerminated(self);
}

pub fn blockJitResumeIndex(block: *const __process_block_jit.Block, cursor: u32, rip: u64) ?u32 {
    if (cursor < block.insns.len and block.insns[cursor].rip == rip) return cursor;
    if (cursor == 0) return null;
    const source = cursor - 1;
    if (source >= @bitSizeOf(u128) or (block.internal_sources >> @intCast(source)) & 1 == 0) return null;
    var index = cursor + 1;
    while (index < block.insns.len) : (index += 1) {
        if (block.insns[index].rip == rip) return index;
    }
    return null;
}

pub fn verifyBlockJit(self: *ElfState, jit: *__process_BlockJitState, block: *__process_block_jit.Block, slot_index: usize) bool {
    jit.lifetime.enter();
    defer leaveBlockJitExecution(self, jit);
    const before = process_impl_lifecycle.guestContextField(self, "regs").*;
    var interpreted: u32 = 0;
    var cursor: u32 = 0;
    while (cursor < block.insns.len) {
        // A branch the block takes internally lands on a later
        // instruction of the same block; the translation follows it.
        cursor = blockJitResumeIndex(block, cursor, process_impl_lifecycle.guestContextField(self, "regs").*.rip) orelse break;
        blockJitExecuteInsn(self, block, cursor);
        cursor += 1;
        interpreted += 1;
        if (process_impl_lifecycle.isTerminated(self) or process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").*) break;
    }
    const reference = process_impl_lifecycle.guestContextField(self, "regs").*;
    __process_tso_memory.flushActiveStoreBufferFor(.jit_fallback);
    block.verified = true;
    if (process_impl_lifecycle.isTerminated(self) or process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").*) {
        // The interpreter's run is the result; nothing to compare.
        process_impl_lifecycle.guestContextField(self, "step_retired").* = @max(interpreted, 1);
        process_impl_instruction_decode.advanceWindowsGuestClockBy(self, process_impl_lifecycle.guestContextField(self, "step_retired").* - 1);
        return false;
    }
    process_impl_lifecycle.guestContextField(self, "regs").* = before;
    process_impl_lifecycle.guestContextField(self, "block_jit_scratch").* = .{ .block = block };
    process_impl_guest_diagnostics.refreshBlockJitGuards(self, process_impl_lifecycle.guestContextField(self, "block_jit_scratch"));
    // The cross-check runs exactly this block against exactly this
    // block's instructions. Letting it chain would run its successor
    // too and report a mismatch against work the interpreter side never
    // did, dropping a block that was in fact correct.
    process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.chain_break = 1;
    const scratch = bindBlockJitRegisterFile(self);
    const tso_entry = __process_tso_memory.enterTranslatedCode(.jit_entry, block.start_rip);
    if (tso_entry.first) logTranslatedEntryViolation(self, block, tso_entry.pending, "verification");
    const completed = block.entry()(self, &block.helpers, scratch);
    process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.block = null;
    const translated = process_impl_lifecycle.guestContextField(self, "regs").*;

    var mismatch: ?[]const u8 = null;
    inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip" }) |name| {
        if (mismatch == null and @field(reference, name) != @field(translated, name)) mismatch = name;
    }
    if (mismatch == null and reference.rflags != translated.rflags) mismatch = "rflags";
    if (mismatch == null and completed != interpreted) mismatch = "retired count";
    if (mismatch) |name| {
        jit.mismatches +|= 1;
        if (jit.mismatches <= 8 or (jit.mismatches & (jit.mismatches - 1)) == 0) {
            var symbol_text: [__process_guest_symbol_text_bytes]u8 = undefined;
            __process_log.warn("PE64 BLOCK JIT MISMATCH: block=0x{x} at={s} instructions={d} first_op={s} last_op={s} differs_in={s} interpreter(rip=0x{x} rflags=0x{x} rax=0x{x}) translated(rip=0x{x} rflags=0x{x} rax=0x{x}) retired(interpreter/translated)={d}/{d} mismatches={d}; the interpreter's result stands, the block is dropped and this address stays interpreted", .{
                block.start_rip,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, block.start_rip, &symbol_text),
                block.insns.len,
                @tagName(block.insns[0].decoded.op),
                @tagName(block.insns[block.insns.len - 1].decoded.op),
                name,
                reference.rip,
                reference.rflags,
                reference.rax,
                translated.rip,
                translated.rflags,
                translated.rax,
                interpreted,
                completed,
                jit.mismatches,
            });
        }
        process_impl_lifecycle.guestContextField(self, "regs").* = reference;
        process_impl_lifecycle.guestContextField(self, "step_retired").* = @max(interpreted, 1);
        process_impl_instruction_decode.advanceWindowsGuestClockBy(self, process_impl_lifecycle.guestContextField(self, "step_retired").* - 1);
        blockJitRefuse(jit, block.start_rip);
        // Only while the slot still holds this block: anything the run
        // did in between may have evicted it already.
        if (jit.blocks[slot_index] == block) {
            dropBlockJitSlot(self, jit, slot_index);
            jit.dropped_mismatch +|= 1;
        }
        return false;
    }
    jit.verified +|= 1;
    // Trusted from here on, so hops may enter it.
    blockJitArmChain(block);
    // The translation's result is the one that stands (it is identical);
    // account it as a normal execution.
    const retired = accountBlockJit(self, jit, block, completed);
    process_impl_lifecycle.guestContextField(self, "step_retired").* = retired;
    process_impl_instruction_decode.advanceWindowsGuestClockBy(self, retired - 1);
    return true;
}

pub inline fn activeVerifyJournal(self: anytype) ?*__process_block_verify.Journal {
    if (self.verify_journal_users.load(.monotonic) == 0) return null;
    return process_impl_lifecycle.guestContextField(self, "verify_journal").*;
}

pub fn memoryBlockJournalSafe(block: *const __process_block_jit.Block) bool {
    if (block.touches_x87) return false;
    for (block.insns) |insn| {
        if (insn.decoded.lock) return false;
        const name = @tagName(insn.decoded.op);
        if (!__process_block_verify.journalSafeOp(name)) return false;
        // An indirect transfer may be completed in translated code by a
        // lock-free import lane or a hook, which the interpreted pass
        // only reaches the stub of: the two would disagree on RIP, and
        // putting the interpreter's state back would run the import twice.
        if (__process_std.mem.startsWith(u8, name, "call_mem") or __process_std.mem.startsWith(u8, name, "call_reg") or
            __process_std.mem.startsWith(u8, name, "jmp_mem") or __process_std.mem.startsWith(u8, name, "jmp_reg")) return false;
    }
    return true;
}

pub fn blockVerifyReachesHook(self: *const ElfState, block: *const __process_block_jit.Block) bool {
    if (blockJitTargetHooked(self, block.start_rip)) return true;
    for (block.insns) |insn| {
        const d = insn.decoded;
        switch (d.op) {
            .jmp_rel8, .call_rel32, .jcc_rel8, .jcc_rel32 => {
                const target = insn.rip +% d.len +% @as(u64, @bitCast(d.imm));
                if (blockJitTargetHooked(self, target)) return true;
            },
            else => {},
        }
    }
    return false;
}

pub fn verifyMemoryBlockJit(self: *ElfState, jit: *__process_BlockJitState, block: *__process_block_jit.Block, slot_index: usize) bool {
    if (!memoryBlockJournalSafe(block) or blockVerifyReachesHook(self, block)) {
        jit.verify_memory_unsafe +|= 1;
        block.verified = true;
        blockJitArmChain(block);
        return false;
    }
    jit.lifetime.enter();
    defer leaveBlockJitExecution(self, jit);
    const regs_field = process_impl_lifecycle.guestContextField(self, "regs");
    const before = regs_field.*;
    const xmm_before = process_impl_lifecycle.guestContextField(self, "xmm").*;
    const ymm_before = process_impl_lifecycle.guestContextField(self, "ymm_hi").*;
    const zmm_before = process_impl_lifecycle.guestContextField(self, "zmm_hi").*;
    const k_before = process_impl_lifecycle.guestContextField(self, "k").*;
    const fault_before = process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").*;
    var journal: __process_block_verify.Journal = .{};
    process_impl_lifecycle.guestContextField(self, "verify_journal").* = &journal;
    _ = self.verify_journal_users.fetchAdd(1, .monotonic);
    // The translation leaves the block at every taken branch, even one
    // to the next instruction (Xenia emits `je +0`), while the
    // interpreter walks on through it: compare at the boundary where
    // the translation stopped, so record the state after each step.
    const snapshot_limit = 256;
    var snapshot_regs: [snapshot_limit]__process_ElfRegs = undefined;
    var snapshot_journal: [snapshot_limit]u32 = undefined;
    var interpreted: u32 = 0;
    var cursor: u32 = 0;
    while (cursor < block.insns.len) {
        cursor = blockJitResumeIndex(block, cursor, regs_field.*.rip) orelse break;
        // A return into a hooked address (a callback's synthetic return,
        // a shim) would run that hook in a pass that is thrown away.
        const op_name = @tagName(block.insns[cursor].decoded.op);
        if (__process_std.mem.startsWith(u8, op_name, "ret")) {
            const target = process_impl_guest_memory.read64(self, regs_field.*.rsp);
            if (blockJitTargetHooked(self, target)) {
                journal.fail(.unsupported, target);
                break;
            }
        }
        blockJitExecuteInsn(self, block, cursor);
        cursor += 1;
        if (interpreted < snapshot_limit) {
            snapshot_regs[interpreted] = regs_field.*;
            snapshot_journal[interpreted] = journal.len;
        }
        interpreted += 1;
        if (process_impl_lifecycle.isTerminated(self) or process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").* or journal.failure != null) break;
    }
    process_impl_lifecycle.guestContextField(self, "verify_journal").* = null;
    _ = self.verify_journal_users.fetchSub(1, .monotonic);
    const reference = regs_field.*;
    const xmm_reference = process_impl_lifecycle.guestContextField(self, "xmm").*;
    if (process_impl_lifecycle.isTerminated(self)) {
        // The run is ending on the interpreter's word; nothing to compare.
        block.verified = true;
        process_impl_lifecycle.guestContextField(self, "step_retired").* = @max(interpreted, 1);
        return true;
    }
    const restore = struct {
        fn apply(state: *ElfState, regs: __process_ElfRegs, xmm: anytype, ymm: anytype, zmm: anytype, k: anytype) void {
            process_impl_lifecycle.guestContextField(state, "regs").* = regs;
            process_impl_lifecycle.guestContextField(state, "xmm").* = xmm;
            process_impl_lifecycle.guestContextField(state, "ymm_hi").* = ymm;
            process_impl_lifecycle.guestContextField(state, "zmm_hi").* = zmm;
            process_impl_lifecycle.guestContextField(state, "k").* = k;
        }
    };
    if (journal.failure != null or process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").* != fault_before) {
        // Nothing the pass did reached memory: put the registers back and
        // let the block run as usual, trusted unchecked.
        restore.apply(self, before, xmm_before, ymm_before, zmm_before, k_before);
        process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").* = fault_before;
        jit.verify_memory_failed +|= 1;
        block.verified = true;
        blockJitArmChain(block);
        return false;
    }
    restore.apply(self, before, xmm_before, ymm_before, zmm_before, k_before);
    process_impl_lifecycle.guestContextField(self, "block_jit_scratch").* = .{ .block = block };
    process_impl_guest_diagnostics.refreshBlockJitGuards(self, process_impl_lifecycle.guestContextField(self, "block_jit_scratch"));
    process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.chain_break = 1;
    const scratch = bindBlockJitRegisterFile(self);
    const tso_entry = __process_tso_memory.enterTranslatedCode(.jit_entry, block.start_rip);
    if (tso_entry.first) logTranslatedEntryViolation(self, block, tso_entry.pending, "verification");
    const completed = block.entry()(self, &block.helpers, scratch);
    process_impl_lifecycle.guestContextField(self, "block_jit_scratch").*.block = null;
    block.verified = true;
    const translated = regs_field.*;
    if (process_impl_lifecycle.isTerminated(self) or process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").*) {
        // The translation met a fault the interpreted pass did not (the
        // page changed between them): its run is the real one.
        const retired = accountBlockJit(self, jit, block, @max(completed, 1));
        process_impl_lifecycle.guestContextField(self, "step_retired").* = retired;
        return true;
    }

    const Mismatch = struct { what: []const u8, address: u64 = 0, interpreter: u64, translated: u64 };
    var mismatch: ?Mismatch = null;
    // Where the translation stopped short of the interpreter's walk, the
    // interpreter's state at that boundary is the reference, and only
    // the stores it had made by then.
    const early = completed > 0 and completed < interpreted and completed <= snapshot_limit and
        translated.rip == snapshot_regs[completed - 1].rip;
    const compare_regs = if (early) snapshot_regs[completed - 1] else reference;
    const compare_count: u32 = if (early) completed else interpreted;
    if (early) {
        journal.len = snapshot_journal[completed - 1];
        jit.verify_memory_early_exits +|= 1;
    }
    inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip" }) |name| {
        if (mismatch == null and @field(compare_regs, name) != @field(translated, name)) {
            mismatch = .{ .what = name, .interpreter = @field(compare_regs, name), .translated = @field(translated, name) };
        }
    }
    if (mismatch == null and completed != compare_count) mismatch = .{ .what = "retired", .interpreter = compare_count, .translated = completed };
    if (mismatch == null) {
        // Every exit owes all six flags except one through a call or a
        // ret (the Windows ABI) and a jump back into the block (only
        // what the code there reads).
        var owes_all = !(translated.rip >= block.start_rip and translated.rip < block.end_rip);
        for (block.insns) |insn| {
            const name = @tagName(insn.decoded.op);
            if (__process_std.mem.startsWith(u8, name, "call") or __process_std.mem.startsWith(u8, name, "ret")) owes_all = false;
        }
        if (owes_all and (compare_regs.rflags & 0x8D5) != (translated.rflags & 0x8D5)) {
            mismatch = .{ .what = "rflags", .interpreter = compare_regs.rflags, .translated = translated.rflags };
        }
    }
    if (mismatch == null and block.touches_vectors and !early) {
        const xmm_now = process_impl_lifecycle.guestContextField(self, "xmm").*;
        for (0..16) |index| {
            if (!__process_std.mem.eql(u8, &xmm_reference[index], &xmm_now[index])) {
                mismatch = .{
                    .what = "xmm",
                    .address = index,
                    .interpreter = __process_std.mem.readInt(u64, xmm_reference[index][0..8], .little),
                    .translated = __process_std.mem.readInt(u64, xmm_now[index][0..8], .little),
                };
                break;
            }
        }
    }
    var final: [__process_block_verify.Journal.capacity * 16]__process_block_verify.Journal.Byte = undefined;
    const stored = journal.finalBytes(&final);
    if (mismatch == null) {
        for (final[0..stored]) |byte| {
            const now = process_impl_guest_memory.read8(self, byte.address);
            if (now != byte.value) {
                mismatch = .{ .what = "memory", .address = byte.address, .interpreter = byte.value, .translated = now };
                break;
            }
        }
    }
    if (mismatch) |found| {
        jit.verify_memory_mismatches +|= 1;
        jit.mismatches +|= 1;
        if (comptime !@import("builtin").is_test) {
            if (jit.verify_memory_mismatches <= 32 or (jit.verify_memory_mismatches & (jit.verify_memory_mismatches - 1)) == 0) {
                logMemoryBlockMismatch(self, block, found.what, found.address, found.interpreter, found.translated, compare_count, completed, stored, jit.verify_memory_mismatches);
            }
        }
        // The interpreter's answer stands: its registers, and its bytes
        // over whatever the translation stored.
        regs_field.* = compare_regs;
        if (!early) process_impl_lifecycle.guestContextField(self, "xmm").* = xmm_reference;
        for (final[0..stored]) |byte| process_impl_guest_memory.write8(self, byte.address, byte.value);
        process_impl_lifecycle.guestContextField(self, "step_retired").* = @max(compare_count, 1);
        process_impl_instruction_decode.advanceWindowsGuestClockBy(self, process_impl_lifecycle.guestContextField(self, "step_retired").* - 1);
        blockJitRefuse(jit, block.start_rip);
        if (jit.blocks[slot_index] == block) {
            dropBlockJitSlot(self, jit, slot_index);
            jit.dropped_mismatch +|= 1;
        }
        return true;
    }
    jit.verify_memory_checked +|= 1;
    blockJitArmChain(block);
    const retired = accountBlockJit(self, jit, block, completed);
    process_impl_lifecycle.guestContextField(self, "step_retired").* = retired;
    process_impl_instruction_decode.advanceWindowsGuestClockBy(self, retired - 1);
    return true;
}

pub fn logMemoryBlockMismatch(self: *ElfState, block: *const __process_block_jit.Block, what: []const u8, address: u64, interpreter: u64, translated: u64, interpreted: u32, completed: u32, stored: usize, count: u64) void {
    var symbol_text: [__process_guest_symbol_text_bytes]u8 = undefined;
    var ops: [1024]u8 = undefined;
    var used: usize = 0;
    for (block.insns, 0..) |insn, index| {
        const piece = __process_std.fmt.bufPrint(ops[used..], "{s}{s}", .{ if (index == 0) "" else ",", @tagName(insn.decoded.op) }) catch break;
        used += piece.len;
    }
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
    const shown_bytes = block.bytes[0..@min(block.bytes.len, 192)];
    __process_log.warn("PE64 BLOCK JIT MISMATCH: kind=memory_block block=0x{x} at={s} instructions={d} differs_in={s} index_or_address=0x{x} interpreter=0x{x} translated=0x{x} retired(interpreter/translated)={d}/{d} stored_bytes={d} thread='{s}' mismatches={d} ops=[{s}] bytes={x}; the interpreter's registers and stored bytes were put back, the block is dropped and this address stays interpreted. In parallel mode a concurrent store to memory the block reads can also produce this", .{
        block.start_rip,
        process_impl_kernel_services.describeGuestAddressOrUnnamed(self, block.start_rip, &symbol_text),
        block.insns.len,
        what,
        address,
        interpreter,
        translated,
        interpreted,
        completed,
        stored,
        process_impl_guest_diagnostics.guestThreadLabel(self, if (slot) |index| @intCast(@min(index + 1, 255)) else 0),
        count,
        ops[0..used],
        shown_bytes,
    });
}

pub fn runBlockJit(self: *ElfState) ?bool {
    // A bound worker runs translated code too: the block addresses the
    // executing context's registers through its own scratch record.
    // Under the parallel scheduler only the process owner reaches this
    // arena (`step` keeps worker contexts on the interpreter), so the
    // owner's blocks run beside the workers without any gate.
    if (self.block_jit_tlb_active == null) self.block_jit_tlb_active = ownerBlockJitTlb(self);
    const jit = blockJitActive(self) orelse return null;
    const rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    const base = jit.firstSlot(rip);
    for (base..base + __process_BLOCK_JIT_WAYS) |slot_index| {
        const block = jit.blocks[slot_index] orelse continue;
        if (block.start_rip != rip) continue;
        if (blockJitValidate(self, jit, block)) return executeBlockJit(self, jit, block, slot_index);
        dropBlockJitSlot(self, jit, slot_index);
        jit.dropped_stale +|= 1;
        break;
    }
    const hot = blockJitHotness(jit, rip);
    if (hot.refused) {
        // Retried after `block_jit_refusal_retry_base << retries`
        // interpreted runs: the cost of a refusal that keeps failing is
        // one compile attempt per thousands of interpreted runs.
        const due = hot.retries < __process_block_jit_refusal_retry_limit and
            hot.refused_runs >= __process_block_jit_refusal_retry_base << @intCast(hot.retries);
        if (!due) {
            hot.refused_runs +|= 1;
            jit.interpreted_refused +|= 1;
            if (jit.interpreted_refused % __process_BlockJitState.interpreted_heat_stride == 0) jit.refused_heat.sample(rip);
            return null;
        }
        hot.refused = false;
        hot.retries += 1;
        hot.refused_runs = 0;
        hot.count = jit.hot_threshold -| 1;
        jit.refusal_retries +|= 1;
    }
    hot.count +|= 1;
    if (hot.count < jit.hot_threshold) {
        jit.interpreted_cold +|= 1;
        if (jit.interpreted_cold % __process_BlockJitState.interpreted_heat_stride == 0) jit.interpreted_heat.sample(rip);
        return null;
    }
    // The code memory is full and cannot be reset under the execution
    // this step is nested in; compile once it has been.
    if (jit.lifetime.reset_pending) {
        jit.interpreted_reset_pending +|= 1;
        return null;
    }
    const block = compileBlockJit(self, jit, rip) orelse {
        // Out of code memory under a live execution is not this
        // address's failure: keep it hot, not refused.
        if (jit.lifetime.reset_pending) {
            jit.interpreted_reset_pending +|= 1;
            return null;
        }
        hot.refused = true;
        hot.refused_runs = 0;
        jit.compile_refusals +|= 1;
        jit.interpreted_refused +|= 1;
        noteBlockJitRefusal(jit, rip, hot.retries);
        return null;
    };
    // Compiled: the address needs no counter now, and keeping one held a
    // way of its 4-way set at a count no warming address can beat, so
    // a set of compiled addresses left the next warming one fighting
    // its neighbours for a single way - 4.1 million replacements and
    // 19.7 million cold interpreted steps on Halo 3's main thread on
    // 2026-10-02. A block that is later dropped warms up again from zero.
    // Freed before any growth below: growing replaces the hotness array.
    hot.* = .{};
    // A full set is capacity pressure. Enough of it grows the table,
    // which moves this address to a set with room: a growth never
    // evicts, and each new set is fed by one old one.
    var seat_base = base;
    if (blockJitSetFull(jit, seat_base)) {
        jit.pressure +|= 1;
        if (jit.growIfPressed(self.allocator)) seat_base = jit.firstSlot(rip);
    }
    // An empty way, else the way that has run least.
    var chosen: usize = seat_base;
    var chosen_executions: u64 = __process_std.math.maxInt(u64);
    for (seat_base..seat_base + __process_BLOCK_JIT_WAYS) |slot_index| {
        if (jit.blocks[slot_index]) |resident| {
            if (resident.executions < chosen_executions) {
                chosen = slot_index;
                chosen_executions = resident.executions;
            }
        } else {
            chosen = slot_index;
            chosen_executions = 0;
            break;
        }
    }
    if (jit.blocks[chosen] != null) {
        jit.slot_evictions +|= 1;
        dropBlockJitSlot(self, jit, chosen);
        // Age the survivors. A block that was hot once must not keep its
        // way for the rest of the run against code that is hot now.
        for (jit.blocks[seat_base .. seat_base + __process_BLOCK_JIT_WAYS]) |maybe| {
            if (maybe) |resident| resident.executions >>= 1;
        }
    }
    jit.blocks[chosen] = block;
    return executeBlockJit(self, jit, block, chosen);
}

pub fn blockJitSetFull(jit: *const __process_BlockJitState, base: usize) bool {
    for (jit.blocks[base .. base + __process_BLOCK_JIT_WAYS]) |slot| {
        if (slot == null) return false;
    }
    return true;
}

pub fn reportBlockJit(self: *ElfState) void {
    const jit = self.block_jit orelse {
        __process_log.info("PE64 BLOCK JIT: active=false enabled={} reason={s}; every instruction was interpreted", .{
            self.block_jit_enabled and !self.block_jit_unavailable,
            if (self.block_jit_unavailable) self.block_jit_disabled_reason else if (self.block_jit_enabled) "no instruction has stepped yet" else "ROSETTE_X64_BLOCK_JIT=0",
        });
        return;
    };
    const interpreted = process_impl_run_reporting.totalInterpretedSteps(self);
    const translated_percent = if (interpreted == 0) 0 else @divTrunc(jit.instructions_retired *| 100, interpreted);
    const mean_block = if (jit.executions == 0) 0 else @divTrunc(jit.instructions_retired, jit.executions);
    const table_load_percent = @divTrunc(jit.liveBlocks() *| 100, jit.blocks.len);
    const eviction_per_compile = if (jit.compiled == 0) 0 else @divTrunc(jit.slot_evictions *| 100, jit.compiled);
    const reset_per_compile = if (jit.compiled == 0) 0 else @divTrunc(jit.resets *| 100, jit.compiled);
    __process_log.info("PE64 BLOCK JIT: active=true table(entries/ways/live/load_percent)={d}/{d}/{d}/{d} hot_threshold={d} churn(evictions/compiles_percent/resets/compiles_percent)={d}/{d}/{d}/{d} blocks(live/compiled/refused/failed/dropped/evicted/resets)={d}/{d}/{d}/{d}/{d}/{d}/{d} dropped(stale/unmapped/reset/mismatch)={d}/{d}/{d}/{d} compiled_instructions(native/fallback/flags_elided/flags_narrowed)={d}/{d}/{d}/{d} executions={d} retired={d} ({d}% of the run) mean_block_len={d} conditionals_followed={d} flag_completions={d} native_chain(hops/links)={d}/{d}; high eviction or reset ratios indicate translation-cache churn; retired counts the block-JIT lane including interpreter fallback helpers, not exclusively native instructions", .{
        jit.blocks.len,
        __process_BLOCK_JIT_WAYS,
        jit.liveBlocks(),
        table_load_percent,
        jit.hot_threshold,
        jit.slot_evictions,
        eviction_per_compile,
        jit.resets,
        reset_per_compile,
        jit.liveBlocks(),
        jit.compiled,
        jit.compile_refusals,
        jit.compile_failures,
        jit.invalidations,
        jit.slot_evictions,
        jit.resets,
        jit.dropped_stale,
        jit.dropped_unmapped,
        jit.dropped_reset,
        jit.dropped_mismatch,
        jit.native_instructions_compiled,
        jit.fallback_instructions_compiled,
        jit.flags_elided,
        jit.flags_narrowed,
        jit.executions,
        jit.instructions_retired,
        translated_percent,
        mean_block,
        jit.conditionals_followed,
        jit.flag_completions,
        jit.native_chain_hops,
        jit.links_armed,
    });
    const fallback_percent = if (jit.instructions_retired == 0) 0 else @divTrunc(jit.fallback_calls *| 100, jit.instructions_retired);
    __process_log.info("PE64 BLOCK JIT LANE: chained={d} ({d}% of executions entered from the previous block) fallback_calls={d} ({d}% of retired) x87_helpers(raw/memory)={d}/{d} aborts={d} continuation_write_aborts={d} revalidations={d} verified={d} mismatches={d} tlb(considers/fills/refused/invalidations/flushes)={d}/{d}/{d}/{d}/{d} tlb_bail(traced/straddle/null_page)={d}/{d}/{d} direct_calls(native/hooked)={d}/{d} code_bytes(used/capacity)={d}/{d}; x87 helpers bypass the general interpreter fallback while preserving the guest x87 model and memory ordering; direct_calls counts call sites, not executions, and hooked targets retain their interpreter-owned shims; integer/register verification does not cover all vector or memory effects; mismatches must read zero", .{
        jit.chained,
        if (jit.executions == 0) 0 else @divTrunc(jit.chained *| 100, jit.executions),
        jit.fallback_calls,
        fallback_percent,
        jit.x87_fast_helpers,
        jit.x87_memory_helpers,
        jit.aborts,
        jit.continuation_write_aborts,
        jit.revalidations,
        jit.verified,
        jit.mismatches,
        self.block_jit_tlb_considers,
        jit.tlb_fills,
        jit.tlb_fill_refusals,
        jit.tlb_invalidations,
        jit.tlb_flushes,
        self.block_jit_tlb_bail_traced,
        self.block_jit_tlb_bail_straddle,
        self.block_jit_tlb_bail_null_page,
        jit.call_targets_plain,
        jit.call_targets_hooked,
        jit.memory.used,
        jit.memory.capacity(),
    });
    reportBlockJitTlbRefusalReasons(self, "", jit.tlb_refusal_stats);
    // How much of the guest register file the translated code kept in
    // host registers. Per block it is at most four; a mean near zero
    // means blocks are too short, or too spread across registers, for
    // the cache to find anything worth holding.
    __process_log.info("PE64 BLOCK JIT REGISTERS: cached={d} across {d} compiled blocks (mean {d}.{d:0>2} per block, at most 4); a cached guest register lives in x25-x28 for its block and meets the register file only at an exit and around an interpreted instruction", .{
        jit.cached_registers,
        jit.compiled,
        if (jit.compiled == 0) 0 else jit.cached_registers / jit.compiled,
        if (jit.compiled == 0) 0 else ((jit.cached_registers *| 100) / jit.compiled) % 100,
    });
    __process_log.info("PE64 BLOCK JIT HOISTING: accesses={d} across {d} compiled blocks; each is a [base+disp] access that reaches memory through one per-block page translation held in x29 instead of its own TLB probe", .{
        jit.hoisted_accesses,
        jit.compiled,
    });
    __process_log.info("PE64 BLOCK JIT NESTING: nested_executions={d} nesting_peak={d} deferred(frees/resets)={d}/{d} retired_peak={d} retire_leaks={d} reset_pending={} live_at_exit={d}; a nested execution is a translated block entered while another was still on the host stack (a block's helper ran another guest thread's slice, as a wait import does); what it dropped, evicted or reset was held until the outermost block returned, and retire_leaks and live_at_exit must read zero", .{
        jit.lifetime.stats.nested_executions,
        jit.lifetime.stats.nesting_peak,
        jit.lifetime.stats.deferred_frees,
        jit.lifetime.stats.deferred_resets,
        jit.lifetime.stats.retired_peak,
        jit.lifetime.stats.retire_leaks,
        jit.lifetime.reset_pending,
        jit.lifetime.active_executions,
    });
    reportBlockJitFallbackOps(self, jit);
    reportParallelWorkerBlockJits(self);
}

pub fn reportParallelWorkerBlockJits(self: *ElfState) void {
    var states: u64 = 0;
    var refused: u64 = 0;
    var live: u64 = 0;
    var compiled: u64 = 0;
    var compile_refusals: u64 = 0;
    var executions: u64 = 0;
    var retired: u64 = 0;
    var fallback_calls: u64 = 0;
    var resets: u64 = 0;
    var mismatches: u64 = 0;
    var nested: u64 = 0;
    var tlb_fills: u64 = 0;
    var tlb_refusals: u64 = 0;
    var tlb_refusal_cache_lookups: u64 = 0;
    var tlb_refusal_cache_hits: u64 = 0;
    var tlb_refusal_cache_misses: u64 = 0;
    var tlb_refusal_stats: __process_tlb_diagnostics.RefusalStats = .{};
    var mapped_transfer_checks: u64 = 0;
    var mapped_transfer_native: u64 = 0;
    var hooked_transfer_exact_checks: u64 = 0;
    var hooked_transfer_exact_claims: u64 = 0;
    var hooked_transfer_filter_false_positives: u64 = 0;
    var x87_fast_helpers: u64 = 0;
    var x87_memory_helpers: u64 = 0;
    var returns_owing_flags: u64 = 0;
    for (self.windows_guest_threads) |thread| {
        if (thread.parallel_block_jit_refused) refused += 1;
        const jit = thread.parallel_block_jit orelse continue;
        states += 1;
        tlb_fills +|= jit.tlb_fills;
        tlb_refusals +|= jit.tlb_fill_refusals;
        tlb_refusal_cache_lookups +|= jit.tlb_refusal_cache.lookups;
        tlb_refusal_cache_hits +|= jit.tlb_refusal_cache.hits;
        tlb_refusal_cache_misses +|= jit.tlb_refusal_cache.misses;
        tlb_refusal_stats.merge(jit.tlb_refusal_stats);
        mapped_transfer_checks +|= jit.mapped_transfer_checks;
        mapped_transfer_native +|= jit.mapped_transfer_native;
        hooked_transfer_exact_checks +|= jit.hooked_transfer_exact_checks;
        hooked_transfer_exact_claims +|= jit.hooked_transfer_exact_claims;
        hooked_transfer_filter_false_positives +|= jit.hooked_transfer_filter_false_positives;
        x87_fast_helpers +|= jit.x87_fast_helpers;
        x87_memory_helpers +|= jit.x87_memory_helpers;
        live += jit.liveBlocks();
        compiled +|= jit.compiled;
        compile_refusals +|= jit.compile_refusals;
        executions +|= jit.executions;
        retired +|= jit.instructions_retired;
        fallback_calls +|= jit.fallback_calls;
        resets +|= jit.resets;
        mismatches +|= jit.mismatches;
        nested +|= jit.lifetime.stats.nested_executions;
        returns_owing_flags +|= jit.returns_owing_flags;
    }
    if (states == 0 and refused == 0) {
        reportParallelTlbInvalidationWork(self);
        return;
    }
    if (self.block_jit) |owner| returns_owing_flags +|= owner.returns_owing_flags;
    __process_log.info("PE64 BLOCK JIT RETURN FLAGS: blocks={d}; compiled blocks whose ret hands flags back to the caller. Under the Windows calling convention a return owes no flag, but a hand-written helper may return its result in one: Xenia's stwcx. helper returns success in ZF, and dropping it made failed stores report success. Nonzero means that helper is translated with its result intact", .{returns_owing_flags});
    const worker_steps = process_impl_lifecycle.windowsWorkerSteps(self);
    __process_log.info("PE64 BLOCK JIT WORKERS: states={d} refused={d} blocks(live/compiled/refused)={d}/{d}/{d} executions={d} retired={d} ({d}% of worker instructions) fallback_calls={d} x87_helpers(raw/memory)={d}/{d} mapped_transfer_helper(checks/accepted)={d}/{d} resets={d} mismatches={d} nested={d}; inline code-cache range admissions bypass the helper counters; x87 helpers bypass the general interpreter fallback while preserving guest state and memory ordering; each worker uses its own translator cache", .{
        states,
        refused,
        live,
        compiled,
        compile_refusals,
        executions,
        retired,
        if (worker_steps == 0) 0 else @min(100, @divTrunc(retired *| 100, worker_steps)),
        fallback_calls,
        x87_fast_helpers,
        x87_memory_helpers,
        mapped_transfer_checks,
        mapped_transfer_native,
        resets,
        mismatches,
        nested,
    });
    __process_log.info("PE64 BLOCK JIT HOOK FILTER: exact_checks={d} exact_claims={d} false_positives_kept_native={d}; a Bloom hit is now confirmed against the live hook tables, including saturated kernel-census exports", .{
        hooked_transfer_exact_checks,
        hooked_transfer_exact_claims,
        hooked_transfer_filter_false_positives,
    });
    __process_log.info("PE64 BLOCK JIT WORKER TLB: direct_route={} fills={d} refused={d} refusal_cache(lookups/hits/misses)={d}/{d}/{d} cross_thread_invalidations={d} raced_fills_retired={d}; refusal-cache hits skip repeated admission proofs for still-refused pages; complete page-aligned native maps can use the ordered direct route in parallel mode, while partial or unproven aliases stay on the device-aware helper", .{
        parallelDirectTlbActive(self),
        tlb_fills,
        tlb_refusals,
        tlb_refusal_cache_lookups,
        tlb_refusal_cache_hits,
        tlb_refusal_cache_misses,
        self.parallel_tlb_cross_invalidations.load(.monotonic),
        self.parallel_tlb_raced_fills.load(.monotonic),
    });
    reportBlockJitTlbRefusalReasons(self, "WORKER ", tlb_refusal_stats);
    reportParallelTlbInvalidationWork(self);
    reportParallelWorkerBlockJitThreads(self);
    reportParallelWorkerFallbackOps(self);
}

pub fn reportParallelWorkerBlockJitThreads(self: *ElfState) void {
    const shown = 8;
    var ranked: [shown]?usize = @splat(null);
    var ranked_interpreted: [shown]u64 = @splat(0);
    for (self.windows_guest_threads, 0..) |thread, slot| {
        const jit = thread.parallel_block_jit orelse continue;
        const interpreted = jit.interpreted_cold +| jit.interpreted_refused +| jit.interpreted_reset_pending;
        if (interpreted == 0 and jit.growths == 0) continue;
        for (0..shown) |rank| {
            if (ranked[rank] != null and interpreted <= ranked_interpreted[rank]) continue;
            var move: usize = shown - 1;
            while (move > rank) : (move -= 1) {
                ranked[move] = ranked[move - 1];
                ranked_interpreted[move] = ranked_interpreted[move - 1];
            }
            ranked[rank] = slot;
            ranked_interpreted[rank] = interpreted;
            break;
        }
    }
    if (self.block_jit_verify_memory) {
        for (self.windows_guest_threads, 0..) |thread, slot| {
            const jit = thread.parallel_block_jit orelse continue;
            if (jit.verify_memory_checked == 0 and jit.verify_memory_mismatches == 0 and jit.verify_memory_unsafe == 0 and jit.verify_memory_failed == 0) continue;
            __process_log.info("PE64 BLOCK JIT MEMORY VERIFY: slot={d} name='{s}' checked={d} mismatches={d} unchecked(unsafe_op/journal_failed)={d}/{d} register_only_verified={d}; each mismatch is a PE64 BLOCK JIT MISMATCH kind=memory_block line naming the block, its ops and its bytes", .{
                slot,
                process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(slot + 1, 255))),
                jit.verify_memory_checked,
                jit.verify_memory_mismatches,
                jit.verify_memory_unsafe,
                jit.verify_memory_failed,
                jit.verified,
            });
        }
    }
    for (ranked) |maybe_slot| {
        const slot = maybe_slot orelse break;
        const thread = &self.windows_guest_threads[slot];
        const jit = thread.parallel_block_jit.?;
        __process_log.info("PE64 BLOCK JIT WORKER THREAD: slot={d} name='{s}' table={d} growths={d} live={d} compiled={d} evictions={d} hotness_replacements={d} resets={d} code_mib(used/reserved)={d}/{d} executions={d} retired={d} interpreted(cold/refused/reset_pending)={d}/{d}/{d} fallback_calls={d} revalidations={d} dropped_stale={d} dispatch(entries/relinks/native_hops)={d}/{d}/{d} retired_per_dispatch={d} chain_exits(budget/break/miss)={d}/{d}/{d} tlb_fills={d} fpcr_writes={d}; an interpreted step costs about a hundred translated instructions: cold means the address had not run hot_threshold times since it took its hotness entry, and hotness_replacements beside it is the table thrashing; a dispatch entry is a return through step, a relink is a hop made in Zig, a native hop never left translated code; a chain exit on miss is a successor neither the block's ways nor the jump cache could prove; fpcr_writes counts translated MXCSR loads that changed FZ or RMode, about 12 ns each", .{
            slot,
            if (thread.name_len != 0) thread.nameText() else "<unnamed>",
            jit.blocks.len,
            jit.growths,
            jit.liveBlocks(),
            jit.compiled,
            jit.slot_evictions,
            jit.hotness_replacements,
            jit.resets,
            jit.memory.used >> 20,
            jit.memory.capacity() >> 20,
            jit.executions,
            jit.instructions_retired,
            jit.interpreted_cold,
            jit.interpreted_refused,
            jit.interpreted_reset_pending,
            jit.fallback_calls,
            jit.revalidations,
            jit.dropped_stale,
            jit.dispatch_entries,
            jit.dispatch_relinks,
            jit.native_chain_hops,
            if (jit.dispatch_entries == 0) 0 else jit.instructions_retired / jit.dispatch_entries,
            jit.chain_exits_budget,
            jit.chain_exits_break,
            jit.chain_exits_miss,
            jit.tlb_fills,
            jit.fpcr_writes,
        });
        var text: [__process_guest_symbol_text_bytes]u8 = undefined;
        reportBlockJitRefusals(self, slot, jit);
        for (jit.interpreted_heat.top(), 0..) |hotspot, rank| {
            if (hotspot.count == 0) break;
            __process_log.info("PE64 BLOCK JIT WORKER THREAD:   slot={d} interpreted rank={d} region=0x{x} at={s} samples={d}..{d} of {d} (one per {d} cold steps)", .{
                slot,
                rank + 1,
                hotspot.address,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, hotspot.address, &text),
                hotspot.count - hotspot.error_bound,
                hotspot.count,
                jit.interpreted_heat.samples,
                __process_BlockJitState.interpreted_heat_stride,
            });
        }
        for (jit.refused_heat.top(), 0..) |hotspot, rank| {
            if (hotspot.count == 0) break;
            var op_text: [64]u8 = undefined;
            __process_log.info("PE64 BLOCK JIT WORKER THREAD:   slot={d} refused rank={d} region=0x{x} at={s} first_op={s} samples={d}..{d} of {d} (one per {d} refused steps)", .{
                slot,
                rank + 1,
                hotspot.address,
                process_impl_kernel_services.describeGuestAddressOrUnnamed(self, hotspot.address, &text),
                describeGuestOpAt(self, hotspot.address, &op_text),
                hotspot.count - hotspot.error_bound,
                hotspot.count,
                jit.refused_heat.samples,
                __process_BlockJitState.interpreted_heat_stride,
            });
        }
    }
}

pub fn describeGuestOpAt(self: *ElfState, address: u64, buffer: []u8) []const u8 {
    var bytes: [16]u8 = undefined;
    const fetched = process_impl_instruction_decode.guestInstructionBytes(self, address, &bytes);
    if (fetched.len == 0) return "<unreadable>";
    const decoded = __process_decodeInsn(fetched);
    return __process_std.fmt.bufPrint(buffer, "{s}", .{@tagName(decoded.op)}) catch @tagName(decoded.op);
}

pub fn reportBlockJitTlbRefusalReasons(self: *ElfState, label: []const u8, stats: __process_tlb_diagnostics.RefusalStats) void {
    _ = self;
    var text: [1024]u8 = undefined;
    __process_log.info("PE64 BLOCK JIT {s}TLB REFUSAL REASONS:{s}; counts are exact per helper admission attempt; each address is the first guest page refused for that reason", .{
        label,
        stats.format(&text),
    });
}

pub fn reportParallelTlbInvalidationWork(self: *const ElfState) void {
    __process_log.info("PE64 SRW FAST PATH: acquires={d} releases={d} lane={} owner_stack(all/captured/skipped)={}/{d}/{d}; SRW ownership, waiters and TSO fences remain under the runtime mutex; unsampled acquisition stacks are cleared, and live owner stacks remain available to stall diagnostics", .{
        self.windows_srw_fast_acquires.load(.monotonic), self.windows_srw_fast_releases.load(.monotonic), self.windows_srw_import_lane,
        self.windows_srw_stack_capture_all,              self.windows_srw_stack_captures,                 self.windows_srw_stack_skipped,
    });
    __process_log.info("PE64 CPU FAST PATHS: streaming_stores={} pause_batches={} additional_pause_instructions={d}; streaming stores retain release ordering and require admitted write pages with no guest queue; additional_pause_instructions retired inside bounded PAUSE bundles still count toward hint and execution totals", .{
        self.block_jit_streaming_stores_enabled,                   self.parallel_pause_batches_enabled,
        self.parallel_pause_batched_instructions.load(.monotonic),
    });
    const work = self.parallel_tlb_invalidation_work.snapshot();
    __process_log.info("PE64 BLOCK JIT TLB INVALIDATION WORK: range_calls={d} requested_pages={d} wide_range_flushes={d} explicit_flushes={d} table_visits={d} tag_slots_touched={d}; tag_slots counts the tags probed or written across executor tables and exposes broad invalidation fanout", .{
        work.range_calls,
        work.requested_pages,
        work.wide_range_flushes,
        work.explicit_flushes,
        work.table_visits,
        work.tag_slots_touched,
    });
}

pub fn reportParallelWorkerFallbackOps(self: *ElfState) void {
    const Sums = struct {
        calls: u64 = 0,
        ops: [__state_op_value_limit]u64 = @splat(0),
        samples: [__state_op_value_limit]u64 = @splat(0),
        nanos: [__state_op_value_limit]u64 = @splat(0),
        reasons: [@typeInfo(__process_block_jit.FallbackReason).@"enum".fields.len]u64 = @splat(0),
        transfer_imports: u64 = 0,
        transfer_hooked: u64 = 0,
        transfer_plain: u64 = 0,
        transfer_target_overflow: u64 = 0,
        transfer_targets: [__process_BlockJitState.transfer_target_slots]__process_BlockJitState.TransferTarget = @splat(.{}),
    };
    const sums = self.allocator.create(Sums) catch return;
    defer self.allocator.destroy(sums);
    sums.* = .{};
    var any = false;
    for (self.windows_guest_threads) |thread| {
        const jit = thread.parallel_block_jit orelse continue;
        any = true;
        sums.calls +|= jit.fallback_calls;
        for (&sums.ops, jit.fallback_ops) |*sum, value| sum.* +|= value;
        for (&sums.samples, jit.fallback_cost_sample_count) |*sum, value| sum.* +|= value;
        for (&sums.nanos, jit.fallback_cost_sampled_nanos) |*sum, value| sum.* +|= value;
        for (&sums.reasons, jit.fallback_reason_counts) |*sum, value| sum.* +|= value;
        sums.transfer_imports +|= jit.transfer_fallback_imports;
        sums.transfer_hooked +|= jit.transfer_fallback_hooked;
        sums.transfer_plain +|= jit.transfer_fallback_plain;
        sums.transfer_target_overflow +|= jit.transfer_target_overflow;
        for (jit.transfer_targets) |entry| {
            if (entry.count == 0) continue;
            var matching: ?*__process_BlockJitState.TransferTarget = null;
            var vacant: ?*__process_BlockJitState.TransferTarget = null;
            for (&sums.transfer_targets) |*candidate| {
                if (candidate.count != 0 and candidate.target == entry.target and candidate.op == entry.op) {
                    matching = candidate;
                    break;
                }
                if (candidate.count == 0 and vacant == null) vacant = candidate;
            }
            if (matching) |candidate| {
                candidate.count +|= entry.count;
            } else if (vacant) |candidate| {
                candidate.* = entry;
            } else {
                sums.transfer_target_overflow +|= entry.count;
            }
        }
    }
    if (!any) return;
    reportBlockJitFallbackView(.{
        .label = "WORKER ",
        .calls = sums.calls,
        .ops = &sums.ops,
        .samples = &sums.samples,
        .nanos = &sums.nanos,
        .reasons = &sums.reasons,
    });
    reportBlockJitTransferFallbackSummary(
        self,
        "WORKER ",
        sums.transfer_imports,
        sums.transfer_hooked,
        sums.transfer_plain,
        &sums.transfer_targets,
        sums.transfer_target_overflow,
    );
    process_impl_guest_memory.reportImportHistogram(self);
}

pub fn reportBlockJitFallbackOps(self: *ElfState, jit: *const __process_BlockJitState) void {
    reportBlockJitFallbackView(.{
        .label = "",
        .calls = jit.fallback_calls,
        .ops = &jit.fallback_ops,
        .samples = &jit.fallback_cost_sample_count,
        .nanos = &jit.fallback_cost_sampled_nanos,
        .reasons = &jit.fallback_reason_counts,
    });
    reportBlockJitTransferFallbacks(self, jit);
}

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

pub fn reportBlockJitTransferFallbacks(self: *ElfState, jit: *const __process_BlockJitState) void {
    reportBlockJitCallRefusals(self);
    reportBlockJitTransferFallbackSummary(
        self,
        "",
        jit.transfer_fallback_imports,
        jit.transfer_fallback_hooked,
        jit.transfer_fallback_plain,
        &jit.transfer_targets,
        jit.transfer_target_overflow,
    );
}

pub fn reportBlockJitCallRefusals(self: *ElfState) void {
    var refusal_text: [512]u8 = undefined;
    var refusal_written: usize = 0;
    for (0..self.block_jit_call_refusals.len) |index| {
        const piece = __process_std.fmt.bufPrint(refusal_text[refusal_written..], " {s}={d}", .{
            @tagName(@as(__process_BlockJitCallRefusal, @enumFromInt(index))),
            @atomicLoad(u64, &self.block_jit_call_refusals[index], .monotonic),
        }) catch break;
        refusal_written += piece.len;
    }
    __process_log.info("PE64 BLOCK JIT CALL REFUSALS (compile-time, all translators):{s}; each is a direct call compiled as an interpreter fallback for the life of its block, and the first sites of each reason are named by PE64 BLOCK JIT CALL REFUSAL lines", .{refusal_text[0..refusal_written]});
}

pub fn reportBlockJitTransferFallbackSummary(
    self: *ElfState,
    label: []const u8,
    imports: u64,
    hooked: u64,
    plain: u64,
    targets: *const [__process_BlockJitState.transfer_target_slots]__process_BlockJitState.TransferTarget,
    target_overflow: u64,
) void {
    const total = imports +| hooked +| plain;
    if (total == 0) return;
    __process_log.info("PE64 BLOCK JIT {s}TRANSFER FALLBACKS: imports={d} hooked={d} plain={d} target_overflow={d}; hooked is a target a shim, milestone, census entry or hook-filter collision claims, plain is one no hook claims", .{
        label,
        imports,
        hooked,
        plain,
        target_overflow,
    });
    var ranked: [10]usize = undefined;
    var ranked_count: usize = 0;
    for (targets.*, 0..) |entry, entry_index| {
        if (entry.count == 0) continue;
        var position = ranked_count;
        while (position > 0 and targets[ranked[position - 1]].count < entry.count) : (position -= 1) {}
        if (position >= ranked.len) continue;
        var cursor = @min(ranked_count, ranked.len - 1);
        while (cursor > position) : (cursor -= 1) ranked[cursor] = ranked[cursor - 1];
        ranked[position] = entry_index;
        if (ranked_count < ranked.len) ranked_count += 1;
    }
    for (ranked[0..ranked_count], 1..) |entry_index, rank| {
        const entry = targets[entry_index];
        var name_buffer: [256]u8 = undefined;
        const name = process_impl_kernel_services.describeGuestAddressOrUnnamed(self, entry.target, &name_buffer);
        const milestone = process_impl_guest_diagnostics.isGuestMilestoneAddress(self, entry.target);
        const census = self.guest_kernel_calls.exportAt(entry.target) != null;
        const filter_hit = __process_block_jit.hookFilterHas(&self.block_jit_hook_filter, entry.target);
        __process_log.info("PE64 BLOCK JIT {s}TRANSFER FALLBACKS:   rank={d} op={s} target=0x{x} ({s}) calls={d} hooked={} milestone={} census={} filter_bit={}", .{
            label,
            rank,
            __state_op_names[entry.op] orelse "?",
            entry.target,
            name,
            entry.count,
            entry.hooked,
            milestone,
            census,
            filter_hit,
        });
    }
}

pub fn step(self: *ElfState) bool {
    var execution_guard: ?__process_GuestExecutionGate.StepGuard = null;
    if (self.parallel_guest_execution) execution_guard = self.guest_execution_gate.enterStep();
    defer {
        if (execution_guard) |*guard| guard.unlock();
    }
    // The prologue's context fields, read through one binding lookup.
    // Everything from the hook gates on reads them afresh: a shim can
    // switch the executing context.
    const step_ctx = process_impl_lifecycle.guestContextRef(self);
    const parallel_worker_slot = if (self.parallel_guest_execution)
        step_ctx.field("windows_active_guest_thread_slot").*
    else
        null;
    defer if (parallel_worker_slot) |slot| {
        if (slot < self.windows_guest_threads.len) {
            const context = &self.windows_guest_threads[slot].context;
            context.parallel_code_sample_steps +%= 1;
            if (context.parallel_code_sample_steps == 0) {
                const thread = &self.windows_guest_threads[slot];
                if (context.last_instruction_rip != 0) thread.code.sample(context.regs.rip);
                thread.spin.progress_probe_stride +%= 1;
                if (thread.spin.progress_probe_stride == 0) process_impl_lifecycle.noteGuestProgressStall(self, slot);
            }
        }
    };
    const active_tso_buffer = activeGuestTsoStoreBuffer(self);
    const prior_tso_buffer = __process_tso_memory.setActiveStoreBuffer(active_tso_buffer);
    defer _ = __process_tso_memory.setActiveStoreBuffer(prior_tso_buffer);
    // With the translator live, the next step may enter translated code,
    // which reads guest memory directly, and the host code that runs
    // between steps (the scheduler, wait wakeups, reports) reads it with
    // no buffer bound at all. Publish this step's stores before either
    // looks. Without the translator the buffer keeps its bounded
    // retirement progress across steps.
    const translated_tier_live = !self.parallel_guest_execution and self.block_jit_enabled and !self.block_jit_unavailable;
    defer if (active_tso_buffer) |buffer| {
        if (translated_tier_live) {
            if (!buffer.isEmpty()) __process_tso_memory.boundary_ledger.noteFlush(.jit_entry, buffer.drain());
        } else {
            buffer.retireInstruction();
        }
    };
    const prior_coordinated_access = __process_tso_memory.setCoordinatedGuestAccess(self.parallel_guest_execution);
    defer _ = __process_tso_memory.setCoordinatedGuestAccess(prior_coordinated_access);
    // `step` is the one boundary shared by the owner loop and every
    // cooperative Windows worker. Advancing the Windows performance
    // counter here keeps Xenia's worker-owned frame limiter progressing
    // even while the owner is parked in a wait service loop.
    step_ctx.field("step_retired").* = 1;
    process_impl_instruction_decode.advanceWindowsGuestClockIn(self, step_ctx);
    // The hook checks happen before decoding so an intercepted entry
    // never becomes a translated block. Executable ranges use a box;
    // sparse compatibility entry points use exact membership so the
    // space between far-apart hooks is not treated as executable work.
    const step_rip = step_ctx.field("regs").*.rip;
    if (step_rip >= __process_SYNTHETIC_RIP_FLOOR) {
        var runtime_guard = process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
        defer runtime_guard.unlock();
        if (process_impl_guest_diagnostics.handleSyntheticRip(self)) return !process_impl_lifecycle.isTerminated(self);
        self.step_hook_box_false_positives +|= 1;
        self.step_synthetic_hook_false_positives +|= 1;
    }
    if (self.parallel_guest_execution) if (self.xbox_critical_section_hooks.at(step_rip)) |api| {
        // Xbox critical sections run Xenia's lock protocol on the guest
        // structure: an uncontended call takes no lock at all, and only
        // a waiter or a release that finds one takes the runtime lock.
        // See `handleXboxCriticalSectionExport`.
        if (process_impl_windows_sync.handleXboxCriticalSectionExport(self, api)) return !process_impl_lifecycle.isTerminated(self);
    };
    if (self.windows_fmt_probe_active or self.windows_fmt_vformat_entry == step_rip) {
        var runtime_guard = process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
        process_impl_windows_sync.noteWindowsFmtProbeInstruction(self);
        runtime_guard.unlock();
    }
    if (self.windows_stub_box.contains(step_rip)) {
        // The one lock-free import must be recognized before this
        // dispatch guard; entering the ordinary import path first would
        // already serialize every caller and erase the fast path's gain.
        if (process_impl_kernel_services.tryWindowsFastImportStub(self, step_rip)) return !process_impl_lifecycle.isTerminated(self);
        if (self.parallel_guest_execution) __ProcessInternals._import_lock_requested_ns().* = __process_concurrency.monotonicNanoseconds();
        defer __ProcessInternals._import_lock_requested_ns().* = 0;
        var runtime_guard = process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
        defer runtime_guard.unlock();
        if (process_impl_kernel_services.handleWindowsImportStub(self)) return !process_impl_lifecycle.isTerminated(self);
        self.step_hook_box_false_positives +|= 1;
        self.step_windows_stub_false_positives +|= 1;
    }
    if (self.windows_utf8_count_entry == step_rip) {
        // This address is an observer, not a replacement. Run its bounded
        // read-only probe, then let the normal decode/JIT path execute the
        // original xe::utf8::count body without calling this a false hit.
        var runtime_guard = process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
        defer runtime_guard.unlock();
        if (__process_x64_linux_runtime.tryWindowsGuestCompatibility(self)) return !process_impl_lifecycle.isTerminated(self);
    } else if (self.windows_cxa_throw_entry == step_rip) {
        // __cxa_throw is observed before its original guest body runs.
        // Keep it out of false-positive accounting so the observer does
        // not turn every exception into a synthetic interpreter fallback.
        var runtime_guard = process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
        defer runtime_guard.unlock();
        if (__process_x64_linux_runtime.tryWindowsGuestCompatibility(self)) return !process_impl_lifecycle.isTerminated(self);
    } else if (self.windows_compat_hook_points.contains(step_rip)) {
        var runtime_guard = process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
        defer runtime_guard.unlock();
        if (__process_x64_linux_runtime.tryWindowsGuestCompatibility(self)) return !process_impl_lifecycle.isTerminated(self);
        self.step_hook_box_false_positives +|= 1;
        self.step_windows_compat_hook_false_positives +|= 1;
    }
    // The second tier: a translated block for this RIP, or a count
    // towards one. Past the hooks above on purpose, so an address they
    // own is never the start of a block.
    // Every executor reaches the translator: a parallel worker translates
    // into its own state (`parallelWorkerBlockJit`), so no thread frees,
    // evicts or links a block another is running. Workers used to be
    // interpreted, every instruction, because the one table was shared.
    if (self.block_jit_enabled and !self.block_jit_unavailable) {
        // Translated blocks use eager, ordered host stores. Drain this
        // executor's interpreted stores before entering them so their
        // direct memory loads observe the same state as guest loads.
        __process_tso_memory.flushActiveStoreBufferFor(.jit_entry);
        // Each executor's block table and code arena are its own. A guest
        // code write publishes its bytes before advancing the shared
        // source generation, so blocks can invalidate on re-entry without
        // freeing a block another executor may still be running. The
        // parallel TLB is executor-local; ordered invalidation retires its
        // tags, while misses use the coordinated memory helper. The owner
        // no longer stops the world on every block boundary.
        // A spin capture interprets its thread: translated loads never
        // reach the read path the capture listens on.
        const capturing = self.spin_capture_threads.load(.monotonic) != 0 and process_impl_lifecycle.spinCaptureStep(self);
        if (!capturing) {
            if (runBlockJit(self)) |continued| return continued;
        }
    }
    const decoded = process_impl_instruction_decode.decodeAt(self) orelse {
        if (process_impl_lifecycle.isTerminated(self)) return false;
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = if (process_impl_lifecycle.guestContextField(self, "decode_failure_is_invalid_control_target").*)
            .invalid_control_flow_target
        else
            .decode_failed;
        process_impl_lifecycle.markTerminated(self);
        return false;
    };
    if (self.trace_string_memory) {
        switch (process_impl_lifecycle.guestContextField(self, "regs").*.rip) {
            0x14011b6f0 => {
                const haystack_view = process_impl_lifecycle.guestContextField(self, "regs").*.rcx;
                const needle_view = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
                const haystack_length = process_impl_guest_memory.read64(self, haystack_view);
                const haystack_data = process_impl_guest_memory.read64(self, haystack_view +| 8);
                const needle_length = process_impl_guest_memory.read64(self, needle_view);
                const needle_data = process_impl_guest_memory.read64(self, needle_view +| 8);
                __process_log.info("PE utf8 find_any_of entry haystack_view=0x{x} data=0x{x} length={d} bytes={any} needle_view=0x{x} data=0x{x} length={d} bytes={any}", .{
                    haystack_view,
                    haystack_data,
                    haystack_length,
                    if (haystack_length == 0) &[_]u8{} else process_impl_execution.guestMemoryConst(self, haystack_data, @min(haystack_length, 64)) orelse &[_]u8{},
                    needle_view,
                    needle_data,
                    needle_length,
                    if (needle_length == 0) &[_]u8{} else process_impl_execution.guestMemoryConst(self, needle_data, @min(needle_length, 64)) orelse &[_]u8{},
                });
            },
            0x140134c80 => {
                const view = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
                const length = process_impl_guest_memory.read64(self, view);
                const data = process_impl_guest_memory.read64(self, view +| 8);
                const preview_len: usize = @intCast(@min(length, 64));
                __process_log.info("PE EscapeString entry result=0x{x} view=0x{x} data=0x{x} length={d} bytes={any}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                    view,
                    data,
                    length,
                    if (preview_len == 0) &[_]u8{} else process_impl_execution.guestMemoryConst(self, data, preview_len) orelse &[_]u8{},
                });
            },
            0x140134cc9,
            0x140134d06,
            0x140134e33,
            => __process_log.info("PE EscapeString find_any_of return rip=0x{x} result=0x{x}", .{ process_impl_lifecycle.guestContextField(self, "regs").*.rip, process_impl_lifecycle.guestContextField(self, "regs").*.rax }),
            0x140134e5a => {
                const view = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
                const length = process_impl_guest_memory.read64(self, view);
                const data = process_impl_guest_memory.read64(self, view +| 8);
                __process_log.info("PE EscapeString escape-basic call view=0x{x} data=0x{x} length={d} bytes={any}", .{
                    view,
                    data,
                    length,
                    if (length == 0) &[_]u8{} else process_impl_execution.guestMemoryConst(self, data, @min(length, 64)) orelse &[_]u8{},
                });
            },
            0x140134f6d => {
                const view = process_impl_lifecycle.guestContextField(self, "regs").*.rdi;
                const length = process_impl_guest_memory.read64(self, view);
                const data = process_impl_guest_memory.read64(self, view +| 8);
                __process_log.info("PE EscapeString plain-string path view=0x{x} data=0x{x} length={d} bytes={any}", .{
                    view,
                    data,
                    length,
                    if (length == 0) &[_]u8{} else process_impl_execution.guestMemoryConst(self, data, @min(length, 64)) orelse &[_]u8{},
                });
            },
            else => {},
        }
    }
    if (decoded.op == .invalid) {
        // Through the code mappings as well as the image: Xenia's JIT
        // cache is a mapping, and the 2026-09-14 fault at 0xa0535c03
        // printed `bytes={ }` because only the image was read.
        var fetched_bytes: [16]u8 = undefined;
        const opcode_bytes = process_impl_instruction_decode.guestInstructionBytes(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &fetched_bytes);
        var fault_symbol_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        const fault_slot_plus_one: u8 = if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*) |slot| @intCast(@min(slot + 1, 255)) else 0;
        // Name the opcode-map slot, not just the bytes.  Hand-decoding a
        // VEX prefix to find out which instruction is missing is the slow
        // part of acting on this fault, and the coordinates printed here
        // are the same ones the decoder's opcode census reports, so the
        // gap can be looked up directly.
        var encoding_buffer: [96]u8 = undefined;
        __process_log.err("invalid instruction at rip=0x{x} ({s}) thread={s}: encoding={s} bytes={any}; this opcode slot has no decoder entry -- see ISA/decoding/coverage.zig for the census of what does, and if the address is generated code, add the form to the Xenia JIT corpus (tools/gen_xenia_jit_corpus.py)", .{
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip, &fault_symbol_text),
            process_impl_guest_diagnostics.guestThreadLabel(self, fault_slot_plus_one),
            __process_x64_decoder.coverage.describeEncoding(&encoding_buffer, opcode_bytes),
            opcode_bytes,
        });
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .invalid_instruction;
        process_impl_lifecycle.markTerminated(self);
        return false;
    }
    process_impl_lifecycle.guestContextField(self, "last_decoded_op").* = decoded.op;
    process_impl_lifecycle.guestContextField(self, "last_decoded_len").* = decoded.len;
    process_impl_kernel_services.recordTrace(self, decoded);
    const stack_rsp_before = process_impl_lifecycle.guestContextField(self, "regs").*.rsp;
    const stack_rip_before = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    defer if (process_impl_lifecycle.guestContextField(self, "regs").*.rsp < __process_STACK_COLLAPSE_FLOOR and stack_rsp_before >= __process_STACK_COLLAPSE_FLOOR) {
        process_impl_kernel_services.noteStackPointerCollapse(self, "interpreter", stack_rsp_before, stack_rip_before, @tagName(decoded.op));
    };
    if (self.trace_formatter and process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x1400ccf50 and
        (self.trace_formatter_address == null or self.trace_formatter_address.? == process_impl_lifecycle.guestContextField(self, "regs").*.r8))
    {
        const appender = process_impl_lifecycle.guestContextField(self, "regs").*.r8;
        __process_log.info("formatter entry appender=0x{x} caller=0x{x} data=0x{x} offset=0x{x} end=0x{x} callback=0x{x} rsp=0x{x} thread=0x{x}", .{
            appender,
            process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
            process_impl_guest_memory.read64(self, appender),
            process_impl_guest_memory.read64(self, appender +| 8),
            process_impl_guest_memory.read64(self, appender +| 0x10),
            process_impl_guest_memory.read64(self, appender +| 0x18),
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
        });
    }
    // A Windows process can block before its message loop exists.  The
    // bundled Xenia runtime does exactly that: the creating thread enters
    // an internal pthread_spin_lock while the newly-created worker is
    // expected to initialize the shared state and release the lock.  A
    // single cooperative interpreter must service that worker at the
    // architectural PAUSE wait point; waiting for GetMessage here would
    // deadlock the process before any UI or Vulkan import is reachable.
    const is_pause = decoded.op == .nop and decoded.len == 2 and
        process_impl_guest_memory.read8(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip) == 0xF3 and process_impl_guest_memory.read8(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip +| 1) == 0x90;
    const worker_service_due = if (self.parallel_guest_execution)
        if (self.windows_last_service_owner_step) |last|
            process_impl_lifecycle.observedExecutionSteps(self) >= last +| __process_WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE
        else
            true
    else if (self.windows_last_service_owner_step) |last|
        process_impl_lifecycle.observedExecutionSteps(self) >= last +| __process_WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE
    else
        true;
    if (is_pause and self.windows_runtime_enabled and
        process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* == null and worker_service_due and
        (self.parallel_guest_execution or process_impl_windows_sync.nextWindowsGuestThread(self) != null))
    {
        _ = process_impl_windows_sync.serviceWindowsGuestThreads(self, __process_WINDOWS_GUEST_THREAD_SERVICE_SLICE);
        if (process_impl_lifecycle.isTerminated(self)) return false;
    }
    if (is_pause) process_impl_lifecycle.noteWindowsGuestPause(self);
    const trace_this = __process_shouldTraceRip(self, process_impl_lifecycle.guestContextField(self, "regs").*.rip);
    if (is_pause and !trace_this) {
        // PAUSE has no architectural effect beyond advancing RIP. The
        // scheduling, spin capture, service point and trace bookkeeping
        // have already run above; skip the general interpreter's vector,
        // scalar and memory dispatch for this very hot wait instruction.
        process_impl_lifecycle.guestContextField(self, "regs").*.rip +%= decoded.len;
        process_impl_lifecycle.retireParallelPauseTail(self);
        if (process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").*) process_impl_guest_memory.raiseGuestAccessViolation(self);
        return !process_impl_lifecycle.isTerminated(self);
    }
    var trace_rip: u64 = 0;
    var trace_flags_before: u64 = 0;
    if (trace_this) {
        trace_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
        trace_flags_before = process_impl_lifecycle.guestContextField(self, "regs").*.rflags;
        __process_log.info("trace before rip=0x{x} thread=0x{x} op={s} len={d} addr=0x{x} dst={s} src={s} cond={s} rax=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} r8=0x{x} r9=0x{x} r10=0x{x} r11=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x} rsp=0x{x} ret=0x{x} rbp=0x{x} flags=0x{x}", .{
            trace_rip,
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            @tagName(decoded.op),
            decoded.len,
            decoded.addr,
            @tagName(decoded.dst_reg),
            @tagName(decoded.src_reg),
            @tagName(decoded.cond),
            process_impl_lifecycle.guestContextField(self, "regs").*.rax,
            process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsi,
            process_impl_lifecycle.guestContextField(self, "regs").*.rdi,
            process_impl_lifecycle.guestContextField(self, "regs").*.r8,
            process_impl_lifecycle.guestContextField(self, "regs").*.r9,
            process_impl_lifecycle.guestContextField(self, "regs").*.r10,
            process_impl_lifecycle.guestContextField(self, "regs").*.r11,
            process_impl_lifecycle.guestContextField(self, "regs").*.r12,
            process_impl_lifecycle.guestContextField(self, "regs").*.r13,
            process_impl_lifecycle.guestContextField(self, "regs").*.r14,
            process_impl_lifecycle.guestContextField(self, "regs").*.r15,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
            process_impl_lifecycle.guestContextField(self, "regs").*.rbp,
            process_impl_lifecycle.guestContextField(self, "regs").*.rflags,
        });
        // Xenia's Xbyak emitter materializes an Address displacement in
        // a stack object before passing it through CodeGenerator::mov.
        // Keep this narrowly keyed to the compiled PushStackpoint store
        // so an opt-in RIP trace can distinguish a bad guest store from
        // a later vector/address-object corruption without adding normal
        // run noise.
        if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x140b18098 and decoded.op == .mov_mem64_imm32) {
            __process_log.info("trace Xbyak displacement store before address=0x{x} value=0x{x} immediate=0x{x} rsp=0x{x}", .{
                decoded.addr,
                process_impl_guest_memory.read64(self, decoded.addr),
                decoded.imm,
                process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            });
        }
        // ImDrawList::PushClipRect receives two ImVec2 pointers in rdx
        // and r8.  The invalid 1280,720,1280,720 rectangle is present in
        // the guest-owned clip stack, so capture these inputs at the
        // function boundary before any vector instruction can transform
        // them.  This keeps the diagnosis honest: bad inputs identify a
        // caller/window-geometry problem, while good inputs move the
        // investigation into Rosette's VEX/SSE semantics.
        if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x140419fc0) {
            const min_bytes = process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.rdx, 8);
            const max_bytes = process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.r8, 8);
            const current_clip = process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.rcx +| 96, 16);
            const min_x_bits: u32 = if (min_bytes) |bytes| __process_std.mem.readInt(u32, bytes[0..4], .little) else 0;
            const min_y_bits: u32 = if (min_bytes) |bytes| __process_std.mem.readInt(u32, bytes[4..8], .little) else 0;
            const max_x_bits: u32 = if (max_bytes) |bytes| __process_std.mem.readInt(u32, bytes[0..4], .little) else 0;
            const max_y_bits: u32 = if (max_bytes) |bytes| __process_std.mem.readInt(u32, bytes[4..8], .little) else 0;
            __process_log.info("trace PushClipRect args this=0x{x} min=0x{x} readable={} ({d},{d}) max=0x{x} readable={} ({d},{d}) intersect={} current_clip_addr=0x{x} current_clip={any}", .{
                process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
                min_bytes != null,
                @as(f32, @bitCast(min_x_bits)),
                @as(f32, @bitCast(min_y_bits)),
                process_impl_lifecycle.guestContextField(self, "regs").*.r8,
                max_bytes != null,
                @as(f32, @bitCast(max_x_bits)),
                @as(f32, @bitCast(max_y_bits)),
                @as(u8, @truncate(process_impl_lifecycle.guestContextField(self, "regs").*.r9)) != 0,
                process_impl_lifecycle.guestContextField(self, "regs").*.rcx +| 96,
                current_clip orelse &[_]u8{},
            });
            // In ImGuiWindow, these fields are the position/size state
            // consumed by Begin() while it builds OuterRectClipped and
            // the local clip vectors.  Keep them beside the call inputs
            // so a bad window rectangle can be attributed to the state
            // producer instead of guessed from the final ImDrawCmd.
            const viewport = process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x40);
            __process_log.info("trace PushClipRect window window=0x{x} pos={any} size={any} size_full={any} outer_rect_clipped={any} inner_rect={any} inner_clip_rect={any} work_rect={any} clip={any} draw_list=0x{x}", .{
                process_impl_lifecycle.guestContextField(self, "regs").*.r14,
                process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x58, 8) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x60, 8) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x68, 8) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x258, 16) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x268, 16) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x278, 16) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x288, 16) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x2a8, 16) orelse &[_]u8{},
                process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.r14 +| 0x318),
            });
            __process_log.info("trace PushClipRect viewport viewport=0x{x} pos={any} size={any} work_pos={any} work_size={any} dpi={any} flags={any}", .{
                viewport,
                process_impl_execution.guestMemoryConst(self, viewport +| 8, 8) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, viewport +| 0x10, 8) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, viewport +| 0x18, 8) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, viewport +| 0x20, 8) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, viewport +| 0x28, 4) orelse &[_]u8{},
                process_impl_execution.guestMemoryConst(self, viewport +| 4, 4) orelse &[_]u8{},
            });
        }
        if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x1405b953e) {
            const address_object = process_impl_lifecycle.guestContextField(self, "regs").*.rsi;
            __process_log.info("trace Xbyak opAddr displacement read before address_object=0x{x} displacement_address=0x{x} value=0x{x} bytes={any}", .{
                address_object,
                address_object +| 0x20,
                process_impl_guest_memory.read64(self, address_object +| 0x20),
                process_impl_execution.guestMemoryConst(self, address_object, 0x28) orelse &[_]u8{},
            });
        }
        if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x1405b9980) {
            const regexp_object = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
            __process_log.info("trace Xbyak setSIB displacement read before regexp=0x{x} displacement_address=0x{x} value=0x{x} bytes={any}", .{
                regexp_object,
                regexp_object +| 0x18,
                process_impl_guest_memory.read64(self, regexp_object +| 0x18),
                process_impl_execution.guestMemoryConst(self, regexp_object, 0x20) orelse &[_]u8{},
            });
        }
        if (self.trace_vector) {
            switch (decoded.op) {
                .vcvtss2sd,
                .vcvtsi2sd_xmm_reg,
                .vcvtsi2sd_xmm_mem,
                .vdivsd,
                .vucomisd,
                => __process_log.info("trace scalar-sse rip=0x{x} op={s} xmm0=0x{x} xmm1=0x{x} xmm2=0x{x} xmm3=0x{x} xmm4=0x{x} xmm5=0x{x} xmm6=0x{x} xmm7=0x{x}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    @tagName(decoded.op),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[0][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[1][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[2][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[3][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[4][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[5][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[6][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[7][0..8], .little),
                }),
                else => {},
            }
            if ((process_impl_lifecycle.guestContextField(self, "regs").*.rip >= 0x14048ae80 and process_impl_lifecycle.guestContextField(self, "regs").*.rip <= 0x14048ae96) or
                (process_impl_lifecycle.guestContextField(self, "regs").*.rip >= 0x14048b10c and process_impl_lifecycle.guestContextField(self, "regs").*.rip <= 0x14048b119))
            {
                __process_log.info("trace ImGui rect-vector before rip=0x{x} op={s} xmm0={any} xmm1={any} xmm2={any} xmm3={any} xmm7={any} mem={any}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    @tagName(decoded.op),
                    process_impl_lifecycle.guestContextField(self, "xmm").*[0],
                    process_impl_lifecycle.guestContextField(self, "xmm").*[1],
                    process_impl_lifecycle.guestContextField(self, "xmm").*[2],
                    process_impl_lifecycle.guestContextField(self, "xmm").*[3],
                    process_impl_lifecycle.guestContextField(self, "xmm").*[7],
                    process_impl_execution.guestMemoryConst(self, decoded.addr, 16) orelse &[_]u8{},
                });
            }
        }
        if (self.trace_utf8) {
            // This is intentionally opt-in and lives behind the existing
            // RIP trace gate.  The Windows PE uses the same utfcpp
            // helpers for xe::to_utf16. The Windows libstdc++ ABI stores
            // a string_view as {length, data}; logging it in the more
            // familiar {data, length} order produces a convincing but
            // completely false multi-gigabyte input diagnosis.
            if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x14011f930) {
                const current = process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rcx);
                const end = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
                const remaining = if (end >= current) end - current else 0;
                const preview_len: usize = @intCast(@min(remaining, 32));
                __process_log.info("trace utf8::next iterator=0x{x} current=0x{x} end=0x{x} remaining={d} bytes={any}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
                    current,
                    end,
                    remaining,
                    if (preview_len == 0) &[_]u8{} else process_impl_execution.guestMemoryConst(self, current, preview_len) orelse &[_]u8{},
                });
            } else if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x1401307a0) {
                const source_view = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
                const length = process_impl_guest_memory.read64(self, source_view);
                const source = process_impl_guest_memory.read64(self, source_view +| 8);
                const preview_len: usize = @intCast(@min(length, 64));
                __process_log.info("trace threading::set_name view=0x{x} source=0x{x} length={d} bytes={any}", .{
                    source_view,
                    source,
                    length,
                    if (preview_len == 0) &[_]u8{} else process_impl_execution.guestMemoryConst(self, source, preview_len) orelse &[_]u8{},
                });
            } else if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x140122950) {
                const source_view = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
                const length = process_impl_guest_memory.read64(self, source_view);
                const source = process_impl_guest_memory.read64(self, source_view +| 8);
                const preview_len: usize = @intCast(@min(length, 64));
                __process_log.info("trace xe::to_utf16 source_view=0x{x} source=0x{x} length={d} bytes={any}", .{
                    source_view,
                    source,
                    length,
                    if (preview_len == 0) &[_]u8{} else process_impl_execution.guestMemoryConst(self, source, preview_len) orelse &[_]u8{},
                });
            }
        }
        switch (decoded.op) {
            .cmp_mem32_imm8 => {
                __process_log.info("trace memory rip=0x{x} op=cmp_mem32_imm8 address=0x{x} value=0x{x} immediate=0x{x}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    decoded.addr,
                    process_impl_execution.readMemVal(self, decoded.addr, .bits32),
                    decoded.imm,
                });
                // The PE probe currently reaches libstdc++'s regex
                // compiler.  Its scanner is embedded immediately after
                // the compiler object; include its state only under the
                // existing RIP trace gate so a token mismatch can be
                // attributed without adding normal-run noise.
                const scanner = process_impl_lifecycle.guestContextField(self, "regs").*.rsi +| 8;
                const current = process_impl_guest_memory.read64(self, scanner +| 0xb0);
                const end = process_impl_guest_memory.read64(self, scanner +| 0xb8);
                const remaining = if (end >= current) end - current else 0;
                const preview_len: usize = @intCast(@min(remaining, 16));
                __process_log.info("trace regex scanner scanner=0x{x} state=0x{x} token=0x{x} current=0x{x} end=0x{x} remaining={d} next=0x{x} preview={any}", .{
                    scanner,
                    process_impl_guest_memory.read32(self, scanner +| 0x88),
                    process_impl_guest_memory.read32(self, scanner +| 0x90),
                    current,
                    end,
                    remaining,
                    process_impl_guest_memory.read8(self, current),
                    if (preview_len == 0) &[_]u8{} else process_impl_execution.guestMemoryConst(self, current, preview_len) orelse &[_]u8{},
                });
            },
            .mov_reg32_mem32 => {
                __process_log.info("trace 32-bit memory-load address=0x{x} bytes={any}", .{
                    decoded.addr,
                    process_impl_execution.guestMemoryConst(self, decoded.addr, 80) orelse &[_]u8{},
                });
            },
            else => {},
        }
        switch (decoded.op) {
            .vmovups_xmm_mem,
            .vmovups_ymm_mem,
            .vmovaps_xmm_mem,
            .vmovaps_ymm_mem,
            => {
                const width: usize = if (decoded.vector_256) 32 else 16;
                __process_log.info("trace vector-load address=0x{x} width={d} xmm_dst={d} xmm_src={d} legacy_sse={} bytes={any}", .{
                    decoded.addr,
                    width,
                    decoded.xmm_dst,
                    decoded.xmm_src,
                    decoded.legacy_sse,
                    process_impl_execution.guestMemoryConst(self, decoded.addr, width) orelse &[_]u8{},
                });
            },
            else => {},
        }
    }
    __process_x64_interpreter.execute(self, decoded);
    // The fault is raised here, at the boundary, rather than from inside
    // the memory access: the instruction has finished, so the CONTEXT
    // handed to the guest describes a consistent machine.
    if (process_impl_lifecycle.guestContextField(self, "guest_access_violation_pending").*) process_impl_guest_memory.raiseGuestAccessViolation(self);
    if (trace_this) {
        __process_log.info("trace transition rip=0x{x} next_rip=0x{x} op={s} len={d} thread=0x{x} addr=0x{x} cond={s} flags_before=0x{x} flags_after=0x{x}", .{
            trace_rip,
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            @tagName(decoded.op),
            decoded.len,
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            decoded.addr,
            @tagName(decoded.cond),
            trace_flags_before,
            process_impl_lifecycle.guestContextField(self, "regs").*.rflags,
        });
        if (decoded.op == .mov_mem8_reg8 and process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x14011f219) {
            const source_value = process_impl_execution.decodedRegVal(self, decoded.src_reg, decoded.src_high8, .bits8);
            __process_log.info("trace byte-store rip=0x{x} address=0x{x} src={s} high8={} source=0x{x} stored=0x{x} rdi=0x{x} r13=0x{x}", .{
                process_impl_lifecycle.guestContextField(self, "regs").*.rip -| decoded.len,
                decoded.addr,
                @tagName(decoded.src_reg),
                decoded.src_high8,
                source_value,
                process_impl_guest_memory.read8(self, decoded.addr),
                process_impl_lifecycle.guestContextField(self, "regs").*.rdi,
                process_impl_lifecycle.guestContextField(self, "regs").*.r13,
            });
        }
        __process_log.info("trace after  rip=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} r8=0x{x} r9=0x{x} r10=0x{x} r11=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x} rsp=0x{x} rbp=0x{x} flags=0x{x}", .{
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            process_impl_lifecycle.guestContextField(self, "regs").*.rax,
            process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsi,
            process_impl_lifecycle.guestContextField(self, "regs").*.rdi,
            process_impl_lifecycle.guestContextField(self, "regs").*.r8,
            process_impl_lifecycle.guestContextField(self, "regs").*.r9,
            process_impl_lifecycle.guestContextField(self, "regs").*.r10,
            process_impl_lifecycle.guestContextField(self, "regs").*.r11,
            process_impl_lifecycle.guestContextField(self, "regs").*.r12,
            process_impl_lifecycle.guestContextField(self, "regs").*.r13,
            process_impl_lifecycle.guestContextField(self, "regs").*.r14,
            process_impl_lifecycle.guestContextField(self, "regs").*.r15,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            process_impl_lifecycle.guestContextField(self, "regs").*.rbp,
            process_impl_lifecycle.guestContextField(self, "regs").*.rflags,
        });
        if (process_impl_lifecycle.guestContextField(self, "regs").*.rip == 0x140b180a1 and decoded.op == .mov_mem64_imm32) {
            const displacement_address = process_impl_lifecycle.guestContextField(self, "regs").*.rsp +| 0x60;
            __process_log.info("trace Xbyak displacement store after address=0x{x} value=0x{x} expected=0x130 rsp=0x{x}", .{
                displacement_address,
                process_impl_guest_memory.read64(self, displacement_address),
                process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            });
        }
        if (self.trace_vector) {
            switch (decoded.op) {
                .vcvtss2sd,
                .vcvtsi2sd_xmm_reg,
                .vcvtsi2sd_xmm_mem,
                .vdivsd,
                .vucomisd,
                => __process_log.info("trace scalar-sse after rip=0x{x} op={s} xmm0=0x{x} xmm1=0x{x} xmm2=0x{x} xmm3=0x{x} xmm4=0x{x} xmm5=0x{x} xmm6=0x{x} xmm7=0x{x} flags=0x{x}", .{
                    process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                    @tagName(decoded.op),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[0][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[1][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[2][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[3][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[4][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[5][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[6][0..8], .little),
                    __process_std.mem.readInt(u64, process_impl_lifecycle.guestContextField(self, "xmm").*[7][0..8], .little),
                    process_impl_lifecycle.guestContextField(self, "regs").*.rflags,
                }),
                else => {},
            }
            if ((trace_rip >= 0x14048ae80 and trace_rip <= 0x14048ae96) or
                (trace_rip >= 0x14048b10c and trace_rip <= 0x14048b119))
            {
                __process_log.info("trace ImGui rect-vector after rip=0x{x} op={s} xmm0={any} xmm1={any} xmm2={any} xmm3={any} xmm7={any} mem={any}", .{
                    trace_rip,
                    @tagName(decoded.op),
                    process_impl_lifecycle.guestContextField(self, "xmm").*[0],
                    process_impl_lifecycle.guestContextField(self, "xmm").*[1],
                    process_impl_lifecycle.guestContextField(self, "xmm").*[2],
                    process_impl_lifecycle.guestContextField(self, "xmm").*[3],
                    process_impl_lifecycle.guestContextField(self, "xmm").*[7],
                    process_impl_execution.guestMemoryConst(self, decoded.addr, 16) orelse &[_]u8{},
                });
            }
        }
        switch (decoded.op) {
            .vmovups_mem_xmm,
            .vmovups_mem_ymm,
            .vmovaps_mem_xmm,
            .vmovaps_mem_ymm,
            => {
                const width: usize = if (decoded.vector_256) 32 else 16;
                __process_log.info("trace vector-store address=0x{x} width={d} xmm_dst={d} xmm_src={d} legacy_sse={} bytes={any}", .{
                    decoded.addr,
                    width,
                    decoded.xmm_dst,
                    decoded.xmm_src,
                    decoded.legacy_sse,
                    process_impl_execution.guestMemoryConst(self, decoded.addr, width) orelse &[_]u8{},
                });
            },
            else => {},
        }
    }
    return !process_impl_lifecycle.isTerminated(self);
}
