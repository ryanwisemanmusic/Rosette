//! Initializer dispatch, transaction tracking, and vector pre-population.
//! Extracted from MachOState (process.zig) to reduce file size.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const x64_decoder = @import("x64_decoder");
const Regs = x64_decoder.Regs;
const exit_diagnostics = @import("exit_diagnostics");
const initialization_resolution = @import("init").initialization_engine;
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const export_table_lifecycle = @import("dyld").export_table_lifecycle;

const types = @import("macho_core").types;
const InitializerRunOutcome = types.InitializerRunOutcome;

const constants = @import("macho_core").constants;
const INITIALIZER_RETURN_SENTINEL = constants.INITIALIZER_RETURN_SENTINEL;
const INITIALIZER_STEP_LIMIT = constants.INITIALIZER_STEP_LIMIT;
const UNSUPPORTED_RUNTIME_EXIT_CODE = constants.UNSUPPORTED_RUNTIME_EXIT_CODE;

pub fn initializerAbi(self: anytype) initialization_resolution.AbiSnapshot {
    return .{
        .rsp = self.regs.rsp,
        .rbx = self.regs.rbx,
        .rbp = self.regs.rbp,
        .r12 = self.regs.r12,
        .r13 = self.regs.r13,
        .r14 = self.regs.r14,
        .r15 = self.regs.r15,
    };
}

pub fn beginInitializerTransaction(self: anytype) void {
    self.initializer_memory.begin();
    self.initializer_checkpoint = .{
        .heap_next = self.heap_next,
        .compat = self.compat,
        .monotonic_nanoseconds = self.guest_time.now(),
        .ios_xalloc_next = self.ios_xalloc_next,
        .cxxopts_split_accelerations = self.cxxopts_split_accelerations,
        .guest_errno_address = self.guest_errno_address,
    };
}

pub fn rollbackInitializerTransaction(self: anytype) bool {
    const checkpoint = self.initializer_checkpoint orelse return false;
    const complete = self.initializer_memory.rollback(self.mem);
    self.heap_next = checkpoint.heap_next;
    self.compat = checkpoint.compat;
    self.guest_time.restoreMonotonic(checkpoint.monotonic_nanoseconds);
    self.ios_xalloc_next = checkpoint.ios_xalloc_next;
    self.cxxopts_split_accelerations = checkpoint.cxxopts_split_accelerations;
    self.guest_errno_address = checkpoint.guest_errno_address;
    self.initializer_checkpoint = null;
    return complete;
}

pub fn commitInitializerTransaction(self: anytype) bool {
    if (self.initializer_checkpoint == null) return false;
    self.initializer_checkpoint = null;
    return self.initializer_memory.commit();
}

pub fn runOneInitializer(self: anytype, launch_regs: Regs, index: usize, is_retry: bool) InitializerRunOutcome {
    if (self.consumeHostTerminationRequest()) return .failed;
    const address = self.metadata.initializer_addresses[index];
    const nearest_symbol = self.metadata.nearestSymbol(address);
    const symbol_name = if (nearest_symbol) |symbol| symbol.name else "<unknown>";
    self.regs = launch_regs;
    self.initializer_abort_requested = false;
    self.initializer_abort_reason = .none;
    // Clear the guard tracker for a fresh initializer run
    self.guard_rollback.reset();

    if (is_retry) {
        if (!self.initializer_resolver.retry(
            index,
            self.initializerAbi(),
            self.unresolved_import_count,
            self.guest_assertion_count,
        )) return .failed;
    } else {
        if (!self.initializer_resolver.begin(
            index,
            address,
            symbol_name,
            self.initializerAbi(),
            self.unresolved_import_count,
            self.guest_assertion_count,
        )) {
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.initializer_transaction_failure);
            self.terminated = true;
            return .failed;
        }
    }

    self.beginInitializerTransaction();

    if (!self.isExecutableAddress(address)) {
        machoCapturePrint(
            "macho-processor: initializer [{d}/{d}] has invalid target 0x{x}\n",
            .{ index + 1, self.metadata.initializer_addresses.len, address },
        );
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        self.terminated = true;
        _ = self.rollbackInitializerTransaction();
        self.initializer_resolver.fail(
            .invalid_target,
            0,
            self.initializerAbi(),
            self.unresolved_import_count,
            self.guest_assertion_count,
        );
        return .failed;
    }

    // Log vtable state at start of each attempt so we can correlate
    // write-protection recoveries across retries of the same initializer.
    // N7 (perf audit): gated behind initializer_detail_logging — the 722
    // per-initializer lines flooded the run log (~700K chars) for a detail
    // that is only useful when diagnosing write-protection recoveries.
    if (self.initializer_detail_logging) {
        machoCapturePrint(
            "macho-processor: running initializer [{d}/{d}] {s}+0x{x} vtable(write_protections={d} recoveries={d} detections={d} guards={d})\n",
            .{
                index + 1,
                self.metadata.initializer_addresses.len,
                symbol_name,
                if (nearest_symbol) |item| item.offset else address,
                self.vtable_tracker.live_vtable_write_protections,
                self.vtable_tracker.live_vtable_guard_recoveries,
                self.vtable_tracker.heap_corruption_detections,
                self.guard_rollback.count(),
            },
        );
    }

    self.push(INITIALIZER_RETURN_SENTINEL);
    self.regs.rip = address;

    var steps: u64 = 0;
    var next_host_termination_poll: u64 = 500_000;
    while (!self.terminated and !self.initializer_abort_requested and
        self.regs.rip != INITIALIZER_RETURN_SENTINEL and steps < INITIALIZER_STEP_LIMIT) : (steps +|= 1)
    {
        next_host_termination_poll -|= 1;
        if (next_host_termination_poll == 0) {
            next_host_termination_poll = 500_000;
            if (self.consumeHostTerminationRequest()) break;
        }
        if (!self.step()) break;
    }
    if (self.initializer_abort_requested) {
        const final_abi = self.initializerAbi();
        const deferral_reason = self.initializer_abort_reason;
        const deferral_attempt = if (self.initializer_resolver.current()) |record| record.attempts else 0;
        if (!self.rollbackInitializerTransaction()) {
            self.initializer_resolver.fail(
                .transaction_failed,
                steps,
                final_abi,
                self.unresolved_import_count,
                self.guest_assertion_count,
            );
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.initializer_transaction_failure);
            self.terminated = true;
            return .failed;
        }
        // Clear all __cxa_guard variables acquired during this initializer run
        // so the retry starts from a clean initialization state.
        {
            const cleared_count = self.guard_rollback.clearAndReset(self, struct {
                fn writeByte(ctx: *anyopaque, addr: u64, off: u64, val: u8) bool {
                    const StatePtr = @TypeOf(self);
                    const st: StatePtr = @ptrCast(@alignCast(ctx));
                    if (st.guestMemory(addr, 8)) |bytes| {
                        bytes[@as(usize, @intCast(off))] = val;
                        return true;
                    }
                    return false;
                }
            }.writeByte);
            if (cleared_count > 0) {
                machoCapturePrint(
                    "macho-processor: initializer [{d}/{d}] cleared {d} guard(s) on deferral vtable(protections={d} recoveries={d} detections={d})\n",
                    .{
                        index + 1,
                        self.metadata.initializer_addresses.len,
                        cleared_count,
                        self.vtable_tracker.live_vtable_write_protections,
                        self.vtable_tracker.live_vtable_guard_recoveries,
                        self.vtable_tracker.heap_corruption_detections,
                    },
                );
            }
        }

        // Flush log before deferring the initializer so diagnostics
        // from guard clearing are captured even if the process crashes.
        macho_log.checkPointSync();

        self.initializer_resolver.deferCurrent(
            steps,
            final_abi,
            self.unresolved_import_count,
            self.guest_assertion_count,
            deferral_reason,
        );
        self.initializer_abort_requested = false;
        self.initializer_abort_reason = .none;

        if (deferral_reason != .runtime_dependency or deferral_attempt <= 1) {
            machoCapturePrint(
                "macho-processor: deferred initializer [{d}/{d}] {s} reason={s}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, symbol_name, @tagName(deferral_reason) },
            );
        }
        return .deferred;
    }
    if (self.terminated) {
        const final_abi = self.initializerAbi();
        const crash_symbol = self.metadata.nearestSymbol(self.regs.rip);
        machoCapturePrint(
            "macho-processor: initializer [{d}/{d}] terminated at rip=0x{x} symbol={s}+0x{x} reason={s} exit_code=0x{x} vtable(protections={d} recoveries={d} detections={d})\n",
            .{
                index + 1,
                self.metadata.initializer_addresses.len,
                self.regs.rip,
                if (crash_symbol) |s| s.name else "<unknown>",
                if (crash_symbol) |s| s.offset else @as(i64, 0),
                @tagName(exit_diagnostics.reasonFromValue(self.termination_reason)),
                self.exit_code,
                self.vtable_tracker.live_vtable_write_protections,
                self.vtable_tracker.live_vtable_guard_recoveries,
                self.vtable_tracker.heap_corruption_detections,
            },
        );
        macho_log.checkPointSync();
        self.dumpRecentTrace();
        _ = self.rollbackInitializerTransaction();
        self.initializer_resolver.fail(
            .terminated,
            steps,
            final_abi,
            self.unresolved_import_count,
            self.guest_assertion_count,
        );
        machoCapturePrint(
            "macho-processor: initializer [{d}/{d}] failed at {s}+0x{x}\n",
            .{ index + 1, self.metadata.initializer_addresses.len, symbol_name, if (nearest_symbol) |item| item.offset else address },
        );
        return .failed;
    }
    if (self.regs.rip != INITIALIZER_RETURN_SENTINEL) {
        const final_abi = self.initializerAbi();
        machoCapturePrint(
            "macho-processor: initializer [{d}/{d}] exceeded {d} steps at {s}+0x{x}; terminal_rip=0x{x}\n",
            .{ index + 1, self.metadata.initializer_addresses.len, INITIALIZER_STEP_LIMIT, symbol_name, if (nearest_symbol) |item| item.offset else address, self.regs.rip },
        );
        macho_log.checkPointSync();
        self.dumpRecentTrace();
        _ = self.rollbackInitializerTransaction();
        // Clear all __cxa_guard variables acquired during this initializer run
        // so the retry starts from a clean initialization state.
        {
            const cleared_count = self.guard_rollback.clearAndReset(self, struct {
                fn writeByte(ctx: *anyopaque, addr: u64, off: u64, val: u8) bool {
                    const StatePtr = @TypeOf(self);
                    const st: StatePtr = @ptrCast(@alignCast(ctx));
                    if (st.guestMemory(addr, 8)) |bytes| {
                        bytes[@as(usize, @intCast(off))] = val;
                        return true;
                    }
                    return false;
                }
            }.writeByte);
            if (cleared_count > 0) {
                machoCapturePrint(
                    "macho-processor: initializer [{d}/{d}] cleared {d} guard(s) on deferral\n",
                    .{ index + 1, self.metadata.initializer_addresses.len, cleared_count },
                );
            }
        }
        self.initializer_resolver.deferCurrent(
            steps,
            final_abi,
            self.unresolved_import_count,
            self.guest_assertion_count,
            .step_limit,
        );
        machoCapturePrint(
            "macho-processor: deferred initializer [{d}/{d}] {s} after step limit vtable(protections={d} recoveries={d} detections={d})\n",
            .{
                index + 1,
                self.metadata.initializer_addresses.len,
                symbol_name,
                self.vtable_tracker.live_vtable_write_protections,
                self.vtable_tracker.live_vtable_guard_recoveries,
                self.vtable_tracker.heap_corruption_detections,
            },
        );
        return .deferred;
    }

    const final_abi = self.initializerAbi();
    if (!self.commitInitializerTransaction()) {
        self.initializer_resolver.fail(
            .transaction_failed,
            steps,
            final_abi,
            self.unresolved_import_count,
            self.guest_assertion_count,
        );
        self.faulted = true;
        self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.initializer_transaction_failure);
        self.terminated = true;
        return .failed;
    }

    const degraded_before = self.initializer_resolver.degraded;
    self.initializer_resolver.finish(
        steps,
        final_abi,
        self.unresolved_import_count,
        self.guest_assertion_count,
    );
    if (self.strict_initializers and self.initializer_resolver.degraded != degraded_before) {
        machoCapturePrint(
            "macho-processor: strict initializer mode rejected [{d}/{d}] {s}\n",
            .{ index + 1, self.metadata.initializer_addresses.len, symbol_name },
        );
        self.faulted = true;
        self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
        self.terminated = true;
        return .failed;
    }
    return .completed;
}

pub fn runInitializers(self: anytype) bool {
    if (self.metadata.initializer_addresses.len == 0) return true;

    const launch_regs = self.regs;
    self.export_table_lc.enterPhase(.initializers_in_progress);

    var pending: std.ArrayList(usize) = .empty;
    defer pending.deinit(self.allocator);
    var next_pending: std.ArrayList(usize) = .empty;
    defer next_pending.deinit(self.allocator);

    for (self.metadata.initializer_addresses, 0..) |_, index| {
        switch (self.runOneInitializer(launch_regs, index, false)) {
            .completed => {},
            .deferred => pending.append(self.allocator, index) catch return false,
            .failed => return false,
        }
        if ((index + 1) % 50 == 0 or index + 1 == self.metadata.initializer_addresses.len) {
            // N7 (perf audit): the progress line stays (one write per 50
            // initializers) but the 3× fsync per checkpoint is dropped — the
            // log is buffered by the OS and failure/deferral paths below still
            // checkpoint explicitly before returning.
            machoCapturePrint(
                "macho-processor: processed initializer {d}/{d}\n",
                .{ index + 1, self.metadata.initializer_addresses.len },
            );
        }
    }

    self.export_table_lc.enterPhase(.exports_resolved);

    if (pending.items.len != 0) {
        var growth_buf: [4]export_table_lifecycle.VectorGrowthRequest = undefined;
        const growth_count = self.export_table_lc.popGrowthRequests(&growth_buf);
        if (growth_count > 0) {
            machoCapturePrint(
                "macho-processor: pre-populating {d} export vector(s) before retry pass\n",
                .{growth_count},
            );
        }
        for (growth_buf[0..growth_count]) |req| {
            const var_name = std.mem.sliceTo(&req.variable_name, 0);
            const current_size = if (self.guestMemoryConst(req.vector_address, 16) != null)
                self.read32(req.vector_address)
            else
                0;
            machoCapturePrint(
                "macho-processor:   pre-populating vector={s} at 0x{x} current_size={d} needed_size={d} element_size={d}\n",
                .{ var_name, req.vector_address, current_size, req.needed_size, req.element_size },
            );
            if (current_size >= req.needed_size) {
                machoCapturePrint(
                    "macho-processor:   vector already has enough entries ({d} >= {d}); skipping growth\n",
                    .{ current_size, req.needed_size },
                );
                continue;
            }
            if (current_size > 0) {
                machoCapturePrint(
                    "macho-processor:   vector has {d} entries but needs {d}; growing\n",
                    .{ current_size, req.needed_size },
                );
            }
            const dummy_item = self.memory_forwarder.allocate(self, req.element_size, 16) orelse {
                machoCapturePrint(
                    "macho-processor:   failed to allocate dummy item for vector pre-population\n",
                    .{},
                );
                continue;
            };
            {
                const slice = self.guestMemory(dummy_item, req.element_size) orelse {
                    machoCapturePrint(
                        "macho-processor:   dummy item memory not writable after allocation\n",
                        .{},
                    );
                    continue;
                };
                @memset(slice, 0);
            }
            const item_addr = dummy_item;
            var append_count: u32 = 0;
            while (self.read32(req.vector_address) < req.needed_size) {
                if (!self.appendTrivialVector(req.vector_address, item_addr, req.element_size, req.needed_size)) {
                    machoCapturePrint(
                        "macho-processor:   appendTrivialVector failed after {d} appends\n",
                        .{append_count},
                    );
                    break;
                }
                append_count += 1;
            }
            machoCapturePrint(
                "macho-processor:   vector pre-population: appended {d} entries, new size={d}\n",
                .{ append_count, self.read32(req.vector_address) },
            );
        }
    }

    var retry_round: u8 = 0;
    while (pending.items.len != 0 and retry_round < 3) : (retry_round += 1) {
        self.export_table_lc.retry_pass = retry_round + 1;
        machoCapturePrint(
            "macho-processor: retrying {d} deferred initializer(s), pass {d}\n",
            .{ pending.items.len, retry_round + 1 },
        );
        for (pending.items) |index| {
            switch (self.runOneInitializer(launch_regs, index, true)) {
                .completed => {},
                .deferred => next_pending.append(self.allocator, index) catch return false,
                .failed => return false,
            }
        }
        self.export_table_lc.onRetryPass(retry_round + 1);
        pending.clearRetainingCapacity();
        std.mem.swap(std.ArrayList(usize), &pending, &next_pending);
    }

    if (pending.items.len != 0) {
        machoCapturePrint(
            "macho-processor: {d} initializer(s) remained deferred after 3 retry passes\n",
            .{pending.items.len},
        );
        self.faulted = true;
        self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
        self.terminated = true;
        return false;
    }

    self.regs = launch_regs;
    return true;
}

pub fn appendTrivialVector(self: anytype, vector: u64, item: u64, element_size: u64, minimum_capacity: u32) bool {
    const header_size: u64 = 16;
    if (element_size == 0 or self.guestMemory(vector, header_size) == null or self.guestMemoryConst(item, element_size) == null) {
        const bad_address = if (self.guestMemory(vector, header_size) == null) vector else item;
        self.terminateForGuestAccess(bad_address, @intCast(@min(@max(element_size, header_size), std.math.maxInt(u8))), .read, "trivial_vector_push_back");
        return false;
    }

    const size = self.read32(vector);
    var capacity = self.read32(vector + 4);
    var data = self.read64(vector + 8);
    const storage_is_valid = data != 0 and capacity >= size and
        self.guestMemoryConst(data, @as(u64, capacity) * element_size) != null;

    // A non-empty vector without backing storage cannot be repaired without
    // inventing missing elements. Stop at the violated invariant instead
    // of allowing a later near-null dereference to obscure the cause.
    if (size != 0 and !storage_is_valid) {
        self.terminateForGuestAccess(data, @intCast(@min(element_size, std.math.maxInt(u8))), .read, "trivial_vector_invalid_storage");
        return false;
    }

    if (!storage_is_valid or size == capacity) {
        const requested = size +| 1;
        const grown = if (capacity == 0) minimum_capacity else capacity +| capacity / 2;
        const new_capacity = @max(requested, grown);
        const allocation_size = std.math.mul(u64, new_capacity, element_size) catch {
            self.terminated = true;
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            return false;
        };
        const new_data = self.memory_forwarder.allocate(self, allocation_size, 16) orelse {
            self.terminated = true;
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            return false;
        };
        if (size != 0) {
            const used = @as(u64, size) * element_size;
            const source = self.guestMemoryConst(data, used) orelse return false;
            const destination = self.guestMemory(new_data, used) orelse return false;
            std.mem.copyForwards(u8, destination, source);
            self.memory_forwarder.releaseFrom(data, self.regs.rip);
            self.vtable_tracker.forgetAddress(data);
        }
        data = new_data;
        capacity = new_capacity;
        self.write32(vector + 4, capacity);
        self.write64(vector + 8, data);
    }

    const destination_address = data + @as(u64, size) * element_size;
    const source = self.guestMemoryConst(item, element_size) orelse return false;
    const destination = self.guestMemory(destination_address, element_size) orelse return false;
    std.mem.copyForwards(u8, destination, source);
    self.write32(vector, size +| 1);
    return true;
}
