const std = @import("std");
const x64_decoder = @import("x64_decoder");
const RegId = x64_decoder.RegId;
const Regs = x64_decoder.Regs;
const DecodedInsn = x64_decoder.DecodedInsn;
const Size = x64_decoder.OperandSize;
const compat_runtime = @import("macho_compat_runtime");
const exit_diagnostics = @import("exit_diagnostics");
const libcpp_shared_control_block = @import("cxx_abi").libcpp_shared_control_block;
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const constants = @import("../../Mach-O/constants.zig");
const TRACE_BUFFER_LEN = constants.TRACE_BUFFER_LEN;
const UNSUPPORTED_RUNTIME_EXIT_CODE = constants.UNSUPPORTED_RUNTIME_EXIT_CODE;
const types = @import("../../Mach-O/types.zig");
const TraceEntry = types.TraceEntry;
const ControlTransferContext = types.ControlTransferContext;
const decoder = @import("../../Mach-O/decoder.zig");
const decodeInsn = decoder.decodeInsn;
const scheduler = @import("scheduler");

pub const NearNullBaseTransition = struct {
    object_address: u64,
    previous_value: u64,
    producer_rip: u64,
    distance: usize,
};

fn traceRegisterValue(entry: TraceEntry, register: RegId) u64 {
    return switch (@intFromEnum(register)) {
        0 => entry.rax,
        1 => entry.rcx,
        2 => entry.rdx,
        3 => entry.rbx,
        4 => entry.rsp,
        5 => entry.rbp,
        6 => entry.rsi,
        7 => entry.rdi,
        8 => entry.r8,
        9 => entry.r9,
        10 => entry.r10,
        11 => entry.r11,
        12 => entry.r12,
        13 => entry.r13,
        14 => entry.r14,
        15 => entry.r15,
    };
}

pub fn isXModuleMatchesSymbol(symbol: []const u8) bool {
    return std.mem.indexOf(u8, symbol, "XModule") != null and
        std.mem.indexOf(u8, symbol, "Matches") != null;
}

pub fn terminateForUnresolvedImport(self: anytype) void {
    self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
    self.terminated = true;
}

pub fn recoverLibcppSharedControlBlockCall(
    self: anytype,
    instruction_address: u64,
    operand_address: u64,
) ?u64 {
    const caller = self.metadata.nearestSymbol(instruction_address) orelse return null;
    const object = self.regs.rdi;
    const object_bytes = self.guestMemoryConst(object, 3 * @sizeOf(u64));
    const vtable_symbol = self.internal_targets.libcpp_atomic_bool_control_block_vtable;
    const address_point = std.math.add(
        u64,
        vtable_symbol,
        libcpp_shared_control_block.vtable_address_point_offset,
    ) catch 0;
    const slot_address = std.math.add(
        u64,
        address_point,
        libcpp_shared_control_block.on_zero_shared_slot_offset,
    ) catch 0;
    const vtable_mapped = vtable_symbol != 0 and self.guestMemoryConst(vtable_symbol, 5 * @sizeOf(u64)) != null;
    const slot_target = if (vtable_mapped) self.read64(slot_address) else 0;
    const decision = libcpp_shared_control_block.assess(.{
        .operation = "call_mem64",
        .caller_symbol = caller.name,
        .operand_address = operand_address,
        .object_address = object,
        .current_vptr = if (object_bytes != null) self.read64(object) else 0,
        .strong_count = if (object_bytes != null) self.read64(object + 8) else 0,
        .weak_count = if (object_bytes != null) self.read64(object + 16) else 0,
        .vtable_symbol_address = vtable_symbol,
        .slot_target = slot_target,
        .object_mapped = object_bytes != null,
        .vtable_mapped = vtable_mapped,
        .target_executable = self.isExecutableAddress(slot_target),
    });
    self.libcpp_shared_control_blocks.record(decision);
    switch (decision) {
        .not_applicable => return null,
        .rejected => |reason| {
            machoCapturePrint(
                "macho-processor: libc++ shared control-block recovery rejected: object=0x{x} operand=0x{x} vptr=0x{x} strong=0x{x} weak=0x{x} reason={s}\n",
                .{
                    object,
                    operand_address,
                    if (object_bytes != null) self.read64(object) else 0,
                    if (object_bytes != null) self.read64(object + 8) else 0,
                    if (object_bytes != null) self.read64(object + 16) else 0,
                    reason,
                },
            );
            return null;
        },
        .recover => |recovery| {
            self.write64(object, recovery.address_point);
            machoCapturePrint(
                "macho-processor: libc++ shared control-block vptr restored: object=0x{x} vtable_symbol=0x{x} address_point=0x{x} slot=0x{x} target=0x{x} strong=0x{x} weak=0x{x} caller={s}+0x{x}; continuing verified __on_zero_shared dispatch\n",
                .{
                    object,
                    vtable_symbol,
                    recovery.address_point,
                    recovery.slot_address,
                    recovery.target,
                    self.read64(object + 8),
                    self.read64(object + 16),
                    caller.name,
                    caller.offset,
                },
            );
            return recovery.target;
        },
    }
}

pub fn findNearNullBaseTransition(self: anytype, register: RegId, terminal_value: u64) ?NearNullBaseTransition {
    const count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
    if (count < 2) return null;

    var skipped_current = false;
    const after = terminal_value;
    var same_thread_distance: usize = 0;
    var reverse_index = count;
    while (reverse_index != 0) {
        reverse_index -= 1;
        const index = if (self.trace_filled)
            (self.trace_index + reverse_index) % TRACE_BUFFER_LEN
        else
            reverse_index;
        const entry = self.trace_entries[index];
        if (entry.thread_handle != self.active_guest_thread) continue;

        if (!skipped_current) {
            if (entry.rip != self.regs.rip) return null;
            skipped_current = true;
            continue;
        }

        same_thread_distance += 1;
        const before = traceRegisterValue(entry, register);
        if (before == after) continue;
        if (before == 0) return null;

        const producer = self.decodeTraceInstruction(entry) orelse return null;
        if (producer.op != .mov_reg64_mem64 or producer.dst_reg != register) return null;
        const source = self.guestMemoryConst(producer.addr, @sizeOf(u64)) orelse return null;
        if (std.mem.readInt(u64, source[0..8], .little) != 0) return null;

        return .{
            .object_address = producer.addr,
            .previous_value = before,
            .producer_rip = entry.rip,
            .distance = same_thread_distance,
        };
    }
    return null;
}

pub fn ensureXmoduleVtable(self: anytype) ?u64 {
    const real = self.internal_targets.xmodule_vtable;
    if (real != 0) {
        if (self.guestMemoryConst(real + 0x28, @sizeOf(u64))) |slot| {
            const target = std.mem.readInt(u64, slot[0..8], .little);
            if (target != 0 and
                (self.isExecutableAddress(target) or
                    compat_runtime.syntheticThunk(target) != null or
                    self.metadata.importAtStub(target) != null))
            {
                return real;
            }
        }
    }

    if (self.internal_targets.xmodule_synthetic_vtable == 0) {
        const vtable_mem = self.guestAlloc(256, 16) orelse return null;
        const bytes = self.guestMemory(vtable_mem, 256) orelse return null;
        @memset(bytes, 0);
        const get_name = compat_runtime.thunkAddress(.xmodule_get_name);
        var i: u8 = 0;
        while (i < 32) : (i += 1) {
            self.write64(vtable_mem + @as(u64, i) * 8, get_name);
        }
        self.internal_targets.xmodule_synthetic_vtable = vtable_mem;

        const empty = self.guestAlloc(1, 1) orelse return null;
        const empty_bytes = self.guestMemory(empty, 1) orelse return null;
        empty_bytes[0] = 0;
        self.internal_targets.xmodule_empty_string = empty;
    }
    return self.internal_targets.xmodule_synthetic_vtable;
}

pub fn recoverNearNullBaseRegister(self: anytype, d: *DecodedInsn) bool {
    if (!d.sib_has_base or d.has_0x67) return false;

    const base_register = d.sib_base_reg;
    const base_value = self.regVal(base_register, .bits64);
    if (base_value >= 0x1000 or (base_value & 0x8000_0000_0000_0000) != 0) return false;
    if (d.addr >= 0x1000 and (d.addr & 0x8000_0000_0000_0000) == 0) return false;
    if (self.guestMemoryConst(d.addr, @sizeOf(u64)) != null) return false;

    const symbol = self.metadata.nearestSymbol(self.regs.rip) orelse return false;
    if (!isXModuleMatchesSymbol(symbol.name)) return false;

    const transition = self.findNearNullBaseTransition(base_register, base_value) orelse return false;
    if (transition.object_address != self.regs.rdi or
        self.guestMemoryConst(transition.object_address, @sizeOf(u64)) == null or
        self.read64(transition.object_address) != 0)
    {
        return false;
    }

    const resolved_vtable = self.ensureXmoduleVtable() orelse return false;
    self.write64(transition.object_address, resolved_vtable);
    self.setReg(base_register, .bits64, resolved_vtable);
    d.addr = d.addr -% base_value +% resolved_vtable;
    machoCapturePrint(
        "macho-processor: near-null base register recovery: thread=0x{x} register={s} before=0x{x} after=0x0 object=0x{x} vtable=0x{x} producer=0x{x} distance={d} fault_rip=0x{x} symbol={s}+0x{x} action=restore_vptr_and_retry_load\n",
        .{ self.active_guest_thread, @tagName(base_register), transition.previous_value, transition.object_address, resolved_vtable, transition.producer_rip, transition.distance, self.regs.rip, symbol.name, symbol.offset },
    );
    return true;
}

pub fn recoverNullVtableSlot(self: anytype, instruction_address: u64, operand_address: u64) ?u64 {
    const caller = self.metadata.nearestSymbol(instruction_address) orelse return null;
    if (std.mem.indexOf(u8, caller.name, "codecvt") == null and
        std.mem.indexOf(u8, caller.name, "__narrow_to_utf8") == null) return null;
    for (self.metadata.imports) |imported| {
        if (std.mem.indexOf(u8, imported.name, "codecvt") == null) continue;
        if (imported.stub_address == 0) continue;
        if (std.mem.indexOf(u8, imported.name, "do_in") != null) {
            _ = self.write64(operand_address, imported.stub_address);
            machoCapturePrint(
                "macho-processor: null vtable slot repair: instruction=0x{x} operand=0x{x} func=do_in stub=0x{x}\n",
                .{ instruction_address, operand_address, imported.stub_address },
            );
            return imported.stub_address;
        }
    }
    machoCapturePrint(
        "macho-processor: codecvt virtual dispatch unresolved: instruction=0x{x} operand=0x{x} caller={s}+0x{x} required=do_in action=reject_abi_unsafe_fallback\n",
        .{ instruction_address, operand_address, caller.name, caller.offset },
    );
    return null;
}

pub fn terminateForInvalidControlTransfer(self: anytype, context: ControlTransferContext) void {
    var failure = exit_diagnostics.ControlTransferFailure{
        .kind = context.kind,
        .instruction_address = context.instruction_address,
        .operand_address = context.operand_address,
        .target_address = context.target_address,
        .return_address = context.return_address,
        .operand_mapped = context.operand_address != 0 and self.addrToOffset(context.operand_address) != null,
        .target_mapped = self.addrToOffset(context.target_address) != null,
        .target_executable = self.isExecutableAddress(context.target_address),
    };
    if (self.guestMemoryConst(context.instruction_address, 16)) |bytes| {
        const byte_count: usize = @min(bytes.len, failure.instruction_bytes.len);
        @memcpy(failure.instruction_bytes[0..byte_count], bytes[0..byte_count]);
        failure.instruction_byte_count = @intCast(byte_count);
        const decoded = decodeInsn(bytes[0..byte_count]);
        failure.decoded_operation = @tagName(decoded.op);
        failure.decoded_length = decoded.len;
    }
    if (context.operand_address != 0) {
        if (self.guestMemoryConst(context.operand_address, 8)) |_| {
            failure.operand_value = self.read64(context.operand_address);
        }
    }
    if (self.metadata.nearestSymbol(context.instruction_address)) |caller| {
        failure.caller_symbol = caller.name;
        failure.caller_offset = caller.offset;
    }
    if (self.metadata.nearestSymbol(context.target_address)) |target| {
        failure.target_symbol = target.name;
        failure.target_offset = target.offset;
    }
    for (self.metadata.imports) |imported| {
        if (imported.stub_address == context.instruction_address or
            (context.operand_address != 0 and imported.lazy_pointer_address == context.operand_address))
        {
            failure.candidate_import = imported.name;
            failure.candidate_image = imported.dylib;
            break;
        }
    }
    self.pending_control_transfer = null;
    self.terminal_control_transfer = failure;
    machoCapturePrint(
        "macho-processor: invalid control transfer: kind={s} instruction=0x{x} operand=0x{x} target=0x{x} return=0x{x} candidate_import={s}\n",
        .{
            failure.kind,
            failure.instruction_address,
            failure.operand_address,
            failure.target_address,
            failure.return_address,
            if (failure.candidate_import.len != 0) failure.candidate_import else "<none>",
        },
    );
    if (failure.instruction_byte_count != 0) {
        machoCapturePrint(
            "macho-processor: transfer decode: op={s} len={d} bytes={any} indirect=[0x{x}]=0x{x} mapped={} executable={} import_image={s}\n",
            .{
                failure.decoded_operation,
                failure.decoded_length,
                failure.instruction_bytes[0..failure.instruction_byte_count],
                failure.operand_address,
                failure.operand_value,
                failure.target_mapped,
                failure.target_executable,
                if (failure.candidate_image.len != 0) failure.candidate_image else "<none>",
            },
        );
    }
    logCrashDiagnostics(self, context);
    self.faulted = true;
    self.exit_code = 127;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
    self.terminated = true;
}

pub fn logCrashDiagnostics(self: anytype, context: ControlTransferContext) void {
    machoCapturePrint("macho-processor: CRASH DIAGNOSTICS BEGIN\n", .{});

    const thread_handle = self.active_guest_thread;
    const thread_id = self.threadNumericId(thread_handle);
    const thread_role = self.threadRole(thread_handle, self.regs.rip);
    machoCapturePrint(
        "macho-processor:   thread: handle=0x{x} numeric_id={d} role={s} rip=0x{x} rsp=0x{x} rbp=0x{x}\n",
        .{ thread_handle, thread_id, thread_role, self.regs.rip, self.regs.rsp, self.regs.rbp },
    );

    machoCapturePrint(
        "macho-processor:   regs: rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x}\n" ++ "macho-processor:         rsi=0x{x} rdi=0x{x} rbp=0x{x} rsp=0x{x}\n" ++ "macho-processor:         r8=0x{x}  r9=0x{x}  r10=0x{x} r11=0x{x}\n" ++ "macho-processor:         r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x}\n" ++ "macho-processor:         rip=0x{x} rflags=0x{x}\n",
        .{
            self.regs.rax, self.regs.rbx,    self.regs.rcx, self.regs.rdx,
            self.regs.rsi, self.regs.rdi,    self.regs.rbp, self.regs.rsp,
            self.regs.r8,  self.regs.r9,     self.regs.r10, self.regs.r11,
            self.regs.r12, self.regs.r13,    self.regs.r14, self.regs.r15,
            self.regs.rip, self.regs.rflags,
        },
    );

    {
        const insn_bytes = self.guestMemoryConst(context.instruction_address, 16);
        if (insn_bytes) |bytes| {
            const dec = decodeInsn(bytes[0..@min(bytes.len, 15)]);
            const addrmode = if (dec.rip_relative)
                "rip_relative"
            else if (dec.sib_has_index)
                "sib_indexed"
            else
                "direct";
            const dst_reg = @tagName(dec.dst_reg);
            machoCapturePrint(
                "macho-processor:   instr decode: op={s} addr_mode={s} addr=0x{x} dst_reg={s}\n",
                .{ @tagName(dec.op), addrmode, dec.addr, dst_reg },
            );
            if (dec.sib_has_index) {
                const idx_reg = @tagName(dec.sib_index_reg);
                const base_reg = if (dec.sib_has_base) @tagName(dec.sib_base_reg) else "none";
                machoCapturePrint(
                    "macho-processor:     sib: index={s} scale={d} base={s}\n",
                    .{ idx_reg, dec.sib_scale, base_reg },
                );
            }
        }
    }

    if (context.operand_address != 0) {
        const op_offset = self.addrToOffset(context.operand_address);
        const op_mapped = op_offset != null;
        if (op_mapped) {
            const op_sym = self.metadata.nearestSymbol(context.operand_address);
            const op_value = self.read64(context.operand_address);
            machoCapturePrint(
                "macho-processor:   operand 0x{x}: mapped=yes offset=0x{x} value=0x{x}\n",
                .{ context.operand_address, op_offset.?, op_value },
            );
            if (op_sym) |s| {
                const stale = if (s.offset > 1024) " (STALE MATCH: offset > 1024)" else "";
                machoCapturePrint(
                    "macho-processor:   nearest symbol: {s}+0x{x}{s}\n",
                    .{ s.name, s.offset, stale },
                );
            }
        } else {
            machoCapturePrint(
                "macho-processor:   operand 0x{x}: mapped=no offset=<none>\n",
                .{context.operand_address},
            );
        }

        {
            var found_seg = false;
            for (self.segments) |seg| {
                if (context.operand_address >= seg.vmaddr and context.operand_address < seg.vmaddr + seg.vmsize) {
                    const rel_off = context.operand_address - seg.vmaddr;
                    machoCapturePrint(
                        "macho-processor:   address region: Mach-O segment {s} [0x{x}-0x{x}] offset_in_segment=0x{x} prot=",
                        .{ seg.name, seg.vmaddr, seg.vmaddr + seg.vmsize - 1, rel_off },
                    );
                    if (seg.initprot & 1 != 0) {
                        machoCapturePrint("r", .{});
                    } else {
                        machoCapturePrint("-", .{});
                    }
                    if (seg.initprot & 2 != 0) {
                        machoCapturePrint("w", .{});
                    } else {
                        machoCapturePrint("-", .{});
                    }
                    if (seg.initprot & 4 != 0) {
                        machoCapturePrint("x", .{});
                    } else {
                        machoCapturePrint("-", .{});
                    }
                    machoCapturePrint("\n", .{});
                    found_seg = true;
                    break;
                }
            }
            if (!found_seg) {
                const in_sparse = self.sparse_memory.contains(context.operand_address, 8);
                machoCapturePrint(
                    "macho-processor:   address region: outside Mach-O segments sparse_mapped={}\n",
                    .{in_sparse},
                );
            }
        }

        machoCapturePrint("macho-processor:   jump table dump [0x{x} +/- 64 bytes]:\n", .{context.operand_address});
        const dump_start = context.operand_address -| 64;
        const dump_end = context.operand_address + 72;
        var dump_addr = dump_start;
        while (dump_addr < dump_end) : (dump_addr += 8) {
            const marker = if (dump_addr == context.operand_address) " <-- OPERAND" else "";
            if (self.addrToOffset(dump_addr)) |_| {
                const val = self.read64(dump_addr);
                const val_sym = self.metadata.nearestSymbol(val);
                machoCapturePrint(
                    "macho-processor:     [0x{x}]=0x{x}{s}",
                    .{ dump_addr, val, marker },
                );
                if (val_sym) |s| {
                    machoCapturePrint(" {s}+0x{x}", .{ s.name, s.offset });
                }
                machoCapturePrint("\n", .{});
            } else {
                machoCapturePrint("macho-processor:     [0x{x}]=<unmapped>{s}\n", .{ dump_addr, marker });
            }
        }

        {
            var hi32_const: ?u32 = null;
            var hi32_all_same = true;
            var lo32_prev: ?u32 = null;
            var lo32_step: ?i64 = null;
            var lo32_arith_prog = true;
            var lo32_counts: u32 = 0;
            var lo32_all_small = true;

            var scan_addr = context.operand_address -| 64;
            const scan_end = context.operand_address + 72;
            while (scan_addr < scan_end) : (scan_addr += 8) {
                if (self.addrToOffset(scan_addr) == null) continue;
                const val = self.read64(scan_addr);
                if (val == 0) continue;
                const hi32 = @as(u32, @truncate(val >> 32));
                const lo32 = @as(u32, @truncate(val));
                lo32_counts += 1;
                if (lo32 >= 0x1000000000) lo32_all_small = false;

                if (hi32_const) |h| {
                    if (h != hi32) hi32_all_same = false;
                } else {
                    hi32_const = hi32;
                }

                if (lo32_prev) |p| {
                    const diff = @as(i64, lo32) - @as(i64, p);
                    if (lo32_step) |known_step| {
                        if (diff != known_step) lo32_arith_prog = false;
                    } else {
                        lo32_step = diff;
                    }
                }
                lo32_prev = lo32;
            }

            if (lo32_counts > 1 and hi32_const != null and hi32_all_same) {
                const hi = hi32_const.?;
                machoCapturePrint(
                    "macho-processor:   corruption pattern: all entries have constant high 32 bits = 0x{x}",
                    .{hi},
                );
                if (hi == 0xfffffc00) {
                    machoCapturePrint(" (kernel-space range, possible sign-extended 32-bit address)\n", .{});
                } else if (hi == 0x00000000) {
                    machoCapturePrint(" (entries are valid 32-bit addresses in low 4GB)\n", .{});
                } else if (hi == 0xffffffff) {
                    machoCapturePrint(" (possible -1 / invalid pattern)\n", .{});
                } else if (hi == 0x00007fff) {
                    machoCapturePrint(" (possible userspace address on macOS)\n", .{});
                } else {
                    machoCapturePrint("\n", .{});
                }

                machoCapturePrint("macho-processor:   interpreting as 32-bit pointer table:\n", .{});
                scan_addr = context.operand_address -| 64;
                while (scan_addr < scan_end) : (scan_addr += 8) {
                    if (self.addrToOffset(scan_addr) == null) continue;
                    const val = self.read64(scan_addr);
                    if (val == 0) continue;
                    const lo32 = @as(u32, @truncate(val));
                    const lo_sym = self.metadata.nearestSymbol(lo32);
                    const lo_small = if (lo32 < 0x1000) " (looks like a small offset, not a pointer)" else "";
                    if (lo_sym) |s| {
                        machoCapturePrint(
                            "macho-processor:     0x{x} -> 0x{x} (lo32) {s}+0x{x}{s}\n",
                            .{ scan_addr, lo32, s.name, s.offset, lo_small },
                        );
                    } else {
                        machoCapturePrint(
                            "macho-processor:     0x{x} -> 0x{x} (lo32){s}\n",
                            .{ scan_addr, lo32, lo_small },
                        );
                    }
                }
            }

            if (lo32_counts > 1 and lo32_arith_prog and lo32_step != null) {
                const step_val = lo32_step.?;
                machoCapturePrint(
                    "macho-processor:   corruption pattern: lo32 entries form arithmetic progression (step={d}, decreasing={}). Table was shifted by one entry (read as wrong-type entries).\n",
                    .{ @abs(step_val), step_val < 0 },
                );
            }

            if (lo32_counts > 1 and lo32_all_small) {
                machoCapturePrint(
                    "macho-processor:   corruption pattern: all lo32 values are small (< 4GB). Entries may be 32-bit offsets, not addresses.\n",
                    .{},
                );
            }
        }
    }

    if (self.suspended_guest_thread_count > 0) {
        machoCapturePrint("macho-processor:   suspended threads ({d}):\n", .{self.suspended_guest_thread_count});
        for (self.suspended_guest_threads[0..self.suspended_guest_thread_count], 0..) |st, i| {
            const st_sym = self.metadata.nearestSymbol(st.regs.rip);
            machoCapturePrint(
                "macho-processor:     [{d}] handle=0x{x} rip=0x{x} rsp=0x{x} reason={s} suspended_step={d}",
                .{ i, st.handle, st.regs.rip, st.regs.rsp, st.reason, st.suspended_step },
            );
            if (st_sym) |s| {
                machoCapturePrint(" {s}+0x{x}", .{ s.name, s.offset });
            }
            machoCapturePrint("\n", .{});
        }
    }

    machoCapturePrint("macho-processor:   guest backtrace (rbp chain):\n", .{});
    var frame_rbp = self.regs.rbp;
    var frame_rip = self.regs.rip;
    var frame_depth: usize = 0;
    while (frame_depth < 16) : (frame_depth += 1) {
        const frame_sym = self.metadata.nearestSymbol(frame_rip);
        machoCapturePrint(
            "macho-processor:     #{d} rip=0x{x} rbp=0x{x}",
            .{ frame_depth, frame_rip, frame_rbp },
        );
        if (frame_sym) |s| {
            machoCapturePrint(" {s}+0x{x}", .{ s.name, s.offset });
        }
        machoCapturePrint("\n", .{});
        if (frame_rbp == 0 or self.addrToOffset(frame_rbp) == null) break;
        const next_rbp = self.read64(frame_rbp);
        const next_rip_offset = frame_rbp + 8;
        if (next_rbp == 0 or next_rbp <= frame_rbp) {
            if (self.addrToOffset(next_rip_offset) != null) {
                frame_rip = self.read64(next_rip_offset);
                break;
            }
            break;
        }
        if (self.addrToOffset(next_rip_offset) == null) break;
        frame_rip = self.read64(next_rip_offset);
        frame_rbp = next_rbp;
    }

    machoCapturePrint(
        "macho-processor:   scheduler: active=0x{x} suspended={d} switches={d} returns={d}" ++ " wait_yields={d} quantum_yields={d} rotation_yields={d}" ++ " preserved_resumes={d} wait_resumes={d} self_resumes={d}" ++ " quiescence_recoveries={d} starvation_warnings={d}\n",
        .{
            self.active_guest_thread,
            self.suspended_guest_thread_count,
            self.cooperative_thread_switches,
            self.cooperative_thread_returns,
            self.cooperative_wait_yields,
            self.cooperative_quantum_yields,
            self.cooperative_rotation_yields,
            self.cooperative_preserved_register_resumes,
            self.cooperative_wait_result_resumes,
            self.cooperative_self_resumes,
            self.cooperative_quiescence_recoveries,
            self.cooperative_starvation_warnings,
        },
    );
    machoCapturePrint("macho-processor: CRASH DIAGNOSTICS END\n", .{});
}
